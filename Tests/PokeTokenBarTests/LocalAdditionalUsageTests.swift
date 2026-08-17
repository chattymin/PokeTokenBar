import SQLite3
import XCTest
@testable import PokeTokenBar

final class LocalAdditionalUsageTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PokeTokenBar-LocalAdditionalUsageTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
        temporaryDirectory = nil
    }

    func testOpenCodeReadsSQLiteAndPreservesReportedTotalAndCost() throws {
        let database = temporaryDirectory.appendingPathComponent("opencode.db")
        try execute(database, sql: """
        CREATE TABLE message (
            id TEXT PRIMARY KEY,
            session_id TEXT NOT NULL,
            time_created INTEGER NOT NULL,
            data TEXT NOT NULL
        );
        INSERT INTO message VALUES (
            'msg-1', 'session-1', 1767312000000,
            '{"id":"msg-1","sessionID":"session-1","providerID":"anthropic","modelID":"claude-sonnet-4-20250514","time":{"created":1767312000000},"tokens":{"input":100,"output":50,"total":250,"cache":{"read":10,"write":20}},"cost":0.25}'
        );
        """)

        let entries = LocalAdditionalUsageReader.openCodeEntries(
            modifiedSince: try date("2026-01-01T00:00:00Z"), roots: [temporaryDirectory])

        let entry = try XCTUnwrap(entries.first)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entry.input, 100)
        XCTAssertEqual(entry.output, 120, "unclassified total tokens are retained as output")
        XCTAssertEqual(entry.cacheWrite, 20)
        XCTAssertEqual(entry.cacheRead, 10)
        XCTAssertEqual(entry.total, 250)
        XCTAssertEqual(entry.explicitCost, 0.25)

        let daily = try XCTUnwrap(LocalUsageReader.daily(entries: entries, localDay: entry.localDay))
        XCTAssertEqual(daily.totalTokens, 250)
        XCTAssertEqual(daily.totalCost, 0.25, accuracy: 0.000_001)
    }

    func testOpenCodeFallsBackToLegacyDatabaseWithoutTimeCreatedColumn() throws {
        let database = temporaryDirectory.appendingPathComponent("opencode.db")
        try execute(database, sql: """
        CREATE TABLE message (id TEXT PRIMARY KEY, session_id TEXT NOT NULL, data TEXT NOT NULL);
        INSERT INTO message VALUES (
            'legacy-1', 'session-1',
            '{"id":"legacy-1","sessionID":"session-1","providerID":"openai","modelID":"gpt-5","time":{"created":1767312000000},"tokens":{"input":7,"output":3,"cache":{"read":2,"write":1}},"cost":0}'
        );
        """)

        let entries = LocalAdditionalUsageReader.openCodeEntries(
            modifiedSince: try date("2026-01-01T00:00:00Z"), roots: [temporaryDirectory])

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.total, 13)
    }

    func testHermesReadsSessionTokensReasoningAndActualCost() throws {
        let database = temporaryDirectory.appendingPathComponent("state.db")
        try execute(database, sql: """
        CREATE TABLE sessions (
            id TEXT PRIMARY KEY,
            model TEXT,
            billing_provider TEXT,
            started_at REAL NOT NULL,
            message_count INTEGER DEFAULT 0,
            input_tokens INTEGER DEFAULT 0,
            output_tokens INTEGER DEFAULT 0,
            cache_read_tokens INTEGER DEFAULT 0,
            cache_write_tokens INTEGER DEFAULT 0,
            reasoning_tokens INTEGER DEFAULT 0,
            estimated_cost_usd REAL,
            actual_cost_usd REAL
        );
        INSERT INTO sessions VALUES (
            'session-1', 'claude-sonnet-4-20250514', 'anthropic', 1767312000, 42,
            100, 50, 10, 20, 5, 0.12, 0.34
        );
        """)

        let entries = LocalAdditionalUsageReader.hermesEntries(
            modifiedSince: try date("2026-01-01T00:00:00Z"), roots: [database])

        let entry = try XCTUnwrap(entries.first)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entry.input, 100)
        XCTAssertEqual(entry.output, 55)
        XCTAssertEqual(entry.cacheWrite, 20)
        XCTAssertEqual(entry.cacheRead, 10)
        XCTAssertEqual(entry.total, 185)
        XCTAssertEqual(entry.explicitCost, 0.34)
    }

    func testHermesAcceptsMillisecondStartedAt() throws {
        let database = temporaryDirectory.appendingPathComponent("state.db")
        try execute(database, sql: """
        CREATE TABLE sessions (
            id TEXT PRIMARY KEY, model TEXT, billing_provider TEXT, started_at REAL NOT NULL,
            message_count INTEGER, input_tokens INTEGER, output_tokens INTEGER,
            cache_read_tokens INTEGER, cache_write_tokens INTEGER, reasoning_tokens INTEGER,
            estimated_cost_usd REAL, actual_cost_usd REAL
        );
        INSERT INTO sessions VALUES (
            'session-ms', 'gpt-5', 'openai', 1767312000000, 1,
            10, 5, 0, 0, 0, 0, 0
        );
        """)

        let entries = LocalAdditionalUsageReader.hermesEntries(
            modifiedSince: try date("2026-01-01T00:00:00Z"), roots: [database])

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.localDay, "2026-01-02")
        XCTAssertEqual(entries.first?.total, 15)
    }

    @MainActor
    func testDefaultRegistryIncludesOnlyRequestedAdditionalProviders() {
        let suite = "LocalAdditionalUsageTests.registry.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UsageStore(autoRefresh: false, defaults: defaults)

        XCTAssertEqual(
            Set(store.registeredProviderIDs),
            Set(["claude_code", "codex", "gemini", "antigravity",
                 "opencode", "hermes", "cursor", "grok", "copilot", "kiro", "pi"]))
    }

    func testPrintRealOpenCodeAggregate() throws {
        guard ProcessInfo.processInfo.environment["PTB_PARITY"] == "1" else {
            throw XCTSkip("set PTB_PARITY=1 for the local OpenCode smoke test")
        }
        let roots = LocalAdditionalUsageReader.defaultOpenCodeRoots
        guard roots.contains(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            throw XCTSkip("no local OpenCode data directory")
        }
        let entries = LocalAdditionalUsageReader.openCodeEntries(
            modifiedSince: LocalUsageReader.startOfMonth(Date()))
        XCTAssertFalse(entries.isEmpty)
        let today = LocalUsageReader.todayKey()
        let todayTotal = entries.filter { $0.localDay == today }.reduce(0) { $0 + $1.total }
        print("OPENCODE_NATIVE_PARITY entries=\(entries.count) today=\(todayTotal) month=\(entries.reduce(0) { $0 + $1.total })")
    }

    func testPrintRealHermesAggregate() throws {
        guard ProcessInfo.processInfo.environment["PTB_PARITY"] == "1" else {
            throw XCTSkip("set PTB_PARITY=1 for the local Hermes smoke test")
        }
        let database = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".hermes/state.db")
        guard FileManager.default.fileExists(atPath: database.path) else {
            throw XCTSkip("no local Hermes state database")
        }
        let entries = LocalAdditionalUsageReader.hermesEntries(
            modifiedSince: LocalUsageReader.startOfMonth(Date()), roots: [database])
        XCTAssertFalse(entries.isEmpty)
        let today = LocalUsageReader.todayKey()
        let todayTotal = entries.filter { $0.localDay == today }.reduce(0) { $0 + $1.total }
        print("HERMES_NATIVE_PARITY entries=\(entries.count) today=\(todayTotal) month=\(entries.reduce(0) { $0 + $1.total })")
    }

    private func date(_ value: String) throws -> Date {
        try XCTUnwrap(ISO8601DateFormatter().date(from: value))
    }

    private func execute(_ databaseURL: URL, sql: String) throws {
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &database), SQLITE_OK)
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
