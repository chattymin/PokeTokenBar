import Foundation

enum BattleSide: Int, Codable, Sendable, CaseIterable {
    case a, b
    var opponent: BattleSide { self == .a ? .b : .a }
}

/// SplitMix64. Draws use plain modulo instead of `Int.random(in:using:)`, whose algorithm is not
/// guaranteed stable across Swift versions — both peers must draw identical numbers.
struct BattleRNG: Codable, Sendable, Equatable {
    private(set) var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
    mutating func below(_ bound: Int) -> Int { Int(next() % UInt64(max(1, bound))) }
    mutating func percent(_ chance: Int) -> Bool { below(100) < chance }
}

struct BattleStages: Codable, Sendable, Equatable {
    static let range = -6...6
    var attack = 0, defense = 0, specialAttack = 0, specialDefense = 0, speed = 0, accuracy = 0, evasion = 0

    /// nil for a stat name this engine does not track, e.g. one a future PokéAPI release adds.
    func value(_ stat: String) -> Int? {
        switch stat {
        case "attack": return attack
        case "defense": return defense
        case "special-attack": return specialAttack
        case "special-defense": return specialDefense
        case "speed": return speed
        case "accuracy": return accuracy
        case "evasion": return evasion
        default: return nil
        }
    }

    mutating func set(_ stat: String, _ newValue: Int) {
        let value = min(Self.range.upperBound, max(Self.range.lowerBound, newValue))
        switch stat {
        case "attack": attack = value
        case "defense": defense = value
        case "special-attack": specialAttack = value
        case "special-defense": specialDefense = value
        case "speed": speed = value
        case "accuracy": accuracy = value
        case "evasion": evasion = value
        default: break
        }
    }
}

struct BattleCombatant: Codable, Sendable, Equatable {
    let pokemon: BattlePokemon
    var hp: Int
    var pp: [Int]
    var stages = BattleStages()
    var isFainted: Bool { hp == 0 }

    init(_ pokemon: BattlePokemon) {
        self.pokemon = pokemon
        hp = pokemon.stats.hp
        pp = pokemon.moves.map(\.pp)
    }
}

struct BattleSideState: Codable, Sendable, Equatable {
    var team: [BattleCombatant]
    var active = 0
    var current: BattleCombatant { team[active] }
    var hasRemaining: Bool { team.contains { !$0.isFainted } }
}

enum BattlePhase: Codable, Sendable, Equatable {
    case choosing
    /// Sides whose active Pokémon fainted and that still have one left to send out.
    case replacing([BattleSide])
    /// nil winner = both sides ran out in the same turn.
    case finished(winner: BattleSide?)
}

enum BattleAction: Codable, Sendable, Hashable {
    case move(Int)
    case struggle
    case switchTo(Int)
    case forfeit
}

enum BattleEngineError: Error, Equatable, Sendable {
    case wrongPhase
    case illegalAction(BattleSide)
}

/// Everything the UI needs to play a turn back, carrying resulting values so views never recompute rules.
enum BattleEvent: Equatable, Sendable {
    case sentOut(BattleSide, index: Int)
    case usedMove(BattleSide, move: String)
    case noMovesLeft(BattleSide)
    case missed(BattleSide)
    case noEffect(target: BattleSide)
    /// `effectiveness` is in quarters: 4 = neutral, 8 = super effective, 2 = not very effective.
    case damaged(BattleSide, amount: Int, hp: Int, effectiveness: Int, critical: Bool)
    case healed(BattleSide, amount: Int, hp: Int)
    case recoil(BattleSide, amount: Int, hp: Int)
    case statChanged(BattleSide, stat: String, change: Int)
    case statLimit(BattleSide, stat: String, rising: Bool)
    case failed(BattleSide)
    case fainted(BattleSide, index: Int)
    case forfeited(BattleSide)
    case ended(winner: BattleSide?)
}

extension BattleMove {
    static let struggle = BattleMove(name: "struggle", type: BattleTypeChart.typeless, power: 50, accuracy: nil,
                                     pp: 1, priority: 0, damageClass: .physical, target: "random-opponent",
                                     category: "damage", healing: -25)

