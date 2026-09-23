import XCTest
@testable import PokeTokenBar

@MainActor
final class StreakMultiplierTests: XCTestCase {
    private static func defaultLine() -> EvoLine {
        var names: [Int: [String: String]] = [:]
        for id in [1, 2, 3] { names[id] = ["en": "P\(id)", "ko": "포켓몬\(id)"] }
        return EvoLine(baseID: 1,
                       tree: EvoNode(speciesID: 1, children: [EvoNode(speciesID: 2, children: [EvoNode(speciesID: 3, children: [])])]),
                       rarity: .common, names: names)
    }

    @MainActor
    private func makeStore(state: CompanionState = CompanionState(),
                           growthDifficulty: Double = 1.0,
                           line: EvoLine? = nil) -> CompanionStore {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("ptb-streak-\(UUID().uuidString).json")
        let data = try! JSONEncoder().encode(state)
        try! data.write(to: file)
        let defs = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        defs.set(growthDifficulty, forKey: "growthDifficulty")
        let provider = StubDiffProvider(value: line ?? Self.defaultLine())
        return CompanionStore(provider: provider,
                              clock: { Date(timeIntervalSince1970: 1_700_000_000) },
                              fileURL: file, rng: SeededDiffRNG(seed: 7),
                              dittoDisguiseRollingEnabled: false,
                              defaults: defs)
    }

    // MARK: - Multiplier Tiers

    func testStreakMultiplierTiers() {
        XCTAssertEqual(PokemonBalance.streakMultiplier(for: 0), 1.0)
        XCTAssertEqual(PokemonBalance.streakMultiplier(for: 1), 1.0)
        XCTAssertEqual(PokemonBalance.streakMultiplier(for: 2), 1.0)
        XCTAssertEqual(PokemonBalance.streakMultiplier(for: 3), 1.10)
        XCTAssertEqual(PokemonBalance.streakMultiplier(for: 6), 1.10)
        XCTAssertEqual(PokemonBalance.streakMultiplier(for: 7), 1.25)
        XCTAssertEqual(PokemonBalance.streakMultiplier(for: 13), 1.25)
        XCTAssertEqual(PokemonBalance.streakMultiplier(for: 14), 1.35)
        XCTAssertEqual(PokemonBalance.streakMultiplier(for: 29), 1.35)
        XCTAssertEqual(PokemonBalance.streakMultiplier(for: 30), 1.50)
        XCTAssertEqual(PokemonBalance.streakMultiplier(for: 100), 1.50)
    }

    // MARK: - Day Difference

    func testDayDifferenceCalculation() {
        XCTAssertEqual(LocalUsageReader.dayDifference(from: "2026-09-22", to: "2026-09-22"), 0)
        XCTAssertEqual(LocalUsageReader.dayDifference(from: "2026-09-22", to: "2026-09-23"), 1)
        XCTAssertEqual(LocalUsageReader.dayDifference(from: "2026-09-21", to: "2026-09-23"), 2)
        XCTAssertEqual(LocalUsageReader.dayDifference(from: "2026-09-23", to: "2026-09-22"), -1)
        // Month boundary
        XCTAssertEqual(LocalUsageReader.dayDifference(from: "2026-09-30", to: "2026-10-01"), 1)
        // Year boundary
        XCTAssertEqual(LocalUsageReader.dayDifference(from: "2026-12-31", to: "2027-01-01"), 1)
        // Leap year
        XCTAssertEqual(LocalUsageReader.dayDifference(from: "2028-02-28", to: "2028-02-29"), 1)
        XCTAssertEqual(LocalUsageReader.dayDifference(from: "2028-02-29", to: "2028-03-01"), 1)
        // Invalid date
        XCTAssertNil(LocalUsageReader.dayDifference(from: "invalid", to: "2026-09-23"))
    }

    // MARK: - State Transitions & Morning Tolerance

