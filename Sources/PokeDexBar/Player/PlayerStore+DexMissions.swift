import Foundation

/// 도감 미션 — 진행 판정과 수령.
extension PlayerStore {
    struct DexMissionStatus: Identifiable, Equatable {
        let mission: DexMission
        let done: Int
        let target: Int
        let claimed: Bool
        var id: String { mission.id }
        /// 달성했고 아직 안 받았다 — 화면이 "받기" 버튼을 이걸로 낸다.
        var claimable: Bool { !claimed && done >= target }
    }

    /// 전체 미션의 현재 상태. 순서는 카탈로그 그대로다.
    func dexMissionStatuses() -> [DexMissionStatus] {
        let dex = state.dex
        return DexMissions.all.map { mission in
            let progress = DexMissions.progress(of: mission, dex: dex)
            return DexMissionStatus(mission: mission, done: progress.done,
                                    target: progress.target,
                                    claimed: state.claimedDexMissions.contains(mission.id))
        }
    }

    /// 이 미션을 지금 받을 수 있나 — 달성·미수령에 더해, 알 보상이면 빈 슬롯도 본다.
    /// 화면이 버튼 활성을 이 판정으로 정한다(조건을 화면이 따로 적으면 스토어와 갈린다).
    func canClaimDexMission(_ mission: DexMission) -> Bool {
        guard !state.claimedDexMissions.contains(mission.id) else { return false }
        guard DexMissions.achieved(mission, dex: state.dex) else { return false }
        return freeSlots >= DexMissions.eggCount(in: mission.rewards)
    }

    /// 받는다. 알 보상은 종이 필요하므로 **뷰가 인덱스에서 골라 넘긴다**(상점 뽑기와 같은
    /// 흐름 — 후보가 네트워크에 살기 때문이다). 알 수만큼 안 넘어오면 실패다.
    ///
    /// 이로치는 여기서 굴린다 — 부적 상태(`shinyDenominator`)를 받는 건 뽑기·발견 알과 같고,
    /// **미션 알이라고 더 잘 나오지 않는다.**
    ///
    /// **놓인 알들을 돌려준다**(실패면 nil, 아이템만 있는 미션이면 빈 배열) — 화면이 상점
    /// 뽑기와 같은 연출(`EggRevealView`)을 띄우려면 굴려 나온 등급·이로치를 알아야 한다.
    /// 안 돌려주면 "받기를 눌렀는데 알이 실제로 받아졌는지 모르겠다" 가 된다(사용자 지적).
    @discardableResult
    func claimDexMission(_ mission: DexMission,
                         eggSpecies: [(speciesID: Int, growthRate: GrowthRate)] = []) -> [Egg]? {
        guard canClaimDexMission(mission) else { return nil }
        guard eggSpecies.count == DexMissions.eggCount(in: mission.rewards) else { return nil }

        var eggQueue = eggSpecies
        var placed: [Egg] = []
        for reward in mission.rewards {
            guard case .egg(let grade) = reward, let pick = eggQueue.first else { continue }
            eggQueue.removeFirst()
            let shiny = EggBalance.rollShiny(nextRandomUnit(), denominator: shinyDenominator)
            // `canClaim` 이 빈 슬롯을 확인했고 여기는 MainActor 라 그 사이에 찰 수 없다.
            if let egg = placeEgg(grade: grade, speciesID: pick.speciesID, shiny: shiny,
                                  growthRate: pick.growthRate) {
                placed.append(egg)
            }
        }
        mutate { s in
            for reward in mission.rewards {
                switch reward {
                case .egg: break   // 위에서 놓았다
                case .expCandy(let n):
                    s.inventory[ShopItem.expCandy.rawValue, default: 0] += n
                case .shinyCandy(let n):
                    s.inventory[ShopItem.shinyCandy.rawValue, default: 0] += n
                case .rainbowCharm:
                    s.ownsRainbowCharm = true
                }
            }
            s.claimedDexMissions.insert(mission.id)
        }
        return placed
    }
}
