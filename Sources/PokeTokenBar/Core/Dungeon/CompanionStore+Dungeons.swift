import Foundation

/// The dungeons in the game: what opens them, the teams and their loops, the departure, the tokens walking the team,
/// the answers the player gives (emergency heal, throws, leaving), and the end, its loot in the Bag.
extension CompanionStore {
    var expedition: Expedition? { state.dungeons.expedition }
    var dungeonProgress: DungeonProgress { state.dungeons }

    /// Q1: while a team explores, the Pokémon raised and the egg do not grow. Waiting for the heal's answer, they grow
    /// again (the owner, 2026-11-09: a player away for a day lost that day's growth).
    var growthPaused: Bool {
        if case .exploring? = expedition?.phase { return true }
        return false
    }

    private var expeditionContext: ExpeditionContext? {
        expedition.map { ExpeditionContext(tier: $0.info.tier,
                                           shinyDenominator: Int(shinyDenominator), now: currentDate) }
    }

    // MARK: Opening (Q27, R10, R11)

    /// The conditions still unmet for a dungeon to open; empty when it is open.
    func unmetUnlocks(_ id: DungeonID) -> [DungeonUnlock] {
        dungeonInfo(id).unlocks.filter { !isMet($0) }
    }

    func isMet(_ unlock: DungeonUnlock) -> Bool {
        let graduated = state.dex.filter { !$0.isReleased }
        switch unlock {
        case .graduated(let count): return graduated.count >= count
        case .won(let id): return state.dungeons.wins(id) > 0
        case .wonTier(let tier):
            return DungeonCatalog.all.contains { $0.tier == tier && !$0.id.isChallenge && !$0.id.isHideout && state.dungeons.wins($0.id) > 0 }
        case .wonEvery(let tier): return DungeonMedals.dungeons(tier).allSatisfy { state.dungeons.wins($0) > 0 }
        case .linesGraduated(let count):
            // The lines alone: the whole collection count walked every form of every species for one number.
            let species = Set(graduated.map(\.finalID)).filter(PokemonAssets.animatedSpeciesIDs.contains)
            return Set(species.map(PokemonEvolutionData.root)).count >= count
        case .legendariesGraduated(let count):
            return Set(graduated.filter { $0.rarity == .legendary }.map(\.finalID)).count >= count
        case .beatBosses(let species): return species.allSatisfy(state.dungeons.beat)
        case .treasureMap: return itemCount(.treasureMap) > 0
        case .caughtBosses(let ids): return bossesLeft(ids).isEmpty
        }
    }

    /// These dungeons' bosses not yet caught in their dungeon (the owner, 2026-11-12: one had from an egg counted, and
    /// Mt. Coronet opened with no boss caught).
    func bossesLeft(_ ids: [DungeonID]) -> [Int] {
        DungeonCatalog.bosses(of: ids).filter { !state.dungeons.caughtInDungeon($0) }
    }

    /// Open once its unlocks are met, and for good once won: the tier rule of 2026-11-05 locks none a player has beaten.
    func isDungeonOpen(_ id: DungeonID) -> Bool {
        // A hideout is there while its team keeps what it stole (issue #180).
        if let team = id.villain { return villainStash(team) != nil }
        return unmetUnlocks(id).isEmpty || state.dungeons.wins(id) > 0
    }

    // MARK: The artifacts in the dungeons (the owner, 2026-11-06)

    /// What speeds a dungeon's floors up, as the Pokémon raised grows (`growthSpeedFactors`, `tokenGrowthFactors`),
    /// added up the same way: the artifacts for everyone (Silver Wing, Old Sea Map, DNA Splicers, Zygarde Cube), those
    /// of a type the dungeon has, and the badges its types are weak to. An artifact that fits no dungeon (a stage, a
    /// rarity, a kind of Pokémon) does nothing here.
    func dungeonGrowthFactors(_ id: DungeonID) -> [GrowthFactor] {
        let types = dungeonInfo(id).themeTypes
        var factors: [GrowthFactor] = []
        func add(_ kind: ItemKind, _ multiplier: Double, if applies: Bool) {
            if applies, itemCount(kind) > 0 { factors.append(GrowthFactor(source: .item(kind), multiplier: multiplier)) }
        }
        add(.silverWing, CollectorBonus.silverWingGrowth, if: true)
        add(.griseousOrb, CollectorBonus.griseousOrbGhostDragon, if: types.contains { $0 == .ghost || $0 == .dragon })
        add(.sparklingStone, CollectorBonus.sparklingStoneFairy, if: types.contains(.fairy))
        add(.tealMask, CollectorBonus.tealMaskTypes, if: types.contains(where: CollectorBonus.tealMaskTypeList.contains))
        add(.lunarWing, CollectorBonus.lunarWingPsychicDark, if: types.contains { $0 == .psychic || $0 == .dark })
        add(.zRing, CollectorBonus.zRingSteelElectric, if: types.contains { $0 == .steel || $0 == .electric })
        add(.scrollOfDarkness, CollectorBonus.scrollOfDarknessFighting, if: types.contains(.fighting))
        // A badge counts once for a dungeon one of whose types is weak to its type, as a species weak to it.
        let regions = PokemonType.allCases.reduce(0) { count, badge in
            let weak = types.contains { badge == .normal ? $0 == .normal : PokemonTypeData.effectiveness(attacking: badge, defending: $0) > 1 }
            return weak ? count + claimedBadgeTierCount(badge) : count
        }
        if regions > 0 {
            factors.append(GrowthFactor(source: .badges, multiplier: 1 + CollectorBonus.badgeRegionBonus * Double(regions)))
        }
        return factors + tokenGrowthFactors
    }

    /// How much faster a dungeon's floors go (1.5 = 50% faster): one plus its factors' bonuses, added up.
    func dungeonSpeed(_ id: DungeonID) -> Double { 1 + Self.bonusSum(dungeonGrowthFactors(id)) }

    /// The tokens a dungeon takes, its artifacts counted: what its card shows and an expedition sets off with.
    func dungeonCost(_ id: DungeonID) -> Int {
        Int((Double(dungeonInfo(id).cost(difficulty: growthDifficulty)) / dungeonSpeed(id)).rounded(.up))
    }

    /// The Legendary Keys an entry spends (R10, R11): the Ruins of Alph take their Treasure Map instead.
    func keysToEnter(_ id: DungeonID) -> Int {
        id == .ruinsOfAlph || id.isChallenge || id.isHideout ? 0 : dungeonInfo(id).tier.keys
    }

    /// Whether a team may set off for it now: open, its keys in the Bag, no other expedition under way.
    func canEnter(_ id: DungeonID) -> Bool {
        guard expedition == nil, isDungeonOpen(id), itemCount(.legendaryKey) >= keysToEnter(id) else { return false }
        // The week's dungeon, once won, waits for Monday (the owner, 2026-11-10: one of its forms a week at most).
        return !id.isChallenge || (challengeBoss(id) != nil && !challengeTried(id) && challengeBeaten(id) == nil)
    }

