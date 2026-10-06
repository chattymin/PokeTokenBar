import XCTest
@testable import PokeTokenBar

private func move(_ name: String, type: String = "normal", power: Int? = 40, accuracy: Int? = nil, pp: Int = 20,
                  priority: Int = 0, damageClass: BattleDamageClass = .physical, target: String = "selected-pokemon",
                  statChanges: [BattleStatChange] = [], category: String? = "damage", ailment: String? = nil,
                  healing: Int = 0, drain: Int = 0) -> BattleMove {
    BattleMove(name: name, type: type, power: power, accuracy: accuracy, pp: pp, priority: priority,
               damageClass: damageClass, target: target, statChanges: statChanges, category: category,
               drain: drain, healing: healing, ailment: ailment)
}

private func status(_ name: String, type: String = "normal", target: String = "selected-pokemon", priority: Int = 0,
                    statChanges: [BattleStatChange] = [], category: String = "unique", healing: Int = 0,
                    ailment: String? = nil) -> BattleMove {
    move(name, type: type, power: nil, priority: priority, damageClass: .status, target: target,
         statChanges: statChanges, category: category, ailment: ailment, healing: healing)
}

private let tackle = move("tackle")
private let harden = status("harden", target: "user", statChanges: [BattleStatChange(stat: "defense", change: 1)],
                            category: "net-good-stats")
private let hypnosis = status("hypnosis", type: "psychic", category: "ailment", ailment: "sleep")
private let thunderWave = status("thunder-wave", type: "electric", category: "ailment", ailment: "paralysis")

private func mon(_ id: String, hp: Int = 200, attack: Int = 80, defense: Int = 80, speed: Int = 50, level: Int = 50,
                 types: [String] = ["normal"], moves: [BattleMove] = [tackle], gender: PokemonGender? = nil) -> BattlePokemon {
    BattlePokemon(instanceID: id, speciesID: 25, names: ["en": id], level: level, isShiny: false, unownForm: nil,
                  gender: gender, nature: nil, abilityName: nil, types: types,
                  stats: BattleStats(hp: hp, attack: attack, defense: defense, specialAttack: 80, specialDefense: 80,
                                     speed: speed),
                  moves: moves)
}

private func battle(_ a: [BattlePokemon], _ b: [BattlePokemon], seed: UInt64 = 1) throws -> BattleState {
    BattleState(teamA: try BattleTeam(members: a), teamB: try BattleTeam(members: b), seed: seed)
}

private func contains(_ events: [BattleEvent], _ match: (BattleEvent) -> Bool) -> Bool { events.contains(where: match) }

final class BattlePowerEdgeCaseTests: XCTestCase {
    func testTrumpCardEchoedVoiceAndFuryCutterScale() throws {
        let trumpCard = move("trump-card", power: nil, pp: 5)
        var trump = try battle([mon("a", speed: 90, moves: [trumpCard])], [mon("b", hp: 9_999, moves: [harden])])
        XCTAssertEqual(trump.effectivePower(of: trumpCard, by: .a), 40)
        for _ in 0..<4 { _ = try trump.resolveTurn(.move(0), .move(0)) }
        XCTAssertEqual(trump.effectivePower(of: trumpCard, by: .a), 200, "the last PP hits hardest")

        let echoedVoice = move("echoed-voice", power: 40, damageClass: .special)
        var echo = try battle([mon("a", speed: 90, moves: [echoedVoice])], [mon("b", hp: 9_999, moves: [harden])])
        _ = try echo.resolveTurn(.move(0), .move(0))
        XCTAssertEqual(echo.effectivePower(of: echoedVoice, by: .a), 80, "it grows when used on consecutive turns")

        let furyCutter = move("fury-cutter", type: "bug", power: 40)
        var cutter = try battle([mon("a", speed: 90, moves: [furyCutter])], [mon("b", hp: 9_999, moves: [harden])])
        _ = try cutter.resolveTurn(.move(0), .move(0))
        XCTAssertEqual(cutter.effectivePower(of: furyCutter, by: .a), 80)
        _ = try cutter.resolveTurn(.move(0), .move(0))
        _ = try cutter.resolveTurn(.move(0), .move(0))
        XCTAssertEqual(cutter.effectivePower(of: furyCutter, by: .a), 160, "capped at 160")
    }

