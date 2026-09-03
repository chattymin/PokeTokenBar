import XCTest
import AppKit
@testable import PokeTokenBar

// UsageStore 의 refresh 파이프라인 + 파생 표시값을 주입 스텁으로 결정적 검증.
// (실제 ccusage/Keychain/Codex 바이너리 없이 — 위협 모델: 1인 로컬, CI 없음)

// MARK: 스텁

private enum StubError: Error { case boom }

/// 호출 후에도 동작을 바꿀 수 있는 usage provider (실패 전환 테스트용). 단일 스레드 테스트 한정.
private final class FakeUsageProvider: UsageProvider, @unchecked Sendable {
    let id: String
    let displayName: String
    let reportsCost: Bool
    nonisolated(unsafe) var daily: DailyUsage?
    nonisolated(unsafe) var enrichment = ProviderEnrichment()
    nonisolated(unsafe) var failDaily = false

    init(id: String, displayName: String, daily: DailyUsage? = nil, reportsCost: Bool = true) {
        self.id = id
        self.displayName = displayName
        self.reportsCost = reportsCost
        self.daily = daily
    }
    func fetchDaily() async throws -> DailyUsage? {
        if failDaily { throw StubError.boom }
        return daily
    }
    func fetchEnrichment() async -> ProviderEnrichment { enrichment }
}

/// 첫 fetchDaily 호출을 continuation 으로 붙잡아, in-flight refresh 중 두 번째 refresh 를 겹치게 하는 스텁.
/// 게이트 상태는 actor 로 격리(백그라운드 fetchDaily ↔ 테스트 폴링/release 간 데이터레이스 없음).
private actor GatedUsageProvider: UsageProvider {
    nonisolated let id = "claude_code"
    nonisolated let displayName = "Claude Code"
    private let dailyValue: DailyUsage
    private var calls = 0
    private var gate: CheckedContinuation<Void, Never>?
    private var released = false
    init(daily: DailyUsage) { self.dailyValue = daily }
    var dailyCalls: Int { calls }
    func fetchDaily() async throws -> DailyUsage? {
        calls += 1
        if calls == 1 {
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                if released { c.resume() } else { gate = c }   // release()가 먼저 왔으면 즉시 통과
            }
        }
        return dailyValue
    }
    func fetchEnrichment() async -> ProviderEnrichment { ProviderEnrichment() }
    func release() { released = true; let c = gate; gate = nil; c?.resume() }
}

/// 첫 호출만 성공하고 이후는 실패 — "성공으로 채워진 `limits` 를 든 채 조회가 실패하는" 상태를
/// 만든다. 이력이 그 낡은 값을 관측으로 오해하는지 보는 데 쓴다.
private final class FailAfterFirstClaudeLimits: ClaudeLimitsProviding, @unchecked Sendable {
    private let status: LimitStatus
    nonisolated(unsafe) private var calls = 0
    init(status: LimitStatus) { self.status = status }
    func fetch(allowKeychainPrompt: Bool) async throws -> LimitStatus {
        calls += 1
        if calls == 1 { return status }
        throw StubError.boom
    }
}

/// 호출 횟수를 세는 스텁 — 폴 간격 게이트가 실제로 호출을 *막는지* 세어서 확인한다.
/// 상태만 보면 "값이 그대로다"와 "다시 조회했는데 같은 값이다"를 구분할 수 없다.
private final class CountingClaudeLimits: ClaudeLimitsProviding, @unchecked Sendable {
    private let status: LimitStatus
    nonisolated(unsafe) private(set) var calls = 0
    init(status: LimitStatus) { self.status = status }
    func fetch(allowKeychainPrompt: Bool) async throws -> LimitStatus {
        calls += 1
        return status
    }
}

/// 지정한 오류만 던지는 antigravity 스텁 — 401/403 분기 검증용.
private struct ThrowingAntigravityLimits: AntigravityLimitsProviding {
    let error: LimitsError
    func fetch(allowKeychainPrompt: Bool) async throws -> AntigravityRateLimitStatus { throw error }
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

private struct FakeOpenCodeGoLimits: OpenCodeGoLimitsProviding {
    var status: OpenCodeGoLimitStatus?
    func fetch() async throws -> OpenCodeGoLimitStatus? { status }
}

/// fetch 호출 수를 세는 스텁 — OpenCode Go 폴링 스로틀(최소 5분) 회귀 검증용.
private final class CountingOpenCodeGoLimits: OpenCodeGoLimitsProviding, @unchecked Sendable {
    nonisolated(unsafe) var calls = 0
    nonisolated(unsafe) var status: OpenCodeGoLimitStatus?
    nonisolated(unsafe) var error: (any Error)?
    func fetch() async throws -> OpenCodeGoLimitStatus? {
        calls += 1
        if let error { throw error }
        return status
    }
}

private struct FakeAntigravityLimits: AntigravityLimitsProviding {
    var status: AntigravityRateLimitStatus?
    func fetch(allowKeychainPrompt: Bool) async throws -> AntigravityRateLimitStatus {
        guard let status else { throw LimitsError.keychainInteractionNotAllowed }
        return status
    }
}

/// 호출마다 allowKeychainPrompt 값을 기록 — 자동/수동 경로가 올바른 플래그를 쓰는지 회귀 검증용.
private final class RecordingClaudeLimits: ClaudeLimitsProviding, @unchecked Sendable {
    nonisolated(unsafe) var promptFlags: [Bool] = []
    nonisolated(unsafe) var status: LimitStatus?
    init(status: LimitStatus? = nil) { self.status = status }
    func fetch(allowKeychainPrompt: Bool) async throws -> LimitStatus {
        promptFlags.append(allowKeychainPrompt)
        guard let status else { throw LimitsError.keychainInteractionNotAllowed }
        return status
    }
}

/// 세션 키 저장소 스텁 — 실제 파일을 건드리지 않는다.
private final class StubSessionKeys: SessionKeyManaging, @unchecked Sendable {
    nonisolated(unsafe) var stored: SessionKeyCredential?
    nonisolated(unsafe) var discovered: [SessionKeyOrganization]
    nonisolated(unsafe) var cleared = false
    nonisolated(unsafe) var saves: [SessionKeyCredential] = []

