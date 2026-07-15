import XCTest
@testable import PokeTokenBar

// MARK: 헬퍼 (CompanionTests 의 private 라인 헬퍼와 독립)

private func rcNode(_ id: Int, _ children: [EvoNode] = []) -> EvoNode { EvoNode(speciesID: id, children: children) }
private func rcLine(base: Int, tree: EvoNode, rarity: Rarity = .common) -> EvoLine {
    func ids(_ n: EvoNode) -> [Int] { [n.speciesID] + n.children.flatMap(ids) }
    var names: [Int: [String: String]] = [:]
    for id in ids(tree) { names[id] = ["en": "P\(id)", "ko": "포\(id)", "ja": "ポ\(id)"] }
    return EvoLine(baseID: base, tree: tree, rarity: rarity, names: names)
}
private let rcLinear3 = rcLine(base: 1, tree: rcNode(1, [rcNode(2, [rcNode(3)])]))   // 커먼 3형태: 125M/250M/375M
private let rcNoEvo = rcLine(base: 20, tree: rcNode(20))                              // 커먼 1형태: 750M 단일
private let rcNow = Date(timeIntervalSince1970: 1_700_000_000)

private func w(_ key: String, _ kind: WindowClass, _ util: Double, name: String = "T") -> CandyWindow {
    CandyWindow(key: key, name: name, kind: kind, utilization: util)
}

/// line() 이 throw 하는 provider — 라인 미로딩(오프라인/재시작 직후) 상태 재현용.
private struct RCLineThrows: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

// MARK: 순수 판정 (evaluateCandyGrants — 부수효과 분리)

@MainActor
final class CandyGrantEvaluationTests: XCTestCase {
    func testSessionGrantsOne() {
        var tier: [String: Int] = [:]
        let grants = CompanionStore.evaluateCandyGrants(windows: [w("s", .session, 100)], grantTier: &tier)
        XCTAssertEqual(grants.map(\.count), [1])
        XCTAssertEqual(tier["s"], 1)
    }

    func testWeeklyGrantsFive() {
        var tier: [String: Int] = [:]
        let grants = CompanionStore.evaluateCandyGrants(windows: [w("wk", .weekly, 100)], grantTier: &tier)
        XCTAssertEqual(grants.map(\.count), [RareCandy.weeklyGrant])
    }

    func testBelow100NoGrant() {
        var tier: [String: Int] = [:]
        let grants = CompanionStore.evaluateCandyGrants(windows: [w("s", .session, 99.9)], grantTier: &tier)
        XCTAssertTrue(grants.isEmpty)
        XCTAssertNil(tier["s"])
    }

    /// 같은 tier 유지 중엔 재지급 안 함(80·81·84… 억제의 사탕 버전).
    func testNoDoubleGrantWhileAt100() {
        var tier: [String: Int] = [:]
        _ = CompanionStore.evaluateCandyGrants(windows: [w("s", .session, 100)], grantTier: &tier)
        let again = CompanionStore.evaluateCandyGrants(windows: [w("s", .session, 100)], grantTier: &tier)
        XCTAssertTrue(again.isEmpty, "이미 지급한 창은 재지급 안 함")
    }

    /// 100% 아래로 내려가면 재무장(맵에서 제거) → 다시 채우면 재지급.
    func testRearmAfterDropBelow100() {
        var tier: [String: Int] = [:]
        _ = CompanionStore.evaluateCandyGrants(windows: [w("s", .session, 100)], grantTier: &tier)
        _ = CompanionStore.evaluateCandyGrants(windows: [w("s", .session, 40)], grantTier: &tier)
        XCTAssertNil(tier["s"], "경고선 아래 → 제거(재무장)")
        let regrant = CompanionStore.evaluateCandyGrants(windows: [w("s", .session, 100)], grantTier: &tier)
        XCTAssertEqual(regrant.map(\.count), [1], "리셋 후 다시 채우면 재지급")
    }

    /// 세션+주간+미달 혼합 — 세션 1 + 주간 5, 미달 창은 무시.
    func testMixedWindows() {
        var tier: [String: Int] = [:]
        let grants = CompanionStore.evaluateCandyGrants(windows: [
            w("claude.fiveHour", .session, 100),
            w("claude.sevenDay", .weekly, 100),
            w("codex.codex.primary", .session, 50),
        ], grantTier: &tier)
        XCTAssertEqual(grants.reduce(0) { $0 + $1.count }, 1 + RareCandy.weeklyGrant)
    }

    /// 지급 grant 는 발화 창 이름을 담는다(알림 "왜 받는지").
    func testGrantCarriesWindowName() {
        var tier: [String: Int] = [:]
        let grants = CompanionStore.evaluateCandyGrants(
            windows: [w("claude.fiveHour", .session, 100, name: "Claude 5시간 세션")], grantTier: &tier)
        XCTAssertEqual(grants.first?.windowName, "Claude 5시간 세션")
    }

