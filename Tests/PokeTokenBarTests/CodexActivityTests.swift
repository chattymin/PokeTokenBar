import XCTest
@testable import PokeTokenBar

/// Rollout lines shaped like Codex writes them (compact serde JSON, `{timestamp,type,payload}`).
/// Key order and fields follow `RolloutItemWire` / `EventMsg` / `ResponseItem` in openai/codex
/// (`codex-rs/history/src/rollout_payload.rs`, `codex-rs/protocol/src/{protocol,models}.rs`) and
/// real 0.118 / 0.142 rollouts (structure only, 2026-11); content is made up.
private enum Line {
    static let ts = "2026-11-05T05:56:45.000Z"

    static func event(_ payload: String) -> String {
        #"{"timestamp":""# + ts + #"","type":"event_msg","payload":"# + payload + "}"
    }

    static func item(_ payload: String) -> String {
        #"{"timestamp":""# + ts + #"","type":"response_item","payload":"# + payload + "}"
    }

    static func sessionMeta(cwd: String = "/Users/me/code/web-app", source: String = #""cli""#,
                            extra: String = "") -> String {
        #"{"timestamp":""# + ts + #"","type":"session_meta","payload":{"session_id":"019a0000-0000-7000-8000-000000000001","id":"019a0000-0000-7000-8000-000000000001","timestamp":""#
            + ts + #"","cwd":""# + cwd + #"","originator":"codex_cli_rs","cli_version":"0.142.5","source":"#
            + source + extra + #","model_provider":"openai","base_instructions":{"text":"You are Codex."},"git":{"branch":"main"}}}"#
    }

    static func turnContext(cwd: String = "/Users/me/code/web-app", turn: String = "turn-1") -> String {
        #"{"timestamp":""# + ts + #"","type":"turn_context","payload":{"turn_id":""# + turn + #"","cwd":""# + cwd
            + #"","current_date":"2026-11-05","timezone":"Asia/Seoul","approval_policy":"on-request","sandbox_policy":{"type":"workspace-write"},"model":"gpt-5.5","summary":"auto"}}"#
    }

