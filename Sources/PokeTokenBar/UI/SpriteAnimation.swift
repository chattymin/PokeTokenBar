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

    /// fps 상한을 **재생 속도를 보존하면서** 적용한다 — 프레임을 늘려 붙이는(hold) 게 아니라
    /// 솎아낸다(decimate). 누적 delay 가 `floor` 를 넘을 때만 그 구간의 첫 프레임을 내보내고
    /// 구간 길이만큼 hold 하므로, 루프 한 바퀴 길이는 원본과 같고 초당 프레임 수만 `1/floor` 로 준다.
    ///
    /// **왜 `max(floor, delay)` 가 아닌가:** 그 방식은 프레임 수를 그대로 두고 각 프레임을 늘리므로
    /// 애니메이션 **전체가 느려진다**. Gen-V 스프라이트는 55프레임×0.05s(=2.75s, 20fps)라 floor 0.4s
    /// 에선 22s 루프 = 1/8 속도가 됐다. 원래 근거였던 "22px 에선 2.5fps 와 5fps 가 구분 안 된다"는
    /// 프레임 레이트에만 맞는 얘기였고, 재생 속도가 8배 늘어나는 건 놓친 것이다(사용자 지적,
    /// 2026-08-20 — 메뉴바가 팝오버보다 느리다는 리포트의 실제 원인). 2프레임 bob 에선 프레임 수가
    /// 적어 늘리기와 솎아내기가 같은 결과라 이 결함이 드러나지 않았다.
    static func capFrameRate(_ frames: [(image: NSImage, delay: TimeInterval)],
                             floor: TimeInterval) -> [(image: NSImage, delay: TimeInterval)] {
        guard floor > 0, frames.count > 1 else { return frames }
        var out: [(image: NSImage, delay: TimeInterval)] = []
        var held: NSImage?          // 현재 구간을 대표하는(= 구간 첫) 프레임
        var acc: TimeInterval = 0   // 구간 누적 길이
        for f in frames {
            if held == nil { held = f.image }
            acc += f.delay
            // 부동소수 누적(0.05×4 = 0.20000000000000004 / 0.19999999999999998)에 걸려 구간이
            // 한 프레임씩 밀리지 않게 epsilon 을 둔다.
            if acc + 1e-9 >= floor {
                out.append((held!, acc))
                held = nil
                acc = 0
            }
        }
        // 마지막 구간이 floor 에 못 미치면 직전 프레임에 합친다 — 총 길이(재생 속도)를 보존한다.
        if let tail = held, acc > 0 {
            if out.isEmpty { out.append((tail, acc)) } else { out[out.count - 1].delay += acc }
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