    func testStreakStateTransitionsAndMorningTolerance() {
        var streak = StreakState()
        XCTAssertEqual(streak.effectiveDays(todayDate: "2026-09-21"), 0)

        // Day 1: User reaches 10M tokens on 2026-09-21
        streak.recordActiveDay("2026-09-21")
        XCTAssertEqual(streak.days, 1)
        XCTAssertEqual(streak.lastDay, "2026-09-21")
        XCTAssertEqual(streak.effectiveDays(todayDate: "2026-09-21"), 1)

        // Multiple recordings on the same day do not increase streak
        streak.recordActiveDay("2026-09-21")
        XCTAssertEqual(streak.days, 1)

        // Day 2 morning (2026-09-22): User has not recorded tokens yet today
        // Morning tolerance: yesterday was active, so streak of 1 day is still effective today!
        XCTAssertEqual(streak.effectiveDays(todayDate: "2026-09-22"), 1)

        // Day 2 afternoon: User reaches 10M tokens today
        streak.recordActiveDay("2026-09-22")
        XCTAssertEqual(streak.days, 2)
        XCTAssertEqual(streak.lastDay, "2026-09-22")
        XCTAssertEqual(streak.effectiveDays(todayDate: "2026-09-22"), 2)

        // Day 3: Consecutive day recorded -> reaches 3 days (1.10x boost unlocked)
        streak.recordActiveDay("2026-09-23")
        XCTAssertEqual(streak.days, 3)
        XCTAssertEqual(streak.lastDay, "2026-09-23")
        XCTAssertEqual(streak.effectiveDays(todayDate: "2026-09-23"), 3)

        // Missed day: User misses 2026-09-24. On 2026-09-25 morning:
        // Difference from 2026-09-23 to 2026-09-25 is 2 (> 1) -> streak is broken!
        XCTAssertEqual(streak.effectiveDays(todayDate: "2026-09-25"), 0)

        // User reaches 10M tokens on 2026-09-25 -> resets to day 1
        streak.recordActiveDay("2026-09-25")
        XCTAssertEqual(streak.days, 1)
        XCTAssertEqual(streak.lastDay, "2026-09-25")
        XCTAssertEqual(streak.effectiveDays(todayDate: "2026-09-25"), 1)
    }

    // MARK: - Multiplier Scales Thresholds

    func testMultiplierReducesEggHatchAndStageThresholds() {
        let today = LocalUsageReader.todayKey()
        var state = CompanionState()
        state.streak = StreakState(days: 7, lastDay: today)
        state.active = MonState(baseID: 1, pathIDs: [1, 2, 3], stageIndex: 0,
                                usedAtStage: 0, rarity: .common, totalForms: 3)
        let store = makeStore(state: state)

        // 7-day streak has 1.25x multiplier
        XCTAssertEqual(store.streakDays, 7)
        XCTAssertEqual(store.streakMultiplier, 1.25)

        // Base common stage 0 threshold is 125M tokens.
        // With 1.25x boost: 125_000_000 / 1.25 = 100_000_000
        XCTAssertEqual(store.threshold, 100_000_000)

        // Base egg hatch threshold is 5M tokens.
        // With 1.25x boost: 5_000_000 / 1.25 = 4_000_000
        var eggState = CompanionState()
        eggState.streak = StreakState(days: 7, lastDay: today)
        eggState.active = nil
        let eggStore = makeStore(state: eggState)
        XCTAssertEqual(eggStore.eggTokensToHatch, 4_000_000)
    }

    // MARK: - Multiplicative Composition with Repeat Boost and Difficulty

    func testMultiplierComposesWithRepeatBoostAndDifficulty() {
        let today = LocalUsageReader.todayKey()
        var state = CompanionState()
        state.streak = StreakState(days: 7, lastDay: today)
        // Mon with repeat boost (hasGrowthBoost = true -> 2x)
        state.active = MonState(baseID: 1, pathIDs: [1, 2, 3], stageIndex: 0,
                                usedAtStage: 0, rarity: .common, totalForms: 3,
                                hasGrowthBoost: true)

        // Base phaseThreshold with repeat boost (2x) is 62_500_000
        // Combined with 7-day streak (1.25x): 62_500_000 / 1.25 = 50_000_000 (total 2.5x growth!)
        let store = makeStore(state: state, growthDifficulty: 1.0)
        XCTAssertEqual(store.threshold, 50_000_000)

        // If growth difficulty is 1.5: 50_000_000 * 1.5 = 75_000_000
        store.setGrowthDifficulty(1.5)
        XCTAssertEqual(store.threshold, 75_000_000)
    }

    // MARK: - Streak Accelerates Evolution

