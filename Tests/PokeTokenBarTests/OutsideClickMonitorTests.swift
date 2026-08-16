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
        XCTAssertEqual(removed, [1], "stop must remove the first token, not a replacement that hid the leak")
        XCTAssertNil(monitor.token)
    }

    /// Stop is a no-op when nothing is installed — mirrors popoverDidClose after
    /// a show that never registered, and must not call remove.
    func testStopWhenIdleDoesNotRemove() {
        var monitor = OutsideClickMonitor()
        var removed = 0
        monitor.stop { _ in removed += 1 }
        XCTAssertEqual(removed, 0)
        XCTAssertNil(monitor.token)
    }

    /// After a paired stop, start may register again (open → close → open).
    func testStartAfterStopRegistersAgain() {
        var monitor = OutsideClickMonitor()
        var registers = 0
        monitor.start { registers += 1; return registers }
        monitor.stop { _ in }
        monitor.start { registers += 1; return registers }
        XCTAssertEqual(registers, 2)
        XCTAssertEqual(monitor.token as? Int, 2)
    }

    /// A nil register result is not a token — the next start may try again.
    /// `NSEvent.addGlobalMonitorForEvents` is documented to return Optional.
    func testNilRegisterDoesNotOccupyTheSlot() {
        var monitor = OutsideClickMonitor()
        var attempts = 0
        monitor.start { attempts += 1; return nil as Int? }
        monitor.start { attempts += 1; return 7 }
        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(monitor.token as? Int, 7)
    }
}
