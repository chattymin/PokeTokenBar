import AppKit
import QuartzCore
import SwiftUI

/// 데스크톱 위에 떠 있는 컴패니언 포켓몬 오버레이(옵트인, 설정 → 플로팅 펫).
/// - 드래그: 커스텀 `mouseDragged` (클릭과 충돌하지 않음).
/// - 클릭 → 알 기도 / 포켓몬 팝오버, 우클릭 → 메뉴, 호버 → 오늘 사용량 콜아웃.
/// - Limit-alert speech bubbles grow the panel; persisted origin is the *pet*, not the panel.
/// - Agent activity (`poketokenbar://agent`): bob while working, bubble while waiting,
///   run to the cursor when done. The run never moves the saved home.
/// - Hatch/evolve sequences play live on the pet whenever it is shown, in sync with an open popover: the subject
///   being celebrated replaces a pinned one, the caption goes in the bubble, a click skips.
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

    private static let originXKey = "floatingPetOriginX"
    private static let originYKey = "floatingPetOriginY"

    /// Squared movement (pt²) below which a mouse-up counts as a click, not a drag.
    static let clickThresholdSquared: CGFloat = 16  // ~4pt

    /// Vertical space above the sprite for the bubble + VStack spacing (pt).
    /// Sized for two wrapped body lines + title + padding + tail (ja strings).
    static let bubbleHeadroom: CGFloat = 72
    /// Minimum panel width while a bubble is showing.
    static let bubbleMinWidth: CGFloat = 180
    /// Horizontal padding inside the bubble chrome (each side). Content + 2× this = `bubbleMinWidth`.
    static let bubbleHorizontalPadding: CGFloat = 8
    /// Fixed text column — wraps instead of growing past the panel (`bubbleMinWidth` − 16).
    static let bubbleContentWidth: CGFloat = bubbleMinWidth - (bubbleHorizontalPadding * 2)
    /// `SpeechBubbleView` body `.lineLimit`. Measure and view must share this — a
    /// headroom-only guard stays green for 3-line copy that still fits 70pt (#167).
    static let bubbleBodyLineLimit = 2

    /// An untitled bubble (the pet speaking a celebration line) gives the freed title row to its body,
    /// so a long Russian reveal line keeps the name of what it became.
    static func bodyLineLimit(titled: Bool) -> Int { titled ? bubbleBodyLineLimit : bubbleBodyLineLimit + 1 }

    /// Run to the cursor / back home.
    static let agentRunDuration: TimeInterval = 0.6
    /// Distance between the cursor and the panel after a run, so the pet never sits under the pointer.
    static let agentRunCursorGap: CGFloat = 16
    /// Half a bob cycle while an agent works. Must stay > 0: it is the frame cap of this loop.
    static let agentBobInterval: TimeInterval = 0.5
    /// Frame cap of a hatch/evolve sequence's effects on the pet (30 fps). The popover draws them every
    /// display frame; this surface is always on, so it keeps a named cap above 0 (defect-log §에너지).
    /// The GIF frames inside still follow the user's `animationQuality.frameFloor`.
    static let celebrationFrameInterval: TimeInterval = 1.0 / 30

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

    static func shouldBob(working: Bool, motionAllowed: Bool) -> Bool {
        motionAllowed && working
    }

    /// The one bubble the pet shows. A limit alert outranks agent messages.
    enum Bubble: Equatable {
        case limit(UsageStore.LimitAlert)
        case agentWaiting(label: String?, message: String?, others: Int)
        case agentDone(label: String?, message: String?)
        /// The caption of the hatch/evolve sequence playing on the pet.
        case celebration(String)
    }

    /// A critical limit alert outranks the playing celebration's caption, which outranks a warning and
    /// agents; among agents a fresh `done` outranks waiting.
    static func bubble(limitAlert: UsageStore.LimitAlert?, agent: AgentActivitySummary,
                       celebration: String? = nil) -> Bubble? {
        if let limitAlert, limitAlert.isCritical { return .limit(limitAlert) }
        if let celebration { return .celebration(celebration) }
        if let limitAlert { return .limit(limitAlert) }
        if let done = agent.done { return .agentDone(label: done.label, message: done.message) }
        if let waiting = agent.waiting {
            return .agentWaiting(label: waiting.label, message: waiting.message, others: agent.otherWaitingCount)
        }
        return nil
    }

    struct SpeechBubbleContent: Equatable {
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
        case .agentDone(let label, let message):
            let title = agentTitle(label: label, unlabeled: l.agentDoneTitle, status: l.agentDoneStatus, count: nil)
            return agentContent(title: title, body: message ?? l.agentDoneDefaultBody)
        case .celebration(let line):
            // The pet speaking: no title, the line itself in the body's two lines.
            return SpeechBubbleContent(title: "", body: fittedBubbleBody(line, title: ""), isCritical: false)
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

    /// Speech takes priority over hearts: limit alert, celebration, agent done, agent waiting, then a stroke.
    static func heartsShowing(afterStrokeWithAlertActive alertActive: Bool,
                              agent: AgentActivitySummary = .init(), celebration: String? = nil) -> Bool {
        !alertActive && bubble(limitAlert: nil, agent: agent, celebration: celebration) == nil
    }

    /// Reserve headroom for either speech or hearts, including agent-only and celebration speech.
    static func isShowingBubble(alertActive: Bool, heartsShowing: Bool,
                                agent: AgentActivitySummary = .init(), celebration: String? = nil) -> Bool {
        alertActive || bubble(limitAlert: nil, agent: agent, celebration: celebration) != nil || heartsShowing
    }

    // MARK: Celebrations (pure)

    /// The pet plays sequences only while it is enabled, actually on screen, the display is awake and
    /// someone can see it (no lock screen, screensaver or switched-out user session).
    static func isLive(enabled: Bool, panelVisible: Bool, displayAwake: Bool, sessionInteractive: Bool) -> Bool {
        enabled && panelVisible && displayAwake && sessionInteractive
    }

    /// What the login session looks like right now. `NSWindow.isVisible` stays true behind a lock screen
    /// or another user's session, so this is read separately.
    struct SessionState: Equatable {
        var screenLocked = false
        var onConsole = true

        /// Read from the system, not remembered from notifications: `CGSessionCopyCurrentDictionary`
        /// (lock flag, console ownership).
        static func current() -> SessionState {
            let session = CGSessionCopyCurrentDictionary() as? [String: Any]
            return SessionState(
                screenLocked: session?["CGSSessionScreenIsLocked"] as? Bool ?? false,
                onConsole: session?["kCGSSessionOnConsoleKey"] as? Bool ?? true)
        }
    }

    /// The session notifications the pet (and through it the popover) follows.
    enum SessionNotice: Equatable {
        case locked, unlocked, screensaverStarted, screensaverStopped, resignedActive, becameActive

        /// The "un-" side: the session may lag behind it, so one re-check follows a moment later.
        var endsInterruption: Bool {
            switch self {
            case .unlocked, .screensaverStopped, .becameActive: true
            case .locked, .screensaverStarted, .resignedActive: false
            }
        }
    }

    /// `screensaverRunning`: a flag set and cleared by the screensaver's own start/stop notifications (its
    /// engine process is still listed when `didstop` arrives, so a process scan kept the pet hidden).
    /// `startNoticed`: a lock / session-resign notification triggered this check, so it counts as
    /// non-interactive even if the session state lags behind it. Every later check trusts the session state,
    /// so a missed "un-" notification never keeps the pet down.
    static func sessionInteractive(_ state: SessionState, screensaverRunning: Bool, startNoticed: Bool) -> Bool {
        !startNoticed && !screensaverRunning && !state.screenLocked && state.onConsole
    }

    /// Who the pet is showing: the subject a pending hatch/evolve presents (`CelebrationPresentation`, shared
    /// with the popover), even when the user pinned another species; without one, the pinned or live one.
    static func displayedSubject(representative: CompanionStore.RepresentativeSubject,
                                 presentation: CelebrationPresentation?) -> CompanionStore.RepresentativeSubject {
        switch presentation {
        case .egg?: CompanionStore.RepresentativeSubject(speciesID: nil, isShiny: false)
        case .subject(let s)?: CompanionStore.RepresentativeSubject(speciesID: s.speciesID, isShiny: s.isShiny, form: s.form)
        case nil: representative
        }
    }

    /// What the pet presents for the queue: no result before its sequence is seen, across a whole chain.
    /// `liveSpeciesID`: the companion's species in the store now (nil for an egg), whatever the pet represents.
    static func presentation(queue: CelebrationQueue, player: CelebrationPlayer,
                             liveSpeciesID: Int?) -> CelebrationPresentation? {
        CelebrationPresentation.shown(queue: queue, playing: player.item, text: player.text, surface: .floatingPet,
                                      liveSpeciesID: liveSpeciesID)
    }

    /// The subject on the pet with the queue taken into account.
    static func displayedSubject(representative: CompanionStore.RepresentativeSubject, queue: CelebrationQueue,
                                 player: CelebrationPlayer, liveSpeciesID: Int?) -> CompanionStore.RepresentativeSubject {
        displayedSubject(representative: representative,
                         presentation: presentation(queue: queue, player: player, liveSpeciesID: liveSpeciesID))
    }

    /// The caption of the playing sequence in `language`; nil between lines or at rest.
    static func celebrationCaption(player: CelebrationPlayer, language: AppLanguage) -> String? {
        player.item.flatMap { L(language).celebrationText(player.text, kind: $0.kind) }
    }

    /// What the pet's player does about the queue.
    enum CelebrationStep: Equatable {
        case keep
        case play(PendingCelebration)
        case stop
    }

    /// The pet plays the queue head whenever it is live, the popover open or not: both surfaces then play it at
    /// the same time, and the first to reach its end marks it seen. The popover closing mid-sequence changes
    /// nothing here (no restart). When the head moves on (seen on the popover, or the queue was reset) the pet
    /// follows or stops. Not live means the pet was hidden or put to sleep, and `hide()` already stopped it.
    static func celebrationStep(petLive: Bool, head: PendingCelebration?, playingID: Int?) -> CelebrationStep {
        guard petLive else { return .keep }
        guard let head else { return playingID == nil ? .keep : .stop }
        return head.id == playingID ? .keep : .play(head)
    }

    /// Pause between the resting egg's one-shot wobbles; nil = no wobble task at all (not a resting egg,
    /// early tier, hidden or asleep, Low Power or Reduce Motion).
    static func eggWobbleInterval(restingEgg: Bool, progress: Double, motionAllowed: Bool,
                                  panelVisible: Bool) -> Duration? {
        guard restingEgg, motionAllowed, panelVisible else { return nil }
        return EggIncubationTier.tier(progress: progress).wobbleInterval
    }

    /// The egg's incubation tier for the hover text; nil when the pet shows a Pokémon. An egg presented by a
    /// pending hatch is already past the store (its progress is the next egg's), so it reads as imminent.
    static func eggTierLine(subject: CompanionStore.RepresentativeSubject, presentation: CelebrationPresentation?,
                            eggProgress: Double, l: L) -> String? {
        guard subject.speciesID == nil else { return nil }
        let tier: EggIncubationTier = presentation == .egg ? .imminent : .tier(progress: eggProgress)
        return tier.text(l)
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
    /// Plays the hatch/evolve sequences on the pet. Owned here, not by the hosted view, so a hosting
    /// rebuild (Low Power toggle) keeps the sequence where it is.
    let celebrationPlayer: CelebrationPlayer
    private let spriteStore: SpriteStore
    /// The resting egg's periodic one-shot wobbles (see `eggWobbleInterval`).
    private lazy var eggWobbles = EggWobbleDriver { [weak self] in self?.prayerBurst.nudge() }
    /// Tests pin motion on or off (the hosted view's animations included); nil follows Low Power Mode and
    /// Reduce Motion.
    private let motionOverride: Bool?
    /// Owned here and handed to the view once, so a prayer never rebuilds the hosting `rootView`.
    let prayerBurst = PrayerBurst()
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
         motionOverride: Bool? = nil, celebrationPlayer: CelebrationPlayer? = nil,
         spriteStore: SpriteStore = .shared,
         sessionProbe: @escaping @MainActor () -> SessionState = { SessionState.current() },
         sessionRecheckWait: @escaping @MainActor () async throws -> Void = { try await Task.sleep(for: .seconds(1)) }) {
        self.clock = clock
        self.sessionProbe = sessionProbe
        self.sessionRecheckWait = sessionRecheckWait
        self.celebrationPlayer = celebrationPlayer ?? CelebrationPlayer()
        self.spriteStore = spriteStore
        self.store = store
        self.companion = companion
        self.defaults = defaults
        self.motionOverride = motionOverride
        self.onOpenPopover = onOpenPopover
        self.onHide = onHide
        super.init()
        lastSeenEventSeq = companion.latestEvent?.seq   // an event from before the pet existed is not news
        observeSettings()
        observePowerState()
        observeReduceMotion()
        observeSession()
        sync()
    }

    static func isClick(from start: NSPoint, to end: NSPoint,
                        thresholdSquared: CGFloat = clickThresholdSquared) -> Bool {
        let dx = end.x - start.x, dy = end.y - start.y
        return dx * dx + dy * dy < thresholdSquared
    }

    func setDisplayAwake(_ awake: Bool) {
        displayAwake = awake
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
            _ = companion.celebrations       // a new sequence to play (or the queue moved on)
            _ = companion.liveSurfaces       // the popover opened or closed
            _ = companion.celebrationPlayback   // the popover joined or skipped the shared item
            _ = celebrationPlayer.item       // panel room for the effects
            _ = celebrationPlayer.text       // the caption bubble needs headroom
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

    private var sessionObservers: [(NotificationCenter, NSObjectProtocol)] = []
    /// Set by a start notification for the one `sync()` it triggers (see `sessionInteractive`).
    private var sessionStartNoticed = false
    /// Between the screensaver's `didstart` and `didstop` (see `sessionInteractive`).
    private var screensaverRunning = false
    private let sessionProbe: @MainActor () -> SessionState
    /// How long the one-shot re-check waits (~1 s); injectable so tests decide when it fires.
    private let sessionRecheckWait: @MainActor () async throws -> Void
    /// The one-shot re-check after an "un-" notification; nil when none is pending (never a repeating timer).
    private var sessionRecheck: Task<Void, Never>?
    var sessionRecheckPending: Bool { sessionRecheck != nil }
    /// Whether someone can see the screen, as of the last `sync()`. The popover is live only while
    /// this holds too (`CelebrationQueue.popoverLive`); `onSessionInteractiveChange` reports each change.
    private(set) var sessionInteractive = true
    var onSessionInteractiveChange: (@MainActor (Bool) -> Void)?

    /// Lock screen, screensaver and fast user switching. The lock and user-switch notifications only trigger
    /// a re-check, `sync()` reads the session every time (`sessionProbe`); the screensaver sets its flag.
    private func observeSession() {
        let distributed = DistributedNotificationCenter.default()
        let workspace = NSWorkspace.shared.notificationCenter
        let events: [(NotificationCenter, Notification.Name, SessionNotice)] = [
            (distributed, Notification.Name("com.apple.screenIsLocked"), .locked),
            (distributed, Notification.Name("com.apple.screenIsUnlocked"), .unlocked),
            (distributed, Notification.Name("com.apple.screensaver.didstart"), .screensaverStarted),
            (distributed, Notification.Name("com.apple.screensaver.didstop"), .screensaverStopped),
            (workspace, NSWorkspace.sessionDidResignActiveNotification, .resignedActive),
            (workspace, NSWorkspace.sessionDidBecomeActiveNotification, .becameActive),
        ]
        sessionObservers = events.map { center, name, notice in
            (center, center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.sessionDidChange(notice) }
            })
        }
    }

    /// A session notification arrived: re-check now, and once more shortly after an "un-" notification.
    func sessionDidChange(_ notice: SessionNotice) {
        switch notice {
        case .screensaverStarted: screensaverRunning = true; sessionStartNoticed = true
        case .screensaverStopped: screensaverRunning = false
        case .locked, .resignedActive: sessionStartNoticed = true
        case .unlocked, .becameActive: break
        }
        sync()
        if notice.endsInterruption { scheduleSessionRecheck() }
    }

    /// The session dictionary can still read locked when the unlock notification arrives, and nothing else
    /// would look again while the pet is hidden: one cancellable one-shot `sync()` heals a stale read.
    private func scheduleSessionRecheck() {
        sessionRecheck?.cancel()
        let wait = sessionRecheckWait
        sessionRecheck = Task { @MainActor [weak self] in
            do { try await wait() } catch { return }
            guard let self else { return }
            self.sessionRecheck = nil
            self.sync()
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

    /// The same rule as the popover (`MotionSettings`): no Reduce Motion and no Low Power.
    private var motionAllowed: Bool {
        motionOverride ?? !MotionSettings.system.reduced
    }

    private var agentEnabled: Bool { store.floatingPetEnabled && store.floatingPetAgentActivity }

    var isBobbing: Bool { agentModel.bobs }

    // MARK: Agent activity

    /// Entry point for `poketokenbar://agent` URLs. Dropped while the pet or the setting is off.
    func handleAgentEvent(_ event: AgentActivityEvent) {
        guard agentEnabled else { return }
        tracker.apply(event, now: Date())
        agentDidChange()
    }

    private func agentDidChange() {
        let summary = tracker.summary
        agentModel.summary = summary
        agentModel.bobs = Self.shouldBob(working: summary.working, motionAllowed: motionAllowed)
        scheduleAgentExpiry()
        if summary.done != nil {
            if let p = panel, Self.runsToCursor(phase: runPhase, motionAllowed: motionAllowed, panelVisible: p.isVisible) {
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
        agentTimer?.invalidate()
        agentTimer = nil
        agentModel.summary = AgentActivitySummary()
        agentModel.bobs = false
        runPhase = .home
        runGeneration += 1
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
        let size = Self.panelSize(petSize: petSize, showingBubble: true, celebrating: celebrating)
        let origin = Self.runPanelOrigin(cursor: cursor, panelSize: size, visibleFrame: visibleFrame)
        runPhase = .away
        _ = updateLayout()   // the run's frame step: the agent's bubble switches with it
        awayPetOrigin = Self.petOrigin(panelOrigin: origin, petSize: petSize, panelSize: size, celebrating: celebrating)
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
        _ = updateLayout()   // the run's frame step: the agent's bubble switches with it
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
    /// While a sequence plays, a click only skips it to the reveal.
    func petClicked() {
        if celebrationPlayer.item != nil {
            celebrationPlayer.skip()
            return
        }
        if tracker.dismissBubble() { agentDidChange() }
        clickRouter.handle(subjectIsEgg: displayedSubject.speciesID == nil)
    }

    /// Context-menu Open always opens, including when the representative is an egg.
    private func openPopover() {
        if tracker.dismissBubble() { agentDidChange() }
        onOpenPopover?()
    }

    /// Panel size for a given pet size and bubble visibility. Pure — tested without AppKit layout.
    /// A playing sequence widens the panel by the stage's effects margin on each side and adds it on top;
    /// the pet keeps standing on the bottom edge, so `panelOrigin`/`petOrigin` keep it in place.
    static func panelSize(petSize: CGFloat, showingBubble: Bool, celebrating: Bool = false) -> NSSize {
        var size = showingBubble ? NSSize(width: max(petSize, bubbleMinWidth), height: petSize + bubbleHeadroom)
                                 : NSSize(width: petSize, height: petSize)
        if celebrating {
            let margin = CelebrationStage.effectsMargin
            size.width = max(size.width, petSize + 2 * margin)
            size.height += 2 * margin
        }
        return size
    }

    /// While celebrating, the panel also reaches `effectsMargin` below the feet: the pet box sits that
    /// far above the panel's bottom edge, so it stays at the same spot on screen.
    static func panelOrigin(petOrigin: NSPoint, petSize: CGFloat, panelSize: NSSize, celebrating: Bool = false) -> NSPoint {
        let xInset = max(0, (panelSize.width - petSize) / 2)
        return NSPoint(x: petOrigin.x - xInset, y: petOrigin.y - bottomInset(celebrating: celebrating))
    }

    static func petOrigin(panelOrigin: NSPoint, petSize: CGFloat, panelSize: NSSize, celebrating: Bool = false) -> NSPoint {
        let xInset = max(0, (panelSize.width - petSize) / 2)
        return NSPoint(x: panelOrigin.x + xInset, y: panelOrigin.y + bottomInset(celebrating: celebrating))
    }

    private static func bottomInset(celebrating: Bool) -> CGFloat { celebrating ? CelebrationStage.effectsMargin : 0 }

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
        let titleFont = NSFont.systemFont(ofSize: 11, weight: .bold)
        let bodyFont = NSFont.systemFont(ofSize: 10)
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
        let titleHeight = title.isEmpty ? 0 : ceil(titleRect.height) + 2   // an empty title is not drawn
        let textHeight = titleHeight + ceil(bodyRect.height)
        // Match SpeechBubbleView: horizontal padding ×2, vertical 6, bottom pad 6 for the tail.
        let hPad = bubbleHorizontalPadding * 2
        let bodyLineCount = wrappedLineCount(body, font: bodyFont, width: contentWidth)
        return SpeechBubbleLayout(
            size: NSSize(width: textWidth + hPad, height: textHeight + 12 + 6),
            bodyLineCount: bodyLineCount,
            unclampedTitleWidth: unclampedTitle.width,
            unclampedBodyWidth: unclampedBody.width,
            wouldTruncate: bodyLineCount > bodyLineLimit(titled: !title.isEmpty))
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
        if !agentEnabled, !tracker.agents.isEmpty || runPhase != .home { resetAgent() }
        let interactive = Self.sessionInteractive(sessionProbe(), screensaverRunning: screensaverRunning,
                                                  startNoticed: sessionStartNoticed)
        sessionStartNoticed = false
        if interactive != sessionInteractive {
            sessionInteractive = interactive
            onSessionInteractiveChange?(interactive)
        }
        // Behind a lock screen, a screensaver or another user's session the pet is as good as asleep:
        // hidden like display sleep, so a sequence is cancelled, never finished unseen.
        let shown = store.floatingPetEnabled && displayAwake && interactive
        if shown { show() } else { hide() }
        let live = Self.isLive(enabled: store.floatingPetEnabled, panelVisible: panel?.isVisible == true,
                               displayAwake: displayAwake, sessionInteractive: interactive)
        // Only on change: every write notifies the store's observers, this controller included.
        if companion.floatingPetLive != live { companion.floatingPetLive = live }
        syncCelebration()
        if shown, let p = panel {
            // The step above may have just started or ended a sequence: give the stage its room now, in
            // the same pass, so its first frame is never clipped.
            applyFrame(p, targetFrame(petSize: CGFloat(store.floatingPetSize), showingBubble: showingBubble))
        }
        syncEggWobble()
    }

    /// Frames the panel and switches the view's layout (stage or resting sprite, bubble, hearts) in one step,
    /// then lays the content out and draws it at once, so the new frame and the new layout land in the same
    /// display cycle. The view used to follow the player and the store instead: at a sequence's end it drew the
    /// resting sprite in the still-grown panel, and a limit alert's bubble over the pet in the resting-size
    /// panel, until the observation hop reframed it. Does nothing when nothing changed (no idle cost).
    private func applyFrame(_ p: NSPanel, _ frame: NSRect) {
        let layoutChanged = updateLayout()
        guard layoutChanged || p.frame != frame else { return }
        p.setFrame(frame, display: true)
        p.contentView?.layoutSubtreeIfNeeded()
        p.displayIfNeeded()
    }

    private func syncCelebration() {
        switch Self.celebrationStep(petLive: companion.isLive(.floatingPet),
                                    head: companion.celebrations.next(for: .floatingPet),
                                    playingID: celebrationPlayer.item?.id) {
        case .keep:
            followSharedStart()
        case .play(let head):
            if let previous = celebrationPlayer.item?.id { companion.celebrationStopped(id: previous, on: .floatingPet) }
            // Joins the popover's start and version when it already plays the item: both show the same phase.
            let shared = companion.beginCelebration(id: head.id, on: .floatingPet, now: celebrationPlayer.now,
                                                    reduced: !motionAllowed)
            playCelebration(head, from: shared.startedAt, reduced: shared.reduced)
        case .stop:
            stopCelebration()
        }
    }

    private func playCelebration(_ head: PendingCelebration, from start: Date, reduced: Bool) {
        celebrationPlayer.reduced = reduced
        // The end of the sequence marks it seen and releases its notification. The store decides: finished if
        // the pet is still live, else a stop (seen only past the reveal).
        // The end reframes at once (`sync()`), in the player's own step: waiting for the observation hop left
        // the resting sprite drawn in the still-grown panel. The next queued item, if any, starts there too.
        celebrationPlayer.play(head, now: start, onFinish: { [weak self, companion] id in
            companion.celebrationPlayerEnded(id: id, on: .floatingPet)
            self?.sync()
        }, onSkip: { [companion] id, start in companion.skipCelebration(id: id, startedAt: start) },
           onSeen: { [companion] id in companion.celebrationRevealed(id: id) })
    }

    /// Re-aligns on the shared start after the popover skipped the item.
    private func followSharedStart() {
        guard let shared = companion.celebrationPlayback, let item = celebrationPlayer.item, shared.id == item.id,
              celebrationPlayer.startedAt != shared.startedAt else { return }
        playCelebration(item, from: shared.startedAt, reduced: shared.reduced)
    }

    /// Stops the pet's playback before its end: seen if it passed the reveal and nobody else plays it.
    private func stopCelebration() {
        let id = celebrationPlayer.item?.id
        celebrationPlayer.cancel()
        if let id { companion.celebrationStopped(id: id, on: .floatingPet) }
    }

    private func syncEggWobble() {
        eggWobbles.update(every: Self.eggWobbleInterval(
            restingEgg: celebrationPlayer.item == nil && displayedSubject.speciesID == nil,
            progress: companion.eggProgress, motionAllowed: motionAllowed, panelVisible: panel?.isVisible == true))
    }

    private var celebrationCaption: String? {
        Self.celebrationCaption(player: celebrationPlayer, language: companion.language)
    }

    private var celebrating: Bool { celebrationPlayer.item != nil }

    /// Who the pet shows now: a pending hatch/evolve's source until that item is finished.
    var displayedSubject: CompanionStore.RepresentativeSubject {
        Self.displayedSubject(representative: companion.representativeSubject, queue: companion.celebrations,
                              player: celebrationPlayer, liveSpeciesID: companion.currentSpeciesID)
    }

    /// The frame on screen was laid out for a sequence (pet raised by the effects margin). Read by the hosted
    /// view too, so the frame and the layout never disagree.
    private let layout = FloatingPetLayoutModel()
    private var framedForCelebration: Bool { layout.celebrating }

    /// The panel's frame on screen; nil before it was first shown.
    var panelFrame: NSRect? { panel?.frame }
    /// The hosted pet view (tests capture it).
    var hostingView: PetHostingView? { panel?.contentView as? PetHostingView }
    /// Whether the hosted view lays out the stage (rather than the resting sprite) right now.
    var contentShowsStage: Bool { FloatingPetView.showsStage(layout: layout) }
    /// Whether the hosted view draws a speech bubble right now.
    var contentShowsBubble: Bool { FloatingPetView.speechBubble(layout: layout) != nil }

    private var showingBubble: Bool {
        Self.isShowingBubble(alertActive: store.currentBubbleAlert != nil, heartsShowing: hearts.isShowing,
                             agent: tracker.summary, celebration: celebrationCaption)
    }

    /// The speech bubble the panel reserves its headroom for (`showingBubble` without the hearts).
    private var speechBubble: Bubble? {
        Self.bubble(limitAlert: store.currentBubbleAlert, agent: tracker.summary, celebration: celebrationCaption)
    }

    /// Writes what the view lays out (stage, bubble, hearts) from the state the frame is computed from.
    /// Returns whether anything changed. Only the frame-setting paths call it, so both switch together.
    private func updateLayout() -> Bool {
        let bubble = speechBubble, heartsShowing = hearts.isShowing
        var changed = false
        if layout.celebrating != celebrating { layout.celebrating = celebrating; changed = true }
        if layout.bubble != bubble { layout.bubble = bubble; changed = true }
        if layout.hearts != heartsShowing { layout.hearts = heartsShowing; changed = true }
        return changed
    }

    /// Build once per animation mode; callbacks share the controller's click and bubble routing.
    func makeHostingView(animated: Bool) -> PetHostingView {
        let hosting = PetHostingView(rootView: AnyView(
            FloatingPetView(animated: animated, agent: agentModel, layout: layout, spriteStore: spriteStore,
                            burst: prayerBurst, celebration: celebrationPlayer)
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
        let wantAnimated = motionOverride ?? Self.shouldAnimate(lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled)
        if p.contentView == nil || builtAnimated != wantAnimated {
            p.contentView = makeHostingView(animated: wantAnimated)
            builtAnimated = wantAnimated
        }
        if let hosting = p.contentView as? PetHostingView {
            hosting.toolTip = Self.nativeToolTip(currentHoverText(), heartsShowing: hearts.isShowing)
            hosting.strokeDistance = max(10, CGFloat(store.floatingPetSize) * 0.15)
        }
        agentModel.bobs = Self.shouldBob(working: tracker.summary.working, motionAllowed: motionAllowed)
        applyFrame(p, targetFrame(petSize: CGFloat(store.floatingPetSize), showingBubble: showingBubble))
        p.orderFrontRegardless()
        if hoverPanel?.isVisible == true { showHoverCallout() }
    }

    private func petWasStroked() {
        hearts.isShowing = Self.heartsShowing(afterStrokeWithAlertActive: store.currentBubbleAlert != nil,
                                             agent: tracker.summary, celebration: celebrationCaption)
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

    /// Every way off screen (Hide, the setting, display sleep) comes through here, before `sync()` writes
    /// the live flag: the sequence stops unfinished here (it stays queued unless an open popover, playing it in
    /// sync, reaches its end).
    private func hide() {
        stopCelebration()
        eggWobbles.update(every: nil)
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
        let l = L(companion.language)
        let presentation = Self.presentation(queue: companion.celebrations, player: celebrationPlayer,
                                             liveSpeciesID: companion.currentSpeciesID)
        let subject = Self.displayedSubject(representative: companion.representativeSubject, presentation: presentation)
        return FloatingPetView.hoverTooltip(
            todayTokens: store.todayTotalTokens,
            limitUtilization: store.highestLimitUtilization,
            mode: store.limitDisplayMode,
            l: l,
            sulkIdle: companion.sulkIdle,
            eventLine: eventPopText,
            eggLine: Self.eggTierLine(subject: subject, presentation: presentation,
                                      eggProgress: companion.eggProgress, l: l),
            prayers: Self.hoverPrayerCount(subject: subject, presentation: presentation,
                                           prayers: companion.state.eggPrayers?.count ?? 0))
    }

    /// The prayer count belongs to the resting egg; during its hatch it is already the next egg's (zero).
    static func hoverPrayerCount(subject: CompanionStore.RepresentativeSubject, presentation: CelebrationPresentation?,
                                 prayers: Int) -> Int {
        subject.speciesID == nil && presentation == nil ? prayers : 0
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
        let size = Self.panelSize(petSize: petSize, showingBubble: showingBubble, celebrating: celebrating)
        let petOrigin: NSPoint
        if runPhase == .away, let awayPetOrigin {
            petOrigin = awayPetOrigin
        } else if let x = defaults.object(forKey: Self.originXKey) as? Double,
           let y = defaults.object(forKey: Self.originYKey) as? Double {
            petOrigin = NSPoint(x: x, y: y)
        } else {
            petOrigin = Self.defaultPetOrigin(petSize: petSize)
        }
        var frame = NSRect(origin: Self.panelOrigin(petOrigin: petOrigin, petSize: petSize, panelSize: size,
                                                    celebrating: celebrating),
                           size: size)
        if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) {
            let fallbackPet = Self.defaultPetOrigin(petSize: petSize)
            frame.origin = Self.panelOrigin(petOrigin: fallbackPet, petSize: petSize, panelSize: size,
                                            celebrating: celebrating)
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
        panelDidMove(panelOrigin: p.frame.origin, panelSize: p.frame.size,
                     userDragging: (p.contentView as? PetHostingView)?.isDragging ?? false)
        if hoverPanel?.isVisible == true { showHoverCallout() }
    }

    /// `panelSize` is the panel's actual size on screen, not one recomputed from the current state.
    func panelDidMove(panelOrigin: NSPoint, panelSize size: NSSize, userDragging: Bool) {
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
        let pet = Self.petOrigin(panelOrigin: panelOrigin, petSize: petSize, panelSize: size,
                                 celebrating: framedForCelebration)
        defaults.set(Double(pet.x), forKey: Self.originXKey)
        defaults.set(Double(pet.y), forKey: Self.originYKey)
    }
}

/// The resting egg's periodic one-shot wobbles: one sleeping task per interval, none while `interval` is nil.
/// `sleep` is injectable so tests do not wait for real seconds.
@MainActor
final class EggWobbleDriver {
    private(set) var interval: Duration?
    /// Unsafe only for `deinit`, which runs once nothing else references the driver.
    private nonisolated(unsafe) var task: Task<Void, Never>?
    private let sleep: @MainActor (Duration) async throws -> Void
    private let wobble: @MainActor () -> Void

    init(sleep: @escaping @MainActor (Duration) async throws -> Void = { try await Task.sleep(for: $0, tolerance: .seconds(1)) },
         wobble: @escaping @MainActor () -> Void) {
        self.sleep = sleep
        self.wobble = wobble
    }

    /// The loop does not hold the driver: a released driver (a rebuilt or test controller) stops it here.
    deinit { task?.cancel() }

    /// Restarts the loop only when the interval changes; nil stops it.
    func update(every: Duration?) {
        guard every != interval else { return }
        task?.cancel()
        task = nil
        interval = every
        guard let every else { return }
        let sleep = sleep, wobble = wobble
        task = Task { await EggIncubationTier.wobbleLoop(every: every, sleep: sleep, wobble: wobble) }
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

/// What the panel is framed for, and so what the view lays out in it: the stage (grown by the effects margin)
/// or the resting sprite, and the speech bubble or hearts that take the headroom above the pet.
/// The one source of truth for both the panel frame and the view's layout: only the controller writes it, in
/// the same step that sets the frame (`FloatingPetController.applyFrame`, and the run's animated frames).
/// The view never decides from the player, the store's alert or the heart state, which change on their own
/// clocks, before the panel can grow or shrink.
@MainActor
@Observable
final class FloatingPetLayoutModel {
    var celebrating = false
    /// The speech bubble the panel reserved its headroom for; nil = none.
    var bubble: FloatingPetController.Bubble?
    /// The heart bubble after a stroke (drawn only without a speech bubble).
    var hearts = false
}

@MainActor
struct FloatingPetView: View {
    var animated: Bool = true
    var agent = FloatingPetAgentModel()
    /// The controller's framing; it alone switches the stage and the resting sprite, the bubble and the hearts.
    var layout = FloatingPetLayoutModel()
    /// Injectable so render tests stay offline and away from the real sprite cache.
    var spriteStore: SpriteStore = .shared
    var burst = PrayerBurst()
    /// The controller's sequence player; while it plays, its stage takes the resting sprite's place.
    var celebration = CelebrationPlayer()
    @Environment(UsageStore.self) private var store
    @Environment(CompanionStore.self) private var companion

    /// The stage on the pet: the sprite's GIF frames keep the user's floor, the effects get the pet's cap.
    static func celebrationStage(player: CelebrationPlayer, size: CGFloat, frameFloor: TimeInterval,
                                 spriteStore: SpriteStore) -> CelebrationStage {
        CelebrationStage(player: player, size: size, minFrameDelay: frameFloor, spriteStore: spriteStore,
                         minimumInterval: FloatingPetController.celebrationFrameInterval)
    }

    static func showsStage(layout: FloatingPetLayoutModel) -> Bool { layout.celebrating }

    static func speechBubble(layout: FloatingPetLayoutModel) -> FloatingPetController.Bubble? { layout.bubble }

    var body: some View {
        let size = CGFloat(store.floatingPetSize)
        let l = L(companion.language)
        let bubble = Self.speechBubble(layout: layout)
        VStack(spacing: 8) {
            if let bubble {
                // Removal is instant, like the hearts: the panel drops the bubble headroom at the same moment
                // (and the effects margin at a sequence's end), so a fading bubble would be drawn over the pet.
                // Only the insertion carries an animation, on the transition itself: the bubble changes in the
                // panel's frame step, so an animated transaction would also slide the pet into the resized
                // panel, and on an older SwiftUI keep a removed bubble drawn for the animation's length.
                SpeechBubbleView(content: FloatingPetController.bubbleContent(bubble, l: l))
                    .transition(.asymmetric(insertion: Self.popIn(animated: animated), removal: .identity))
                    .zIndex(1)
            }

            if Self.showsStage(layout: layout) {
                // The sprite box stays where the resting pet stands; the stage (the box grown by its margin
                // on every side) is centred on it, so the sprite at scale 1 lands exactly on the resting one.
                // The panel adds the margin above and below (`panelSize(celebrating:)`).
                let side = size + 2 * CelebrationStage.effectsMargin
                Color.clear
                    .frame(width: size, height: size)
                    .overlay {
                        Self.celebrationStage(player: celebration, size: size,
                                              frameFloor: store.animationQuality.frameFloor, spriteStore: spriteStore)
                            .frame(width: side, height: side)
                    }
                    .padding(.vertical, CelebrationStage.effectsMargin)
                    .zIndex(0)
                    // The swap with the resting sprite is never animated: the panel frame switches in one step,
                    // so a cross-fade drew the outgoing sprite at its old place in the new frame.
                    .transition(.identity)
            } else {
                restingSprite(size: size, bubbleShowing: bubble != nil)
                    .transition(.identity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    /// A bubble's (speech or hearts) pop-in, animated by the transition alone, never by the transaction that
    /// resizes the panel with it.
    static func popIn(animated: Bool) -> AnyTransition {
        guard animated else { return .identity }
        return AnyTransition.scale(scale: 0.8, anchor: .bottom).combined(with: .opacity)
            .animation(.spring(response: 0.3, dampingFraction: 0.7))
    }

    @ViewBuilder
    private func restingSprite(size: CGFloat, bubbleShowing: Bool) -> some View {
        // A pending hatch/evolve shows its source (the egg) until it is seen, even under the popover.
        let subject = FloatingPetController.displayedSubject(representative: companion.representativeSubject,
                                                             queue: companion.celebrations, player: celebration,
                                                             liveSpeciesID: companion.currentSpeciesID)
        SpriteView(speciesID: subject.speciesID, size: size, animated: animated,
                   shiny: subject.isShiny,
                   minFrameDelay: store.animationQuality.frameFloor, spriteStore: spriteStore, form: subject.form,
                   back: companion.facesBack, reportsVisibleTop: true)
            // One-shot wobble per prayer or incubation stir; runs once per trigger change, never in a loop.
            .modifier(OneShotWobble(trigger: burst.wobbleCount))
            .frame(width: size, height: size)
            .overlay { PrayerEmojiLayer(burst: burst, size: size, animated: animated) }
            // Hearts hug the visible top of the sprite (not its box). Insertion pops in; removal is
            // instant, because the panel shrinks at the same moment and a fading bubble would be
            // drawn lower, over the pet.
            .overlayPreferenceValue(SpriteVisibleTopKey.self, alignment: .top) { visibleTop in
                if layout.hearts, !bubbleShowing {
                    HeartBubbleView(l: L(companion.language))
                        .offset(y: SpriteVisibleTop.bubbleTopOffset(
                            visibleTop: visibleTop ?? 0,
                            bubbleHeight: HeartBubbleArt.height,
                            overlap: HeartBubbleArt.tailOverlap))
                        .transition(.asymmetric(insertion: Self.popIn(animated: animated), removal: .identity))
                        .allowsHitTesting(false)
                }
            }
            // Keep the attached heart and prayer particles aligned with the bobbing sprite.
            .modifier(AgentBob(active: agent.bobs))
            .zIndex(0)
    }

    /// `sulkIdle` > 0 appends how long the companion has been sulking: hours below 48 h, days from there.
    /// `eggLine` is the egg's incubation tier (nil for a Pokémon), right above its prayer count.
    static func hoverTooltip(todayTokens: Int, limitUtilization: Double?,
                             mode: UsageStore.LimitDisplayMode, l: L, sulkIdle: TimeInterval = 0,
                             eventLine: String? = nil, eggLine: String? = nil, prayers: Int = 0) -> String {
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
        if let eggLine { base += "\n" + eggLine }
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

    /// One wobble without a particle: the resting egg stirring on its own (incubation tier).
    func nudge() { wobbleCount += 1 }

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

/// Transient limit-alert, agent or celebration bubble. Width is capped so copy wraps instead of clipping the panel.
@MainActor
struct SpeechBubbleView: View {
    let content: FloatingPetController.SpeechBubbleContent

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Untitled = the pet speaking (a celebration line): the line itself is the message.
            if !content.title.isEmpty {
                Text(content.title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(content.isCritical ? .red : .primary)
            }
            Text(content.body)
                .font(.system(size: 10))
                .foregroundColor(content.title.isEmpty ? .primary : .secondary)
                .lineLimit(FloatingPetController.bodyLineLimit(titled: !content.title.isEmpty))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: FloatingPetController.bubbleContentWidth, alignment: .leading)
        .padding(.horizontal, FloatingPetController.bubbleHorizontalPadding)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        )
        .overlay(
            Path { path in
                path.move(to: CGPoint(x: 10, y: 0))
                path.addLine(to: CGPoint(x: 20, y: 0))
                path.addLine(to: CGPoint(x: 15, y: 6))
                path.closeSubpath()
            }
            .fill(Color(nsColor: .windowBackgroundColor))
            .offset(y: 5),
            alignment: .bottom
        )
        .padding(.bottom, 6)
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

/// Whether the heart bubble is up. Controller state: the view draws the hearts from `FloatingPetLayoutModel.hearts`,
/// written with the panel frame.
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