    /// Codex 창 분류 — ≤24h=세션, 초과=주간, 미상=세션.
    func testCodexWindowClassification() {
        XCTAssertEqual(UsageStore.windowClass(minutes: 300), .session)     // 5h
        XCTAssertEqual(UsageStore.windowClass(minutes: 1440), .session)    // 24h 경계
        XCTAssertEqual(UsageStore.windowClass(minutes: 10_080), .weekly)   // 7d
        XCTAssertEqual(UsageStore.windowClass(minutes: nil), .session)
    }
}

// MARK: 하위호환 디코딩

final class InventoryDecodeTests: XCTestCase {
    /// 구버전 저장(인벤토리 키 없음)도 깨지지 않고 기본값으로 로드.
    func testDecodesWithoutInventoryFields() throws {
        let json = #"{"installBaselineSet":true,"usedSinceInstall":5,"lastDate":"d","dex":[],"language":"ko"}"#
        let s = try JSONDecoder().decode(CompanionState.self, from: Data(json.utf8))
        XCTAssertEqual(s.inventory, [:])
        XCTAssertEqual(s.candyGrantTier, [:])
        XCTAssertFalse(s.candyFeatureSeeded)
    }

    func testInventoryRoundTrip() throws {
        var st = CompanionState()
        st.inventory = ["rareCandy": 3]
        st.candyGrantTier = ["claude.fiveHour": 1]
        st.candyFeatureSeeded = true
        let round = try JSONDecoder().decode(CompanionState.self, from: JSONEncoder().encode(st))
        XCTAssertEqual(round.inventory, ["rareCandy": 3])
        XCTAssertEqual(round.candyGrantTier, ["claude.fiveHour": 1])
        XCTAssertTrue(round.candyFeatureSeeded)
    }
}

// MARK: 지급 (grantCandies — 시드·영속) + 사용 (useRareCandy)

