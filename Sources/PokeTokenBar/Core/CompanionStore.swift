import Foundation
import PokeTokenBarShared
import Observation
import UserNotifications

/// 게임 상태의 출처. 설치 이후 토큰 사용량으로 포켓몬을 진화시키고, 최종체 + 추가 임계 도달 시
/// 도감(라인 전체)에 보존 + 새 알. 진화 트리/희귀도/이름은 PokeProviding 으로 런타임 주입.
@MainActor
@Observable
final class CompanionStore {
    private(set) var state = CompanionState()
    private(set) var displayState: CompanionStateKind = .egg
    private(set) var currentLine: EvoLine?
    private(set) var representativeSubject = RepresentativeSubject(speciesID: nil, isShiny: false)
    private(set) var isHatching = false
    private var isRevealingDitto = false   // 메타몽 리빌 비동기 중복 방지(isHatching 자매)
    private(set) var justEvolvedTo: String?     // 이름(연출/문구)
    private(set) var justGraduated: String?
    private var eventUntil: Date?

    /// 부화/진화 연출 트리거 — seq 증가로 UI 가 감지, 팝오버가 닫혀 있었어도 다음 오픈에 1회 재생.
    enum Celebration: Equatable { case hatch(shiny: Bool), evolve, dittoReveal(shiny: Bool) }
    private(set) var celebration: Celebration?
    private(set) var celebrationSeq = 0
    private func fireCelebration(_ c: Celebration) { celebration = c; celebrationSeq += 1 }
    /// 연출 재생 후 UI 가 호출(1회성 보장).
    func consumeCelebration() { celebration = nil }

    /// 사탕 사용 시 "+XP" 순간 표시 — 진화 없이 부분 진행일 때도 피드백. seq 증가로 CompanionHeader 감지.
    private(set) var candyFeedbackSeq = 0
    private(set) var candyFeedbackAmount = 0
    /// "+XP" 표시 1회성 보장 — CompanionHeader 가 재생 후 호출한다. 소비하지 않으면 다른 탭에 갔다
    /// 홈으로 재진입할 때(CompanionHeader 재마운트) @State 가 초기화돼 같은 값이 다시 떠오른다(회귀).
    func consumeCandyFeedback() { candyFeedbackAmount = 0 }

    /// 민트 사용 시 "성격이 X로" 순간 표시 — 사탕 피드백과 동일 1회성 패턴(seq + consume).
    private(set) var mintFeedbackSeq = 0
    private(set) var mintFeedbackNature: PokemonNature?
    func consumeMintFeedback() { mintFeedbackNature = nil }

    private let provider: any PokeProviding
    private let clock: () -> Date
    private let fileURL: URL
    private var rng: any RandomNumberGenerator
    private let dittoDisguiseRollingEnabled: Bool
    /// 세션 내 활성 개체 교체 감지용. await 뒤 이전 개체의 결과가 새 개체를 덮지 않게 한다.
    private var activeGeneration = 0

    init(provider: any PokeProviding = PokeAPIClient.shared,
         clock: @escaping () -> Date = Date.init,
         fileURL: URL? = nil,
         rng: any RandomNumberGenerator = SystemRandomNumberGenerator(),
         dittoDisguiseRollingEnabled: Bool = AppEnv.isBundledApp) {
        self.provider = provider
        self.clock = clock
        self.fileURL = fileURL ?? Self.defaultURL()
        self.rng = rng
        self.dittoDisguiseRollingEnabled = dittoDisguiseRollingEnabled
        load()
        refreshRepresentativeSubject()
        if state.active != nil { displayState = .idle }
    }

    static func defaultURL() -> URL {
        // 상태 파일 위치. 기본은 Application Support/PokeTokenBar. `PTB_STATE_DIR` 환경변수가 있으면
        // 그 디렉토리를 쓴다 — 개발/QA 격리용(실제 companion 상태를 건드리지 않고 데모 상태로 실행).
        // 프로덕션은 이 변수가 없어 무영향.
        AppStatePaths.directory().appendingPathComponent("companion-state.json")
    }

    // MARK: 파생값 (UI)

    var language: AppLanguage { state.language }
    func setLanguage(_ lang: AppLanguage) { state.language = lang; save() }
    /// 앱 전체 UI 문자열 — language 변경 시 자동 재렌더.
    var l: L { L(language) }

    var hasActive: Bool { state.active != nil }
    var rarity: Rarity? { state.active?.rarity }
    var currentIsShiny: Bool {
        guard let a = state.active else { return false }
        if a.dittoDisguise != nil && !a.dittoRevealed { return false }   // 위장 중엔 이로치 숨김(리빌 때 공개)
        return a.isShiny
    }
    var currentNature: PokemonNature? { state.active?.nature }

    /// 메뉴바와 플로팅 펫이 그릴 대표 종과 색. nil 선택은 기존 동작(현재 개체/알)을 보존한다.
    /// 저장된 값이라 상시 렌더링 경로가 도감 전체를 다시 접거나 불필요한 상태를 관찰하지 않는다.
    struct RepresentativeSubject: Equatable, Sendable {
        let speciesID: Int?
        let isShiny: Bool
    }

    var representativeSpeciesID: Int? { state.representativeSpeciesID }

    /// 관련 상태가 바뀌어 저장되는 경계에서만 갱신한다. 고정 종 하나의 이로치 여부만 조회하므로
    /// 이름 해석·정렬을 포함한 `dexSpecies` 계산을 메뉴바/플로팅 펫 렌더마다 반복하지 않는다.
    private func refreshRepresentativeSubject() {
        let next: RepresentativeSubject
        if let selected = state.representativeSpeciesID {
            next = RepresentativeSubject(speciesID: selected,
                                         isShiny: state.ownsShinySpecies(selected))
        } else {
            next = RepresentativeSubject(speciesID: currentSpeciesID, isShiny: currentIsShiny)
        }
        if representativeSubject != next { representativeSubject = next }
    }

    /// nil 은 자동 추적. 도감에 없는 id 는 저장하지 않는다 — UI 밖 호출이나 손상된 입력도 같은
    /// 불변식을 지키며, 실패한 요청이 기존 선택을 조용히 해제하지 않도록 false 만 반환한다.
    @discardableResult
    func setRepresentativeSpeciesID(_ id: Int?) -> Bool {
        if let id, !state.ownsSpecies(id) { return false }
        state.representativeSpeciesID = id
        save()
        return true
    }

    // 알 인큐베이션 (active 없을 때)
    var isEgg: Bool { state.active == nil }
    var eggStarted: Bool { state.eggUsage > 0 }
    var eggProgress: Double { min(1, max(0, Double(state.eggUsage) / Double(PokemonBalance.eggHatchThreshold))) }
    var eggTokensToHatch: Int { max(0, PokemonBalance.eggHatchThreshold - state.eggUsage) }

    var displayName: String {
        guard let a = state.active, let line = currentLine else { return "Token Egg" }
        return line.localizedName(a.currentID, state.language)
    }
    var currentSpeciesID: Int? { state.active?.currentID }
    var isFinalStage: Bool {
        guard let a = state.active, let line = currentLine else { return false }
        return line.tree.node(withID: a.currentID)?.children.isEmpty ?? true
    }
    var stageText: String {
        guard let a = state.active else { return "" }
        return isFinalStage ? l.finalForm : l.stage(a.stageIndex + 1, a.totalForms)
    }
    var threshold: Int {
        guard let a = state.active else { return 1 }
        return PokemonBalance.phaseThreshold(rarity: a.rarity, totalForms: a.totalForms, stageIndex: a.stageIndex)
    }
    var progress: Double {
        guard let a = state.active, threshold > 0 else { return 0 }
        return min(1, max(0, Double(a.usedAtStage) / Double(threshold)))
    }
    var tokensToNext: Int { guard let a = state.active else { return 0 }; return max(0, threshold - a.usedAtStage) }
    /// iPhone companion: tokens to next evolution.
    var tokensToNextEvolution: Int { tokensToNext }
    /// iPhone companion: tokens to graduation (final form) — estimated remaining.
    var tokensToGraduation: Int { tokensToNext }

    /// 컴패니언 헤더 아래 상태 한 줄 — Mac 팝오버와 폰 페이로드가 같은 문구를 쓴다.
    var statusText: String {
        switch displayState {
        case .egg:     return l.statusEgg
        case .idle:    return l.statusIdle
        case .working: return l.statusWorking
        case .focus:   return l.statusFocus
        case .tired:   return l.statusTired
        case .sleep:   return l.statusSleep
        case .levelUp: return justEvolvedTo.map { l.statusEvolved($0) } ?? l.statusGrew
        }
    }

    /// lineNodes 를 폰 페이로드 형태(종 이름 현지화 포함)로 변환.
    var phoneLineNodes: [PhoneEvoNode] {
        lineNodes.map { item in
            let state: PhoneEvoNode.State
            switch item.state {
            case .done: state = .done
            case .current: state = .current
            case .future: state = .future
            }
            switch item.content {
            case .species(let id):
                return PhoneEvoNode(speciesID: id, name: currentLine?.localizedName(id, language), state: state)
            case .mystery:
                return PhoneEvoNode(speciesID: nil, name: nil, state: state)
            }
        }
    }

