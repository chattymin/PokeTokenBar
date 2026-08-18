import SQLite3
import XCTest
@testable import PokeTokenBar

/// Pins the shared incremental SQLite scanner (#157) on a format-neutral table.
/// Cursor and Copilot keep their own SQL/parse tests; these cover the scaffolding
/// that must not exist twice: failed-read ≠ shrink, empty incremental keeps the
/// watermark, and a reset in one root cold-rescans every root.
final class IncrementalStoreScanTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PokeTokenBar-IncrementalStoreScanTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
        temporaryDirectory = nil
    }

    func testFailedMaxIsNotAShrink() throws {
        let root = try seedRoot("a", ids: [1, 2])
        let first = scan(roots: [root])
        XCTAssertEqual(first.entries.count, 2)
        let watermark = first.highWaterRowID
        XCTAssertEqual(watermark, 2)

        try Data("not-a-sqlite-database".utf8).write(
            to: databaseURL(from: root), options: .atomic)

        let second = scan(roots: [root], afterRowIDByPath: first.highWaterByPath)
        XCTAssertFalse(second.didReset, "open/prepare failure must not look like VACUUM")
        XCTAssertEqual(second.highWaterRowID, watermark)
        XCTAssertTrue(second.entries.isEmpty)
    }

    func testEmptyIncrementalReadPreservesWatermark() throws {
        let root = try seedRoot("a", ids: [7])
        let first = scan(roots: [root])
        XCTAssertEqual(first.highWaterRowID, 7)

        let second = scan(roots: [root], afterRowIDByPath: first.highWaterByPath)
        XCTAssertTrue(second.entries.isEmpty)
        XCTAssertEqual(second.highWaterRowID, 7, "highWater == 0 must keep effectiveAfter")
        XCTAssertFalse(second.didReset)
    }

    func testIncrementalReadReturnsOnlyRowsAfterWatermark() throws {
        let root = try seedRoot("a", ids: [1])
        let first = scan(roots: [root])
        try insert(ids: [2], in: databaseURL(from: root))

        let second = scan(roots: [root], afterRowIDByPath: first.highWaterByPath)
        XCTAssertEqual(second.entries.map(\.id), ["scan|a-2"])
        XCTAssertEqual(second.highWaterRowID, 2)
        XCTAssertFalse(second.didReset)
    }

    func testShrinkInOneRootColdRescansEveryRoot() throws {
        let rootA = try seedRoot("a", ids: Array(1...5))
        let rootB = try seedRoot("b", ids: Array(1...5))
        let first = scan(roots: [rootA, rootB])
        XCTAssertEqual(first.entries.count, 10)
        XCTAssertEqual(first.highWaterByPath.count, 2)

        try FileManager.default.removeItem(at: databaseURL(from: rootB))
        try seed(ids: [1], in: databaseURL(from: rootB))

        let second = scan(roots: [rootA, rootB], afterRowIDByPath: first.highWaterByPath)
        XCTAssertTrue(second.didReset)
        XCTAssertEqual(
            second.entries.filter { $0.id.hasPrefix("scan|a-") }.count, 5,
            "root A must be in the reset payload, not only rows above its watermark")
        XCTAssertEqual(second.entries.filter { $0.id.hasPrefix("scan|b-") }.count, 1)
        XCTAssertEqual(second.entries.first { $0.id.hasPrefix("scan|b-") }?.id, "scan|b-1")
        let pathA = databaseURL(from: rootA).path
        XCTAssertEqual(
            second.highWaterByPath[pathA], first.highWaterByPath[pathA],
            "healthy root watermark must survive the other root's cold rescan")
    }

    // MARK: - Helpers

    private func scan(
        roots: [URL],
        afterRowIDByPath: [String: Int64]? = nil
    ) -> LocalAdditionalUsageReader.IncrementalStoreLoadResult {
        LocalAdditionalUsageReader.scanIncrementalStores(
            roots: roots,
            modifiedSince: Date(timeIntervalSince1970: 0),
            afterRowIDByPath: afterRowIDByPath,
            databaseURL: databaseURL(from:),
            maxRowIDSQL: "SELECT MAX(id) FROM events",
            rowSQL: { effectiveAfter, _ in
                LocalAdditionalUsageReader.IncrementalRowQuery(
                    sql: "SELECT id, created_at, tokens FROM events WHERE id > ?1",
                    bindInt64: effectiveAfter,
                    bindText: nil)
            },
            parse: { statement, database in
                let id = sqlite3_column_int64(statement, 0)
                guard let created = sqlite3_column_text(statement, 1) else { return nil }
                let tokens = Int(sqlite3_column_int64(statement, 2))
                guard let date = ISO8601DateFormatter().date(from: String(cString: created)) else {
                    return nil
                }
                let prefix = database.deletingLastPathComponent().lastPathComponent
                return LocalUsageReader.Entry(
                    id: "scan|\(prefix)-\(id)",
                    date: date,
                    localDay: "2026-01-04",
                    model: "test",
                    input: tokens,
                    output: 0,
                    cacheWrite: 0,
                    cacheRead: 0)
            })
    }

    private func databaseURL(from root: URL) -> URL {
        root.pathExtension == "db" ? root : root.appendingPathComponent("store.db")
    }

    private func seedRoot(_ name: String, ids: [Int]) throws -> URL {
        let root = temporaryDirectory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try seed(ids: ids, in: databaseURL(from: root))
        return root
    }

    private func seed(ids: [Int], in database: URL) throws {
        try execute(database, sql: """
        CREATE TABLE events (
            id INTEGER PRIMARY KEY,
            created_at TEXT NOT NULL,
            tokens INTEGER NOT NULL
        );
        """)
        try insert(ids: ids, in: database)
    }

    private func insert(ids: [Int], in database: URL) throws {
        guard !ids.isEmpty else { return }
        let values = ids.map { id in
            "(\(id), '2026-01-04T10:00:00Z', 10)"
        }.joined(separator: ", ")
        try execute(database, sql: "INSERT INTO events (id, created_at, tokens) VALUES \(values);")
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
