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
                DexEntry(id: "leafeon", baseID: 133, finalID: 470, chainOrder: [133, 470], rarity: .rare, caughtAt: caught),
                DexEntry(id: "vaporeon", baseID: 133, finalID: 134, chainOrder: [133, 134], rarity: .rare, caughtAt: caught),
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

    func testALikedPokemonIsKeptByTheFilters() throws {
        let (s, _) = try store()
        s.toggleFavorite(try entry(s, "leafeon"))
        XCTAssertTrue(s.isFavorite(try entry(s, "leafeon")))
        XCTAssertFalse(s.isFavorite(try entry(s, "vaporeon")))
        XCTAssertEqual(s.filteredDexEntries(favoritesOnly: true).map(\.id), ["leafeon"])
        // The grid keeps the species it went through: Eevee and Leafeon, not Vaporeon.
        XCTAssertEqual(Set(s.filteredDexSpecies(favoritesOnly: true).map(\.id)), [133, 470])
        XCTAssertEqual(s.catchLogItems(favoritesOnly: true).count, 1)
        s.toggleFavorite(try entry(s, "leafeon"))
        XCTAssertTrue(s.filteredDexEntries(favoritesOnly: true).isEmpty)
    }

    func testOnlyAGraduatedPokemonIsLiked() throws {
        let (s, _) = try store()
        let sentOff = try entry(s, "sent-off")
        XCTAssertFalse(s.canFavorite(sentOff))
        s.toggleFavorite(sentOff)
        XCTAssertTrue(s.state.favoriteIDs.isEmpty)
        XCTAssertTrue(s.canFavorite(try entry(s, "raichu")))
    }

    func testTheFavoritesAreSavedAndAnOldSaveHasNone() throws {
        let (s, url) = try store()
        s.toggleFavorite(try entry(s, "raichu"))
        let (reloaded, _) = try store(file: url)
        XCTAssertTrue(reloaded.isFavorite(try entry(reloaded, "raichu")))
        // A save from before the favorites.
        let old = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
            .filter { $0.key != "favoriteIDs" }
        try JSONSerialization.data(withJSONObject: old).write(to: url)
        let (before, _) = try store(file: url)
        XCTAssertTrue(before.state.favoriteIDs.isEmpty)
        XCTAssertEqual(before.state.dex.count, 4)
    }
}
