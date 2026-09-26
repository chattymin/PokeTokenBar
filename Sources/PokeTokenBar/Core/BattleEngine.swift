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


/// Major status: at most one at a time, kept when switching out.
enum BattleStatus: String, Codable, Sendable, CaseIterable {
    case burn, paralysis, poison, badPoison, sleep, freeze

    /// Types that can never receive this status.
    var immuneTypes: Set<String> {
        switch self {
        case .burn: return ["fire"]
        case .paralysis: return ["electric"]
        case .poison, .badPoison: return ["poison", "steel"]
        case .freeze: return ["ice"]
        case .sleep: return []
        }
    }
}

enum BattleLock: String, Codable, Sendable { case rampage, rollout, uproar, bide }

/// Effects that end when the Pokémon leaves the field.
struct BattleVolatiles: Codable, Sendable, Equatable {
    var confusionTurns = 0
    var protectStreak = 0
    var focusEnergy = false
    var leechSeeded = false
    var cursed = false
    var nightmare = false
    var yawnTurns = 0
    var tauntTurns = 0
    var encoreTurns = 0
    var encoreMove: Int?
    var disabledMove: Int?
    var disableTurns = 0
    var tormented = false
    var imprisoning = false
    var healBlockTurns = 0
    var magnetRiseTurns = 0
    var telekinesisTurns = 0
    var perishCount: Int?
    var infatuated = false
    var trapped = false
    var ingrained = false
    var aquaRing = false
    var stockpile = 0
    var lockOnTurns = 0
    var destinyBond = false
    var grudge = false
    var identified = false
    var miracleEye = false
    var grounded = false
    var insomnia = false
    var charged = false
    var defenseCurl = false
    var magicCoat = false
    /// Two-turn move waiting for its second turn, and where the user hides meanwhile.
    var chargingMove: Int?
    var hideout: BattleHideout?
    var mustRecharge = false
    var rechargeMove: Int?
    var lockedMove: Int?
    var lock: BattleLock?
    var lockTurns = 0
    var lockHits = 0
    var bideDamage = 0
    var furyCutter = 0
    var lastMove: Int?
    /// The first turn this Pokémon may act on after coming in; Fake Out works only then.
    var firstTurn = 1
}

/// Cleared at the end of every turn.
struct BattleTurnFlags: Codable, Sendable, Equatable {
    var isProtected = false
    var isEnduring = false
    var flinched = false
    var damageTaken = 0
    var physicalFromOpponent = 0
    var specialFromOpponent = 0
    var quickGuard = false
    var wideGuard = false
}

struct BattleCombatant: Codable, Sendable, Equatable {
    let pokemon: BattlePokemon
    var hp: Int
    var pp: [Int]
    /// Transform and Mimic give copied moves 5 PP, so the maximum is tracked per slot.
    var maxPP: [Int]
    var moves: [BattleMove]
    var types: [String]
    var stats: BattleStats
    var weight: Int
    /// Species shown while transformed.
    var appearance: Int?
    var stages = BattleStages()
    var status: BattleStatus?
    var sleepTurns = 0
    var toxicCounter = 0
    var volatiles = BattleVolatiles()
    var turn = BattleTurnFlags()
    /// Moves and PP from before Transform/Mimic, restored when leaving the field.
    var savedMoves: [BattleMove]?
    var savedPP: [Int]?
    var faintReported = false
    var isFainted: Bool { hp == 0 }
    var maxHP: Int { pokemon.stats.hp }

    init(_ pokemon: BattlePokemon) {
        self.pokemon = pokemon
        hp = pokemon.stats.hp
        pp = pokemon.moves.map(\.pp)
        maxPP = pokemon.moves.map(\.pp)
        moves = pokemon.moves
        types = pokemon.types
        stats = pokemon.stats
        weight = pokemon.weight
    }

    var isGrounded: Bool { !types.contains("flying") && volatiles.magnetRiseTurns == 0 && volatiles.telekinesisTurns == 0 }

    /// What leaving the field resets; major status and its sleep counter stay.
    mutating func leaveField() {
        stages = BattleStages()
        toxicCounter = 0
        if let savedMoves {
            moves = savedMoves
            maxPP = savedMoves.map(\.pp)
        }
        if let savedPP {
            // Transform replaced every move; keep PP spent on the original moves only.
            pp = savedPP
        }
        savedMoves = nil
        savedPP = nil
        types = pokemon.types
        stats = pokemon.stats
        weight = pokemon.weight
        appearance = nil
        volatiles = BattleVolatiles()
        turn = BattleTurnFlags()
    }
}

struct BattleSideConditions: Codable, Sendable, Equatable {
    /// Keyed by raw value, never by the enum: JSON encodes non-String-keyed dictionaries as arrays in hash
    /// order, which differs per process and would give two peers different digests for the same state.
    var screens: [String: Int] = [:]
    var spikes = 0
    var toxicSpikes = 0
    var stealthRock = false
    var healingWish: Bool?
    var faintedThisTurn = false
    var faintedLastTurn = false
    var wishTurns = 0
    var wishHP = 0
    var futureTurns = 0
    var futureDamage = 0
    var futureType = BattleTypeChart.typeless

    func has(_ screen: BattleBarrier) -> Bool { (screens[screen.rawValue] ?? 0) > 0 }
}

struct BattleField: Codable, Sendable, Equatable {
    var weather: BattleWeather?
    var weatherTurns = 0
    var sports: [String: Int] = [:]
    var trickRoomTurns = 0
    var gravityTurns = 0
    var uproarTurns = 0
    var echoedVoice = 0
    var echoedVoiceTurn = 0
}

struct BattleSideState: Codable, Sendable, Equatable {
    var team: [BattleCombatant]
    var active = 0
    var conditions = BattleSideConditions()
    var current: BattleCombatant { team[active] }
    var hasRemaining: Bool { team.contains { !$0.isFainted } }
}

enum BattlePhase: Codable, Sendable, Equatable {
    case choosing
    /// Sides that must send in a Pokémon: after a knockout, or mid-turn after U-turn or Baton Pass.
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

enum BattleCantMoveReason: Equatable, Sendable {
    case asleep, frozen, paralyzed, flinched, infatuated, recharging, lostFocus
}

enum BattleEffectDamage: String, Codable, Sendable {
    case leechSeed, curse, nightmare, sandstorm, hail, spikes, stealthRock, crash, bellyDrum, curseCost
}

enum BattleEffectHeal: String, Codable, Sendable {
    case aquaRing, ingrain, wish, leechSeed, healingWish, painSplit
}

/// Everything the UI needs to play a turn back, carrying resulting values so views never recompute rules.
enum BattleEvent: Equatable, Sendable {
    case sentOut(BattleSide, index: Int)
    case withdrew(BattleSide)
    case usedMove(BattleSide, move: String)
    case noMovesLeft(BattleSide)
    case missed(BattleSide)
    case noEffect(target: BattleSide)
    /// `effectiveness` is in quarters: 4 = neutral, 8 = super effective, 2 = not very effective.
    case damaged(BattleSide, amount: Int, hp: Int, effectiveness: Int, critical: Bool)
    case hitCount(Int)
    case oneHitKO
    case healed(BattleSide, amount: Int, hp: Int)
    case recoil(BattleSide, amount: Int, hp: Int)
    case effectDamage(BattleSide, BattleEffectDamage, amount: Int, hp: Int)
    case effectHeal(BattleSide, BattleEffectHeal, amount: Int, hp: Int)
    case statChanged(BattleSide, stat: String, change: Int)
    case statLimit(BattleSide, stat: String, rising: Bool)
    case stagesReset(BattleSide?)
    case failed(BattleSide)
    case nothingHappened
    case statusApplied(BattleSide, BattleStatus)
    case statusCured(BattleSide)
    case teamCured(BattleSide)
    case confused(BattleSide)
    case cantMove(BattleSide, BattleCantMoveReason)
    case wokeUp(BattleSide)
    case thawed(BattleSide)
    case isConfused(BattleSide)
    case snappedOut(BattleSide)
    case hurtByConfusion(BattleSide, amount: Int, hp: Int)
    case residual(BattleSide, BattleStatus, amount: Int, hp: Int)
    case protecting(BattleSide)
    case bracing(BattleSide)
    case blocked(BattleSide)
    case endured(BattleSide)
    case rested(BattleSide, hp: Int)
    case charging(BattleSide, BattleChargeKind)
    case storingEnergy(BattleSide)
    case unleashedEnergy(BattleSide)
    case fellForFeint(BattleSide)
    case foresaw(BattleSide)
    case futureHit(BattleSide, amount: Int, hp: Int)
    case draggedOut(BattleSide)
    case hazardsCleared(BattleSide)
    case fellDown(BattleSide)
    case pumped(BattleSide)
    case screenStarted(BattleSide, BattleBarrier)
    case screenEnded(BattleSide, BattleBarrier)
    case weatherStarted(BattleWeather)
    case weatherEnded(BattleWeather)
    case sportStarted(String)
    case trickRoom(started: Bool)
    case gravity(started: Bool)
    case uproar(BattleSide, started: Bool)
    case taunted(BattleSide)
    case tauntEnded(BattleSide)
    case encored(BattleSide)
    case encoreEnded(BattleSide)
    case disabled(BattleSide, move: String)
    case disableEnded(BattleSide)
    case tormented(BattleSide)
    case imprisoning(BattleSide)
    case healBlocked(BattleSide)
    case healBlockEnded(BattleSide)
    case seeded(BattleSide)
    case drowsy(BattleSide)
    case identified(BattleSide)
    case trapped(BattleSide)
    case stockpiled(BattleSide, count: Int)
    case copiedStages(BattleSide)
    case tookAim(BattleSide)
    case destinyBond(BattleSide)
    case tookDownWithIt(BattleSide)
    case healingWishCameTrue(BattleSide)
    case infatuated(BattleSide)
    case levitating(BattleSide)
    case perishSong
    case perishCount(BattleSide, count: Int)
    case guarding(BattleSide)
    case hazardSet(BattleSide, BattleHazard)
    case transformed(BattleSide, into: BattleSide)
    case typeChanged(BattleSide, type: String)
    case learnedMove(BattleSide, move: String)
    case sharedPain
    case maximizedAttack(BattleSide)
    case madeWish(BattleSide)
    case nightmareStarted(BattleSide)
    case spite(BattleSide, move: String, amount: Int)
    case grudge(BattleSide)
    case grudgeTriggered(BattleSide, move: String)
    case swappedStages(BattleSide)
    case sharedStats(BattleSide)
    case lighter(BattleSide)
    case hurledIntoAir(BattleSide)
    case magicCoat(BattleSide)
    case bounced(BattleSide, move: String)
    case chargingPower(BattleSide)
    case magnitude(Int)
    case aquaRing(BattleSide)
    case rooted(BattleSide)
    case fainted(BattleSide, index: Int)
    case forfeited(BattleSide)
    case ended(winner: BattleSide?)
}

private struct PendingTurn: Codable, Sendable, Equatable {
    var actions: [BattleAction?]
    var queue: [BattleSide]
}

extension BattleMove {
    static let struggle = BattleMove(name: "struggle", type: BattleTypeChart.typeless, power: 50, accuracy: nil,
                                     pp: 1, priority: 0, damageClass: .physical, target: "random-opponent",
                                     category: "damage", healing: -25)

    private static let selfTargets: Set<String> = ["user", "user-and-allies", "user-or-ally", "all-allies", "users-field",
                                                   "entire-field", "all-pokemon"]
    /// Moves that do not aim at the opponent and so skip accuracy, Protect and Magic Coat.
    var targetsUser: Bool {
        if case .effect(let effect) = kind {
            switch effect {
            case .hazard, .perishSong, .haze, .trickRoom, .gravity, .weather, .sport: return true
            default: break
            }
        }
        return Self.selfTargets.contains(target)
    }
    var hitsBothOpponents: Bool { ["all-opponents", "all-other-pokemon"].contains(target) }

