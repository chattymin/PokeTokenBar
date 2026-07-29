import XCTest
@testable import PokeTokenBar

/// 오늘 사용량만 돌려주는 최소 스텁 — grok 단독 사용자 시나리오(프로바이더 무관 집계) 검증용.
private struct GrokOnlyProvider: UsageProvider {
    let id = "grok"
    let displayName = "Grok"
    let daily: DailyUsage?
    let block: BlockUsage?

    func fetchDaily() async throws -> DailyUsage? { daily }
    func fetchEnrichment() async -> ProviderEnrichment {
        var r = ProviderEnrichment()
        r.activeBlock = block
        r.blocksOK = true
        r.weekTotal = PeriodUsage(period: "W", totalTokens: 9_000, totalCost: 0)
        r.monthTotal = PeriodUsage(period: "M", totalTokens: 30_000, totalCost: 0)
        r.periodsOK = true
        return r
    }
}

private struct NoLimitsForGrok: ClaudeLimitsProviding {
    func fetch(allowKeychainPrompt: Bool) async throws -> LimitStatus { throw LimitsError.keychainInteractionNotAllowed }
}
private struct NoCodexLimitsForGrok: CodexLimitsProviding {
    func fetch() async throws -> CodexRateLimitStatus? { nil }
}
private struct NoStatusForGrok: ProviderStatusProviding {
    func fetch() async -> [String: ProviderStatus] { [:] }
}

/// 공식 xAI Grok CLI 세션 파싱 — `~/.grok/sessions/<id>/updates.jsonl` 의 `turn_completed.usage`.
/// 스키마 근거는 grok-build 소스(`extensions/notification.rs` 의 SessionUpdate/PromptUsage serde 계약).
final class GrokUsageTests: XCTestCase {
    private var base: URL!
    private var root: URL!          // = <base>/sessions
    private var cacheFile: URL!

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory
            .appendingPathComponent("ptb-grok-\(UUID().uuidString)")
        root = base.appendingPathComponent("sessions")
        cacheFile = base.appendingPathComponent("usage-cache.json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: base)
    }

    // MARK: 픽스처

    /// 스트리밍 청크 라인(토큰 없음) — 실제 updates.jsonl 대부분이 이 형태다.
    private let chunkLine = """
    {"timestamp":"2026-07-29T01:00:00.000Z","update":{"sessionId":"s1","update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"hi"}},"_meta":{"totalTokens":100,"eventId":"e0","agentTimestampMs":1785000000000,"chunkId":0}}}
    """

    /// 턴 종료 라인 — ACP durable wire(camelCase): inputTokens 는 캐시 읽기를 **포함**한다.
    private func turnLine(
        promptID: String,
        input: Int = 41_203,
        output: Int = 812,
        cachedRead: Int = 38_400,
        total: Int = 42_015,
        costTicks: Int? = 12_000_000_000,
        costIsPartial: Bool = false,
        usageIsIncomplete: Bool = false,
        model: String? = "grok-build-1",
        timestamp: String? = "2026-07-29T01:00:10.000Z",
        isReplay: Bool = false
    ) -> String {
        var usage: [String] = [
            "\"inputTokens\":\(input)", "\"outputTokens\":\(output)", "\"totalTokens\":\(total)",
            "\"cachedReadTokens\":\(cachedRead)", "\"reasoningTokens\":260", "\"modelCalls\":3",
            "\"numTurns\":1",
        ]
        if let costTicks { usage.append("\"costUsdTicks\":\(costTicks)") }
        if costIsPartial { usage.append("\"costIsPartial\":true") }
        if usageIsIncomplete { usage.append("\"usageIsIncomplete\":true") }
        if let model {
            usage.append("""
            "modelUsage":{"\(model)":{"inputTokens":\(input),"outputTokens":\(output),"totalTokens":\(total),"cachedReadTokens":\(cachedRead)}}
            """)
        }
        var meta = ["\"totalTokens\":\(total)", "\"eventId\":\"ev-\(promptID)\"",
                    "\"agentTimestampMs\":1785000010000", "\"promptId\":\"\(promptID)\""]
        if isReplay { meta.append("\"isReplay\":true") }
        let ts = timestamp.map { "\"timestamp\":\"\($0)\"," } ?? ""
        return """
        {\(ts)"update":{"sessionId":"s1","update":{"sessionUpdate":"turn_completed","prompt_id":"\(promptID)","stop_reason":"end_turn","usage":{\(usage.joined(separator: ","))}},"_meta":{\(meta.joined(separator: ","))}}}
        """
    }

