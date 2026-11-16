import SwiftUI

/// Home while a team explores (maquettes 3, 4, 6): the floor and the tokens before the next, the team's HP, the rare
/// in gold, the journal; the emergency heal waiting for its answer (R5); the throws at the fallen boss (Q18).
@MainActor
struct ExpeditionCard: View {
    let store: CompanionStore
    let nav: PopoverNavigation
    @State private var confirmingAbandon = false
    /// Drawn for its image (`CardSnapshotButton`): the card without its buttons.
    @Environment(\.isCardSnapshot) private var isSnapshot

    var body: some View {
        if let e = store.expedition {
            // Prof. Oak's layout (the owner, 2026-11-10, choice C): the dungeon and its guide telling how it goes, a circle
            // a floor, the team in rings of their HP.
            VStack(alignment: .leading, spacing: 10) {
                titleRow(e)
                ExpeditionGuideHeader(store: store, e: e)
                switch e.phase {
                case .awaitingHeal(let price): heal(e, price: price)
                // The throws go by themselves as the boss falls (`throwAutomatically`): never waits here.
                case .capture, .exploring, .finished: exploring(e)
                }
            }
            .heroCard(colors: e.dungeon.villain.map { [$0.color] } ?? DungeonCard.colors(e.dungeon))
        }
    }

    private var l: L { store.l }

    private func titleRow(_ e: Expedition) -> some View {
        HStack(spacing: 6) {
            LiveDot()
            Text(l.expeditionLive.uppercased())
                .font(.system(size: 10, weight: .heavy)).kerning(0.6).foregroundStyle(Design.actionColor)
            Spacer(minLength: 4)
            Text(l.dungeonFloorOf(min(e.floor, e.floors), e.floors)).font(.caption.weight(.semibold))
                .foregroundStyle(.secondary).monospacedDigit().fixedSize()
            CardSnapshotButton(store: store, sprites: e.team.map { ($0.spec.speciesID, $0.spec.isShiny, $0.spec.form) }
                + [(e.boss.speciesID, e.boss.isShiny, e.boss.form)]) { ExpeditionCard(store: store, nav: nav) }
        }
    }

    // MARK: Exploring

    /// The floors, what moves the team on, the team, the last of the journal.
    @ViewBuilder
    private func exploring(_ e: Expedition) -> some View {
        let floor = min(e.floor, e.floors)
        let have = TokenFormatter.compact(e.floorTokens)
        let need = TokenFormatter.compact(e.floorCost)
        let toBoss = (e.floors - floor) * e.floorCost + max(0, e.floorCost - e.floorTokens)
        ExpeditionFloorTrack(store: store, e: e)
            .hoverTip(l.dungeonExploringNow)
        HStack(spacing: 4) {
            Text(e.floor >= e.floors ? l.dungeonToBoss(have, need) : l.dungeonToNextFloor(have, need, next: e.floor + 1))
                .font(.caption2.weight(.semibold)).monospacedDigit()
            if e.floor < e.floors {
                Text("· " + l.dungeonLeftToBoss(TokenFormatter.compact(toBoss)))
                    .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        ExpeditionTeamRings(team: e.team)
        let recent = e.log.suffix(2).reversed()
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(recent)) { entry in
                    ExpeditionLogRow(store: store, nav: nav, entry: entry, team: e.team, floors: e.floors)
                }
            }
        }
        if isSnapshot {
            EmptyView()
        } else if confirmingAbandon {
            abandonConfirmation
        } else {
            HStack(spacing: 8) {
                if e.log.count > 2 {
                    Button(l.dungeonWholeLog) { nav.showingExpeditionLog = true }
                        .buttonStyle(.borderless).controlSize(.small).font(.caption.weight(.semibold))
                }
                Spacer(minLength: 4)
                Button(l.dungeonAbandon) { confirmingAbandon = true }
                    .buttonStyle(.borderless).controlSize(.small).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased()).font(.caption2.weight(.bold)).tracking(0.6).foregroundStyle(.secondary)
            .padding(.top, 2)
    }