    init(credential: SessionKeyCredential?, organizations: [SessionKeyOrganization] = []) {
        stored = credential
        discovered = organizations
    }
    func credential() -> SessionKeyCredential? { stored }
    func organizations(sessionKey: String) async throws -> [SessionKeyOrganization] { discovered }
    func save(key: String, organizationID: String?) throws {
        let credential = SessionKeyCredential(key: key, organizationID: organizationID)
        stored = credential
        saves.append(credential)
    }
    func clear() { stored = nil; cleared = true }
}

private func sessionOrg(_ id: String, hasUsage: Bool) -> SessionKeyOrganization {
    SessionKeyOrganization(id: id, name: id.uppercased(), hasUsageData: hasUsage,
                           limits: claudeLimits(fiveHourUtil: hasUsage ? 7 : 0))
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

private func opencodeGoLimits(rolling: Int? = nil, weekly: Int? = nil, monthly: Int? = nil) -> OpenCodeGoLimitStatus {
    func win(_ p: Int) -> String { "{\"status\":\"ok\",\"percent\":\(p),\"resetsAt\":\"2099-01-01T00:00:00Z\"}" }
    var parts: [String] = []
    if let rolling { parts.append("\"rolling\":\(win(rolling))") }
    if let weekly { parts.append("\"weekly\":\(win(weekly))") }
    if let monthly { parts.append("\"monthly\":\(win(monthly))") }
    let json = "{\"usage\":{\(parts.joined(separator: ","))}}"
    return try! JSONDecoder().decode(OpenCodeGoLimitStatus.self, from: Data(json.utf8))
}

// MARK: 테스트

@MainActor
final class UsageStoreTests: XCTestCase {
    /// 테스트 전용 defaults suite — 실제 사용자 설정(UserDefaults.standard)을 절대 건드리지 않는다.
    /// nonisolated(unsafe): @MainActor 클래스의 sync setUp/tearDown 은 릴리스 Swift 에서 nonisolated 로
    /// 취급돼 main-actor 프로퍼티 접근이 컴파일 에러가 된다. XCTest 는 인스턴스별로 직렬 실행하므로 안전.
    nonisolated(unsafe) private var testDefaults: UserDefaults!
    nonisolated(unsafe) private var suiteName: String!

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
        codex: CodexRateLimitStatus? = nil,
        opencodeGo: OpenCodeGoLimitStatus? = nil,
        antigravity: AntigravityRateLimitStatus? = nil
    ) -> UsageStore {
        UsageStore(providers: providers,
                   claudeLimitsProvider: FakeClaudeLimits(status: claude),
                   codexLimitsProvider: FakeCodexLimits(status: codex),
                   opencodeGoLimitsProvider: FakeOpenCodeGoLimits(status: opencodeGo),
                   antigravityLimitsProvider: FakeAntigravityLimits(status: antigravity),
                   autoRefresh: false,
                   defaults: testDefaults)
    }

    private func makeStatusStore(_ stub: FakeStatusProvider) -> UsageStore {
        let claude = FakeUsageProvider(id: "claude_code", displayName: "Claude Code", daily: todayDaily(1_000))
        return UsageStore(providers: [claude], claudeLimitsProvider: FakeClaudeLimits(status: nil),
                          codexLimitsProvider: FakeCodexLimits(status: nil),
                          opencodeGoLimitsProvider: FakeOpenCodeGoLimits(status: nil),
                          antigravityLimitsProvider: FakeAntigravityLimits(status: nil),
                          statusProvider: stub,
                          autoRefresh: false, defaults: testDefaults)
    }

    // MARK: 한도 이력 배선

    /// 이력 파생 로직이 아무리 옳아도(LimitHistoryTests) refresh 가 기록을 안 부르면 이력은 영원히
    /// 비어 있다 — 그 배선을 프로덕션 경로(refresh)로 직접 밟는다.
    func testRefreshRecordsLimitHistory() async {
        let history = LimitHistoryStore(fileURL: historyFile())
        let claude = FakeUsageProvider(id: "claude_code", displayName: "Claude Code",
                                       daily: todayDaily(1_000))
        let store = UsageStore(providers: [claude],
                               claudeLimitsProvider: FakeClaudeLimits(
                                   status: claudeLimits(fiveHourUtil: 37)),
                               codexLimitsProvider: FakeCodexLimits(status: nil),
                               opencodeGoLimitsProvider: FakeOpenCodeGoLimits(status: nil),
                               antigravityLimitsProvider: FakeAntigravityLimits(status: nil),
                               limitHistory: history, autoRefresh: false, defaults: testDefaults)
        await store.refresh()

        XCTAssertEqual(history.samples(providerID: "claude_code", window: "five_hour")
            .map(\.utilization), [37])
    }

    func testRefreshRecordsAntigravityLimitHistory() async throws {
        let history = LimitHistoryStore(fileURL: historyFile())
        let agyProvider = FakeUsageProvider(id: "antigravity", displayName: "Antigravity",
                                            daily: todayDaily(5_000))
        let gemini5h = AntigravityQuotaBucket(bucketId: "gemini-5h", displayName: "5h", window: "5h", remainingFraction: 0.8) // 20%
        let geminiWeekly = AntigravityQuotaBucket(bucketId: "gemini-weekly", displayName: "Weekly", window: "weekly", remainingFraction: 0.95) // 5%
        let agyStatus = AntigravityRateLimitStatus(groups: [
            AntigravityQuotaGroup(displayName: "Gemini Models", buckets: [gemini5h, geminiWeekly])
        ])

        let store = UsageStore(providers: [agyProvider],
                               claudeLimitsProvider: FakeClaudeLimits(status: nil),
                               codexLimitsProvider: FakeCodexLimits(status: nil),
                               opencodeGoLimitsProvider: FakeOpenCodeGoLimits(status: nil),
                               antigravityLimitsProvider: FakeAntigravityLimits(status: agyStatus),
                               limitHistory: history, autoRefresh: false, defaults: testDefaults)
        await store.refresh()

        let sample5h = try XCTUnwrap(history.samples(providerID: "antigravity", window: "gemini_5h").first)
        XCTAssertEqual(sample5h.utilization, 20.0, accuracy: 0.001)
        let sampleWeekly = try XCTUnwrap(history.samples(providerID: "antigravity", window: "gemini_weekly").first)
        XCTAssertEqual(sampleWeekly.utilization, 5.0, accuracy: 0.001)
    }

    /// 사용량 스캔 주기(로컬 파일 읽기)와 원격 한도 조회를 분리한다. 2분 주기에서 429 가 반복된 것이
    /// 근거다 — 사용자는 "사용량을 자주 갱신"을 고른 것이지 "비공식 endpoint 를 자주 두드림"을 고른 게 아니다.
    func testConsecutiveRefreshesDoNotRefetchRemoteLimits() async {
        let limitsProvider = CountingClaudeLimits(status: claudeLimits(fiveHourUtil: 12))
        let claude = FakeUsageProvider(id: "claude_code", displayName: "Claude Code",
                                       daily: todayDaily(1_000))
        let store = UsageStore(providers: [claude],
                               claudeLimitsProvider: limitsProvider,
                               codexLimitsProvider: FakeCodexLimits(status: nil),
                               opencodeGoLimitsProvider: FakeOpenCodeGoLimits(status: nil),
                               antigravityLimitsProvider: FakeAntigravityLimits(status: nil),
                               autoRefresh: false, defaults: testDefaults)

        await store.refresh()
        await store.refresh()

        XCTAssertEqual(limitsProvider.calls, 1,
                       "간격 안의 두 번째 폴이 원격 endpoint 를 다시 두드렸다")
        XCTAssertNotNil(store.limits, "첫 조회는 막히면 안 된다 — 기동 직후 한도가 비어 보인다")
    }

    /// 사용자가 누른 갱신은 간격을 무시한다 — 눌렀는데 아무 일도 안 일어나면 고장으로 보인다.
    func testManualRefreshBypassesThePollInterval() async {
        let limitsProvider = CountingClaudeLimits(status: claudeLimits(fiveHourUtil: 12))
        let claude = FakeUsageProvider(id: "claude_code", displayName: "Claude Code",
                                       daily: todayDaily(1_000))
        let store = UsageStore(providers: [claude],
                               claudeLimitsProvider: limitsProvider,
                               codexLimitsProvider: FakeCodexLimits(status: nil),
                               opencodeGoLimitsProvider: FakeOpenCodeGoLimits(status: nil),
                               antigravityLimitsProvider: FakeAntigravityLimits(status: nil),
                               autoRefresh: false, defaults: testDefaults)

        await store.refresh()
        await store.refreshLimitTokenFromKeychain()

        XCTAssertEqual(limitsProvider.calls, 2, "사용자 갱신이 간격에 막혔다")
    }

    /// 한도 조회가 실패해도 `store.limits` 에는 **직전 성공값이 그대로 남는다**. 기록을 실패 경로에도
    /// 걸면 endpoint 가 죽어 있는 내내 그 낡은 값이 heartbeat 마다 쌓여 "그 구간 내내 한도가
    /// 평평했다"는 거짓 이력이 된다. 실제로는 아무것도 관측 못 한 구간이라 gap 으로 남아야 맞다.
    ///
    /// 검증은 **성공 뒤 실패** 순서라야 의미가 있다. 처음부터 실패시키면 `limits` 가 nil 이라
    /// 기록 함수가 어차피 조기 반환해, 실패 경로에 기록을 잘못 걸어 놔도 테스트는 통과한다
    /// (실제로 그 defect 를 주입했더니 순서를 뒤집기 전 버전은 잡지 못했다). 시계도 직접 쥔다 —
    /// 두 refresh 가 같은 순간에 일어나면 다운샘플링이 중복 샘플을 걸러 결함을 가린다.
    func testFailedLimitFetchDoesNotAppendStaleHistory() async {
        var clock = Date(timeIntervalSince1970: 1_700_000_000)
        let history = LimitHistoryStore(fileURL: historyFile(), now: { clock })
        let claude = FakeUsageProvider(id: "claude_code", displayName: "Claude Code",
                                       daily: todayDaily(1_000))
        let limits = FailAfterFirstClaudeLimits(status: claudeLimits(fiveHourUtil: 51))
        let store = UsageStore(providers: [claude], claudeLimitsProvider: limits,
                               codexLimitsProvider: FakeCodexLimits(status: nil),
                               opencodeGoLimitsProvider: FakeOpenCodeGoLimits(status: nil),
                               antigravityLimitsProvider: FakeAntigravityLimits(status: nil),
                               limitHistory: history, autoRefresh: false, defaults: testDefaults)

        await store.refresh()   // 1회차: 성공 → 관측 1건
        XCTAssertEqual(history.samples(providerID: "claude_code", window: "five_hour")
            .map(\.utilization), [51])

        // heartbeat 를 넘겨 "값이 그대로여도 기록될" 조건을 만든 뒤 실패시킨다.
        clock = clock.addingTimeInterval(LimitHistoryStore.heartbeat + 60)
        await store.refresh()   // 2회차: 실패 — limits 는 51 로 남아 있다
        XCTAssertNotNil(store.limits, "실패해도 직전 한도는 화면에 남는다 (이 테스트의 전제)")
        XCTAssertEqual(history.samples(providerID: "claude_code", window: "five_hour")
            .map(\.utilization), [51],
            "관측하지 못한 구간을 낡은 값으로 메우면 안 된다")
    }

    /// 키체인 접근을 끈 사용자는 한도 조회 자체를 하지 않는다(`limits = nil`). 이 경로가 기록까지
    /// 타면 nil 을 0% 로 흘려 "한도를 전혀 안 썼다"는 막대가 그려진다.
    func testKeychainDisabledRecordsNoHistory() async {
        let history = LimitHistoryStore(fileURL: historyFile())
        let claude = FakeUsageProvider(id: "claude_code", displayName: "Claude Code",
                                       daily: todayDaily(1_000))
        let store = UsageStore(providers: [claude],
                               claudeLimitsProvider: FakeClaudeLimits(
                                   status: claudeLimits(fiveHourUtil: 44)),
                               codexLimitsProvider: FakeCodexLimits(status: nil),
                               opencodeGoLimitsProvider: FakeOpenCodeGoLimits(status: nil),
                               antigravityLimitsProvider: FakeAntigravityLimits(status: nil),
                               limitHistory: history, autoRefresh: false, defaults: testDefaults)
        store.disableKeychainAccess = true
        await store.refresh()

        XCTAssertTrue(history.samples(providerID: "claude_code", window: "five_hour").isEmpty)
    }

    private func historyFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ptb-history-\(UUID().uuidString).json")
    }

    // MARK: refresh 코얼레싱 (회귀)

    /// [회귀] 진행 중 refresh 에 겹친 refresh 는 드롭이 아니라 완료 후 1회 재실행(코얼레싱)돼야 한다.
    /// 수동모드(interval 0)에서 키체인 재활성 refresh 가 in-flight 폴에 묻혀 Claude 한도가 빈 채로
    /// 남던 회귀 가드 — 겹친 요청이 그냥 무시되면 fetchDaily 는 1회로 끝난다.
    func testConcurrentRefreshIsCoalescedNotDropped() async {
        let p = GatedUsageProvider(daily: todayDaily(1_000))
        let store = UsageStore(providers: [p],
                               claudeLimitsProvider: FakeClaudeLimits(status: nil),
                               codexLimitsProvider: FakeCodexLimits(status: nil),
                               opencodeGoLimitsProvider: FakeOpenCodeGoLimits(status: nil),
                               antigravityLimitsProvider: FakeAntigravityLimits(status: nil),
                               statusProvider: FakeStatusProvider([:]),
                               autoRefresh: false, defaults: testDefaults)
        // A: 첫 refresh — fetchDaily 의 gate 에 걸려 in-flight 로 멈춘다.
        let a = Task { await store.refresh(scheduleEmptyRetry: false) }
        for _ in 0..<500 { if await p.dailyCalls >= 1 { break }; await Task.yield() }
        XCTAssertTrue(store.isRefreshing, "A 가 in-flight 여야 한다")
        // B: 겹친 refresh — 드롭 대신 예약(즉시 리턴).
        await store.refresh(scheduleEmptyRetry: false)
        // gate 해제 → A 완료 → defer 가 예약분을 1회 재실행.
        await p.release()
        await a.value
        for _ in 0..<500 { if await p.dailyCalls >= 2 { break }; await Task.yield() }
        let calls = await p.dailyCalls
        XCTAssertGreaterThanOrEqual(calls, 2, "겹친 refresh 는 완료 후 1회 재실행돼야 한다(드롭 금지)")
    }

