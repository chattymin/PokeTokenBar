import AppKit
import SwiftUI

/// 데스크톱 위에 떠 있는 컴패니언 포켓몬 오버레이(옵트인, 설정 → 플로팅 펫).
/// - 드래그: 커스텀 `mouseDragged` (클릭과 충돌하지 않음).
/// - 클릭 → 팝오버, 우클릭 → 메뉴, 호버 → 오늘 사용량 콜아웃.
/// - Limit-alert speech bubbles grow the panel; persisted origin is the *pet*, not the panel.
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

    /// How long the heart bubble stays after the last qualifying stroke.
    static let heartDuration: Duration = .milliseconds(1800)

    /// Whether the heart bubble shows after a stroke. A limit alert always wins: no hearts over it.
    static func heartsShowing(afterStrokeWithAlertActive alertActive: Bool) -> Bool { !alertActive }

    /// The panel needs bubble headroom for a limit alert or for the heart bubble.
    static func isShowingBubble(alertActive: Bool, heartsShowing: Bool) -> Bool {
        alertActive || heartsShowing
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

    /// Pop the callout only for an event not shown yet, while the pet is on screen and no bubble (limit alert or
    /// hearts) is up. An event that arrives when it cannot pop is dropped, not queued.
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

    private func handleClick() {
        clickRouter.handle(subjectIsEgg: companion.representativeSubject.speciesID == nil)
    }

    private let clock: () -> Date

    init(store: UsageStore, companion: CompanionStore, defaults: UserDefaults = .standard,
         clock: @escaping () -> Date = Date.init,
         onOpenPopover: (() -> Void)? = nil, onHide: (() -> Void)? = nil) {
        self.clock = clock
        self.store = store
        self.companion = companion
        self.defaults = defaults
        self.onOpenPopover = onOpenPopover
        self.onHide = onHide
        super.init()
        lastSeenEventSeq = companion.latestEvent?.seq   // an event from before the pet existed is not news
        observeSettings()
        observePowerState()
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

    static func shouldAnimate(lowPower: Bool) -> Bool { !lowPower }

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
        let textHeight = ceil(titleRect.height) + 2 + ceil(bodyRect.height)
        // Match SpeechBubbleView: horizontal padding ×2, vertical 6, bottom pad 6 for the tail.
        let hPad = bubbleHorizontalPadding * 2
        let bodyLineCount = wrappedLineCount(body, font: bodyFont, width: contentWidth)
        return SpeechBubbleLayout(
            size: NSSize(width: textWidth + hPad, height: textHeight + 12 + 6),
            bodyLineCount: bodyLineCount,
            unclampedTitleWidth: unclampedTitle.width,
            unclampedBodyWidth: unclampedBody.width,
            wouldTruncate: bodyLineCount > bubbleBodyLineLimit)
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
        guard store.floatingPetEnabled, displayAwake else { hide(); return }
        show()
    }

    private var showingBubble: Bool {
        Self.isShowingBubble(alertActive: store.currentBubbleAlert != nil, heartsShowing: hearts.isShowing)
    }

    private func show() {
        let p = panel ?? makePanel()
        panel = p
        let wantAnimated = Self.shouldAnimate(lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled)
        if p.contentView == nil || builtAnimated != wantAnimated {
            let hosting = PetHostingView(rootView: AnyView(
                FloatingPetView(animated: wantAnimated, burst: prayerBurst, hearts: hearts).environment(store).environment(companion)))
            hosting.onOpenPopover = onOpenPopover
            hosting.onClick = { [weak self] in self?.handleClick() }
            hosting.onStroke = { [weak self] in self?.petWasStroked() }
            hosting.onHide = onHide
            hosting.onToggleBackView = { [weak self] in self?.store.alwaysFacesBack.toggle() }
            hosting.isBackViewOn = { [weak self] in self?.store.alwaysFacesBack ?? false }
            hosting.languageProvider = { [weak self] in self?.companion.language ?? .systemDefault }
            hosting.onHoverChange = { [weak self] hovering in
                self?.isHovering = hovering
                if hovering { self?.showHoverCallout() } else { self?.hideHoverCallout() }
            }
            p.contentView = hosting
            builtAnimated = wantAnimated
        }
        if let hosting = p.contentView as? PetHostingView {
            hosting.toolTip = Self.nativeToolTip(currentHoverText(), heartsShowing: hearts.isShowing)
            hosting.strokeDistance = max(10, CGFloat(store.floatingPetSize) * 0.15)
        }
        let petSize = CGFloat(store.floatingPetSize)
        p.setFrame(targetFrame(petSize: petSize, showingBubble: showingBubble),
                   display: true)
        p.orderFrontRegardless()
        if hoverPanel?.isVisible == true { showHoverCallout() }
    }

    private func petWasStroked() {
        hearts.isShowing = Self.heartsShowing(afterStrokeWithAlertActive: store.currentBubbleAlert != nil)
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
            hosting.toolTip = currentHoverText()
        }
        if hoverPanel?.isVisible == true { showHoverCallout() }
    }

    private func showHoverCallout() {
        guard let pet = panel, pet.isVisible else { return }
        // Don't cover an active limit bubble — the speech bubble is the priority surface.
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
        if let x = defaults.object(forKey: Self.originXKey) as? Double,
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
        let petSize = CGFloat(store.floatingPetSize)
        let size = Self.panelSize(petSize: petSize, showingBubble: showingBubble)
        let pet = Self.petOrigin(panelOrigin: p.frame.origin, petSize: petSize, panelSize: size)
        defaults.set(Double(pet.x), forKey: Self.originXKey)
        defaults.set(Double(pet.y), forKey: Self.originYKey)
        if hoverPanel?.isVisible == true { showHoverCallout() }
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

@MainActor
struct FloatingPetView: View {
    var animated: Bool = true
    /// Injectable so render tests stay offline and away from the real sprite cache.
    var spriteStore: SpriteStore = .shared
    var burst = PrayerBurst()
    /// Heart bubble shown after a stroke. A limit alert takes precedence.
    var hearts = PetHeartState()
    @Environment(UsageStore.self) private var store
    @Environment(CompanionStore.self) private var companion

    var body: some View {
        let size = CGFloat(store.floatingPetSize)
        let subject = companion.representativeSubject
        VStack(spacing: 8) {
            if let alert = store.currentBubbleAlert {
                SpeechBubbleView(alert: alert, l: L(companion.language))
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
                    if hearts.isShowing, store.currentBubbleAlert == nil {
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
                .zIndex(0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .animation(animated ? .spring(response: 0.3, dampingFraction: 0.7) : nil,
                   value: store.currentBubbleAlert)
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

/// Transient limit-alert bubble. Width is capped so copy wraps instead of clipping the panel.
@MainActor
private struct SpeechBubbleView: View {
    let alert: UsageStore.LimitAlert
    let l: L

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(alert.isCritical ? l.notifCritical : l.notifWarning)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(alert.isCritical ? .red : .primary)
            Text(FloatingPetController.bubbleBody(for: alert, title: alert.isCritical ? l.notifCritical : l.notifWarning, l: l))
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .lineLimit(FloatingPetController.bubbleBodyLineLimit)
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
