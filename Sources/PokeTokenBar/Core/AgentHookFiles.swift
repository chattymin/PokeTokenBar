import Foundation

/// One hook the app adds to an agent's own hook config. The hook command decides the pet state
/// from the hook's JSON payload with `rule` (see `AgentHookFile.command`).
struct AgentHookEntry: Equatable, Sendable {
    let event: String
    /// Written only for layouts with matcher groups; nil leaves it out.
    let matcher: String?
    /// `field:value=state,…,*=state` clauses separated by `;`, tried in order; a bare word is a
    /// fixed state. `skip` sends nothing. Booleans read as `1`/`0`; a missing field as empty.
    let rule: String

    init(_ event: String, matcher: String? = nil, _ rule: String) {
        self.event = event
        self.matcher = matcher
        self.rule = rule
    }
}

/// How an agent nests hook entries in its JSON config.
enum AgentHookLayout: Equatable, Sendable {
    /// Claude Code's shape: `{<root>: {Event: [{"matcher"?, "hooks": [{"type": "command", "command"}]}]}}`.
    case groups(root: String)
    /// `{<header…>, <root>: {event: [{<commandKey>: …, <extra…>}]}}` (Copilot, Cursor).
    case flat(root: String, commandKey: String, extra: [String: OrderedJSONScalar], header: [String: OrderedJSONScalar])
}

/// A JSON scalar for fixed keys in a layout (`"version": 1`, `"type": "command"`), kept `Equatable`
/// and `Sendable` without carrying a whole `OrderedJSON` tree.
enum OrderedJSONScalar: Equatable, Sendable {
    case string(String)
    case number(String)

    var json: OrderedJSON {
        switch self {
        case .string(let s): .string(s)
        case .number(let n): .number(n)
        }
    }
}

/// An agent's hook config as data: where it lives, its shape, and what the app adds. Generic over
/// agents; each agent's file only fills this in (see `Core/AgentSources`).
struct AgentHookFile: Sendable {
    let agentID: String
    let agentName: String
    /// The files to edit. Usually one; several when the agent reads several user configs.
    let files: @Sendable () -> [URL]
    /// The file is the app's alone (a hooks folder the agent scans): uninstall deletes it.
    let ownsFile: Bool
    let layout: AgentHookLayout
    let entries: [AgentHookEntry]
    /// Where the hook finds the working folder: payload keys first (an array uses its first
    /// item), then `$NAME` environment variables.
    let labelKeys: [String]
    /// Printed after the URL is sent, for agents that read a hook's stdout as a reply.
    let stdout: String?
    /// Whether the agent looks installed on this Mac (its data folder exists), so Settings and
    /// the offer only mention agents the person uses.
    let isAvailable: @Sendable () -> Bool
    /// Set when the agent runs a new hook only after the person approves it in the agent.
    let approval: String?

    static let marker = ClaudeAgentHooks.marker

    // MARK: Command

    /// Reads the payload with the `perl` and `JSON::PP` that ship with macOS, picks a state with the
    /// entry's rule, takes the folder name, percent-encodes it (as UTF-8) and opens the URL. No script
    /// file to leave behind; `pgrep` keeps a hook from relaunching a quit app; always exits 0.
    /// The script has no single quotes, so it sits inside one single-quoted shell word.
    static let script = #"my($a,$r,@k)=@ARGV;my $i=do{local $/;<STDIN>};my $j=eval{decode_json($i)};$j={} unless ref $j eq "HASH";my $s="";for my $p(split /;/,$r){if($p=~/^(\w+):(.*)$/){my($f,$l)=($1,$2);my $v=$j->{$f};$v="" unless defined $v;$v=$v?"1":"0" if JSON::PP::is_bool($v);my %m=map{split /=/,$_,2}split /,/,$l;if(exists $m{$v}){$s=$m{$v};last}if(exists $m{"*"}){$s=$m{"*"};last}}else{$s=$p;last}}exit 0 if $s eq "" or $s eq "skip";my $d="";for my $x(@k){my $v=$x=~/^\$(\w+)$/?$ENV{$1}:$j->{$x};$v=$v->[0] if ref $v eq "ARRAY";if(defined $v and !ref $v and length $v){$d=$v;last}}$d=~s{/+$}{};$d=~s{^.*/}{};utf8::encode($d) if utf8::is_utf8($d);$d=~s/([^A-Za-z0-9._~-])/sprintf("%%%02X",ord $1)/ge;system("open","-g","poketokenbar://agent?state=$s&agent=$a&label=$d");"#

