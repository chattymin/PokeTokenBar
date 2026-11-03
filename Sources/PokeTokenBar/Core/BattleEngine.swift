import Foundation

struct BattleStats: Codable, Sendable, Equatable {
    let hp: Int
    let attack: Int
    let defense: Int
    let specialAttack: Int
    let specialDefense: Int
    let speed: Int

    fileprivate var isValid: Bool {
        [hp, attack, defense, specialAttack, specialDefense, speed].allSatisfy { (1...9999).contains($0) }
    }
}

enum BattleStat: String, Codable, Sendable, CaseIterable {
    case attack, defense, specialAttack = "special-attack", specialDefense = "special-defense", speed
}

struct BattleStatChange: Codable, Sendable, Equatable {
    let stat: BattleStat
    let stages: Int
}

struct BattleStatStages: Codable, Sendable, Equatable {
    var attack = 0
    var defense = 0
    var specialAttack = 0
    var specialDefense = 0
    var speed = 0

    subscript(_ stat: BattleStat) -> Int {
        get {
            switch stat {
            case .attack: return attack
            case .defense: return defense
            case .specialAttack: return specialAttack
            case .specialDefense: return specialDefense
            case .speed: return speed
            }
        }
        set {
            let value = min(6, max(-6, newValue))
            switch stat {
            case .attack: attack = value
            case .defense: defense = value
            case .specialAttack: specialAttack = value
            case .specialDefense: specialDefense = value
            case .speed: speed = value
            }
        }
    }
    fileprivate var isValid: Bool { BattleStat.allCases.allSatisfy { (-6...6).contains(self[$0]) } }
}

struct BattleMove: Codable, Sendable, Equatable, Identifiable {
    enum Category: String, Codable, Sendable { case physical, special, status }
    enum Target: String, Codable, Sendable { case user, opponent }
    enum Effect: Codable, Sendable, Equatable {
        case damage
        /// Double-Edge: recoil equals one third of the HP actually lost by the target.
        case recoil
        case stages(target: Target, changes: [BattleStatChange])
        case heal
    }
    let id: String
    let name: String
    let type: String
    let category: Category
    let power: Int
    let accuracy: Int
    let effect: Effect

    init(id: String, name: String, type: String, category: Category, power: Int, accuracy: Int,
         effect: Effect = .damage) {
        self.id = id; self.name = name; self.type = type; self.category = category
        self.power = power; self.accuracy = accuracy; self.effect = effect
    }
}

struct BattleCombatant: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let speciesID: Int
    let name: String
    let level: Int
    let types: [String]
    let stats: BattleStats
    let moves: [BattleMove]

    fileprivate var isValid: Bool {
        !id.isEmpty && (1...649).contains(speciesID) && (1...100).contains(level)
            && stats.isValid && (1...2).contains(types.count)
            && Set(types).count == types.count && types.allSatisfy { BattleTypeChart.types.contains($0) }
            && (1...4).contains(moves.count) && Set(moves.map(\.id)).count == moves.count
            && moves.allSatisfy { BattleMoveCatalog.move(named: $0.id) == $0 }
    }
}

struct BattleFighter: Codable, Sendable, Equatable {
    let combatant: BattleCombatant
    fileprivate(set) var currentHP: Int
    fileprivate(set) var stages = BattleStatStages()

    func effectiveStat(_ stat: BattleStat) -> Int {
        let base: Int
        switch stat {
        case .attack: base = combatant.stats.attack
        case .defense: base = combatant.stats.defense
        case .specialAttack: base = combatant.stats.specialAttack
        case .specialDefense: base = combatant.stats.specialDefense
        case .speed: base = combatant.stats.speed
        }
        let stage = stages[stat]
        return max(1, stage >= 0 ? base * (2 + stage) / 2 : base * 2 / (2 - stage))
    }
}

enum BattleEvent: Codable, Sendable, Equatable {
    case attack(side: Int, moveID: String, damage: Int, effectiveness: Double)
    case miss(side: Int, moveID: String)
    case statChange(side: Int, target: Int, moveID: String, stat: BattleStat, change: Int, stage: Int)
    case heal(side: Int, moveID: String, amount: Int)
    case failed(side: Int, moveID: String)
    case recoil(side: Int, moveID: String, damage: Int)
    case fainted(side: Int)
    case won(side: Int)
    case draw
}

