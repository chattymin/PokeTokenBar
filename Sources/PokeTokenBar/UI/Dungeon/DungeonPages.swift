import SwiftUI

/// The general team (a player, 2026-11-05): six graduated Pokémon at most, their moves and battle forms set here; a
/// dungeon's team screen starts from it (`CompanionStore.startingTeam`).
@MainActor
struct MyTeamScreen: View {
    let store: CompanionStore
    let onBack: () -> Void

    @State private var team: [String] = []
    @State private var focus: String?
    @State private var editingSlot: Int?
    @State private var search = ""
    @State private var loaded = false

    static let size = 6

    var body: some View {
        let l = store.l
        let picked = team.compactMap { id in store.dungeonCandidates.first { $0.id == id } }
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Button { onBack() } label: { Label(l.back, systemImage: "chevron.left").labelStyle(.titleAndIcon) }
                    .buttonStyle(.borderless)
                    .keyboardShortcut(.cancelAction)
                Spacer(minLength: 4)
                Image(systemName: "person.3.fill").foregroundStyle(.secondary)
                Text(l.myTeamTitle).font(.headline)
            }
            Text(l.myTeamHint).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TeamMemberRow(store: store, picked: picked, size: Self.size, dungeon: nil, team: $team, focus: $focus,
                          editingSlot: $editingSlot)
            if let focused = focus, let entry = picked.first(where: { $0.id == focused }) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Button(l.dungeonMemberDone, systemImage: "chevron.left") {
                            focus = nil
                            editingSlot = nil
                        }
                        .buttonStyle(.borderless).font(.caption.weight(.semibold))
                        Spacer(minLength: 0)
                        Button(l.dungeonRemove, systemImage: "minus.circle") {
                            team.removeAll { $0 == entry.id }
                            focus = nil
                            editingSlot = nil
                        }
                        .buttonStyle(.borderless).controlSize(.small).font(.caption)
                    }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            if !store.wonBattleForms(speciesID: entry.finalID).isEmpty {
                                BattleFormChooser(store: store, entry: entry)
                            }
                            LoopEditor(store: store, entry: entry, dungeon: nil, editingSlot: $editingSlot)
                        }
                        .reservesScrollerLane()
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
            } else {
                TextField(l.dexSearchPlaceholder, text: $search)
                    .textFieldStyle(.roundedBorder).controlSize(.small)
                ScrollView {
                    TeamCandidateList(store: store, dungeon: nil, faced: [], rules: [], size: Self.size, query: search,
                                      team: $team, focus: $focus)
                        .reservesScrollerLane()
                }
                .frame(minHeight: 46)
            }
        }
        .padding(PopoverMetrics.padding)
        .frame(height: 520, alignment: .top)
        .onAppear {
            team = store.savedTeam
            loaded = true
        }
        .onChange(of: team) { _, new in if loaded { store.setSavedTeam(new) } }
    }
}

/// A dungeon's page (a player, 2026-11-05), in the Pokémon page's look (issue #181, the owner's choice A, 2026-11-16):
/// the dungeon as a hero card, then cards under small capital titles, its bosses as named portraits, its loot as item
/// tiles, its two paths with the odds folded away, the expeditions that ended there, its wild Pokémon.
@MainActor
struct DungeonDetailScreen: View {
    let store: CompanionStore
    let nav: PopoverNavigation
    let id: DungeonID
    let onBack: () -> Void
    let onPrepare: () -> Void
    @State private var showsOdds = false
    @State private var showsAllWild = false

    /// The wild Pokémon shown before "See all".
    private static let wildShown = 16