@MainActor
final class RareCandyStoreTests: XCTestCase {
    private func store(_ line: EvoLine, seed: UInt64 = 7) -> CompanionStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rc-\(UUID().uuidString).json")
        return CompanionStore(provider: StubProvider(value: line), clock: { rcNow }, fileURL: url, rng: SeededRNG(seed: seed))
    }

    /// 시드+지급 헬퍼 — 빈 창으로 시드 완료 후, 유니크 세션 창을 100%로 올려 n개 지급.
    private func giveCandies(_ s: CompanionStore, _ n: Int) {
        s.grantCandies(from: [], limitsReady: true)   // 시드(지급 0)
        for i in 0..<n {
            s.grantCandies(from: [w("test.session.\(i)", .session, 100)], limitsReady: true)
        }
    }

    // MARK: 지급

    /// 첫 실행: 이미 100%인 창은 소급 지급 안 하고 tier 시드만(candyFeatureSeeded=true).
    func testFirstRunSeedsWithoutGranting() {
        let s = store(rcLinear3)
        s.grantCandies(from: [w("claude.fiveHour", .session, 100)], limitsReady: true)
        XCTAssertEqual(s.rareCandyCount, 0, "첫 실행 100% 창은 소급 지급 안 함")
        XCTAssertTrue(s.state.candyFeatureSeeded)
        XCTAssertEqual(s.state.candyGrantTier["claude.fiveHour"], 1, "tier 시드됨")
    }

    /// 시드 후 같은 창이 계속 100%여도 재지급 없음.
    func testNoGrantForAlreadySeededWindow() {
        let s = store(rcLinear3)
        s.grantCandies(from: [w("claude.fiveHour", .session, 100)], limitsReady: true)   // 시드
        s.grantCandies(from: [w("claude.fiveHour", .session, 100)], limitsReady: true)   // 재호출
        XCTAssertEqual(s.rareCandyCount, 0)
    }

    /// 한도 미로딩(limitsReady=false)이면 시드조차 하지 않는다(다음 refresh 재시도).
    func testNoSeedWhenLimitsNotReady() {
        let s = store(rcLinear3)
        s.grantCandies(from: [w("claude.fiveHour", .session, 100)], limitsReady: false)
        XCTAssertFalse(s.state.candyFeatureSeeded)
        XCTAssertEqual(s.rareCandyCount, 0)
    }

    /// 시드 후 새 창이 100%를 새로 넘으면 지급 — 세션 1개.
    func testSessionGrantAfterSeed() {
        let s = store(rcLinear3)
        s.grantCandies(from: [], limitsReady: true)   // 시드
        s.grantCandies(from: [w("claude.fiveHour", .session, 100)], limitsReady: true)
        XCTAssertEqual(s.rareCandyCount, 1)
    }

    /// 주간 창은 5개.
    func testWeeklyGrantsFiveCandies() {
        let s = store(rcLinear3)
        s.grantCandies(from: [], limitsReady: true)
        s.grantCandies(from: [w("claude.sevenDay", .weekly, 100)], limitsReady: true)
        XCTAssertEqual(s.rareCandyCount, RareCandy.weeklyGrant)
    }

    /// [핵심 회귀] 지급 tier 는 영속 — 재시작(같은 파일 재로드) 후 같은 100% 창이 재지급되지 않는다.
    /// (notifiedTier 인메모리와 달리 candyGrantTier 는 파일에 저장돼야 함.)
    func testGrantTierPersistsAcrossRestartNoDoubleGrant() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rc-persist-\(UUID().uuidString).json")
        let s1 = CompanionStore(provider: StubProvider(value: rcLinear3), clock: { rcNow }, fileURL: url, rng: SeededRNG(seed: 1))
        s1.grantCandies(from: [], limitsReady: true)                                        // 시드
        s1.grantCandies(from: [w("claude.fiveHour", .session, 100)], limitsReady: true)     // 지급 1
        XCTAssertEqual(s1.rareCandyCount, 1)

        // 재시작: 같은 파일 로드
        let s2 = CompanionStore(provider: StubProvider(value: rcLinear3), clock: { rcNow }, fileURL: url, rng: SeededRNG(seed: 1))
        XCTAssertEqual(s2.rareCandyCount, 1, "인벤토리 영속")
        XCTAssertEqual(s2.state.candyGrantTier["claude.fiveHour"], 1, "tier 영속")
        // 여전히 100%인 같은 창 → 재지급 없어야 함
        s2.grantCandies(from: [w("claude.fiveHour", .session, 100)], limitsReady: true)
        XCTAssertEqual(s2.rareCandyCount, 1, "재시작 후 같은 100% 창의 재지급 금지(무한지급 익스플로잇 차단)")
    }

    /// [회귀] 재무장(100%→아래로)으로 grantTier 에서 제거된 것이 영속돼야 재시작 후 지급 누락이 없다.
    /// 지급 없이 재무장만 발생한 경우에도 save() 돼야 한다(과거: grants 비면 save 스킵 → stale tier 잔존).
    func testRearmPersistsAcrossRestart() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rc-rearm-\(UUID().uuidString).json")
        let s1 = CompanionStore(provider: StubProvider(value: rcLinear3), clock: { rcNow }, fileURL: url, rng: SeededRNG(seed: 1))
        s1.grantCandies(from: [], limitsReady: true)                                      // 시드
        s1.grantCandies(from: [w("claude.fiveHour", .session, 100)], limitsReady: true)   // 지급 1 (tier=1)
        XCTAssertEqual(s1.rareCandyCount, 1)
        s1.grantCandies(from: [w("claude.fiveHour", .session, 40)], limitsReady: true)    // 재무장(제거) — 지급 0
        XCTAssertNil(s1.state.candyGrantTier["claude.fiveHour"])

        // 재시작: 재무장이 영속됐어야 함
        let s2 = CompanionStore(provider: StubProvider(value: rcLinear3), clock: { rcNow }, fileURL: url, rng: SeededRNG(seed: 1))
        XCTAssertNil(s2.state.candyGrantTier["claude.fiveHour"], "재무장이 영속돼야 함")
        // 다시 100% → 재지급(누락 없음)
        s2.grantCandies(from: [w("claude.fiveHour", .session, 100)], limitsReady: true)
        XCTAssertEqual(s2.rareCandyCount, 2, "재무장 후 재도달은 재지급돼야 함(지급 누락 회귀 방지)")
    }

    // MARK: 사용

    /// 사탕 XP(100M) < 최소 임계(125M) → 진화 못 시키는 케이스는 부분 진행(.progressed), 통계 불변.
    func testUseProgressesWithoutEvolution() async {
        let s = store(rcLinear3)
        await s.hatch(baseID: 1)
        giveCandies(s, 1)
        XCTAssertEqual(s.rareCandyCount, 1)
        let before = s.state.usedSinceInstall
        let result = s.useRareCandy()
        XCTAssertEqual(result, .progressed)
        XCTAssertEqual(s.state.active?.usedAtStage, RareCandy.xp)
        XCTAssertEqual(s.state.active?.stageIndex, 0)
        XCTAssertEqual(s.rareCandyCount, 0, "재고 1 소모")
        XCTAssertEqual(s.state.usedSinceInstall, before, "사탕 XP 는 실사용 통계에 안 잡힘")
    }

    /// 잔여가 사탕XP 이하인 단계에서 사용 → 정확히 1단계 진화.
    func testUseEvolvesWhenCrossingThreshold() async {
        let s = store(rcLinear3)
        await s.hatch(baseID: 1)
        s.applyUsage(50_000_000)   // stage0(125M) 잔여 75M ≤ 100M
        giveCandies(s, 1)
        let result = s.useRareCandy()
        XCTAssertEqual(result, .evolved)
        XCTAssertEqual(s.currentSpeciesID, 2)
        XCTAssertEqual(s.state.active?.stageIndex, 1)
    }

    /// [불변식] 사탕 1개 = 최대 1단계 — 임계 직전(124M)에서 써도 2단계 연쇄 안 됨.
    func testSingleCandyAdvancesAtMostOneStage() async {
        let s = store(rcLinear3)
        await s.hatch(baseID: 1)
        s.applyUsage(124_000_000)   // stage0 임계 직전
        giveCandies(s, 1)
        _ = s.useRareCandy()        // +100M → 224M: stage0(125M) 1회만, stage1(250M) 미달
        XCTAssertEqual(s.state.active?.stageIndex, 1, "최대 1단계")
    }

    /// 최종단계에서 잔여가 사탕XP 이하면 졸업 → 도감 + 새 알.
    func testUseGraduatesFinalStage() async {
        let s = store(rcNoEvo)
        await s.hatch(baseID: 20)
        s.applyUsage(700_000_000)   // 졸업 총량 750M 잔여 50M ≤ 100M
        giveCandies(s, 1)
        let result = s.useRareCandy()
        XCTAssertEqual(result, .graduated)
        XCTAssertNil(s.state.active)
        XCTAssertEqual(s.dexEntries.count, 1)
    }

    /// 알(부화 전)에는 사용 불가 — 재고가 있어도 소모되지 않는다.
    func testCannotUseOnEgg() {
        let s = store(rcLinear3)
        giveCandies(s, 2)
        XCTAssertTrue(s.isEgg)
        XCTAssertFalse(s.canUseRareCandy)
        XCTAssertEqual(s.useRareCandy(), .unavailable)
        XCTAssertEqual(s.rareCandyCount, 2, "알 상태에선 소모 안 됨")
    }

    /// 재고 0이면 사용 불가.
    func testCannotUseWithoutStock() async {
        let s = store(rcLinear3)
        await s.hatch(baseID: 1)
        XCTAssertEqual(s.rareCandyCount, 0)
        XCTAssertFalse(s.canUseRareCandy)
        XCTAssertEqual(s.useRareCandy(), .unavailable)
    }

    /// [회귀 가드] 활성 포켓몬이 있어도 라인 미로딩(재시작 직후·오프라인)이면 사용 불가 —
    /// 진화 없이 XP만 적립되는 것 방지. 재고가 있어도 소모되지 않는다.
    func testCannotUseWhileLineUnloaded() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rc-unloaded-\(UUID().uuidString).json")
        // 활성 포켓몬 + 사탕 1 + 시드완료 상태를 저장 → RCLineThrows 로 로드하면 currentLine 이 nil.
        let json = #"{"installBaselineSet":true,"lastDate":"d1","active":{"baseID":1,"pathIDs":[1],"stageIndex":0,"usedAtStage":0,"rarity":"common","totalForms":3},"inventory":{"rareCandy":1},"candyFeatureSeeded":true,"dex":[],"collectedFinals":[]}"#
        try? json.data(using: .utf8)!.write(to: url)
        let s = CompanionStore(provider: RCLineThrows(), clock: { rcNow }, fileURL: url, rng: SeededRNG(seed: 1))
        XCTAssertNotNil(s.state.active, "활성 포켓몬 로드")
        XCTAssertNil(s.currentLine, "라인 미로딩(throws)")
        XCTAssertEqual(s.rareCandyCount, 1)
        XCTAssertFalse(s.canUseRareCandy)
        XCTAssertEqual(s.useRareCandy(), .unavailable)
        XCTAssertEqual(s.rareCandyCount, 1, "라인 미로딩 시 사탕 소모 안 됨")
    }

    /// 사용 시 "+XP" 피드백 seq 가 증가(진화 없이 부분 진행이어도).
    func testUseBumpsCandyFeedback() async {
        let s = store(rcLinear3)
        await s.hatch(baseID: 1)
        giveCandies(s, 1)
        let before = s.candyFeedbackSeq
        _ = s.useRareCandy()
        XCTAssertEqual(s.candyFeedbackSeq, before + 1)
        XCTAssertEqual(s.candyFeedbackAmount, RareCandy.xp)
    }

    /// ownedItems 는 개수>0 아이템만 노출.
    func testOwnedItemsReflectsStock() async {
        let s = store(rcLinear3)
        XCTAssertTrue(s.ownedItems.isEmpty)
        giveCandies(s, 3)
        XCTAssertEqual(s.ownedItems.map(\.kind), [.rareCandy])
        XCTAssertEqual(s.ownedItems.first?.count, 3)
    }

    /// 데모 시나리오(구구 3형태, usedAtStage 100M, 사탕 3): 진화 → 부분성장 → 진화, 그 뒤 재고 0.
    func testSequentialCandyUseMatchesDemo() async {
        let s = store(rcLinear3)
        await s.hatch(baseID: 1)
        s.applyUsage(100_000_000)                      // stage0(125M) 도달 전
        giveCandies(s, 3)
        XCTAssertEqual(s.useRareCandy(), .evolved)     // 200M ≥125M → stage1, 이월 75M
        XCTAssertEqual(s.state.active?.stageIndex, 1)
        XCTAssertEqual(s.useRareCandy(), .progressed)  // 175M <250M → 부분성장
        XCTAssertEqual(s.state.active?.stageIndex, 1)
        XCTAssertEqual(s.useRareCandy(), .evolved)     // 275M ≥250M → stage2
        XCTAssertEqual(s.state.active?.stageIndex, 2)
        XCTAssertEqual(s.rareCandyCount, 0)
    }

    /// "+XP" 1회성 store 계약 — 사용 후 amount>0, consume 후 0(재렌더 재생 방지의 핵심).
    func testConsumeCandyFeedbackResets() async {
        let s = store(rcLinear3)
        await s.hatch(baseID: 1)
        giveCandies(s, 1)
        _ = s.useRareCandy()
        XCTAssertEqual(s.candyFeedbackAmount, RareCandy.xp)
        s.consumeCandyFeedback()
        XCTAssertEqual(s.candyFeedbackAmount, 0, "consume 후 0 — CompanionHeader 재마운트 시 재생 안 됨")
    }
}