    private static let selfTargets: Set<String> = ["user", "user-and-allies", "user-or-ally", "all-allies", "users-field"]
    var targetsUser: Bool { Self.selfTargets.contains(target) }

    /// Moves the engine can resolve today. Everything else is shown but cannot be picked.
    var isSupportedInBattle: Bool {
        if isDamaging { return true }
        if category == "net-good-stats" { return !statChanges.isEmpty }
        if category == "heal" { return healing > 0 }
        return false
    }
}

enum BattleTypeChart {
    static let typeless = "typeless"
    /// Attacking type → defending types that are not neutral, in halves (0 immune, 1 resisted, 4 weak).
    private static let chart: [String: [String: Int]] = [
        "normal": ["rock": 1, "steel": 1, "ghost": 0],
        "fire": ["grass": 4, "ice": 4, "bug": 4, "steel": 4, "fire": 1, "water": 1, "rock": 1, "dragon": 1],
        "water": ["fire": 4, "ground": 4, "rock": 4, "water": 1, "grass": 1, "dragon": 1],
        "electric": ["water": 4, "flying": 4, "electric": 1, "grass": 1, "dragon": 1, "ground": 0],
        "grass": ["water": 4, "ground": 4, "rock": 4, "fire": 1, "grass": 1, "poison": 1, "flying": 1,
                  "bug": 1, "dragon": 1, "steel": 1],
        "ice": ["grass": 4, "ground": 4, "flying": 4, "dragon": 4, "fire": 1, "water": 1, "ice": 1, "steel": 1],
        "fighting": ["normal": 4, "ice": 4, "rock": 4, "dark": 4, "steel": 4, "poison": 1, "flying": 1,
                     "psychic": 1, "bug": 1, "fairy": 1, "ghost": 0],
        "poison": ["grass": 4, "fairy": 4, "poison": 1, "ground": 1, "rock": 1, "ghost": 1, "steel": 0],
        "ground": ["fire": 4, "electric": 4, "poison": 4, "rock": 4, "steel": 4, "grass": 1, "bug": 1, "flying": 0],
        "flying": ["grass": 4, "fighting": 4, "bug": 4, "electric": 1, "rock": 1, "steel": 1],
        "psychic": ["fighting": 4, "poison": 4, "psychic": 1, "steel": 1, "dark": 0],
        "bug": ["grass": 4, "psychic": 4, "dark": 4, "fire": 1, "fighting": 1, "poison": 1, "flying": 1,
                "ghost": 1, "steel": 1, "fairy": 1],
        "rock": ["fire": 4, "ice": 4, "flying": 4, "bug": 4, "fighting": 1, "ground": 1, "steel": 1],
        "ghost": ["psychic": 4, "ghost": 4, "dark": 1, "normal": 0],
        "dragon": ["dragon": 4, "steel": 1, "fairy": 0],
        "dark": ["psychic": 4, "ghost": 4, "fighting": 1, "dark": 1, "fairy": 1],
        "steel": ["ice": 4, "rock": 4, "fairy": 4, "fire": 1, "water": 1, "electric": 1, "steel": 1],
        "fairy": ["fighting": 4, "dragon": 4, "dark": 4, "fire": 1, "poison": 1, "steel": 1],
    ]

    /// In quarters, so a dual-type product stays an integer: 0, 1, 2, 4, 8 or 16.
    static func effectiveness(of moveType: String, against types: [String]) -> Int {
        var quarters = 4
        for type in types.prefix(2) {
            quarters = quarters * (chart[moveType]?[type] ?? 2) / 2
        }
        return quarters
    }
}

enum BattleFormula {
    /// Gen V damage with integer truncation after every step, in the main-series order.
    static func damage(level: Int, power: Int, attack: Int, defense: Int, critical: Bool,
                       randomPercent: Int, stab: Bool, effectiveness: Int) -> Int {
        var damage = ((2 * level / 5 + 2) * power * attack / max(1, defense)) / 50 + 2
        if critical { damage *= 2 }
        damage = damage * randomPercent / 100
        if stab { damage = damage * 3 / 2 }
        damage = damage * effectiveness / 4
        return effectiveness == 0 ? 0 : max(1, damage)
    }

