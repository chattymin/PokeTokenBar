import XCTest
@testable import PokeTokenBar

@MainActor
final class BattleNavigationTests: XCTestCase {
    func testClosingPopoverDropsBattleScreenAndReturnsHome() {
        let navigation = PopoverNavigation()
        navigation.tab = .collection
        navigation.showingBattle = true
        navigation.reset()
        XCTAssertFalse(navigation.showingBattle)
        XCTAssertEqual(navigation.tab, .home)
    }

    func testOpeningBattleDropsCoveredDexDetail() {
        let navigation = PopoverNavigation()
        navigation.openDexEntry(collectionID: "25")
        navigation.showingBattle = true
        XCTAssertNil(navigation.dexDetailCollectionID)
    }
}
