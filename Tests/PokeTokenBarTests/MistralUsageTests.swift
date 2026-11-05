import XCTest
@testable import PokeTokenBar

/// Synthetic Mistral Vibe session stores; these tests never read the installed `~/.vibe`.
final class MistralUsageTests: XCTestCase, @unchecked Sendable {
    private var temporaryDirectory: URL!
    private var root: URL { temporaryDirectory.appendingPathComponent("vibe/logs/session") }
    private var unified: URL { root.appendingPathComponent("unified") }
    /// 2026-11-05T04:33:00.371Z, the shape Vibe writes for `createdAt` (epoch milliseconds).
    private let createdAtMillis: Int64 = 1_793_853_180_371

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PokeTokenBar-MistralUsageTests-\(UUID())")
        try FileManager.default.createDirectory(at: unified, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: temporaryDirectory)
    }

    // MARK: Reader

    func testSnapshotTotalMapsCachedInputToCacheRead() throws {
        try writeSession("s1", snapshot: Snapshot(sequence: 10, input: 1_000, cached: 800, output: 50))
        let entry = try XCTUnwrap(scan().first)

        XCTAssertEqual(entry.id, "mistral|s1")
        XCTAssertEqual(entry.input, 200, "Vibe's inputTokens includes the cached prefix")
        XCTAssertEqual(entry.cacheRead, 800)
        XCTAssertEqual(entry.cacheWrite, 0)
        XCTAssertEqual(entry.output, 50)
        XCTAssertEqual(entry.total, 1_050, "the total must equal Vibe's totalTokens (input + output)")
        XCTAssertEqual(entry.model, "devstral-2")
        XCTAssertEqual(entry.costUnavailable, true)
        XCTAssertNil(entry.explicitCost)
        XCTAssertEqual(entry.date, Date(timeIntervalSince1970: Double(createdAtMillis) / 1_000),
                       "createdAt is epoch milliseconds")
    }

    /// The snapshot already covers every completion up to `snapshot_sequence`. Only records
    /// journaled after it are added, whether they sit in an older segment or the current one.
    func testJournalAddsOnlyCompletionsAfterTheSnapshot() throws {
        try writeSession(
            "s1",
            snapshot: Snapshot(sequence: 20, input: 1_000, cached: 800, output: 50),
            segments: [
                5: [completion(sequence: 6, input: 400, cached: 300, output: 20)],
                21: [
                    completion(sequence: 22, input: 100, cached: 60, output: 10),
                    completion(sequence: 24, input: 30, cached: 0, output: 5),
                ],
            ])
        let entry = try XCTUnwrap(scan().first)
        XCTAssertEqual(entry.input, 200 + 40 + 30)
        XCTAssertEqual(entry.cacheRead, 800 + 60)
        XCTAssertEqual(entry.output, 50 + 10 + 5)
        XCTAssertEqual(entry.total, 1_050 + 110 + 35)
    }

    func testRecordsAtOrBeforeTheSnapshotInsideALaterSegmentAreSkipped() throws {
        try writeSession(
            "s1",
            snapshot: Snapshot(sequence: 20, input: 1_000, cached: 0, output: 0),
            segments: [
                // A segment named past the snapshot is read, but its records are still checked.
                21: [
                    completion(sequence: 20, input: 999, cached: 0, output: 0),
                    completion(sequence: 21, input: 7, cached: 0, output: 0),
                ],
            ])
        XCTAssertEqual(try XCTUnwrap(scan().first).total, 1_007)
    }

    func testOtherJournalRecordsAndFailedCompletionsAreIgnored() throws {
        let failed = #"{"type":"action_result","sequence":3,"payload":{"result":{"type":"completion_failed","result":{"usage":{"input_tokens":500}}}}}"#
        let intent = #"{"type":"action_intent","sequence":2,"payload":{"kind":"completion","note":"completion_succeeded"}}"#
        try writeSession("s1", snapshot: nil, segments: [
            1: [intent, failed, completion(sequence: 4, input: 10, cached: 0, output: 1)],
        ])
        XCTAssertEqual(try XCTUnwrap(scan().first).total, 11)
    }

    /// Before the first snapshot there is no CURRENT: the whole journal is the total and the
    /// start time comes from meta.json.
    func testSessionWithoutSnapshotUsesWholeJournalAndMetaStartTime() throws {
        try writeSession("fresh", snapshot: nil, segments: [
            0: [
                completion(sequence: 1, input: 100, cached: 40, output: 5),
                completion(sequence: 3, input: 200, cached: 150, output: 6),
            ],
        ], startTime: "2026-11-05T05:39:08.354000+00:00")
        let entry = try XCTUnwrap(scan().first)
        XCTAssertEqual(entry.total, 311)
        XCTAssertEqual(entry.cacheRead, 190)
        XCTAssertEqual(entry.date.timeIntervalSince1970, 1_793_857_148.354, accuracy: 0.001)
    }

    /// Vibe may be mid-write. A torn last line must not drop the lines before it.
    func testTornTrailingLineIsSkipped() throws {
        try writeSession("s1", snapshot: nil, segments: [
            0: [
                completion(sequence: 1, input: 10, cached: 0, output: 1),
                #"{"type":"action_result","sequence":2,"payload":{"result":{"type":"completion_succeeded","res"#,
            ],
        ], startTime: "2026-11-05T05:39:08Z")
        XCTAssertEqual(try XCTUnwrap(scan().first).total, 11)
    }

    /// Without a readable snapshot the journal alone would undercount the session, and the
    /// cache would then hold that lower value next to nothing better. Skip it instead.
    func testUnreadableSnapshotSkipsTheSession() throws {
        try writeSession("s1", snapshot: Snapshot(sequence: 10, input: 1_000, cached: 0, output: 0),
                         segments: [11: [completion(sequence: 11, input: 5, cached: 0, output: 0)]])
        try Data("{".utf8).write(to: projectionURL("s1", sequence: 10))
        XCTAssertTrue(scan().isEmpty)
    }

    func testGenerationNameCannotEscapeTheStore() throws {
        try writeSession("s1", snapshot: Snapshot(sequence: 10, input: 1_000, cached: 0, output: 0))
        let pointer = #"{"generation":"../../other","snapshot_sequence":10}"#
        try Data(pointer.utf8).write(to: unified.appendingPathComponent("s1/CURRENT"))
        XCTAssertTrue(scan().isEmpty)
    }

    func testEachSessionIsOneEntryAndZeroSessionsAreDropped() throws {
        try writeSession("a", snapshot: Snapshot(sequence: 1, input: 10, cached: 0, output: 1))
        try writeSession("b", snapshot: Snapshot(sequence: 1, input: 20, cached: 0, output: 2))
        try writeSession("empty", snapshot: Snapshot(sequence: 1, input: 0, cached: 0, output: 0))
        XCTAssertEqual(Set(scan().map(\.id)), ["mistral|a", "mistral|b"])
    }

    func testSessionsStartedBeforeTheWindowAreExcluded() throws {
        try writeSession("old", snapshot: Snapshot(sequence: 1, input: 10, cached: 0, output: 1))
        let start = Date(timeIntervalSince1970: Double(createdAtMillis) / 1_000)
        XCTAssertEqual(scan(since: start).count, 1)
        XCTAssertTrue(scan(since: start.addingTimeInterval(1)).isEmpty)
    }

    /// The last-write prune is only sound because the entry date is the session start.
    /// A store whose files are all older than the window cannot hold usage dated inside it.
    func testStoreUntouchedSinceTheWindowIsNotParsed() throws {
        try writeSession("s1", snapshot: Snapshot(sequence: 1, input: 10, cached: 0, output: 1),
                         createdAtMillis: Int64(Date().timeIntervalSince1970 * 1_000))
        let past = Date().addingTimeInterval(-3_600)
        let store = unified.appendingPathComponent("s1")
        for file in try allFiles(in: store) {
            try FileManager.default.setAttributes([.modificationDate: past], ofItemAtPath: file.path)
        }
        XCTAssertTrue(scan(since: Date().addingTimeInterval(-60)).isEmpty)
        XCTAssertEqual(scan(since: past.addingTimeInterval(-60)).count, 1)
    }

    func testRootCanNameLogFolderVibeHomeUnifiedFolderOrOneStore() throws {
        try writeSession("s1", snapshot: Snapshot(sequence: 1, input: 10, cached: 0, output: 1))
        let home = temporaryDirectory.appendingPathComponent("vibe")
        for candidate in [root, home, unified, unified.appendingPathComponent("s1")] {
            XCTAssertEqual(
                LocalAdditionalUsageReader.mistralEntries(modifiedSince: .distantPast, roots: [candidate])
                    .map(\.id),
                ["mistral|s1"], candidate.path)
        }
    }

    func testSameSessionUnderTwoRootsCountsOnce() throws {
        try writeSession("s1", snapshot: Snapshot(sequence: 1, input: 10, cached: 0, output: 1))
        let entries = LocalAdditionalUsageReader.mistralEntries(
            modifiedSince: .distantPast, roots: [root, unified])
        XCTAssertEqual(entries.count, 1)
    }

    func testMissingRootIsEmpty() {
        let missing = temporaryDirectory.appendingPathComponent("nope")
        XCTAssertTrue(LocalAdditionalUsageReader.mistralEntries(
            modifiedSince: .distantPast, roots: [missing]).isEmpty)
    }

    func testCustomRootsAddToVibeHomeOrDefaultRoot() throws {
        let home = temporaryDirectory.appendingPathComponent("fake-home")
        let extra = temporaryDirectory.appendingPathComponent("extra")
        try FileManager.default.createDirectory(at: extra, withIntermediateDirectories: true)
        let expected = UsageEnvironment.value("VIBE_HOME").map { raw in
            raw.split(separator: ",").map {
                URL(fileURLWithPath: $0.trimmingCharacters(in: .whitespaces))
                    .appendingPathComponent("logs/session")
            }
        } ?? [home.appendingPathComponent(".vibe/logs/session")]

        XCTAssertEqual(LocalAdditionalUsageReader.mistralRoots(home: home).map(\.path),
                       LocalUsageReader.normalizedRoots(expected).map(\.path))
        XCTAssertEqual(
            LocalAdditionalUsageReader.mistralRoots(customRootsValue: extra.path, home: home).map(\.path),
            LocalUsageReader.normalizedRoots(expected + [extra]).map(\.path))
        XCTAssertEqual(LocalAdditionalUsageReader.defaultMistralRoots,
                       LocalAdditionalUsageReader.mistralRoots())
        XCTAssertEqual(CustomScanRoots.curatedRoots(for: "mistral"),
                       LocalAdditionalUsageReader.mistralRoots())
    }

    @MainActor
    func testProviderIsRegisteredWithExpectedIdentity() throws {
        let provider = LocalMistralProvider()
        XCTAssertEqual(provider.id, "mistral")
        XCTAssertEqual(provider.displayName, "Mistral")
        let suite = "MistralRegistration-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let ids = UsageStore(autoRefresh: false, defaults: defaults).registeredProviderIDs
        XCTAssertTrue(ids.contains("mistral"))
    }

    // MARK: Provider through the shared cache

    func testProviderReplacesAGrowingSessionTotalInsteadOfAddingIt() async throws {
        let (provider, clock) = try makeProvider()
        let now = Int64(clock.now.timeIntervalSince1970 * 1_000)
        try writeSession("s1", snapshot: Snapshot(sequence: 1, input: 100, cached: 0, output: 10),
                         createdAtMillis: now)
        let first = try await provider.fetchDaily()
        XCTAssertEqual(first?.totalTokens, 110)

        try writeSession("s1", snapshot: Snapshot(sequence: 5, input: 300, cached: 0, output: 30),
                         createdAtMillis: now)
        let cached = await provider.fetchEnrichment()
        XCTAssertEqual(cached.monthTotal?.totalTokens, 110,
                       "daily and enrichment must share the same 30-second cache")

        clock.now += 31
        let second = try await provider.fetchDaily()
        XCTAssertEqual(second?.totalTokens, 330, "a session total is cumulative, not a new request")
        let enrichment = await provider.fetchEnrichment()
        XCTAssertTrue(enrichment.blocksOK && enrichment.periodsOK)
        XCTAssertEqual(enrichment.weekTotal?.totalTokens, 330)
        XCTAssertEqual(enrichment.monthTotal?.totalTokens, 330)
        XCTAssertEqual(enrichment.monthDaily?.reduce(0) { $0 + $1.totalTokens }, 330)
        XCTAssertEqual(enrichment.lastUsage, Date(timeIntervalSince1970: Double(now) / 1_000))
    }

    /// Vibe deletes a closed subagent's store. Its usage was spent and must stay counted.
    func testProviderKeepsADeletedSubagentSessionCounted() async throws {
        let (provider, clock) = try makeProvider()
        let now = Int64(clock.now.timeIntervalSince1970 * 1_000)
        try writeSession("parent", snapshot: Snapshot(sequence: 1, input: 100, cached: 0, output: 0),
                         createdAtMillis: now)
        try writeSession("child", snapshot: Snapshot(sequence: 1, input: 40, cached: 0, output: 0),
                         createdAtMillis: now)
        let first = try await provider.fetchDaily()
        XCTAssertEqual(first?.totalTokens, 140)

        try FileManager.default.removeItem(at: unified.appendingPathComponent("child"))
        clock.now += 31
        let second = try await provider.fetchDaily()
        XCTAssertEqual(second?.totalTokens, 140)
    }

    func testMissingStoreProducesNoDailyUsageAndSuccessfulEmptyEnrichment() async throws {
        let (provider, _) = try makeProvider()
        let daily = try await provider.fetchDaily()
        XCTAssertNil(daily)
        let enrichment = await provider.fetchEnrichment()
        XCTAssertTrue(enrichment.blocksOK && enrichment.periodsOK)
        XCTAssertNil(enrichment.lastUsage)
        XCTAssertEqual(enrichment.monthTotal?.totalTokens ?? 0, 0)
    }

    // MARK: Fixtures

    private struct Snapshot {
        var sequence: Int
        var input: Int
        var cached: Int
        var output: Int
    }

    private final class Clock: @unchecked Sendable { var now = Date() }

    private func makeProvider() throws -> (LocalMistralProvider, Clock) {
        let clock = Clock()
        let dayEnd = try XCTUnwrap(Calendar.current.dateInterval(of: .day, for: clock.now)?.end)
        try XCTSkipIf(dayEnd.timeIntervalSince(clock.now) < 60, "cache test crosses a calendar boundary")
        let cache = LocalAdditionalUsageCache(mistralRootsOverride: [root], clock: { clock.now })
        return (LocalMistralProvider(cache: cache), clock)
    }

    private func scan(since: Date = .distantPast) -> [LocalUsageReader.Entry] {
        LocalAdditionalUsageReader.mistralEntries(modifiedSince: since, roots: [root])
    }

    private func generationName(_ sequence: Int) -> String {
        String(format: "%016d", sequence)
    }

    private func projectionURL(_ id: String, sequence: Int) -> URL {
        unified.appendingPathComponent("\(id)/generations/\(generationName(sequence))/projection-state.json")
    }

    private func writeSession(
        _ id: String,
        snapshot: Snapshot?,
        segments: [Int: [String]] = [:],
        startTime: String = "2026-11-05T04:33:00.371000+00:00",
        createdAtMillis: Int64? = nil
    ) throws {
        let store = unified.appendingPathComponent(id)
        let journal = store.appendingPathComponent("journal")
        try FileManager.default.createDirectory(at: journal, withIntermediateDirectories: true)
        let meta = """
        {"session_id":"\(id)","start_time":"\(startTime)",\
        "config":{"active_model":"devstral-2","model_name":"devstral-2"}}
        """
        try Data(meta.utf8).write(to: store.appendingPathComponent("meta.json"))
        if let snapshot {
            let projection = projectionURL(id, sequence: snapshot.sequence)
            try FileManager.default.createDirectory(
                at: projection.deletingLastPathComponent(), withIntermediateDirectories: true)
            let created = createdAtMillis ?? self.createdAtMillis
            let state = """
            {"projection_state_version":1,"session_id":"\(id)","snapshot_sequence":\(snapshot.sequence),\
            "snapshot":{"session":{"createdAt":\(created),"id":"\(id)",\
            "contextUsage":{"cachedInputTokens":1,"inputTokens":2,"outputTokens":3,"totalTokens":5},\
            "tokenUsage":{"cachedInputTokens":\(snapshot.cached),"inputTokens":\(snapshot.input),\
            "outputTokens":\(snapshot.output),"totalTokens":\(snapshot.input + snapshot.output)}}}}
            """
            try Data(state.utf8).write(to: projection)
            let pointer = """
            {"generation":"\(generationName(snapshot.sequence))","session_id":"\(id)",\
            "snapshot_sequence":\(snapshot.sequence),"store_format":"mistral.vibe.unified-session-store/v1"}
            """
            try Data(pointer.utf8).write(to: store.appendingPathComponent("CURRENT"))
        }
        for (first, lines) in segments {
            let body = lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")
            try Data(body.utf8).write(to: journal.appendingPathComponent("\(generationName(first)).jsonl"))
        }
    }

    private func completion(sequence: Int, input: Int, cached: Int, output: Int) -> String {
        """
        {"type":"action_result","sequence":\(sequence),"payload":{"action_id":"a\(sequence)",\
        "result":{"action_id":"a\(sequence)","type":"completion_succeeded","result":{"finish_reason":"stop",\
        "usage":{"cache_write_tokens":0,"cached_input_tokens":\(cached),"input_tokens":\(input),\
        "output_tokens":\(output),"reasoning_tokens":0,"total_tokens":\(input + output)}}},\
        "state":"succeeded"}}
        """
    }

    private func allFiles(in directory: URL) throws -> [URL] {
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil))
        return enumerator.compactMap { $0 as? URL }
    }
}
