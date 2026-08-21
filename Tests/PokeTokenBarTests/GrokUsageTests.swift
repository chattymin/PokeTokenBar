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
private struct NoOpenCodeGoLimitsForGrok: OpenCodeGoLimitsProviding {
    func fetch() async throws -> OpenCodeGoLimitStatus? { nil }
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
    /// 봉투는 실제 디스크 형식 그대로: `{timestamp:<초>, method, params:{sessionId, update, _meta}}`.
    /// (`_meta.totalTokens` 는 컨텍스트 창 크기 — 사용량으로 세면 안 된다.)
    private let chunkLine = """
    {"timestamp":1785000000,"method":"_x.ai/session/update","params":{"sessionId":"s1","update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"hi"}},"_meta":{"totalTokens":100,"eventId":"e0","agentTimestampMs":1785000000000,"chunkId":0}}}
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
        envelopeSeconds: Int? = 1_785_000_010,
        agentTimestampMs: Int? = 1_785_000_010_000,
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
                    "\"promptId\":\"\(promptID)\""]
        if let agentTimestampMs { meta.append("\"agentTimestampMs\":\(agentTimestampMs)") }
        if isReplay { meta.append("\"isReplay\":true") }
        let ts = envelopeSeconds.map { "\"timestamp\":\($0)," } ?? ""
        return """
        {\(ts)"method":"_x.ai/session/update","params":{"sessionId":"s1","update":{"sessionUpdate":"turn_completed","prompt_id":"\(promptID)","stop_reason":"end_turn","usage":{\(usage.joined(separator: ","))}},"_meta":{\(meta.joined(separator: ","))}}}
        """
    }

    /// 세션 디렉토리 하나를 만든다. 실제 레이아웃은 `sessions/<encoded-cwd>/<session-id>/` 라
    /// 한 단계 더 깊다 — 스캔이 재귀인지까지 함께 확인하려고 같은 깊이로 쓴다.
    @discardableResult
    private func writeSession(_ id: String, lines: [String], sessionKind: String? = nil,
                              summary: Bool = true, mtime: Date? = nil) throws -> URL {
        let dir = root.appendingPathComponent("cwd-group/\(id)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let updates = dir.appendingPathComponent("updates.jsonl")
        try lines.joined(separator: "\n").write(to: updates, atomically: true, encoding: .utf8)
        if summary { try writeSummary(id, sessionKind: sessionKind) }
        if let mtime {
            try FileManager.default.setAttributes([.modificationDate: mtime], ofItemAtPath: updates.path)
        }
        return updates
    }

    private func writeSummary(_ id: String, sessionKind: String? = nil) throws {
        var summary = "{\"session_summary\":\"x\""
        if let sessionKind { summary += ",\"session_kind\":\"\(sessionKind)\"" }
        summary += "}"
        try summary.write(to: root.appendingPathComponent("cwd-group/\(id)/summary.json"),
                          atomically: true, encoding: .utf8)
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
    /// (디스크의 durable 라인은 camelCase 다. 이 형태는 헤드리스 결과 JSON 을 옮겨 적는 도구를
    /// 대비한 방어 경로이므로, 의미가 반대인 두 스펠링이 섞여도 각각 맞게 읽히는지 고정한다.)
    func testHeadlessSnakeCaseInputIsNotCacheAdjustedAgain() throws {
        let line = """
        {"timestamp":1785000020,"method":"_x.ai/session/update","params":{"sessionId":"s2","update":{"sessionUpdate":"turn_completed","prompt_id":"p-snake","stop_reason":"end_turn","usage":{"input_tokens":60,"output_tokens":10,"total_tokens":110,"cached_read_tokens":40}},"_meta":{"eventId":"ev-snake","agentTimestampMs":1785000020000}}}
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
    /// 두 방어가 겹쳐 있어 각각을 따로 밟는다 — 같은 id 중복은 dedup 이, 그렇지 않은 재생 라인은
    /// isReplay 판정이 막는다. (같은 id 로만 테스트하면 dedup 이 통과시켜 isReplay 분기가 미검증으로 남는다.)
    func testReplayLinesAreNotCountedTwice() throws {
        let deduped = try writeSession("s4", lines: [
            turnLine(promptID: "p-1"),
            turnLine(promptID: "p-1", isReplay: true),
        ])
        let byID = parse(deduped)
        XCTAssertEqual(byID.count, 1, "같은 턴 id 는 한 번만")
        XCTAssertEqual(byID.first?.total, 42_015)

        // isReplay 분기 단독: id 가 달라 dedup 이 못 막는 재생 라인.
        let replayOnly = try writeSession("s4-replay", lines: [
            turnLine(promptID: "p-live"),
            turnLine(promptID: "p-replayed", isReplay: true),
        ])
        XCTAssertEqual(parse(replayOnly).map(\.id), ["grok|p-live"],
                       "isReplay 라인은 id 가 달라도 집계 대상이 아니다")
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
    }

