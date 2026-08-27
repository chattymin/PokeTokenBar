import XCTest
@testable import PokeTokenBar

final class OllamaUsageTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PokeTokenBar-OllamaUsageTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        directory = nil
    }

    func testReadsProxyLedgerAndPreservesExactReportedTotal() throws {
        let timestamp = "2026-08-25T16:45:00Z"
        let date = try XCTUnwrap(ISO8601Parser.date(from: timestamp))
        let day = LocalUsageReader.localDayFormatter().string(from: date)
        let ledger = directory.appendingPathComponent("\(day).jsonl")
        let contents = """
        {"ts":"\(timestamp)","source":"ollama","endpoint":"/api/chat","model":"qwen3.6:35b","prompt_tokens":100,"completion_tokens":25,"total_tokens":130}
        {"ts":"\(timestamp)","source":"ollama","endpoint":"/api/embed","model":"qwen3-embedding:0.6b","prompt_tokens":7,"completion_tokens":0,"total_tokens":7}
        not-json

        """
        try contents.write(to: ledger, atomically: true, encoding: .utf8)

        let entries = LocalOllamaUsageReader.entries(
            modifiedSince: date.addingTimeInterval(-1), roots: [directory])

        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].input, 100)
        XCTAssertEqual(entries[0].output, 30, "a future/unclassified token class must not be dropped")
        XCTAssertEqual(entries[0].total, 130)
        XCTAssertEqual(entries[1].total, 7)
        let daily = try XCTUnwrap(LocalUsageReader.daily(entries: entries, localDay: day))
        XCTAssertEqual(daily.totalTokens, 137)
        XCTAssertEqual(daily.totalCost, 0)
    }

    func testExternalCountsAreClampedAndNullIsNotAValue() throws {
        let formatter = LocalUsageReader.localDayFormatter()
        let line = Data("""
        {"ts":"2026-08-25T16:45:00Z","model":"bad","prompt_tokens":null,"completion_tokens":1e30,"total_tokens":-4}
        """.utf8)

        let entry = try XCTUnwrap(LocalOllamaUsageReader.parse(
            line: line, file: "fixture", lineNumber: 1, formatter: formatter))

        XCTAssertEqual(entry.input, 0)
        XCTAssertEqual(entry.output, 1_000_000_000_000_000)
        XCTAssertEqual(entry.total, 1_000_000_000_000_000)
    }

    func testProviderIsTokenOnly() {
        let provider = LocalOllamaProvider()
        XCTAssertEqual(provider.id, "ollama")
        XCTAssertEqual(provider.displayName, "Ollama")
        XCTAssertFalse(provider.reportsCost)
    }
}
