import Foundation

/// The rules a battle was fought under: a replay keeps its version, so a later rule change never rewrites an old one.
enum BattleRules {
    /// 2 (the owner, 2026-11-09): the next Pokémon steps in at once after a knock-out, and a foe stepping in faces the
    /// player's best against it (`BattleSimulation.rematch`). A battle of version 1 replays as it was fought.
    static let version = 2
    /// Every cast lasts a third of its time (R1: battles three times faster).
    static let speedUp = 3
    /// One turn of the games in battle time (the owner, 2026-11-03): Bide waits two, Counter answers a hit of the last one.
    static let turn = 4000
    /// Burn, poison, weather, traps and Leech Seed act every four seconds.
    static let residualTick = 4000
    /// A frozen Pokémon may thaw every two seconds, one time in five.
    static let thawTick = 2000
    /// Weather and terrains last twenty seconds.
    static let fieldDuration = 20000
    /// Version 1: the next Pokémon stepped in one second after a knock-out. None since version 2.
    static let benchDelay = 1000
    /// Version 2: how much better a bench member must fare against a foe stepping in for the Pokémon in front to leave
    /// it its place (`BattleMatchup.score`), so that two near equals never swap for nothing.
    static let rematchMargin = 0.05
    /// A battle that runs this long ends on the HP left.
    static let timeLimit = 300_000
    /// Spread moves hit each foe at 75% when more than one stands (R3: never an ally).
    static let spreadFactor = 0.75
}

/// A battler's stats, the HP its maximum.
struct BattleStats: Codable, Sendable, Equatable {
    var hp: Int
    var attack: Int
    var defense: Int
    var specialAttack: Int
    var specialDefense: Int
    var speed: Int

    func value(_ stat: BattleStat) -> Int {
        switch stat {
        case .attack: attack
        case .defense: defense
        case .specialAttack: specialAttack
        case .specialDefense: specialDefense
        case .speed: speed
        case .accuracy, .evasion: 1
        }
    }

    /// The games' formula at `level`, a nature's change included. Shedinja always has 1 HP.
    /// `evs`: none but in Giovanni's armor (the owner, 2026-11-17: "ivs evs parfaits"), the games' formula's quarter.
    static func computed(base: [Int], ivs: [Int], evs: [Int] = [], level: Int, nature: PokemonNature?, speciesID: Int) -> BattleStats {
        func iv(_ i: Int) -> Int { (i < ivs.count ? ivs[i] : 0) + (i < evs.count ? evs[i] / 4 : 0) }
        func other(_ i: Int, _ name: String) -> Int {
            let neutral = ((2 * base[i] + iv(i)) * level) / 100 + 5
            return Int((Double(neutral) * (nature?.modifier(for: name) ?? 1)).rounded(.down))
        }
        let hp = speciesID == PokemonStatCalculator.shedinjaSpeciesID ? 1 : ((2 * base[0] + iv(0)) * level) / 100 + level + 10
        return BattleStats(hp: hp, attack: other(1, "attack"), defense: other(2, "defense"),
                           specialAttack: other(3, "special-attack"), specialDefense: other(4, "special-defense"),
                           speed: other(5, "speed"))
    }

    /// A boss's HP and stats multiplied (R13).
    func scaled(hp hpFactor: Double, stats factor: Double) -> BattleStats {
        BattleStats(hp: Int((Double(hp) * hpFactor).rounded()), attack: Int((Double(attack) * factor).rounded()),
                    defense: Int((Double(defense) * factor).rounded()),
                    specialAttack: Int((Double(specialAttack) * factor).rounded()),
                    specialDefense: Int((Double(specialDefense) * factor).rounded()),
                    speed: Int((Double(speed) * factor).rounded()))
    }
}

/// One Pokémon going into a battle: what the engine needs, nothing of the save.
struct BattlerSpec: Codable, Sendable, Equatable {
    /// Stable within the battle: a Pokédex entry's id, or a wild one's.
    var id: String
    var speciesID: Int
    var form: PokemonForm?
    var level: Int
    var types: [PokemonType]
    /// `hp` is the maximum.
    var stats: BattleStats
    /// HP at the start: a dungeon keeps them from one battle to the next.
    var hp: Int
    var ability: String?
    /// The loop, one to four moves, cast in order then again.
    var moves: [String]
    var isShiny = false
    /// A boss never falls to a one-hit knock-out move, and loses only a share of its HP to the moves that do not
    /// read the damage formula (the owner, 2026-11-03: "on doit jamais pouvoir one shot des boss").
    var isBoss = false
    /// A Pokémon of the player's has its profile's; nil for a foe, whose gender `resolvedGender` draws.
    var gender: PokemonGender?
    /// Hidden Power's type, from its IVs (`hiddenPowerType(ivs:)`); nil in a battle saved before it.
    var hiddenPowerType: PokemonType?

