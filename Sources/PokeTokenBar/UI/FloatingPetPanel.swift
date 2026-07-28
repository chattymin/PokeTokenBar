import AppKit
import SwiftUI

/// 데스크톱 위에 떠 있는 컴패니언 포켓몬 오버레이(옵트인, 설정 → 플로팅 펫).
/// - 위치는 사용자가 드래그로만 옮긴다(커스텀 mouseDragged — 클릭과 충돌하지 않게).
/// - 클릭 → 팝오버 오픈, 우클릭 → 컨텍스트 메뉴, 호버 → 오늘 사용량 콜아웃.
/// - 에너지: 숨김·디스플레이 슬립 시 SwiftUI 호스팅 트리를 해제한다.
@MainActor
final class FloatingPetController: NSObject, NSWindowDelegate {
    private let store: UsageStore
    private let companion: CompanionStore
    private let defaults: UserDefaults
    private var panel: NSPanel?
    private var hoverPanel: NSPanel?
    private var displayAwake = true
    private var builtAnimated: Bool?        // 현재 contentView 가 어떤 animated 상태로 지어졌나(nil=없음)
    private var powerObserver: NSObjectProtocol?

    private static let originXKey = "floatingPetOriginX"
    private static let originYKey = "floatingPetOriginY"

    /// Squared movement (pt²) below which a mouse-up counts as a click, not a drag.
    static let clickThresholdSquared: CGFloat = 16  // ~4pt

    private var onOpenPopover: (() -> Void)?
    private var onHide: (() -> Void)?

    init(store: UsageStore, companion: CompanionStore, defaults: UserDefaults = .standard,
         onOpenPopover: (() -> Void)? = nil, onHide: (() -> Void)? = nil) {
        self.store = store
        self.companion = companion
        self.defaults = defaults
        self.onOpenPopover = onOpenPopover
        self.onHide = onHide
        super.init()
        observeSettings()
        observePowerState()
        sync()
    }

    /// Pure click-vs-drag gate — tested without AppKit event delivery.
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
            _ = store.todayTotalTokens
            _ = store.highestLimitUtilization
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