    // MARK: The daily and weekly dungeons (2026-11-02)

    /// The day (`yyyy-MM-dd`) or the ISO week (`yyyy-Www`) a challenge's one try belongs to.
    func challengePeriod(_ id: DungeonID, at date: Date? = nil) -> String {
        DungeonProgress.challengePeriod(id, at: date ?? currentDate)
    }

    /// The day a challenge's try belongs to: one try a day for both, the week's included (the owner, 2026-11-10: "une
    /// tentative par jour possible pas 1 par semaine"); its boss stays the week's (`challengePeriod`).
    func challengeTryPeriod(at date: Date? = nil) -> String { challengePeriod(.daily, at: date) }

    /// Whether this day's one try was spent.
    func challengeTried(_ id: DungeonID) -> Bool {
        (id == .weekly ? state.dungeons.weeklyTried : state.dungeons.dailyTried) == challengeTryPeriod()
    }

    /// How this day's one try ended: nil before it or while it runs, true won, false lost or left (the owner,
    /// 2026-11-09: a lost daily dungeon shows as such). Its run is the one of that challenge ended this day, never the
    /// day before's. A save from before the history counts it lost when its boss's form was not won.
    func challengeOutcome(_ id: DungeonID) -> Bool? {
        guard expedition?.dungeon != id else { return nil }
        // The week's boss beaten on Monday is still won on Wednesday.
        if challengeBeaten(id) != nil { return true }
        guard challengeTried(id) else { return nil }
        let day = challengeTryPeriod()
        if let run = state.dungeons.history.last(where: { $0.dungeon == id && challengeTryPeriod(at: $0.endedAt) == day }) {
            return run.won
        }
        return challengeBoss(id).map { state.dungeons.battleForms.contains($0.key) } ?? false
    }

    /// The battle forms a challenge may still give: those of the species the player graduated and has not won yet.
    func challengeCandidates(_ id: DungeonID) -> [BattleForm] {
        let graduated = graduatedSpeciesIDs, won = state.dungeons.battleForms
        return (id == .weekly ? BattleForms.weekly : BattleForms.daily)
            .filter { graduated.contains($0.speciesID) && !won.contains($0.key) }
    }

    /// The day's (or the week's) boss: one of the forms left, drawn from the period alone, so it stays all day. Nil
    /// once every form a challenge can give is won.
    func challengeBoss(_ id: DungeonID) -> BattleForm? {
        guard id.isChallenge else { return nil }
        if let beaten = challengeBeaten(id) { return beaten }
        let candidates = challengeCandidates(id)
        guard !candidates.isEmpty else { return nil }
        // Kept once seen (`settleChallengeBosses`): a graduation in the day changed the draw's list, and the boss.
        if let key = state.dungeons.challengeDraws[challengeDrawKey(id)],
           let kept = candidates.first(where: { $0.key == key }) { return kept }
        // FNV-1a: `hashValue` changes from launch to launch.
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in (id.rawValue + challengePeriod(id)).utf8 { hash = (hash ^ UInt64(byte)) &* 0x100_0000_01b3 }
        return candidates[Int(hash % UInt64(candidates.count))]
    }

    /// The boss beaten in this period (`DungeonProgress.challengeWins`): it stays the day's boss until the next day
    /// (the owner, 2026-11-10: Mega Staraptor beaten, its card showed another boss under "won today"), the week's until
    /// Monday. Won, it had left the draw, which fell on another form.
    func challengeBeaten(_ id: DungeonID) -> BattleForm? {
        guard id.isChallenge else { return nil }
        return state.dungeons.challengeWins[challengeDrawKey(id)].flatMap { BattleForms.form(key: $0) }
    }

    private func challengeDrawKey(_ id: DungeonID) -> String { DungeonProgress.challengeKey(id, at: currentDate) }

    /// Keeps the day's and the week's bosses as first shown, for their whole period; older draws go.
    func settleChallengeBosses() {
        var draws: [String: String] = [:]
        for id in [DungeonID.daily, .weekly] {
            if let boss = challengeBoss(id) { draws[challengeDrawKey(id)] = boss.key }
        }
        guard draws != state.dungeons.challengeDraws else { return }
        changeDungeons { $0.challengeDraws = draws }
        persist()
    }

    /// The battle form a graduated Pokémon fights in: one of its species' won forms, chosen on the team screen.
    func battleFormChoice(for entry: DexEntry) -> BattleForm? {
        guard let raw = state.dungeons.battleFormChoice[entry.id],
              let form = BattleForms.form(speciesID: entry.finalID, form: PokemonForm(raw)),
              state.dungeons.battleForms.contains(form.key) else { return nil }
        return form
    }

    /// The battle forms won for this species, for its Pokédex page and the team screen.
    func wonBattleForms(speciesID: Int) -> [BattleForm] {
        BattleForms.forms(speciesID: speciesID).filter { state.dungeons.battleForms.contains($0.key) }
    }

    /// The team screen's filters (the owner, 2026-11-10: to find the Megas and the rest the Hall of Origin asks for).
    enum TeamFilter: CaseIterable, Sendable {
        case shiny, megaOrPrimal, gigantamax

        var kinds: [BattleFormKind] {
            switch self {
            case .shiny: []
            case .megaOrPrimal: [.mega, .primal]
            case .gigantamax: [.gigantamax]
            }
        }
    }

    /// Whether a graduated Pokémon shows under a filter: shiny, or its species having won a form of the kind, chosen
    /// or not yet (it can take it from the list).
    func matches(_ entry: DexEntry, _ filter: TeamFilter) -> Bool {
        if filter == .shiny { return entry.isShiny }
        return wonBattleForms(speciesID: entry.finalID).contains { filter.kinds.contains($0.kind) }
    }

    /// Never used up: a Pokémon takes a won form, or goes back to its usual one with nil; not while it explores.
    @discardableResult
    func setBattleForm(_ form: BattleForm?, for entryID: String) -> Bool {
        guard !isExploring(entryID), let entry = state.dex.first(where: { $0.id == entryID }) else { return false }
        if let form {
            guard form.speciesID == entry.finalID, state.dungeons.battleForms.contains(form.key) else { return false }
        }
        changeDungeons { $0.battleFormChoice[entryID] = form?.form.rawValue }
        persist()
        return true
    }

    // MARK: The team (Q5 to Q8, R4)

    /// The team's size and rules: the Ruins of Alph draw theirs for each visit.
    func teamRules(_ id: DungeonID) -> (size: Int, rules: [DungeonRule]) {
        if id == .ruinsOfAlph {
            let drawn = DungeonCatalog.alphRules(seed: UInt64(state.dungeons.departures) &+ 0xA1F)
            return (drawn.teamSize, drawn.rules)
        }
        let dungeon = dungeonInfo(id)
        return (dungeon.teamSize, dungeon.rules)
    }

