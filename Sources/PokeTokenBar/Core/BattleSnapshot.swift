import Foundation

/// Fixed fields instead of `[String: Int]`: both peers must iterate stats in the same order.
struct BattleStats: Codable, Sendable, Equatable {
    let hp: Int
    let attack: Int
    let defense: Int
    let specialAttack: Int
    let specialDefense: Int
    let speed: Int
}

/// One fully resolved team member. Peers exchange these so both battle engines consume identical
/// input, independent of each side's PokéAPI cache age.
struct BattlePokemon: Codable, Sendable, Equatable {
    let instanceID: String
    let speciesID: Int
    let names: [String: String]
    let level: Int
    let isShiny: Bool
    let unownForm: UnownForm?
    let gender: PokemonGender?
    let nature: PokemonNature?
    let abilityName: String?
    let types: [String]
    let stats: BattleStats
    let moves: [BattleMove]
}

struct BattleTeam: Codable, Sendable, Equatable {
    static let maxSize = 6
    let members: [BattlePokemon]

    init(members: [BattlePokemon]) throws(BattleSnapshotError) {
        guard (1...Self.maxSize).contains(members.count) else { throw .invalidTeamSize(members.count) }
        var seen = Set<String>()
        for member in members where !seen.insert(member.instanceID).inserted {
            throw .duplicateMember(member.instanceID)
        }
        self.members = members
    }
}

enum BattleSnapshotError: Error, Equatable, Sendable {
    case missingProfile(entryID: String)
    case notEnriched(entryID: String)
    case incompleteStats(entryID: String)
    case missingMove(entryID: String, move: String)
    case invalidTeamSize(Int)
    case duplicateMember(String)
}

enum BattleSnapshotBuilder {
    static func pokemon(from entry: DexEntry, details: PokemonDetails,
                        moves: [String: BattleMove]) throws(BattleSnapshotError) -> BattlePokemon {
        guard let profile = entry.profile else { throw .missingProfile(entryID: entry.id) }
        // `enrich` always equips at least one level-up move; none means details never loaded for it.
        guard !profile.moves.isEmpty else { throw .notEnriched(entryID: entry.id) }

        let computed = PokemonStatCalculator.stats(details: details, profile: profile, nature: entry.nature)
        func stat(_ name: String) throws(BattleSnapshotError) -> Int {
            guard let value = computed.first(where: { $0.name == name })?.value else {
                throw .incompleteStats(entryID: entry.id)
            }
            return value
        }
        let stats = BattleStats(
            hp: try stat("hp"), attack: try stat("attack"), defense: try stat("defense"),
            specialAttack: try stat("special-attack"), specialDefense: try stat("special-defense"),
            speed: try stat("speed"))

        var resolved: [BattleMove] = []
        for known in profile.moves.prefix(4) {
            guard let move = moves[known.name] else { throw .missingMove(entryID: entry.id, move: known.name) }
            resolved.append(move.name == HiddenPower.moveName ? move.withType(HiddenPower.type(for: profile.ivs)) : move)
        }

        return BattlePokemon(
            instanceID: profile.instanceID,
            speciesID: entry.finalID,
            names: entry.names?[entry.finalID] ?? [:],
            level: profile.level,
            isShiny: entry.isShiny,
            unownForm: entry.unownForm,
            gender: profile.gender,
            nature: entry.nature,
            abilityName: profile.abilityName,
            types: details.types,
            stats: stats,
            moves: resolved)
    }
}

enum HiddenPower {
    static let moveName = "hidden-power"
    private static let types = ["fighting", "flying", "poison", "ground", "rock", "bug", "ghost", "steel",
                                "fire", "water", "grass", "electric", "psychic", "ice", "dragon", "dark"]

    /// Main-series formula (Gen III+): the lowest bit of each IV, in HP/Atk/Def/Spe/SpA/SpD order.
    static func type(for ivs: PokemonIVs) -> String {
        let ordered = [ivs.hp, ivs.attack, ivs.defense, ivs.speed, ivs.specialAttack, ivs.specialDefense]
        let bits = ordered.enumerated().reduce(0) { $0 + (($1.element & 1) << $1.offset) }
        return types[bits * 15 / 63]
    }
}

/// Resolves team entries into a battle snapshot. Missing data fails loudly rather than
/// silently dropping a move, which would make the team differ from what the player picked.
struct BattleTeamLoader: Sendable {
    let details: any PokemonDetailProviding
    let moves: any BattleMoveProviding

    func load(_ entries: [DexEntry]) async throws -> BattleTeam {
        let moveNames = Set(entries.flatMap { $0.profile?.moves.prefix(4).map(\.name) ?? [] })
        let provider = moves
        let movesByName = try await withThrowingTaskGroup(of: BattleMove.self) { group in
            for name in moveNames { group.addTask { try await provider.move(named: name) } }
            var result: [String: BattleMove] = [:]
            for try await move in group { result[move.name] = move }
            return result
        }
        var members: [BattlePokemon] = []
        for entry in entries {
            let speciesDetails = try await details.pokemonDetails(speciesID: entry.finalID)
            members.append(try BattleSnapshotBuilder.pokemon(from: entry, details: speciesDetails, moves: movesByName))
        }
        return try BattleTeam(members: members)
    }
}
