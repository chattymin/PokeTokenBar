import XCTest
@testable import PokeTokenBar

/// The costumed Pokémon of Pokémon GO (the owner, 2026-11-13: "la collection qui se renouvelle"): a lot a month, a
/// Costume Egg every 300M tokens, its first costumed stage growing in its costume, a collection of its own.
@MainActor
final class CostumeTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    /// Pichu's line as PokéAPI has it, Eevee's with its eight branches; any other line, its base alone.
    private struct Lines: PokeProviding {
        func line(baseSpeciesID id: Int) async throws -> EvoLine {
            let tree: EvoNode
            switch id {
            case 172: tree = EvoNode(speciesID: 172, children: [EvoNode(speciesID: 25, children: [EvoNode(speciesID: 26, children: [])])])
            case 133: tree = EvoNode(speciesID: 133, children: [134, 135, 136, 196, 197, 470, 471, 700].map { EvoNode(speciesID: $0, children: []) })
            default: tree = EvoNode(speciesID: id, children: [])
            }
            return EvoLine(baseID: id, tree: tree, rarity: SpeciesInfo.lineRarity(of: id), names: [:])
        }
        func baseSpeciesIndex() async throws -> [BaseSpecies] { [BaseSpecies(id: 172, captureRate: 190)] }
    }

    private func store(prepare: (inout CompanionState) -> Void = { _ in }) throws -> CompanionStore {
        var st = CompanionState()
        st.installBaselineSet = true
        st.lastDate = "2026-12-05"
        st.claimedTodayTokensByProvider = ["test": 0]
        st.active = MonState(baseID: 16, pathIDs: [16], stageIndex: 0, usedAtStage: 0, rarity: .common, totalForms: 3)
        prepare(&st)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("costume-\(UUID().uuidString).json")
        try JSONEncoder().encode(st).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return CompanionStore(provider: Lines(), clock: { self.now }, fileURL: url, rng: SeededRNG(seed: 5), difficulty: 0.1)
    }

    private func egg(_ code: String, _ species: Int, month: Int = 12) -> CostumeEgg {
        CostumeEgg(id: "\(code)-\(species)", code: code, speciesID: species, form: nil, month: month)
    }

    /// Grows the Pokémon raised until it graduates, at most `stages` evolutions on.
    private func growToTheEnd(_ s: CompanionStore) {
        for _ in 0..<6 {
            guard let mon = s.state.active else { return }
            s.applyUsage(s.stageThreshold(for: mon))
        }
    }

    // MARK: The catalog

    func testTheCatalogHasALotEachMonth() {
        XCTAssertEqual(CostumeCatalog.entries.count, 217)
        XCTAssertEqual(Set(CostumeCatalog.entries.map(\.key)).count, 217, "each once")
        for month in 1...12 {
            XCTAssertFalse(CostumeCatalog.lot(month: month).isEmpty, "\(month)")
            XCTAssertFalse(CostumeCatalog.starts(month: month).isEmpty, "\(month)")
        }
        let starts = CostumeCatalog.starts(month: 12).map(\.key)
        XCTAssertTrue(starts.contains("HOLIDAY_2016:172"), "Pichu in its hat")
        XCTAssertFalse(starts.contains("HOLIDAY_2016:25"), "its Pikachu grows from it")
        let pichu = try? XCTUnwrap(CostumeCatalog.byKey["HOLIDAY_2016:172"])
        XCTAssertEqual(pichu.map { CostumeCatalog.family(of: $0).map(\.speciesID) }, [172, 25, 26])
        // Pokémon GO's "can't evolve" costumes: each its own start, growing into nothing.
        let january = CostumeCatalog.starts(month: 1).map(\.key)
        XCTAssertTrue(["JAN_2020_NOEVOLVE:1", "JAN_2020_NOEVOLVE:2", "JAN_2020_NOEVOLVE:3"].allSatisfy(january.contains))
        XCTAssertEqual(CostumeCatalog.byKey["JAN_2020_NOEVOLVE:1"].map(CostumeCatalog.children), [])
        // A costume on a form: a Pumpkaboo's average size is its usual look.
        XCTAssertEqual(CostumeCatalog.entry(code: "FALL_2022", speciesID: 710, form: nil)?.key, "FALL_2022:710:average")
        XCTAssertEqual(CostumeCatalog.entry(code: "FALL_2022", speciesID: 710, form: PokemonForm("small"))?.key,
                       "FALL_2022:710:small")
        XCTAssertNil(CostumeCatalog.entry(code: "FALL_2022", speciesID: 25, form: nil))
    }

    func testTheImagesArePokeMinersStills() throws {
        let pikachu = CostumeCatalog.displayForm(code: "HOLIDAY_2016", form: nil)
        XCTAssertEqual(CostumeCatalog.spriteURL(speciesID: 25, display: pikachu, shiny: true)?.lastPathComponent,
                       "pm25.cHOLIDAY_2016.s.icon.png")
        let small = CostumeCatalog.displayForm(code: "FALL_2022", form: PokemonForm("small"))
        XCTAssertEqual(CostumeCatalog.spriteURL(speciesID: 710, display: small, shiny: false)?.lastPathComponent,
                       "pm710.fSMALL.cFALL_2022.icon.png")
        XCTAssertEqual(SpriteStore.spriteURLs(speciesID: 710, animated: true, shiny: false, form: small).map(\.lastPathComponent),
                       ["pm710.fSMALL.cFALL_2022.icon.png"], "a still, whatever is asked")
        XCTAssertNil(CostumeCatalog.spriteURL(speciesID: 25, display: nil, shiny: false))
        XCTAssertEqual(PokemonForm.resolved(speciesID: 25, form: pikachu), pikachu, "kept as it is shown")
        XCTAssertEqual(PikachuCostume.displayForm(speciesID: 25, form: pikachu), pikachu, "never under the equipped cap")
    }

    // MARK: The eggs

    /// One every 300M tokens, of the day's month, the missing ones first.
    func testAnEggEvery300MTokensOfTheMonthsLot() throws {
        let s = try store()
        s.earnCostumeEggs(250_000_000, day: "2026-12-05")
        XCTAssertTrue(s.state.costumeEggs.isEmpty)
        s.earnCostumeEggs(400_000_000, day: "2026-12-05")
        XCTAssertEqual(s.state.costumeEggs.count, 2)
        XCTAssertEqual(s.state.costumeEggTokens, 50_000_000, "the rest kept toward the next")
        let december = Set(CostumeCatalog.starts(month: 12).map(\.key))
        XCTAssertTrue(s.state.costumeEggs.allSatisfy { $0.month == 12 && december.contains($0.entry?.key ?? "") })
        XCTAssertNotEqual(s.state.costumeEggs[0].entry, s.state.costumeEggs[1].entry, "a costume waiting is not drawn again")
        s.earnCostumeEggs(300_000_000, day: "2027-01-02")
        XCTAssertEqual(s.state.costumeEggs.last?.month, 1, "January's lot in January")
    }

    /// The one missing comes first: with every costume of June in but one, the egg holds that one, whichever it is.
    func testTheMissingCostumeComesFirst() throws {
        let starts = CostumeCatalog.starts(month: 6)
        XCTAssertGreaterThan(starts.count, 3)
        for missing in starts {
            let s = try store {
                $0.dex = CostumeCatalog.lot(month: 6).filter { !CostumeCatalog.family(of: missing).contains($0) }.map { entry in
                    var record = DexEntry(baseID: SpeciesInfo.baseID(of: entry.speciesID), finalID: entry.speciesID,
                                          chainOrder: [entry.speciesID], rarity: .common, caughtAt: Date(), form: entry.form)
                    record.costume = entry.code
                    return record
                }
            }
            XCTAssertEqual(s.drawCostumeEgg(month: 6)?.entry, missing, missing.key)
        }
    }

    /// Once the whole lot is in: any of it again, for its shiny.
    func testAFullLotStillGivesEggs() throws {
        let starts = CostumeCatalog.starts(month: 6)
        let s = try store {
            $0.dex = CostumeCatalog.lot(month: 6).map { entry in
                var record = DexEntry(baseID: SpeciesInfo.baseID(of: entry.speciesID), finalID: entry.speciesID,
                                      chainOrder: [entry.speciesID], rarity: .common, caughtAt: Date(), form: entry.form)
                record.costume = entry.code
                return record
            }
        }
        XCTAssertEqual(s.ownedCostumeKeys().all, Set(CostumeCatalog.lot(month: 6).map(\.key)))
        let egg = try XCTUnwrap(s.drawCostumeEgg(month: 6))
        XCTAssertTrue(starts.map(\.key).contains(egg.entry?.key ?? ""))
    }

    /// The egg hatches its first costumed stage, which grows only into the stages wearing the costume and graduates
    /// wearing it: Pichu, Pikachu and Raichu in the same hat.
    func testItHatchesAndGrowsInItsCostume() async throws {
        let s = try store { $0.costumeEggs = [self.egg("HOLIDAY_2016", 172)] }
        XCTAssertTrue(s.useCostumeEgg("HOLIDAY_2016-172"))
        XCTAssertTrue(s.state.costumeEggs.isEmpty)
        s.setEggUsageForTesting(s.eggHatchThreshold)
        await s.hatchIfNeeded()
        let pichu = try XCTUnwrap(s.state.active)
        XCTAssertEqual(pichu.pathIDs, [172])
        XCTAssertEqual(pichu.costume, "HOLIDAY_2016")
        XCTAssertEqual(pichu.plannedPathIDs, [172, 25, 26])
        XCTAssertEqual(pichu.spriteForm, CostumeCatalog.displayForm(code: "HOLIDAY_2016", form: nil))
        XCTAssertEqual(pichu.hatch?.egg, .costume(code: "HOLIDAY_2016", speciesID: 172))
        XCTAssertNil(s.state.eggFromCostume)
        XCTAssertEqual(s.ownedCostumeKeys().all, ["HOLIDAY_2016:172"])
        growToTheEnd(s)
        XCTAssertNil(s.state.active, "graduated")
        let record = try XCTUnwrap(s.state.dex.last)
        XCTAssertEqual(record.chainOrder, [172, 25, 26])
        XCTAssertEqual(record.costume, "HOLIDAY_2016")
        XCTAssertEqual(record.spriteForm(), CostumeCatalog.displayForm(code: "HOLIDAY_2016", form: nil))
        XCTAssertEqual(s.ownedCostumeKeys().all, ["HOLIDAY_2016:172", "HOLIDAY_2016:25", "HOLIDAY_2016:26"])
    }

    /// [Regression of the plan] A costume starting mid-line (Pikachu and Raichu, no Pichu) hatches as Pikachu, and a
    /// "can't evolve" one stays as it hatched though its species evolves: the line's root never takes over.
    func testItStartsMidLineAndStopsWhereTheCostumeStops() async throws {
        let s = try store { $0.costumeEggs = [self.egg("FEB_2019", 25, month: 2), self.egg("JAN_2023_NOEVOLVE", 25, month: 1)] }
        XCTAssertTrue(s.useCostumeEgg("FEB_2019-25"))
        s.setEggUsageForTesting(s.eggHatchThreshold)
        await s.hatchIfNeeded()
        XCTAssertEqual(s.state.active?.pathIDs, [25])
        XCTAssertEqual(s.state.active?.plannedPathIDs, [25, 26])
        growToTheEnd(s)
        XCTAssertEqual(s.state.dex.last?.chainOrder, [25, 26])
        s.setEggUsageForTesting(s.eggHatchThreshold)
        await s.hatchIfNeeded()
        XCTAssertNotNil(s.state.active, "the next egg hatched: a Pokémon raised to send off")
        XCTAssertTrue(s.useCostumeEgg("JAN_2023_NOEVOLVE-25"))
        s.setEggUsageForTesting(s.eggHatchThreshold)
        await s.hatchIfNeeded()
        XCTAssertEqual(s.state.active?.plannedPathIDs, [25])
        growToTheEnd(s)
        XCTAssertEqual(s.state.dex.last?.chainOrder, [25], "a Pikachu, never a Raichu")
        XCTAssertEqual(s.state.dex.last?.finalID, 25)
    }

    /// The owner, 2026-11-13: Home says "New costume" for a costumed Pokémon whose species are all held but whose
    /// costume is not, "New" when a species is new, and nothing new once the costume is collected too.
    func testHomeSaysNewCostume() throws {
        func raised(_ dex: [DexEntry]) throws -> CompanionStore {
            try store {
                var mon = MonState(baseID: 172, pathIDs: [172, 25], plannedPathIDs: [172, 25, 26], stageIndex: 1,
                                   usedAtStage: 0, rarity: .common, totalForms: 3)
                mon.costume = "HOLIDAY_2016"
                $0.active = mon
                $0.dex = dex
            }
        }
        let plain = DexEntry(baseID: 172, finalID: 26, chainOrder: [172, 25, 26], rarity: .common, caughtAt: now)
        var dressed = plain
        dressed.costume = "HOLIDAY_2016"
        let costumeOnly = try XCTUnwrap(try raised([plain]).activeNews)
        XCTAssertEqual(costumeOnly.newSpecies, [])
        XCTAssertTrue(costumeOnly.newCostume, "the species held, the costume not")
        XCTAssertFalse(costumeOnly.isDuplicate)
        let both = try XCTUnwrap(try raised([]).activeNews)
        XCTAssertFalse(both.newSpecies.isEmpty, "a new species: plain New")
        let held = try XCTUnwrap(try raised([plain, dressed]).activeNews)
        XCTAssertFalse(held.newCostume)
        XCTAssertTrue(held.isDuplicate, "nothing new once the costume is in")
    }

    /// The costumed collection's medals (the owner, 2026-11-13): a step at 25 costumed, then 50, 100 and all, Rare Eggs
    /// and Rare Candies, a Legendary Egg at the end; and a step for each monthly lot completed.
    func testTheMedalsCountTheCostumesAndTheLots() throws {
        func dressed(_ entry: CostumeEntry) -> DexEntry {
            var record = DexEntry(baseID: SpeciesInfo.baseID(of: entry.speciesID), finalID: entry.speciesID,
                                  chainOrder: [entry.speciesID], rarity: .common, caughtAt: Date(), form: entry.form)
            record.costume = entry.code
            return record
        }
        let june = CostumeCatalog.lot(month: 6)
        let others = CostumeCatalog.entries.filter { $0.month != 6 }.prefix(25 - june.count)
        let s = try store { $0.dex = (june + others).map(dressed); $0.inventory = [:] }
        XCTAssertEqual(s.ownedCostumeKeys().all.count, 25)
        let steps = s.regionTiers(.costumeMedal)
        XCTAssertEqual(steps.map(\.isReady), [true, false, false, false], "25 of 50, 100 and 217")
        XCTAssertEqual(s.regionTiers(.costumeLotsMedal).map(\.isReady).filter { $0 }.count, 1, "June complete")
        XCTAssertGreaterThan(s.claimRegionTiers(.costumeMedal), 0)
        XCTAssertEqual(s.itemCount(.rareEgg), 1)
        XCTAssertEqual(s.itemCount(.rareCandy), 3)
        XCTAssertGreaterThan(s.claimRegionTiers(.costumeLotsMedal), 0)
        XCTAssertEqual(s.itemCount(.rareEgg), 2)
        XCTAssertTrue(s.regionTiers(.costumeMedal)[0].isDone)
        // The whole collection: every step of both, a Legendary Egg at the end of each.
        let all = try store { $0.dex = CostumeCatalog.entries.map(dressed); $0.inventory = [:] }
        _ = all.claimRegionTiers(.costumeMedal)
        XCTAssertEqual([all.itemCount(.rareEgg), all.itemCount(.rareCandy), all.itemCount(.legendaryEgg)], [6, 26, 1])
        _ = all.claimRegionTiers(.costumeLotsMedal)
        XCTAssertEqual([all.itemCount(.rareEgg), all.itemCount(.rareCandy), all.itemCount(.legendaryEgg)], [17, 53, 2],
                       "eleven lots a Rare Egg and two candies, the twelfth a Legendary Egg and five")
        XCTAssertEqual(CostumeMedals.rewards(step: 4).first?.kind, .legendaryEgg)
        XCTAssertEqual(CostumeMedals.lotRewards(step: 12).first?.kind, .legendaryEgg)
        XCTAssertTrue(CompanionStore.achievementItems.contains(.costumeMedal))
        XCTAssertTrue(CompanionStore.achievementItems.contains(.costumeLotsMedal))
    }

    /// A relaunch reloads the line: the costumed Pokémon keeps its costume's stages, not the line's root.
    func testARelaunchKeepsTheCostumesPath() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("costume-relaunch-\(UUID().uuidString).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        var st = CompanionState()
        st.installBaselineSet = true
        st.lastDate = "2026-02-05"
        st.claimedTodayTokensByProvider = ["test": 0]
        var mon = MonState(baseID: 172, pathIDs: [25], plannedPathIDs: [25, 26], stageIndex: 0, usedAtStage: 0,
                           rarity: .common, totalForms: 2)
        mon.costume = "FEB_2019"
        st.active = mon
        try JSONEncoder().encode(st).write(to: url)
        let s = CompanionStore(provider: Lines(), clock: { self.now }, fileURL: url, rng: SeededRNG(seed: 5), difficulty: 0.1)
        s.update(todayTokensByProvider: ["test": 0], todayDate: "2026-02-05", monthTotal: 0, burnTier: .idle,
                 limitWarning: false, hasUsageData: true)
        for _ in 0..<50 where s.currentLine == nil { await Task.yield() }
        XCTAssertNotNil(s.currentLine)
        XCTAssertEqual(s.state.active?.pathIDs, [25])
        XCTAssertEqual(s.state.active?.plannedPathIDs, [25, 26])
        XCTAssertEqual(s.state.active?.costume, "FEB_2019")
    }
}
