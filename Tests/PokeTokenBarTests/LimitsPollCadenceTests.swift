import XCTest
@testable import PokeTokenBar

final class LimitsPollCadenceTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    /// 첫 조회는 무조건 통과 — 막으면 기동 직후 한도 섹션이 비어 보인다.
    func testFirstAttemptAlwaysPasses() {
        XCTAssertTrue(LimitsPollCadence.shouldFetch(lastAttemptAt: nil, now: now))
    }

    func testWithinTheWindowIsBlocked() {
        let lastAttempt = now.addingTimeInterval(-120)   // 사용량 스캔 2분 주기
        XCTAssertFalse(LimitsPollCadence.shouldFetch(lastAttemptAt: lastAttempt, now: now))
    }

    func testAfterTheWindowPasses() {
        let lastAttempt = now.addingTimeInterval(-LimitsPollCadence.minimumInterval - 1)
        XCTAssertTrue(LimitsPollCadence.shouldFetch(lastAttemptAt: lastAttempt, now: now))
    }

    /// 경계는 통과다(>=). 정확히 간격만큼 지났는데 막으면 5분 주기 사용자가 매번 한 틱씩 밀린다.
    func testTheBoundaryItselfPasses() {
        let lastAttempt = now.addingTimeInterval(-LimitsPollCadence.minimumInterval)
        XCTAssertTrue(LimitsPollCadence.shouldFetch(lastAttemptAt: lastAttempt, now: now))
    }

    /// 시계가 뒤로 갔을 때(수동 변경·NTP 보정) 음수 경과로 영원히 막히지 않는지.
    /// 막히면 한도가 조용히 정지하고 사용자는 원인을 알 수 없다.
    func testAFutureLastAttemptDoesNotWedgeThePoll() {
        let lastAttempt = now.addingTimeInterval(3600)
        XCTAssertFalse(LimitsPollCadence.shouldFetch(lastAttemptAt: lastAttempt, now: now),
                       "지금은 막히는 게 맞다 — 다만 시계가 정상화되면 자동으로 풀려야 한다")
        let recovered = now.addingTimeInterval(3600 + LimitsPollCadence.minimumInterval)
        XCTAssertTrue(LimitsPollCadence.shouldFetch(lastAttemptAt: lastAttempt, now: recovered))
    }
}
