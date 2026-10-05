import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

/// #379: the Pokédex pager chevrons only accepted clicks on the ~7×12pt glyph itself.
@MainActor
final class DexPageButtonHitAreaTests: XCTestCase {
    func testClickOutsideGlyphButInsideHitAreaPages() throws {
        let side = DexPageButton.hitSize
        // Corner-adjacent point: well outside the chevron glyph, inside the 28pt target.
        let taps = try clickCount(at: CGPoint(x: 3, y: 3), side: side)
        XCTAssertEqual(taps, 1)
    }

    func testHitAreaMeetsPointerTargetMinimum() {
        XCTAssertGreaterThanOrEqual(DexPageButton.hitSize, 24)
    }

    private func clickCount(at point: CGPoint, side: CGFloat) throws -> Int {
        var taps = 0
        let host = NSHostingView(rootView: DexPageButton(forward: true, label: "next") { taps += 1 }
            .font(.system(size: 13, weight: .semibold))
            .frame(width: side, height: side))
        host.frame = NSRect(x: 0, y: 0, width: side, height: side)
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: side, height: side),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
                pressure: type == .leftMouseDown ? 1 : 0))
            window.sendEvent(event)
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        return taps
    }
}
