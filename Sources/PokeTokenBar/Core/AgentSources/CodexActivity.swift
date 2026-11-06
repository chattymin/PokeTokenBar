import Foundation

extension AgentLogSource {
    /// Codex (CLI, IDE extension and app all write the same rollouts):
    /// `<codex home>/sessions/YYYY/MM/DD/rollout-<time>-<thread id>.jsonl`. Archived and compressed
    /// (`.jsonl.zst`) rollouts are cold, so they are not watched. Subagent and helper threads are
    /// marked only in the first line, so `head` skips them. A name the person gave lives in
    /// `<codex home>/session_index.jsonl`, outside the rollout.
    static func codex() -> AgentLogSource {
        AgentLogSource(
            id: "codex",
            roots: { CodexRolloutActivity.sessionRoots() },
            accepts: CodexRolloutActivity.isLiveRollout(_:),
            interpret: CodexRolloutActivity.reading(lines:),
            hooks: nil,
            head: CodexRolloutActivity.head(lines:),
            externalTitle: CodexRolloutActivity.indexTitle(rollout:))
    }
}

/// Reads Codex rollout lines. Each line is `{"timestamp",["ordinal",]"type","payload"}` written as
/// compact JSON by serde (`codex-rs/history/src/rollout_payload.rs` `RolloutItemWire`, flattened
/// into `RolloutLine` in `codex-rs/history/src/lib.rs`). What is persisted at all is decided in
/// `codex-rs/rollout/src/policy.rs`: turn start/complete/abort events always, tool calls and
/// messages as `response_item`s in both history modes, while approvals, errors and
/// `request_user_input` events are transient and never reach the file.
///
/// Only the newest line that says something about the turn matters:
/// - `event_msg` `task_started` (alias `turn_started`) or `user_message` → working.
/// - `event_msg` `task_complete` (alias `turn_complete`) → done, or idle when it carries `error`
///   (the turn failed: `TurnCompleteEvent.error`, `codex-rs/protocol/src/protocol.rs`).
/// - `event_msg` `turn_aborted`: `replaced` → working (`Session::spawn_task` aborts the running turn
///   only to start the next one, `codex-rs/core/src/tasks/mod.rs`); `interrupted`, `budget_limited`,
///   `review_ended` or anything newer → idle (the turn stopped without an answer).
/// - `response_item` `function_call` named `request_user_input` (no namespace) → waiting: the
///   blocking question tool, `REQUEST_USER_INPUT_TOOL_NAME` in
///   `codex-rs/core/src/tools/handlers/request_user_input_spec.rs`. `request_user_input_async`
///   does not block the turn, so it is working like any other tool.
/// - other tool calls and outputs, reasoning and assistant messages → working.
/// `token_count`, `turn_context`, `compacted` and the like are skipped. Rollouts from before Codex
/// persisted turn events (seen in a 0.47 rollout) never read as done. Checked against
/// openai/codex `main` at a142c90 (2026-11-06) and real rollouts of 0.118 and 0.142.
enum CodexRolloutActivity {
    /// `ARCHIVED_SESSIONS_SUBDIR` in `codex-rs/rollout/src/lib.rs`.
    static let archivedFolder = "archived_sessions"
    /// `SESSIONS_SUBDIR` in `codex-rs/rollout/src/lib.rs`.
    static let sessionsFolder = "sessions"
    /// `SESSION_INDEX_FILE` in `codex-rs/rollout/src/session_index.rs`, next to `sessions`.
    static let indexFileName = "session_index.jsonl"
    /// How much of the end of the session index is read for a title. The index is append-only and
    /// a name is one short line, so a recent rename is always within this.
    static let indexTailBytes: UInt64 = 256 * 1024

    // MARK: Files

    /// The folders the usage reader scans for Codex (plus the Settings custom roots), without the
    /// archive. `CODEX_HOME` counts once `UsageEnvironment` looks it up; until then a moved Codex
    /// home is covered by the custom roots.
    static func sessionRoots() -> [URL] {
        var roots = LocalUsageReader.codexSessionRoots(customRootsValue: CustomScanRoots.storedValue(for: "codex"))
        if let home = UsageEnvironment.value("CODEX_HOME")?.trimmingCharacters(in: .whitespacesAndNewlines),
           !home.isEmpty {
            roots.append(URL(fileURLWithPath: (home as NSString).expandingTildeInPath)
                .appendingPathComponent(sessionsFolder))
        }
        return roots.filter { $0.lastPathComponent != archivedFolder }
    }

