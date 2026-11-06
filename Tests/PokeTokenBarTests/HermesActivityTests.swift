import XCTest
@testable import PokeTokenBar

/// Synthetic `state.db` files shaped like Hermes Agent v0.23.0 (`hermes_state_common.py`).
final class HermesActivityTests: XCTestCase {
    private var directory: URL!
    private var now = Date()
    private var seconds: Double { now.timeIntervalSince1970 }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("HermesActivityTests-\(UUID())")
        now = Date()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func fixture(admissions: Bool = false, at path: String = "state.db") throws -> AgentDatabaseFixture {
        try AgentDatabaseFixture(directory.appendingPathComponent(path), schema: """
            CREATE TABLE sessions (id TEXT PRIMARY KEY, source TEXT NOT NULL, model TEXT, parent_session_id TEXT,
                started_at REAL NOT NULL, cwd TEXT, title TEXT);
            CREATE TABLE messages (id INTEGER PRIMARY KEY AUTOINCREMENT, session_id TEXT NOT NULL REFERENCES sessions(id),
                role TEXT NOT NULL, content TEXT, tool_call_id TEXT, tool_calls TEXT, tool_name TEXT,
                timestamp REAL NOT NULL, finish_reason TEXT, active INTEGER NOT NULL DEFAULT 1, message_uid TEXT);
            CREATE INDEX idx_messages_session_id ON messages(session_id, id);
            \(admissions ? """
            CREATE TABLE session_admissions (seq INTEGER PRIMARY KEY AUTOINCREMENT, admission_id TEXT NOT NULL UNIQUE,
                target_session_id TEXT NOT NULL REFERENCES sessions(id), intent TEXT NOT NULL,
                status TEXT NOT NULL, outcome TEXT);
            CREATE INDEX session_admissions_pending ON session_admissions(target_session_id, status, seq);
            """ : "")
            """)
    }

    private func session(_ db: AgentDatabaseFixture, _ id: String, source: String = "cli",
                         cwd: String? = "/Users/me/code/agent-lab", title: String? = "Tidy the README") throws {
        try db.exec("""
            INSERT INTO sessions VALUES ('\(id)', '\(source)', 'm', NULL, \(seconds),
                \(cwd.map(AgentDatabaseFixture.quoted) ?? "NULL"), \(title.map(AgentDatabaseFixture.quoted) ?? "NULL"));
            """)
    }

    private var uid = 0
    private func message(_ db: AgentDatabaseFixture, _ session: String, role: String, at time: Double? = nil,
                         toolCalls: String? = nil, toolCallID: String? = nil, finish: String? = nil) throws {
        uid += 1
        try db.exec("""
            INSERT INTO messages (session_id, role, content, tool_call_id, tool_calls, timestamp, finish_reason, message_uid)
            VALUES ('\(session)', '\(role)', 'text', \(toolCallID.map { "'\($0)'" } ?? "NULL"),
                \(toolCalls.map(AgentDatabaseFixture.quoted) ?? "NULL"), \(time ?? seconds),
                \(finish.map { "'\($0)'" } ?? "NULL"), 'uid\(uid)');
            """)
    }

