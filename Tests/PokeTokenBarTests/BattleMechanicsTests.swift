import XCTest
@testable import PokeTokenBar

private func move(_ name: String, type: String = "normal", power: Int? = 40, accuracy: Int? = nil, pp: Int = 30,
                  priority: Int = 0, damageClass: BattleDamageClass = .physical, target: String = "selected-pokemon",
                  statChanges: [BattleStatChange] = [], category: String? = "damage", ailment: String? = nil,
                  ailmentChance: Int = 0, flinchChance: Int = 0, healing: Int = 0) -> BattleMove {
    BattleMove(name: name, type: type, power: power, accuracy: accuracy, pp: pp, priority: priority,
               damageClass: damageClass, target: target, statChanges: statChanges, category: category,
               healing: healing, ailment: ailment, ailmentChance: ailmentChance, flinchChance: flinchChance)
}

private let tackle = move("tackle")
/// Harmless and supported, for a side that should just pass the turn (Splash would make it Struggle).
private let harden = move("harden", power: nil, damageClass: .status, target: "user",
                          statChanges: [BattleStatChange(stat: "defense", change: 1)], category: "net-good-stats")
private let splash = move("metronome", power: nil, damageClass: .status, target: "user", category: "unique")
private let protect = move("protect", power: nil, pp: 10, priority: 4, damageClass: .status, target: "user", category: "unique")
private let endure = move("endure", power: nil, pp: 10, priority: 4, damageClass: .status, target: "user", category: "unique")
private let rest = move("rest", power: nil, pp: 10, damageClass: .status, target: "user", category: "unique")
private let nuke = move("nuke", power: 250)
private func statusMove(_ name: String, _ ailment: String, type: String = "normal") -> BattleMove {
    move(name, type: type, power: nil, damageClass: .status, category: "ailment", ailment: ailment)
}
private let thunderWave = statusMove("thunder-wave", "paralysis", type: "electric")
private let willOWisp = statusMove("will-o-wisp", "burn", type: "fire")
private let poisonPowder = statusMove("poison-powder", "poison", type: "poison")
private let toxic = statusMove("toxic", "poison", type: "poison")
private let hypnosis = statusMove("hypnosis", "sleep", type: "psychic")
private let confuseRay = statusMove("confuse-ray", "confusion", type: "ghost")

private func mon(_ id: String, hp: Int = 160, attack: Int = 60, defense: Int = 60, speed: Int = 50, level: Int = 50,
                 types: [String] = ["normal"], moves: [BattleMove] = [tackle], weight: Int = 100) -> BattlePokemon {
    BattlePokemon(instanceID: id, speciesID: 25, names: ["en": id], level: level, isShiny: false, unownForm: nil,
                  gender: nil, nature: nil, abilityName: nil, types: types,
                  stats: BattleStats(hp: hp, attack: attack, defense: defense, specialAttack: 60,
                                     specialDefense: 60, speed: speed),
                  moves: moves, weight: weight)
}

private func battle(_ a: [BattlePokemon], _ b: [BattlePokemon], seed: UInt64 = 1) throws -> BattleState {
    BattleState(teamA: try BattleTeam(members: a), teamB: try BattleTeam(members: b), seed: seed)
}

private func damage(to side: BattleSide, in events: [BattleEvent]) -> Int? {
    events.compactMap { if case .damaged(side, let amount, _, _, _) = $0 { return amount } else { return nil } }.first
}

final class BattleDamageRuleTests: XCTestCase {
    func testPowerTablesMatchTheMainSeries() {
        XCTAssertEqual(BattleFormula.userHPPower(hp: 1, maxHP: 100), 200)
        XCTAssertEqual(BattleFormula.userHPPower(hp: 9, maxHP: 100), 150)
        XCTAssertEqual(BattleFormula.userHPPower(hp: 20, maxHP: 100), 100)
        XCTAssertEqual(BattleFormula.userHPPower(hp: 34, maxHP: 100), 80)
        XCTAssertEqual(BattleFormula.userHPPower(hp: 60, maxHP: 100), 40)
        XCTAssertEqual(BattleFormula.userHPPower(hp: 100, maxHP: 100), 20)
        XCTAssertEqual(BattleFormula.weightRatioPower(user: 500, target: 100), 120)
        XCTAssertEqual(BattleFormula.weightRatioPower(user: 400, target: 100), 100)
        XCTAssertEqual(BattleFormula.weightRatioPower(user: 300, target: 100), 80)
        XCTAssertEqual(BattleFormula.weightRatioPower(user: 250, target: 100), 60)
        XCTAssertEqual(BattleFormula.weightRatioPower(user: 100, target: 400), 40)
        XCTAssertEqual(BattleFormula.targetWeightPower(2_000), 120)
        XCTAssertEqual(BattleFormula.targetWeightPower(1_999), 100)
        XCTAssertEqual(BattleFormula.targetWeightPower(500), 80)
        XCTAssertEqual(BattleFormula.targetWeightPower(250), 60)
        XCTAssertEqual(BattleFormula.targetWeightPower(100), 40)
        XCTAssertEqual(BattleFormula.targetWeightPower(99), 20)
    }