    /// 진화 라인 표시용: 실현된 경로 + 다음 단계 미리보기.
    /// 유일하게 이어지는 단계 뒤에 분기가 있으면, 그 확정 접두어와 하나의 미지 항목을 함께 보여 준다.
    /// 분기 후보는 부화 시 계획됐더라도 실제 진화 전까지 하나의 미지 항목으로 숨긴다.
    var lineNodes: [EvoLineItem] {
        guard let a = state.active, let line = currentLine else { return [] }
        var out = Self.realizedLineItems(pathIDs: a.pathIDs, stageIndex: a.stageIndex)
        if let current = line.tree.node(withID: a.currentID) {
            var node = current
            var guaranteedPrefix: [EvoNode] = []
            while node.children.count == 1, let child = node.children.first {
                guaranteedPrefix.append(child)
                node = child
            }

            if node.children.count > 1 {
                out += guaranteedPrefix.map { EvoLineItem(.species($0.speciesID), .future) }
                out.append(EvoLineItem(.mystery, .future))
            } else {
                out += guaranteedPrefix.map { EvoLineItem(.species($0.speciesID), .future) }
            }
        }
        return out
    }

    static func realizedLineItems(pathIDs: [Int], stageIndex: Int) -> [EvoLineItem] {
        pathIDs.enumerated().map { i, id in
            EvoLineItem(.species(id), i == stageIndex ? .current : .done)
        }
    }
    /// 도감에는 영구 보존된 졸업 개체와 현재 키우는 포켓몬을 함께 표시한다.
    /// 현재 개체는 영속 dex 에 중복 저장하지 않고 화면용 항목으로 합성한다. 졸업 시 active 가 사라지고
    /// 같은 개체의 영구 DexEntry 가 추가되므로 목록 개수는 그대로 유지된다.
    private var activeDexEntry: DexEntry? {
        guard let active = state.active else { return nil }
        return DexEntry(
            id: "active-\(active.baseID)-\(active.currentID)",
            baseID: active.baseID,
            finalID: active.currentID,
            chainOrder: active.pathIDs,
            rarity: active.rarity,
            caughtAt: nil,
            isShiny: currentIsShiny,   // 위장 메타몽은 리빌 전까지 이로치를 숨긴다(판정 단일 소스)
            nature: active.nature,
            names: currentLine.map { line in
                Dictionary(uniqueKeysWithValues:
                    active.pathIDs.compactMap { id in line.names[id].map { (id, $0) } })
            }
        )
    }

    /// 놓아준 개체의 영구 기록 — 알을 새로 사서 육성을 포기하는 순간 만든다.
    ///
    /// **도달한 형태만 담는다**(`pathIDs.prefix(stageIndex + 1)`). 도감이 육성 중 보여주던 범위와
    /// 같아야 놓아준 뒤에도 칸 구성이 그대로 유지된다 — `plannedPathIDs` 나 `pathIDs` 전체를 쓰면
    /// 도달한 적 없는 진화형까지 보유로 잡힌다(`dexSpecies` 가 같은 prefix 규칙을 쓴다).
    ///
    /// 이로치는 `currentIsShiny` — 위장 중인 메타몽은 리빌 전까지 숨긴다(`activeDexEntry` 와 단일 판정).
    /// `caughtAt` 은 놓아준 시각이다: 포획 로그가 그 값으로 정렬하므로 기록이 남은 시점과 일치해야 한다.
    private func releasedDexEntry(from a: MonState) -> DexEntry {
        // stageIndex 가 음수·범위 밖이어도 최소 한 형태는 남긴다(손상 상태 파일 방어 — MonState.currentID 와 같은 태도).
        let reached = Array(a.pathIDs.prefix(max(1, a.stageIndex + 1)))
        let chain = reached.isEmpty ? [a.baseID] : reached
        let now = clock()
        return DexEntry(
            baseID: a.baseID,
            finalID: chain.last ?? a.baseID,
            chainOrder: chain,
            rarity: a.rarity,
            caughtAt: now,
            isShiny: currentIsShiny,
            nature: a.nature,
            names: currentLine.map { line in
                Dictionary(uniqueKeysWithValues:
                    chain.compactMap { id in line.names[id].map { (id, $0) } })
            },
            releasedAt: now)
    }

    var dexEntries: [DexEntry] {
        guard let activeDexEntry else { return state.dex }
        return state.dex + [activeDexEntry]
    }

    /// 합성된 현재 포켓몬 항목인지 판별한다. caughtAt 이 없는 구버전 졸업 항목과 혼동하지 않는다.
    func isActiveDexEntry(_ entry: DexEntry) -> Bool {
        entry.id == activeDexEntry?.id
    }

    /// 포획 로그 표시 순서 — 현재 키우는 포켓몬을 맨 앞에 고정하고, 졸업 항목은 **기록 시각 최신순**.
    ///
    /// 과거에는 희귀도 내림차순이 먼저였다(종 단위 도감의 규칙). 로그는 시간순 기록이라 희귀도로
    /// 먼저 묶으면 방금 졸업한 개체가 며칠 전에 잡은 상위 희귀도 밑에 묻힌다. 희귀도로 좁히는 일은
    /// 이제 필터 캡슐과 도감이 담당한다.
    ///
    /// caughtAt 이 없는 구버전 항목은 .distantPast 로 묶여 맨 뒤에 온다(그들끼리의 순서는 미정).
    var dexEntriesSorted: [DexEntry] {
        let graduated = state.dex.sorted {
            ($0.caughtAt ?? .distantPast) > ($1.caughtAt ?? .distantPast)
        }
        guard let activeDexEntry else { return graduated }
        return [activeDexEntry] + graduated
    }

    /// 희귀도별 포획 로그 개수(요약 헤더용) — 개체 수 기준. 도감(종 단위)은 dexSpecies 를 쓴다.
    func dexCount(_ rarity: Rarity) -> Int { dexEntries.lazy.filter { $0.rarity == rarity }.count }

    /// 도감 한 칸 — 종 1개로 접힌 수집 기록. 같은 라인을 여러 번 키워도 종은 한 칸이다.
    /// **종 정보만 담는다** — 성격·획득 횟수처럼 개체에 딸린 것은 포획 로그가 개체 단위로 보여준다.
    struct DexSpecies: Identifiable, Sendable {
        let id: Int                     // speciesID = 도감 번호(정렬 키)
        let name: String
        let rarity: Rarity
        let isShiny: Bool               // 이 종을 이로치로 보유한 적이 있는가
        /// 이 종이 현재 키우는 개체의 **현재 형태**인가. 지나온 진화 단계에는 서지 않는다.
        let isRaising: Bool
    }

    /// 종 하나가 모으는 것 — 누적 전용. 병렬 딕셔너리를 여러 개 두면 키 집합이 서로 어긋날 수 있고
    /// (한쪽에만 써서 그 종이 조용히 사라지거나), 읽는 쪽에 도달 불가한 기본값이 생긴다. 하나로 묶어
    /// 두 여지를 함께 없앤다.
    private struct DexAccumulator {
        /// 첫 발견 때 확정 — 같은 종은 항상 같은 base 라인에서 오므로 갱신할 값이 없다.
        let rarity: Rarity
        var names: [String: String]?
        var isShiny = false
    }

    /// 도감 목록 — 보유 종만, 도감 번호 오름차순.
    ///
    /// 포함 종 = 졸업분 `chainOrder` ∪ 현재 개체의 **도달분** `pathIDs[0...stageIndex]`.
    /// `plannedPathIDs`(사전 선택된 전체 경로)는 미도달 단계를 포함하므로 절대 쓰지 않는다 — 쓰면
    /// 아직 진화하지 않은 종이 보유로 잡힌다.
    var dexSpecies: [DexSpecies] {
        // 종별 누적을 한 번에 훑는다(뷰가 body 에서 1회 소비 — 메모이즈 없이 충분).
        var acc: [Int: DexAccumulator] = [:]
        for entry in state.dex {
            for id in entry.chainOrder {
                var a = acc[id] ?? DexAccumulator(rarity: entry.rarity)
                if let n = entry.names?[id] { a.names = n }   // 이름 없는 구버전 항목이 덮어쓰지 않게
                if entry.isShiny { a.isShiny = true }
                acc[id] = a
            }
        }
        if let active = state.active {
            // 도달분만 — stageIndex 가 pathIDs 범위 안임은 두 입구가 보장한다:
            // MonState.init(from:) 의 clamp, 그리고 SaveTransfer 의 가져오기 정규화.
            for id in active.pathIDs.prefix(active.stageIndex + 1) {
                var a = acc[id] ?? DexAccumulator(rarity: active.rarity)
                if let n = currentLine?.names[id] { a.names = n }
                if currentIsShiny { a.isShiny = true }   // 위장 중 숨김 규칙 재사용
                acc[id] = a
            }
        }
        return acc.sorted { $0.key < $1.key }.map { id, a in
            DexSpecies(
                id: id,
                name: a.names.flatMap { state.language.resolveName($0) } ?? "#\(id)",
                rarity: a.rarity,
                isShiny: a.isShiny,
                isRaising: id == state.active?.currentID)
        }
    }

    /// 이름이 없는 구버전 졸업 항목의 체인 이름을 채운다(도감 격자 진입 시 1회).
    ///
    /// 격자는 저장된 이름만 읽으므로 백필이 없으면 칸이 종 번호(`#41`)로 남는다. 포획 로그는 행이
    /// 뜰 때 행 단위로 같은 일을 해 왔지만, 로그를 한 번도 안 열면 격자는 계속 번호다.
    /// 라인 조회는 `PokeAPIClient` 가 base 단위로 캐시하므로 같은 라인이 여러 항목이어도 네트워크는 1회.
    /// 오프라인이면 `dexResolveChainNames` 가 저장 없이 폴백만 돌려주므로 다음 진입에서 다시 시도한다.
    func backfillMissingDexNames() async {
        for entry in state.dex where entry.names == nil {
            _ = await dexResolveChainNames(entry)   // 성공분만 내부에서 state.dex 에 저장
        }
    }

