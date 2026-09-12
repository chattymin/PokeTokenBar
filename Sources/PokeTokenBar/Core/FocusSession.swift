import Foundation

/// Overlay/desk prompt. Zero-time wins if both would show.
enum FocusPrompt: Equatable {
    case none
    case zeroTime
    case checkIn
}

enum FocusPhase: String, Codable, Equatable {
    case running
    case paused
    case awaitingChoice
    case overtime
}

enum CheckInAnswer: String, Codable, Equatable {
    case yes, no, skip
}

/// Session XP on the time-open meter: +1M / 10 min, same daily cap.
enum SessionXP {
    static let intervalSeconds = TimeOpenXP.awardIntervalSeconds
    static let tokensPerAward = TimeOpenXP.tokensPerAward
    static let autoContinueDelay: TimeInterval = 30
    static let minMinutes = 5
    static let maxMinutes = 180
    static let defaultPlannedMinutes = 50
    static let defaultCheckInMinutes = 30
    static let plannedPresets = [25, 50, 90]
    static let checkInPresets = [30, 60]

    static func clampMinutes(_ minutes: Int) -> Int {
        return min(maxMinutes, max(minMinutes, minutes))
    }

    static func intervals(seconds: TimeInterval) -> Int {
        guard seconds >= intervalSeconds else { return 0 }
        return Int(seconds / intervalSeconds)
    }

    static func plannedXP(elapsed: TimeInterval, planned: TimeInterval, multiplier: Int) -> Int {
        return intervals(seconds: min(max(0, elapsed), planned)) * tokensPerAward * multiplier
    }

    static func overtimeXP(
        overtimeSeconds: TimeInterval,
        alreadyPaid: Int,
        paidMultiplier: Int,
        notePosted: Bool
    ) -> (xp: Int, paid: Int, multiplier: Int) {
        let intervals = Self.intervals(seconds: overtimeSeconds)
        let multiplier = notePosted ? 2 : 1
        var xp = 0
        if notePosted, paidMultiplier < 2, alreadyPaid > 0 {
            xp += alreadyPaid * tokensPerAward * (2 - paidMultiplier)
        }
        let unpaid = max(0, intervals - alreadyPaid)
        if unpaid > 0 {
            xp += unpaid * tokensPerAward * multiplier
        }
        return (xp, intervals, multiplier)
    }
}

