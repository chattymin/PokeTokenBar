import Foundation

struct RemoteMachine: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var label: String
    var sshTarget: String
    var remoteHome: String
    var enabled: Bool
    var providerIDs: [String]
    var lastImportAt: Date?
    var lastError: String?

    init(id: String = UUID().uuidString,
         label: String,
         sshTarget: String,
         remoteHome: String = "~",
         enabled: Bool = true,
         providerIDs: [String],
         lastImportAt: Date? = nil,
         lastError: String? = nil) {
        self.id = id
        self.label = label
        self.sshTarget = sshTarget
        self.remoteHome = remoteHome
        self.enabled = enabled
        self.providerIDs = providerIDs
        self.lastImportAt = lastImportAt
        self.lastError = lastError
    }

    var displayName: String { label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? sshTarget : label }
}

enum RemoteUsage {
    static let defaultsKey = "remoteMachines"

    static func load(defaults: UserDefaults = .standard) -> [RemoteMachine] {
        guard let data = defaults.data(forKey: defaultsKey) else { return [] }
        return (try? JSONDecoder().decode([RemoteMachine].self, from: data)) ?? []
    }

    static func save(_ machines: [RemoteMachine], defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(machines) else { return }
        defaults.set(data, forKey: defaultsKey)
    }

    static var baseDirectory: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PokeTokenBar")
            .appendingPathComponent("RemoteUsage", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func importedRoots(for providerID: String, machines: [RemoteMachine]? = nil) -> [URL] {
        let source = machines ?? load()
        let fm = FileManager.default
        var roots: [URL] = []
        for machine in source where machine.enabled && machine.providerIDs.contains(providerID) {
            let providerDir = providerDirectory(machineID: machine.id, providerID: providerID)
            let children = ((try? fm.contentsOfDirectory(
                at: providerDir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles])) ?? [])
                .filter { url in
                    ((try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false)
                    && url.lastPathComponent.hasPrefix("root-")
                }
                .sorted { $0.path < $1.path }
            roots.append(contentsOf: children.isEmpty ? [providerDir] : children)
        }
        return roots
    }

    static func providerDirectory(machineID: String, providerID: String) -> URL {
        baseDirectory
            .appendingPathComponent(safePathComponent(machineID), isDirectory: true)
            .appendingPathComponent(safePathComponent(providerID), isDirectory: true)
    }

    static func safePathComponent(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        let scalars = raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let value = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: ".-"))
        return value.isEmpty ? "remote" : value
    }

    static func remoteRoots(providerID: String, remoteHome: String) -> [String] {
        let home = remoteHome.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "~" : remoteHome
        func path(_ suffix: String) -> String { home == "~" ? "~/\(suffix)" : "\(home)/\(suffix)" }
        switch providerID {
        case "claude_code": return [path(".config/claude/projects"), path(".claude/projects")]
        case "codex": return [path(".codex/sessions"), path(".codex/archived_sessions")]
        case "gemini": return [path(".gemini/tmp")]
        case "antigravity": return [path(".gemini/antigravity/conversations"), path(".gemini/antigravity-cli/conversations"), path(".gemini/antigravity-ide/conversations")]
        case "opencode": return [path(".local/share/opencode")]
        case "hermes": return [path(".hermes")]
        case "cursor": return [path("Library/Application Support/Cursor/User/globalStorage")]
        case "grok": return [path(".grok/sessions")]
        case "copilot": return [path(".copilot")]
        case "kiro": return [path("Library/Application Support/kiro-cli"), path(".kiro")]
        case "pi": return [path(".pi/agent/sessions")]
        case "omp": return [path(".omp/agent/sessions")]
        case "aside": return [path(".aside/u")]
        default: return []
        }
    }
}

struct RemoteUsageImportResult: Sendable, Equatable {
    var importedProviderIDs: [String]
    var errorDescription: String?
}

protocol RemoteUsageRunning {
    func run(_ binary: String, _ arguments: [String], timeout: TimeInterval) async throws -> String
}

struct RemoteUsageProcessRunner: RemoteUsageRunning {
    func run(_ binary: String, _ arguments: [String], timeout: TimeInterval = 20) async throws -> String {
        try await Task.detached(priority: .utility) { () async throws -> String in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: binary)
            process.arguments = arguments
            let out = Pipe()
            let err = Pipe()
            process.standardOutput = out
            process.standardError = err
            try process.run()

            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning && Date() < deadline {
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            if process.isRunning {
                process.terminate()
                throw RemoteUsageImporter.ImportError.timedOut
            }
            let output = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            guard process.terminationStatus == 0 else {
                throw RemoteUsageImporter.ImportError.commandFailed(stderr.isEmpty ? output : stderr)
            }
            return output
        }.value
    }
}

struct RemoteUsageImporter {
    enum ImportError: Error, Equatable, CustomStringConvertible {
        case missingRsync
        case timedOut
        case commandFailed(String)

