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

    func testFirstCompletePersistsXPAndRecompleteKeepsStoredAmount() {
        let stores = makeStores()
        _ = stores.companion.creditLinearCompletions([])
        let completed = LinearCompletedIssue(
            id: "issue-1", identifier: "ENG-142", title: "Ship login", completedAt: t0)

        let first = stores.companion.creditLinearCompletions([completed])
        XCTAssertEqual(first.xp, LinearRewards.xpPerIssue)
        XCTAssertEqual(stores.companion.linearIssueXP(id: "issue-1")?.xp, LinearRewards.xpPerIssue)
        let eggAfterAward = stores.companion.state.eggUsage

        let second = stores.companion.creditLinearCompletions([completed])
        XCTAssertEqual(second.xp, 0)
        XCTAssertEqual(stores.companion.linearIssueXP(id: "issue-1")?.xp, LinearRewards.xpPerIssue)
        XCTAssertEqual(stores.companion.state.eggUsage, eggAfterAward)
        XCTAssertNil(stores.focus.history(forIssueID: "issue-1"))
    }

    func testCompletedIssueWithoutSessionShowsLinearXPOnly() {
        let stores = makeStores()
        _ = stores.companion.creditLinearCompletions([])
        let completed = LinearCompletedIssue(
            id: "issue-1", identifier: "ENG-142", title: "Ship login", completedAt: t0)
        _ = stores.companion.creditLinearCompletions([completed])

        XCTAssertEqual(stores.companion.linearIssueXP(id: "issue-1")?.xp, LinearRewards.xpPerIssue)
        XCTAssertNil(stores.focus.history(forIssueID: "issue-1"))
        XCTAssertNil(stores.focus.history(forIssueID: "missing"))
        XCTAssertNil(stores.companion.linearIssueXP(id: "missing"))
    }

    func testCompletedIssueAfterFocusSessionStoresTimerSummary() throws {
        let clock = TimeOpenCompanionTestsClock(t0)
        let stores = makeStores(clock: clock)
        stores.focus.pin(issue(), openDesk: false)
        stores.focus.tick(now: t0.addingTimeInterval(50 * 60))
        let completed = LinearCompletedIssue(
            id: "issue-1", identifier: "ENG-142", title: "Ship login", completedAt: t0)
        _ = stores.companion.creditLinearCompletions([])
        _ = stores.companion.creditLinearCompletions([completed])
        stores.focus.handleLinearCompletion(completed)

        XCTAssertEqual(stores.companion.linearIssueXP(id: "issue-1")?.xp, LinearRewards.xpPerIssue)
        let history = try XCTUnwrap(stores.focus.history(forIssueID: "issue-1"))
        XCTAssertEqual(history.finish, .doneOnTime)
        XCTAssertEqual(history.plannedSeconds, 50 * 60)
        XCTAssertEqual(history.durationSeconds, 50 * 60, accuracy: 0.01)
        XCTAssertEqual(history.overtimeSeconds, 0)
        XCTAssertEqual(history.sessionXP, 25_000_000)
        XCTAssertTrue(history.checkIns.isEmpty)
        XCTAssertNil(stores.focus.session)
    }

    func testOvertimeDoneHistoryRecordsContinuePath() throws {
        let clock = TimeOpenCompanionTestsClock(t0)
        let stores = makeStores(clock: clock)
        stores.focus.pin(issue(), openDesk: false)
        stores.focus.tick(now: t0.addingTimeInterval(50 * 60))
        clock.now = t0.addingTimeInterval(50 * 60 + 1)
        stores.focus.continueOvertime()
        clock.now = t0.addingTimeInterval(50 * 60 + 1 + 10 * 60)
        stores.focus.tick(now: clock.now)
        let completed = LinearCompletedIssue(
            id: "issue-1", identifier: "ENG-142", title: "Ship login", completedAt: clock.now)
        stores.focus.handleLinearCompletion(completed)

        let history = try XCTUnwrap(stores.focus.history(forIssueID: "issue-1"))
        XCTAssertEqual(history.finish, .doneOvertime)
        XCTAssertGreaterThan(history.overtimeSeconds, 0)
        XCTAssertEqual(history.sessionXP, 6_000_000)
    }

    func testLeaveInProgressHistoryThenCompleteWithoutSessionKeepsTimer() throws {
        let clock = TimeOpenCompanionTestsClock(t0)
        let stores = makeStores(clock: clock)
        stores.focus.pin(issue(), openDesk: false)
        stores.focus.tick(now: t0.addingTimeInterval(20 * 60))
        stores.focus.finishLeavingInProgress()

        let history = try XCTUnwrap(stores.focus.history(forIssueID: "issue-1"))
        XCTAssertEqual(history.finish, .leftInProgress)
        XCTAssertEqual(history.durationSeconds, 20 * 60, accuracy: 0.01)
        XCTAssertEqual(history.sessionXP, 2_000_000)

        _ = stores.companion.creditLinearCompletions([])
        _ = stores.companion.creditLinearCompletions([
            LinearCompletedIssue(
                id: "issue-1", identifier: "ENG-142", title: "Ship login", completedAt: t0)
        ])
        XCTAssertEqual(stores.companion.linearIssueXP(id: "issue-1")?.xp, LinearRewards.xpPerIssue)
        XCTAssertEqual(stores.focus.history(forIssueID: "issue-1")?.finish, .leftInProgress)
    }

    func testCheckInNoteLandsOnCompletedHistory() async throws {
        let clock = TimeOpenCompanionTestsClock(t0)
        let stores = makeStores(clock: clock)
        stores.focus.checkInMinutes = 30
        stores.focus.pin(issue(), openDesk: false)
        stores.focus.tick(now: t0.addingTimeInterval(30 * 60))
        XCTAssertEqual(stores.focus.prompt, .checkIn)
        stores.focus.checkInDraft = "  still debugging  "
        await stores.focus.answerCheckIn(.no)
        stores.focus.tick(now: t0.addingTimeInterval(50 * 60))
        stores.focus.handleLinearCompletion(LinearCompletedIssue(
            id: "issue-1", identifier: "ENG-142", title: "Ship login", completedAt: t0))

        let history = try XCTUnwrap(stores.focus.history(forIssueID: "issue-1"))
        XCTAssertEqual(history.checkIns.count, 1)
        XCTAssertEqual(history.checkIns.first?.answer, .no)
        XCTAssertEqual(history.checkIns.first?.note, "still debugging")
        XCTAssertFalse(history.checkIns.first?.notePosted ?? true)
    }

    func testIssueHistorySurvivesReloadAndOldJSONDoesNotCrash() throws {
        let clock = TimeOpenCompanionTestsClock(t0)
        let stores = makeStores(clock: clock)
        stores.focus.pin(issue(), openDesk: false)
        stores.focus.tick(now: t0.addingTimeInterval(50 * 60))
        stores.focus.handleLinearCompletion(LinearCompletedIssue(
            id: "issue-1", identifier: "ENG-142", title: "Ship login", completedAt: t0))

        let reloaded = FocusSessionStore(
            usage: stores.usage,
            companion: stores.companion,
            clock: { clock.now },
            fileURL: stores.focusURL,
            ticksOnTimer: false)
        XCTAssertEqual(reloaded.history(forIssueID: "issue-1")?.finish, .doneOnTime)
        XCTAssertEqual(reloaded.history(forIssueID: "issue-1")?.sessionXP, 25_000_000)

        let legacyURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("focus-legacy-\(UUID().uuidString).json")
        let legacy = """
        {"checkInMinutes":30,"log":[],"logDay":"2026-09-06","plannedMinutes":50}
        """
        try Data(legacy.utf8).write(to: legacyURL)
        let legacyStore = FocusSessionStore(
            usage: stores.usage,
            companion: stores.companion,
            clock: { self.t0 },
            fileURL: legacyURL,
            ticksOnTimer: false)
        XCTAssertTrue(legacyStore.issueHistory.isEmpty)
        XCTAssertEqual(legacyStore.plannedMinutes, 50)
        XCTAssertNil(legacyStore.history(forIssueID: "issue-1"))
    }

    func testTruncatedCheckInNoteCapsLength() throws {
        let long = String(repeating: "n", count: FocusCheckInSummary.maxNoteChars + 40)
        let note = try XCTUnwrap(FocusCheckInSummary.truncatedNote("  \(long)  "))
        XCTAssertEqual(note.count, FocusCheckInSummary.maxNoteChars)
        XCTAssertNil(FocusCheckInSummary.truncatedNote("   "))
    }

    func testSessionCommentBodyDoesNotLookLikeACheckIn() {
        let body = FocusTick.sessionCommentBody(
            identifier: "ENG-142",
            elapsedSeconds: 12 * 60,
            note: "  still blocked  ")
        XCTAssertEqual(body, "Note · ENG-142 · 12m\nstill blocked")
        XCTAssertFalse(body.contains("Check-in"))
        XCTAssertFalse(body.contains("lin_api_"))
    }

    func testSessionNoteCanBePostedBeforeFirstCheckIn() async {
        let capture = CommentCapture()
        let stores = makeStores(postComment: capture.post)
        stores.focus.pin(issue(), openDesk: false)
        XCTAssertEqual(stores.focus.session?.pendingCheckIn, false)
        XCTAssertEqual(stores.focus.prompt, .none)

        stores.focus.noteDraft = "context before check-in"
        await stores.focus.postSessionNote()

        XCTAssertEqual(capture.posts.count, 1)
        XCTAssertEqual(capture.posts.first?.issueID, "issue-1")
        XCTAssertTrue(capture.posts.first?.body.contains("Note · ENG-142") == true)
        XCTAssertTrue(capture.posts.first?.body.contains("context before check-in") == true)
        XCTAssertTrue(stores.focus.session?.checkInNotePosted == true)
        XCTAssertEqual(stores.focus.todayLog.filter { $0.kind == .note }.compactMap(\.noteText), ["context before check-in"])
        XCTAssertFalse(stores.focus.notePostFailed)
        XCTAssertTrue(stores.focus.noteDraft.isEmpty)
    }

    func testSessionNotePostsLinearCommentAndEmptyIsNoOp() async {
        let capture = CommentCapture()
        let stores = makeStores(postComment: capture.post)
        stores.focus.pin(issue(), openDesk: false)

        stores.focus.noteDraft = "   "
        await stores.focus.postSessionNote()
        XCTAssertTrue(capture.posts.isEmpty)
        XCTAssertFalse(stores.focus.session?.checkInNotePosted ?? true)

        stores.focus.noteDraft = ""
        await stores.focus.postSessionNote()
        XCTAssertTrue(capture.posts.isEmpty)

        stores.focus.noteDraft = "ship it"
        await stores.focus.postSessionNote()
        XCTAssertEqual(capture.posts.map(\.body), ["Note · ENG-142 · 0m\nship it"])
        XCTAssertFalse(capture.posts.contains { $0.body.contains("lin_api_") })
    }

    func testSessionNoteInOvertimeSetsOTFlag() async {
        let clock = TimeOpenCompanionTestsClock(t0)
        let capture = CommentCapture()
        let stores = makeStores(clock: clock, postComment: capture.post)
        stores.focus.pin(issue(), openDesk: false)
        stores.focus.tick(now: t0.addingTimeInterval(50 * 60))
        clock.now = t0.addingTimeInterval(50 * 60 + 1)
        stores.focus.continueOvertime()
        clock.now = t0.addingTimeInterval(50 * 60 + 1 + 10 * 60)
        stores.focus.tick(now: clock.now)
        XCTAssertEqual(stores.focus.session?.overtimePaidMultiplier, 1)
        XCTAssertEqual(stores.focus.session?.checkInNotePosted, false)

        stores.focus.noteDraft = "still going"
        await stores.focus.postSessionNote()

        XCTAssertEqual(capture.posts.count, 1)
        XCTAssertEqual(stores.focus.session?.checkInNotePosted, true)
        XCTAssertEqual(stores.focus.session?.overtimePaidMultiplier, 2)
    }

    func testSessionNotePersistsForTodayDeskAndCompletedHistory() async throws {
        let clock = TimeOpenCompanionTestsClock(t0)
        let capture = CommentCapture()
        let stores = makeStores(clock: clock, postComment: capture.post)
        stores.focus.pin(issue(), openDesk: false)
        stores.focus.noteDraft = "desk context"
        await stores.focus.postSessionNote()
        stores.focus.tick(now: t0.addingTimeInterval(50 * 60))
        stores.focus.handleLinearCompletion(LinearCompletedIssue(
            id: "issue-1", identifier: "ENG-142", title: "Ship login", completedAt: t0))

        XCTAssertEqual(stores.focus.history(forIssueID: "issue-1")?.notes, ["desk context"])
        XCTAssertEqual(stores.focus.todayLog.filter { $0.kind == .note }.compactMap(\.noteText), ["desk context"])

        let reloaded = FocusSessionStore(
            usage: stores.usage,
            companion: stores.companion,
            clock: { clock.now },
            fileURL: stores.focusURL,
            ticksOnTimer: false)
        XCTAssertEqual(reloaded.history(forIssueID: "issue-1")?.notes, ["desk context"])
        XCTAssertEqual(reloaded.todayLog.filter { $0.kind == .note }.compactMap(\.noteText), ["desk context"])
    }

    func testFailedSessionNoteSurfacesErrorAndDoesNotPersist() async {
        let capture = CommentCapture()
        capture.result = false
        let stores = makeStores(postComment: capture.post)
        stores.focus.pin(issue(), openDesk: false)
        stores.focus.noteDraft = "nope"
        await stores.focus.postSessionNote()

        XCTAssertEqual(capture.posts.count, 1)
        XCTAssertTrue(stores.focus.notePostFailed)
        XCTAssertEqual(stores.focus.noteDraft, "nope")
        XCTAssertFalse(stores.focus.session?.checkInNotePosted ?? true)
        XCTAssertTrue(stores.focus.todayLog.filter { $0.kind == .note }.isEmpty)
    }

    func testIslandPanelGrowsWhenComposingNote() {
        let pet: CGFloat = 48
        let closed = FloatingPetController.panelSize(
            petSize: pet, showingBubble: false, hasIsland: true, prompt: .none, composingNote: false)
        let open = FloatingPetController.panelSize(
            petSize: pet, showingBubble: false, hasIsland: true, prompt: .none, composingNote: true)
        XCTAssertGreaterThan(open.height, closed.height)
        XCTAssertEqual(open.height - closed.height, FloatingPetController.noteComposerHeight)
        XCTAssertEqual(closed.height, FloatingPetController.islandHeight)
    }

    private func makeStores(
        clock: TimeOpenCompanionTestsClock? = nil,
        postComment: ((String, String) async -> Bool)? = nil
    ) -> (usage: UsageStore, companion: CompanionStore, focus: FocusSessionStore, focusURL: URL) {
        let now: () -> Date = {
            if let clock { return clock.now }
            return self.t0
        }
        let companion = CompanionStore(
            provider: StubProvider(value: EvoLine(
                baseID: 1,
                tree: EvoNode(speciesID: 1, children: []),
                rarity: .common,
                names: [:])),
            clock: now,
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("focus-xp-card-\(UUID().uuidString).json"),
            rng: SeededRNG(seed: 1))
        let usage = UsageStore(
            providers: [],
            autoRefresh: false,
            defaults: UserDefaults(suiteName: "focus-history-\(UUID().uuidString)")!)
        let focusURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("focus-state-card-\(UUID().uuidString).json")
        let focus = FocusSessionStore(
            usage: usage,
            companion: companion,
            clock: now,
            fileURL: focusURL,
            ticksOnTimer: false,
            postComment: postComment)
        return (usage, companion, focus, focusURL)
    }
}

/// Clock box local to this file so FocusSessionTests does not depend on TimeOpenCompanionTests internals.
private final class TimeOpenCompanionTestsClock: @unchecked Sendable {
    nonisolated(unsafe) var now: Date
    init(_ d: Date) { now = d }
}

private final class CommentCapture: @unchecked Sendable {
    var posts: [(issueID: String, body: String)] = []
    var result = true

    @MainActor
    func post(issueID: String, body: String) async -> Bool {
        posts.append((issueID, body))
        return result
    }
}
