import Foundation

extension AgentLogSource {
    /// GitHub Copilot CLI: `~/.copilot/session-state/<session id>/events.jsonl` (`$COPILOT_HOME`
    /// moves `~/.copilot`). Subagents write into the same file, marked per event.
    ///
    /// Reports working, waiting (a permission prompt) and idle, never done: see `CopilotCLIActivity`.
    static func copilotCLI() -> AgentLogSource {
        AgentLogSource(
            id: "copilot",
            roots: { LocalAdditionalUsageReader.copilotRoots(customRootsValue: CustomScanRoots.storedValue(for: "copilot")) },
            accepts: CopilotCLIActivity.accepts(_:),
            interpret: CopilotCLIActivity.reading(lines:),
            hooks: AgentHookFile.copilotCLI.integration,
            head: CopilotCLIActivity.head(lines:),
            externalTitle: CopilotCLIActivity.externalTitle(forLog:))
    }
}

/// Reads Copilot CLI session event logs. The CLI is closed source; the event schema is the
/// generated one in github/copilot-sdk `nodejs/src/generated/session-events.ts` (checked at main
/// c74ef96, 2026-11-05) and `docs/features/{agent-loop,streaming-events}.md`. Each line is an
/// envelope `{id, timestamp, parentId, type, data, agentId?}`. Events typed `ephemeral: true`
/// (`session.idle`, `assistant.idle`, `user_input.requested`, deltas, …) are never written to disk.
///
/// What the newest event says:
/// - `user.message`, `assistant.turn_start`, `assistant.message`, `tool.execution_*`,
///   `subagent.*`, `permission.completed`, `human_response.recorded` → working.
/// - `permission.requested` → waiting. It is flushed while the prompt is on screen (epilande/ccmux
///   `docs/agent-adapters.md`, verified live on Copilot CLI 1.0.71). Requests settled without the
///   person are not: one a hook resolved (`resolvedByHook`), any in `allow-all` mode, and one the
///   assisted-approval judge already recommended approving.
/// - `assistant.turn_end` of a main-agent turn whose reply asked for no tools → idle (see below).
/// - `abort`, `session.error`, `session.shutdown` → idle.
///
/// Deliberately not inferred:
/// - **done.** `assistant.turn_end` closes one model call, not the request: "Each iteration of this
///   loop is exactly one LLM API call, visible as one `assistant.turn_start` / `assistant.turn_end`
///   pair" (`agent-loop.md`). The request ends with `session.idle`, which is ephemeral. A reply
///   without tool requests usually ends the loop, but not always: Autopilot injects a nudge and
///   continues, a queued message starts the next run, and background agents can wake the session
///   again. That end is therefore reported as idle, which never calls the person.
/// - **questions** (`ask_user`). The request event is ephemeral; only the answer is written.
/// - `session.task_complete`: the model may call it before its last reply.
enum CopilotCLIActivity {
    static func accepts(_ url: URL) -> Bool {
        url.lastPathComponent == "events.jsonl"
            && url.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent == "session-state"
    }

    static func reading(lines: [Substring]) -> AgentLogReading? {
        // The newest meaningful event decides; a turn end looks back at the replies of its turn.
        // Only events whose payload matters are parsed: tool results can be large.
        for index in lines.indices.reversed() {
            guard let type = eventType(lines[index]) else { continue }
            func reading(_ activity: AgentActivity, _ event: Event? = nil) -> AgentLogReading {
                AgentLogReading(activity: activity, label: label(in: lines[...index]), lineID: event?.id)
            }
            switch type {
            case "user.message", "assistant.turn_start", "assistant.message", "assistant.reasoning",
                 "tool.execution_start", "tool.execution_complete", "tool.user_requested",
                 "subagent.started", "subagent.completed", "subagent.failed",
                 "permission.completed", "human_response.recorded":
                return reading(.working)
            case "permission.requested":
                guard let event = Event(lines[index]), !settledWithoutPerson(event.data) else { continue }
                return reading(.waiting(message: nil), event)
            case "assistant.turn_end":
                guard let event = Event(lines[index]), !event.isSubagent else { continue }
                return reading(endedWithoutTools(event, before: index, in: lines) ? .idle : .working, event)
            case "abort", "session.error", "session.shutdown":
                return reading(.idle, Event(lines[index]))
            default:
                continue
            }
        }
        return nil
    }

    /// `session.start` is the first line, beyond the tail of a long session.
    static func head(lines: [Substring]) -> AgentLogHead {
        AgentLogHead(label: label(in: lines[...]))
    }