    /// Hidden Power's type as the games read it from the IVs' parity: HP, Attack, Defense, Speed, Special Attack and
    /// Special Defense, the sixteen types from Fighting to Dark. `ivs`: HP, Attack, Defense, Special Attack, Special
    /// Defense, Speed.
    static func hiddenPowerType(ivs: [Int]) -> PokemonType {
        guard ivs.count == 6 else { return .normal }
        let bits = [ivs[0], ivs[1], ivs[2], ivs[5], ivs[3], ivs[4]].enumerated().reduce(0) { $0 + ($1.element & 1) << $1.offset }
        let order: [PokemonType] = [.fighting, .flying, .poison, .ground, .rock, .bug, .ghost, .steel, .fire, .water,
                                    .grass, .electric, .psychic, .ice, .dragon, .dark]
        return order[bits * 15 / 63]
    }

    /// Its gender: its own, or for a foe one drawn by its species' rate, the same for the same Pokémon (its id and
    /// stats), so a replay shows the same.
    var resolvedGender: PokemonGender? {
        if let gender { return gender }
        guard let rate = SpeciesInfo.all[speciesID]?.genderRate else { return nil }
        if rate < 0 { return .genderless }
        var hash: UInt64 = 1_469_598_103_934_665_603
        let key = "\(id)|\(stats.hp)|\(stats.attack)|\(stats.defense)|\(stats.specialAttack)|\(stats.specialDefense)|\(stats.speed)"
        for byte in key.utf8 { hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211 }
        return Int(hash % 8) < rate ? .female : .male
    }
}

/// Berries a side eats on its own when a Pokémon's HP drop (each Pokémon at most one per battle).
enum BattleBerry: String, Codable, Sendable, CaseIterable {
    /// 25% of the HP.
    case oran
    /// 50% of the HP.
    case sitrus

    var share: Double { self == .oran ? 0.25 : 0.5 }
}

/// One side: its Pokémon, how many stand on the field at once, and its berries.
struct BattleSideSpec: Codable, Sendable, Equatable {
    var battlers: [BattlerSpec]
    /// The first ones fight; the others wait on the bench, the best against the foe in front stepping in.
    var active: Int
    var berries: [BattleBerry: Int] = [:]
}

/// What a battle is: two sides and a seed. The same setup always plays the same battle, to the millisecond.
struct BattleSetup: Codable, Sendable, Equatable {
    var sides: [BattleSideSpec]
    var seed: UInt64
    var rules = BattleRules.version
}

/// The weather and terrains a battle knows.
enum BattleWeather: String, Codable, Sendable {
    case sun, rain, sand, snow
}

enum BattleTerrain: String, Codable, Sendable {
    case electric, grassy, misty, psychic
}

/// Why a Pokémon lost HP outside a hit.
enum BattleHurtCause: String, Codable, Sendable {
    case burn, poison, weather, recoil, trap, leechSeed, confusion, ability, belly, destinyBond, sun, painSplit
    /// Substitute's cost, and Spiky Shield's thorns.
    case substitute, protection
    /// Spikes or Stealth Rock on entry.
    case hazard
    case curse, nightmare, perishSong
}

/// Why a Pokémon regained HP.
enum BattleHealCause: String, Codable, Sendable {
    case move, drain, berry, ability, weather, leechSeed, wish, terrain, painSplit, ingrain, aquaRing
}

/// Why a cast did nothing.
enum BattleFailReason: String, Codable, Sendable {
    case paralysis, confusion, noTarget, protected, truant, immune, failed
    /// A status move against a Pokémon behind its substitute.
    case substitute
    /// A move that does nothing here, as in the games (Splash), or whose effect has no hold in these battles.
    case nothing
    /// Taunt, Encore, Disable, Torment, Imprison or Heal Block forbids the move now.
    case restrained
    /// In love (Attract, Cute Charm), it would not attack.
    case infatuation
}

