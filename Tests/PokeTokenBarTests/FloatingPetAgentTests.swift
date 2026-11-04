import AppKit
import XCTest
@testable import PokeTokenBar

@MainActor
final class FloatingPetAgentTests: XCTestCase {
    private typealias C = FloatingPetController

    // MARK: Home persistence

    /// The run to the cursor must never become the saved home; a drag during it must.
    func testOnlyHomeOrADragPersistsTheOrigin() {
        XCTAssertTrue(C.resolveMove(phase: .home, userDragging: false) == (.home, true))
        XCTAssertTrue(C.resolveMove(phase: .home, userDragging: true) == (.home, true))
        XCTAssertTrue(C.resolveMove(phase: .away, userDragging: false) == (.away, false),
                      "animation frames of the run must not overwrite home")
        XCTAssertTrue(C.resolveMove(phase: .returning, userDragging: false) == (.returning, false),
                      "frames of the way back must not be saved either")
        XCTAssertTrue(C.resolveMove(phase: .away, userDragging: true) == (.home, true),
                      "a drag cancels the return and becomes the new home")
        XCTAssertTrue(C.resolveMove(phase: .returning, userDragging: true) == (.home, true))
    }

    // MARK: Run target

    private let screen = NSRect(x: 0, y: 25, width: 1440, height: 875)
    private let panel = NSSize(width: 180, height: 168)

    private func assertInside(_ origin: NSPoint, _ visible: NSRect, file: StaticString = #filePath, line: UInt = #line) {
        let rect = NSRect(origin: origin, size: panel)
        XCTAssertTrue(visible.contains(rect), "\(rect) leaves \(visible)", file: file, line: line)
    }

    func testRunLandsBelowRightOfTheCursor() {
        let cursor = NSPoint(x: 600, y: 500)
        let origin = C.runPanelOrigin(cursor: cursor, panelSize: panel, visibleFrame: screen, gap: 16)
        XCTAssertEqual(origin, NSPoint(x: 616, y: 500 - 16 - 168))
        XCTAssertFalse(NSRect(origin: origin, size: panel).contains(cursor))
    }

    func testRunFlipsAtScreenEdgesInsteadOfCoveringThePointer() {
        let corners = [
            NSPoint(x: 1430, y: 500),   // right edge
            NSPoint(x: 600, y: 40),     // bottom edge
            NSPoint(x: 1435, y: 30),    // bottom-right corner
            NSPoint(x: 5, y: 895),      // top-left corner
        ]
        for cursor in corners {
            let origin = C.runPanelOrigin(cursor: cursor, panelSize: panel, visibleFrame: screen, gap: 16)
            assertInside(origin, screen)
            XCTAssertFalse(NSRect(origin: origin, size: panel).contains(cursor), "covers the pointer at \(cursor)")
        }
        // Flipped, not just clamped: a clamp alone would park the pet right under the pointer's column.
        XCTAssertEqual(C.runPanelOrigin(cursor: NSPoint(x: 1430, y: 500), panelSize: panel, visibleFrame: screen, gap: 16),
                       NSPoint(x: 1430 - 16 - 180, y: 500 - 16 - 168))
        XCTAssertEqual(C.runPanelOrigin(cursor: NSPoint(x: 600, y: 40), panelSize: panel, visibleFrame: screen, gap: 16),
                       NSPoint(x: 616, y: 40 + 16))
    }

    func testRunStaysOnTheCursorScreen() {
        let secondary = NSRect(x: -1920, y: 0, width: 1920, height: 1080)
        let origin = C.runPanelOrigin(cursor: NSPoint(x: -10, y: 1075), panelSize: panel, visibleFrame: secondary)
        assertInside(origin, secondary)
    }

    func testOversizedPanelKeepsThePetVisible() {
        let small = NSRect(x: 0, y: 0, width: 300, height: 200)
        let huge = NSSize(width: 384, height: 456)
        let origin = C.runPanelOrigin(cursor: NSPoint(x: 150, y: 100), panelSize: huge, visibleFrame: small)
        XCTAssertEqual(origin, NSPoint(x: small.minX, y: small.minY), "bottom-left (the pet) wins the clamp")
    }

