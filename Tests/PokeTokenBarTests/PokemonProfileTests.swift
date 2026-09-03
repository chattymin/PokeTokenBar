import XCTest
@testable import PokeTokenBar

private let profileDetails = PokemonDetails(
    speciesID: 79,
    name: "slowpoke",
    height: 12,
    weight: 360,
    baseExperience: 63,
    genderRate: 8,
    types: ["water", "psychic"],
    baseStats: [
        "hp": 90, "attack": 65, "defense": 65,
        "special-attack": 40, "special-defense": 40, "speed": 15,
    ],
    abilities: [PokemonAbilityOption(name: "oblivious", slot: 1, isHidden: false)],
    moves: [
        PokemonMoveOption(name: "tackle", learnMethods: [
            PokemonMoveLearnMethod(method: "level-up", level: 1)]),
        PokemonMoveOption(name: "curse", learnMethods: [
            PokemonMoveLearnMethod(method: "level-up", level: 1)]),
        PokemonMoveOption(name: "yawn", learnMethods: [
            PokemonMoveLearnMethod(method: "level-up", level: 1)]),
        PokemonMoveOption(name: "growl", learnMethods: [
            PokemonMoveLearnMethod(method: "level-up", level: 5)]),
        PokemonMoveOption(name: "water-gun", learnMethods: [
            PokemonMoveLearnMethod(method: "level-up", level: 9)]),
        PokemonMoveOption(name: "surf", learnMethods: [
            PokemonMoveLearnMethod(method: "machine", level: 0)]),
    ])

private func profileDetails(genderRate: Int,
                            abilities: [PokemonAbilityOption]) -> PokemonDetails {
    PokemonDetails(speciesID: 999, name: "test", height: 10, weight: 100,
                   baseExperience: nil, genderRate: genderRate, types: ["normal"],
                   baseStats: ["hp": 50], abilities: abilities, moves: [])
}

final class PokemonProfileLogicTests: XCTestCase {
    func testGenerationIsDeterministicAndIVsStayInRange() {
        let a = PokemonProfile.generate(seed: 42, instanceID: "same")
        let b = PokemonProfile.generate(seed: 42, instanceID: "same")
        XCTAssertEqual(a, b)
        for iv in [a.ivs.hp, a.ivs.attack, a.ivs.defense,
                   a.ivs.specialAttack, a.ivs.specialDefense, a.ivs.speed] {
            XCTAssertTrue((0...31).contains(iv))
        }
    }

    func testEnrichmentRollsPersistentIdentityAndFourLegalMoves() {
        var profile = PokemonProfile.generate(seed: 7, instanceID: "p")
        profile.level = 9
        profile.enrich(with: profileDetails)

        XCTAssertEqual(profile.gender, .female)
        XCTAssertEqual(profile.abilityName, "oblivious")
        XCTAssertEqual(profile.abilitySlot, 1)
        XCTAssertEqual(profile.moves.count, 4)
        XCTAssertTrue(profile.moves.contains { $0.name == "water-gun" })
        XCTAssertFalse(profile.moves.contains { $0.name == "surf" }, "TM moves are listed but not auto-equipped")

        let first = profile
        profile.enrich(with: profileDetails)
        XCTAssertEqual(profile, first, "enrichment must not reroll an individual")
    }

    func testNatureChangesCalculatedNonHPStat() throws {
        var neutral = PokemonProfile.generate(seed: 1, instanceID: "neutral")
        neutral.level = 50
        let stats = PokemonStatCalculator.stats(details: profileDetails, profile: neutral, nature: .adamant)
        let attack = try XCTUnwrap(stats.first { $0.name == "attack" })
        let specialAttack = try XCTUnwrap(stats.first { $0.name == "special-attack" })
        let neutralAttack = ((2 * 65 + neutral.ivs.attack) * 50) / 100 + 5
        let neutralSpecial = ((2 * 40 + neutral.ivs.specialAttack) * 50) / 100 + 5
        XCTAssertEqual(attack.value, Int((Double(neutralAttack) * 1.1).rounded(.down)))
        XCTAssertEqual(specialAttack.value, Int((Double(neutralSpecial) * 0.9).rounded(.down)))
    }

    func testActualStatScaleExpandsForHighHPPokemon() {
        XCTAssertEqual(PokemonStatCalculator.displayScaleMaximum(for: [180, 299]), 300)
        XCTAssertEqual(PokemonStatCalculator.displayScaleMaximum(for: [651, 300]), 700)
    }