enum FocusClock {
    static func format(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

struct FocusPinnedIssue: Codable, Equatable, Identifiable {
    var id: String
    var identifier: String
    var title: String
    var url: URL?
    var stateId: String?
    var stateName: String?
    var completedStateId: String?
    var teamStates: [LinearWorkflowState]

    init(_ issue: LinearIssueSummary) {
        id = issue.id
        identifier = issue.identifier
        title = issue.title
        url = issue.issueURL
        stateId = issue.stateId
        stateName = issue.stateName
        completedStateId = issue.completedStateId
            ?? issue.teamStates.first { $0.type.lowercased() == "completed" }?.id
        teamStates = issue.teamStates
    }

    var summary: LinearIssueSummary {
        LinearIssueSummary(
            id: id,
            identifier: identifier,
            title: title,
            issueURL: url,
            priority: nil,
            estimate: nil,
            stateId: stateId,
            stateName: stateName,
            stateType: teamStates.first(where: { $0.id == stateId })?.type,
            assigneeName: nil,
            assigneeEmail: nil,
            projectName: nil,
            teamName: nil,
            teamKey: nil,
            teamID: nil,
            teamStates: teamStates,
            completedStateId: completedStateId,
            labelNames: [],
            createdAt: nil,
            updatedAt: nil,
            dueDate: nil,
            completedAt: nil,
            descriptionText: nil)
    }
}

struct FocusSession: Codable, Equatable {
    var issue: FocusPinnedIssue
    var phase: FocusPhase
    var plannedSeconds: TimeInterval
    var startedAt: Date
    var accumulatedSeconds: TimeInterval
    var segmentStartedAt: Date?
    var userPaused: Bool
    var sleepHeld: Bool
    var enteredOvertime: Bool
    var fiveXOpen: Bool
    var plannedXPSettled: Bool
    var checkInNotePosted: Bool
    var checkInIntervalSeconds: TimeInterval
    var checkInAccumulatedSeconds: TimeInterval
    var pendingCheckIn: Bool
    var checkInDeferred: Bool
    var awaitingChoiceSince: Date?
    var overtimeIntervalsPaid: Int
    var overtimePaidMultiplier: Int

    var isAccruing: Bool {
        !userPaused && !sleepHeld && (phase == .running || phase == .overtime)
    }

    static func start(
        issue: FocusPinnedIssue,
        plannedMinutes: Int,
        checkInMinutes: Int,
        now: Date
    ) -> FocusSession {
        return FocusSession(
            issue: issue,
            phase: .running,
            plannedSeconds: TimeInterval(SessionXP.clampMinutes(plannedMinutes) * 60),
            startedAt: now,
            accumulatedSeconds: 0,
            segmentStartedAt: now,
            userPaused: false,
            sleepHeld: false,
            enteredOvertime: false,
            fiveXOpen: true,
            plannedXPSettled: false,
            checkInNotePosted: false,
            checkInIntervalSeconds: TimeInterval(SessionXP.clampMinutes(checkInMinutes) * 60),
            checkInAccumulatedSeconds: 0,
            pendingCheckIn: false,
            checkInDeferred: false,
            awaitingChoiceSince: nil,
            overtimeIntervalsPaid: 0,
            overtimePaidMultiplier: 1)
    }

    func displayedSeconds(at now: Date) -> TimeInterval {
        var t = accumulatedSeconds
        if let start = segmentStartedAt, isAccruing {
            t += now.timeIntervalSince(start)
        }
        if phase == .awaitingChoice { return plannedSeconds }
        return t
    }

    func clockDisplay(at now: Date) -> (text: String, overtime: Bool) {
        if phase == .awaitingChoice {
            return (FocusClock.format(0), false)
        }
        let elapsed = displayedSeconds(at: now)
        if phase == .overtime || elapsed > plannedSeconds {
            return (FocusClock.format(elapsed), true)
        }
        return (FocusClock.format(plannedSeconds - elapsed), false)
    }
}

struct FocusTickResult: Equatable {
    var session: FocusSession
    var sessionXP: Int
    var hitZero: Bool
    var autoContinued: Bool
    var checkInBecameDue: Bool
}

enum FocusTick {
    static func apply(_ session: FocusSession, now: Date) -> FocusTickResult {
        var s = session
        var xp = 0
        var hitZero = false
        var autoContinued = false
        var checkInBecameDue = false

        if let start = s.segmentStartedAt, s.isAccruing {
            let delta = now.timeIntervalSince(start)
            if delta > 0 {
                s.accumulatedSeconds += delta
                s.checkInAccumulatedSeconds += delta
                s.segmentStartedAt = now
            }
        }

        if s.phase == .running, s.accumulatedSeconds >= s.plannedSeconds {
            s.accumulatedSeconds = s.plannedSeconds
            s.phase = .awaitingChoice
            s.awaitingChoiceSince = now
            s.segmentStartedAt = nil
            hitZero = true
            if s.pendingCheckIn || s.checkInAccumulatedSeconds >= s.checkInIntervalSeconds {
                s.checkInDeferred = true
                s.pendingCheckIn = false
                s.checkInAccumulatedSeconds = 0
            }
        }

        if s.phase == .awaitingChoice,
           let since = s.awaitingChoiceSince,
           now.timeIntervalSince(since) >= SessionXP.autoContinueDelay {
            let settled = settlePlanned(&s, multiplier: 1)
            xp += settled
            applyContinue(&s, now: now)
            autoContinued = true
        }

        if s.phase == .overtime {
            let ot = max(0, s.accumulatedSeconds - s.plannedSeconds)
            let grant = SessionXP.overtimeXP(
                overtimeSeconds: ot,
                alreadyPaid: s.overtimeIntervalsPaid,
                paidMultiplier: s.overtimePaidMultiplier,
                notePosted: s.checkInNotePosted)
            xp += grant.xp
            s.overtimeIntervalsPaid = grant.paid
            s.overtimePaidMultiplier = grant.multiplier
        }

        if s.phase != .awaitingChoice, !s.pendingCheckIn,
           s.checkInAccumulatedSeconds >= s.checkInIntervalSeconds {
            s.pendingCheckIn = true
            s.checkInAccumulatedSeconds = 0
            checkInBecameDue = true
        }

        if hitZero, checkInBecameDue || s.pendingCheckIn {
            s.checkInDeferred = true
            s.pendingCheckIn = false
            checkInBecameDue = false
        }

        if autoContinued, s.checkInDeferred {
            s.checkInDeferred = false
            s.pendingCheckIn = true
            checkInBecameDue = true
        }

        return FocusTickResult(
            session: s,
            sessionXP: xp,
            hitZero: hitZero,
            autoContinued: autoContinued,
            checkInBecameDue: checkInBecameDue)
    }

    static func pause(_ session: FocusSession, now: Date) -> FocusSession {
        var s = freeze(session, now: now)
        s.userPaused = true
        if s.phase == .running || s.phase == .overtime {
            s.phase = .paused
        }
        return s
    }

    static func resume(_ session: FocusSession, now: Date) -> FocusSession {
        var s = session
        s.userPaused = false
        if s.phase == .paused {
            s.phase = s.enteredOvertime ? .overtime : .running
        }
        if s.isAccruing { s.segmentStartedAt = now }
        return s
    }

    static func holdSleep(_ session: FocusSession, now: Date) -> FocusSession {
        var s = freeze(session, now: now)
        s.sleepHeld = true
        return s
    }

    static func wake(_ session: FocusSession, now: Date) -> FocusSession {
        var s = session
        s.sleepHeld = false
        if s.isAccruing { s.segmentStartedAt = now }
        return s
    }

    static func continueOvertime(_ session: FocusSession, now: Date) -> (session: FocusSession, xp: Int) {
        var s = session
        let xp = settlePlanned(&s, multiplier: 1)
        applyContinue(&s, now: now)
        return (s, xp)
    }

    static func settleLeaveInProgress(_ session: FocusSession) -> Int {
        var s = session
        var xp = settlePlanned(&s, multiplier: 1)
        if s.enteredOvertime {
            let ot = max(0, s.accumulatedSeconds - s.plannedSeconds)
            let grant = SessionXP.overtimeXP(
                overtimeSeconds: ot,
                alreadyPaid: s.overtimeIntervalsPaid,
                paidMultiplier: s.overtimePaidMultiplier,
                notePosted: s.checkInNotePosted)
            xp += grant.xp
        }
        return xp
    }

    static func settleOnTimeDone(_ session: FocusSession) -> Int {
        return SessionXP.plannedXP(
            elapsed: session.accumulatedSeconds,
            planned: session.plannedSeconds,
            multiplier: 5)
    }

    static func settleOvertimeDone(_ session: FocusSession) -> Int {
        return settleLeaveInProgress(session)
    }

    static func restoreAsPaused(_ session: FocusSession) -> FocusSession {
        var s = session
        s.userPaused = true
        s.sleepHeld = false
        s.segmentStartedAt = nil
        if s.phase == .awaitingChoice {
            s.awaitingChoiceSince = nil
        } else if s.phase == .running || s.phase == .overtime {
            s.phase = .paused
        }
        return s
    }

    static func markNotePosted(_ session: FocusSession) -> (session: FocusSession, topUpXP: Int) {
        var s = session
        s.checkInNotePosted = true
        guard s.enteredOvertime else { return (s, 0) }
        let ot = max(0, s.accumulatedSeconds - s.plannedSeconds)
        let grant = SessionXP.overtimeXP(
            overtimeSeconds: ot,
            alreadyPaid: s.overtimeIntervalsPaid,
            paidMultiplier: s.overtimePaidMultiplier,
            notePosted: true)
        s.overtimeIntervalsPaid = grant.paid
        s.overtimePaidMultiplier = grant.multiplier
        return (s, grant.xp)
    }

    static func answerCheckIn(_ session: FocusSession, now: Date) -> FocusSession {
        var s = session
        s.pendingCheckIn = false
        s.checkInAccumulatedSeconds = 0
        return s
    }

    static func checkInCommentBody(
        answer: CheckInAnswer,
        identifier: String,
        elapsedSeconds: TimeInterval,
        note: String
    ) -> String {
        let minutes = max(0, Int(elapsedSeconds / 60))
        let word = answer == .yes ? "Yes" : "No"
        var body = "Check-in · \(word) · \(identifier) · \(minutes)m"
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            body += "\n\(trimmed)"
        }
        return body
    }

    /// Context note posted from the overlay/desk without a check-in answer.
    static func sessionCommentBody(
        identifier: String,
        elapsedSeconds: TimeInterval,
        note: String
    ) -> String {
        let minutes = max(0, Int(elapsedSeconds / 60))
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return "Note · \(identifier) · \(minutes)m\n\(trimmed)"
    }

    private static func freeze(_ session: FocusSession, now: Date) -> FocusSession {
        var s = session
        if let start = s.segmentStartedAt, s.isAccruing {
            let delta = now.timeIntervalSince(start)
            if delta > 0 {
                s.accumulatedSeconds += delta
                s.checkInAccumulatedSeconds += delta
            }
        }
        s.segmentStartedAt = nil
        return s
    }

    private static func settlePlanned(_ session: inout FocusSession, multiplier: Int) -> Int {
        guard !session.plannedXPSettled else { return 0 }
        session.plannedXPSettled = true
        session.fiveXOpen = false
        return SessionXP.plannedXP(
            elapsed: session.accumulatedSeconds,
            planned: session.plannedSeconds,
            multiplier: multiplier)
    }

    private static func applyContinue(_ session: inout FocusSession, now: Date) {
        session.phase = .overtime
        session.enteredOvertime = true
        session.fiveXOpen = false
        session.awaitingChoiceSince = nil
        session.userPaused = false
        if session.checkInDeferred {
            session.pendingCheckIn = true
            session.checkInDeferred = false
        }
        if session.isAccruing { session.segmentStartedAt = now }
    }
}

struct FocusLogEntry: Codable, Equatable, Identifiable {
    var id: UUID
    var day: String
    var kind: Kind
    var issueIdentifier: String
    var issueTitle: String
    var startedAt: Date?
    var durationSeconds: TimeInterval?
    var overtimeSeconds: TimeInterval?
    var checkInAnswer: CheckInAnswer?
    var notePosted: Bool
    var noteText: String? = nil

