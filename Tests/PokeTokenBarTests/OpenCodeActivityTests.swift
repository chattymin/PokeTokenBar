import SQLite3
import XCTest
@testable import PokeTokenBar

/// A SQLite file held open by a writer, as the agent holds its database while it runs.
/// Synthetic data only; these tests never read an installed agent's database.
final class AgentDatabaseFixture {
    let url: URL
    private var handle: OpaquePointer?

    init(_ url: URL, schema: String) throws {
        self.url = url
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard sqlite3_open(url.path, &handle) == SQLITE_OK else { throw NSError(domain: "SQLite", code: 1) }
        try exec("PRAGMA journal_mode = WAL;" + schema)
    }

    deinit { sqlite3_close(handle) }

    func exec(_ sql: String, file: StaticString = #filePath, line: UInt = #line) throws {
        var error: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(handle, sql, nil, nil, &error)
        let message = error.map { String(cString: $0) }
        sqlite3_free(error)
        XCTAssertEqual(result, SQLITE_OK, message ?? "SQLite statement failed", file: file, line: line)
        if result != SQLITE_OK { throw NSError(domain: "SQLite", code: Int(result)) }
    }

    /// `'…'` with quotes doubled.
    static func quoted(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "''") + "'" }
}

final class OpenCodeActivityTests: XCTestCase {
    private var directory: URL!
    private var now = Date()
    private var ms: Int64 { Int64(now.timeIntervalSince1970 * 1000) }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("OpenCodeActivityTests-\(UUID())")
        now = Date()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: 1.x (`packages/core/src/session/sql.ts` at v1.19.5)

    private func v1() throws -> AgentDatabaseFixture {
        try AgentDatabaseFixture(directory.appendingPathComponent("opencode.db"), schema: """
            CREATE TABLE session (id TEXT PRIMARY KEY, project_id TEXT NOT NULL, parent_id TEXT, slug TEXT NOT NULL,
                directory TEXT NOT NULL, title TEXT NOT NULL, version TEXT NOT NULL,
                time_created INTEGER NOT NULL, time_updated INTEGER NOT NULL);
            CREATE INDEX session_parent_idx ON session (parent_id);
            CREATE TABLE message (id TEXT PRIMARY KEY, session_id TEXT NOT NULL,
                time_created INTEGER NOT NULL, time_updated INTEGER NOT NULL, data TEXT NOT NULL);
            CREATE INDEX message_session_time_created_id_idx ON message (session_id, time_created, id);
            CREATE TABLE part (id TEXT PRIMARY KEY, message_id TEXT NOT NULL, session_id TEXT NOT NULL,
                time_created INTEGER NOT NULL, time_updated INTEGER NOT NULL, data TEXT NOT NULL);
            CREATE INDEX part_message_id_id_idx ON part (message_id, id);
            CREATE INDEX part_session_idx ON part (session_id);
            """)
    }

    private func session(_ db: AgentDatabaseFixture, _ id: String, parent: String? = nil,
                         directory: String = "/Users/me/code/web-app", title: String = "Fix the login bug") throws {
        try db.exec("""
            INSERT INTO session VALUES ('\(id)', 'p', \(parent.map { "'\($0)'" } ?? "NULL"), 'slug',
                \(AgentDatabaseFixture.quoted(directory)), \(AgentDatabaseFixture.quoted(title)), '1.19.5', \(ms), \(ms));
            """)
    }

    private func message(_ db: AgentDatabaseFixture, _ id: String, session: String, at time: Int64? = nil, _ data: String) throws {
        let time = time ?? ms
        try db.exec("""
            INSERT INTO message VALUES ('\(id)', '\(session)', \(time), \(time), \(AgentDatabaseFixture.quoted(data)))
            ON CONFLICT(id) DO UPDATE SET data = excluded.data, time_updated = excluded.time_updated;
            """)
    }

