import AppKit
import SwiftUI

/// Pet overlay panel. Stock `.nonactivatingPanel` cannot become key, so overlay
/// `TextField`s (session notes, check-in) swallow clicks and drop keystrokes.
final class FloatingPetPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// 데스크톱 위에 떠 있는 컴패니언 포켓몬 오버레이(옵트인, 설정 → 플로팅 펫).
/// - 드래그: 커스텀 `mouseDragged` (클릭과 충돌하지 않음).
/// - 클릭 → 팝오버, 우클릭 → 메뉴, 호버 → 오늘 사용량 콜아웃.
/// - Limit-alert speech bubbles grow the panel; persisted origin is the *pet*, not the panel.
/// - 에너지: 숨김·슬립 시 호스팅 트리 해제.
@MainActor
final class FloatingPetController: NSObject, NSWindowDelegate {
    enum OverlayConfirmPrompt: Equatable {
        case none, forfeit, reset
    }
    private let store: UsageStore
    private let companion: CompanionStore
    private let session: FocusSessionStore
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
    static let islandWidth: CGFloat = 228
    static let islandHeight: CGFloat = 108
    static let islandGap: CGFloat = 8
    /// Chevron *hit* target. Glyph stays smaller inside this frame.
    static let islandFoldChevronSize: CGFloat = 32
    /// Folded countdown (`50:00` + compact OT capsule). Wider than digits-only so OT is not clipped.
    static let islandFoldedClockWidth: CGFloat = 88
    static let islandFoldedClockHeight: CGFloat = 18
    static let promptHeightZeroTime: CGFloat = 152
    static let promptHeightCheckIn: CGFloat = 176
    static let promptHeightForfeit: CGFloat = 168
    static let promptHeightReset: CGFloat = 108
    static let noteComposerHeight: CGFloat = 68

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
    private var onOpenToday: (() -> Void)?
    private var onNewIssue: (() -> Void)?
    /// Rising-edge so token/bubble `sync()` does not re-activate while typing.
    private var textInputArmed = false