    func testVariablePowerFollowsHPAndWeight() throws {
        let reversal = move("reversal", type: "fighting", power: nil)
        var low = try battle([mon("a", hp: 160, speed: 10, moves: [reversal])],
                             [mon("b", hp: 999, attack: 150, speed: 90, moves: [tackle])])
        XCTAssertEqual(low.effectivePower(of: reversal, by: .a), 20, "full HP is the weakest Reversal")
        _ = try low.resolveTurn(.move(0), .move(0))
        XCTAssertLessThan(low[.a].current.hp, 160)
        XCTAssertGreaterThan(try XCTUnwrap(low.effectivePower(of: reversal, by: .a)), 20, "less HP, more power")

        let heavySlam = move("heavy-slam", type: "steel", power: nil)
        let heavy = try battle([mon("a", moves: [heavySlam], weight: 4_000)], [mon("b", weight: 100)])
        XCTAssertEqual(heavy.effectivePower(of: heavySlam, by: .a), 120)
        let lowKick = move("low-kick", type: "fighting", power: nil)
        let kick = try battle([mon("a", moves: [lowKick])], [mon("b", weight: 2_100)])
        XCTAssertEqual(kick.effectivePower(of: lowKick, by: .a), 120)

    }

    func testFixedDamageIgnoresTheFormulaButNotImmunity() throws {
        let seismicToss = move("seismic-toss", type: "fighting", power: nil)
        let dragonRage = move("dragon-rage", type: "dragon", power: nil, damageClass: .special)
        let superFang = move("super-fang", power: nil)
        var state = try battle([mon("a", speed: 90, level: 37, moves: [seismicToss, dragonRage, superFang])],
                               [mon("b", hp: 300, defense: 999, types: ["rock", "steel"], moves: [splash])])
        XCTAssertEqual(damage(to: .b, in: try state.resolveTurn(.move(0), .struggle)), 37, "Seismic Toss deals the user's level")
        XCTAssertEqual(damage(to: .b, in: try state.resolveTurn(.move(1), .struggle)), 40)
        let hpBefore = state[.b].current.hp
        XCTAssertEqual(damage(to: .b, in: try state.resolveTurn(.move(2), .struggle)), hpBefore / 2)

        var ghost = try battle([mon("a", speed: 90, moves: [seismicToss])], [mon("g", types: ["ghost"], moves: [splash])])
        XCTAssertTrue(try ghost.resolveTurn(.move(0), .struggle).contains(.noEffect(target: .b)))
        var fairy = try battle([mon("a", speed: 90, moves: [dragonRage])], [mon("f", types: ["fairy"], moves: [splash])])
        XCTAssertTrue(try fairy.resolveTurn(.move(0), .struggle).contains(.noEffect(target: .b)))
    }

    func testRuleMovesAreSupportedAndUnknownOnesAreNot() {
        for name in ["reversal", "flail", "heavy-slam", "heat-crash", "low-kick", "grass-knot",
                     "seismic-toss", "night-shade", "dragon-rage", "sonic-boom", "super-fang"] {
            XCTAssertTrue(move(name, power: nil).isSupportedInBattle, name)
        }
        for supported in [protect, endure, rest, thunderWave, confuseRay,
                          move("swagger", power: nil, damageClass: .status, category: "swagger")] {
            XCTAssertTrue(supported.isSupportedInBattle, supported.name)
        }
        XCTAssertFalse(splash.isSupportedInBattle)
        for name in ["metronome", "nature-power", "substitute", "snatch", "sky-drop"] {
            XCTAssertFalse(move(name, power: nil, damageClass: .status, category: "unique").isSupportedInBattle, name)
        }
        XCTAssertFalse(move("some-future-move", power: nil, damageClass: .status, category: "unique").isSupportedInBattle,
                       "an unknown unique move stays unsupported until it has a rule")
    }
}

