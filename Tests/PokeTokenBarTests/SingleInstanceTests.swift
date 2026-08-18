import XCTest

@testable import PokeTokenBar

/// 중복 인스턴스 가드 — "나중에 뜬 쪽이 물러난다".
///
/// 실제 트리거(로그인 에이전트 등록이 두 번째 프로세스를 띄우는 것)는 launchd 가 관여해 단위 테스트로
/// 재현할 수 없다. 그래서 두 층을 나눠 잠근다 — 어느 쪽이 물러나는가(순수 판정)와, 그 판정의 입력인
/// 시작 시각을 실제로 읽어낼 수 있는가. 첫 구현이 무효였던 원인이 판정이 아니라 **입력** 이었기 때문에
/// 뒤쪽이 특히 중요하다.
final class SingleInstanceTests: XCTestCase {
    private let mine = Date(timeIntervalSince1970: 2_000)
    private var earlier: Date { mine.addingTimeInterval(-60) }
    private var later: Date { mine.addingTimeInterval(60) }

    // MARK: 판정 — 어느 쪽이 물러나는가

    /// 결함 자체: 로그인 에이전트가 띄운 두 번째 인스턴스는 먼저 떠 있던 쪽에 자리를 넘긴다.
    func testYieldsWhenAnotherInstanceStartedEarlier() {
        XCTAssertTrue(SingleInstance.shouldYield(myStartTime: mine, otherStartTimes: [earlier]))
    }

    /// 반대 브랜치 — 먼저 뜬 쪽은 남는다. 양쪽이 다 물러나면 앱이 통째로 사라진다.
    func testStaysWhenEveryOtherInstanceStartedLater() {
        XCTAssertFalse(SingleInstance.shouldYield(myStartTime: mine, otherStartTimes: [later]))
    }

    func testStaysWhenNoOtherInstanceIsRunning() {
        XCTAssertFalse(SingleInstance.shouldYield(myStartTime: mine, otherStartTimes: []))
    }

    /// 시작 시각을 못 읽었을 땐 남는다 — 잘못 물러나 유일한 인스턴스를 잃는 쪽이 더 나쁘다.
    /// (커널 조회가 실패해야 닿는 경로다. 첫 구현에선 이게 launchd 인스턴스의 **정상** 입력이라
    /// 가드가 무효였다 — `testProcessStartTimeIsReadable…` 이 그 회귀를 잠근다.)
    func testStaysWhenOwnStartTimeIsUnavailable() {
        XCTAssertFalse(SingleInstance.shouldYield(myStartTime: nil, otherStartTimes: [earlier]))
    }

    func testIgnoresOtherInstancesWithUnavailableStartTime() {
        XCTAssertFalse(SingleInstance.shouldYield(myStartTime: mine, otherStartTimes: [nil]))
    }

    /// 시각을 아는 인스턴스가 섞여 있으면 그것만 보고 판정한다.
    func testYieldsOnAnEarlierInstanceEvenWhenAnotherStartTimeIsUnavailable() {
        XCTAssertTrue(SingleInstance.shouldYield(myStartTime: mine, otherStartTimes: [nil, earlier]))
    }

    /// 동시에 시작한 것으로 보이면 남는다 — 서로를 보고 함께 사라지지 않게.
    func testStaysWhenStartTimesTie() {
        XCTAssertFalse(SingleInstance.shouldYield(myStartTime: mine, otherStartTimes: [mine]))
    }

    /// 여러 인스턴스 중 하나만 먼저여도 물러난다.
    func testYieldsWhenOnlyOneOfSeveralStartedEarlier() {
        XCTAssertTrue(
            SingleInstance.shouldYield(myStartTime: mine, otherStartTimes: [later, earlier, later]))
    }

    // MARK: 입력 — 시작 시각을 실제로 읽어내는가

    /// 회귀 가드(핵심). 첫 구현은 `NSRunningApplication.launchDate` 로 판정했는데, 그 값은 launchd 가
    /// 직접 exec 한 프로세스에서 nil 이라 정작 물러나야 할 인스턴스가 판정에서 빠져나가 가드가 통째로
    /// 무효였다. 커널 `p_starttime` 은 실행 경로와 무관하게 값을 준다 — 그 성질을 잠근다.
    func testProcessStartTimeIsReadableForTheCurrentProcess() {
        let start = SingleInstance.processStartTime(getpid())
        XCTAssertNotNil(start, "현재 프로세스의 시작 시각을 읽지 못하면 가드는 아무것도 막지 못한다")
    }

    /// 읽어낸 값이 비교에 쓸 만한가 — 과거이고, 이 프로세스가 방금 뜬 것과 어긋나지 않는다.
    func testProcessStartTimeIsPlausible() {
        guard let start = SingleInstance.processStartTime(getpid()) else {
            return XCTFail("시작 시각을 읽지 못했다")
        }
        XCTAssertLessThanOrEqual(start, Date())
        XCTAssertGreaterThan(start, Date().addingTimeInterval(-86_400))
    }

    /// 존재하지 않는 pid 는 nil — 종료된 인스턴스를 "먼저 떴다"로 오판하지 않는다.
    func testProcessStartTimeIsNilForAnUnknownProcess() {
        XCTAssertNil(SingleInstance.processStartTime(pid_t(Int32.max)))
    }
}
