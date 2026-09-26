import XCTest
@testable import PokeTokenBar

private struct MockPokeProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

@MainActor
final class DexSearchAndFilterTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func createTestStore() -> CompanionStore {
        let entryBulbasaur = DexEntry(
            id: "entry-1",
            baseID: 1,
            finalID: 3,
            chainOrder: [1, 2, 3],
            rarity: .common,
            caughtAt: Date(timeIntervalSince1970: 1_700_000_100),
            isShiny: false,
            names: [
                1: ["ko": "이상해씨", "en": "Bulbasaur", "fr": "Bulbizarre"],
                2: ["ko": "이상해풀", "en": "Ivysaur", "fr": "Herbizarre"],
                3: ["ko": "이상해꽃", "en": "Venusaur", "fr": "Florizarre"]
            ]
        )
        let entryPikachu = DexEntry(
            id: "entry-2",
            baseID: 25,
            finalID: 26,
            chainOrder: [25, 26],
            rarity: .rare,
            caughtAt: Date(timeIntervalSince1970: 1_700_000_200),
            isShiny: true,
            names: [
                25: ["ko": "피카츄", "en": "Pikachu", "fr": "Pikachu"],
                26: ["ko": "라이츄", "en": "Raichu", "fr": "Raichu"]
            ]
        )
        let entryMewtwo = DexEntry(
            id: "entry-3",
            baseID: 150,
            finalID: 150,
            chainOrder: [150],
            rarity: .legendary,
            caughtAt: Date(timeIntervalSince1970: 1_700_000_300),
            isShiny: false,
            names: [
                150: ["ko": "뮤츠", "en": "Mewtwo", "fr": "Mewtwo"]
            ]
        )

