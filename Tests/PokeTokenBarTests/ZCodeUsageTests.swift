import XCTest
@testable import PokeTokenBar

/// ZCode (Z.ai) `model-io-*.jsonl` rollout parsing — bucket mapping, both response shapes,
/// requestId dedup, roots, and the cache/provider path.
final class ZCodeUsageTests: XCTestCase {
    private var base: URL!
    private var root: URL!
    private var cacheFile: URL!
    private static let baseDate = Date(timeIntervalSince1970: 1_779_256_800)

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory
            .appendingPathComponent("ptb-zcode-\(UUID().uuidString)")
        root = base.appendingPathComponent("rollout")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        cacheFile = base.appendingPathComponent("usage-cache.json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: base)
    }

    private static func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }

    /// Writes a `model-io-*.jsonl` under the rollout root.
    @discardableResult
    private func writeRollout(_ text: String, name: String = "model-io-sess_abc.jsonl") throws -> URL {
        let url = root.appendingPathComponent(name)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static func record(model: String = "GLM-5.3-Flash", date: Date,
                               input: Int = 100, output: Int = 20, read: Int = 500, write: Int = 30,
                               requestID: String = "req-1", attempt: Int = 1,
                               legacy: Bool = false) -> String {
        let usage = """
        {"inputTokens":\(input),"outputTokens":\(output),"totalTokens":\(input + output),"cacheReadTokens":\(read),"cacheWriteTokens":\(write)}
        """
        if legacy {
            return """
            {"completedAt":"\(iso(date))","requestId":"\(requestID)","attempt":\(attempt),"model":{"modelId":"\(model)"},"response":{"body":{"usage":\(usage)}}}
            """
        }
        return """
        {"completedAt":"\(iso(date))","requestId":"\(requestID)","attempt":\(attempt),"model":{"modelId":"\(model)"},"response":{"usage":\(usage)}}
        """
    }

    /// 4-way bucket mapping: `inputTokens` excludes the cache buckets and the recorded
    /// `totalTokens` is input + output only, so the app recomputes total = input + output + cache.
    func testParsesUsageRecordMapping() throws {
        let url = try writeRollout(Self.record(date: Self.baseDate))
        let entries = try XCTUnwrap(LocalUsageReader.parseZCodeFile(url, fmt: LocalUsageReader.localDayFormatter()))
        XCTAssertEqual(entries.count, 1)
        let e = try XCTUnwrap(entries.first)
        XCTAssertEqual(e.model, "GLM-5.3-Flash")
        XCTAssertEqual(e.input, 100)
        XCTAssertEqual(e.output, 20)
        XCTAssertEqual(e.cacheRead, 500)
        XCTAssertEqual(e.cacheWrite, 30)
        XCTAssertEqual(e.total, 650, "recorded totalTokens (120) must not replace input + output + cache")
        XCTAssertEqual(e.date, Self.baseDate)
        XCTAssertEqual(e.localDay, LocalUsageReader.localDayFormatter().string(from: e.date))
    }

    /// Older builds nest the payload in `response.body` — both shapes count.
    func testReadsLegacyBodyUsageShape() throws {
        let url = try writeRollout(Self.record(date: Self.baseDate, legacy: true))
        let entries = try XCTUnwrap(LocalUsageReader.parseZCodeFile(url, fmt: LocalUsageReader.localDayFormatter()))
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.total, 650)
    }

    /// Broken JSON, no usage object, and missing/invalid timestamps yield nothing.
    /// A missing model falls back to `zcode`; `startedAt` substitutes for a missing `completedAt`.
    func testSkipsMalformedLinesAndDefaultsModel() throws {
        let started = Self.baseDate.addingTimeInterval(-1)
        let url = try writeRollout([
            "{\"requestId\":\"r\",\"response\":{\"usage\":{}},\"completedAt\":",
            Self.record(date: Self.baseDate, requestID: "r1"),
            "{\"requestId\":\"r2\",\"response\":{\"text\":\"hi\"},\"completedAt\":\"\(Self.iso(Self.baseDate))\"}",
            Self.record(model: "", date: Self.baseDate, requestID: "r4"),
            "{\"requestId\":\"r3\",\"model\":{\"modelId\":\"GLM-5.3\"},\"response\":{\"usage\":{\"inputTokens\":5}},\"startedAt\":\"\(Self.iso(started))\"}",
        ].joined(separator: "\n"))
        let entries = try XCTUnwrap(LocalUsageReader.parseZCodeFile(url, fmt: LocalUsageReader.localDayFormatter()))
        XCTAssertEqual(entries.count, 3, "broken line + no-usage line skipped; r1, r4, r3 kept")
        XCTAssertEqual(entries[0].model, "GLM-5.3-Flash")
        XCTAssertEqual(entries[1].model, "zcode", "an empty model id falls back to the provider name")
        XCTAssertEqual(entries[2].model, "GLM-5.3")
        XCTAssertEqual(entries[2].date, started, "startedAt substitutes for a missing completedAt")
    }

    /// A cache-only request (no input/output) still counts; missing buckets default to 0.
    func testPartialUsageDefaultsMissingBuckets() throws {
        let url = try writeRollout(
            "{\"completedAt\":\"\(Self.iso(Self.baseDate))\",\"requestId\":\"r\"," +
            "\"response\":{\"usage\":{\"cacheReadTokens\":9}}}")
        let e = try XCTUnwrap(LocalUsageReader.parseZCodeFile(url, fmt: LocalUsageReader.localDayFormatter())?.first)
        XCTAssertEqual(e.input, 0)
        XCTAssertEqual(e.output, 0)
        XCTAssertEqual(e.cacheRead, 9)
        XCTAssertEqual(e.cacheWrite, 0)
    }

    /// `requestId` + `attempt` is the identity: the same request logged into two files counts once
    /// (folded by the global dedup), a logged retry (same requestId, next attempt) counts again,
    /// and a requestId-less line falls back to a content id.
    func testRequestIdDedupAndRetryAttempt() async throws {
        let second = Self.baseDate.addingTimeInterval(1)
        try writeRollout(Self.record(date: Self.baseDate, requestID: "r1", attempt: 2),
                         name: "model-io-sess_a.jsonl")
        try writeRollout(Self.record(date: Self.baseDate, requestID: "r1", attempt: 2),
                         name: "model-io-sess_b.jsonl")
        try writeRollout([
            Self.record(date: second, input: 100, output: 7, requestID: "r1", attempt: 1),
            Self.record(date: second, input: 3, output: 4, requestID: ""),
        ].joined(separator: "\n"), name: "model-io-sess_c.jsonl")

        let direct = LocalUsageReader.zcodeEntries(modifiedSince: Date(timeIntervalSince1970: 0),
                                                   roots: [root])
        XCTAssertEqual(direct.count, 3, "retry + requestId-less line; the copied r1/a2 folds")

        let cached = await LocalUsageCache(zcodeRoots: [root], fileURL: cacheFile)
            .zcodeEntries(modifiedSince: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(cached.count, 3, "cache (production) path dedups the same way")
    }

    /// Only `model-io-*.jsonl` counts — other jsonl under the rollout root (e.g. app logs) is ignored.
    func testOnlyModelIOFilesAreScanned() async throws {
        try writeRollout(Self.record(date: Self.baseDate))
        let other = root.appendingPathComponent("zcode-2026-11-05.jsonl")
        try "{\"response\":{\"usage\":{\"inputTokens\":9}}}".write(to: other, atomically: true, encoding: .utf8)

        let cached = await LocalUsageCache(zcodeRoots: [root], fileURL: cacheFile)
            .zcodeEntries(modifiedSince: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(cached.count, 1)
    }

    /// Unreadable file → nil, so the failure is not cached and the next refresh retries.
    func testUnreadableFileYieldsNil() throws {
        let url = try writeRollout(Self.record(date: Self.baseDate))
        try Data([0xFF, 0xFE, 0x41, 0x42]).write(to: url)
        XCTAssertNil(LocalUsageReader.parseZCodeFile(url, fmt: LocalUsageReader.localDayFormatter()))
        XCTAssertTrue(LocalUsageReader.zcodeEntries(modifiedSince: Date(timeIntervalSince1970: 0),
                                                    roots: [root]).isEmpty,
                      "an unreadable rollout file inside a scanned root is skipped, not fatal")
    }

    /// Blob cache round-trips through the disk snapshot, and an appended record is picked up.
    func testCacheRoundTripAndPicksUpAppendedRecord() async throws {
        let url = try writeRollout(Self.record(date: Self.baseDate))
        let first = await LocalUsageCache(zcodeRoots: [root], fileURL: cacheFile)
            .zcodeEntries(modifiedSince: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(first.count, 1)

        let again = await LocalUsageCache(zcodeRoots: [root], fileURL: cacheFile)
            .zcodeEntries(modifiedSince: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(again.count, 1, "identical after disk snapshot round-trip")

        try [Self.record(date: Self.baseDate), Self.record(date: Self.baseDate.addingTimeInterval(1), requestID: "r2")]
            .joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        let appended = await LocalUsageCache(zcodeRoots: [root], fileURL: cacheFile)
            .zcodeEntries(modifiedSince: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(appended.count, 2, "size change invalidates the blob")
    }

    /// A snapshot written before ZCode support (no `zcode` key) still loads.
    func testCacheLoadsSnapshotWithoutZCodeKey() async throws {
        let legacy = """
        {"claude":{},"codex":{},"codexSessionIDs":{},"gemini":{},"grok":{},"pi":{},"omp":{},"omo":{},
         "kimi":{},"codexParserVersion":4,"codexSessionIndexVersion":2,"grokParserVersion":1,
         "piParserVersion":3,"ompParserVersion":2,"kimiParserVersion":1}
        """
        try legacy.write(to: cacheFile, atomically: true, encoding: .utf8)
        try writeRollout(Self.record(date: Self.baseDate))
        let entries = await LocalUsageCache(zcodeRoots: [root], fileURL: cacheFile)
            .zcodeEntries(modifiedSince: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(entries.count, 1)
    }

    /// The single default root is `~/.zcode/cli/rollout`.
    func testRolloutRoots() {
        let home = URL(fileURLWithPath: "/Users/tester")
        XCTAssertEqual(LocalUsageReader.computeZCodeRolloutRoots(home: home).map(\.path),
                       ["/Users/tester/.zcode/cli/rollout"])
    }

    /// Through the provider: today's records → daily total with a per-model breakdown. GLM models
    /// are not in the price table and ZCode records no cost → cost is unavailable, not a measured $0.
    func testProviderFetchDailyBreakdownAndUnavailableCost() async throws {
        let now = Date()
        try writeRollout([
            Self.record(model: "GLM-5.3-Flash", date: now.addingTimeInterval(-2),
                        input: 100, output: 200, read: 0, write: 0, requestID: "r1"),
            Self.record(model: "GLM-5.3", date: now.addingTimeInterval(-1),
                        input: 10, output: 20, read: 0, write: 0, requestID: "r2"),
        ].joined(separator: "\n"))

        let provider = LocalZCodeProvider(cache: LocalUsageCache(zcodeRoots: [root], fileURL: cacheFile))
        XCTAssertEqual(provider.id, "zcode")
        XCTAssertEqual(provider.displayName, "ZCode")
        let fetched = try await provider.fetchDaily()
        let daily = try XCTUnwrap(fetched)
        XCTAssertEqual(daily.totalTokens, 330)
        XCTAssertEqual(daily.costCoverage, .unavailable)
        let models = try XCTUnwrap(daily.models)
        XCTAssertEqual(models["GLM-5.3-Flash"], 300)
        XCTAssertEqual(models["GLM-5.3"], 30)

        let enrichment = await provider.fetchEnrichment()
        XCTAssertTrue(enrichment.periodsOK)
        XCTAssertEqual(enrichment.monthTotal?.totalTokens, 330)
    }

    /// No ZCode data → no snapshot (provider hidden).
    func testProviderWithoutDataReturnsNil() async throws {
        let provider = LocalZCodeProvider(cache: LocalUsageCache(zcodeRoots: [root], fileURL: cacheFile))
        let daily = try await provider.fetchDaily()
        XCTAssertNil(daily)
    }

    /// Curated settings roots expose the ZCode default (Settings → scan roots).
    func testCuratedRootsIncludeZCodeDefault() {
        let curated = CustomScanRoots.curatedRoots(for: "zcode").map(\.path)
        XCTAssertTrue(curated.contains { $0.hasSuffix(".zcode/cli/rollout") })
    }
}
