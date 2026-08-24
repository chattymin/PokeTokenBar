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

    /// 이 미션을 지금 받을 수 있나 — 달성했고 아직 안 받았으면 된다. **보상이 전부
    /// 아이템(확정권·사탕·부적)이라 다른 조건이 없다** — 알을 직접 주던 판에는 빈 부화
    /// 슬롯 요구가 여기 붙어 있었는데, 그게 "받기가 왜 안 되지" 를 만들었다(사용자 지적).
    func canClaimDexMission(_ mission: DexMission) -> Bool {
        !state.claimedDexMissions.contains(mission.id)
            && DexMissions.achieved(mission, dex: state.dex)
    }

    /// 받는다 — 보상이 전부 아이템이라 가방에 담고 끝이다. 알 확정권은 상점의 알 뽑기
    /// 자리에서 쓴다(`redeemEggTicket`).
    @discardableResult
    func claimDexMission(_ mission: DexMission) -> Bool {
        guard canClaimDexMission(mission) else { return false }
        mutate { s in
            for reward in mission.rewards {
                switch reward {
                case .eggTicket(let grade):
                    if let ticket = ShopItem.eggTicket(for: grade) {
                        s.inventory[ticket.rawValue, default: 0] += 1
                    }
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
        return true
    }

    /// 확정권으로 알을 뽑는다 — **무료이고 등급이 확정**이라는 점만 다르고, 나머지(빈 슬롯
    /// 요구·이로치 굴림·부화 감면)는 일반 뽑기와 같다. 종 선택은 뷰가 인덱스에서 해 온다
    /// (상점 뽑기와 같은 흐름 — 후보가 네트워크에 산다).
    ///
    /// 확정권 차감과 알 놓기가 한 함수에 있다 — 갈라 두면 "권은 줄었는데 알이 없다" 나
    /// 그 반대가 생길 수 있다.
    @discardableResult
    func redeemEggTicket(grade: Grade, speciesID: Int,
                         growthRate: GrowthRate = .mediumFast) -> Egg? {
        guard let ticket = ShopItem.eggTicket(for: grade), count(of: ticket) > 0 else { return nil }
        let shiny = EggBalance.rollShiny(nextRandomUnit(), denominator: shinyDenominator)
        guard let egg = placeEgg(grade: grade, speciesID: speciesID, shiny: shiny,
                                 growthRate: growthRate) else { return nil }
        mutate { s in
            s.inventory[ticket.rawValue, default: 0] -= 1
            if s.inventory[ticket.rawValue] ?? 0 <= 0 { s.inventory[ticket.rawValue] = nil }
        }
        return egg
    }
}