// MARK: 지급 통합 (UsageStore 한도 → candyEligibleWindows → grantCandies)
// "특정 조건(한도 100%)에서 사탕 지급" — 수동으로 열기 힘든 경로를 주입 한도로 결정적 검증.

private struct RCFakeClaude: ClaudeLimitsProviding {
    var status: LimitStatus?
    func fetch(allowKeychainPrompt: Bool) async throws -> LimitStatus {
        guard let status else { throw LimitsError.keychainInteractionNotAllowed }
        return status
    }
}
private struct RCFakeCodex: CodexLimitsProviding {
    var status: CodexRateLimitStatus?
    func fetch() async throws -> CodexRateLimitStatus? { status }
}
private final class RCFakeStatus: ProviderStatusProviding, @unchecked Sendable {
    func fetch() async -> [String: ProviderStatus] { [:] }
}
private final class RCFakeProvider: UsageProvider, @unchecked Sendable {
    let id: String
    let displayName: String
    nonisolated(unsafe) var daily: DailyUsage?
    init(id: String, displayName: String, daily: DailyUsage?) {
        self.id = id; self.displayName = displayName; self.daily = daily
    }
    func fetchDaily() async throws -> DailyUsage? { daily }
    func fetchEnrichment() async -> ProviderEnrichment { ProviderEnrichment() }
}
private func rcDaily(_ tokens: Int) -> DailyUsage {
    DailyUsage(date: LocalUsageReader.todayKey(), inputTokens: 0, outputTokens: 0,
               cacheCreationTokens: 0, cacheReadTokens: 0, totalTokens: tokens, totalCost: 0)
}
private func rcClaude(fiveHour: Double? = nil, sevenDay: Double? = nil,
                      opus: Double? = nil, sonnet: Double? = nil) -> LimitStatus {
    var parts: [String] = []
    if let fiveHour { parts.append("\"five_hour\":{\"utilization\":\(fiveHour)}") }
    if let sevenDay { parts.append("\"seven_day\":{\"utilization\":\(sevenDay)}") }
    if let opus { parts.append("\"seven_day_opus\":{\"utilization\":\(opus)}") }
    if let sonnet { parts.append("\"seven_day_sonnet\":{\"utilization\":\(sonnet)}") }
    return try! JSONDecoder().decode(LimitStatus.self, from: Data("{\(parts.joined(separator: ","))}".utf8))
}
private func rcCodex(primary: Int? = nil, secondary: Int? = nil, individual: Int? = nil) -> CodexRateLimitStatus {
    func win(_ p: Int, _ mins: Int) -> String { "{\"usedPercent\":\(p),\"windowDurationMins\":\(mins)}" }
    var parts: [String] = []
    if let primary { parts.append("\"primary\":\(win(primary, 300))") }
    if let secondary { parts.append("\"secondary\":\(win(secondary, 10080))") }
    if let individual {
        parts.append("\"individualLimit\":{\"limit\":\"$10\",\"remainingPercent\":\(100 - individual),\"resetsAt\":9999999999,\"used\":\"$1\"}")
    }
    return try! JSONDecoder().decode(CodexRateLimitStatus.self, from: Data("{\"rateLimits\":{\(parts.joined(separator: ","))}}".utf8))
}

