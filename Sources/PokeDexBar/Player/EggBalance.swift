import Foundation

/// 뽑기·부화·슬롯의 수치. 전부 순수 함수라 굴려 보지 않고도 잠글 수 있다.
enum EggBalance {
    static let drawPrice = 150_000_000
    static let maxSlots = 6
    /// 기본 슬롯 수(2a 의 `PlayerState.slots` 초기값과 같아야 한다).
    static let baseSlots = 3

    /// 등급별 뽑기 확률 — 그 등급이 가진 실제 베이스 종 수에 맞춘 값이다.
    /// (커먼 252종 · 레어 65종 · 에픽 136종 · 레전더리 88종)
    static let odds: [(grade: Grade, probability: Double)] = [
        (.common, 0.55), (.rare, 0.15), (.epic, 0.25), (.legendary, 0.05),
    ]

    /// 0…1 굴림 → 등급. 누적 경계로 자른다.
    ///
    /// `odds` 를 순회하며 `remaining -= probability` 로 누적 차감하면 0.55+0.15 처럼
    /// 이진 소수로 딱 안 떨어지는 값에서 오차가 쌓여(`0.70 - 0.55 == 0.1499999999999999`)
    /// 경계 바로 위 값이 한 등급 아래로 새 버린다. 그래서 경계값을 직접 리터럴로 박아
    /// 굴림과 같은 방식으로 파싱되게 한다 — 비교 양쪽이 같은 리터럴이면 정확히 일치한다.
    static func rollGrade(_ roll: Double) -> Grade {
        let r = min(1, max(0, roll))
        if r < 0.55 { return .common }
        if r < 0.70 { return .rare }
        if r < 0.95 { return .epic }
        return .legendary
    }

    static func duration(_ grade: Grade) -> TimeInterval {
        switch grade {
        case .common: 30 * 60
        case .rare: 2 * 3600
        case .epic: 6 * 3600
        case .legendary: 24 * 3600
        }
    }

    /// N 번째 슬롯의 가격. 기본 슬롯(1~3)과 상한 초과는 nil — 살 수 없다.
    static func slotPrice(forSlotNumber slot: Int) -> Int? {
        switch slot {
        case 4: 500_000_000
        case 5: 1_500_000_000
        case 6: 4_000_000_000
        default: nil
        }
    }

    /// 이로치 판정. 부적은 분모를 낮춘다(1/64 → 1/48).
    static func rollShiny(_ roll: Double, hasCharm: Bool) -> Bool {
        roll < (hasCharm ? 1.0 / 48 : 1.0 / 64)
    }
}
