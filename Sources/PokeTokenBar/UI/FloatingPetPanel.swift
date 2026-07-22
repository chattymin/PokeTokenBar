import AppKit
import SwiftUI

/// 데스크톱 위에 떠 있는 컴패니언 포켓몬 오버레이(옵트인, 설정 → 플로팅 펫).
/// - 스스로 움직이지 않는다: 화면을 돌아다니는 로직이 없고, 위치는 사용자가 드래그로만 옮긴다.
/// - 위치는 UserDefaults 에 영속 — 재실행/재표시 시 복원, 화면 구성이 바뀌어 화면 밖이면 기본 위치로.
/// - 에너지: 숨김·디스플레이 슬립 시 SwiftUI 호스팅 트리를 해제한다(숨은 트리 상주 재레이아웃
///   비용 제거 — AppDelegate 의 popoverDidClose 패턴과 동일).
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

    init(store: UsageStore, companion: CompanionStore, defaults: UserDefaults = .standard) {
        self.store = store
        self.companion = companion
        self.defaults = defaults
        super.init()
        observeSettings()
        observePowerState()
        sync()
    }

    /// AppDelegate 의 디스플레이 슬립 게이팅과 연동 — 꺼진 화면 뒤에서 GIF 프레임 루프가 돌지 않게.
    func setDisplayAwake(_ awake: Bool) {
        displayAwake = awake
        sync()
    }

    /// 설정(켬/끔·크기) 변경 관찰 — 재등록 패턴(AppDelegate.observeStore 와 동일).
    /// 종/이로치 변경은 패널 내부 SwiftUI 가 environment 관찰로 스스로 갱신하므로 여기선 안 본다.
    private func observeSettings() {
        withObservationTracking {
            _ = store.floatingPetEnabled
            _ = store.floatingPetSize
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
        // 저전력 모드가 토글되면 animated 플래그가 바뀌므로 콘텐츠를 재구성(정적↔애니메이션 전환).
        let wantAnimated = Self.shouldAnimate(lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled)
        if p.contentView == nil || builtAnimated != wantAnimated {
            p.contentView = PetHostingView(rootView: AnyView(
                FloatingPetView(animated: wantAnimated).environment(store).environment(companion)))
            builtAnimated = wantAnimated
        }
        p.setFrame(targetFrame(size: CGFloat(store.floatingPetSize)), display: true)
        p.orderFrontRegardless()
    }

    private func hide() {
        guard let p = panel else { return }
        p.orderOut(nil)
        p.contentView = nil   // 숨은 SwiftUI 트리 해제(GIF 프레임 루프 정지 포함)
        builtAnimated = nil
    }

    /// 표시 프레임 — 저장된 위치(드래그 영속) 우선, 없으면 주 화면 우하단. 화면 밖이면 기본 위치로 복귀.
    private func targetFrame(size: CGFloat) -> NSRect {
        var origin: NSPoint
        if let x = defaults.object(forKey: Self.originXKey) as? Double,
           let y = defaults.object(forKey: Self.originYKey) as? Double {
            origin = NSPoint(x: x, y: y)
        } else {
            origin = Self.defaultOrigin(size: size)
        }
        var frame = NSRect(origin: origin, size: NSSize(width: size, height: size))
        // 화면 구성 변경(모니터 분리 등)으로 어떤 화면과도 안 겹치면 기본 위치로.
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
        p.isMovableByWindowBackground = true   // 유일한 이동 수단 — 자율 이동 없음
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.becomesKeyOnlyIfNeeded = true
        p.animationBehavior = .none
        p.delegate = self
        return p
    }

    // MARK: NSWindowDelegate — 드래그 위치 영속

    func windowDidMove(_ notification: Notification) {
        guard let p = panel, p.isVisible else { return }
        defaults.set(Double(p.frame.origin.x), forKey: Self.originXKey)
        defaults.set(Double(p.frame.origin.y), forKey: Self.originYKey)
    }
}

/// NSHostingView 는 콘텐츠에 따라 배경 드래그 이동을 막을 수 있어 명시 허용 — 패널 어디를 잡아도 이동.
private final class PetHostingView: NSHostingView<AnyView> {
    override var mouseDownCanMoveWindow: Bool { true }
}

/// 패널 콘텐츠 — 현재 컴패니언(알 포함)을 설정 크기로 표시. 종/이로치/크기 변경은 environment 관찰로 자동 반영.
/// `animated`=false(저전력 모드)면 정적 스프라이트로 고정. 애니메이션 시엔 fps 하한 0.4s(≈2.5fps)로
/// 캡 — 항상 떠 있는 표면이라 메뉴바 GIF 규율과 동일하게 idle wakeup 을 통제한다.
struct FloatingPetView: View {
    /// GIF fps 하한(초). >0 필수 — 0 이면 네이티브 fps 로 새어 메뉴바에서 고친 idle wakeup 회귀가 재발한다.
    /// 상시 표시 표면이라 메뉴바와 동일한 0.4s(≈2.5fps) 캡. 값 조정 시 여기 한 곳만 — 회귀 가드는 `frameFloor>0`.
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
}
