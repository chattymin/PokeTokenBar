import AppKit
import ImageIO
import UniformTypeIdentifiers

/// 뮤 스프라이트에 메타몽의 얼굴을 넣는다 — 변신이 눈까지는 못 따라간다는 그 설정이다.
///
/// **왜 그려서 만드나.** 이 저장소는 포켓몬 에셋을 배포물에 담지 않는다(README 명시). 그래서 위장
/// 그림을 미리 만들어 넣을 수 없고, 앱이 이미 런타임에 받아 캐시하는 뮤 스프라이트를 기기에서
/// 변환한다. 원칙을 지키면서, 위장 대상이 늘어도 같은 코드로 간다.
///
/// **핵심은 자리를 만든다는 것이다.** 뮤의 눈은 세로 다섯 줄을 차지하는데 메타몽의 얼굴은 그보다
/// 작다 — 점 둘과 그 아래 가로선 하나가 전부다. 그래서 뮤의 눈을 통째로 지우면 **메타몽 얼굴이
/// 들어갈 빈 자리가 생긴다.** 처음엔 이 사실을 못 보고 턱 아래에서만 입 자리를 찾다가, 뮤의 머리가
/// 열세 픽셀뿐이라 거의 모든 프레임에서 입을 못 그렸다.
///
/// 색만 빼 보기도 했다(홍채를 선 색으로 덮기). 눈 모양은 살았지만 그건 초점 잃은 뮤일 뿐
/// 메타몽이 아니었다 — 메타몽 얼굴이 읽히는 건 *빈 바탕에 작은 점 둘과 넓은 입*이라는 관계다.
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
        var carried: FaceLayout?
        for index in 0..<count {
            guard let frame = CGImageSourceCreateImageAtIndex(source, index, nil) else { return nil }
            // 자리를 다음 프레임으로 넘긴다 — 뮤가 눈을 감는 프레임에서 얼굴이 사라지지 않게.
            let result = disguise(frame, reusing: carried)
            if let result { carried = result.layout }
            let made = result?.image ?? frame
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

    /// 얼굴이 놓일 자리 — 뮤의 눈을 지워 만든 네모 둘.
    ///
    /// 그리기와 갈라 둔 이유는 **프레임 사이의 흔들림을 잴 수 있어야** 하기 때문이다. 자리가
    /// 프레임마다 튀면 얼굴이 붙었다 떨어졌다 하는 것처럼 보인다(사용자 지적).
    struct FaceLayout: Equatable, Sendable {
        struct Rect: Equatable, Sendable {
            var minX: Int, maxX: Int, minY: Int, maxY: Int
            var midX: Int { (minX + maxX) / 2 }
        }
        struct Room: Equatable, Sendable {
            /// 지울 네모 — 눈 테두리와 그늘까지 넉넉히 덮는다.
            var erased: Rect
            /// 홍채의 네모 — 점을 찍을 자리는 여기서 잡는다.
            var iris: Rect
        }
        var eyes: [Room]

        /// 눈이 찍힐 자리.
        ///
        /// **지운 네모가 아니라 홍채에 건다.** 지운 네모의 경계는 그 프레임에서 눈 테두리가 어디까지
        /// 이어졌느냐에 따라 달라져 프레임마다 세 칸씩 튄다(실측). 홍채의 아래끝은 머리의 위아래
        /// 움직임을 그대로 따라가 매끄럽다 — 얼굴이 머리에 붙어 있으려면 이쪽을 봐야 한다.
        var eyeDots: [(x: Int, y: Int)] { eyes.map { ($0.iris.midX, $0.iris.maxY - 1) } }

        /// 입이 놓일 자리 — 두 네모 사이를 가로지른다. 눈이 하나면 입은 없다.
        var mouth: (x: Int, y: Int)? {
            guard eyes.count == 2 else { return nil }
            let sorted = eyes.sorted { $0.erased.minX < $1.erased.minX }
            return ((sorted[0].erased.maxX + sorted[1].erased.minX) / 2,
                    min(sorted[0].erased.maxY, sorted[1].erased.maxY) - 1)
        }
    }

    /// 한 프레임에 메타몽 얼굴을 넣는다.
    ///
    /// - Parameter previous: 직전 프레임의 자리. 눈을 못 찾은 프레임(뮤가 눈을 감는다)에 쓴다 —
    ///   없으면 그 한 프레임만 얼굴이 사라져 깜빡인다. **메타몽은 눈을 안 감는다.**
    /// - Returns: 만든 그림과 이번에 쓴 자리. 손댈 것이 없으면 nil.
    static func disguise(_ image: CGImage,
                         reusing previous: FaceLayout? = nil) -> (image: CGImage, layout: FaceLayout)? {
        let canvas = Canvas(image)
        let blues = canvas.coordinates { isBlue($0) }
        // 선 색은 눈 둘레에서 뽑는다. 눈을 못 찾은 프레임은 직전 자리 둘레에서 뽑는다.
        let probe = blues.isEmpty
            ? (previous?.eyes.map { Point(x: $0.iris.midX, y: $0.iris.maxY) } ?? [])
            : blues
        guard !probe.isEmpty else { return nil }
        let ink = faceInk(canvas, near: probe)

        let layout: FaceLayout
        if blues.isEmpty {
            guard let previous else { return nil }
            layout = previous
            // 직전 자리를 그대로 비운다 — 감은 눈의 선이 남아 얼굴에 겹치지 않게.
            for room in layout.eyes { blank(canvas, room.erased) }
        } else {
            var rooms = splitEyes(blues).map { erase(canvas, eye: $0) }
            rooms.sort { $0.erased.minX < $1.erased.minX }
            layout = FaceLayout(eyes: rooms)
        }

        // 눈 — 작은 점. 메타몽의 눈은 점이고, 크게 그리면 "네모"로 읽힌다.
        for dot in layout.eyeDots {
            canvas.set(Point(x: dot.x, y: dot.y), ink)
            canvas.set(Point(x: dot.x + 1, y: dot.y), ink)
        }
        // 입 — 폭이 이 얼굴의 핵심이다. 메타몽의 입은 제 얼굴을 절반쯤 가로지르고, 짧게 그리면
        // 점 몇 개로 보인다. 한 칸 층진 것도 원본 그대로다.
        if let mouth = layout.mouth {
            for dx in -3...0 { canvas.set(Point(x: mouth.x + dx, y: mouth.y), ink) }
            for dx in 1...3 { canvas.set(Point(x: mouth.x + dx, y: mouth.y + 1), ink) }
        }
        guard let made = canvas.image else { return nil }
        return (made, layout)
    }

    /// 네모 하나를 살색으로 비운다(실루엣은 남긴다).
    private static func blank(_ canvas: Canvas, _ rect: FaceLayout.Rect) {
        var cells: Set<Point> = []
        for y in rect.minY...rect.maxY {
            for x in rect.minX...rect.maxX {
                let point = Point(x: x, y: y)
                guard canvas[point].a > 128, !canvas.onSilhouette(point) else { continue }
                cells.insert(point)
            }
        }
        let fills = cells.map { ($0, skinNear(canvas, $0, avoiding: cells)) }
        for (point, color) in fills { canvas.set(point, color) }
    }

    /// 눈 하나를 지우고, 지운 네모를 돌려준다.
    ///
    /// **네모를 통째로 비운다.** 색으로 고른 픽셀만 지우면 눈두덩 그늘(어두운 살색)이 살아남는다 —
    /// 잉크도 파랑도 하이라이트도 아니라 어느 조건에도 안 걸린다. 그렇게 남은 그늘이 원래 눈의
    /// 윤곽을 그려서, 그 위에 메타몽 눈을 얹으면 눈이 둘로 겹쳐 보인다(사용자 지적).
    /// 실루엣만 빼고 다 지운다 — 바깥 테두리까지 지우면 머리에 구멍이 뚫린다.
    private static func erase(_ canvas: Canvas, eye seeds: [Point]) -> FaceLayout.Room {
        // **눈만큼만 번진다.** 뮤의 눈 테두리는 목·팔 같은 몸 안쪽 선과 이어져 있어서, 가두지
        // 않으면 탐색이 얼굴 밖으로 새어 나가 몸의 절반을 눈으로 친다. 그러면 지운 네모가 프레임마다
        // 들쭉날쭉해지고(실측: 눈 자리가 최대 아홉 칸씩 튀었다) 얼굴이 붙었다 떨어졌다 한다.
        let sx = seeds.map(\.x), sy = seeds.map(\.y)
        let reach = 3
        let bounds = (minX: sx.min()! - reach, maxX: sx.max()! + reach,
                      minY: sy.min()! - reach, maxY: sy.max()! + reach)

        var seen = Set(seeds)
        var queue = seeds
        let steps = [(-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (1, -1), (-1, 1), (1, 1)]
        while let point = queue.popLast() {
            for (dx, dy) in steps {
                let next = Point(x: point.x + dx, y: point.y + dy)
                guard !seen.contains(next),
                      next.x >= bounds.minX, next.x <= bounds.maxX,
                      next.y >= bounds.minY, next.y <= bounds.maxY else { continue }
                let pixel = canvas[next]
                guard isInk(pixel) || isBlue(pixel) || isHighlight(pixel) else { continue }
                guard !canvas.onSilhouette(next) else { continue }
                seen.insert(next); queue.append(next)
            }
        }
        let xs = seen.map(\.x), ys = seen.map(\.y)
        let erased = FaceLayout.Rect(minX: xs.min()! - 1, maxX: xs.max()! + 1,
                                     minY: ys.min()! - 1, maxY: ys.max()! + 1)
        blank(canvas, erased)
        return FaceLayout.Room(erased: erased,
                               iris: FaceLayout.Rect(minX: sx.min()!, maxX: sx.max()!,
                                                     minY: sy.min()!, maxY: sy.max()!))
    }

    /// 지운 자리를 메울 살색.    /// 지운 자리를 메울 살색.
    ///
    /// **밝은 살결을 먼저 찾는다.** 가장 가까운 아무 픽셀이나 쓰면 눈두덩 그늘을 퍼오게 되고,
    /// 눈이 있던 자리에 회색 얼룩이 남아 "지웠다"가 아니라 "뭉갰다"로 보인다(실측).
    private static func skinNear(_ canvas: Canvas, _ point: Point,
                                 avoiding room: Set<Point>) -> (r: Int, g: Int, b: Int) {
        func candidate(_ at: Point) -> (r: Int, g: Int, b: Int)? {
            let p = canvas[at]
            guard p.a > 128, !isInk(p), !isBlue(p), !isHighlight(p), !room.contains(at) else { return nil }
            return (p.r, p.g, p.b)
        }
        for lightOnly in [true, false] {
            for distance in 1...10 {
                for at in [Point(x: point.x - distance, y: point.y), Point(x: point.x + distance, y: point.y),
                           Point(x: point.x, y: point.y - distance), Point(x: point.x, y: point.y + distance)] {
                    guard let color = candidate(at) else { continue }
                    if !lightOnly || (color.r > 230 && color.g > 195) { return color }
                }
            }
        }
        return (254, 213, 229)   // 뮤의 살색 — 주변을 하나도 못 찾았을 때의 마지막 보루
    }

    /// 파란 픽셀을 눈별로 가른다.
    ///
    /// **가운데로 자르면 안 된다.** 머리가 돌아가 한쪽 눈만 보이는 그림(정적 스프라이트가 그렇다)에서
    /// 하나뿐인 눈이 둘로 쪼개진다(실측). 실제로 **가로로 떨어져 있을 때만** 가른다.
    static func splitEyes(_ blues: [Point]) -> [[Point]] {
        let columns = Set(blues.map(\.x)).sorted()
        var cut: Int?
        var widest = 1
        for (left, right) in zip(columns, columns.dropFirst()) where right - left > widest {
            widest = right - left
            cut = left
        }
        guard let cut, widest >= 3 else { return [blues] }
        return [blues.filter { $0.x <= cut }, blues.filter { $0.x > cut }].filter { !$0.isEmpty }
    }

    /// 눈 둘레에서 가장 많이 쓰인 어두운 선 색.    /// 눈 둘레에서 가장 많이 쓰인 어두운 선 색. 이 색으로 홍채를 덮는다.
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
