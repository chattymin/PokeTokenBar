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

    /// 상태 전이는 절대 놓치지 않는다 — 억제가 이걸 삼키면 로그가 거짓말을 한다.
    func testAChangedMessageIsWrittenImmediately() {
        var suppressor = LogRepeatSuppressor()
        _ = suppressor.shouldWrite(key: "codex", message: "not found", now: start, repeatAfter: hour)
        XCTAssertTrue(suppressor.shouldWrite(key: "codex", message: "found: 1.2.3",
                                             now: start.addingTimeInterval(1), repeatAfter: hour))
    }

    /// 같은 상태가 오래 이어져도 주기적으로 한 번은 남긴다 — "언제부터 이랬나"와 "지금도 그런가"를
    /// 구분할 수 있어야 한다. 억제만 하면 로그가 조용한 건지 앱이 죽은 건지 알 수 없다.
    func testTheSameStateIsReaffirmedAfterTheInterval() {
        var suppressor = LogRepeatSuppressor()
        _ = suppressor.shouldWrite(key: "codex", message: "not found", now: start, repeatAfter: hour)
        XCTAssertFalse(suppressor.shouldWrite(key: "codex", message: "not found",
                                              now: start.addingTimeInterval(hour - 1), repeatAfter: hour))
        XCTAssertTrue(suppressor.shouldWrite(key: "codex", message: "not found",
                                             now: start.addingTimeInterval(hour), repeatAfter: hour))
    }

    /// 재확인 후에는 타이머가 다시 시작한다 — 한 번 지나면 계속 통과하면 억제가 무의미해진다.
    func testTheIntervalRestartsAfterAReaffirmation() {
        var suppressor = LogRepeatSuppressor()
        _ = suppressor.shouldWrite(key: "codex", message: "x", now: start, repeatAfter: hour)
        _ = suppressor.shouldWrite(key: "codex", message: "x", now: start.addingTimeInterval(hour), repeatAfter: hour)
        XCTAssertFalse(suppressor.shouldWrite(key: "codex", message: "x",
                                              now: start.addingTimeInterval(hour + 60), repeatAfter: hour))
    }

    /// 키가 다르면 서로의 억제에 영향을 주지 않는다 — 한 프로바이더의 변화가 다른 프로바이더의
    /// 억제를 풀면 잡음이 그대로 돌아온다.
    func testKeysAreIndependent() {
        var suppressor = LogRepeatSuppressor()
        _ = suppressor.shouldWrite(key: "codex", message: "not found", now: start, repeatAfter: hour)
        _ = suppressor.shouldWrite(key: "antigravity", message: "not found", now: start, repeatAfter: hour)

        XCTAssertTrue(suppressor.shouldWrite(key: "codex", message: "found",
                                             now: start.addingTimeInterval(1), repeatAfter: hour))
        XCTAssertFalse(suppressor.shouldWrite(key: "antigravity", message: "not found",
                                              now: start.addingTimeInterval(1), repeatAfter: hour),
                       "다른 키의 전이가 이 키의 억제를 풀었다")
    }
}
