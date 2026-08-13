import SQLite3
import XCTest
@testable import PokeTokenBar

final class CursorUsageTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PokeTokenBar-CursorUsageTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
        temporaryDirectory = nil
    }

    // MARK: - End-to-end SQLite path

    func testCursorReadsBubbleTokensFromTempDatabase() throws {
        let database = temporaryDirectory.appendingPathComponent("state.vscdb")
        try execute(database, sql: """
        CREATE TABLE cursorDiskKV (key TEXT UNIQUE ON CONFLICT REPLACE, value BLOB);
        INSERT INTO cursorDiskKV VALUES (
            'bubbleId:tab-1:msg-1',
            '{"tokenCount":{"inputTokens":1500,"outputTokens":800},"createdAt":"2026-01-04T10:34:54.766Z","modelType":"claude-3.5-sonnet"}'
        );
        INSERT INTO cursorDiskKV VALUES (
            'composerData:other',
            '{"unrelated":true}'
        );
        INSERT INTO cursorDiskKV VALUES (
            'bubbleId:tab-1:msg-zero',
            '{"tokenCount":{"inputTokens":0,"outputTokens":0},"createdAt":"2026-01-04T11:00:00.000Z","modelType":"gpt-4o"}'
        );
        INSERT INTO cursorDiskKV VALUES (
            'bubbleid:tab-1:wrong-case',
            '{"tokenCount":{"inputTokens":999,"outputTokens":1},"createdAt":"2026-01-04T12:00:00.000Z","modelType":"gpt-4o"}'
        );
        """)

        let entries = LocalAdditionalUsageReader.cursorEntries(
            modifiedSince: try date("2026-01-01T00:00:00Z"),
            roots: [temporaryDirectory]).entries

        let entry = try XCTUnwrap(entries.first)
        XCTAssertEqual(entries.count, 1, "GLOB must be case-sensitive — lowercase bubbleid:* must not match")
        XCTAssertEqual(entry.input, 1500)
        XCTAssertEqual(entry.output, 800)
        XCTAssertEqual(entry.model, "claude-3.5-sonnet")
        XCTAssertEqual(entry.id, "cursor|bubbleId:tab-1:msg-1")
    }

    func testCursorIncrementalPrefersRowIDPlan() throws {
        let database = temporaryDirectory.appendingPathComponent("state.vscdb")
        try execute(database, sql: """
        CREATE TABLE cursorDiskKV (key TEXT UNIQUE ON CONFLICT REPLACE, value BLOB);
        INSERT INTO cursorDiskKV VALUES (
            'bubbleId:tab:a',
            '{"tokenCount":{"inputTokens":100,"outputTokens":50},"createdAt":"2026-01-04T10:00:00.000Z","modelType":"gpt-4o"}'
        );
        """)
        let first = LocalAdditionalUsageReader.cursorEntries(
            modifiedSince: try date("2026-01-01T00:00:00Z"),
            roots: [temporaryDirectory])
        XCTAssertGreaterThan(first.highWaterRowID, 0)

        let plan = try XCTUnwrap(LocalAdditionalUsageReader.cursorIncrementalQueryPlan(
            database: database, afterRowID: first.highWaterRowID))
        XCTAssertFalse(
            plan.localizedCaseInsensitiveContains("cursorDiskKV_1")
                || plan.localizedCaseInsensitiveContains("USING INDEX"),
            "incremental scan must not walk the key index over all bubbleId:* history; plan was: \(plan)")
        XCTAssertTrue(
            plan.localizedCaseInsensitiveContains("rowid")
                || plan.localizedCaseInsensitiveContains("SCAN"),
            "expected a rowid/table scan plan; got: \(plan)")
    }

    func testCursorWatermarkResetsWhenDatabaseIsReplaced() throws {
        let database = temporaryDirectory.appendingPathComponent("state.vscdb")
        try execute(database, sql: """
        CREATE TABLE cursorDiskKV (key TEXT UNIQUE ON CONFLICT REPLACE, value BLOB);
        INSERT INTO cursorDiskKV VALUES (
            'bubbleId:tab:old',
            '{"tokenCount":{"inputTokens":100,"outputTokens":50},"createdAt":"2026-01-04T10:00:00.000Z","modelType":"gpt-4o"}'
        );
        INSERT INTO cursorDiskKV VALUES (
            'bubbleId:tab:old2',
            '{"tokenCount":{"inputTokens":110,"outputTokens":50},"createdAt":"2026-01-04T10:01:00.000Z","modelType":"gpt-4o"}'
        );
        """)
        let first = LocalAdditionalUsageReader.cursorEntries(
            modifiedSince: try date("2026-01-01T00:00:00Z"),
            roots: [temporaryDirectory])
        XCTAssertEqual(first.entries.count, 2)
        let staleHighWater = first.highWaterRowID
        XCTAssertGreaterThan(staleHighWater, 1)

        // Recreate DB at the same path with lower rowids (simulates Cursor rewrite / VACUUM).
        try FileManager.default.removeItem(at: database)
        try execute(database, sql: """
        CREATE TABLE cursorDiskKV (key TEXT UNIQUE ON CONFLICT REPLACE, value BLOB);
        INSERT INTO cursorDiskKV VALUES (
            'bubbleId:tab:new',
            '{"tokenCount":{"inputTokens":200,"outputTokens":80},"createdAt":"2026-01-04T11:00:00.000Z","modelType":"gpt-4o"}'
        );
        """)

        let second = LocalAdditionalUsageReader.cursorEntries(
            modifiedSince: try date("2026-01-01T00:00:00Z"),
            afterRowID: staleHighWater,
            roots: [temporaryDirectory])
        XCTAssertTrue(second.didReset, "watermark above max(rowid) must force a full rescan")
        XCTAssertEqual(second.entries.count, 1)
        XCTAssertEqual(second.entries.first?.id, "cursor|bubbleId:tab:new")
    }

    /// Transient open/prepare failure must not look like a DB shrink — keep the watermark
    /// and leave didReset false so the in-memory cache is not wiped to zero for a cycle.
    func testCursorUnreadableDatabaseKeepsWatermarkAndDoesNotReset() throws {
        let database = temporaryDirectory.appendingPathComponent("state.vscdb")
        try execute(database, sql: """
        CREATE TABLE cursorDiskKV (key TEXT UNIQUE ON CONFLICT REPLACE, value BLOB);
        INSERT INTO cursorDiskKV VALUES (
            'bubbleId:tab:a',
            '{"tokenCount":{"inputTokens":100,"outputTokens":50},"createdAt":"2026-01-04T10:00:00.000Z","modelType":"gpt-4o"}'
        );
        """)
        let first = LocalAdditionalUsageReader.cursorEntries(
            modifiedSince: try date("2026-01-01T00:00:00Z"),
            roots: [temporaryDirectory])
        let watermark = first.highWaterRowID
        XCTAssertGreaterThan(watermark, 0)

        // Corrupt the file so SQLite open/prepare fails (owner repro: non-database bytes).
        try Data("not-a-sqlite-database".utf8).write(to: database, options: .atomic)

        let second = LocalAdditionalUsageReader.cursorEntries(
            modifiedSince: try date("2026-01-01T00:00:00Z"),
            afterRowID: watermark,
            roots: [temporaryDirectory])
        XCTAssertFalse(second.didReset, "failed read must not be treated as a shrink")
        XCTAssertEqual(
            second.highWaterRowID, watermark,
            "watermark must survive an unreadable cycle")
        XCTAssertTrue(second.entries.isEmpty)
    }

    /// Resetting one root must cold-rescan every root so the cache replacement payload
    /// still contains history from roots that were only scanned incrementally.
    func testCursorResetInOneRootKeepsOtherRootHistory() throws {
        let rootA = temporaryDirectory.appendingPathComponent("CursorA")
        let rootB = temporaryDirectory.appendingPathComponent("CursorB")
        try FileManager.default.createDirectory(at: rootA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: rootB, withIntermediateDirectories: true)

        try seedBubbles(in: rootA.appendingPathComponent("state.vscdb"), prefix: "a", count: 5)
        try seedBubbles(in: rootB.appendingPathComponent("state.vscdb"), prefix: "b", count: 5)

        let since = try date("2026-01-01T00:00:00Z")
        let first = LocalAdditionalUsageReader.cursorEntries(
            modifiedSince: since, roots: [rootA, rootB])
        XCTAssertEqual(first.entries.count, 10)
        XCTAssertFalse(first.didReset)
        let marks = first.highWaterByPath
        XCTAssertEqual(marks.count, 2)

        // Rewrite only root B with a lower max(rowid) — Stable+Nightly style dual-root reset.
        let dbB = rootB.appendingPathComponent("state.vscdb")
        try FileManager.default.removeItem(at: dbB)
        try seedBubbles(in: dbB, prefix: "b-new", count: 1)

        let second = LocalAdditionalUsageReader.cursorEntries(
            modifiedSince: since,
            afterRowIDByPath: marks,
            roots: [rootA, rootB])
        XCTAssertTrue(second.didReset)
        let aIDs = second.entries.map(\.id).filter { $0.contains("bubbleId:a:") }
        XCTAssertEqual(
            aIDs.count, 5,
            "root A history must be in the reset payload (got \(second.entries.map(\.id)))")
        XCTAssertEqual(second.entries.filter { $0.id.contains("bubbleId:b-new:") }.count, 1)
        XCTAssertFalse(
            second.entries.contains { $0.id.contains("bubbleId:b:") && !$0.id.contains("b-new") },
            "old root B bubbles must not linger after its rewrite")
        let pathA = rootA.appendingPathComponent("state.vscdb").path
        XCTAssertEqual(
            second.highWaterByPath[pathA], marks[pathA],
            "healthy root watermark must survive the other root's cold rescan")
    }

    func testCursorSkipsBubblesBeforeModifiedSince() throws {
        let database = temporaryDirectory.appendingPathComponent("state.vscdb")
        try execute(database, sql: """
        CREATE TABLE cursorDiskKV (key TEXT UNIQUE ON CONFLICT REPLACE, value BLOB);
        INSERT INTO cursorDiskKV VALUES (
            'bubbleId:tab:old',
            '{"tokenCount":{"inputTokens":10,"outputTokens":5},"createdAt":"2025-12-01T00:00:00.000Z","modelType":"gpt-4o"}'
        );
        INSERT INTO cursorDiskKV VALUES (
            'bubbleId:tab:new',
            '{"tokenCount":{"inputTokens":20,"outputTokens":10},"createdAt":"2026-01-10T00:00:00.000Z","modelType":"gpt-4o"}'
        );
        """)

        let entries = LocalAdditionalUsageReader.cursorEntries(
            modifiedSince: try date("2026-01-01T00:00:00Z"),
            roots: [temporaryDirectory]).entries

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.id, "cursor|bubbleId:tab:new")
    }

    func testCursorIncrementalScanUsesRowIDHighWater() throws {
        let database = temporaryDirectory.appendingPathComponent("state.vscdb")
        try execute(database, sql: """
        CREATE TABLE cursorDiskKV (key TEXT UNIQUE ON CONFLICT REPLACE, value BLOB);
        INSERT INTO cursorDiskKV VALUES (
            'bubbleId:tab:a',
            '{"tokenCount":{"inputTokens":100,"outputTokens":50},"createdAt":"2026-01-04T10:00:00.000Z","modelType":"gpt-4o"}'
        );
        """)

        let first = LocalAdditionalUsageReader.cursorEntries(
            modifiedSince: try date("2026-01-01T00:00:00Z"),
            roots: [temporaryDirectory])
        XCTAssertEqual(first.entries.count, 1)
        XCTAssertGreaterThan(first.highWaterRowID, 0)

        try execute(database, sql: """
        INSERT INTO cursorDiskKV VALUES (
            'bubbleId:tab:b',
            '{"tokenCount":{"inputTokens":200,"outputTokens":80},"createdAt":"2026-01-04T11:00:00.000Z","modelType":"gpt-4o"}'
        );
        """)

        let second = LocalAdditionalUsageReader.cursorEntries(
            modifiedSince: try date("2026-01-01T00:00:00Z"),
            afterRowID: first.highWaterRowID,
            roots: [temporaryDirectory])
        XCTAssertEqual(second.entries.count, 1)
        XCTAssertEqual(second.entries.first?.id, "cursor|bubbleId:tab:b")
        XCTAssertGreaterThan(second.highWaterRowID, first.highWaterRowID)
    }

    func testCursorEmptyIncrementalReadPreservesWatermark() throws {
        let database = temporaryDirectory.appendingPathComponent("state.vscdb")
        try execute(database, sql: """
        CREATE TABLE cursorDiskKV (key TEXT UNIQUE ON CONFLICT REPLACE, value BLOB);
        INSERT INTO cursorDiskKV VALUES (
            'bubbleId:tab:a',
            '{"tokenCount":{"inputTokens":100,"outputTokens":50},"createdAt":"2026-01-04T10:00:00.000Z","modelType":"gpt-4o"}'
        );
        """)
        let since = try date("2026-01-01T00:00:00Z")
        let first = LocalAdditionalUsageReader.cursorEntries(
            modifiedSince: since, roots: [temporaryDirectory])
        XCTAssertGreaterThan(first.highWaterRowID, 0)

        let second = LocalAdditionalUsageReader.cursorEntries(
            modifiedSince: since, afterRowID: first.highWaterRowID, roots: [temporaryDirectory])
        XCTAssertTrue(second.entries.isEmpty)
        XCTAssertEqual(second.highWaterRowID, first.highWaterRowID)
        XCTAssertFalse(second.didReset)
    }

    func testParseCursorBubbleAcceptsNumericCreatedAt() {
        let bubble: [String: Any] = [
            "tokenCount": ["inputTokens": 10, "outputTokens": 5] as [String: Any],
            "createdAt": 1_767_312_000_000,
            "modelType": "gpt-4o",
        ]
        let entry = LocalAdditionalUsageReader.parseCursorBubble(
            bubble, key: "bubbleId:t:m", modifiedSince: .distantPast)
        XCTAssertNotNil(entry, "numeric createdAt (millis) should parse like OpenCode dates")
        XCTAssertEqual(entry?.input, 10)
    }

    func testParseCursorBubbleAcceptsNumericCreatedAtSeconds() {
        let bubble: [String: Any] = [
            "tokenCount": ["inputTokens": 7, "outputTokens": 3] as [String: Any],
            "createdAt": 1_767_312_000,
            "modelType": "gpt-4o",
        ]
        let entry = LocalAdditionalUsageReader.parseCursorBubble(
            bubble, key: "bubbleId:t:m", modifiedSince: .distantPast)
        XCTAssertNotNil(entry, "numeric createdAt (seconds) should parse")
        XCTAssertEqual(entry?.total, 10)
    }

    func testDefaultCursorRootsIncludeStableAndNightly() throws {
        if ProcessInfo.processInfo.environment["CURSOR_DATA_DIR"] != nil {
            throw XCTSkip("CURSOR_DATA_DIR override is set — default roots not used")
        }
        let roots = LocalAdditionalUsageReader.defaultCursorRoots
        let paths = roots.map(\.path)
        XCTAssertTrue(paths.contains { $0.contains("/Cursor/User/globalStorage") })
        XCTAssertTrue(paths.contains { $0.contains("/Cursor Nightly/User/globalStorage") })
    }

    // MARK: - Bubble parsing

    func testParseCursorBubbleWithTokens() {
        let now = Date()
        let bubble: [String: Any] = [
            "type": 1,
            "modelType": "claude-3.5-sonnet",
            "createdAt": ISO8601DateFormatter().string(from: now),
            "tokenCount": [
                "inputTokens": 1500,
                "outputTokens": 800,
            ] as [String: Any],
        ]
        let entry = LocalAdditionalUsageReader.parseCursorBubble(
            bubble, key: "bubbleId:tab1:msg1", modifiedSince: .distantPast)
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.input, 1500)
        XCTAssertEqual(entry?.output, 800)
        XCTAssertEqual(entry?.model, "claude-3.5-sonnet")
        XCTAssertTrue(entry?.id.hasPrefix("cursor|") ?? false)
    }

    func testParseCursorBubbleWithFractionalSeconds() {
        let bubble: [String: Any] = [
            "tokenCount": ["inputTokens": 100, "outputTokens": 50] as [String: Any],
            "createdAt": "2026-01-04T10:34:54.766Z",
            "modelType": "gpt-4o",
        ]
        let entry = LocalAdditionalUsageReader.parseCursorBubble(
            bubble, key: "bubbleId:t:m", modifiedSince: .distantPast)
        XCTAssertNotNil(entry, "ISO 8601 with fractional seconds should parse")
        XCTAssertEqual(entry?.input, 100)
        XCTAssertEqual(entry?.output, 50)
        XCTAssertEqual(entry?.model, "gpt-4o")
    }

    func testParseCursorBubbleIgnoresZeroTokens() {
        let bubble: [String: Any] = [
            "tokenCount": ["inputTokens": 0, "outputTokens": 0] as [String: Any],
            "createdAt": ISO8601DateFormatter().string(from: Date()),
        ]
        let entry = LocalAdditionalUsageReader.parseCursorBubble(
            bubble, key: "bubbleId:t:m", modifiedSince: .distantPast)
        XCTAssertNil(entry, "Zero-token entries should be skipped")
    }

    func testParseCursorBubbleIgnoresOldEntries() {
        let yesterday = Date().addingTimeInterval(-86400)
        let bubble: [String: Any] = [
            "tokenCount": ["inputTokens": 100, "outputTokens": 50] as [String: Any],
            "createdAt": ISO8601DateFormatter().string(from: yesterday),
        ]
        let entry = LocalAdditionalUsageReader.parseCursorBubble(
            bubble, key: "bubbleId:t:m", modifiedSince: Date())
        XCTAssertNil(entry, "Entries before modifiedSince should be skipped")
    }

    func testParseCursorBubbleMissingTokenCount() {
        let bubble: [String: Any] = [
            "type": 1,
            "modelType": "gpt-4",
            "createdAt": ISO8601DateFormatter().string(from: Date()),
        ]
        let entry = LocalAdditionalUsageReader.parseCursorBubble(
            bubble, key: "bubbleId:t:m", modifiedSince: .distantPast)
        XCTAssertNil(entry, "Missing tokenCount should be skipped")
    }

    func testParseCursorBubbleMissingModelFallsBackToUnknown() {
        let bubble: [String: Any] = [
            "tokenCount": ["inputTokens": 100, "outputTokens": 50] as [String: Any],
            "createdAt": ISO8601DateFormatter().string(from: Date()),
        ]
        let entry = LocalAdditionalUsageReader.parseCursorBubble(
            bubble, key: "bubbleId:t:m", modifiedSince: .distantPast)
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.model, "unknown")
    }

    func testParseCursorBubbleMissingCreatedAt() {
        let bubble: [String: Any] = [
            "tokenCount": ["inputTokens": 100, "outputTokens": 50] as [String: Any],
        ]
        let entry = LocalAdditionalUsageReader.parseCursorBubble(
            bubble, key: "bubbleId:t:m", modifiedSince: .distantPast)
        XCTAssertNil(entry, "Missing createdAt should be skipped")
    }

    func testParseCursorBubbleInvalidCreatedAt() {
        let bubble: [String: Any] = [
            "tokenCount": ["inputTokens": 100, "outputTokens": 50] as [String: Any],
            "createdAt": "not-a-date",
        ]
        let entry = LocalAdditionalUsageReader.parseCursorBubble(
            bubble, key: "bubbleId:t:m", modifiedSince: .distantPast)
        XCTAssertNil(entry, "Invalid createdAt should be skipped")
    }

    func testParseCursorBubbleIdPrefix() {
        let bubble: [String: Any] = [
            "tokenCount": ["inputTokens": 100, "outputTokens": 50] as [String: Any],
            "createdAt": ISO8601DateFormatter().string(from: Date()),
        ]
        let entry = LocalAdditionalUsageReader.parseCursorBubble(
            bubble, key: "bubbleId:abc:def", modifiedSince: .distantPast)
        XCTAssertEqual(entry?.id, "cursor|bubbleId:abc:def")
    }

    // MARK: - cursorEntries with nonexistent path

    func testCursorEntriesNonexistentPath() {
        let result = LocalAdditionalUsageReader.cursorEntries(
            modifiedSince: .distantPast,
            roots: [URL(fileURLWithPath: "/nonexistent/cursor/path")])
        XCTAssertTrue(result.entries.isEmpty, "Nonexistent database should return empty")
        XCTAssertEqual(result.highWaterRowID, 0)
    }

    // MARK: - Provider identity

    func testLocalCursorProviderID() {
        let provider = LocalCursorProvider()
        XCTAssertEqual(provider.id, "cursor")
        XCTAssertEqual(provider.displayName, "Cursor")
        XCTAssertFalse(provider.reportsCost, "Cursor is flat-rate — tokens only, no invented cost")
    }

    // MARK: - Helpers

    private func date(_ value: String) throws -> Date {
        try XCTUnwrap(ISO8601DateFormatter().date(from: value))
    }

    private func seedBubbles(in database: URL, prefix: String, count: Int) throws {
        var statements = [
            "CREATE TABLE cursorDiskKV (key TEXT UNIQUE ON CONFLICT REPLACE, value BLOB);"
        ]
        for i in 0..<count {
            let key = "bubbleId:\(prefix):\(i)"
            let json = """
            {"tokenCount":{"inputTokens":\(10 + i),"outputTokens":5},"createdAt":"2026-01-04T10:\(String(format: "%02d", i)):00.000Z","modelType":"gpt-4o"}
            """
            let escaped = json.replacingOccurrences(of: "'", with: "''")
            statements.append("INSERT INTO cursorDiskKV VALUES ('\(key)', '\(escaped)');")
        }
        try execute(database, sql: statements.joined(separator: "\n"))
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
