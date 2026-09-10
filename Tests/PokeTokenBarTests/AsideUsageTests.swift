import XCTest
import SQLite3
@testable import PokeTokenBar

/// Synthetic SQLite fixtures; no personal Aside data is used by these tests.
final class AsideUsageTests: XCTestCase, @unchecked Sendable {
    private var home: URL!
    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("AsideTests-\(UUID())")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: home) }

    private func sql(_ text: String, at url: URL) throws {
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        XCTAssertEqual(sqlite3_exec(db, text, nil, nil, nil), SQLITE_OK,
                       db.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed")
    }
    private func fixture(user: String = "0", directory: URL? = nil, date: Date = Date(), lastMessage: Date? = nil,
                         usage: String = "{\"input\":22744,\"output\":5515,\"cacheRead\":758400,\"cacheWrite\":0,\"totalTokens\":786659,\"cost\":{\"total\":0.65837}}") throws -> URL {
        let root = directory ?? home.appendingPathComponent(".aside/u/\(user)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let db = root.appendingPathComponent("state.db")
        try sql("""
            CREATE TABLE sessions (id TEXT PRIMARY KEY, model TEXT);
            CREATE TABLE session_turns (id INTEGER PRIMARY KEY, session_id TEXT, token_usage TEXT, started_at INTEGER, last_message_timestamp INTEGER NOT NULL, finished_at INTEGER);
            INSERT INTO sessions VALUES ('synthetic-session', '{"modelId":"synthetic-model"}');
            INSERT INTO session_turns VALUES (1, 'synthetic-session', '\(usage)', \(Int(date.timeIntervalSince1970)), \(Int((lastMessage ?? date).timeIntervalSince1970)), NULL);
            """, at: db)
        return db
    }

    func testTotalOnlyUsageFallsBackWithoutInventingCache() throws {
        let db = try fixture(usage: "{\"input\":null,\"totalTokens\":123}")
        let entry = try XCTUnwrap(try LocalAsideUsageReader.entries(databases: [db], since: .distantPast).first)
        XCTAssertEqual(entry.total, 123)
        XCTAssertEqual(entry.cacheRead, 0)
    }

    @MainActor
    func testRegisteredAlongsideHermesWithCustomRootSupport() throws {
        let suite = "AsideRegistration-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let ids = UsageStore(autoRefresh: false, defaults: defaults).registeredProviderIDs
        XCTAssertTrue(ids.contains("aside"))
        XCTAssertTrue(ids.contains("hermes"))
        XCTAssertEqual(CustomScanRoots.curatedRoots(for: "aside"), LocalAsideUsageReader.roots())
    }

    func testProviderDiscoversAllUsersAndRefreshesMutableTurns() async throws {
        let db = try fixture()
        _ = try fixture(user: "1")
        let provider = LocalAsideProvider(home: home, customRoots: { nil })
        let first = try await provider.fetchDaily()
        XCTAssertEqual(first?.totalTokens, 1573318)
        try sql("UPDATE session_turns SET token_usage = '{\"input\":10,\"output\":20}' WHERE id = 1", at: db)
        let second = try await provider.fetchDaily()
        XCTAssertEqual(second?.totalTokens, 786689)
        let enrichment = await provider.fetchEnrichment()
        XCTAssertEqual(enrichment.weekTotal?.totalTokens, 786689)
        XCTAssertEqual(enrichment.monthTotal?.totalTokens, 786689)
        XCTAssertTrue(enrichment.periodsOK)
    }

    func testReadsTurnBucketsWithoutCountingTotalAgain() throws {
        let db = try fixture()
        let entries = try LocalAsideUsageReader.entries(databases: [db], since: .distantPast)
        let entry = try XCTUnwrap(entries.first)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entry.input, 22744)
        XCTAssertEqual(entry.output, 5515)
        XCTAssertEqual(entry.cacheRead, 758400)
        XCTAssertEqual(entry.total, 786659)
        XCTAssertEqual(entry.explicitCost, 0.65837)
        XCTAssertEqual(entry.model, "synthetic-model")
    }

    /// An unmigrated profile or a foreign state.db must not blank out the healthy databases.
    func testSkipsUnreadableDatabaseAndKeepsHealthyOnes() async throws {
        let noTurns = home.appendingPathComponent(".aside/u/0")
        try FileManager.default.createDirectory(at: noTurns, withIntermediateDirectories: true)
        try sql("CREATE TABLE sessions (id TEXT PRIMARY KEY, model TEXT);", at: noTurns.appendingPathComponent("state.db"))
        _ = try fixture(user: "1")
        let provider = LocalAsideProvider(home: home, customRoots: { nil })
        let withBadSchema = try await provider.fetchDaily()
        XCTAssertEqual(withBadSchema?.totalTokens, 786659)
        let notSQLite = home.appendingPathComponent(".aside/u/2")
        try FileManager.default.createDirectory(at: notSQLite, withIntermediateDirectories: true)
        try Data("not a database".utf8).write(to: notSQLite.appendingPathComponent("state.db"))
        let withGarbage = try await provider.fetchDaily()
        XCTAssertEqual(withGarbage?.totalTokens, 786659)
        // A garbage file fails at prepare; a directory named state.db is what fails at open.
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".aside/u/3/state.db"), withIntermediateDirectories: true)
        let withDirectory = try await provider.fetchDaily()
        XCTAssertEqual(withDirectory?.totalTokens, 786659)
    }

    /// Every database failing is a read failure, not zero usage: the previous snapshot must survive.
    func testAllDatabasesUnreadableThrowsInsteadOfReportingZero() async throws {
        let provider = LocalAsideProvider(home: home, customRoots: { nil })
        let none = try await provider.fetchDaily()
        XCTAssertNil(none, "no databases at all is genuinely no usage")
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".aside/u/0/state.db"), withIntermediateDirectories: true)
        do {
            _ = try await provider.fetchDaily()
            XCTFail("expected throw")
        } catch {}
        let enrichment = await provider.fetchEnrichment()
        XCTAssertFalse(enrichment.periodsOK)
        XCTAssertFalse(enrichment.blocksOK)
        XCTAssertNil(enrichment.weekTotal)
    }

    /// A scan that fails after yielding rows (corrupted pages) must not leak those partial rows.
    func testPartialScanFailureDiscardsThatDatabaseOnly() async throws {
        let corruptRoot = home.appendingPathComponent(".aside/u/0")
        try FileManager.default.createDirectory(at: corruptRoot, withIntermediateDirectories: true)
        let corrupt = corruptRoot.appendingPathComponent("state.db")
        let pad = String(repeating: "x", count: 4000)
        var seed = """
            PRAGMA page_size=4096; PRAGMA journal_mode=DELETE;
            CREATE TABLE sessions (id TEXT PRIMARY KEY, model TEXT);
            CREATE TABLE session_turns (id INTEGER PRIMARY KEY, session_id TEXT, token_usage TEXT, started_at INTEGER, last_message_timestamp INTEGER NOT NULL, finished_at INTEGER);
            """
        let now = Int(Date().timeIntervalSince1970)
        for id in 1...200 {
            seed += "INSERT INTO session_turns VALUES (\(id), 's', '{\"input\":1,\"output\":1,\"pad\":\"\(pad)\"}', \(now), \(now), NULL);"
        }
        try sql(seed, at: corrupt)
        // Page 1 (schema) stays intact so prepare succeeds; interior leaf pages are trashed so step fails mid-scan.
        let handle = try FileHandle(forWritingTo: corrupt)
        try handle.seek(toOffset: 4096 * 20)
        try handle.write(contentsOf: Data(repeating: 0xFF, count: 4096 * 100))
        try handle.close()
        XCTAssertThrowsError(try LocalAsideUsageReader.entries(databases: [corrupt], since: .distantPast))
        _ = try fixture(user: "1")
        let daily = try await LocalAsideProvider(home: home, customRoots: { nil }).fetchDaily()
        XCTAssertEqual(daily?.totalTokens, 786659)
    }

    /// Aborted turns carry all-zero buckets; they must not surface as a 0-token active block (phantom tab).
    func testDropsZeroTokenTurnsSoTheyNeverFormAnActiveBlock() async throws {
        let db = try fixture(usage: "{\"input\":0,\"output\":0,\"cacheRead\":0,\"cacheWrite\":0,\"totalTokens\":0}")
        XCTAssertTrue(try LocalAsideUsageReader.entries(databases: [db], since: .distantPast).isEmpty)
        let provider = LocalAsideProvider(home: home, customRoots: { nil })
        let daily = try await provider.fetchDaily()
        XCTAssertEqual(daily?.totalTokens ?? 0, 0)
        let empty = await provider.fetchEnrichment()
        XCTAssertNil(empty.activeBlock)
        _ = try fixture(user: "1")
        let active = await provider.fetchEnrichment()
        XCTAssertEqual(active.activeBlock?.totalTokens, 786659)
    }

    /// Turns run for a long time and `token_usage` grows while they run; the tokens belong to the day of last activity.
    func testTurnSpanningMidnightCountsTowardLastActivityDay() throws {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        let lateYesterday = startOfToday.addingTimeInterval(-600)
        let spanning = try fixture(user: "0", date: lateYesterday, lastMessage: startOfToday.addingTimeInterval(600))
        let entries = try LocalAsideUsageReader.entries(databases: [spanning], since: startOfToday)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.localDay, LocalUsageReader.todayKey())
        let finishedYesterday = try fixture(user: "1", date: lateYesterday, lastMessage: lateYesterday.addingTimeInterval(60))
        XCTAssertEqual(try LocalAsideUsageReader.entries(databases: [finishedYesterday], since: startOfToday).count, 0)
    }

    /// Settings edits apply on the next refresh, not after a relaunch.
    func testCustomRootsAreReadOnEveryFetch() async throws {
        _ = try fixture()
        let extraRoot = home.appendingPathComponent("extra")
        _ = try fixture(directory: extraRoot)
        final class Box: @unchecked Sendable { var value: String? }
        let extra = Box()
        let provider = LocalAsideProvider(home: home, customRoots: { extra.value })
        let before = try await provider.fetchDaily()
        XCTAssertEqual(before?.totalTokens, 786659)
        extra.value = extraRoot.path
        let after = try await provider.fetchDaily()
        XCTAssertEqual(after?.totalTokens, 1573318)
    }
}
