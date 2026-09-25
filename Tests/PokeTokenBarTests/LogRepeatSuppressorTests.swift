import XCTest
@testable import PokeTokenBar

final class LogRepeatSuppressorTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)
    private let hour: TimeInterval = 3600

    func testFirstObservationIsAlwaysWritten() {
        var suppressor = LogRepeatSuppressor()
        XCTAssertTrue(suppressor.shouldWrite(key: "codex", message: "not found",
                                             now: start, repeatAfter: hour))
    }

    func testIdenticalRepeatIsSuppressed() {
        var suppressor = LogRepeatSuppressor()
        _ = suppressor.shouldWrite(key: "codex", message: "not found", now: start, repeatAfter: hour)
        XCTAssertFalse(suppressor.shouldWrite(key: "codex", message: "not found",
                                              now: start.addingTimeInterval(120), repeatAfter: hour))
    }

    /// A state change is never lost: if suppression swallowed it, the log would lie.
    func testAChangedMessageIsWrittenImmediately() {
        var suppressor = LogRepeatSuppressor()
        _ = suppressor.shouldWrite(key: "codex", message: "not found", now: start, repeatAfter: hour)
        XCTAssertTrue(suppressor.shouldWrite(key: "codex", message: "found: 1.2.3",
                                             now: start.addingTimeInterval(1), repeatAfter: hour))
    }

    /// An unchanged state is still written once per interval, so the log can tell "since when" from
    /// "still true now" — and a quiet log from a dead app.
    func testTheSameStateIsReaffirmedAfterTheInterval() {
        var suppressor = LogRepeatSuppressor()
        _ = suppressor.shouldWrite(key: "codex", message: "not found", now: start, repeatAfter: hour)
        XCTAssertFalse(suppressor.shouldWrite(key: "codex", message: "not found",
                                              now: start.addingTimeInterval(hour - 1), repeatAfter: hour))
        XCTAssertTrue(suppressor.shouldWrite(key: "codex", message: "not found",
                                             now: start.addingTimeInterval(hour), repeatAfter: hour))
    }

    /// The interval restarts after a reaffirmation; otherwise, once passed, every repeat would pass.
    func testTheIntervalRestartsAfterAReaffirmation() {
        var suppressor = LogRepeatSuppressor()
        _ = suppressor.shouldWrite(key: "codex", message: "x", now: start, repeatAfter: hour)
        _ = suppressor.shouldWrite(key: "codex", message: "x", now: start.addingTimeInterval(hour), repeatAfter: hour)
        XCTAssertFalse(suppressor.shouldWrite(key: "codex", message: "x",
                                              now: start.addingTimeInterval(hour + 60), repeatAfter: hour))
    }

    /// Keys are independent: one provider's change must not lift another provider's suppression.
    func testKeysAreIndependent() {
        var suppressor = LogRepeatSuppressor()
        _ = suppressor.shouldWrite(key: "codex", message: "not found", now: start, repeatAfter: hour)
        _ = suppressor.shouldWrite(key: "antigravity", message: "not found", now: start, repeatAfter: hour)

        XCTAssertTrue(suppressor.shouldWrite(key: "codex", message: "found",
                                             now: start.addingTimeInterval(1), repeatAfter: hour))
        XCTAssertFalse(suppressor.shouldWrite(key: "antigravity", message: "not found",
                                              now: start.addingTimeInterval(1), repeatAfter: hour),
                       "another key's change lifted this key's suppression")
    }
}
