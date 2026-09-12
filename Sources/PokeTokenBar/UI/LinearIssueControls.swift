import AppKit
import SwiftUI

/// Status menu shared by the Linear tab, overlay island, and Today desk.
@MainActor
struct LinearIssueStatusPicker: View {
    let issue: LinearIssueSummary
    var compact: Bool = true

    @Environment(UsageStore.self) private var store
    @Environment(CompanionStore.self) private var companion
    @Environment(FocusSessionStore.self) private var session

    private var l: L { L(store.localizationLanguage) }

    var body: some View {
        let busy = store.updatingLinearIssueID == issue.id
        let states = issue.teamStates
        let selectedID = issue.stateId
            ?? states.first(where: { $0.name == issue.stateName })?.id
            ?? ""
        Picker("", selection: Binding(
            get: { selectedID },
            set: { newID in
                guard let state = states.first(where: { $0.id == newID }) else { return }
                Task { await changeStatus(to: state) }
            }
        )) {
            if states.isEmpty {
                Text(issue.stateName ?? l.linearStatusUnknown).tag(selectedID)
            }
            ForEach(states) { state in
                Text(state.name).tag(state.id)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .controlSize(compact ? .mini : .small)
        .fixedSize()
        .disabled(states.isEmpty || store.updatingLinearIssueID != nil)
        .opacity(busy ? 0.45 : 1)
        .overlay {
            if busy { ProgressView().controlSize(.mini) }
        }
        .help(states.isEmpty ? l.linearStatusUnavailable : l.linearStatusHelp)
    }

    private func changeStatus(to state: LinearWorkflowState) async {
        let currentID = issue.stateId
            ?? issue.teamStates.first(where: { $0.name == issue.stateName })?.id
        guard state.id != currentID else { return }
        let completed = await store.updateLinearIssueState(issue, stateID: state.id)
        if let completed {
            let outcome = companion.creditLinearCompletions([completed])
            store.announceLinearCompletions(outcome.newlyCredited)
            session.handleLinearCompletion(completed)
        }
    }
}

@MainActor
struct LinearIssueIDButton: View {
    let identifier: String
    var url: URL?
    var style: Font = .caption.weight(.semibold)

    /// Help uses the companion language; English fallback is never shown as a Hangul literal.
    @Environment(CompanionStore.self) private var companion

    var body: some View {
        Button {
            if let url { NSWorkspace.shared.open(url) }
        } label: {
            Text(identifier)
                .font(style)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Color.accentColor.opacity(0.15))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(url == nil)
        .help(companion.l.linearOpenIssue)
    }
}

/// Rewards and timer summary on a completed Linear issue card. Omits anything we did not persist.
@MainActor
struct LinearIssueCompletionStats: View {
    let issue: LinearIssueSummary

    @Environment(CompanionStore.self) private var companion
    @Environment(FocusSessionStore.self) private var session

    private var l: L { companion.l }
    private var isCompleted: Bool {
        issue.completedAt != nil || (issue.stateType ?? "").lowercased() == "completed"
    }

    var body: some View {
        let xp = isCompleted ? companion.linearIssueXP(id: issue.id) : nil
        let history = isCompleted ? session.history(forIssueID: issue.id) : nil
        if isCompleted, xp != nil || history != nil {
            VStack(alignment: .leading, spacing: 2) {
                xpRow(xp, history: history)
                if let history {
                        timerRow(history)
                        finishRow(history.finish)
                        checkInRows(history.checkIns)
                        noteRows(history.notes ?? [])
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func xpRow(_ xp: LinearIssueXPRecord?, history: FocusIssueHistory?) -> some View {
        HStack(spacing: 8) {
            if let xp, xp.xp > 0 {
                Text(l.linearCompletionXPAmount(TokenFormatter.compact(xp.xp)))
            }
            if let history, history.sessionXP > 0 {
                Text(l.sessionXPAmount(TokenFormatter.compact(history.sessionXP)))
            }
        }
    }

    @ViewBuilder
    private func timerRow(_ history: FocusIssueHistory) -> some View {
        let plannedMinutes = max(0, Int((history.plannedSeconds / 60).rounded(.down)))
        HStack(spacing: 8) {
            Text(l.plannedDurationLine(l.minutesValue(plannedMinutes)))
            Text(FocusClock.format(history.durationSeconds))
                .monospacedDigit()
            if history.overtimeSeconds > 0 {
                Text(l.overtimeDurationLine(FocusClock.format(history.overtimeSeconds)))
                    .monospacedDigit()
            }
        }
    }

    @ViewBuilder
    private func finishRow(_ finish: FocusFinishKind) -> some View {
        switch finish {
        case .doneOnTime:
            Text(l.focusFinishedOnTime)
        case .doneOvertime:
            Text(l.focusFinishedOvertime)
        case .leftInProgress:
            Text(l.focusFinishedLeftInProgress)
        }
    }

    @ViewBuilder
    private func checkInRows(_ checkIns: [FocusCheckInSummary]) -> some View {
        ForEach(Array(checkIns.enumerated()), id: \.offset) { _, checkIn in
            VStack(alignment: .leading, spacing: 1) {
                Text(l.focusCheckInLine(answer: checkInAnswerLabel(checkIn.answer), notePosted: checkIn.notePosted))
                if let note = checkIn.note, !note.isEmpty {
                    Text(note)
                        .lineLimit(2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func checkInAnswerLabel(_ answer: CheckInAnswer) -> String {
        switch answer {
        case .yes: return l.checkInYes
        case .no: return l.checkInNo
        case .skip: return l.checkInSkip
        }
    }

    @ViewBuilder
    private func noteRows(_ notes: [String]) -> some View {
        ForEach(Array(notes.enumerated()), id: \.offset) { _, note in
            Text(note)
                .lineLimit(2)
                .foregroundStyle(.tertiary)
        }
    }
}

@MainActor
struct LinearFocusButton: View {
    let issue: LinearIssueSummary
    var compact: Bool = true

    @Environment(FocusSessionStore.self) private var session
    @Environment(CompanionStore.self) private var companion

    private var l: L { companion.l }
    private var isPinned: Bool { session.session?.issue.id == issue.id }

    var body: some View {
        Button {
            session.pin(issue)
        } label: {
            Text(isPinned ? l.focusingNow : l.focusAction)
        }
        .buttonStyle(.bordered)
        .controlSize(compact ? .mini : .small)
        .tint(isPinned ? .accentColor : .secondary)
    }
}