    /// [트리거 브랜치] Grok 이름은 패밀리 폴백에 걸리기 전에 0 으로 끊어야 한다 — `grok-codex-*`·
    /// `grok-4o-*` 는 `codex`/`o4` 부분문자열에 걸려 GPT 단가($5/$30)로 가짜 금액을 만들 수 있다.
    func testGrokNamesNeverInheritOtherFamilyPricing() {
        for name in ["grok-build-1", "grok-4-fast", "grok-code-fast-1", "grok-codex-next", "grok-4o-mini"] {
            XCTAssertEqual(ModelPricing.rate(for: name), .zero, "\(name) 단가는 0이어야 한다")
        }
        XCTAssertEqual(ModelPricing.cost(model: "grok-codex-next", input: 1_000_000, output: 1_000_000,
                                         cacheWrite: 0, cacheRead: 0), 0)
        // 다른 프로바이더의 폴백은 그대로 살아 있어야 한다(과잉 차단 방지).
        XCTAssertEqual(ModelPricing.rate(for: "gpt-5.6-codex"), .perMillion(5, 30, 0, 0.5))
    }

    /// 프로바이더가 쓰는 것과 같은 집계 경로(블록·주·월)를 실제 파일로 검증한다.
    /// (`LocalGrokProvider` 는 이 세 helper 를 그대로 호출한다 — 산술이 여기서 고정된다.)
    func testBlockWeekMonthAggregatesFromRealFiles() throws {
        let now = Date()
        // 10분 전 = 5h 블록 안. 단 로컬 자정 직후 10분 안에 돌면 그 시각이 **어제**가 되어, 마지막
        // `todayKey()` 일별 단언이 nil 로 깨진다(프로덕션은 정상 — 엔트리를 제 날짜에 넣을 뿐이다).
        // 실측: TZ=UTC 로 00:00~00:10 사이에 실행하면 재현. 오늘 안으로 클램프해 벽시계 의존을 없앤다.
        let tenMinutesAgo = now.addingTimeInterval(-600)
        let recent = Int(max(tenMinutesAgo, Calendar.current.startOfDay(for: now).addingTimeInterval(1))
                            .timeIntervalSince1970)
        try writeSession("agg", lines: [
            turnLine(promptID: "p-block", input: 1_000, output: 100, cachedRead: 0, total: 1_100,
                     costTicks: nil, envelopeSeconds: recent, agentTimestampMs: recent * 1_000)])
        let entries = LocalUsageReader.grokEntries(modifiedSince: epoch, root: root)
        XCTAssertEqual(entries.count, 1)

        let block = try XCTUnwrap(LocalUsageReader.activeBlock(entries: entries, now: now))
        XCTAssertEqual(block.totalTokens, 1_100)
        XCTAssertTrue(block.isActive)
        let fmt = LocalUsageReader.localDayFormatter()
        let weekStart = LocalUsageReader.startOfWeek(now)
        let week = LocalUsageReader.period(entries: entries, periodKey: "W",
                                          fromDay: fmt.string(from: weekStart), toDay: fmt.string(from: now))
        XCTAssertEqual(week.totalTokens, 1_100)
        let month = LocalUsageReader.period(entries: entries, periodKey: LocalUsageReader.monthKey(now),
                                            fromDay: fmt.string(from: LocalUsageReader.startOfMonth(now)),
                                            toDay: fmt.string(from: now))
        XCTAssertEqual(month.totalTokens, 1_100)
        XCTAssertEqual(LocalUsageReader.daily(entries: entries,
                                              localDay: LocalUsageReader.todayKey())?.totalTokens, 1_100)
    }

