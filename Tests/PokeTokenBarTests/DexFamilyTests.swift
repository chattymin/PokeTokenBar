import XCTest
@testable import PokeTokenBar

private struct DexFamilyProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    /// Bulbasaur's line rare (capture rate 45), Pidgey's common.
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [BaseSpecies(id: 1, captureRate: 45), BaseSpecies(id: 16, captureRate: 255)] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

/// A Pokédex page shows the species' evolution family: what it evolves from and into, caught ones to open,
/// the others as silhouettes, in the page's form.
@MainActor
final class DexFamilyTests: XCTestCase {
    /// Graduated individuals, one per chain, in these forms.
    private func store(_ chains: [(chain: [Int], form: PokemonForm?)], shiny: Set<Int> = []) throws -> CompanionStore {
        let suite = "DexFamily-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(suite).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: file) }
        var state = CompanionState()
        state.installBaselineSet = true
        state.dex = chains.enumerated().map { index, item in
            DexEntry(baseID: item.chain[0], finalID: item.chain.last!, chainOrder: item.chain, rarity: .common,
                     caughtAt: Date(timeIntervalSince1970: 1_790_000_000 + Double(index)), isShiny: shiny.contains(index),
                     form: item.form)
        }
        try JSONEncoder().encode(state).write(to: file)
        return CompanionStore(provider: DexFamilyProvider(), fileURL: file, defaults: defaults)
    }

    func testALinearLineShowsBothSidesAndSilhouettesWhatIsNotCaught() throws {
        let store = try store([([4, 5], nil)])
        XCTAssertEqual(store.dexFamily(speciesID: 5, form: nil).nodes, [
            EvoLineItem(.species(4), .done), EvoLineItem(.species(5), .current), EvoLineItem(.species(6), .uncaught),
        ])
        XCTAssertEqual(store.dexFamily(speciesID: 4, form: nil).nodes.map(\.state), [.current, .done, .uncaught])
    }

    func testTheFirstStageWithSeveralEvolutionsEndsTheLineAsABranch() throws {
        let store = try store([([133, 134], nil), ([43, 44, 45], nil)])
        let eevee = store.dexFamily(speciesID: 133, form: nil).nodes
        XCTAssertEqual(eevee.first, EvoLineItem(.species(133), .current))
        guard case .branch(let items)? = eevee.last?.content else { return XCTFail("\(eevee)") }
        XCTAssertEqual(eevee.count, 2)
        XCTAssertEqual(items.count, 8)
        XCTAssertEqual(items.filter(\.isCollected).map(\.speciesID), [134])
        // Oddish: Gloom, then Vileplume or Bellossom.
        let oddish = store.dexFamily(speciesID: 43, form: nil).nodes
        XCTAssertEqual(Array(oddish.prefix(2)), [EvoLineItem(.species(43), .current), EvoLineItem(.species(44), .done)])
        guard case .branch(let gloomInto)? = oddish.last?.content else { return XCTFail("\(oddish)") }
        XCTAssertEqual(gloomInto.map(\.speciesID), [45, 182])
        XCTAssertEqual(gloomInto.map(\.isCollected), [true, false])
        // A branch's page shows its own path only: Vaporeon after Eevee, not its siblings.
        XCTAssertEqual(store.dexFamily(speciesID: 134, form: nil).nodes,
                       [EvoLineItem(.species(133), .done), EvoLineItem(.species(134), .current)])
    }

    func testTheFamilyFollowsThePagesForm() throws {
        let alola = PokemonForm("alola"), galar = PokemonForm("galar"), kanto = PokemonForm("normal")
        let store = try store([([37], alola), ([37, 38], kanto), ([52, 863], galar)])
        // Alolan Vulpix: an Alolan Ninetales was never caught, a Kanto one was.
        let vulpix = store.dexFamily(speciesID: 37, form: alola)
        XCTAssertEqual(vulpix.form, alola)
        XCTAssertEqual(vulpix.nodes.map(\.state), [.current, .uncaught])
        XCTAssertEqual(store.dexFamily(speciesID: 37, form: kanto).nodes.map(\.state), [.current, .done])
        // Galarian Meowth evolves into Perrserker, a Kanto one into Persian.
        XCTAssertEqual(store.dexFamily(speciesID: 52, form: galar).nodes.map(\.content), [.species(52), .species(863)])
        XCTAssertEqual(store.dexFamily(speciesID: 52, form: kanto).nodes.map(\.content), [.species(52), .species(53)])
        // Perrserker has no forms: its Meowth is the Galarian one it evolves from.
        let perrserker = store.dexFamily(speciesID: 863, form: nil)
        XCTAssertEqual(perrserker.form, galar)
        XCTAssertEqual(perrserker.nodes, [EvoLineItem(.species(52), .done), EvoLineItem(.species(863), .current)])
    }

