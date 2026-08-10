import Foundation
import Observation

/// 플레이어 상태의 메인 액터 표면. 업스트림 `CompanionStore`(한 마리·졸업·자동 진화)를 대체한다.
/// 진화는 여기서 자동으로 일어나지 않는다 — 사용자가 눌러야 한다(`PlayerStore+Evolution`).
@MainActor @Observable
final class PlayerStore {
    private(set) var state = PlayerState()

    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private var rng: any RandomNumberGenerator
    @ObservationIgnored private let now: () -> Date
    /// 봉인을 이미 쓴 기기인가를 세이브 **밖에** 적어 둔다. 세이브 안에 두면 평문으로 새로 쓴
    /// 파일에 그 표시까지 같이 적어 넣으면 그만이라 아무것도 못 걸러낸다.
    @ObservationIgnored private let defaults: UserDefaults
    static let sealedKey = "playerSaveSealed"

    init(fileURL: URL? = nil,
         rng: any RandomNumberGenerator = SystemRandomNumberGenerator(),
         now: @escaping () -> Date = Date.init,
         defaults: UserDefaults = .standard) {
        self.fileURL = fileURL ?? Self.defaultURL()
        self.rng = rng
        self.now = now
        self.defaults = defaults
        load()
    }

    static func defaultURL() -> URL {
        AppEnv.supportDirectory().appendingPathComponent("player-state.json")
    }

    // MARK: 스타터

    /// 첫 개체를 만든다. 스타터 목록 밖이거나 이미 골랐으면 nil.
    /// 스타터는 이로치가 아니다 — 첫 개체는 다시 뽑을 수 없으니 운에 맡기지 않는다.
    @discardableResult
    func chooseStarter(speciesID: Int, grade: Grade) -> Individual? {
        guard !state.starterChosen, StarterCatalog.contains(speciesID) else { return nil }
        let natures = PokemonNature.allCases
        let nature = natures[Int(rng.next() % UInt64(natures.count))]
        let individual = Individual(baseID: speciesID, speciesID: speciesID, pathIDs: [speciesID],
                                    shiny: false, nature: nature, exp: 0,
                                    obtainedAt: now(), grade: grade)
        let hadSpeedup = HatchSpeedup.present(in: state.box)
        state.box.append(individual)
        state.box[state.box.count - 1].partnerSince = now()
        state.partnerID = individual.id
        state.starterChosen = true
        state.dex.insert(speciesID)
        save()
        applyHatchSpeedupIfNewlyEarned(hadSpeedupBefore: hadSpeedup)
        return individual
    }

    /// 메뉴바 아이콘·플로팅 펫이 그릴 종. 파트너가 없으면 nil.
    var displayedSpeciesID: Int? { state.partner?.displaySpeciesID }
    var displayedIsShiny: Bool { state.partner?.showsShiny ?? false }
    /// 파트너가 메가·거다이맥스 폼이면 그 슬러그 — 메뉴바·플로팅 펫도 바뀐 모습으로 보여야 한다.
    var displayedForm: String? { state.partner?.spriteForm }

    // MARK: 언어

    var language: AppLanguage { state.language }
    func setLanguage(_ lang: AppLanguage) { mutate { $0.language = lang } }
    /// 앱 전체 UI 문자열 — language 변경 시 @Observable 로 자동 재렌더.
    var l: L { L(language) }

    // MARK: 적립