    static func stagedStat(_ value: Int, stage: Int) -> Int {
        stage >= 0 ? value * (2 + stage) / 2 : value * 2 / (2 - stage)
    }

    /// Hit chance in percent after accuracy and evasion stages.
    static func hitChance(accuracy: Int, stage: Int) -> Int {
        let stage = min(6, max(-6, stage))
        return stage >= 0 ? accuracy * (3 + stage) / 3 : accuracy * 3 / (3 - stage)
    }

    /// Gen V critical-hit odds per stage: 1/16, 1/8, 1/4, 1/3, 1/2.
    static func criticalDenominator(stage: Int) -> Int {
        [16, 8, 4, 3, 2][min(4, max(0, stage))]
    }
}

/// Deterministic singles battle. Same teams + seed + actions always give the same state and events,
/// which is what lets two Macs each run their own copy in lockstep.
struct BattleState: Codable, Sendable, Equatable {
    private(set) var sides: [BattleSideState]
    private(set) var phase: BattlePhase = .choosing
    private(set) var turn = 1
    private var rng: BattleRNG

    init(teamA: BattleTeam, teamB: BattleTeam, seed: UInt64) {
        sides = [BattleSideState(team: teamA.members.map(BattleCombatant.init)),
                 BattleSideState(team: teamB.members.map(BattleCombatant.init))]
        rng = BattleRNG(seed: seed)
    }

    subscript(side: BattleSide) -> BattleSideState { sides[side.rawValue] }

    var openingEvents: [BattleEvent] { [.sentOut(.a, index: 0), .sentOut(.b, index: 0)] }

    var needsReplacement: [BattleSide] {
        if case .replacing(let pending) = phase { return pending }
        return []
    }

    // MARK: Legality

    func usableMoves(for side: BattleSide) -> [Int] {
        let current = self[side].current
        return current.pokemon.moves.indices.filter {
            current.pokemon.moves[$0].isSupportedInBattle && current.pp[$0] > 0
        }
    }

    func switchTargets(for side: BattleSide) -> [Int] {
        let state = self[side]
        return state.team.indices.filter { $0 != state.active && !state.team[$0].isFainted }
    }

    func legalActions(for side: BattleSide) -> [BattleAction] {
        guard phase == .choosing else { return [] }
        let moves = usableMoves(for: side)
        return (moves.isEmpty ? [.struggle] : moves.map(BattleAction.move))
            + switchTargets(for: side).map(BattleAction.switchTo) + [.forfeit]
    }

    // MARK: Turn resolution

    mutating func resolveTurn(_ actionA: BattleAction, _ actionB: BattleAction) throws(BattleEngineError) -> [BattleEvent] {
        guard phase == .choosing else { throw .wrongPhase }
        guard legalActions(for: .a).contains(actionA) else { throw .illegalAction(.a) }
        guard legalActions(for: .b).contains(actionB) else { throw .illegalAction(.b) }

        let actions: [BattleSide: BattleAction] = [.a: actionA, .b: actionB]
        let forfeits = BattleSide.allCases.filter { actions[$0] == .forfeit }
        if !forfeits.isEmpty {
            let winner: BattleSide? = forfeits.count == 2 ? nil : forfeits[0].opponent
            phase = .finished(winner: winner)
            return forfeits.map(BattleEvent.forfeited) + [.ended(winner: winner)]
        }

        var events: [BattleEvent] = []
        let switchers = ordered(BattleSide.allCases.filter {
            if case .switchTo = actions[$0] { return true }
            return false
        }, priorities: [:])
        for side in switchers {
            if case .switchTo(let index) = actions[side] { events += switchIn(side, to: index) }
        }

        var priorities: [BattleSide: Int] = [:]
        for side in BattleSide.allCases {
            if case .move(let index) = actions[side] { priorities[side] = self[side].current.pokemon.moves[index].priority }
        }
        let attackers = ordered(BattleSide.allCases.filter { !switchers.contains($0) }, priorities: priorities)
        for side in attackers where !self[side].current.isFainted && !self[side.opponent].current.isFainted {
            switch actions[side] {
            case .move(let index): events += use(side, moveIndex: index)
            case .struggle: events += [.noMovesLeft(side)] + use(side, moveIndex: nil)
            default: break
            }
        }

        events += concludeTurn()
        turn += 1
        return events
    }

