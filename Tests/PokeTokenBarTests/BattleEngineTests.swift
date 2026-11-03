import XCTest
@testable import PokeTokenBar

final class BattleEngineTests: XCTestCase {
    func testDoubleEdgeRecoilUsesActualDamageAndSurvivesReplay() throws {
        var battle = try BattleState(first: mon("a", speed: 100, move: "double-edge"),
                                     second: mon("b", hp: 10), seed: 1)
        var replay = try JSONDecoder().decode(BattleState.self, from: JSONEncoder().encode(battle))
        let events = try battle.resolve(firstMoveID: "double-edge", secondMoveID: "tackle")
        XCTAssertEqual(events, try replay.resolve(firstMoveID: "double-edge", secondMoveID: "tackle"))
        XCTAssertEqual(events, [.attack(side: 0, moveID: "double-edge", damage: 10, effectiveness: 1),
                                .recoil(side: 0, moveID: "double-edge", damage: 3),
                                .fainted(side: 1), .won(side: 0)])
        XCTAssertEqual(battle.fighters.map(\.currentHP), [197, 0])
    }

    func testDoubleEdgeRecoilKnockoutSkipsOpponentAndDoubleKnockoutDrawDecodes() throws {
        var battle = try BattleState(first: mon("a", hp: 1, speed: 100, move: "double-edge"),
                                     second: mon("b", hp: 200), seed: 1)
        let events = try battle.resolve(firstMoveID: "double-edge", secondMoveID: "tackle")
        XCTAssertEqual(events.suffix(2), [.fainted(side: 0), .won(side: 1)])
        XCTAssertEqual(events.filter { if case .attack = $0 { return true }; return false }.count, 1)
        var doubleKO = try BattleState(first: mon("a", hp: 1, speed: 100, move: "double-edge"),
                                       second: mon("b", hp: 1), seed: 1)
        let tied = try doubleKO.resolve(firstMoveID: "double-edge", secondMoveID: "tackle")
        XCTAssertEqual(tied.suffix(3), [.fainted(side: 1), .fainted(side: 0), .draw])
        XCTAssertNil(doubleKO.winner)
        XCTAssertEqual(try JSONDecoder().decode(BattleState.self, from: JSONEncoder().encode(doubleKO)), doubleKO)
    }

    func testDoubleEdgeImmunityDoesNotCauseRecoil() throws {
        var battle = try BattleState(first: mon("a", speed: 100, types: ["ghost"], move: "double-edge"),
                                     second: mon("b", types: ["ghost"]), seed: 1)
        let events = try battle.resolve(firstMoveID: "double-edge", secondMoveID: "tackle")
        XCTAssertFalse(events.contains { if case .recoil = $0 { return true }; return false })
        XCTAssertEqual(battle.fighters.map(\.currentHP), [200, 200])
    }

    private func mon(_ id: String, hp: Int = 200, speed: Int = 50, attack: Int = 80,
                     types: [String] = ["normal"], move: String = "tackle") -> BattleCombatant {
        BattleCombatant(id: id, speciesID: 1, name: id, level: 50, types: types,
                        stats: BattleStats(hp: hp, attack: attack, defense: 80,
                                           specialAttack: 80, specialDefense: 80, speed: speed),
                        moves: [BattleMoveCatalog.move(named: move)!])
    }

    func testFasterKnockoutSkipsSecondAttackAndClampsDamage() throws {
        var battle = try BattleState(first: mon("a", speed: 100), second: mon("b", hp: 1), seed: 0)
        XCTAssertEqual(try battle.resolve(firstMoveID: "tackle", secondMoveID: "tackle"), [
            .attack(side: 0, moveID: "tackle", damage: 1, effectiveness: 1), .fainted(side: 1), .won(side: 0)])
        XCTAssertEqual(battle.winner, 0)
        XCTAssertTrue(battle.isFinished)
        XCTAssertThrowsError(try battle.resolve(firstMoveID: "tackle", secondMoveID: "tackle")) {
            XCTAssertEqual($0 as? BattleError, .finished)
        }
    }

