import Foundation

/// 시간 부화. 알은 토큰이 아니라 실시간으로 깨지므로, 앱이 꺼져 있던 동안의 경과도 그대로 반영된다.
///
/// **익었다고 저절로 박스로 들어가지 않는다.** 부화 시각이 지난 알은 슬롯에 남아 "확인"을 기다리고,
/// 사용자가 눌러야 개체가 되어 박스·도감에 들어가고 슬롯이 빈다 — 무엇이 나왔는지 못 보고 지나가는
/// 일이 없게 하려는 것이다. 그래서 여기서 하는 일은 둘로 나뉜다: 익은 걸 **알리는 것**(자동)과
/// 개체로 **거두는 것**(사용자 동작).
extension PlayerStore {
    func readyEggCount(at now: Date) -> Int {
        state.eggs.count { $0.isReady(at: now) }
    }

    /// 아직 안 알린 익은 알들. 알린 표시를 남기고 그 알들을 돌려준다 — 익은 알이 슬롯에 계속
    /// 남으므로 이 표시가 없으면 매 틱마다 같은 알을 다시 알리게 된다.
    @discardableResult
    func announceReadyEggs(at now: Date) -> [Egg] {
        let fresh = state.eggs.filter { $0.isReady(at: now) && !$0.announced }
        guard !fresh.isEmpty else { return [] }
        let ids = Set(fresh.map(\.id))
        mutate { state in
            for index in state.eggs.indices where ids.contains(state.eggs[index].id) {
                state.eggs[index].announced = true
            }
        }
        return fresh
    }

    /// 알리고, 알릴 게 있었으면 알림을 보낸다. 호출 지점이 셋(사용량 틱·팝오버 열기·카운트다운 틱)이라
    /// "한 번 익음 = 한 번 알림" 규칙이 지점마다 갈라지지 않게 여기 한 곳에 묶는다.
    @discardableResult
    func announceReadyEggsAndNotify(at now: Date) -> [Egg] {
        let fresh = announceReadyEggs(at: now)
        HatchNotifier().notify(hatched: fresh, language: language)
        return fresh
    }

    /// 익은 알 하나를 거둔다 — 개체를 만들어 박스·도감에 넣고 슬롯을 비운다.
    /// 아직 안 익었거나 없는 알이면 아무것도 하지 않는다.
    @discardableResult
    func claimHatch(eggID: UUID, at now: Date) -> Individual? {
        guard let egg = state.eggs.first(where: { $0.id == eggID }), egg.isReady(at: now) else {
            return nil
        }
        let individual = makeHatchling(from: egg, at: now)
        mutate { state in
            state.box.append(individual)
            // **위장 중이면 도감에 안 넣는다.** 넣으면 정체(메타몽)가 도감에서 먼저 새고,
            // 위장한 종(뮤)을 넣으면 잡지도 않은 종이 도감에 남는다. 정체가 드러날 때 등록한다.
            if individual.disguisedAs == nil { state.dex.insert(individual.speciesID) }
            state.eggs.removeAll { $0.id == eggID }
        }
        return individual
    }

    /// 익은 알을 전부 거둔다(여러 개가 한꺼번에 익었을 때).
    @discardableResult
    func claimAllReady(at now: Date) -> [Individual] {
        state.eggs.filter { $0.isReady(at: now) }
            .compactMap { claimHatch(eggID: $0.id, at: now) }
    }

    /// 알 → 개체. 성격과 지방은 **거두는 시점에** 굴린다 — 알에 미리 넣어 두면 세이브에
    /// 결과가 노출되고, 확인 전에 무엇인지 알 수 있게 된다.
    private func makeHatchling(from egg: Egg, at now: Date) -> Individual {
        let natures = PokemonNature.allCases
        let nature = natures[Int(nextRandomUnit() * Double(natures.count)) % natures.count]
        // 지방 모습은 태어날 때 정해져 평생 간다 — 굴림은 종에 지방 모습이 있을 때만 의미가 있다.
        let rolled = RegionBalance.rollRegion(speciesID: egg.speciesID,
                                              roll: nextRandomUnit(), pick: nextRandomUnit())
        var individual = Individual(baseID: egg.speciesID, speciesID: egg.speciesID,
                                    pathIDs: [egg.speciesID], shiny: egg.shiny,
                                    nature: nature, exp: 0, obtainedAt: now, grade: egg.grade)
        individual.region = rolled?.0
        individual.regionVariant = rolled?.1
        // 메타몽은 뮤의 모습을 하고 나온다. 위장은 **거두는 시점에** 붙인다 — 성격·지방과 같은
        // 이유로, 알에 미리 넣어 두면 확인을 누르기 전에 세이브에 정체가 노출된다.
        if egg.speciesID == DittoDisguise.speciesID { individual.disguisedAs = DittoDisguise.disguisedAs }
        return individual
    }
}