    /// 사용량 갱신 — 지갑과 파트너 경험치가 같은 델타를 먹는다(서로 깎지 않는다).
    func update(todayTokens: Int, todayDate: String, hasUsageData: Bool) {
        if !state.installBaselineSet {
            // 실제 데이터가 도착한 시점의 오늘 사용량을 기준선으로 — 설치 이전 사용분은 세지 않는다.
            guard hasUsageData else { return }
            state.installBaselineSet = true
            state.claimedTodayTokens = todayTokens
            state.lastDate = todayDate
            save()
            return
        }
        if todayDate != state.lastDate {
            state.lastDate = todayDate
            state.claimedTodayTokens = 0
        }
        // 롤오버로 오늘 총량이 0으로 재설정된 경우도 여기서 걸러진다 — 그래도 위 리셋은
        // save() 로 반드시 디스크에 반영해야 한다(로컬 장부가 메모리에만 남으면 안 된다).
        if todayTokens > state.claimedTodayTokens {
            let delta = todayTokens - state.claimedTodayTokens
            state.claimedTodayTokens = todayTokens
            state.earnedTokens += Self.currencyGain(delta, charm: state.ownsFortuneCharm)
            if let index = state.box.firstIndex(where: { $0.id == state.partnerID }) {
                state.box[index].exp += Self.expGain(delta, charm: state.ownsExpCharm)
                // 봉인 이전 세이브의 파트너에는 시작 시각이 없다 — 여기서 늦게라도 시계를 건다.
                if state.box[index].partnerSince == nil { state.box[index].partnerSince = now() }
                // 함께 쓴 토큰 기록은 부적과 무관하게 실제 쓴 만큼만 센다.
                state.box[index].partnerTokens += delta
                produceRibbonCandy(at: index, delta: delta, in: &state)
            }
        }
        save()
    }

    /// 경험치 부적을 반영한 실제 경험치 증가분. 순수 함수라 테스트로 잠근다.
    nonisolated static func expGain(_ base: Int, charm: Bool) -> Int { charm ? base * 2 : base }

    /// 행운의 부적을 반영한 재화 증가분. 정수 나눗셈이라 1.5배가 내림으로 떨어진다 —
    /// 소수 재화는 없으므로 그게 맞다.
    nonisolated static func currencyGain(_ base: Int, charm: Bool) -> Int {
        charm ? base + base / 2 : base
    }

    /// 리본을 단 파트너가 토큰을 쓴 만큼 사탕을 만든다. 진행분(`candyProgress`)을 남겨 두므로
    /// 한 번에 여러 개가 나올 수도 있고, 리본 단계가 올라 필요량이 줄어도 그동안 쌓은 건 안 버린다.
    private func produceRibbonCandy(at index: Int, delta: Int, in state: inout PlayerState) {
        guard let ribbon = state.box[index].ribbon(at: now()) else { return }
        let produced = Self.candyYield(progress: state.box[index].candyProgress + delta,
                                       per: ribbon.tokensPerCandy)
        state.box[index].candyProgress = produced.remainder
        guard produced.count > 0 else { return }
        state.inventory[ShopItem.expCandy.rawValue, default: 0] += produced.count
        // 사탕이 나온 김에 이 개체가 자기 진화에 쓸 도구도 굴린다 — 도구를 얻는 유일한 길이다.
        // 사탕 개수만큼 굴려서, 오래 안 켠 뒤 한꺼번에 정산될 때 손해 보지 않게 한다.
        // **이미 가진 것은 후보에서 뺀다** — 도구는 없어지지 않으므로 두 번째는 아무 쓸모가 없고,
        // 그대로 두면 다 모은 개체의 채집 굴림이 영원히 헛돈다. 그래서 `owned` 를 매번 다시 읽는다
        // (한 정산에서 둘이 나올 때 같은 걸 두 번 주지 않으려면 루프 안에서 갱신돼야 한다).
        let needs = ForageCatalog.needs(speciesID: state.box[index].speciesID,
                                        region: state.box[index].region)
        for _ in 0..<produced.count {
            let owned = Set(needs.filter { state.inventory[$0.rawValue] != nil })
            guard let item = Self.forage(ribbon: ribbon, needs: needs, owned: owned,
                                         roll: nextRandomUnit(),
                                         pick: nextRandomUnit()) else { continue }
            state.inventory[item.rawValue, default: 0] += 1
            state.discoveries.append(.init(itemKey: item.rawValue,
                                           speciesID: state.box[index].speciesID))
        }

        // 폼 도구는 따로 굴린다 — 확률이 다르기 때문이다(전설은 1/10). 진화 도구와 한 통에
        // 넣으면 기라티나의 백금옥이 이브이의 물의돌과 같은 값이 된다.
        let formItems = FormForageCatalog.items(speciesID: state.box[index].speciesID,
                                                region: state.box[index].region)
        for _ in 0..<produced.count {
            let missing = formItems.filter { state.inventory[$0.item.rawValue] == nil }
            guard let found = Self.forageFormItem(ribbon: ribbon, candidates: missing,
                                                  roll: nextRandomUnit(),
                                                  pick: nextRandomUnit()) else { continue }
            state.inventory[found.rawValue, default: 0] += 1
            state.discoveries.append(.init(itemKey: found.rawValue,
                                           speciesID: state.box[index].speciesID))
        }
    }

