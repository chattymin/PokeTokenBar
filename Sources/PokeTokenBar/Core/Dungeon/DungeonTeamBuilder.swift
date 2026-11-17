import Foundation

/// From the Pokédex to a team: a graduated Pokémon's battle self, "Compose for me" (Q8) and the odds of reaching the
/// boss (R7), both against the dungeon's theme, never its boss.
enum DungeonTeamBuilder {
    /// A graduated Pokémon at level 100 with its IVs, nature and ability; its loop is the one chosen for it, else the
    /// one the app suggests against `theme` with the moves `unlocked` (R4).
    static func spec(for entry: DexEntry, loop: [String]? = nil, unlocked: Set<String> = [],
                     theme: [PokemonType] = [], bosses: [[PokemonType]] = []) -> BattlerSpec? {
        // A battle form has its own ability (a Mega Charizard X's Tough Claws), not the Pokémon's usual one.
        let battleForm = BattleForms.form(speciesID: entry.finalID, form: entry.form)
        // Giovanni's armor: perfect IVs and EVs, whatever the Mewtwo wearing it (the owner, 2026-11-17).
        let armored = battleForm?.kind == .armor
        let ivs = armored ? Array(repeating: 31, count: 6) : entry.profile.map { p in
            [p.ivs.hp, p.ivs.attack, p.ivs.defense, p.ivs.specialAttack, p.ivs.specialDefense, p.ivs.speed]
        } ?? Array(repeating: 15, count: 6)
        let ability = battleForm == nil ? entry.profile?.abilityName : nil
        guard var spec = BattlerSpec.make(id: entry.id, speciesID: entry.finalID, form: entry.form, level: 100, ivs: ivs,
                                          evs: armored ? Array(repeating: 252, count: 6) : [],
                                          nature: entry.nature, ability: ability, isShiny: entry.isShiny),
              let data = SpeciesBattleTable.data(speciesID: entry.finalID, form: entry.form) else { return nil }
        // In a battle form, stronger (`BattleFormKind.playerFactors`): the moves below are picked on these stats.
        if let kind = battleForm?.kind {
            spec.stats = spec.stats.scaled(hp: kind.playerFactors.hp, stats: kind.playerFactors.stats)
            spec.hp = spec.stats.hp
        }
        // Its profile's gender, or the one its profile will draw once enriched.
        spec.gender = entry.profile.flatMap { profile in
            profile.gender ?? SpeciesInfo.all[entry.finalID]?.genderRate.map(profile.drawnGender)
        }
        let chosen = (loop ?? []).filter { MoveTable.move($0) != nil }
        spec.moves = chosen.isEmpty
            ? MoveSuggester.suggest(data, stats: spec.stats, types: spec.types,
                                    learnable: entry.profile?.moves.map(\.name) ?? [], unlocked: unlocked, theme: theme,
                                    bosses: bosses)
            : Array(chosen.prefix(4))
        if spec.moves.isEmpty { spec.moves = ["struggle"] }
        return spec
    }

    /// The dungeon's wild Pokémon at the middle of its tier's levels, IVs of 15: what a team is measured against.
    static func sampleFoes(_ dungeon: Dungeon, limit: Int = 24) -> [BattlerSpec] {
        let level = (dungeon.tier.wildLevels.lowerBound + dungeon.tier.wildLevels.upperBound) / 2
        let step = max(1, dungeon.wild.count / limit)
        return stride(from: 0, to: dungeon.wild.count, by: step).compactMap { i in
            BattlerSpec.make(id: "sample\(i)", speciesID: dungeon.wild[i], level: level,
                             ivs: Array(repeating: 15, count: 6))
        }
    }

    /// How a Pokémon fares against the theme: its mean matchup over the sample.
    static func themeScore(_ spec: BattlerSpec, foes: [BattlerSpec]) -> Double {
        guard !foes.isEmpty else { return 0 }
        let bulk = Double(spec.stats.hp) * Double(spec.stats.defense + spec.stats.specialDefense) / 200_000
        return foes.reduce(0) { $0 + BattleMatchup.score(spec, against: $1) } / Double(foes.count) + bulk
    }

