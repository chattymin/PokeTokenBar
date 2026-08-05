import XCTest
import AppKit
@testable import PokeDexBar

final class PixelUpscalerTests: XCTestCase {
    // MARK: - 픽셀 입출력 헬퍼

    private func makeImage(w: Int, h: Int, rgba: [UInt8]) -> NSImage {
        var data = rgba
        let cg: CGImage = data.withUnsafeMutableBytes { buf in
            let ctx = CGContext(data: buf.baseAddress, width: w, height: h,
                                bitsPerComponent: 8, bytesPerRow: w * 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            return ctx.makeImage()!
        }
        return NSImage(cgImage: cg, size: .zero)
    }

    private func pixels(of image: NSImage) -> (w: Int, h: Int, rgba: [UInt8]) {
        var rect = CGRect(origin: .zero, size: image.size)
        let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil)!
        let w = cg.width, h = cg.height
        var out = [UInt8](repeating: 0, count: w * h * 4)
        out.withUnsafeMutableBytes { buf in
            let ctx = CGContext(data: buf.baseAddress, width: w, height: h,
                                bitsPerComponent: 8, bytesPerRow: w * 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return (w, h, out)
    }

    /// 4×4 대각선 — 왼쪽 아래 삼각형만 채운 2색 패턴.
    private func diagonal() -> NSImage {
        let fg: [UInt8] = [200, 40, 60, 255], bg: [UInt8] = [0, 0, 0, 0]
        var px: [UInt8] = []
        for y in 0..<4 { for x in 0..<4 { px += (x <= y) ? fg : bg } }
        return makeImage(w: 4, h: 4, rgba: px)
    }

    private func colorSet(_ p: (w: Int, h: Int, rgba: [UInt8])) -> Set<[UInt8]> {
        Set(stride(from: 0, to: p.rgba.count, by: 4).map { Array(p.rgba[$0..<$0 + 4]) })
    }

    // MARK: - EPX

    func testPassesDoubleEachTime() {
        let src = diagonal()
        XCTAssertEqual(pixels(of: PixelUpscaler.epx(src, passes: 1)).w, 8)
        XCTAssertEqual(pixels(of: PixelUpscaler.epx(src, passes: 2)).h, 16)
    }

    func testZeroPassesIsIdentity() {
        let p = pixels(of: PixelUpscaler.epx(diagonal(), passes: 0))
        XCTAssertEqual(p.w, 4)
        XCTAssertEqual(p.h, 4)
    }

    /// EPX 의 핵심 성질 — 색을 섞지 않는다. 새 색이 생기면 그건 보간이지 EPX 가 아니다.
    func testIntroducesNoNewColors() {
        let src = diagonal()
        let before = colorSet(pixels(of: src))
        let after = colorSet(pixels(of: PixelUpscaler.epx(src, passes: 2)))
        XCTAssertTrue(after.isSubset(of: before), "EPX 가 원본에 없던 색을 만들어냈다: \(after.subtracting(before))")
    }

    /// 단색 이미지는 확대해도 단색 — 가장자리 클램프가 윤곽을 깎지 않는지 확인.
    func testSolidImageStaysSolid() {
        let solid = makeImage(w: 4, h: 4, rgba: Array(repeating: [90, 160, 110, 255], count: 16).flatMap { $0 })
        XCTAssertEqual(colorSet(pixels(of: PixelUpscaler.epx(solid, passes: 2))).count, 1)
    }

    /// 계단이 실제로 깎여야 한다 — 단순 픽셀 복제(최근접)와 결과가 달라야 의미가 있다.
    func testDiagonalDiffersFromPlainDuplication() {
        let src = pixels(of: diagonal())
        let out = pixels(of: PixelUpscaler.epx(diagonal(), passes: 1))
        var duplicated = false
        for y in 0..<out.h where !duplicated {
            for x in 0..<out.w {
                let o = (y * out.w + x) * 4, s = ((y / 2) * src.w + x / 2) * 4
                if Array(out.rgba[o..<o + 4]) != Array(src.rgba[s..<s + 4]) { duplicated = true; break }
            }
        }
        XCTAssertTrue(duplicated, "EPX 결과가 최근접 이웃 복제와 동일 — 계단이 전혀 깎이지 않았다")
    }

    // MARK: - 확대 단계 선택

    func testPassCountFollowsAvailableFactor() {
        let src = CGSize(width: 45, height: 49)
        // 96pt @2x → 192/49 = 3.9배 → 2배 한 번
        XCTAssertEqual(PixelScale.epxPasses(source: src, in: CGSize(width: 96, height: 96),
                                            displayScale: 2), 1)
        // 48pt @2x → 96/49 = 1.9배 → 2배도 안 되므로 확대 없음
        XCTAssertEqual(PixelScale.epxPasses(source: src, in: CGSize(width: 48, height: 48),
                                            displayScale: 2), 0)
        // 256pt @2x → 10.4배 → 상한 2회
        XCTAssertEqual(PixelScale.epxPasses(source: src, in: CGSize(width: 256, height: 256),
                                            displayScale: 2), 2)
    }

    func testPassCountNeverOverflowsBounds() {
        let src = CGSize(width: 45, height: 49)
        for size in stride(from: 48.0, through: 256.0, by: 8) {
            let box = CGSize(width: size, height: size)
            let n = CGFloat(1 << PixelScale.epxPasses(source: src, in: box, displayScale: 2))
            XCTAssertLessThanOrEqual(src.height * n, size * 2 + 0.001,
                                     "petSize \(size) 에서 EPX 결과가 박스를 넘는다")
        }
    }

    // MARK: - AA 켠 상태의 배치

    /// AA 를 켜면 박스를 채운다 — 정수배 스냅까지 겹쳐 걸어 펫이 작아지면 안 된다.
    func testAntialiasedFitFillsBoxAndNeverShrinks() {
        let box = CGSize(width: 96, height: 96)
        // EPX 1회를 거친 90×98 이 들어온다고 가정
        let aa = PixelScale.fit(source: CGSize(width: 90, height: 98), in: box,
                                displayScale: 2, antialiased: true)
        let snapped = PixelScale.fit(source: CGSize(width: 45, height: 49), in: box,
                                     displayScale: 2)
        XCTAssertEqual(aa.size.height, 96, accuracy: 0.001)
        XCTAssertGreaterThan(aa.size.height, snapped.size.height)
        XCTAssertFalse(aa.pixelated)   // 1.96배 — 정수가 아니므로 나머지는 보간
    }

    /// 나머지 배율이 마침 정수로 떨어지면 보간 없이 최근접 이웃이 더 선명하다.
    func testAntialiasedFitUsesNearestOnExactMultiple() {
        let r = PixelScale.fit(source: CGSize(width: 48, height: 48),
                               in: CGSize(width: 48, height: 48), displayScale: 2,
                               antialiased: true)
        XCTAssertTrue(r.pixelated)
    }
}
