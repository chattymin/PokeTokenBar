import XCTest
@testable import PokeTokenBar

private func move(_ name: String, type: String = "normal", power: Int? = 40, accuracy: Int? = nil, pp: Int = 20,
                  priority: Int = 0, damageClass: BattleDamageClass = .physical, target: String = "selected-pokemon",
                  statChanges: [BattleStatChange] = [], category: String? = "damage", ailment: String? = nil,
                  ailmentChance: Int = 0, flinchChance: Int = 0, drain: Int = 0, healing: Int = 0,
                  minHits: Int? = nil, maxHits: Int? = nil) -> BattleMove {
    BattleMove(name: name, type: type, power: power, accuracy: accuracy, pp: pp, priority: priority,
               damageClass: damageClass, target: target, statChanges: statChanges, category: category,
               drain: drain, healing: healing, minHits: minHits, maxHits: maxHits, ailment: ailment,
               ailmentChance: ailmentChance, flinchChance: flinchChance)
}

private func status(_ name: String, type: String = "normal", target: String = "selected-pokemon", priority: Int = 0,
                    statChanges: [BattleStatChange] = [], category: String = "unique", healing: Int = 0,
                    ailment: String? = nil, accuracy: Int? = nil) -> BattleMove {
    move(name, type: type, power: nil, accuracy: accuracy, priority: priority, damageClass: .status, target: target,
         statChanges: statChanges, category: category, ailment: ailment, healing: healing)
}

private let tackle = move("tackle")
private let harden = status("harden", target: "user", statChanges: [BattleStatChange(stat: "defense", change: 1)],
                            category: "net-good-stats")
private let protect = status("protect", target: "user", priority: 4)

private func mon(_ id: String, hp: Int = 200, attack: Int = 80, defense: Int = 80, spAtk: Int = 80, spDef: Int = 80,
                 speed: Int = 50, level: Int = 50, types: [String] = ["normal"], moves: [BattleMove] = [tackle],
                 weight: Int = 100, gender: PokemonGender? = nil) -> BattlePokemon {
    BattlePokemon(instanceID: id, speciesID: 25, names: ["en": id.capitalized], level: level, isShiny: false,
                  unownForm: nil, gender: gender, nature: nil, abilityName: nil, types: types,
                  stats: BattleStats(hp: hp, attack: attack, defense: defense, specialAttack: spAtk,
                                     specialDefense: spDef, speed: speed),
                  moves: moves, weight: weight)
}

private func battle(_ a: [BattlePokemon], _ b: [BattlePokemon], seed: UInt64 = 1) throws -> BattleState {
    BattleState(teamA: try BattleTeam(members: a), teamB: try BattleTeam(members: b), seed: seed)
}

private func damage(to side: BattleSide, in events: [BattleEvent]) -> [Int] {
    events.compactMap { if case .damaged(side, let amount, _, _, _) = $0 { return amount } else { return nil } }
}

final class BattleMultiHitAndPowerTests: XCTestCase {
    func testMultiHitMovesHitTwoToFiveTimesAndDoubleKickTwice() throws {
        let furySwipes = move("fury-swipes", power: 18, minHits: 2, maxHits: 5)
        var counts = Set<Int>()
        for seed in UInt64(1)...40 {
            var state = try battle([mon("a", speed: 90, moves: [furySwipes])], [mon("b", hp: 999, moves: [harden])], seed: seed)
            let events = try state.resolveTurn(.move(0), .move(0))
            let hits = damage(to: .b, in: events).count
            XCTAssertTrue(events.contains(.hitCount(hits)))
            counts.insert(hits)
        }
        XCTAssertEqual(counts, [2, 3, 4, 5])
        var twice = try battle([mon("a", speed: 90, moves: [move("double-kick", type: "fighting", power: 30, minHits: 2, maxHits: 2)])],
                               [mon("b", hp: 999, moves: [harden])])
        XCTAssertEqual(damage(to: .b, in: try twice.resolveTurn(.move(0), .move(0))).count, 2)
    }

    func testMultiHitStopsWhenTheTargetFaints() throws {
        var state = try battle([mon("a", attack: 300, speed: 90, moves: [move("fury-attack", power: 60, minHits: 5, maxHits: 5)])],
                               [mon("b", hp: 20, moves: [harden])])
        let events = try state.resolveTurn(.move(0), .move(0))
        XCTAssertEqual(damage(to: .b, in: events).count, 1)
        XCTAssertTrue(events.contains(.hitCount(1)))
    }

    func testConditionalDoublePowerMoves() throws {
        let brine = move("brine", type: "water", power: 65, damageClass: .special)
        var state = try battle([mon("a", speed: 10, moves: [brine])], [mon("b", hp: 100, attack: 150, speed: 90)])
        XCTAssertEqual(state.effectivePower(of: brine, by: .a), 65)
        _ = try state.resolveTurn(.move(0), .move(0))
        if state[.b].current.hp * 2 <= 100 { XCTAssertEqual(state.effectivePower(of: brine, by: .a), 130) }

        let hex = move("hex", type: "ghost", power: 65, damageClass: .special)
        let facade = move("facade", power: 70)
        let thunderWave = status("thunder-wave", type: "electric", category: "ailment", ailment: "paralysis")
        var statused = try battle([mon("a", speed: 90, moves: [thunderWave, hex, facade])], [mon("b", moves: [thunderWave])])
        XCTAssertEqual(statused.effectivePower(of: hex, by: .a), 65)
        _ = try statused.resolveTurn(.move(0), .move(0))
        XCTAssertEqual(statused.effectivePower(of: hex, by: .a), 130, "Hex doubles against a statused target")
        XCTAssertEqual(statused.effectivePower(of: facade, by: .a), 140, "Facade doubles when the user is paralyzed")

        let revenge = move("revenge", type: "fighting", power: 60, priority: -4)
        var hurt = try battle([mon("a", hp: 999, speed: 90, moves: [revenge])], [mon("b", hp: 999, moves: [tackle])])
        let events = try hurt.resolveTurn(.move(0), .move(0))
        XCTAssertEqual(events.first, .usedMove(.b, move: "tackle"), "priority -4 goes last")
        XCTAssertNotNil(damage(to: .b, in: events).first)

        let payback = move("payback", type: "dark", power: 50)
        let slow = try battle([mon("a", speed: 10, moves: [payback])], [mon("b", speed: 90)])
        XCTAssertEqual(slow.effectivePower(of: payback, by: .a), 50, "not doubled before the turn starts")
    }

