import SwiftUI

/// Pet + island while a session is running. Prompts sit above the island.
@MainActor
struct SessionIslandView: View {
    @Environment(UsageStore.self) private var store
    @Environment(CompanionStore.self) private var companion
    @Environment(FocusSessionStore.self) private var session

    private var l: L { companion.l }

    var body: some View {
        if let current = session.session {
            let issue = store.linearIssue(id: current.issue.id) ?? current.issue.summary
            let clock = session.clockDisplay()
            VStack(alignment: .leading, spacing: 6) {
                SessionPromptCard()
                    .frame(width: FloatingPetController.islandWidth)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        LinearIssueIDButton(identifier: current.issue.identifier, url: current.issue.url)
                        Text(current.issue.title)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    HStack(spacing: 6) {
                        Text(clock.text)
                            .font(.system(size: 16, weight: .semibold, design: .rounded).monospacedDigit())
                        if clock.overtime {
                            Text(l.overtimeAbbrev)
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.orange.opacity(0.2))
                                .foregroundStyle(.orange)
                                .clipShape(Capsule())
                        }
                        Spacer(minLength: 0)
                        Button {
                            session.togglePause()
                        } label: {
                            Image(systemName: current.userPaused || current.phase == .paused
                                  ? "play.fill" : "pause.fill")
                        }
                        .buttonStyle(.borderless)
                        .disabled(current.phase == .awaitingChoice)
                        .help(current.userPaused || current.phase == .paused ? l.resumeTimer : l.pauseTimer)
                        LinearIssueStatusPicker(issue: issue)
                    }
                }
                .padding(8)
                .frame(width: FloatingPetController.islandWidth, alignment: .leading)
                .background(Color(nsColor: .windowBackgroundColor).opacity(0.95))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }
}
