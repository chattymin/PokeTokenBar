import AppKit
import QuartzCore
import SwiftUI

extension Notification.Name {
    /// The app added or removed an agent's hooks.
    static let agentHooksDidChange = Notification.Name("PokeTokenBar.agentHooksDidChange")
}

/// 데스크톱 위에 떠 있는 컴패니언 포켓몬 오버레이(옵트인, 설정 → 플로팅 펫).
/// - 드래그: 커스텀 `mouseDragged` (클릭과 충돌하지 않음).
/// - 클릭 → 알 기도 / 포켓몬 팝오버, 우클릭 → 메뉴, 호버 → 오늘 사용량 콜아웃.
/// - Limit-alert speech bubbles grow the panel; persisted origin is the *pet*, not the panel.
/// - Agent activity (`poketokenbar://agent`): bob while working, bubble while waiting,
///   run to the cursor when done. The run never moves the saved home.
/// - 에너지: 숨김·슬립 시 호스팅 트리 해제.
@MainActor
final class FloatingPetController: NSObject, NSWindowDelegate {
    private let store: UsageStore
    private let companion: CompanionStore
    private let defaults: UserDefaults
    private var panel: NSPanel?
    private var hoverPanel: NSPanel?
    private var displayAwake = true
    private var builtAnimated: Bool?
    private var powerObserver: NSObjectProtocol?
    private var reduceMotionObserver: NSObjectProtocol?
    private(set) var tracker = AgentActivityTracker()
    private var agentTimer: Timer?
    private let agentModel = FloatingPetAgentModel()
    private(set) var runPhase: RunPhase = .home
    /// Pet origin next to the cursor; read only while `runPhase == .away`.
    private var awayPetOrigin: NSPoint?
    /// Bumped on every run/return animation so a stale completion handler does nothing.
    private var runGeneration = 0
    /// Agents whose session logs drive the pet with no setup. Empty in tests: no file watching.
    private let agentLogSources: [AgentLogSource]
    private var agentLogWatcher: AgentLogWatcher?
    /// Hooks the pet is offering to add right now, shown as the lowest-priority bubble.
    private var hookOffer: AgentHookIntegration?
    /// Offer waiting for the `done` bubble that prompted it to finish.
    private var pendingHookOffer: AgentHookIntegration?
    private var hookOfferExpiry: Task<Void, Never>?
    private var offeredHooksThisLaunch = false
    private let confirmHookOffer: @MainActor (AgentHookIntegration) -> Void
    private var hooksObserver: NSObjectProtocol?

    private static let originXKey = "floatingPetOriginX"
    private static let originYKey = "floatingPetOriginY"

    /// Squared movement (pt²) below which a mouse-up counts as a click, not a drag.
    static let clickThresholdSquared: CGFloat = 16  // ~4pt

    /// Vertical space above the sprite for the bubble + `bubbleSpacing` (pt).
    /// Sized for two wrapped body lines + title + padding (ja strings).
    static let bubbleHeadroom: CGFloat = 84
    /// Gap between the bubble and the sprite (the pet view's VStack spacing).
    static let bubbleSpacing: CGFloat = 8
    /// Minimum panel width while a bubble is showing.
    static let bubbleMinWidth: CGFloat = 190
    /// Horizontal padding inside the dialogue box (each side): the frame, its corner balls and a gap.
    /// Content + 2× this = `bubbleMinWidth`.
    static let bubbleHorizontalPadding: CGFloat = 11
    /// Fixed text column — wraps instead of growing past the panel.
    static let bubbleContentWidth: CGFloat = bubbleMinWidth - (bubbleHorizontalPadding * 2)
    /// Above the title, inside the frame.
    static let bubbleTopPadding: CGFloat = 11
    /// Below the body: room for the ▼ indicator inside the frame.
    static let bubbleBottomPadding: CGFloat = 14
    /// Dialogue text uses the rounded system face; view and measurement share these fonts.
    static let bubbleTitleFont = roundedFont(size: 11, weight: .bold)
    static let bubbleBodyFont = roundedFont(size: 10, weight: .medium)

