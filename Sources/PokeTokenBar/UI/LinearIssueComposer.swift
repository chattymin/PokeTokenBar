import AppKit
import SwiftUI

extension LaunchWindowPolicy {
    static let newLinearIssueIdentifier = "PokeTokenBar.NewLinearIssue"
    static let newLinearIssueAutosaveName = "PokeTokenBarNewLinearIssue"
}

/// Shared New issue window. Closing it does not affect a running session.
@MainActor
final class LinearIssueComposerController: NSObject, NSWindowDelegate {
    private let usage: UsageStore
    private let companion: CompanionStore
    private let session: FocusSessionStore
    private var window: NSWindow?

    init(usage: UsageStore, companion: CompanionStore, session: FocusSessionStore) {
        self.usage = usage
        self.companion = companion
        self.session = session
        super.init()
        session.onOpenComposer = { [weak self] in self?.open() }
    }

    func open() {
        guard usage.canComposeLinearIssue else { return }
        NSApp.activate(ignoringOtherApps: true)
        if window == nil {
            window = makeWindow()
        } else if window?.contentView == nil {
            window?.contentView = hostedView()
            window?.title = L(companion.language).newLinearIssue
        }
        window?.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }

    private func hostedView() -> NSView {
        NSHostingView(rootView:
            LinearIssueComposerView(onClose: { [weak self] in self?.close() })
                .environment(usage)
                .environment(companion)
                .environment(session)
                .environment(\.locale, companion.language.displayLocale)
        )
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)
        window.title = L(companion.language).newLinearIssue
        window.identifier = NSUserInterfaceItemIdentifier(LaunchWindowPolicy.newLinearIssueIdentifier)
        window.setFrameAutosaveName(LaunchWindowPolicy.newLinearIssueAutosaveName)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = hostedView()
        if window.frame.origin == .zero { window.center() }
        return window
    }

    func windowWillClose(_ notification: Notification) {
        window?.contentView = nil
        usage.clearLinearCreateError()
    }
}

@MainActor
struct LinearIssueComposerView: View {
    var onClose: () -> Void

    @Environment(UsageStore.self) private var store
    @Environment(CompanionStore.self) private var companion
    @Environment(FocusSessionStore.self) private var session

    @State private var title = ""
    @State private var description = ""
    @State private var teamID = ""
    @State private var projectID = ""
    @State private var assigneeID = ""
    @State private var stateID = ""
    @State private var selectedLabelIDs: Set<String> = []
    @State private var catalog: LinearCreateCatalog?
    @State private var waitingForForfeit = false
    @State private var pinnedIDAtSubmit: String?

    private var l: L { companion.l }
    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSubmit: Bool {
        !trimmedTitle.isEmpty && !teamID.isEmpty && !store.isCreatingLinearIssue
    }

    private var selectedTeam: LinearTeamCatalog? {
        catalog?.teams.first { $0.id == teamID }
    }

    private var teamProjects: [LinearProjectRef] {
        guard let catalog, !teamID.isEmpty else { return [] }
        return LinearClient.projects(in: catalog, forTeamID: teamID)
    }