@MainActor
final class RareCandyGrantIntegrationTests: XCTestCase {
    // nonisolated(unsafe): sync setUp/tearDown 은 릴리스 Swift 에서 nonisolated → main-actor 프로퍼티
    // 접근이 컴파일 에러. XCTest 인스턴스별 직렬 실행이라 데이터 레이스 없음. (UsageStoreTests 와 동일)
    nonisolated(unsafe) private var defaults: UserDefaults!
    nonisolated(unsafe) private var suiteName: String!
    override func setUp() {
        super.setUp()
        suiteName = "rc-int-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }
    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func usage(claude: LimitStatus? = nil, codex: CodexRateLimitStatus? = nil,
                       providers: [any UsageProvider]? = nil) -> UsageStore {
        UsageStore(
            providers: providers ?? [RCFakeProvider(id: "claude_code", displayName: "Claude Code", daily: rcDaily(1_000))],
            claudeLimitsProvider: RCFakeClaude(status: claude),
            codexLimitsProvider: RCFakeCodex(status: codex),
            statusProvider: RCFakeStatus(),
            autoRefresh: false, defaults: defaults)
    }
    private func companion() -> CompanionStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rc-int-\(UUID().uuidString).json")
        return CompanionStore(provider: StubProvider(value: rcLinear3), clock: { rcNow }, fileURL: url, rng: SeededRNG(seed: 7))
    }