    /// PokéAPI reports Toxic's badly-poisoned status as plain poison.
    private static let badPoisonMoves: Set<String> = ["toxic", "poison-fang"]

    var inflictedAilment: BattleAilment? {
        switch ailment {
        case "paralysis": return .major(.paralysis)
        case "burn": return .major(.burn)
        case "freeze": return .major(.freeze)
        case "sleep": return .major(.sleep)
        case "poison": return .major(Self.badPoisonMoves.contains(name) ? .badPoison : .poison)
        case "confusion": return .confusion
        case "unknown" where name == "tri-attack": return .triAttack
        default: return nil
        }
    }

    var isPowder: Bool { ["sleep-powder", "stun-spore", "poison-powder", "spore", "cotton-spore"].contains(name) }
    var isHealing: Bool {
        if category == "heal" { return true }
        if case .effect(let effect) = kind {
            switch effect {
            case .rest, .swallow, .wish, .moonlight, .healingWish: return true
            default: return false
            }
        }
        return false
    }

    /// Moves the engine can resolve. Everything else is shown but cannot be picked.
    var isSupportedInBattle: Bool {
        switch kind {
        case .unsupported: return false
        case .standard: break
        default: return true
        }
        if isDamaging { return true }
        switch category {
        case "net-good-stats": return !statChanges.isEmpty
        case "heal": return healing > 0
        case "ailment": return inflictedAilment != nil
        case "swagger": return true
        default: return false
        }
    }
}

enum BattleAilment: Equatable, Sendable {
    case major(BattleStatus)
    case confusion
    case triAttack
}

enum BattleTypeChart {
    static let typeless = "typeless"
    static let allTypes = ["normal", "fire", "water", "electric", "grass", "ice", "fighting", "poison", "ground", "flying",
                           "psychic", "bug", "rock", "ghost", "dragon", "dark", "steel", "fairy"]
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


extension BattleFormula {
    /// Reversal/Flail power from the share of HP left, in 48ths like the main series.
    static func userHPPower(hp: Int, maxHP: Int) -> Int {
        switch 48 * hp / max(1, maxHP) {
        case ...1: return 200
        case ...4: return 150
        case ...9: return 100
        case ...16: return 80
        case ...32: return 40
        default: return 20
        }
    }

    /// Heavy Slam/Heat Crash: how many times heavier the user is.
    static func weightRatioPower(user: Int, target: Int) -> Int {
        switch user / max(1, target) {
        case 5...: return 120
        case 4: return 100
        case 3: return 80
        case 2: return 60
        default: return 40
        }
    }

    /// Low Kick/Grass Knot from the target's weight in hectograms.
    static func targetWeightPower(_ weight: Int) -> Int {
        switch weight {
        case 2_000...: return 120
        case 1_000...: return 100
        case 500...: return 80
        case 250...: return 60
        case 100...: return 40
        default: return 20
        }
    }

    static func electroBallPower(user: Int, target: Int) -> Int {
        switch user / max(1, target) {
        case 4...: return 150
        case 3: return 120
        case 2: return 80
        case 1: return 60
        default: return 40
        }
    }

    static func gyroBallPower(user: Int, target: Int) -> Int { min(150, 25 * target / max(1, user) + 1) }

    static func trumpCardPower(ppLeft: Int) -> Int {
        switch ppLeft {
        case 0: return 200
        case 1: return 80
        case 2: return 60
        case 3: return 50
        default: return 40
        }
    }
}

/// Deterministic singles battle. Same teams + seed + actions always give the same state and events,
/// which is what lets two Macs each run their own copy in lockstep.
///
/// Any change to these rules must bump `BattleWireMessage.protocolVersion`: two app versions with
/// different rules would silently compute different battles. `BattleEngineVersionTests` enforces it.
struct BattleState: Codable, Sendable, Equatable {
    private(set) var sides: [BattleSideState]
    private(set) var phase: BattlePhase = .choosing
    private(set) var turn = 1
    private(set) var field = BattleField()
    private var rng: BattleRNG
    private var movedThisTurn: [Bool] = [false, false]
    private var pending: PendingTurn?
    /// The last move anyone used, for Copycat.
    private var lastMoveUsed: BattleMove?
    /// Each side's last move, for Mirror Move.
    private var lastMoveBy: [BattleMove?] = [nil, nil]
    /// Stages and effects Baton Pass hands to the Pokémon picked next.
    private var batonPassing: BattlePass?

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

    /// A move the Pokémon is committed to this turn: a second charge turn, recharge, rampage or Bide.
    func forcedMove(for side: BattleSide) -> Int? {
        let v = self[side].current.volatiles
        if v.mustRecharge { return v.rechargeMove }
        return v.chargingMove ?? v.lockedMove
    }

    func usableMoves(for side: BattleSide) -> [Int] {
        if let forced = forcedMove(for: side) { return [forced] }
        let current = self[side].current
        let opponent = self[side.opponent].current
        let v = current.volatiles
        if let encore = v.encoreMove, v.encoreTurns > 0 { return current.pp[encore] > 0 ? [encore] : [] }
        let sealed = opponent.volatiles.imprisoning ? Set(opponent.moves.map(\.name)) : []
        return current.moves.indices.filter { index in
            let move = current.moves[index]
            guard move.isSupportedInBattle, current.pp[index] > 0, index != v.disabledMove else { return false }
            if v.tauntTurns > 0, move.damageClass == .status { return false }
            if v.tormented, index == v.lastMove { return false }
            if sealed.contains(move.name) { return false }
            if v.healBlockTurns > 0, move.isHealing { return false }
            if field.gravityTurns > 0, ["fly", "bounce", "magnet-rise", "telekinesis", "jump-kick", "high-jump-kick",
                                        "splash"].contains(move.name) { return false }
            return true
        }
    }

    func switchTargets(for side: BattleSide) -> [Int] {
        let state = self[side]
        return state.team.indices.filter { $0 != state.active && !state.team[$0].isFainted }
    }

    /// Voluntary switching; being trapped, rooted or committed to a move prevents it.
    func canSwitch(_ side: BattleSide) -> Bool {
        let v = self[side].current.volatiles
        return !v.trapped && !v.ingrained && forcedMove(for: side) == nil
    }

    func legalActions(for side: BattleSide) -> [BattleAction] {
        guard phase == .choosing else { return [] }
        let moves = usableMoves(for: side)
        let switches = canSwitch(side) ? switchTargets(for: side).map(BattleAction.switchTo) : []
        return (moves.isEmpty ? [.struggle] : moves.map(BattleAction.move)) + switches + [.forfeit]
    }

    /// Base power this move would hit with right now; nil for fixed-damage and status moves.
    func effectivePower(of move: BattleMove, by side: BattleSide) -> Int? {
        let user = self[side].current, target = self[side.opponent].current
        switch move.kind {
        case .power(let rule):
            switch rule {
            case .userHP: return BattleFormula.userHPPower(hp: user.hp, maxHP: user.maxHP)
            case .weightRatio: return BattleFormula.weightRatioPower(user: user.weight, target: target.weight)
            case .targetWeight: return BattleFormula.targetWeightPower(target.weight)
            case .doubled(let condition): return (move.power ?? 0) * (doubles(condition, user: side) ? 2 : 1)
            case .fixed(let power): return power
            case .storedPower: return 20 + 20 * user.stages.positiveTotal
            case .punishment: return min(200, 60 + 20 * target.stages.positiveTotal)
            case .gyroBall: return BattleFormula.gyroBallPower(user: effectiveSpeed(side), target: effectiveSpeed(side.opponent))
            case .electroBall: return BattleFormula.electroBallPower(user: effectiveSpeed(side), target: effectiveSpeed(side.opponent))
            case .eruption: return max(1, 150 * user.hp / user.maxHP)
            case .wringOut: return max(1, 1 + 120 * target.hp / target.maxHP)
            case .trumpCard:
                let index = user.moves.firstIndex(of: move)
                return BattleFormula.trumpCardPower(ppLeft: index.map { max(0, user.pp[$0] - 1) } ?? 4)
            case .furyCutter: return min(160, (move.power ?? 40) << min(2, user.volatiles.furyCutter))
            case .echoedVoice:
                let streak = field.echoedVoiceTurn == turn - 1 ? field.echoedVoice : 0
                return min(200, (move.power ?? 40) * (streak + 1))
            case .weatherBall: return field.weather == nil ? 50 : 100
            case .spitUp: return 100 * user.volatiles.stockpile
            case .magnitude: return nil
            }
        case .rollout:
            let base = (move.power ?? 30) << min(4, user.volatiles.lockHits)
            return user.volatiles.defenseCurl ? base * 2 : base
        case .fixedDamage, .ohko, .tripleKick, .beatUp, .present: return nil
        default: return move.power
        }
    }

    private func doubles(_ condition: BattleDoubleCondition, user side: BattleSide) -> Bool {
        let user = self[side].current, target = self[side.opponent].current
        switch condition {
        case .targetHurtThisTurn: return target.turn.damageTaken > 0
        case .targetMovedFirst: return movedThisTurn[side.opponent.rawValue]
        case .hurtByTargetThisTurn: return user.turn.physicalFromOpponent + user.turn.specialFromOpponent > 0
        case .targetAtHalfHP: return target.hp * 2 <= target.maxHP
        case .targetStatused: return target.status != nil
        case .targetPoisoned: return target.status == .poison || target.status == .badPoison
        case .userStatused: return [.burn, .poison, .badPoison, .paralysis].contains(user.status)
        case .targetAsleep: return target.status == .sleep
        case .targetParalyzed: return target.status == .paralysis
        case .allyFaintedLastTurn: return self[side].conditions.faintedLastTurn
        }
    }

    /// Paralysis halves speed and Tailwind doubles it (current generations).
    func effectiveSpeed(_ side: BattleSide) -> Int {
        let current = self[side].current
        var speed = BattleFormula.stagedStat(current.stats.speed, stage: current.stages.speed)
        if current.status == .paralysis { speed /= 2 }
        if self[side].conditions.has(.tailwind) { speed *= 2 }
        return speed
    }

    /// Type effectiveness including Foresight, Miracle Eye, grounding and levitation.
    func effectiveness(of move: BattleMove, type: String, against side: BattleSide) -> Int {
        let target = self[side].current
        var types = target.types
        if target.volatiles.identified, ["normal", "fighting"].contains(type) { types.removeAll { $0 == "ghost" } }
        if target.volatiles.miracleEye, type == "psychic" { types.removeAll { $0 == "dark" } }
        let grounded = target.volatiles.grounded || target.volatiles.ingrained || field.gravityTurns > 0
        if type == "ground" {
            if grounded { types.removeAll { $0 == "flying" } }
            if !grounded, target.volatiles.magnetRiseTurns > 0 || target.volatiles.telekinesisTurns > 0 { return 0 }
        }
        return BattleTypeChart.effectiveness(of: type, against: types)
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

        movedThisTurn = [false, false]
        var events: [BattleEvent] = []
        var queuedActions: [BattleAction?] = [actionA, actionB]
        let switchers = ordered(BattleSide.allCases.filter {
            if case .switchTo = actions[$0] { return true }
            return false
        }, priorities: [:])
        for side in switchers {
            guard case .switchTo(let index) = actions[side] else { continue }
            // Pursuit hits a Pokémon that is switching out, at double power, before it leaves.
            let chaser = side.opponent
            if case .move(let moveIndex) = actions[chaser], !switchers.contains(chaser),
               self[chaser].current.moves[moveIndex].kind == .pursuit, !self[chaser].current.isFainted {
                events += use(chaser, moveIndex: moveIndex, pursuingSwitch: true)
                movedThisTurn[chaser.rawValue] = true
                queuedActions[chaser.rawValue] = nil
                if self[side].current.isFainted { continue }
            }
            events += [.withdrew(side)] + switchIn(side, to: index, midTurn: true)
            movedThisTurn[side.rawValue] = true
            queuedActions[side.rawValue] = nil
        }

        var priorities: [BattleSide: Int] = [:]
        for side in BattleSide.allCases {
            if case .move(let index) = queuedActions[side.rawValue] ?? .forfeit {
                priorities[side] = self[side].current.moves[index].priority
            }
        }
        let attackers = ordered(BattleSide.allCases.filter { queuedActions[$0.rawValue] != nil }, priorities: priorities)
        pending = PendingTurn(actions: queuedActions, queue: attackers)
        events += runPendingTurn()
        return events
    }

