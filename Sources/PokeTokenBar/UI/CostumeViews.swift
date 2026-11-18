import SwiftUI

/// A Costume Egg in the Bag (the owner, 2026-11-13): its month's event egg, the costumed Pokémon it holds shown beside
/// it, used as the Shop's eggs are.
@MainActor
struct CostumeEggCard: View {
    let store: CompanionStore
    let nav: PopoverNavigation
    let egg: CostumeEgg

    var body: some View {
        let l = store.l
        let name = l.costumeEggName(egg.month)
        VStack(alignment: .leading, spacing: Design.productCardSpacing) {
            HStack(alignment: .center, spacing: 10) {
                SpriteView(speciesID: nil, size: 30, egg: .costume(egg.month))
                VStack(alignment: .leading, spacing: Design.productTextSpacing) {
                    Text(name).font(.callout.weight(.semibold)).lineLimit(1)
                    HStack(spacing: 4) {
                        SpriteView(speciesID: egg.speciesID, size: 22, form: egg.entry?.displayForm, sameScale: true)
                        PokemonNameLabel(items: [PokemonNameItem(resource: PokemonNameResource(kind: .pokemonSpecies,
                                                                                               name: String(egg.speciesID)))],
                                         language: store.language)
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    if store.hasActive {
                        Text(l.eggReleaseNote).font(.caption2).foregroundStyle(.tertiary)
                            .lineSpacing(Design.productLineSpacing)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            ReleaseForEggControls(store: store, nav: nav, detail: "", actionTitle: l.useItem,
                                  isAvailable: store.canUseCostumeEgg(egg.id), unavailableText: l.useNeedsPokemon,
                                  confirmText: l.stoneConfirm(store.displayName, name),
                                  lockedHint: store.isRaisingFossilEggPokemon ? l.fossilEggInProgress : nil) {
                store.useCostumeEgg(egg.id)
            }
        }
        .productCard()
    }
}

/// The costumed Pokémon collected (the owner, 2026-11-13): the counts, this month's event and the next Costume Egg,
/// then each month's lot, this month's first, the ones collected in their costume, the others in silhouette.
@MainActor
struct CostumeCollectionScreen: View {
    let store: CompanionStore
    let onBack: () -> Void

    private static let cell: CGFloat = 44

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
                        StatsRing(title: l.dexStatsShinies, owned: owned.shiny.count, total: CostumeCatalog.entries.count,
                                  color: CollectionStatsScreen.left)
                    }
                    .frame(maxWidth: .infinity)
                    nextEgg(month, l)
                    ForEach(Array((0..<12).map { (month - 1 + $0) % 12 + 1 }), id: \.self) { lotMonth in
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
        return VStack(alignment: .leading, spacing: 6) {
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
        .padding(10)
        .designSurface(cornerRadius: Design.cornerRadius)
    }

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
            LazyVGrid(columns: [GridItem(.adaptive(minimum: Self.cell, maximum: Self.cell), spacing: 4)],
                      alignment: .leading, spacing: 4) {
                ForEach(entries, id: \.key) { entry in
                    let isOwned = owned.all.contains(entry.key)
                    SpriteView(speciesID: entry.speciesID, size: Self.cell - 4, shiny: owned.shiny.contains(entry.key),
                               form: entry.displayForm, isSilhouette: !isOwned, sameScale: true)
                        .frame(width: Self.cell, height: Self.cell)
                        .opacity(isOwned ? 1 : 0.45)
                        .speciesNameTooltip(entry.speciesID, form: entry.form, language: store.language)
                }
            }
        }
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
                        .font(.caption)
                    Spacer(minLength: 4)
                    let rewards = kind == .costumeMedal ? CostumeMedals.rewards(step: step.generation)
                                                        : CostumeMedals.lotRewards(step: step.generation)
                    ForEach(Array(rewards.enumerated()), id: \.offset) { _, reward in
                        HStack(spacing: 1) {
                            ItemIconView(kind: reward.kind, size: 16)
                            if reward.count > 1 { Text("×\(reward.count)").font(.caption2).monospacedDigit() }
                        }
                        .hoverTip(l.itemName(reward.kind))
                    }
                    Image(systemName: step.isDone ? "checkmark.circle.fill" : step.isReady ? "gift.fill" : "circle")
                        .font(.caption)
                        .foregroundStyle(step.isDone ? Design.actionColor : step.isReady ? Color.readableOrange : .secondary)
                }
            }
        }
    }
}
