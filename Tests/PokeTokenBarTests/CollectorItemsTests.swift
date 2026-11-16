import XCTest
@testable import PokeTokenBar

// MARK: Collector items (achievement rewards unlocked by the Pokédex)

private func collectorNode(_ id: Int, _ children: [EvoNode] = []) -> EvoNode {
    EvoNode(speciesID: id, children: children)
}

/// Dratini (147) is the one rare line, for the Reins of Unity.
private func collectorLine(base: Int) -> EvoLine {
    EvoLine(baseID: base, tree: collectorNode(base), rarity: base == 147 ? .rare : .common,
            names: [base: ["en": "P\(base)", "ko": "포\(base)", "fr": "P\(base)"]])
}

/// Base species index for stone eggs: one candidate per type the tests ask for.
private struct CollectorStubProvider: PokeProviding {
    let entries = [
        BaseSpecies(id: 1, captureRate: 45),    // Bulbasaur (Grass/Poison)
        BaseSpecies(id: 4, captureRate: 45),    // Charmander (Fire)
        BaseSpecies(id: 7, captureRate: 45),    // Squirtle (Water)
        BaseSpecies(id: 25, captureRate: 190),  // Pikachu (Electric)
    ]
    func line(baseSpeciesID: Int) async throws -> EvoLine { collectorLine(base: baseSpeciesID) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { entries }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { entries.first { $0.id == id } }
}

@MainActor
final class CollectorItemsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let rich = 1_000_000_000_000

    private func store(used: Int = 0, dex: [DexEntry] = [], active: MonState? = nil,
                       inventory: [String: Int] = [:], collectedFinals: Set<String> = [],
                       claimed: Set<String> = [], growthDifficulty: Double? = nil) -> CompanionStore {
        var st = CompanionState()
        st.installBaselineSet = true
        st.usedSinceInstall = used
        st.lastDate = "2026-10-05"
        st.dex = dex
        st.active = active
        st.inventory = inventory
        st.collectedFinals = collectedFinals
        st.claimedAchievements = claimed
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("collector-\(UUID().uuidString).json")
        try? JSONEncoder().encode(st).write(to: url)
        return CompanionStore(provider: CollectorStubProvider(), clock: { self.now }, fileURL: url,
                              rng: SeededRNG(seed: 1), difficulty: growthDifficulty ?? PokemonBalance.difficulty)
    }

    private func entry(_ chain: [Int], rarity: Rarity = .common, released: Bool = false) -> DexEntry {
        DexEntry(baseID: chain[0], finalID: chain.last!, chainOrder: chain, rarity: rarity, caughtAt: now,
                 releasedAt: released ? now : nil)
    }

    private func entries(_ ids: [Int], rarity: Rarity = .common) -> [DexEntry] {
        ids.map { entry([$0], rarity: rarity) }
    }

    // MARK: Catalogue

    func testCollectorItemsAndAchievements() {
        let s = store()
        XCTAssertEqual(s.collectorItems(in: .evolutionStones).count, 11, "10 stones and the excavation")
        XCTAssertEqual(s.collectorItems(in: .legendaryArtifacts).count, 48,
                       "the Old Amber, the five Dungeons medals, the Battle Forms Medal and the two costume medals with the other artifacts")
        XCTAssertEqual(s.collectorItems(in: .gymBadges).count, 18)
        XCTAssertEqual(s.collectorItems(in: .forms).count, 26, "with Tauros's and Necrozma's, and #135's fourteen")
        XCTAssertEqual(Set(CompanionStore.achievementItems), Set(ItemKind.allCases.filter { $0.collectorGroup != nil }))
        XCTAssertEqual(s.totalAchievementsCount, 298,
                       "10 stones, 39 artifacts and the Legendary Egg's 9 regions, 161 badge regions, 26 forms, 15 digs, "
                       + "16 Dungeons medal steps, 6 Battle Forms Medal steps, 4 Costume Medal steps, 12 Seasons Medal steps")
        XCTAssertEqual(s.purchasableItems, [.mint, .rareCandy, .greatBall, .ultraBall, .shinyCharm],
                       "the Shop sells what main sells, the Mint (back on 2026-11-09) and the dungeons' two balls")

        // An unlocked stone is an achievement to claim, never a Shop item.
        let withFire = store(dex: entries([154, 157, 160]))
        XCTAssertTrue(withFire.isUnlocked(.fireStone))
        XCTAssertEqual(withFire.purchasableItems, [.mint, .rareCandy, .greatBall, .ultraBall, .shinyCharm])
        XCTAssertFalse(withFire.shopEntries.contains(.item(.fireStone)))
        XCTAssertEqual(withFire.unclaimedAchievementsCount, 1)
    }

    func testItemsHaveAppropriatePricesAndUnlockConditions() {
        for kind in ItemKind.allCases {
            if kind == .birthdayEgg || EventEgg(item: kind) != nil || kind.isShopEgg || kind == .fossilEgg {
                // The birthday and event gifts and the Shop's eggs (sold as Shop eggs, not items): neither sold as an
                // item nor an achievement of their own.
                XCTAssertNil(kind.unlock)
                XCTAssertNil(kind.shopPrice)
                XCTAssertFalse(kind.isAchievement)
            } else if kind.isDungeonItem {
                // Found in dungeons, never an achievement; only the Great and Ultra Balls are sold (R12 B), and the
                // Mint (2026-11-09).
                XCTAssertNil(kind.unlock)
                XCTAssertFalse(kind.isAchievement)
                XCTAssertFalse(kind.isPassive, "\(kind) is used up")
                XCTAssertEqual(kind.shopPrice != nil, [.greatBall, .ultraBall, .mint].contains(kind), "\(kind)")
            } else if kind.collectorGroup == nil {
                XCTAssertNil(kind.unlock, "\(kind) is always on sale")
                XCTAssertNotNil(kind.shopPrice, "\(kind) must have a price")
            } else {
                XCTAssertNotNil(kind.unlock, "\(kind) achievement is unlocked by the Pokédex")
                XCTAssertNil(kind.shopPrice, "\(kind) achievement is free to claim, not bought")
                XCTAssertTrue(kind.isAchievement)
                XCTAssertEqual(kind.achievementRewardCount, kind.stoneType != nil ? 5 : 1)
                // An achievement that gives other items (eggs, candies) is never kept in the Bag itself.
                XCTAssertEqual(kind.isPassive,
                               kind.stoneType == nil && !kind.givesOtherItems && ![.typeNullEgg, .legendaryEgg].contains(kind),
                               "stones, eggs and what gives eggs or candies are the only consumable rewards")
            }
        }
    }