    func testInvalidSecondCommandDoesNotConsumeFirstActionOrRandomness() throws {
        var battle = try BattleState(first: mon("a"), second: mon("b"), seed: 0)
        let before = battle
        XCTAssertThrowsError(try battle.resolve(firstMoveID: "tackle", secondMoveID: "ember")) {
            XCTAssertEqual($0 as? BattleError, .invalidMove)
        }
        XCTAssertEqual(battle, before)
    }

    func testSeededReplayIncludingSpeedTiesSurvivesSerialization() throws {
        var left = try BattleState(first: mon("a"), second: mon("b"), seed: 42)
        var right = try JSONDecoder().decode(BattleState.self, from: JSONEncoder().encode(left))
        for _ in 0..<3 {
            XCTAssertEqual(try left.resolve(firstMoveID: "tackle", secondMoveID: "tackle"),
                           try right.resolve(firstMoveID: "tackle", secondMoveID: "tackle"))
            XCTAssertEqual(left, right)
        }
    }

    func testImmunityStalemateEndsInDrawAtTurnLimit() throws {
        var battle = try BattleState(first: mon("a", types: ["ghost"]), second: mon("b", types: ["ghost"]), seed: 1)
        var events: [BattleEvent] = []
        for _ in 0..<BattleState.maximumTurns {
            events = try battle.resolve(firstMoveID: "tackle", secondMoveID: "tackle")
        }
        XCTAssertEqual(events.last, .draw)
        XCTAssertTrue(battle.isFinished)
        XCTAssertNil(battle.winner)
        XCTAssertEqual(battle.fighters.map(\.currentHP), [200, 200])
    }

    func testTypeChartHandlesDualTypesResistanceAndImmunity() {
        XCTAssertEqual(BattleTypeChart.multiplier(attacking: "grass", defending: ["water", "ground"]), 4)
        XCTAssertEqual(BattleTypeChart.multiplier(attacking: "normal", defending: ["rock", "steel"]), 0.25)
        XCTAssertEqual(BattleTypeChart.multiplier(attacking: "normal", defending: ["ghost", "rock"]), 0)
        XCTAssertEqual(BattleTypeChart.multiplier(attacking: "dragon", defending: ["fairy"]), 0)
    }

    func testDamageUsesIntegerBaseAndFlooredModifiers() throws {
        // base = ((22 * 40 * 80 / 80) / 50) + 2 = 19; STAB gives floor(28.5 * 0.85...1).
        var battle = try BattleState(first: mon("a", speed: 100), second: mon("b"), seed: 1)
        let events = try battle.resolve(firstMoveID: "tackle", secondMoveID: "tackle")
        guard case let .attack(side, _, damage, _) = events[0] else { return XCTFail("Expected hit") }
        XCTAssertEqual(side, 0)
        XCTAssertEqual(damage, 26, "Seed 1 rolls 92%; floor(19 × 1.5 × 0.92) = 26")
        XCTAssertEqual(battle.fighters[1].currentHP, 200 - damage)
    }

    func testAccuracyMissAndSpecialCategoryUseCorrectStat() throws {
        var foundMiss = false
        for seed in UInt64(0)..<100 {
            var battle = try BattleState(first: mon("a", speed: 100, move: "slam"), second: mon("b"), seed: seed)
            if case .miss(side: 0, moveID: "slam") = try battle.resolve(firstMoveID: "slam", secondMoveID: "tackle")[0] {
                XCTAssertEqual(battle.fighters[1].currentHP, 200)
                foundMiss = true
                break
            }
        }
        XCTAssertTrue(foundMiss)
        var low = try BattleState(first: mon("a", speed: 100, attack: 1, move: "water-gun"), second: mon("b"), seed: 4)
        var high = try BattleState(first: mon("a", speed: 100, attack: 9999, move: "water-gun"), second: mon("b"), seed: 4)
        XCTAssertEqual(try low.resolve(firstMoveID: "water-gun", secondMoveID: "tackle"),
                       try high.resolve(firstMoveID: "water-gun", secondMoveID: "tackle"))
    }

