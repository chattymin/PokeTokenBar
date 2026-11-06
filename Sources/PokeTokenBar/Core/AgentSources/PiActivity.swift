import Foundation

/// Reads the session logs of Pi Agent and its forks omp (oh-my-pi) and omo (senpi). All three write
/// the same JSONL (one compact `JSON.stringify` object per line) and differ only in which tool asks
/// the person a question and which folders under the sessions root are not sessions.
///
/// Checked against upstream source (2026-11-06): earendil-works/pi @2a32a60 (formerly
/// badlogic/pi-mono), can1357/oh-my-pi @660a31d, code-yeongyu/senpi @f4dc3ac.
/// - Messages are `{"type":"message","id":…,"message":{"role":…}}`, written on `message_end`
///   (pi `packages/coding-agent/src/core/agent-session.ts`, omp `src/session/agent-session.ts`).
/// - An assistant `stopReason` is `stop`, `length`, `toolUse`, `error` or `aborted` (pi also has
///   `pending` and `deferred` for its proxy and batch APIs; `packages/ai/src/types.ts`).
///   Tool calls are content blocks `{"type":"toolCall","id":…,"name":…}`.
/// - The agent loop keeps going while an assistant message has tool calls, even one cut off by
///   `length`, and ends on `error`/`aborted` (pi `packages/agent/src/agent-loop.ts`).
/// - Tool results of one batch are written in call order, after the calls before them finished
///   (pi `executeToolCallsParallel`, omp `flushResultMessages` in `packages/agent/src/agent-loop.ts`).
/// - The working folder is only in the session header `{"type":"session",…,"cwd":…}`: line 1 for
///   Pi and senpi, line 2 for omp, whose line 1 is a fixed 256-byte `{"type":"title"}` slot
///   (omp `src/session/session-entries.ts`, `session-title-slot.ts`).
enum PiSessionActivity {
    /// What differs between the forks.
    struct Fork: Sendable {
        /// Tools that wait for the person's answer until their result is written.
        let askTools: Set<String>
        /// Folders under the sessions root that hold no sessions of the person's.
        let skippedFolders: Set<String>

        /// Pi has no built-in tool that asks the person.
        static let pi = Fork(askTools: [], skippedFolders: [])
        /// omp `ask` (`src/tools/ask.ts`). `bridge/` holds copies pi-session-manager converts from
        /// other agents' sessions (see `LocalUsageReader.isOmpUsageFile`).
        static let omp = Fork(askTools: ["ask"], skippedFolders: ["bridge"])
        /// senpi's ask-user extension names its tool after the model family
        /// (`src/core/extensions/builtin/ask-user/family.ts`). `session-holders/` holds
        /// per-process lock records (`src/core/session-holders.ts`).
        static let omo = Fork(askTools: ["ask_user_question", "request_user_input"],
                              skippedFolders: ["session-holders"])
    }

