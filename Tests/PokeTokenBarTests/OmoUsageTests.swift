import XCTest
@testable import PokeTokenBar

final class OmoUsageTests: XCTestCase {
    private var root: URL!
    private var cacheFile: URL!

    override func setUpWithError() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("ptb-omo-\(UUID().uuidString)")
        root = base.appendingPathComponent("sessions")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("-Users-x-Proj"), withIntermediateDirectories: true)
        cacheFile = base.appendingPathComponent("usage-cache.json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
    }

    func testParseAssistantToolResultAndEnvelopeUsage() throws {
        let jsonl = """
        {"type":"session","version":3,"id":"s1","timestamp":"2026-07-03T01:00:00.000Z","cwd":"/Users/x/Proj"}
        {"type":"message","id":"u1","timestamp":"2026-07-03T01:00:05.000Z","message":{"role":"user","content":"hi"}}
        {"type":"message","id":"a1","timestamp":"2026-07-03T01:00:10.000Z","message":{"role":"assistant","model":"grok-4.7","provider":"xai","stopReason":"stop","usage":{"input":100,"output":20,"cacheRead":30,"cacheWrite":4,"cacheWrite1h":6,"reasoning":8,"totalTokens":160,"cost":{"total":0.05}}}}
        {"type":"message","id":"t1","timestamp":"2026-07-03T01:00:12.000Z","message":{"role":"toolResult","toolName":"bash","usage":{"input":3,"output":1,"cacheRead":0,"cacheWrite":0,"totalTokens":4,"cost":{"total":0}}}}
        {"type":"message","id":"a2","timestamp":"2026-07-03T01:00:20.000Z","message":{"role":"assistant","stopReason":"aborted","usage":{"input":9,"output":1,"cacheRead":0,"cacheWrite":0}}}
        {"type":"message","id":"a3","timestamp":"2026-07-03T01:00:21.000Z","message":{"role":"assistant","stopReason":"error","usage":{"input":9,"output":1,"cacheRead":0,"cacheWrite":0}}}
        {"type":"compaction","id":"c1","timestamp":"2026-07-03T01:00:30.000Z","usage":{"input":40,"output":6,"cacheRead":0,"cacheWrite":0,"totalTokens":46,"cost":{"total":0.01}}}
        {"type":"branch_summary","id":"b1","timestamp":"2026-07-03T01:00:40.000Z","usage":{"totalTokens":7}}
        """
        let url = root.appendingPathComponent("-Users-x-Proj/session.jsonl")
        try jsonl.write(to: url, atomically: true, encoding: .utf8)
        let entries = try XCTUnwrap(LocalUsageReader.parseOmoFile(url, fmt: LocalUsageReader.localDayFormatter()))
        XCTAssertEqual(entries.count, 4, "assistant, toolResult, compaction, and total-only branch summary")

        let byID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id.components(separatedBy: "|").last!, $0) })
        let assistant = try XCTUnwrap(byID["a1"])
        XCTAssertEqual(assistant.model, "grok-4.7")
        XCTAssertEqual(assistant.input, 100)
        XCTAssertEqual(assistant.output, 20, "reasoning is already inside output")
        XCTAssertEqual(assistant.cacheRead, 30)
        XCTAssertEqual(assistant.cacheWrite, 10, "cacheWrite1h is a separate bucket")
        XCTAssertEqual(assistant.total, 160)
        XCTAssertEqual(assistant.explicitCost, 0.05)
        XCTAssertEqual(assistant.costIsEstimate, true)

        let tool = try XCTUnwrap(byID["t1"])
        XCTAssertEqual(tool.total, 4)
        XCTAssertEqual(tool.explicitCost, 0, "an explicit zero is preserved")
        XCTAssertEqual(tool.model, "omo")

        let summary = try XCTUnwrap(byID["b1"])
        XCTAssertEqual([summary.input, summary.output, summary.cacheWrite, summary.cacheRead], [7, 0, 0, 0])
        XCTAssertEqual(summary.costUnavailable, true)
    }

    func testUnreadableFileYieldsNilAndDoesNotHideSiblings() throws {
        try Data([0xFF, 0xFE, 0x41, 0x42]).write(to: root.appendingPathComponent("-Users-x-Proj/garbage.jsonl"))
        XCTAssertNil(LocalUsageReader.parseOmoFile(
            root.appendingPathComponent("-Users-x-Proj/garbage.jsonl"),
            fmt: LocalUsageReader.localDayFormatter()))
        try #"{"type":"message","id":"a1","timestamp":"2026-07-03T01:00:10.000Z","message":{"role":"assistant","usage":{"input":1,"output":1,"cacheRead":0,"cacheWrite":0}}}"#
            .write(to: root.appendingPathComponent("-Users-x-Proj/ok.jsonl"), atomically: true, encoding: .utf8)
        let entries = LocalUsageReader.omoEntries(modifiedSince: Date(timeIntervalSince1970: 0), roots: [root])
        XCTAssertEqual(entries.count, 1)
    }

    func testSubagentFileIsCountedAndIdsDoNotCollide() async throws {
        let session = root.appendingPathComponent("-Users-x-Proj/sess-a")
        let other = root.appendingPathComponent("-Users-x-Proj/sess-b")
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        let line = #"{"type":"message","id":"ad01","timestamp":"2026-07-03T01:02:00.000Z","message":{"role":"assistant","model":"grok-4.7","usage":{"input":7,"output":3,"cacheRead":0,"cacheWrite":0}}}"#
        try line.write(to: session.appendingPathComponent("__advisor.jsonl"), atomically: true, encoding: .utf8)
        try line.write(to: other.appendingPathComponent("__advisor.jsonl"), atomically: true, encoding: .utf8)

        let cache = LocalUsageCache(omoRoots: [root], fileURL: cacheFile)
        let entries = await cache.omoEntries(modifiedSince: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(entries.count, 2, "same entry id in two session files is not one turn")
        let again = await LocalUsageCache(omoRoots: [root], fileURL: cacheFile)
            .omoEntries(modifiedSince: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(again.count, 2, "disk snapshot round-trip")
    }

    func testAppendedLineInvalidatesTheBlob() async throws {
        let url = root.appendingPathComponent("-Users-x-Proj/grow.jsonl")
        let first = #"{"type":"message","id":"a1","timestamp":"2026-07-03T01:00:10.000Z","message":{"role":"assistant","usage":{"input":1,"output":1,"cacheRead":0,"cacheWrite":0}}}"#
        try first.write(to: url, atomically: true, encoding: .utf8)
        let cache = LocalUsageCache(omoRoots: [root], fileURL: cacheFile)
        let initial = await cache.omoEntries(modifiedSince: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(initial.count, 1)
        try ([first, #"{"type":"message","id":"a2","timestamp":"2026-07-03T01:00:20.000Z","message":{"role":"assistant","usage":{"input":2,"output":2,"cacheRead":0,"cacheWrite":0}}}"#] as [String])
            .joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        let appended = await LocalUsageCache(omoRoots: [root], fileURL: cacheFile)
            .omoEntries(modifiedSince: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(appended.count, 2)
    }

    func testCacheLoadsSnapshotWithoutOmoKey() async throws {
        let legacy = """
        {"claude":{},"codex":{},"codexSessionIDs":{},"gemini":{},"grok":{},"pi":{},"omp":{},
         "codexParserVersion":4,"codexSessionIndexVersion":2,"grokParserVersion":1,"piParserVersion":3,"ompParserVersion":2}
        """
        try legacy.write(to: cacheFile, atomically: true, encoding: .utf8)
        try #"{"type":"message","id":"a1","timestamp":"2026-07-03T01:00:10.000Z","message":{"role":"assistant","usage":{"input":4,"output":1,"cacheRead":0,"cacheWrite":0}}}"#
            .write(to: root.appendingPathComponent("-Users-x-Proj/s1.jsonl"), atomically: true, encoding: .utf8)
        let entries = await LocalUsageCache(omoRoots: [root], fileURL: cacheFile)
            .omoEntries(modifiedSince: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(entries.count, 1, "a snapshot from before omo support still loads")
    }

    func testRootsCoverBothDefaultsAndEnvOverridesWithoutPi() {
        let home = URL(fileURLWithPath: "/tmp/ptb-home")
        let roots = LocalUsageReader.computeOmoSessionRoots(
            omoAgentDirValue: "~/omo-agent",
            senpiAgentDirValue: " ",
            home: home)
        XCTAssertEqual(roots.map(\.path), [
            home.appendingPathComponent(".omo/agent/sessions").path,
            home.appendingPathComponent(".senpi/agent/sessions").path,
            URL(fileURLWithPath: NSString(string: "~/omo-agent").expandingTildeInPath)
                .appendingPathComponent("sessions").path,
        ])
        let collapsed = LocalUsageReader.computeOmoSessionRoots(
            omoAgentDirValue: home.appendingPathComponent(".omo/agent").path,
            senpiAgentDirValue: home.appendingPathComponent(".senpi/agent").path,
            home: home)
        XCTAssertEqual(collapsed.count, 2, "env overrides that repeat a default root collapse")
        XCTAssertFalse(collapsed.contains { $0.path.contains("/.pi/") })
    }

    func testProviderFetchDailyForwardsModelsAndKeepsEstimate() async throws {
        let iso = Self.isoUTC.string(from: Date())
        let jsonl = """
        {"type":"message","id":"m1","timestamp":"\(iso)","message":{"role":"assistant","model":"grok-4.7","usage":{"input":100,"output":20,"cacheRead":0,"cacheWrite":0,"totalTokens":120,"cost":{"total":0.01}}}}
        {"type":"message","id":"m2","timestamp":"\(iso)","message":{"role":"assistant","model":"grok-4.20","usage":{"input":10,"output":5,"cacheRead":0,"cacheWrite":0,"totalTokens":15,"cost":{"total":0.002}}}}
        """
        try jsonl.write(to: root.appendingPathComponent("-Users-x-Proj/today.jsonl"),
                        atomically: true, encoding: .utf8)
        let provider = LocalOmoProvider(cache: LocalUsageCache(omoRoots: [root], fileURL: cacheFile))
        let fetched = try await provider.fetchDaily()
        let daily = try XCTUnwrap(fetched)
        XCTAssertEqual(daily.totalTokens, 135)
        XCTAssertEqual(daily.totalCost, 0.012, accuracy: 1e-9)
        XCTAssertEqual(daily.costCoverage, .estimate)
        let models = try XCTUnwrap(daily.models)
        XCTAssertEqual(models["grok-4.7"], 120)
        XCTAssertEqual(models["grok-4.20"], 15)
    }

    func testFetchDailyIsNilWhenTheLogRootIsEmpty() async throws {
        let provider = LocalOmoProvider(cache: LocalUsageCache(omoRoots: [root], fileURL: cacheFile))
        let daily = try await provider.fetchDaily()
        XCTAssertNil(daily, "no session files is no usage, not a read failure")
    }

    func testCuratedRootsMatchTheReaderDefaults() {
        let home = URL(fileURLWithPath: "/tmp/ptb-curated")
        let curated = Set(LocalUsageReader.computeOmoSessionRoots(
            omoAgentDirValue: nil, senpiAgentDirValue: nil, home: home).map(\.path))
        XCTAssertEqual(curated, Set([
            home.appendingPathComponent(".omo/agent/sessions").path,
            home.appendingPathComponent(".senpi/agent/sessions").path,
        ]))
    }

    func testSettingsCuratedRootsIncludeBothDefaults() {
        let paths = CustomScanRoots.curatedRoots(for: "omo").map(\.path)
        XCTAssertTrue(paths.contains { $0.hasSuffix("/.omo/agent/sessions") })
        XCTAssertTrue(paths.contains { $0.hasSuffix("/.senpi/agent/sessions") })
    }

    private static let isoUTC: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        return formatter
    }()
}
