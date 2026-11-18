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
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                SpriteView(speciesID: nil, size: 30, egg: .costume(egg.month))
                VStack(alignment: .leading, spacing: 3) {
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
        .padding(12)
        .designSurface(cornerRadius: Design.cornerRadius)
    }
}

/// The costumed Pokémon collected (the owner, 2026-11-13): the counts, this month's event and the next Costume Egg,
/// then one month's lot a page (#183), this month's first, twenty Pokémon a page, the ones collected in their costume
/// and named, the others in silhouette. The month's name opens a menu of the months; the pager turns the lot's pages,
/// then the next month's.
@MainActor
struct CostumeCollectionScreen: View {
    let store: CompanionStore
    let onBack: () -> Void
    /// The page shown among every lot's pages, this month's lot first.
    @State private var page = 0

    /// A sprite's size: four rows of five fit under the rings and the event, with their names.
    private static let cell: CGFloat = 40
    /// Costumed Pokémon on a page: four rows of five.
    nonisolated static let pageSize = 20

    /// A page of a month's lot: its month, its place in the lot and the lot's number of pages.
    struct LotPage: Equatable {
        let month: Int
        let index: Int
        let count: Int

        var entries: [CostumeEntry] {
            Paging.slice(CostumeCatalog.lot(month: month), page: index, size: CostumeCollectionScreen.pageSize)
        }
    }

    /// Every lot's pages, from `month`'s lot on, around the year.
    static func pages(from month: Int) -> [LotPage] {
        (0..<12).map { (month - 1 + $0) % 12 + 1 }.flatMap { lotMonth in
            let count = Paging.pageCount(CostumeCatalog.lot(month: lotMonth).count, size: pageSize)
            return (0..<count).map { LotPage(month: lotMonth, index: $0, count: count) }
        }
    }

    /// The first page of `month`'s lot: where the month menu leads.
    static func firstPage(of month: Int, in pages: [LotPage]) -> Int {
        pages.firstIndex { $0.month == month } ?? 0
    }

    var body: some View {
        let l = store.l
        let owned = store.ownedCostumeKeys()
        let month = store.costumeMonth
        let pages = Self.pages(from: month)
        let current = min(max(0, page), pages.count - 1)
        let shown = pages[current]
        let turn = Binding<Int>(get: { current }, set: { page = $0 })
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Button { onBack() } label: { Label(l.back, systemImage: "chevron.left").labelStyle(.titleAndIcon) }
                    .buttonStyle(.borderless)
                    .keyboardShortcut(.cancelAction)
                Spacer(minLength: 4)
                Image(systemName: "theatermasks.fill").foregroundStyle(.secondary)
                Text(l.costumesTitle).font(.headline).lineLimit(1).minimumScaleFactor(0.8)
            }
            HStack(spacing: 4) {
                StatsRing(title: l.costumesTitle, owned: owned.all.count, total: CostumeCatalog.entries.count,
                          color: CollectionStatsScreen.done)
                StatsRing(title: l.dexStatsShinies, owned: owned.shiny.count, total: CostumeCatalog.entries.count,
                          color: CollectionStatsScreen.left)
            }
            .frame(maxWidth: .infinity)
            nextEgg(month, l)
            lotHeader(shown, pages: pages, owned: owned.all, current: shown.month == month, l)
            PagedArea(page: turn, pageCount: pages.count) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 5), alignment: .leading,
                          spacing: 2) {
                    ForEach(shown.entries, id: \.key) { entry in
                        cell(entry, owned: owned.all.contains(entry.key), shiny: owned.shiny.contains(entry.key), l)
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            PageControl(page: turn, pageCount: pages.count, l: l,
                        caption: "\(l.monthName(shown.month)) · \(shown.index + 1) / \(shown.count)")
                .frame(maxWidth: .infinity)
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

    /// The lot's month (its menu), event, "this month" and count.
    private func lotHeader(_ shown: LotPage, pages: [LotPage], owned: Set<String>, current: Bool, _ l: L) -> some View {
        let lot = CostumeCatalog.lot(month: shown.month)
        let have = lot.filter { owned.contains($0.key) }.count
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            monthMenu(shown.month, pages: pages, l)
            Text(l.costumeEventName(shown.month)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            if current { Badge(l.costumeNowBadge.uppercased(), tint: .blue, style: .tinted) }
            Spacer(minLength: 4)
            Text("\(have)/\(lot.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
    }

    /// The month's name, which opens the twelve months to jump to one's lot.
    private func monthMenu(_ month: Int, pages: [LotPage], _ l: L) -> some View {
        Menu {
            ForEach(Array((0..<12).map { (store.costumeMonth - 1 + $0) % 12 + 1 }), id: \.self) { choice in
                Button { page = Self.firstPage(of: choice, in: pages) } label: {
                    HStack {
                        Text("\(l.monthName(choice)) · \(l.costumeEventName(choice))")
                        if choice == month { Image(systemName: "checkmark") }
                    }
                }
            }
        } label: {
            Text(l.monthName(month)).font(.subheadline.weight(.semibold))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.visible)
        .fixedSize()
        .hoverTip(l.costumeChooseMonth)
        .accessibilityLabel(l.costumeChooseMonth)
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
