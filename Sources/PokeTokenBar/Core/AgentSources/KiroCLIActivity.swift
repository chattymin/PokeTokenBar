import Foundation

extension AgentLogSource {
    /// Kiro CLI, both log layouts under `~/.kiro/sessions` (`$KIRO_HOME/sessions`):
    /// - v3 (2.20+, `--v3`): `<workspace hash>/<session id>/messages.jsonl` beside `session.json`.
    /// - classic 2.x: `cli/<session id>.jsonl` beside `cli/<session id>.json`.
    /// The older SQLite store under `kiro-cli` is not followed (it rewrites whole conversations).
    ///
    /// v3 reports working, waiting, done and idle; classic reports working and idle only (it has no
    /// turn end). See `KiroCLIActivity`.
    static func kiroCLI() -> AgentLogSource {
        AgentLogSource(
            id: "kiro",
            roots: { LocalAdditionalUsageReader.kiroRoots(customRootsValue: CustomScanRoots.storedValue(for: "kiro")) },
            accepts: KiroCLIActivity.accepts(_:),
            interpret: KiroCLIActivity.reading(lines:),
            hooks: nil,
            turns: KiroCLIActivity.turns(lines:from:),
            externalTitle: KiroCLIActivity.externalTitle(forLog:),
            pathLabel: KiroCLIActivity.label(forLog:))
    }
}

/// Reads Kiro CLI session logs. Kiro is closed source; the shapes come from the app's usage reader
/// (`LocalAdditionalUsageReader.kiroV3JSONLEntries` / `kiroCLIJSONLEntries`, `KiroUsageTests`,
/// `KiroContentBlockTests` — CLI 2.25.0 writer output) and from lpaiu-cs/osk-system
/// `_governance/_engine/osk/transcripts.py` (`_kiro`, checked against real transcripts, 2026-10).
///
/// **v3** lines are `{id, timestamp, payload: {type, …}}`. A request is one `turn_start` …
/// `turn_end` pair sharing an `executionId`, opened by the `user` lines before it; one turn spans
/// several model requests (`usage_summary.requestIds`). So:
/// - `user`, `turn_start`, `assistant`, `tool_call`, `tool_result`, `sub_agent_*`,
///   `interaction_resolved` → working.
/// - `pending_interaction` → waiting: a tool approval is up.
/// - `turn_end` with `stopReason` `end_turn` → done. Any other reason (`cancelled`, `error`,
///   `content_filtered`, or none) → idle.
/// - `assistant` lines with `operationType` `Summary` are compaction, outside any turn: skipped.
///   So are `usage_summary` and `session_metadata`.
///
/// **Classic** lines are `{version, kind, data}` with kinds `Prompt`, `AssistantMessage`,
/// `ToolResults` and `Clear`. A reply carries its tool requests as `toolUse` content blocks, and
/// their results follow as `ToolResults`. So a reply without `toolUse` blocks is the end of the
/// agent loop — reported as **idle**, not done: no line confirms the turn ended (the companion
/// `<id>.json` records turn ends, but it is rewritten in place, which the watcher cannot follow).
/// `Clear` → idle; everything else → working.
enum KiroCLIActivity {
    static func accepts(_ url: URL) -> Bool {
        isV3(url) || isClassic(url)
    }

    static func reading(lines: [Substring]) -> AgentLogReading? {
        for line in lines.reversed() {
            if let reading = v3Reading(line) ?? classicReading(line) {
                return reading
            }
        }
        return nil
    }

    /// A v3 turn is automatic when no `user` line came before its `turn_start` (osk-system keeps
    /// such turns as "inputless"). `user` lines queued while a turn runs open the next one.
    ///
    /// `open` here means "a person's line is waiting for the next `turn_start`". It starts true, so
    /// a tail read first that begins mid-turn counts as the person's. Classic logs have no turn
    /// lines and never mark a turn automatic.
    static func turns(lines: [Substring], from start: AgentTurnState) -> AgentTurnState {
        var state = start
        for line in lines where line.contains(#""payload""#) {
            switch payload(line)?.type {
            case "user":
                state.open = true
            case "turn_start":
                state = AgentTurnState(open: false, automatic: !state.open)
            default:
                continue
            }
        }
        return state
    }

