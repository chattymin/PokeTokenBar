import Foundation

/// 뽑기·부화·슬롯의 수치. 전부 순수 함수라 굴려 보지 않고도 잠글 수 있다.
enum EggBalance {
    static let drawPrice = 10_000_000
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
    /// 아니다(레전더리는 베이스 종의 16% 가량이지만 뽑기 확률은 그보다 한참 아래로 억제한다).
    ///
    /// **레전더리 3% → 2% (도감 미션 도입과 함께, 사용자 결정).** 미션이 레전더리 확정권
    /// 11장을 공급하게 되면서 뽑기 쪽 수급을 조인 것이다 — 알 하나의 기대 비용이 333M → 500M.
    /// 폭을 더 키우지 않은 이유: 세대 완성 미션이 레전더리 88종(베이스) 등록을 요구하는데
    /// 확정권은 대부분 그 *뒤에* 나오므로, 주 수급처는 여전히 뽑기다 — 1% 로 내리면 방금 만든
    /// 미션이 사실상 막힌다(중복 포함 ~440알 규모의 수집이라 확률이 곧 총비용이다).
    /// 뺀 1%p 는 에픽으로 옮겼다(15 → 16%) — 커먼에 주면 뽑는 재미만 준다.
    static let odds: [OddsEntry] = [
        OddsEntry(grade: .common, weight: 600),
        OddsEntry(grade: .rare, weight: 220),
        OddsEntry(grade: .epic, weight: 160),
        OddsEntry(grade: .legendary, weight: 20),
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

    /// 이로치 분모. 부적이 낮춘다 — 이로치 부적 1/48, 무지개 부적 1/32(둘 다 있어도 32).
    ///
    /// 무지개 부적은 이로치 부적의 **업그레이드**라 겹쳐도 더 안 좋아진다 — 전국도감 완성
    /// 보상이고, 이로치 부적 없이도 받을 수 있으므로 독립으로 판정한다.
    static func shinyDenominator(shinyCharm: Bool, rainbowCharm: Bool) -> Int {
        if rainbowCharm { return 32 }
        if shinyCharm { return 48 }
        return 64
    }

    /// 이로치 판정.
    static func rollShiny(_ roll: Double, denominator: Int) -> Bool {
        roll < 1.0 / Double(max(1, denominator))
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
    /// 도감에 없는 종에 주는 배수. **"살짝"이다** — 실제 커먼 풀(252종)로 재면 도감 80% 에서
    /// 미보유가 뜰 확률이 20% → 43% 가 된다. ×5 면 55% 라 "우선"이 아니라 "거의 항상"이 되고,
    /// ×2 면 33% 라 하루 세 마리로는 체감이 안 된다.
    static let unseenBoost = 3

    /// - Parameter unseenIn: 이미 가진 종(`dex`). 주면 그 안에 **없는** 종이 `unseenBoost` 배
    ///   가중을 받는다. nil 이면 가중을 아예 안 곱한다 — 알 뽑기가 쓰는 기본값이다.
    static func pickSpecies(from index: [BaseSpecies], grade: Grade, roll: Double,
                            unseenIn: Set<Int>? = nil) -> Int {
        precondition(!index.isEmpty, "index must not be empty")
        let order = Grade.allCases   // 선언 순서 == common, rare, epic, legendary(낮은 등급 → 높은 등급)
        var candidates: [BaseSpecies] = []
        // 실제로 뽑히는 등급 — 요청 등급이 비어 아래로 내려갔으면 그 등급이다. 가중 방식이
        // 등급마다 다르므로(아래 참고) 요청값이 아니라 이 값으로 판단해야 한다.
        var resolved = grade
        if let start = order.firstIndex(of: grade) {
            var i = start
            while true {
                let pool = index.filter { speciesGrade($0) == order[i] }
                if !pool.isEmpty { candidates = pool; resolved = order[i]; break }
                guard i > 0 else { break }
                i -= 1
            }
        }
        if candidates.isEmpty { candidates = index }   // 이론상 도달 불가 — 안전망

        // **레전더리만 균등하다.** 커먼·레어·에픽은 등급 자체가 포획률로 정의되므로(≤45=에픽 …)
        // 풀 안의 값이 좁고, 남은 편차는 진짜 희귀도다 — 에픽 135종 중 102종이 45 로 같고 나머지
        // 편차는 메탕(3)처럼 원작에서도 희귀한 꼬리에만 있다. 가중이 뜻을 갖는다.
        //
        // 레전더리는 다르다. 등급이 포획률이 아니라 **플래그**(`isLegendary`)로 정해지므로 풀에
        // 3부터 255까지 섞여 들어온다. 그 255 는 "흔하다"가 아니라 원작에서 스토리상 반드시
        // 잡게 되는 아이라 붙은 값이다(테라파고스·무한다이노·네크로즈마). 포획률로 가중하면
        // 이 셋이 각 18.6%, 합쳐서 레전더리 알의 56% 를 차지하고 뮤츠·루기아는 0.22% 가 된다 —
        // 테라파고스가 뮤츠보다 85배 잘 나왔다. 이 풀에서 포획률은 희귀도 정보가 아니라 잡음이다.
        // 아직 도감에 없는 종을 밀어 준다 — **`unseenIn` 을 준 호출부만.** nil 이면 곱하는 일
        // 자체가 없어 알 뽑기의 분포는 한 비트도 안 바뀐다(알은 무엇이 나올지 모르고 사는 것이라
        // 도감을 봐 주면 그 성격이 달라진다).
        //
        // **등급이 정해진 뒤 그 풀 안에서만** 적용한다. 인덱스를 미리 걸러 넘기면, 어떤 등급에
        // 미보유 종이 하나도 없을 때 위 등급 걷기가 아래 등급으로 내려가 **굴려 놓은 등급이
        // 바뀐다.** 여기서 곱하면 그런 일이 없다 — 전부 보유한 등급이면 모든 후보가 같은 배수를
        // 받아 분포가 원래대로 돌아온다.
        let weights = candidates.map { candidate -> Int in
            let base = resolved == .legendary ? 1 : max(1, candidate.captureRate)
            guard let seen = unseenIn else { return base }
            return seen.contains(candidate.id) ? base : base * unseenBoost
        }
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
