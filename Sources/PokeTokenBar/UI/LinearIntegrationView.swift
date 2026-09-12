import AppKit
import SwiftUI

/// Closest SF Symbols to Linear’s chrome (issue circle / project hexagon / initiative flag).
private enum LinearChromeSymbol {
    static let issue = "circle"
    static let project = "hexagon"
    static let initiative = "flag"
}

@MainActor
private enum LinearRootTab: Hashable {
    case issues
    case projects
    case initiatives

    var symbol: String {
        switch self {
        case .issues: return LinearChromeSymbol.issue
        case .projects: return LinearChromeSymbol.project
        case .initiatives: return LinearChromeSymbol.initiative
        }
    }
}

@MainActor
private enum LinearIssuesTab: Hashable {
    case inProgress
    case completedToday
}

@MainActor
private enum LinearProjectsTab: Hashable {
    case inProgress
    case production
}

@MainActor
private enum LinearInitiativesTab: Hashable {
    case active
    case planned
}

@MainActor
struct LinearIntegrationView: View {
    let store: UsageStore
    @Environment(CompanionStore.self) private var companion
    @Environment(FocusSessionStore.self) private var session
    @State private var selectedRoot: LinearRootTab = .issues
    @State private var selectedIssuesTab: LinearIssuesTab = .inProgress
    @State private var selectedProjectsTab: LinearProjectsTab = .inProgress
    @State private var selectedInitiativesTab: LinearInitiativesTab = .active

    private var l: L { companion.l }

    private var visibleIssues: [LinearIssueSummary] {
        switch selectedIssuesTab {
        case .completedToday: return store.linearCompletedTodayIssues
        case .inProgress: return store.linearInProgressIssues
        }
    }

    private var visibleProjects: [LinearProjectSummary] {
        store.linearProjects.filter { project in
            switch selectedProjectsTab {
            case .inProgress:
                return LinearClient.matchesProjectInProgressTab(
                    name: project.statusName, type: project.statusType)
            case .production:
                return LinearClient.matchesProjectProduction(
                    name: project.statusName, type: project.statusType)
            }
        }
    }

