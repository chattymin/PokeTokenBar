import Foundation

extension AgentLogSource {
    /// Cursor's agent (the IDE agent and the `cursor-agent` CLI) writes one transcript per chat:
    /// `~/.cursor/projects/<slug>/agent-transcripts/<chat>.jsonl` or `…/<chat>/<chat>.jsonl`.
    /// Delegated runs write to `<chat>/subagents/`, and their turns are not the chat's.
    ///
    /// This is a different place from the usage scan (`LocalCursorProvider`), which reads
    /// `Library/Application Support/Cursor/User/globalStorage/state.vscdb`.
    ///
    /// Current transcripts mark no turn end, so this source reports working and waiting; done only
    /// from older builds' end row (see `CursorTranscriptActivity`). No label: the folder is only in the lossy `<slug>`,
    /// which `interpret` cannot see. No title: Cursor keeps the chat name in `state.vscdb`.
    static func cursor() -> AgentLogSource {
        AgentLogSource(
            id: "cursor",
            roots: { CursorTranscriptActivity.roots() },
            accepts: CursorTranscriptActivity.isChatTranscript(_:),
            interpret: CursorTranscriptActivity.reading(lines:),
            hooks: AgentHookFile.cursor.integration,
            pathLabel: { CursorTranscriptActivity.folderName(transcript: $0) })
    }
}

/// Reads Cursor's agent transcript lines (one JSON object per line). Cursor documents neither the
/// place nor the format; both are taken from tools that read these files, which agree:
/// - `{"role":"user"|"assistant","message":{"content":[…]}}`, blocks `text` and
///   `tool_use{name,input}`. No timestamps, ids or stop reasons; tool results are not written.
///   (Cursor forum "Richer agent transcripts + lifecycle data", 2026-07-24, with real rows;
///   Tencent/teamai-cli `src/session-flow/adapters/cursor.ts`; caliber-ai-org/ai-setup
///   `src/compaction/cursor-transcript.ts`; perplexityai/numbat `internal/extract/cursor.go`.)
/// - Older builds also wrote `{"type":"turn_ended","status":"success"}` after the turn's last
///   assistant line; current builds do not (same forum post; teamai-cli writes "1 user + N
///   assistant + 1 turn_ended" to mirror it).
/// - Cursor appends while the agent runs (eunomia-bpf/agentsight `script/cursor_scan.py`).
///
/// Only the newest line that says something about the turn matters:
/// - `turn_ended` `success` → done; any other status → idle (over, nothing to announce).
/// - assistant with an `AskQuestion` call → waiting (the agent shows a question and stops).
/// - any other user or assistant line → working.
///
/// Without `turn_ended`, an assistant text line looks the same mid-turn (between tool calls) and
/// at the end, so the end is never guessed: the pet stays working until its own timeout. A false
/// "done" while the agent still works is worse than none. No line carries an id, so `lineID` is
/// nil: two turns that both end inside one batch of file events count as one.
enum CursorTranscriptActivity {
    static let transcriptsFolder = "agent-transcripts"

    static func roots(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        [home.appendingPathComponent(".cursor/projects")]
    }

    /// `<slug>/agent-transcripts/<chat>.jsonl` or `<slug>/agent-transcripts/<chat>/<chat>.jsonl`.
    /// A subagent's file sits one level deeper (`<chat>/subagents/<child>.jsonl`), so depth alone
    /// refuses it (eunomia-bpf/agentsight `script/cursor_scan.py`, getagentseal/codeburn).
    static func isChatTranscript(_ url: URL) -> Bool {
        guard url.pathExtension == "jsonl" else { return false }
        let parts = url.pathComponents
        guard let index = parts.lastIndex(of: transcriptsFolder), index > 1 else { return false }
        let below = parts.count - index - 1
        return below == 1 || below == 2
    }

    static func reading(lines: [Substring]) -> AgentLogReading? {
        for line in lines.reversed() {
            // Cheap filter before parsing. An escaped copy of a line inside a string (`\"role\"`)
            // cannot match `"role"`, and only top-level keys are read below anyway.
            guard line.contains(#""role""#) || line.contains("turn_ended"),
                  let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
            else { continue }
            if object["type"] as? String == "turn_ended" {
                let activity: AgentActivity = object["status"] as? String == "success" ? .done(message: nil) : .idle
                return AgentLogReading(activity: activity, label: nil, lineID: nil)
            }
            guard let message = object["message"] as? [String: Any] else { continue }
            switch object["role"] as? String {
            case "assistant":
                let blocks = message["content"] as? [[String: Any]] ?? []
                let asks = blocks.contains { $0["type"] as? String == "tool_use" && $0["name"] as? String == "AskQuestion" }
                return AgentLogReading(activity: asks ? .waiting(message: nil) : .working, label: nil, lineID: nil)
            case "user":
                return AgentLogReading(activity: .working, label: nil, lineID: nil)
            default:
                continue
            }
        }
        return nil
    }

    // MARK: - Working folder

    /// The `<slug>` folder a transcript sits under, e.g. `Users-me-code-web-app`.
    static func projectSlug(of url: URL) -> String? {
        let parts = url.pathComponents
        guard let index = parts.lastIndex(of: transcriptsFolder), index > 1 else { return nil }
        return parts[index - 1]
    }

    /// The working folder's name, for a source API that can label a file from its path (the
    /// current one cannot, see `AgentLogSource.cursor()`).
    ///
    /// The slug is the absolute path without its leading `/`, with `/` and `.` turned into `-`
    /// (thedotmack/claude-mem `src/cli/adapters/cursor.ts`; caliber-ai-org/ai-setup says every
    /// non-alphanumeric). That cannot be undone from the text: `code-web-app` may be `code/web-app`
    /// or `code/web/app`, and the last `-` piece is often not the folder. So the path is rebuilt
    /// against the folders that exist, comparing names with every non-alphanumeric as `-`. Nil when
    /// nothing matches or two folders do: no name is better than someone else's. `children` lists a
    /// folder's entries, nil when the path is not a folder.
    static func folderName(slug: String, children: (String) -> [String]?) -> String? {
        let target = normalized(slug)
        guard !target.isEmpty else { return nil }
        var matches: [String] = []
        func walk(_ directory: String, _ rest: Substring) {
            guard matches.count < 2, let names = children(directory.isEmpty ? "/" : directory) else { return }
            for name in names {
                let key = normalized(name)
                guard !key.isEmpty else { continue }
                let path = directory + "/" + name
                if rest == key {
                    if children(path) != nil { matches.append(path) }
                } else if rest.hasPrefix(key + "-") {
                    walk(path, rest.dropFirst(key.count + 1))
                }
            }
        }
        walk("", target[...])
        guard matches.count == 1, let path = matches.first else { return nil }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    /// `folderName(slug:children:)` against the disk. Lists only the folders along candidate
    /// paths; a file cannot be listed, so it never matches.
    static func folderName(transcript url: URL, fileManager: FileManager = .default) -> String? {
        guard let slug = projectSlug(of: url) else { return nil }
        return folderName(slug: slug) { try? fileManager.contentsOfDirectory(atPath: $0) }
    }

    private static func normalized(_ text: String) -> String {
        String(text.unicodeScalars.map { scalar -> Character in
            scalar.isASCII && CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : "-"
        })
    }
}
