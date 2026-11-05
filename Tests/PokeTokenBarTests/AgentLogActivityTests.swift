import XCTest
@testable import PokeTokenBar

/// Transcript lines shaped like Claude Code 2.x writes them (compact JSON, one object per line).
/// Keys checked against real transcripts (2026-11); content is made up.
private enum Line {
    static func assistant(stop: String, blocks: String = #"[{"type":"text","text":"Done."}]"#,
                          uuid: String = UUID().uuidString, cwd: String = "/Users/me/code/web-app",
                          extra: String = "") -> String {
        #"{"parentUuid":"p","isSidechain":false,"userType":"external","cwd":""# + cwd
            + #"","sessionId":"s","version":"2.1.0","gitBranch":"main","message":{"id":"msg_1","type":"message","role":"assistant","model":"claude-opus-5-5","content":"#
            + blocks + #","stop_reason":""# + stop + #"","stop_sequence":null,"usage":{"input_tokens":3,"output_tokens":9}},"requestId":"req_1","type":"assistant","uuid":""#
            + uuid + #"","timestamp":"2026-11-05T05:56:45.000Z""# + extra + "}"
    }

    static func user(content: String, cwd: String = "/Users/me/code/web-app", extra: String = "") -> String {
        #"{"parentUuid":"p","isSidechain":false,"userType":"external","cwd":""# + cwd
            + #"","sessionId":"s","version":"2.1.0","gitBranch":"main","type":"user","message":{"role":"user","content":"#
            + content + #"},"uuid":""# + UUID().uuidString + #"","timestamp":"2026-11-05T05:56:46.000Z""# + extra + "}"
    }