    // MARK: Achievement claim gate

    func testLockedAchievementCannotBeClaimed() {
        let s = store(dex: entries([144, 145], rarity: .legendary))
        XCTAssertFalse(s.isUnlocked(.silverWing))
        XCTAssertFalse(s.claimAchievement(.silverWing))
        XCTAssertEqual(s.itemCount(.silverWing), 0)
        XCTAssertEqual(s.state.spentTokens, 0)
    }

    func testCompletingTheGroupUnlocksTheAchievement() {
        let s = store(dex: entries([144, 145, 146], rarity: .legendary))
        XCTAssertTrue(s.isUnlocked(.silverWing))
        XCTAssertEqual(s.unclaimedAchievementsCount, 1)
        XCTAssertTrue(s.claimAchievement(.silverWing))
        XCTAssertEqual(s.itemCount(.silverWing), 1)
        XCTAssertEqual(s.state.spentTokens, 0, "achievements are free to claim")
        XCTAssertFalse(s.claimAchievement(.silverWing), "claimed achievements cannot be claimed again")
        XCTAssertEqual(s.unclaimedAchievementsCount, 0)
    }

    /// Every stage of a graduated chain counts. A released Pokémon stays in the Pokédex but earns nothing: it could
    /// be raised, claimed for, then sent off.
    func testGraduatedChainsCountButNotReleasedOnes() {
        let graduated = store(dex: [entry([1, 2, 3]), entry([4, 5, 6]), entry([7, 8, 9])])
        XCTAssertTrue(graduated.isUnlocked(.leafStone))
        let released = store(dex: [entry([1, 2, 3]), entry([4, 5, 6], released: true), entry([7, 8, 9])])
        XCTAssertTrue(released.registeredSpeciesIDs.contains(6), "the Pokédex keeps it")
        XCTAssertFalse(released.isUnlocked(.leafStone))
        XCTAssertEqual(released.unclaimedAchievementsCount, 0)
    }

    /// The Pokémon being raised is in the Pokédex for the stages it has reached, but earns nothing before it
    /// graduates, even at its last stage.
    func testThePokemonBeingRaisedEarnsNothing() {
        let finalStage = MonState(baseID: 1, pathIDs: [1, 2, 3], stageIndex: 2, usedAtStage: 0, rarity: .common,
                                  totalForms: 3)
        let raising = store(dex: [entry([4, 5, 6]), entry([7, 8, 9])], active: finalStage)
        XCTAssertTrue(raising.registeredSpeciesIDs.isSuperset(of: [1, 2, 3]), "the Pokédex shows it")
        XCTAssertFalse(raising.isUnlocked(.leafStone))
        XCTAssertFalse(raising.claimAchievement(.leafStone))
        XCTAssertTrue(store(dex: [entry([1, 2, 3]), entry([4, 5, 6]), entry([7, 8, 9])]).isUnlocked(.leafStone))
    }

    /// Magma Stone has three goals: the Galar Regis alone unlock it, and goals don't mix.
    func testAlternativeGoalUnlocksOnItsOwn() {
        XCTAssertTrue(store(dex: entries([894, 895], rarity: .legendary)).isUnlocked(.magmaStone))
        XCTAssertTrue(store(dex: entries([377, 378, 379], rarity: .legendary)).isUnlocked(.magmaStone))
        XCTAssertFalse(store(dex: entries([377, 378, 894], rarity: .legendary)).isUnlocked(.magmaStone),
                       "goals don't mix: two Regis of each group is not a full group")
    }

    /// Magma Stone accepts any 4 of the 9 fossil Pokémon.
    func testPartialGoalNeedsOnlyItsCount() {
        XCTAssertFalse(store(dex: entries([139, 141, 142])).isUnlocked(.magmaStone))
        XCTAssertTrue(store(dex: entries([139, 141, 142, 567])).isUnlocked(.magmaStone))
        XCTAssertTrue(store(dex: entries([377, 378, 379], rarity: .legendary)).isUnlocked(.magmaStone))
    }

    /// A badge has one region per generation: every Pokémon of its type from that generation. Dark has no
    /// Kanto region, so its badge has eight; 161 regions in all.
    func testBadgeRegionsFollowTheGenerations() {
        XCTAssertEqual(PokemonTypeData.badgeGenerations(for: .fire), Array(1...9))
        XCTAssertEqual(PokemonTypeData.badgeGenerations(for: .dark), Array(2...9))
        XCTAssertEqual(PokemonTypeData.badgeSpecies(for: .fairy, generation: 1), [35, 36, 39, 40, 122])
        XCTAssertEqual(PokemonTypeData.badgeSpecies(for: .fairy, generation: 2), [173, 174, 175, 176, 183, 184, 209, 210])
        XCTAssertEqual(ItemKind.allCases.compactMap(\.badgeType)
            .map { PokemonTypeData.badgeGenerations(for: $0).count }.reduce(0, +), 161)
        let kanto = store(dex: entries([35, 36, 39, 40, 122])).regionTiers(.fairyBadge)
        XCTAssertEqual(kanto.filter(\.isReady).map(\.generation), [1])
        XCTAssertFalse(store(dex: entries([35, 36, 39, 40])).regionTiers(.fairyBadge).contains(where: \.isReady),
                       "a region needs every one of its Pokémon")
    }

    /// Claiming a badge claims its ready regions; the badge waits in the Bag for the others.
    func testClaimingABadgeClaimsItsReadyRegions() {
        let s = store(dex: entries([35, 36, 39, 40, 122, 173, 174, 175, 176, 183, 184, 209, 210]))
        XCTAssertEqual(s.achievementTally(in: .gymBadges).ready, 2, "Kanto and Johto Fairy")
        XCTAssertTrue(s.claimAchievement(.fairyBadge))
        XCTAssertTrue(s.isRegionTierClaimed(.fairyBadge, generation: 1))
        XCTAssertTrue(s.isRegionTierClaimed(.fairyBadge, generation: 2))
        XCTAssertEqual(s.claimedBadgeTierCount(.fairy), 2)
        XCTAssertEqual(s.itemCount(.fairyBadge), 1)
        XCTAssertFalse(s.isClaimed(.fairyBadge), "seven regions to go")
        XCTAssertEqual(s.achievementTally(in: .gymBadges), CompanionStore.AchievementTally(ready: 0, claimed: 2, total: 161))
        XCTAssertFalse(s.claimAchievement(.fairyBadge), "nothing left to claim")
    }