    // MARK: candyEligibleWindows 구성

    func testEligibleWindowsClaudeSessionAndWeekly() async {
        let store = usage(claude: rcClaude(fiveHour: 100, sevenDay: 100))
        await store.refresh(scheduleEmptyRetry: false)
        let byKey = Dictionary(uniqueKeysWithValues: store.candyEligibleWindows.map { ($0.key, $0) })
        XCTAssertEqual(byKey["claude.fiveHour"]?.kind, .session)
        XCTAssertEqual(byKey["claude.fiveHour"]?.utilization, 100)
        XCTAssertEqual(byKey["claude.sevenDay"]?.kind, .weekly)
        XCTAssertEqual(store.candyEligibleWindows.count, 2)
    }

    /// Opus/Sonnet 주간은 지급 대상에서 제외(헤드라인 창 중복 방지).
    func testEligibleWindowsExcludeOpusSonnet() async {
        let store = usage(claude: rcClaude(fiveHour: 100, opus: 100, sonnet: 100))
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(Set(store.candyEligibleWindows.map(\.key)), ["claude.fiveHour"], "Opus/Sonnet 주간 제외")
    }

    /// Codex primary=세션, secondary=주간. individual spend limit 은 제외.
    func testEligibleWindowsCodexClassificationExcludesSpend() async {
        let store = usage(codex: rcCodex(primary: 100, secondary: 100, individual: 100),
                          providers: [RCFakeProvider(id: "codex", displayName: "Codex", daily: rcDaily(1_000))])
        await store.refresh(scheduleEmptyRetry: false)
        let byKey = Dictionary(uniqueKeysWithValues: store.candyEligibleWindows.map { ($0.key, $0.kind) })
        XCTAssertEqual(byKey["codex.codex.primary"], .session)
        XCTAssertEqual(byKey["codex.codex.secondary"], .weekly)
        XCTAssertFalse(store.candyEligibleWindows.contains { $0.key.contains("individual") }, "spend limit 제외")
    }

    /// Gemini 는 공식 한도 신호가 없어 창 목록에 안 나온다(제외 설계).
    func testEligibleWindowsExcludeGemini() async {
        let store = usage(claude: rcClaude(fiveHour: 100),
                          providers: [RCFakeProvider(id: "gemini", displayName: "Gemini", daily: rcDaily(9_000)),
                                      RCFakeProvider(id: "claude_code", displayName: "Claude Code", daily: rcDaily(1_000))])
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertFalse(store.candyEligibleWindows.contains { $0.key.contains("gemini") })
    }

    func testLimitsReadyReflectsLoad() async {
        let store = usage(claude: rcClaude(fiveHour: 50))
        XCTAssertFalse(store.limitsReady, "refresh 전")
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertTrue(store.limitsReady, "한도 로드 후")
    }

    // MARK: 통합 — 한도 100% → 지급

    /// [핵심] 시드된 상태에서 Claude 5h 100% 도달 → 세션 사탕 1개(수동으로 못 여는 경로 검증).
    func testClaudeSessionLimitGrantsOneCandy() async {
        let c = companion()
        c.grantCandies(from: [], limitsReady: true)   // 시드(현재 100% 창 없음)
        let store = usage(claude: rcClaude(fiveHour: 100))
        await store.refresh(scheduleEmptyRetry: false)
        c.grantCandies(from: store.candyEligibleWindows, limitsReady: store.limitsReady)
        XCTAssertEqual(c.rareCandyCount, 1)
    }

    /// 주간 100% → 5개.
    func testClaudeWeeklyLimitGrantsFive() async {
        let c = companion()
        c.grantCandies(from: [], limitsReady: true)
        let store = usage(claude: rcClaude(sevenDay: 100))
        await store.refresh(scheduleEmptyRetry: false)
        c.grantCandies(from: store.candyEligibleWindows, limitsReady: store.limitsReady)
        XCTAssertEqual(c.rareCandyCount, RareCandy.weeklyGrant)
    }

