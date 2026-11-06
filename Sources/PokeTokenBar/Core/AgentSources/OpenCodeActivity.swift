import Foundation

extension AgentLogSource {
    /// OpenCode: `<data>/opencode.db` (`opencode-<channel>.db` for side channels), WAL. Both
    /// release lines are maintained (1.19.x and 2.x, checked 2026-11) and a 2.x database keeps the
    /// 1.x tables beside its own, so each generation is read when its tables exist.
    static func openCode() -> AgentLogSource {
        AgentLogSource(
            id: "opencode",
            roots: {
                LocalAdditionalUsageReader.openCodeRoots(customRootsValue: CustomScanRoots.storedValue(for: "opencode"))
                    .map { $0.pathExtension == "db" ? $0.deletingLastPathComponent() : $0 }
            },
            accepts: { OpenCodeActivity.database($0) != nil },
            interpret: { _ in nil },
            hooks: nil,
            database: AgentDatabaseReader(
                database: OpenCodeActivity.database(_:),
                read: { OpenCodeActivity.read($0, watermark: $1) }))
    }
}

/// Reads OpenCode's session database. Schemas checked against anomalyco/opencode (2026-11):
///
/// 1.x (v1.19.5, `packages/core/src/session/sql.ts`): `session(id, parent_id, directory, title, …)`,
/// `message(id, session_id, time_created, data)` and `part(id, message_id, session_id, data)`, both
/// upserted per update (`session/projector.ts`). `message.data` holds `role`, `time.completed`,
/// `finish`, `error`, `summary`; one assistant message per model step.
/// - user → working; assistant still streaming → working, or waiting when its `question` tool
///   (`packages/opencode/src/tool/question.ts`) is running.
/// - assistant completed with `finish` other than `tool-calls`/`unknown`, no tool part and not a
///   compaction summary → done. These are the conditions OpenCode's own loop exits on
///   (`packages/opencode/src/session/prompt.ts`); anything else starts another step.
/// - assistant with `error` → idle. Esc is `MessageAbortedError`
///   (`packages/opencode/src/cli/cmd/run/session-data.ts`); other errors also end the turn.
///
/// 2.x (v2.2.5, same file): `session_v2(id, parent_id, directory, title, time_busy, time_idle,
/// idle_outcome)` and `session_message(id, session_id, type, seq, data)` (+ `session_part` in newer
/// builds). Every execution that ends appends a `type = 'idle'` row whose `outcome` is
/// `succeeded`/`failed`/`interrupted`; a shutdown appends none, because the execution resumes
/// (`packages/core/src/session/message-updater.ts`).
/// - user/synthetic/compaction → working; assistant → working, or waiting while a `question`
///   tool's `state.status` is `running` (`packages/schema/src/session-message.ts`).
/// - idle `succeeded` → done; `failed`/`interrupted` → idle. A done is held back while
///   `time_busy` (set when an execution starts, `session/projector.ts`) is not older than `time_idle`.
///
/// Child sessions (`parent_id` set) are subagents (the `task` tool): skipped. Permission prompts
/// live only in OpenCode's memory, so waiting for a permission is not seen.
enum OpenCodeActivity {
    /// `opencode.db` or `opencode-<channel>.db` (`packages/cli/src/database-path.ts`).
    static func database(_ url: URL) -> URL? {
        AgentDatabasePoll.database(url) { name in
            guard name.hasPrefix("opencode"), name.hasSuffix(".db") else { return false }
            let channel = name.dropFirst("opencode".count).dropLast(".db".count)
            return channel.isEmpty || (channel.hasPrefix("-") && channel.count > 1 && channel.dropFirst().allSatisfy {
                $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" || $0 == ".")
            })
        }
    }

    static func read(_ database: URL, watermark: String?, now: Date = Date()) -> (readings: [AgentLogReading], watermark: String?) {
        AgentDatabasePoll.read(database, watermark: watermark, now: now, feeds: feeds, probe: probe)
    }

    private static let v1 = "1:"
    private static let v2 = "2:"