    /// Inline, as the Bag's confirmations: a sheet or an alert left behind by the closing popover would swallow clicks.
    private var abandonConfirmation: some View {
        return VStack(alignment: .leading, spacing: 6) {
            Text(l.dungeonLeaveKeeps)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button(l.cancel) { confirmingAbandon = false }
                    .buttonStyle(.borderless).controlSize(.small)
                Button(l.dungeonLeave) {
                    confirmingAbandon = false
                    store.abandonExpedition()
                }
                .buttonStyle(.pill(prominent: true))
            }
        }
    }

    // MARK: The emergency heal (R5, maquette 4)

    @ViewBuilder
    private func heal(_ e: Expedition, price: Int) -> some View {
        let available = store.availableTokens
        Label(l.dungeonTeamInDanger(Int((e.hpShare * 100).rounded())), systemImage: "exclamationmark.triangle.fill")
            .font(.callout.weight(.semibold)).foregroundStyle(Color.readableOrange)
        ExpeditionTeamRings(team: e.team)
        Text(l.dungeonHealExplain).font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        Text(l.dungeonHealPrice(TokenFormatter.compact(price), have: TokenFormatter.compact(available)))
            .font(.caption.weight(.semibold)).monospacedDigit()
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            Button(l.dungeonHealSkip) { store.answerEmergencyHeal(pay: false) }
                .buttonStyle(.pill())
            Button(l.dungeonHealPay(TokenFormatter.compact(price))) { store.answerEmergencyHeal(pay: true) }
                .buttonStyle(.pill(prominent: true))
                .disabled(available < price)
        }
        // A reserve only a save from before 2026-11-09 holds; since, the wait's tokens grow the Pokémon raised.
        Label(e.reserve > 0 ? l.dungeonReserve(TokenFormatter.compact(e.reserve)) : l.dungeonHealGrowthGoesOn,
              systemImage: e.reserve > 0 ? "hourglass" : "leaf")
            .font(.caption2).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The team's HP, two by row: blue bar, the share left; an orange "!" under a quarter, "K.O." once down.
@MainActor
struct ExpeditionTeamGrid: View {
    let store: CompanionStore
    let team: [ExpeditionMember]

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                  alignment: .leading, spacing: 6) {
            ForEach(team, id: \.entryID) { member in
                row(member)
            }
        }
    }

    private func row(_ member: ExpeditionMember) -> some View {
        let spec = member.spec
        let share = Double(max(0, spec.hp)) / Double(max(1, spec.stats.hp))
        return HStack(spacing: 5) {
            SpriteView(speciesID: spec.speciesID, size: 24, shiny: spec.isShiny, form: spec.form, sameScale: true)
                .opacity(member.isFainted ? 0.35 : 1)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 3) {
                    // A long name shrinks a little before it is cut; "Debilitado" and "Desmaiado" never break in two.
                    PokemonNameLabel(.pokemonSpecies, String(spec.speciesID), language: store.language)
                        .font(.caption2.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.75)
                    GenderGlyph(gender: spec.resolvedGender, l: store.l)
                    Spacer(minLength: 2)
                    if member.isFainted {
                        Text(store.l.battleKO).font(.caption2.weight(.bold)).foregroundStyle(.secondary).fixedSize()
                    } else {
                        if share < ExpeditionEngine.healThreshold {
                            Text("!").font(.caption2.weight(.heavy)).foregroundStyle(Color.readableOrange)
                        }
                        Text("\(Int((share * 100).rounded()))%").font(.caption2).monospacedDigit()
                            .foregroundStyle(.secondary).fixedSize()
                    }
                }
                ExpeditionBar(value: share, color: .blue, height: 4)
            }
        }
    }
}

