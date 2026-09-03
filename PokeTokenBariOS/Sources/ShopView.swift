import SwiftUI
import PokeTokenBarShared

/// Shop — read-only mirror of the Mac's shop (purchasable items + egg rerolls).
/// Buying happens on the Mac; the phone shows prices, owned state, and whether
/// the current spendable tokens cover each price.
struct ShopView: View {
    @Environment(PhonePayloadStore.self) private var store

    var body: some View {
        NavigationStack {
            Group {
                if let payload = store.payload {
                    content(payload)
                } else {
                    waitingView
                }
            }
            .navigationTitle("Shop")
            .refreshable { await store.fetch() }
        }
    }

    @ViewBuilder
    private func content(_ payload: PhonePayload) -> some View {
        if payload.shop.isEmpty {
            emptyState
        } else {
            ScrollView {
                VStack(spacing: 12) {
                    walletHeader(payload)
                    ForEach(payload.shop) { entry in
                        ShopItemCard(entry: entry)
                    }
                    Text("Items can be purchased on your Mac.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding()
            }
        }
    }

    /// Wallet header — spendable tokens (usedSinceInstall − spentTokens), matching
    /// the Mac's shop header.
    private func walletHeader(_ payload: PhonePayload) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Spendable tokens")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(TokenFormatter.compact(payload.spendableTokens))
                .font(.system(size: 24, weight: .bold))
                .monospacedDigit()
            Text("Spend the tokens you've used on items.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    /// Shop data missing — the Mac is running a version that predates the shop
    /// payload (older Macs publish without the `shop` field).
    private var emptyState: some View {
        VStack(spacing: 12) {
            SpeciesSprite(speciesID: 52, shiny: false, size: 96)
            Text("No shop data yet")
                .font(.callout.weight(.semibold))
            Text("Update PokeTokenBar on your Mac\nto browse the shop here.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var waitingView: some View {
        VStack(spacing: 12) {
            Image(systemName: "desktopcomputer.and.iphone")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Waiting for data from your Mac…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

/// One shop listing — icon, name (+ egg rarity badge, owned count), description,
/// and the price row. Read-only: the Mac's Buy/confirm controls become an
/// affordability hint ("Buy on Mac" / "Not enough tokens").
private struct ShopItemCard: View {
    let entry: PhoneShopEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                ItemIconView(iconName: entry.iconName, fallbackEmoji: entry.fallbackEmoji, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(entry.name)
                            .font(.callout.weight(.semibold))
                        if let rarity = entry.rarity {
                            // Same label/color pair as the collection chips so the
                            // tier notation reads the same across tabs.
                            Text(RarityStyle.label(rarity).uppercased())
                                .font(.system(size: 8, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(RarityStyle.color(rarity))
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                        }
                        if !entry.isPassive, entry.ownedCount > 0 {
                            Text("×\(entry.ownedCount)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    Text(entry.itemDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            priceControls
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private var priceControls: some View {
        if entry.isOwned {
            // Passive one-time purchase already owned — matches the Mac's
            // green "Owned" state (no repurchase).
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.caption2)
                    .foregroundStyle(.green)
                Text("Owned")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.green)
                Spacer()
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Price \(TokenFormatter.compact(entry.price))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                    Spacer()
                    // A state block (egg stage) outranks the balance: the Mac sends the
                    // localized reason, so showing "Not enough tokens" over it would be a
                    // lie whenever the wallet is fine. Same priority as the Mac's EggCard.
                    if entry.lockedReason != nil {
                        Label("Buy on Mac", systemImage: "desktopcomputer")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    } else if entry.canAfford {
                        Label("Buy on Mac", systemImage: "desktopcomputer")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Not enough tokens")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                if let reason = entry.lockedReason {
                    Text(reason)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
