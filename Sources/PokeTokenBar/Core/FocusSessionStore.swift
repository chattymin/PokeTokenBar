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
    private let postComment: ((String, String) async -> Bool)?
    private var timer: Timer?

    private(set) var session: FocusSession?
    private(set) var log: [FocusLogEntry] = []
    private(set) var logDay = ""
    private(set) var issueHistory: [FocusIssueHistory] = []
    private var sessionGrantedXP = 0
    private var sessionCheckIns: [FocusCheckInSummary] = []
    private var sessionNotes: [String] = []
    private(set) var isPostingNote = false
    private(set) var notePostFailed = false
    var isComposingNote = false
    var noteDraft = ""
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
    var onOpenComposer: (() -> Void)?
    private var isLoading = false
    private(set) var forfeitPrompt: FocusForfeitWarning?
    private(set) var resetPrompt = false
    private var pendingAfterForfeit: PendingAfterForfeit = .none
    private let createIssue: ((LinearIssueDraft) async -> LinearIssueSummary?)?

    private enum PendingAfterForfeit: Equatable {
        case none
        case idle
        case pin(LinearIssueSummary, openDesk: Bool)
        case createAndFocus(LinearIssueDraft)
    }

    init(
        usage: UsageStore,
        companion: CompanionStore,
        clock: @escaping () -> Date = Date.init,
        fileURL: URL? = nil,
        ticksOnTimer: Bool = true,
        postComment: ((String, String) async -> Bool)? = nil,
        createIssue: ((LinearIssueDraft) async -> LinearIssueSummary?)? = nil
    ) {
        self.usage = usage
        self.companion = companion
        self.clock = clock
        self.fileURL = fileURL ?? AppStatePaths.directory().appendingPathComponent("focus-session.json")
        self.ticksOnTimer = ticksOnTimer
        self.postComment = postComment
        self.createIssue = createIssue
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

    func openComposer() { onOpenComposer?() }

    var canResetClock: Bool {
        guard let session else { return false }
        return FocusTick.elapsedSeconds(session, now: clock()) > 0
    }

    var canAddRemainingTime: Bool {
        guard let session else { return false }
        return FocusTick.addRemaining(session, minutes: 5, now: clock()) != nil
    }

    func pin(_ issue: LinearIssueSummary, openDesk: Bool = true) {
        if let current = session, current.issue.id == issue.id {
            if openDesk { self.openDesk() }
            return
        }
        if session != nil {
            presentForfeit(pending: .pin(issue, openDesk: openDesk))
            return
        }
        start(issue)
        if openDesk { self.openDesk() }
    }

    func requestUnfocus() {
        guard session != nil else { return }
        presentForfeit(pending: .idle)
    }

    func cancelForfeit() {
        pendingAfterForfeit = .none
        forfeitPrompt = nil
    }

    func confirmForfeit() async {
        guard session != nil, forfeitPrompt != nil else { return }
        let pending = pendingAfterForfeit
        let resumeTimeOpen: Bool
        switch pending {
        case .pin, .createAndFocus: resumeTimeOpen = false
        case .none, .idle: resumeTimeOpen = true
        }
        applyForfeit(resumeTimeOpen: resumeTimeOpen)
        pendingAfterForfeit = .none
        switch pending {
        case .none, .idle:
            break
        case .pin(let issue, let openDesk):
            start(issue)
            if openDesk { self.openDesk() }
        case .createAndFocus(let draft):
            if let created = await performCreate(draft) {
                start(created)
                openDesk()
            }
        }
    }

    func createIssue(_ draft: LinearIssueDraft) async -> LinearIssueSummary? {
        await performCreate(draft)
    }

    func createAndFocus(_ draft: LinearIssueDraft) async {
        if session != nil {
            presentForfeit(pending: .createAndFocus(draft))
            return
        }
        guard let created = await performCreate(draft) else { return }
        start(created)
        openDesk()
    }

    func requestReset() {
        guard canResetClock else { return }
        resetPrompt = true
        forfeitPrompt = nil
        pendingAfterForfeit = .none
    }

    func cancelReset() {
        resetPrompt = false
    }

    func confirmReset() {
        guard let session else { return }
        resetPrompt = false
        guard let reset = FocusTick.resetClock(session, now: clock()) else { return }
        self.session = reset
        persist()
        syncTimer()
    }

    func addRemainingMinutes(_ minutes: Int) {
        guard let session else { return }
        guard let next = FocusTick.addRemaining(session, minutes: minutes, now: clock()) else { return }
        self.session = next
        persist()
        syncTimer()
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

    func history(forIssueID id: String) -> FocusIssueHistory? {
        issueHistory.first { $0.id == id }
    }

    func finishLeavingInProgress(resumeTimeOpen: Bool = true) {
        guard let session else { return }
        let xp = FocusTick.settleLeaveInProgress(session)
        grantSessionXP(xp)
        appendSessionLog(session)
        recordHistory(session, finish: .leftInProgress)
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
        let finish: FocusFinishKind
        let xp: Int
        if session.fiveXOpen, !session.enteredOvertime {
            finish = .doneOnTime
            xp = FocusTick.settleOnTimeDone(session)
        } else {
            finish = .doneOvertime
            xp = FocusTick.settleOvertimeDone(session)
        }
        grantSessionXP(xp)
        appendSessionLog(session)
        recordHistory(session, finish: finish)
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
            notePosted = await postLinearComment(issueID: session.issue.id, body: body)
            if notePosted {
                applySuccessfulNoteFlag()
                session = self.session ?? session
            }
        }
        if answer != .skip {
            appendCheckInLog(session.issue, answer: answer, notePosted: notePosted)
            sessionCheckIns.append(FocusCheckInSummary(
                answer: answer,
                notePosted: notePosted,
                note: FocusCheckInSummary.truncatedNote(trimmed)))
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

    func toggleNoteComposer() {
        guard session != nil else { return }
        isComposingNote.toggle()
        if !isComposingNote { notePostFailed = false }
    }

    func postSessionNote() async {
        guard let current = session, !isPostingNote else { return }
        let trimmed = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isPostingNote = true
        defer { isPostingNote = false }

        let body = FocusTick.sessionCommentBody(
            identifier: current.issue.identifier,
            elapsedSeconds: current.displayedSeconds(at: clock()),
            note: trimmed)
        let posted = await postLinearComment(issueID: current.issue.id, body: body)
        guard posted else {
            notePostFailed = true
            return
        }
        guard session != nil else { return }
        applySuccessfulNoteFlag()
        if let stored = FocusCheckInSummary.truncatedNote(trimmed) {
            sessionNotes.append(stored)
        }
        appendNoteLog(current.issue, text: trimmed)
        noteDraft = ""
        isComposingNote = false
        notePostFailed = false
        persist()
    }

    // MARK: - Internals

    private func presentForfeit(pending: PendingAfterForfeit) {
        guard let session else { return }
        resetPrompt = false
        pendingAfterForfeit = pending
        forfeitPrompt = FocusTick.forfeitWarning(for: session)
    }

    private func applyForfeit(resumeTimeOpen: Bool) {
        guard let session else { return }
        let result = FocusTick.unfocusForfeit(session)
        usage.announceForfeit(
            identifier: session.issue.identifier,
            leaveInProgressXP: result.warning.leaveInProgressXP)
        appendForfeitLog(session, leaveInProgressXP: result.warning.leaveInProgressXP)
        recordHistory(session, finish: .forfeited)
        forfeitPrompt = nil
        resetPrompt = false
        clearSession(resumeTimeOpen: resumeTimeOpen)
    }

    private func performCreate(_ draft: LinearIssueDraft) async -> LinearIssueSummary? {
        if let createIssue {
            return await createIssue(draft)
        }
        return await usage.createLinearIssue(draft)
    }

    private func postLinearComment(issueID: String, body: String) async -> Bool {
        if let postComment {
            return await postComment(issueID, body)
        }
        return await usage.createLinearComment(issueID: issueID, body: body)
    }

    private func applySuccessfulNoteFlag() {
        guard let session else { return }
        let marked = FocusTick.markNotePosted(session)
        self.session = marked.session
        grantSessionXP(marked.topUpXP)
    }

    private func start(_ issue: LinearIssueSummary) {
        let now = clock()
        companion.setTimeOpenXPSuspended(true)
        sessionGrantedXP = 0
        sessionCheckIns = []
        sessionNotes = []
        noteDraft = ""
        isComposingNote = false
        notePostFailed = false
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
        noteDraft = ""
        isComposingNote = false
        notePostFailed = false
        sessionGrantedXP = 0
        sessionCheckIns = []
        sessionNotes = []
        forfeitPrompt = nil
        resetPrompt = false
        pendingAfterForfeit = .none
        if resumeTimeOpen {
            companion.setTimeOpenXPSuspended(false, resumeFromNow: true)
        }
        persist()
        syncTimer()
    }

    private func grantSessionXP(_ delta: Int) {
        guard delta > 0, usage.timeOpenXPEnabled else { return }
        let granted = companion.applyCappedProgressXP(delta, today: todayKey())
        if granted > 0 { sessionGrantedXP += granted }
    }

    private func recordHistory(_ session: FocusSession, finish: FocusFinishKind) {
        let overtime = session.enteredOvertime
            ? max(0, session.accumulatedSeconds - session.plannedSeconds)
            : 0
        let entry = FocusIssueHistory(
            id: session.issue.id,
            identifier: session.issue.identifier,
            plannedSeconds: session.plannedSeconds,
            durationSeconds: session.accumulatedSeconds,
            overtimeSeconds: overtime,
            sessionXP: sessionGrantedXP,
            finish: finish,
            checkIns: sessionCheckIns,
            notes: sessionNotes.isEmpty ? nil : sessionNotes,
            finishedAt: clock())
        issueHistory.removeAll { $0.id == entry.id }
        issueHistory.insert(entry, at: 0)
        if issueHistory.count > FocusIssueHistory.maxStored {
            issueHistory = Array(issueHistory.prefix(FocusIssueHistory.maxStored))
        }
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

    private func appendNoteLog(_ issue: FocusPinnedIssue, text: String) {
        rolloverLogIfNeeded()
        log.insert(FocusLogEntry.note(day: todayKey(), issue: issue, text: text), at: 0)
    }

    private func appendForfeitLog(_ session: FocusSession, leaveInProgressXP: Int) {
        rolloverLogIfNeeded()
        log.insert(
            FocusLogEntry.forfeit(
                day: todayKey(),
                issue: session.issue,
                leaveInProgressXP: leaveInProgressXP),
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
        issueHistory = Array(saved.issueHistory.prefix(FocusIssueHistory.maxStored))
        sessionGrantedXP = max(0, saved.sessionGrantedXP)
        sessionCheckIns = saved.sessionCheckIns
        sessionNotes = saved.sessionNotes
        rolloverLogIfNeeded()
        if var restored = saved.session {
            restored = FocusTick.restoreAsPaused(restored)
            session = restored
            companion.setTimeOpenXPSuspended(true)
        } else {
            sessionGrantedXP = 0
            sessionCheckIns = []
            sessionNotes = []
        }
    }

    private func persist() {
        guard !isLoading else { return }
        let snapshot = FocusPersistedState(
            plannedMinutes: plannedMinutes,
            checkInMinutes: checkInMinutes,
            session: session,
            log: Array(log.prefix(200)),
            logDay: logDay.isEmpty ? todayKey() : logDay,
            sessionGrantedXP: sessionGrantedXP,
            sessionCheckIns: sessionCheckIns,
            sessionNotes: sessionNotes,
            issueHistory: Array(issueHistory.prefix(FocusIssueHistory.maxStored)))
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