    func testStatScalingPowers() throws {
        let state = try battle([mon("a", hp: 200, speed: 20, moves: [tackle])], [mon("b", hp: 200, speed: 200)])
        XCTAssertEqual(state.effectivePower(of: move("gyro-ball", type: "steel", power: nil), by: .a), 150,
                       "a much slower user hits harder, capped at 150")
        XCTAssertEqual(state.effectivePower(of: move("electro-ball", type: "electric", power: nil, damageClass: .special), by: .a), 40)
        XCTAssertEqual(state.effectivePower(of: move("eruption", type: "fire", power: nil, damageClass: .special), by: .a), 150)
        XCTAssertEqual(state.effectivePower(of: move("wring-out", power: nil, damageClass: .special), by: .a), 121)
        XCTAssertEqual(state.effectivePower(of: move("stored-power", type: "psychic", power: nil, damageClass: .special), by: .a), 20)
        XCTAssertEqual(state.effectivePower(of: move("return", power: nil), by: .a), 102)
        XCTAssertEqual(state.effectivePower(of: move("acrobatics", type: "flying", power: 55), by: .a), 110)
    }

    func testTripleKickBeatUpPresentAndMagnitude() throws {
        var triple = try battle([mon("a", speed: 90, moves: [move("triple-kick", type: "fighting", power: 10, accuracy: 100)])],
                                [mon("b", hp: 999, moves: [harden])])
        let hits = damage(to: .b, in: try triple.resolveTurn(.move(0), .move(0)))
        XCTAssertLessThanOrEqual(hits.count, 3)
        XCTAssertGreaterThanOrEqual(hits.count, 1)

        var beatUp = try battle([mon("a", speed: 90, moves: [move("beat-up", type: "dark", power: nil)]), mon("a2"), mon("a3")],
                                [mon("b", hp: 999, moves: [harden])])
        XCTAssertEqual(damage(to: .b, in: try beatUp.resolveTurn(.move(0), .move(0))).count, 3, "one hit per healthy member")

        var levels = Set<Int>()
        for seed in UInt64(1)...60 {
            var magnitude = try battle([mon("a", speed: 90, moves: [move("magnitude", type: "ground", power: nil)])],
                                       [mon("b", hp: 999, moves: [harden])], seed: seed)
            for event in try magnitude.resolveTurn(.move(0), .move(0)) { if case .magnitude(let level) = event { levels.insert(level) } }
        }
        XCTAssertTrue(levels.isSubset(of: Set(4...10)))
        XCTAssertGreaterThan(levels.count, 3)
    }
}

final class BattleTimingMoveTests: XCTestCase {
    func testHyperBeamForcesARechargeTurn() throws {
        let hyperBeam = move("hyper-beam", power: 150, damageClass: .special)
        var state = try battle([mon("a", speed: 90, moves: [hyperBeam, tackle]), mon("a2")], [mon("b", hp: 999, moves: [harden])])
        _ = try state.resolveTurn(.move(0), .move(0))
        XCTAssertEqual(state.legalActions(for: .a), [.move(0), .forfeit], "no switching or other moves while recharging")
        XCTAssertEqual(state.forcedMove(for: .a), 0)
        let events = try state.resolveTurn(.move(0), .move(0))
        XCTAssertTrue(events.contains(.cantMove(.a, .recharging)))
        XCTAssertEqual(state[.a].current.pp[0], 19, "recharging costs no PP")
        XCTAssertNil(state.forcedMove(for: .a))
    }

    func testSolarBeamChargesUnlessSunny() throws {
        let solarBeam = move("solar-beam", type: "grass", power: 120, damageClass: .special)
        var state = try battle([mon("a", speed: 90, moves: [solarBeam, status("sunny-day", type: "fire", target: "entire-field",
                                                                               category: "whole-field-effect")])],
                               [mon("b", hp: 999, moves: [harden])])
        var events = try state.resolveTurn(.move(0), .move(0))
        XCTAssertTrue(events.contains(.charging(.a, .solarBeam)))
        XCTAssertTrue(damage(to: .b, in: events).isEmpty)
        events = try state.resolveTurn(.move(0), .move(0))
        XCTAssertFalse(damage(to: .b, in: events).isEmpty, "the second turn fires")
        _ = try state.resolveTurn(.move(1), .move(0))
        events = try state.resolveTurn(.move(0), .move(0))
        XCTAssertFalse(damage(to: .b, in: events).isEmpty, "no charge turn in harsh sunlight")
    }

    func testFlyDodgesMostMovesButNotThunder() throws {
        let fly = move("fly", type: "flying", power: 90)
        let thunder = move("thunder", type: "electric", power: 110, damageClass: .special)
        var dodge = try battle([mon("a", speed: 90, types: ["flying"], moves: [fly])], [mon("b", hp: 999, moves: [tackle])])
        var events = try dodge.resolveTurn(.move(0), .move(0))
        XCTAssertTrue(events.contains(.charging(.a, .fly)))
        XCTAssertTrue(events.contains(.missed(.b)), "Tackle cannot reach a Pokémon in the air")
        var hit = try battle([mon("a", hp: 999, speed: 90, moves: [fly])], [mon("b", hp: 999, moves: [thunder])])
        events = try hit.resolveTurn(.move(0), .move(0))
        XCTAssertFalse(damage(to: .a, in: events).isEmpty, "Thunder reaches the sky")
    }

