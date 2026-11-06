import XCTest
@testable import PokeTokenBar

/// Wire records shaped like Kimi Code writes them: compact JSON, `type` first, payload spread at the
/// top level, `time` last (`packages/agent-core-v2/docs/wire-manifest.d.ts`, protocol 1.5, and the
/// event classes behind it at upstream d37c9d2). Content is made up.
private enum Wire {
    static let metadata = #"{"type":"metadata","protocol_version":"1.5","created_at":1779256791085,"min_protocol_version":"1.5"}"#

    static func prompt(origin: String = #"{"kind":"user"}"#, turn: Int = 0) -> String {
        #"{"type":"turn.prompt","agentId":"main","input":[{"type":"text","text":"Fix the login bug"}],"origin":"#
            + origin + #","promptId":"prompt_1","turnId":\#(turn),"time":1779256800000}"#
    }

    static let userMessage = #"{"type":"context.append_message","agentId":"main","message":{"role":"user","content":[{"type":"text","text":"Fix the login bug"}],"toolCalls":[],"id":"msg_1","origin":{"kind":"user"}},"time":1779256800001}"#
    static let stepBegin = #"{"type":"context.append_loop_event","agentId":"main","event":{"type":"step.begin","uuid":"s1","turnId":"0","step":1},"time":1779256800100}"#
    static let toolCall = #"{"type":"context.append_loop_event","agentId":"main","event":{"type":"tool.call","stepUuid":"s1","toolCallId":"call_1","name":"Bash","args":{"command":"ls"},"uuid":"u2","turnId":"0","step":1},"time":1779256800200}"#
    static let toolResult = #"{"type":"context.append_loop_event","agentId":"main","event":{"type":"tool.result","toolCallId":"call_1","result":{"output":"README.md"},"parentUuid":"u2"},"time":1779256800300}"#
    static let stepEnd = #"{"type":"context.append_loop_event","agentId":"main","event":{"type":"step.end","uuid":"s1","turnId":"0","step":1,"finishReason":"end_turn"},"time":1779256800400}"#
    static let usage = #"{"type":"usage.record","agentId":"main","model":"kimi-k2","usage":{"inputOther":10,"output":5,"inputCacheRead":0,"inputCacheCreation":0},"usageScope":"turn","time":1779256800401}"#
    static let llmRequest = #"{"type":"llm.request","agentId":"main","kind":"compaction","provider":"kimi","model":"kimi-k2","toolSelect":false,"systemPromptHash":"h","toolsHash":"t","messageCount":4,"time":1779256800402}"#
    static let promptCompleted = #"{"type":"prompt.completed","agentId":"main","promptId":"prompt_1","finishedAt":"2026-11-06T03:00:00.000Z","reason":"completed","time":1779256800501}"#
    static let promptAborted = #"{"type":"prompt.aborted","agentId":"main","promptId":"prompt_2","abortedAt":"2026-11-06T03:00:00.000Z","time":1779256800502}"#
    static let steer = #"{"type":"turn.steer","agentId":"main","input":[{"type":"text","text":"also check signup"}],"origin":{"kind":"user"},"turnId":0,"time":1779256800250}"#
    static let retrying = #"{"type":"turn.step.retrying","agentId":"main","turnId":0,"step":1,"failedAttempt":1,"nextAttempt":2,"maxAttempts":3,"delayMs":500,"errorName":"APIError","errorMessage":"overloaded","statusCode":529,"time":1779256800260}"#
    static let forked = #"{"type":"forked","agentId":"main","time":1779256900000}"#

    static func ended(_ reason: String, turn: Int = 0, time: Int = 1779256800500) -> String {
        #"{"type":"turn.ended","agentId":"main","turnId":\#(turn),"reason":""# + reason
            + #"","durationMs":500,"time":\#(time)}"#
    }

    static func cancel(target: String) -> String {
        #"{"type":"turn.cancel","agentId":"main","turnId":0,"target":""# + target + #"","reason":"user_cancelled","time":1779256800450}"#
    }

    static func request(kind: String, id: String = "approval_1") -> String {
        let payload = kind == "question"
            ? #"{"questions":[{"question":"Which database?","options":[{"label":"Postgres"},{"label":"SQLite"}]}]}"#
            : #"{"toolCallId":"call_1","toolName":"Bash","action":"run command","display":{"kind":"command","command":"rm -rf build"}}"#
        return #"{"type":"interaction.request","agentId":"main","id":""# + id + #"","kind":""# + kind
            + #"","toolCallId":"call_1","request":"# + payload + #","time":1779256800210}"#
    }