enum BattleError: Error, Equatable {
    case invalidCombatant, sameIndividual, invalidMove, finished
}

/// Rules v3: stat stages, recoil and neutral-weather recovery, without EVs, PP, critical hits, abilities,
/// weather, status conditions, items, or other special move effects.
/// Both commands are validated before any state/randomness changes. Snapshots never reference saves.
struct BattleState: Codable, Sendable, Equatable {
    static let rulesetVersion = 3
    static let maximumTurns = 100
    private(set) var version: Int
    private(set) var fighters: [BattleFighter]
    private(set) var turn = 1
    private(set) var winner: Int?
    private(set) var isFinished = false
    private var randomState: UInt64

    init(first: BattleCombatant, second: BattleCombatant, seed: UInt64) throws {
        guard first.isValid, second.isValid else { throw BattleError.invalidCombatant }
        guard first.id != second.id else { throw BattleError.sameIndividual }
        version = Self.rulesetVersion
        fighters = [first, second].map { BattleFighter(combatant: $0, currentHP: $0.stats.hp) }
        randomState = seed
    }

    private enum CodingKeys: String, CodingKey {
        case version, fighters, turn, winner, isFinished, randomState
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(Int.self, forKey: .version)
        fighters = try values.decode([BattleFighter].self, forKey: .fighters)
        turn = try values.decode(Int.self, forKey: .turn)
        winner = try values.decodeIfPresent(Int.self, forKey: .winner)
        isFinished = try values.decode(Bool.self, forKey: .isFinished)
        randomState = try values.decode(UInt64.self, forKey: .randomState)
        guard version == Self.rulesetVersion, fighters.count == 2,
              fighters.allSatisfy({ $0.combatant.isValid && $0.stages.isValid && (0...$0.combatant.stats.hp).contains($0.currentHP) }),
              fighters[0].combatant.id != fighters[1].combatant.id,
              (1...Self.maximumTurns).contains(turn) else {
            throw DecodingError.dataCorruptedError(forKey: .fighters, in: values, debugDescription: "Invalid battle snapshot")
        }
        let outcomeValid: Bool
        if let winner {
            outcomeValid = isFinished && (0...1).contains(winner)
                && fighters[winner].currentHP > 0 && fighters[1 - winner].currentHP == 0
        } else {
            let bothAlive = fighters.allSatisfy { $0.currentHP > 0 }
            let doubleKnockout = fighters.allSatisfy { $0.currentHP == 0 }
            outcomeValid = isFinished ? (doubleKnockout || (bothAlive && turn == Self.maximumTurns)) : bothAlive
        }
        guard outcomeValid else {
            throw DecodingError.dataCorruptedError(forKey: .winner, in: values, debugDescription: "Invalid battle outcome")
        }
    }

