import XCTest
import AppKit
@testable import PokeTokenBar

// Dex grid scroll paging: wheel notch = one page, trackpad gesture = one page past a threshold,
// momentum tail ignored, result clamped to the page range.
final class DexScrollPagerTests: XCTestCase {

    private let threshold = DexScrollPager.preciseThreshold

    // MARK: pageAfterScroll

    func testNextAndPreviousPage() {
        XCTAssertEqual(DexScrollPager.pageAfterScroll(current: 1, pageCount: 3, step: 1), 2)
        XCTAssertEqual(DexScrollPager.pageAfterScroll(current: 1, pageCount: 3, step: -1), 0)
    }

    func testClampsAtBothEnds() {
        XCTAssertEqual(DexScrollPager.pageAfterScroll(current: 2, pageCount: 3, step: 1), 2)
        XCTAssertEqual(DexScrollPager.pageAfterScroll(current: 0, pageCount: 3, step: -1), 0)
        XCTAssertEqual(DexScrollPager.pageAfterScroll(current: 0, pageCount: 1, step: 1), 0)
    }

    // MARK: Mouse wheel (non-precise)

    func testWheelNotchPagesOncePerEvent() {
        var pager = DexScrollPager()
        // Content moves up (negative delta) -> next page; natural scrolling is already baked in.
        XCTAssertEqual(pager.step(deltaY: -1, precise: false, phase: [], momentumPhase: []), 1)
        XCTAssertEqual(pager.step(deltaY: -1, precise: false, phase: [], momentumPhase: []), 1)
        XCTAssertEqual(pager.step(deltaY: 3, precise: false, phase: [], momentumPhase: []), -1)
        XCTAssertEqual(pager.step(deltaY: 0, precise: false, phase: [], momentumPhase: []), 0)
    }

    // MARK: Trackpad (precise)

    func testTrackpadBelowThresholdIsNoOp() {
        var pager = DexScrollPager()
        let small = threshold / 4
        XCTAssertEqual(pager.step(deltaY: -small, precise: true, phase: .began, momentumPhase: []), 0)
        XCTAssertEqual(pager.step(deltaY: -small, precise: true, phase: .changed, momentumPhase: []), 0)
        XCTAssertEqual(pager.step(deltaY: 0, precise: true, phase: .ended, momentumPhase: []), 0)
        // A new gesture starts from zero, not from the leftover of the previous one.
        XCTAssertEqual(pager.step(deltaY: -small * 2, precise: true, phase: .began, momentumPhase: []), 0)
    }

    func testTrackpadGesturePagesOnceAfterThreshold() {
        var pager = DexScrollPager()
        let chunk = threshold / 2 + 1
        XCTAssertEqual(pager.step(deltaY: -chunk, precise: true, phase: .began, momentumPhase: []), 0)
        XCTAssertEqual(pager.step(deltaY: -chunk, precise: true, phase: .changed, momentumPhase: []), 1)
        // Keeps swiping within the same gesture: still one page only.
        for _ in 0..<5 {
            XCTAssertEqual(pager.step(deltaY: -threshold * 2, precise: true, phase: .changed, momentumPhase: []), 0)
        }
        XCTAssertEqual(pager.step(deltaY: 0, precise: true, phase: .ended, momentumPhase: []), 0)
        // Next gesture in the opposite direction pages back.
        XCTAssertEqual(pager.step(deltaY: threshold, precise: true, phase: .began, momentumPhase: []), -1)
    }

    func testMomentumTailIsIgnored() {
        var pager = DexScrollPager()
        XCTAssertEqual(pager.step(deltaY: -threshold, precise: true, phase: .began, momentumPhase: []), 1)
        XCTAssertEqual(pager.step(deltaY: 0, precise: true, phase: .ended, momentumPhase: []), 0)
        // Momentum arrives after the gesture ended (latch already reset), so only the
        // momentum guard stops these large deltas from paging again.
        XCTAssertEqual(pager.step(deltaY: -threshold * 3, precise: true, phase: [], momentumPhase: .began), 0)
        for _ in 0..<5 {
            XCTAssertEqual(pager.step(deltaY: -threshold * 3, precise: true, phase: [], momentumPhase: .changed), 0)
        }
        XCTAssertEqual(pager.step(deltaY: 0, precise: true, phase: [], momentumPhase: .ended), 0)
    }
}
