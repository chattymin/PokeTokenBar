import AppKit
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

    /// A Costume Egg as earned: its month only (the owner, 2026-11-18: what it holds is drawn when opened).
    private func egg(_ id: String, month: Int = 12) -> CostumeEgg { CostumeEgg(month: month, id: id) }

    /// A graduated Pokémon of this chain, no costume: its species held.
    private func plain(_ chain: [Int]) -> DexEntry {
        DexEntry(baseID: chain[0], finalID: chain.last ?? chain[0], chainOrder: chain, rarity: .common, caughtAt: now)
    }

    /// A graduated Pokémon wearing this costume: the costume collected.
    private func dressed(_ entry: CostumeEntry) -> DexEntry {
        var record = DexEntry(baseID: SpeciesInfo.baseID(of: entry.speciesID), finalID: entry.speciesID,
                              chainOrder: [entry.speciesID], rarity: .common, caughtAt: now, form: entry.form)
        record.costume = entry.code
        return record
    }

    private func costumes(_ keys: [String]) -> [CostumeEntry] { keys.compactMap { CostumeCatalog.byKey[$0] } }

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

    /// [Regression] The owner, 2026-11-16: Pokémon GO draws each Pokémon at its size on a 256 px canvas, and a costumed
    /// Eevee took a fifth of its cell. A costume's still is cropped to the Pokémon with a margin; any other still stays.
    func testACostumeStillIsCroppedToThePokemon() throws {
        let canvas = NSImage(size: NSSize(width: 256, height: 256), flipped: false) { _ in
            NSColor.systemOrange.setFill()
            NSRect(x: 100, y: 20, width: 50, height: 60).fill()
            return true
        }
        let costume = CostumeCatalog.displayForm(code: "NOVEMBER_2018", form: nil)
        let cropped = SpriteLoader.still(canvas, form: costume)
        // In the canvas's pixels, whatever the screen's scale.
        let full = try XCTUnwrap(canvas.cgImage(forProposedRect: nil, context: nil, hints: nil)).width
        let side = try XCTUnwrap(cropped.cgImage(forProposedRect: nil, context: nil, hints: nil)).width
        XCTAssertEqual(Double(side) / Double(full), 60 * 1.24 / 256, accuracy: 0.02, "the Pokémon's long side and a margin, not the canvas")
        XCTAssertTrue(SpriteLoader.still(canvas, form: nil) === canvas, "a PokéAPI still is drawn as it is")
        XCTAssertTrue(SpriteLoader.still(canvas, form: PokemonForm("alola")) === canvas)
    }

    // MARK: The eggs
    // MARK: The eggs

    /// One every 300M tokens, of the day's month; it holds its month only, what it gives is drawn when opened.
    func testAnEggEvery300MTokensOfTheMonthsLot() throws {
        let s = try store()
        s.earnCostumeEggs(250_000_000, day: "2026-12-05")
        XCTAssertTrue(s.state.costumeEggs.isEmpty)
        s.earnCostumeEggs(400_000_000, day: "2026-12-05")
        XCTAssertEqual(s.state.costumeEggs.count, 2)
        XCTAssertEqual(s.state.costumeEggTokens, 50_000_000, "the rest kept toward the next")
        XCTAssertEqual(s.state.costumeEggs.map(\.month), [12, 12])
        XCTAssertTrue(s.state.costumeEggs.allSatisfy { $0.entry == nil }, "nothing drawn yet")
        s.earnCostumeEggs(300_000_000, day: "2027-01-02")
        XCTAssertEqual(s.state.costumeEggs.last?.month, 1, "January's lot in January")
    }

    /// The owner, 2026-11-18: three eggs waiting for three costumes left, no fourth; a lot complete gives none.
    func testEggsStopOnceTheyCoverTheCostumesLeft() throws {
        let june = CostumeCatalog.lot(month: 6)
        let s = try store { $0.dex = june.dropFirst(3).map(self.dressed) }
        XCTAssertEqual(s.costumeEggsLeftToEarn(month: 6), 3)
        s.earnCostumeEggs(3_000_000_000, day: "2026-06-10")
        XCTAssertEqual(s.state.costumeEggs.count, 3, "as many as the costumes left")
        XCTAssertEqual(s.costumeEggsLeftToEarn(month: 6), 0)
        let full = try store { $0.dex = june.map(self.dressed) }
        full.earnCostumeEggs(3_000_000_000, day: "2026-06-10")
        XCTAssertTrue(full.state.costumeEggs.isEmpty, "the lot complete: no egg")
        XCTAssertNil(full.drawCostumeEgg(month: 6))
    }

    /// The owner, 2026-11-18: a season's eggs stack in the Bag as the other eggs do; a use opens one of the stack.
    func testASeasonsEggsStack() throws {
        let s = try store {
            $0.costumeEggs = [self.egg("b", month: 11), self.egg("a", month: 12), self.egg("c", month: 12), self.egg("d", month: 12)]
            $0.dex = [self.plain([172, 25, 26])]
        }
        XCTAssertEqual(s.costumeEggStacks.map(\.month), [12, 11], "this month's first, then the latest")
        XCTAssertEqual(s.costumeEggStacks.map(\.count), [3, 1])
        XCTAssertEqual(s.costumeEggStacks.first?.first.id, "a")
        XCTAssertTrue(s.useCostumeEgg("a"))
        XCTAssertEqual(s.costumeEggStacks.map(\.count), [2, 1], "one of the stack opened")
    }

    /// The owner, 2026-11-18: an egg gives only a Pokémon the player has; with none of its lot's, it stays locked.
    func testAnEggIsLockedUntilAPokemonOfItsLotIsHeld() throws {
        let none = try store { $0.costumeEggs = [self.egg("e")] }
        XCTAssertTrue(none.isCostumeEggLocked("e"))
        XCTAssertFalse(none.useCostumeEgg("e"))
        XCTAssertEqual(none.state.costumeEggs.count, 1, "kept, locked")
        let held = try store { $0.costumeEggs = [self.egg("e")]; $0.dex = [self.plain([172, 25, 26])] }
        XCTAssertFalse(held.isCostumeEggLocked("e"))
        XCTAssertTrue(held.costumeEggCandidates(month: 12).allSatisfy { [172, 25, 26].contains($0.speciesID) },
                      "only the Pichu line, the one held")
    }

    /// [Regression] The owner, 2026-11-18: a costumed Eevee grew into Eeveelutions never caught. The egg's Pokémon grows
    /// only into species already held.
    func testItGrowsOnlyIntoSpeciesHeld() async throws {
        let s = try store { $0.costumeEggs = [self.egg("e")]; $0.dex = [self.plain([133])] }
        XCTAssertEqual(s.costumeEggCandidates(month: 12).map(\.key), ["HOLIDAY_2022:133"])
        XCTAssertTrue(s.useCostumeEgg("e"))
        s.setEggUsageForTesting(s.eggHatchThreshold)
        await s.hatchIfNeeded()
        XCTAssertEqual(s.state.active?.costume, "HOLIDAY_2022")
        XCTAssertEqual(s.state.active?.plannedPathIDs, [133], "no Vaporeon nor any Eeveelution not held")
    }

    /// [Regression] The owner, 2026-11-19: an egg's Eevee, drawn for a missing Vaporeon, grew into Sylveon, whose
    /// costume was held. It grows only toward a costume still missing.
    func testItGrowsOnlyTowardACostumeMissing() async throws {
        let held = costumes(["HOLIDAY_2022:133", "HOLIDAY_2022:700"])
        let s = try store {
            $0.costumeEggs = [self.egg("e")]
            $0.dex = [self.plain([133, 134]), self.plain([133, 700])] + held.map(self.dressed)
        }
        XCTAssertEqual(s.costumeEggCandidates(month: 12).map(\.key), ["HOLIDAY_2022:133"], "for Vaporeon's")
        XCTAssertTrue(s.useCostumeEgg("e"))
        s.setEggUsageForTesting(s.eggHatchThreshold)
        await s.hatchIfNeeded()
        XCTAssertEqual(s.currentLine?.tree.children.map(\.speciesID), [134], "Sylveon's costume held: no way to it")
        XCTAssertEqual(s.state.active?.plannedPathIDs, [133, 134])
        // Eevee's own missing and every evolution's held: it graduates as it hatched.
        let line = EvoLine(baseID: 133, tree: EvoNode(speciesID: 133, children: [EvoNode(speciesID: 700, children: [])]),
                           rarity: .common, names: [:])
        let eeveeOnly = CompanionStore.costumeLine(line, start: 133, code: "HOLIDAY_2022", form: nil, owned: [133, 700],
                                                   taken: ["HOLIDAY_2022:700"])
        XCTAssertEqual(eeveeOnly?.tree.children.count, 0)
    }

    /// [Regression] A friend's report of 2026-11-16: a "can't evolve" costume counted at its hatch, so sending the
    /// Pokémon off at once kept it, and Home still said "New costume". As the Pokédex counts: collected once graduated.
    func testACostumeIsCollectedOnceGraduatedNeverSentOff() async throws {
        let s = try store { $0.costumeEggs = [self.egg("a", month: 1), self.egg("b", month: 1)]; $0.dex = [self.plain([25])] }
        XCTAssertTrue(s.useCostumeEgg("a"))
        s.setEggUsageForTesting(s.eggHatchThreshold)
        await s.hatchIfNeeded()
        let code = try XCTUnwrap(s.state.active?.costume)
        XCTAssertTrue(code.hasSuffix("_NOEVOLVE"), code)
        XCTAssertTrue(s.ownedCostumeKeys().all.isEmpty, "raised, not collected")
        XCTAssertTrue(s.useCostumeEgg("b"), "sent off for the next egg")
        XCTAssertTrue(s.state.dex.contains { $0.isReleased && $0.costume == code })
        XCTAssertTrue(s.ownedCostumeKeys().all.isEmpty, "sent off: not collected")
        s.setEggUsageForTesting(s.eggHatchThreshold)
        await s.hatchIfNeeded()
        let next = try XCTUnwrap(s.state.active?.costume)
        growToTheEnd(s)
        XCTAssertEqual(s.ownedCostumeKeys().all, ["\(next):25"], "graduated: collected")
    }

    /// The egg holds a costume missing, of a Pokémon held: with every costume of June in but one, that one.
    func testTheMissingCostumeComesFirst() throws {
        for missing in CostumeCatalog.starts(month: 6) {
            let family = CostumeCatalog.family(of: missing)
            let s = try store {
                $0.dex = CostumeCatalog.lot(month: 6).filter { !family.contains($0) }.map(self.dressed)
                    + [self.plain(family.map(\.speciesID))]
            }
            XCTAssertEqual(s.drawCostumeEgg(month: 6)?.entry, missing, missing.key)
        }
    }

    /// The egg hatches its first costumed stage, which grows only into the stages wearing the costume and graduates
    /// wearing it: Pichu, Pikachu and Raichu in the same hat.
    func testItHatchesAndGrowsInItsCostume() async throws {
        // December's other Pichu-line costumes already in: the Holiday 2016 hat is the one left.
        let others = costumes(["HOLIDAY_2023:25", "HOLIDAY_2023:26", "WINTER_2018:172", "WINTER_2018:25", "WINTER_2018:26"])
        let s = try store { $0.costumeEggs = [self.egg("e")]; $0.dex = [self.plain([172, 25, 26])] + others.map(self.dressed) }
        XCTAssertTrue(s.useCostumeEgg("e"))
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
        let hat: Set<String> = ["HOLIDAY_2016:172", "HOLIDAY_2016:25", "HOLIDAY_2016:26"]
        XCTAssertTrue(s.ownedCostumeKeys().all.isDisjoint(with: hat), "collected once graduated, as the Pokédex counts")
        XCTAssertTrue(s.costumesTaken().isSuperset(of: hat), "never drawn again meanwhile")
        growToTheEnd(s)
        XCTAssertNil(s.state.active, "graduated")
        let record = try XCTUnwrap(s.state.dex.last)
        XCTAssertEqual(record.chainOrder, [172, 25, 26])
        XCTAssertEqual(record.costume, "HOLIDAY_2016")
        XCTAssertEqual(record.spriteForm(), CostumeCatalog.displayForm(code: "HOLIDAY_2016", form: nil))
        XCTAssertTrue(s.ownedCostumeKeys().all.isSuperset(of: hat))
    }

    /// [Regression of the plan] A costume starting mid-line (Pikachu and Raichu, no Pichu) hatches as Pikachu, and a
    /// "can't evolve" one stays as it hatched though its species evolves: the line's root never takes over.
    func testItStartsMidLineAndStopsWhereTheCostumeStops() async throws {
        // February's other Pikachu costumes already in: the 2019 one, on Pikachu and Raichu, is left.
        let february = CostumeCatalog.lot(month: 2).filter { [25, 26].contains($0.speciesID) && $0.code != "FEB_2019" }
        let s = try store {
            $0.costumeEggs = [self.egg("feb", month: 2), self.egg("jan", month: 1)]
            $0.dex = [self.plain([172, 25, 26])] + february.map(self.dressed)
        }
        XCTAssertEqual(s.costumeEggCandidates(month: 2).map(\.key), ["FEB_2019:25"])
        XCTAssertTrue(s.useCostumeEgg("feb"))
        s.setEggUsageForTesting(s.eggHatchThreshold)
        await s.hatchIfNeeded()
        XCTAssertEqual(s.state.active?.pathIDs, [25])
        XCTAssertEqual(s.state.active?.plannedPathIDs, [25, 26])
        growToTheEnd(s)
        XCTAssertEqual(s.state.dex.last?.chainOrder, [25, 26])
        s.setEggUsageForTesting(s.eggHatchThreshold)
        await s.hatchIfNeeded()
        XCTAssertNotNil(s.state.active, "the next egg hatched: a Pokémon raised to send off")
        XCTAssertTrue(s.useCostumeEgg("jan"))
        s.setEggUsageForTesting(s.eggHatchThreshold)
        await s.hatchIfNeeded()
        XCTAssertEqual(s.state.active?.plannedPathIDs, [25])
        growToTheEnd(s)
        XCTAssertEqual(s.state.dex.last?.chainOrder, [25], "a Pikachu, never a Raichu")
        XCTAssertEqual(s.state.dex.last?.finalID, 25)
    }

    /// The owner, 2026-11-18: a Pokémon's page shows its plain look, the animated sprite, until a costume is picked in
    /// its Costumes tab, for an individual caught in a costume too; a page opened again starts with nothing picked.
    func testAPageShowsACostumeOnlyOncePicked() throws {
        let costumes = CostumeCatalog.entries.filter {
            $0.speciesID == 25 && CostumeCatalog.entry(code: $0.code, speciesID: 25, form: nil) == $0
        }
        let hat = try XCTUnwrap(CostumeCatalog.byKey["HOLIDAY_2016:25"])
        XCTAssertTrue(costumes.contains(hat))
        let look = { (shown: String?, shinies: Set<String>) in
            PokemonDetailView.headerLook(shown: shown, form: nil, shiny: true, costumes: costumes, shinyCostumes: shinies)
        }
        XCTAssertNil(look(nil, [hat.key]).form, "nothing picked: the plain look")
        XCTAssertTrue(look(nil, [hat.key]).shiny)
        XCTAssertNil(look("", [hat.key]).form, "\"No costume\" picked")
        XCTAssertEqual(look(hat.key, [hat.key]).form, hat.displayForm, "picked: worn")
        XCTAssertTrue(look(hat.key, [hat.key]).shiny)
        XCTAssertFalse(look(hat.key, []).shiny, "its shiny only once collected shiny")
        XCTAssertNil(look("FALL_2022:710:small", [hat.key]).form, "another species' costume: the plain look")
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
