import SwiftUI

/// Trade summary + accept/reject. Receives, as is, the snapshot `TradeView` builds inside the
/// `TradeSession.onOffersReady` callback — even if the session state changes afterward (e.g. a
/// withdraw), this screen keeps showing the fixed "offer as seen at that moment."
/// Inside the popover this is shown inline as the trade tab's body instead of via `.sheet` — that
/// avoids an existing defect where an orphaned sheet left behind when a transient popover closes
/// swallows every subsequent click (see the NOTE at the top of `PopoverView`, and `BagView`'s
/// identical workaround).
@MainActor
struct TradeProposalPanel: View {
    let myOffer: TradeItem
    let theirOffer: TradeItem
    let overwriteWarning: String?
    let store: CompanionStore
    let l: L
    let onAccept: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(l.tradeProposalTitle).font(.headline)
            tradeRow(label: l.tradeGiving, item: myOffer)
            tradeRow(label: l.tradeReceiving, item: theirOffer)
            if let overwriteWarning {
                Text(overwriteWarning)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button(l.tradeReject, role: .cancel, action: onReject)
                Spacer()
                Button(l.tradeAccept, action: onAccept)
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tradeRow(label: String, item: TradeItem) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            TradeItemRow(item: item, store: store)
            Text(l.rarityLabel(item.rarity)).font(.caption).foregroundStyle(.secondary)
        }
    }
}