    func testEveryNatureChangesExactlyItsExpectedNumberOfStats() {
        let neutral: Set<PokemonNature> = [.hardy, .docile, .serious, .bashful, .quirky]
        let affectedStats = PokemonStatCalculator.order.filter { $0 != "hp" }
        XCTAssertEqual(PokemonNature.allCases.count, 25)
        for nature in PokemonNature.allCases {
            let raised = affectedStats.filter { nature.modifier(for: $0) == 1.1 }
            let lowered = affectedStats.filter { nature.modifier(for: $0) == 0.9 }
            if neutral.contains(nature) {
                XCTAssertTrue(raised.isEmpty && lowered.isEmpty, "\(nature) must be neutral")
            } else {
                XCTAssertEqual(raised.count, 1, "\(nature) must raise exactly one stat")
                XCTAssertEqual(lowered.count, 1, "\(nature) must lower exactly one stat")
                XCTAssertNotEqual(raised.first, lowered.first)
            }
        }
    }

    func testGrowthMapsHatchToFiveAndGraduationToHundred() {
        var profile = PokemonProfile.generate(seed: 1, instanceID: "growth")
        XCTAssertEqual(profile.level, 5)
        profile.applyGrowth(PokemonBalance.graduationTotal(.common), rarity: .common)
        XCTAssertEqual(profile.level, 100)
    }

    func testGenderlessAndMaleBranchesAreResolved() {
        var genderless = PokemonProfile.generate(seed: 1, instanceID: "genderless")
        genderless.enrich(with: profileDetails(genderRate: -1, abilities: []))
        XCTAssertEqual(genderless.gender, .genderless)

        var male = PokemonProfile.generate(seed: 1, instanceID: "male")
        male.enrich(with: profileDetails(genderRate: 0, abilities: []))
        XCTAssertEqual(male.gender, .male)
    }

    func testHiddenAbilityRollCanSelectAHiddenSlot() {
        let details = profileDetails(genderRate: -1, abilities: [
            PokemonAbilityOption(name: "hidden-one", slot: 3, isHidden: true),
            PokemonAbilityOption(name: "hidden-two", slot: 4, isHidden: true),
        ])
        var profile = PokemonProfile.generate(seed: 115, instanceID: "hidden-roll")
        profile.enrich(with: details)
        XCTAssertEqual(profile.abilityName, "hidden-two")
        XCTAssertEqual(profile.abilitySlot, 4)
        XCTAssertTrue(profile.abilityIsHidden)
    }

    func testAllHiddenAbilitiesFallBackWhenRareRollMisses() {
        let details = profileDetails(genderRate: -1, abilities: [
            PokemonAbilityOption(name: "first-hidden", slot: 2, isHidden: true),
            PokemonAbilityOption(name: "second-hidden", slot: 3, isHidden: true),
        ])
        var profile = PokemonProfile.generate(seed: 1, instanceID: "hidden-fallback")
        profile.enrich(with: details)
        XCTAssertEqual(profile.abilityName, "first-hidden")
        XCTAssertEqual(profile.abilitySlot, 2)
        XCTAssertTrue(profile.abilityIsHidden)
    }

    func testAbilityNameFallbackChainRepairsPersistedSelections() {
        let normal = PokemonAbilityOption(name: "normal", slot: 1, isHidden: false)
        let hidden = PokemonAbilityOption(name: "hidden", slot: 3, isHidden: true)

        var slotOnly = PokemonProfile.generate(seed: 2, instanceID: "slot-only")
        slotOnly.abilitySlot = 1
        slotOnly.abilityIsHidden = true
        slotOnly.enrich(with: profileDetails(genderRate: -1, abilities: [normal]))
        XCTAssertEqual(slotOnly.abilityName, "normal", "same slot should repair a stale hidden flag")
        XCTAssertFalse(slotOnly.abilityIsHidden)

        var normalFallback = PokemonProfile.generate(seed: 3, instanceID: "normal-fallback")
        normalFallback.abilitySlot = 99
        normalFallback.abilityIsHidden = true
        normalFallback.enrich(with: profileDetails(genderRate: -1, abilities: [hidden, normal]))
        XCTAssertEqual(normalFallback.abilityName, "normal")
        XCTAssertFalse(normalFallback.abilityIsHidden)

        var hiddenFallback = PokemonProfile.generate(seed: 4, instanceID: "hidden-fallback-chain")
        hiddenFallback.abilitySlot = 99
        hiddenFallback.enrich(with: profileDetails(genderRate: -1, abilities: [hidden]))
        XCTAssertEqual(hiddenFallback.abilityName, "hidden")
        XCTAssertTrue(hiddenFallback.abilityIsHidden)
    }

