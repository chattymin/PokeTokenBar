import XCTest
@testable import PokeTokenBar

final class BattleRosterTests: XCTestCase {
    private func details(moves: [String] = ["tackle"]) -> PokemonDetails {
        PokemonDetails(speciesID: 1, name: "bulbasaur", height: 7, weight: 69,
                       baseExperience: 64, genderRate: 1, types: ["grass", "poison"],
                       baseStats: ["hp": 45, "attack": 49, "defense": 49,
                                   "special-attack": 65, "special-defense": 65, "speed": 45],
                       abilities: [PokemonAbilityOption(name: "overgrow", slot: 1, isHidden: false)],
                       moves: moves.map {
                           PokemonMoveOption(name: $0, learnMethods: [.init(method: "level-up", level: 1)])
                       })
    }

    private func state(profile: PokemonProfile? = .generate(seed: 8, instanceID: "active")) -> CompanionState {
        var state = CompanionState()
        state.active = MonState(baseID: 1, pathIDs: [1], stageIndex: 0, usedAtStage: 0,
                                rarity: .common, totalForms: 3, nature: .adamant, profile: profile)
        return state
    }

    func testRosterContainsIndividualsRatherThanEveryEvolutionAndDeduplicatesImportedIDs() {
        var state = state()
        state.dex = [
            DexEntry(baseID: 1, finalID: 3, chainOrder: [1, 2, 3], rarity: .common,
                     caughtAt: nil, profile: .generate(seed: 9, instanceID: "collected")),
            DexEntry(baseID: 1, finalID: 1, chainOrder: [1], rarity: .common,
                     caughtAt: nil, profile: .generate(seed: 8, instanceID: "active")),
        ]
        let candidates = BattleRoster.candidates(from: state)
        XCTAssertEqual(candidates.map(\.id), ["active", "collected"])
        XCTAssertEqual(candidates.map(\.speciesID), [1, 3])
        XCTAssertTrue(candidates[0].isActive)
        XCTAssertFalse(candidates[1].isActive)
    }

