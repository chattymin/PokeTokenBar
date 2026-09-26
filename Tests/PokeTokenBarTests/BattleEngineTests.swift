import XCTest
@testable import PokeTokenBar

private func move(_ name: String, type: String = "normal", power: Int? = 40, accuracy: Int? = nil, pp: Int = 10,
                  priority: Int = 0, damageClass: BattleDamageClass = .physical, target: String = "selected-pokemon",
                  statChanges: [BattleStatChange] = [], category: String? = "damage", statChance: Int = 0,
                  drain: Int = 0, healing: Int = 0) -> BattleMove {
    BattleMove(name: name, type: type, power: power, accuracy: accuracy, pp: pp, priority: priority,
               damageClass: damageClass, target: target, statChanges: statChanges, category: category,
               statChance: statChance, drain: drain, healing: healing)
}

private let tackle = move("tackle")
private let nuke = move("nuke", power: 250)
private let quickAttack = move("quick-attack", priority: 1)
private let growl = move("growl", power: nil, damageClass: .status, target: "all-opponents",
                         statChanges: [BattleStatChange(stat: "attack", change: -1)], category: "net-good-stats")
private let swordsDance = move("swords-dance", power: nil, damageClass: .status, target: "user",
                               statChanges: [BattleStatChange(stat: "attack", change: 2)], category: "net-good-stats")
private let recover = move("recover", power: nil, damageClass: .status, target: "user", category: "heal", healing: 50)
private let splash = move("metronome", power: nil, damageClass: .status, target: "user", category: "unique")

private func mon(_ id: String, hp: Int = 100, attack: Int = 50, defense: Int = 50, speed: Int = 50,
                 level: Int = 50, types: [String] = ["normal"], moves: [BattleMove] = [tackle]) -> BattlePokemon {
    BattlePokemon(instanceID: id, speciesID: 25, names: ["en": id], level: level, isShiny: false, unownForm: nil,
                  gender: nil, nature: nil, abilityName: nil, types: types,
                  stats: BattleStats(hp: hp, attack: attack, defense: defense, specialAttack: 50,
                                     specialDefense: 50, speed: speed),
                  moves: moves)
}

private func movers(_ events: [BattleEvent]) -> [BattleSide] {
    events.compactMap { event -> BattleSide? in
        if case .usedMove(let side, _) = event { return side }
        return nil
    }
}

private func battle(_ a: [BattlePokemon], _ b: [BattlePokemon], seed: UInt64 = 1) throws -> BattleState {
    BattleState(teamA: try BattleTeam(members: a), teamB: try BattleTeam(members: b), seed: seed)
}

final class BattleFormulaTests: XCTestCase {
    /// Bulbapedia's worked example: Lv. 75 Glaceon's Ice Fang against Garchomp does 168–196.
    func testDamageMatchesMainSeriesWorkedExample() {
        let effectiveness = BattleTypeChart.effectiveness(of: "ice", against: ["dragon", "ground"])
        XCTAssertEqual(effectiveness, 16)
        func roll(_ percent: Int) -> Int {
            BattleFormula.damage(level: 75, power: 65, attack: 123, defense: 163, critical: false,
                                 randomPercent: percent, stab: true, effectiveness: effectiveness)
        }
        XCTAssertEqual(roll(85), 168)
        XCTAssertEqual(roll(100), 196)
    }

    func testImmunityDealsNothingAndOtherHitsDealAtLeastOne() {
        XCTAssertEqual(BattleFormula.damage(level: 5, power: 40, attack: 5, defense: 999, critical: false,
                                            randomPercent: 85, stab: false, effectiveness: 0), 0)
        XCTAssertEqual(BattleFormula.damage(level: 5, power: 10, attack: 5, defense: 999, critical: false,
                                            randomPercent: 85, stab: false, effectiveness: 1), 1)
    }

