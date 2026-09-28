import XCTest
@testable import PokeTokenBar

private enum IdenticalTradeStubError: Error { case unavailable }

private struct IdenticalTradeOfflineProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw IdenticalTradeStubError.unavailable }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { throw IdenticalTradeStubError.unavailable }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { throw IdenticalTradeStubError.unavailable }
}

/// Trading for a mon identical to one already owned — same species, nature, moves and stats.
@MainActor
final class IdenticalTradeTests: XCTestCase {
    private func fixture(state: CompanionState = CompanionState()) throws -> CompanionStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("identical-trade-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("companion-state.json")
        try JSONEncoder().encode(state).write(to: url)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "identical-trade-\(UUID())"))
        return CompanionStore(provider: IdenticalTradeOfflineProvider(), fileURL: url,
                              dittoDisguiseRollingEnabled: false, defaults: defaults)
    }

    /// One shared profile so every entry below has identical moves, IVs and stats. A graduated entry
    /// takes its id from `profile.instanceID`, so entries seeded here carry that pairing too.
    private func sharedProfile(instanceID: String) -> PokemonProfile {
        PokemonProfile.generate(seed: 42, instanceID: instanceID)
    }

    private func entry(id: String, instanceID: String? = nil) -> DexEntry {
        DexEntry(id: id, baseID: 1, finalID: 3, chainOrder: [1, 2, 3], rarity: .rare,
                 caughtAt: Date(timeIntervalSince1970: 0), nature: .adamant,
                 profile: sharedProfile(instanceID: instanceID ?? id))
    }

    // MARK: Individuals stay distinct

    /// Receiving a mon identical in every visible respect, but a distinct individual.
    func testReceivingIdenticalTwinKeepsBothIndividuals() throws {
        var seed = CompanionState()
        seed.dex = [entry(id: "mine"), entry(id: "payment")]
        let store = try fixture(state: seed)

        _ = try store.applyTradeCommit(sending: .dexEntry(entry(id: "payment")),
                                       receiving: .dexEntry(entry(id: "twin")))

        XCTAssertEqual(Set(store.state.dex.map(\.id)), ["mine", "twin"])
        XCTAssertEqual(store.pokemonIndividuals(speciesID: 3).count, 2,
                       "both identical individuals must stay visible on the species page")
    }

    /// The dex collapses by species, so an identical twin must not inflate the collected count.
    func testIdenticalTwinDoesNotInflateSpeciesCount() throws {
        var seed = CompanionState()
        seed.dex = [entry(id: "mine"), entry(id: "payment")]
        let store = try fixture(state: seed)
        let speciesBefore = store.dexSpecies.count

        _ = try store.applyTradeCommit(sending: .dexEntry(entry(id: "payment")),
                                       receiving: .dexEntry(entry(id: "twin")))

        XCTAssertEqual(store.dexSpecies.count, speciesBefore)
    }

    // MARK: Identity reissue

    /// The partner returns an entry we still hold — a one-sided commit left the same id on both
    /// devices. The incoming id must be reissued or a later trade deletes two mons at once.
    func testReceivingAnEntryWithAnIdWeStillHoldReissuesTheId() throws {
        var seed = CompanionState()
        seed.dex = [entry(id: "shared"), entry(id: "payment")]
        let store = try fixture(state: seed)

        _ = try store.applyTradeCommit(sending: .dexEntry(entry(id: "payment")),
                                       receiving: .dexEntry(entry(id: "shared")))

        XCTAssertEqual(store.state.dex.count, 2)
        XCTAssertEqual(Set(store.state.dex.map(\.id)).count, 2, "the incoming id must be reissued")
    }

    /// A graduated entry's id comes from `profile.instanceID`, so reissuing one without the other
    /// leaves the traded copy pointing at another individual's instance identity.
    func testReissuedEntryKeepsIdAndInstanceIDInSync() throws {
        var seed = CompanionState()
        seed.dex = [entry(id: "shared"), entry(id: "payment")]
        let store = try fixture(state: seed)

        _ = try store.applyTradeCommit(sending: .dexEntry(entry(id: "payment")),
                                       receiving: .dexEntry(entry(id: "shared")))

        let instanceIDs = store.state.dex.compactMap { $0.profile?.instanceID }
        XCTAssertEqual(instanceIDs.count, 2)
        XCTAssertEqual(Set(instanceIDs).count, 2, "two individuals must not share an instanceID")
        for entry in store.state.dex {
            XCTAssertEqual(entry.id, entry.profile?.instanceID,
                           "a dex entry's id and its profile instanceID must stay equal")
        }
    }

    /// The ids differ but the instance identity still collides — a twin cloned from our own entry
    /// on the partner's device. Checking only the id would let this one through.
    func testInstanceIDCollisionIsReissuedEvenWhenTheIdDiffers() throws {
        var seed = CompanionState()
        seed.dex = [entry(id: "mine", instanceID: "cloned"), entry(id: "payment")]
        let store = try fixture(state: seed)

        _ = try store.applyTradeCommit(sending: .dexEntry(entry(id: "payment")),
                                       receiving: .dexEntry(entry(id: "twin", instanceID: "cloned")))

        let instanceIDs = store.state.dex.compactMap { $0.profile?.instanceID }
        XCTAssertEqual(Set(instanceIDs).count, 2, "the colliding instanceID must be reissued")
        XCTAssertEqual(store.state.dex.count, 2, "reissuing identity must not drop the entry")
    }

    // MARK: Offer eligibility

    /// A released entry is the record of a mon we let go, so it must not appear among the things
    /// we can offer — while still staying in the dex so its species page survives.
    func testReleasedEntriesAreNotOfferable() throws {
        var released = entry(id: "released")
        released.releasedAt = Date(timeIntervalSince1970: 0)
        var seed = CompanionState()
        seed.dex = [entry(id: "graduated"), released]
        let store = try fixture(state: seed)

        XCTAssertEqual(store.tradeOfferableDexEntries.map(\.id), ["graduated"])
        XCTAssertEqual(store.state.dex.count, 2, "the released record itself must stay in the dex")
    }

    // MARK: Commit ordering and the active mon

    /// Giving an entry away and receiving the identical id back in the same trade: remove runs
    /// first, so the entry ends up held exactly once rather than duplicated or lost.
    func testTradingAnEntryForItsOwnIdLeavesExactlyOneCopy() throws {
        var seed = CompanionState()
        seed.dex = [entry(id: "same")]
        let store = try fixture(state: seed)

        _ = try store.applyTradeCommit(sending: .dexEntry(entry(id: "same")),
                                       receiving: .dexEntry(entry(id: "same")))

        XCTAssertEqual(store.state.dex.count, 1)
        XCTAssertEqual(store.state.dex[0].id, "same")
    }

    /// Receiving an in-progress mon identical to the one being raised still warns before it
    /// overwrites — an identical twin destroys the local mon just the same.
    func testReceivingIdenticalActiveMonStillWarnsAndOverwrites() throws {
        var seed = CompanionState()
        seed.active = MonState(baseID: 1, pathIDs: [1, 2, 3], stageIndex: 1, usedAtStage: 500,
                               rarity: .rare, totalForms: 3)
        let store = try fixture(state: seed)
        let twin = MonState(baseID: 1, pathIDs: [1, 2, 3], stageIndex: 1, usedAtStage: 500,
                            rarity: .rare, totalForms: 3)

        XCTAssertNotNil(store.tradeOverwriteWarning(forReceiving: .activeMon(twin)))
        _ = try store.applyTradeCommit(sending: .activeMon(try XCTUnwrap(seed.active)),
                                       receiving: .activeMon(twin))
        XCTAssertEqual(store.state.active?.usedAtStage, 500)
        XCTAssertNil(store.state.eggTier)
    }
}
