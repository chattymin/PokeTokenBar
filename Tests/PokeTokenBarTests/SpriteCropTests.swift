import XCTest
@testable import PokeTokenBar

/// Sprite content cropping — the geometry both frontends share.
///
/// The defect this guards is visible, not crashy: without cropping, a 96×96 canvas holding a 28×30
/// egg is scaled whole into the tray, so the egg draws at roughly a third of the available box and
/// reads as "the icon is broken". That is exactly how it shipped on Linux before this existed.
final class SpriteCropTests: XCTestCase {
    /// Treats a rectangle of content at a known offset as opaque.
    private func box(x: Int, y: Int, w: Int, h: Int) -> (Int, Int) -> Bool {
        { px, py in px >= x && px < x + w && py >= y && py < y + h }
    }

    func testCropsAwayTransparentPadding() {
        // The real egg case: 28×30 of content on a 96×96 canvas.
        let rect = SpriteCrop.squareContentRect(
            width: 96, height: 96, isOpaque: box(x: 34, y: 33, w: 28, h: 30))
        // The square takes the longer edge, so the subject fills the frame instead of ~29% of it.
        XCTAssertEqual(rect, SpriteCrop.Rect(x: 33, y: 33, side: 30))
    }

    /// Squaring is the whole reason a taller-than-wide subject does not come out stretched.
    func testExpandsToSquareOnTheLongerEdge() {
        let rect = try? XCTUnwrap(SpriteCrop.squareContentRect(
            width: 100, height: 100, isOpaque: box(x: 40, y: 10, w: 10, h: 40)))
        XCTAssertEqual(rect?.side, 40)
    }

    /// A square must never hang off the canvas, or the crop reads out of bounds.
    func testClampsToCanvasWhenContentSitsOnTheEdge() {
        let rect = try? XCTUnwrap(SpriteCrop.squareContentRect(
            width: 50, height: 50, isOpaque: box(x: 0, y: 45, w: 4, h: 5)))
        guard let rect else { return XCTFail("expected a rect") }
        XCTAssertGreaterThanOrEqual(rect.x, 0)
        XCTAssertGreaterThanOrEqual(rect.y, 0)
        XCTAssertLessThanOrEqual(rect.x + rect.side, 50)
        XCTAssertLessThanOrEqual(rect.y + rect.side, 50)
    }

    /// Fully transparent → nil, so the caller keeps the original image instead of cropping to nothing.
    func testFullyTransparentCanvasHasNoContentRect() {
        XCTAssertNil(SpriteCrop.squareContentRect(width: 32, height: 32, isOpaque: { _, _ in false }))
    }

    func testRejectsAnEmptyCanvas() {
        XCTAssertNil(SpriteCrop.squareContentRect(width: 0, height: 0, isOpaque: { _, _ in true }))
    }

    /// Content filling the canvas is already square — cropping must be a no-op, not a shrink.
    func testFullCanvasIsUnchanged() {
        let rect = SpriteCrop.squareContentRect(
            width: 64, height: 64, isOpaque: { _, _ in true })
        XCTAssertEqual(rect, SpriteCrop.Rect(x: 0, y: 0, side: 64))
    }
}