    func testTypeChartCoversImmunityResistanceAndTypeless() {
        XCTAssertEqual(BattleTypeChart.effectiveness(of: "fire", against: ["grass"]), 8)
        XCTAssertEqual(BattleTypeChart.effectiveness(of: "electric", against: ["water", "ground"]), 0)
        XCTAssertEqual(BattleTypeChart.effectiveness(of: "normal", against: ["rock", "steel"]), 1)
        XCTAssertEqual(BattleTypeChart.effectiveness(of: "fire", against: ["water", "grass"]), 4)
        XCTAssertEqual(BattleTypeChart.effectiveness(of: "dragon", against: ["fairy"]), 0)
        XCTAssertEqual(BattleTypeChart.effectiveness(of: BattleTypeChart.typeless, against: ["ghost"]), 4)
    }

    func testStageMultipliers() {
        XCTAssertEqual(BattleFormula.stagedStat(100, stage: 2), 200)
        XCTAssertEqual(BattleFormula.stagedStat(100, stage: -1), 66)
        XCTAssertEqual(BattleFormula.stagedStat(100, stage: -6), 25)
        XCTAssertEqual(BattleFormula.hitChance(accuracy: 100, stage: -1), 75)
        XCTAssertEqual(BattleFormula.hitChance(accuracy: 100, stage: 1), 133)
        XCTAssertEqual(BattleFormula.criticalDenominator(stage: 0), 16)
        XCTAssertEqual(BattleFormula.criticalDenominator(stage: 9), 2)
    }
}

final class BattleEngineTests: XCTestCase {
    func testFasterPokemonMovesFirstAndPriorityBeatsSpeed() throws {
        var state = try battle([mon("slow", speed: 10, moves: [tackle, quickAttack])], [mon("fast", speed: 90)])
        var events = try state.resolveTurn(.move(0), .move(0))
        XCTAssertEqual(movers(events), [.b, .a])
        events = try state.resolveTurn(.move(1), .move(0))
        XCTAssertEqual(movers(events), [.a, .b], "priority +1 goes before a faster normal move")
    }

    func testSpeedTiesAreDecidedByTheSeed() throws {
        var firsts = Set<BattleSide>()
        for seed in 1...40 {
            var state = try battle([mon("x")], [mon("y")], seed: UInt64(seed))
            let events = try state.resolveTurn(.move(0), .move(0))
            if case .usedMove(let side, _) = events.first { firsts.insert(side) }
        }
        XCTAssertEqual(firsts, [.a, .b])
    }

    func testSwitchHappensBeforeTheOpponentsMoveAndTakesTheHit() throws {
        var state = try battle([mon("lead"), mon("bench")], [mon("foe", speed: 200)])
        let events = try state.resolveTurn(.switchTo(1), .move(0))
        XCTAssertEqual(events.prefix(2), [.withdrew(.a), .sentOut(.a, index: 1)])
        XCTAssertEqual(state[.a].active, 1)
        XCTAssertEqual(state[.a].team[0].hp, 100)
        XCTAssertLessThan(state[.a].team[1].hp, 100)
    }

    func testKnockoutAsksForReplacementThenLastKnockoutEndsTheBattle() throws {
        var state = try battle([mon("a1", speed: 90, moves: [nuke]), mon("a2", speed: 90, moves: [nuke])],
                               [mon("b1"), mon("b2")])
        var events = try state.resolveTurn(.move(0), .move(0))
        XCTAssertTrue(events.contains(.fainted(.b, index: 0)))
        XCTAssertFalse(events.contains { if case .usedMove(.b, _) = $0 { return true } else { return false } },
                       "a fainted Pokémon does not get to move")
        XCTAssertEqual(state.phase, .replacing([.b]))
        XCTAssertEqual(state.legalActions(for: .a), [], "no turn can start while a side must replace")
        XCTAssertThrowsError(try state.replace(.b, with: 0)) { XCTAssertEqual($0 as? BattleEngineError, .illegalAction(.b)) }
        XCTAssertThrowsError(try state.replace(.a, with: 1)) { XCTAssertEqual($0 as? BattleEngineError, .wrongPhase) }
        XCTAssertEqual(try state.replace(.b, with: 1), [.sentOut(.b, index: 1)])
        XCTAssertEqual(state.phase, .choosing)

        events = try state.resolveTurn(.move(0), .move(0))
        XCTAssertEqual(events.last, .ended(winner: .a))
        XCTAssertEqual(state.phase, .finished(winner: .a))
        XCTAssertThrowsError(try state.resolveTurn(.move(0), .move(0))) {
            XCTAssertEqual($0 as? BattleEngineError, .wrongPhase)
        }
    }

