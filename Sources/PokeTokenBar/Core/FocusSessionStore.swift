import AppKit
import Foundation
import Observation

/// Single source of truth for the pinned Linear timer, Today desk, overlay island, and session XP.
@MainActor
@Observable
final class FocusSessionStore {
    private let usage: UsageStore
    private let companion: CompanionStore
    private let clock: () -> Date
    private let fileURL: URL
    private let ticksOnTimer: Bool
    private var timer: Timer?

    private(set) var session: FocusSession?
    private(set) var log: [FocusLogEntry] = []
    private(set) var logDay = ""
    var plannedMinutes: Int {
        didSet {
            let clamped = SessionXP.clampMinutes(plannedMinutes)
            if clamped != plannedMinutes { plannedMinutes = clamped }
            persist()
        }
    }
    var checkInMinutes: Int {
        didSet {
            let clamped = SessionXP.clampMinutes(checkInMinutes)
            if clamped != checkInMinutes { checkInMinutes = clamped }
            persist()
        }
    }
    var checkInDraft = ""
    var onOpenDesk: (() -> Void)?
    private var isLoading = false

    init(
        usage: UsageStore,
        companion: CompanionStore,
        clock: @escaping () -> Date = Date.init,
        fileURL: URL? = nil,
        ticksOnTimer: Bool = true
    ) {
        self.usage = usage
        self.companion = companion
        self.clock = clock
        self.fileURL = fileURL ?? AppStatePaths.directory().appendingPathComponent("focus-session.json")
        self.ticksOnTimer = ticksOnTimer
        plannedMinutes = SessionXP.defaultPlannedMinutes
        checkInMinutes = SessionXP.defaultCheckInMinutes
        load()
    }

    var prompt: FocusPrompt {
        guard let session else { return .none }
        if session.phase == .awaitingChoice { return .zeroTime }
        if session.pendingCheckIn { return .checkIn }
        return .none
    }

    var isActive: Bool { session != nil }

    var todayDriftCount: Int {
        let day = todayKey()
        return log.filter { $0.day == day && $0.kind == .checkIn && $0.checkInAnswer == .no }.count
    }

    var todayLog: [FocusLogEntry] {
        let day = todayKey()
        return log.filter { $0.day == day }
    }

    func clockDisplay(at now: Date? = nil) -> (text: String, overtime: Bool) {
        return session?.clockDisplay(at: now ?? clock()) ?? (FocusClock.format(0), false)
    }

    func openDesk() { onOpenDesk?() }

    func pin(_ issue: LinearIssueSummary, openDesk: Bool = true) {
        if let current = session, current.issue.id == issue.id {
            if openDesk { self.openDesk() }
            return
        }
        if session != nil {
            finishLeavingInProgress(resumeTimeOpen: false)
        }
        start(issue)
        if openDesk { self.openDesk() }
    }

    func togglePause() {
        guard var session else { return }
        let now = clock()
        if session.userPaused || session.phase == .paused {
            session = FocusTick.resume(session, now: now)
        } else if session.phase == .running || session.phase == .overtime {
            session = FocusTick.pause(session, now: now)
        }
        self.session = session
        persist()
        syncTimer()
    }

    func setDisplayAwake(_ awake: Bool) {
        guard var session else { return }
        let now = clock()
        session = awake ? FocusTick.wake(session, now: now) : FocusTick.holdSleep(session, now: now)
        self.session = session
        persist()
        syncTimer()
    }

    func continueOvertime() {
        guard var session, session.phase == .awaitingChoice else { return }
        let result = FocusTick.continueOvertime(session, now: clock())
        session = result.session
        self.session = session
        grantSessionXP(result.xp)
        persist()
        syncTimer()
    }

    func finishLeavingInProgress(resumeTimeOpen: Bool = true) {
        guard let session else { return }
        let xp = FocusTick.settleLeaveInProgress(session)
        appendSessionLog(session)
        grantSessionXP(xp)
        clearSession(resumeTimeOpen: resumeTimeOpen)
    }

    func markIssueDone() async {
        guard let session else { return }
        let issue = usage.linearIssue(id: session.issue.id) ?? session.issue.summary
        guard let stateID = session.issue.completedStateId
                ?? issue.completedStateId
                ?? issue.teamStates.first(where: { $0.type.lowercased() == "completed" })?.id
        else { return }
        let completed = await usage.updateLinearIssueState(issue, stateID: stateID)
        if let completed {
            let outcome = companion.creditLinearCompletions([completed])
            usage.announceLinearCompletions(outcome.newlyCredited)
            handleLinearCompletion(completed)
        }
    }

    func handleLinearCompletion(_ completed: LinearCompletedIssue) {
        guard let session, session.issue.id == completed.id else { return }
        let xp: Int
        if session.fiveXOpen, !session.enteredOvertime {
            xp = FocusTick.settleOnTimeDone(session)
        } else {
            xp = FocusTick.settleOvertimeDone(session)
        }
        appendSessionLog(session)
        grantSessionXP(xp)
        clearSession(resumeTimeOpen: true)
    }

