import XCTest
@testable import PokeTokenBar

private struct MockPokeProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

@MainActor
final class CatchLogDuplicateTests: XCTestCase {
    private let baseDate = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeStore(dex: [DexEntry], active: MonState? = nil) -> CompanionStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("dex-dup-\(UUID().uuidString).json")
        var state = CompanionState()
        state.dex = dex
        state.active = active
        state.language = .en
        try? JSONEncoder().encode(state).write(to: url)
        return CompanionStore(provider: MockPokeProvider(), clock: { self.baseDate }, fileURL: url, rng: SeededRNG(seed: 42))
    }

    func testFirstCatchIsNotDuplicate() {
        let entry = DexEntry(
            id: "entry-1",
            baseID: 1,
            finalID: 3,
            chainOrder: [1, 2, 3],
            rarity: .common,
            caughtAt: baseDate
        )
        let store = makeStore(dex: [entry])

        XCTAssertFalse(store.isDuplicateCatch(entry))
        XCTAssertTrue(store.duplicateCatchEntryIDs.isEmpty)
    }

    func testSecondCatchOfSameSpeciesIsDuplicate() {
        let entry1 = DexEntry(
            id: "entry-1",
            baseID: 1,
            finalID: 3,
            chainOrder: [1, 2, 3],
            rarity: .common,
            caughtAt: baseDate
        )
        let entry2 = DexEntry(
            id: "entry-2",
            baseID: 1,
            finalID: 3,
            chainOrder: [1, 2, 3],
            rarity: .common,
            caughtAt: baseDate.addingTimeInterval(3600)
        )
        let store = makeStore(dex: [entry1, entry2])

        XCTAssertFalse(store.isDuplicateCatch(entry1), "First catch of Bulbasaur should not be a duplicate")
        XCTAssertTrue(store.isDuplicateCatch(entry2), "Second catch of Bulbasaur should be a duplicate")
        XCTAssertEqual(store.duplicateCatchEntryIDs, Set(["entry-2"]))
    }

    func testDifferentSpeciesAreNotDuplicates() {
        let bulbasaur = DexEntry(
            id: "entry-1",
            baseID: 1,
            finalID: 3,
            chainOrder: [1, 2, 3],
            rarity: .common,
            caughtAt: baseDate
        )
        let charmander = DexEntry(
            id: "entry-2",
            baseID: 4,
            finalID: 6,
            chainOrder: [4, 5, 6],
            rarity: .common,
            caughtAt: baseDate.addingTimeInterval(3600)
        )
        let store = makeStore(dex: [bulbasaur, charmander])

        XCTAssertFalse(store.isDuplicateCatch(bulbasaur))
        XCTAssertFalse(store.isDuplicateCatch(charmander))
        XCTAssertTrue(store.duplicateCatchEntryIDs.isEmpty)
    }

    func testActiveCatchDetectedAsDuplicate() {
        let graduated = DexEntry(
            id: "entry-1",
            baseID: 25,
            finalID: 26,
            chainOrder: [25, 26],
            rarity: .rare,
            caughtAt: baseDate
        )
        let active = MonState(
            baseID: 25,
            pathIDs: [25, 26],
            plannedPathIDs: [25, 26],
            stageIndex: 0,
            usedAtStage: 0,
            rarity: .rare,
            totalForms: 2
        )
        let store = makeStore(dex: [graduated], active: active)

        XCTAssertFalse(store.isDuplicateCatch(graduated), "Earlier graduated catch should not be duplicate")
        let activeEntry = store.dexEntries.first(where: { store.isActiveDexEntry($0) })
        XCTAssertNotNil(activeEntry)
        if let activeEntry {
            XCTAssertTrue(store.isDuplicateCatch(activeEntry), "Active catch of existing species should be marked duplicate")
        }
    }

    func testActiveCatchAsFirstCatchIsNotDuplicate() {
        let active = MonState(
            baseID: 25,
            pathIDs: [25, 26],
            plannedPathIDs: [25, 26],
            stageIndex: 0,
            usedAtStage: 0,
            rarity: .rare,
            totalForms: 2
        )
        let store = makeStore(dex: [], active: active)

        let activeEntry = store.dexEntries.first(where: { store.isActiveDexEntry($0) })
        XCTAssertNotNil(activeEntry)
        if let activeEntry {
            XCTAssertFalse(store.isDuplicateCatch(activeEntry), "First catch as active mon should not be duplicate")
        }
    }

    func testReleasedCatchDoesNotMarkSubsequentGraduationAsDuplicate() {
        let released = DexEntry(
            id: "entry-released",
            baseID: 25,
            finalID: 25,
            chainOrder: [25],
            rarity: .rare,
            caughtAt: baseDate,
            releasedAt: baseDate
        )
        let laterGraduated = DexEntry(
            id: "entry-graduated",
            baseID: 25,
            finalID: 26,
            chainOrder: [25, 26],
            rarity: .rare,
            caughtAt: baseDate.addingTimeInterval(1800)
        )
        let store = makeStore(dex: [released, laterGraduated])

        XCTAssertFalse(store.isDuplicateCatch(released), "First released catch should not be duplicate")
        XCTAssertFalse(store.isDuplicateCatch(laterGraduated), "Later graduated catch should not be marked duplicate by an earlier released catch")
    }

    func testEeveeBranchingEvolutionsAreNotMarkedDuplicateOnNewBranch() {
        let vaporeon = DexEntry(
            id: "entry-vaporeon",
            baseID: 133,
            finalID: 134,
            chainOrder: [133, 134],
            rarity: .common,
            caughtAt: baseDate
        )
        let jolteon = DexEntry(
            id: "entry-jolteon",
            baseID: 133,
            finalID: 135,
            chainOrder: [133, 135],
            rarity: .common,
            caughtAt: baseDate.addingTimeInterval(1800)
        )
        let secondJolteon = DexEntry(
            id: "entry-jolteon-2",
            baseID: 133,
            finalID: 135,
            chainOrder: [133, 135],
            rarity: .common,
            caughtAt: baseDate.addingTimeInterval(3600)
        )
        let store = makeStore(dex: [vaporeon, jolteon, secondJolteon])

        XCTAssertFalse(store.isDuplicateCatch(vaporeon), "First graduation of Vaporeon should not be duplicate")
        XCTAssertFalse(store.isDuplicateCatch(jolteon), "First graduation of Jolteon should not be duplicate, even if Eevee base was seen")
        XCTAssertTrue(store.isDuplicateCatch(secondJolteon), "Second graduation of Jolteon should be marked as duplicate")
        XCTAssertEqual(store.duplicateCatchEntryIDs, Set(["entry-jolteon-2"]))
    }

    func testWurmpleBranchingEvolutionsAreNotMarkedDuplicateOnNewBranch() {
        let beautifly = DexEntry(
            id: "entry-beautifly",
            baseID: 265,
            finalID: 267,
            chainOrder: [265, 266, 267],
            rarity: .common,
            caughtAt: baseDate
        )
        let dustox = DexEntry(
            id: "entry-dustox",
            baseID: 265,
            finalID: 269,
            chainOrder: [265, 268, 269],
            rarity: .common,
            caughtAt: baseDate.addingTimeInterval(1800)
        )
        let store = makeStore(dex: [beautifly, dustox])

        XCTAssertFalse(store.isDuplicateCatch(beautifly))
        XCTAssertFalse(store.isDuplicateCatch(dustox), "Cascoon -> Dustox branch is new and should not be marked duplicate")
        XCTAssertTrue(store.duplicateCatchEntryIDs.isEmpty)
    }

    func testReleasedCatchWithUncollectedEvolutionIsNotDuplicate() {
        let vaporeon = DexEntry(
            id: "entry-vaporeon",
            baseID: 133,
            finalID: 134,
            chainOrder: [133, 134],
            rarity: .common,
            caughtAt: baseDate
        )
        let releasedEevee = DexEntry(
            id: "entry-released-eevee",
            baseID: 133,
            finalID: 133,
            chainOrder: [133],
            rarity: .common,
            caughtAt: baseDate.addingTimeInterval(1800),
            releasedAt: baseDate.addingTimeInterval(1800)
        )
        let store = makeStore(dex: [vaporeon, releasedEevee])

        XCTAssertFalse(store.isDuplicateCatch(vaporeon))
        XCTAssertFalse(store.isDuplicateCatch(releasedEevee), "Released Eevee should not be duplicate while other Eeveelutions remain uncollected")
    }

    func testReleasedCatchWithAllEvolutionsCollectedIsDuplicate() {
        // Collect all Eeveelutions (134, 135, 136, 196, 197, 470, 471, 700)
        let finals = [134, 135, 136, 196, 197, 470, 471, 700]
        var entries = finals.enumerated().map { idx, finalID in
            DexEntry(
                id: "eevee-grad-\(finalID)",
                baseID: 133,
                finalID: finalID,
                chainOrder: [133, finalID],
                rarity: .common,
                caughtAt: baseDate.addingTimeInterval(Double(idx * 100))
            )
        }
        let releasedEevee = DexEntry(
            id: "entry-released-eevee-all-collected",
            baseID: 133,
            finalID: 133,
            chainOrder: [133],
            rarity: .common,
            caughtAt: baseDate.addingTimeInterval(5000),
            releasedAt: baseDate.addingTimeInterval(5000)
        )
        entries.append(releasedEevee)
        let store = makeStore(dex: entries)

        XCTAssertTrue(store.isDuplicateCatch(releasedEevee), "Released Eevee should be marked duplicate once all its evolutions have been collected")
    }

    func testReleasedLinearSpeciesWhenGraduatedIsDuplicate() {
        let graduatedRaichu = DexEntry(
            id: "raichu-grad",
            baseID: 25,
            finalID: 26,
            chainOrder: [25, 26],
            rarity: .rare,
            caughtAt: baseDate
        )
        let releasedPikachu = DexEntry(
            id: "pikachu-released",
            baseID: 25,
            finalID: 25,
            chainOrder: [25],
            rarity: .rare,
            caughtAt: baseDate.addingTimeInterval(1000),
            releasedAt: baseDate.addingTimeInterval(1000)
        )
        let store = makeStore(dex: [graduatedRaichu, releasedPikachu])

        XCTAssertFalse(store.isDuplicateCatch(graduatedRaichu))
        XCTAssertTrue(store.isDuplicateCatch(releasedPikachu), "Released Pikachu should be marked duplicate if Raichu was already graduated")
    }

    func testUnownFormsTrackedIndividually() {
        let unownA1 = DexEntry(
            id: "unown-a1",
            baseID: PokemonForm.unownSpeciesID,
            finalID: PokemonForm.unownSpeciesID,
            chainOrder: [PokemonForm.unownSpeciesID],
            rarity: .rare,
            caughtAt: baseDate,
            form: .a
        )
        let unownB = DexEntry(
            id: "unown-b",
            baseID: PokemonForm.unownSpeciesID,
            finalID: PokemonForm.unownSpeciesID,
            chainOrder: [PokemonForm.unownSpeciesID],
            rarity: .rare,
            caughtAt: baseDate.addingTimeInterval(100),
            form: .b
        )
        let unownA2 = DexEntry(
            id: "unown-a2",
            baseID: PokemonForm.unownSpeciesID,
            finalID: PokemonForm.unownSpeciesID,
            chainOrder: [PokemonForm.unownSpeciesID],
            rarity: .rare,
            caughtAt: baseDate.addingTimeInterval(200),
            form: .a
        )
        let store = makeStore(dex: [unownA1, unownB, unownA2])

        XCTAssertFalse(store.isDuplicateCatch(unownA1), "First Unown [A] should not be duplicate")
        XCTAssertFalse(store.isDuplicateCatch(unownB), "First Unown [B] should not be duplicate")
        XCTAssertTrue(store.isDuplicateCatch(unownA2), "Second Unown [A] should be duplicate")
    }

    func testLegacyEntriesWithoutCaughtAtPreserveOrder() {
        let legacy1 = DexEntry(
            id: "legacy-1",
            baseID: 7,
            finalID: 9,
            chainOrder: [7, 8, 9],
            rarity: .common,
            caughtAt: nil
        )
        let legacy2 = DexEntry(
            id: "legacy-2",
            baseID: 7,
            finalID: 9,
            chainOrder: [7, 8, 9],
            rarity: .common,
            caughtAt: nil
        )
        let store = makeStore(dex: [legacy1, legacy2])

        XCTAssertFalse(store.isDuplicateCatch(legacy1))
        XCTAssertTrue(store.isDuplicateCatch(legacy2))
    }

    func testDuplicateLocalizationInAllLanguages() {
        let languages: [AppLanguage] = [.ko, .en, .ja, .es, .fr, .pt, .de]
        let expected: [AppLanguage: String] = [
            .ko: "중복",
            .en: "Duplicate",
            .ja: "重複",
            .es: "Duplicado",
            .fr: "Doublon",
            .pt: "Duplicado",
            .de: "Duplikat",
        ]

        for lang in languages {
            let l = L(lang)
            XCTAssertEqual(l.dexDuplicate, expected[lang], "Mismatch for \(lang)")
            XCTAssertFalse(l.dexDuplicate.isEmpty)
        }
    }

    func testAlternateFormsTrackedIndividuallyAcrossEvolutions() {
        // Shellos (422) -> Gastrodon (423) with West vs East forms
        let west = DexEntry(
            id: "gastrodon-west",
            baseID: 422,
            finalID: 423,
            chainOrder: [422, 423],
            rarity: .common,
            caughtAt: baseDate,
            form: PokemonForm("west")
        )
        let east = DexEntry(
            id: "gastrodon-east",
            baseID: 422,
            finalID: 423,
            chainOrder: [422, 423],
            rarity: .common,
            caughtAt: baseDate.addingTimeInterval(3600),
            form: PokemonForm("east")
        )
        let secondWest = DexEntry(
            id: "gastrodon-west-2",
            baseID: 422,
            finalID: 423,
            chainOrder: [422, 423],
            rarity: .common,
            caughtAt: baseDate.addingTimeInterval(7200),
            form: PokemonForm("west")
        )
        let store = makeStore(dex: [west, east, secondWest])

        XCTAssertFalse(store.isDuplicateCatch(west), "First West Sea Gastrodon should not be duplicate")
        XCTAssertFalse(store.isDuplicateCatch(east), "First East Sea Gastrodon should NOT be duplicate even though species 422/423 was graduated in West form")
        XCTAssertTrue(store.isDuplicateCatch(secondWest), "Second West Sea Gastrodon should be marked duplicate")
    }

    func testRotomFormsTrackedIndividually() {
        let normal = DexEntry(
            id: "rotom-normal",
            baseID: 479,
            finalID: 479,
            chainOrder: [479],
            rarity: .rare,
            caughtAt: baseDate,
            form: PokemonForm("normal")
        )
        let heat = DexEntry(
            id: "rotom-heat",
            baseID: 479,
            finalID: 479,
            chainOrder: [479],
            rarity: .rare,
            caughtAt: baseDate.addingTimeInterval(100),
            form: PokemonForm("heat")
        )
        let secondHeat = DexEntry(
            id: "rotom-heat-2",
            baseID: 479,
            finalID: 479,
            chainOrder: [479],
            rarity: .rare,
            caughtAt: baseDate.addingTimeInterval(200),
            form: PokemonForm("heat")
        )
        let store = makeStore(dex: [normal, heat, secondHeat])

        XCTAssertFalse(store.isDuplicateCatch(normal), "Normal Rotom should not be duplicate")
        XCTAssertFalse(store.isDuplicateCatch(heat), "Heat Rotom should NOT be duplicate of Normal Rotom")
        XCTAssertTrue(store.isDuplicateCatch(secondHeat), "Second Heat Rotom should be marked duplicate")
    }

    func testReleasedAlternateFormNotDuplicateIfThatFormUncollected() {
        // Player graduated Gastrodon West
        let west = DexEntry(
            id: "gastrodon-west",
            baseID: 422,
            finalID: 423,
            chainOrder: [422, 423],
            rarity: .common,
            caughtAt: baseDate,
            form: PokemonForm("west")
        )
        // Player hatches Shellos East and releases it at stage 0
        let releasedEast = DexEntry(
            id: "shellos-east-released",
            baseID: 422,
            finalID: 422,
            chainOrder: [422],
            rarity: .common,
            caughtAt: baseDate.addingTimeInterval(100),
            releasedAt: baseDate.addingTimeInterval(100),
            form: PokemonForm("east")
        )
        let store = makeStore(dex: [west, releasedEast])

        XCTAssertFalse(store.isDuplicateCatch(west))
        XCTAssertFalse(store.isDuplicateCatch(releasedEast), "Released East Shellos must NOT be duplicate because East form was never graduated")
    }
}
