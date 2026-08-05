import AppKit
import CoreGraphics

/// EPX(Scale2x) — 픽셀아트 전용 2배 확대.
///
/// 이웃 4방향의 색이 서로 같은지만 보고 대각선 계단을 깎는다. 색을 섞지 않으므로(보간 없음)
/// 팔레트와 선명도가 그대로 유지된 채 윤곽만 부드러워진다. Lanczos 같은 일반 보간은
/// 45×49 처럼 작은 원본에서는 뭉갤 디테일이 없어 부드러워지는 만큼 흐려지기만 한다.
enum PixelUpscaler {
    /// 프레임을 2^passes 배로 확대. passes 가 0 이면 원본을 그대로 돌려준다.
    static func epx(_ image: NSImage, passes: Int) -> NSImage {
        guard passes > 0, var bitmap = Bitmap(image) else { return image }
        for _ in 0..<passes { bitmap = bitmap.scaled2x() }
        guard let cg = bitmap.cgImage else { return image }
        return NSImage(cgImage: cg, size: .zero)
    }

    /// RGBA8 프리멀티플라이드 픽셀 버퍼. 픽셀당 UInt32 한 워드로 다뤄 색 비교를 == 로 끝낸다.
    private struct Bitmap {
        let w: Int, h: Int
        var px: [UInt32]

        init?(_ image: NSImage) {
            var rect = CGRect(origin: .zero, size: image.size)
            guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil),
                  cg.width > 0, cg.height > 0 else { return nil }
            w = cg.width
            h = cg.height
            px = [UInt32](repeating: 0, count: w * h)
            let ok = px.withUnsafeMutableBytes { buf -> Bool in
                guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h,
                                          bitsPerComponent: 8, bytesPerRow: w * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                else { return false }
                ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
                return true
            }
            guard ok else { return nil }
        }

        private init(w: Int, h: Int, px: [UInt32]) { self.w = w; self.h = h; self.px = px }

        /// 가장자리 밖은 클램프 — 바깥을 투명으로 두면 윤곽선이 한 겹 깎여 나간다.
        private func at(_ x: Int, _ y: Int) -> UInt32 {
            px[min(max(y, 0), h - 1) * w + min(max(x, 0), w - 1)]
        }

        func scaled2x() -> Bitmap {
            let ow = w * 2, oh = h * 2
            var out = [UInt32](repeating: 0, count: ow * oh)
            for y in 0..<h {
                for x in 0..<w {
                    //     A
                    //   C P B      대각으로 이어지는 두 이웃이 같고 그 반대쪽이 다를 때만
                    //     D        해당 모서리를 이웃 색으로 채운다.
                    let p = at(x, y)
                    let a = at(x, y - 1), b = at(x + 1, y), c = at(x - 1, y), d = at(x, y + 1)
                    out[(y * 2) * ow + x * 2]         = (c == a && c != d && a != b) ? a : p
                    out[(y * 2) * ow + x * 2 + 1]     = (a == b && a != c && b != d) ? b : p
                    out[(y * 2 + 1) * ow + x * 2]     = (d == c && d != b && c != a) ? c : p
                    out[(y * 2 + 1) * ow + x * 2 + 1] = (b == d && b != a && d != c) ? d : p
                }
            }
            return Bitmap(w: ow, h: oh, px: out)
        }

        var cgImage: CGImage? {
            var buffer = px
            return buffer.withUnsafeMutableBytes { buf -> CGImage? in
                CGContext(data: buf.baseAddress, width: w, height: h,
                          bitsPerComponent: 8, bytesPerRow: w * 4,
                          space: CGColorSpaceCreateDeviceRGB(),
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
            }
        }
    }
}