    func answerCheckIn(_ answer: CheckInAnswer) async {
        guard var session, session.pendingCheckIn else { return }
        let note = checkInDraft
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        var notePosted = false
        if answer != .skip, !trimmed.isEmpty {
            let body = FocusTick.checkInCommentBody(
                answer: answer,
                identifier: session.issue.identifier,
                elapsedSeconds: session.displayedSeconds(at: clock()),
                note: trimmed)
            notePosted = await usage.createLinearComment(issueID: session.issue.id, body: body)
            if notePosted {
                let marked = FocusTick.markNotePosted(session)
                session = marked.session
                grantSessionXP(marked.topUpXP)
            }
        }
        if answer != .skip {
            appendCheckInLog(session.issue, answer: answer, notePosted: notePosted)
        }
        session = FocusTick.answerCheckIn(session, now: clock())
        self.session = session
        checkInDraft = ""
        persist()
    }

    func tick(now: Date? = nil) {
        guard let session else { return }
        let result = FocusTick.apply(session, now: now ?? clock())
        self.session = result.session
        if result.sessionXP > 0 { grantSessionXP(result.sessionXP) }
        if result.hitZero {
            usage.announceTimesUp(result.session.issue.identifier)
        }
        persist()
        syncTimer()
    }

    // MARK: - Internals

    private func start(_ issue: LinearIssueSummary) {
        let now = clock()
        companion.setTimeOpenXPSuspended(true)
        session = FocusSession.start(
            issue: FocusPinnedIssue(issue),
            plannedMinutes: plannedMinutes,
            checkInMinutes: checkInMinutes,
            now: now)
        persist()
        syncTimer()
    }

    private func clearSession(resumeTimeOpen: Bool) {
        session = nil
        checkInDraft = ""
        if resumeTimeOpen {
            companion.setTimeOpenXPSuspended(false, resumeFromNow: true)
        }
        persist()
        syncTimer()
    }

    private func grantSessionXP(_ delta: Int) {
        guard delta > 0, usage.timeOpenXPEnabled else { return }
        _ = companion.applyCappedProgressXP(delta, today: todayKey())
    }

    private func appendSessionLog(_ session: FocusSession) {
        rolloverLogIfNeeded()
        let overtime = session.enteredOvertime
            ? max(0, session.accumulatedSeconds - session.plannedSeconds)
            : 0
        log.insert(
            FocusLogEntry.session(
                day: todayKey(),
                issue: session.issue,
                startedAt: session.startedAt,
                duration: session.accumulatedSeconds,
                overtime: overtime),
            at: 0)
    }

    private func appendCheckInLog(_ issue: FocusPinnedIssue, answer: CheckInAnswer, notePosted: Bool) {
        rolloverLogIfNeeded()
        log.insert(
            FocusLogEntry.checkIn(day: todayKey(), issue: issue, answer: answer, notePosted: notePosted),
            at: 0)
    }

    private func todayKey() -> String { LocalUsageReader.todayKey(clock()) }

    private func rolloverLogIfNeeded() {
        let day = todayKey()
        if logDay != day {
            log = log.filter { $0.day == day }
            logDay = day
        }
    }

    private func syncTimer() {
        let needs = ticksOnTimer && session != nil && (
            session?.isAccruing == true || session?.phase == .awaitingChoice
        )
        if needs {
            if timer == nil {
                let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.tick() }
                }
                t.tolerance = 0.2
                RunLoop.main.add(t, forMode: .common)
                timer = t
            }
        } else {
            timer?.invalidate()
            timer = nil
        }
    }

    private func load() {
        isLoading = true
        defer {
            isLoading = false
            persist()
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: fileURL),
              let saved = try? decoder.decode(FocusPersistedState.self, from: data)
        else { return }
        plannedMinutes = SessionXP.clampMinutes(saved.plannedMinutes)
        checkInMinutes = SessionXP.clampMinutes(saved.checkInMinutes)
        log = saved.log
        logDay = saved.logDay
        rolloverLogIfNeeded()
        if var restored = saved.session {
            restored = FocusTick.restoreAsPaused(restored)
            session = restored
            companion.setTimeOpenXPSuspended(true)
        }
    }

    private func persist() {
        guard !isLoading else { return }
        let snapshot = FocusPersistedState(
            plannedMinutes: plannedMinutes,
            checkInMinutes: checkInMinutes,
            session: session,
            log: Array(log.prefix(200)),
            logDay: logDay.isEmpty ? todayKey() : logDay)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

extension LaunchWindowPolicy {
    static let todayDeskIdentifier = "PokeTokenBar.TodayDesk"
    static let todayDeskAutosaveName = "PokeTokenBarTodayDesk"
}
