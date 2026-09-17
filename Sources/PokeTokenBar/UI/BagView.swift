import SwiftUI

/// 가방(인벤토리) — 소유 아이템 카드 + 사용. 빈 상태는 움직이는 잠만보(컬렉션의 피카츄 패턴).
@MainActor
struct BagView: View {
    let store: CompanionStore
    let nav: PopoverNavigation

    var body: some View {
        if store.ownedItems.isEmpty {
            emptyState
        } else {
            // 고정 높이 — 컬렉션과 동일(팝오버 재오픈 시 fitting size 축소 방지).
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(store.ownedItems, id: \.kind) { item in
                        ItemCard(store: store, nav: nav, kind: item.kind, count: item.count)
                    }
                }
            }
            .frame(height: 520)
        }
    }

    /// 빈 가방 — 움직이는 잠만보(143) + 안내(특정 아이템명 미언급, 확장 대비).
    private var emptyState: some View {
        VStack(spacing: 10) {
            SpriteView(speciesID: 143, size: 96, animated: true)   // 잠만보(움직임)
            Text(store.l.bagEmptyTitle)
                .font(.callout.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}

/// 아이템 1장 — 아이콘·이름·개수·설명 + 인라인 확인 사용.
/// 확인은 인라인(버튼 morph) — .sheet/.alert 금지: transient 팝오버가 닫힐 때 고아 시트가
/// 이후 클릭을 먹통내는 기존 결함(PopoverView 주석) 회피.
@MainActor
private struct ItemCard: View {
    let store: CompanionStore
    let nav: PopoverNavigation
    let kind: ItemKind
    let count: Int

    private enum UseStage {
        case idle
        case confirm
        case shinyConfirm
    }
    @State private var stage: UseStage = .idle

    var body: some View {
        let l = store.l
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                ItemIconView(kind: kind, size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(l.itemName(kind)).font(.callout.weight(.semibold))
                        if !kind.isPassive {   // 보유형은 개수 개념이 없음(1회 구매·영구)
                            Text("×\(count)").font(.caption.weight(.bold))
                                .foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                    Text(l.itemDescription(kind))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            useControls(l)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    /// 이 아이템을 지금 쓸 수 있나 (kind 별 — 사탕은 라인 로딩 필요, 민트/돌은 활성 포켓몬만).
    private var canUse: Bool {
        switch kind {
        case .rareCandy: return store.canUseRareCandy
        case .mint:      return store.canUseMint
        case .leafStone, .fireStone, .waterStone, .thunderStone, .sunStone,
             .moonStone, .iceStone, .duskStone, .dawnStone, .shinyStone:
            return store.canUseStone(kind)
        default:         return false
        }
    }
    /// 사용 컨트롤 효과 힌트 ("+XP" / "성격 랜덤 변경" / "타입 알 교체").
    private func effectHint(_ l: L) -> String {
        switch kind {
        case .rareCandy: return "+\(TokenFormatter.compact(RareCandy.xp)) XP"
        case .mint:      return l.mintEffectHint
        case .shinyCharm: return l.shinyCharmEffectHint
        case .legendCharm: return l.legendCharmEffectHint
        case .silverWing: return l.silverWingEffectHint
        case .oldSeaMap: return l.oldSeaMapEffectHint
        case .clearBell: return l.clearBellEffectHint
        case .rainbowWing: return l.rainbowWingEffectHint
        case .magmaStone: return l.magmaStoneEffectHint
        case .soulDew: return l.soulDewEffectHint
        case .jadeOrb: return l.jadeOrbEffectHint
        case .gracidea: return l.gracideaEffectHint
        case .griseousOrb: return l.griseousOrbEffectHint
        case .libertyPass: return l.libertyPassEffectHint
        case .revealGlass: return l.revealGlassEffectHint
        case .dnaSplicers: return l.dnaSplicersEffectHint
        case .boulderBadge, .cascadeBadge, .thunderBadge, .rainbowBadge,
             .soulBadge, .marshBadge, .volcanoBadge, .earthBadge,
             .zephyrBadge, .hiveBadge, .plainBadge, .fogBadge,
             .stormBadge, .mineralBadge, .glacierBadge, .risingBadge,
             .darkBadge, .fairyBadge:
            return l.badgeEffectHint
        case .leafStone, .fireStone, .waterStone, .thunderStone, .sunStone,
             .moonStone, .iceStone, .duskStone, .dawnStone, .shinyStone:
            if let st = kind.stoneType {
                return l.stoneEffectHint(l.typeName(st))
            }
            return ""
        }
    }
    private func performUse() {
        switch kind {
        case .rareCandy: _ = store.useRareCandy()
        case .mint:      _ = store.useMint()
        case .leafStone, .fireStone, .waterStone, .thunderStone, .sunStone,
             .moonStone, .iceStone, .duskStone, .dawnStone, .shinyStone:
            _ = store.useStone(kind)
        default:         break
        }
    }

    @ViewBuilder
    private func useControls(_ l: L) -> some View {
        if kind.isPassive {
            // 보유형(패시브 아이템) — 사용 버튼 대신 상시 효과 표시.
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill").font(.caption2).foregroundStyle(.green)
                Text(effectHint(l)).font(.caption2.weight(.semibold)).foregroundStyle(.green)
                Spacer()
            }
        } else if canUse {
            switch stage {
            case .idle:
                HStack {
                    Text(effectHint(l))
                        .font(.caption2).foregroundStyle(.tertiary).monospacedDigit()
                    Spacer()
                    Button(l.useItem) { stage = .confirm }
                        .buttonStyle(.bordered).controlSize(.small)
                }
            case .confirm:
                HStack(spacing: 8) {
                    if kind.stoneType != nil {
                        Text(l.stoneConfirm(store.displayName, l.itemName(kind)))
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                    } else {
                        Text(l.useOnCurrent(store.displayName))
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Button(l.use) {
                        if kind.stoneType != nil && store.currentIsShiny {
                            stage = .shinyConfirm
                        } else {
                            useNow()
                        }
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
                    Button(l.freshEggDiscardShiny) { useNow() }
                        .buttonStyle(.borderedProminent).controlSize(.small).tint(.orange)
                    Button(l.cancel) { stage = .idle }
                        .buttonStyle(.borderless).controlSize(.small)
                }
            }
        } else {
            // 알(부화 전)/활성 없음/(사탕만)라인 미로딩 — 비활성 + 사유
            Text(store.isEgg ? l.useAfterHatch : l.useNeedsPokemon)
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    /// 사용 → 항상 Home 탭으로 전환(진화/졸업 연출·"+XP"·성격 변경 토스트, 또는 새 알은 Home 에서 확인).
    private func useNow() {
        stage = .idle
        performUse()
        nav.tab = .home
    }
}
