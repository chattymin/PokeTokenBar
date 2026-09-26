import Foundation

/// Practice opponent. Usually picks the move with the best expected damage, sometimes a random one,
/// and never switches voluntarily — enough to be a fair sparring partner without reading ahead.
enum BattleCPU {
    static let randomMovePercent = 25

    static func action(for side: BattleSide, in state: BattleState, rng: inout BattleRNG) -> BattleAction {
        let moves = state.usableMoves(for: side)
        guard !moves.isEmpty else { return .struggle }
        if rng.percent(randomMovePercent) { return .move(moves[rng.below(moves.count)]) }
        let known = state[side].current.moves
        var best = moves[0]
        for index in moves.dropFirst()
        where score(known[index], by: side, in: state) > score(known[best], by: side, in: state) {
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

    /// Expected-value proxy in "power × effectiveness × STAB × accuracy" units. Status moves only score
    /// when they can still do something, so the CPU does not paralyze what is already paralyzed.
    static func score(_ move: BattleMove, by side: BattleSide, in state: BattleState) -> Int {
        guard move.isSupportedInBattle else { return -1 }
        let user = state[side].current, target = state[side.opponent].current
        let accuracy = move.accuracy ?? 100
        if move.isDamaging {
            let effectiveness = state.effectiveness(of: move, type: move.type, against: side.opponent)
            if move.damageRule != nil || move.kind == .ohko { return effectiveness > 0 ? 60 * 4 * 2 * accuracy : 0 }
            let stab = user.types.contains(move.type) ? 3 : 2
            var value = (state.effectivePower(of: move, by: side) ?? 60) * effectiveness * stab * accuracy
            // Moves that cost a turn or the user are worth less than their power suggests.
            switch move.kind {
            case .recharge, .charge: value = value * 2 / 3
            case .selfDestruct: value = user.hp * 4 < user.maxHP ? value : value / 4
            default: break
            }
            return value
        }
        switch move.kind {
        case .effect(.protect), .effect(.endure): return 5 * 4 * 2 * 100
        case .effect(.rest):
            return user.hp * 2 < user.maxHP && user.status != .sleep ? 90 * 4 * 2 * 100 : 0
        case .effect(let effect):
            return uniqueScore(effect, user: user, target: target, state: state, side: side)
        default:
            break
        }
        switch move.inflictedAilment {
        case .major(let status):
            let affected = target.status == nil && target.types.allSatisfy { !status.immuneTypes.contains($0) }
            // Worth about a 70-power hit: better than a weak STAB move, worse than a strong one.
            return affected ? 70 * 4 * 2 * accuracy : 0
        case .confusion:
            return target.volatiles.confusionTurns == 0 ? 30 * 4 * 2 * accuracy : 0
        case .triAttack, nil:
            return 20 * 4 * 2 * 100
        }
    }

    /// Setup and field moves score once; using them again while they are still active would fail.
    private static func uniqueScore(_ effect: BattleUniqueEffect, user: BattleCombatant, target: BattleCombatant,
                                    state: BattleState, side: BattleSide) -> Int {
        let useful: Bool
        switch effect {
        case .screen(let barrier): useful = !state[side].conditions.has(barrier)
        case .weather(let weather): useful = state.field.weather != weather
        case .hazard(let hazard):
            let conditions = state[side.opponent].conditions
            useful = hazard == .spikes ? conditions.spikes < 3 : hazard == .toxicSpikes ? conditions.toxicSpikes < 2 : !conditions.stealthRock
        case .leechSeed: useful = !target.volatiles.leechSeeded && !target.types.contains("grass")
        case .taunt: useful = target.volatiles.tauntTurns == 0
        case .focusEnergy: useful = !user.volatiles.focusEnergy
        case .curse: useful = user.types.contains("ghost") ? !target.volatiles.cursed && user.hp * 2 > user.maxHP : true
        case .yawn: useful = target.status == nil && target.volatiles.yawnTurns == 0
        case .bellyDrum: useful = user.hp * 2 > user.maxHP && user.stages.attack < 6
        case .splash, .noEffectHere, .failsInSingles: useful = false
        default: useful = true
        }
        return useful ? 25 * 4 * 2 * 100 : 0
    }

    private static func bestScore(_ attacker: BattlePokemon, _ defender: BattlePokemon) -> Int {
        attacker.moves.filter(\.isDamaging).map { move in
            (move.power ?? 60) * BattleTypeChart.effectiveness(of: move.type, against: defender.types)
                * (attacker.types.contains(move.type) ? 3 : 2)
        }.max() ?? 0
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