    func testWeatherBallPresentAndMetalBurst() throws {
        let weatherBall = move("weather-ball", power: 50, damageClass: .special)
        let sunnyDay = status("sunny-day", type: "fire", target: "entire-field", category: "whole-field-effect")
        var ball = try battle([mon("a", speed: 90, moves: [sunnyDay, weatherBall])],
                              [mon("b", hp: 9_999, types: ["grass"], moves: [harden])])
        _ = try ball.resolveTurn(.move(0), .move(0))
        XCTAssertEqual(ball.effectivePower(of: weatherBall, by: .a), 100)
        let events = try ball.resolveTurn(.move(1), .move(0))
        XCTAssertTrue(contains(events) { if case .damaged(.b, _, _, 8, _) = $0 { return true } else { return false } },
                      "in sun it turns Fire and hits Grass super effectively")

        var outcomes = Set<String>()
        for seed in UInt64(1)...40 {
            var present = try battle([mon("a", speed: 90, moves: [move("present", power: nil)])],
                                     [mon("b", hp: 9_999, moves: [move("nuke", power: 60)])], seed: seed)
            _ = try present.resolveTurn(.move(0), .move(0))
            let events = try present.resolveTurn(.move(0), .move(0))
            outcomes.insert(contains(events) { if case .healed(.b, _, _) = $0 { return true } else { return false } } ? "heal" : "hit")
        }
        XCTAssertEqual(outcomes, ["heal", "hit"])

        let metalBurst = move("metal-burst", type: "steel", power: nil, priority: -1)
        var burst = try battle([mon("a", hp: 999, moves: [metalBurst])], [mon("b", hp: 999, moves: [tackle])])
        let hit = try burst.resolveTurn(.move(0), .move(0))
        let taken = hit.compactMap { if case .damaged(.a, let amount, _, _, _) = $0 { return amount } else { return nil } }.first ?? 0
        XCTAssertTrue(contains(hit) { if case .damaged(.b, taken * 3 / 2, _, _, _) = $0 { return true } else { return false } })
    }

    func testStockpileSpitUpAndSwallow() throws {
        let stockpile = status("stockpile", target: "user")
        let spitUp = move("spit-up", power: nil, damageClass: .special)
        let swallow = status("swallow", target: "user")
        var state = try battle([mon("a", hp: 400, speed: 10, moves: [stockpile, spitUp, swallow])],
                               [mon("b", hp: 9_999, attack: 120, speed: 90, moves: [tackle])])
        XCTAssertTrue(try state.resolveTurn(.move(2), .move(0)).contains(.failed(.a)), "nothing stored to swallow")
        XCTAssertTrue(try state.resolveTurn(.move(0), .move(0)).contains(.stockpiled(.a, count: 1)))
        XCTAssertEqual(state[.a].current.stages.defense, 1)
        _ = try state.resolveTurn(.move(0), .move(0))
        XCTAssertEqual(state.effectivePower(of: spitUp, by: .a), 200)
        _ = try state.resolveTurn(.move(1), .move(0))
        XCTAssertEqual(state[.a].current.volatiles.stockpile, 0)
        XCTAssertEqual(state[.a].current.stages.defense, 0, "spitting up gives the Defense back")
        XCTAssertTrue(try state.resolveTurn(.move(1), .move(0)).contains(.failed(.a)))
        _ = try state.resolveTurn(.move(0), .move(0))
        XCTAssertTrue(contains(try state.resolveTurn(.move(2), .move(0))) { if case .healed(.a, _, _) = $0 { return true } else { return false } })
    }

    func testWakeUpSlapAndSmellingSaltsCureWhatTheyExploit() throws {
        let wakeUpSlap = move("wake-up-slap", type: "fighting", power: 70)
        var slap = try battle([mon("a", speed: 90, moves: [hypnosis, wakeUpSlap])], [mon("b", hp: 999, moves: [harden])], seed: 3)
        _ = try slap.resolveTurn(.move(0), .move(0))
        XCTAssertEqual(slap[.b].current.status, .sleep)
        XCTAssertEqual(slap.effectivePower(of: wakeUpSlap, by: .a), 140)
        XCTAssertTrue(try slap.resolveTurn(.move(1), .move(0)).contains(.wokeUp(.b)))

        let smellingSalts = move("smelling-salts", power: 70)
        var salts = try battle([mon("a", speed: 90, moves: [thunderWave, smellingSalts])], [mon("b", hp: 999, moves: [harden])])
        _ = try salts.resolveTurn(.move(0), .move(0))
        XCTAssertTrue(try salts.resolveTurn(.move(1), .move(0)).contains(.statusCured(.b)))
    }

    func testClearSmogSmackDownAndMultiHitRanges() throws {
        let swordsDance = status("swords-dance", target: "user", statChanges: [BattleStatChange(stat: "attack", change: 2)],
                                 category: "net-good-stats")
        var smog = try battle([mon("a", moves: [move("clear-smog", type: "poison", power: 50, damageClass: .special)])],
                              [mon("b", hp: 999, speed: 90, moves: [swordsDance])])
        let events = try smog.resolveTurn(.move(0), .move(0))
        XCTAssertTrue(events.contains(.stagesReset(.b)))
        XCTAssertEqual(smog[.b].current.stages.attack, 0)

        let earthquake = move("earthquake", type: "ground", power: 100)
        var smack = try battle([mon("a", speed: 90, moves: [move("smack-down", type: "rock", power: 50), earthquake])],
                               [mon("bird", hp: 999, types: ["flying"], moves: [harden])])
        XCTAssertTrue(try smack.resolveTurn(.move(0), .move(0)).contains(.fellDown(.b)))
        XCTAssertFalse(try smack.resolveTurn(.move(1), .move(0)).contains(.noEffect(target: .b)), "grounded flyers take Ground moves")

        let doubleHit = BattleMove(name: "arm-thrust-ish", type: "fighting", power: 15, accuracy: nil, pp: 20, priority: 0,
                                   damageClass: .physical, target: "selected-pokemon", minHits: 1, maxHits: 3)
        var counts = Set<Int>()
        for seed in UInt64(1)...30 {
            var state = try battle([mon("a", speed: 90, moves: [doubleHit])], [mon("b", hp: 999, moves: [harden])], seed: seed)
            for event in try state.resolveTurn(.move(0), .move(0)) { if case .hitCount(let count) = event { counts.insert(count) } }
        }
        XCTAssertEqual(counts, [1, 2, 3], "non 2–5 ranges are uniform")
    }
}