    /// `name:` in `workspace.yaml` next to the log, which Copilot writes on `/rename`
    /// (jazzyalex/agent-sessions `CopilotSessionParser.swift`, `readWorkspaceName`). The generated
    /// title (`session.title_changed`) is ephemeral, so there is no generated one to read.
    static func externalTitle(forLog url: URL) -> AgentSessionTitle {
        let file = url.deletingLastPathComponent().appendingPathComponent("workspace.yaml")
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return AgentSessionTitle() }
        return AgentSessionTitle(named: workspaceName(yaml: text), generated: nil)
    }

    /// The top-level `name` scalar: plain, quoted, or a block scalar (`name: |-` with the title on
    /// the indented line below), which Copilot often writes.
    static func workspaceName(yaml: String) -> String? {
        let lines = yaml.components(separatedBy: .newlines)
        guard let index = lines.firstIndex(where: { $0.hasPrefix("name:") }) else { return nil }
        var value = lines[index].dropFirst("name:".count).trimmingCharacters(in: .whitespaces)
        if let style = value.first, style == "|" || style == ">" {
            guard value.dropFirst().allSatisfy({ $0 == "-" || $0 == "+" || $0.isNumber }) else { return nil }
            let body = lines[(index + 1)...].first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            guard let body, body.first == " " || body.first == "\t" else { return nil }
            value = body.trimmingCharacters(in: .whitespaces)
        } else if value.count >= 2, let first = value.first, first == "\"" || first == "'", value.last == first {
            value = String(value.dropFirst().dropLast())
        }
        return value.isEmpty ? nil : value
    }

    /// The working folder: `data.context.cwd` on `session.start` / `session.resume`, `data.cwd` on
    /// `session.context_changed` (`WorkingDirectoryContext`). Newest first.
    private static func label(in lines: ArraySlice<Substring>) -> String? {
        for line in lines.reversed() {
            let cwd: Any?
            switch eventType(line) {
            case "session.start", "session.resume":
                cwd = (Event(line)?.data["context"] as? [String: Any])?["cwd"]
            case "session.context_changed":
                cwd = Event(line)?.data["cwd"]
            default:
                continue
            }
            if let path = cwd as? String, !path.isEmpty {
                return URL(fileURLWithPath: path).lastPathComponent
            }
        }
        return nil
    }

    /// A permission request nobody is looking at: resolved by a hook, auto-approved by mode, or
    /// already recommended for approval by the assisted-approval judge
    /// (`PermissionRequestedData`, `AssistedApprovalAssessment`).
    private static func settledWithoutPerson(_ data: [String: Any]) -> Bool {
        if data["resolvedByHook"] as? Bool == true { return true }
        let mode = data["permissionMode"] as? String
        if mode == "allow-all" { return true }
        let assessment = data["assistedApprovalAssessment"] as? [String: Any]
        return mode == "assisted" && assessment?["status"] as? String == "completed"
            && assessment?["recommendation"] as? String == "approve"
    }

    /// Whether the main-agent turn that `end` closes answered without asking for tools. Looks back
    /// within these lines to the turn's start; false when no reply of the turn is among them (a
    /// lone turn end usually follows tool runs, and more turns follow those).
    private static func endedWithoutTools(_ end: Event, before index: Int, in lines: [Substring]) -> Bool {
        let turnID = end.data["turnId"] as? String
        var sawReply = false
        for line in lines[..<index].reversed() {
            switch eventType(line) {
            case "assistant.turn_start", "assistant.turn_end", "user.message":
                guard let event = Event(line), !event.isSubagent else { continue }
                return sawReply
            case "assistant.message":
                guard let event = Event(line), !event.isSubagent else { continue }
                if let turnID, let other = event.data["turnId"] as? String, other != turnID { return sawReply }
                if let requests = event.data["toolRequests"] as? [Any], !requests.isEmpty { return false }
                sawReply = true
            case "tool.execution_start", "tool.execution_complete":
                // A subagent's tools run inside the parent's tool call, so any tool here means the
                // main turn asked for one.
                return false
            default:
                continue
            }
        }
        return sawReply
    }

    /// The event type without parsing the line: Copilot writes compact JSON with `type` first.
    /// Other shapes are parsed.
    private static func eventType(_ line: Substring) -> String? {
        let prefix = #"{"type":""#
        if line.hasPrefix(prefix) {
            let rest = line.dropFirst(prefix.count)
            guard let close = rest.firstIndex(of: "\"") else { return nil }
            return String(rest[..<close])
        }
        return Event(line)?.type
    }

    private struct Event {
        let id: String?
        let type: String
        let data: [String: Any]
        /// Subagent events carry a top-level `agentId` (current schema) or `data.parentToolCallId`
        /// (older CLIs and turn events), and their turns are not the session's.
        let isSubagent: Bool

        init?(_ line: Substring) {
            guard line.contains(#""type":""#),
                  let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let type = object["type"] as? String
            else { return nil }
            id = object["id"] as? String
            self.type = type
            data = object["data"] as? [String: Any] ?? [:]
            isSubagent = object["agentId"] is String || data["parentToolCallId"] is String
        }
    }
}
