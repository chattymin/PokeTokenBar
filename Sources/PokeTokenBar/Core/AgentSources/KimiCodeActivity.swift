import Foundation

extension AgentLogSource {
    /// Kimi Code (CLI and the Kimi desktop runtime):
    /// `<sessions root>/<workspaceId>/<sessionId>/agents/main/wire.jsonl`. Subagents write their own
    /// `agents/agent-N/wire.jsonl`; their turns ending is not the session ending, so only `main` is
    /// read. The title and the working folder live in `<sessionId>/state.json`, not in the wire.
    static func kimiCode() -> AgentLogSource {
        AgentLogSource(
            id: "kimi_code",
            roots: { LocalUsageReader.kimiSessionRoots },
            accepts: KimiCodeActivity.isMainWire,
            interpret: KimiCodeActivity.reading(lines:),
            hooks: nil,
            turns: KimiCodeActivity.turns(lines:from:),
            externalTitle: { KimiCodeActivity.title(state: KimiCodeActivity.state(wire: $0)) },
            pathLabel: KimiCodeActivity.label(wire:))
    }
}

/// Reads Kimi Code's wire journal (one compact JSON record per line, `{"type", …payload, "time"}`;
/// upstream `MoonshotAI/kimi-code` `packages/agent-core-v2/docs/wire-manifest.d.ts`). Only the
/// newest record that says something about the turn matters:
/// - `turn.ended` `completed` → done; `cancelled`, `failed`, `blocked` → idle. Every turn ends with
///   one (`src/agent/loop/loopService.ts` `endTurn`).
/// - `turn.cancel` for the active turn (Esc) → idle, a moment before its `turn.ended`. A cancel of a
///   queued prompt (`target` `queued`) leaves the running turn alone.
/// - `interaction.request` of kind `approval` or `question` → waiting. `user_tool` is a tool the
///   client runs, not a question to the person → working.
/// - `interaction.resolved` → working, unless it is the cancellation a turn's end sends to its open
///   requests (`src/agent/interaction/interactionWiring.ts`, `{cancelled: true}`).
/// - `turn.prompt`, `turn.steer`, `turn.step.retrying` and loop events (`step.begin`, `tool.call`,
///   `tool.result`, …) → working.
/// - `forked` (appended at the end of a `/fork` copy) → idle: the copied history is not news.
/// Skipped: `context.append_message` (also written for prompts a hook blocks, which start no turn),
/// `prompt.*` (they repeat the turn's end, and `prompt.aborted` also fires for a queued prompt while
/// another turn runs), `llm.request` (manual compaction runs outside turns), bookkeeping records.
/// Checked against upstream source at d37c9d2 (2026-11-06); Kimi Code is not installed here.
enum KimiCodeActivity {
    /// `agents/main/wire.jsonl` (`docs/en/configuration/data-locations.md`).
    static func isMainWire(_ url: URL) -> Bool {
        let parts = url.pathComponents
        guard parts.count >= 3 else { return false }
        return parts[parts.count - 1] == "wire.jsonl" && parts[parts.count - 2] == "main"
            && parts[parts.count - 3] == "agents"
    }

    static func reading(lines: [Substring]) -> AgentLogReading? {
        for line in lines.reversed() {
            guard let type = recordType(line) else { continue }
            switch type {
            case "turn.prompt", "turn.steer", "turn.step.retrying", "context.append_loop_event":
                return AgentLogReading(activity: .working)
            case "turn.ended":
                guard let record = object(line) else { continue }
                switch record["reason"] as? String {
                case "completed":
                    let id = "turn.ended:" + text(record["turnId"]) + ":" + text(record["time"])
                    return AgentLogReading(activity: .done(message: nil), lineID: id)
                case "cancelled", "failed", "blocked":
                    return AgentLogReading(activity: .idle)
                default:
                    continue
                }
            case "turn.cancel":
                guard let record = object(line), record["target"] as? String != "queued" else { continue }
                return AgentLogReading(activity: .idle)
            case "interaction.request":
                guard let record = object(line) else { continue }
                let kind = record["kind"] as? String
                guard kind == "approval" || kind == "question" else { return AgentLogReading(activity: .working) }
                return AgentLogReading(activity: .waiting(message: nil), lineID: "interaction:" + text(record["id"]))
            case "interaction.resolved":
                guard let record = object(line) else { continue }
                if (record["response"] as? [String: Any])?["cancelled"] as? Bool == true { continue }
                return AgentLogReading(activity: .working)
            case "forked":
                return AgentLogReading(activity: .idle)
            default:
                continue
            }
        }
        return nil
    }

    /// Every turn opens with one `turn.prompt` (`loopService.ts`) and closes with one `turn.ended`.
    /// The prompt's `origin.kind` says who asked (`src/agent/contextMemory/types.ts` `PromptOrigin`).
    static func turns(lines: [Substring], from start: AgentTurnState) -> AgentTurnState {
        var state = start
        for line in lines {
            switch recordType(line) {
            case "turn.prompt":
                guard let record = object(line) else { continue }
                state = AgentTurnState(open: true, automatic: isAutomatic(origin: record["origin"]))
            case "turn.ended", "forked":
                state.open = false
            default:
                continue
            }
        }
        return state
    }

