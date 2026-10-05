import AppKit
import XCTest
@testable import PokeTokenBar

@MainActor
final class StatusItemMenuTests: XCTestCase {
    private let reportedCost = UsageCost(amount: 5.09, coverage: CostCoverage(reported: true))

    // MARK: click routing

    func testRightClickOpensMenu() {
        XCTAssertTrue(StatusItemMenu.opensMenu(eventType: .rightMouseUp, modifiers: []))
    }

    func testPlainLeftClickKeepsThePopover() {
        XCTAssertFalse(StatusItemMenu.opensMenu(eventType: .leftMouseUp, modifiers: []))
        XCTAssertFalse(StatusItemMenu.opensMenu(eventType: .leftMouseUp, modifiers: [.command, .option]))
    }

    /// One-button mice and trackpads without secondary click rely on this branch alone.
    func testControlClickOpensMenu() {
        XCTAssertTrue(StatusItemMenu.opensMenu(eventType: .leftMouseUp, modifiers: [.control]))
    }

    /// A programmatic `performClick` has no current event; it must not turn into a menu.
    func testMissingEventKeepsThePopover() {
        XCTAssertFalse(StatusItemMenu.opensMenu(eventType: nil, modifiers: [.control]))
    }

    // MARK: contents

    func testEntriesInOrderWithShortcuts() {
        let l = L(.en)
        let entries = StatusItemMenu.entries(l: l, todayTokens: 19_400_000, todayCost: reportedCost,
                                             floatingPetEnabled: true)
        XCTAssertEqual(entries, [
            .init(title: "Today's tokens 19.4M · $5.09", keyEquivalent: "", action: nil),
            nil,
            .init(title: l.refreshNow, keyEquivalent: "r", action: .refresh),
            .init(title: l.dexTitle, keyEquivalent: "d", action: .openDex),
            .init(title: "Settings…", keyEquivalent: ",", action: .openSettings),
            .init(title: l.floatingPetHideLabel, keyEquivalent: "", action: .toggleFloatingPet),
            nil,
            .init(title: l.quit, keyEquivalent: "q", action: .quit),
        ])
    }

    func testFloatingPetRowOffersShowWhenHidden() {
        let l = L(.ko)
        let entries = StatusItemMenu.entries(l: l, todayTokens: 0, todayCost: nil, floatingPetEnabled: false)
        let row = entries.compactMap { $0 }.first { $0.action == .toggleFloatingPet }
        XCTAssertEqual(row?.title, l.floatingPetEnableLabel)
    }

    func testSummaryOmitsCostWhenNoProviderReportsOne() {
        XCTAssertEqual(StatusItemMenu.summary(l: L(.ko), todayTokens: 987, todayCost: nil), "오늘 사용한 토큰 987")
    }

    // MARK: NSMenu

    func testBuiltMenuKeepsSummaryDisabledAndRoutesActions() throws {
        let entries = StatusItemMenu.entries(l: L(.en), todayTokens: 1, todayCost: nil, floatingPetEnabled: true)
        let target = NSObject()
        let menu = StatusItemMenu.build(entries, target: target, selector: #selector(NSObject.description))

        XCTAssertEqual(menu.items.count, entries.count)
        XCTAssertFalse(menu.items[0].isEnabled, "the summary row is information, not a command")
        XCTAssertNil(StatusItemMenu.action(of: menu.items[0]))
        XCTAssertTrue(menu.items[1].isSeparatorItem)

        let quit = try XCTUnwrap(menu.items.last)
        XCTAssertTrue(quit.isEnabled)
        XCTAssertTrue(quit.target === target)
        XCTAssertEqual(StatusItemMenu.action(of: quit), .quit)
        XCTAssertEqual(quit.keyEquivalentModifierMask, .command)
    }
}