    /// Leaving outside the choice phase, e.g. while picking a replacement or when a peer disconnects.
    mutating func forfeit(_ side: BattleSide) -> [BattleEvent] {
        if case .finished = phase { return [] }
        phase = .finished(winner: side.opponent)
        pending = nil
        return [.forfeited(side), .ended(winner: side.opponent)]
    }

    mutating func replace(_ side: BattleSide, with index: Int) throws(BattleEngineError) -> [BattleEvent] {
        guard case .replacing(var waiting) = phase, waiting.contains(side) else { throw .wrongPhase }
        guard switchTargets(for: side).contains(index) else { throw .illegalAction(side) }
        var events = switchIn(side, to: index, midTurn: pending != nil, passing: batonPassing)
        batonPassing = nil
        waiting.removeAll { $0 == side }
        phase = waiting.isEmpty ? .choosing : .replacing(waiting)
        if waiting.isEmpty, pending != nil { events += runPendingTurn() }
        return events
    }

    // MARK: Turn flow

    /// Runs queued actions until a mid-turn switch is needed or the turn ends.
    private mutating func runPendingTurn() -> [BattleEvent] {
        var events: [BattleEvent] = []
        while var turnState = pending, !turnState.queue.isEmpty {
            let side = turnState.queue.removeFirst()
            pending = turnState
            guard let action = turnState.actions[side.rawValue], !self[side].current.isFainted,
                  !self[side.opponent].current.isFainted else { continue }
            switch action {
            case .move(let index): events += use(side, moveIndex: index)
            case .struggle: events += [.noMovesLeft(side)] + use(side, moveIndex: nil)
            case .switchTo, .forfeit: break
            }
            movedThisTurn[side.rawValue] = true
            if case .finished = phase { return events }
            if case .replacing = phase { return events }   // U-turn or Baton Pass: resumes in `replace`
        }
        pending = nil
        events += endOfTurn()
        events += concludeTurn()
        turn += 1
        return events
    }

    private mutating func update(_ side: BattleSide, _ change: (inout BattleCombatant) -> Void) {
        change(&sides[side.rawValue].team[sides[side.rawValue].active])
    }

    private mutating func updateSide(_ side: BattleSide, _ change: (inout BattleSideState) -> Void) {
        change(&sides[side.rawValue])
    }

    /// Higher priority first, then higher effective speed (reversed under Trick Room); ties draw from the RNG.
    private mutating func ordered(_ candidates: [BattleSide], priorities: [BattleSide: Int]) -> [BattleSide] {
        guard candidates.count == 2 else { return candidates }
        let flip = field.trickRoomTurns > 0 ? -1 : 1
        let a = (priorities[.a] ?? 0, flip * effectiveSpeed(.a)), b = (priorities[.b] ?? 0, flip * effectiveSpeed(.b))
        if a == b { return rng.below(2) == 0 ? [.a, .b] : [.b, .a] }
        return a > b ? [.a, .b] : [.b, .a]
    }

    private mutating func switchIn(_ side: BattleSide, to index: Int, midTurn: Bool,
                                   passing: BattlePass? = nil) -> [BattleEvent] {
        update(side) { $0.leaveField() }
        // Whoever trapped the opponent lets go when it leaves.
        update(side.opponent) {
            $0.volatiles.trapped = false
            $0.volatiles.infatuated = false
        }
        sides[side.rawValue].active = index
        let firstTurn = midTurn ? turn + 1 : turn
        update(side) {
            $0.volatiles = BattleVolatiles()
            $0.volatiles.firstTurn = firstTurn
            $0.turn = BattleTurnFlags()
            passing?.apply(to: &$0)
        }
        var events: [BattleEvent] = [.sentOut(side, index: index)]
        if let lunar = self[side].conditions.healingWish {
            updateSide(side) { $0.conditions.healingWish = nil }
            let healed = self[side].current.maxHP - self[side].current.hp
            update(side) {
                $0.hp = $0.maxHP
                $0.status = nil
                if lunar { $0.pp = $0.moves.map(\.pp) }
            }
            events.append(.healingWishCameTrue(side))
            if healed > 0 { events.append(.effectHeal(side, .healingWish, amount: healed, hp: self[side].current.hp)) }
        }
        events += entryHazards(side)
        return events
    }

    private mutating func entryHazards(_ side: BattleSide) -> [BattleEvent] {
        var events: [BattleEvent] = []
        let conditions = self[side].conditions
        let grounded = self[side].current.isGrounded || field.gravityTurns > 0
        if conditions.stealthRock {
            let effectiveness = BattleTypeChart.effectiveness(of: "rock", against: self[side].current.types)
            events += effectDamage(side, .stealthRock, amount: max(1, self[side].current.maxHP * effectiveness / 32))
        }
        if conditions.spikes > 0, grounded, !self[side].current.isFainted {
            let divisor = [8, 6, 4][min(2, conditions.spikes - 1)]
            events += effectDamage(side, .spikes, amount: max(1, self[side].current.maxHP / divisor))
        }
        if conditions.toxicSpikes > 0, grounded, !self[side].current.isFainted {
            if self[side].current.types.contains("poison") {
                updateSide(side) { $0.conditions.toxicSpikes = 0 }
                events.append(.hazardsCleared(side))
            } else if !conditions.has(.safeguard) {
                events += inflict(conditions.toxicSpikes > 1 ? .badPoison : .poison, on: side, primary: false)
            }
        }
        return events
    }

    private mutating func effectDamage(_ side: BattleSide, _ kind: BattleEffectDamage, amount: Int) -> [BattleEvent] {
        let current = self[side].current
        guard !current.isFainted else { return [] }
        let taken = min(amount, current.hp)
        update(side) { $0.hp -= taken }
        var events: [BattleEvent] = [.effectDamage(side, kind, amount: taken, hp: self[side].current.hp)]
        if self[side].current.isFainted { events += faint(side) }
        return events
    }

    private mutating func effectHeal(_ side: BattleSide, _ kind: BattleEffectHeal, amount: Int) -> [BattleEvent] {
        let current = self[side].current
        guard !current.isFainted, current.volatiles.healBlockTurns == 0 else { return [] }
        let healed = min(amount, current.maxHP - current.hp)
        guard healed > 0 else { return [] }
        update(side) { $0.hp += healed }
        return [.effectHeal(side, kind, amount: healed, hp: self[side].current.hp)]
    }

    /// Idempotent: several paths can notice the same knockout.
    private mutating func faint(_ side: BattleSide) -> [BattleEvent] {
        guard self[side].current.isFainted, !self[side].current.faintReported else { return [] }
        update(side) { $0.faintReported = true }
        updateSide(side) { $0.conditions.faintedThisTurn = true }
        return [.fainted(side, index: self[side].active)]
    }

    // MARK: Before the move

    /// Recharge, sleep, freeze, flinch, confusion, love and paralysis, in main-series order. False = turn lost.
    private mutating func canAct(_ side: BattleSide, moveIndex: Int?, _ events: inout [BattleEvent]) -> Bool {
        let current = self[side].current
        if current.volatiles.mustRecharge {
            update(side) { $0.volatiles.mustRecharge = false; $0.volatiles.rechargeMove = nil }
            events.append(.cantMove(side, .recharging))
            return false
        }
        let chosen = moveIndex.map { current.moves[$0] }
        let worksAsleep = chosen?.kind == .snore || chosen?.kind == .effect(.sleepTalk)
        if current.status == .sleep {
            if field.uproarTurns > 0 {
                update(side) { $0.status = nil; $0.sleepTurns = 0 }
                events.append(.wokeUp(side))
            } else if current.sleepTurns > 0 {
                update(side) { $0.sleepTurns -= 1 }
                if !worksAsleep {
                    events.append(.cantMove(side, .asleep))
                    return false
                }
            } else {
                update(side) { $0.status = nil }
                events.append(.wokeUp(side))
            }
        }
        if current.status == .freeze {
            let thaws = ["flame-wheel", "sacred-fire", "flare-blitz", "scald", "fusion-flare"].contains(chosen?.name ?? "")
            guard thaws || rng.percent(20) else {
                events.append(.cantMove(side, .frozen))
                return false
            }
            update(side) { $0.status = nil }
            events.append(.thawed(side))
        }
        if current.turn.flinched {
            events.append(.cantMove(side, .flinched))
            return false
        }
        if current.volatiles.confusionTurns > 0 {
            update(side) { $0.volatiles.confusionTurns -= 1 }
            if self[side].current.volatiles.confusionTurns == 0 {
                events.append(.snappedOut(side))
            } else {
                events.append(.isConfused(side))
                if rng.percent(33) {
                    events += hurtByConfusion(side)
                    return false
                }
            }
        }
        if current.volatiles.infatuated, rng.percent(50) {
            events.append(.cantMove(side, .infatuated))
            return false
        }
        if current.status == .paralysis, rng.percent(25) {
            events.append(.cantMove(side, .paralyzed))
            return false
        }
        return true
    }

    /// A typeless 40-power physical hit against itself; no crit and no STAB.
    private mutating func hurtByConfusion(_ side: BattleSide) -> [BattleEvent] {
        let current = self[side].current
        let attack = BattleFormula.stagedStat(current.stats.attack, stage: current.stages.attack)
        let defense = BattleFormula.stagedStat(current.stats.defense, stage: current.stages.defense)
        let amount = min(current.hp, BattleFormula.damage(
            level: current.pokemon.level, power: 40, attack: attack, defense: defense, critical: false,
            randomPercent: 85 + rng.below(16), stab: false, effectiveness: 4))
        update(side) { $0.hp -= amount }
        var events: [BattleEvent] = [.hurtByConfusion(side, amount: amount, hp: self[side].current.hp)]
        if self[side].current.isFainted { events += faint(side) }
        return events
    }

    private mutating func endLock(_ side: BattleSide) {
        update(side) {
            $0.volatiles.lockedMove = nil
            $0.volatiles.lock = nil
            $0.volatiles.lockTurns = 0
            $0.volatiles.lockHits = 0
        }
    }

    // MARK: Using a move

    private mutating func use(_ side: BattleSide, moveIndex: Int?, pursuingSwitch: Bool = false) -> [BattleEvent] {
        var events: [BattleEvent] = []
        guard canAct(side, moveIndex: moveIndex, &events) else {
            endLock(side)
            update(side) { $0.volatiles.chargingMove = nil; $0.volatiles.hideout = nil }
            return events
        }
        let volatiles = self[side].current.volatiles
        let move: BattleMove
        if let moveIndex {
            move = self[side].current.moves[moveIndex]
            let continuing = volatiles.chargingMove == moveIndex || volatiles.lockedMove == moveIndex
            if !continuing { update(side) { $0.pp[moveIndex] = max(0, $0.pp[moveIndex] - 1) } }
            if volatiles.lastMove != moveIndex, move.kind != .power(.furyCutter) {
                update(side) { $0.volatiles.furyCutter = 0 }
            }
            update(side) { $0.volatiles.lastMove = moveIndex }
            if case .effect(let effect) = move.kind, effect == .grudge || effect == .destinyBond {} else {
                update(side) { $0.volatiles.destinyBond = false; $0.volatiles.grudge = false }
            }
        } else {
            move = .struggle
        }
        if case .effect(.protect) = move.kind {} else if case .effect(.endure) = move.kind {} else {
            update(side) { $0.volatiles.protectStreak = 0 }
        }
        events.append(.usedMove(side, move: move.name))
        lastMoveBy[side.rawValue] = move
        if !isCallingMove(move) { lastMoveUsed = move }
        if move.name == "echoed-voice" {
            field.echoedVoice = field.echoedVoiceTurn == turn - 1 ? field.echoedVoice + 1 : 1
            field.echoedVoiceTurn = turn
        }
        events += perform(move, by: side, index: moveIndex, pursuingSwitch: pursuingSwitch)
        return events
    }

