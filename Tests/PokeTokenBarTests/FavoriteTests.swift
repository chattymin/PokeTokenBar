import XCTest
@testable import PokeTokenBar

private struct FavoriteProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

/// A graduated Pokémon is liked on its Pokédex page; the ♥ filter keeps the liked ones in the catch log and the species
/// they went through in the grid (the owner, 2026-11-17: by individual).
@MainActor
final class FavoriteTests: XCTestCase {
    private func store(file: URL? = nil) throws -> (CompanionStore, URL) {
        let suite = "Favorite-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let url = file ?? FileManager.default.temporaryDirectory.appendingPathComponent("\(suite).json")
        if file == nil {
            var state = CompanionState()
            state.installBaselineSet = true
            let caught = Date(timeIntervalSince1970: 1_790_000_000)
            state.dex = [
                DexEntry(id: "leafeon", baseID: 133, finalID: 470, chainOrder: [133, 470], rarity: .rare, caughtAt: caught,
                         profile: .generate(seed: 1)),
                DexEntry(id: "vaporeon", baseID: 133, finalID: 134, chainOrder: [133, 134], rarity: .rare, caughtAt: caught,
                         profile: .generate(seed: 2)),
                DexEntry(id: "raichu", baseID: 25, finalID: 26, chainOrder: [25, 26], rarity: .common, caughtAt: caught),
                DexEntry(id: "sent-off", baseID: 1, finalID: 1, chainOrder: [1], rarity: .common, caughtAt: caught,
                         releasedAt: caught),
            ]
            try JSONEncoder().encode(state).write(to: url)
            addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        }
        return (CompanionStore(provider: FavoriteProvider(), fileURL: url, defaults: defaults), url)
    }

    private func entry(_ s: CompanionStore, _ id: String) throws -> DexEntry {
        try XCTUnwrap(s.state.dex.first { $0.id == id })
    }

    /// A liked species shows alone under the ♥ filter: not the species it evolved from, nor its siblings (the owner,
    /// 2026-11-18: "c'est que ce pokémon là qui m'intéresse").
    func testALikedSpeciesIsKeptByTheFiltersAlone() throws {
        let (s, _) = try store()
        s.toggleFavorite(speciesID: 470)
        XCTAssertTrue(s.isFavorite(speciesID: 470))
        XCTAssertEqual(Set(s.filteredDexSpecies(favoritesOnly: true).map(\.id)), [470])
        XCTAssertEqual(s.filteredDexEntries(favoritesOnly: true).map(\.id), ["leafeon"], "its individuals in the log")
        XCTAssertEqual(s.catchLogItems(favoritesOnly: true).count, 1)
        s.toggleFavorite(speciesID: 470)
        XCTAssertTrue(s.filteredDexEntries(favoritesOnly: true).isEmpty)
    }

    /// A species an evolution went through can be liked too: Eevee, Leafeon's first stage, though no Eevee graduated.
    func testASpeciesAnEvolutionWentThroughCanBeLiked() throws {
        let (s, _) = try store()
        XCTAssertTrue(s.canFavorite(speciesID: 133))
        s.toggleFavorite(speciesID: 133)
        XCTAssertEqual(Set(s.filteredDexSpecies(favoritesOnly: true).map(\.id)), [133])
        XCTAssertTrue(s.filteredDexEntries(favoritesOnly: true).isEmpty, "no individual graduated as Eevee")
        XCTAssertFalse(s.canFavorite(speciesID: 150), "a species never graduated is not liked")
        s.toggleFavorite(speciesID: 150)
        XCTAssertFalse(s.isFavorite(speciesID: 150))
    }

    /// The ♥ filter of the Capsules, the Mints and the team screens keeps the liked species' individuals.
    func testTheFavoritesFilterEveryScreenThatListsThePokemon() throws {
        let (s, _) = try store()
        s.toggleFavorite(speciesID: 470)
        XCTAssertEqual(s.itemTargets(.goldCapsule, query: "", shinyOnly: false, favoritesOnly: true, sort: .strongest).map(\.id),
                       ["leafeon"])
        XCTAssertEqual(s.itemTargets(.mint, query: "", shinyOnly: false, favoritesOnly: true, sort: .strongest).map(\.id),
                       ["leafeon"])
        XCTAssertGreaterThan(s.itemTargets(.goldCapsule, query: "", shinyOnly: false, sort: .strongest).count, 1, "unfiltered, all")
        XCTAssertTrue(s.matches(try entry(s, "leafeon"), .favorite))
        XCTAssertFalse(s.matches(try entry(s, "vaporeon"), .favorite))
    }

    func testTheFavoritesAreSavedAndAnOldSaveHasNone() throws {
        let (s, url) = try store()
        s.toggleFavorite(speciesID: 26)
        let (reloaded, _) = try store(file: url)
        XCTAssertTrue(reloaded.isFavorite(speciesID: 26))
        // A save from before the favorites.
        let old = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
            .filter { $0.key != "favoriteSpecies" }
        try JSONSerialization.data(withJSONObject: old).write(to: url)
        let (before, _) = try store(file: url)
        XCTAssertTrue(before.state.favoriteSpecies.isEmpty)
        XCTAssertEqual(before.state.dex.count, 4)
    }
}
