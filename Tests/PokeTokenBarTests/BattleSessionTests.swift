import XCTest
@testable import PokeTokenBar

private func move(_ name: String, type: String = "normal", power: Int? = 40, damageClass: BattleDamageClass = .physical,
                  category: String = "damage") -> BattleMove {
    BattleMove(name: name, type: type, power: power, accuracy: nil, pp: 20, priority: 0, damageClass: damageClass,
               target: "selected-pokemon", category: category)
}

private func mon(_ id: String, hp: Int = 100, speed: Int = 50, types: [String] = ["normal"],
                 moves: [BattleMove] = [move("tackle")], names: [String: String]? = nil) -> BattlePokemon {
    BattlePokemon(instanceID: id, speciesID: 25, names: names ?? ["en": id.capitalized], level: 50, isShiny: false,
                  unownForm: nil, gender: nil, nature: nil, abilityName: nil, types: types,
                  stats: BattleStats(hp: hp, attack: 60, defense: 50, specialAttack: 60, specialDefense: 50, speed: speed),
                  moves: moves)
}

@MainActor
private final class SuspendingOpponent: BattleOpponent {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var waiting = false
    func action(in state: BattleState, side: BattleSide) async throws -> BattleAction {
        waiting = true
        await withCheckedContinuation { continuation = $0 }
        return .move(0)
    }
    func replacement(in state: BattleState, side: BattleSide) async throws -> Int { state.switchTargets(for: side)[0] }
    func release() { continuation?.resume(); continuation = nil }
}

private func team(_ members: [BattlePokemon]) throws -> BattleTeam { try BattleTeam(members: members) }

@MainActor
private final class ScriptedOpponent: BattleOpponent {
    var actions: [BattleAction]
    var fails = false
    init(_ actions: [BattleAction]) { self.actions = actions }
    func action(in state: BattleState, side: BattleSide) async throws -> BattleAction {
        if fails { throw URLError(.networkConnectionLost) }
        return actions.isEmpty ? .move(0) : actions.removeFirst()
    }
    func replacement(in state: BattleState, side: BattleSide) async throws -> Int { state.switchTargets(for: side)[0] }
}

final class BattleCPUTests: XCTestCase {
    func testPicksTheStrongestExpectedDamageWhenNotRolling() throws {
        let cpu = mon("cpu", types: ["water"], moves: [move("tackle"), move("water-gun", type: "water"),
                                                        move("vine-whip", type: "grass", power: 45)])
        let state = BattleState(teamA: try team([mon("foe", types: ["fire"])]), teamB: try team([cpu]), seed: 1)
        var picks: [BattleAction: Int] = [:]
        var rng = BattleRNG(seed: 3)
        for _ in 0..<400 { picks[BattleCPU.action(for: .b, in: state, rng: &rng), default: 0] += 1 }
        XCTAssertGreaterThan(picks[.move(1), default: 0], 250, "super effective + STAB wins most turns")
        XCTAssertGreaterThan(picks[.move(0), default: 0], 0, "a random pick still happens sometimes")
        XCTAssertNil(picks[.switchTo(0)])
    }

    func testStatusMovesAreOnlyAFallbackAndUnsupportedMovesAreNever() throws {
        let growl = BattleMove(name: "growl", type: "normal", power: nil, accuracy: 100, pp: 40, priority: 0,
                               damageClass: .status, target: "all-opponents",
                               statChanges: [BattleStatChange(stat: "attack", change: -1)], category: "net-good-stats")
        let splash = move("splash", power: nil, damageClass: .status, category: "unique")
        let attacker = mon("cpu", moves: [splash, growl, move("tackle")])
        let defender = mon("foe")
        XCTAssertLessThan(BattleCPU.score(splash, attacker, defender), BattleCPU.score(growl, attacker, defender))
        XCTAssertLessThan(BattleCPU.score(growl, attacker, defender), BattleCPU.score(move("tackle"), attacker, defender))
    }

    func testStrugglesWithoutUsableMovesAndReplacesWithTheBestMatchup() throws {
        let splash = move("splash", power: nil, damageClass: .status, category: "unique")
        var rng = BattleRNG(seed: 1)
        let stuck = BattleState(teamA: try team([mon("foe")]), teamB: try team([mon("cpu", moves: [splash])]), seed: 1)
        XCTAssertEqual(BattleCPU.action(for: .b, in: stuck, rng: &rng), .struggle)

        var state = BattleState(
            teamA: try team([mon("a", speed: 90, types: ["fire"], moves: [move("nuke", power: 250)])]),
            teamB: try team([mon("b0"), mon("weak", moves: [move("ember", type: "fire")]),
                             mon("strong", moves: [move("surf", type: "water", power: 90)])]), seed: 1)
        _ = try state.resolveTurn(.move(0), .move(0))
        XCTAssertEqual(BattleCPU.replacement(for: .b, in: state), 2)
    }
}