    // MARK: 경계·폴백

    /// 0 토큰 턴(취소 등)은 엔트리를 만들지 않는다 — `usage` 존재만으로 판정하지 않는다.
    func testZeroUsageTurnProducesNoEntry() throws {
        let url = try writeSession("zero", lines: [
            turnLine(promptID: "p-zero", input: 0, output: 0, cachedRead: 0, total: 0, costTicks: nil)])
        XCTAssertTrue(parse(url).isEmpty)
    }

    /// [트리거 브랜치] 봉투 `timestamp` 는 *기록* 시각이고 fork 복사 때 새로 찍힌다 →
    /// 그걸 우선하면 포크된 세션의 과거 사용량이 전부 포크 시점으로 재날짜화된다.
    /// `_meta.agentTimestampMs`(턴 시각, 복사 시 보존)가 이겨야 한다.
    func testAgentTimestampWinsOverEnvelopeWriteTime() throws {
        let forkWriteTime = 1_785_600_000              // 원래 턴보다 약 6.9일 뒤
        let url = try writeSession("forked", lines: [
            turnLine(promptID: "p-old", envelopeSeconds: forkWriteTime,
                     agentTimestampMs: 1_785_000_010_000)])
        let e = try XCTUnwrap(parse(url).first)
        XCTAssertEqual(e.date.timeIntervalSince1970, 1_785_000_010, accuracy: 0.001,
                       "포크 기록 시각(\(forkWriteTime))이 아니라 턴 시각을 써야 한다")
    }

    /// `_meta.agentTimestampMs` 가 없으면 봉투 `timestamp`(Unix 초)로 폴백한다.
    /// 봉투는 ISO 문자열이 아니라 숫자다 — 문자열로만 읽으면 모든 턴이 조용히 사라진다.
    func testEnvelopeSecondsUsedWhenAgentTimestampMissing() throws {
        let url = try writeSession("ts", lines: [
            turnLine(promptID: "p-ts", envelopeSeconds: 1_785_000_010, agentTimestampMs: nil)])
        let e = try XCTUnwrap(parse(url).first)
        XCTAssertEqual(e.date.timeIntervalSince1970, 1_785_000_010, accuracy: 0.001)
    }

    /// [트리거 브랜치] JSON `null` 은 "값 있음"이 아니다. camelCase 키가 null 이면 snake_case 값을
    /// 써야 하고, null 을 0 으로 읽어 캐시분을 빼면 입력 토큰이 통째로 사라진다.
    func testNullTokenFieldsDoNotZeroTheTurn() throws {
        let line = """
        {"timestamp":1785000030,"method":"_x.ai/session/update","params":{"sessionId":"s5","update":{"sessionUpdate":"turn_completed","prompt_id":"p-null","stop_reason":"end_turn","usage":{"inputTokens":null,"input_tokens":60,"outputTokens":null,"output_tokens":10,"cachedReadTokens":40,"totalTokens":110}},"_meta":{"eventId":"ev-null","agentTimestampMs":1785000030000}}}
        """
        let url = try writeSession("nulls", lines: [line])
        let e = try XCTUnwrap(parse(url).first)
        XCTAssertEqual(e.input, 60, "inputTokens 가 null 이면 snake_case 값을 쓴다")
        XCTAssertEqual(e.output, 10)
        XCTAssertEqual(e.cacheRead, 40)
        XCTAssertEqual(e.total, 110)
    }

