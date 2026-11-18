import SwiftUI

/// A dungeon's egg in the Bag (Q20 B): named by the Pokémon it hatches, shiny when it was, used as the Shop's eggs are.
@MainActor
struct DungeonEggCard: View {
    let store: CompanionStore
    let nav: PopoverNavigation
    let egg: DungeonEgg

    var body: some View {
        let l = store.l
        let name = DungeonEggTitle.text(egg.baseID, l: l, language: store.language, secret: egg.isSecret == true)
        VStack(alignment: .leading, spacing: Design.productCardSpacing) {
            HStack(alignment: .center, spacing: 10) {
                SpriteView(speciesID: nil, size: 30, egg: egg.eggKind)
                VStack(alignment: .leading, spacing: Design.productTextSpacing) {
                    DungeonEggTitle(speciesID: egg.baseID, l: l, language: store.language, secret: egg.isSecret == true)
                        .font(.callout.weight(.semibold)).lineLimit(1)
                    if egg.isShiny { Badge("✦ " + l.dungeonEggShiny.uppercased(), tint: .orange, style: .tinted) }
                    if store.hasActive {
                        Text(l.eggReleaseNote).font(.caption2).foregroundStyle(.tertiary)
                            .lineSpacing(Design.productLineSpacing)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            ReleaseForEggControls(store: store, nav: nav, detail: "", actionTitle: l.useItem,
                                  isAvailable: store.canUseDungeonEgg(egg.id), unavailableText: l.useNeedsPokemon,
                                  confirmText: l.stoneConfirm(store.displayName, name),
                                  lockedHint: store.isRaisingFossilEggPokemon ? l.fossilEggInProgress : nil) {
                store.useDungeonEgg(egg.id)
            }
        }
        .productCard()
    }
}

/// "Mewtwo Egg" in the player's language: the Pokémon's name loaded as `PokemonNameLabel` loads it, "…" until then.
@MainActor
struct DungeonEggTitle: View {
    let speciesID: Int
    let l: L
    let language: AppLanguage
    var secret = false
    var displayStore = PokemonNameDisplayStore.shared

    static func text(_ speciesID: Int, l: L, language: AppLanguage, secret: Bool = false,
                     names: PokemonNameDisplayStore.Names = PokemonNameDisplayStore.shared.names) -> String {
        let item = PokemonNameItem(resource: PokemonNameResource(kind: .pokemonSpecies, name: String(speciesID)))
        let name = PokemonNameText(items: [item], language: language, names: names).text
        return secret ? l.secretEggOf(name) : l.eggOf(name)
    }

    var body: some View {
        let resource = PokemonNameResource(kind: .pokemonSpecies, name: String(speciesID))
        Text(Self.text(speciesID, l: l, language: language, secret: secret, names: displayStore.names))
            .task(id: resource) {
                if displayStore.names[resource] == nil { _ = await displayStore.load(resource, provider: PokemonNameClient.shared) }
            }
    }
}

/// Under a dungeon item in the Bag: a Capsule opens its screen, a chest opens, the rest waits for the dungeons.
@MainActor
struct DungeonItemControls: View {
    let store: CompanionStore
    let nav: PopoverNavigation
    let kind: ItemKind
    let openChest: () -> Void

    var body: some View {
        let l = store.l
        HStack(spacing: 6) {
            switch kind {
            case .silverCapsule, .goldCapsule, .mint:
                if kind == .mint ? store.mintCandidates.isEmpty : store.capsuleCandidates.isEmpty {
                    Text(kind == .mint ? l.mintNoTarget : l.dungeonNoCapsuleTarget).font(.caption2).foregroundStyle(.tertiary)
                } else {
                    Text(store.effectHint(for: kind)).font(.caption2).foregroundStyle(.tertiary).monospacedDigit()
                    Spacer()
                    Button(l.useItem) { nav.capsule = kind }.buttonStyle(.pill(prominent: true))
                }
            case .explorerChest:
                Text(store.effectHint(for: kind)).font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                Button(l.dungeonOpen, action: openChest).buttonStyle(.pill(prominent: true))
            default:
                Image(systemName: "map.fill").font(.caption2).foregroundStyle(.secondary)
                Text(kind == .treasureMap || kind == .legendaryKey
                     ? l.dungeonItemHint : l.dungeonItemHint + " · " + store.effectHint(for: kind))
                    .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
            }
        }
    }
}

/// A Capsule or a Mint used on a graduated Pokémon: pick it, then the IV (Silver), all of them (Gold) or a new nature at
/// random (Mint, again as long as Mints are left).
@MainActor
struct CapsuleScreen: View {
    let store: CompanionStore
    let kind: ItemKind
    let onBack: () -> Void
    @State private var selected: String?
    /// A Gold Capsule used: all six at 31.
    @State private var raised = false
    /// The IV a Silver Capsule last raised: the buttons stay for the others while Capsules are left (the owner,
    /// 2026-11-12: they went after one, and the screen had to be left and opened again).
    @State private var lastRaised: Int?
    @State private var search = ""
    @State private var shinyOnly = false
    @State private var favoritesOnly = false
    @State private var sort: CompanionStore.CapsuleSortOption = .strongest
    /// The Mint's last change on the Pokémon picked.
    @State private var mintChange: (from: PokemonNature?, to: PokemonNature)?

    var body: some View {
        let l = store.l
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Button {
                    // Back to the list from a Pokémon, whatever was used on it: another one may come next.
                    if selected != nil {
                        selected = nil
                        mintChange = nil
                        raised = false
                        lastRaised = nil
                    } else {
                        onBack()
                    }
                } label: {
                    Label(l.back, systemImage: "chevron.left").labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
                Spacer(minLength: 4)
                ItemIconView(kind: kind, size: 20)
                Text(l.itemName(kind)).font(.headline)
                Text("×\(store.itemCount(kind))").font(.caption.weight(.bold)).foregroundStyle(.secondary).monospacedDigit()
            }
            Text(l.itemDescription(kind)).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let id = selected, let entry = store.state.dex.first(where: { $0.id == id }) {
                if kind == .mint { mintDetail(entry, l) } else { detail(entry, l) }
            } else {
                Text(l.dungeonCapsulePick).font(.caption.weight(.semibold))
                toolbar(l)
                let shown = store.itemTargets(kind, query: search, shinyOnly: shinyOnly, favoritesOnly: favoritesOnly,
                                              sort: sort)
                if shown.isEmpty {
                    noResult(l)
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 62), spacing: 6)], spacing: 6) {
                            ForEach(shown) { entry in
                                if kind != .mint, CompanionStore.hasAllIVsMaxed(entry) {
                                    // Nothing left to raise: shown greyed, its reason under the pointer.
                                    cell(entry, maxed: true)
                                } else {
                                    Button { selected = entry.id } label: { cell(entry) }
                                        .buttonStyle(.plain)
                                }
                            }
                        }
                        .reservesScrollerLane()
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(PopoverMetrics.padding)
        .frame(height: 520, alignment: .top)
    }

    private func total(_ entry: DexEntry) -> Int { CompanionStore.ivTotal(entry) }

    /// The Pokédex's search, its shiny filter and a sort of the Capsule's own, its choice written beside the arrows.
    private func toolbar(_ l: L) -> some View {
        HStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.system(size: 13))
                TextField(l.dexSearchPlaceholder, text: $search).textFieldStyle(.plain).font(.system(size: 13))
                if !search.isEmpty {
                    Button { search = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary).font(.system(size: 13))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(l.clearFilters)
                }
            }
            .modifier(CapsuleFilterChip(active: false, tint: .secondary))
            Button { shinyOnly.toggle() } label: {
                Image(systemName: shinyOnly ? "sparkles" : "sparkle")
                    .font(.system(size: 13, weight: shinyOnly ? .bold : .regular))
                    .foregroundStyle(shinyOnly ? Color.yellow : Color.secondary)
                    .frame(width: 16, height: 16)
                    .modifier(CapsuleFilterChip(active: shinyOnly, tint: .yellow))
            }
            .buttonStyle(.plain)
            .hoverTip(l.filterShinyOnly)
            .accessibilityLabel(l.filterShinyOnly)
            Button { favoritesOnly.toggle() } label: {
                // Filled or not says it, not the pink alone.
                Image(systemName: favoritesOnly ? "heart.fill" : "heart")
                    .font(.system(size: 12, weight: favoritesOnly ? .bold : .regular))
                    .foregroundStyle(favoritesOnly ? Color.pink : Color.secondary)
                    .frame(width: 16, height: 16)
                    .modifier(CapsuleFilterChip(active: favoritesOnly, tint: .pink))
            }
            .buttonStyle(.plain)
            .hoverTip(l.filterFavoritesOnly)
            .accessibilityLabel(l.filterFavoritesOnly)
            .accessibilityAddTraits(favoritesOnly ? .isSelected : [])
            Menu {
                ForEach(CompanionStore.sortOptions(for: kind)) { option in
                    Button { sort = option } label: {
                        HStack {
                            Text(l.label(for: option))
                            if sort == option { Image(systemName: "checkmark") }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.arrow.down").font(.system(size: 12))
                    Text(l.label(for: sort)).font(.system(size: 12)).lineLimit(1)
                }
                .foregroundStyle(Color.secondary)
                .modifier(CapsuleFilterChip(active: false, tint: .secondary))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .hoverTip(l.sortTitle)
            .accessibilityLabel(l.sortTitle)
        }
    }

    private func noResult(_ l: L) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 24)).foregroundStyle(.tertiary)
            Text(l.noSearchResults).font(.callout.weight(.medium)).foregroundStyle(.secondary)
            Button(l.clearFilters) { search = ""; shinyOnly = false; favoritesOnly = false }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    @ViewBuilder
    private func cell(_ entry: DexEntry, maxed: Bool = false) -> some View {
        let content = VStack(spacing: 2) {
            SpriteView(speciesID: entry.finalID, size: 40, shiny: entry.isShiny, form: entry.form, isSilhouette: false,
                       sameScale: true)
                .opacity(maxed ? 0.35 : 1)
                .overlay(alignment: .topTrailing) {
                    if store.isFavorite(entry) {
                        Image(systemName: "heart.fill").font(.system(size: 9)).foregroundStyle(Color.pink)
                            .accessibilityLabel(store.l.favoriteLabel)
                    }
                }
            Text(kind == .mint ? entry.nature.map { $0.name(store.language) } ?? "?" : "\(total(entry))/186")
                .font(.caption2).foregroundStyle(maxed ? .tertiary : .secondary).monospacedDigit().lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .designSurface(cornerRadius: 10)
        .opacity(maxed ? 0.6 : 1)
        if maxed {
            content.contentShape(Rectangle()).hoverTip(store.l.dungeonCapsuleAllMaxed)
        } else {
            content.speciesNameTooltip(entry.finalID, form: entry.form, language: store.language)
        }
    }

    @ViewBuilder
    private func detail(_ entry: DexEntry, _ l: L) -> some View {
        let ivs = entry.profile?.ivs
        HStack(spacing: 10) {
            SpriteView(speciesID: entry.finalID, size: 56, shiny: entry.isShiny, form: entry.form, sameScale: true)
            VStack(alignment: .leading, spacing: 2) {
                PokemonNameLabel(.pokemonSpecies, String(entry.finalID), language: store.language).font(.headline)
                Text("IV \(total(entry))/186").font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        let left = store.itemCount(kind) > 0
        if raised {
            Label(l.dungeonCapsuleDone, systemImage: "checkmark.seal.fill")
                .font(.callout.weight(.semibold)).foregroundStyle(Design.actionColor)
        } else if kind == .silverCapsule {
            if let lastRaised {
                Label(l.dungeonCapsuleStatRaised(l.statLabel(PokemonStatCalculator.order[lastRaised])),
                      systemImage: "checkmark.seal.fill")
                    .font(.callout.weight(.semibold)).foregroundStyle(Design.actionColor)
            }
            if CompanionStore.hasAllIVsMaxed(entry) {
                Text(l.dungeonCapsuleAllMaxed).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            } else if left {
                Text(l.dungeonCapsulePickStat).font(.caption.weight(.semibold))
            } else {
                Text(l.dungeonCapsuleNoneLeft(l.itemName(kind))).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
        }
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(PokemonStatCalculator.order.enumerated()), id: \.offset) { index, name in
                let value = ivs?[keyPath: CompanionStore.ivKeyPaths[index]] ?? 0
                HStack(spacing: 8) {
                    Text(l.statLabel(name)).font(.caption).frame(width: 70, alignment: .leading)
                    Text("\(value)").font(.caption.weight(.semibold)).monospacedDigit().frame(width: 22, alignment: .trailing)
                    ExpeditionBar(value: Double(value) / 31, color: value == 31 ? Design.actionColor : .secondary, height: 5)
                    if kind == .silverCapsule, left {
                        Button("→ 31") { if store.useCapsule(kind, on: entry.id, stat: index) { lastRaised = index } }
                            .buttonStyle(.pill())
                            .disabled(value >= 31)
                            .opacity(value >= 31 ? 0 : 1)
                    }
                }
            }
        }
        if kind == .goldCapsule, !raised {
            HStack {
                Spacer()
                Button(l.dungeonCapsuleRaiseAll) { raised = store.useCapsule(kind, on: entry.id) }
                    .buttonStyle(.pill(prominent: true))
            }
        }
    }

    /// A Mint on the Pokémon picked: its nature and what it raises and lowers, a new one at random on each Mint.
    @ViewBuilder
    private func mintDetail(_ entry: DexEntry, _ l: L) -> some View {
        HStack(spacing: 10) {
            SpriteView(speciesID: entry.finalID, size: 56, shiny: entry.isShiny, form: entry.form, sameScale: true)
            VStack(alignment: .leading, spacing: 3) {
                PokemonNameLabel(.pokemonSpecies, String(entry.finalID), language: store.language).font(.headline)
                if let nature = entry.nature {
                    HStack(spacing: 6) {
                        NatureBadge(nature: nature, language: store.language)
                        Text(Self.effect(of: nature, l)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        if let change = mintChange {
            Label(l.mintChanged(change.from?.name(store.language), change.to.name(store.language)),
                  systemImage: "leaf.fill")
                .font(.callout.weight(.semibold)).foregroundStyle(Design.actionColor)
        }
        if store.itemCount(.mint) > 0 {
            HStack {
                Spacer()
                Button(l.mintUse) { mintChange = store.useMint(on: entry.id) }
                    .buttonStyle(.pill(prominent: true))
            }
        }
    }

    /// "+Speed −Sp. Def", or that the nature changes nothing.
    static func effect(of nature: PokemonNature, _ l: L) -> String {
        let stats = PokemonStatCalculator.order.dropFirst()
        guard let up = stats.first(where: { nature.modifier(for: $0) > 1 }),
              let down = stats.first(where: { nature.modifier(for: $0) < 1 }) else { return l.natureNeutral }
        return "+\(l.statLabel(up)) −\(l.statLabel(down))"
    }
}

/// A Dungeons medal's steps on its Achievements card: each dungeon of the tier, then the whole tier, with what it
/// gives and where it stands (claimed, ready, still to win), by glyph and color.
@MainActor
struct DungeonMedalPanel: View {
    let store: CompanionStore
    let tier: DungeonTier

    var body: some View {
        let l = store.l
        let dungeons = DungeonMedals.dungeons(tier)
        VStack(alignment: .leading, spacing: 4) {
            ForEach(store.regionTiers(DungeonMedals.medal(tier)), id: \.generation) { step in
                HStack(spacing: 6) {
                    if step.generation <= dungeons.count {
                        DungeonIcon(id: dungeons[step.generation - 1], size: 20)
                    } else {
                        Image(systemName: "crown.fill").font(.caption).frame(width: 20)
                    }
                    Text(l.medalStepName(tier, step: step.generation)).font(.caption).lineLimit(1)
                    Spacer(minLength: 4)
                    MedalRewards(rewards: DungeonMedals.rewards(tier, step: step.generation), l: l)
                    Image(systemName: step.isDone ? "checkmark.circle.fill" : step.isReady ? "gift.fill" : "circle")
                        .font(.caption)
                        .foregroundStyle(step.isDone ? Design.actionColor : step.isReady ? Color.readableOrange : .secondary)
                }
            }
        }
    }
}

/// A medal step's rewards (#183): each icon at 24 pt with its name and count, or the icons alone, named on hover,
/// where the names leave no room (two rewards in a long language).
@MainActor
struct MedalRewards: View {
    let rewards: [(kind: ItemKind, count: Int)]
    let l: L

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(named: true)
            row(named: false)
        }
    }

    private func row(named: Bool) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(rewards.enumerated()), id: \.offset) { _, reward in
                HStack(spacing: 3) {
                    ItemIconView(kind: reward.kind, size: 24)
                    if named {
                        Text(l.itemName(reward.kind)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    if reward.count > 1 { Text("×\(reward.count)").font(.caption2).monospacedDigit() }
                }
                .fixedSize()
                .hoverTip(l.itemName(reward.kind))
            }
        }
    }
}

/// A battle form's name in the player's language ("Mega Charizard X"), its species' name loaded as `PokemonNameLabel`
/// loads it, "…" until then; `wrap` sets it in a sentence.
@MainActor
struct BattleFormTitle: View {
    let form: BattleForm
    let language: AppLanguage
    var wrap: (String) -> String = { $0 }
    var displayStore = PokemonNameDisplayStore.shared

    static func text(_ form: BattleForm, language: AppLanguage,
                     names: PokemonNameDisplayStore.Names = PokemonNameDisplayStore.shared.names) -> String {
        let item = PokemonNameItem(resource: PokemonNameResource(kind: .pokemonSpecies, name: String(form.speciesID)))
        let species = PokemonNameText(items: [item], language: language, names: names).text
        return PokemonForm.displayName(species, speciesID: form.speciesID, form: form.form, language: language)
    }

    var body: some View {
        let resource = PokemonNameResource(kind: .pokemonSpecies, name: String(form.speciesID))
        Text(wrap(Self.text(form, language: language, names: displayStore.names)))
            .task(id: resource) {
                if displayStore.names[resource] == nil { _ = await displayStore.load(resource, provider: PokemonNameClient.shared) }
            }
    }
}

/// The Battle Forms Medal's steps on its Achievements card: how many forms each asks for, what it gives, where it
/// stands, by glyph and color.
@MainActor
struct BattleFormsMedalPanel: View {
    let store: CompanionStore

    var body: some View {
        let l = store.l
        let won = store.dungeonProgress.battleForms.count
        VStack(alignment: .leading, spacing: 4) {
            Text(l.battleFormsWon(won, of: BattleForms.all.count)).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(store.regionTiers(.battleFormsMedal), id: \.generation) { step in
                HStack(spacing: 6) {
                    Text(l.battleFormsMedalStep(step.generation)).font(.caption).lineLimit(1)
                    Spacer(minLength: 4)
                    MedalRewards(rewards: BattleFormsMedal.rewards(step: step.generation), l: l)
                    Image(systemName: step.isDone ? "checkmark.circle.fill" : step.isReady ? "gift.fill" : "circle")
                        .font(.caption)
                        .foregroundStyle(step.isDone ? Design.actionColor : step.isReady ? Color.readableOrange : .secondary)
                }
            }
        }
    }
}

/// The Pokédex toolbar's look for the Capsule screen's search, filter and sort: tinted while it narrows the list.
@MainActor
struct CapsuleFilterChip: ViewModifier {
    let active: Bool
    let tint: Color

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(active ? tint.opacity(0.18) : Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .strokeBorder(active ? tint.opacity(0.6) : Color.secondary.opacity(0.2), lineWidth: 0.5))
    }
}
