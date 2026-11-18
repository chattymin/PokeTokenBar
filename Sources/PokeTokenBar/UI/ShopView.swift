import SwiftUI

/// 상점 — 사용한 토큰(재화 = usedSinceInstall − spentTokens)으로 아이템 구매(이상한 사탕·민트).
/// 인라인 확인(버튼 morph) — .sheet/.alert 금지(BagView 주석과 동일: transient 팝오버가 닫힐 때
/// 고아 시트가 이후 클릭을 먹통내는 결함 회피).
@MainActor
struct ShopView: View {
    let store: CompanionStore
    let nav: PopoverNavigation

    var body: some View {
        // The products' tab (#183): the eggs at first, as the Shop always opened on them, then the last one shown.
        let tabs = store.shopTabs
        let current = tabs.contains { $0.tab == nav.shopTab } ? nav.shopTab : (tabs.first?.tab ?? .eggs)
        // 고정 높이 — 컬렉션/가방과 동일(팝오버 재오픈 시 fitting size 축소 방지).
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                walletHeader(store.l)
                // Prof. Oak's advice and, some days, the travelling merchant (2026-11-09).
                ShopHeadCards(store: store, nav: nav)
                // The products in tabs under the cards (#183), the switch the Pokédex and its log use: one tab's
                // sections at a time instead of the page of all of them. A bought egg goes in the Bag (`EggCard`).
                if tabs.count > 1 {
                    PillPicker(selection: Binding(get: { current }, set: { nav.shopTab = $0 }),
                               options: tabs.map { ($0.tab, store.l.shopTab($0.tab)) })
                }
                ForEach(tabs.first { $0.tab == current }?.sections ?? [], id: \.section) { group in
                    if current.namesItsSections {
                        SectionTitle(text: store.l.shopSection(group.section))
                            .padding(.top, 4)
                    }
                    ForEach(group.entries, id: \.self) { entry in
                        switch entry {
                        case .item(let kind):
                            ShopItemCard(store: store, kind: kind)
                        case .egg(let tier):
                            EggCard(store: store, tier: tier)
                        }
                    }
                }
            }
            .reservesScrollerLane()
        }
        .frame(height: 520)
        .task { await store.loadHatchIndex() }
    }

    /// The balance first and large, on one line: Prof. Oak's card below spends it.
    private func walletHeader(_ l: L) -> some View {
        HStack(alignment: .center, spacing: 8) {
            SectionTitle(text: l.spendableTokens, systemImage: "creditcard.fill")
            Spacer(minLength: 8)
            Text(TokenFormatter.compact(store.availableTokens))
                .font(.system(size: 22, weight: .bold, design: .rounded)).monospacedDigit()
        }
        .heroCard(colors: store.themeColors)
    }
}

/// 상점 아이템 1장 — 아이콘·이름·설명(사탕 XP / 민트 "성격 랜덤 변경")·보유수 + 가격/구매(인라인 확인).
/// kind 별 store.canBuy(kind)/buy(kind:count:) 로 일반화 — 판매 목록은 store.purchasableItems.
/// 소모품은 수량 Stepper(가방의 사탕 일괄 사용과 같은 패턴)로 잔액 한도까지 한 번에 산다.
@MainActor
private struct ShopItemCard: View {
    let store: CompanionStore
    let kind: ItemKind
    @State private var confirming = false
    @State private var failed = false
    @State private var quantity = 1

    private var price: Int { store.price(of: kind) ?? 0 }
    private var maxQuantity: Int { max(1, store.maxBuyCount(kind)) }
    /// 잔액이 줄어 한도가 내려가도 선택값이 한도를 넘지 않게 클램프.
    private var selectedQuantity: Int { min(quantity, maxQuantity) }
    /// 보유형은 1회 구매라 수량 선택이 없다. 2개 이상 살 수 있을 때만 Stepper 노출.
    private var showsQuantity: Bool { !kind.isPassive && store.maxBuyCount(kind) > 1 }

