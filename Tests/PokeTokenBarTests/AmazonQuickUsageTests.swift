import XCTest
import SQLite3
@testable import PokeTokenBar

/// Synthetic SQLite fixtures mirroring Amazon Quick's `session_events` schema.
/// No personal Quick data is used by these tests.
final class AmazonQuickUsageTests: XCTestCase, @unchecked Sendable {
    private var home: URL!
    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("AmazonQuickTests-\(UUID())")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: home) }

    private var roots: [URL] { LocalAmazonQuickUsageReader.roots(customRootsValue: nil, home: home) }
    private func scan(since: Date = .distantPast) -> [LocalUsageReader.Entry] {
        LocalAmazonQuickUsageReader.entries(modifiedSince: since, roots: roots)
    }
    private func total(_ entries: [LocalUsageReader.Entry]) -> Int { entries.reduce(0) { $0 + $1.total } }

    private func sql(_ text: String, at url: URL) throws {
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        XCTAssertEqual(sqlite3_exec(db, text, nil, nil, nil), SQLITE_OK,
                       db.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed")
    }

    /// Creates a `sessions.db` at `<home>/.quickwork[/profiles/<profile>]/sessions/sessions.db`
    /// with the real `session_events` schema, seeded with the given assistant-complete events.
    /// A decoy `message_user` row is added so the type filter is exercised.
    @discardableResult
    private func fixture(profile: String? = nil,
                         events: [(session: String, usage: String, date: Date)]) throws -> URL {
        var base = home.appendingPathComponent(".quickwork")
        if let profile { base = base.appendingPathComponent("profiles/\(profile)") }
        let sessions = base.appendingPathComponent("sessions")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let db = sessions.appendingPathComponent("sessions.db")

        var seed = """
            CREATE TABLE session_events (
                rowid INTEGER PRIMARY KEY,
                id TEXT UNIQUE NOT NULL,
                session_id TEXT NOT NULL,
                type TEXT NOT NULL,
                timestamp REAL NOT NULL,
                data TEXT NOT NULL
            );
            INSERT INTO session_events (id, session_id, type, timestamp, data)
                VALUES ('decoy-user', 's-decoy', 'message_user', \(Date().timeIntervalSince1970), '{"full_content":"hi"}');
            """
        var n = 0
        for event in events {
            n += 1
            let data = "{\"_response_message_id\":\"msg-\(n)\",\"token_usage\":\(event.usage)}"
                .replacingOccurrences(of: "'", with: "''")
            seed += """
                INSERT INTO session_events (id, session_id, type, timestamp, data)
                    VALUES ('evt-\(n)', '\(event.session)', 'message_assistant_complete', \(event.date.timeIntervalSince1970), '\(data)');
                """
        }
        try sql(seed, at: db)
        return db
    }

    private let usageA = "{\"input_tokens\":137,\"output_tokens\":287,\"cache_read_tokens\":34638,\"cache_write_tokens\":22605,\"model\":\"balanced\"}"
    // Total of usageA = 137 + 287 + 34638 + 22605 = 57667
    private let usageATotal = 57667

    func testParsesRealTokenUsageBuckets() throws {
        try fixture(events: [("s1", usageA, Date())])
        let entry = try XCTUnwrap(scan().first)
        XCTAssertEqual(scan().count, 1)
        XCTAssertEqual(entry.input, 137)
        XCTAssertEqual(entry.output, 287)
        XCTAssertEqual(entry.cacheRead, 34638)
        XCTAssertEqual(entry.cacheWrite, 22605)
        XCTAssertEqual(entry.total, usageATotal)
        XCTAssertEqual(entry.model, "balanced")
        XCTAssertEqual(entry.costUnavailable, true, "the plan-mode label has no price table")
    }

    /// A single database holds every session — the reader sums all of them, so multi-session
    /// totals need no per-session file scanning.
    func testSumsMultipleSessionsInOneDatabase() throws {
        try fixture(events: [
            ("s1", usageA, Date()),
            ("s2", usageA, Date()),
            ("s3", usageA, Date()),
        ])
        XCTAssertEqual(scan().count, 3)
        XCTAssertEqual(total(scan()), usageATotal * 3)
    }

    /// Enterprise/team installs keep one database per profile under `profiles/<id>/sessions`;
    /// the reader scans every profile plus the single-profile `sessions/` location.
    func testSumsAcrossMultipleProfilesAndSingleProfileLocation() throws {
        try fixture(profile: "enterprise-aaa", events: [("s1", usageA, Date())])
        try fixture(profile: "enterprise-bbb", events: [("s2", usageA, Date())])
        try fixture(events: [("s3", usageA, Date())]) // single-profile ~/.quickwork/sessions
        XCTAssertEqual(scan().count, 3)
        XCTAssertEqual(total(scan()), usageATotal * 3)
    }

    /// Aborted/empty turns carry all-zero buckets; they must not surface as a 0-token active block.
    func testDropsZeroTokenTurns() throws {
        try fixture(events: [("s1", "{\"input_tokens\":0,\"output_tokens\":0,\"cache_read_tokens\":0,\"cache_write_tokens\":0}", Date())])
        XCTAssertTrue(scan().isEmpty)
        XCTAssertNil(LocalUsageReader.activeBlock(entries: scan(), now: Date()))
    }

    /// The `type` filter must exclude non-assistant rows (the decoy `message_user`).
    func testIgnoresNonAssistantEvents() throws {
        try fixture(events: [("s1", usageA, Date())])
        XCTAssertEqual(scan().count, 1)
    }

    /// Tokens land in the day of the turn's completion timestamp.
    func testTimestampDrivesLocalDay() throws {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        try fixture(events: [
            ("s-today", usageA, startOfToday.addingTimeInterval(3600)),
            ("s-yesterday", usageA, startOfToday.addingTimeInterval(-3600)),
        ])
        let todayOnly = scan(since: startOfToday)
        XCTAssertEqual(todayOnly.count, 1)
        XCTAssertEqual(todayOnly.first?.localDay, LocalUsageReader.todayKey())
    }

    /// A database that cannot be opened or queried is skipped, never blanking healthy ones.
    func testSkipsUnreadableDatabaseAndKeepsHealthyOnes() throws {
        try fixture(profile: "good", events: [("s1", usageA, Date())])
        let badSessions = home.appendingPathComponent(".quickwork/profiles/bad/sessions")
        try FileManager.default.createDirectory(at: badSessions, withIntermediateDirectories: true)
        try Data("not a database".utf8).write(to: badSessions.appendingPathComponent("sessions.db"))
        XCTAssertEqual(total(scan()), usageATotal, "the healthy profile survives the broken one")
    }

    /// Malformed `token_usage` JSON is skipped without throwing.
    func testMalformedUsageJSONIsSkipped() throws {
        let db = try fixture(events: [("s1", usageA, Date())])
        try sql("UPDATE session_events SET data = 'token_usage but not json' WHERE id = 'evt-1'", at: db)
        XCTAssertTrue(scan().isEmpty)
    }

    /// The provider is registered in the store and exposes custom-scan-root support.
    @MainActor
    func testRegisteredInUsageStoreWithCustomRootSupport() throws {
        let suite = "AmazonQuickRegistration-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let ids = UsageStore(autoRefresh: false, defaults: defaults).registeredProviderIDs
        XCTAssertTrue(ids.contains("amazonquick"))
        XCTAssertEqual(CustomScanRoots.curatedRoots(for: "amazonquick"),
                       LocalAmazonQuickUsageReader.roots(customRootsValue: nil))
        let extra = home.appendingPathComponent("extra")
        try FileManager.default.createDirectory(at: extra, withIntermediateDirectories: true)
        XCTAssertEqual(LocalAmazonQuickUsageReader.roots(customRootsValue: extra.path, home: home).map(\.path),
                       [home.appendingPathComponent(".quickwork").path, extra.path])
    }

    /// One shared scan feeds daily and enrichment totals.
    func testEnrichmentTotalsFromSharedScan() throws {
        try fixture(events: [("s1", usageA, Date()), ("s2", usageA, Date())])
        let entries = scan()
        XCTAssertEqual(total(entries), usageATotal * 2)
        let enrichment = ProviderEnrichment.local(entries: entries)
        XCTAssertTrue(enrichment.periodsOK && enrichment.blocksOK)
        XCTAssertEqual(enrichment.monthTotal?.totalTokens, usageATotal * 2)
    }
}