/// A thin bar: the HP left, the tokens toward the next floor.
@MainActor
struct ExpeditionBar: View {
    let value: Double
    let color: Color
    var height: CGFloat = 4

    var body: some View {
        Capsule().fill(Color.primary.opacity(0.12))
            .overlay(alignment: .leading) {
                GeometryReader { geometry in
                    Capsule().fill(color.opacity(0.85)).frame(width: geometry.size.width * min(1, max(0, value)))
                }
            }
            .frame(height: height)
    }
}

/// One line of the journal: its floor, what happened, the species as sprites (named on hover), the loot as icons; a
/// battle replays, live while it is still being fought.
@MainActor
struct ExpeditionLogRow: View {
    let store: CompanionStore
    let nav: PopoverNavigation
    let entry: ExpeditionLogEntry
    let team: [ExpeditionMember]
    /// The expedition's floors: a fork says until which floor its path holds, never the boss's.
    var floors: Int?

    private var l: L { store.l }

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Text(l.dungeonFloor(entry.floor)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                .frame(minWidth: 44, alignment: .leading)
            content
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch entry.kind {
        case .battle(let battle):
            battleLine(battle)
        case .chest(let loot):
            line("shippingbox.fill", loot.isEmpty ? l.dungeonLogEmptyChest : l.dungeonLogChest)
            ExpeditionLootIcons(loot: loot)
        case .trap(let percent, let item):
            line("exclamationmark.triangle", item.flatMap(ItemKind.init(rawValue:)).map { l.dungeonLogTrapItem(l.itemName($0)) }
                 ?? l.dungeonLogTrap(percent: percent))
        case .spring(let percent):
            line("drop.fill", l.dungeonLogSpring(percent: percent))
        case .center:
            line("cross.case.fill", l.dungeonLogCenter)
        case .lost(let species, let percent, let loot):
            sprite(species)
            line(nil, l.dungeonLogLost(percent: percent))
            ExpeditionLootIcons(loot: loot)
        case .shiny(let species, let caught):
            sprite(species, shiny: true)
            line("sparkles", l.dungeonLogShiny(caught: caught))
        case .secretPassage(let skipped, let loot):
            line("door.left.hand.open", skipped ? l.dungeonLogSecretSkip(entry.floor + 1) : l.dungeonLogSecretRoom)
                .hoverTip(l.dungeonSecretRule)
            if let loot { ExpeditionLootIcons(loot: loot) }
        case .branch(let roll, let risky):
            // Rolled at the end of a floor, it holds for the next three, the boss's floor apart.
            line(risky ? "dice.fill" : "dice",
                 l.dungeonLogBranch(roll: roll, risky: risky, until: min(entry.floor + 3, (floors ?? .max) - 1)))
                .hoverTip(l.dungeonPathRule)
        case .revive(let entryID, let max):
            if let member = team.first(where: { $0.entryID == entryID }) {
                sprite(member.spec.speciesID, shiny: member.spec.isShiny, form: member.spec.form)
            }
            ItemIconView(kind: max ? .maxRevive : .revive, size: 16)
            line(nil, l.dungeonLogItemUsed(l.itemName(max ? .maxRevive : .revive)))
        case .emergencyHeal(let paid):
            line("heart.fill", l.dungeonLogHeal(TokenFormatter.compact(paid)))
        case .bossReached(let species, let shiny, let form, let secret):
            sprite(species, shiny: shiny, form: form)
            line(secret == true ? "sparkles" : "crown.fill", secret == true ? l.dungeonLogSecretBoss : l.dungeonLogBoss)
        case .capture(let attempt, let ball, let caught):
            let kind = ball.flatMap(ItemKind.init(rawValue:))
            if let kind { ItemIconView(kind: kind, size: 16) }
            line(kind == nil ? "circle.circle" : nil,
                 l.dungeonLogThrow(attempt, ball: kind.map(l.itemName) ?? l.dungeonPokeBall, caught: caught))
        case .victory:
            line("flag.checkered", l.dungeonLogVictory)
        case .defeat:
            line("xmark.octagon", l.dungeonLogDefeat)
        case .abandon:
            line("figure.walk", l.dungeonLogLeft)
        }
    }

