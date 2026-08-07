import Foundation

/// 폼 — 같은 개체의 겉모습을 바꾼다. 종이 바뀌는 게 아니라서 도감에는 아무 일도 일어나지 않고,
/// 진화 단계·경험치도 그대로다. **진화와 달리 언제든 되돌릴 수 있다**(`revertForm`).
///
/// 도구는 두 갈래다(`FormSource`): 메가스톤·다이맥스 버섯은 상점에서 사고 쓰면 없어지지만,
/// 나머지는 리본 파트너가 물어 오고 **없어지지 않는다** — 되돌릴 수 있는 변화를 소모품으로
/// 잠그면 한 번 잘못 고른 게 영영 굳는다.
extension PlayerStore {
    /// 이 개체가 그 갈래의 폼을 가질 수 있나. **지방 모습에는 메가·거다이맥스가 없다** —
    /// 메가는 칼로스, 거다이맥스는 가라르 지방의 현상이고 둘 다 원종에만 붙는다.
    /// 나옹이 대표적이다: 거다이맥스 나옹은 관동 나옹이고, 가라르 나옹은 거다이맥스하지 못한다.
    func hasForms(_ individual: Individual, kind: FormKind) -> Bool {
        individual.region == nil && FormCatalog.has(speciesID: individual.speciesID, kind: kind)
    }

    /// 이 개체에 쓸 수 있는 폼들. 이미 그 폼이면 후보에서 빠진다(헛수고 방지).
    /// 합체 폼은 상대가 박스에 없으면 **후보에는 남기되** 못 누르게 한다 — 목록에서 아예 빼면
    /// 큐레무 블랙이 이 게임에 있다는 사실 자체를 알 수 없다.
    func formChoices(_ individual: Individual, kind: FormKind) -> [PokemonForm] {
        guard hasForms(individual, kind: kind) else { return [] }
        return FormCatalog.forms(speciesID: individual.speciesID, kind: kind)
            .filter { $0.slug != individual.form }
    }

    /// 그 폼을 여는 도구를 갖고 있나.
    func hasItem(for form: PokemonForm) -> Bool {
        switch form.source {
        case .shop(let item): count(of: item) > 0
        case .foraged(let item): count(of: item) > 0
        }
    }

    /// 합체 상대가 박스에 있나. 합체 폼이 아니면 항상 참.
    /// **상대를 소모하지 않는다** — 폼은 되돌릴 수 있는데 상대를 먹어 버리면 되돌릴 수가 없다.
    func hasFusionPartner(for form: PokemonForm) -> Bool {
        guard let partner = form.fusionPartner else { return true }
        return state.box.contains { $0.speciesID == partner }
    }

    /// 지금 이 폼으로 바꿀 수 있나 — 도구도 있고 합체 상대도 갖췄나.
    func canChange(_ individual: Individual, to form: PokemonForm) -> Bool {
        formChoices(individual, kind: form.kind).contains(form)
            && hasItem(for: form) && hasFusionPartner(for: form)
    }

    /// 이 갈래에서 바꿀 수 있는 폼이 하나라도 있나 — 상세 화면이 버튼을 낼지 판단한다.
    func canChangeForm(_ individual: Individual, kind: FormKind) -> Bool {
        formChoices(individual, kind: kind).contains { canChange(individual, to: $0) }
    }

    /// 도구를 써서 폼을 바꾼다. 조건을 못 채웠으면 아무것도 건드리지 않고 false.
    /// 슬러그를 그대로 받지 않고 카탈로그에서 검증한다 — 스프라이트가 없는 폼을 저장하면
    /// 그림이 안 나오는 개체가 세이브에 영구히 남는다.
    @discardableResult
    func changeForm(individualID: UUID, to form: PokemonForm) -> Bool {
        guard let index = state.box.firstIndex(where: { $0.id == individualID }) else { return false }
        guard FormCatalog.form(slug: form.slug) != nil,
              canChange(state.box[index], to: form) else { return false }
        mutate {
            $0.box[index].form = form.slug
            // 상점에서 산 것만 없어진다. 물어 온 도구는 남아서 다시 이 폼으로 돌아올 수 있다.
            if case .shop(let item) = form.source { Self.consume(item, in: &$0) }
        }
        return true
    }

    /// 원래 모습으로 되돌린다 — 공짜다. **폼의 핵심이 여기 있다**: 진화는 못 되돌리지만
    /// 폼은 겉모습이라 언제든 되돌아온다.
    @discardableResult
    func revertForm(individualID: UUID) -> Bool {
        guard let index = state.box.firstIndex(where: { $0.id == individualID }),
              state.box[index].form != nil else { return false }
        mutate { $0.box[index].form = nil }
        return true
    }
}

/// 리본 파트너가 **지금 무엇을 찾고 있나**. 화면이 이걸 말해 줘야 리본이 사탕 공장으로만
/// 읽히지 않는다 — 채집은 사탕이 나올 때 함께 굴러가는데, 그 사실이 어디에도 안 적혀 있었다.
extension PlayerStore {
    /// 이 개체가 아직 안 가진, 자기가 쓸 수 있는 도구들의 이름. 다 모았으면 빈 배열.
    /// 진화 도구가 먼저 오고 폼 도구가 뒤에 온다 — 진화가 이 게임의 기본 동작이라 급하다.
    func forageTargets(_ individual: Individual) -> [String] {
        let evolution = ForageCatalog.needs(speciesID: individual.speciesID,
                                            region: individual.region)
            .filter { count(of: $0) == 0 }
            .map { $0.label(language) }
        let forms = FormForageCatalog.items(speciesID: individual.speciesID,
                                            region: individual.region)
            .map(\.item)
            .filter { count(of: $0) == 0 }
            .map { $0.label(language) }
        return evolution + forms
    }
}
