import Foundation

/// 알 발견 — **파트너**가 알 계량기(`eggProgress`)를 채워 자기 라인의 알을 부른다. 받는 순간
/// 곧바로 부화 슬롯에 들어간다 — 중간에 보관되는 물건이 없다(알 계량기 자체가 저장고다).
///
/// **더 이상 최종형일 필요가 없다.** 예전엔 진화할 곳이 남았으면 제외했지만, `eggProgress` 가
/// `exp` 와 분리된 뒤로는 둘이 서로의 진행을 깎지 않는다 — 진화 중인 개체도 알을 부를 수 있다.
/// 자격은 **파트너인 동안 토큰이 쌓인다**는 사실 하나로 충분하다(`PlayerStore.update`).
///
/// **자동으로 일어나지 않는다.** 진화와 같은 방식으로 배지가 뜨고 사용자가 누를 때 지급된다 —
/// 같은 자리에서 같은 파트너가 쓰는 일이 진화는 클릭, 알 발견은 자동으로 갈리면 안 되기 때문이다.
///
/// **한 번에 한 개다.** 알 계량기는 알 임계에서 멈추고(`PlayerStore.update` 의 상한), 받으면
/// 0 으로 돌아간다. 그래서 알이 두 개 예약되는 일이 없다 — 받아야 다시 쌓인다.
///
/// 그 대신 **다 찬 채로 두면 그동안의 알 진행분은 안 쌓인다.** 알을 받는 것이 밀린 수령이 아니라
/// 결정이 되게 하려는 의도된 맞바꿈이다(재화·사탕·경험치는 상한과 무관하게 계속 들어온다).
extension PlayerStore {
    /// 이 개체가 지금 알을 받을 수 있나. **빈 부화 슬롯까지 본다** — 버튼의 활성 조건이 곧
    /// 이 함수다(뷰는 이 함수 하나로 버튼을 켜고 끈다).
    func canTakeFoundEgg(_ individual: Individual, line: EvoLine) -> Bool {
        // 정체를 숨기고 있는 개체는 제외한다 — 받은 라인은 **겉모습의 것**이라 판정이 성립하지
        // 않고, 발견 문구에 적히는 종 이름이 정체를 흘린다.
        // (`IndividualDetailView.choices` 가 진화에 대해 같은 판단을 한다.)
        guard individual.disguisedAs == nil else { return false }
        guard individual.eggProgress >= ExpBalance.eggThreshold(grade: individual.grade) else { return false }
        return freeSlots > 0
    }

    /// 알을 받는다. 조건을 못 채우면 아무것도 하지 않고 nil.
    ///
    /// **알을 먼저 놓고, 놓였을 때만 알 계량기를 깎는다.** 반대로 하면 슬롯이 꽉 찼을 때
    /// 진행분만 사라진다 — 5억~40억 토큰어치가 조용히 증발하는 사고다.
    @discardableResult
    func takeFoundEgg(individualID: UUID, line: EvoLine) -> Egg? {
        guard let index = state.box.firstIndex(where: { $0.id == individualID }) else { return nil }
        let individual = state.box[index]
        guard canTakeFoundEgg(individual, line: line) else { return nil }
        // 종은 확정이지만 이로치는 평소 확률로 굴린다 — 확정으로 만들면 이로치 부적이 무의미해진다.
        let shiny = EggBalance.rollShiny(nextRandomUnit(), denominator: shinyDenominator)
        // 종은 그 개체의 baseID(리자몽은 파이리를 부른다), 등급은 그 개체의 등급을 그대로 쓴다.
        // 성장 타입은 라인에서 baseID 기준으로 다시 찾는다 — 진화한 개체의 growthRate 는 지금
        // 폼(예: 리자몽) 기준일 수 있어, 알이 될 baseID(파이리) 의 값과 다를 수 있다. 라인이
        // 아직 안 받아져 있으면(nil) 그 개체가 이미 들고 있는 값으로 물러난다.
        let growthRate = line.growthRate(of: individual.baseID) ?? individual.growthRate
        guard let egg = placeEgg(grade: individual.grade, speciesID: individual.baseID, shiny: shiny,
                                 growthRate: growthRate)
        else { return nil }
        // 인덱스는 `placeEgg`(state 변형 + save) 가 끝난 **뒤에 다시 찾는다** — 미리 잡아 두면
        // 그 사이 바뀐 배열에 옛 인덱스로 깎는 꼴이 된다.
        mutate { s in
            guard let i = s.box.firstIndex(where: { $0.id == individualID }) else { return }
            // **알 계량기만 0 으로 되돌린다**(진화의 이월과 다르다) — 경험치(`exp`)는 건드리지
            // 않는다. 알 진행분이 애초에 알 임계에서 멈추므로 버릴 초과분이 없고, 이 한 줄이
            // "받기 전에는 다음 알을 쌓을 수 없다"를 보장한다.
            s.box[i].eggProgress = 0
        }
        return egg
    }
}