    func testSpeciesIdentityRebaseKeepsIVsButClearsDisguiseMetadata() {
        var profile = PokemonProfile.generate(seed: 7, instanceID: "ditto")
        profile.enrich(with: profileDetails)
        let ivs = profile.ivs

        profile.rebaseForSpeciesIdentity(growthTokens: 175_000_000, rarity: .rare)

        XCTAssertEqual(profile.instanceID, "ditto")
        XCTAssertEqual(profile.ivs, ivs)
        XCTAssertNil(profile.gender)
        XCTAssertNil(profile.abilitySlot)
        XCTAssertNil(profile.abilityName)
        XCTAssertFalse(profile.abilityIsHidden)
        XCTAssertTrue(profile.moves.isEmpty)
        XCTAssertEqual(profile.growthTokens, 175_000_000)
        XCTAssertEqual(profile.level, 10)
    }
}

final class PokemonDetailNormalizationTests: XCTestCase {
    func testParserKeepsOnlySupportedVersionGroupBeforeCaching() {
        let supported = PokemonMoveVersionDTO(
            level_learned_at: 5,
            move_learn_method: NamedRef(name: "level-up", url: nil),
            version_group: NamedRef(name: PokemonDetails.preferredVersionGroup, url: nil))
        let unsupported = PokemonMoveVersionDTO(
            level_learned_at: 9,
            move_learn_method: NamedRef(name: "level-up", url: nil),
            version_group: NamedRef(name: "scarlet-violet", url: nil))
        let moves = [
            PokemonMoveDTO(move: NamedRef(name: "mixed", url: nil),
                           version_group_details: [supported, unsupported]),
            PokemonMoveDTO(move: NamedRef(name: "future-only", url: nil),
                           version_group_details: [unsupported]),
        ]

        let normalized = PokeAPIClient.normalizedMoves(moves)

        XCTAssertEqual(normalized.map(\.name), ["mixed"])
        XCTAssertEqual(normalized[0].learnMethods,
                       [PokemonMoveLearnMethod(method: "level-up", level: 5)])
    }
}

/// 이식 세이브는 다른 기기에서 온 파일이고 `PokemonProfile` 은 합성 디코더라 파일이 말하는 값을 그대로
/// 받는다. 즉 `SaveTransfer.sanitized` 가 손편집된 세이브와 상세 화면 사이의 유일한 관문이다.
/// `moves` 클램프는 특히 tragend — 배운 기술 목록은 lazy 가 아닌 `VStack` 에 그려지므로 무제한 배열은
/// 전부 즉시 생성된다. active/dex 두 호출부를 각각 검증한다(한쪽만 통과하는 걸 구별하기 위해).
final class PokemonProfileSanitizationTests: XCTestCase {
    private func hostileProfile() -> PokemonProfile {
        var profile = PokemonProfile.generate(seed: 5, instanceID: "hostile")
        profile.instanceID = ""
        profile.level = 9_999
        profile.growthTokens = .max
        profile.ivs = PokemonIVs(hp: 999, attack: -5, defense: 31,
                                 specialAttack: 64, specialDefense: -1, speed: 500)
        profile.moves = (0..<400).map {
            PokemonKnownMove(name: "move-\($0)-" + String(repeating: "x", count: 200),
                             learnedAtLevel: 900 + $0)
        }
        return profile
    }

    private func assertClamped(_ profile: PokemonProfile?, _ label: String) throws {
        let p = try XCTUnwrap(profile, label)
        XCTAssertEqual(p.level, 100, "\(label): level")
        XCTAssertEqual(p.growthTokens, SaveTransfer.maxTokenValue, "\(label): growthTokens")
        XCTAssertEqual([p.ivs.hp, p.ivs.attack, p.ivs.defense,
                        p.ivs.specialAttack, p.ivs.specialDefense, p.ivs.speed],
                       [31, 0, 31, 31, 0, 31], "\(label): IVs")
        XCTAssertEqual(p.moves.count, 4, "\(label): unbounded move lists render eagerly")
        XCTAssertTrue(p.moves.allSatisfy { $0.name.count <= 80 }, "\(label): move name length")
        XCTAssertTrue(p.moves.allSatisfy { (0...100).contains($0.learnedAtLevel) },
                      "\(label): move level")
        XCTAssertFalse(p.instanceID.isEmpty, "\(label): instanceID")
    }