    func testIllegalActionsAreRejected() throws {
        var state = try battle([mon("a", moves: [tackle, splash]), mon("a2")], [mon("b")])
        XCTAssertEqual(state.legalActions(for: .a), [.move(0), .switchTo(1), .forfeit])
        for action in [BattleAction.move(1), .move(7), .struggle, .switchTo(0), .switchTo(5)] {
            XCTAssertThrowsError(try state.resolveTurn(action, .move(0)), "\(action)") {
                XCTAssertEqual($0 as? BattleEngineError, .illegalAction(.a))
            }
        }
        XCTAssertThrowsError(try state.resolveTurn(.move(0), .switchTo(0))) {
            XCTAssertEqual($0 as? BattleEngineError, .illegalAction(.b))
        }
    }

    func testStruggleOnlyWhenNothingElseIsUsableAndCostsRecoil() throws {
        var state = try battle([mon("a", hp: 200, speed: 90, moves: [move("once", pp: 1)])], [mon("b", hp: 999)])
        _ = try state.resolveTurn(.move(0), .move(0))
        XCTAssertEqual(state.legalActions(for: .a), [.struggle, .forfeit])
        let events = try state.resolveTurn(.struggle, .move(0))
        XCTAssertEqual(events.first, .noMovesLeft(.a))
        XCTAssertTrue(events.contains(.usedMove(.a, move: "struggle")))
        XCTAssertTrue(events.contains { if case .recoil(.a, 50, _) = $0 { return true } else { return false } },
                      "Struggle recoil is a quarter of max HP")

        let splashOnly = try battle([mon("a", moves: [splash])], [mon("b")])
        XCTAssertEqual(splashOnly.legalActions(for: .a), [.struggle, .forfeit],
                       "unsupported moves cannot be picked, so the Pokémon struggles")
    }

    func testStatMovesChangeStagesStopAtLimitsAndAffectDamage() throws {
        var state = try battle([mon("a", speed: 90, moves: [growl, swordsDance])], [mon("b", moves: [growl])])
        let events = try state.resolveTurn(.move(0), .move(0))
        XCTAssertTrue(events.contains(.statChanged(.b, stat: "attack", change: -1)))
        XCTAssertTrue(events.contains(.statChanged(.a, stat: "attack", change: -1)))
        for _ in 0..<3 { _ = try state.resolveTurn(.move(1), .move(0)) }
        XCTAssertEqual(state[.a].current.stages.attack, 2, "-1 from Growl each turn, +2 from Swords Dance")
        for _ in 0..<5 { _ = try state.resolveTurn(.move(0), .move(0)) }
        XCTAssertEqual(state[.b].current.stages.attack, -6)
        let atLimit = try state.resolveTurn(.move(0), .move(0))
        XCTAssertTrue(atLimit.contains(.statLimit(.b, stat: "attack", rising: false)))

        var boosted = try battle([mon("a", speed: 90, moves: [tackle, swordsDance])], [mon("b", hp: 999, moves: [splash])])
        var plain = boosted
        _ = try boosted.resolveTurn(.move(1), .struggle)
        _ = try plain.resolveTurn(.move(0), .struggle)
        let boostedHit = try boosted.resolveTurn(.move(0), .struggle)
        let plainHit = try plain.resolveTurn(.move(0), .struggle)
        func damageToB(_ events: [BattleEvent]) -> Int {
            events.compactMap { if case .damaged(.b, let amount, _, _, _) = $0 { return amount } else { return nil } }.first ?? 0
        }
        XCTAssertGreaterThan(damageToB(boostedHit), damageToB(plainHit))
    }