    private var visibleInitiatives: [LinearInitiativeSummary] {
        store.linearInitiatives.filter { initiative in
            switch selectedInitiativesTab {
            case .active:
                return LinearClient.matchesInitiativeActive(name: initiative.statusName)
            case .planned:
                return LinearClient.matchesInitiativePlanned(name: initiative.statusName)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: selectedRoot.symbol)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                    .accessibilityHidden(true)
                Picker("", selection: $selectedRoot) {
                    Text(l.linearIssuesTab).tag(LinearRootTab.issues)
                    Text(l.linearProjectsTab).tag(LinearRootTab.projects)
                    Text(l.linearInitiativesTab).tag(LinearRootTab.initiatives)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Spacer()
                Button {
                    session.openDesk()
                } label: {
                    Image(systemName: "calendar")
                }
                .buttonStyle(.borderless)
                .help(l.todayDeskMenuOpen)
                Button {
                    Task { _ = await store.refreshLinearIssues() }
                } label: {
                    if store.isRefreshingLinearIssues {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(.borderless)
                .help(l.refreshNow)
                .disabled(!store.linearIntegrationEnabled || !store.linearAPIKeyConfigured || store.isRefreshingLinearIssues)
            }

            if !store.linearIntegrationEnabled || !store.linearAPIKeyConfigured {
                Text(l.linearIssuesNeedsSetup)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                if selectedRoot == .issues {
                    Picker("", selection: $selectedIssuesTab) {
                        Text(l.linearInProgressTab).tag(LinearIssuesTab.inProgress)
                        Text(l.linearCompletedTodayTab).tag(LinearIssuesTab.completedToday)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                } else if selectedRoot == .projects {
                    Picker("", selection: $selectedProjectsTab) {
                        Text(l.linearInProgressTab).tag(LinearProjectsTab.inProgress)
                        Text(l.linearProductionTab).tag(LinearProjectsTab.production)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                } else if selectedRoot == .initiatives {
                    Picker("", selection: $selectedInitiativesTab) {
                        Text(l.linearActiveTab).tag(LinearInitiativesTab.active)
                        Text(l.linearPlannedTab).tag(LinearInitiativesTab.planned)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                if let updated = store.linearIssuesUpdatedAt {
                    HStack(spacing: 4) {
                        Text(l.linearLastSynced)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(updated, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                if store.linearIssuesError != nil {
                    Text(l.linearIssuesSyncFailed)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }

                switch selectedRoot {
                case .issues:
                    issuesList
                case .projects:
                    containerList(
                        items: visibleProjects.map { LinearContainerRow(project: $0) },
                        emptyText: selectedProjectsTab == .production
                            ? l.linearProjectsEmptyProduction
                            : l.linearProjectsEmpty,
                        openHelp: l.linearOpenProject)
                case .initiatives:
                    containerList(
                        items: visibleInitiatives.map { LinearContainerRow(initiative: $0) },
                        emptyText: selectedInitiativesTab == .planned
                            ? l.linearInitiativesEmptyPlanned
                            : l.linearInitiativesEmpty,
                        openHelp: l.linearOpenInitiative)
                }
            }
        }
        .frame(height: 520)
        .task(id: store.linearIntegrationEnabled && store.linearAPIKeyConfigured) {
            guard store.linearIntegrationEnabled, store.linearAPIKeyConfigured else { return }
            _ = await store.refreshLinearIssues()
        }
    }

    @ViewBuilder
    private var issuesList: some View {
        if visibleIssues.isEmpty {
            Text(selectedIssuesTab == .completedToday ? l.linearIssuesEmptyCompleted : l.linearIssuesEmptyInProgress)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, 4)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(visibleIssues) { issue in
                        issueCard(issue)
                    }
                }
            }
        }
    }

    private func containerList(
        items: [LinearContainerRow],
        emptyText: String,
        openHelp: String
    ) -> some View {
        Group {
            if items.isEmpty {
                Text(emptyText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.top, 4)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(items) { row in
                            LinearFoldableRow(row: row, openHelp: openHelp) {
                                if row.issues.isEmpty {
                                    Text(l.linearContainerEmptyIssues)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .padding(.vertical, 4)
                                } else {
                                    VStack(alignment: .leading, spacing: 8) {
                                        ForEach(row.issues) { issue in
                                            issueCard(issue)
                                        }
                                    }
                                    .padding(.top, 6)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func issueCard(_ issue: LinearIssueSummary) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: LinearChromeSymbol.issue)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(issue.identifier)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                priorityBadge(issue.priority)
                Spacer(minLength: 4)
                LinearIssueStatusPicker(issue: issue)
                LinearFocusButton(issue: issue)
                if let url = issue.issueURL {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Image(systemName: "arrow.up.right.square")
                            .font(.caption2)
                    }
                    .buttonStyle(.borderless)
                    .help(l.linearOpenIssue)
                }
            }

            Text(issue.title)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.primary)

            if let text = issue.descriptionText, !text.isEmpty {
                Text(text)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            metadataRow(issue)
            LinearIssueCompletionStats(issue: issue)
        }
        .padding(8)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func metadataRow(_ issue: LinearIssueSummary) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                if let assignee = issue.assigneeName {
                    metadataChip(Image(systemName: "person.fill"), assignee)
                }
                if let email = issue.assigneeEmail {
                    metadataChip(Image(systemName: "envelope"), email)
                }
            }
            HStack(spacing: 8) {
                if let team = issue.teamName {
                    metadataChip(Image(systemName: "person.3.fill"), teamKeyLabel(name: team, key: issue.teamKey))
                }
                if let project = issue.projectName {
                    metadataChip(Image(systemName: "folder.fill"), project)
                }
                if let estimate = issue.estimate {
                    metadataChip(Image(systemName: "number"), "E\(estimate)")
                }
            }
            if !issue.labelNames.isEmpty {
                metadataChip(Image(systemName: "tag.fill"), issue.labelNames.joined(separator: ", "))
            }
            HStack(spacing: 8) {
                if let due = issue.dueDate {
                    metadataChip(Image(systemName: "calendar"), relativeDateText(due))
                }
                if let completed = issue.completedAt {
                    metadataChip(Image(systemName: "checkmark.circle"), relativeDateText(completed))
                }
                if let updated = issue.updatedAt {
                    metadataChip(Image(systemName: "clock"), "\(l.updated) \(relativeDateText(updated))")
                }
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func metadataChip(_ icon: Image, _ text: String) -> some View {
        HStack(spacing: 3) {
            icon
            Text(text)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private func priorityBadge(_ value: Int?) -> some View {
        Text(l.linearPriority(value))
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(priorityColor(value).opacity(0.2))
            .foregroundStyle(priorityColor(value))
            .clipShape(Capsule())
    }

    private func priorityColor(_ value: Int?) -> Color {
        switch value {
        case 1: return .red
        case 2: return .orange
        case 3: return .yellow
        case 4: return .blue
        default: return .secondary
        }
    }

    private func teamKeyLabel(name: String, key: String?) -> String {
        guard let key, !key.isEmpty else { return name }
        return "\(name) (\(key))"
    }

    private func relativeDateText(_ date: Date) -> String {
        RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }
}

/// Shared unfold row for Linear projects and initiatives.
private struct LinearContainerRow: Identifiable {
    var id: String
    var name: String
    var url: URL?
    var statusName: String?
    var symbol: String
    var issues: [LinearIssueSummary]

    init(project: LinearProjectSummary) {
        id = project.id
        name = project.name
        url = project.url
        statusName = project.statusName ?? project.statusType
        symbol = LinearChromeSymbol.project
        issues = project.issues
    }

    init(initiative: LinearInitiativeSummary) {
        id = initiative.id
        name = initiative.name
        url = initiative.url
        statusName = initiative.statusName
        symbol = LinearChromeSymbol.initiative
        issues = initiative.issues
    }
}

/// Whole header row toggles fold; the open-in-Linear button does not.
@MainActor
private struct LinearFoldableRow<Content: View>: View {
    let row: LinearContainerRow
    let openHelp: String
    @ViewBuilder let content: () -> Content

    @State private var expanded = false
    @State private var hoveringHeader = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.12)) { expanded.toggle() }
                } label: {
                    HStack(alignment: .center, spacing: 8) {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                            .frame(width: 10)
                        Image(systemName: row.symbol)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(width: 12)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.name)
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(.primary)
                            HStack(spacing: 6) {
                                if let status = row.statusName {
                                    Text(status)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Text("\(row.issues.count)")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        Spacer(minLength: 8)
                    }
                    .padding(8)
                    .contentShape(Rectangle())
                    .background(
                        hoveringHeader
                            ? Color.primary.opacity(0.08)
                            : Color.clear
                    )
                }
                .buttonStyle(.plain)
                .onHover { hoveringHeader = $0 }

                if let url = row.url {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Image(systemName: "arrow.up.right.square")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .help(openHelp)
                    .padding(.trailing, 8)
                }
            }

            if expanded {
                content()
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
            }
        }
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
