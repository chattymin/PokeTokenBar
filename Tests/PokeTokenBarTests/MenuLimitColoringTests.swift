import XCTest
import AppKit
@testable import PokeTokenBar

final class MenuLimitColoringTests: XCTestCase {
    private func color(_ string: NSAttributedString, at location: Int) -> NSColor? {
        string.attribute(.foregroundColor, at: location, effectiveRange: nil) as? NSColor
    }

    /// Only the items are colored — not the separator and not the token/cost line above them.
    func testColorsWholeItemsAndNothingElse() {
        let title = NSMutableAttributedString(string: "1.2M · $3.40\nClaude 40% · Codex 70%")
        MenuLimitColoring.apply([.init(text: "Claude 40%", tier: .onPace), .init(text: "Codex 70%", tier: .over)],
                                to: title)
        let text = title.string as NSString
        let claude = text.range(of: "Claude 40%")
        let codex = text.range(of: "Codex 70%")

        XCTAssertNil(color(title, at: 0), "token/cost line keeps the system color")
        XCTAssertEqual(color(title, at: claude.location), NSColor(PaceTier.onPace.color))
        XCTAssertEqual(color(title, at: NSMaxRange(claude) - 1), NSColor(PaceTier.onPace.color))
        XCTAssertNil(color(title, at: NSMaxRange(claude) + 1), "separator keeps the system color")
        XCTAssertEqual(color(title, at: codex.location), NSColor(PaceTier.over.color))
        XCTAssertEqual(color(title, at: text.length - 1), NSColor(PaceTier.over.color))
    }

    /// Attention mode leaves out calm items; the colored item still gets its own range.
    func testASkippedItemDoesNotShiftTheNextOne() {
        let title = NSMutableAttributedString(string: "Claude 40% · Codex 70%")
        MenuLimitColoring.apply([.init(text: "Codex 70%", tier: .over)], to: title)
        XCTAssertNil(color(title, at: 0))
        XCTAssertEqual(color(title, at: (title.string as NSString).range(of: "Codex").location),
                       NSColor(PaceTier.over.color))
    }

    func testARunWhoseTextIsMissingIsIgnored() {
        let title = NSMutableAttributedString(string: "Claude 40%")
        MenuLimitColoring.apply([.init(text: "Codex 70%", tier: .over), .init(text: "Claude 40%", tier: .onPace)],
                                to: title)
        XCTAssertEqual(color(title, at: 0), NSColor(PaceTier.onPace.color))
    }
}
