import AppKit
import XCTest
@testable import PokeDexBar

/// 투명 여백 잘라내기 — 종마다 캔버스 여백 비율이 달라서, 안 자르면 작은 포켓몬이 같은 칸에서
/// 더 작게 남아 구분이 안 된다(사용자 지적).
final class SpriteTrimTests: XCTestCase {
    /// `canvas` 크기의 투명 이미지 한가운데(또는 지정 위치)에 불투명 사각형 하나를 그린다.
    private func image(canvas: CGSize, content: CGRect) -> NSImage {
        let image = NSImage(size: NSSize(width: canvas.width, height: canvas.height))
        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: image.size).fill()
        NSColor.red.setFill()
        // NSImage 는 아래가 원점, contentRect 는 위가 원점 — 여기서 뒤집어 준다.
        NSRect(x: content.minX, y: canvas.height - content.maxY,
               width: content.width, height: content.height).fill()
        image.unlockFocus()
        return image
    }

    func testFindsTheOpaqueBox() {
        let rect = CGRect(x: 10, y: 6, width: 20, height: 30)
        let found = SpriteTrim.contentRect(of: image(canvas: CGSize(width: 64, height: 64),
                                                     content: rect))
        XCTAssertEqual(found?.minX ?? -1, rect.minX, accuracy: 1)
        XCTAssertEqual(found?.minY ?? -1, rect.minY, accuracy: 1)
        XCTAssertEqual(found?.width ?? -1, rect.width, accuracy: 1.5)
        XCTAssertEqual(found?.height ?? -1, rect.height, accuracy: 1.5)
    }

    /// 여백이 없으면 캔버스 전체가 내용이다 — 그대로 둬야 한다.
    func testFullyOpaqueImageIsNotCropped() {
        let canvas = CGSize(width: 32, height: 32)
        let found = SpriteTrim.contentRect(of: image(canvas: canvas,
                                                     content: CGRect(origin: .zero, size: canvas)))
        XCTAssertEqual(found?.width ?? 0, 32, accuracy: 1)
        XCTAssertEqual(found?.height ?? 0, 32, accuracy: 1)
    }

    /// 전부 투명하면 자를 것이 없다 — nil 이어야 호출부가 원본을 그대로 그린다.
    func testFullyTransparentImageHasNoContent() {
        let empty = NSImage(size: NSSize(width: 16, height: 16))
        empty.lockFocus()
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: 16, height: 16).fill()
        empty.unlockFocus()
        XCTAssertNil(SpriteTrim.contentRect(of: empty))
    }

    /// **핵심**: 여백이 다른 두 캔버스에 같은 크기의 그림이 있으면, 자른 뒤에는 같아야 한다.
    /// 이게 어긋나면 같은 칸에 놓았을 때 하나가 더 작게 보인다.
    func testTwoDifferentCanvasesNormaliseToTheSameContent() {
        let content = CGSize(width: 20, height: 20)
        let tight = image(canvas: CGSize(width: 24, height: 24),
                          content: CGRect(x: 2, y: 2, width: content.width, height: content.height))
        let loose = image(canvas: CGSize(width: 96, height: 96),
                          content: CGRect(x: 38, y: 38, width: content.width, height: content.height))
        let a = SpriteTrim.cropped(tight, to: SpriteTrim.contentRect(of: tight)!)
        let b = SpriteTrim.cropped(loose, to: SpriteTrim.contentRect(of: loose)!)
        XCTAssertEqual(a.size.width, b.size.width, accuracy: 1.5,
                       "여백이 다르면 잘라낸 뒤에도 크기가 달라진다 — 작은 종이 계속 작게 보인다")
        XCTAssertEqual(a.size.height, b.size.height, accuracy: 1.5)
    }

    /// 애니메이션은 프레임 합집합으로 잘라야 한다 — 프레임마다 재면 칸 안에서 들썩인다.
    func testUnionCoversEveryFrame() {
        let canvas = CGSize(width: 64, height: 64)
        let left = image(canvas: canvas, content: CGRect(x: 8, y: 20, width: 10, height: 10))
        let right = image(canvas: canvas, content: CGRect(x: 40, y: 20, width: 10, height: 10))
        guard let union = SpriteTrim.unionContentRect(of: [left, right]) else {
            return XCTFail("합집합을 못 구했다")
        }
        for frame in [left, right] {
            let rect = SpriteTrim.contentRect(of: frame)!
            XCTAssertTrue(union.contains(rect), "합집합이 한 프레임을 잘라낸다 — 팔다리가 잘린다")
        }
        XCTAssertGreaterThan(union.width, 30, "합집합이 두 위치를 모두 감싸야 한다")
    }

    func testUnionOfNothingIsNil() {
        XCTAssertNil(SpriteTrim.unionContentRect(of: []))
    }

    /// 자르기가 실패해도 스프라이트가 사라지면 안 된다 — 원본을 그대로 돌려준다.
    func testCroppingOutsideTheImageFallsBackToTheOriginal() {
        let source = image(canvas: CGSize(width: 20, height: 20),
                           content: CGRect(x: 4, y: 4, width: 8, height: 8))
        let out = SpriteTrim.cropped(source, to: CGRect(x: 500, y: 500, width: 10, height: 10))
        XCTAssertEqual(out.size.width, source.size.width, accuracy: 0.5)
    }
}

