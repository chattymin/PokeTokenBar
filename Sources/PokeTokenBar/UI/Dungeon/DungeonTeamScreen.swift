import SwiftUI

/// A dungeon's team screen, redone on 2026-11-06 (the owner: "not intuitive, and ugly"): the dungeon and its rules
/// ticked as the team forms; the team as cards, with what its types do against the dungeon's (#139); the candidates
/// as a list, each with its types, its moves' types and its fit here, those the rules refuse greyed with the rule; a
/// member clicked opens its moves in place of the list (R4); "Compose for me" (Q8) tries the best teams to the end;
/// the odds of reaching the boss (R7) and of winning, then the departure.
@MainActor
struct DungeonTeamScreen: View {
    let store: CompanionStore
    let dungeon: DungeonID
    let onBack: () -> Void
    let onDepart: () -> Void

    @State private var team: [String] = []
    @State private var focus: String?
    @State private var editingSlot: Int?
    @State private var odds: DungeonTeamBuilder.Odds?
    /// A challenge's boss as the screen opened: shown, estimated and set off against, even past midnight.
    @State private var shownBoss: BattleForm?
    /// Checked: the automatic throws may take the Master Ball at a legendary boss (the owner, 2026-11-04).
    @State private var useMasterBall = true
    @State private var search = ""
    @State private var filter: CompanionStore.TeamFilter?
    @State private var composing = false