final class BattleProtectionTests: XCTestCase {
    func testProtectBlocksAttacksAndStatusMoves() throws {
        var state = try battle([mon("a", moves: [protect, harden])], [mon("b", speed: 90, moves: [tackle, thunderWave])])
        var events = try state.resolveTurn(.move(0), .move(0))
        XCTAssertEqual(events.prefix(3), [.usedMove(.a, move: "protect"), .protecting(.a), .usedMove(.b, move: "tackle")],
                       "priority +4 goes first even though the user is slower")
        XCTAssertTrue(events.contains(.blocked(.a)))
        XCTAssertEqual(state[.a].current.hp, 160)
        events = try state.resolveTurn(.move(1), .move(1))
        XCTAssertEqual(state[.a].current.status, .paralysis, "Protect lasts one turn only")
        XCTAssertFalse(events.contains(.blocked(.a)))
    }

    func testRepeatedProtectGetsLessReliableAndMovingLastFails() throws {
        var failures = 0
        for seed in UInt64(1)...60 {
            var state = try battle([mon("a", moves: [protect, tackle])], [mon("b", moves: [tackle])], seed: seed)
            _ = try state.resolveTurn(.move(0), .move(0))
            if try state.resolveTurn(.move(0), .move(0)).contains(.failed(.a)) { failures += 1 }
        }
        XCTAssertGreaterThan(failures, 25, "the second Protect in a row succeeds only a third of the time")
        XCTAssertLessThan(failures, 55)

        var both = try battle([mon("fast", speed: 90, moves: [protect])], [mon("slow", speed: 10, moves: [protect])])
        let events = try both.resolveTurn(.move(0), .move(0))
        XCTAssertTrue(events.contains(.protecting(.a)))
        XCTAssertTrue(events.contains(.failed(.b)), "Protect fails for whoever moves last")
    }

    func testEndureSurvivesAKnockoutWithOneHP() throws {
        var state = try battle([mon("a", hp: 50, moves: [endure])], [mon("b", attack: 200, moves: [nuke])])
        let events = try state.resolveTurn(.move(0), .move(0))
        XCTAssertTrue(events.contains(.bracing(.a)))
        XCTAssertTrue(events.contains(.endured(.a)))
        XCTAssertEqual(state[.a].current.hp, 1)
        XCTAssertEqual(state.phase, .choosing)
    }
}

final class BattleStatusTests: XCTestCase {
    func testParalysisHalvesSpeedAndSometimesStopsTheMove() throws {
        var state = try battle([mon("a", speed: 40, moves: [thunderWave, tackle])], [mon("b", speed: 60)])
        let events = try state.resolveTurn(.move(0), .move(0))
        XCTAssertTrue(events.contains(.statusApplied(.b, .paralysis)))
        XCTAssertEqual(state.effectiveSpeed(.b), 30)
        var fullyParalyzed = 0
        for _ in 0..<40 {
            let turn = try state.resolveTurn(.move(1), .move(0))
            XCTAssertEqual(turn.first, .usedMove(.a, move: "tackle"), "the halved Pokémon now moves second")
            if turn.contains(.cantMove(.b, .paralyzed)) { fullyParalyzed += 1 }
            if state.phase != .choosing { break }
        }
        XCTAssertGreaterThan(fullyParalyzed, 0)
    }

