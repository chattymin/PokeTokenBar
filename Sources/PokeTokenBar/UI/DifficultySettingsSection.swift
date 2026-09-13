import SwiftUI

/// Local editing state. Discarding Settings discards this value without touching the store.
struct DifficultyDraft: Equatable {
    var growth: Double
    var shop: Double

    @MainActor init(companion: CompanionStore) {
        growth = companion.growthDifficulty
        shop = companion.shopDifficulty
    }

    @MainActor func differs(from companion: CompanionStore) -> Bool {
        growth != companion.growthDifficulty || shop != companion.shopDifficulty
    }

    @MainActor mutating func save(to companion: CompanionStore) {
        companion.setGrowthDifficulty(growth)
        companion.setShopDifficulty(shop)
        self = DifficultyDraft(companion: companion)
    }
}

@MainActor
struct DifficultySettingsSection: View {
    let companion: CompanionStore
    @State var draft: DifficultyDraft
    private var l: L { companion.l }

    init(companion: CompanionStore, draft: DifficultyDraft? = nil) {
        self.companion = companion
        _draft = State(initialValue: draft ?? DifficultyDraft(companion: companion))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(l.difficultySectionTitle)
                .font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
                .textCase(.uppercase).padding(.leading, 4)
            VStack(spacing: 0) {
                row(l.difficultyGrowthLabel, value: $draft.growth)
                Divider()
                row(l.difficultyShopLabel, value: $draft.shop)
            }
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 1))
            Text("10%–200% · " + l.difficultyHint).font(.caption2).foregroundStyle(.tertiary).padding(.leading, 4)
            if draft.differs(from: companion) {
                HStack {
                    Spacer()
                    Button(l.save) { draft.save(to: companion) }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("saveDifficulty")
                }
            }
        }
    }

    private func row(_ label: String, value: Binding<Double>) -> some View {
        HStack(spacing: 10) {
            Text(label).font(.callout).frame(width: 76, alignment: .leading)
            Slider(value: Binding(
                get: { PokemonBalance.difficultyPosition(value.wrappedValue) },
                set: { value.wrappedValue = PokemonBalance.difficulty(atPosition: $0) }), in: 0...1)
                .accessibilityLabel(label)
            Text(l.difficultyValue(value.wrappedValue))
                .font(.caption).monospacedDigit().frame(width: 52, alignment: .trailing)
        }
        .padding(.horizontal, 12).padding(.vertical, 8).frame(minHeight: 38)
    }
}
