import XCTest
@testable import PokeTokenBar

/// `poketokenbar://agent` is an input any app or web page can send, so parsing must drop
/// everything it does not understand and keep the message plain and short.
final class AgentActivityTests: XCTestCase {
    private func event(_ string: String) -> AgentActivity? {
        URL(string: string).flatMap(AgentActivityEvent.init(url:))?.activity
    }

    func testParsesEveryState() {
        XCTAssertEqual(event("poketokenbar://agent?state=working"), .working)
        XCTAssertEqual(event("poketokenbar://agent?state=waiting"), .waiting(message: nil))
        XCTAssertEqual(event("poketokenbar://agent?state=done"), .done(message: nil))
        XCTAssertEqual(event("poketokenbar://agent?state=idle"), .idle)
        XCTAssertEqual(event("POKETOKENBAR://Agent?state=DONE"), .done(message: nil))
    }

    func testIgnoresUnknownInput() {
        XCTAssertNil(event("poketokenbar://agent?state=sleeping"), "unknown state")
        XCTAssertNil(event("poketokenbar://agent"), "missing state")
        XCTAssertNil(event("poketokenbar://agent?message=hi"), "message without state")
        XCTAssertNil(event("poketokenbar://settings?state=done"), "unknown host")
        XCTAssertNil(event("poketokenbar:agent?state=done"), "no host")
        XCTAssertNil(event("https://agent?state=done"), "other scheme")
    }

    func testMessageIsKeptOnlyForBubbleStates() {
        XCTAssertEqual(event("poketokenbar://agent?state=waiting&message=Pick%20a%20branch"),
                       .waiting(message: "Pick a branch"))
        XCTAssertEqual(event("poketokenbar://agent?state=done&message=Tests%20pass"), .done(message: "Tests pass"))
        XCTAssertEqual(event("poketokenbar://agent?state=working&message=ignored"), .working)
        XCTAssertEqual(event("poketokenbar://agent?message=first&state=done&state=working"), .done(message: "first"),
                       "the first state wins")
    }

    func testMessageIsCollapsedToOnePlainLine() {
        XCTAssertEqual(event("poketokenbar://agent?state=done&message=%20%20line%201%0A%0D%09line%202%20%20"),
                       .done(message: "line 1 line 2"))
        // Bidi override and zero-width space are invisible tricks, not text.
        XCTAssertEqual(AgentActivityEvent.sanitizedMessage("ab\u{202E}cd\u{200B}ef\u{0007}g"), "abcdef g")
        XCTAssertEqual(AgentActivityEvent.sanitizedMessage("family 👨‍👩‍👧"), "family 👨‍👩‍👧", "ZWJ emoji stay joined")
        XCTAssertNil(AgentActivityEvent.sanitizedMessage(" \n\t "))
        XCTAssertNil(AgentActivityEvent.sanitizedMessage(""))
        XCTAssertNil(AgentActivityEvent.sanitizedMessage(nil))
        XCTAssertEqual(event("poketokenbar://agent?state=waiting&message="), .waiting(message: nil))
    }

    func testOversizedMessageIsCappedWithAnEllipsis() throws {
        let limit = AgentActivityEvent.maxMessageLength
        let exact = String(repeating: "a", count: limit)
        XCTAssertEqual(AgentActivityEvent.sanitizedMessage(exact), exact)

        let long = String(repeating: "word ", count: 100)
        let capped = try XCTUnwrap(AgentActivityEvent.sanitizedMessage(long))
        XCTAssertLessThanOrEqual(capped.count, limit)
        XCTAssertTrue(capped.hasSuffix("…"))
        XCTAssertFalse(capped.dropLast().hasSuffix(" "), "no dangling space before the ellipsis")

        let encoded = try XCTUnwrap(long.addingPercentEncoding(withAllowedCharacters: .alphanumerics))
        guard case .done(let message)? = event("poketokenbar://agent?state=done&message=\(encoded)") else {
            return XCTFail("expected done")
        }
        XCTAssertEqual(message, capped)
    }