    /// v3: `title` in `session.json` (Kiro writes it from the conversation; tokscale
    /// `crates/tokscale-core/src/sessions/kiro.rs`, issue #813 sample). Classic logs keep no title.
    static func externalTitle(forLog url: URL) -> AgentSessionTitle {
        guard isV3(url), let session = companion(forLog: url) else { return AgentSessionTitle() }
        return AgentSessionTitle(named: nil, generated: nonEmpty(session["title"]))
    }

    /// The working folder: v3 `session.json` `workspacePaths[0]` (tokscale `KiroIdeSession`),
    /// classic `<id>.json` `cwd` (the app's `kiroCLIJSONLEntries` fixtures). Neither log line names it.
    static func label(forLog url: URL) -> String? {
        label(companion: companion(forLog: url), v3: isV3(url))
    }

    static func label(companion: [String: Any]?, v3: Bool) -> String? {
        let path = v3 ? (companion?["workspacePaths"] as? [String])?.first : companion?["cwd"] as? String
        guard let path = path?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else { return nil }
        let name = URL(fileURLWithPath: path).lastPathComponent
        return name.isEmpty || name == "/" ? nil : name
    }

    // MARK: v3

    private static func isV3(_ url: URL) -> Bool {
        url.lastPathComponent == "messages.jsonl"
    }

    private static func v3Reading(_ line: Substring) -> AgentLogReading? {
        guard line.contains(#""payload""#), let (type, payload, id) = payload(line) else { return nil }
        func reading(_ activity: AgentActivity) -> AgentLogReading {
            AgentLogReading(activity: activity, label: nil, lineID: id ?? payload["executionId"] as? String)
        }
        switch type {
        case "user", "turn_start", "tool_call", "tool_result", "sub_agent_start", "sub_agent_complete",
             "interaction_resolved":
            return reading(.working)
        case "assistant":
            return payload["operationType"] as? String == "Summary" ? nil : reading(.working)
        case "pending_interaction":
            return reading(.waiting(message: nil))
        case "turn_end":
            return reading(payload["stopReason"] as? String == "end_turn" ? .done(message: nil) : .idle)
        default:
            return nil
        }
    }

    private static func payload(_ line: Substring) -> (type: String, payload: [String: Any], id: String?)? {
        guard let object = jsonObject(line),
              let payload = object["payload"] as? [String: Any],
              let type = payload["type"] as? String
        else { return nil }
        return (type, payload, object["id"] as? String)
    }

    // MARK: Classic

    private static func isClassic(_ url: URL) -> Bool {
        url.pathExtension == "jsonl" && url.deletingLastPathComponent().lastPathComponent == "cli"
    }

    private static func classicReading(_ line: Substring) -> AgentLogReading? {
        guard line.contains(#""kind""#), let object = jsonObject(line),
              object["payload"] == nil, let kind = object["kind"] as? String
        else { return nil }
        let data = object["data"] as? [String: Any]
        let lineID = data?["message_id"] as? String
        switch kind {
        case "Prompt", "ToolResults":
            return AgentLogReading(activity: .working, label: nil, lineID: lineID)
        case "AssistantMessage":
            let blocks = data?["content"] as? [[String: Any]] ?? []
            let asksForTools = blocks.contains { $0["kind"] as? String == "toolUse" }
            return AgentLogReading(activity: asksForTools ? .working : .idle, label: nil, lineID: lineID)
        case "Clear":
            return AgentLogReading(activity: .idle, label: nil, lineID: lineID)
        default:
            return nil
        }
    }

    // MARK: Files

    /// `session.json` beside a v3 log, `<id>.json` beside a classic one. Bounded: the classic
    /// companion also holds per-turn metadata, and this is read on every reading.
    private static func companion(forLog url: URL) -> [String: Any]? {
        let file = isV3(url)
            ? url.deletingLastPathComponent().appendingPathComponent("session.json")
            : url.deletingPathExtension().appendingPathExtension("json")
        guard let size = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.size] as? UInt64,
              size <= maxCompanionBytes,
              let data = FileManager.default.contents(atPath: file.path)
        else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    static let maxCompanionBytes: UInt64 = 1024 * 1024

    private static func jsonObject(_ line: Substring) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
    }

    private static func nonEmpty(_ value: Any?) -> String? {
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty
        else { return nil }
        return text
    }
}