    mutating func resolve(firstMoveID: String, secondMoveID: String) throws -> [BattleEvent] {
        guard !isFinished else { throw BattleError.finished }
        guard let first = fighters[0].combatant.moves.first(where: { $0.id == firstMoveID }),
              let second = fighters[1].combatant.moves.first(where: { $0.id == secondMoveID }) else {
            throw BattleError.invalidMove
        }
        let moves = [first, second]
        let speeds = fighters.map { $0.effectiveStat(.speed) }
        let firstSide = speeds[0] == speeds[1] ? random(upperBound: 2) : (speeds[0] > speeds[1] ? 0 : 1)
        var events: [BattleEvent] = []
        for side in [firstSide, 1 - firstSide] {
            let target = 1 - side
            let move = moves[side]
            guard random(upperBound: 100) < move.accuracy else {
                events.append(.miss(side: side, moveID: move.id))
                continue
            }
            switch move.effect {
            case let .stages(destination, changes):
                let recipient = destination == .user ? side : target
                let deltas = changes.map { change -> (BattleStat, Int, Int) in
                    let old = fighters[recipient].stages[change.stat]
                    let next = min(6, max(-6, old + change.stages))
                    return (change.stat, next - old, next)
                }
                if deltas.allSatisfy({ $0.1 == 0 }) {
                    events.append(.failed(side: side, moveID: move.id))
                } else {
                    for (stat, delta, stage) in deltas {
                        fighters[recipient].stages[stat] = stage
                        events.append(.statChange(side: side, target: recipient, moveID: move.id,
                                                  stat: stat, change: delta, stage: stage))
                    }
                }
                continue
            case .heal:
                let amount = min(fighters[side].combatant.stats.hp - fighters[side].currentHP,
                                 max(1, fighters[side].combatant.stats.hp / 2))
                if amount == 0 { events.append(.failed(side: side, moveID: move.id)) }
                else {
                    fighters[side].currentHP += amount
                    events.append(.heal(side: side, moveID: move.id, amount: amount))
                }
                continue
            case .damage, .recoil: break
            }
            let attacker = fighters[side].combatant
            let defender = fighters[target].combatant
            let effectiveness = BattleTypeChart.multiplier(attacking: move.type, defending: defender.types)
            let attack = fighters[side].effectiveStat(move.category == .physical ? .attack : .specialAttack)
            let defense = fighters[target].effectiveStat(move.category == .physical ? .defense : .specialDefense)
            let base = ((2 * attacker.level / 5 + 2) * move.power * attack / defense) / 50 + 2
            let stab = attacker.types.contains(move.type) ? 1.5 : 1.0
            let variation = Double(85 + random(upperBound: 16)) / 100
            let calculated = effectiveness == 0 ? 0 : max(1, Int((Double(base) * stab * effectiveness * variation).rounded(.down)))
            let damage = min(fighters[target].currentHP, calculated)
            fighters[target].currentHP -= damage
            events.append(.attack(side: side, moveID: move.id, damage: damage, effectiveness: effectiveness))
            if move.effect == .recoil, damage > 0 {
                let recoil = min(fighters[side].currentHP, max(1, damage / 3))
                fighters[side].currentHP -= recoil
                events.append(.recoil(side: side, moveID: move.id, damage: recoil))
            }
            if fighters.contains(where: { $0.currentHP == 0 }) {
                isFinished = true
                for fainted in [target, side] where fighters[fainted].currentHP == 0 {
                    events.append(.fainted(side: fainted))
                }
                if fighters.allSatisfy({ $0.currentHP == 0 }) {
                    events.append(.draw)
                } else {
                    winner = fighters[side].currentHP > 0 ? side : target
                    events.append(.won(side: winner!))
                }
                return events
            }
        }
        if turn == Self.maximumTurns {
            isFinished = true
            events.append(.draw)
        } else {
            turn += 1
        }
        return events
    }

    /// SplitMix64 keeps replays stable across processes and Swift versions, including seed zero.
    private mutating func random(upperBound: Int) -> Int {
        randomState &+= 0x9E3779B97F4A7C15
        var value = randomState
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return Int((value ^ (value >> 31)) % UInt64(upperBound))
    }
}

/// Explicit whitelist of attacks and supported stat/recovery moves for the limited app ruleset.
/// Power/accuracy/category/type checked against https://pokeapi.co/api/v2/move/{name}.
/// This catalog is not a complete historical generation or full battle simulator.
enum BattleMoveCatalog {
    /// App-specific safety valve for species whose legal learnset has no implemented attacks.
    /// This is explicitly a practice action, never a saved or official Pokémon move.
    static let practiceStrike = move("practice-strike", "normal", .physical, 40, 100)