    /// 리본 파트너가 이번에 물어 온 폼 도구. 전설의 폼만 확률이 따로다.
    /// 후보에 갈래가 섞여 있으면(한 종이 전설 폼과 일반 폼을 함께 갖는 경우는 없지만)
    /// **각 후보를 자기 확률로 판정**한다 — 하나의 확률로 뭉뚱그리면 어느 쪽이든 틀린다.
    nonisolated static func forageFormItem(ribbon: Ribbon,
                                           candidates: [(item: FormItem, kind: FormKind)],
                                           roll: Double, pick: Double) -> FormItem? {
        guard !candidates.isEmpty else { return nil }
        let index = min(candidates.count - 1, max(0, Int(pick * Double(candidates.count))))
        let chosen = candidates[index]
        let permille = chosen.kind == .legendary ? ribbon.legendaryFormPermille : ribbon.foragePermille
        guard Int(roll * 1000) < permille else { return nil }
        return chosen.item
    }

    /// 리본 파트너가 이번에 물어 온 도구. `needs` 는 **그 개체가 쓸 수 있는 것만** 담기고
    /// (`ForageCatalog.needs`), 거기서 **이미 가진 것(`owned`)을 뺀 것**이 후보다.
    /// 진화에 도구가 필요 없는 종이거나 필요한 걸 다 모았으면 아무것도 안 나온다.
    /// 순수 함수라 확률 경계를 테스트로 잠근다.
    nonisolated static func forage(ribbon: Ribbon, needs: [EvolutionItem],
                                   owned: Set<EvolutionItem> = [],
                                   roll: Double, pick: Double) -> EvolutionItem? {
        let candidates = needs.filter { !owned.contains($0) }
        guard !candidates.isEmpty else { return nil }
        guard Int(roll * 1000) < ribbon.foragePermille else { return nil }
        // 갈래가 여럿이면(이브이는 돌이 다섯) 아직 없는 것 중에서 하나를 고른다.
        return candidates[min(candidates.count - 1, max(0, Int(pick * Double(candidates.count))))]
    }

    /// 쌓인 토큰 → (사탕 개수, 남은 진행분). 순수 함수라 경계를 테스트로 잠근다.
    nonisolated static func candyYield(progress: Int, per: Int) -> (count: Int, remainder: Int) {
        guard per > 0, progress > 0 else { return (0, max(0, progress)) }
        return (progress / per, progress % per)
    }

    // MARK: 박스·도감

    func setPartner(_ id: UUID) {
        guard state.box.contains(where: { $0.id == id }) else { return }
        guard id != state.partnerID else { return }   // 같은 개체를 다시 지정해도 시계를 끊지 않는다
        Self.closePartnerStint(in: &state, at: now())
        state.partnerID = id
        if let index = state.box.firstIndex(where: { $0.id == id }) {
            state.box[index].partnerSince = now()
        }
        save()
    }