    private func line(_ symbol: String?, _ text: String) -> some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).font(.caption2).foregroundStyle(.secondary) }
            Text(text).font(.caption).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func sprite(_ species: Int, shiny: Bool = false, form: PokemonForm? = nil) -> some View {
        SpriteView(speciesID: species, size: 20, shiny: shiny, form: form, sameScale: true)
            .speciesNameTooltip(species, form: form, language: store.language)
    }

    /// The team's sprites against the foes', the outcome by glyph and word, and the way to watch it.
    private func battleLine(_ battle: ExpeditionBattle) -> some View {
        let sides = battle.setup.sides
        let ours = sides.first?.battlers ?? []
        let theirs = sides.count > 1 ? sides[1].battlers : []
        let since = Int(Date().timeIntervalSince(entry.date) * 1000)
        let live = since >= 0 && since < battle.duration
        // Two sprites a side and words that never break: three a side cut "Horde" and "Replay" in two in English.
        return HStack(spacing: 4) {
            Text(l.battleKind(battle.kind)).font(.caption.weight(.semibold)).lineLimit(1).fixedSize()
            sprites(ours, limit: 2)
            Text("vs").font(.caption2).foregroundStyle(.secondary).fixedSize()
            sprites(theirs, limit: 2)
            Image(systemName: battle.won ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(battle.won ? Design.actionColor : Color.readableOrange)
                .hoverTip(battle.won ? l.battleWon : l.battleLost)
            Spacer(minLength: 4)
            Button {
                nav.replayStart = live ? since : 0
                nav.replayBattle = battle
            } label: {
                // Live, the antenna alone: its word as well no longer fit the line in French or Spanish.
                Group {
                    if live { Image(systemName: "dot.radiowaves.left.and.right") } else { Text(l.dungeonReplay) }
                }
                .font(.caption2.weight(.semibold)).foregroundStyle(Design.actionColor)
                .lineLimit(1).fixedSize()
            }
            .buttonStyle(.plain)
            .hoverTip(live ? l.dungeonLive : nil)
            .accessibilityLabel(live ? l.dungeonLive : l.dungeonReplay)
        }
    }

    private func sprites(_ battlers: [BattlerSpec], limit: Int) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(battlers.prefix(limit).enumerated()), id: \.offset) { _, battler in
                sprite(battler.speciesID, shiny: battler.isShiny, form: battler.form)
            }
            if battlers.count > limit {
                Text("+\(battlers.count - limit)").font(.caption2).foregroundStyle(.secondary).fixedSize()
            }
        }
    }
}

/// Loot as small icons with their counts: candies, items, eggs.
@MainActor
struct ExpeditionLootIcons: View {
    let loot: ExpeditionLoot

    var body: some View {
        HStack(spacing: 4) {
            if loot.candies > 0 { icon(.rareCandy, loot.candies) }
            ForEach(loot.items.filter { $0.value > 0 }.sorted { $0.key < $1.key }, id: \.key) { key, count in
                if let kind = ItemKind(rawValue: key) { icon(kind, count) }
            }
            ForEach(loot.eggs) { egg in
                SpriteView(speciesID: nil, size: 16, egg: egg.eggKind)
            }
        }
    }

    private func icon(_ kind: ItemKind, _ count: Int) -> some View {
        HStack(spacing: 1) {
            ItemIconView(kind: kind, size: 16)
            if count > 1 { Text("×\(count)").font(.caption2).monospacedDigit().foregroundStyle(.secondary) }
        }
    }
}

/// The return (maquette 7): how it went, what came back to the Bag, what opened; until the player closes it.
@MainActor
struct ExpeditionResultCard: View {
    let store: CompanionStore
    let nav: PopoverNavigation
    /// Drawn for its image (`CardSnapshotButton`): the card without its buttons.
    @Environment(\.isCardSnapshot) private var isSnapshot

