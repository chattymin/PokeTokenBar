import XCTest
@testable import PokeDexBar

/// 스프라이트를 정사각형 칸에 그대로 늘려 그리면 종마다 다른 원본 비율이 찌부된다
/// (Showdown 스프라이트는 45×49 ~ 100×135). 칸 크기는 그대로 두고 안쪽만 비율을 지켜야 한다.
final class PixelFitTests: XCTestCase {
    func testTallSpriteKeepsItsRatio() {
        let rect = PixelScale.fittedRect(source: CGSize(width: 100, height: 135),
                                         in: CGSize(width: 20, height: 20))
        XCTAssertEqual(rect.width / rect.height, 100.0 / 135.0, accuracy: 0.0001,
                       "세로로 긴 스프라이트가 정사각형으로 늘어났다")
        XCTAssertEqual(rect.height, 20, accuracy: 0.0001, "긴 쪽이 칸을 꽉 채워야 한다")
        XCTAssertEqual(rect.midX, 10, accuracy: 0.0001, "남는 폭은 양쪽으로 나눠 중앙 정렬")
    }

    func testWideSpriteKeepsItsRatio() {
        let rect = PixelScale.fittedRect(source: CGSize(width: 120, height: 60),
                                         in: CGSize(width: 20, height: 20))
        XCTAssertEqual(rect.width / rect.height, 2, accuracy: 0.0001)
        XCTAssertEqual(rect.width, 20, accuracy: 0.0001)
        XCTAssertEqual(rect.midY, 10, accuracy: 0.0001)
    }

    /// 어떤 비율이든 칸 밖으로 나가지 않는다 — 메뉴바 캔버스는 22×22 고정이다.
    func testNeverOverflowsTheBounds() {
        let bounds = CGSize(width: 20, height: 20)
        for source in [CGSize(width: 45, height: 49), CGSize(width: 100, height: 135),
                       CGSize(width: 160, height: 40), CGSize(width: 7, height: 7)] {
            let rect = PixelScale.fittedRect(source: source, in: bounds)
            XCTAssertLessThanOrEqual(rect.width, bounds.width + 0.0001, "\(source) 가 폭을 넘었다")
            XCTAssertLessThanOrEqual(rect.height, bounds.height + 0.0001, "\(source) 가 높이를 넘었다")
            XCTAssertGreaterThanOrEqual(rect.minX, -0.0001)
            XCTAssertGreaterThanOrEqual(rect.minY, -0.0001)
        }
    }

    /// 크기를 모르는 이미지(0×0)면 칸 전체를 쓴다 — 나눗셈으로 NaN 을 만들지 않는다.
    func testDegenerateSourceFallsBackToTheWholeBox() {
        let rect = PixelScale.fittedRect(source: .zero, in: CGSize(width: 20, height: 20))
        XCTAssertEqual(rect, CGRect(x: 0, y: 0, width: 20, height: 20))
    }
}