    private func part(_ db: AgentDatabaseFixture, _ id: String, message: String, session: String, _ data: String) throws {
        try db.exec("""
            INSERT INTO part VALUES ('\(id)', '\(message)', '\(session)', \(ms), \(ms), \(AgentDatabaseFixture.quoted(data)))
            ON CONFLICT(id) DO UPDATE SET data = excluded.data;
            """)
    }

    private static let user = #"{"role":"user","time":{"created":1}}"#
    private static let streaming = #"{"role":"assistant","time":{"created":1},"parentID":"msg_1"}"#
    private static let stopped = #"{"role":"assistant","time":{"created":1,"completed":2},"finish":"stop","parentID":"msg_1"}"#
    private static let toolStep = #"{"role":"assistant","time":{"created":1,"completed":2},"finish":"tool-calls"}"#

    private func read(_ db: AgentDatabaseFixture, _ watermark: String?, at date: Date? = nil) -> (readings: [AgentLogReading], watermark: String?) {
        OpenCodeActivity.read(db.url, watermark: watermark, now: date ?? now)
    }

    func testFirstLookReportsOnlySessionsThatMovedInTheLastMinute() throws {
        let db = try v1()
        try session(db, "ses_old", directory: "/Users/me/code/old")
        try session(db, "ses_new")
        try message(db, "msg_0", session: "ses_old", at: ms - 3_600_000, Self.user)
        try message(db, "msg_1", session: "ses_new", Self.user)

        let first = read(db, nil)
        XCTAssertEqual(first.readings, [AgentLogReading(activity: .working, label: "web-app", title: "Fix the login bug",
                                                        session: "ses_new")])
        XCTAssertNotNil(first.watermark)
        XCTAssertEqual(read(db, first.watermark).readings, [], "nothing new since the watermark")
    }