    func testTypeImmunitiesAndOneStatusAtATime() throws {
        var electric = try battle([mon("a", speed: 90, moves: [thunderWave])], [mon("e", types: ["electric"], moves: [splash])])
        XCTAssertTrue(try electric.resolveTurn(.move(0), .struggle).contains(.failed(.b)))
        var ground = try battle([mon("a", speed: 90, moves: [thunderWave])], [mon("g", types: ["ground"], moves: [splash])])
        XCTAssertTrue(try ground.resolveTurn(.move(0), .struggle).contains(.noEffect(target: .b)),
                      "Thunder Wave follows the type chart")
        var steel = try battle([mon("a", speed: 90, moves: [toxic])], [mon("s", types: ["steel"], moves: [splash])])
        XCTAssertTrue(try steel.resolveTurn(.move(0), .struggle).contains(.failed(.b)))
        var grass = try battle([mon("a", speed: 90, moves: [poisonPowder])], [mon("p", types: ["grass"], moves: [splash])])
        XCTAssertTrue(try grass.resolveTurn(.move(0), .struggle).contains(.noEffect(target: .b)), "powders miss Grass types")
        var dark = try battle([mon("a", speed: 90, moves: [hypnosis])], [mon("d", types: ["dark"], moves: [splash])])
        XCTAssertTrue(try dark.resolveTurn(.move(0), .struggle).contains(.statusApplied(.b, .sleep)),
                      "other status moves ignore the type chart")

        var twice = try battle([mon("a", speed: 90, moves: [willOWisp, thunderWave])], [mon("b", hp: 999, moves: [splash])])
        _ = try twice.resolveTurn(.move(0), .struggle)
        XCTAssertTrue(try twice.resolveTurn(.move(1), .struggle).contains(.failed(.b)))
        XCTAssertEqual(twice[.b].current.status, .burn)
    }

    /// The random factor is 85–100%, so a halved hit can never reach half of the largest normal one:
    /// comparing against that bound tests the burn itself, not two different random rolls.
    func testBurnHalvesPhysicalDamageAndHurtsEachTurn() throws {
        let unburnedMax = BattleFormula.damage(level: 50, power: 40, attack: 60, defense: 60, critical: false,
                                               randomPercent: 100, stab: true, effectiveness: 4)
        let unburnedMin = BattleFormula.damage(level: 50, power: 40, attack: 60, defense: 60, critical: false,
                                               randomPercent: 85, stab: true, effectiveness: 4)
        XCTAssertGreaterThan(unburnedMin, unburnedMax / 2, "the bound below only works if the ranges do not overlap")
        var checked = 0
        for seed in UInt64(1)...20 {
            var state = try battle([mon("a", speed: 10, moves: [tackle])],
                                   [mon("b", hp: 999, speed: 90, moves: [willOWisp, harden])], seed: seed)
            _ = try state.resolveTurn(.move(0), .move(0))
            guard state[.a].current.status == .burn else { continue }
            if seed == 1 { XCTAssertEqual(state[.a].current.hp, 160 - 10, "a burn costs 1/16 of max HP each turn") }
            let events = try state.resolveTurn(.move(0), .move(1))
            guard case .damaged(.b, let amount, _, _, false)? = events.first(where: {
                if case .damaged(.b, _, _, _, _) = $0 { return true } else { return false }
            }) else { continue }
            XCTAssertLessThanOrEqual(amount, unburnedMax / 2, "seed \(seed)")
            checked += 1
        }
        XCTAssertGreaterThan(checked, 10)
    }

    func testPoisonAndBadPoisonDamageAndSwitchingResetsTheToxicCounter() throws {
        var poisoned = try battle([mon("a", speed: 90, moves: [poisonPowder])], [mon("b", hp: 160, moves: [harden])])
        _ = try poisoned.resolveTurn(.move(0), .move(0))
        XCTAssertEqual(poisoned[.b].current.hp, 140, "poison costs 1/8")

        var badly = try battle([mon("a", speed: 90, moves: [toxic, tackle])],
                               [mon("b", hp: 160, moves: [harden]), mon("b2", moves: [harden])])
        var events = try badly.resolveTurn(.move(0), .move(0))
        XCTAssertTrue(events.contains(.statusApplied(.b, .badPoison)))
        XCTAssertEqual(badly[.b].current.hp, 150, "1/16 on the first turn")
        _ = try badly.resolveTurn(.move(1), .move(0))
        let afterSecond = badly[.b].current.hp
        XCTAssertTrue(events.contains { if case .residual(.b, .badPoison, 10, _) = $0 { return true } else { return false } })
        events = try badly.resolveTurn(.move(1), .switchTo(1))
        _ = try badly.resolveTurn(.move(1), .switchTo(0))
        XCTAssertLessThan(afterSecond, 150)
        XCTAssertEqual(badly[.b].current.status, .badPoison, "the status stays through a switch")
        XCTAssertEqual(badly[.b].current.toxicCounter, 1, "the counter restarts after coming back in")
    }

