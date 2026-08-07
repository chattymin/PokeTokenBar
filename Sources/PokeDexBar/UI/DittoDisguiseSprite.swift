import AppKit
import ImageIO
import UniformTypeIdentifiers

/// 뮤 스프라이트의 눈에서 색을 뺀다 — 메타몽이 변신할 때 눈까지는 못 따라간다는 그 설정이다.
///
/// **왜 그려서 만드나.** 이 저장소는 포켓몬 에셋을 배포물에 담지 않는다(README 명시). 그래서 위장
/// 그림을 미리 만들어 넣을 수 없고, 앱이 이미 런타임에 받아 캐시하는 뮤 스프라이트를 기기에서
/// 변환한다. 원칙을 지키면서, 위장 대상이 늘어도 같은 코드로 간다.
///
/// **왜 지우고 새로 그리지 않나.** 처음엔 눈을 지우고 그 자리에 메타몽의 점 두 개와 넓은 입을
/// 그렸다. 안 됐다. 뮤의 머리는 13픽셀뿐이고 눈 바로 아래가 턱·목이라 입이 들어갈 자리가 거의
/// 없어 대부분의 프레임에서 입이 통째로 빠졌고, 눈을 키우니 "눈"이 아니라 "네모"로 읽혔다.
/// 진짜 메타몽 얼굴이 읽히는 건 크기가 아니라 *빈 바탕에 작은 점 둘과 긴 가로선*이라는 관계인데,
/// 뮤의 얼굴은 빈 바탕이 아니다.
///
/// 그래서 **뮤의 눈 모양은 그대로 두고 색만 뺀다.** 홍채와 흰 하이라이트를 뮤 자신의 선 색으로
/// 덮으면 눈의 생김새는 살아 있고 초점만 사라진다 — 얹은 티가 안 나면서 확실히 잘못돼 보인다.
///
/// **왜 색으로 눈을 찾나.** 뮤의 몸은 분홍인데 눈만 파랗다. 프레임마다 머리가 움직여 좌표를 적어
/// 둘 수 없으므로(50프레임), 매 프레임 파란 픽셀에서 눈을 찾아 들어간다.
enum DittoDisguiseSprite {
    /// 얼굴 선 색을 못 뽑았을 때의 마지막 보루 — 뮤 애니메이션의 얼굴 선 실측값.
    private static let fallbackInk = (r: 98, g: 80, b: 87)

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
                let seconds = delay(of: source, at: index)
                CGImageDestinationAddImage(destination, made, [kCGImagePropertyGIFDictionary:
                    [kCGImagePropertyGIFUnclampedDelayTime: seconds,
                     kCGImagePropertyGIFDelayTime: seconds]] as CFDictionary)
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

    /// 한 프레임의 눈에서 색을 뺀다. 눈을 못 찾으면 nil —
    /// 눈을 감은 프레임이 그렇고, 그때는 손댈 것이 없으므로 원본이 맞다.
    static func disguise(_ image: CGImage) -> CGImage? {
        let canvas = Canvas(image)
        let blues = canvas.coordinates { isBlue($0) }
        guard !blues.isEmpty else { return nil }

        // **선 색은 뮤에게서 빌린다.** 순수한 검정으로 덮으면 얹은 티가 나고, 스프라이트마다 선
        // 색이 다르다 — 움직이는 쪽은 (98,80,87), 정적 쪽은 (90,41,82) 이다(실측).
        let ink = faceInk(canvas, near: blues)
        for point in iris(canvas, from: blues) { canvas.set(point, ink) }
        return canvas.image
    }