    /// 도감 항목 진화 체인 각 종의 이름(speciesID → 현재 언어 이름). 저장돼 있으면 즉시(네트워크 0),
    /// 없으면 nil(뷰가 async 조회로 폴백).
    func dexStoredChainNames(_ entry: DexEntry) -> [Int: String]? {
        guard let names = entry.names, !names.isEmpty else { return nil }
        return names.compactMapValues { state.language.resolveName($0) }
    }

    /// 이름 미저장(구버전) 항목용 — line 을 1회 조회해 체인 전 종의 다국어 이름을 얻고 항목에 백필한다
    /// (다음부터 네트워크 0). 저장돼 있으면 그대로(fetch 없음). 오프라인이면 종 번호(#id)로 폴백.
    /// 반환은 chainOrder 전 종을 채운 [speciesID: 현재 언어 이름].
    func dexResolveChainNames(_ entry: DexEntry) async -> [Int: String] {
        if let stored = dexStoredChainNames(entry) { return stored }
        guard let line = try? await provider.line(baseSpeciesID: entry.baseID) else {
            return Dictionary(uniqueKeysWithValues: entry.chainOrder.map { ($0, "#\($0)") })
        }
        let chainNames = Dictionary(uniqueKeysWithValues:
            entry.chainOrder.compactMap { id in line.names[id].map { (id, $0) } })
        if !chainNames.isEmpty, let idx = state.dex.firstIndex(where: { $0.id == entry.id }) {
            state.dex[idx].names = chainNames   // 백필 저장
            save()
        }
        return Dictionary(uniqueKeysWithValues: entry.chainOrder.map { id in
            (id, chainNames[id].flatMap { state.language.resolveName($0) } ?? "#\(id)")
        })
    }

    // MARK: 갱신 (AppDelegate 가 UsageStore 값으로 호출)

    func update(todayTokensByProvider: [String: Int], todayDate: String, monthTotal: Int,
                burnTier: BurnTier, limitWarning: Bool, hasUsageData: Bool) {
        let todayTokens = todayTokensByProvider.values.reduce(0, +)
        // `hasUsageData`는 표시용 snapshot 존재 여부이고, 이 map은 오늘 날짜가 확인된
        // provider 데이터만 담는다. stale snapshot이나 today == nil carrier만 있는 refresh는
        // ledger의 기준점을 움직일 수 있는 관측으로 취급하지 않는다.
        let hasCurrentProviderData = hasUsageData && !todayTokensByProvider.isEmpty
        if !state.installBaselineSet {
            // 설치 기준선 — 실제 데이터가 도착한 시점의 today 를 baseline 으로(이전 사용량 미카운트).
            // 데이터 도착 전(기동 직후 빈 새로고침)에는 잡지 않는다.
            guard hasCurrentProviderData else {
                // 세이브 불러오기가 baseline 판정을 이 경로에 넘겼을 수 있다(SaveTransfer.rebasedForThisDevice).
                // 그 경우 개체는 이미 들어와 있으므로 알로 표시하면 안 되고, 진화 라인 로드도 계속 재시도해야
                // 한다 — 새 Mac 은 AI CLI 를 처음 쓸 때까지 hasUsageData 가 false 라 여기서 막히면 그날 내내
                // 알로 보인다(재시작해도 동일).
                displayState = state.active == nil ? .egg : .idle
                kickLineLoadIfNeeded()
                return
            }
            state.installBaselineSet = true
            state.claimedTodayTokensByProvider = todayTokensByProvider
            state.lastDate = todayDate
            save()
        } else {
            // `today == nil` carrier만 남거나 파싱이 실패한 refresh는 현재 map이 비어 있을 수
            // 있다. 그런 관측으로 날짜·ledger를 움직이면 다음 정상 snapshot을 당일 전체 신규
            // 사용량으로 오인할 수 있으므로, 유효한 사용량이 있는 refresh만 ledger를 갱신한다.
            if hasCurrentProviderData {
                let dateChanged = todayDate != state.lastDate
                if state.claimedTodayTokensByProvider == nil {
                    // 구버전 세이브에는 aggregate high-water mark만 있어 프로바이더별로 분해할 수 없다.
                    // 첫 유효 관측을 새 장부의 기준점으로만 저장해 과거 사용량을 소급 지급하지 않는다.
                    state.claimedTodayTokensByProvider = todayTokensByProvider
                    state.lastDate = todayDate
                    AppLog.write("companion provider ledger seeded date=\(todayDate) providers=\(todayTokensByProvider.keys.sorted().joined(separator: ","))")
                } else if dateChanged {
                    // 일자별 snapshot은 서로 비교할 수 없다. 새 날짜에는 이전 날짜의 ledger를
                    // 기준으로 삼지 않고, 현재 날짜의 누적값 전체를 새 날짜 사용량으로 적립한다.
                    // 단, 위의 nil migration 경로는 구버전 aggregate를 분해할 수 없으므로 seed만 한다.
                    //
                    // 이전 날짜에 이미 알려진 provider가 첫 새로고침에서 빠질 수 있다(오늘 데이터
                    // 없음, stale 응답, 일시 실패). 그 provider를 아예 ledger에서 제거하면 같은
                    // 날짜에 복구될 때 현재 누적값을 "이미 적립한 값"으로 seed해 사용량이 누락된다.
                    // 이전 날짜의 숫자는 비교에 사용할 수 없으므로, 알려진 provider의 새 날짜 기준을
                    // 0으로 열어 둔다. 이후 복구된 현재 날짜 값은 그 날짜의 실제 사용량으로 적립되고,
                    // 같은 날짜의 부분 응답에서는 이 기준을 그대로 보존한다.
                    state.lastDate = todayDate
                    var newLedger = Dictionary(uniqueKeysWithValues:
                        state.claimedTodayTokensByProvider!.keys.map { ($0, 0) })
                    for (providerID, current) in todayTokensByProvider {
                        newLedger[providerID] = current
                    }
                    state.claimedTodayTokensByProvider = newLedger
                    let delta = todayTokensByProvider.values.reduce(0, +)
                    if delta > 0 {
                        state.usedSinceInstall += delta
                        if state.active == nil {
                            state.eggUsage += delta
                        } else {
                            applyUsage(delta)
                        }
                    }
                } else {
                    var ledger = state.claimedTodayTokensByProvider ?? [:]
                    var delta = 0
                    for (providerID, current) in todayTokensByProvider {
                        guard let previous = ledger[providerID] else {
                            // 새로 관측된 프로바이더의 과거 로그를 소급하지 않는다. 이후 refresh부터
                            // 해당 프로바이더의 증가분을 추적할 수 있도록 현재 값을 seed한다.
                            ledger[providerID] = current
                            continue
                        }
                        if current < previous {
                            // 전체 합계가 아니라 해당 프로바이더의 line만 rebase한다. 다른 프로바이더가
                            // 이번 refresh에서 보고하지 않았거나 carrier snapshot만 남은 경우에는 map에
                            // line 자체가 없으므로 기존 기준값을 건드리지 않는다.
                            ledger[providerID] = current
                            AppLog.write("companion usage regression provider=\(providerID) date=\(todayDate) previous=\(previous) current=\(current) drop=\(previous - current) — rebased provider ledger")
                            continue
                        }
                        delta += current - previous
                        ledger[providerID] = current
                    }
                    state.claimedTodayTokensByProvider = ledger
                    if delta > 0 {
                        state.usedSinceInstall += delta
                        if state.active == nil {
                            state.eggUsage += delta   // 알 인큐베이션 누적
                        } else {
                            applyUsage(delta)
                        }
                    }
                }
            }
        }
        // 이벤트(진화/졸업/부화) 창 만료 — .levelUp 창이 끝날 때 문구 플래그를 함께 정리한다.
        // justEvolvedTo 는 여기(창 만료)에서만 지운다: 과거엔 매 update() 초입에 무조건 nil 로 밀어,
        // 진화 후 4초 창 도중 update 틱이 끼면 "…(으)로 진화했어요"→"성장했어요"로 되돌아갔다(회귀 #4).
        if let until = eventUntil, clock() > until {
            justGraduated = nil; justEvolvedTo = nil; eventUntil = nil
        }
        // 알 상태 프리패칭 — 종 pre-roll + 라인/스프라이트 예열(부화 순간 딜레이 제거).
        // 성공할 때까지 매 update 틱마다 재시도(성공 후엔 no-op).
        if state.active == nil, state.installBaselineSet, !isHatching {
            Task { await ensureEggPrefetch() }
        }
        // 알이 부화 임계에 도달하면 부화
        if state.active == nil, state.eggUsage >= PokemonBalance.eggHatchThreshold, !isHatching {
            Task { await hatchIfNeeded() }
        }
        // active 인데 라인 미로딩(앱 재시작) → 로드
        if state.active != nil, currentLine == nil, !isHatching {
            Task { await loadCurrentLine() }
        }
        // 위장 메타몽이 첫 진화 임계 도달 → 리빌(재시작 등 applyUsage 킥을 못 탄 경우 백업 트리거)
        if let a = state.active, a.dittoDisguise != nil, !a.dittoRevealed, currentLine != nil,
           !isHatching, !isRevealingDitto,
           a.usedAtStage >= PokemonBalance.phaseThreshold(rarity: a.rarity, totalForms: a.totalForms, stageIndex: 0) {
            Task { await revealDitto() }
        }
        displayState = computeState(burnTier: burnTier, limitWarning: limitWarning,
                                    hasUsageData: hasUsageData, today: todayTokens)
        save()
    }