/// 설정 — 칸 채우기는 **박스에만** 있는 개념이다. 크기가 같은 칸이 나란히 놓이는 자리가
/// 박스뿐이라 문제도 거기서만 생기고, 다른 화면은 원래 캔버스가 주는 실제 크기 차이를 남긴다.
@MainActor
final class FillBoxSlotsSettingTests: XCTestCase {
    private func makeStore() -> (UsageStore, UserDefaults) {
        let defaults = UserDefaults(suiteName: "fill-\(UUID().uuidString)")!
        return (UsageStore(defaults: defaults), defaults)
    }

    /// 기본은 켬 — 안 켜면 박스에서 작은 포켓몬이 칸에서 작게 남아 구분이 안 된다.
    func testDefaultsToOn() {
        XCTAssertTrue(makeStore().0.fillBoxSlots)
    }

    func testPersistsAcrossLaunches() {
        let (store, defaults) = makeStore()
        store.fillBoxSlots = false
        XCTAssertFalse(UsageStore(defaults: defaults).fillBoxSlots, "설정이 저장되지 않는다")
    }

    /// 껐을 때 원본이 그대로 나와야 한다 — 잘라낸 결과가 아니라.
    func testTurningItOffKeepsTheOriginalCanvas() {
        let canvas = NSSize(width: 64, height: 64)
        let image = NSImage(size: canvas)
        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: canvas).fill()
        NSColor.blue.setFill()
        NSRect(x: 26, y: 26, width: 12, height: 12).fill()
        image.unlockFocus()

        let rect = SpriteTrim.contentRect(of: image)!
        XCTAssertLessThan(rect.width, canvas.width, "잘라낼 여백이 있어야 이 테스트가 의미 있다")
        XCTAssertEqual(SpriteTrim.cropped(image, to: rect).size.width, rect.width, accuracy: 1.5)
        // 설정을 끄면 호출부가 `cropped` 를 아예 부르지 않는다 — 원본 크기가 유지된다.
        XCTAssertEqual(image.size.width, canvas.width)
    }
}

/// 박스 밖에서는 자르지 않는다 — `SpriteView` 기본값이 곧 그 규칙이다.
final class SpriteFillDefaultTests: XCTestCase {
    @MainActor
    func testSpritesDoNotFillTheirFrameByDefault() {
        XCTAssertFalse(SpriteView(speciesID: 1).fillFrame,
                       "기본이 켜져 있으면 도감·홈·플로팅 펫까지 잘려 실제 크기 차이가 사라진다")
    }

    @MainActor
    func testTheBoxOptsIn() {
        XCTAssertTrue(SpriteView(speciesID: 1, fillFrame: true).fillFrame)
    }
}