    static let prompt = user(content: #""Fix the login bug""#)
    static let toolResult = user(content: #"[{"tool_use_id":"toolu_1","type":"tool_result","content":"ok"}]"#)
    static let toolUse = assistant(stop: "tool_use", blocks: #"[{"type":"tool_use","id":"toolu_1","name":"Bash","input":{"command":"ls"}}]"#)
    static let ask = assistant(stop: "tool_use",
                               blocks: #"[{"type":"tool_use","id":"toolu_2","name":"AskUserQuestion","input":{"questions":[]}}]"#)
    static let interrupted = user(content: #"[{"type":"text","text":"[Request interrupted by user]"}]"#)
    static let interruptedForTool = user(content: #"[{"type":"text","text":"[Request interrupted by user for tool use]"}]"#)
    static let localCommand = user(content: #""<command-name>/model</command-name>""#)
    static let localStdout = user(content: #""<local-command-stdout>Set model</local-command-stdout>""#)
    static let meta = user(content: #""Caveat: local command""#, extra: #","isMeta":true"#)
    static let lastPrompt = #"{"type":"last-prompt","lastPrompt":"Fix the login bug","sessionId":"s"}"#
    static let attachment = #"{"type":"attachment","attachment":{"type":"hook"},"uuid":"a","timestamp":"2026-11-05T05:56:46.000Z"}"#
}

final class ClaudeTranscriptActivityTests: XCTestCase {
    private func reading(_ lines: String...) -> AgentLogReading? {
        ClaudeTranscriptActivity.reading(lines: lines.map { Substring($0) })
    }

    func testTurnStatesFromTheNewestMeaningfulLine() {
        XCTAssertEqual(reading(Line.prompt)?.activity, .working)
        XCTAssertEqual(reading(Line.prompt, Line.toolUse)?.activity, .working)
        XCTAssertEqual(reading(Line.toolUse, Line.toolResult)?.activity, .working)
        XCTAssertEqual(reading(Line.toolResult, Line.assistant(stop: "end_turn"))?.activity, .done(message: nil))
        XCTAssertEqual(reading(Line.prompt, Line.ask)?.activity, .waiting(message: nil))
        XCTAssertEqual(reading(Line.ask, Line.toolResult)?.activity, .working, "answered: back to work")
    }

    /// Esc leaves no `Stop` hook, so this is the only way the pet learns a turn was cut short.
    func testAnInterruptIsIdle() {
        XCTAssertEqual(reading(Line.toolUse, Line.interrupted)?.activity, .idle)
        XCTAssertEqual(reading(Line.toolUse, Line.interruptedForTool)?.activity, .idle)
    }

    func testBookkeepingLinesAreSkipped() {
        let done = Line.assistant(stop: "end_turn")
        XCTAssertEqual(reading(done, Line.lastPrompt, Line.attachment)?.activity, .done(message: nil))
        XCTAssertEqual(reading(done, Line.meta)?.activity, .done(message: nil))
        XCTAssertEqual(reading(done, Line.localCommand, Line.localStdout)?.activity, .done(message: nil),
                       "a local slash command starts no turn, so it must not start working")
        XCTAssertNil(reading(Line.lastPrompt, Line.attachment))
        XCTAssertNil(reading("not json", ""))
    }

    func testSidechainAndApiErrorLines() {
        let sidechainDone = Line.assistant(stop: "end_turn").replacingOccurrences(of: #""isSidechain":false"#,
                                                                                  with: #""isSidechain":true"#)
        XCTAssertEqual(reading(Line.toolUse, sidechainDone)?.activity, .working, "a subagent finishing is not the turn ending")
        let apiError = Line.assistant(stop: "stop_sequence", extra: #","isApiErrorMessage":true"#)
        XCTAssertEqual(reading(Line.toolUse, apiError)?.activity, .idle)
    }

    func testLabelIsTheWorkingFolderAndDoneCarriesItsLine() throws {
        let done = Line.assistant(stop: "end_turn", uuid: "line-42", cwd: "/Users/me/code/my app")
        let result = try XCTUnwrap(reading(done))
        XCTAssertEqual(result.label, "my app")
        XCTAssertEqual(result.lineID, "line-42")
    }

    /// A tool result can quote another transcript; the escaped copy must not count as a line type.
    func testNestedTranscriptTextDoesNotMatch() {
        let quoted = Line.user(content: #"[{"type":"tool_result","tool_use_id":"t","content":"{\"type\":\"assistant\",\"message\":{\"stop_reason\":\"end_turn\"}}"}]"#)
        XCTAssertEqual(reading(Line.toolUse, quoted)?.activity, .working)
    }

    func testClaudeSourceSkipsSubagentFiles() {
        let source = AgentLogSource.claudeCode(hooks: nil)
        XCTAssertTrue(source.accepts(URL(fileURLWithPath: "/h/.claude/projects/-a/1234.jsonl")))
        XCTAssertFalse(source.accepts(URL(fileURLWithPath: "/h/.claude/projects/-a/1234/subagents/agent-1.jsonl")))
        XCTAssertFalse(source.accepts(URL(fileURLWithPath: "/h/.claude/projects/-a/notes.txt")))
    }
}

final class AgentLogEmitterTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func r(_ activity: AgentActivity, _ label: String? = "web", line: String? = nil) -> AgentLogReading {
        AgentLogReading(activity: activity, label: label, lineID: line)
    }

    func testWorkingIsSentOnChangeAndThenOncePerMinute() {
        var e = AgentLogEmitter()
        XCTAssertTrue(e.shouldEmit(r(.working), sourceID: "c", hooksReport: false, now: t0))
        XCTAssertFalse(e.shouldEmit(r(.working), sourceID: "c", hooksReport: false, now: t0 + 1))
        XCTAssertFalse(e.shouldEmit(r(.working), sourceID: "c", hooksReport: false, now: t0 + 59),
                       "a steady stream of lines must not push the refresh back")
        XCTAssertTrue(e.shouldEmit(r(.working), sourceID: "c", hooksReport: false, now: t0 + 60),
                      "keeps the pet's 10-minute working timeout from firing mid-task")
        XCTAssertFalse(e.shouldEmit(r(.working), sourceID: "c", hooksReport: false, now: t0 + 61))
    }

    func testTwoTurnsEndingInOneBatchAreTwoDones() {
        var e = AgentLogEmitter()
        XCTAssertTrue(e.shouldEmit(r(.done(message: nil), line: "a"), sourceID: "c", hooksReport: false, now: t0))
        XCTAssertFalse(e.shouldEmit(r(.done(message: nil), line: "a"), sourceID: "c", hooksReport: false, now: t0 + 1),
                       "the same line read again")
        XCTAssertTrue(e.shouldEmit(r(.done(message: nil), line: "b"), sourceID: "c", hooksReport: false, now: t0 + 2))
    }

    func testLabelsAndSourcesAreIndependent() {
        var e = AgentLogEmitter()
        XCTAssertTrue(e.shouldEmit(r(.working, "web"), sourceID: "c", hooksReport: false, now: t0))
        XCTAssertTrue(e.shouldEmit(r(.working, "api"), sourceID: "c", hooksReport: false, now: t0))
        XCTAssertTrue(e.shouldEmit(r(.working, "web"), sourceID: "other", hooksReport: false, now: t0))
    }

    func testIdleIsSentOnlyAfterSomethingElse() {
        var e = AgentLogEmitter()
        XCTAssertFalse(e.shouldEmit(r(.idle), sourceID: "c", hooksReport: false, now: t0), "nothing to clear")
        XCTAssertTrue(e.shouldEmit(r(.working), sourceID: "c", hooksReport: false, now: t0))
        XCTAssertTrue(e.shouldEmit(r(.idle), sourceID: "c", hooksReport: false, now: t0 + 1))
        XCTAssertFalse(e.shouldEmit(r(.idle), sourceID: "c", hooksReport: false, now: t0 + 2))
    }

    /// With hooks, the hooks speak; the log only adds the Esc interrupt they cannot see.
    func testWithHooksOnlyTheInterruptPasses() {
        var e = AgentLogEmitter()
        XCTAssertFalse(e.shouldEmit(r(.working), sourceID: "c", hooksReport: true, now: t0))
        XCTAssertFalse(e.shouldEmit(r(.done(message: nil), line: "a"), sourceID: "c", hooksReport: true, now: t0))
        XCTAssertFalse(e.shouldEmit(r(.waiting(message: nil), line: "b"), sourceID: "c", hooksReport: true, now: t0))
        XCTAssertTrue(e.shouldEmit(r(.idle), sourceID: "c", hooksReport: true, now: t0 + 1))
        XCTAssertFalse(e.shouldEmit(r(.idle), sourceID: "c", hooksReport: true, now: t0 + 2))
        var fresh = AgentLogEmitter()
        XCTAssertTrue(fresh.shouldEmit(r(.idle), sourceID: "c", hooksReport: true, now: t0),
                      "the first thing read can be the interrupt itself")
    }

    func testMemoryIsBounded() {
        var e = AgentLogEmitter()
        for i in 0..<(AgentLogEmitter.maxTracked * 3) {
            _ = e.shouldEmit(r(.working, "label-\(i)"), sourceID: "c", hooksReport: false, now: t0)
        }
        XCTAssertTrue(e.shouldEmit(r(.working, "label-0"), sourceID: "c", hooksReport: false, now: t0),
                      "old labels were forgotten, not kept forever")
    }
}

final class AgentLogTailTests: XCTestCase {
    func testRanges() {
        XCTAssertNil(AgentLogTail.range(size: 100, knownOffset: 100), "nothing new")
        XCTAssertEqual(AgentLogTail.range(size: 150, knownOffset: 100)?.start, 100)
        XCTAssertEqual(AgentLogTail.range(size: 150, knownOffset: 100)?.dropsFirstLine, false)
        // First sight: the tail only.
        XCTAssertEqual(AgentLogTail.range(size: 100, knownOffset: nil)?.start, 0)
        XCTAssertEqual(AgentLogTail.range(size: 100, knownOffset: nil)?.dropsFirstLine, false)
        let big: UInt64 = 10 * 1024 * 1024
        XCTAssertEqual(AgentLogTail.range(size: big, knownOffset: nil)?.start, big - AgentLogTail.tailBytes)
        XCTAssertEqual(AgentLogTail.range(size: big, knownOffset: nil)?.dropsFirstLine, true)
        // Rewritten shorter, or jumped far ahead: tail again.
        XCTAssertEqual(AgentLogTail.range(size: 50, knownOffset: 100)?.start, 0)
        XCTAssertEqual(AgentLogTail.range(size: big, knownOffset: 10)?.start, big - AgentLogTail.tailBytes)
    }

    func testOnlyCompleteLinesAreConsumed() {
        let (lines, consumed) = AgentLogTail.completeLines(Data("a\nb\npartial".utf8), dropsFirstLine: false)
        XCTAssertEqual(lines, ["a", "b"])
        XCTAssertEqual(consumed, 4, "the half-written line is read next time")
        XCTAssertEqual(AgentLogTail.completeLines(Data("no newline yet".utf8), dropsFirstLine: false).consumed, 0)
        XCTAssertEqual(AgentLogTail.completeLines(Data("cut\nwhole\n".utf8), dropsFirstLine: true).lines, ["whole"])
        XCTAssertEqual(AgentLogTail.completeLines(Data("\nwhole\n".utf8), dropsFirstLine: true).lines, ["whole"],
                       "starting right after a newline, nothing is cut")
    }
}

/// The real FSEvents path, on a temporary folder.
final class AgentLogWatcherTests: XCTestCase {
    private final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [AgentActivity] = []
        func append(_ a: AgentActivity) { lock.lock(); items.append(a); lock.unlock() }
        var all: [AgentActivity] { lock.lock(); defer { lock.unlock() }; return items }
    }

    func testAppendedLinesReachTheHandler() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AgentLogWatcherTests-\(UUID().uuidString)", isDirectory: true)
        let project = root.appendingPathComponent("-Users-me-web", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = AgentLogSource(id: "test", roots: { [root] }, accepts: { $0.pathExtension == "jsonl" },
                                    interpret: ClaudeTranscriptActivity.reading(lines:), hooks: nil)
        let received = Box()
        let done = expectation(description: "done read from the log")
        let watcher = AgentLogWatcher(sources: [source]) { reading, _, _ in
            received.append(reading.activity)
            if case .done = reading.activity { done.fulfill() }
        }
        watcher.start()
        defer { watcher.stop() }
        Thread.sleep(forTimeInterval: 0.5)   // let the stream start before writing

        let file = project.appendingPathComponent("session.jsonl")
        try Data((Line.prompt + "\n").utf8).write(to: file)
        Thread.sleep(forTimeInterval: 0.6)
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((Line.toolUse + "\n" + Line.assistant(stop: "end_turn") + "\n").utf8))
        try handle.close()

        wait(for: [done], timeout: 5)
        XCTAssertEqual(received.all.first, .working)
        XCTAssertEqual(received.all.last, .done(message: nil))
    }
}