    static let all: [BattleMove] = [
        move("tackle", "normal", .physical, 40, 100),
        BattleMove(id: "double-edge", name: "Double-Edge", type: "normal", category: .physical,
                   power: 120, accuracy: 100, effect: .recoil),
        move("scratch", "normal", .physical, 40, 100),
        move("pound", "normal", .physical, 40, 100),
        move("cut", "normal", .physical, 50, 95),
        move("vine-whip", "grass", .physical, 45, 100),
        move("water-gun", "water", .special, 40, 100),
        move("peck", "flying", .physical, 35, 100),
        move("gust", "flying", .special, 40, 100),
        move("wing-attack", "flying", .physical, 60, 100),
        move("horn-attack", "normal", .physical, 65, 100),
        move("strength", "normal", .physical, 80, 100),
        move("slam", "normal", .physical, 80, 75),
        move("mega-punch", "normal", .physical, 80, 85),
        move("mega-kick", "normal", .physical, 120, 75),
        move("hyper-voice", "normal", .special, 90, 100),
        move("power-gem", "rock", .special, 80, 100),
        move("drill-peck", "flying", .physical, 80, 100),
        move("aqua-tail", "water", .physical, 90, 90),
        move("dragon-claw", "dragon", .physical, 80, 100),
        move("seed-bomb", "grass", .physical, 80, 100),
        move("rock-throw", "rock", .physical, 50, 90),
        move("vice-grip", "normal", .physical, 55, 100),
        move("hydro-pump", "water", .special, 110, 80),
        move("egg-bomb", "normal", .physical, 100, 75),
        move("megahorn", "bug", .physical, 120, 85),
        move("x-scissor", "bug", .physical, 80, 100),
        move("dragon-pulse", "dragon", .special, 85, 100),
        move("power-whip", "grass", .physical, 120, 85),
        // PokéAPI reports null accuracy for these never-miss attacks. With no accuracy/evasion
        // modifiers or semi-invulnerable states in rules v1, 100 represents that guarantee.
        move("swift", "normal", .special, 60, 100),
        move("feint-attack", "dark", .physical, 60, 100),
        move("shadow-punch", "ghost", .physical, 60, 100),
        move("aerial-ace", "flying", .physical, 60, 100),
        move("magical-leaf", "grass", .special, 60, 100),
        move("shock-wave", "electric", .special, 60, 100),
        move("aura-sphere", "fighting", .special, 80, 100),
        move("magnet-bomb", "steel", .physical, 60, 100),
        stages("swords-dance", "normal", .user, [.init(stat: .attack, stages: 2)]),
        stages("growl", "normal", .opponent, [.init(stat: .attack, stages: -1)]),
        stages("tail-whip", "normal", .opponent, [.init(stat: .defense, stages: -1)]),
        stages("leer", "normal", .opponent, [.init(stat: .defense, stages: -1)]),
        stages("harden", "normal", .user, [.init(stat: .defense, stages: 1)]),
        stages("defense-curl", "normal", .user, [.init(stat: .defense, stages: 1)]),
        stages("withdraw", "water", .user, [.init(stat: .defense, stages: 1)]),
        stages("iron-defense", "steel", .user, [.init(stat: .defense, stages: 2)]),
        stages("agility", "psychic", .user, [.init(stat: .speed, stages: 2)]),
        stages("scary-face", "normal", .opponent, [.init(stat: .speed, stages: -2)]),
        stages("calm-mind", "psychic", .user, [.init(stat: .specialAttack, stages: 1), .init(stat: .specialDefense, stages: 1)]),
        stages("nasty-plot", "dark", .user, [.init(stat: .specialAttack, stages: 2)]),
        stages("amnesia", "psychic", .user, [.init(stat: .specialDefense, stages: 2)]),
        stages("metal-sound", "steel", .opponent, [.init(stat: .specialDefense, stages: -2)], accuracy: 85),
        stages("fake-tears", "dark", .opponent, [.init(stat: .specialDefense, stages: -2)]),
        stages("screech", "normal", .opponent, [.init(stat: .defense, stages: -2)], accuracy: 85),
        stages("charm", "fairy", .opponent, [.init(stat: .attack, stages: -2)]),
        stages("bulk-up", "fighting", .user, [.init(stat: .attack, stages: 1), .init(stat: .defense, stages: 1)]),
        stages("work-up", "normal", .user, [.init(stat: .attack, stages: 1), .init(stat: .specialAttack, stages: 1)]),
        heal("recover", "normal"), heal("soft-boiled", "normal"), heal("slack-off", "normal"),
        heal("milk-drink", "normal"), heal("synthesis", "grass"), heal("moonlight", "fairy"),
        heal("morning-sun", "normal"),
    ]

    static func move(named name: String) -> BattleMove? {
        name == practiceStrike.id ? practiceStrike : all.first { $0.id == name }
    }

