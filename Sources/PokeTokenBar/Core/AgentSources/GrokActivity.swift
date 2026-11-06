import Foundation

extension AgentLogSource {
    /// Grok Build CLI: `$GROK_HOME|~/.grok/sessions/<percent-encoded cwd>/<session uuid>/updates.jsonl`,
    /// with `summary.json` next to it. Subagent sessions live beside the person's sessions and are
    /// told apart only by `summary.json` `session_kind`, so `accepts` reads that small file (the
    /// usage reader's own check). Grok has no hooks the app can add.
    static func grok() -> AgentLogSource {
        AgentLogSource(
            id: "grok",
            roots: { LocalUsageReader.grokSessionRoots(customRootsValue: CustomScanRoots.storedValue(for: "grok")) },
            accepts: { LocalUsageReader.isGrokUsageFile($0) },
            interpret: GrokActivity.reading(lines:),
            hooks: nil,
            turns: GrokActivity.turns(lines:from:),
            externalTitle: { GrokActivity.title(summary: $0.deletingLastPathComponent().appendingPathComponent("summary.json")) },
            pathLabel: GrokActivity.label(updatesFile:))
    }
}

/// Reads Grok Build CLI's `updates.jsonl`. Each line is one session update in an envelope:
/// `{"timestamp":…,"method":"_x.ai/session/update","params":{"sessionId":…,"update":{"sessionUpdate":…},"_meta":{…}}}`
/// (older lines carry the notification without the envelope). Only the newest line that says
/// something about the turn matters:
/// - `turn_completed` (`session/turn_completion.rs`, the durable twin of `prompt_complete`): its
///   `stop_reason` is an ACP stop reason (`end_turn`, `max_tokens`, `max_turn_requests`, `refusal`,
///   `cancelled`) or, for a failed turn, `error` / `rate_limit` (`sampling/error.rs`
///   `prompt_complete_fields`). A turn that returned normally is done; `cancelled` (Esc, also
///   written by `acp_session_impl/cancel.rs`) and a failure are idle.
/// - `user_message_chunk` (the prompt echo, `acp_session_impl/turn.rs`), `agent_message_chunk`,
///   `agent_thought_chunk`, `tool_call`, `tool_call_update` and `plan` → working.
/// Bookkeeping updates written around a turn (summaries, memory, background tasks, model
/// changes, compaction markers) are skipped, so they cannot turn a done back into working.
/// Grok writes no record of waiting for the person: `PendingInteraction` (permission,
/// `ask_user_question`, plan approval) is "never persisted" (`extensions/notification.rs`).
/// Checked against xai-org/grok-build `main` (2026-11); the CLI was not run locally.
enum GrokActivity {
    /// `summary.json` is small; a larger one is broken (e.g. a failed write) and is not read.
    static let maxSummaryBytes: UInt64 = 1024 * 1024

