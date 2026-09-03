import XCTest
@testable import PokeTokenBar

// MARK: Fresh egg (queued — the active companion keeps growing; the egg waits for graduation)

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
        let mon = "{\"baseID\":10,\"pathIDs\":[10],\"stageIndex\":0,\"usedAtStage\":200000000,"
            + "\"rarity\":\"common\",\"totalForms\":3,\"isShiny\":\(shiny)}"
        let dex = "{\"baseID\":1,\"finalID\":3,\"chainOrder\":[1,2,3],\"rarity\":\"common\"}"
        let json = "{\"installBaselineSet\":true,\"usedSinceInstall\":\(used),\"spentTokens\":\(spent),"
            + "\"lastDate\":\"d\",\"active\":\(active ? mon : "null"),\"dex\":[\(dex)],\"collectedFinals\":[\"1:3\"]}"
        try? json.data(using: .utf8)!.write(to: url)
        return CompanionStore(provider: FreshEggNoProvider(), clock: { self.now }, fileURL: url, rng: SeededRNG(seed: 7))
    }

    func testPriceIsOneBillion() { XCTAssertEqual(FreshEgg.price, 1_000_000_000) }

    /// [core] Buying an egg does NOT release the active — it keeps growing. The egg is queued and the
    /// wallet is charged; the dex and probability weighting (collectedFinals) are untouched.
    func testBuyFreshEggQueuesWithoutReleasingActive() {
        let s = store(used: 5_000_000_000, spent: 0)
        let dexCountBefore = s.state.dex.count
        let collectedBefore = s.state.collectedFinals
        XCTAssertTrue(s.hasActive)

        XCTAssertTrue(s.buyFreshEgg())

        XCTAssertNotNil(s.state.active, "the active companion keeps growing — it is not released")
        XCTAssertEqual(s.state.active?.baseID, 10)
        XCTAssertFalse(s.isEgg, "still raising the active, not incubating")
        XCTAssertTrue(s.hasQueuedEgg, "the purchased egg is now waiting")
        XCTAssertNil(s.queuedEggTier, "a plain fresh egg has no rarity guarantee")
        XCTAssertEqual(s.state.dex.count, dexCountBefore, "nothing is released into the dex")
        XCTAssertEqual(s.state.collectedFinals, collectedBefore, "probability weighting unchanged")
        XCTAssertEqual(s.state.spentTokens, FreshEgg.price, "wallet charged 1B")
        XCTAssertEqual(s.availableTokens, 5_000_000_000 - FreshEgg.price)
    }

    /// A guaranteed (premium) egg stores its rarity floor on the queued egg.
    func testGuaranteedEggStoresTierOnQueue() {
        let s = store(used: 10_000_000_000)
        XCTAssertTrue(s.buyEgg(.uncommon))
        XCTAssertTrue(s.hasQueuedEgg)
        XCTAssertEqual(s.queuedEggTier, .uncommon)
        XCTAssertEqual(s.state.spentTokens, FreshEgg.price(guaranteeing: .uncommon))
    }

    /// Only one egg can wait at a time — a second purchase is a no-op.
    func testCannotQueueTwoEggs() {
        let s = store(used: 10_000_000_000)
        XCTAssertTrue(s.buyFreshEgg())
        XCTAssertFalse(s.canBuyFreshEgg, "one already queued")
        XCTAssertFalse(s.buyFreshEgg())
        XCTAssertEqual(s.state.spentTokens, FreshEgg.price, "charged only once")
    }

    /// The species stays in the Pokédex — buying an egg no longer removes it (the active is untouched).
    func testActiveSpeciesStaysInDexAfterBuying() {
        let s = store()
        XCTAssertTrue(s.dexSpecies.contains { $0.id == 10 }, "raising → shown in the Pokédex")
        XCTAssertTrue(s.buyFreshEgg())
        XCTAssertTrue(s.dexSpecies.contains { $0.id == 10 }, "still shown — nothing was released")
        XCTAssertTrue(s.dexSpecies.first { $0.id == 10 }?.isRaising ?? false, "still the active buddy")
    }

    /// Buying an egg does not touch collectedFinals (probability weighting).
    func testBuyingEggDoesNotCollect() {
        let s = store()
        XCTAssertTrue(s.buyFreshEgg())
        XCTAssertFalse(s.state.collectedFinals.contains { $0.hasPrefix("10:") },
                       "the active's species is not added to the collected set")
    }

    /// In the egg state (no active) there is nothing to grow behind, so buying is blocked.
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

    /// A shiny active is NOT released by buying an egg — it keeps growing (no discard, no warning).
    func testBuyingEggKeepsShinyActive() {
        let s = store(shiny: true)
        XCTAssertTrue(s.currentIsShiny)
        XCTAssertTrue(s.buyFreshEgg())
        XCTAssertNotNil(s.state.active, "the shiny keeps growing")
        XCTAssertTrue(s.currentIsShiny, "still shiny and active")
    }
}
