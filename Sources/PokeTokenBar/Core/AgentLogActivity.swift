import Foundation

/// Whether an agent reports itself through hooks the app can add for it.
enum AgentHookStatus: Equatable, Sendable {
    case notInstalled
    /// `removable` is false when only hand-written hooks exist; the app leaves those alone.
    case installed(removable: Bool)

    var isInstalled: Bool { self != .notInstalled }
}

/// Hooks the app can add to an agent's own settings so it reports waiting for permission too,
/// which its session log does not show.
struct AgentHookIntegration: Sendable {
    let agentName: String
    /// Shown in the confirmation, so the person knows which file changes.
    let settingsDescription: @Sendable () -> String
    let status: @Sendable () -> AgentHookStatus
    let install: @Sendable () throws -> Void
    let uninstall: @Sendable () throws -> Void
}

/// What the newest lines of a session log say about its agent.
struct AgentLogReading: Equatable, Sendable {
    var activity: AgentActivity
    var label: String?
    /// Identifies the line behind a `done` or `waiting`, so two turns that end within one batch of
    /// file events still count as two.
    var lineID: String?
}

/// One kind of agent whose session logs show its activity, so the pet reacts with no setup.
/// The watcher and the pet only see this description, never a particular agent.
struct AgentLogSource: Sendable {
    let id: String
    /// Folders holding the logs. May take a while (login shell lookup): called off the main thread.
    let roots: @Sendable () -> [URL]
    let accepts: @Sendable (URL) -> Bool
    /// Reading after these complete lines were appended; nil when they say nothing new.
    let interpret: @Sendable ([Substring]) -> AgentLogReading?
    let hooks: AgentHookIntegration?
}

extension AgentLogSource {
    /// Claude Code: `<projects root>/<project>/<session>.jsonl`. Subagents write to
    /// `<session>/subagents/`, and their turns ending is not the session ending.
    static func claudeCode(hooks: AgentHookIntegration? = .claudeCode) -> AgentLogSource {
        AgentLogSource(
            id: "claude-code",
            roots: { LocalUsageReader.claudeProjectRoots },
            accepts: { $0.pathExtension == "jsonl" && !$0.pathComponents.contains("subagents") },
            interpret: ClaudeTranscriptActivity.reading(lines:),
            hooks: hooks)
    }
}

extension AgentLogSource {
    /// What the app watches. Empty outside the bundled app: tests must not read the developer's
    /// own logs or settings.
    static var installed: [AgentLogSource] { AppEnv.isBundledApp ? [.claudeCode()] : [] }
}

extension AgentHookIntegration {
    /// Rows in Settings → Floating Pet. Render tests replace it with a fake integration.
    @MainActor static var settingsRows: [AgentHookIntegration] = AgentLogSource.installed.compactMap(\.hooks)

    static let claudeCode = AgentHookIntegration(
        agentName: "Claude Code",
        settingsDescription: {
            files().map { $0.path.replacingOccurrences(of: NSHomeDirectory(), with: "~") }.joined(separator: ", ")
        },
        status: { ClaudeAgentHooks.status(files: files()) },
        install: { try ClaudeAgentHooks.install(files: files()) },
        uninstall: { try ClaudeAgentHooks.uninstall(files: files()) })

    private static func files() -> [URL] {
        ClaudeAgentHooks.settingsFiles(configDirValue: LocalUsageReader.shellAwareClaudeConfigDir())
    }
}

