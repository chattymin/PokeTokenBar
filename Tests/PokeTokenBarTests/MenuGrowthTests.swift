import AppKit
import Observation
import XCTest
@testable import PokeTokenBar

@MainActor
final class MenuGrowthTests: XCTestCase {
    private final class ChangeFlag: @unchecked Sendable {
        var changed = false
    }

    private func observe(_ usage: UsageStore, _ companion: CompanionStore) -> ChangeFlag {
        let flag = ChangeFlag()
        withObservationTracking {
            _ = MenuBarContent.lines(store: usage, companion: companion)
        } onChange: { flag.changed = true }
        return flag
    }

    private func fixture(_ body: (UsageStore, CompanionStore) async throws -> Void) async throws {
        let name = "ptb-menu-growth-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: directory)
        }
        var state = CompanionState()
        state.language = .en
        state.inventory[ItemKind.rareCandy.rawValue] = 1
        let file = directory.appendingPathComponent("companion.json")
        try JSONEncoder().encode(state).write(to: file)
        let line = EvoLine(baseID: 1,
            tree: EvoNode(speciesID: 1, children: [EvoNode(speciesID: 2,
                children: [EvoNode(speciesID: 3, children: [])])]),
            rarity: .common, names: [1: ["en": "Bulbasaur"], 2: ["en": "Ivysaur"], 3: ["en": "Venusaur"]])
        let companion = CompanionStore(provider: StubProvider(value: line), fileURL: file,
            rng: SeededRNG(seed: 7), dittoDisguiseRollingEnabled: false, defaults: defaults)
        let usage = UsageStore(providers: [], autoRefresh: false, defaults: defaults)
        usage.showTokensInMenu = false
        usage.showCostInMenu = false
        usage.showLimitInMenu = false
        usage.showGrowthInMenu = true
        try await body(usage, companion)
    }

    func testEggEvolutionAndGraduationUseCurrentStageProgress() async throws {
        try await fixture { usage, companion in
            XCTAssertEqual(MenuBarContent.lines(store: usage, companion: companion), ["Hatch 0%"])
            companion.update(todayTokensByProvider: ["test": 0], todayDate: "d", monthTotal: 0,
                             burnTier: .idle, limitWarning: false, hasUsageData: true)
            companion.update(todayTokensByProvider: ["test": companion.eggHatchThreshold * 2 / 5],
                             todayDate: "d", monthTotal: 0, burnTier: .idle,
                             limitWarning: false, hasUsageData: true)
            XCTAssertEqual(companion.menuGrowthText, "Hatch 40%")
            await companion.hatch(baseID: 1)
            XCTAssertEqual(companion.menuGrowthText, "Growth 0%")
            companion.applyUsage(companion.threshold / 2)
            XCTAssertEqual(companion.menuGrowthText, "Growth 50%")
            companion.applyUsage(companion.tokensToNext)
            XCTAssertEqual(companion.state.active?.stageIndex, 1)
            XCTAssertEqual(companion.menuGrowthText, "Growth 0%")
            companion.applyUsage(companion.tokensToNext)
            XCTAssertTrue(companion.isFinalStage)
            companion.applyUsage(companion.threshold / 2)
            XCTAssertEqual(companion.menuGrowthText, "Growth 50%")
            companion.applyUsage(companion.tokensToNext)
            XCTAssertTrue(companion.isEgg)
            XCTAssertEqual(companion.menuGrowthText, "Hatch 0%")
        }
    }

    func testCandyDifficultyLanguageAndToggleInvalidateMenuWithoutUsageRefresh() async throws {
        try await fixture { usage, companion in
            await companion.hatch(baseID: 1)
            let candy = observe(usage, companion)
            XCTAssertEqual(companion.useRareCandy(), .progressed)
            XCTAssertTrue(candy.changed)
            XCTAssertEqual(companion.menuGrowthText, "Growth 80%")
            let difficulty = observe(usage, companion)
            companion.setGrowthDifficulty(0.5)
            XCTAssertTrue(difficulty.changed)
            XCTAssertEqual(companion.menuGrowthText, "Growth 80%", "difficulty preserves the earned fraction")
            let language = observe(usage, companion)
            companion.setLanguage(.ko)
            XCTAssertTrue(language.changed)
            XCTAssertEqual(companion.menuGrowthText, "성장 80%")
            let russian = observe(usage, companion)
            companion.setLanguage(.ru)
            XCTAssertTrue(russian.changed)
            XCTAssertEqual(MenuBarContent.lines(store: usage, companion: companion), ["Рост 80%"])
            let toggle = observe(usage, companion)
            usage.showGrowthInMenu = false
            XCTAssertTrue(toggle.changed)
            XCTAssertEqual(MenuBarContent.lines(store: usage, companion: companion), ["—"])
            let disabled = observe(usage, companion)
            companion.applyUsage(1_000_000)
            XCTAssertFalse(disabled.changed, "hidden growth must not cause extra menu redraws")
        }
    }

    func testPinnedRepresentativeDoesNotReplaceRaisedCompanionProgress() async throws {
        try await fixture { usage, companion in
            await companion.hatch(baseID: 1)
            XCTAssertTrue(companion.setRepresentativeSpeciesID(1))
            companion.applyUsage(companion.tokensToNext)
            XCTAssertEqual(companion.representativeSubject.speciesID, 1)
            XCTAssertEqual(companion.currentSpeciesID, 2)
            companion.applyUsage(companion.threshold / 2)
            XCTAssertEqual(MenuBarContent.lines(store: usage, companion: companion), ["Growth 50%"])
        }
    }

    func testAllLanguagesIncludePercentageInBothStates() {
        for language in AppLanguage.allCases {
            let l = L(language)
            XCTAssertFalse(l.pokemonGrowthPercent.isEmpty)
            XCTAssertFalse(l.pokemonGrowthPercentHint.isEmpty)
            XCTAssertTrue(l.menuGrowthProgress(42, isEgg: true).contains("42%"))
            XCTAssertTrue(l.menuGrowthProgress(42, isEgg: false).contains("42%"))
            XCTAssertNotEqual(l.menuGrowthProgress(42, isEgg: true), l.menuGrowthProgress(42, isEgg: false))
        }
    }

    func testNativeRendererPreservesGrowthAndLimitColorsAcrossLineChanges() {
        let button = NSStatusBarButton(frame: NSRect(x: 0, y: 0, width: 240, height: 22))
        AppDelegate.applyMenuText(["1.2M · Growth 42%", "Claude 40%"], to: button,
                                  colors: [.init(text: "Claude 40%", tier: .onPace)])
        let title = button.attributedTitle
        XCTAssertEqual(title.string, "1.2M · Growth 42%\nClaude 40%")
        let growth = (title.string as NSString).range(of: "Growth")
        let limit = (title.string as NSString).range(of: "Claude")
        XCTAssertNil(title.attribute(.foregroundColor, at: growth.location, effectiveRange: nil))
        XCTAssertEqual(title.attribute(.foregroundColor, at: limit.location, effectiveRange: nil) as? NSColor,
                       NSColor(PaceTier.onPace.color))
        AppDelegate.applyMenuText(["Growth 42%"], to: button, colors: [])
        XCTAssertEqual(button.title, " Growth 42%")
        AppDelegate.applyMenuText([], to: button, colors: [])
        XCTAssertEqual(button.title, "")
    }
}
