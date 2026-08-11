import Foundation

/// 확정 알 교환권 — 지급과 사용.
///
/// **자동으로 지급되지 않는다.** 진화와 같은 방식으로 배지가 뜨고 사용자가 누를 때 지급된다.
/// 이유는 두 가지다. ① 최종형인지 아는 데 `EvoLine` 이 필요한데 그건 네트워크로 오고 UI 가
/// 비동기로 싣는다 — 사용량 갱신 경로(`update`)에는 라인이 없어 판정 자체가 불가능하다. 거기서
/// 판정하려면 "최종형인가"를 세이브에 캐시해야 하는데, 그건 네트워크에서 파생된 값을 영속 상태에
/// 굳히는 일이라 라인 데이터가 바뀌면 조용히 틀어진다. ② 같은 자리에서 같은 경험치를 쓰는 일이
/// 진화는 클릭, 교환권은 자동으로 갈리면 안 된다.
///
/// **기다린다고 손해 보지 않는다** — 경험치는 계속 쌓이고 지급은 `exp -= 임계` 이므로,
/// 한 주 만에 열어도 쌓인 만큼 연속으로 받는다.
extension PlayerStore {
    /// 이 개체가 교환권을 받을 수 있나. 최종형 판정에 라인이 필요하다.
    func canClaimEggVoucher(_ individual: Individual, line: EvoLine) -> Bool {
        // 정체를 숨기고 있는 개체는 제외한다 — 받은 라인은 **겉모습의 것**이라 후보 판정이
        // 성립하지 않고, 교환권에 적히는 종 이름이 정체를 흘린다.
        // (`IndividualDetailView.choices` 가 진화에 대해 같은 판단을 한다.)
        guard individual.disguisedAs == nil else { return false }
        guard evolutionChoices(individual, line: line).isEmpty else { return false }
        return individual.exp >= EggVoucher.threshold(grade: individual.grade)
    }

    /// 교환권 지급. 경험치를 임계만큼 깎고 한 장을 더한다. 조건을 못 채우면 아무것도 하지 않고 false.
    @discardableResult
    func claimEggVoucher(individualID: UUID, line: EvoLine) -> Bool {
        guard let index = state.box.firstIndex(where: { $0.id == individualID }) else { return false }
        let individual = state.box[index]
        guard canClaimEggVoucher(individual, line: line) else { return false }
        mutate { state in
            // 초과분은 남긴다 — 진화와 같은 이월이다. 통째로 0 으로 만들면 오래 비워 둔
            // 사용자가 쌓아 둔 경험치를 한 장 값에 전부 잃는다.
            state.box[index].exp -= EggVoucher.threshold(grade: individual.grade)
            state.eggVouchers.append(EggVoucher(baseID: individual.baseID,
                                                grade: individual.grade))
        }
        return true
    }

    /// 교환권으로 알을 건다. 빈 슬롯이 없거나 그 종의 교환권이 없으면 nil — **이때 차감도 없다.**
    /// 같은 종이 여러 장이면 한 장만 없앤다.
    @discardableResult
    func redeemEggVoucher(baseID: Int) -> Egg? {
        guard let voucher = state.eggVouchers.first(where: { $0.baseID == baseID }) else { return nil }
        // 종은 확정이지만 이로치는 평소 확률로 굴린다 — 확정으로 만들면 이로치 부적이 무의미해진다.
        let shiny = EggBalance.rollShiny(nextRandomUnit(), hasCharm: state.ownsShinyCharm)
        // 알을 먼저 세운다. 슬롯이 없어 실패하면 교환권을 안 쓴 채로 돌아간다.
        guard let egg = placeEgg(grade: voucher.grade, speciesID: voucher.baseID, shiny: shiny)
        else { return nil }
        // 인덱스는 `placeEgg`(state 변형 + save) 가 끝난 **뒤에 다시 찾는다** — 미리 잡아 두면
        // 그 사이 바뀐 배열에 옛 인덱스로 지우는 꼴이 된다. 같은 종이 여러 장이면 한 장만.
        mutate { s in
            if let index = s.eggVouchers.firstIndex(where: { $0.baseID == baseID }) {
                s.eggVouchers.remove(at: index)
            }
        }
        return egg
    }
}