    private static func feeds(_ db: AgentSQLiteConnection) -> [AgentDatabaseFeed] {
        let tables = db.tables ?? []
        var feeds: [AgentDatabaseFeed] = []
        if tables.isSuperset(of: ["session", "message", "part"]) {
            // A new message per step and a new part per tool call or text block.
            feeds.append(.init(table: "message", sql: "SELECT session_id, rowid, time_created FROM message WHERE rowid > ?1", prefix: v1))
            feeds.append(.init(table: "part", sql: "SELECT session_id, rowid, time_created FROM part WHERE rowid > ?1", prefix: v1))
        }
        if tables.isSuperset(of: ["session_v2", "session_message"]) {
            feeds.append(.init(table: "session_message",
                               sql: "SELECT session_id, rowid, time_created FROM session_message WHERE rowid > ?1", prefix: v2))
            if tables.contains("session_part") {
                feeds.append(.init(table: "session_part",
                                   sql: "SELECT session_id, rowid, time_created FROM session_part WHERE rowid > ?1", prefix: v2))
            }
        }
        return feeds
    }

    private static func probe(_ db: AgentSQLiteConnection, key: String, ref _: Int64?) -> AgentSessionProbe? {
        if key.hasPrefix(v1) { return probeV1(db, session: String(key.dropFirst(v1.count))) }
        if key.hasPrefix(v2) { return probeV2(db, session: String(key.dropFirst(v2.count))) }
        return nil
    }

    private struct Session {
        var label: String?
        var title: String?
    }

    /// Nil for a child session or one that is gone.
    private static func session(_ db: AgentSQLiteConnection, table: String, id: String) -> Session? {
        db.query("SELECT directory, title, parent_id FROM \(table) WHERE id = ?1", [.text(id)]) { row -> Session? in
            guard row.isNull(2) else { return nil }
            var title = AgentDatabasePoll.nonEmpty(row.text(1))
            // `New session - <ISO date>` until a title is generated (`packages/opencode/src/session/session.ts`).
            if title?.hasPrefix("New session - ") == true { title = nil }
            return Session(label: AgentDatabasePoll.folderName(row.text(0)), title: title)
        }?.first
    }

    // MARK: 1.x

    private static func probeV1(_ db: AgentSQLiteConnection, session id: String) -> AgentSessionProbe? {
        guard let session = session(db, table: "session", id: id),
              // `message_session_time_created_id_idx (session_id, time_created, id)`.
              let latest = db.query(
                  "SELECT id, data FROM message WHERE session_id = ?1 ORDER BY time_created DESC, id DESC LIMIT 1",
                  [.text(id)], { row -> (String, [String: Any])? in
                      guard let messageID = row.text(0), let data = row.text(1),
                            let object = try? JSONSerialization.jsonObject(with: Data(data.utf8)) as? [String: Any]
                      else { return nil }
                      return (messageID, object)
                  })?.first
        else { return nil }
        let (messageID, message) = latest
        func probe(_ activity: AgentActivity, lineID: String? = nil) -> AgentSessionProbe {
            AgentSessionProbe(
                reading: AgentLogReading(activity: activity, label: session.label, lineID: lineID,
                                         title: session.title, session: id),
                progress: messageID)
        }
        switch message["role"] as? String {
        case "user":
            return probe(.working)
        case "assistant":
            if message["error"] is [String: Any] { return probe(.idle) }
            let completed = (message["time"] as? [String: Any])?["completed"] != nil
            if !completed {
                if let question = runningQuestionV1(db, message: messageID) {
                    return probe(.waiting(message: nil), lineID: question)
                }
                return probe(.working)
            }
            let finish = message["finish"] as? String
            let stepEnds = finish == nil || finish == "tool-calls" || finish == "unknown"
            if stepEnds || message["summary"] as? Bool == true || hasToolPartV1(db, message: messageID) {
                return probe(.working)
            }
            return probe(.done(message: nil), lineID: messageID)
        default:
            return nil
        }
    }

