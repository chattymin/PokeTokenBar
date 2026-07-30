import XCTest
@testable import PokeTokenBar

// LocalUsageReader / ModelPricing 의 파싱·dedup·날짜·비용 로직 — 임시 디렉토리 fixture 로 결정적 검증.
final class LocalUsageReaderTests: XCTestCase {

    private func tempDir() -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("ptb-local-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    private func write(_ lines: [String], to dir: URL, name: String = "s.jsonl", sub: String? = nil) {
        let folder = sub.map { dir.appendingPathComponent($0) } ?? dir
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? lines.joined(separator: "\n").write(to: folder.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }
    private func copyCodexForkFixture(_ name: String, to dir: URL) throws -> URL {
        let source = try XCTUnwrap(
            Bundle.module.url(forResource: name, withExtension: "jsonl", subdirectory: "CodexFork")
        )
        let destination = dir.appendingPathComponent("\(name).jsonl")
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }

    // MARK: ModelPricing

    func testPricingExactAndFallbackAndZero() {
        XCTAssertEqual(ModelPricing.cost(model: "claude-opus-4-8", input: 1_000_000, output: 0, cacheWrite: 0, cacheRead: 0), 5.0, accuracy: 1e-6)
        XCTAssertEqual(ModelPricing.cost(model: "claude-opus-4-8", input: 0, output: 1_000_000, cacheWrite: 0, cacheRead: 0), 25.0, accuracy: 1e-6)
        XCTAssertEqual(ModelPricing.cost(model: "claude-haiku-4-5-20251001", input: 1_000_000, output: 0, cacheWrite: 0, cacheRead: 0), 1.0, accuracy: 1e-6)
        XCTAssertEqual(ModelPricing.cost(model: "claude-fable-5", input: 1_000_000, output: 1_000_000, cacheWrite: 1_000_000, cacheRead: 1_000_000), 0, accuracy: 1e-9)
        // 미지 모델 → 패밀리 폴백
        XCTAssertEqual(ModelPricing.cost(model: "claude-opus-4-99", input: 1_000_000, output: 0, cacheWrite: 0, cacheRead: 0), 5.0, accuracy: 1e-6)
        XCTAssertEqual(ModelPricing.cost(model: "totally-unknown", input: 1_000_000, output: 0, cacheWrite: 0, cacheRead: 0), 0, accuracy: 1e-9)
    }

    // MARK: Claude 파싱 + dedup(keep-max) + 날짜

    private func claudeLine(id: String, req: String, model: String, ts: String, i: Int, o: Int, cw: Int, cr: Int) -> String {
        """
        {"type":"assistant","requestId":"\(req)","timestamp":"\(ts)","message":{"id":"\(id)","model":"\(model)","usage":{"input_tokens":\(i),"output_tokens":\(o),"cache_creation_input_tokens":\(cw),"cache_read_input_tokens":\(cr)}}}
        """
    }

    func testClaudeDedupKeepsMaxOutput() {
        let dir = tempDir()
        let ts = "2026-06-30T10:00:00.000Z"
        // 같은 (id,req) 가 스트리밍으로 두 번: output 5 → 200. cacheRead 고정 1000.
        write([
            claudeLine(id: "A", req: "R1", model: "claude-opus-4-8", ts: ts, i: 100, o: 5, cw: 0, cr: 1000),
            claudeLine(id: "A", req: "R1", model: "claude-opus-4-8", ts: ts, i: 100, o: 200, cw: 0, cr: 1000),
            claudeLine(id: "B", req: "R2", model: "claude-sonnet-4-6", ts: ts, i: 50, o: 10, cw: 0, cr: 0),
        ], to: dir, sub: "proj/sub")

        let entries = LocalUsageReader.claudeEntries(modifiedSince: .distantPast, root: dir)
        XCTAssertEqual(entries.count, 2)   // A(dedup), B
        let a = entries.first { $0.id.hasPrefix("A|") }
        XCTAssertEqual(a?.output, 200)     // keep-max: 완성된 output
        XCTAssertEqual(a?.cacheRead, 1000)
    }

    func testClaudeDailyAndCost() {
        let dir = tempDir()
        let ts = "2026-06-30T10:00:00.000Z"
        let day = LocalUsageReader.localDayFormatter().string(from: ISO8601Parser.date(from: ts)!)
        write([
            claudeLine(id: "A", req: "R1", model: "claude-opus-4-8", ts: ts, i: 1_000_000, o: 0, cw: 0, cr: 0),
        ], to: dir, sub: "p")
        let entries = LocalUsageReader.claudeEntries(modifiedSince: .distantPast, root: dir)
        let d = LocalUsageReader.daily(entries: entries, localDay: day)
        XCTAssertEqual(d?.totalTokens, 1_000_000)
        XCTAssertEqual(d?.totalCost ?? 0, 5.0, accuracy: 1e-6)   // opus input 5/Mtok
        XCTAssertNil(LocalUsageReader.daily(entries: entries, localDay: "2000-01-01"))
    }

    // MARK: Codex 파싱 (input=total−cached, cacheRead=cached, output, cacheWrite=0)

    private func codexLine(ts: String, input: Int = 1_000, cached: Int = 200,
                           output: Int = 50, reasoning: Int = 10, cacheWrite: Int = 0) -> String {
        return """
        {"type":"event_msg","timestamp":"\(ts)","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":\(input),"cached_input_tokens":\(cached),"cache_write_input_tokens":\(cacheWrite),"output_tokens":\(output),"reasoning_output_tokens":\(reasoning),"total_tokens":\(input + output)}}}}
        """
    }

    private func codexSessionMeta(id: String, ts: String) -> String {
        """
        {"type":"session_meta","timestamp":"\(ts)","payload":{"id":"\(id)","session_id":"\(id)"}}
        """
    }

    private func codexStateLine(
        ts: String,
        cumulativeInput: Int,
        cumulativeCached: Int = 0,
        cumulativeOutput: Int,
        cumulativeReasoning: Int = 0,
        lastInput: Int,
        lastCached: Int = 0,
        lastOutput: Int,
        lastReasoning: Int = 0,
        lastTotal: Int? = nil
    ) -> String {
        let cumulativeTotal = cumulativeInput + cumulativeOutput
        let reportedLastTotal = lastTotal ?? (lastInput + lastOutput)
        return """
        {"type":"event_msg","timestamp":"\(ts)","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":\(cumulativeInput),"cached_input_tokens":\(cumulativeCached),"output_tokens":\(cumulativeOutput),"reasoning_output_tokens":\(cumulativeReasoning),"total_tokens":\(cumulativeTotal)},"last_token_usage":{"input_tokens":\(lastInput),"cached_input_tokens":\(lastCached),"output_tokens":\(lastOutput),"reasoning_output_tokens":\(lastReasoning),"total_tokens":\(reportedLastTotal)}}}}
        """
    }

    private func forkedSessionMeta(ts: String) -> String {
        """
        {"type":"session_meta","timestamp":"\(ts)","payload":{"id":"child","forked_from_id":"parent","parent_thread_id":"parent","thread_source":"subagent"}}
        """
    }

    private func forkedSubagentSessionMeta(ts: String) -> String {
        """
        {"type":"session_meta","timestamp":"\(ts)","payload":{"id":"child","parent_thread_id":"parent","thread_source":"subagent","cli_version":"0.145.0"}}
        """
    }

    func testCodexParsing() {
        let dir = tempDir()
        let line = codexLine(ts: "2026-06-30T11:00:00.000Z")
        write([line], to: dir, name: "rollout-x.jsonl", sub: "2026/06/30")
        let entries = LocalUsageReader.codexEntries(modifiedSince: .distantPast, root: dir)
        XCTAssertEqual(entries.count, 1)
        let e = entries[0]
        XCTAssertEqual(e.input, 800)       // 1000 - 200
        XCTAssertEqual(e.cacheRead, 200)
        XCTAssertEqual(e.output, 50)
        XCTAssertEqual(e.cacheWrite, 0)
    }

    func testCodexDropsConsecutiveSameStateRerecordsAndMatchesCumulativeTotal() {
        let dir = tempDir()
        write([
            codexSessionMeta(id: "session-a", ts: "2026-07-29T01:00:00.000Z"),
            codexStateLine(
                ts: "2026-07-29T01:00:01.000Z",
                cumulativeInput: 100, cumulativeCached: 20, cumulativeOutput: 10,
                lastInput: 100, lastCached: 20, lastOutput: 10),
            // 같은 snapshot의 단순 재기록.
            codexStateLine(
                ts: "2026-07-29T01:00:02.000Z",
                cumulativeInput: 100, cumulativeCached: 20, cumulativeOutput: 10,
                lastInput: 100, lastCached: 20, lastOutput: 10),
            codexStateLine(
                ts: "2026-07-29T01:00:03.000Z",
                cumulativeInput: 300, cumulativeCached: 120, cumulativeOutput: 30,
                lastInput: 200, lastCached: 100, lastOutput: 20),
            // 같은 session_meta가 다시 기록돼도 token_count 상태의 연속성은 유지한다.
            codexSessionMeta(id: "session-a", ts: "2026-07-29T01:00:04.000Z"),
            codexStateLine(
                ts: "2026-07-29T01:00:05.000Z",
                cumulativeInput: 300, cumulativeCached: 120, cumulativeOutput: 30,
                lastInput: 200, lastCached: 100, lastOutput: 20),
        ], to: dir)

        let entries = LocalUsageReader.codexEntries(modifiedSince: .distantPast, root: dir)

        XCTAssertEqual(entries.map(\.total), [110, 220])
        XCTAssertEqual(entries.reduce(0) { $0 + $1.total }, 330)
    }

    func testCodexSameScalarTotalsWithDifferentFullVectorsArePreserved() {
        let dir = tempDir()
        write([
            codexSessionMeta(id: "session-a", ts: "2026-07-29T01:00:00.000Z"),
            codexStateLine(
                ts: "2026-07-29T01:00:01.000Z",
                cumulativeInput: 100, cumulativeCached: 20, cumulativeOutput: 10,
                lastInput: 100, lastCached: 20, lastOutput: 10),
            // cumulative/last total은 각각 110으로 같지만 input/cache/output 구성은 다르다.
            codexStateLine(
                ts: "2026-07-29T01:00:02.000Z",
                cumulativeInput: 90, cumulativeCached: 10, cumulativeOutput: 20,
                lastInput: 90, lastCached: 10, lastOutput: 20),
        ], to: dir)

        let entries = LocalUsageReader.codexEntries(modifiedSince: .distantPast, root: dir)

        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.map(\.total), [110, 110])
    }

