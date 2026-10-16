import SwiftUI

/// Permanent Mega Stone unlocks for final species already registered in the Pokédex.
/// Activation happens on the Pokémon screen so the shop remains focused on the one-time purchase.
@MainActor
struct MegaStoneSection: View {
    let store: CompanionStore

    var body: some View {
        if store.purchasableMegaStones.isEmpty {
            Text(store.l.megaStoneNoEligiblePokemon)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(store.purchasableMegaStones, id: \.self) { stone in
                    MegaStoneCard(store: store, stone: stone)
                }
            }
        }
    }
}

@MainActor
private struct MegaStoneCard: View {
    let store: CompanionStore
    let stone: MegaStone
    @State private var confirming = false

    private var price: Int { store.price(of: stone) }
    private var isOwned: Bool { store.ownsMegaStone(stone) }

    var body: some View {
        let l = store.l
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                ItemIconView(spriteName: stone.spriteName,
                             fallbackEmoji: stone.fallbackEmoji, size: 38)
                .frame(width: 48)
                // Mega artwork is already transparent; the preview intentionally
                // has no extra background or clipping rectangle.
                SpriteView(speciesID: stone.megaSpeciesID, size: 42)
                    .frame(width: 42, height: 42)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(l.megaStoneName(stone)).font(.callout.weight(.semibold))
                        if isOwned {
                            Text(l.ownedAlready).font(.caption2.weight(.bold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(l.megaStoneDescription(stone))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            if isOwned {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.caption2).foregroundStyle(.green)
                    Text(l.ownedAlready)
                        .font(.caption2.weight(.semibold)).foregroundStyle(.green)
                    Spacer()
                }
            } else {
                purchaseControls(l)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func purchaseControls(_ l: L) -> some View {
        if confirming {
            HStack(spacing: 8) {
                Text(l.buyConfirm(l.megaStoneName(stone)))
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
                if store.canBuy(stone) {
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
        _ = store.buy(stone)
    }
}
