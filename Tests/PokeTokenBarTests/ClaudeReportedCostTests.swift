import XCTest
@testable import PokeTokenBar

/// Claude Code keeps its own cost ledger (`type:"cost-state"`) and prices models the local
/// table has no rate for — including context variants such as `claude-opus-5[1m]`. These cover
/// preferring that reported amount, and the attribution rules that keep a session total exact.
final class ClaudeReportedCostTests: XCTestCase {

    private func tempDir() -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("ptb-cost-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    private func assistant(id: String, model: String, ts: String,
                           input: Int = 0, output: Int = 0, cacheWrite: Int = 0, cacheRead: Int = 0) -> String {
        """
        {"type":"assistant","timestamp":"\(ts)","requestId":"r-\(id)","message":{"id":"\(id)",\
        "model":"\(model)","usage":{"input_tokens":\(input),"output_tokens":\(output),\
        "cache_creation_input_tokens":\(cacheWrite),"cache_read_input_tokens":\(cacheRead)}}}
        """
    }

    private func costState(_ models: [String: Double], unknown: Bool = false) -> String {
        let usage = models.map { "\"\($0.key)\":{\"costUSD\":\($0.value)}" }.joined(separator: ",")
        return "{\"type\":\"cost-state\",\"totalCostUSD\":\(models.values.reduce(0,+)),\"modelUsage\":{\(usage)},\"hasUnknownModelCost\":\(unknown)}"
    }

    private func parse(_ lines: [String]) -> [LocalUsageReader.Entry] {
        let dir = tempDir()
        let url = dir.appendingPathComponent("s.jsonl")
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return LocalUsageReader.parseClaudeFile(url, fmt: LocalUsageReader.localDayFormatter())
    }

    private func bucket(_ entries: [LocalUsageReader.Entry]) -> LocalUsageReader.Bucket {
        var b = LocalUsageReader.Bucket()
        for e in entries { b.add(e) }
        return b
    }

    func testIncrementalAppendReattributesTheWholeSessionToLatestLedger() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("session.jsonl")
        let model = "claude-future-unpriced-model"
        let first = assistant(id: "a", model: model, ts: "2026-09-15T10:00:00.000Z", input: 10)
        let prefix = first + "\n" + costState([model: 1]) + "\n"
        try prefix.write(to: url, atomically: true, encoding: .utf8)
        let cache = LocalUsageCache(claudeRoot: dir, fileURL: dir.appendingPathComponent("cache.json"))
        let initial = await cache.claudeEntries(modifiedSince: .distantPast)
        XCTAssertEqual(bucket(initial).cost, 1, accuracy: 1e-9)

        let next = assistant(id: "b", model: model, ts: "2026-09-16T10:00:00.000Z", input: 10)
        try (prefix + next + "\n" + costState([model: 9]) + "\n")
            .write(to: url, atomically: true, encoding: .utf8)
        let appended = await cache.claudeEntries(modifiedSince: .distantPast)
        XCTAssertEqual(appended.count, 2)
        XCTAssertEqual(bucket(appended).cost, 9, accuracy: 1e-9)
        XCTAssertTrue(appended.allSatisfy { $0.explicitCost == 4.5 && $0.sessionID == "session" })

