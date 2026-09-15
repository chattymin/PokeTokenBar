import XCTest
@testable import PokeTokenBar

final class RemoteUsageTests: XCTestCase {
    private var createdDirectories: [URL] = []

    override func tearDownWithError() throws {
        for url in createdDirectories {
            try? FileManager.default.removeItem(at: url)
        }
        createdDirectories.removeAll()
        try super.tearDownWithError()
    }

    func testRemoteMachinesPersistInProviderScopedDefaultsKey() throws {
        let suite = "ptb.remote.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let machine = RemoteMachine(
            id: "m1", label: "M1", sshTarget: "m1.local", remoteHome: "/Users/me",
            providerIDs: ["pi", "omp"])
        RemoteUsage.save([machine], defaults: defaults)

        XCTAssertEqual(RemoteUsage.load(defaults: defaults), [machine])
        XCTAssertNotNil(defaults.data(forKey: RemoteUsage.defaultsKey))
        XCTAssertNil(defaults.string(forKey: "customScanRoots"), "remote sync must not revive the old shared scan-roots key")
    }

    func testImportedRootsExposeCopiedRootChildrenPerProvider() throws {
        let machine = RemoteMachine(id: "m1 test", label: "M1", sshTarget: "m1.local", providerIDs: ["pi"])
        let providerDir = RemoteUsage.providerDirectory(machineID: machine.id, providerID: "pi")
        createdDirectories.append(providerDir.deletingLastPathComponent())
        let first = providerDir.appendingPathComponent("root-0", isDirectory: true)
        let second = providerDir.appendingPathComponent("root-1", isDirectory: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)

        let roots = RemoteUsage.importedRoots(for: "pi", machines: [machine]).map(\.lastPathComponent)
        XCTAssertEqual(roots, ["root-0", "root-1"])
        XCTAssertTrue(RemoteUsage.importedRoots(for: "omp", machines: [machine]).isEmpty)
    }

    func testProviderRootsIncludeEnabledRemoteMirrors() throws {
        let old = UserDefaults.standard.data(forKey: RemoteUsage.defaultsKey)
        defer {
            if let old { UserDefaults.standard.set(old, forKey: RemoteUsage.defaultsKey) }
            else { UserDefaults.standard.removeObject(forKey: RemoteUsage.defaultsKey) }
        }

        let machine = RemoteMachine(id: "roots-test", label: "M1", sshTarget: "m1.local", providerIDs: ["pi"])
        let providerDir = RemoteUsage.providerDirectory(machineID: machine.id, providerID: "pi")
        createdDirectories.append(providerDir.deletingLastPathComponent())
        let copiedRoot = providerDir.appendingPathComponent("root-0", isDirectory: true)
        try FileManager.default.createDirectory(at: copiedRoot, withIntermediateDirectories: true)
        RemoteUsage.save([machine])

        let roots = LocalUsageReader.piSessionRoots.map(\.path)
        XCTAssertTrue(roots.contains(copiedRoot.path), "Pi reader did not include imported remote root")
        XCTAssertFalse(LocalUsageReader.ompSessionRoots.map(\.path).contains(copiedRoot.path),
                       "remote roots must remain provider-scoped")
    }

    func testLocalPiProviderCountsImportedRemoteRoot() async throws {
        let machine = RemoteMachine(id: "provider-test", label: "M1", sshTarget: "m1.local", providerIDs: ["pi"])
        let providerDir = RemoteUsage.providerDirectory(machineID: machine.id, providerID: "pi")
        createdDirectories.append(providerDir.deletingLastPathComponent())
        let copiedRoot = providerDir.appendingPathComponent("root-0", isDirectory: true)
        try FileManager.default.createDirectory(at: copiedRoot, withIntermediateDirectories: true)
        let line = try piMessageLine(id: "remote-turn", input: 100, output: 23)
        try line.write(to: copiedRoot.appendingPathComponent("session.jsonl"), atomically: true, encoding: .utf8)

        let cacheFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("PokeTokenBar-RemoteUsageTests-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: cacheFile) }
        let provider = LocalPiProvider(cache: LocalUsageCache(piRoots: RemoteUsage.importedRoots(for: "pi", machines: [machine]), fileURL: cacheFile))

        let fetched = try await provider.fetchDaily()
        let daily = try XCTUnwrap(fetched)
        XCTAssertEqual(daily.totalTokens, 123)
    }

    func testImporterBuildsSafeRsyncArguments() {
        let importer = RemoteUsageImporter()
        let args = importer.rsyncArguments(
            sshTarget: "m1.local",
            remoteRoot: "~/Library/Application Support/Cursor/User/globalStorage",
            destination: URL(fileURLWithPath: "/tmp/ptb remote"),
            providerID: "cursor")

        XCTAssertTrue(args.contains("/state.vscdb"), "single-db providers copy only their database")
        XCTAssertTrue(args.contains("/*"), "runtime tree must not be walked or transferred")
        XCTAssertFalse(args.contains("--ignore-missing-args"), "macOS openrsync does not support the GNU-only flag")
        XCTAssertFalse(args.contains("--delete"))
        XCTAssertTrue(args.contains("ssh -o BatchMode=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=2"))
        XCTAssertTrue(args.contains("m1.local:\"$HOME/Library/Application Support/Cursor/User/globalStorage\"/"),
                      "tilde must become $HOME inside double quotes; single quotes freeze it (observed openrsync bug)")
        XCTAssertEqual(args.last, "/tmp/ptb remote/")
    }

    func testProbeArgumentsExpandHomeAndQuoteSpaces() {
        let importer = RemoteUsageImporter()
        let args = importer.sshProbeArguments(
            sshTarget: "m1",
            remoteRoots: ["~/.pi/agent/sessions", "~/Library/Application Support/Cursor/User/globalStorage"])
        XCTAssertEqual(args.first, "-o")
        XCTAssertTrue(args.contains("m1"))
        let command = args.last ?? ""
        XCTAssertTrue(command.contains("\"$HOME/.pi/agent/sessions\""))
        XCTAssertTrue(command.contains("\"$HOME/Library/Application Support/Cursor/User/globalStorage\""))
    }

    func testImporterSkipsProvidersWithoutRemoteRootsAndImportsExistingOnes() async throws {
        final class ScriptedRunner: RemoteUsageRunning, @unchecked Sendable {
            var commands: [[String]] = []
            func run(_ binary: String, _ arguments: [String], timeout: TimeInterval) async throws -> String {
                commands.append([binary] + arguments)
                if binary == "/usr/bin/ssh" {
                    return arguments.last?.contains("$HOME/.pi/agent/sessions") == true ? "0\n" : ""
                }
                return ""
            }
        }
        let runner = ScriptedRunner()
        let importer = RemoteUsageImporter(runner: runner, rsyncPath: "/usr/bin/rsync")
        let machine = RemoteMachine(id: "probe", label: "M1", sshTarget: "m1", providerIDs: ["pi", "claude_code"])
        let result = await importer.importUsage(from: machine)
        XCTAssertEqual(result.importedProviderIDs, ["pi"], "claude_code has no remote root on m1 → skipped silently")
        XCTAssertNil(result.errorDescription)
        // One probe per provider (2), one rsync for the single existing pi root.
        XCTAssertEqual(runner.commands.filter { $0[0] == "/usr/bin/rsync" }.count, 1)
        let rsyncArgs = try XCTUnwrap(runner.commands.first { $0[0] == "/usr/bin/rsync" })
        XCTAssertTrue(rsyncArgs.contains("m1:\"$HOME/.pi/agent/sessions\"/"))
    }

    func testImporterReportsMissingRsyncWithoutTouchingRemote() async {
        let importer = RemoteUsageImporter(runner: RecordingRemoteRunner(), rsyncPath: "/definitely/missing/rsync")
        let result = await importer.importUsage(from: RemoteMachine(
            id: "missing-rsync", label: "M1", sshTarget: "m1.local", providerIDs: ["pi"]))
        XCTAssertEqual(result.importedProviderIDs, [])
        XCTAssertEqual(result.errorDescription, RemoteUsageImporter.ImportError.missingRsync.description)
    }
    private func piMessageLine(id: String, input: Int, output: Int) throws -> String {
        let object: [String: Any] = [
            "type": "message",
            "id": id,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "message": [
                "role": "assistant",
                "model": "gpt-test",
                "usage": ["input": input, "output": output, "cacheWrite": 0, "cacheRead": 0],
            ],
        ]
        return String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }
}

private struct RecordingRemoteRunner: RemoteUsageRunning {
    func run(_ binary: String, _ arguments: [String], timeout: TimeInterval) async throws -> String {
        XCTFail("runner should not be called when rsync is missing")
        return ""
    }
}
