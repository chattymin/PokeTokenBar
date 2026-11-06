import Foundation

extension AgentLogSource {
    /// Devin CLI: `$XDG_DATA_HOME/devin/cli/sessions.db` (default `~/.local/share/devin`), WAL.
    static func devin() -> AgentLogSource {
        AgentLogSource(
            id: "devin",
            roots: {
                LocalAdditionalUsageReader.devinRoots(customRootsValue: CustomScanRoots.storedValue(for: "devin"))
                    .map { $0.pathExtension == "db" ? $0.deletingLastPathComponent() : $0 }
            },
            accepts: { DevinActivity.database($0) != nil },
            interpret: { _ in nil },
            hooks: nil,
            database: AgentDatabaseReader(
                database: DevinActivity.database(_:),
                read: { DevinActivity.read($0, watermark: $1) }))
    }
}

/// Reads Devin CLI's `sessions.db`. The format is undocumented; what this relies on is what the
/// app's usage reader already reads from real databases (`LocalAdditionalUsageReader.devinEntries`,
/// `DevinUsageTests`): `message_nodes(row_id INTEGER PRIMARY KEY AUTOINCREMENT, session_id,
/// chat_message JSON, created_at)` with `created_at` in epoch seconds, one row per chat message.
///
/// So it reports **working only**: a new message node in a session means Devin is at work there.
/// Nothing confirmed marks the end of a turn (no finish reason; assistant rows carry metrics, and
/// branch copies re-insert old messages under new row ids), so done, waiting and idle are not
/// inferred; the pet's working timeout ends the state instead. Rows older than two minutes are
/// ignored, so a branch copy of an old conversation does not start "working".
///
/// Label and title are read only when the `sessions` table has the columns another reader of
/// these databases relies on (`working_directory`, `title`, `hidden`; kenn-io/agentsview
/// `internal/parser/devin.go`); hidden sessions are skipped.
enum DevinActivity {
    static let freshRow: TimeInterval = 120

    static func database(_ url: URL) -> URL? {
        guard url.deletingLastPathComponent().lastPathComponent == "cli" else { return nil }
        return AgentDatabasePoll.database(url) { $0 == "sessions.db" }
    }

    static func read(_ database: URL, watermark: String?, now: Date = Date()) -> (readings: [AgentLogReading], watermark: String?) {
        AgentDatabasePoll.read(database, watermark: watermark, now: now, feeds: feeds, probe: { db, session, _ in
            probe(db, session: session, now: now)
        })
    }

    private static func feeds(_ db: AgentSQLiteConnection) -> [AgentDatabaseFeed] {
        guard db.tables?.contains("message_nodes") == true else { return [] }
        return [AgentDatabaseFeed(
            table: "message_nodes", sql: "SELECT session_id, row_id, created_at FROM message_nodes WHERE row_id > ?1")]
    }

    private static func probe(_ db: AgentSQLiteConnection, session: String, now: Date) -> AgentSessionProbe? {
        // The session's newest node through the primary key, scanning back from the end.
        guard let newest = db.query("""
            SELECT row_id, created_at FROM message_nodes WHERE session_id = ?1 ORDER BY row_id DESC LIMIT 1
            """, [.text(session)], { row in (id: row.int64(0) ?? 0, created: row.double(1) ?? 0) })?.first,
              now.timeIntervalSince1970 - AgentDatabasePoll.seconds(newest.created) < freshRow
        else { return nil }
        var label: String?
        var title: String?
        let columns = db.columns("sessions")
        if !columns.isEmpty {
            let folder = columns.contains("working_directory") ? "working_directory" : "NULL"
            let name = columns.contains("title") ? "title" : "NULL"
            let hidden = columns.contains("hidden") ? "COALESCE(hidden, 0)" : "0"
            let info = db.query("SELECT \(folder), \(name), \(hidden) FROM sessions WHERE id = ?1", [.text(session)]) { row in
                (folder: row.text(0), title: row.text(1), hidden: row.int64(2) == 1)
            }?.first
            if info?.hidden == true { return nil }
            label = AgentDatabasePoll.folderName(info?.folder)
            title = AgentDatabasePoll.nonEmpty(info?.title)
        }
        return AgentSessionProbe(
            reading: AgentLogReading(activity: .working, label: label, title: title, session: session),
            progress: String(newest.id))
    }
}