    static func shouldAnimate(lowPower: Bool) -> Bool { !lowPower }

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
                FloatingPetView(animated: wantAnimated).environment(store).environment(companion)))
            hosting.onOpenPopover = onOpenPopover
            hosting.onHide = onHide
            hosting.languageProvider = { [weak self] in self?.companion.language ?? .systemDefault }
            hosting.onHoverChange = { [weak self] hovering in
                if hovering { self?.showHoverCallout() } else { self?.hideHoverCallout() }
            }
            p.contentView = hosting
            builtAnimated = wantAnimated
        }
        if let hosting = p.contentView as? PetHostingView {
            // Belt-and-suspenders with the custom callout (LSUIElement often suppresses NSToolTip).
            hosting.toolTip = currentHoverText()
        }
        p.setFrame(targetFrame(size: CGFloat(store.floatingPetSize)), display: true)
        p.orderFrontRegardless()
        // Refresh callout text if currently visible.
        if hoverPanel?.isVisible == true { showHoverCallout() }
    }

    private func hide() {
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
            l: L(companion.language))
    }

    /// Custom callout — `NSView.toolTip` / `.help()` often never appear on a non-activating
    /// LSUIElement panel even with `allowsToolTipsWhenApplicationIsInactive`.
    private func showHoverCallout() {
        guard let pet = panel, pet.isVisible else { return }
        let text = currentHoverText()
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .labelColor
        label.backgroundColor = .clear
        label.drawsBackground = false
        label.sizeToFit()

        let pad: CGFloat = 8
        let size = NSSize(width: label.bounds.width + pad * 2,
                          height: label.bounds.height + pad * 2)
        let container = NSView(frame: NSRect(origin: .zero, size: size))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        container.layer?.cornerRadius = 8
        container.layer?.borderWidth = 0.5
        container.layer?.borderColor = NSColor.separatorColor.cgColor
        label.frame.origin = NSPoint(x: pad, y: pad)
        container.addSubview(label)

        let hp = hoverPanel ?? makeHoverPanel()
        hoverPanel = hp
        hp.contentView = container
        hp.setContentSize(size)
        // Place above the pet, horizontally centered.
        let petFrame = pet.frame
        let origin = NSPoint(
            x: petFrame.midX - size.width / 2,
            y: petFrame.maxY + 6)
        hp.setFrameOrigin(origin)
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
        p.ignoresMouseEvents = true   // don't steal hover from the pet
        p.animationBehavior = .none
        return p
    }

    private func targetFrame(size: CGFloat) -> NSRect {
        var origin: NSPoint
        if let x = defaults.object(forKey: Self.originXKey) as? Double,
           let y = defaults.object(forKey: Self.originYKey) as? Double {
            origin = NSPoint(x: x, y: y)
        } else {
            origin = Self.defaultOrigin(size: size)
        }
        var frame = NSRect(origin: origin, size: NSSize(width: size, height: size))
        if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) {
            frame.origin = Self.defaultOrigin(size: size)
        }
        return frame
    }

    private static func defaultOrigin(size: CGFloat) -> NSPoint {
        guard let visible = NSScreen.main?.visibleFrame else { return NSPoint(x: 120, y: 120) }
        return NSPoint(x: visible.maxX - size - 24, y: visible.minY + 24)
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 96, height: 96),
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
        // Still set — helps if anything falls back to NSToolTip.
        p.allowsToolTipsWhenApplicationIsInactive = true
        p.animationBehavior = .none
        p.delegate = self
        return p
    }

    func windowDidMove(_ notification: Notification) {
        guard let p = panel, p.isVisible else { return }
        defaults.set(Double(p.frame.origin.x), forKey: Self.originXKey)
        defaults.set(Double(p.frame.origin.y), forKey: Self.originYKey)
        if hoverPanel?.isVisible == true { showHoverCallout() }
    }
}

/// Hosts the SwiftUI pet. Owns click / drag / context-menu / hover tracking.
final class PetHostingView: NSHostingView<AnyView> {
    var onOpenPopover: (() -> Void)?
    var onHide: (() -> Void)?
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
        // `.activeAlways` — LSUIElement app is almost never "active"; without it hover never fires.
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { onHoverChange?(true) }
    override func mouseExited(with event: NSEvent) { onHoverChange?(false) }

    override func mouseDown(with event: NSEvent) {
        // Control-click is the accessibility equivalent of a right-click.
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

    /// `menu(for:)` alone is unreliable on `NSHostingView` — pop up explicitly.
    private func showContextMenu(_ event: NSEvent) {
        let l = L(languageProvider())
        let menu = NSMenu(title: "")
        let open = menu.addItem(withTitle: l.floatingPetMenuOpen,
                                action: #selector(handleOpen), keyEquivalent: "")
        open.target = self
        let hide = menu.addItem(withTitle: l.floatingPetMenuHide,
                                action: #selector(handleHide), keyEquivalent: "")
        hide.target = self
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func handleOpen() { onOpenPopover?() }
    @objc private func handleHide() { onHide?() }
}

struct FloatingPetView: View {
    static let frameFloor: TimeInterval = 0.4
    var animated: Bool = true
    @Environment(UsageStore.self) private var store
    @Environment(CompanionStore.self) private var companion

    var body: some View {
        let size = CGFloat(store.floatingPetSize)
        SpriteView(speciesID: companion.currentSpeciesID, size: size, animated: animated,
                   shiny: companion.currentIsShiny, minFrameDelay: Self.frameFloor)
            .frame(width: size, height: size)
    }

    static func hoverTooltip(todayTokens: Int, limitUtilization: Double?, l: L) -> String {
        let usage = TokenFormatter.grouped(todayTokens)
        if let pct = limitUtilization {
            return l.floatingPetHoverWithLimit(usage, TokenFormatter.percent(pct))
        }
        return l.floatingPetHoverTokensOnly(usage)
    }
}
