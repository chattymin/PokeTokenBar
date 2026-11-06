import XCTest
@testable import PokeTokenBar

/// Transcript lines shaped like Cursor writes them: compact JSON, only `role` + `message`, blocks
/// `text` / `tool_use{name,input}` (no `id`), the prompt wrapped in `<timestamp>` / `<user_query>`.
/// Shapes from the rows quoted in the Cursor forum post "Richer agent transcripts + lifecycle data
/// for observability" (2026-07-24) and the readers cited in `CursorTranscriptActivity`; content is
/// made up. `turnEnded` is the older builds' control row (same sources).
private enum CursorLine {
    static func user(_ text: String) -> String {
        #"{"role":"user","message":{"content":[{"type":"text","text":"<timestamp>Thursday, Jul 23, 2026, 11:20 PM (UTC+9)</timestamp>\n<user_query>\n"#
            + text + #"\n</user_query>"}]}}"#
    }

    static func assistant(_ text: String) -> String {
        #"{"role":"assistant","message":{"content":[{"type":"text","text":""# + text + #""}]}}"#
    }

    static func tool(_ name: String, input: String = #"{"path":"/Users/me/code/web-app/src/app.ts"}"#) -> String {
        #"{"role":"assistant","message":{"content":[{"type":"text","text":"Let me look."},{"type":"tool_use","name":""#
            + name + #"","input":"# + input + "}]}}"
    }