    var body: some View {
        let l = store.l
        let (size, rules) = store.teamRules(dungeon)
        let picked = team.compactMap { id in store.dungeonCandidates.first { $0.id == id } }
        let members = picked.map(DungeonCandidate.init)
        let info = store.dungeonInfo(dungeon)
        let boss = shownBoss ?? store.challengeBoss(dungeon)
        let faced = TeamMatchup.facedTypes(info, boss: boss)
        VStack(alignment: .leading, spacing: 8) {
            header(info, boss: boss, l)
            rulesLine(size: size, rules: rules, members: members, info: info, l)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(l.dungeonTeamHeader(picked.count, size)).font(.caption.weight(.semibold))
                    Spacer(minLength: 4)
                    composeButton(l)
                }
                TeamMemberRow(store: store, picked: picked, size: size, dungeon: dungeon, team: $team, focus: $focus,
                              editingSlot: $editingSlot)
                if !faced.isEmpty, !picked.isEmpty {
                    versus(picked, faced: faced, boss: info.themeTypes.isEmpty, l)
                }
            }
            .padding(8)
            .designSurface(cornerRadius: 10)
            if let focus, let entry = picked.first(where: { $0.id == focus }) {
                memberPanel(entry, l)
            } else {
                HStack(spacing: 5) {
                    TextField(l.dexSearchPlaceholder, text: $search)
                        .textFieldStyle(.roundedBorder).controlSize(.small)
                    filterChips(l)
                }
                ScrollView {
                    TeamCandidateList(store: store, dungeon: dungeon, faced: faced, rules: rules, size: size, query: search,
                                      filter: filter, team: $team, focus: $focus)
                        .reservesScrollerLane()
                }
                .frame(minHeight: 46)
            }
            footer(size: size, rules: rules, members: members, boss: boss, l)
        }
        .padding(PopoverMetrics.padding)
        .frame(height: 520, alignment: .top)
        .onAppear {
            if dungeon.isChallenge, shownBoss == nil { shownBoss = store.challengeBoss(dungeon) }
            // The general team, as far as this dungeon's rules admit it (a player, 2026-11-05).
            if team.isEmpty { team = store.startingTeam(for: dungeon) }
        }
        // Again when a member changes form or moves: its spec changes with them, not the team's ids.
        .task(id: estimateKey) { await estimate() }
    }

    private func header(_ info: Dungeon, boss: BattleForm?, _ l: L) -> some View {
        HStack(spacing: 6) {
            Button { onBack() } label: { Label(l.back, systemImage: "chevron.left").labelStyle(.titleAndIcon) }
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
            Spacer(minLength: 4)
            DungeonIcon(id: dungeon, size: 20,
                        boss: boss.map { ExpeditionBoss(speciesID: $0.speciesID, form: $0.form, isShiny: false) })
            if !dungeon.isChallenge { Badge("T\(info.tier.rawValue)", tint: .secondary, style: .tinted) }
            Text(l.dungeonName(dungeon)).font(.headline).lineLimit(1).minimumScaleFactor(0.8)
        }
    }

    /// The dungeon's types, then each rule, ticked once the team keeps it.
    private func rulesLine(size: Int, rules: [DungeonRule], members: [DungeonCandidate], info: Dungeon, _ l: L) -> some View {
        WrappingHStack(spacing: 6, lineSpacing: 4) {
            ForEach(info.themeTypes, id: \.self) { type in
                Badge(l.typeName(type).uppercased(), tint: .type(type)).fixedSize()
            }
            rule(l.dungeonTeamSize(size), met: members.count == size && DungeonTeamRules.distinctSpecies(members))
            ForEach(Array(rules.enumerated()), id: \.offset) { _, item in
                rule(l.dungeonRule(item), met: DungeonTeamRules.holds(item, for: members) && !members.isEmpty)
            }
        }
    }

    private func rule(_ text: String, met: Bool) -> some View {
        Label(text, systemImage: met ? "checkmark.circle.fill" : "circle")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(met ? Design.actionColor : .secondary)
            .fixedSize()
    }

    private func composeButton(_ l: L) -> some View {
        Button {
            composing = true
            let choice = store.composeChoice(for: dungeon)
            Task {
                let ids = await BattleEngine.offMain { choice.run() }
                if !ids.isEmpty { team = ids }
                focus = nil
                composing = false
            }
        } label: {
            HStack(spacing: 4) {
                if composing { ProgressView().controlSize(.mini) }
                Text(composing ? l.dungeonComposing : l.dungeonComposeForMe)
            }
        }
        .buttonStyle(.pill())
        .disabled(composing)
        .hoverTip(l.dungeonComposeHint)
    }

    /// #139: what the team's moves reach on each type it faces, and the members each one hits twice. Written, never
    /// told by a color alone.
    private func versus(_ picked: [DexEntry], faced: [PokemonType], boss: Bool, _ l: L) -> some View {
        let specs = picked.compactMap { store.dungeonSpec($0, for: dungeon) }
        let lines = TeamMatchup.summary(team: specs, against: faced)
        let weak = lines.filter { $0.weakMembers > 0 }
        return VStack(alignment: .leading, spacing: 3) {
            Text(l.dungeonVersus(boss: boss)).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            WrappingHStack(spacing: 6, lineSpacing: 3) {
                Text(l.dungeonYourHits).font(.caption2)
                ForEach(lines, id: \.type) { line in
                    HStack(spacing: 2) {
                        TypeMiniBadge(type: line.type, l: l)
                        Text(TeamMatchup.multiplierText(line.best)).font(.caption2.weight(.bold)).monospacedDigit()
                            .foregroundStyle(line.best >= 2 ? Color.blue : line.best < 1 ? Color.readableOrange : .primary)
                    }
                    .fixedSize()
                }
            }
            WrappingHStack(spacing: 6, lineSpacing: 3) {
                Text(l.dungeonWeakSpots).font(.caption2)
                if weak.isEmpty {
                    Text(l.dungeonDetailNone).font(.caption2).foregroundStyle(.secondary)
                }
                ForEach(weak, id: \.type) { line in
                    HStack(spacing: 2) {
                        TypeMiniBadge(type: line.type, l: l)
                        Text(l.dungeonWeakMembers(line.weakMembers)).font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.readableOrange)
                    }
                    .fixedSize()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Shinies, Megas and Primals, Gigantamax forms: one at a time, a second click lifts it.
    private func filterChips(_ l: L) -> some View {
        HStack(spacing: 4) {
            ForEach(CompanionStore.TeamFilter.allCases, id: \.self) { option in
                let on = filter == option
                Button { filter = on ? nil : option } label: {
                    Group {
                        if option == .favorite {
                            // Filled or not says it, not the color alone.
                            Image(systemName: on ? "heart.fill" : "heart").font(.system(size: 11, weight: on ? .bold : .regular))
                        } else if option == .shiny {
                            Image(systemName: on ? "sparkles" : "sparkle").font(.system(size: 11, weight: on ? .bold : .regular))
                        } else {
                            Text(option == .megaOrPrimal ? l.teamFilterMega : l.teamFilterGigantamax)
                                .font(.system(size: 10, weight: .semibold)).lineLimit(1)
                        }
                    }
                    .foregroundStyle(on ? Design.actionColor : Color.secondary)
                    .modifier(CapsuleFilterChip(active: on, tint: Design.actionColor))
                }
                .buttonStyle(.plain)
                .fixedSize()
                .hoverTip(option == .favorite ? l.filterFavoritesOnly : option == .shiny ? l.filterShinyOnly
                          : option == .megaOrPrimal ? l.teamFilterMega : l.teamFilterGigantamax)
            }
        }
    }

    /// The member clicked: its moves (R4) and battle form, in place of the list; back to the list with "Done".
    private func memberPanel(_ entry: DexEntry, _ l: L) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button(l.dungeonMemberDone, systemImage: "chevron.left") {
                    focus = nil
                    editingSlot = nil
                }
                .buttonStyle(.borderless).font(.caption.weight(.semibold))
                Spacer(minLength: 4)
                PokemonNameLabel(.pokemonSpecies, String(entry.finalID), language: store.language).font(.caption.weight(.semibold))
                Spacer(minLength: 4)
                // A visible way out of the team: it was a right click only (a player, 2026-11-05).
                Button(l.dungeonRemove, systemImage: "minus.circle") {
                    team.removeAll { $0 == entry.id }
                    focus = nil
                    editingSlot = nil
                }
                .buttonStyle(.borderless).font(.caption)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if !store.wonBattleForms(speciesID: entry.finalID).isEmpty {
                        BattleFormChooser(store: store, entry: entry)
                    }
                    LoopEditor(store: store, entry: entry, dungeon: dungeon, editingSlot: $editingSlot)
                }
                .reservesScrollerLane()
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// The candidates, one cell per species, form and shininess: a player with nine Seedot saw nine identical cells
    /// (a player, 2026-11-05). Each cell stands for the copy picked already, else the one whose moves were chosen,
    /// else the best IVs; `count` its copies.
    /// A liked copy stands for its cell before the best IVs: the one the player chose to keep.
    static func candidateGroups(_ entries: [DexEntry], picked: [String], loops: [String: [String]],
                                favorites: Set<String> = []) -> [(entry: DexEntry, count: Int)] {
        func ivTotal(_ e: DexEntry) -> Int {
            e.profile.map { $0.ivs.hp + $0.ivs.attack + $0.ivs.defense + $0.ivs.specialAttack + $0.ivs.specialDefense + $0.ivs.speed } ?? 0
        }
        func rank(_ e: DexEntry) -> (Int, Int, Int, Int) {
            (picked.contains(e.id) ? 1 : 0, loops[e.id] == nil ? 0 : 1, favorites.contains(e.id) ? 1 : 0, ivTotal(e))
        }
        var order: [String] = []
        var groups: [String: [DexEntry]] = [:]
        for e in entries {
            let key = "\(e.finalID)|\(e.form?.rawValue ?? "")|\(e.isShiny)"
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(e)
        }
        return order.compactMap { key in
            guard let copies = groups[key], let best = copies.max(by: { rank($0) < rank($1) }) else { return nil }
            return (best, copies.count)
        }
    }

    private func footer(size: Int, rules: [DungeonRule], members: [DungeonCandidate], boss: BattleForm?, _ l: L) -> some View {
        let valid = DungeonTeamRules.isValid(members, size: size, rules: rules)
        return VStack(alignment: .leading, spacing: 6) {
            // The automatic throws take the Master Ball at a legendary boss unless it stays home for this one.
            if store.itemCount(.masterBall) > 0, store.mayMeetALegendary(dungeon, boss: boss) {
                Toggle(isOn: $useMasterBall) {
                    Text(l.dungeonUseMasterBall(l.itemName(.masterBall))).font(.caption)
                }
                .toggleStyle(.checkbox)
            }
            HStack(alignment: .center, spacing: 8) {
                if valid {
                    VStack(alignment: .leading, spacing: 1) {
                        oddsLine(l.dungeonReachOdds, odds?.reach)
                        oddsLine(l.dungeonWinOdds, odds?.win)
                            .hoverTip(dungeon.isChallenge ? nil : l.dungeonWinOddsHint)
                    }
                } else {
                    Text(l.dungeonTeamIncomplete).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                let keys = store.keysToEnter(dungeon)
                Button(keys > 0 ? "\(l.dungeonSetOff) · 🗝️ \(keys)" : l.dungeonSetOff) {
                    if store.startExpedition(dungeon, team: self.team, expectedBoss: shownBoss, keepsMasterBall: !useMasterBall) {
                        onDepart()
                    } else if dungeon.isChallenge {
                        // Midnight came: the new period's boss, shown and estimated before anything is spent.
                        shownBoss = store.challengeBoss(dungeon)
                    }
                }
                .buttonStyle(.pill(prominent: true))
                .disabled(!valid || !store.canEnter(dungeon))
            }
        }
    }

    private func oddsLine(_ label: String, _ value: Double?) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value.map { "\(Int(($0 * 100).rounded())) %" } ?? "…").font(.caption.weight(.bold)).monospacedDigit()
        }
    }

    /// R7: run off the main thread, the team's specs made here.
    /// The team, each member's battle form and loop: what the estimate depends on.
    private var estimateKey: [String] {
        team.map { id in
            "\(id)|\(store.dungeonProgress.battleFormChoice[id] ?? "")|\((store.dungeonProgress.moveLoops[id] ?? []).joined(separator: ","))"
        } + [shownBoss?.key ?? ""]
    }

    private func estimate() async {
        odds = nil
        let (size, rules) = store.teamRules(dungeon)
        let picked = team.compactMap { id in store.dungeonCandidates.first { $0.id == id } }
        guard DungeonTeamRules.isValid(picked.map(DungeonCandidate.init), size: size, rules: rules),
              let estimate = store.reachEstimate(team: team, for: dungeon, boss: shownBoss) else { return }
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        // The Bag's berries and Revives go along, as at the departure; a challenge's boss stands at the end.
        let value = await BattleEngine.offMain { estimate.run() }
        guard !Task.isCancelled else { return }
        odds = value
    }
}