    private func isCallingMove(_ move: BattleMove) -> Bool {
        switch move.kind {
        case .effect(.copycat), .effect(.mirrorMove), .effect(.sleepTalk), .effect(.assist), .effect(.meFirst): return true
        default: return false
        }
    }

    /// What Copycat, Mirror Move, Sleep Talk and Assist may call: nothing that needs a second turn or a lock.
    private func isCallable(_ move: BattleMove) -> Bool {
        guard move.isSupportedInBattle, !isCallingMove(move) else { return false }
        switch move.kind {
        case .charge, .bide, .rampage, .rollout, .uproar, .recharge: return false
        default: return true
        }
    }

    /// The move's effect; `index` is nil for Struggle and for moves called by another move.
    /// `powerPercent` lets Me First hit 50% harder.
    private mutating func perform(_ move: BattleMove, by side: BattleSide, index: Int?, pursuingSwitch: Bool = false,
                                  powerPercent: Int = 100) -> [BattleEvent] {
        let target = side.opponent
        switch move.kind {
        case .effect(let effect):
            return performEffect(effect, move: move, by: side, index: index)
        case .charge(let kind):
            if self[side].current.volatiles.chargingMove == nil {
                if kind == .solarBeam, field.weather == .sun {
                    break
                }
                update(side) {
                    $0.volatiles.chargingMove = index
                    $0.volatiles.hideout = kind.hideout
                    if kind == .skullBash { $0.stages.set("defense", $0.stages.defense + 1) }
                }
                return [.charging(side, kind)]
            }
            update(side) { $0.volatiles.chargingMove = nil; $0.volatiles.hideout = nil }
        case .bide:
            let v = self[side].current.volatiles
            if v.lock != .bide {
                update(side) {
                    $0.volatiles.lockedMove = index
                    $0.volatiles.lock = .bide
                    $0.volatiles.lockTurns = 2
                    $0.volatiles.bideDamage = 0
                }
                return [.storingEnergy(side)]
            }
            update(side) { $0.volatiles.lockTurns -= 1 }
            guard self[side].current.volatiles.lockTurns == 0 else { return [.storingEnergy(side)] }
            let stored = self[side].current.volatiles.bideDamage
            endLock(side)
            guard stored > 0, !self[target].current.isFainted else { return [.unleashedEnergy(side), .failed(side)] }
            var events: [BattleEvent] = [.unleashedEnergy(side)]
            events += hit(target, from: side, amount: stored * 2, effectiveness: 4, critical: false, move: move)
            events += faintChecks(side, target)
            return events
        case .futureAttack:
            guard self[target].conditions.futureTurns == 0 else { return [.failed(side)] }
            let user = self[side].current
            let attack = BattleFormula.stagedStat(user.stats.specialAttack, stage: user.stages.specialAttack)
            let defense = BattleFormula.stagedStat(self[target].current.stats.specialDefense,
                                                   stage: self[target].current.stages.specialDefense)
            let damage = BattleFormula.damage(level: user.pokemon.level, power: move.power ?? 120, attack: attack,
                                              defense: defense, critical: false, randomPercent: 85 + rng.below(16),
                                              stab: false, effectiveness: 4)
            updateSide(target) {
                $0.conditions.futureTurns = 3
                $0.conditions.futureDamage = damage
                $0.conditions.futureType = move.type
            }
            return [.foresaw(side)]
        default:
            break
        }

        // Everything below aims at the opponent.
        var events: [BattleEvent] = []
        if let blocked = blockedOrMissed(move, by: side) {
            events += blocked
            events += afterFailure(move, by: side)
            if move.kind == .selfDestruct { events += selfFaint(side) }
            return events
        }

        switch move.kind {
        case .fakeOut where turn != self[side].current.volatiles.firstTurn,
             .suckerPunch where !opponentIsAttacking(target),
             .focusPunch where self[side].current.turn.damageTaken > 0:
            if move.kind == .focusPunch { return [.cantMove(side, .lostFocus)] }
            return [.failed(side)]
        case .snore where self[side].current.status != .sleep:
            return [.failed(side)]
        default:
            break
        }
        if move.kind == .feint, self[target].current.turn.isProtected {
            update(target) { $0.turn.isProtected = false }
            events.append(.fellForFeint(target))
        }

        if move.isDamaging {
            events += attack(move, by: side, pursuingSwitch: pursuingSwitch, powerPercent: powerPercent)
        } else if move.category == "heal" {
            events += heal(side, percent: move.healing)
        } else if move.category == "ailment", let ailment = move.inflictedAilment {
            events += statusMove(move, ailment, on: target, from: side)
        } else if move.category == "swagger" {
            events += applyStatChanges(move.statChanges, to: target, from: side) + confuse(target, primary: true, from: side)
        } else {
            events += applyStatChanges(move.statChanges, to: move.targetsUser ? side : target, from: side)
        }
        if move.kind == .selfDestruct { events += selfFaint(side) }
        return events
    }

    private mutating func selfFaint(_ side: BattleSide) -> [BattleEvent] {
        guard !self[side].current.isFainted else { return [] }
        update(side) { $0.hp = 0 }
        return faint(side)
    }

    /// Jump Kick crashes, locked moves stop, and charged attacks are wasted when they do not connect.
    private mutating func afterFailure(_ move: BattleMove, by side: BattleSide) -> [BattleEvent] {
        endLock(side)
        update(side) { $0.volatiles.furyCutter = 0 }
        if move.kind == .crash {
            return effectDamage(side, .crash, amount: max(1, self[side].current.maxHP / 2))
        }
        return []
    }

    private func opponentIsAttacking(_ target: BattleSide) -> Bool {
        guard !movedThisTurn[target.rawValue], case .move(let index)? = pending?.actions[target.rawValue] else { return false }
        return self[target].current.moves[index].isDamaging
    }

    /// Semi-invulnerability, Protect and its variants, Magic Coat, and the accuracy roll.
    private mutating func blockedOrMissed(_ move: BattleMove, by side: BattleSide) -> [BattleEvent]? {
        let target = side.opponent
        let user = self[side].current, defender = self[target].current
        if move.targetsUser { return nil }
        let lockedOn = user.volatiles.lockOnTurns > 0 || defender.volatiles.telekinesisTurns > 0
        if let hideout = defender.volatiles.hideout, !lockedOn, !reaches(move, hideout) { return [.missed(side)] }
        let breaksProtection = move.kind == .feint || move.kind == .charge(.vanish)
        if defender.turn.isProtected, !breaksProtection { return [.blocked(target)] }
        if defender.turn.quickGuard, move.priority > 0 { return [.blocked(target)] }
        if defender.turn.wideGuard, move.hitsBothOpponents, move.isDamaging { return [.blocked(target)] }
        if defender.volatiles.magicCoat, move.damageClass == .status {
            update(target) { $0.volatiles.magicCoat = false }
            return [.bounced(target, move: move.name)] + reflect(move, onto: side)
        }
        if lockedOn { return nil }
        if move.kind == .ohko {
            let difference = user.pokemon.level - defender.pokemon.level
            guard difference >= 0, rng.percent(30 + difference) else { return [difference < 0 ? .failed(side) : .missed(side)] }
            return nil
        }
        var accuracy = move.accuracy
        switch (move.name, field.weather) {
        case ("thunder", .rain), ("hurricane", .rain), ("blizzard", .hail): accuracy = nil
        case ("thunder", .sun), ("hurricane", .sun): accuracy = 50
        default: break
        }
        guard let accuracy else { return nil }
        let ignoresEvasion = defender.volatiles.identified || defender.volatiles.miracleEye || move.name == "chip-away"
            || move.name == "sacred-sword"
        let stage = user.stages.accuracy - (ignoresEvasion ? min(0, defender.stages.evasion) : defender.stages.evasion)
        var chance = BattleFormula.hitChance(accuracy: accuracy, stage: stage)
        if field.gravityTurns > 0 { chance = chance * 5 / 3 }
        return rng.percent(chance) ? nil : [.missed(side)]
    }

    private func reaches(_ move: BattleMove, _ hideout: BattleHideout) -> Bool {
        switch hideout {
        case .air: return ["gust", "twister", "thunder", "hurricane", "sky-uppercut", "smack-down"].contains(move.name)
        case .underground: return ["earthquake", "magnitude", "fissure"].contains(move.name)
        case .underwater: return ["surf", "whirlpool"].contains(move.name)
        case .vanished: return false
        }
    }

    /// Magic Coat sends a status move back at its user.
    private mutating func reflect(_ move: BattleMove, onto side: BattleSide) -> [BattleEvent] {
        let from = side.opponent
        if move.category == "ailment", let ailment = move.inflictedAilment {
            return statusMove(move, ailment, on: side, from: from)
        }
        if case .effect(let effect) = move.kind { return performEffect(effect, move: move, by: from, index: nil) }
        return applyStatChanges(move.statChanges, to: side, from: from)
    }

    // MARK: Damage

    private mutating func attack(_ move: BattleMove, by side: BattleSide, pursuingSwitch: Bool, powerPercent: Int) -> [BattleEvent] {
        let target = side.opponent
        let before = self[target].current.hp
        var type = move.type
        if move.kind == .power(.weatherBall), let weather = field.weather {
            type = ["rain": "water", "sun": "fire", "sandstorm": "rock", "hail": "ice"][weather.rawValue] ?? type
        }
        let effectiveness = effectiveness(of: move, type: type, against: target)
        guard effectiveness > 0 else {
            return [.noEffect(target: target)] + afterFailure(move, by: side)
        }

        var events: [BattleEvent] = []
        switch move.kind {
        case .fixedDamage(let rule):
            guard let amount = fixedDamage(rule, by: side) else { return [.failed(side)] }
            events += hit(target, from: side, amount: amount, effectiveness: 4, critical: false, move: move)
            if rule == .finalGambit { events += selfFaint(side) }
            events += faintChecks(side, target)
            return events
        case .ohko:
            events += hit(target, from: side, amount: self[target].current.hp, effectiveness: 4, critical: false, move: move)
            events.insert(.oneHitKO, at: 0)
            events += faintChecks(side, target)
            return events
        case .present:
            let roll = rng.below(10)
            guard roll >= 2 else { return heal(target, amount: max(1, self[target].current.maxHP / 4)) }
            events += strike(move, by: side, type: type, power: roll < 6 ? 40 : roll < 9 ? 80 : 120,
                             effectiveness: effectiveness)
        case .power(.magnitude):
            let roll = rng.below(100)
            let table = [(5, 4, 10), (15, 5, 30), (35, 6, 50), (65, 7, 70), (85, 8, 90), (95, 9, 110), (100, 10, 150)]
            let entry = table.first { roll < $0.0 } ?? (100, 10, 150)
            events.append(.magnitude(entry.1))
            let doubled = self[target].current.volatiles.hideout == .underground ? 2 : 1
            events += strike(move, by: side, type: type, power: entry.2 * doubled, effectiveness: effectiveness)
        case .tripleKick:
            var hits = 0
            for power in [10, 20, 30] where !self[target].current.isFainted {
                if hits > 0, let accuracy = move.accuracy, !rng.percent(accuracy) { break }
                events += strike(move, by: side, type: type, power: power, effectiveness: effectiveness)
                hits += 1
            }
            events.append(.hitCount(hits))
        case .beatUp:
            var hits = 0
            for member in self[side].team where !member.isFainted && member.status == nil && !self[target].current.isFainted {
                events += strike(move, by: side, type: type, power: 5 + member.stats.attack / 20, effectiveness: effectiveness)
                hits += 1
            }
            events.append(.hitCount(hits))
        default:
            guard var power = effectivePower(of: move, by: side) else { return [.failed(side)] }
            if move.kind == .power(.spitUp) {
                guard power > 0 else { return [.failed(side)] }
                update(side) {
                    let count = $0.volatiles.stockpile
                    $0.stages.set("defense", $0.stages.defense - count)
                    $0.stages.set("special-defense", $0.stages.specialDefense - count)
                    $0.volatiles.stockpile = 0
                }
            }
            if pursuingSwitch { power *= 2 }
            power = power * powerPercent / 100
            if let hideout = self[target].current.volatiles.hideout {
                if hideout == .underground, move.name == "earthquake" { power *= 2 }
                if hideout == .underwater, ["surf", "whirlpool"].contains(move.name) { power *= 2 }
                if hideout == .air, ["gust", "twister"].contains(move.name) { power *= 2 }
            }
            let planned = hitCount(move)
            var landed = 0
            for number in 0..<planned where !self[target].current.isFainted && !self[side].current.isFainted {
                events += strike(move, by: side, type: type, power: power, effectiveness: effectiveness,
                                 secondary: number == planned - 1 || move.ailmentChance > 0)
                landed += 1
            }
            // Report the hits that landed, not the planned count: a knockout ends the sequence early.
            if (move.maxHits ?? 1) > 1 { events.append(.hitCount(landed)) }
        }
        events += afterHit(move, by: side, dealt: before - self[target].current.hp)
        events += faintChecks(side, target)
        return events
    }