    func testCodexUnchangedCumulativeWithDifferentLastVectorIsPreserved() {
        let dir = tempDir()
        write([
            codexSessionMeta(id: "session-a", ts: "2026-07-29T01:00:00.000Z"),
            codexStateLine(
                ts: "2026-07-29T01:00:01.000Z",
                cumulativeInput: 100, cumulativeOutput: 10,
                lastInput: 100, lastOutput: 10),
            // 실제 fork fixture의 post-replay 이벤트와 같은 모양: cumulative는 그대로지만
            // last.total_tokens만 비영(앱 회계 필드는 모두 0)인 상태는 동일 snapshot이 아니다.
            codexStateLine(
                ts: "2026-07-29T01:00:02.000Z",
                cumulativeInput: 100, cumulativeOutput: 10,
                lastInput: 0, lastOutput: 0, lastTotal: 6_742),
        ], to: dir)

        let entries = LocalUsageReader.codexEntries(modifiedSince: .distantPast, root: dir)

        XCTAssertEqual(entries.map(\.total), [110, 0])
    }

    func testCodexSessionChangeResetsSameStateComparison() {
        let dir = tempDir()
        let stateA = codexStateLine(
            ts: "2026-07-29T01:00:01.000Z",
            cumulativeInput: 100, cumulativeOutput: 10,
            lastInput: 100, lastOutput: 10)
        let stateB = codexStateLine(
            ts: "2026-07-29T01:00:03.000Z",
            cumulativeInput: 100, cumulativeOutput: 10,
            lastInput: 100, lastOutput: 10)
        write([
            codexSessionMeta(id: "session-a", ts: "2026-07-29T01:00:00.000Z"),
            stateA,
            codexSessionMeta(id: "session-b", ts: "2026-07-29T01:00:02.000Z"),
            stateB,
        ], to: dir)

        let entries = LocalUsageReader.codexEntries(modifiedSince: .distantPast, root: dir)

        XCTAssertEqual(entries.map(\.total), [110, 110])
    }

