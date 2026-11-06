import XCTest
@testable import PokeTokenBar

/// Records shaped like Gemini CLI's `ChatRecordingService` writes them (`JSON.stringify`, one per
/// line; google-gemini/gemini-cli `chatRecordingService.ts` / `chatRecordingTypes.ts`, main
/// 2026-11-05). Content is made up.
private enum GeminiLine {
    static let metadata = #"{"sessionId":"5f0c2a1e-9d4b-4c8e-8a1f-2b3c4d5e6f70","projectHash":"9a7b","startTime":"2026-11-05T05:56:40.000Z","lastUpdated":"2026-11-05T05:56:40.000Z","kind":"main"}"#
    static let subagentMetadata = #"{"sessionId":"sub-1","projectHash":"9a7b","startTime":"2026-11-05T05:56:40.000Z","lastUpdated":"2026-11-05T05:56:40.000Z","kind":"subagent","directories":["/Users/me/code/web-app"]}"#
    /// Written by `updateMessagesFromHistory` when a session starts (`environmentContext.ts`).
    static let bootstrap = #"{"id":"env-ctx","timestamp":"2026-11-05T05:56:40.100Z","type":"user","content":[{"text":"<session_context>\nThis is the Gemini CLI. We are setting up the context for our chat.\n</session_context>"}]}"#
    static let prompt = #"{"id":"u-1","timestamp":"2026-11-05T05:56:45.000Z","type":"user","content":[{"text":"Fix the login bug"}]}"#
    static let lastUpdated = #"{"$set":{"lastUpdated":"2026-11-05T05:56:45.001Z"}}"#
    static func gemini(id: String = "g-1", text: String = "Let me look.") -> String {
        #"{"id":""# + id + #"","timestamp":"2026-11-05T05:56:47.000Z","type":"gemini","content":""# + text
            + #"","thoughts":[],"tokens":{"input":900,"output":12,"cached":0,"thoughts":0,"tool":0,"total":912},"model":"gemini-3-pro"}"#
    }
    /// The same message written again once its tool call completed (`recordCompletedToolCalls`).
    static let geminiWithTools = #"{"id":"g-1","timestamp":"2026-11-05T05:56:47.000Z","type":"gemini","content":"Let me look.","toolCalls":[{"id":"call-1","name":"read_file","args":{"file_path":"src/login.ts","type":"user"},"result":[{"functionResponse":{"id":"call-1","name":"read_file","response":{"output":"…"}}}],"status":"success","timestamp":"2026-11-05T05:56:49.000Z","displayName":"ReadFile"}],"model":"gemini-3-pro"}"#
    static let toolResponse = #"{"id":"u-2","timestamp":"2026-11-05T05:56:49.100Z","type":"user","content":[{"functionResponse":{"id":"call-1","name":"read_file","response":{"output":"…"}}}]}"#
    static let cancelled = #"{"id":"i-1","timestamp":"2026-11-05T05:56:50.000Z","type":"info","content":"Request cancelled."}"#
    static let otherInfo = #"{"id":"i-2","timestamp":"2026-11-05T05:56:50.000Z","type":"info","content":"Chat history compressed."}"#
    static let warning = #"{"id":"w-1","timestamp":"2026-11-05T05:56:50.000Z","type":"warning","content":"Loop detected."}"#
    static let error = #"{"id":"e-1","timestamp":"2026-11-05T05:56:50.000Z","type":"error","content":"[API Error: quota exceeded]"}"#
    static let patch = #"{"$patch":{"updates":[{"id":"g-1","content":"Let me look again."}]}}"#
    static let rewind = #"{"$rewindTo":"u-1"}"#
    static func summary(_ text: String) -> String { #"{"$set":{"summary":""# + text + #""}}"# }
}

final class GeminiCLIActivityTests: XCTestCase {
    private func reading(_ lines: String...) -> AgentLogReading? {
        GeminiCLIActivity.reading(lines: lines.map { Substring($0) })
    }

    func testWorkingFromPromptsRepliesAndToolResponses() {
        XCTAssertEqual(reading(GeminiLine.prompt, GeminiLine.lastUpdated)?.activity, .working)
        XCTAssertEqual(reading(GeminiLine.prompt, GeminiLine.gemini())?.activity, .working)
        XCTAssertEqual(reading(GeminiLine.gemini(), GeminiLine.geminiWithTools, GeminiLine.lastUpdated)?.activity, .working)
        XCTAssertEqual(reading(GeminiLine.geminiWithTools, GeminiLine.toolResponse)?.activity, .working)
        XCTAssertEqual(reading(GeminiLine.prompt)?.lineID, "u-1")
    }

    /// The log has no turn end. A reply without tool calls is what the log shows during a tool run
    /// or an approval prompt too, so it must not read as done.
    func testAReplyThatLooksFinalIsStillWorking() {
        let final = GeminiLine.gemini(id: "g-9", text: "Fixed: the session token was not refreshed.")
        XCTAssertEqual(reading(GeminiLine.toolResponse, final, GeminiLine.lastUpdated)?.activity, .working)
        let session = [GeminiLine.metadata, GeminiLine.prompt, GeminiLine.gemini(), GeminiLine.geminiWithTools,
                        GeminiLine.toolResponse, final, GeminiLine.lastUpdated, GeminiLine.summary("Fix login")]
        for end in session.indices {
            let activity = GeminiCLIActivity.reading(lines: session[...end].map { Substring($0) })?.activity
            if case .done = activity { XCTFail("done after line \(end)") }
            if case .waiting = activity { XCTFail("waiting after line \(end)") }
        }
    }