    /// A page's family is drawn shiny only where each species was caught shiny, in the line's form (the owner,
    /// 2026-11-17: a shiny Eevee's page showed every Eeveelution shiny).
    func testTheFamilyIsShinyOnlyWhereCaughtShiny() throws {
        let alola = PokemonForm("alola"), kanto = PokemonForm("normal")
        // A shiny Eevee become Leafeon, a plain Vaporeon, a shiny Alolan Vulpix, a plain Kanto Ninetales.
        let store = try store([([133, 470], nil), ([133, 134], nil), ([37], alola), ([37, 38], kanto)], shiny: [0, 2])
        XCTAssertEqual(store.dexFamilyShinies(store.dexFamily(speciesID: 133, form: nil)), [133, 470])
        XCTAssertEqual(store.dexFamilyShinies(store.dexFamily(speciesID: 134, form: nil)), [133])
        XCTAssertEqual(store.dexFamilyShinies(store.dexFamily(speciesID: 37, form: alola)), [37])
        XCTAssertEqual(store.dexFamilyShinies(store.dexFamily(speciesID: 37, form: kanto)), [])
    }

    /// The page's line leaves the page's species out: its header shows it already (the owner, 2026-11-17).
    func testThePagesLineLeavesItsOwnSpeciesOut() throws {
        let store = try store([([133, 134], nil), ([1, 2, 3], nil)])
        let eevee = PokemonDetailView.lineWithoutPage(store.dexFamily(speciesID: 133, form: nil).nodes)
        XCTAssertEqual(eevee.count, 1)
        guard case .branch(let items)? = eevee.first?.content else { return XCTFail("\(eevee)") }
        XCTAssertEqual(items.count, 8)
        XCTAssertEqual(PokemonDetailView.lineWithoutPage(store.dexFamily(speciesID: 2, form: nil).nodes).map(\.content),
                       [.species(1), .species(3)])
    }

    /// A species never caught has a rarity too, its line's, for the Pokédex's rarity filter (#183).
    @MainActor
    func testEverySpeciesTakesItsLinesRarity() async throws {
        let store = try store([([1, 2], nil)])
        await store.loadHatchIndex()
        let rarities = try XCTUnwrap(store.speciesRarities)
        XCTAssertEqual(rarities[1], BaseSpecies(id: 1, captureRate: 45).rarity)
        XCTAssertEqual(rarities[3], rarities[1], "Venusaur, never caught, rates as its line")
        XCTAssertEqual(rarities[18], BaseSpecies(id: 16, captureRate: 255).rarity, "Pidgeot as Pidgey's line")
        XCTAssertNotEqual(rarities[18], rarities[3])
    }

    func testASpeciesThatNeitherEvolvesNorEvolvesFromAnythingHasNoFamily() throws {
        let store = try store([([128], nil)])
        XCTAssertTrue(store.dexFamily(speciesID: 128, form: nil).nodes.isEmpty)
    }

    /// Back returns through the pages a family opened, then to the grid; leaving the page forgets them.
    func testNavigationWalksBackThroughFamilyPages() {
        let nav = PopoverNavigation()
        nav.tab = .collection
        nav.dexDetailCollectionID = "2"
        let galar = PokemonForm("galar")
        nav.openDexPage(.init(collectionID: "1", form: galar), from: .init(collectionID: "2", form: nil))
        XCTAssertEqual(nav.dexDetailCollectionID, "1")
        XCTAssertEqual(nav.dexDetailForm, galar)
        nav.openDexPage(.init(collectionID: "1", form: nil), from: .init(collectionID: "1", form: galar))
        XCTAssertEqual(nav.dexDetailHistory.count, 1, "the open page is not opened again")
        XCTAssertTrue(nav.returnToPreviousDexPage())
        XCTAssertEqual(nav.dexDetailCollectionID, "2")
        XCTAssertNil(nav.dexDetailForm)
        XCTAssertFalse(nav.returnToPreviousDexPage())
        nav.openDexPage(.init(collectionID: "3", form: nil), from: .init(collectionID: "2", form: nil))
        nav.tab = .home
        XCTAssertNil(nav.dexDetailCollectionID)
        XCTAssertTrue(nav.dexDetailHistory.isEmpty)
        XCTAssertNil(nav.dexDetailForm)
    }
}
