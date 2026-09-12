import AppKit
import SwiftUI

/// Dedicated Today desk. Closing it does not stop a running session.
@MainActor
final class TodayDeskController: NSObject, NSWindowDelegate {
    private let usage: UsageStore
    private let companion: CompanionStore
    private let session: FocusSessionStore
    private var window: NSWindow?

    init(usage: UsageStore, companion: CompanionStore, session: FocusSessionStore) {
        self.usage = usage
        self.companion = companion
        self.session = session
        super.init()
        session.onOpenDesk = { [weak self] in self?.open() }
    }

    func open() {
        NSApp.activate(ignoringOtherApps: true)
        if window == nil {
            window = makeWindow()
        } else if window?.contentView == nil {
            window?.contentView = hostedView()
            window?.title = L(companion.language).todayDeskWindowTitle
        }
        window?.makeKeyAndOrderFront(nil)
    }

    private func hostedView() -> NSView {
        NSHostingView(rootView:
            TodayDeskView()
                .environment(usage)
                .environment(companion)
                .environment(session)
                .environment(\.locale, companion.language.displayLocale)
        )
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)
        window.title = L(companion.language).todayDeskWindowTitle
        window.identifier = NSUserInterfaceItemIdentifier(LaunchWindowPolicy.todayDeskIdentifier)
        window.setFrameAutosaveName(LaunchWindowPolicy.todayDeskAutosaveName)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = hostedView()
        if window.frame.origin == .zero { window.center() }
        return window
    }

    func windowWillClose(_ notification: Notification) {
        // Keep the session on the overlay; only hide the desk.
        window?.contentView = nil
    }
}

@MainActor
struct TodayDeskView: View {
    @Environment(UsageStore.self) private var store
    @Environment(CompanionStore.self) private var companion
    @Environment(FocusSessionStore.self) private var session