final class BattleStatusEdgeCaseTests: XCTestCase {
    func testUproarWakesAndKeepsEveryoneAwake() throws {
        let uproar = move("uproar", power: 90, damageClass: .special)
        var state = try battle([mon("a", hp: 999, speed: 10, moves: [uproar])], [mon("b", hp: 9_999, speed: 90, moves: [hypnosis, harden])],
                               seed: 4)
        _ = try state.resolveTurn(.move(0), .move(0))
        XCTAssertTrue(state[.a].current.status == .sleep || state.field.uproarTurns > 0)
        var fresh = try battle([mon("a", hp: 999, speed: 90, moves: [uproar])], [mon("b", hp: 9_999, moves: [hypnosis])])
        XCTAssertTrue(try fresh.resolveTurn(.move(0), .move(0)).contains(.uproar(.a, started: true)))
        XCTAssertTrue(try fresh.resolveTurn(.move(0), .move(0)).contains(.failed(.a)), "nobody falls asleep during an uproar")
    }

    func testInfatuationSometimesStopsTheMove() throws {
        let attract = status("attract", category: "ailment", ailment: "infatuation")
        var immobilized = 0
        for seed in UInt64(1)...20 {
            var state = try battle([mon("a", speed: 90, moves: [attract, harden], gender: .female)],
                                   [mon("b", hp: 999, moves: [tackle], gender: .male)], seed: seed)
            _ = try state.resolveTurn(.move(0), .move(0))
            if try state.resolveTurn(.move(1), .move(0)).contains(.cantMove(.b, .infatuated)) { immobilized += 1 }
        }
        XCTAssertGreaterThan(immobilized, 3)
        XCTAssertLessThan(immobilized, 17)
    }

    func testNightmareHurtsASleepingTarget() throws {
        var state = try battle([mon("a", speed: 90, moves: [hypnosis, status("nightmare", type: "ghost")])],
                               [mon("b", hp: 400, moves: [harden])], seed: 5)
        _ = try state.resolveTurn(.move(0), .move(0))
        let events = try state.resolveTurn(.move(1), .move(0))
        XCTAssertTrue(events.contains(.nightmareStarted(.b)))
        XCTAssertTrue(contains(events) { if case .effectDamage(.b, .nightmare, 100, _) = $0 { return true } else { return false } })
        var awake = try battle([mon("a", speed: 90, moves: [status("nightmare", type: "ghost")])], [mon("b", moves: [harden])])
        XCTAssertTrue(try awake.resolveTurn(.move(0), .move(0)).contains(.failed(.a)))
    }

    func testToxicSpikesAreAbsorbedByPoisonTypes() throws {
        let toxicSpikes = status("toxic-spikes", type: "poison", target: "opponents-field", category: "field-effect")
        var state = try battle([mon("a", speed: 90, moves: [toxicSpikes, harden])],
                               [mon("b", moves: [harden]), mon("poison", types: ["poison"])])
        _ = try state.resolveTurn(.move(0), .move(0))
        let events = try state.resolveTurn(.move(1), .switchTo(1))
        XCTAssertTrue(events.contains(.hazardsCleared(.b)))
        XCTAssertEqual(state[.b].conditions.toxicSpikes, 0)
        XCTAssertNil(state[.b].current.status)
    }

    func testRefreshHealBellWorrySeedAndMoonlight() throws {
        var refresh = try battle([mon("a", moves: [status("refresh", target: "user")])], [mon("b", speed: 90, moves: [thunderWave])])
        _ = try refresh.resolveTurn(.move(0), .move(0))
        XCTAssertNil(refresh[.a].current.status, "cured right after being paralyzed")
        var nothing = try battle([mon("a", speed: 90, moves: [status("refresh", target: "user")])], [mon("b", moves: [harden])])
        XCTAssertTrue(try nothing.resolveTurn(.move(0), .move(0)).contains(.failed(.a)))

        var bell = try battle([mon("a", moves: [status("heal-bell", target: "user")])], [mon("b", speed: 90, moves: [thunderWave])])
        XCTAssertTrue(try bell.resolveTurn(.move(0), .move(0)).contains(.teamCured(.a)))
        XCTAssertNil(bell[.a].current.status)

        var seed = try battle([mon("a", speed: 90, moves: [status("worry-seed", type: "grass"), hypnosis])], [mon("b", moves: [harden])])
        _ = try seed.resolveTurn(.move(0), .move(0))
        XCTAssertTrue(try seed.resolveTurn(.move(1), .move(0)).contains(.failed(.b)), "insomnia keeps it awake")

        let moonlight = status("moonlight", type: "fairy", target: "user", category: "heal", healing: 50)
        var night = try battle([mon("a", hp: 200, speed: 10, moves: [moonlight])],
                               [mon("b", attack: 200, speed: 90, moves: [move("nuke", power: 80)])])
        let healed = try night.resolveTurn(.move(0), .move(0))
        XCTAssertTrue(contains(healed) { if case .healed(.a, _, _) = $0 { return true } else { return false } })
    }