    // MARK: Keychain 프롬프트 경로 분리 (회귀)

    /// 회귀 가드: 자동 폴링은 프롬프트 없는 경로(allowKeychainPrompt=false)로만 한도를 조회하고,
    /// macOS Keychain 암호 다이얼로그를 유발할 수 있는 경로는 사용자 명시 동작(설정/팝오버 버튼)에서만
    /// 쓴다. 자동 경로에 true 를 넘기면(과거 회귀: 캐시 만료 폴이 하루 몇 번 암호 팝업을 띄움) 실패한다.
    func testAutoRefreshUsesNoPromptPathManualUsesPromptPath() async {
        let claude = FakeUsageProvider(id: "claude_code", displayName: "Claude Code", daily: todayDaily(1_000))
        let limits = RecordingClaudeLimits(status: claudeLimits(fiveHourUtil: 10))
        let store = UsageStore(providers: [claude],
                               claudeLimitsProvider: limits,
                               codexLimitsProvider: FakeCodexLimits(status: nil),
                               opencodeGoLimitsProvider: FakeOpenCodeGoLimits(status: nil),
                               autoRefresh: false,
                               defaults: testDefaults)

        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertFalse(limits.promptFlags.isEmpty, "자동 refresh 가 한도를 조회해야 한다")
        XCTAssertTrue(limits.promptFlags.allSatisfy { $0 == false },
                      "자동 폴링은 절대 Keychain 프롬프트 경로(true)를 쓰면 안 된다 — 암호 다이얼로그 유발")

        await store.refreshLimitTokenFromKeychain()
        XCTAssertEqual(limits.promptFlags.last, true,
                       "수동 갱신(사용자 버튼)만 프롬프트 허용 경로를 쓴다")
    }

    // MARK: 플로팅 펫 설정 (기본값 + 영속)

    /// 플로팅 펫은 기본 꺼짐(96px). 토글·크기 변경은 defaults 에 영속돼 재시작 후 유지된다.
    /// Bubble alerts default ON (opt-out), nested under the pet — independent of Notification Center.
    func testFloatingPetSettingsDefaultAndPersistence() {
        let claude = FakeUsageProvider(id: "claude_code", displayName: "Claude Code", daily: todayDaily(1_000))
        let store = makeStore(providers: [claude])
        XCTAssertFalse(store.floatingPetEnabled, "옵트인 기능 — 기본은 꺼짐")
        XCTAssertEqual(store.floatingPetSize, 96)
        XCTAssertTrue(store.floatingPetBubbleAlerts, "bubble alerts default on when pet is later enabled")

        store.floatingPetEnabled = true
        store.floatingPetSize = 144
        store.floatingPetBubbleAlerts = false

        let reloaded = makeStore(providers: [claude])   // 같은 suite 재로딩 = 앱 재시작
        XCTAssertTrue(reloaded.floatingPetEnabled)
        XCTAssertEqual(reloaded.floatingPetSize, 144)
        XCTAssertFalse(reloaded.floatingPetBubbleAlerts)
    }

    /// Bubble picker is pure: critical beats warn; within a tier higher utilization wins (stable choice).
    func testBubbleAlertPicksHighestSeverityThenUtilization() {
        let warnLow = UsageStore.LimitAlert(key: "a", window: "A", isCritical: false, utilization: 81)
        let warnHigh = UsageStore.LimitAlert(key: "b", window: "B", isCritical: false, utilization: 90)
        let critLow = UsageStore.LimitAlert(key: "c", window: "C", isCritical: true, utilization: 95)
        let critHigh = UsageStore.LimitAlert(key: "d", window: "D", isCritical: true, utilization: 99)
        XCTAssertNil(UsageStore.bubbleAlert(from: []))
        XCTAssertEqual(UsageStore.bubbleAlert(from: [warnLow, warnHigh]), warnHigh)
        XCTAssertEqual(UsageStore.bubbleAlert(from: [warnHigh, critLow]), critLow)
        XCTAssertEqual(UsageStore.bubbleAlert(from: [critLow, warnHigh, critHigh]), critHigh)
    }

    /// 6s auto-dismiss is a pure time check — testable without AppKit / Task.sleep.
    func testBubbleDismissUsesTTL() {
        let shown = Date(timeIntervalSince1970: 1_000)
        XCTAssertFalse(UsageStore.shouldDismissBubble(shownAt: shown, now: shown.addingTimeInterval(5.9)))
        XCTAssertTrue(UsageStore.shouldDismissBubble(shownAt: shown, now: shown.addingTimeInterval(6)))
        XCTAssertTrue(UsageStore.shouldDismissBubble(shownAt: shown, now: shown.addingTimeInterval(6), ttl: 6))
        XCTAssertFalse(UsageStore.shouldDismissBubble(shownAt: shown, now: shown.addingTimeInterval(3), ttl: 6))
    }

    /// 회귀(#56 표시 버전): compact hover tooltip must not surface a provider unused today.
    /// Claude limits exist after auth even with 0 tokens today — gate like `menuLimitLine`.
    func testHighestLimitUtilizationIgnoresProviderUnusedToday() async {
        let claude = FakeUsageProvider(id: "claude_code", displayName: "Claude Code", daily: nil) // unused today
        let codex = FakeUsageProvider(id: "codex", displayName: "Codex", daily: todayDaily(500_000))
        let store = makeStore(
            providers: [claude, codex],
            claude: claudeLimits(fiveHourUtil: 90),
            codex: codexLimits(primaryUsed: 40))
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(try XCTUnwrap(store.highestLimitUtilization), 40, accuracy: 0.01,
                       "Claude util must not leak into the pet tooltip when Claude unused today")
    }

