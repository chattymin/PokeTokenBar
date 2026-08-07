import AppKit
import ImageIO
import UniformTypeIdentifiers

/// 뮤 스프라이트에 메타몽의 눈과 입을 얹어 위장 그림을 만든다.
///
/// **왜 그려서 만드나.** 이 저장소는 포켓몬 에셋을 배포물에 담지 않는다(README 명시). 그래서 위장
/// 그림을 미리 만들어 넣을 수 없고, 앱이 이미 런타임에 받아 캐시하는 뮤 스프라이트를 기기에서
/// 변환한다. 원칙을 지키면서, 위장 대상이 늘어도 같은 코드로 간다.
///
/// **왜 색으로 눈을 찾나.** 뮤의 몸은 분홍인데 눈만 파랗다. 프레임마다 머리가 움직여 좌표를 적어
/// 둘 수 없으므로(50프레임), 매 프레임 파란 픽셀에서 눈을 찾아 들어간다.
enum DittoDisguiseSprite {
    /// 메타몽의 눈·입 색 — 실제 스프라이트에서 잰 값.
    private static let ink = (r: 39, g: 39, b: 39)

    /// GIF 든 PNG 든 프레임을 전부 변환해 같은 형식으로 돌려준다. 만들지 못하면 nil —
    /// 호출부가 원본을 그대로 쓰게 해서, 변환 실패가 빈 화면이 되지 않게 한다.
    static func apply(to data: Data, animated: Bool) -> Data? {
        guard let source = CGImageSourceCreateWithURL(temporaryURL(for: data) as CFURL, nil)
                ?? CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return nil }
        let type = animated ? UTType.gif.identifier : UTType.png.identifier
        let buffer = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(buffer, type as CFString, count, nil) else {
            return nil
        }
        if animated {
            CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary:
                [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        }
        for index in 0..<count {
            guard let frame = CGImageSourceCreateImageAtIndex(source, index, nil) else { return nil }
            let made = disguise(frame) ?? frame
            if animated {
                // 원본 간격을 그대로 쓴다 — 손으로 적으면 위장 중일 때만 재생 속도가 달라진다.
                CGImageDestinationAddImage(destination, made, [kCGImagePropertyGIFDictionary:
                    [kCGImagePropertyGIFUnclampedDelayTime: delay(of: source, at: index),
                     kCGImagePropertyGIFDelayTime: delay(of: source, at: index)]] as CFDictionary)
            } else {
                CGImageDestinationAddImage(destination, made, nil)
            }
        }
        guard CGImageDestinationFinalize(destination) else { return nil }
        return buffer as Data
    }