    func testImportClampsHostileActiveProfile() throws {
        var state = CompanionState()
        state.active = MonState(baseID: 79, pathIDs: [79], stageIndex: 0, usedAtStage: 0,
                                rarity: .common, totalForms: 1, profile: hostileProfile())

        try assertClamped(SaveTransfer.sanitized(state).active?.profile, "active")
    }

    func testImportClampsHostileDexProfile() throws {
        var state = CompanionState()
        state.dex = [DexEntry(id: "imported", baseID: 79, finalID: 79, chainOrder: [79],
                              rarity: .common, caughtAt: Date(), profile: hostileProfile())]

        try assertClamped(SaveTransfer.sanitized(state).dex.first?.profile, "dex")
    }
}

private struct ProfileLineProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: baseSpeciesID, tree: EvoNode(speciesID: baseSpeciesID, children: []),
                rarity: .common, names: [baseSpeciesID: ["en": "Slowpoke"]])
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

private struct ProfileDetailProvider: PokemonDetailProviding {
    func pokemonDetails(speciesID: Int) async throws -> PokemonDetails { profileDetails }
}

private enum ProfileDetailTestError: Error { case unavailable }

private struct ThrowingProfileDetailProvider: PokemonDetailProviding {
    func pokemonDetails(speciesID: Int) async throws -> PokemonDetails {
        throw ProfileDetailTestError.unavailable
    }
}

private actor RecordingProfileProvider: PokeProviding, PokemonDetailProviding {
    private var requestedDetails: [Int] = []

    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: baseSpeciesID, tree: EvoNode(speciesID: baseSpeciesID, children: []),
                rarity: .common, names: [baseSpeciesID: ["en": "Test"]])
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func pokemonDetails(speciesID: Int) async throws -> PokemonDetails {
        requestedDetails.append(speciesID)
        return PokemonDetails(speciesID: speciesID, name: "test", height: 10, weight: 100,
                              baseExperience: nil, genderRate: -1, types: ["normal"],
                              baseStats: ["hp": 50], abilities: [], moves: [])
    }
    func detailIDs() -> [Int] { requestedDetails }
}

private actor SuspendedProfileProvider: PokeProviding, PokemonDetailProviding {
    private var continuation: CheckedContinuation<PokemonDetails, Never>?

    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: baseSpeciesID, tree: EvoNode(speciesID: baseSpeciesID, children: []),
                rarity: .common, names: [baseSpeciesID: ["en": "Test"]])
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func pokemonDetails(speciesID: Int) async throws -> PokemonDetails {
        await withCheckedContinuation { continuation = $0 }
    }
    func isDetailSuspended() -> Bool { continuation != nil }
    func resumeDetails() {
        let pending = continuation
        continuation = nil
        pending?.resume(returning: profileDetails)
    }
}

@MainActor
final class PokemonProfileMigrationTests: XCTestCase {
    func testCorruptProfileRegeneratesWithoutDroppingPokemon() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("profile-recovery-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("companion-state.json")
        let json = #"{"active":{"baseID":79,"pathIDs":[79],"plannedPathIDs":[79],"stageIndex":0,"usedAtStage":10,"rarity":"common","totalForms":1,"profile":"broken"},"dex":[{"id":"kept","baseID":1,"finalID":1,"chainOrder":[1],"rarity":"common","profile":"broken"}]}"#
        try Data(json.utf8).write(to: file)

        let store = CompanionStore(provider: ProfileLineProvider(), fileURL: file)
        XCTAssertEqual(store.state.active?.currentID, 79)
        XCTAssertNotNil(store.state.active?.profile)
        XCTAssertEqual(store.state.dex.first?.id, "kept")
        XCTAssertNotNil(store.state.dex.first?.profile)
    }

