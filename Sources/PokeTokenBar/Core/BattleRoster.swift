import Foundation

/// A value copy of an owned individual. Preparing a battle never writes to the companion save.
struct OwnedBattlePokemon: Identifiable, Sendable {
    let id: String
    let speciesID: Int
    let names: [String: String]
    let isShiny: Bool
    let form: PokemonForm?
    let isActive: Bool
    let rarity: Rarity
    let profile: PokemonProfile?
    let nature: PokemonNature?

    var level: Int { profile?.level ?? 0 }

    func displayName(language: AppLanguage) -> String {
        language.resolveName(names) ?? "#\(speciesID)"
    }
}

enum BattlePreparationError: Error, Equatable {
    case missingProfile
    case invalidProfile
    case invalidMetadata
    case noSupportedMoves
}

/// Explains how the practice moveset relates to the four moves shown in the profile.
struct BattleMoveAvailability: Sendable, Equatable {
    let knownMoves: [PokemonKnownMove]
    let unsupportedKnownMoves: [PokemonKnownMove]
    let recalledMoves: [BattleMove]
    let usesPracticeStrike: Bool
    let selectedMoves: [BattleMove]
}

struct PreparedBattlePokemon: Sendable {
    let combatant: BattleCombatant
    let moveAvailability: BattleMoveAvailability
}

enum BattleRoster {
    static func moveAvailability(details: PokemonDetails, level: Int) -> BattleMoveAvailability {
        let history = details.levelUpMoves(through: level)
        let known = Array(history.suffix(4))
        let supported = BattleMoveCatalog.moves(for: known)
        let unsupported = known.filter { BattleMoveCatalog.move(named: $0.name) == nil }
        var selected = supported
        var recalled: [BattleMove] = []
        var practice = false
        // Preserve the profile's current moves first. Recall one earlier attack only when
        // necessary to keep the practice match playable, and expose that choice to the UI.
        if !selected.contains(where: { $0.category != .status }) {
            if let attack = history.reversed().compactMap({ BattleMoveCatalog.move(named: $0.name) })
                .first(where: { $0.category != .status }) {
                selected = Array(selected.suffix(3)) + [attack]
                recalled = [attack]
            } else {
                selected = Array(selected.suffix(3)) + [BattleMoveCatalog.practiceStrike]
                practice = true
            }
        }
        return BattleMoveAvailability(knownMoves: known, unsupportedKnownMoves: unsupported,
                                      recalledMoves: recalled, usesPracticeStrike: practice,
                                      selectedMoves: selected)
    }

    static func prepareWithAvailability(_ candidate: OwnedBattlePokemon, language: AppLanguage,
                                       provider: any PokemonDetailProviding = PokeAPIClient.shared) async throws -> PreparedBattlePokemon {
        guard candidate.profile != nil else { throw BattlePreparationError.missingProfile }
        let details = try await provider.pokemonDetails(speciesID: candidate.speciesID)
        let combatant = try prepare(candidate, details: details, language: language)
        return PreparedBattlePokemon(combatant: combatant,
                                     moveAvailability: moveAvailability(details: details, level: combatant.level))
    }

    /// Evolution stages in a Pokédex line are appearances of one individual, not extra combatants.
    static func candidates(from state: CompanionState,
                           activeNames: [String: String] = [:]) -> [OwnedBattlePokemon] {
        var result: [OwnedBattlePokemon] = []
        if let active = state.active {
            result.append(OwnedBattlePokemon(
                id: active.profile?.instanceID ?? "active-missing-profile",
                speciesID: active.currentID, names: activeNames,
                isShiny: active.displaysShiny, form: active.form,
                isActive: true, rarity: active.rarity,
                profile: active.profile, nature: active.nature))
        }
        result += state.dex.map { entry in
            OwnedBattlePokemon(
                id: entry.profile?.instanceID ?? "dex:\(entry.id)",
                speciesID: entry.finalID, names: entry.names?[entry.finalID] ?? [:],
                isShiny: entry.isShiny, form: entry.form,
                isActive: false, rarity: entry.rarity,
                profile: entry.profile, nature: entry.nature)
        }
        // Imported saves can contain the same instance more than once. Do not offer it as two sides.
        var seen = Set<String>()
        return result.filter { seen.insert($0.id).inserted }
    }

    static func prepare(_ candidate: OwnedBattlePokemon, language: AppLanguage,
                        provider: any PokemonDetailProviding = PokeAPIClient.shared) async throws -> BattleCombatant {
        guard candidate.profile != nil else { throw BattlePreparationError.missingProfile }
        let details = try await provider.pokemonDetails(speciesID: candidate.speciesID)
        return try prepare(candidate, details: details, language: language)
    }

    static func prepare(_ candidate: OwnedBattlePokemon, details: PokemonDetails,
                        language: AppLanguage) throws -> BattleCombatant {
        guard var profile = candidate.profile else { throw BattlePreparationError.missingProfile }
        guard !profile.instanceID.isEmpty, profile.instanceID == candidate.id,
              (5...100).contains(profile.level),
              PokemonStatCalculator.order.allSatisfy({ (0...31).contains(profile.ivs[$0]) }) else {
            throw BattlePreparationError.invalidProfile
        }
        guard (1...649).contains(candidate.speciesID), details.speciesID == candidate.speciesID,
              !details.types.isEmpty, details.types.count <= 2,
              Set(details.types).count == details.types.count,
              details.types.allSatisfy({ BattleTypeChart.types.contains($0) }),
              PokemonStatCalculator.order.allSatisfy({ (1...1000).contains(details.baseStats[$0] ?? 0) }) else {
            throw BattlePreparationError.invalidMetadata
        }
        // Deferred profiles are completed on this local copy only. Rebuilding from the legal
        // learnset also prevents stale moves from an earlier evolution entering the battle.
        profile.enrich(with: details)
        let moves = moveAvailability(details: details, level: profile.level).selectedMoves
        let computed = Dictionary(uniqueKeysWithValues:
            PokemonStatCalculator.stats(details: details, profile: profile, nature: candidate.nature)
                .map { ($0.name, $0.value) })
        let stats = BattleStats(hp: computed["hp"]!, attack: computed["attack"]!,
                                defense: computed["defense"]!, specialAttack: computed["special-attack"]!,
                                specialDefense: computed["special-defense"]!, speed: computed["speed"]!)
        return BattleCombatant(id: candidate.id, speciesID: candidate.speciesID,
                               name: language.resolveName(candidate.names)
                                ?? PokemonNameLocalization.identifier(details.name),
                               level: profile.level, types: details.types, stats: stats, moves: moves)
    }
}
