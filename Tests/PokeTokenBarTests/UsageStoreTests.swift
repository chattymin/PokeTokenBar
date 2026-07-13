import XCTest
@testable import PokeTokenBar

// UsageStore 의 refresh 파이프라인 + 파생 표시값을 주입 스텁으로 결정적 검증.
// (실제 ccusage/Keychain/Codex 바이너리 없이 — 위협 모델: 1인 로컬, CI 없음)

// MARK: 스텁

private enum StubError: Error { case boom }

/// 호출 후에도 동작을 바꿀 수 있는 usage provider (실패 전환 테스트용). 단일 스레드 테스트 한정.
private final class FakeUsageProvider: UsageProvider, @unchecked Sendable {
    let id: String
    let displayName: String
    nonisolated(unsafe) var daily: DailyUsage?
    nonisolated(unsafe) var enrichment = ProviderEnrichment()
    nonisolated(unsafe) var failDaily = false

    init(id: String, displayName: String, daily: DailyUsage? = nil) {
        self.id = id
        self.displayName = displayName
        self.daily = daily
    }
    func fetchDaily() async throws -> DailyUsage? {
        if failDaily { throw StubError.boom }
        return daily
    }
    func fetchEnrichment() async -> ProviderEnrichment { enrichment }
}

private struct FakeClaudeLimits: ClaudeLimitsProviding {
    var status: LimitStatus?
    func fetch(allowKeychainPrompt: Bool) async throws -> LimitStatus {
        guard let status else { throw LimitsError.keychainInteractionNotAllowed }
        return status
    }
}

/// 호출마다 다른 결과 — 첫 N회는 지정 오류, 이후 성공(또는 실패) 반환. auth-expired 회복 테스트용.
private final class SequenceClaudeLimits: ClaudeLimitsProviding, @unchecked Sendable {
    nonisolated(unsafe) var errors: [any Error]
    nonisolated(unsafe) var success: LimitStatus?
    nonisolated(unsafe) var call = 0
    init(errors: [any Error], success: LimitStatus? = nil) { self.errors = errors; self.success = success }
    func fetch(allowKeychainPrompt: Bool) async throws -> LimitStatus {
        defer { call += 1 }
        if call < errors.count { throw errors[call] }
        if let success { return success }
        throw LimitsError.keychainInteractionNotAllowed
    }
}

private struct FakeCodexLimits: CodexLimitsProviding {
    var status: CodexRateLimitStatus?
    func fetch() async throws -> CodexRateLimitStatus? { status }
}

private final class FakeStatusProvider: ProviderStatusProviding, @unchecked Sendable {
    nonisolated(unsafe) var result: [String: ProviderStatus]
    init(_ result: [String: ProviderStatus] = [:]) { self.result = result }
    func fetch() async -> [String: ProviderStatus] { result }
}

// MARK: 픽스처 헬퍼

private func todayDaily(_ tokens: Int, cost: Double = 0) -> DailyUsage {
    DailyUsage(date: LocalUsageReader.todayKey(), inputTokens: 0, outputTokens: 0,
               cacheCreationTokens: 0, cacheReadTokens: 0, totalTokens: tokens, totalCost: cost)
}

private func block(tokensPerMinute tpm: Double) -> BlockUsage {
    let json = "{\"blocks\":[{\"id\":\"b\",\"startTime\":\"\",\"endTime\":\"\",\"isActive\":true," +
               "\"totalTokens\":1000,\"costUSD\":1,\"burnRate\":{\"tokensPerMinute\":\(tpm)}}]}"
    return try! JSONDecoder().decode(BlocksReport.self, from: Data(json.utf8)).blocks[0]
}

private func claudeLimits(fiveHourUtil: Double, resetsAt: String? = nil) -> LimitStatus {
    let reset = resetsAt.map { "\"\($0)\"" } ?? "null"
    let json = "{\"five_hour\":{\"utilization\":\(fiveHourUtil),\"resets_at\":\(reset)}}"
    return try! JSONDecoder().decode(LimitStatus.self, from: Data(json.utf8))
}

private func codexLimits(primaryUsed: Int? = nil, secondaryUsed: Int? = nil) -> CodexRateLimitStatus {
    func win(_ p: Int, _ mins: Int) -> String { "{\"usedPercent\":\(p),\"windowDurationMins\":\(mins)}" }
    var parts: [String] = []
    if let primaryUsed { parts.append("\"primary\":\(win(primaryUsed, 300))") }
    if let secondaryUsed { parts.append("\"secondary\":\(win(secondaryUsed, 10080))") }
    let json = "{\"rateLimits\":{\(parts.joined(separator: ","))}}"
    return try! JSONDecoder().decode(CodexRateLimitStatus.self, from: Data(json.utf8))
}

// MARK: 테스트