        return makeStore(dex: [entryBulbasaur, entryPikachu, entryMewtwo])
    }

    private func makeStore(dex: [DexEntry]) -> CompanionStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("dex-search-\(UUID().uuidString).json")
        var state = CompanionState()
        state.dex = dex
        state.language = .en
        try? JSONEncoder().encode(state).write(to: url)

        return CompanionStore(provider: MockPokeProvider(), clock: { self.now }, fileURL: url, rng: SeededRNG(seed: 42))
    }

    func testDexSpeciesSearchByIDAndName() {
        let store = createTestStore()

        // Search by number (exact and with # prefix)
        let byID = store.filteredDexSpecies(query: "25")
        XCTAssertTrue(byID.contains(where: { $0.id == 25 }))
        XCTAssertFalse(byID.contains(where: { $0.id == 1 }))

        let byHashID = store.filteredDexSpecies(query: "#150")
        XCTAssertEqual(byHashID.count, 1)
        XCTAssertEqual(byHashID.first?.id, 150)

        // Partial number, with or without the # prefix
        XCTAssertEqual(store.filteredDexSpecies(query: "15").map(\.id), [150])
        XCTAssertEqual(store.filteredDexEntries(query: "#15").map(\.id), ["entry-3"])

        // Search by English name
        let byName = store.filteredDexSpecies(query: "Venusaur")
        XCTAssertEqual(byName.count, 1)
        XCTAssertEqual(byName.first?.id, 3)

        // Case-insensitive
        let byCaseInsensitive = store.filteredDexSpecies(query: "pika")
        XCTAssertTrue(byCaseInsensitive.contains(where: { $0.id == 25 }))

        // Multilingual search (French name for Bulbasaur)
        let byFrenchName = store.filteredDexSpecies(query: "Bulbizarre")
        XCTAssertTrue(byFrenchName.contains(where: { $0.id == 1 }))

        // Korean name
        let byKoreanName = store.filteredDexSpecies(query: "뮤츠")
        XCTAssertEqual(byKoreanName.count, 1)
        XCTAssertEqual(byKoreanName.first?.id, 150)

        // No match
        let noMatch = store.filteredDexSpecies(query: "MissingNo")
        XCTAssertTrue(noMatch.isEmpty)

        // Empty query matches all
        let all = store.filteredDexSpecies(query: "")
        XCTAssertEqual(all.count, store.dexSpecies.count)
    }

    /// Regression: both screens used `localizedCaseInsensitiveContains`, which keeps accents, so
    /// "flabebe" missed Flabébé although the PR promised diacritic-insensitive name search.
    func testNameSearchIgnoresCaseAndDiacriticsInPokedexAndCatchLog() {
        let flabebe = DexEntry(
            id: "entry-flabebe",
            baseID: 669,
            finalID: 669,
            chainOrder: [669],
            rarity: .common,
            caughtAt: Date(timeIntervalSince1970: 1_700_000_400),
            names: [669: ["ko": "플라베베", "en": "Flabébé", "fr": "Flabébé"]]
        )
        let pikachu = DexEntry(
            id: "entry-pikachu",
            baseID: 25,
            finalID: 25,
            chainOrder: [25],
            rarity: .rare,
            caughtAt: Date(timeIntervalSince1970: 1_700_000_500),
            names: [25: ["ko": "피카츄", "en": "Pikachu", "fr": "Pikachu"]]
        )
        let store = makeStore(dex: [flabebe, pikachu])

        for query in ["flabebe", "FLABEBE", "Flabébé", "flabébe"] {
            XCTAssertEqual(store.filteredDexSpecies(query: query).map(\.id), [669], "Pokédex: \(query)")
            XCTAssertEqual(store.filteredDexEntries(query: query).map(\.id), ["entry-flabebe"], "Catch Log: \(query)")
        }
    }

    func testDexSpeciesFilterByShinyAndRarity() {
        let store = createTestStore()

        // Shiny only
        let shinyOnly = store.filteredDexSpecies(shinyOnly: true)
        XCTAssertTrue(shinyOnly.allSatisfy { $0.isShiny })
        XCTAssertTrue(shinyOnly.contains(where: { $0.id == 25 }))
        XCTAssertFalse(shinyOnly.contains(where: { $0.id == 150 }))

        // Rarity only
        let legendaries = store.filteredDexSpecies(rarity: .legendary)
        XCTAssertEqual(legendaries.count, 1)
        XCTAssertEqual(legendaries.first?.id, 150)

        let commons = store.filteredDexSpecies(rarity: .common)
        XCTAssertEqual(commons.count, 3) // 1, 2, 3

        // Combined shiny + rarity
        let shinyRare = store.filteredDexSpecies(rarity: .rare, shinyOnly: true)
        XCTAssertEqual(shinyRare.count, 2) // 25, 26

        let shinyLegendary = store.filteredDexSpecies(rarity: .legendary, shinyOnly: true)
        XCTAssertTrue(shinyLegendary.isEmpty)
    }

    func testDexSpeciesSorting() {
        let store = createTestStore()

        // Number Asc
        let numAsc = store.filteredDexSpecies(sort: .numberAsc)
        let numAscIDs = numAsc.map(\.id)
        XCTAssertEqual(numAscIDs, numAscIDs.sorted())

        // Number Desc
        let numDesc = store.filteredDexSpecies(sort: .numberDesc)
        let numDescIDs = numDesc.map(\.id)
        XCTAssertEqual(numDescIDs, numDescIDs.sorted(by: >))

        // Name Asc
        let nameAsc = store.filteredDexSpecies(sort: .nameAsc)
        let names = nameAsc.map(\.name)
        for i in 0..<(names.count - 1) {
            let result = names[i].localizedCompare(names[i + 1])
            XCTAssertTrue(result == .orderedAscending || result == .orderedSame)
        }

        // Name Desc
        let nameDesc = store.filteredDexSpecies(sort: .nameDesc)
        let descNames = nameDesc.map(\.name)
        for i in 0..<(descNames.count - 1) {
            let result = descNames[i].localizedCompare(descNames[i + 1])
            XCTAssertTrue(result == .orderedDescending || result == .orderedSame)
        }

        // Rarity Desc
        let rarityDesc = store.filteredDexSpecies(sort: .rarityDesc)
        for i in 0..<(rarityDesc.count - 1) {
            XCTAssertGreaterThanOrEqual(rarityDesc[i].rarity.sortRank, rarityDesc[i + 1].rarity.sortRank)
        }
    }

    func testCatchLogSearchAndFilters() {
        let store = createTestStore()

        // Search by chain species ID
        let matchChain = store.filteredDexEntries(query: "25")
        XCTAssertEqual(matchChain.count, 1)
        XCTAssertEqual(matchChain.first?.baseID, 25)

        // Search by name
        let matchName = store.filteredDexEntries(query: "Raichu")
        XCTAssertEqual(matchName.count, 1)
        XCTAssertEqual(matchName.first?.baseID, 25)

        // Shiny only
        let shinies = store.filteredDexEntries(shinyOnly: true)
        XCTAssertEqual(shinies.count, 1)
        XCTAssertEqual(shinies.first?.baseID, 25)

        // Rarity
        let legendaryEntries = store.filteredDexEntries(rarity: .legendary)
        XCTAssertEqual(legendaryEntries.count, 1)
        XCTAssertEqual(legendaryEntries.first?.baseID, 150)
    }

    func testCatchLogSorting() {
        let store = createTestStore()

        // Recent first
        let recent = store.filteredDexEntries(sort: .recentFirst)
        XCTAssertEqual(recent.first?.finalID, 150) // caughtAt 300 is most recent
        XCTAssertEqual(recent.last?.finalID, 3)    // caughtAt 100 is oldest

        // Oldest first
        let oldest = store.filteredDexEntries(sort: .oldestFirst)
        XCTAssertEqual(oldest.first?.finalID, 3)
        XCTAssertEqual(oldest.last?.finalID, 150)

        // Number asc
        let numAsc = store.filteredDexEntries(sort: .numberAsc)
        XCTAssertEqual(numAsc.map(\.finalID), [3, 26, 150])

        // Number desc
        let numDesc = store.filteredDexEntries(sort: .numberDesc)
        XCTAssertEqual(numDesc.map(\.finalID), [150, 26, 3])

        // Rarity desc
        let rarityDesc = store.filteredDexEntries(sort: .rarityDesc)
        XCTAssertEqual(rarityDesc.map(\.rarity), [.legendary, .rare, .common])
    }

    func testSortOptionLabelsExistInAllLanguages() {
        let languages: [AppLanguage] = [.ko, .en, .ja, .es, .fr, .pt, .de]

        for lang in languages {
            let l = L(lang)
            for option in CompanionStore.DexSortOption.allCases {
                let label = l.label(for: option)
                XCTAssertFalse(label.isEmpty, "Missing DexSortOption label for \(option) in \(lang)")
            }
            for option in CompanionStore.CatchLogSortOption.allCases {
                let label = l.label(for: option)
                XCTAssertFalse(label.isEmpty, "Missing CatchLogSortOption label for \(option) in \(lang)")
            }
            XCTAssertFalse(l.dexSearchPlaceholder.isEmpty)
            XCTAssertFalse(l.sortTitle.isEmpty)
            XCTAssertFalse(l.filterShinyOnly.isEmpty)
            XCTAssertFalse(l.noSearchResults.isEmpty)
            XCTAssertFalse(l.clearFilters.isEmpty)
        }
    }
}
