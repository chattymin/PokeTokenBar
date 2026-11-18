import XCTest
@testable import PokeTokenBar

/// The Mint, back on 2026-11-09 (the owner: "sur tous les pokémon comme les capsules, pas sur celui qui se diplôme",
/// "au hasard", "100M", in the chests and bought back by the merchant). Retired on 2026-10-28, when it changed the
/// nature of the Pokémon raised.
@MainActor
final class MintTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func graduated(_ id: String, species: Int, nature: PokemonNature?, released: Bool = false) -> DexEntry {
        var e = DexEntry(baseID: species, finalID: species, chainOrder: [species], rarity: .common,
                         caughtAt: Date(timeIntervalSince1970: 1_690_000_000))
        e.id = id
        e.nature = nature
        if released { e.releasedAt = Date(timeIntervalSince1970: 1_695_000_000) }
        return e
    }

    /// A Pokémon raised (Adamant) and three graduated: a Modest Pikachu, an old Snorlax with no nature, a released
    /// Gengar.
    private func store(mints: Int = 1, used: Int = 0, difficulty: Double = 1, seed: UInt64 = 7,
                       url: URL? = nil) throws -> CompanionStore {
        let file = url ?? FileManager.default.temporaryDirectory.appendingPathComponent("mint-\(UUID().uuidString).json")
        if url == nil || !FileManager.default.fileExists(atPath: file.path) {
            var st = CompanionState()
            st.installBaselineSet = true
            st.lastDate = "d"
            st.usedSinceInstall = used
            st.active = MonState(baseID: 1, pathIDs: [1], stageIndex: 0, usedAtStage: 0, rarity: .common, totalForms: 3,
                                 nature: .adamant)
            st.dex = [graduated("pika", species: 25, nature: .modest), graduated("lax", species: 143, nature: nil),
                      graduated("gone", species: 94, nature: .timid, released: true)]
            st.inventory = mints > 0 ? ["mint": mints] : [:]
            try JSONEncoder().encode(st).write(to: file)
            if url == nil { addTeardownBlock { try? FileManager.default.removeItem(at: file) } }
        }
        return CompanionStore(provider: StubProvider(value: EvoLine(baseID: 1, tree: EvoNode(speciesID: 1, children: []),
                                                                    rarity: .common, names: [:])),
                              clock: { self.now }, fileURL: file, rng: SeededRNG(seed: seed), difficulty: difficulty)
    }

    /// Every graduated Pokémon kept, never the one raised nor a released one.
    func testTheMintReachesTheGraduatedOnly() throws {
        let s = try store()
        XCTAssertEqual(s.mintCandidates.map(\.id), ["pika", "lax"])
        XCTAssertNil(s.useMint(on: "gone"))
        XCTAssertNil(s.useMint(on: "nobody"))
        XCTAssertEqual(s.itemCount(.mint), 1, "nothing spent")
        XCTAssertEqual(s.state.active?.nature, .adamant, "the Pokémon raised keeps its nature")
    }

    /// Another nature each time, at random, one Mint each: a hundred in a row, so a roll that could keep the nature
    /// would show (one in 25 each).
    func testEachMintGivesAnotherNature() throws {
        let s = try store(mints: 100)
        for left in (0..<100).reversed() {
            let before = s.state.dex.first { $0.id == "pika" }?.nature
            let change = try XCTUnwrap(s.useMint(on: "pika"))
            XCTAssertEqual(change.from, before)
            XCTAssertNotEqual(change.to, before)
            XCTAssertEqual(s.state.dex.first { $0.id == "pika" }?.nature, change.to)
            XCTAssertEqual(s.itemCount(.mint), left)
        }
        XCTAssertNil(s.useMint(on: "pika"), "no Mint left")
    }

    /// A Pokémon saved before natures gets one of the 25.
    func testANatureForAnOldSave() throws {
        let s = try store()
        let change = try XCTUnwrap(s.useMint(on: "lax"))
        XCTAssertNil(change.from)
        XCTAssertTrue(PokemonNature.allCases.contains(change.to))
    }

    func testTheNewNatureIsSaved() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mint-saved-\(UUID().uuidString).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let change = try XCTUnwrap(try store(mints: 2, url: url).useMint(on: "pika"))
        let reloaded = try store(url: url)
        XCTAssertEqual(reloaded.state.dex.first { $0.id == "pika" }?.nature, change.to)
        XCTAssertEqual(reloaded.itemCount(.mint), 1)
    }

    /// 20M in the Shop as the players see it, in the raising tab for the graduated Pokémon; bought back for a third.
    func testTheShopSellsItAgain() throws {
        let s = try store(mints: 0, used: 400_000_000, difficulty: PokemonBalance.difficulty)
        XCTAssertFalse(ItemKind.mint.isRetired)
        XCTAssertEqual(s.price(of: .mint), 20_000_000)
        XCTAssertTrue(s.purchasableItems.contains(.mint))
        XCTAssertEqual(CompanionStore.bagSection(of: .mint), .graduated, "beside the raising, no longer the dungeons' (#183)")
        XCTAssertEqual(BagView.Section.of(.mint), .raising)
        XCTAssertTrue(s.buy(.mint))
        XCTAssertEqual(s.itemCount(.mint), 1)
        XCTAssertTrue(TravellingMerchant.wares.contains(.mint))
        XCTAssertEqual(TravellingMerchant.buyBackBase(.mint), Mint.price / 3)
    }

    /// In the chests from T2, one draw as a Revive; never in T1.
    func testTheChestsHoldMintsFromT2() {
        XCTAssertFalse(ExpeditionEngine.itemTable(.t1).contains(.mint))
        for tier: DungeonTier in [.t2, .t3, .t4, .t5] {
            XCTAssertEqual(ExpeditionEngine.itemTable(tier).filter { $0 == .mint }.count, 1, "\(tier)")
        }
    }

    /// Its screen is the Capsules' one, without "most to gain", and lists a Pokémon whatever its IVs.
    func testItsScreenListsEveryGraduatedPokemon() throws {
        let s = try store()
        XCTAssertFalse(CompanionStore.sortOptions(for: .mint).contains(.mostToGain))
        XCTAssertTrue(CompanionStore.sortOptions(for: .goldCapsule).contains(.mostToGain))
        // Every IV at 31: no Capsule's, still a Mint's.
        let i = try XCTUnwrap(s.state.dex.firstIndex { $0.id == "pika" })
        XCTAssertNotNil(s.state.dex[i].profile, "profiles are drawn on load")
        s.changeProfile(of: "pika") { p in for path in CompanionStore.ivKeyPaths { p.ivs[keyPath: path] = 31 } }
        XCTAssertFalse(s.capsuleCandidates.contains { $0.id == "pika" })
        XCTAssertEqual(Set(s.itemTargets(.mint, query: "", shinyOnly: false, sort: .numberAsc).map(\.id)), ["pika", "lax"])
    }

    func testItsWordsInEveryLanguage() {
        for language in AppLanguage.allCases {
            let l = L(language)
            for text in [l.mintUse, l.mintChanged("A", "B"), l.mintChanged(nil, "B"), l.natureNeutral, l.mintNoTarget,
                         l.itemDescription(.mint)] {
                XCTAssertFalse(text.isEmpty, "\(language)")
                XCTAssertFalse(text.contains("\u{2014}") || text.contains("\u{2013}"), "\(language): \(text)")
            }
        }
        XCTAssertEqual(CapsuleScreen.effect(of: .naive, L(.fr)), "+\(L(.fr).statLabel("speed")) −\(L(.fr).statLabel("special-defense"))")
        XCTAssertEqual(CapsuleScreen.effect(of: .hardy, L(.fr)), L(.fr).natureNeutral)
    }
}