    /// [트리거 브랜치] 캐시 읽기는 프롬프트의 부분집합이라 전체보다 클 수 없다. 어긋난 페이로드에서
    /// `max(0, full − cache)` 로 뭉개면 input+cacheRead 가 프롬프트를 넘어 total 이 조용히 부푼다.
    func testCacheReadIsClampedToPromptTotal() throws {
        let url = try writeSession("clamp", lines: [
            turnLine(promptID: "p-clamp", input: 1_000, output: 50, cachedRead: 1_200,
                     total: 1_050, costTicks: nil)])
        let e = try XCTUnwrap(parse(url).first)
        XCTAssertEqual(e.input, 0)
        XCTAssertEqual(e.cacheRead, 1_000, "캐시 읽기는 프롬프트 전체(1000)로 clamp")
        XCTAssertEqual(e.total, 1_050, "소스가 말한 totalTokens 와 일치해야 한다")
    }

    /// 부분 필드 합이 소스의 `totalTokens` 보다 작으면 남는 분은 output 에 귀속시켜 합계를 소스에 맞춘다.
    func testResidualAgainstReportedTotalGoesToOutput() throws {
        let url = try writeSession("residual", lines: [
            turnLine(promptID: "p-res", input: 500, output: 10, cachedRead: 100,
                     total: 700, costTicks: nil)])
        let e = try XCTUnwrap(parse(url).first)
        XCTAssertEqual(e.total, 700)
        XCTAssertEqual(e.input, 400)
        XCTAssertEqual(e.cacheRead, 100)
        XCTAssertEqual(e.output, 200, "10 + (700 − 510) 잔여분")
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

    /// 스케일 정확성: 실제 updates.jsonl 은 스트리밍 청크가 대부분(세션당 수만 라인)이고 그 안엔
    /// `_meta.totalTokens` 같은 *컨텍스트 창* 숫자가 라인마다 들어 있다. 2만 라인 중 턴 종료 50건만
    /// 정확히 집계돼야 한다(청크의 토큰 필드가 새면 합계가 수십 배로 부푼다).
    /// (벽시계 상한은 두지 않는다 — 실측상 prefilter 유무의 차이가 작아 상한이 통과의례가 된다.)
    func testLargeUpdatesFileAggregatesOnlyTurnEndings() throws {
        var lines: [String] = []
        for turn in 0..<50 {
            lines.append(contentsOf: Array(repeating: chunkLine, count: 400))
            lines.append(turnLine(promptID: "p-\(turn)", input: 1_000, output: 100,
                                  cachedRead: 400, total: 1_100, costTicks: nil))
        }
        let url = try writeSession("big", lines: lines)
        let entries = parse(url)
        XCTAssertEqual(entries.count, 50)
        XCTAssertEqual(entries.map(\.total).reduce(0, +), 50 * 1_100)
    }

    // MARK: 캐시 경로

    private var epoch: Date { Date(timeIntervalSince1970: 0) }

    /// 캐시는 updates.jsonl 만 읽는다 — 같은 디렉토리의 chat_history/events 는 토큰이 없고,
    /// 파싱하면 없는 사용량이 잡히거나 빈 blob 이 스냅샷을 부풀린다.
    func testCacheReadsOnlyTheUpdatesFile() async throws {
        let dir = root.appendingPathComponent("cwd-group/s-cache")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try [chunkLine, turnLine(promptID: "p-1")].joined(separator: "\n")
            .write(to: dir.appendingPathComponent("updates.jsonl"), atomically: true, encoding: .utf8)
        try turnLine(promptID: "p-should-not-count")
            .write(to: dir.appendingPathComponent("chat_history.jsonl"), atomically: true, encoding: .utf8)
        try turnLine(promptID: "p-events")
            .write(to: dir.appendingPathComponent("events.jsonl"), atomically: true, encoding: .utf8)
        try writeSummary("s-cache")

        let entries = await LocalUsageCache(grokRoot: root, fileURL: cacheFile).grokEntries(modifiedSince: epoch)
        XCTAssertEqual(entries.map(\.id), ["grok|p-1"])
    }

    /// blob 재사용을 실제로 증명한다: mtime·size 를 유지한 채 내용만 바꿔치기하면 캐시 히트가
    /// **옛 값**을 돌려줘야 한다(같은 결과가 나오는지만 보면 재파싱과 구분되지 않는다).
    func testCacheHitReusesBlobForUnchangedFileStamp() async throws {
        let stamp = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970) - 3_600)
        let first = turnLine(promptID: "p-aaaa", input: 1_000, output: 100, cachedRead: 0,
                             total: 1_100, costTicks: nil)
        try writeSession("hit", lines: [first], mtime: stamp)
        _ = await LocalUsageCache(grokRoot: root, fileURL: cacheFile).grokEntries(modifiedSince: epoch)

