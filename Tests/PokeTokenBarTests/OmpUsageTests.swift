import XCTest
@testable import PokeTokenBar

/// omp (oh-my-pi) session parsing — assistant usage summing, source-cost trust, recursive scan.
final class OmpUsageTests: XCTestCase {
    private var root: URL!
    private var cacheFile: URL!

    override func setUpWithError() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("ptb-omp-\(UUID().uuidString)")
        root = base.appendingPathComponent("sessions")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("-Users-x-Proj"), withIntermediateDirectories: true)
        cacheFile = base.appendingPathComponent("usage-cache.json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
    }

    private let sessionJSONL = """
    {"type":"session","version":3,"id":"019f9552","timestamp":"2026-07-03T01:00:00.000Z","cwd":"/Users/x/Proj"}
    {"type":"model_change","id":"aa01","parentId":null,"timestamp":"2026-07-03T01:00:01.000Z","model":"modal-k3/moonshotai/Kimi-K3"}
    {"type":"message","id":"bb01","parentId":"aa01","timestamp":"2026-07-03T01:00:05.000Z","message":{"role":"user","content":[{"type":"text","text":"hi"}]}}
    {"type":"message","id":"cc01","parentId":"bb01","timestamp":"2026-07-03T01:00:10.000Z","message":{"role":"assistant","content":[{"type":"text","text":"hello"}],"model":"moonshotai/Kimi-K3","usage":{"input":100,"output":10,"cacheRead":600,"cacheWrite":40,"totalTokens":750,"cost":{"input":0.001,"output":0.002,"cacheRead":0.002,"cacheWrite":0.0,"total":0.005}}}}
    {"type":"message","id":"dd01","parentId":"cc01","timestamp":"2026-07-03T01:00:12.000Z","message":{"role":"toolResult","toolCallId":"t1","content":[{"type":"text","text":"ok"}]}}
    {"type":"message","id":"ee01","parentId":"dd01","timestamp":"2026-07-03T01:01:00.000Z","message":{"role":"assistant","content":[],"model":"modal/nvidia/GLM-5.2","usage":{"input":5,"output":7,"cacheRead":0,"cacheWrite":3,"totalTokens":15,"cost":{"input":0,"output":0,"cacheRead":0,"cacheWrite":0,"total":0}}}}
    {"type":"custom","customType":"tool_execution_start","timestamp":"2026-07-03T01:01:05.000Z"}
    """

    /// Only assistant usage lines are collected — 4-way token mapping + total identity + cost.total trust rule.
    func testParseAssistantUsageMapping() throws {
        let url = root.appendingPathComponent("-Users-x-Proj/2026-07-03T01-00-00-000Z_019f9552.jsonl")
        try sessionJSONL.write(to: url, atomically: true, encoding: .utf8)
        let entries = try XCTUnwrap(LocalUsageReader.parseOmpFile(url, fmt: LocalUsageReader.localDayFormatter()))
        XCTAssertEqual(entries.count, 2, "2 assistant events with usage (user/toolResult/custom excluded)")

        let byMsg = Dictionary(uniqueKeysWithValues: entries.map { ($0.id.components(separatedBy: "|").last!, $0) })
        let cc = try XCTUnwrap(byMsg["cc01"])
        XCTAssertEqual(cc.model, "moonshotai/Kimi-K3")
        XCTAssertEqual(cc.input, 100)
        XCTAssertEqual(cc.cacheRead, 600)
        XCTAssertEqual(cc.cacheWrite, 40)
        XCTAssertEqual(cc.output, 10)
        XCTAssertEqual(cc.total, 750, "Entry.total preserves usage.totalTokens")
        XCTAssertEqual(cc.explicitCost, 0.005, "source-persisted charge wins over the price table")

        let ee = try XCTUnwrap(byMsg["ee01"])
        XCTAssertEqual(ee.model, "modal/nvidia/GLM-5.2")
        XCTAssertEqual(ee.total, 15)
        XCTAssertNil(ee.explicitCost, "a free/unknown model's 0 cost is not trusted (falls back to the price table)")
    }

    /// Lines mentioning usage that are not billable events, broken JSON, compaction with null
    /// usage, aborted/error turns, and missing required fields yield nothing.
    func testSkipsNonAssistantAndMalformedLines() throws {
        let tricky = """
        {"type":"message","id":"u1","timestamp":"2026-07-03T01:00:05.000Z","message":{"role":"user","content":[{"type":"text","text":"what is my usage?"}]}}
        {"type":"message","id":"a1","timestamp":"2026-07-03T01:00:10.000Z","message":{"role":"assistant","content":[],"model":"m"}}
        {"type":"message","id":"a2","message":{"role":"assistant","usage":{"input":1,"output":1,"cacheRead":0,"cacheWrite":0}}}
        {"type":"message","id":"a3","timestamp":"2026-07-03T01:00:20.000Z","message":{"role":"assistant","stopReason":"aborted","usage":{"input":9,"output":1,"cacheRead":0,"cacheWrite":0}}}
        {"type":"compaction","id":"cp1","timestamp":"2026-07-03T01:00:30.000Z","usage":null}
        {"type":"message","id":"a4","timestamp":"2026-07-03T01:00:40.000Z","message":{"role":"assistant","usage":{"input":1,
        """
        let url = root.appendingPathComponent("-Users-x-Proj/broken.jsonl")
        try tricky.write(to: url, atomically: true, encoding: .utf8)
        let entries = LocalUsageReader.parseOmpFile(url, fmt: LocalUsageReader.localDayFormatter()) ?? []
        XCTAssertTrue(entries.isEmpty)
    }

    /// An unreadable file (broken encoding) returns nil — the failure is not cached, so the next refresh retries.
    func testUnreadableFileYieldsNothing() throws {
        let url = root.appendingPathComponent("-Users-x-Proj/garbage.jsonl")
        try Data([0xFF, 0xFE, 0x41, 0x42]).write(to: url)
        XCTAssertNil(LocalUsageReader.parseOmpFile(url, fmt: LocalUsageReader.localDayFormatter()))
    }

    /// A usage line without a message id still counts (falls back to a generated id).
    func testAssistantLineWithoutIdStillCounts() throws {
        let line = #"{"type":"message","timestamp":"2026-07-03T01:00:10.000Z","message":{"role":"assistant","usage":{"input":10,"output":5,"cacheRead":0,"cacheWrite":0}}}"#
        let url = root.appendingPathComponent("-Users-x-Proj/noid.jsonl")
        try line.write(to: url, atomically: true, encoding: .utf8)
        let entries = try XCTUnwrap(LocalUsageReader.parseOmpFile(url, fmt: LocalUsageReader.localDayFormatter()))
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.total, 15)
        XCTAssertTrue(entries.first?.id.hasPrefix("omp|noid.jsonl|") ?? false)
    }

    /// Same-file duplicate lines count once (keep-max).
    func testDuplicateLinesWithinFileDedup() throws {
        let line = #"{"type":"message","id":"cc01","timestamp":"2026-07-03T01:00:10.000Z","message":{"role":"assistant","usage":{"input":10,"output":5,"cacheRead":0,"cacheWrite":0}}}"#
        let url = root.appendingPathComponent("-Users-x-Proj/dup.jsonl")
        try ([line, line] as [String]).joined(separator: "\n")
            .write(to: url, atomically: true, encoding: .utf8)
        let entries = try XCTUnwrap(LocalUsageReader.parseOmpFile(url, fmt: LocalUsageReader.localDayFormatter()))
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.total, 15)
    }

    /// `branch_summary` envelope usage is a billed model call and counts (compaction/branch_summary mirror `parsePiFile`).
    func testBranchSummaryEnvelopeUsageCounts() throws {
        let line = """
        {"type":"branch_summary","id":"bs01","timestamp":"2026-07-03T01:04:00.000Z","usage":{"input":40,"output":6,"cacheRead":0,"cacheWrite":0,"totalTokens":46,"cost":{"input":0,"output":0,"cacheRead":0,"cacheWrite":0,"total":0}}}
        """
        let url = root.appendingPathComponent("-Users-x-Proj/branch.jsonl")
        try line.write(to: url, atomically: true, encoding: .utf8)
        let entries = try XCTUnwrap(LocalUsageReader.parseOmpFile(url, fmt: LocalUsageReader.localDayFormatter()))
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.total, 46)
        XCTAssertEqual(entries.first?.model, "omp", "envelope usage carries no model")
    }

    /// Partial granular usage defaults the missing buckets to 0 (granular wins whenever any key is present).
    func testPartialGranularUsageDefaultsMissingBuckets() throws {
        let line = #"{"type":"message","id":"pg01","timestamp":"2026-07-03T01:05:00.000Z","message":{"role":"assistant","usage":{"input":7}}}"#
        let url = root.appendingPathComponent("-Users-x-Proj/partial.jsonl")
        try line.write(to: url, atomically: true, encoding: .utf8)
        let entries = try XCTUnwrap(LocalUsageReader.parseOmpFile(url, fmt: LocalUsageReader.localDayFormatter()))
        XCTAssertEqual(entries.count, 1)
        let e = try XCTUnwrap(entries.first)
        XCTAssertEqual(e.input, 7)
        XCTAssertEqual(e.output + e.cacheWrite + e.cacheRead, 0)
    }

    /// A usage object with only totalTokens has no recoverable split — the aggregate survives as input (mirrors `piEntry`).
    func testTotalTokenOnlyUsageIsPreservedAsInput() throws {
        let line = #"{"type":"message","id":"tt01","timestamp":"2026-07-03T01:06:00.000Z","message":{"role":"assistant","usage":{"totalTokens":42}}}"#
        let url = root.appendingPathComponent("-Users-x-Proj/totalonly.jsonl")
        try line.write(to: url, atomically: true, encoding: .utf8)
        let entries = try XCTUnwrap(LocalUsageReader.parseOmpFile(url, fmt: LocalUsageReader.localDayFormatter()))
        XCTAssertEqual(entries.count, 1)
        let e = try XCTUnwrap(entries.first)
        XCTAssertEqual([e.input, e.output, e.cacheWrite, e.cacheRead], [42, 0, 0, 0])
    }

    /// An unreadable file inside a scanned root contributes nothing and does not poison the other files' parse.
    func testUnreadableFileInsideScannedRootIsSkipped() throws {
        try sessionJSONL.write(to: root.appendingPathComponent("-Users-x-Proj/ok.jsonl"),
                               atomically: true, encoding: .utf8)
        try Data([0xFF, 0xFE, 0x41, 0x42]).write(to: root.appendingPathComponent("-Users-x-Proj/garbage.jsonl"))
        let entries = LocalUsageReader.ompEntries(modifiedSince: Date(timeIntervalSince1970: 0), roots: [root])
        XCTAssertEqual(entries.count, 2)
    }

    /// Subagent sessions (`<id>/__advisor.jsonl`) are picked up by the recursive scan, and the (path,mtime,size) cache round-trips.
    func testCacheRecursesIntoSubagentSessionsAndRoundTrips() async throws {
        let sub = root.appendingPathComponent("-Users-x-Proj/2026-07-03T01-00-00-000Z_019f9552")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try sessionJSONL.write(to: root.appendingPathComponent("-Users-x-Proj/2026-07-03T01-00-00-000Z_019f9552.jsonl"),
                               atomically: true, encoding: .utf8)
        let advisor = """
        {"type":"message","id":"ad01","timestamp":"2026-07-03T01:02:00.000Z","message":{"role":"assistant","usage":{"input":7,"output":3,"cacheRead":0,"cacheWrite":0}}}
        """
        try advisor.write(to: sub.appendingPathComponent("__advisor.jsonl"), atomically: true, encoding: .utf8)

        let cache = LocalUsageCache(ompRoots: [root], fileURL: cacheFile)
        let entries = await cache.ompEntries(modifiedSince: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(entries.count, 3, "2 parent + 1 subagent")
        XCTAssertEqual(entries.map(\.total).reduce(0, +), 750 + 15 + 10)

        let again = await LocalUsageCache(ompRoots: [root], fileURL: cacheFile)
            .ompEntries(modifiedSince: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(again.count, 3, "identical after disk snapshot round-trip")
    }

    /// Conversion copies under `bridge/` are excluded in both paths (reader and cache) — the original is already aggregated elsewhere.
    func testBridgeDirectoryIsExcluded() async throws {
        let line = """
        {"type":"message","id":"br01","timestamp":"2026-07-03T01:03:00.000Z","message":{"role":"assistant","usage":{"input":9,"output":1,"cacheRead":0,"cacheWrite":0}}}
        """
        try sessionJSONL.write(to: root.appendingPathComponent("-Users-x-Proj/s3.jsonl"),
                               atomically: true, encoding: .utf8)
        let bridge = root.appendingPathComponent("bridge")
        try FileManager.default.createDirectory(at: bridge, withIntermediateDirectories: true)
        try line.write(to: bridge.appendingPathComponent("converted.jsonl"), atomically: true, encoding: .utf8)

        let direct = LocalUsageReader.ompEntries(modifiedSince: Date(timeIntervalSince1970: 0), roots: [root])
        XCTAssertEqual(direct.count, 2, "reader scan: bridge copy excluded")

        let cached = await LocalUsageCache(ompRoots: [root], fileURL: cacheFile)
            .ompEntries(modifiedSince: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(cached.count, 2, "cache (production) scan: bridge copy excluded")
    }

    /// A legacy snapshot without the omp key still loads, so the cold start does not recur.
    func testCacheLoadsSnapshotWithoutOmpKey() async throws {
        let legacy = """
        {"claude":{},"codex":{},"codexSessionIDs":{},"gemini":{},"grok":{},"pi":{},
         "codexParserVersion":4,"codexSessionIndexVersion":2,"grokParserVersion":1,"piParserVersion":2}
        """
        try legacy.write(to: cacheFile, atomically: true, encoding: .utf8)
        try sessionJSONL.write(to: root.appendingPathComponent("-Users-x-Proj/s1.jsonl"),
                               atomically: true, encoding: .utf8)
        let entries = await LocalUsageCache(ompRoots: [root], fileURL: cacheFile)
            .ompEntries(modifiedSince: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(entries.count, 2, "fresh parse proceeds from a snapshot missing the omp key")
    }

    /// Source cost wins over the price table (unknown model = 0) — reflected as-is in the daily total.
    func testDailyPrefersSourceCostForUnknownModel() throws {
        let url = root.appendingPathComponent("-Users-x-Proj/s2.jsonl")
        try sessionJSONL.write(to: url, atomically: true, encoding: .utf8)
        let entries = try XCTUnwrap(LocalUsageReader.parseOmpFile(url, fmt: LocalUsageReader.localDayFormatter()))
        let day = try XCTUnwrap(entries.first?.localDay)
        let daily = try XCTUnwrap(LocalUsageReader.daily(entries: entries, localDay: day))
        XCTAssertEqual(daily.totalTokens, 765)
        XCTAssertEqual(daily.totalCost, 0.005, accuracy: 1e-12)
    }

    func testPrintRealOmpAggregate() throws {
        guard ProcessInfo.processInfo.environment["PTB_PARITY"] == "1" else {
            throw XCTSkip("set PTB_PARITY=1 for the local omp smoke test")
        }
        let sessionsRoots = LocalUsageReader.ompSessionRoots
        guard sessionsRoots.contains(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            throw XCTSkip("no omp sessions on this machine")
        }
        let entries = LocalUsageReader.ompEntries(
            modifiedSince: LocalUsageReader.startOfMonth(Date()), roots: sessionsRoots)
        XCTAssertFalse(entries.isEmpty)
        let today = LocalUsageReader.todayKey()
        let todayTotal = entries.filter { $0.localDay == today }.reduce(0) { $0 + $1.total }
        print("OMP_NATIVE_PARITY entries=\(entries.count) today=\(todayTotal) month=\(entries.reduce(0) { $0 + $1.total })")
    }
}