    func testSleepSkipsTurnsThenWakesAndActs() throws {
        for seed in UInt64(1)...15 {
            var state = try battle([mon("a", speed: 90, moves: [hypnosis, harden])], [mon("b", hp: 999)], seed: seed)
            // Put to sleep before it moved, so the first lost turn is this one.
            var asleep = try state.resolveTurn(.move(0), .move(0)).contains(.cantMove(.b, .asleep)) ? 1 : 0
            XCTAssertEqual(state[.b].current.status, .sleep)
            while true {
                let events = try state.resolveTurn(.move(1), .move(0))
                if events.contains(.cantMove(.b, .asleep)) { asleep += 1; continue }
                XCTAssertTrue(events.contains(.wokeUp(.b)))
                XCTAssertTrue(events.contains(.usedMove(.b, move: "tackle")), "it acts on the turn it wakes")
                break
            }
            XCTAssertTrue((1...3).contains(asleep), "seed \(seed): slept \(asleep) turns")
        }
    }

    func testRestHealsFullyAndSleepsTwoTurnsButFailsAtFullHP() throws {
        var state = try battle([mon("a", moves: [rest])], [mon("b", attack: 90, speed: 90)])
        XCTAssertTrue(try state.resolveTurn(.move(0), .move(0)).contains(.rested(.a, hp: 160)))
        XCTAssertEqual(state[.a].current.status, .sleep)
        XCTAssertTrue(try state.resolveTurn(.move(0), .move(0)).contains(.cantMove(.a, .asleep)))
        XCTAssertTrue(try state.resolveTurn(.move(0), .move(0)).contains(.cantMove(.a, .asleep)))
        XCTAssertTrue(try state.resolveTurn(.move(0), .move(0)).contains(.wokeUp(.a)))

        var full = try battle([mon("a", speed: 90, moves: [rest])], [mon("b", moves: [splash])])
        XCTAssertTrue(try full.resolveTurn(.move(0), .struggle).contains(.failed(.a)))
    }

    func testFreezeStopsMovesAndFireThawsTheTarget() throws {
        let iceBeam = move("ice-beam", type: "ice", power: 20, damageClass: .special, category: "damage-ailment",
                           ailment: "freeze", ailmentChance: 100)
        let ember = move("ember", type: "fire", power: 20, damageClass: .special)
        var state = try battle([mon("a", speed: 90, moves: [iceBeam, ember, harden])], [mon("b", hp: 999)], seed: 2)
        _ = try state.resolveTurn(.move(0), .move(0))
        XCTAssertEqual(state[.b].current.status, .freeze)
        var frozenTurns = 0
        for _ in 0..<3 where try state.resolveTurn(.move(2), .move(0)).contains(.cantMove(.b, .frozen)) { frozenTurns += 1 }
        XCTAssertGreaterThan(frozenTurns, 0)
        var fire = try battle([mon("a", speed: 90, moves: [iceBeam, ember])], [mon("b", hp: 999)], seed: 2)
        _ = try fire.resolveTurn(.move(0), .move(0))
        XCTAssertTrue(try fire.resolveTurn(.move(1), .move(0)).contains(.thawed(.b)))
        var ice = try battle([mon("a", speed: 90, moves: [iceBeam])], [mon("i", hp: 999, types: ["ice"])])
        _ = try ice.resolveTurn(.move(0), .move(0))
        XCTAssertNil(ice[.b].current.status, "Ice types cannot be frozen")
    }