    @discardableResult
    private func writeSession(_ id: String, lines: [String], sessionKind: String? = nil) throws -> URL {
        let dir = root.appendingPathComponent(id)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let updates = dir.appendingPathComponent("updates.jsonl")
        try lines.joined(separator: "\n").write(to: updates, atomically: true, encoding: .utf8)
        var summary = "{\"session_summary\":\"x\""
        if let sessionKind { summary += ",\"session_kind\":\"\(sessionKind)\"" }
        summary += "}"
        try summary.write(to: dir.appendingPathComponent("summary.json"), atomically: true, encoding: .utf8)
        return updates
    }

    private func parse(_ url: URL) -> [LocalUsageReader.Entry] {
        LocalUsageReader.parseGrokFile(url, fmt: LocalUsageReader.localDayFormatter())
    }

    // MARK: 토큰 매핑

    /// camelCase(durable ACP wire) — inputTokens 는 캐시 포함이므로 캐시분을 빼야 하고,
    /// Entry.total 은 usage.totalTokens 와 정확히 일치해야 한다.
    func testTurnCompletedTokenMappingPreservesTotalIdentity() throws {
        let url = try writeSession("s1", lines: [chunkLine, turnLine(promptID: "p-1")])
        let entries = parse(url)
        XCTAssertEqual(entries.count, 1, "청크 라인은 토큰이 없어 집계 대상이 아니다")
        let e = try XCTUnwrap(entries.first)
        XCTAssertEqual(e.input, 2_803, "input = inputTokens(41203) − cachedReadTokens(38400)")
        XCTAssertEqual(e.cacheRead, 38_400)
        XCTAssertEqual(e.output, 812, "reasoning 은 output 에 포함 — 따로 더하지 않는다")
        XCTAssertEqual(e.cacheWrite, 0, "Grok 은 캐시 쓰기를 prompt 토큰에 접어 넣는다")
        XCTAssertEqual(e.total, 42_015, "Entry.total == usage.totalTokens")
        XCTAssertEqual(e.model, "grok-build-1")
        XCTAssertEqual(try XCTUnwrap(e.explicitCost), 1.2, accuracy: 1e-9, "12e9 ticks = $1.2")
    }

    /// [트리거 브랜치] 헤드리스 투영(snake_case)의 `input_tokens` 는 **이미 캐시 제외**다.
    /// camelCase 와 같은 값으로 취급하면 캐시분을 두 번 빼 input 이 60 → 20 으로 어긋난다.
    func testHeadlessSnakeCaseInputIsNotCacheAdjustedAgain() throws {
        let line = """
        {"timestamp":"2026-07-29T02:00:00.000Z","update":{"sessionId":"s2","update":{"sessionUpdate":"turn_completed","prompt_id":"p-snake","stop_reason":"end_turn","usage":{"input_tokens":60,"output_tokens":10,"total_tokens":110,"cached_read_tokens":40}},"_meta":{"eventId":"ev-snake","agentTimestampMs":1785000020000}}}
        """
        let url = try writeSession("s2", lines: [line])
        let e = try XCTUnwrap(parse(url).first)
        XCTAssertEqual(e.input, 60, "snake_case input_tokens 는 캐시 제외값 — 다시 빼면 안 된다")
        XCTAssertEqual(e.cacheRead, 40)
        XCTAssertEqual(e.output, 10)
        XCTAssertEqual(e.total, 110)
    }

