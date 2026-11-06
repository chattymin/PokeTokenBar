import XCTest
@testable import PokeTokenBar

/// `updates.jsonl` lines shaped like Grok Build CLI writes them: the `_x.ai/session/update` envelope
/// of `GrokUsageTests`, ACP updates (`user_message_chunk`, `tool_call`, …) and the CLI's own
/// (`turn_completed`, bookkeeping) as serde writes them (snake_case tag, compact JSON). Keys
/// checked against xai-org/grok-build `main` (2026-11); content is made up.
private enum GrokLine {
    static func envelope(_ update: String, meta: String = "") -> String {
        let meta = #""eventId":""# + UUID().uuidString + #"","agentTimestampMs":1785000000000"# + meta
        return #"{"timestamp":1785000000,"method":"_x.ai/session/update","params":{"sessionId":"s1","update":"#
            + update + #","_meta":{"# + meta + "}}}"
    }

    static let prompt = envelope(#"{"sessionUpdate":"user_message_chunk","content":{"type":"text","text":"Fix the login bug"},"_meta":{"modelId":"grok-build-1","promptIndex":0}}"#)
    static func chunk(_ text: String = "hi") -> String {
        envelope(#"{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":""# + text + #""}}"#,
                 meta: #","chunkId":0"#)
    }
    static let thought = envelope(#"{"sessionUpdate":"agent_thought_chunk","content":{"type":"text","text":"Looking"}}"#)
    static let toolCall = envelope(#"{"sessionUpdate":"tool_call","toolCallId":"call_1","title":"ls","kind":"execute","status":"pending","rawInput":{"command":"ls"}}"#)
    static let toolDone = envelope(#"{"sessionUpdate":"tool_call_update","toolCallId":"call_1","status":"completed"}"#)
    static func completed(_ reason: String, prompt: String = "p-1", meta: String = "") -> String {
        envelope(#"{"sessionUpdate":"turn_completed","prompt_id":""# + prompt + #"","stop_reason":""# + reason
            + #"","usage":{"inputTokens":100,"outputTokens":20,"totalTokens":120},"elapsed_ms":1500}"#,
            meta: #","promptId":""# + prompt + #"""# + meta)
    }
    /// Written around a turn without starting one.
    static let bookkeeping = [
        envelope(#"{"sessionUpdate":"memory_capture_activity","status":"queued","attempt":0}"#),
        envelope(#"{"sessionUpdate":"background_tasks","tasks":[]}"#),
        envelope(#"{"sessionUpdate":"session_summary_generated","summary":"Fix login"}"#),
        envelope(#"{"sessionUpdate":"plan_kept","plan_uri":"file:///p.md","content":"x"}"#),
    ]
}

final class GrokActivityTests: XCTestCase {
    private func reading(_ lines: String...) -> AgentLogReading? { reading(lines) }
    private func reading(_ lines: [String]) -> AgentLogReading? {
        GrokActivity.reading(lines: lines.map { Substring($0) })
    }

    func testTurnStatesFromTheNewestMeaningfulLine() {
        XCTAssertEqual(reading(GrokLine.prompt)?.activity, .working)
        XCTAssertEqual(reading(GrokLine.prompt, GrokLine.thought, GrokLine.toolCall)?.activity, .working)
        XCTAssertEqual(reading(GrokLine.toolCall, GrokLine.toolDone)?.activity, .working)
        XCTAssertEqual(reading(GrokLine.chunk(), GrokLine.completed("end_turn"))?.activity, .done(message: nil))
        XCTAssertEqual(reading(GrokLine.completed("end_turn"), GrokLine.prompt)?.activity, .working, "the next prompt")
    }

    /// `turn_completed` is also how Esc and failures end a turn (`cancel.rs`, `prompt_complete_fields`).
    func testStopReasons() {
        for reason in ["end_turn", "max_tokens", "max_turn_requests", "refusal"] {
            XCTAssertEqual(reading(GrokLine.completed(reason))?.activity, .done(message: nil), reason)
        }
        for reason in ["cancelled", "error", "rate_limit", "something_new"] {
            XCTAssertEqual(reading(GrokLine.toolCall, GrokLine.completed(reason))?.activity, .idle, reason)
        }
    }

    func testDoneCarriesThePromptID() throws {
        let done = try XCTUnwrap(reading(GrokLine.completed("end_turn", prompt: "p-42")))
        XCTAssertEqual(done.lineID, "p-42")
        XCTAssertNil(done.label, "the label comes from the path")
        XCTAssertNotEqual(reading(GrokLine.completed("end_turn", prompt: "p-43"))?.lineID, done.lineID,
                          "two turns ending in one batch of events stay two")
    }

    func testBookkeepingAfterTheTurnKeepsItDone() {
        XCTAssertEqual(reading([GrokLine.completed("end_turn")] + GrokLine.bookkeeping)?.activity, .done(message: nil))
        XCTAssertNil(reading(GrokLine.bookkeeping))
        XCTAssertNil(reading("not json", ""))
    }

    /// Streaming text is one line per chunk; a batch is mostly chunks.
    func testChunkHeavyBatches() {
        let chunks = (0..<20_000).map { GrokLine.chunk("part \($0)") }
        XCTAssertEqual(reading(chunks + [GrokLine.completed("end_turn")])?.activity, .done(message: nil))
        XCTAssertEqual(reading([GrokLine.completed("end_turn"), GrokLine.prompt] + chunks)?.activity, .working)
    }

    /// Agent text can quote a session log; the escaped copy is not a line of its own.
    func testQuotedUpdatesDoNotMatch() {
        let quoted = GrokLine.chunk(#"{\"sessionUpdate\":\"turn_completed\",\"stop_reason\":\"end_turn\"}"#)
        XCTAssertEqual(reading(GrokLine.toolCall, quoted)?.activity, .working)
    }

    func testReplayedAndUnwrappedLines() {
        let replayed = GrokLine.completed("end_turn", prompt: "p-old", meta: #","isReplay":true"#)
        XCTAssertEqual(reading(GrokLine.toolCall, replayed)?.activity, .working, "a replayed end is not this turn's")
        let bare = #"{"sessionId":"s1","update":{"sessionUpdate":"turn_completed","prompt_id":"p-9","stop_reason":"end_turn"}}"#
        XCTAssertEqual(reading(bare)?.lineID, "p-9", "older lines carry the notification without the envelope")
    }

    private func turns(_ lines: String..., from start: AgentTurnState = AgentTurnState()) -> AgentTurnState {
        GrokActivity.turns(lines: lines.map { Substring($0) }, from: start)
    }

    /// Grok wakes itself (a background task finished, `/loop` fired); those ends are not news.
    func testTurnsGrokStartedItselfAreAutomatic() {
        XCTAssertEqual(turns(GrokLine.prompt, GrokLine.completed("end_turn", prompt: "6f1c")),
                       AgentTurnState(open: false, automatic: false))
        for prompt in ["task-completed-t1", "subagent-completed-a1", "scheduler-fired-3", "notifications-7",
                       "parent-agent-message-m1", "goal-summary-2"] {
            XCTAssertEqual(turns(GrokLine.prompt, GrokLine.completed("end_turn", prompt: prompt)),
                           AgentTurnState(open: false, automatic: true), prompt)
        }
        XCTAssertFalse(turns(GrokLine.completed("end_turn", prompt: "plan-resume-1")).automatic,
                       "the person approved the plan and waits for it")
        let afterWake = AgentTurnState(open: false, automatic: true)
        XCTAssertEqual(turns(GrokLine.prompt, GrokLine.chunk(), from: afterWake), AgentTurnState(open: true, automatic: false),
                       "the next prompt starts a fresh turn")
        XCTAssertEqual(turns(GrokLine.chunk(), from: afterWake), afterWake, "chunks change nothing")
    }

    // MARK: Files next to the log

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ptb-grok-activity-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// `<root>/<cwd folder>/<session>/updates.jsonl`, as the CLI lays it out.
    @discardableResult
    private func session(cwdFolder: String, id: String = UUID().uuidString, summary: String? = nil,
                         lines: [String] = [GrokLine.prompt]) throws -> URL {
        let dir = root.appendingPathComponent(cwdFolder).appendingPathComponent(id)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let summary { try summary.write(to: dir.appendingPathComponent("summary.json"), atomically: true, encoding: .utf8) }
        let updates = dir.appendingPathComponent("updates.jsonl")
        try (lines.joined(separator: "\n") + "\n").write(to: updates, atomically: true, encoding: .utf8)
        return updates
    }

    private func summary(title: String? = nil, manual: Bool = false, summary: String = "", kind: String? = nil,
                         cwd: String = "/Users/me/code/web-app") -> String {
        var fields = [#""info":{"id":"s1","cwd":""# + cwd + #""}"#, #""session_summary":""# + summary + #"""#,
                      #""title_is_manual":"# + (manual ? "true" : "false")]
        if let title { fields.append(#""generated_title":""# + title + #"""#) }
        if let kind { fields.append(#""session_kind":""# + kind + #"""#) }
        return "{" + fields.joined(separator: ",") + "}"
    }

    /// `urlencoding::encode` of the cwd, the CLI's folder name for paths that fit.
    private func encoded(_ cwd: String) -> String {
        cwd.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~"))!
    }

    func testLabelDecodesTheWorkingFolder() throws {
        XCTAssertEqual(GrokActivity.label(updatesFile: try session(cwdFolder: encoded("/Users/me/code/my app"))), "my app")
        XCTAssertEqual(GrokActivity.label(updatesFile: try session(cwdFolder: encoded("/Users/me/코드/결제-서버"))), "결제-서버")
        XCTAssertNil(GrokActivity.label(cwdFolderName: "web-app-0123456789abcdef"), "the hashed form decodes to no path")
        XCTAssertNil(GrokActivity.label(cwdFolderName: encoded("/")))
    }

    /// A cwd too long for a folder name: `<slug>-<hash>` with the path in `.cwd`, else `summary.json`.
    func testLabelOfAHashedFolderComesFromItsFiles() throws {
        let withFile = try session(cwdFolder: "long-0123456789abcdef")
        try "/Users/me/very/long/checkout\n".write(to: root.appendingPathComponent("long-0123456789abcdef/.cwd"),
                                                  atomically: true, encoding: .utf8)
        XCTAssertEqual(GrokActivity.label(updatesFile: withFile), "checkout")
        let fromSummary = try session(cwdFolder: "other-fedcba9876543210", summary: summary(cwd: "/Users/me/api"))
        XCTAssertEqual(GrokActivity.label(updatesFile: fromSummary), "api")
        XCTAssertNil(GrokActivity.label(updatesFile: try session(cwdFolder: "bare-00112233aabbccdd")))
    }

    func testTitleFromTheSummaryNextToTheLog() throws {
        let source = AgentLogSource.grok()
        let externalTitle = try XCTUnwrap(source.externalTitle)
        let folder = encoded("/Users/me/web")
        XCTAssertEqual(externalTitle(try session(cwdFolder: folder, summary: summary(title: "Fix login bug"))),
                       AgentSessionTitle(named: nil, generated: "Fix login bug"))
        XCTAssertEqual(externalTitle(try session(cwdFolder: folder, summary: summary(title: "auth", manual: true))),
                       AgentSessionTitle(named: "auth", generated: nil), "a /rename")
        XCTAssertEqual(externalTitle(try session(cwdFolder: folder, summary: summary(summary: "Fix the login bug"))).text,
                       "Fix the login bug", "the CLI shows session_summary until a title exists")
        XCTAssertEqual(externalTitle(try session(cwdFolder: folder, summary: summary(title: "  "))), AgentSessionTitle())
        XCTAssertEqual(externalTitle(try session(cwdFolder: folder)), AgentSessionTitle(), "no summary yet")
        XCTAssertEqual(externalTitle(try session(cwdFolder: folder, summary: #"{"generated_title":"half"#)),
                       AgentSessionTitle(), "caught mid-write")
    }

    /// Subagents run in sessions of their own; their turns ending is not the person's turn ending.
    func testSourceSkipsSubagentSessions() throws {
        let source = AgentLogSource.grok()
        XCTAssertEqual(source.id, "grok", "the usage provider's id")
        XCTAssertNil(source.hooks)
        let folder = encoded("/Users/me/web")
        XCTAssertTrue(source.accepts(try session(cwdFolder: folder, summary: summary())))
        XCTAssertTrue(source.accepts(try session(cwdFolder: folder)), "summary not written yet")
        XCTAssertTrue(source.accepts(try session(cwdFolder: folder, summary: summary(kind: "fork"))))
        for kind in ["subagent", "subagent_fork", "subagent_resume"] {
            XCTAssertFalse(source.accepts(try session(cwdFolder: folder, summary: summary(kind: kind))), kind)
        }
        let updates = try session(cwdFolder: folder, summary: summary())
        XCTAssertFalse(source.accepts(updates.deletingLastPathComponent().appendingPathComponent("summary.json")))
        XCTAssertFalse(source.accepts(updates.deletingLastPathComponent().appendingPathComponent("chat_history.jsonl")))
    }
}

/// The Grok pieces on the real FSEvents path, with the roots pointed at a temporary folder.
final class GrokActivityWatcherTests: XCTestCase {
    private final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [AgentLogReading] = []
        func append(_ r: AgentLogReading) { lock.lock(); items.append(r); lock.unlock() }
        var all: [AgentLogReading] { lock.lock(); defer { lock.unlock() }; return items }
    }

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GrokActivityWatcherTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func source() -> AgentLogSource {
        let grok = AgentLogSource.grok()
        let root = root!
        return AgentLogSource(id: grok.id, roots: { [root] }, accepts: grok.accepts, interpret: grok.interpret,
                              hooks: nil, turns: grok.turns, externalTitle: grok.externalTitle, pathLabel: grok.pathLabel)
    }

    private func append(_ lines: [String], to file: URL) throws {
        if !FileManager.default.fileExists(atPath: file.path) { try Data().write(to: file) }
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(lines.map { $0 + "\n" }.joined().utf8))
        try handle.close()
    }

    func testDoneIsLabeledAndTitledAndWakeUpsStayQuiet() throws {
        let received = Box()
        let done = expectation(description: "done")
        let wake = expectation(description: "the wake-up turn ended")
        wake.assertForOverFulfill = false
        let watcher = AgentLogWatcher(sources: [source()]) { reading, _, _ in
            received.append(reading)
            if case .done = reading.activity { done.fulfill() }
            if reading.activity == .idle { wake.fulfill() }
        }
        watcher.start()
        defer { watcher.stop() }
        Thread.sleep(forTimeInterval: 0.5)

        let sessionDir = root.appendingPathComponent("%2FUsers%2Fme%2Fcode%2Fweb-app/0199aa00-1111-7000-8000-000000000001")
        let subagentDir = root.appendingPathComponent("%2FUsers%2Fme%2Fcode%2Fweb-app/0199aa00-2222-7000-8000-000000000002")
        for dir in [sessionDir, subagentDir] { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
        try #"{"info":{"cwd":"/Users/me/code/web-app"},"session_summary":"","generated_title":"Fix login bug","title_is_manual":false}"#
            .write(to: sessionDir.appendingPathComponent("summary.json"), atomically: true, encoding: .utf8)
        try #"{"info":{"cwd":"/Users/me/code/web-app"},"session_summary":"","title_is_manual":false,"session_kind":"subagent"}"#
            .write(to: subagentDir.appendingPathComponent("summary.json"), atomically: true, encoding: .utf8)

        let updates = sessionDir.appendingPathComponent("updates.jsonl")
        try append([GrokLine.prompt, GrokLine.chunk()], to: updates)
        try append([GrokLine.prompt, GrokLine.completed("end_turn", prompt: "p-sub")],
                   to: subagentDir.appendingPathComponent("updates.jsonl"))
        Thread.sleep(forTimeInterval: 0.6)
        try append((0..<2_000).map { GrokLine.chunk("part \($0)") } + [GrokLine.completed("end_turn", prompt: "p-1")],
                   to: updates)
        wait(for: [done], timeout: 5)
        let finished = try XCTUnwrap(received.all.last)
        XCTAssertEqual(finished.label, "web-app")
        XCTAssertEqual(finished.title, "Fix login bug")
        XCTAssertEqual(finished.lineID, "p-1", "the subagent's done never arrives")

        Thread.sleep(forTimeInterval: 0.6)
        try append([GrokLine.prompt, GrokLine.chunk(), GrokLine.completed("end_turn", prompt: "task-completed-t1")],
                   to: updates)
        wait(for: [wake], timeout: 5)
        XCTAssertEqual(received.all.filter { if case .done = $0.activity { true } else { false } }.count, 1,
                       "a turn Grok started itself ends quietly")
    }
}
