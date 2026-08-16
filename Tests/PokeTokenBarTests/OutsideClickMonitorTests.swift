import XCTest
@testable import PokeTokenBar

/// #168: the popover's global mouse monitor must not drop a live token.
/// `start` overwriting `outsideClickMonitor` without `removeMonitor` leaks a
/// process-lifetime observer — silent, no crash. These tests inject register/remove
/// so the leak is visible without installing a real `NSEvent` monitor.
final class OutsideClickMonitorTests: XCTestCase {

    /// Second start must not call register again and must keep the first token.
    /// The production bug: assignment replaces the token, `removeMonitor` never
    /// sees the first one, and a second observer stays installed.
    func testStartTwiceKeepsFirstTokenAndDoesNotRegisterAgain() {
        var monitor = OutsideClickMonitor()
        var registers = 0
        var removed: [Int] = []
        monitor.start { registers += 1; return registers }
        monitor.start { registers += 1; return registers }
        XCTAssertEqual(registers, 1, "second start must be a no-op, not a new observer")
        monitor.stop { removed.append($0 as! Int) }
        XCTAssertEqual(removed, [1], "stop must remove the first token, not a replacement")
    }

    func testStopWhenIdleDoesNotRemove() {
        var monitor = OutsideClickMonitor()
        var removed = 0
        monitor.stop { _ in removed += 1 }
        XCTAssertEqual(removed, 0)
    }

    func testStartAfterStopRegistersAgain() {
        var monitor = OutsideClickMonitor()
        var registers = 0
        monitor.start { registers += 1; return registers }
        monitor.stop { _ in }
        monitor.start { registers += 1; return registers }
        XCTAssertEqual(registers, 2)
    }

    /// `addGlobalMonitorForEvents` returns `Optional`; a nil result must not block the next start.
    func testNilRegisterDoesNotOccupyTheSlot() {
        var monitor = OutsideClickMonitor()
        var registers = 0
        monitor.start { registers += 1; return nil }
        monitor.start { registers += 1; return 1 }
        XCTAssertEqual(registers, 2)
        var removed: [Int] = []
        monitor.stop { removed.append($0 as! Int) }
        XCTAssertEqual(removed, [1])
    }
}
