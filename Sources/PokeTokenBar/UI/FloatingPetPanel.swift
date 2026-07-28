import AppKit
import SwiftUI

/// 데스크톱 위에 떠 있는 컴패니언 포켓몬 오버레이(옵트인, 설정 → 플로팅 펫).
/// - 위치는 사용자가 드래그로만 옮긴다(커스텀 mouseDragged — 클릭과 충돌하지 않게).
/// - 클릭 → 팝오버 오픈, 우클릭 → 컨텍스트 메뉴, 호버 → 오늘 사용량 툴팁.
/// - 에너지: 숨김·디스플레이 슬립 시 SwiftUI 호스팅 트리를 해제한다.
@MainActor
final class FloatingPetController: NSObject, NSWindowDelegate {
    private let store: UsageStore
    private let companion: CompanionStore
    private let defaults: UserDefaults
    private var panel: NSPanel?
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

    /// AppDelegate 의 디스플레이 슬립 게이팅과 연동 — 꺼진 화면 뒤에서 GIF 프레임 루프가 돌지 않게.
    func setDisplayAwake(_ awake: Bool) {
        displayAwake = awake
        sync()
    }

    /// 설정(켬/끔·크기) + 툴팁 소스 변경 관찰 — 재등록 패턴(AppDelegate.observeStore 와 동일).
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

    /// 저전력 모드 토글 관찰 — 켜지면 정적, 꺼지면 애니메이션 재개(패널 콘텐츠 재구성). 메뉴바 low-power 규율과 동일.
    private func observePowerState() {
        powerObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NSProcessInfoPowerStateDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.sync() }
        }
    }

    /// 저전력 모드면 애니메이션을 멈추고 정적 스프라이트로 — 배터리 절약. 순수·테스트용.
    static func shouldAnimate(lowPower: Bool) -> Bool { !lowPower }

    /// 설정·디스플레이 상태에 맞춰 표시/숨김·크기를 반영한다(멱등).
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
            p.contentView = hosting
            builtAnimated = wantAnimated
        }
        if let hosting = p.contentView as? PetHostingView {
            let l = L(companion.language)
            hosting.toolTip = FloatingPetView.hoverTooltip(
                todayTokens: store.todayTotalTokens,
                limitUtilization: store.highestLimitUtilization,
                l: l)
        }
        p.setFrame(targetFrame(size: CGFloat(store.floatingPetSize)), display: true)
        p.orderFrontRegardless()
    }

    private func hide() {
        guard let p = panel else { return }
        p.orderOut(nil)
        p.contentView = nil
        builtAnimated = nil
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
        // Drag is driven by PetHostingView.mouseDragged — background-move would swallow clicks.
        p.isMovableByWindowBackground = false
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.becomesKeyOnlyIfNeeded = true
        p.animationBehavior = .none
        p.delegate = self
        return p
    }

    func windowDidMove(_ notification: Notification) {
        guard let p = panel, p.isVisible else { return }
        defaults.set(Double(p.frame.origin.x), forKey: Self.originXKey)
        defaults.set(Double(p.frame.origin.y), forKey: Self.originYKey)
    }
}

/// Hosts the SwiftUI pet. Owns click / drag / context-menu so AppKit delivery is explicit
/// (non-activating panels are never key → menu items need `target = self`).
final class PetHostingView: NSHostingView<AnyView> {
    var onOpenPopover: (() -> Void)?
    var onHide: (() -> Void)?
    var languageProvider: () -> AppLanguage = { .systemDefault }

    private var mouseDownScreen: NSPoint?
    private var originAtDown: NSPoint?
    private var didDrag = false

    override var mouseDownCanMoveWindow: Bool { false }

    /// Same pure gate as `FloatingPetController.isClick` — kept here for the event path.
    static func isClick(from start: NSPoint, to end: NSPoint,
                        thresholdSquared: CGFloat = FloatingPetController.clickThresholdSquared) -> Bool {
        FloatingPetController.isClick(from: start, to: end, thresholdSquared: thresholdSquared)
    }

    override func mouseDown(with event: NSEvent) {
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

    override func menu(for event: NSEvent) -> NSMenu? {
        let l = L(languageProvider())
        let menu = NSMenu(title: "")
        let open = menu.addItem(withTitle: l.floatingPetMenuOpen,
                                action: #selector(handleOpen), keyEquivalent: "")
        open.target = self
        let hide = menu.addItem(withTitle: l.floatingPetMenuHide,
                                action: #selector(handleHide), keyEquivalent: "")
        hide.target = self
        return menu
    }

    @objc private func handleOpen() { onOpenPopover?() }
    @objc private func handleHide() { onHide?() }
}

/// 패널 콘텐츠 — 현재 컴패니언(알 포함)을 설정 크기로 표시.
struct FloatingPetView: View {
    /// GIF fps 하한(초). >0 필수 — 메뉴바와 동일한 0.4s(≈2.5fps) 캡.
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

    /// Pure tooltip builder (tokens always; limit % only when the compact surface may show it).
    static func hoverTooltip(todayTokens: Int, limitUtilization: Double?, l: L) -> String {
        let usage = TokenFormatter.grouped(todayTokens)
        if let pct = limitUtilization {
            return l.floatingPetHoverWithLimit(usage, TokenFormatter.percent(pct))
        }
        return l.floatingPetHoverTokensOnly(usage)
    }
}