    private var l: L { companion.l }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            hero
            Divider()
            pinList
            Divider()
            todayLog
        }
        .padding(18)
        .frame(minWidth: 400, minHeight: 520)
        .task(id: store.linearIntegrationEnabled && store.linearAPIKeyConfigured) {
            guard store.linearIntegrationEnabled, store.linearAPIKeyConfigured else { return }
            _ = await store.refreshLinearIssues()
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(l.todayDeskWindowTitle)
                    .font(.title2.weight(.semibold))
                Text(Date(), format: .dateTime.weekday(.wide).month().day())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            durationPickers
        }
    }

    private var durationPickers: some View {
        @Bindable var session = session
        return HStack(spacing: 10) {
            labeledMinutes(l.plannedLengthLabel, selection: $session.plannedMinutes, presets: SessionXP.plannedPresets)
            labeledMinutes(l.checkInIntervalLabel, selection: $session.checkInMinutes, presets: SessionXP.checkInPresets)
        }
    }

    private func labeledMinutes(_ title: String, selection: Binding<Int>, presets: [Int]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Picker(title, selection: selection) {
                ForEach(presets, id: \.self) { minutes in
                    Text(l.minutesValue(minutes)).tag(minutes)
                }
                if !presets.contains(selection.wrappedValue) {
                    Text(l.minutesValue(selection.wrappedValue)).tag(selection.wrappedValue)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
            .frame(width: 92)
            Stepper("", value: selection, in: SessionXP.minMinutes...SessionXP.maxMinutes)
                .labelsHidden()
                .controlSize(.mini)
                .help(l.customMinutes)
        }
    }

    @ViewBuilder
    private var hero: some View {
        if let current = session.session {
            let issue = store.linearIssue(id: current.issue.id) ?? current.issue.summary
            let clock = session.clockDisplay()
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    LinearIssueIDButton(
                        identifier: current.issue.identifier,
                        url: current.issue.url,
                        style: .title3.weight(.bold))
                    Text(current.issue.title)
                        .font(.title3.weight(.semibold))
                        .lineLimit(2)
                    Spacer()
                }
                HStack(alignment: .center, spacing: 12) {
                    Button {
                        session.togglePause()
                    } label: {
                        Image(systemName: current.userPaused || current.phase == .paused
                              ? "play.fill" : "pause.fill")
                            .font(.title)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(current.phase == .awaitingChoice)
                    .help(current.userPaused || current.phase == .paused ? l.resumeTimer : l.pauseTimer)

                    Text(clock.text)
                        .font(.system(size: 44, weight: .medium, design: .rounded).monospacedDigit())
                    if clock.overtime {
                        Text(l.overtimeAbbrev)
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.2))
                            .foregroundStyle(.orange)
                            .clipShape(Capsule())
                    }
                    Spacer()
                    LinearIssueStatusPicker(issue: issue, compact: false)
                    Button(l.markDone) {
                        Task { await session.markIssueDone() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(issue.completedStateId == nil && !issue.teamStates.contains { $0.type.lowercased() == "completed" })
                }
                SessionPromptCard()
            }
            .padding(12)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            Text(l.todayDeskEmpty)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 20)
        }
    }

    private var pinList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(l.todayDeskPinList).font(.headline)
            if store.linearInProgressIssues.isEmpty {
                Text(l.linearIssuesEmptyInProgress)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(store.linearInProgressIssues) { issue in
                            HStack(spacing: 8) {
                                LinearIssueIDButton(identifier: issue.identifier, url: issue.issueURL)
                                Text(issue.title)
                                    .lineLimit(1)
                                    .font(.callout)
                                Spacer()
                                LinearIssueStatusPicker(issue: issue)
                                LinearFocusButton(issue: issue)
                            }
                            .padding(6)
                            .background(Color.secondary.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                .frame(minHeight: 80, maxHeight: 180)
            }
        }
    }

    private var todayLog: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(l.todayDeskLogTitle).font(.headline)
                Spacer()
                Text(l.driftCountLabel(session.todayDriftCount))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            let entries = session.todayLog
            if entries.isEmpty {
                Text(l.todayDeskLogEmpty)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(entries) { entry in
                            logRow(entry)
                        }
                    }
                }
            }
        }
    }

    private func logRow(_ entry: FocusLogEntry) -> some View {
        Group {
            if entry.kind == .session {
                let duration = FocusClock.format(entry.durationSeconds ?? 0)
                let ot = (entry.overtimeSeconds ?? 0) > 0 ? FocusClock.format(entry.overtimeSeconds ?? 0) : ""
                Text(l.sessionLogLine(identifier: entry.issueIdentifier, duration: duration, overtime: ot))
            } else {
                let answer: String = {
                    switch entry.checkInAnswer {
                    case .yes: return l.checkInYes
                    case .no: return l.checkInNo
                    case .skip: return l.checkInSkip
                    case nil: return ""
                    }
                }()
                Text(l.checkInLogLine(
                    identifier: entry.issueIdentifier,
                    answer: answer,
                    notePosted: entry.notePosted))
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

@MainActor
struct SessionPromptCard: View {
    @Environment(FocusSessionStore.self) private var session
    @Environment(CompanionStore.self) private var companion

    private var l: L { companion.l }

    var body: some View {
        switch session.prompt {
        case .none:
            EmptyView()
        case .zeroTime:
            zeroTime
        case .checkIn:
            checkIn
        }
    }

    private var zeroTime: some View {
        let id = session.session?.issue.identifier ?? ""
        return VStack(alignment: .leading, spacing: 8) {
            Text(l.timesUpPopupTitle(id))
                .font(.callout.weight(.semibold))
            Button(l.timesUpContinue) { session.continueOvertime() }
                .buttonStyle(.borderedProminent)
            Button(l.timesUpFinishLeave) { session.finishLeavingInProgress() }
            Button(l.timesUpMarkDone) { Task { await session.markIssueDone() } }
        }
        .controlSize(.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.windowBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var checkIn: some View {
        @Bindable var session = session
        let id = session.session?.issue.identifier ?? ""
        return VStack(alignment: .leading, spacing: 8) {
            Text(l.stillOnIssue(id))
                .font(.callout.weight(.semibold))
            TextField(l.checkInNotePlaceholder, text: $session.checkInDraft)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button(l.checkInYes) { Task { await session.answerCheckIn(.yes) } }
                    .buttonStyle(.borderedProminent)
                Button(l.checkInNo) { Task { await session.answerCheckIn(.no) } }
                Button(l.checkInSkip) { Task { await session.answerCheckIn(.skip) } }
                    .foregroundStyle(.secondary)
            }
            Text(l.checkInAddNote)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .controlSize(.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.windowBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private extension Color {
    static var windowBackgroundColor: Color { Color(nsColor: .windowBackgroundColor) }
}