    private static func roundedFont(size: CGFloat, weight: NSFont.Weight) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        return base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? base
    }

    /// Typewriter reveal: one tick per frame at 30 fps, finished within 0.4–0.8 s.
    static let typewriterTick: TimeInterval = 1.0 / 30
    static func typewriterSteps(characterCount: Int) -> Int {
        let duration = min(max(Double(characterCount) * 0.02, 0.4), 0.8)
        return max(1, min(characterCount, Int((duration / typewriterTick).rounded())))
    }

    /// Characters shown after `step` of `steps` (from `typewriterSteps`, always ≥ 1).
    static func revealedCount(step: Int, of steps: Int, characterCount: Int) -> Int {
        characterCount * min(step, steps) / steps
    }

    /// ▼ blinks after the reveal, then stays on: a bubble can stay up indefinitely (waiting).
    static let dialogueBlinkInterval: TimeInterval = 0.5
    static let dialogueBlinkLimit: TimeInterval = 10
    /// `SpeechBubbleView` body `.lineLimit`. Measure and view must share this — a
    /// headroom-only guard stays green for 3-line copy that still fits 70pt (#167).
    static let bubbleBodyLineLimit = 2

    /// Run to the cursor / back home.
    static let agentRunDuration: TimeInterval = 0.6
    /// Distance between the cursor and the panel after a run, so the pet never sits under the pointer.
    static let agentRunCursorGap: CGFloat = 16
    /// Half a bob cycle while an agent works. Must stay > 0: it is the frame cap of this loop.
    static let agentBobInterval: TimeInterval = 0.5

    /// Where the pet stands relative to its saved home during an agent "done" run.
    enum RunPhase: Equatable {
        case home
        case away
        case returning
    }

    /// A window move persists the origin only at home. A user drag during a run cancels the
    /// return and becomes the new home; the run's own animation frames never overwrite it.
    static func resolveMove(phase: RunPhase, userDragging: Bool) -> (phase: RunPhase, persist: Bool) {
        if userDragging { return (.home, true) }
        return (phase, phase == .home)
    }

    /// Panel origin next to the cursor: below-right by default, flipped left/up at screen
    /// edges so the panel does not cover the pointer, then clamped to `visibleFrame`.
    /// When the panel is larger than the screen, the bottom-left (the pet) stays visible.
    static func runPanelOrigin(cursor: NSPoint, panelSize: NSSize, visibleFrame: NSRect,
                               gap: CGFloat = agentRunCursorGap) -> NSPoint {
        let fitsRight = cursor.x + gap + panelSize.width <= visibleFrame.maxX
        let fitsBelow = cursor.y - gap - panelSize.height >= visibleFrame.minY
        let x = fitsRight ? cursor.x + gap : cursor.x - gap - panelSize.width
        let y = fitsBelow ? cursor.y - gap - panelSize.height : cursor.y + gap
        return NSPoint(x: max(min(x, visibleFrame.maxX - panelSize.width), visibleFrame.minX),
                       y: max(min(y, visibleFrame.maxY - panelSize.height), visibleFrame.minY))
    }

    /// Motion (bob, run) needs an animated host and no Reduce Motion.
    static func allowsMotion(animated: Bool, reduceMotion: Bool) -> Bool { animated && !reduceMotion }

    /// A done runs to the cursor unless the pet is already there for another agent's done.
    static func runsToCursor(phase: RunPhase, motionAllowed: Bool, panelVisible: Bool) -> Bool {
        phase != .away && motionAllowed && panelVisible
    }

    /// Only the person's own turn ending calls them over to the cursor; a finished subagent or
    /// background task is said where the pet stands.
    static func callsPersonOver(_ done: AgentActivitySummary.Note) -> Bool { done.task == nil }

    static func shouldBob(working: Bool, motionAllowed: Bool) -> Bool {
        motionAllowed && working
    }

    /// The one bubble the pet shows. A limit alert outranks agent messages.
    enum Bubble: Equatable {
        case limit(UsageStore.LimitAlert)
        case agentWaiting(label: String?, message: String?, others: Int)
        /// `task`: a subagent or background task finished, not the person's own turn.
        case agentDone(label: String?, message: String?, task: AgentTaskKind? = nil)
        /// The pet offers to add an agent's hooks; a click asks for confirmation.
        case hookOffer(agentName: String)
    }

    /// A limit alert outranks agents; among agents a fresh `done` outranks waiting.
    static func bubble(limitAlert: UsageStore.LimitAlert?, agent: AgentActivitySummary) -> Bubble? {
        if let limitAlert { return .limit(limitAlert) }
        if let done = agent.done { return .agentDone(label: done.label, message: done.message, task: done.task) }
        if let waiting = agent.waiting {
            return .agentWaiting(label: waiting.label, message: waiting.message, others: agent.otherWaitingCount)
        }
        if let offer = agent.hookOffer { return .hookOffer(agentName: offer) }
        return nil
    }

    struct SpeechBubbleContent: Hashable {
        var title: String
        var body: String
        var isCritical: Bool
    }

    static func bubbleContent(_ bubble: Bubble, l: L) -> SpeechBubbleContent {
        switch bubble {
        case .limit(let alert):
            let title = alert.isCritical ? l.notifCritical : l.notifWarning
            return SpeechBubbleContent(title: title, body: bubbleBody(for: alert, title: title, l: l),
                                       isCritical: alert.isCritical)
        case .agentWaiting(let label, let message, let others):
            let title = agentTitle(label: label, unlabeled: l.agentWaitingTitle, status: l.agentWaitingStatus,
                                   count: others > 0 ? "+\(others)" : nil)
            return agentContent(title: title, body: message ?? l.agentWaitingDefaultBody)
        case .agentDone(let label, let message, let task):
            let (unlabeled, status) = switch task {
            case nil: (l.agentDoneTitle, l.agentDoneStatus)
            case .subagent: (l.agentSubagentDoneTitle, l.agentSubagentDoneStatus)
            case .background: (l.agentBackgroundDoneTitle, l.agentBackgroundDoneStatus)
            }
            let title = agentTitle(label: label, unlabeled: unlabeled, status: status, count: nil)
            return agentContent(title: title, body: message ?? l.agentDoneDefaultBody)
        case .hookOffer(let agentName):
            return agentContent(title: agentName, body: l.agentHookOfferBody)
        }
    }

    private static func agentContent(title: String, body: String) -> SpeechBubbleContent {
        SpeechBubbleContent(title: title, body: fittedBubbleBody(body, title: title), isCritical: false)
    }

    /// "<label> · <status>" (or the plain title without a label), then "+N" more waiting agents.
    /// The count is digits in every language: words would take the room the label needs.
    /// The label — or the plain title — is cut with an ellipsis so the title stays on one line.
    static func agentTitle(label: String?, unlabeled: String, status: String, count: String?) -> String {
        let lead = label ?? unlabeled
        var suffix = label == nil ? "" : " · " + status
        if let count { suffix += " " + count }
        func fits(_ title: String) -> Bool {
            measureSpeechBubbleLayout(title: title, body: "").unclampedTitleWidth <= bubbleContentWidth
        }
        guard !fits(lead + suffix) else { return lead + suffix }
        let characters = Array(lead)
        func cut(_ count: Int) -> String {
            String(characters.prefix(count)).trimmingCharacters(in: .whitespaces) + "…" + suffix
        }
        // Invariant: `low` fits (or is the shortest cut), `high` does not.
        var low = 0, high = characters.count
        while high - low > 1 {
            let mid = (low + high) / 2
            if fits(cut(mid)) { low = mid } else { high = mid }
        }
        // Prefer a word boundary ("needs…", not "needs y…"); folder names and CJK have none.
        if let space = characters[..<low].lastIndex(of: " "), space >= low / 2 { return cut(space) }
        return cut(low)
    }

    /// Cut `text` with an ellipsis until it fits `bubbleBodyLineLimit`, so the view never clips it.
    static func fittedBubbleBody(_ text: String, title: String) -> String {
        guard measureSpeechBubbleLayout(title: title, body: text).wouldTruncate else { return text }
        let characters = Array(text)
        func ellipsized(_ count: Int) -> String {
            String(characters.prefix(count)).trimmingCharacters(in: .whitespaces) + "…"
        }
        // Invariant: `low` fits, `high` does not. Only fitting candidates are ever returned.
        var low = 0, high = characters.count
        while high - low > 1 {
            let mid = (low + high) / 2
            if measureSpeechBubbleLayout(title: title, body: ellipsized(mid)).wouldTruncate {
                high = mid
            } else {
                low = mid
            }
        }
        return ellipsized(low)
    }

    /// How long the heart bubble stays after the last qualifying stroke.
    static let heartDuration: Duration = .milliseconds(1800)

    /// Speech takes priority over hearts: limit alert, agent done, agent waiting, then a stroke.
    static func heartsShowing(afterStrokeWithAlertActive alertActive: Bool,
                              agent: AgentActivitySummary = .init()) -> Bool {
        !alertActive && bubble(limitAlert: nil, agent: agent) == nil
    }

    /// Reserve headroom for either speech or hearts, including agent-only speech.
    static func isShowingBubble(alertActive: Bool, heartsShowing: Bool,
                                agent: AgentActivitySummary = .init()) -> Bool {
        alertActive || bubble(limitAlert: nil, agent: agent) != nil || heartsShowing
    }

    /// The native tooltip would overlap the heart bubble, so it is cleared while hearts show.
    /// Limit alerts keep the tooltip as before.
    static func nativeToolTip(_ text: String, heartsShowing: Bool) -> String? {
        heartsShowing ? nil : text
    }

    /// Chrome size plus the signals the view actually fails on: wrap count vs
    /// `bubbleBodyLineLimit`, and single-line width vs the content column.
    struct SpeechBubbleLayout: Equatable {
        var size: NSSize
        var bodyLineCount: Int
        var unclampedTitleWidth: CGFloat
        var unclampedBodyWidth: CGFloat
        var wouldTruncate: Bool
    }

    /// AppKit 호버 콜아웃에 사용할 appearance 해석 완료 색상.
    ///
    /// 이 콜아웃은 SwiftUI가 아니라 `NSTextField`와 레이어 기반 `NSView`로 조립된다.
    /// 텍스트 필드에 semantic `NSColor`를 그대로 지정하면 뷰의 effective appearance로
    /// 해석되지만, `windowBackgroundColor.cgColor`는 현재 그리기 appearance에서 즉시
    /// 색상이 굳어진다. 세 색상을 하나의 appearance에서 함께 해석해야 글자와 외곽선이
    /// 같은 라이트/다크 모드를 유지한다.
    struct HoverCalloutColors {
        var text: NSColor
        var background: NSColor
        var border: NSColor
    }

    static func hoverCalloutColors(for appearance: NSAppearance) -> HoverCalloutColors {
        HoverCalloutColors(
            text: snapshot(NSColor.labelColor, for: appearance),
            background: snapshot(NSColor.windowBackgroundColor, for: appearance),
            border: snapshot(NSColor.separatorColor, for: appearance))
    }

    private static func snapshot(_ color: NSColor, for appearance: NSAppearance) -> NSColor {
        var resolved = color
        appearance.performAsCurrentDrawingAppearance {
            resolved = NSColor(cgColor: color.cgColor) ?? color
        }
        return resolved
    }

    private var onOpenPopover: (() -> Void)?
    private var onHide: (() -> Void)?
    /// Tests pin motion on or off; nil follows Low Power Mode and Reduce Motion.
    private let motionOverride: Bool?
    /// Owned here and handed to the view once, so a prayer never rebuilds the hosting `rootView`.
    private let prayerBurst = PrayerBurst()
    private let hearts = PetHeartState()
    private var heartExpiry: Task<Void, Never>?
    private var isHovering = false
    /// The event text while the self-popped callout is up (nil otherwise, so it never shows on a later hover).
    private var eventPopText: String?
    private var eventPopExpiry: Task<Void, Never>?
    private var lastSeenEventSeq: Int?

    /// What a click on the pet does: an egg is prayed over, a hatched Pokémon opens the popover.
    enum ClickAction: Equatable { case pray, openPopover }

    static func clickAction(subjectIsEgg: Bool) -> ClickAction { subjectIsEgg ? .pray : .openPopover }

    /// Praying refreshes usage every 30 prayers (30, 60, 90...), the same step as the hover quip, so the egg's
    /// progress moves without a request per click.
    static let prayersPerRefresh = L.prayersPerQuip
    /// How long the callout stays up on its own when a hatch / evolution / graduation / Ditto line arrives.
    static let eventPopDuration: Duration = .seconds(6)

    /// Pop the callout only for an event not shown yet, while the pet is on screen and no speech or
    /// hearts bubble is up. An event that arrives when it cannot pop is dropped, not queued.
    static func shouldPopEvent(eventSeq: Int?, lastSeenSeq: Int?, petVisible: Bool, bubbleShowing: Bool) -> Bool {
        guard let eventSeq, eventSeq != lastSeenSeq else { return false }
        return petVisible && !bubbleShowing
    }

    /// Minimum gap between prayer-triggered refreshes. A refresh also queries the limit endpoints
    /// (Claude, Codex, Cursor, Antigravity), which have their own rate limits.
    static let prayerRefreshInterval: TimeInterval = 30

    /// How many refresh milestones `count` prayers have passed.
    static func prayerRefreshMilestone(for count: Int) -> Int { max(0, count) / prayersPerRefresh }

    /// Refresh once a milestone is passed that was not refreshed yet AND the floor since the last refresh has passed.
    /// A milestone held back by the floor is not lost: the next click after the floor still sees it as new.
    static func shouldRefreshOnPrayer(count: Int, lastRefreshedMilestone: Int, lastRefreshAt: Date?, now: Date) -> Bool {
        guard prayerRefreshMilestone(for: count) > lastRefreshedMilestone else { return false }
        guard let lastRefreshAt else { return true }
        return now.timeIntervalSince(lastRefreshAt) >= prayerRefreshInterval
    }

    private lazy var clickRouter = PetClickRouter(
        pray: { [weak self] in self?.companion.pray() },
        prayerCount: { [weak self] in self?.companion.state.eggPrayers?.count ?? 0 },
        didPray: { [weak self] in self?.refreshHoverAfterPrayer() },
        spawnEmoji: { [weak self] in self?.prayerBurst.spawn() },
        refreshUsage: { [weak self] in
            guard let store = self?.store else { return }
            Task { await store.refresh() }
        },
        openPopover: { [weak self] in self?.onOpenPopover?() },
        clock: clock)

    private let clock: () -> Date

    init(store: UsageStore, companion: CompanionStore, defaults: UserDefaults = .standard,
         clock: @escaping () -> Date = Date.init,
         onOpenPopover: (() -> Void)? = nil, onHide: (() -> Void)? = nil,
         motionOverride: Bool? = nil,
         agentLogSources: [AgentLogSource] = [],
         confirmHookOffer: (@MainActor (AgentHookIntegration) -> Void)? = nil) {
        self.clock = clock
        self.store = store
        self.companion = companion
        self.defaults = defaults
        self.motionOverride = motionOverride
        self.agentLogSources = agentLogSources
        self.confirmHookOffer = confirmHookOffer ?? { [companion] in
            FloatingPetController.presentHookConfirmation($0, defaults: defaults, language: companion.language)
        }
        self.onOpenPopover = onOpenPopover
        self.onHide = onHide
        super.init()
        lastSeenEventSeq = companion.latestEvent?.seq   // an event from before the pet existed is not news
        observeSettings()
        observePowerState()
        observeReduceMotion()
        sync()
    }

    static func isClick(from start: NSPoint, to end: NSPoint,
                        thresholdSquared: CGFloat = clickThresholdSquared) -> Bool {
        let dx = end.x - start.x, dy = end.y - start.y
        return dx * dx + dy * dy < thresholdSquared
    }

    func setDisplayAwake(_ awake: Bool) {
        displayAwake = awake
        if awake, let pending = pendingHookOffer, tracker.summary.done == nil {
            presentHookOffer(pending)
            agentModel.summary = agentSummary
        }
        sync()
    }

    private func observeSettings() {
        withObservationTracking {
            _ = store.floatingPetEnabled
            _ = store.floatingPetSize
            _ = store.floatingPetAgentActivity
            _ = store.currentBubbleAlert
            _ = store.todayTotalTokens
            _ = store.highestLimitUtilization
            _ = store.limitDisplayMode   // hover 툴팁 %가 파생되는 값 — 수동 관찰 표면은 파생 원천을 직접 추적(defect-log §표시·UI)
            _ = companion.language
            _ = companion.sulkIdle   // hover tooltip suffix
            _ = companion.state.eggPrayers   // hover text shows the prayer count
            _ = companion.latestEvent        // hover text shows the latest hatch / evolution line
            _ = companion.representativeSubject
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.sync()
                self.popEventIfNew()
                self.observeSettings()
            }
        }
    }

    private func observePowerState() {
        powerObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NSProcessInfoPowerStateDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.sync() }
        }
    }

    private func observeReduceMotion() {
        reduceMotionObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.sync() }
        }
    }

    static func shouldAnimate(lowPower: Bool) -> Bool { !lowPower }

    private var motionAllowed: Bool {
        if let motionOverride { return motionOverride }
        return Self.allowsMotion(
            animated: Self.shouldAnimate(lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled),
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    private var agentEnabled: Bool { store.floatingPetEnabled && store.floatingPetAgentActivity }

    var isBobbing: Bool { agentModel.bobs }

    // MARK: Agent activity

    /// Entry point for `poketokenbar://agent` URLs. Dropped while the pet or the setting is off.
    /// A done or waiting without a message shows the title of the session that last moved in that
    /// folder, when its log has one. A done for a turn that session started on its own (a message
    /// from another session) only ends the work: nobody is waiting for it.
    func handleAgentEvent(_ event: AgentActivityEvent) {
        guard agentEnabled else { return }
        var event = event
        let isDone = if case .done = event.activity { true } else { false }
        if isDone || event.lacksMessage, let session = latestSession(event.label) {
            if isDone, session.automaticTurn {
                event = AgentActivityEvent(activity: .idle, label: event.label)
            } else if isDone, let task = session.task {
                event = AgentActivityEvent(activity: .done(message: session.taskName, task: task), label: event.label)
                    .fillingMessage(session.title)
            } else {
                event = event.fillingMessage(session.title)
            }
        }
        apply(event)
    }

    private func apply(_ event: AgentActivityEvent) {
        tracker.apply(event, now: Date())
        agentDidChange()
    }

    private func agentDidChange() {
        if tracker.summary.done == nil, let pending = pendingHookOffer { presentHookOffer(pending) }
        let summary = agentSummary
        agentModel.summary = summary
        agentModel.bobs = Self.shouldBob(working: summary.working, motionAllowed: motionAllowed)
        scheduleAgentExpiry()
        if let done = summary.done {
            if Self.callsPersonOver(done), let p = panel,
               Self.runsToCursor(phase: runPhase, motionAllowed: motionAllowed, panelVisible: p.isVisible) {
                runToCursor(p)
            } else {
                sync()
            }
        } else {
            returnHome()
        }
    }

    /// One timer at the tracker's deadline — none while idle or waiting.
    private func scheduleAgentExpiry() {
        agentTimer?.invalidate()
        agentTimer = nil
        guard let deadline = tracker.deadline else { return }
        let timer = Timer(fire: deadline, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.expireAgentActivity(now: Date()) }
        }
        RunLoop.main.add(timer, forMode: .common)
        agentTimer = timer
    }

    /// Timer callback. A fire before the deadline re-arms instead of leaving the state stuck.
    func expireAgentActivity(now: Date) {
        agentTimer?.invalidate()   // this call is the fire; a still-early state must arm a new one
        agentTimer = nil
        if tracker.expire(now: now) { agentDidChange() } else { scheduleAgentExpiry() }
    }

    /// When the pending expiry fires; nil while nothing is armed.
    var agentExpiryFireDate: Date? {
        guard let agentTimer, agentTimer.isValid else { return nil }
        return agentTimer.fireDate
    }

    private func resetAgent() {
        tracker.reset()
        hookOffer = nil
        pendingHookOffer = nil
        hookOfferExpiry?.cancel()
        agentTimer?.invalidate()
        agentTimer = nil
        agentModel.summary = AgentActivitySummary()
        agentModel.bobs = false
        runPhase = .home
        runGeneration += 1
    }

    // MARK: Agent session logs

    /// Session-log readings arrive here (see `AgentLogWatcher`). The first `done` of a launch from
    /// an agent without hooks queues an offer to add them, shown once that `done` bubble is over.
    func handleAgentReading(_ reading: AgentLogReading, source: AgentLogSource, hooksInstalled: Bool) {
        guard agentEnabled else { return }
        if let hooks = source.hooks, hookOffer == nil, pendingHookOffer == nil,
           Self.shouldOfferHooks(activity: reading.activity, hooksInstalled: hooksInstalled,
                                 declined: defaults.bool(forKey: Self.hookOfferDeclinedKey),
                                 shownCount: defaults.integer(forKey: Self.hookOfferCountKey),
                                 offeredThisLaunch: offeredHooksThisLaunch) {
            pendingHookOffer = hooks
        }
        // Already about its own session file: no lookup by folder, which could pick another session.
        apply(AgentActivityEvent(activity: reading.activity, label: reading.label).fillingMessage(reading.title))
    }

    /// Tests set this instead of running a log watcher.
    var sessionOverride: ((String?) -> AgentSessionInfo?)?

    private func latestSession(_ label: String?) -> AgentSessionInfo? {
        if let sessionOverride { return sessionOverride(label) }
        return agentLogWatcher?.latestSession(label: label)
    }

    static let hookOfferCountKey = "agentHookOfferCount"
    static let hookOfferDeclinedKey = "agentHookOfferDeclined"
    /// Asked at most this many times (once per launch) unless the person says never.
    static let maxHookOffers = 3
    static let hookOfferDuration: Duration = .seconds(30)

    /// Offer right after a turn ends: the person just looked at the pet, and the agent is quiet.
    static func shouldOfferHooks(activity: AgentActivity, hooksInstalled: Bool, declined: Bool,
                                 shownCount: Int, offeredThisLaunch: Bool) -> Bool {
        guard case .done = activity else { return false }
        return !hooksInstalled && !declined && shownCount < maxHookOffers && !offeredThisLaunch
    }

    var isOfferingHooks: Bool { hookOffer != nil }

    /// Tests keep the display "asleep" so no panel goes on screen; this lets them see the offer.
    var showsHookOffersWhileAsleep = false

    /// The bubble the pet shows now, offer included.
    var currentBubble: Bubble? { Self.bubble(limitAlert: store.currentBubbleAlert, agent: agentSummary) }

    private func presentHookOffer(_ hooks: AgentHookIntegration) {
        // Nobody would see it: it stays pending until the display wakes.
        guard displayAwake || showsHookOffersWhileAsleep else { return }
        pendingHookOffer = nil
        hookOffer = hooks
        offeredHooksThisLaunch = true
        defaults.set(defaults.integer(forKey: Self.hookOfferCountKey) + 1, forKey: Self.hookOfferCountKey)
        hookOfferExpiry?.cancel()
        hookOfferExpiry = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.hookOfferDuration)
            guard !Task.isCancelled, let self, self.hookOffer != nil else { return }
            self.dismissHookOffer()
        }
    }

    private func dismissHookOffer() {
        hookOffer = nil
        hookOfferExpiry?.cancel()
        hookOfferExpiry = nil
        agentDidChange()
    }

    /// Asks before touching another app's settings. Runs the edit off the main thread.
    private static func presentHookConfirmation(_ hooks: AgentHookIntegration, defaults: UserDefaults,
                                                language: AppLanguage) {
        let l = L(language)
        let alert = NSAlert()
        alert.messageText = l.agentHookConfirmTitle(hooks.agentName)
        alert.informativeText = l.agentHookConfirmBody(hooks.agentName, hooks.settingsDescription())
        alert.addButton(withTitle: l.agentHookConnect)
        alert.addButton(withTitle: l.agentHookLater)
        alert.addButton(withTitle: l.agentHookNever)
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            Task.detached {
                var failure: String?
                do { try hooks.install() } catch {
                    failure = (error as? ClaudeAgentHooks.Failure) == .unreadableSettings
                        ? l.agentHookFailed : l.agentHookWriteFailed
                }
                await MainActor.run { [failure] in
                    NotificationCenter.default.post(name: .agentHooksDidChange, object: nil)
                    guard let failure else { return }
                    let error = NSAlert()
                    error.messageText = failure
                    error.runModal()
                }
            }
        case .alertThirdButtonReturn:
            defaults.set(true, forKey: hookOfferDeclinedKey)
        default:
            break
        }
    }

    private func updateAgentLogWatcher() {
        let wanted = agentEnabled && !agentLogSources.isEmpty
        if wanted, agentLogWatcher == nil {
            let watcher = AgentLogWatcher(sources: agentLogSources) { [weak self] reading, source, installed in
                Task { @MainActor in self?.handleAgentReading(reading, source: source, hooksInstalled: installed) }
            }
            watcher.start()
            agentLogWatcher = watcher
            hooksObserver = NotificationCenter.default.addObserver(
                forName: .agentHooksDidChange, object: nil, queue: .main) { [weak watcher] _ in
                watcher?.invalidateHookStatus()
            }
        } else if !wanted, let watcher = agentLogWatcher {
            watcher.stop()
            agentLogWatcher = nil
            if let hooksObserver { NotificationCenter.default.removeObserver(hooksObserver) }
            hooksObserver = nil
        }
    }

    private func runToCursor(_ p: NSPanel) {
        let cursor = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(cursor, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { sync(); return }
        let frame = beginRun(cursor: cursor, visibleFrame: visible)
        hideHoverCallout()
        animate(p, to: frame) {}
    }

    /// Leaves home for a spot next to the cursor and returns the panel frame to animate to.
    func beginRun(cursor: NSPoint, visibleFrame: NSRect) -> NSRect {
        let petSize = CGFloat(store.floatingPetSize)
        let size = Self.panelSize(petSize: petSize, showingBubble: true)
        let origin = Self.runPanelOrigin(cursor: cursor, panelSize: size, visibleFrame: visibleFrame)
        runPhase = .away
        awayPetOrigin = Self.petOrigin(panelOrigin: origin, petSize: petSize, panelSize: size)
        return NSRect(origin: origin, size: size)
    }

    private func returnHome() {
        guard runPhase == .away, let p = panel, p.isVisible else {
            if runPhase == .away { runPhase = .home }
            sync()
            return
        }
        guard motionAllowed else {
            runPhase = .home
            sync()
            return
        }
        runPhase = .returning
        let frame = targetFrame(petSize: CGFloat(store.floatingPetSize), showingBubble: showingBubble)
        animate(p, to: frame) { [weak self] in
            guard let self, self.runPhase == .returning else { return }
            self.runPhase = .home
            self.sync()
        }
    }

    private func animate(_ p: NSPanel, to frame: NSRect, completion: @escaping @MainActor () -> Void) {
        runGeneration += 1
        let generation = runGeneration
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.agentRunDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            p.animator().setFrame(frame, display: true)
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.runGeneration == generation else { return }
                completion()
            }
        })
    }

    /// A plain click answers waiting/done agents, then prays over an egg or opens a hatched pet.
    func petClicked() {
        if let offer = hookOffer, currentBubble == .hookOffer(agentName: offer.agentName) {
            dismissHookOffer()
            confirmHookOffer(offer)
            return
        }
        if tracker.dismissBubble() { agentDidChange() }
        clickRouter.handle(subjectIsEgg: companion.representativeSubject.speciesID == nil)
    }

    /// Context-menu Open always opens, including when the representative is an egg.
    private func openPopover() {
        if tracker.dismissBubble() { agentDidChange() }
        onOpenPopover?()
    }

    /// Panel size for a given pet size and bubble visibility. Pure — tested without AppKit layout.
    static func panelSize(petSize: CGFloat, showingBubble: Bool) -> NSSize {
        if showingBubble {
            return NSSize(width: max(petSize, bubbleMinWidth),
                          height: petSize + bubbleHeadroom)
        }
        return NSSize(width: petSize, height: petSize)
    }

    static func panelOrigin(petOrigin: NSPoint, petSize: CGFloat, panelSize: NSSize) -> NSPoint {
        let xInset = max(0, (panelSize.width - petSize) / 2)
        return NSPoint(x: petOrigin.x - xInset, y: petOrigin.y)
    }

    static func petOrigin(panelOrigin: NSPoint, petSize: CGFloat, panelSize: NSSize) -> NSPoint {
        let xInset = max(0, (panelSize.width - petSize) / 2)
        return NSPoint(x: panelOrigin.x + xInset, y: panelOrigin.y)
    }

    /// Measure speech-bubble chrome for a title/body at the fixed content width (wrapping).
    /// Pure AppKit typography — keeps the layout test free of SwiftUI hosting.
    /// The alert text, with its Claude account only when it still fits: the percentage matters more.
    static func bubbleBody(for alert: UsageStore.LimitAlert, title: String, l: L) -> String {
        let full = alert.body(l)
        guard alert.account != nil, measureSpeechBubbleLayout(title: title, body: full).wouldTruncate else { return full }
        return alert.body(l, withAccount: false)
    }

    static func measureSpeechBubble(title: String, body: String,
                                    contentWidth: CGFloat = bubbleContentWidth) -> NSSize {
        measureSpeechBubbleLayout(title: title, body: body, contentWidth: contentWidth).size
    }

    /// Layout the view draws: unconstrained chrome (`size`) plus wrap count and
    /// single-line widths. `size.width` is clamped to the column (cannot fail a
    /// `≤ panel.width` assert); `unclamped*Width` is the check that can.
    static func measureSpeechBubbleLayout(title: String, body: String,
                                          contentWidth: CGFloat = bubbleContentWidth) -> SpeechBubbleLayout {
        let titleFont = bubbleTitleFont
        let bodyFont = bubbleBodyFont
        let wrap = NSSize(width: contentWidth, height: 10_000)
        let unclamped = NSSize(width: CGFloat.greatestFiniteMagnitude, height: 10_000)
        let opts: NSString.DrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]
        let titleRect = (title as NSString).boundingRect(
            with: wrap, options: opts, attributes: [.font: titleFont])
        let bodyRect = (body as NSString).boundingRect(
            with: wrap, options: opts, attributes: [.font: bodyFont])
        let unclampedTitle = (title as NSString).boundingRect(
            with: unclamped, options: opts, attributes: [.font: titleFont])
        let unclampedBody = (body as NSString).boundingRect(
            with: unclamped, options: opts, attributes: [.font: bodyFont])
        let textWidth = min(contentWidth, max(titleRect.width, bodyRect.width))
        let titleLineCount = wrappedLineCount(title, font: titleFont, width: contentWidth)
        let bodyLineCount = wrappedLineCount(body, font: bodyFont, width: contentWidth)
        let textHeight = CGFloat(titleLineCount) * drawnLineHeight(titleFont) + 2
            + CGFloat(bodyLineCount) * drawnLineHeight(bodyFont)
        // Match SpeechBubbleView: horizontal padding ×2, top/bottom padding.
        let hPad = bubbleHorizontalPadding * 2
        let vPad = bubbleTopPadding + bubbleBottomPadding
        return SpeechBubbleLayout(
            size: NSSize(width: textWidth + hPad, height: textHeight + vPad),
            bodyLineCount: bodyLineCount,
            unclampedTitleWidth: unclampedTitle.width,
            unclampedBodyWidth: unclampedBody.width,
            wouldTruncate: bodyLineCount > bubbleBodyLineLimit)
    }

    /// Line height SwiftUI draws: ascent and descent each rounded up. `boundingRect` reports one
    /// point less per line (12 vs 13 at 10 pt), which left two-line bubbles 3 pt taller than
    /// measured. `SpeechBubbleRenderingTests` holds this against real renders.
    private static func drawnLineHeight(_ font: NSFont) -> CGFloat {
        ceil(font.ascender) + ceil(-font.descender) + ceil(font.leading)
    }

    /// Wrap count at `width` using the same `boundingRect` path as `size`, so a
    /// height-jump fixture and `bodyLineCount` cannot disagree.
    private static func wrappedLineCount(_ string: String, font: NSFont, width: CGFloat) -> Int {
        guard !string.isEmpty else { return 0 }
        let opts: NSString.DrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]
        let wrapped = (string as NSString).boundingRect(
            with: NSSize(width: width, height: 10_000), options: opts, attributes: [.font: font])
        let single = ("Ay" as NSString).boundingRect(
            with: NSSize(width: 10_000, height: 10_000), options: opts, attributes: [.font: font])
        let unit = max(single.height, 1)
        return max(1, Int((wrapped.height / unit).rounded()))
    }

    private func sync() {
        if !agentEnabled, !tracker.agents.isEmpty || runPhase != .home || hookOffer != nil { resetAgent() }
        updateAgentLogWatcher()
        guard store.floatingPetEnabled, displayAwake else { hide(); return }
        show()
    }

    private var showingBubble: Bool {
        Self.isShowingBubble(alertActive: store.currentBubbleAlert != nil, heartsShowing: hearts.isShowing,
                             agent: agentSummary)
    }

    /// The tracker's summary plus the hook offer, which is the controller's own state.
    private var agentSummary: AgentActivitySummary {
        var summary = tracker.summary
        summary.hookOffer = hookOffer?.agentName
        return summary
    }

    /// Build once per animation mode; callbacks share the controller's click and bubble routing.
    func makeHostingView(animated: Bool) -> PetHostingView {
        let hosting = PetHostingView(rootView: AnyView(
            FloatingPetView(animated: animated, agent: agentModel, burst: prayerBurst, hearts: hearts)
                .environment(store).environment(companion)))
        hosting.onOpenPopover = { [weak self] in self?.openPopover() }
        hosting.onClick = { [weak self] in self?.petClicked() }
        hosting.onStroke = { [weak self] in self?.petWasStroked() }
        hosting.onHide = onHide
        hosting.onToggleBackView = { [weak self] in self?.store.alwaysFacesBack.toggle() }
        hosting.isBackViewOn = { [weak self] in self?.store.alwaysFacesBack ?? false }
        hosting.languageProvider = { [weak self] in self?.companion.language ?? .systemDefault }
        hosting.onHoverChange = { [weak self] hovering in
            self?.isHovering = hovering
            if hovering { self?.showHoverCallout() } else { self?.hideHoverCallout() }
        }
        return hosting
    }

    private func show() {
        let p = panel ?? makePanel()
        panel = p
        let wantAnimated = Self.shouldAnimate(lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled)
        if p.contentView == nil || builtAnimated != wantAnimated {
            p.contentView = makeHostingView(animated: wantAnimated)
            builtAnimated = wantAnimated
        }
        if let hosting = p.contentView as? PetHostingView {
            hosting.toolTip = Self.nativeToolTip(currentHoverText(), heartsShowing: hearts.isShowing)
            hosting.strokeDistance = max(10, CGFloat(store.floatingPetSize) * 0.15)
        }
        agentModel.bobs = Self.shouldBob(working: tracker.summary.working, motionAllowed: motionAllowed)
        let petSize = CGFloat(store.floatingPetSize)
        p.setFrame(targetFrame(petSize: petSize, showingBubble: showingBubble),
                   display: true)
        p.orderFrontRegardless()
        if hoverPanel?.isVisible == true { showHoverCallout() }
    }

    private func petWasStroked() {
        hearts.isShowing = Self.heartsShowing(afterStrokeWithAlertActive: store.currentBubbleAlert != nil,
                                             agent: agentSummary)
        guard hearts.isShowing else { return }
        hideHoverCallout()
        sync()
        // One-shot expiry, restarted by every stroke; no standing timer.
        heartExpiry?.cancel()
        heartExpiry = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.heartDuration)
            guard !Task.isCancelled, let self else { return }
            self.hearts.isShowing = false
            self.sync()
            if self.isHovering { self.showHoverCallout() }
        }
    }

    /// Show the callout by itself for `eventPopDuration` when a new event arrived. One-shot task, no standing timer.
    private func popEventIfNew() {
        guard let event = companion.latestEvent, event.seq != lastSeenEventSeq else { return }
        let shouldPop = Self.shouldPopEvent(eventSeq: event.seq, lastSeenSeq: lastSeenEventSeq,
                                            petVisible: panel?.isVisible == true, bubbleShowing: showingBubble)
        lastSeenEventSeq = event.seq   // seen either way: a missed event is not queued
        guard shouldPop else { return }
        eventPopText = event.text
        sync()   // refresh the native tooltip text too
        showHoverCallout()
        eventPopExpiry?.cancel()
        eventPopExpiry = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.eventPopDuration)
            guard !Task.isCancelled, let self else { return }
            self.eventPopText = nil
            self.sync()
            if self.isHovering { self.showHoverCallout() } else { self.hideHoverCallout() }
        }
    }

    private func hide() {
        eventPopExpiry?.cancel()
        eventPopText = nil
        heartExpiry?.cancel()
        hearts.isShowing = false
        hideHoverCallout()
        // A hidden pet comes back at home, not where it last ran to.
        runPhase = .home
        runGeneration += 1
        guard let p = panel else { return }
        p.orderOut(nil)
        p.contentView = nil
        builtAnimated = nil
    }

    private func currentHoverText() -> String {
        FloatingPetView.hoverTooltip(
            todayTokens: store.todayTotalTokens,
            limitUtilization: store.highestLimitUtilization,
            mode: store.limitDisplayMode,
            l: L(companion.language),
            sulkIdle: companion.sulkIdle,
            eventLine: eventPopText,
            prayers: companion.representativeSubject.speciesID == nil ? companion.state.eggPrayers?.count ?? 0 : 0)
    }

    /// A prayer changes the count in the hover text. Rebuild it right here instead of waiting for the observation
    /// round trip: re-set the native tooltip and redraw the callout if it is open.
    private func refreshHoverAfterPrayer() {
        if let hosting = panel?.contentView as? PetHostingView {
            hosting.toolTip = nil
            hosting.toolTip = Self.nativeToolTip(currentHoverText(), heartsShowing: hearts.isShowing)
        }
        if hoverPanel?.isVisible == true { showHoverCallout() }
    }

    private func showHoverCallout() {
        guard let pet = panel, pet.isVisible else { return }
        // Speech and hearts take priority over the hover/event callout.
        if showingBubble { hideHoverCallout(); return }
        let text = currentHoverText()
        let appearance = NSApp.effectiveAppearance
        let colors = Self.hoverCalloutColors(for: appearance)
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = colors.text
        label.backgroundColor = .clear
        label.drawsBackground = false
        label.sizeToFit()

        let pad: CGFloat = 8
        let size = NSSize(width: label.bounds.width + pad * 2,
                          height: label.bounds.height + pad * 2)
        let container = NSView(frame: NSRect(origin: .zero, size: size))
        container.appearance = appearance
        container.wantsLayer = true
        container.layer?.backgroundColor = colors.background.cgColor
        container.layer?.cornerRadius = 8
        container.layer?.borderWidth = 0.5
        container.layer?.borderColor = colors.border.cgColor
        label.frame.origin = NSPoint(x: pad, y: pad)
        container.addSubview(label)

        let hp = hoverPanel ?? makeHoverPanel()
        hoverPanel = hp
        hp.appearance = appearance
        hp.contentView = container
        hp.setContentSize(size)
        let petFrame = pet.frame
        hp.setFrameOrigin(NSPoint(x: petFrame.midX - size.width / 2, y: petFrame.maxY + 6))
        hp.orderFrontRegardless()
    }

    private func hideHoverCallout() {
        hoverPanel?.orderOut(nil)
        hoverPanel?.contentView = nil
    }

    private func makeHoverPanel() -> NSPanel {
        let p = NSPanel(contentRect: .zero,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.ignoresMouseEvents = true
        p.animationBehavior = .none
        return p
    }

    private func targetFrame(petSize: CGFloat, showingBubble: Bool) -> NSRect {
        let size = Self.panelSize(petSize: petSize, showingBubble: showingBubble)
        let petOrigin: NSPoint
        if runPhase == .away, let awayPetOrigin {
            petOrigin = awayPetOrigin
        } else if let x = defaults.object(forKey: Self.originXKey) as? Double,
           let y = defaults.object(forKey: Self.originYKey) as? Double {
            petOrigin = NSPoint(x: x, y: y)
        } else {
            petOrigin = Self.defaultPetOrigin(petSize: petSize)
        }
        var frame = NSRect(origin: Self.panelOrigin(petOrigin: petOrigin, petSize: petSize, panelSize: size),
                           size: size)
        if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) {
            let fallbackPet = Self.defaultPetOrigin(petSize: petSize)
            frame.origin = Self.panelOrigin(petOrigin: fallbackPet, petSize: petSize, panelSize: size)
        }
        return frame
    }

    private static func defaultPetOrigin(petSize: CGFloat) -> NSPoint {
        guard let visible = NSScreen.main?.visibleFrame else { return NSPoint(x: 120, y: 120) }
        return NSPoint(x: visible.maxX - petSize - 24, y: visible.minY + 24)
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isMovableByWindowBackground = false
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.becomesKeyOnlyIfNeeded = true
        p.allowsToolTipsWhenApplicationIsInactive = true
        p.animationBehavior = .none
        p.delegate = self
        return p
    }

    func windowDidMove(_ notification: Notification) {
        guard let p = panel, p.isVisible else { return }
        panelDidMove(panelOrigin: p.frame.origin,
                     userDragging: (p.contentView as? PetHostingView)?.isDragging ?? false)
        if hoverPanel?.isVisible == true { showHoverCallout() }
    }

    func panelDidMove(panelOrigin: NSPoint, userDragging: Bool) {
        let move = Self.resolveMove(phase: runPhase, userDragging: userDragging)
        if move.phase != runPhase {
            runPhase = move.phase
            runGeneration += 1   // the pending return is cancelled
            // Stop the in-flight run/return, or its remaining frames would become home.
            if let p = panel {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0
                    p.animator().setFrame(p.frame, display: false)
                }
            }
        }
        guard move.persist else { return }
        let petSize = CGFloat(store.floatingPetSize)
        let size = Self.panelSize(petSize: petSize, showingBubble: showingBubble)
        let pet = Self.petOrigin(panelOrigin: panelOrigin, petSize: petSize, panelSize: size)
        defaults.set(Double(pet.x), forKey: Self.originXKey)
        defaults.set(Double(pet.y), forKey: Self.originYKey)
    }
}