    func testConfusionCanHurtTheUserEndsAndClearsOnSwitch() throws {
        var hurt = 0, snapped = 0
        for seed in UInt64(1)...20 {
            var state = try battle([mon("a", speed: 90, moves: [confuseRay, harden])], [mon("b", hp: 999), mon("b2")],
                                   seed: seed)
            var turns = [try state.resolveTurn(.move(0), .move(0))]
            XCTAssertTrue(turns[0].contains(.confused(.b)))
            turns.append(try state.resolveTurn(.move(0), .move(0)))
            XCTAssertTrue(turns[1].contains(.failed(.b)), "no double confusion")
            while !turns.joined().contains(.snappedOut(.b)), turns.count < 8 {
                turns.append(try state.resolveTurn(.move(1), .move(0)))
            }
            let all = Array(turns.joined())
            hurt += all.filter { if case .hurtByConfusion(.b, _, _) = $0 { return true } else { return false } }.count
            let confusedAttempts = all.filter { $0 == .isConfused(.b) }.count
            XCTAssertTrue((1...4).contains(confusedAttempts), "seed \(seed): confused for \(confusedAttempts) attempts")
            if all.contains(.snappedOut(.b)) { snapped += 1 }
        }
        XCTAssertGreaterThan(hurt, 0)
        XCTAssertEqual(snapped, 20, "confusion always ends within four turns")

        var switching = try battle([mon("a", speed: 90, moves: [confuseRay, harden])], [mon("b"), mon("b2")])
        _ = try switching.resolveTurn(.move(0), .move(0))
        _ = try switching.resolveTurn(.move(1), .switchTo(1))
        _ = try switching.resolveTurn(.move(1), .switchTo(0))
        XCTAssertEqual(switching[.b].current.volatiles.confusionTurns, 0)
    }

    func testFlinchOnlyWorksWhenTheAttackerMovesFirst() throws {
        let bite = move("bite", type: "dark", power: 20, flinchChance: 100)
        var first = try battle([mon("a", speed: 90, moves: [bite])], [mon("b", hp: 999)])
        XCTAssertTrue(try first.resolveTurn(.move(0), .move(0)).contains(.cantMove(.b, .flinched)))
        var second = try battle([mon("a", speed: 10, moves: [bite])], [mon("b", hp: 999, speed: 90)])
        let events = try second.resolveTurn(.move(0), .move(0))
        XCTAssertFalse(events.contains(.cantMove(.b, .flinched)))
        XCTAssertFalse(second[.b].current.turn.flinched, "flinching ends with the turn")
    }

    func testSecondaryStatusAndSwagger() throws {
        let bodySlam = move("body-slam", power: 20, category: "damage-ailment", ailment: "paralysis", ailmentChance: 100)
        var state = try battle([mon("a", speed: 90, moves: [bodySlam])], [mon("b", hp: 999)])
        XCTAssertTrue(try state.resolveTurn(.move(0), .move(0)).contains(.statusApplied(.b, .paralysis)))
        XCTAssertFalse(try state.resolveTurn(.move(0), .move(0)).contains(.failed(.b)),
                       "a secondary effect on an already-statused target stays silent")

        let swagger = move("swagger", power: nil, damageClass: .status,
                           statChanges: [BattleStatChange(stat: "attack", change: 2)], category: "swagger")
        var swag = try battle([mon("a", speed: 90, moves: [swagger])], [mon("b", hp: 999, moves: [splash])])
        let events = try swag.resolveTurn(.move(0), .struggle)
        XCTAssertTrue(events.contains(.statChanged(.b, stat: "attack", change: 2)))
        XCTAssertTrue(events.contains(.confused(.b)))
    }
}

final class BattleCPUStatusTests: XCTestCase {
    func testCPUUsesStatusMovesOnlyWhileTheyCanStillWork() throws {
        var state = try battle([mon("foe", hp: 999, moves: [harden])], [mon("cpu", moves: [thunderWave, tackle])])
        XCTAssertGreaterThan(BattleCPU.score(thunderWave, by: .b, in: state), BattleCPU.score(tackle, by: .b, in: state))
        _ = try state.resolveTurn(.move(0), .move(0))
        XCTAssertEqual(state[.a].current.status, .paralysis)
        XCTAssertEqual(BattleCPU.score(thunderWave, by: .b, in: state), 0, "paralyzing twice is pointless")
        XCTAssertEqual(BattleCPU.score(confuseRay, by: .b, in: state) > 0, true)

        let electric = try battle([mon("e", types: ["electric"])], [mon("cpu", moves: [thunderWave])])
        XCTAssertEqual(BattleCPU.score(thunderWave, by: .b, in: electric), 0)
    }

