import AppKit
import XCTest
@testable import PokeTokenBar

private struct PagingStubProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: baseSpeciesID, tree: EvoNode(speciesID: baseSpeciesID, children: []), rarity: .common, names: [:])
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

/// The Achievements, the costumes and the Stats page's graduates turn pages instead of scrolling a long list (#183):
/// how many a page holds, that nothing is lost or repeated, and where each opens.
@MainActor
final class TrainerStatsPagingTests: XCTestCase {
    private typealias A = AchievementsView

    private func store(registering ids: [Int]) throws -> CompanionStore {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("paging-\(UUID().uuidString).json")
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
        return CompanionStore(provider: PagingStubProvider(), fileURL: file)
    }

    // MARK: Achievements

    /// The stones four rows a page, the Excavation alone on the last; every section in its order, each card once.
    func testEachSectionIsCutIntoPagesOfItsSize() throws {
        let store = try store(registering: [])
        for category in A.AchievementCategory.allCases {
            let items = store.achievementItems(in: category.collectorGroup)
            let pages = A.pages(items, category)
            XCTAssertEqual(pages.flatMap { $0 }.filter { $0 != .excavation }, items.filter { $0 != .excavation },
                           "\(category): every card once, in the section's order")
            switch category {
            case .evolutionStones:
                XCTAssertEqual(pages.map(\.count), [4, 4, 2, 1])
                XCTAssertEqual(pages.last, [.excavation], "the digs close the stones, on a page of their own")
            case .gymBadges:
                XCTAssertEqual(pages.count, 9)
                XCTAssertTrue(pages.allSatisfy { $0.count == 2 }, "two badges a page")
            case .legendaryArtifacts, .forms:
                for page in pages {
                    XCTAssertLessThanOrEqual(page.count, 2, "\(category): two cards a page at most")
                    if page.contains(where: A.isTall) { XCTAssertEqual(page.count, 1, "\(page): a tall card alone") }
                }
                // Only a tall card or the section's last leaves a page half empty.
                for (index, page) in pages.enumerated().dropLast() where page.count == 1 {
                    XCTAssertTrue(A.isTall(page[0]) || A.isTall(pages[index + 1][0]), "\(page) shares its page")
                }
            }
        }
    }

    /// A medal listing more than four steps, an item asking for one of more than two goals: a page each. A badge's
    /// regions and the Legendary Egg's, drawn three to a row, are not steps.
    func testTallCards() {
        XCTAssertTrue(A.isTall(.costumeLotsMedal), "twelve steps")
        XCTAssertTrue(A.isTall(.battleFormsMedal), "six steps")
        XCTAssertTrue(A.isTall(.magmaStone), "four goals")
        XCTAssertFalse(A.isTall(.legendsMedal), "four steps")
        XCTAssertFalse(A.isTall(.costumeMedal), "four steps")
        XCTAssertFalse(A.isTall(.soulBadge))
        XCTAssertFalse(A.isTall(.legendaryEgg))
        XCTAssertFalse(A.isTall(.oldSeaMap))
    }

    /// Home opens an achievement on the page holding it, whichever it is.
    func testAnAchievementOpensOnItsPage() throws {
        let store = try store(registering: [])
        for category in A.AchievementCategory.allCases {
            let pages = A.pages(store.achievementItems(in: category.collectorGroup), category)
            for kind in pages.flatMap({ $0 }) {
                let page = A.openingPage(pages, focus: kind, store: store)
                XCTAssertTrue(pages[page].contains(kind), "\(kind) opens on page \(page + 1), not its own")
            }
        }
        let stones = A.pages(store.achievementItems(in: .evolutionStones), .evolutionStones)
        XCTAssertEqual(A.openingPage(stones, focus: .excavation, store: store), stones.count - 1)
        XCTAssertEqual(A.category(of: .excavation), .evolutionStones)
    }

    /// Without one to open, a section opens on its first page holding a reward ready: the digs' page when only a dig
    /// is ready, the first one when a stone is (the stones ready come first).
    func testASectionOpensOnItsFirstReward() throws {
        let rocks = FossilDig.rockSpecies.filter { !CollectorBonus.fossilLines.contains($0) && !PokemonForm.hasForms(speciesID: $0) }
        let dig = try store(registering: Array(rocks.prefix(FossilDig.rockPerDig)))
        XCTAssertTrue(A.isReady(.excavation, dig))
        let stones = A.pages(dig.achievementItems(in: .evolutionStones), .evolutionStones)
        XCTAssertFalse(stones.dropLast().joined().contains { A.isReady($0, dig) }, "no stone ready")
        XCTAssertEqual(A.openingPage(stones, focus: nil, store: dig), stones.count - 1)

        let both = try store(registering: Array(rocks.prefix(FossilDig.rockPerDig)) + [3, 6, 9])
        let withStone = A.pages(both.achievementItems(in: .evolutionStones), .evolutionStones)
        XCTAssertEqual(A.openingPage(withStone, focus: nil, store: both), 0)
        XCTAssertEqual(withStone[0].first, .leafStone)

        let none = try store(registering: [])
        XCTAssertEqual(A.openingPage(A.pages(none.achievementItems(in: .gymBadges), .gymBadges), focus: nil, store: none), 0)
    }

    // MARK: Costumes

    /// One month's lot a page, twenty Pokémon at most, from this month's lot around the year; each costume once.
    func testCostumesOneLotAPageTwentyAtMost() {
        let pages = CostumeCollectionScreen.pages(from: 11)
        let months = (0..<12).map { (11 - 1 + $0) % 12 + 1 }
        XCTAssertEqual(pages.first, .init(month: 11, index: 0, count: 1))
        XCTAssertEqual(pages.flatMap(\.entries).map(\.key), months.flatMap { CostumeCatalog.lot(month: $0).map(\.key) })
        for month in months {
            let lot = pages.filter { $0.month == month }
            let size = CostumeCatalog.lot(month: month).count
            XCTAssertEqual(lot.map(\.entries.count),
                           stride(from: 0, to: size, by: 20).map { min(20, size - $0) }, "month \(month)")
            XCTAssertEqual(lot.map(\.index), Array(0..<lot.count))
            XCTAssertTrue(lot.allSatisfy { $0.count == lot.count })
        }
        XCTAssertEqual(pages.filter { $0.month == 10 }.count, 3, "October's 49 costumes: three pages")
        // The month menu leads to the lot's first page.
        for month in months {
            XCTAssertEqual(pages[CostumeCollectionScreen.firstPage(of: month, in: pages)],
                           pages.first { $0.month == month })
        }
        XCTAssertEqual(CostumeCollectionScreen.pages(from: 1).first?.month, 1, "January's lot first in January")
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
        XCTAssertEqual(StatsScreen.graduatesPerPage, 10)
        let graduates = Array(0..<25)
        XCTAssertEqual((0..<Paging.pageCount(25, size: StatsScreen.graduatesPerPage)).map {
            Paging.slice(graduates, page: $0, size: StatsScreen.graduatesPerPage).count
        }, [10, 10, 5])
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