    /// The graduated Pokémon a team is formed from (Q6: not sent off), those the battle table knows.
    var dungeonCandidates: [DexEntry] {
        // Observed even from the cache: a view reading it redraws when the Pokédex or a battle form changes.
        _ = state.dex.count
        _ = state.dungeons.battleFormChoice.count
        if let cached = dungeonCandidatesCache { return cached }
        let candidates = state.dex.filter { !$0.isReleased && SpeciesBattleTable.data(speciesID: $0.finalID, form: $0.form) != nil }
            .map { entry in
                // In the battle form chosen for it: the team, its rules and its battles see its Mega.
                guard let form = battleFormChoice(for: entry) else { return entry }
                var shown = entry
                shown.form = form.form
                return shown
            }
        dungeonCandidatesCache = candidates
        dungeonCandidatesBuilds += 1
        return candidates
    }

    func dungeonCandidates(wearing forms: [String: BattleForm]) -> [DexEntry] {
        guard !forms.isEmpty else { return dungeonCandidates }
        return dungeonCandidates.map { entry in
            guard let form = forms[entry.id] else { return entry }
            var shown = entry
            shown.form = form.form
            return shown
        }
    }

    /// The species a team holds, for the team screens' rows: one look-up per render, not one per row and member.
    func teamSpecies(_ team: [String]) -> Set<Int> {
        let ids = Set(team)
        return Set(dungeonCandidates.lazy.filter { ids.contains($0.id) }.map(\.finalID))
    }

    /// What a dungeon's moves are suggested against (the owner, 2026-11-09: "l'équipe doit toujours aussi viser le
    /// boss"): its theme, and its bosses, a challenge's known in advance, a dungeon's each it may draw (not the Ruins of
    /// Alph's, any species at all).
    func moveTargets(_ id: DungeonID?) -> (theme: [PokemonType], bosses: [[PokemonType]]) {
        guard let id else { return ([], []) }
        let dungeon = dungeonInfo(id)
        if id.isChallenge {
            let boss = challengeBoss(id).map { PokemonTypeData.types(forSpeciesID: $0.speciesID, form: $0.form) }
            return (dungeon.themeTypes, boss.map { [$0] } ?? [])
        }
        guard dungeon.bosses.count <= 8 else { return (dungeon.themeTypes, []) }
        return (dungeon.themeTypes, dungeon.bosses.map { PokemonTypeData.types(forSpeciesID: $0) })
    }

    /// A graduated Pokémon's battle self for a dungeon: its chosen loop, else the one suggested against the theme and
    /// the bosses (none outside a dungeon, as on its Pokédex page). `targets`: `moveTargets(id)` worked out once for many.
    func dungeonSpec(_ entry: DexEntry, for id: DungeonID?,
                     targets: (theme: [PokemonType], bosses: [[PokemonType]])? = nil) -> BattlerSpec? {
        let targets = targets ?? moveTargets(id)
        return DungeonTeamBuilder.spec(for: entry, loop: state.dungeons.moveLoops[entry.id],
                                       unlocked: state.dungeons.unlockedMoves, theme: targets.theme, bosses: targets.bosses)
    }

    /// Its loop is frozen while it explores (R4: set outside an expedition).
    func isExploring(_ entryID: String) -> Bool { expedition?.team.contains { $0.entryID == entryID } == true }

    /// R4: the player's loop for a Pokémon, outside an expedition; an empty one goes back to the suggestion. Locked
    /// moves are refused.
    @discardableResult
    func setMoveLoop(_ moves: [String], for entryID: String) -> Bool {
        guard !isExploring(entryID) else { return false }
        let allowed = moves.filter { slug in
            guard let move = MoveTable.move(slug) else { return false }
            return !move.isLocked || state.dungeons.unlockedMoves.contains(slug)
        }
        guard allowed.count == moves.count, moves.count <= 4 else { return false }
        changeDungeons { $0.moveLoops[entryID] = moves.isEmpty ? nil : moves }
        persist()
        return true
    }

    /// Q8: the best team the rules allow against the dungeon's theme.
    func composeTeam(for id: DungeonID, forms: [String: BattleForm] = [:]) -> [String] {
        let (size, rules) = teamRules(id)
        return DungeonTeamBuilder.compose(composePool(id, forms: forms), dungeon: dungeonInfo(id), size: size, rules: rules,
                                          boss: challengeBoss(id).map { ExpeditionBoss(speciesID: $0.speciesID, form: $0.form, isShiny: false) })
    }

    /// What "Compose for me" runs off the main thread: the starting teams and the bench, as they would set off, a
    /// challenge's boss, and the Bag's berries and Revives the team would take along.
    func composeChoice(for id: DungeonID) -> DungeonTeamBuilder.ComposeChoice {
        let (size, rules) = teamRules(id)
        let pool = composePool(id)
        let dungeon = dungeonInfo(id)
        let boss = challengeBoss(id).map { ExpeditionBoss(speciesID: $0.speciesID, form: $0.form, isShiny: false) }
        let start = DungeonTeamBuilder.searchStart(pool, dungeon: dungeon, size: size, rules: rules, boss: boss)
        let byID = Dictionary(pool.map { ($0.candidate.entryID, $0) }, uniquingKeysWith: { first, _ in first })
        let teams = start.teams.map { ids in
            ids.compactMap { entryID in byID[entryID].map { ExpeditionMember(entryID: entryID, spec: $0.spec) } }
        }
        let bench = start.bench.compactMap { entryID in
            byID[entryID].map { DungeonTeamBuilder.ComposeChoice.Pick(candidate: $0.candidate,
                                                                      member: ExpeditionMember(entryID: entryID, spec: $0.spec)) }
        }
        return .init(teams: teams, dungeon: dungeon, boss: boss, berries: bagBerries, revives: bagRevives, bench: bench,
                     rules: rules)
    }

    private func composePool(_ id: DungeonID, forms: [String: BattleForm] = [:]) -> [(candidate: DungeonCandidate, spec: BattlerSpec)] {
        let targets = moveTargets(id)
        return dungeonCandidates(wearing: forms).compactMap { entry in
            dungeonSpec(entry, for: id, targets: targets).map { (DungeonCandidate(entry), $0) }
        }
    }

    /// R7: what the odds that this team reaches the boss are run on, off the main thread: the team as it would set
    /// off (its battle forms, its loops), with the Bag's berries and Revives it takes along, and a challenge's boss.
    /// `shown`: the challenge boss the team screen shows, which the odds are for.
    func reachEstimate(team ids: [String], for id: DungeonID, boss shown: BattleForm? = nil,
                       forms: [String: BattleForm] = [:]) -> DungeonTeamBuilder.ReachEstimate? {
        let candidates = dungeonCandidates(wearing: forms)
        let members = ids.compactMap { id in candidates.first { $0.id == id } }
            .compactMap { entry in dungeonSpec(entry, for: id).map { ExpeditionMember(entryID: entry.id, spec: $0) } }
        guard members.count == ids.count, !members.isEmpty else { return nil }
        let boss = (shown ?? challengeBoss(id)).map { ExpeditionBoss(speciesID: $0.speciesID, form: $0.form, isShiny: false) }
        return .init(team: members, dungeon: dungeonInfo(id), berries: bagBerries, revives: bagRevives, boss: boss)
    }