/// Routes a plain click on the pet. Praying always counts and spawns its emoji at once;
/// only the usage refresh it triggers is throttled (at growing prayer milestones, at most once per interval).
@MainActor
final class PetClickRouter {
    private let pray: () -> Void
    private let prayerCount: () -> Int
    private let didPray: () -> Void
    private let spawnEmoji: () -> Void
    private let refreshUsage: () -> Void
    private let openPopover: () -> Void
    private let clock: () -> Date
    private var lastPrayerRefreshAt: Date?
    /// In memory only: after a restart the first click past a milestone may refresh once more, which is harmless.
    private var lastRefreshedMilestone = 0

    init(pray: @escaping () -> Void, prayerCount: @escaping () -> Int, didPray: @escaping () -> Void = {}, spawnEmoji: @escaping () -> Void, refreshUsage: @escaping () -> Void,
         openPopover: @escaping () -> Void, clock: @escaping () -> Date) {
        self.pray = pray
        self.prayerCount = prayerCount
        self.didPray = didPray
        self.spawnEmoji = spawnEmoji
        self.refreshUsage = refreshUsage
        self.openPopover = openPopover
        self.clock = clock
    }

    func handle(subjectIsEgg: Bool) {
        switch FloatingPetController.clickAction(subjectIsEgg: subjectIsEgg) {
        case .pray:
            pray()
            spawnEmoji()
            didPray()
            let count = prayerCount()
            let milestone = FloatingPetController.prayerRefreshMilestone(for: count)
            if milestone < lastRefreshedMilestone { lastRefreshedMilestone = milestone }   // a new egg started over
            let now = clock()
            if FloatingPetController.shouldRefreshOnPrayer(count: count, lastRefreshedMilestone: lastRefreshedMilestone,
                                                           lastRefreshAt: lastPrayerRefreshAt, now: now) {
                lastRefreshedMilestone = milestone
                lastPrayerRefreshAt = now
                refreshUsage()
            }
        case .openPopover:
            openPopover()
        }
    }
}

