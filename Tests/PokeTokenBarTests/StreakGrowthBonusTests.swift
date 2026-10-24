import XCTest
@testable import PokeTokenBar

/// The streak growth bonus: a running streak speeds up growth, never the wallet.
///
/// The traps are where the bonus lands. `update` credits usage on two paths (a new day and the same
/// day), and a rule added to one of them still compiles; both are driven here. The wallet
/// (`usedSinceInstall`) is also the shop balance, so it must stay at the real token count.
final class StreakGrowthBonusTests: XCTestCase {

    // MARK: Tiers

    func testTiersStartAtThreeDaysAndTopOutAtFourteen() {
        XCTAssertEqual(PokemonBalance.streakMultiplier(days: 0), 1.0)
        XCTAssertEqual(PokemonBalance.streakMultiplier(days: 2), 1.0)
        XCTAssertEqual(PokemonBalance.streakMultiplier(days: 3), 1.05)
        XCTAssertEqual(PokemonBalance.streakMultiplier(days: 6), 1.05)
        XCTAssertEqual(PokemonBalance.streakMultiplier(days: 7), 1.10)
        XCTAssertEqual(PokemonBalance.streakMultiplier(days: 13), 1.10)
        XCTAssertEqual(PokemonBalance.streakMultiplier(days: 14), 1.20)
        XCTAssertEqual(PokemonBalance.streakMultiplier(days: 400), 1.20)
    }

    /// The table must stay ascending in both columns: `streakMultiplier` takes the last tier reached.
    func testTierTableIsAscending() {
        let tiers = PokemonBalance.streakGrowthTiers
        XCTAssertEqual(tiers.map(\.days), tiers.map(\.days).sorted())
        XCTAssertEqual(tiers.map(\.multiplier), tiers.map(\.multiplier).sorted())
        XCTAssertTrue(tiers.allSatisfy { $0.multiplier > 1 })
    }

    func testBoostRoundsAndNeverShrinksOrOverflows() {
        XCTAssertEqual(PokemonBalance.streakBoosted(1_000_000, streakDays: 0), 1_000_000)
        XCTAssertEqual(PokemonBalance.streakBoosted(1_000_000, streakDays: 7), 1_100_000)
        XCTAssertEqual(PokemonBalance.streakBoosted(0, streakDays: 14), 0)
        XCTAssertEqual(PokemonBalance.streakBoosted(1, streakDays: 3), 1, "1 × 1.05 rounds back to 1")
        XCTAssertEqual(PokemonBalance.streakBoosted(SaveTransfer.maxTokenValue, streakDays: 14),
                       SaveTransfer.maxTokenValue)
    }

    // MARK: Crediting

    private let line = EvoLine(baseID: 1, tree: EvoNode(speciesID: 1, children: [EvoNode(speciesID: 2, children: [])]),
                               rarity: .common, names: [1: ["en": "P1"], 2: ["en": "P2"]])

    @MainActor
    private func store() -> CompanionStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("streak-\(UUID().uuidString).json")
        return CompanionStore(provider: StubProvider(value: line), clock: { Date(timeIntervalSince1970: 1_700_000_000) },
                              fileURL: url, rng: SeededRNG(seed: 7))
    }

    @MainActor
    private func observe(_ s: CompanionStore, _ today: Int, date: String = "2026-10-19", streak: Int) {
        s.update(todayTokensByProvider: ["test": today], todayDate: date, monthTotal: 0, burnTier: .idle,
                 limitWarning: false, hasUsageData: true, streakDays: streak)
    }

    @MainActor
    func testSameDayUsageBoostsTheEggButNotTheWallet() {
        let s = store()
        observe(s, 0, streak: 7)
        observe(s, 1_000_000, streak: 7)
        XCTAssertEqual(s.state.eggUsage, 1_100_000)
        XCTAssertEqual(s.state.usedSinceInstall, 1_000_000, "the wallet is the shop balance — real tokens only")
    }

    @MainActor
    func testNewDayUsageIsBoostedToo() {
        let s = store()
        observe(s, 0, date: "2026-10-18", streak: 3)
        observe(s, 2_000_000, date: "2026-10-19", streak: 3)
        XCTAssertEqual(s.state.eggUsage, 2_100_000, "the new-day path must apply the same rule")
        XCTAssertEqual(s.state.usedSinceInstall, 2_000_000)
    }

    @MainActor
    func testAHatchedPokemonGrowsFasterDuringAStreak() async throws {
        let s = store()
        await s.hatch(baseID: 1)
        observe(s, 0, streak: 14)
        let before = try XCTUnwrap(s.state.active?.usedAtStage)
        observe(s, 10_000_000, streak: 14)
        XCTAssertEqual(try XCTUnwrap(s.state.active?.usedAtStage) - before, 12_000_000)
        XCTAssertEqual(s.state.usedSinceInstall, 10_000_000)
    }

    /// Without a streak nothing changes — the default keeps every existing caller as it was.
    @MainActor
    func testNoStreakCreditsTheRealDelta() {
        let s = store()
        observe(s, 0, streak: 0)
        observe(s, 1_000_000, streak: 0)
        XCTAssertEqual(s.state.eggUsage, 1_000_000)
    }

    // MARK: Badge

    func testTheBadgeSaysWhenTheStreakSpeedsUpGrowth() {
        let l = L(.en)
        XCTAssertFalse(StreakBadge.label(UsageStreak(days: 2, includesToday: true), l: l).contains("×"),
                       "no bonus below three days")
        XCTAssertTrue(StreakBadge.label(UsageStreak(days: 7, includesToday: true), l: l).contains("×1.10"))
        for language in AppLanguage.allCases {
            XCTAssertTrue(L(language).streakGrowthBonus("×1.10").contains("×1.10"), "\(language.rawValue)")
        }
    }
}