    private var bagBerries: [BattleBerry: Int] {
        [.oran: itemCount(.oranBerry), .sitrus: itemCount(.sitrusBerry)].filter { $0.value > 0 }
    }

    private var bagRevives: [String: Int] {
        [ItemKind.revive.rawValue: itemCount(.revive), ItemKind.maxRevive.rawValue: itemCount(.maxRevive)]
            .filter { $0.value > 0 }
    }

    // MARK: Departure

    /// Sets the team off: the rules held, the keys or the map spent, the Bag's berries and Revives taken along.
    @discardableResult
    /// `expectedBoss`: the challenge boss the team screen showed. Past midnight (or the week's turn) the day's boss is
    /// another, and the new period's try is not spent on one the player never saw nor was shown the odds of.
    func startExpedition(_ id: DungeonID, team ids: [String], expectedBoss: BattleForm? = nil,
                         keepsMasterBall: Bool = false) -> Bool {
        guard canEnter(id) else { return false }
        if id.isChallenge, let expectedBoss {
            settleChallengeBosses()
            guard challengeBoss(id) == expectedBoss else { return false }
        }
        let entries = ids.compactMap { id in dungeonCandidates.first { $0.id == id } }
        let (size, rules) = teamRules(id)
        guard entries.count == ids.count,
              DungeonTeamRules.isValid(entries.map(DungeonCandidate.init), size: size, rules: rules) else { return false }
        let dungeon = dungeonInfo(id)
        let members = entries.compactMap { entry in dungeonSpec(entry, for: id).map { ExpeditionMember(entryID: entry.id, spec: $0) } }
        guard members.count == size else { return false }
        if id == .ruinsOfAlph { changeBag(.treasureMap, by: -1) }
        changeBag(.legendaryKey, by: -keysToEnter(id))
        let berries = bagBerries
        let revives = bagRevives
        changeBag(.oranBerry, by: -(berries[.oran] ?? 0))
        changeBag(.sitrusBerry, by: -(berries[.sitrus] ?? 0))
        changeBag(.revive, by: -(revives[ItemKind.revive.rawValue] ?? 0))
        changeBag(.maxRevive, by: -(revives[ItemKind.maxRevive.rawValue] ?? 0))
        let context = ExpeditionContext(tier: dungeon.tier, shinyDenominator: Int(shinyDenominator), now: currentDate)
        let seed = drawSeed() ^ UInt64(state.dungeons.departures + 1)
        settleChallengeBosses()
        // A hideout's boss is its leader's ace (`VillainTeam.leaderTeam`), with two more at the end.
        let challenge = challengeBoss(id).map { ExpeditionBoss(speciesID: $0.speciesID, form: $0.form, isShiny: false) }
            ?? id.villain.map { ExpeditionBoss(speciesID: $0.leaderTeam[0], form: $0.leaderForms[0], isShiny: false) }
        let started = ExpeditionEngine.start(dungeon: dungeon, team: members, rules: rules, teamSize: size, seed: seed,
                                             cost: dungeonCost(id), berries: berries,
                                             revives: revives, context: context, boss: challenge)
        var expedition = started
        if keepsMasterBall { expedition.keepsMasterBall = true }
        // What its capture gives (2026-11-04, `bossReward`); a challenge's boss gives its form, never shiny; a
        // hideout's leader is no capture.
        if !id.isChallenge, !id.isHideout {
            let species = expedition.boss.speciesID
            let reward = bossReward(species)
            if reward != .ownEgg { expedition.bossReward = reward }
            // A legendary the player has, never shiny, its egg not won yet: it comes shiny, for its shiny egg.
            if reward == .ownEgg, SpeciesInfo.lineRarity(of: species) == .legendary, hasCaughtBoss(species) {
                expedition.boss.isShiny = true
            }
            // One time in a hundred, a secret boss (the owner, 2026-11-10): in the boss's place, or after Arceus.
            if let secret = SecretBosses.draw(id, seed: seed, caught: state.dungeons.secretsCaught,
                                              owned: { self.state.ownsSpecies($0.speciesID, form: $0.form) }) {
                expedition.secret = secret
                if !secret.after {
                    expedition.boss = secret.boss
                    expedition.bossReward = secret.lootOnly ? .lootOnly : nil
                }
                AppLog.write("dungeon: a secret boss in \(id.rawValue), \(secret.boss.speciesID)")
            }
        }
        let day = challengeTryPeriod()
        changeDungeons {
            $0.expedition = expedition
            $0.lastResult = nil
            $0.departures += 1
            // The day's one try is spent at the departure, whatever the end; the week's dungeon has one a day too.
            if id == .daily { $0.dailyTried = day }
            if id == .weekly { $0.weeklyTried = day }
        }
        AppLog.write("dungeon: \(id.rawValue) set off, team \(ids.joined(separator: ","))")
        persist()
        return true
    }

    // MARK: Tokens

    /// Q1: while a team explores, the tokens walk it instead of growing the Pokémon. Returns nil when no team takes
    /// them (none, its boss fallen, or waiting for the heal's answer), else those it left once its boss fell, it lost
    /// or the heal was offered, which growth takes back.
    func feedExpedition(_ tokens: Int) -> Int? {
        guard var e = expedition, let context = expeditionContext else { return nil }
        switch e.phase {
        case .exploring: break
        case .awaitingHeal, .capture, .finished: return nil
        }
        let reached = e.bossReached
        let left = walkingTheDungeon { ExpeditionEngine.feed(&e, tokens: tokens, context: context) }
        store(e, bossNewlyReached: !reached && e.bossReached)
        throwAutomatically()
        return left
    }

    /// A battle that crashed the app would crash it at every launch: its seed, team and floor are saved, so the next
    /// tokens replay the very same battle. A mark set while the engine plays a step and cleared once it returns tells
    /// the next launch that the step never came back (`recoverFromACrashedDungeonStep`).
    static let stepInFlightKey = "dungeonStepInFlight"

    private func walkingTheDungeon<T>(_ step: () -> T) -> T {
        defaultsForDungeons.set(true, forKey: Self.stepInFlightKey)
        defer { defaultsForDungeons.removeObject(forKey: Self.stepInFlightKey) }
        return step()
    }

    /// At launch: a step that never came back ends its expedition, as a defeat with nothing lost but the loot, rather
    /// than replay what crashed. The tokens held for the heal go back to growth.
    func recoverFromACrashedDungeonStep() {
        guard defaultsForDungeons.bool(forKey: Self.stepInFlightKey) else { return }
        defaultsForDungeons.removeObject(forKey: Self.stepInFlightKey)
        guard var e = expedition, let context = expeditionContext else { return }
        if case .finished = e.phase { return }
        AppLog.write("dungeon: a step of \(e.dungeon.rawValue) did not come back last time, the expedition ends")
        let held = e.reserve
        // A defeat, not a departure: the floors crossed keep their loot.
        ExpeditionEngine.finish(&e, won: false, context: context)
        changeDungeons { $0.expedition = e }
        finishExpedition(leftEarly: false)
        creditGrowthPastTheDungeon(held)
    }

