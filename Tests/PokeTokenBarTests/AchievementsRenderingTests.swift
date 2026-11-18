import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

private struct AchievementsStubProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: baseSpeciesID, tree: EvoNode(speciesID: baseSpeciesID, children: []), rarity: .legendary,
                names: [baseSpeciesID: ["en": "P\(baseSpeciesID)"]])
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

/// The Achievements tab gets the same 520 pt as the other tabs. A fixed list height under the header, the claim
/// banner and the category picker made the stack taller than that frame: SwiftUI centered it, so the header slid
/// under the tab bar and the list ran under the footer.
@MainActor
final class AchievementsRenderingTests: XCTestCase {
    func testPickerAndListStayInsideTheTabFrameWithTheClaimBanner() async throws {
        let suite = "AchievementsLayout-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(suite).json")
        defer { try? FileManager.default.removeItem(at: file) }
        var state = CompanionState()
        state.language = .en
        state.installBaselineSet = true
        // Articuno, Zapdos, Moltres: the Silver Wing is ready, so the banner (the tallest header) is shown.
        state.dex = [144, 145, 146].map {
            DexEntry(baseID: $0, finalID: $0, chainOrder: [$0], rarity: .legendary,
                     caughtAt: Date(timeIntervalSince1970: 1_790_000_000))
        }
        try JSONEncoder().encode(state).write(to: file)
        let store = CompanionStore(provider: AchievementsStubProvider(), fileURL: file, defaults: defaults)
        XCTAssertGreaterThan(store.unclaimedAchievementsCount, 0)