    var body: some View {
        let l = store.l
        let dungeon = DungeonCatalog.dungeon(id)
        let runs = store.runs(of: id)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Button { onBack() } label: { Label(l.back, systemImage: "chevron.left").labelStyle(.titleAndIcon) }
                    .buttonStyle(.borderless)
                    .keyboardShortcut(.cancelAction)
                Spacer(minLength: 4)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    hero(dungeon, l)
                    bosses(dungeon, l)
                    loot(dungeon, l)
                    floors(dungeon, l)
                    record(runs, l)
                    // Last: a T2 or later brings a hundred and more.
                    wild(dungeon, l)
                }
                .reservesScrollerLane()
            }
            HStack {
                Spacer()
                Button(l.dungeonPrepare) { onPrepare() }
                    .buttonStyle(.pill(prominent: true))
                    .disabled(!store.isDungeonOpen(id))
            }
        }
        .padding(PopoverMetrics.padding)
        .frame(height: 520, alignment: .top)
    }

    private func title(_ text: String, trailing: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text.uppercased()).font(.system(size: 10, weight: .bold, design: .rounded)).tracking(0.6).foregroundStyle(.secondary)
            Spacer(minLength: 4)
            if let trailing { Text(trailing).font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
        }
    }

    /// Its identity, as the Pokémon's: the diorama large, the tier, the name, the types, what the team must be, what
    /// opens it while it is closed, how often it was finished.
    private func hero(_ dungeon: Dungeon, _ l: L) -> some View {
        let (size, rules) = store.teamRules(id)
        let wins = store.dungeonProgress.wins(id)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                DungeonIcon(id: id, size: 92, animated: true)
                    .frame(width: 100, height: 100)
                    .background(alignment: .bottom) {
                        Ellipse().fill(Color.black.opacity(0.22)).frame(width: 70, height: 12).blur(radius: 2)
                    }
                VStack(alignment: .leading, spacing: 5) {
                    Badge("T\(dungeon.tier.rawValue)", tint: .secondary).fixedSize()
                    Text(l.dungeonName(id)).font(.system(size: 18, weight: .bold, design: .rounded))
                        .lineLimit(2).minimumScaleFactor(0.85).fixedSize(horizontal: false, vertical: true)
                    if !dungeon.themeTypes.isEmpty {
                        HStack(spacing: 3) {
                            ForEach(dungeon.themeTypes, id: \.self) { type in
                                Badge(l.typeName(type).uppercased(), tint: .type(type)).fixedSize()
                            }
                        }
                    }
                    Text(([l.dungeonFloors(dungeon.floors), l.dungeonTeamSize(size)] + rules.map(l.dungeonRule)).joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if wins > 0 {
                        Label(l.dungeonWins(wins), systemImage: "checkmark.seal.fill").font(.caption.weight(.semibold))
                            .foregroundStyle(Design.actionColor)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // What opens it, while it is closed.
            if wins == 0 {
                ForEach(Array(dungeon.unlocks.enumerated()), id: \.offset) { _, unlock in
                    let met = store.isMet(unlock)
                    Label(store.unlockLine(unlock), systemImage: met ? "checkmark.circle.fill" : "lock.fill")
                        .font(.caption).foregroundStyle(met ? .primary : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .heroCard(colors: DungeonCard.colors(id))
    }

    static func factorName(_ source: CompanionStore.GrowthFactor.Source, _ l: L) -> String {
        switch source {
        case .repeatBoost: l.bonusRepeat
        case .badges: l.collectorGroupTitle(.gymBadges)
        case .item(let kind): l.itemName(kind)
        }
    }

    /// The bosses as the evolution line shows a family (Q17, #137): a portrait each, whole once caught here, a
    /// silhouette once met, a "?" before; its name under it.
    private func bosses(_ dungeon: Dungeon, _ l: L) -> some View {
        let slots = BossSlots(store: store, id: id, dungeon: dungeon, size: 44, shownAtMost: 12)
        let caught = dungeon.bosses.filter { store.dungeonProgress.caughtInDungeon(id, $0) }.count
        return VStack(alignment: .leading, spacing: 8) {
            title(l.dungeonBossesTitle, trailing: l.dungeonBossesCaught(caught, of: dungeon.bosses.count))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 8) {
                ForEach(Array(slots.slots.enumerated()), id: \.offset) { _, slot in bossPortrait(slot, l) }
            }
            if slots.hidden > 0 {
                Text("+\(slots.hidden)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
        }
        .designCard()
    }

    private func bossPortrait(_ slot: BossSlots.Slot, _ l: L) -> some View {
        VStack(spacing: 3) {
            slot.view(size: 44, language: store.language)
                .frame(width: 54, height: 54)
                .background(Circle().fill(Color.black.opacity(0.18)))
            switch slot {
            case .met(let species, let caught, _):
                HStack(spacing: 3) {
                    Image(systemName: caught ? "checkmark.circle.fill" : "eye.fill").font(.system(size: 9))
                        .foregroundStyle(caught ? Design.actionColor : .secondary)
                    PokemonNameLabel(.pokemonSpecies, String(species), language: store.language)
                        .font(.system(size: 10, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                }
                .hoverTip(caught ? l.dungeonBossCaughtHere : l.dungeonBossMetNotCaught)
            case .unknown:
                Text(l.dungeonBossNotMet).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// What it gives as the Bag shows items, from the rolls' own tables: an icon each with how many or how often (a box
    /// for a chest's, a crown for the boss's), the chests' items in a row, what a first victory adds.
    private func loot(_ dungeon: Dungeon, _ l: L) -> some View {
        let tier = dungeon.tier
        let candies = ExpeditionEngine.candyRange(tier)
        let items = ExpeditionEngine.itemTable(tier).reduce(into: [ItemKind]()) { if !$0.contains($1) { $0.append($1) } }
        let eggs = ExpeditionEngine.chestEggOdds(tier)
        let extras = CompanionStore.victoryExtraOdds(tier)
        var tiles: [(kind: ItemKind?, name: String, value: String, symbol: String?, hint: String)] = [
            (.rareCandy, l.itemName(.rareCandy), l.dungeonRange(candies.lowerBound, candies.upperBound), nil,
             l.dungeonDetailCandies(candies.lowerBound, candies.upperBound)),
        ]
        tiles += eggs.map { ($0.egg, l.itemName($0.egg), l.oddsPercent(Double($0.perMille) / 10), "shippingbox.fill", l.dungeonDetailChestEggs) }
        tiles += extras.map { ($0.item, l.itemName($0.item), l.oddsPercent($0.percent), "crown.fill", l.dungeonDetailVictory) }
        tiles.append((nil, l.dungeonTechnicalCapsule, l.oddsPercent(Double(CompanionStore.technicalCapsuleChance(tier))),
                      "crown.fill", l.dungeonDetailVictory))
        return VStack(alignment: .leading, spacing: 8) {
            title(l.dungeonLootTitle)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                ForEach(Array(tiles.enumerated()), id: \.offset) { _, tile in
                    VStack(spacing: 3) {
                        if let kind = tile.kind {
                            ItemIconView(kind: kind, size: 26)
                        } else {
                            Image(systemName: "opticaldisc.fill").font(.system(size: 18)).foregroundStyle(.secondary).frame(height: 26)
                        }
                        Text(tile.name).font(.system(size: 10, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.65)
                        HStack(spacing: 2) {
                            if let symbol = tile.symbol { Image(systemName: symbol).font(.system(size: 8)) }
                            Text(tile.value).font(.system(size: 10)).monospacedDigit()
                        }
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6).padding(.horizontal, 2).frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Color.black.opacity(0.16)))
                    .hoverTip(tile.hint)
                }
            }
            title(l.dungeonDetailChestItems)
            HStack(spacing: 8) {
                ForEach(items, id: \.self) { kind in ItemIconView(kind: kind, size: 24).hoverTip(l.itemName(kind)) }
            }
            Label(l.dungeonDetailFirstVictory, systemImage: "star.fill").font(.caption.weight(.semibold))
                .foregroundStyle(Color.yellow).fixedSize(horizontal: false, vertical: true)
        }
        .designCard()
    }

    /// Its floors: the two paths as the die gives them, what a floor holds on each folded away (the owner, 2026-11-06:
    /// nothing said what they change).
    private func floors(_ dungeon: Dungeon, _ l: L) -> some View {
        let safe = ExpeditionEngine.eventOdds(tier: dungeon.tier, risky: false)
        let risky = ExpeditionEngine.eventOdds(tier: dungeon.tier, risky: true)
        return VStack(alignment: .leading, spacing: 8) {
            title(l.dungeonFloorsTitle, trailing: "\(dungeon.floors)")
            HStack(spacing: 6) {
                path(risky: false, l)
                path(risky: true, l)
            }
            Button {
                withAnimation(.easeOut(duration: 0.15)) { showsOdds.toggle() }
            } label: {
                Label(l.dungeonOddsToggle(open: showsOdds), systemImage: showsOdds ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.semibold)).foregroundStyle(Design.actionColor)
            }
            .buttonStyle(.plain)
            if showsOdds {
                Text(l.dungeonPathRule).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 3) {
                    ForEach(Array(safe.enumerated()), id: \.offset) { i, item in
                        GridRow {
                            Text(l.dungeonEventName(item.kind)).font(.caption)
                            Text(l.oddsPercent(item.percent)).font(.caption).monospacedDigit().foregroundStyle(Design.actionColor)
                                .gridColumnAlignment(.trailing)
                            Text(l.oddsPercent(risky[i].percent))
                                .font(.caption.weight(risky[i].percent > item.percent + 0.5 ? .bold : .regular)).monospacedDigit()
                                .foregroundStyle(Color.readableOrange).gridColumnAlignment(.trailing)
                        }
                    }
                }
                // #141: on top of the floor's event, on either path.
                if dungeon.tier >= .t2, !id.isChallenge {
                    Label(l.dungeonSecretRule, systemImage: "door.left.hand.open").font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .designCard()
    }

    /// A path, by name, glyph and color: blue the safe one, orange the risky one.
    private func path(risky: Bool, _ l: L) -> some View {
        let color = risky ? Color.readableOrange : Design.actionColor
        return HStack(spacing: 6) {
            Image(systemName: risky ? "dice.fill" : "dice").font(.system(size: 16, weight: .bold)).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 1) {
                Text(l.dungeonPath(risky: risky)).font(.system(size: 11, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
                Text(l.dungeonPathShort(risky: risky)).font(.system(size: 10)).foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.65)
            }
        }
        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 9).fill(color.opacity(0.14)))
    }

    /// The expeditions that ended there: four numbers, what speeds it up, then each run.
    private func record(_ runs: [DungeonRunRecord], _ l: L) -> some View {
        let best = runs.map(\.floor).max() ?? 0
        let factors = store.dungeonGrowthFactors(id)
        return VStack(alignment: .leading, spacing: 8) {
            title(l.dungeonYourRuns)
            HStack(spacing: 18) {
                stat(l.dungeonStatRuns, "\(runs.count)")
                stat(l.dungeonStatWins, "\(store.dungeonProgress.wins(id))")
                stat(l.dungeonStatBest, best > 0 ? "\(best)" : "-")
                stat(l.dungeonStatCost, TokenFormatter.compact(store.dungeonCost(id)))
            }
            // The artifacts that speed it up (the owner, 2026-11-06), each with its share, the cost above counting them.
            if !factors.isEmpty {
                Label(l.dungeonArtifactsSpeed(Int(((store.dungeonSpeed(id) - 1) * 100).rounded()),
                                              factors.map { Self.factorName($0.source, l) + " +" + String(Int((($0.multiplier - 1) * 100).rounded())) + " %" }
                                                .joined(separator: ", ")),
                      systemImage: "sparkles")
                    .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if runs.isEmpty {
                Text(l.dungeonDetailNoRun).font(.caption).foregroundStyle(.secondary)
            }
            ForEach(Array(runs.enumerated()), id: \.offset) { _, run in
                RunRow(store: store, run: run) { nav.pastRun = run.endedAt }
            }
        }
        .designCard()
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
            Text(value).font(.system(size: 15, weight: .bold)).monospacedDigit()
        }
    }

    private func wild(_ dungeon: Dungeon, _ l: L) -> some View {
        let shown = showsAllWild ? dungeon.wild : Array(dungeon.wild.prefix(Self.wildShown))
        return VStack(alignment: .leading, spacing: 8) {
            title(l.dungeonDetailWild, trailing: "\(dungeon.wild.count)")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 8), spacing: 4) {
                ForEach(shown, id: \.self) { species in
                    SpriteView(speciesID: species, size: 32, sameScale: true)
                        .speciesNameTooltip(species, language: store.language)
                }
            }
            if dungeon.wild.count > Self.wildShown {
                Button {
                    showsAllWild.toggle()
                } label: {
                    Text(showsAllWild ? l.dungeonShowLess : "\(l.costumesSeeAll) (+\(dungeon.wild.count - Self.wildShown))")
                        .font(.caption.weight(.semibold)).foregroundStyle(Design.actionColor)
                }
                .buttonStyle(.plain)
            }
        }
        .designCard()
    }
}

/// The types' strengths and weaknesses (a player, 2026-11-05): the full chart, the multiplier written in each cell,
/// and one type's details on a click.
@MainActor
struct TypeChartScreen: View {
    let store: CompanionStore
    let onBack: () -> Void
    @State private var selected: PokemonType?

    /// 18 cells and the row labels fit the popover's width beside the scroller's lane.
    private static let cell: CGFloat = 15
    private static let label: CGFloat = 26

    var body: some View {
        let l = store.l
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Button { onBack() } label: { Label(l.back, systemImage: "chevron.left").labelStyle(.titleAndIcon) }
                    .buttonStyle(.borderless)
                    .keyboardShortcut(.cancelAction)
                Spacer(minLength: 4)
                Image(systemName: "tablecells").foregroundStyle(.secondary)
                Text(l.typeChartTitle).font(.headline)
            }
            Text(l.typeChartLegend).font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    chart(l)
                    if let selected { details(selected, l) }
                }
                .reservesScrollerLane()
            }
        }
        .padding(PopoverMetrics.padding)
        .frame(height: 520, alignment: .top)
    }

    private func short(_ type: PokemonType, _ l: L) -> String { String(l.typeName(type).prefix(3)).uppercased() }

    private func chart(_ l: L) -> some View {
        let types = PokemonType.allCases
        return Grid(horizontalSpacing: 1, verticalSpacing: 1) {
            GridRow {
                Color.clear.frame(width: Self.label, height: 28)
                ForEach(types, id: \.self) { defending in
                    Text(short(defending, l)).font(.system(size: 7, weight: .bold))
                        .rotationEffect(.degrees(-90)).fixedSize()
                        .frame(width: Self.cell, height: 28)
                        .background(defending.color.opacity(selected == defending ? 0.6 : 0.3))
                        .onTapGesture { selected = selected == defending ? nil : defending }
                }
            }
            ForEach(types, id: \.self) { attacking in
                GridRow {
                    Text(short(attacking, l)).font(.system(size: 8, weight: .bold))
                        .frame(width: Self.label, height: Self.cell)
                        .background(attacking.color.opacity(selected == attacking ? 0.6 : 0.3))
                        .onTapGesture { selected = selected == attacking ? nil : attacking }
                    ForEach(types, id: \.self) { defending in
                        cell(PokemonTypeData.effectiveness(attacking: attacking, defending: defending),
                             lit: selected == nil || selected == attacking || selected == defending)
                    }
                }
            }
        }
    }

    /// The multiplier written, its color doubling it: blue for twice, orange for half, grey for none (never red and
    /// green alone).
    private func cell(_ value: Double, lit: Bool) -> some View {
        let (text, fill): (String, Color) = switch value {
        case 2...: ("2", .blue)
        case 0.4..<0.6: ("½", .orange)
        case ..<0.1: ("0", .gray)
        default: ("", .clear)
        }
        return Text(text).font(.system(size: 9, weight: .bold)).monospacedDigit()
            .frame(width: Self.cell, height: Self.cell)
            .background(fill.opacity(text.isEmpty ? 0 : 0.35))
            .background(Color.secondary.opacity(0.06))
            .opacity(lit ? 1 : 0.35)
    }

    private func details(_ type: PokemonType, _ l: L) -> some View {
        let types = PokemonType.allCases
        func list(_ title: String, _ matches: [PokemonType]) -> some View {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                if matches.isEmpty {
                    Text(l.dungeonDetailNone).font(.caption2).foregroundStyle(.tertiary)
                } else {
                    WrappingHStack(spacing: 3, lineSpacing: 3) {
                        ForEach(matches, id: \.self) { Badge(l.typeName($0).uppercased(), tint: .type($0)) }
                    }
                }
            }
        }
        let attack = { (v: Double) in types.filter { PokemonTypeData.effectiveness(attacking: type, defending: $0) == v } }
        let defense = { (v: Double) in types.filter { PokemonTypeData.effectiveness(attacking: $0, defending: type) == v } }
        return VStack(alignment: .leading, spacing: 6) {
            Badge(l.typeName(type).uppercased(), tint: .type(type))
            Text(l.typeAttacking).font(.caption.weight(.semibold))
            list(l.typeStrongAgainst, attack(2))
            list(l.typeWeakAgainst, attack(0.5))
            list(l.typeNoEffectOn, attack(0))
            Text(l.typeDefending).font(.caption.weight(.semibold))
            list(l.typeWeakTo, defense(2))
            list(l.typeResists, defense(0.5))
            list(l.typeImmuneTo, defense(0))
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .designSurface(cornerRadius: 10)
    }
}

/// Every expedition that ended, the latest first (#133): its dungeon, how it ended, its loot; one with its journal
/// kept opens on it (`PastRunScreen`).
@MainActor
struct RunHistoryScreen: View {
    let store: CompanionStore
    let nav: PopoverNavigation
    let onBack: () -> Void

    var body: some View {
        let l = store.l
        let runs = store.allRuns
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Button { onBack() } label: { Label(l.back, systemImage: "chevron.left").labelStyle(.titleAndIcon) }
                    .buttonStyle(.borderless)
                    .keyboardShortcut(.cancelAction)
                Spacer(minLength: 4)
                Image(systemName: "clock.arrow.circlepath").foregroundStyle(.secondary)
                Text(l.runHistoryTitle).font(.headline)
            }
            Text(l.runHistoryHint(DungeonRunRecord.journalsKept)).font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if runs.isEmpty {
                Text(l.dungeonDetailNoRun).font(.caption).foregroundStyle(.secondary)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(runs.enumerated()), id: \.offset) { _, run in
                        RunRow(store: store, run: run, showsDungeon: true) {
                            if run.log != nil { nav.pastRun = run.endedAt }
                        }
                    }
                }
                .reservesScrollerLane()
            }
        }
        .padding(PopoverMetrics.padding)
        .frame(height: 520, alignment: .top)
    }
}