    var body: some View {
        let l = store.l
        VStack(alignment: .leading, spacing: Design.productCardSpacing) {
            HStack(alignment: .top, spacing: 10) {
                ItemIconView(kind: kind, size: 30)
                VStack(alignment: .leading, spacing: Design.productTextSpacing) {
                    HStack(spacing: 6) {
                        Text(l.itemName(kind)).font(.callout.weight(.semibold))
                        let owned = store.itemCount(kind)
                        if owned > 0 && !kind.isPassive {
                            Text(l.ownedCount(owned)).font(.caption2.weight(.bold))
                                .foregroundStyle(.secondary).monospacedDigit()
                        }
                        Spacer(minLength: 4)
                        if showsQuantity {
                            Stepper(value: $quantity, in: 1...maxQuantity) {
                                Text("×\(selectedQuantity)").font(.callout.weight(.semibold)).monospacedDigit()
                            }
                            .fixedSize()
                            .accessibilityLabel(l.itemName(kind))
                            .accessibilityValue("\(selectedQuantity)")
                        }
                    }
                    Text(l.itemDescription(kind, rareCandyXP: store.rareCandyXP))
                        .font(.caption).foregroundStyle(.secondary)
                        .lineSpacing(Design.productLineSpacing)
                        .fixedSize(horizontal: false, vertical: true)
                    if kind == .shinyCharm, store.itemCount(kind) == 0 {
                        let odds = store.shinyCharmOdds
                        Text(l.shinyOddsChange(from: odds.now, to: odds.withCharm))
                            .font(.caption.weight(.semibold)).monospacedDigit()
                    }
                }
                // 바깥 Spacer 없음 — 이름 줄의 Spacer 가 남는 폭을 전부 받아 Stepper 를 카드 오른쪽 끝에
                // 붙인다(가방 ItemCard 와 같은 구조). 둘 다 두면 남는 폭을 나눠 가져 Stepper 가 가운데에 뜬다.
            }
            buyControls(l)
            ActionFailedNote(failed: $failed, text: l.actionFailed)
        }
        .productCard()
        .onChange(of: store.maxBuyCount(kind)) { _, _ in
            quantity = selectedQuantity
        }
    }

    /// 수량이 붙은 표시 이름("이상한 사탕 ×3"). 1개면 기존 문구 그대로.
    private func quantityName(_ l: L) -> String {
        selectedQuantity > 1 ? "\(l.itemName(kind)) ×\(selectedQuantity)" : l.itemName(kind)
    }

    @ViewBuilder
    private func buyControls(_ l: L) -> some View {
        if kind.isPassive && store.itemCount(kind) > 0 {
            // 보유형(이로치 부적 등) — 1회 구매라 소유 후엔 "보유 중" 표시(재구매 버튼 없음).
            HStack(spacing: 5) {
                Image(systemName: "checkmark.seal.fill").font(.caption2).foregroundStyle(Color.readableGreen)
                Text(l.ownedAlready).font(.caption2.weight(.semibold)).foregroundStyle(Color.readableGreen)
                Spacer()
            }
        } else if confirming {
            ShopConfirmation(store: store, name: quantityName(l), total: price * selectedQuantity,
                             quantity: selectedQuantity, toBag: false, onBuy: buyNow, onCancel: { confirming = false })
        } else {
            HStack(alignment: .firstTextBaseline) {
                // 가격은 선택 수량의 합계 — 확인 전에 총 지출을 보여준다.
                ShopPrice(store: store, entry: .item(kind), quantity: selectedQuantity)
                Spacer()
                if store.canBuy(kind) {
                    Button(l.buy) { confirming = true }
                        .buttonStyle(.pill(prominent: true))
                } else {
                    ShopMissing(store: store, total: price)
                }
            }
        }
    }

