import SwiftUI

/// Local editing state. Discarding Settings discards this value without touching the store.
/// Mirrors `DifficultyDraft` so both Companion settings behave the same on Save/Discard.
struct HatchRegionDraft: Equatable {
    var regions: Set<PokedexRegion>

    @MainActor init(companion: CompanionStore) {
        regions = companion.hatchRegions
    }

    @MainActor func differs(from companion: CompanionStore) -> Bool {
        regions != companion.hatchRegions
    }

    @MainActor mutating func save(to companion: CompanionStore) {
        companion.setHatchRegions(regions)
        self = HatchRegionDraft(companion: companion)
    }

    /// Toggling is refused when it would empty the selection — an empty pool is an egg
    /// that never hatches. The last enabled toggle is disabled in the UI as well, so this
    /// is a guard rather than the primary defence.
    mutating func toggle(_ region: PokedexRegion) {
        if regions.contains(region) {
            guard regions.count > 1 else { return }
            regions.remove(region)
        } else {
            regions.insert(region)
        }
    }
}

@MainActor
struct HatchRegionSettingsSection: View {
    let companion: CompanionStore
    @State var draft: HatchRegionDraft
    private var l: L { companion.l }

    init(companion: CompanionStore, draft: HatchRegionDraft? = nil) {
        self.companion = companion
        _draft = State(initialValue: draft ?? HatchRegionDraft(companion: companion))
    }

    private var isPartial: Bool { draft.regions.count < PokedexRegion.allCases.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(l.hatchRegionsSectionTitle)
                .font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
                .textCase(.uppercase).padding(.leading, 4)
            VStack(spacing: 0) {
                ForEach(Array(PokedexRegion.allCases.enumerated()), id: \.element) { index, region in
                    if index > 0 { Divider() }
                    row(region)
                }
            }
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 1))
            Text(l.hatchRegionsHint)
                .font(.caption2).foregroundStyle(.tertiary).padding(.leading, 4)
            if isPartial {
                Text(l.hatchRegionsBadgeWarning)
                    .font(.caption2).foregroundStyle(.tertiary).padding(.leading, 4)
            }
            if draft.differs(from: companion) {
                HStack {
                    Spacer()
                    Button(l.save) { draft.save(to: companion) }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("saveHatchRegions")
                }
            }
        }
    }

    /// Matches `SettingsView.toggleRow`: label left, switch right, same insets and row height.
    /// That helper is private to SettingsView, so the layout is repeated rather than shared —
    /// keep the two in step if the settings rows are ever restyled.
    private func row(_ region: PokedexRegion) -> some View {
        let isOn = draft.regions.contains(region)
        // The last enabled region cannot be switched off; say why instead of failing silently.
        let isLastOn = isOn && draft.regions.count == 1
        return HStack(spacing: 10) {
            // Baseline-aligned so the smaller dex range sits on the region name's line.
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(l.regionName(region))
                Text("#\(region.dexRange.lowerBound)–\(region.dexRange.upperBound)")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
            Toggle(l.regionName(region), isOn: Binding(
                get: { isOn },
                set: { _ in draft.toggle(region) }
            ))
            .labelsHidden().toggleStyle(.switch).controlSize(.small)
            .disabled(isLastOn)
            .help(isLastOn ? l.hatchRegionsLastOneHint : "")
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(minHeight: 38)
    }
}