    /// Saves the expedition's step and ends it when it is over.
    private func store(_ e: Expedition, bossNewlyReached: Bool = false) {
        changeDungeons {
            $0.expedition = e
            // A secret boss met in the boss's place is kept apart: it is none of the dungeon's bosses.
            if bossNewlyReached, let secret = e.secret, !secret.after {
                $0.secretsMet.insert(SecretBosses.key(e.dungeon, secret.boss))
            } else if bossNewlyReached {
                $0.bossesReached.insert(DungeonProgress.bossKey(e.dungeon, e.boss.speciesID))
            }
        }
        if e.isOver { finishExpedition(leftEarly: false) } else { persist() }
    }

    // MARK: The player's answers

    /// R5: pays the emergency heal from the wallet, or goes on without it.
    @discardableResult
    func answerEmergencyHeal(pay: Bool) -> Bool {
        guard var e = expedition, let context = expeditionContext, case .awaitingHeal(let price) = e.phase else { return false }
        if pay {
            guard availableTokens >= price else { return false }
            spendTokens(price)
        }
        let left = walkingTheDungeon { ExpeditionEngine.answerHeal(&e, paid: pay, context: context) }
        store(e)
        throwAutomatically()
        creditGrowthPastTheDungeon(left)
        return true
    }

    /// Leaves the dungeon with the loot of the floors crossed (the owner, 2026-11-04: the Escape Rope is gone); the floor
    /// under way gives nothing.
    func abandonExpedition() {
        // Not once the boss fell: a victory, its throws waiting, would turn into a defeat.
        guard var e = expedition, let context = expeditionContext else { return }
        switch e.phase {
        case .exploring, .awaitingHeal: break
        case .capture, .finished: return
        }
        ExpeditionEngine.append(&e, .abandon(rope: false), context: context)
        e.phase = .finished(won: false)
        changeDungeons { $0.expedition = e }
        finishExpedition(leftEarly: true)
    }

    /// Q18: a throw at the fallen boss, with a ball of the Bag or a plain one. Returns whether it was caught; nil when
    /// no throw is possible.
    @discardableResult
    func throwAtBoss(_ ball: ItemKind?) -> Bool? {
        guard var e = expedition, let context = expeditionContext, case .capture(let left) = e.phase, left > 0 else { return nil }
        if let ball {
            guard [.greatBall, .ultraBall, .masterBall].contains(ball), changeBag(ball, by: -1) == -1 else { return nil }
        }
        let caught = ExpeditionEngine.throwBall(&e, ball: ball, context: context)
        store(e)
        return caught
    }

    /// The general team (a player, 2026-11-05): six graduated Pokémon at most, one per species, those the Pokédex
    /// still has.
    var savedTeam: [String] {
        let ids = Set(dungeonCandidates.map(\.id))
        return state.dungeons.savedTeam.filter(ids.contains)
    }

    func setSavedTeam(_ ids: [String]) {
        let entries = ids.compactMap { id in dungeonCandidates.first { $0.id == id } }
        var species = Set<Int>()
        let kept = entries.filter { species.insert($0.finalID).inserted }.prefix(6).map(\.id)
        changeDungeons { $0.savedTeam = Array(kept) }
        persist()
    }

    /// What a dungeon's team screen starts with: the general team's members its rules admit, in order, as many as it
    /// takes, one per species.
    func startingTeam(for id: DungeonID) -> [String] {
        let (size, rules) = teamRules(id)
        var team: [DexEntry] = []
        for entryID in savedTeam {
            guard team.count < size, let entry = dungeonCandidates.first(where: { $0.id == entryID }),
                  DungeonTeamRules.admits(DungeonCandidate(entry), rules: rules),
                  !team.contains(where: { $0.finalID == entry.finalID }) else { continue }
            team.append(entry)
        }
        return team.map(\.id)
    }

    /// A dungeon's expeditions that ended, the latest first.
    func runs(of id: DungeonID) -> [DungeonRunRecord] { state.dungeons.history.filter { $0.dungeon == id }.reversed() }

    /// Every expedition that ended, the latest first (#133).
    var allRuns: [DungeonRunRecord] { state.dungeons.history.reversed() }

    /// Whether a boss's species is already the player's: in the Pokédex (graduated, raised or sent off), or its egg
    /// waiting in the Bag. A Secret Egg is not its boss's: Galarian Articuno's waiting is no Articuno caught.
    func hasCaughtBoss(_ speciesID: Int) -> Bool {
        state.registeredSpeciesIDs.contains(speciesID)
            || state.dungeons.eggs.contains { $0.sourceSpeciesID == speciesID && $0.isSecret != true }
    }

    /// Whether the player has this species shiny: in the Pokédex, or the Pokémon raised once at it.
    func hasCaughtShiny(_ speciesID: Int) -> Bool {
        state.dex.contains { $0.isShiny && $0.chainOrder.contains(speciesID) }
            || state.active.map { $0.isShiny && $0.pathIDs.prefix($0.stageIndex + 1).contains(speciesID) } == true
    }

    /// Whether this legendary boss's egg was won (once per species, the owner 2026-11-04): recorded at the capture,
    /// or still in the Bag or incubating from a save before the record.
    func hasWonLegendaryEgg(_ speciesID: Int) -> Bool {
        state.dungeons.legendaryEggsWon.contains(speciesID)
            || state.dungeons.eggs.contains { $0.sourceSpeciesID == speciesID && $0.isSecret != true }
            || state.eggFromDungeon.map { $0.sourceSpeciesID == speciesID && $0.isSecret != true } == true
    }

    /// What catching this boss would give now (the owner, 2026-11-04): a legendary gives its egg once (shiny when the
    /// player has it, a Legendary Egg when the player has it shiny), then the loot only; another, caught already, an
    /// egg of the tier's rarity.
    func bossReward(_ speciesID: Int) -> Expedition.BossReward {
        guard SpeciesInfo.lineRarity(of: speciesID) == .legendary else { return hasCaughtBoss(speciesID) ? .tierEgg : .ownEgg }
        if hasWonLegendaryEgg(speciesID) { return .lootOnly }
        return hasCaughtShiny(speciesID) ? .legendaryEgg : .ownEgg
    }

    // MARK: The automatic capture

    /// The boss fallen, the throws go by themselves (the owner, 2026-11-04: the player was not there to make them, and
    /// the expedition waited): each takes the ball `automaticBall` picks, until one catches or none are left.
    func throwAutomatically() {
        while let e = expedition, case .capture(let left) = e.phase, left > 0 {
            guard throwAtBoss(automaticBall(for: e)) != nil else { break }
        }
    }