    private func buyNow() {
        confirming = false
        if store.buy(kind, count: selectedQuantity) { quantity = 1 } else { failed = true }
    }
}

/// An egg card: `tier` is the rarity it guarantees at least (nil: none). Bought, the egg goes in the Bag
/// (`ItemKind(shopEgg:)`): the player uses it there when they want to send their Pokémon off. Before, buying sent it
/// off at once.
///
/// 등급 알의 시각 구분은 **카드의 등급 배지**로만 한다 — 알 스프라이트는 한 장뿐이고, 메뉴바·플로팅 펫은
/// 기존 알 그대로 둔다(새 에셋 없이 구분이 서는 최소 범위).
@MainActor
private struct EggCard: View {
    let store: CompanionStore
    let tier: Rarity?
    @State private var confirming = false
    @State private var failed = false

    @State private var quantity = 1

    private var price: Int { store.price(of: .egg(tier)) }
    private var owned: Int { ItemKind(shopEgg: tier).map(store.itemCount) ?? 0 }
    private var maxQuantity: Int { max(1, store.maxEggBuyCount(tier)) }
    private var selectedQuantity: Int { min(quantity, maxQuantity) }

    var body: some View {
        let l = store.l
        VStack(alignment: .leading, spacing: Design.productCardSpacing) {
            HStack(alignment: .top, spacing: 10) {
                // 크롭+정사각 보정한 알. 레이아웃은 30(다른 아이템 아이콘과 정렬 일치)으로 두되 알 자체는 26으로
                // 살짝 작게 — 프레임에 여백이 생겨 꽉 찬 "뚱뚱" 느낌이 줄고 크기도 약간 작아진다.
                SpriteView(speciesID: nil, size: 26, egg: EggKind(tier: tier))
                    .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: Design.productTextSpacing) {
                    HStack(spacing: 6) {
                        Text(l.eggName(tier)).font(.callout.weight(.semibold))
                        if let tier {
                            // 도감 칩과 같은 라벨·색 — 상점의 등급 표기가 도감과 한 말로 맞물리게.
                            Badge(l.rarityLabel(tier).uppercased(), tint: .rarity(tier))
                        }
                        if owned > 0 {
                            Text(l.ownedCount(owned)).font(.caption2.weight(.bold))
                                .foregroundStyle(.secondary).monospacedDigit()
                        }
                        Spacer(minLength: 4)
                        // They wait in the Bag now, so several can be bought at once.
                        if store.maxEggBuyCount(tier) > 1 {
                            Stepper(value: $quantity, in: 1...maxQuantity) {
                                Text("×\(selectedQuantity)").font(.callout.weight(.semibold)).monospacedDigit()
                            }
                            .fixedSize()
                            .accessibilityLabel(l.eggName(tier))
                            .accessibilityValue("\(selectedQuantity)")
                        }
                    }
                    Text(l.eggDescription(tier))
                        .font(.caption).foregroundStyle(.secondary)
                        .lineSpacing(Design.productLineSpacing)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(l.eggGoesToBag)
                        .font(.caption2).foregroundStyle(.tertiary)
                        .lineSpacing(Design.productLineSpacing)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let odds = store.hatchOdds(for: .init(tier: tier)) {
                HatchOddsView(odds: odds, l: l)
            }
            buyControls(l)
            ActionFailedNote(failed: $failed, text: l.actionFailed)
        }
        .productCard()
        .onChange(of: store.maxEggBuyCount(tier)) { _, _ in quantity = selectedQuantity }
    }

    /// The same inline confirmation as the other items' (`ShopItemCard`).
    @ViewBuilder
    private func buyControls(_ l: L) -> some View {
        if confirming {
            let name = selectedQuantity > 1 ? "\(l.eggName(tier)) ×\(selectedQuantity)" : l.eggName(tier)
            ShopConfirmation(store: store, name: name, total: price * selectedQuantity, quantity: selectedQuantity,
                             toBag: true, onBuy: {
                                 confirming = false
                                 if store.buyEgg(tier, count: selectedQuantity) { quantity = 1 } else { failed = true }
                             }, onCancel: { confirming = false })
        } else {
            HStack(alignment: .firstTextBaseline) {
                ShopPrice(store: store, entry: .egg(tier), quantity: selectedQuantity)
                Spacer()
                if store.canBuyEgg(tier) {
                    Button(l.buy) { confirming = true }
                        .buttonStyle(.pill(prominent: true))
                } else {
                    ShopMissing(store: store, total: price)
                }
            }
        }
    }
}

/// A Shop price: what the selected quantity costs, its base price struck beside it when an item lowers it, and why.
@MainActor
private struct ShopPrice: View {
    let store: CompanionStore
    let entry: ShopEntry
    let quantity: Int