    /// 알을 빨리 깨우는 아이를 **처음** 얻었으면, 진행 중인 알의 남은 시간을 절반으로 줄인다.
    ///
    /// 개체가 박스에 들어오거나 진화로 종이 바뀐 뒤에 부른다. 이미 그런 아이가 있었다면 아무 일도
    /// 없다 — 원작에서도 여러 마리는 중첩되지 않는다.
    ///
    /// **지나간 시간은 안 건드린다.** 남은 몫만 줄어드니 20분 굴린 30분짜리 알은 남은 10분이
    /// 5분이 되는 것이지, 유효 시간이 15분이 되어 이미 익어 있지는 않다.
    ///
    /// - Parameter hadSpeedupBefore: 이 개체가 들어오기 **전에** 이미 있었나. 호출부가 먼저 재서
    ///   넘긴다 — 들어온 뒤에 재면 방금 들어온 아이 때문에 항상 참이 되어 감면이 영영 안 걸린다.
    func applyHatchSpeedupIfNewlyEarned(hadSpeedupBefore: Bool) {
        guard !hadSpeedupBefore, HatchSpeedup.present(in: state.box) else { return }
        let now = currentDate()
        mutate { state in
            for index in state.eggs.indices {
                state.eggs[index].hatchesAt = HatchSpeedup.halvedRemaining(
                    hatchesAt: state.eggs[index].hatchesAt, now: now)
            }
        }
    }

    /// 파트너의 겉모습을 깨뜨린다 — 두드릴 수 있는 아이일 때만.
    /// 이미 깨져 있으면 아무 일도 없다(저장을 헛되이 다시 쓰지 않는다).
    func breakPartnerForm() {
        guard let id = state.partnerID,
              let index = state.box.firstIndex(where: { $0.id == id }),
              BrokenForm.breaks(speciesID: state.box[index].speciesID),
              !state.box[index].formBroken else { return }
        mutate { $0.box[index].formBroken = true }
    }

    /// 지금 파트너의 진행 중인 구간을 닫아 누적에 더한다. 파트너를 바꾸기 직전에 부른다 —
    /// 안 닫으면 이전 파트너의 `partnerSince` 가 남아 파트너가 아닌데도 시간이 계속 늘어난다.
    static func closePartnerStint(in state: inout PlayerState, at now: Date) {
        guard let current = state.partnerID,
              let index = state.box.firstIndex(where: { $0.id == current }),
              let since = state.box[index].partnerSince else { return }
        state.box[index].partnerSeconds += max(0, Int(now.timeIntervalSince(since)))
        state.box[index].partnerSince = nil
        // 곁에서 내려오면 깨진 겉모습이 돌아온다 — 그 아이의 배틀이 끝나는 셈이다.
        state.box[index].formBroken = false
        // 물러난 횟수가 하나 는다 — 돌핀맨의 모습이 여기서 번갈아 바뀐다.
        state.box[index].partnerStintsEnded += 1
    }

    func registerInDex(_ speciesID: Int) {
        guard !state.dex.contains(speciesID) else { return }
        state.dex.insert(speciesID)
        save()
    }

    #if DEBUG
    /// 테스트 전용 — 부화가 없는 2a 단계에서 박스에 개체를 넣는 유일한 경로.
    /// 획득 불변식(스타터 1회·카탈로그 소속·성격 굴림)을 전부 우회하므로 릴리스 빌드에서 잘라낸다.
    func addForTesting(_ individual: Individual) {
        let hadSpeedup = HatchSpeedup.present(in: state.box)
        state.box.append(individual)
        applyHatchSpeedupIfNewlyEarned(hadSpeedupBefore: hadSpeedup)
        state.dex.insert(individual.speciesID)
        save()
    }

    /// 테스트 전용 — 물어 오는 도구를 인벤토리에 직접 넣는다. 채집은 확률과 토큰 누적을
    /// 거쳐야 해서 소모 여부 같은 다른 성질을 검증할 때 준비 과정이 본론을 덮는다.
    func grantForTesting(_ item: EvolutionItem) {
        mutate { $0.inventory[item.rawValue, default: 0] += 1 }
    }

    /// 테스트 전용 — 발견 알림을 직접 넣는다. 채집은 확률과 토큰 누적을 거쳐야 해서
    /// 카드가 그려지는지만 볼 때는 준비 과정이 본론을 덮는다.
    func grantDiscoveryForTesting(_ discovery: Discovery) {
        mutate { $0.discoveries.append(discovery) }
    }

    /// 테스트 전용 — 폼 도구를 인벤토리에 직접 넣는다.
    func grantForTesting(_ item: FormItem) {
        mutate { $0.inventory[item.rawValue, default: 0] += 1 }
    }

