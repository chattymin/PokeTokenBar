import XCTest
@testable import PokeTokenBar

/// Synthetic Devin CLI `sessions.db` files: `message_nodes` as in `DevinUsageTests`, `sessions`
/// with and without the optional label/title columns.
final class DevinActivityTests: XCTestCase {
    private var directory: URL!
    private var now = Date()
    private var seconds: Int64 { Int64(now.timeIntervalSince1970) }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("DevinActivityTests-\(UUID())")
        now = Date()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func fixture(sessionColumns: Bool = true) throws -> AgentDatabaseFixture {
        let sessions = sessionColumns
            ? "CREATE TABLE sessions (id TEXT PRIMARY KEY, model TEXT NOT NULL, title TEXT, working_directory TEXT, hidden INTEGER);"
            : "CREATE TABLE sessions (id TEXT PRIMARY KEY, model TEXT NOT NULL);"
        return try AgentDatabaseFixture(directory.appendingPathComponent("devin/cli/sessions.db"), schema: sessions + """
            CREATE TABLE message_nodes (row_id INTEGER PRIMARY KEY AUTOINCREMENT, session_id TEXT NOT NULL,
                node_id INTEGER, chat_message TEXT NOT NULL, created_at INTEGER NOT NULL);
            """)
    }

    private func node(_ db: AgentDatabaseFixture, _ session: String, role: String = "assistant", at time: Int64? = nil) throws {
        try db.exec("""
            INSERT INTO message_nodes (session_id, node_id, chat_message, created_at)
            VALUES ('\(session)', 1, '{"role":"\(role)","metadata":{"metrics":null}}', \(time ?? seconds));
            """)
    }

    private func read(_ db: AgentDatabaseFixture, _ watermark: String?) -> (readings: [AgentLogReading], watermark: String?) {
        DevinActivity.read(db.url, watermark: watermark, now: now)
    }

    func testNewNodesAreWorkingWithFolderAndTitle() throws {
        let db = try fixture()
        try db.exec("""
            INSERT INTO sessions VALUES ('main', 'swe-2-max', 'Port the parser', '/Users/me/code/parser', 0),
                ('old', 'swe-2-max', 'Old', '/Users/me/code/old', 0), ('hid', 'swe-2-max', 'Hidden', '/tmp/x', 1);
            """)
        try node(db, "old", at: seconds - 3_600)
        try node(db, "main", role: "user")
        try node(db, "hid", role: "user")
        let first = read(db, nil)
        XCTAssertEqual(first.readings, [AgentLogReading(activity: .working, label: "parser", title: "Port the parser",
                                                        session: "main")])

        var mark = first.watermark
        XCTAssertEqual(read(db, mark).readings, [], "nothing new")
        try node(db, "main")
        let next = read(db, mark)
        XCTAssertEqual(next.readings.map(\.activity), [.working])
        mark = next.watermark
        XCTAssertEqual(read(db, mark).readings, [])
    }

    func testOnlyWorkingIsReportedAndOldCopiesAreIgnored() throws {
        let db = try fixture(sessionColumns: false)
        try db.exec("INSERT INTO sessions VALUES ('main', 'swe-2-max');")
        let mark = read(db, nil).watermark
        // A branch copy of an old message: new row id, old time.
        try node(db, "main", at: seconds - 3_600)
        XCTAssertEqual(read(db, mark).readings, [])
        try node(db, "main", role: "assistant")
        XCTAssertEqual(read(db, mark).readings, [AgentLogReading(activity: .working, label: nil, session: "main")],
                       "no done is inferred and no label without the column")
    }

    func testDatabaseLocation() {
        let db = URL(fileURLWithPath: "/Users/me/.local/share/devin/cli/sessions.db")
        XCTAssertEqual(DevinActivity.database(db), db)
        XCTAssertEqual(DevinActivity.database(URL(fileURLWithPath: db.path + "-wal")), db)
        XCTAssertNil(DevinActivity.database(URL(fileURLWithPath: db.path + "-shm")))
        XCTAssertNil(DevinActivity.database(URL(fileURLWithPath: "/Users/me/.local/share/devin/sessions.db")))
        XCTAssertEqual(AgentLogSource.devin().id, "devin")
    }
}
