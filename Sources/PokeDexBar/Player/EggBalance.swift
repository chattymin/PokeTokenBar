import Foundation

/// 뽑기·부화·슬롯의 수치. 전부 순수 함수라 굴려 보지 않고도 잠글 수 있다.
enum EggBalance {
    static let drawPrice = 150_000_000
    static let maxSlots = 6
    /// 기본 슬롯 수(2a 의 `PlayerState.slots` 초기값과 같아야 한다).
    static let baseSlots = 3

    /// 뽑기 확률표의 한 행. 정수 천분율(`weight`)이 유일한 선언이고, `probability` 는 그로부터
    /// 파생된다 — 확률을 소수로 따로 적으면 표시(상점)와 실제 뽑기가 각자 소수로 반올림되며 갈라질 수 있다.
    struct OddsEntry {
        let grade: Grade
        /// 천분율 가중치. 네 값의 합은 정확히 1000 이어야 한다(정수라 오차 없이 검증 가능).
        let weight: Int
        /// 상점 등에서 쓰는 0…1 확률 — `weight` 에서 파생, 별도로 손댈 값이 아니다.
        var probability: Double { Double(weight) / 1000 }
    }

    /// 등급별 뽑기 확률 — 종 수 쏠림을 반영해 *가중*한 값이지 그 등급 베이스 종 수의 비율 그대로는
    /// 아니다(레전더리는 베이스 종의 16% 가량이지만 뽑기 확률은 5%로 억제했다).
    static let odds: [OddsEntry] = [
        OddsEntry(grade: .common, weight: 600),
        OddsEntry(grade: .rare, weight: 220),
        OddsEntry(grade: .epic, weight: 150),
        OddsEntry(grade: .legendary, weight: 30),
    ]

    /// 0…1 굴림 → 등급. 누적 경계로 자른다.
    ///
    /// `odds` 를 소수 확률로 순회하며 누적 차감하면 0.55+0.15 처럼 이진 소수로 딱 안 떨어지는
    /// 값에서 오차가 쌓여(`0.70 - 0.55 == 0.1499999999999999`) 경계 바로 위 값이 한 등급
    /// 아래로 새 버린다. 그래서 굴림을 천분율 정수 공간으로 스케일링해(`0.70 → 700`) `weight` 를
    /// 정수로 누적한다 — 정수 덧셈은 오차가 없어 600+220 은 항상 정확히 820 이다.
    static func rollGrade(_ roll: Double) -> Grade {
        let clamped = min(1, max(0, roll))
        let scaled = Int(clamped * 1000)
        var cumulative = 0
        for entry in odds {
            cumulative += entry.weight
            if scaled < cumulative { return entry.grade }
        }
        return odds.last!.grade   // 반올림 여분으로 끝까지 온 경우
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

    // MARK: 뽑기 종 선택

    /// `index` 안에서 `grade` 등급 후보만 걸러 포획률 가중으로 하나를 고른다. `index` 는 비어있지
    /// 않아야 한다(호출부가 네트워크 인덱스를 이미 non-empty 로 확인해 둔다).
    ///
    /// 그 등급의 후보가 하나도 없으면(레전더리·미시컬 플래그가 인덱스에 없던 시절의 결함이 정확히
    /// 이 경로였다) 전체 인덱스로 넓히지 않는다 — 그러면 포획률 가중이 가장 흔한(=가장 안 희귀한)
    /// 종을 오히려 편애해, "레전더리 5%"를 뽑고 최흔 종을 받는 사태가 난다. 대신 한 단계 아래
    /// 등급에서 다시 찾는다(레전더리 없음 → 에픽 → 레어 → 커먼). 커먼까지 내려가도 비어 있으면
    /// (인덱스 자체가 비어있지 않다고 보장되므로 이론상 불가능한 경우) 최후의 보루로 전체를 쓴다.
    static func pickSpecies(from index: [BaseSpecies], grade: Grade, roll: Double) -> Int {
        precondition(!index.isEmpty, "index must not be empty")
        let order = Grade.allCases   // 선언 순서 == common, rare, epic, legendary(낮은 등급 → 높은 등급)
        var candidates: [BaseSpecies] = []
        if let start = order.firstIndex(of: grade) {
            var i = start
            while true {
                let pool = index.filter { speciesGrade($0) == order[i] }
                if !pool.isEmpty { candidates = pool; break }
                guard i > 0 else { break }
                i -= 1
            }
        }
        if candidates.isEmpty { candidates = index }   // 이론상 도달 불가 — 안전망

        let weights = candidates.map { max(1, $0.captureRate) }
        let total = weights.reduce(0, +)
        let clampedRoll = min(1, max(0, roll))
        var pick = Int(clampedRoll * Double(total))
        if pick >= total { pick = total - 1 }   // roll == 1.0 경계에서도 마지막 후보를 가리키게
        var chosen = candidates[0].id
        for (candidate, weight) in zip(candidates, weights) {
            if pick < weight { chosen = candidate.id; break }
            pick -= weight
        }
        return chosen
    }

    private static func speciesGrade(_ species: BaseSpecies) -> Grade {
        Grade.from(captureRate: species.captureRate,
                  isLegendary: species.isLegendary, isMythical: species.isMythical)
    }
}
