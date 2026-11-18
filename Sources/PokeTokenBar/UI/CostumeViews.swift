import SwiftUI

/// A Costume Egg in the Bag (the owner, 2026-11-13): its month's event egg, used as the Shop's eggs are. What it holds
/// is drawn when opened, so it shows no Pokémon; locked while none of the player's Pokémon has a costume left in its lot
/// (the owner, 2026-11-18).
@MainActor
struct CostumeEggCard: View {
    let store: CompanionStore
    let nav: PopoverNavigation
    let egg: CostumeEgg

    var body: some View {
        let l = store.l
        let name = l.costumeEggName(egg.month)
        let locked = store.isCostumeEggLocked(egg.id)
        VStack(alignment: .leading, spacing: Design.productCardSpacing) {
            HStack(alignment: .center, spacing: 10) {
                SpriteView(speciesID: nil, size: 30, egg: .costume(egg.month))
                VStack(alignment: .leading, spacing: Design.productTextSpacing) {
                    Text(name).font(.callout.weight(.semibold)).lineLimit(1)
                    Text(locked ? l.costumeEggLocked : l.costumeEggDrawnAtOpening)
                        .font(.caption).foregroundStyle(locked ? Color.readableOrange : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if store.hasActive, !locked {
                        Text(l.eggReleaseNote).font(.caption2).foregroundStyle(.tertiary)
                            .lineSpacing(Design.productLineSpacing)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            ReleaseForEggControls(store: store, nav: nav, detail: "", actionTitle: l.useItem,
                                  isAvailable: store.canUseCostumeEgg(egg.id),
                                  unavailableText: locked ? l.costumeEggLockedShort : l.useNeedsPokemon,
                                  confirmText: l.stoneConfirm(store.displayName, name),
                                  lockedHint: store.isRaisingFossilEggPokemon ? l.fossilEggInProgress : nil) {
                store.useCostumeEgg(egg.id)
            }
        }
        .productCard()
    }
}

/// The costumed Pokémon collected (the owner, 2026-11-13): the counts, this month's event and the next Costume Egg,
/// then each month's lot under its month, this month's first, all in one list: the ones collected in their costume and
/// named, the others in silhouette.
@MainActor
struct CostumeCollectionScreen: View {
    let store: CompanionStore
    let onBack: () -> Void

    /// A sprite's size, five to a row with their names.
    private static let cell: CGFloat = 40

    /// The lots' months, from `month`'s on, around the year.
    static func lotMonths(from month: Int) -> [Int] {
        (0..<12).map { (month - 1 + $0) % 12 + 1 }
    }

    var body: some View {
        let l = store.l
        let owned = store.ownedCostumeKeys()
        let month = store.costumeMonth
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Button { onBack() } label: { Label(l.back, systemImage: "chevron.left").labelStyle(.titleAndIcon) }
                    .buttonStyle(.borderless)
                    .keyboardShortcut(.cancelAction)
                Spacer(minLength: 4)
                Image(systemName: "theatermasks.fill").foregroundStyle(.secondary)
                Text(l.costumesTitle).font(.headline).lineLimit(1).minimumScaleFactor(0.8)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 4) {
                        StatsRing(title: l.costumesTitle, owned: owned.all.count, total: CostumeCatalog.entries.count,
                                  color: CollectionStatsScreen.done)
                        StatsRing(title: l.dexStatsShinies, owned: owned.shiny.count,
                                  total: CostumeCatalog.entries.count, color: CollectionStatsScreen.left)
                    }
                    .frame(maxWidth: .infinity)
                    nextEgg(month, l)
                    ForEach(Self.lotMonths(from: month), id: \.self) { lotMonth in
                        lot(lotMonth, owned: owned, current: lotMonth == month, l)
                    }
                }
                .reservesScrollerLane()
            }
        }
        .padding(PopoverMetrics.padding)
        .frame(height: 520, alignment: .top)
    }

