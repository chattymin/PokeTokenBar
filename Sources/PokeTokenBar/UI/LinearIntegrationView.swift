import SwiftUI

@MainActor
private enum LinearIssuesTab: Hashable {
    case inProgress
    case completedToday
}

@MainActor
struct LinearIntegrationView: View {
    let store: UsageStore
    @State private var selectedTab: LinearIssuesTab = .inProgress

    private var l: L { L(store.localizationLanguage) }

    private var visibleIssues: [LinearIssueSummary] {
        switch selectedTab {
        case .completedToday: return store.linearCompletedTodayIssues
        case .inProgress: return store.linearInProgressIssues
        }
    }

    var body: some View {
        @Bindable var store = store
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(l.linearIssuesTitle)
                    .font(.callout.weight(.semibold))
                Spacer()
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
                    Picker("", selection: $selectedTab) {
                        Text(l.linearInProgressTab).tag(LinearIssuesTab.inProgress)
                        Text(l.linearCompletedTodayTab).tag(LinearIssuesTab.completedToday)
                    }
                .pickerStyle(.segmented)
                .labelsHidden()

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

                if visibleIssues.isEmpty {
                    Text(selectedTab == .completedToday ? l.linearIssuesEmptyCompleted : l.linearIssuesEmptyInProgress)
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
        }
        .frame(height: 520)
        .task(id: store.linearIntegrationEnabled && store.linearAPIKeyConfigured) {
            guard store.linearIntegrationEnabled, store.linearAPIKeyConfigured else { return }
            _ = await store.refreshLinearIssues()
        }
    }

    @ViewBuilder
    private func issueCard(_ issue: LinearIssueSummary) -> some View {
        let content = issueCardContent(issue)
        if let url = issue.issueURL {
            Link(destination: url) {
                content
            }
            .buttonStyle(.plain)
            .help(l.linearOpenIssue)
        } else {
            content
        }
    }

    private func issueCardContent(_ issue: LinearIssueSummary) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(issue.identifier)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                priorityBadge(issue.priority)
                if let state = issue.stateName {
                    Text(state)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if issue.issueURL != nil {
                    Image(systemName: "arrow.up.right.square")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
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