    func testCatalogRejectsUnsupportedEffectsAndDeduplicatesKnownMoves() {
        XCTAssertNil(BattleMoveCatalog.move(named: "ember"), "Burn effect is unsupported")
        let known = ["tackle", "growl", "tackle", "water-gun"].map { PokemonKnownMove(name: $0, learnedAtLevel: 1) }
        XCTAssertEqual(BattleMoveCatalog.moves(for: known).map(\.id), ["tackle", "growl", "water-gun"])
        XCTAssertEqual(BattleMoveCatalog.moves(for: [PokemonKnownMove(name: "practice-strike", learnedAtLevel: 1)]), [])
    }

    func testPracticeActionRunsAndReplaysAsExplicitAppMove() throws {
        var battle = try BattleState(first: mon("a", move: "practice-strike"),
                                     second: mon("b", move: "practice-strike"), seed: 1)
        var decoded = try JSONDecoder().decode(BattleState.self, from: JSONEncoder().encode(battle))
        let events = try battle.resolve(firstMoveID: "practice-strike", secondMoveID: "practice-strike")
        XCTAssertEqual(events, try decoded.resolve(firstMoveID: "practice-strike", secondMoveID: "practice-strike"))
        XCTAssertTrue(battle.fighters.allSatisfy { $0.currentHP < $0.combatant.stats.hp })
    }

    func testExpandedAttacksResolveAndReplayUsingTheirOwnCategoryAndType() throws {
        let added = ["vice-grip", "hydro-pump", "egg-bomb", "megahorn", "x-scissor", "dragon-pulse",
                     "power-whip", "swift", "feint-attack", "shadow-punch", "aerial-ace",
                     "magical-leaf", "shock-wave", "aura-sphere", "magnet-bomb"]
        for move in added {
            var battle = try BattleState(first: mon("a", speed: 100, move: move),
                                         second: mon("b", types: ["water", "flying"]), seed: 4)
            var decoded = try JSONDecoder().decode(BattleState.self, from: JSONEncoder().encode(battle))
            let events = try battle.resolve(firstMoveID: move, secondMoveID: "tackle")
            XCTAssertEqual(events, try decoded.resolve(firstMoveID: move, secondMoveID: "tackle"), move)
            XCTAssertEqual(battle, decoded, move)
            if move == "shock-wave" {
                guard case let .attack(side, _, damage, effectiveness) = events[0] else {
                    return XCTFail("Shock Wave must hit")
                }
                XCTAssertEqual(side, 0)
                XCTAssertEqual(effectiveness, 4)
                XCTAssertGreaterThan(damage, 0)
            }
        }
    }

    func testNeverMissAttacksAlwaysActAcrossRandomSeeds() throws {
        for move in ["swift", "feint-attack", "shadow-punch", "aerial-ace", "magical-leaf",
                     "shock-wave", "aura-sphere", "magnet-bomb"] {
            for seed in UInt64(0)..<100 {
                var battle = try BattleState(first: mon("a", speed: 100, move: move),
                                             second: mon("b", types: ["water"]), seed: seed)
                guard case let .attack(side, _, damage, _) = try battle.resolve(firstMoveID: move, secondMoveID: "tackle")[0] else {
                    return XCTFail("\(move) must not miss for seed \(seed)")
                }
                XCTAssertEqual(side, 0)
                XCTAssertGreaterThan(damage, 0)
            }
        }
        for unsupported in ["ember", "thunderbolt", "ice-beam", "quick-attack", "double-slap", "psyshock"] {
            XCTAssertNil(BattleMoveCatalog.move(named: unsupported), "Unsupported effects must not be silently omitted")
        }
    }

    func testDecodedSnapshotsRejectIncompatibleRulesAndInvalidState() throws {
        let battle = try BattleState(first: mon("a"), second: mon("b"), seed: 0)
        let encoded = try JSONEncoder().encode(battle)
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        for (key, value) in [("fighters", [] as Any), ("version", 999 as Any), ("winner", 7 as Any), ("turn", 0 as Any)] {
            var changed = original
            changed[key] = value
            XCTAssertThrowsError(try JSONDecoder().decode(BattleState.self, from: JSONSerialization.data(withJSONObject: changed)))
        }
    }