    func testCodexMissingCumulativeUsagePreservesRepeatedRecords() {
        let dir = tempDir()
        write([
            codexSessionMeta(id: "session-a", ts: "2026-07-29T01:00:00.000Z"),
            codexLine(ts: "2026-07-29T01:00:01.000Z"),
            codexLine(ts: "2026-07-29T01:00:02.000Z"),
        ], to: dir)

        let entries = LocalUsageReader.codexEntries(modifiedSince: .distantPast, root: dir)

        XCTAssertEqual(entries.count, 2)
    }

    func testCodexForkTrimsReplayBeforeDroppingActualSameStateRerecord() {
        let dir = tempDir()
        write([
            forkedSessionMeta(ts: "2026-07-29T01:00:00.000Z"),
            codexStateLine(
                ts: "2026-07-29T01:00:00.010Z",
                cumulativeInput: 100, cumulativeOutput: 10,
                lastInput: 100, lastOutput: 10),
            codexStateLine(
                ts: "2026-07-29T01:00:03.000Z",
                cumulativeInput: 300, cumulativeOutput: 30,
                lastInput: 200, lastOutput: 20),
            codexStateLine(
                ts: "2026-07-29T01:00:04.000Z",
                cumulativeInput: 300, cumulativeOutput: 30,
                lastInput: 200, lastOutput: 20),
        ], to: dir, name: "rollout-child.jsonl", sub: "child")

        let entries = LocalUsageReader.codexEntries(modifiedSince: .distantPast, root: dir)

        XCTAssertEqual(entries.map(\.total), [220])
    }