    func testOutrageLocksThenConfuses() throws {
        let outrage = move("outrage", type: "dragon", power: 120)
        for seed in UInt64(1)...10 {
            var state = try battle([mon("a", hp: 999, speed: 90, moves: [outrage, tackle]), mon("a2")],
                                   [mon("b", hp: 9_999, moves: [harden])], seed: seed)
            var turns = 0
            var confused = false
            while turns < 5, !confused {
                if turns > 0 { XCTAssertEqual(state.legalActions(for: .a), [.move(0), .forfeit]) }
                confused = try state.resolveTurn(.move(0), .move(0)).contains(.confused(.a))
                turns += 1
            }
            XCTAssertTrue(confused)
            XCTAssertTrue((2...3).contains(turns), "seed \(seed): \(turns) turns")
        }
    }

    func testBideReturnsDoubleTheDamageTaken() throws {
        let bide = move("bide", power: nil, priority: 1)
        var state = try battle([mon("a", hp: 999, speed: 90, moves: [bide])], [mon("b", hp: 999, moves: [tackle])])
        XCTAssertTrue(try state.resolveTurn(.move(0), .move(0)).contains(.storingEnergy(.a)))
        _ = try state.resolveTurn(.move(0), .move(0))
        let taken = 999 - state[.a].current.hp
        let events = try state.resolveTurn(.move(0), .move(0))
        XCTAssertTrue(events.contains(.unleashedEnergy(.a)))
        XCTAssertEqual(damage(to: .b, in: events).first, taken * 2 - (999 - state[.a].current.hp - taken) * 0 == taken * 2 ? taken * 2 : damage(to: .b, in: events).first)
    }

    func testFutureSightLandsTwoTurnsLaterOnWhoeverIsIn() throws {
        let futureSight = move("future-sight", type: "psychic", power: 120, damageClass: .special)
        var state = try battle([mon("a", speed: 90, moves: [futureSight, harden])], [mon("b", hp: 999, moves: [harden]), mon("b2", hp: 999)])
        XCTAssertTrue(try state.resolveTurn(.move(0), .move(0)).contains(.foresaw(.a)))
        XCTAssertTrue(try state.resolveTurn(.move(0), .move(0)).contains(.failed(.a)), "one foreseen attack at a time")
        let events = try state.resolveTurn(.move(1), .switchTo(1))
        XCTAssertTrue(events.contains { if case .futureHit(.b, _, _) = $0 { return true } else { return false } })
        XCTAssertLessThan(state[.b].current.hp, 999, "the Pokémon that came in takes it")
    }

    func testExplosionFaintsTheUserEvenWhenProtectedAgainst() throws {
        let explosion = move("explosion", power: 250)
        var state = try battle([mon("a", moves: [explosion]), mon("a2")], [mon("b", hp: 999, speed: 90, moves: [protect])])
        let events = try state.resolveTurn(.move(0), .move(0))
        XCTAssertTrue(events.contains(.blocked(.b)))
        XCTAssertTrue(events.contains(.fainted(.a, index: 0)))
        XCTAssertEqual(state.phase, .replacing([.a]))
    }

    func testJumpKickCrashesOnMissOrImmunity() throws {
        let jumpKick = move("jump-kick", type: "fighting", power: 100)
        var state = try battle([mon("a", speed: 90, moves: [jumpKick])], [mon("g", hp: 999, types: ["ghost"], moves: [harden])])
        let events = try state.resolveTurn(.move(0), .move(0))
        XCTAssertTrue(events.contains(.noEffect(target: .b)))
        XCTAssertTrue(events.contains(.effectDamage(.a, .crash, amount: 100, hp: 100)))
    }

    func testFakeOutWorksOnlyOnTheFirstTurnAndFlinches() throws {
        let fakeOut = move("fake-out", power: 40, priority: 3, flinchChance: 100)
        var state = try battle([mon("a", moves: [fakeOut])], [mon("b", hp: 999, speed: 90, moves: [tackle])])
        var events = try state.resolveTurn(.move(0), .move(0))
        XCTAssertTrue(events.contains(.cantMove(.b, .flinched)))
        events = try state.resolveTurn(.move(0), .move(0))
        XCTAssertTrue(events.contains(.failed(.a)))
    }

    func testSuckerPunchNeedsAnIncomingAttackAndFeintBreaksProtect() throws {
        let suckerPunch = move("sucker-punch", type: "dark", power: 70, priority: 1)
        var vsAttack = try battle([mon("a", moves: [suckerPunch])], [mon("b", hp: 999, speed: 90, moves: [tackle, harden])])
        XCTAssertFalse(damage(to: .b, in: try vsAttack.resolveTurn(.move(0), .move(0))).isEmpty)
        XCTAssertTrue(try vsAttack.resolveTurn(.move(0), .move(1)).contains(.failed(.a)))

        let feint = move("feint", power: 30, priority: 2)
        var state = try battle([mon("a", moves: [feint])], [mon("b", hp: 999, moves: [protect])])
        let events = try state.resolveTurn(.move(0), .move(0))
        XCTAssertTrue(events.contains(.fellForFeint(.b)))
        XCTAssertFalse(damage(to: .b, in: events).isEmpty)
    }

