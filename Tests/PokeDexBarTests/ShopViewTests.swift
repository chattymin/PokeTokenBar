import XCTest
@testable import PokeDexBar

final class ShopViewTests: XCTestCase {
    /// 확률은 숨기지 않는다 — 표기 문자열을 테스트로 잠근다.
    func testOddsTextListsEveryGrade() {
        let text = ShopTabView.oddsText(.ko)
        XCTAssertTrue(text.contains("커먼 55%"), text)
        XCTAssertTrue(text.contains("레어 15%"), text)
        XCTAssertTrue(text.contains("에픽 25%"), text)
        XCTAssertTrue(text.contains("레전더리 5%"), text)
    }

    /// 표기 확률의 합은 100% 여야 한다 — 밸런스를 고치면 문구도 같이 틀어지는 걸 막는다.
    func testOddsSumToOne() {
        let total = EggBalance.odds.reduce(0) { $0 + $1.probability }
        XCTAssertEqual(total, 1.0, accuracy: 0.0001)
    }
}