    /// Only the newest line that says something about the turn matters:
    /// - assistant `aborted` (Esc) or `error` → idle. Pi and omp retry some errors on their own;
    ///   the retry's lines then read as working again.
    /// - assistant calling an ask tool → waiting; calling any other tool → working (its result
    ///   follows); no tool calls and `stop`/`length` → done; anything else → working.
    /// - user prompt or tool result → working, except a result that leaves an ask call of the same
    ///   message unanswered (results of calls before it are written while it waits).
    /// `bashExecution` (`!cmd`), `pythonExecution`, `custom`, `developer` and summary messages
    /// neither start nor end a turn and are skipped, like every non-message line.
    static func reading(lines: [Substring], fork: Fork) -> AgentLogReading? {
        // Results newer than the assistant message they answer: the newest one, and every call id.
        var sawResult = false
        var newestResultID: String?
        var answered: Set<String> = []
        for line in lines.reversed() {
            // Cheap filter before parsing. An escaped copy inside a tool result cannot match.
            guard line.contains(#""type":"message""#),
                  let object = parse(line), object["type"] as? String == "message",
                  let message = object["message"] as? [String: Any]
            else { continue }
            let lineID = object["id"] as? String
            switch message["role"] as? String {
            case "toolResult":
                if !sawResult { sawResult = true; newestResultID = lineID }
                if let id = message["toolCallId"] as? String { answered.insert(id) }
            case "user":
                return AgentLogReading(activity: .working, label: nil, lineID: sawResult ? newestResultID : lineID)
            case "assistant":
                if pendingAsk(message, fork: fork, answered: answered) {
                    return AgentLogReading(activity: .waiting(message: nil), label: nil, lineID: lineID)
                }
                if sawResult { return AgentLogReading(activity: .working, label: nil, lineID: newestResultID) }
                return AgentLogReading(activity: assistantActivity(message), label: nil, lineID: lineID)
            default:
                continue
            }
        }
        return sawResult ? AgentLogReading(activity: .working, label: nil, lineID: newestResultID) : nil
    }

    /// The message calls an ask tool whose result is not among `answered`. A `length` stop fails
    /// every call without running it, and an `error`/`aborted` one runs none, so no question shows.
    private static func pendingAsk(_ message: [String: Any], fork: Fork, answered: Set<String>) -> Bool {
        let stop = message["stopReason"] as? String ?? ""
        guard !fork.askTools.isEmpty, !["length", "error", "aborted"].contains(stop) else { return false }
        return toolCalls(message).contains {
            guard let name = $0["name"] as? String, fork.askTools.contains(name) else { return false }
            return !answered.contains($0["id"] as? String ?? "")
        }
    }

    private static func assistantActivity(_ message: [String: Any]) -> AgentActivity {
        let stop = message["stopReason"] as? String
        if stop == "aborted" || stop == "error" { return .idle }
        if !toolCalls(message).isEmpty { return .working }
        return stop == "stop" || stop == "length" ? .done(message: nil) : .working
    }

    private static func toolCalls(_ message: [String: Any]) -> [[String: Any]] {
        (message["content"] as? [[String: Any]] ?? []).filter { $0["type"] as? String == "toolCall" }
    }

    /// Titles appended to the log:
    /// - `{"type":"session_info","name":…}` (Pi, senpi): `/name`, or senpi's generated title, which
    ///   it writes the same way. Kept as `named`: the newest line is the session's name either way.
    /// - `{"type":"title_change","title":…,"source":"user"|"auto"}` (omp `setSessionName`).
    static func title(lines: [Substring]) -> AgentSessionTitle {
        var title = AgentSessionTitle()
        for line in lines.reversed() where title.named == nil || title.generated == nil {
            let info = line.contains(#""type":"session_info""#)
            guard info || line.contains(#""type":"title_change""#), let object = parse(line) else { continue }
            switch object["type"] as? String {
            case "session_info":
                if title.named == nil { title.named = nonEmpty(object["name"]) }
            case "title_change":
                if object["source"] as? String == "user" {
                    if title.named == nil { title.named = nonEmpty(object["title"]) }
                } else if title.generated == nil {
                    title.generated = nonEmpty(object["title"])
                }
            default:
                continue
            }
        }
        return title
    }

    /// The working folder and the title from the first lines. omp keeps its current title in the
    /// line 1 slot (rewritten in place, so only this read sees it) and in the header; the header
    /// only changes when the whole file is rewritten. senpi marks sessions it started for a task
    /// of another session with `spawnedBy` (`src/core/session-manager.ts`); they are skipped.
    static func head(lines: [Substring]) -> AgentLogHead {
        var head = AgentLogHead()
        for line in lines {
            guard line.contains(#""type":"session""#) || line.contains(#""type":"title""#),
                  let object = parse(line)
            else { continue }
            switch object["type"] as? String {
            case "title":
                head.title = slotTitle(object["title"], source: object["source"])
            case "session":
                head.label = (object["cwd"] as? String).flatMap(nonEmpty).map { URL(fileURLWithPath: $0).lastPathComponent }
                if object["spawnedBy"] is [String: Any] { head.skip = true }
                if head.title.text == nil { head.title = slotTitle(object["title"], source: object["titleSource"]) }
                return head
            default:
                continue
            }
        }
        return head
    }

    /// Whether `url` is a session the person runs. omp keeps a session's subagent transcripts in
    /// a folder named after the session file (`<time>_<id>/<agent>.jsonl`, and deeper for nested
    /// subagents; `src/task/executor.ts`, `structured-subagent.ts`), so any `.jsonl` under such a
    /// folder is a helper's.
    static func accepts(_ url: URL, fork: Fork) -> Bool {
        guard url.pathExtension == "jsonl" else { return false }
        let folders = url.pathComponents.dropLast()
        return !folders.contains { fork.skippedFolders.contains($0) || isSessionFileStem($0) }
    }

    /// `2026-01-02T03-04-05-678Z_<id>`: the session file name without `.jsonl` (pi `newSession`,
    /// omp `session-listing.ts`). Encoded working folders start with `-`, so they never match.
    static func isSessionFileStem(_ name: String) -> Bool {
        guard let underscore = name.firstIndex(of: "_") else { return false }
        let stamp = Array(name[..<underscore])
        guard stamp.count >= 19, stamp[10] == "T", stamp[4] == "-", stamp[7] == "-" else { return false }
        return [0, 1, 2, 3, 5, 6, 8, 9, 11, 12].allSatisfy { stamp[$0].isASCII && stamp[$0].isNumber }
    }

    private static func slotTitle(_ text: Any?, source: Any?) -> AgentSessionTitle {
        guard let text = nonEmpty(text) else { return AgentSessionTitle() }
        return source as? String == "user" ? AgentSessionTitle(named: text, generated: nil)
            : AgentSessionTitle(named: nil, generated: text)
    }

    private static func parse(_ line: Substring) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
    }

    private static func nonEmpty(_ value: Any?) -> String? {
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty
        else { return nil }
        return text
    }
}

extension AgentLogSource {
    /// Pi Agent: `<sessions root>/--<cwd with / as ->--/<time>_<uuid>.jsonl`.
    static func pi() -> AgentLogSource {
        piFamily(id: "pi", defaults: { LocalUsageReader.piSessionRoots }, fork: .pi)
    }

    /// omp (oh-my-pi): `~/.omp/agent/sessions/<encoded cwd>/<time>_<id>.jsonl`.
    static func omp() -> AgentLogSource {
        piFamily(id: "omp", defaults: { LocalUsageReader.ompSessionRoots }, fork: .omp)
    }

    /// omo (senpi edition): `~/.omo/agent/sessions/…` or `~/.senpi/agent/sessions/…`.
    static func omo() -> AgentLogSource {
        piFamily(id: "omo", defaults: { LocalUsageReader.omoSessionRoots }, fork: .omo)
    }

    /// The same roots the usage scan reads, including the folders added in Settings.
    private static func piFamily(id: String, defaults: @escaping @Sendable () -> [URL],
                                 fork: PiSessionActivity.Fork) -> AgentLogSource {
        AgentLogSource(
            id: id,
            roots: { CustomScanRoots.union(defaults: defaults(), extraRaw: CustomScanRoots.storedValue(for: id)) },
            accepts: { PiSessionActivity.accepts($0, fork: fork) },
            interpret: { PiSessionActivity.reading(lines: $0, fork: fork) },
            hooks: nil,
            title: PiSessionActivity.title(lines:),
            head: PiSessionActivity.head(lines:))
    }
}
