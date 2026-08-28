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
        // Parse stability is a property of the reader, not of the mtime gate —
        // this overload passes no known signatures, so the second call re-reads.
        let second = LocalAdditionalUsageReader.kiroEntries(modifiedSince: since, roots: [temporaryDirectory])

        XCTAssertEqual(Set(first.map(\.id)), Set(second.map(\.id)))
        XCTAssertEqual(LocalUsageReader.dedupKeepMax(first + second).count, first.count,
                       "merging two identical scans must not double the entries")
    }

    /// #178: `modifiedSince` is applied after the JSON parse, so an unchanged
    /// database still pays the full read. The cheap gate is the file's own
    /// signature — a second scan that sees the same mtime+size must return
    /// nothing. The `.kiro` cache merges `existing + loaded`, so empty is
    /// the correct "nothing new" signal, not a wipe.
    func testUnchangedDatabaseSkipsTheRescan() throws {
        try seedV2(conversations: [
            (id: "conv-1", turns: [
                turn(timestampMs: 1_780_000_000_000, model: "claude-sonnet-4.5",
                     userText: String(repeating: "u", count: 40), responseBytes: 40),
            ]),
        ])
        let since = try date("2026-01-01T00:00:00Z")

        let first = LocalAdditionalUsageReader.kiroEntries(
            modifiedSince: since, knownSignatures: [:], roots: [temporaryDirectory])
        XCTAssertEqual(first.entries.map(\.id), ["kiro|conv-1|1780000000000"])

        let second = LocalAdditionalUsageReader.kiroEntries(
            modifiedSince: since, knownSignatures: first.signatures, roots: [temporaryDirectory])
        XCTAssertTrue(second.entries.isEmpty, "unchanged database must not be re-parsed; empty keeps the cached entries")
        XCTAssertEqual(LocalUsageReader.dedupKeepMax(first.entries + second.entries).count, first.entries.count)
    }

    /// A WAL commit leaves the main file's mtime alone. Keying the skip on
    /// `data.sqlite3` only would miss the turn that just landed — the same
    /// class `LocalAntigravityUsageReader.signature` already records. Do not
    /// copy that function; reuse it.
    func testWalCommitForcesARescan() throws {
        try seedV2(conversations: [
            (id: "conv-1", turns: [
                turn(timestampMs: 1_780_000_000_000, model: "claude-sonnet-4.5",
                     userText: String(repeating: "u", count: 40), responseBytes: 40),
            ]),
        ])
        let since = try date("2026-01-01T00:00:00Z")
        let first = LocalAdditionalUsageReader.kiroEntries(
            modifiedSince: since, knownSignatures: [:], roots: [temporaryDirectory])
        XCTAssertFalse(first.entries.isEmpty)

        try Data("wal-commit".utf8).write(to: URL(fileURLWithPath: databaseURL.path + "-wal"))
        let second = LocalAdditionalUsageReader.kiroEntries(
            modifiedSince: since, knownSignatures: first.signatures, roots: [temporaryDirectory])
        XCTAssertEqual(Set(second.entries.map(\.id)), Set(first.entries.map(\.id)),
                       "a newer -wal sibling must invalidate the skip")
    }

    /// `-shm` is a rebuildable index. A read-only connection writes read
    /// marks into it, so including it would let the skip invalidate itself
    /// on every poll (hit rate 0). Same exclusion as Antigravity.
    func testShmChurnDoesNotForceARescan() throws {
        try seedV2(conversations: [
            (id: "conv-1", turns: [
                turn(timestampMs: 1_780_000_000_000, model: "claude-sonnet-4.5",
                     userText: String(repeating: "u", count: 40), responseBytes: 40),
            ]),
        ])
        let since = try date("2026-01-01T00:00:00Z")
        let first = LocalAdditionalUsageReader.kiroEntries(
            modifiedSince: since, knownSignatures: [:], roots: [temporaryDirectory])

        try Data("shm-read-mark".utf8).write(to: URL(fileURLWithPath: databaseURL.path + "-shm"))
        let second = LocalAdditionalUsageReader.kiroEntries(
            modifiedSince: since, knownSignatures: first.signatures, roots: [temporaryDirectory])
        XCTAssertTrue(second.entries.isEmpty, "-shm churn is a read, not a write")
    }

    /// A failed open must not occupy the skip slot — otherwise a BUSY or
    /// corrupt page is frozen as "no usage" until the file's mtime moves.
    func testFailedOpenDoesNotOccupyTheSkipSlot() throws {
        try Data("not-a-sqlite-database".utf8).write(to: databaseURL)
        let since = try date("2026-01-01T00:00:00Z")
        let first = LocalAdditionalUsageReader.kiroEntries(
            modifiedSince: since, knownSignatures: [:], roots: [temporaryDirectory])
        XCTAssertTrue(first.entries.isEmpty)
        XCTAssertNil(
            first.signatures[databaseURL.path],
            "failed open must not record a signature")

        try FileManager.default.removeItem(at: databaseURL)
        try seedV2(conversations: [
            (id: "conv-1", turns: [
                turn(timestampMs: 1_780_000_000_000, model: "claude-sonnet-4.5",
                     userText: String(repeating: "u", count: 40), responseBytes: 40),
            ]),
        ])
        let second = LocalAdditionalUsageReader.kiroEntries(
            modifiedSince: since, knownSignatures: first.signatures, roots: [temporaryDirectory])
        XCTAssertEqual(second.entries.map(\.id), ["kiro|conv-1|1780000000000"])
    }

    /// #179 review: `existing` empties on a month-key change while a process-lifetime
    /// skip cache does not. The skip then returns `[]` and `dedupKeepMax([] + [])`
    /// zeros the week/block window that still reaches into last month.
    func testSkipDoesNotSurviveAnEmptyExistingSet() throws {
        let turnDate = try date("2026-08-31T12:00:00Z")
        let timestampMs = Int64(turnDate.timeIntervalSince1970 * 1000)
        try seedV2(conversations: [
            (id: "conv-1", turns: [
                turn(timestampMs: timestampMs, model: "claude-sonnet-4.5",
                     userText: String(repeating: "u", count: 40), responseBytes: 40),
            ]),
        ])

        let august = LocalAdditionalUsageReader.kiroEntries(
            modifiedSince: try date("2026-08-01T00:00:00Z"), roots: [temporaryDirectory])
        XCTAssertFalse(august.isEmpty, "the August scan must see the 31st turn")

        // Month rolls over: the actor drops `existing`. The skip must drop with it
        // so a week window starting Aug 30 still finds the turn.
        let september = LocalAdditionalUsageReader.kiroEntries(
            modifiedSince: try date("2026-08-30T00:00:00Z"), roots: [temporaryDirectory])
        XCTAssertFalse(
            LocalUsageReader.dedupKeepMax([] + september).isEmpty,
            "skip surviving an empty existing set zeros the week/block total across the 1st")
    }

    /// Option (b): skip state is an argument, not a process-lifetime map.
    /// A month-key drop sets `previous` to nil, so the actor passes `[:]` —
    /// the same contract this file's `[Entry]` overload uses. A static cache
    /// (or a test-only `clearKiroScanCache`) would re-introduce #179.
    func testSkipStateIsPassedByTheCallerNotHeldByTheReader() throws {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/PokeTokenBar/Core/LocalAdditionalUsageProvider.swift")
        let text = try String(contentsOf: source, encoding: .utf8)
        XCTAssertFalse(text.contains("KiroDatabaseScanCache"), "skip must not outlive Cached")
        XCTAssertFalse(text.contains("kiroScanCache"))
        XCTAssertFalse(text.contains("clearKiroScanCache"))
        XCTAssertFalse(text.contains("recordedKiroSignature"))
        XCTAssertTrue(
            text.contains("previous?.kiroSignatures"),
            "the actor must take skip state from the same Cached that holds existing")
        XCTAssertTrue(
            text.contains("let kiroSignatures:"),
            "signatures live next to entries, so a month-key drop invalidates both")
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
            XCTAssertTrue(roots.contains(expected), "legacy SQLite home must stay a default root")
        }
        XCTAssertFalse(roots.isEmpty)
    }

    /// Kiro CLI 2.20+ / `--v3` write JSONL under `~/.kiro/sessions`, not `data.sqlite3`.
    /// Injected `home` is the only safe way to assert this — the real home may have
    /// `KIRO_CLI_HOME` / `KIRO_HOME` set.
    func testDefaultRootsIncludeJsonlSessionsDirectory() {
        let home = URL(fileURLWithPath: "/Users/testhome")
        let roots = LocalAdditionalUsageReader.kiroRoots(customRootsValue: nil, home: home).map(\.path)
        XCTAssertTrue(roots.contains("/Users/testhome/Library/Application Support/kiro-cli"),
                      "SQLite path for pre-2.20 installs")
        XCTAssertTrue(roots.contains("/Users/testhome/.kiro/sessions"),
                      "JSONL sessions for Kiro CLI 2.20+ / v3")
    }

    /// #236: adding `~/.kiro` as an extra scan folder used to no-op because the reader
    /// only ever opened `data.sqlite3` under each root. The JSONL layouts live here.
    func testExtraRootFindsJsonlSessionsWithoutSqlite() throws {
        let kiroHome = temporaryDirectory.appendingPathComponent(".kiro")
        try seedCliSession(
            under: kiroHome,
            id: "session-1",
            prompt: String(repeating: "u", count: 400),
            assistant: String(repeating: "a", count: 200))

        let entries = LocalAdditionalUsageReader.kiroEntries(
            modifiedSince: try date("2026-01-01T00:00:00Z"), roots: [kiroHome])
        XCTAssertEqual(entries.count, 1, "a ~/.kiro extra folder with only JSONL must yield usage")
        XCTAssertEqual(entries.first?.input, 100)
        XCTAssertEqual(entries.first?.output, 50)
        XCTAssertNil(entries.first?.explicitCost, "credits are not API dollars; tokens stay an estimate")
    }

    // MARK: - JSONL sessions (CLI 2.20 / v3)

    /// Fixture keys copied from tokscale's `crates/tokscale-core/src/sessions/kiro.rs`
    /// contract tests (`version`/`kind`/`data.content[].kind=text`) — that parser was
    /// written against real `~/.kiro/sessions/cli/*.jsonl` files. Inventing a different
    /// envelope would pass here and miss every live session (#133).
    func testCliJsonlSessionIsReadFromWriterShapedEvents() throws {
        try seedCliSession(
            under: temporaryDirectory,
            id: "session-1",
            prompt: "hello world",
            assistant: "response text",
            model: "claude-sonnet-4-5",
            promptTimestampSeconds: 1_770_983_426.420942)

        let entries = LocalAdditionalUsageReader.kiroEntries(
            modifiedSince: try date("2026-01-01T00:00:00Z"), roots: [temporaryDirectory])
        let entry = try XCTUnwrap(entries.first)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entry.model, "claude-sonnet-4-5")
        XCTAssertEqual(entry.input, 11 / 4, "utf8 bytes/4, same estimator as the SQLite path")
        XCTAssertEqual(entry.output, 13 / 4)
        XCTAssertEqual(entry.id, "kiro|cli|session-1|1770983426420")
        XCTAssertNil(entry.explicitCost)
    }

    /// Same "whole conversation is resent" rule as the SQLite path — a later CLI turn's
    /// input is accumulated history, not just the newly typed prompt.
    func testCliJsonlLaterTurnAccumulatesHistory() throws {
        try seedCliSession(
            under: temporaryDirectory,
            id: "session-2",
            turns: [
                (prompt: String(repeating: "u", count: 400),
                 assistant: String(repeating: "a", count: 800),
                 timestampSeconds: 1_770_983_426.0),
                (prompt: String(repeating: "u", count: 40),
                 assistant: String(repeating: "a", count: 40),
                 timestampSeconds: 1_770_983_526.0),
            ])

        let entries = LocalAdditionalUsageReader.kiroEntries(
            modifiedSince: try date("2026-01-01T00:00:00Z"), roots: [temporaryDirectory])
        let second = try XCTUnwrap(entries.first { $0.id.hasSuffix("|1770983526000") })
        XCTAssertEqual(second.input, (400 + 800 + 40) / 4)
        XCTAssertEqual(second.output, 40 / 4)
    }

    /// v3 / IDE layout from the issue: `sessions/<workspace>/<session>/messages.jsonl`
    /// plus sibling `session.json`. Event shape from tokscale's structured-payload tests
    /// (`payload.type` = user/assistant/usage_summary/turn_end).
    func testV3MessagesJsonlSessionIsRead() throws {
        try seedV3Session(
            under: temporaryDirectory,
            workspace: "my-project",
            sessionID: "sess_abc",
            model: "claude-sonnet-4-5",
            prompt: String(repeating: "u", count: 400),
            assistant: String(repeating: "a", count: 200),
            timestamp: "2026-06-20T10:00:00Z",
            credits: 2.5)

        let entries = LocalAdditionalUsageReader.kiroEntries(
            modifiedSince: try date("2026-01-01T00:00:00Z"), roots: [temporaryDirectory])
        let entry = try XCTUnwrap(entries.first)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entry.model, "claude-sonnet-4-5")
        XCTAssertEqual(entry.input, 100)
        XCTAssertEqual(entry.output, 50)
        XCTAssertEqual(entry.id, "kiro|v3|sess_abc|0")
        XCTAssertNil(entry.explicitCost,
                     "usage_summary credits are not converted to USD (reportsCost stays false)")
    }

    /// A||B: the flat `{role,content}` messages.jsonl (no `payload` wrapper) is a
    /// documented sibling of the structured v3 format. Structured-only coverage
    /// would leave this branch untested.
    func testV3FlatRoleMessagesJsonlIsRead() throws {
        try seedV3FlatSession(
            under: temporaryDirectory,
            workspace: "ws",
            sessionID: "sess_flat",
            prompt: String(repeating: "u", count: 400),
            assistant: String(repeating: "a", count: 200),
            createdAt: "2026-06-30T12:57:10.991Z")

        let entries = LocalAdditionalUsageReader.kiroEntries(
            modifiedSince: try date("2026-01-01T00:00:00Z"), roots: [temporaryDirectory])
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.input, 100)
        XCTAssertEqual(entries.first?.output, 50)
    }

    /// Flat `{role,content}` lines often have no per-line timestamp (tokscale issue #813
    /// sample). Keying the entry id on `createdAt` millis then collides and
    /// `dedupKeepMax` drops the earlier turn.
    func testV3FlatMultiTurnWithoutTimestampsKeepsEveryTurn() throws {
        try seedV3FlatSession(
            under: temporaryDirectory,
            workspace: "ws",
            sessionID: "sess_multi",
            prompt: String(repeating: "u", count: 400),
            assistant: String(repeating: "a", count: 200),
            createdAt: "2026-06-30T12:57:10.991Z",
            extraTurns: [
                (prompt: String(repeating: "u", count: 40),
                 assistant: String(repeating: "a", count: 40)),
            ])

        let entries = LocalAdditionalUsageReader.kiroEntries(
            modifiedSince: try date("2026-01-01T00:00:00Z"), roots: [temporaryDirectory])
        XCTAssertEqual(entries.count, 2, "two turns sharing createdAt must not collapse")
        XCTAssertEqual(Set(entries.map(\.id)), ["kiro|v3|sess_multi|0", "kiro|v3|sess_multi|1"])
    }

    /// tokscale's v3 parser counts `payload.args` toward the turn's output. Ignoring
    /// `tool_call` undercounts agentic sessions where the model mostly emits tools.
    func testV3ToolCallArgsCountTowardOutput() throws {
        let dir = temporaryDirectory.appendingPathComponent("sessions/ws/sess_tools")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try """
        {"schemaVersion":"1.0.0","id":"sess_tools","modelId":"claude-sonnet-4-5","createdAt":"2026-06-20T10:00:00Z"}
        """.write(to: dir.appendingPathComponent("session.json"), atomically: true, encoding: .utf8)
        try """
        {"timestamp":"2026-06-20T10:00:00Z","payload":{"type":"user","content":"\(String(repeating: "u", count: 400))"}}
        {"payload":{"type":"tool_call","args":"\(String(repeating: "t", count: 200))"}}
        {"payload":{"type":"turn_end"},"timestamp":"2026-06-20T10:00:05Z"}
        """.write(to: dir.appendingPathComponent("messages.jsonl"), atomically: true, encoding: .utf8)

        let entry = try XCTUnwrap(LocalAdditionalUsageReader.kiroEntries(
            modifiedSince: try date("2026-01-01T00:00:00Z"), roots: [temporaryDirectory]).first)
        XCTAssertEqual(entry.input, 100)
        XCTAssertEqual(entry.output, 50, "tool_call args are output bytes, same as assistant text")
    }

    /// Pre-2.20 SQLite and post-2.20 JSONL are disjoint stores during the cutover.
    /// Both must count — JSONL is not a replacement that stops the SQLite scan.
    func testSqliteAndJsonlSessionsAreBothCounted() throws {
        try seedV2(conversations: [
            (id: "conv-sqlite", turns: [
                turn(timestampMs: 1_780_000_000_000, model: "claude-sonnet-4.5",
                     userText: String(repeating: "u", count: 400), responseBytes: 200),
            ]),
        ])
        try seedCliSession(
            under: temporaryDirectory,
            id: "session-jsonl",
            prompt: String(repeating: "u", count: 400),
            assistant: String(repeating: "a", count: 200))

        let entries = LocalAdditionalUsageReader.kiroEntries(
            modifiedSince: try date("2026-01-01T00:00:00Z"), roots: [temporaryDirectory])
        XCTAssertEqual(Set(entries.map(\.id)).count, 2)
        XCTAssertTrue(entries.contains { $0.id.hasPrefix("kiro|conv-sqlite|") })
        XCTAssertTrue(entries.contains { $0.id.hasPrefix("kiro|cli|session-jsonl|") })
    }

    func testMalformedJsonlLinesAreSkipped() throws {
        try seedCliSessionRaw(
            under: temporaryDirectory,
            id: "session-3",
            jsonl: """
            {"version":"v1","kind":"Prompt","data":{"message_id":"prompt-3","content":[{"kind":"text","data":"hello world"}],"meta":{"timestamp":1770983426.420942}}}
            not valid json at all
            {"version":"v1","kind":"AssistantMessage","data":{"message_id":"assistant-3","content":[{"kind":"text","data":"response text"}]}}
            """)

        let entries = LocalAdditionalUsageReader.kiroEntries(
            modifiedSince: try date("2026-01-01T00:00:00Z"), roots: [temporaryDirectory])
        XCTAssertEqual(entries.count, 1)
        XCTAssertGreaterThan((entries.first?.input ?? 0) + (entries.first?.output ?? 0), 0)
    }

    /// Unrelated `*.jsonl` next to the known layouts must not be ingested — the
    /// scanner is layout-shaped, not "every jsonl under the root".
    func testUnrelatedJsonlFilesAreIgnored() throws {
        let noise = temporaryDirectory.appendingPathComponent("notes.jsonl")
        try "{\"role\":\"user\",\"content\":\"ignore me please\"}\n".write(to: noise, atomically: true, encoding: .utf8)

        let entries = LocalAdditionalUsageReader.kiroEntries(
            modifiedSince: try date("2026-01-01T00:00:00Z"), roots: [temporaryDirectory])
        XCTAssertTrue(entries.isEmpty)
    }

    func testUnchangedJsonlSkipsTheRescan() throws {
        try seedCliSession(
            under: temporaryDirectory,
            id: "session-skip",
            prompt: String(repeating: "u", count: 40),
            assistant: String(repeating: "a", count: 40))
        let since = try date("2026-01-01T00:00:00Z")

        let first = LocalAdditionalUsageReader.kiroEntries(
            modifiedSince: since, knownSignatures: [:], roots: [temporaryDirectory])
        XCTAssertEqual(first.entries.count, 1)

        let second = LocalAdditionalUsageReader.kiroEntries(
            modifiedSince: since, knownSignatures: first.signatures, roots: [temporaryDirectory])
        XCTAssertTrue(second.entries.isEmpty, "unchanged JSONL must not be re-parsed")
        XCTAssertEqual(LocalUsageReader.dedupKeepMax(first.entries + second.entries).count, 1)
    }

    func testAppendedJsonlLineForcesARescan() throws {
        try seedCliSession(
            under: temporaryDirectory,
            id: "session-append",
            prompt: String(repeating: "u", count: 40),
            assistant: String(repeating: "a", count: 40))
        let since = try date("2026-01-01T00:00:00Z")
        let first = LocalAdditionalUsageReader.kiroEntries(
            modifiedSince: since, knownSignatures: [:], roots: [temporaryDirectory])
        XCTAssertEqual(first.entries.count, 1)

        let jsonl = temporaryDirectory
            .appendingPathComponent("sessions/cli/session-append.jsonl")
        let handle = try FileHandle(forWritingTo: jsonl)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("""
        {"version":"v1","kind":"Prompt","data":{"message_id":"prompt-2","content":[{"kind":"text","data":"next"}],"meta":{"timestamp":1770983526.0}}}
        {"version":"v1","kind":"AssistantMessage","data":{"message_id":"assistant-2","content":[{"kind":"text","data":"more"}]}}

        """.utf8))
        try handle.close()

        let second = LocalAdditionalUsageReader.kiroEntries(
            modifiedSince: since, knownSignatures: first.signatures, roots: [temporaryDirectory])
        XCTAssertGreaterThan(second.entries.count, 0, "a grown JSONL file must invalidate the skip")
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

    /// CLI 2.20 layout: `sessions/cli/<id>.jsonl` + companion `<id>.json`.
    /// Event envelope is tokscale's writer-shaped fixture (kind Prompt/AssistantMessage).
    private func seedCliSession(
        under root: URL,
        id: String,
        prompt: String,
        assistant: String,
        model: String = "claude-sonnet-4-5",
        promptTimestampSeconds: Double = 1_770_983_426.420942
    ) throws {
        try seedCliSession(
            under: root, id: id,
            turns: [(prompt: prompt, assistant: assistant, timestampSeconds: promptTimestampSeconds)],
            model: model)
    }

    private func seedCliSession(
        under root: URL,
        id: String,
        turns: [(prompt: String, assistant: String, timestampSeconds: Double)],
        model: String = "claude-sonnet-4-5"
    ) throws {
        var lines: [String] = []
        var messageIDs: [String] = []
        for (index, turn) in turns.enumerated() {
            let promptID = "prompt-\(index + 1)"
            let assistantID = "assistant-\(index + 1)"
            messageIDs += [promptID, assistantID]
            lines.append(
                #"{"version":"v1","kind":"Prompt","data":{"message_id":"\#(promptID)","content":[{"kind":"text","data":"\#(turn.prompt)"}],"meta":{"timestamp":\#(turn.timestampSeconds)}}}"#)
            lines.append(
                #"{"version":"v1","kind":"AssistantMessage","data":{"message_id":"\#(assistantID)","content":[{"kind":"text","data":"\#(turn.assistant)"}]}}"#)
        }
        let lastEnd = turns.last.map { Int($0.timestampSeconds) + 1 } ?? 0
        let idsJSON = messageIDs.map { "\"\($0)\"" }.joined(separator: ",")
        let companion = """
        {"session_id":"\(id)","cwd":"/tmp/project","created_at":"2026-02-13T12:00:00Z","updated_at":"2026-02-13T12:00:01Z","session_state":{"rts_model_state":{"model_info":{"model_id":"\(model)"}},"conversation_metadata":{"user_turn_metadatas":[{"input_token_count":0,"output_token_count":0,"end_timestamp":\(lastEnd),"total_request_count":\(turns.count),"message_ids":[\(idsJSON)]}]}}}
        """
        try seedCliSessionRaw(under: root, id: id, jsonl: lines.joined(separator: "\n") + "\n", companion: companion)
    }

    private func seedCliSessionRaw(
        under root: URL, id: String, jsonl: String,
        companion: String? = nil
    ) throws {
        let cli = root.appendingPathComponent("sessions/cli")
        try FileManager.default.createDirectory(at: cli, withIntermediateDirectories: true)
        try jsonl.write(to: cli.appendingPathComponent("\(id).jsonl"), atomically: true, encoding: .utf8)
        let meta = companion ?? "{\"session_id\":\"\(id)\",\"cwd\":\"/tmp\",\"created_at\":\"2026-02-13T12:00:00Z\",\"updated_at\":\"2026-02-13T12:00:00Z\"}"
        try meta.write(to: cli.appendingPathComponent("\(id).json"), atomically: true, encoding: .utf8)
    }

    /// v3 layout from issue #236: `sessions/<workspace>/<session>/{session.json,messages.jsonl}`.
    private func seedV3Session(
        under root: URL,
        workspace: String,
        sessionID: String,
        model: String,
        prompt: String,
        assistant: String,
        timestamp: String,
        credits: Double
    ) throws {
        let dir = root.appendingPathComponent("sessions/\(workspace)/\(sessionID)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let sessionJSON = """
        {"schemaVersion":"1.0.0","id":"\(sessionID)","modelId":"\(model)","createdAt":"\(timestamp)","lastModifiedAt":"\(timestamp)"}
        """
        try sessionJSON.write(to: dir.appendingPathComponent("session.json"), atomically: true, encoding: .utf8)
        let jsonl = """
        {"timestamp":"\(timestamp)","payload":{"type":"user","content":"\(prompt)"}}
        {"timestamp":"\(timestamp)","payload":{"type":"assistant","content":"\(assistant)"}}
        {"payload":{"type":"usage_summary","promptTurnSummaries":[{"usage":\(credits)}]}}
        {"payload":{"type":"turn_end"},"timestamp":"\(timestamp)"}
        """
        try jsonl.write(to: dir.appendingPathComponent("messages.jsonl"), atomically: true, encoding: .utf8)
    }

    private func seedV3FlatSession(
        under root: URL,
        workspace: String,
        sessionID: String,
        prompt: String,
        assistant: String,
        createdAt: String,
        extraTurns: [(prompt: String, assistant: String)] = []
    ) throws {
        let dir = root.appendingPathComponent("sessions/\(workspace)/\(sessionID)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let sessionJSON = """
        {"schemaVersion":"1.0.0","id":"\(sessionID)","createdAt":"\(createdAt)","lastModifiedAt":"\(createdAt)"}
        """
        try sessionJSON.write(to: dir.appendingPathComponent("session.json"), atomically: true, encoding: .utf8)
        var jsonl = """
        {"role":"user","content":"\(prompt)"}
        {"role":"assistant","content":"\(assistant)"}
        """
        for turn in extraTurns {
            jsonl += """

            {"role":"user","content":"\(turn.prompt)"}
            {"role":"assistant","content":"\(turn.assistant)"}
            """
        }
        try jsonl.write(to: dir.appendingPathComponent("messages.jsonl"), atomically: true, encoding: .utf8)
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