    /// 토큰 증분을 현재 포켓몬에 적용 — 임계 도달 시 진화/졸업.
    /// 라인 미로딩(재시작 직후·오프라인)이어도 사용량은 항상 적립한다 — 여기서 드롭하면
    /// 프로바이더별 ledger 는 이미 전진해 델타가 영구 유실된다. 진화 판정만 라인 로드 후로 미룬다.
    func applyUsage(_ delta: Int) {
        guard state.active != nil else { return }
        state.active!.usedAtStage += delta
        guard let line = currentLine else { save(); return }
        var guardCount = 0
        while state.active != nil, guardCount < 50 {
            guardCount += 1
            let a = state.active!
            let thr = PokemonBalance.phaseThreshold(rarity: a.rarity, totalForms: a.totalForms, stageIndex: a.stageIndex)
            guard a.usedAtStage >= thr else { break }
            guard let node = line.tree.node(withID: a.currentID) else { break }
            // 위장체는 부화 때는 다형태지만, 에셋 정규화/마이그레이션 뒤 leaf가 될 수 있다.
            // 따라서 terminal 졸업보다 먼저 리빌해야 위장 종이 도감으로 잘못 졸업하지 않는다.
            if a.dittoDisguise != nil, !a.dittoRevealed {
                if !isRevealingDitto { Task { await revealDitto() } }
                break
            }
            if node.children.isEmpty {
                graduate(); break
            } else {
                let nextIndex = a.stageIndex + 1
                let next: EvoNode
                if a.plannedPathIDs.indices.contains(nextIndex),
                   let planned = node.children.first(where: { $0.speciesID == a.plannedPathIDs[nextIndex] }) {
                    next = planned
                } else {
                    next = pickPlannedChild(node, baseID: a.baseID)
                    let fallbackRoute = [node.speciesID] + makeEvolutionPlan(from: next, baseID: a.baseID)
                    let repaired = Self.repairedPlan(realizedPath: a.pathIDs, stageIndex: a.stageIndex,
                                                     fallbackRoute: fallbackRoute)
                    state.active!.plannedPathIDs = repaired
                    state.active!.totalForms = repaired.count
                    AppLog.write("evolve: repaired invalid planned path for base \(a.baseID)")
                }
                state.active!.pathIDs = Array(a.pathIDs.prefix(a.stageIndex + 1)) + [next.speciesID]
                state.active!.stageIndex += 1
                state.active!.usedAtStage = a.usedAtStage - thr   // 초과분 이월
                let newName = line.localizedName(next.speciesID, state.language)
                justEvolvedTo = newName
                fireCelebration(.evolve)
                // 짧은 levelUp 창 — 진화 순간 "…(으)로 진화했어요" 문구 노출(hatch/graduate 와 동일 패턴).
                // 이게 없으면 computeState 가 .levelUp 을 안 내 statusEvolved 가 도달 불가(dead code)였다.
                eventUntil = clock().addingTimeInterval(4)
                notifyCompanionEvent(l.notifEvolveTitle, l.notifEvolveBody(newName))
            }
        }
        save()
    }

    private func pickPlannedChild(_ node: EvoNode, baseID: Int) -> EvoNode {
        let fresh = node.children.filter { ch in
            ch.finalIDs.contains { !state.collectedFinals.contains("\(baseID):\($0)") }
        }
        let pool = fresh.isEmpty ? node.children : fresh
        return pool[Int(rng.next() % UInt64(pool.count))]
    }

    private func makeEvolutionPlan(from root: EvoNode, baseID: Int) -> [Int] {
        var plan = [root.speciesID]
        var node = root
        while !node.children.isEmpty {
            let next = pickPlannedChild(node, baseID: baseID)
            plan.append(next.speciesID)
            node = next
        }
        return plan
    }

    static func repairedPlan(realizedPath: [Int], stageIndex: Int, fallbackRoute: [Int]) -> [Int] {
        guard !realizedPath.isEmpty else { return fallbackRoute }
        let currentIndex = min(stageIndex, realizedPath.count - 1)
        let prefix = Array(realizedPath.prefix(currentIndex + 1))
        guard fallbackRoute.first == prefix.last else { return prefix }
        return prefix + fallbackRoute.dropFirst()
    }

    /// 루트부터 실제로 이어지는 가장 긴 ID 경로와 마지막 유효 노드. 첫 ID가 루트와 다르면 루트로 복구한다.
    private func longestValidPath(_ ids: [Int], from root: EvoNode) -> (path: [Int], lastNode: EvoNode) {
        var path = [root.speciesID]
        var node = root
        guard ids.first == root.speciesID else { return (path, node) }
        for id in ids.dropFirst() {
            guard let child = node.children.first(where: { $0.speciesID == id }) else { break }
            path.append(id)
            node = child
        }
        return (path, node)
    }

    /// 저장된 실제 경로와 계획을 현재 에셋 트리에 맞춘다. 완전한 계획만 재사용해 재시작 시 RNG를 소비하지 않는다.
    private func normalizedEvolutionState(_ saved: MonState, from root: EvoNode) -> MonState {
        var normalized = saved
        let realized = longestValidPath(saved.pathIDs, from: root)
        let candidate = longestValidPath(saved.plannedPathIDs, from: root)
        let canReusePlan = candidate.path == saved.plannedPathIDs
            && candidate.path.starts(with: realized.path)
            && candidate.lastNode.children.isEmpty
        let plan: [Int]
        if canReusePlan {
            plan = candidate.path
        } else {
            let suffix = makeEvolutionPlan(from: realized.lastNode, baseID: saved.baseID)
            plan = realized.path + suffix.dropFirst()
        }
        normalized.pathIDs = realized.path
        normalized.plannedPathIDs = plan
        normalized.stageIndex = realized.path.count - 1
        normalized.totalForms = plan.count
        return normalized
    }

    private func graduate() {
        guard let a = state.active else { return }
        let finalID = a.currentID
        state.collectedFinals.insert("\(a.baseID):\(finalID)")
        state.dex.append(DexEntry(baseID: a.baseID, finalID: finalID,
                                  chainOrder: a.pathIDs, rarity: a.rarity, caughtAt: clock(),
                                  isShiny: a.isShiny, nature: a.nature,
                                  names: currentLine.map { line in   // 체인 각 종의 다국어 이름 저장(표시 즉시)
                                      Dictionary(uniqueKeysWithValues:
                                          a.pathIDs.compactMap { id in line.names[id].map { (id, $0) } })
                                  }))
        let name = currentLine?.localizedName(finalID, state.language) ?? ""
        justGraduated = name
        notifyCompanionEvent(l.notifGraduateTitle, l.notifGraduateBody(name))
        eventUntil = clock().addingTimeInterval(6)
        state.active = nil
        state.reconcileRepresentativeSelection()   // 졸업 체인이 dex 로 옮겨져 선택은 정상적으로 유지된다
        activeGeneration += 1
        currentLine = nil
        state.eggUsage = 0   // 새 알은 처음부터 인큐베이션
        // eggTier 는 손대지 않는다 — 여기 도달했다는 건 활성 포켓몬이 있었다는 뜻이라 보증은 이미 nil 이다
        // (부화가 소비, 디스크/불러오기는 sanitized 가 정규화). 소비 지점은 hatchCore 한 곳으로 유지한다.
        // "알을 받는 순간" 즉시 프리패칭 시작 — 다음 부화의 종·라인·스프라이트 예열.
        Task { await self.ensureEggPrefetch() }
    }

    // MARK: 인벤토리 / 이상한 사탕

    var rareCandyCount: Int { itemCount(.rareCandy) }
    func itemCount(_ kind: ItemKind) -> Int { state.inventory[kind.rawValue] ?? 0 }
    /// 이로치 부적 보유 여부 — 보유형이라 개수>0 = 소유(부화 shiny 분모를 낮춘다).
    var ownsShinyCharm: Bool { itemCount(.shinyCharm) > 0 }

    /// 소유 아이템(개수>0) — 가방 목록. 정렬은 ItemKind.allCases 순서.
    var ownedItems: [(kind: ItemKind, count: Int)] {
        ItemKind.allCases.compactMap { k in
            let c = itemCount(k)
            return c > 0 ? (k, c) : nil
        }
    }

    /// 이상한 사탕 사용 가능 — 활성 포켓몬 + 라인 로딩 완료 + 재고>0.
    /// 라인 미로딩(재시작 직후·오프라인)이면 비활성 — 사탕이 진화 없이 적립만 되는 것 방지.
    var canUseRareCandy: Bool { hasActive && currentLine != nil && rareCandyCount > 0 }

    /// 사탕 사용 결과 — UI 피드백 분기용.
    enum CandyUseResult: Equatable { case evolved, graduated, progressed, unavailable }

    /// 이상한 사탕 1개 사용 — 현재 포켓몬에 +RareCandy.xp. applyUsage 재사용으로 이월·진화·졸업·연출 자동.
    /// 사탕 XP 는 usedAtStage(진화 진행)에만 반영 — usedSinceInstall/오늘 토큰(실사용 통계)엔 안 잡힌다.
    @discardableResult
    func useRareCandy() -> CandyUseResult {
        guard canUseRareCandy else { return .unavailable }
        state.inventory[ItemKind.rareCandy.rawValue] = rareCandyCount - 1
        let beforeStage = state.active?.stageIndex ?? 0
        // 진화 안 될 때(부분 진행)도 즉시 "+XP" 피드백 — CompanionHeader 가 연출과 별개로 표시.
        candyFeedbackAmount = RareCandy.xp
        candyFeedbackSeq += 1
        applyUsage(RareCandy.xp)   // 내부에서 save() 수행(인벤토리 감소 포함 영속)
        if state.active == nil { return .graduated }
        if state.active!.stageIndex > beforeStage { return .evolved }
        return .progressed
    }

    // MARK: 민트 (성격 랜덤 재설정)

