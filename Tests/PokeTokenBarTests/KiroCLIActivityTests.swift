import XCTest
@testable import PokeTokenBar

/// Kiro v3 rows `{id, timestamp, payload: {type, …}}` (lpaiu-cs/osk-system `osk/transcripts.py`
/// `_kiro`; the app's `KiroUsageTests` v3 fixtures) and classic `{version, kind, data}` lines
/// (`KiroUsageTests` / `KiroContentBlockTests`, CLI 2.25.0 shapes). Fields beyond `type` on
/// `pending_interaction` / `interaction_resolved` are made up; so is all content.
private enum KiroLine {
    private static func row(_ payload: String, id: String = UUID().uuidString) -> String {
        #"{"id":""# + id + #"","timestamp":"2026-11-05T05:56:45.000Z","payload":"# + payload + "}"
    }

    static let prompt = row(#"{"type":"user","content":"Fix the login bug"}"#)
    static func turnStart(_ execution: String = "exec-1") -> String {
        row(#"{"type":"turn_start","executionId":""# + execution + #""}"#)
    }
    static let reasoning = row(#"{"type":"assistant","operationType":"Reasoning","content":"Look at the token refresh."}"#)
    static let say = row(#"{"type":"assistant","operationType":"Say","content":"Fixed it."}"#)
    static let summary = row(#"{"type":"assistant","operationType":"Summary","content":"Earlier: login work."}"#)
    static let toolCall = row(#"{"type":"tool_call","toolCallId":"t1","toolName":"fs_read","args":"{\"path\":\"src/login.ts\",\"type\":\"user\"}"}"#)
    static let toolResult = row(#"{"type":"tool_result","toolCallId":"t1","content":"export function login() {}"}"#)
    static let pending = row(#"{"type":"pending_interaction","toolCallId":"t1"}"#)
    static let resolved = row(#"{"type":"interaction_resolved","toolCallId":"t1"}"#)
    static let subAgent = row(#"{"type":"sub_agent_start","subSessionId":"sess_sub","subAgentName":"explorer","prompt":"Find callers"}"#)
    static let usage = row(#"{"type":"usage_summary","requestIds":["q1","q2"],"elapsedTime":5000}"#)
    static let metadata = row(#"{"type":"session_metadata","key":"contextUsage","value":{"usagePercentage":12.5}}"#)
    static func turnEnd(_ reason: String? = "end_turn", execution: String = "exec-1", id: String = UUID().uuidString) -> String {
        let stop = reason.map { #","stopReason":""# + $0 + #"""# } ?? ""
        return row(#"{"type":"turn_end","executionId":""# + execution + #"""# + stop + "}", id: id)
    }

    static let classicPrompt = #"{"version":"v1","kind":"Prompt","data":{"message_id":"prompt-1","content":[{"kind":"text","data":"Fix the login bug"}],"meta":{"timestamp":1770983426.42}}}"#
    static let classicToolUse = #"{"version":"v1","kind":"AssistantMessage","data":{"message_id":"assistant-1","content":[{"kind":"thinking","data":{"text":"check"}},{"kind":"toolUse","data":{"toolUseId":"t1","name":"fs_read","input":{"path":"src/login.ts"}}}]}}"#
    static let classicResults = #"{"version":"v1","kind":"ToolResults","data":{"message_id":"results-1","content":[{"kind":"toolResult","data":{"toolUseId":"t1","content":[{"kind":"text","data":"ok"}],"status":"success"}}]}}"#
    static let classicReply = #"{"version":"v1","kind":"AssistantMessage","data":{"message_id":"assistant-2","content":[{"kind":"text","data":"Fixed it."}]}}"#
    static let classicClear = #"{"version":"v1","kind":"Clear","data":{}}"#
}

final class KiroCLIActivityTests: XCTestCase {
    private func reading(_ lines: String...) -> AgentLogReading? {
        KiroCLIActivity.reading(lines: lines.map { Substring($0) })
    }

    private func activity(_ lines: String...) -> AgentActivity? {
        KiroCLIActivity.reading(lines: lines.map { Substring($0) })?.activity
    }

    func testV3TurnStates() throws {
        XCTAssertEqual(activity(KiroLine.prompt), .working)
        XCTAssertEqual(activity(KiroLine.prompt, KiroLine.turnStart(), KiroLine.reasoning), .working)
        XCTAssertEqual(activity(KiroLine.toolCall, KiroLine.toolResult, KiroLine.subAgent), .working)
        let done = try XCTUnwrap(reading(KiroLine.say, KiroLine.usage, KiroLine.turnEnd(id: "row-42"), KiroLine.metadata))
        XCTAssertEqual(done.activity, .done(message: nil))
        XCTAssertEqual(done.lineID, "row-42")
        XCTAssertEqual(activity(KiroLine.turnEnd(), KiroLine.prompt), .working, "the next request")
    }

    /// Only `end_turn` is a finished request; anything else ended it some other way.
    func testOtherTurnEndsAreIdle() {
        for reason in ["cancelled", "error", "content_filtered", "max_tokens"] {
            XCTAssertEqual(activity(KiroLine.toolCall, KiroLine.turnEnd(reason)), .idle, reason)
        }
        XCTAssertEqual(activity(KiroLine.toolCall, KiroLine.turnEnd(nil)), .idle, "no reason given")
    }

    func testAToolApprovalIsWaiting() throws {
        let waiting = try XCTUnwrap(reading(KiroLine.toolCall, KiroLine.pending))
        XCTAssertEqual(waiting.activity, .waiting(message: nil))
        XCTAssertNotNil(waiting.lineID)
        XCTAssertEqual(activity(KiroLine.pending, KiroLine.resolved), .working)
        XCTAssertEqual(activity(KiroLine.pending, KiroLine.resolved, KiroLine.toolResult), .working)
    }

    func testCompactionAndBookkeepingAreSkipped() {
        XCTAssertEqual(activity(KiroLine.turnEnd(), KiroLine.summary, KiroLine.usage, KiroLine.metadata), .done(message: nil),
                       "a compaction summary outside a turn starts nothing")
        XCTAssertNil(reading(KiroLine.summary, KiroLine.usage, KiroLine.metadata, "not json", ""))
    }

    private func turns(_ lines: String..., from start: AgentTurnState = AgentTurnState()) -> AgentTurnState {
        KiroCLIActivity.turns(lines: lines.map { Substring($0) }, from: start)
    }

    func testTurnsWithoutAPromptAreAutomatic() {
        XCTAssertFalse(turns(KiroLine.prompt, KiroLine.turnStart()).automatic)
        XCTAssertTrue(turns(KiroLine.prompt, KiroLine.turnStart(), KiroLine.turnEnd(), KiroLine.turnStart("exec-2")).automatic,
                      "a turn nobody typed for")
        XCTAssertFalse(turns(KiroLine.turnStart(), KiroLine.prompt, KiroLine.turnEnd(), KiroLine.turnStart("exec-2")).automatic,
                       "a prompt queued during the previous turn opens the next one")
        XCTAssertFalse(turns(KiroLine.turnStart(), KiroLine.toolCall).automatic, "first sight: the tail starts mid-turn")
        let afterPrompt = turns(KiroLine.turnEnd(), KiroLine.prompt)
        XCTAssertFalse(turns(KiroLine.turnStart("exec-2"), from: afterPrompt).automatic,
                       "the prompt and its turn arrive in separate batches")
        XCTAssertEqual(turns(KiroLine.classicPrompt, KiroLine.classicReply), AgentTurnState(), "classic logs have no turns")
    }

    func testClassicLogsAreWorkingOrIdle() {
        XCTAssertEqual(activity(KiroLine.classicPrompt), .working)
        XCTAssertEqual(activity(KiroLine.classicPrompt, KiroLine.classicToolUse), .working)
        XCTAssertEqual(activity(KiroLine.classicToolUse, KiroLine.classicResults), .working)
        XCTAssertEqual(activity(KiroLine.classicResults, KiroLine.classicReply), .idle,
                       "a reply without tool use ends the loop, but nothing confirms it: idle, not done")
        XCTAssertEqual(activity(KiroLine.classicReply, KiroLine.classicClear), .idle)
        let all = [KiroLine.classicPrompt, KiroLine.classicToolUse, KiroLine.classicResults, KiroLine.classicReply, KiroLine.classicClear]
        for end in all.indices {
            let activity = KiroCLIActivity.reading(lines: all[...end].map { Substring($0) })?.activity
            if case .done = activity { XCTFail("done after classic line \(end)") }
        }
    }

    func testLabelsComeFromTheCompanionFile() throws {
        XCTAssertEqual(KiroCLIActivity.label(companion: ["workspacePaths": ["/Users/me/code/web app", "/x"]], v3: true), "web app")
        XCTAssertEqual(KiroCLIActivity.label(companion: ["cwd": "/Users/me/code/api"], v3: false), "api")
        XCTAssertNil(KiroCLIActivity.label(companion: ["cwd": "/Users/me/code/api"], v3: true))
        XCTAssertNil(KiroCLIActivity.label(companion: ["workspacePaths": []], v3: true))
        XCTAssertNil(KiroCLIActivity.label(companion: ["cwd": "/"], v3: false))
        XCTAssertNil(KiroCLIActivity.label(companion: nil, v3: true))

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("kiro-label-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let v3 = root.appendingPathComponent("sessions/4f1a/sess_abc", isDirectory: true)
        let cli = root.appendingPathComponent("sessions/cli", isDirectory: true)
        try FileManager.default.createDirectory(at: v3, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cli, withIntermediateDirectories: true)
        try Data(#"{"schemaVersion":"1.0.0","id":"sess_abc","title":"Fix login","workspacePaths":["/Users/me/code/web-app"]}"#.utf8)
            .write(to: v3.appendingPathComponent("session.json"))
        try Data(#"{"session_id":"s1","cwd":"/Users/me/code/api","created_at":"2026-11-05T05:56:40Z"}"#.utf8)
            .write(to: cli.appendingPathComponent("s1.json"))
        let v3Log = v3.appendingPathComponent("messages.jsonl")
        let cliLog = cli.appendingPathComponent("s1.jsonl")
        XCTAssertEqual(KiroCLIActivity.label(forLog: v3Log), "web-app")
        XCTAssertEqual(KiroCLIActivity.label(forLog: cliLog), "api")
        XCTAssertEqual(KiroCLIActivity.externalTitle(forLog: v3Log), AgentSessionTitle(named: nil, generated: "Fix login"))
        XCTAssertEqual(KiroCLIActivity.externalTitle(forLog: cliLog), AgentSessionTitle())
        XCTAssertNil(KiroCLIActivity.label(forLog: cli.appendingPathComponent("missing.jsonl")))
    }

    func testAcceptsBothLayoutsOnly() {
        XCTAssertTrue(KiroCLIActivity.accepts(URL(fileURLWithPath: "/h/.kiro/sessions/4f1a/sess_abc/messages.jsonl")))
        XCTAssertTrue(KiroCLIActivity.accepts(URL(fileURLWithPath: "/h/.kiro/sessions/cli/5f0c2a1e.jsonl")))
        XCTAssertFalse(KiroCLIActivity.accepts(URL(fileURLWithPath: "/h/.kiro/sessions/cli/5f0c2a1e.json")))
        XCTAssertFalse(KiroCLIActivity.accepts(URL(fileURLWithPath: "/h/.kiro/sessions/4f1a/sess_abc/session.json")))
        XCTAssertFalse(KiroCLIActivity.accepts(URL(fileURLWithPath: "/h/Library/Application Support/kiro-cli/data.sqlite3")))
    }

    func testSourceShape() {
        let source = AgentLogSource.kiroCLI()
        XCTAssertEqual(source.id, "kiro")
        XCTAssertNil(source.hooks)
        XCTAssertNil(source.head)
        XCTAssertNotNil(source.externalTitle)
        XCTAssertNotNil(source.pathLabel)
        XCTAssertNil(source.database)
    }
}

/// The Kiro source on the real FSEvents path: label and title from `session.json`, and a turn
/// nobody typed for ending without a done.
final class KiroCLIWatcherTests: XCTestCase {
    private final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [AgentLogReading] = []
        func append(_ r: AgentLogReading) { lock.lock(); items.append(r); lock.unlock() }
        var all: [AgentLogReading] { lock.lock(); defer { lock.unlock() }; return items }
    }

    func testV3SessionReachesThePet() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("KiroCLIWatcherTests-\(UUID().uuidString)", isDirectory: true)
        let session = root.appendingPathComponent("4f1a/sess_abc", isDirectory: true)
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(#"{"id":"sess_abc","title":"Fix login","workspacePaths":["/Users/me/code/web-app"]}"#.utf8)
            .write(to: session.appendingPathComponent("session.json"))
        let kiro = AgentLogSource.kiroCLI()
        let source = AgentLogSource(id: kiro.id, roots: { [root] }, accepts: kiro.accepts, interpret: kiro.interpret,
                                    hooks: nil, turns: kiro.turns, externalTitle: kiro.externalTitle,
                                    pathLabel: kiro.pathLabel)
        let received = Box()
        let done = expectation(description: "done for the person's request")
        let quiet = expectation(description: "an inputless turn ends without a done")
        let watcher = AgentLogWatcher(sources: [source]) { reading, _, _ in
            received.append(reading)
            if case .done = reading.activity { done.fulfill() }
            if reading.activity == .idle { quiet.fulfill() }
        }
        watcher.start()
        defer { watcher.stop() }
        Thread.sleep(forTimeInterval: 0.5)

        let log = session.appendingPathComponent("messages.jsonl")
        func append(_ text: String) throws {
            let handle = try FileHandle(forWritingTo: log)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(text.utf8))
            try handle.close()
        }
        try Data((KiroLine.prompt + "\n" + KiroLine.turnStart() + "\n").utf8).write(to: log)
        Thread.sleep(forTimeInterval: 0.6)
        try append(KiroLine.say + "\n" + KiroLine.turnEnd() + "\n")
        wait(for: [done], timeout: 5)
        let last = try XCTUnwrap(received.all.last)
        XCTAssertEqual(last.label, "web-app")
        XCTAssertEqual(last.title, "Fix login")
        XCTAssertEqual(received.all.first?.activity, .working)

        try append(KiroLine.turnStart("exec-2") + "\n")
        Thread.sleep(forTimeInterval: 0.6)
        try append(KiroLine.say + "\n" + KiroLine.turnEnd(execution: "exec-2") + "\n")
        wait(for: [quiet], timeout: 5)
        XCTAssertEqual(received.all.filter { if case .done = $0.activity { true } else { false } }.count, 1)
    }
}