private struct FactoryDetails: PokemonDetailProviding {
    func pokemonDetails(speciesID: Int) async throws -> PokemonDetails {
        // Every fifth species learns nothing by level-up, like a hatchling without moves yet.
        let learnset = speciesID % 5 == 0 ? [] : [
            PokemonMoveOption(name: "tackle", learnMethods: [PokemonMoveLearnMethod(method: "level-up", level: 1)])]
        return PokemonDetails(speciesID: speciesID, name: "s\(speciesID)", height: 1, weight: 1, baseExperience: nil,
                              genderRate: 4, types: ["normal"],
                              baseStats: ["hp": 50, "attack": 50, "defense": 50, "special-attack": 50,
                                          "special-defense": 50, "speed": 50],
                              abilities: [PokemonAbilityOption(name: "run-away", slot: 1, isHidden: false)], moves: learnset)
    }
}

private struct FactoryMoves: BattleMoveProviding {
    func move(named name: String) async throws -> BattleMove {
        BattleMove(name: name, type: "normal", power: 40, accuracy: 100, pp: 35, priority: 0,
                   damageClass: .physical, target: "selected-pokemon")
    }
}

final class BattleOpponentFactoryTests: XCTestCase {
    func testOpponentMirrorsTeamSizeAndLevelsWithDistinctSpecies() async throws {
        let levels = [5, 17, 33, 48, 76, 100]
        let player = try team(levels.enumerated().map { index, level in
            let base = mon("p\(index)")
            return BattlePokemon(instanceID: base.instanceID, speciesID: base.speciesID, names: base.names, level: level,
                                 isShiny: false, unownForm: nil, gender: nil, nature: nil, abilityName: nil,
                                 types: base.types, stats: base.stats, moves: base.moves)
        })
        let factory = BattleOpponentFactory(details: FactoryDetails(), moves: FactoryMoves(),
                                            speciesNames: { ["en": "Species \($0)"] })
        for seed in UInt64(1)...30 {
            let opponent = try await factory.team(matching: player, seed: seed)
            XCTAssertEqual(opponent.members.map(\.level), levels)
            let species = opponent.members.map(\.speciesID)
            XCTAssertEqual(Set(species).count, species.count)
            XCTAssertFalse(species.contains(PokemonOdds.dittoSpeciesID))
            XCTAssertTrue(species.allSatisfy { PokemonAssets.animatedSpeciesIDs.contains($0) && $0 % 5 != 0 },
                          "species without a single move are skipped")
            XCTAssertEqual(opponent.members[0].names["en"], "Species \(species[0])")
        }
        let again = try await factory.team(matching: player, seed: 7)
        let first = try await factory.team(matching: player, seed: 7)
        XCTAssertEqual(again, first, "the same seed builds the same opponent")
    }
}

@MainActor
final class BattleSessionTests: XCTestCase {
    private func session(_ mine: [BattlePokemon], _ theirs: [BattlePokemon], opponent: any BattleOpponent,
                         language: AppLanguage = .en) throws -> BattleSession {
        BattleSession(myTeam: try team(mine), opponentTeam: try team(theirs), seed: 5, opponent: opponent,
                      language: language, pace: .zero)
    }

    func testFullCPUBattlePlaysToAnOutcomeAndDisplayCatchesUp() async throws {
        let mine = (0..<3).map { mon("mine\($0)", hp: 120, speed: 60 + $0) }
        let theirs = (0..<3).map { mon("cpu\($0)", hp: 110, speed: 55 + $0) }
        let s = try session(mine, theirs, opponent: CPUOpponent(seed: 9))
        await s.start()
        XCTAssertEqual(s.log.prefix(2), ["Go! Mine0!", "The opponent sent out Cpu0!"])
        XCTAssertEqual(s.message, "What will Mine0 do?")

        var turns = 0
        while s.outcome == nil, turns < 200 {
            if s.awaitingReplacement {
                await s.replace(with: s.switchTargets[0])
            } else {
                await s.choose(.move(0))
            }
            XCTAssertEqual(s.display.hp, BattleSide.allCases.map { side in s.state[side].team.map(\.hp) },
                           "after playback the screen shows exactly the engine state")
            turns += 1
        }
        XCTAssertNotNil(s.outcome)
        XCTAssertTrue(s.log.contains { $0.hasPrefix("The opposing Cpu") && $0.hasSuffix("fainted!") }
                      || s.log.contains { $0.hasPrefix("Mine") && $0.hasSuffix("fainted!") })
    }