    /// One character can stack thousands of combining marks: the character cap alone let
    /// 79 × ("a" + 2000 marks) through and stalled text measuring on the main thread.
    func testStackedCombiningMarksAreBoundedByScalars() throws {
        let raw = String(repeating: "a" + String(repeating: "\u{0301}", count: 2000), count: 79)
        XCTAssertEqual(raw.count, 79, "precondition: the character cap alone would let it through")
        let message = try XCTUnwrap(AgentActivityEvent.sanitizedMessage(raw))
        XCTAssertLessThanOrEqual(message.unicodeScalars.count, AgentActivityEvent.maxMessageScalars)
        XCTAssertLessThanOrEqual(message.count, AgentActivityEvent.maxMessageLength)
        XCTAssertTrue(message.hasSuffix("…"))
    }

    // MARK: Tracker

    private let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)
    private func apply(_ activity: AgentActivity, label: String? = nil,
                       to tracker: inout AgentActivityTracker, at date: Date) {
        let state: String
        var message = ""
        switch activity {
        case .idle: state = "idle"
        case .working: state = "working"
        case .waiting(let m): state = "waiting"; message = m.map { "&message=\($0)" } ?? ""
        case .done(let m): state = "done"; message = m.map { "&message=\($0)" } ?? ""
        }
        let labelItem = label.map { "&label=\($0)" } ?? ""
        tracker.apply(AgentActivityEvent(url: URL(string: "poketokenbar://agent?state=\(state)\(message)\(labelItem)")!)!,
                      now: date)
    }

    func testWorkingExpiresAfterTenMinutesWithoutNews() {
        var tracker = AgentActivityTracker()
        apply(.working, to: &tracker, at: t0)
        XCTAssertEqual(tracker.deadline, t0.addingTimeInterval(600))
        XCTAssertFalse(tracker.expire(now: t0.addingTimeInterval(599)))
        XCTAssertEqual(tracker.activity, .working)
        XCTAssertTrue(tracker.expire(now: t0.addingTimeInterval(600)))
        XCTAssertEqual(tracker.activity, .idle)
        XCTAssertNil(tracker.deadline)
        XCTAssertFalse(tracker.expire(now: t0.addingTimeInterval(10_000)), "idle has nothing to expire")
    }

    func testAnotherWorkingEventPushesTheTimeoutBack() {
        var tracker = AgentActivityTracker()
        apply(.working, to: &tracker, at: t0)
        apply(.working, to: &tracker, at: t0.addingTimeInterval(500))
        XCTAssertFalse(tracker.expire(now: t0.addingTimeInterval(700)))
        XCTAssertEqual(tracker.activity, .working)
    }

    func testDoneShowsForSixSeconds() {
        var tracker = AgentActivityTracker()
        apply(.done(message: "ok"), to: &tracker, at: t0)
        XCTAssertFalse(tracker.expire(now: t0.addingTimeInterval(5.9)))
        XCTAssertEqual(tracker.activity, .done(message: "ok"))
        XCTAssertTrue(tracker.expire(now: t0.addingTimeInterval(6)))
        XCTAssertEqual(tracker.activity, .idle)
    }

    func testWaitingStaysUntilTheNextEventOrAClick() {
        var tracker = AgentActivityTracker()
        apply(.working, to: &tracker, at: t0)
        apply(.waiting(message: nil), to: &tracker, at: t0.addingTimeInterval(1))
        XCTAssertNil(tracker.deadline, "waiting must not inherit the working timeout")
        XCTAssertFalse(tracker.expire(now: t0.addingTimeInterval(86_400)))
        XCTAssertEqual(tracker.activity, .waiting(message: nil))

        XCTAssertTrue(tracker.dismissBubble())
        XCTAssertEqual(tracker.activity, .idle)

        apply(.waiting(message: nil), to: &tracker, at: t0)
        apply(.working, to: &tracker, at: t0.addingTimeInterval(2))
        XCTAssertEqual(tracker.activity, .working)
    }

    func testClickDismissesOnlyBubbles() {
        var tracker = AgentActivityTracker()
        apply(.working, to: &tracker, at: t0)
        XCTAssertFalse(tracker.dismissBubble(), "a click does not stop work")
        XCTAssertEqual(tracker.activity, .working)
        XCTAssertNotNil(tracker.deadline)

        apply(.done(message: nil), to: &tracker, at: t0)
        XCTAssertTrue(tracker.dismissBubble())
        XCTAssertEqual(tracker.activity, .idle)
        XCTAssertNil(tracker.deadline)
        XCTAssertFalse(tracker.dismissBubble())
    }

    func testIdleEventClearsEverything() {
        var tracker = AgentActivityTracker()
        apply(.working, to: &tracker, at: t0)
        apply(.idle, to: &tracker, at: t0)
        XCTAssertTrue(tracker.agents.isEmpty)
        XCTAssertNil(tracker.deadline)
        XCTAssertEqual(tracker.activity, .idle)
    }

    // MARK: Several agents

    func testLabelIsParsedAndCleanedLikeAMessage() throws {
        let url = try XCTUnwrap(URL(string: "poketokenbar://agent?state=done&label=%20my%0A%20project%E2%80%AE%20"))
        XCTAssertEqual(AgentActivityEvent(url: url)?.label, "my project")
        let plain = try XCTUnwrap(URL(string: "poketokenbar://agent?state=done"))
        XCTAssertNil(AgentActivityEvent(url: plain)?.label, "no label is the one unlabeled agent")
        let empty = try XCTUnwrap(URL(string: "poketokenbar://agent?state=done&label=%20"))
        XCTAssertNil(AgentActivityEvent(url: empty)?.label)

        let limit = AgentActivityEvent.maxLabelLength
        let long = try XCTUnwrap(AgentActivityEvent.sanitizedLabel(String(repeating: "x", count: 100)))
        XCTAssertEqual(long.count, limit)
        XCTAssertTrue(long.hasSuffix("…"))
        let stacked = try XCTUnwrap(AgentActivityEvent.sanitizedLabel(
            String(repeating: "a" + String(repeating: "\u{0301}", count: 500), count: 20)))
        XCTAssertLessThanOrEqual(stacked.unicodeScalars.count, limit * 4)
    }

    /// The regression this change fixes: one session's events wiped another session's state.
    func testEachLabelKeepsItsOwnState() {
        var tracker = AgentActivityTracker()
        apply(.working, label: "web", to: &tracker, at: t0)
        apply(.done(message: nil), label: "api", to: &tracker, at: t0.addingTimeInterval(1))
        XCTAssertTrue(tracker.summary.working, "api's done must not end web's work")
        XCTAssertEqual(tracker.summary.done, .init(label: "api", message: nil))

        XCTAssertTrue(tracker.expire(now: t0.addingTimeInterval(7)))
        XCTAssertNil(tracker.summary.done)
        XCTAssertTrue(tracker.summary.working)
        XCTAssertEqual(tracker.activity, .working)
    }

    func testUnlabeledEventsStillShareOneAgent() {
        var tracker = AgentActivityTracker()
        apply(.working, to: &tracker, at: t0)
        apply(.done(message: nil), to: &tracker, at: t0)
        XCTAssertFalse(tracker.summary.working, "without labels a done ends the work, as before")
        XCTAssertEqual(tracker.agents.count, 1)
    }

    func testWaitingOutranksWorkingAndCountsTheOthers() {
        var tracker = AgentActivityTracker()
        apply(.waiting(message: "first"), label: "a", to: &tracker, at: t0)
        apply(.working, label: "b", to: &tracker, at: t0)
        apply(.waiting(message: "latest"), label: "c", to: &tracker, at: t0)
        let summary = tracker.summary
        XCTAssertEqual(summary.waiting, .init(label: "c", message: "latest"), "the most recent question first")
        XCTAssertEqual(summary.otherWaitingCount, 1)
        XCTAssertTrue(summary.working)
        XCTAssertEqual(tracker.activity, .waiting(message: "latest"))

        apply(.working, label: "c", to: &tracker, at: t0)   // c's question was answered
        XCTAssertEqual(tracker.summary.waiting, .init(label: "a", message: "first"))
        XCTAssertEqual(tracker.summary.otherWaitingCount, 0)
    }

    func testDoneOverlaysAWaitingAgentOnlyForItsFewSeconds() {
        var tracker = AgentActivityTracker()
        apply(.waiting(message: nil), label: "a", to: &tracker, at: t0)
        apply(.done(message: nil), label: "b", to: &tracker, at: t0)
        XCTAssertEqual(tracker.activity, .done(message: nil))
        XCTAssertEqual(tracker.summary.waiting?.label, "a", "the question is still there underneath")
        tracker.expire(now: t0.addingTimeInterval(AgentActivityTracker.doneDuration))
        XCTAssertEqual(tracker.activity, .waiting(message: nil))
    }

    /// Overlapping dones: the bubble follows the latest, and each leaves on its own clock.
    func testOverlappingDonesShowTheLatest() {
        var tracker = AgentActivityTracker()
        apply(.done(message: "a"), label: "a", to: &tracker, at: t0)
        apply(.done(message: "b"), label: "b", to: &tracker, at: t0.addingTimeInterval(2))
        apply(.done(message: "c"), label: "c", to: &tracker, at: t0.addingTimeInterval(1))
        XCTAssertEqual(tracker.summary.done, .init(label: "c", message: "c"), "latest event, not latest clock")
        tracker.expire(now: t0.addingTimeInterval(AgentActivityTracker.doneDuration + 1))
        XCTAssertEqual(tracker.summary.done, .init(label: "b", message: "b"))
    }

    func testEachLabelExpiresOnItsOwnClock() {
        var tracker = AgentActivityTracker()
        apply(.working, label: "a", to: &tracker, at: t0)
        apply(.working, label: "b", to: &tracker, at: t0.addingTimeInterval(300))
        XCTAssertEqual(tracker.deadline, t0.addingTimeInterval(600), "the earliest deadline arms the timer")
        XCTAssertTrue(tracker.expire(now: t0.addingTimeInterval(600)))
        XCTAssertEqual(Array(tracker.agents.keys), ["b"])
        XCTAssertEqual(tracker.deadline, t0.addingTimeInterval(900))
    }

    func testClickClearsEveryQuestionAndResultButNotWork() {
        var tracker = AgentActivityTracker()
        apply(.waiting(message: nil), label: "a", to: &tracker, at: t0)
        apply(.waiting(message: nil), label: "b", to: &tracker, at: t0)
        apply(.done(message: nil), label: "c", to: &tracker, at: t0)
        apply(.working, label: "d", to: &tracker, at: t0)
        XCTAssertTrue(tracker.dismissBubble())
        XCTAssertEqual(Array(tracker.agents.keys), ["d"])
        XCTAssertFalse(tracker.dismissBubble())
    }

    func testIdleClearsOnlyItsOwnLabel() {
        var tracker = AgentActivityTracker()
        apply(.working, label: "a", to: &tracker, at: t0)
        apply(.working, label: "b", to: &tracker, at: t0)
        apply(.idle, label: "a", to: &tracker, at: t0)
        XCTAssertEqual(Array(tracker.agents.keys), ["b"])
    }

    /// Labels are untrusted: a flood of them keeps only the newest few agents.
    func testTheNumberOfAgentsIsCapped() {
        var tracker = AgentActivityTracker()
        for index in 0..<50 {
            apply(.working, label: "agent\(index)", to: &tracker, at: t0.addingTimeInterval(Double(index)))
        }
        XCTAssertEqual(tracker.agents.count, AgentActivityTracker.maxAgents)
        XCTAssertEqual(Set(tracker.agents.keys), Set((42..<50).map { "agent\($0)" }), "the oldest go first")

        apply(.working, label: "agent42", to: &tracker, at: t0.addingTimeInterval(60))   // refresh, no eviction
        XCTAssertEqual(tracker.agents.count, AgentActivityTracker.maxAgents)
        apply(.waiting(message: nil), label: "new", to: &tracker, at: t0.addingTimeInterval(61))
        XCTAssertNil(tracker.agents["agent43"], "agent42 was refreshed, so agent43 is now the oldest")
        XCTAssertNotNil(tracker.agents["agent42"])
    }
}
