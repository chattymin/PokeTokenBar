import XCTest
@testable import PokeTokenBar

@MainActor
final class FocusSessionTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private let day = "2026-09-06"

    private func issue() -> LinearIssueSummary {
        LinearIssueSummary(
            id: "issue-1",
            identifier: "ENG-142",
            title: "Ship login",
            issueURL: URL(string: "https://linear.app/issue/ENG-142"),
            priority: 2,
            estimate: nil,
            stateId: "start",
            stateName: "In Progress",
            stateType: "started",
            assigneeName: nil,
            assigneeEmail: nil,
            projectName: nil,
            teamName: "Eng",
            teamKey: "ENG",
            teamID: "team-1",
            teamStates: [
                LinearWorkflowState(id: "start", name: "In Progress", type: "started", position: 1),
                LinearWorkflowState(id: "done", name: "Done", type: "completed", position: 2),
            ],
            completedStateId: "done",
            labelNames: [],
            createdAt: nil,
            updatedAt: nil,
            dueDate: nil,
            completedAt: nil,
            descriptionText: nil)
    }

    private func runningSession(planned: Int = 50, checkIn: Int = 30) -> FocusSession {
        FocusSession.start(
            issue: FocusPinnedIssue(issue()),
            plannedMinutes: planned,
            checkInMinutes: checkIn,
            now: t0)
    }

    func testOnTimeDonePaysFiveTimesPlannedIntervals() {
        var session = runningSession()
        session = FocusTick.apply(session, now: t0.addingTimeInterval(50 * 60)).session
        XCTAssertEqual(session.phase, .awaitingChoice)
        XCTAssertTrue(session.fiveXOpen)
        XCTAssertEqual(FocusTick.settleOnTimeDone(session), 25_000_000)
    }

    func testFinishLeaveInProgressNeverOvertimePaysOneTimes() {
        var session = runningSession()
        session = FocusTick.apply(session, now: t0.addingTimeInterval(50 * 60)).session
        XCTAssertEqual(FocusTick.settleLeaveInProgress(session), 5_000_000)
    }

    func testAutoContinueClosesFiveXAndSettlesPlannedAtOneX() {
        var session = runningSession()
        session = FocusTick.apply(session, now: t0.addingTimeInterval(50 * 60)).session
        let result = FocusTick.apply(session, now: t0.addingTimeInterval(50 * 60 + 30))
        XCTAssertTrue(result.autoContinued)
        XCTAssertEqual(result.session.phase, .overtime)
        XCTAssertFalse(result.session.fiveXOpen)
        XCTAssertEqual(result.sessionXP, 5_000_000)
        XCTAssertEqual(FocusTick.settleLeaveInProgress(result.session), 0)
    }

    func testOvertimeWithoutNotePaysOneXPerInterval() {
        var session = runningSession()
        session = FocusTick.apply(session, now: t0.addingTimeInterval(50 * 60)).session
        let continued = FocusTick.continueOvertime(session, now: t0.addingTimeInterval(50 * 60 + 1))
        XCTAssertEqual(continued.xp, 5_000_000)
        let ot = FocusTick.apply(
            continued.session,
            now: t0.addingTimeInterval(50 * 60 + 1 + 10 * 60))
        XCTAssertEqual(ot.sessionXP, 1_000_000)
        XCTAssertEqual(ot.session.overtimePaidMultiplier, 1)
    }

    func testOvertimeWithNotePaysTwoXAndTopsUpEarlierTicks() {
        var session = runningSession()
        session = FocusTick.apply(session, now: t0.addingTimeInterval(50 * 60)).session
        session = FocusTick.continueOvertime(session, now: t0.addingTimeInterval(50 * 60 + 1)).session
        session = FocusTick.apply(
            session,
            now: t0.addingTimeInterval(50 * 60 + 1 + 10 * 60)).session
        XCTAssertEqual(session.overtimeIntervalsPaid, 1)
        XCTAssertEqual(session.overtimePaidMultiplier, 1)

        let marked = FocusTick.markNotePosted(session)
        XCTAssertEqual(marked.topUpXP, 1_000_000)
        XCTAssertEqual(marked.session.overtimePaidMultiplier, 2)

        let next = FocusTick.apply(
            marked.session,
            now: t0.addingTimeInterval(50 * 60 + 1 + 20 * 60))
        XCTAssertEqual(next.sessionXP, 2_000_000)
    }

    func testSubTenMinuteOnTimeDoneHasZeroSessionIntervals() {
        var session = runningSession()
        session = FocusTick.apply(session, now: t0.addingTimeInterval(8 * 60)).session
        XCTAssertEqual(session.phase, .running)
        XCTAssertEqual(FocusTick.settleOnTimeDone(session), 0)
        XCTAssertEqual(FocusTick.settleLeaveInProgress(session), 0)
    }

    func testZeroTimeHoldDoesNotAccrueOvertime() {
        var session = runningSession()
        session = FocusTick.apply(session, now: t0.addingTimeInterval(50 * 60)).session
        XCTAssertEqual(session.phase, .awaitingChoice)
        let held = FocusTick.apply(session, now: t0.addingTimeInterval(50 * 60 + 29))
        XCTAssertEqual(held.session.phase, .awaitingChoice)
        XCTAssertEqual(held.sessionXP, 0)
        XCTAssertEqual(held.session.accumulatedSeconds, 50 * 60)
        XCTAssertFalse(held.autoContinued)
    }

    func testCheckInWaitsWhenZeroTimePopupIsShowing() {
        let session = runningSession(planned: 30, checkIn: 30)
        let result = FocusTick.apply(session, now: t0.addingTimeInterval(30 * 60))
        XCTAssertEqual(result.session.phase, .awaitingChoice)
        XCTAssertTrue(result.hitZero)
        XCTAssertFalse(result.session.pendingCheckIn)
        XCTAssertTrue(result.session.checkInDeferred)

        let continued = FocusTick.continueOvertime(
            result.session, now: t0.addingTimeInterval(30 * 60 + 1))
        XCTAssertTrue(continued.session.pendingCheckIn)
    }

    func testPauseAndSleepDoNotAccrue() {
        var session = runningSession()
        session = FocusTick.apply(session, now: t0.addingTimeInterval(5 * 60)).session
        session = FocusTick.pause(session, now: t0.addingTimeInterval(5 * 60))
        session = FocusTick.apply(session, now: t0.addingTimeInterval(40 * 60)).session
        XCTAssertEqual(session.accumulatedSeconds, 5 * 60, accuracy: 0.01)

        session = FocusTick.resume(session, now: t0.addingTimeInterval(40 * 60))
        session = FocusTick.holdSleep(session, now: t0.addingTimeInterval(41 * 60))
        session = FocusTick.apply(session, now: t0.addingTimeInterval(80 * 60)).session
        XCTAssertEqual(session.accumulatedSeconds, 6 * 60, accuracy: 0.01)
    }

    func testCheckInCommentBodyAndSkipIsNotDrift() {
        let body = FocusTick.checkInCommentBody(
            answer: .no,
            identifier: "ENG-142",
            elapsedSeconds: 32 * 60,
            note: "  still debugging  ")
        XCTAssertEqual(body, "Check-in · No · ENG-142 · 32m\nstill debugging")
        XCTAssertFalse(body.contains("lin_api_"))
    }

    func testTimeOpenIsPausedDuringSessionAndResumesFromNow() {
        let clock = TimeOpenCompanionTestsClock(t0)
        let companion = CompanionStore(
            provider: StubProvider(value: EvoLine(
                baseID: 1,
                tree: EvoNode(speciesID: 1, children: []),
                rarity: .common,
                names: [:])),
            clock: { clock.now },
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("focus-xp-\(UUID().uuidString).json"),
            rng: SeededRNG(seed: 1))
        let usage = UsageStore(
            providers: [],
            autoRefresh: false,
            defaults: UserDefaults(suiteName: "focus-session-\(UUID().uuidString)")!)
        let focus = FocusSessionStore(
            usage: usage,
            companion: companion,
            clock: { clock.now },
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("focus-state-\(UUID().uuidString).json"),
            ticksOnTimer: false)

        companion.update(
            todayTokensByProvider: ["test": 0],
            todayDate: day,
            monthTotal: 0,
            burnTier: .idle,
            limitWarning: false,
            hasUsageData: true)
        XCTAssertNotNil(companion.state.lastTimeOpenAwardAt)

        focus.pin(issue(), openDesk: false)
        XCTAssertTrue(companion.timeOpenXPSuspended)

        clock.now = t0.addingTimeInterval(TimeOpenXP.awardIntervalSeconds * 2)
        companion.update(
            todayTokensByProvider: ["test": 0],
            todayDate: day,
            monthTotal: 0,
            burnTier: .idle,
            limitWarning: false,
            hasUsageData: true)
        XCTAssertEqual(companion.state.eggUsage, 0, "time-open must not pay during a session")

        focus.tick(now: t0.addingTimeInterval(50 * 60))
        XCTAssertEqual(focus.session?.phase, .awaitingChoice)
        focus.finishLeavingInProgress()
        XCTAssertFalse(companion.timeOpenXPSuspended)
        XCTAssertEqual(companion.state.eggUsage, 5_000_000)
        XCTAssertEqual(companion.state.lastTimeOpenAwardAt, clock.now)
    }

    func testSessionXPFollowsTimeOpenToggle() {
        let companion = CompanionStore(
            provider: StubProvider(value: EvoLine(
                baseID: 1,
                tree: EvoNode(speciesID: 1, children: []),
                rarity: .common,
                names: [:])),
            clock: { self.t0 },
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("focus-xp-off-\(UUID().uuidString).json"),
            rng: SeededRNG(seed: 1))
        let defaults = UserDefaults(suiteName: "focus-xp-off-\(UUID().uuidString)")!
        let usage = UsageStore(providers: [], autoRefresh: false, defaults: defaults)
        usage.timeOpenXPEnabled = false
        let focus = FocusSessionStore(
            usage: usage,
            companion: companion,
            clock: { self.t0 },
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("focus-state-off-\(UUID().uuidString).json"),
            ticksOnTimer: false)

        focus.pin(issue(), openDesk: false)
        focus.tick(now: t0.addingTimeInterval(50 * 60))
        focus.finishLeavingInProgress()
        XCTAssertEqual(companion.state.eggUsage, 0)
    }
}

/// Clock box local to this file so FocusSessionTests does not depend on TimeOpenCompanionTests internals.
private final class TimeOpenCompanionTestsClock: @unchecked Sendable {
    nonisolated(unsafe) var now: Date
    init(_ d: Date) { now = d }
}