    /// 여러 턴 합산 + 청크 라인 다수 무시.
    func testMultipleTurnsAggregate() throws {
        let url = try writeSession("s3", lines: [
            chunkLine, turnLine(promptID: "p-1"), chunkLine,
            turnLine(promptID: "p-2", input: 100, output: 20, cachedRead: 0, total: 120, costTicks: nil),
        ])
        let entries = parse(url)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.map(\.total).reduce(0, +), 42_015 + 120)
        let day = try XCTUnwrap(entries.first?.localDay)
        let daily = try XCTUnwrap(LocalUsageReader.daily(entries: entries, localDay: day))
        XCTAssertEqual(daily.totalTokens, 42_015 + 120)
        XCTAssertEqual(daily.totalCost, 1.2, accuracy: 1e-9, "비용은 서버가 준 ticks 만 — 두 번째 턴은 0")
    }

    // MARK: 이중 집계 방어

    /// 재생(replay)으로 다시 append 된 턴 라인은 같은 턴을 두 번 세게 만든다.
    func testReplayLineIsNotCountedTwice() throws {
        let url = try writeSession("s4", lines: [
            turnLine(promptID: "p-1"),
            turnLine(promptID: "p-1", isReplay: true),
        ])
        let entries = parse(url)
        XCTAssertEqual(entries.count, 1, "isReplay 라인은 건너뛴다")
        XCTAssertEqual(entries.first?.total, 42_015)
    }

    /// [트리거 브랜치] fork 세션이 부모 updates 를 복사하면 같은 턴이 두 파일에 존재한다.
    /// 턴 id 에 세션 경로를 섞지 않아야 전역 dedup 으로 한 번만 잡힌다.
    func testForkedSessionCopyDoesNotDoubleCount() throws {
        try writeSession("parent", lines: [turnLine(promptID: "p-1")])
        try writeSession("child-fork", lines: [turnLine(promptID: "p-1")], sessionKind: "fork")
        let entries = LocalUsageReader.grokEntries(modifiedSince: Date(timeIntervalSince1970: 0), root: root)
        XCTAssertEqual(entries.count, 1, "같은 prompt_id 는 파일이 달라도 한 턴이다")
        XCTAssertEqual(entries.first?.total, 42_015)
    }

    /// [트리거 브랜치] 서브에이전트 토큰은 부모 턴 usage 에 이미 접혀 들어온다(RecordSubagentUsage) →
    /// 서브에이전트 세션을 또 집계하면 이중 계산. worktree/fork 등 사용자 세션은 유지해야 한다.
    func testSubagentSessionsAreSkippedButUserSessionsKept() throws {
        try writeSession("main", lines: [turnLine(promptID: "p-main")])
        try writeSession("sub", lines: [turnLine(promptID: "p-sub")], sessionKind: "subagent")
        try writeSession("sub2", lines: [turnLine(promptID: "p-sub2")], sessionKind: "subagent_fork")
        try writeSession("wt", lines: [turnLine(promptID: "p-wt")], sessionKind: "worktree")

        let entries = LocalUsageReader.grokEntries(modifiedSince: Date(timeIntervalSince1970: 0), root: root)
        XCTAssertEqual(Set(entries.map(\.id)), Set(["grok|p-main", "grok|p-wt"]))
    }

    // MARK: 비용 신뢰 조건

    /// 부분합·불완전 집계면 서버 비용을 버린다. Grok 단가표가 없으므로 결과 비용은 0(추정 금지).
    func testUntrustworthyCostsAreDropped() throws {
        let partial = try writeSession("cost-partial", lines: [
            turnLine(promptID: "p-partial", costIsPartial: true)])
        XCTAssertNil(parse(partial).first?.explicitCost, "costIsPartial → 신뢰 불가")

        let incomplete = try writeSession("cost-incomplete", lines: [
            turnLine(promptID: "p-incomplete", usageIsIncomplete: true)])
        XCTAssertNil(parse(incomplete).first?.explicitCost, "usageIsIncomplete → 신뢰 불가")

        let entries = parse(partial)
        let day = try XCTUnwrap(entries.first?.localDay)
        let daily = try XCTUnwrap(LocalUsageReader.daily(entries: entries, localDay: day))
        XCTAssertEqual(daily.totalCost, 0, "단가표에 없는 모델 → 0 (금액 오표시 방지)")
        XCTAssertEqual(ModelPricing.rate(for: "grok-build-1"), .zero)
        XCTAssertEqual(ModelPricing.rate(for: "grok-4-fast"), .zero)
    }

    // MARK: 경계·폴백

    /// 0 토큰 턴(취소 등)은 엔트리를 만들지 않는다 — `usage` 존재만으로 판정하지 않는다.
    func testZeroUsageTurnProducesNoEntry() throws {
        let url = try writeSession("zero", lines: [
            turnLine(promptID: "p-zero", input: 0, output: 0, cachedRead: 0, total: 0, costTicks: nil)])
        XCTAssertTrue(parse(url).isEmpty)
    }

    /// 봉투 timestamp 가 없으면 `_meta.agentTimestampMs` 로 폴백한다.
    func testTimestampFallsBackToMetaAgentTimestamp() throws {
        let url = try writeSession("ts", lines: [turnLine(promptID: "p-ts", timestamp: nil)])
        let e = try XCTUnwrap(parse(url).first)
        XCTAssertEqual(e.date.timeIntervalSince1970, 1_785_000_010, accuracy: 0.001)
    }

    /// modelUsage 가 없으면 totals 만으로 집계하고 모델명은 폴백.
    func testMissingModelUsageFallsBackToGenericModel() throws {
        let url = try writeSession("nomodel", lines: [turnLine(promptID: "p-nm", model: nil)])
        let e = try XCTUnwrap(parse(url).first)
        XCTAssertEqual(e.model, "grok")
        XCTAssertEqual(e.total, 42_015)
    }

    /// turn_completed 가 없는 파일(청크만)은 조용히 0건 — JSON 파싱 전에 문자열로 걸러진다.
    func testFileWithoutTurnCompletedYieldsNothing() throws {
        let url = try writeSession("chunks", lines: [chunkLine, chunkLine, chunkLine])
        XCTAssertTrue(parse(url).isEmpty)
    }

    /// 스케일 가드: 실제 updates.jsonl 은 스트리밍 청크가 대부분이라 세션당 수만 라인이 된다.
    /// 문자열 prefilter 없이 라인마다 JSON 을 파싱하면 새로고침마다 이 비용을 문다.
    func testLargeUpdatesFileStaysCheapAndAccurate() throws {
        var lines: [String] = []
        for turn in 0..<50 {
            lines.append(contentsOf: Array(repeating: chunkLine, count: 400))
            lines.append(turnLine(promptID: "p-\(turn)", input: 1_000, output: 100,
                                  cachedRead: 400, total: 1_100, costTicks: nil))
        }
        let url = try writeSession("big", lines: lines)
        let started = Date()
        let entries = parse(url)
        let elapsed = Date().timeIntervalSince(started)
        XCTAssertEqual(entries.count, 50)
        XCTAssertEqual(entries.map(\.total).reduce(0, +), 50 * 1_100)
        XCTAssertLessThan(elapsed, 5, "20k 라인 파싱이 \(elapsed)s — prefilter 가 빠졌는지 확인")
    }

    // MARK: 캐시 경로

    /// 캐시는 updates.jsonl 만 읽는다(chat_history/events 는 토큰이 없어 blob 만 부풀린다) + 스냅샷 라운드트립.
    func testCacheReadsOnlyUpdatesFileAndPersists() async throws {
        let dir = root.appendingPathComponent("s-cache")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try [chunkLine, turnLine(promptID: "p-1")].joined(separator: "\n")
            .write(to: dir.appendingPathComponent("updates.jsonl"), atomically: true, encoding: .utf8)
        // 같은 디렉토리의 다른 .jsonl — 파싱 대상이 아니어야 한다.
        try turnLine(promptID: "p-should-not-count")
            .write(to: dir.appendingPathComponent("chat_history.jsonl"), atomically: true, encoding: .utf8)
        try turnLine(promptID: "p-events")
            .write(to: dir.appendingPathComponent("events.jsonl"), atomically: true, encoding: .utf8)
        try "{\"session_summary\":\"x\"}".write(
            to: dir.appendingPathComponent("summary.json"), atomically: true, encoding: .utf8)

        let entries = await LocalUsageCache(grokRoot: root, fileURL: cacheFile)
            .grokEntries(modifiedSince: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(entries.map(\.id), ["grok|p-1"])

        // 두 번째 인스턴스는 디스크 스냅샷을 재사용해도 같은 결과여야 한다.
        let again = await LocalUsageCache(grokRoot: root, fileURL: cacheFile)
            .grokEntries(modifiedSince: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(again.map(\.id), ["grok|p-1"])
    }

    // MARK: 등록·집계 패리티

    /// Grok 만 쓰는 사용자도 오늘/주/월·번레이트·메뉴 표시가 모두 동작해야 한다
    /// (과거 회귀: 특정 프로바이더에만 계산을 붙여 다른 프로바이더 전용 사용자가 idle 로 남았다).
    @MainActor
    func testGrokOnlyUserGetsAllAggregates() async throws {
        let suite = "GrokUsageTests.parity.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let today = LocalUsageReader.todayKey()
        // burnTier 임계는 1,000 tokens/min 초과 — 그 위 값으로 "관측됐다"를 검증한다.
        let block = BlockUsage(id: "b", startTime: "", endTime: "", isActive: true,
                               totalTokens: 50_000, costUSD: 0, tokensPerMinute: 5_000)
        let store = UsageStore(
            providers: [GrokOnlyProvider(
                daily: DailyUsage(date: today, inputTokens: 1_000, outputTokens: 200,
                                  cacheCreationTokens: 0, cacheReadTokens: 800,
                                  totalTokens: 2_000, totalCost: 0.5),
                block: block)],
            claudeLimitsProvider: NoLimitsForGrok(),
            codexLimitsProvider: NoCodexLimitsForGrok(),
            statusProvider: NoStatusForGrok(),
            autoRefresh: false,
            defaults: defaults)

        await store.refresh(scheduleEmptyRetry: false)

        XCTAssertEqual(store.todayTotalTokens, 2_000)
        XCTAssertEqual(store.weekTotalTokens, 9_000)
        XCTAssertEqual(store.monthTotalTokens, 30_000)
        XCTAssertEqual(store.snapshots.map(\.providerID), ["grok"])
        XCTAssertEqual(store.burnTier, .normal, "번레이트가 Grok 블록을 관측해야 한다(idle 이면 미관측)")
        XCTAssertFalse(store.menuTitle.isEmpty)
        XCTAssertNil(store.lastErrorDescription)
    }

    /// 기본 레지스트리에 Grok 이 등록돼 있어야 팝오버 탭/집계에 나타난다.
    @MainActor
    func testDefaultRegistryIncludesGrok() {
        let suite = "GrokUsageTests.registry.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UsageStore(autoRefresh: false, defaults: defaults)
        XCTAssertTrue(store.registeredProviderIDs.contains("grok"))
    }

    /// `$GROK_HOME` 이 설정돼 있으면 그 아래 sessions 를 본다(CLI 와 같은 규칙).
    func testSessionsDirHonoursGrokHomeEnvironment() throws {
        let expected: URL
        if let home = ProcessInfo.processInfo.environment["GROK_HOME"]?
            .trimmingCharacters(in: .whitespacesAndNewlines), !home.isEmpty {
            expected = URL(fileURLWithPath: home).appendingPathComponent("sessions")
        } else {
            expected = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".grok/sessions")
        }
        XCTAssertEqual(LocalUsageReader.grokSessionsDir.standardizedFileURL, expected.standardizedFileURL)
        XCTAssertEqual(LocalUsageReader.grokSessionsDir.lastPathComponent, "sessions")
    }
}