final class PetHostingView: NSHostingView<AnyView> {
    var onOpenPopover: (() -> Void)?
    /// A plain click on the pet. The controller decides between praying and opening the popover.
    var onClick: (() -> Void)?
    var onStroke: (() -> Void)?
    /// Minimum horizontal travel (pt) for one stroke; scales with the pet size.
    var strokeDistance: CGFloat = 14
    private var petting = PettingDetector()
    var onHide: (() -> Void)?
    var onToggleBackView: (() -> Void)?
    var isBackViewOn: () -> Bool = { false }
    var onHoverChange: ((Bool) -> Void)?
    var languageProvider: () -> AppLanguage = { .systemDefault }

    private var mouseDownScreen: NSPoint?
    private var originAtDown: NSPoint?
    private var didDrag = false

    /// True once the pointer moved past the click threshold with the button held.
    var isDragging: Bool { didDrag }

    override var mouseDownCanMoveWindow: Bool { false }

    static func isClick(from start: NSPoint, to end: NSPoint,
                        thresholdSquared: CGFloat = FloatingPetController.clickThresholdSquared) -> Bool {
        FloatingPetController.isClick(from: start, to: end, thresholdSquared: thresholdSquared)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect],
            owner: self,
            userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { onHoverChange?(true) }
    override func mouseExited(with event: NSEvent) {
        petting.reset()
        onHoverChange?(false)
    }