    /// 민트 사용 가능 — 활성 포켓몬 + 재고>0. 성격은 MonState 에만 있어 진화 라인 로딩과 무관하다
    /// (사탕과 달리 currentLine 조건 없음 — 재시작 직후·오프라인에도 사용 가능).
    var canUseMint: Bool { hasActive && itemCount(.mint) > 0 }

    /// 민트 1개 사용 — 현재 포켓몬 성격을 '현재와 다른' 무작위 성격으로 교체(반드시 바뀐다). 성장·shiny·
    /// 종·usedAtStage·통계 전부 무관(순수 코스메틱). 사용 불가면 nil(무소모). 바뀐 성격을 반환(피드백용).
    @discardableResult
    func useMint() -> PokemonNature? {
        guard canUseMint, state.active != nil else { return nil }
        let cur = state.active!.nature
        let pool = PokemonNature.allCases.filter { $0 != cur }   // cur=nil(구버전 개체)이면 25종 전체
        let new = pool[Int(rng.next() % UInt64(pool.count))]
        state.active!.nature = new
        state.inventory[ItemKind.mint.rawValue] = itemCount(.mint) - 1
        mintFeedbackNature = new
        mintFeedbackSeq += 1
        save()
        return new
    }

    // MARK: 상점 (재화 = 사용한 토큰)

    /// 상점에서 쓸 수 있는 토큰(재화) = 실사용 누적 − 상점 지출 누적. 성장 미터(usedSinceInstall)는
    /// 여기선 읽기만 — 구매는 spentTokens 만 올려 잔액을 깎는다(진화 진행·오늘/주/월 통계 무영향).
    var availableTokens: Int { max(0, state.usedSinceInstall - state.spentTokens) }

    /// 상점 판매 아이템 — shopPrice 있는 것만. 가격 저렴한 순, 단 구매 완료한 보유형은 맨 아래로.
    var purchasableItems: [ItemKind] {
        ItemKind.allCases
            .filter { $0.shopPrice != nil }
            .sorted { a, b in
                // 구매 완료한 보유형(이로치 부적 등)은 맨 아래로 — 재구매 불가라 위에 있을 이유가 없다.
                let aDone = a.isPassive && itemCount(a) > 0
                let bDone = b.isPassive && itemCount(b) > 0
                if aDone != bDone { return !aDone }
                return (a.shopPrice ?? 0) < (b.shopPrice ?? 0)   // 나머지는 가격 저렴한 순
            }
    }

    /// 상점 표시 순서 — 판매 아이템 + 알 3종을 하나의 가격 오름차순 목록으로 병합.
    /// 정렬 규칙은 purchasableItems 와 동일: 구매 완료한 보유형은 맨 아래, 나머지는 가격 저렴한 순.
    /// 알은 즉시 액션이라 '보유' 개념이 없어 가격 순서에만 참여한다.
    ///
    /// 알은 활성 포켓몬이 없어도(알 상태) 목록에 남는다 — 구매는 `canBuyEgg` 의 `hasActive` 게이트가
    /// 막고, EggCard 가 비활성 버튼 + 사유 한 줄로 보여준다. 목록에서 통째로 빼면 "상점에 알이 원래
    /// 없다"로 읽혀서, 게이트는 유지하되 존재는 계속 보이게 한다.
    ///
    /// 등급 알끼리 붙여 '티어 사다리'로 묶어 보이게 하는 안도 검토했으나 채택하지 않았다 — 지금의 순수
    /// 가격 오름차순은 "알이 무조건 맨 아래로 append 돼 더 비싼 부적보다 아래에 놓이던" 표시 회귀를
    /// 고치며 들어온 규칙이라(ShopTests 참조), 그룹 배치는 그 회귀를 부분적으로 되살린다. 티어 관계는
    /// 카드의 등급 배지로 읽히게 한다.
    var shopEntries: [ShopEntry] {
        var entries: [ShopEntry] = purchasableItems.map { ShopEntry.item($0) }
        entries += FreshEgg.shopTiers.map { ShopEntry.egg($0) }
        return entries.sorted { a, b in
            let aDone = isPurchasedPassive(a)
            let bDone = isPurchasedPassive(b)
            if aDone != bDone { return !aDone }
            return a.price < b.price
        }
    }

    /// 구매 완료한 보유형(이로치 부적 등)인지 — shopEntries 정렬에서 맨 아래로 보낼 판정.
    private func isPurchasedPassive(_ entry: ShopEntry) -> Bool {
        guard case .item(let kind) = entry else { return false }   // 알은 즉시 액션 — 보유 개념 없음
        return kind.isPassive && itemCount(kind) > 0
    }

    /// 구매 가능 — 잔액이 그 아이템 가격 이상(상점 미판매면 false). 활성/알 무관(재고는 미리 쌓아둘 수 있음).
    func canBuy(_ kind: ItemKind) -> Bool {
        guard let price = kind.shopPrice else { return false }
        if kind.isPassive && itemCount(kind) > 0 { return false }   // 보유형은 1회만(재구매 불가)
        return availableTokens >= price
    }

    /// 아이템 1개 구매 — 지갑에서 price 차감, 인벤토리 +1. usedSinceInstall(성장·통계)·진화 진행엔
    /// 무영향(지출 원장만 증가). 잔액 부족/미판매면 no-op(false).
    @discardableResult
    func buy(_ kind: ItemKind) -> Bool {
        guard let price = kind.shopPrice, availableTokens >= price else { return false }
        if kind.isPassive && itemCount(kind) > 0 { return false }   // 보유형 중복 구매 방지(방어)
        state.spentTokens += price
        state.inventory[kind.rawValue, default: 0] += 1
        save()
        return true
    }

    // 사탕 전용 래퍼 — 기존 호출부/테스트 호환.
    var canBuyRareCandy: Bool { canBuy(.rareCandy) }
    @discardableResult
    func buyRareCandy() -> Bool { buy(.rareCandy) }

    // MARK: 알 (리롤 — 현재 포켓몬 폐기, 도감·확률 무영향)

    /// 현재 알이 보증하는 등급 하한(UI 표시용). 활성 포켓몬이 있으면 알이 없으므로 nil.
    var eggGuarantee: Rarity? { state.active == nil ? state.eggTier : nil }

    /// 알 구매 가능 — 폐기할 활성 포켓몬이 있고 지갑이 그 티어 가격 이상일 때만.
    /// 알 상태에서도 살 수 있게 하는 안은 채택하지 않았다(기존 새 알과 게이트 통일) — 알끼리 교체하는
    /// 동작을 새로 만들지 않고, 상점의 알은 언제나 "지금 개체를 놓아주고 다시 뽑는다"는 한 가지 의미만 갖는다.
    /// 항목 자체는 알 상태에서도 상점에 남는다(shopEntries) — 이 게이트는 구매만 막는다.
    func canBuyEgg(_ tier: Rarity?) -> Bool {
        // 파는 티어인지 먼저 확인한다 — 만족 불가능한 보증(전설: capture_rate 로 표현 불가)을 사면
        // 두 롤 경로 모두 후보가 0개라 알이 영영 안 깨지고, 부화가 없으니 보증도 안 풀리며,
        // 새 알 구매는 `hasActive` 에 막혀 되돌릴 수단이 없다. 가격만 계산되면 값이 빠져나가므로
        // 판매 목록을 여기서 강제한다(호출부 하나가 실수하면 토큰이 통째로 사라진다).
        guard FreshEgg.shopTiers.contains(tier) else { return false }
        return hasActive && availableTokens >= FreshEgg.price(guaranteeing: tier)
    }

    /// 알 구매 — 현재 포켓몬을 놓아주고 처음부터 인큐베이션하는 새 알로. 지갑에서 가격 차감.
    /// graduate() 의 알-리셋을 미러링하되, 놓아준 개체는 **도감에 남긴다**(`releasedDexEntry`).
    /// 도감은 "쌓이기만 한다"는 약속을 주는데, 여기가 종이 사라질 수 있던 유일한 경로였다.
    /// `collectedFinals`(최종체 완성·분기 가중)는 여전히 손대지 않는다 — 끝까지 키운 게 아니다.
    /// 성장(usedAtStage)은 소멸(추가 비용).
    ///
    /// 여기서 종을 롤하지 않는다 — 롤에는 네트워크가 필요해서 오프라인이면 토큰만 사라진다. 보증만
    /// 상태(`eggTier`)에 적고, 실제 롤은 프리패치/부화 경로가 그 보증을 읽어 수행한다.
    @discardableResult
    func buyEgg(_ tier: Rarity?) -> Bool {
        guard canBuyEgg(tier) else { return false }
        state.spentTokens += FreshEgg.price(guaranteeing: tier)
        if let a = state.active {
            state.dex.append(releasedDexEntry(from: a))   // 놓아줌 기록 — 도감에서 종이 사라지지 않게
        }
        state.active = nil            // 놓아줌 (졸업 아님 — collectedFinals 는 미변경)
        // 놓아준 종도 이제 dex 에 있으므로 대표 선택은 유지된다. 손상 상태 파일 등으로 정말 보유가
        // 끊긴 경우만 자동 추적으로 복귀한다.
        state.reconcileRepresentativeSelection()
        activeGeneration += 1
        currentLine = nil
        state.eggUsage = 0            // 새 알은 처음부터 인큐베이션(재부화에 5M 필요)
        state.eggTier = tier          // 등급 보증(nil = 보증 없음)
        state.pendingHatchID = nil    // 새 보증으로 처음부터 롤(활성 포켓몬이 있는 동안엔 원래 비어 있다)
        prefetchedLineID = nil
        justGraduated = nil; justEvolvedTo = nil; eventUntil = nil
        AppLog.write("egg purchased: discarded active, tier=\(tier?.rawValue ?? "none")")
        Task { await self.ensureEggPrefetch() }   // 다음 부화 예열
        save()
        return true
    }

