import CoreGraphics

/// 픽셀아트 정수배 스케일링.
///
/// Showdown 애니메이션 스프라이트는 45×49 ~ 100×135 로 아주 작아서 96pt 펫 패널에 올리면
/// 4배 가까이 확대된다. EPX 는 소스 픽셀을 그대로 복제·정렬만 하는 정수배 확대라, 몇 번(passes)
/// 돌려야 표시 영역의 실제 화면 픽셀 크기에 가깝게 채우는지가 관건이다.
enum PixelScale {
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

    /// `bounds` 안에 원본 비율을 유지한 채 들어가는 중앙 정렬 사각형.
    /// 스프라이트는 종마다 45×49 ~ 100×135 로 비율이 제각각이라, 정사각형 칸에 그대로 늘리면 찌부된다.
    /// 캔버스 자체는 호출부가 정한 크기를 유지한다 — 메뉴바 아이템 폭이 프레임마다 흔들리면 안 된다.
    static func fittedRect(source: CGSize, in bounds: CGSize) -> CGRect {
        guard source.width > 0, source.height > 0,
              bounds.width > 0, bounds.height > 0 else { return CGRect(origin: .zero, size: bounds) }
        let scale = min(bounds.width / source.width, bounds.height / source.height)
        let size = CGSize(width: source.width * scale, height: source.height * scale)
        return CGRect(x: (bounds.width - size.width) / 2,
                      y: (bounds.height - size.height) / 2,
                      width: size.width, height: size.height)
    }
}
