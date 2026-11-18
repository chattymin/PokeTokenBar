import XCTest
@testable import PokeTokenBar

private struct FormProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: baseSpeciesID, tree: EvoNode(speciesID: baseSpeciesID, children: []), rarity: .common, names: [:])
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [BaseSpecies(id: 479, captureRate: 45)] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

/// The forms achievements: every form of one species graduated earns candies or eggs, and the Rotom Catalog a candy
/// for each Pokémon graduated in a form its line never graduated.
@MainActor
final class FormAchievementsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func store(dex: [DexEntry] = [], active: MonState? = nil, inventory: [ItemKind: Int] = [:],
                       seed: UInt64 = 1) throws -> CompanionStore {
        var st = CompanionState()
        st.installBaselineSet = true
        st.lastDate = "2026-10-27"
        st.dex = dex
        st.active = active
        st.inventory = Dictionary(uniqueKeysWithValues: inventory.map { ($0.key.rawValue, $0.value) })
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("forms-\(UUID().uuidString).json")
        try JSONEncoder().encode(st).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return CompanionStore(provider: FormProvider(), clock: { self.now }, fileURL: url, rng: SeededRNG(seed: seed))
    }

    private func graduated(_ chain: [Int], _ form: String, released: Bool = false) -> DexEntry {
        DexEntry(baseID: chain[0], finalID: chain.last!, chainOrder: chain, rarity: .common, caughtAt: now,
                 releasedAt: released ? now : nil, form: PokemonForm(form))
    }

    private func every(_ kind: ItemKind, chain: [Int]) throws -> [DexEntry] {
        guard case .forms(let goal) = kind.unlock else { throw XCTSkip("\(kind) is no forms achievement") }
        return goal.forms.map { graduated(chain, $0.rawValue) }
    }

    /// [Regression] The tab bar's achievement count is kept until the state changes (#183: it read the whole Pokédex
    /// for each form goal at each opening of the popover). A graduation in the last form missing counts at once.
    func testTheAchievementCountFollowsAGraduation() async throws {
        guard case .forms(let goal) = ItemKind.rotomCatalog.unlock, let last = goal.forms.last else { return XCTFail() }
        var mon = MonState(baseID: 479, pathIDs: [479], stageIndex: 0, usedAtStage: 0, rarity: .common, totalForms: 1)
        mon.form = last
        let s = try store(dex: goal.forms.dropLast().map { graduated([479], $0.rawValue) }, active: mon)
        XCTAssertFalse(s.isUnlocked(.rotomCatalog))
        let before = s.achievementTally(in: .forms).ready
        s.update(todayTokensByProvider: ["test": 0], todayDate: "2026-10-27", monthTotal: 0, burnTier: .idle,
                 limitWarning: false, hasUsageData: true)
        for _ in 0..<50 where s.currentLine == nil { await Task.yield() }
        s.applyUsage(s.stageThreshold(for: mon))
        XCTAssertNil(s.state.active, "graduated")
        XCTAssertTrue(s.isUnlocked(.rotomCatalog))
        XCTAssertEqual(s.achievementTally(in: .forms).ready, before + 1, "counted at once, not the count kept from before")
        XCTAssertEqual(s.unclaimedAchievementsCount, s.achievementTally().ready)
    }

    /// Each achievement counts its species' forms, Minior's seven cores without its Meteor shell.
    func testEachAchievementAsksForEveryFormOfItsSpecies() {
        let expected: [(ItemKind, Int, Int)] = [(.rotomCatalog, 479, 6), (.cometShard, 774, 7), (.redNectar, 741, 4),
                                                (.smoothRock, 351, 4), (.sawsbuckSeasons, 586, 4), (.fairyFeather, 671, 5),
                                                (.furfrouTrims, 676, 10), (.vivillonPatterns, 666, 20),
                                                (.whippedDream, 869, 63), (.unownLetters, 201, 28),
                                                (.taurosBreeds, 128, 4), (.necrozmaForms, 800, 4),
                                                // #135 (the owner, 2026-11-06): every final species of three forms or more.
                                                (.deoxysFormes, 386, 4), (.wormadamCloaks, 413, 3), (.darmanitanModes, 555, 4),
                                                (.kyuremFusions, 646, 3), (.genesectDrives, 649, 5), (.gourgeistSizes, 711, 4),
                                                (.zygardeFormes, 718, 3), (.lycanrocForms, 745, 3), (.cramorantForms, 845, 3),
                                                (.calyrexSteeds, 898, 3), (.squawkabillyPlumages, 931, 4), (.tatsugiriForms, 978, 3),
                                                (.ogerponMasks, 1017, 4), (.terapagosForms, 1024, 3)]
        for (kind, species, count) in expected {
            guard case .forms(let goal) = kind.unlock else { return XCTFail("\(kind)") }
            XCTAssertEqual(goal.speciesID, species, "\(kind)")
            XCTAssertEqual(goal.forms.count, count, "\(kind)")
            XCTAssertEqual(kind.collectorGroup, .forms)
        }
        guard case .forms(let minior) = ItemKind.cometShard.unlock else { return XCTFail() }
        XCTAssertFalse(minior.forms.contains(PokemonForm("meteor")))
        XCTAssertEqual(Set(ItemKind.allCases.filter { $0.collectorGroup == .forms }).count, expected.count)
    }

    /// #135's rule, kept by the catalog: every final species with three forms or more that eggs roll has its
    /// achievement, except the item-made ones (Arceus's Plates, Silvally's Memories); two forms never ask for one.
    func testEverySpeciesOfThreeFormsHasItsAchievement() {
        let asked = Set(ItemKind.allCases.compactMap { kind -> Int? in
            guard case .forms(let goal) = kind.unlock else { return nil }
            return goal.speciesID
        })
        for species in 1...1025 where SpeciesInfo.isFinal(species) && PokemonForm.unlockSources[species] == nil {
            let forms = PokemonForm.forms(speciesID: species)
            let rollable = Set(HatchRules.current.rollableForms(baseID: SpeciesInfo.baseID(of: species)))
            guard forms.count >= 3, forms.allSatisfy(rollable.contains) else { continue }
            XCTAssertTrue(asked.contains(species), "\(species) has \(forms.count) forms and no achievement")
        }
        for species in asked { XCTAssertGreaterThanOrEqual(FormGoal(species).forms.count, 3, "\(species)") }
    }

    /// Graduated forms only: one missing, released or being raised keeps it locked.
    func testOnlyEveryGraduatedFormUnlocksIt() throws {
        let all = try every(.redNectar, chain: [741])
        XCTAssertTrue(try store(dex: all).isUnlocked(.redNectar))
        XCTAssertFalse(try store(dex: Array(all.dropLast())).isUnlocked(.redNectar), "a style missing")
        var released = all
        released[0].releasedAt = now
        XCTAssertFalse(try store(dex: released).isUnlocked(.redNectar), "a style sent off")
        let raising = MonState(baseID: 741, pathIDs: [741], stageIndex: 0, usedAtStage: 0, rarity: .common, totalForms: 1,
                               form: all.last!.form)
        XCTAssertFalse(try store(dex: Array(all.dropLast()), active: raising).isUnlocked(.redNectar), "a style being raised")
        XCTAssertEqual(try store(dex: Array(all.dropLast())).formProgress(FormGoal(741)).count, 3)

        // Vivillon's patterns count on Vivillon itself, whatever Scatterbug and Spewpa wore.
        XCTAssertTrue(try store(dex: try every(.vivillonPatterns, chain: [664, 665, 666])).isUnlocked(.vivillonPatterns))
    }

    /// Claimed, they put candies and eggs in the Bag, never themselves; the Rotom Catalog stays.
    func testTheirRewardsGoToTheBag() throws {
        let rewards: [(ItemKind, [Int], [ItemKind: Int])] = [
            (.cometShard, [774], [.rareCandy: 5]), (.redNectar, [741], [.rareCandy: 3]), (.smoothRock, [351], [.rareCandy: 3]),
            (.sawsbuckSeasons, [585, 586], [.uncommonEgg: 1]), (.fairyFeather, [669, 670, 671], [.uncommonEgg: 1]),
            (.furfrouTrims, [676], [.rareEgg: 1]), (.vivillonPatterns, [664, 665, 666], [.rareEgg: 2]),
            (.whippedDream, [868, 869], [.rareEgg: 2, .rareCandy: 5]), (.unownLetters, [201], [.rareEgg: 2]),
            // #135: a legendary's a Rare Egg and five candies, four forms an Uncommon Egg, three forms three candies.
            (.kyuremFusions, [646], [.rareEgg: 1, .rareCandy: 5]), (.genesectDrives, [649], [.rareEgg: 1, .rareCandy: 5]),
            (.darmanitanModes, [554, 555], [.uncommonEgg: 1]), (.lycanrocForms, [744, 745], [.rareCandy: 3]),
            (.wormadamCloaks, [412, 413], [.rareCandy: 3]),
        ]
        for (kind, chain, items) in rewards {
            let s = try store(dex: try every(kind, chain: chain))
            XCTAssertTrue(s.isUnlocked(kind), "\(kind)")
            XCTAssertTrue(s.claimAchievement(kind), "\(kind)")
            for (item, count) in items { XCTAssertEqual(s.itemCount(item), count, "\(kind) gives \(item)") }
            XCTAssertEqual(s.itemCount(kind), 0, "\(kind) is not kept")
            XCTAssertTrue(s.isClaimed(kind))
            XCTAssertFalse(s.claimAchievement(kind), "once")
        }
        // Tauros's and Necrozma's rewards are artifacts, kept in the Bag (the owner, 2026-11-05).
        for (kind, chain) in [(ItemKind.taurosBreeds, [128]), (.necrozmaForms, [800])] {
            let s = try store(dex: try every(kind, chain: chain))
            XCTAssertFalse(try store(dex: Array(try every(kind, chain: chain).dropLast())).isUnlocked(kind), "\(kind): one missing")
            XCTAssertTrue(s.claimAchievement(kind), "\(kind)")
            XCTAssertEqual(s.itemCount(kind), 1, "\(kind) is kept")
            XCTAssertEqual(BonusTheme.of(kind), .eggs)
        }
        let rotom = try store(dex: try every(.rotomCatalog, chain: [479]))
        XCTAssertTrue(rotom.claimAchievement(.rotomCatalog))
        XCTAssertEqual(rotom.itemCount(.rotomCatalog), 1)
        XCTAssertEqual(BonusTheme.of(.rotomCatalog), .candies)
    }

    /// The Rotom Catalog pays one candy when a Pokémon graduates in a form its line never graduated, nothing at the
    /// hatch. Paid at the hatch, a form sent off before graduating paid again each time it hatched (#91). A form only
    /// sent off (Wash here) still pays once graduated.
    func testTheRotomCatalogPaysForANewFormGraduated() async throws {
        let heat = graduated([479], "heat")
        let wash = graduated([479], "wash", released: true)
        var paid = Set<Bool>()
        for seed: UInt64 in 1...24 {
            let s = try store(dex: [heat, wash], inventory: [.rotomCatalog: 1], seed: seed)
            await s.hatch(baseID: 479)
            let mon = try XCTUnwrap(s.state.active)
            XCTAssertEqual(s.itemCount(.rareCandy), 0, "nothing at the hatch, seed \(seed)")
            s.applyUsage(100_000_000_000)
            XCTAssertNil(s.state.active, "graduated, seed \(seed)")
            XCTAssertEqual(s.itemCount(.rareCandy), mon.form == PokemonForm("heat") ? 0 : 1,
                           "seed \(seed), \(String(describing: mon.form))")
            XCTAssertNotEqual(mon.form, PokemonForm("heat"), "a missing form first (`missingFormsFirst`), seed \(seed)")
            paid.insert(s.itemCount(.rareCandy) > 0)
        }
        XCTAssertEqual(paid, [true], "every hatch brings a form never graduated, so every graduation pays")

        let without = try store(dex: [heat])
        await without.hatch(baseID: 479)
        without.applyUsage(100_000_000_000)
        XCTAssertEqual(without.itemCount(.rareCandy), 0, "no Catalog, no candy")
    }

    /// On a line whose species branch (Slowpoke into Slowbro or Slowking, Burmy into Mothim or Wormadam), a form the
    /// line graduated once pays nothing again: it read "every species of the line in this form", and a Kanto Slowking
    /// paid after a Kanto Slowbro.
    func testTheRotomCatalogPaysOncePerFormOnBranchedLines() async throws {
        for (chain, known) in [([79, 80], "normal"), ([412, 414], "plant")] {
            var paid = Set<Bool>()
            for seed: UInt64 in 1...16 {
                let s = try store(dex: [graduated(chain, known)], inventory: [.rotomCatalog: 1], seed: seed)
                await s.hatch(baseID: chain[0])
                let form = try XCTUnwrap(s.state.active?.form, "\(chain[0]), seed \(seed)")
                s.applyUsage(100_000_000_000)
                XCTAssertNil(s.state.active)
                XCTAssertEqual(s.itemCount(.rareCandy), form == PokemonForm(known) ? 0 : 1, "\(chain[0]) \(form), seed \(seed)")
                paid.insert(s.itemCount(.rareCandy) > 0)
            }
            XCTAssertEqual(paid, [true, false], "\(chain[0])")
        }
    }

    /// Graduated again, a form pays nothing: ten Rotom for six forms, so one comes twice.
    func testTheRotomCatalogPaysEachFormOnce() async throws {
        let s = try store(inventory: [.rotomCatalog: 1], seed: 3)
        var graduatedForms = Set<PokemonForm>()
        for round in 0..<10 {
            await s.hatch(baseID: 479)
            let form = try XCTUnwrap(s.state.active?.form, "round \(round)")
            let before = s.itemCount(.rareCandy)
            s.applyUsage(100_000_000_000)
            XCTAssertNil(s.state.active, "round \(round)")
            XCTAssertEqual(s.itemCount(.rareCandy) - before, graduatedForms.contains(form) ? 0 : 1, "round \(round), \(form)")
            graduatedForms.insert(form)
        }
        XCTAssertLessThan(graduatedForms.count, 10, "a form graduated twice")
    }
}