    /// Tracking-area `mouseMoved` only arrives with no button pressed, so drags never count as strokes.
    override func mouseMoved(with event: NSEvent) {
        // Screen coordinates: the panel widens and re-centres when the bubble appears, which would
        // shift view-local x mid-gesture and fake or break a stroke.
        if petting.feed(x: NSEvent.mouseLocation.x, at: event.timestamp, minStroke: strokeDistance) {
            onStroke?()
        }
    }

    override func mouseDown(with event: NSEvent) {
        petting.reset()
        if event.modifierFlags.contains(.control) {
            showContextMenu(event)
            return
        }
        mouseDownScreen = NSEvent.mouseLocation
        originAtDown = window?.frame.origin
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        petting.reset()
        guard let window, let start = mouseDownScreen, let origin = originAtDown else { return }
        let now = NSEvent.mouseLocation
        if !Self.isClick(from: start, to: now) { didDrag = true }
        window.setFrameOrigin(NSPoint(x: origin.x + (now.x - start.x),
                                      y: origin.y + (now.y - start.y)))
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            mouseDownScreen = nil
            originAtDown = nil
            didDrag = false
        }
        guard !didDrag, let start = mouseDownScreen else { return }
        if Self.isClick(from: start, to: NSEvent.mouseLocation) {
            onClick?()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        showContextMenu(event)
    }

