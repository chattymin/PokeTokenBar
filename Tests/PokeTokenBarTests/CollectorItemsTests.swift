import XCTest
@testable import PokeTokenBar

// MARK: Collector items (achievement rewards unlocked by the Pokédex)

private func collectorNode(_ id: Int, _ children: [EvoNode] = []) -> EvoNode {
    EvoNode(speciesID: id, children: children)
}

private func collectorLine(base: Int) -> EvoLine {
    EvoLine(baseID: base, tree: collectorNode(base), rarity: .common,
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
                       claimed: Set<String> = []) -> CompanionStore {
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
                              rng: SeededRNG(seed: 1))
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
        XCTAssertEqual(s.collectorItems(in: .evolutionStones).count, 10)
        XCTAssertEqual(s.collectorItems(in: .legendaryArtifacts).count, 13)
        XCTAssertEqual(s.collectorItems(in: .gymBadges).count, 18)
        XCTAssertEqual(Set(CompanionStore.achievementItems), Set(ItemKind.allCases.filter { $0.collectorGroup != nil }))
        XCTAssertEqual(s.totalAchievementsCount, 41)
        XCTAssertEqual(s.purchasableItems, [.mint, .rareCandy, .shinyCharm], "the Shop sells what main sells")

        // An unlocked stone is an achievement to claim, never a Shop item.
        let withFire = store(dex: entries([154, 157, 160]))
        XCTAssertTrue(withFire.isUnlocked(.fireStone))
        XCTAssertEqual(withFire.purchasableItems, [.mint, .rareCandy, .shinyCharm])
        XCTAssertFalse(withFire.shopEntries.contains(.item(.fireStone)))
        XCTAssertEqual(withFire.unclaimedAchievementsCount, 1)
    }

    func testItemsHaveAppropriatePricesAndUnlockConditions() {
        for kind in ItemKind.allCases {
            if kind.collectorGroup == nil {
                XCTAssertNil(kind.unlock, "\(kind) is always on sale")
                XCTAssertNotNil(kind.shopPrice, "\(kind) must have a price")
            } else {
                XCTAssertNotNil(kind.unlock, "\(kind) achievement is unlocked by the Pokédex")
                XCTAssertNil(kind.shopPrice, "\(kind) achievement is free to claim, not bought")
                XCTAssertTrue(kind.isAchievement)
                XCTAssertEqual(kind.achievementRewardCount, kind.stoneType != nil ? 5 : 1)
                XCTAssertEqual(kind.isPassive, kind.stoneType == nil, "stones are the only consumable rewards")
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

    /// Every stage of a graduated chain counts, and so does a released Pokémon: the Pokédex keeps both.
    func testEvolutionChainsAndReleasedEntriesCountAsRegistered() {
        let s = store(dex: [entry([1, 2, 3]), entry([4, 5, 6], released: true), entry([7, 8, 9])])
        XCTAssertTrue(s.isUnlocked(.leafStone))
    }

    /// The current Pokémon counts for the stages it has reached, never for its planned evolutions.
    func testActivePokemonCountsOnlyReachedStages() {
        func active(stage: Int) -> MonState {
            MonState(baseID: 1, pathIDs: [1, 2, 3], stageIndex: stage, usedAtStage: 0,
                     rarity: .common, totalForms: 3)
        }
        let others = [entry([4, 5, 6]), entry([7, 8, 9])]
        XCTAssertFalse(store(dex: others, active: active(stage: 1)).isUnlocked(.leafStone))
        XCTAssertTrue(store(dex: others, active: active(stage: 2)).isUnlocked(.leafStone))
    }

    /// Water Stone has two Pokémon goals: the second one alone unlocks it.
    func testAlternativeGoalUnlocksOnItsOwn() {
        XCTAssertTrue(store(dex: entries([134, 135, 136])).isUnlocked(.waterStone))
        XCTAssertTrue(store(dex: entries([254, 257, 260])).isUnlocked(.waterStone))
        XCTAssertFalse(store(dex: entries([134, 135, 254, 257])).isUnlocked(.waterStone),
                       "goals don't mix: two of each trio is not a full trio")
    }

    /// Magma Stone accepts any 4 of the 9 fossil Pokémon.
    func testPartialGoalNeedsOnlyItsCount() {
        XCTAssertFalse(store(dex: entries([139, 141, 142])).isUnlocked(.magmaStone))
        XCTAssertTrue(store(dex: entries([139, 141, 142, 567])).isUnlocked(.magmaStone))
        XCTAssertTrue(store(dex: entries([377, 378, 379], rarity: .legendary)).isUnlocked(.magmaStone))
    }

    /// A badge asks for every Gen 1 to 5 Pokémon of its type, not the later Fairy types like Sylveon.
    func testBadgeNeedsEveryPokemonOfItsType() {
        let fairy = PokemonTypeData.badgeSpecies(for: .fairy)
        XCTAssertEqual(fairy.count, 22)
        XCTAssertFalse(fairy.contains(700), "Sylveon is Gen 6")
        XCTAssertFalse(store(dex: entries(Array(fairy.dropFirst()))).isUnlocked(.fairyBadge))
        XCTAssertTrue(store(dex: entries(fairy)).isUnlocked(.fairyBadge))
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
        XCTAssertEqual(goals.count, 2)
        XCTAssertEqual(goals[0].registered, [254, 257])
        XCTAssertEqual(goals[0].count, 2)
        XCTAssertFalse(goals[0].isMet)
        XCTAssertEqual(goals[1].count, 0)
        XCTAssertTrue(s.unlockProgress(of: .legendCharm).isEmpty, "the Azure Flute has no species list")
        XCTAssertTrue(s.unlockProgress(of: .rareCandy).isEmpty)
    }

    /// The Shiny Stone guarantees Dragon, the strongest type: it asks for the three Dragon/Flying Pokémon.
    func testShinyStoneNeedsTheSkyDragons() {
        XCTAssertFalse(store(dex: entries([149, 373], rarity: .rare)).isUnlocked(.shinyStone))
        XCTAssertTrue(store(dex: entries([149, 373], rarity: .rare) + entries([384], rarity: .legendary))
            .isUnlocked(.shinyStone))
    }

    func testThunderAndDawnStonesNeedTheirEvolvers() {
        XCTAssertFalse(store(dex: entries([26, 135])).isUnlocked(.thunderStone))
        XCTAssertTrue(store(dex: entries([26, 135, 604])).isUnlocked(.thunderStone))
        XCTAssertFalse(store(dex: entries([475])).isUnlocked(.dawnStone))
        XCTAssertTrue(store(dex: entries([475, 478])).isUnlocked(.dawnStone))
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
        XCTAssertEqual(s.collectorItems(in: .evolutionStones).last, .fireStone, "claimed cards sink to the bottom")
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
        XCTAssertEqual(artifacts.last, .soulDew, "owned passives sink to the bottom")
        XCTAssertEqual(artifacts.count, 13)
    }

    // MARK: Effects

    func testGracideaDoublesEveryCandyGrant() {
        let window = { (key: String, kind: WindowClass) in
            CandyWindow(key: key, name: "T", kind: kind, utilization: 100)
        }
        let plain = store()
        plain.grantCandies(from: [], limitsReady: true)
        plain.grantCandies(from: [window("s", .session)], limitsReady: true)
        XCTAssertEqual(plain.rareCandyCount, 1)

        let flower = store(inventory: [ItemKind.gracidea.rawValue: 1])
        flower.grantCandies(from: [], limitsReady: true)
        flower.grantCandies(from: [window("s", .session)], limitsReady: true)
        XCTAssertEqual(flower.rareCandyCount, 2)
        flower.grantCandies(from: [window("w", .weekly)], limitsReady: true)
        XCTAssertEqual(flower.rareCandyCount, 2 + RareCandy.weeklyGrant * 2)
    }

    func testGracideaDoublesBoughtCandies() {
        let plain = store(used: rich)
        XCTAssertTrue(plain.buy(.rareCandy))
        XCTAssertEqual(plain.rareCandyCount, 1)

        let flower = store(used: rich, inventory: [ItemKind.gracidea.rawValue: 1])
        XCTAssertTrue(flower.buy(.rareCandy))
        XCTAssertEqual(flower.rareCandyCount, 2)
        XCTAssertEqual(flower.state.spentTokens, flower.price(of: .rareCandy), "still one candy's price")
    }

    func testGriseousOrbDoublesGhostAndDragonHatchWeight() {
        let gastly = BaseSpecies(id: 92, captureRate: 190)     // Ghost/Poison
        let dratini = BaseSpecies(id: 147, captureRate: 45)    // Dragon
        let rattata = BaseSpecies(id: 19, captureRate: 255)    // Normal
        let plain = store()
        let orb = store(inventory: [ItemKind.griseousOrb.rawValue: 1])
        XCTAssertEqual(orb.hatchWeight(for: gastly), plain.hatchWeight(for: gastly) * 2)
        XCTAssertEqual(orb.hatchWeight(for: dratini), plain.hatchWeight(for: dratini) * 2)
        XCTAssertEqual(orb.hatchWeight(for: rattata), plain.hatchWeight(for: rattata))
    }

    func testAzureFluteAndClearBellBoostTheirTiers() {
        let mewtwo = BaseSpecies(id: 150, captureRate: 3)
        let dratini = BaseSpecies(id: 147, captureRate: 45)
        let rattata = BaseSpecies(id: 19, captureRate: 255)
        let plain = store()
        let flute = store(inventory: [ItemKind.legendCharm.rawValue: 1])
        let bell = store(inventory: [ItemKind.clearBell.rawValue: 1])
        XCTAssertEqual(flute.hatchWeight(for: mewtwo), plain.hatchWeight(for: mewtwo) * LegendCharm.weightMultiplier)
        XCTAssertEqual(flute.hatchWeight(for: dratini), plain.hatchWeight(for: dratini))
        XCTAssertEqual(bell.hatchWeight(for: dratini), plain.hatchWeight(for: dratini) * 2)
        XCTAssertEqual(bell.hatchWeight(for: mewtwo), plain.hatchWeight(for: mewtwo), "legendaries are the flute's")
        XCTAssertEqual(bell.hatchWeight(for: rattata), plain.hatchWeight(for: rattata))
    }

    /// Mew has the Kanto starters' capture rate (45) but rolls like Mewtwo, so it belongs to the flute's
    /// tier, not the bell's. Phione keeps its rare-like roll (30) and stays the bell's.
    func testAzureFluteAndClearBellTierLegendariesByHatchWeight() {
        let mew = BaseSpecies(id: 151, captureRate: 45, isUnbreedableLegendary: true)
        let phione = BaseSpecies(id: 489, captureRate: 30)
        let plain = store()
        let flute = store(inventory: [ItemKind.legendCharm.rawValue: 1])
        let bell = store(inventory: [ItemKind.clearBell.rawValue: 1])
        XCTAssertEqual(plain.hatchWeight(for: mew), PokemonOdds.legendaryHatchWeight)
        XCTAssertEqual(flute.hatchWeight(for: mew), plain.hatchWeight(for: mew) * LegendCharm.weightMultiplier)
        XCTAssertEqual(bell.hatchWeight(for: mew), plain.hatchWeight(for: mew), "legendaries are the flute's")
        XCTAssertEqual(bell.hatchWeight(for: phione), plain.hatchWeight(for: phione) * 2)
        XCTAssertEqual(flute.hatchWeight(for: phione), plain.hatchWeight(for: phione))
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

    func testSilverWingHalvesTheEggThreshold() {
        let plain = store().eggHatchThreshold
        XCTAssertEqual(store(inventory: [ItemKind.silverWing.rawValue: 1]).eggHatchThreshold,
                       max(1_000_000, plain / 2))
    }

    func testBadgesStackOnPokemonWeakToThem() {
        let s = store(inventory: [ItemKind.fairyBadge.rawValue: 1, ItemKind.glacierBadge.rawValue: 1])
        // Dragonite (Dragon/Flying) is weak to both Fairy and Ice.
        XCTAssertEqual(s.ownedBadgeCount(weakAgainst: 149), 2)
        XCTAssertEqual(s.typeBadgeSpeedMultiplier(forSpeciesID: 149), 1.40, accuracy: 0.0001)
        // Charizard (Fire/Flying) is weak to neither.
        XCTAssertEqual(s.typeBadgeSpeedMultiplier(forSpeciesID: 6), 1.0)
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

    func testBagListsConsumablesBeforePassiveItems() {
        let s = store(inventory: [ItemKind.shinyCharm.rawValue: 1, ItemKind.soulDew.rawValue: 1,
                                  ItemKind.fireStone.rawValue: 5, ItemKind.rareCandy.rawValue: 2])
        XCTAssertEqual(s.ownedItems.map(\.kind), [.rareCandy, .fireStone, .shinyCharm, .soulDew])
    }

    private var pikachu: MonState {
        MonState(baseID: 25, pathIDs: [25], stageIndex: 0, usedAtStage: 0, rarity: .common, totalForms: 1)
    }
}