    private mutating func hitCount(_ move: BattleMove) -> Int {
        guard let low = move.minHits, let high = move.maxHits, high > 1 else { return 1 }
        if low == high { return low }
        // Two to five hits: 1/3, 1/3, 1/6, 1/6.
        if low == 2, high == 5 { return [2, 2, 3, 3, 4, 5][rng.below(6)] }
        return low + rng.below(high - low + 1)
    }

    private mutating func fixedDamage(_ rule: BattleFixedDamage, by side: BattleSide) -> Int? {
        let user = self[side].current, target = self[side.opponent].current
        switch rule {
        case .userLevel: return user.pokemon.level
        case .fixed(let value): return value
        case .halfTargetHP: return max(1, target.hp / 2)
        case .psywave: return max(1, user.pokemon.level * (50 + rng.below(101)) / 100)
        case .endeavor: return target.hp > user.hp ? target.hp - user.hp : nil
        case .finalGambit: return user.hp
        case .counter: return user.turn.physicalFromOpponent > 0 ? user.turn.physicalFromOpponent * 2 : nil
        case .mirrorCoat: return user.turn.specialFromOpponent > 0 ? user.turn.specialFromOpponent * 2 : nil
        case .metalBurst:
            let taken = user.turn.physicalFromOpponent + user.turn.specialFromOpponent
            return taken > 0 ? taken * 3 / 2 : nil
        }
    }

    /// One hit of the damage formula, with every modifier in main-series order.
    private mutating func strike(_ move: BattleMove, by side: BattleSide, type: String, power basePower: Int,
                                 effectiveness: Int, secondary: Bool = true) -> [BattleEvent] {
        let target = side.opponent
        let user = self[side].current, defender = self[target].current
        var power = basePower
        if user.volatiles.charged, type == "electric" { power *= 2 }
        if let sport = field.sports[type], sport > 0 { power = max(1, power / 3) }
        if move.name == "solar-beam", let weather = field.weather, weather != .sun { power /= 2 }

        let alwaysCrits = ["frost-breath", "storm-throw"].contains(move.name)
        let critStage = move.critRate + (user.volatiles.focusEnergy ? 2 : 0)
        let critical = !self[target].conditions.has(.luckyChant)
            && (alwaysCrits || rng.below(BattleFormula.criticalDenominator(stage: critStage)) == 0)
        let physical = move.damageClass == .physical
        let targetsDefense = physical || ["psyshock", "psystrike", "secret-sword"].contains(move.name)
        let attackerStats = move.name == "foul-play" ? defender : user
        var attackStage = physical ? attackerStats.stages.attack : attackerStats.stages.specialAttack
        var defenseStage = targetsDefense ? defender.stages.defense : defender.stages.specialDefense
        if ["chip-away", "sacred-sword"].contains(move.name) { defenseStage = 0 }
        if critical { attackStage = max(0, attackStage); defenseStage = min(0, defenseStage) }
        let attack = BattleFormula.stagedStat(physical ? attackerStats.stats.attack : attackerStats.stats.specialAttack,
                                              stage: attackStage)
        var defense = BattleFormula.stagedStat(targetsDefense ? defender.stats.defense : defender.stats.specialDefense,
                                               stage: defenseStage)
        if field.weather == .sandstorm, !targetsDefense, defender.types.contains("rock") { defense = defense * 3 / 2 }

        var amount = BattleFormula.damage(level: user.pokemon.level, power: power, attack: attack, defense: max(1, defense),
                                          critical: critical, randomPercent: 85 + rng.below(16),
                                          stab: user.types.contains(type), effectiveness: effectiveness)
        switch (field.weather, type) {
        case (.rain, "water"), (.sun, "fire"): amount = amount * 3 / 2
        case (.rain, "fire"), (.sun, "water"): amount = max(1, amount / 2)
        default: break
        }
        if physical, user.status == .burn, move.kind != .power(.doubled(.userStatused)) { amount = max(1, amount / 2) }
        if !critical, self[target].conditions.has(physical ? .reflect : .lightScreen) { amount = max(1, amount / 2) }
        if type == "electric" { update(side) { $0.volatiles.charged = false } }

        var events = hit(target, from: side, amount: amount, effectiveness: effectiveness, critical: critical, move: move)
        if secondary { events += secondaryEffects(move, by: side, type: type) }
        return events
    }

    /// Applies direct damage; Endure leaves the target at 1 HP. Feeds Counter, Bide and Revenge.
    private mutating func hit(_ target: BattleSide, from side: BattleSide, amount: Int, effectiveness: Int,
                              critical: Bool, move: BattleMove) -> [BattleEvent] {
        let current = self[target].current
        var dealt = min(current.hp, amount)
        let endures = current.turn.isEnduring && dealt == current.hp
        if endures { dealt = current.hp - 1 }
        update(target) {
            $0.hp -= dealt
            $0.turn.damageTaken += dealt
            if move.damageClass == .physical { $0.turn.physicalFromOpponent += dealt }
            if move.damageClass == .special { $0.turn.specialFromOpponent += dealt }
            if $0.volatiles.lock == .bide { $0.volatiles.bideDamage += dealt }
        }
        var events: [BattleEvent] = [.damaged(target, amount: dealt, hp: self[target].current.hp,
                                              effectiveness: effectiveness, critical: critical)]
        if endures { events.append(.endured(target)) }
        return events
    }

    private mutating func secondaryEffects(_ move: BattleMove, by side: BattleSide, type: String) -> [BattleEvent] {
        let target = side.opponent
        var events: [BattleEvent] = []
        if type == "fire", self[target].current.status == .freeze, !self[target].current.isFainted {
            update(target) { $0.status = nil }
            events.append(.thawed(target))
        }
        if let ailment = move.inflictedAilment, move.ailmentChance > 0, !self[target].current.isFainted,
           rng.percent(move.ailmentChance) {
            events += apply(ailment, to: target, primary: false, from: side)
        }
        if move.flinchChance > 0, !movedThisTurn[target.rawValue], !self[target].current.isFainted,
           rng.percent(move.flinchChance) {
            update(target) { $0.turn.flinched = true }
        }
        if move.kind == .power(.doubled(.targetAsleep)), self[target].current.status == .sleep {
            update(target) { $0.status = nil; $0.sleepTurns = 0 }
            events.append(.wokeUp(target))
        }
        if move.kind == .power(.doubled(.targetParalyzed)), self[target].current.status == .paralysis {
            update(target) { $0.status = nil }
            events.append(.statusCured(target))
        }
        return events
    }

    /// Drain, recoil, stat effects and move-specific follow-ups once all hits have landed.
    private mutating func afterHit(_ move: BattleMove, by side: BattleSide, dealt: Int) -> [BattleEvent] {
        let target = side.opponent
        var events: [BattleEvent] = []
        if move.drain > 0, self[side].current.volatiles.healBlockTurns == 0 {
            events += heal(side, amount: max(1, dealt * move.drain / 100))
        } else if move.drain < 0 {
            events += takeRecoil(side, amount: max(1, dealt * -move.drain / 100))
        }
        if move.healing < 0 { events += takeRecoil(side, amount: max(1, self[side].current.maxHP * -move.healing / 100)) }
        if !move.statChanges.isEmpty, move.statChance > 0, !self[target].current.isFainted || move.category == "damage-raise",
           rng.percent(move.statChance) {
            events += applyStatChanges(move.statChanges, to: move.category == "damage-raise" ? side : target, from: side)
        }
        update(side) { $0.volatiles.lockOnTurns = 0 }
        switch move.kind {
        case .recharge:
            update(side) { $0.volatiles.mustRecharge = true; $0.volatiles.rechargeMove = $0.volatiles.lastMove }
        case .rampage, .rollout, .uproar:
            events += continueLock(move, by: side)
        case .power(.furyCutter):
            update(side) { $0.volatiles.furyCutter += 1 }
        case .rapidSpin:
            let conditions = self[side].conditions
            if conditions.spikes + conditions.toxicSpikes > 0 || conditions.stealthRock || self[side].current.volatiles.leechSeeded {
                updateSide(side) {
                    $0.conditions.spikes = 0
                    $0.conditions.toxicSpikes = 0
                    $0.conditions.stealthRock = false
                }
                update(side) { $0.volatiles.leechSeeded = false }
                events.append(.hazardsCleared(side))
            }
        case .clearSmog where !self[target].current.isFainted:
            update(target) { $0.stages = BattleStages() }
            events.append(.stagesReset(target))
        case .smackDown where !self[target].current.isFainted:
            update(target) {
                $0.volatiles.grounded = true
                $0.volatiles.magnetRiseTurns = 0
                $0.volatiles.telekinesisTurns = 0
                if $0.volatiles.hideout == .air { $0.volatiles.hideout = nil; $0.volatiles.chargingMove = nil }
            }
            events.append(.fellDown(target))
        case .dragOut where !self[target].current.isFainted:
            events += dragOut(target)
        case .pivot where !self[side].current.isFainted && !switchTargets(for: side).isEmpty:
            events.append(.withdrew(side))
            phase = .replacing([side])
        default:
            break
        }
        return events
    }

    /// Outrage-style moves keep going for 2–3 turns and then confuse; Rollout grows for up to 5; Uproar lasts 3.
    private mutating func continueLock(_ move: BattleMove, by side: BattleSide) -> [BattleEvent] {
        let v = self[side].current.volatiles
        let lock: BattleLock = move.kind == .rampage ? .rampage : move.kind == .rollout ? .rollout : .uproar
        if v.lock == nil {
            let turns = lock == .rampage ? 2 + rng.below(2) : lock == .rollout ? 5 : 3
            update(side) {
                $0.volatiles.lock = lock
                $0.volatiles.lockedMove = $0.volatiles.lastMove
                $0.volatiles.lockTurns = turns
                $0.volatiles.lockHits = 0
            }
            if lock == .uproar {
                field.uproarTurns = 3
                return [.uproar(side, started: true)]
            }
        }
        update(side) {
            $0.volatiles.lockTurns -= 1
            $0.volatiles.lockHits += 1
        }
        guard self[side].current.volatiles.lockTurns <= 0 else { return [] }
        endLock(side)
        if lock == .rampage { return confuse(side, primary: false, from: side) }
        if lock == .uproar { return [.uproar(side, started: false)] }
        return []
    }

    /// Announces knockouts from this move, including Destiny Bond taking the attacker along.
    private mutating func faintChecks(_ side: BattleSide, _ target: BattleSide) -> [BattleEvent] {
        var events: [BattleEvent] = []
        if self[target].current.isFainted {
            events += faint(target)
            if self[target].current.volatiles.destinyBond, !self[side].current.isFainted {
                events.append(.tookDownWithIt(target))
                update(side) { $0.hp = 0 }
            }
            if self[target].current.volatiles.grudge, let index = self[side].current.volatiles.lastMove {
                update(side) { $0.pp[index] = 0 }
                events.append(.grudgeTriggered(side, move: self[side].current.moves[index].name))
            }
        }
        if self[side].current.isFainted { events += faint(side) }
        return events
    }

