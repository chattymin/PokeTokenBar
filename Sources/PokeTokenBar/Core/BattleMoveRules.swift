import Foundation

/// How a move deviates from "hit once with its listed power", keyed by PokéAPI name. PokéAPI's metadata
/// covers stat changes, ailments, drain and hit counts; everything else needs a rule here.
enum BattleMoveKind: Equatable, Sendable {
    case standard
    case power(BattlePowerRule)
    case fixedDamage(BattleFixedDamage)
    case ohko
    case tripleKick
    case beatUp
    case present
    case recharge
    case charge(BattleChargeKind)
    case rampage
    case rollout
    case uproar
    case bide
    case futureAttack
    case selfDestruct
    case crash
    case fakeOut
    case suckerPunch
    case feint
    case focusPunch
    case pursuit
    case pivot
    case dragOut
    case rapidSpin
    case clearSmog
    case smackDown
    case snore
    case effect(BattleUniqueEffect)
    /// Needs data or mechanics this engine does not have (e.g. a random move from all moves).
    case unsupported
}

enum BattlePowerRule: Equatable, Sendable {
    case userHP, weightRatio, targetWeight
    case doubled(BattleDoubleCondition)
    case fixed(Int)
    case storedPower, punishment, gyroBall, electroBall, eruption, wringOut
    case trumpCard, furyCutter, echoedVoice, weatherBall, spitUp, magnitude
}

enum BattleDoubleCondition: Equatable, Sendable {
    case targetHurtThisTurn, targetMovedFirst, hurtByTargetThisTurn, targetAtHalfHP
    case targetStatused, targetPoisoned, userStatused, targetAsleep, targetParalyzed, allyFaintedLastTurn
}

enum BattleFixedDamage: Equatable, Sendable {
    case userLevel, fixed(Int), halfTargetHP, psywave, endeavor, finalGambit, counter, mirrorCoat, metalBurst
}

enum BattleChargeKind: String, Codable, Sendable {
    case solarBeam, razorWind, skullBash, skyAttack, freezeShock, iceBurn, fly, dig, dive, bounce, vanish

    var hideout: BattleHideout? {
        switch self {
        case .fly, .bounce: return .air
        case .dig: return .underground
        case .dive: return .underwater
        case .vanish: return .vanished
        default: return nil
        }
    }
}

/// Where a two-turn move keeps its user out of reach.
enum BattleHideout: String, Codable, Sendable { case air, underground, underwater, vanished }

enum BattleWeather: String, Codable, Sendable { case rain, sun, sandstorm, hail }
enum BattleBarrier: String, Codable, Sendable {
    case reflect, lightScreen, safeguard, mist, tailwind, luckyChant

    var moveName: String {
        switch self {
        case .lightScreen: return "light-screen"
        case .luckyChant: return "lucky-chant"
        default: return rawValue
        }
    }
}
enum BattleHazard: String, Codable, Sendable { case spikes, toxicSpikes, stealthRock }
enum BattleStageShare: String, Codable, Sendable { case defenses, offenses, all }

enum BattleUniqueEffect: Equatable, Sendable {
    case protect, endure, rest, focusEnergy, splash, noEffectHere, failsInSingles
    case screen(BattleBarrier), weather(BattleWeather), sport(String), trickRoom, gravity
    case curse, taunt, encore, disable, torment, imprison, healBlock, roar, leechSeed, yawn, batonPass
    case aquaRing, ingrain, identify, miracleEye, trap, stockpile, swallow, psychUp, haze, lockOn
    case destinyBond, memento, healingWish(lunar: Bool), refresh, copycat, mirrorMove, sleepTalk, assist, meFirst
    case attract, magnetRise, perishSong, quickGuard, wideGuard, hazard(BattleHazard), transform
    case conversion, conversion2, soak, reflectType, mimic, painSplit, bellyDrum, healBell, wish, nightmare
    case spite, grudge, captivate, swapStages(BattleStageShare), splitStats(BattleStageShare), autotomize
    case telekinesis, magicCoat, charge, defenseCurl, worrySeed, growth, moonlight
    case selfStats, acupressure, psychoShift, defog, camouflage
}