    enum Kind: String, Codable { case session, checkIn, note }

    static func session(
        day: String,
        issue: FocusPinnedIssue,
        startedAt: Date,
        duration: TimeInterval,
        overtime: TimeInterval
    ) -> FocusLogEntry {
        FocusLogEntry(
            id: UUID(),
            day: day,
            kind: .session,
            issueIdentifier: issue.identifier,
            issueTitle: issue.title,
            startedAt: startedAt,
            durationSeconds: duration,
            overtimeSeconds: overtime,
            checkInAnswer: nil,
            notePosted: false)
    }

    static func checkIn(
        day: String,
        issue: FocusPinnedIssue,
        answer: CheckInAnswer,
        notePosted: Bool
    ) -> FocusLogEntry {
        FocusLogEntry(
            id: UUID(),
            day: day,
            kind: .checkIn,
            issueIdentifier: issue.identifier,
            issueTitle: issue.title,
            startedAt: nil,
            durationSeconds: nil,
            overtimeSeconds: nil,
            checkInAnswer: answer,
            notePosted: notePosted)
    }

    static func note(
        day: String,
        issue: FocusPinnedIssue,
        text: String
    ) -> FocusLogEntry {
        FocusLogEntry(
            id: UUID(),
            day: day,
            kind: .note,
            issueIdentifier: issue.identifier,
            issueTitle: issue.title,
            startedAt: nil,
            durationSeconds: nil,
            overtimeSeconds: nil,
            checkInAnswer: nil,
            notePosted: true,
            noteText: FocusCheckInSummary.truncatedNote(text))
    }
}

/// How a focus session ended. Continue is not a finish — overtime then Done is `doneOvertime`.
enum FocusFinishKind: String, Codable, Equatable {
    case doneOnTime
    case doneOvertime
    case leftInProgress
}

struct FocusCheckInSummary: Codable, Equatable {
    var answer: CheckInAnswer
    var notePosted: Bool
    var note: String?