    /// `part_message_id_id_idx (message_id, id)` bounds this to one message's parts.
    private static func runningQuestionV1(_ db: AgentSQLiteConnection, message: String) -> String? {
        db.query("""
            SELECT id FROM part WHERE message_id = ?1
              AND json_extract(data, '$.type') = 'tool' AND json_extract(data, '$.tool') = 'question'
              AND json_extract(data, '$.state.status') = 'running'
            ORDER BY id DESC LIMIT 1
            """, [.text(message)]) { $0.text(0) }?.first
    }

    /// A tool the model called (not one the provider ran itself) means OpenCode sends the result
    /// back for another step, even when the provider said `stop`.
    private static func hasToolPartV1(_ db: AgentSQLiteConnection, message: String) -> Bool {
        let found = db.query("""
            SELECT 1 FROM part WHERE message_id = ?1 AND json_extract(data, '$.type') = 'tool'
              AND json_extract(data, '$.metadata.providerExecuted') IS NOT 1
            LIMIT 1
            """, [.text(message)]) { _ in true }
        // A failed check must not turn into a done.
        return found.map { !$0.isEmpty } ?? true
    }

    // MARK: 2.x

    private static func probeV2(_ db: AgentSQLiteConnection, session id: String) -> AgentSessionProbe? {
        guard let session = session(db, table: "session_v2", id: id),
              // `session_message_session_type_seq_idx (session_id, type, seq)`.
              let latest = db.query("""
                  SELECT id, type, CASE WHEN type = 'idle' THEN json_extract(data, '$.outcome') END
                  FROM session_message
                  WHERE session_id = ?1 AND type IN ('user', 'synthetic', 'assistant', 'compaction', 'idle')
                  ORDER BY seq DESC LIMIT 1
                  """, [.text(id)], { row -> (id: String, type: String, outcome: String?)? in
                      guard let messageID = row.text(0), let type = row.text(1) else { return nil }
                      return (messageID, type, row.text(2))
                  })?.first
        else { return nil }
        func probe(_ activity: AgentActivity, lineID: String? = nil) -> AgentSessionProbe {
            AgentSessionProbe(
                reading: AgentLogReading(activity: activity, label: session.label, lineID: lineID,
                                         title: session.title, session: id),
                progress: latest.id)
        }
        switch latest.type {
        case "idle":
            guard latest.outcome == "succeeded" else { return probe(.idle) }
            return busyAgainV2(db, session: id) ? probe(.working) : probe(.done(message: nil), lineID: latest.id)
        case "assistant":
            if let question = runningQuestionV2(db, message: latest.id) {
                return probe(.waiting(message: nil), lineID: question)
            }
            return probe(.working)
        default:
            return probe(.working)
        }
    }

    /// An execution started after the last idle row (its first row not written yet).
    private static func busyAgainV2(_ db: AgentSQLiteConnection, session: String) -> Bool {
        guard db.columns("session_v2").isSuperset(of: ["time_busy", "time_idle"]) else { return false }
        let busy = db.query(
            "SELECT time_busy IS NOT NULL AND (time_idle IS NULL OR time_busy >= time_idle) FROM session_v2 WHERE id = ?1",
            [.text(session)]) { $0.int64(0) == 1 }
        return busy?.first ?? true
    }

    private static func runningQuestionV2(_ db: AgentSQLiteConnection, message: String) -> String? {
        let inline = db.query("""
            SELECT json_extract(c.value, '$.id') FROM session_message AS m, json_each(m.data, '$.content') AS c
            WHERE m.id = ?1 AND json_extract(c.value, '$.type') = 'tool'
              AND json_extract(c.value, '$.name') = 'question' AND json_extract(c.value, '$.state.status') = 'running'
            LIMIT 1
            """, [.text(message)]) { $0.text(0) ?? "question" }?.first
        if let inline { return inline }
        // Newer builds move assistant content to `session_part` (primary key `message_id, ordinal`).
        guard db.tables?.contains("session_part") == true else { return nil }
        return db.query("""
            SELECT COALESCE(call_id, 'question') FROM session_part
            WHERE message_id = ?1 AND type = 'tool' AND json_extract(data, '$.name') = 'question'
              AND json_extract(data, '$.state.status') = 'running'
            LIMIT 1
            """, [.text(message)]) { $0.text(0) }?.first
    }
}