    var body: some View {
        if let r = store.dungeonProgress.lastResult {
            content(r, store.l)
        }
    }

    private func content(_ r: ExpeditionResult, _ l: L) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Label(l.dungeonResultTitle(won: r.won, roped: r.roped),
                      systemImage: r.won ? "checkmark.seal.fill" : r.roped ? "arrow.uturn.left.circle.fill" : "xmark.seal.fill")
                    .font(.system(size: 11, weight: .heavy)).textCase(.uppercase)
                    .foregroundStyle(r.won ? Design.actionColor : Color.readableOrange)
                Spacer(minLength: 4)
                if r.firstVictory { Badge(l.dungeonFirstVictory.uppercased(), tint: .blue, style: .tinted) }
                CardSnapshotButton(store: store, sprites: [(r.boss.speciesID, r.boss.isShiny, r.boss.form)]) {
                    ExpeditionResultCard(store: store, nav: nav)
                }
            }
            // The guide tells how it went, beside the dungeon (the owner, 2026-11-10: the same look as the run).
            ExpeditionResultGuide(store: store, r: r)
            ExpeditionFloorTrack(store: store, result: r)
            // What a hideout's leader gave back (issue #180).
            if let recovered = r.recovered, !recovered.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(l.villainTakenBack.uppercased()).font(.caption2.weight(.bold)).tracking(0.6).foregroundStyle(.secondary)
                    ForEach(recovered.sorted { $0.key < $1.key }, id: \.key) { key, count in
                        if let kind = ItemKind(rawValue: key) {
                            HStack(spacing: 6) {
                                ItemIconView(kind: kind, size: 20)
                                Text("\(l.itemName(kind)) ×\(count)").font(.callout.weight(.semibold))
                            }
                        }
                    }
                }
            }
            // A challenge's boss is no capture: the form it gave says it below; nor a hideout's leader.
            if r.won, !r.dungeon.isChallenge, !r.dungeon.isHideout {
                HStack(spacing: 8) {
                    SpriteView(speciesID: r.boss.speciesID, size: 36, shiny: r.boss.isShiny, form: r.boss.form,
                               sameScale: true)
                    VStack(alignment: .leading, spacing: 1) {
                        PokemonNameLabel(.pokemonSpecies, String(r.boss.speciesID), language: store.language)
                            .font(.caption.weight(.semibold))
                        Text(Self.bossLine(r, l))
                            .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        if let thrown = thrownBalls(r, l) {
                            Text(l.dungeonThrowsUsed(thrown)).font(.caption2).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            if r.loot.isEmpty, !r.won {
                // A defeat or leaving keeps the floors' loot, here none: the guide says so.
                EmptyView()
            } else {
                if !r.won {
                    Text(l.dungeonLootKept).font(.caption.weight(.semibold))
                }
                lootRows(r, l)
            }
            if !r.unlocked.isEmpty {
                Label(l.dungeonUnlocked(r.unlocked.map(l.dungeonName).joined(separator: ", ")), systemImage: "lock.open.fill")
                    .font(.caption.weight(.semibold))
            }
            if let key = r.battleForm, let form = BattleForms.form(key: key) {
                HStack(spacing: 6) {
                    SpriteView(speciesID: form.speciesID, size: 28, form: form.form, sameScale: true)
                    BattleFormTitle(form: form, language: store.language, wrap: l.challengeFormWon)
                        .font(.callout.weight(.semibold))
                }
            }
            if let move = r.unlockedMove {
                HStack(spacing: 4) {
                    Image(systemName: "opticaldisc.fill").font(.caption)
                    Text(l.dungeonTechnicalCapsule).font(.caption)
                    Text("·").font(.caption).foregroundStyle(.secondary)
                    PokemonNameLabel(.move, move, language: store.language).font(.caption.weight(.semibold))
                }
            }
            Label(l.dungeonGrowthResumes, systemImage: "play.circle").font(.caption2).foregroundStyle(.secondary)
            if !isSnapshot { HStack(spacing: 8) {
                Button(l.dungeonSeeLog) { nav.showingExpeditionLog = true }
                    .buttonStyle(.borderless).controlSize(.small).font(.caption.weight(.semibold))
                Spacer(minLength: 4)
                if store.expedition == nil, store.isDungeonOpen(r.dungeon) {
                    Button(l.dungeonGoAgain) {
                        store.dismissExpeditionResult()
                        nav.dungeonTeam = r.dungeon
                    }
                    .buttonStyle(.pill())
                    .disabled(!store.canEnter(r.dungeon))
                }
                Button(l.close) { store.dismissExpeditionResult() }
                    .buttonStyle(.pill(prominent: true))
            } }
        }
        .heroCard(colors: r.won ? r.villain.map { [$0.color] } ?? DungeonCard.colors(r.dungeon) : [.gray])
    }

    /// The boss's line on the result card: caught or not, or what it gave in place of its own egg (2026-11-04).
    static func bossLine(_ r: ExpeditionResult, _ l: L) -> String {
        if r.bossReward == .lootOnly { return l.dungeonBossEggWonBefore }
        guard r.caught else { return l.dungeonBossNotCaught }
        if let egg = ExpeditionEngine.eggInPlace(r.bossReward, tier: DungeonCatalog.dungeon(r.dungeon).tier) {
            return l.dungeonBossCaughtAgain(l.itemName(egg))
        }
        return l.dungeonBossCaught
    }

    /// The balls the automatic throws took, in order ("Ultra Ball, Ultra Ball, Poké Ball").
    private func thrownBalls(_ r: ExpeditionResult, _ l: L) -> String? {
        let balls = r.log.compactMap { entry -> String? in
            guard case .capture(_, let ball, _) = entry.kind else { return nil }
            return ball.flatMap(ItemKind.init(rawValue:)).map(l.itemName) ?? l.dungeonPokeBall
        }
        return balls.isEmpty ? nil : balls.joined(separator: ", ")
    }

    /// What a recap shows apart, above the rest (the owner, 2026-11-09: a Legendary Egg listed among berries).
    static let exceptionalFinds: [ItemKind] = [.legendaryEgg, .masterBall]

    /// The loot's items: the exceptional finds apart, the rest in the Bag's order (its sections, then the items' own),
    /// no longer by their names in code.
    static func lootItems(_ loot: ExpeditionLoot) -> (finds: [(ItemKind, Int)], rest: [(ItemKind, Int)]) {
        let items = loot.items.filter { $0.value > 0 }.compactMap { key, count in ItemKind(rawValue: key).map { ($0, count) } }
            .sorted { CompanionStore.bagOrdered($0.0, $1.0) }
        return (items.filter { exceptionalFinds.contains($0.0) }, items.filter { !exceptionalFinds.contains($0.0) })
    }

    private func lootRows(_ r: ExpeditionResult, _ l: L) -> some View {
        let (finds, items) = Self.lootItems(r.loot)
        return VStack(alignment: .leading, spacing: 3) {
            ForEach(finds, id: \.0) { kind, count in
                HStack(spacing: 8) {
                    ItemIconView(kind: kind, size: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Label(l.dungeonExceptionalFind, systemImage: "sparkles")
                            .font(.caption2.weight(.heavy)).foregroundStyle(Color.readableOrange)
                        Text(count > 1 ? "\(l.itemName(kind)) ×\(count)" : l.itemName(kind))
                            .font(.callout.weight(.bold))
                    }
                }
                .padding(.vertical, 5).padding(.horizontal, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.16)))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.orange.opacity(0.45)))
                .padding(.bottom, 3)
            }
            if r.loot.candies > 0 {
                lootRow(.rareCandy, r.loot.candies, l, doubled: r.firstVictory)
            }
            ForEach(items, id: \.0) { kind, count in
                lootRow(kind, count, l, doubled: false)
            }
            ForEach(r.loot.eggs) { egg in
                HStack(spacing: 6) {
                    SpriteView(speciesID: nil, size: 18, egg: egg.eggKind)
                    DungeonEggTitle(speciesID: egg.baseID, l: l, language: store.language, secret: egg.isSecret == true)
                        .font(.caption)
                    if egg.isShiny { Image(systemName: "sparkles").font(.caption2).foregroundStyle(.secondary) }
                }
            }
        }
    }

    private func lootRow(_ kind: ItemKind, _ count: Int, _ l: L, doubled: Bool) -> some View {
        HStack(spacing: 6) {
            ItemIconView(kind: kind, size: 18)
            Text("\(l.itemName(kind)) ×\(count)").font(.caption).monospacedDigit()
            if doubled, count > 1 {
                Text("(\(count / 2) ×2)").font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            }
        }
    }
}

