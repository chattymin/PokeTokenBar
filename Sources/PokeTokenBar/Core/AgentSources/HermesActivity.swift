import Foundation

extension AgentLogSource {
    /// Hermes Agent: `$HERMES_HOME/state.db` (default `~/.hermes`) and one per named profile under
    /// `profiles/<name>/state.db`, WAL (`website/docs/developer-guide/session-storage.md`).
    static func hermes() -> AgentLogSource {
        AgentLogSource(
            id: "hermes",
            roots: {
                LocalAdditionalUsageReader.hermesRoots(customRootsValue: CustomScanRoots.storedValue(for: "hermes"))
                    .map { $0.pathExtension == "db" ? $0.deletingLastPathComponent() : $0 }
            },
            accepts: { HermesActivity.database($0) != nil },
            interpret: { _ in nil },
            hooks: nil,
            database: AgentDatabaseReader(
                database: HermesActivity.database(_:),
                read: { HermesActivity.read($0, watermark: $1) }))
    }
}

/// Reads Hermes Agent's `state.db`. Schema checked against NousResearch/hermes-agent v0.23.0
/// (`hermes_state_common.py` `SCHEMA_SQL`, 2026-11):
/// - `messages(id AUTOINCREMENT, session_id, role, tool_calls JSON, tool_call_id, finish_reason,
///   timestamp REAL seconds, active, message_uid)`, indexed `(session_id, id)`. The assistant
///   tool-call row is written before its tools run (`agent/turn_tool_round.py`), so a `clarify`
///   call (`tools/clarify_tool.py`) without its tool row yet is the agent waiting for an answer.
/// - `sessions(id, source, cwd, title)`. Only the person's own surfaces count: `cli`, `tui`, `gui`,
///   `desktop`, `acp` (`LEGACY_LOCAL_SOURCES` in `hermes_state_local_migration.py`, without the
///   scripted `oneshot`/`tool`). Messaging bots, cron, kanban and `subagent` sessions are skipped.
///   `parent_session_id` is a compression split, not a subagent, so it is not a filter.
/// - `session_admissions(seq AUTOINCREMENT, target_session_id, status, outcome)` (since 2026-09):
///   every input's turn goes `queued → started → terminal` (`hermes_state_runtime.py`).
///
/// Newest active row: user or tool → working; assistant with tool calls → working (waiting for an
/// unanswered `clarify`); assistant with `finish_reason = 'stop'` and no tool calls → done.
/// When admissions exist they decide whether the turn is over: a stop-gate nudge
/// (`agent/turn_stop_gates.py`) writes an interim answer row and keeps the turn going, so a done
/// is only reported once no admission is queued or started, and a turn that ended any other way
/// than `completed` (failed, interrupted, cancelled, lost in a restart) is idle.
enum HermesActivity {
    static let localSources = ["cli", "tui", "gui", "desktop", "acp"]

    /// Not Aside's `u/<account>/state.db`, which shares the file name.
    static func database(_ url: URL) -> URL? {
        guard !AsideActivity.isAsideLayout(url) else { return nil }
        return AgentDatabasePoll.database(url) { $0 == "state.db" }
    }

    static func read(_ database: URL, watermark: String?, now: Date = Date()) -> (readings: [AgentLogReading], watermark: String?) {
        AgentDatabasePoll.read(database, watermark: watermark, now: now, feeds: feeds, probe: probe)
    }

    private static func feeds(_ db: AgentSQLiteConnection) -> [AgentDatabaseFeed] {
        let tables = db.tables ?? []
        guard tables.isSuperset(of: ["sessions", "messages"]) else { return [] }
        var feeds = [AgentDatabaseFeed(table: "messages", sql: "SELECT session_id, id, timestamp FROM messages WHERE id > ?1")]
        if tables.contains("session_admissions") {
            // No time column: a first look takes its sessions from the messages alone.
            feeds.append(.init(table: "session_admissions",
                               sql: "SELECT target_session_id, seq, NULL FROM session_admissions WHERE seq > ?1"))
        }
        return feeds
    }

    private struct Row {
        var id: Int64
        var role: String
        var toolCalls: [(id: String?, name: String?)]
        var finishReason: String?
        var toolCallID: String?
        var uid: String?
    }

