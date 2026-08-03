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
    private func copyCodexSubagentFixture(_ name: String, to dir: URL) throws -> URL {
        let source = try XCTUnwrap(
            Bundle.module.url(forResource: name, withExtension: "jsonl", subdirectory: "CodexSubagent")
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
        {"type":"session_meta","timestamp":"\(ts)","payload":{"id":"child","forked_from_id":"parent","parent_thread_id":"parent","thread_source":"user"}}
        """
    }

    private func forkedSessionMeta(id: String, parentID: String, ts: String) -> String {
        """
        {"type":"session_meta","timestamp":"\(ts)","payload":{"id":"\(id)","session_id":"\(parentID)","forked_from_id":"\(parentID)","parent_thread_id":"\(parentID)","thread_source":"subagent"}}
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

    func testCodexNonForkResolverPreservesParsedEntriesExceptCanonicalIDs() {
        let dir = tempDir()
        write([
            codexSessionMeta(id: "session-a", ts: "2026-07-29T01:00:00.000Z"),
            codexStateLine(
                ts: "2026-07-29T01:00:01.000Z",
                cumulativeInput: 100, cumulativeCached: 20, cumulativeOutput: 10,
                lastInput: 100, lastCached: 20, lastOutput: 10),
            codexStateLine(
                ts: "2026-07-29T01:00:02.000Z",
                cumulativeInput: 300, cumulativeCached: 120, cumulativeOutput: 30,
                lastInput: 200, lastCached: 100, lastOutput: 20),
            codexStateLine(
                ts: "2026-07-29T01:00:03.000Z",
                cumulativeInput: 450, cumulativeCached: 170, cumulativeOutput: 45,
                lastInput: 150, lastCached: 50, lastOutput: 15),
        ], to: dir, name: "rollout.jsonl")
        let file = dir.appendingPathComponent("rollout.jsonl")
        let rollout = LocalUsageReader.parseCodexRollout(
            file,
            fmt: LocalUsageReader.localDayFormatter()
        )
        let parsed = rollout.events.map(\.entry)
        XCTAssertEqual(parsed.count, 3)

        let resolved = LocalUsageReader.resolveCodexRollouts(
            [rollout],
            includedPaths: [rollout.path]
        )

        XCTAssertEqual(resolved.count, parsed.count)
        for (before, after) in zip(parsed, resolved) {
            XCTAssertNotEqual(after.id, before.id)
            XCTAssertTrue(after.id.hasPrefix("codex|session-a|0|"))
            XCTAssertEqual(after.date, before.date)
            XCTAssertEqual(after.localDay, before.localDay)
            XCTAssertEqual(after.model, before.model)
            XCTAssertEqual(after.input, before.input)
            XCTAssertEqual(after.output, before.output)
            XCTAssertEqual(after.cacheWrite, before.cacheWrite)
            XCTAssertEqual(after.cacheRead, before.cacheRead)
            XCTAssertEqual(after.explicitCost, before.explicitCost)
        }
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

    func testCodexManualForkFallsBackWhenParentUsageStateIsUnavailable() {
        let dir = tempDir()
        write([
            codexSessionMeta(id: "parent", ts: "2026-07-29T01:00:00.000Z"),
            codexLine(ts: "2026-07-29T01:00:00.010Z", output: 50),
            codexLine(ts: "2026-07-29T01:00:00.020Z", output: 51),
        ], to: dir, name: "parent.jsonl")
        write([
            forkedSessionMeta(ts: "2026-07-30T01:00:00.000Z"),
            codexSessionMeta(id: "parent", ts: "2026-07-30T01:00:00.001Z"),
            // total_token_usage가 없는 구형 replay는 parent와 구조 비교할 수 없으므로 시간 fallback 대상.
            codexLine(ts: "2026-07-30T01:00:03.000Z", output: 50),
            codexLine(ts: "2026-07-30T01:00:03.010Z", output: 51),
            codexLine(ts: "2026-07-30T01:00:06.000Z", output: 99),
        ], to: dir, name: "child.jsonl")

        let entries = LocalUsageReader.codexEntries(modifiedSince: .distantPast, root: dir)

        XCTAssertEqual(entries.map(\.output).sorted(), [50, 51, 99])
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
            forkedSessionMeta(ts: "2026-07-29T01:00:00.000Z"),
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
            forkedSessionMeta(ts: "2026-07-29T01:00:00.000Z"),
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
            forkedSessionMeta(ts: "2026-07-29T01:00:00.001Z"),
            codexLine(ts: "2026-07-29T01:00:00.010Z", output: 1),
            codexLine(ts: "2026-07-29T01:00:03.000Z", output: 99),
        ], to: dir, name: "rollout-child.jsonl", sub: "child")

        let entries = LocalUsageReader.codexEntries(modifiedSince: .distantPast, root: dir)

        XCTAssertEqual(entries.map(\.output), [99])
    }

    // MARK: Codex metadata probe (parent dependency 탐색용)

    /// `session_meta` 한 줄을 임의 길이로 부풀린다(실파일에서 이 줄을 키우는 건 dynamic_tools·base_instructions).
    private func paddedCodexSessionMeta(id: String, totalBytes: Int, tail: String = "") -> String {
        let head = #"{"type":"session_meta","timestamp":"2026-07-29T01:00:00.000Z","payload":{"id":"\#(id)","session_id":"\#(id)","base_instructions":""#
        let close = #""}}"#
        let pad = totalBytes - head.utf8.count - close.utf8.count - tail.utf8.count
        XCTAssertGreaterThan(pad, 0, "패딩 계산이 음수 — 테스트 상수 확인")
        return head + String(repeating: "a", count: max(pad, 0)) + tail + close
    }

    private func writeProbeFile(_ lines: [String]) -> URL {
        let url = tempDir().appendingPathComponent("rollout-probe.jsonl")
        // 실제 rollout 처럼 마지막 줄에 개행을 붙이지 않는다(EOF 플러시 경로도 함께 검증).
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// 첫 줄이 고정 prefix(64KB)보다 길어도 session id 를 읽어야 한다.
    /// MCP 도구가 늘면 `dynamic_tools` 만으로 30KB 를 넘기므로 실사용에서 도달 가능한 크기다.
    func testCodexProbeReadsSessionIDWhenMetadataLineExceedsChunk() throws {
        let url = writeProbeFile([
            paddedCodexSessionMeta(id: "parent-xl", totalBytes: 200_000),
            codexLine(ts: "2026-07-29T01:00:01.000Z"),
        ])
        let prefix = try XCTUnwrap(FileHandle(forReadingFrom: url).read(upToCount: 64 * 1024))
        XCTAssertFalse(prefix.contains(0x0A),
                       "첫 64KB 안에 완성된 줄이 없어야 고정 prefix 방식이 실패하는 조건이 된다")

        XCTAssertEqual(LocalUsageReader.codexRolloutSessionID(at: url), "parent-xl")
    }

    /// 64KB chunk 경계가 멀티바이트 문자 중간에 떨어져도 완성된 줄 단위로 디코드해 id 를 얻는다.
    /// (고정 prefix 를 통째로 `String(data:encoding:)` 하던 방식은 여기서 nil 을 돌려줬다.)
    func testCodexProbeDecodesMultibyteStraddlingChunkBoundary() {
        let boundary = 64 * 1024
        // "가"(3바이트)가 65535 바이트에서 시작하도록 채워 경계(65536)가 문자 내부에 놓이게 한다.
        let meta = paddedCodexSessionMeta(id: "parent-utf8", totalBytes: boundary + 4, tail: "가")
        let bytes = Array(meta.utf8)
        XCTAssertTrue((0x80...0xBF).contains(bytes[boundary]),
                      "경계 바이트가 UTF-8 연속 바이트가 아니면 이 테스트는 회귀를 못 잡는다")
        XCTAssertNil(String(data: Data(bytes[0..<boundary]), encoding: .utf8),
                     "고정 prefix 디코드가 실패하는 조건이어야 한다")

        let url = writeProbeFile([meta, codexLine(ts: "2026-07-29T01:00:01.000Z")])

        XCTAssertEqual(LocalUsageReader.codexRolloutSessionID(at: url), "parent-utf8")
    }

    /// chunk 를 여러 번 넘기며 완성된 줄을 순회하는 경로 — 줄 경계가 chunk 경계와 어긋나고,
    /// 소비한 prefix 를 chunk 당 한 번만 제거하는 커서 처리가 어긋나면 여기서 깨진다.
    func testCodexProbeScansManyLinesAcrossChunks() {
        // 한 줄 ~80B × 2,000줄 ≈ 160KB → chunk(64KB) 3개에 걸치고 줄이 경계를 가로지른다.
        var lines = (0..<2_000).map {
            #"{"type":"response_item","seq":\#($0),"payload":{"text":"filler-filler-filler"}}"#
        }
        lines.append(codexSessionMeta(id: "parent-after-many-lines", ts: "2026-07-29T01:00:00.000Z"))
        let url = writeProbeFile(lines)

        XCTAssertEqual(LocalUsageReader.codexRolloutSessionID(at: url), "parent-after-many-lines")
    }

    /// 상한을 넘으면 무한히 읽지 않고 포기한다(meta 도 token_count 도 없는 손상 파일 방어).
    func testCodexProbeStopsAtByteLimit() {
        let url = writeProbeFile([paddedCodexSessionMeta(id: "parent-capped", totalBytes: 4_096)])

        XCTAssertNil(LocalUsageReader.codexRolloutSessionID(at: url, byteLimit: 1_024),
                     "상한 안에서 줄이 안 끝나면 nil")
        XCTAssertEqual(LocalUsageReader.codexRolloutSessionID(at: url, byteLimit: 4_096),
                       "parent-capped",
                       "개행 없는 metadata가 상한과 정확히 같으면 완성된 마지막 줄로 처리")
        XCTAssertEqual(LocalUsageReader.codexRolloutSessionID(at: url), "parent-capped",
                       "기본 상한(1MiB)에서는 같은 파일을 읽어낸다")
    }

    /// 손상된 child meta를 건너뛰어 뒤의 parent meta를 파일 자체의 id로 오인하면 안 된다.
    func testCodexProbeStopsAtInvalidUTF8BeforeSessionMeta() throws {
        let url = tempDir().appendingPathComponent("rollout-invalid-utf8.jsonl")
        var data = Data([0xFF, 0x0A])
        data.append(Data(codexSessionMeta(
            id: "wrong-parent",
            ts: "2026-07-29T01:00:00.001Z"
        ).utf8))
        try data.write(to: url)

        XCTAssertNil(LocalUsageReader.codexRolloutSessionID(at: url))
    }

    /// 기존 종료 조건 유지 — meta 보다 token_count 를 먼저 만나면 이 파일엔 쓸 metadata 가 없다.
    func testCodexProbeStopsAtTokenCountBeforeSessionMeta() {
        let url = writeProbeFile([
            codexLine(ts: "2026-07-29T01:00:00.000Z"),
            codexSessionMeta(id: "too-late", ts: "2026-07-29T01:00:01.000Z"),
        ])

        XCTAssertNil(LocalUsageReader.codexRolloutSessionID(at: url))
    }

    /// meta 가 첫 줄이 아니어도(선행 non-token 레코드) 찾고, 개행으로 끝나지 않는 파일도 처리한다.
    func testCodexProbeFindsMetadataAfterLeadingNonTokenRecord() {
        let url = writeProbeFile([
            #"{"type":"turn_context","timestamp":"2026-07-29T01:00:00.000Z","payload":{}}"#,
            codexSessionMeta(id: "parent-late", ts: "2026-07-29T01:00:00.001Z"),
        ])

        XCTAssertEqual(LocalUsageReader.codexRolloutSessionID(at: url), "parent-late")
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
        XCTAssertEqual(Set(entries.map(\.id)).count, entries.count)
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

    func testCodexSubagentFixturesKeepAllOwnUsageWithoutReplayPrefix() throws {
        let fixtures: [(parent: String, child: String, totals: [Int], combined: Int, childID: String)] = [
            (
                "parent", "child",
                [22_992, 23_043, 23_062, 23_219, 23_291],
                115_607,
                "00000000-0000-7000-8000-000000000002"
            ),
            (
                "parent-v145", "child-v145",
                [20_863, 21_175, 21_365, 21_458, 21_722],
                106_583,
                "00000000-0000-7000-8000-000000000146"
            ),
        ]

        for fixture in fixtures {
            let dir = tempDir()
            _ = try copyCodexSubagentFixture(fixture.parent, to: dir)
            _ = try copyCodexSubagentFixture(fixture.child, to: dir)

            let entries = LocalUsageReader.codexEntries(modifiedSince: .distantPast, root: dir)

            XCTAssertEqual(entries.map(\.total).sorted(), fixture.totals, fixture.child)
            XCTAssertEqual(entries.reduce(0) { $0 + $1.total }, fixture.combined, fixture.child)
            XCTAssertEqual(
                entries.filter { $0.id.hasPrefix("codex|\(fixture.childID)|") }.count,
                2,
                fixture.child
            )
        }
    }

    func testCodexSubagentChildFixturesKeepFirstTurnWhenParentIsMissing() throws {
        let fixtures: [(name: String, childID: String, parentID: String, totals: [Int])] = [
            (
                "child",
                "00000000-0000-7000-8000-000000000002",
                "00000000-0000-7000-8000-000000000001",
                [23_062, 23_291]
            ),
            (
                "child-v145",
                "00000000-0000-7000-8000-000000000146",
                "00000000-0000-7000-8000-000000000145",
                [21_458, 21_722]
            ),
        ]

        for fixture in fixtures {
            let child = try copyCodexSubagentFixture(fixture.name, to: tempDir())
            let rollout = LocalUsageReader.parseCodexRollout(
                child,
                fmt: LocalUsageReader.localDayFormatter()
            )
            let entries = LocalUsageReader.parseCodexFile(
                child,
                fmt: LocalUsageReader.localDayFormatter()
            )

            XCTAssertEqual(rollout.sessionID, fixture.childID, fixture.name)
            XCTAssertEqual(rollout.parentSessionID, fixture.parentID, fixture.name)
            XCTAssertTrue(rollout.isSubagent, fixture.name)
            XCTAssertEqual(entries.map(\.total), fixture.totals, fixture.name)
            XCTAssertTrue(
                entries.allSatisfy { $0.id.hasPrefix("codex|\(fixture.childID)|") },
                fixture.name
            )
        }
    }

    func testCodexForkOfForkReusesResolvedAncestorHistory() {
        let dir = tempDir()
        let first = codexStateLine(
            ts: "2026-07-30T01:00:01.000Z",
            cumulativeInput: 100, cumulativeOutput: 10,
            lastInput: 100, lastOutput: 10)
        let second = codexStateLine(
            ts: "2026-07-30T01:00:02.000Z",
            cumulativeInput: 200, cumulativeOutput: 20,
            lastInput: 100, lastOutput: 10)
        let third = codexStateLine(
            ts: "2026-07-30T01:00:03.000Z",
            cumulativeInput: 300, cumulativeOutput: 30,
            lastInput: 100, lastOutput: 10)
        let fourth = codexStateLine(
            ts: "2026-07-30T01:00:04.000Z",
            cumulativeInput: 400, cumulativeOutput: 40,
            lastInput: 100, lastOutput: 10)

        write([
            codexSessionMeta(id: "root", ts: "2026-07-30T01:00:00.000Z"),
            first, second,
        ], to: dir, name: "root.jsonl")
        write([
            forkedSessionMeta(id: "child", parentID: "root", ts: "2026-07-30T02:00:00.000Z"),
            codexSessionMeta(id: "root", ts: "2026-07-30T02:00:00.001Z"),
            first, second, third,
        ], to: dir, name: "child.jsonl")
        write([
            forkedSessionMeta(id: "grandchild", parentID: "child", ts: "2026-07-30T03:00:00.000Z"),
            codexSessionMeta(id: "child", ts: "2026-07-30T03:00:00.001Z"),
            first, second, third, fourth,
        ], to: dir, name: "grandchild.jsonl")

        let entries = LocalUsageReader.codexEntries(modifiedSince: .distantPast, root: dir)

        XCTAssertEqual(entries.map(\.total), [110, 110, 110, 110])
        XCTAssertEqual(entries.filter { $0.id.hasPrefix("codex|root|") }.count, 2)
        XCTAssertEqual(entries.filter { $0.id.hasPrefix("codex|child|") }.count, 1)
        XCTAssertEqual(entries.filter { $0.id.hasPrefix("codex|grandchild|") }.count, 1)
    }

    func testCodexSiblingForksWithIdenticalOwnUsageKeepDistinctIDs() {
        let dir = tempDir()
        let replay = codexStateLine(
            ts: "2026-07-30T01:00:01.000Z",
            cumulativeInput: 100, cumulativeOutput: 10,
            lastInput: 100, lastOutput: 10)
        let own = codexStateLine(
            ts: "2026-07-30T02:00:01.000Z",
            cumulativeInput: 200, cumulativeOutput: 20,
            lastInput: 100, lastOutput: 10)
        write([
            codexSessionMeta(id: "root", ts: "2026-07-30T01:00:00.000Z"),
            replay,
        ], to: dir, name: "root.jsonl")
        for childID in ["left", "right"] {
            write([
                forkedSessionMeta(id: childID, parentID: "root", ts: "2026-07-30T02:00:00.000Z"),
                codexSessionMeta(id: "root", ts: "2026-07-30T02:00:00.001Z"),
                replay, own,
            ], to: dir, name: "\(childID).jsonl")
        }

        let entries = LocalUsageReader.codexEntries(modifiedSince: .distantPast, root: dir)

        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(Set(entries.map(\.id)).count, 3)
        XCTAssertEqual(entries.filter { $0.id.hasPrefix("codex|left|") }.count, 1)
        XCTAssertEqual(entries.filter { $0.id.hasPrefix("codex|right|") }.count, 1)
    }

    func testCodexCumulativeResetStartsNewCanonicalEpoch() {
        let dir = tempDir()
        write([
            codexSessionMeta(id: "session-a", ts: "2026-07-30T01:00:00.000Z"),
            codexStateLine(
                ts: "2026-07-30T01:00:01.000Z",
                cumulativeInput: 100, cumulativeOutput: 10,
                lastInput: 100, lastOutput: 10),
            codexStateLine(
                ts: "2026-07-30T01:00:02.000Z",
                cumulativeInput: 10, cumulativeOutput: 1,
                lastInput: 10, lastOutput: 1),
        ], to: dir)

        let entries = LocalUsageReader.codexEntries(modifiedSince: .distantPast, root: dir)

        XCTAssertEqual(entries.count, 2)
        XCTAssertTrue(entries[0].id.hasPrefix("codex|session-a|0|"))
        XCTAssertTrue(entries[1].id.hasPrefix("codex|session-a|1|"))
    }

    func testCodexCanonicalIDCollapsesSameSessionStateAcrossFilesKeepingEarliestDate() {
        let dir = tempDir()
        for (name, timestamp) in [
            ("later.jsonl", "2026-07-30T02:00:00.000Z"),
            ("earlier.jsonl", "2026-07-30T01:00:00.000Z"),
        ] {
            write([
                codexSessionMeta(id: "session-a", ts: timestamp),
                codexStateLine(
                    ts: timestamp,
                    cumulativeInput: 100, cumulativeOutput: 10,
                    lastInput: 100, lastOutput: 10),
            ], to: dir, name: name)
        }

        let entries = LocalUsageReader.codexEntries(modifiedSince: .distantPast, root: dir)

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].date, ISO8601Parser.date(from: "2026-07-30T01:00:00.000Z"))
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