    func testStreakAcceleratesEvolution() async {
        let store = makeStore()
        await store.hatch(baseID: 1)

        let fmt = LocalUsageReader.localDayFormatter()
        let today = Date()
        let cal = Calendar(identifier: .gregorian)
        var series: [DailyUsage] = []
        for i in (0..<7).reversed() {
            let d = cal.date(byAdding: .day, value: -i, to: today)!
            let dateStr = fmt.string(from: d)
            series.append(DailyUsage(date: dateStr, inputTokens: 0, outputTokens: 0,
                                     cacheCreationTokens: 0, cacheReadTokens: 0,
                                     totalTokens: 10_000_000, totalCost: 0, costCoverage: .empty))
        }
        let todayStr = fmt.string(from: today)
        store.bootstrapStreakIfNeeded(from: series, todayDate: todayStr)

        XCTAssertEqual(store.streakDays, 7)
        XCTAssertEqual(store.streakMultiplier, 1.25)
        XCTAssertEqual(store.threshold, 100_000_000)
        XCTAssertEqual(store.state.active?.stageIndex, 0)

        // Apply 99M tokens -> still in stage 0
        store.applyUsage(99_000_000)
        XCTAssertEqual(store.state.active?.stageIndex, 0)
        XCTAssertEqual(store.state.active?.usedAtStage, 99_000_000)

        // Apply 2M delta -> 99M + 2M = 101M >= 100M threshold -> triggers evolution to stage 1!
        store.applyUsage(2_000_000)

        XCTAssertEqual(store.state.active?.stageIndex, 1)
        XCTAssertEqual(store.state.active?.currentID, 2)
        // Excess 1M carries over to stage 1
        XCTAssertEqual(store.state.active?.usedAtStage, 1_000_000)
    }

    // MARK: - Bootstrap From Month Daily Totals

    func testBootstrapStreakFromMonthDailyTotals() {
        let series = [
            DailyUsage(date: "2026-09-20", inputTokens: 0, outputTokens: 0, cacheCreationTokens: 0,
                       cacheReadTokens: 0, totalTokens: 15_000_000, totalCost: 0, costCoverage: .empty),
            DailyUsage(date: "2026-09-21", inputTokens: 0, outputTokens: 0, cacheCreationTokens: 0,
                       cacheReadTokens: 0, totalTokens: 20_000_000, totalCost: 0, costCoverage: .empty),
            DailyUsage(date: "2026-09-22", inputTokens: 0, outputTokens: 0, cacheCreationTokens: 0,
                       cacheReadTokens: 0, totalTokens: 12_000_000, totalCost: 0, costCoverage: .empty),
            DailyUsage(date: "2026-09-23", inputTokens: 0, outputTokens: 0, cacheCreationTokens: 0,
                       cacheReadTokens: 0, totalTokens: 1_000_000, totalCost: 0, costCoverage: .empty)
        ]

        let store = makeStore()
        XCTAssertEqual(store.state.streak.days, 0)

        // Bootstrap on 2026-09-23 (where today is 1M < 10M, but yesterday 2026-09-22 completed 3 days)
        store.bootstrapStreakIfNeeded(from: series, todayDate: "2026-09-23")

        XCTAssertEqual(store.state.streak.days, 3)
        XCTAssertEqual(store.state.streak.lastDay, "2026-09-22")
        // Check effective days on 2026-09-23
        XCTAssertEqual(store.state.streak.effectiveDays(todayDate: "2026-09-23"), 3)
    }

    // MARK: - Save Sanitization

    func testSaveSanitizationClampsStreakDays() {
        var state = CompanionState()
        state.streak.days = 99999
        let sanitized = SaveTransfer.sanitized(state)
        XCTAssertEqual(sanitized.streak.days, 3650)

        var negative = CompanionState()
        negative.streak.days = -10
        let sanitizedNegative = SaveTransfer.sanitized(negative)
        XCTAssertEqual(sanitizedNegative.streak.days, 0)
    }

    // MARK: - Extreme Difficulty Scaling (Defect Log Requirement)

