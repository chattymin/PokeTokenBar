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

    private func spec(_ layout: AgentHookLayout, owns: Bool = false, file: URL? = nil, stdout: String? = nil,
                      entries: [AgentHookEntry] = [AgentHookEntry("Stop", "done")]) -> AgentHookFile {
        let file = file ?? dir.appendingPathComponent("hooks.json")
        return AgentHookFile(agentID: "toy", agentName: "Toy", files: { [file] }, ownsFile: owns, layout: layout,
                             entries: entries, labelKeys: ["cwd", "workspace_roots", "$TOY_PROJECT_DIR"],
                             stdout: stdout, isAvailable: { true }, approval: nil)
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

    func testStdoutReplyIsPrinted() throws {
        let command = spec(Self.flat, stdout: "{}").command(for: AgentHookEntry("stop", "done"))
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

    func testGroupsInANamedBucket() throws {
        let toy = spec(.groups(root: "poketokenbar"), entries: [AgentHookEntry("Stop", "done")])
        let other = try OrderedJSON(parsing: Data(#"{"mine":{"Stop":[{"hooks":[{"type":"command","command":"say hi"}]}]}}"#.utf8))
        let installed = toy.installing(into: other)
        guard case .object(let members) = installed else { return XCTFail() }
        XCTAssertEqual(members.map(\.key), ["mine", "poketokenbar"])
        XCTAssertEqual(toy.removing(from: installed), other)
        XCTAssertEqual(toy.status(of: other), .notInstalled)
    }

    func testCommentedConfigIsRefused() throws {
        let file = dir.appendingPathComponent("settings.json")
        try Data("{ // mine\n}".utf8).write(to: file)
        XCTAssertThrowsError(try spec(.groups(root: "hooks"), file: file).install())
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "{ // mine\n}")
    }
}
