import Foundation

/// Adds or removes the Claude Code hooks that send `poketokenbar://agent` URLs, in Claude Code's
/// `settings.json`. The app only touches entries it wrote (tagged with `marker`); everything else in
/// the file keeps its order and spelling. Hooks set up by hand from the README count as installed
/// but are never removed.
enum ClaudeAgentHooks {
    /// Ends every command the app writes. A shell comment, so Claude Code ignores it.
    static let marker = "# poketokenbar-agent-hook"
    /// Any hook command containing one of these drives the pet, written by the app or by hand.
    static let detectionNeedles = ["poketokenbar://agent", "poketokenbar.sh"]

    struct Hook: Equatable {
        let event: String
        let matcher: String?
        let state: String
    }

    /// Same events as the README's manual setup.
    static let hooks: [Hook] = [
        Hook(event: "UserPromptSubmit", matcher: nil, state: "working"),
        Hook(event: "PostToolUse", matcher: "*", state: "working"),
        Hook(event: "PreToolUse", matcher: "AskUserQuestion", state: "waiting"),
        // Without the matcher, Claude Code's idle reminder would leave a "waiting" bubble after every turn.
        Hook(event: "Notification", matcher: "permission_prompt|elicitation_dialog", state: "waiting"),
        Hook(event: "Stop", matcher: nil, state: "done"),
    ]

    /// Self-contained: no script file to leave behind. `pgrep` keeps a hook from relaunching a quit
    /// app, `open -g` keeps terminal focus, and the label is the project folder, percent-encoded with
    /// the `perl` that ships with macOS. Always exits 0 so a hook can never block Claude Code.
    /// Grok CLI and Devin CLI run the hooks in `~/.claude/settings.json` too (Grok: always, its
    /// `custom-hooks.md`; Devin: by default, `read_config_from.claude`). Grok's turns are read from
    /// its own log and its own hook file, so the command does nothing when `GROK_HOOK_EVENT` is set.
    /// Cursor runs them too (Third-Party Imports, on by default) and has its own hook file, so
    /// `CURSOR_VERSION` also means "not Claude Code". Devin sets no `CLAUDE_PROJECT_DIR`, so its
    /// folder comes from `DEVIN_PROJECT_DIR`: these hooks give Devin the done its database lacks.
    static func command(state: String) -> String {
        #"[ -z "$GROK_HOOK_EVENT$CURSOR_VERSION" ] && pgrep -xq PokeTokenBar && d="${CLAUDE_PROJECT_DIR:-$DEVIN_PROJECT_DIR}" && open -g "poketokenbar://agent?state="# + state
            + #"&label=$(printf %s "${d##*/}" | perl -pe 's/([^A-Za-z0-9._~-])/sprintf("%%%02X", ord $1)/ge')" >/dev/null 2>&1; exit 0 "#
            + marker
    }

    enum Failure: Error, Equatable {
        /// The file is not a JSON object; the app refuses to touch it.
        case unreadableSettings
        case writeFailed
    }

    // MARK: Pure edits

    static func status(of settings: OrderedJSON) -> AgentHookStatus {
        let commands = hookCommands(in: settings)
        guard commands.contains(where: { c in detectionNeedles.contains { c.contains($0) } }) else { return .notInstalled }
        return .installed(removable: commands.contains { $0.hasSuffix(marker) })
    }

    /// Adds the app's hooks next to whatever is there. Idempotent: earlier app entries are replaced.
    static func installing(into settings: OrderedJSON) -> OrderedJSON {
        var settings = removing(from: settings)
        var hooksObject = settings["hooks"] ?? .object([])
        if case .object = hooksObject {} else { hooksObject = .object([]) }
        for hook in hooks {
            var groups = hooksObject[hook.event]?.arrayValue ?? []
            var group: [(key: String, value: OrderedJSON)] = []
            if let matcher = hook.matcher { group.append(("matcher", .string(matcher))) }
            group.append(("hooks", .array([.object([
                ("type", .string("command")),
                ("command", .string(command(state: hook.state))),
            ])])))
            groups.append(.object(group))
            hooksObject.set(hook.event, .array(groups))
        }
        settings.set("hooks", hooksObject)
        return settings
    }

    /// Drops only the app's own commands, then any group or event left empty by that.
    static func removing(from settings: OrderedJSON) -> OrderedJSON {
        guard case .object(let events)? = settings["hooks"] else { return settings }
        var changed = false
        var kept: [(key: String, value: OrderedJSON)] = []
        for (event, value) in events {
            guard let groups = value.arrayValue else { kept.append((event, value)); continue }
            var newGroups: [OrderedJSON] = []
            for group in groups {
                guard let commands = group["hooks"]?.arrayValue else { newGroups.append(group); continue }
                let remaining = commands.filter { !(($0["command"]?.stringValue)?.hasSuffix(marker) ?? false) }
                if remaining.count == commands.count { newGroups.append(group); continue }
                changed = true
                guard !remaining.isEmpty else { continue }
                var g = group
                g.set("hooks", .array(remaining))
                newGroups.append(g)
            }
            if !newGroups.isEmpty || groups.isEmpty { kept.append((event, .array(newGroups))) }
        }
        guard changed else { return settings }
        var settings = settings
        settings.set("hooks", kept.isEmpty ? nil : .object(kept))
        return settings
    }

    private static func hookCommands(in settings: OrderedJSON) -> [String] {
        guard case .object(let events)? = settings["hooks"] else { return [] }
        return events.flatMap { $0.value.arrayValue ?? [] }
            .flatMap { $0["hooks"]?.arrayValue ?? [] }
            .compactMap { $0["command"]?.stringValue }
    }

    // MARK: Files

    /// Where Claude Code reads user settings: each `CLAUDE_CONFIG_DIR` folder, else `~/.claude`.
    static func settingsFiles(configDirValue: String?,
                              home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        let dirs = (configDirValue ?? "").split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { URL(fileURLWithPath: NSString(string: $0).expandingTildeInPath, isDirectory: true) }
        let roots = dirs.isEmpty ? [home.appendingPathComponent(".claude", isDirectory: true)] : dirs
        var seen = Set<String>()
        return roots.map { $0.appendingPathComponent("settings.json").standardizedFileURL }
            .filter { seen.insert($0.path).inserted }
    }

    /// A missing file is an empty object: Claude Code creates it the same way.
    static func read(_ file: URL) throws -> OrderedJSON { try AgentSettingsFile.read(file) }

    static func status(files: [URL]) -> AgentHookStatus {
        let statuses = files.compactMap { try? status(of: read($0)) }
        if statuses.contains(.installed(removable: true)) { return .installed(removable: true) }
        if statuses.contains(.installed(removable: false)) { return .installed(removable: false) }
        return .notInstalled
    }

    static func install(files: [URL]) throws { try edit(files, installing(into:)) }
    static func uninstall(files: [URL]) throws { try edit(files, removing(from:)) }

    /// See `AgentSettingsFile.edit`: read and checked first, backed up once, written atomically.
    private static func edit(_ files: [URL], _ transform: (OrderedJSON) -> OrderedJSON) throws {
        try AgentSettingsFile.edit(files, transform)
    }
}
