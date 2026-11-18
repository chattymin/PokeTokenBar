import XCTest
@testable import PokeTokenBar

/// The Bag splits its items as the Achievements tabs do, so the 18 gym badges no longer bury the others; the items
/// themselves split between the raising and the dungeons since #183.
@MainActor
final class BagSectionTests: XCTestCase {
    func testItemsGoToTheirAchievementSection() {
        // The Legendary Egg and Type: Null's are eggs to use, in the raising tab since 2026-11-09 (the owner).
        for kind in [ItemKind.rareCandy, .mint, .shinyCharm, .fireStone, .shinyStone, .typeNullEgg, .legendaryEgg] {
            XCTAssertEqual(BagView.Section.of(kind), .raising, "\(kind)")
        }
        XCTAssertEqual(BagView.Section.of(.silverCapsule), .dungeons)
        for kind in ItemKind.allCases where kind.badgeType != nil {
            XCTAssertEqual(BagView.Section.of(kind), .badges, "\(kind)")
        }
        for kind in [ItemKind.soulDew, .relicStatue, .ovalCharm] {
            XCTAssertEqual(BagView.Section.of(kind), .artifacts, "\(kind)")
        }
    }

    /// The badges' effect is said once above them, with the Plain Badge's exception.
    func testTheBadgeHintNamesTheStepInEveryLanguage() {
        for language in AppLanguage.allCases {
            let l = L(language)
            XCTAssertTrue(l.bagBadgesHint.contains(l.percentNumber(CollectorBonus.badgeRegionBonus * 100)), "\(language)")
            if [.en, .fr].contains(language) {
                XCTAssertTrue(l.bagBadgesHint.contains(l.itemName(.plainBadge)), "\(language)")
            }
        }
    }
}