    /// Badges claimed before regions existed asked for Kanto (Johto for Dark): they become that region.
    func testLegacyBadgesBecomeTheirFirstRegion() {
        let s = store(inventory: [ItemKind.boulderBadge.rawValue: 1, ItemKind.darkBadge.rawValue: 1],
                      claimed: [ItemKind.boulderBadge.rawValue])
        XCTAssertTrue(s.isRegionTierClaimed(.boulderBadge, generation: 1))
        XCTAssertTrue(s.isRegionTierClaimed(.darkBadge, generation: 2))
        XCTAssertFalse(s.state.claimedAchievements.contains(ItemKind.boulderBadge.rawValue))
        XCTAssertEqual(s.claimedBadgeTierCount(.rock), 1)
        // A badge in the Bag through a later region is not mistaken for a Kanto one.
        let later = store(inventory: [ItemKind.volcanoBadge.rawValue: 1], claimed: ["volcanoBadge@9"])
        XCTAssertFalse(later.isRegionTierClaimed(.volcanoBadge, generation: 1))
        XCTAssertEqual(later.claimedBadgeTierCount(.fire), 1)
    }

    /// A species missing from the type table never hatches from a stone egg and ignores badges and the
    /// Griseous Orb, so the table covers every species that can hatch, later generations included.
    func testTypeTableCoversEveryHatchableSpecies() {
        let missing = PokemonAssets.animatedSpeciesIDs.filter { PokemonTypeData.types(forSpeciesID: $0).isEmpty }
        XCTAssertEqual(missing, [])
        for id in 650...1025 {
            XCTAssertFalse(PokemonTypeData.types(forSpeciesID: id).isEmpty, "#\(id)")
        }
        XCTAssertEqual(PokemonTypeData.types(forSpeciesID: 700), [.fairy])            // Sylveon
        XCTAssertEqual(PokemonTypeData.types(forSpeciesID: 1007), [.fighting, .dragon]) // Koraidon
        XCTAssertTrue(PokemonTypeData.species(for: .fairy).contains(669))               // Flabébé, for Moon Stone eggs
    }

    func testAzureFluteNeedsTheSameLegendaryGraduatedTwice() {
        let mewtwo = entry([150], rarity: .legendary)
        let rayquaza = entry([384], rarity: .legendary)
        let releasedMewtwo = entry([150], rarity: .legendary, released: true)
        XCTAssertFalse(store(dex: [mewtwo]).isUnlocked(.legendCharm))
        XCTAssertFalse(store(dex: [mewtwo, rayquaza]).isUnlocked(.legendCharm))
        XCTAssertFalse(store(dex: [mewtwo, releasedMewtwo]).isUnlocked(.legendCharm),
                       "a released copy was never graduated")
        XCTAssertTrue(store(dex: [mewtwo, entry([150], rarity: .legendary)]).isUnlocked(.legendCharm))
    }

    func testUnlockProgressReportsRegisteredSpecies() {
        let s = store(dex: entries([254, 257]))
        let goals = s.unlockProgress(of: .waterStone)
        XCTAssertEqual(goals.count, 1, "one starter trio per stone, no alternative")
        XCTAssertEqual(goals[0].registered, [254, 257])
        XCTAssertEqual(goals[0].count, 2)
        XCTAssertFalse(goals[0].isMet)
        XCTAssertTrue(s.unlockProgress(of: .legendCharm).isEmpty, "the Azure Flute has no species list")
        XCTAssertTrue(s.unlockProgress(of: .rareCandy).isEmpty)
    }

    /// The Shiny Stone guarantees Dragon, the strongest type: it asks for the three Dragon/Flying Pokémon.
    func testShinyStoneNeedsTheSkyDragons() {
        XCTAssertFalse(store(dex: entries([149, 373], rarity: .rare)).isUnlocked(.shinyStone))
        XCTAssertTrue(store(dex: entries([149, 373], rarity: .rare) + entries([384], rarity: .legendary))
            .isUnlocked(.shinyStone))
    }

    /// The first nine stones follow the generations in order: each asks for one region's final starters.
    func testStonesFollowTheStartersOfEachGeneration() {
        let trios: [(ItemKind, [Int])] = [
            (.leafStone, [3, 6, 9]), (.fireStone, [154, 157, 160]), (.waterStone, [254, 257, 260]),
            (.thunderStone, [389, 392, 395]), (.sunStone, [497, 500, 503]), (.moonStone, [652, 655, 658]),
            (.duskStone, [724, 727, 730]), (.iceStone, [812, 815, 818]), (.dawnStone, [908, 911, 914]),
        ]
        for (stone, trio) in trios {
            XCTAssertEqual(stone.unlock, .species([SpeciesGoal(trio)]), "\(stone)")
            XCTAssertFalse(store(dex: entries(Array(trio.dropLast()))).isUnlocked(stone), "\(stone)")
            XCTAssertTrue(store(dex: entries(trio)).isUnlocked(stone), "\(stone)")
        }
        XCTAssertFalse(store(dex: entries([26, 135, 604])).isUnlocked(.thunderStone), "the evolver goals are gone")
        XCTAssertFalse(store(dex: entries([134, 135, 136])).isUnlocked(.waterStone))
    }

    func testLockedStoneAchievementCannotBeClaimed() {
        let s = store(used: rich, active: pikachu)
        XCTAssertFalse(s.claimAchievement(.fireStone))
        XCTAssertEqual(s.itemCount(.fireStone), 0)
        XCTAssertFalse(s.canUseStone(.fireStone), "no stone in the Bag")
        XCTAssertFalse(s.useStone(.fireStone))
        XCTAssertFalse(s.isEgg, "the companion stays")
    }

    func testStoneNeedsACompanionToSendOff() {
        let s = store(dex: entries([154, 157, 160]), inventory: [ItemKind.fireStone.rawValue: 5],
                      claimed: [ItemKind.fireStone.rawValue])
        XCTAssertFalse(s.canUseStone(.fireStone), "an egg is incubating: nothing to send off")
        XCTAssertFalse(s.useStone(.fireStone))
        XCTAssertEqual(s.itemCount(.fireStone), 5, "a refused use keeps the stone")
    }