    /// 세션+주간 동시 100% → 1 + 5.
    func testSessionAndWeeklyTogetherGrantSix() async {
        let c = companion()
        c.grantCandies(from: [], limitsReady: true)
        let store = usage(claude: rcClaude(fiveHour: 100, sevenDay: 100))
        await store.refresh(scheduleEmptyRetry: false)
        c.grantCandies(from: store.candyEligibleWindows, limitsReady: store.limitsReady)
        XCTAssertEqual(c.rareCandyCount, 1 + RareCandy.weeklyGrant)
    }

    /// Codex 세션(primary) 100% → 1개(전 프로바이더 지급).
    func testCodexPrimaryLimitGrantsOne() async {
        let c = companion()
        c.grantCandies(from: [], limitsReady: true)
        let store = usage(codex: rcCodex(primary: 100),
                          providers: [RCFakeProvider(id: "codex", displayName: "Codex", daily: rcDaily(1_000))])
        await store.refresh(scheduleEmptyRetry: false)
        c.grantCandies(from: store.candyEligibleWindows, limitsReady: store.limitsReady)
        XCTAssertEqual(c.rareCandyCount, 1)
    }

    /// 99.9% 는 지급 없음(엄격히 100% 이상).
    func testJustUnder100NoGrant() async {
        let c = companion()
        c.grantCandies(from: [], limitsReady: true)
        let store = usage(claude: rcClaude(fiveHour: 99.9))
        await store.refresh(scheduleEmptyRetry: false)
        c.grantCandies(from: store.candyEligibleWindows, limitsReady: store.limitsReady)
        XCTAssertEqual(c.rareCandyCount, 0)
    }

    /// 첫 실행(미시드) + 이미 100% → 소급 지급 안 함(시드만).
    func testFirstRunAt100SeedsNoGrant() async {
        let c = companion()   // candyFeatureSeeded=false
        let store = usage(claude: rcClaude(fiveHour: 100))
        await store.refresh(scheduleEmptyRetry: false)
        c.grantCandies(from: store.candyEligibleWindows, limitsReady: store.limitsReady)
        XCTAssertEqual(c.rareCandyCount, 0, "업데이트 직후 이미 100%인 창은 소급 지급 안 함")
        XCTAssertTrue(c.state.candyFeatureSeeded)
        c.grantCandies(from: store.candyEligibleWindows, limitsReady: store.limitsReady)
        XCTAssertEqual(c.rareCandyCount, 0, "시드된 창은 재호출에도 지급 없음")
    }

    /// 지급은 엣지 1회 — 같은 100% 창을 여러 refresh 에 반복 평가해도 1개만.
    func testRepeatedRefreshGrantsOnce() async {
        let c = companion()
        c.grantCandies(from: [], limitsReady: true)
        let store = usage(claude: rcClaude(fiveHour: 100))
        await store.refresh(scheduleEmptyRetry: false)
        for _ in 0..<5 { c.grantCandies(from: store.candyEligibleWindows, limitsReady: store.limitsReady) }
        XCTAssertEqual(c.rareCandyCount, 1, "여러 번 호출해도 엣지 1회만")
    }

    /// 지급 알림 대상 창 이름이 세션/주간 모두 candyEligibleWindows 에 실제로 담기는지(본문 "왜 받는지").
    /// Claude: "Claude 5시간 세션"/"Claude 주간". Codex: "Codex 5시간 세션"/"Codex 주간".
    func testEligibleWindowNamesForNotificationBody() async {
        // 로케일 무관하게 한국어 창 이름 검증 — CI 는 영어 로케일이라 명시 고정 필요.
        let claudeStore = usage(claude: rcClaude(fiveHour: 100, sevenDay: 100))
        claudeStore.localizationLanguage = .ko
        await claudeStore.refresh(scheduleEmptyRetry: false)
        let claudeNames = Dictionary(uniqueKeysWithValues: claudeStore.candyEligibleWindows.map { ($0.key, $0.name) })
        XCTAssertEqual(claudeNames["claude.fiveHour"], "Claude 5시간 세션")
        XCTAssertEqual(claudeNames["claude.sevenDay"], "Claude 주간")

        let codexStore = usage(codex: rcCodex(primary: 100, secondary: 100),
                               providers: [RCFakeProvider(id: "codex", displayName: "Codex", daily: rcDaily(1_000))])
        codexStore.localizationLanguage = .ko
        await codexStore.refresh(scheduleEmptyRetry: false)
        let codexNames = Dictionary(uniqueKeysWithValues: codexStore.candyEligibleWindows.map { ($0.key, $0.name) })
        XCTAssertEqual(codexNames["codex.codex.primary"], "Codex 5시간 세션")
        XCTAssertEqual(codexNames["codex.codex.secondary"], "Codex 주간")
    }