    func testHealBlockStopsHealingMovesAndWearsOff() throws {
        let recover = status("recover", target: "user", category: "heal", healing: 50)
        var state = try battle([mon("a", speed: 90, moves: [status("heal-block", type: "psychic"), harden])],
                               [mon("b", moves: [recover, tackle])])
        XCTAssertTrue(try state.resolveTurn(.move(0), .move(1)).contains(.healBlocked(.b)))
        XCTAssertEqual(state.usableMoves(for: .b), [1])
        var ended = false
        for _ in 0..<5 where !ended { ended = try state.resolveTurn(.move(1), .move(1)).contains(.healBlockEnded(.b)) }
        XCTAssertTrue(ended)
        XCTAssertEqual(state.usableMoves(for: .b), [0, 1])
    }
}

final class BattleUniqueEffectCoverageTests: XCTestCase {
    func testImprisonSealsSharedMoves() throws {
        var state = try battle([mon("a", speed: 90, moves: [status("imprison", type: "psychic", target: "user"), tackle])],
                               [mon("b", moves: [tackle, harden])])
        XCTAssertTrue(try state.resolveTurn(.move(0), .move(1)).contains(.imprisoning(.a)))
        XCTAssertEqual(state.usableMoves(for: .b), [1])
        XCTAssertTrue(try state.resolveTurn(.move(0), .move(1)).contains(.failed(.a)))
    }

    func testDisableCancelsTheMoveAboutToBeUsed() throws {
        var state = try battle([mon("a", speed: 90, moves: [tackle, status("disable")])], [mon("b", hp: 999, moves: [tackle, harden])])
        _ = try state.resolveTurn(.move(0), .move(0))
        let events = try state.resolveTurn(.move(1), .move(0))
        XCTAssertTrue(events.contains(.disabled(.b, move: "tackle")))
        XCTAssertFalse(events.contains(.usedMove(.b, move: "tackle")), "the disabled move chosen this turn does not happen")
        var ended = false
        for _ in 0..<5 where !ended { ended = try state.resolveTurn(.move(0), .move(1)).contains(.disableEnded(.b)) }
        XCTAssertTrue(ended)
    }

    func testAquaRingIngrainIdentifyAndMiracleEye() throws {
        var ring = try battle([mon("a", hp: 160, speed: 10, moves: [status("aqua-ring", type: "water", target: "user")])],
                              [mon("b", attack: 120, speed: 90, moves: [tackle])])
        let events = try ring.resolveTurn(.move(0), .move(0))
        XCTAssertTrue(events.contains(.aquaRing(.a)))
        XCTAssertTrue(contains(events) { if case .effectHeal(.a, .aquaRing, 10, _) = $0 { return true } else { return false } })
        XCTAssertTrue(try ring.resolveTurn(.move(0), .move(0)).contains(.failed(.a)))

        var foresight = try battle([mon("a", speed: 90, moves: [status("foresight"), tackle])],
                                   [mon("g", hp: 999, types: ["ghost"], moves: [harden])])
        XCTAssertTrue(try foresight.resolveTurn(.move(0), .move(0)).contains(.identified(.b)))
        XCTAssertFalse(try foresight.resolveTurn(.move(1), .move(0)).contains(.noEffect(target: .b)), "Normal now hits Ghost")

        let psychic = move("psychic", type: "psychic", power: 90, damageClass: .special)
        var eye = try battle([mon("a", speed: 90, moves: [status("miracle-eye", type: "psychic"), psychic])],
                             [mon("d", hp: 999, types: ["dark"], moves: [harden])])
        _ = try eye.resolveTurn(.move(0), .move(0))
        XCTAssertFalse(try eye.resolveTurn(.move(1), .move(0)).contains(.noEffect(target: .b)))
    }