/// A type in three letters on its color: where a whole badge does not fit (a team card, a move). The letters say it,
/// not the color alone.
@MainActor
struct TypeMiniBadge: View {
    let type: PokemonType
    let l: L

    var body: some View {
        Text(String(l.typeName(type).prefix(3)).uppercased())
            .font(.system(size: 8, weight: .heavy))
            .foregroundStyle(.white)
            .padding(.horizontal, 3).padding(.vertical, 1)
            .background(Capsule().fill(type.color))
            .fixedSize()
    }
}

/// The team as cards: each member's sprite, name and types, a cross to take it out; a click opens its moves. Empty
/// places wait with a "+".
@MainActor
struct TeamMemberRow: View {
    let store: CompanionStore
    let picked: [DexEntry]
    let size: Int
    let dungeon: DungeonID?
    @Binding var team: [String]
    @Binding var focus: String?
    @Binding var editingSlot: Int?

    var body: some View {
        HStack(spacing: 4) {
            ForEach(picked, id: \.id) { entry in card(entry) }
            ForEach(0..<max(0, size - picked.count), id: \.self) { _ in
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [3]))
                    .overlay(Image(systemName: "plus").font(.caption.weight(.bold)).foregroundStyle(.secondary))
                    .frame(maxWidth: 64, minHeight: 66, maxHeight: 66)
            }
        }
    }

    private func card(_ entry: DexEntry) -> some View {
        let l = store.l
        let types = store.dungeonSpec(entry, for: dungeon)?.types ?? PokemonTypeData.types(forSpeciesID: entry.finalID, form: entry.form)
        let focused = focus == entry.id
        return Button {
            focus = focused ? nil : entry.id
            editingSlot = nil
        } label: {
            VStack(spacing: 2) {
                SpriteView(speciesID: entry.finalID, size: 32, shiny: entry.isShiny, form: entry.spriteForm(), sameScale: true)
                PokemonNameLabel(.pokemonSpecies, String(entry.finalID), language: store.language)
                    .font(.system(size: 9, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                HStack(spacing: 2) {
                    ForEach(types, id: \.self) { TypeMiniBadge(type: $0, l: l) }
                }
            }
            .padding(.vertical, 4).padding(.horizontal, 2)
            .frame(maxWidth: 64, minHeight: 66)
            .background(RoundedRectangle(cornerRadius: 8).fill(focused ? Design.actionColor.opacity(0.25) : Color.secondary.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(focused ? Design.actionColor : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            Button {
                team.removeAll { $0 == entry.id }
                if focused { focus = nil }
            } label: {
                Image(systemName: "xmark.circle.fill").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(2)
            .accessibilityLabel(l.dungeonRemove)
        }
        .speciesNameTooltip(entry.finalID, form: entry.form, language: store.language)
    }
}

/// The candidates as a list (redone 2026-11-06), one row per species, form and shininess (`candidateGroups`): its
/// types and its moves' types, its fit against the types faced, those the rules refuse greyed with the rule, the best
/// here first. A click picks or drops one. Without a dungeon (the general team), no fit and no rule.
@MainActor
struct TeamCandidateList: View {
    let store: CompanionStore
    let dungeon: DungeonID?
    let faced: [PokemonType]
    let rules: [DungeonRule]
    let size: Int
    var query = ""
    var filter: CompanionStore.TeamFilter? = nil
    @Binding var team: [String]
    @Binding var focus: String?

    /// Each candidate's battle self as it would fight here, made off the main thread once (a few hundred).
    struct Info: Sendable {
        let types: [PokemonType]
        let moves: [(slug: String, type: PokemonType)]
        let fit: TeamMatchup.Fit
        let total: Int
    }
    @State private var infos: [String: Info] = [:]
    @State private var page = 0
    static let pageSize = 6

    var body: some View {
        let l = store.l
        let all = store.dungeonCandidates
        let searched = CompanionStore.DexSearchMatcher(query).map { matcher in all.filter { matcher.matches($0) } } ?? all
        let shown = filter.map { f in searched.filter { store.matches($0, f) } } ?? searched
        let groups = DungeonTeamScreen.candidateGroups(shown, picked: team, loops: store.dungeonProgress.moveLoops,
                                                       favorites: store.state.favoriteIDs)
        let rows = groups.map { group in
            (entry: group.entry, count: group.count,
             refusal: rules.first { !DungeonTeamRules.admits(DungeonCandidate(group.entry), rules: [$0]) })
        }
        .sorted { a, b in rank(a.entry, a.refusal) < rank(b.entry, b.refusal) }
        let taken = store.teamSpecies(team)
        Group {
            if rows.isEmpty {
                Text(l.dungeonNoCandidate).font(.caption).foregroundStyle(.secondary)
            } else {
                // Six to a page, the best here first: the list ran over some 470 lines (#183).
                let pageCount = Paging.pageCount(rows.count, size: Self.pageSize)
                VStack(spacing: 6) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                        ForEach(Paging.slice(rows, page: page, size: Self.pageSize), id: \.entry.id) { row in
                            CandidateRow(store: store, entry: row.entry, count: row.count, refusal: row.refusal,
                                         info: infos[row.entry.id], size: size, taken: taken, team: $team, focus: $focus)
                        }
                    }
                    HStack {
                        Spacer()
                        PageControl(page: $page, pageCount: pageCount, l: l)
                    }
                }
                .onChange(of: query) { page = 0 }
                .onChange(of: filter) { page = 0 }
            }
        }
        .task(id: "\(dungeon?.rawValue ?? "")|\(all.count)|\(store.dungeonProgress.moveLoops.count)") { await loadInfos(all) }
    }

    /// Refused last, then strong, neutral and weak here, the strongest Pokémon first in each.
    private func rank(_ entry: DexEntry, _ refusal: DungeonRule?) -> (Int, Int, Int) {
        let info = infos[entry.id]
        let fit = switch info?.fit { case .strong: 0; case .weak: 2; default: 1 }
        return (refusal == nil ? 0 : 1, fit, -(info?.total ?? 0))
    }

    private func loadInfos(_ entries: [DexEntry]) async {
        let loops = store.dungeonProgress.moveLoops, unlocked = store.dungeonProgress.unlockedMoves
        let targets = store.moveTargets(dungeon)
        let faced = faced
        let inputs = entries.map { (entry: $0, loop: loops[$0.id]) }
        let made = await BattleEngine.offMain { () -> [String: Info] in
            var out: [String: Info] = [:]
            for input in inputs {
                guard let spec = DungeonTeamBuilder.spec(for: input.entry, loop: input.loop, unlocked: unlocked,
                                                         theme: targets.theme, bosses: targets.bosses)
                else { continue }
                let moves = spec.moves.compactMap(MoveTable.move).map { (slug: $0.slug, type: $0.type(for: spec)) }
                let total = SpeciesBattleTable.data(speciesID: input.entry.finalID, form: input.entry.form)?.baseStats.reduce(0, +) ?? 0
                out[input.entry.id] = Info(types: spec.types, moves: moves, fit: TeamMatchup.fit(spec, against: faced), total: total)
            }
            return out
        }
        infos = made
    }
}

/// One candidate: sprite, name, copies, types; its four moves' types (their names on hover); its fit, or the rule
/// that refuses it; a tick once picked.
@MainActor
private struct CandidateRow: View {
    let store: CompanionStore
    let entry: DexEntry
    let count: Int
    let refusal: DungeonRule?
    let info: TeamCandidateList.Info?
    let size: Int
    /// The team's species, made once per render by the list.
    let taken: Set<Int>
    @Binding var team: [String]
    @Binding var focus: String?

    var body: some View {
        let l = store.l
        let chosen = team.contains(entry.id)
        let blocked = !chosen && (refusal != nil || team.count >= size || taken.contains(entry.finalID))
        let types = info?.types ?? PokemonTypeData.types(forSpeciesID: entry.finalID, form: entry.form)
        // A tile of the team grid (#183): what the row said, its moves under the pointer rather than on a line.
        VStack(spacing: 3) {
            Button {
                if chosen {
                    team.removeAll { $0 == entry.id }
                    if focus == entry.id { focus = nil }
                } else if !blocked {
                    team.append(entry.id)
                }
            } label: {
                VStack(spacing: 3) {
                    SpriteView(speciesID: entry.finalID, size: 44, shiny: entry.isShiny, form: entry.spriteForm(), sameScale: true)
                    HStack(spacing: 3) {
                        PokemonNameLabel(.pokemonSpecies, String(entry.finalID), language: store.language)
                            .font(.caption.weight(.semibold)).lineLimit(1)
                        if count > 1 {
                            Text(l.catchCount(count)).font(.caption2.weight(.semibold)).monospacedDigit().foregroundStyle(.secondary)
                        }
                        if store.isFavorite(entry) {
                            Image(systemName: "heart.fill").font(.system(size: 9)).foregroundStyle(Color.pink)
                                .accessibilityLabel(l.favoriteLabel)
                        }
                    }
                    HStack(spacing: 3) {
                        ForEach(types, id: \.self) { Badge(l.typeName($0).uppercased(), tint: .type($0)).fixedSize() }
                    }
                    if let refusal {
                        Label(l.dungeonRule(refusal), systemImage: "nosign").font(.caption2).foregroundStyle(.secondary)
                            .lineLimit(2).multilineTextAlignment(.center)
                    } else if let fit = info?.fit, fit != .neutral {
                        fitTag(fit, l)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6).padding(.horizontal, 3)
                .opacity(blocked ? 0.45 : 1)
                .background(RoundedRectangle(cornerRadius: 10)
                    .fill(chosen ? Design.actionColor.opacity(0.18) : Color.secondary.opacity(0.08)))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(chosen ? Design.actionColor : .clear, lineWidth: 1))
                .overlay(alignment: .topTrailing) {
                    if chosen {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Design.actionColor).padding(4)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverTip(movesTip)
            .task(id: moveResources) {
                await PokemonNameDisplayStore.shared.loadMissing(moveResources, provider: PokemonNameClient.shared)
            }
            formMenu(l)
        }
    }

    /// Its four moves here, under the pointer: the row showed them, the tile has no room.
    private var moveResources: [PokemonNameResource] {
        (info?.moves ?? []).map { PokemonNameResource(kind: .move, name: $0.slug) }
    }

    private var movesTip: String {
        let names = PokemonNameDisplayStore.shared.names
        return moveResources.map { resource in
            names[resource].flatMap(store.language.resolveName) ?? PokemonNameLocalization.identifier(resource.name)
        }.joined(separator: " · ")
    }

    /// The battle form it fights in, chosen from the list (the owner, 2026-11-10): a Pokémon that is not shiny joins
    /// the Hall of Origin as its Mega or its Gigantamax. Only for a species with a form won.
    @ViewBuilder
    private func formMenu(_ l: L) -> some View {
        let forms = store.wonBattleForms(speciesID: entry.finalID)
        if !forms.isEmpty {
            let current = store.battleFormChoice(for: entry)
            Menu {
                Button { store.setBattleForm(nil, for: entry.id) } label: { Self.menuLine(l.battleFormUsual, on: current == nil) }
                ForEach(forms, id: \.key) { form in
                    Button { store.setBattleForm(form, for: entry.id) } label: {
                        Self.menuLine(Self.formName(form, store), on: current == form)
                    }
                }
            } label: {
                Text(current.map { Self.formName($0, store) } ?? l.battleFormUsual).lineLimit(1)
            }
            .menuStyle(.button)
            .controlSize(.mini)
            .font(.caption2.weight(.semibold))
            .tint(current == nil ? nil : Design.actionColor)
            .fixedSize()
            .disabled(store.isExploring(entry.id))
            .hoverTip(l.battleFormPickTitle)
        }
    }

    @ViewBuilder
    static func menuLine(_ title: String, on: Bool) -> some View {
        if on { Label(title, systemImage: "checkmark") } else { Text(title) }
    }

    static func formName(_ form: BattleForm, _ store: CompanionStore) -> String {
        PokemonForm.label(speciesID: form.speciesID, form: form.form, language: store.language) ?? store.l.battleFormLabel(form)
    }

    private func fitTag(_ fit: TeamMatchup.Fit, _ l: L) -> some View {
        let strong = fit == .strong
        return Label(strong ? l.dungeonFitStrong : l.dungeonFitWeak,
                     systemImage: strong ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(strong ? Color.blue : Color.readableOrange)
            .lineLimit(1).fixedSize()
            .hoverTip(l.dungeonFitHint)
    }
}

/// A Pokémon's loop for a dungeon (R4): its four moves with their cast time; one clicked opens the moves it can learn,
/// the locked ones greyed. Each move's details show on hover.
@MainActor
struct LoopEditor: View {
    let store: CompanionStore
    let entry: DexEntry
    /// The dungeon whose theme the suggestion plays against; none on the Pokédex page.
    let dungeon: DungeonID?
    @Binding var editingSlot: Int?
    /// A card of its own, as the Pokédex page's sections, rather than a panel inside the team screen's.
    var asCard = false

    var body: some View {
        let l = store.l
        let spec = store.dungeonSpec(entry, for: dungeon)
        let loop = spec?.moves ?? []
        let frozen = store.isExploring(entry.id)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                SectionTitle(text: l.dungeonLoopTitle)
                Spacer()
                if store.dungeonProgress.moveLoops[entry.id] != nil, !frozen {
                    Button(l.dungeonSuggestLoop) { store.setMoveLoop([], for: entry.id) }
                        .buttonStyle(.borderless).font(.caption)
                }
            }
            ForEach(Array(loop.enumerated()), id: \.offset) { index, slug in
                Button { editingSlot = editingSlot == index ? nil : index } label: {
                    MoveRow(store: store, slug: slug, speed: spec?.stats.speed ?? 100, number: index + 1,
                            selected: editingSlot == index, spec: spec)
                }
                .buttonStyle(.plain)
                .disabled(frozen)
            }
            if frozen {
                Label(l.dungeonLoopFrozen, systemImage: "lock.fill").font(.caption2).foregroundStyle(.secondary)
            } else if let slot = editingSlot {
                movePicker(slot: slot, loop: loop, spec: spec)
            } else {
                Text(l.dungeonLoopHint).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .modifier(LoopEditorFrame(asCard: asCard))
    }

    private func movePicker(slot: Int, loop: [String], spec: BattlerSpec?) -> some View {
        let data = SpeciesBattleTable.data(speciesID: entry.finalID, form: entry.form)
        let learnable = store.pokemonDetails(speciesID: entry.finalID, form: entry.form)?.moves.map(\.name) ?? []
        let options = Array(Set((data?.pool ?? []) + learnable + loop)).compactMap(MoveTable.move)
            .filter { !loop.contains($0.slug) && !$0.isZOrMax }
            .sorted { ($0.isDamaging ? $0.power : -1, $1.slug) > ($1.isDamaging ? $1.power : -1, $0.slug) }
        let unlocked = store.dungeonProgress.unlockedMoves
        return ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(options, id: \.slug) { move in
                    let locked = move.isLocked && !unlocked.contains(move.slug)
                    Button {
                        var next = loop
                        next[slot] = move.slug
                        store.setMoveLoop(next, for: entry.id)
                        editingSlot = nil
                    } label: {
                        MoveRow(store: store, slug: move.slug, speed: spec?.stats.speed ?? 100, number: nil, selected: false,
                                spec: spec)
                            .opacity(locked || !move.hasEffect ? 0.4 : 1)
                    }
                    .buttonStyle(.plain)
                    .disabled(locked)
                }
            }
            .reservesScrollerLane()
        }
        .frame(maxHeight: 120)
    }
}

@MainActor
private struct LoopEditorFrame: ViewModifier {
    let asCard: Bool

    func body(content: Content) -> some View {
        if asCard {
            content.designCard()
        } else {
            content.padding(8).designSurface(cornerRadius: 10)
        }
    }
}

/// One move: its name, type, power and cast time at the caster's speed (R1); the details on hover.
@MainActor
struct MoveRow: View {
    let store: CompanionStore
    let slug: String
    let speed: Int
    let number: Int?
    let selected: Bool
    /// The Pokémon it is shown for: Hidden Power, Judgment and the others take their type from it.
    var spec: BattlerSpec?

    var body: some View {
        let l = store.l
        let move = MoveTable.move(slug)
        let type = move.map { move in spec.map { move.type(for: $0) } ?? move.type }
        HStack(spacing: 6) {
            if let number {
                Text("\(number)").font(.caption2.weight(.bold)).monospacedDigit().frame(width: 14)
            }
            PokemonNameLabel(.move, slug, language: store.language).font(.caption.weight(.semibold))
            if let type {
                Badge(l.typeName(type).uppercased(), tint: .type(type))
            }
            Spacer(minLength: 4)
            if let move {
                if move.isLocked && !store.dungeonProgress.unlockedMoves.contains(slug) {
                    Image(systemName: "lock.fill").font(.system(size: 9)).foregroundStyle(.secondary)
                }
                Text(move.power > 0 ? "\(move.power)" : "-").font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                Text(l.dungeonCast(Double(move.castBase) * 300 / (100 + Double(speed)) / Double(BattleRules.speedUp) / 1000))
                    .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2).padding(.horizontal, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Design.actionColor.opacity(0.2) : .clear))
        .contentShape(Rectangle())
        .hoverTip(move.map { HoverTip(id: "move:\(slug)", title: l.moveDetails($0, unlocked: store.dungeonProgress.unlockedMoves, type: type)) })
    }
}

/// A placeholder until the live view lands: the battle's outcome.
@MainActor
struct BattleReplayScreen: View {
    let store: CompanionStore
    let battle: ExpeditionBattle
    var startAt = 0
    let onBack: () -> Void

    var body: some View {
        BattleReplayView(store: store, battle: battle, startAt: startAt, onBack: onBack)
    }
}

/// The form a team member fights in: its usual one or a battle form its species won, never used up (2026-11-02).
@MainActor
struct BattleFormChooser: View {
    let store: CompanionStore
    let entry: DexEntry

    var body: some View {
        let l = store.l
        let chosen = store.battleFormChoice(for: entry)
        VStack(alignment: .leading, spacing: 4) {
            Text(l.battleFormPickTitle).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            // On one line when they fit, else one under the other: "Mega (Curly Form)" thrice does not.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) { options(chosen, l) }
                VStack(alignment: .leading, spacing: 3) { options(chosen, l) }
            }
        }
    }

    @ViewBuilder
    private func options(_ chosen: BattleForm?, _ l: L) -> some View {
        option(l.battleFormUsual, selected: chosen == nil) { store.setBattleForm(nil, for: entry.id) }
        ForEach(store.wonBattleForms(speciesID: entry.finalID), id: \.key) { form in
            // Its own form named when the species has several (Tatsugiri, Urshifu, Toxtricity).
            option(PokemonForm.label(speciesID: form.speciesID, form: form.form, language: store.language) ?? l.battleFormLabel(form),
                   selected: chosen == form) { store.setBattleForm(form, for: entry.id) }
        }
    }

    private func option(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: selected ? "checkmark.circle.fill" : "circle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(selected ? AnyShapeStyle(Design.actionColor) : AnyShapeStyle(.secondary))
                .fixedSize()
        }
        .buttonStyle(.plain)
        .disabled(store.isExploring(entry.id))
    }
}