    /// Q8: the best team the rules allow, the strongest against the theme first. A team-wide rule (one shared type,
    /// one region) tries each type or region and keeps the best group. Empty when no team of `size` fits. The team
    /// screen then lets the simulation decide among `candidateTeams` (`ComposeChoice`).
    static func compose(_ pool: [(candidate: DungeonCandidate, spec: BattlerSpec)], dungeon: Dungeon, size: Int,
                        rules: [DungeonRule], boss: ExpeditionBoss? = nil) -> [String] {
        candidateTeams(pool, dungeon: dungeon, size: size, rules: rules, boss: boss).first ?? []
    }

    /// The teams "Compose for me" starts from, the best by theme score first: each group's best (one per type or region
    /// a team-wide rule asks), then each again with the dungeon's bosses counted, with them counted thrice, and the
    /// strongest by their stats. The Mt. Moon of 2026-11-05 showed why the theme score alone is not enough: its best
    /// region won 85% of the runs, another one 98%.
    /// `boss`: a challenge's, known in advance (the owner, 2026-11-09: its teams never counted it, a challenge having
    /// no boss list), counted as the dungeons' bosses are.
    static func candidateTeams(_ pool: [(candidate: DungeonCandidate, spec: BattlerSpec)], dungeon: Dungeon, size: Int,
                               rules: [DungeonRule], keep: Int = 6, boss: ExpeditionBoss? = nil) -> [[String]] {
        searchStart(pool, dungeon: dungeon, size: size, rules: rules, keep: keep, boss: boss).teams
    }