    func testMultiplierAtExtremeDifficulties() {
        let today = LocalUsageReader.todayKey()
        var state = CompanionState()
        state.streak = StreakState(days: 7, lastDay: today) // 1.25x
        state.active = MonState(baseID: 1, pathIDs: [1, 2, 3], stageIndex: 0,
                                usedAtStage: 0, rarity: .common, totalForms: 3)

        // At lowest difficulty (0.1): base 125M * 0.1 = 12.5M.
        // With 1.25x streak: 12.5M / 1.25 = 10M.
        // Verifies difficulty clamping does not swallow streak multiplier.
        let lowStore = makeStore(state: state, growthDifficulty: 0.1)
        XCTAssertEqual(lowStore.threshold, 10_000_000)

        // At highest difficulty (2.0): base 125M * 2.0 = 250M.
        // With 1.25x streak: 250M / 1.25 = 200M.
        let highStore = makeStore(state: state, growthDifficulty: 2.0)
        XCTAssertEqual(highStore.threshold, 200_000_000)
    }

    // MARK: - Timezone Travel

    func testTimezoneTravelPreservesStreak() {
        var streak = StreakState(days: 3, lastDay: "2026-09-23")

        // User travels west to a timezone where local date is still yesterday (2026-09-22)
        XCTAssertEqual(streak.effectiveDays(todayDate: "2026-09-22"), 3)

        // Coding in that earlier timezone must not reset or regress streak
        streak.recordActiveDay("2026-09-22")
        XCTAssertEqual(streak.days, 3)
        XCTAssertEqual(streak.lastDay, "2026-09-23")

        // The following day (2026-09-24), streak is preserved and advances
        XCTAssertEqual(streak.effectiveDays(todayDate: "2026-09-24"), 3)
        streak.recordActiveDay("2026-09-24")
        XCTAssertEqual(streak.days, 4)
        XCTAssertEqual(streak.lastDay, "2026-09-24")
    }

    // MARK: - Multi-Provider Usage Accumulation in Update

    func testMultiProviderUsageReachesStreakThresholdInUpdate() {
        let store = makeStore()
        XCTAssertEqual(store.state.streak.days, 0)

        // Multi-provider tokens: Claude 6M + Codex 4.5M = 10.5M >= 10M threshold
        store.update(
            todayTokensByProvider: ["claude": 6_000_000, "codex": 4_500_000],
            todayDate: "2026-09-23",
            monthTotal: 10_500_000,
            burnTier: .normal,
            limitWarning: false,
            hasUsageData: true
        )

        XCTAssertEqual(store.state.streak.days, 1)
        XCTAssertEqual(store.state.streak.lastDay, "2026-09-23")
        XCTAssertEqual(store.streakDays, 1)
    }

    // MARK: - Daily Streak Threshold Setting & Clamping

    func testDailyStreakThresholdSettingAndClamping() {
        let store = makeStore()
        XCTAssertEqual(store.dailyStreakThreshold, 10_000_000)

        store.setDailyStreakThreshold(5_000_000)
        XCTAssertEqual(store.dailyStreakThreshold, 5_000_000)

        store.setDailyStreakThreshold(-50)
        XCTAssertEqual(store.dailyStreakThreshold, 1)

        store.setDailyStreakThreshold(2_000_000_000)
        XCTAssertEqual(store.dailyStreakThreshold, 1_000_000_000)
    }

    // MARK: - Multiplier Formatting

    func testMultiplierFormattingInLocalization() {
        let l = L(.en)
        let badge3 = l.streakBadge(days: 3, multiplier: 1.10)
        XCTAssertEqual(badge3, "🔥 3d (1.10×)")

        let badge7 = l.streakBadge(days: 7, multiplier: 1.25)
        XCTAssertEqual(badge7, "🔥 7d (1.25×)")

        let badge30 = l.streakBadge(days: 30, multiplier: 1.50)
        XCTAssertEqual(badge30, "🔥 30d (1.50×)")

        let tooltip3 = l.streakTooltip(days: 3, multiplier: 1.10)
        XCTAssertTrue(tooltip3.contains("1.10× growth boost active"))
    }
}

// MARK: - Test Stubs

private struct StubDiffProvider: PokeProviding {
    let value: EvoLine
    func line(baseSpeciesID: Int) async throws -> EvoLine { value }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [BaseSpecies(id: value.baseID, captureRate: 255)] }
}

private struct SeededDiffRNG: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
