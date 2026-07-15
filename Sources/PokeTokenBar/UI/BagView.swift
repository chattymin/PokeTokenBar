import SwiftUI

/// 가방(인벤토리) — 소유 아이템 카드 + 사용. 빈 상태는 움직이는 잠만보(컬렉션의 피카츄 패턴).
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
private struct ItemCard: View {
    let store: CompanionStore
    let nav: PopoverNavigation
    let kind: ItemKind
    let count: Int
    @State private var confirming = false

    var body: some View {
        let l = store.l
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                ItemIconView(kind: kind, size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(l.itemName(kind)).font(.callout.weight(.semibold))
                        Text("×\(count)").font(.caption.weight(.bold))
                            .foregroundStyle(.secondary).monospacedDigit()
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

    @ViewBuilder
    private func useControls(_ l: L) -> some View {
        if store.canUseRareCandy {
            if confirming {
                HStack(spacing: 8) {
                    Text(l.useOnCurrent(store.displayName))
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    Button(l.use) { useNow() }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                    Button(l.cancel) { confirming = false }
                        .buttonStyle(.borderless).controlSize(.small)
                }
            } else {
                HStack {
                    Text("+\(TokenFormatter.compact(RareCandy.xp)) XP")
                        .font(.caption2).foregroundStyle(.tertiary).monospacedDigit()
                    Spacer()
                    Button(l.useItem) { confirming = true }
                        .buttonStyle(.bordered).controlSize(.small)
                }
            }
        } else {
            // 알(부화 전)/활성 없음/라인 미로딩 — 비활성 + 사유
            Text(store.isEgg ? l.useAfterHatch : l.useNeedsPokemon)
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    /// 사용 → 항상 Home 탭으로 전환(진화/졸업 연출·"+XP" 는 Home 의 CompanionHeader 에서 재생).
    private func useNow() {
        confirming = false
        _ = store.useRareCandy()
        nav.tab = .home
    }
}
