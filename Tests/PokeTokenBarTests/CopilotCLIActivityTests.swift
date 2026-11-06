import XCTest
@testable import PokeTokenBar

/// Events shaped like Copilot CLI writes them to `events.jsonl`: compact JSON, `type` first
/// (jazzyalex/agent-sessions `Resources/Fixtures/stage0/agents/copilot/small.jsonl`), fields from
/// github/copilot-sdk `nodejs/src/generated/session-events.ts` (main 2026-11-05). Content is made up.
private enum CopilotLine {
    private static func event(_ type: String, _ data: String, extra: String = "") -> String {
        #"{"type":""# + type + #"","data":"# + data + #","id":""# + UUID().uuidString
            + #"","timestamp":"2026-11-05T05:56:45.000Z","parentId":"evt-0""# + extra + "}"
    }

    static func start(cwd: String = "/Users/me/code/web-app") -> String {
        event("session.start", #"{"sessionId":"5f0c2a1e","version":1,"producer":"copilot-agent","copilotVersion":"1.0.77","startTime":"2026-11-05T05:56:40.000Z","selectedModel":"gpt-5","context":{"cwd":""# + cwd + #"","gitRoot":""# + cwd + #"","branch":"main","repository":"me/web-app"}}"#)
    }
    static func resume(cwd: String) -> String {
        event("session.resume", #"{"resumeTime":"2026-11-05T06:00:00.000Z","eventCount":12,"context":{"cwd":""# + cwd + #""}}"#)
    }
    static func contextChanged(cwd: String) -> String { event("session.context_changed", #"{"cwd":""# + cwd + #""}"#) }
    static let prompt = event("user.message", #"{"content":"Fix the login bug","transformedContent":"<current_datetime>…</current_datetime>Fix the login bug","attachments":[],"delivery":"idle","interactionId":"int-1"}"#)
    static func turnStart(_ turn: String, extra: String = "") -> String {
        event("assistant.turn_start", #"{"turnId":""# + turn + #"","interactionId":"int-1","model":"gpt-5","agentMode":"interactive"}"#, extra: extra)
    }
    static func turnEnd(_ turn: String, extra: String = "", data: String = "") -> String {
        event("assistant.turn_end", #"{"turnId":""# + turn + #"","model":"gpt-5""# + data + "}", extra: extra)
    }
    static func message(_ turn: String, tools: Bool, extra: String = "", data: String = "") -> String {
        let requests = tools ? #"[{"toolCallId":"call-1","name":"bash","arguments":{"command":"ls"},"type":"function"}]"# : "[]"
        return event("assistant.message", #"{"messageId":"msg-"# + turn + #"","content":"Done.","toolRequests":"# + requests
            + #","turnId":""# + turn + #"","interactionId":"int-1","outputTokens":12"# + data + "}", extra: extra)
    }
    static let toolStart = event("tool.execution_start", #"{"toolCallId":"call-1","toolName":"bash","arguments":{"command":"ls"},"turnId":"0"}"#)
    static let toolComplete = event("tool.execution_complete", #"{"toolCallId":"call-1","success":true,"result":{"content":"src\ntests"},"turnId":"0"}"#)
    static func permission(_ extraData: String = #","permissionMode":"manual""#) -> String {
        event("permission.requested", #"{"requestId":"perm-1","permissionRequest":{"kind":"shell","fullCommandText":"rm -rf build","intention":"Clean the build"}"# + extraData + "}")
    }
    static let permissionDone = event("permission.completed", #"{"requestId":"perm-1","result":{"kind":"approved"},"decisionSource":"human_response"}"#)
    static let abort = event("abort", #"{"reason":"user_initiated"}"#)
    static let error = event("session.error", #"{"errorType":"rate_limit","message":"Rate limited"}"#)
    static let shutdown = event("session.shutdown", #"{"shutdownType":"routine","sessionStartTime":1770000000000}"#)
    static let checkpoint = event("session.usage_checkpoint", #"{"totalPremiumRequests":1,"totalNanoAiu":1}"#)
    static let taskComplete = event("session.task_complete", #"{"summary":"Fixed it","success":true,"outcome":"completed"}"#)
}

final class CopilotCLIActivityTests: XCTestCase {
    private func reading(_ lines: String...) -> AgentLogReading? {
        CopilotCLIActivity.reading(lines: lines.map { Substring($0) })
    }

    private func activity(_ lines: String...) -> AgentActivity? {
        CopilotCLIActivity.reading(lines: lines.map { Substring($0) })?.activity
    }

    func testAToolLoopIsWorking() {
        XCTAssertEqual(activity(CopilotLine.prompt), .working)
        XCTAssertEqual(activity(CopilotLine.prompt, CopilotLine.turnStart("0")), .working)
        XCTAssertEqual(activity(CopilotLine.turnStart("0"), CopilotLine.message("0", tools: true), CopilotLine.toolStart), .working)
        XCTAssertEqual(activity(CopilotLine.message("0", tools: true), CopilotLine.toolStart, CopilotLine.toolComplete,
                                CopilotLine.turnEnd("0")), .working,
                       "a turn that ran tools is one model call of many")
        XCTAssertEqual(activity(CopilotLine.toolComplete, CopilotLine.turnEnd("0")), .working)
        XCTAssertEqual(activity(CopilotLine.turnEnd("0")), .working, "a lone turn end: its reply is not in view")
    }

    /// The loop's end is only idle: `session.idle` is ephemeral, and Autopilot, queued messages and
    /// background agents can start another run right after a reply without tools.
    func testAReplyWithoutToolsEndsQuietly() throws {
        let end = try XCTUnwrap(reading(CopilotLine.turnStart("1"), CopilotLine.message("1", tools: false),
                                        CopilotLine.turnEnd("1"), CopilotLine.checkpoint))
        XCTAssertEqual(end.activity, .idle)
        XCTAssertEqual(activity(CopilotLine.toolComplete, CopilotLine.turnEnd("0"), CopilotLine.turnStart("1"),
                                CopilotLine.message("1", tools: false), CopilotLine.turnEnd("1")), .idle)
        XCTAssertEqual(activity(CopilotLine.message("1", tools: false), CopilotLine.turnEnd("1"), CopilotLine.prompt), .working,
                       "the next message")
        XCTAssertEqual(activity(CopilotLine.message("0", tools: false), CopilotLine.turnEnd("1")), .working,
                       "a reply from another turn says nothing about this one")
    }

    func testNeverDone() {
        let session = [CopilotLine.start(), CopilotLine.prompt, CopilotLine.turnStart("0"), CopilotLine.message("0", tools: true),
                       CopilotLine.permission(), CopilotLine.permissionDone, CopilotLine.toolStart, CopilotLine.toolComplete,
                       CopilotLine.turnEnd("0"), CopilotLine.turnStart("1"), CopilotLine.message("1", tools: false),
                       CopilotLine.taskComplete, CopilotLine.turnEnd("1"), CopilotLine.checkpoint, CopilotLine.shutdown]
        for end in session.indices {
            if case .done = CopilotCLIActivity.reading(lines: session[...end].map { Substring($0) })?.activity {
                XCTFail("done after line \(end)")
            }
        }
    }

    func testAPermissionPromptIsWaiting() throws {
        let waiting = try XCTUnwrap(reading(CopilotLine.message("0", tools: true), CopilotLine.permission()))
        XCTAssertEqual(waiting.activity, .waiting(message: nil))
        XCTAssertNotNil(waiting.lineID, "two prompts in one batch are two waits")
        XCTAssertEqual(activity(CopilotLine.permission(), CopilotLine.permissionDone), .working, "answered")
        XCTAssertEqual(activity(CopilotLine.permission(""), CopilotLine.checkpoint), .waiting(message: nil),
                       "events from before permissionMode existed")
    }

    func testPermissionsNobodyIsAskedAboutAreNotWaits() {
        let before = CopilotLine.message("0", tools: true)
        XCTAssertEqual(activity(before, CopilotLine.permission(#","permissionMode":"manual","resolvedByHook":true"#)), .working)
        XCTAssertEqual(activity(before, CopilotLine.permission(#","permissionMode":"allow-all""#)), .working)
        let approve = #","permissionMode":"assisted","assistedApprovalAssessment":{"status":"completed","recommendation":"approve"}"#
        XCTAssertEqual(activity(before, CopilotLine.permission(approve)), .working)
        let ask = #","permissionMode":"assisted","assistedApprovalAssessment":{"status":"completed","recommendation":"requireApproval"}"#
        XCTAssertEqual(activity(before, CopilotLine.permission(ask)), .waiting(message: nil))
    }

    func testAbortErrorAndShutdownAreIdle() {
        XCTAssertEqual(activity(CopilotLine.toolStart, CopilotLine.abort), .idle)
        XCTAssertEqual(activity(CopilotLine.prompt, CopilotLine.error), .idle)
        XCTAssertEqual(activity(CopilotLine.prompt, CopilotLine.shutdown, CopilotLine.checkpoint), .idle)
    }

    /// Subagents write into the parent's log. Their turns ending is not the session's.
    func testSubagentTurnsAreNotTheSessions() {
        let agent = #","agentId":"agent-7""#
        XCTAssertEqual(activity(CopilotLine.message("0", tools: true), CopilotLine.toolStart,
                                CopilotLine.turnStart("s0", extra: agent), CopilotLine.message("s0", tools: false, extra: agent),
                                CopilotLine.turnEnd("s0", extra: agent)), .working)
        let older = #","parentToolCallId":"call-1""#
        XCTAssertEqual(activity(CopilotLine.toolStart, CopilotLine.message("s0", tools: false, data: older),
                                CopilotLine.turnEnd("s0", data: older)), .working, "older CLIs mark them in data")
        XCTAssertEqual(activity(CopilotLine.message("1", tools: false), CopilotLine.turnEnd("1"),
                                CopilotLine.turnEnd("s0", extra: agent)), .idle,
                       "a background subagent's turn end after the session's own end changes nothing")
    }

    func testLabelIsTheWorkingFolder() {
        XCTAssertEqual(reading(CopilotLine.start(cwd: "/Users/me/code/my app"), CopilotLine.prompt)?.label, "my app")
        XCTAssertEqual(reading(CopilotLine.start(), CopilotLine.contextChanged(cwd: "/Users/me/code/api"), CopilotLine.prompt)?.label, "api")
        XCTAssertEqual(reading(CopilotLine.start(), CopilotLine.resume(cwd: "/Users/me/code/cli"), CopilotLine.prompt)?.label, "cli")
        XCTAssertEqual(reading(CopilotLine.prompt, CopilotLine.contextChanged(cwd: "/Users/me/code/api"))?.label, nil,
                       "a folder change after the newest event is not this event's folder")
        XCTAssertNil(reading(CopilotLine.prompt)?.label)
        XCTAssertEqual(CopilotCLIActivity.head(lines: [Substring(CopilotLine.start()), Substring(CopilotLine.prompt)]).label, "web-app")
        XCTAssertNil(CopilotCLIActivity.head(lines: [Substring(CopilotLine.prompt)]).label)
    }

    func testBookkeepingKeyOrderAndBrokenLines() {
        XCTAssertNil(reading(CopilotLine.checkpoint, CopilotLine.start(), "not json", ""))
        XCTAssertNil(reading(CopilotLine.taskComplete), "task_complete may come before the last reply")
        let reordered = #"{"id":"x","data":{"reason":"user_initiated"},"type":"abort","timestamp":"t","parentId":null}"#
        XCTAssertEqual(activity(CopilotLine.prompt, reordered), .idle, "another key order is parsed")
    }

    func testWorkspaceNameIsTheRenamedTitle() throws {
        XCTAssertEqual(CopilotCLIActivity.workspaceName(yaml: "id: 5f0c\nname: Fix login\ncwd: /x\n"), "Fix login")
        XCTAssertEqual(CopilotCLIActivity.workspaceName(yaml: "name: \"Fix: login\"\n"), "Fix: login")
        XCTAssertEqual(CopilotCLIActivity.workspaceName(yaml: "id: a\nname: |-\n  Fix login\n  more\ncwd: /x\n"), "Fix login")
        XCTAssertNil(CopilotCLIActivity.workspaceName(yaml: "name: |-\ncwd: /x\n"), "an empty block scalar")
        XCTAssertNil(CopilotCLIActivity.workspaceName(yaml: "id: a\n  name: nested\n"))
        XCTAssertNil(CopilotCLIActivity.workspaceName(yaml: "name:\n"))

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("copilot-title-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = dir.appendingPathComponent("events.jsonl")
        XCTAssertEqual(CopilotCLIActivity.externalTitle(forLog: log), AgentSessionTitle())
        try Data("id: x\nname: auth\n".utf8).write(to: dir.appendingPathComponent("workspace.yaml"))
        XCTAssertEqual(CopilotCLIActivity.externalTitle(forLog: log), AgentSessionTitle(named: "auth", generated: nil))
    }

    func testOnlySessionEventLogsAreAccepted() {
        XCTAssertTrue(CopilotCLIActivity.accepts(URL(fileURLWithPath: "/h/.copilot/session-state/5f0c2a1e-9d4b/events.jsonl")))
        XCTAssertFalse(CopilotCLIActivity.accepts(URL(fileURLWithPath: "/h/.copilot/session-state/5f0c2a1e.jsonl")))
        XCTAssertFalse(CopilotCLIActivity.accepts(URL(fileURLWithPath: "/h/.copilot/session-state/5f0c/session.db")))
        XCTAssertFalse(CopilotCLIActivity.accepts(URL(fileURLWithPath: "/h/.copilot/logs/x/events.jsonl")))
    }

    func testSourceShape() {
        let source = AgentLogSource.copilotCLI()
        XCTAssertEqual(source.id, "copilot")
        XCTAssertEqual(source.hooks?.id, "copilot", "its hooks add what the log lacks")
        XCTAssertNotNil(source.head)
        XCTAssertNotNil(source.externalTitle)
        XCTAssertNil(source.database)
    }
}
