import SwiftUI

/// Controls of every action that sends the current Pokémon off for a new egg (a Shop egg, an evolution
/// stone from the Bag): disabled while an egg incubates, one confirmation, and a second one for a shiny or
/// legendary companion. A successful action switches to Home to show the new egg.
@MainActor
struct ReleaseForEggControls: View {
    let store: CompanionStore
    let nav: PopoverNavigation
    /// Line left of the button: an egg's price, a stone's guaranteed type.
    let detail: String
    let actionTitle: String
    let isAvailable: Bool
    /// Shown instead of the button when a companion is there but the action is not available.
    let unavailableText: String
    let confirmText: String
    let action: @MainActor () -> Bool
    @State private var stage: Stage = .idle
    private enum Stage { case idle, confirm, preciousConfirm }

    var body: some View {
        let l = store.l
        switch stage {
        case .idle:
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(detail)
                        .font(.caption2).foregroundStyle(.tertiary).monospacedDigit()
                    Spacer()
                    if !store.hasActive {
                        // 알 상태: 리롤 대상이 없어 실행만 막는다(canBuyEgg/canUseStone 게이트). 항목을 숨기는 대신
                        // 비활성 버튼으로 "있긴 하다"를 보이고, 사유는 아래 한 줄로.
                        Button(actionTitle) {}
                            .buttonStyle(.bordered).controlSize(.small).disabled(true)
                    } else if isAvailable {
                        Button(actionTitle) { stage = .confirm }
                            .buttonStyle(.bordered).controlSize(.small)
                    } else {
                        Text(unavailableText).font(.caption2).foregroundStyle(.tertiary)
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
                Button(actionTitle) {
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

    /// 실행 → 새 알을 볼 수 있게 Home 으로 전환(가방 사용과 동일 패턴).
    private func commit() {
        stage = .idle
        if action() { nav.tab = .home }
    }
}
