import AppKit

/// 스프라이트의 투명 여백 잘라내기.
///
/// Showdown 스프라이트는 종마다 캔버스가 다르고(45×49 ~ 100×135) 그 안에서 실제 그림이
/// 차지하는 비율도 제각각이다. 그대로 `scaledToFit` 하면 **여백까지 같이 축소돼** 디그다는
/// 칸 안에서 작게 남고 레쿠자는 꽉 찬다 — 같은 크기의 칸에 놓았는데 서로 구분이 안 된다.
/// 본가 박스/도감은 크기와 무관하게 각자 칸을 채우므로, 그리기 전에 알파 경계로 잘라낸다.
///
/// **애니메이션은 프레임마다 따로 자르면 안 된다.** 팔다리가 움직이면 경계가 바뀌어 스프라이트가
/// 칸 안에서 들썩인다. 모든 프레임의 경계를 합집합으로 구해 같은 사각형으로 잘라야 제자리에 선다.
enum SpriteTrim {
    /// 알파가 있는 부분을 감싸는 최소 사각형. **이미지 자신의 좌표계(포인트, 위가 원점)** 로
    /// 돌려준다 — 비트맵이 2x 백킹이면 픽셀 수가 두 배라, 픽셀 좌표를 그대로 쓰면 자른 결과가
    /// 두 배 크기로 나온다. 전부 투명하면 nil.
    static func contentRect(of image: NSImage) -> CGRect? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              cg.width > 0, cg.height > 0 else { return nil }
        let width = cg.width, height = cg.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let ctx = CGContext(data: &pixels, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: width * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))

        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            let row = y * width * 4
            for x in 0..<width where pixels[row + x * 4 + 3] > 8 {   // 거의 투명한 안티앨리어싱 가장자리는 무시
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        let scale = image.size.width > 0 ? CGFloat(width) / image.size.width : 1
        guard scale > 0 else { return nil }
        return CGRect(x: CGFloat(minX) / scale, y: CGFloat(minY) / scale,
                      width: CGFloat(maxX - minX + 1) / scale,
                      height: CGFloat(maxY - minY + 1) / scale)
    }

    /// 여러 프레임을 한 사각형으로 — 합집합. 프레임마다 자르면 스프라이트가 칸 안에서 들썩인다.
    static func unionContentRect(of images: [NSImage]) -> CGRect? {
        images.compactMap(contentRect(of:)).reduce(nil) { acc, rect in
            acc.map { $0.union(rect) } ?? rect
        }
    }

    /// 잘라낸 이미지. `rect` 는 `contentRect` 와 같은 포인트 좌표계다.
    /// 사각형이 비었거나 이미지 밖이면 원본을 그대로 돌려준다 — 잘라내기가 실패해도
    /// 스프라이트가 사라지는 일은 없어야 한다.
    static func cropped(_ image: NSImage, to rect: CGRect) -> NSImage {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              image.size.width > 0 else { return image }
        let scale = CGFloat(cg.width) / image.size.width
        guard scale > 0 else { return image }
        let inPixels = CGRect(x: rect.minX * scale, y: rect.minY * scale,
                              width: rect.width * scale, height: rect.height * scale)
        let bounds = CGRect(x: 0, y: 0, width: cg.width, height: cg.height)
        let clamped = inPixels.intersection(bounds)
        guard !clamped.isEmpty, let cut = cg.cropping(to: clamped) else { return image }
        // 포인트 크기로 되돌려 둬야 2x 백킹 이미지가 두 배로 커지지 않는다.
        return NSImage(cgImage: cut,
                       size: NSSize(width: clamped.width / scale, height: clamped.height / scale))
    }
}