    func testLegacyActiveAndDexProfilesMigrateOnceAndAreBackedUp() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("profile-migration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("companion-state.json")

        var legacy = CompanionState()
        legacy.active = MonState(baseID: 79, pathIDs: [79], stageIndex: 0, usedAtStage: 10_000,
                                 rarity: .common, totalForms: 2, nature: .sassy)
        legacy.dex = [DexEntry(id: "old-catch", baseID: 1, finalID: 3,
                               chainOrder: [1, 2, 3], rarity: .common, caughtAt: Date())]
        try JSONEncoder().encode(legacy).write(to: file)

        let store = CompanionStore(provider: ProfileLineProvider(), detailProvider: ProfileDetailProvider(),
                                   fileURL: file)
        XCTAssertNotNil(store.state.active?.profile)
        XCTAssertEqual(store.state.dex.first?.profile?.level, 100)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: dir.appendingPathComponent("companion-state.pre-profiles-v1.json").path))

        let instanceID = try XCTUnwrap(store.state.active?.profile?.instanceID)
        await store.loadPokemonDetails(speciesID: 79)
        XCTAssertEqual(store.state.active?.profile?.instanceID, instanceID)
        XCTAssertEqual(store.state.active?.profile?.gender, .female)
        XCTAssertEqual(store.state.active?.profile?.abilityName, "oblivious")

        let reloaded = CompanionStore(provider: ProfileLineProvider(), fileURL: file)
        XCTAssertEqual(reloaded.state.active?.profile?.instanceID, instanceID,
                       "a migrated individual must not be regenerated on restart")
    }

    func testReleasedLegacyEntryUsesReachedChainAsGrowthUpperBound() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("released-profile-migration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("companion-state.json")
        var legacy = CompanionState()
        legacy.dex = [DexEntry(id: "released", baseID: 1, finalID: 2,
                               chainOrder: [1, 2], rarity: .common, caughtAt: Date(),
                               releasedAt: Date())]
        try JSONEncoder().encode(legacy).write(to: file)

        let store = CompanionStore(provider: ProfileLineProvider(), fileURL: file)
        let profile = try XCTUnwrap(store.state.dex.first?.profile)
        let expected = CompanionStore.reconstructedGrowthTokens(
            rarity: .common, totalForms: 2, completedStages: 1, currentStageUsage: 0)
        let actualThreeFormThreshold = PokemonBalance.phaseThreshold(
            rarity: .common, totalForms: 3, stageIndex: 0)
        XCTAssertEqual(profile.growthTokens, expected)
        XCTAssertGreaterThan(expected, actualThreeFormThreshold,
                             "without planned totalForms the estimate is intentionally an upper bound")
        XCTAssertGreaterThan(profile.level, 5)
        XCTAssertLessThan(profile.level, 100)
    }

    func testPokemonIndividualsIncludesSyntheticActiveAndMatchingStoredIndividuals() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("profile-individuals-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("companion-state.json")
        var saved = CompanionState()
        saved.active = MonState(
            baseID: 79, pathIDs: [79], stageIndex: 0, usedAtStage: 0, rarity: .common,
            totalForms: 1, profile: PokemonProfile.generate(seed: 1, instanceID: "active-instance"))
        saved.dex = [
            DexEntry(id: "stored-new", baseID: 79, finalID: 79, chainOrder: [79], rarity: .common,
                     caughtAt: Date(timeIntervalSince1970: 20),
                     profile: PokemonProfile.generate(seed: 2, instanceID: "stored-new")),
            DexEntry(id: "stored-old", baseID: 79, finalID: 79, chainOrder: [79], rarity: .common,
                     caughtAt: Date(timeIntervalSince1970: 10),
                     profile: PokemonProfile.generate(seed: 3, instanceID: "stored-old")),
        ]
        try JSONEncoder().encode(saved).write(to: file)
        let store = CompanionStore(provider: ProfileLineProvider(), fileURL: file)

        let individuals = store.pokemonIndividuals(speciesID: 79)

        XCTAssertEqual(individuals.map(\.id), ["active-79-79", "stored-new", "stored-old"])
        XCTAssertEqual(individuals.first?.profile?.instanceID, "active-instance")
        XCTAssertNotEqual(individuals.first?.id, individuals.first?.profile?.instanceID,
                          "the active row has a synthetic UI identity but keeps its profile identity")
        XCTAssertTrue(store.pokemonIndividuals(speciesID: 80).isEmpty)
    }

    func testDetailLoadEnrichesEveryMatchingStoredIndividual() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("profile-dex-enrichment-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("companion-state.json")
        var saved = CompanionState()
        saved.dex = [
            DexEntry(id: "one", baseID: 79, finalID: 79, chainOrder: [79], rarity: .common,
                     caughtAt: Date(), profile: PokemonProfile.generate(seed: 1, instanceID: "one")),
            DexEntry(id: "two", baseID: 79, finalID: 79, chainOrder: [79], rarity: .common,
                     caughtAt: Date(), profile: PokemonProfile.generate(seed: 2, instanceID: "two")),
        ]
        try JSONEncoder().encode(saved).write(to: file)
        let store = CompanionStore(provider: ProfileLineProvider(), detailProvider: ProfileDetailProvider(),
                                   fileURL: file)

        await store.loadPokemonDetails(speciesID: 79)

        XCTAssertEqual(store.state.dex.compactMap(\.profile?.gender), [.female, .female])
        XCTAssertTrue(store.state.dex.allSatisfy { $0.profile?.abilityName == "oblivious" })
        XCTAssertTrue(store.state.dex.allSatisfy { !($0.profile?.moves.isEmpty ?? true) })
    }

    func testDetailFetchFailureSetsRetryStateAndClearsLoadingState() async {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("profile-detail-error-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let store = CompanionStore(provider: ProfileLineProvider(),
                                   detailProvider: ThrowingProfileDetailProvider(), fileURL: file)

        await store.loadPokemonDetails(speciesID: 79)

        XCTAssertTrue(store.failedPokemonDetailIDs.contains(79))
        XCTAssertFalse(store.loadingPokemonDetailIDs.contains(79))
        XCTAssertNil(store.pokemonDetailsByID[79])
    }

    func testStartupWarmupLoadsOnlyTheActivePokemon() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("profile-warmup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("companion-state.json")
        var saved = CompanionState()
        saved.active = MonState(baseID: 79, pathIDs: [79], stageIndex: 0, usedAtStage: 0,
                                rarity: .common, totalForms: 1)
        saved.dex = [DexEntry(id: "old", baseID: 1, finalID: 3,
                              chainOrder: [1, 2, 3], rarity: .common, caughtAt: Date())]
        try JSONEncoder().encode(saved).write(to: file)
        let provider = RecordingProfileProvider()
        let store = CompanionStore(provider: provider, fileURL: file)

        await store.preparePokemonProfiles()

        let detailIDs = await provider.detailIDs()
        XCTAssertEqual(detailIDs, [79])
    }

    func testPathNormalizationLoadsDetailsForTheRecoveredCurrentSpecies() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("profile-normalization-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("companion-state.json")
        var saved = CompanionState()
        saved.active = MonState(baseID: 79, pathIDs: [79, 999], plannedPathIDs: [79, 999],
                                stageIndex: 1, usedAtStage: 0, rarity: .common, totalForms: 2)
        try JSONEncoder().encode(saved).write(to: file)
        let provider = RecordingProfileProvider()
        let store = CompanionStore(provider: provider, fileURL: file)

        store.update(todayTokensByProvider: ["test": 0], todayDate: "d1", monthTotal: 0,
                     burnTier: .idle, limitWarning: false, hasUsageData: true)
        for _ in 0..<200 {
            if !(await provider.detailIDs()).isEmpty { break }
            await Task.yield()
        }

        XCTAssertEqual(store.currentSpeciesID, 79)
        let detailIDs = await provider.detailIDs()
        XCTAssertEqual(detailIDs, [79])
        XCTAssertEqual(store.state.active?.profile?.gender, .genderless)
    }

    func testLineLoadReleasesHatchingLockBeforeDetailRequestCompletes() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("profile-lock-lifetime-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("companion-state.json")
        var saved = CompanionState()
        saved.active = MonState(baseID: 79, pathIDs: [79], stageIndex: 0, usedAtStage: 0,
                                rarity: .common, totalForms: 1)
        try JSONEncoder().encode(saved).write(to: file)
        let provider = SuspendedProfileProvider()
        let store = CompanionStore(provider: provider, fileURL: file)

        store.update(todayTokensByProvider: ["test": 0], todayDate: "d1", monthTotal: 0,
                     burnTier: .idle, limitWarning: false, hasUsageData: true)
        for _ in 0..<200 {
            if await provider.isDetailSuspended() { break }
            await Task.yield()
        }

        let detailIsSuspended = await provider.isDetailSuspended()
        XCTAssertTrue(detailIsSuspended)
        XCTAssertFalse(store.isHatching, "detail enrichment must not extend the evolution-line lock")
        await provider.resumeDetails()
    }
}
