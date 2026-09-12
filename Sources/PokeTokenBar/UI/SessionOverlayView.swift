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
                if let warning = session.forfeitPrompt {
                    FocusForfeitWarningCard(warning: warning)
                        .frame(width: FloatingPetController.islandWidth)
                } else if session.resetPrompt {
                    FocusResetConfirmCard()
                        .frame(width: FloatingPetController.islandWidth)
                } else {
                    SessionPromptCard()
                        .frame(width: FloatingPetController.islandWidth)
                }

                if !store.floatingPetIslandFolded {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            LinearIssueIDButton(identifier: current.issue.identifier, url: current.issue.url)
                            Text(current.issue.title)
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Spacer(minLength: 0)
                            NewLinearIssueButton()
                            SessionNoteButton()
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
                        FocusTimerControls()
                        if session.isComposingNote {
                            SessionNoteComposer()
                        }
                    }
                    .padding(8)
                    .frame(width: FloatingPetController.islandWidth, alignment: .leading)
                    .background(Color(nsColor: .windowBackgroundColor).opacity(0.95))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else if session.isComposingNote {
                    SessionNoteComposer()
                        .padding(8)
                        .frame(width: FloatingPetController.islandWidth, alignment: .leading)
                        .background(Color(nsColor: .windowBackgroundColor).opacity(0.95))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }
}

/// Bubble button that expands the compact Linear comment field.
@MainActor
struct SessionNoteButton: View {
    var compact: Bool = true

    @Environment(FocusSessionStore.self) private var session
    @Environment(CompanionStore.self) private var companion

    private var l: L { companion.l }

    var body: some View {
        Group {
            if compact {
                Button {
                    session.toggleNoteComposer()
                } label: {
                    Image(systemName: session.isComposingNote ? "text.bubble.fill" : "text.bubble")
                }
                .buttonStyle(.borderless)
                .controlSize(.mini)
            } else {
                Button {
                    session.toggleNoteComposer()
                } label: {
                    Label(l.checkInAddNote, systemImage: session.isComposingNote ? "text.bubble.fill" : "text.bubble")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .help(l.sessionNoteHelp)
    }
}

/// Compact field + Post. Shared by the overlay island and Today desk.
@MainActor
struct SessionNoteComposer: View {
    var compact: Bool = true

    @Environment(FocusSessionStore.self) private var session
    @Environment(CompanionStore.self) private var companion

    private var l: L { companion.l }
    @FocusState private var noteFieldFocused: Bool
    private var trimmedEmpty: Bool {
        session.noteDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        @Bindable var session = session
        VStack(alignment: .leading, spacing: compact ? 4 : 6) {
            HStack(spacing: 6) {
                TextField(l.checkInNotePlaceholder, text: $session.noteDraft)
                    .textFieldStyle(.roundedBorder)
                    .focused($noteFieldFocused)
                    .onSubmit { Task { await session.postSessionNote() } }
                Button(l.postNote) {
                    Task { await session.postSessionNote() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(session.isPostingNote || trimmedEmpty)
            }
            if session.notePostFailed {
                Text(l.linearCommentFailed)
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .controlSize(compact ? .mini : .small)
        .onAppear { noteFieldFocused = true }
    }
}
