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