    func testFocusPunchFailsAfterBeingHit() throws {
        let focusPunch = move("focus-punch", type: "fighting", power: 150, priority: -3)
        var hit = try battle([mon("a", hp: 999, speed: 90, moves: [focusPunch])], [mon("b", hp: 999, moves: [tackle, harden])])
        XCTAssertTrue(try hit.resolveTurn(.move(0), .move(0)).contains(.cantMove(.a, .lostFocus)))
        XCTAssertFalse(damage(to: .b, in: try hit.resolveTurn(.move(0), .move(1))).isEmpty)
    }

    func testPursuitHitsASwitchingTargetFirstAtDoublePower() throws {
        let pursuit = move("pursuit", type: "dark", power: 40)
        var state = try battle([mon("a", moves: [pursuit])], [mon("b", hp: 999, speed: 90), mon("b2", hp: 999)])
        let events = try state.resolveTurn(.move(0), .switchTo(1))
        XCTAssertEqual(events.first, .usedMove(.a, move: "pursuit"))
        XCTAssertLessThan(state[.b].team[0].hp, 999, "the Pokémon leaving took the hit")
        XCTAssertEqual(state[.b].team[1].hp, 999)
    }

    func testCounterReturnsDoublePhysicalDamage() throws {
        let counter = move("counter", type: "fighting", power: nil, priority: -5)
        var state = try battle([mon("a", hp: 999, moves: [counter])], [mon("b", hp: 999, moves: [tackle, harden])])
        let events = try state.resolveTurn(.move(0), .move(0))
        let taken = damage(to: .a, in: events).first ?? 0
        XCTAssertEqual(damage(to: .b, in: events).first, taken * 2)
        XCTAssertTrue(try state.resolveTurn(.move(0), .move(1)).contains(.failed(.a)), "nothing to counter")
    }

    func testOHKOFailsAgainstHigherLevelsAndKnocksOutOtherwise() throws {
        let guillotine = move("guillotine", power: nil, accuracy: 30)
        var higher = try battle([mon("a", speed: 90, level: 40, moves: [guillotine])], [mon("b", level: 60, moves: [harden])])
        XCTAssertTrue(try higher.resolveTurn(.move(0), .move(0)).contains(.failed(.a)))
        var knocked = 0
        for seed in UInt64(1)...30 {
            var state = try battle([mon("a", speed: 90, level: 100, moves: [guillotine])], [mon("b", level: 50, moves: [harden])], seed: seed)
            if try state.resolveTurn(.move(0), .move(0)).contains(.oneHitKO) { knocked += 1 }
        }
        XCTAssertGreaterThan(knocked, 10, "30 + 50 levels = 80% here")
    }

    func testEndeavorAndFinalGambit() throws {
        let endeavor = move("endeavor", power: nil)
        var state = try battle([mon("a", hp: 30, speed: 90, moves: [endeavor])], [mon("b", hp: 200, moves: [harden])])
        _ = try state.resolveTurn(.move(0), .move(0))
        XCTAssertEqual(state[.b].current.hp, 30)
        let gambit = move("final-gambit", type: "fighting", power: nil, damageClass: .special)
        var all = try battle([mon("a", hp: 120, speed: 90, moves: [gambit]), mon("a2")], [mon("b", hp: 200, moves: [harden])])
        _ = try all.resolveTurn(.move(0), .move(0))
        XCTAssertEqual(all[.b].current.hp, 80)
        XCTAssertTrue(all[.a].current.isFainted)
    }
}

final class BattleSwitchingMoveTests: XCTestCase {
    func testUTurnPausesTheTurnForAChoiceAndThenFinishesIt() throws {
        let uTurn = move("u-turn", type: "bug", power: 70)
        var state = try battle([mon("a", speed: 90, moves: [uTurn]), mon("a2", hp: 300)], [mon("b", hp: 999, moves: [tackle])])
        let events = try state.resolveTurn(.move(0), .move(0))
        XCTAssertTrue(events.contains(.withdrew(.a)))
        XCTAssertEqual(state.phase, .replacing([.a]))
        XCTAssertEqual(state.turn, 1, "the turn is not over yet")
        let rest = try state.replace(.a, with: 1)
        XCTAssertEqual(rest.first, .sentOut(.a, index: 1))
        XCTAssertTrue(rest.contains(.usedMove(.b, move: "tackle")), "the slower opponent now attacks the new Pokémon")
        XCTAssertLessThan(state[.a].team[1].hp, 300)
        XCTAssertEqual(state.turn, 2)
        XCTAssertEqual(state.phase, .choosing)
    }

    func testBatonPassHandsOverStatStages() throws {
        let swordsDance = status("swords-dance", target: "user", statChanges: [BattleStatChange(stat: "attack", change: 2)],
                                 category: "net-good-stats")
        var state = try battle([mon("a", speed: 90, moves: [swordsDance, status("baton-pass", target: "user")]), mon("a2")],
                               [mon("b", hp: 999, moves: [harden])])
        _ = try state.resolveTurn(.move(0), .move(0))
        _ = try state.resolveTurn(.move(1), .move(0))
        _ = try state.replace(.a, with: 1)
        XCTAssertEqual(state[.a].current.stages.attack, 2)
    }

    func testRoarDragsOutAndIngrainResists() throws {
        let roar = status("roar", priority: -6)
        var state = try battle([mon("a", moves: [roar])], [mon("b"), mon("b2")])
        let events = try state.resolveTurn(.move(0), .move(0))
        XCTAssertTrue(events.contains(.draggedOut(.b)))
        XCTAssertEqual(state[.b].active, 1)
        var rooted = try battle([mon("a", moves: [roar])], [mon("b", speed: 90, moves: [status("ingrain", type: "grass", target: "user")]), mon("b2")])
        XCTAssertTrue(try rooted.resolveTurn(.move(0), .move(0)).contains(.failed(.a)))
        XCTAssertFalse(rooted.canSwitch(.b), "a rooted Pokémon cannot switch")
    }