@MainActor
final class UsageStoreTests: XCTestCase {
    /// 테스트 전용 defaults suite — 실제 사용자 설정(UserDefaults.standard)을 절대 건드리지 않는다.
    private var testDefaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "ptb-test-\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)
        KeychainAccessGate.isDisabled = false
    }

    override func tearDown() {
        testDefaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func makeStore(
        providers: [any UsageProvider],
        claude: LimitStatus? = nil,
        codex: CodexRateLimitStatus? = nil
    ) -> UsageStore {
        UsageStore(providers: providers,
                   claudeLimitsProvider: FakeClaudeLimits(status: claude),
                   codexLimitsProvider: FakeCodexLimits(status: codex),
                   autoRefresh: false,
                   defaults: testDefaults)
    }

    private func makeStatusStore(_ stub: FakeStatusProvider) -> UsageStore {
        let claude = FakeUsageProvider(id: "claude_code", displayName: "Claude Code", daily: todayDaily(1_000))
        return UsageStore(providers: [claude], claudeLimitsProvider: FakeClaudeLimits(status: nil),
                          codexLimitsProvider: FakeCodexLimits(status: nil), statusProvider: stub,
                          autoRefresh: false, defaults: testDefaults)
    }

    // MARK: 프로바이더 상태(인시던트) 표시

    /// statuspage.io status.json 파싱(순수) — indicator/description 매핑 + 미지값 unknown + malformed nil.
    func testProviderStatusParse() {
        let s = StatuspageStatusProvider.parse(Data(#"{"page":{"name":"Claude"},"status":{"indicator":"minor","description":"Partially Degraded Service"}}"#.utf8))
        XCTAssertEqual(s?.indicator, .minor)
        XCTAssertEqual(s?.description, "Partially Degraded Service")
        XCTAssertTrue(s!.indicator.hasIssue)
        let none = StatuspageStatusProvider.parse(Data(#"{"status":{"indicator":"none","description":"All Systems Operational"}}"#.utf8))
        XCTAssertEqual(none?.indicator, .operational)
        XCTAssertFalse(none!.indicator.hasIssue)   // 정상은 배너 안 뜸
        XCTAssertEqual(StatuspageStatusProvider.parse(Data(#"{"status":{"indicator":"potato"}}"#.utf8))?.indicator, .unknown)
        XCTAssertNil(StatuspageStatusProvider.parse(Data("not json".utf8)))
        XCTAssertNil(StatuspageStatusProvider.parse(Data(#"{"nope":true}"#.utf8)))
    }

    /// 조회 실패(결과에서 빠진 provider)는 이전 값 유지(keep-previous) — flaky 엔드포인트가 앱을 흔들지 않게.
    func testProviderStatusKeepsPreviousOnFailure() async {
        let stub = FakeStatusProvider(["claude_code": ProviderStatus(indicator: .minor, description: "deg")])
        let store = makeStatusStore(stub)
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(store.providerStatus(for: "claude_code")?.indicator, .minor)
        stub.result = [:]                                       // 다음 조회 실패
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(store.providerStatus(for: "claude_code")?.indicator, .minor, "실패 시 이전 값 유지")
        stub.result = ["claude_code": ProviderStatus(indicator: .operational, description: "ok")]   // 복구
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(store.providerStatus(for: "claude_code")?.indicator, .operational)
    }

    /// 상태 조회 꺼짐 → 접근자 nil + refresh 가 저장분도 비워 UI 에서 사라짐.
    func testProviderStatusDisabledClears() async {
        let stub = FakeStatusProvider(["claude_code": ProviderStatus(indicator: .major, description: "x")])
        let store = makeStatusStore(stub)
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(store.providerStatus(for: "claude_code")?.indicator, .major)
        store.statusChecksEnabled = false
        XCTAssertNil(store.providerStatus(for: "claude_code"))   // 꺼짐 → 접근자 nil
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertTrue(store.statuses.isEmpty, "꺼진 뒤 refresh 는 저장 상태를 비운다")
    }

    // MARK: 한도 알림 — 엣지 트리거(임계값 도달 시 최초 1회만)

    /// 회귀(#사용자리포트): 경고선 80% 로 두면 80·81·84·90·94 매 갱신마다 반복 알림되던 문제.
    /// 이제 같은 tier 유지 중엔 재알림하지 않고, 위험선 통과 시에만 1회 추가 발화.
    func testLimitAlertFiresOncePerTierNotEveryRefresh() {
        var tiers: [String: Int] = [:]
        func eval(_ util: Double) -> [UsageStore.LimitAlert] {
            UsageStore.evaluateLimitAlerts(windows: [("주간", "주간", util)], warn: 80, crit: 95, tiers: &tiers)
        }
        XCTAssertEqual(eval(80), [UsageStore.LimitAlert(key: "주간", window: "주간", isCritical: false, utilization: 80)])
        XCTAssertTrue(eval(81).isEmpty)   // 반복 억제 — 사용자 리포트의 핵심
        XCTAssertTrue(eval(84).isEmpty)
        XCTAssertTrue(eval(90).isEmpty)
        XCTAssertTrue(eval(94).isEmpty)
        XCTAssertEqual(eval(95), [UsageStore.LimitAlert(key: "주간", window: "주간", isCritical: true, utilization: 95)])
        XCTAssertTrue(eval(96).isEmpty)   // 위험 tier 유지 → 재알림 없음
        XCTAssertTrue(eval(99).isEmpty)
    }

    /// 휘발성 resets_at 회귀 직접 재현: 같은 utilization 을 여러 번(= 매 fetch resets_at 만 달라지던
    /// 상황) 평가해도, 판정이 resets_at 를 아예 받지 않으므로 최초 1회만 발화.
    func testLimitAlertDoesNotRefireOnRepeatedSameUtilization() {
        var tiers: [String: Int] = [:]
        XCTAssertEqual(UsageStore.evaluateLimitAlerts(windows: [("주간", "주간", 90)], warn: 80, crit: 95, tiers: &tiers).count, 1)
        XCTAssertTrue(UsageStore.evaluateLimitAlerts(windows: [("주간", "주간", 90)], warn: 80, crit: 95, tiers: &tiers).isEmpty)
        XCTAssertTrue(UsageStore.evaluateLimitAlerts(windows: [("주간", "주간", 90)], warn: 80, crit: 95, tiers: &tiers).isEmpty)
    }

    /// 경고선 아래로 내려가면(창 리셋 등) 재무장 — 다음 상승 시 새 에피소드로 다시 1회 발화.
    func testLimitAlertRearmsAfterDroppingBelowWarn() {
        var tiers: [String: Int] = [:]
        _ = UsageStore.evaluateLimitAlerts(windows: [("주간", "주간", 82)], warn: 80, crit: 95, tiers: &tiers)
        XCTAssertTrue(UsageStore.evaluateLimitAlerts(windows: [("주간", "주간", 40)], warn: 80, crit: 95, tiers: &tiers).isEmpty)
        XCTAssertEqual(
            UsageStore.evaluateLimitAlerts(windows: [("주간", "주간", 85)], warn: 80, crit: 95, tiers: &tiers),
            [UsageStore.LimitAlert(key: "주간", window: "주간", isCritical: false, utilization: 85)])
    }

    /// 여러 창은 독립 추적 — 5h 가 이미 위험 발화해도 주간은 자기 임계값에서 별도 1회.
    func testLimitAlertTracksWindowsIndependently() {
        var tiers: [String: Int] = [:]
        let first = UsageStore.evaluateLimitAlerts(
            windows: [("5시간", "5시간", 96), ("주간", "주간", 50)], warn: 80, crit: 95, tiers: &tiers)
        XCTAssertEqual(first, [UsageStore.LimitAlert(key: "5시간", window: "5시간", isCritical: true, utilization: 96)])
        let second = UsageStore.evaluateLimitAlerts(
            windows: [("5시간", "5시간", 97), ("주간", "주간", 82)], warn: 80, crit: 95, tiers: &tiers)
        XCTAssertEqual(second, [UsageStore.LimitAlert(key: "주간", window: "주간", isCritical: false, utilization: 82)])
    }

    /// 회귀(#61 계열): 서로 다른 창이 **같은 표시명**을 만들어도 tier 는 `key` 로 독립 추적돼야 한다.
    /// 과거엔 표시명을 식별자로 써서 Codex 다중 bucket 의 개인 한도(둘 다 "Codex 개인 한도")나
    /// legacy opus 필드 vs weekly_scoped Opus 엔트리가 서로의 tier 를 덮어써 한쪽 알림이 억제됐다.
    /// 이제 key 가 다르면 표시명이 같아도 각자 1회씩 발화한다.
    func testLimitAlertKeyDisambiguatesDuplicateDisplayNames() {
        var tiers: [String: Int] = [:]
        // 같은 표시명("Codex 개인 한도"), 다른 key — 두 bucket 이 동시에 경고선을 넘음.
        let alerts = UsageStore.evaluateLimitAlerts(
            windows: [("codex.codex.individual", "Codex 개인 한도", 90),
                      ("codex.codex_other.individual", "Codex 개인 한도", 92)],
            warn: 80, crit: 95, tiers: &tiers)
        XCTAssertEqual(alerts.count, 2, "표시명이 같아도 key 가 다르면 각 창이 독립 발화")
        XCTAssertEqual(Set(alerts.map(\.key)),
                       ["codex.codex.individual", "codex.codex_other.individual"])
        XCTAssertTrue(alerts.allSatisfy { $0.window == "Codex 개인 한도" })
        // 두 창 모두 tier 1 로 기록 — 한쪽이 다른 쪽을 덮어쓰지 않음.
        XCTAssertEqual(tiers["codex.codex.individual"], 1)
        XCTAssertEqual(tiers["codex.codex_other.individual"], 1)
        // 재평가 시 같은 tier → 둘 다 억제(각자 상태 유지).
        XCTAssertTrue(UsageStore.evaluateLimitAlerts(
            windows: [("codex.codex.individual", "Codex 개인 한도", 91),
                      ("codex.codex_other.individual", "Codex 개인 한도", 93)],
            warn: 80, crit: 95, tiers: &tiers).isEmpty)
    }

    // MARK: 메뉴바 표시 (menuLines)

    /// 회귀(#사용자리포트): 오늘 안 쓴 프로바이더의 한도가 메뉴바에 떴다.
    /// 한도는 오늘 usage>0 인 프로바이더만 노출 — Codex 오늘 미사용이면 Codex 한도 숨김.
    func testMenuBarLimitHidesProviderUnusedToday() async {
        let claude = FakeUsageProvider(id: "claude_code", displayName: "Claude Code", daily: todayDaily(1_000_000))
        let codex = FakeUsageProvider(id: "codex", displayName: "Codex", daily: nil)   // 오늘 미사용
        let store = makeStore(
            providers: [claude, codex],
            claude: claudeLimits(fiveHourUtil: 40, resetsAt: "2099-01-01T00:00:00Z"),
            codex: codexLimits(primaryUsed: 85))
        store.showTokensInMenu = false
        store.showCostInMenu = false
        store.showLimitInMenu = true
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertFalse(store.menuTitle.contains("Codex"))   // 오늘 미사용 → 숨김
        XCTAssertTrue(store.menuTitle.contains("Claude"))    // 오늘 사용 → 노출
    }

    /// 오늘 사용한 프로바이더의 한도는 노출.
    func testMenuBarLimitShowsProviderUsedToday() async {
        let codex = FakeUsageProvider(id: "codex", displayName: "Codex", daily: todayDaily(500_000))
        let store = makeStore(providers: [codex], codex: codexLimits(primaryUsed: 85))
        store.showTokensInMenu = false
        store.showCostInMenu = false
        store.showLimitInMenu = true
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertTrue(store.menuTitle.contains("Codex"))
    }

    /// 사용량(토큰)과 한도는 각각 다른 줄로 분리 — 세로 2줄 스택.
    func testMenuLinesStacksUsageAndLimitsSeparately() async {
        let claude = FakeUsageProvider(id: "claude_code", displayName: "Claude Code", daily: todayDaily(1_200_000))
        let store = makeStore(providers: [claude],
                              claude: claudeLimits(fiveHourUtil: 40, resetsAt: "2099-01-01T00:00:00Z"))
        store.showTokensInMenu = true
        store.showCostInMenu = false
        store.showLimitInMenu = true
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(store.menuLines.count, 2)              // 토큰 줄 + 한도 줄
        XCTAssertTrue(store.menuLines[1].contains("Claude"))  // 둘째 줄 = 한도
    }

    /// 회귀(#사용자리포트): 토큰·비용만 켜면 가로("488M · $376")로 붙어 나오던 것 →
    /// 각각 세로 2줄(토큰 위, 비용 아래). 가로로 합치지 않는다.
    func testMenuLinesTokenAndCostStackVertically() async {
        let claude = FakeUsageProvider(id: "claude_code", displayName: "Claude Code",
                                       daily: todayDaily(1_200_000, cost: 3.45))
        let store = makeStore(providers: [claude])
        store.showTokensInMenu = true
        store.showCostInMenu = true
        store.showLimitInMenu = false
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(store.menuLines.count, 2)               // 토큰 / 비용 = 2줄 (가로 아님)
        XCTAssertFalse(store.menuLines[0].contains(" · "))     // 윗줄 = 토큰만(합치지 않음)
        XCTAssertTrue(store.menuLines[1].contains("$"))        // 아랫줄 = 비용
    }

    /// 3개 다 켜면 → 각각 세로 3줄(토큰 / 비용 / 한도).
    /// 확정 규칙 전수 검증(사용자 요청 "전부 다 테스트"): 8개 토글 조합 각각의 menuLines.
    /// - 2개 이하 활성 → 각 항목 개별 세로 줄. - 3개 다 활성 → 토큰·비용 한 줄 + 한도 아랫줄(2줄).
    func testMenuLinesAllCombinations() async {
        let claude = FakeUsageProvider(id: "claude_code", displayName: "Claude Code",
                                       daily: todayDaily(1_200_000, cost: 3.45))
        let store = makeStore(providers: [claude],
                              claude: claudeLimits(fiveHourUtil: 40, resetsAt: "2099-01-01T00:00:00Z"))
        await store.refresh(scheduleEmptyRetry: false)
        func lines(_ t: Bool, _ c: Bool, _ l: Bool) -> [String] {
            store.showTokensInMenu = t; store.showCostInMenu = c; store.showLimitInMenu = l
            return store.menuLines
        }
        // 전부 끔 → 아이콘만
        XCTAssertEqual(lines(false, false, false), [])
        // 1개만 → 1줄
        XCTAssertEqual(lines(true, false, false).count, 1)   // 토큰
        XCTAssertEqual(lines(false, true, false).count, 1)   // 비용
        XCTAssertEqual(lines(false, false, true).count, 1)   // 한도
        // 2개 → 무조건 세로(각 항목 개별 줄)
        let tc = lines(true, true, false)
        XCTAssertEqual(tc.count, 2)                           // 토큰 / 비용
        XCTAssertFalse(tc[0].contains(" · "))                // 윗줄=토큰만(합침 없음)
        XCTAssertTrue(tc[1].contains("$"))                   // 아랫줄=비용
        XCTAssertEqual(lines(true, false, true).count, 2)    // 토큰 / 한도
        XCTAssertEqual(lines(false, true, true).count, 2)    // 비용 / 한도
        // 3개 → 토큰·비용 한 줄 + 한도 아랫줄 (2줄)
        let three = lines(true, true, true)
        XCTAssertEqual(three.count, 2)                        // 3줄 아님 — 2줄
        XCTAssertTrue(three[0].contains(" · "))              // 윗줄=토큰·비용 나란히
        XCTAssertFalse(three[0].contains("Claude"))          // 윗줄에 한도 없음
        XCTAssertTrue(three[1].contains("Claude"))           // 아랫줄=한도
    }

    // MARK: 집계

    func testAggregatesTodayTokensAcrossProviders() async {
        let claude = FakeUsageProvider(id: "claude_code", displayName: "Claude Code", daily: todayDaily(100_000_000))
        let codex = FakeUsageProvider(id: "codex", displayName: "Codex", daily: todayDaily(50_000_000))
        let store = makeStore(providers: [claude, codex])
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(store.todayTotalTokens, 150_000_000)
        XCTAssertNotNil(store.lastUpdated)
        XCTAssertNil(store.lastErrorDescription)
    }

    func testCodexOnlyWhenClaudeHasNoData() async {
        let claude = FakeUsageProvider(id: "claude_code", displayName: "Claude Code", daily: nil) // 데이터 없음
        let codex = FakeUsageProvider(id: "codex", displayName: "Codex", daily: todayDaily(50_000_000))
        let store = makeStore(providers: [claude, codex])
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(store.todayTotalTokens, 50_000_000)
        XCTAssertTrue(store.hasUsageData)
        XCTAssertEqual(store.snapshots.count, 1)        // claude 는 today nil → 스냅샷 미생성
        XCTAssertEqual(store.snapshots.first?.providerID, "codex")
    }

    func testStaleDatedSnapshotExcludedFromTodayTotal() async {
        let claude = FakeUsageProvider(id: "claude_code", displayName: "Claude Code", daily: todayDaily(100_000_000))
        // 어제(다른 날짜) 데이터 — 날짜 가드로 오늘 합계에서 제외돼야 함
        let codex = FakeUsageProvider(id: "codex", displayName: "Codex",
            daily: DailyUsage(date: "2000-01-01", inputTokens: 0, outputTokens: 0,
                              cacheCreationTokens: 0, cacheReadTokens: 0, totalTokens: 999, totalCost: 0))
        let store = makeStore(providers: [claude, codex])
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(store.todayTotalTokens, 100_000_000)   // codex 999 제외
    }

    func testProviderFailureKeepsPreviousTodayValue() async {
        let claude = FakeUsageProvider(id: "claude_code", displayName: "Claude Code", daily: todayDaily(100_000_000))
        let store = makeStore(providers: [claude])
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(store.todayTotalTokens, 100_000_000)

        claude.failDaily = true
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(store.todayTotalTokens, 100_000_000)    // 실패 → 이전 값 유지
        XCTAssertNotNil(store.lastErrorDescription)            // 에러는 표면화
    }

    // MARK: 메뉴바 타이틀

    func testMenuTitleReflectsToggles() async {
        let claude = FakeUsageProvider(id: "claude_code", displayName: "Claude Code", daily: todayDaily(100_000_000, cost: 12.5))
        let store = makeStore(providers: [claude])
        store.showTokensInMenu = true
        store.showCostInMenu = false
        store.showLimitInMenu = false
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(store.menuTitle, "100M")

        store.showCostInMenu = true
        XCTAssertEqual(store.menuTitle, "100M · $12.5")
    }

    func testMenuTitleShowsLimitPercents() async {
        // 둘 다 오늘 사용 → 두 한도 모두 노출. (오늘 usage 게이트: codex 사용 프로바이더도 등록)
        let claude = FakeUsageProvider(id: "claude_code", displayName: "Claude Code", daily: todayDaily(10_000_000))
        let codex = FakeUsageProvider(id: "codex", displayName: "Codex", daily: todayDaily(2_000_000))
        let store = makeStore(providers: [claude, codex],
                              claude: claudeLimits(fiveHourUtil: 42),
                              codex: codexLimits(primaryUsed: 73))
        store.showTokensInMenu = false
        store.showCostInMenu = false
        store.showLimitInMenu = true
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(store.menuTitle, "Claude 42% · Codex 73%")
    }

    // MARK: 한도 경고

    func testLimitWarningWhenClaudeOverCritical() async {
        let claude = FakeUsageProvider(id: "claude_code", displayName: "Claude Code", daily: todayDaily(10_000_000))
        let store = makeStore(providers: [claude], claude: claudeLimits(fiveHourUtil: 96))
        store.critThreshold = 95
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertTrue(store.isLimitWarning)
        XCTAssertNotNil(store.limits, "한도가 로드돼야 한다")
    }

    func testNoLimitWarningWhenUnderCritical() async {
        let claude = FakeUsageProvider(id: "claude_code", displayName: "Claude Code", daily: todayDaily(10_000_000))
        let store = makeStore(providers: [claude], claude: claudeLimits(fiveHourUtil: 50))
        store.critThreshold = 95
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertFalse(store.isLimitWarning)
    }

    func testLimitWarningFromCodexSecondary() async {
        let claude = FakeUsageProvider(id: "claude_code", displayName: "Claude Code", daily: todayDaily(10_000_000))
        let store = makeStore(providers: [claude], codex: codexLimits(primaryUsed: 10, secondaryUsed: 97))
        store.critThreshold = 95
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertTrue(store.isLimitWarning)
    }

    func testLimitWarningFromForecastAtFullUtilization() async {
        // crit 을 100 초과로 올려 임계 분기를 끄고, util 100 → 예측 분기만으로 경고가 켜지는지 확인
        let claude = FakeUsageProvider(id: "claude_code", displayName: "Claude Code", daily: todayDaily(10_000_000))
        let store = makeStore(providers: [claude],
                              claude: claudeLimits(fiveHourUtil: 100, resetsAt: "2099-01-01T00:00:00Z"))
        store.critThreshold = 101
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertTrue(store.isLimitWarning)   // fiveHourForecast(beforeReset:true)
    }

    // MARK: burn tier

    func testBurnTierThresholds() async {
        func tier(_ tpm: Double) async -> BurnTier {
            let p = FakeUsageProvider(id: "claude_code", displayName: "Claude Code", daily: todayDaily(10_000_000))
            p.enrichment = ProviderEnrichment(activeBlock: block(tokensPerMinute: tpm), blocksOK: true,
                                              weekTotal: nil, monthTotal: nil, periodsOK: false)
            let store = makeStore(providers: [p])
            await store.refresh(scheduleEmptyRetry: false)
            return store.burnTier
        }
        let idle = await tier(500)         // <=1000 → idle
        let normal = await tier(50_000)    // <100k → normal
        let fast = await tier(200_000)     // <400k → fast
        let blazing = await tier(500_000)  // >=400k → blazing
        XCTAssertEqual(idle, .idle)
        XCTAssertEqual(normal, .normal)
        XCTAssertEqual(fast, .fast)
        XCTAssertEqual(blazing, .blazing)
    }

    /// Codex 전용 사용자도 burn tier 가 반영되는지 (프로바이더 종속 제거 회귀 방지).
    func testBurnTierFromNonClaudeProvider() async {
        let codex = FakeUsageProvider(id: "codex", displayName: "Codex", daily: todayDaily(10_000_000))
        codex.enrichment = ProviderEnrichment(activeBlock: block(tokensPerMinute: 200_000), blocksOK: true,
                                              weekTotal: nil, monthTotal: nil, periodsOK: false)
        let store = makeStore(providers: [codex])
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(store.burnTier, .fast)
    }

    /// 자정 직후 — 오늘 토큰 0이지만 **활성 5h 블록**이 있으면 캐리어 스냅샷 생성.
    /// (없으면 매일 자정~첫토큰 창에서 burn/forecast/주월이 소실되던 버그 회귀 방지)
    func testMidnightCarrierSnapshotFromActiveBlock() async {
        let claude = FakeUsageProvider(id: "claude_code", displayName: "Claude Code", daily: nil)
        claude.enrichment = ProviderEnrichment(
            activeBlock: block(tokensPerMinute: 200_000), blocksOK: true,
            weekTotal: PeriodUsage(period: "w", totalTokens: 90_000_000, totalCost: 0),
            monthTotal: PeriodUsage(period: "m", totalTokens: 300_000_000, totalCost: 0),
            periodsOK: true)
        let store = makeStore(providers: [claude])
        await store.refresh(scheduleEmptyRetry: false)

        let snap = store.snapshot(preferring: "claude_code")
        XCTAssertEqual(snap?.providerID, "claude_code", "캐리어 스냅샷 미생성")
        XCTAssertNil(snap?.today, "오늘 데이터는 없어야(today=nil)")
        XCTAssertEqual(store.weekTotalTokens, 90_000_000)
        XCTAssertEqual(store.burnTier, .fast, "자정 직후에도 활성 블록으로 burn 반영(idle 아님)")
    }

    /// 오늘·최근 미사용(활성 블록 없음)인데 주/월 기록만 있으면 캐리어를 만들지 않는다 —
    /// weekTotal 이 항상 non-nil 이라 탭이 뜨던 회귀 방지("안 썼는데 왜 뜨지").
    func testNoCarrierForWeekMonthOnlyWithoutActiveBlock() async {
        let codex = FakeUsageProvider(id: "codex", displayName: "Codex", daily: nil)
        codex.enrichment = ProviderEnrichment(
            activeBlock: nil, blocksOK: true,   // 최근 5h 사용 없음 → 블록 없음
            weekTotal: PeriodUsage(period: "w", totalTokens: 50_000_000, totalCost: 0),
            monthTotal: PeriodUsage(period: "m", totalTokens: 80_000_000, totalCost: 0),
            periodsOK: true)
        let store = makeStore(providers: [codex])
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertFalse(store.snapshots.contains { $0.providerID == "codex" },
                       "오늘·최근 미사용 프로바이더는 탭이 뜨면 안 됨")
    }

    /// 여러 프로바이더의 burn 은 합산된다 (60k + 60k = 120k → fast).
    func testBurnTierCombinesProviders() async {
        let claude = FakeUsageProvider(id: "claude_code", displayName: "Claude Code", daily: todayDaily(10_000_000))
        claude.enrichment = ProviderEnrichment(activeBlock: block(tokensPerMinute: 60_000), blocksOK: true,
                                               weekTotal: nil, monthTotal: nil, periodsOK: false)
        let codex = FakeUsageProvider(id: "codex", displayName: "Codex", daily: todayDaily(10_000_000))
        codex.enrichment = ProviderEnrichment(activeBlock: block(tokensPerMinute: 60_000), blocksOK: true,
                                              weekTotal: nil, monthTotal: nil, periodsOK: false)
        let store = makeStore(providers: [claude, codex])
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(store.burnTier, .fast)
    }

    // MARK: 확장 규약 — 프로바이더 무관 집계 (CLAUDE.md "확장 규약" 강제)

    /// 하드코딩 allow-list 없이 *임의의 미래 프로바이더*(id 가 claude_code/codex/gemini 어느 것도 아님)가
    /// 범용 집계 경로 전부에 흘러가는지 강제한다. 누군가 오늘/주/월/burn 에 `== "claude_code"` 류
    /// id 분기를 넣어 특정 프로바이더만 세면 이 테스트가 깨진다.
    func testUnknownFutureProviderFlowsThroughAllAggregation() async {
        let future = FakeUsageProvider(
            id: "future_tool_xyz", displayName: "Future Tool", daily: todayDaily(42_000_000))
        future.enrichment = ProviderEnrichment(
            activeBlock: block(tokensPerMinute: 200_000), blocksOK: true,
            weekTotal: PeriodUsage(period: "w", totalTokens: 90_000_000, totalCost: 0),
            monthTotal: PeriodUsage(period: "m", totalTokens: 300_000_000, totalCost: 0),
            periodsOK: true)
        let store = makeStore(providers: [future])
        await store.refresh(scheduleEmptyRetry: false)

        XCTAssertEqual(store.todayTotalTokens, 42_000_000, "오늘 합계가 id 로 필터링됨")
        XCTAssertEqual(store.weekTotalTokens, 90_000_000, "주 합계가 id 로 필터링됨")
        XCTAssertEqual(store.monthTotalTokens, 300_000_000, "월 합계가 id 로 필터링됨")
        XCTAssertEqual(store.burnTier, .fast, "burn 이 특정 프로바이더에만 종속됨")
        // preferring 은 미스 시 .first 폴백이라 id 일치까지 확인해야 유효(theater 방지)
        XCTAssertEqual(store.snapshot(preferring: "future_tool_xyz")?.providerID, "future_tool_xyz",
                       "탭에 노출 안 됨")
    }

    /// 기본 등록 프로바이더 레지스트리 무결성 — 비어 있지 않고 id 가 유일.
    /// (새 프로바이더를 배열에 등록하는 단일 지점이 살아있는지 최소 보증.)
    func testDefaultProviderRegistryHasUniqueIds() {
        let store = UsageStore(autoRefresh: false, defaults: testDefaults)
        let ids = store.registeredProviderIDs
        XCTAssertFalse(ids.isEmpty)
        XCTAssertEqual(Set(ids).count, ids.count, "프로바이더 id 중복")
    }

    // MARK: stale

    // MARK: 세션 만료(401) UX

    func testLimitsAuthExpiredSetOn401AndClearedOnSuccess() async {
        let claude = FakeUsageProvider(id: "claude_code", displayName: "Claude Code", daily: todayDaily(10_000_000))
        let seq = SequenceClaudeLimits(errors: [LimitsError.httpStatus(401)],
                                       success: claudeLimits(fiveHourUtil: 12, resetsAt: "2099-01-01T00:00:00Z"))
        let store = UsageStore(providers: [claude], claudeLimitsProvider: seq,
                               codexLimitsProvider: FakeCodexLimits(status: nil),
                               autoRefresh: false, defaults: testDefaults)
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertTrue(store.limitsAuthExpired, "401 → 세션 만료 안내 상태")
        await store.refresh(scheduleEmptyRetry: false)   // 이번엔 성공
        XCTAssertFalse(store.limitsAuthExpired, "성공 시 해제")
    }

    func testLimitsAuthExpiredNotSetOnNon401() async {
        let claude = FakeUsageProvider(id: "claude_code", displayName: "Claude Code", daily: todayDaily(10_000_000))
        let store = UsageStore(providers: [claude],
                               claudeLimitsProvider: SequenceClaudeLimits(errors: [LimitsError.httpStatus(500)]),
                               codexLimitsProvider: FakeCodexLimits(status: nil),
                               autoRefresh: false, defaults: testDefaults)
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertFalse(store.limitsAuthExpired, "500 은 세션 만료 아님 — 오탐 방지")
    }

    func testIsStaleBeforeFirstRefreshThenFreshAfter() async {
        let claude = FakeUsageProvider(id: "claude_code", displayName: "Claude Code", daily: todayDaily(10_000_000))
        let store = makeStore(providers: [claude])
        XCTAssertTrue(store.isStale)   // lastUpdated nil
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertFalse(store.isStale)
    }

    // MARK: 프로바이더 탭 선택 해석

    func testSnapshotPreferringSelection() async {
        let claude = FakeUsageProvider(id: "claude_code", displayName: "Claude Code", daily: todayDaily(1_000))
        let gemini = FakeUsageProvider(id: "gemini", displayName: "Gemini", daily: todayDaily(2_000))
        let store = makeStore(providers: [claude, gemini])
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(store.snapshot(preferring: "gemini")?.providerID, "gemini")
        XCTAssertEqual(store.snapshot(preferring: nil)?.providerID, "claude_code", "선호 없음 → 첫 번째")
        XCTAssertEqual(store.snapshot(preferring: "cursor")?.providerID, "claude_code", "미연결 id → 첫 번째 폴백")
    }

    // MARK: 주/월 누적 유지 (팝오버 깜빡임 회귀 방지)

    /// phase1 재빌드가 이전 스냅샷의 주/월 누적을 이어받지 않으면, 다음 enrichment 가
    /// 다시 채우기 전까지 nil 이 되어 팝오버 "이번 주/이번 달" 행이 사라졌다 나타난다.
    /// enrichment 가 주월을 못 채우는(periodsOK=false) 갱신에서도 이전 값이 유지돼야 한다.
    func testWeekMonthPersistAcrossRefreshWhenEnrichmentSkips() async {
        let claude = FakeUsageProvider(id: "claude_code", displayName: "Claude Code", daily: todayDaily(1_000))
        claude.enrichment = ProviderEnrichment(
            activeBlock: nil, blocksOK: false,
            weekTotal: PeriodUsage(period: "2026-06-28", totalTokens: 7_000, totalCost: 0),
            monthTotal: PeriodUsage(period: "2026-06", totalTokens: 30_000, totalCost: 0),
            periodsOK: true)
        let store = makeStore(providers: [claude])
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(store.weekTotalTokens, 7_000)
        XCTAssertEqual(store.monthTotalTokens, 30_000)

        // 다음 갱신: enrichment 가 주월을 채우지 못함 → 이전 값이 살아있어야 한다.
        claude.enrichment = ProviderEnrichment(
            activeBlock: nil, blocksOK: false, weekTotal: nil, monthTotal: nil, periodsOK: false)
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(store.weekTotalTokens, 7_000, "주 누적이 재빌드에서 사라지면 안 된다")
        XCTAssertEqual(store.monthTotalTokens, 30_000, "월 누적이 재빌드에서 사라지면 안 된다")
    }

    // MARK: friendlyLimitError 매핑

    func testFriendlyLimitErrorMapping() {
        let l = L(.en)
        XCTAssertEqual(UsageStore.friendlyLimitError(LimitsError.httpStatus(401), l), l.limitRefreshHTTPError(401))
        XCTAssertEqual(UsageStore.friendlyLimitError(LimitsError.httpStatus(500), l), l.limitRefreshHTTPError(500))
        XCTAssertEqual(UsageStore.friendlyLimitError(LimitsError.credentialFormat, l), l.limitRefreshNoCredential)
        XCTAssertEqual(UsageStore.friendlyLimitError(LimitsError.keychainInteractionNotAllowed, l), l.limitRefreshGeneric)
        XCTAssertEqual(UsageStore.friendlyLimitError(StubError.boom, l), l.limitRefreshGeneric)   // 비 LimitsError
    }
}
