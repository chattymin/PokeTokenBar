import SwiftUI

/// 상점 — 사용한 토큰(재화 = usedSinceInstall − spentTokens)으로 아이템 구매(이상한 사탕·민트).
/// 인라인 확인(버튼 morph) — .sheet/.alert 금지(BagView 주석과 동일: transient 팝오버가 닫힐 때
/// 고아 시트가 이후 클릭을 먹통내는 결함 회피).
@MainActor
struct ShopView: View {
    let store: CompanionStore
    let nav: PopoverNavigation
    /// Collector sections start folded: 38 cards would bury the regular items.
    @State private var expandedGroups: Set<CollectorGroup> = []

    var body: some View {
        let l = store.l
        // 고정 높이 — 컬렉션/가방과 동일(팝오버 재오픈 시 fitting size 축소 방지).
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                walletHeader(l)
                // shopEntries = 판매 아이템 + 알 3종(보증 없음·고급 이상·희귀 이상)을 가격 오름차순으로
                // 병합한 단일 목록. 알은 항상 포함되고(즉시 액션이라 ItemKind 가 아님), 알 상태에선
                // EggCard 가 구매만 비활성으로 보여준다.
                ForEach(store.shopEntries, id: \.self) { entry in
                    switch entry {
                    case .item(let kind):
                        ShopItemCard(store: store, kind: kind)
                    case .egg(let tier):
                        EggCard(store: store, nav: nav, tier: tier)
                    }
                }
                Text(l.collectorHint)
                    .font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
                ForEach(CollectorGroup.allCases, id: \.self) { group in
                    CollectorSection(store: store, nav: nav, group: group, expanded: expandedBinding(group))
                }
            }
            .reservesScrollerLane()
        }
        .frame(height: 520)
    }

    private func expandedBinding(_ group: CollectorGroup) -> Binding<Bool> {
        Binding(
            get: { expandedGroups.contains(group) },
            set: { if $0 { expandedGroups.insert(group) } else { expandedGroups.remove(group) } })
    }

    private func walletHeader(_ l: L) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(l.spendableTokens)
                .font(.caption).foregroundStyle(.secondary)
            Text(TokenFormatter.compact(store.availableTokens))
                .font(.system(size: 24, weight: .bold)).monospacedDigit()
            Text(l.shopHint)
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
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
    @State private var quantity = 1

    private var price: Int { store.price(of: kind) ?? 0 }
    private var maxQuantity: Int { max(1, store.maxBuyCount(kind)) }
    /// 잔액이 줄어 한도가 내려가도 선택값이 한도를 넘지 않게 클램프.
    private var selectedQuantity: Int { min(quantity, maxQuantity) }
    /// 보유형은 1회 구매라 수량 선택이 없다. 2개 이상 살 수 있을 때만 Stepper 노출.
    private var showsQuantity: Bool { !kind.isPassive && store.maxBuyCount(kind) > 1 }
    /// Not yet on sale: the Pokédex goal is missing. An owned passive is past that question.
    private var isLocked: Bool {
        !(kind.isPassive && store.itemCount(kind) > 0) && !store.isUnlocked(kind)
    }

    var body: some View {
        let l = store.l
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                ItemIconView(kind: kind, size: 30)
                    .grayscale(isLocked ? 1 : 0).opacity(isLocked ? 0.5 : 1)
                VStack(alignment: .leading, spacing: 2) {
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
                    Text(l.itemDescription(kind))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // 바깥 Spacer 없음 — 이름 줄의 Spacer 가 남는 폭을 전부 받아 Stepper 를 카드 오른쪽 끝에
                // 붙인다(가방 ItemCard 와 같은 구조). 둘 다 두면 남는 폭을 나눠 가져 Stepper 가 가운데에 뜬다.
            }
            if kind.unlock != nil {
                UnlockRequirementView(store: store, kind: kind, compact: !isLocked)
            }
            buyControls(l)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
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
                Image(systemName: "checkmark.seal.fill").font(.caption2).foregroundStyle(.green)
                Text(l.ownedAlready).font(.caption2.weight(.semibold)).foregroundStyle(.green)
                Spacer()
            }
        } else if isLocked {
            LockedPriceRow(store: store, price: price)
        } else if confirming {
            HStack(spacing: 8) {
                Text(l.buyConfirm(quantityName(l)))
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Button(selectedQuantity > 1 ? "\(l.buy) ×\(selectedQuantity)" : l.buy) { buyNow() }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                Button(l.cancel) { confirming = false }
                    .buttonStyle(.borderless).controlSize(.small)
            }
        } else {
            HStack {
                // 가격은 선택 수량의 합계 — 확인 전에 총 지출을 보여준다.
                Text("\(l.shopPriceLabel) \(TokenFormatter.compact(price * selectedQuantity))")
                    .font(.caption2).foregroundStyle(.tertiary).monospacedDigit()
                Spacer()
                if store.canBuy(kind) {
                    Button(l.buy) { confirming = true }
                        .buttonStyle(.bordered).controlSize(.small)
                } else {
                    Text(l.notEnoughTokens)
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func buyNow() {
        confirming = false
        if store.buy(kind, count: selectedQuantity) { quantity = 1 }
    }
}

/// One foldable shop section of collector items, with how many are unlocked.
@MainActor
private struct CollectorSection: View {
    let store: CompanionStore
    let nav: PopoverNavigation
    let group: CollectorGroup
    @Binding var expanded: Bool

    var body: some View {
        let l = store.l
        let items = store.collectorItems(in: group)
        let registered = store.registeredSpeciesIDs
        let unlocked = items.filter { store.isUnlocked($0, registered: registered) }.count
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    ItemIconView(kind: group.iconItem, size: 22)
                    Text(l.collectorGroupTitle(group)).font(.callout.weight(.semibold))
                    Spacer()
                    Text(l.collectorUnlockedCount(unlocked, of: items.count))
                        .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .padding(10)
                .frame(maxWidth: .infinity)
                .background(Color.secondary.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if expanded {
                ForEach(items, id: \.self) { kind in
                    if kind.stoneType != nil {
                        StoneCard(store: store, nav: nav, kind: kind)
                    } else {
                        ShopItemCard(store: store, kind: kind)
                    }
                }
            }
        }
    }
}

private extension CollectorGroup {
    /// Item drawn on the section header.
    var iconItem: ItemKind {
        switch self {
        case .evolutionStones: return .fireStone
        case .legendaryArtifacts: return .legendCharm
        case .gymBadges: return .boulderBadge
        }
    }
}

/// Pokédex goal of a collector item: its Pokémon (greyed until registered) with a counter, or a progress
/// bar for the long type lists of the gym badges. Once the item is unlocked the goal stays visible in a
/// `compact` line (smaller sprites, a check, no box), limited to the goal that was met.
@MainActor
private struct UnlockRequirementView: View {
    let store: CompanionStore
    let kind: ItemKind
    var compact = false

    /// Above this many species a sprite row no longer fits the card: show a bar instead.
    private static let spriteRowLimit = 9

    var body: some View {
        let l = store.l
        let content = VStack(alignment: .leading, spacing: compact ? 2 : 4) {
            switch kind.unlock {
            case .duplicateLegendary:
                let copies = min(store.graduatedLegendaryCopies, 2)
                counterRow(l.duplicateLegendaryGoal, count: copies, needed: 2, met: copies >= 2)
            case .species:
                let goals = store.unlockProgress(of: kind)
                // Compact: only the goal that unlocked the item (all of them if none is met, e.g. an owned
                // item bought before the goal existed).
                let shown = compact && goals.contains(where: \.isMet) ? goals.filter(\.isMet) : goals
                ForEach(Array(shown.enumerated()), id: \.offset) { index, progress in
                    if index > 0 {
                        Text(l.unlockOr).font(.caption2).foregroundStyle(.tertiary)
                    }
                    goalView(progress, l)
                }
            case nil:
                EmptyView()
            }
        }
        if compact {
            content
        } else {
            content
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    @ViewBuilder
    private func goalView(_ progress: CompanionStore.GoalProgress, _ l: L) -> some View {
        let goal = progress.goal
        if goal.species.count > Self.spriteRowLimit {
            VStack(alignment: .leading, spacing: 3) {
                counterRow(kind.badgeType.map(l.typeGoal) ?? "", count: progress.count, needed: goal.needed,
                           met: progress.isMet)
                if !compact {
                    ProgressView(value: Double(progress.count), total: Double(max(1, goal.needed)))
                        .controlSize(.small)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                if goal.needed < goal.species.count {
                    Text(l.anyOfGoal(goal.needed)).font(.caption2).foregroundStyle(compact ? .tertiary : .secondary)
                }
                HStack(spacing: compact ? 2 : 3) {
                    if compact && progress.isMet { checkmark }
                    ForEach(goal.species, id: \.self) { id in
                        let has = progress.registered.contains(id)
                        SpriteView(speciesID: id, size: spriteSize(count: goal.species.count))
                            .grayscale(has ? 0 : 1).opacity(has ? 1 : 0.35)
                            .help("#\(id)")
                    }
                    Spacer(minLength: 4)
                    counter(progress.count, needed: goal.needed)
                }
            }
        }
    }

    private func spriteSize(count: Int) -> CGFloat {
        compact ? (count > 6 ? 16 : 18) : (count > 6 ? 24 : 30)
    }

    /// Only on a met goal: an item can be owned without its goal (bought before the goal existed).
    private var checkmark: some View {
        Image(systemName: "checkmark.circle.fill").font(.caption2).foregroundStyle(.green)
    }

    private func counter(_ count: Int, needed: Int) -> some View {
        Text("\(count)/\(needed)")
            .font(.caption2.weight(.semibold)).foregroundStyle(compact ? .tertiary : .secondary).monospacedDigit()
    }

    private func counterRow(_ text: String, count: Int, needed: Int, met: Bool) -> some View {
        HStack(spacing: 4) {
            if compact && met { checkmark }
            Text(text).font(.caption2).foregroundStyle(compact ? .tertiary : .secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            counter(count, needed: needed)
        }
    }
}

/// 알 카드 — 구매 = 즉시 현재 포켓몬 폐기 후 새 알로. `tier` 는 보증 등급 하한(nil = 보증 없는 기본 알).
/// 인라인 2단계 확인: 일반은 1회, 이로치면 한 번 더(사고 폐기 방지). 성공하면 Home 으로 전환해 새 알을 보여준다.
/// 알 상태(활성 없음)에서도 카드는 노출하되 구매 버튼만 비활성 + 사유 한 줄(eggShopLockedHint).
///
/// 등급 알의 시각 구분은 **카드의 등급 배지**로만 한다 — 알 스프라이트는 한 장뿐이고, 메뉴바·플로팅 펫은
/// 기존 알 그대로 둔다(새 에셋 없이 구분이 서는 최소 범위).
@MainActor
private struct EggCard: View {
    let store: CompanionStore
    let nav: PopoverNavigation
    let tier: Rarity?

    private var price: Int { store.price(of: .egg(tier)) }

    var body: some View {
        let l = store.l
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                // 크롭+정사각 보정한 알. 레이아웃은 30(다른 아이템 아이콘과 정렬 일치)으로 두되 알 자체는 26으로
                // 살짝 작게 — 프레임에 여백이 생겨 꽉 찬 "뚱뚱" 느낌이 줄고 크기도 약간 작아진다.
                SpriteView(speciesID: nil, size: 26)
                    .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(l.eggName(tier)).font(.callout.weight(.semibold))
                        if let tier {
                            // 도감 칩과 같은 라벨·색 — 상점의 등급 표기가 도감과 한 말로 맞물리게.
                            Badge(l.rarityLabel(tier).uppercased(), tint: .rarity(tier))
                        }
                    }
                    Text(l.eggDescription(tier))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    // "놓아준다" 바로 아래 — 무엇을 잃는지 읽은 자리에서 무엇이 남는지 이어 읽게 한다.
                    // 가격 줄이 아니라 여기인 이유: 이건 가격·구매 가능 여부와 무관한 상품 설명이고,
                    // 아래쪽은 버튼과 `eggShopLockedHint`(왜 못 사는지) 가 쓰는 자리다.
                    // 놓아줄 대상이 있을 때만 — 알 상태에선 할 말이 아니다.
                    if store.hasActive {
                        Text(l.eggReleaseNote)
                            .font(.caption2).foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer()
            }
            ReleaseForEggControls(store: store, nav: nav, price: price, canBuy: store.canBuyEgg(tier),
                                  confirmText: l.eggConfirm(store.displayName, l.eggName(tier))) {
                store.buyEgg(tier)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

/// Buy controls of every purchase that sends the current Pokémon off for a new egg (eggs and evolution
/// stones): disabled while an egg incubates, one confirmation, and a second one for a shiny or legendary
/// companion. A successful purchase switches to Home to show the new egg.
@MainActor
private struct ReleaseForEggControls: View {
    let store: CompanionStore
    let nav: PopoverNavigation
    let price: Int
    let canBuy: Bool
    let confirmText: String
    let purchase: @MainActor () -> Bool
    @State private var stage: Stage = .idle
    private enum Stage { case idle, confirm, preciousConfirm }

    var body: some View {
        let l = store.l
        switch stage {
        case .idle:
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("\(l.shopPriceLabel) \(TokenFormatter.compact(price))")
                        .font(.caption2).foregroundStyle(.tertiary).monospacedDigit()
                    Spacer()
                    if !store.hasActive {
                        // 알 상태: 리롤 대상이 없어 구매만 막는다(canBuyEgg/canBuyStone 게이트). 항목을 숨기는 대신
                        // 비활성 버튼으로 "상점에 있긴 하다"를 보이고, 사유는 아래 한 줄로.
                        Button(l.buy) {}
                            .buttonStyle(.bordered).controlSize(.small).disabled(true)
                    } else if canBuy {
                        Button(l.buy) { stage = .confirm }
                            .buttonStyle(.bordered).controlSize(.small)
                    } else {
                        Text(l.notEnoughTokens).font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                if !store.hasActive {
                    Text(l.eggShopLockedHint)
                        .font(.caption2).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        case .confirm:
            HStack(spacing: 8) {
                Text(confirmText)
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                Spacer()
                // 이로치나 전설 등 고가치 포켓몬이면 한 번 더 경고, 아니면 즉시 실행.
                Button(l.buy) {
                    if store.isHighValueCompanion { stage = .preciousConfirm } else { commit() }
                }
                .buttonStyle(.borderedProminent).controlSize(.small)
                Button(l.cancel) { stage = .idle }
                    .buttonStyle(.borderless).controlSize(.small)
            }
        case .preciousConfirm:
            HStack(spacing: 8) {
                Text(store.rarity == .legendary ? l.freshEggLegendaryWarning : l.freshEggShinyWarning)
                    .font(.caption2.weight(.semibold)).foregroundStyle(.orange).lineLimit(2)
                Spacer()
                Button(store.currentIsShiny && store.rarity != .legendary ? l.freshEggDiscardShiny : l.freshEggDiscardValuable) { commit() }
                    .buttonStyle(.borderedProminent).controlSize(.small).tint(.orange)
                Button(l.cancel) { stage = .idle }
                    .buttonStyle(.borderless).controlSize(.small)
            }
        }
    }

    /// 리롤 실행 → 새 알을 볼 수 있게 Home 으로 전환(가방 사용과 동일 패턴).
    private func commit() {
        stage = .idle
        if purchase() { nav.tab = .home }
    }
}

/// Evolution stone card: bought like an egg. The current Pokémon is sent off right away for an egg of
/// the stone's type; the stone never goes to the Bag. Locked until its Pokédex goal is met.
@MainActor
private struct StoneCard: View {
    let store: CompanionStore
    let nav: PopoverNavigation
    let kind: ItemKind

    private var price: Int { store.price(of: kind) ?? 0 }
    private var isLocked: Bool { !store.isUnlocked(kind) }

    var body: some View {
        let l = store.l
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                ItemIconView(kind: kind, size: 30)
                    .grayscale(isLocked ? 1 : 0).opacity(isLocked ? 0.5 : 1)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(l.itemName(kind)).font(.callout.weight(.semibold))
                        if let type = kind.stoneType {
                            Badge(l.typeName(type).uppercased(), tint: .type(type))
                        }
                    }
                    Text(l.itemDescription(kind))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if store.hasActive && !isLocked {
                        Text(l.eggReleaseNote)
                            .font(.caption2).foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer()
            }
            UnlockRequirementView(store: store, kind: kind, compact: !isLocked)
            if isLocked {
                LockedPriceRow(store: store, price: price)
            } else {
                ReleaseForEggControls(store: store, nav: nav, price: price, canBuy: store.canBuyStone(kind),
                                      confirmText: l.stoneConfirm(store.displayName, l.itemName(kind))) {
                    store.buyStone(kind)
                }
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

/// Price and lock of a collector item whose Pokédex goal is not met yet.
@MainActor
private struct LockedPriceRow: View {
    let store: CompanionStore
    let price: Int

    var body: some View {
        let l = store.l
        HStack {
            Text("\(l.shopPriceLabel) \(TokenFormatter.compact(price))")
                .font(.caption2).foregroundStyle(.tertiary).monospacedDigit()
            Spacer()
            Label(l.lockedLabel, systemImage: "lock.fill")
                .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
        }
    }
}
