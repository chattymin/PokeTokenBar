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

    // MARK: - Dating what Antigravity 2.0 leaves undated

    /// The store's mtime is one value for every record it holds, so a conversation that ran
    /// across midnight files yesterday's spend under today. The step that produced the record
    /// knows better, and it is in the same database.
    func testStepTimeWinsOverTheStoreMtime() throws {
        let yesterday = try date("2026-03-04T23:40:00Z")
        try writeConversation("c1", records: [
            undatedRecord(responseID: "r1", model: "gemini-3.7-flash", execution: "e1",
                          input: 100, output: 20, cacheRead: 300),
        ], steps: [makeStep(execution: "e1", queued: yesterday, finished: yesterday)])
        // The store was last written well after the turn it holds, which is the ordinary state
        // of a conversation somebody is still using.
        let database = temporaryDirectory.appendingPathComponent("c1.db")
        let touched = try date("2026-03-05T09:00:00Z")
        try FileManager.default.setAttributes([.modificationDate: touched], ofItemAtPath: database.path)

        let entry = try XCTUnwrap(readAll().first)
        XCTAssertEqual(entry.date.timeIntervalSince1970, yesterday.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(entry.localDay, LocalUsageReader.localDayFormatter().string(from: yesterday),
                       "the mtime would have moved this turn onto the following day")
    }

    /// `finished_at` is when the tokens were spent, so it is preferred over the moment the step
    /// was queued.
    func testRecordIsDatedFromTheFinishOfItsStep() throws {
        let queued = try date("2026-03-04T10:00:00Z")
        let finished = try date("2026-03-04T10:00:12Z")
        try writeConversation("c1", records: [
            undatedRecord(responseID: "r1", model: "gemini-3.7-flash", execution: "e1",
                          input: 100, output: 20, cacheRead: 300),
        ], steps: [makeStep(execution: "e1", queued: queued, finished: finished)])

        let entry = try XCTUnwrap(readAll().first)
        XCTAssertEqual(entry.date.timeIntervalSince1970, finished.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(entry.total, 420, "the counters are the writer's — only the date is inferred")
    }

    /// `gen_metadata.idx` is its own dense sequence and drifts from `steps.idx` by minutes inside
    /// one conversation, so the join has to be the execution id and nothing else.
    func testTheJoinIsTheExecutionIdAndNotTheRowIndex() throws {
        let first = try date("2026-03-04T10:00:00Z")
        let second = try date("2026-03-05T18:00:00Z")
        try writeConversation("c1", records: [
            undatedRecord(responseID: "r1", model: "gemini-3.7-flash", execution: "e2",
                          input: 100, output: 20, cacheRead: 300),
        ], steps: [
            makeStep(execution: "e1", queued: first, finished: first),
            makeStep(execution: "e2", queued: second, finished: second),
        ])

        let entry = try XCTUnwrap(readAll().first)
        XCTAssertEqual(entry.date.timeIntervalSince1970, second.timeIntervalSince1970, accuracy: 0.001,
                       "row 0 was dated from step 0 instead of from its own execution")
    }

    /// One execution answers several times. Pairing them in order follows the execution as it
    /// runs; collapsing them onto its last step would file a turn under the wrong day whenever
    /// an execution straddles midnight.
    func testStepTimesAreHandedOutInOrderWithinAnExecution() throws {
        let times = try [
            date("2026-03-04T23:50:00Z"), date("2026-03-04T23:55:00Z"), date("2026-03-05T00:05:00Z"),
        ]
        try writeConversation("c1", records: (0..<3).map {
            undatedRecord(responseID: "r\($0)", model: "gemini-3.7-flash", execution: "e1",
                          input: 100, output: 20, cacheRead: 300)
        }, steps: times.map { makeStep(execution: "e1", queued: $0, finished: $0) })

        let dates = readAll().sorted { $0.id < $1.id }.map(\.date.timeIntervalSince1970)
        XCTAssertEqual(dates, times.map(\.timeIntervalSince1970))
    }

    /// A step still running has no `finished_at`, and more records than steps is what a store
    /// read mid-execution looks like. The last known time still dates them.
    func testRecordsBeyondTheStepsFallBackToTheLastKnownTime() throws {
        let queued = try date("2026-03-04T10:00:00Z")
        try writeConversation("c1", records: (0..<2).map {
            undatedRecord(responseID: "r\($0)", model: "gemini-3.7-flash", execution: "e1",
                          input: 100, output: 20, cacheRead: 300)
        }, steps: [makeStep(execution: "e1", queued: queued, finished: nil)])

        let dates = readAll().map(\.date.timeIntervalSince1970)
        XCTAssertEqual(dates.count, 2)
        XCTAssertEqual(Set(dates), [queued.timeIntervalSince1970])
    }

    /// New Antigravity stores omit `chat_start_metadata.created_at` from the generation blob.
    /// The same response id and timestamp remain in the corresponding generation step metadata.
    func testCurrentGenerationFormatUsesStepMetadataTimestamp() throws {
        let firstID = "synthetic-new-format-call-1"
        let secondID = "synthetic-new-format-call-2"
        let firstDate = try date("2026-08-19T10:00:00Z")
        let secondDate = try date("2026-08-19T10:01:00Z")
        try writeConversation(
            "c1",
            records: [
                undatedRecord(responseID: firstID, model: "gemini-3.7-flash", execution: "e1",
                              input: 100, output: 20, cacheRead: 300),
                undatedRecord(responseID: secondID, model: "gemini-3.7-flash", execution: "e1",
                              input: 200, output: 30, cacheRead: 400),
            ],
            // Deliberately reverse the rows: correlation must use response_id, not table order.
            steps: [
                makeStep(execution: "e1", responseID: secondID, queued: secondDate, finished: secondDate),
                makeStep(execution: "e1", responseID: firstID, queued: firstDate, finished: firstDate),
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

    /// Multiple generations in the same conversation sharing an execution_id are correlated
    /// directly by response_id even across midnight.
    func testMultipleGenerationsSharingExecutionIdAreCorrelatedByResponseId() throws {
        let firstID = "synthetic-shared-exec-call-1"
        let secondID = "synthetic-shared-exec-call-2"
        let firstDate = try date("2026-08-18T10:00:00Z")
        let secondDate = try date("2026-08-19T10:00:00Z")
        let executionID = "shared-execution-uuid"
        try writeConversation(
            "c1",
            records: [
                undatedRecord(responseID: firstID, model: "gemini-3.7-flash", execution: executionID,
                              input: 100, output: 20, cacheRead: 300),
                undatedRecord(responseID: secondID, model: "gemini-3.7-flash", execution: executionID,
                              input: 200, output: 30, cacheRead: 400),
            ],
            steps: [
                makeStep(execution: executionID, responseID: secondID, queued: secondDate, finished: secondDate),
                makeStep(execution: executionID, responseID: firstID, queued: firstDate, finished: firstDate),
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

    /// The writer's own value where there is one — the step time is an inference, and an
    /// inference must never displace the thing it stands in for.
    func testWriterCreatedAtWinsOverTheStepTime() throws {
        let created = try date("2026-03-04T10:00:00Z")
        try writeConversation("c1", records: [
            makeRecord(responseID: "r1", model: "gemini-3.6-flash",
                       createdAtSeconds: UInt64(created.timeIntervalSince1970),
                       input: 100, output: 20, cacheRead: 300, execution: "e1"),
        ], steps: [makeStep(execution: "e1",
                            queued: try date("2026-03-09T10:00:00Z"),
                            finished: try date("2026-03-09T10:00:01Z"))])

        let entry = try XCTUnwrap(readAll().first)
        XCTAssertEqual(entry.date.timeIntervalSince1970, created.timeIntervalSince1970, accuracy: 0.001)
    }

    /// The store's mtime stays as the last resort: a record whose execution has no steps to date
    /// it with must still be counted rather than dropped.
    func testStoreMtimeRemainsTheLastResort() throws {
        try writeConversation("c1", records: [
            undatedRecord(responseID: "r1", model: "gemini-3.7-flash", execution: "e1",
                          input: 100, output: 20, cacheRead: 300),
        ], steps: [makeStep(execution: "another-execution",
                            queued: try date("2026-03-01T10:00:00Z"), finished: nil)])
        let database = temporaryDirectory.appendingPathComponent("c1.db")
        let touched = try date("2026-03-05T09:00:00Z")
        try FileManager.default.setAttributes([.modificationDate: touched], ofItemAtPath: database.path)

        let entry = try XCTUnwrap(readAll().first)
        XCTAssertEqual(entry.date.timeIntervalSince1970, touched.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(entry.total, 420)
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
        let hasAnyStore = LocalAntigravityUsageReader.defaultRoots.contains {
            FileManager.default.fileExists(atPath: $0.path)
        }
        guard !hasAnyStore else {
            throw XCTSkip("this machine has Antigravity conversation stores — the absent path cannot be exercised")
        }
        let daily = try await LocalAntigravityProvider().fetchDaily()
        XCTAssertNil(daily)
    }

    func testDefaultRootsContainsAllKnownLocations() {
        let paths = LocalAntigravityUsageReader.defaultRoots.map(\.path)
        XCTAssertTrue(paths.contains { $0.hasSuffix(".gemini/antigravity/conversations") })
        XCTAssertTrue(paths.contains { $0.hasSuffix(".gemini/antigravity-cli/conversations") })
        XCTAssertTrue(paths.contains { $0.hasSuffix(".gemini/antigravity-ide/conversations") })
        XCTAssertEqual(LocalAntigravityUsageReader.defaultRoot, LocalAntigravityUsageReader.defaultRoots[0])
    }

    func testMultiRootScanDiscoversAndDeduplicatesAcrossDirectories() throws {
        let rootA = temporaryDirectory.appendingPathComponent("rootA")
        let rootB = temporaryDirectory.appendingPathComponent("rootB")
        try FileManager.default.createDirectory(at: rootA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: rootB, withIntermediateDirectories: true)

        let stamp = try date("2026-03-04T10:00:00Z")

        // rootA has unique entry r1, and duplicate r_shared
        try writeConversation("c1", at: rootA, records: [
            record(responseID: "r1", model: "gemini-3.6-flash", createdAt: stamp, input: 100, output: 50, cacheRead: 0),
            record(responseID: "r_shared", model: "gemini-3.6-flash", createdAt: stamp, input: 200, output: 100, cacheRead: 0),
        ])

        // rootB has unique entry r2, and duplicate r_shared
        try writeConversation("c2", at: rootB, records: [
            record(responseID: "r2", model: "gemini-3.6-flash", createdAt: stamp, input: 300, output: 150, cacheRead: 0),
            record(responseID: "r_shared", model: "gemini-3.6-flash", createdAt: stamp, input: 200, output: 100, cacheRead: 0),
        ])

        let entries = LocalAntigravityUsageReader.entries(modifiedSince: .distantPast, roots: [rootA, rootB])
        let ids = Set(entries.map(\.id))
        XCTAssertEqual(ids, ["antigravity|r1", "antigravity|r2", "antigravity|r_shared"])
        XCTAssertEqual(entries.count, 3, "duplicate r_shared must collapse to a single entry")
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

    /// Antigravity 2.0 / IDE sessions may omit `chat_start_metadata.created_at` from the protobuf.
    /// The reader should fallback to the database file's mtime so tokens are not dropped.
    func testConversationWithoutProtobufCreatedAtUsesFileMtimeFallback() throws {
        let recordWithoutTimestamp = makeRecord(
            responseID: "r_modern_1",
            model: "gemini-3.7-flash",
            createdAtSeconds: nil,
            input: 500,
            output: 100,
            cacheRead: 2000
        )
        try writeConversation("c_modern", records: [recordWithoutTimestamp])

        let entries = readAll()
        XCTAssertEqual(entries.count, 1)
        let entry = try XCTUnwrap(entries.first)
        XCTAssertEqual(entry.id, "antigravity|r_modern_1")
        XCTAssertEqual(entry.input, 500)
        XCTAssertEqual(entry.output, 100)
        XCTAssertEqual(entry.cacheRead, 2000)
        XCTAssertEqual(entry.total, 2600)
        XCTAssertEqual(entry.model, "antigravity/gemini-3.7-flash")
    }

    /// `CortexStepGeneratorMetadata { 1 chat_model { 4 usage, 9 chat_start_metadata, 19 response_model } }`
    /// An Antigravity 2.0 record: it names the execution it belongs to and carries no time.
    private func undatedRecord(
        responseID: String?,
        model: String,
        execution: String?,
        input: UInt64,
        output: UInt64,
        cacheRead: UInt64
    ) -> Data {
        makeRecord(responseID: responseID, model: model, createdAtSeconds: nil,
                   input: input, output: output, cacheRead: cacheRead, execution: execution)
    }

    /// `StepMetadata { 1 created_at, 8 finished_at, 9 { 11 response_id }, 12 execution_id }`
    private func makeStep(execution: String? = nil, responseID: String? = nil, queued: Date, finished: Date?) -> Data {
        func stamp(_ field: Int, _ date: Date) -> [UInt8] {
            AntigravityProto.encodeMessage(
                field: field,
                AntigravityProto.encodeVarint(field: 1, UInt64(date.timeIntervalSince1970)))
        }
        var metadata = stamp(1, queued)
        if let finished { metadata += stamp(8, finished) }
        if let responseID {
            metadata += AntigravityProto.encodeMessage(
                field: 9, AntigravityProto.encodeString(field: 11, responseID))
        }
        if let execution {
            metadata += AntigravityProto.encodeString(field: 12, execution)
        }
        return Data(metadata)
    }

    private func makeRecord(
        responseID: String?,
        model: String,
        createdAtSeconds: UInt64? = nil,
        input: UInt64,
        output: UInt64,
        cacheRead: UInt64,
        thinking: UInt64? = nil,
        response: UInt64? = nil,
        execution: String? = nil
    ) -> Data {
        var usage = AntigravityProto.encodeVarint(field: 1, 1071)          // model enum
        usage += AntigravityProto.encodeVarint(field: 2, input)            // input_tokens
        usage += AntigravityProto.encodeVarint(field: 3, output)           // output_tokens
        usage += AntigravityProto.encodeVarint(field: 5, cacheRead)        // cache_read_tokens
        usage += AntigravityProto.encodeVarint(field: 6, 24)               // api_provider
        if let thinking { usage += AntigravityProto.encodeVarint(field: 9, thinking) }
        if let response { usage += AntigravityProto.encodeVarint(field: 10, response) }
        if let responseID { usage += AntigravityProto.encodeString(field: 11, responseID) }

        var chatModel = AntigravityProto.encodeVarint(field: 3, 1071)
        chatModel += AntigravityProto.encodeMessage(field: 4, usage)
        // Antigravity 2.0 still writes `chat_start_metadata`; it is `created_at` inside it that
        // is gone. Dropping the whole message instead would let a future writer that puts
        // something else at field 4 pass these tests unnoticed.
        let chatStart = createdAtSeconds.map {
            AntigravityProto.encodeMessage(field: 4, AntigravityProto.encodeVarint(field: 1, $0))
        } ?? AntigravityProto.encodeVarint(field: 2, UInt64.max)
        chatModel += AntigravityProto.encodeMessage(field: 9, chatStart)
        chatModel += AntigravityProto.encodeString(field: 19, model)

        var record = AntigravityProto.encodeMessage(field: 1, chatModel)
        if let execution { record += AntigravityProto.encodeString(field: 4, execution) }
        return Data(record)
    }

    private func writeConversation(_ name: String, at root: URL? = nil, records: [Data],
                                   steps: [Data] = [], walMode: Bool = false) throws {
        try writeConversation(name, at: root, blobs: records, steps: steps, walMode: walMode)
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
            handle, "SELECT idx, data FROM gen_metadata WHERE data IS NOT NULL ORDER BY idx",
            -1, &statement, nil), SQLITE_OK)
        defer { sqlite3_finalize(statement) }
        var rows = 0
        while true {
            let step = sqlite3_step(statement)
            guard step == SQLITE_ROW else { return (rows, step) }
            rows += 1
        }
    }

    private func writeConversation(_ name: String, at root: URL? = nil, blobs: [Data],
                                   steps: [Data] = [], walMode: Bool = false,
                                   pageSize: Int? = nil) throws {
        let directory = root ?? temporaryDirectory!
        let database = directory.appendingPathComponent("\(name).db")
        // `page_size` only takes effect before the first table exists.
        var sql = pageSize.map { "PRAGMA page_size=\($0);\n" } ?? ""
        sql += walMode ? "PRAGMA journal_mode=WAL;\n" : ""
        sql += "CREATE TABLE gen_metadata (idx integer, data blob, size integer NOT NULL DEFAULT 0, PRIMARY KEY (idx));\n"
        for (index, blob) in blobs.enumerated() {
            sql += "INSERT INTO gen_metadata VALUES (\(index), X'\(blob.map { String(format: "%02x", $0) }.joined())', \(blob.count));\n"
        }
        if !steps.isEmpty {
            sql += "CREATE TABLE steps (idx integer, metadata blob, PRIMARY KEY (idx));\n"
            for (index, blob) in steps.enumerated() {
                sql += "INSERT INTO steps VALUES (\(index), X'\(blob.map { String(format: "%02x", $0) }.joined())');\n"
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
