import SwiftUI
import PokeTokenBarShared

/// Bag (inventory) — read-only mirror of the Mac's bag. Items are bought and used on
/// the Mac; the phone only shows what's currently owned.
struct BagView: View {
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
            .navigationTitle("Bag")
            .refreshable { await store.fetch() }
        }
    }

    @ViewBuilder
    private func content(_ payload: PhonePayload) -> some View {
        if payload.bag.isEmpty {
            emptyState
        } else {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(payload.bag) { item in
                        BagItemCard(item: item)
                    }
                    Text("Items can be used on your Mac.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding()
            }
        }
    }

    /// Empty bag — Snorlax mascot, matching the Mac's empty-bag screen.
    private var emptyState: some View {
        VStack(spacing: 12) {
            SpeciesSprite(speciesID: 143, shiny: false, size: 96)
            Text("Your bag is empty!")
                .font(.callout.weight(.semibold))
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

/// One owned item — icon, name, count, description. No use controls (read-only).
private struct BagItemCard: View {
    let item: PhoneBagItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                ItemIconView(iconName: item.iconName, fallbackEmoji: item.fallbackEmoji, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(item.name)
                            .font(.callout.weight(.semibold))
                        if !item.isPassive {
                            Text("×\(item.count)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    Text(item.itemDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            if item.isPassive, !item.effectHint.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                    Text(item.effectHint)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.green)
                    Spacer()
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

/// Item icon — PokéAPI item sprite with emoji fallback. Shared by bag/shop cards.
struct ItemIconView: View {
    let iconName: String?
    let fallbackEmoji: String
    let size: CGFloat

    var body: some View {
        Group {
            if let url = iconName.flatMap(PokeSprite.itemURL(name:)) {
                AsyncImage(url: url) { image in
                    image.resizable().interpolation(.none)
                } placeholder: {
                    Text(fallbackEmoji)
                        .font(.system(size: size * 0.6))
                }
                .frame(width: size, height: size)
            } else {
                Text(fallbackEmoji)
                    .font(.system(size: size * 0.6))
                    .frame(width: size, height: size)
            }
        }
    }
}

/// Static species sprite (pixelated) shared by bag/collection empty states.
struct SpeciesSprite: View {
    let speciesID: Int
    let shiny: Bool
    let size: CGFloat

    var body: some View {
        AsyncImage(url: PokeSprite.speciesURL(id: speciesID, shiny: shiny)) { image in
            image.resizable().interpolation(.none)
        } placeholder: {
            ProgressView()
        }
        .frame(width: size, height: size)
    }
}