    private func showContextMenu(_ event: NSEvent) {
        onHoverChange?(false)
        NSApp.activate(ignoringOtherApps: true)
        let l = L(languageProvider())
        let menu = NSMenu(title: "")
        menu.autoenablesItems = false
        let open = menu.addItem(withTitle: l.floatingPetMenuOpen,
                                action: #selector(handleOpen(_:)), keyEquivalent: "")
        open.target = self
        open.isEnabled = true
        let hide = menu.addItem(withTitle: l.floatingPetMenuHide,
                                action: #selector(handleHide(_:)), keyEquivalent: "")
        hide.target = self
        hide.isEnabled = true
        let backView = menu.addItem(withTitle: l.backViewLabel,
                                    action: #selector(handleToggleBackView(_:)), keyEquivalent: "")
        backView.target = self
        backView.isEnabled = true
        backView.state = isBackViewOn() ? .on : .off
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc func handleOpen(_ sender: Any?) { onOpenPopover?() }
    @objc func handleHide(_ sender: Any?) { onHide?() }
    @objc func handleToggleBackView(_ sender: Any?) { onToggleBackView?() }
}

/// Agent state the controller pushes into the SwiftUI pet; already gated by the settings.
@MainActor
@Observable
final class FloatingPetAgentModel {
    var summary = AgentActivitySummary()
    var bobs = false
}

@MainActor
struct FloatingPetView: View {
    var animated: Bool = true
    var agent = FloatingPetAgentModel()
    /// Injectable so render tests stay offline and away from the real sprite cache.
    var spriteStore: SpriteStore = .shared
    var burst = PrayerBurst()
    /// Heart bubble shown after a stroke. Limit and agent speech take precedence.
    var hearts = PetHeartState()
    @Environment(UsageStore.self) private var store
    @Environment(CompanionStore.self) private var companion
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let size = CGFloat(store.floatingPetSize)
        let subject = companion.representativeSubject
        let bubble = FloatingPetController.bubble(limitAlert: store.currentBubbleAlert, agent: agent.summary)
        VStack(spacing: FloatingPetController.bubbleSpacing) {
            if let bubble {
                let content = FloatingPetController.bubbleContent(bubble, l: L(companion.language))
                SpeechBubbleView(content: content,
                                 animates: FloatingPetController.allowsMotion(animated: animated,
                                                                              reduceMotion: reduceMotion))
                    .id(content)   // a new message replays the reveal
                    .transition(.scale(scale: 0.8, anchor: .bottom).combined(with: .opacity))
                    .zIndex(1)
            }

            SpriteView(speciesID: subject.speciesID, size: size, animated: animated,
                       shiny: subject.isShiny,
                       minFrameDelay: store.animationQuality.frameFloor, spriteStore: spriteStore, form: subject.form,
                       back: companion.facesBack, reportsVisibleTop: true)
                // One-shot wobble per prayer; keyframes run once per trigger change, never in a loop.
                .keyframeAnimator(initialValue: 0.0, trigger: burst.wobbleCount) { sprite, angle in
                    sprite.rotationEffect(.degrees(angle))
                } keyframes: { _ in
                    KeyframeTrack {
                        LinearKeyframe(-9.0, duration: 0.06)
                        LinearKeyframe(9.0, duration: 0.10)
                        LinearKeyframe(-5.0, duration: 0.08)
                        LinearKeyframe(0.0, duration: 0.06)
                    }
                }
                .frame(width: size, height: size)
                .overlay { PrayerEmojiLayer(burst: burst, size: size, animated: animated) }
                // Hearts hug the visible top of the sprite (not its box). Insertion pops in; removal is
                // instant, because the panel shrinks at the same moment and a fading bubble would be
                // drawn lower, over the pet.
                .overlayPreferenceValue(SpriteVisibleTopKey.self, alignment: .top) { visibleTop in
                    if hearts.isShowing, bubble == nil {
                        HeartBubbleView(l: L(companion.language))
                            .offset(y: SpriteVisibleTop.bubbleTopOffset(
                                visibleTop: visibleTop ?? 0,
                                bubbleHeight: HeartBubbleArt.height,
                                overlap: HeartBubbleArt.tailOverlap))
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.8, anchor: .bottom).combined(with: .opacity),
                                removal: .identity))
                            .allowsHitTesting(false)
                    }
                }
                // Keep the attached heart and prayer particles aligned with the bobbing sprite.
                .modifier(AgentBob(active: agent.bobs))
                .zIndex(0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .animation(animated ? .spring(response: 0.3, dampingFraction: 0.7) : nil,
                   value: bubble)
        .animation(animated ? .spring(response: 0.3, dampingFraction: 0.7) : nil,
                   value: hearts.isShowing)
    }

    /// `sulkIdle` > 0 appends how long the companion has been sulking: hours below 48 h, days from there.
    static func hoverTooltip(todayTokens: Int, limitUtilization: Double?,
                             mode: UsageStore.LimitDisplayMode, l: L, sulkIdle: TimeInterval = 0,
                             eventLine: String? = nil, prayers: Int = 0) -> String {
        let usage = TokenFormatter.grouped(todayTokens)
        var base = l.floatingPetHoverTokensOnly(usage)
        if let pct = limitUtilization {
            let percent = TokenFormatter.percent(UsageStore.displayPercent(pct, mode: mode))
            base = l.floatingPetHoverWithLimit(usage, mode == .remaining ? l.percentRemaining(percent) : percent)
        }
        if sulkIdle > 0 {
            let hours = Int(sulkIdle / 3600)
            base += " · " + (hours < 48 ? l.floatingPetHoverSulkHours(hours) : l.floatingPetHoverSulkDays(hours / 24))
        }
        if let eventLine { base += "\n" + eventLine }
        return prayers > 0 ? base + "\n" + l.prayerHoverLine(prayers) : base
    }
}

/// The 🙏 particles floating up from the egg. Each one removes itself after `lifetime`; no standing timer.
/// Pure presentation state: it never touches an RNG that feeds a hatch roll.
@MainActor @Observable
final class PrayerBurst {
    struct Particle: Identifiable, Equatable {
        let id = UUID()
        /// 0...1 across the usable width of the pet (the emoji's own width is already excluded).
        let xFraction: Double
    }

    /// A little longer than the 1 s float-and-fade, so a particle is gone only once it is invisible.
    static let lifetime: Duration = .milliseconds(1100)

    private(set) var particles: [Particle] = []
    /// Bumped on every prayer; the egg wobbles once per change.
    private(set) var wobbleCount = 0

    func spawn(xFraction: Double = .random(in: 0...1)) {
        let particle = Particle(xFraction: min(max(xFraction, 0), 1))
        particles.append(particle)
        wobbleCount += 1
        Task {
            try? await Task.sleep(for: Self.lifetime)
            particles.removeAll { $0.id == particle.id }
        }
    }
}

/// Draws the particles inside the pet's own frame, so the transparent panel never needs to grow.
@MainActor
struct PrayerEmojiLayer: View {
    let burst: PrayerBurst
    let size: CGFloat
    let animated: Bool

    /// Emoji edge for a pet size (clamped so it stays legible at 48 pt and modest at 384 pt).
    static func emojiSize(petSize: CGFloat) -> CGFloat { min(max(petSize * 0.25, 14), 32) }

    var body: some View {
        let emojiSize = Self.emojiSize(petSize: size)
        ZStack {
            ForEach(burst.particles) { particle in
                PrayerEmoji(xFraction: particle.xFraction, petSize: size, emojiSize: emojiSize)
            }
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
    }
}

/// One particle at a fixed point of its flight (`progress` 0 = just spawned, 1 = gone).
@MainActor
struct PrayerEmojiFrame: View {
    let xFraction: Double
    let petSize: CGFloat
    let emojiSize: CGFloat
    let progress: Double

    var body: some View {
        // Centre x keeps the glyph fully inside [0, petSize]; it rises from the lower middle to the top edge.
        let x = emojiSize / 2 + CGFloat(xFraction) * (petSize - emojiSize)
        let startY = petSize * 0.7
        let endY = emojiSize / 2
        Text("🙏")
            .font(.system(size: emojiSize * 0.8))
            .frame(width: emojiSize, height: emojiSize)
            .position(x: x, y: startY + (endY - startY) * CGFloat(progress))
            .opacity(1 - progress)
    }
}

@MainActor
private struct PrayerEmoji: View {
    let xFraction: Double
    let petSize: CGFloat
    let emojiSize: CGFloat
    @State private var progress = 0.0

    var body: some View {
        PrayerEmojiFrame(xFraction: xFraction, petSize: petSize, emojiSize: emojiSize, progress: progress)
            .onAppear { withAnimation(.easeOut(duration: 1)) { progress = 1 } }
    }
}

/// Two-frame squash toward the feet while an agent works, like the menu bar's static bob: no
/// interpolation, so the loop costs two redraws a second. A hop would clip — the panel is
/// sprite-tall. The state lives here so a tick re-runs only this modifier, not the pet's body
/// (sprite lookup, bubble measuring).
@MainActor
private struct AgentBob: ViewModifier {
    let active: Bool
    @State private var squashed = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(x: squashed ? 1.03 : 1, y: squashed ? 0.94 : 1, anchor: .bottom)
            .task(id: active) {
                squashed = false
                guard active else { return }   // idle leaves no loop behind
                let interval = FloatingPetController.agentBobInterval
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(interval), tolerance: .seconds(interval * 0.1))
                    guard !Task.isCancelled else { return }
                    squashed.toggle()
                }
            }
    }
}