    /// `candidateTeams`, and the bench a search swaps their members with: the best `benchSize` by each score, and in
    /// each starting team's group (its type, its region) its best by the theme and the bosses.
    static func searchStart(_ pool: [(candidate: DungeonCandidate, spec: BattlerSpec)], dungeon: Dungeon, size: Int,
                            rules: [DungeonRule], keep: Int = 6, boss: ExpeditionBoss? = nil,
                            benchSize: Int = 12) -> (teams: [[String]], bench: [String]) {
        let foes = sampleFoes(dungeon)
        var random = BattleRandom(seed: 1)
        let bosses = boss.map { known in
            [ExpeditionEngine.bossSpec(known, tier: dungeon.tier, challenge: dungeon.id.isChallenge ? dungeon.id : nil,
                                       random: &random)].compactMap { $0 }
        } ?? dungeon.bosses.prefix(8).compactMap {
            ExpeditionEngine.bossSpec(ExpeditionBoss(speciesID: $0, form: nil, isShiny: false), tier: dungeon.tier, random: &random)
        }
        let admitted = pool.filter { DungeonTeamRules.admits($0.candidate, rules: rules) }
        let theme = admitted.map { themeScore($0.spec, foes: foes) }
        let against = admitted.map { item in
            bosses.isEmpty ? 0 : bosses.reduce(0) { $0 + BattleMatchup.score(item.spec, against: $1) } / Double(bosses.count)
        }
        let withBosses = admitted.indices.map { theme[$0] + against[$0] }
        let bossFirst = admitted.indices.map { theme[$0] + 3 * against[$0] }
        // Raw strength, whatever the matchups: the owner's day dungeon of 2026-11-13 was won most by such a team.
        let power = admitted.map { item in
            let s = item.spec.stats
            return Double(s.hp + s.attack + s.defense + s.specialAttack + s.specialDefense + s.speed)
                + Double(max(s.attack, s.specialAttack)) / 2
        }
        func greedy(_ order: [Int], _ score: [Double]) -> (ids: [String], score: Double)? {
            var team: [DungeonCandidate] = [], total = 0.0
            func take(_ i: Int) -> Bool {
                let item = admitted[i]
                guard team.count < size, !team.contains(where: { $0.speciesID == item.candidate.speciesID }) else { return false }
                let next = team + [item.candidate]
                guard rules.allSatisfy({ rule in
                    DungeonTeamRules.holds(rule, for: next) || rule == .sharedType || rule == .oneRegion || rule.isTeamMinimum
                }) else { return false }
                team = next
                total += score[i]
                return true
            }
            // What the team must have first, the best of each (the Hall of Origin, 2026-11-10): its battle forms, then
            // its shinies; then the best of the rest.
            for rule in rules {
                guard case .needsBattleForm(let kinds) = rule, !DungeonTeamRules.holds(rule, for: team) else { continue }
                for i in order {
                    guard let kind = admitted[i].candidate.battleFormKind, kinds.contains(kind) else { continue }
                    if take(i) { break }
                }
            }
            for rule in rules {
                guard case .atLeastShinies(let count) = rule else { continue }
                for i in order where admitted[i].candidate.isShiny && team.filter(\.isShiny).count < count { _ = take(i) }
            }
            for i in order where team.count < size { _ = take(i) }
            guard team.count == size, rules.filter(\.isTeamMinimum).allSatisfy({ DungeonTeamRules.holds($0, for: team) })
            else { return nil }
            return (team.map(\.entryID), total)
        }
        var groups: [[Int]] = [Array(admitted.indices)]
        if rules.contains(.sharedType) {
            groups = PokemonType.allCases.map { type in admitted.indices.filter { admitted[$0].candidate.types.contains(type) } }
        }
        if rules.contains(.oneRegion) {
            let regions = Set(admitted.map(\.candidate.generation)).sorted()
            groups = groups.flatMap { group in regions.map { region in group.filter { admitted[$0].candidate.generation == region } } }
        }
        func best(_ indices: [Int], by score: [Double]) -> [Int] {
            indices.sorted { (score[$0], admitted[$0].candidate.entryID) > (score[$1], admitted[$1].candidate.entryID) }
        }
        func ranked(_ score: [Double]) -> [(ids: [String], score: Double, group: Int)] {
            groups.indices.compactMap { g in
                greedy(best(groups[g], by: score), score).map { ($0.ids, $0.score, g) }
            }
            .sorted { $0.score > $1.score }
        }
        var teams: [[String]] = [], seedGroups: [Int] = []
        let starts = ranked(theme).prefix(keep) + ranked(withBosses).prefix(keep / 2)
            + (bosses.isEmpty ? [] : ranked(bossFirst).prefix(keep / 2)) + ranked(power).prefix(keep / 2)
        for start in starts where !teams.contains(where: { Set($0) == Set(start.ids) }) {
            teams.append(start.ids)
            seedGroups.append(start.group)
        }
        var bench: [String] = []
        func add(_ indices: some Sequence<Int>) {
            for i in indices where !bench.contains(admitted[i].candidate.entryID) { bench.append(admitted[i].candidate.entryID) }
        }
        let all = Array(admitted.indices)
        add(best(all, by: withBosses).prefix(benchSize))
        add(best(all, by: theme).prefix(benchSize))
        add(best(all, by: power).prefix(benchSize))
        if groups.count > 1 {
            for g in Set(seedGroups).sorted() { add(best(groups[g], by: withBosses).prefix(benchSize / 2)) }
        }
        for team in teams { for id in team where !bench.contains(id) { bench.append(id) } }
        return (teams, bench)
    }

    /// "Compose for me" off the main thread (the owner, 2026-11-13: "il faut simuler plein d'équipes même si on a un
    /// petit chargement de quelques secondes ... il faut la meilleure équipe possible"). His day dungeon of that morning
    /// had kept a team winning 88% of the runs over one winning 96%: two teams only were weighed, on 24 runs each and
    /// without the Bag's berries, which he took along and which made the gap. Now the runs carry the berries and
    /// Revives the team sets off with, and the search plays many teams: its starting teams, every team one swap away
    /// from the best ones, then the best again on more and more runs until one stays.
    struct ComposeChoice: Sendable {
        /// The starting teams (`candidateTeams`), each valid.
        let teams: [[ExpeditionMember]]
        let dungeon: Dungeon
        let boss: ExpeditionBoss?
        /// What the team takes from the Bag, as `CompanionStore.reachEstimate` counts it.
        var berries: [BattleBerry: Int] = [:]
        var revives: [String: Int] = [:]
        /// The Pokémon a swap may bring in (`searchStart`'s bench, the starting teams' members among them), and the rules
        /// a team must keep.
        var bench: [Pick] = []
        var rules: [DungeonRule] = []