    private mutating func dragOut(_ target: BattleSide) -> [BattleEvent] {
        let targets = switchTargets(for: target)
        guard !targets.isEmpty, !self[target].current.volatiles.ingrained else { return [] }
        let index = targets[rng.below(targets.count)]
        // The Pokémon dragged in does not get the move its predecessor chose.
        pending?.actions[target.rawValue] = nil
        return [.draggedOut(target)] + switchIn(target, to: index, midTurn: true)
    }

    // MARK: Status

    /// Status moves ignore the type chart, except Thunder Wave (Ground) and powders (Grass).
    private mutating func statusMove(_ move: BattleMove, _ ailment: BattleAilment, on target: BattleSide,
                                     from side: BattleSide) -> [BattleEvent] {
        let types = self[target].current.types
        if move.name == "thunder-wave", effectiveness(of: move, type: move.type, against: target) == 0 {
            return [.noEffect(target: target)]
        }
        if move.isPowder, types.contains("grass") { return [.noEffect(target: target)] }
        return apply(ailment, to: target, primary: true, from: side)
    }

    private mutating func apply(_ ailment: BattleAilment, to target: BattleSide, primary: Bool,
                                from side: BattleSide) -> [BattleEvent] {
        switch ailment {
        case .major(let status): return inflict(status, on: target, primary: primary, from: side)
        case .confusion: return confuse(target, primary: primary, from: side)
        case .triAttack: return inflict([.burn, .paralysis, .freeze][rng.below(3)], on: target, primary: false, from: side)
        }
    }

    /// `primary` = the move's whole point; a failed secondary effect stays silent.
    private mutating func inflict(_ status: BattleStatus, on side: BattleSide, primary: Bool,
                                  from source: BattleSide? = nil) -> [BattleEvent] {
        let current = self[side].current
        let shielded = source != nil && source != side && self[side].conditions.has(.safeguard)
        let sleepless = status == .sleep && (field.uproarTurns > 0 || current.volatiles.insomnia)
        guard !current.isFainted, current.status == nil, !shielded, !sleepless,
              current.types.allSatisfy({ !status.immuneTypes.contains($0) }) else {
            return primary ? [.failed(side)] : []
        }
        let sleepTurns = status == .sleep ? 1 + rng.below(3) : 0
        update(side) {
            $0.status = status
            $0.sleepTurns = sleepTurns
            $0.toxicCounter = 0
            $0.volatiles.yawnTurns = 0
        }
        return [.statusApplied(side, status)]
    }

    private mutating func confuse(_ side: BattleSide, primary: Bool, from source: BattleSide) -> [BattleEvent] {
        let current = self[side].current
        let shielded = source != side && self[side].conditions.has(.safeguard)
        guard !current.isFainted, current.volatiles.confusionTurns == 0, !shielded else { return primary ? [.failed(side)] : [] }
        let turns = 2 + rng.below(4)
        update(side) { $0.volatiles.confusionTurns = turns }
        return [.confused(side)]
    }

    // MARK: Unique effects

