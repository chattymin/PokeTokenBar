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
}