    private func nextEgg(_ month: Int, _ l: L) -> some View {
        let progress = store.state.costumeEggTokens
        let rate = CostumeCatalog.tokensPerEgg
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                SpriteView(speciesID: nil, size: 28, egg: .costume(month))
                VStack(alignment: .leading, spacing: 2) {
                    Text(l.costumeEventNow(l.costumeEventName(month))).font(.callout.weight(.semibold))
                    Text(l.costumeEggRule(TokenFormatter.compact(rate))).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            ProgressView(value: Double(progress), total: Double(rate)).tint(CollectionStatsScreen.done)
            Text(l.costumeEggNext(TokenFormatter.compact(rate - progress))).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .designSurface(cornerRadius: Design.cornerRadius)
    }

    /// A month's lot: its month, event, "this month" and count, then its costumed Pokémon.
    private func lot(_ month: Int, owned: (all: Set<String>, shiny: Set<String>), current: Bool, _ l: L) -> some View {
        let entries = CostumeCatalog.lot(month: month)
        let have = entries.filter { owned.all.contains($0.key) }.count
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(l.monthName(month)).font(.subheadline.weight(.semibold))
                Text(l.costumeEventName(month)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if current { Badge(l.costumeNowBadge.uppercased(), tint: .blue, style: .tinted) }
                Spacer(minLength: 4)
                Text("\(have)/\(entries.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 5), alignment: .leading,
                      spacing: 2) {
                ForEach(entries, id: \.key) { entry in
                    cell(entry, owned: owned.all.contains(entry.key), shiny: owned.shiny.contains(entry.key), l)
                }
            }
        }
    }

    /// A costumed Pokémon: in its costume and named once collected, its shape and "???" until then; a shiny one wears
    /// the sparkles too.
    private func cell(_ entry: CostumeEntry, owned: Bool, shiny: Bool, _ l: L) -> some View {
        VStack(spacing: 0) {
            SpriteView(speciesID: entry.speciesID, size: Self.cell, shiny: shiny, form: entry.displayForm,
                       isSilhouette: !owned, sameScale: true)
                .frame(width: Self.cell, height: Self.cell)
                .opacity(owned ? 1 : 0.45)
                .overlay(alignment: .topTrailing) {
                    if shiny {
                        Image(systemName: "sparkles").font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.readableOrange)
                    }
                }
            Group {
                if owned {
                    PokemonNameLabel(.pokemonSpecies, String(entry.speciesID), language: store.language)
                } else {
                    Text("???")
                }
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(owned ? .primary : .secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.9)
        }
        .frame(maxWidth: .infinity)
        .speciesNameTooltip(entry.speciesID, form: entry.form, language: store.language)
    }
}

/// A costumed collection's medal on its Achievements card (`CostumeMedals`): where it stands, then each step, what it
/// gives and whether it is done, ready or ahead, by glyph and color.
@MainActor
struct CostumeMedalPanel: View {
    let store: CompanionStore
    let kind: ItemKind

    var body: some View {
        let l = store.l
        let owned = store.ownedCostumeKeys().all
        let lots = (1...12).filter { month in CostumeCatalog.lot(month: month).allSatisfy { owned.contains($0.key) } }.count
        VStack(alignment: .leading, spacing: 4) {
            Text(kind == .costumeMedal ? l.costumesCollected(owned.count, of: CostumeCatalog.entries.count)
                                       : l.costumeLotsComplete(lots))
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(store.regionTiers(kind), id: \.generation) { step in
                HStack(spacing: 6) {
                    Text(kind == .costumeMedal ? l.costumeMedalStep(step.generation) : l.costumeLotsMedalStep(step.generation))
                        .font(.caption).lineLimit(1)
                    Spacer(minLength: 4)
                    MedalRewards(rewards: kind == .costumeMedal ? CostumeMedals.rewards(step: step.generation)
                                                                : CostumeMedals.lotRewards(step: step.generation), l: l)
                    Image(systemName: step.isDone ? "checkmark.circle.fill" : step.isReady ? "gift.fill" : "circle")
                        .font(.caption)
                        .foregroundStyle(step.isDone ? Design.actionColor : step.isReady ? Color.readableOrange : .secondary)
                }
            }
        }
    }
}
