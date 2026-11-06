import Foundation

extension AgentLogSource {
    /// Aside: one `state.db` per account under `~/.aside/u/<account>/`.
    static func aside() -> AgentLogSource {
        AgentLogSource(
            id: "aside",
            roots: { LocalAsideUsageReader.roots(customRootsValue: CustomScanRoots.storedValue(for: "aside")) },
            accepts: { AsideActivity.database($0) != nil },
            interpret: { _ in nil },
            hooks: nil,
            database: AgentDatabaseReader(
                database: AsideActivity.database(_:),
                read: { AsideActivity.read($0, watermark: $1) }))
    }
}

/// Reads Aside's `session_turns(id INTEGER PRIMARY KEY AUTOINCREMENT, session_id, started_at,
/// last_message_timestamp, finished_at, aborted_at)`, the table `LocalAsideUsageReader` reads for
/// usage (schema mirrored in `AsideUsageTests`). One row per turn, updated in place while it runs:
/// - neither `finished_at` nor `aborted_at` → working (each newer `last_message_timestamp`
///   refreshes it);
/// - `aborted_at` → idle; `finished_at` → done.
///
/// New turns are found by `id`; a running turn is rechecked by its `id` (primary key) until it
/// ends, so no read scans the table.
///
/// Aside sessions have no working folder, so the label is the fixed name "Aside". A nil label would
/// share the pet's unlabeled slot with every other agent that has no folder, and an Aside idle would
/// then clear that agent's state; the fixed name keeps Aside in a slot of its own and reads as the
/// agent's name in the bubble. No title column is known.
enum AsideActivity {
    static let label = "Aside"

    /// `u/<account>/state.db` only: Hermes keeps a `state.db` too, and custom roots may overlap.
    static func database(_ url: URL) -> URL? {
        guard isAsideLayout(url) else { return nil }
        return AgentDatabasePoll.database(url) { $0 == "state.db" }
    }

    static func isAsideLayout(_ url: URL) -> Bool {
        url.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent == "u"
    }

    static func read(_ database: URL, watermark: String?, now: Date = Date()) -> (readings: [AgentLogReading], watermark: String?) {
        AgentDatabasePoll.read(database, watermark: watermark, now: now, feeds: feeds, probe: probe)
    }

    private static func feeds(_ db: AgentSQLiteConnection) -> [AgentDatabaseFeed] {
        guard db.tables?.contains("session_turns") == true else { return [] }
        return [AgentDatabaseFeed(table: "session_turns", sql: """
            SELECT session_id, id, COALESCE(aborted_at, finished_at, last_message_timestamp, started_at)
            FROM session_turns WHERE id > ?1
            """)]
    }

    private static func probe(_ db: AgentSQLiteConnection, key session: String, ref turn: Int64?) -> AgentSessionProbe? {
        guard let turn,
              let row = db.query("""
                  SELECT id, finished_at, aborted_at, last_message_timestamp FROM session_turns
                  WHERE id = ?1 AND session_id = ?2
                  """, [.int(turn), .text(session)], { row in
                      (id: row.int64(0) ?? turn, finished: !row.isNull(1), aborted: !row.isNull(2), last: row.text(3))
                  })?.first
        else { return nil }
        let activity: AgentActivity = row.aborted ? .idle : row.finished ? .done(message: nil) : .working
        return AgentSessionProbe(
            reading: AgentLogReading(activity: activity, label: label,
                                     lineID: row.finished ? "turn:\(row.id)" : nil, session: session),
            progress: row.last, ref: row.id)
    }
}