    /// The ball a throw takes (issue #197, the owner's pick of 2026-11-16): the Master Ball at a legendary boss, unless
    /// the player kept it out of this expedition at the departure; else the cheapest ball the Bag has that catches the
    /// boss `automaticBallOdds` of the time over the three throws (the free Poké Ball, nil, for a common boss, a Great
    /// Ball for an uncommon one, an Ultra Ball for a rare one); else the best one it has. An Ultra Ball went at every
    /// boss before, a common one the Poké Ball catches 94% of the time.
    func automaticBall(for e: Expedition) -> ItemKind? {
        let boss = e.secret?.capturing == true ? (e.secret?.boss ?? e.boss) : e.boss
        if SpeciesInfo.lineRarity(of: boss.speciesID) == .legendary, e.keepsMasterBall != true, itemCount(.masterBall) > 0 {
            return .masterBall
        }
        let held: [ItemKind?] = [nil] + [ItemKind.greatBall, .ultraBall].filter { itemCount($0) > 0 }
        let throwsCount = Double(ExpeditionEngine.captureThrows)
        let pick = held.first(where: { 1 - pow(1 - ExpeditionEngine.throwOdds(boss, ball: $0), throwsCount) >= Self.automaticBallOdds })
            ?? (held.last ?? nil)
        // The last throw, the two before missed: one ball up, the Great Ball after Poké Balls, the Ultra Ball after Great
        // Balls, else the best held (the owner, 2026-11-16: a Butterfree got away from three Poké Balls, a Great Ball in
        // the Bag).
        guard case .capture(let left) = e.phase, left == 1 else { return pick }
        let ladder: [ItemKind?] = [nil, .greatBall, .ultraBall]
        guard let rung = ladder.firstIndex(of: pick), rung + 1 < ladder.count else { return pick }
        return held.first { ball in (ladder.firstIndex(of: ball) ?? 0) > rung } ?? pick
    }

    /// What a ball must reach over the three throws for the throws to take it rather than a dearer one.
    static let automaticBallOdds = 0.9

    /// Whether this dungeon's boss may be legendary: what the Master Ball box of the team screen is for. A challenge's
    /// boss is the one shown.
    func mayMeetALegendary(_ id: DungeonID, boss: BattleForm?) -> Bool {
        if id.isChallenge { return boss.map { SpeciesInfo.lineRarity(of: $0.speciesID) == .legendary } ?? false }
        // Not one whose egg was won: it gives the loot only, with no throw.
        return dungeonInfo(id).bosses.contains {
            SpeciesInfo.lineRarity(of: $0) == .legendary && bossReward($0) != .lootOnly
        }
    }

    /// Lets the boss go without throwing again: the expedition ends, won.
    func endCapture() {
        guard var e = expedition, let context = expeditionContext, case .capture = e.phase else { return }
        // Arceus let go, the Origin trio may still wait; the trio's one let go, it ends.
        if e.secret?.capturing == true {
            e.secret?.capturing = false
            e.phase = .finished(won: true)
        } else {
            ExpeditionEngine.endBoss(&e, context: context)
        }
        store(e)
    }

    /// Something waits for the player (R13): the emergency heal, the throws at the boss, the return not yet closed.
    var dungeonNeedsAttention: Bool {
        if let e = expedition {
            switch e.phase {
            case .awaitingHeal, .capture: return true
            case .exploring, .finished: return false
            }
        }
        return state.dungeons.lastResult != nil
    }

    /// The menu bar's floor while a team explores ("É6/12"), in place of the growth it pauses.
    var dungeonMenuFloor: String? {
        expedition.map { l.dungeonFloorTag(min($0.floor, $0.floors), $0.floors) }
    }

    func dismissExpeditionResult() {
        guard state.dungeons.lastResult != nil else { return }
        changeDungeons { $0.lastResult = nil }
        persist()
    }

    // MARK: The Bag's dungeon items

    /// The six IVs in the order the Pokédex shows them, HP to Speed.
    static let ivKeyPaths: [WritableKeyPath<PokemonIVs, Int>] = [\.hp, \.attack, \.defense, \.specialAttack,
                                                                \.specialDefense, \.speed]

    /// The graduated Pokémon a Capsule can raise: those with an IV under 31.
    var capsuleCandidates: [DexEntry] {
        state.dex.filter { entry in
            !entry.isReleased && entry.profile.map { p in Self.ivKeyPaths.contains { p.ivs[keyPath: $0] < 31 } } == true
        }
    }

    /// How the Capsule screen orders its Pokémon (the owner, 2026-11-09: a search and a sort, as the Pokédex has).
    enum CapsuleSortOption: String, CaseIterable, Identifiable, Sendable {
        /// The highest base stats first, where IVs at 31 weigh most; the most to gain first among equals.
        case strongest
        /// The most IV points under 31 first.
        case mostToGain
        case recentFirst
        case numberAsc
        case nameAsc

        var id: String { rawValue }
    }

    /// The sum of a graduated Pokémon's six IVs, out of 186.
    static func ivTotal(_ entry: DexEntry) -> Int {
        guard let ivs = entry.profile?.ivs else { return 0 }
        return ivKeyPaths.reduce(0) { $0 + ivs[keyPath: $1] }
    }

    /// Its species' base stats added up, in its form.
    static func baseStatTotal(_ entry: DexEntry) -> Int {
        SpeciesBattleTable.data(speciesID: entry.finalID, form: entry.form)?.baseStats.reduce(0, +) ?? 0
    }

    /// The Capsule screen's Pokémon: `query` read as the Pokédex reads it, the shiny ones alone when asked, in `sort`'s
    /// order.
    func capsuleCandidates(query: String, shinyOnly: Bool, sort: CapsuleSortOption) -> [DexEntry] {
        itemTargets(.goldCapsule, query: query, shinyOnly: shinyOnly, sort: sort)
    }

    /// The sorts the screen of `kind` offers: a Mint has no IVs to gain.
    static func sortOptions(for kind: ItemKind) -> [CapsuleSortOption] {
        kind == .mint ? CapsuleSortOption.allCases.filter { $0 != .mostToGain } : CapsuleSortOption.allCases
    }

    /// The Pokémon `kind` can be used on, searched and sorted as the Capsule screen shows them: a Capsule's those with
    /// an IV under 31, a Mint's every graduated one.
    /// Whether a Capsule has nothing left to raise on this Pokémon: its six IVs at 31.
    static func hasAllIVsMaxed(_ entry: DexEntry) -> Bool {
        entry.profile.map { p in ivKeyPaths.allSatisfy { p.ivs[keyPath: $0] >= 31 } } ?? false
    }

    /// The Capsule screen's Pokémon: those a Capsule can raise, then those already at 31 everywhere, shown greyed (the
    /// owner, 2026-11-12: a Pokémon gone from the list looked lost). A Mint's: every one it can change.
    func itemTargets(_ kind: ItemKind, query: String, shinyOnly: Bool, sort: CapsuleSortOption) -> [DexEntry] {
        let sorted = sortedItemTargets(kind, query: query, shinyOnly: shinyOnly, sort: sort)
        guard kind != .mint else { return sorted }
        return sorted.filter { !Self.hasAllIVsMaxed($0) } + sorted.filter(Self.hasAllIVsMaxed)
    }

