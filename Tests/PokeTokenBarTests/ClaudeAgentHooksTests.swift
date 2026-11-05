import XCTest
@testable import PokeTokenBar

final class OrderedJSONTests: XCTestCase {
    private func parse(_ s: String) throws -> OrderedJSON { try OrderedJSON(parsing: Data(s.utf8)) }

    func testRoundTripKeepsOrderNumbersAndText() throws {
        let text = """
        {
          "zeta": 1,
          "alpha": {
            "b": [
              1.50,
              -2e3,
              true,
              null
            ],
            "a": "한글 \\"quoted\\" \\\\ tab\\t 😀"
          },
          "empty": {},
          "list": []
        }

        """
        let json = try parse(text)
        XCTAssertEqual(json.serialized(), text, "untouched input comes back byte for byte")
        guard case .object(let members) = json else { return XCTFail() }
        XCTAssertEqual(members.map(\.key), ["zeta", "alpha", "empty", "list"])
    }

    func testEscapesDecode() throws {
        XCTAssertEqual(try parse(#""\u00e9\ud83d\ude00\/""#), .string("é😀/"))
        XCTAssertEqual(OrderedJSON.quoted("a\u{01}b"), #""a\u0001b""#)
    }

    func testRejectsWhatIsNotJSON() {
        for bad in ["", "{", "{\"a\":}", "[1,]", "{\"a\" 1}", "01", "\"\\ud83d\"", "{} x", "// comment\n{}", "\"tab\there\""] {
            XCTAssertThrowsError(try parse(bad), bad)
        }
        let deep = String(repeating: "[", count: 10_000) + String(repeating: "]", count: 10_000)
        XCTAssertThrowsError(try parse(deep), "bounded depth instead of a stack overflow")
    }

    func testBOMIsAccepted() throws {
        XCTAssertEqual(try OrderedJSON(parsing: Data([0xEF, 0xBB, 0xBF] + Array("{}".utf8))), .object([]))
    }

    func testSetReplacesInPlaceAppendsAndRemoves() throws {
        var json = try parse(#"{"a":1,"b":2,"a":3}"#)
        json.set("a", .number("9"))
        XCTAssertEqual(json.serialized(), "{\n  \"a\": 9,\n  \"b\": 2\n}\n", "first position kept, duplicate dropped")
        json.set("c", .bool(true))
        json.set("b", nil)
        XCTAssertEqual(json.serialized(), "{\n  \"a\": 9,\n  \"c\": true\n}\n")
    }
}

final class ClaudeAgentHooksTests: XCTestCase {
    private typealias H = ClaudeAgentHooks
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("ClaudeAgentHooksTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func parse(_ s: String) throws -> OrderedJSON { try OrderedJSON(parsing: Data(s.utf8)) }

    private func commands(_ json: OrderedJSON, _ event: String) -> [String] {
        (json["hooks"]?[event]?.arrayValue ?? []).flatMap { $0["hooks"]?.arrayValue ?? [] }
            .compactMap { $0["command"]?.stringValue }
    }

    func testInstallIntoEmptySettingsAddsEveryEvent() throws {
        let json = H.installing(into: .object([]))
        for hook in H.hooks {
            XCTAssertEqual(commands(json, hook.event), [H.command(state: hook.state)], hook.event)
            XCTAssertEqual(json["hooks"]?[hook.event]?.arrayValue?.first?["matcher"]?.stringValue, hook.matcher)
        }
        XCTAssertEqual(H.status(of: json), .installed(removable: true))
    }

    /// The person's own hooks and every other setting survive install and uninstall unchanged.
    func testOtherSettingsAndHooksAreKept() throws {
        let original = try parse("""
        {
          "permissions": {"allow": ["Bash"]},
          "hooks": {
            "Stop": [{"hooks": [{"type": "command", "command": "say done"}]}],
            "PreCompact": [{"hooks": [{"type": "command", "command": "echo compact"}]}]
          },
          "theme": "auto"
        }
        """)
        let installed = H.installing(into: original)
        XCTAssertEqual(commands(installed, "Stop"), ["say done", H.command(state: "done")])
        XCTAssertEqual(commands(installed, "PreCompact"), ["echo compact"])
        guard case .object(let members) = installed else { return XCTFail() }
        XCTAssertEqual(members.map(\.key), ["permissions", "hooks", "theme"])

        XCTAssertEqual(H.installing(into: installed), installed, "installing twice adds nothing")
        XCTAssertEqual(H.removing(from: installed), original, "uninstall restores the original exactly")
    }

    func testRemovingFromSettingsWithoutHooksChangesNothing() throws {
        let json = try parse(#"{"theme":"auto"}"#)
        XCTAssertEqual(H.removing(from: json), json)
        let emptied = H.removing(from: H.installing(into: json))
        XCTAssertEqual(emptied, json, "an app-only hooks object goes away entirely")
    }

    /// The README's manual setup is detected, and never removed by the app.
    func testHandWrittenHooksCountButStay() throws {
        let manual = try parse(#"{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"sh ~/.claude/poketokenbar.sh done || true"}]}]}}"#)
        XCTAssertEqual(H.status(of: manual), .installed(removable: false))
        XCTAssertEqual(H.removing(from: manual), manual)
        XCTAssertEqual(H.status(of: .object([])), .notInstalled)
    }

    func testFilesAreWrittenSafely() throws {
        let settings = dir.appendingPathComponent("settings.json")
        let original = "{\n  \"theme\": \"auto\"\n}\n"
        try Data(original.utf8).write(to: settings)

        try H.install(files: [settings])
        XCTAssertEqual(H.status(files: [settings]), .installed(removable: true))
        let backup = settings.appendingPathExtension("poketokenbar-backup")
        XCTAssertEqual(try String(contentsOf: backup, encoding: .utf8), original, "the person's original is kept")

        try H.uninstall(files: [settings])
        XCTAssertEqual(try String(contentsOf: settings, encoding: .utf8), original)
        XCTAssertEqual(H.status(files: [settings]), .notInstalled)
    }

    func testMissingFileIsCreated() throws {
        let settings = dir.appendingPathComponent("new/settings.json")
        try H.install(files: [settings])
        XCTAssertEqual(H.status(files: [settings]), .installed(removable: true))
    }

    /// One broken file: nothing is written anywhere, the broken file keeps its bytes.
    func testUnreadableSettingsAreNeverTouched() throws {
        let good = dir.appendingPathComponent("a.json")
        let bad = dir.appendingPathComponent("b.json")
        try Data("{}".utf8).write(to: good)
        try Data("{ \"theme\": \"auto\", // trailing comment\n}".utf8).write(to: bad)
        XCTAssertThrowsError(try H.install(files: [good, bad])) {
            XCTAssertEqual($0 as? H.Failure, .unreadableSettings)
        }
        XCTAssertEqual(try String(contentsOf: good, encoding: .utf8), "{}")
        XCTAssertEqual(try String(contentsOf: bad, encoding: .utf8), "{ \"theme\": \"auto\", // trailing comment\n}")
        try Data("[1]".utf8).write(to: good)
        XCTAssertThrowsError(try H.install(files: [good]), "an array is not a settings object")
    }

    /// Dotfiles setups link `settings.json` into a repository; the link must stay a link.
    func testSymlinkedSettingsStayLinked() throws {
        let real = dir.appendingPathComponent("dotfiles-settings.json")
        try Data("{}".utf8).write(to: real)
        let link = dir.appendingPathComponent("settings.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        try H.install(files: [link])
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path), real.path)
        XCTAssertEqual(H.status(files: [real]), .installed(removable: true))
    }

    func testSettingsFilesFollowClaudeConfigDir() {
        let home = URL(fileURLWithPath: "/Users/me")
        XCTAssertEqual(H.settingsFiles(configDirValue: nil, home: home).map(\.path), ["/Users/me/.claude/settings.json"])
        XCTAssertEqual(H.settingsFiles(configDirValue: "/work/claude, /work/claude ,/play", home: home).map(\.path),
                       ["/work/claude/settings.json", "/play/settings.json"])
    }

    /// Runs the exact command text through `sh`, with stand-ins for `pgrep` and `open`, so the
    /// quoting survives JSON and the shell, and the URL parses back to the folder name.
    func testHookCommandOpensAParsableURL() throws {
        let bin = dir.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let captured = dir.appendingPathComponent("opened.txt")
        let stubs = ["pgrep": "exit 0", "open": "printf %s \"$2\" > '\(captured.path)'"]
        for (name, body) in stubs {
            let url = bin.appendingPathComponent(name)
            try Data("#!/bin/sh\n\(body)\n".utf8).write(to: url)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
        let roundTripped = try XCTUnwrap(H.installing(into: .object([])).serialized().data(using: .utf8))
        let stop = try OrderedJSON(parsing: roundTripped)
        let command = try XCTUnwrap(commands(stop, "Stop").first)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        process.environment = ["PATH": bin.path + ":/usr/bin:/bin", "CLAUDE_PROJECT_DIR": "/Users/me/code/my app & 日本"]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)

        let opened = try String(contentsOf: captured, encoding: .utf8)
        XCTAssertEqual(opened, "poketokenbar://agent?state=done&label=my%20app%20%26%20%E6%97%A5%E6%9C%AC")
        let event = try XCTUnwrap(AgentActivityEvent(url: try XCTUnwrap(URL(string: opened))))
        XCTAssertEqual(event.activity, .done(message: nil))
        XCTAssertEqual(event.label, "my app & 日本")
    }

    /// Quit app: `pgrep` fails, nothing is opened, and the hook still succeeds.
    func testHookCommandIsQuietWhenTheAppIsNotRunning() throws {
        let bin = dir.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let marker = dir.appendingPathComponent("opened")
        for (name, body) in ["pgrep": "exit 1", "open": "touch '\(marker.path)'"] {
            let url = bin.appendingPathComponent(name)
            try Data("#!/bin/sh\n\(body)\n".utf8).write(to: url)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", H.command(state: "working")]
        process.environment = ["PATH": bin.path + ":/usr/bin:/bin", "CLAUDE_PROJECT_DIR": "/x/web"]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
    }
}
