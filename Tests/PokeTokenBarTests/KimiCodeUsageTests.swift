import XCTest
@testable import PokeTokenBar

/// Kimi Code `wire.jsonl` parsing (#386) — `usage.record` mapping, scope rules, fork dedup, roots.
final class KimiCodeUsageTests: XCTestCase {
    private var base: URL!
    private var root: URL!
    private var cacheFile: URL!

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory
            .appendingPathComponent("ptb-kimi-\(UUID().uuidString)")
        root = base.appendingPathComponent("sessions")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        cacheFile = base.appendingPathComponent("usage-cache.json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: base)
    }

    /// Writes `wire.jsonl` at the upstream layout `sessions/<workDirKey>/<sessionId>/agents/<agent>/`.
    @discardableResult
    private func writeWire(_ text: String, session: String = "ses_1", agent: String = "main") throws -> URL {
        let dir = root.appendingPathComponent("wd_proj_abc/\(session)/agents/\(agent)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("wire.jsonl")
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static func millis(_ date: Date) -> Int64 { Int64(date.timeIntervalSince1970 * 1000) }

    private static func record(model: String = "k3-agent", scope: String? = "turn", time: Int64,
                               input: Int = 100, output: Int = 20, read: Int = 500, write: Int = 30) -> String {
        let scopeField = scope.map { ",\"usageScope\":\"\($0)\"" } ?? ""
        return """
        {"type":"usage.record","model":"\(model)","usage":{"inputOther":\(input),"output":\(output),"inputCacheRead":\(read),"inputCacheCreation":\(write)}\(scopeField),"time":\(time)}
        """
    }

    /// Upstream fixture shape: 4-way bucket mapping, model, millisecond `time` → local day.
    func testParsesUsageRecordMapping() throws {
        let t: Int64 = 1_779_256_800_302
        let url = try writeWire("""
        {"type":"turn.begin","turnId":"t1","time":\(t - 10)}
        {"type":"usage.record","model":"kimi-k2","usage":{"inputOther":10,"output":5,"inputCacheRead":7,"inputCacheCreation":3},"usageScope":"turn","time":\(t)}
        """)
        let entries = try XCTUnwrap(LocalUsageReader.parseKimiWireFile(url, fmt: LocalUsageReader.localDayFormatter()))
        XCTAssertEqual(entries.count, 1)
        let e = try XCTUnwrap(entries.first)
        XCTAssertEqual(e.model, "kimi-k2")
        XCTAssertEqual(e.input, 10)
        XCTAssertEqual(e.output, 5)
        XCTAssertEqual(e.cacheRead, 7)
        XCTAssertEqual(e.cacheWrite, 3)
        XCTAssertEqual(e.total, 25)
        XCTAssertEqual(e.date, Date(timeIntervalSince1970: Double(t) / 1000))
        XCTAssertEqual(e.localDay, LocalUsageReader.localDayFormatter().string(from: e.date))
    }

    /// `turn` and `session` (requests outside a turn, e.g. compaction) are both per-request deltas;
    /// a record without a scope also counts. An unknown scope is skipped, not guessed.
    func testCountsTurnSessionAndMissingScopeSkipsUnknown() throws {
        let t: Int64 = 1_779_256_800_000
        let url = try writeWire([
            Self.record(scope: "turn", time: t),
            Self.record(scope: "session", time: t + 1),
            Self.record(scope: nil, time: t + 2),
            Self.record(scope: "cumulative", time: t + 3),
        ].joined(separator: "\n"))
        let entries = try XCTUnwrap(LocalUsageReader.parseKimiWireFile(url, fmt: LocalUsageReader.localDayFormatter()))
        XCTAssertEqual(entries.count, 3, "turn + session + scope-less; unknown scope skipped")
    }

    /// Non-usage lines that mention the record type, broken JSON, missing/zero time, and a missing
    /// usage object yield nothing. A missing model falls back to `kimi-code`.
    func testSkipsMalformedLinesAndDefaultsModel() throws {
        let t: Int64 = 1_779_256_800_000
        let url = try writeWire("""
        {"type":"message","text":"what is \\"usage.record\\"?","time":\(t)}
        {"type":"usage.record","usage":{"inputOther":1,"output":1},"usageScope":"turn"}
        {"type":"usage.record","usage":{"inputOther":1,"output":1},"usageScope":"turn","time":0}
        {"type":"usage.record","model":"k3-agent","usageScope":"turn","time":\(t)}
        {"type":"usage.record","model":"k3-agent","usage":{"inputOther":1,
        {"type":"usage.record","model":"","usage":{"inputOther":4,"output":2},"usageScope":"turn","time":\(t)}
        """)
        let entries = try XCTUnwrap(LocalUsageReader.parseKimiWireFile(url, fmt: LocalUsageReader.localDayFormatter()))
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.model, "kimi-code")
        XCTAssertEqual(entries.first?.total, 6)
    }

    /// A cache-only request (no `inputOther`/`output`) still counts; missing buckets default to 0.
    func testPartialUsageDefaultsMissingBuckets() throws {
        let url = try writeWire("""
        {"type":"usage.record","model":"k3-agent","usage":{"inputCacheRead":9},"usageScope":"turn","time":1779256800000}
        """)
        let e = try XCTUnwrap(LocalUsageReader.parseKimiWireFile(url, fmt: LocalUsageReader.localDayFormatter())?.first)
        XCTAssertEqual(e.input, 0)
        XCTAssertEqual(e.output, 0)
        XCTAssertEqual(e.cacheRead, 9)
        XCTAssertEqual(e.cacheWrite, 0)
    }

    /// Unreadable file → nil, so the failure is not cached and the next refresh retries.
    func testUnreadableFileYieldsNil() throws {
        let url = try writeWire("")
        try Data([0xFF, 0xFE, 0x41, 0x42]).write(to: url)
        XCTAssertNil(LocalUsageReader.parseKimiWireFile(url, fmt: LocalUsageReader.localDayFormatter()))
        XCTAssertTrue(LocalUsageReader.kimiEntries(modifiedSince: Date(timeIntervalSince1970: 0), roots: [root]).isEmpty,
                      "an unreadable wire file inside a scanned root is skipped, not fatal")
    }

    /// `/fork` copies a session's records into a new session directory. The content id folds the
    /// copy; the fork's own new request still counts. Subagent wire files are scanned too.
    func testForkCopyDedupsAndSubagentsCount() async throws {
        let t: Int64 = 1_779_256_800_000
        let original = [Self.record(time: t), Self.record(time: t + 1000, output: 40)]
        try writeWire(original.joined(separator: "\n"), session: "ses_orig")
        try writeWire((original + [Self.record(time: t + 5000, output: 7)]).joined(separator: "\n"),
                      session: "ses_fork")
        try writeWire(Self.record(model: "k2d6-agent", time: t + 2000), session: "ses_orig", agent: "sub_1")

        let direct = LocalUsageReader.kimiEntries(modifiedSince: Date(timeIntervalSince1970: 0), roots: [root])
        XCTAssertEqual(direct.count, 4, "2 original + 1 fork-only + 1 subagent; copied history folded")

        let cache = LocalUsageCache(kimiRoots: [root], fileURL: cacheFile)
        let cached = await cache.kimiEntries(modifiedSince: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(cached.count, 4, "cache (production) path dedups the same way")
        XCTAssertEqual(Set(cached.map(\.model)), ["k3-agent", "k2d6-agent"])
    }

    /// Only `wire.jsonl` counts — other jsonl under the session tree (e.g. state/context logs) is ignored.
    func testOnlyWireFilesAreScanned() async throws {
        let t: Int64 = 1_779_256_800_000
        try writeWire(Self.record(time: t))
        let other = root.appendingPathComponent("wd_proj_abc/ses_1/context.jsonl")
        try Self.record(time: t + 1).write(to: other, atomically: true, encoding: .utf8)

        let cached = await LocalUsageCache(kimiRoots: [root], fileURL: cacheFile)
            .kimiEntries(modifiedSince: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(cached.count, 1)
    }

    /// Blob cache round-trips through the disk snapshot, and an appended record is picked up.
    func testCacheRoundTripAndPicksUpAppendedRecord() async throws {
        let t: Int64 = 1_779_256_800_000
        let url = try writeWire(Self.record(time: t))
        let first = await LocalUsageCache(kimiRoots: [root], fileURL: cacheFile)
            .kimiEntries(modifiedSince: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(first.count, 1)

        let again = await LocalUsageCache(kimiRoots: [root], fileURL: cacheFile)
            .kimiEntries(modifiedSince: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(again.count, 1, "identical after disk snapshot round-trip")

        try [Self.record(time: t), Self.record(time: t + 1000, output: 1)]
            .joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        let appended = await LocalUsageCache(kimiRoots: [root], fileURL: cacheFile)
            .kimiEntries(modifiedSince: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(appended.count, 2, "size change invalidates the blob")
    }

    /// A snapshot written before Kimi support (no `kimi` key) still loads.
    func testCacheLoadsSnapshotWithoutKimiKey() async throws {
        let legacy = """
        {"claude":{},"codex":{},"codexSessionIDs":{},"gemini":{},"grok":{},"pi":{},"omp":{},
         "codexParserVersion":4,"codexSessionIndexVersion":2,"grokParserVersion":1,"piParserVersion":3,"ompParserVersion":2}
        """
        try legacy.write(to: cacheFile, atomically: true, encoding: .utf8)
        try writeWire(Self.record(time: 1_779_256_800_000))
        let entries = await LocalUsageCache(kimiRoots: [root], fileURL: cacheFile)
            .kimiEntries(modifiedSince: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(entries.count, 1)
    }

    /// CLI root, desktop runtime root, and `$KIMI_CODE_HOME` (tilde-expanded); blank env is ignored
    /// and a duplicate of a default root collapses.
    func testSessionRoots() {
        let home = URL(fileURLWithPath: "/Users/tester")
        let defaults = LocalUsageReader.computeKimiSessionRoots(homeValue: nil, home: home).map(\.path)
        XCTAssertEqual(defaults, [
            "/Users/tester/.kimi-code/sessions",
            "/Users/tester/Library/Application Support/kimi-desktop/daimon-share/daimon/runtime/kimi-code/home/sessions",
        ])
        XCTAssertEqual(LocalUsageReader.computeKimiSessionRoots(homeValue: "  ", home: home).map(\.path), defaults)
        XCTAssertEqual(
            LocalUsageReader.computeKimiSessionRoots(homeValue: "/opt/kimi", home: home).map(\.path),
            defaults + ["/opt/kimi/sessions"])
        XCTAssertEqual(
            LocalUsageReader.computeKimiSessionRoots(homeValue: "/Users/tester/.kimi-code", home: home).map(\.path),
            defaults, "env pointing at the default root does not double-scan")
    }

    /// Through the provider: today's records → daily total with a per-model breakdown. Kimi models
    /// are not in the price table and Kimi records no cost → cost is unavailable, not a measured $0.
    func testProviderFetchDailyBreakdownAndUnavailableCost() async throws {
        let now = Self.millis(Date())
        try writeWire([
            Self.record(model: "k3-agent", time: now - 2000, input: 100, output: 200, read: 0, write: 0),
            Self.record(model: "k2d6-agent", scope: "session", time: now - 1000,
                        input: 10, output: 20, read: 0, write: 0),
        ].joined(separator: "\n"))

        let provider = LocalKimiCodeProvider(cache: LocalUsageCache(kimiRoots: [root], fileURL: cacheFile))
        XCTAssertEqual(provider.id, "kimi_code")
        let fetched = try await provider.fetchDaily()
        let daily = try XCTUnwrap(fetched)
        XCTAssertEqual(daily.totalTokens, 330)
        XCTAssertEqual(daily.costCoverage, .unavailable)
        let models = try XCTUnwrap(daily.models)
        XCTAssertEqual(models["k3-agent"], 300)
        XCTAssertEqual(models["k2d6-agent"], 30)

        let enrichment = await provider.fetchEnrichment()
        XCTAssertTrue(enrichment.periodsOK)
        XCTAssertEqual(enrichment.monthTotal?.totalTokens, 330)
    }

    /// No Kimi data → no snapshot (provider hidden).
    func testProviderWithoutDataReturnsNil() async throws {
        let provider = LocalKimiCodeProvider(cache: LocalUsageCache(kimiRoots: [root], fileURL: cacheFile))
        let daily = try await provider.fetchDaily()
        XCTAssertNil(daily)
    }

    /// Curated settings roots expose the Kimi defaults (Settings → scan roots).
    func testCuratedRootsIncludeKimiDefaults() {
        let curated = CustomScanRoots.curatedRoots(for: "kimi_code").map(\.path)
        XCTAssertTrue(curated.contains { $0.hasSuffix(".kimi-code/sessions") })
    }
}
