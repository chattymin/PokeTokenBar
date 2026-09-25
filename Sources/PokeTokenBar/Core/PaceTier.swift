import Foundation

/// 한도 게이지의 페이스 대비 6단계. 기준값은 delta = 사용률 − 페이스(%p) — 창 길이에 이미
/// 정규화된 값이라 5시간·주간 창이 같은 경계를 쓴다.
/// 판정은 **실제 사용률** 기준이라 표시 모드(used/remaining)와 무관하다 — `limitColor` 와 같은 규칙.
/// 경고 알림·메뉴바·플로팅 펫은 여전히 절대 임계로 판정한다. 이건 팝오버 행의 색만 정한다.
enum PaceTier: Int, CaseIterable {
    case wayUnder, under, onPace, slightlyOver, over, wayOver

    /// 창의 이 비율이 지나기 전엔 단계를 보류한다(5시간 창 30분, 주간 창 약 17시간).
    /// 초반엔 페이스가 0 에 가까워 요청 하나로도 delta 가 몇 단계씩 튄다.
    static let minimumPace = 0.1

    /// nil 이면 호출부가 절대 임계색(`limitColor`)으로 돌아간다 — 페이스가 없거나 보류 중인 행.
    static func tier(utilization: Double, pace: Double?, critThreshold: Double) -> PaceTier? {
        guard let pace, pace >= minimumPace else { return nil }
        if utilization >= critThreshold { return .wayOver }
        // 반올림한 delta 로 판정해 툴팁에 찍히는 정수와 단계가 경계에서 어긋나지 않게 한다.
        switch roundedDelta(utilization: utilization, pace: pace) {
        case ..<(-25): return .wayUnder
        case ..<(-10): return .under
        case ..<5: return .onPace
        case ..<15: return .slightlyOver
        case ..<30: return .over
        default: return .wayOver
        }
    }

    static func roundedDelta(utilization: Double, pace: Double) -> Int {
        Int((utilization - pace * 100).rounded())
    }
}
