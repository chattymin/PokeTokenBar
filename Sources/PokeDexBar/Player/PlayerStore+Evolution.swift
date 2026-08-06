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
        // PokéAPI 체인은 지방 갈래를 한꺼번에 돌려준다(`meowth → persian | perrserker`) —
        // 개체의 지방으로 좁히지 않으면 관동 나옹도 나이킹이 된다.
        return RegionBalance.allowedChoices(node.children.map(\.speciesID),
                                            speciesID: individual.speciesID,
                                            region: individual.region)
    }

    /// 이 갈래를 지나려면 무엇이 필요한가. 트리에 없는 종이면 조건 없음으로 본다.
    func requirement(for speciesID: Int, line: EvoLine) -> EvoRequirement {
        line.tree.node(withID: speciesID)?.requirement ?? .none
    }

    /// 그 조건을 지금 만족하는가. 도구는 **갖고 있으면** 되고(쓰는 건 진화 실행 때),
    /// 친밀도는 그 개체와 함께한 시간으로 판단한다.
    func meetsRequirement(_ requirement: EvoRequirement, for individual: Individual) -> Bool {
        switch requirement {
        case .none: true
        case .item(let item): count(of: item) > 0
        case .friendship:
            individual.partnerDuration(at: currentDate()) >= EvoRequirement.friendshipSeconds
        }
    }

    /// 진화 실행. 경험치가 모자라거나 트리에서 갈 수 없는 종이거나 조건을 못 채웠으면
    /// 아무것도 하지 않고 false — 도구도 소모하지 않는다.
    @discardableResult
    func evolve(individualID: UUID, to speciesID: Int, line: EvoLine) -> Bool {
        guard let index = state.box.firstIndex(where: { $0.id == individualID }) else { return false }
        let individual = state.box[index]
        let need = requirement(for: speciesID, line: line)
        guard canEvolve(individual),
              evolutionChoices(individual, line: line).contains(speciesID),
              meetsRequirement(need, for: individual) else { return false }
        let threshold = ExpBalance.threshold(grade: individual.grade,
                                             stageIndex: individual.stageIndex)
        mutate { state in
            state.box[index].speciesID = speciesID
            state.box[index].pathIDs.append(speciesID)
            state.box[index].exp = individual.exp - threshold   // 초과분 이월
            // 폼은 종에 달린 것이라 진화하면 풀린다 — 피카츄의 거다이맥스를 라이츄가 이어받을 수 없다.
            state.box[index].form = nil
            state.dex.insert(speciesID)
            // 도구는 여기서 소모한다 — 실패한 진화가 도구를 먹으면 안 되므로 검증 뒤에 온다.
            if case .item(let item) = need { Self.consume(item, in: &state) }
        }
        return true
    }
}