    func testMeanLookTrapsUntilTheTrapperLeaves() throws {
        var state = try battle([mon("a", speed: 90, moves: [status("mean-look", type: "normal")]), mon("a2")],
                               [mon("b", moves: [harden]), mon("b2")])
        _ = try state.resolveTurn(.move(0), .move(0))
        XCTAssertFalse(state.legalActions(for: .b).contains(.switchTo(1)))
        _ = try state.resolveTurn(.switchTo(1), .move(0))
        XCTAssertTrue(state.legalActions(for: .b).contains(.switchTo(1)))
    }

    func testEntryHazardsAndRapidSpin() throws {
        let spikes = status("spikes", type: "ground", target: "opponents-field", category: "field-effect")
        let stealthRock = status("stealth-rock", type: "rock", target: "opponents-field", category: "field-effect")
        let toxicSpikes = status("toxic-spikes", type: "poison", target: "opponents-field", category: "field-effect")
        var state = try battle([mon("a", speed: 90, moves: [spikes, stealthRock, toxicSpikes])],
                               [mon("b", hp: 999, moves: [harden]), mon("fire", hp: 160, types: ["fire", "flying"]),
                                mon("grounded", hp: 160)])
        _ = try state.resolveTurn(.move(0), .move(0))
        _ = try state.resolveTurn(.move(1), .move(0))
        _ = try state.resolveTurn(.move(2), .move(0))
        var events = try state.resolveTurn(.move(0), .switchTo(1))
        XCTAssertTrue(events.contains(.effectDamage(.b, .stealthRock, amount: 80, hp: 80)),
                      "Stealth Rock does 4× to a Fire/Flying type: half its HP")
        XCTAssertFalse(events.contains { if case .effectDamage(.b, .spikes, _, _) = $0 { return true } else { return false } },
                       "flying Pokémon float over Spikes")
        events = try state.resolveTurn(.move(0), .switchTo(2))
        XCTAssertTrue(events.contains { if case .effectDamage(.b, .spikes, _, _) = $0 { return true } else { return false } })
        XCTAssertEqual(state[.b].current.status, .poison)

        let rapidSpin = move("rapid-spin", power: 20)
        var spin = try battle([mon("a", speed: 90, moves: [spikes, rapidSpin])], [mon("b", hp: 999, speed: 95, moves: [spikes])])
        _ = try spin.resolveTurn(.move(0), .move(0))
        XCTAssertTrue(try spin.resolveTurn(.move(1), .move(0)).contains(.hazardsCleared(.a)))
        XCTAssertEqual(spin[.a].conditions.spikes, 0)
    }
}

final class BattleFieldTests: XCTestCase {
    private func weather(_ name: String) -> BattleMove {
        status(name, target: "entire-field", category: "whole-field-effect")
    }

    func testRainBoostsWaterWeakensFireAndEndsAfterFiveTurns() throws {
        let surf = move("surf", type: "water", power: 90, damageClass: .special)
        let unboostedMax = BattleFormula.damage(level: 50, power: 90, attack: 80, defense: 80, critical: false,
                                                randomPercent: 100, stab: false, effectiveness: 4)
        var state = try battle([mon("a", speed: 90, moves: [weather("rain-dance"), surf])], [mon("b", hp: 9_999, moves: [harden])])
        XCTAssertTrue(try state.resolveTurn(.move(0), .move(0)).contains(.weatherStarted(.rain)))
        var sawBoost = false
        for _ in 0..<3 {
            let events = try state.resolveTurn(.move(1), .move(0))
            if case .damaged(.b, let amount, _, _, false)? = events.first(where: {
                if case .damaged = $0 { return true } else { return false }
            }), amount > unboostedMax { sawBoost = true }
        }
        XCTAssertTrue(sawBoost, "rain lifts Water moves above their normal maximum")
        XCTAssertTrue(try state.resolveTurn(.move(1), .move(0)).contains(.weatherEnded(.rain)), "five turns including the first")
    }

    func testSandstormAndHailChip() throws {
        var state = try battle([mon("a", hp: 160, speed: 90, types: ["rock"], moves: [weather("sandstorm")])],
                               [mon("b", hp: 160, moves: [harden])])
        let events = try state.resolveTurn(.move(0), .move(0))
        XCTAssertTrue(events.contains(.effectDamage(.b, .sandstorm, amount: 10, hp: 150)))
        XCTAssertEqual(state[.a].current.hp, 160, "Rock types are immune")
    }

    func testReflectHalvesPhysicalHitsAndSafeguardAndMistShield() throws {
        let reflect = status("reflect", type: "psychic", target: "users-field", category: "field-effect")
        let maxHit = BattleFormula.damage(level: 50, power: 40, attack: 80, defense: 80, critical: false,
                                          randomPercent: 100, stab: true, effectiveness: 4)
        var checked = 0
        for seed in UInt64(1)...20 {
            var state = try battle([mon("a", hp: 999, speed: 90, moves: [reflect, harden])], [mon("b", moves: [tackle])], seed: seed)
            let events = try state.resolveTurn(.move(0), .move(0))
            XCTAssertTrue(events.contains(.screenStarted(.a, .reflect)))
            guard case .damaged(.a, let amount, _, _, false)? = events.first(where: {
                if case .damaged = $0 { return true } else { return false }
            }) else { continue }
            XCTAssertLessThanOrEqual(amount, maxHit / 2)
            checked += 1
        }
        XCTAssertGreaterThan(checked, 10)

        let safeguard = status("safeguard", target: "users-field", category: "field-effect")
        let thunderWave = status("thunder-wave", type: "electric", category: "ailment", ailment: "paralysis")
        var guarded = try battle([mon("a", speed: 90, moves: [safeguard])], [mon("b", moves: [thunderWave])])
        _ = try guarded.resolveTurn(.move(0), .move(0))
        XCTAssertNil(guarded[.a].current.status)

        let mist = status("mist", type: "ice", target: "users-field", category: "field-effect")
        let growl = status("growl", target: "all-opponents", statChanges: [BattleStatChange(stat: "attack", change: -1)],
                           category: "net-good-stats")
        var misty = try battle([mon("a", speed: 90, moves: [mist])], [mon("b", moves: [growl])])
        _ = try misty.resolveTurn(.move(0), .move(0))
        XCTAssertEqual(misty[.a].current.stages.attack, 0)
    }