    static func resolved(_ response: String, id: String = "approval_1") -> String {
        #"{"type":"interaction.resolved","agentId":"main","id":""# + id + #"","response":"# + response + #","time":1779256800220}"#
    }
}

final class KimiCodeActivityTests: XCTestCase {
    private func reading(_ lines: String...) -> AgentLogReading? {
        KimiCodeActivity.reading(lines: lines.map { Substring($0) })
    }

    func testTurnStatesFromTheNewestMeaningfulRecord() {
        XCTAssertEqual(reading(Wire.metadata, Wire.prompt())?.activity, .working)
        XCTAssertEqual(reading(Wire.prompt(), Wire.userMessage, Wire.stepBegin, Wire.toolCall)?.activity, .working)
        XCTAssertEqual(reading(Wire.toolCall, Wire.toolResult)?.activity, .working)
        XCTAssertEqual(reading(Wire.ended("completed"), Wire.steer)?.activity, .working)
        XCTAssertEqual(reading(Wire.ended("failed"), Wire.retrying)?.activity, .working, "a retry runs on")
        XCTAssertEqual(reading(Wire.toolResult, Wire.stepEnd, Wire.ended("completed"))?.activity, .done(message: nil))
    }

    func testCancelledFailedAndBlockedTurnsAreIdle() {
        XCTAssertEqual(reading(Wire.toolCall, Wire.ended("cancelled"))?.activity, .idle)
        XCTAssertEqual(reading(Wire.toolCall, Wire.ended("failed"))?.activity, .idle)
        XCTAssertEqual(reading(Wire.toolCall, Wire.ended("blocked"))?.activity, .idle)
        XCTAssertEqual(reading(Wire.toolCall, Wire.cancel(target: "active"))?.activity, .idle,
                       "Esc: idle before the turn's end is written")
        XCTAssertEqual(reading(Wire.toolCall, Wire.cancel(target: "queued"), Wire.promptAborted)?.activity, .working,
                       "dropping a queued prompt leaves the running turn alone")
        XCTAssertEqual(reading(Wire.toolCall, Wire.ended("someday"))?.activity, .working, "an unknown reason says nothing")
    }