    /// A rollout being written. Archived ones only move; compressed ones (`.jsonl.zst`,
    /// `codex-rs/rollout/src/compression.rs`) are cold by definition.
    static func isLiveRollout(_ url: URL) -> Bool {
        url.pathExtension == "jsonl" && url.lastPathComponent.hasPrefix("rollout-")
            && !url.pathComponents.contains(archivedFolder)
    }

    /// The thread id in `rollout-YYYY-MM-DDThh-mm-ss-<thread id>[_<rollout id>].jsonl`
    /// (`RolloutFileName::parse`, `codex-rs/rollout/src/rollout_file_name.rs`). A reverted thread
    /// gets a new rollout id after `_` but keeps its thread id, which is what the index uses.
    static func threadID(fileName: String) -> String? {
        guard fileName.hasPrefix("rollout-"), fileName.hasSuffix(".jsonl") else { return nil }
        let core = fileName.dropFirst("rollout-".count).dropLast(".jsonl".count)
        guard core.count > 20, core[core.index(core.startIndex, offsetBy: 19)] == "-" else { return nil }
        let ids = core.dropFirst(20)
        let thread = ids.split(separator: "_", maxSplits: 1, omittingEmptySubsequences: false).first ?? ids
        return thread.isEmpty ? nil : String(thread)
    }

    /// `<codex home>/session_index.jsonl` for a rollout under `<codex home>/sessions/…`. Found by
    /// walking up to the `sessions` folder, so any Codex home (or custom root) works. Nil for a
    /// rollout outside such a folder.
    static func indexURL(rollout url: URL) -> URL? {
        var folder = url.deletingLastPathComponent()
        for _ in 0..<5 {
            if folder.lastPathComponent == sessionsFolder {
                return folder.deletingLastPathComponent().appendingPathComponent(indexFileName)
            }
            let parent = folder.deletingLastPathComponent()
            if parent.path == folder.path { return nil }
            folder = parent
        }
        return nil
    }

    // MARK: Lines

