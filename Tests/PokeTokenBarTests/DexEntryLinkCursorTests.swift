import XCTest
@testable import PokeTokenBar

/// A click on a dex link navigates the link view away while the pointer is still on it, so no hover
/// `.ended` arrives.
/// The decision returns a plain enum: in the test process `NSCursor.arrow` compares equal to nil. The disappearance must reset the hand cursor, or it sticks on the next screen.
@MainActor
final class DexEntryLinkCursorTests: XCTestCase {
    func testHoverShowsHandAndLeavingRestoresArrow() {
        XCTAssertEqual(DexEntryLink.cursor(after: .moved, wasHovered: false), .hand)
        XCTAssertEqual(DexEntryLink.cursor(after: .ended, wasHovered: true), .arrow)
    }

    func testDisappearingWhileHoveredRestoresArrow() {
        XCTAssertEqual(DexEntryLink.cursor(after: .disappeared, wasHovered: true), .arrow)
    }

    func testDisappearingUnhoveredLeavesOtherViewsCursorAlone() {
        XCTAssertNil(DexEntryLink.cursor(after: .disappeared, wasHovered: false))
    }
}