    static let prompt = user("Fix the login bug")
    static let shell = tool("Shell", input: #"{"command":"npm test","working_directory":"/Users/me/code/web-app"}"#)
    static let ask = tool("AskQuestion", input: #"{"questions":[{"id":"scope","prompt":"Which one?","options":[{"id":"a","label":"Login"},{"id":"b","label":"Signup"}]}]}"#)
    static let reply = assistant("Fixed: the session cookie was not refreshed.")
    static let turnEnded = #"{"type":"turn_ended","status":"success"}"#
}

final class CursorTranscriptActivityTests: XCTestCase {
    private func reading(_ lines: String...) -> AgentLogReading? {
        CursorTranscriptActivity.reading(lines: lines.map { Substring($0) })
    }

    func testCurrentTranscriptsOnlyEverSayWorkingOrWaiting() {
        XCTAssertEqual(reading(CursorLine.prompt)?.activity, .working)
        XCTAssertEqual(reading(CursorLine.prompt, CursorLine.shell)?.activity, .working)
        XCTAssertEqual(reading(CursorLine.shell, CursorLine.reply)?.activity, .working,
                       "an assistant text line is the same mid-turn and at the end: never guessed as done")
        XCTAssertEqual(reading(CursorLine.prompt, CursorLine.ask)?.activity, .waiting(message: nil))
        XCTAssertEqual(reading(CursorLine.ask, CursorLine.prompt)?.activity, .working, "answered: back to work")
        XCTAssertEqual(reading(CursorLine.ask, CursorLine.shell)?.activity, .working)
    }

    /// Older builds closed each turn with a control row; that is a real end, so it may say done.
    func testTheOlderTurnEndedRowIsDone() {
        XCTAssertEqual(reading(CursorLine.shell, CursorLine.reply, CursorLine.turnEnded)?.activity, .done(message: nil))
        XCTAssertEqual(reading(CursorLine.turnEnded, CursorLine.prompt)?.activity, .working, "the next turn started")
        XCTAssertEqual(reading(CursorLine.reply, #"{"type":"turn_ended","status":"aborted"}"#)?.activity, .idle,
                       "a turn that did not succeed is over but not news")
        XCTAssertEqual(reading(CursorLine.reply, #"{"type":"turn_ended"}"#)?.activity, .idle)
    }

    func testNoLabelOrLineIDFromLines() throws {
        let result = try XCTUnwrap(reading(CursorLine.ask))
        XCTAssertNil(result.label, "the working folder is not in the lines; a tool's path is not the folder")
        XCTAssertNil(result.lineID, "Cursor writes no ids")
    }

    func testUnrelatedOrBrokenLinesAreSkipped() {
        XCTAssertEqual(reading(CursorLine.ask, "", "not json", #"{"role":"system","message":{"content":[]}}"#)?.activity,
                       .waiting(message: nil))
        XCTAssertEqual(reading(CursorLine.prompt, #"{"role":"assistant"}"#)?.activity, .working,
                       "a role without a message says nothing")
        XCTAssertEqual(reading(CursorLine.prompt, #"{"role":"assistant","message":{"content":[{"type":"tool_use","name":"AskQu"#)?.activity,
                       .working, "a torn line is not a question")
        XCTAssertNil(reading("not json", #"{"type":"something_else"}"#))
    }

    /// A tool input can quote another transcript; the escaped copy must not count as a line.
    func testQuotedTranscriptTextDoesNotMatch() {
        let quoted = CursorLine.tool("Write", input: #"{"contents":"{\"type\":\"turn_ended\",\"status\":\"success\"}\n{\"role\":\"assistant\",\"message\":{\"content\":[{\"type\":\"tool_use\",\"name\":\"AskQuestion\"}]}}"}"#)
        XCTAssertEqual(reading(CursorLine.prompt, quoted)?.activity, .working)
        XCTAssertEqual(reading(CursorLine.user(#"why does {\"type\":\"turn_ended\"} show up?"#))?.activity, .working)
    }

    func testSourceWatchesChatTranscriptsButNotSubagents() {
        let source = AgentLogSource.cursor()
        XCTAssertEqual(source.id, "cursor", "the usage provider's id")
        XCTAssertNil(source.hooks)
        let root = "/h/.cursor/projects/Users-me-code-web-app/agent-transcripts"
        XCTAssertTrue(source.accepts(URL(fileURLWithPath: root + "/0b6abeae-fbe9-43db-bd0c-088516bb1536.jsonl")), "flat")
        XCTAssertTrue(source.accepts(URL(fileURLWithPath: root + "/0b6abeae/0b6abeae.jsonl")), "nested")
        XCTAssertFalse(source.accepts(URL(fileURLWithPath: root + "/0b6abeae/subagents/child-1.jsonl")))
        XCTAssertFalse(source.accepts(URL(fileURLWithPath: root + "/0b6abeae.txt")))
        XCTAssertFalse(source.accepts(URL(fileURLWithPath: "/h/.cursor/projects/Users-me-code-web-app/terminals/1.jsonl")))
        XCTAssertFalse(source.accepts(URL(fileURLWithPath: "/agent-transcripts/a.jsonl")), "no project folder above it")
    }

    func testRootIsTheProjectsFolderNotTheUsageScan() {
        let home = URL(fileURLWithPath: "/Users/me")
        XCTAssertEqual(CursorTranscriptActivity.roots(home: home).map(\.path), ["/Users/me/.cursor/projects"])
    }

    // MARK: - Working folder from the slug

    /// A fake disk: folder path → entries.
    private func folder(_ slug: String, _ tree: [String: [String]]) -> String? {
        CursorTranscriptActivity.folderName(slug: slug) { tree[$0] }
    }

    func testSlugIsTheFolderAboveTheTranscripts() {
        XCTAssertEqual(CursorTranscriptActivity.projectSlug(
            of: URL(fileURLWithPath: "/h/.cursor/projects/Users-me-code-web-app/agent-transcripts/a/a.jsonl")),
                       "Users-me-code-web-app")
        XCTAssertNil(CursorTranscriptActivity.projectSlug(of: URL(fileURLWithPath: "/h/a.jsonl")))
    }

    func testSlugIsRebuiltAgainstExistingFolders() {
        let tree = [
            "/": ["Users", "System"],
            "/Users": ["me"],
            "/Users/me": ["code", ".config", "notes.txt"],
            "/Users/me/code": ["web-app", "api"],
            "/Users/me/code/web-app": [],
            "/Users/me/code/api": [],
            "/Users/me/.config": ["tool.d"],
            "/Users/me/.config/tool.d": [],
        ]
        XCTAssertEqual(folder("Users-me-code-web-app", tree), "web-app", "not the last `-` piece")
        XCTAssertEqual(folder("Users-me-code-api", tree), "api")
        XCTAssertEqual(folder("Users-me--config-tool-d", tree), "tool.d", "`.` became `-`")
        XCTAssertNil(folder("Users-me-code-gone", tree), "a folder that no longer exists")
        XCTAssertNil(folder("Users-me-notes-txt", tree), "a file is not a working folder")
        XCTAssertNil(folder("", tree))
    }

    func testAnAmbiguousSlugHasNoName() {
        let tree = [
            "/": ["Users"],
            "/Users": ["me"],
            "/Users/me": ["web", "web-app"],
            "/Users/me/web": ["app"],
            "/Users/me/web/app": [],
            "/Users/me/web-app": [],
        ]
        XCTAssertNil(folder("Users-me-web-app", tree), "`web/app` and `web-app` both exist: no name beats a wrong one")
    }

    func testTheDiskWalkFindsARealFolder() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("cursor-slug-\(UUID().uuidString)/my.project", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base.deletingLastPathComponent()) }
        let real = try XCTUnwrap(AgentLogWatcher.realPath(base.path))
        let slug = String(real.dropFirst()).replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ".", with: "-")
        let transcript = URL(fileURLWithPath: "/h/.cursor/projects/\(slug)/agent-transcripts/a/a.jsonl")
        XCTAssertEqual(CursorTranscriptActivity.folderName(transcript: transcript), "my.project")
    }
}
