import Foundation

/// The villains' teams in the game (issue #180): the day's theft, the chase, the hideouts.
extension CompanionStore {
    /// The dungeon as walked: the catalog's, its bosses narrowed to those not caught in it yet while any is left (the
    /// owner, 2026-11-13: the same first boss beaten twice in Viridian Forest, "un boss que j'ai jamais capturé en
    /// priorité tant que j'ai pas capturé tous les boss du donjon"). The draw at the entry, the odds, "Compose for me"
    /// and the moves suggested all read this. A challenge's and a hideout's are as they are.
    func dungeonInfo(_ id: DungeonID) -> Dungeon {
        var dungeon = DungeonCatalog.dungeon(id)
        guard !id.isChallenge, !id.isHideout else { return dungeon }
        let left = dungeon.bosses.filter { !state.dungeons.caughtInDungeon(id, $0) }
        if !left.isEmpty { dungeon.bosses = left }
        return dungeon
    }

    /// The thefts not settled yet, the latest first.
    var villainAmbushes: [VillainAmbush] { state.dungeons.ambushes.sorted { $0.at > $1.at } }
    var villainStashes: [VillainStash] { state.dungeons.stashes.sorted { $0.team.tier > $1.team.tier } }

    func villainStash(_ team: VillainTeam) -> VillainStash? { state.dungeons.stashes.first { $0.team == team } }

    /// The day's thieves, every day at their minute (`VillainRules.minute`, the owner, 2026-11-13). Their minute passing
    /// while a team explores, they wait for its return (the owner, 2026-11-13: before, the day was lost, and his
    /// two-day Cerulean Cave run had taken both days they were due), then come at once, that day's theft whatever the
    /// day: a team away for days brings one theft back, not one a day. Never before a first dungeon is won with a team to
    /// give chase. They take the item as they come (the owner, 2026-11-10: else no one would fight them) and thefts add
    /// up, hideouts open or not; the team is the one of the item's tier, so a team only comes for what it is after, and
    /// none comes once nothing is left to take.
    /// `runLoot`: what an expedition just brought back (the owner, 2026-11-16): the day's thieves due at the team's
    /// return strike at once and take from it (`VillainRules.target(fromRun:)`), before it can be used.
    func settleVillainAmbush(runLoot: ExpeditionLoot? = nil) {
        let day = challengePeriod(.daily)
        guard state.dungeons.villainDay != day else { return }
        if state.dungeons.villainWaiting == nil {
            let parts = LocalUsageReader.gregorianCalendar().dateComponents([.hour, .minute], from: currentDate)
            guard (parts.hour ?? 0) * 60 + (parts.minute ?? 0) >= VillainRules.minute(day) else { return }
        }
        if expedition != nil {
            if state.dungeons.villainWaiting == nil {
                changeDungeons { $0.villainWaiting = day }
                persist()
            }
            return
        }
        changeDungeons {
            $0.villainDay = day
            $0.villainWaiting = nil
        }
        let wonOne = DungeonCatalog.all.contains { !$0.id.isChallenge && !$0.id.isHideout && state.dungeons.wins($0.id) > 0 }
        guard wonOne, dungeonCandidates.count >= 3 else {
            persist()
            return
        }
        var random = VillainRules.random(day + ":target")
        let bag = Dictionary(uniqueKeysWithValues: ItemKind.allCases.map { ($0, itemCount($0)) })
        guard let target = runLoot.flatMap({ VillainRules.target(fromRun: $0, bag: bag) }) ?? VillainRules.target(bag, random: &random),
              let tier = VillainRules.tier(of: target.kind) else {
            persist()
            return
        }
        let team = VillainTeam.team(for: tier)
        let taken = min(target.count, itemCount(target.kind))
        changeBag(target.kind, by: -taken)
        if target.kind.isPassive, target.kind.isAchievement { markAchievementClaimed(target.kind) }
        let ambush = VillainAmbush(id: "\(day)-\(target.kind.rawValue)", team: team, item: target.kind.rawValue, count: taken,
                                   at: currentDate, seed: random.next(), grunts: VillainRules.grunts(team, random: &random))
        changeDungeons { progress in
            progress.ambushes.append(ambush)
            if let i = progress.stashes.firstIndex(where: { $0.team == team }) {
                progress.stashes[i].items[target.kind.rawValue, default: 0] += taken
            } else {
                progress.stashes.append(VillainStash(team: team, items: [target.kind.rawValue: taken]))
            }
        }
        notifyCompanionEvent(l.villainAmbushTitle(team), l.villainStoleLine(team, item: l.itemName(target.kind)))
        AppLog.write("villains: \(team.rawValue) took \(taken) \(target.kind.rawValue)")
        persist()
    }

