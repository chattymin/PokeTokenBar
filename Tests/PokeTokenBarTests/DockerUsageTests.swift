import SQLite3
import XCTest
@testable import PokeTokenBar

/// Docker Agent (docker/docker-agent, previously "cagent") parser + incremental-scan
/// wiring. The store lives at `<data dir>/session.db`; every `session_items` row is one
/// chat message whose assistant rows persist per-message usage and a docker-computed cost.
/// The scanner-generic invariants (watermark preservation, didReset recovery) are pinned
/// by IncrementalStoreScanTests — here we exercise the docker-specific plumbing of them.
final class DockerUsageTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PokeTokenBar-DockerUsageTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
        temporaryDirectory = nil
    }

    // MARK: - Row parsing

    /// The denormalized `usage_json`/`model`/`cost` columns are authoritative when present —
    /// the copies embedded in `message_json` are deliberately different here to prove it.
    func testReadsAssistantUsageFromDenormalizedColumns() throws {
        try createSessionItems()
        try insertItem(
            message: try json([
                "role": "assistant", "created_at": "2026-01-02T12:00:00Z",
                "model": "embedded-model", "cost": 9.99,
                "usage": ["input_tokens": 1, "output_tokens": 1],
            ]),
            usage: try json(["input_tokens": 1000, "output_tokens": 300,
                             "cached_input_tokens": 400, "cached_write_tokens": 100]),
            model: "claude-sonnet-4-5", cost: 0.42)

        let loaded = LocalAdditionalUsageReader.dockerEntries(
            modifiedSince: try date("2026-01-01T00:00:00Z"), roots: [temporaryDirectory])

        let entry = try XCTUnwrap(loaded.entries.first)
        XCTAssertEqual(loaded.entries.count, 1)
        XCTAssertEqual(entry.model, "claude-sonnet-4-5")
        XCTAssertEqual(entry.explicitCost, 0.42)
        XCTAssertEqual(entry.cacheRead, 400)
        XCTAssertEqual(entry.cacheWrite, 100)
        XCTAssertEqual(entry.input, 500, "input_tokens minus the cached subset")
        XCTAssertEqual(entry.output, 300)
        XCTAssertEqual(entry.date, try date("2026-01-02T12:00:00Z"))
        XCTAssertEqual(entry.id, "docker|\(databaseURL.path)|1")
        XCTAssertFalse(loaded.didReset)
    }

    /// Rows written before the denormalizing migration carry the values only inside
    /// `message_json` — each field must fall back independently.
    func testFallsBackToMessageJSONWhenColumnsAreNull() throws {
        try createSessionItems()
        try insertItem(
            message: try json([
                "role": "assistant", "created_at": "2026-01-02T12:00:00Z",
                "model": "gpt-5", "cost": 0.07,
                "usage": ["input_tokens": 120, "output_tokens": 30,
                          "cached_input_tokens": 20, "cached_write_tokens": 0],
            ]))

        let entry = try XCTUnwrap(LocalAdditionalUsageReader.dockerEntries(
            modifiedSince: try date("2026-01-01T00:00:00Z"),
            roots: [temporaryDirectory]).entries.first)
        XCTAssertEqual(entry.model, "gpt-5")
        XCTAssertEqual(entry.explicitCost, 0.07)
        XCTAssertEqual(entry.input, 100)
        XCTAssertEqual(entry.output, 30)
        XCTAssertEqual(entry.cacheRead, 20)
    }

    /// docker-agent writes cost 0 for local Docker Model Runner models — a zero must not
    /// become `explicitCost`, or it would suppress the pricing-table fallback in Bucket.add.
    func testZeroCostIsNotTreatedAsExplicit() throws {
        try createSessionItems()
        try insertItem(
            message: try json([
                "role": "assistant", "created_at": "2026-01-02T12:00:00Z",
                "model": "qwen3", "cost": 0,
                "usage": ["input_tokens": 100, "output_tokens": 10],
            ]),
            cost: 0)

        let entry = try XCTUnwrap(LocalAdditionalUsageReader.dockerEntries(
            modifiedSince: try date("2026-01-01T00:00:00Z"),
            roots: [temporaryDirectory]).entries.first)
        XCTAssertNil(entry.explicitCost)
    }

    /// User and tool messages carry no usage object — they are not billed calls.
    /// An assistant row whose usage is all zeros likewise produces no entry.
    func testItemsWithoutUsageOrAllZeroUsageAreSkipped() throws {
        try createSessionItems()
        try insertItem(message: try json([
            "role": "user", "created_at": "2026-01-02T12:00:00Z", "content": "hello",
        ]))
        try insertItem(message: try json([
            "role": "assistant", "created_at": "2026-01-02T12:00:01Z",
            "usage": ["input_tokens": 0, "output_tokens": 0],
        ]))

        XCTAssertTrue(LocalAdditionalUsageReader.dockerEntries(
            modifiedSince: try date("2026-01-01T00:00:00Z"),
            roots: [temporaryDirectory]).entries.isEmpty)
    }

    /// `session_items` has no time column of its own — a message without a parseable
    /// `created_at` has no local day to attribute to, so it is skipped rather than dated
    /// off the session start (which would misdate a long session's later usage).
    func testItemsMissingCreatedAtAreSkipped() throws {
        try createSessionItems()
        try insertItem(message: try json([
            "role": "assistant",
            "usage": ["input_tokens": 100, "output_tokens": 10],
        ]))
        try insertItem(message: try json([
            "role": "assistant", "created_at": "not-a-date",
            "usage": ["input_tokens": 100, "output_tokens": 10],
        ]))

        XCTAssertTrue(LocalAdditionalUsageReader.dockerEntries(
            modifiedSince: try date("2026-01-01T00:00:00Z"),
            roots: [temporaryDirectory]).entries.isEmpty)
    }

    func testMalformedMessageJSONRowsAreSkipped() throws {
        try createSessionItems()
        try insertItem(message: "{not json")
        try insertItem(message: try json([
            "role": "assistant", "created_at": "2026-01-02T12:00:00Z",
            "usage": ["input_tokens": 100, "output_tokens": 10],
        ]))

        let loaded = LocalAdditionalUsageReader.dockerEntries(
            modifiedSince: try date("2026-01-01T00:00:00Z"), roots: [temporaryDirectory])
        XCTAssertEqual(loaded.entries.count, 1)
        XCTAssertEqual(loaded.highWaterRowID, 2, "a skipped row still advances the watermark")
    }

    /// cagent normalizes several upstream providers into one usage shape. Anthropic-shaped
    /// rows report `input_tokens` *excluding* the cached tokens — the subtraction must clamp
    /// at zero instead of going negative (the `max(0, …)` branch on its own, A=false B=true).
    func testCacheSubtractionClampsForAnthropicShapedRows() throws {
        try createSessionItems()
        try insertItem(message: try json([
            "role": "assistant", "created_at": "2026-01-02T12:00:00Z",
            "usage": ["input_tokens": 50, "output_tokens": 10,
                      "cached_input_tokens": 400, "cached_write_tokens": 100],
        ]))

        let entry = try XCTUnwrap(LocalAdditionalUsageReader.dockerEntries(
            modifiedSince: try date("2026-01-01T00:00:00Z"),
            roots: [temporaryDirectory]).entries.first)
        XCTAssertEqual(entry.input, 0, "50 - 400 - 100 clamps to 0, never negative")
        XCTAssertEqual(entry.cacheRead, 400)
        XCTAssertEqual(entry.cacheWrite, 100)
        XCTAssertEqual(entry.total, 510)
    }

    /// `reasoning_tokens` is a breakdown of `output_tokens`, not an extra charge.
    func testReasoningTokensAreNotAddedToOutput() throws {
        try createSessionItems()
        try insertItem(message: try json([
            "role": "assistant", "created_at": "2026-01-02T12:00:00Z",
            "usage": ["input_tokens": 100, "output_tokens": 80, "reasoning_tokens": 60],
        ]))

        let entry = try XCTUnwrap(LocalAdditionalUsageReader.dockerEntries(
            modifiedSince: try date("2026-01-01T00:00:00Z"),
            roots: [temporaryDirectory]).entries.first)
        XCTAssertEqual(entry.output, 80)
        XCTAssertEqual(entry.total, 180)
    }

    func testItemsBeforeTheWindowAreExcluded() throws {
        try createSessionItems()
        try insertItem(message: try json([
            "role": "assistant", "created_at": "2025-12-15T12:00:00Z",
            "usage": ["input_tokens": 100, "output_tokens": 10],
        ]))
        try insertItem(message: try json([
            "role": "assistant", "created_at": "2026-01-02T12:00:00Z",
            "usage": ["input_tokens": 100, "output_tokens": 10],
        ]))

        let loaded = LocalAdditionalUsageReader.dockerEntries(
            modifiedSince: try date("2026-01-01T00:00:00Z"), roots: [temporaryDirectory])
        XCTAssertEqual(loaded.entries.map(\.id), ["docker|\(databaseURL.path)|2"])
    }

    // MARK: - Incremental scanning

    func testRescanningTheSameDatabaseProducesStableEntryIDs() throws {
        try createSessionItems()
        try insertItem(message: try json([
            "role": "assistant", "created_at": "2026-01-02T12:00:00Z",
            "usage": ["input_tokens": 100, "output_tokens": 10],
        ]))
        try insertItem(message: try json([
            "role": "assistant", "created_at": "2026-01-02T12:01:00Z",
            "usage": ["input_tokens": 200, "output_tokens": 20],
        ]))

        let since = try date("2026-01-01T00:00:00Z")
        let first = LocalAdditionalUsageReader.dockerEntries(
            modifiedSince: since, roots: [temporaryDirectory]).entries
        let second = LocalAdditionalUsageReader.dockerEntries(
            modifiedSince: since, roots: [temporaryDirectory]).entries
        XCTAssertEqual(LocalUsageReader.dedupKeepMax(first + second).count, first.count)
        XCTAssertEqual(Set(first.map(\.id)), Set(second.map(\.id)))
    }

    func testIncrementalScanReturnsOnlyRowsAfterTheWatermark() throws {
        try createSessionItems()
        try insertItem(message: try json([
            "role": "assistant", "created_at": "2026-01-02T12:00:00Z",
            "usage": ["input_tokens": 100, "output_tokens": 10],
        ]))
        let since = try date("2026-01-01T00:00:00Z")
        let cold = LocalAdditionalUsageReader.dockerEntries(
            modifiedSince: since, roots: [temporaryDirectory])
        XCTAssertEqual(cold.highWaterRowID, 1)

        try insertItem(message: try json([
            "role": "assistant", "created_at": "2026-01-02T12:01:00Z",
            "usage": ["input_tokens": 200, "output_tokens": 20],
        ]))
        let incremental = LocalAdditionalUsageReader.dockerEntries(
            modifiedSince: since, afterRowIDByPath: cold.highWaterByPath,
            roots: [temporaryDirectory])

        XCTAssertEqual(incremental.entries.map(\.id), ["docker|\(databaseURL.path)|2"])
        XCTAssertEqual(incremental.highWaterRowID, 2)
        XCTAssertFalse(incremental.didReset)
    }

    /// `/undo` (or a recreated DB) can remove the newest rows — MAX(rowid) drops below the
    /// watermark, and the scan must fall back to a cold rescan and say so via `didReset`,
    /// because the cached entry ids would otherwise name different items after rowid reuse.
    func testDeletingTheNewestRowsTriggersColdRescan() throws {
        try createSessionItems()
        try insertItem(message: try json([
            "role": "assistant", "created_at": "2026-01-02T12:00:00Z",
            "usage": ["input_tokens": 100, "output_tokens": 10],
        ]))
        try insertItem(message: try json([
            "role": "assistant", "created_at": "2026-01-02T12:01:00Z",
            "usage": ["input_tokens": 200, "output_tokens": 20],
        ]))
        let since = try date("2026-01-01T00:00:00Z")
        let cold = LocalAdditionalUsageReader.dockerEntries(
            modifiedSince: since, roots: [temporaryDirectory])
        XCTAssertEqual(cold.highWaterRowID, 2)

        try execute(databaseURL, sql: "DELETE FROM session_items WHERE rowid = 2")
        let rescanned = LocalAdditionalUsageReader.dockerEntries(
            modifiedSince: since, afterRowIDByPath: cold.highWaterByPath,
            roots: [temporaryDirectory])

        XCTAssertTrue(rescanned.didReset)
        XCTAssertEqual(rescanned.entries.map(\.id), ["docker|\(databaseURL.path)|1"])
        XCTAssertEqual(rescanned.highWaterRowID, 1)
    }

    /// rowid is only unique within one store, and the env override may name several roots —
    /// same-numbered rows must not collapse into one event during dedup.
    func testEntriesFromTwoStoresDoNotCollapse() throws {
        let otherRoot = temporaryDirectory.appendingPathComponent("second")
        try FileManager.default.createDirectory(at: otherRoot, withIntermediateDirectories: true)
        let message = try json([
            "role": "assistant", "created_at": "2026-01-02T12:00:00Z",
            "usage": ["input_tokens": 100, "output_tokens": 10],
        ])
        for database in [databaseURL, otherRoot.appendingPathComponent("session.db")] {
            try createSessionItems(at: database)
            try insertItem(message: message, into: database)
        }

        let loaded = LocalAdditionalUsageReader.dockerEntries(
            modifiedSince: try date("2026-01-01T00:00:00Z"),
            roots: [temporaryDirectory, otherRoot])
        XCTAssertEqual(loaded.entries.count, 2)
        XCTAssertEqual(Set(loaded.entries.map(\.id)).count, 2)
    }

    // MARK: - Roots

    func testAcceptsADirectDatabasePathAsRoot() throws {
        try createSessionItems()
        try insertItem(message: try json([
            "role": "assistant", "created_at": "2026-01-02T12:00:00Z",
            "usage": ["input_tokens": 100, "output_tokens": 10],
        ]))

        let loaded = LocalAdditionalUsageReader.dockerEntries(
            modifiedSince: try date("2026-01-01T00:00:00Z"), roots: [databaseURL])
        XCTAssertEqual(loaded.entries.count, 1)
    }

    func testNonexistentRootReturnsNothing() {
        let loaded = LocalAdditionalUsageReader.dockerEntries(
            modifiedSince: .distantPast, roots: [URL(fileURLWithPath: "/nonexistent/cagent")])
        XCTAssertTrue(loaded.entries.isEmpty)
        XCTAssertFalse(loaded.didReset)
    }

    func testDefaultRootIsTheCagentHome() {
        let expected = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cagent")
        let roots = LocalAdditionalUsageReader.defaultDockerRoots
        let environment = ProcessInfo.processInfo.environment
        if environment["DOCKER_AGENT_DATA_DIR"] == nil, environment["CAGENT_DATA_DIR"] == nil {
            XCTAssertEqual(roots, [expected])
        }
        XCTAssertFalse(roots.isEmpty)
    }

    // MARK: - Aggregation

    /// docker's own dollar figure must flow into the daily aggregate via `explicitCost`.
    func testDailyAggregatesTokensAndExplicitCost() throws {
        try createSessionItems()
        try insertItem(
            message: try json([
                "role": "assistant", "created_at": "2026-01-02T12:00:00Z",
                "usage": ["input_tokens": 100, "output_tokens": 10],
            ]),
            cost: 0.30)
        try insertItem(
            message: try json([
                "role": "assistant", "created_at": "2026-01-02T12:01:00Z",
                "usage": ["input_tokens": 200, "output_tokens": 20],
            ]),
            cost: 0.20)

        let entries = LocalAdditionalUsageReader.dockerEntries(
            modifiedSince: try date("2026-01-01T00:00:00Z"), roots: [temporaryDirectory]).entries
        let day = try XCTUnwrap(entries.first?.localDay)
        let daily = try XCTUnwrap(LocalUsageReader.daily(entries: entries, localDay: day))
        XCTAssertEqual(daily.totalTokens, 330)
        XCTAssertEqual(daily.totalCost, 0.5, accuracy: 0.000_001)
    }

    // MARK: - Provider identity

    func testLocalDockerProviderIdentity() {
        let provider = LocalDockerProvider()
        XCTAssertEqual(provider.id, "docker")
        XCTAssertEqual(provider.displayName, "Docker Agent")
        XCTAssertTrue(provider.reportsCost, "docker-agent persists its own models.dev dollar cost")
    }

    // MARK: - Real-data smoke test

    func testPrintRealDockerAggregate() throws {
        guard ProcessInfo.processInfo.environment["PTB_PARITY"] == "1" else {
            throw XCTSkip("set PTB_PARITY=1 for the local Docker Agent smoke test")
        }
        let roots = LocalAdditionalUsageReader.defaultDockerRoots
        guard roots.contains(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            throw XCTSkip("no local Docker Agent data directory")
        }
        let entries = LocalAdditionalUsageReader.dockerEntries(
            modifiedSince: LocalUsageReader.startOfMonth(Date())).entries
        XCTAssertFalse(entries.isEmpty)
        let today = LocalUsageReader.todayKey()
        let todayTotal = entries.filter { $0.localDay == today }.reduce(0) { $0 + $1.total }
        print("DOCKER_NATIVE_PARITY entries=\(entries.count) today=\(todayTotal) month=\(entries.reduce(0) { $0 + $1.total })")
    }

    // MARK: - Fixture construction

    private var databaseURL: URL {
        temporaryDirectory.appendingPathComponent("session.db")
    }

    private func createSessionItems(at database: URL? = nil) throws {
        try execute(database ?? databaseURL, sql: """
        CREATE TABLE IF NOT EXISTS session_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id TEXT,
            position INTEGER,
            item_type TEXT,
            agent_name TEXT,
            message_json TEXT,
            cost REAL,
            model TEXT,
            usage_json TEXT
        );
        """)
    }

    /// Inserts one message row. `usage`/`model`/`cost` stay NULL unless given, matching
    /// rows written before cagent's denormalizing migration.
    private func insertItem(
        message: String,
        usage: String? = nil,
        model: String? = nil,
        cost: Double? = nil,
        into database: URL? = nil
    ) throws {
        let target = database ?? databaseURL
        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open(target.path, &handle), SQLITE_OK)
        guard let handle else { throw NSError(domain: "SQLite", code: 1) }
        defer { sqlite3_close(handle) }
        var statement: OpaquePointer?
        let sql = """
        INSERT INTO session_items (session_id, position, item_type, message_json, usage_json, model, cost)
        VALUES ('session-1', 0, 'message', ?1, ?2, ?3, ?4)
        """
        XCTAssertEqual(sqlite3_prepare_v2(handle, sql, -1, &statement, nil), SQLITE_OK)
        guard let statement else { throw NSError(domain: "SQLite", code: 2) }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, message, -1, transient)
        if let usage { sqlite3_bind_text(statement, 2, usage, -1, transient) }
        else { sqlite3_bind_null(statement, 2) }
        if let model { sqlite3_bind_text(statement, 3, model, -1, transient) }
        else { sqlite3_bind_null(statement, 3) }
        if let cost { sqlite3_bind_double(statement, 4, cost) }
        else { sqlite3_bind_null(statement, 4) }
        XCTAssertEqual(sqlite3_step(statement), SQLITE_DONE)
    }

    private func execute(_ database: URL, sql: String) throws {
        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open(database.path, &handle), SQLITE_OK)
        guard let handle else { throw NSError(domain: "SQLite", code: 1) }
        defer { sqlite3_close(handle) }
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(handle, sql, nil, nil, &errorMessage)
        let message = errorMessage.map { String(cString: $0) }
        sqlite3_free(errorMessage)
        XCTAssertEqual(result, SQLITE_OK, message ?? "SQLite statement failed")
        if result != SQLITE_OK { throw NSError(domain: "SQLite", code: Int(result)) }
    }

    private func json(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object)
        return String(data: data, encoding: .utf8)!
    }

    private func date(_ value: String) throws -> Date {
        try XCTUnwrap(ISO8601DateFormatter().date(from: value))
    }
}
