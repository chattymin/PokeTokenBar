import XCTest
@testable import PokeTokenBar

// MARK: Fresh egg (swap — the active companion is parked in the box, not released; a new egg hatches)

private struct FreshEggNoProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

@MainActor
final class FreshEggTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    /// Active Pokémon (baseID 10, common 3-form, 200M grown) + 1 dex entry + 1 collected pair + wallet.
    /// active=false means the egg (no active) state.
    private func store(active: Bool = true, shiny: Bool = false, used: Int = 5_000_000_000,
                       spent: Int = 0) -> CompanionStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("egg-\(UUID().uuidString).json")
        let mon = "{\"id\":\"m10\",\"baseID\":10,\"pathIDs\":[10],\"stageIndex\":0,\"usedAtStage\":200000000,"
            + "\"rarity\":\"common\",\"totalForms\":3,\"isShiny\":\(shiny)}"
        let dex = "{\"baseID\":1,\"finalID\":3,\"chainOrder\":[1,2,3],\"rarity\":\"common\"}"
        let json = "{\"installBaselineSet\":true,\"usedSinceInstall\":\(used),\"spentTokens\":\(spent),"
            + "\"lastDate\":\"d\",\"active\":\(active ? mon : "null"),\"dex\":[\(dex)],\"collectedFinals\":[\"1:3\"]}"
        try? json.data(using: .utf8)!.write(to: url)
        return CompanionStore(provider: FreshEggNoProvider(), clock: { self.now }, fileURL: url, rng: SeededRNG(seed: 7))
    }

    func testPriceIsOneBillion() { XCTAssertEqual(FreshEgg.price, 1_000_000_000) }

    /// [core] Buying an egg parks the active in the box (NOT released) with its growth preserved and
    /// starts a fresh egg immediately. The dex and probability weighting are untouched.
    func testBuyFreshEggParksActiveInBoxAndIncubates() {
        let s = store(used: 5_000_000_000, spent: 0)
        let dexCountBefore = s.state.dex.count
        XCTAssertTrue(s.hasActive)

        XCTAssertTrue(s.buyFreshEgg())

        XCTAssertNil(s.state.active, "active slot is now the fresh egg")
        XCTAssertTrue(s.isEgg)
        XCTAssertEqual(s.state.box.count, 1, "the previous companion is parked in the box")
        XCTAssertEqual(s.state.box.last?.baseID, 10)
        XCTAssertEqual(s.state.box.last?.usedAtStage, 200_000_000, "its growth is preserved")
        XCTAssertFalse(s.state.box.last?.isComplete ?? true, "parked, not graduated")
        XCTAssertEqual(s.state.eggUsage, 0, "fresh egg from scratch")
        XCTAssertEqual(s.state.dex.count, dexCountBefore, "nothing is released into the dex")
        XCTAssertEqual(s.state.spentTokens, FreshEgg.price, "wallet charged 1B")
        XCTAssertEqual(s.availableTokens, 5_000_000_000 - FreshEgg.price)
    }

    /// A guaranteed (premium) egg sets the rarity floor on the freshly incubating egg.
    func testGuaranteedEggSetsTierOnFreshEgg() {
        let s = store(used: 10_000_000_000)
        XCTAssertTrue(s.buyEgg(.uncommon))
        XCTAssertNil(s.state.active)
        XCTAssertEqual(s.state.eggTier, .uncommon)
        XCTAssertEqual(s.state.spentTokens, FreshEgg.price(guaranteeing: .uncommon))
    }

    /// After buying, the active slot is an egg — you can't buy again until it hatches.
    func testCannotBuyAgainWhileIncubating() {
        let s = store(used: 10_000_000_000)
        XCTAssertTrue(s.buyFreshEgg())
        XCTAssertFalse(s.hasActive)
        XCTAssertFalse(s.canBuyFreshEgg, "no active to park behind the next egg")
        XCTAssertFalse(s.buyFreshEgg())
        XCTAssertEqual(s.state.spentTokens, FreshEgg.price, "charged only once")
    }

    /// The parked species stays in the Pokédex (the box counts toward it) — nothing is lost.
    func testParkedSpeciesStaysInDex() {
        let s = store()
        XCTAssertTrue(s.dexSpecies.contains { $0.id == 10 }, "raising → shown")
        XCTAssertTrue(s.buyFreshEgg())
        XCTAssertTrue(s.dexSpecies.contains { $0.id == 10 }, "still shown — parked in the box, not released")
    }

    /// Buying an egg does not touch collectedFinals (probability weighting).
    func testBuyingEggDoesNotCollect() {
        let s = store()
        XCTAssertTrue(s.buyFreshEgg())
        XCTAssertFalse(s.state.collectedFinals.contains { $0.hasPrefix("10:") },
                       "the parked species is not added to the collected set")
    }

    /// In the egg state (no active) there is nothing to park, so buying is blocked.
    func testCannotBuyWhenEgg() {
        let s = store(active: false, used: 5_000_000_000)
        XCTAssertFalse(s.hasActive)
        XCTAssertFalse(s.canBuyFreshEgg)
        XCTAssertFalse(s.buyFreshEgg())
        XCTAssertEqual(s.state.spentTokens, 0, "no-op")
    }

    /// Insufficient funds → blocked; the active stays.
    func testCannotBuyWithoutFunds() {
        let s = store(used: 500_000_000)   // below 1B
        XCTAssertFalse(s.canBuyFreshEgg)
        XCTAssertFalse(s.buyFreshEgg())
        XCTAssertNotNil(s.state.active, "active retained")
        XCTAssertEqual(s.state.spentTokens, 0)
    }

    /// A shiny active is NOT released — it is parked in the box (kept), and a new egg starts.
    func testBuyingEggParksShinyInBox() {
        let s = store(shiny: true)
        XCTAssertTrue(s.currentIsShiny)
        XCTAssertTrue(s.buyFreshEgg())
        XCTAssertNil(s.state.active, "the shiny is parked, not active")
        XCTAssertEqual(s.state.box.last?.isShiny, true, "the shiny is kept in the box")
    }
}