/// Classic 8-bit dialogue box for limit alerts and agent messages: square white box, black
/// double frame with a Poké Ball at each corner, ▼ indicator. Drawn in code as whole-point rectangles (no
/// strokes), so edges stay crisp at 1× and 2×, and with fixed colors so it reads the same in
/// light and dark mode. Width is capped so copy wraps instead of clipping the panel.
/// The reveal/blink state lives here, so its ticks re-run only this view.
@MainActor
struct SpeechBubbleView: View {
    let content: FloatingPetController.SpeechBubbleContent
    let animates: Bool
    @State private var revealed: Int
    @State private var indicatorVisible = true

    private static let ink = Color(white: 0.06)
    private static let paper = Color.white
    private static let titleColor = Color(white: 0.08)
    private static let criticalColor = Color(red: 0.80, green: 0.12, blue: 0.12)
    /// Monochrome like a Game Boy screen. Not 0.5: an ink/white edge on a half point blends
    /// to about 0.53, and the crisp-frame test must tell that blur from the ball.
    private static let ballGrey = Color(white: 0.45)
    private static let bodyColor = Color(white: 0.18)

    init(content: FloatingPetController.SpeechBubbleContent, animates: Bool) {
        self.content = content
        self.animates = animates
        _revealed = State(initialValue: animates ? 0 : content.title.count + content.body.count)
    }

    var body: some View {
        let titleCount = content.title.count
        VStack(alignment: .leading, spacing: 2) {
            Self.reveal(content.title, upTo: revealed)
                .font(Font(FloatingPetController.bubbleTitleFont))
                .foregroundColor(content.isCritical ? Self.criticalColor : Self.titleColor)
            Self.reveal(content.body, upTo: revealed - titleCount)
                .font(Font(FloatingPetController.bubbleBodyFont))
                .foregroundColor(Self.bodyColor)
                .lineLimit(FloatingPetController.bubbleBodyLineLimit)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: FloatingPetController.bubbleContentWidth, alignment: .leading)
        .padding(.horizontal, FloatingPetController.bubbleHorizontalPadding)
        .padding(.top, FloatingPetController.bubbleTopPadding)
        .padding(.bottom, FloatingPetController.bubbleBottomPadding)
        .background(Canvas { context, size in
            Self.drawFrame(in: &context, width: size.width.rounded(.down), height: size.height.rounded(.down))
        })
        .overlay(alignment: .bottomTrailing) {
            Canvas { context, _ in
                for rect in Self.indicatorRects { context.fill(Path(rect), with: .color(Self.ink)) }
            }
            .frame(width: 7, height: 4)
            .opacity(indicatorVisible ? 1 : 0)
            .padding(.trailing, 11)
            .padding(.bottom, 9)
        }
        .task { await play() }
    }