    static let maxNoteChars = 280

    static func truncatedNote(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.count <= maxNoteChars { return trimmed }
        return String(trimmed.prefix(maxNoteChars))
    }
}

/// Compact per-issue timer summary for completed Linear cards. Survives session clear and day rollover.
struct FocusIssueHistory: Codable, Equatable, Identifiable {
    static let maxStored = 200

    var id: String
    var identifier: String
    var plannedSeconds: TimeInterval
    var durationSeconds: TimeInterval
    var overtimeSeconds: TimeInterval
    var sessionXP: Int
    var finish: FocusFinishKind
    var checkIns: [FocusCheckInSummary]
    var notes: [String]? = nil
    var finishedAt: Date
}

struct FocusPersistedState: Equatable, Codable {
    var plannedMinutes: Int
    var checkInMinutes: Int
    var session: FocusSession?
    var log: [FocusLogEntry]
    var logDay: String
    var sessionGrantedXP: Int
    var sessionCheckIns: [FocusCheckInSummary]
    var sessionNotes: [String]
    var issueHistory: [FocusIssueHistory]

    enum CodingKeys: String, CodingKey {
        case plannedMinutes, checkInMinutes, session, log, logDay
        case sessionGrantedXP, sessionCheckIns, sessionNotes, issueHistory
    }

