import XCTest
import SwiftUI
@testable import PokeTokenBar

@MainActor
final class DifficultySaveTests: XCTestCase {
    private func fixture(egg: Bool = false, difficulty: Double = 1, boost: Bool = false,
                         fraction: Double = 0.5) throws -> (CompanionStore, URL, UserDefaults) {
        var state = CompanionState()
        state.installBaselineSet = true
        state.lastDate = "2026-09-11"
        state.claimedTodayTokensByProvider = ["test": 1234]
        state.usedSinceInstall = 900_000_000
        state.spentTokens = 123_000_000
        if egg {
            state.eggUsage = Int(Double(PokemonBalance.eggHatchThreshold) * difficulty * fraction)
        } else {
            var mon = MonState(baseID: 1, pathIDs: [1], plannedPathIDs: [1, 2, 3],
                               stageIndex: 0, usedAtStage: 0, rarity: .common, totalForms: 3,
                               hasGrowthBoost: boost)
            mon.usedAtStage = Int(Double(mon.phaseThreshold) * difficulty * fraction)
            state.active = mon
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("difficulty-save-\(UUID()).json")
        try JSONEncoder().encode(state).write(to: url)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "difficulty-save-\(UUID())"))
        defaults.set(difficulty, forKey: "growthDifficulty")
        defaults.set(20.0, forKey: "shopDifficulty")
        let store = CompanionStore(provider: DifficultySaveProvider(), fileURL: url,
                                   dittoDisguiseRollingEnabled: false, defaults: defaults)
        return (store, url, defaults)
    }

    func testDraftDoesNotApplyUntilSaveAndSavesBothControls() throws {
        let (s, _, d) = try fixture()
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let before = try encoder.encode(s.state)
        var draft = DifficultyDraft(companion: s)
        draft.growth = 0.1
        draft.shop = 0.5
        XCTAssertTrue(draft.differs(from: s))
        XCTAssertEqual(s.growthDifficulty, 1)
        XCTAssertEqual(s.shopDifficulty, 2)
        XCTAssertEqual(d.double(forKey: "growthDifficulty"), 1)
        XCTAssertEqual(try encoder.encode(s.state), before)
        // Closing Settings discards this value; reopening gets the saved values.
        XCTAssertFalse(DifficultyDraft(companion: s).differs(from: s))
        draft.save(to: s)
        XCTAssertEqual(s.growthDifficulty, 0.1)
        XCTAssertEqual(s.shopDifficulty, 0.5)
        XCTAssertEqual(s.progress, 0.5, accuracy: 0.000001)
        XCTAssertFalse(draft.differs(from: s))
    }

    func testSavedDifficultyPreservesEggAndActiveProgressAndActualUsage() async throws {
        for egg in [false, true] {
            for boost in [false, true] {
                let (s, _, _) = try fixture(egg: egg, boost: boost)
                let ledger = s.state.claimedTodayTokensByProvider
                let wallet = s.availableTokens
                let profile = s.state.active?.profile
                for difficulty in [0.1, 2.0, 0.5, 1.0] {
                    s.setGrowthDifficulty(difficulty)
                    XCTAssertEqual(egg ? s.eggProgress : s.progress, 0.5, accuracy: 0.000001)
                    XCTAssertEqual(s.state.active?.stageIndex, egg ? nil : 0)
                    XCTAssertEqual(s.state.active?.profile, profile)
                    XCTAssertEqual(s.state.usedSinceInstall, 900_000_000)
                    XCTAssertEqual(s.state.spentTokens, 123_000_000)
                    XCTAssertEqual(s.availableTokens, wallet)
                    XCTAssertEqual(s.state.claimedTodayTokensByProvider, ledger)
                    XCTAssertEqual(s.state.lastDate, "2026-09-11")
                    XCTAssertTrue(s.state.dex.isEmpty)
                }
            }
        }
    }

    func testLegacyRangeMigrationPreservesFractionAndDoesNotRepeatOnRestart() throws {
        for old in [0.0001, 0.01, 20.0] {
            for egg in [false, true] {
                let (s, url, defaults) = try fixture(egg: egg, difficulty: old, boost: true)
                let expected = PokemonBalance.clampDifficulty(old)
                XCTAssertEqual(s.growthDifficulty, expected)
                XCTAssertEqual(defaults.double(forKey: "growthDifficulty"), expected)
                XCTAssertEqual(s.shopDifficulty, 2)
                XCTAssertEqual(defaults.double(forKey: "shopDifficulty"), 2)
                XCTAssertEqual(egg ? s.eggProgress : s.progress, 0.5, accuracy: 0.000001)
                let activeCredits = s.state.active?.usedAtStage
                let eggCredits = s.state.eggUsage
                let profile = s.state.active?.profile
                let again = CompanionStore(provider: DifficultySaveProvider(), fileURL: url, defaults: defaults)
                XCTAssertEqual(again.state.active?.usedAtStage, activeCredits)
                XCTAssertEqual(again.state.eggUsage, eggCredits)
                XCTAssertEqual(again.state.active?.profile, profile)
                XCTAssertEqual(again.state.usedSinceInstall, 900_000_000)
                XCTAssertTrue(again.state.dex.isEmpty)
            }
        }
    }

    func testSaveButtonAppearsBelowEditedSlidersInEveryLanguage() throws {
        let (s, _, _) = try fixture()
        var draft = DifficultyDraft(companion: s)
        draft.growth = 0.1
        draft.shop = 0.5
        for language in AppLanguage.allCases {
            s.setLanguage(language)
            let saved = NSHostingController(rootView: DifficultySettingsSection(companion: s))
            let editedView = DifficultySettingsSection(companion: s, draft: draft)
            let edited = NSHostingController(rootView: editedView)
            let size = CGSize(width: 300, height: 500)
            XCTAssertGreaterThan(edited.sizeThatFits(in: size).height,
                                 saved.sizeThatFits(in: size).height + 20)
            if language == .ko, let path = ProcessInfo.processInfo.environment["PTB_DIFFICULTY_SCREENSHOT"] {
                let host = NSHostingController(rootView: editedView.padding(16).frame(width: 332)
                    .background(Color(nsColor: .windowBackgroundColor)))
                host.view.frame = CGRect(origin: .zero, size: host.sizeThatFits(in: CGSize(width: 332, height: 500)))
                host.view.layoutSubtreeIfNeeded()
                let bitmap = try XCTUnwrap(host.view.bitmapImageRepForCachingDisplay(in: host.view.bounds))
                host.view.cacheDisplay(in: host.view.bounds, to: bitmap)
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: path))
            }
        }
    }

    func testNewRangeClampsBothControls() throws {
        let (s, _, _) = try fixture()
        s.setGrowthDifficulty(0.001)
        s.setShopDifficulty(10)
        XCTAssertEqual(s.growthDifficulty, 0.1)
        XCTAssertEqual(s.shopDifficulty, 2)
        s.setGrowthDifficulty(20)
        s.setShopDifficulty(0.01)
        XCTAssertEqual(s.growthDifficulty, 2)
        XCTAssertEqual(s.shopDifficulty, 0.1)
    }
}

private struct DifficultySaveProvider: PokeProviding {
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: 1, tree: EvoNode(speciesID: 1, children: [
            EvoNode(speciesID: 2, children: [EvoNode(speciesID: 3, children: [])])]),
                rarity: .common, names: [:])
    }
}
