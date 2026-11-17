import SQLite3
import XCTest
@testable import PokeTokenBar

/// Synthetic Devin databases; these tests never read installed session stores.
final class DevinUsageTests: XCTestCase, @unchecked Sendable {
    private var temporaryDirectory: URL!
    private let timestamp: Int64 = 1_793_299_034
    private let turnTotal = 3 + 17 + 32_820 + 5_661

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PokeTokenBar-DevinUsageTests-\(UUID())")
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testTokenBucketsMapDirectlyWithoutSubtractingCaches() throws {
        try seed(rows: [Row(id: 1)])
        let result = scan()
        let entry = try XCTUnwrap(result.entries.first)

        XCTAssertEqual(result.entries.count, 1)
        XCTAssertEqual(entry.input, 3, "Devin input_tokens already excludes both cache buckets")
        XCTAssertEqual(entry.output, 17)
        XCTAssertEqual(entry.cacheRead, 32_820)
        XCTAssertEqual(entry.cacheWrite, 5_661)
        XCTAssertEqual(entry.total, turnTotal, "context_input_tokens must not be added again")
        XCTAssertEqual(entry.id, entryID(1))
        XCTAssertEqual(entry.model, "swe-2-max")
        XCTAssertEqual(entry.costUnavailable, true)
        XCTAssertNil(entry.explicitCost)
        XCTAssertEqual(entry.date, Date(timeIntervalSince1970: Double(timestamp)),
                       "created_at is epoch seconds, not milliseconds")
    }

