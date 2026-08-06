import Foundation

/// 상점 — 슬롯 확장과 아이템. 실패한 구매·사용은 재화도 아이템도 건드리지 않는다.
extension PlayerStore {
    static let expCandyAmount = 100_000_000

    // MARK: 슬롯

    /// 다음 슬롯을 산다. 상한이거나 재화가 모자라면 false.
    func buySlot() -> Bool {
        let next = state.slots + 1
        guard let price = EggBalance.slotPrice(forSlotNumber: next),
              state.wallet >= price else { return false }
        mutate {
            $0.spentTokens += price
            $0.slots = next
        }
        return true
    }

    /// 다음 슬롯 가격(화면 표시용). 상한이면 nil.
    var nextSlotPrice: Int? { EggBalance.slotPrice(forSlotNumber: state.slots + 1) }

    // MARK: 구매

    func count(of item: ShopItem) -> Int { state.inventory[item.rawValue] ?? 0 }
    /// 진화 도구 보유량. 상점 품목과 같은 인벤토리를 쓴다 — 키가 겹치지 않고,
    /// 저장 형식이 하나면 관대 디코딩·검증도 한 번만 하면 된다.
    func count(of item: EvolutionItem) -> Int { state.inventory[item.rawValue] ?? 0 }

    /// 진화 도구를 산다. 상점에서 파는 것만 살 수 있다 — 특수 도구는 리본 파트너가 물어 온다.
    func buy(_ item: EvolutionItem) -> Bool {
        guard item.isSold, state.wallet >= item.price else { return false }
        mutate {
            $0.spentTokens += item.price
            $0.inventory[item.rawValue, default: 0] += 1
        }
        return true
    }

    /// 진화 도구 1개 소모. `mutate` 블록 안에서 불리므로 상태를 인자로 받는다.
    static func consume(_ item: EvolutionItem, in state: inout PlayerState) {
        let left = (state.inventory[item.rawValue] ?? 0) - 1
        if left > 0 { state.inventory[item.rawValue] = left }
        else { state.inventory.removeValue(forKey: item.rawValue) }
    }

    /// 이 보유형 부적을 이미 갖고 있나.
    func owns(_ item: ShopItem) -> Bool {
        switch item {
        case .shinyCharm: state.ownsShinyCharm
        case .expCharm: state.ownsExpCharm
        case .fortuneCharm: state.ownsFortuneCharm
        default: false
        }
    }

    func buy(_ item: ShopItem) -> Bool {
        guard state.wallet >= item.price else { return false }
        if item.isCharm {
            guard !owns(item) else { return false }   // 보유형 — 두 번 사지 않는다
            mutate {
                $0.spentTokens += item.price
                switch item {
                case .shinyCharm: $0.ownsShinyCharm = true
                case .expCharm: $0.ownsExpCharm = true
                case .fortuneCharm: $0.ownsFortuneCharm = true
                default: break
                }
            }
            return true
        }
        mutate {
            $0.spentTokens += item.price
            $0.inventory[item.rawValue, default: 0] += 1
        }
        return true
    }

    // MARK: 사용

    func useExpCandy(on individualID: UUID) -> Bool {
        guard count(of: .expCandy) > 0,
              let index = state.box.firstIndex(where: { $0.id == individualID }) else { return false }
        mutate {
            $0.box[index].exp += PlayerStore.expGain(Self.expCandyAmount, charm: $0.ownsExpCharm)
            Self.consume(.expCandy, in: &$0)
        }
        return true
    }

    func useShinyCandy(on individualID: UUID) -> Bool {
        guard count(of: .shinyCandy) > 0,
              let index = state.box.firstIndex(where: { $0.id == individualID }),
              !state.box[index].shiny else { return false }   // 이미 이로치면 낭비하지 않는다
        mutate {
            $0.box[index].shiny = true
            Self.consume(.shinyCandy, in: &$0)
        }
        return true
    }

    /// 아이템 1개 소모. `mutate` 블록 안에서 불리므로 상태를 인자로 받는다.
    static func consume(_ item: ShopItem, in state: inout PlayerState) {
        let left = (state.inventory[item.rawValue] ?? 0) - 1
        if left > 0 { state.inventory[item.rawValue] = left }
        else { state.inventory.removeValue(forKey: item.rawValue) }
    }
}