        let unchanged = await cache.claudeEntries(modifiedSince: .distantPast)
        XCTAssertEqual(bucket(unchanged).cost, 9, accuracy: 1e-9)
        XCTAssertTrue(unchanged.allSatisfy { $0.explicitCost == 4.5 })
    }

    func testPersistedLedgerIsRetainedWhenTheAppendedTailHasNoLedger() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("session.jsonl")
        let cacheURL = dir.appendingPathComponent("cache.json")
        let model = "claude-future-unpriced-model"
        let prefix = assistant(id: "a", model: model, ts: "2026-09-15T10:00:00.000Z", input: 10)
            + "\n" + costState([model: 4]) + "\n"
        try prefix.write(to: url, atomically: true, encoding: .utf8)
        let cache = LocalUsageCache(claudeRoot: dir, fileURL: cacheURL)
        _ = await cache.claudeEntries(modifiedSince: .distantPast)

        let reloaded = LocalUsageCache(claudeRoot: dir, fileURL: cacheURL)
        let next = assistant(id: "b", model: model, ts: "2026-09-16T10:00:00.000Z", input: 10)
        try (prefix + next + "\n").write(to: url, atomically: true, encoding: .utf8)
        let entries = await reloaded.claudeEntries(modifiedSince: .distantPast)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(bucket(entries).cost, 4, accuracy: 1e-9)
        XCTAssertTrue(entries.allSatisfy { $0.explicitCost == 2 })
    }

    func testTruncationDiscardsTheCachedLedger() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("session.jsonl")
        let model = "claude-future-unpriced-model"
        let line = assistant(id: "a", model: model, ts: "2026-09-15T10:00:00.000Z", input: 10)
        try (line + "\n" + costState([model: 9]) + "\n")
            .write(to: url, atomically: true, encoding: .utf8)
        let cache = LocalUsageCache(claudeRoot: dir, fileURL: dir.appendingPathComponent("cache.json"))
        _ = await cache.claudeEntries(modifiedSince: .distantPast)

        try (line + "\n").write(to: url, atomically: true, encoding: .utf8)
        let entries = await cache.claudeEntries(modifiedSince: .distantPast)
        XCTAssertEqual(entries.count, 1)
        XCTAssertNil(entries.first?.explicitCost)
        XCTAssertTrue(bucket(entries).costCoverage.unknown)
    }

    func testHalfWrittenCostStateIsRetriedOnAppend() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("session.jsonl")
        let model = "claude-future-unpriced-model"
        let prefix = assistant(id: "a", model: model, ts: "2026-09-15T10:00:00.000Z", input: 10) + "\n"
        let ledger = costState([model: 9])
        try (prefix + ledger.prefix(ledger.count / 2)).write(to: url, atomically: true, encoding: .utf8)
        let cache = LocalUsageCache(claudeRoot: dir, fileURL: dir.appendingPathComponent("cache.json"))
        let initial = await cache.claudeEntries(modifiedSince: .distantPast)
        XCTAssertNil(initial.first?.explicitCost)

        try (prefix + ledger + "\n").write(to: url, atomically: true, encoding: .utf8)
        let completed = await cache.claudeEntries(modifiedSince: .distantPast)
        XCTAssertEqual(bucket(completed).cost, 9, accuracy: 1e-9)
        XCTAssertEqual(completed.count, 1)
    }

    /// The regression: a model with no price-table rate used to aggregate as unavailable ("$—")
    /// even though Claude had already priced it in the same file.
    func testUnpricedModelUsesReportedCost() {
        let model = "claude-future-unpriced-model"
        XCTAssertNil(ModelPricing.estimatedCost(model: model, input: 10, output: 10,
                                                cacheWrite: 0, cacheRead: 0),
                     "precondition: the table has no rate for the fixture model")

        let entries = parse([
            assistant(id: "a", model: model, ts: "2026-09-15T10:00:00.000Z", input: 100, output: 50),
            costState(["\(model)[1m]": 12.5]),
        ])
        let b = bucket(entries)

        XCTAssertEqual(b.cost, 12.5, accuracy: 1e-9)
        XCTAssertTrue(b.costCoverage.reported)
        XCTAssertFalse(b.costCoverage.unknown)
    }

    /// `modelUsage` keys carry the context-window suffix; `message.model` never does.
    func testContextWindowVariantMatchesBaseModel() {
        let entries = parse([
            assistant(id: "a", model: "claude-opus-5", ts: "2026-09-15T10:00:00.000Z", input: 10, output: 10),
            costState(["claude-opus-5[1m]": 4, "claude-opus-5": 1]),
        ])
        XCTAssertEqual(bucket(entries).cost, 5, accuracy: 1e-9, "both variants pool onto the base id")
    }

    /// A reported amount wins over the table estimate for a model that *is* priced.
    func testReportedCostOverridesTableEstimate() throws {
        let model = "claude-haiku-4-5-20251001"
        let table = try XCTUnwrap(ModelPricing.estimatedCost(model: model, input: 1_000_000, output: 0,
                                                            cacheWrite: 0, cacheRead: 0))
        XCTAssertEqual(table, 1.0, accuracy: 1e-9, "precondition: table rate is $1/MTok input")

        let entries = parse([
            assistant(id: "a", model: model, ts: "2026-09-15T10:00:00.000Z", input: 1_000_000),
            costState([model: 7.25]),
        ])
        XCTAssertEqual(bucket(entries).cost, 7.25, accuracy: 1e-9)
    }

    /// The ledger is cumulative — only the final record describes the session.
    func testLastCostStateWins() {
        let entries = parse([
            assistant(id: "a", model: "claude-opus-5", ts: "2026-09-15T10:00:00.000Z", input: 10),
            costState(["claude-opus-5": 1]),
            assistant(id: "b", model: "claude-opus-5", ts: "2026-09-15T11:00:00.000Z", input: 10),
            costState(["claude-opus-5": 9]),
        ])
        XCTAssertEqual(bucket(entries).cost, 9, accuracy: 1e-9)
    }

    /// A session spanning a day boundary must split by tokens and still total exactly.
    /// The stamps sit 24h apart so the fixture straddles a local day in any timezone.
    func testCostSplitsAcrossDaysAndSumsExactly() {
        let entries = parse([
            assistant(id: "a", model: "claude-opus-5", ts: "2026-09-15T12:00:00.000Z", input: 300),
            assistant(id: "b", model: "claude-opus-5", ts: "2026-09-16T12:00:00.000Z", input: 100),
            costState(["claude-opus-5": 10]),
        ])
        XCTAssertEqual(entries.count, 2)

        let byDay = Dictionary(grouping: entries, by: \.localDay)
        XCTAssertEqual(byDay.count, 2, "fixture must straddle a local-day boundary")
        let total = entries.reduce(0.0) { $0 + ($1.explicitCost ?? 0) }
        XCTAssertEqual(total, 10, accuracy: 1e-9, "redistribution must not lose or invent money")

        let sorted = entries.sorted { $0.date < $1.date }
        XCTAssertEqual(sorted[0].explicitCost ?? 0, 7.5, accuracy: 1e-9, "300 of 400 tokens")
        XCTAssertEqual(sorted[1].explicitCost ?? 0, 2.5, accuracy: 1e-9, "100 of 400 tokens")
    }

    /// Cost for a model that produced no parsed entry is dropped, never moved onto another model.
    func testUnattributableModelCostIsNotReassigned() {
        let entries = parse([
            assistant(id: "a", model: "claude-opus-5", ts: "2026-09-15T10:00:00.000Z", input: 100),
            costState(["claude-opus-5": 2, "claude-haiku-4-5-20251001": 98]),
        ])
        XCTAssertEqual(bucket(entries).cost, 2, accuracy: 1e-9)
    }

    /// Without a ledger the previous behaviour stands: table estimate, or unavailable.
    func testNoCostStateFallsBackToTable() {
        let priced = parse([
            assistant(id: "a", model: "claude-haiku-4-5-20251001", ts: "2026-09-15T10:00:00.000Z", input: 1_000_000),
        ])
        let pb = bucket(priced)
        XCTAssertEqual(pb.cost, 1.0, accuracy: 1e-9)
        XCTAssertTrue(pb.costCoverage.estimated)

        let unpriced = parse([
            assistant(id: "a", model: "claude-future-unpriced-model", ts: "2026-09-15T10:00:00.000Z", input: 1_000_000),
        ])
        let ub = bucket(unpriced)
        XCTAssertEqual(ub.cost, 0)
        XCTAssertTrue(ub.costCoverage.unknown)
    }

    /// Zero-token records must not claim a share and strand the money on them.
    func testZeroTokenEntriesDoNotAbsorbCost() {
        let entries = parse([
            assistant(id: "a", model: "claude-opus-5", ts: "2026-09-15T10:00:00.000Z"),
            assistant(id: "b", model: "claude-opus-5", ts: "2026-09-15T10:05:00.000Z", input: 500),
            costState(["claude-opus-5": 6]),
        ])
        XCTAssertEqual(bucket(entries).cost, 6, accuracy: 1e-9)
    }
}