    /// Leaving outside the choice phase, e.g. while picking a replacement or when a peer disconnects.
    mutating func forfeit(_ side: BattleSide) -> [BattleEvent] {
        if case .finished = phase { return [] }
        phase = .finished(winner: side.opponent)
        return [.forfeited(side), .ended(winner: side.opponent)]
    }

    mutating func replace(_ side: BattleSide, with index: Int) throws(BattleEngineError) -> [BattleEvent] {
        guard case .replacing(var pending) = phase, pending.contains(side) else { throw .wrongPhase }
        guard switchTargets(for: side).contains(index) else { throw .illegalAction(side) }
        let events = switchIn(side, to: index)
        pending.removeAll { $0 == side }
        phase = pending.isEmpty ? .choosing : .replacing(pending)
        return events
    }

    // MARK: Internals

    private mutating func update(_ side: BattleSide, _ change: (inout BattleCombatant) -> Void) {
        change(&sides[side.rawValue].team[sides[side.rawValue].active])
    }

    /// Higher priority first, then higher staged speed; exact ties draw from the RNG.
    private mutating func ordered(_ candidates: [BattleSide], priorities: [BattleSide: Int]) -> [BattleSide] {
        guard candidates.count == 2 else { return candidates }
        func key(_ side: BattleSide) -> (Int, Int) {
            let current = self[side].current
            return (priorities[side] ?? 0, BattleFormula.stagedStat(current.pokemon.stats.speed, stage: current.stages.speed))
        }
        let a = key(.a), b = key(.b)
        if a == b { return rng.below(2) == 0 ? [.a, .b] : [.b, .a] }
        return a > b ? [.a, .b] : [.b, .a]
    }

    private mutating func switchIn(_ side: BattleSide, to index: Int) -> [BattleEvent] {
        update(side) { $0.stages = BattleStages() }
        sides[side.rawValue].active = index
        return [.sentOut(side, index: index)]
    }

    private mutating func use(_ side: BattleSide, moveIndex: Int?) -> [BattleEvent] {
        let target = side.opponent
        let move: BattleMove
        if let moveIndex {
            move = self[side].current.pokemon.moves[moveIndex]
            update(side) { $0.pp[moveIndex] -= 1 }
        } else {
            move = .struggle
        }
        var events: [BattleEvent] = [.usedMove(side, move: move.name)]

        if !move.targetsUser, let accuracy = move.accuracy {
            let stage = self[side].current.stages.accuracy - self[target].current.stages.evasion
            if !rng.percent(BattleFormula.hitChance(accuracy: accuracy, stage: stage)) {
                return events + [.missed(side)]
            }
        }

        if move.isDamaging {
            events += dealDamage(side, move: move)
        } else if move.category == "heal" {
            events += heal(side, percent: move.healing)
        } else {
            events += applyStatChanges(move.statChanges, to: move.targetsUser ? side : target)
        }
        return events
    }