    func testPsychUpHazeLockOnMemento() throws {
        let swordsDance = status("swords-dance", target: "user", statChanges: [BattleStatChange(stat: "attack", change: 2)],
                                 category: "net-good-stats")
        var copy = try battle([mon("a", moves: [status("psych-up", target: "selected-pokemon")])], [mon("b", speed: 90, moves: [swordsDance])])
        XCTAssertTrue(try copy.resolveTurn(.move(0), .move(0)).contains(.copiedStages(.a)))
        XCTAssertEqual(copy[.a].current.stages.attack, 2)

        var haze = try battle([mon("a", moves: [status("haze", type: "ice", target: "entire-field")])], [mon("b", speed: 90, moves: [swordsDance])])
        XCTAssertTrue(try haze.resolveTurn(.move(0), .move(0)).contains(.stagesReset(nil)))
        XCTAssertEqual(haze[.b].current.stages.attack, 0)

        let inaccurate = move("zap-cannon", type: "electric", power: 120, accuracy: 1, damageClass: .special)
        var lockOn = try battle([mon("a", speed: 90, moves: [status("lock-on"), inaccurate])], [mon("b", hp: 999, moves: [harden])])
        XCTAssertTrue(try lockOn.resolveTurn(.move(0), .move(0)).contains(.tookAim(.a)))
        XCTAssertFalse(try lockOn.resolveTurn(.move(1), .move(0)).contains(.missed(.a)), "Lock-On guarantees the next hit")

        var memento = try battle([mon("a", speed: 90, moves: [status("memento", type: "dark")]), mon("a2")], [mon("b", moves: [harden])])
        let events = try memento.resolveTurn(.move(0), .move(0))
        XCTAssertTrue(events.contains(.statChanged(.b, stat: "attack", change: -2)))
        XCTAssertTrue(memento[.a].team[0].isFainted)
    }

    func testGrudgeEmptiesTheMoveThatKnockedItOut() throws {
        let nuke = move("nuke", power: 250)
        var state = try battle([mon("a", hp: 10, speed: 90, moves: [status("grudge", type: "ghost", target: "user")]), mon("a2")],
                               [mon("b", attack: 200, moves: [nuke])])
        let events = try state.resolveTurn(.move(0), .move(0))
        XCTAssertTrue(events.contains(.grudge(.a)))
        XCTAssertTrue(events.contains(.grudgeTriggered(.b, move: "nuke")))
        XCTAssertEqual(state[.b].current.pp[0], 0)
    }

    func testAssistMeFirstAndMirrorMoveFailures() throws {
        var assist = try battle([mon("a", speed: 90, moves: [status("assist", target: "user")]), mon("a2", moves: [tackle])],
                                [mon("b", hp: 999, moves: [harden])])
        XCTAssertTrue(try assist.resolveTurn(.move(0), .move(0)).contains(.usedMove(.a, move: "tackle")), "calls a teammate's move")
        var alone = try battle([mon("a", speed: 90, moves: [status("assist", target: "user")])], [mon("b", moves: [harden])])
        XCTAssertTrue(try alone.resolveTurn(.move(0), .move(0)).contains(.failed(.a)))

        var meFirst = try battle([mon("a", speed: 90, moves: [status("me-first", priority: 0)])], [mon("b", hp: 999, moves: [tackle, harden])])
        XCTAssertTrue(try meFirst.resolveTurn(.move(0), .move(0)).contains(.usedMove(.a, move: "tackle")))
        XCTAssertTrue(try meFirst.resolveTurn(.move(0), .move(1)).contains(.failed(.a)), "nothing to steal from a status move")

        var mirror = try battle([mon("a", speed: 90, moves: [status("mirror-move", type: "flying")])], [mon("b", moves: [harden])])
        XCTAssertTrue(try mirror.resolveTurn(.move(0), .move(0)).contains(.failed(.a)), "nothing used against it yet")
    }

    func testCaptivateTelekinesisAndQuickGuard() throws {
        let captivate = status("captivate", statChanges: [BattleStatChange(stat: "special-attack", change: -2)])
        var charm = try battle([mon("a", speed: 90, moves: [captivate], gender: .male)], [mon("b", moves: [harden], gender: .female)])
        XCTAssertTrue(try charm.resolveTurn(.move(0), .move(0)).contains(.statChanged(.b, stat: "special-attack", change: -2)))
        var same = try battle([mon("a", speed: 90, moves: [captivate], gender: .male)], [mon("b", moves: [harden], gender: .male)])
        XCTAssertTrue(try same.resolveTurn(.move(0), .move(0)).contains(.failed(.a)))

        let inaccurate = move("zap-cannon", type: "electric", power: 120, accuracy: 1, damageClass: .special)
        var toss = try battle([mon("a", speed: 90, moves: [status("telekinesis", type: "psychic"), inaccurate])],
                              [mon("b", hp: 999, moves: [harden])])
        XCTAssertTrue(try toss.resolveTurn(.move(0), .move(0)).contains(.hurledIntoAir(.b)))
        XCTAssertFalse(try toss.resolveTurn(.move(1), .move(0)).contains(.missed(.a)), "a floating target cannot dodge")

        let quickAttack = move("quick-attack", power: 40, priority: 1)
        let quickGuard = status("quick-guard", type: "fighting", target: "users-field", priority: 3)
        var guarded = try battle([mon("a", moves: [quickGuard])], [mon("b", moves: [quickAttack])])
        let events = try guarded.resolveTurn(.move(0), .move(0))
        XCTAssertTrue(events.contains(.guarding(.a)))
        XCTAssertTrue(events.contains(.blocked(.a)))
    }