    func testNullMetricsAdvanceWatermarkWithoutProducingEntries() throws {
        try seed(rows: [
            Row(id: 1),
            Row(id: 2, payload: #"{"role":"user","metadata":{"metrics":null}}"#),
            Row(id: 3, payload: #"{"role":"tool","metadata":{"metrics":null}}"#),
            Row(id: 4, payload: #"{"role":"system","metadata":{"metrics":null}}"#),
        ])
        let first = scan()
        XCTAssertEqual(first.entries.map(\.id), [entryID(1)])
        XCTAssertEqual(first.highWaterRowID, 4)

        try insert(rows: [Row(id: 5)])
        let second = LocalAdditionalUsageReader.devinEntries(
            modifiedSince: .distantPast, afterRowIDByPath: first.highWaterByPath, roots: [root])
        XCTAssertEqual(second.entries.map(\.id), [entryID(5)])
        XCTAssertEqual(second.highWaterRowID, 5)
        XCTAssertFalse(second.didReset)

        let empty = LocalAdditionalUsageReader.devinEntries(
            modifiedSince: .distantPast, afterRowID: second.highWaterRowID, roots: [root])
        XCTAssertTrue(empty.entries.isEmpty)
        XCTAssertEqual(empty.highWaterRowID, 5, "an empty incremental scan must retain its watermark")
    }

    func testBranchCopiesWithSameMessageIDKeepMaximumMetrics() throws {
        try seed(rows: [
            Row(id: 1, payload: """
            {"message_id":"shared","metadata":{"metrics":{"input_tokens":10,"output_tokens":20,\
            "cache_read_tokens":30,"cache_creation_tokens":40}}}
            """),
            Row(id: 2, payload: """
            {"message_id":"shared","metadata":{"metrics":{"input_tokens":1,"output_tokens":2,\
            "cache_read_tokens":3,"cache_creation_tokens":4}}}
            """),
        ])
        let result = scan()
        XCTAssertEqual(result.entries.count, 1)
        let entry = try XCTUnwrap(result.entries.first)
        XCTAssertEqual(entry.id, "devin|\(databaseURL.path)|main|shared")
        XCTAssertEqual(entry.input, 10)
        XCTAssertEqual(entry.output, 20)
        XCTAssertEqual(entry.cacheRead, 30)
        XCTAssertEqual(entry.cacheWrite, 40)
        XCTAssertEqual(entry.total, 100)
        XCTAssertEqual(result.highWaterRowID, 2, "deduplication must not change the row watermark")
    }

    func testSameMessageIDInDifferentSessionsStaysDistinct() throws {
        let payload = #"{"message_id":"shared","metadata":{"metrics":{"input_tokens":10}}}"#
        try seed(rows: [
            Row(id: 1, payload: payload),
            Row(id: 2, sessionID: "sidekick", payload: payload),
        ])
        XCTAssertEqual(Set(scan().entries.map(\.id)), [
            "devin|\(databaseURL.path)|main|shared",
            "devin|\(databaseURL.path)|sidekick|shared",
        ])
    }

    func testMetricsWithoutMessageIDUseUniqueRowFallbacks() throws {
        try seed(rows: [Row(id: 1), Row(id: 2)])
        let result = scan()
        XCTAssertEqual(result.entries.count, 2)
        XCTAssertEqual(Set(result.entries.map(\.id)), [
            "devin|\(databaseURL.path)|main|row1",
            "devin|\(databaseURL.path)|main|row2",
        ])
        XCTAssertEqual(result.entries.reduce(0) { $0 + $1.total }, turnTotal * 2)
    }

    func testModelComesFromSessionJoinIncludingSidekickAndMissingSession() throws {
        try seed(rows: [
            Row(id: 1, payload: #"{"metadata":{"metrics":{"input_tokens":1}},"model":"wrong"}"#),
            Row(id: 2, sessionID: "sidekick"),
            Row(id: 3, sessionID: "missing"),
        ])
        let entries = scan().entries
        let models = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0.model) })
        XCTAssertEqual(models, [
            entryID(1): "swe-2-max",
            entryID(2, sessionID: "sidekick"): "fusion-swe-2-high",
            entryID(3, sessionID: "missing"): "unknown",
        ])
        XCTAssertEqual(entries.count, 3, "metrics mark usage without requiring a role or excluding sidekicks")
    }

    func testMalformedMissingAndZeroMetricsAreSkippedButWatermarked() throws {
        try seed(rows: [
            Row(id: 1, payload: "not json"),
            Row(id: 2, payload: #"{"metadata":null}"#),
            Row(id: 3, payload: #"{"metadata":{}}"#),
            Row(id: 4, payload: #"{"metadata":{"metrics":{}}}"#),
        ])
        let result = scan()
        XCTAssertTrue(result.entries.isEmpty)
        XCTAssertEqual(result.highWaterRowID, 4)
    }

    func testNumericCutoffUsesExactParsedDateWindow() throws {
        try seed(rows: [
            Row(id: 1, createdAt: timestamp - 86_401),
            Row(id: 2, createdAt: timestamp - 1),
            Row(id: 3),
            Row(id: 4, createdAt: timestamp + 1),
        ])
        let result = scan(since: Date(timeIntervalSince1970: Double(timestamp)))
        XCTAssertEqual(Set(result.entries.map(\.id)), [entryID(3), entryID(4)])
        XCTAssertEqual(result.highWaterRowID, 4)

        let incremental = LocalAdditionalUsageReader.devinEntries(
            modifiedSince: .distantPast, afterRowID: 3, roots: [root])
        XCTAssertEqual(incremental.entries.map(\.id), [entryID(4)])
    }

    func testRecreatedStoreBelowWatermarkTriggersColdRescan() throws {
        try seed(rows: [Row(id: 1), Row(id: 5)])
        let first = scan()
        XCTAssertEqual(first.highWaterRowID, 5)
        try FileManager.default.removeItem(at: databaseURL)
        try seed(rows: [Row(id: 1, payload: #"{"metadata":{"metrics":{"input_tokens":2}}}"#)])

        let result = LocalAdditionalUsageReader.devinEntries(
            modifiedSince: .distantPast, afterRowIDByPath: first.highWaterByPath, roots: [root])
        XCTAssertTrue(result.didReset)
        XCTAssertEqual(result.entries.map(\.id), [entryID(1)])
        XCTAssertEqual(result.entries.first?.total, 2)
        XCTAssertEqual(result.highWaterRowID, 1)
    }

    func testMultipleDatabasesKeepDistinctIDsAndHistoryWhenOneResets() throws {
        try seed(rows: [Row(id: 1), Row(id: 5)])
        let otherDatabase = temporaryDirectory.appendingPathComponent("other/cli/sessions.db")
        try seed(rows: [Row(id: 1), Row(id: 5)], in: otherDatabase)
        let first = LocalAdditionalUsageReader.devinEntries(
            modifiedSince: .distantPast, roots: [root, otherDatabase])
        XCTAssertEqual(first.entries.count, 4)
        XCTAssertEqual(Set(first.entries.map(\.id)).count, 4)
        XCTAssertEqual(first.highWaterByPath.count, 2)

        try FileManager.default.removeItem(at: otherDatabase)
        try seed(rows: [Row(id: 1)], in: otherDatabase)
        let result = LocalAdditionalUsageReader.devinEntries(
            modifiedSince: .distantPast, afterRowIDByPath: first.highWaterByPath,
            roots: [root, otherDatabase])
        XCTAssertTrue(result.didReset)
        XCTAssertEqual(Set(result.entries.map(\.id)),
                       [entryID(1), entryID(5), entryID(1, in: otherDatabase)])
        XCTAssertEqual(result.highWaterByPath[databaseURL.path], 5)
        XCTAssertEqual(result.highWaterByPath[otherDatabase.path], 1)
    }

    func testRootCanPointAtDevinFolderCliFolderOrDatabase() throws {
        try seed(rows: [Row(id: 1)])
        for scanRoot in [root, databaseURL.deletingLastPathComponent(), databaseURL] {
            let result = LocalAdditionalUsageReader.devinEntries(
                modifiedSince: .distantPast, roots: [scanRoot])
            XCTAssertEqual(result.entries.map(\.id), [entryID(1)], scanRoot.path)
        }
    }

    func testMissingDatabaseReturnsEmptyWithoutReset() {
        let result = scan()
        XCTAssertTrue(result.entries.isEmpty)
        XCTAssertEqual(result.highWaterRowID, 0)
        XCTAssertFalse(result.didReset)
    }

    func testCustomRootsAddToXDGOrDefaultRoots() throws {
        let home = temporaryDirectory.appendingPathComponent("fake-home")
        let extra = temporaryDirectory.appendingPathComponent("extra")
        try FileManager.default.createDirectory(at: extra, withIntermediateDirectories: true)
        let expected = UsageEnvironment.value("XDG_DATA_HOME").map { raw in
            raw.split(separator: ",").map {
                URL(fileURLWithPath: $0.trimmingCharacters(in: .whitespaces))
                    .appendingPathComponent("devin")
            }
        } ?? [home.appendingPathComponent(".local/share/devin")]

        XCTAssertEqual(LocalAdditionalUsageReader.devinRoots(home: home).map(\.path),
                       LocalUsageReader.normalizedRoots(expected).map(\.path))
        XCTAssertEqual(
            LocalAdditionalUsageReader.devinRoots(customRootsValue: extra.path, home: home).map(\.path),
            LocalUsageReader.normalizedRoots(expected + [extra]).map(\.path))
        XCTAssertEqual(LocalAdditionalUsageReader.defaultDevinRoots,
                       LocalAdditionalUsageReader.devinRoots())
        XCTAssertEqual(CustomScanRoots.curatedRoots(for: "devin"),
                       LocalAdditionalUsageReader.devinRoots())
    }

    @MainActor
    func testProviderIsRegisteredWithExpectedIdentity() throws {
        let provider = LocalDevinProvider()
        XCTAssertEqual(provider.id, "devin")
        XCTAssertEqual(provider.displayName, "Devin")
        let suite = "DevinRegistration-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let ids = UsageStore(autoRefresh: false, defaults: defaults).registeredProviderIDs
        XCTAssertEqual(ids.last, "devin")
    }

    func testReadsCommittedRowsWhileWALWriterRemainsOpen() throws {
        try seed(rows: [Row(id: 1)])
        var writer: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &writer), SQLITE_OK)
        defer { sqlite3_close(writer) }
        try insert(rows: [Row(id: 2)])
        XCTAssertTrue(FileManager.default.fileExists(atPath: databaseURL.path + "-wal"))
        XCTAssertEqual(Set(scan().entries.map(\.id)), [entryID(1), entryID(2)])
    }

    func testProviderSharesDailyAndEnrichmentCacheThenMergesNewRows() async throws {
        let (provider, clock) = try makeProvider()
        let createdAt = Int64(clock.now.timeIntervalSince1970)
        try seed(rows: [Row(id: 1, createdAt: createdAt)])
        let first = try await provider.fetchDaily()
        XCTAssertEqual(first?.totalTokens, turnTotal)

        try insert(rows: [Row(id: 2, createdAt: createdAt)])
        let cached = await provider.fetchEnrichment()
        XCTAssertEqual(cached.monthTotal?.totalTokens, turnTotal,
                       "daily and enrichment must share the same 30-second cache")

        clock.now += 31
        let second = try await provider.fetchDaily()
        XCTAssertEqual(second?.totalTokens, turnTotal * 2, "incremental rows must merge with cached rows")
        let enrichment = await provider.fetchEnrichment()
        XCTAssertTrue(enrichment.blocksOK && enrichment.periodsOK)
        XCTAssertEqual(enrichment.weekTotal?.totalTokens, turnTotal * 2)
        XCTAssertEqual(enrichment.monthTotal?.totalTokens, turnTotal * 2)
        XCTAssertEqual(enrichment.monthDaily?.reduce(0) { $0 + $1.totalTokens }, turnTotal * 2)
        XCTAssertEqual(enrichment.lastUsage, Date(timeIntervalSince1970: Double(createdAt)))
    }

    func testProviderDiscardsStaleCacheWhenDatabaseRestartsIDs() async throws {
        let (provider, clock) = try makeProvider()
        let createdAt = Int64(clock.now.timeIntervalSince1970)
        try seed(rows: [Row(id: 1, createdAt: createdAt), Row(id: 5, createdAt: createdAt)])
        let first = try await provider.fetchDaily()
        XCTAssertEqual(first?.totalTokens, turnTotal * 2)

        try FileManager.default.removeItem(at: databaseURL)
        try seed(rows: [Row(id: 1, createdAt: createdAt,
                            payload: #"{"metadata":{"metrics":{"input_tokens":2}}}"#)])
        clock.now += 31
        let second = try await provider.fetchDaily()
        XCTAssertEqual(second?.totalTokens, 2,
                       "reset must replace existing rows, not keep-max against reused ids")
    }

    func testProviderMergesBranchCopiesAcrossIncrementalScans() async throws {
        let (provider, clock) = try makeProvider()
        let createdAt = Int64(clock.now.timeIntervalSince1970)
        try seed(rows: [Row(id: 1, createdAt: createdAt,
                            payload: #"{"message_id":"shared","metadata":{"metrics":{"input_tokens":10}}}"#)])
        let first = try await provider.fetchDaily()
        XCTAssertEqual(first?.totalTokens, 10)

        try insert(rows: [Row(id: 2, createdAt: createdAt,
                              payload: #"{"message_id":"shared","metadata":{"metrics":{"input_tokens":20}}}"#)])
        clock.now += 31
        let second = try await provider.fetchDaily()
        XCTAssertEqual(second?.totalTokens, 20, "branch copies must merge with cached usage, not add to it")
        let enrichment = await provider.fetchEnrichment()
        XCTAssertEqual(enrichment.monthTotal?.totalTokens, 20)
    }

    func testUnreadableDatabaseRetainsCachedUsageWithoutThrowingOrResetting() async throws {
        let (provider, clock) = try makeProvider()
        try seed(rows: [Row(id: 1, createdAt: Int64(clock.now.timeIntervalSince1970))])
        let first = try await provider.fetchDaily()
        XCTAssertEqual(first?.totalTokens, turnTotal)

        try Data("not sqlite".utf8).write(to: databaseURL, options: .atomic)
        let result = LocalAdditionalUsageReader.devinEntries(
            modifiedSince: .distantPast, afterRowID: 1, roots: [root])
        XCTAssertTrue(result.entries.isEmpty)
        XCTAssertEqual(result.highWaterRowID, 1)
        XCTAssertFalse(result.didReset)
        clock.now += 31
        let second = try await provider.fetchDaily()
        XCTAssertEqual(second?.totalTokens, turnTotal)
        let enrichment = await provider.fetchEnrichment()
        XCTAssertTrue(enrichment.periodsOK)
        XCTAssertEqual(enrichment.monthTotal?.totalTokens, turnTotal)
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

    private final class Clock: @unchecked Sendable { var now = Date() }

    private func makeProvider() throws -> (LocalDevinProvider, Clock) {
        let clock = Clock()
        let dayEnd = try XCTUnwrap(Calendar.current.dateInterval(of: .day, for: clock.now)?.end)
        try XCTSkipIf(dayEnd.timeIntervalSince(clock.now) < 60, "cache test crosses a calendar boundary")
        let cache = LocalAdditionalUsageCache(devinRootsOverride: [root], clock: { clock.now })
        return (LocalDevinProvider(cache: cache), clock)
    }

    // MARK: Fixtures

    private var root: URL { temporaryDirectory.appendingPathComponent("devin") }
    private var databaseURL: URL { root.appendingPathComponent("cli/sessions.db") }

    private func scan(since: Date = .distantPast) -> LocalAdditionalUsageReader.IncrementalStoreLoadResult {
        LocalAdditionalUsageReader.devinEntries(modifiedSince: since, roots: [root])
    }

    private func entryID(_ id: Int64, sessionID: String = "main", in database: URL? = nil) -> String {
        "devin|\((database ?? databaseURL).path)|\(sessionID)|row\(id)"
    }

    private struct Row {
        let id: Int64
        var sessionID = "main"
        var createdAt: Int64 = 1_793_299_034
        var payload = """
        {"role":"assistant","metadata":{"metrics":{"input_tokens":3,"output_tokens":17,\
        "cache_read_tokens":32820,"cache_creation_tokens":5661,"context_input_tokens":38484,\
        "ttft_ms":200,"total_time_ms":1000,"tpot_ms":10,"tokens_per_sec":20}}}
        """
    }

    private func seed(rows: [Row], in database: URL? = nil) throws {
        let target = database ?? databaseURL
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try execute(target, sql: """
        PRAGMA journal_mode = WAL;
        CREATE TABLE sessions (id TEXT PRIMARY KEY, model TEXT NOT NULL);
        CREATE TABLE message_nodes (
            row_id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id TEXT NOT NULL,
            node_id INTEGER,
            chat_message TEXT NOT NULL,
            created_at INTEGER NOT NULL
        );
        INSERT INTO sessions VALUES ('main', 'swe-2-max'), ('sidekick', 'fusion-swe-2-high');
        """)
        try insert(rows: rows, in: target)
    }

    private func insert(rows: [Row], in database: URL? = nil) throws {
        guard !rows.isEmpty else { return }
        let values = rows.map { row in
            let payload = row.payload.replacingOccurrences(of: "'", with: "''")
            return "(\(row.id), '\(row.sessionID)', \(row.id), '\(payload)', \(row.createdAt))"
        }.joined(separator: ",\n")
        try execute(database ?? databaseURL, sql: "INSERT INTO message_nodes VALUES \(values);")
    }

    private func execute(_ url: URL, sql: String) throws {
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &database), SQLITE_OK)
        guard let database else { throw NSError(domain: "SQLite", code: 1) }
        defer { sqlite3_close(database) }
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(database, sql, nil, nil, &errorMessage)
        let message = errorMessage.map { String(cString: $0) }
        sqlite3_free(errorMessage)
        XCTAssertEqual(result, SQLITE_OK, message ?? "SQLite statement failed")
        if result != SQLITE_OK { throw NSError(domain: "SQLite", code: Int(result)) }
    }
}
