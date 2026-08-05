import Foundation

/// 시간 부화. 알은 토큰이 아니라 실시간으로 깨지므로, 앱이 꺼져 있던 동안의 경과를
/// 실행 시점에 한 번에 정산한다.
extension PlayerStore {
    func readyEggCount(at now: Date) -> Int {
        state.eggs.count { $0.isReady(at: now) }
    }

    /// 시각이 지난 알을 전부 부화시킨다. 부화한 개체들을 돌려주고(알림·연출용) 슬롯을 비운다.
    /// 여러 번 불려도 같은 알을 두 번 부화시키지 않는다 — 부화한 알은 목록에서 사라진다.
    @discardableResult
    func settleHatches(at now: Date) -> [Individual] {
        let ripe = state.eggs.filter { $0.isReady(at: now) }
        guard !ripe.isEmpty else { return [] }
        let natures = PokemonNature.allCases
        var hatched: [Individual] = []
        for egg in ripe {
            let nature = natures[Int(nextRandomUnit() * Double(natures.count)) % natures.count]
            hatched.append(Individual(baseID: egg.speciesID, speciesID: egg.speciesID,
                                      pathIDs: [egg.speciesID], shiny: egg.shiny,
                                      nature: nature, exp: 0, obtainedAt: now, grade: egg.grade))
        }
        let hatchedIDs = Set(ripe.map(\.id))
        mutate {
            $0.box.append(contentsOf: hatched)
            for individual in hatched { $0.dex.insert(individual.speciesID) }
            $0.eggs.removeAll { hatchedIDs.contains($0.id) }
        }
        return hatched
    }
}