/// One expedition that ended: its boss, how it ended, when, how deep, its loot and tokens; a chevron when its journal
/// opens.
@MainActor
struct RunRow: View {
    let store: CompanionStore
    let run: DungeonRunRecord
    var showsDungeon = false
    var onOpen: (() -> Void)?

    var body: some View {
        let l = store.l
        if run.log != nil, let onOpen {
            Button { onOpen() } label: { content(l, opens: true) }
                .buttonStyle(.plain)
                .hoverTip(l.runOpenJournal)
        } else {
            // Not a button: a line without its journal reads as plainly as the others, never greyed.
            content(l, opens: false)
        }
    }

    private func content(_ l: L, opens: Bool) -> some View {
        let result = Text(l.dungeonResultTitle(won: run.won, roped: run.left))
            .foregroundStyle(run.won ? Design.actionColor : Color.readableOrange)
        let when = [run.endedAt.formatted(.dateTime.day().month().hour().minute().locale(store.language.displayLocale)),
                    l.dungeonFloorOf(run.floor, run.floors)].joined(separator: " · ")
        return HStack(spacing: 8) {
            SpriteView(speciesID: run.bossSpeciesID, size: 26, isSilhouette: !run.won, sameScale: true)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    // The dungeon first when the list mixes them, its result under it with the date.
                    if showsDungeon {
                        Text(l.dungeonName(run.dungeon)).font(.caption.weight(.semibold)).lineLimit(1)
                    } else {
                        result.font(.caption.weight(.semibold))
                    }
                    if run.caught { Image(systemName: "checkmark.seal.fill").font(.caption2).foregroundStyle(.secondary) }
                }
                if showsDungeon {
                    (result + Text(" · ") + Text(when).foregroundStyle(.secondary)).font(.caption2).lineLimit(1)
                } else {
                    Text(when).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 1) {
                Text("🍬 \(run.candies) · 🥚 \(run.eggs) · 🎒 \(run.items)").font(.caption2).monospacedDigit()
                Text(TokenFormatter.compact(run.tokens)).font(.caption2).monospacedDigit()
            }
            .foregroundStyle(.secondary)
            .fixedSize()
            if opens {
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3).padding(.horizontal, 4)
        .contentShape(Rectangle())
    }
}

/// A past expedition's whole journal (#133), its battles replayable as they were fought.
@MainActor
struct PastRunScreen: View {
    let store: CompanionStore
    let nav: PopoverNavigation
    let run: DungeonRunRecord
    let onBack: () -> Void

    var body: some View {
        let l = store.l
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Button { onBack() } label: { Label(l.back, systemImage: "chevron.left").labelStyle(.titleAndIcon) }
                    .buttonStyle(.borderless)
                    .keyboardShortcut(.cancelAction)
                Spacer(minLength: 4)
                DungeonIcon(id: run.dungeon, size: 20)
                Text(l.dungeonName(run.dungeon)).font(.headline).lineLimit(1)
            }
            RunRow(store: store, run: run)
                .padding(6)
                .designSurface(cornerRadius: 10)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach((run.log ?? []).reversed()) { entry in
                        ExpeditionLogRow(store: store, nav: nav, entry: entry, team: run.team ?? [], floors: run.floors)
                    }
                }
                .reservesScrollerLane()
            }
        }
        .padding(PopoverMetrics.padding)
        .frame(height: 520, alignment: .top)
    }
}
