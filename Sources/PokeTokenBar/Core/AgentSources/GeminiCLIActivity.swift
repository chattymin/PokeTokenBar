import Foundation

extension AgentLogSource {
    /// Gemini CLI: `~/.gemini/tmp/<project>/chats/session-<time>-<id>.jsonl`. Subagents write to
    /// `chats/<parent session id>/<id>.jsonl` and mark their first line `kind: "subagent"`; both are
    /// skipped. Older CLIs kept one rewritten `.json` per session, which is not followed.
    ///
    /// Reports working and idle only: the log has no turn-end marker (see `GeminiCLIActivity`).
    static func geminiCLI() -> AgentLogSource {
        AgentLogSource(
            id: "gemini",
            roots: { LocalUsageReader.geminiScanRoots(customRootsValue: CustomScanRoots.storedValue(for: "gemini")) },
            accepts: GeminiCLIActivity.accepts(_:),
            interpret: GeminiCLIActivity.reading(lines:),
            hooks: AgentHookFile.geminiCLI.integration,
            title: GeminiCLIActivity.title(lines:),
            head: GeminiCLIActivity.head(lines:),
            pathLabel: GeminiCLIActivity.label(forLog:))
    }
}

/// Reads Gemini CLI session logs (`ChatRecordingService`, google-gemini/gemini-cli
/// `packages/core/src/services/chatRecording{Service,Types}.ts`, checked at main 3fd7d26,
/// 2026-11-05). The file is append-only: a metadata line, then one JSON object per message
/// (`{id, timestamp, type: user|gemini|info|warning|error, content, toolCalls?}`), plus
/// `{"$set": …}` (metadata, e.g. `lastUpdated` after every message), `{"$patch": …}` and
/// `{"$rewindTo": …}`. A message is written again under the same id when it changes.
///
/// What the newest message says:
/// - `user` → working. Gemini records the person's prompt and also each tool response as a
///   `user` message (`geminiChat.ts`, `recordSyntheticMessage('user', …)`). The environment
///   context it writes when a session starts (`<session_context>…`, `environmentContext.ts`) is
///   not a prompt and is skipped.
/// - `gemini` → working.
/// - `info` "Request cancelled." → idle: the CLI writes exactly this on Esc/Ctrl+C and when every
///   tool call of a batch was cancelled (`useGeminiStream.ts`, three call sites).
/// - `error` → idle: a failed request (`handleErrorEvent`, `handleInvalidStreamEvent`).
///
/// Deliberately not inferred:
/// - **done.** No line marks the end of a turn. A `gemini` message without `toolCalls` looks
///   final but is not: tool calls are added to it only after they *complete*
///   (`recordCompletedToolCalls`), so the same message sits there tool-less for the whole run
///   of a tool or an approval prompt. The CLI can also continue on its own after a reply (a
///   next-speaker check, an `AfterAgent` hook retry). A done from this would call the person
///   while Gemini still works.
/// - **waiting.** Approval prompts are not written at all; `toolCalls` carry only final statuses.
/// - **automatic turns.** Nothing in the log tells them apart.
enum GeminiCLIActivity {
    /// Main sessions only: `chats/session-*.jsonl`. A subagent's file sits one folder deeper.
    static func accepts(_ url: URL) -> Bool {
        url.pathExtension == "jsonl"
            && url.lastPathComponent.hasPrefix("session-")
            && url.deletingLastPathComponent().lastPathComponent == "chats"
    }

