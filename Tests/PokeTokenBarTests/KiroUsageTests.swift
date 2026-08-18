import SQLite3
import XCTest
@testable import PokeTokenBar

final class KiroUsageTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PokeTokenBar-KiroUsageTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
        temporaryDirectory = nil
    }

    // MARK: - Token accounting

    /// Kiro's `RequestMetadata` never carries a real token count (verified against the
    /// `aws/amazon-q-developer-cli` source kiro-cli forks). Output is a bytes/4 estimate off
    /// the real streamed `response_size`; a first turn's input is a bytes/4 estimate off the
    /// user's own message, since there is no prior history yet to resend.
    func testFirstTurnInputIsTheUserMessageByteEstimate() throws {
        try seedV2(conversations: [
            (id: "conv-1", turns: [
                turn(timestampMs: 1_780_000_000_000, model: "claude-sonnet-4.5",
                     userText: String(repeating: "u", count: 400), responseBytes: 200),
            ]),
        ])

        let entries = LocalAdditionalUsageReader.kiroEntries(
            modifiedSince: try date("2026-01-01T00:00:00Z"), roots: [temporaryDirectory])

        let entry = try XCTUnwrap(entries.first)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entry.input, 100, "400 bytes / 4 = 100 estimated input tokens")
        XCTAssertEqual(entry.output, 50, "200 bytes / 4 = 50 estimated output tokens")
        XCTAssertEqual(entry.cacheRead, 0)
        XCTAssertEqual(entry.cacheWrite, 0)
        XCTAssertEqual(entry.model, "claude-sonnet-4.5")
        XCTAssertEqual(entry.id, "kiro|conv-1|1780000000000")
    }

    /// Kiro has no server-side session — every turn resends the whole conversation. Using
    /// only `request_metadata.user_prompt_length` (just the newly typed message; verified
    /// against its assignment site in kiro-cli's upstream) would undercount a long-running
    /// conversation by orders of magnitude, so a later turn's input must include everything
    /// said before it.
    func testLaterTurnInputIncludesTheAccumulatedConversationHistory() throws {
        try seedV2(conversations: [
            (id: "conv-1", turns: [
                turn(timestampMs: 1_780_000_000_000, model: "claude-sonnet-4.5",
                     userText: String(repeating: "u", count: 400),
                     assistantText: String(repeating: "a", count: 800),
                     responseBytes: 800),
                turn(timestampMs: 1_780_000_100_000, model: "claude-sonnet-4.5",
                     userText: String(repeating: "u", count: 40), responseBytes: 40),
            ]),
        ])

        let entries = LocalAdditionalUsageReader.kiroEntries(
            modifiedSince: try date("2026-01-01T00:00:00Z"), roots: [temporaryDirectory])

        let second = try XCTUnwrap(entries.first { $0.id == "kiro|conv-1|1780000100000" })
        XCTAssertEqual(second.input, (400 + 800 + 40) / 4,
                       "must resend turn 1's user+assistant text plus turn 2's own message")
    }

    /// A turn skipped for its own entry (outside the window, missing timestamp) still
    /// happened — later turns in the same conversation still resend its text as history.
    func testSkippedTurnsStillContributeToLaterHistory() throws {
        try seedV2(conversations: [
            (id: "conv-1", turns: [
                turnMissingTimestamp(model: "claude-sonnet-4.5",
                                      userText: String(repeating: "u", count: 400),
                                      assistantText: String(repeating: "a", count: 400)),
                turn(timestampMs: 1_780_000_000_000, model: "claude-sonnet-4.5",
                     userText: String(repeating: "u", count: 40), responseBytes: 40),
            ]),
        ])

        let entry = try XCTUnwrap(LocalAdditionalUsageReader.kiroEntries(
            modifiedSince: try date("2026-01-01T00:00:00Z"), roots: [temporaryDirectory]).first)
        XCTAssertEqual(entry.input, (400 + 400 + 40) / 4)
    }

    /// `latest_summary` stands in for turns compaction deleted from `history` — it is still
    /// resent on every later request, so a post-compaction turn must count it as history too,
    /// not start accumulation from zero.
    func testLatestSummarySeedsTheAccumulatedHistory() throws {
        let summaryText = String(repeating: "s", count: 120)
        let turnJSON = try turnJSONString(
            turn(timestampMs: 1_780_000_000_000, model: "claude-sonnet-4.5",
                 userText: String(repeating: "u", count: 40), responseBytes: 40))
        let json = """
        {"conversation_id":"conv-1","latest_summary":["\(summaryText)"],"history":[\(turnJSON)]}
        """
        try seedV2Raw(rows: [(id: "conv-1", value: json)])

        let entry = try XCTUnwrap(LocalAdditionalUsageReader.kiroEntries(
            modifiedSince: try date("2026-01-01T00:00:00Z"), roots: [temporaryDirectory]).first)
        XCTAssertEqual(entry.input, (120 + 40) / 4)
    }

    // MARK: - Rescan stability

    /// The `.kiro` cache case merges each scan with previously-seen entries
    /// (`dedupKeepMax(existing + loaded)`) instead of replacing them, because Kiro deletes
    /// turns from its DB on `/clear`/compaction. That merge only behaves if two scans of an
    /// unchanged database agree on entry ids — otherwise it would double rather than merge.
    func testRescanningTheSameDatabaseProducesStableEntryIDs() throws {
        try seedV2(conversations: [
            (id: "conv-1", turns: [
                turn(timestampMs: 1_780_000_000_000, model: "claude-sonnet-4.5",
                     userText: String(repeating: "u", count: 400),
                     assistantText: String(repeating: "a", count: 200), responseBytes: 200),
                turn(timestampMs: 1_780_000_100_000, model: "claude-sonnet-4.5",
                     userText: String(repeating: "u", count: 40), responseBytes: 40),
            ]),
        ])
        let since = try date("2026-01-01T00:00:00Z")

        let first = LocalAdditionalUsageReader.kiroEntries(modifiedSince: since, roots: [temporaryDirectory])
        let second = LocalAdditionalUsageReader.kiroEntries(modifiedSince: since, roots: [temporaryDirectory])

        XCTAssertEqual(Set(first.map(\.id)), Set(second.map(\.id)))
        XCTAssertEqual(LocalUsageReader.dedupKeepMax(first + second).count, first.count,
                       "merging two identical scans must not double the entries")
    }

    func testMissingModelIDFallsBackToUnknown() throws {
        try seedV2(conversations: [
            (id: "conv-1", turns: [
                turn(timestampMs: 1_780_000_000_000, model: nil,
                     userText: String(repeating: "u", count: 40), responseBytes: 40),
            ]),
        ])

        let entry = try XCTUnwrap(LocalAdditionalUsageReader.kiroEntries(
            modifiedSince: try date("2026-01-01T00:00:00Z"), roots: [temporaryDirectory]).first)
        XCTAssertEqual(entry.model, "unknown")
    }

    /// A turn whose prompt and response were both empty carries no signal — `makeEntry`'s
    /// shared zero-token guard drops it, same as every other local provider.
    func testZeroByteTurnsAreSkipped() throws {
        try seedV2(conversations: [
            (id: "conv-1", turns: [
                turn(timestampMs: 1_780_000_000_000, model: "claude-sonnet-4.5",
                     userText: "", responseBytes: 0),
                turn(timestampMs: 1_780_000_001_000, model: "claude-sonnet-4.5",
                     userText: String(repeating: "u", count: 4), responseBytes: 0),
            ]),
        ])

        let entries = LocalAdditionalUsageReader.kiroEntries(
            modifiedSince: try date("2026-01-01T00:00:00Z"), roots: [temporaryDirectory])
        XCTAssertEqual(entries.map(\.id), ["kiro|conv-1|1780000001000"])
    }

    /// A base64 `images` blob would otherwise dwarf the actual text — it is excluded from the
    /// byte estimate rather than silently inflating every turn after it.
    func testImagesFieldIsExcludedFromTheByteEstimate() throws {
        var userField: [String: Any] = ["content": String(repeating: "u", count: 40)]
        userField["images"] = [String(repeating: "x", count: 1_000_000)]
        let turnObject: [String: Any] = [
            "user": userField, "assistant": [:],
            "request_metadata": [
                "request_start_timestamp_ms": 1_780_000_000_000,
                "model_id": "claude-sonnet-4.5",
                "response_size": 40,
            ],
        ]
        try seedV2(conversations: [(id: "conv-1", turns: [turnObject])])

        let entry = try XCTUnwrap(LocalAdditionalUsageReader.kiroEntries(
            modifiedSince: try date("2026-01-01T00:00:00Z"), roots: [temporaryDirectory]).first)
        XCTAssertEqual(entry.input, 10, "only the 40-byte `content` field counts, not the image blob")
    }

    // MARK: - Timestamps / windowing

    /// A turn without `request_start_timestamp_ms` has nothing stable to key an entry id on,
    /// so it must be skipped rather than assigned a made-up id.
    func testTurnsMissingTimestampAreSkipped() throws {
        try seedV2(conversations: [
            (id: "conv-1", turns: [
                turnMissingTimestamp(model: "claude-sonnet-4.5",
                                      userText: String(repeating: "u", count: 400)),
                turn(timestampMs: 1_780_000_000_000, model: "claude-sonnet-4.5",
                     userText: String(repeating: "u", count: 400), responseBytes: 200),
            ]),
        ])

        let entries = LocalAdditionalUsageReader.kiroEntries(
            modifiedSince: try date("2026-01-01T00:00:00Z"), roots: [temporaryDirectory])
        XCTAssertEqual(entries.count, 1)
    }

    func testTurnsBeforeTheWindowAreExcluded() throws {
        try seedV2(conversations: [
            (id: "conv-1", turns: [
                turn(timestampMs: 1_766_000_000_000, model: "claude-sonnet-4.5",
                     userText: String(repeating: "u", count: 400), responseBytes: 200),
                turn(timestampMs: 1_767_500_000_000, model: "claude-sonnet-4.5",
                     userText: String(repeating: "u", count: 400), responseBytes: 200),
            ]),
        ])

        let entries = LocalAdditionalUsageReader.kiroEntries(
            modifiedSince: date(fromMillis: 1_767_000_000_000), roots: [temporaryDirectory])
        XCTAssertEqual(entries.map(\.id), ["kiro|conv-1|1767500000000"])
    }

    /// A turn object missing `request_metadata` entirely (or a malformed history array) must
    /// not crash the scan — it is simply skipped, same as any other unparseable turn.
    func testConversationWithoutRequestMetadataIsSkipped() throws {
        let json = """
        {"conversation_id":"conv-1","history":[{"user":{},"assistant":{}}]}
        """
        try seedV2Raw(rows: [(id: "conv-1", value: json)])

        let entries = LocalAdditionalUsageReader.kiroEntries(
            modifiedSince: try date("2026-01-01T00:00:00Z"), roots: [temporaryDirectory])
        XCTAssertTrue(entries.isEmpty)
    }

    // MARK: - Schema generations

    /// kiro-cli < 2.0.1 stores each conversation as its own row in `conversations_v2` with a
    /// dedicated `conversation_id` column.
    func testReadsTheV2ConversationsTable() throws {
        try seedV2(conversations: [
            (id: "conv-1", turns: [
                turn(timestampMs: 1_780_000_000_000, model: "claude-sonnet-4.5",
                     userText: String(repeating: "u", count: 400), responseBytes: 200),
            ]),
        ])

        let entries = LocalAdditionalUsageReader.kiroEntries(
            modifiedSince: try date("2026-01-01T00:00:00Z"), roots: [temporaryDirectory])
        XCTAssertEqual(entries.map(\.id), ["kiro|conv-1|1780000000000"])
    }

    /// kiro-cli 2.0.1+ keys `conversations` by working directory and drops the dedicated
    /// timestamp/id columns — the conversation id must be read out of the JSON body instead.
    func testReadsTheV1ConversationsTable() throws {
        try seedV1(conversations: [
            (cwd: "/Users/dev/project", id: "conv-2", turns: [
                turn(timestampMs: 1_780_000_000_000, model: "claude-sonnet-4.5",
                     userText: String(repeating: "u", count: 800), responseBytes: 400),
            ]),
        ])

        let entries = LocalAdditionalUsageReader.kiroEntries(
            modifiedSince: try date("2026-01-01T00:00:00Z"), roots: [temporaryDirectory])
        let entry = try XCTUnwrap(entries.first)
        XCTAssertEqual(entry.id, "kiro|conv-2|1780000000000")
        XCTAssertEqual(entry.input, 200)
        XCTAssertEqual(entry.output, 100)
    }

    /// A `conversations` (v1) row whose JSON has no `conversation_id` cannot be keyed at all
    /// — it must be dropped, not counted under a made-up or empty id.
    func testV1RowWithoutConversationIDIsSkipped() throws {
        let json = """
        {"history":[{"request_metadata":{"request_start_timestamp_ms":1780000000000,\
        "model_id":"claude-sonnet-4.5","response_size":200}}]}
        """
        try seedV1Raw(rows: [(cwd: "/Users/dev/project", value: json)])

        let entries = LocalAdditionalUsageReader.kiroEntries(
            modifiedSince: try date("2026-01-01T00:00:00Z"), roots: [temporaryDirectory])
        XCTAssertTrue(entries.isEmpty)
    }

    /// A row whose `value` is not parseable JSON (write torn mid-checkpoint, hand edit, future
    /// schema this reader doesn't understand yet) must be skipped, not crash the scan — the same
    /// external-file resilience every other local reader in this file gets.
    func testMalformedJSONRowsAreSkippedInBothSchemas() throws {
        try seedV2Raw(rows: [(id: "conv-1", value: "{not valid json")])
        try seedV1Raw(rows: [(cwd: "/Users/dev/project", value: "{not valid json")])

        let entries = LocalAdditionalUsageReader.kiroEntries(
            modifiedSince: try date("2026-01-01T00:00:00Z"), roots: [temporaryDirectory])
        XCTAssertTrue(entries.isEmpty)
    }

    /// A conversation JSON without a `history` array (unexpected shape, not just an empty one)
    /// must not crash — it simply contributes no turns.
    func testConversationWithoutHistoryArrayIsSkipped() throws {
        try seedV2Raw(rows: [(id: "conv-1", value: #"{"conversation_id":"conv-1"}"#)])

        let entries = LocalAdditionalUsageReader.kiroEntries(
            modifiedSince: try date("2026-01-01T00:00:00Z"), roots: [temporaryDirectory])
        XCTAssertTrue(entries.isEmpty)
    }

    /// Both schema generations can be present at once during a kiro-cli upgrade. If the same
    /// conversation is mid-migration and shows up in both tables, it must not be double-counted.
    func testSameConversationInBothTablesIsNotDoubleCounted() throws {
        try seedV2(conversations: [
            (id: "conv-1", turns: [
                turn(timestampMs: 1_780_000_000_000, model: "claude-sonnet-4.5",
                     userText: String(repeating: "u", count: 400), responseBytes: 200),
            ]),
        ])
        try seedV1(conversations: [
            (cwd: "/Users/dev/project", id: "conv-1", turns: [
                turn(timestampMs: 1_780_000_000_000, model: "claude-sonnet-4.5",
                     userText: String(repeating: "u", count: 400), responseBytes: 200),
            ]),
        ])

        let entries = LocalAdditionalUsageReader.kiroEntries(
            modifiedSince: try date("2026-01-01T00:00:00Z"), roots: [temporaryDirectory])
        XCTAssertEqual(entries.count, 1, "the same turn id from both tables must collapse to one entry")
    }

    /// Two independent conversations, one only in each table, must both be counted — the v1
    /// table is not just a fallback that stops scanning once v2 has rows.
    func testConversationsAcrossBothTablesAreBothCounted() throws {
        try seedV2(conversations: [
            (id: "conv-1", turns: [
                turn(timestampMs: 1_780_000_000_000, model: "claude-sonnet-4.5",
                     userText: String(repeating: "u", count: 400), responseBytes: 200),
            ]),
        ])
        try seedV1(conversations: [
            (cwd: "/Users/dev/other-project", id: "conv-2", turns: [
                turn(timestampMs: 1_780_000_100_000, model: "claude-sonnet-4.5",
                     userText: String(repeating: "u", count: 800), responseBytes: 400),
            ]),
        ])

        let entries = LocalAdditionalUsageReader.kiroEntries(
            modifiedSince: try date("2026-01-01T00:00:00Z"), roots: [temporaryDirectory])
        XCTAssertEqual(Set(entries.map(\.id)),
                       ["kiro|conv-1|1780000000000", "kiro|conv-2|1780000100000"])
    }

    // MARK: - Roots

    func testAcceptsADirectDatabasePathAsRoot() throws {
        try seedV2(conversations: [
            (id: "conv-1", turns: [
                turn(timestampMs: 1_780_000_000_000, model: "claude-sonnet-4.5",
                     userText: String(repeating: "u", count: 400), responseBytes: 200),
            ]),
        ])

        let entries = LocalAdditionalUsageReader.kiroEntries(
            modifiedSince: try date("2026-01-01T00:00:00Z"),
            roots: [temporaryDirectory.appendingPathComponent("data.sqlite3")])
        XCTAssertEqual(entries.count, 1)
    }

    func testNonexistentRootReturnsNothing() {
        let entries = LocalAdditionalUsageReader.kiroEntries(
            modifiedSince: .distantPast, roots: [URL(fileURLWithPath: "/nonexistent/kiro-cli/home")])
        XCTAssertTrue(entries.isEmpty)
    }

    func testDefaultRootIsTheKiroCliHome() {
        let expected = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/kiro-cli")
        let roots = LocalAdditionalUsageReader.defaultKiroRoots
        if ProcessInfo.processInfo.environment["KIRO_CLI_HOME"] == nil {
            XCTAssertEqual(roots, [expected])
        }
        XCTAssertFalse(roots.isEmpty)
    }

    // MARK: - Aggregation

    func testDailyAggregatesEveryTurnOfTheDay() throws {
        try seedV2(conversations: [
            (id: "conv-1", turns: [
                turn(timestampMs: 1_780_000_000_000, model: "claude-sonnet-4.5",
                     userText: String(repeating: "u", count: 400), responseBytes: 200),
                turn(timestampMs: 1_780_000_100_000, model: "claude-sonnet-4.5",
                     userText: "", responseBytes: 40),
            ]),
        ])

        let entries = LocalAdditionalUsageReader.kiroEntries(
            modifiedSince: try date("2026-01-01T00:00:00Z"), roots: [temporaryDirectory])
        let day = try XCTUnwrap(entries.first?.localDay)
        let daily = try XCTUnwrap(LocalUsageReader.daily(entries: entries, localDay: day))
        XCTAssertEqual(daily.totalTokens, entries.reduce(0) { $0 + $1.total })
    }

    // MARK: - Provider identity

    func testLocalKiroProviderIdentity() {
        let provider = LocalKiroProvider()
        XCTAssertEqual(provider.id, "kiro")
        XCTAssertEqual(provider.displayName, "Kiro")
        XCTAssertFalse(provider.reportsCost, "tokens are a bytes/4 estimate — no real dollar cost to report")
    }

    // MARK: - Fixture construction

    private func turn(
        timestampMs: Int64, model: String?,
        userText: String, assistantText: String = "", responseBytes: Int = 0
    ) -> [String: Any] {
        var metadata: [String: Any] = [
            "request_start_timestamp_ms": timestampMs,
            "response_size": responseBytes,
            "time_between_chunks": [],
            "tool_use_ids_and_names": [],
        ]
        if let model { metadata["model_id"] = model }
        return [
            "user": ["content": userText], "assistant": ["content": assistantText],
            "request_metadata": metadata,
        ]
    }

    private func turnMissingTimestamp(model: String?, userText: String, assistantText: String = "") -> [String: Any] {
        var metadata: [String: Any] = ["response_size": 0]
        if let model { metadata["model_id"] = model }
        return [
            "user": ["content": userText], "assistant": ["content": assistantText],
            "request_metadata": metadata,
        ]
    }

    private func conversationJSON(id: String, turns: [[String: Any]]) throws -> String {
        let object: [String: Any] = ["conversation_id": id, "history": turns, "latest_summary": NSNull()]
        let data = try JSONSerialization.data(withJSONObject: object)
        return String(data: data, encoding: .utf8)!
    }

    /// A single turn dict, serialized standalone for hand-assembling a conversation JSON
    /// string (used when a test needs to control `latest_summary` directly).
    private func turnJSONString(_ turn: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: turn)
        return String(data: data, encoding: .utf8)!
    }

    private func date(_ value: String) throws -> Date {
        try XCTUnwrap(ISO8601DateFormatter().date(from: value))
    }

    private func date(fromMillis ms: Int64) -> Date {
        Date(timeIntervalSince1970: Double(ms) / 1000)
    }

    private var databaseURL: URL {
        temporaryDirectory.appendingPathComponent("data.sqlite3")
    }

    private func seedV2(conversations: [(id: String, turns: [[String: Any]])]) throws {
        let rows = try conversations.map { (id: $0.id, value: try conversationJSON(id: $0.id, turns: $0.turns)) }
        try seedV2Raw(rows: rows)
    }

    private func seedV2Raw(rows: [(id: String, value: String)]) throws {
        try execute(databaseURL, sql: """
        CREATE TABLE IF NOT EXISTS conversations_v2 (
            conversation_id TEXT PRIMARY KEY,
            key TEXT,
            created_at INTEGER,
            updated_at INTEGER,
            value TEXT
        );
        """)
        for row in rows {
            try insert(
                databaseURL,
                sql: "INSERT INTO conversations_v2 (conversation_id, key, created_at, updated_at, value) VALUES (?1, ?2, 0, 0, ?3)",
                text: [row.id, "/Users/dev/project", row.value])
        }
    }

    private func seedV1(conversations: [(cwd: String, id: String, turns: [[String: Any]])]) throws {
        let rows = try conversations.map {
            (cwd: $0.cwd, value: try conversationJSON(id: $0.id, turns: $0.turns))
        }
        try seedV1Raw(rows: rows)
    }

    private func seedV1Raw(rows: [(cwd: String, value: String)]) throws {
        try execute(databaseURL, sql: """
        CREATE TABLE IF NOT EXISTS conversations (
            key TEXT PRIMARY KEY,
            value TEXT
        );
        """)
        for row in rows {
            try insert(
                databaseURL,
                sql: "INSERT INTO conversations (key, value) VALUES (?1, ?2)",
                text: [row.cwd, row.value])
        }
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

    private func insert(_ databaseURL: URL, sql: String, text: [String]) throws {
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &database), SQLITE_OK)
        guard let database else { throw NSError(domain: "SQLite", code: 1) }
        defer { sqlite3_close(database) }
        var statement: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(database, sql, -1, &statement, nil), SQLITE_OK)
        guard let statement else { throw NSError(domain: "SQLite", code: 2) }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, value) in text.enumerated() {
            sqlite3_bind_text(statement, Int32(index + 1), value, -1, transient)
        }
        XCTAssertEqual(sqlite3_step(statement), SQLITE_DONE)
    }
}