    private static func calls(_ names: String...) -> String {
        "[" + names.enumerated().map { #"{"id":"call_\#($0.offset)","type":"function","function":{"name":"\#($0.element)","arguments":"{}"}}"# }
            .joined(separator: ",") + "]"
    }

    private func read(_ db: AgentDatabaseFixture, _ watermark: String?) -> (readings: [AgentLogReading], watermark: String?) {
        HermesActivity.read(db.url, watermark: watermark, now: now)
    }

    func testFirstLookKeepsRecentLocalSessionsOnly() throws {
        let db = try fixture()
        try session(db, "cli_old")
        try session(db, "cli_new")
        try session(db, "tg", source: "telegram")
        try session(db, "sub", source: "subagent")
        try message(db, "cli_old", role: "user", at: seconds - 3_600)
        try message(db, "cli_new", role: "user")
        try message(db, "tg", role: "user")
        try message(db, "sub", role: "user")
        let first = read(db, nil)
        XCTAssertEqual(first.readings, [AgentLogReading(activity: .working, label: "agent-lab", title: "Tidy the README",
                                                        session: "cli_new")])
        XCTAssertEqual(read(db, first.watermark).readings, [])
    }

    func testTurnFromPromptThroughToolsToStop() throws {
        let db = try fixture()
        try session(db, "s", cwd: nil, title: nil)
        var mark = read(db, nil).watermark
        try message(db, "s", role: "user")
        var result = read(db, mark)
        XCTAssertEqual(result.readings, [AgentLogReading(activity: .working, label: nil, session: "s")])
        mark = result.watermark

        try message(db, "s", role: "assistant", toolCalls: Self.calls("terminal"), finish: "tool_calls")
        try message(db, "s", role: "tool", toolCallID: "call_0")
        result = read(db, mark)
        XCTAssertEqual(result.readings.map(\.activity), [.working])
        mark = result.watermark

        try message(db, "s", role: "assistant", finish: "stop")
        result = read(db, mark)
        XCTAssertEqual(result.readings.map(\.activity), [.done(message: nil)])
        XCTAssertEqual(result.readings.first?.lineID, "uid4", "the row's durable uid, which a compaction clone keeps")
    }

    func testUnansweredClarifyIsWaiting() throws {
        let db = try fixture()
        try session(db, "s")
        var mark = read(db, nil).watermark
        // The clarify call shares a batch with a tool whose result is already written.
        try message(db, "s", role: "assistant", toolCalls: Self.calls("read_file", "clarify"), finish: "tool_calls")
        try message(db, "s", role: "tool", toolCallID: "call_0")
        var result = read(db, mark)
        XCTAssertEqual(result.readings.map(\.activity), [.waiting(message: nil)])
        XCTAssertEqual(result.readings.first?.lineID, "call_1")
        mark = result.watermark

        try message(db, "s", role: "tool", toolCallID: "call_1")
        result = read(db, mark)
        XCTAssertEqual(result.readings.map(\.activity), [.working])
    }

    func testArchivedCompactionRowsAreIgnored() throws {
        let db = try fixture()
        try session(db, "s")
        let mark = read(db, nil).watermark
        try message(db, "s", role: "user")
        try message(db, "s", role: "assistant", finish: "stop")
        try db.exec("UPDATE messages SET active = 0 WHERE role = 'assistant';")
        XCTAssertEqual(read(db, mark).readings.map(\.activity), [.working])
    }

    /// A stop-gate nudge writes an interim answer and keeps the turn: the admission is still started.
    func testAdmissionsHoldBackAnInterimAnswerAndDecideTheEnd() throws {
        let db = try fixture(admissions: true)
        try session(db, "s")
        var mark = read(db, nil).watermark
        try db.exec("INSERT INTO session_admissions (admission_id, target_session_id, intent, status) VALUES ('a1', 's', 'queue', 'started');")
        try message(db, "s", role: "user")
        try message(db, "s", role: "assistant", finish: "stop")
        var result = read(db, mark)
        XCTAssertEqual(result.readings.map(\.activity), [.working])
        mark = result.watermark

        try db.exec("UPDATE session_admissions SET status = 'terminal', outcome = 'completed' WHERE admission_id = 'a1';")
        result = read(db, mark)
        XCTAssertEqual(result.readings.map(\.activity), [.done(message: nil)], "seen on the open session, without new rows")
        mark = result.watermark

        // A steered input folds into a turn that then gets interrupted.
        try db.exec("""
            INSERT INTO session_admissions (admission_id, target_session_id, intent, status) VALUES ('a2', 's', 'queue', 'started');
            INSERT INTO session_admissions (admission_id, target_session_id, intent, status, outcome)
                VALUES ('a3', 's', 'steer', 'terminal', 'steered');
            """)
        try message(db, "s", role: "user")
        result = read(db, mark)
        XCTAssertEqual(result.readings.map(\.activity), [.working])
        mark = result.watermark
        try db.exec("UPDATE session_admissions SET status = 'terminal', outcome = 'interrupted' WHERE admission_id = 'a2';")
        XCTAssertEqual(read(db, mark).readings.map(\.activity), [.idle])
    }

    func testProfilesAndSidecars() throws {
        let profile = directory.appendingPathComponent("profiles/coder/state.db")
        XCTAssertEqual(HermesActivity.database(profile), profile)
        XCTAssertEqual(HermesActivity.database(directory.appendingPathComponent("profiles/coder/state.db-wal")), profile)
        XCTAssertNil(HermesActivity.database(directory.appendingPathComponent("state.db-shm")))
        XCTAssertNil(HermesActivity.database(directory.appendingPathComponent("logs/errors.log")))

        let db = try fixture(at: "profiles/coder/state.db")
        try session(db, "p", title: "Coder profile")
        try message(db, "p", role: "user")
        XCTAssertEqual(read(db, nil).readings.map(\.title), ["Coder profile"])
        XCTAssertEqual(AgentLogSource.hermes().id, "hermes")
    }
}
