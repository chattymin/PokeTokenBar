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

    init(fileURL: URL? = nil,
         rng: any RandomNumberGenerator = SystemRandomNumberGenerator(),
         now: @escaping () -> Date = Date.init) {
        self.fileURL = fileURL ?? Self.defaultURL()
        self.rng = rng
        self.now = now
        load()
    }

    static func defaultURL() -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PokeDexBar", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("player-state.json")
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
        state.box.append(individual)
        state.partnerID = individual.id
        state.starterChosen = true
        state.dex.insert(speciesID)
        save()
        return individual
    }

    /// 메뉴바 아이콘·플로팅 펫이 그릴 종. 파트너가 없으면 nil.
    var displayedSpeciesID: Int? { state.partner?.speciesID }
    var displayedIsShiny: Bool { state.partner?.shiny ?? false }
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
            state.earnedTokens += delta
            if let index = state.box.firstIndex(where: { $0.id == state.partnerID }) {
                state.box[index].exp += delta
            }
        }
        save()
    }

    // MARK: 박스·도감

    func setPartner(_ id: UUID) {
        guard state.box.contains(where: { $0.id == id }) else { return }
        state.partnerID = id
        save()
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
        state.box.append(individual)
        state.dex.insert(individual.speciesID)
        save()
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
        guard let data = try? Data(contentsOf: fileURL) else { return }
        guard let decoded = try? JSONDecoder().decode(PlayerState.self, from: data) else {
            AppLog.write("PlayerStore: 상태 파일을 읽지 못해 새로 시작한다 — \(fileURL.lastPathComponent)")
            return
        }
        state = decoded
    }

    func save() {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: fileURL, options: .atomic)   // 부분 쓰기 손상 방지
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