    func testReplacementWaitsForThePlayerThenTheBattleContinues() async throws {
        let s = try session([mon("a", hp: 10), mon("b")], [mon("foe", speed: 99, moves: [move("nuke", power: 250)])],
                            opponent: ScriptedOpponent([]))
        await s.start()
        await s.choose(.move(0))
        XCTAssertTrue(s.awaitingReplacement)
        XCTAssertFalse(s.canChoose)
        XCTAssertEqual(s.message, "Choose your next Pokémon.")
        await s.choose(.move(0))
        XCTAssertTrue(s.awaitingReplacement, "moves are ignored until a replacement is picked")
        await s.replace(with: 1)
        XCTAssertTrue(s.canChoose)
        XCTAssertEqual(s.display.active[BattleSide.a.rawValue], 1)
        XCTAssertEqual(s.message, "What will B do?")
    }

    func testForfeitLosesAndOpponentFailureCountsAsTheirForfeit() async throws {
        let s = try session([mon("a")], [mon("b")], opponent: ScriptedOpponent([]))
        await s.start()
        await s.forfeit()
        XCTAssertEqual(s.outcome, .lost)
        XCTAssertEqual(s.log.last, "You forfeited.")

        let broken = ScriptedOpponent([])
        broken.fails = true
        let t = try session([mon("a")], [mon("b")], opponent: broken)
        await t.start()
        await t.choose(.move(0))
        XCTAssertEqual(t.outcome, .won)
        XCTAssertEqual(t.log.last, "The opponent forfeited!")
    }

    func testRematchStartsFreshWithTheSameTeams() async throws {
        let s = try session([mon("a")], [mon("b", hp: 1)], opponent: ScriptedOpponent([]))
        await s.start()
        await s.choose(.move(0))
        XCTAssertEqual(s.outcome, .won)
        await s.rematch()
        XCTAssertNil(s.outcome)
        XCTAssertTrue(s.canChoose)
        XCTAssertEqual(s.state[.b].current.hp, 1)
        XCTAssertEqual(s.log.count, 2, "the log restarts with the send-out lines")
    }

    func testAbandonedSessionIgnoresFurtherInput() async throws {
        let s = try session([mon("a")], [mon("b")], opponent: ScriptedOpponent([]))
        await s.start()
        s.abandon()
        await s.choose(.move(0))
        XCTAssertEqual(s.state.turn, 1)
    }

    func testLinesUseTranslatedNamesAndMarkTheOpposingSide() async throws {
        let s = BattleSession(myTeam: try team([mon("a", names: ["ja-hrkt": "ピカチュウ", "en": "Pikachu"])]),
                              opponentTeam: try team([mon("b", names: ["en": "Eevee"])]), seed: 1,
                              opponent: ScriptedOpponent([]), language: .ja, pace: .zero,
                              names: { $0 == PokemonNameResource(kind: .move, name: "tackle") ? ["ja-hrkt": "たいあたり"] : nil })
        await s.start()
        XCTAssertEqual(s.lines(for: .usedMove(.a, move: "tackle")), ["ピカチュウの たいあたり！"])
        XCTAssertEqual(s.lines(for: .fainted(.b, index: 0)), ["あいての Eeveeは たおれた！"])
        XCTAssertEqual(s.moveName("thunder-shock"), "Thunder Shock", "untranslated moves fall back to a readable id")
        XCTAssertEqual(s.typeName(BattleTypeChart.typeless), "—")
        XCTAssertEqual(s.lines(for: .damaged(.b, amount: 1, hp: 1, effectiveness: 4, critical: false)), [],
                       "a neutral, non-critical hit has no line of its own")
    }

    func testInputDuringPlaybackIsIgnoredAndClosingStopsPlayback() async throws {
        let opponent = SuspendingOpponent()
        let s = try session([mon("a"), mon("a2")], [mon("b")], opponent: opponent)
        await s.start()
        let turn = Task { await s.choose(.move(0)) }
        while !opponent.waiting { await Task.yield() }
        XCTAssertTrue(s.isPlaying)
        XCTAssertFalse(s.canChoose)
        await s.choose(.switchTo(1))
        await s.forfeit()
        await s.rematch()
        XCTAssertNil(s.outcome, "forfeit is ignored while a turn plays")
        XCTAssertEqual(s.log.count, 2, "rematch is ignored while a turn plays")

        s.abandon()
        opponent.release()
        await turn.value
        XCTAssertEqual(s.log.count, 2, "a closed window plays nothing further")
        XCTAssertFalse(s.isPlaying)
    }