        struct Pick: Sendable {
            let candidate: DungeonCandidate
            let member: ExpeditionMember
        }

        /// How far the search goes: every team `screen` runs; from the `climbFrom` best not climbed from yet, every
        /// team one swap away, `climbs` times; then each round's `keep` best played until `runs` in all. Measured on the
        /// owner's save on 2026-11-13 (release build, 10 cores): 3 to 6 s, about 8,000 runs; the team kept won 99% of
        /// 600 other runs of the day dungeon (84% for the old pick), 99% of the weekly one's (52% for the first start).
        struct Search: Sendable {
            var screen = 16
            var climbs = 2
            var climbFrom = 1
            var rounds: [Round] = [Round(keep: 12, runs: 64), Round(keep: 4, runs: 200), Round(keep: 2, runs: 400)]

            struct Round: Sendable {
                let keep: Int
                let runs: Int
            }
        }

        /// What a team's runs gave: the wins, then the share of its HP the team kept in them, which tells apart teams
        /// winning as often.
        struct Tally: Sendable {
            var runs = 0
            var wins = 0
            var hpKept = 0.0

            mutating func add(_ other: Tally) {
                runs += other.runs
                wins += other.wins
                hpKept += other.hpKept
            }
        }

        func run(_ search: Search = Search()) -> [String] {
            guard let first = teams.first else { return [] }
            guard teams.count > 1 || !bench.isEmpty else { return first.map(\.entryID) }
            var tried: [[ExpeditionMember]] = [], tallies: [Tally] = [], seen = Set<[String]>()
            func fresh(_ team: [ExpeditionMember]) -> Bool { seen.insert(team.map(\.entryID).sorted()).inserted }
            func play(_ indices: [Int], from: Int, to: Int) {
                guard to > from else { return }
                let chunk = 8
                let work = indices.flatMap { i in stride(from: from, to: to, by: chunk).map { (i, $0, min($0 + chunk, to)) } }
                let teams = tried, dungeon = self.dungeon, boss = self.boss, berries = self.berries, revives = self.revives
                let results = BattleEngine.parallelMap(work) { item in
                    var tally = Tally()
                    for run in item.1..<item.2 {
                        tally.add(DungeonTeamBuilder.play(team: teams[item.0], dungeon: dungeon, run: run, berries: berries,
                                                          revives: revives, boss: boss))
                    }
                    return tally
                }
                for (k, item) in work.enumerated() { tallies[item.0].add(results[k]) }
            }
            /// The best first: wins, then the HP kept, then the order they came in (the theme's best first).
            func ranking(_ indices: [Int]) -> [Int] {
                indices.sorted { a, b in
                    (tallies[a].wins, tallies[a].hpKept, -a) > (tallies[b].wins, tallies[b].hpKept, -b)
                }
            }
            func admit(_ new: [[ExpeditionMember]]) -> [Int] {
                let start = tried.count
                for team in new where fresh(team) {
                    tried.append(team)
                    tallies.append(Tally())
                }
                return Array(start..<tried.count)
            }
            play(admit(teams), from: 0, to: search.screen)
            var climbed = Set<Int>()
            for _ in 0..<search.climbs {
                let from = ranking(Array(tried.indices)).filter { !climbed.contains($0) }.prefix(search.climbFrom)
                climbed.formUnion(from)
                let added = admit(from.flatMap { swaps(of: tried[$0]) })
                guard !added.isEmpty else { break }
                play(added, from: 0, to: search.screen)
            }
            var alive = ranking(Array(tried.indices)), played = search.screen
            for round in search.rounds where alive.count > 1 && round.runs > played {
                alive = Array(alive.prefix(round.keep))
                play(alive, from: played, to: round.runs)
                played = round.runs
                alive = ranking(alive)
            }
            return tried[alive[0]].map(\.entryID)
        }

