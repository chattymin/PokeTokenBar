import AppKit
import XCTest
@testable import PokeTokenBar

private struct ListsStubProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: baseSpeciesID, tree: EvoNode(speciesID: baseSpeciesID, children: []), rarity: .common, names: [:])
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

/// The Achievements, the costumes and the Stats page's graduates show every item in one list (the owner, 2026-11-18,
/// after a round of pages): what each list holds, in which order, and which card a list scrolls to.
@MainActor
final class TrainerStatsListsTests: XCTestCase {
    private typealias A = AchievementsView

    private func store(registering ids: [Int]) throws -> CompanionStore {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("lists-\(UUID().uuidString).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: file) }
        var state = CompanionState()
        state.language = .en
        state.installBaselineSet = true
        state.lastDate = "2026-11-18"
        state.dex = ids.map {
            DexEntry(baseID: $0, finalID: $0, chainOrder: [$0], rarity: .common,
                     caughtAt: Date(timeIntervalSince1970: 1_790_000_000))
        }
        try JSONEncoder().encode(state).write(to: file)
        return CompanionStore(provider: ListsStubProvider(), fileURL: file)
    }

    // MARK: Achievements

    /// Every card of a section once, in the section's order; the Excavation after every stone.
    func testEachSectionListsEveryCardOnce() throws {
        let store = try store(registering: [])
        for category in A.AchievementCategory.allCases {
            let items = store.achievementItems(in: category.collectorGroup)
            let listed = A.listed(items, category)
            XCTAssertEqual(listed.count, items.count, "\(category): every card")
            XCTAssertEqual(Set(listed), Set(items), "\(category): every card once")
            XCTAssertEqual(listed.filter { $0 != .excavation }, items.filter { $0 != .excavation },
                           "\(category): in the section's order")
        }
        let stones = A.listed(store.achievementItems(in: .evolutionStones), .evolutionStones)
        XCTAssertEqual(stones.last, .excavation, "the digs close the stones")
        XCTAssertEqual(stones.dropLast().filter { $0.stoneType == nil }, [], "nothing but stones above them")
    }

    /// Home opens an achievement in its section, on its card: the list holds it and scrolls to it, whichever it is.
    func testAnAchievementOpenedFromHomeTargetsItsCard() throws {
        let store = try store(registering: [])
        for category in A.AchievementCategory.allCases {
            let listed = A.listed(store.achievementItems(in: category.collectorGroup), category)
            for kind in listed {
                XCTAssertEqual(A.category(of: kind), category, "\(kind) opens its own section")
                XCTAssertEqual(A.scrollTarget(listed, focus: kind, store: store), kind, "\(kind)")
            }
        }
        XCTAssertEqual(A.category(of: .excavation), .evolutionStones)
    }

    /// The claim banner leads to the first card holding a reward ready: the digs' when only a dig is ready, the stone's
    /// when a stone is (the stones ready come first); none when nothing is ready.
    func testTheBannerScrollsToTheFirstReward() throws {
        let rocks = FossilDig.rockSpecies.filter { !CollectorBonus.fossilLines.contains($0) && !PokemonForm.hasForms(speciesID: $0) }
        let dig = try store(registering: Array(rocks.prefix(FossilDig.rockPerDig)))
        XCTAssertTrue(A.isReady(.excavation, dig))
        let stones = A.listed(dig.achievementItems(in: .evolutionStones), .evolutionStones)
        XCTAssertFalse(stones.dropLast().contains { A.isReady($0, dig) }, "no stone ready")
        XCTAssertEqual(A.scrollTarget(stones, focus: nil, store: dig), .excavation)

        let both = try store(registering: Array(rocks.prefix(FossilDig.rockPerDig)) + [3, 6, 9])
        let withStone = A.listed(both.achievementItems(in: .evolutionStones), .evolutionStones)
        XCTAssertEqual(withStone.first, .leafStone)
        XCTAssertEqual(A.scrollTarget(withStone, focus: nil, store: both), .leafStone)

        let none = try store(registering: [])
        XCTAssertNil(A.scrollTarget(A.listed(none.achievementItems(in: .gymBadges), .gymBadges), focus: nil, store: none))
    }

    // MARK: Costumes

    /// Every month's lot one after the other, this month's first around the year, so each costume shows once.
    func testCostumeLotsFromThisMonthAroundTheYear() {
        let months = CostumeCollectionScreen.lotMonths(from: 11)
        XCTAssertEqual(months, [11, 12, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
        XCTAssertEqual(months.flatMap { CostumeCatalog.lot(month: $0).map(\.key) }.sorted(),
                       CostumeCatalog.entries.map(\.key).sorted(), "each costume once")
        XCTAssertEqual(CostumeCollectionScreen.lotMonths(from: 1).first, 1, "January's lot first in January")
    }

    // MARK: Stats

    /// Four periods, the last everything since install; three tabs under a period, the bars' named after the period.
    func testStatsPeriodsAndTabs() {
        let fr = L(.fr)
        XCTAssertEqual(StatsScreen.Period.allCases.map { StatsScreen.periodTitle($0, fr) }, ["Semaine", "Mois", "Année", "Début"])
        XCTAssertNil(StatsScreen.Period.sinceInstall.scope)
        XCTAssertEqual(StatsScreen.Tab.allCases.map { StatsScreen.tabTitle($0, scope: .month, fr) },
                       ["Jours", "Répartition", "Diplômés"])
        XCTAssertEqual(StatsScreen.tabTitle(.days, scope: .year, fr), "Mois")
    }

    /// The Stats page's two pickers sit in its scroll view: each label fits its segment in every language.
    func testStatsPickersFitInEveryLanguage() {
        let font = PillPicker<StatsScreen.Period>.labelFont
        let scale = PillPicker<StatsScreen.Period>.minimumLabelScale
        for language in AppLanguage.allCases {
            let l = L(language)
            let rows: [[String]] = [
                StatsScreen.Period.allCases.map { StatsScreen.periodTitle($0, l) },
                StatsScreen.Tab.allCases.map { StatsScreen.tabTitle($0, scope: .month, l) },
                StatsScreen.Tab.allCases.map { StatsScreen.tabTitle($0, scope: .year, l) },
            ]
            for titles in rows {
                let room = PillPicker<StatsScreen.Period>.labelWidth(count: titles.count, in: PopoverMetrics.scrollContentWidth)
                for title in titles {
                    let width = (title as NSString).size(withAttributes: [.font: font]).width
                    XCTAssertLessThanOrEqual(width * scale, room, "\(language): \"\(title)\" is \(width) pt for \(room) pt")
                }
            }
        }
    }
}
