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

    private var roots: [URL] { LocalAsideUsageReader.roots(customRootsValue: nil, home: home) }
    private func scan(since: Date = .distantPast) -> [LocalUsageReader.Entry] {
        LocalAsideUsageReader.entries(modifiedSince: since, roots: roots)
    }
    private func total(_ entries: [LocalUsageReader.Entry]) -> Int { entries.reduce(0) { $0 + $1.total } }

    private func sql(_ text: String, at url: URL) throws {
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        XCTAssertEqual(sqlite3_exec(db, text, nil, nil, nil), SQLITE_OK,
                       db.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed")
    }
    private func fixture(user: String = "0", directory: URL? = nil, date: Date = Date(), lastMessage: Date? = nil,
                         finishedAt: Date? = nil, abortedAt: Date? = nil,
                         usage: String = "{\"input\":22744,\"output\":5515,\"cacheRead\":758400,\"cacheWrite\":0,\"totalTokens\":786659,\"cost\":{\"total\":0.65837}}") throws -> URL {
        let root = directory ?? home.appendingPathComponent(".aside/u/\(user)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let db = root.appendingPathComponent("state.db")
        let finished = finishedAt.map { String(Int($0.timeIntervalSince1970)) } ?? "NULL"
        let aborted = abortedAt.map { String(Int($0.timeIntervalSince1970)) } ?? "NULL"
        // Mirrors the real schema: AUTOINCREMENT (ids never reused inside one file) and `aborted_at`.
        try sql("""
            CREATE TABLE sessions (id TEXT PRIMARY KEY, model TEXT);
            CREATE TABLE session_turns (id INTEGER PRIMARY KEY AUTOINCREMENT, session_id TEXT REFERENCES sessions(id) ON DELETE CASCADE, token_usage TEXT, started_at INTEGER, last_message_timestamp INTEGER NOT NULL, finished_at INTEGER, aborted_at INTEGER);
            INSERT INTO sessions VALUES ('synthetic-session', '{"modelId":"synthetic-model"}');
            INSERT INTO session_turns VALUES (1, 'synthetic-session', '\(usage)', \(Int(date.timeIntervalSince1970)), \(Int((lastMessage ?? date).timeIntervalSince1970)), \(finished), \(aborted));
            """, at: db)
        return db
    }

    func testTotalOnlyUsageFallsBackWithoutInventingCache() throws {
        _ = try fixture(usage: "{\"input\":null,\"totalTokens\":123}")
        let entry = try XCTUnwrap(scan().first)
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
        XCTAssertEqual(CustomScanRoots.curatedRoots(for: "aside"), LocalAsideUsageReader.roots(customRootsValue: nil))
        let extra = home.appendingPathComponent("extra")
        try FileManager.default.createDirectory(at: extra, withIntermediateDirectories: true)
        XCTAssertEqual(LocalAsideUsageReader.roots(customRootsValue: extra.path, home: home).map(\.path),
                       [home.appendingPathComponent(".aside/u").path, extra.path])
    }

    /// A cache the test owns: fixed roots instead of Settings, and a clock the test steps past
    /// the 30 s entry so the second scan really merges with `existing`.
    private final class Clock: @unchecked Sendable { var now = Date() }
    private func XCTAssertEqualAsync(_ value: @autoclosure () async throws -> Int?, _ expected: Int, _ message: String = "",
                                     file: StaticString = #filePath, line: UInt = #line) async {
        do { let got = try await value(); XCTAssertEqual(got, expected, message, file: file, line: line) }
        catch { XCTFail("threw \(error) — \(message)", file: file, line: line) }
    }
    private func today(_ provider: LocalAsideProvider) async throws -> Int? { try await provider.fetchDaily()?.totalTokens }
    private func makeProvider() -> (LocalAsideProvider, Clock) {
        let clock = Clock()
        let cache = LocalAdditionalUsageCache(rootsOverride: [.aside: roots], clock: { clock.now })
        return (LocalAsideProvider(cache: cache), clock)
    }

    /// One shared scan feeds daily and enrichment; no per-model rows because `sessions.model`
    /// is the session's current model, not a per-turn record (it would relabel earlier turns).
    func testProviderSharesOneScanAndReportsNoPerModelBreakdown() async throws {
        _ = try fixture()
        _ = try fixture(user: "1")
        let (provider, _) = makeProvider()
        let daily = try await provider.fetchDaily()
        XCTAssertEqual(daily?.totalTokens, 1573318)
        XCTAssertNil(daily?.models, "per-model rows would be relabelled whenever the session switches model")
        let enrichment = await provider.fetchEnrichment()
        XCTAssertTrue(enrichment.periodsOK && enrichment.blocksOK)
        XCTAssertEqual(enrichment.weekTotal?.totalTokens, 1573318)
        XCTAssertEqual(enrichment.monthTotal?.totalTokens, 1573318)
        XCTAssertEqual(enrichment.activeBlock?.totalTokens, 1573318)
    }

    /// Deleting an Aside session cascades to its turns. A plain rescan would drop today's
    /// total by that session's tokens; the cache's keep-max merge keeps them counted until
    /// the cache is invalidated (Settings save / month rollover / relaunch).
    func testDeletedSessionStaysCountedUntilCacheInvalidation() async throws {
        let db = try fixture()
        _ = try fixture(user: "1")
        let (provider, clock) = makeProvider()
        await XCTAssertEqualAsync(try await today(provider), 1573318)
        try sql("PRAGMA foreign_keys = ON; DELETE FROM sessions WHERE id = 'synthetic-session'", at: db)
        XCTAssertEqual(scan().count, 1, "cascade must have removed the turn — otherwise this test guards nothing")
        clock.now += 31
        await XCTAssertEqualAsync(try await today(provider), 1573318, "already-counted usage must not regress")
        await provider.cache.invalidate()
        await XCTAssertEqualAsync(try await today(provider), 786659, "after invalidation the rescan is the truth")
    }

    /// Turns run for a long time and `token_usage` grows in place; the merge keeps the larger value.
    func testGrowingTurnReplacesTheCachedValue() async throws {
        let db = try fixture()
        let (provider, clock) = makeProvider()
        await XCTAssertEqualAsync(try await today(provider), 786659)
        try sql("UPDATE session_turns SET token_usage = '{\"input\":22744,\"output\":9999,\"cacheRead\":758400}' WHERE id = 1", at: db)
        await XCTAssertEqualAsync(try await today(provider), 786659, "inside the 30 s entry the cache answers")
        clock.now += 31
        await XCTAssertEqualAsync(try await today(provider), 786659 + 9999 - 5515)
    }

    /// A recreated state.db (profile removed and re-created) restarts AUTOINCREMENT at 1, so its
    /// first new turn would share an id with the cached pre-reset turn and hide behind the larger
    /// value in the keep-max merge. The inode in the entry id keeps the two apart: the new turn is
    /// visible at once, and the old one lingers only until the cache is invalidated (same policy
    /// as a deleted session).
    func testRecreatedDatabaseGetsFreshEntryIDs() async throws {
        let db = try fixture()
        let (provider, clock) = makeProvider()
        await XCTAssertEqualAsync(try await today(provider), 786659)
        try FileManager.default.removeItem(at: db)
        _ = try fixture(usage: "{\"input\":10,\"output\":20}")   // new file, id 1 again, far smaller
        clock.now += 31
        await XCTAssertEqualAsync(try await today(provider), 786659 + 30, "the recreated store's turn must not hide behind the stale id")
        await provider.cache.invalidate()
        await XCTAssertEqualAsync(try await today(provider), 30)
    }

    /// Every database failing must keep the previous values and never throw — a throw from
    /// `fetchDaily` lands in `failedIDs` and freezes `lastUpdated` app-wide (`UsageStore.refresh`).
    func testUnreadableDatabaseKeepsPreviousValuesWithoutThrowing() async throws {
        let db = try fixture()
        let (provider, clock) = makeProvider()
        await XCTAssertEqualAsync(try await today(provider), 786659)
        try Data("not a database".utf8).write(to: db)
        clock.now += 31
        await XCTAssertEqualAsync(try await today(provider), 786659, "a skipped store merges as nothing new")
        let week = await provider.fetchEnrichment().weekTotal?.totalTokens
        XCTAssertEqual(week, 786659)
    }

    /// An aborted turn that already consumed tokens is usage (real stores hold such rows).
    func testAbortedTurnWithTokensIsCounted() throws {
        _ = try fixture(abortedAt: Date())
        XCTAssertEqual(total(scan()), 786659)
    }

    func testReadsTurnBucketsWithoutCountingTotalAgain() throws {
        _ = try fixture()
        let entries = scan()
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
    func testSkipsUnreadableDatabaseAndKeepsHealthyOnes() throws {
        let noTurns = home.appendingPathComponent(".aside/u/0")
        try FileManager.default.createDirectory(at: noTurns, withIntermediateDirectories: true)
        try sql("CREATE TABLE sessions (id TEXT PRIMARY KEY, model TEXT);", at: noTurns.appendingPathComponent("state.db"))
        _ = try fixture(user: "1")
        XCTAssertEqual(total(scan()), 786659)
        let notSQLite = home.appendingPathComponent(".aside/u/2")
        try FileManager.default.createDirectory(at: notSQLite, withIntermediateDirectories: true)
        try Data("not a database".utf8).write(to: notSQLite.appendingPathComponent("state.db"))
        XCTAssertEqual(total(scan()), 786659)
        // A garbage file fails at prepare; a directory named state.db is what fails at open.
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".aside/u/3/state.db"), withIntermediateDirectories: true)
        XCTAssertEqual(total(scan()), 786659)
    }

    /// A scan that fails after yielding rows (corrupted pages) must not leak those partial rows.
    func testPartialScanFailureDiscardsThatDatabaseOnly() throws {
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
        XCTAssertTrue(scan().isEmpty)
        _ = try fixture(user: "1")
        XCTAssertEqual(total(scan()), 786659)
    }

    /// Aborted turns carry all-zero buckets; they must not surface as a 0-token active block (phantom tab).
    func testDropsZeroTokenTurnsSoTheyNeverFormAnActiveBlock() throws {
        _ = try fixture(usage: "{\"input\":0,\"output\":0,\"cacheRead\":0,\"cacheWrite\":0,\"totalTokens\":0}")
        XCTAssertTrue(scan().isEmpty)
        XCTAssertNil(LocalUsageReader.activeBlock(entries: scan(), now: Date()))
        _ = try fixture(user: "1")
        XCTAssertEqual(LocalUsageReader.activeBlock(entries: scan(), now: Date())?.totalTokens, 786659)
    }

    /// Turns run for a long time and `token_usage` grows while they run; the tokens belong to the day of last activity.
    func testTurnSpanningMidnightCountsTowardLastActivityDay() throws {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        let lateYesterday = startOfToday.addingTimeInterval(-600)
        _ = try fixture(user: "0", date: lateYesterday, lastMessage: startOfToday.addingTimeInterval(600))
        let entries = scan(since: startOfToday)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.localDay, LocalUsageReader.todayKey())
        let finishedYesterday = try fixture(user: "1", date: lateYesterday, lastMessage: lateYesterday.addingTimeInterval(60))
        XCTAssertEqual(LocalAsideUsageReader.entries(modifiedSince: startOfToday, roots: [finishedYesterday.deletingLastPathComponent()]).count, 0)
    }

    /// `finished_at` outranks `last_message_timestamp` in both the SELECT and the WHERE: a turn that
    /// finished today counts today even if its last message was yesterday, and the reverse is excluded.
    func testFinishedAtOutranksLastMessageTimestamp() throws {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        let yesterday = startOfToday.addingTimeInterval(-3600)
        let today = startOfToday.addingTimeInterval(3600)
        let finishedToday = try fixture(user: "0", date: yesterday, lastMessage: yesterday, finishedAt: today)
        let counted = LocalAsideUsageReader.entries(modifiedSince: startOfToday, roots: [finishedToday.deletingLastPathComponent()])
        XCTAssertEqual(counted.count, 1)
        XCTAssertEqual(counted.first?.localDay, LocalUsageReader.todayKey())
        let finishedYesterday = try fixture(user: "1", date: yesterday, lastMessage: today, finishedAt: yesterday)
        XCTAssertTrue(LocalAsideUsageReader.entries(modifiedSince: startOfToday, roots: [finishedYesterday.deletingLastPathComponent()]).isEmpty)
    }
}
