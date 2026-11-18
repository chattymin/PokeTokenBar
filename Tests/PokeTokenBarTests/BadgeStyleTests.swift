import SwiftUI
import XCTest
@testable import PokeTokenBar

/// [Regression] The owner, 2026-11-18: the dungeons' "T2" was white text on the light gray `.secondary` fill, unreadable
/// on the dark card. The gray badge is always tinted, whatever style a screen asks for.
@MainActor
final class BadgeStyleTests: XCTestCase {
    func testTheGrayBadgeIsAlwaysTinted() {
        XCTAssertEqual(Badge("T2", tint: .secondary, style: .solid, size: 10).resolvedStyle, .tinted)
        XCTAssertEqual(Badge("T2", tint: .secondary).resolvedStyle, .tinted, "solid by default, tinted for the gray")
        XCTAssertEqual(Badge("RARE", tint: .rarity(.rare)).resolvedStyle, .solid, "a colored fill keeps its white text")
        XCTAssertEqual(Badge("NEW", tint: .accent, style: .tinted).resolvedStyle, .tinted)
    }
}
