import Foundation

/// 여러 마리를 한 번에 보낼 때의 판단들. **순수 함수만** 둔다 — 뷰 없이 테스트로 잠그기 위해서다.
/// 이 기능에서 화면이 스토어와 다른 조건을 적었다가 갈린 적이 있어, 판단은 전부 여기로 모은다.
enum BulkRelease {
    /// 이 배치를 보내기 전에 몇 번 확인하나.
    ///
    /// **배치는 그 안에서 가장 엄한 규칙을 따른다.** 20마리 중 이로치 한 마리가 딸려 나가는 것이
    /// 이 기능의 유일한 진짜 사고라, 하나라도 섞이면 배치 전체가 한 번 더 묻는다.
    ///
    /// 규칙 자체는 단일 보내기의 `releaseConfirmSteps` 를 그대로 쓴다 — 두 군데 적으면 갈린다.
    /// 빈 배치가 1인 것은 확인 화면이 안 뜨기 때문이 아니라, 0을 돌려주면 호출부의 단계 비교가
    /// 뜻을 잃기 때문이다.
    static func confirmSteps(for individuals: [Individual]) -> Int {
        individuals.reduce(1) { steps, individual in
            max(steps, IndividualDetailView.releaseConfirmSteps(shiny: individual.shiny,
                                                                grade: individual.grade))
        }
    }

    /// 확인 화면에서 **이름으로 불러 줄** 아이들 — 이로치와 전설.
    /// 스무 마리를 다 나열하면 아무도 안 읽지만, 위험한 것만 부르면 읽힌다.
    static func risky(_ individuals: [Individual]) -> [Individual] {
        individuals.filter { $0.shiny || $0.grade == .legendary }
    }

    /// 확인 줄에 실제로 찍히는 이름 — **왜 불려 있는지**를 이름 앞에 달아 준다.
    /// `Individual.displayName` 은 메가·거다이맥스·지방 접두는 알아도 이로치 여부는 모른다.
    /// 그래서 이로치 파이리와 평범한 파이리가 한 배치에 있으면 이름만으로는 어느 쪽이
    /// 불려 있는지 갈리지 않는다 — 표식이 이 리스트의 존재 이유다.
    ///
    /// **위장 중인 아이는 표식을 안 붙인다.** 이름이 이미 "???" 라 표식을 더 붙이면
    /// (예: "이로치 ???") 정체는 몰라도 "뭔가 특별한 게 숨어 있다"는 힌트가 반쯤 새는
    /// 셈이라, 위장 규칙("정체가 드러나기 전엔 아무것도 티 내지 않는다")과 어긋난다.
    static func riskyLabel(_ individual: Individual, name: String, l: L) -> String {
        guard individual.disguisedAs == nil else { return name }
        var marks: [String] = []
        if individual.shiny { marks.append(l.riskyShinyMark) }
        if individual.grade == .legendary { marks.append(individual.grade.label(l.lang)) }
        return (marks + [name]).joined(separator: " ")
    }
}
