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
    static func aiTitle(_ title: String) -> String {
        #"{"type":"ai-title","aiTitle":""# + title + #"","sessionId":"s"}"#
    }
    static func customTitle(_ title: String) -> String {
        #"{"type":"custom-title","customTitle":""# + title + #"","sessionId":"s"}"#
    }
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

    private func title(_ lines: String...) -> AgentSessionTitle {
        ClaudeTranscriptActivity.title(lines: lines.map { Substring($0) })
    }

    func testTitlesComeFromTitleLines() {
        XCTAssertEqual(title(Line.prompt, Line.aiTitle("Fix login"), Line.toolUse, Line.aiTitle("Fix login bug")),
                       AgentSessionTitle(named: nil, generated: "Fix login bug"), "the newest generated title")
        XCTAssertEqual(title(Line.customTitle("auth"), Line.aiTitle("Fix login bug")).text, "auth",
                       "a name the person gave wins")
        XCTAssertEqual(title(Line.prompt, Line.lastPrompt), AgentSessionTitle(), "no title lines")
        XCTAssertEqual(title(Line.aiTitle("  ")), AgentSessionTitle(), "a blank title is no title")
        let quoted = Line.user(content: #"[{"type":"tool_result","tool_use_id":"t","content":"{\"type\":\"ai-title\",\"aiTitle\":\"x\"}"}]"#)
        XCTAssertEqual(title(quoted), AgentSessionTitle(), "an escaped copy inside a tool result is not a title")
    }

    private func info(_ memory: inout AgentSessionMemory, _ file: String, _ title: AgentSessionTitle = AgentSessionTitle(),
                      _ lines: String...) -> AgentSessionInfo {
        memory.update(file: file, title: title) {
            ClaudeTranscriptActivity.turns(lines: lines.map { Substring($0) }, from: $0)
        }
    }

    func testTitlesAreRememberedPerFileAndLabel() {
        var memory = AgentSessionMemory()
        XCTAssertEqual(info(&memory, "/a.jsonl", AgentSessionTitle(named: nil, generated: "Fix login bug")).title,
                       "Fix login bug")
        XCTAssertEqual(info(&memory, "/a.jsonl").title, "Fix login bug", "a later batch without title lines keeps the title")
        XCTAssertEqual(info(&memory, "/a.jsonl", AgentSessionTitle(named: "auth", generated: nil)).title, "auth")
        XCTAssertNil(info(&memory, "/b.jsonl").title)

        memory.noteActivity(label: "web", file: "/a.jsonl")
        XCTAssertEqual(memory.latest(label: "web")?.title, "auth")
        memory.noteActivity(label: "web", file: "/b.jsonl")
        XCTAssertEqual(memory.latest(label: "web"), AgentSessionInfo(title: nil, automaticTurn: false),
                       "another session in the folder moved; it has no title")
        XCTAssertNil(memory.latest(label: nil))
        XCTAssertNil(memory.latest(label: "api"))
    }

    /// Claude Code writes the title a moment after the prompt, often in a batch with no turn line.
    func testATitleWrittenAfterThePromptStillAnswersForTheFolder() {
        var memory = AgentSessionMemory()
        _ = info(&memory, "/c.jsonl", AgentSessionTitle(), Line.prompt)
        memory.noteActivity(label: "web", file: "/c.jsonl")
        XCTAssertNil(memory.latest(label: "web")?.title)
        _ = info(&memory, "/c.jsonl", AgentSessionTitle(named: nil, generated: "Fix login bug"))
        XCTAssertEqual(memory.latest(label: "web")?.title, "Fix login bug")
    }

    private func turns(_ lines: String..., from start: AgentTurnState = AgentTurnState()) -> AgentTurnState {
        ClaudeTranscriptActivity.turns(lines: lines.map { Substring($0) }, from: start)
    }

    /// Another session's message starts a turn as an `isMeta` user line; the person did not ask for it.
    func testTurnsStartedByAnotherSessionAreAutomatic() {
        let done = Line.assistant(stop: "end_turn")
        let fromSession = Line.user(content: #""Another Claude session sent a message""#, extra: #","isMeta":true"#)
        XCTAssertEqual(turns(done, fromSession, Line.toolUse), AgentTurnState(open: true, automatic: true))
        XCTAssertEqual(turns(done, fromSession, Line.toolUse, done), AgentTurnState(open: false, automatic: true))
        XCTAssertEqual(turns(done, fromSession, done, Line.prompt), AgentTurnState(open: true, automatic: false),
                       "the person's next prompt starts a turn of their own")
        XCTAssertEqual(turns(Line.toolUse, Line.interrupted, fromSession), AgentTurnState(open: true, automatic: true),
                       "an interrupt ends a turn too")
    }

    func testMetaLinesInsideATurnAreNotStarts() {
        let done = Line.assistant(stop: "end_turn")
        let image = Line.user(content: #"[{"type":"text","text":"[Image: source]"}]"#, extra: #","isMeta":true"#)
        XCTAssertEqual(turns(done, Line.prompt, Line.toolUse, image, Line.toolResult),
                       AgentTurnState(open: true, automatic: false), "an attached image is part of the person's turn")
        XCTAssertEqual(turns(Line.toolUse, image), AgentTurnState(), "first sight: the tail starts mid-turn")
        let sidechainDone = done.replacingOccurrences(of: #""isSidechain":false"#, with: #""isSidechain":true"#)
        XCTAssertEqual(turns(Line.prompt, sidechainDone), AgentTurnState(), "a subagent finishing does not end the turn")
        XCTAssertEqual(turns(done, Line.localCommand, Line.localStdout), AgentTurnState(open: false, automatic: false),
                       "a local slash command starts no turn")
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
                                    interpret: ClaudeTranscriptActivity.reading(lines:), hooks: nil,
                                    title: ClaudeTranscriptActivity.title(lines:),
                                    turns: ClaudeTranscriptActivity.turns(lines:from:))
        let received = Box()
        let done = expectation(description: "done read from the log")
        let quiet = expectation(description: "a turn another session started ends without a done")
        let watcher = AgentLogWatcher(sources: [source]) { reading, _, _ in
            received.append(reading.activity)
            if case .done = reading.activity {
                XCTAssertEqual(reading.title, "Fix login bug", "the title from the first write is remembered")
                done.fulfill()
            }
            if reading.activity == .idle { quiet.fulfill() }
        }
        watcher.start()
        defer { watcher.stop() }
        Thread.sleep(forTimeInterval: 0.5)   // let the stream start before writing

        let file = project.appendingPathComponent("session.jsonl")
        try Data((Line.prompt + "\n" + Line.aiTitle("Fix login bug") + "\n").utf8).write(to: file)
        Thread.sleep(forTimeInterval: 0.6)
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((Line.toolUse + "\n" + Line.assistant(stop: "end_turn") + "\n").utf8))
        try handle.close()

        wait(for: [done], timeout: 5)
        XCTAssertEqual(received.all.first, .working)
        XCTAssertEqual(received.all.last, .done(message: nil))
        XCTAssertEqual(watcher.latestSession(label: "web-app")?.title, "Fix login bug", "hook events look the title up by folder")

        let fromSession = Line.user(content: #""Another Claude session sent a message""#, extra: #","isMeta":true"#)
        let more = try FileHandle(forWritingTo: file)
        try more.seekToEnd()
        try more.write(contentsOf: Data((fromSession + "\n" + Line.toolUse + "\n").utf8))
        Thread.sleep(forTimeInterval: 0.6)
        try more.write(contentsOf: Data((Line.assistant(stop: "end_turn") + "\n").utf8))
        try more.close()
        wait(for: [quiet], timeout: 5)
        XCTAssertEqual(received.all.last, .idle)
        XCTAssertEqual(received.all.filter { if case .done = $0 { true } else { false } }.count, 1,
                       "only the person's turn ended with a done (FSEvents may merge the last two writes)")
        XCTAssertEqual(watcher.latestSession(label: "web-app")?.automaticTurn, true)
    }
}

/// The watcher's extension points for agents other than Claude Code, on the real FSEvents path.
final class AgentLogWatcherSourceShapeTests: XCTestCase {
    private final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [AgentLogReading] = []
        func append(_ r: AgentLogReading) { lock.lock(); items.append(r); lock.unlock() }
        var all: [AgentLogReading] { lock.lock(); defer { lock.unlock() }; return items }
    }

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AgentLogWatcherSourceShapeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// A toy line format: `state` lines (`working`, `done`) and a `head:<label>` or `head:skip` first line.
    private func lineSource(externalTitle: (@Sendable (URL) -> AgentSessionTitle)? = nil) -> AgentLogSource {
        let root = root!
        return AgentLogSource(
            id: "toy", roots: { [root] }, accepts: { $0.pathExtension == "log" },
            interpret: { lines in
                guard let last = lines.last(where: { !$0.hasPrefix("head:") }) else { return nil }
                return AgentLogReading(activity: last == "done" ? .done(message: nil) : .working, label: nil,
                                       lineID: UUID().uuidString)
            },
            hooks: nil,
            head: { lines in
                let first = lines.first.map(String.init) ?? ""
                return first == "head:skip" ? AgentLogHead(skip: true)
                    : AgentLogHead(label: first.replacingOccurrences(of: "head:", with: ""))
            },
            externalTitle: externalTitle)
    }

    private func append(_ text: String, to file: URL) throws {
        if !FileManager.default.fileExists(atPath: file.path) { try Data().write(to: file) }
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
        try handle.close()
    }

    func testHeadGivesTheLabelAndSkipsHelperLogs() throws {
        let received = Box()
        let done = expectation(description: "done from the main log")
        let watcher = AgentLogWatcher(sources: [lineSource(externalTitle: { _ in
            AgentSessionTitle(named: nil, generated: "From the index")
        })]) { reading, _, _ in
            received.append(reading)
            if case .done = reading.activity { done.fulfill() }
        }
        watcher.start()
        defer { watcher.stop() }
        Thread.sleep(forTimeInterval: 0.5)

        // A long tail pushes the head line out of the 64 KB read; the head read still finds it.
        let main = root.appendingPathComponent("main.log")
        try append("head:web-app\n" + String(repeating: "working\n", count: 20_000), to: main)
        try append("head:skip\nworking\ndone\n", to: root.appendingPathComponent("helper.log"))
        Thread.sleep(forTimeInterval: 0.6)
        try append("done\n", to: main)

        wait(for: [done], timeout: 5)
        let last = try XCTUnwrap(received.all.last)
        XCTAssertEqual(last.label, "web-app")
        XCTAssertEqual(last.title, "From the index", "an external title fills a done")
        XCTAssertEqual(received.all.filter { if case .done = $0.activity { true } else { false } }.count, 1,
                       "the helper's done never arrives")
    }

    /// Written aside and renamed over the old file: the new file is read from its tail, not from the
    /// old offset (which would start mid-line).
    func testAReplacedFileIsReadAsNew() throws {
        let received = Box()
        let done = expectation(description: "done after the file was replaced")
        let watcher = AgentLogWatcher(sources: [lineSource()]) { reading, _, _ in
            received.append(reading)
            if case .done = reading.activity { done.fulfill() }
        }
        watcher.start()
        defer { watcher.stop() }
        Thread.sleep(forTimeInterval: 0.5)

        let file = root.appendingPathComponent("s.log")
        try append("head:a\n" + String(repeating: "working\n", count: 50), to: file)
        Thread.sleep(forTimeInterval: 0.6)
        let aside = root.appendingPathComponent("s.tmp")
        try Data(("head:a\n" + String(repeating: "x", count: 900) + "\ndone\n").utf8).write(to: aside)
        _ = try FileManager.default.replaceItemAt(file, withItemAt: aside)
        wait(for: [done], timeout: 5)
    }

    func testDatabaseSourcesAreQueriedOncePerBatchAndNeverForShm() throws {
        final class Calls: @unchecked Sendable {
            private let lock = NSLock()
            private var marks: [String?] = []
            func add(_ m: String?) { lock.lock(); marks.append(m); lock.unlock() }
            var all: [String?] { lock.lock(); defer { lock.unlock() }; return marks }
        }
        let calls = Calls()
        let root = root!
        let reader = AgentDatabaseReader(
            database: { url in
                url.lastPathComponent.hasSuffix("-shm") ? nil
                    : URL(fileURLWithPath: url.path.replacingOccurrences(of: "-wal", with: ""))
            },
            read: { _, watermark in
                calls.add(watermark)
                let next = String((Int(watermark ?? "0") ?? 0) + 1)
                return ([AgentLogReading(activity: .done(message: nil), label: "api", lineID: next,
                                         title: "Add rate limits", session: "s1")], next)
            })
        let source = AgentLogSource(id: "db", roots: { [root] }, accepts: { $0.lastPathComponent.hasPrefix("state.db") },
                                    interpret: { _ in nil }, hooks: nil, database: reader)
        let received = Box()
        let first = expectation(description: "first query")
        let watcher = AgentLogWatcher(sources: [source]) { reading, _, _ in
            received.append(reading)
            first.fulfill()
        }
        watcher.start()
        defer { watcher.stop() }
        Thread.sleep(forTimeInterval: 0.5)

        try Data("db".utf8).write(to: root.appendingPathComponent("state.db"))
        try Data("wal".utf8).write(to: root.appendingPathComponent("state.db-wal"))
        wait(for: [first], timeout: 5)
        try Data("shm".utf8).write(to: root.appendingPathComponent("state.db-shm"))
        Thread.sleep(forTimeInterval: 0.8)

        XCTAssertEqual(calls.all.first ?? "unset", nil, "the first look has no watermark")
        XCTAssertLessThanOrEqual(calls.all.count, 2, "db and -wal in one batch share a query; -shm adds none")
        XCTAssertEqual(received.all.first?.title, "Add rate limits")
        XCTAssertEqual(watcher.latestSession(label: "api")?.title, "Add rate limits", "hook events find database sessions too")
    }
}
