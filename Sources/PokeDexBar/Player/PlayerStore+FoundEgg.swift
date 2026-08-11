import Foundation

/// 알 발견 — 더 진화할 곳이 없는 개체가 경험치를 모아 자기 라인의 알을 부른다. 받는 순간
/// 곧바로 부화 슬롯에 들어간다 — 중간에 보관되는 물건이 없다(경험치 자체가 저장고다).
///
/// **자동으로 일어나지 않는다.** 진화와 같은 방식으로 배지가 뜨고 사용자가 누를 때 지급된다.
/// 이유는 두 가지다. ① 최종형인지 아는 데 `EvoLine` 이 필요한데 그건 네트워크로 오고 UI 가
/// 비동기로 싣는다 — 사용량 갱신 경로(`update`)에는 라인이 없어 판정 자체가 불가능하다. 거기서
/// 판정하려면 "최종형인가"를 세이브에 캐시해야 하는데, 그건 네트워크에서 파생된 값을 영속 상태에
/// 굳히는 일이라 라인 데이터가 바뀌면 조용히 틀어진다. ② 같은 자리에서 같은 경험치를 쓰는 일이
/// 진화는 클릭, 알 발견은 자동으로 갈리면 안 된다.
///
/// **기다린다고 손해 보지 않는다** — 경험치는 계속 쌓이고 차감은 `exp -= 임계` 이므로,
/// 한 주 만에 열어도 쌓인 만큼 연속으로 받는다(빈 슬롯이 허용하는 만큼).
extension PlayerStore {
    /// 이 개체가 지금 알을 받을 수 있나. **빈 부화 슬롯까지 본다** — 버튼의 활성 조건이 곧
    /// 이 함수다(뷰는 이 함수 하나로 버튼을 켜고 끈다).
    func canTakeFoundEgg(_ individual: Individual, line: EvoLine) -> Bool {
        // 정체를 숨기고 있는 개체는 제외한다 — 받은 라인은 **겉모습의 것**이라 판정이 성립하지
        // 않고, 발견 문구에 적히는 종 이름이 정체를 흘린다.
        // (`IndividualDetailView.choices` 가 진화에 대해 같은 판단을 한다.)
        guard individual.disguisedAs == nil else { return false }
        guard evolutionChoices(individual, line: line).isEmpty else { return false }
        guard individual.exp >= ExpBalance.eggThreshold(grade: individual.grade) else { return false }
        return freeSlots > 0
    }

    /// 알을 받는다. 조건을 못 채우면 아무것도 하지 않고 nil.
    ///
    /// **알을 먼저 놓고, 놓였을 때만 경험치를 깎는다.** 반대로 하면 슬롯이 꽉 찼을 때
    /// 경험치만 사라진다 — 5000만~4억 토큰어치가 조용히 증발하는 사고다.
    @discardableResult
    func takeFoundEgg(individualID: UUID, line: EvoLine) -> Egg? {
        guard let index = state.box.firstIndex(where: { $0.id == individualID }) else { return nil }
        let individual = state.box[index]
        guard canTakeFoundEgg(individual, line: line) else { return nil }
        // 종은 확정이지만 이로치는 평소 확률로 굴린다 — 확정으로 만들면 이로치 부적이 무의미해진다.
        let shiny = EggBalance.rollShiny(nextRandomUnit(), hasCharm: state.ownsShinyCharm)
        // 종은 그 개체의 baseID(리자몽은 파이리를 부른다), 등급은 그 개체의 등급을 그대로 쓴다.
        guard let egg = placeEgg(grade: individual.grade, speciesID: individual.baseID, shiny: shiny)
        else { return nil }
        // 인덱스는 `placeEgg`(state 변형 + save) 가 끝난 **뒤에 다시 찾는다** — 미리 잡아 두면
        // 그 사이 바뀐 배열에 옛 인덱스로 깎는 꼴이 된다.
        mutate { s in
            guard let i = s.box.firstIndex(where: { $0.id == individualID }) else { return }
            // 초과분은 남긴다 — 진화와 같은 이월이다. 통째로 0 으로 만들면 오래 비워 둔
            // 사용자가 쌓아 둔 경험치를 한 번에 전부 잃는다.
            s.box[i].exp -= ExpBalance.eggThreshold(grade: individual.grade)
        }
        return egg
    }
}