        let host = NSHostingView(rootView: AchievementsView(store: store, nav: PopoverNavigation())
            .frame(width: PopoverMetrics.contentWidth))
        let size = NSSize(width: PopoverMetrics.contentWidth, height: 520)
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -10000, y: -10000), size: size),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(300))
        host.layoutSubtreeIfNeeded()

        XCTAssertEqual(AchievementsView.firstCategoryWithRewards(store), .legendaryArtifacts,
                       "the tab opens on the section holding the Silver Wing")
        // The list sits under the header, the claim banner and the category picker: inside the frame, the whole
        // stack fits; past its bottom, SwiftUI centered a stack taller than the tab.
        let list = try XCTUnwrap(descendants(of: host, NSScrollView.self).first)
        let frame = host.convert(list.bounds, from: list)
        XCTAssertGreaterThanOrEqual(frame.minY, -0.5, "list \(frame) leaves the tab frame \(host.bounds)")
        XCTAssertLessThanOrEqual(frame.maxY, host.bounds.maxY + 0.5, "list \(frame) leaves the tab frame \(host.bounds)")
    }

    /// Three segments with their counts used to be wider than the popover: SwiftUI centered the wider stack,
    /// so the whole tab slid off both edges. Checked in every language with the widest labels: every reward
    /// ready, so the four segments carry counts up to three digits (10, 161, 46, 10).
    func testCategoryPickerFitsTheTabWidthInEveryLanguage() async throws {
        let categories = AchievementsView.AchievementCategory.allCases
        let labelWidth = PillPicker<AchievementsView.AchievementCategory>.labelWidth(count: categories.count,
                                                                                    in: PopoverMetrics.contentWidth)
        let font = PillPicker<AchievementsView.AchievementCategory>.labelFont
        let scale = PillPicker<AchievementsView.AchievementCategory>.minimumLabelScale
        for language in AppLanguage.allCases {
            let suite = "AchievementsWidth-\(UUID())"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(suite).json")
            defer { try? FileManager.default.removeItem(at: file) }
            var state = CompanionState()
            state.language = language
            state.installBaselineSet = true
            state.dex = Self.everySpeciesTwiceMewtwo
            try JSONEncoder().encode(state).write(to: file)
            let store = CompanionStore(provider: AchievementsStubProvider(), fileURL: file, defaults: defaults)
            // Every species graduated no longer readies the Glimmering Charm: every form counts the battle forms too.
            XCTAssertEqual(categories.map { AchievementsView.readyCount($0, store) }, [10, 161, 46, 26])
            for category in categories {
                let title = AchievementsView.tabTitle(category, store)
                let width = (title as NSString).size(withAttributes: [.font: font]).width
                XCTAssertLessThanOrEqual(width * scale, labelWidth,
                                         "\(language): \"\(title)\" is \(width) pt for a \(labelWidth) pt segment")
            }
        }
    }

    /// Every species registered, Mewtwo graduated twice: every achievement is ready to claim.
    private static let everySpeciesTwiceMewtwo: [DexEntry] = (1...1025).map { id in
        // Mewtwo graduated twice (Azure Flute), and a legendary of every type for Silvally's Memories (Type: Null Egg).
        DexEntry(baseID: id, finalID: id, chainOrder: [id],
                 rarity: [150, 146, 245, 145, 251, 144, 638, 890, 383, 649, 377, 487, 491, 716].contains(id) ? .legendary : .common,
                 caughtAt: Date(timeIntervalSince1970: 1_790_000_000))
    } + [DexEntry(baseID: 150, finalID: 150, chainOrder: [150], rarity: .legendary,
                  caughtAt: Date(timeIntervalSince1970: 1_790_000_000))]
      // Every other form too, for the Glimmering Charm.
      + PokemonAssets.animatedSpeciesIDs.flatMap { id in
          PokemonForm.forms(speciesID: id).dropFirst().map {
              DexEntry(baseID: PokemonForm.lineBase(of: id), finalID: id, chainOrder: [id], rarity: .common,
                       caughtAt: Date(timeIntervalSince1970: 1_790_000_000), form: $0)
          }
      }

    private func store(registering ids: [Int]) throws -> CompanionStore {
        let suite = "AchievementsTabs-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(suite).json")
        var state = CompanionState()
        state.language = .en
        state.installBaselineSet = true
        state.dex = ids.map {
            DexEntry(baseID: $0, finalID: $0, chainOrder: [$0], rarity: .common,
                     caughtAt: Date(timeIntervalSince1970: 1_790_000_000))
        }
        try JSONEncoder().encode(state).write(to: file)
        return CompanionStore(provider: AchievementsStubProvider(), fileURL: file, defaults: defaults)
    }

    /// A segment used to read "Stones (1/10)", taken for "1 of 10 to claim". It now counts the rewards ready
    /// there, the view opens on the first section holding one, and the claim banner walks through them.
    func testTabsCountRewardsReadyAndLeadToThem() throws {
        typealias A = AchievementsView
        // Johto starters (Fire Stone) and the legendary birds (Silver Wing); no badge is ready.
        let both = try store(registering: [154, 157, 160, 144, 145, 146])
        XCTAssertEqual(A.tabTitle(.evolutionStones, both), "Stones ●1")
        XCTAssertEqual(A.tabTitle(.gymBadges, both), "Badges")
        XCTAssertEqual(A.tabTitle(.legendaryArtifacts, both), "Artifacts ●1")
        XCTAssertEqual(A.firstCategoryWithRewards(both), .evolutionStones)
        XCTAssertEqual(A.nextCategoryWithRewards(after: .evolutionStones, both), .legendaryArtifacts)
        XCTAssertEqual(A.nextCategoryWithRewards(after: .legendaryArtifacts, both), .evolutionStones, "wraps around")
        XCTAssertEqual(A.nextCategoryWithRewards(after: .gymBadges, both), .legendaryArtifacts)

        let birds = try store(registering: [144, 145, 146])
        XCTAssertEqual(A.firstCategoryWithRewards(birds), .legendaryArtifacts, "opens where the reward is")
        XCTAssertEqual(A.nextCategoryWithRewards(after: .legendaryArtifacts, birds), .legendaryArtifacts)

        let none = try store(registering: [])
        XCTAssertNil(A.firstCategoryWithRewards(none))
        XCTAssertEqual(A.AchievementCategory.allCases.map { A.tabTitle($0, none) }, ["Stones", "Badges", "Artifacts", "Forms"])
    }

    /// The Achievements tab made the popover's segmented tab bar five labels wide. With a two-digit count it was
    /// wider than the popover in German, and Russian overflowed even without one. The Dungeons tab made it six, and
    /// "Achievements" was cut in English while this test still counted five tabs: the share is counted from the bar.
    /// Each tab gets an equal share of the popover's width; its label may shrink to `minimumLabelScale`, never further,
    /// in every language. The bar itself lays out within the content width.
    func testTabBarFitsThePopoverInEveryLanguage() async throws {
        for language in AppLanguage.allCases {
            var tab = PopoverTab.home
            let picker = PopoverTabPicker(tab: Binding(get: { tab }, set: { tab = $0 }), l: L(language),
                                          unclaimedAchievements: 41)
            // 3 pt padding on each side, 2 pt between the tabs.
            let count = CGFloat(picker.items().count)
            let tabWidth = (PopoverMetrics.contentWidth - 6 - (count - 1) * 2) / count
            for item in picker.items() {
                let width = (item.title as NSString).size(withAttributes: [.font: PopoverTabPicker.labelFont]).width
                XCTAssertLessThanOrEqual(width * PopoverTabPicker.minimumLabelScale, tabWidth,
                                         "\(language): \"\(item.title)\" is \(width) pt for a \(tabWidth) pt tab")
            }
            let host = NSHostingView(rootView: picker.frame(width: PopoverMetrics.contentWidth))
            host.frame = NSRect(origin: .zero, size: NSSize(width: PopoverMetrics.contentWidth, height: 60))
            host.layoutSubtreeIfNeeded()
            XCTAssertLessThanOrEqual(host.fittingSize.width, PopoverMetrics.contentWidth + 0.5, "\(language)")
        }
    }

    /// Five tabs at most (the owner, 2026-11-02): the Bag and the achievements share the Trainer tab, which lights up
    /// for the rewards ready.
    func testTheBagAndTheAchievementsShareTheTrainerTab() {
        var tab = PopoverTab.achievements
        let picker = PopoverTabPicker(tab: Binding(get: { tab }, set: { tab = $0 }), l: L(.en), unclaimedAchievements: 3)
        XCTAssertEqual(picker.items().map(\.tab), [.home, .shop, .bag, .collection, .dungeons])
        XCTAssertLessThanOrEqual(picker.items().count, 5)
        XCTAssertEqual(picker.items()[2].title, "Trainer")
    }

    /// Home opens an achievement low in its section's list (the Excavation, after every stone): the list is scrolled
    /// to its card, which pages had done by opening its page. Opened from the tab, the list stays at its top.
    func testAnAchievementOpenedFromHomeIsScrolledTo() async throws {
        let store = try store(registering: [])
        func listOffset(_ nav: PopoverNavigation) async throws -> CGFloat {
            let host = NSHostingView(rootView: AchievementsView(store: store, nav: nav)
                .frame(width: PopoverMetrics.contentWidth))
            let size = NSSize(width: PopoverMetrics.contentWidth, height: 520)
            host.frame = NSRect(origin: .zero, size: size)
            let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -10000, y: -10000), size: size),
                                  styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            window.orderFront(nil)
            defer { window.close() }
            try await Task.sleep(for: .milliseconds(500))
            host.layoutSubtreeIfNeeded()
            let list = try XCTUnwrap(descendants(of: host, NSScrollView.self).first)
            return list.contentView.bounds.minY
        }

        let fromHome = PopoverNavigation()
        fromHome.openAchievement(.excavation)
        let scrolled = try await listOffset(fromHome)
        XCTAssertGreaterThan(scrolled, 100, "the Excavation's card scrolled into view")
        XCTAssertNil(fromHome.achievementFocus, "the focus is used once")
        let fromTab = try await listOffset(PopoverNavigation())
        XCTAssertEqual(fromTab, 0, accuracy: 0.5, "the section opens at its top")
    }

    private func descendants<T: NSView>(of view: NSView, _ type: T.Type) -> [T] {
        view.subviews.compactMap { $0 as? T } + view.subviews.flatMap { descendants(of: $0, type) }
    }
}
