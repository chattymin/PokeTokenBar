import XCTest
@testable import PokeTokenBar

private enum DexStoreTestError: Error { case offline }

/// Returns lines from memory and fails prefetch so no network is touched.
private struct OfflineProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: baseSpeciesID, tree: EvoNode(speciesID: baseSpeciesID, children: []),
                rarity: .common, names: [baseSpeciesID: ["en": "Mon"]])
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { throw DexStoreTestError.offline }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { throw DexStoreTestError.offline }
}

@MainActor
final class DexCompletionStoreTests: XCTestCase {

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ptb-dex-\(UUID().uuidString).json")
    }

    /// One DexEntry whose chainOrder spans a dex range registers every species in it.
    private func store(withOwnedRange range: ClosedRange<Int>, shiny: Bool = false) throws -> CompanionStore {
        var state = CompanionState()
        state.dex = [DexEntry(baseID: range.lowerBound, finalID: range.upperBound,
                              chainOrder: Array(range), rarity: .common, caughtAt: Date(), isShiny: shiny)]
        let url = tempURL()
        try JSONEncoder().encode(state).write(to: url)
        return CompanionStore(provider: OfflineProvider(), fileURL: url)
    }

    func testEmptyStoreHasNoCompletionsAndIsSeeded() throws {
        let url = tempURL()
        try JSONEncoder().encode(CompanionState()).write(to: url)
        let s = CompanionStore(provider: OfflineProvider(), fileURL: url)
        XCTAssertTrue(s.dexCompletions.allSatisfy { !$0.isComplete })
        XCTAssertTrue(s.earnedDexBadges.isEmpty)
        XCTAssertTrue(s.state.dexCompletionsSeeded, "fresh load seeds the completion tracker")
        XCTAssertTrue(s.state.notifiedDexCompletions.isEmpty)
    }

    func testCompleteRegionIsReportedComplete() throws {
        let s = try store(withOwnedRange: PokedexRegion.kanto.dexRange)
        let kanto = s.dexCompletions.first { $0.region == .kanto }
        XCTAssertEqual(kanto?.owned, 151)
        XCTAssertTrue(kanto?.isComplete ?? false)
        XCTAssertTrue(s.earnedDexBadges.contains(.region(.kanto)))
    }

    /// A save that was already complete before the feature shipped must not fire a notification burst:
    /// seeding records the earned badges as already-notified on first load.
    func testExistingCompletionsAreSeededAsNotifiedWithoutFiring() throws {
        let s = try store(withOwnedRange: PokedexRegion.kanto.dexRange)
        XCTAssertTrue(s.state.dexCompletionsSeeded)
        XCTAssertTrue(s.state.notifiedDexCompletions.contains(DexBadge.region(.kanto).notificationKey))
        // Nothing is "newly earned" after seeding, so a re-check adds no keys and fires nothing.
        let before = s.state.notifiedDexCompletions
        s.checkDexCompletions()
        XCTAssertEqual(s.state.notifiedDexCompletions, before)
    }

    func testRegionFilterReturnsOnlySpeciesInThatGeneration() throws {
        let s = try store(withOwnedRange: 1...200)   // all of Kanto + Johto 152–200
        let johto = s.filteredDexSpecies(region: .johto)
        XCTAssertEqual(johto.count, 49)
        XCTAssertTrue(johto.allSatisfy { PokedexRegion.region(forDexNumber: $0.id) == .johto })
        XCTAssertEqual(s.filteredDexSpecies(region: .kanto).count, 151)
        XCTAssertEqual(s.filteredDexSpecies(region: nil).count, 200)
    }

    func testNationalProgressCountsAcrossAllRegions() throws {
        let s = try store(withOwnedRange: PokedexRegion.nationalRange)
        XCTAssertEqual(s.nationalDexProgress.owned, PokedexRegion.nationalTotal)
        XCTAssertTrue(s.earnedDexBadges.contains(.national))
        XCTAssertTrue(PokedexRegion.allCases.allSatisfy { s.earnedDexBadges.contains(.region($0)) })
    }

    func testCurrentFormsCountUnownLettersWithoutInflatingRegionalSpecies() throws {
        var state = CompanionState()
        let letters = PokemonForm.forms(speciesID: PokemonForm.unownSpeciesID)
        state.dex = letters.dropLast().map { form in
            DexEntry(baseID: 201, finalID: 201, chainOrder: [201], rarity: .rare,
                     caughtAt: Date(), form: form)
        }
        state.dex += PokemonForm.forms(speciesID: 351).map { form in
            DexEntry(baseID: 351, finalID: 351, chainOrder: [351], rarity: .common,
                     caughtAt: Date(), form: form)
        }
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try JSONEncoder().encode(state).write(to: url)
        let partial = CompanionStore(provider: OfflineProvider(), fileURL: url)
        XCTAssertFalse(partial.earnedDexBadges.contains(.unown))

        // The last letter belongs to the active individual, which is owned before graduation.
        state.active = MonState(baseID: 201, pathIDs: [201], stageIndex: 0, usedAtStage: 0,
                                rarity: .rare, totalForms: 1, form: letters.last)
        try JSONEncoder().encode(state).write(to: url)
        let complete = CompanionStore(provider: OfflineProvider(), fileURL: url)
        XCTAssertTrue(complete.earnedDexBadges.contains(.unown))
        XCTAssertEqual(complete.dexCompletions.first { $0.region == .johto }?.owned, 1)
        XCTAssertEqual(complete.dexCompletions.first { $0.region == .hoenn }?.owned, 1)
        XCTAssertEqual(complete.nationalDexProgress.owned, 2)
        XCTAssertEqual(complete.formSpecies(speciesID: 201).filter { $0.hasNormal || $0.isShiny }.count, 28)
        XCTAssertTrue(complete.state.notifiedDexCompletions.contains("unown"))
    }

    func testLegacyImportSeedsExistingCompletionsBeforeANewHatch() async throws {
        try await assertLegacyImportTracksTheNextCompletion(existingKanto: true)
    }

    func testLegacyImportWithoutEarnedBadgesStillEnablesFutureCompletions() async throws {
        try await assertLegacyImportTracksTheNextCompletion(existingKanto: false)
    }

    private func assertLegacyImportTracksTheNextCompletion(existingKanto: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ptb-dex-import-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("companion-state.json")
        let suite = "ptb-dex-import-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(1.0, forKey: "growthDifficulty")

        var legacy = CompanionState()
        let lower = existingKanto ? 1 : 152
        legacy.dex = [DexEntry(baseID: lower, finalID: 250, chainOrder: Array(lower...250),
                               rarity: .common, caughtAt: Date())]
        legacy.eggUsage = PokemonBalance.eggHatchThreshold
        legacy.pendingHatchID = 251 // The final missing Johto species, ready to hatch after import.
        let data = try SaveTransfer.encode(state: legacy, appVersion: "2.5.0", deviceName: "Old Mac", now: Date())
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var oldState = try XCTUnwrap(json["state"] as? [String: Any])
        oldState.removeValue(forKey: "notifiedDexCompletions")
        oldState.removeValue(forKey: "dexCompletionsSeeded")
        json["state"] = oldState
        let envelope = try SaveTransfer.decode(JSONSerialization.data(withJSONObject: json))
        XCTAssertFalse(envelope.state.dexCompletionsSeeded, "the exported save predates completion tracking")

        let store = CompanionStore(provider: OfflineProvider(), fileURL: url, defaults: defaults)
        try store.applySave(envelope, todayTokensByProvider: ["test": 0], todayDate: "2026-11-05", hasUsageData: true)
        let preexisting: Set<String> = existingKanto ? ["region.kanto"] : []
        XCTAssertTrue(store.state.dexCompletionsSeeded)
        XCTAssertEqual(store.state.notifiedDexCompletions, preexisting,
                       "imported completions are seeded rather than announced again")
        let persisted = try JSONDecoder().decode(CompanionState.self, from: Data(contentsOf: url))
        XCTAssertTrue(persisted.dexCompletionsSeeded, "even an empty seed must persist during import")

        await store.hatchIfNeeded()
        XCTAssertEqual(store.state.active?.baseID, 251)
        XCTAssertTrue(store.earnedDexBadges.contains(.region(.johto)))
        XCTAssertEqual(store.state.notifiedDexCompletions, preexisting.union(["region.johto"]),
                       "a newly completed region is announced in the same session without restarting")
        let after = store.state.notifiedDexCompletions
        store.checkDexCompletions()
        XCTAssertEqual(store.state.notifiedDexCompletions, after, "completion is announced once")
    }
}
