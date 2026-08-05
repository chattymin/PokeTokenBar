import AppKit
import ImageIO
import UniformTypeIdentifiers

/// GIF 바이트 → 프레임(이미지 + 지속시간) 디코드. Gen-V 움직이는 스프라이트(메뉴바)용.
enum GIFDecoder {
    /// 각 프레임의 원본 이미지 + delay(초). 단일 프레임/디코드 실패 시 빈 배열.
    static func frames(from data: Data) -> [(image: NSImage, delay: TimeInterval)] {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return [] }
        let count = CGImageSourceGetCount(src)
        guard count > 1 else { return [] }
        var out: [(NSImage, TimeInterval)] = []
        for i in 0..<count {
            guard let cg = CGImageSourceCreateImageAtIndex(src, i, nil) else { continue }
            let img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            out.append((img, delay(src, i)))
        }
        return out
    }

    /// GIF 프레임 delay. unclamped 우선, 너무 짧으면(브라우저 관행) 0.1s 로 보정.
    private static func delay(_ src: CGImageSource, _ index: Int) -> TimeInterval {
        guard let props = CGImageSourceCopyPropertiesAtIndex(src, index, nil) as? [CFString: Any],
              let gif = props[kCGImagePropertyGIFDictionary] as? [CFString: Any] else { return 0.1 }
        let unclamped = gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double
        let clamped = gif[kCGImagePropertyGIFDelayTime] as? Double
        let d = unclamped ?? clamped ?? 0.1
        return d < 0.02 ? 0.1 : d
    }
}