    // 보증 없는 기본 알 래퍼 — 기존 호출부/테스트 호환.
    var canBuyFreshEgg: Bool { canBuyEgg(nil) }
    @discardableResult
    func buyFreshEgg() -> Bool { buyEgg(nil) }

    /// 지급 판정(순수·엣지 트리거) — 한도 창이 100% 를 새로 넘어선 순간에만 지급.
    /// - 100% 미만 → 맵에서 제거(재무장). resets_at 등 휘발 필드는 key 에 없다(안정 식별자만).
    /// - 이미 지급한 창(tier≥1)은 재지급 안 함. session=1개·weekly=weeklyGrant.
    /// - 부수효과(인벤토리·알림)와 분리해 xctest 가능. (evaluateLimitAlerts 자매)
    static func evaluateCandyGrants(
        windows: [CandyWindow], grantTier: inout [String: Int]
    ) -> [CandyGrant] {
        var grants: [CandyGrant] = []
        for w in windows {
            guard w.utilization >= 100 else { grantTier[w.key] = nil; continue }
            let previous = grantTier[w.key] ?? 0
            guard previous < 1 else { continue }
            grantTier[w.key] = 1
            let count = w.kind == .weekly ? RareCandy.weeklyGrant : 1
            grants.append(CandyGrant(windowKey: w.key, windowName: w.name, count: count))
        }
        return grants
    }

    /// 한도 창 상태로부터 사탕 지급(엣지·영속). AppDelegate 가 매 refresh 완료 시(한도 로드 후) 호출.
    /// - 첫 실행: 현재 100% 창을 지급 없이 tier 시드만 → 이후 "새로 넘어서는" 순간부터 지급(소급 차단).
    /// - limitsReady=false(한도 미로딩)면 시드/지급 모두 대기(다음 refresh 에 재시도).
    func grantCandies(from windows: [CandyWindow], limitsReady: Bool) {
        guard limitsReady else { return }
        if !state.candyFeatureSeeded {
            // 한계(수용): 첫 refresh 에 한 프로바이더 한도만 로드되면 그 프로바이더 창만 시드된다.
            // 이후 다른 프로바이더가 이미 100%인 채 로드되면 소급 지급될 수 있으나, 1회·소수 캔디라
            // 1인 로컬에서 무시(YAGNI). refresh() 는 전 프로바이더 fetch 를 await 후 onRefresh 하므로
            // 정상 경로(둘 다 성공)에선 원자적 시드다.
            for w in windows where w.utilization >= 100 { state.candyGrantTier[w.key] = 1 }
            state.candyFeatureSeeded = true
            save()
            return
        }
        let before = state.candyGrantTier
        let grants = Self.evaluateCandyGrants(windows: windows, grantTier: &state.candyGrantTier)
        for g in grants {
            state.inventory[ItemKind.rareCandy.rawValue, default: 0] += g.count
            // 지급 자체는 알림 여부와 무관(상태 변경). 알림은 "왜 받는지"(그 창 한도를 다 채운 수고) 명시.
            notifyCompanionEvent(l.notifCandyTitle(item: l.itemName(.rareCandy), count: g.count),
                                 l.notifCandyBody(window: g.windowName))
        }
        // 지급이 없어도 재무장(창이 100%→아래로 내려가며 grantTier 에서 제거)은 영속해야 한다 —
        // 안 하면 재시작 시 stale tier=1 로 다음 100% 도달이 "이미 지급"으로 오판돼 지급 누락(회귀).
        if !grants.isEmpty || state.candyGrantTier != before { save() }
    }