    /// Codex personal/spend limit is dollars — never fold it into token-limit utilization (candyEligibleWindows parity).
    func testHighestLimitUtilizationExcludesCodexIndividualSpendLimit() async {
        let codex = FakeUsageProvider(id: "codex", displayName: "Codex", daily: todayDaily(10_000))
        // primary 30%; individual remainingPercent 1 → usedPercent 99 — only primary should win
        let json = """
        {"rateLimits":{"primary":{"usedPercent":30,"windowDurationMins":300},\
        "individualLimit":{"limit":"$100","remainingPercent":1,"resetsAt":9999999999,"used":"$99"}}}
        """
        let status = try! JSONDecoder().decode(CodexRateLimitStatus.self, from: Data(json.utf8))
        let store = makeStore(providers: [codex], codex: status)
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(try XCTUnwrap(store.highestLimitUtilization), 30, accuracy: 0.01)
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

    /// [회귀] OpenAI 전역 상태가 이미지 생성 장애로 minor 여도 Codex API 구성요소가 정상이면
    /// Codex 탭에 "일부 장애"를 표시하면 안 된다.
    func testCodexStatusIgnoresUnrelatedGlobalIncident() {
        let data = Data(#"""
        {
          "status":{"indicator":"minor","description":"Partial System Degradation"},
          "components":[
            {"name":"Image Generation","status":"degraded_performance"},
            {"name":"Codex API","status":"operational"}
          ]
        }
        """#.utf8)
        let status = StatuspageStatusProvider.parseComponent(data, named: "Codex API")
        XCTAssertEqual(status?.indicator, .operational)
        XCTAssertFalse(status!.indicator.hasIssue)
        XCTAssertEqual(status?.description, "Codex API")
    }

    /// 실제 해당 구성요소가 저하됐을 때는 경고를 유지한다.
    func testProviderComponentDegradationMapsToIssue() {
        let data = Data(#"{"components":[{"name":"Claude Code","status":"degraded_performance"}]}"#.utf8)
        let status = StatuspageStatusProvider.parseComponent(data, named: "Claude Code")
        XCTAssertEqual(status?.indicator, .minor)
        XCTAssertTrue(status!.indicator.hasIssue)
        XCTAssertNil(StatuspageStatusProvider.parseComponent(data, named: "Codex API"))
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

    // MARK: 한도 표시 방식 (used / remaining)

    /// 표시 변환 순수 판정 — remaining = 100−사용률, 0 하한(사용률 100 초과 시 음수 금지), 경계 포함.
    func testLimitDisplayPercentModes() {
        XCTAssertEqual(UsageStore.displayPercent(40, mode: .used), 40)
        XCTAssertEqual(UsageStore.displayPercent(40, mode: .remaining), 60)
        XCTAssertEqual(UsageStore.displayPercent(0, mode: .remaining), 100)
        XCTAssertEqual(UsageStore.displayPercent(100, mode: .remaining), 0)
        XCTAssertEqual(UsageStore.displayPercent(120, mode: .remaining), 0, "100% 초과 사용 → 남은 양 0 클램프")
        XCTAssertEqual(UsageStore.displayPercent(40.5, mode: .remaining), 59.5, "소수 유지")
    }

    /// remaining 모드의 메뉴바 한도 줄 — 숫자만 반전, 프로바이더 라벨·조합 규칙은 그대로.
    func testMenuBarLimitRemainingModeInvertsPercents() async {
        let claude = FakeUsageProvider(id: "claude_code", displayName: "Claude Code", daily: todayDaily(10_000_000))
        let codex = FakeUsageProvider(id: "codex", displayName: "Codex", daily: todayDaily(5_000_000))
        let store = makeStore(
            providers: [claude, codex],
            claude: claudeLimits(fiveHourUtil: 40, resetsAt: "2099-01-01T00:00:00Z"),
            codex: codexLimits(primaryUsed: 85))
        store.showTokensInMenu = false
        store.showCostInMenu = false
        store.showLimitInMenu = true
        store.limitDisplayMode = .remaining
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertTrue(store.menuTitle.contains("Claude 60%"), "used 40 → remaining 60: \(store.menuTitle)")
        XCTAssertTrue(store.menuTitle.contains("Codex 15%"), "used 85 → remaining 15: \(store.menuTitle)")

        store.limitDisplayMode = .used
        XCTAssertTrue(store.menuTitle.contains("Claude 40%"), "used 모드 복귀: \(store.menuTitle)")
    }

    /// 설정 영속 — 기본은 used(기존 사용자 무변화), remaining 선택은 재시작(같은 defaults 재로드) 후 유지.
    func testLimitDisplayModePersistsAcrossRestart() {
        let s1 = makeStore(providers: [])
        XCTAssertEqual(s1.limitDisplayMode, .used, "기본값 = used(현행 표시 유지)")
        s1.limitDisplayMode = .remaining
        let s2 = makeStore(providers: [])
        XCTAssertEqual(s2.limitDisplayMode, .remaining, "같은 defaults 재로드 → 유지")
    }

    /// 설정 영속 — 기본은 powerSaver(이 설정 이전의 고정 캡과 동일), 선택은 재시작 후 유지.
    func testAnimationQualityPersistsAcrossRestart() {
        let s1 = makeStore(providers: [])
        XCTAssertEqual(s1.animationQuality, .powerSaver, "기본값 = powerSaver(기존 동작 보존)")
        s1.animationQuality = .smooth
        let s2 = makeStore(providers: [])
        XCTAssertEqual(s2.animationQuality, .smooth, "같은 defaults 재로드 → 유지")
    }

    // MARK: 집계

    func testAggregatesTodayTokensAcrossProviders() async {
        let claude = FakeUsageProvider(id: "claude_code", displayName: "Claude Code", daily: todayDaily(100_000_000))
        let codex = FakeUsageProvider(id: "codex", displayName: "Codex", daily: todayDaily(50_000_000))
        let store = makeStore(providers: [claude, codex])
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(store.todayTotalTokens, 150_000_000)
        XCTAssertEqual(store.todayTokensByProvider,
                       ["claude_code": 100_000_000, "codex": 50_000_000])
        XCTAssertEqual(store.todayTokensByProvider.values.reduce(0, +), store.todayTotalTokens)
        XCTAssertNotNil(store.lastUpdated)
        XCTAssertNil(store.lastErrorDescription)
    }

    /// [issue #115 DoD] 신규 provider(kiro) 의 snapshot 이 today/week/month/burn 전부에 흘러가는지 확인.
    /// (파서/스키마 회귀는 KiroUsageTests.swift 담당 — 여기는 store 집계 경로만 본다.)
    func testKiroSnapshotFlowsThroughTodayWeekMonthAndBurn() async {
        let claude = FakeUsageProvider(id: "claude_code", displayName: "Claude Code", daily: todayDaily(100_000_000))
        let kiro = FakeUsageProvider(id: "kiro", displayName: "Kiro", daily: todayDaily(50_000_000), reportsCost: false)
        kiro.enrichment = ProviderEnrichment(
            activeBlock: block(tokensPerMinute: 200_000), blocksOK: true,
            weekTotal: PeriodUsage(period: "w", totalTokens: 90_000_000, totalCost: 0),
            monthTotal: PeriodUsage(period: "m", totalTokens: 300_000_000, totalCost: 0),
            periodsOK: true)
        let store = makeStore(providers: [claude, kiro])
        await store.refresh(scheduleEmptyRetry: false)

        XCTAssertEqual(store.todayTotalTokens, 150_000_000)
        XCTAssertEqual(store.todayTokensByProvider["kiro"], 50_000_000)
        XCTAssertEqual(store.weekTotalTokens, 90_000_000)
        XCTAssertEqual(store.monthTotalTokens, 300_000_000)
        XCTAssertEqual(store.burnTier, .fast, "burn 이 kiro 의 활성 블록을 반영")
        XCTAssertEqual(store.snapshot(preferring: "kiro")?.providerID, "kiro", "탭에 노출됨")
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
        XCTAssertEqual(store.todayTokensByProvider, ["codex": 50_000_000])
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
        XCTAssertEqual(store.todayTokensByProvider, ["claude_code": 100_000_000])
    }

    /// [회귀] 한 provider의 성공 응답이 today=nil이 된 partial snapshot에서도 다른 provider의
    /// 당일 값은 유지하고, 빠졌던 provider가 실제 refresh 결과에 복귀하면 다시 map에 포함한다.
    /// CompanionStore가 이 map을 소비할 때 provider별 ledger line을 보존할 수 있도록 하는 경계 테스트다.
    func testRefreshPreservesProviderIdentityAcrossPartialSnapshotLossAndRecovery() async {
        let claude = FakeUsageProvider(id: "claude_code", displayName: "Claude Code",
                                       daily: todayDaily(1_000))
        let codex = FakeUsageProvider(id: "codex", displayName: "Codex", daily: todayDaily(500))
        let store = makeStore(providers: [claude, codex])

        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(store.todayTokensByProvider,
                       ["claude_code": 1_000, "codex": 500])

        // 성공했지만 오늘 데이터가 없는 응답은 해당 provider snapshot을 제거한다.
        codex.daily = nil
        claude.daily = todayDaily(1_200)
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(store.todayTokensByProvider, ["claude_code": 1_200])
        XCTAssertEqual(store.snapshots.map(\.providerID), ["claude_code"])

        // 복구된 provider는 같은 provider ID로 map에 돌아온다.
        codex.daily = todayDaily(700)
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(store.todayTokensByProvider,
                       ["claude_code": 1_200, "codex": 700])
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

    // MARK: OpenCode Go 한도

    func testLimitWarningFromOpenCodeGoMonthly() async {
        let opencode = FakeUsageProvider(id: "opencode", displayName: "OpenCode", daily: todayDaily(1_000_000))
        let store = makeStore(providers: [opencode],
                              opencodeGo: opencodeGoLimits(rolling: 3, weekly: 41, monthly: 97))
        store.critThreshold = 95
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertTrue(store.isLimitWarning, "월간 97% ≥ crit 95 → 경고")
    }

    func testNoLimitWarningWhenOpenCodeGoUnderCritical() async {
        let opencode = FakeUsageProvider(id: "opencode", displayName: "OpenCode", daily: todayDaily(1_000_000))
        let store = makeStore(providers: [opencode],
                              opencodeGo: opencodeGoLimits(rolling: 2, weekly: 41, monthly: 20))
        store.critThreshold = 95
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertFalse(store.isLimitWarning)
        XCTAssertTrue(store.limitsReady, "Go 한도만 있어도 limitsReady(사탕 시드 게이트)")
    }

    func testMenuBarLimitIncludesOpenCodeGoWhenUsedToday() async {
        let opencode = FakeUsageProvider(id: "opencode", displayName: "OpenCode", daily: todayDaily(1_000_000))
        let store = makeStore(providers: [opencode],
                              opencodeGo: opencodeGoLimits(rolling: 2, weekly: 41, monthly: 20))
        store.showTokensInMenu = false
        store.showCostInMenu = false
        store.showLimitInMenu = true
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(store.menuTitle, "OpenCode 41%", "세 창 최대값(41) 표기")
    }

    /// 오늘 사용 게이트 — OpenCode 를 안 썼으면 한도가 로드돼도 메뉴바에 뜨지 않는다(codex 와 대칭).
    func testMenuBarLimitExcludesOpenCodeGoWhenNotUsedToday() async {
        let claude = FakeUsageProvider(id: "claude_code", displayName: "Claude Code", daily: todayDaily(1_000))
        let opencode = FakeUsageProvider(id: "opencode", displayName: "OpenCode", daily: nil)
        let store = makeStore(providers: [claude, opencode],
                              claude: claudeLimits(fiveHourUtil: 42),
                              opencodeGo: opencodeGoLimits(weekly: 90))
        store.showTokensInMenu = false
        store.showCostInMenu = false
        store.showLimitInMenu = true
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(store.menuTitle, "Claude 42%", "미사용 프로바이더 한도는 메뉴바 제외")
    }

    /// highestLimitUtilization 도 오늘 사용 게이트를 따른다 — compact 표면 오염 방지.
    func testHighestLimitUtilizationGatesOpenCodeGoByTodayUsage() async {
        let opencode = FakeUsageProvider(id: "opencode", displayName: "OpenCode", daily: todayDaily(1_000))
        let used = makeStore(providers: [opencode], opencodeGo: opencodeGoLimits(weekly: 77))
        await used.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(used.highestLimitUtilization, 77)

        let unused = FakeUsageProvider(id: "opencode", displayName: "OpenCode", daily: nil)
        let idle = makeStore(providers: [unused], opencodeGo: opencodeGoLimits(weekly: 77))
        await idle.refresh(scheduleEmptyRetry: false)
        XCTAssertNil(idle.highestLimitUtilization)
    }

    /// 사탕 지급 대상 창 — Go 세 창이 각각 세션/주간/주간급으로 들어간다.
    func testCandyEligibleWindowsIncludeOpenCodeGo() async {
        let opencode = FakeUsageProvider(id: "opencode", displayName: "OpenCode", daily: todayDaily(1_000))
        let store = makeStore(providers: [opencode],
                              opencodeGo: opencodeGoLimits(rolling: 5, weekly: 50, monthly: 30))
        await store.refresh(scheduleEmptyRetry: false)
        let windows = store.candyEligibleWindows
        XCTAssertEqual(windows.count, 3)
        XCTAssertEqual(windows.map(\.key), ["opencodeGo.rolling", "opencodeGo.weekly", "opencodeGo.monthly"])
        XCTAssertEqual(windows.first { $0.key == "opencodeGo.rolling" }?.kind, .session)
        XCTAssertEqual(windows.first { $0.key == "opencodeGo.weekly" }?.kind, .weekly)
        XCTAssertEqual(windows.first { $0.key == "opencodeGo.monthly" }?.kind, .weekly)
    }

    /// 폴링 스로틀 — 5분 최소 간격 동안 다시 fetch 하지 않는다(실패 포함, 서버 예의).
    func testOpenCodeGoFetchThrottledWithinPollInterval() async {
        let stub = CountingOpenCodeGoLimits()
        stub.status = opencodeGoLimits(weekly: 41)
        let opencode = FakeUsageProvider(id: "opencode", displayName: "OpenCode", daily: todayDaily(1_000))
        let store = UsageStore(providers: [opencode],
                               claudeLimitsProvider: FakeClaudeLimits(status: nil),
                               codexLimitsProvider: FakeCodexLimits(status: nil),
                               opencodeGoLimitsProvider: stub,
                               autoRefresh: false, defaults: testDefaults)
        await store.refresh(scheduleEmptyRetry: false)
        await store.refresh(scheduleEmptyRetry: false)
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(stub.calls, 1, "스로틀 미적용 시 매 refresh(기본 2분)마다 요청한다")
        XCTAssertEqual(store.opencodeGoLimits?.weekly?.percent, 41)
    }

    /// 조회 실패(403 등) → 한도 없음 상태 유지(codex 와 동일하게 catch 후 조용히 숨김).
    /// 같은 스토어에서 성공→실패 전환은 스로틀(시도마다 5분) 때문에 도달 불가 — 검증 대상이 아니다.
    func testOpenCodeGoFailureLeavesLimitsHidden() async {
        let stub = CountingOpenCodeGoLimits()
        stub.error = LimitsError.httpStatus(403)
        let opencode = FakeUsageProvider(id: "opencode", displayName: "OpenCode", daily: todayDaily(1_000))
        let store = UsageStore(providers: [opencode],
                               claudeLimitsProvider: FakeClaudeLimits(status: nil),
                               codexLimitsProvider: FakeCodexLimits(status: nil),
                               opencodeGoLimitsProvider: stub,
                               autoRefresh: false, defaults: testDefaults)
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertNil(store.opencodeGoLimits, "실패 → 섹션 숨김")
        XCTAssertFalse(store.limitsReady)
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

    // MARK: 프로바이더 표시/숨김 설정

    func testProviderVisibilityTogglePersistsAndFiltersUsageAndLimits() async {
        let claude = FakeUsageProvider(id: "claude_code", displayName: "Claude Code", daily: todayDaily(1_000))
        let codex = FakeUsageProvider(id: "codex", displayName: "Codex", daily: todayDaily(2_000))
        let opencode = FakeUsageProvider(id: "opencode", displayName: "OpenCode", daily: todayDaily(3_000))
        let claudeLim = RecordingClaudeLimits(status: claudeLimits(fiveHourUtil: 50))
        let codexLim = FakeCodexLimits(status: codexLimits(primaryUsed: 20))
        let goLim = FakeOpenCodeGoLimits(status: opencodeGoLimits(rolling: 30))

        let store = UsageStore(
            providers: [claude, codex, opencode],
            claudeLimitsProvider: claudeLim,
            codexLimitsProvider: codexLim,
            opencodeGoLimitsProvider: goLim,
            autoRefresh: false,
            remoteLimitsPollInterval: 0,
            defaults: testDefaults)

        await store.refresh(scheduleEmptyRetry: false)

        XCTAssertTrue(store.isProviderVisible("claude_code"))
        XCTAssertTrue(store.isProviderVisible("codex"))
        XCTAssertTrue(store.isProviderVisible("opencode"))
        XCTAssertEqual(store.todayTotalTokens, 6_000)
        XCTAssertEqual(store.snapshots.count, 3)
        XCTAssertNotNil(store.limits)
        XCTAssertNotNil(store.codexLimits)
        XCTAssertNotNil(store.opencodeGoLimits)

        // Hide OpenCode
        store.setProvider("opencode", visible: false)
        XCTAssertFalse(store.isProviderVisible("opencode"))
        XCTAssertEqual(testDefaults.stringArray(forKey: "hiddenProviders"), ["opencode"])

        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(store.todayTotalTokens, 3_000)
        XCTAssertEqual(store.snapshots.map { $0.providerID }, ["claude_code", "codex"])
        XCTAssertNil(store.opencodeGoLimits)
        XCTAssertNotNil(store.limits)
        XCTAssertNotNil(store.codexLimits)

        // Hide Claude
        store.setProvider("claude_code", visible: false)
        XCTAssertFalse(store.isProviderVisible("claude_code"))

        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(store.todayTotalTokens, 2_000)
        XCTAssertEqual(store.snapshots.map { $0.providerID }, ["codex"])
        XCTAssertNil(store.limits)
        XCTAssertFalse(store.limitsAvailable)
        XCTAssertNotNil(store.codexLimits)

        // Unhide OpenCode
        store.setProvider("opencode", visible: true)
        XCTAssertTrue(store.isProviderVisible("opencode"))

        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(store.todayTotalTokens, 5_000)
        XCTAssertEqual(store.snapshots.map { $0.providerID }, ["codex", "opencode"])
        XCTAssertNotNil(store.opencodeGoLimits)
    }

    func testProviderVisibilityInitializesFromUserDefaults() {
        testDefaults.set(["codex", "opencode"], forKey: "hiddenProviders")
        let store = UsageStore(autoRefresh: false, defaults: testDefaults)
        XCTAssertFalse(store.isProviderVisible("codex"))
        XCTAssertFalse(store.isProviderVisible("opencode"))
        XCTAssertTrue(store.isProviderVisible("claude_code"))
    }

    // MARK: stale

    // MARK: 세션 만료(401) UX

    /// 키를 넣은 사용자가 한도를 영영 못 본다.
    func testKeychainDisabledStillFetchesLimitsWhenSessionKeyIsConfigured() async {
        let claude = FakeUsageProvider(id: "claude_code", displayName: "Claude Code", daily: todayDaily(1_000))
        let limits = RecordingClaudeLimits(status: claudeLimits(fiveHourUtil: 10))
        testDefaults.set(true, forKey: "disableKeychainAccess")
        let store = UsageStore(providers: [claude],
                               claudeLimitsProvider: limits,
                               codexLimitsProvider: FakeCodexLimits(status: nil),
                               sessionKeys: StubSessionKeys(credential: .init(key: "sk", organizationID: "org")),
                               autoRefresh: false,
                               defaults: testDefaults)

        XCTAssertTrue(store.sessionKeyConfigured, "저장된 키는 기동 시 인식돼야 한다")
        await store.refresh(scheduleEmptyRetry: false)

        XCTAssertTrue(store.limitsAvailable, "세션 키가 있으면 Keychain 토글과 무관하게 한도가 떠야 한다")
        XCTAssertEqual(limits.promptFlags, [false], "그래도 프롬프트 경로는 쓰지 않는다")
    }

    /// 키가 없으면 기존 동작 그대로 — 토글이 켜져 있으면 조회 자체를 하지 않는다(팝업 원천 차단).
    func testKeychainDisabledSkipsLimitsWithoutSessionKey() async {
        let claude = FakeUsageProvider(id: "claude_code", displayName: "Claude Code", daily: todayDaily(1_000))
        let limits = RecordingClaudeLimits(status: claudeLimits(fiveHourUtil: 10))
        testDefaults.set(true, forKey: "disableKeychainAccess")
        let store = UsageStore(providers: [claude],
                               claudeLimitsProvider: limits,
                               codexLimitsProvider: FakeCodexLimits(status: nil),
                               sessionKeys: StubSessionKeys(credential: nil),
                               autoRefresh: false,
                               defaults: testDefaults)

        await store.refresh(scheduleEmptyRetry: false)

        XCTAssertTrue(limits.promptFlags.isEmpty, "키가 없고 토글이 켜져 있으면 한도 조회를 아예 하지 않는다")
        XCTAssertFalse(store.limitsAvailable)
    }

    /// 붙여넣기 → 검증 → 저장. 사용 중인 조직을 자동으로 골라야 한다(목록의 첫 번째가 아니라).
    func testSaveSessionKeyValidatesAndPicksOrgWithUsage() async {
        let claude = FakeUsageProvider(id: "claude_code", displayName: "Claude Code", daily: todayDaily(1_000))
        let keys = StubSessionKeys(credential: nil,
                                   organizations: [sessionOrg("org-idle", hasUsage: false),
                                                   sessionOrg("org-active", hasUsage: true)])
        let store = UsageStore(providers: [claude],
                              claudeLimitsProvider: FakeClaudeLimits(status: claudeLimits(fiveHourUtil: 7)),
                              codexLimitsProvider: FakeCodexLimits(status: nil),
                              sessionKeys: keys, autoRefresh: false, defaults: testDefaults)

        await store.saveSessionKey("  sk-ant-sid02-\(String(repeating: "a", count: 60))\n")

        XCTAssertNil(store.sessionKeyError)
        XCTAssertTrue(store.sessionKeyConfigured)
        XCTAssertEqual(store.sessionKeySelectedOrgID, "org-active", "값이 있는 조직을 골라야 한다")
        XCTAssertEqual(keys.saves.last?.key.hasSuffix("aaa"), true, "공백·줄바꿈은 잘라서 저장한다")
        XCTAssertEqual(store.sessionKeyOrganizations.count, 2, "드롭다운용 후보는 남겨둔다")
    }

    /// 형식이 틀리면 저장하지 않고 안내만 띄운다 — 잘못된 키로 폴링을 시작하면 매번 401 을 맞는다.
    func testSaveSessionKeyRejectsMalformedInputWithoutStoring() async {
        let claude = FakeUsageProvider(id: "claude_code", displayName: "Claude Code", daily: todayDaily(1_000))
        let keys = StubSessionKeys(credential: nil, organizations: [sessionOrg("org", hasUsage: true)])
        let store = UsageStore(providers: [claude],
                              claudeLimitsProvider: FakeClaudeLimits(status: nil),
                              codexLimitsProvider: FakeCodexLimits(status: nil),
                              sessionKeys: keys, autoRefresh: false, defaults: testDefaults)

        store.localizationLanguage = .ko   // 스토어가 만든 문구를 비교하므로 언어를 고정한다
        await store.saveSessionKey("not-a-session-key")

        XCTAssertFalse(store.sessionKeyConfigured)
        XCTAssertTrue(keys.saves.isEmpty, "형식 검증을 통과하지 못한 값은 저장하지 않는다")
        XCTAssertEqual(store.sessionKeyError, L(.ko).sessionKeyMalformedError)
    }

    /// 키에 보이는 조직이 없으면(전부 403) 저장하지 않는다 — 저장해도 한도를 못 본다.
    func testSaveSessionKeyRejectsKeyWithNoVisibleOrganization() async {
        let claude = FakeUsageProvider(id: "claude_code", displayName: "Claude Code", daily: todayDaily(1_000))
        let keys = StubSessionKeys(credential: nil, organizations: [])
        let store = UsageStore(providers: [claude],
                              claudeLimitsProvider: FakeClaudeLimits(status: nil),
                              codexLimitsProvider: FakeCodexLimits(status: nil),
                              sessionKeys: keys, autoRefresh: false, defaults: testDefaults)

        store.localizationLanguage = .ko   // 스토어가 만든 문구를 비교하므로 언어를 고정한다
        await store.saveSessionKey("sk-ant-sid02-\(String(repeating: "a", count: 60))")

        XCTAssertFalse(store.sessionKeyConfigured)
        XCTAssertTrue(keys.saves.isEmpty)
        XCTAssertEqual(store.sessionKeyError, L(.ko).sessionKeyNoOrgError)
    }

    func testClearSessionKeyResetsStateAndStorage() async {
        let claude = FakeUsageProvider(id: "claude_code", displayName: "Claude Code", daily: todayDaily(1_000))
        let keys = StubSessionKeys(credential: .init(key: "sk", organizationID: "org-active"),
                                   organizations: [sessionOrg("org-active", hasUsage: true)])
        let store = UsageStore(providers: [claude],
                              claudeLimitsProvider: FakeClaudeLimits(status: claudeLimits(fiveHourUtil: 7)),
                              codexLimitsProvider: FakeCodexLimits(status: nil),
                              sessionKeys: keys, autoRefresh: false, defaults: testDefaults)
        XCTAssertTrue(store.sessionKeyConfigured)

        store.clearSessionKey()

        XCTAssertTrue(keys.cleared)
        XCTAssertFalse(store.sessionKeyConfigured)
        XCTAssertNil(store.sessionKeySelectedOrgID)
        XCTAssertTrue(store.sessionKeyOrganizations.isEmpty)
    }

    /// 자동 선택이 틀렸을 때 사용자가 조직을 바꾼다 — 같은 키로 조직만 갈아끼워 저장해야 한다.
    func testSelectSessionOrganizationSwitchesOrgKeepingTheKey() async {
        let claude = FakeUsageProvider(id: "claude_code", displayName: "Claude Code", daily: todayDaily(1_000))
        let keys = StubSessionKeys(credential: .init(key: "sk-ant-sid02-abc", organizationID: "org-a"))
        let store = UsageStore(providers: [claude],
                              claudeLimitsProvider: FakeClaudeLimits(status: claudeLimits(fiveHourUtil: 7)),
                              codexLimitsProvider: FakeCodexLimits(status: nil),
                              sessionKeys: keys, autoRefresh: false, defaults: testDefaults)

        await store.selectSessionOrganization("org-b")

        XCTAssertEqual(keys.saves.last?.organizationID, "org-b")
        XCTAssertEqual(keys.saves.last?.key, "sk-ant-sid02-abc", "키는 그대로 유지돼야 한다")
        XCTAssertEqual(store.sessionKeySelectedOrgID, "org-b")
    }

    /// 재시작 후에는 후보 목록이 비어 있다 — 설정을 열 때 다시 채워야 조직을 바꿀 수 있다.
    func testRefreshSessionOrganizationsRepopulatesAfterRestart() async {
        let claude = FakeUsageProvider(id: "claude_code", displayName: "Claude Code", daily: todayDaily(1_000))
        let keys = StubSessionKeys(credential: .init(key: "sk-ant-sid02-abc", organizationID: "org-b"),
                                   organizations: [sessionOrg("org-a", hasUsage: false),
                                                   sessionOrg("org-b", hasUsage: true)])
        let store = UsageStore(providers: [claude],
                              claudeLimitsProvider: FakeClaudeLimits(status: claudeLimits(fiveHourUtil: 7)),
                              codexLimitsProvider: FakeCodexLimits(status: nil),
                              sessionKeys: keys, autoRefresh: false, defaults: testDefaults)
        XCTAssertTrue(store.sessionKeyOrganizations.isEmpty, "기동 직후에는 후보를 모른다(네트워크 미조회)")

        await store.refreshSessionOrganizations()

        XCTAssertEqual(store.sessionKeyOrganizations.map(\.id), ["org-a", "org-b"])
        XCTAssertEqual(store.sessionKeySelectedOrgID, "org-b", "저장된 선택을 그대로 반영해야 한다")
    }

    /// 키가 없으면 네트워크를 치지 않는다 — 설정을 여는 것만으로 조회가 나가면 안 된다.
    func testRefreshSessionOrganizationsDoesNothingWithoutKey() async {
        let claude = FakeUsageProvider(id: "claude_code", displayName: "Claude Code", daily: todayDaily(1_000))
        let keys = StubSessionKeys(credential: nil, organizations: [sessionOrg("org-a", hasUsage: true)])
        let store = UsageStore(providers: [claude],
                              claudeLimitsProvider: FakeClaudeLimits(status: nil),
                              codexLimitsProvider: FakeCodexLimits(status: nil),
                              sessionKeys: keys, autoRefresh: false, defaults: testDefaults)

        await store.refreshSessionOrganizations()

        XCTAssertTrue(store.sessionKeyOrganizations.isEmpty)
    }

    // MARK: 플로팅 펫 설정 (기본값 + 영속)

    func testLimitsAuthExpiredSetOn401AndClearedOnSuccess() async {
        let claude = FakeUsageProvider(id: "claude_code", displayName: "Claude Code", daily: todayDaily(10_000_000))
        let seq = SequenceClaudeLimits(errors: [LimitsError.httpStatus(401)],
                                       success: claudeLimits(fiveHourUtil: 12, resetsAt: "2099-01-01T00:00:00Z"))
        // 이 테스트의 관심사는 401 설정/해제이지 폴 간격이 아니다 — 간격을 꺼서 두 번째 refresh 가
        // 실제로 조회하게 한다(간격 자체는 LimitsPollCadenceTests 가 검증).
        let store = UsageStore(providers: [claude], claudeLimitsProvider: seq,
                               codexLimitsProvider: FakeCodexLimits(status: nil),
                               opencodeGoLimitsProvider: FakeOpenCodeGoLimits(status: nil),
                               autoRefresh: false, remoteLimitsPollInterval: 0,
                               defaults: testDefaults)
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertTrue(store.limitsAuthExpired, "401 → 세션 만료 안내 상태")
        await store.refresh(scheduleEmptyRetry: false)   // 이번엔 성공
        XCTAssertFalse(store.limitsAuthExpired, "성공 시 해제")
    }

    /// 그 팝업을 띄운다. 그래서 만료의 **출처**를 남긴다.
    func testSessionKeyExpiryIsDistinguishedFromOAuthExpiry() async {
        let claude = FakeUsageProvider(id: "claude_code", displayName: "Claude Code", daily: todayDaily(10_000_000))
        let store = UsageStore(providers: [claude],
                               claudeLimitsProvider: SequenceClaudeLimits(errors: [LimitsError.sessionKeyInvalid]),
                               codexLimitsProvider: FakeCodexLimits(status: nil),
                               autoRefresh: false, defaults: testDefaults)
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(store.limitsAuthExpiry, .sessionKey, "세션 키 401 → 세션 키 만료로 식별돼야 한다")
        XCTAssertTrue(store.limitsAuthExpired, "기존 불리언 계약은 그대로 유지")
    }

    /// OAuth 401 은 세션 키 만료로 오인되면 안 된다 — 반대 방향 오분류 가드.
    func testOAuthExpiryIsNotReportedAsSessionKeyExpiry() async {
        let claude = FakeUsageProvider(id: "claude_code", displayName: "Claude Code", daily: todayDaily(10_000_000))
        let store = UsageStore(providers: [claude],
                               claudeLimitsProvider: SequenceClaudeLimits(errors: [LimitsError.httpStatus(401)]),
                               codexLimitsProvider: FakeCodexLimits(status: nil),
                               autoRefresh: false, defaults: testDefaults)
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(store.limitsAuthExpiry, .oauth, "OAuth 401 → OAuth 만료")
    }

    /// 만료 출처는 성공하면 사라져야 한다 — 남으면 한도가 정상인데 만료 배너가 계속 뜬다.
    func testSessionKeyExpiryClearsOnSuccess() async {
        let claude = FakeUsageProvider(id: "claude_code", displayName: "Claude Code", daily: todayDaily(10_000_000))
        let seq = SequenceClaudeLimits(errors: [LimitsError.sessionKeyInvalid],
                                       success: claudeLimits(fiveHourUtil: 12, resetsAt: "2099-01-01T00:00:00Z"))
        // 이 테스트의 관심사는 만료 해제이지 폴 간격이 아니다 — 간격을 꺼서 두 번째 refresh 가
        // 실제로 조회하게 한다(간격 자체는 LimitsPollCadenceTests 가 검증).
        let store = UsageStore(providers: [claude], claudeLimitsProvider: seq,
                               codexLimitsProvider: FakeCodexLimits(status: nil),
                               autoRefresh: false, remoteLimitsPollInterval: 0,
                               defaults: testDefaults)
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(store.limitsAuthExpiry, .sessionKey)
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertNil(store.limitsAuthExpiry, "성공 시 해제")
    }

    /// [회귀] 설정 화면의 세션 키 배지는 `sessionKeyConfigured` 만 보고 그려졌다 — 그 값은 키가
    /// 만료돼도 true 라, 팝오버에서 "만료"를 보고 설정에 들어가면 여전히 "설정됨"이라 적혀 있었다.
    /// 사용자가 "뭘 해야 하지"에서 막히던 지점이라 만료를 배지가 읽을 수 있는 상태로 노출한다.
    func testSessionKeyExpiredIsVisibleWhileKeyIsStillStored() async {
        let claude = FakeUsageProvider(id: "claude_code", displayName: "Claude Code", daily: todayDaily(10_000_000))
        let store = UsageStore(providers: [claude],
                               claudeLimitsProvider: SequenceClaudeLimits(errors: [LimitsError.sessionKeyInvalid]),
                               codexLimitsProvider: FakeCodexLimits(status: nil),
                               sessionKeys: StubSessionKeys(credential: .init(key: "sk", organizationID: "org")),
                               autoRefresh: false, defaults: testDefaults)
        XCTAssertFalse(store.sessionKeyExpired, "만료 전에는 평상시 배지")
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertTrue(store.sessionKeyConfigured, "키는 여전히 저장돼 있다 — 지우는 건 사용자 몫")
        XCTAssertTrue(store.sessionKeyExpired, "그래도 배지는 '만료됨' 이어야 한다")
    }

    /// 키를 넣은 적 없는 사용자의 OAuth 만료가 세션 키 배지를 건드리면 안 된다.
    func testOAuthExpiryDoesNotMarkSessionKeyExpired() async {
        let claude = FakeUsageProvider(id: "claude_code", displayName: "Claude Code", daily: todayDaily(10_000_000))
        let store = UsageStore(providers: [claude],
                               claudeLimitsProvider: SequenceClaudeLimits(errors: [LimitsError.httpStatus(401)]),
                               codexLimitsProvider: FakeCodexLimits(status: nil),
                               sessionKeys: StubSessionKeys(credential: nil),
                               autoRefresh: false, defaults: testDefaults)
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertFalse(store.sessionKeyExpired)
    }

    func testLimitsAuthExpiredNotSetOnNon401() async {
        let claude = FakeUsageProvider(id: "claude_code", displayName: "Claude Code", daily: todayDaily(10_000_000))
        let store = UsageStore(providers: [claude],
                               claudeLimitsProvider: SequenceClaudeLimits(errors: [LimitsError.httpStatus(500)]),
                               codexLimitsProvider: FakeCodexLimits(status: nil),
                               opencodeGoLimitsProvider: FakeOpenCodeGoLimits(status: nil),
                               autoRefresh: false, defaults: testDefaults)
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertFalse(store.limitsAuthExpired, "500 은 세션 만료 아님 — 오탐 방지")
    }

    /// 403 은 "인증은 됐고 권한이 없다"라 재로그인으로 풀리지 않는다. 세션 만료로 표시하면
    /// 사용자는 고쳐지지 않는 조치를 반복하고, 그 안내가 재시도 행까지 가려 막다른 길이 된다
    /// (실측 2026-08-31: antigravity CLI 자격증명 → retrieveUserQuotaSummary 403).
    func testLimitsAuthExpiredNotSetOn403() async {
        let claude = FakeUsageProvider(id: "claude_code", displayName: "Claude Code", daily: todayDaily(10_000_000))
        let store = UsageStore(providers: [claude],
                               claudeLimitsProvider: SequenceClaudeLimits(errors: [LimitsError.httpStatus(403)]),
                               codexLimitsProvider: FakeCodexLimits(status: nil),
                               opencodeGoLimitsProvider: FakeOpenCodeGoLimits(status: nil),
                               autoRefresh: false, defaults: testDefaults)
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertFalse(store.limitsAuthExpired,
                       "403 을 세션 만료로 표시하면 재로그인해도 사라지지 않는 안내가 남는다")
    }

    func testAntigravityAuthExpiredSetOn401ButNotOn403() async {
        let claude = FakeUsageProvider(id: "claude_code", displayName: "Claude Code", daily: todayDaily(10_000_000))
        func store(throwing error: LimitsError) -> UsageStore {
            UsageStore(providers: [claude],
                       claudeLimitsProvider: FakeClaudeLimits(status: nil),
                       codexLimitsProvider: FakeCodexLimits(status: nil),
                       opencodeGoLimitsProvider: FakeOpenCodeGoLimits(status: nil),
                       antigravityLimitsProvider: ThrowingAntigravityLimits(error: error),
                       autoRefresh: false, defaults: testDefaults)
        }

        let unauthenticated = store(throwing: .httpStatus(401))
        await unauthenticated.refresh(scheduleEmptyRetry: false)
        XCTAssertTrue(unauthenticated.antigravityLimitsAuthExpired, "401 은 재로그인이 답이다")

        let forbidden = store(throwing: .httpStatus(403))
        await forbidden.refresh(scheduleEmptyRetry: false)
        XCTAssertFalse(forbidden.antigravityLimitsAuthExpired,
                       "403 에 만료 안내를 띄우면 CLI 사용자에게 영구히 지워지지 않는다")
    }

    /// 403 을 "HTTP 403" 으로만 보여주면 사용자는 재로그인을 시도한다 — 그 조치로는 안 풀린다.
    func testForbiddenGetsItsOwnMessageNotAGenericHTTPError() {
        let l = L(.en)
        XCTAssertEqual(UsageStore.friendlyLimitError(LimitsError.httpStatus(403), l), l.limitRefreshForbidden)
        XCTAssertEqual(UsageStore.friendlyLimitError(LimitsError.httpStatus(500), l), l.limitRefreshHTTPError(500))
    }

    /// 사용자가 누른 갱신이 실패하면 화면에 사유가 남아야 한다. 로그에만 남으면 버튼이 고장 난 것처럼
    /// 보인다(실사용자 리포트 2026-08-31: "antigravity 갱신을 눌러도 아무 일도 안 일어난다").
    func testAntigravityUserRefreshSurfacesTheFailure() async {
        let claude = FakeUsageProvider(id: "claude_code", displayName: "Claude Code", daily: todayDaily(10_000_000))
        let store = UsageStore(providers: [claude],
                               claudeLimitsProvider: FakeClaudeLimits(status: nil),
                               codexLimitsProvider: FakeCodexLimits(status: nil),
                               opencodeGoLimitsProvider: FakeOpenCodeGoLimits(status: nil),
                               antigravityLimitsProvider: ThrowingAntigravityLimits(error: .httpStatus(403)),
                               autoRefresh: false, defaults: testDefaults)

        await store.refreshAntigravityLimitsFromKeychain()
        XCTAssertEqual(store.antigravityLimitRefreshError,
                       L(.en).limitRefreshForbidden,
                       "사용자 동작 실패가 화면에 남지 않았다")
    }

    /// 자동 폴 실패까지 문구를 띄우면 미구독 사용자에게 오류가 상주한다 — 사용자 동작만 표시한다.
    func testAntigravityAutomaticFailureStaysSilent() async {
        let claude = FakeUsageProvider(id: "claude_code", displayName: "Claude Code", daily: todayDaily(10_000_000))
        let store = UsageStore(providers: [claude],
                               claudeLimitsProvider: FakeClaudeLimits(status: nil),
                               codexLimitsProvider: FakeCodexLimits(status: nil),
                               opencodeGoLimitsProvider: FakeOpenCodeGoLimits(status: nil),
                               antigravityLimitsProvider: ThrowingAntigravityLimits(error: .httpStatus(403)),
                               autoRefresh: false, defaults: testDefaults)

        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertNil(store.antigravityLimitRefreshError, "자동 폴 실패가 화면에 문구를 남겼다")
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
        // 계정 OAuth 없음은 "자격증명 없음"이 아니라 재로그인 안내다 — 두 메시지가 갈려야 한다.
        XCTAssertEqual(UsageStore.friendlyLimitError(LimitsError.credentialMissingAccountOAuth, l),
                       l.limitRefreshReauthNeeded)
        XCTAssertNotEqual(l.limitRefreshReauthNeeded, l.limitRefreshNoCredential)
    }

    /// 자격증명 항목이 MCP 서버 OAuth 상태만 담고 계정 토큰(`claudeAiOauth`)은 없는 경우
    /// (Claude Code 2.1.x 에서 관측) — 형식 오류로 뭉뚱그리면 "재로그인하면 된다"를 안내 못 한다.
    func testAccountOAuthMissingIsDistinguishedFromMalformedCredential() {
        func data(_ json: String) -> Data { Data(json.utf8) }

        XCTAssertTrue(OAuthCredentialData.isAccountOAuthMissing(
            data(#"{"mcpOAuth":{"some-server":{"accessToken":"x"}}}"#)))
        // 깨진 JSON·계정 OAuth 가 있는 경우는 이 분기가 아니다(형식 오류 / 정상).
        XCTAssertFalse(OAuthCredentialData.isAccountOAuthMissing(data("not json at all")))
        XCTAssertFalse(OAuthCredentialData.isAccountOAuthMissing(
            data(#"{"claudeAiOauth":{"accessToken":"t"}}"#)))
        // 명시적 JSON null 은 NSNull 로 디코드돼 `!= nil` 이 참이 된다 — 로그아웃 상태를 "값 있음"으로
        // 오판하면 재로그인 안내 대신 "자격증명 없음"이 뜬다(CLAUDE.md 의 JSON null 금지 규칙).
        XCTAssertTrue(OAuthCredentialData.isAccountOAuthMissing(
            data(#"{"claudeAiOauth":null,"mcpOAuth":{}}"#)))

        // 파싱 자체는 계정 OAuth 가 있을 때만 성공한다.
        XCTAssertNil(OAuthCredentialData.credential(from: data(#"{"mcpOAuth":{}}"#)))
        XCTAssertEqual(
            OAuthCredentialData.credential(from: data(#"{"claudeAiOauth":{"accessToken":"t"}}"#))?.accessToken, "t")
    }

    // MARK: Cursor provider aggregation

    func testCursorProviderFlowsThroughAggregation() async {
        let cursor = FakeUsageProvider(id: "cursor", displayName: "Cursor", daily: todayDaily(8_000))
        cursor.enrichment = ProviderEnrichment(
            activeBlock: nil, blocksOK: true,
            weekTotal: PeriodUsage(period: "w", totalTokens: 50_000, totalCost: 0),
            monthTotal: PeriodUsage(period: "m", totalTokens: 200_000, totalCost: 0),
            periodsOK: true)
        let store = makeStore(providers: [cursor])
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(store.todayTotalTokens, 8_000, "Cursor today tokens should aggregate")
        XCTAssertEqual(store.weekTotalTokens, 50_000, "Cursor week tokens should aggregate")
        XCTAssertEqual(store.monthTotalTokens, 200_000, "Cursor month tokens should aggregate")
        XCTAssertEqual(store.snapshot(preferring: "cursor")?.providerID, "cursor",
                       "Cursor snapshot should be accessible by preferring id")
    }

    func testCursorAndClaudeCombinedAggregation() async {
        let claude = FakeUsageProvider(id: "claude_code", displayName: "Claude Code", daily: todayDaily(100_000))
        let cursor = FakeUsageProvider(id: "cursor", displayName: "Cursor", daily: todayDaily(50_000))
        let store = makeStore(providers: [claude, cursor])
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(store.todayTotalTokens, 150_000, "Claude + Cursor today tokens should sum")
        XCTAssertEqual(store.snapshots.count, 2, "Both providers should have snapshots")
    }

    func testCursorContributesZeroToTodayCostTotal() async {
        let claude = FakeUsageProvider(
            id: "claude_code", displayName: "Claude Code",
            daily: todayDaily(100_000, cost: 1.25))
        let cursor = FakeUsageProvider(
            id: "cursor", displayName: "Cursor",
            daily: todayDaily(50_000, cost: 9.99), reportsCost: false)
        let store = makeStore(providers: [claude, cursor])
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(store.todayTotalTokens, 150_000)
        XCTAssertEqual(store.todayCostTotal, 1.25, accuracy: 0.000_001,
                       "Cursor is tokens-only — invented cost must not enter todayCostTotal")
        XCTAssertEqual(store.snapshot(preferring: "cursor")?.reportsCost, false)
        XCTAssertEqual(store.snapshot(preferring: "claude_code")?.reportsCost, true)
    }

    func testCursorOnlyDoesNotSurfaceZeroDollarCostInMenu() async {
        let cursor = FakeUsageProvider(
            id: "cursor", displayName: "Cursor",
            daily: todayDaily(50_000, cost: 9.99), reportsCost: false)
        let store = makeStore(providers: [cursor])
        store.showTokensInMenu = true
        store.showCostInMenu = true
        store.showLimitInMenu = false
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertTrue(store.costingSnapshots.isEmpty)
        XCTAssertFalse(store.showsCost)
        XCTAssertEqual(store.menuLines, [TokenFormatter.compact(50_000)],
                       "Cursor-only must not render $0.00 / $0.0 in the menu bar")
    }

    // MARK: 디스플레이 슬립 폴링 (회귀)

    /// [회귀] 화면이 꺼져도 폴링은 **멈추지 않고 늦춰질 뿐**이어야 한다.
    ///
    /// iCloud 페이로드는 refresh 완료 훅에서만 나가므로(`onStoreRefreshed` → `CloudKitSync.save`)
    /// 화면 꺼짐에 타이머를 invalidate 하면 Mac 이 깨어서 토큰을 쓰는 중에도 iPhone 앱이 굳는다
    /// (실측 2026-08-29: 화면 꺼짐 32분 동안 refresh 0건 → 폰 stale). 타이머 **생존**이 핵심 단언이다.
    func testDisplaySleepSlowsPollingInsteadOfStoppingIt() {
        let claude = FakeUsageProvider(id: "claude_code", displayName: "Claude Code", daily: todayDaily(1_000))
        let store = makeStore(providers: [claude])
        XCTAssertEqual(store.scheduledPollingInterval, 120, "기본 폴링 주기")

        store.slowPollingForDisplaySleep()

        XCTAssertNotNil(store.scheduledPollingInterval, "화면이 꺼져도 타이머는 살아 있어야 한다 — 폰이 굳는다")
        XCTAssertEqual(store.scheduledPollingInterval, UsageStore.displayAsleepMinimumInterval)
    }

    /// [회귀] 화면이 켜지면 원래 주기로 돌아온다.
    func testDisplayWakeRestoresTheConfiguredInterval() {
        let claude = FakeUsageProvider(id: "claude_code", displayName: "Claude Code", daily: todayDaily(1_000))
        let store = makeStore(providers: [claude])
        store.slowPollingForDisplaySleep()
        XCTAssertEqual(store.scheduledPollingInterval, UsageStore.displayAsleepMinimumInterval)

        store.restoreFullPolling()

        XCTAssertEqual(store.scheduledPollingInterval, 120)

        // 슬립 없이 도착한 wake 는 no-op — 안 그러면 알림마다 refresh 가 한 번씩 더 나간다.
        store.restoreFullPolling()
        XCTAssertEqual(store.scheduledPollingInterval, 120)
    }

    /// 수동 모드(0)는 사용자가 고른 것이라 화면 상태가 뒤집지 않는다 — 꺼져도 켜져도 타이머 없음.
    func testManualModeStaysManualWhileTheDisplaySleeps() {
        let claude = FakeUsageProvider(id: "claude_code", displayName: "Claude Code", daily: todayDaily(1_000))
        let store = makeStore(providers: [claude])
        store.refreshInterval = 0
        XCTAssertNil(store.scheduledPollingInterval)

        store.slowPollingForDisplaySleep()
        XCTAssertNil(store.scheduledPollingInterval, "수동 모드에 폴링을 새로 만들면 안 된다")

        store.restoreFullPolling()
        XCTAssertNil(store.scheduledPollingInterval)
    }

    /// 하한은 max 다 — 사용자가 5분보다 느리게 잡았으면 화면이 꺼졌다고 **빨라지면** 안 된다.
    func testDisplaySleepNeverSpeedsUpASlowerConfiguredInterval() {
        let claude = FakeUsageProvider(id: "claude_code", displayName: "Claude Code", daily: todayDaily(1_000))
        let store = makeStore(providers: [claude])
        store.refreshInterval = 600

        store.slowPollingForDisplaySleep()

        XCTAssertEqual(store.scheduledPollingInterval, 600, "하한이지 고정값이 아니다")
    }

    /// 정책 경계를 순수 함수로 고정 — 그리고 이 상수의 **존재 이유**(폰 stale 기준보다 짧게)를 기계로 건다.
    /// `DashboardView.isStale` 이 30분이므로, 이 값을 그 위로 올리면 화면 꺼진 Mac 이 폰을 stale 로 만든다.
    func testSlowPollWhileAsleepStaysAheadOfThePhoneStaleThreshold() {
        let phoneStaleThreshold: TimeInterval = 30 * 60   // PokeTokenBariOS/Sources/DashboardView.swift
        XCTAssertLessThan(UsageStore.displayAsleepMinimumInterval, phoneStaleThreshold,
                          "화면 꺼진 동안의 폴링이 폰 stale 기준보다 느리면 폰이 stale 로 굳는다")

        XCTAssertEqual(UsageStore.effectiveRefreshInterval(base: 120, displayAsleep: false), 120)
        XCTAssertEqual(UsageStore.effectiveRefreshInterval(base: 120, displayAsleep: true), 300)
        XCTAssertEqual(UsageStore.effectiveRefreshInterval(base: 0, displayAsleep: true), 0)
        XCTAssertEqual(UsageStore.effectiveRefreshInterval(base: 600, displayAsleep: true), 600)
    }

    /// 배선 가드 — 정책 함수가 옳아도 알림에 안 걸려 있으면 아무 일도 안 일어난다.
    /// 위 테스트들이 정책 지점을 직접 부르므로, 실제 `NSWorkspace` 알림이 거기 닿는지는 여기서만 확인된다.
    func testScreensDidSleepNotificationReachesTheStore() async {
        let claude = FakeUsageProvider(id: "claude_code", displayName: "Claude Code", daily: todayDaily(1_000))
        let store = makeStore(providers: [claude])

        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.screensDidSleepNotification, object: nil)
        await waitForPollingInterval(UsageStore.displayAsleepMinimumInterval, on: store)
        XCTAssertEqual(store.scheduledPollingInterval, UsageStore.displayAsleepMinimumInterval,
                       "screensDidSleep 가 폴링 정책에 안 닿는다")

        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.screensDidWakeNotification, object: nil)
        await waitForPollingInterval(120, on: store)
        XCTAssertEqual(store.scheduledPollingInterval, 120, "screensDidWake 가 원래 주기를 복구하지 않는다")
    }

    /// NSWorkspace 알림은 `OperationQueue.main` 배달 + `Task` 홉을 거친다 — 도착까지 유한 대기(최대 ~1s).
    /// 도달하면 즉시 반환하므로 통과 경로에 고정 지연이 없고, 실패는 뒤따르는 단언이 잡는다.
    private func waitForPollingInterval(_ expected: TimeInterval, on store: UsageStore) async {
        for _ in 0..<200 {
            if store.scheduledPollingInterval == expected { return }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }
}