    private func sortedItemTargets(_ kind: ItemKind, query: String, shinyOnly: Bool, sort: CapsuleSortOption) -> [DexEntry] {
        var result = kind == .mint ? mintCandidates : state.dex.filter { !$0.isReleased && $0.profile != nil }
        if shinyOnly { result = result.filter(\.isShiny) }
        if let matcher = DexSearchMatcher(query) { result = result.filter { matcher.matches($0) } }
        switch sort {
        case .strongest, .mostToGain:
            let keyed = result.map { (entry: $0, base: Self.baseStatTotal($0), gain: 186 - Self.ivTotal($0)) }
            return keyed.sorted { a, b in
                let first = sort == .strongest ? (a.base, a.gain, b.base, b.gain) : (a.gain, a.base, b.gain, b.base)
                if first.0 != first.2 { return first.0 > first.2 }
                if first.1 != first.3 { return first.1 > first.3 }
                if a.entry.finalID != b.entry.finalID { return a.entry.finalID < b.entry.finalID }
                return a.entry.id < b.entry.id
            }.map(\.entry)
        case .recentFirst: return sortDexEntries(result, by: .recentFirst)
        case .numberAsc: return sortDexEntries(result, by: .numberAsc)
        case .nameAsc: return sortDexEntries(result, by: .nameAsc)
        }
    }

    /// A Silver Capsule raises one IV (`stat`, 0 for HP to 5 for Speed) to 31, a Gold Capsule all six. Spent only
    /// when it raised something.
    @discardableResult
    func useCapsule(_ kind: ItemKind, on entryID: String, stat: Int? = nil) -> Bool {
        guard itemCount(kind) > 0, let entry = capsuleCandidates.first(where: { $0.id == entryID }),
              let ivs = entry.profile?.ivs else { return false }
        let raised: [WritableKeyPath<PokemonIVs, Int>]
        switch kind {
        case .goldCapsule:
            raised = Self.ivKeyPaths
        case .silverCapsule:
            guard let stat, Self.ivKeyPaths.indices.contains(stat), ivs[keyPath: Self.ivKeyPaths[stat]] < 31 else { return false }
            raised = [Self.ivKeyPaths[stat]]
        default:
            return false
        }
        changeProfile(of: entryID) { profile in for path in raised { profile.ivs[keyPath: path] = 31 } }
        changeBag(kind, by: -1)
        AppLog.write("dungeon: \(kind.rawValue) on \(entryID), stat \(stat.map(String.init) ?? "all")")
        persist()
        return true
    }

    /// Q23: an Explorer's Chest holds one of the Explorer Kit's treasures, drawn at the opening.
    @discardableResult
    func openExplorerChest() -> (kind: ItemKind, count: Int)? {
        guard changeBag(.explorerChest, by: -1) == -1 else { return nil }
        let treasure = ExplorerKit.treasure(roll: Int(drawSeed() % UInt64(ExplorerKit.rollRange)))
        if treasure.kind == .rareCandy { _ = grantRareCandies(treasure.count) } else { changeBag(treasure.kind, by: treasure.count) }
        AppLog.write("dungeon: explorer's chest gave \(treasure.count) \(treasure.kind.rawValue)")
        persist()
        return treasure
    }

    // MARK: The end

    /// The tier's extras on a victory (Q22, Q23, R10, R4): an egg sometimes, the very rare items, a Legendary Key
    /// from T3, one victory in two every time (the owner, 2026-11-09: no sure key at the first T3 victory any more,
    /// "que ça soit la 1e ou 15e fois").
    static func victoryExtras(tier: DungeonTier, random: inout BattleRandom) -> ExpeditionLoot {
        var loot = ExpeditionLoot()
        // In the table's order, a sure one drawing nothing: the rolls after it stay what they were.
        for (item, percent) in victoryExtraOdds(tier)
        where percent >= 100 || Double(random.below(10_000)) < percent * 100 {
            loot.add(item)
        }
        return loot
    }

    /// What a victory adds, each with its chance in percent: the roll's own table, which each dungeon's page shows.
    static func victoryExtraOdds(_ tier: DungeonTier) -> [(item: ItemKind, percent: Double)] {
        switch tier {
        case .t1: [(.pokemonEgg, 10)]
        case .t2: [(.uncommonEgg, 10)]
        // A Legendary Key one T3 victory in two (the owner, 2026-11-06: one in ten made a key 3B and Arceus 450B).
        case .t3: [(.rareEgg, 10), (.legendaryKey, 50), (.treasureMap, 5), (.explorerChest, 0.5)]
        case .t4: [(.rareEgg, 25), (.legendaryEgg, 1), (.masterBall, 2), (.explorerChest, 1)]
        case .t5: [(.legendaryEgg, 5), (.masterBall, 10)]
        }
    }

    /// R4 (validated 2026-10-30, T4 and T5 lowered 2026-11-02): a successful expedition unlocks a Technical Capsule
    /// 10%, 20%, 35%, 20%, 15% of the time from T1 to T5; few locked moves are left by then.
    static func technicalCapsuleChance(_ tier: DungeonTier) -> Int {
        switch tier {
        case .t1: 10
        case .t2: 20
        case .t3: 35
        case .t4: 20
        case .t5: 15
        }
    }

