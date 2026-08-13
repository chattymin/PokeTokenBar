import SQLite3
import XCTest
@testable import PokeTokenBar

final class CopilotUsageTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PokeTokenBar-CopilotUsageTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
        temporaryDirectory = nil
    }

    // MARK: - Token accounting

    /// Copilot stores `input_tokens` as the *whole* prompt, with cached reads/writes as a
    /// subset of it. Adding the columns as-is would triple-count every cached prompt, so the
    /// reader must subtract them — this is the accounting fault the parser exists to avoid.
    func testCachedPromptTokensAreNotCountedTwice() throws {
        try seed(rows: [
            Row(id: 1, model: "claude-opus-5", input: 43_792, output: 443,
                cacheRead: 42_698, cacheWrite: 904, reasoning: 59,
                createdAt: "2026-01-04T10:00:00.000Z"),
        ])

        let entries = LocalAdditionalUsageReader.copilotEntries(
            modifiedSince: try date("2026-01-01T00:00:00Z"), roots: [temporaryDirectory]).entries

        let entry = try XCTUnwrap(entries.first)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entry.input, 190, "uncached prompt = input_tokens - cache_read - cache_write")
        XCTAssertEqual(entry.cacheRead, 42_698)
        XCTAssertEqual(entry.cacheWrite, 904)
        XCTAssertEqual(entry.output, 443, "reasoning_tokens is a breakdown of output, not an extra charge")
        XCTAssertEqual(entry.total, 44_235, "total must equal the prompt plus the completion, counted once")
        XCTAssertEqual(entry.id, entryID(1))
        XCTAssertEqual(entry.model, "claude-opus-5")
    }

    func testFullyCachedPromptKeepsZeroUncachedInput() throws {
        try seed(rows: [
            Row(id: 1, model: "gpt-5.4-mini", input: 57_375, output: 35,
                cacheRead: 57_375, cacheWrite: 0, reasoning: 0,
                createdAt: "2026-01-04T10:00:00.000Z"),
        ])

        let entry = try XCTUnwrap(LocalAdditionalUsageReader.copilotEntries(
            modifiedSince: try date("2026-01-01T00:00:00Z"), roots: [temporaryDirectory]).entries.first)
        XCTAssertEqual(entry.input, 0)
        XCTAssertEqual(entry.total, 57_410)
    }

    // MARK: - Timestamps

    /// The column default is `datetime('now')` ("YYYY-MM-DD HH:MM:SS", UTC) while the CLI
    /// writes ISO-8601 with a "Z". Both shapes must land in the same window.
    func testReadsBothStoredTimestampShapes() throws {
        try seed(rows: [
            Row(id: 1, model: "claude-opus-5", input: 100, output: 10,
                cacheRead: 0, cacheWrite: 0, reasoning: 0, createdAt: "2026-01-04T10:00:00.000Z"),
            Row(id: 2, model: "claude-opus-5", input: 200, output: 20,
                cacheRead: 0, cacheWrite: 0, reasoning: 0, createdAt: "2026-01-04 11:00:00"),
        ])

        let entries = LocalAdditionalUsageReader.copilotEntries(
            modifiedSince: try date("2026-01-01T00:00:00Z"), roots: [temporaryDirectory]).entries

        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.map(\.date).sorted(),
                       [try date("2026-01-04T10:00:00Z"), try date("2026-01-04T11:00:00Z")])
    }

    /// The SQL cutoff is a lexicographic compare on text. A same-day ISO row sorts *after*
    /// the space-separated day boundary, so rounding down to the UTC day must not drop it.
    func testDayBoundaryCutoffKeepsSameDayIsoRows() throws {
        try seed(rows: [
            Row(id: 1, model: "claude-opus-5", input: 100, output: 10,
                cacheRead: 0, cacheWrite: 0, reasoning: 0, createdAt: "2026-01-04T00:00:01.000Z"),
            Row(id: 2, model: "claude-opus-5", input: 200, output: 20,
                cacheRead: 0, cacheWrite: 0, reasoning: 0, createdAt: "2026-01-03T23:59:59.000Z"),
        ])

        let entries = LocalAdditionalUsageReader.copilotEntries(
            modifiedSince: try date("2026-01-04T12:00:00Z"), roots: [temporaryDirectory]).entries

        XCTAssertEqual(entries.count, 0, "both rows precede the window and are filtered exactly")

        let wider = LocalAdditionalUsageReader.copilotEntries(
            modifiedSince: try date("2026-01-04T00:00:00Z"), roots: [temporaryDirectory]).entries
        XCTAssertEqual(wider.map(\.id), [entryID(1)], "the earlier day must stay out, the same day must stay in")
    }

    /// A row can carry a UTC offset, and a negative one renders an earlier calendar day than
    /// the instant it represents. The coarse text cutoff must not drop it — the row would be
    /// lost for good once a later id advances the watermark.
    func testNegativeUTCOffsetRowIsNotDroppedByTheTextCutoff() throws {
        try seed(rows: [
            // 2026-01-04T01:00:00Z, but its text sorts on 2026-01-03.
            Row(id: 1, model: "claude-opus-5", input: 100, output: 10,
                cacheRead: 0, cacheWrite: 0, reasoning: 0, createdAt: "2026-01-03T20:00:00-05:00"),
        ])

        let entries = LocalAdditionalUsageReader.copilotEntries(
            modifiedSince: try date("2026-01-04T00:00:00Z"), roots: [temporaryDirectory]).entries

        XCTAssertEqual(entries.map(\.id), [entryID(1)])
        XCTAssertEqual(entries.first?.date, try date("2026-01-04T01:00:00Z"),
                       "the offset must be applied, not ignored")
    }

    func testRowsWithoutTokensAreSkipped() throws {
        try seed(rows: [
            Row(id: 1, model: "claude-opus-5", input: 0, output: 0,
                cacheRead: 0, cacheWrite: 0, reasoning: 0, createdAt: "2026-01-04T10:00:00.000Z"),
            Row(id: 2, model: "claude-opus-5", input: 5, output: 1,
                cacheRead: 0, cacheWrite: 0, reasoning: 0, createdAt: "2026-01-04T10:01:00.000Z"),
        ])

        let entries = LocalAdditionalUsageReader.copilotEntries(
            modifiedSince: try date("2026-01-01T00:00:00Z"), roots: [temporaryDirectory]).entries
        XCTAssertEqual(entries.map(\.id), [entryID(2)])
    }

    // MARK: - Incremental reads

    func testIncrementalReadReturnsOnlyRowsAfterTheWatermark() throws {
        try seed(rows: [
            Row(id: 1, model: "claude-opus-5", input: 100, output: 10,
                cacheRead: 0, cacheWrite: 0, reasoning: 0, createdAt: "2026-01-04T10:00:00.000Z"),
        ])
        let since = try date("2026-01-01T00:00:00Z")

        let first = LocalAdditionalUsageReader.copilotEntries(modifiedSince: since, roots: [temporaryDirectory])
        XCTAssertEqual(first.entries.count, 1)
        XCTAssertEqual(first.highWaterRowID, 1)
        XCTAssertFalse(first.didReset)

        try insert(rows: [
            Row(id: 2, model: "claude-opus-5", input: 300, output: 30,
                cacheRead: 0, cacheWrite: 0, reasoning: 0, createdAt: "2026-01-04T11:00:00.000Z"),
        ])

        let second = LocalAdditionalUsageReader.copilotEntries(
            modifiedSince: since, afterRowIDByPath: first.highWaterByPath, roots: [temporaryDirectory])
        XCTAssertEqual(second.entries.map(\.id), [entryID(2)], "already-read rows must not be replayed")
        XCTAssertEqual(second.highWaterRowID, 2)
    }

    /// An incremental read that finds nothing must keep the watermark — resetting it to zero
    /// would replay the whole store on the next refresh.
    func testEmptyIncrementalReadPreservesTheWatermark() throws {
        try seed(rows: [
            Row(id: 7, model: "claude-opus-5", input: 100, output: 10,
                cacheRead: 0, cacheWrite: 0, reasoning: 0, createdAt: "2026-01-04T10:00:00.000Z"),
        ])
        let since = try date("2026-01-01T00:00:00Z")
        let first = LocalAdditionalUsageReader.copilotEntries(modifiedSince: since, roots: [temporaryDirectory])

        let second = LocalAdditionalUsageReader.copilotEntries(
            modifiedSince: since, afterRowIDByPath: first.highWaterByPath, roots: [temporaryDirectory])
        XCTAssertTrue(second.entries.isEmpty)
        XCTAssertEqual(second.highWaterRowID, 7)
        XCTAssertFalse(second.didReset)
    }

    /// A pruned or recreated session store restarts ids below the watermark. The reader must
    /// report the reset so the provider cache drops rows whose ids now mean something else.
    func testRecreatedStoreBelowWatermarkTriggersColdRescan() throws {
        try seed(rows: (1...5).map {
            Row(id: $0, model: "claude-opus-5", input: 100, output: 10,
                cacheRead: 0, cacheWrite: 0, reasoning: 0,
                createdAt: "2026-01-04T10:0\($0):00.000Z")
        })
        let since = try date("2026-01-01T00:00:00Z")
        let first = LocalAdditionalUsageReader.copilotEntries(modifiedSince: since, roots: [temporaryDirectory])
        XCTAssertEqual(first.highWaterRowID, 5)

        // Really recreate the store, the way `copilot` does when its session data is cleared.
        try FileManager.default.removeItem(at: databaseURL)
        try seed(rows: [
            Row(id: 1, model: "claude-opus-5", input: 700, output: 70,
                cacheRead: 0, cacheWrite: 0, reasoning: 0, createdAt: "2026-01-05T10:00:00.000Z"),
        ])

        let result = LocalAdditionalUsageReader.copilotEntries(
            modifiedSince: since, afterRowIDByPath: first.highWaterByPath, roots: [temporaryDirectory])

        XCTAssertTrue(result.didReset, "ids restarting below the watermark must force a cold rescan")
        XCTAssertEqual(result.entries.map(\.id), [entryID(1)])
        XCTAssertEqual(result.entries.first?.total, 770, "the rescan must return the new store's rows")
        XCTAssertEqual(result.highWaterRowID, 1)
    }

    /// Copilot-only path for the shared scanner (#157): a failed open/prepare must
    /// not look like a shrink. Cursor already covers this; A||B needs B alone.
    func testUnreadableDatabaseKeepsWatermarkAndDoesNotReset() throws {
        try seed(rows: [
            Row(id: 1, model: "claude-opus-5", input: 100, output: 10,
                cacheRead: 0, cacheWrite: 0, reasoning: 0, createdAt: "2026-01-04T10:00:00.000Z"),
        ])
        let since = try date("2026-01-01T00:00:00Z")
        let first = LocalAdditionalUsageReader.copilotEntries(modifiedSince: since, roots: [temporaryDirectory])
        let watermark = first.highWaterRowID
        XCTAssertGreaterThan(watermark, 0)

        try Data("not-a-sqlite-database".utf8).write(to: databaseURL, options: .atomic)

        let second = LocalAdditionalUsageReader.copilotEntries(
            modifiedSince: since, afterRowIDByPath: first.highWaterByPath, roots: [temporaryDirectory])
        XCTAssertFalse(second.didReset, "failed read must not be treated as a shrink")
        XCTAssertEqual(second.highWaterRowID, watermark)
        XCTAssertTrue(second.entries.isEmpty)
    }

    /// Copilot-only dual-root reset: rewriting one store must still return the
    /// other store's history in the replacement payload.
    func testResetInOneRootKeepsOtherRootHistory() throws {
        try seed(rows: (1...5).map {
            Row(id: $0, model: "claude-opus-5", input: 100, output: 10,
                cacheRead: 0, cacheWrite: 0, reasoning: 0,
                createdAt: "2026-01-04T10:0\($0):00.000Z")
        })
        let otherRoot = temporaryDirectory.appendingPathComponent("other")
        try FileManager.default.createDirectory(at: otherRoot, withIntermediateDirectories: true)
        let otherDatabase = otherRoot.appendingPathComponent("session-store.db")
        try seed(rows: (1...5).map {
            Row(id: $0, model: "gpt-5.4-mini", input: 200, output: 20,
                cacheRead: 0, cacheWrite: 0, reasoning: 0,
                createdAt: "2026-01-04T11:0\($0):00.000Z")
        }, in: otherDatabase)

        let since = try date("2026-01-01T00:00:00Z")
        let first = LocalAdditionalUsageReader.copilotEntries(
            modifiedSince: since, roots: [temporaryDirectory, otherRoot])
        XCTAssertEqual(first.entries.count, 10)

        try FileManager.default.removeItem(at: otherDatabase)
        try seed(rows: [
            Row(id: 1, model: "gpt-5.4-mini", input: 700, output: 70,
                cacheRead: 0, cacheWrite: 0, reasoning: 0, createdAt: "2026-01-05T10:00:00.000Z"),
        ], in: otherDatabase)

        let second = LocalAdditionalUsageReader.copilotEntries(
            modifiedSince: since, afterRowIDByPath: first.highWaterByPath,
            roots: [temporaryDirectory, otherRoot])
        XCTAssertTrue(second.didReset)
        XCTAssertEqual(
            second.entries.filter { $0.id.hasPrefix("copilot|\(databaseURL.path)|") }.count, 5,
            "first store history must be in the reset payload")
        XCTAssertEqual(second.entries.filter { $0.id.hasPrefix("copilot|\(otherDatabase.path)|") }.map(\.id),
                       [entryID(1, in: otherDatabase)])
        XCTAssertEqual(
            second.highWaterByPath[databaseURL.path], first.highWaterByPath[databaseURL.path],
            "healthy store watermark must survive the other store's cold rescan")
    }

    // MARK: - Multiple stores

    /// `$COPILOT_HOME` may name more than one store, and each numbers its rows from 1. Keying
    /// entries on the row id alone would let dedup collapse two unrelated events into one.
    func testTwoStoresWithTheSameRowIDsAreBothCounted() throws {
        try seed(rows: [
            Row(id: 1, model: "claude-opus-5", input: 100, output: 10,
                cacheRead: 0, cacheWrite: 0, reasoning: 0, createdAt: "2026-01-04T10:00:00.000Z"),
        ])
        let otherRoot = temporaryDirectory.appendingPathComponent("other")
        try FileManager.default.createDirectory(at: otherRoot, withIntermediateDirectories: true)
        let otherDatabase = otherRoot.appendingPathComponent("session-store.db")
        try seed(rows: [
            Row(id: 1, model: "gpt-5.4-mini", input: 400, output: 40,
                cacheRead: 0, cacheWrite: 0, reasoning: 0, createdAt: "2026-01-04T11:00:00.000Z"),
        ], in: otherDatabase)

        let result = LocalAdditionalUsageReader.copilotEntries(
            modifiedSince: try date("2026-01-01T00:00:00Z"),
            roots: [temporaryDirectory, otherRoot])

        XCTAssertEqual(Set(result.entries.map(\.id)),
                       [entryID(1), entryID(1, in: otherDatabase)])
        XCTAssertEqual(result.entries.reduce(0) { $0 + $1.total }, 110 + 440,
                       "neither store's usage may be swallowed by the other")
        XCTAssertEqual(result.highWaterByPath.count, 2, "each store keeps its own watermark")
    }

    // MARK: - Roots

    func testAcceptsADirectDatabasePathAsRoot() throws {
        try seed(rows: [
            Row(id: 1, model: "claude-opus-5", input: 100, output: 10,
                cacheRead: 0, cacheWrite: 0, reasoning: 0, createdAt: "2026-01-04T10:00:00.000Z"),
        ])

        let entries = LocalAdditionalUsageReader.copilotEntries(
            modifiedSince: try date("2026-01-01T00:00:00Z"),
            roots: [temporaryDirectory.appendingPathComponent("session-store.db")]).entries
        XCTAssertEqual(entries.count, 1)
    }

    func testNonexistentRootReturnsNothing() {
        let result = LocalAdditionalUsageReader.copilotEntries(
            modifiedSince: .distantPast, roots: [URL(fileURLWithPath: "/nonexistent/copilot/home")])
        XCTAssertTrue(result.entries.isEmpty)
        XCTAssertEqual(result.highWaterRowID, 0)
        XCTAssertFalse(result.didReset)
    }

    func testDefaultRootIsTheCopilotHome() {
        let expected = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".copilot")
        let roots = LocalAdditionalUsageReader.defaultCopilotRoots
        if ProcessInfo.processInfo.environment["COPILOT_HOME"] == nil {
            XCTAssertEqual(roots, [expected])
        }
        XCTAssertFalse(roots.isEmpty)
    }

    // MARK: - Aggregation

    func testDailyAggregatesEveryUsageEventOfTheDay() throws {
        try seed(rows: [
            Row(id: 1, model: "claude-opus-5", input: 100, output: 10,
                cacheRead: 0, cacheWrite: 0, reasoning: 0, createdAt: "2026-01-04T10:00:00.000Z"),
            Row(id: 2, model: "gpt-5.4-mini", input: 250, output: 40,
                cacheRead: 50, cacheWrite: 100, reasoning: 5, createdAt: "2026-01-04T10:05:00.000Z"),
        ])

        let entries = LocalAdditionalUsageReader.copilotEntries(
            modifiedSince: try date("2026-01-01T00:00:00Z"), roots: [temporaryDirectory]).entries
        let day = try XCTUnwrap(entries.first?.localDay)
        let daily = try XCTUnwrap(LocalUsageReader.daily(entries: entries, localDay: day))

        XCTAssertEqual(daily.totalTokens, 110 + 290)
    }

    // MARK: - Provider identity

    func testLocalCopilotProviderIdentity() {
        let provider = LocalCopilotProvider()
        XCTAssertEqual(provider.id, "copilot")
        XCTAssertEqual(provider.displayName, "Copilot")
        XCTAssertFalse(provider.reportsCost, "Copilot bills premium requests — no invented dollar cost")
    }

    // MARK: - Helpers

    private struct Row {
        let id: Int
        let model: String
        let input, output, cacheRead, cacheWrite, reasoning: Int
        let createdAt: String
    }

    private func date(_ value: String) throws -> Date {
        try XCTUnwrap(ISO8601DateFormatter().date(from: value))
    }

    /// Entry ids are namespaced by database path so two stores cannot collide on row id.
    private func entryID(_ rowID: Int, in database: URL? = nil) -> String {
        "copilot|\((database ?? databaseURL).path)|\(rowID)"
    }

    private var databaseURL: URL {
        temporaryDirectory.appendingPathComponent("session-store.db")
    }

    /// Mirrors the shape the Copilot CLI creates for `assistant_usage_events`.
    private func seed(rows: [Row], in database: URL? = nil) throws {
        let target = database ?? databaseURL
        try execute(target, sql: """
        CREATE TABLE assistant_usage_events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id TEXT NOT NULL,
            turn_index INTEGER,
            agent_id TEXT,
            parent_tool_call_id TEXT,
            model TEXT NOT NULL,
            input_tokens INTEGER,
            output_tokens INTEGER,
            cache_read_tokens INTEGER,
            cache_write_tokens INTEGER,
            reasoning_tokens INTEGER,
            total_nano_aiu INTEGER,
            request_multiplier REAL,
            duration_ms INTEGER,
            time_to_first_token_ms INTEGER,
            inter_token_latency_ms INTEGER,
            initiator TEXT,
            api_endpoint TEXT,
            reasoning_effort TEXT,
            finish_reason TEXT,
            content_filter_triggered INTEGER,
            token_details_json TEXT,
            created_at TEXT DEFAULT (datetime('now'))
        );
        """)
        try insert(rows: rows, in: target)
    }

    private func insert(rows: [Row], in database: URL? = nil) throws {
        guard !rows.isEmpty else { return }
        let values = rows.map { row in
            """
            (\(row.id), 'session-1', 0, NULL, NULL, '\(row.model)', \(row.input), \(row.output), \
            \(row.cacheRead), \(row.cacheWrite), \(row.reasoning), 0, 1.0, 0, 0, 0, 'user', \
            '/v1/messages', 'medium', 'stop', 0, NULL, '\(row.createdAt)')
            """
        }.joined(separator: ",\n")
        try execute(database ?? databaseURL, sql: "INSERT INTO assistant_usage_events VALUES \(values);")
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