    /// 테스트 전용 — 지갑·슬롯·알 개수를 직접 세팅한다(적립 경로를 돌리지 않고).
    func seedForTesting(wallet: Int, slots: Int, eggs: Int, at date: Date) {
        mutate {
            $0.earnedTokens = wallet
            $0.spentTokens = 0
            $0.slots = slots
            $0.eggs = (0..<eggs).map { _ in
                Egg(grade: .common, speciesID: 1, shiny: false, startedAt: date,
                    hatchesAt: date.addingTimeInterval(EggBalance.duration(.common)))
            }
        }
    }
    #endif

    // MARK: 영속

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else {
            defaults.set(true, forKey: Self.sealedKey)   // 새 세이브는 처음부터 봉인된다
            return
        }
        let outcome = Self.open(data, alreadySealedOnce: defaults.bool(forKey: Self.sealedKey))
        guard var decoded = outcome.state else {
            AppLog.write("PlayerStore: 상태 파일을 읽지 못해 새로 시작한다 — \(fileURL.lastPathComponent)")
            return
        }
        if outcome.tampered {
            AppLog.write("PlayerStore: 세이브 봉인이 맞지 않는다 — 조작 표시를 남긴다")
        }
        decoded.tampered = decoded.tampered || outcome.tampered
        state = decoded
        GameIntegrity.isTampered = state.tampered
        defaults.set(true, forKey: Self.sealedKey)
        if outcome.needsResealing { save() }
    }

    /// 파일 바이트를 상태로 여는 순수 판정. 봉인이 깨졌는지까지 함께 돌려준다.
    /// 순수 함수라 테스트가 파일시스템 없이 모든 갈래를 밟는다.
    ///
    /// - `alreadySealedOnce`: 이 기기가 이미 봉인 세이브를 쓴 적이 있나. 이 앱이 봉인을 도입하기
    ///   전에 만들어진 평문 세이브는 조작이 아니므로(그때는 그게 정상 형식이었다) 한 번은 그냥
    ///   받아들이고 봉인해 준다. 그 뒤로 평문이 다시 나타나면 누군가 새로 쓴 것이다.
    nonisolated static func open(_ data: Data,
                                 alreadySealedOnce: Bool) -> (state: PlayerState?, tampered: Bool,
                                                              needsResealing: Bool) {
        if let payload = SaveSeal.unseal(data) {
            return (try? JSONDecoder().decode(PlayerState.self, from: payload), false, false)
        }
        // 봉투인데 못 열었다 = 봉인된 본문을 손댔다. 본문을 못 읽으니 상태는 살릴 수 없다.
        if SaveSeal.looksSealed(data) {
            return (PlayerState(), true, true)
        }
        // 평문 JSON. 봉인을 쓴 적 없는 기기면 구 세이브 이전(정상), 아니면 손으로 쓴 것이다.
        guard let decoded = try? JSONDecoder().decode(PlayerState.self, from: data) else {
            return (nil, false, false)
        }
        return (decoded, alreadySealedOnce, true)
    }

    func save() {
        guard let payload = try? JSONEncoder().encode(state),
              let sealed = try? SaveSeal.seal(payload) else { return }
        try? sealed.write(to: fileURL, options: .atomic)   // 부분 쓰기 손상 방지
    }

    // MARK: 확장 진입점

    /// 확장이 상태를 바꾸는 유일한 창구. 저장까지 여기서 하므로, 바꾸고 저장을 잊는 경로가
    /// 생기지 않는다(Task 3 에서 실제로 그 경로가 나왔다).
    func mutate(_ change: (inout PlayerState) -> Void) {
        change(&state)
        save()
    }

    /// 0…1 난수. 확장(뽑기)이 주입된 rng 를 쓰는 유일한 창구.
    func nextRandomUnit() -> Double {
        Double(rng.next() % 1_000_000) / 1_000_000
    }

    /// 주입된 시계. 확장이 시각을 얻는 유일한 창구.
    func currentDate() -> Date { now() }
}