    init(store: UsageStore, companion: CompanionStore, session: FocusSessionStore,
         defaults: UserDefaults = .standard,
         onOpenPopover: (() -> Void)? = nil, onHide: (() -> Void)? = nil,
         onOpenToday: (() -> Void)? = nil, onNewIssue: (() -> Void)? = nil) {
        self.store = store
        self.companion = companion
        self.session = session
        self.defaults = defaults
        self.onOpenPopover = onOpenPopover
        self.onHide = onHide
        self.onOpenToday = onOpenToday
        self.onNewIssue = onNewIssue
        super.init()
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
            _ = store.floatingPetIslandFolded
            _ = store.currentSpeechBubble
            _ = store.todayTotalTokens
            _ = store.highestLimitUtilization
            _ = store.limitDisplayMode   // hover 툴팁 %가 파생되는 값 — 수동 관찰 표면은 파생 원천을 직접 추적(defect-log §표시·UI)
            _ = companion.language
            _ = session.isActive
            _ = session.prompt
            _ = session.isComposingNote
            _ = session.forfeitPrompt
            _ = session.resetPrompt
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

    static func shouldAnimate(lowPower: Bool) -> Bool { !lowPower }

    /// Panel size for a given pet size and bubble visibility. Pure — tested without AppKit layout.
    static func panelSize(petSize: CGFloat, showingBubble: Bool) -> NSSize {
        panelSize(petSize: petSize, showingBubble: showingBubble, hasIsland: false, prompt: .none)
    }

    /// Overlay `TextField`s (note composer, check-in) need a key window. Stock
    /// `.nonactivatingPanel` returns `canBecomeKey == false`, so keystrokes never arrive.
    static func overlayNeedsKeyWindow(composingNote: Bool, prompt: FocusPrompt) -> Bool {
        composingNote || prompt == .checkIn
    }

    static func panelSize(petSize: CGFloat, showingBubble: Bool,
                          hasIsland: Bool, prompt: FocusPrompt, composingNote: Bool = false,
                          confirm: OverlayConfirmPrompt = .none,
                          islandFolded: Bool = false) -> NSSize {
        if !hasIsland, prompt == .none, confirm == .none {
            if showingBubble {
                return NSSize(width: max(petSize, bubbleMinWidth),
                              height: petSize + bubbleHeadroom)
            }
            return NSSize(width: petSize, height: petSize)
        }
        var promptH: CGFloat = 0
        switch confirm {
        case .forfeit: promptH = promptHeightForfeit + 8
        case .reset: promptH = promptHeightReset + 8
        case .none:
            switch prompt {
            case .none: break
            case .zeroTime: promptH = promptHeightZeroTime + 8
            case .checkIn: promptH = promptHeightCheckIn + 8
            }
        }
        let composerH = (hasIsland && composingNote) ? noteComposerHeight : 0
        let chevronW: CGFloat = hasIsland ? islandFoldChevronSize + islandGap : 0
        let foldedClockW: CGFloat = (hasIsland && islandFolded) ? islandFoldedClockWidth + islandGap : 0
        let showChrome = hasIsland && !islandFolded
        let needsPromptColumn = promptH > 0 || composerH > 0
        let contentW: CGFloat = (showChrome || needsPromptColumn) ? islandWidth + islandGap : 0
        let islandW = contentW + foldedClockW + chevronW
        let chromeH: CGFloat = showChrome ? islandHeight : 0
        let foldedClockH: CGFloat = (hasIsland && islandFolded) ? islandFoldedClockHeight : 0
        let column = chromeH + composerH + promptH
        let width = max(petSize + islandW, showingBubble ? bubbleMinWidth : petSize + islandW)
        let height = (showingBubble ? bubbleHeadroom : 0) + max(petSize, column, foldedClockH)
        return NSSize(width: width, height: height)
    }

    static func panelOrigin(petOrigin: NSPoint, petSize: CGFloat, panelSize: NSSize) -> NSPoint {
        panelOrigin(petOrigin: petOrigin, petSize: petSize, panelSize: panelSize, hasIsland: false)
    }

    static func panelOrigin(petOrigin: NSPoint, petSize: CGFloat, panelSize: NSSize,
                            hasIsland: Bool) -> NSPoint {
        if hasIsland {
            return NSPoint(x: petOrigin.x + petSize - panelSize.width, y: petOrigin.y)
        }
        let xInset = max(0, (panelSize.width - petSize) / 2)
        return NSPoint(x: petOrigin.x - xInset, y: petOrigin.y)
    }

    static func petOrigin(panelOrigin: NSPoint, petSize: CGFloat, panelSize: NSSize) -> NSPoint {
        petOrigin(panelOrigin: panelOrigin, petSize: petSize, panelSize: panelSize, hasIsland: false)
    }

    static func petOrigin(panelOrigin: NSPoint, petSize: CGFloat, panelSize: NSSize,
                          hasIsland: Bool) -> NSPoint {
        if hasIsland {
            return NSPoint(x: panelOrigin.x + panelSize.width - petSize, y: panelOrigin.y)
        }
        let xInset = max(0, (panelSize.width - petSize) / 2)
        return NSPoint(x: panelOrigin.x + xInset, y: panelOrigin.y)
    }

    /// Measure speech-bubble chrome for a title/body at the fixed content width (wrapping).
    /// Pure AppKit typography — keeps the layout test free of SwiftUI hosting.
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

    private func show() {
        let p = panel ?? makePanel()
        panel = p
        let wantAnimated = Self.shouldAnimate(lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled)
        if p.contentView == nil || builtAnimated != wantAnimated {
            let hosting = PetHostingView(rootView: AnyView(
                FloatingPetView(animated: wantAnimated)
                    .environment(store).environment(companion).environment(session)))
            hosting.onOpenPopover = onOpenPopover
            hosting.onHide = onHide
            hosting.onOpenToday = onOpenToday
            hosting.onNewIssue = onNewIssue
            hosting.canCreateIssue = { [weak self] in self?.store.canComposeLinearIssue ?? false }
            hosting.languageProvider = { [weak self] in self?.companion.language ?? .systemDefault }
            hosting.petSize = CGFloat(store.floatingPetSize)
            hosting.hasIsland = session.isActive
            hosting.onHoverChange = { [weak self] hovering in
                if hovering { self?.showHoverCallout() } else { self?.hideHoverCallout() }
            }
            p.contentView = hosting
            builtAnimated = wantAnimated
        }
        if let hosting = p.contentView as? PetHostingView {
            hosting.toolTip = currentHoverText()
            hosting.petSize = CGFloat(store.floatingPetSize)
            hosting.hasIsland = session.isActive
            hosting.onOpenToday = onOpenToday
            hosting.onNewIssue = onNewIssue
            hosting.canCreateIssue = { [weak self] in self?.store.canComposeLinearIssue ?? false }
        }
        let petSize = CGFloat(store.floatingPetSize)
        p.setFrame(targetFrame(petSize: petSize, showingBubble: store.currentSpeechBubble != nil),
                   display: true)
        p.orderFrontRegardless()
        let needsKey = Self.overlayNeedsKeyWindow(
            composingNote: session.isComposingNote, prompt: session.prompt)
        if needsKey, !textInputArmed {
            // Accessory apps ignore cooperative activate; same trap as the popover.
            NSApp.activate(ignoringOtherApps: true)
            p.makeKeyAndOrderFront(nil)
        }
        textInputArmed = needsKey
        if hoverPanel?.isVisible == true { showHoverCallout() }
    }

    private func hide() {
        hideHoverCallout()
        textInputArmed = false
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
        if store.currentSpeechBubble != nil || session.prompt != .none
            || session.forfeitPrompt != nil || session.resetPrompt
        { hideHoverCallout(); return }
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

    private var overlayConfirm: OverlayConfirmPrompt {
        if session.forfeitPrompt != nil { return .forfeit }
        if session.resetPrompt { return .reset }
        return .none
    }

    private func targetFrame(petSize: CGFloat, showingBubble: Bool) -> NSRect {
        let hasIsland = session.isActive
        let size = Self.panelSize(petSize: petSize, showingBubble: showingBubble,
                                  hasIsland: hasIsland, prompt: session.prompt,
                                  composingNote: session.isComposingNote,
                                  confirm: overlayConfirm,
                                  islandFolded: store.floatingPetIslandFolded)
        let petOrigin: NSPoint
        if let x = defaults.object(forKey: Self.originXKey) as? Double,
           let y = defaults.object(forKey: Self.originYKey) as? Double {
            petOrigin = NSPoint(x: x, y: y)
        } else {
            petOrigin = Self.defaultPetOrigin(petSize: petSize)
        }
        var frame = NSRect(origin: Self.panelOrigin(petOrigin: petOrigin, petSize: petSize,
                                                    panelSize: size, hasIsland: hasIsland),
                           size: size)
        if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) {
            let fallbackPet = Self.defaultPetOrigin(petSize: petSize)
            frame.origin = Self.panelOrigin(petOrigin: fallbackPet, petSize: petSize,
                                            panelSize: size, hasIsland: hasIsland)
        }
        return frame
    }

    private static func defaultPetOrigin(petSize: CGFloat) -> NSPoint {
        guard let visible = NSScreen.main?.visibleFrame else { return NSPoint(x: 120, y: 120) }
        return NSPoint(x: visible.maxX - petSize - 24, y: visible.minY + 24)
    }

    private func makePanel() -> FloatingPetPanel {
        let p = FloatingPetPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
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
        let hasIsland = session.isActive
        let size = Self.panelSize(petSize: petSize, showingBubble: store.currentSpeechBubble != nil,
                                  hasIsland: hasIsland, prompt: session.prompt,
                                  composingNote: session.isComposingNote,
                                  confirm: overlayConfirm,
                                  islandFolded: store.floatingPetIslandFolded)
        let pet = Self.petOrigin(panelOrigin: p.frame.origin, petSize: petSize,
                                 panelSize: size, hasIsland: hasIsland)
        defaults.set(Double(pet.x), forKey: Self.originXKey)
        defaults.set(Double(pet.y), forKey: Self.originYKey)
        if hoverPanel?.isVisible == true { showHoverCallout() }
    }
}

final class PetHostingView: NSHostingView<AnyView> {
    var onOpenPopover: (() -> Void)?
    var onHide: (() -> Void)?
    var onOpenToday: (() -> Void)?
    var onNewIssue: (() -> Void)?
    var canCreateIssue: () -> Bool = { false }
    var onHoverChange: ((Bool) -> Void)?
    var languageProvider: () -> AppLanguage = { .systemDefault }
    var hasIsland = false
    var petSize: CGFloat = 96