    func testCodexForkedRolloutDropsLeadingReplayBurst() {
        let dir = tempDir()
        write([
            forkedSessionMeta(ts: "2026-07-29T01:00:00.000Z"),
            codexLine(ts: "2026-07-29T01:00:00.010Z", output: 50),
            codexLine(ts: "2026-07-29T01:00:00.020Z", output: 51),
            codexLine(ts: "2026-07-29T01:00:03.000Z", output: 52),
        ], to: dir, name: "rollout-child.jsonl", sub: "child")

        let entries = LocalUsageReader.codexEntries(modifiedSince: .distantPast, root: dir)

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].output, 52)
    }

    func testCodexForkDropsReplayBurstThatStartsAfterMetadataDelay() {
        let dir = tempDir()
        write([
            forkedSubagentSessionMeta(ts: "2026-07-29T01:00:00.000Z"),
            codexLine(ts: "2026-07-29T01:00:03.000Z", output: 1),
            codexLine(ts: "2026-07-29T01:00:03.010Z", output: 2),
            codexLine(ts: "2026-07-29T01:00:03.020Z", output: 3),
            codexLine(ts: "2026-07-29T01:00:43.000Z", output: 99),
        ], to: dir, name: "rollout-child.jsonl", sub: "child")

        let entries = LocalUsageReader.codexEntries(modifiedSince: .distantPast, root: dir)

        XCTAssertEqual(entries.map(\.output), [99])
    }

    func testCodexForkKeepsRealTurnsAfterReplayBurstWhenTheyAreLessThanTwoSecondsApart() {
        let dir = tempDir()
        write([
            forkedSubagentSessionMeta(ts: "2026-07-29T01:00:00.000Z"),
            codexLine(ts: "2026-07-29T01:00:00.010Z", output: 1),
            codexLine(ts: "2026-07-29T01:00:00.020Z", output: 2),
            codexLine(ts: "2026-07-29T01:00:00.030Z", output: 3),
            codexLine(ts: "2026-07-29T01:00:01.530Z", output: 11),
            codexLine(ts: "2026-07-29T01:00:03.030Z", output: 22),
            codexLine(ts: "2026-07-29T01:00:04.530Z", output: 33),
            codexLine(ts: "2026-07-29T01:01:00.000Z", output: 44),
        ], to: dir, name: "rollout-child.jsonl", sub: "child")

        let entries = LocalUsageReader.codexEntries(modifiedSince: .distantPast, root: dir)

        XCTAssertEqual(entries.map(\.output), [11, 22, 33, 44])
    }

    func testCodexForkDetectsMetadataAfterLeadingNonTokenRecord() {
        let dir = tempDir()
        write([
            #"{"type":"turn_context","timestamp":"2026-07-29T01:00:00.000Z","payload":{}}"#,
            forkedSubagentSessionMeta(ts: "2026-07-29T01:00:00.001Z"),
            codexLine(ts: "2026-07-29T01:00:00.010Z", output: 1),
            codexLine(ts: "2026-07-29T01:00:03.000Z", output: 99),
        ], to: dir, name: "rollout-child.jsonl", sub: "child")

        let entries = LocalUsageReader.codexEntries(modifiedSince: .distantPast, root: dir)

        XCTAssertEqual(entries.map(\.output), [99])
    }

    func testCodexManualForkFixtureKeepsOnlyPostReplayUsage() throws {
        let child = try copyCodexForkFixture("child", to: tempDir())
        let entries = LocalUsageReader.parseCodexFile(child, fmt: LocalUsageReader.localDayFormatter())

        // 실제 `codex fork` 파일: child meta(forked_from_id only) 뒤에 parent meta와
        // 8개 부모 token_count가 재삽입된다. 이후 0 토큰 이벤트는 보존하고, 새 turn만 집계한다.
        XCTAssertEqual(entries.map(\.total), [0, 28_138])
    }

    func testCodexManualForkFixtureKeepsParentAndChildUsageOnTheirOwnDays() throws {
        let dir = tempDir()
        let parent = try copyCodexForkFixture("parent", to: dir)
        _ = try copyCodexForkFixture("child", to: dir)
        let fmt = LocalUsageReader.localDayFormatter()
        let parentEntries = LocalUsageReader.parseCodexFile(parent, fmt: fmt)
        let parentDay = try XCTUnwrap(parentEntries.first?.localDay)
        let entries = LocalUsageReader.codexEntries(modifiedSince: .distantPast, root: dir)
        let childDay = try XCTUnwrap(entries.first { $0.total == 28_138 }?.localDay)

        XCTAssertEqual(LocalUsageReader.daily(entries: entries, localDay: parentDay)?.totalTokens, 312_814)
        XCTAssertEqual(LocalUsageReader.daily(entries: entries, localDay: childDay)?.totalTokens, 28_138)
        XCTAssertEqual(
            LocalUsageReader.period(entries: entries, periodKey: "fixture", fromDay: parentDay, toDay: childDay).totalTokens,
            340_952
        )
    }

    func testCodexSiblingForkFixturesKeepIndependentPostReplayUsage() throws {
        let dir = tempDir()
        _ = try copyCodexForkFixture("parent", to: dir)
        _ = try copyCodexForkFixture("child", to: dir)
        _ = try copyCodexForkFixture("sibling", to: dir)

        let entries = LocalUsageReader.codexEntries(modifiedSince: .distantPast, root: dir)

        let forkTotals = entries.map(\.total).filter { $0 == 28_138 || $0 == 28_263 }
        XCTAssertEqual(forkTotals.sorted(), [28_138, 28_263])
        XCTAssertEqual(entries.reduce(0) { $0 + $1.total }, 369_215)
    }

    // MARK: 기간 집계 + 활성 블록

    func testPeriodAndActiveBlock() {
        // 로컬 정오로 고정 — Date() 로 두면 자정 직후 실행 시 now-30분이 전날로 넘어가
        // period(today,today) 범위 밖이 돼 flaky 했다(시각-의존 결함, 자정±30분에만 실패).
        let now = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date()) ?? Date()
        let recent = now.addingTimeInterval(-30 * 60)   // 30분 전(같은 날)
        let old = now.addingTimeInterval(-10 * 3600)    // 10시간 전(블록 밖, 같은 날)
        let fmt = LocalUsageReader.localDayFormatter()
        func entry(_ date: Date, _ tok: Int) -> LocalUsageReader.Entry {
            LocalUsageReader.Entry(id: UUID().uuidString, date: date, localDay: fmt.string(from: date),
                                   model: "claude-opus-4-8", input: tok, output: 0, cacheWrite: 0, cacheRead: 0)
        }
        let entries = [entry(recent, 600_000), entry(old, 999)]
        let block = LocalUsageReader.activeBlock(entries: entries, now: now)
        XCTAssertEqual(block?.totalTokens, 600_000)        // 5h 윈도우 내 항목만
        XCTAssertEqual(block?.isActive, true)
        XCTAssertGreaterThan(block?.tokensPerMinute ?? 0, 0)
        // period: 오늘 범위
        let today = fmt.string(from: now)
        let p = LocalUsageReader.period(entries: entries, periodKey: "w", fromDay: today, toDay: today)
        // recent 는 오늘, old 도 (10h 전이라 같은 날일 수 있음) → 최소 recent 포함
        XCTAssertGreaterThanOrEqual(p.totalTokens, 600_000)
    }

    // MARK: enrichment 스캔 하한 (월초 경계 흡수)

    /// 스캔 하한은 블록(now-5h)·이번 주(weekStart)·이번 달(monthStart) 세 윈도우 시작을 모두 덮어야
    /// append-only 로그의 "하한 이전 파일엔 범위 내 엔트리 없음" 전제가 성립한다. 월초엔 weekStart 가
    /// 지난달로 넘어가므로 하한 < monthStart 여야 한다(monthStart-only 였던 과거 회귀를 순수 경로로 고정).
    func testEnrichmentScanStartCoversAllWindows() throws {
        let cal = Calendar.current
        let base = cal.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 2))!
        var straddle: Date?
        for offset in 0..<14 {
            guard let candidate = cal.date(byAdding: .month, value: offset, to: base) else { continue }
            if LocalUsageReader.startOfWeek(candidate) < LocalUsageReader.startOfMonth(candidate) {
                straddle = candidate; break
            }
        }
        let now = try XCTUnwrap(straddle)
        let scan = LocalUsageReader.enrichmentScanStart(now: now)
        XCTAssertLessThanOrEqual(scan, LocalUsageReader.startOfMonth(now))
        XCTAssertLessThanOrEqual(scan, LocalUsageReader.startOfWeek(now))
        XCTAssertLessThanOrEqual(scan, now.addingTimeInterval(-LocalUsageReader.blockWindow))
        XCTAssertLessThan(scan, LocalUsageReader.startOfMonth(now),
                          "월초엔 weekStart 가 더 이르므로 하한이 monthStart 보다 앞서야 한다")

        // 월 중순: monthStart 가 가장 이르므로 하한 == monthStart (경계 밖 과다 스캔 없음).
        let mid = cal.date(from: DateComponents(year: 2026, month: 7, day: 20, hour: 12))!
        XCTAssertEqual(LocalUsageReader.enrichmentScanStart(now: mid), LocalUsageReader.startOfMonth(mid))
    }
}