    private mutating func performEffect(_ effect: BattleUniqueEffect, move: BattleMove, by side: BattleSide,
                                        index: Int?) -> [BattleEvent] {
        let target = side.opponent
        if !move.targetsUser, let blocked = blockedOrMissed(move, by: side) { return blocked }
        switch effect {
        case .protect: return protect(side, endure: false)
        case .endure: return protect(side, endure: true)
        case .rest: return rest(side)
        case .splash, .noEffectHere: return [.nothingHappened]
        case .failsInSingles: return [.failed(side)]
        case .focusEnergy:
            guard !self[side].current.volatiles.focusEnergy else { return [.failed(side)] }
            update(side) { $0.volatiles.focusEnergy = true }
            return [.pumped(side)]
        case .screen(let screen):
            guard !self[side].conditions.has(screen) else { return [.failed(side)] }
            updateSide(side) { $0.conditions.screens[screen.rawValue] = screen == .tailwind ? 4 : 5 }
            return [.screenStarted(side, screen)]
        case .weather(let weather):
            guard field.weather != weather else { return [.failed(side)] }
            field.weather = weather
            field.weatherTurns = 5
            return [.weatherStarted(weather)]
        case .sport(let type):
            guard (field.sports[type] ?? 0) == 0 else { return [.failed(side)] }
            field.sports[type] = 5
            return [.sportStarted(type)]
        case .trickRoom:
            let starting = field.trickRoomTurns == 0
            field.trickRoomTurns = starting ? 5 : 0
            return [.trickRoom(started: starting)]
        case .gravity:
            guard field.gravityTurns == 0 else { return [.failed(side)] }
            field.gravityTurns = 5
            for other in BattleSide.allCases {
                update(other) {
                    $0.volatiles.magnetRiseTurns = 0
                    $0.volatiles.telekinesisTurns = 0
                    if $0.volatiles.hideout == .air { $0.volatiles.hideout = nil; $0.volatiles.chargingMove = nil }
                }
            }
            return [.gravity(started: true)]
        case .curse:
            if self[side].current.types.contains("ghost") {
                guard !self[target].current.volatiles.cursed else { return [.failed(side)] }
                update(target) { $0.volatiles.cursed = true }
                return effectDamage(side, .curseCost, amount: max(1, self[side].current.maxHP / 2))
            }
            return applyStatChanges([BattleStatChange(stat: "attack", change: 1), BattleStatChange(stat: "defense", change: 1),
                                     BattleStatChange(stat: "speed", change: -1)], to: side, from: side)
        case .taunt:
            guard self[target].current.volatiles.tauntTurns == 0 else { return [.failed(side)] }
            update(target) { $0.volatiles.tauntTurns = 3 }
            return [.taunted(target)]
        case .encore:
            let v = self[target].current.volatiles
            guard v.encoreTurns == 0, let last = v.lastMove, self[target].current.pp[last] > 0,
                  !["encore", "transform", "mimic", "sketch", "mirror-move", "struggle"].contains(self[target].current.moves[last].name)
            else { return [.failed(side)] }
            update(target) { $0.volatiles.encoreTurns = 3; $0.volatiles.encoreMove = last }
            if !movedThisTurn[target.rawValue], case .move? = pending?.actions[target.rawValue] {
                pending?.actions[target.rawValue] = .move(last)
            }
            return [.encored(target)]
        case .disable:
            let v = self[target].current.volatiles
            guard v.disableTurns == 0, let last = v.lastMove, self[target].current.pp[last] > 0 else { return [.failed(side)] }
            update(target) { $0.volatiles.disabledMove = last; $0.volatiles.disableTurns = 4 }
            if !movedThisTurn[target.rawValue], pending?.actions[target.rawValue] == .move(last) {
                pending?.actions[target.rawValue] = nil
            }
            return [.disabled(target, move: self[target].current.moves[last].name)]
        case .torment:
            guard !self[target].current.volatiles.tormented else { return [.failed(side)] }
            update(target) { $0.volatiles.tormented = true }
            return [.tormented(target)]
        case .imprison:
            guard !self[side].current.volatiles.imprisoning else { return [.failed(side)] }
            update(side) { $0.volatiles.imprisoning = true }
            return [.imprisoning(side)]
        case .healBlock:
            guard self[target].current.volatiles.healBlockTurns == 0 else { return [.failed(side)] }
            update(target) { $0.volatiles.healBlockTurns = 5 }
            return [.healBlocked(target)]
        case .roar:
            guard !switchTargets(for: target).isEmpty, !self[target].current.volatiles.ingrained else { return [.failed(side)] }
            return dragOut(target)
        case .leechSeed:
            guard !self[target].current.types.contains("grass") else { return [.noEffect(target: target)] }
            guard !self[target].current.volatiles.leechSeeded else { return [.failed(side)] }
            update(target) { $0.volatiles.leechSeeded = true }
            return [.seeded(target)]
        case .yawn:
            let t = self[target].current
            guard t.status == nil, t.volatiles.yawnTurns == 0, !self[target].conditions.has(.safeguard) else { return [.failed(side)] }
            update(target) { $0.volatiles.yawnTurns = 2 }
            return [.drowsy(target)]
        case .batonPass:
            guard !switchTargets(for: side).isEmpty else { return [.failed(side)] }
            batonPassing = BattlePass(from: self[side].current)
            phase = .replacing([side])
            return [.withdrew(side)]
        case .aquaRing:
            guard !self[side].current.volatiles.aquaRing else { return [.failed(side)] }
            update(side) { $0.volatiles.aquaRing = true }
            return [.aquaRing(side)]
        case .ingrain:
            guard !self[side].current.volatiles.ingrained else { return [.failed(side)] }
            update(side) { $0.volatiles.ingrained = true; $0.volatiles.magnetRiseTurns = 0 }
            return [.rooted(side)]
        case .identify:
            update(target) { $0.volatiles.identified = true }
            return [.identified(target)]
        case .miracleEye:
            update(target) { $0.volatiles.miracleEye = true }
            return [.identified(target)]
        case .trap:
            guard !self[target].current.volatiles.trapped else { return [.failed(side)] }
            update(target) { $0.volatiles.trapped = true }
            return [.trapped(target)]
        case .stockpile:
            guard self[side].current.volatiles.stockpile < 3 else { return [.failed(side)] }
            update(side) { $0.volatiles.stockpile += 1 }
            return [.stockpiled(side, count: self[side].current.volatiles.stockpile)]
                + applyStatChanges([BattleStatChange(stat: "defense", change: 1),
                                    BattleStatChange(stat: "special-defense", change: 1)], to: side, from: side)
        case .swallow:
            let count = self[side].current.volatiles.stockpile
            guard count > 0 else { return [.failed(side)] }
            update(side) {
                $0.stages.set("defense", $0.stages.defense - count)
                $0.stages.set("special-defense", $0.stages.specialDefense - count)
                $0.volatiles.stockpile = 0
            }
            return heal(side, amount: self[side].current.maxHP * [0, 25, 50, 100][count] / 100, failIfFull: true)
        case .psychUp:
            let stages = self[target].current.stages
            update(side) { $0.stages = stages }
            return [.copiedStages(side)]
        case .haze:
            for other in BattleSide.allCases { update(other) { $0.stages = BattleStages() } }
            return [.stagesReset(nil)]
        case .lockOn:
            update(side) { $0.volatiles.lockOnTurns = 2 }
            return [.tookAim(side)]
        case .destinyBond:
            update(side) { $0.volatiles.destinyBond = true }
            return [.destinyBond(side)]
        case .grudge:
            update(side) { $0.volatiles.grudge = true }
            return [.grudge(side)]
        case .memento:
            let drops = applyStatChanges([BattleStatChange(stat: "attack", change: -2),
                                          BattleStatChange(stat: "special-attack", change: -2)], to: target, from: side)
            return drops + selfFaint(side)
        case .healingWish(let lunar):
            guard !switchTargets(for: side).isEmpty else { return [.failed(side)] }
            updateSide(side) { $0.conditions.healingWish = lunar }
            return selfFaint(side)
        case .refresh:
            guard [.burn, .poison, .badPoison, .paralysis].contains(self[side].current.status) else { return [.failed(side)] }
            update(side) { $0.status = nil }
            return [.statusCured(side)]
        case .healBell:
            updateSide(side) { state in for index in state.team.indices { state.team[index].status = nil } }
            return [.teamCured(side)]
        case .copycat:
            guard let called = lastMoveUsed, isCallable(called) else { return [.failed(side)] }
            return [.usedMove(side, move: called.name)] + perform(called, by: side, index: nil)
        case .mirrorMove:
            guard let called = lastMoveBy[target.rawValue], isCallable(called), !called.targetsUser else {
                return [.failed(side)]
            }
            return [.usedMove(side, move: called.name)] + perform(called, by: side, index: nil)
        case .sleepTalk:
            let current = self[side].current
            let options = current.moves.filter(isCallable)
            guard current.status == .sleep, !options.isEmpty else { return [.failed(side)] }
            let called = options[rng.below(options.count)]
            return [.usedMove(side, move: called.name)] + perform(called, by: side, index: nil)
        case .assist:
            let options = self[side].team.indices.filter { $0 != self[side].active }.flatMap { self[side].team[$0].moves }
                .filter(isCallable)
            guard !options.isEmpty else { return [.failed(side)] }
            let called = options[rng.below(options.count)]
            return [.usedMove(side, move: called.name)] + perform(called, by: side, index: nil)
        case .meFirst:
            guard opponentIsAttacking(target), case .move(let chosen)? = pending?.actions[target.rawValue] else {
                return [.failed(side)]
            }
            let called = self[target].current.moves[chosen]
            return [.usedMove(side, move: called.name)] + perform(called, by: side, index: nil, powerPercent: 150)
        case .attract:
            let genders = (self[side].current.pokemon.gender, self[target].current.pokemon.gender)
            guard let mine = genders.0, let theirs = genders.1, mine != .genderless, theirs != .genderless, mine != theirs,
                  !self[target].current.volatiles.infatuated else { return [.failed(side)] }
            update(target) { $0.volatiles.infatuated = true }
            return [.infatuated(target)]
        case .captivate:
            let genders = (self[side].current.pokemon.gender, self[target].current.pokemon.gender)
            guard let mine = genders.0, let theirs = genders.1, mine != .genderless, theirs != .genderless, mine != theirs
            else { return [.failed(side)] }
            return applyStatChanges(move.statChanges, to: target, from: side)
        case .magnetRise:
            guard self[side].current.volatiles.magnetRiseTurns == 0, !self[side].current.volatiles.ingrained,
                  field.gravityTurns == 0 else { return [.failed(side)] }
            update(side) { $0.volatiles.magnetRiseTurns = 5 }
            return [.levitating(side)]
        case .telekinesis:
            guard self[target].current.volatiles.telekinesisTurns == 0, field.gravityTurns == 0 else { return [.failed(side)] }
            update(target) { $0.volatiles.telekinesisTurns = 3 }
            return [.hurledIntoAir(target)]
        case .perishSong:
            for other in BattleSide.allCases where self[other].current.volatiles.perishCount == nil {
                update(other) { $0.volatiles.perishCount = 3 }
            }
            return [.perishSong]
        case .quickGuard, .wideGuard:
            guard !movedThisTurn[target.rawValue] else { return [.failed(side)] }
            update(side) {
                if effect == .quickGuard { $0.turn.quickGuard = true } else { $0.turn.wideGuard = true }
            }
            return [.guarding(side)]
        case .hazard(let hazard):
            let conditions = self[target].conditions
            switch hazard {
            case .spikes:
                guard conditions.spikes < 3 else { return [.failed(side)] }
                updateSide(target) { $0.conditions.spikes += 1 }
            case .toxicSpikes:
                guard conditions.toxicSpikes < 2 else { return [.failed(side)] }
                updateSide(target) { $0.conditions.toxicSpikes += 1 }
            case .stealthRock:
                guard !conditions.stealthRock else { return [.failed(side)] }
                updateSide(target) { $0.conditions.stealthRock = true }
            }
            return [.hazardSet(target, hazard)]
        case .transform:
            let other = self[target].current
            guard other.appearance == nil, self[side].current.appearance == nil, other.volatiles.hideout == nil else {
                return [.failed(side)]
            }
            update(side) {
                $0.savedMoves = $0.moves
                $0.savedPP = $0.pp
                $0.moves = other.moves
                $0.pp = other.moves.map { _ in 5 }
                $0.maxPP = other.moves.map { _ in 5 }
                $0.types = other.types
                $0.stats = BattleStats(hp: $0.stats.hp, attack: other.stats.attack, defense: other.stats.defense,
                                       specialAttack: other.stats.specialAttack, specialDefense: other.stats.specialDefense,
                                       speed: other.stats.speed)
                $0.stages = other.stages
                $0.weight = other.weight
                $0.appearance = other.appearance ?? other.pokemon.speciesID
            }
            return [.transformed(side, into: target)]
        case .conversion:
            let current = self[side].current
            guard let type = current.moves.map(\.type).first(where: { !current.types.contains($0) && $0 != BattleTypeChart.typeless })
            else { return [.failed(side)] }
            update(side) { $0.types = [type] }
            return [.typeChanged(side, type: type)]
        case .conversion2:
            guard let last = lastMoveBy[target.rawValue] else { return [.failed(side)] }
            let resisting = BattleTypeChart.allTypes.first {
                BattleTypeChart.effectiveness(of: last.type, against: [$0]) < 4 && !self[side].current.types.contains($0)
            }
            guard let type = resisting else { return [.failed(side)] }
            update(side) { $0.types = [type] }
            return [.typeChanged(side, type: type)]
        case .soak:
            guard self[target].current.types != ["water"] else { return [.failed(side)] }
            update(target) { $0.types = ["water"] }
            return [.typeChanged(target, type: "water")]
        case .reflectType:
            let types = self[target].current.types
            update(side) { $0.types = types }
            return [.typeChanged(side, type: types.first ?? "normal")]
        case .mimic:
            guard let index, let copied = lastMoveBy[target.rawValue], copied.isSupportedInBattle,
                  !self[side].current.moves.contains(where: { $0.name == copied.name }) else { return [.failed(side)] }
            update(side) {
                if $0.savedMoves == nil { $0.savedMoves = $0.moves; $0.savedPP = $0.pp }
                $0.moves[index] = copied
                $0.pp[index] = min(5, copied.pp)
                $0.maxPP[index] = min(5, copied.pp)
            }
            return [.learnedMove(side, move: copied.name)]
        case .painSplit:
            let average = (self[side].current.hp + self[target].current.hp) / 2
            update(side) { $0.hp = min($0.maxHP, average) }
            update(target) { $0.hp = min($0.maxHP, average) }
            return [.sharedPain,
                    .effectHeal(side, .painSplit, amount: 0, hp: self[side].current.hp),
                    .effectHeal(target, .painSplit, amount: 0, hp: self[target].current.hp)]
        case .bellyDrum:
            let current = self[side].current
            guard current.hp > current.maxHP / 2, current.stages.attack < 6 else { return [.failed(side)] }
            update(side) { $0.stages.set("attack", 6) }
            return effectDamage(side, .bellyDrum, amount: current.maxHP / 2) + [.maximizedAttack(side)]
        case .wish:
            guard self[side].conditions.wishTurns == 0 else { return [.failed(side)] }
            let wishHP = max(1, self[side].current.maxHP / 2)
            updateSide(side) {
                $0.conditions.wishTurns = 2
                $0.conditions.wishHP = wishHP
            }
            return [.madeWish(side)]
        case .nightmare:
            guard self[target].current.status == .sleep, !self[target].current.volatiles.nightmare else { return [.failed(side)] }
            update(target) { $0.volatiles.nightmare = true }
            return [.nightmareStarted(target)]
        case .spite:
            guard let last = self[target].current.volatiles.lastMove, self[target].current.pp[last] > 0 else { return [.failed(side)] }
            let amount = min(4, self[target].current.pp[last])
            update(target) { $0.pp[last] -= amount }
            return [.spite(target, move: self[target].current.moves[last].name, amount: amount)]
        case .swapStages(let share):
            let mine = self[side].current.stages, theirs = self[target].current.stages
            update(side) { $0.stages = BattleStages.swapped(mine, theirs, share) }
            update(target) { $0.stages = BattleStages.swapped(theirs, mine, share) }
            return [.swappedStages(side)]
        case .splitStats(let share):
            let a = self[side].current.stats, b = self[target].current.stats
            update(side) { $0.stats = BattleStats.split(a, b, share) }
            update(target) { $0.stats = BattleStats.split(b, a, share) }
            return [.sharedStats(side)]
        case .autotomize:
            update(side) { $0.weight = max(1, $0.weight - 1_000) }
            return applyStatChanges(move.statChanges, to: side, from: side) + [.lighter(side)]
        case .magicCoat:
            update(side) { $0.volatiles.magicCoat = true }
            return [.magicCoat(side)]
        case .charge:
            update(side) { $0.volatiles.charged = true }
            return [.chargingPower(side)] + applyStatChanges(move.statChanges, to: side, from: side)
        case .defenseCurl:
            update(side) { $0.volatiles.defenseCurl = true }
            return applyStatChanges(move.statChanges, to: side, from: side)
        case .worrySeed:
            guard self[target].current.status != .sleep else { return [.failed(side)] }
            update(target) { $0.volatiles.insomnia = true }
            return [.nothingHappened]
        case .growth:
            let boost = field.weather == .sun ? 2 : 1
            return applyStatChanges(move.statChanges.map { BattleStatChange(stat: $0.stat, change: $0.change * boost) },
                                    to: side, from: side)
        case .selfStats:
            return applyStatChanges(move.statChanges, to: side, from: side)
        case .acupressure:
            let stats = ["attack", "defense", "special-attack", "special-defense", "speed", "accuracy", "evasion"]
                .filter { (self[side].current.stages.value($0) ?? 6) < 6 }
            guard !stats.isEmpty else { return [.failed(side)] }
            return applyStatChanges([BattleStatChange(stat: stats[rng.below(stats.count)], change: 2)], to: side, from: side)
        case .psychoShift:
            guard let status = self[side].current.status else { return [.failed(side)] }
            let moved = inflict(status, on: target, primary: true, from: side)
            guard moved.contains(.statusApplied(target, status)) else { return moved }
            update(side) { $0.status = nil; $0.sleepTurns = 0 }
            return moved + [.statusCured(side)]
        case .defog:
            var events = applyStatChanges(move.statChanges, to: target, from: side)
            let conditions = self[target].conditions
            let barriers: [BattleBarrier] = [.reflect, .lightScreen, .safeguard, .mist]
            if conditions.spikes + conditions.toxicSpikes > 0 || conditions.stealthRock || barriers.contains(where: conditions.has) {
                updateSide(target) {
                    $0.conditions.spikes = 0
                    $0.conditions.toxicSpikes = 0
                    $0.conditions.stealthRock = false
                    for barrier in barriers { $0.conditions.screens[barrier.rawValue] = nil }
                }
                events.append(.hazardsCleared(target))
            }
            return events
        case .camouflage:
            // Link battles take place on the ground terrain, so Camouflage turns the user Ground-type.
            guard self[side].current.types != ["ground"] else { return [.failed(side)] }
            update(side) { $0.types = ["ground"] }
            return [.typeChanged(side, type: "ground")]
        case .moonlight:
            let percent: Int
            switch field.weather {
            case .sun: percent = 67
            case nil: percent = 50
            default: percent = 25
            }
            return heal(side, percent: percent)
        }
    }

    /// Protect fails when the user moves last; each consecutive success is a third as likely.
    private mutating func protect(_ side: BattleSide, endure: Bool) -> [BattleEvent] {
        let streak = self[side].current.volatiles.protectStreak
        let odds = (0..<min(streak, 6)).reduce(1) { odds, _ in odds * 3 }
        guard !movedThisTurn[side.opponent.rawValue], rng.below(odds) == 0 else {
            update(side) { $0.volatiles.protectStreak = 0 }
            return [.failed(side)]
        }
        update(side) {
            $0.volatiles.protectStreak += 1
            if endure { $0.turn.isEnduring = true } else { $0.turn.isProtected = true }
        }
        return [endure ? .bracing(side) : .protecting(side)]
    }

    private mutating func rest(_ side: BattleSide) -> [BattleEvent] {
        let current = self[side].current
        guard current.hp < current.maxHP, current.status != .sleep, field.uproarTurns == 0,
              !current.volatiles.insomnia else { return [.failed(side)] }
        update(side) {
            $0.hp = $0.maxHP
            $0.status = .sleep
            $0.sleepTurns = 2
            $0.toxicCounter = 0
        }
        return [.rested(side, hp: self[side].current.hp)]
    }