    func testCancelAndErrorAreIdle() {
        XCTAssertEqual(reading(GeminiLine.gemini(), GeminiLine.cancelled, GeminiLine.lastUpdated)?.activity, .idle)
        XCTAssertEqual(reading(GeminiLine.prompt, GeminiLine.error)?.activity, .idle)
        XCTAssertEqual(reading(GeminiLine.gemini(), GeminiLine.otherInfo, GeminiLine.warning)?.activity, .working,
                       "other notes say nothing about the turn")
        XCTAssertEqual(reading(GeminiLine.cancelled, GeminiLine.prompt)?.activity, .working, "the next prompt")
    }

    /// Starting `gemini` writes the environment context as a `user` message; nothing is running.
    func testSessionStartIsNotAPrompt() {
        XCTAssertNil(reading(GeminiLine.metadata, GeminiLine.bootstrap, GeminiLine.lastUpdated))
        XCTAssertEqual(reading(GeminiLine.cancelled, GeminiLine.bootstrap)?.activity, .idle)
    }

    func testBookkeepingAndBrokenLinesAreSkipped() {
        XCTAssertNil(reading(GeminiLine.lastUpdated, GeminiLine.patch, GeminiLine.rewind, GeminiLine.metadata))
        XCTAssertNil(reading("not json", "", #"{"type":"user""#))
        XCTAssertEqual(reading(GeminiLine.cancelled, GeminiLine.patch)?.activity, .idle)
    }

    func testTitleIsTheSessionSummary() {
        XCTAssertEqual(GeminiCLIActivity.title(lines: [Substring(GeminiLine.summary("Fix login")), Substring(GeminiLine.lastUpdated)]),
                       AgentSessionTitle(named: nil, generated: "Fix login"))
        XCTAssertEqual(GeminiCLIActivity.title(lines: [Substring(GeminiLine.summary(" "))]), AgentSessionTitle())
        XCTAssertEqual(GeminiCLIActivity.title(lines: [Substring(GeminiLine.prompt)]), AgentSessionTitle())
    }

    func testHeadSkipsSubagentsAndCarriesAMigratedSummary() {
        XCTAssertEqual(GeminiCLIActivity.head(lines: [Substring(GeminiLine.metadata), Substring(GeminiLine.prompt)]),
                       AgentLogHead())
        XCTAssertTrue(GeminiCLIActivity.head(lines: [Substring(GeminiLine.subagentMetadata)]).skip)
        let migrated = #"{"sessionId":"s","projectHash":"h","startTime":"t","lastUpdated":"t","summary":"Refactor auth"}"#
        XCTAssertEqual(GeminiCLIActivity.head(lines: [Substring(migrated)]).title.generated, "Refactor auth")
        XCTAssertEqual(GeminiCLIActivity.head(lines: [Substring(GeminiLine.prompt)]), AgentLogHead(), "not a metadata line")
    }

    func testOnlyMainSessionLogsAreAccepted() {
        let chats = "/h/.gemini/tmp/web-app/chats/"
        XCTAssertTrue(GeminiCLIActivity.accepts(URL(fileURLWithPath: chats + "session-2026-11-05T05-56-5f0c2a1e.jsonl")))
        XCTAssertFalse(GeminiCLIActivity.accepts(URL(fileURLWithPath: chats + "5f0c2a1e-full-id/sub-1.jsonl")),
                       "a subagent's log")
        XCTAssertFalse(GeminiCLIActivity.accepts(URL(fileURLWithPath: chats + "session-2026-01-01T00-00-abc.json")),
                       "legacy whole-file JSON")
        XCTAssertFalse(GeminiCLIActivity.accepts(URL(fileURLWithPath: "/h/.gemini/tmp/web-app/logs.jsonl")))
    }

    func testLabelComesFromTheProjectRootMarker() throws {
        XCTAssertEqual(GeminiCLIActivity.label(projectRoot: "/Users/me/code/Web App\n", projectFolder: "web-app"), "Web App")
        XCTAssertEqual(GeminiCLIActivity.label(projectRoot: nil, projectFolder: "web-app"), "web-app")
        XCTAssertNil(GeminiCLIActivity.label(projectRoot: nil, projectFolder: String(repeating: "ab12", count: 16)),
                     "a pre-registry hash folder names nothing")
        XCTAssertEqual(GeminiCLIActivity.label(projectRoot: "  ", projectFolder: "api"), "api")

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("gemini-label-\(UUID().uuidString)")
        let chats = root.appendingPathComponent("web-app/chats", isDirectory: true)
        try FileManager.default.createDirectory(at: chats, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let log = chats.appendingPathComponent("session-2026-11-05T05-56-5f0c2a1e.jsonl")
        XCTAssertEqual(GeminiCLIActivity.label(forLog: log), "web-app")
        try Data("/Users/me/code/WebApp".utf8).write(to: root.appendingPathComponent("web-app/.project_root"))
        XCTAssertEqual(GeminiCLIActivity.label(forLog: log), "WebApp")
    }

    func testSourceShape() {
        let source = AgentLogSource.geminiCLI()
        XCTAssertEqual(source.id, "gemini")
        XCTAssertEqual(source.hooks?.id, "gemini", "its hooks add what the log lacks")
        XCTAssertNotNil(source.head)
        XCTAssertNotNil(source.pathLabel)
        XCTAssertNil(source.database)
    }
}