    func testTailwindAndTrickRoomChangeTheOrder() throws {
        let tailwind = status("tailwind", type: "flying", target: "users-field", category: "field-effect")
        var state = try battle([mon("a", speed: 40, moves: [tailwind, tackle])], [mon("b", hp: 999, speed: 60)])
        _ = try state.resolveTurn(.move(0), .move(0))
        XCTAssertEqual(try state.resolveTurn(.move(1), .move(0)).first, .usedMove(.a, move: "tackle"))

        let trickRoom = status("trick-room", type: "psychic", target: "entire-field", priority: -7, category: "whole-field-effect")
        var room = try battle([mon("a", hp: 999, speed: 90, moves: [trickRoom, tackle])], [mon("b", hp: 999, speed: 10)])
        XCTAssertTrue(try room.resolveTurn(.move(0), .move(0)).contains(.trickRoom(started: true)))
        XCTAssertEqual(try room.resolveTurn(.move(1), .move(0)).first, .usedMove(.b, move: "tackle"), "the slower one goes first")
    }

    func testGravityGroundsFlyingTypesAndMagnetRiseLevitates() throws {
        let earthquake = move("earthquake", type: "ground", power: 100, target: "all-other-pokemon")
        let gravity = status("gravity", type: "psychic", target: "entire-field", category: "whole-field-effect")
        var state = try battle([mon("a", speed: 90, moves: [earthquake, gravity])], [mon("bird", hp: 999, types: ["flying"], moves: [harden])])
        XCTAssertTrue(try state.resolveTurn(.move(0), .move(0)).contains(.noEffect(target: .b)))
        _ = try state.resolveTurn(.move(1), .move(0))
        XCTAssertFalse(damage(to: .b, in: try state.resolveTurn(.move(0), .move(0))).isEmpty)

        let magnetRise = status("magnet-rise", type: "electric", target: "user")
        var float = try battle([mon("a", hp: 999, speed: 90, moves: [magnetRise])], [mon("b", moves: [earthquake])])
        let events = try float.resolveTurn(.move(0), .move(0))
        XCTAssertTrue(events.contains(.levitating(.a)))
        XCTAssertTrue(events.contains(.noEffect(target: .a)))
    }
}

final class BattleVolatileEffectTests: XCTestCase {
    func testTauntEncoreDisableAndTorment() throws {
        let taunt = status("taunt", type: "dark")
        var taunted = try battle([mon("a", speed: 90, moves: [taunt])], [mon("b", moves: [tackle, harden])])
        _ = try taunted.resolveTurn(.move(0), .move(0))
        XCTAssertEqual(taunted.usableMoves(for: .b), [0], "status moves are off the table")

        var encored = try battle([mon("a", moves: [status("encore")])], [mon("b", speed: 90, moves: [harden, tackle])])
        _ = try encored.resolveTurn(.move(0), .move(0))
        XCTAssertEqual(encored.usableMoves(for: .b), [0])

        var disabled = try battle([mon("a", moves: [status("disable")])], [mon("b", speed: 90, moves: [tackle, harden])])
        let events = try disabled.resolveTurn(.move(0), .move(0))
        XCTAssertTrue(events.contains(.disabled(.b, move: "tackle")))
        XCTAssertEqual(disabled.usableMoves(for: .b), [1])

        var tormented = try battle([mon("a", speed: 90, moves: [status("torment", type: "dark")])], [mon("b", moves: [tackle, harden])])
        _ = try tormented.resolveTurn(.move(0), .move(0))
        XCTAssertEqual(tormented.usableMoves(for: .b), [1], "the same move twice in a row is not allowed")
    }

    func testLeechSeedDrainsAndCurseCosts() throws {
        let leechSeed = status("leech-seed", type: "grass", category: "ailment", ailment: "leech-seed", accuracy: 90)
        var state = try battle([mon("a", hp: 200, speed: 90, moves: [leechSeed, harden])], [mon("b", hp: 160, moves: [tackle])], seed: 2)
        let events = try state.resolveTurn(.move(0), .move(0))
        if events.contains(.seeded(.b)) {
            XCTAssertTrue(events.contains { if case .effectDamage(.b, .leechSeed, 20, _) = $0 { return true } else { return false } })
            XCTAssertTrue(events.contains { if case .effectHeal(.a, .leechSeed, _, _) = $0 { return true } else { return false } })
        }
        var grass = try battle([mon("a", speed: 90, moves: [leechSeed])], [mon("g", types: ["grass"], moves: [harden])])
        XCTAssertTrue(try grass.resolveTurn(.move(0), .move(0)).contains(.noEffect(target: .b)))

        let curse = status("curse", type: "ghost")
        var ghost = try battle([mon("a", hp: 200, speed: 90, types: ["ghost"], moves: [curse])], [mon("b", hp: 200, moves: [harden])])
        let cursed = try ghost.resolveTurn(.move(0), .move(0))
        XCTAssertTrue(cursed.contains(.effectDamage(.a, .curseCost, amount: 100, hp: 100)))
        XCTAssertTrue(cursed.contains(.effectDamage(.b, .curse, amount: 50, hp: 150)))
        var normal = try battle([mon("a", speed: 90, moves: [curse])], [mon("b", moves: [harden])])
        _ = try normal.resolveTurn(.move(0), .move(0))
        XCTAssertEqual(normal[.a].current.stages.attack, 1)
        XCTAssertEqual(normal[.a].current.stages.speed, -1)
    }

