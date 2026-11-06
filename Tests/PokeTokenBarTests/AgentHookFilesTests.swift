import XCTest
@testable import PokeTokenBar

final class AgentHookFilesTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("AgentHookFilesTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func spec(_ layout: AgentHookLayout, owns: Bool = false, file: URL? = nil, skipEnv: [String] = [],
                      entries: [AgentHookEntry] = [AgentHookEntry("Stop", "done")]) -> AgentHookFile {
        let file = file ?? dir.appendingPathComponent("hooks.json")
        return AgentHookFile(agentID: "toy", agentName: "Toy", files: { [file] }, ownsFile: owns, layout: layout,
                             entries: entries, labelKeys: ["cwd", "workspace_roots", "env:TOY_PROJECT_DIR"],
                             skipEnv: skipEnv, isAvailable: { true }, approval: nil)
    }

    private static let flat = AgentHookLayout.flat(root: "hooks", commandKey: "bash",
                                                   extra: ["type": .string("command"), "timeoutSec": .number("10")],
                                                   header: ["version": .number("1")])

    /// Runs one hook command through `sh` with `payload` on stdin and a stand-in `open`.
    private func run(_ command: String, payload: String, env: [String: String] = [:]) throws -> (opened: String?, stdout: String) {
        let bin = dir.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let captured = dir.appendingPathComponent("opened-\(UUID().uuidString)")
        for (name, body) in ["pgrep": "exit 0", "open": "printf %s \"$2\" > '\(captured.path)'"] {
            let url = bin.appendingPathComponent(name)
            try Data("#!/bin/sh\n\(body)\n".utf8).write(to: url)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        process.environment = ["PATH": bin.path + ":/usr/bin:/bin"].merging(env) { $1 }
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        try process.run()
        input.fileHandleForWriting.write(Data(payload.utf8))
        try input.fileHandleForWriting.close()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "a hook must never fail the agent")
        let stdout = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return (try? String(contentsOf: captured, encoding: .utf8), stdout)
    }

    /// The command text survives the JSON file and the shell, and the URL parses back.
    func testCommandMapsPayloadsToStates() throws {
        let toy = spec(.groups(root: "hooks"))
        let written = try XCTUnwrap(toy.installing(into: .object([])).serialized().data(using: .utf8))
        let reread = try OrderedJSON(parsing: written)
        let stored = try XCTUnwrap(reread["hooks"]?["Stop"]?.arrayValue?.first?["hooks"]?.arrayValue?.first?["command"]?.stringValue)
        XCTAssertEqual(stored, toy.command(for: AgentHookEntry("Stop", "done")))

        let opened = try XCTUnwrap(run(stored, payload: #"{"cwd":"/Users/me/code/my app & 日本"}"#).opened)
        XCTAssertEqual(opened, "poketokenbar://agent?state=done&agent=toy&label=my%20app%20%26%20%E6%97%A5%E6%9C%AC")
        let event = try XCTUnwrap(AgentActivityEvent(url: try XCTUnwrap(URL(string: opened))))
        XCTAssertEqual(event.activity, .done(message: nil))
        XCTAssertEqual(event.label, "my app & 日本")

        let rule = AgentHookEntry("stop", "fullyIdle:0=working;status:completed=done,*=idle")
        let command = toy.command(for: rule)
        XCTAssertEqual(try run(command, payload: #"{"fullyIdle":false,"status":"completed"}"#).opened?.contains("state=working"), true)
        XCTAssertEqual(try run(command, payload: #"{"fullyIdle":true,"status":"completed"}"#).opened?.contains("state=done"), true)
        XCTAssertEqual(try run(command, payload: #"{"status":"aborted"}"#).opened?.contains("state=idle"), true)

        let notify = toy.command(for: AgentHookEntry("Notification", "notification_type:ToolPermission=waiting,*=skip"))
        XCTAssertNil(try run(notify, payload: #"{"notification_type":"idle"}"#).opened, "skip sends nothing")
        XCTAssertEqual(try run(notify, payload: #"{"notification_type":"ToolPermission"}"#).opened?.contains("state=waiting"), true)
    }

    func testLabelComesFromArraysThenEnvironment() throws {
        let command = spec(.groups(root: "hooks")).command(for: AgentHookEntry("Stop", "done"))
        XCTAssertEqual(try run(command, payload: #"{"workspace_roots":["/w/api/","/w/web"]}"#).opened?.hasSuffix("label=api"), true)
        XCTAssertEqual(try run(command, payload: "not json", env: ["TOY_PROJECT_DIR": "/x/web"]).opened?.hasSuffix("label=web"), true,
                       "no payload: the environment names the folder")
        XCTAssertEqual(try run(command, payload: "{}").opened?.hasSuffix("label="), true)
    }

    /// Grok CLI substitutes or refuses every `$NAME` in a command; Gemini rewrites some.
    func testCommandHasNoDollarSign() {
        let command = spec(.groups(root: "hooks")).command(for: AgentHookEntry("Stop", "reason:end_turn=done,*=skip"))
        XCTAssertFalse(command.contains("$"), command)
    }

    func testPresenceRuleAndOtherAgentsSkip() throws {
        let toy = spec(.groups(root: "hooks"), skipEnv: ["OTHER_AGENT"])
        let command = toy.command(for: AgentHookEntry("Stop", "subagentType:+=skip;reason:end_turn=done,*=skip"))
        XCTAssertNil(try run(command, payload: #"{"subagentType":"explore","reason":"end_turn"}"#).opened)
        XCTAssertEqual(try run(command, payload: #"{"subagentType":"","reason":"end_turn"}"#).opened?.contains("state=done"), true)
        XCTAssertNil(try run(command, payload: #"{"reason":"shutdown"}"#).opened)
        XCTAssertNil(try run(command, payload: #"{"reason":"end_turn"}"#, env: ["OTHER_AGENT": "1"]).opened,
                     "another agent running this hook file sends nothing")
    }

    func testStdoutReplyIsPrinted() throws {
        let command = spec(Self.flat).command(for: AgentHookEntry("stop", "done", stdout: "{}"))
        XCTAssertEqual(try run(command, payload: "{}").stdout, "{}")
    }

    func testFlatLayoutKeepsOtherHooksAndOwnedFilesGoAway() throws {
        let file = dir.appendingPathComponent("own.json")
        let toy = spec(Self.flat, owns: true, file: file, entries: [AgentHookEntry("agentStop", "done")])
        try toy.install()
        let json = try AgentSettingsFile.read(file)
        XCTAssertEqual(json["version"], .number("1"))
        let item = try XCTUnwrap(json["hooks"]?["agentStop"]?.arrayValue?.first)
        XCTAssertEqual(item["type"], .string("command"))
        XCTAssertEqual(item["timeoutSec"], .number("10"))
        XCTAssertEqual(toy.status(), .installed(removable: true))
        try toy.uninstall()
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path), "the app's own file is deleted")
        XCTAssertEqual(toy.status(), .notInstalled)

        let shared = dir.appendingPathComponent("shared.json")
        let original = """
        {
          "version": 1,
          "hooks": {
            "stop": [
              {
                "command": "say done"
              }
            ]
          }
        }

        """
        try Data(original.utf8).write(to: shared)
        let cursorLike = spec(.flat(root: "hooks", commandKey: "command", extra: [:], header: ["version": .number("1")]),
                              file: shared, entries: [AgentHookEntry("stop", "done")])
        try cursorLike.install()
        XCTAssertEqual(try AgentSettingsFile.read(shared)["hooks"]?["stop"]?.arrayValue?.count, 2)
        try cursorLike.uninstall()
        XCTAssertEqual(try String(contentsOf: shared, encoding: .utf8), original, "a shared file returns to its exact bytes")
    }

    func testHandlerListsInANamedBucketWithFields() throws {
        let toy = spec(.flat(root: "poketokenbar", commandKey: "command", extra: ["type": .string("command")], header: [:],
                             rootFields: ["enabled": .bool(true)]))
        let installed = toy.installing(into: .object([]))
        XCTAssertEqual(installed["poketokenbar"]?["enabled"], .bool(true))
        XCTAssertEqual(installed["poketokenbar"]?["Stop"]?.arrayValue?.first?["type"], .string("command"))
        XCTAssertEqual(toy.removing(from: installed), .object([]), "the bucket goes once only its fields are left")
    }

    func testGroupsInANamedBucket() throws {
        let toy = spec(.groups(root: "poketokenbar"), entries: [AgentHookEntry("Stop", "done")])
        let other = try OrderedJSON(parsing: Data(#"{"mine":{"Stop":[{"hooks":[{"type":"command","command":"say hi"}]}]}}"#.utf8))
        let installed = toy.installing(into: other)
        guard case .object(let members) = installed else { return XCTFail() }
        XCTAssertEqual(members.map(\.key), ["mine", "poketokenbar"])
        XCTAssertEqual(toy.removing(from: installed), other)
        XCTAssertEqual(toy.status(of: other), .notInstalled)
    }

    func testQuotesInWordsStayOneShellWord() throws {
        XCTAssertEqual(AgentHookFile.quoted("it's"), #"'it'\''s'"#)
        let toy = spec(.groups(root: "hooks"))
        let command = toy.command(for: AgentHookEntry("Stop", "reason:it's=done,*=skip", stdout: "a'b"))
        let result = try run(command, payload: #"{"reason":"it's","cwd":"/x/web"}"#)
        XCTAssertEqual(result.opened?.contains("state=done"), true)
        XCTAssertEqual(result.stdout, "a'b")
    }

    /// Several files: a write that fails part way puts back the files already written.
    func testAFailedWriteLeavesNoFileHalfChanged() throws {
        let first = dir.appendingPathComponent("a/settings.json")
        let locked = dir.appendingPathComponent("b", isDirectory: true)
        try FileManager.default.createDirectory(at: first.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: first)
        try Data("{}".utf8).write(to: locked.appendingPathComponent("settings.json"))
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }
        XCTAssertThrowsError(try AgentSettingsFile.edit([first, locked.appendingPathComponent("settings.json")]) {
            spec(.groups(root: "hooks")).installing(into: $0)
        })
        XCTAssertEqual(try String(contentsOf: first, encoding: .utf8), "{}", "the first file was put back")
    }

    func testCommentedConfigIsRefused() throws {
        let file = dir.appendingPathComponent("settings.json")
        try Data("{ // mine\n}".utf8).write(to: file)
        XCTAssertThrowsError(try spec(.groups(root: "hooks"), file: file).install())
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "{ // mine\n}")
    }
}

/// Each agent's hook description, run for real through `sh` and `perl` with payloads shaped like
/// the agent's docs.
final class AgentHookSpecsTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("AgentHookSpecsTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func command(_ spec: AgentHookFile, _ event: String) throws -> AgentHookEntry {
        try XCTUnwrap(spec.entries.first { $0.event == event }, event)
    }

    /// Returns the opened URL (nil when nothing was sent) and stdout.
    private func run(_ spec: AgentHookFile, _ event: String, payload: String, env: [String: String] = [:],
                     in folder: URL? = nil) throws -> (url: String?, stdout: String) {
        let bin = dir.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let captured = dir.appendingPathComponent("opened-\(UUID().uuidString)")
        for (name, body) in ["pgrep": "exit 0", "open": "printf %s \"$2\" > '\(captured.path)'"] {
            let url = bin.appendingPathComponent(name)
            try Data("#!/bin/sh\n\(body)\n".utf8).write(to: url)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", spec.command(for: try command(spec, event))]
        process.environment = ["PATH": bin.path + ":/usr/bin:/bin"].merging(env) { $1 }
        if let folder { process.currentDirectoryURL = folder }
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        try process.run()
        input.fileHandleForWriting.write(Data(payload.utf8))
        try input.fileHandleForWriting.close()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        return (try? String(contentsOf: captured, encoding: .utf8),
                String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
    }

    private func state(_ url: String?) -> String? {
        url.flatMap { URLComponents(string: $0)?.queryItems?.first { $0.name == "state" }?.value }
    }

    private func label(_ url: String?) -> String? {
        url.flatMap { URLComponents(string: $0)?.queryItems?.first { $0.name == "label" }?.value }
    }

    func testNoCommandHasADollarSign() {
        for spec in [AgentHookFile.codex, .geminiCLI, .grok, .copilotCLI, .cursor, .antigravity] {
            for entry in spec.entries {
                XCTAssertFalse(spec.command(for: entry).contains("$"), "\(spec.agentName) \(entry.event)")
            }
        }
    }

    func testCodex() throws {
        let codex = AgentHookFile.codex
        let config = codex.installing(into: .object([]))
        guard case .object(let top) = config else { return XCTFail() }
        XCTAssertEqual(top.map(\.key), ["hooks"], "only `hooks`: Codex rejects unknown top-level keys")
        // Codex runs the command in the session folder; the shell sets PWD from it.
        let session = dir.appendingPathComponent("web-app", isDirectory: true)
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        let stop = try run(codex, "Stop", payload: #"{"cwd":"/elsewhere/tool","hook_event_name":"Stop"}"#, in: session)
        XCTAssertEqual(state(stop.url), "done")
        XCTAssertEqual(label(stop.url), "web-app", "the session folder, not a tool's cwd")
        XCTAssertEqual(stop.stdout, "", "UserPromptSubmit stdout would reach the model; nothing is printed")
        XCTAssertEqual(state(try run(codex, "PermissionRequest", payload: #"{"cwd":"/x/api"}"#).url), "waiting")
        XCTAssertEqual(state(try run(codex, "Interrupt", payload: "{}").url), "idle")
        XCTAssertEqual(codex.approval, "/hooks")
    }

    func testGeminiCLI() throws {
        let gemini = AgentHookFile.geminiCLI
        XCTAssertEqual(state(try run(gemini, "AfterAgent", payload: #"{"cwd":"/x/web"}"#).url), "done")
        XCTAssertNil(try run(gemini, "Notification", payload: #"{"notification_type":"Other"}"#).url)
        let wait = try run(gemini, "Notification", payload: #"{"notification_type":"ToolPermission","cwd":"/x/web"}"#)
        XCTAssertEqual(state(wait.url), "waiting")
        XCTAssertEqual(label(wait.url), "web")
        XCTAssertEqual(label(try run(gemini, "BeforeAgent", payload: "{}", env: ["GEMINI_PROJECT_DIR": "/x/api"]).url), "api")
    }

    func testGrok() throws {
        let grok = AgentHookFile.grok
        XCTAssertTrue(grok.ownsFile)
        XCTAssertEqual(state(try run(grok, "Stop", payload: #"{"reason":"end_turn","cwd":"/x/web"}"#).url), "done")
        XCTAssertNil(try run(grok, "Stop", payload: #"{"reason":"shutdown"}"#).url, "a session closing is not a turn's end")
        XCTAssertNil(try run(grok, "Stop", payload: #"{"reason":"end_turn","subagentType":"explore"}"#).url)
        XCTAssertEqual(state(try run(grok, "StopCancelled", payload: #"{"reason":"user_interrupt"}"#).url), "idle")
        XCTAssertEqual(state(try run(grok, "Notification", payload: #"{"notificationType":"permission_prompt"}"#).url), "waiting")
        XCTAssertEqual(grok.entries.first { $0.event == "Notification" }?.matcher, "permission_prompt")
    }

    func testCopilotCLI() throws {
        let copilot = AgentHookFile.copilotCLI
        let config = copilot.installing(into: .object([]))
        XCTAssertEqual(config["version"], .number("1"))
        let item = try XCTUnwrap(config["hooks"]?["agentStop"]?.arrayValue?.first)
        XCTAssertNotNil(item["bash"]?.stringValue)
        XCTAssertEqual(item["type"], .string("command"))
        XCTAssertEqual(state(try run(copilot, "agentStop", payload: #"{"cwd":"/x/web","stopReason":"end_turn"}"#).url), "done")
        XCTAssertEqual(state(try run(copilot, "notification", payload: #"{"notification_type":"elicitation_dialog"}"#).url), "waiting")
        XCTAssertNil(try run(copilot, "notification", payload: #"{"notification_type":"agent_completed"}"#).url,
                     "a background agent finishing is not the main turn")
    }

    func testCursor() throws {
        let cursor = AgentHookFile.cursor
        let prompt = try run(cursor, "beforeSubmitPrompt", payload: #"{"workspace_roots":["/x/web"]}"#)
        XCTAssertEqual(state(prompt.url), "working")
        XCTAssertEqual(label(prompt.url), "web")
        XCTAssertEqual(prompt.stdout, #"{"continue":true}"#)
        let stop = try run(cursor, "stop", payload: #"{"status":"aborted"}"#)
        XCTAssertEqual(state(stop.url), "idle")
        XCTAssertEqual(stop.stdout, "{}", "no followup_message")
        XCTAssertEqual(state(try run(cursor, "stop", payload: #"{"status":"completed"}"#).url), "done")
        XCTAssertNil(try run(cursor, "stop", payload: #"{"status":"completed"}"#, env: ["GROK_HOOK_EVENT": "stop"]).url,
                     "Grok runs Cursor's hook file too")
        let events = Set(cursor.entries.map(\.event))
        XCTAssertTrue(events.isDisjoint(with: ["preToolUse", "beforeShellExecution", "beforeMCPExecution", "beforeReadFile"]),
                      "permission hooks block on unexpected output")
    }

    func testAntigravity() throws {
        let antigravity = AgentHookFile.antigravity
        let config = antigravity.installing(into: .object([]))
        XCTAssertEqual(config["poketokenbar"]?["enabled"], .bool(true))
        XCTAssertNotNil(config["poketokenbar"]?["Stop"]?.arrayValue?.first?["command"])
        let more = try run(antigravity, "Stop", payload: #"{"fullyIdle":false,"terminationReason":"model_stop","workspacePaths":["/x/web"]}"#)
        XCTAssertEqual(state(more.url), "working")
        XCTAssertEqual(more.stdout, "{}")
        XCTAssertEqual(state(try run(antigravity, "Stop", payload: #"{"fullyIdle":true,"terminationReason":"model_stop"}"#).url), "done")
        XCTAssertEqual(state(try run(antigravity, "Stop", payload: #"{"fullyIdle":true,"terminationReason":"error"}"#).url), "idle")
    }
}
