import AppKit
import XCTest
@testable import PokeTokenBar

private struct TabsNoProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

/// The Shop's and the Bag's tabs (#183): the Shop's products under Prof. Oak's card in Eggs, Raising and Dungeons; the
/// Bag in Raising, Dungeons, Badges and Artifacts. The Mint, used on a graduated Pokémon, leaves the dungeons' items for
/// the raising tab in both.
@MainActor
final class ShopBagTabsTests: XCTestCase {
    private func store(used: Int) -> CompanionStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("shop-tabs-\(UUID().uuidString).json")
        let json = "{\"installBaselineSet\":true,\"usedSinceInstall\":\(used),\"spentTokens\":0,"
            + "\"lastDate\":\"d\",\"dex\":[],\"collectedFinals\":[]}"
        try? json.data(using: .utf8)!.write(to: url)
        return CompanionStore(provider: TabsNoProvider(), clock: { Date(timeIntervalSince1970: 1_700_000_000) },
                              fileURL: url, rng: SeededRNG(seed: 1), difficulty: 1)
    }

    /// Exactly four tabs. The raising one holds the candies, every egg and stone, the Mint and what is kept for good;
    /// the dungeons' one every dungeon item but the Mint.
    func testTheBagSplitsTheRaisingFromTheDungeons() {
        XCTAssertEqual(BagView.Section.allCases, [.raising, .dungeons, .badges, .artifacts])
        var raising: [ItemKind] = [.rareCandy, .mint, .shinyCharm, .pokemonEgg, .uncommonEgg, .rareEgg, .legendaryEgg,
                                   .fossilEgg, .typeNullEgg, .birthdayEgg]
        raising += EventEgg.allCases.map(\.item) + ItemKind.allCases.filter { $0.stoneType != nil }
        for kind in raising {
            XCTAssertEqual(BagView.Section.of(kind), .raising, "\(kind)")
        }
        let dungeons = ItemKind.allCases.filter { $0.isDungeonItem && $0 != .mint }
        XCTAssertEqual(dungeons.count, 12)
        for kind in dungeons {
            XCTAssertEqual(BagView.Section.of(kind), .dungeons, "\(kind)")
        }
        XCTAssertTrue(ItemKind.mint.isDungeonItem, "still found in the chests and used from its Capsule-like screen")
        // Nothing but the dungeons' items in their tab.
        for kind in ItemKind.allCases where BagView.Section.of(kind) == .dungeons {
            XCTAssertTrue(kind.isDungeonItem && kind != .mint, "\(kind)")
        }
    }

    /// The Shop: its three eggs in the first tab, the Rare Candy, the Mint and the Shiny Charm in the raising one under
    /// their own titles, the two balls in the dungeons' one.
    func testTheShopTabs() {
        let s = store(used: 10_000_000_000)
        let tabs = s.shopTabs
        XCTAssertEqual(tabs.map(\.tab), [.eggs, .raising, .dungeons])
        XCTAssertEqual(tabs[0].sections.flatMap(\.entries), [.egg(nil), .egg(.uncommon), .egg(.rare)])
        XCTAssertEqual(tabs[1].sections.map(\.section), [.raising, .graduated, .keptForGood])
        XCTAssertEqual(tabs[1].sections.map(\.entries), [[.item(.rareCandy)], [.item(.mint)], [.item(.shinyCharm)]])
        XCTAssertEqual(tabs[2].sections.flatMap(\.entries), [.item(.greatBall), .item(.ultraBall)])
        XCTAssertEqual(tabs.flatMap { $0.sections.flatMap(\.entries) }.count, s.shopEntries.count, "every product in a tab")
        // Only the raising tab, of three sections, names them.
        XCTAssertEqual(CompanionStore.ShopTab.allCases.filter(\.namesItsSections), [.raising])
    }

    /// The tabs' titles fit their segments in every language: the Bag's four with two-digit counts across the tab, the
    /// Shop's three beside the scroller's lane.
    func testTheTabTitlesFitTheirSegmentsInEveryLanguage() {
        let font = PillPicker<BagView.Section>.labelFont
        let scale = PillPicker<BagView.Section>.minimumLabelScale
        let bagWidth = PillPicker<BagView.Section>.labelWidth(count: 4, in: PopoverMetrics.contentWidth)
        let shopWidth = PillPicker<CompanionStore.ShopTab>.labelWidth(
            count: 3, in: PopoverMetrics.contentWidth - PopoverMetrics.scrollerInset)
        for language in AppLanguage.allCases {
            let l = L(language)
            let bag = [l.raisingTab, l.dungeonsTab, l.collectorGroupTitle(.gymBadges),
                       l.collectorGroupTitle(.legendaryArtifacts)].map { "\($0) 88" }
            for title in bag {
                let width = (title as NSString).size(withAttributes: [.font: font]).width
                XCTAssertLessThanOrEqual(width * scale, bagWidth, "\(language): \"\(title)\" is \(width) pt")
            }
            for tab in CompanionStore.ShopTab.allCases {
                let title = l.shopTab(tab)
                let width = (title as NSString).size(withAttributes: [.font: font]).width
                XCTAssertLessThanOrEqual(width * scale, shopWidth, "\(language): \"\(title)\" is \(width) pt")
            }
            for text in [l.raisingTab, l.shopGraduatedSection] {
                XCTAssertFalse(text.isEmpty)
                XCTAssertFalse(text.contains("\u{2014}") || text.contains("\u{2013}"), "\(language): \(text)")
            }
        }
    }
}
