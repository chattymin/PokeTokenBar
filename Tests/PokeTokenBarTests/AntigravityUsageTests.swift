import SQLite3
import XCTest
@testable import PokeTokenBar

/// The fixtures here encode the field numbers read out of the Antigravity CLI's own embedded
/// `FileDescriptorProto` pool — `ModelUsageStats` 2/3/4/5/11, `ChatStartMetadata.created_at` 4,
/// `ChatModelMetadata.response_model` 19. They are not a guess at the shape, and the same
/// mapping was run against the live store (3,934 records) before it was written down here.
final class AntigravityUsageTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PokeTokenBar-AntigravityUsageTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
        temporaryDirectory = nil
    }

    // MARK: - Token mapping

    /// `input_tokens` excludes cache reads and `output_tokens` already contains the thinking
    /// half, so neither may be adjusted the way the Gemini CLI parser adjusts its own fields.
    func testTokenMappingKeepsTheWriterSemantics() throws {
        try writeConversation("c1", records: [
            record(responseID: "r1", model: "gemini-3.6-flash", createdAt: try date("2026-03-04T10:00:00Z"),
                   input: 4667, output: 462, cacheRead: 52968, thinking: 398, response: 64),
        ])

        let entry = try XCTUnwrap(readAll().first)
        XCTAssertEqual(entry.input, 4667, "input_tokens is already net of the cache read")
        XCTAssertEqual(entry.cacheRead, 52968)
        XCTAssertEqual(entry.output, 462, "output_tokens already sums thinking and response")
        XCTAssertEqual(entry.cacheWrite, 0)
        XCTAssertEqual(entry.model, "antigravity/gemini-3.6-flash")
    }

    /// The schema has no total field, so the total is whatever the three counters add up to —
    /// which is the identity `Entry.total` already keeps for every other provider.
    func testTotalIsTheSumOfTheCountersBecauseTheSourceHasNoTotal() throws {
        try writeConversation("c1", records: [
            record(responseID: "r1", model: "gemini-3.6-flash", createdAt: try date("2026-03-04T10:00:00Z"),
                   input: 100, output: 20, cacheRead: 300),
        ])

        let entry = try XCTUnwrap(readAll().first)
        XCTAssertEqual(entry.total, 420)
    }

    func testThinkingAndResponseAreNotAddedOnTopOfOutput() throws {
        try writeConversation("c1", records: [
            record(responseID: "r1", model: "gemini-3.6-flash", createdAt: try date("2026-03-04T10:00:00Z"),
                   input: 10, output: 900, cacheRead: 0, thinking: 800, response: 100),
        ])

        let entry = try XCTUnwrap(readAll().first)
        XCTAssertEqual(entry.output, 900, "adding the siblings to their own sum would double the output")
    }

    func testRowWithNoTokensProducesNoEntry() throws {
        try writeConversation("c1", records: [
            record(responseID: "r1", model: "gemini-3.6-flash", createdAt: try date("2026-03-04T10:00:00Z"),
                   input: 0, output: 0, cacheRead: 0),
        ])

        XCTAssertTrue(readAll().isEmpty)
    }

    // MARK: - Identity

    /// The turn's own id, so the same call copied into a second conversation store stays one
    /// charge rather than becoming two.
    func testResponseIdDeduplicatesAcrossConversations() throws {
        let shared = record(responseID: "same-call", model: "gemini-3.6-flash",
                            createdAt: try date("2026-03-04T10:00:00Z"),
                            input: 100, output: 20, cacheRead: 300)
        try writeConversation("c1", records: [shared])
        try writeConversation("c2", records: [shared])

        let entries = readAll()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.id, "antigravity|same-call")
    }

    func testRecordWithoutResponseIdFallsBackToConversationAndIndex() throws {
        try writeConversation("c1", records: [
            record(responseID: nil, model: "gemini-3.6-flash", createdAt: try date("2026-03-04T10:00:00Z"),
                   input: 100, output: 20, cacheRead: 300),
        ])

        XCTAssertEqual(readAll().first?.id, "antigravity|c1|0")
    }

    // MARK: - Time

    func testCreatedAtDrivesTheLocalDay() throws {
        let created = try date("2026-03-04T10:00:00Z")
        try writeConversation("c1", records: [
            record(responseID: "r1", model: "gemini-3.6-flash", createdAt: created,
                   input: 100, output: 20, cacheRead: 300),
        ])

        let entry = try XCTUnwrap(readAll().first)
        XCTAssertEqual(entry.date.timeIntervalSince1970, created.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(entry.localDay, LocalUsageReader.localDayFormatter().string(from: created))
    }

    func testRecordsBeforeTheWindowAreExcluded() throws {
        try writeConversation("c1", records: [
            record(responseID: "old", model: "gemini-3.6-flash", createdAt: try date("2026-03-01T10:00:00Z"),
                   input: 100, output: 20, cacheRead: 300),
            record(responseID: "new", model: "gemini-3.6-flash", createdAt: try date("2026-03-09T10:00:00Z"),
                   input: 100, output: 20, cacheRead: 300),
        ])

        let entries = LocalAntigravityUsageReader.entries(
            modifiedSince: try date("2026-03-05T00:00:00Z"), root: temporaryDirectory)
        XCTAssertEqual(entries.map(\.id), ["antigravity|new"])
    }

    /// A timestamp outside any plausible window is a misread varint, not a date — building a
    /// `Date` from it would hand nonsense to every window calculation downstream.
    func testImplausibleTimestampIsRejected() throws {
        try writeConversation("c1", records: [
            record(responseID: "r1", model: "gemini-3.6-flash", createdAtSeconds: UInt64.max,
                   input: 100, output: 20, cacheRead: 300),
            record(responseID: "r2", model: "gemini-3.6-flash", createdAtSeconds: 0,
                   input: 100, output: 20, cacheRead: 300),
        ])

        XCTAssertTrue(readAll().isEmpty)
    }

    // MARK: - Hostile input

    /// A `uint64` sentinel widened into `Int` would trap the process on the next addition, and
    /// it would trap again on every refresh because the file never changes.
    func testSentinelTokenCountIsDiscardedRatherThanTrapping() throws {
        try writeConversation("c1", records: [
            record(responseID: "r1", model: "gemini-3.6-flash", createdAt: try date("2026-03-04T10:00:00Z"),
                   input: UInt64.max, output: 20, cacheRead: 300),
        ])

        let entry = try XCTUnwrap(readAll().first)
        XCTAssertEqual(entry.input, 0)
        XCTAssertEqual(entry.total, 320, "the rest of the record still counts")
    }

    func testMalformedBlobIsIgnored() throws {
        try writeConversation("c1", blobs: [Data([0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF])])
        XCTAssertTrue(readAll().isEmpty)
    }

    func testTruncatedBlobIsIgnored() throws {
        var bytes = [UInt8](makeRecord(responseID: "r1", model: "gemini-3.6-flash",
                                       createdAtSeconds: 1_772_618_400,
                                       input: 100, output: 20, cacheRead: 300))
        bytes.removeLast(bytes.count / 2)
        try writeConversation("c1", blobs: [Data(bytes)])
        XCTAssertTrue(readAll().isEmpty)
    }

    func testMissingDirectoryYieldsNoEntries() {
        let absent = temporaryDirectory.appendingPathComponent("not-here")
        XCTAssertTrue(LocalAntigravityUsageReader.entries(modifiedSince: .distantPast, root: absent).isEmpty)
    }

    func testDatabaseWithoutTheExpectedTableIsIgnored() throws {
        let database = temporaryDirectory.appendingPathComponent("c1.db")
        try execute(database, sql: "CREATE TABLE something_else (a INTEGER);")
        XCTAssertTrue(readAll().isEmpty)
    }

    // MARK: - Opening WAL databases read-only

    /// Every conversation store is in WAL mode. A checkpointed one has no `-wal` sibling, and
    /// `mode=ro` cannot create the `-shm` file it would need — 28 of the 124 stores on the
    /// machine this was written on fail that way. The reader has to fall back.
    func testCheckpointedWalDatabaseIsStillReadable() throws {
        try writeConversation("c1", records: [
            record(responseID: "r1", model: "gemini-3.6-flash", createdAt: try date("2026-03-04T10:00:00Z"),
                   input: 100, output: 20, cacheRead: 300),
        ], walMode: true)
        let database = temporaryDirectory.appendingPathComponent("c1.db")
        try checkpointAndDropWalSiblings(database)

        // Assert the condition the fallback exists for, so this test cannot pass through the
        // ordinary path and quietly stop covering it.
        XCTAssertNil(openReadOnlyWithoutFallback(database),
                     "mode=ro must fail here — otherwise this no longer exercises the fallback")
        XCTAssertEqual(readAll().count, 1)
    }

    /// A WAL commit lands in the sibling and leaves the main file's timestamp untouched, so a
    /// scan keyed on the `.db` alone would skip exactly the conversations that just moved.
    func testWalSiblingTimestampSelectsTheDatabase() throws {
        try writeConversation("c1", records: [
            record(responseID: "r1", model: "gemini-3.6-flash", createdAt: try date("2026-03-04T10:00:00Z"),
                   input: 100, output: 20, cacheRead: 300),
        ])
        let database = temporaryDirectory.appendingPathComponent("c1.db")
        let stale = try date("2020-01-01T00:00:00Z")
        try FileManager.default.setAttributes([.modificationDate: stale], ofItemAtPath: database.path)
        FileManager.default.createFile(atPath: database.path + "-wal", contents: Data([0]))

        let fresh = try XCTUnwrap(LocalAntigravityUsageReader.effectiveModificationDate(of: database))
        XCTAssertGreaterThan(fresh, stale)
        XCTAssertEqual(LocalAntigravityUsageReader.entries(
            modifiedSince: try date("2026-01-01T00:00:00Z"), root: temporaryDirectory).count, 1)
    }

    // MARK: - Pricing

    /// Antigravity is a subscription and reports no amount, so an estimate would be an
    /// invented bill. The prefix keeps the names out of the exact table as well — this CLI
    /// really does call `claude-sonnet-4-6`, which the table prices.
    func testAntigravityUsageIsNotPriced() {
        for model in ["gemini-3.6-flash", "gemini-3-flash-e", "gemini-default", "claude-sonnet-4-6"] {
            XCTAssertEqual(
                ModelPricing.cost(model: "antigravity/\(model)",
                                  input: 1_000_000, output: 1_000_000,
                                  cacheWrite: 1_000_000, cacheRead: 1_000_000),
                0, accuracy: 0.0000001, "antigravity/\(model) must not be priced")
        }
        XCTAssertGreaterThan(
            ModelPricing.cost(model: "claude-sonnet-4-6", input: 1_000_000, output: 0,
                              cacheWrite: 0, cacheRead: 0),
            0, "the unprefixed name must keep its rate")
    }

    // MARK: - Fixtures

    private func readAll() -> [LocalUsageReader.Entry] {
        LocalAntigravityUsageReader.entries(modifiedSince: .distantPast, root: temporaryDirectory)
    }

    private func date(_ text: String) throws -> Date {
        try XCTUnwrap(ISO8601DateFormatter().date(from: text))
    }

    private func record(
        responseID: String?,
        model: String,
        createdAt: Date,
        input: UInt64,
        output: UInt64,
        cacheRead: UInt64,
        thinking: UInt64? = nil,
        response: UInt64? = nil
    ) -> Data {
        makeRecord(responseID: responseID, model: model,
                   createdAtSeconds: UInt64(createdAt.timeIntervalSince1970),
                   input: input, output: output, cacheRead: cacheRead,
                   thinking: thinking, response: response)
    }

    private func record(
        responseID: String?,
        model: String,
        createdAtSeconds: UInt64,
        input: UInt64,
        output: UInt64,
        cacheRead: UInt64
    ) -> Data {
        makeRecord(responseID: responseID, model: model, createdAtSeconds: createdAtSeconds,
                   input: input, output: output, cacheRead: cacheRead)
    }

    /// `CortexStepGeneratorMetadata { 1 chat_model { 4 usage, 9 chat_start_metadata, 19 response_model } }`
    private func makeRecord(
        responseID: String?,
        model: String,
        createdAtSeconds: UInt64,
        input: UInt64,
        output: UInt64,
        cacheRead: UInt64,
        thinking: UInt64? = nil,
        response: UInt64? = nil
    ) -> Data {
        var usage = AntigravityProto.encodeVarint(field: 1, 1071)          // model enum
        usage += AntigravityProto.encodeVarint(field: 2, input)            // input_tokens
        usage += AntigravityProto.encodeVarint(field: 3, output)           // output_tokens
        usage += AntigravityProto.encodeVarint(field: 5, cacheRead)        // cache_read_tokens
        usage += AntigravityProto.encodeVarint(field: 6, 24)               // api_provider
        if let thinking { usage += AntigravityProto.encodeVarint(field: 9, thinking) }
        if let response { usage += AntigravityProto.encodeVarint(field: 10, response) }
        if let responseID { usage += AntigravityProto.encodeString(field: 11, responseID) }

        let timestamp = AntigravityProto.encodeVarint(field: 1, createdAtSeconds)
        let chatStart = AntigravityProto.encodeMessage(field: 4, timestamp)

        var chatModel = AntigravityProto.encodeVarint(field: 3, 1071)
        chatModel += AntigravityProto.encodeMessage(field: 4, usage)
        chatModel += AntigravityProto.encodeMessage(field: 9, chatStart)
        chatModel += AntigravityProto.encodeString(field: 19, model)

        return Data(AntigravityProto.encodeMessage(field: 1, chatModel))
    }

    private func writeConversation(_ name: String, records: [Data], walMode: Bool = false) throws {
        try writeConversation(name, blobs: records, walMode: walMode)
    }

    private func writeConversation(_ name: String, blobs: [Data], walMode: Bool = false) throws {
        let database = temporaryDirectory.appendingPathComponent("\(name).db")
        var sql = walMode ? "PRAGMA journal_mode=WAL;\n" : ""
        sql += "CREATE TABLE gen_metadata (idx integer, data blob, size integer NOT NULL DEFAULT 0, PRIMARY KEY (idx));\n"
        for (index, blob) in blobs.enumerated() {
            sql += "INSERT INTO gen_metadata VALUES (\(index), X'\(blob.map { String(format: "%02x", $0) }.joined())', \(blob.count));\n"
        }
        try execute(database, sql: sql)
    }

    /// Reproduces a conversation that has been fully checkpointed: the rows are in the main
    /// file and the siblings are gone. That is the state 28 of the 124 live stores are in.
    private func checkpointAndDropWalSiblings(_ database: URL) throws {
        try execute(database, sql: "PRAGMA wal_checkpoint(TRUNCATE);")
        for suffix in ["-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: database.path + suffix)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: database.path + "-wal"))
    }

    private func openReadOnlyWithoutFallback(_ database: URL) -> OpaquePointer? {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2("file:\(database.path)?mode=ro", &handle, flags, nil) == SQLITE_OK else {
            if let handle { sqlite3_close(handle) }
            return nil
        }
        // Opening can succeed lazily; the read is what actually needs the -shm file.
        var statement: OpaquePointer?
        let prepared = sqlite3_prepare_v2(handle, "SELECT count(*) FROM gen_metadata", -1, &statement, nil)
        let stepped = prepared == SQLITE_OK ? sqlite3_step(statement) : SQLITE_ERROR
        sqlite3_finalize(statement)
        guard stepped == SQLITE_ROW else {
            sqlite3_close(handle)
            return nil
        }
        return handle
    }

    private func execute(_ databaseURL: URL, sql: String) throws {
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &database), SQLITE_OK)
        defer { sqlite3_close(database) }
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(database, sql, nil, nil, &errorMessage)
        if result != SQLITE_OK {
            let message = errorMessage.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(errorMessage)
            XCTFail("sqlite: \(message)")
        }
    }
}

// MARK: - Wire format encoding, test side only

private extension AntigravityProto {
    static func encodeRawVarint(_ value: UInt64) -> [UInt8] {
        var value = value
        var bytes: [UInt8] = []
        while true {
            let byte = UInt8(value & 0x7f)
            value >>= 7
            if value == 0 {
                bytes.append(byte)
                return bytes
            }
            bytes.append(byte | 0x80)
        }
    }

    static func encodeVarint(field: Int, _ value: UInt64) -> [UInt8] {
        encodeRawVarint(UInt64(field) << 3) + encodeRawVarint(value)
    }

    static func encodeMessage(field: Int, _ payload: [UInt8]) -> [UInt8] {
        encodeRawVarint(UInt64(field) << 3 | 2) + encodeRawVarint(UInt64(payload.count)) + payload
    }

    static func encodeString(field: Int, _ text: String) -> [UInt8] {
        encodeMessage(field: field, [UInt8](text.utf8))
    }
}
