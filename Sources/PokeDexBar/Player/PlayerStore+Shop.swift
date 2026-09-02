import Foundation

/// 상점 — 슬롯 확장과 아이템. 실패한 구매·사용은 재화도 아이템도 건드리지 않는다.
extension PlayerStore {
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
    /// 폼 도구 보유량. 키가 `form-` 으로 시작해 다른 품목과 안 겹친다(테스트가 확인한다).
    func count(of item: FormItem) -> Int { state.inventory[item.rawValue] ?? 0 }

    /// 이 보유형 부적을 갖고 있나 — **사다리 부적은 1단계라도 올렸으면 보유**다.
    func owns(_ item: ShopItem) -> Bool {
        if CharmLadder.isTiered(item) { return charmTier(item) >= 1 }
        // 무지개 부적은 상점이 아니라 도감 완성 미션에서 온다 — 보유 판정은 같은 자리에서.
        return item == .rainbowCharm ? state.ownsRainbowCharm : false
    }

    /// 다음 단계를 사는 값. 최고 단계에 닿았으면 nil(더 살 수 없다).
    func nextCharmPrice(_ item: ShopItem) -> Int? {
        guard CharmLadder.isTiered(item) else { return nil }
        return CharmLadder.price(tier: charmTier(item) + 1)
    }

    /// 지금 이 부적을 한 단계 더 올릴 수 있나 — 값이 있고 지갑이 닿으면.
    func canUpgradeCharm(_ item: ShopItem) -> Bool {
        guard let price = nextCharmPrice(item) else { return false }
        return state.wallet >= price
    }

    /// 부적을 한 단계 올린다. **`buy` 와 갈라 둔 이유**: 부적은 이제 값이 단계마다 달라서
    /// `item.price` 한 값으로는 표현이 안 된다. 소모품 구매는 예전 그대로다.
    @discardableResult
    func upgradeCharm(_ item: ShopItem) -> Bool {
        guard let price = nextCharmPrice(item), state.wallet >= price else { return false }
        mutate {
            $0.spentTokens += price
            $0.charmTiers[item.rawValue] = ($0.charmTiers[item.rawValue] ?? 0) + 1
        }
        return true
    }

    func buy(_ item: ShopItem) -> Bool {
        // 사다리 부적은 단계 구매로 간다 — 옛 호출부가 남아 있어도 값이 안 어긋난다.
        if CharmLadder.isTiered(item) { return upgradeCharm(item) }
        guard state.wallet >= item.price else { return false }
        if item.isCharm {
            guard !owns(item) else { return false }   // 보유형 — 두 번 사지 않는다
            mutate { $0.spentTokens += item.price }
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
        let multiplier = charmMultiplier(.expCharm)
        guard count(of: .expCandy) > 0,
              let index = state.box.firstIndex(where: { $0.id == individualID }) else { return false }
        // 사탕은 **경험치**를 준다(알은 안 건드린다) — 만렙 상한도 사용량 갱신과 같다.
        let cap = state.box[index].growthRate.totalExp(at: GrowthRate.maxLevel)
        // **만렙이면 줄 것이 없다 — 여기서 거부해야 한다.** 예전엔 그냥 소모했다. 그 근거였던
        // "초과분은 진화 때 다음 단계로 이월된다"가 지금은 사실이 아니다(`evolve` 는 경험치를
        // 그대로 둔다, 이월하지 않는다) — 만렙 개체에 쓴 사탕(약 1.5억 토큰어치)이 아무 효과
        // 없이 그대로 사라졌다.
        guard state.box[index].exp < cap else { return false }
        mutate {
            $0.box[index].exp = min(cap, $0.box[index].exp
                                    + PlayerStore.expGain(ExpBalance.candyExp,
                                                          multiplier: multiplier))
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
