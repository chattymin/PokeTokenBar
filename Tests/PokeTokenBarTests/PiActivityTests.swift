import XCTest
@testable import PokeTokenBar

/// Session lines shaped like Pi Agent, omp and senpi write them (compact `JSON.stringify`, one
/// entry per line). Keys checked against upstream source (2026-11-06): earendil-works/pi @2a32a60
/// `packages/coding-agent/src/core/session-manager.ts`, `packages/ai/src/types.ts`;
/// can1357/oh-my-pi @660a31d `src/session/session-entries.ts`, `session-title-slot.ts`;
/// code-yeongyu/senpi @f4dc3ac `src/core/session-manager.ts`. Content is made up.
private enum PiLine {
    static func header(cwd: String = "/Users/me/code/web-app", extra: String = "") -> String {
        #"{"type":"session","version":3,"id":"019a1b2c-3d4e-7f80-9a1b-2c3d4e5f6a7b","timestamp":"2026-11-05T05:56:40.000Z","cwd":""#
            + cwd + #"""# + extra + "}"
    }

    /// omp's line 1: exactly 256 bytes with its newline.
    static func titleSlot(_ title: String, source: String? = "auto") -> String {
        let source = source.map { #","source":""# + $0 + #"""# } ?? ""
        let start = #"{"type":"title","v":1,"title":""# + title + #"""# + source + #","updatedAt":"2026-11-05T05:56:41.000Z","pad":""#
        let line = start + String(repeating: " ", count: 255 - start.utf8.count - 2) + #""}"#
        precondition(line.utf8.count + 1 == 256)
        return line
    }

    /// omp header: the title fields sit before `timestamp` once a title exists.
    static func ompHeader(cwd: String = "/Users/me/code/api", title: String? = nil) -> String {
        let title = title.map { #""title":""# + $0 + #"","titleSource":"auto","# } ?? ""
        return #"{"type":"session","version":3,"id":"7f3a9c1e2b4d","# + title
            + #""timestamp":"2026-11-05T05:56:40.000Z","cwd":""# + cwd + #""}"#
    }

    private static func entry(_ id: String, _ message: String) -> String {
        #"{"type":"message","id":""# + id + #"","parentId":"a0a0a0a0","timestamp":"2026-11-05T05:56:45.000Z","message":"#
            + message + "}"
    }

    static func user(_ text: String = "Fix the login bug", id: String = "b1b1b1b1") -> String {
        entry(id, #"{"role":"user","content":[{"type":"text","text":""# + text + #""}],"timestamp":1762322205000}"#)
    }

    static func call(_ name: String, id: String) -> String {
        #"{"type":"toolCall","id":""# + id + #"","name":""# + name + #"","arguments":{}}"#
    }

    static func assistant(stop: String, content: [String] = [#"{"type":"text","text":"Done."}"#],
                          id: String = "c1c1c1c1", extra: String = "") -> String {
        entry(id, #"{"role":"assistant","content":["# + content.joined(separator: ",")
            + #"],"api":"anthropic-messages","provider":"anthropic","model":"claude-opus-5-5","usage":{"input":3,"output":9,"cacheRead":0,"cacheWrite":0,"totalTokens":12,"cost":{"input":0,"output":0,"cacheRead":0,"cacheWrite":0,"total":0}},"stopReason":""#
            + stop + #"""# + extra + #","timestamp":1762322206000}"#)
    }

    static func toolResult(callID: String, name: String = "bash", id: String = "d1d1d1d1", text: String = "ok") -> String {
        entry(id, #"{"role":"toolResult","toolCallId":""# + callID + #"","toolName":""# + name
            + #"","content":[{"type":"text","text":""# + text + #""}],"isError":false,"timestamp":1762322207000}"#)
    }

    static let bash = assistant(stop: "toolUse", content: [call("bash", id: "toolu_1")], id: "c2c2c2c2")
    static let bashResult = toolResult(callID: "toolu_1", id: "d2d2d2d2")
    static let bashExecution = entry("e1e1e1e1", #"{"role":"bashExecution","command":"ls","output":"a","exitCode":0,"cancelled":false,"truncated":false,"timestamp":1762322208000}"#)
    static let modelChange = #"{"type":"model_change","id":"f1f1f1f1","parentId":"a0a0a0a0","timestamp":"2026-11-05T05:56:44.000Z","provider":"anthropic","modelId":"claude-opus-5-5"}"#
    static let compaction = #"{"type":"compaction","id":"f2f2f2f2","parentId":"a0a0a0a0","timestamp":"2026-11-05T05:56:44.000Z","summary":"…","firstKeptEntryId":"b1b1b1b1","tokensBefore":120000}"#
    static let customMessage = #"{"type":"custom_message","id":"f3f3f3f3","parentId":"a0a0a0a0","timestamp":"2026-11-05T05:56:44.000Z","customType":"note","content":"hi","display":true}"#

    static func sessionInfo(_ name: String) -> String {
        #"{"type":"session_info","id":"a9a9a9a9","parentId":"c1c1c1c1","timestamp":"2026-11-05T05:56:50.000Z","name":""# + name + #""}"#
    }

    static func titleChange(_ title: String, source: String) -> String {
        #"{"type":"title_change","id":"a8a8a8a8","parentId":"c1c1c1c1","timestamp":"2026-11-05T05:56:50.000Z","title":""#
            + title + #"","source":""# + source + #""}"#
    }
}

final class PiActivityTests: XCTestCase {
    private func reading(_ fork: PiSessionActivity.Fork = .pi, _ lines: String...) -> AgentLogReading? {
        PiSessionActivity.reading(lines: lines.map { Substring($0) }, fork: fork)
    }

    func testTurnStatesFromTheNewestMeaningfulLine() {
        XCTAssertEqual(reading(.pi, PiLine.user())?.activity, .working)
        XCTAssertEqual(reading(.pi, PiLine.user(), PiLine.bash)?.activity, .working)
        XCTAssertEqual(reading(.pi, PiLine.bash, PiLine.bashResult)?.activity, .working)
        XCTAssertEqual(reading(.pi, PiLine.bashResult, PiLine.assistant(stop: "stop"))?.activity, .done(message: nil))
        XCTAssertEqual(reading(.pi, PiLine.assistant(stop: "length"))?.activity, .done(message: nil),
                       "cut off by the output limit with no tool call: the loop ends")
        XCTAssertEqual(reading(.pi, PiLine.assistant(stop: "length", content: [PiLine.call("bash", id: "t")]))?.activity,
                       .working, "cut-off tool calls get failed results and the loop goes on")
        XCTAssertEqual(reading(.pi, PiLine.assistant(stop: "pending"))?.activity, .working)
    }

    /// Esc writes the assistant message with `aborted`; a failed request with `error`.
    func testAbortAndErrorAreIdle() {
        XCTAssertEqual(reading(.pi, PiLine.bash, PiLine.assistant(stop: "aborted"))?.activity, .idle)
        XCTAssertEqual(reading(.pi, PiLine.user(), PiLine.assistant(stop: "error", extra: #","errorMessage":"overloaded""#))?.activity,
                       .idle)
        XCTAssertEqual(reading(.pi, PiLine.assistant(stop: "error"), PiLine.assistant(stop: "toolUse",
                                                                                       content: [PiLine.call("read", id: "t")]))?.activity,
                       .working, "an automatic retry reads as working again")
    }

    func testBookkeepingLinesAreSkipped() {
        let done = PiLine.assistant(stop: "stop")
        XCTAssertEqual(reading(.pi, done, PiLine.bashExecution, PiLine.modelChange, PiLine.compaction,
                               PiLine.customMessage, PiLine.sessionInfo("auth"))?.activity, .done(message: nil),
                       "a `!` command after the turn starts no turn")
        XCTAssertNil(reading(.pi, PiLine.header(), PiLine.modelChange))
        XCTAssertNil(reading(.pi, "not json", ""))
    }

    func testDoneCarriesItsEntryAndNoLabel() throws {
        let result = try XCTUnwrap(reading(.pi, PiLine.assistant(stop: "stop", id: "5e5e5e5e")))
        XCTAssertEqual(result.lineID, "5e5e5e5e")
        XCTAssertNil(result.label, "only the header has the folder; the watcher fills it from `head`")
    }

    /// A tool result can quote another session's lines; the escaped copy must not count.
    func testNestedSessionTextDoesNotMatch() {
        let quoted = PiLine.toolResult(callID: "toolu_1",
                                       text: #"{\"type\":\"message\",\"message\":{\"role\":\"assistant\",\"stopReason\":\"stop\"}}"#)
        XCTAssertEqual(reading(.pi, PiLine.bash, quoted)?.activity, .working)
    }

    func testAskToolsPerFork() {
        let ompAsk = PiLine.assistant(stop: "toolUse", content: [PiLine.call("ask", id: "q1")], id: "c3c3c3c3")
        XCTAssertEqual(reading(.omp, PiLine.user(), ompAsk)?.activity, .waiting(message: nil))
        XCTAssertEqual(reading(.omp, ompAsk)?.lineID, "c3c3c3c3")
        XCTAssertEqual(reading(.omp, ompAsk, PiLine.toolResult(callID: "q1", name: "ask"))?.activity, .working,
                       "answered: back to work")
        XCTAssertEqual(reading(.pi, ompAsk)?.activity, .working, "Pi has no ask tool; an extension's `ask` is any tool")

        for name in ["ask_user_question", "request_user_input"] {
            let senpiAsk = PiLine.assistant(stop: "toolUse", content: [PiLine.call(name, id: "q2")])
            XCTAssertEqual(reading(.omo, senpiAsk)?.activity, .waiting(message: nil), name)
            XCTAssertEqual(reading(.omp, senpiAsk)?.activity, .working, "\(name) is not an omp tool")
        }
        let cutOff = PiLine.assistant(stop: "length", content: [PiLine.call("ask", id: "q1")])
        XCTAssertEqual(reading(.omp, cutOff)?.activity, .working, "a cut-off call is failed, not shown")
    }

    /// Results are written in call order: the calls before an ask finish while it still waits.
    func testAResultBeforeAnUnansweredAskStillWaits() {
        let both = PiLine.assistant(stop: "toolUse", content: [PiLine.call("bash", id: "b1"), PiLine.call("ask", id: "q1")],
                                    id: "c4c4c4c4")
        let waiting = reading(.omp, both, PiLine.toolResult(callID: "b1"))
        XCTAssertEqual(waiting?.activity, .waiting(message: nil))
        XCTAssertEqual(waiting?.lineID, "c4c4c4c4", "the same question as before, not a new one")
        XCTAssertEqual(reading(.omp, both, PiLine.toolResult(callID: "b1"), PiLine.toolResult(callID: "q1", name: "ask", id: "d9d9d9d9"))?
                           .lineID, "d9d9d9d9")
        XCTAssertEqual(reading(.omp, both, PiLine.toolResult(callID: "b1"), PiLine.toolResult(callID: "q1", name: "ask"))?.activity,
                       .working)
    }

    private func title(_ lines: String...) -> AgentSessionTitle {
        PiSessionActivity.title(lines: lines.map { Substring($0) })
    }

    func testTitlesFromAppendedLines() {
        XCTAssertEqual(title(PiLine.sessionInfo("first"), PiLine.user(), PiLine.sessionInfo("auth fix")),
                       AgentSessionTitle(named: "auth fix", generated: nil), "Pi/senpi: the newest name")
        XCTAssertEqual(title(PiLine.titleChange("Fix login", source: "auto"), PiLine.titleChange("Fix login bug", source: "auto")),
                       AgentSessionTitle(named: nil, generated: "Fix login bug"))
        XCTAssertEqual(title(PiLine.titleChange("auth", source: "user"), PiLine.titleChange("Fix login bug", source: "auto")).text,
                       "auth", "omp: a name the person gave wins")
        XCTAssertEqual(title(PiLine.sessionInfo("  ")), AgentSessionTitle(), "a blank name is no title")
        XCTAssertEqual(title(PiLine.user(), PiLine.assistant(stop: "stop")), AgentSessionTitle())
        let quoted = PiLine.toolResult(callID: "t", text: #"{\"type\":\"session_info\",\"name\":\"x\"}"#)
        XCTAssertEqual(title(quoted), AgentSessionTitle(), "an escaped copy inside a tool result is not a title")
    }

    private func head(_ lines: String...) -> AgentLogHead {
        PiSessionActivity.head(lines: lines.map { Substring($0) })
    }

    func testHeadLabelFromTheHeaderOnLineOneOrTwo() {
        XCTAssertEqual(head(PiLine.header(cwd: "/Users/me/code/my app"), PiLine.modelChange, PiLine.user()),
                       AgentLogHead(label: "my app"), "Pi and senpi: line 1")
        let omp = head(PiLine.titleSlot("Fix login bug"), PiLine.ompHeader(cwd: "/Users/me/code/api"), PiLine.user())
        XCTAssertEqual(omp.label, "api", "omp: line 2, after the title slot")
        XCTAssertEqual(omp.title, AgentSessionTitle(named: nil, generated: "Fix login bug"))
        XCTAssertFalse(omp.skip)
        XCTAssertEqual(head(PiLine.user()), AgentLogHead(), "no header")
    }

    /// The slot is rewritten in place, so it is newer than the header (which changes only when
    /// the whole file is rewritten). An empty slot falls back to the header.
    func testOmpTitleSlot() {
        XCTAssertEqual(head(PiLine.titleSlot("auth", source: "user"), PiLine.ompHeader(title: "Fix login")).title,
                       AgentSessionTitle(named: "auth", generated: nil))
        XCTAssertEqual(head(PiLine.titleSlot("", source: nil), PiLine.ompHeader(title: "Fix login")).title,
                       AgentSessionTitle(named: nil, generated: "Fix login"))
        XCTAssertEqual(head(PiLine.titleSlot("", source: nil), PiLine.ompHeader()).title, AgentSessionTitle())
    }

    func testSenpiSpawnedSessionsAreSkipped() {
        let spawned = PiLine.header(extra: #","spawnedBy":{"parentSessionId":"p","rootSessionId":"r","taskId":"t"}"#)
        XCTAssertTrue(head(spawned).skip)
        XCTAssertFalse(head(PiLine.header(extra: #","parentSession":"/Users/me/.pi/agent/sessions/x.jsonl""#)).skip,
                       "a fork the person made is theirs")
    }

    func testAcceptsOnlyThePersonsSessions() {
        let pi = AgentLogSource.pi(), omp = AgentLogSource.omp(), omo = AgentLogSource.omo()
        let piFile = "/h/.pi/agent/sessions/--Users-me-web--/2026-11-05T05-56-40-000Z_019a1b2c-3d4e-7f80-9a1b-2c3d4e5f6a7b.jsonl"
        XCTAssertTrue(pi.accepts(URL(fileURLWithPath: piFile)))
        XCTAssertFalse(pi.accepts(URL(fileURLWithPath: "/h/.pi/agent/sessions/--Users-me-web--/notes.txt")))

        let session = "/h/.omp/agent/sessions/-Users-me-api/2026-11-05T05-56-40-000Z_7f3a9c1e2b4d"
        XCTAssertTrue(omp.accepts(URL(fileURLWithPath: session + ".jsonl")))
        XCTAssertFalse(omp.accepts(URL(fileURLWithPath: session + "/explore.jsonl")), "a subagent")
        XCTAssertFalse(omp.accepts(URL(fileURLWithPath: session + "/__advisor.jsonl")), "the advisor")
        XCTAssertFalse(omp.accepts(URL(fileURLWithPath: session + "/explore/review.jsonl")), "a nested subagent")
        XCTAssertFalse(omp.accepts(URL(fileURLWithPath: "/h/.omp/agent/sessions/bridge/2026-08-19T03-19-25.604_00000000.jsonl")),
                       "a pi-session-manager copy")

        XCTAssertTrue(omo.accepts(URL(fileURLWithPath: "/h/.senpi/agent/sessions/--Users-me-web--/2026-11-05T05-56-40-000Z_abc.jsonl")))
        XCTAssertFalse(omo.accepts(URL(fileURLWithPath: "/h/.omo/agent/sessions/--Users-me-web--/session-holders/abc/123.jsonl")))
        XCTAssertFalse(omo.accepts(URL(fileURLWithPath: "/h/.omo/agent/sessions/--Users-me-web--/session-holders/abc/123.json")))
    }

    func testSessionFileStems() {
        XCTAssertTrue(PiSessionActivity.isSessionFileStem("2026-11-05T05-56-40-000Z_7f3a9c1e"))
        XCTAssertTrue(PiSessionActivity.isSessionFileStem("2026-08-19T03-19-25.604_00000000"))
        XCTAssertFalse(PiSessionActivity.isSessionFileStem("--Users-me-2026-11-05T05-56-40-000Z_x--"))
        XCTAssertFalse(PiSessionActivity.isSessionFileStem("-Users-me-api"))
        XCTAssertFalse(PiSessionActivity.isSessionFileStem("2026_x"))
    }

    func testSourcesUseTheProviderIDsAndNoHooks() {
        XCTAssertEqual([AgentLogSource.pi(), .omp(), .omo()].map(\.id), ["pi", "omp", "omo"])
        XCTAssertTrue([AgentLogSource.pi(), .omp(), .omo()].allSatisfy { $0.hooks == nil && $0.head != nil })
    }

    private final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [AgentLogReading] = []
        func append(_ r: AgentLogReading) { lock.lock(); items.append(r); lock.unlock() }
        var all: [AgentLogReading] { lock.lock(); defer { lock.unlock() }; return items }
    }

    private func append(_ text: String, to file: URL) throws {
        if !FileManager.default.fileExists(atPath: file.path) { try Data().write(to: file) }
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
        try handle.close()
    }

    /// omp's layout on the real FSEvents path: the label and title come from lines 1–2, which a long
    /// session pushes out of the 64 KB tail, and a subagent's turn ending is not news.
    func testOmpSessionReadsHeadAndSkipsSubagents() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PiActivityWatcherTests-\(UUID().uuidString)", isDirectory: true)
        let bucket = root.appendingPathComponent("-Users-me-api", isDirectory: true)
        let stem = "2026-11-05T05-56-40-000Z_7f3a9c1e2b4d"
        try FileManager.default.createDirectory(at: bucket.appendingPathComponent(stem), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let omp = AgentLogSource.omp()
        let source = AgentLogSource(id: omp.id, roots: { [root] }, accepts: omp.accepts, interpret: omp.interpret,
                                    hooks: nil, title: omp.title, head: omp.head)
        let received = Box()
        let done = expectation(description: "done from the main session")
        let watcher = AgentLogWatcher(sources: [source]) { reading, _, _ in
            received.append(reading)
            if case .done = reading.activity { done.fulfill() }
        }
        watcher.start()
        defer { watcher.stop() }
        Thread.sleep(forTimeInterval: 0.5)

        let main = bucket.appendingPathComponent(stem + ".jsonl")
        let filler = PiLine.toolResult(callID: "toolu_1", text: String(repeating: "x", count: 2_000))
        try append([PiLine.titleSlot("Fix login bug"), PiLine.ompHeader(cwd: "/Users/me/code/api"), PiLine.user(), PiLine.bash]
                       .joined(separator: "\n") + "\n" + String(repeating: filler + "\n", count: 40), to: main)
        let subagent = bucket.appendingPathComponent(stem).appendingPathComponent("explore.jsonl")
        try append([PiLine.ompHeader(cwd: "/Users/me/code/api"), PiLine.user(), PiLine.assistant(stop: "stop")]
                       .joined(separator: "\n") + "\n", to: subagent)
        Thread.sleep(forTimeInterval: 0.6)
        try append(PiLine.assistant(stop: "stop", id: "c9c9c9c9") + "\n", to: main)

        wait(for: [done], timeout: 5)
        let last = try XCTUnwrap(received.all.last)
        XCTAssertEqual(last.label, "api")
        XCTAssertEqual(last.title, "Fix login bug")
        XCTAssertEqual(last.lineID, "c9c9c9c9")
        XCTAssertEqual(received.all.filter { if case .done = $0.activity { true } else { false } }.count, 1,
                       "the subagent's done never arrives")
    }
}