    func testRejectsSameIndividualAndUnusableSnapshots() {
        XCTAssertThrowsError(try BattleState(first: mon("a"), second: mon("a"), seed: 0)) {
            XCTAssertEqual($0 as? BattleError, .sameIndividual)
        }
        XCTAssertThrowsError(try BattleState(first: mon("a", hp: 0), second: mon("b"), seed: 0))
        let invalid = BattleCombatant(id: "x", speciesID: 1, name: "x", level: 50, types: ["normal"],
                                      stats: mon("a").stats, moves: [])
        XCTAssertThrowsError(try BattleState(first: invalid, second: mon("b"), seed: 0))
    }
    private func equipped(_ id: String, hp: Int = 200, speed: Int = 50, moves: [String]) -> BattleCombatant {
        let source = mon(id, hp: hp, speed: speed)
        return BattleCombatant(id: source.id, speciesID: source.speciesID, name: source.name,
                               level: source.level, types: source.types, stats: source.stats,
                               moves: moves.map { BattleMoveCatalog.move(named: $0)! })
    }

    func testStageBuffChangesDamageAndCapsAtSix() throws {
        var buffed = try BattleState(first: equipped("a", hp: 9999, speed: 100, moves: ["swords-dance", "tackle"]),
                                     second: equipped("b", hp: 9999, moves: ["harden", "tackle"]), seed: 2)
        for _ in 0..<3 { _ = try buffed.resolve(firstMoveID: "swords-dance", secondMoveID: "harden") }
        XCTAssertEqual(buffed.fighters[0].stages[.attack], 6)
        XCTAssertEqual(buffed.fighters[0].effectiveStat(.attack), 320)
        let capped = try buffed.resolve(firstMoveID: "swords-dance", secondMoveID: "harden")
        XCTAssertEqual(capped.first, .failed(side: 0, moveID: "swords-dance"))
        XCTAssertEqual(buffed.fighters[0].stages[.attack], 6)
    }

    func testDebuffAffectsLaterActionImmediatelyAndCapsAtMinusSix() throws {
        var debuffed = try BattleState(first: equipped("a", hp: 9999, speed: 100, moves: ["growl"]),
                                       second: equipped("b", hp: 9999, moves: ["tackle"]), seed: 3)
        var neutral = try BattleState(first: equipped("a", hp: 9999, speed: 100, moves: ["recover"]),
                                     second: equipped("b", hp: 9999, moves: ["tackle"]), seed: 3)
        let reduced = try debuffed.resolve(firstMoveID: "growl", secondMoveID: "tackle")
        let normal = try neutral.resolve(firstMoveID: "recover", secondMoveID: "tackle")
        guard case let .attack(_, _, low, _) = reduced.last,
              case let .attack(_, _, high, _) = normal.last else { return XCTFail("Expected damage") }
        // Same seed and accuracy draws: the fast Growl reduces the later attack this turn.
        XCTAssertEqual(debuffed.fighters[1].effectiveStat(.attack), 53)
        XCTAssertLessThan(low, high)
        for _ in 0..<5 { _ = try debuffed.resolve(firstMoveID: "growl", secondMoveID: "tackle") }
        XCTAssertEqual(debuffed.fighters[1].stages[.attack], -6)
        XCTAssertEqual(debuffed.fighters[1].effectiveStat(.attack), 20)
        XCTAssertEqual(try debuffed.resolve(firstMoveID: "growl", secondMoveID: "tackle").first,
                       .failed(side: 0, moveID: "growl"))
    }