    func testApprovalsAndQuestionsWait() throws {
        let approval = try XCTUnwrap(reading(Wire.toolCall, Wire.request(kind: "approval", id: "approval_7")))
        XCTAssertEqual(approval.activity, .waiting(message: nil))
        XCTAssertEqual(approval.lineID, "interaction:approval_7")
        XCTAssertEqual(reading(Wire.toolCall, Wire.request(kind: "question", id: "question_1"))?.activity,
                       .waiting(message: nil))
        XCTAssertEqual(reading(Wire.toolCall, Wire.request(kind: "user_tool", id: "user_tool_1"))?.activity, .working,
                       "a client-side tool is not a question to the person")
        XCTAssertEqual(reading(Wire.request(kind: "approval"), Wire.resolved(#"{"decision":"approved"}"#))?.activity,
                       .working)
        XCTAssertEqual(reading(Wire.request(kind: "question"), Wire.resolved("null"))?.activity, .working)
    }

    /// A turn's end cancels its open requests after `turn.ended` is written; that must not restart work.
    func testTheCancellationAfterATurnEndsStaysIdle() {
        let cancelled = Wire.resolved(#"{"cancelled":true,"reason":"turn_ended"}"#)
        XCTAssertEqual(reading(Wire.request(kind: "approval"), Wire.cancel(target: "active"), Wire.ended("cancelled"),
                               cancelled)?.activity, .idle)
        XCTAssertNil(reading(cancelled))
    }

    func testBookkeepingRecordsAreSkipped() {
        let done = Wire.ended("completed")
        XCTAssertEqual(reading(done, Wire.usage, Wire.promptCompleted, Wire.llmRequest)?.activity, .done(message: nil))
        XCTAssertEqual(reading(done, Wire.userMessage)?.activity, .done(message: nil),
                       "a prompt a hook blocked is appended as a message but starts no turn")
        XCTAssertNil(reading(Wire.metadata, Wire.usage, Wire.promptCompleted, Wire.llmRequest, Wire.userMessage))
        XCTAssertNil(reading("not json", "", "{\"type\":"))
    }

    func testAForkedCopyIsNotNews() {
        XCTAssertEqual(reading(Wire.ended("completed"), Wire.forked)?.activity, .idle)
        XCTAssertEqual(KimiCodeActivity.turns(lines: [Substring(Wire.prompt()), Substring(Wire.forked)], from: AgentTurnState()),
                       AgentTurnState(open: false, automatic: false))
    }

    func testTwoTurnsEndingAreTwoLines() throws {
        let first = try XCTUnwrap(reading(Wire.ended("completed", turn: 3, time: 1779256800500)))
        let second = try XCTUnwrap(reading(Wire.ended("completed", turn: 4, time: 1779256900500)))
        XCTAssertEqual(first.lineID, "turn.ended:3:1779256800500")
        XCTAssertNotEqual(first.lineID, second.lineID)
        XCTAssertNil(first.label, "the wire names no folder; the source labels from the path")
    }

    /// Tool output can quote wire records; escaped copies and nested objects are not records.
    func testNestedRecordTextDoesNotMatch() {
        let quoted = #"{"type":"context.append_loop_event","agentId":"main","event":{"type":"tool.result","toolCallId":"call_1","result":{"output":"{\"type\":\"turn.ended\",\"reason\":\"completed\"}"},"parentUuid":"u2"},"time":1}"#
        let nestedArgs = #"{"type":"context.append_loop_event","agentId":"main","event":{"type":"tool.call","stepUuid":"s1","toolCallId":"c","name":"Write","args":{"type":"turn.ended","reason":"completed"},"uuid":"u","turnId":"0","step":1},"time":1}"#
        XCTAssertEqual(reading(Wire.toolCall, quoted)?.activity, .working)
        XCTAssertEqual(reading(Wire.toolCall, nestedArgs)?.activity, .working)
        let quotedPrompt = Wire.prompt(origin: #"{"kind":"user"}"#).replacingOccurrences(
            of: "Fix the login bug", with: #"{\"type\":\"turn.ended\",\"reason\":\"completed\"}"#)
        XCTAssertEqual(reading(Wire.ended("completed"), quotedPrompt)?.activity, .working)
    }

    func testRecordsInAnotherKeyOrderStillCount() {
        let reordered = #"{"agentId":"main","turnId":2,"reason":"completed","type":"turn.ended","time":7}"#
        XCTAssertEqual(reading(Wire.toolCall, reordered)?.activity, .done(message: nil))
        XCTAssertNil(KimiCodeActivity.recordType(Substring(Wire.usage)), "types this reader ignores are not parsed")
    }

    private func turns(_ lines: String..., from start: AgentTurnState = AgentTurnState()) -> AgentTurnState {
        KimiCodeActivity.turns(lines: lines.map { Substring($0) }, from: start)
    }

    func testTurnsStartedByThePersonAndByTheSystem() {
        XCTAssertEqual(turns(Wire.prompt()), AgentTurnState(open: true, automatic: false))
        XCTAssertEqual(turns(Wire.prompt(), Wire.toolCall, Wire.ended("completed")), AgentTurnState(open: false, automatic: false))
        let automatic = [
            #"{"kind":"task","taskId":"t1","status":"completed","notificationId":"n1"}"#,
            #"{"kind":"cron_job","jobId":"j1","cron":"*/5 * * * *","recurring":true,"coalescedCount":0,"stale":false}"#,
            #"{"kind":"cron_missed","count":2}"#,
            #"{"kind":"injection","variant":"tower_inbox_wake"}"#,
            #"{"kind":"hook_result","event":"SessionStart"}"#,
            #"{"kind":"system_trigger","name":"stop_hook"}"#,
            #""task""#,
        ]
        for origin in automatic {
            XCTAssertEqual(turns(Wire.ended("completed"), Wire.prompt(origin: origin)), AgentTurnState(open: true, automatic: true), origin)
        }
        let person = [
            #"{"kind":"user","clientMetadata":[]}"#,
            #"{"kind":"skill_activation","activationId":"a1","skillName":"review","trigger":"user-slash"}"#,
            #"{"kind":"plugin_command","activationId":"a2","pluginId":"p","commandName":"deploy","trigger":"user-slash"}"#,
            #"{"kind":"system_trigger","name":"goal_continuation"}"#,
            #"{"kind":"retry"}"#,
            #"{"kind":"something_new"}"#,
            "null",
        ]
        for origin in person {
            XCTAssertEqual(turns(Wire.prompt(origin: #"{"kind":"task","taskId":"t","status":"completed","notificationId":"n"}"#),
                                 Wire.ended("completed"), Wire.prompt(origin: origin)),
                           AgentTurnState(open: true, automatic: false), origin)
        }
        XCTAssertEqual(turns(Wire.toolCall, Wire.steer, from: AgentTurnState(open: true, automatic: true)),
                       AgentTurnState(open: true, automatic: true), "steering does not start a turn")
    }

    func testOnlyTheMainAgentsWireIsRead() {
        let source = AgentLogSource.kimiCode()
        let session = "/h/.kimi-code/sessions/wd_web-app_0123456789ab/session_1"
        XCTAssertTrue(source.accepts(URL(fileURLWithPath: session + "/agents/main/wire.jsonl")))
        XCTAssertFalse(source.accepts(URL(fileURLWithPath: session + "/agents/agent-0/wire.jsonl")), "a subagent")
        XCTAssertFalse(source.accepts(URL(fileURLWithPath: session + "/state.json")))
        XCTAssertFalse(source.accepts(URL(fileURLWithPath: session + "/agents/main/plans/p1.md")))
        XCTAssertFalse(source.accepts(URL(fileURLWithPath: "/h/.kimi-code/sessions/x/main/wire.jsonl")))
        XCTAssertEqual(source.id, LocalKimiCodeProvider().id, "the pet and the usage tab name the same agent")
        XCTAssertNil(source.hooks)
    }

    func testTitlesComeFromTheStateFile() {
        func title(_ json: String) -> AgentSessionTitle {
            KimiCodeActivity.title(state: try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        }
        XCTAssertEqual(title(#"{"title":"auth","titleKind":"custom","isCustomTitle":true}"#),
                       AgentSessionTitle(named: "auth", generated: nil))
        XCTAssertEqual(title(#"{"title":"Fix login bug","titleKind":"generated","isCustomTitle":false}"#),
                       AgentSessionTitle(named: nil, generated: "Fix login bug"))
        XCTAssertEqual(title(#"{"title":"Fix the login bug","titleKind":"replaceable"}"#).text, "Fix the login bug",
                       "a title taken from the first prompt")
        XCTAssertEqual(title(#"{"title":"old","isCustomTitle":true}"#).named, "old", "an older file")
        XCTAssertEqual(title(#"{"title":"New Session","titleKind":"replaceable"}"#), AgentSessionTitle())
        XCTAssertEqual(title(#"{"title":"  "}"#), AgentSessionTitle())
        XCTAssertEqual(title(#"{"cwd":"/x"}"#), AgentSessionTitle())
        XCTAssertEqual(KimiCodeActivity.title(state: nil), AgentSessionTitle())
    }

    func testWorkspaceFolderNames() {
        XCTAssertEqual(KimiCodeActivity.workspaceSlug("wd_web-app_0123456789ab"), "web-app")
        XCTAssertEqual(KimiCodeActivity.workspaceSlug("wd_my_project_0123456789ab"), "my_project")
        XCTAssertNil(KimiCodeActivity.workspaceSlug("wm_6f1c2a7e-0d5b-4d8e-9a43-1b2c3d4e5f60"), "a managed workspace")
        XCTAssertNil(KimiCodeActivity.workspaceSlug("wd_web-app_xyz"))
        XCTAssertNil(KimiCodeActivity.workspaceSlug("wd__0123456789ab"))
    }

    func testLabelAndTitleFromTheSessionFolder() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("ptb-kimi-activity-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base) }
        let session = base.appendingPathComponent("sessions/wd_my-app_0123456789ab/session_1")
        let main = session.appendingPathComponent("agents/main")
        try FileManager.default.createDirectory(at: main, withIntermediateDirectories: true)
        let wire = main.appendingPathComponent("wire.jsonl")
        try (Wire.metadata + "\n").write(to: wire, atomically: true, encoding: .utf8)
        let source = AgentLogSource.kimiCode()

        XCTAssertEqual(source.pathLabel?(wire), "my-app", "no state file yet: the workspace folder's slug")
        XCTAssertEqual(source.externalTitle?(wire), AgentSessionTitle())

        try #"{"id":"session_1","version":2,"title":"Fix login bug","titleKind":"generated","isCustomTitle":false,"cwd":"/Users/me/code/My App","createdAt":1,"updatedAt":2,"archived":false,"agents":{"main":{"type":"main"}},"custom":{}}"#
            .write(to: session.appendingPathComponent("state.json"), atomically: true, encoding: .utf8)
        XCTAssertEqual(source.pathLabel?(wire), "My App", "the real folder name, not the lower-cased slug")
        XCTAssertEqual(source.externalTitle?(wire).text, "Fix login bug")
    }
}