    /// 색을 뺄 자리 = 홍채. 파란 픽셀에서 시작해 거기 붙은 **흰 하이라이트**까지 먹는다 —
    /// 하이라이트를 남기면 초점이 살아 있어 눈이 여전히 뮤의 눈으로 보인다.
    ///
    /// **눈의 테두리는 건드리지 않는다.** 그 어두운 선이 눈의 생김새이고, 덮으면 눈이 뭉개진다.
    ///
    /// 실루엣에 닿은 픽셀은 **뺴지 않는다.** 뮤의 눈은 머리 가장자리에 붙어 있어, 실루엣을 피하면
    /// 그쪽 눈의 하이라이트가 옅게 남아 초점이 살아 있다(실측). 밝은 살색으로 *지우던* 시절엔
    /// 그 가드가 필요했지만 — 지우면 몸에 구멍이 났다 — 지금은 어두운 선 색으로 *덮으므로*
    /// 불투명한 어두운 픽셀이 그대로 남는다. 실루엣은 깨지지 않는다.
    static func iris(_ canvas: Canvas, from blues: [Point]) -> Set<Point> {
        var seen = Set(blues)
        var queue = blues
        let steps = [(-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (1, -1), (-1, 1), (1, 1)]
        while let point = queue.popLast() {
            for (dx, dy) in steps {
                let next = Point(x: point.x + dx, y: point.y + dy)
                guard !seen.contains(next), isBlue(canvas[next]) || isHighlight(canvas[next])
                else { continue }
                seen.insert(next); queue.append(next)
            }
        }
        return seen
    }

    /// 눈 둘레에서 가장 많이 쓰인 어두운 선 색. 이 색으로 홍채를 덮는다.
    ///
    /// 실루엣(투명에 닿은 픽셀)은 뺀다 — 바깥 테두리는 거의 검정이라(39,39,39) 그걸 뽑으면
    /// 다시 새까만 눈이 된다. 얼굴 안쪽 선은 그보다 따뜻하다.
    static func faceInk(_ canvas: Canvas, near blues: [Point]) -> (r: Int, g: Int, b: Int) {
        let xs = blues.map(\.x), ys = blues.map(\.y)
        var tally: [Pixel3: Int] = [:]
        for y in (ys.min()! - 2)...(ys.max()! + 2) {
            for x in (xs.min()! - 2)...(xs.max()! + 2) {
                let point = Point(x: x, y: y)
                let pixel = canvas[point]
                guard isInk(pixel), !isBlue(pixel), !canvas.onSilhouette(point) else { continue }
                tally[Pixel3(r: pixel.r, g: pixel.g, b: pixel.b), default: 0] += 1
            }
        }
        // 동률이면 어두운 쪽으로 — 선은 진해야 눈으로 읽힌다.
        guard let best = tally.max(by: { ($0.value, $1.key.sum) < ($1.value, $0.key.sum) })?.key else {
            return fallbackInk
        }
        return (best.r, best.g, best.b)
    }

    private static func isInk(_ p: Pixel) -> Bool { p.a > 128 && p.r < 130 && p.g < 130 && p.b < 150 }
    private static func isBlue(_ p: Pixel) -> Bool { p.a > 128 && p.b > p.r + 25 && p.b > p.g + 10 }
    /// 눈의 밝은 부분 — 흰 하이라이트와 그 둘레의 옅은 회색.
    ///
    /// 순수한 흰색(`r>235`)만 잡으면 그 바로 옆의 옅은 회색이 남아 눈에 초점이 살아 있다(실측).
    /// 판정은 "밝고 **분홍이 아닌** 것"이다 — 뮤의 살색은 (254,213,229) 처럼 빨강이 파랑보다
    /// 뚜렷이 커서 이 조건에 안 걸린다. 그래서 얼굴을 먹지 않는다.
    private static func isHighlight(_ p: Pixel) -> Bool {
        p.a > 128 && p.r > 175 && p.b >= p.r - 8
    }

    // MARK: 픽셀 판

    struct Point: Hashable { let x: Int, y: Int }
    struct Pixel { let r: Int, g: Int, b: Int, a: Int }
    struct Pixel3: Hashable { let r: Int, g: Int, b: Int; var sum: Int { r + g + b } }

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

        /// 투명에 닿아 있나 — 그런 픽셀은 몸의 외곽선이라 덮으면 실루엣이 달라진다.
        func onSilhouette(_ point: Point) -> Bool {
            for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1)]
            where self[Point(x: point.x + dx, y: point.y + dy)].a < 128 { return true }
            return false
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
