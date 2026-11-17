import Foundation

struct OakDungeon: Equatable, Sendable {
    enum Reason: Equatable, Sendable {
        case firstWin, challenge, boss, coronetDoor, coronet, hall
        case key(for: DungeonID)
    }

    let id: DungeonID
    let reason: Reason
    let team: [String]
    let win: Double
    let tokens: Int
    var forms: [OakBattleForm] = []
    var capsules: [OakCapsule] = []
}

struct OakBattleForm: Equatable, Sendable {
    let entryID: String
    let form: BattleForm
}

struct OakUnfinishedDungeon: Equatable, Sendable {
    let id: DungeonID
    let reason: OakDungeon.Reason
    var forms: [OakBattleForm] = []
}

struct OakCapsule: Equatable, Sendable {
    let entryID: String
    let kind: ItemKind
    let stat: Int?
}

struct OakDungeonOdds {
    struct Inputs: Equatable {
        let dex: [DexEntry]
        let loops: [String: [String]]
        let moves: Set<String>
        let choices: [String: String]
        let won: Set<String>
        let boss: BattleForm?
        let forms: [String: BattleForm]
        let bag: [Int]
        let caught: Set<String>?
    }

    let inputs: Inputs
    let team: [String]?
    let win: Double
}

extension CompanionStore {
    static let oakDungeonShare = 0.15
    static let oakDungeonWin = 0.5
    static let oakHallWin = 0.1

    var oakDungeon: OakDungeon? {
        guard expedition == nil, !oakDungeonBudgetSpent else { return nil }
        var waiting: DungeonID?
        var searching = false
        func offer(_ id: DungeonID, _ reason: OakDungeon.Reason, atLeast least: Double = Self.oakDungeonWin,
                   forms: [OakBattleForm] = []) -> OakDungeon? {
            guard !searching, let odds = oakOdds(id, forms: forms), odds.team != nil,
                  id.isChallenge || odds.win >= least else { return nil }
            guard itemCount(.legendaryKey) >= keysToEnter(id) else {
                if waiting == nil { waiting = id }
                return nil
            }
            guard let pick = reason == .hall ? odds : oakSearch(id) else {
                searching = true
                return nil
            }
            guard let team = pick.team, pick.win >= least else { return nil }
            return OakDungeon(id: id, reason: reason, team: team, win: pick.win, tokens: dungeonCost(id),
                              forms: forms.filter { team.contains($0.entryID) }, capsules: oakCapsules(for: team, in: id))
        }
        for dungeon in oakUnfinishedDungeons {
            let least = dungeon.reason == .hall ? Self.oakHallWin : Self.oakDungeonWin
            if let advice = offer(dungeon.id, dungeon.reason, atLeast: least, forms: dungeon.forms) { return advice }
        }
        guard !searching, let waiting else { return nil }
        let best = oakOpenDungeons.filter { $0.tier == .t3 }
            .compactMap { dungeon in oakOdds(dungeon.id).map { (id: dungeon.id, win: $0.team == nil ? 0 : $0.win) } }
            .max { $0.win < $1.win }
        return best.flatMap { offer($0.id, .key(for: waiting)) }
    }

    var oakUnfinishedDungeons: [OakUnfinishedDungeon] {
        let open = oakOpenDungeons
        var list = open.filter { $0.id != .hallOfOrigin && state.dungeons.wins($0.id) == 0 }
            .map { OakUnfinishedDungeon(id: $0.id, reason: .firstWin) }
        list += [DungeonID.weekly, .daily].filter(canEnter).map { OakUnfinishedDungeon(id: $0, reason: .challenge) }
        list += open.reversed().filter { $0.id != .hallOfOrigin && $0.bosses.contains(where: oakWantsBoss) }
            .map { OakUnfinishedDungeon(id: $0.id, reason: .boss) }
        let door = isDungeonOpen(.mtCoronet) ? [] : bossesLeft(DungeonCatalog.bossDungeons(before: .mtCoronet))
        list += open.reversed().filter { $0.bosses.contains(where: door.contains) }
            .map { OakUnfinishedDungeon(id: $0.id, reason: .coronetDoor) }
        if isDungeonOpen(.mtCoronet), DungeonCatalog.dungeon(.mtCoronet).bosses.contains(where: { !state.dungeons.beat($0) }) {
            list.append(OakUnfinishedDungeon(id: .mtCoronet, reason: .coronet))
        }
        if isDungeonOpen(.hallOfOrigin), DungeonCatalog.dungeon(.hallOfOrigin).bosses.contains(where: oakWantsBoss),
           let forms = oakHallForms {
            list.append(OakUnfinishedDungeon(id: .hallOfOrigin, reason: .hall, forms: forms))
        }
        return list
    }

    private var oakOpenDungeons: [Dungeon] {
        let regular = DungeonCatalog.all.filter { !$0.id.isChallenge && $0.id != .ruinsOfAlph && !$0.id.isHideout }
        return DungeonTier.allCases.flatMap { tier in regular.filter { $0.tier == tier && isDungeonOpen($0.id) } }
    }

    func oakCapsules(for team: [String], in id: DungeonID) -> [OakCapsule] {
        var gold = itemCount(.goldCapsule), silver = itemCount(.silverCapsule)
        let targets = moveTargets(id)
        var plan: [OakCapsule] = []
        for entryID in team {
            guard let entry = dungeonCandidates.first(where: { $0.id == entryID }), let ivs = entry.profile?.ivs,
                  let spec = dungeonSpec(entry, for: id, targets: targets),
                  let stat = Self.usefulStats(spec).first(where: { ivs[keyPath: Self.ivKeyPaths[$0]] < 31 }) else { continue }
            if gold > 0 {
                gold -= 1
                plan.append(OakCapsule(entryID: entryID, kind: .goldCapsule, stat: nil))
            } else if silver > 0 {
                silver -= 1
                plan.append(OakCapsule(entryID: entryID, kind: .silverCapsule, stat: stat))
            }
        }
        return plan
    }

