import Foundation

/// Practice opponent. Usually picks the move with the best expected damage, sometimes a random one,
/// and never switches voluntarily — enough to be a fair sparring partner without reading ahead.
enum BattleCPU {
    static let randomMovePercent = 25

    static func action(for side: BattleSide, in state: BattleState, rng: inout BattleRNG) -> BattleAction {
        let moves = state.usableMoves(for: side)
        guard !moves.isEmpty else { return .struggle }
        if rng.percent(randomMovePercent) { return .move(moves[rng.below(moves.count)]) }
        let attacker = state[side].current.pokemon
        let defender = state[side.opponent].current.pokemon
        var best = moves[0]
        for index in moves.dropFirst()
        where score(attacker.moves[index], attacker, defender) > score(attacker.moves[best], attacker, defender) {
            best = index
        }
        return .move(best)
    }

    static func replacement(for side: BattleSide, in state: BattleState) -> Int? {
        let defender = state[side.opponent].current.pokemon
        return state.switchTargets(for: side).max { lhs, rhs in
            bestScore(state[side].team[lhs].pokemon, defender) < bestScore(state[side].team[rhs].pokemon, defender)
        }
    }

    /// Expected damage proxy: power × effectiveness × STAB × accuracy. Status moves get a small fixed value
    /// so a Pokémon without attacks still uses them instead of standing still.
    static func score(_ move: BattleMove, _ attacker: BattlePokemon, _ defender: BattlePokemon) -> Int {
        guard move.isSupportedInBattle else { return -1 }
        guard move.isDamaging else { return 20 * 4 * 2 * 100 }
        let effectiveness = BattleTypeChart.effectiveness(of: move.type, against: defender.types)
        let stab = attacker.types.contains(move.type) ? 3 : 2
        return (move.power ?? 0) * effectiveness * stab * (move.accuracy ?? 100)
    }

    private static func bestScore(_ attacker: BattlePokemon, _ defender: BattlePokemon) -> Int {
        attacker.moves.map { score($0, attacker, defender) }.max() ?? 0
    }
}

/// Builds a practice team: one random Gen I–V species per player slot, at the same level,
/// with its own rolled individual values and the moves it would know at that level.
struct BattleOpponentFactory: Sendable {
    let details: any PokemonDetailProviding
    let moves: any BattleMoveProviding
    let speciesNames: @Sendable (Int) async -> [String: String]

    func team(matching player: BattleTeam, seed: UInt64) async throws -> BattleTeam {
        var rng = BattleRNG(seed: seed)
        var entries: [DexEntry] = []
        var used = Set<Int>()
        for member in player.members {
            var speciesID: Int
            var profile: PokemonProfile
            repeat {
                repeat {
                    speciesID = PokemonAssets.animatedSpeciesIDs.lowerBound + rng.below(PokemonAssets.animatedSpeciesIDs.count)
                } while used.contains(speciesID) || speciesID == PokemonOdds.dittoSpeciesID
                used.insert(speciesID)
                let speciesDetails = try await details.pokemonDetails(speciesID: speciesID)
                profile = PokemonProfile.generate(seed: rng.next(), instanceID: "cpu-\(entries.count)")
                profile.level = member.level
                profile.enrich(with: speciesDetails)
            } while profile.moves.isEmpty
            let nature = PokemonNature.allCases[rng.below(PokemonNature.allCases.count)]
            entries.append(DexEntry(id: profile.instanceID, baseID: speciesID, finalID: speciesID,
                                    chainOrder: [speciesID], rarity: .common, caughtAt: nil, nature: nature,
                                    profile: profile, names: [speciesID: await speciesNames(speciesID)]))
        }
        return try await BattleTeamLoader(details: details, moves: moves).load(entries)
    }
}