    /// Stones are used up, so the Bag cannot say whether their achievement was claimed: an empty slot must
    /// not hand out five more.
    func testUsingEveryStoneDoesNotReopenItsAchievement() async {
        let s = store(dex: entries([154, 157, 160]), active: pikachu)
        XCTAssertTrue(s.claimAchievement(.fireStone))
        for _ in 0..<EvolutionStone.achievementReward {
            XCTAssertTrue(s.useStone(.fireStone))
            s.setEggUsageForTesting(s.eggHatchThreshold)
            await s.hatchIfNeeded()
            XCTAssertFalse(s.isEgg)
        }
        XCTAssertTrue(s.isClaimed(.fireStone))
        XCTAssertFalse(s.claimAchievement(.fireStone))
        XCTAssertEqual(s.itemCount(.fireStone), 0)
        XCTAssertEqual(s.unclaimedAchievementsCount, 0)
        XCTAssertEqual(s.claimedAchievementsCount, 1)
        let stones = s.collectorItems(in: .evolutionStones)
        XCTAssertEqual(stones.last, .fireStone, "claimed stones sink to the very bottom")
        XCTAssertEqual(stones.dropLast().last, .excavation, "the Excavation closes what is left to earn")
    }

    /// Badges and artifacts claimed before the ledger existed are only in the Bag: they stay claimed.
    func testPassiveRewardOwnedBeforeTheLedgerStaysClaimed() {
        let s = store(dex: entries([380, 381], rarity: .legendary), inventory: [ItemKind.soulDew.rawValue: 1])
        XCTAssertTrue(s.state.claimedAchievements.isEmpty)
        XCTAssertTrue(s.isClaimed(.soulDew))
        XCTAssertFalse(s.claimAchievement(.soulDew))
        XCTAssertEqual(s.itemCount(.soulDew), 1)
        XCTAssertEqual(s.unclaimedAchievementsCount, 0)
    }

