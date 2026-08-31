import SQLite3
import XCTest
@testable import PokeTokenBar

final class KunUsageTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PokeTokenBar-KunUsageTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
        temporaryDirectory = nil
    }

    func testKunDatabaseParsing() throws {
        let dbURL = temporaryDirectory.appendingPathComponent("index.sqlite3")
        try createKunDatabase(at: dbURL)

        let usageJSON = """
        {"promptTokens":1000,"completionTokens":200,"cachedTokens":300,"totalTokens":1200,"costUsd":0.05}
        """
        try insertEvent(at: dbURL, threadID: "thr_test_1", seq: 1, timestamp: "2026-08-20T10:00:00.000Z", model: "deepseek-v4-pro", usageJSON: usageJSON)

        let entries = LocalAdditionalUsageReader.kunEntries(modifiedSince: .distantPast, roots: [dbURL])
        XCTAssertEqual(entries.count, 1)

        let entry = try XCTUnwrap(entries.first)
        XCTAssertEqual(entry.id, "kun|thr_test_1|1")
        XCTAssertEqual(entry.model, "kun/deepseek-v4-pro")
        XCTAssertEqual(entry.input, 700) // 1000 - 300
        XCTAssertEqual(entry.output, 200)
        XCTAssertEqual(entry.cacheRead, 300)
        XCTAssertEqual(entry.total, 1200)
        XCTAssertEqual(entry.explicitCost, 0.05)
    }

    func testKunDatabaseFiltersByModifiedSince() throws {
        let dbURL = temporaryDirectory.appendingPathComponent("index.sqlite3")
        try createKunDatabase(at: dbURL)

        let usageJSON = """
        {"promptTokens":100,"completionTokens":50,"cachedTokens":0,"totalTokens":150,"costUsd":0.01}
        """
        try insertEvent(at: dbURL, threadID: "thr_old", seq: 1, timestamp: "2026-08-01T10:00:00.000Z", model: "deepseek-v4-pro", usageJSON: usageJSON)
        try insertEvent(at: dbURL, threadID: "thr_new", seq: 2, timestamp: "2026-08-20T10:00:00.000Z", model: "deepseek-v4-pro", usageJSON: usageJSON)

        let cutoff = ISO8601DateFormatter().date(from: "2026-08-15T00:00:00Z")!
        let entries = LocalAdditionalUsageReader.kunEntries(modifiedSince: cutoff, roots: [dbURL])
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.id, "kun|thr_new|2")
    }

    func testKunDatabaseComputesTurnDeltasForCumulativeEvents() throws {
        let dbURL = temporaryDirectory.appendingPathComponent("index.sqlite3")
        try createKunDatabase(at: dbURL)

        let turn1 = """
        {"promptTokens":1000,"completionTokens":200,"cachedTokens":300,"totalTokens":1200,"costUsd":0.05}
        """
        let turn2 = """
        {"promptTokens":2500,"completionTokens":500,"cachedTokens":800,"totalTokens":3000,"costUsd":0.12}
        """
        try insertEvent(at: dbURL, threadID: "thr_multi", seq: 1, timestamp: "2026-08-20T10:00:00.000Z", model: "deepseek-v4-pro", usageJSON: turn1)
        try insertEvent(at: dbURL, threadID: "thr_multi", seq: 2, timestamp: "2026-08-20T10:05:00.000Z", model: "deepseek-v4-pro", usageJSON: turn2)

        let entries = LocalAdditionalUsageReader.kunEntries(modifiedSince: .distantPast, roots: [dbURL])
        XCTAssertEqual(entries.count, 2)

        let e1 = entries[0]
        XCTAssertEqual(e1.total, 1200)
        XCTAssertEqual(e1.output, 200)
        XCTAssertEqual(e1.explicitCost, 0.05)

        let e2 = entries[1]
        XCTAssertEqual(e2.total, 1800) // 3000 - 1200
        XCTAssertEqual(e2.output, 300) // 500 - 200
        XCTAssertEqual(e2.cacheRead, 500) // 800 - 300
        XCTAssertEqual(e2.explicitCost ?? 0, 0.07, accuracy: 0.001) // 0.12 - 0.05
    }

    @MainActor
    func testDefaultRegistryIncludesKun() {
        let suite = "KunUsageTests.registry.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UsageStore(autoRefresh: false, defaults: defaults)
        XCTAssertTrue(store.registeredProviderIDs.contains("kun"))
    }

    // MARK: - SQLite Helpers

    private func createKunDatabase(at url: URL) throws {
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        let sql = """
        CREATE TABLE usage_events (
            thread_id TEXT NOT NULL,
            seq INTEGER NOT NULL,
            timestamp TEXT NOT NULL,
            turn_id TEXT,
            model TEXT,
            usage_json TEXT NOT NULL,
            PRIMARY KEY(thread_id, seq)
        );
        """
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
    }

    private func insertEvent(at url: URL, threadID: String, seq: Int64, timestamp: String, model: String, usageJSON: String) throws {
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        let sql = "INSERT INTO usage_events (thread_id, seq, timestamp, model, usage_json) VALUES (?, ?, ?, ?, ?)"
        var stmt: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(db, sql, -1, &stmt, nil), SQLITE_OK)
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, threadID, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_int64(stmt, 2, seq)
        sqlite3_bind_text(stmt, 3, timestamp, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_text(stmt, 4, model, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_text(stmt, 5, usageJSON, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        XCTAssertEqual(sqlite3_step(stmt), SQLITE_DONE)
    }
}
