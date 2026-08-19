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

    /// New Antigravity stores omit `chat_start_metadata.created_at` from the generation blob.
    /// The generation still carries an `execution_id` at field 4, but that id is shared by
    /// multiple generations. The response id remains the per-generation correlation key at
    /// `field 1 → field 4 → field 11`; the step metadata mirrors it at `field 9 → field 11`.
    func testCurrentGenerationFormatUsesStepMetadataTimestamp() throws {
        let firstID = "synthetic-new-format-call-1"
        let secondID = "synthetic-new-format-call-2"
        let executionID = "00000000-0000-0000-0000-000000000001"
        let firstDate = try date("2026-08-19T10:00:00Z")
        let secondDate = try date("2026-08-19T10:01:00Z")
        try writeConversation(
            "c1",
            blobs: [
                currentFormatRecord(responseID: firstID, executionID: executionID, createdAt: firstDate,
                                    input: 100, output: 20, cacheRead: 300),
                currentFormatRecord(responseID: secondID, executionID: executionID, createdAt: secondDate,
                                    input: 200, output: 30, cacheRead: 400),
            ],
            // Deliberately reverse the rows: correlation must use response_id, not execution_id
            // or table order.
            stepMetadata: [
                stepMetadata(responseID: secondID, executionID: executionID, createdAt: secondDate),
                stepMetadata(responseID: firstID, executionID: executionID, createdAt: firstDate),
            ])

        let entries = readAll()
        XCTAssertEqual(entries.count, 2)
        let byID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        let first = try XCTUnwrap(byID["antigravity|\(firstID)"])
        let second = try XCTUnwrap(byID["antigravity|\(secondID)"])
        XCTAssertEqual(first.date.timeIntervalSince1970, firstDate.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(second.date.timeIntervalSince1970, secondDate.timeIntervalSince1970, accuracy: 0.001)
        let formatter = LocalUsageReader.localDayFormatter()
        XCTAssertEqual(first.localDay, formatter.string(from: firstDate))
        XCTAssertEqual(second.localDay, formatter.string(from: secondDate))
        XCTAssertEqual(first.total, 420)
        XCTAssertEqual(second.total, 630)
    }

    func testCurrentFormatPreservesEachRecordAcrossLocalMidnight() throws {
        let firstID = "synthetic-midnight-call-1"
        let secondID = "synthetic-midnight-call-2"
        let executionID = "00000000-0000-0000-0000-000000000002"
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let firstDate = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 18, hour: 23, minute: 59)))
        let secondDate = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 19, hour: 0, minute: 1)))

        try writeConversation(
            "c1",
            blobs: [
                currentFormatRecord(responseID: firstID, executionID: executionID, createdAt: firstDate,
                                    input: 100, output: 20, cacheRead: 300),
                currentFormatRecord(responseID: secondID, executionID: executionID, createdAt: secondDate,
                                    input: 200, output: 30, cacheRead: 400),
            ],
            stepMetadata: [
                stepMetadata(responseID: secondID, executionID: executionID, createdAt: secondDate),
                stepMetadata(responseID: firstID, executionID: executionID, createdAt: firstDate),
            ])

        let entries = readAll()
        let byID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        let first = try XCTUnwrap(byID["antigravity|\(firstID)"])
        let second = try XCTUnwrap(byID["antigravity|\(secondID)"])
        let formatter = LocalUsageReader.localDayFormatter()
        XCTAssertEqual(first.localDay, formatter.string(from: firstDate))
        XCTAssertEqual(second.localDay, formatter.string(from: secondDate))
        XCTAssertNotEqual(first.localDay, second.localDay)
    }

    func testLegacyCreatedAtRemainsPreferredOverStepMetadataTimestamp() throws {
        let responseID = "synthetic-legacy-precedence"
        let legacyDate = try date("2026-08-18T10:00:00Z")
        let stepDate = try date("2026-08-19T10:00:00Z")
        try writeConversation(
            "c1",
            records: [
                record(responseID: responseID, model: "gemini-3.6-flash", createdAt: legacyDate,
                       input: 100, output: 20, cacheRead: 300),
            ],
            stepMetadata: [
                stepMetadata(responseID: responseID,
                             executionID: "00000000-0000-0000-0000-000000000003",
                             createdAt: stepDate),
            ])

        let entry = try XCTUnwrap(readAll().first)
        XCTAssertEqual(entry.date.timeIntervalSince1970, legacyDate.timeIntervalSince1970, accuracy: 0.001)
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
    /// it would trap again on every refresh because the file never changes. Dropping it is
    /// right; dropping it silently makes the turn read as one that used no input at all.
    func testSentinelTokenCountIsDiscardedRatherThanTrapping() throws {
        try writeConversation("c1", records: [
            record(responseID: "r1", model: "gemini-3.6-flash", createdAt: try date("2026-03-04T10:00:00Z"),
                   input: UInt64.max, output: 20, cacheRead: 300),
        ])

        let entry = try XCTUnwrap(readAll().first)
        XCTAssertEqual(entry.input, 0)
        XCTAssertEqual(entry.total, 320, "the rest of the record still counts")

        let read = readConversation("c1")
        guard case .complete(_, let discarded) = read else { return XCTFail("expected a complete read") }
        XCTAssertEqual(discarded, 1)
        let line = try XCTUnwrap(
            LocalAntigravityUsageReader.discardLog([(conversation: "c1", read: read)]).first)
        XCTAssertTrue(line.contains("conversation=c1"), line)
        XCTAssertTrue(line.contains("discarded=1"), line)
    }

    /// A counter the writer never sets is a zero, not a bad value — `cache_write_tokens` is
    /// declared and never written, so treating "absent" as a discard would report every single
    /// record on every scan.
    func testAbsentCounterIsNotADiscard() throws {
        try writeConversation("c1", records: [
            record(responseID: "r1", model: "gemini-3.6-flash", createdAt: try date("2026-03-04T10:00:00Z"),
                   input: 100, output: 20, cacheRead: 300),
        ])

        let read = readConversation("c1")
        guard case .complete(let entries, let discarded) = read else {
            return XCTFail("expected a complete read")
        }
        XCTAssertEqual(entries.first?.cacheWrite, 0)
        XCTAssertEqual(discarded, 0)
        XCTAssertTrue(LocalAntigravityUsageReader.discardLog([(conversation: "c1", read: read)]).isEmpty)
    }

    /// Same bound as the loss lines, and for the same reason.
    func testDiscardLogNamesAFewStoresAndCountsTheRest() {
        let limit = LocalAntigravityUsageReader.namedLossLimit
        let reads = (0..<(limit + 2)).map {
            (conversation: "c\($0)",
             read: LocalAntigravityUsageReader.ConversationRead.complete(entries: [], discardedCounters: 3))
        }

        let lines = LocalAntigravityUsageReader.discardLog(reads)
        XCTAssertEqual(lines.count, limit + 1)
        XCTAssertEqual(lines.last?.contains("in \(limit + 2) conversation(s)"), true, lines.last ?? "")
        XCTAssertEqual(lines.last?.contains("(2 not named)"), true, lines.last ?? "")
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

    // MARK: - A lost conversation leaves a trace

    /// A scan that cannot finish drops the rows it did read, which is right, and used to say
    /// nothing about it, which is not: the result is indistinguishable from a conversation with
    /// no usage, so a store that could never be read to the end read as no spend, for as long
    /// as it stayed that way.
    func testIncompleteScanDropsTheConversationAndNamesTheReason() throws {
        try writeManyRecords("c1", count: 60, pageSize: 512)
        try writeConversation("c2", records: [
            record(responseID: "survivor", model: "gemini-3.6-flash",
                   createdAt: try date("2026-03-04T10:00:00Z"), input: 100, output: 20, cacheRead: 300),
        ])
        let database = temporaryDirectory.appendingPathComponent("c1.db")
        try corruptLastPage(database, pageSize: 512)

        // Assert the branch this test exists for is the one being walked: the store still opens
        // and still hands back rows, so the loss can only be coming from the step loop. Without
        // this the test would keep passing if the failure moved to the open.
        let probe = try stepUntilNotARow(database)
        XCTAssertGreaterThan(probe.rows, 0, "no rows read — the failure moved to open/prepare")
        XCTAssertNotEqual(probe.status, SQLITE_DONE, "the scan finished — this no longer covers the drop")

        let read = readConversation("c1")
        guard case .incompleteScan(let status, let rows) = read else {
            return XCTFail("expected an incomplete scan, got \(read)")
        }
        XCTAssertEqual(status, probe.status)
        XCTAssertGreaterThan(rows, 0)
        XCTAssertTrue(read.entries.isEmpty, "half a conversation must not pass for the whole of it")

        let lines = LocalAntigravityUsageReader.lossLog([(conversation: "c1", read: read)])
        XCTAssertEqual(lines.count, 1)
        let line = try XCTUnwrap(lines.first)
        XCTAssertTrue(line.contains("conversation=c1"), line)
        XCTAssertTrue(line.contains("reason=scan-incomplete"), line)
        XCTAssertTrue(line.contains("status=\(status)"), line)
        XCTAssertTrue(line.contains("rows=\(rows)"), line)

        // The rest of the directory is unaffected — one bad store, not a bad scan.
        XCTAssertEqual(Set(readAll().map(\.id)), ["antigravity|survivor"])
    }

    /// A file that is not a database at all must read as unreadable rather than as an empty
    /// conversation — the two are the same zero, and only one of them is about usage.
    func testUnreadableStoreIsNotAnEmptyConversation() throws {
        let database = temporaryDirectory.appendingPathComponent("c1.db")
        try Data("not a sqlite database".utf8).write(to: database, options: .atomic)

        let read = readConversation("c1")
        guard case .unreadable = read else { return XCTFail("expected unreadable, got \(read)") }
        XCTAssertTrue(read.entries.isEmpty)

        let line = try XCTUnwrap(LocalAntigravityUsageReader.lossLog([(conversation: "c1", read: read)]).first)
        XCTAssertTrue(line.contains("conversation=c1"), line)
        XCTAssertTrue(line.contains("reason=unreadable"), line)
    }

    /// The opposite case, and the reason the reader cannot simply log every empty read: this
    /// directory may hold databases that are not conversation stores. A missing `gen_metadata`
    /// is a permanent fact about the file, so naming it would repeat every refresh forever.
    func testDatabaseWithoutTheExpectedTableIsNotReportedAsALoss() throws {
        let database = temporaryDirectory.appendingPathComponent("c1.db")
        try execute(database, sql: "CREATE TABLE something_else (a INTEGER);")

        let read = readConversation("c1")
        guard case .notAConversation = read else { return XCTFail("expected notAConversation, got \(read)") }
        XCTAssertTrue(LocalAntigravityUsageReader.lossLog([(conversation: "c1", read: read)]).isEmpty)
    }

    /// A directory that has gone bad wholesale must not be able to rotate the log — `AppLog`
    /// keeps 2 MB and the crash history lives in the same file.
    func testLossLogNamesAFewStoresAndCountsTheRest() {
        let limit = LocalAntigravityUsageReader.namedLossLimit
        let reads = (0..<(limit + 4)).map {
            (conversation: "c\($0)", read: LocalAntigravityUsageReader.ConversationRead.unreadable(status: nil))
        }

        let lines = LocalAntigravityUsageReader.lossLog(reads)
        XCTAssertEqual(lines.count, limit + 1)
        let summary = try? XCTUnwrap(lines.last)
        XCTAssertEqual(summary?.contains("lost \(limit + 4) conversation(s)"), true, lines.last ?? "")
        XCTAssertEqual(summary?.contains("(4 not named)"), true, lines.last ?? "")
    }

    /// A clean scan says nothing at all.
    func testCompleteScanLogsNothing() throws {
        try writeConversation("c1", records: [
            record(responseID: "r1", model: "gemini-3.6-flash",
                   createdAt: try date("2026-03-04T10:00:00Z"), input: 100, output: 20, cacheRead: 300),
        ])
        let read = readConversation("c1")
        XCTAssertEqual(read.entries.count, 1)
        XCTAssertTrue(LocalAntigravityUsageReader.lossLog([(conversation: "c1", read: read)]).isEmpty)
        XCTAssertTrue(LocalAntigravityUsageReader.discardLog([(conversation: "c1", read: read)]).isEmpty)
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

        let fresh = try XCTUnwrap(LocalAntigravityUsageReader.signature(of: database))
        XCTAssertGreaterThan(fresh.mtime, stale)
        XCTAssertEqual(LocalAntigravityUsageReader.entries(
            modifiedSince: try date("2026-01-01T00:00:00Z"), root: temporaryDirectory).count, 1)
    }

    // MARK: - Not re-reading what has not changed

    /// The blob stands in for the store while its signature holds — the point of keying on the
    /// signature at all is that an unchanged store is never reopened.
    func testStoreWithAnUnchangedSignatureIsNotReread() throws {
        try writeConversation("c1", records: [
            record(responseID: "onDisk", model: "gemini-3.6-flash",
                   createdAt: try date("2026-03-04T10:00:00Z"), input: 100, output: 20, cacheRead: 300),
        ])
        let database = temporaryDirectory.appendingPathComponent("c1.db")
        let planted = try plantedBlob(for: database)

        let scanned = scan(known: [database.path: planted])
        XCTAssertEqual(scanned.blobs[database.path]?.entries.map(\.id), ["planted"],
                       "the store was reopened even though nothing about it had changed")
    }

    /// The commit a WAL database actually makes: the `.db` is untouched and the `-wal` grows.
    func testWalCommitInvalidatesTheBlob() throws {
        try writeConversation("c1", records: [
            record(responseID: "onDisk", model: "gemini-3.6-flash",
                   createdAt: try date("2026-03-04T10:00:00Z"), input: 100, output: 20, cacheRead: 300),
        ])
        let database = temporaryDirectory.appendingPathComponent("c1.db")
        let planted = try plantedBlob(for: database)
        FileManager.default.createFile(atPath: database.path + "-wal", contents: Data([0, 1, 2, 3]))

        let scanned = scan(known: [database.path: planted])
        XCTAssertEqual(scanned.blobs[database.path]?.entries.map(\.id), ["antigravity|onDisk"],
                       "a WAL commit must invalidate the blob — the `.db` alone never moves")
    }

    /// The other half, and the reason `-shm` is not in the key: a read-only connection writes
    /// read marks into it, so a signature that included it would be invalidated by this very
    /// reader, on every scan, and the cache would never hit at all.
    func testShmChurnDoesNotInvalidateTheBlob() throws {
        try writeConversation("c1", records: [
            record(responseID: "onDisk", model: "gemini-3.6-flash",
                   createdAt: try date("2026-03-04T10:00:00Z"), input: 100, output: 20, cacheRead: 300),
        ])
        let database = temporaryDirectory.appendingPathComponent("c1.db")
        let planted = try plantedBlob(for: database)
        FileManager.default.createFile(atPath: database.path + "-shm", contents: Data([9, 9, 9, 9]))

        let scanned = scan(known: [database.path: planted])
        XCTAssertEqual(scanned.blobs[database.path]?.entries.map(\.id), ["planted"],
                       "`-shm` churn is somebody reading the store, not somebody writing to it")
    }

    /// A read that did not finish must not be filed under the current signature: the store would
    /// then read as no usage for as long as it sat still, and the next refresh — the whole
    /// reason the partial read was discarded — would never come.
    func testIncompleteScanKeepsThePreviousRowsUnderTheirOldSignature() throws {
        try writeManyRecords("c1", count: 60, pageSize: 512)
        let database = temporaryDirectory.appendingPathComponent("c1.db")
        try corruptLastPage(database, pageSize: 512)
        let stale = LocalAntigravityUsageReader.Blob(
            mtime: .distantPast, size: 0,
            entries: try plantedBlob(for: database).entries)

        let scanned = scan(known: [database.path: stale])
        let blob = try XCTUnwrap(scanned.blobs[database.path])
        XCTAssertEqual(blob.entries.map(\.id), ["planted"], "the rows already known were thrown away")
        XCTAssertEqual(blob.mtime, .distantPast, "the old signature must survive so the next scan retries")
    }

    /// With nothing to carry forward there must be no blob at all — an empty one would freeze
    /// the store as "no usage" until something happened to change it.
    func testUnreadableStoreIsNotCachedAsAnEmptyConversation() throws {
        let database = temporaryDirectory.appendingPathComponent("c1.db")
        try Data("not a sqlite database".utf8).write(to: database, options: .atomic)

        XCTAssertNil(scan().blobs[database.path])
    }

    /// The opposite: a database with no `gen_metadata` will never grow one, so caching its empty
    /// is what stops it being reopened on every refresh for the life of the install.
    func testDatabaseWithoutTheExpectedTableIsCachedAsEmpty() throws {
        let database = temporaryDirectory.appendingPathComponent("c1.db")
        try execute(database, sql: "CREATE TABLE something_else (a INTEGER);")

        let blob = try XCTUnwrap(scan().blobs[database.path])
        XCTAssertTrue(blob.entries.isEmpty)
        XCTAssertEqual(blob.mtime, LocalAntigravityUsageReader.signature(of: database)?.mtime)
    }

    /// A store that drops out of the window leaves the cache with it — the sweep rebuilds from
    /// what it visited, so there is no separate prune to forget to run.
    func testStoresOutsideTheWindowLeaveTheCache() throws {
        try writeConversation("c1", records: [
            record(responseID: "old", model: "gemini-3.6-flash",
                   createdAt: try date("2020-01-01T10:00:00Z"), input: 100, output: 20, cacheRead: 300),
        ])
        let database = temporaryDirectory.appendingPathComponent("c1.db")
        try FileManager.default.setAttributes(
            [.modificationDate: try date("2020-01-02T00:00:00Z")], ofItemAtPath: database.path)
        let planted = try plantedBlob(for: database)

        let scanned = scan(known: [database.path: planted], modifiedSince: try date("2026-03-01T00:00:00Z"))
        XCTAssertTrue(scanned.blobs.isEmpty)
    }

    /// The behaviour the 30-second expiry could not give: a store that changed a moment ago is
    /// read a moment ago, not up to half a minute later.
    func testCacheSeesAChangedStoreWithoutWaiting() async throws {
        let recent = Date().addingTimeInterval(-600)
        try writeConversation("c1", records: [
            record(responseID: "first", model: "gemini-3.6-flash", createdAt: recent,
                   input: 100, output: 20, cacheRead: 300),
        ])
        let cache = LocalAntigravityUsageCache(root: temporaryDirectory)
        let before = await cache.entries()
        XCTAssertEqual(Set(before.map(\.id)), ["antigravity|first"])

        try appendRecords("c1", records: [
            record(responseID: "second", model: "gemini-3.6-flash", createdAt: recent.addingTimeInterval(1),
                   input: 100, output: 20, cacheRead: 300),
        ], startingAt: 1)

        let after = await cache.entries()
        XCTAssertEqual(Set(after.map(\.id)), ["antigravity|first", "antigravity|second"])
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

    // MARK: - Provider

    /// Registered in its own right, so someone who runs only Antigravity sees their own tab
    /// rather than their spend labelled "Gemini". The two share `~/.gemini/` and nothing else.
    @MainActor
    func testDefaultRegistryIncludesAntigravity() {
        let suite = "AntigravityUsageTests.registry.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UsageStore(autoRefresh: false, defaults: defaults)
        XCTAssertTrue(store.registeredProviderIDs.contains("antigravity"))
    }

    /// The wire schema carries no amount and the rate lookup is short-circuited by the prefix,
    /// so there is no cost to contribute. Reporting one would print `$0.00` next to the tokens
    /// of a subscription that never billed per token — the same reason Cursor reports none.
    func testProviderReportsTokensOnly() {
        XCTAssertFalse(LocalAntigravityProvider().reportsCost)
    }

    /// Someone who has never run Antigravity must get silence rather than a zero: throwing
    /// colours the whole refresh as an error, and a zero raises a tab for a tool they don't use.
    func testProviderIsSilentWithoutAnyConversationStore() async throws {
        guard !FileManager.default.fileExists(atPath: LocalAntigravityUsageReader.defaultRoot.path) else {
            throw XCTSkip("this machine has Antigravity conversation stores — the absent path cannot be exercised")
        }
        let daily = try await LocalAntigravityProvider().fetchDaily()
        XCTAssertNil(daily)
    }

    // MARK: - Fixtures

    private func readAll() -> [LocalUsageReader.Entry] {
        LocalAntigravityUsageReader.entries(modifiedSince: .distantPast, root: temporaryDirectory)
    }

    private func readConversation(_ name: String) -> LocalAntigravityUsageReader.ConversationRead {
        LocalAntigravityUsageReader.conversationEntries(
            temporaryDirectory.appendingPathComponent("\(name).db"),
            formatter: LocalUsageReader.localDayFormatter())
    }

    private func scan(known: [String: LocalAntigravityUsageReader.Blob] = [:],
                      modifiedSince: Date = .distantPast) -> LocalAntigravityUsageReader.Scan {
        LocalAntigravityUsageReader.scan(
            root: temporaryDirectory, modifiedSince: modifiedSince, known: known)
    }

    /// A blob that does not match the file it is filed under, so a test can tell a cache hit
    /// (the planted rows come back) from a re-read (the file's own rows do).
    private func plantedBlob(for database: URL, id: String = "planted") throws
    -> LocalAntigravityUsageReader.Blob {
        let signature = try XCTUnwrap(LocalAntigravityUsageReader.signature(of: database))
        return LocalAntigravityUsageReader.Blob(
            mtime: signature.mtime, size: signature.size,
            entries: [LocalUsageReader.Entry(
                id: id, date: try date("2026-03-04T10:00:00Z"), localDay: "2026-03-04",
                model: "antigravity/planted", input: 1, output: 0, cacheWrite: 0, cacheRead: 0)])
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

    /// Minimal current-format record: the generation blob keeps usage/identity but no longer
    /// carries `chat_start_metadata.created_at`.
    private func currentFormatRecord(
        responseID: String,
        executionID: String,
        createdAt: Date,
        input: UInt64,
        output: UInt64,
        cacheRead: UInt64
    ) -> Data {
        var usage = AntigravityProto.encodeVarint(field: 2, input)
        usage += AntigravityProto.encodeVarint(field: 3, output)
        usage += AntigravityProto.encodeVarint(field: 5, cacheRead)
        usage += AntigravityProto.encodeString(field: 11, responseID)

        // `chat_start_metadata` now contains other metadata at field 10, but not field 4
        // (`created_at`). It is included only to keep the fixture on the new wire shape.
        var start = AntigravityProto.encodeVarint(field: 2, 1)
        start += AntigravityProto.encodeMessage(
            field: 10,
            AntigravityProto.encodeVarint(field: 1, 1)
                + AntigravityProto.encodeVarint(field: 4, 256_000))

        var chatModel = AntigravityProto.encodeMessage(field: 4, usage)
        chatModel += AntigravityProto.encodeMessage(field: 9, start)
        chatModel += AntigravityProto.encodeString(field: 19, "gemini-3.6-flash")
        var metadata = AntigravityProto.encodeMessage(field: 1, chatModel)
        // Observed current writer shape: gen_metadata.data field 4 is the execution_id.
        metadata += AntigravityProto.encodeString(field: 4, executionID)
        return Data(metadata)
    }

    /// Minimal `steps.metadata` record used by the current writer. Field 12 repeats the
    /// execution_id group key; field 9 → field 11 carries the per-generation response id used
    /// to correlate the timestamp with a generation metadata row.
    private func stepMetadata(responseID: String, executionID: String, createdAt: Date) -> Data {
        let timestamp = AntigravityProto.encodeVarint(
            field: 1, UInt64(createdAt.timeIntervalSince1970))
        var metadata = AntigravityProto.encodeMessage(field: 1, timestamp)
        metadata += AntigravityProto.encodeMessage(
            field: 9, AntigravityProto.encodeString(field: 11, responseID))
        metadata += AntigravityProto.encodeString(field: 12, executionID)
        return Data(metadata)
    }

    private func writeConversation(_ name: String, records: [Data], walMode: Bool = false,
                                   stepMetadata: [Data] = []) throws {
        try writeConversation(name, blobs: records, walMode: walMode, stepMetadata: stepMetadata)
    }

    /// A store spanning several pages, so damaging the last one still leaves earlier rows
    /// readable — which is the shape a scan that stops half way actually has.
    private func writeManyRecords(_ name: String, count: Int, pageSize: Int) throws {
        let base = UInt64(try date("2026-03-04T10:00:00Z").timeIntervalSince1970)
        try writeConversation(name, blobs: (0..<count).map { index in
            makeRecord(responseID: "r\(index)", model: "gemini-3.6-flash",
                       createdAtSeconds: base + UInt64(index),
                       input: 100, output: 20, cacheRead: 300)
        }, pageSize: pageSize)
    }

    /// Appends to a store that already exists, the way the CLI does — the `.db` grows and its
    /// timestamp moves, which is what the signature has to notice.
    private func appendRecords(_ name: String, records: [Data], startingAt index: Int) throws {
        var sql = ""
        for (offset, blob) in records.enumerated() {
            sql += "INSERT INTO gen_metadata VALUES (\(index + offset),"
                + " X'\(blob.map { String(format: "%02x", $0) }.joined())', \(blob.count));\n"
        }
        try execute(temporaryDirectory.appendingPathComponent("\(name).db"), sql: sql)
    }

    /// Damages the b-tree page-type byte of the last page. Page 1 — the schema — is untouched on
    /// purpose, so `openReadOnly`'s probe still succeeds and the connection it returns is the
    /// `mode=ro` one; corrupting the header instead would fail the open and cover a different
    /// branch entirely.
    private func corruptLastPage(_ database: URL, pageSize: Int) throws {
        let size = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: database.path)[.size] as? Int)
        XCTAssertGreaterThan(size / pageSize, 2, "the fixture needs more than two pages to damage the last one")
        let handle = try FileHandle(forUpdating: database)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64((size / pageSize - 1) * pageSize))
        handle.write(Data([0x00]))   // not a valid b-tree page type
    }

    /// Walks the reader's own query so a test can assert that rows really do arrive before the
    /// failure — i.e. that it is exercising the partial-scan branch and not a failed open.
    private func stepUntilNotARow(_ database: URL) throws -> (rows: Int, status: Int32) {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI | SQLITE_OPEN_NOMUTEX
        XCTAssertEqual(sqlite3_open_v2("file:\(database.path)?mode=ro", &handle, flags, nil), SQLITE_OK)
        defer { sqlite3_close_v2(handle) }
        var statement: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(
            handle, "SELECT idx, data FROM gen_metadata WHERE data IS NOT NULL",
            -1, &statement, nil), SQLITE_OK)
        defer { sqlite3_finalize(statement) }
        var rows = 0
        while true {
            let step = sqlite3_step(statement)
            guard step == SQLITE_ROW else { return (rows, step) }
            rows += 1
        }
    }

    private func writeConversation(_ name: String, blobs: [Data], walMode: Bool = false,
                                   pageSize: Int? = nil, stepMetadata: [Data] = []) throws {
        let database = temporaryDirectory.appendingPathComponent("\(name).db")
        // `page_size` only takes effect before the first table exists.
        var sql = pageSize.map { "PRAGMA page_size=\($0);\n" } ?? ""
        sql += walMode ? "PRAGMA journal_mode=WAL;\n" : ""
        sql += "CREATE TABLE gen_metadata (idx integer, data blob, size integer NOT NULL DEFAULT 0, PRIMARY KEY (idx));\n"
        for (index, blob) in blobs.enumerated() {
            sql += "INSERT INTO gen_metadata VALUES (\(index), X'\(blob.map { String(format: "%02x", $0) }.joined())', \(blob.count));\n"
        }
        if !stepMetadata.isEmpty {
            sql += "CREATE TABLE steps (idx integer, step_type integer NOT NULL DEFAULT 0, metadata blob, PRIMARY KEY (idx));\n"
            for (index, metadata) in stepMetadata.enumerated() {
                sql += "INSERT INTO steps VALUES (\(index), 15, X'\(metadata.map { String(format: "%02x", $0) }.joined())');\n"
            }
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
            if let handle { sqlite3_close_v2(handle) }
            return nil
        }
        // Opening can succeed lazily; the read is what actually needs the -shm file.
        var statement: OpaquePointer?
        let prepared = sqlite3_prepare_v2(handle, "SELECT count(*) FROM gen_metadata", -1, &statement, nil)
        let stepped = prepared == SQLITE_OK ? sqlite3_step(statement) : SQLITE_ERROR
        sqlite3_finalize(statement)
        guard stepped == SQLITE_ROW else {
            sqlite3_close_v2(handle)
            return nil
        }
        return handle
    }

    private func execute(_ databaseURL: URL, sql: String) throws {
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &database), SQLITE_OK)
        defer { sqlite3_close_v2(database) }
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