    /// companion 이벤트 시스템 알림(.app + 토글 ON 일 때만). 한도 알림과 독립.
    private var notifSeq = 0
    private func notifyCompanionEvent(_ title: String, _ body: String) {
        guard AppEnv.isBundledApp else { return }
        guard UserDefaults.standard.object(forKey: "companionNotifications") as? Bool ?? true else { return }
        notifSeq += 1
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "companion-event-\(notifSeq)", content: content, trigger: nil))
    }

    // MARK: 부화

    func hatchIfNeeded() async {
        guard state.active == nil, !isHatching, state.eggUsage >= PokemonBalance.eggHatchThreshold else { return }
        // 프리패치가 "종 롤 중"(pending 미확정)일 때만 대기 — 이중 rng 소비 방지.
        // pending 확정 후의 예열(라인/스프라이트)과는 동시 진행해도 안전하다.
        guard state.pendingHatchID != nil || !prefetchInFlight else { return }
        // isHatching 을 롤~부화 전체에 defer 로 잠근다. 과거엔 chooseBase 후 isHatching 을 잠깐
        // 내렸다가(hatch 자체 가드 통과용) hatch 를 호출해, 그 await 창에서 다른 update 틱이
        // 두 번째 종을 롤하는 경합이 있었다. hatchCore 는 isHatching 을 재검사하지 않으므로
        // 여기서 소유한 락 하나로 롤·부화가 원자적으로 보호된다.
        let generation = activeGeneration
        isHatching = true
        defer { isHatching = false }
        // 프리패칭된 종이 있으면 그대로 사용(라인·스프라이트 예열됨 → 딜레이 ~0), 없으면 지금 롤.
        let base: Int?
        if let pending = state.pendingHatchID {
            base = pending
        } else {
            base = await chooseBase()
        }
        guard let base else { return }   // 네트워크 불안정 → 알 유지, 다음 update 틱에 재시도
        // 세대 검사는 **여기서** 해야 한다. `chooseBase()` 대기 창에서 상태가 통째로 교체되면
        // (세이브 불러오기) 그 뒤에 진입하는 hatchCore 는 *교체 이후*의 세대를 캡처해 자기 가드가
        // 무조건 통과한다 — 옛 롤 결과가 불러온 개체를 덮어쓰고 save() 로 디스크에 박힌다.
        guard activeGeneration == generation, state.active == nil else {
            AppLog.write("hatch: discarded before core — subject replaced during species roll")
            kickLineLoadIfNeeded()
            return
        }
        state.pendingHatchID = nil
        await hatchCore(baseID: base)
    }

    /// 부화가 폐기된 뒤 남은 개체(대개 방금 불러온 개체)의 진화 라인을 다시 로드한다.
    /// `loadCurrentLine` 은 `!isHatching` 을 요구하므로 부화 중에 걸린 로드는 조용히 실패한다 —
    /// 아무도 재시도하지 않으면 다음 update 틱(기본 120초)까지 이름이 "Token Egg" 로 남는다.
    /// Task 본문은 현재 동기 실행(= defer 로 isHatching 해제)이 끝난 뒤 돌므로 락이 이미 풀려 있다.
    private func kickLineLoadIfNeeded() {
        guard state.active != nil, currentLine == nil else { return }
        Task { await loadCurrentLine() }
    }

    // MARK: 알 프리패칭

    private var prefetchInFlight = false
    private var prefetchedLineID: Int?   // 라인·스프라이트 예열 완료한 종(세션 메모리)

    /// 알 상태에서 부화를 미리 준비 — ① 종 pre-roll(pendingHatchID, 영속) ② 진화 라인
    /// fetch(provider 캐시 적재) ③ 스프라이트 예열(정적+애니메이션+shiny 애니메이션).
    /// 전부 성공하면 부화 순간 네트워크 0. 실패 지점부터 다음 update 틱에 이어서 재시도.
    private func ensureEggPrefetch() async {
        guard state.active == nil, !isHatching, !prefetchInFlight else { return }
        let generation = activeGeneration
        prefetchInFlight = true
        defer { prefetchInFlight = false }

        if state.pendingHatchID == nil {
            guard let id = await chooseBase() else { return }   // 오프라인 → 다음 틱 재시도
            // await 사이에 부화가 끝났거나(active != nil) 상태가 통째로 교체됐으면(세이브 불러오기)
            // 이 롤을 버린다 — 안 그러면 불러온 알의 pre-roll 을 남의 롤로 덮어쓴다.
            guard state.active == nil, activeGeneration == generation else { return }
            state.pendingHatchID = id
            save()
        }
        guard let id = state.pendingHatchID, prefetchedLineID != id else { return }
        guard let line = try? await provider.line(baseSpeciesID: id) else { return }   // 라인 예열
        // 스프라이트 예열 — 부화 직후 보일 것들: base 정적+애니메이션, shiny 롤(1/64) 대비 shiny 애니메이션.
        // .app 번들에서만(단위 테스트가 실네트워크에 닿지 않도록 — 알림과 동일한 게이트).
        if AppEnv.isBundledApp {
            _ = await SpriteStore.shared.data(speciesID: line.baseID, animated: false, shiny: false)
            _ = await SpriteStore.shared.data(speciesID: line.baseID, animated: true, shiny: false)
            _ = await SpriteStore.shared.data(speciesID: line.baseID, animated: true, shiny: true)
        }
        prefetchedLineID = id
    }

    func hatch(baseID: Int) async {
        guard !isHatching else { return }
        isHatching = true
        defer { isHatching = false }
        await hatchCore(baseID: baseID)
    }

    // MARK: 메타몽 위장/리빌

    /// 메타몽 위장 롤 판정(순수) — common·≥2형태만, 미리 뽑은 roll 값으로 1/128. (부수효과 없이 xctest)
    nonisolated static func dittoDisguiseHit(rarity: Rarity, totalForms: Int, roll: UInt64) -> Bool {
        rarity == .common && totalForms >= 2 && roll % PokemonOdds.dittoDisguiseDenominator == 0
    }

    /// 이로치 부화 판정(순수) — 미리 뽑은 roll 값 % 분모(부적 보유 48, 없으면 64)==0. (부수효과 없이 xctest)
    nonisolated static func rollsShiny(roll: UInt64, charmOwned: Bool) -> Bool {
        roll % (charmOwned ? ShinyCharm.shinyDenominator : PokemonOdds.shinyDenominator) == 0
    }

    /// 실제 부화 로직 — isHatching 락은 호출자(hatch / hatchIfNeeded)가 소유·해제한다.
    private func hatchCore(baseID: Int) async {
        let generation = activeGeneration
        guard let line = try? await provider.line(baseSpeciesID: baseID) else {
            AppLog.write("hatch: line fetch failed for base \(baseID) — egg kept, retry next tick")
            return
        }
        // 라인 fetch 창(네트워크) 동안 활성 개체가 교체됐으면 이 부화 결과를 폐기한다. 세이브 불러오기가
        // 그 창에 들어오면, 여기서 멈추지 않는 한 갓 부화한 개체가 방금 불러온 개체를 덮어쓴다.
        // (loadCurrentLine·revealDitto 와 같은 세대 가드 — isHatching 락은 같은 앱 내 중복 부화만 막는다.)
        guard activeGeneration == generation else {
            AppLog.write("hatch: discarded — active subject replaced during line fetch")
            kickLineLoadIfNeeded()
            return
        }
        // 산 보증을 지키는 마지막 관문 — 진짜 등급을 아는 건 여기뿐이다(후보 인덱스엔 capture_rate 만
        // 있고 is_legendary 가 없다). 필터가 어긋났으면(인덱스 stale 등) 낮은 등급을 그냥 내주지 말고
        // 알을 유지한 채 pre-roll 만 버려 다음 틱에 다시 뽑는다 — 사용자는 산 보증을 계속 들고 있는다.
        if let tier = state.eggTier, line.rarity.sortRank < tier.sortRank {
            AppLog.write("hatch: rolled \(line.rarity) below guaranteed \(tier) — discarded, re-roll next tick")
            state.pendingHatchID = nil
            prefetchedLineID = nil
            save()
            return
        }
        currentLine = line
        // 부화 임계 초과분은 부화체 성장에 이월(낭비 없음).
        let overflow = max(0, state.eggUsage - PokemonBalance.eggHatchThreshold)
        state.eggUsage = 0
        state.eggTier = nil   // 보증은 이 부화로 소비된다(다음 알은 다시 무보증)
        // 개체 롤 — shiny(1/64)·성격(25종)은 부화 순간 확정, 진화해도 유지.
        let isShiny = Self.rollsShiny(roll: rng.next(), charmOwned: ownsShinyCharm)
        let nature = PokemonNature.allCases[Int(rng.next() % UInt64(PokemonNature.allCases.count))]
        // 메타몽 위장 롤 — common·≥2형태에 한해 1/128. .app 게이트(&& 단락 → 비앱에선 rng 미소비로
        // 기존 테스트 RNG 시퀀스 무영향). 위장/리빌 로직은 상태 기반으로 별도 테스트한다.
        var dittoDisguise: Int?
        if dittoDisguiseRollingEnabled,
           Self.dittoDisguiseHit(rarity: line.rarity, totalForms: line.totalForms, roll: rng.next()) {
            dittoDisguise = line.baseID
        }
        let evolutionPlan = makeEvolutionPlan(from: line.tree, baseID: line.baseID)
        // 위장 중엔 이로치를 숨긴다 — 부화 알림·연출도 일반체로(정체는 리빌 때 공개).
        let showShiny = isShiny && dittoDisguise == nil
        activeGeneration += 1
        state.active = MonState(baseID: line.baseID, pathIDs: [line.baseID], plannedPathIDs: evolutionPlan,
                                stageIndex: 0, usedAtStage: 0, rarity: line.rarity, totalForms: evolutionPlan.count,
                                isShiny: isShiny, nature: nature, dittoDisguise: dittoDisguise)
        AppLog.write("hatch: base=\(line.baseID) rarity=\(line.rarity) shiny=\(isShiny) forms=\(evolutionPlan.count) ditto=\(dittoDisguise != nil)")
        let name = line.localizedName(line.baseID, state.language)
        notifyCompanionEvent(showShiny ? l.notifShinyHatchTitle : l.notifHatchTitle,
                             showShiny ? l.notifShinyHatchBody(name) : l.notifHatchBody(name))
        justEvolvedTo = nil        // 새 부화는 "성장" 문구(진화 아님) — 직전 진화명이 남아 표시되지 않게
        displayState = .levelUp
        eventUntil = clock().addingTimeInterval(4)
        if overflow > 0 { applyUsage(overflow) }   // 이월분 즉시 반영(필요 시 진화/리빌까지)
        // 연출은 이월 진화 뒤에 발화 — 이월 evolve 가 shiny 부화 버스트를 덮지 않도록
        // 마지막 이벤트를 hatch 로 유지한다. 이월로 즉시 졸업한 극단 케이스면 생략(이미 도감행).
        if state.active != nil { fireCelebration(.hatch(shiny: showShiny)) }
        save()
    }

    /// 위장 → 리빌: 진화 못 하는 메타몽이 "첫 진화 임계"에서 진화 대신 정체를 드러내는 순간.
    /// Ditto 라인 로드 후 상태 변환(rare·단일형태·초과분 이월, isShiny/nature 유지) + 연출·알림.
    private func revealDitto() async {
        guard let a = state.active, a.dittoDisguise != nil, !a.dittoRevealed, !isRevealingDitto else { return }
        let generation = activeGeneration
        let firstEvoThr = PokemonBalance.phaseThreshold(rarity: a.rarity, totalForms: a.totalForms, stageIndex: 0)
        guard a.usedAtStage >= firstEvoThr else { return }   // 임계 미달 방어
        isRevealingDitto = true
        defer { isRevealingDitto = false }
        guard let dittoLine = try? await provider.line(baseSpeciesID: PokemonOdds.dittoSpeciesID) else {
            AppLog.write("ditto reveal: line fetch failed — retry next tick"); return
        }
        guard activeGeneration == generation,
              var m = state.active, m.dittoDisguise != nil, !m.dittoRevealed else { return }
        let latestFirstEvoThr = PokemonBalance.phaseThreshold(rarity: m.rarity, totalForms: m.totalForms, stageIndex: 0)
        guard m.usedAtStage >= latestFirstEvoThr else { return }
        let disguiseName = currentLine?.localizedName(m.baseID, state.language) ?? "#\(m.baseID)"
        let carryOver = max(0, m.usedAtStage - latestFirstEvoThr)   // 위장체 첫 진화 초과분 → 메타몽 성장 이월
        // 메타몽으로 전환 — rarity/forms 는 로드한 라인에서, isShiny/nature/dittoDisguise 는 유지.
        m.baseID = dittoLine.baseID
        let evolutionPlan = makeEvolutionPlan(from: dittoLine.tree, baseID: dittoLine.baseID)
        m.pathIDs = [dittoLine.baseID]
        m.plannedPathIDs = evolutionPlan
        m.stageIndex = 0
        m.rarity = dittoLine.rarity
        m.totalForms = evolutionPlan.count
        m.usedAtStage = carryOver
        m.dittoRevealed = true
        let shiny = m.isShiny
        state.active = m
        state.reconcileRepresentativeSelection()   // 위장 종만 근거였던 선택은 리빌과 함께 제거
        currentLine = dittoLine
        AppLog.write("ditto reveal: disguise=\(m.dittoDisguise ?? -1) → ditto rarity=\(dittoLine.rarity) shiny=\(shiny)")
        fireCelebration(.dittoReveal(shiny: shiny))
        displayState = .levelUp
        eventUntil = clock().addingTimeInterval(5)
        notifyCompanionEvent(shiny ? l.notifShinyDittoRevealTitle : l.notifDittoRevealTitle,
                             shiny ? l.notifShinyDittoRevealBody(disguiseName) : l.notifDittoRevealBody(disguiseName))
        save()
        applyUsage(0)   // 이월분으로 메타몽 졸업 재평가(rare 3B라 보통 즉시 졸업 아님)
    }

    private func loadCurrentLine() async {
        guard let a = state.active, currentLine == nil, !isHatching else { return }
        let generation = activeGeneration
        isHatching = true
        defer { isHatching = false }
        if let line = try? await provider.line(baseSpeciesID: a.baseID) {
            // await 중 사용량·민트 등 활성 상태는 계속 바뀔 수 있다. 요청 당시 스냅샷을 다시 쓰지 말고
            // 같은 개체가 아직 활성인 경우에만 최신 상태를 정규화한다.
            guard activeGeneration == generation,
                  let latest = state.active, latest.baseID == a.baseID, currentLine == nil else { return }
            state.active = normalizedEvolutionState(latest, from: line.tree)
            state.reconcileRepresentativeSelection()   // 손상 경로 정규화로 사라진 단계가 대표로 남지 않게
            currentLine = line
            save()   // 마이그레이션 선택을 사용량 재평가 전에 영속화해 재시작마다 다시 롤리지 않는다.
            applyUsage(0)   // 라인 미로딩 동안 적립된 사용량이 임계를 넘었으면 지금 진화 판정
        }
    }

    /// 부화 종 선정 — 하드코딩 풀 없이 PokéAPI 1~5세대 base 전체(329종)에서 가중 선택.
    ///   ① base 인덱스(id + capture_rate)를 GraphQL 1쿼리로 취득(30일 디스크 캐시 → 보통 0콜)
    ///   ② 가중치 = 공식 capture_rate 그대로(캐터피 255 vs 뮤츠 3 = 85:1, 전설군 ≈ 0.77%)
    ///      단, 이미 수집한 base 는 가중치 ½(미수집 부스트 — 재부화/shiny 사냥은 열어둠)
    ///   ③ 누적 가중치에서 정확히 1롤 — 루프/재롤 없음, 시간 상한 확정적
    /// 인덱스 취득 실패(오프라인 + 캐시 없음) 시 nil → 알 유지, 다음 갱신 틱 재시도.
    private func chooseBase() async -> Int? {
        let tier = state.eggTier
        if let full = try? await provider.baseSpeciesIndex(), !full.isEmpty {
            // 등급 보증 알은 후보를 먼저 좁힌다 — capture_rate 상한이 곧 등급 하한이므로
            // (Rarity.captureRateCeiling) 전설도 자연히 포함된다("희귀 이상"에 전설이 들어가는 게 정상).
            // 좁힌 결과가 비면 보증을 못 지키므로 전체 풀로 폴백하지 말고 알을 유지한다(다음 틱 재시도).
            let index = tier.map { t in full.filter { t.includes(captureRate: $0.captureRate) } } ?? full
            guard !index.isEmpty else {
                AppLog.write("hatch: no candidate for guaranteed \(tier?.rawValue ?? "none") — egg kept, retry next tick")
                return nil
            }
            let weights = index.map { e in
                state.collectedFinals.contains(where: { $0.hasPrefix("\(e.id):") })
                    ? max(1, e.captureRate / 2) : max(1, e.captureRate)
            }
            let total = weights.reduce(0, +)
            var r = Int(rng.next() % UInt64(total))
            for (i, w) in weights.enumerated() {
                r -= w
                if r < 0 { return index[i].id }
            }
            return index.last?.id   // 도달 불가(방어)
        }
        // GraphQL base 인덱스 엔드포인트 장애 → REST 폴백. 부화가 한 엔드포인트에 묶이지 않게.
        AppLog.write("hatch: base index unavailable — REST fallback")
        return await chooseBaseViaREST()
    }

    /// REST 폴백 — animated 에셋 지원 범위에서 무작위 id 를 뽑아 base 인지 확인(rejection sampling).
    /// GraphQL 인덱스가 죽어도 부화가 되게 한다. 가중치(capture_rate)는 생략 — 희귀도는 부화 후
    /// line() 이 실제 capture_rate 로 계산하므로 결과 개체의 등급은 정확하다. 인덱스 복구 시 가중 선택 재개.
    private func chooseBaseViaREST() async -> Int? {
        let tier = state.eggTier
        for attempt in 1...16 {
            let ids = PokemonAssets.animatedSpeciesIDs
            let id = Int(rng.next() % UInt64(ids.count)) + ids.lowerBound
            do {
                if let bs = try await provider.baseSpecies(id: id) {
                    // 등급 보증은 가중 경로와 **같은 기준**으로 여기서도 걸러야 한다 — 이 폴백만 빠지면
                    // GraphQL 인덱스 장애 때 보증이 조용히 깨진다. 못 찾으면 알 유지(구매 소멸 금지).
                    if let tier, !tier.includes(captureRate: bs.captureRate) { continue }
                    AppLog.write("hatch: REST fallback picked base \(id) (cap \(bs.captureRate), \(attempt) tries)")
                    return id
                }
                // nil = base 아님(진화 중간체) → 다음 시도
            } catch {
                AppLog.write("hatch: REST fallback network error — retry next tick: \(error)")
                return nil   // REST 도 불가 → 알 유지, 다음 update 틱 재시도
            }
        }
        AppLog.write("hatch: REST fallback exhausted 16 tries")
        return nil
    }

    private func computeState(burnTier: BurnTier, limitWarning: Bool, hasUsageData: Bool, today: Int) -> CompanionStateKind {
        if state.active == nil { return .egg }
        if justGraduated != nil || (eventUntil != nil && clock() < eventUntil!) { return .levelUp }
        if limitWarning { return .tired }
        if !hasUsageData || today == 0 { return .sleep }
        switch burnTier {
        case .idle: return .idle
        case .normal: return .working
        case .fast, .blazing: return .focus
        }
    }

    // MARK: 세이브 이전 (기기 교체)

    /// 덮어쓰기 확인에 쓸 "이 기기의 현재 진행" 요약.
    var transferSummary: SaveSummary { SaveSummary(state: state) }

    /// 저장 패널에 채울 기본 파일명. 봉투의 `exportedAt` 과 **같은 시계**에서 뽑는다 — 뷰가 따로
    /// `Date()` 를 부르면 파일명 날짜와 내용의 날짜가 갈릴 수 있다(자정 경계).
    var suggestedExportFileName: String { SaveTransfer.suggestedFileName(date: clock()) }

    /// 내보내기 페이로드. 파일 쓰기는 호출자(UI)가 사용자가 고른 위치에 수행한다.
    func exportedSaveData(appVersion: String, deviceName: String) throws -> Data {
        try SaveTransfer.encode(state: state, appVersion: appVersion, deviceName: deviceName, now: clock())
    }

    /// 검증된 세이브를 이 기기에 적용 — 기존 상태 백업 → 기기 기준 재정렬 → 저장 → 라인 재로딩.
    /// 백업을 못 남기면 **적용하지 않고** throw 한다 — 확인창이 "직전 상태가 남는다"고 약속하므로,
    /// 그 약속을 못 지키는 채로 덮어쓰면 사용자는 되돌릴 수단 없이 진행을 잃는다.
    func applySave(_ envelope: SaveEnvelope, todayTokensByProvider: [String: Int], todayDate: String,
                   hasUsageData: Bool) throws {
        try backupStateBeforeImport()
        state = SaveTransfer.rebasedForThisDevice(envelope.state,
                                                  current: state,
                                                  todayTokensByProvider: todayTokensByProvider,
                                                  todayDate: todayDate,
                                                  hasUsageData: hasUsageData)
        // 이전 개체 기준으로 진행 중이던 비동기·연출을 전부 무효화한다. activeGeneration 을 올리지
        // 않으면 먼저 떠 있던 라인 로드가 완료되며 새로 불러온 개체를 덮어쓴다.
        activeGeneration += 1
        currentLine = nil
        prefetchedLineID = nil
        justEvolvedTo = nil
        justGraduated = nil
        eventUntil = nil
        celebration = nil
        // 이전 개체 기준의 1회성 피드백(사탕 +XP·민트 성격)도 비운다 — 안 비우면 불러온 직후 남의
        // 개체에 대한 "+XP" 가 새 개체 위에 떠오른다.
        candyFeedbackAmount = 0
        mintFeedbackNature = nil
        displayState = state.active != nil ? .idle : .egg
        save()
        if state.active != nil { Task { await loadCurrentLine() } }
        AppLog.write("save imported from \(envelope.sourceDevice): dex=\(state.dex.count) lifetime=\(state.usedSinceInstall)")
    }

    /// 덮어쓰기 직전 현재 상태를 옆에 남긴다 — 잘못 불러왔을 때 되돌릴 수단.
    /// 슬롯을 하나만 쓰면 두 번째 불러오기가 **원본**을 덮어써, "잘못 불러왔으니 되돌린다"는 바로 그
    /// 상황에서 되돌릴 대상이 사라진다. 불러올 때마다 새 슬롯을 쓰고 오래된 것부터 정리한다.
    @discardableResult
    private func backupStateBeforeImport() throws -> URL {
        guard let data = try? JSONEncoder().encode(state) else { throw SaveTransferError.backupFailed }
        let dir = fileURL.deletingLastPathComponent()
        let backup = dir.appendingPathComponent(SaveTransfer.backupFileName(date: clock()))
        do {
            try data.write(to: backup, options: .atomic)
        } catch {
            AppLog.write("save import aborted — backup write failed: \(error)")
            throw SaveTransferError.backupFailed
        }
        pruneImportBackups(in: dir)
        return backup
    }

    /// 최근 N 개만 남기고 오래된 백업을 지운다. 파일명이 `yyyy-MM-dd-HHmmss` 라 사전순 = 시간순이다.
    private func pruneImportBackups(in dir: URL) {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return }
        let backups = names.filter { $0.hasPrefix(SaveTransfer.backupFilePrefix) }.sorted()
        guard backups.count > SaveTransfer.backupsToKeep else { return }
        for stale in backups.dropLast(SaveTransfer.backupsToKeep) {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(stale))
        }
    }

    // MARK: 영속
    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }   // 파일 없음 = 신규 설치
        guard let s = try? JSONDecoder().decode(CompanionState.self, from: data) else {
            // 디코드 실패(전면 손상/미래 스키마) → fresh 로 시작하되, 다음 save() 가 원본을 덮어써 영구
            // 유실되기 전에 .corrupt 로 보존해 수동 복구 여지를 남긴다(도감 per-entry 격리로 못 살린 경우 대비).
            let backup = fileURL.appendingPathExtension("corrupt")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.moveItem(at: fileURL, to: backup)
            AppLog.write("companion state decode failed — original backed up to \(backup.lastPathComponent), starting fresh")
            return
        }
        // 불러오기 경계와 같은 정규화를 디스크에서 읽을 때도 건다. 불러오기만 막으면 **이미 저장된**
        // 극단값은 그대로 남아, 앱이 매 기동마다 같은 값을 읽어 산술 트랩으로 죽는 상태를 못 벗어난다
        // (디코드는 *성공*하므로 위의 .corrupt 복구도 발동하지 않는다). 여기서 걸면 자가 복구된다.
        state = SaveTransfer.sanitized(s)
    }
    private func save() {
        refreshRepresentativeSubject()
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: fileURL, options: .atomic)   // 부분 쓰기 손상 방지(펫 상태)
    }
}