    /// Gives up what a team took (the owner, 2026-11-16): gone for good, its thefts still waiting settled with it; the
    /// hideout closes once nothing is left. An artifact is never given up (`VillainRules.canAbandon`). Returns whether
    /// anything was given up.
    @discardableResult
    func abandonStolen(_ team: VillainTeam) -> Bool {
        guard let stash = villainStash(team) else { return false }
        let given = stash.items.filter { key, count in count > 0 && ItemKind(rawValue: key).map(VillainRules.canAbandon) ?? true }
        guard !given.isEmpty else { return false }
        changeDungeons { progress in
            guard let i = progress.stashes.firstIndex(where: { $0.team == team }) else { return }
            for key in given.keys { progress.stashes[i].items[key] = nil }
            progress.ambushes.removeAll { $0.team == team && $0.won == nil && given[$0.item] != nil }
            if progress.stashes[i].items.isEmpty { progress.stashes.remove(at: i) }
        }
        AppLog.write("villains: \(team.rawValue) keeps \(given.keys.sorted()), given up")
        persist()
        return true
    }

    /// Who gives chase: Mon équipe, else the six strongest graduated Pokémon.
    var ambushDefenders: [DexEntry] {
        let candidates = dungeonCandidates
        let saved = state.dungeons.savedTeam.compactMap { id in candidates.first { $0.id == id } }
        if !saved.isEmpty { return saved }
        func total(_ entry: DexEntry) -> Int {
            SpeciesBattleTable.data(speciesID: entry.finalID, form: entry.form)?.baseStats.reduce(0, +) ?? 0
        }
        return Array(candidates.sorted { total($0) > total($1) }.prefix(6))
    }

    /// The chase, one against one as in the dungeons: won, the item comes back from the hideout and the team flies off;
    /// lost, it stays there. Nil when there is nothing to chase now (no such theft, chased already, a team away).
    @discardableResult
    func defendAgainstAmbush(_ id: String) -> Bool? {
        guard let index = state.dungeons.ambushes.firstIndex(where: { $0.id == id }), expedition == nil else { return nil }
        var ambush = state.dungeons.ambushes[index]
        guard ambush.won == nil, let kind = ambush.kind else { return nil }
        let targets = (theme: ambush.team.themeTypes, bosses: ambush.grunts.map { PokemonTypeData.types(forSpeciesID: $0) })
        let mine = ambushDefenders.compactMap { dungeonSpec($0, for: nil, targets: targets) }
        let foes = VillainRules.gruntSpecs(ambush.grunts, tier: ambush.tier, seed: ambush.seed)
        guard !mine.isEmpty, !foes.isEmpty else { return nil }
        let setup = BattleSetup(sides: [BattleSideSpec(battlers: mine, active: 1), BattleSideSpec(battlers: foes, active: 1)],
                                seed: ambush.seed &+ 1)
        let outcome = BattleEngine.run(setup)
        let won = outcome.winner == 0
        ambush.won = won
        ambush.collapsed = nil
        ambush.battle = ExpeditionBattle(kind: .trainer, setup: setup, won: won, duration: outcome.duration, foes: ambush.grunts)
        if won, let held = villainStash(ambush.team)?.items[kind.rawValue], held > 0 {
            let back = min(held, ambush.count)
            changeBag(kind, by: back)
            let team = ambush.team
            changeDungeons { progress in
                guard let i = progress.stashes.firstIndex(where: { $0.team == team }) else { return }
                progress.stashes[i].items[kind.rawValue] = held - back > 0 ? held - back : nil
                if progress.stashes[i].items.isEmpty { progress.stashes.remove(at: i) }
            }
        }
        let settled = ambush
        changeDungeons { $0.ambushes[index] = settled }
        AppLog.write("villains: \(ambush.team.rawValue) chase \(won ? "won, \(ambush.count) \(kind.rawValue) back" : "lost")")
        persist()
        return won
    }

    /// "Later": the card folds to a low banner, opened again with a click; it stays until the theft is settled.
    func setVillainAmbushCollapsed(_ id: String, _ collapsed: Bool) {
        guard let index = state.dungeons.ambushes.firstIndex(where: { $0.id == id }) else { return }
        changeDungeons { $0.ambushes[index].collapsed = collapsed ? true : nil }
        persist()
    }

    /// The card goes once its chase is over (won, or lost and its item left at the hideout).
    func dismissVillainAmbush(_ id: String) {
        guard state.dungeons.ambushes.contains(where: { $0.id == id && $0.won != nil }) else { return }
        changeDungeons { $0.ambushes.removeAll { $0.id == id } }
        persist()
    }
}