extension BattleMove {
    private static let kinds: [String: BattleMoveKind] = {
        var table: [String: BattleMoveKind] = [
            "reversal": .power(.userHP), "flail": .power(.userHP),
            "heavy-slam": .power(.weightRatio), "heat-crash": .power(.weightRatio),
            "low-kick": .power(.targetWeight), "grass-knot": .power(.targetWeight),
            "assurance": .power(.doubled(.targetHurtThisTurn)), "payback": .power(.doubled(.targetMovedFirst)),
            "revenge": .power(.doubled(.hurtByTargetThisTurn)), "avalanche": .power(.doubled(.hurtByTargetThisTurn)),
            "brine": .power(.doubled(.targetAtHalfHP)), "hex": .power(.doubled(.targetStatused)),
            "venoshock": .power(.doubled(.targetPoisoned)), "facade": .power(.doubled(.userStatused)),
            "wake-up-slap": .power(.doubled(.targetAsleep)), "smelling-salts": .power(.doubled(.targetParalyzed)),
            "retaliate": .power(.doubled(.allyFaintedLastTurn)),
            // No held items in this game: Acrobatics always gets its itemless double power.
            "acrobatics": .power(.fixed(110)),
            // Pokémon raised on tokens are treated as maximally friendly.
            "return": .power(.fixed(102)), "frustration": .power(.fixed(1)),
            "stored-power": .power(.storedPower), "punishment": .power(.punishment),
            "gyro-ball": .power(.gyroBall), "electro-ball": .power(.electroBall),
            "eruption": .power(.eruption), "water-spout": .power(.eruption),
            "wring-out": .power(.wringOut), "crush-grip": .power(.wringOut),
            "trump-card": .power(.trumpCard), "fury-cutter": .power(.furyCutter),
            "echoed-voice": .power(.echoedVoice), "weather-ball": .power(.weatherBall),
            "spit-up": .power(.spitUp), "magnitude": .power(.magnitude),
            "seismic-toss": .fixedDamage(.userLevel), "night-shade": .fixedDamage(.userLevel),
            "dragon-rage": .fixedDamage(.fixed(40)), "sonic-boom": .fixedDamage(.fixed(20)),
            "super-fang": .fixedDamage(.halfTargetHP), "psywave": .fixedDamage(.psywave),
            "endeavor": .fixedDamage(.endeavor), "final-gambit": .fixedDamage(.finalGambit),
            "counter": .fixedDamage(.counter), "mirror-coat": .fixedDamage(.mirrorCoat),
            "metal-burst": .fixedDamage(.metalBurst),
            "sheer-cold": .ohko, "guillotine": .ohko, "fissure": .ohko, "horn-drill": .ohko,
            "triple-kick": .tripleKick, "beat-up": .beatUp, "present": .present,
            "solar-beam": .charge(.solarBeam), "razor-wind": .charge(.razorWind), "skull-bash": .charge(.skullBash),
            "sky-attack": .charge(.skyAttack), "freeze-shock": .charge(.freezeShock), "ice-burn": .charge(.iceBurn),
            "fly": .charge(.fly), "dig": .charge(.dig), "dive": .charge(.dive), "bounce": .charge(.bounce),
            "shadow-force": .charge(.vanish), "phantom-force": .charge(.vanish),
            "outrage": .rampage, "thrash": .rampage, "petal-dance": .rampage,
            "rollout": .rollout, "ice-ball": .rollout, "uproar": .uproar, "bide": .bide,
            "future-sight": .futureAttack, "doom-desire": .futureAttack,
            "explosion": .selfDestruct, "self-destruct": .selfDestruct,
            "jump-kick": .crash, "high-jump-kick": .crash,
            "fake-out": .fakeOut, "sucker-punch": .suckerPunch, "feint": .feint, "focus-punch": .focusPunch,
            "pursuit": .pursuit, "u-turn": .pivot, "volt-switch": .pivot,
            "dragon-tail": .dragOut, "circle-throw": .dragOut, "rapid-spin": .rapidSpin,
            "clear-smog": .clearSmog, "smack-down": .smackDown, "snore": .snore,
            "metronome": .unsupported, "nature-power": .unsupported, "substitute": .unsupported,
            "snatch": .unsupported, "sky-drop": .unsupported,
        ]
        for name in ["hyper-beam", "giga-impact", "blast-burn", "hydro-cannon", "frenzy-plant", "rock-wrecker", "roar-of-time"] {
            table[name] = .recharge
        }
        let effects: [String: BattleUniqueEffect] = [
            "protect": .protect, "detect": .protect, "endure": .endure, "rest": .rest,
            "focus-energy": .focusEnergy, "splash": .splash,
            "reflect": .screen(.reflect), "light-screen": .screen(.lightScreen), "safeguard": .screen(.safeguard),
            "mist": .screen(.mist), "tailwind": .screen(.tailwind), "lucky-chant": .screen(.luckyChant),
            "rain-dance": .weather(.rain), "sunny-day": .weather(.sun), "sandstorm": .weather(.sandstorm),
            "hail": .weather(.hail), "water-sport": .sport("fire"), "mud-sport": .sport("electric"),
            "trick-room": .trickRoom, "gravity": .gravity,
            "curse": .curse, "taunt": .taunt, "encore": .encore, "disable": .disable, "torment": .torment,
            "imprison": .imprison, "heal-block": .healBlock, "roar": .roar, "whirlwind": .roar,
            "leech-seed": .leechSeed, "yawn": .yawn, "baton-pass": .batonPass, "aqua-ring": .aquaRing,
            "ingrain": .ingrain, "foresight": .identify, "odor-sleuth": .identify, "miracle-eye": .miracleEye,
            "mean-look": .trap, "block": .trap, "spider-web": .trap,
            "stockpile": .stockpile, "swallow": .swallow, "psych-up": .psychUp, "haze": .haze,
            "lock-on": .lockOn, "mind-reader": .lockOn, "destiny-bond": .destinyBond, "memento": .memento,
            "healing-wish": .healingWish(lunar: false), "lunar-dance": .healingWish(lunar: true),
            "refresh": .refresh, "copycat": .copycat, "mirror-move": .mirrorMove, "sleep-talk": .sleepTalk,
            "assist": .assist, "me-first": .meFirst, "attract": .attract, "magnet-rise": .magnetRise,
            "perish-song": .perishSong, "quick-guard": .quickGuard, "wide-guard": .wideGuard,
            "spikes": .hazard(.spikes), "toxic-spikes": .hazard(.toxicSpikes), "stealth-rock": .hazard(.stealthRock),
            "transform": .transform, "conversion": .conversion, "conversion-2": .conversion2, "soak": .soak,
            "reflect-type": .reflectType, "mimic": .mimic, "sketch": .mimic, "pain-split": .painSplit,
            "belly-drum": .bellyDrum, "heal-bell": .healBell, "aromatherapy": .healBell, "wish": .wish,
            "nightmare": .nightmare, "spite": .spite, "grudge": .grudge, "captivate": .captivate,
            "guard-swap": .swapStages(.defenses), "power-swap": .swapStages(.offenses), "heart-swap": .swapStages(.all),
            "guard-split": .splitStats(.defenses), "power-split": .splitStats(.offenses), "autotomize": .autotomize,
            "telekinesis": .telekinesis, "magic-coat": .magicCoat, "charge": .charge,
            "defense-curl": .defenseCurl, "worry-seed": .worrySeed, "growth": .growth,
            "moonlight": .moonlight, "synthesis": .moonlight, "morning-sun": .moonlight,
            "shell-smash": .selfStats, "acupressure": .acupressure, "psycho-shift": .psychoShift, "defog": .defog,
            "camouflage": .camouflage,
            "teleport": .failsInSingles, "helping-hand": .failsInSingles, "follow-me": .failsInSingles,
            "rage-powder": .failsInSingles, "ally-switch": .failsInSingles, "after-you": .failsInSingles,
            "quash": .failsInSingles, "aromatic-mist": .failsInSingles,
        ]
        // This game has no held items and no abilities: these moves succeed but change nothing.
        for name in ["embargo", "gastro-acid", "simple-beam", "entrainment", "skill-swap", "role-play", "magic-room",
                     "wonder-room", "power-trick", "trick", "switcheroo", "bestow", "recycle", "fling", "natural-gift"] {
            table[name] = .effect(.noEffectHere)
        }
        for (name, effect) in effects { table[name] = .effect(effect) }
        return table
    }()

    var kind: BattleMoveKind { Self.kinds[name] ?? .standard }

    /// Kinds whose damage does not come from the listed power, so a nil power is expected.
    var hasDamageRule: Bool {
        switch kind {
        case .power, .fixedDamage, .ohko, .tripleKick, .beatUp, .present: return true
        default: return false
        }
    }

    /// Rule-based damage, used for legality and the CPU.
    var damageRule: BattleFixedDamage? {
        if case .fixedDamage(let rule) = kind { return rule }
        return nil
    }
}