        /// Every valid team one Pokémon of the bench away from `team`, the swapped one in its place.
        func swaps(of team: [ExpeditionMember]) -> [[ExpeditionMember]] {
            let known = Dictionary(bench.map { ($0.member.entryID, $0.candidate) }, uniquingKeysWith: { first, _ in first })
            guard let members = Optional(team.compactMap { known[$0.entryID] }), members.count == team.count else { return [] }
            var out: [[ExpeditionMember]] = []
            for slot in team.indices {
                for pick in bench where !team.contains(where: { $0.entryID == pick.member.entryID }) {
                    var candidates = members
                    candidates[slot] = pick.candidate
                    guard DungeonTeamRules.isValid(candidates, size: team.count, rules: rules) else { continue }
                    var next = team
                    next[slot] = pick.member
                    out.append(next)
                }
            }
            return out
        }
    }

    /// One expedition of `team`, as the odds play it (`odds`'s seeds): won or not, and the share of its HP it kept.
    static func play(team: [ExpeditionMember], dungeon: Dungeon, run: Int, seed: UInt64 = 1,
                     berries: [BattleBerry: Int] = [:], revives: [String: Int] = [:],
                     boss: ExpeditionBoss? = nil) -> ComposeChoice.Tally {
        let context = ExpeditionContext(tier: dungeon.tier, shinyDenominator: 64, now: Date(timeIntervalSince1970: 0))
        var expedition = ExpeditionEngine.start(dungeon: dungeon, team: team, rules: dungeon.rules,
                                                teamSize: team.count, seed: seed &+ UInt64(run) &* 7919,
                                                cost: dungeon.floors * 1000, berries: berries, revives: revives,
                                                context: context, boss: boss)
        // Bounded: every feed walks a floor or ends the run.
        for _ in 0...(dungeon.floors * 4) {
            if case .capture = expedition.phase { break }
            if expedition.isOver { break }
            ExpeditionEngine.feed(&expedition, tokens: expedition.floorCost, context: context)
            if case .awaitingHeal = expedition.phase {
                ExpeditionEngine.answerHeal(&expedition, paid: false, context: context)
            }
        }
        var won = false
        if case .capture = expedition.phase { won = true } else if case .finished(won: true) = expedition.phase { won = true }
        guard won else { return .init(runs: 1, wins: 0, hpKept: 0) }
        let hp = expedition.team.reduce(0) { $0 + max(0, $1.spec.hp) }
        let full = max(1, expedition.team.reduce(0) { $0 + $1.spec.stats.hp })
        return .init(runs: 1, wins: 1, hpKept: Double(hp) / Double(full))
    }

    /// The share of `runs` expeditions this team wins: every floor, then its boss falling.
    static func winOdds(team: [ExpeditionMember], dungeon: Dungeon, runs: Int = 24, seed: UInt64 = 1,
                        boss: ExpeditionBoss? = nil) -> Double {
        guard !team.isEmpty, runs > 0 else { return 0 }
        let context = ExpeditionContext(tier: dungeon.tier, shinyDenominator: 64, now: Date(timeIntervalSince1970: 0))
        var won = 0
        for run in 0..<runs {
            var expedition = ExpeditionEngine.start(dungeon: dungeon, team: team, rules: dungeon.rules,
                                                    teamSize: team.count, seed: seed &+ UInt64(run) &* 7919,
                                                    cost: dungeon.floors * 1000, berries: [:], revives: [:],
                                                    context: context, boss: boss)
            // Bounded: every feed walks a floor or ends the run.
            for _ in 0...(dungeon.floors * 4) {
                if case .capture = expedition.phase { break }
                if expedition.isOver { break }
                ExpeditionEngine.feed(&expedition, tokens: expedition.floorCost, context: context)
                if case .awaitingHeal = expedition.phase {
                    ExpeditionEngine.answerHeal(&expedition, paid: false, context: context)
                }
            }
            if case .capture = expedition.phase { won += 1 } else if case .finished(won: true) = expedition.phase { won += 1 }
        }
        return Double(won) / Double(runs)
    }