    private var teamLabels: [LinearLabelSummary] {
        guard let catalog, !teamID.isEmpty else { return [] }
        return LinearClient.labels(in: catalog, forTeamID: teamID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(l.newLinearIssue)
                .font(.title2.weight(.semibold))

            labeled(l.linearIssueTitle) {
                TextField(l.linearIssueTitle, text: $title)
                    .textFieldStyle(.roundedBorder)
            }
            labeled(l.linearIssueDescription) {
                TextEditor(text: $description)
                    .font(.body)
                    .frame(minHeight: 88)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.3))
                    )
            }
            labeled(l.linearIssueTeam) {
                Picker(l.linearIssueTeam, selection: $teamID) {
                    ForEach(catalog?.teams ?? []) { team in
                        Text(teamKeyLabel(team)).tag(team.id)
                    }
                }
                .labelsHidden()
                .onChange(of: teamID) { _, _ in applyTeamDefaults() }
            }
            labeled(l.linearIssueProject) {
                Picker(l.linearIssueProject, selection: $projectID) {
                    Text(l.linearIssueNoProject).tag("")
                    ForEach(teamProjects) { project in
                        Text(project.name).tag(project.id)
                    }
                }
                .labelsHidden()
            }
            labeled(l.linearIssueAssignee) {
                Picker(l.linearIssueAssignee, selection: $assigneeID) {
                    Text(l.linearIssueUnassigned).tag("")
                    ForEach(catalog?.users ?? []) { user in
                        Text(assigneeLabel(user)).tag(user.id)
                    }
                }
                .labelsHidden()
            }
            labeled(l.linearIssueStatus) {
                Picker(l.linearIssueStatus, selection: $stateID) {
                    ForEach(selectedTeam?.states ?? []) { state in
                        Text(state.name).tag(state.id)
                    }
                }
                .labelsHidden()
            }
            labeled(l.linearIssueLabels) {
                LinearIssueLabelsMenu(
                    labels: teamLabels,
                    selectedIDs: $selectedLabelIDs,
                    catalogLoaded: catalog != nil)
            }

            if store.linearCreateError != nil {
                Text(l.linearCreateFailed)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if let warning = session.forfeitPrompt, waitingForForfeit {
                FocusForfeitWarningCard(warning: warning)
            }

            HStack {
                Spacer()
                Button(l.createLinearIssue) {
                    Task { await submit(focus: false) }
                }
                .disabled(!canSubmit)
                Button(l.createAndFocusLinearIssue) {
                    Task { await submit(focus: true) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSubmit)
            }
        }
        .padding(18)
        .frame(minWidth: 420, minHeight: 520)
        .task {
            let loaded = await store.fetchLinearCreateCatalog()
            catalog = loaded
            applyCatalogDefaults()
        }
        .onChange(of: session.forfeitPrompt) { old, new in
            guard waitingForForfeit, old != nil, new == nil else { return }
            waitingForForfeit = false
            if let current = session.session, current.issue.id != pinnedIDAtSubmit {
                onClose()
            }
        }
    }

    private func labeled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            content()
        }
    }

    private func draft() -> LinearIssueDraft {
        LinearIssueDraft(
            title: trimmedTitle,
            description: description,
            teamId: teamID,
            projectId: projectID.isEmpty ? nil : projectID,
            assigneeId: assigneeID.isEmpty ? nil : assigneeID,
            stateId: stateID.isEmpty ? nil : stateID,
            labelIds: Array(selectedLabelIDs).sorted())
    }

    private func submit(focus: Bool) async {
        store.clearLinearCreateError()
        let payload = draft()
        if focus {
            if session.isActive {
                waitingForForfeit = true
                pinnedIDAtSubmit = session.session?.issue.id
                await session.createAndFocus(payload)
                return
            }
            await session.createAndFocus(payload)
            if session.session != nil { onClose() }
            return
        }
        if await store.createLinearIssue(payload) != nil {
            onClose()
        }
    }

    private func applyCatalogDefaults() {
        guard let catalog else { return }
        if teamID.isEmpty {
            if !store.lastLinearTeamID.isEmpty,
               catalog.teams.contains(where: { $0.id == store.lastLinearTeamID })
            {
                teamID = store.lastLinearTeamID
            } else {
                teamID = catalog.teams.first?.id ?? ""
            }
        }
        if assigneeID.isEmpty {
            assigneeID = catalog.viewer?.id ?? ""
        }
        applyTeamDefaults()
    }

    private func applyTeamDefaults() {
        guard let team = selectedTeam else { return }
        if let def = LinearClient.defaultCreateState(for: team) {
            stateID = def.id
        } else {
            stateID = team.states.first?.id ?? ""
        }
        if !projectID.isEmpty, !teamProjects.contains(where: { $0.id == projectID }) {
            projectID = ""
        }
        let allowed = Set(teamLabels.map(\.id))
        selectedLabelIDs = selectedLabelIDs.filter { allowed.contains($0) }
    }

    private func teamKeyLabel(_ team: LinearTeamCatalog) -> String {
        if let key = team.key, !key.isEmpty { return "\(team.name) (\(key))" }
        return team.name
    }

    private func assigneeLabel(_ user: LinearUserSummary) -> String {
        if user.id == catalog?.viewer?.id {
            return "\(l.linearIssueAssigneeMe) · \(user.displayName ?? user.name)"
        }
        return user.displayName ?? user.name
    }
}

/// Multi-select labels control. Picker(.menu) is single-select; Menu + Toggle keeps checkmarks.
@MainActor
struct LinearIssueLabelsMenu: View {
    let labels: [LinearLabelSummary]
    @Binding var selectedIDs: Set<String>
    var catalogLoaded: Bool = true

    @Environment(CompanionStore.self) private var companion

    private var l: L { companion.l }
    private var title: String {
        if catalogLoaded, labels.isEmpty { return l.linearIssueNoLabels }
        return LinearIssueLabelMenuTitle.text(
            selectedIDs: selectedIDs,
            labels: labels,
            placeholder: l.linearIssueLabels,
            counted: l.linearIssueLabelsCount)
    }

    var body: some View {
        Menu {
            if labels.isEmpty {
                Text(l.linearIssueNoLabels)
            } else {
                ForEach(labels) { label in
                    Toggle(label.name, isOn: binding(label.id))
                }
            }
        } label: {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .menuIndicator(.visible)
        .frame(maxWidth: .infinity, alignment: .leading)
        .disabled(labels.isEmpty)
        .accessibilityLabel(l.linearIssueLabels)
        .accessibilityValue(title)
    }

    private func binding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { selectedIDs.contains(id) },
            set: { on in
                if on { selectedIDs.insert(id) } else { selectedIDs.remove(id) }
            }
        )
    }
}