    /// `CGImageSourceCreateWithData` 가 애니메이션 GIF 의 프레임 속성을 못 읽는 경우가 있어
    /// 파일을 거쳐 연다. 실패하면 호출부가 데이터 경로로 떨어진다.
    private static func temporaryURL(for data: Data) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ptb-disguise-\(data.count).bin")
        try? data.write(to: url, options: .atomic)
        return url
    }

    private static func delay(of source: CGImageSource, at index: Int) -> Double {
        let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
        let gif = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        return (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
            ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.06
    }

    // MARK: 한 프레임

    /// 한 프레임의 눈을 지우고 메타몽의 눈·입을 얹는다. 눈을 못 찾으면 nil —
    /// 눈을 감은 프레임이 그렇고, 그때는 위조할 것이 없으므로 원본이 맞다.
    static func disguise(_ image: CGImage) -> CGImage? {
        let canvas = Canvas(image)
        let blues = canvas.coordinates { isBlue($0) }
        guard !blues.isEmpty else { return nil }

        let sides = splitEyes(blues)

        var centers: [(x: Int, y: Int)] = []
        for side in sides {
            let blob = eyeBlob(canvas, from: side)
            // 채울 색을 **먼저 다 읽고** 나중에 쓴다 — 지우면서 읽으면 방금 지운 자리를 다시 샘플링한다.
            let fills = blob.map { ($0, canvas.skinNear($0, avoiding: blob)) }
            for (point, color) in fills { canvas.set(point, color) }
            let xs = blob.map(\.x), ys = blob.map(\.y)
            centers.append((x: (xs.min()! + xs.max()!) / 2, y: (ys.min()! + ys.max()!) / 2))
        }

        // 메타몽의 눈은 1픽셀 점이다. 원본이 딱 그렇고, 뮤의 머리는 13픽셀뿐이라 더 키우면 얼굴을 먹는다.
        for center in centers { canvas.set(Point(x: center.x, y: center.y), ink) }

        // 입 — 두 눈 사이 바로 아래. 메타몽의 입은 짧은 선과 한 칸 낮은 선으로 그려져 있고,
        // 그 층짐이 얼굴을 메타몽으로 읽히게 하는 실제 신호다. 원본만큼 내리면(+3) 뮤의 턱·목
        // 외곽선에 붙어 입이 아니라 얼룩이 된다(실측).
        if centers.count == 2 {
            let x = (centers[0].x + centers[1].x) / 2
            let y = max(centers[0].y, centers[1].y) + 1
            for dx in -2...(-1) { canvas.set(Point(x: x + dx, y: y), ink) }
            for dx in 1...2 { canvas.set(Point(x: x + dx, y: y + 1), ink) }
        }
        return canvas.image
    }

    /// 파란 픽셀을 눈별로 가른다.
    ///
    /// **가운데로 자르면 안 된다.** 머리가 돌아가 한쪽 눈만 보이는 그림(정적 스프라이트가 그렇다)에서
    /// 하나뿐인 눈이 둘로 쪼개져, 눈 하나 자리에 점 두 개와 입이 구겨 들어간다(실측). 실제로
    /// **가로로 떨어져 있을 때만** 가른다.
    static func splitEyes(_ blues: [Point]) -> [[Point]] {
        let columns = Set(blues.map(\.x)).sorted()
        // 가장 큰 빈 구간을 찾는다. 두 눈 사이는 여러 칸이 비고, 한 눈 안은 붙어 있다.
        var cut: Int?
        var widest = 1
        for (left, right) in zip(columns, columns.dropFirst()) where right - left > widest {
            widest = right - left
            cut = left
        }
        guard let cut, widest >= 3 else { return [blues] }
        return [blues.filter { $0.x <= cut }, blues.filter { $0.x > cut }].filter { !$0.isEmpty }
    }

    /// 눈 덩어리 — 파란 픽셀에서 이어진 눈동자·하이라이트·테두리를 모은다.
    private static func eyeBlob(_ canvas: Canvas, from seeds: [Point]) -> Set<Point> {
        var seen = Set(seeds)
        var queue = seeds
        let steps = [(-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (1, -1), (-1, 1), (1, 1)]
        while let point = queue.popLast() {
            for (dx, dy) in steps {
                let next = Point(x: point.x + dx, y: point.y + dy)
                guard !seen.contains(next) else { continue }
                let pixel = canvas[next]
                guard isInk(pixel) || isBlue(pixel) || isHighlight(pixel) else { continue }
                // **실루엣은 건드리지 않는다.** 뮤의 눈은 머리 외곽선에 닿아 있어, 외곽선까지
                // 지우면 몸에 구멍이 뚫린다.
                guard !canvas.onSilhouette(next) else { continue }
                seen.insert(next); queue.append(next)
            }
        }
        // 눈 테두리의 **옅은 한색**까지 걷어낸다. 눈동자는 진한 파랑이지만 그 둘레는 살색으로
        // 넘어가는 중간색이라 `isBlue` 에 안 걸린다. 남겨 두면 눈을 지운 자리에 푸르스름한 얼룩이
        // 남아 "메타몽의 눈"이 아니라 "뭉갠 자국"으로 보인다(실측).
        let xs = seen.map(\.x), ys = seen.map(\.y)
        var widened = seen
        for y in (ys.min()! - 1)...(ys.max()! + 1) {
            for x in (xs.min()! - 1)...(xs.max()! + 1) {
                let point = Point(x: x, y: y)
                let pixel = canvas[point]
                guard pixel.a > 128, pixel.b > pixel.r, !canvas.onSilhouette(point) else { continue }
                widened.insert(point)
            }
        }
        return widened
    }

    private static func isInk(_ p: Pixel) -> Bool { p.a > 128 && p.r < 130 && p.g < 130 && p.b < 150 }
    private static func isBlue(_ p: Pixel) -> Bool { p.a > 128 && p.b > p.r + 25 && p.b > p.g + 10 }
    private static func isHighlight(_ p: Pixel) -> Bool { p.a > 128 && p.r > 235 && p.g > 232 && p.b > 232 }

    // MARK: 픽셀 판

    struct Point: Hashable { let x: Int, y: Int }
    struct Pixel { let r: Int, g: Int, b: Int, a: Int }

    /// 한 프레임을 RGBA 로 펼쳐 픽셀 단위로 손대게 해 주는 판.
    final class Canvas {
        private let width: Int, height: Int
        private var bytes: [UInt8]

        init(_ image: CGImage) {
            width = image.width; height = image.height
            bytes = [UInt8](repeating: 0, count: width * height * 4)
            bytes.withUnsafeMutableBytes { buffer in
                guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                              bitsPerComponent: 8, bytesPerRow: width * 4,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                else { return }
                context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            }
        }

        subscript(_ point: Point) -> Pixel {
            guard point.x >= 0, point.x < width, point.y >= 0, point.y < height else {
                return Pixel(r: 0, g: 0, b: 0, a: 0)
            }
            let offset = (point.y * width + point.x) * 4
            return Pixel(r: Int(bytes[offset]), g: Int(bytes[offset + 1]),
                         b: Int(bytes[offset + 2]), a: Int(bytes[offset + 3]))
        }

        func set(_ point: Point, _ color: (r: Int, g: Int, b: Int)) {
            guard point.x >= 0, point.x < width, point.y >= 0, point.y < height else { return }
            let offset = (point.y * width + point.x) * 4
            bytes[offset] = UInt8(color.r); bytes[offset + 1] = UInt8(color.g)
            bytes[offset + 2] = UInt8(color.b); bytes[offset + 3] = 255
        }

        func coordinates(where matches: (Pixel) -> Bool) -> [Point] {
            var found: [Point] = []
            for y in 0..<height {
                for x in 0..<width {
                    let point = Point(x: x, y: y)
                    if matches(self[point]) { found.append(point) }
                }
            }
            return found
        }

        /// 투명에 닿아 있나 — 그런 픽셀은 몸의 외곽선이라 지우면 실루엣이 깨진다.
        func onSilhouette(_ point: Point) -> Bool {
            for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1)]
            where self[Point(x: point.x + dx, y: point.y + dy)].a < 128 { return true }
            return false
        }

        /// 지운 자리를 메울 살색.
        ///
        /// **밝은 살결을 먼저 찾는다.** 가장 가까운 아무 픽셀이나 쓰면 눈두덩 그늘을 퍼오게 되고,
        /// 눈이 있던 자리에 회색 얼룩이 남는다(실측).
        func skinNear(_ point: Point, avoiding blob: Set<Point>) -> (r: Int, g: Int, b: Int) {
            func candidate(_ at: Point) -> (r: Int, g: Int, b: Int)? {
                let p = self[at]
                guard p.a > 128, !isInk(p), !isBlue(p), !isHighlight(p), !blob.contains(at) else { return nil }
                return (p.r, p.g, p.b)
            }
            for lightOnly in [true, false] {
                for distance in 1...10 {
                    let ring = [Point(x: point.x - distance, y: point.y),
                                Point(x: point.x + distance, y: point.y),
                                Point(x: point.x, y: point.y - distance),
                                Point(x: point.x, y: point.y + distance)]
                    for at in ring {
                        guard let color = candidate(at) else { continue }
                        if !lightOnly || (color.r > 230 && color.g > 195) { return color }
                    }
                }
            }
            return (254, 213, 229)   // 뮤의 살색 — 주변을 하나도 못 찾았을 때의 마지막 보루
        }

        var image: CGImage? {
            bytes.withUnsafeMutableBytes { buffer in
                CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                          bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
            }
        }
    }
}
