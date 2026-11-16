import XCTest
@testable import PokeTokenBar

private struct OakProvider: PokeProviding {
    var index: [BaseSpecies] = []
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: baseSpeciesID, tree: EvoNode(speciesID: baseSpeciesID, children: []), rarity: .common, names: [:])
    }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { index }
}

/// Prof. Oak's advice in the Shop: what to do with the Pokémon being raised for the Form Pokédex.
@MainActor
final class OakAdviceTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func store(active: MonState?, dex: [DexEntry], inventory: [ItemKind: Int] = [:], index: [BaseSpecies] = [],
                       difficulty: Double = PokemonBalance.difficulty,
                       prepare: (inout CompanionState) -> Void = { _ in }) throws -> CompanionStore {
        var st = CompanionState()
        st.installBaselineSet = true
        st.lastDate = "2026-10-29"
        st.active = active
        st.dex = dex
        st.inventory = Dictionary(uniqueKeysWithValues: inventory.map { ($0.key.rawValue, $0.value) })
        prepare(&st)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("oak-\(UUID().uuidString).json")
        try JSONEncoder().encode(st).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return CompanionStore(provider: OakProvider(index: index), clock: { self.now }, fileURL: url, rng: SeededRNG(seed: 1),
                              difficulty: difficulty)
    }

    private func graduated(_ chain: [Int], rarity: Rarity = .common, form: PokemonForm? = nil,
                           released: Bool = false) -> DexEntry {
        DexEntry(baseID: chain[0], finalID: chain.last!, chainOrder: chain, rarity: rarity, caughtAt: now,
                 releasedAt: released ? now : nil, form: form)
    }

    /// The odds an egg brings something when `new` of its `total` draws bring a species or a form, the others a first
    /// shiny one time in 64: no graduated Pokémon is shiny here.
    private func odds(_ new: Double, of total: Double) -> Double { (new + (total - new) / 64) / total }

    private func mon(_ path: [Int], stage: Int = 0, rarity: Rarity = .common, form: PokemonForm? = nil,
                     shiny: Bool = false) -> MonState {
        var m = MonState(baseID: path[0], pathIDs: path, stageIndex: stage, usedAtStage: 0, rarity: rarity,
                         totalForms: path.count, form: form)
        m.isShiny = shiny
        return m
    }

    func testAnEggHasNoVerdict() throws {
        XCTAssertNil(try store(active: nil, dex: [graduated([4, 5, 6])]).activeVerdict)
    }

    func testALineGraduatedWholeIsASpare() throws {
        XCTAssertEqual(try store(active: mon([4]), dex: [graduated([4, 5, 6])]).activeVerdict, .spare)
    }

    /// A Charmeleon whose Charizard was never graduated: one species to bring. A released Charizard holds nothing.
    func testASpeciesNeverGraduatedIsALineToComplete() throws {
        let charmeleon = mon([4, 5], stage: 1)
        XCTAssertEqual(try store(active: charmeleon, dex: [graduated([4, 5])]).activeVerdict, .lineToComplete(newSpecies: 1...1))
        XCTAssertEqual(try store(active: charmeleon, dex: [graduated([4, 5, 6], released: true)]).activeVerdict,
                       .lineToComplete(newSpecies: 3...3))
    }

    /// [Regression] An individual takes one way of its line: an Applin brings 2 species or 3, not the 5 of all its ways.
    func testALineToCompleteCountsOneWayOfTheLine() throws {
        XCTAssertEqual(try store(active: mon([840]), dex: []).activeVerdict, .lineToComplete(newSpecies: 2...3))
        XCTAssertEqual(try store(active: mon([840, 1011], stage: 1), dex: []).activeVerdict,
                       .lineToComplete(newSpecies: 3...3), "its way taken")
        XCTAssertEqual(try store(active: mon([133]), dex: [graduated([133, 470])]).activeVerdict,
                       .lineToComplete(newSpecies: 0...1), "the evolution already graduated brings nothing")
    }

    func testTheBubbleSaysUpToWhileTheWayIsOpen() {
        func bubble(_ count: ClosedRange<Int>) -> String {
            L(.en).oakBubble(.lineToComplete(newSpecies: count), name: "Applin", newFormName: "")
        }
        XCTAssertTrue(bubble(3...3).contains("will bring 3 species"), bubble(3...3))
        XCTAssertTrue(bubble(1...1).contains("will bring a species"), bubble(1...1))
        XCTAssertTrue(bubble(2...3).contains("can bring up to 3 species"), bubble(2...3))
        XCTAssertTrue(bubble(0...1).contains("can bring a species"), bubble(0...1))
    }

    /// An Alolan Vulpix while only Kanto's line is graduated: every species is there, not in its form.
    func testALineGraduatedInAnotherFormBringsANewForm() throws {
        let alola = PokemonForm("alola")
        XCTAssertEqual(try store(active: mon([37], form: alola), dex: [graduated([37, 38])]).activeVerdict,
                       .newForm(speciesID: 37))
        XCTAssertEqual(try store(active: mon([37], form: alola), dex: [graduated([37], form: alola)]).activeVerdict,
                       .lineToComplete(newSpecies: 1...1), "a species never graduated weighs more than a form")
    }

    /// A Pichu whose line is graduated still brings a costume missing when it becomes Pikachu: not a Spare.
    func testAPichuThatWillBringACostumeIsKept() throws {
        let line = [graduated([172, 25, 26], form: PokemonForm("normal")), graduated([172, 25, 26], form: PokemonForm("alola"))]
        XCTAssertEqual(try store(active: mon([172, 25, 26]), dex: line).activeVerdict, .costume)
    }

    /// [Regression] A Pikachu from a Costume Egg wears its costume's form for good: no Raichu stage hides it, though
    /// its line's form stays hidden until Raichu for any other Pikachu (`FormSuspense`). Its line graduated in both
    /// forms, the costume it brings still keeps it.
    func testACostumedPikachuHasNoFormToReveal() throws {
        let line = [graduated([172, 25, 26], form: PokemonForm("normal")), graduated([172, 25, 26], form: PokemonForm("alola"))]
        var pikachu = MonState(baseID: 172, pathIDs: [25], plannedPathIDs: [25, 26], stageIndex: 0, usedAtStage: 0,
                               rarity: .common, totalForms: 2, form: PokemonForm("normal"))
        pikachu.costume = "FEB_2019"
        let s = try store(active: pikachu, dex: line) { $0.pikachuCostumes = Set(PikachuCostume.allCases) }
        XCTAssertNil(s.formSuspense)
        XCTAssertEqual(s.activeVerdict, .newCostume)
    }

    /// A shiny Charmander whose line is graduated, none of it shiny: a Spare that brings its first shiny.
    func testAFirstShinyIsASpareToKeep() throws {
        XCTAssertEqual(try store(active: mon([4], shiny: true), dex: [graduated([4, 5, 6])]).activeVerdict, .shinyToKeep)
    }

    /// A second Articuno graduated unlocks the Azure Flute (`ItemUnlock.duplicateLegendary`): a Spare kept for it.
    func testASecondLegendaryCopyIsKeptForTheAzureFlute() throws {
        let articuno = mon([144], rarity: .legendary)
        XCTAssertEqual(try store(active: articuno, dex: [graduated([144], rarity: .legendary)]).activeVerdict,
                       .keptForAchievement(.legendCharm))
        let twoMewtwo = [graduated([150], rarity: .legendary), graduated([150], rarity: .legendary)]
        XCTAssertEqual(try store(active: articuno, dex: twoMewtwo + [graduated([144], rarity: .legendary)]).activeVerdict,
                       .spare, "the Azure Flute already unlocked")
    }

    // MARK: Rare Candies to give

    /// A Common with one 750 M stage at difficulty 1: one Rare Candy is 75 M.
    private func candyStore() async -> CompanionStore {
        let line = EvoLine(baseID: 20, tree: EvoNode(speciesID: 20, children: []), rarity: .common, names: [20: ["en": "P20"]])
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("oak-candy-\(UUID().uuidString).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let s = CompanionStore(provider: StubProvider(value: line), clock: { self.now }, fileURL: url, rng: SeededRNG(seed: 7),
                               difficulty: 1)
        await s.hatch(baseID: 20)
        return s
    }

    private func giveCandies(_ s: CompanionStore, _ n: Int) {
        s.grantCandies(from: [], limitsReady: true)
        for i in 0..<n {
            s.grantCandiesFilling([CandyWindow(key: "oak.session.\(i)", name: "T", kind: .session, utilization: 100, epoch: nil)])
        }
    }

    /// Two candies and a half left before graduation: two go in whole, a third would lose half its XP.
    func testGivesTheCandiesItsGrowthTakesWhole() async throws {
        let s = await candyStore()
        s.applyUsage(750_000_000 - s.rareCandyXP * 5 / 2)
        giveCandies(s, 5)
        XCTAssertEqual(s.candiesToGive, 2)
    }

    /// Less than one candy left: one would lose most of its XP at graduation, so they wait for the next one.
    func testKeepsTheCandiesWhenLessThanOneIsLeft() async throws {
        let s = await candyStore()
        s.applyUsage(750_000_000 - s.rareCandyXP / 2)
        giveCandies(s, 3)
        XCTAssertEqual(s.growthToGraduation, s.rareCandyXP / 2)
        XCTAssertEqual(s.candiesToGive, 0)
    }

    /// A last candy that loses a tenth of its XP at most still goes in.
    func testALastCandyLosingATenthAtMostIsGiven() async throws {
        let s = await candyStore()
        s.applyUsage(750_000_000 - s.rareCandyXP * 19 / 10)
        giveCandies(s, 3)
        XCTAssertEqual(s.candiesToGive, 2, "the second loses a tenth")
        let t = await candyStore()
        t.applyUsage(750_000_000 - t.rareCandyXP * 18 / 10)
        giveCandies(t, 3)
        XCTAssertEqual(t.candiesToGive, 1, "a second would lose a fifth")
    }

    /// The Reins of Unity add a Rare Candy at each graduation but a Common's (`CollectorBonus.reinsOfUnityCandies`).
    func testTheReinsOfUnityAddACandyAtGraduation() throws {
        let reins: [ItemKind: Int] = [.reinsOfUnity: 1]
        XCTAssertTrue(try store(active: mon([147], rarity: .rare), dex: [], inventory: reins).reinsCandyOnGraduation)
        XCTAssertFalse(try store(active: mon([4]), dex: [], inventory: reins).reinsCandyOnGraduation, "not for a Common")
        XCTAssertFalse(try store(active: mon([147], rarity: .rare), dex: []).reinsCandyOnGraduation, "without the Reins")
    }

    // MARK: What to send a Spare off for

    /// Charmander, Torchic and Squirtle, Rare; Caterpie, Common; Omanyte and Kabuto, fossil lines, which hatch from
    /// any egg once graduated.
    private let releaseIndex = [BaseSpecies(id: 4, captureRate: 45), BaseSpecies(id: 255, captureRate: 45),
                                BaseSpecies(id: 7, captureRate: 45), BaseSpecies(id: 10, captureRate: 255),
                                BaseSpecies(id: 138, captureRate: 45), BaseSpecies(id: 140, captureRate: 45)]
    /// Every line of `releaseIndex` but Torchic's and Kabuto's.
    private let mostLines = [[4, 5, 6], [7, 8, 9], [10, 11, 12], [138, 139]]

    /// A Spare Pidgey, hatched last, its line graduated with `lines`. The clock says 21 September 2026: the summer's egg
    /// waits to be claimed unless `claimed` holds it.
    private func spareStore(bag: [ItemKind: Int] = [:], lines: [[Int]]? = nil, active: MonState? = nil,
                            index: [BaseSpecies]? = nil, claimed: Set<String> = ["summer@2026"],
                            wallet: Int = 0, exploring: Bool = false) async throws -> CompanionStore {
        let spare = active ?? mon([16])
        let dex = ([[16, 17, 18]] + (lines ?? mostLines)).map { graduated($0) }
        let expedition = exploring ? try explorer() : nil
        let s = try store(active: spare, dex: dex, inventory: bag, index: index ?? releaseIndex) { st in
            st.lastHatchedBaseID = spare.baseID
            st.claimedEventEggs = claimed
            st.usedSinceInstall = wallet
            st.dungeons.expedition = expedition
        }
        await s.loadHatchIndex()
        return s
    }

    /// The Bag's egg with the best odds of something new, whatever it is: a Fossil Egg brings Kabuto for sure, a Fire
    /// Stone Torchic one time in two, the summer's egg one in four (the Rare lines of its types).
    func testASpareGoesForTheEggWithTheBestOdds() async throws {
        var s = try await spareStore(bag: [.fireStone: 1, .pokemonEgg: 1, .fossilEgg: 1], claimed: [])
        XCTAssertEqual(s.oakRelease, .bag(.fossilEgg, odds: 1))
        s = try await spareStore(bag: [.fireStone: 1, .pokemonEgg: 1], claimed: [])
        XCTAssertEqual(s.oakRelease, .bag(.fireStone, odds: odds(1, of: 2)))
        s = try await spareStore(bag: [.pokemonEgg: 1], claimed: [])
        XCTAssertEqual(s.oakRelease, .claim(.summer, odds: odds(1, of: 4)), "claimed, then used")
        XCTAssertEqual(s.oakBudget?.waitsForNext, true, "the summer's egg may bring Torchic")
    }

    /// An egg sends a Spare off only if it brings something more often than the Pokémon Egg its graduation gives (40 in
    /// 372, Caterpie weighs 212): never a Pokémon Egg, nor a Water Stone once Squirtle is graduated.
    func testOnlyAnEggThatBeatsThePokemonEggSendsASpareOff() async throws {
        let rare = try await spareStore().price(of: .egg(.rare))
        let s = try await spareStore(bag: [.pokemonEgg: 1, .waterStone: 1], wallet: rare)
        XCTAssertEqual(s.oakRelease, .buy(.rare, odds: odds(1, of: 4)))
    }

    /// A Spare grown further than it has left to grow loses more sent off than its graduation takes: it is left to
    /// finish, unless the Old Amber carries enough of its stage to the one that hatches. Pidgey's one stage is 75 M.
    func testASpareTooFarAlongIsLeftToFinish() async throws {
        var pidgey = mon([16])
        pidgey.usedAtStage = 40_000_000
        var s = try await spareStore(bag: [.fossilEgg: 1], active: pidgey)
        XCTAssertEqual(s.oakRelease, .finish(left: 35_000_000, why: .tooFarAlong), "40 M lost for 35 M left")
        s = try await spareStore(bag: [.fossilEgg: 1, .oldAmber: 1], active: pidgey)
        XCTAssertEqual(s.oakRelease, .bag(.fossilEgg, odds: 1), "20 M lost once the Old Amber carries half")
    }

    /// The Old Amber's carry stops short of the first evolution of what hatches (`hatch`): a Leaf Stone brings Oddish, a
    /// Common whose first stage is 12.5 M. A Pidgey 48 M along, 27 M left, carries 12.5 M of its 24: too far along.
    func testTheOldAmberCarriesNoMoreThanTheFirstStageOfWhatHatches() async throws {
        var pidgey = mon([16])
        pidgey.usedAtStage = 48_000_000
        let s = try await spareStore(bag: [.leafStone: 1, .oldAmber: 1], lines: [[4, 5, 6]], active: pidgey,
                                     index: [BaseSpecies(id: 43, captureRate: 255), BaseSpecies(id: 4, captureRate: 45)])
        XCTAssertEqual(s.oakRelease, .finish(left: 27_000_000, why: .tooFarAlong))
    }

    /// The Old Amber carries half of the stage reached, not of the whole line: a Pidgeot 5 M into its last stage
    /// (12.5, 25 and 37.5 M) has grown 42.5 M of 75 M, and the 2.5 M carried leave it too far along.
    func testTheOldAmberCarriesHalfOfTheStageReachedOnly() async throws {
        var pidgeot = mon([16, 17, 18], stage: 2)
        pidgeot.usedAtStage = 5_000_000
        let s = try await spareStore(bag: [.fossilEgg: 1, .oldAmber: 1], active: pidgeot)
        XCTAssertEqual(s.oakRelease, .finish(left: 32_500_000, why: .tooFarAlong))
    }

    /// Waiting for the balance to hold the egg grows the Spare as much as the balance: too far along by then, it is
    /// left to finish. Nothing is set aside for the stock meanwhile.
    func testASpareThatOutgrowsTheWaitIsLeftToFinish() async throws {
        let rare = try await spareStore().price(of: .egg(.rare))
        var pidgey = mon([16])
        pidgey.usedAtStage = 10_000_000
        var s = try await spareStore(active: pidgey, wallet: rare - 1_000_000)
        let wait = OakRelease.wait(.rare, odds: odds(1, of: 4), short: 1_000_000)
        XCTAssertEqual(s.oakRelease, wait)
        XCTAssertEqual(s.oakBudget?.reserve, 0)
        XCTAssertEqual(s.oakSteps, [.release(wait)])
        s = try await spareStore(active: pidgey, wallet: rare - 30_000_000)
        XCTAssertEqual(s.oakRelease, .finish(left: 65_000_000, why: .outgrowsTheWait), "40 M grown for 35 M left")
    }

    /// Equal odds: the Bag's order decides (`ItemKind`), the Uncommon Egg before the Rare Egg and the summer's egg when
    /// no Uncommon line sets them apart.
    func testOnATieTheBagsOrderDecides() async throws {
        let s = try await spareStore(bag: [.rareEgg: 1, .uncommonEgg: 1], claimed: [])
        XCTAssertEqual(s.oakRelease, .bag(.uncommonEgg, odds: odds(1, of: 4)))
    }

    /// A Fossil Egg's own Pokémon gives its egg back when sent off: never that egg on it (`canUseFossilEgg`).
    func testNoFossilEggOnItsOwnPokemon() async throws {
        var omanyte = mon([138], rarity: .rare)
        omanyte.fromFossilEgg = true
        let s = try await spareStore(bag: [.fossilEgg: 1, .fireStone: 1], active: omanyte)
        XCTAssertEqual(s.activeVerdict, .spare)
        XCTAssertEqual(s.oakRelease, .bag(.fireStone, odds: odds(1, of: 2)))
        XCTAssertEqual(s.oakBudget?.held, 2, "Omanyte gives its Fossil Egg back")
    }

    /// No egg in the Bag: the most selective Shop egg that can still bring something, bought when the balance holds its
    /// price, else awaited.
    func testWithoutABagEggTheSpareGoesForTheShopsMostSelectiveEgg() async throws {
        let rare = try await spareStore().price(of: .egg(.rare))
        var s = try await spareStore(wallet: rare)
        XCTAssertEqual(s.oakRelease, .buy(.rare, odds: odds(1, of: 4)))
        XCTAssertEqual(s.oakBudget?.waitsForNext, true, "the Rare+ Egg bought now may bring Torchic")
        s = try await spareStore(wallet: rare - 300)
        XCTAssertEqual(s.oakRelease, .wait(.rare, odds: odds(1, of: 4), short: 300))
        // Only Caterpie, a Common, is missing: the Pokémon Egg its graduation gives is the one that can bring it.
        s = try await spareStore(lines: [[4, 5, 6], [7, 8, 9], [255, 256, 257], [138, 139]], wallet: 10 * rare)
        XCTAssertEqual(s.oakRelease, .finish(left: 75_000_000, why: .noBetterEgg))
    }

    private func explorer() throws -> Expedition {
        let spec = try XCTUnwrap(BattlerSpec.make(id: "e6", speciesID: 6, level: 100))
        return ExpeditionEngine.start(dungeon: DungeonCatalog.dungeon(.viridianForest),
                                      team: [ExpeditionMember(entryID: "e6", spec: spec)], rules: [], teamSize: 1, seed: 1,
                                      cost: 75_000_000, berries: [:], revives: [:],
                                      context: ExpeditionContext(tier: .t1, shinyDenominator: 64, now: now), boss: nil)
    }

    /// [Regression] While a team explores, no egg nor stone sends the Pokémon off (`canSendOffActive`), yet the Bag's still
    /// waits for the Spare: none is bought on top of it, and it is used at the return. Buying stays advised when the Bag
    /// has none.
    func testWhileATeamExploresTheBagsEggStillWaitsForTheSpare() async throws {
        let rare = try await spareStore().price(of: .egg(.rare))
        var s = try await spareStore(bag: [.fireStone: 1], wallet: rare, exploring: true)
        XCTAssertTrue(s.growthPaused)
        let stone = OakRelease.bag(.fireStone, odds: odds(1, of: 2))
        XCTAssertEqual(s.oakRelease, stone)
        XCTAssertEqual(s.oakSteps.filter(s.oakWaitsForTheTeam), [.release(stone)])
        s = try await spareStore(wallet: rare, exploring: true)
        XCTAssertEqual(s.oakRelease, .buy(.rare, odds: odds(1, of: 4)))
        XCTAssertEqual(s.oakSteps.filter(s.oakWaitsForTheTeam), [.release(.buy(.rare, odds: odds(1, of: 4)))])
        s = try await spareStore(bag: [.fireStone: 1], wallet: rare)
        XCTAssertEqual(s.oakSteps.filter(s.oakWaitsForTheTeam), [], "no team away")
    }

    /// Every line an egg can hatch graduated: nothing to gain by sending the Spare off.
    func testASpareNoEggCanBetterIsLeftToFinish() async throws {
        let every = mostLines + [[255, 256, 257], [140, 141]]
        let s = try await spareStore(bag: [.fireStone: 1, .pokemonEgg: 1, .fossilEgg: 1], lines: every, claimed: [],
                                     wallet: 100_000_000_000)
        XCTAssertEqual(s.oakRelease, .finish(left: 75_000_000, why: .noBetterEgg))
    }

    /// Only a Spare is sent off: a Pokémon that brings something has no egg to go for.
    func testAPokemonThatBringsSomethingIsNotSentOff() async throws {
        let s = try await spareStore(bag: [.fossilEgg: 1], lines: [[4, 5, 6]], active: mon([7]))
        XCTAssertEqual(s.activeVerdict, .lineToComplete(newSpecies: 3...3))
        XCTAssertNil(s.oakRelease)
    }

    /// Kanto's Vulpix graduated, not Alola's: a plain egg rolls the Alolan form, missing, for sure
    /// (`HatchRules.Change.missingFormsFirst`; twice as often as the one collected before it), a Fire Stone only
    /// Kanto's, which brings nothing.
    func testAnEggsOddsWeighTheFormsItRolls() async throws {
        let s = try store(active: mon([16]), dex: [graduated([16, 17, 18]), graduated([37, 38])],
                          index: [BaseSpecies(id: 37, captureRate: 190)])
        await s.loadHatchIndex()
        XCTAssertEqual(try XCTUnwrap(s.newOdds(item: .pokemonEgg)), odds(1, of: 1), accuracy: 1e-9)
        XCTAssertEqual(s.newOdds(item: .fireStone), odds(0, of: 1), "a first shiny only")
    }

    /// A season's egg first hatches Deerling, a Common, in the season's form one time in three, then from its Uncommon+
    /// pool: Psyduck graduated, only that summer Deerling can bring something.
    func testASeasonsEggFirstHatchesDeerlingInItsForm() async throws {
        func summerOdds(deerlingForms: [String]) async throws -> Double? {
            let deerling = deerlingForms.map { graduated([585, 586], form: PokemonForm($0)) }
            let s = try store(active: mon([16]), dex: [graduated([16, 17, 18]), graduated([54, 55])] + deerling,
                              index: [BaseSpecies(id: 585, captureRate: 190), BaseSpecies(id: 54, captureRate: 90)])
            await s.loadHatchIndex()
            return s.newOdds(item: EventEgg.summer.item)
        }
        let spring = try await summerOdds(deerlingForms: ["spring"])
        XCTAssertEqual(try XCTUnwrap(spring), odds(1, of: 3), accuracy: 1e-12)
        let summer = try await summerOdds(deerlingForms: ["spring", "summer"])
        XCTAssertEqual(try XCTUnwrap(summer), odds(0, of: 1), accuracy: 1e-12, "summer's Deerling graduated")
    }

    /// A Spare sent off loses its growth, now or once its egg is affordable: no Rare Candy then, they are kept for the
    /// next one. Left to finish, it graduates and gets them like any other.
    func testASpareGetsCandiesOnlyWhenLeftToFinish() async throws {
        let (rare, _) = try prices(difficulty: 1)
        func hatchedSpare(bag: [ItemKind: Int] = [:], wallet: Int = 0) async throws -> CompanionStore {
            let s = try store(active: nil, dex: ([[16, 17, 18]] + mostLines).map { graduated($0) }, inventory: bag,
                              index: releaseIndex, difficulty: 1) { st in
                st.claimedEventEggs = ["summer@2026"]
                st.usedSinceInstall = wallet
            }
            await s.hatch(baseID: 16)
            await s.loadHatchIndex()
            giveCandies(s, 3)
            return s
        }
        let sentOff = try await hatchedSpare(bag: [.fossilEgg: 1])
        XCTAssertEqual(sentOff.activeVerdict, .spare)
        XCTAssertEqual(sentOff.oakRelease, .bag(.fossilEgg, odds: 1))
        XCTAssertEqual(sentOff.candiesToGive, 0)
        let waiting = try await hatchedSpare(wallet: rare - 1_000_000)
        guard case .wait? = waiting.oakRelease else { return XCTFail("raised until its egg is affordable") }
        XCTAssertEqual(waiting.candiesToGive, 0)
        let finishing = try await hatchedSpare()
        guard case .finish? = finishing.oakRelease else { return XCTFail("left to finish") }
        XCTAssertEqual(finishing.candiesToGive, 3)
    }

    /// [Regression] A Squirtle from a Costume Egg, its line graduated, its costume missing from the collection: it brings
    /// a costume (`ActiveNews.newCostume`), so it is no Spare. Kept rather than sent off for the Bag's Fossil Egg, its Rare
    /// Candies given. Once a graduated Squirtle wears that costume, it is a Spare again.
    func testACostumeTheCollectionLacksIsKept() async throws {
        func hatchedInCostume(dressed: Bool) async throws -> CompanionStore {
            var squirtle = graduated([7, 8, 9])
            squirtle.costume = "SUMMER_2018"
            let s = try store(active: nil, dex: ([[16, 17, 18]] + mostLines).map { graduated($0) } + (dressed ? [squirtle] : []),
                              inventory: [.fossilEgg: 1], index: releaseIndex, difficulty: 1) { st in
                st.claimedEventEggs = ["summer@2026"]
                st.eggFromCostume = CostumeEgg(id: "summer-7", code: "SUMMER_2018", speciesID: 7, form: nil, month: 8)
            }
            await s.hatch(baseID: 7)
            await s.loadHatchIndex()
            giveCandies(s, 3)
            return s
        }
        let kept = try await hatchedInCostume(dressed: false)
        XCTAssertEqual(kept.state.active?.costume, "SUMMER_2018")
        XCTAssertEqual(kept.activeVerdict, .newCostume)
        XCTAssertNil(kept.oakRelease)
        XCTAssertEqual(kept.oakSteps.first, .raise)
        XCTAssertEqual(kept.candiesToGive, 3)
        let spare = try await hatchedInCostume(dressed: true)
        XCTAssertEqual(spare.activeVerdict, .spare)
        XCTAssertEqual(spare.oakRelease, .bag(.fossilEgg, odds: 1))
        XCTAssertEqual(spare.candiesToGive, 0)
    }

    /// The wait for the balance, at the player's pace (`UsageStore.dailyPace`): 300 M at 600 M a day, half a day.
    func testTheWaitForTheBalanceGoesAtThePlayersPace() throws {
        let s = try store(active: nil, dex: [])
        XCTAssertNil(s.timeToEarn(300_000_000), "pace unknown")
        s.usagePacePerDay = 600_000_000
        XCTAssertEqual(s.timeToEarn(300_000_000), 43_200)
    }

    // MARK: The stock and the Rare Candies to buy

    func testTheStockHoldsAnEggForEachNewPokemonItBringsThreeAtMost() {
        XCTAssertEqual(OakBudget.stockTarget(odds: 0.95), 1)
        XCTAssertEqual(OakBudget.stockTarget(odds: 0.45), 2)
        XCTAssertEqual(OakBudget.stockTarget(odds: 0.25), 3)
        XCTAssertEqual(OakBudget.stockTarget(odds: 0.05), 3, "three at most")
    }

    /// `releaseIndex` with Bulbasaur and Chikorita, Rare and missing: three of the six Rare lines bring something.
    private var stockIndex: [BaseSpecies] {
        releaseIndex + [BaseSpecies(id: 1, captureRate: 45), BaseSpecies(id: 152, captureRate: 45)]
    }

    /// The Shop's prices scale with the difficulty (`shopDifficulty`).
    private func prices(difficulty: Double = PokemonBalance.difficulty) throws -> (rare: Int, candy: Int) {
        let s = try store(active: nil, dex: [], difficulty: difficulty)
        return (s.price(of: .egg(.rare)), try XCTUnwrap(s.price(of: .rareCandy)))
    }

    /// The Spare goes for an Uncommon Egg and leaves one in the Bag, as good as the Rare+ Egg (one in two): of a stock
    /// of two, one Rare+ Egg is bought ahead and the rest goes into Rare Candies. Short of its price, the balance is
    /// kept aside for it.
    func testTheStockCountsTheBagsEggsThenTheRestGoesIntoCandies() async throws {
        let (rare, candy) = try prices()
        let bag: [ItemKind: Int] = [.uncommonEgg: 2, .pokemonEgg: 2]
        var s = try await spareStore(bag: bag, index: stockIndex, wallet: rare + 2 * candy + 7)
        XCTAssertEqual(s.oakRelease, .bag(.uncommonEgg, odds: odds(1, of: 2)))
        XCTAssertEqual(s.oakBudget, OakBudget(egg: .rareEgg, odds: odds(1, of: 2), target: 2, held: 1, buyAhead: 1,
                                              waitsForNext: false, reserve: 0, candies: 2))
        s = try await spareStore(bag: bag, index: stockIndex, wallet: rare / 2)
        XCTAssertEqual(s.oakBudget, OakBudget(egg: .rareEgg, odds: odds(1, of: 2), target: 2, held: 1, buyAhead: 0,
                                              waitsForNext: false, reserve: rare, candies: 0))
    }

    /// The one egg that holds the stock goes to the next Pokémon sent off, not this one: Oak says so and gives the next
    /// one's price, with no reserve nor fewer candies (Q24, Q30). Two in the Bag leave one after it.
    func testTheBagsLastEggIsSaidToGoToTheNextSendOff() async throws {
        let (_, candy) = try prices()
        func charmander(_ eggs: Int) async throws -> CompanionStore {
            let s = try store(active: mon([4], rarity: .rare), dex: [graduated([10, 11, 12]), graduated([16, 17, 18])],
                              inventory: [.rareEgg: eggs], index: releaseIndex) { st in
                st.lastHatchedBaseID = 4
                st.claimedEventEggs = ["summer@2026"]
                st.usedSinceInstall = 2 * candy
            }
            await s.loadHatchIndex()
            return s
        }
        var s = try await charmander(1)
        let budget = try XCTUnwrap(s.oakBudget)
        XCTAssertEqual(s.oakRelease, nil)
        XCTAssertEqual([budget.target, budget.held, budget.buyAhead, budget.reserve, budget.candies], [1, 1, 0, 0, 2])
        XCTAssertTrue(budget.takesTheLast)
        XCTAssertTrue(s.oakSteps.contains(.stock(budget)))
        s = try await charmander(2)
        XCTAssertEqual(s.oakBudget?.takesTheLast, false)
        XCTAssertFalse(s.oakSteps.contains { if case .stock = $0 { return true }; return false })
    }

    /// No egg bought ahead that what hatches next may leave with nothing to bring: Torchic, the one Rare line missing,
    /// may come from the Fire Stone the Spare goes for. Its price is kept aside.
    func testNoEggBoughtAheadThatTheNextHatchMayLeaveWithNothing() async throws {
        let (rare, _) = try prices()
        var s = try await spareStore(bag: [.fireStone: 1], wallet: 10 * rare)
        XCTAssertEqual(s.oakRelease, .bag(.fireStone, odds: odds(1, of: 2)))
        XCTAssertEqual(s.oakBudget?.buyAhead, 0)
        XCTAssertEqual(s.oakBudget?.waitsForNext, true)
        XCTAssertEqual(s.oakBudget?.reserve, 3 * rare, "a stock of three for one in four")
        // Bulbasaur and Chikorita missing too: whatever the Fire Stone brings, the Rare+ Egg still can.
        s = try await spareStore(bag: [.fireStone: 1], index: stockIndex, wallet: 10 * rare)
        XCTAssertEqual(s.oakBudget?.buyAhead, 2)
        // Torchic raised, the one Rare line left to draw (`withoutLastHatched`): once graduated, it is not new anymore.
        s = try store(active: mon([255], rarity: .rare), dex: [graduated([10, 11, 12])],
                      index: [BaseSpecies(id: 255, captureRate: 45), BaseSpecies(id: 10, captureRate: 255)]) { st in
            st.lastHatchedBaseID = 255
            st.claimedEventEggs = ["summer@2026"]
            st.usedSinceInstall = 10 * rare
        }
        await s.loadHatchIndex()
        XCTAssertEqual(s.activeVerdict, .lineToComplete(newSpecies: 3...3))
        XCTAssertEqual(s.oakBudget?.egg, .rareEgg)
        XCTAssertEqual(s.oakBudget?.buyAhead, 0, "the Pokémon raised")
        XCTAssertEqual(s.oakBudget?.waitsForNext, true)
    }

    /// The egg incubating, read by its own draws, never by the Pokémon it already rolled (`pendingHatchID`), which stays
    /// hidden until it hatches. Torchic is the one Rare line missing.
    func testTheEggIncubatingIsReadByWhatItMayHatchNotByWhatItRolled() async throws {
        let (rare, _) = try prices()
        func buyAhead(_ prepare: (inout CompanionState) -> Void) async throws -> Int? {
            let s = try store(active: nil, dex: ([[16, 17, 18]] + mostLines).map { graduated($0) }, index: releaseIndex) { st in
                st.lastHatchedBaseID = 16
                st.claimedEventEggs = ["summer@2026"]
                st.usedSinceInstall = 10 * rare
                prepare(&st)
            }
            await s.loadHatchIndex()
            return s.oakBudget?.buyAhead
        }
        let fire = try await buyAhead { $0.eggTypeGuarantee = .fire }
        XCTAssertEqual(fire, 0, "a Fire Stone's egg may bring Torchic")
        let charmander = try await buyAhead { $0.eggTypeGuarantee = .fire; $0.pendingHatchID = 4 }
        XCTAssertEqual(charmander, 0, "the roll stays hidden until the egg hatches")
        let torchic = try await buyAhead { $0.eggTypeGuarantee = .fire; $0.pendingHatchID = 255 }
        XCTAssertEqual(torchic, 0)
        let typeNull = try await buyAhead { $0.eggFromTypeNullEgg = true }
        XCTAssertEqual(typeNull, 3, "a Type: Null Egg brings Type: Null")
        let fossil = try await buyAhead { $0.eggFromFossilEgg = true }
        XCTAssertEqual(fossil, 3, "a Fossil Egg brings Kabuto")
        let birthday = try await buyAhead { $0.eggFromBirthdayEgg = true }
        XCTAssertEqual(birthday, 3, "a Birthday Egg, no legendary to draw")
        let costume = try await buyAhead {
            $0.eggFromCostume = CostumeEgg(id: "summer-7", code: "SUMMER_2018", speciesID: 7, form: nil, month: 8)
        }
        XCTAssertEqual(costume, 3, "a Costume Egg brings its costumed Squirtle")
    }

    /// The Rare Candies the balance buys go to the Pokémon raised as well. Caterpie graduated, the Rare+ Egg brings
    /// something new more often than the Pokémon Egg: one is bought ahead.
    func testTheCandiesBoughtAreGivenToo() async throws {
        let (rare, candy) = try prices(difficulty: 1)
        let s = try store(active: nil, dex: [graduated([10, 11, 12])], index: releaseIndex, difficulty: 1) { st in
            st.claimedEventEggs = ["summer@2026"]
            st.usedSinceInstall = rare + 2 * candy
        }
        await s.hatch(baseID: 16)
        await s.loadHatchIndex()
        XCTAssertEqual(s.activeVerdict, .lineToComplete(newSpecies: 3...3))
        XCTAssertEqual(s.oakBudget, OakBudget(egg: .rareEgg, odds: 1, target: 1, held: 0, buyAhead: 1, waitsForNext: false,
                                              reserve: 0, candies: 2))
        XCTAssertEqual(s.candiesToGive, 2)
    }

    /// The Shiny Charm brings the Form Pokédex nothing: proposed for shinies until bought, or once every hatch is shiny.
    func testTheShinyCharmIsProposedUntilBought() throws {
        XCTAssertTrue(try store(active: mon([16]), dex: []).proposesShinyCharm)
        XCTAssertFalse(try store(active: mon([16]), dex: [], inventory: [.shinyCharm: 1]).proposesShinyCharm)
        XCTAssertFalse(try store(active: mon([16]), dex: [], inventory: [.glimmeringCharm: 1]).proposesShinyCharm)
    }

    // MARK: The steps

    /// The Rare Candies to buy and what becomes of them make one step: kept for the next one when the Spare is sent off,
    /// given to the Pokémon raised as far as its growth takes them.
    func testTheCandiesBoughtAndWhereTheyGoMakeOneStep() async throws {
        let (rare, candy) = try prices()
        let spare = try await spareStore(bag: [.uncommonEgg: 2, .pokemonEgg: 2], index: stockIndex,
                                         wallet: rare + 2 * candy + 7)
        let stock = try XCTUnwrap(spare.oakBudget)
        XCTAssertEqual(spare.oakSteps, [.release(.bag(.uncommonEgg, odds: odds(1, of: 2))), .stock(stock),
                                        .candies(buy: 2, give: 0, keep: 2)])

        let (rareAtOne, candyAtOne) = try prices(difficulty: 1)
        let raised = try store(active: nil, dex: [graduated([10, 11, 12])], index: releaseIndex, difficulty: 1) { st in
            st.claimedEventEggs = ["summer@2026"]
            st.usedSinceInstall = rareAtOne + 2 * candyAtOne
        }
        await raised.hatch(baseID: 16)
        await raised.loadHatchIndex()
        let ahead = try XCTUnwrap(raised.oakBudget)
        XCTAssertEqual(raised.oakSteps, [.raise, .stock(ahead), .candies(buy: 2, give: 2, keep: 0)])
    }

    /// Before the index is loaded, the egg a Spare goes for is unknown: Oak gives his verdict and no step.
    func testASpareWhoseEggIsNotKnownYetHasNoStep() throws {
        let s = try store(active: mon([16]), dex: [graduated([16, 17, 18])], inventory: [.rareCandy: 2])
        XCTAssertEqual(s.activeVerdict, .spare)
        XCTAssertEqual(s.oakSteps, [])
    }

    // MARK: First shinies

    /// A hatch also brings something when it shines in a form whose shiny no graduated Pokémon holds: one time in 64,
    /// 48 with the Shiny Charm, every time with the Glimmering Charm.
    func testAnEggsOddsCountTheFirstShiniesItMayHatch() async throws {
        func rareOdds(shinyHeld: Bool = false, bag: [ItemKind: Int] = [:]) async throws -> Double? {
            var charmander = graduated([4, 5, 6])
            charmander.isShiny = shinyHeld
            let s = try store(active: mon([16]), dex: [charmander], inventory: bag,
                              index: [BaseSpecies(id: 4, captureRate: 45)])
            await s.loadHatchIndex()
            return s.newOdds(item: .rareEgg)
        }
        let plain = try await rareOdds()
        XCTAssertEqual(plain, 1.0 / 64)
        let held = try await rareOdds(shinyHeld: true)
        XCTAssertEqual(held, 0)
        let charm = try await rareOdds(bag: [.shinyCharm: 1])
        XCTAssertEqual(charm, 1.0 / 48)
        let glimmering = try await rareOdds(bag: [.glimmeringCharm: 1])
        XCTAssertEqual(glimmering, 1)
    }

    /// The odds are kept between two reads, until the save changes: the Shiny Charm bought, the Rare+ Egg's first
    /// shinies come one time in 48.
    func testTheOddsKeptFollowTheSave() async throws {
        let (rare, _) = try prices()
        let s = try store(active: mon([16]), dex: [graduated([4, 5, 6])], index: [BaseSpecies(id: 4, captureRate: 45)]) {
            $0.usedSinceInstall = 3 * rare
        }
        await s.loadHatchIndex()
        XCTAssertEqual(s.newOdds(item: .rareEgg), 1.0 / 64)
        XCTAssertEqual(s.newOdds(item: .rareEgg), 1.0 / 64)
        XCTAssertTrue(s.buy(.shinyCharm))
        XCTAssertEqual(s.newOdds(item: .rareEgg), 1.0 / 48)
    }

    /// Most event eggs hatch shiny every time (`EventEgg.alwaysShiny`), and so does a Birthday Egg once every legendary
    /// is graduated: the first shinies they may bring come for sure.
    func testAnAlwaysShinyEggBringsItsFirstShiniesForSure() async throws {
        let s = try store(active: mon([16]), dex: [graduated([92, 93, 94]), graduated([144], rarity: .legendary)],
                          index: [BaseSpecies(id: 92, captureRate: 190),
                                  BaseSpecies(id: 144, captureRate: 3, isLegendary: true)])
        await s.loadHatchIndex()
        XCTAssertEqual(s.newOdds(item: EventEgg.halloween.item), 1, "Gastly, shiny for sure")
        XCTAssertEqual(s.newOdds(item: .birthdayEgg), 1, "every legendary graduated: Articuno, shiny for sure")
    }

    /// Once every species and form is graduated, the Rare+ Egg still brings first shinies: two lines, so whatever hatches
    /// next, it keeps one, and the stock is bought ahead.
    func testAStockOfFirstShiniesIsBoughtAhead() async throws {
        let (rare, _) = try prices()
        var caterpie = graduated([10, 11, 12])
        caterpie.isShiny = true
        let s = try store(active: nil, dex: [graduated([4, 5, 6]), graduated([7, 8, 9]), caterpie],
                          index: [BaseSpecies(id: 4, captureRate: 45), BaseSpecies(id: 7, captureRate: 45),
                                  BaseSpecies(id: 10, captureRate: 255)]) { $0.usedSinceInstall = 3 * rare }
        await s.loadHatchIndex()
        XCTAssertEqual(s.oakBudget?.egg, .rareEgg)
        XCTAssertEqual(s.oakBudget?.waitsForNext, false)
        XCTAssertEqual(s.oakBudget?.buyAhead, 3)
    }
}