    // MARK: Motion gates

    /// Overlapping dones from several agents: one run, then only the bubble changes.
    func testASecondDoneDoesNotRunAgainWhileAway() {
        XCTAssertTrue(C.runsToCursor(phase: .home, motionAllowed: true, panelVisible: true))
        XCTAssertTrue(C.runsToCursor(phase: .returning, motionAllowed: true, panelVisible: true),
                      "a done on the way back turns the pet around")
        XCTAssertFalse(C.runsToCursor(phase: .away, motionAllowed: true, panelVisible: true))
        XCTAssertFalse(C.runsToCursor(phase: .home, motionAllowed: false, panelVisible: true), "Reduce Motion / Low Power")
        XCTAssertFalse(C.runsToCursor(phase: .home, motionAllowed: true, panelVisible: false))
    }

    func testMotionFollowsLowPowerAndReduceMotion() {
        XCTAssertTrue(C.allowsMotion(animated: true, reduceMotion: false))
        XCTAssertFalse(C.allowsMotion(animated: false, reduceMotion: false), "static host (low power)")
        XCTAssertFalse(C.allowsMotion(animated: true, reduceMotion: true), "Reduce Motion")
        XCTAssertTrue(C.shouldBob(working: true, motionAllowed: true))
        XCTAssertFalse(C.shouldBob(working: true, motionAllowed: false))
        XCTAssertFalse(C.shouldBob(working: false, motionAllowed: true), "nothing working must not loop")
        XCTAssertGreaterThan(C.agentBobInterval, 0, "the bob loop is an always-visible surface: it needs a cap")
    }

    // MARK: Bubbles

    func testLimitAlertOutranksAgentBubbles() {
        typealias Note = AgentActivitySummary.Note
        let alert = UsageStore.LimitAlert(key: "k", window: "Claude weekly", isCritical: true, utilization: 96)
        let waiting = AgentActivitySummary(waiting: Note(label: "a", message: "x"), otherWaitingCount: 2)
        let both = AgentActivitySummary(done: Note(label: "b", message: nil), waiting: Note(label: "a", message: "x"))
        XCTAssertEqual(C.bubble(limitAlert: alert, agent: waiting), .limit(alert))
        XCTAssertEqual(C.bubble(limitAlert: alert, agent: AgentActivitySummary()), .limit(alert))
        XCTAssertEqual(C.bubble(limitAlert: nil, agent: waiting), .agentWaiting(label: "a", message: "x", others: 2))
        XCTAssertEqual(C.bubble(limitAlert: nil, agent: both), .agentDone(label: "b", message: nil),
                       "a fresh done overlays a waiting agent")
        XCTAssertNil(C.bubble(limitAlert: nil, agent: AgentActivitySummary(working: true)))
        XCTAssertNil(C.bubble(limitAlert: nil, agent: AgentActivitySummary()))
    }

    /// Generalizing the bubble view must leave the limit-alert copy exactly as before.
    func testLimitBubbleContentIsUnchanged() {
        for lang in AppLanguage.allCases {
            let l = L(lang)
            for critical in [true, false] {
                let alert = UsageStore.LimitAlert(key: "k", window: l.claudeWeekly, isCritical: critical,
                                                  utilization: 96, account: "firstname.lastname@corp.example")
                let title = critical ? l.notifCritical : l.notifWarning
                XCTAssertEqual(C.bubbleContent(.limit(alert), l: l),
                               C.SpeechBubbleContent(title: title, body: C.bubbleBody(for: alert, title: title, l: l),
                                                     isCritical: critical))
            }
        }
    }

