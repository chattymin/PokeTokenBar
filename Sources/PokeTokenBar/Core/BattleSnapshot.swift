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
    /// PokéAPI hectograms; Heavy Slam, Heat Crash, Low Kick and Grass Knot scale with it.
    var weight = 100
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

    private enum CodingKeys: String, CodingKey { case members }

    /// A team decoded from a peer is untrusted: the same invariants as the local init, plus value ranges
    /// the engine relies on (a zero-HP or seven-member team would otherwise reach it).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let members = try container.decode([BattlePokemon].self, forKey: .members)
        guard members.allSatisfy(\.isPlausible) else {
            throw DecodingError.dataCorruptedError(forKey: .members, in: container, debugDescription: "implausible member")
        }
        do {
            try self.init(members: members)
        } catch {
            throw DecodingError.dataCorruptedError(forKey: .members, in: container, debugDescription: "\(error)")
        }
    }
}

extension BattlePokemon {
    var isPlausible: Bool {
        let statValues = [stats.hp, stats.attack, stats.defense, stats.specialAttack, stats.specialDefense, stats.speed]
        guard (1...64).contains(instanceID.count), (1...100).contains(level) else { return false }
        guard statValues.allSatisfy({ (1...9_999).contains($0) }) else { return false }
        guard (1...2).contains(types.count), types.allSatisfy({ (1...20).contains($0.count) }) else { return false }
        guard moves.count <= 4, moves.allSatisfy(\.isPlausible), (1...9_999).contains(weight) else { return false }
        return names.count <= 64 && names.allSatisfy { $0.key.count <= 16 && $0.value.count <= 64 }
    }
}

extension BattleMove {
    /// The ranges `init(dto:)` clamps to; anything outside them did not come from this app.
    var isPlausible: Bool {
        guard (1...80).contains(name.count), (1...20).contains(type.count) else { return false }
        if let power, !(1...250).contains(power) { return false }
        if let accuracy, !(1...100).contains(accuracy) { return false }
        guard (1...64).contains(pp), (-7...5).contains(priority) else { return false }
        guard statChanges.count <= 7, statChanges.allSatisfy({ (-6...6).contains($0.change) }) else { return false }
        let chances: [Int] = [statChance, ailmentChance, flinchChance]
        guard chances.allSatisfy({ (0...100).contains($0) }), (0...6).contains(critRate) else { return false }
        return (-100...100).contains(drain) && (-100...100).contains(healing)
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
            moves: resolved,
            weight: min(9_999, max(1, details.weight)))
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