    private mutating func dealDamage(_ side: BattleSide, move: BattleMove) -> [BattleEvent] {
        let target = side.opponent
        let attacker = self[side].current
        let defender = self[target].current
        let effectiveness = BattleTypeChart.effectiveness(of: move.type, against: defender.pokemon.types)
        guard effectiveness > 0 else { return [.noEffect(target: target)] }

        let critical = rng.below(BattleFormula.criticalDenominator(stage: move.critRate)) == 0
        let physical = move.damageClass == .physical
        var attackStage = physical ? attacker.stages.attack : attacker.stages.specialAttack
        var defenseStage = physical ? defender.stages.defense : defender.stages.specialDefense
        // A critical hit ignores the attacker's drops and the defender's boosts.
        if critical { attackStage = max(0, attackStage); defenseStage = min(0, defenseStage) }
        let attack = BattleFormula.stagedStat(physical ? attacker.pokemon.stats.attack : attacker.pokemon.stats.specialAttack,
                                              stage: attackStage)
        let defense = BattleFormula.stagedStat(physical ? defender.pokemon.stats.defense : defender.pokemon.stats.specialDefense,
                                               stage: defenseStage)
        let amount = min(defender.hp, BattleFormula.damage(
            level: attacker.pokemon.level, power: move.power ?? 0, attack: attack, defense: defense,
            critical: critical, randomPercent: 85 + rng.below(16),
            stab: attacker.pokemon.types.contains(move.type), effectiveness: effectiveness))
        update(target) { $0.hp -= amount }
        var events: [BattleEvent] = [.damaged(target, amount: amount, hp: self[target].current.hp,
                                              effectiveness: effectiveness, critical: critical)]

        if move.drain > 0 {
            events += heal(side, amount: max(1, amount * move.drain / 100))
        } else if move.drain < 0 {
            events += takeRecoil(side, amount: max(1, amount * -move.drain / 100))
        }
        if move.healing < 0 {
            events += takeRecoil(side, amount: max(1, attacker.pokemon.stats.hp * -move.healing / 100))
        }

        if !move.statChanges.isEmpty, move.statChance > 0, !self[target].current.isFainted || move.category == "damage-raise",
           rng.percent(move.statChance) {
            events += applyStatChanges(move.statChanges, to: move.category == "damage-raise" ? side : target)
        }
        if self[target].current.isFainted { events.append(.fainted(target, index: self[target].active)) }
        if self[side].current.isFainted { events.append(.fainted(side, index: self[side].active)) }
        return events
    }

    private mutating func heal(_ side: BattleSide, percent: Int) -> [BattleEvent] {
        heal(side, amount: max(1, self[side].current.pokemon.stats.hp * percent / 100), failIfFull: true)
    }

    private mutating func heal(_ side: BattleSide, amount: Int, failIfFull: Bool = false) -> [BattleEvent] {
        let current = self[side].current
        let healed = min(amount, current.pokemon.stats.hp - current.hp)
        guard healed > 0, !current.isFainted else { return failIfFull ? [.failed(side)] : [] }
        update(side) { $0.hp += healed }
        return [.healed(side, amount: healed, hp: self[side].current.hp)]
    }

    private mutating func takeRecoil(_ side: BattleSide, amount: Int) -> [BattleEvent] {
        let taken = min(amount, self[side].current.hp)
        update(side) { $0.hp -= taken }
        return [.recoil(side, amount: taken, hp: self[side].current.hp)]
    }

    private mutating func applyStatChanges(_ changes: [BattleStatChange], to side: BattleSide) -> [BattleEvent] {
        var events: [BattleEvent] = []
        for change in changes {
            guard let before = self[side].current.stages.value(change.stat) else { continue }
            update(side) { $0.stages.set(change.stat, before + change.change) }
            let applied = (self[side].current.stages.value(change.stat) ?? before) - before
            events.append(applied == 0
                ? .statLimit(side, stat: change.stat, rising: change.change > 0)
                : .statChanged(side, stat: change.stat, change: applied))
        }
        return events.isEmpty ? [.failed(side)] : events
    }

    private mutating func concludeTurn() -> [BattleEvent] {
        let remaining = BattleSide.allCases.filter { self[$0].hasRemaining }
        if remaining.count < 2 {
            let winner = remaining.first
            phase = .finished(winner: winner)
            return [.ended(winner: winner)]
        }
        let pending = BattleSide.allCases.filter { self[$0].current.isFainted }
        phase = pending.isEmpty ? .choosing : .replacing(pending)
        return []
    }
}