    func testSecondaryStatEffectsHitTheRightSide() throws {
        let overheat = move("overheat", type: "fire", power: 130, damageClass: .special,
                            statChanges: [BattleStatChange(stat: "special-attack", change: -2)],
                            category: "damage-raise", statChance: 100)
        let acid = move("acid-spray", type: "poison", power: 40, damageClass: .special,
                        statChanges: [BattleStatChange(stat: "special-defense", change: -2)],
                        category: "damage-lower", statChance: 100)
        var state = try battle([mon("a", speed: 90, moves: [overheat, acid])], [mon("b", hp: 999, moves: [splash])])
        var events = try state.resolveTurn(.move(0), .struggle)
        XCTAssertTrue(events.contains(.statChanged(.a, stat: "special-attack", change: -2)), "damage-raise changes the user")
        events = try state.resolveTurn(.move(1), .struggle)
        XCTAssertTrue(events.contains(.statChanged(.b, stat: "special-defense", change: -2)), "damage-lower changes the target")
    }

    func testEveryTrackedStatCanChangeAndUnknownStatsFail() throws {
        let all = ["attack", "defense", "special-attack", "special-defense", "speed", "accuracy", "evasion"]
        let dance = move("everything", power: nil, damageClass: .status, target: "user",
                         statChanges: all.map { BattleStatChange(stat: $0, change: 1) }, category: "net-good-stats")
        let unknown = move("future", power: nil, damageClass: .status, target: "user",
                           statChanges: [BattleStatChange(stat: "hp", change: 1)], category: "net-good-stats")
        var state = try battle([mon("a", speed: 90, moves: [dance, unknown])], [mon("b", hp: 999, moves: [splash])])
        let events = try state.resolveTurn(.move(0), .struggle)
        XCTAssertEqual(events.filter { if case .statChanged(.a, _, 1) = $0 { return true } else { return false } }.count, 7)
        XCTAssertEqual(all.map { state[.a].current.stages.value($0) }, Array(repeating: 1, count: 7))
        XCTAssertTrue(try state.resolveTurn(.move(1), .struggle).contains(.failed(.a)))
    }

    func testDrainAtFullHPHealsNothing() throws {
        let absorb = move("absorb", type: "grass", power: 20, damageClass: .special, drain: 50)
        var state = try battle([mon("a", speed: 90, moves: [absorb])], [mon("b", hp: 999, moves: [splash])])
        let events = try state.resolveTurn(.move(0), .struggle)
        XCTAssertFalse(events.contains { if case .healed = $0 { return true } else { return false } })
    }

    func testDrainHealsAndRecoilHurtsTheUser() throws {
        let absorb = move("absorb", type: "grass", power: 80, damageClass: .special, drain: 50)
        let doubleEdge = move("double-edge", power: 120, drain: -33)
        var state = try battle([mon("a", speed: 90, moves: [absorb, doubleEdge])], [mon("b", hp: 999)])
        _ = try state.resolveTurn(.move(1), .move(0))
        let hurt = state[.a].current.hp
        XCTAssertLessThan(hurt, 100)
        let events = try state.resolveTurn(.move(0), .move(0))
        XCTAssertTrue(events.contains { if case .healed(.a, _, _) = $0 { return true } else { return false } })
    }

    func testHealingFailsAtFullHP() throws {
        var state = try battle([mon("a", speed: 90, moves: [recover])], [mon("b", moves: [splash])])
        let events = try state.resolveTurn(.move(0), .struggle)
        XCTAssertTrue(events.contains(.failed(.a)))
    }