    private mutating func heal(_ side: BattleSide, percent: Int) -> [BattleEvent] {
        heal(side, amount: max(1, self[side].current.maxHP * percent / 100), failIfFull: true)
    }

    private mutating func heal(_ side: BattleSide, amount: Int, failIfFull: Bool = false) -> [BattleEvent] {
        let current = self[side].current
        let healed = min(amount, current.maxHP - current.hp)
        guard healed > 0, !current.isFainted, current.volatiles.healBlockTurns == 0 else {
            return failIfFull ? [.failed(side)] : []
        }
        update(side) { $0.hp += healed }
        return [.healed(side, amount: healed, hp: self[side].current.hp)]
    }

    private mutating func takeRecoil(_ side: BattleSide, amount: Int) -> [BattleEvent] {
        let taken = min(amount, self[side].current.hp)
        update(side) { $0.hp -= taken }
        return [.recoil(side, amount: taken, hp: self[side].current.hp)]
    }

    /// Mist stops drops coming from the opponent.
    private mutating func applyStatChanges(_ changes: [BattleStatChange], to side: BattleSide,
                                           from source: BattleSide) -> [BattleEvent] {
        if source != side, self[side].conditions.has(.mist), changes.contains(where: { $0.change < 0 }) {
            return [.failed(side)]
        }
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

    // MARK: End of turn

    private mutating func endOfTurn() -> [BattleEvent] {
        var events: [BattleEvent] = []
        let order: [BattleSide] = effectiveSpeed(.b) > effectiveSpeed(.a) ? [.b, .a] : [.a, .b]

        for side in order {
            if self[side].conditions.futureTurns > 0 {
                updateSide(side) { $0.conditions.futureTurns -= 1 }
                if self[side].conditions.futureTurns == 0, !self[side].current.isFainted {
                    let type = self[side].conditions.futureType
                    let effectiveness = BattleTypeChart.effectiveness(of: type, against: self[side].current.types)
                    let damage = effectiveness == 0 ? 0 : max(1, self[side].conditions.futureDamage * effectiveness / 4)
                    let taken = min(damage, self[side].current.hp)
                    update(side) { $0.hp -= taken }
                    events.append(.futureHit(side, amount: taken, hp: self[side].current.hp))
                    if self[side].current.isFainted { events += faint(side) }
                }
            }
            if self[side].conditions.wishTurns > 0 {
                updateSide(side) { $0.conditions.wishTurns -= 1 }
                if self[side].conditions.wishTurns == 0 {
                    events += effectHeal(side, .wish, amount: self[side].conditions.wishHP)
                }
            }
        }

        if let weather = field.weather {
            for side in order where !self[side].current.isFainted {
                let types = self[side].current.types
                let immune: Set<String> = weather == .sandstorm ? ["rock", "ground", "steel"] : weather == .hail ? ["ice"] : []
                guard weather == .sandstorm || weather == .hail, !types.contains(where: immune.contains),
                      self[side].current.volatiles.hideout != .underground,
                      self[side].current.volatiles.hideout != .underwater else { continue }
                events += effectDamage(side, weather == .sandstorm ? .sandstorm : .hail,
                                       amount: max(1, self[side].current.maxHP / 16))
            }
            field.weatherTurns -= 1
            if field.weatherTurns <= 0 {
                field.weather = nil
                events.append(.weatherEnded(weather))
            }
        }

        for side in order where !self[side].current.isFainted {
            let v = self[side].current.volatiles
            let sixteenth = max(1, self[side].current.maxHP / 16)
            if v.aquaRing { events += effectHeal(side, .aquaRing, amount: sixteenth) }
            if v.ingrained { events += effectHeal(side, .ingrain, amount: sixteenth) }
            if v.leechSeeded, !self[side.opponent].current.isFainted {
                let before = self[side].current.hp
                events += effectDamage(side, .leechSeed, amount: max(1, self[side].current.maxHP / 8))
                events += effectHeal(side.opponent, .leechSeed, amount: before - self[side].current.hp)
            }
            events += statusDamage(side)
            if self[side].current.volatiles.nightmare, self[side].current.status == .sleep {
                events += effectDamage(side, .nightmare, amount: max(1, self[side].current.maxHP / 4))
            }
            if self[side].current.volatiles.cursed {
                events += effectDamage(side, .curse, amount: max(1, self[side].current.maxHP / 4))
            }
        }

        for side in order where !self[side].current.isFainted {
            if let count = self[side].current.volatiles.perishCount {
                update(side) { $0.volatiles.perishCount = count - 1 }
                events.append(.perishCount(side, count: count - 1))
                if count - 1 <= 0 {
                    update(side) { $0.hp = 0 }
                    events += faint(side)
                    continue
                }
            }
            if self[side].current.volatiles.yawnTurns > 0 {
                update(side) { $0.volatiles.yawnTurns -= 1 }
                if self[side].current.volatiles.yawnTurns == 0 { events += inflict(.sleep, on: side, primary: false) }
            }
        }

        events += countdowns()
        for side in BattleSide.allCases {
            update(side) { $0.turn = BattleTurnFlags() }
            updateSide(side) {
                $0.conditions.faintedLastTurn = $0.conditions.faintedThisTurn
                $0.conditions.faintedThisTurn = false
            }
        }
        return events
    }

    private mutating func statusDamage(_ side: BattleSide) -> [BattleEvent] {
        let current = self[side].current
        guard let status = current.status else { return [] }
        let amount: Int
        switch status {
        case .burn: amount = max(1, current.maxHP / 16)
        case .poison: amount = max(1, current.maxHP / 8)
        case .badPoison:
            update(side) { $0.toxicCounter = min(15, $0.toxicCounter + 1) }
            amount = max(1, current.maxHP * self[side].current.toxicCounter / 16)
        case .paralysis, .sleep, .freeze: return []
        }
        let taken = min(amount, current.hp)
        update(side) { $0.hp -= taken }
        var events: [BattleEvent] = [.residual(side, status, amount: taken, hp: self[side].current.hp)]
        if self[side].current.isFainted { events += faint(side) }
        return events
    }

    /// Every "for N turns" effect ticks down here and announces when it ends.
    private mutating func countdowns() -> [BattleEvent] {
        var events: [BattleEvent] = []
        for side in BattleSide.allCases {
            for (key, turns) in self[side].conditions.screens.sorted(by: { $0.key < $1.key }) where turns > 0 {
                updateSide(side) { $0.conditions.screens[key] = turns - 1 }
                if turns - 1 == 0, let screen = BattleBarrier(rawValue: key) { events.append(.screenEnded(side, screen)) }
            }
            guard !self[side].current.isFainted else { continue }
            let v = self[side].current.volatiles
            update(side) {
                if $0.volatiles.lockOnTurns > 0 { $0.volatiles.lockOnTurns -= 1 }
                if $0.volatiles.magnetRiseTurns > 0 { $0.volatiles.magnetRiseTurns -= 1 }
                if $0.volatiles.telekinesisTurns > 0 { $0.volatiles.telekinesisTurns -= 1 }
            }
            if v.tauntTurns > 0 {
                update(side) { $0.volatiles.tauntTurns -= 1 }
                if v.tauntTurns == 1 { events.append(.tauntEnded(side)) }
            }
            if v.encoreTurns > 0 {
                update(side) { $0.volatiles.encoreTurns -= 1 }
                if v.encoreTurns == 1 {
                    update(side) { $0.volatiles.encoreMove = nil }
                    events.append(.encoreEnded(side))
                }
            }
            if v.disableTurns > 0 {
                update(side) { $0.volatiles.disableTurns -= 1 }
                if v.disableTurns == 1 {
                    update(side) { $0.volatiles.disabledMove = nil }
                    events.append(.disableEnded(side))
                }
            }
            if v.healBlockTurns > 0 {
                update(side) { $0.volatiles.healBlockTurns -= 1 }
                if v.healBlockTurns == 1 { events.append(.healBlockEnded(side)) }
            }
        }
        for (type, turns) in field.sports.sorted(by: { $0.key < $1.key }) where turns > 0 { field.sports[type] = turns - 1 }
        if field.trickRoomTurns > 0 {
            field.trickRoomTurns -= 1
            if field.trickRoomTurns == 0 { events.append(.trickRoom(started: false)) }
        }
        if field.gravityTurns > 0 {
            field.gravityTurns -= 1
            if field.gravityTurns == 0 { events.append(.gravity(started: false)) }
        }
        if field.uproarTurns > 0 { field.uproarTurns -= 1 }
        return events
    }

    private mutating func concludeTurn() -> [BattleEvent] {
        let remaining = BattleSide.allCases.filter { self[$0].hasRemaining }
        if remaining.count < 2 {
            let winner = remaining.first
            phase = .finished(winner: winner)
            return [.ended(winner: winner)]
        }
        let waiting = BattleSide.allCases.filter { self[$0].current.isFainted }
        phase = waiting.isEmpty ? .choosing : .replacing(waiting)
        return []
    }
}

/// What Baton Pass hands to the incoming Pokémon.
struct BattlePass: Codable, Sendable, Equatable {
    let stages: BattleStages
    let confusionTurns: Int
    let focusEnergy: Bool
    let leechSeeded: Bool
    let cursed: Bool
    let perishCount: Int?
    let ingrained: Bool
    let aquaRing: Bool
    let magnetRiseTurns: Int
    let lockOnTurns: Int

    init(from combatant: BattleCombatant) {
        stages = combatant.stages
        confusionTurns = combatant.volatiles.confusionTurns
        focusEnergy = combatant.volatiles.focusEnergy
        leechSeeded = combatant.volatiles.leechSeeded
        cursed = combatant.volatiles.cursed
        perishCount = combatant.volatiles.perishCount
        ingrained = combatant.volatiles.ingrained
        aquaRing = combatant.volatiles.aquaRing
        magnetRiseTurns = combatant.volatiles.magnetRiseTurns
        lockOnTurns = combatant.volatiles.lockOnTurns
    }

    func apply(to combatant: inout BattleCombatant) {
        combatant.stages = stages
        combatant.volatiles.confusionTurns = confusionTurns
        combatant.volatiles.focusEnergy = focusEnergy
        combatant.volatiles.leechSeeded = leechSeeded
        combatant.volatiles.cursed = cursed
        combatant.volatiles.perishCount = perishCount
        combatant.volatiles.ingrained = ingrained
        combatant.volatiles.aquaRing = aquaRing
        combatant.volatiles.magnetRiseTurns = magnetRiseTurns
        combatant.volatiles.lockOnTurns = lockOnTurns
    }
}

extension BattleStages {
    var positiveTotal: Int { [attack, defense, specialAttack, specialDefense, speed, accuracy, evasion].filter { $0 > 0 }.reduce(0, +) }

    static func swapped(_ mine: BattleStages, _ theirs: BattleStages, _ share: BattleStageShare) -> BattleStages {
        var result = mine
        switch share {
        case .defenses:
            result.defense = theirs.defense
            result.specialDefense = theirs.specialDefense
        case .offenses:
            result.attack = theirs.attack
            result.specialAttack = theirs.specialAttack
        case .all:
            result = theirs
        }
        return result
    }
}

extension BattleStats {
    static func split(_ mine: BattleStats, _ theirs: BattleStats, _ share: BattleStageShare) -> BattleStats {
        switch share {
        case .defenses:
            return BattleStats(hp: mine.hp, attack: mine.attack, defense: (mine.defense + theirs.defense) / 2,
                               specialAttack: mine.specialAttack,
                               specialDefense: (mine.specialDefense + theirs.specialDefense) / 2, speed: mine.speed)
        case .offenses, .all:
            return BattleStats(hp: mine.hp, attack: (mine.attack + theirs.attack) / 2, defense: mine.defense,
                               specialAttack: (mine.specialAttack + theirs.specialAttack) / 2,
                               specialDefense: mine.specialDefense, speed: mine.speed)
        }
    }
}
