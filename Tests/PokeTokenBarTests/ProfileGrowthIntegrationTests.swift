import XCTest
@testable import PokeTokenBar

private struct GrowthProfileProvider: PokeProviding, PokemonDetailProviding {
    var forms = 3
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        var node = EvoNode(speciesID: forms, children: [])
        if forms > 1 {
            for id in (1..<forms).reversed() { node = EvoNode(speciesID: id, children: [node]) }
        }
        return EvoLine(baseID: 1, tree: node, rarity: .common,
                       names: Dictionary(uniqueKeysWithValues: (1...forms).map { ($0, ["en": "P\($0)"]) }))
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
    func pokemonDetails(speciesID: Int) async throws -> PokemonDetails {
        PokemonDetails(speciesID: speciesID, name: "p", height: 1, weight: 1,
                       baseExperience: nil, genderRate: -1, types: [], baseStats: [:], abilities: [],
                       moves: [PokemonMoveOption(name: "final-\(speciesID)", learnMethods: [
                        PokemonMoveLearnMethod(method: "level-up", level: 100)])])
    }
}

@MainActor
final class ProfileGrowthIntegrationTests: XCTestCase {
    nonisolated(unsafe) private var paths: [URL] = []
    nonisolated(unsafe) private var suites: [String] = []
    override func tearDown() {
        for path in paths { try? FileManager.default.removeItem(at: path) }
        for suite in suites { UserDefaults.standard.removePersistentDomain(forName: suite) }
        super.tearDown()
    }
    private func fixture(_ state: CompanionState = CompanionState(), difficulty: Double = 1,
                         forms: Int = 3) throws -> (CompanionStore, URL, UserDefaults) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("profile-integration-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        paths.append(dir)
        let file = dir.appendingPathComponent("state.json")
        try JSONEncoder().encode(state).write(to: file)
        let suite = "profile-integration-\(UUID())"
        suites.append(suite)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.set(difficulty, forKey: "growthDifficulty")
        return (CompanionStore(provider: GrowthProfileProvider(forms: forms), fileURL: file,
                               dittoDisguiseRollingEnabled: false, defaults: defaults), file, defaults)
    }

    func testEveryDifficultyAndRepeatHatchGraduatesAtLevel100() async throws {
        for difficulty in [0.0001, 1, 20] {
            for forms in 1...3 {
                let (s, _, _) = try fixture(difficulty: difficulty, forms: forms)
                for repeated in [false, true] {
                    await s.hatch(baseID: 1)
                    XCTAssertEqual(s.state.active?.hasGrowthBoost, repeated)
                    XCTAssertEqual(s.state.active?.profile?.level, 5)
                    await s.loadPokemonDetails(speciesID: forms)
                    for _ in 0..<forms { s.applyUsage(s.tokensToNext) }
                    XCTAssertNil(s.state.active)
                    XCTAssertEqual(s.state.dex.last?.profile?.level, 100)
                    XCTAssertEqual(s.state.dex.last?.profile?.growthTokens, 750_000_000)
                    XCTAssertEqual(s.state.dex.last?.profile?.moves.map(\.name), ["final-\(forms)"])
                }
            }
        }
    }

    func testDifficultyChangesAndRestartNeverUndoEarnedLevels() async throws {
        var seed = CompanionState()
        seed.collectedFinals = ["1:1"]
        let (s, file, defaults) = try fixture(seed, difficulty: 0.5, forms: 1)
        await s.hatch(baseID: 1)
        s.applyUsage(93_750_000)
        let profile = try XCTUnwrap(s.state.active?.profile)
        XCTAssertEqual(profile.level, 52)
        s.setGrowthDifficulty(20)
        XCTAssertEqual(s.state.active?.profile?.level, 52)
        let reloaded = CompanionStore(provider: GrowthProfileProvider(forms: 1), fileURL: file, defaults: defaults)
        XCTAssertEqual(reloaded.state.active?.profile?.instanceID, profile.instanceID)
        XCTAssertEqual(reloaded.state.active?.profile?.ivs, profile.ivs)
        XCTAssertEqual(reloaded.state.active?.profile?.level, 52)
        s.setGrowthDifficulty(0.0001)
        XCTAssertNil(s.state.active)
        XCTAssertEqual(s.state.dex.last?.profile?.level, 100)
    }