    func command(for entry: AgentHookEntry) -> String {
        let words = ([agentID, entry.rule] + labelKeys).map { "'" + $0 + "'" }.joined(separator: " ")
        let reply = stdout.map { "printf '%s' '" + $0 + "'; " } ?? ""
        return "pgrep -xq PokeTokenBar && perl -MJSON::PP -e '" + Self.script + "' " + words
            + " >/dev/null 2>&1; " + reply + "exit 0 " + Self.marker
    }

    // MARK: Pure edits

    private var root: String {
        switch layout {
        case .groups(let root), .flat(let root, _, _, _): root
        }
    }

    private var commandKey: String {
        if case .flat(_, let key, _, _) = layout { return key }
        return "command"
    }

    /// Every command in the config's hook entries, in either layout.
    private func commands(in config: OrderedJSON) -> [String] {
        guard case .object(let events)? = config[root] else { return [] }
        let entries = events.flatMap { $0.value.arrayValue ?? [] }
        let nested = entries.flatMap { $0["hooks"]?.arrayValue ?? [] }
        return (entries + nested).compactMap { $0[commandKey]?.stringValue ?? $0["command"]?.stringValue }
    }

    func status(of config: OrderedJSON) -> AgentHookStatus {
        let commands = commands(in: config)
        guard commands.contains(where: { $0.contains("poketokenbar://agent") || $0.hasSuffix(Self.marker) })
        else { return .notInstalled }
        return .installed(removable: commands.contains { $0.hasSuffix(Self.marker) })
    }

    /// Adds the app's hooks after whatever is there. Idempotent: earlier app entries are replaced.
    func installing(into config: OrderedJSON) -> OrderedJSON {
        var config = removing(from: config)
        if case .flat(_, _, _, let header) = layout {
            for (key, value) in header.sorted(by: { $0.key < $1.key }) where config[key] == nil {
                config.set(key, value.json)
            }
        }
        var events = config[root] ?? .object([])
        if case .object = events {} else { events = .object([]) }
        for entry in entries {
            var list = events[entry.event]?.arrayValue ?? []
            switch layout {
            case .groups:
                var group: [(key: String, value: OrderedJSON)] = []
                if let matcher = entry.matcher { group.append(("matcher", .string(matcher))) }
                group.append(("hooks", .array([.object([
                    ("type", .string("command")),
                    ("command", .string(command(for: entry))),
                ])])))
                list.append(.object(group))
            case .flat(_, let key, let extra, _):
                var item: [(key: String, value: OrderedJSON)] = [(key, .string(command(for: entry)))]
                item += extra.sorted(by: { $0.key < $1.key }).map { ($0.key, $0.value.json) }
                list.append(.object(item))
            }
            events.set(entry.event, .array(list))
        }
        config.set(root, events)
        return config
    }