/// The whole journal, of the expedition under way or of the last one back.
@MainActor
struct ExpeditionLogScreen: View {
    let store: CompanionStore
    let nav: PopoverNavigation

    var body: some View {
        let l = store.l
        let e = store.expedition
        let log = e?.log ?? store.dungeonProgress.lastResult?.log ?? []
        let floors = e?.floors ?? store.dungeonProgress.lastResult.map { DungeonCatalog.dungeon($0.dungeon).floors }
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Button { nav.showingExpeditionLog = false } label: {
                    Label(l.back, systemImage: "chevron.left").labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
                Spacer(minLength: 4)
                Text(l.dungeonLogTitle).font(.headline)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(log.reversed()) { entry in
                        ExpeditionLogRow(store: store, nav: nav, entry: entry, team: e?.team ?? [], floors: floors)
                    }
                }
                .reservesScrollerLane()
            }
        }
        .padding(PopoverMetrics.padding)
        .frame(height: 520, alignment: .top)
    }
}

/// The Pokémon raised (or its egg) while a team explores: one small line under the expedition, its growth paused. The
/// whole card comes back as soon as the growth does, at the boss's fall or the team's defeat.
@MainActor
struct PausedCompanionStrip: View {
    let store: CompanionStore

    var body: some View {
        let l = store.l
        HStack(spacing: 8) {
            Group {
                if store.hasActive {
                    SpriteView(speciesID: store.currentSpeciesID, size: 26, shiny: store.state.active?.isShiny == true,
                               form: store.currentForm, sameScale: true)
                } else {
                    SpriteView(speciesID: nil, size: 26, egg: store.eggKind)
                }
            }
            .frame(width: 30, height: 30)
            .background(Circle().fill(Color.primary.opacity(0.06)))
            VStack(alignment: .leading, spacing: 1) {
                Text(store.displayName).font(.caption.weight(.semibold)).lineLimit(1)
                Text(l.companionPausedForExpedition).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            Image(systemName: "pause.circle.fill").font(.callout).foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .designSurface(cornerRadius: Design.cornerRadius)
        .accessibilityElement(children: .combine)
    }
}

/// The dungeon's floors as segments: those walked full, the current one filling with the tokens, the boss's last
/// under a crown. Full and empty differ by fill, not only by color.
@MainActor
struct ExpeditionFloors: View {
    let floor: Int
    let floors: Int
    let progress: Double

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...max(1, floors), id: \.self) { n in
                GeometryReader { geo in
                    let share = n < floor ? 1 : n == floor ? min(1, max(0, progress)) : 0
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.1))
                        Capsule().fill(Design.actionColor).frame(width: geo.size.width * share)
                    }
                }
                .frame(height: 6)
            }
            Image(systemName: "crown.fill").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                .padding(.leading, 2)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityValue("\(floor)/\(floors)")
    }
}