    func testSmallUsageChunksMatchSingleDeltaAtHardDifficulty() async throws {
        let (small, _, _) = try fixture(difficulty: 20)
        let (large, _, _) = try fixture(difficulty: 20)
        await small.hatch(baseID: 1)
        await large.hatch(baseID: 1)
        for _ in 0..<20 { small.applyUsage(1) }
        large.applyUsage(20)
        XCTAssertEqual(small.state.active?.profile?.growthTokens, 1)
        XCTAssertEqual(small.state.active?.profile?.growthTokens, large.state.active?.profile?.growthTokens)
        XCTAssertEqual(small.state.active?.profile?.level, large.state.active?.profile?.level)
    }

    func testLegacyStageMigrationUsesBoostAndDifficulty() throws {
        var seed = CompanionState()
        seed.active = MonState(baseID: 1, pathIDs: [1, 2], plannedPathIDs: [1, 2, 3],
                               stageIndex: 1, usedAtStage: 6_250_000, rarity: .common,
                               totalForms: 3, hasGrowthBoost: true)
        let (s, _, _) = try fixture(seed, difficulty: 0.1)
        XCTAssertEqual(s.state.active?.profile?.growthTokens, 250_000_000)
        XCTAssertEqual(s.state.active?.profile?.level, 36)
    }

    func testOfflineOverflowCatchesUpWhenLineLoads() async throws {
        var seed = CompanionState()
        seed.active = MonState(baseID: 1, pathIDs: [1], plannedPathIDs: [1, 2, 3],
                               stageIndex: 0, usedAtStage: 0, rarity: .common, totalForms: 3)
        let (s, _, _) = try fixture(seed, difficulty: 0.0001)
        s.applyUsage(75_000)
        XCTAssertEqual(s.state.active?.usedAtStage, 75_000)
        s.update(todayTokensByProvider: [:], todayDate: "day", monthTotal: 0,
                 burnTier: .idle, limitWarning: false, hasUsageData: false)
        for _ in 0..<200 {
            if s.state.active == nil { break }
            await Task.yield()
        }
        XCTAssertNil(s.state.active)
        XCTAssertEqual(s.state.dex.last?.profile?.level, 100)
    }

    func testImportOntoHarderDeviceKeepsEarnedIdentityAndLevel() async throws {
        let (source, _, _) = try fixture(difficulty: 0.1, forms: 1)
        await source.hatch(baseID: 1)
        source.applyUsage(37_500_000)
        let original = try XCTUnwrap(source.state.active?.profile)
        XCTAssertEqual(original.level, 52)
        let data = try SaveTransfer.encode(state: source.state, appVersion: "test",
                                           deviceName: "source", now: Date())
        let (destination, _, _) = try fixture(difficulty: 20, forms: 1)
        try destination.applySave(SaveTransfer.decode(data), todayTokensByProvider: [:],
                                  todayDate: "day", hasUsageData: false)
        XCTAssertEqual(destination.state.active?.profile?.instanceID, original.instanceID)
        XCTAssertEqual(destination.state.active?.profile?.ivs, original.ivs)
        XCTAssertEqual(destination.state.active?.profile?.level, 52)
        for _ in 0..<200 {
            if destination.currentLine != nil { break }
            await Task.yield()
        }
        destination.applyUsage(destination.tokensToNext)
        XCTAssertEqual(destination.state.dex.last?.profile?.level, 100)
    }

    func testRareCandyFinalizesGraduationProfile() async throws {
        var seed = CompanionState()
        seed.inventory[ItemKind.rareCandy.rawValue] = 1
        let (s, _, _) = try fixture(seed, difficulty: 0.0001)
        await s.hatch(baseID: 1)
        await s.loadPokemonDetails(speciesID: 3)
        _ = s.useRareCandy()
        XCTAssertNil(s.state.active)
        XCTAssertEqual(s.state.dex.last?.profile?.level, 100)
        XCTAssertEqual(s.state.dex.last?.profile?.moves.map(\.name), ["final-3"])
    }
}