/// Everything that happens, timed in milliseconds from the start: a replay replays these, a live view plays them at
/// their time.
enum BattleEvent: Codable, Sendable, Equatable {
    case enter(side: Int, slot: Int, battler: String)
    /// U-turn, Baton Pass, Roar... took the battler off the field, back to its bench.
    case leave(battler: String)
    case cast(battler: String, move: String, target: String?, ends: Int)
    case hit(attacker: String, target: String, move: String, damage: Int, hp: Int, effectiveness: Double, critical: Bool)
    case miss(attacker: String, target: String, move: String)
    case noEffect(attacker: String, target: String, move: String)
    case fail(battler: String, move: String, reason: BattleFailReason)
    case status(battler: String, ailment: BattleAilment)
    case cure(battler: String, ailment: BattleAilment)
    case stat(battler: String, stat: BattleStat, change: Int)
    case heal(battler: String, amount: Int, hp: Int, cause: BattleHealCause)
    case hurt(battler: String, amount: Int, hp: Int, cause: BattleHurtCause)
    case flinch(battler: String)
    case ability(battler: String, ability: String)
    case berry(battler: String, berry: BattleBerry)
    /// The battler no longer holds its berry: knocked off, burnt, stolen or eaten by `by`, thrown, given.
    case berryTaken(battler: String, berry: BattleBerry, by: String?)
    /// Recycle, Thief, Trick or Bestow gave the battler a berry to hold.
    case berryGiven(battler: String, berry: BattleBerry)
    case weather(BattleWeather?)
    case terrain(BattleTerrain?)
    case faint(battler: String)
    /// A move that uses another (Metronome, Sleep Talk, Copycat...) and the move it used; Instruct's ally repeating.
    case call(battler: String, move: String)
    /// Transform or Imposter: the battler now looks like `into`.
    case transform(battler: String, into: String)
    /// Mimic or Sketch put `move` in the loop for the rest of the battle.
    case learn(battler: String, move: String)
    /// The battler's substitute, `hp` left (0: it broke).
    case substitute(battler: String, hp: Int)
    /// Endure kept the battler at 1 HP.
    case endured(battler: String)
    /// Magic Coat or Magic Bounce sent `move` back; Snatch took it.
    case reflect(battler: String, move: String)
    /// A side's Reflect, Light Screen, Aurora Veil, Safeguard, Mist, Tailwind or Lucky Chant starts or ends.
    case sideCondition(side: Int, condition: String, active: Bool)
    /// Trick Room, Gravity, Magic Room, Wonder Room, Mud Sport, Water Sport or Ion Deluge starts or ends.
    case fieldCondition(condition: String, active: Bool)
    /// A side's entry hazard and its layers now (0: cleared).
    case hazard(side: Int, hazard: String, layers: Int)
    /// A lasting effect on one battler starts: Taunt, Encore, Disable, Torment, Heal Block, Embargo, Perish Song,
    /// Nightmare, Ingrain, Aqua Ring, Foresight, Miracle Eye, Telekinesis, Magnet Rise, Curse, Lock-On, Octolock,
    /// Tar Shot, Imprison, Grudge.
    case volatile(battler: String, effect: String)
    /// Soak, Reflect Type, Conversion... gave the battler these types.
    case retype(battler: String, types: [PokemonType])
    /// Skill Swap, Role Play, Entrainment, Simple Beam, Worry Seed or Gastro Acid gave the battler this ability ("" for
    /// none).
    case abilityChange(battler: String, ability: String)
    case end(winner: Int)
}

struct TimedBattleEvent: Codable, Sendable, Equatable {
    let time: Int
    let event: BattleEvent
}

/// How a battle ended, and its whole story.
struct BattleOutcome: Codable, Sendable, Equatable {
    var setup: BattleSetup
    /// 0 or 1.
    var winner: Int
    var duration: Int
    var events: [TimedBattleEvent]
    /// HP each Pokémon ended with.
    var hpLeft: [String: Int]
    var berriesLeft: [[BattleBerry: Int]]
}

/// A deterministic random sequence (SplitMix64): the battle's only source of chance.
struct BattleRandom: Sendable {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// 0 ..< bound.
    mutating func below(_ bound: Int) -> Int {
        guard bound > 1 else { return 0 }
        return Int(next() % UInt64(bound))
    }

    /// True `percent` times in 100.
    mutating func chance(_ percent: Int) -> Bool {
        percent >= 100 || (percent > 0 && below(100) < percent)
    }

    /// lower ... upper.
    mutating func between(_ lower: Int, _ upper: Int) -> Int {
        upper <= lower ? lower : lower + below(upper - lower + 1)
    }
}
