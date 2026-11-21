import AppKit
import XCTest
@testable import PokeTokenBar

@MainActor
final class MenuBarCenteringTests: XCTestCase {
    private static let canvas = NSSize(width: 24, height: 22)

    private func frame(block: NSRect) -> NSImage {
        let image = NSImage(size: Self.canvas)
        image.lockFocus()
        NSColor.black.setFill()
        block.fill()
        image.unlockFocus()
        return image
    }

    private func bounds(of frames: [(image: NSImage, delay: TimeInterval)]) -> (boxes: [CGRect], size: CGSize) {
        let bitmaps = frames.compactMap { AppDelegate.cgFrame(from: $0.image) }
        XCTAssertEqual(bitmaps.count, frames.count)
        let boxes = bitmaps.compactMap { AppDelegate.visibleBounds(of: $0) }
        XCTAssertEqual(boxes.count, frames.count)
        return (boxes, CGSize(width: bitmaps[0].width, height: bitmaps[0].height))
    }

    func testImageIsCenteredOnlyWhenThereIsNoText() {
        let button = NSStatusBarButton(frame: NSRect(x: 0, y: 0, width: 120, height: 22))
        AppDelegate.applyMenuText([], to: button, colors: [])
        XCTAssertEqual(button.imagePosition, .imageOnly)
        AppDelegate.applyMenuText(["1.2M"], to: button, colors: [])
        XCTAssertEqual(button.imagePosition, .imageLeading)
        AppDelegate.applyMenuText(["1.2M", "Claude 40%"], to: button, colors: [])
        XCTAssertEqual(button.imagePosition, .imageLeading)
        AppDelegate.applyMenuText([""], to: button, colors: [])
        XCTAssertEqual(button.imagePosition, .imageOnly)
    }

    func testVisibleArtMovesToTheMiddleOfTheCanvas() {
        let frames = [(image: frame(block: NSRect(x: 2, y: 0, width: 8, height: 6)), delay: 0.5)]
        let result = bounds(of: AppDelegate.centeredOnArt(frames))
        XCTAssertEqual(result.boxes[0].midX, result.size.width / 2, accuracy: 1)
        XCTAssertEqual(result.boxes[0].midY, result.size.height / 2, accuracy: 1)
    }

    func testFramesShareOneOffsetSoTheAnimationDoesNotShake() {
        let low = frame(block: NSRect(x: 4, y: 0, width: 8, height: 6))
        let lifted = frame(block: NSRect(x: 4, y: 2, width: 8, height: 6))
        let before = bounds(of: [(low, 0.5), (lifted, 0.5)])
        let after = bounds(of: AppDelegate.centeredOnArt([(low, 0.5), (lifted, 0.5)]))
        XCTAssertEqual(after.boxes[0].minY - after.boxes[1].minY,
                       before.boxes[0].minY - before.boxes[1].minY, accuracy: 0.001)
        let art = after.boxes[0].union(after.boxes[1])
        XCTAssertEqual(art.midY, after.size.height / 2, accuracy: 1)
    }

    func testFullyTransparentFramesAreLeftAlone() {
        let empty = NSImage(size: Self.canvas)
        empty.lockFocus()
        empty.unlockFocus()
        let result = AppDelegate.centeredOnArt([(empty, 0.5)])
        XCTAssertTrue(result[0].image === empty)
    }
}
