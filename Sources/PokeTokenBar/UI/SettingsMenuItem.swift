import AppKit
import SwiftUI

/// 앱 메뉴의 "Settings…"(⌘,) 항목을 찾는다.
///
/// **왜 필요한가.** 이 앱의 설정 화면은 팝오버 안에만 있다(`PopoverView` 가 `SettingsView` 를 렌더).
/// 그런데 SwiftUI `App` 은 최소 하나의 `Scene` 을 요구해서 `Settings { EmptyView() }` 를 두고 있고,
/// macOS 는 그 씬에 ⌘, 를 고정 연결한다 — 눌러도 **빈 창** 이 뜬다. 씬을 없앨 수는 없으므로
/// (다른 최소 씬은 실제 창을 띄워 더 나쁘다), 메뉴 항목의 target/action 을 우리 것으로 바꿔
/// 빈 창이 애초에 만들어지지 않게 한다.
///
/// **왜 셀렉터로 찾나.** 제목("Settings…")은 시스템 로케일을 따라 번역된다 — 한국어 시스템에서는
/// "설정…" 이라 제목 매칭은 그 기기에서 조용히 실패한다. 셀렉터는 로케일과 무관하다.
enum SettingsMenuItem {
    /// macOS 13+ 는 `showSettingsWindow:`, 그 이전은 `showPreferencesWindow:`.
    /// 문서화된 API 가 아니라 관측된 이름이라, 못 찾는 경우가 정상 경로로 존재한다 —
    /// 그래서 호출부는 실패를 조용히 넘기지 않고 폴백(`SettingsSceneBridge`)을 함께 둔다.
    static let actions: [Selector] = [
        Selector(("showSettingsWindow:")),
        Selector(("showPreferencesWindow:")),
    ]

    /// 메뉴 트리를 훑어 설정 항목을 돌려준다(서브메뉴 포함).
    ///
    /// 셀렉터를 먼저 보고, 못 찾으면 **⌘, 키 조합** 으로 찾는다. 실측(2026-09-02): SwiftUI 의
    /// `Settings` 씬이 만든 항목은 `showSettingsWindow:`·`showPreferencesWindow:` 어느 쪽도 아니었고,
    /// 셀렉터만 보던 구현은 항목이 눈앞에 있는데도 못 찾아 폴백 브리지로 떨어졌다(빈 창이 잠깐 뜸).
    /// 우리가 가로채려는 건 결국 "⌘, 를 누르면 열리는 것" 이므로, 키 조합이 셀렉터 이름보다
    /// 계약에 가깝고 SwiftUI 내부 변경에도 덜 흔들린다.
    static func find(in menu: NSMenu) -> NSMenuItem? {
        if let bySelector = first(in: menu, where: { item in
            guard let action = item.action else { return false }
            return actions.contains(action)
        }) {
            return bySelector
        }
        return first(in: menu) {
            $0.keyEquivalent == "," && $0.keyEquivalentModifierMask.contains(.command)
        }
    }

    private static func first(
        in menu: NSMenu, where matches: (NSMenuItem) -> Bool
    ) -> NSMenuItem? {
        for item in menu.items {
            if matches(item) { return item }
            if let submenu = item.submenu, let found = first(in: submenu, where: matches) {
                return found
            }
        }
        return nil
    }

    /// 찾은 항목을 주어진 target/action 으로 돌린다. 성공하면 true.
    @discardableResult
    static func retarget(in menu: NSMenu, to target: AnyObject, action: Selector) -> Bool {
        guard let item = find(in: menu) else { return false }
        item.target = target
        item.action = action
        return true
    }
}

/// `Settings` 씬의 폴백 내용 — 메뉴 항목 리타깃이 실패했을 때만 도달한다.
///
/// 아무것도 그리지 않고, 자기 창을 닫은 뒤 팝오버의 설정 화면을 연다. 창이 잠깐 보일 수는 있지만
/// **빈 창이 남는 것보다는 낫다** — 원래 결함이 정확히 "아무것도 없는 창이 떠 있다" 였다.
@MainActor
struct SettingsSceneBridge: View {
    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                // onAppear 시점엔 아직 창이 키가 아닐 수 있어 다음 런루프에서 처리한다.
                DispatchQueue.main.async {
                    NSApp.keyWindow?.close()
                    (NSApp.delegate as? AppDelegate)?.openSettingsFromMenu(nil)
                }
            }
    }
}