    func testAgentBubbleUsesDefaultsWithoutAMessage() {
        let l = L(.en)
        XCTAssertEqual(C.bubbleContent(.agentWaiting(label: nil, message: nil, others: 0), l: l),
                       C.SpeechBubbleContent(title: l.agentWaitingTitle, body: l.agentWaitingDefaultBody, isCritical: false))
        XCTAssertEqual(C.bubbleContent(.agentDone(label: nil, message: "Tests pass"), l: l),
                       C.SpeechBubbleContent(title: l.agentDoneTitle, body: "Tests pass", isCritical: false))
    }

    func testLabeledTitlesNameTheAgentAndCountTheRest() {
        let l = L(.en)
        XCTAssertEqual(C.bubbleContent(.agentWaiting(label: "web", message: nil, others: 0), l: l).title, "web · waiting")
        XCTAssertEqual(C.bubbleContent(.agentWaiting(label: "web", message: nil, others: 2), l: l).title,
                       "web · waiting +2")
        XCTAssertEqual(C.bubbleContent(.agentDone(label: "api", message: nil), l: l).title, "api · done")
        // Unlabeled keeps its title, cut at a word if the column is too narrow for the count.
        let unlabeled = C.bubbleContent(.agentWaiting(label: nil, message: nil, others: 1), l: l).title
        XCTAssertLessThanOrEqual(C.measureSpeechBubbleLayout(title: unlabeled, body: "").unclampedTitleWidth,
                                 C.bubbleContentWidth)
        XCTAssertTrue(unlabeled.hasSuffix(" +1"), unlabeled)
        let kept = String(unlabeled.dropLast(" +1".count))
        if kept != l.agentWaitingTitle {
            XCTAssertTrue(kept.hasSuffix("…"), unlabeled)
            let words = String(kept.dropLast())
            XCTAssertTrue(l.agentWaitingTitle.hasPrefix(words + " "), "cut between words: \(unlabeled)")
        }
        // Too long for any column: the cut lands between words, not inside one.
        let sentence = "Your coding agent is waiting for an answer from you"
        let cut = C.agentTitle(label: nil, unlabeled: sentence, status: "", count: "+3")
        XCTAssertTrue(cut.hasSuffix("… +3"), cut)
        XCTAssertTrue(sentence.hasPrefix(String(cut.dropLast("… +3".count)) + " "), "cut between words: \(cut)")
        let wide = String(repeating: "W", count: AgentActivityEvent.maxLabelLength)   // fits the label cap, not the line
        let long = C.bubbleContent(.agentWaiting(label: wide, message: nil, others: 7), l: l).title
        XCTAssertNotEqual(long, "\(wide) · waiting +7", "precondition: the full title does not fit one line")
        XCTAssertTrue(long.hasPrefix("WWW") && long.hasSuffix("… · waiting +7"),
                      "the label is cut, the status and count stay: \(long)")
    }

    /// Agent text is untrusted and up to 80 characters: in every language it must be cut with an
    /// ellipsis before the view's `lineLimit` would clip it (the #167 guard, reused).
    func testAgentBubbleTextNeverTruncates() throws {
        let limit = AgentActivityEvent.maxMessageLength
        let messages: [String?] = [
            nil,
            "Tests pass",
            try XCTUnwrap(AgentActivityEvent.sanitizedMessage(String(repeating: "M", count: 200))),
            try XCTUnwrap(AgentActivityEvent.sanitizedMessage(String(repeating: "あ", count: 200))),
            try XCTUnwrap(AgentActivityEvent.sanitizedMessage(String(repeating: "Supercalifragilistic ", count: 10))),
            String(repeating: "W", count: limit),
            try XCTUnwrap(AgentActivityEvent.sanitizedMessage(
                String(repeating: "a" + String(repeating: "\u{0301}", count: 2000), count: 79))),
        ]
        let labels: [String?] = [
            nil,
            "my-web-app",
            try XCTUnwrap(AgentActivityEvent.sanitizedLabel(String(repeating: "W", count: 60))),
            try XCTUnwrap(AgentActivityEvent.sanitizedLabel(String(repeating: "가나다라", count: 10))),
        ]
        for lang in AppLanguage.allCases {
            let l = L(lang)
            for message in messages {
                let bubbles = labels.flatMap { label in
                    [C.Bubble.agentWaiting(label: label, message: message, others: 0),
                     .agentWaiting(label: label, message: message, others: AgentActivityTracker.maxAgents - 1),
                     .agentDone(label: label, message: message)]
                }
                for bubble in bubbles {
                    let content = C.bubbleContent(bubble, l: l)
                    let layout = C.measureSpeechBubbleLayout(title: content.title, body: content.body)
                    XCTAssertFalse(layout.wouldTruncate, "\(lang.rawValue): \(content.body)")
                    XCTAssertLessThanOrEqual(layout.unclampedTitleWidth, C.bubbleContentWidth,
                                             "\(lang.rawValue) title wraps: \(content.title)")
                    XCTAssertLessThanOrEqual(layout.size.height, C.bubbleHeadroom - 2,
                                             "\(lang.rawValue) bubble overflows the headroom")
                }
            }
        }
    }

