import XCTest
@testable import PokeDexBar

final class PixelScaleTests: XCTestCase {
    /// 이상부활: 45×49 를 96pt 박스에 Retina 로. 192px/49px = 3.9 → 3배로 스냅.
    func testSnapsDownToIntegerMultiple() {
        let r = PixelScale.fit(source: CGSize(width: 45, height: 49),
                               in: CGSize(width: 96, height: 96), displayScale: 2)
        XCTAssertTrue(r.pixelated)
        XCTAssertEqual(r.size.width, 45 * 3 / 2, accuracy: 0.001)
        XCTAssertEqual(r.size.height, 49 * 3 / 2, accuracy: 0.001)
    }

    /// 스냅 결과는 항상 박스 안에 들어가야 한다(넘치면 창 밖으로 잘림).
    func testResultFitsWithinBounds() {
        for (w, h) in [(45.0, 49.0), (74.0, 135.0), (104.0, 88.0), (92.0, 105.0)] {
            for size in [48.0, 96.0, 137.0, 256.0] {
                let r = PixelScale.fit(source: CGSize(width: w, height: h),
                                       in: CGSize(width: size, height: size), displayScale: 2)
                XCTAssertLessThanOrEqual(r.size.width, size + 0.001)
                XCTAssertLessThanOrEqual(r.size.height, size + 0.001)
            }
        }
    }

    /// 정수배 스냅의 핵심 — 화면 픽셀 크기가 소스 픽셀의 정수배여야 계단 폭이 균일하다.
    func testDeviceSizeIsWholeMultipleOfSource() {
        let scale: CGFloat = 2
        let r = PixelScale.fit(source: CGSize(width: 62, height: 85),
                               in: CGSize(width: 200, height: 200), displayScale: scale)
        let ratio = r.size.height * scale / 85
        XCTAssertEqual(ratio, ratio.rounded(), accuracy: 0.001)
    }

    /// 논-Retina 에서도 같은 규칙이 성립.
    func testNonRetinaScale() {
        let r = PixelScale.fit(source: CGSize(width: 45, height: 49),
                               in: CGSize(width: 96, height: 96), displayScale: 1)
        XCTAssertTrue(r.pixelated)
        XCTAssertEqual(r.size.height, 49, accuracy: 0.001)   // 96/49 = 1.9 → 1배
    }

    /// 트로피우스 203×79 를 96pt 에 — 축소라 정수배가 불가능하므로 부드러운 보간.
    func testDownscaleFallsBackToSmooth() {
        let r = PixelScale.fit(source: CGSize(width: 203, height: 79),
                               in: CGSize(width: 96, height: 96), displayScale: 1)
        XCTAssertFalse(r.pixelated)
        XCTAssertEqual(r.size.width, 96, accuracy: 0.001)
        XCTAssertEqual(r.size.width / r.size.height, 203 / 79, accuracy: 0.001)
    }

    /// 크기 0 이미지(디코드 실패 등)에 나눗셈 0 이 새지 않아야 한다.
    func testDegenerateInputsAreSafe() {
        let box = CGSize(width: 96, height: 96)
        XCTAssertEqual(PixelScale.fit(source: .zero, in: box, displayScale: 2).size, box)
        XCTAssertEqual(PixelScale.fit(source: box, in: .zero, displayScale: 2).size, .zero)
        XCTAssertEqual(PixelScale.fit(source: box, in: box, displayScale: 0).size, box)
    }
}