    var body: some View {
        let l = store.l
        let paid = store.price(of: entry) * quantity
        let base = store.basePrice(of: entry) * quantity
        let discounts = store.discounts(of: entry)
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(l.shopPriceLabel).foregroundStyle(.tertiary)
                if base > paid {
                    Text(TokenFormatter.compact(base)).strikethrough().foregroundStyle(.tertiary)
                    Text(TokenFormatter.compact(paid)).fontWeight(.semibold).foregroundStyle(.secondary)
                } else {
                    Text(TokenFormatter.compact(paid)).foregroundStyle(.tertiary)
                }
            }
            .font(.caption2).monospacedDigit()
            if base > paid, !discounts.isEmpty {
                Text(discounts.map(l.discountLine).joined(separator: " · "))
                    .font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// What the wallet lacks, in place of the Buy button: "Not enough tokens" said nothing of how many.
@MainActor
private struct ShopMissing: View {
    let store: CompanionStore
    let total: Int

    var body: some View {
        Label(store.l.shopMissing(TokenFormatter.compact(max(0, total - store.availableTokens))),
              systemImage: "exclamationmark.circle.fill")
            .font(.caption2.weight(.semibold)).monospacedDigit()
            .foregroundStyle(Color.readableOrange)
    }
}

/// The inline confirmation of a purchase: its total in the question, what the wallet keeps after it, and for eggs
/// that they go in the Bag. The total used to give way to the question at the moment of paying.
@MainActor
private struct ShopConfirmation: View {
    let store: CompanionStore
    let name: String
    let total: Int
    let quantity: Int
    let toBag: Bool
    let onBuy: () -> Void
    let onCancel: () -> Void

    var body: some View {
        let l = store.l
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(l.buyConfirm(name, total: TokenFormatter.compact(total)))
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Button(quantity > 1 ? "\(l.buy) ×\(quantity)" : l.buy) { onBuy() }
                    .buttonStyle(.pill(prominent: true))
                Button(l.cancel) { onCancel() }
                    .buttonStyle(.borderless).controlSize(.small)
            }
            let left = l.remainingAfterPurchase(TokenFormatter.compact(max(0, store.availableTokens - total)))
            Text(toBag ? "\(l.eggsGoToBag(quantity)) \(left)" : left)
                .font(.caption2).foregroundStyle(.tertiary).monospacedDigit()
        }
    }
}

/// A product's card, the same in the Shop and in the Bag (#183): a little more air than the app's other cards, with the
/// same text sizes, so a card stays compact.
extension Design {
    static let productCardPadding: CGFloat = 14
    /// Between a card's blocks: its name and description, odds, controls.
    static let productCardSpacing: CGFloat = 10
    /// Between the name line and the lines under it.
    static let productTextSpacing: CGFloat = 3
    /// Inside a description that wraps.
    static let productLineSpacing: CGFloat = 1.5
}

extension View {
    func productCard() -> some View {
        padding(Design.productCardPadding).designSurface(cornerRadius: Design.cornerRadius)
    }
}