    /// What the newest lines say about the turn. Nil when they say nothing new.
    static func reading(lines: [Substring]) -> AgentLogReading? {
        let label = label(lines: lines)
        for line in lines.reversed() {
            // Cheap filter before parsing: tool outputs are large and most lines are token counts or
            // tool items. serde writes compact JSON, and a nested (escaped) copy cannot match.
            let event = line.contains(#""type":"event_msg""#)
            guard event ? eventMarkers.contains(where: { line.contains($0) }) : line.contains(#""type":"response_item""#),
                  let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let payload = object["payload"] as? [String: Any],
                  let kind = payload["type"] as? String
            else { continue }
            func reading(_ activity: AgentActivity, id: Any?) -> AgentLogReading {
                AgentLogReading(activity: activity, label: label,
                                lineID: nonEmpty(id) ?? (object["timestamp"] as? String))
            }
            switch object["type"] as? String {
            case "event_msg":
                switch kind {
                case "task_started", "turn_started":
                    return reading(.working, id: payload["turn_id"])
                case "user_message":
                    return reading(.working, id: nil)
                case "task_complete", "turn_complete":
                    let failed = payload["error"] is [String: Any]
                    return reading(failed ? .idle : .done(message: nil), id: payload["turn_id"])
                case "turn_aborted":
                    let replaced = payload["reason"] as? String == "replaced"
                    return reading(replaced ? .working : .idle, id: payload["turn_id"])
                default:
                    continue
                }
            case "response_item":
                if kind == "function_call", payload["name"] as? String == "request_user_input",
                   nonEmpty(payload["namespace"]) == nil {
                    return reading(.waiting(message: nil), id: payload["call_id"])
                }
                if workingItems.contains(kind) || (kind == "message" && payload["role"] as? String == "assistant") {
                    return reading(.working, id: nil)
                }
                continue
            default:
                continue
            }
        }
        return nil
    }

    /// `event_msg` payload types that decide the turn; every other event (mostly `token_count`) is
    /// skipped without parsing.
    private static let eventMarkers = ["task_started", "turn_started", "user_message", "task_complete",
                                       "turn_complete", "turn_aborted"].map { #""type":""# + $0 + #"""# }

    /// `response_item` payload types that only happen inside a running turn (`ResponseItem`,
    /// `codex-rs/protocol/src/models.rs`).
    private static let workingItems: Set = [
        "function_call", "function_call_output", "custom_tool_call", "custom_tool_call_output",
        "local_shell_call", "web_search_call", "tool_search_call", "tool_search_output",
        "image_generation_call", "reasoning",
    ]

    /// The working folder of the newest `turn_context` (written every turn, `TurnContextItem.cwd`).
    /// Nil when the lines hold none; the watcher then uses the head's.
    static func label(lines: [Substring]) -> String? {
        for line in lines.reversed() where line.contains(#""type":"turn_context""#) {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  object["type"] as? String == "turn_context",
                  let payload = object["payload"] as? [String: Any],
                  let cwd = nonEmpty(payload["cwd"])
            else { continue }
            return URL(fileURLWithPath: cwd).lastPathComponent
        }
        return nil
    }

    /// The first line is `session_meta` (`SessionMeta`, `codex-rs/protocol/src/protocol.rs`): its
    /// `cwd` is the label when no `turn_context` is in reach, and its `source` / `thread_source`
    /// mark threads the person did not start. The usage reader (`LocalUsageReader.codexSessionMeta`)
    /// counts `thread_source` `subagent` or a `source.subagent`; helpers that run on their own
    /// (`source.internal`: memory consolidation, guardian review, and the matching
    /// `thread_source`s) are not the person's turns either.
    static func head(lines: [Substring]) -> AgentLogHead {
        for line in lines where line.contains(#""type":"session_meta""#) {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  object["type"] as? String == "session_meta",
                  let payload = object["payload"] as? [String: Any]
            else { continue }
            let label = nonEmpty(payload["cwd"]).map { URL(fileURLWithPath: $0).lastPathComponent }
            let source = payload["source"] as? [String: Any]
            let helper = source?["subagent"] != nil || source?["internal"] != nil
                || (payload["thread_source"] as? String).map(helperThreadSources.contains) == true
            return AgentLogHead(label: label, skip: helper)
        }
        return AgentLogHead()
    }

    /// `ThreadSource::as_str` values of threads nobody typed into.
    private static let helperThreadSources: Set = ["subagent", "guardian_review", "memory_consolidation"]

    // MARK: Titles

    /// The name the person gave the rollout's thread (`/rename`, or renaming it in the app), from the
    /// session index. Generated titles exist only in `state_N.sqlite`, so they are not read.
    static func indexTitle(rollout url: URL) -> AgentSessionTitle {
        guard let id = threadID(fileName: url.lastPathComponent),
              let index = indexURL(rollout: url),
              let lines = tailLines(of: index)
        else { return AgentSessionTitle() }
        return AgentSessionTitle(named: indexedName(threadID: id, lines: lines), generated: nil)
    }

    /// Index lines are `{"id","thread_name","updated_at"}` and only ever appended; the newest
    /// non-blank name for the id wins, as in `find_thread_names_by_ids`
    /// (`codex-rs/rollout/src/session_index.rs`).
    static func indexedName(threadID: String, lines: [Substring]) -> String? {
        for line in lines.reversed() where line.contains(threadID) {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  object["id"] as? String == threadID,
                  let name = nonEmpty(object["thread_name"])
            else { continue }
            return name
        }
        return nil
    }

    /// Complete lines in the last `indexTailBytes` of `url`.
    private static func tailLines(of url: URL) -> [Substring]? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        let start = size > indexTailBytes ? size - indexTailBytes : 0
        guard (try? handle.seek(toOffset: start)) != nil,
              let data = try? handle.readToEnd()
        else { return nil }
        let lines = AgentLogTail.completeLines(data, dropsFirstLine: start > 0).lines
        return lines.isEmpty ? nil : lines
    }

    private static func nonEmpty(_ value: Any?) -> String? {
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty
        else { return nil }
        return text
    }
}
