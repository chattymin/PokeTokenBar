import AppKit
import XCTest
@testable import PokeTokenBar

/// ⌘, 가 빈 창을 띄우던 결함의 가드.
///
/// 이 앱의 설정은 팝오버 안에만 있는데 SwiftUI `Settings` 씬이 ⌘, 를 가져가, 눌러도 아무것도 없는
/// 창이 떴다. 고치는 방법은 앱 메뉴 항목을 우리 액션으로 돌리는 것이고, **찾기가 곧 계약** 이다 —
/// 못 찾으면 조용히 예전 동작으로 돌아간다.
@MainActor
final class SettingsMenuItemTests: XCTestCase {

    /// 제목이 아니라 셀렉터로 찾아야 한다. 시스템 언어가 한국어면 항목 제목은 "설정…" 이라
    /// 제목 매칭은 그 기기에서만 조용히 실패한다 — 개발 기기에서는 끝까지 안 드러나는 부류다.
    func testFindsSettingsItemRegardlessOfLocalizedTitle() throws {
        let menu = NSMenu()
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About", action: nil, keyEquivalent: "")
        let settings = NSMenuItem(
            title: "설정…", action: Selector(("showSettingsWindow:")), keyEquivalent: ",")
        appMenu.addItem(settings)
        appMenuItem.submenu = appMenu
        menu.addItem(appMenuItem)

        XCTAssertIdentical(SettingsMenuItem.find(in: menu), settings)
    }

    /// macOS 13 미만의 이름도 받는다.
    func testFindsLegacyPreferencesSelector() throws {
        let menu = NSMenu()
        let container = NSMenuItem()
        let sub = NSMenu()
        let legacy = NSMenuItem(
            title: "Preferences…", action: Selector(("showPreferencesWindow:")), keyEquivalent: ",")
        sub.addItem(legacy)
        container.submenu = sub
        menu.addItem(container)

        XCTAssertIdentical(SettingsMenuItem.find(in: menu), legacy)
    }

    /// SwiftUI 가 만든 항목은 알려진 셀렉터 어느 쪽도 아니었다(실측) — 그때는 ⌘, 로 찾는다.
    func testFindsByCommandCommaWhenSelectorIsUnrecognized() throws {
        let menu = NSMenu()
        let container = NSMenuItem()
        let sub = NSMenu()
        let unknown = NSMenuItem(
            title: "Settings…", action: Selector(("someSwiftUIInternal:")), keyEquivalent: ",")
        unknown.keyEquivalentModifierMask = [.command]
        sub.addItem(unknown)
        container.submenu = sub
        menu.addItem(container)

        XCTAssertIdentical(SettingsMenuItem.find(in: menu), unknown)
    }

    /// ⌘ 없이 "," 만 쓰는 항목은 설정이 아니다.
    func testIgnoresCommaWithoutCommandModifier() {
        let menu = NSMenu()
        let container = NSMenuItem()
        let sub = NSMenu()
        let plain = NSMenuItem(title: "Something", action: Selector(("x:")), keyEquivalent: ",")
        plain.keyEquivalentModifierMask = [.shift]
        sub.addItem(plain)
        container.submenu = sub
        menu.addItem(container)

        XCTAssertNil(SettingsMenuItem.find(in: menu))
    }

    /// 없으면 nil — 호출부가 폴백(브리지)으로 갈 수 있게 실패를 숨기지 않는다.
    func testReturnsNilWhenNoSettingsItemExists() {
        let menu = NSMenu()
        let item = NSMenuItem()
        let sub = NSMenu()
        sub.addItem(withTitle: "Quit", action: Selector(("terminate:")), keyEquivalent: "q")
        sub.items.last?.keyEquivalentModifierMask = [.command]
        item.submenu = sub
        menu.addItem(item)

        XCTAssertNil(SettingsMenuItem.find(in: menu))
    }

    func testRetargetRewiresTargetAndAction() throws {
        final class Receiver: NSObject {
            @objc func openIt(_ sender: Any?) {}
        }
        let receiver = Receiver()
        let menu = NSMenu()
        let container = NSMenuItem()
        let sub = NSMenu()
        let settings = NSMenuItem(
            title: "Settings…", action: Selector(("showSettingsWindow:")), keyEquivalent: ",")
        sub.addItem(settings)
        container.submenu = sub
        menu.addItem(container)

        let rewired = SettingsMenuItem.retarget(
            in: menu, to: receiver, action: #selector(Receiver.openIt(_:)))

        XCTAssertTrue(rewired)
        XCTAssertIdentical(settings.target as AnyObject, receiver)
        XCTAssertEqual(settings.action, #selector(Receiver.openIt(_:)))
        XCTAssertEqual(settings.keyEquivalent, ",", "⌘, 는 그대로 유지된다")
    }

    func testRetargetReportsFailureWhenItemIsAbsent() {
        let receiver = NSObject()
        XCTAssertFalse(
            SettingsMenuItem.retarget(in: NSMenu(), to: receiver, action: Selector(("noop:"))),
            "못 찾았으면 false 여야 폴백이 동작한다")
    }
}
