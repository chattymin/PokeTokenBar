import Foundation

/// Immutable PokéAPI combat metadata for one default Pokémon form.
/// This is cached separately from the user's save; only rolled individual values live in `PokemonProfile`.
struct PokemonDetails: Codable, Sendable, Equatable {
    let speciesID: Int
    let name: String
    let height: Int                 // PokéAPI decimetres
    let weight: Int                 // PokéAPI hectograms
    let baseExperience: Int?
    let genderRate: Int             // female eighths; -1 = genderless
    let types: [String]
    let baseStats: [String: Int]
    let abilities: [PokemonAbilityOption]
    let moves: [PokemonMoveOption]

    var baseStatTotal: Int { baseStats.values.reduce(0, +) }

    /// PokeTokenBar supports animated sprites through Gen V, so use the latest matching learnset.
    static let preferredVersionGroup = "black-2-white-2"

    func levelUpMoves(through level: Int) -> [PokemonKnownMove] {
        var bestByName: [String: Int] = [:]
        for move in moves {
            let matching = move.learnMethods.filter {
                $0.method == "level-up" && $0.level <= level
            }
            guard let learnedAt = matching.map(\.level).min() else { continue }
            bestByName[move.name] = min(bestByName[move.name] ?? learnedAt, learnedAt)
        }
        return bestByName.map { PokemonKnownMove(name: $0.key, learnedAtLevel: $0.value) }
            .sorted {
                if $0.learnedAtLevel != $1.learnedAtLevel { return $0.learnedAtLevel < $1.learnedAtLevel }
                return $0.name < $1.name
            }
    }
}

struct PokemonAbilityOption: Codable, Sendable, Equatable {
    let name: String
    let slot: Int
    let isHidden: Bool
}

struct PokemonMoveOption: Codable, Sendable, Equatable, Identifiable {
    var id: String { name }
    let name: String
    let learnMethods: [PokemonMoveLearnMethod]
}

struct PokemonMoveLearnMethod: Codable, Sendable, Equatable {
    let method: String
    let level: Int
}

enum PokemonGender: String, Codable, Sendable, CaseIterable {
    case male
    case female
    case genderless
}

struct PokemonIVs: Codable, Sendable, Equatable {
    var hp: Int
    var attack: Int
    var defense: Int
    var specialAttack: Int
    var specialDefense: Int
    var speed: Int

    subscript(stat: String) -> Int {
        switch stat {
        case "hp": return hp
        case "attack": return attack
        case "defense": return defense
        case "special-attack": return specialAttack
        case "special-defense": return specialDefense
        case "speed": return speed
        default: return 0
        }
    }
}

struct PokemonKnownMove: Codable, Sendable, Equatable, Identifiable {
    var id: String { name }
    let name: String
    let learnedAtLevel: Int
}

/// Values that make one caught Pokémon distinct from another.
/// `seed` keeps deferred/offline enrichment deterministic; explicit results are persisted once resolved.
struct PokemonProfile: Codable, Sendable, Equatable {
    var instanceID: String
    var seed: UInt64
    var gender: PokemonGender?
    var ivs: PokemonIVs
    var abilitySlot: Int?
    var abilityName: String?
    var abilityIsHidden: Bool
    var level: Int
    var growthTokens: Int
    var moves: [PokemonKnownMove]

    static func generate(seed: UInt64, growthTokens: Int = 0,
                         instanceID: String = UUID().uuidString) -> PokemonProfile {
        var random = ProfileRNG(seed: seed)
        let ivs = PokemonIVs(
            hp: Int(random.next() % 32),
            attack: Int(random.next() % 32),
            defense: Int(random.next() % 32),
            specialAttack: Int(random.next() % 32),
            specialDefense: Int(random.next() % 32),
            speed: Int(random.next() % 32))
        return PokemonProfile(
            instanceID: instanceID,
            seed: seed,
            gender: nil,
            ivs: ivs,
            abilitySlot: nil,
            abilityName: nil,
            abilityIsHidden: false,
            level: 5,
            growthTokens: max(0, growthTokens),
            moves: [])
    }

    /// Ditto's disguise is a different species identity, not an evolution. Keep the individual
    /// values, but reroll every species-dependent field once Ditto's own metadata is available.
    mutating func rebaseForSpeciesIdentity(growthTokens: Int, rarity: Rarity) {
        gender = nil
        abilitySlot = nil
        abilityName = nil
        abilityIsHidden = false
        moves = []
        self.growthTokens = min(SaveTransfer.maxTokenValue, max(0, growthTokens))
        applyGrowth(0, rarity: rarity)
    }