    /// Turns nobody at the keyboard asked for: background task and cron notifications, messages
    /// injected from other sessions (`injection`, e.g. the tower inbox), hook results, compaction,
    /// and system triggers. A goal's continuation turns (`system_trigger` `goal_continuation`) carry
    /// on with what the person asked, so they count as the person's. `user`, slash commands, `!`
    /// shell commands, retries and kinds this code does not know are the person's too: better one
    /// bubble too many than a missed answer.
    static func isAutomatic(origin: Any?) -> Bool {
        let object = origin as? [String: Any]
        // The manifest sketches `origin` as a bare kind; the runtime writes `{"kind": …}`.
        switch object?["kind"] as? String ?? origin as? String {
        case "task", "cron_job", "cron_missed", "injection", "hook_result", "compaction_summary":
            return true
        case "system_trigger":
            return object?["name"] as? String != "goal_continuation"
        default:
            return false
        }
    }

    /// The session's `state.json` (`src/session/sessionMetadata/sessionMetadataService.ts`): `title`
    /// with `titleKind` `custom` (`/rename`), `generated`, or `replaceable` (taken from the first
    /// prompt). Older files mark a custom title with `isCustomTitle`. "New Session" is no title.
    static func title(state: [String: Any]?) -> AgentSessionTitle {
        guard let state, let title = nonEmpty(state["title"]), title != "New Session" else { return AgentSessionTitle() }
        let kind = state["titleKind"] as? String
        let custom = kind == "custom" || (kind == nil && state["isCustomTitle"] as? Bool == true)
        return custom ? AgentSessionTitle(named: title, generated: nil) : AgentSessionTitle(named: nil, generated: title)
    }

    /// The working folder's name: `state.json` `cwd`, else the slug in the implicit workspace folder
    /// name `wd_<slug>_<sha256 prefix>` (`src/_base/utils/workdir-slug.ts`; lower-cased and cut to
    /// 40 characters). A managed workspace (`wm_<uuid>`) names no folder.
    static func label(wire url: URL) -> String? {
        let session = sessionFolder(wire: url)
        if let cwd = nonEmpty(state(session: session)?["cwd"]) {
            let name = URL(fileURLWithPath: cwd).lastPathComponent
            if !name.isEmpty, name != "/" { return name }
        }
        return workspaceSlug(session.deletingLastPathComponent().lastPathComponent)
    }

    static func workspaceSlug(_ folder: String) -> String? {
        guard folder.hasPrefix("wd_") else { return nil }
        let body = folder.dropFirst(3)
        guard let separator = body.lastIndex(of: "_") else { return nil }
        let hash = body[body.index(after: separator)...]
        let slug = body[..<separator]
        guard hash.count == 12, hash.allSatisfy(\.isHexDigit), !slug.isEmpty else { return nil }
        return String(slug)
    }

    static func state(wire url: URL) -> [String: Any]? {
        state(session: sessionFolder(wire: url))
    }

    /// `state.json` is a few KB; anything far larger is not the file this expects.
    static let maxStateBytes = 1024 * 1024

    private static func state(session: URL) -> [String: Any]? {
        let file = session.appendingPathComponent("state.json")
        guard let size = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.size] as? Int,
              size <= maxStateBytes,
              let data = try? Data(contentsOf: file)
        else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// `<session>/agents/main/wire.jsonl` → `<session>`.
    private static func sessionFolder(wire url: URL) -> URL {
        url.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private static let typePrefix = #"{"type":""#
    /// Records this reader acts on; other lines are never parsed.
    private static let knownTypes: Set<String> = [
        "turn.prompt", "turn.steer", "turn.step.retrying", "turn.ended", "turn.cancel",
        "context.append_loop_event", "interaction.request", "interaction.resolved", "forked",
    ]

    /// The record's top-level `type`. Upstream writes it as the first key (`src/app/event/event2.ts`
    /// `serialize`, `JSON.stringify` per line in `persistence/backends/node-fs/appendLogStore.ts`),
    /// so it is read from the prefix without parsing: loop events carry tool output and can be
    /// large. A line in another key order is parsed only when it names a known type; an escaped copy
    /// inside a string (`\"type\":\"…\"`) never matches.
    static func recordType(_ line: Substring) -> String? {
        if line.hasPrefix(typePrefix) {
            let rest = line.dropFirst(typePrefix.count)
            guard let end = rest.firstIndex(of: "\"") else { return nil }
            let type = String(rest[..<end])
            return knownTypes.contains(type) ? type : nil
        }
        guard knownTypes.contains(where: { line.contains(#""type":""# + $0 + "\"") }),
              let type = object(line)?["type"] as? String, knownTypes.contains(type)
        else { return nil }
        return type
    }

    private static func object(_ line: Substring) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
    }

    private static func text(_ value: Any?) -> String {
        switch value {
        case let string as String: string
        case let number as NSNumber: number.stringValue
        default: ""
        }
    }

    private static func nonEmpty(_ value: Any?) -> String? {
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty
        else { return nil }
        return text
    }
}
