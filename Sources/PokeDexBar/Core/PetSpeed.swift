import Foundation

/// 플로팅 펫이 얼마나 빨리 움직이나 — 지금 태우고 있는 분당 토큰에서 배속을 정한다.
///
/// 순수 표라 테스트로 잠근다. 화면·타이머와 섞이면 "값은 맞는데 안 빨라진다"를 못 잡는다.
enum PetSpeed {

    /// 배속 사다리. 경계값은 **실제 사용 로그에서 재서** 정했다(5분 창 1043개의 분포):
    /// p25 ≈ 590k, p50 ≈ 1.2M, p75 ≈ 2.1M tok/min. 즉 `light` 는 하위 1/4,
    /// `full` 은 상위 1/4에 해당한다 — 지어낸 숫자가 아니라 실제로 그 빈도로 나온다.
    ///
    /// 상한이 2배인 이유: 원본 GIF 가 보통 10프레임 안팎이라 그 위로는 우스꽝스러워진다.
    static let ladder: [(atLeast: Double, multiplier: Double)] = [
        (2_000_000, 2.0),
        (500_000, 1.5),
        (1, 1.25),
    ]

    /// 유휴일 때의 배속. **정확히 1.0이어야 한다** — 이 기능을 켜도 아무것도 안 하는 동안에는
    /// 프레임 간격이 지금과 한 톨도 달라지지 않는다는 뜻이고, idle wakeup 회귀가 없다는 근거다.
    static let idle: Double = 1.0

    /// 분당 토큰 → 배속. 음수·NaN 같은 말이 안 되는 값은 유휴로 떨어뜨린다.
    static func multiplier(tokensPerMinute: Double) -> Double {
        guard tokensPerMinute.isFinite, tokensPerMinute > 0 else { return idle }
        for step in ladder where tokensPerMinute >= step.atLeast { return step.multiplier }
        return idle
    }

    /// 설정을 반영한 최종 배속. 꺼져 있으면 무조건 유휴 속도다 —
    /// 이 게이트가 한 곳에만 있어야 "설정을 껐는데 여전히 빠르다"가 안 생긴다.
    static func multiplier(tokensPerMinute: Double, enabled: Bool) -> Double {
        enabled ? multiplier(tokensPerMinute: tokensPerMinute) : idle
    }
}