    private var mouseDownScreen: NSPoint?
    private var originAtDown: NSPoint?
    private var didDrag = false
    private var forwardingToSwiftUI = false

    override var mouseDownCanMoveWindow: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

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

    private var spriteRect: NSRect {
        NSRect(x: bounds.width - petSize, y: 0, width: petSize, height: petSize)
    }

    private func isInteractiveIsland(_ point: NSPoint) -> Bool {
        hasIsland && point.x < bounds.width - petSize
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            showContextMenu(event)
            return
        }
        let local = convert(event.locationInWindow, from: nil)
        if isInteractiveIsland(local) {
            forwardingToSwiftUI = true
            super.mouseDown(with: event)
            return
        }
        forwardingToSwiftUI = false
        mouseDownScreen = NSEvent.mouseLocation
        originAtDown = window?.frame.origin
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        if forwardingToSwiftUI {
            super.mouseDragged(with: event)
            return
        }
        guard let window, let start = mouseDownScreen, let origin = originAtDown else { return }
        let now = NSEvent.mouseLocation
        if !Self.isClick(from: start, to: now) { didDrag = true }
        window.setFrameOrigin(NSPoint(x: origin.x + (now.x - start.x),
                                      y: origin.y + (now.y - start.y)))
    }

    override func mouseUp(with event: NSEvent) {
        if forwardingToSwiftUI {
            forwardingToSwiftUI = false
            super.mouseUp(with: event)
            return
        }
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
        let today = menu.addItem(withTitle: l.todayDeskMenuOpen,
                                 action: #selector(handleOpenToday(_:)), keyEquivalent: "")
        today.target = self
        today.isEnabled = true
        let create = menu.addItem(withTitle: l.newLinearIssue,
                                  action: #selector(handleNewIssue(_:)), keyEquivalent: "")
        create.target = self
        create.isEnabled = canCreateIssue()
        let hide = menu.addItem(withTitle: l.floatingPetMenuHide,
                                action: #selector(handleHide(_:)), keyEquivalent: "")
        hide.target = self
        hide.isEnabled = true
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc func handleOpen(_ sender: Any?) { onOpenPopover?() }
    @objc func handleOpenToday(_ sender: Any?) { onOpenToday?() }
    @objc func handleNewIssue(_ sender: Any?) { onNewIssue?() }
    @objc func handleHide(_ sender: Any?) { onHide?() }
}

@MainActor
struct FloatingPetView: View {
    var animated: Bool = true
    @Environment(UsageStore.self) private var store
    @Environment(CompanionStore.self) private var companion
    @Environment(FocusSessionStore.self) private var session

    var body: some View {
        let size = CGFloat(store.floatingPetSize)
        let subject = companion.representativeSubject
        VStack(spacing: 8) {
            if let bubble = store.currentSpeechBubble {
                SpeechBubbleView(bubble: bubble)
                    .transition(.scale(scale: 0.8, anchor: .bottom).combined(with: .opacity))
                    .zIndex(1)
            }

            HStack(alignment: .bottom, spacing: FloatingPetController.islandGap) {
                if session.isActive {
                    if showsIslandColumn {
                        SessionIslandView()
                    }
                    if store.floatingPetIslandFolded {
                        foldedMiniClock
                    }
                    islandFoldChevron
                }
                SpriteView(speciesID: subject.speciesID, size: size, animated: animated,
                           shiny: subject.isShiny,
                           minFrameDelay: store.animationQuality.frameFloor)
                    .frame(width: size, height: size)
                    .zIndex(0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .animation(animated ? .spring(response: 0.3, dampingFraction: 0.7) : nil,
                   value: store.currentSpeechBubble)
    }

    private var showsIslandColumn: Bool {
        if !store.floatingPetIslandFolded { return true }
        return session.forfeitPrompt != nil
            || session.resetPrompt
            || session.prompt != .none
            || session.isComposingNote
    }

    private var foldedMiniClock: some View {
        let clock = session.clockDisplay()
        let l = companion.l
        return Button {
            store.floatingPetIslandFolded = false
        } label: {
            HStack(spacing: 3) {
                Text(clock.text)
                    .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if clock.overtime {
                    Text(l.overtimeAbbrev)
                        .font(.system(size: 8, weight: .bold))
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(Color.orange.opacity(0.2))
                        .foregroundStyle(.orange)
                        .clipShape(Capsule())
                }
            }
            .frame(
                width: FloatingPetController.islandFoldedClockWidth,
                height: FloatingPetController.islandFoldedClockHeight,
                alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(
            width: FloatingPetController.islandFoldedClockWidth,
            height: FloatingPetController.islandFoldedClockHeight)
        .contentShape(Rectangle())
        .help(l.expandTimer)
        .accessibilityLabel(l.expandTimer)
    }

    private var islandFoldChevron: some View {
        let l = companion.l
        return Button {
            store.floatingPetIslandFolded.toggle()
        } label: {
            Image(systemName: store.floatingPetIslandFolded ? "chevron.left" : "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(
                    width: FloatingPetController.islandFoldChevronSize,
                    height: FloatingPetController.islandFoldChevronSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(
            width: FloatingPetController.islandFoldChevronSize,
            height: FloatingPetController.islandFoldChevronSize)
        .contentShape(Rectangle())
        .help(store.floatingPetIslandFolded ? l.expandTimer : l.collapseTimer)
        .accessibilityLabel(store.floatingPetIslandFolded ? l.expandTimer : l.collapseTimer)
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

/// Transient speech bubble. Width is capped so copy wraps instead of clipping the panel.
@MainActor
private struct SpeechBubbleView: View {
    let bubble: UsageStore.SpeechBubble

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(bubble.title)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(bubble.isCritical ? .red : .primary)
            Text(bubble.body)
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
