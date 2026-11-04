import AppKit
import QuartzCore
import SwiftUI

/// 데스크톱 위에 떠 있는 컴패니언 포켓몬 오버레이(옵트인, 설정 → 플로팅 펫).
/// - 드래그: 커스텀 `mouseDragged` (클릭과 충돌하지 않음).
/// - 클릭 → 팝오버, 우클릭 → 메뉴, 호버 → 오늘 사용량 콜아웃.
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

    static func shouldBob(working: Bool, motionAllowed: Bool) -> Bool {
        motionAllowed && working
    }

    /// The one bubble the pet shows. A limit alert outranks agent messages.
    enum Bubble: Equatable {
        case limit(UsageStore.LimitAlert)
        case agentWaiting(label: String?, message: String?, others: Int)
        case agentDone(label: String?, message: String?)
    }

    /// A limit alert outranks agents; among agents a fresh `done` outranks waiting.
    static func bubble(limitAlert: UsageStore.LimitAlert?, agent: AgentActivitySummary) -> Bubble? {
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

    init(store: UsageStore, companion: CompanionStore, defaults: UserDefaults = .standard,
         onOpenPopover: (() -> Void)? = nil, onHide: (() -> Void)? = nil,
         motionOverride: Bool? = nil) {
        self.store = store
        self.companion = companion
        self.defaults = defaults
        self.motionOverride = motionOverride
        self.onOpenPopover = onOpenPopover
        self.onHide = onHide
        super.init()
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
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.sync()
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

    private var showsBubble: Bool {
        Self.bubble(limitAlert: store.currentBubbleAlert, agent: tracker.summary) != nil
    }

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
        let frame = targetFrame(petSize: CGFloat(store.floatingPetSize), showingBubble: showsBubble)
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

    /// Click on the pet: a waiting/done bubble is answered, then the usual popover opens.
    func petClicked() {
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
        if !agentEnabled, !tracker.agents.isEmpty || runPhase != .home { resetAgent() }
        guard store.floatingPetEnabled, displayAwake else { hide(); return }
        show()
    }

    private func show() {
        let p = panel ?? makePanel()
        panel = p
        let wantAnimated = Self.shouldAnimate(lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled)
        if p.contentView == nil || builtAnimated != wantAnimated {
            let hosting = PetHostingView(rootView: AnyView(
                FloatingPetView(animated: wantAnimated, agent: agentModel)
                    .environment(store).environment(companion)))
            hosting.onOpenPopover = { [weak self] in self?.petClicked() }
            hosting.onHide = onHide
            hosting.languageProvider = { [weak self] in self?.companion.language ?? .systemDefault }
            hosting.onHoverChange = { [weak self] hovering in
                if hovering { self?.showHoverCallout() } else { self?.hideHoverCallout() }
            }
            p.contentView = hosting
            builtAnimated = wantAnimated
        }
        if let hosting = p.contentView as? PetHostingView {
            hosting.toolTip = currentHoverText()
        }
        agentModel.bobs = Self.shouldBob(working: tracker.summary.working, motionAllowed: motionAllowed)
        let petSize = CGFloat(store.floatingPetSize)
        p.setFrame(targetFrame(petSize: petSize, showingBubble: showsBubble), display: true)
        p.orderFrontRegardless()
        if hoverPanel?.isVisible == true { showHoverCallout() }
    }

    private func hide() {
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
            l: L(companion.language))
    }

    private func showHoverCallout() {
        guard let pet = panel, pet.isVisible else { return }
        // Don't cover an active limit bubble — the speech bubble is the priority surface.
        if showsBubble { hideHoverCallout(); return }
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
        let size = Self.panelSize(petSize: petSize, showingBubble: showsBubble)
        let pet = Self.petOrigin(panelOrigin: panelOrigin, petSize: petSize, panelSize: size)
        defaults.set(Double(pet.x), forKey: Self.originXKey)
        defaults.set(Double(pet.y), forKey: Self.originYKey)
    }
}

final class PetHostingView: NSHostingView<AnyView> {
    var onOpenPopover: (() -> Void)?
    var onHide: (() -> Void)?
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
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { onHoverChange?(true) }
    override func mouseExited(with event: NSEvent) { onHoverChange?(false) }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            showContextMenu(event)
            return
        }
        mouseDownScreen = NSEvent.mouseLocation
        originAtDown = window?.frame.origin
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
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
            onOpenPopover?()
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
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc func handleOpen(_ sender: Any?) { onOpenPopover?() }
    @objc func handleHide(_ sender: Any?) { onHide?() }
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
    let agent: FloatingPetAgentModel
    @Environment(UsageStore.self) private var store
    @Environment(CompanionStore.self) private var companion

    var body: some View {
        let size = CGFloat(store.floatingPetSize)
        let subject = companion.representativeSubject
        let bubble = FloatingPetController.bubble(limitAlert: store.currentBubbleAlert, agent: agent.summary)
        VStack(spacing: 8) {
            if let bubble {
                SpeechBubbleView(content: FloatingPetController.bubbleContent(bubble, l: L(companion.language)))
                    .transition(.scale(scale: 0.8, anchor: .bottom).combined(with: .opacity))
                    .zIndex(1)
            }

            SpriteView(speciesID: subject.speciesID, size: size, animated: animated,
                       shiny: subject.isShiny,
                       minFrameDelay: store.animationQuality.frameFloor, form: subject.form)
                .frame(width: size, height: size)
                .modifier(AgentBob(active: agent.bobs))
                .zIndex(0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .animation(animated ? .spring(response: 0.3, dampingFraction: 0.7) : nil,
                   value: bubble)
    }


    static func hoverTooltip(todayTokens: Int, limitUtilization: Double?,
                             mode: UsageStore.LimitDisplayMode, l: L) -> String {
        let usage = TokenFormatter.grouped(todayTokens)
        if let pct = limitUtilization {
            let text = TokenFormatter.percent(UsageStore.displayPercent(pct, mode: mode))
            return l.floatingPetHoverWithLimit(usage, mode == .remaining ? l.percentRemaining(text) : text)
        }
        return l.floatingPetHoverTokensOnly(usage)
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

/// Transient limit-alert or agent bubble. Width is capped so copy wraps instead of clipping the panel.
@MainActor
private struct SpeechBubbleView: View {
    let content: FloatingPetController.SpeechBubbleContent

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(content.title)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(content.isCritical ? .red : .primary)
            Text(content.body)
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
