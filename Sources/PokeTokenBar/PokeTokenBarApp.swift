import AppKit
import QuartzCore
import SwiftUI

@main
struct PokeTokenBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // 메뉴바는 AppDelegate 의 NSStatusItem 이 담당.
        // MenuBarExtra 라벨은 고빈도 갱신 시 재렌더링 폭주로 CPU/메모리 문제가 있어 사용하지 않는다.
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var store: UsageStore!
    private var companion: CompanionStore!
    private var updater: UpdateChecker!
    private let navigation = PopoverNavigation()

    // 메뉴바 캐릭터 애니메이션 — 단일 타이머로 프레임 순환.
    // 프레임 = 이미 22px 로 합성된 이미지 + delay. egg/static 은 2프레임 bob, animated 는 GIF 실제 프레임.
    private var menuSpriteKey: String?   // "id-shiny" — 같은 종이라도 shiny 여부가 바뀌면 재로딩
    private var menuFrames: [(image: NSImage, delay: TimeInterval)] = []
    private var menuIndex = 0
    private var menuTimer: Timer?
    private var menuLoadGen = 0     // async 로드 경합 방지
    private var displayAwake = true     // 디스플레이 켜짐 여부 (꺼지면 메뉴 애니메이션 정지 — 배터리)

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 서브프로세스(codex app-server 등) 파이프가 조기 종료로 끊겨도 SIGPIPE 로 앱이 죽지 않게
        // 무시한다. ProcessRunner 의 throwing write 와 함께 broken-pipe 크래시를 막는 이중 방어.
        signal(SIGPIPE, SIG_IGN)
        // 크래시·OOM·강제종료·런치실패를 로그에 남기는 전역 처리. 가능한 이르게(초기 크래시도 잡히게).
        CrashReporter.install(
            version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")
        NSApp.setActivationPolicy(.accessory)
        Self.migrateLegacyStorageIfNeeded()   // TokenMac → PokeTokenBar 리네임: 기존 companion/캐시 보존
        LoginItem.migrateFromLegacyLoginItemIfNeeded()   // 로그인아이템 → KeepAlive 에이전트(크래시 자동 재실행)
        store = UsageStore()
        companion = CompanionStore()
        updater = UpdateChecker()
        store.localizationLanguage = companion.language   // 알림 현지화용 미러 시드
        store.onRefresh = { [weak self] in self?.onStoreRefreshed() }   // 한도 로드 후 companion·사탕 지급
        Task { await updater.check() }                    // 기동 시 1회 업데이트 확인

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            setStatusImage(Self.eggImage(up: false))   // 초기 알도 전환 억제 경로로 통일(불변식)
            button.imagePosition = .imageLeading
            button.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
            button.cell?.usesSingleLineMode = false   // 사용량/한도를 2줄로 세로 스택 가능하게
            button.action = #selector(togglePopover)
            button.target = self
        }

        popover.behavior = .transient
        popover.delegate = self   // 닫힐 때(popoverDidClose) 호스팅 컨트롤러 해제 → 숨은 채 재레이아웃 비용 제거

        observeStore()
        observeDisplaySleep()
        applyState()
    }

    /// Observation 기반 상태 반영 — store 의 menuTitle(=menuLines) 변경 시 재호출.
    /// (isStale 은 더 이상 추적 안 함 — 메뉴바 dim 제거로 시각 출력에 관여하지 않음.)
    private func observeStore() {
        withObservationTracking {
            _ = store.menuTitle
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.applyState()
                self.observeStore()
            }
        }
    }

    private func applyState() {
        guard let button = statusItem.button else { return }
        Self.applyMenuText(store.menuLines, to: button)
        // stale 시각 dim 제거 — 슬립/런치 직후 refresh 완료 전 몇 초간 회색으로 보여 '고장/비활성'
        // 으로 오인되던 것 방지(사용자 반복 지적). 데이터가 오래됐다는 신호가 필요하면 팝오버
        // (limitsUpdatedAt 등)에서 제공하고, 메뉴바 아이콘·숫자는 흐리게 하지 않는다.
        button.appearsDisabled = false

        updateCompanion()
        ensureMenuAnimation()
        syncMenuAnimation()   // 가시성 상태 주기적 재평가(occlusion 이 잘못 멈춰도 자가 복구)
    }

    /// 메뉴바 버튼 텍스트 반영 — 1줄이면 기본 title(13pt), 2줄 이상이면 세로 스택.
    /// 줄 수에 맞춰 폰트를 자동 축소해 N줄이 메뉴바 높이에 클리핑 없이 들어오게 한다. 색을 지정하지
    /// 않아 메뉴바 명암(라이트/다크)·비활성(appearsDisabled) 상태에 자동 적응한다.
    private static func applyMenuText(_ lines: [String], to button: NSStatusBarButton) {
        if lines.count >= 2 {
            // NSStatusBarButton 은 멀티라인 title 을 세로 중앙에 두지 않고 위로 치우쳐 그린다(측정:
            // titleRect.y 가 음수 → 상단 클리핑 + 하단 여백, 사용자 지적). 그래서 baselineOffset 을
            // '런타임 측정'으로 보정한다: offset 0 으로 한번 세팅해 셀이 계산한 title 상자(titleRect)를
            // 재고, 그 상자 중앙을 버튼 중앙에 맞추는 offset 을 역산해 재적용. 매직넘버 없이 두께·폰트·
            // 아이콘에 자동 적응. 줄높이는 폰트 자연 줄높이(×1.16)보다 크게 둬 어센더 클리핑을 막는다.
            let thickness = NSStatusBar.system.thickness
            let share = thickness / CGFloat(lines.count)                 // 줄당 몫
            let fontSize = min(11, max(8, (share * 0.85).rounded(.down)))
            let effLH = min(share, (fontSize * 1.28).rounded())          // 자연 줄높이보다 크게(어센더 클리핑 방지)
            let font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .regular)
            func titled(_ offset: CGFloat) -> NSAttributedString {
                let para = NSMutableParagraphStyle()
                para.alignment = .center
                para.minimumLineHeight = effLH
                para.maximumLineHeight = effLH
                return NSAttributedString(
                    string: lines.joined(separator: "\n"),
                    attributes: [.font: font, .paragraphStyle: para, .baselineOffset: offset])
            }
            let bounds = button.bounds
            if bounds.height > 1 {
                // 1) offset 0 으로 측정 → 2) 상자 중앙을 버튼 중앙에 맞추는 보정량 역산 → 3) 재적용.
                // (측정용 title 은 표시 전 즉시 교체되므로 깜빡임 없음.)
                button.attributedTitle = titled(0)
                let r0 = (button.cell as? NSButtonCell)?.titleRect(forBounds: bounds) ?? bounds
                button.attributedTitle = titled(r0.midY - bounds.midY)
            } else {
                button.attributedTitle = titled(0)   // 레이아웃 전(폭 0) — 보정 없이, 다음 갱신에 재보정
            }
        } else {
            // 1줄로 되돌릴 때 이전 attributedTitle 이 남지 않게 먼저 비운다.
            button.attributedTitle = NSAttributedString(string: "")
            let title = lines.first ?? ""
            button.title = title.isEmpty ? "" : " " + title
        }
    }

    /// UsageStore 값 → CompanionStore (사용량 적립 + 표시 상태). 매 관찰 변경 시 호출.
    private func updateCompanion() {
        companion.update(
            todayTokens: store.todayTotalTokens,
            todayDate: LocalUsageReader.todayKey(),
            monthTotal: store.monthTotalTokens,
            burnTier: store.burnTier,
            limitWarning: store.isLimitWarning,
            hasUsageData: store.hasUsageData)
    }

    /// 매 refresh 완료 훅 — companion 갱신 + 사탕 지급(한도가 신선한 시점). 지급을 여기 묶는 이유는
    /// UsageStore.onRefresh 주석 참조(observeStore 만으론 한도 변경이 companion 에 안 전달되는 케이스).
    private func onStoreRefreshed() {
        updateCompanion()
        companion.grantCandies(from: store.candyEligibleWindows, limitsReady: store.limitsReady)
    }

    // MARK: 메뉴바 애니메이션

    /// 현재 포켓몬에 맞춰 메뉴바 프레임을 준비. 종이 바뀐 경우에만 재로딩.
    /// 정적 스프라이트로 먼저 보여주고, animated GIF 가 받아지면 교체한다(메뉴바도 GIF로 움직임).
    /// 에너지 통제는 ① delay 하한 0.2s(≈5fps) ② 안 보이면 정지(menuShouldAnimate) ③ 저전력 모드
    /// 에선 GIF 생략(가벼운 bob)로 처리한다 — 통제된 저프레임 + 비가시 시 정지로 저전력.
    private func ensureMenuAnimation() {
        let id = companion.currentSpeciesID
        let shiny = companion.currentIsShiny
        let key = id.map { "\($0)-\(shiny)" }
        if key == menuSpriteKey, !menuFrames.isEmpty { return }   // 이미 이 개체로 애니메이션 중
        menuSpriteKey = key
        menuLoadGen += 1
        let gen = menuLoadGen

        guard let id else {                  // 알: 2프레임 bob
            setMenuFrames(Self.eggFrames())
            return
        }
        // 정적 스프라이트 bob 을 먼저(없으면 받아와서). GIF 가 받아지면 아래에서 교체.
        if let cached = SpriteLoader.cachedImage(speciesID: id, shiny: shiny) {
            setMenuFrames(Self.bobFrames(from: cached))
        } else {
            setMenuFrames(Self.eggFrames())
            Task { @MainActor [weak self] in
                guard let self, gen == self.menuLoadGen,
                      let sprite = await SpriteLoader.image(speciesID: id, shiny: shiny) else { return }
                guard gen == self.menuLoadGen else { return }
                self.setMenuFrames(Self.bobFrames(from: sprite))
            }
        }

        // 풀 GIF 애니메이션(저전력 모드에서는 생략하고 bob 유지). delay 하한 0.1s(≤10fps)로 redraw 통제.
        guard !ProcessInfo.processInfo.isLowPowerModeEnabled else { return }
        Task { @MainActor [weak self] in
            guard let self, gen == self.menuLoadGen else { return }
            // shiny GIF 미제공 종이면 일반 GIF 폴백
            var data = await SpriteStore.shared.data(speciesID: id, animated: true, shiny: shiny)
            if data == nil, shiny {
                data = await SpriteStore.shared.data(speciesID: id, animated: true, shiny: false)
            }
            guard let data else { return }
            let raw = GIFDecoder.frames(from: data)
            guard raw.count > 1, gen == self.menuLoadGen else { return }
            // 메뉴바 GIF 는 delay 하한 0.2s(≈5fps)로 캡 — 22px 스프라이트엔 충분하고 저전력.
            self.setMenuFrames(raw.map { (Self.menuBarImage(from: $0.image, up: false), max(0.2, $0.delay)) })
        }
    }

    private func setMenuFrames(_ frames: [(image: NSImage, delay: TimeInterval)]) {
        menuFrames = frames
        menuIndex = 0
        advanceMenu()
    }

    /// 상태아이템 이미지 교체 — 암묵적 CA 전환(NSStatusItemScene updateSettings:transition) 억제.
    /// 레이어 백드 NSStatusBarButton 은 button.image 대입마다 전환 애니메이션을 돌려 상태바를 재합성한다
    /// (측정: idle CPU 주범 — updateSettings:transition → NSAnimationContext runAnimationGroup → 셀 리드로우).
    /// setDisableActions 로 전환 없이 즉시 반영해 프레임당 비용을 값싼 리드로우로 낮춘다.
    private func setStatusImage(_ image: NSImage?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        statusItem.button?.image = image
        CATransaction.commit()
    }

    /// 현재 프레임을 메뉴바에 올리고, 그 프레임의 delay 후 다음 프레임 예약(자기 재예약).
    private func advanceMenu() {
        menuTimer?.invalidate()
        menuTimer = nil
        guard !menuFrames.isEmpty else { return }
        let frame = menuFrames[menuIndex % menuFrames.count]
        setStatusImage(frame.image)   // 현재 프레임은 항상 반영(정지 중에도 올바른 스프라이트). 전환 억제 대입.
        // 화면 꺼짐/메뉴바 가림(occlusion) 또는 단일 프레임이면 다음 프레임 예약 안 함 → 정지(낭비 제거).
        guard menuShouldAnimate, menuFrames.count > 1 else { return }
        let timer = Timer(timeInterval: frame.delay, repeats: false) { [weak self] _ in
            // 메인 런루프에서 발화 → Task 없이 동기 처리(프레임당 Task 할당 제거, 배터리)
            MainActor.assumeIsolated {
                guard let self else { return }
                self.menuIndex = (self.menuIndex + 1) % self.menuFrames.count
                self.advanceMenu()
            }
        }
        timer.tolerance = frame.delay * 0.3   // 웨이크업 코얼레싱 (배터리)
        RunLoop.main.add(timer, forMode: .common)
        menuTimer = timer
    }

    /// 메뉴바가 실제로 보이고(occlusion) 화면이 켜져 있을 때만 애니메이션 — 안 보이면 정지(낭비 제거).
    private var menuShouldAnimate: Bool {
        // 팝오버 열림 중엔 정지 — 팝오버 SpriteView 가 이미 컴패니언을 움직여 중복이고, 트래킹 중 상태아이콘
        // 리드로우는 WindowServer 부하(다른 앱 비컨볼) 위험. (status-item 앱은 occlusion 이 실제로 잘 안 떠서
        // displayAwake 슬립 게이팅이 실질 방어 — occlusion 체크는 유지하되 보조적.)
        displayAwake && !popover.isShown
            && (statusItem.button?.window?.occlusionState.contains(.visible) ?? true)
    }

    // MARK: 프레임 합성 (22px)

    /// 스프라이트 정적 + 가벼운 상하 bob 2프레임 (animated 미지원/로딩 폴백).
    private static func bobFrames(from sprite: NSImage) -> [(image: NSImage, delay: TimeInterval)] {
        [(menuBarImage(from: sprite, up: false), 0.5), (menuBarImage(from: sprite, up: true), 0.5)]
    }

    /// 부화 전/로딩 중 알 글리프 2프레임 bob.
    private static func eggFrames() -> [(image: NSImage, delay: TimeInterval)] {
        [(eggImage(up: false), 0.5), (eggImage(up: true), 0.5)]
    }

    private static func menuBarImage(from sprite: NSImage, up: Bool) -> NSImage {
        let h: CGFloat = 22
        let img = NSImage(size: NSSize(width: h, height: h))
        img.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .none
        let off: CGFloat = up ? 1 : 0
        sprite.draw(in: NSRect(x: 1, y: off, width: h - 2, height: h - 2),
                    from: .zero, operation: .sourceOver, fraction: 1)
        img.unlockFocus()
        return img
    }

    /// TokenMac→PokeTokenBar 리네임에 따른 1회 이전: 기존 Application Support 폴더를
    /// 새 이름으로 옮겨 companion 진행상황·스프라이트 캐시·스냅샷을 보존한다(신규 폴더 없을 때만).
    private static func migrateLegacyStorageIfNeeded() {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let old = base.appendingPathComponent("TokenMac")
        let new = base.appendingPathComponent("PokeTokenBar")
        guard fm.fileExists(atPath: old.path), !fm.fileExists(atPath: new.path) else { return }
        try? fm.moveItem(at: old, to: new)
    }

    /// 스프라이트가 아직 없을 때(부화 전/로딩 중) 메뉴바에 표시하는 알 글리프.
    private static func eggImage(up: Bool) -> NSImage {
        let h: CGFloat = 22
        let img = NSImage(size: NSSize(width: h, height: h))
        img.lockFocus()
        let off: CGFloat = up ? 1 : 0
        let s = "🥚" as NSString
        s.draw(in: NSRect(x: 2, y: off, width: h - 2, height: h - 2),
               withAttributes: [.font: NSFont.systemFont(ofSize: 15)])
        img.unlockFocus()
        return img
    }

    /// 팝오버 콘텐츠(SwiftUI 호스팅) 생성. .transient 팝오버는 contentViewController 를 평생 보유해 닫혀도
    /// NSHostingView 트리가 상주하며 매 디스플레이 사이클 재레이아웃된다(측정: idle CPU 최대 비용 — 닫힌
    /// 팝오버의 relative-time Text self-invalidation × 메뉴 애니메이션 CA 커밋). 그래서 열 때 만들고 닫힐 때 해제.
    private func buildPopoverContent() {
        popover.contentViewController = NSHostingController(
            rootView: PopoverView()
                .environment(store).environment(companion).environment(updater).environment(navigation))
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)   // 해제·메뉴 애니메이션 재개는 popoverDidClose 에서
        } else {
            navigation.reset()   // 닫혔다 열리면 항상 Home 으로 (설정 화면 잔류 방지)
            buildPopoverContent()   // 열 때 호스팅 트리 생성(닫힐 때 해제)
            // LSUIElement 앱이 비활성이면 팝오버 내부 버튼 클릭이 무시됨 — show 전에 활성화 보장
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKeyAndOrderFront(nil)
            syncMenuAnimation()   // 팝오버 열림 → 메뉴바 애니메이션 정지(중복 + WindowServer 부하 회피)
            store.requestNotificationAuthorizationIfNeeded()   // 알림 권한은 사용자가 앱을 처음 열 때 요청
            Task { await updater.check() }   // 팝오버 열 때 재확인(내부 minInterval 디바운스)
        }
    }

    /// 팝오버가 닫히면 호스팅 컨트롤러 해제(숨은 트리 재레이아웃 비용 제거) + 메뉴바 애니메이션 재개.
    func popoverDidClose(_ notification: Notification) {
        popover.contentViewController = nil
        syncMenuAnimation()
    }

    // MARK: 디스플레이 / 메뉴바 가시성 (에너지 절약 — 안 보이면 애니메이션 정지)

    private func observeDisplaySleep() {
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.setDisplayAwake(false) }
        }
        workspace.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.setDisplayAwake(true) }
        }
        // 메뉴바가 가려지면(풀스크린 등으로 occlusion) 애니메이션 정지, 다시 보이면 재개.
        NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.syncMenuAnimation() }
        }
    }

    private func setDisplayAwake(_ awake: Bool) {
        displayAwake = awake
        syncMenuAnimation()
    }

    /// menuShouldAnimate 상태에 맞춰 애니메이션을 재개/정지한다(멱등 — 중복 호출 안전).
    private func syncMenuAnimation() {
        if menuShouldAnimate {
            if menuTimer == nil { advanceMenu() }   // 재개
        } else {
            menuTimer?.invalidate()
            menuTimer = nil
        }
    }
}