    /// utilization nil(five_hour 존재하나 값 없음) 창은 지급 대상 제외 — 옵셔널 tautology 방지
    /// (CompanionState "값이 있나"는 의미값으로 검사 — CLAUDE.md 회귀 부류).
    func testEligibleWindowsSkipNilUtilization() async {
        let claude = try! JSONDecoder().decode(LimitStatus.self, from: Data(#"{"five_hour":{}}"#.utf8))
        let store = usage(claude: claude)
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertNil(store.limits?.fiveHour?.utilization, "five_hour 는 있으나 utilization 은 nil")
        XCTAssertTrue(store.candyEligibleWindows.isEmpty, "utilization nil → 지급 창 아님")
    }

    /// 사탕 임계(100)와 알림 임계(crit 95)는 분리 — 97%는 경고는 켜지되 사탕은 지급 0.
    /// (두 임계가 리팩터에서 조용히 수렴하지 않도록 잠금.)
    func testCandyThresholdSeparateFromAlertThreshold() async {
        let c = companion()
        c.grantCandies(from: [], limitsReady: true)   // 시드(현재 100% 없음)
        let store = usage(claude: rcClaude(fiveHour: 97))
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertTrue(store.isLimitWarning, "97% ≥ crit 95 → 한도 경고 켜짐")
        c.grantCandies(from: store.candyEligibleWindows, limitsReady: store.limitsReady)
        XCTAssertEqual(c.rareCandyCount, 0, "97% < 사탕 임계 100 → 지급 없음")
    }

    /// [문서화된 한계 잠금] 첫 시드에 한 프로바이더만 로드되면 그 프로바이더만 시드된다.
    /// 이후 늦게 등장한 프로바이더가 이미 100%면 소급 지급된다(정상 경로는 둘 다 await 후라 원자적).
    /// 이 동작을 잠가, 향후 "수정"이 의식적 선택이 되게 한다.
    func testStaggeredProviderSeedRetroactiveGrant() async {
        let c = companion()
        let claudeStore = usage(claude: rcClaude(fiveHour: 50))   // 시드 시점 Claude 는 100 아님
        await claudeStore.refresh(scheduleEmptyRetry: false)
        c.grantCandies(from: claudeStore.candyEligibleWindows, limitsReady: claudeStore.limitsReady)  // 시드(Claude만)
        XCTAssertTrue(c.state.candyFeatureSeeded)
        XCTAssertEqual(c.rareCandyCount, 0)
        // 이후: Codex 가 이미 100% 인 채 처음 등장 → 시드 안 돼 소급 지급
        let codexStore = usage(codex: rcCodex(primary: 100),
                               providers: [RCFakeProvider(id: "codex", displayName: "Codex", daily: rcDaily(1_000))])
        await codexStore.refresh(scheduleEmptyRetry: false)
        c.grantCandies(from: codexStore.candyEligibleWindows, limitsReady: codexStore.limitsReady)
        XCTAssertEqual(c.rareCandyCount, 1, "문서화된 한계: 늦게 등장한 100% 창은 소급 지급됨")
    }
}

// MARK: 알림 문구 치환 (제목 개수 · 본문 창 이름 — Claude/Codex 공통)

final class CandyNotificationCopyTests: XCTestCase {
    /// 제목에 개수(1개·5개)와 아이템명이 들어간다.
    func testTitleIncludesCountAndItem() {
        let l = L(.ko)
        let one = l.notifCandyTitle(item: l.itemName(.rareCandy), count: 1)
        let five = l.notifCandyTitle(item: l.itemName(.rareCandy), count: 5)
        XCTAssertTrue(one.contains("이상한 사탕"))
        XCTAssertTrue(one.contains("1개"), one)
        XCTAssertTrue(five.contains("5개"), five)
    }

    /// 본문은 넘겨받은 창 이름을 그대로 앞에 붙인다 — Claude·Codex 어느 창이든 자연스럽게 뜬다.
    func testBodyPrefixesWindowNameClaudeAndCodex() {
        let l = L(.ko)
        XCTAssertTrue(l.notifCandyBody(window: "Claude 5시간 세션").hasPrefix("Claude 5시간 세션 토큰 한도를 다 채웠"))
        XCTAssertTrue(l.notifCandyBody(window: "Claude 주간").hasPrefix("Claude 주간 토큰 한도를 다 채웠"))
        XCTAssertTrue(l.notifCandyBody(window: "Codex 5시간 세션").hasPrefix("Codex 5시간 세션 토큰 한도를 다 채웠"))
        XCTAssertTrue(l.notifCandyBody(window: "Codex 주간").hasPrefix("Codex 주간 토큰 한도를 다 채웠"))
    }

    /// 3개 언어 모두 개수 치환 + 비어있지 않음.
    func testTitleLocalizedAllLanguages() {
        for lang in AppLanguage.allCases {
            let l = L(lang)
            let title = l.notifCandyTitle(item: l.itemName(.rareCandy), count: 3)
            XCTAssertTrue(title.contains("3"), "\(lang): \(title)")
            XCTAssertFalse(title.isEmpty)
        }
    }
}