    func testImmuneTargetTakesNoDamage() throws {
        var state = try battle([mon("a", speed: 90)], [mon("ghost", types: ["ghost"], moves: [splash])])
        let events = try state.resolveTurn(.move(0), .struggle)
        XCTAssertTrue(events.contains(.noEffect(target: .b)))
        XCTAssertFalse(events.contains { if case .damaged(.b, _, _, _, _) = $0 { return true } else { return false } })
    }

    func testMissesAreReported() throws {
        var state = try battle([mon("a", speed: 90, moves: [move("wild", accuracy: 1)])], [mon("b", hp: 999)])
        let events = try state.resolveTurn(.move(0), .move(0))
        XCTAssertTrue(events.contains(.missed(.a)))
    }

    func testForfeitEndsTheBattleInAnyPhase() throws {
        var state = try battle([mon("a")], [mon("b")])
        XCTAssertEqual(try state.resolveTurn(.forfeit, .move(0)), [.forfeited(.a), .ended(winner: .b)])
        var both = try battle([mon("a")], [mon("b")])
        XCTAssertEqual(try both.resolveTurn(.forfeit, .forfeit), [.forfeited(.a), .forfeited(.b), .ended(winner: nil)])

        var replacing = try battle([mon("a", speed: 90, moves: [nuke])], [mon("b"), mon("b2")])
        _ = try replacing.resolveTurn(.move(0), .move(0))
        XCTAssertEqual(replacing.forfeit(.b), [.forfeited(.b), .ended(winner: .a)])
        XCTAssertEqual(replacing.forfeit(.a), [], "a finished battle cannot be forfeited again")
    }

    func testBothLastPokemonFaintingIsADraw() throws {
        let doubleEdge = move("double-edge", power: 250, drain: -100)
        var state = try battle([mon("a", hp: 20, speed: 90, moves: [doubleEdge])], [mon("b", hp: 20)])
        let events = try state.resolveTurn(.move(0), .move(0))
        XCTAssertEqual(events.suffix(3), [.fainted(.b, index: 0), .fainted(.a, index: 0), .ended(winner: nil)])
    }