    private static func boundedData(_ file: URL) -> Data? {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.size] as? UInt64,
              size <= maxSummaryBytes
        else { return nil }
        return try? Data(contentsOf: file)
    }

    /// Streaming text arrives one chunk per line (tens of thousands per session), so lines are
    /// matched as text before parsing. serde writes compact JSON, and an escaped copy inside a
    /// string (`\"sessionUpdate\":\"…`) cannot match these.
    private static let completedTag = #""sessionUpdate":"turn_completed""#
    private static let userTag = #""sessionUpdate":"user_message_chunk""#
    private static let workingTags = [
        userTag,
        #""sessionUpdate":"agent_message_chunk""#,
        #""sessionUpdate":"agent_thought_chunk""#,
        #""sessionUpdate":"tool_call""#,
        #""sessionUpdate":"tool_call_update""#,
        #""sessionUpdate":"plan""#,
    ]
    private static let workingKinds: Set<String> = [
        "user_message_chunk", "agent_message_chunk", "agent_thought_chunk", "tool_call", "tool_call_update", "plan",
    ]

    /// Stop reasons of a turn that ran to its end; the rest (`cancelled`, `error`, `rate_limit`, or
    /// one this list does not know yet) leave nothing to look at.
    private static let finishedReasons: Set<String> = ["end_turn", "max_tokens", "max_turn_requests", "refusal"]

    static func reading(lines: [Substring]) -> AgentLogReading? {
        for line in lines.reversed() {
            let completed = line.contains(completedTag)
            guard completed || workingTags.contains(where: { line.contains($0) }),
                  let update = update(in: line)
            else { continue }
            let kind = update.fields["sessionUpdate"] as? String
            if kind == "turn_completed" {
                let reason = update.fields["stop_reason"] as? String
                let lineID = nonEmpty(update.fields["prompt_id"]) ?? nonEmpty(update.meta?["eventId"])
                return AgentLogReading(activity: reason.map(finishedReasons.contains) == true ? .done(message: nil) : .idle,
                                       label: nil, lineID: lineID)
            }
            if let kind, workingKinds.contains(kind) { return AgentLogReading(activity: .working, label: nil, lineID: nil) }
        }
        return nil
    }

    /// A turn starts with the prompt echo after the previous turn ended, and ends with
    /// `turn_completed`. Grok starts turns of its own (a background task or subagent finished, a
    /// scheduled task fired, a message from another session, goal-mode nudges) and names them by a
    /// `prompt_id` prefix (`session/mod.rs` `PromptOrigin::from_prompt_id`). Their end is not news,
    /// except `plan-resume-`: the person just approved a plan and waits for it. The prompt echo
    /// carries no prompt id, so the turn is marked when it ends, in the same batch as its done.
    static func turns(lines: [Substring], from start: AgentTurnState) -> AgentTurnState {
        var state = start
        for line in lines {
            let completed = line.contains(completedTag)
            guard completed || (!state.open && line.contains(userTag)),
                  let update = update(in: line)
            else { continue }
            switch update.fields["sessionUpdate"] as? String {
            case "turn_completed":
                let promptID = update.fields["prompt_id"] as? String ?? ""
                state = AgentTurnState(open: false, automatic: isAutomatic(promptID: promptID))
            case "user_message_chunk":
                state = AgentTurnState(open: true, automatic: false)
            default:
                continue
            }
        }
        return state
    }

    /// `PromptOrigin` prefixes for turns nobody typed (`session/mod.rs`).
    private static let automaticPrefixes = [
        "task-completed-", "subagent-completed-", "parent-agent-message-", "parent-message-",
        "workflow-completed-", "notifications-", "goal-summary-", "goal-classifier-nudge-", "scheduler-fired-",
    ]

    static func isAutomatic(promptID: String) -> Bool {
        automaticPrefixes.contains { promptID.hasPrefix($0) }
    }

    /// The session's name from `summary.json` (written whole, under a lock). `generated_title` is
    /// the person's `/rename` when `title_is_manual`, else the title Grok wrote; the CLI shows
    /// `session_summary` when there is none (`session/persistence.rs` `display_title`,
    /// `manual_title_opt`). Unreadable (missing, or caught mid-write): no title, so the one
    /// already known stays.
    static func title(summary file: URL) -> AgentSessionTitle {
        guard let data = boundedData(file),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return AgentSessionTitle() }
        let title = nonEmpty(object["generated_title"])
        if object["title_is_manual"] as? Bool == true, let title { return AgentSessionTitle(named: title, generated: nil) }
        return AgentSessionTitle(named: nil, generated: title ?? nonEmpty(object["session_summary"]))
    }

    /// The working folder's name. The folder above the session is the cwd, percent-encoded
    /// (`xai-grok-config/src/paths.rs` `encode_cwd_dirname`); a cwd too long for a folder name is
    /// stored as `<slug>-<hash>` with the real path in a `.cwd` file there. `summary.json`
    /// `info.cwd` is the last resort.
    static func label(updatesFile: URL) -> String? {
        let sessionFolder = updatesFile.deletingLastPathComponent()
        let cwdFolder = sessionFolder.deletingLastPathComponent()
        if let label = label(cwdFolderName: cwdFolder.lastPathComponent) { return label }
        if let text = try? String(contentsOf: cwdFolder.appendingPathComponent(".cwd"), encoding: .utf8),
           let label = folderName(text) {
            return label
        }
        guard let data = boundedData(sessionFolder.appendingPathComponent("summary.json")),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cwd = (object["info"] as? [String: Any])?["cwd"] as? String
        else { return nil }
        return folderName(cwd)
    }

    /// Nil for the hashed form, which never decodes to an absolute path (the CLI's own test).
    static func label(cwdFolderName name: String) -> String? {
        guard let cwd = name.removingPercentEncoding, cwd.hasPrefix("/") else { return nil }
        return folderName(cwd)
    }

    private static func folderName(_ path: String) -> String? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else { return nil }
        let name = URL(fileURLWithPath: trimmed).lastPathComponent
        return name.isEmpty || name == "/" ? nil : name
    }

    /// The update object and the notification's `_meta`, from either line shape. Nil for a replayed
    /// copy of an older update (`_meta.isReplay`), which says nothing about now.
    private static func update(in line: Substring) -> (fields: [String: Any], meta: [String: Any]?)? {
        guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { return nil }
        let notification = object["params"] as? [String: Any] ?? object
        guard let update = notification["update"] as? [String: Any] else { return nil }
        let meta = notification["_meta"] as? [String: Any]
        if meta?["isReplay"] as? Bool == true { return nil }
        return (update, meta)
    }

    private static func nonEmpty(_ value: Any?) -> String? {
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty
        else { return nil }
        return text
    }
}