    private static func probe(_ db: AgentSQLiteConnection, key session: String, ref _: Int64?) -> AgentSessionProbe? {
        let sessionColumns = db.columns("sessions")
        let cwd = sessionColumns.contains("cwd") ? "cwd" : "NULL"
        let placeholders = localSources.indices.map { "?\($0 + 2)" }.joined(separator: ", ")
        guard let info = db.query(
            "SELECT \(cwd), title FROM sessions WHERE id = ?1 AND source IN (\(placeholders))",
            [.text(session)] + localSources.map { .text($0) },
            { row in (label: AgentDatabasePoll.folderName(row.text(0)), title: AgentDatabasePoll.nonEmpty(row.text(1))) })?.first
        else { return nil }

        let messageColumns = db.columns("messages")
        // Compaction archives old rows as `active = 0` and inserts the kept context again.
        let active = messageColumns.contains("active") ? "AND active = 1" : ""
        let uid = messageColumns.contains("message_uid") ? "message_uid" : "NULL"
        // The newest rows of one session through `idx_messages_session_id (session_id, id)`; enough
        // to reach the assistant row behind a batch of tool results.
        guard let rows = db.query("""
            SELECT id, role, tool_calls, finish_reason, tool_call_id, \(uid) FROM messages
            WHERE session_id = ?1 \(active) AND role IN ('user', 'assistant', 'tool')
            ORDER BY id DESC LIMIT 32
            """, [.text(session)], { row -> Row? in
                guard let role = row.text(1) else { return nil }
                return Row(id: row.int64(0) ?? 0, role: role, toolCalls: toolCalls(row.text(2)),
                           finishReason: row.text(3), toolCallID: row.text(4), uid: row.text(5))
            }),
              let newest = rows.first
        else { return nil }

        var activity = activity(rows)
        if db.tables?.contains("session_admissions") == true {
            activity = admitted(db, session: session, messages: activity)
        }
        let lineID: String? = switch activity.activity {
        case .done: newest.uid ?? "row:\(newest.id)"
        case .waiting: activity.lineID
        case .working, .idle: nil
        }
        return AgentSessionProbe(
            reading: AgentLogReading(activity: activity.activity, label: info.label, lineID: lineID,
                                     title: info.title, session: session),
            progress: String(newest.id))
    }

    /// What the newest rows (newest first) say on their own.
    private static func activity(_ rows: [Row]) -> (activity: AgentActivity, lineID: String?) {
        guard let newest = rows.first else { return (.working, nil) }
        switch newest.role {
        case "user":
            return (.working, nil)
        case "assistant" where newest.toolCalls.isEmpty:
            return (newest.finishReason == "stop" ? .done(message: nil) : .working, nil)
        default:
            // A tool-call row followed only by its results: an unanswered `clarify` is waiting.
            var answered = Set<String>()
            for row in rows {
                if row.role == "tool" {
                    if let id = row.toolCallID { answered.insert(id) }
                    continue
                }
                guard row.role == "assistant", !row.toolCalls.isEmpty else { break }
                if let clarify = row.toolCalls.first(where: { $0.name == "clarify" && !answered.contains($0.id ?? "") }) {
                    return (.waiting(message: nil), clarify.id ?? "row:\(row.id)")
                }
                break
            }
            return (.working, nil)
        }
    }

    /// The turn state the session authority keeps, over what the rows say.
    private static func admitted(_ db: AgentSQLiteConnection, session: String,
                                 messages: (activity: AgentActivity, lineID: String?)) -> (activity: AgentActivity, lineID: String?) {
        // `session_admissions_pending (target_session_id, status, seq)`.
        guard let running = db.query("""
            SELECT 1 FROM session_admissions WHERE target_session_id = ?1 AND status IN ('queued', 'started') LIMIT 1
            """, [.text(session)], { _ in true })
        else { return (messages.activity == .done(message: nil) ? .working : messages.activity, messages.lineID) }
        if !running.isEmpty {
            switch messages.activity {
            case .waiting: return messages
            case .working, .done, .idle: return (.working, nil)
            }
        }
        // A steered input folds into the running turn and ends on its own; the turn's outcome is
        // the newest other one.
        let last = db.query("""
            SELECT status, outcome FROM session_admissions
            WHERE target_session_id = ?1 AND NOT (status = 'terminal' AND outcome = 'steered')
            ORDER BY seq DESC LIMIT 1
            """, [.text(session)]) { row in (status: row.text(0), outcome: row.text(1)) }
        guard let last, let newest = last.first else {
            // No admission for this session (written before admissions, or a failed read).
            return last == nil && messages.activity == .done(message: nil) ? (.working, nil) : messages
        }
        if newest.status == "terminal", newest.outcome == "completed", messages.activity == .done(message: nil) {
            return messages
        }
        return (.idle, nil)
    }

    /// `[{"id": …, "function": {"name": …}}]` (OpenAI shape, `SessionDB.append_message`).
    private static func toolCalls(_ json: String?) -> [(id: String?, name: String?)] {
        guard let json, let data = json.data(using: .utf8),
              let calls = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }
        return calls.map { call in
            (call["id"] as? String, (call["function"] as? [String: Any])?["name"] as? String ?? call["name"] as? String)
        }
    }
}
