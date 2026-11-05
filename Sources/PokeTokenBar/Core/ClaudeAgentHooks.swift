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
    static func command(state: String) -> String {
        #"pgrep -xq PokeTokenBar && open -g "poketokenbar://agent?state="# + state
            + #"&label=$(printf %s "${CLAUDE_PROJECT_DIR##*/}" | perl -pe 's/([^A-Za-z0-9._~-])/sprintf("%%%02X", ord $1)/ge')" >/dev/null 2>&1; exit 0 "#
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
    static func read(_ file: URL) throws -> OrderedJSON {
        guard let data = FileManager.default.contents(atPath: file.path) else { return .object([]) }
        if data.allSatisfy({ [0x20, 0x09, 0x0A, 0x0D].contains($0) }) { return .object([]) }
        guard let json = try? OrderedJSON(parsing: data), case .object = json else { throw Failure.unreadableSettings }
        return json
    }

    static func status(files: [URL]) -> AgentHookStatus {
        let statuses = files.compactMap { try? status(of: read($0)) }
        if statuses.contains(.installed(removable: true)) { return .installed(removable: true) }
        if statuses.contains(.installed(removable: false)) { return .installed(removable: false) }
        return .notInstalled
    }

    static func install(files: [URL]) throws { try edit(files, installing(into:)) }
    static func uninstall(files: [URL]) throws { try edit(files, removing(from:)) }

    /// Reads right before writing, keeps a one-time backup of the user's original, writes atomically.
    /// Every file is read and checked before the first write, so one unreadable file changes nothing.
    private static func edit(_ files: [URL], _ transform: (OrderedJSON) -> OrderedJSON) throws {
        let plans = try files.map { file -> (URL, OrderedJSON, OrderedJSON) in
            let current = try read(file)
            return (file, current, transform(current))
        }
        let fm = FileManager.default
        for (link, current, updated) in plans where updated != current {
            // An atomic write replaces the path, so write through a symlink (a dotfiles repo) instead.
            let file = link.resolvingSymlinksInPath()
            do {
                try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                let backup = file.appendingPathExtension("poketokenbar-backup")
                if fm.fileExists(atPath: file.path), !fm.fileExists(atPath: backup.path) {
                    try fm.copyItem(at: file, to: backup)
                }
                try Data(updated.serialized().utf8).write(to: file, options: .atomic)
            } catch {
                throw Failure.writeFailed
            }
        }
    }
}