    func testFittingKeepsShortTextAndCutsLongText() {
        XCTAssertEqual(C.fittedBubbleBody("Tests pass", title: "Done!"), "Tests pass")
        let long = String(repeating: "W", count: 80)
        XCTAssertTrue(C.measureSpeechBubbleLayout(title: "Done!", body: long).wouldTruncate,
                      "precondition: the raw text would be clipped by the view")
        let fitted = C.fittedBubbleBody(long, title: "Done!")
        XCTAssertTrue(fitted.hasSuffix("…"))
        XCTAssertTrue(long.hasPrefix(fitted.dropLast()))
        XCTAssertFalse(C.measureSpeechBubbleLayout(title: "Done!", body: fitted).wouldTruncate)
        XCTAssertTrue(C.measureSpeechBubbleLayout(title: "Done!", body: String(long.prefix(fitted.count)) + "…").wouldTruncate,
                      "one more character must not fit — the cut is as long as possible")
    }
}

/// Controller wiring, not just the pure helpers. The display is kept "asleep" so no panel is
/// ever put on screen; the internal entry points stand in for AppKit callbacks.
@MainActor
final class FloatingPetAgentWiringTests: XCTestCase {
    private struct Fixture {
        let controller: FloatingPetController
        let store: UsageStore
        let defaults: UserDefaults
        let cleanUp: () -> Void
    }