    func testClaimedAchievementsSurviveARestart() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("claimed-\(UUID().uuidString).json")
        var st = CompanionState()
        st.installBaselineSet = true
        st.dex = entries([154, 157, 160])
        try JSONEncoder().encode(st).write(to: url)
        let first = CompanionStore(provider: CollectorStubProvider(), clock: { self.now }, fileURL: url,
                                   rng: SeededRNG(seed: 1))
        XCTAssertTrue(first.claimAchievement(.fireStone))
        let reopened = CompanionStore(provider: CollectorStubProvider(), clock: { self.now }, fileURL: url,
                                      rng: SeededRNG(seed: 1))
        // A stone is not passive: only the saved ledger can say it was claimed.
        XCTAssertTrue(reopened.isClaimed(.fireStone))
        XCTAssertFalse(reopened.claimAchievement(.fireStone))
        XCTAssertEqual(reopened.itemCount(.fireStone), 5)
    }

    func testSectionListsItemsOnSaleBeforeLockedAndOwnedOnes() {
        let s = store(dex: entries([243, 244, 245, 380, 381], rarity: .legendary),
                      inventory: [ItemKind.soulDew.rawValue: 1])
        let artifacts = s.collectorItems(in: .legendaryArtifacts)
        XCTAssertEqual(artifacts.first, .clearBell, "unlocked and not owned comes first")
        XCTAssertEqual(artifacts.last, .soulDew, "owned passives sink to the very bottom, below the four still to earn")
        XCTAssertEqual(artifacts.count, 48)
    }

    /// Badges too go from the closest to done to the farthest, over all their regions, claimable or not: seven Kanto
    /// Fire-type species put the Volcano Badge before the Cascade Badge's one Water-type, both before a badge with none.
    func testBadgesGoFromTheClosestToDone() {
        let s = store(dex: entries([4, 5, 6, 37, 38, 58, 59, 7]))
        XCTAssertGreaterThan(s.achievementShare(.volcanoBadge), s.achievementShare(.cascadeBadge))
        XCTAssertGreaterThan(s.achievementShare(.cascadeBadge), 0)
        XCTAssertEqual(s.achievementShare(.fairyBadge), 0)
        let badges = s.collectorItems(in: .gymBadges)
        let order = [ItemKind.volcanoBadge, .cascadeBadge, .fairyBadge].map { badges.firstIndex(of: $0)! }
        XCTAssertEqual(order, order.sorted(), "\(badges.map(\.rawValue))")
        // A region claimed counts whole: one of the badge's regions done is that share of it.
        let regions = PokemonTypeData.badgeGenerations(for: .fire)
        let oneDone = store(claimed: [CompanionState.regionTierKey(.volcanoBadge, generation: regions[0])])
        XCTAssertEqual(oneDone.achievementShare(.volcanoBadge), 1 / Double(regions.count), accuracy: 1e-9)
    }

    /// The Legendary Egg, Type: Null's Egg and the two whole-Pokédex charms close the Artifacts still to earn, never
    /// below those claimed (the owner, 2026-11-02: under the artifacts already claimed, they read as forgotten). Once
    /// claimed, one sinks with the others.
    func testTheFourCloseWhatIsLeftNeverBelowWhatIsClaimed() {
        let closing: [ItemKind] = [.legendaryEgg, .typeNullEgg, .ovalCharm, .glimmeringCharm]
        let fresh = store()
        XCTAssertEqual(Array(fresh.collectorItems(in: .legendaryArtifacts).suffix(4)), closing)
        let soulDewOwned = store(inventory: [ItemKind.soulDew.rawValue: 1])
        let artifacts = soulDewOwned.collectorItems(in: .legendaryArtifacts)
        XCTAssertEqual(artifacts.last, .soulDew, "claimed, below the four")
        XCTAssertEqual(Array(artifacts.dropLast().suffix(4)), closing)
        let ovalOwned = store(inventory: [ItemKind.ovalCharm.rawValue: 1])
        let withOval = ovalOwned.collectorItems(in: .legendaryArtifacts)
        XCTAssertEqual(withOval.last, .ovalCharm, "claimed, it sinks with the claimed ones")
        XCTAssertEqual(Array(withOval.dropLast().suffix(3)), [.legendaryEgg, .typeNullEgg, .glimmeringCharm])
        XCTAssertEqual(fresh.collectorItems(in: .evolutionStones).last, .excavation)
    }

    /// Achievements in progress go from the closest to done to the farthest: two titans of three, then Mewtwo without
    /// Mew, then one bird of three, then those with nothing yet.
    func testAchievementsInProgressGoFromTheClosestToDone() {
        let s = store(dex: entries([377, 378, 150, 144], rarity: .legendary))
        let artifacts = s.collectorItems(in: .legendaryArtifacts)
        XCTAssertEqual(s.achievementShare(.magmaStone), 2.0 / 3, accuracy: 1e-9)
        XCTAssertEqual(s.achievementShare(.oldSeaMap), 0.5)
        XCTAssertEqual(s.achievementShare(.silverWing), 1.0 / 3, accuracy: 1e-9)
        XCTAssertEqual(s.achievementShare(.rainbowWing), 0)
        let order = [ItemKind.magmaStone, .oldSeaMap, .silverWing, .rainbowWing].map { artifacts.firstIndex(of: $0)! }
        XCTAssertEqual(order, order.sorted(), "\(artifacts.map(\.rawValue))")
    }

    // MARK: Effects

    /// The Gracidea no longer touches Rare Candies: it doubled every one, bought ones included, which stacked
    /// with the Soul Dew and the Rainbow Wing into four times the EXP per shop token.
    func testGracideaNoLongerDoublesCandies() {
        let window = { (key: String, kind: WindowClass) in
            CandyWindow(key: key, name: "T", kind: kind, utilization: 100)
        }
        let flower = store(used: rich, inventory: [ItemKind.gracidea.rawValue: 1])
        flower.grantCandies(from: [], limitsReady: true)
        flower.grantCandiesFilling([window("s", .session)])
        XCTAssertEqual(flower.rareCandyCount, 1)
        XCTAssertTrue(flower.buy(.rareCandy))
        XCTAssertEqual(flower.rareCandyCount, 2)
    }

    /// The Gracidea speeds up the first stage of a Pokémon that will evolve, the Sun Flute's mirror.
    func testGracideaSpeedsUpTheFirstStageOfAPokemonThatWillEvolve() {
        let flower = store(inventory: [ItemKind.gracidea.rawValue: 1])
        XCTAssertEqual(flower.growthSpeedMultiplier(for: mon(1, forms: 3)), CollectorBonus.gracideaFirstStage,
                       accuracy: 0.0001, "Bulbasaur")
        XCTAssertEqual(flower.growthSpeedMultiplier(for: mon(1, stage: 1, forms: 3)), 1, accuracy: 0.0001, "Ivysaur")
        XCTAssertEqual(flower.growthSpeedMultiplier(for: mon(128, forms: 1)), 1, accuracy: 0.0001,
                       "Tauros does not evolve")
        XCTAssertEqual(store().growthSpeedMultiplier(for: mon(1, forms: 3)), 1, accuracy: 0.0001)
    }

    /// Only the Azure Flute reweights the egg roll. Every other item is a pure bonus: owning the Clear Bell,
    /// the Griseous Orb or a badge never lowers another Pokémon's chances.
    func testAzureFluteIsTheOnlyItemThatChangesHatchOdds() {
        let mewtwo = BaseSpecies(id: 150, captureRate: 3, isUnbreedableLegendary: true)
        let mew = BaseSpecies(id: 151, captureRate: 45, isUnbreedableLegendary: true)
        let beldum = BaseSpecies(id: 374, captureRate: 3)   // Mewtwo's weight, but not a legendary
        let others = [BaseSpecies(id: 92, captureRate: 190), BaseSpecies(id: 147, captureRate: 45),
                      BaseSpecies(id: 19, captureRate: 255), BaseSpecies(id: 489, captureRate: 30)]
        let plain = store()
        let flute = store(inventory: [ItemKind.legendCharm.rawValue: 1])
        XCTAssertEqual(flute.hatchDraw.hatchWeight(for: mewtwo), plain.hatchDraw.hatchWeight(for: mewtwo) * LegendCharm.weightMultiplier)
        XCTAssertEqual(plain.hatchDraw.hatchWeight(for: mew), PokemonOdds.hatchWeight(.legendary))
        XCTAssertEqual(flute.hatchDraw.hatchWeight(for: mew), plain.hatchDraw.hatchWeight(for: mew) * LegendCharm.weightMultiplier,
                       "Mew rolls like Mewtwo, so the flute boosts it")
        let passives = ItemKind.allCases.filter { $0.isPassive && $0 != .legendCharm }
        let everything = store(inventory: Dictionary(uniqueKeysWithValues: passives.map { ($0.rawValue, 1) }))
        for e in others + [mewtwo, mew] {
            XCTAssertEqual(everything.hatchDraw.hatchWeight(for: e), plain.hatchDraw.hatchWeight(for: e), "#\(e.id)")
        }
        for e in others + [beldum] {
            XCTAssertEqual(flute.hatchDraw.hatchWeight(for: e), plain.hatchDraw.hatchWeight(for: e), "#\(e.id)")
        }
    }

    private func mon(_ id: Int, rarity: Rarity = .common, stage: Int = 0, forms: Int = 2,
                     form: PokemonForm? = nil, newForm: Bool = false) -> MonState {
        var m = MonState(baseID: id, pathIDs: [id], stageIndex: 0, usedAtStage: 0, rarity: rarity,
                         totalForms: forms, form: form)
        m.stageIndex = stage
        m.pathIDs = Array(repeating: id, count: stage + 1)
        m.hasNewForm = newForm
        return m
    }

    /// Each growth artifact speeds up its own group by its bonus and leaves everyone else alone.
    func testGrowthArtifactsSpeedUpOnlyTheirGroup() {
        let cases: [(ItemKind, MonState, MonState, Double)] = [
            (.clearBell, mon(147, rarity: .rare), mon(19), CollectorBonus.clearBellRare),
            (.griseousOrb, mon(92), mon(19), CollectorBonus.griseousOrbGhostDragon),          // Gastly vs Rattata
            (.prisonBottle, mon(37, newForm: true), mon(37), CollectorBonus.prisonBottleNewForm),
            (.sparklingStone, mon(35), mon(19), CollectorBonus.sparklingStoneFairy),          // Clefairy
            (.sunFlute, mon(19, stage: 1, forms: 2), mon(19), CollectorBonus.sunFluteFinalStage),
            (.beastBall, mon(793, rarity: .rare), mon(147, rarity: .rare), CollectorBonus.beastBallUltraBeast),
            (.rustedSword, mon(150, rarity: .legendary), mon(147, rarity: .rare), CollectorBonus.rustedSwordLegendary),
            (.boosterEnergy, mon(984, rarity: .rare), mon(147, rarity: .rare), CollectorBonus.boosterEnergyParadox),
            (.tealMask, mon(74), mon(19), CollectorBonus.tealMaskTypes),                      // Geodude (Rock)
            (.relicStatue, mon(128, forms: 1), mon(19), CollectorBonus.relicStatueNoEvolution), // Tauros vs Rattata
            (.lunarWing, mon(63), mon(19), CollectorBonus.lunarWingPsychicDark),             // Abra
            (.lunarWing, mon(261), mon(19), CollectorBonus.lunarWingPsychicDark),            // Poochyena
            (.oaksLetter, mon(5, stage: 1), mon(19), CollectorBonus.oaksLetterStarter),       // Charmeleon
            (.zRing, mon(81), mon(19), CollectorBonus.zRingSteelElectric),                    // Magnemite
            (.zRing, mon(25), mon(19), CollectorBonus.zRingSteelElectric),                    // Pikachu
            (.scrollOfDarkness, mon(66), mon(19), CollectorBonus.scrollOfDarknessFighting),   // Machop
            // Pidgeotto, between Pidgey and Pidgeot, against Pidgeot.
            (.relicVase, mon(17, stage: 1, forms: 3), mon(18, stage: 2, forms: 3), CollectorBonus.relicVaseMiddleStage),
        ]
        let plain = store()
        for (item, boosted, other, bonus) in cases {
            let owner = store(inventory: [item.rawValue: 1])
            XCTAssertEqual(owner.growthSpeedMultiplier(for: boosted), bonus, accuracy: 0.0001, "\(item)")
            XCTAssertEqual(owner.growthSpeedMultiplier(for: other), 1, accuracy: 0.0001, "\(item)")
            XCTAssertEqual(plain.growthSpeedMultiplier(for: boosted), 1, accuracy: 0.0001, "\(item)")
        }
        // The Alolan form's types count: an Alolan Vulpix is Ice, not Fire, so the Teal Mask skips it.
        let mask = store(inventory: [ItemKind.tealMask.rawValue: 1])
        XCTAssertEqual(mask.growthSpeedMultiplier(for: mon(37)), CollectorBonus.tealMaskTypes, accuracy: 0.0001)
        XCTAssertEqual(mask.growthSpeedMultiplier(for: mon(37, form: PokemonForm("alola"))), 1, accuracy: 0.0001)
    }

    func testGrowthBonusesShortenTheStageThreshold() {
        let gastly = mon(92)
        let plain = store(active: gastly).threshold
        let orb = store(active: gastly, inventory: [ItemKind.griseousOrb.rawValue: 1]).threshold
        XCTAssertEqual(Double(orb), Double(plain) / CollectorBonus.griseousOrbGhostDragon, accuracy: 1)
    }

    func testZygardeCubeGrowsWithThePokedex() {
        let cube = [ItemKind.zygardeCube.rawValue: 1]
        XCTAssertEqual(store(inventory: cube).zygardeCubeMultiplier, 1, accuracy: 0.0001)
        XCTAssertEqual(store(dex: entries(Array(1...50)), inventory: cube).zygardeCubeMultiplier, 1.02, accuracy: 0.0001)
        XCTAssertEqual(store(dex: entries(Array(1...1025)), inventory: cube).zygardeCubeMultiplier, 1.40, accuracy: 0.0001,
                       "capped at +40%")
        // Graduated species only: fifty released ones stay in the Pokédex but add nothing.
        let released = Array(1...50).map { entry([$0], released: true) }
        XCTAssertEqual(store(dex: entries(Array(51...100)) + released, inventory: cube).zygardeCubeMultiplier, 1.02,
                       accuracy: 0.0001)
    }

    func testTeraOrbHalvesOnlyAStoneEggsThreshold() {
        let plain = store()
        let orb = store(inventory: [ItemKind.teraOrb.rawValue: 1])
        XCTAssertEqual(orb.eggHatchThreshold, plain.eggHatchThreshold, "a plain egg keeps its threshold")
        let stoneEgg = store(used: rich, dex: entries([154, 157, 160]), active: pikachu,
                             inventory: [ItemKind.teraOrb.rawValue: 1, ItemKind.fireStone.rawValue: 1])
        XCTAssertTrue(stoneEgg.useStone(.fireStone))
        XCTAssertEqual(stoneEgg.eggHatchThreshold, plain.eggHatchThreshold / 2)
    }

    /// A candy for each graduation but a Common's: one candy is a whole Common line's XP, so each Common graduated
    /// paid the next one, and Commons graduated for free one egg apart.
    func testReinsOfUnityAddACandyToEachGraduationButACommons() async {
        for (owned, base, expected) in [(false, 147, 0), (true, 147, CollectorBonus.reinsOfUnityCandies), (true, 4, 0)] {
            let s = store(inventory: owned ? [ItemKind.reinsOfUnity.rawValue: 1] : [:])
            await s.hatch(baseID: base)
            XCTAssertEqual(s.state.active?.rarity, base == 147 ? .rare : .common)
            s.applyUsage(s.threshold)
            XCTAssertEqual(s.state.dex.count, 1, "graduated")
            XCTAssertEqual(s.rareCandyCount, expected, "owned \(owned), base \(base)")
        }
    }

    /// The new legendary groups each unlock their artifact; the Beast Ball and Booster Energy take any four.
    func testNewArtifactsUnlockFromTheirLegendaries() {
        let goals: [(ItemKind, [Int])] = [
            (.zygardeCube, [716, 717, 718]), (.prisonBottle, [719, 720, 721]),
            (.sparklingStone, [785, 786, 787, 788]), (.sunFlute, [791, 792, 800]),
            (.rustedSword, [888, 889, 890]), (.reinsOfUnity, [896, 897, 898]),
            (.tealMask, [1014, 1015, 1016, 1017]), (.teraOrb, [1007, 1008, 1024]),
            (.beastBall, [793, 798, 803, 806]), (.boosterEnergy, [984, 990, 1009, 1023]),
            (.revealGlass, [641, 642, 905]), (.relicStatue, [377, 378, 379, 486, 894, 895]),
            (.lunarWing, [488, 491]), (.meteorite, [385, 386]), (.oaksLetter, [251, 492]), (.seaIncense, [490, 382]),
            (.shockDrive, [494, 648, 649]), (.zRing, [773, 801, 802, 807]), (.scrollOfDarkness, [892, 893]),
            (.relicVase, [1001, 1002, 1003, 1004]), (.legendPlate, [493]),
            // Kyurem is needed with Reshiram and Zekrom; Keldeo and Pecharunt can stand in for one of the others.
            (.dnaSplicers, [643, 644, 646]), (.libertyPass, [638, 639, 647]), (.tealMask, [1014, 1015, 1016, 1025]),
            // Heatran with Groudon, never alone: no achievement but Arceus's asks for one Pokémon.
            (.magmaStone, [485, 383]),
        ]
        for (item, ids) in goals {
            XCTAssertTrue(store(dex: entries(ids, rarity: .legendary)).isUnlocked(item), "\(item)")
            XCTAssertFalse(store(dex: entries(Array(ids.dropLast()), rarity: .legendary)).isUnlocked(item), "\(item)")
        }
        XCTAssertTrue(store(dex: entries([697, 699, 880, 883])).isUnlocked(.magmaStone), "later fossils count")
    }

    /// No achievement but Arceus's can be earned with a single Pokémon: every goal asks for two at least (the
    /// player's rule; Manaphy alone and Heatran alone broke it).
    func testNoAchievementAsksForASinglePokemonButArceus() {
        for kind in ItemKind.allCases where kind != .legendPlate && !kind.isRegional {
            guard case .species(let goals) = kind.unlock else { continue }
            for goal in goals { XCTAssertGreaterThanOrEqual(goal.needed, 2, "\(kind): \(goal.species)") }
        }
    }

    func testRainbowWingAndJadeOrbDiscounts() throws {
        let plain = store()
        let wing = store(inventory: [ItemKind.rainbowWing.rawValue: 1])
        let both = store(inventory: [ItemKind.rainbowWing.rawValue: 1, ItemKind.jadeOrb.rawValue: 1])
        let candy = try XCTUnwrap(plain.price(of: .rareCandy))
        XCTAssertEqual(wing.price(of: .rareCandy), Int(Double(candy) * 0.75))
        XCTAssertEqual(both.price(of: .rareCandy), wing.price(of: .rareCandy), "the orb only discounts eggs")
        let egg = plain.price(of: .egg(nil))
        XCTAssertEqual(wing.price(of: .egg(nil)), Int(Double(egg) * 0.75))
        XCTAssertEqual(both.price(of: .egg(nil)), Int(Double(wing.price(of: .egg(nil))) * 0.80))
    }

    /// Liberty Pass speeds up lines never graduated; Magma Stone speeds up the repeats. Neither touches the other.
    func testLibertyPassAndMagmaStoneSplitNewAndRepeatLines() {
        func mon(repeatLine: Bool) -> MonState {
            MonState(baseID: 19, pathIDs: [19, 20], stageIndex: 0, usedAtStage: 0,
                     rarity: .common, totalForms: 2, hasGrowthBoost: repeatLine)
        }
        for repeatLine in [false, true] {
            let plain = store(active: mon(repeatLine: repeatLine)).threshold
            let liberty = store(active: mon(repeatLine: repeatLine),
                                inventory: [ItemKind.libertyPass.rawValue: 1]).threshold
            let magma = store(active: mon(repeatLine: repeatLine),
                              inventory: [ItemKind.magmaStone.rawValue: 1]).threshold
            if repeatLine {
                XCTAssertEqual(liberty, plain)
                XCTAssertLessThan(magma, plain)
            } else {
                XCTAssertLessThan(liberty, plain)
                XCTAssertEqual(liberty, PokemonBalance.scaled(mon(repeatLine: false).phaseThreshold * 3 / 4,
                                                             by: store().growthDifficulty))
                XCTAssertEqual(magma, plain)
            }
        }
    }

    /// The Silver Wing and the Tera Orb halve the egg at any difficulty. A 1M floor used to make the egg slower
    /// with them below difficulty 0.4 (500k without, 1M with at 0.1, the players' difficulty).
    func testEggItemsHalveTheThresholdAtEveryDifficulty() {
        for difficulty in [0.1, 0.2, 0.3, 0.4, 1.0, 2.0] {
            let plain = store(growthDifficulty: difficulty).eggHatchThreshold
            XCTAssertEqual(plain, PokemonBalance.scaled(PokemonBalance.eggHatchThreshold, by: difficulty))
            let wing = store(inventory: [ItemKind.silverWing.rawValue: 1], growthDifficulty: difficulty)
            XCTAssertEqual(wing.eggHatchThreshold, plain / 2, "difficulty \(difficulty)")
            let both = store(used: rich, dex: entries([154, 157, 160]), active: pikachu,
                             inventory: [ItemKind.silverWing.rawValue: 1, ItemKind.teraOrb.rawValue: 1,
                                         ItemKind.fireStone.rawValue: 1], growthDifficulty: difficulty)
            XCTAssertTrue(both.useStone(.fireStone))
            XCTAssertEqual(both.eggHatchThreshold, plain / 4, "difficulty \(difficulty)")
        }
    }

    /// No type is weak to Normal, so the Plain Badge boosts Normal-type Pokémon, and its texts must say so.
    func testPlainBadgeBoostsNormalTypesAndSaysSo() {
        let s = store(claimed: ["plainBadge@1", "plainBadge@2"])
        XCTAssertEqual(s.typeBadgeSpeedMultiplier(forSpeciesID: 143, form: nil), 1.05, accuracy: 0.0001, "Snorlax")
        XCTAssertEqual(s.typeBadgeSpeedMultiplier(forSpeciesID: 6, form: nil), 1.0, "Charizard")
        for lang in AppLanguage.allCases {
            let l = L(lang)
            // The stem of the type name, so a declined form ("обычного") still matches.
            let normal = String(l.typeName(.normal).lowercased().prefix(5))
            XCTAssertTrue(l.itemDescription(.plainBadge).lowercased().contains(normal), "\(lang)")
            XCTAssertNotEqual(l.itemDescription(.plainBadge), l.itemDescription(.boulderBadge), "\(lang)")
            XCTAssertTrue(l.badgeEffectHint(5, type: .normal).lowercased().contains(normal), "\(lang)")
            XCTAssertNotEqual(l.badgeEffectHint(5, type: .normal), l.badgeEffectHint(5), "\(lang)")
            XCTAssertEqual(l.badgeEffectHint(5, type: .rock), l.badgeEffectHint(5), "\(lang)")
        }
    }

    /// Each claimed region adds 2.5% growth to Pokémon weak to its badge's type, across badges.
    func testBadgeRegionsStackOnPokemonWeakToThem() {
        let s = store(claimed: ["fairyBadge@1", "fairyBadge@6", "glacierBadge@1"])
        // Dragonite (Dragon/Flying) is weak to both Fairy and Ice: three regions.
        XCTAssertEqual(s.ownedBadgeTierCount(weakAgainst: 149, form: nil), 3)
        XCTAssertEqual(s.typeBadgeSpeedMultiplier(forSpeciesID: 149, form: nil), 1.075, accuracy: 0.0001)
        // Charizard (Fire/Flying) is weak to neither.
        XCTAssertEqual(s.typeBadgeSpeedMultiplier(forSpeciesID: 6, form: nil), 1.0)
        // Every region of every badge Dragonite is weak to: Dragon 9, Fairy 9, Ice 9, Rock 9 regions.
        let all = store(claimed: Set([PokemonType.dragon, .fairy, .ice, .rock].flatMap { type in
            PokemonTypeData.badgeGenerations(for: type).map { CompanionState.regionTierKey(type.badgeItem, generation: $0) }
        }))
        XCTAssertEqual(all.typeBadgeSpeedMultiplier(forSpeciesID: 149, form: nil), 1 + 4 * 0.225, accuracy: 0.0001)
    }

    /// A regional form takes the badges its own types are weak to: an Alolan Vulpix (Ice) grows faster with the Fire
    /// badge, a Kanto Vulpix (Fire) with the Water one. Before, both read the species' default types.
    func testBadgesFollowTheRegionalFormsTypes() {
        let alolan = mon(37, form: PokemonForm("alola"))
        let kanto = mon(37)
        let fire = store(claimed: ["volcanoBadge@1"])
        XCTAssertEqual(fire.growthSpeedMultiplier(for: alolan), 1.025, accuracy: 0.0001)
        XCTAssertEqual(fire.growthSpeedMultiplier(for: kanto), 1, accuracy: 0.0001)
        let water = store(claimed: ["cascadeBadge@1"])
        XCTAssertEqual(water.growthSpeedMultiplier(for: alolan), 1, accuracy: 0.0001)
        XCTAssertEqual(water.growthSpeedMultiplier(for: kanto), 1.025, accuracy: 0.0001)
    }

    /// The types shown on Home and in the Pokédex follow the form; PokéAPI's species data, the default form's,
    /// only fills in for a species the local table lacks.
    func testShownTypesFollowTheForm() {
        XCTAssertEqual(PokemonTypeData.typeNames(speciesID: 37, form: PokemonForm("alola"), fallback: ["fire"]), ["ice"])
        XCTAssertEqual(PokemonTypeData.typeNames(speciesID: 37, form: nil, fallback: ["fire"]), ["fire"])
        XCTAssertEqual(PokemonTypeData.typeNames(speciesID: 52, form: PokemonForm("galar"), fallback: ["normal"]), ["steel"])
        XCTAssertEqual(PokemonTypeData.typeNames(speciesID: 99_999, form: nil, fallback: ["water"]), ["water"])
    }

    /// Claiming a stone achievement puts five stones in the Bag for free. Using one works like buying an
    /// egg: the companion is sent off at once for a typed egg.
    func testClaimedStonesAreUsedLikeAnEgg() async throws {
        let s = store(used: rich, dex: entries([154, 157, 160]), active: pikachu)
        XCTAssertFalse(s.canBuy(.fireStone), "not sold in the Shop")
        XCTAssertFalse(s.buy(.fireStone))
        XCTAssertNil(s.price(of: .fireStone))

        XCTAssertTrue(s.claimAchievement(.fireStone))
        XCTAssertEqual(s.itemCount(.fireStone), 5)
        XCTAssertEqual(s.state.spentTokens, 0, "achievements are free to claim")
        XCTAssertEqual(s.ownedItems.map(\.kind), [.fireStone], "stones are consumables in the Bag")

        XCTAssertTrue(s.canUseStone(.fireStone))
        XCTAssertTrue(s.useStone(.fireStone))
        XCTAssertEqual(s.itemCount(.fireStone), 4)
        XCTAssertEqual(s.state.spentTokens, 0, "using a stone costs no tokens")
        XCTAssertTrue(s.isEgg)
        XCTAssertEqual(s.eggTypeGuarantee, .fire)
        XCTAssertTrue(s.state.dex.contains { $0.baseID == 25 && $0.isReleased },
                      "the companion goes to the Pokédex as released")
        XCTAssertFalse(s.canUseStone(.fireStone), "no companion to send off while incubating")

        s.setEggUsageForTesting(s.eggHatchThreshold)
        await s.hatchIfNeeded()
        XCTAssertEqual(s.currentSpeciesID, 4, "Charmander is the only Fire-type candidate")
        XCTAssertNil(s.eggTypeGuarantee)
        XCTAssertTrue(s.canUseStone(.fireStone), "the four other stones stay usable")
    }

    /// The banner's "Claim all" claims every ready achievement at once, and nothing that is still locked.
    func testClaimAllClaimsEveryReadyAchievementOnce() {
        let s = store(dex: entries([154, 157, 160]) + entries([144, 145, 146, 380, 381], rarity: .legendary))
        XCTAssertEqual(s.unclaimedAchievementsCount, 3, "Fire Stone, Silver Wing, Soul Dew")
        XCTAssertEqual(s.claimAllAchievements(), 3)
        XCTAssertEqual(s.unclaimedAchievementsCount, 0)
        XCTAssertEqual(s.itemCount(.fireStone), EvolutionStone.achievementReward)
        XCTAssertEqual(s.itemCount(.silverWing), 1)
        XCTAssertEqual(s.itemCount(.soulDew), 1)
        XCTAssertFalse(s.isClaimed(.waterStone), "a locked achievement stays locked")
        XCTAssertEqual(s.claimAllAchievements(), 0, "nothing left to claim")
        let withRegion = store(dex: entries([35, 36, 39, 40, 122, 154, 157, 160]))
        XCTAssertEqual(withRegion.claimAllAchievements(), 2, "the Fire Stone and the Kanto Fairy region")
        XCTAssertTrue(withRegion.isRegionTierClaimed(.fairyBadge, generation: 1))
        XCTAssertEqual(s.itemCount(.fireStone), EvolutionStone.achievementReward, "no second batch")
    }

    func testBagListsConsumablesBeforePassiveItems() {
        let s = store(inventory: [ItemKind.shinyCharm.rawValue: 1, ItemKind.soulDew.rawValue: 1,
                                  ItemKind.fireStone.rawValue: 5, ItemKind.rareCandy.rawValue: 2])
        XCTAssertEqual(s.ownedItems.map(\.kind), [.rareCandy, .fireStone, .shinyCharm, .soulDew])
    }

    private var pikachu: MonState {
        MonState(baseID: 25, pathIDs: [25], stageIndex: 0, usedAtStage: 0, rarity: .common, totalForms: 1)
    }
}
