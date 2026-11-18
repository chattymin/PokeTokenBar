import XCTest
@testable import PokeTokenBar

private struct LegendProvider: PokeProviding {
    var entries: [BaseSpecies]
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        let legendary = entries.first { $0.id == baseSpeciesID }?.isLegendary == true
        return EvoLine(baseID: baseSpeciesID, tree: EvoNode(speciesID: baseSpeciesID, children: []),
                       rarity: legendary ? .legendary : .common, names: [:])
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { entries }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { entries.first { $0.id == id } }
}

/// Each region whose every species has graduated earns a Legendary Egg, claimed region by region on one Artifacts
/// card; the egg sends off the current Pokémon for one that hatches a legendary or mythical Pokémon, any of them.
@MainActor
final class LegendaryEggTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_790_000_000)
    /// Two common bases, a legendary and a mythical.
    private let bases = [BaseSpecies(id: 1, captureRate: 45), BaseSpecies(id: 4, captureRate: 45),
                         BaseSpecies(id: 144, captureRate: 3, isUnbreedableLegendary: true),
                         BaseSpecies(id: 151, captureRate: 45, isUnbreedableLegendary: true)]

    private func graduated(_ ids: some Sequence<Int>) -> [DexEntry] {
        ids.map { DexEntry(baseID: $0, finalID: $0, chainOrder: [$0], rarity: .common, caughtAt: date) }
    }

    private func raising(_ id: Int) -> MonState {
        MonState(baseID: id, pathIDs: [id], stageIndex: 0, usedAtStage: 0, rarity: .common, totalForms: 1)
    }

    private func store(seed: UInt64 = 1, _ edit: (inout CompanionState) -> Void) throws -> CompanionStore {
        var st = CompanionState()
        st.installBaselineSet = true
        st.lastDate = "2026-10-23"
        edit(&st)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("legend-\(UUID().uuidString).json")
        try JSONEncoder().encode(st).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return CompanionStore(provider: LegendProvider(entries: bases), clock: { self.date }, fileURL: url,
                              rng: SeededRNG(seed: seed))
    }

    /// Nine regions, each asking for every one of its species, Ditto included in Kanto; an artifact, in the Bag's
    /// Artifacts too.
    func testEveryRegionIsATierOfAllItsSpecies() throws {
        let goals = try XCTUnwrap(ItemKind.legendaryEgg.regionGoals)
        XCTAssertEqual(goals.map(\.generation), Array(1...9))
        XCTAssertEqual(goals.map(\.goal.needed), [151, 100, 135, 107, 156, 72, 88, 96, 120])
        XCTAssertTrue(goals[0].goal.species.contains(132), "Ditto counts in Kanto")
        XCTAssertTrue(ItemKind.legendaryEgg.isRegional)
        XCTAssertFalse(ItemKind.legendaryEgg.isPassive)
        XCTAssertEqual(ItemKind.legendaryEgg.collectorGroup, .legendaryArtifacts)
        XCTAssertEqual(BagView.Section.of(.legendaryEgg), .raising, "an egg to use, with the eggs (2026-11-09)")
        XCTAssertEqual(try store { _ in }.regionTiers(.legendaryEgg).count, 9)
    }

    /// Kanto complete earns one egg, once; Johto then earns a second. A species missing, or only in the Pokédex
    /// because it is being raised or was sent off, keeps the region from counting.
    func testEachCompleteRegionEarnsOneEgg() throws {
        let withoutDitto = try store { $0.dex = self.graduated((1...151).filter { $0 != 132 }) }
        XCTAssertFalse(withoutDitto.isUnlocked(.legendaryEgg))
        XCTAssertFalse(withoutDitto.regionTiers(.legendaryEgg).contains(where: \.isReady))

        let raisingMew = try store {
            $0.dex = self.graduated(1...150)
            $0.active = self.raising(151)
        }
        XCTAssertTrue(raisingMew.registeredSpeciesIDs.contains(151))
        XCTAssertFalse(raisingMew.isUnlocked(.legendaryEgg), "the Pokémon being raised has not graduated")
        XCTAssertFalse(raisingMew.claimAchievement(.legendaryEgg))

        var releasedMew = graduated([151])[0]
        releasedMew.releasedAt = date
        let sentOff = try store { $0.dex = self.graduated(1...150) + [releasedMew] }
        XCTAssertFalse(sentOff.isUnlocked(.legendaryEgg), "a released Pokémon has not graduated")

        let kanto = try store { $0.dex = self.graduated(1...151) }
        XCTAssertEqual(kanto.regionTiers(.legendaryEgg).map(\.isReady), [true] + Array(repeating: false, count: 8))
        XCTAssertTrue(kanto.claimAchievement(.legendaryEgg))
        XCTAssertEqual(kanto.itemCount(.legendaryEgg), 1)
        XCTAssertFalse(kanto.claimAchievement(.legendaryEgg), "Kanto earns one egg")
        XCTAssertFalse(kanto.isClaimed(.legendaryEgg), "eight regions left")

        var st = kanto.state
        st.dex += graduated(152...251)
        let johto = try store { $0 = st }
        XCTAssertGreaterThan(johto.claimAllAchievements(), 0)
        XCTAssertEqual(johto.itemCount(.legendaryEgg), 2, "one more for Johto")
        XCTAssertTrue(johto.isRegionTierClaimed(.legendaryEgg, generation: 2))
    }

    /// The egg sends off the current Pokémon for an egg drawn as the Legendary Egg, which hatches a legendary or
    /// mythical Pokémon: any of them, never a common one. Without a Pokémon to send off it cannot be used.
    func testTheEggHatchesALegendaryOrMythical() async throws {
        let empty = try store { $0.inventory = [ItemKind.legendaryEgg.rawValue: 1] }
        XCTAssertFalse(empty.canUseLegendaryEgg())

        var hatched = Set<Int>()
        for seed: UInt64 in 1...24 {
            let s = try store(seed: seed) {
                $0.active = self.raising(25)
                $0.inventory = [ItemKind.legendaryEgg.rawValue: 1]
            }
            XCTAssertTrue(s.useLegendaryEgg())
            XCTAssertEqual(s.itemCount(.legendaryEgg), 0)
            XCTAssertNil(s.state.active)
            XCTAssertEqual(s.state.dex.last?.finalID, 25, "the companion is sent off, not lost")
            XCTAssertEqual(s.eggGuarantee, .legendary)
            XCTAssertEqual(s.eggKind, .tier(.legendary))
            s.setEggUsageForTesting(s.eggHatchThreshold)
            await s.hatchIfNeeded()
            let id = try XCTUnwrap(s.state.active?.baseID, "seed \(seed)")
            XCTAssertTrue([144, 151].contains(id), "seed \(seed): hatched \(id)")
            XCTAssertFalse(s.state.eggFromLegendaryEgg, "consumed by the hatch")
            hatched.insert(id)
        }
        XCTAssertEqual(hatched, [144, 151], "a legendary and a mythical both come out")

        // Without the egg, the commons hatch as usual.
        var plain = Set<Int>()
        for seed: UInt64 in 1...8 {
            let s = try store(seed: seed) { _ in }
            s.setEggUsageForTesting(s.eggHatchThreshold)
            await s.hatchIfNeeded()
            plain.formUnion(s.state.active.map { [$0.baseID] } ?? [])
        }
        XCTAssertFalse(plain.isDisjoint(with: [1, 4]))
    }

    /// The hatch consumes the mark, a stone's egg never carries it, and an older save, without it, has no Legendary
    /// Egg in incubation.
    func testTheMarkGoesWithItsEgg() async throws {
        let older = try JSONDecoder().decode(CompanionState.self, from: JSONEncoder().encode(CompanionState()))
        XCTAssertFalse(older.eggFromLegendaryEgg)
        let s = try store {
            $0.active = self.raising(25)
            $0.inventory = [ItemKind.legendaryEgg.rawValue: 1, ItemKind.fireStone.rawValue: 1]
        }
        XCTAssertTrue(s.useLegendaryEgg())
        XCTAssertTrue(s.state.eggFromLegendaryEgg)
        s.setEggUsageForTesting(s.eggHatchThreshold)
        await s.hatchIfNeeded()
        XCTAssertNotNil(s.state.active)
        XCTAssertNil(s.eggGuarantee, "a Pokémon, no egg")
        XCTAssertTrue(s.useStone(.fireStone))
        XCTAssertFalse(s.state.eggFromLegendaryEgg, "the stone's egg is not the Legendary Egg")
        XCTAssertEqual(s.eggKind, .type(.fire))
    }
}
