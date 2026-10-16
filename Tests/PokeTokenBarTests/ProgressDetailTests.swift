import XCTest
@testable import PokeTokenBar

/// CompanionHeader.progressDetail — hover 툴팁용 "X / Y · Z%" 순수 헬퍼.
/// CompanionHeader 의 진화/부화 진행 바가 이 헬퍼를 공유하므로, 뷰 대신 헬퍼 자체를 검증한다.
final class ProgressDetailTests: XCTestCase {
    func testNormalProgressFormatsCompactCountsAndFlooredPercent() {
        XCTAssertEqual(CompanionHeader.progressDetail(used: 37_200, total: 50_000), "37.2K / 50K · 74%")
    }

    func testUsedOverTotalIsClampedToTotal() {
        // 100% 미만이어야 할 진행이 반올림 오차로 total 을 넘는 경우 방어 — X 는 Y 를 넘지 않는다.
        XCTAssertEqual(CompanionHeader.progressDetail(used: 60_000, total: 50_000), "50K / 50K · 100%")
    }

    func testZeroTotalDoesNotCrashAndReportsZeroPercent() {
        XCTAssertEqual(CompanionHeader.progressDetail(used: 0, total: 0), "0 / 0 · 0%")
            }

    func testPercentFloorsRatherThanRounds() {
        // 74.999...% 가 75% 로 반올림돼 완료 전에 100%(혹은 한 단계 위)처럼 보이면 안 된다.
        XCTAssertEqual(CompanionHeader.progressDetail(used: 999, total: 1_000), "999 / 1K · 99%")
    }

}