        var description: String {
            switch self {
            case .missingRsync: return "rsync not found"
            case .timedOut: return "remote import timed out"
            case .commandFailed(let message): return message.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }

    var runner: any RemoteUsageRunning = RemoteUsageProcessRunner()
    var rsyncPath: String = "/usr/bin/rsync"
    /// First import mirrors the remote's whole history (hundreds of MB happen); later
    /// runs are incremental rsync deltas and finish in seconds.
    var timeout: TimeInterval = 600
    var fileManager: FileManager = .default

    func importUsage(from machine: RemoteMachine) async -> RemoteUsageImportResult {
        guard machine.enabled else { return RemoteUsageImportResult(importedProviderIDs: [], errorDescription: nil) }
        guard fileManager.isExecutableFile(atPath: rsyncPath) else {
            return RemoteUsageImportResult(importedProviderIDs: [], errorDescription: ImportError.missingRsync.description)
        }

        var imported: [String] = []
        var errors: [String] = []
        for providerID in machine.providerIDs {
            let remoteRoots = RemoteUsage.remoteRoots(providerID: providerID, remoteHome: machine.remoteHome)
            guard !remoteRoots.isEmpty else { continue }
            let destination = RemoteUsage.providerDirectory(machineID: machine.id, providerID: providerID)
            do {
                try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
            } catch {
                errors.append("\(providerID): \(error.localizedDescription)")
                continue
            }

            // One ssh probe per provider: remote roots that do not exist are skipped
            // silently (a Mac without Claude Code is normal, not an error), so failed
            // imports do not spam Settings or re-run every refresh. A failed probe
            // falls back to trying every root so an ssh hiccup cannot hide usage.
            let indices: [Int]
            if let output = try? await runner.run(
                "/usr/bin/ssh",
                sshProbeArguments(sshTarget: machine.sshTarget, remoteRoots: remoteRoots),
                timeout: 10) {
                indices = output.split(separator: "\n").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                guard !indices.isEmpty else { continue }
            } else {
                indices = Array(remoteRoots.indices)
            }

            var providerImported = false
            for index in indices {
                let target = destination.appendingPathComponent("root-\(index)", isDirectory: true)
                do {
                    try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
                    // openrsync occasionally exits non-zero with empty diagnostics
                    // (observed on m1: intermittent stat/hangup errors); one retry
                    // settles it without surfacing noise to Settings.
                    var lastError: Error?
                    for _ in 0..<2 {
                        do {
                            _ = try await runner.run(rsyncPath, rsyncArguments(sshTarget: machine.sshTarget, remoteRoot: remoteRoots[index], destination: target, providerID: providerID), timeout: timeout)
                            lastError = nil
                            break
                        } catch {
                            lastError = error
                        }
                    }
                    if let lastError { throw lastError }
                    providerImported = true
                } catch let error as ImportError {
                    errors.append("\(providerID): \(error.description)")
                } catch {
                    errors.append("\(providerID): \(error.localizedDescription)")
                }
            }
            if providerImported { imported.append(providerID) }
        }
        return RemoteUsageImportResult(
            importedProviderIDs: imported,
            errorDescription: errors.isEmpty ? nil : errors.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                .joined(separator: " / "))
    }

    func rsyncArguments(sshTarget: String, remoteRoot: String, destination: URL, providerID: String? = nil) -> [String] {
        var args: [String] = ["-az", "--prune-empty-dirs"]
        // Providers whose reader consumes exactly one database: copy that file and
        // nothing else, so a 2.4GB runtime tree (m1's ~/.hermes) is neither walked
        // nor transferred. First-match wins, so these come before the generic filters.
        if let single = providerID.flatMap(Self.singleFileInclude(for:)) {
            args += ["--include", single, "--exclude", "/*"]
        }
        args += [
            "--include", "*/",
            "--include", "*.json",
            "--include", "*.jsonl",
            "--include", "*.db",
            "--include", "*.sqlite",
            "--include", "*.sqlite3",
            "--exclude", "*",
            "-e", "ssh -o BatchMode=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=2",
            "\(sshTarget):\(Self.remoteShellQuote(remoteRoot))/",
            destination.path + "/",
        ]
        return args
    }

    /// Providers whose local reader reads exactly one database file from their root.
    /// Includes precede the generic patterns and a `/*` exclude keeps rsync from
    /// descending into runtime dirs (measured: ~/.hermes is 2.4GB of runtime, 153MB state.db).
    static func singleFileInclude(for providerID: String) -> String? {
        switch providerID {
        case "hermes": return "/state.db"
        case "cursor": return "/state.vscdb"
        case "copilot": return "/session-store.db"
        default: return nil
        }
    }

    /// One ssh per provider: echo the *indices* of the roots that exist remotely —
    /// indices avoid comparing expanded paths (the remote `$HOME` is unknown locally).
    /// Entries use `$HOME` (tilde does not expand inside quotes).
    func sshProbeArguments(sshTarget: String, remoteRoots: [String]) -> [String] {
        let loop = remoteRoots.map { "\"\(Self.homeExpanded($0))\"" }.joined(separator: " ")
        return [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=5",
            sshTarget,
            "set -- \(loop); n=0; for d in \"$@\"; do [ -d \"$d\" ] && printf '%s\\n' \"$n\"; n=$((n+1)); done",
        ]
    }

    /// Rewrite a leading `~` to `$HOME` so the path still expands inside double quotes.
    static func homeExpanded(_ path: String) -> String {
        path.hasPrefix("~") ? "$HOME" + path.dropFirst() : path
    }

    /// Remote path for rsync's host:path form. Tilde does not expand inside single
    /// quotes, so `~` is rewritten to `$HOME` and the whole path is wrapped in double
    /// quotes — `$HOME` expands and spaces stay protected (observed: macOS openrsync
    /// stat'ed a literal `~/...` when the path was single-quoted).
    static func remoteShellQuote(_ path: String) -> String {
        "\"" + homeExpanded(path).replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
