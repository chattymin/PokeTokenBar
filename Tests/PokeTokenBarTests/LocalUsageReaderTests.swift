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

    func testCodexParsing() {
        let dir = tempDir()
        let line = """
        {"type":"event_msg","timestamp":"2026-06-30T11:00:00.000Z","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":1000,"cached_input_tokens":200,"output_tokens":50,"reasoning_output_tokens":10,"total_tokens":1050}}}}
        """
        write([line], to: dir, name: "rollout-x.jsonl", sub: "2026/06/30")
        let entries = LocalUsageReader.codexEntries(modifiedSince: .distantPast, root: dir)
        XCTAssertEqual(entries.count, 1)
        let e = entries[0]
        XCTAssertEqual(e.input, 800)       // 1000 - 200
        XCTAssertEqual(e.cacheRead, 200)
        XCTAssertEqual(e.output, 50)
        XCTAssertEqual(e.cacheWrite, 0)
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
}