/// Reads Claude Code's transcript lines (one JSON object per line). Only the newest line that says
/// something about the turn matters:
/// - assistant, `stop_reason` `end_turn` → done; an `AskUserQuestion` call → waiting; else working.
/// - user prompt or tool result → working; `[Request interrupted by user…]` (Esc) → idle.
/// Meta, sidechain, compact-summary and local-command lines are skipped. Checked against real
/// transcripts written by Claude Code 2.x (2026-11).
enum ClaudeTranscriptActivity {
    static func reading(lines: [Substring]) -> AgentLogReading? {
        for line in lines.reversed() {
            // Cheap filter before parsing: tool results can be large and are most of the lines.
            // Claude Code writes compact JSON, and a nested (escaped) copy cannot match this.
            guard line.contains(#""type":"assistant""#) || line.contains(#""type":"user""#),
                  let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let type = object["type"] as? String,
                  let message = object["message"] as? [String: Any]
            else { continue }
            let skipped = ["isSidechain", "isMeta", "isCompactSummary", "isVisibleInTranscriptOnly"]
            if skipped.contains(where: { object[$0] as? Bool == true }) { continue }
            let label = (object["cwd"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent }
            let lineID = object["uuid"] as? String
            func reading(_ activity: AgentActivity) -> AgentLogReading {
                AgentLogReading(activity: activity, label: label, lineID: lineID)
            }
            switch type {
            case "assistant":
                if object["isApiErrorMessage"] as? Bool == true { return reading(.idle) }
                let blocks = message["content"] as? [[String: Any]] ?? []
                if blocks.contains(where: { $0["type"] as? String == "tool_use" && $0["name"] as? String == "AskUserQuestion" }) {
                    return reading(.waiting(message: nil))
                }
                return reading(message["stop_reason"] as? String == "end_turn" ? .done(message: nil) : .working)
            case "user":
                let text = firstText(message["content"])
                if text?.hasPrefix("[Request interrupted by user") == true { return reading(.idle) }
                // `/model`, `/config` and the like: no turn follows, so they must not start "working".
                if let text, text.hasPrefix("<command-name>") || text.hasPrefix("<local-command") { continue }
                return reading(.working)
            default:
                continue
            }
        }
        return nil
    }

    private static func firstText(_ content: Any?) -> String? {
        if let string = content as? String { return string }
        guard let blocks = content as? [[String: Any]] else { return nil }
        if blocks.contains(where: { $0["type"] as? String == "tool_result" }) { return nil }
        return blocks.first { $0["type"] as? String == "text" }?["text"] as? String
    }
}

/// Decides which readings reach the pet. Logs change several times a second while an agent works;
/// the pet needs a change of state, plus a periodic "still working" so its 10-minute timeout does
/// not fire mid-task.
struct AgentLogEmitter: Sendable {
    static let workingRefresh: TimeInterval = 60
    /// Labels come from folder names; past this many the memory starts over.
    static let maxTracked = 64

    private struct Last: Sendable {
        var kind: Int
        var lineID: String?
        var at: Date
    }

    private var last: [String: Last] = [:]

    /// `hooksReport`: the agent's hooks already send working/waiting/done. Only `idle` passes then,
    /// because hooks miss an Esc interrupt and would leave the pet working for 10 minutes.
    mutating func shouldEmit(_ reading: AgentLogReading, sourceID: String, hooksReport: Bool, now: Date) -> Bool {
        let kind = Self.kind(reading.activity)
        let idle = Self.kind(.idle)
        let key = sourceID + "\u{1F}" + (reading.label ?? "")
        let previous = last[key]
        if last.count >= Self.maxTracked, previous == nil { last = [:] }
        // A "still working" refresh must not move the clock it is measured against.
        let refreshDue = previous.map { now.timeIntervalSince($0.at) >= Self.workingRefresh } ?? true
        if previous?.kind != kind || reading.activity != .working || refreshDue {
            last[key] = Last(kind: kind, lineID: reading.lineID, at: now)
        }
        if hooksReport { return kind == idle && previous?.kind != idle }
        guard let previous else { return kind != idle }
        guard previous.kind == kind else { return true }
        switch reading.activity {
        case .working: return refreshDue
        case .done, .waiting: return reading.lineID != previous.lineID
        case .idle: return false
        }
    }

    private static func kind(_ activity: AgentActivity) -> Int {
        switch activity {
        case .idle: 0
        case .working: 1
        case .waiting: 2
        case .done: 3
        }
    }
}

/// Which bytes of a log to read after it changed. Pure, so the edge cases are tested directly.
enum AgentLogTail {
    /// Read when a file is first seen or jumped far ahead: enough for the last few lines.
    static let tailBytes: UInt64 = 64 * 1024
    /// More new bytes than this and only the tail is read.
    static let maxDelta: UInt64 = 1024 * 1024

    /// Nil when there is nothing new. `dropsFirstLine`: the range starts mid-line.
    static func range(size: UInt64, knownOffset: UInt64?) -> (start: UInt64, dropsFirstLine: Bool)? {
        if let knownOffset, knownOffset == size { return nil }
        if let knownOffset, knownOffset < size, size - knownOffset <= maxDelta { return (knownOffset, false) }
        let start = size > tailBytes ? size - tailBytes : 0
        return (start, start > 0)
    }

    /// Complete lines in `data` and how many bytes they span. A trailing line without its newline
    /// is still being written; it is left for the next read.
    static func completeLines(_ data: Data, dropsFirstLine: Bool) -> (lines: [Substring], consumed: Int) {
        guard let lastNewline = data.lastIndex(of: 0x0A) else { return ([], 0) }
        let consumed = data.distance(from: data.startIndex, to: lastNewline) + 1
        let text = String(decoding: data[data.startIndex..<lastNewline], as: UTF8.self)
        var lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        if dropsFirstLine, !lines.isEmpty, data.first != 0x0A { lines.removeFirst() }
        return (lines, consumed)
    }
}