    static func taskStarted(_ turn: String = "turn-1", type: String = "task_started") -> String {
        event(#"{"type":""# + type + #"","turn_id":""# + turn + #"","started_at":1762322205,"model_context_window":258400,"collaboration_mode_kind":"default"}"#)
    }

    static func taskComplete(_ turn: String = "turn-1", type: String = "task_complete", extra: String = "") -> String {
        event(#"{"type":""# + type + #"","turn_id":""# + turn + #"","last_agent_message":"Fixed it.","completed_at":1762322265,"duration_ms":60000"# + extra + "}")
    }

    static func turnAborted(_ reason: String, turn: String = "turn-1") -> String {
        event(#"{"type":"turn_aborted","turn_id":""# + turn + #"","reason":""# + reason + #""}"#)
    }

    static let userMessage = event(#"{"type":"user_message","message":"Fix the login bug","images":[],"local_images":[],"text_elements":[]}"#)
    static let tokenCount = event(#"{"type":"token_count","info":{"total_token_usage":{"input_tokens":10,"output_tokens":5,"total_tokens":15},"last_token_usage":{"input_tokens":10,"output_tokens":5,"total_tokens":15},"model_context_window":258400},"rate_limits":null}"#)
    static let agentReasoning = event(#"{"type":"agent_reasoning","text":"Looking at the login form"}"#)

    static func functionCall(_ name: String = "exec_command", callID: String = "call_1", extra: String = "") -> String {
        item(#"{"type":"function_call","name":""# + name + #"""# + extra + #","arguments":"{\"cmd\":\"ls\"}","call_id":""# + callID + #""}"#)
    }

    static func functionOutput(_ output: String = #""ok""#, callID: String = "call_1") -> String {
        item(#"{"type":"function_call_output","call_id":""# + callID + #"","output":"# + output + "}")
    }

    static let customToolCall = item(#"{"type":"custom_tool_call","status":"completed","call_id":"call_2","name":"apply_patch","input":"*** Begin Patch\n*** End Patch"}"#)
    static let customToolOutput = item(#"{"type":"custom_tool_call_output","call_id":"call_2","output":"Done!"}"#)
    static let webSearch = item(#"{"type":"web_search_call","status":"completed","action":{"type":"search","query":"swift"}}"#)
    static let reasoning = item(#"{"type":"reasoning","summary":[],"content":null,"encrypted_content":"gAAAA"}"#)
    static let assistantMessage = item(#"{"type":"message","role":"assistant","content":[{"type":"output_text","text":"Done."}],"phase":"final_answer"}"#)
    static let developerMessage = item(#"{"type":"message","role":"developer","content":[{"type":"input_text","text":"<permissions instructions>"}]}"#)
    static let ask = functionCall("request_user_input", callID: "call_ask")
}

final class CodexActivityTests: XCTestCase {
    private func reading(_ lines: String...) -> AgentLogReading? {
        CodexRolloutActivity.reading(lines: lines.map { Substring($0) })
    }

    func testTurnStatesFromTheNewestMeaningfulLine() {
        XCTAssertEqual(reading(Line.taskStarted())?.activity, .working)
        XCTAssertEqual(reading(Line.taskStarted(type: "turn_started"))?.activity, .working, "v2 alias")
        XCTAssertEqual(reading(Line.taskStarted(), Line.userMessage)?.activity, .working)
        XCTAssertEqual(reading(Line.taskStarted(), Line.functionCall())?.activity, .working)
        XCTAssertEqual(reading(Line.functionCall(), Line.functionOutput())?.activity, .working)
        XCTAssertEqual(reading(Line.customToolCall, Line.customToolOutput)?.activity, .working)
        XCTAssertEqual(reading(Line.webSearch)?.activity, .working)
        XCTAssertEqual(reading(Line.reasoning)?.activity, .working)
        XCTAssertEqual(reading(Line.assistantMessage, Line.tokenCount, Line.taskComplete())?.activity, .done(message: nil))
        XCTAssertEqual(reading(Line.taskComplete(type: "turn_complete"))?.activity, .done(message: nil), "v2 alias")
        XCTAssertEqual(reading(Line.taskComplete(), Line.taskStarted("turn-2"))?.activity, .working, "the next turn started")
    }

    func testBookkeepingLinesAreSkipped() {
        XCTAssertEqual(reading(Line.taskComplete(), Line.tokenCount, Line.agentReasoning)?.activity, .done(message: nil))
        XCTAssertEqual(reading(Line.taskComplete(), Line.turnContext())?.activity, .done(message: nil))
        XCTAssertEqual(reading(Line.taskComplete(), Line.developerMessage)?.activity, .done(message: nil),
                       "only assistant messages count as work")
        XCTAssertNil(reading(Line.tokenCount, Line.turnContext(), Line.sessionMeta()))
        XCTAssertNil(reading("not json", ""))
    }

    func testAbortsAndFailuresAreIdle() {
        XCTAssertEqual(reading(Line.functionCall(), Line.turnAborted("interrupted"))?.activity, .idle, "Esc")
        XCTAssertEqual(reading(Line.functionCall(), Line.turnAborted("budget_limited"))?.activity, .idle)
        XCTAssertEqual(reading(Line.functionCall(), Line.turnAborted("review_ended"))?.activity, .idle)
        XCTAssertEqual(reading(Line.functionCall(), Line.turnAborted("replaced"))?.activity, .working,
                       "a replaced turn is followed by the turn that replaced it")
        let failed = Line.taskComplete(extra: #","error":{"message":"stream disconnected","codex_error_info":"other"}"#)
        XCTAssertEqual(reading(Line.functionCall(), failed)?.activity, .idle, "a turn that ended in an error")
    }

    func testAQuestionToThePersonIsWaiting() throws {
        let result = try XCTUnwrap(reading(Line.taskStarted(), Line.ask))
        XCTAssertEqual(result.activity, .waiting(message: nil))
        XCTAssertEqual(result.lineID, "call_ask")
        XCTAssertEqual(reading(Line.ask, Line.functionOutput(#""{\"answers\":{}}""#, callID: "call_ask"))?.activity,
                       .working, "answered: back to work")
        XCTAssertEqual(reading(Line.functionCall("request_user_input_async"))?.activity, .working,
                       "the async variant does not block the turn")
        XCTAssertEqual(reading(Line.functionCall("request_user_input", extra: #","namespace":"mcp__forms""#))?.activity,
                       .working, "a namespaced tool of the same name is someone else's")
    }

    func testLabelIsTheNewestTurnFolderAndDoneCarriesItsTurn() throws {
        let result = try XCTUnwrap(reading(Line.turnContext(cwd: "/Users/me/code/old"), Line.taskStarted(),
                                           Line.turnContext(cwd: "/Users/me/code/my app"), Line.taskComplete("turn-42")))
        XCTAssertEqual(result.label, "my app")
        XCTAssertEqual(result.lineID, "turn-42")
        XCTAssertNil(reading(Line.taskComplete())?.label, "no turn_context in the batch: the head's label is used")
        XCTAssertNotEqual(reading(Line.taskComplete("turn-1"))?.lineID, reading(Line.taskComplete("turn-2"))?.lineID,
                          "two turns ending in one batch are two dones")
    }

    /// Tool output can quote another rollout; the escaped copy must not count as a record.
    func testNestedRolloutTextDoesNotMatch() {
        let quoted = Line.functionOutput(#""{\"timestamp\":\"x\",\"type\":\"event_msg\",\"payload\":{\"type\":\"task_complete\",\"turn_id\":\"t\"}}""#)
        XCTAssertEqual(reading(Line.functionCall(), quoted)?.activity, .working)
        let quotedAbort = Line.userMessage.replacingOccurrences(
            of: "Fix the login bug", with: #"{\"type\":\"turn_aborted\",\"reason\":\"interrupted\"}"#)
        XCTAssertEqual(reading(Line.taskComplete(), quotedAbort)?.activity, .working)
        // `compacted` keeps a replacement history of real (unescaped) response items.
        let compacted = #"{"timestamp":"t","type":"compacted","payload":{"message":"","replacement_history":[{"type":"function_call","name":"request_user_input","arguments":"{}","call_id":"c"}]}}"#
        XCTAssertEqual(reading(Line.taskComplete(), compacted)?.activity, .done(message: nil))
    }

    // MARK: Head

    private func head(_ lines: String...) -> AgentLogHead {
        CodexRolloutActivity.head(lines: lines.map { Substring($0) })
    }

    func testHeadGivesTheSessionFolder() {
        XCTAssertEqual(head(Line.sessionMeta(cwd: "/Users/me/code/api"), Line.taskStarted()),
                       AgentLogHead(label: "api", skip: false))
        XCTAssertEqual(head(Line.sessionMeta(source: #""vscode""#, extra: #","thread_source":"user""#)).skip, false)
        XCTAssertEqual(head(Line.taskStarted()), AgentLogHead(), "no session_meta")
    }

    /// Shaped like `Tests/PokeTokenBarTests/Fixtures/CodexSubagent/child.jsonl` (Codex 0.142).
    func testSubagentAndHelperThreadsAreSkipped() {
        let spawned = #"{"subagent":{"thread_spawn":{"parent_thread_id":"019a0000-0000-7000-8000-000000000001","depth":1}}}"#
        XCTAssertTrue(head(Line.sessionMeta(source: spawned, extra: #","thread_source":"subagent""#)).skip)
        XCTAssertTrue(head(Line.sessionMeta(source: #"{"subagent":"review"}"#)).skip)
        XCTAssertTrue(head(Line.sessionMeta(extra: #","thread_source":"subagent""#)).skip, "thread_source alone")
        XCTAssertTrue(head(Line.sessionMeta(source: #"{"internal":"memory_consolidation"}"#)).skip)
        XCTAssertTrue(head(Line.sessionMeta(extra: #","thread_source":"guardian_review""#)).skip)
        XCTAssertFalse(head(Line.sessionMeta(source: #""exec""#)).skip, "`codex exec` is the person's own run")
    }

    // MARK: Files

    func testOnlyLiveRolloutsAreWatched() {
        let accepts = AgentLogSource.codex().accepts
        XCTAssertTrue(accepts(URL(fileURLWithPath: "/h/.codex/sessions/2026/11/05/rollout-2026-11-05T10-00-00-019a0000-0000-7000-8000-000000000001.jsonl")))
        XCTAssertFalse(accepts(URL(fileURLWithPath: "/h/.codex/archived_sessions/rollout-2026-11-05T10-00-00-019a.jsonl")))
        XCTAssertFalse(accepts(URL(fileURLWithPath: "/h/.codex/sessions/2026/11/05/rollout-2026-11-05T10-00-00-019a.jsonl.zst")))
        XCTAssertFalse(accepts(URL(fileURLWithPath: "/h/.codex/session_index.jsonl")))
    }

    func testThreadIDFromTheFileName() {
        let id = "019a0000-0000-7000-8000-000000000001"
        XCTAssertEqual(CodexRolloutActivity.threadID(fileName: "rollout-2026-11-05T10-00-00-\(id).jsonl"), id)
        XCTAssertEqual(CodexRolloutActivity.threadID(fileName: "rollout-2026-11-05T10-00-00-\(id)_019b0000-0000-7000-8000-000000000002.jsonl"),
                       id, "a reverted thread keeps its thread id before `_`")
        XCTAssertNil(CodexRolloutActivity.threadID(fileName: "rollout-2026-11-05.jsonl"))
        XCTAssertNil(CodexRolloutActivity.threadID(fileName: "notes.jsonl"))
    }

    func testIndexSitsNextToTheSessionsFolder() {
        let rollout = URL(fileURLWithPath: "/work/codex-home/sessions/2026/11/05/rollout-x.jsonl")
        XCTAssertEqual(CodexRolloutActivity.indexURL(rollout: rollout)?.path, "/work/codex-home/session_index.jsonl")
        XCTAssertNil(CodexRolloutActivity.indexURL(rollout: URL(fileURLWithPath: "/elsewhere/rollout-x.jsonl")))
    }

    // MARK: Titles

    private func indexLine(_ id: String, _ name: String) -> String {
        #"{"id":""# + id + #"","thread_name":""# + name + #"","updated_at":"2026-11-05T05:56:45Z"}"#
    }

    func testTheNewestNameInTheIndexWins() {
        let a = "019a0000-0000-7000-8000-00000000000a", b = "019a0000-0000-7000-8000-00000000000b"
        let lines = [indexLine(a, "login fix"), indexLine(b, "billing"), indexLine(a, "auth"), indexLine(a, "  ")]
            .map { Substring($0) }
        XCTAssertEqual(CodexRolloutActivity.indexedName(threadID: a, lines: lines), "auth", "a blank name is skipped")
        XCTAssertEqual(CodexRolloutActivity.indexedName(threadID: b, lines: lines), "billing")
        XCTAssertNil(CodexRolloutActivity.indexedName(threadID: "019a0000-0000-7000-8000-00000000000c", lines: lines))
        let mentions = [Substring(indexLine(b, "follow-up to \(a)"))]
        XCTAssertNil(CodexRolloutActivity.indexedName(threadID: a, lines: mentions), "another thread's name quoting the id")
    }

    func testExternalTitleReadsTheIndexTail() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("codex-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let day = home.appendingPathComponent("sessions/2026/11/05")
        try FileManager.default.createDirectory(at: day, withIntermediateDirectories: true)
        let id = "019a0000-0000-7000-8000-000000000001"
        let rollout = day.appendingPathComponent("rollout-2026-11-05T10-00-00-\(id).jsonl")
        try (Line.sessionMeta() + "\n").write(to: rollout, atomically: true, encoding: .utf8)
        let title = try XCTUnwrap(AgentLogSource.codex().externalTitle)

        XCTAssertEqual(title(rollout), AgentSessionTitle(), "no index yet")
        // Older than the tail that is read, then the current name.
        let filler = String(repeating: indexLine("019a0000-0000-7000-8000-0000000000ff", "other") + "\n", count: 4000)
        let index = indexLine(id, "too old to see") + "\n" + filler + indexLine(id, "auth rewrite") + "\n"
        XCTAssertGreaterThan(UInt64(index.utf8.count), CodexRolloutActivity.indexTailBytes)
        try index.write(to: home.appendingPathComponent("session_index.jsonl"), atomically: true, encoding: .utf8)
        XCTAssertEqual(title(rollout), AgentSessionTitle(named: "auth rewrite", generated: nil))
    }
}
