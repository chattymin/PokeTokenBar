import CoreGraphics

/// 픽셀아트 정수배 스케일링.
///
/// Showdown 애니메이션 스프라이트는 45×49 ~ 100×135 로 아주 작아서 96pt 펫 패널에 올리면
/// 4배 가까이 확대된다. 이때 배율이 정수가 아니면 최근접 이웃 보간(.none)이 소스 픽셀 하나를
/// 어떤 자리에선 4px, 어떤 자리에선 3px 로 찍는다 — 계단 폭이 들쭉날쭉해지는 원인. 표시 크기를
/// 정수배로 스냅해 "소스 픽셀 1개 = 화면 픽셀 N×N" 이 정확히 성립하게 만든다.
enum PixelScale {
    /// - Parameters:
    ///   - source: 소스 이미지의 픽셀 크기
    ///   - bounds: 표시 영역(pt)
    ///   - displayScale: 화면 배율(Retina 는 2)
    ///   - antialiased: PixelUpscaler.epx 로 이미 계단을 깎은 프레임인지. 이 경우 남은 배율은
    ///     정수로 스냅하지 않고 박스를 채우는 데 쓴다 — 아래 fill(...) 주석 참고.
    /// - Returns: 표시 크기(pt)와 최근접 이웃 보간 사용 여부. 소스가 표시 영역보다 커서
    ///   축소해야 하면 정수배가 성립하지 않으므로 부드러운 보간을 쓰라고 알린다.
    static func fit(source: CGSize, in bounds: CGSize, displayScale: CGFloat,
                    antialiased: Bool = false) -> (size: CGSize, pixelated: Bool) {
        guard source.width > 0, source.height > 0, displayScale > 0,
              bounds.width > 0, bounds.height > 0 else { return (bounds, false) }

        if antialiased { return fill(source: source, in: bounds, displayScale: displayScale) }

        // 정수배 판정은 실제로 찍히는 화면 픽셀 기준이어야 한다 — Retina 에서 96pt 는 192px.
        let device = CGSize(width: bounds.width * displayScale,
                            height: bounds.height * displayScale)
        let factor = min(device.width / source.width, device.height / source.height)

        // 축소 구간(예: 203×79 트로피우스를 96pt 안에). 정수 축소는 픽셀 행을 통째로 버려
        // 프레임마다 다른 부분이 사라지므로, 비율만 맞추고 보간에 맡긴다.
        guard factor >= 1 else {
            let shrink = min(bounds.width / source.width, bounds.height / source.height)
            return (CGSize(width: source.width * shrink, height: source.height * shrink), false)
        }

        let n = factor.rounded(.down)
        return (CGSize(width: source.width * n / displayScale,
                       height: source.height * n / displayScale), true)
    }

    /// EPX 로 확대해둔 프레임을 박스에 꽉 채운다.
    ///
    /// EPX 는 2배 단위로만 커지므로, 정수배 스냅까지 함께 강제하면 총 배율이 뚝 떨어진다
    /// (45×49 를 96pt 박스에: 정수배만 = 3배, EPX 2배 + 정수배 = 2배). 즉 안티앨리어싱을
    /// 켰는데 펫이 작아진다. EPX 가 이미 계단을 깎아놨으니 남은 배율은 크기를 채우는 데 쓰고,
    /// 정수로 떨어지지 않는 나머지만 보간에 맡긴다 — 원본에서 곧장 3.92배 보간하는 것보다
    /// 훨씬 덜 흐리다.
    private static func fill(source: CGSize, in bounds: CGSize,
                             displayScale: CGFloat) -> (size: CGSize, pixelated: Bool) {
        let s = min(bounds.width / source.width, bounds.height / source.height)
        let device = s * displayScale
        // 마침 정수배로 떨어지면 보간 없이 최근접 이웃이 더 선명하다.
        let exact = device >= 1 && abs(device - device.rounded()) < 0.0001
        return (CGSize(width: source.width * s, height: source.height * s), exact)
    }

    /// EPX 를 몇 번 돌릴지 — 2의 거듭제곱 배율만 가능하므로 가용 배율 이하의 최대 거듭제곱.
    /// 상한 2회(4배)는 메모리 때문. 45×49 × 4배 × 41프레임 ≈ 5.8MB 선.
    static func epxPasses(source: CGSize, in bounds: CGSize, displayScale: CGFloat,
                          limit: Int = 2) -> Int {
        guard source.width > 0, source.height > 0, displayScale > 0,
              bounds.width > 0, bounds.height > 0 else { return 0 }
        let device = CGSize(width: bounds.width * displayScale,
                            height: bounds.height * displayScale)
        let factor = min(device.width / source.width, device.height / source.height)
        var passes = 0, scale = 1.0
        while passes < limit, scale * 2 <= factor { scale *= 2; passes += 1 }
        return passes
    }
}
