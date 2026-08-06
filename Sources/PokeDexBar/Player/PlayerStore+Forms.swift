import Foundation

/// 메가진화·거다이맥스 — 상점에서 산 메가스톤/다이맥스 버섯을 개체에 써서 겉모습을 바꾼다.
/// 종이 바뀌는 게 아니라서 도감에는 아무 일도 일어나지 않고, 진화 단계·경험치도 그대로다.
extension PlayerStore {
    /// 이 개체에 쓸 수 있는 폼들. 이미 그 폼이면 후보에서 빠진다(아이템 낭비 방지).
    func formChoices(_ individual: Individual, kind: FormKind) -> [PokemonForm] {
        FormCatalog.forms(speciesID: individual.speciesID, kind: kind)
            .filter { $0.slug != individual.form }
    }

    /// 폼을 바꿀 수 있나 — 후보가 있고 해당 아이템도 있어야 한다.
    func canChangeForm(_ individual: Individual, kind: FormKind) -> Bool {
        count(of: kind.item) > 0 && !formChoices(individual, kind: kind).isEmpty
    }

    /// 아이템을 써서 폼을 바꾼다. 후보가 아니거나 아이템이 없으면 아무것도 건드리지 않고 false.
    /// 슬러그를 그대로 받지 않고 카탈로그에서 검증한다 — 스프라이트가 없는 폼을 저장하면
    /// 그림이 안 나오는 개체가 세이브에 영구히 남는다.
    @discardableResult
    func changeForm(individualID: UUID, to form: PokemonForm) -> Bool {
        guard let index = state.box.firstIndex(where: { $0.id == individualID }) else { return false }
        let individual = state.box[index]
        guard FormCatalog.form(slug: form.slug) != nil,
              formChoices(individual, kind: form.kind).contains(form),
              count(of: form.kind.item) > 0 else { return false }
        mutate {
            $0.box[index].form = form.slug
            Self.consume(form.kind.item, in: &$0)
        }
        return true
    }

    /// 원래 모습으로 되돌린다 — 공짜다. 아이템을 또 받으면 X/Y 를 잘못 고른 게 영영 굳는다.
    /// 다시 폼을 잡으려면 아이템이 또 든다.
    @discardableResult
    func revertForm(individualID: UUID) -> Bool {
        guard let index = state.box.firstIndex(where: { $0.id == individualID }),
              state.box[index].form != nil else { return false }
        mutate { $0.box[index].form = nil }
        return true
    }
}