    func testTypeChangingMovesAndMimic() throws {
        let flamethrower = move("flamethrower", type: "fire", power: 90, damageClass: .special)
        var conversion = try battle([mon("a", speed: 90, moves: [status("conversion", target: "user"), flamethrower])],
                                    [mon("b", moves: [harden])])
        XCTAssertTrue(try conversion.resolveTurn(.move(0), .move(0)).contains(.typeChanged(.a, type: "fire")))

        var conversion2 = try battle([mon("a", moves: [status("conversion-2")])], [mon("b", speed: 90, moves: [flamethrower])])
        _ = try conversion2.resolveTurn(.move(0), .move(0))
        XCTAssertLessThan(BattleTypeChart.effectiveness(of: "fire", against: conversion2[.a].current.types), 4,
                          "it becomes a type that resists the last move used on it")

        var soak = try battle([mon("a", speed: 90, moves: [status("soak", type: "water")])], [mon("b", types: ["fire"], moves: [harden])])
        XCTAssertTrue(try soak.resolveTurn(.move(0), .move(0)).contains(.typeChanged(.b, type: "water")))
        XCTAssertTrue(try soak.resolveTurn(.move(0), .move(0)).contains(.failed(.a)))

        var reflectType = try battle([mon("a", speed: 90, moves: [status("reflect-type")])], [mon("b", types: ["ghost", "dark"], moves: [harden])])
        _ = try reflectType.resolveTurn(.move(0), .move(0))
        XCTAssertEqual(reflectType[.a].current.types, ["ghost", "dark"])

        var mimic = try battle([mon("a", moves: [status("mimic"), tackle]), mon("a2")], [mon("b", speed: 90, moves: [flamethrower])])
        XCTAssertTrue(try mimic.resolveTurn(.move(0), .move(0)).contains(.learnedMove(.a, move: "flamethrower")))
        XCTAssertEqual(mimic[.a].current.moves[0].name, "flamethrower")
        _ = try mimic.resolveTurn(.switchTo(1), .move(0))
        XCTAssertEqual(mimic[.a].team[0].moves[0].name, "mimic", "Mimic's copy is forgotten on switching")
    }

    func testSpiteSwapsSplitsAutotomizeChargeDefenseCurlGrowth() throws {
        var spite = try battle([mon("a", moves: [status("spite", type: "ghost")])], [mon("b", speed: 90, moves: [tackle])])
        XCTAssertTrue(try spite.resolveTurn(.move(0), .move(0)).contains(.spite(.b, move: "tackle", amount: 4)))
        XCTAssertEqual(spite[.b].current.pp[0], 15)

        let swordsDance = status("swords-dance", target: "user", statChanges: [BattleStatChange(stat: "attack", change: 2)],
                                 category: "net-good-stats")
        var swap = try battle([mon("a", moves: [status("power-swap", type: "psychic")])], [mon("b", speed: 90, moves: [swordsDance])])
        XCTAssertTrue(try swap.resolveTurn(.move(0), .move(0)).contains(.swappedStages(.a)))
        XCTAssertEqual(swap[.a].current.stages.attack, 2)
        XCTAssertEqual(swap[.b].current.stages.attack, 0)
        var heart = try battle([mon("a", moves: [status("heart-swap", type: "psychic")])], [mon("b", speed: 90, moves: [harden])])
        _ = try heart.resolveTurn(.move(0), .move(0))
        XCTAssertEqual(heart[.a].current.stages.defense, 1)
        var guardSwap = try battle([mon("a", moves: [status("guard-swap", type: "psychic")])], [mon("b", speed: 90, moves: [harden])])
        _ = try guardSwap.resolveTurn(.move(0), .move(0))
        XCTAssertEqual(guardSwap[.a].current.stages.defense, 1)

        var split = try battle([mon("a", attack: 50, speed: 90, moves: [status("power-split", type: "psychic"),
                                                                          status("guard-split", type: "psychic")])],
                               [mon("b", attack: 150, defense: 40, moves: [harden])])
        XCTAssertTrue(try split.resolveTurn(.move(0), .move(0)).contains(.sharedStats(.a)))
        XCTAssertEqual(split[.a].current.stats.attack, 100)
        _ = try split.resolveTurn(.move(1), .move(0))
        XCTAssertEqual(split[.a].current.stats.defense, 60)

        let autotomize = status("autotomize", type: "steel", target: "user", statChanges: [BattleStatChange(stat: "speed", change: 2)])
        var light = try battle([mon("a", speed: 90, moves: [autotomize])], [mon("b", moves: [harden])])
        XCTAssertTrue(try light.resolveTurn(.move(0), .move(0)).contains(.lighter(.a)))
        XCTAssertEqual(light[.a].current.weight, 1)

        let charge = status("charge", type: "electric", target: "user", statChanges: [BattleStatChange(stat: "special-defense", change: 1)])
        let thunderbolt = move("thunderbolt", type: "electric", power: 90, damageClass: .special)
        var charged = try battle([mon("a", speed: 90, moves: [charge, thunderbolt])], [mon("b", hp: 9_999, moves: [harden])])
        XCTAssertTrue(try charged.resolveTurn(.move(0), .move(0)).contains(.chargingPower(.a)))
        XCTAssertTrue(charged[.a].current.volatiles.charged)
        _ = try charged.resolveTurn(.move(1), .move(0))
        XCTAssertFalse(charged[.a].current.volatiles.charged, "the boost is spent on the next Electric move")

        let defenseCurl = status("defense-curl", target: "user", statChanges: [BattleStatChange(stat: "defense", change: 1)])
        let rollout = move("rollout", type: "rock", power: 30)
        var curl = try battle([mon("a", speed: 90, moves: [defenseCurl, rollout])], [mon("b", moves: [harden])])
        _ = try curl.resolveTurn(.move(0), .move(0))
        XCTAssertEqual(curl.effectivePower(of: rollout, by: .a), 60, "Defense Curl doubles Rollout")

        let growth = status("growth", target: "user", statChanges: [BattleStatChange(stat: "attack", change: 1)])
        let sunnyDay = status("sunny-day", type: "fire", target: "entire-field", category: "whole-field-effect")
        var grow = try battle([mon("a", speed: 90, moves: [sunnyDay, growth])], [mon("b", moves: [harden])])
        _ = try grow.resolveTurn(.move(0), .move(0))
        _ = try grow.resolveTurn(.move(1), .move(0))
        XCTAssertEqual(grow[.a].current.stages.attack, 2, "Growth doubles in harsh sunlight")
    }