    init(
        plannedMinutes: Int,
        checkInMinutes: Int,
        session: FocusSession?,
        log: [FocusLogEntry],
        logDay: String,
        sessionGrantedXP: Int = 0,
        sessionCheckIns: [FocusCheckInSummary] = [],
        sessionNotes: [String] = [],
        issueHistory: [FocusIssueHistory] = []
    ) {
        self.plannedMinutes = plannedMinutes
        self.checkInMinutes = checkInMinutes
        self.session = session
        self.log = log
        self.logDay = logDay
        self.sessionGrantedXP = sessionGrantedXP
        self.sessionCheckIns = sessionCheckIns
        self.sessionNotes = sessionNotes
        self.issueHistory = issueHistory
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        plannedMinutes = try c.decode(Int.self, forKey: .plannedMinutes)
        checkInMinutes = try c.decode(Int.self, forKey: .checkInMinutes)
        session = try c.decodeIfPresent(FocusSession.self, forKey: .session)
        log = try c.decodeIfPresent([FocusLogEntry].self, forKey: .log) ?? []
        logDay = try c.decodeIfPresent(String.self, forKey: .logDay) ?? ""
        sessionGrantedXP = try c.decodeIfPresent(Int.self, forKey: .sessionGrantedXP) ?? 0
        sessionCheckIns = try c.decodeIfPresent([FocusCheckInSummary].self, forKey: .sessionCheckIns) ?? []
        sessionNotes = try c.decodeIfPresent([String].self, forKey: .sessionNotes) ?? []
        issueHistory = try c.decodeIfPresent([FocusIssueHistory].self, forKey: .issueHistory) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(plannedMinutes, forKey: .plannedMinutes)
        try c.encode(checkInMinutes, forKey: .checkInMinutes)
        try c.encodeIfPresent(session, forKey: .session)
        try c.encode(log, forKey: .log)
        try c.encode(logDay, forKey: .logDay)
        try c.encode(sessionGrantedXP, forKey: .sessionGrantedXP)
        try c.encode(sessionCheckIns, forKey: .sessionCheckIns)
        try c.encode(sessionNotes, forKey: .sessionNotes)
        try c.encode(issueHistory, forKey: .issueHistory)
    }
}
