import XCTest
@testable import PokeTokenBar

private struct NewsProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: baseSpeciesID, tree: EvoNode(speciesID: baseSpeciesID, children: []), rarity: .common, names: [:])
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

/// Home tells whether sending the current Pokémon off loses anything: what graduating it would add to the graduated
/// Pokédex, through every branch it can still take, in its form.
@MainActor
final class ActiveNewsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func store(active: MonState, dex: [DexEntry], costumes: Set<PikachuCostume> = []) throws -> CompanionStore {
        var st = CompanionState()
        st.installBaselineSet = true
        st.lastDate = "2026-10-27"
        st.active = active
        st.dex = dex
        st.pikachuCostumes = costumes
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("news-\(UUID().uuidString).json")
        try JSONEncoder().encode(st).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return CompanionStore(provider: NewsProvider(), clock: { self.now }, fileURL: url, rng: SeededRNG(seed: 1))
    }

    private func graduated(_ chain: [Int], form: PokemonForm? = nil, shiny: Bool = false,
                           released: Bool = false) -> DexEntry {
        DexEntry(baseID: chain[0], finalID: chain.last!, chainOrder: chain, rarity: .common, caughtAt: now,
                 isShiny: shiny, releasedAt: released ? now : nil, form: form)
    }

    private func mon(_ path: [Int], stage: Int = 0, form: PokemonForm? = nil, shiny: Bool = false) -> MonState {
        var m = MonState(baseID: path[0], pathIDs: path, stageIndex: stage, usedAtStage: 0, rarity: .common,
                         totalForms: 3, form: form)
        m.isShiny = shiny
        return m
    }

    /// [Regression] The growth badge said "Repeat" on an Eevee with seven evolutions to find: the boost comes from the
    /// line, the word says it brings nothing.
    func testARepeatBringsNothingOfWhateverItsBoost() throws {
        var eevee = mon([133])
        eevee.hasGrowthBoost = true
        XCTAssertFalse(try store(active: eevee, dex: [graduated([133, 470])]).activeIsRepeat)
        let everyEvolution = (PokemonEvolutionData.children[133] ?? []).map { graduated([133, $0]) }
        XCTAssertTrue(try store(active: eevee, dex: everyEvolution).activeIsRepeat)
        XCTAssertFalse(try store(active: mon([133]), dex: everyEvolution).activeIsRepeat, "no boost to explain")
    }

    /// One way of the line, so its names can only be promised once the way is taken.
    func testTheHintPromisesOnlyTheWayTaken() throws {
        let applin = try store(active: mon([840]), dex: [])
        XCTAssertEqual(applin.activeNewsHint, applin.l.activeNewHint(applin.activeNewsNames, certain: false))
        let dipplin = try store(active: mon([840, 1011], stage: 1), dex: [])
        XCTAssertEqual(dipplin.activeNewsHint, dipplin.l.activeNewHint(dipplin.activeNewsNames, certain: true))
    }

    /// A Pichu becomes a Pikachu, which brings a costume while one is missing: sending it off loses that costume, so
    /// it is no duplicate, on Home or in the catch log (review of #72). Once Pikachu, it brought its own.
    func testAPichuThatWillBringACostumeIsNotADuplicate() throws {
        let line = [graduated([172, 25, 26], form: PokemonForm("normal")), graduated([172, 25, 26], form: PokemonForm("alola"))]
        let pichu = try store(active: mon([172]), dex: line)
        let news = try XCTUnwrap(pichu.activeNews)
        XCTAssertEqual(news.newSpecies, [])
        XCTAssertTrue(news.costume)
        XCTAssertFalse(news.isDuplicate)
        XCTAssertEqual(pichu.activeNewsHint, pichu.l.activeCostumeHint)
        XCTAssertFalse(pichu.isDuplicateCatch(try XCTUnwrap(pichu.dexEntriesSorted.first)), "nor in the catch log")

        let everyCostume = try store(active: mon([172]), dex: line, costumes: Set(PikachuCostume.allCases))
        XCTAssertEqual(everyCostume.activeNews?.isDuplicate, true, "every costume owned")
        XCTAssertTrue(everyCostume.isDuplicateCatch(try XCTUnwrap(everyCostume.dexEntriesSorted.first)))

        let pikachu = try store(active: mon([172, 25], stage: 1), dex: line)
        XCTAssertEqual(pikachu.activeNews?.costume, false, "its costume came when it arrived")
        XCTAssertEqual(pikachu.activeNews?.isDuplicate, true)
    }

    /// [Regression] A Squirtle from a Costume Egg whose costume the collection lacks is no duplicate on Home ("New
    /// costume"), nor in the catch log, though its line is graduated.
    func testACostumeTheCollectionLacksIsNoDuplicateInTheCatchLog() throws {
        var squirtle = MonState(baseID: 7, pathIDs: [7], plannedPathIDs: [7, 8, 9], stageIndex: 0, usedAtStage: 0,
                                rarity: .common, totalForms: 3)
        squirtle.costume = "SUMMER_2018"
        let s = try store(active: squirtle, dex: [graduated([7, 8, 9])])
        XCTAssertEqual(s.activeNews?.newCostume, true)
        XCTAssertFalse(s.isDuplicateCatch(try XCTUnwrap(s.dexEntriesSorted.first)))
    }

    func testALineGraduatedWholeIsADuplicate() throws {
        let news = try XCTUnwrap(try store(active: mon([4]), dex: [graduated([4, 5, 6])]).activeNews)
        XCTAssertEqual(news.newSpecies, [])
        XCTAssertTrue(news.isDuplicate)
    }

    func testAFinalNotGraduatedIsNew() throws {
        let news = try XCTUnwrap(try store(active: mon([4, 5], stage: 1), dex: [graduated([4, 5])]).activeNews)
        XCTAssertEqual(news.newSpecies, [6])
        XCTAssertFalse(news.isDuplicate)
    }

    /// An Alolan Vulpix brings its form whatever Kanto Ninetales the Pokédex holds.
    func testItsFormCounts() throws {
        let alola = PokemonForm("alola")
        let news = try XCTUnwrap(try store(active: mon([37], form: alola), dex: [graduated([37, 38])]).activeNews)
        XCTAssertEqual(news.newSpecies, [37, 38])
        let held = try store(active: mon([37], form: alola), dex: [graduated([37, 38], form: alola)])
        XCTAssertEqual(held.activeNews?.isDuplicate, true)
    }

    func testTheFirstShinyOfItsSpeciesIsNew() throws {
        let first = try XCTUnwrap(try store(active: mon([4], shiny: true), dex: [graduated([4, 5, 6])]).activeNews)
        XCTAssertTrue(first.firstShiny)
        XCTAssertFalse(first.isDuplicate)
        let again = try store(active: mon([4], shiny: true), dex: [graduated([4, 5, 6], shiny: true)])
        XCTAssertEqual(again.activeNews?.isDuplicate, true)
    }

    /// The first shiny is counted as the Pokédex counts shinies, per species and form, through every branch: a shiny
    /// Kanto Vulpix does not make a shiny Alolan one a duplicate, nor a shiny Slowbro a shiny Slowpoke that could still
    /// become a first shiny Slowking.
    func testTheFirstShinyReadsTheFormAndEveryBranch() throws {
        let alola = PokemonForm("alola")
        let alolan = try store(active: mon([37], form: alola, shiny: true),
                               dex: [graduated([37, 38], form: alola), graduated([37, 38], shiny: true)])
        XCTAssertEqual(alolan.activeNews?.firstShiny, true, "no Alolan shiny yet")
        let slowpoke = try store(active: mon([79], shiny: true),
                                 dex: [graduated([79, 80]), graduated([79, 199]), graduated([79, 80], shiny: true)])
        XCTAssertEqual(slowpoke.activeNews?.firstShiny, true, "a shiny Slowking would be new")
        let both = try store(active: mon([79], shiny: true),
                             dex: [graduated([79, 80], shiny: true), graduated([79, 199], shiny: true)])
        XCTAssertEqual(both.activeNews?.isDuplicate, true)
    }

    /// A disguised Ditto keeps its shine hidden: the badge's hint must not say "its first shiny".
    func testADisguisedDittosShineStaysHidden() throws {
        var ditto = mon([25], shiny: true)
        ditto.dittoDisguise = 132
        let disguised = try store(active: ditto, dex: [])
        XCTAssertEqual(disguised.activeNews?.firstShiny, false)
        ditto.dittoRevealed = true
        XCTAssertEqual(try store(active: ditto, dex: []).activeNews?.firstShiny, true, "revealed, it shows")
    }

    /// A Pokémon sent off stays in the Pokédex but never graduated: it holds nothing here.
    func testReleasedPokemonHoldNothing() throws {
        let news = try XCTUnwrap(try store(active: mon([4]), dex: [graduated([4, 5, 6], released: true)]).activeNews)
        XCTAssertEqual(news.newSpecies, [4, 5, 6])
    }

    /// Every branch counts, so the route chosen at hatch is not given away: an Eevee is new while one Eeveelution is
    /// missing, whichever it will become.
    func testEveryBranchCounts() throws {
        let eeveelutions = [134, 135, 136, 196, 197, 470, 471, 700]
        let allButSylveon = eeveelutions.dropLast().map { graduated([133, $0]) }
        let news = try XCTUnwrap(try store(active: mon([133, 197]), dex: allButSylveon).activeNews)
        XCTAssertEqual(news.newSpecies, [700])
        let all = eeveelutions.map { graduated([133, $0]) }
        XCTAssertEqual(try store(active: mon([133, 197]), dex: all).activeNews?.isDuplicate, true)
    }

    func testAnEggHasNoNews() throws {
        var st = CompanionState()
        st.installBaselineSet = true
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("news-\(UUID().uuidString).json")
        try JSONEncoder().encode(st).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        XCTAssertNil(CompanionStore(provider: NewsProvider(), fileURL: url).activeNews)
    }
}
