import SwiftUI

/// 상점 — 사용한 토큰(재화 = usedSinceInstall − spentTokens)으로 아이템 구매(이상한 사탕·민트).
/// 인라인 확인(버튼 morph) — .sheet/.alert 금지(BagView 주석과 동일: transient 팝오버가 닫힐 때
/// 고아 시트가 이후 클릭을 먹통내는 결함 회피).
@MainActor
struct ShopView: View {
    let store: CompanionStore
    let nav: PopoverNavigation

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
            }
        }
        .frame(height: 520)
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
/// kind 별 store.canBuy(kind)/buy(kind) 로 일반화 — 판매 목록은 store.purchasableItems.
@MainActor
private struct ShopItemCard: View {
    let store: CompanionStore
    let kind: ItemKind
    @State private var confirming = false

    private var price: Int { kind.shopPrice ?? 0 }

    var body: some View {
        let l = store.l
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                ItemIconView(kind: kind, size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(l.itemName(kind)).font(.callout.weight(.semibold))
                        let owned = store.itemCount(kind)
                        if owned > 0 && !kind.isPassive {
                            Text(l.ownedCount(owned)).font(.caption2.weight(.bold))
                                .foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                    Text(l.itemDescription(kind))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            buyControls(l)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
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
        } else if confirming {
            HStack(spacing: 8) {
                Text(l.buyConfirm(l.itemName(kind)))
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Button(l.buy) { buyNow() }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                Button(l.cancel) { confirming = false }
                    .buttonStyle(.borderless).controlSize(.small)
            }
        } else {
            HStack {
                Text("\(l.shopPriceLabel) \(TokenFormatter.compact(price))")
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
        _ = store.buy(kind)
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
    @State private var stage: Stage = .idle
    private enum Stage { case idle, confirm, shinyConfirm }

    private var price: Int { FreshEgg.price(guaranteeing: tier) }

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
                            Text(l.rarityLabel(tier).uppercased()).font(.system(size: 8, weight: .bold))
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(rarityColor(tier)).foregroundStyle(.white)
                                .clipShape(Capsule())
                        }
                    }
                    Text(l.eggDescription(tier))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            controls(l)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func controls(_ l: L) -> some View {
        switch stage {
        case .idle:
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("\(l.shopPriceLabel) \(TokenFormatter.compact(price))")
                        .font(.caption2).foregroundStyle(.tertiary).monospacedDigit()
                    Spacer()
                    if !store.hasActive {
                        // 알 상태 — 리롤 대상이 없어 구매만 막는다(canBuyEgg 게이트). 항목을 숨기는 대신
                        // 비활성 버튼으로 "상점에 있긴 하다"를 보이고, 사유는 아래 한 줄로.
                        Button(l.buy) {}
                            .buttonStyle(.bordered).controlSize(.small).disabled(true)
                    } else if store.canBuyEgg(tier) {
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
                Text(l.eggConfirm(store.displayName, l.eggName(tier)))
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                Spacer()
                // 이로치면 한 번 더 경고, 아니면 즉시 실행.
                Button(l.buy) {
                    if store.currentIsShiny { stage = .shinyConfirm } else { commit() }
                }
                .buttonStyle(.borderedProminent).controlSize(.small)
                Button(l.cancel) { stage = .idle }
                    .buttonStyle(.borderless).controlSize(.small)
            }
        case .shinyConfirm:
            HStack(spacing: 8) {
                Text(l.freshEggShinyWarning)
                    .font(.caption2.weight(.semibold)).foregroundStyle(.orange).lineLimit(2)
                Spacer()
                Button(l.freshEggDiscardShiny) { commit() }
                    .buttonStyle(.borderedProminent).controlSize(.small).tint(.orange)
                Button(l.cancel) { stage = .idle }
                    .buttonStyle(.borderless).controlSize(.small)
            }
        }
    }

    /// 리롤 실행 → 새 알을 볼 수 있게 Home 으로 전환(가방 사용과 동일 패턴).
    private func commit() {
        stage = .idle
        if store.buyEgg(tier) { nav.tab = .home }
    }
}