        // 같은 길이·같은 mtime 으로 교체(id 만 다름) → 캐시를 쓰면 옛 id 가 그대로 나온다.
        let swapped = turnLine(promptID: "p-bbbb", input: 1_000, output: 100, cachedRead: 0,
                              total: 1_100, costTicks: nil)
        XCTAssertEqual(swapped.count, first.count, "바꿔치기 라인은 길이가 같아야 캐시 키가 유지된다")
        try writeSession("hit", lines: [swapped], mtime: stamp)

        let cached = await LocalUsageCache(grokRoot: root, fileURL: cacheFile).grokEntries(modifiedSince: epoch)
        XCTAssertEqual(cached.map(\.id), ["grok|p-aaaa"], "디스크 스냅샷을 재사용해야 한다")
    }

    /// 파서 버전이 바뀌면 Grok blob 만 버리고 재파싱한다(토큰 매핑 변경이 옛 캐시에 굳지 않게).
    func testGrokParserVersionInvalidatesCachedBlobs() async throws {
        let stamp = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970) - 3_600)
        let first = turnLine(promptID: "p-aaaa", input: 1_000, output: 100, cachedRead: 0,
                             total: 1_100, costTicks: nil)
        try writeSession("ver", lines: [first], mtime: stamp)
        _ = await LocalUsageCache(grokRoot: root, fileURL: cacheFile).grokEntries(modifiedSince: epoch)

        try rewriteSnapshot { snapshot in snapshot["grokParserVersion"] = 0 }

        let swapped = turnLine(promptID: "p-bbbb", input: 1_000, output: 100, cachedRead: 0,
                              total: 1_100, costTicks: nil)
        try writeSession("ver", lines: [swapped], mtime: stamp)
        let entries = await LocalUsageCache(grokRoot: root, fileURL: cacheFile).grokEntries(modifiedSince: epoch)
        XCTAssertEqual(entries.map(\.id), ["grok|p-bbbb"], "버전 불일치면 재파싱해야 한다")
    }

    /// grok 키가 없는 구버전 스냅샷도 로드된다 — 여기서 throw 하면 `ensureLoaded` 가 중단되고
    /// Claude/Codex/Gemini 까지 전부 콜드 재파싱(수백 MB)에 빠진다.
    func testSnapshotWithoutGrokKeysStillLoads() async throws {
        let stamp = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970) - 3_600)
        try writeSession("legacy", lines: [turnLine(promptID: "p-legacy")], mtime: stamp)
        _ = await LocalUsageCache(grokRoot: root, fileURL: cacheFile).grokEntries(modifiedSince: epoch)

        try rewriteSnapshot { snapshot in
            snapshot.removeValue(forKey: "grok")
            snapshot.removeValue(forKey: "grokParserVersion")
        }

        let entries = await LocalUsageCache(grokRoot: root, fileURL: cacheFile).grokEntries(modifiedSince: epoch)
        XCTAssertEqual(entries.map(\.id), ["grok|p-legacy"], "구버전 스냅샷에서도 재파싱으로 복구돼야 한다")
    }

    /// [회귀] 서브에이전트 판정 근거(summary.json)는 캐시 키(updates.jsonl 의 mtime·size)와 다른
    /// 파일이다. 판정을 파싱 안에서 하면 "summary 가 아직 session_kind 를 못 쓴" 시점의 결과가 blob 에
    /// 굳어 이중집계가 영구화된다 — 파일 선택 단계 판정이면 다음 새로고침에 자연 복구된다.
    func testLateWrittenSessionKindStopsCountingOnNextRefresh() async throws {
        let stamp = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970) - 3_600)
        try writeSession("sub-late", lines: [turnLine(promptID: "p-sub-late")],
                         summary: false, mtime: stamp)
        let cache = LocalUsageCache(grokRoot: root, fileURL: cacheFile)
        let before = await cache.grokEntries(modifiedSince: epoch)
        XCTAssertEqual(before.map(\.id), ["grok|p-sub-late"], "summary 없으면 사용자 세션으로 센다")

        // 세션이 끝나며 summary 에 session_kind 가 찍힌다. updates.jsonl 은 더 안 바뀐다.
        try writeSummary("sub-late", sessionKind: "subagent")

        let after = await cache.grokEntries(modifiedSince: epoch)
        XCTAssertTrue(after.isEmpty, "다음 새로고침엔 서브에이전트로 제외돼야 한다(부모 턴에 이미 포함)")
    }

    private func rewriteSnapshot(_ mutate: (inout [String: Any]) throws -> Void) throws {
        let raw = try Data(contentsOf: cacheFile)
        let plain = (try? (raw as NSData).decompressed(using: .zlib) as Data) ?? raw
        var snapshot = try XCTUnwrap(JSONSerialization.jsonObject(with: plain) as? [String: Any])
        try mutate(&snapshot)
        let data = try JSONSerialization.data(withJSONObject: snapshot)
        try ((data as NSData).compressed(using: .zlib) as Data).write(to: cacheFile, options: .atomic)
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
            opencodeGoLimitsProvider: NoOpenCodeGoLimitsForGrok(),
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

    /// Grok 을 안 쓰는 사용자(세션 디렉토리 없음)에서 프로바이더는 조용히 비어야 한다 —
    /// 던지면 refresh 전체가 에러로 물들고, 0 을 돌려주면 미사용 프로바이더 탭이 생긴다.
    /// (스모크: 실제 경로가 없을 때의 경로만 확인한다 — 파싱·집계는 위 픽스처 테스트가 담당.)
    func testProviderIsSilentWhenNoGrokDataExists() async throws {
        guard !FileManager.default.fileExists(atPath: LocalUsageReader.grokSessionsDir.path) else {
            throw XCTSkip("이 기기에 Grok 세션이 있어 '없을 때' 경로를 검증할 수 없다")
        }
        let daily = try await LocalGrokProvider().fetchDaily()
        XCTAssertNil(daily, "세션 디렉토리가 없으면 스냅샷을 만들지 않아야 한다")
        let enrichment = await LocalGrokProvider().fetchEnrichment()
        XCTAssertNil(enrichment.activeBlock)
        XCTAssertEqual(enrichment.weekTotal?.totalTokens, 0)
    }

    /// 세션 루트 기본값은 `~/.grok/sessions` — CLI 가 `$GROK_HOME` 없을 때 쓰는 경로와 같아야 한다.
    /// (환경변수가 설정된 셸에서 돌면 그 경로가 진실이므로 기본값 검증은 건너뛴다.)
    func testSessionsDirDefaultsToDotGrokUnderHome() throws {
        let env = ProcessInfo.processInfo.environment["GROK_HOME"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let dir = LocalUsageReader.grokSessionsDir
        if let env, !env.isEmpty {
            XCTAssertTrue(dir.path.hasPrefix(URL(fileURLWithPath: env).path),
                          "$GROK_HOME 가 설정되면 그 아래를 봐야 한다: \(dir.path)")
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".grok/sessions")
            XCTAssertEqual(dir.standardizedFileURL.path, home.standardizedFileURL.path)
        }
        XCTAssertEqual(dir.lastPathComponent, "sessions")
    }
}