    func testAgilityChangesNextTurnOrderAndCompoundBuffsReplay() throws {
        var battle = try BattleState(first: equipped("a", hp: 9999, speed: 40, moves: ["agility", "calm-mind"]),
                                    second: equipped("b", hp: 9999, speed: 60, moves: ["harden"]), seed: 4)
        let first = try battle.resolve(firstMoveID: "agility", secondMoveID: "harden")
        guard case .statChange(side: 1, target: 1, moveID: "harden", stat: .defense, change: 1, stage: 1) = first[0] else {
            return XCTFail("Initial faster Pokémon must act first")
        }
        var replay = try JSONDecoder().decode(BattleState.self, from: JSONEncoder().encode(battle))
        let next = try battle.resolve(firstMoveID: "calm-mind", secondMoveID: "harden")
        XCTAssertEqual(next.first, .statChange(side: 0, target: 0, moveID: "calm-mind", stat: .specialAttack, change: 1, stage: 1))
        XCTAssertEqual(battle.fighters[0].stages[.specialDefense], 1)
        XCTAssertEqual(next, try replay.resolve(firstMoveID: "calm-mind", secondMoveID: "harden"))
        XCTAssertEqual(battle, replay)
    }

    func testRecoveryFailsAtFullHPThenHealsAndClamps() throws {
        var battle = try BattleState(first: equipped("a", hp: 201, speed: 100, moves: ["recover"]),
                                    second: equipped("b", moves: ["tackle", "harden"]), seed: 5)
        XCTAssertEqual(try battle.resolve(firstMoveID: "recover", secondMoveID: "tackle").first,
                       .failed(side: 0, moveID: "recover"))
        let lost = 201 - battle.fighters[0].currentHP
        let events = try battle.resolve(firstMoveID: "recover", secondMoveID: "harden")
        XCTAssertEqual(events.first, .heal(side: 0, moveID: "recover", amount: lost))
        XCTAssertEqual(battle.fighters[0].currentHP, 201)
    }

    func testCatalogRetainsAttackWhenNewestFourMovesAreStatus() {
        let learned = ["tackle", "growl", "harden", "agility", "recover"].map {
            PokemonKnownMove(name: $0, learnedAtLevel: 1)
        }
        let selected = BattleMoveCatalog.moves(for: learned)
        XCTAssertEqual(selected.count, 4)
        XCTAssertTrue(selected.contains { $0.id == "tackle" })
    }

    func testDecodedSnapshotsRejectOutOfRangeStages() throws {
        let battle = try BattleState(first: mon("a"), second: mon("b"), seed: 0)
        var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(battle)) as? [String: Any])
        var fighters = try XCTUnwrap(payload["fighters"] as? [[String: Any]])
        var stages = try XCTUnwrap(fighters[0]["stages"] as? [String: Any])
        stages["attack"] = 7; fighters[0]["stages"] = stages; payload["fighters"] = fighters
        XCTAssertThrowsError(try JSONDecoder().decode(BattleState.self, from: JSONSerialization.data(withJSONObject: payload)))
    }

    func testCompoundBuffStillAppliesUncappedComponent() throws {
        var battle = try BattleState(first: equipped("a", moves: ["swords-dance", "bulk-up"]),
                                    second: equipped("b", moves: ["recover"]), seed: 0)
        for _ in 0..<3 { _ = try battle.resolve(firstMoveID: "swords-dance", secondMoveID: "recover") }
        let events = try battle.resolve(firstMoveID: "bulk-up", secondMoveID: "recover")
        XCTAssertTrue(events.contains(.statChange(side: 0, target: 0, moveID: "bulk-up", stat: .attack, change: 0, stage: 6)))
        XCTAssertTrue(events.contains(.statChange(side: 0, target: 0, moveID: "bulk-up", stat: .defense, change: 1, stage: 1)))
    }

    func testRecoveryRestoresHalfMaximumHPWhenMoreIsMissing() throws {
        let initial = try BattleState(first: equipped("a", hp: 201, speed: 100, moves: ["synthesis"]),
                                     second: equipped("b", moves: ["harden"]), seed: 0)
        var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(initial)) as? [String: Any])
        var fighters = try XCTUnwrap(payload["fighters"] as? [[String: Any]])
        fighters[0]["currentHP"] = 1; payload["fighters"] = fighters
        var battle = try JSONDecoder().decode(BattleState.self, from: JSONSerialization.data(withJSONObject: payload))
        let events = try battle.resolve(firstMoveID: "synthesis", secondMoveID: "harden")
        XCTAssertEqual(events.first, .heal(side: 0, moveID: "synthesis", amount: 100))
        XCTAssertEqual(battle.fighters[0].currentHP, 101)
    }

}