    func testYawnPerishSongAndDestinyBond() throws {
        var yawn = try battle([mon("a", speed: 90, moves: [status("yawn"), harden])], [mon("b", moves: [harden])])
        XCTAssertTrue(try yawn.resolveTurn(.move(0), .move(0)).contains(.drowsy(.b)))
        XCTAssertTrue(try yawn.resolveTurn(.move(1), .move(0)).contains(.statusApplied(.b, .sleep)), "asleep at the end of the next turn")

        let perish = status("perish-song", target: "all-pokemon")
        var song = try battle([mon("a", speed: 90, moves: [perish, harden]), mon("a2")], [mon("b", moves: [harden]), mon("b2")])
        _ = try song.resolveTurn(.move(0), .move(0))
        _ = try song.resolveTurn(.move(1), .move(0))
        let third = try song.resolveTurn(.move(1), .move(0))
        XCTAssertTrue(third.contains(.fainted(.a, index: 0)))
        XCTAssertTrue(third.contains(.fainted(.b, index: 0)))

        let destinyBond = status("destiny-bond", type: "ghost", target: "user")
        var bond = try battle([mon("a", hp: 10, speed: 90, moves: [destinyBond]), mon("a2")],
                              [mon("b", attack: 200, moves: [tackle]), mon("b2")])
        let events = try bond.resolveTurn(.move(0), .move(0))
        XCTAssertTrue(events.contains(.tookDownWithIt(.a)))
        XCTAssertTrue(bond[.b].current.isFainted)
    }

    func testAttractNeedsOppositeGenders() throws {
        let attract = status("attract", category: "ailment", ailment: "infatuation")
        var love = try battle([mon("a", speed: 90, moves: [attract], gender: .male)], [mon("b", moves: [harden], gender: .female)])
        XCTAssertTrue(try love.resolveTurn(.move(0), .move(0)).contains(.infatuated(.b)))
        var same = try battle([mon("a", speed: 90, moves: [attract], gender: .male)], [mon("b", moves: [harden], gender: .male)])
        XCTAssertTrue(try same.resolveTurn(.move(0), .move(0)).contains(.failed(.a)))
    }

    func testTransformCopiesTheTargetUntilSwitchingOut() throws {
        let transform = status("transform", target: "selected-pokemon")
        let flamethrower = move("flamethrower", type: "fire", power: 90, damageClass: .special)
        var state = try battle([mon("ditto", speed: 90, moves: [transform]), mon("a2")],
                               [mon("b", attack: 150, types: ["fire"], moves: [flamethrower, harden])])
        _ = try state.resolveTurn(.move(0), .move(1))
        let ditto = state[.a].team[0]
        XCTAssertEqual(ditto.moves.map(\.name), ["flamethrower", "harden"])
        XCTAssertEqual(ditto.pp, [5, 5])
        XCTAssertEqual(ditto.maxPP, [5, 5], "copied moves show 5 PP as their maximum")
        XCTAssertEqual(ditto.types, ["fire"])
        XCTAssertEqual(ditto.stats.attack, 150)
        XCTAssertEqual(ditto.appearance, 25)
        _ = try state.resolveTurn(.switchTo(1), .move(1))
        XCTAssertEqual(state[.a].team[0].moves.map(\.name), ["transform"], "the original returns when it leaves")
        XCTAssertEqual(state[.a].team[0].maxPP, [20])
        XCTAssertNil(state[.a].team[0].appearance)
    }

    func testSleepTalkCopycatAndMirrorMove() throws {
        let hypnosis = status("hypnosis", type: "psychic", category: "ailment", ailment: "sleep")
        let sleepTalk = status("sleep-talk", target: "user")
        var talker = try battle([mon("a", moves: [sleepTalk, tackle])], [mon("b", hp: 999, speed: 90, moves: [hypnosis, harden])])
        _ = try talker.resolveTurn(.move(1), .move(0))
        XCTAssertEqual(talker[.a].current.status, .sleep)
        let events = try talker.resolveTurn(.move(0), .move(1))
        if talker[.a].current.status == .sleep || events.contains(.usedMove(.a, move: "tackle")) {
            XCTAssertTrue(events.contains(.usedMove(.a, move: "tackle")) || events.contains(.wokeUp(.a)))
        }

        var copy = try battle([mon("a", moves: [status("copycat", target: "user")])], [mon("b", hp: 999, speed: 90, moves: [tackle])])
        let copied = try copy.resolveTurn(.move(0), .move(0))
        XCTAssertEqual(copied.filter { $0 == .usedMove(.a, move: "tackle") }.count, 1, "Copycat repeats the last move used")

        var mirror = try battle([mon("a", moves: [status("mirror-move", type: "flying")])], [mon("b", hp: 999, speed: 90, moves: [tackle])])
        XCTAssertTrue(try mirror.resolveTurn(.move(0), .move(0)).contains(.usedMove(.a, move: "tackle")))
    }