    func testTurnGoesFromWorkingToDoneAndTheWatermarkAdvances() throws {
        let db = try v1()
        try session(db, "ses_a")
        var mark = read(db, nil).watermark
        try message(db, "msg_1", session: "ses_a", Self.user)
        var result = read(db, mark)
        XCTAssertEqual(result.readings.map(\.activity), [.working])
        mark = result.watermark

        // A tool step: completed, but `tool-calls` means another step follows.
        try message(db, "msg_2", session: "ses_a", Self.toolStep)
        try part(db, "prt_1", message: "msg_2", session: "ses_a",
                 #"{"type":"tool","tool":"bash","callID":"c1","state":{"status":"completed"}}"#)
        result = read(db, mark)
        XCTAssertEqual(result.readings.map(\.activity), [.working])
        mark = result.watermark

        // The final step is inserted while streaming, then completed in place (no new row).
        try message(db, "msg_3", session: "ses_a", Self.streaming)
        result = read(db, mark)
        XCTAssertEqual(result.readings.map(\.activity), [.working])
        mark = result.watermark
        try message(db, "msg_3", session: "ses_a", Self.stopped)
        result = read(db, mark)
        XCTAssertEqual(result.readings.map(\.activity), [.done(message: nil)], "the open session is rechecked")
        XCTAssertEqual(result.readings.first?.lineID, "msg_3")
        mark = result.watermark
        XCTAssertEqual(read(db, mark).readings, [], "a done session is not rechecked again")
    }

    func testStopWithAToolPartOrACompactionSummaryIsNotDone() throws {
        let db = try v1()
        try session(db, "ses_a")
        let mark = read(db, nil).watermark
        try message(db, "msg_1", session: "ses_a", Self.stopped)
        // Some providers say `stop` with tool calls; OpenCode then runs another step.
        try part(db, "prt_1", message: "msg_1", session: "ses_a",
                 #"{"type":"tool","tool":"read","callID":"c1","state":{"status":"completed"}}"#)
        XCTAssertEqual(read(db, mark).readings.map(\.activity), [.working])

        try part(db, "prt_1", message: "msg_1", session: "ses_a",
                 #"{"type":"tool","tool":"websearch","metadata":{"providerExecuted":true},"state":{"status":"completed"}}"#)
        XCTAssertEqual(read(db, mark).readings.map(\.activity), [.done(message: nil)], "a provider-run tool needs no step")

        try message(db, "msg_2", session: "ses_a",
                    #"{"role":"assistant","summary":true,"time":{"created":1,"completed":2},"finish":"stop"}"#)
        XCTAssertEqual(read(db, mark).readings.map(\.activity), [.working], "a compaction summary continues the turn")
    }

    func testRunningQuestionIsWaitingUntilAnswered() throws {
        let db = try v1()
        try session(db, "ses_a")
        var mark = read(db, nil).watermark
        try message(db, "msg_1", session: "ses_a", Self.streaming)
        try part(db, "prt_q", message: "msg_1", session: "ses_a",
                 #"{"type":"tool","tool":"question","callID":"c1","state":{"status":"running","input":{}}}"#)
        var result = read(db, mark)
        XCTAssertEqual(result.readings.map(\.activity), [.waiting(message: nil)])
        XCTAssertEqual(result.readings.first?.lineID, "prt_q")
        mark = result.watermark

        try part(db, "prt_q", message: "msg_1", session: "ses_a",
                 #"{"type":"tool","tool":"question","callID":"c1","state":{"status":"completed"}}"#)
        result = read(db, mark)
        XCTAssertEqual(result.readings.map(\.activity), [.working], "the answer is seen without a new row")
    }

    func testErrorsEndTheTurnAsIdle() throws {
        let db = try v1()
        try session(db, "ses_a")
        let mark = read(db, nil).watermark
        try message(db, "msg_1", session: "ses_a", """
            {"role":"assistant","time":{"created":1,"completed":2},"error":{"name":"MessageAbortedError","data":{"message":"Aborted"}}}
            """)
        XCTAssertEqual(read(db, mark).readings.map(\.activity), [.idle])
    }

    func testChildSessionsAreSkippedAndDefaultTitlesDropped() throws {
        let db = try v1()
        try session(db, "ses_main", title: "New session - 2026-11-06T01:02:03.456Z")
        try session(db, "ses_child", parent: "ses_main", title: "Explore the code (@explore subagent)")
        let mark = read(db, nil).watermark
        try message(db, "msg_1", session: "ses_child", Self.stopped)
        try message(db, "msg_2", session: "ses_main", Self.user)
        let readings = read(db, mark).readings
        XCTAssertEqual(readings.map(\.session), ["ses_main"], "a subagent's turns are not the person's")
        XCTAssertNil(readings.first?.title)
    }

    func testRecreatedDatabaseIsReadLikeAFirstLook() throws {
        let db = try v1()
        try session(db, "ses_a")
        try session(db, "ses_old")
        for index in 0..<5 { try message(db, "msg_\(index)", session: "ses_a", at: ms - 3_600_000, Self.user) }
        let mark = read(db, nil).watermark
        try db.exec("DELETE FROM message;")
        // Row ids restart below the watermark: only a first look's recent rows count.
        try message(db, "msg_old", session: "ses_old", at: ms - 3_600_000, Self.user)
        try message(db, "msg_new", session: "ses_a", Self.user)
        XCTAssertEqual(read(db, mark).readings.map(\.session), ["ses_a"])
    }

    // MARK: 2.x (`packages/core/src/session/sql.ts` at v2.2.5)

    private func v2() throws -> AgentDatabaseFixture {
        try AgentDatabaseFixture(directory.appendingPathComponent("opencode.db"), schema: """
            CREATE TABLE session (id TEXT PRIMARY KEY, parent_id TEXT, directory TEXT NOT NULL, title TEXT NOT NULL);
            CREATE TABLE message (id TEXT PRIMARY KEY, session_id TEXT NOT NULL, time_created INTEGER NOT NULL,
                time_updated INTEGER NOT NULL, data TEXT NOT NULL);
            CREATE TABLE part (id TEXT PRIMARY KEY, message_id TEXT NOT NULL, session_id TEXT NOT NULL,
                time_created INTEGER NOT NULL, time_updated INTEGER NOT NULL, data TEXT NOT NULL);
            CREATE TABLE session_v2 (id TEXT PRIMARY KEY, project_id TEXT NOT NULL, parent_id TEXT, slug TEXT NOT NULL,
                directory TEXT NOT NULL, title TEXT, version TEXT NOT NULL, time_created INTEGER NOT NULL,
                time_updated INTEGER NOT NULL, time_busy INTEGER, time_idle INTEGER, idle_outcome TEXT);
            CREATE TABLE session_message (id TEXT PRIMARY KEY, session_id TEXT NOT NULL, type TEXT NOT NULL,
                seq INTEGER NOT NULL, time_created INTEGER NOT NULL, time_updated INTEGER NOT NULL, data TEXT NOT NULL);
            CREATE UNIQUE INDEX session_message_session_seq_idx ON session_message (session_id, seq);
            CREATE INDEX session_message_session_type_seq_idx ON session_message (session_id, type, seq);
            CREATE TABLE session_part (message_id TEXT NOT NULL, session_id TEXT NOT NULL, ordinal INTEGER NOT NULL,
                type TEXT NOT NULL, call_id TEXT, time_created INTEGER NOT NULL, time_updated INTEGER NOT NULL,
                data TEXT NOT NULL, PRIMARY KEY (message_id, ordinal));
            """)
    }

    private func sessionV2(_ db: AgentDatabaseFixture, _ id: String, parent: String? = nil, title: String? = "Ship the API") throws {
        try db.exec("""
            INSERT INTO session_v2 VALUES ('\(id)', 'p', \(parent.map { "'\($0)'" } ?? "NULL"), 'slug',
                '/Users/me/code/api', \(title.map(AgentDatabaseFixture.quoted) ?? "NULL"), '2.2.5', \(ms), \(ms), NULL, NULL, NULL);
            """)
    }

    private var seq = 0
    private func row(_ db: AgentDatabaseFixture, _ id: String, session: String, type: String, _ data: String) throws {
        seq += 1
        try db.exec("""
            INSERT INTO session_message VALUES ('\(id)', '\(session)', '\(type)', \(seq), \(ms), \(ms), \(AgentDatabaseFixture.quoted(data)));
            """)
    }

    private static func assistant(question status: String?) -> String {
        let tool = status.map {
            #",{"type":"tool","id":"call_q","name":"question","state":{"status":"\#($0)","input":{},"metadata":{}},"time":{"created":1}}"#
        } ?? ""
        return #"{"agent":"build","model":{"id":"m","providerID":"p"},"content":[{"type":"text","text":"Hi"}\#(tool)],"time":{"created":1}}"#
    }

    func testV2ExecutionFromPromptToIdleRow() throws {
        let db = try v2()
        try sessionV2(db, "ses_b")
        var mark = read(db, nil).watermark
        try db.exec("UPDATE session_v2 SET time_busy = \(ms) WHERE id = 'ses_b';")
        try row(db, "msg_u", session: "ses_b", type: "user", #"{"text":"Add rate limits","time":{"created":1}}"#)
        var result = read(db, mark)
        XCTAssertEqual(result.readings, [AgentLogReading(activity: .working, label: "api", title: "Ship the API", session: "ses_b")])
        mark = result.watermark

        try row(db, "msg_a", session: "ses_b", type: "assistant", Self.assistant(question: nil))
        XCTAssertEqual(read(db, mark).readings.map(\.activity), [.working])

        try db.exec("UPDATE session_message SET data = \(AgentDatabaseFixture.quoted(Self.assistant(question: "running"))) WHERE id = 'msg_a';")
        result = read(db, mark)
        XCTAssertEqual(result.readings.map(\.activity), [.waiting(message: nil)])
        XCTAssertEqual(result.readings.first?.lineID, "call_q")
        mark = result.watermark

        try db.exec("UPDATE session_message SET data = \(AgentDatabaseFixture.quoted(Self.assistant(question: "completed"))) WHERE id = 'msg_a';")
        result = read(db, mark)
        XCTAssertEqual(result.readings.map(\.activity), [.working], "answering is seen on the open session")
        mark = result.watermark

        try db.exec("UPDATE session_v2 SET time_idle = \(ms + 5), idle_outcome = 'succeeded' WHERE id = 'ses_b';")
        try row(db, "msg_idle", session: "ses_b", type: "idle", #"{"outcome":"succeeded","time":{"created":1}}"#)
        result = read(db, mark)
        XCTAssertEqual(result.readings.map(\.activity), [.done(message: nil)])
        XCTAssertEqual(result.readings.first?.lineID, "msg_idle")
        mark = result.watermark

        // Switching the model while idle adds a row but no turn.
        try row(db, "msg_model", session: "ses_b", type: "model-switched", #"{"time":{"created":1}}"#)
        XCTAssertEqual(read(db, mark).readings.map(\.lineID), ["msg_idle"], "the same done, which the emitter drops")
    }

    func testV2DoneIsHeldBackWhileANewExecutionStarted() throws {
        let db = try v2()
        try sessionV2(db, "ses_b")
        let mark = read(db, nil).watermark
        try db.exec("UPDATE session_v2 SET time_busy = \(ms + 10), time_idle = \(ms), idle_outcome = 'succeeded' WHERE id = 'ses_b';")
        try row(db, "msg_idle", session: "ses_b", type: "idle", #"{"outcome":"succeeded"}"#)
        XCTAssertEqual(read(db, mark).readings.map(\.activity), [.working])
    }

    func testV2InterruptedIsIdleAndChildrenAreSkipped() throws {
        let db = try v2()
        try sessionV2(db, "ses_b", title: nil)
        try sessionV2(db, "ses_c", parent: "ses_b")
        let mark = read(db, nil).watermark
        try row(db, "msg_c", session: "ses_c", type: "idle", #"{"outcome":"succeeded"}"#)
        try row(db, "msg_i", session: "ses_b", type: "idle", #"{"outcome":"interrupted"}"#)
        let readings = read(db, mark).readings
        XCTAssertEqual(readings.map(\.session), ["ses_b"])
        XCTAssertEqual(readings.map(\.activity), [.idle])
        XCTAssertNil(readings.first?.title, "no title until OpenCode writes one")
    }

    func testV2QuestionInSessionPartRows() throws {
        let db = try v2()
        try sessionV2(db, "ses_b")
        let mark = read(db, nil).watermark
        try row(db, "msg_a", session: "ses_b", type: "assistant", #"{"content":[],"time":{"created":1}}"#)
        try db.exec("""
            INSERT INTO session_part VALUES ('msg_a', 'ses_b', 0, 'tool', 'call_p', \(ms), \(ms),
                '{"type":"tool","id":"call_p","name":"question","state":{"status":"running"}}');
            """)
        let reading = try XCTUnwrap(read(db, mark).readings.first)
        XCTAssertEqual(reading.activity, .waiting(message: nil))
        XCTAssertEqual(reading.lineID, "call_p")
    }

    func testDatabaseNamesAndSidecars() {
        let root = URL(fileURLWithPath: "/Users/me/.local/share/opencode")
        let db = root.appendingPathComponent("opencode.db")
        XCTAssertEqual(OpenCodeActivity.database(db), db)
        XCTAssertEqual(OpenCodeActivity.database(root.appendingPathComponent("opencode.db-wal")), db)
        XCTAssertEqual(OpenCodeActivity.database(root.appendingPathComponent("opencode-canary.db-wal")),
                       root.appendingPathComponent("opencode-canary.db"))
        XCTAssertNil(OpenCodeActivity.database(root.appendingPathComponent("opencode.db-shm")),
                     "a read-only reader writes -shm itself")
        XCTAssertNil(OpenCodeActivity.database(root.appendingPathComponent("opencode-.db")))
        XCTAssertNil(OpenCodeActivity.database(root.appendingPathComponent("storage/session/x.json")))
        XCTAssertEqual(AgentLogSource.openCode().id, "opencode")
        XCTAssertNil(AgentLogSource.openCode().hooks)
    }
}