    private func makeFixture(petEnabled: Bool = true, onOpenPopover: (() -> Void)? = nil) throws -> Fixture {
        // Motion pinned on: the bob must not depend on this Mac's Low Power or Reduce Motion.
        let suite = "FloatingPetAgentWiringTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(suite).json")
        let store = UsageStore(providers: [], autoRefresh: false, defaults: defaults)
        let companion = CompanionStore(fileURL: file, defaults: defaults)
        let controller = FloatingPetController(store: store, companion: companion, defaults: defaults,
                                               onOpenPopover: onOpenPopover, motionOverride: true)
        controller.setDisplayAwake(false)
        store.floatingPetEnabled = petEnabled
        return Fixture(controller: controller, store: store, defaults: defaults, cleanUp: {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: file)
        })
    }

    private func send(_ state: String, label: String? = nil, to controller: FloatingPetController) throws {
        let url = try XCTUnwrap(URL(string: "poketokenbar://agent?state=\(state)" + (label.map { "&label=\($0)" } ?? "")))
        controller.handleAgentEvent(try XCTUnwrap(AgentActivityEvent(url: url)))
    }

    /// Settings observation hops through a Task; give it a bounded chance to run.
    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<100 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    func testEventsAreDroppedWhileThePetOrTheSettingIsOff() throws {
        let off = try makeFixture(petEnabled: false)
        defer { off.cleanUp() }
        try send("working", to: off.controller)
        XCTAssertEqual(off.controller.tracker.activity, .idle, "floating pet off")

        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        fixture.store.floatingPetAgentActivity = false
        try send("waiting", to: fixture.controller)
        XCTAssertEqual(fixture.controller.tracker.activity, .idle, "setting off")
        XCTAssertNil(fixture.controller.agentExpiryFireDate)
    }

    func testTurningTheSettingOffResetsAgentState() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        // Let the sync queued by enabling the pet run first, so only the setting change can reset.
        try? await Task.sleep(for: .milliseconds(50))
        try send("working", to: fixture.controller)
        _ = fixture.controller.beginRun(cursor: NSPoint(x: 600, y: 500),
                                        visibleFrame: NSRect(x: 0, y: 0, width: 1440, height: 900))
        XCTAssertEqual(fixture.controller.tracker.activity, .working)
        XCTAssertNotNil(fixture.controller.agentExpiryFireDate)

        fixture.store.floatingPetAgentActivity = false
        await waitUntil { fixture.controller.tracker.activity == .idle }
        XCTAssertEqual(fixture.controller.tracker.activity, .idle)
        XCTAssertEqual(fixture.controller.runPhase, .home)
        XCTAssertNil(fixture.controller.agentExpiryFireDate, "no timer left behind")
    }

    /// The run's animation frames go through `windowDidMove`; they must never become home.
    func testTheRunNeverOverwritesTheSavedHome() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        fixture.defaults.set(300.0, forKey: "floatingPetOriginX")
        fixture.defaults.set(200.0, forKey: "floatingPetOriginY")
        let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)

        try send("done", to: fixture.controller)
        let run = fixture.controller.beginRun(cursor: NSPoint(x: 800, y: 600), visibleFrame: screen)
        fixture.controller.panelDidMove(panelOrigin: NSPoint(x: 500, y: 400), userDragging: false)
        fixture.controller.panelDidMove(panelOrigin: run.origin, userDragging: false)
        XCTAssertEqual(fixture.defaults.double(forKey: "floatingPetOriginX"), 300)
        XCTAssertEqual(fixture.defaults.double(forKey: "floatingPetOriginY"), 200)

        let deadline = try XCTUnwrap(fixture.controller.tracker.deadline)
        fixture.controller.expireAgentActivity(now: deadline)
        XCTAssertEqual(fixture.controller.tracker.activity, .idle)
        XCTAssertEqual(fixture.controller.runPhase, .home)
        XCTAssertEqual(fixture.defaults.double(forKey: "floatingPetOriginX"), 300)
        XCTAssertEqual(fixture.defaults.double(forKey: "floatingPetOriginY"), 200)
    }

    func testADragDuringTheRunBecomesTheNewHome() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        fixture.defaults.set(300.0, forKey: "floatingPetOriginX")
        fixture.defaults.set(200.0, forKey: "floatingPetOriginY")

        try send("done", to: fixture.controller)
        _ = fixture.controller.beginRun(cursor: NSPoint(x: 800, y: 600),
                                        visibleFrame: NSRect(x: 0, y: 0, width: 1440, height: 900))
        let dropped = NSPoint(x: 900, y: 100)
        fixture.controller.panelDidMove(panelOrigin: dropped, userDragging: true)
        XCTAssertEqual(fixture.controller.runPhase, .home, "the return is cancelled")

        let petSize = CGFloat(fixture.store.floatingPetSize)
        let pet = FloatingPetController.petOrigin(
            panelOrigin: dropped, petSize: petSize,
            panelSize: FloatingPetController.panelSize(petSize: petSize, showingBubble: true))
        XCTAssertEqual(fixture.defaults.double(forKey: "floatingPetOriginX"), Double(pet.x))
        XCTAssertEqual(fixture.defaults.double(forKey: "floatingPetOriginY"), Double(pet.y))
    }

    func testClickDismissesTheBubbleAndStillOpensThePopover() throws {
        var opened = 0
        let fixture = try makeFixture(onOpenPopover: { opened += 1 })
        defer { fixture.cleanUp() }

        try send("waiting", to: fixture.controller)
        fixture.controller.petClicked()
        XCTAssertEqual(fixture.controller.tracker.activity, .idle)
        XCTAssertEqual(opened, 1)

        try send("working", to: fixture.controller)
        fixture.controller.petClicked()
        XCTAssertEqual(fixture.controller.tracker.activity, .working, "a click does not stop work")
        XCTAssertEqual(opened, 2)
    }

    func testExpiryRearmsWhenTheTimerFiresEarly() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        try send("done", to: fixture.controller)
        let deadline = try XCTUnwrap(fixture.controller.tracker.deadline)
        XCTAssertEqual(fixture.controller.agentExpiryFireDate, deadline)

        fixture.controller.expireAgentActivity(now: deadline.addingTimeInterval(-0.5))
        XCTAssertEqual(fixture.controller.tracker.activity, .done(message: nil))
        XCTAssertEqual(fixture.controller.agentExpiryFireDate, deadline, "an early fire must arm again")

        fixture.controller.expireAgentActivity(now: deadline)
        XCTAssertEqual(fixture.controller.tracker.activity, .idle)
        XCTAssertNil(fixture.controller.agentExpiryFireDate)

        try send("waiting", to: fixture.controller)
        XCTAssertNil(fixture.controller.agentExpiryFireDate, "waiting arms no timer")
    }

    // MARK: Several agents

    private func bubble(_ controller: FloatingPetController) -> FloatingPetController.Bubble? {
        FloatingPetController.bubble(limitAlert: nil, agent: controller.tracker.summary)
    }

    /// One agent's done must not end another agent's work: the bob resumes after the done.
    func testDoneWhileAnotherAgentWorksKeepsTheBob() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        try send("working", label: "web", to: fixture.controller)
        XCTAssertTrue(fixture.controller.isBobbing)

        try send("done", label: "api", to: fixture.controller)
        _ = fixture.controller.beginRun(cursor: NSPoint(x: 600, y: 500),
                                        visibleFrame: NSRect(x: 0, y: 0, width: 1440, height: 900))
        XCTAssertEqual(bubble(fixture.controller), .agentDone(label: "api", message: nil))
        XCTAssertTrue(fixture.controller.isBobbing, "web is still working")

        let deadline = try XCTUnwrap(fixture.controller.tracker.agents["api"]?.deadline)
        fixture.controller.expireAgentActivity(now: deadline)
        XCTAssertEqual(fixture.controller.runPhase, .home, "the pet walks home after the done")
        XCTAssertNil(bubble(fixture.controller))
        XCTAssertTrue(fixture.controller.isBobbing, "and keeps bobbing for web")
    }

    /// A done overlays a waiting agent for its few seconds; the question comes back after.
    func testDoneWhileAnotherAgentWaitsBringsTheQuestionBack() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        try send("waiting", label: "web", to: fixture.controller)
        try send("working", label: "api", to: fixture.controller)
        XCTAssertEqual(bubble(fixture.controller), .agentWaiting(label: "web", message: nil, others: 0),
                       "another agent's work must not hide the question")

        try send("done", label: "api", to: fixture.controller)
        XCTAssertEqual(bubble(fixture.controller), .agentDone(label: "api", message: nil))
        let deadline = try XCTUnwrap(fixture.controller.tracker.agents["api"]?.deadline)
        fixture.controller.expireAgentActivity(now: deadline)
        XCTAssertEqual(bubble(fixture.controller), .agentWaiting(label: "web", message: nil, others: 0))
    }

    func testClickClearsEveryWaitingAgentButNotWork() throws {
        var opened = 0
        let fixture = try makeFixture(onOpenPopover: { opened += 1 })
        defer { fixture.cleanUp() }
        try send("waiting", label: "web", to: fixture.controller)
        try send("waiting", label: "api", to: fixture.controller)
        try send("working", label: "cli", to: fixture.controller)
        XCTAssertEqual(bubble(fixture.controller), .agentWaiting(label: "api", message: nil, others: 1))

        fixture.controller.petClicked()
        XCTAssertNil(bubble(fixture.controller), "both questions were seen")
        XCTAssertEqual(fixture.controller.tracker.summary.working, true)
        XCTAssertTrue(fixture.controller.isBobbing)
        XCTAssertEqual(opened, 1)
    }
}