    func testPreparationEnrichesOnlyCopyAndUsesIndividualStats() throws {
        let state = state()
        let before = try JSONEncoder().encode(state)
        let candidate = try XCTUnwrap(BattleRoster.candidates(from: state).first)
        let combatant = try BattleRoster.prepare(candidate, details: details(), language: .en)
        XCTAssertEqual(combatant.id, "active")
        XCTAssertEqual(combatant.name, "Bulbasaur")
        XCTAssertEqual(combatant.moves.map(\.id), ["tackle"])
        let expected = PokemonStatCalculator.stats(details: details(), profile: candidate.profile!, nature: .adamant)
        XCTAssertEqual(combatant.stats.hp, expected.first { $0.name == "hp" }?.value)
        XCTAssertEqual(candidate.profile?.moves, [])
        XCTAssertNil(candidate.profile?.gender)
        // JSONEncoder's key order is unspecified; compare decoded structures instead.
        let after = try JSONEncoder().encode(state)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: before) as? NSDictionary,
                       try JSONSerialization.jsonObject(with: after) as? NSDictionary)
    }

    func testMissingProfileFailsAndUnsupportedLearnsetUsesPracticeActionWithoutSavingIt() throws {
        let missing = try XCTUnwrap(BattleRoster.candidates(from: state(profile: nil)).first)
        XCTAssertThrowsError(try BattleRoster.prepare(missing, details: details(), language: .en)) {
            XCTAssertEqual($0 as? BattlePreparationError, .missingProfile)
        }
        let candidate = try XCTUnwrap(BattleRoster.candidates(from: state()).first)
        let combatant = try BattleRoster.prepare(candidate, details: details(moves: ["sketch"]), language: .en)
        XCTAssertEqual(combatant.moves, [BattleMoveCatalog.practiceStrike])
        XCTAssertEqual(candidate.profile?.moves, [])
        XCTAssertNoThrow(try BattleState(first: combatant,
                                       second: BattleCombatant(id: "opponent", speciesID: 1, name: "Opponent",
                                                               level: combatant.level, types: combatant.types,
                                                               stats: combatant.stats, moves: combatant.moves), seed: 1))
    }

    func testStatusOnlyLearnsetKeepsPracticeAttack() throws {
        let candidate = try XCTUnwrap(BattleRoster.candidates(from: state()).first)
        let combatant = try BattleRoster.prepare(candidate, details: details(moves: ["growl"]), language: .en)
        XCTAssertTrue(combatant.moves.contains { $0.id == "growl" })
        XCTAssertTrue(combatant.moves.contains { $0.id == BattleMoveCatalog.practiceStrike.id })
        XCTAssertEqual(candidate.profile?.moves, [])
    }

    func testLaterUnsupportedMovesDoNotHideEarlierLegalAttacks() throws {
        var profile = PokemonProfile.generate(seed: 8, instanceID: "active")
        profile.level = 50
        let candidate = try XCTUnwrap(BattleRoster.candidates(from: state(profile: profile)).first)
        let original = details()
        let metadata = PokemonDetails(speciesID: original.speciesID, name: original.name,
                                      height: original.height, weight: original.weight,
                                      baseExperience: original.baseExperience, genderRate: original.genderRate,
                                      types: original.types, baseStats: original.baseStats,
                                      abilities: original.abilities,
                                      moves: ["tackle", "vine-whip", "leech-seed", "sleep-powder", "poison-powder", "stun-spore"].enumerated().map {
                                          PokemonMoveOption(name: $0.element,
                                                            learnMethods: [.init(method: "level-up", level: $0.offset + 1)])
                                      })
        XCTAssertTrue(metadata.levelUpMoves(through: 50).suffix(4).allSatisfy {
            BattleMoveCatalog.move(named: $0.name) == nil
        })
        let combatant = try BattleRoster.prepare(candidate, details: metadata, language: .en)
        XCTAssertEqual(combatant.moves.map(\.id), ["vine-whip"])
        let availability = BattleRoster.moveAvailability(details: metadata, level: 50)
        XCTAssertEqual(availability.knownMoves.map(\.name), ["leech-seed", "sleep-powder", "poison-powder", "stun-spore"])
        XCTAssertEqual(availability.unsupportedKnownMoves.count, 4)
        XCTAssertEqual(availability.recalledMoves.map(\.id), ["vine-whip"])
        XCTAssertFalse(availability.usesPracticeStrike)
        XCTAssertEqual(candidate.profile?.moves, [])
    }

    func testSupportedHistoryNeverGrantsFutureOrUnsupportedEffectMoves() throws {
        let original = details()
        let metadata = PokemonDetails(speciesID: original.speciesID, name: original.name,
                                      height: original.height, weight: original.weight,
                                      baseExperience: original.baseExperience, genderRate: original.genderRate,
                                      types: original.types, baseStats: original.baseStats,
                                      abilities: original.abilities,
                                      moves: [
                                        PokemonMoveOption(name: "rock-throw", learnMethods: [.init(method: "level-up", level: 1)]),
                                        PokemonMoveOption(name: "seed-bomb", learnMethods: [.init(method: "level-up", level: 20)]),
                                        PokemonMoveOption(name: "ember", learnMethods: [.init(method: "level-up", level: 1)]),
                                      ])
        let candidate = try XCTUnwrap(BattleRoster.candidates(from: state()).first)
        let combatant = try BattleRoster.prepare(candidate, details: metadata, language: .en)
        XCTAssertEqual(combatant.moves.map(\.id), ["rock-throw"])
    }

    func testCurrentKnownMovesArePreservedBeforeRecallingHistory() throws {
        let base = details()
        let metadata = PokemonDetails(speciesID: base.speciesID, name: base.name,
                                      height: base.height, weight: base.weight,
                                      baseExperience: base.baseExperience, genderRate: base.genderRate,
                                      types: base.types, baseStats: base.baseStats, abilities: base.abilities,
                                      moves: ["tackle", "growl", "vine-whip", "synthesis", "growth"].enumerated().map {
                                          PokemonMoveOption(name: $0.element,
                                                            learnMethods: [.init(method: "level-up", level: $0.offset + 1)])
                                      })
        let availability = BattleRoster.moveAvailability(details: metadata, level: 50)
        XCTAssertEqual(availability.selectedMoves.map(\.id), ["growl", "vine-whip", "synthesis", "growth"])
        XCTAssertTrue(availability.unsupportedKnownMoves.isEmpty)
        XCTAssertTrue(availability.recalledMoves.isEmpty)
        XCTAssertFalse(availability.usesPracticeStrike)
    }

    func testMetadataMustMatchSelectedSpeciesAndHaveAllStats() throws {
        let candidate = try XCTUnwrap(BattleRoster.candidates(from: state()).first)
        let invalid = PokemonDetails(speciesID: 2, name: "ivysaur", height: 10, weight: 130,
                                     baseExperience: nil, genderRate: 1, types: ["grass"],
                                     baseStats: ["hp": 60], abilities: [], moves: [])
        XCTAssertThrowsError(try BattleRoster.prepare(candidate, details: invalid, language: .en)) {
            XCTAssertEqual($0 as? BattlePreparationError, .invalidMetadata)
        }
    }

    func testInvalidProfileRejectedBeforeComputingStats() throws {
        var profile = PokemonProfile.generate(seed: 8, instanceID: "active")
        profile.level = Int.max
        let candidate = try XCTUnwrap(BattleRoster.candidates(from: state(profile: profile)).first)
        XCTAssertThrowsError(try BattleRoster.prepare(candidate, details: details(), language: .en)) {
            XCTAssertEqual($0 as? BattlePreparationError, .invalidProfile)
        }
    }

    func testDisplayNameUsesLanguageAndEnglishFallback() throws {
        let candidate = try XCTUnwrap(BattleRoster.candidates(from: state(), activeNames: ["en": "Bulbasaur", "ja": "フシギダネ"]).first)
        XCTAssertEqual(candidate.displayName(language: .ja), "フシギダネ")
        XCTAssertEqual(candidate.displayName(language: .de), "Bulbasaur")
    }
}