    func testEveryEventHasTheExpectedLine() async throws {
        let s = try session([mon("a")], [mon("b")], opponent: ScriptedOpponent([]))
        await s.start()
        let expected: [(BattleEvent, [String])] = [
            (.noMovesLeft(.a), ["A has no moves left!"]),
            (.missed(.b), ["The opposing B’s attack missed!"]),
            (.noEffect(target: .b), ["It doesn’t affect the opposing B…"]),
            (.damaged(.b, amount: 9, hp: 1, effectiveness: 8, critical: true), ["A critical hit!", "It’s super effective!"]),
            (.damaged(.a, amount: 1, hp: 9, effectiveness: 2, critical: false), ["It’s not very effective…"]),
            (.healed(.a, amount: 1, hp: 9), ["A regained health!"]),
            (.recoil(.a, amount: 1, hp: 9), ["A is damaged by recoil!"]),
            (.statChanged(.b, stat: "evasion", change: -2), ["The opposing B’s evasiveness harshly fell!"]),
            (.statLimit(.a, stat: "attack", rising: true), ["A’s Attack won’t go any higher!"]),
            (.failed(.a), ["But it failed!"]),
            (.forfeited(.b), ["The opponent forfeited!"]),
            (.ended(winner: nil), []),
        ]
        for (event, lines) in expected { XCTAssertEqual(s.lines(for: event), lines, "\(event)") }
    }

    func testDrawAndMissingNamesAreHandled() async throws {
        let recoilNuke = move("final-gambit", power: 250)
        let doubleEdge = BattleMove(name: "double-edge", type: "normal", power: 250, accuracy: nil, pp: 5, priority: 0,
                                    damageClass: .physical, target: "selected-pokemon", category: "damage", drain: -100)
        let s = try session([mon("a", hp: 20, speed: 90, moves: [doubleEdge])],
                            [mon("b", hp: 20, moves: [recoilNuke], names: [:])], opponent: ScriptedOpponent([]))
        await s.start()
        XCTAssertEqual(s.name(.b, 0), "#25", "a species without names falls back to its dex number")
        await s.choose(.move(0))
        XCTAssertEqual(s.outcome, .draw)
        XCTAssertEqual(s.message, "It’s a draw!")
    }

    func testMatchCopyKeepsEveryPlaceholderInEveryLanguage() {
        let a = "ZQXA", b = "ZQXB"
        for language in AppLanguage.allCases {
            let l = L(language)
            for (member, text, needles) in [
                ("opposing", l.battleOpposing(a), [a]), ("whatWillDo", l.battleWhatWillDo(a), [a]),
                ("go", l.battleGo(a), [a]), ("sentOut", l.battleOpponentSentOut(a), [a]),
                ("used", l.battleUsed(a, b), [a, b]), ("missed", l.battleMissed(a), [a]),
                ("noEffect", l.battleNoEffect(a), [a]), ("fainted", l.battleFainted(a), [a]),
                ("recoil", l.battleRecoil(a), [a]), ("healed", l.battleHealed(a), [a]),
                ("noMoves", l.battleNoMovesLeft(a), [a]),
                ("rise1", l.battleStatChanged(a, b, 1), [a, b]), ("rise2", l.battleStatChanged(a, b, 2), [a, b]),
                ("rise3", l.battleStatChanged(a, b, 4), [a, b]), ("fall1", l.battleStatChanged(a, b, -1), [a, b]),
                ("fall2", l.battleStatChanged(a, b, -2), [a, b]), ("fall3", l.battleStatChanged(a, b, -3), [a, b]),
                ("limitUp", l.battleStatLimit(a, b, rising: true), [a, b]),
                ("limitDown", l.battleStatLimit(a, b, rising: false), [a, b]),
            ] as [(String, String, [String])] {
                for needle in needles {
                    XCTAssertTrue(text.contains(needle), "\(language.rawValue).\(member): \(needle) missing → \(text)")
                }
            }
            XCTAssertNotEqual(l.battleStatChanged(a, b, 1), l.battleStatChanged(a, b, -1), language.rawValue)
            XCTAssertNotEqual(l.battleStatChanged(a, b, 1), l.battleStatChanged(a, b, 2), language.rawValue)
        }
    }
}