    func testSportsWeakenTheirTypeAndMoonlightChangesWithWeather() throws {
        let waterSport = status("water-sport", type: "water", target: "entire-field", category: "whole-field-effect")
        var sport = try battle([mon("a", speed: 90, moves: [waterSport])], [mon("b", moves: [harden])])
        XCTAssertTrue(try sport.resolveTurn(.move(0), .move(0)).contains(.sportStarted("fire")))
        XCTAssertTrue(try sport.resolveTurn(.move(0), .move(0)).contains(.failed(.a)))

        let moonlight = status("moonlight", type: "fairy", target: "user", category: "heal", healing: 50)
        let rainDance = status("rain-dance", type: "water", target: "entire-field", category: "whole-field-effect")
        var rain = try battle([mon("a", hp: 400, speed: 10, moves: [rainDance, moonlight])],
                              [mon("b", attack: 200, speed: 90, moves: [move("nuke", power: 100)])])
        _ = try rain.resolveTurn(.move(0), .move(0))
        let events = try rain.resolveTurn(.move(1), .move(0))
        XCTAssertTrue(contains(events) { if case .healed(.a, 100, _) = $0 { return true } else { return false } },
                      "a quarter of max HP in rain")
    }

    func testGravityBlocksFlyAndSleepTalkNeedsSleep() throws {
        let gravity = status("gravity", type: "psychic", target: "entire-field", category: "whole-field-effect")
        let fly = move("fly", type: "flying", power: 90)
        var state = try battle([mon("a", speed: 90, moves: [gravity])], [mon("b", moves: [fly, harden])])
        _ = try state.resolveTurn(.move(0), .move(1))
        XCTAssertEqual(state.usableMoves(for: .b), [1], "Fly is unusable under Gravity")

        var awake = try battle([mon("a", speed: 90, moves: [status("sleep-talk", target: "user"), tackle])], [mon("b", moves: [harden])])
        XCTAssertTrue(try awake.resolveTurn(.move(0), .move(0)).contains(.failed(.a)))
    }
}

final class BattleRemainingBranchTests: XCTestCase {
    func testWideGuardBlocksSpreadMovesOnly() throws {
        let earthquake = move("earthquake", type: "ground", power: 100, target: "all-other-pokemon")
        let wideGuard = status("wide-guard", type: "rock", target: "users-field", priority: 3)
        var state = try battle([mon("a", hp: 999, moves: [wideGuard])], [mon("b", moves: [earthquake, tackle])])
        XCTAssertTrue(try state.resolveTurn(.move(0), .move(0)).contains(.blocked(.a)))
        XCTAssertFalse(try state.resolveTurn(.move(0), .move(1)).contains(.blocked(.a)), "single-target moves get through")
    }

    func testUproarWakesASleepingPokemonAndSnoreNeedsSleep() throws {
        let uproar = move("uproar", power: 90, damageClass: .special)
        var state = try battle([mon("a", hp: 999, moves: [hypnosis, uproar])], [mon("b", hp: 9_999, speed: 10, moves: [tackle])], seed: 2)
        _ = try state.resolveTurn(.move(0), .move(0))
        XCTAssertEqual(state[.b].current.status, .sleep)
        // The slower sleeper acts after the uproar starts, so it wakes up in that same turn.
        let events = try state.resolveTurn(.move(1), .move(0))
        XCTAssertTrue(events.contains(.uproar(.a, started: true)))
        XCTAssertTrue(events.contains(.wokeUp(.b)), "the noise wakes it up")

        let snore = move("snore", power: 50, damageClass: .special, category: "damage")
        var awake = try battle([mon("a", speed: 90, moves: [snore])], [mon("b", moves: [harden])])
        XCTAssertTrue(try awake.resolveTurn(.move(0), .move(0)).contains(.failed(.a)))
    }