    static func usefulStats(_ spec: BattlerSpec) -> [Int] {
        let moves = spec.moves.compactMap(MoveTable.move)
        let physical = moves.contains { $0.moveClass == .physical && !["body-press", "foul-play"].contains($0.slug) }
        let special = moves.contains { $0.moveClass == .special }
        return ivKeyPaths.indices.filter { stat in
            switch stat {
            case 0: spec.speciesID != PokemonStatCalculator.shedinjaSpeciesID
            case 1: physical
            case 3: special
            default: true
            }
        }
    }

    var holdsEveryEggFormKey: Bool {
        guard let index = hatchIndex else { return false }
        let new = hatchDraw.bringsNew()
        if new(PokemonOdds.dittoSpeciesID, nil) { return false }
        return !index.contains { base in
            guard !PokemonOdds.dungeonOnly.contains(base.id) else { return false }
            let forms = PokemonForm.rollableLineForms(baseID: base.id)
            return (forms.isEmpty ? [nil] : forms.map(Optional.some)).contains { new(base.id, $0) }
        }
    }

    /// The tokens until the dungeons' fall back under their share, nil while they are under it.
    var oakDungeonBudgetLeft: Int? {
        guard oakDungeonBudgetSpent, let budget = state.dungeons.budget else { return nil }
        return Int(Double(budget.dungeonTokens) / Self.oakDungeonShare) - (state.usedSinceInstall - budget.start)
    }

    private var oakDungeonBudgetSpent: Bool {
        guard let budget = state.dungeons.budget else { return false }
        let tokens = max(state.usedSinceInstall - budget.start, 1)
        return Double(budget.dungeonTokens) >= Self.oakDungeonShare * Double(tokens) && !holdsEveryEggFormKey
    }

    private func oakWantsBoss(_ speciesID: Int) -> Bool {
        !hasCaughtBoss(speciesID)
            && state.eggFromDungeon.map { $0.sourceSpeciesID == speciesID && $0.isSecret != true } != true
    }

    private var oakHallForms: [OakBattleForm]? {
        let graduated = state.dex.filter { !$0.isReleased }
        let won = state.dungeons.battleForms, wonAt = state.dungeons.battleFormsWonAt
        var planned: [OakBattleForm] = []
        for kinds in [[BattleFormKind.mega, .primal], [.gigantamax]] {
            if graduated.contains(where: { battleFormChoice(for: $0).map { kinds.contains($0.kind) } == true }) { continue }
            let forms = BattleForms.all.enumerated()
                .filter { kinds.contains($0.element.kind) && won.contains($0.element.key) }
                .sorted { (wonAt[$0.element.key] ?? .distantFuture, $0.offset) < (wonAt[$1.element.key] ?? .distantFuture, $1.offset) }
                .map(\.element)
            var pick: OakBattleForm?
            for form in forms where pick == nil {
                let entries = graduated.filter { entry in
                    entry.finalID == form.speciesID && battleFormChoice(for: entry) == nil
                        && !planned.contains { $0.entryID == entry.id }
                }
                pick = (entries.first(where: \.isShiny) ?? entries.first).map { OakBattleForm(entryID: $0.id, form: form) }
            }
            guard let pick else { return nil }
            planned.append(pick)
        }
        return planned
    }

    private func oakInputs(_ id: DungeonID, worn: [String: BattleForm]) -> OakDungeonOdds.Inputs {
        OakDungeonOdds.Inputs(
            dex: state.dex, loops: state.dungeons.moveLoops, moves: state.dungeons.unlockedMoves,
            choices: state.dungeons.battleFormChoice, won: state.dungeons.battleForms, boss: challengeBoss(id), forms: worn,
            bag: [ItemKind.oranBerry, .sitrusBerry, .revive, .maxRevive].map(itemCount), caught: state.dungeons.bossesCaught)
    }

    private func oakSearch(_ id: DungeonID) -> OakDungeonOdds? {
        let inputs = oakInputs(id, worn: [:])
        if let done = oakSearches[id], done.inputs == inputs { return done }
        guard oakSearchTasks[id]?.inputs != inputs else { return nil }
        let choice = composeChoice(for: id), search = oakComposeSearch
        let task = Task { [weak self] in
            let team = await BattleEngine.offMain { search(choice) }
            guard let self, self.oakSearchTasks[id]?.inputs == inputs else { return }
            let win = self.reachEstimate(team: team, for: id).map(self.oakWinOdds)
            self.oakSearchTasks[id] = nil
            self.oakSearches[id] = OakDungeonOdds(inputs: inputs, team: win == nil ? nil : team, win: win ?? 0)
        }
        oakSearchTasks[id] = (inputs, task)
        return nil
    }

    private func oakOdds(_ id: DungeonID, forms: [OakBattleForm] = []) -> OakDungeonOdds? {
        let worn = Dictionary(uniqueKeysWithValues: forms.map { ($0.entryID, $0.form) })
        let inputs = oakInputs(id, worn: worn)
        if let cached = oakDungeonCache[id], cached.inputs == inputs { return cached }
        let team = composeTeam(for: id, forms: worn)
        let win = reachEstimate(team: team, for: id, forms: worn).map(oakWinOdds)
        let odds = OakDungeonOdds(inputs: inputs, team: win == nil ? nil : team, win: win ?? 0)
        oakDungeonCache[id] = odds
        return odds
    }
}
