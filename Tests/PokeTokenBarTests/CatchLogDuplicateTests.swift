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

    func testReleasedCatchCountsAsPriorCatch() {
        let released = DexEntry(
            id: "entry-released",
            baseID: 4,
            finalID: 4,
            chainOrder: [4],
            rarity: .common,
            caughtAt: baseDate,
            releasedAt: baseDate
        )
        let laterGraduated = DexEntry(
            id: "entry-graduated",
            baseID: 4,
            finalID: 6,
            chainOrder: [4, 5, 6],
            rarity: .common,
            caughtAt: baseDate.addingTimeInterval(1800)
        )
        let store = makeStore(dex: [released, laterGraduated])

        XCTAssertFalse(store.isDuplicateCatch(released))
        XCTAssertTrue(store.isDuplicateCatch(laterGraduated))
    }

    func testUnownFormsTrackedIndividually() {
        let unownA1 = DexEntry(
            id: "unown-a1",
            baseID: UnownForm.speciesID,
            finalID: UnownForm.speciesID,
            chainOrder: [UnownForm.speciesID],
            rarity: .rare,
            caughtAt: baseDate,
            unownForm: .a
        )
        let unownB = DexEntry(
            id: "unown-b",
            baseID: UnownForm.speciesID,
            finalID: UnownForm.speciesID,
            chainOrder: [UnownForm.speciesID],
            rarity: .rare,
            caughtAt: baseDate.addingTimeInterval(100),
            unownForm: .b
        )
        let unownA2 = DexEntry(
            id: "unown-a2",
            baseID: UnownForm.speciesID,
            finalID: UnownForm.speciesID,
            chainOrder: [UnownForm.speciesID],
            rarity: .rare,
            caughtAt: baseDate.addingTimeInterval(200),
            unownForm: .a
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
}