    private func finishExpedition(leftEarly: Bool) {
        guard let e = expedition, case .finished(let won) = e.phase else { return }
        let dungeon = e.info
        var random = BattleRandom(seed: e.seed ^ 0xFEED_F00D)
        let openBefore = Set(DungeonID.allCases.filter(isDungeonOpen))
        let firstVictory = won && state.dungeons.wins(e.dungeon) == 0 && !e.dungeon.isChallenge && !e.dungeon.isHideout
        // A defeat or leaving keeps what the floors crossed gave (the owner, 2026-11-04: their tokens are paid); the
        // floor it fell on gave nothing, a battle lost bringing no loot.
        var loot = e.loot
        // The boss's own capture: the Origin trio's after Arceus is the secret's (`SecretEncounter.caught`).
        let captures = e.log.filter { if case .capture(_, _, true) = $0.kind { return true }; return false }.count
        let secretAfterCaught = e.secret.map { $0.after && $0.caught == true } ?? false
        let caught = captures - (secretAfterCaught ? 1 : 0) > 0
        let secretInPlace = e.secret.map { !$0.after } ?? false
        // The egg given in place of the boss's own is the boss's, never doubled: one Legendary Egg for one legendary.
        let inPlace = caught ? ExpeditionEngine.eggInPlace(e.bossReward, tier: dungeon.tier)?.rawValue : nil
        var unlockedMove: String?
        // A challenge gives its battle form, and its floors' loot: no first-victory doubling, no extras.
        var battleForm = won && e.dungeon.isChallenge ? BattleForms.form(speciesID: e.boss.speciesID, form: e.boss.form) : nil
        if won, !e.dungeon.isChallenge {
            if firstVictory {
                // Q22: a first victory doubles the loot and adds a dungeon item.
                loot.candies *= 2
                for (key, count) in loot.items {
                    let boss = key == inPlace ? 1 : 0
                    loot.items[key] = (count - boss) * 2 + boss
                }
                let table = ExpeditionEngine.itemTable(dungeon.tier)
                loot.add(table[random.below(table.count)])
            }
            loot.add(Self.victoryExtras(tier: dungeon.tier, random: &random))
            // A hideout's leader beaten opens their chest (the owner, 2026-11-16), beside all the team took: one draw
            // (2026-11-17), Giovanni's armor only for a Mewtwo of the Pokédex and only once.
            if e.dungeon.isHideout {
                let armor = ArmoredMewtwo.battleForm
                let armorAllowed = !state.dungeons.battleForms.contains(armor.key)
                    && state.dex.contains { !$0.isReleased && $0.finalID == ArmoredMewtwo.speciesID }
                switch VillainRules.drawLeaderChest(dungeon.tier, armorAllowed: armorAllowed, random: &random) {
                case .items(.rareCandy, let count): loot.candies += count
                case .items(let kind, let count): loot.add(kind, count)
                case .armoredMewtwo: battleForm = armor
                }
            }
            if random.below(100) < Self.technicalCapsuleChance(dungeon.tier) {
                let locked = MoveTable.all.values.filter { $0.isLocked && $0.hasEffect && !state.dungeons.unlockedMoves.contains($0.slug) }
                    .map(\.slug).sorted()
                if !locked.isEmpty { unlockedMove = locked[random.below(locked.count)] }
            }
        }
        _ = grantRareCandies(loot.candies)
        for (key, count) in loot.items { if let kind = ItemKind(rawValue: key) { changeBag(kind, by: count) } }
        // What was taken along and not used goes back to the Bag.
        changeBag(.oranBerry, by: e.berries[.oran] ?? 0)
        changeBag(.sitrusBerry, by: e.berries[.sitrus] ?? 0)
        changeBag(.revive, by: e.revives[ItemKind.revive.rawValue] ?? 0)
        changeBag(.maxRevive, by: e.revives[ItemKind.maxRevive.rawValue] ?? 0)
        let record = DungeonRunRecord(dungeon: e.dungeon, endedAt: currentDate, won: won, left: leftEarly,
                                      floor: min(e.floor, e.floors), floors: e.floors, tokens: e.tokensIn,
                                      candies: loot.candies, eggs: loot.eggs.count
                                          + loot.items.filter { ItemKind(rawValue: $0.key)?.isEggItem == true }.values.reduce(0, +),
                                      items: loot.items.filter { ItemKind(rawValue: $0.key)?.isEggItem != true }.values.reduce(0, +),
                                      bossSpeciesID: e.boss.speciesID, caught: caught, log: e.log, team: e.team)
        // A hideout's leader beaten gives back all its team took (issue #180), and the hideout closes.
        let recovered = won ? e.dungeon.villain.flatMap(villainStash)?.items : nil
        for (key, count) in recovered ?? [:] { if let kind = ItemKind(rawValue: key) { changeBag(kind, by: count) } }
        changeDungeons { progress in
            progress.history = DungeonRunRecord.trimmed(progress.history + [record])
            // Its thefts still waiting are settled with it: what they took is back.
            if recovered != nil, let team = e.dungeon.villain {
                progress.stashes.removeAll { $0.team == team }
                progress.ambushes.removeAll { $0.team == team && $0.won == nil }
            }
            // A legendary boss's egg, or the Legendary Egg in its place, is won once.
            if caught, !secretInPlace, SpeciesInfo.lineRarity(of: e.boss.speciesID) == .legendary {
                progress.legendaryEggsWon.insert(e.boss.speciesID)
            }
            // Caught in its dungeon: its place shows it whole, and it counts for Mt. Coronet (the owner, 2026-11-12).
            if caught, !secretInPlace, !e.dungeon.isChallenge, !e.dungeon.isHideout {
                progress.bossesCaught = (progress.bossesCaught ?? []).union([DungeonProgress.bossKey(e.dungeon, e.boss.speciesID)])
            }
            // A secret boss: met, caught, apart from the dungeon's bosses (Galarian Articuno is not Articuno).
            if let secret = e.secret {
                let key = SecretBosses.key(e.dungeon, secret.boss)
                // The Origin trio fought together: all three are met.
                if secret.after, secret.fought == true {
                    for foe in secret.foes ?? [secret.boss] { progress.secretsMet.insert(SecretBosses.key(e.dungeon, foe)) }
                } else if !secret.after, e.bossReached {
                    progress.secretsMet.insert(key)
                }
                if secret.after ? secret.caught == true : caught { progress.secretsCaught.insert(key) }
            }
            progress.eggs += loot.eggs
            if let battleForm {
                progress.battleForms.insert(battleForm.key)
                progress.battleFormsWonAt[battleForm.key] = record.endedAt
            }
            if let battleForm, e.dungeon.isChallenge {
                // By the period it set off in: a run past midnight won the day before's boss, not the new day's.
                let current = [DungeonID.daily, .weekly].map { DungeonProgress.challengeKey($0, at: currentDate) }
                progress.challengeWins = progress.challengeWins.filter { current.contains($0.key) }
                progress.challengeWins[DungeonProgress.challengeKey(e.dungeon, at: e.startedAt)] = battleForm.key
            }
            if let unlockedMove { progress.unlockedMoves.insert(unlockedMove) }
            // A hideout's leader is no dungeon's boss: Giovanni's Mewtwo opens nothing.
            if won, !e.dungeon.isHideout {
                progress.wins[e.dungeon.rawValue, default: 0] += 1
                if !secretInPlace { progress.bossesBeaten.insert(DungeonProgress.bossKey(e.dungeon, e.boss.speciesID)) }
            }
            if e.bossReached, !e.dungeon.isHideout, !secretInPlace {
                progress.bossesReached.insert(DungeonProgress.bossKey(e.dungeon, e.boss.speciesID))
            }
            progress.expedition = nil
        }
        let unlocked = DungeonID.allCases.filter { isDungeonOpen($0) && !openBefore.contains($0) && $0 != .ruinsOfAlph }
        changeDungeons {
            $0.lastResult = ExpeditionResult(dungeon: e.dungeon, won: won, roped: leftEarly, startedAt: e.startedAt,
                                             endedAt: currentDate, tokens: e.tokensIn, battles: e.battles, boss: e.boss,
                                             caught: caught, loot: loot, firstVictory: firstVictory,
                                             unlocked: unlocked, unlockedMove: unlockedMove, battleForm: battleForm?.key,
                                             bossReward: won ? e.bossReward : nil, recovered: recovered,
                                             secret: e.secret, log: e.log)
        }
        AppLog.write("dungeon: \(e.dungeon.rawValue) over, won=\(won) left=\(leftEarly) caught=\(caught) candies=\(loot.candies)")
        persist()
        // The day's thieves due strike at the team's return, at what it brought (the owner, 2026-11-16): a player back
        // from a dungeon who used its loot and set off again was never robbed.
        if !e.dungeon.isHideout { settleVillainAmbush(runLoot: loot) }
    }
}
