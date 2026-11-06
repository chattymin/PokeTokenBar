import XCTest
@testable import PokeTokenBar

/// Synthetic Aside `state.db` files with the `session_turns` schema `AsideUsageTests` mirrors.
final class AsideActivityTests: XCTestCase {
    private var directory: URL!
    private var now = Date()
    private var seconds: Int64 { Int64(now.timeIntervalSince1970) }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("AsideActivityTests-\(UUID())")
        now = Date()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func fixture() throws -> AgentDatabaseFixture {
        try AgentDatabaseFixture(directory.appendingPathComponent(".aside/u/0/state.db"), schema: """
            CREATE TABLE sessions (id TEXT PRIMARY KEY, model TEXT);
            CREATE TABLE session_turns (id INTEGER PRIMARY KEY AUTOINCREMENT,
                session_id TEXT REFERENCES sessions(id) ON DELETE CASCADE, token_usage TEXT, started_at INTEGER,
                last_message_timestamp INTEGER NOT NULL, finished_at INTEGER, aborted_at INTEGER);
            INSERT INTO sessions VALUES ('s1', '{"modelId":"m"}'), ('s2', '{"modelId":"m"}');
            """)
    }

    private func turn(_ db: AgentDatabaseFixture, _ session: String, at time: Int64? = nil, finished: Bool = false) throws {
        let time = time ?? seconds
        try db.exec("""
            INSERT INTO session_turns (session_id, token_usage, started_at, last_message_timestamp, finished_at)
            VALUES ('\(session)', '{}', \(time), \(time), \(finished ? String(time) : "NULL"));
            """)
    }

    private func read(_ db: AgentDatabaseFixture, _ watermark: String?) -> (readings: [AgentLogReading], watermark: String?) {
        AsideActivity.read(db.url, watermark: watermark, now: now)
    }

    func testTurnRunsThenFinishesInPlace() throws {
        let db = try fixture()
        try turn(db, "s2", at: seconds - 3_600, finished: true)
        var result = read(db, nil)
        XCTAssertEqual(result.readings, [], "a turn that ended an hour ago is not replayed")
        var mark = result.watermark

        try turn(db, "s1")
        result = read(db, mark)
        XCTAssertEqual(result.readings, [AgentLogReading(activity: .working, label: "Aside", session: "s1")])
        mark = result.watermark
        XCTAssertEqual(read(db, mark).readings, [], "an unchanged running turn says nothing new")

        // The turn row is updated in place: rechecked by its id.
        try db.exec("UPDATE session_turns SET last_message_timestamp = last_message_timestamp + 5 WHERE id = 2;")
        result = read(db, mark)
        XCTAssertEqual(result.readings.map(\.activity), [.working], "a newer message refreshes working")
        mark = result.watermark

        try db.exec("UPDATE session_turns SET finished_at = \(seconds + 6) WHERE id = 2;")
        result = read(db, mark)
        XCTAssertEqual(result.readings, [AgentLogReading(activity: .done(message: nil), label: "Aside", lineID: "turn:2",
                                                         session: "s1")])
        XCTAssertEqual(read(db, result.watermark).readings, [])
    }

    func testAbortedTurnIsIdleAndFirstLookSeesARunningTurn() throws {
        let db = try fixture()
        try turn(db, "s1")
        let first = read(db, nil)
        XCTAssertEqual(first.readings.map(\.activity), [.working])
        try db.exec("UPDATE session_turns SET aborted_at = \(seconds) WHERE id = 1;")
        XCTAssertEqual(read(db, first.watermark).readings.map(\.activity), [.idle])
    }

    func testDatabaseNames() {
        let db = directory.appendingPathComponent(".aside/u/0/state.db")
        XCTAssertEqual(AsideActivity.database(URL(fileURLWithPath: db.path + "-wal")), db)
        XCTAssertNil(AsideActivity.database(URL(fileURLWithPath: db.path + "-shm")))
        XCTAssertEqual(AgentLogSource.aside().id, "aside")
    }
}