    /// What `reachOdds` runs on, built on the main thread (`CompanionStore.reachEstimate`), run off it.
    struct ReachEstimate: Sendable {
        let team: [ExpeditionMember]
        let dungeon: Dungeon
        let berries: [BattleBerry: Int]
        let revives: [String: Int]
        let boss: ExpeditionBoss?

        func run() -> Odds {
            DungeonTeamBuilder.odds(team: team, dungeon: dungeon, berries: berries, revives: revives, boss: boss)
        }
    }

    /// R7 and the owner's ask of 2026-11-06 ("a player with no good Pokémon should not enter"): the share of runs that
    /// reach the boss, and of those that win, the boss falling. A dungeon's boss is drawn as at the entry, so the
    /// second is its odds over every boss it may hold, never telling which.
    struct Odds: Sendable, Equatable {
        let reach: Double
        let win: Double
    }

    static func odds(team: [ExpeditionMember], dungeon: Dungeon, runs: Int = 24, seed: UInt64 = 1,
                     berries: [BattleBerry: Int] = [:], revives: [String: Int] = [:], boss: ExpeditionBoss? = nil) -> Odds {
        guard !team.isEmpty, runs > 0 else { return Odds(reach: 0, win: 0) }
        let context = ExpeditionContext(tier: dungeon.tier, shinyDenominator: 64, now: Date(timeIntervalSince1970: 0))
        var reached = 0, won = 0
        for run in 0..<runs {
            var expedition = ExpeditionEngine.start(dungeon: dungeon, team: team, rules: dungeon.rules,
                                                    teamSize: team.count, seed: seed &+ UInt64(run) &* 7919,
                                                    cost: dungeon.floors * 1000, berries: berries, revives: revives,
                                                    context: context, boss: boss)
            var atBoss = false
            // Bounded: every feed walks a floor or ends the run.
            for _ in 0...(dungeon.floors * 4) {
                if case .capture = expedition.phase { break }
                if expedition.isOver { break }
                if !atBoss, expedition.floor >= expedition.floors, !expedition.team.allSatisfy(\.isFainted) { atBoss = true }
                ExpeditionEngine.feed(&expedition, tokens: expedition.floorCost, context: context)
                if case .awaitingHeal = expedition.phase {
                    ExpeditionEngine.answerHeal(&expedition, paid: false, context: context)
                }
            }
            let win: Bool
            if case .capture = expedition.phase { win = true } else if case .finished(won: true) = expedition.phase { win = true } else { win = false }
            if atBoss || win { reached += 1 }
            if win { won += 1 }
        }
        return Odds(reach: Double(reached) / Double(runs), win: Double(won) / Double(runs))
    }

    /// R7: the share of `runs` expeditions that reach the boss, the boss itself left out.
    static func reachOdds(team: [ExpeditionMember], dungeon: Dungeon, runs: Int = 24, seed: UInt64 = 1,
                          berries: [BattleBerry: Int] = [:], revives: [String: Int] = [:],
                          boss: ExpeditionBoss? = nil) -> Double {
        guard !team.isEmpty, runs > 0 else { return 0 }
        let context = ExpeditionContext(tier: dungeon.tier, shinyDenominator: 64, now: Date(timeIntervalSince1970: 0))
        var reached = 0
        for run in 0..<runs {
            var expedition = ExpeditionEngine.start(dungeon: dungeon, team: team, rules: dungeon.rules,
                                                    teamSize: team.count, seed: seed &+ UInt64(run) &* 7919,
                                                    cost: dungeon.floors * 1000, berries: berries, revives: revives,
                                                    context: context, boss: boss)
            // Walk every floor but the boss's; an emergency heal is taken, as the estimate assumes the player answers.
            while expedition.floor < expedition.floors, !expedition.isOver {
                ExpeditionEngine.feed(&expedition, tokens: expedition.floorCost, context: context)
                if case .awaitingHeal = expedition.phase {
                    ExpeditionEngine.answerHeal(&expedition, paid: false, context: context)
                }
            }
            if !expedition.isOver, !expedition.team.allSatisfy(\.isFainted) { reached += 1 }
        }
        return Double(reached) / Double(runs)
    }
}