    /// Lockstep networking depends on this: two engines fed the same input must agree exactly,
    /// and a state that went through JSON must continue identically.
    func testSameSeedAndActionsReplayIdenticallyIncludingAfterCodableRoundTrip() throws {
        let pool = [tackle, quickAttack, growl, swordsDance, recover, nuke,
                    move("ember", type: "fire", power: 40, accuracy: 100, damageClass: .special),
                    move("psychic", type: "psychic", power: 90, accuracy: 100, damageClass: .special,
                         statChanges: [BattleStatChange(stat: "special-defense", change: -1)],
                         category: "damage-lower", statChance: 10),
                    BattleMove(name: "protect", type: "normal", power: nil, accuracy: nil, pp: 10, priority: 4,
                               damageClass: .status, target: "user", category: "unique"),
                    BattleMove(name: "rest", type: "psychic", power: nil, accuracy: nil, pp: 10, priority: 0,
                               damageClass: .status, target: "user", category: "unique"),
                    BattleMove(name: "toxic", type: "poison", power: nil, accuracy: 90, pp: 10, priority: 0,
                               damageClass: .status, target: "selected-pokemon", category: "ailment", ailment: "poison"),
                    BattleMove(name: "confuse-ray", type: "ghost", power: nil, accuracy: 100, pp: 10, priority: 0,
                               damageClass: .status, target: "selected-pokemon", category: "ailment", ailment: "confusion"),
                    BattleMove(name: "body-slam", type: "normal", power: 85, accuracy: 100, pp: 15, priority: 0,
                               damageClass: .physical, target: "selected-pokemon", category: "damage-ailment",
                               ailment: "paralysis", ailmentChance: 30, flinchChance: 10),
                    move("reversal", type: "fighting", power: nil), move("seismic-toss", type: "fighting", power: nil)]
            + ["u-turn", "fury-swipes", "hyper-beam", "solar-beam", "fly", "outrage", "rollout", "bide", "future-sight",
               "explosion", "jump-kick", "fake-out", "sucker-punch", "pursuit", "counter", "dragon-tail", "rapid-spin"]
                .map { name -> BattleMove in
                    BattleMove(name: name, type: "normal", power: name == "bide" || name == "counter" ? nil : 60,
                               accuracy: 90, pp: 10, priority: name == "counter" ? -5 : 0, damageClass: .physical,
                               target: "selected-pokemon", category: "damage",
                               minHits: name == "fury-swipes" ? 2 : nil, maxHits: name == "fury-swipes" ? 5 : nil)
                }
            + ["reflect", "rain-dance", "spikes", "stealth-rock", "taunt", "encore", "leech-seed", "yawn", "baton-pass",
               "roar", "trick-room", "transform", "perish-song", "substitute-x", "wish", "haze", "focus-energy", "curse",
               "mean-look", "copycat", "sleep-talk", "magic-coat"]
                .map { name -> BattleMove in
                    let target = ["reflect", "baton-pass", "focus-energy", "wish", "magic-coat", "sleep-talk", "copycat"]
                        .contains(name) ? "user" : ["rain-dance", "trick-room", "haze", "perish-song"].contains(name)
                        ? "entire-field" : ["spikes", "stealth-rock"].contains(name) ? "opponents-field" : "selected-pokemon"
                    return BattleMove(name: name, type: "normal", power: nil, accuracy: nil, pp: 10,
                                      priority: name == "roar" ? -6 : name == "magic-coat" ? 4 : 0, damageClass: .status,
                                      target: target, category: "unique")
                }
        let typePool = ["normal", "fire", "water", "grass", "ghost", "psychic", "steel", "fairy"]
        for seed in UInt64(1)...200 {
            var setup = BattleRNG(seed: seed &* 7919)
            func team(_ tag: String) -> [BattlePokemon] {
                (0..<(1 + setup.below(6))).map { i in
                    mon("\(tag)\(i)", hp: 40 + setup.below(200), attack: 20 + setup.below(150),
                        defense: 20 + setup.below(150), speed: 10 + setup.below(150), level: 5 + setup.below(96),
                        types: [typePool[setup.below(typePool.count)]],
                        moves: (0..<(1 + setup.below(4))).map { _ in pool[setup.below(pool.count)] })
                }
            }
            let a = team("a"), b = team("b")
            var first = try battle(a, b, seed: seed)
            var second = try battle(a, b, seed: seed)
            var choices = BattleRNG(seed: seed ^ 0xC0FFEE)
            var turns = 0
            while turns < 5000 {
                if case .finished = first.phase { break }
                if !first.needsReplacement.isEmpty {
                    for side in first.needsReplacement {
                        let pick = first.switchTargets(for: side)[choices.below(first.switchTargets(for: side).count)]
                        XCTAssertEqual(try first.replace(side, with: pick), try second.replace(side, with: pick))
                    }
                    continue
                }
                func pick(_ side: BattleSide) -> BattleAction {
                    let legal = first.legalActions(for: side).filter { $0 != .forfeit }
                    return legal[choices.below(legal.count)]
                }
                let actionA = pick(.a), actionB = pick(.b)
                XCTAssertEqual(try first.resolveTurn(actionA, actionB), try second.resolveTurn(actionA, actionB))
                if turns == 3 {
                    second = try JSONDecoder().decode(BattleState.self, from: try JSONEncoder().encode(second))
                }
                turns += 1
            }
            XCTAssertEqual(first, second, "seed \(seed)")
            guard case .finished = first.phase else { return XCTFail("seed \(seed) did not finish in 5000 turns") }
        }
    }
}