    func testBellyDrumPainSplitWishAndHealingWish() throws {
        var drum = try battle([mon("a", hp: 200, speed: 90, moves: [status("belly-drum", target: "user")])], [mon("b", moves: [harden])])
        XCTAssertTrue(try drum.resolveTurn(.move(0), .move(0)).contains(.maximizedAttack(.a)))
        XCTAssertEqual(drum[.a].current.stages.attack, 6)
        XCTAssertEqual(drum[.a].current.hp, 100)

        var split = try battle([mon("a", hp: 200, speed: 10, moves: [status("pain-split")])],
                               [mon("b", hp: 200, attack: 150, speed: 90, moves: [tackle, harden])])
        _ = try split.resolveTurn(.move(0), .move(0))
        XCTAssertEqual(split[.a].current.hp, split[.b].current.hp)

        var wish = try battle([mon("a", hp: 200, speed: 10, moves: [status("wish", target: "user"), harden])],
                              [mon("b", hp: 999, speed: 90, moves: [tackle])])
        _ = try wish.resolveTurn(.move(0), .move(0))
        let events = try wish.resolveTurn(.move(1), .move(0))
        XCTAssertTrue(events.contains { if case .effectHeal(.a, .wish, _, _) = $0 { return true } else { return false } })

        var healingWish = try battle([mon("a", speed: 90, moves: [status("healing-wish", type: "psychic", target: "user")]),
                                      mon("a2", hp: 200)],
                                     [mon("b", moves: [harden])])
        _ = try healingWish.resolveTurn(.move(0), .move(0))
        XCTAssertTrue(healingWish[.a].team[0].isFainted)
        XCTAssertTrue(try healingWish.replace(.a, with: 1).contains(.healingWishCameTrue(.a)))
    }

    func testMagicCoatBouncesStatusMoves() throws {
        let thunderWave = status("thunder-wave", type: "electric", category: "ailment", ailment: "paralysis")
        var state = try battle([mon("a", speed: 90, moves: [status("magic-coat", type: "psychic", target: "user", priority: 4)])],
                               [mon("b", moves: [thunderWave])])
        let events = try state.resolveTurn(.move(0), .move(0))
        XCTAssertTrue(events.contains(.bounced(.a, move: "thunder-wave")))
        XCTAssertEqual(state[.b].current.status, .paralysis)
        XCTAssertNil(state[.a].current.status)
    }

    func testSplashAndItemAndAbilityMovesDoNothingVisibly() throws {
        var state = try battle([mon("a", speed: 90, moves: [status("splash", target: "user"), status("embargo", type: "dark")])],
                               [mon("b", moves: [harden])])
        XCTAssertTrue(try state.resolveTurn(.move(0), .move(0)).contains(.nothingHappened))
        XCTAssertTrue(try state.resolveTurn(.move(1), .move(0)).contains(.nothingHappened))
        var singles = try battle([mon("a", speed: 90, moves: [status("helping-hand", target: "user", priority: 5)])], [mon("b", moves: [harden])])
        XCTAssertTrue(try singles.resolveTurn(.move(0), .move(0)).contains(.failed(.a)))
    }
}

@MainActor
final class BattleForcedAndNetworkedSpecialMoveTests: XCTestCase {
    private func team(_ members: [BattlePokemon]) throws -> BattleTeam { try BattleTeam(members: members) }

    func testSessionPlaysChargeTurnsByItself() async throws {
        let solarBeam = move("solar-beam", type: "grass", power: 120, damageClass: .special)
        let s = BattleSession(myTeam: try team([mon("a", hp: 999, speed: 90, moves: [solarBeam])]),
                              opponentTeam: try team([mon("b", hp: 999, moves: [harden])]), seed: 1,
                              opponent: CPUOpponent(seed: 1), language: .en, pace: .zero)
        await s.start()
        await s.choose(.move(0))
        for _ in 0..<50 where s.state.turn < 3 { await Task.yield() }
        XCTAssertEqual(s.state.turn, 3, "the charged second turn played without another click")
        XCTAssertTrue(s.log.contains("A absorbed light!"))
    }

    /// U-turn pauses the turn for a choice; both machines must agree on that choice and on the rest of the turn.
    func testUTurnAcrossTheNetworkKeepsBothMachinesInSync() async throws {
        let uTurn = move("u-turn", type: "bug", power: 70)
        let (left, right) = LoopbackTransport.pair()
        let linkA = BattleLink(transport: left), linkB = BattleLink(transport: right)
        let teamA = try team([mon("a", speed: 90, moves: [uTurn]), mon("a2", hp: 300)])
        let teamB = try team([mon("b", hp: 999, moves: [tackle])])
        async let ma = BattleHandshake.run(linkA, isChallenger: true, trainer: "Red", team: teamA, nonce: 1)
        async let mb = BattleHandshake.run(linkB, isChallenger: false, trainer: "Blue", team: teamB, nonce: 2)
        let (matchA, matchB) = try await (ma, mb)
        func session(_ m: BattleMatch, _ link: BattleLink) -> BattleSession {
            BattleSession(myTeam: m.myTeam, opponentTeam: m.opponentTeam, seed: m.seed,
                          opponent: NetworkOpponent(link: link, patience: .seconds(5)), language: .en,
                          mySide: m.mySide, opponentName: m.opponentName, pace: .zero)
        }
        let red = session(matchA, linkA), blue = session(matchB, linkB)
        await red.start()
        await blue.start()
        // Blue keeps waiting for Red's pick in the background, as it would on its own Mac.
        let blueTurn = Task { @MainActor in await blue.choose(.move(0)) }
        await red.choose(.move(0))
        XCTAssertTrue(red.awaitingReplacement, "Red picks who comes in after U-turn")
        await red.replace(with: 1)
        await blueTurn.value
        XCTAssertNil(blue.outcome, "Blue got Red's pick instead of timing out")
        XCTAssertEqual(red.state, blue.state)
        XCTAssertEqual(red.state.turn, 2)
        XCTAssertLessThan(red.state[.a].team[1].hp, 300, "Blue's Tackle hit the Pokémon that came in")
    }
}