    mutating func enrich(with details: PokemonDetails) {
        var random = ProfileRNG(seed: seed ^ 0xA11B_1E5D_9EED)
        if gender == nil {
            if details.genderRate < 0 {
                gender = .genderless
            } else {
                gender = Int(random.next() % 8) < details.genderRate ? .female : .male
            }
        }

        let normal = details.abilities.filter { !$0.isHidden }.sorted { $0.slot < $1.slot }
        let hidden = details.abilities.filter(\.isHidden).sorted { $0.slot < $1.slot }
        if abilitySlot == nil {
            // Hidden abilities are deliberately rare; regular slots are otherwise evenly selected.
            if !hidden.isEmpty, random.next() % 128 == 0 {
                abilitySlot = hidden[Int(random.next() % UInt64(hidden.count))].slot
                abilityIsHidden = true
            } else if !normal.isEmpty {
                abilitySlot = normal[Int(random.next() % UInt64(normal.count))].slot
                abilityIsHidden = false
            } else if let fallback = details.abilities.sorted(by: { $0.slot < $1.slot }).first {
                abilitySlot = fallback.slot
                abilityIsHidden = fallback.isHidden
            }
        }
        let chosen = details.abilities.first { $0.slot == abilitySlot && $0.isHidden == abilityIsHidden }
            ?? details.abilities.first { $0.slot == abilitySlot }
            ?? normal.first
            ?? hidden.first
        abilityName = chosen?.name
        if let chosen { abilitySlot = chosen.slot; abilityIsHidden = chosen.isHidden }

        // Automatic moveset: the four most recently learned legal level-up moves.
        moves = Array(details.levelUpMoves(through: level).suffix(4))
    }

    mutating func applyGrowth(_ delta: Int, rarity: Rarity) {
        growthTokens = min(SaveTransfer.maxTokenValue, max(0, growthTokens + max(0, delta)))
        let total = max(1, PokemonBalance.graduationTotal(rarity))
        let progress = min(1, Double(growthTokens) / Double(total))
        level = min(100, max(5, 5 + Int((progress * 95).rounded(.down))))
    }

    mutating func sanitize() {
        level = min(100, max(1, level))
        growthTokens = min(SaveTransfer.maxTokenValue, max(0, growthTokens))
        ivs.hp = min(31, max(0, ivs.hp))
        ivs.attack = min(31, max(0, ivs.attack))
        ivs.defense = min(31, max(0, ivs.defense))
        ivs.specialAttack = min(31, max(0, ivs.specialAttack))
        ivs.specialDefense = min(31, max(0, ivs.specialDefense))
        ivs.speed = min(31, max(0, ivs.speed))
        moves = Array(moves.prefix(4)).map {
            PokemonKnownMove(name: String($0.name.prefix(80)), learnedAtLevel: min(100, max(0, $0.learnedAtLevel)))
        }
        if instanceID.isEmpty { instanceID = UUID().uuidString }
    }
}

struct PokemonComputedStat: Identifiable, Sendable, Equatable {
    var id: String { name }
    let name: String
    let base: Int
    let iv: Int
    let value: Int
}

enum PokemonStatCalculator {
    static let order = ["hp", "attack", "defense", "special-attack", "special-defense", "speed"]

    static func displayScaleMaximum(for values: [Int]) -> Int {
        let highest = max(300, values.max() ?? 300)
        let remainder = highest % 100
        return remainder == 0 ? highest : highest + (100 - remainder)
    }

    static func stats(details: PokemonDetails, profile: PokemonProfile,
                      nature: PokemonNature?) -> [PokemonComputedStat] {
        order.compactMap { name in
            guard let base = details.baseStats[name] else { return nil }
            let iv = profile.ivs[name]
            let level = profile.level
            let value: Int
            if name == "hp" {
                value = ((2 * base + iv) * level) / 100 + level + 10
            } else {
                let neutral = ((2 * base + iv) * level) / 100 + 5
                value = Int((Double(neutral) * (nature?.modifier(for: name) ?? 1)).rounded(.down))
            }
            return PokemonComputedStat(name: name, base: base, iv: iv, value: value)
        }
    }
}

extension PokemonNature {
    /// Main-series nature modifiers. Neutral natures return 1.0 for every stat.
    func modifier(for stat: String) -> Double {
        let pair: (up: String, down: String)?
        switch self {
        case .lonely:  pair = ("attack", "defense")
        case .brave:   pair = ("attack", "speed")
        case .adamant: pair = ("attack", "special-attack")
        case .naughty: pair = ("attack", "special-defense")
        case .bold:    pair = ("defense", "attack")
        case .relaxed: pair = ("defense", "speed")
        case .impish:  pair = ("defense", "special-attack")
        case .lax:     pair = ("defense", "special-defense")
        case .timid:   pair = ("speed", "attack")
        case .hasty:   pair = ("speed", "defense")
        case .jolly:   pair = ("speed", "special-attack")
        case .naive:   pair = ("speed", "special-defense")
        case .modest:  pair = ("special-attack", "attack")
        case .mild:    pair = ("special-attack", "defense")
        case .quiet:   pair = ("special-attack", "speed")
        case .rash:    pair = ("special-attack", "special-defense")
        case .calm:    pair = ("special-defense", "attack")
        case .gentle:  pair = ("special-defense", "defense")
        case .sassy:   pair = ("special-defense", "speed")
        case .careful: pair = ("special-defense", "special-attack")
        case .hardy, .docile, .serious, .bashful, .quirky: pair = nil
        }
        guard let pair else { return 1 }
        if stat == pair.up { return 1.1 }
        if stat == pair.down { return 0.9 }
        return 1
    }
}

private struct ProfileRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}

enum PokemonProfileMigration {
    /// Stable across processes (unlike Swift's randomized `Hasher`).
    static func seed(_ text: String) -> UInt64 {
        text.utf8.reduce(0xcbf2_9ce4_8422_2325) { hash, byte in
            (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01B3
        }
    }
}