    static func reading(lines: [Substring]) -> AgentLogReading? {
        for line in lines.reversed() {
            // `JSON.stringify` writes compact JSON with `id` first; bookkeeping records start with
            // their `$` key. The type check below still runs on the parsed object, since tool
            // arguments can hold a `"type":…` key of their own.
            guard !line.hasPrefix(#"{"$"#), line.contains(#""type":""#),
                  let object = jsonObject(line),
                  let type = object["type"] as? String
            else { continue }
            let lineID = object["id"] as? String
            func reading(_ activity: AgentActivity) -> AgentLogReading {
                AgentLogReading(activity: activity, label: nil, lineID: lineID)
            }
            switch type {
            case "user":
                if isBootstrap(object["content"]) { continue }
                return reading(.working)
            case "gemini":
                return reading(.working)
            case "info":
                if text(of: object["content"])?.trimmingCharacters(in: .whitespacesAndNewlines) == "Request cancelled." {
                    return reading(.idle)
                }
                continue
            case "error":
                return reading(.idle)
            default:
                continue
            }
        }
        return nil
    }

    /// `{"$set":{"summary":…}}`: the one-line summary Gemini writes for its session list
    /// (`saveSummary`, `sessionSummaryUtils.ts`). It is generated for the *previous* session when a
    /// new one starts, so a live session usually has none until it is resumed.
    static func title(lines: [Substring]) -> AgentSessionTitle {
        for line in lines.reversed() where line.hasPrefix(#"{"$set""#) && line.contains(#""summary""#) {
            guard let set = jsonObject(line)?["$set"] as? [String: Any],
                  let summary = nonEmpty(set["summary"])
            else { continue }
            return AgentSessionTitle(named: nil, generated: summary)
        }
        return AgentSessionTitle()
    }

    /// The first line is the session's metadata (`initialMetadata` in `doInitialize`):
    /// `{sessionId, projectHash, startTime, lastUpdated, kind?, directories?, summary?}`.
    /// `kind: "subagent"` marks a subagent's log. `directories` is only set for subagents, so the
    /// label comes from the project folder instead (`label(forLog:)`).
    static func head(lines: [Substring]) -> AgentLogHead {
        guard let first = lines.first, let object = jsonObject(first),
              object["sessionId"] is String, object["type"] == nil
        else { return AgentLogHead() }
        return AgentLogHead(label: nil, skip: object["kind"] as? String == "subagent",
                            title: AgentSessionTitle(named: nil, generated: nonEmpty(object["summary"])))
    }

    /// The working folder's name. Each project folder under `~/.gemini/tmp` holds a `.project_root`
    /// file with the project's absolute path (`ProjectRegistry.ensureOwnershipMarkers`,
    /// `packages/core/src/config/projectRegistry.ts`).
    static func label(forLog url: URL) -> String? {
        let project = url.deletingLastPathComponent().deletingLastPathComponent()
        let root = try? String(contentsOf: project.appendingPathComponent(".project_root"), encoding: .utf8)
        return label(projectRoot: root, projectFolder: project.lastPathComponent)
    }

    /// Without the marker, the folder name: the CLI names it after the project folder, lowercased
    /// and dashed (`ProjectRegistry.slugify`). Folders from before the registry are a SHA-256 of the
    /// path, which names nothing.
    static func label(projectRoot: String?, projectFolder: String) -> String? {
        if let root = projectRoot?.trimmingCharacters(in: .whitespacesAndNewlines), !root.isEmpty {
            let name = URL(fileURLWithPath: root).lastPathComponent
            if !name.isEmpty, name != "/" { return name }
        }
        let isHash = projectFolder.count == 64 && projectFolder.allSatisfy(\.isHexDigit)
        return projectFolder.isEmpty || isHash ? nil : projectFolder
    }

    /// The session-start context Gemini sends before the first prompt; recorded as a `user`
    /// message, but nobody asked for anything.
    private static func isBootstrap(_ content: Any?) -> Bool {
        guard let text = text(of: content)?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false   // parts without text: a tool response
        }
        return text.isEmpty || text.hasPrefix("<session_context>")
    }

    /// `content` is a `PartListUnion`: a string, one part, or a list of parts. Nil when no part
    /// carries text (a function response).
    private static func text(of content: Any?) -> String? {
        if let string = content as? String { return string }
        let parts = (content as? [[String: Any]]) ?? (content as? [String: Any]).map { [$0] } ?? []
        let texts = parts.compactMap { $0["text"] as? String }
        return texts.isEmpty ? nil : texts.joined()
    }

    private static func jsonObject(_ line: Substring) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
    }

    private static func nonEmpty(_ value: Any?) -> String? {
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty
        else { return nil }
        return text
    }
}
