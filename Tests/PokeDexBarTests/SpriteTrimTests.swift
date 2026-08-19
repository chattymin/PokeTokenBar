import AppKit
import XCTest
@testable import PokeDexBar

/// [회귀] **매달린 포인터로 그리던 버그.**
///
/// `CGContext(data: &pixels, ...)` 로 만든 뒤 호출이 끝나고 `ctx.draw(...)` 를 하면, Swift 의
/// `&배열` 이 준 임시 포인터가 이미 무효라 해제·이동된 메모리에 그림을 그린다. 대개 "동작"하다가
/// 할당자 상태에 따라 힙을 망가뜨리고, **터지는 것은 `malloc` 이 다음에 그 영역을 만질 때**다.
///
/// 실제 제보: "박스를 보다 특정 개체 상세를 열면 죽는다" + **SIGABRT**. 상세 화면은 이 코드를
/// 안 타지만(`fillFrame` 이 꺼져 있다) 그 직전의 박스 그리드가 칸마다 이 함수를 부른다 —
/// 원인과 증상이 화면 하나만큼 떨어져 있었다.
final class SpriteTrimTests: XCTestCase {
    /// 가운데에만 불투명한 사각형이 있는 이미지를 만든다.
    private func image(size: Int, opaque: NSRect) -> NSImage {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: size * 4, bitsPerPixel: 32)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: size, height: size).fill()
        NSColor.red.setFill()
        opaque.fill()
        NSGraphicsContext.restoreGraphicsState()
        let made = NSImage(size: NSSize(width: size, height: size))
        made.addRepresentation(rep)
        return made
    }

    /// **알파 경계를 실제로 찾는다** — 다시 쓰면서 로직이 깨지지 않았는지.
    func testItFindsTheOpaqueBounds() throws {
        let made = image(size: 40, opaque: NSRect(x: 10, y: 10, width: 20, height: 20))
        let rect = try XCTUnwrap(SpriteTrim.contentRect(of: made))
        XCTAssertEqual(rect.width, 20, accuracy: 1.5)
        XCTAssertEqual(rect.height, 20, accuracy: 1.5)
        XCTAssertEqual(rect.minX, 10, accuracy: 1.5)
    }

    /// 전부 투명하면 nil — 자를 것이 없다.
    func testAFullyTransparentImageHasNoContent() {
        let made = image(size: 20, opaque: .zero)
        XCTAssertNil(SpriteTrim.contentRect(of: made))
    }

    /// **여러 번 불러도 값이 같고 안 죽는다.** 매달린 포인터 시절에는 여기가 할당자 상태에
    /// 따라 흔들렸다 — 박스 한 페이지가 30번을 연달아 부른다.
    func testRepeatedCallsAreStable() throws {
        let made = image(size: 48, opaque: NSRect(x: 6, y: 8, width: 30, height: 24))
        let first = try XCTUnwrap(SpriteTrim.contentRect(of: made))
        for _ in 0..<200 {
            let again = try XCTUnwrap(SpriteTrim.contentRect(of: made))
            XCTAssertEqual(again, first)
        }
    }

    /// 여러 프레임의 합집합 — 애니메이션이 칸 안에서 들썩이지 않게 하는 값.
    func testUnionCoversEveryFrame() throws {
        let left = image(size: 40, opaque: NSRect(x: 4, y: 10, width: 10, height: 10))
        let right = image(size: 40, opaque: NSRect(x: 26, y: 10, width: 10, height: 10))
        let union = try XCTUnwrap(SpriteTrim.unionContentRect(of: [left, right]))
        XCTAssertLessThanOrEqual(union.minX, 5)
        XCTAssertGreaterThanOrEqual(union.maxX, 35)
    }

    /// **소스 스캔 — 같은 부류가 다시 안 들어오게.** `&배열` 을 C API 에 넘기고 그 뒤에
    /// 쓰는 형태는 눈으로는 멀쩡해 보이고 대개 동작하기까지 한다.
    func testNoOneBuildsAContextFromAnInoutArray() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/PokeDexBar")
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)!
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        XCTAssertGreaterThan(files.count, 30, "소스를 못 읽었다 — 이 테스트가 아무것도 안 지킨다")

        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for line in text.split(separator: "\n") where !line.contains("///") {
                XCTAssertFalse(line.contains("CGContext(data: &"),
                               "\(file.lastPathComponent): 임시 포인터로 컨텍스트를 만든다 — "
                               + "호출이 끝나면 매달린 포인터가 된다")
            }
        }
    }
}