    /// Drops only the app's own entries, then whatever that leaves empty.
    func removing(from config: OrderedJSON) -> OrderedJSON {
        guard case .object(let events)? = config[root] else { return config }
        func isApp(_ item: OrderedJSON) -> Bool { (item[commandKey]?.stringValue ?? "").hasSuffix(Self.marker) }
        var changed = false
        var kept: [(key: String, value: OrderedJSON)] = []
        for (event, value) in events {
            guard let list = value.arrayValue else { kept.append((event, value)); continue }
            var newList: [OrderedJSON] = []
            for item in list {
                if case .groups = layout, let hooks = item["hooks"]?.arrayValue {
                    let remaining = hooks.filter { !(($0["command"]?.stringValue)?.hasSuffix(Self.marker) ?? false) }
                    if remaining.count == hooks.count { newList.append(item); continue }
                    changed = true
                    guard !remaining.isEmpty else { continue }
                    var g = item
                    g.set("hooks", .array(remaining))
                    newList.append(g)
                } else if isApp(item) {
                    changed = true
                } else {
                    newList.append(item)
                }
            }
            if !newList.isEmpty || list.isEmpty { kept.append((event, .array(newList))) }
        }
        guard changed else { return config }
        var config = config
        config.set(root, kept.isEmpty ? nil : .object(kept))
        return config
    }

    // MARK: Files

    func status() -> AgentHookStatus {
        let statuses = files().compactMap { try? status(of: AgentSettingsFile.read($0)) }
        if statuses.contains(.installed(removable: true)) { return .installed(removable: true) }
        if statuses.contains(.installed(removable: false)) { return .installed(removable: false) }
        return .notInstalled
    }

    func install() throws {
        try AgentSettingsFile.edit(files(), installing(into:))
    }

    /// An owned file goes away once nothing but the layout's header is left in it.
    func uninstall() throws {
        try AgentSettingsFile.edit(files(), removing(from:))
        guard ownsFile else { return }
        for file in files() {
            guard let config = try? AgentSettingsFile.read(file), case .object(let members) = config else { continue }
            var headerKeys: Set<String> = []
            if case .flat(_, _, _, let header) = layout { headerKeys = Set(header.keys) }
            if members.allSatisfy({ headerKeys.contains($0.key) }) {
                try? FileManager.default.removeItem(at: file.resolvingSymlinksInPath())
            }
        }
    }

    var integration: AgentHookIntegration {
        let spec = self
        return AgentHookIntegration(
            agentName: agentName,
            settingsDescription: {
                spec.files().map { $0.path.replacingOccurrences(of: NSHomeDirectory(), with: "~") }.joined(separator: ", ")
            },
            status: { spec.status() },
            install: { try spec.install() },
            uninstall: { try spec.uninstall() },
            id: agentID,
            isAvailable: { spec.isAvailable() },
            approval: approval)
    }
}

/// Reading and safely rewriting an agent's JSON config (shared with `ClaudeAgentHooks`).
enum AgentSettingsFile {
    /// A missing or blank file is an empty object; anything that is not a JSON object (JSONC
    /// comments included) is refused, so the app never rewrites a file it cannot read exactly.
    static func read(_ file: URL) throws -> OrderedJSON {
        guard let data = FileManager.default.contents(atPath: file.path) else { return .object([]) }
        if data.allSatisfy({ [0x20, 0x09, 0x0A, 0x0D].contains($0) }) { return .object([]) }
        guard let json = try? OrderedJSON(parsing: data), case .object = json else {
            throw ClaudeAgentHooks.Failure.unreadableSettings
        }
        return json
    }

    /// Every file is read and checked before the first write, so one unreadable file changes
    /// nothing. Writes through a symlink (dotfiles), keeps a one-time backup, writes atomically.
    static func edit(_ files: [URL], _ transform: (OrderedJSON) -> OrderedJSON) throws {
        let plans = try files.map { file -> (URL, OrderedJSON, OrderedJSON) in
            let current = try read(file)
            return (file, current, transform(current))
        }
        let fm = FileManager.default
        for (link, current, updated) in plans where updated != current {
            let file = link.resolvingSymlinksInPath()
            do {
                try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                let backup = file.appendingPathExtension("poketokenbar-backup")
                if fm.fileExists(atPath: file.path), !fm.fileExists(atPath: backup.path) {
                    try fm.copyItem(at: file, to: backup)
                }
                try Data(updated.serialized().utf8).write(to: file, options: .atomic)
            } catch {
                throw ClaudeAgentHooks.Failure.writeFailed
            }
        }
    }
}