    func testCPUScoresProtectLowRestWhenHurtAndFixedDamageByImmunity() throws {
        let seismicToss = move("seismic-toss", type: "fighting", power: nil)
        var state = try battle([mon("foe", attack: 200, speed: 90, moves: [nuke])],
                               [mon("cpu", hp: 300, moves: [protect, rest, tackle, seismicToss])])
        XCTAssertLessThan(BattleCPU.score(protect, by: .b, in: state), BattleCPU.score(tackle, by: .b, in: state))
        XCTAssertEqual(BattleCPU.score(rest, by: .b, in: state), 0, "no reason to rest at full HP")
        XCTAssertGreaterThan(BattleCPU.score(seismicToss, by: .b, in: state), 0)
        _ = try state.resolveTurn(.move(0), .move(2))
        XCTAssertLessThan(state[.b].current.hp * 2, 300)
        XCTAssertGreaterThan(BattleCPU.score(rest, by: .b, in: state), BattleCPU.score(tackle, by: .b, in: state))

        let ghost = try battle([mon("g", types: ["ghost"])], [mon("cpu", moves: [seismicToss])])
        XCTAssertEqual(BattleCPU.score(seismicToss, by: .b, in: ghost), 0)
    }
}

final class BattleSecondaryConfusionTests: XCTestCase {
    func testDamagingMovesCanConfuseAndStaySilentWhenAlreadyConfused() throws {
        let psybeam = move("psybeam", type: "psychic", power: 20, damageClass: .special, category: "damage-ailment",
                           ailment: "confusion", ailmentChance: 100)
        var state = try battle([mon("a", speed: 90, moves: [psybeam])], [mon("b", hp: 999, moves: [harden])])
        XCTAssertTrue(try state.resolveTurn(.move(0), .move(0)).contains(.confused(.b)))
        let again = try state.resolveTurn(.move(0), .move(0))
        XCTAssertFalse(again.contains(.confused(.b)))
        XCTAssertFalse(again.contains(.failed(.b)), "a secondary effect never reports failure")
    }
}

/// Lockstep peers must run identical rules. A rules change that keeps the protocol version would let
/// an old and a new app battle each other and silently compute different battles.
final class BattleEngineVersionTests: XCTestCase {
    func testEngineRulesChangeOnlyTogetherWithTheProtocolVersion() throws {
        // No overkill moves: damage numbers must matter, or a rule change could leave the digest untouched.
        let pool = [tackle, protect, endure, rest, thunderWave, willOWisp, toxic, hypnosis, confuseRay,
                    move("reversal", type: "fighting", power: nil), move("seismic-toss", type: "fighting", power: nil),
                    move("heavy-slam", type: "steel", power: nil), move("super-fang", power: nil),
                    move("bite", type: "dark", power: 60, flinchChance: 30),
                    move("body-slam", power: 85, category: "damage-ailment", ailment: "paralysis", ailmentChance: 30),
                    move("psychic", type: "psychic", power: 90, damageClass: .special,
                         statChanges: [BattleStatChange(stat: "special-defense", change: -1)],
                         category: "damage-lower")]
        var setup = BattleRNG(seed: 20_260_926)
        func team(_ tag: String) -> [BattlePokemon] {
            (0..<6).map { i in
                mon("\(tag)\(i)", hp: 100 + setup.below(200), attack: 40 + setup.below(120), speed: 20 + setup.below(120),
                    level: 20 + setup.below(80), types: [["normal", "fire", "water", "ghost", "steel", "grass"][setup.below(6)]],
                    moves: (0..<4).map { _ in pool[setup.below(pool.count)] }, weight: 50 + setup.below(3_000))
            }
        }
        var state = try battle(team("a"), team("b"), seed: 99)
        var choices = BattleRNG(seed: 7)
        var turns = 0
        while turns < 2_000 {
            if case .finished = state.phase { break }
            for side in state.needsReplacement {
                _ = try state.replace(side, with: state.switchTargets(for: side)[0])
            }
            guard state.needsReplacement.isEmpty else { continue }
            let a = state.legalActions(for: .a).filter { $0 != .forfeit }
            let b = state.legalActions(for: .b).filter { $0 != .forfeit }
            _ = try state.resolveTurn(a[choices.below(a.count)], b[choices.below(b.count)])
            turns += 1
        }
        XCTAssertEqual(BattleWireMessage.protocolVersion, 3)
        XCTAssertEqual(state.digest, "ae68e64cf558898535d9ef2d", """
            The reference battle changed. If you changed engine rules on purpose, bump \
            BattleWireMessage.protocolVersion and update both expected values here.
            """)
    }
}