    static func moves(for knownMoves: [PokemonKnownMove]) -> [BattleMove] {
        var seen: Set<String> = []
        let supported = knownMoves.compactMap { known -> BattleMove? in
            guard seen.insert(known.name).inserted else { return nil }
            // A saved move list can never grant the app-only practice action.
            return all.first { $0.id == known.name }
        }
        var selected = Array(supported.suffix(4))
        if !selected.contains(where: { $0.effect == .damage }),
           let attack = supported.last(where: { $0.effect == .damage }) {
            if selected.count == 4 { selected.removeFirst() }
            selected.insert(attack, at: 0)
        }
        return selected
    }

    private static func stages(_ id: String, _ type: String, _ target: BattleMove.Target,
                               _ changes: [BattleStatChange], accuracy: Int = 100) -> BattleMove {
        BattleMove(id: id, name: displayName(id), type: type, category: .status, power: 0,
                   accuracy: accuracy, effect: .stages(target: target, changes: changes))
    }

    private static func heal(_ id: String, _ type: String) -> BattleMove {
        BattleMove(id: id, name: displayName(id), type: type, category: .status, power: 0,
                   accuracy: 100, effect: .heal)
    }

    private static func displayName(_ id: String) -> String {
        id.split(separator: "-").map { $0.capitalized }.joined(separator: " ")
    }

    private static func move(_ id: String, _ type: String, _ category: BattleMove.Category,
                             _ power: Int, _ accuracy: Int) -> BattleMove {
        BattleMove(id: id, name: id.split(separator: "-").map { $0.capitalized }.joined(separator: " "),
                   type: type, category: category, power: power, accuracy: accuracy)
    }
}

/// Current type chart, including Fairy. Default-form types match PokemonDetails.
enum BattleTypeChart {
    static let types: Set<String> = ["normal", "fire", "water", "electric", "grass", "ice", "fighting",
        "poison", "ground", "flying", "psychic", "bug", "rock", "ghost", "dragon", "dark", "steel", "fairy"]

    static func multiplier(attacking: String, defending: [String]) -> Double {
        defending.reduce(1) { result, type in
            if immune[attacking, default: []].contains(type) { return 0 }
            if strong[attacking, default: []].contains(type) { return result * 2 }
            if weak[attacking, default: []].contains(type) { return result * 0.5 }
            return result
        }
    }

    private static let immune: [String: Set<String>] = [
        "normal": ["ghost"], "electric": ["ground"], "fighting": ["ghost"],
        "poison": ["steel"], "ground": ["flying"], "psychic": ["dark"],
        "ghost": ["normal"], "dragon": ["fairy"]]
    private static let strong: [String: Set<String>] = [
        "fire": ["grass", "ice", "bug", "steel"], "water": ["fire", "ground", "rock"],
        "electric": ["water", "flying"], "grass": ["water", "ground", "rock"],
        "ice": ["grass", "ground", "flying", "dragon"], "fighting": ["normal", "ice", "rock", "dark", "steel"],
        "poison": ["grass", "fairy"], "ground": ["fire", "electric", "poison", "rock", "steel"],
        "flying": ["grass", "fighting", "bug"], "psychic": ["fighting", "poison"],
        "bug": ["grass", "psychic", "dark"], "rock": ["fire", "ice", "flying", "bug"],
        "ghost": ["psychic", "ghost"], "dragon": ["dragon"], "dark": ["psychic", "ghost"],
        "steel": ["ice", "rock", "fairy"], "fairy": ["fighting", "dragon", "dark"]]
    private static let weak: [String: Set<String>] = [
        "normal": ["rock", "steel"], "fire": ["fire", "water", "rock", "dragon"],
        "water": ["water", "grass", "dragon"], "electric": ["electric", "grass", "dragon"],
        "grass": ["fire", "grass", "poison", "flying", "bug", "dragon", "steel"],
        "ice": ["fire", "water", "ice", "steel"], "fighting": ["poison", "flying", "psychic", "bug", "fairy"],
        "poison": ["poison", "ground", "rock", "ghost"], "ground": ["grass", "bug"],
        "flying": ["electric", "rock", "steel"], "psychic": ["psychic", "steel"],
        "bug": ["fire", "fighting", "poison", "flying", "ghost", "steel", "fairy"],
        "rock": ["fighting", "ground", "steel"], "ghost": ["dark"], "dragon": ["steel"],
        "dark": ["fighting", "dark", "fairy"], "steel": ["fire", "water", "electric", "steel"],
        "fairy": ["fire", "poison", "steel"]]
}