    /// The unrevealed rest is laid out but clear, so lines never re-wrap while typing.
    private static func reveal(_ text: String, upTo count: Int) -> Text {
        let shown = max(0, min(count, text.count))
        return Text(text.prefix(shown)) + Text(text.dropFirst(shown)).foregroundColor(.clear)
    }

    /// Outer line at 3 pt, 1 pt gap, inner line (2 pt top/bottom, 1 pt sides), and a 10 pt
    /// Poké Ball centered where the lines meet at each corner. Outside the outer line stays clear.
    private static func drawFrame(in context: inout GraphicsContext, width w: CGFloat, height h: CGFloat) {
        let paper = CGRect(x: 3, y: 3, width: w - 6, height: h - 6)
        let ink = [
            CGRect(x: 10, y: 3, width: w - 20, height: 1), CGRect(x: 10, y: h - 4, width: w - 20, height: 1),
            CGRect(x: 3, y: 10, width: 1, height: h - 20), CGRect(x: w - 4, y: 10, width: 1, height: h - 20),
            CGRect(x: 10, y: 5, width: w - 20, height: 2), CGRect(x: 10, y: h - 7, width: w - 20, height: 2),
            CGRect(x: 5, y: 10, width: 1, height: h - 20), CGRect(x: w - 6, y: 10, width: 1, height: h - 20),
        ]
        context.fill(Path(paper), with: .color(Self.paper))
        for rect in ink { context.fill(Path(rect), with: .color(Self.ink)) }
        for origin in [CGPoint(x: 0, y: 0), CGPoint(x: w - 10, y: 0), CGPoint(x: 0, y: h - 10), CGPoint(x: w - 10, y: h - 10)] {
            for (rect, color) in pokeBall {
                context.fill(Path(rect.offsetBy(dx: origin.x, dy: origin.y)), with: .color(color))
            }
        }
    }

    /// The corner ornament: a 10 pt pixel-art Poké Ball drawn here row by row — no image asset.
    /// `#` ink, `g` grey, `w` white, `.` clear. Runs of one color become one rectangle.
    private static let pokeBall: [(CGRect, Color)] = {
        let rows = [
            "..######..",
            ".#gggggg#.",
            "#gggggggg#",
            "#ggg##ggg#",
            "####ww####",
            "####ww####",
            "#www##www#",
            "#wwwwwwww#",
            ".#wwwwww#.",
            "..######..",
        ]
        let colors: [Character: Color] = ["#": ink, "g": ballGrey, "w": paper]
        var runs: [(CGRect, Color)] = []
        for (y, row) in rows.enumerated() {
            let cells = Array(row)
            var x = 0
            while x < cells.count {
                var end = x
                while end + 1 < cells.count, cells[end + 1] == cells[x] { end += 1 }
                if let color = colors[cells[x]] {
                    runs.append((CGRect(x: x, y: y, width: end - x + 1, height: 1), color))
                }
                x = end + 1
            }
        }
        return runs
    }()

    /// Solid ▼, one row per point: 7, 5, 3, 1.
    private static let indicatorRects = (0..<4).map {
        CGRect(x: CGFloat($0), y: CGFloat($0), width: CGFloat(7 - 2 * $0), height: 1)
    }

    /// Bounded: the reveal takes at most 24 ticks and the blink stops after `dialogueBlinkLimit`.
    private func play() async {
        guard animates else { return }
        let total = content.title.count + content.body.count
        let steps = FloatingPetController.typewriterSteps(characterCount: total)
        let tick = FloatingPetController.typewriterTick
        for step in 1...steps {
            try? await Task.sleep(for: .seconds(tick))
            guard !Task.isCancelled else { return }
            revealed = FloatingPetController.revealedCount(step: step, of: steps, characterCount: total)
        }
        let interval = FloatingPetController.dialogueBlinkInterval
        for _ in 0..<Int(FloatingPetController.dialogueBlinkLimit / interval) {
            try? await Task.sleep(for: .seconds(interval), tolerance: .seconds(interval * 0.1))
            guard !Task.isCancelled else { return }
            indicatorVisible.toggle()
        }
        indicatorVisible = true
    }
}

/// Detects a back-and-forth stroking motion from horizontal mouse samples. Pure, so it is
/// unit-testable without AppKit events (same style as `FloatingPetController.isClick`).
struct PettingDetector {
    /// Direction reversals needed within `window` to count as stroking.
    static let requiredReversals = 3
    static let window: TimeInterval = 1.2

    private var direction: CGFloat = 0      // 0 = not moving far enough yet, else -1 / +1
    private var extremeX: CGFloat = 0       // furthest x reached in the current direction
    private var lastTimestamp: TimeInterval?
    private var reversalTimes: [TimeInterval] = []

    mutating func reset() { self = PettingDetector() }

    /// Feed one mouse sample. Returns true when this sample completes a reversal and the
    /// recent wiggle has at least `requiredReversals` of them. Every stroke must travel
    /// `minStroke` points, so jitter and slow drifting never reverse.
    mutating func feed(x: CGFloat, at time: TimeInterval, minStroke: CGFloat) -> Bool {
        guard let last = lastTimestamp, time - last <= Self.window else {
            reset()
            lastTimestamp = time
            extremeX = x
            return false
        }
        lastTimestamp = time
        reversalTimes.removeAll { time - $0 > Self.window }

        if direction == 0 {
            guard abs(x - extremeX) >= minStroke else { return false }
            direction = x > extremeX ? 1 : -1
            extremeX = x
            return false
        }
        if (x - extremeX) * direction > 0 {     // still travelling the same way
            extremeX = x
            return false
        }
        guard (extremeX - x) * direction >= minStroke else { return false }
        direction = -direction
        extremeX = x
        reversalTimes.append(time)
        return reversalTimes.count >= Self.requiredReversals
    }
}

/// Whether the heart bubble is up. Owned by the controller so the hosted view is built once and only observes this.
@MainActor @Observable
final class PetHeartState {
    var isShowing = false
}

/// Pixel-art layout of the heart bubble, so it matches the Gen-V pixel sprites.
/// One character per pixel: `.` empty, `O` outline, `W` fill, `R` heart, `D` heart shade, `H` heart highlight.
/// A 2-step rounded bubble with its tail at the bottom center.
enum HeartBubbleArt {
    /// Pixel unit in points; an integer so edges stay crisp on 1x and 2x displays.
    static let pixel: CGFloat = 2
    static let rows = [
        "..OOOOOOOOOOOOO..",
        ".OWWWWWWWWWWWWWO.",
        "OWWWWWWWWWWWWWWWO",
        "OWWWWRRRWRRRWWWWO",
        "OWWWRHHRRRRRRWWWO",
        "OWWWRHRRRRRRDWWWO",
        "OWWWRRRRRRRRDWWWO",
        "OWWWWRRRRRRDWWWWO",
        "OWWWWWRRRRDWWWWWO",
        "OWWWWWWRRDWWWWWWO",
        "OWWWWWWWDWWWWWWWO",
        "OWWWWWWWWWWWWWWWO",
        ".OWWWWWWWWWWWWWO.",
        "..OOOOOWWWOOOOO..",
        ".......OWO.......",
        "........O........",
    ]

    static var height: CGFloat { CGFloat(rows.count) * pixel }
    /// How far the tail tip sticks into the sprite's visible top (pt).
    static let tailOverlap: CGFloat = 3

    static func color(for cell: Character) -> Color? {
        switch cell {
        case "O": Color(red: 0x20 / 255, green: 0x20 / 255, blue: 0x20 / 255)
        case "W": Color.white
        case "R": Color(red: 0xE0 / 255, green: 0x30 / 255, blue: 0x3C / 255)
        case "D": Color(red: 0xA8 / 255, green: 0x20 / 255, blue: 0x2C / 255)
        case "H": Color(red: 0xFF / 255, green: 0x9A / 255, blue: 0xA2 / 255)
        default: nil
        }
    }
}

/// Transient heart shown after stroking the pet: a pixel-art speech bubble drawn on an integer grid.
/// Same colors in light and dark mode (game style).
@MainActor
struct HeartBubbleView: View {
    let l: L

    var body: some View {
        let rows = HeartBubbleArt.rows
        let pixel = HeartBubbleArt.pixel
        Canvas { context, _ in
            for (y, row) in rows.enumerated() {
                for (x, cell) in row.enumerated() {
                    guard let color = HeartBubbleArt.color(for: cell) else { continue }
                    context.fill(Path(CGRect(x: CGFloat(x) * pixel, y: CGFloat(y) * pixel,
                                             width: pixel, height: pixel)),
                                 with: .color(color))
                }
            }
        }
        .frame(width: CGFloat(rows[0].count) * pixel, height: HeartBubbleArt.height)
        .accessibilityLabel(l.floatingPetHeartsLabel)
    }
}