    func testCPUSkipsSetupThatIsAlreadyInPlace() throws {
        let reflect = status("reflect", type: "psychic", target: "users-field", category: "field-effect")
        let spikes = status("spikes", type: "ground", target: "opponents-field", category: "field-effect")
        let leechSeed = status("leech-seed", type: "grass", category: "ailment", ailment: "leech-seed")
        let splash = status("splash", target: "user")
        var state = try battle([mon("cpu", speed: 90, moves: [reflect, spikes, leechSeed, splash])], [mon("b", hp: 999, moves: [harden])])
        XCTAssertGreaterThan(BattleCPU.score(reflect, by: .a, in: state), 0)
        XCTAssertEqual(BattleCPU.score(splash, by: .a, in: state), 0)
        _ = try state.resolveTurn(.move(0), .move(0))
        XCTAssertEqual(BattleCPU.score(reflect, by: .a, in: state), 0, "Reflect is already up")
        for _ in 0..<3 { _ = try state.resolveTurn(.move(1), .move(0)) }
        XCTAssertEqual(BattleCPU.score(spikes, by: .a, in: state), 0, "three layers is the maximum")
        _ = try state.resolveTurn(.move(2), .move(0))
        if state[.b].current.volatiles.leechSeeded { XCTAssertEqual(BattleCPU.score(leechSeed, by: .a, in: state), 0) }

        let explosion = move("explosion", power: 250)
        let healthy = try battle([mon("cpu", hp: 200, moves: [explosion])], [mon("b", moves: [harden])])
        let full = BattleCPU.score(explosion, by: .a, in: healthy)
        let hyperBeam = move("hyper-beam", power: 150, damageClass: .special)
        XCTAssertEqual(BattleCPU.score(hyperBeam, by: .a, in: healthy), 150 * 4 * 3 * 100 * 2 / 3,
                       "a recharge turn costs a third of the value (STAB Normal move from a Normal CPU)")
        XCTAssertLessThan(full, 250 * 4 * 3 * 100 / 2, "self-destructing at full HP is a last resort")
    }
}

final class BattleLastUniqueMoveTests: XCTestCase {
    func testShellSmashAcupressurePsychoShiftDefogAndCamouflage() throws {
        let shellSmash = status("shell-smash", target: "user", statChanges: [
            BattleStatChange(stat: "defense", change: -1), BattleStatChange(stat: "special-defense", change: -1),
            BattleStatChange(stat: "attack", change: 2), BattleStatChange(stat: "special-attack", change: 2),
            BattleStatChange(stat: "speed", change: 2)])
        var smash = try battle([mon("a", speed: 90, moves: [shellSmash])], [mon("b", moves: [harden])])
        _ = try smash.resolveTurn(.move(0), .move(0))
        XCTAssertEqual(smash[.a].current.stages.attack, 2)
        XCTAssertEqual(smash[.a].current.stages.defense, -1)

        var acupressure = try battle([mon("a", speed: 90, moves: [status("acupressure", target: "user-or-ally")])], [mon("b", moves: [harden])])
        let raised = try acupressure.resolveTurn(.move(0), .move(0))
        XCTAssertEqual(raised.filter { if case .statChanged(.a, _, 2) = $0 { return true } else { return false } }.count, 1)

        // A burn never stops the user from acting, unlike paralysis, so this does not depend on the seed.
        let willOWisp = status("will-o-wisp", type: "fire", category: "ailment", ailment: "burn")
        var shift = try battle([mon("a", moves: [status("psycho-shift", type: "psychic"), harden])],
                               [mon("b", hp: 999, speed: 90, moves: [willOWisp, harden])])
        _ = try shift.resolveTurn(.move(1), .move(0))
        XCTAssertEqual(shift[.a].current.status, .burn)
        let events = try shift.resolveTurn(.move(0), .move(1))
        XCTAssertTrue(events.contains(.statusApplied(.b, .burn)))
        XCTAssertNil(shift[.a].current.status, "the status moved over to the target")
        var nothing = try battle([mon("a", speed: 90, moves: [status("psycho-shift", type: "psychic")])], [mon("b", moves: [harden])])
        XCTAssertTrue(try nothing.resolveTurn(.move(0), .move(0)).contains(.failed(.a)))

        let reflect = status("reflect", type: "psychic", target: "users-field", category: "field-effect")
        let defog = status("defog", type: "flying", statChanges: [BattleStatChange(stat: "evasion", change: -1)])
        var fog = try battle([mon("a", moves: [defog])], [mon("b", speed: 90, moves: [reflect])])
        let cleared = try fog.resolveTurn(.move(0), .move(0))
        XCTAssertTrue(cleared.contains(.hazardsCleared(.b)))
        XCTAssertFalse(fog[.b].conditions.has(.reflect))
        XCTAssertEqual(fog[.b].current.stages.evasion, -1)

        var camouflage = try battle([mon("a", speed: 90, moves: [status("camouflage", target: "user")])], [mon("b", moves: [harden])])
        XCTAssertTrue(try camouflage.resolveTurn(.move(0), .move(0)).contains(.typeChanged(.a, type: "ground")))
        XCTAssertTrue(try camouflage.resolveTurn(.move(0), .move(0)).contains(.failed(.a)))
    }
}
