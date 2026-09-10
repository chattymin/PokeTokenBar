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
    private func fixture(user: String = "0", date: Date = Date(), usage: String = "{\"input\":22744,\"output\":5515,\"cacheRead\":758400,\"cacheWrite\":0,\"totalTokens\":786659,\"cost\":{\"total\":0.65837}}") throws -> URL {
        let root = home.appendingPathComponent(".aside/u/\(user)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let db = root.appendingPathComponent("state.db")
        try sql("""
            CREATE TABLE sessions (id TEXT PRIMARY KEY, model TEXT);
            CREATE TABLE session_turns (id INTEGER PRIMARY KEY, session_id TEXT, token_usage TEXT, started_at INTEGER, finished_at INTEGER);
            INSERT INTO sessions VALUES ('synthetic-session', '{"modelId":"synthetic-model"}');
            INSERT INTO session_turns VALUES (1, 'synthetic-session', '\(usage)', \(Int(date.timeIntervalSince1970)), NULL);
            """, at: db)
        return db
    }

    func testTotalOnlyUsageFallsBackWithoutInventingCache() throws {
        let db = try fixture(usage: "{\"input\":null,\"totalTokens\":123}")
        let entry = try XCTUnwrap(LocalAsideUsageReader.entries(databases: [db], since: .distantPast).first)
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
        let provider = LocalAsideProvider(home: home, customRootsValue: nil)
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
}
