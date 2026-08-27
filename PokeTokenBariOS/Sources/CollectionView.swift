import SwiftUI
import PokeTokenBarShared

/// Collection — read-only mirror of the Mac's dex (graduated species ∪ the current
/// mon's reached stages). One cell per species, sorted by dex number.
struct CollectionView: View {
    @Environment(PhonePayloadStore.self) private var store
    @State private var selectedRarity: String?

    private var species: [PhoneDexSpecies] {
        guard let payload = store.payload else { return [] }
        guard let r = selectedRarity else { return payload.dex }
        return payload.dex.filter { $0.rarity == r }
    }

    private var totalCount: Int {
        store.payload?.dex.count ?? 0
    }

    var body: some View {
        NavigationStack {
            Group {
                if let payload = store.payload {
                    if payload.dex.isEmpty {
                        emptyState
                    } else {
                        content
                    }
                } else {
                    waitingView
                }
            }
            .navigationTitle("Collection")
            .refreshable { await store.fetch() }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                rarityFilter
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 8)], spacing: 12) {
                    ForEach(species) { sp in
                        DexCell(species: sp)
                    }
                }
                Text("Pokémon graduate from your Mac to appear here.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
            }
            .padding()
        }
    }

    /// Rarity filter — species-level counts, matching the Mac's dex header.
    private var rarityFilter: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Collection")
                    .font(.callout.weight(.semibold))
                Text("\(totalCount) species", comment: "Species count in the collection header")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                ForEach(RarityStyle.displayOrder, id: \.self) { rarity in
                    let count = store.payload?.dex.filter { $0.rarity == rarity }.count ?? 0
                    RarityChip(label: RarityStyle.label(rarity), count: count,
                               color: RarityStyle.color(rarity),
                               isSelected: selectedRarity == rarity) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedRarity = selectedRarity == rarity ? nil : rarity
                        }
                    }
                    .disabled(count == 0)
                }
            }
        }
    }

    /// Empty dex — Pikachu mascot, matching the Mac's empty-dex screen.
    private var emptyState: some View {
        VStack(spacing: 12) {
            SpeciesSprite(speciesID: 25, shiny: false, size: 96)
            Text("No Pokémon collected yet")
                .font(.callout.weight(.semibold))
            Text("Raise your Pokémon on the Mac —\ngraduated species appear here.")
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

/// One species cell — dex number, sprite, name. Shiny marker (✨) and a
/// "raising" badge when the species is not yet a permanent record.
private struct DexCell: View {
    let species: PhoneDexSpecies

    private static let thumb: CGFloat = 64

    var body: some View {
        VStack(spacing: 2) {
            SpeciesSprite(speciesID: species.id, shiny: species.isShiny, size: Self.thumb)
            .overlay(alignment: .topTrailing) {
                if species.isShiny {
                    Text("✨").font(.caption2)
                }
            }
            .overlay(alignment: .bottom) {
                if species.isRaising {
                    Text("RAISING")
                        .font(.system(size: 8, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .foregroundStyle(.tint)
                        .background(.regularMaterial, in: Capsule())
                }
            }
            Text(species.name)
                .font(.caption2)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text("#\(species.id)")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .padding(6)
        .frame(maxWidth: .infinity)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

/// Rarity filter chip with a count, mirroring the Mac's RarityTally look.
private struct RarityChip: View {
    let label: String
    let count: Int
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Text(label)
                    .font(.caption2)
                Text("\(count)")
                    .font(.caption2.weight(.bold))
                    .monospacedDigit()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(isSelected ? color : .secondary)
            .background(isSelected ? color.opacity(0.18) : Color.secondary.opacity(0.08))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
