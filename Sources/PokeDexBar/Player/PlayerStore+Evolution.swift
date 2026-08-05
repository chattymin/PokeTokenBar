import Foundation

/// 진화 — 임계 판정과 실행. **자동으로 일어나지 않는다.** 임계에 닿으면 UI 가 배지를 띄우고,
/// 사용자가 누를 때 `evolve` 가 불린다(미루기·분기 선택이 가능해야 하기 때문).
extension PlayerStore {
    /// 다음 단계로 갈 경험치가 찼나. 최종형인지까지는 여기서 모른다 — 그건 라인이 필요하다.
    func canEvolve(_ individual: Individual) -> Bool {
        individual.exp >= ExpBalance.threshold(grade: individual.grade,
                                               stageIndex: individual.stageIndex)
    }

    /// 지금 형태에서 갈 수 있는 다음 종들. 최종형이면 빈 배열.
    func evolutionChoices(_ individual: Individual, line: EvoLine) -> [Int] {
        guard let node = line.tree.node(withID: individual.speciesID) else { return [] }
        return node.children.map(\.speciesID)
    }

    /// 진화 실행. 경험치가 모자라거나 트리에서 갈 수 없는 종이면 아무것도 하지 않고 false.
    @discardableResult
    func evolve(individualID: UUID, to speciesID: Int, line: EvoLine) -> Bool {
        guard let index = state.box.firstIndex(where: { $0.id == individualID }) else { return false }
        let individual = state.box[index]
        guard canEvolve(individual),
              evolutionChoices(individual, line: line).contains(speciesID) else { return false }
        let threshold = ExpBalance.threshold(grade: individual.grade,
                                             stageIndex: individual.stageIndex)
        state.box[index].speciesID = speciesID
        state.box[index].pathIDs.append(speciesID)
        state.box[index].exp = individual.exp - threshold   // 초과분 이월
        state.dex.insert(speciesID)
        save()
        return true
    }
}
