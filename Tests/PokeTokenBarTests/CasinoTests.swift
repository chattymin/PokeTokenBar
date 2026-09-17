import XCTest
@testable import PokeTokenBar

private struct CasinoDummyProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

@MainActor
final class CasinoTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func store(used: Int = 100_000_000, spent: Int = 0, casinoCoins: Int = 0,
                       active: MonState? = nil, dex: [DexEntry] = [],
                       starPrisms: Int = 0) -> CompanionStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("casino-\(UUID().uuidString).json")
        var state = CompanionState()
        state.installBaselineSet = true
        state.usedSinceInstall = used
        state.spentTokens = spent
        state.casinoCoins = casinoCoins
        state.active = active
        state.dex = dex
        if starPrisms > 0 {
            state.inventory[ItemKind.starPrism.rawValue] = starPrisms
        }
        try? JSONEncoder().encode(state).write(to: url)
        return CompanionStore(provider: CasinoDummyProvider(), clock: { self.now }, fileURL: url, rng: SeededRNG(seed: 42))
    }

    // MARK: - Coin Packages

    func testCoinPackages() {
        XCTAssertEqual(CoinPackage.all.count, 6)
        let p50 = CoinPackage.all[0]
        XCTAssertEqual(p50.coins, 50)
        XCTAssertEqual(p50.tokenCost, 35_000_000)

        let p100 = CoinPackage.all[1]
        XCTAssertEqual(p100.coins, 100)
        XCTAssertEqual(p100.tokenCost, 65_000_000)
        XCTAssertEqual(p100.bonusPercent, 8)

        let p500 = CoinPackage.all[2]
        XCTAssertEqual(p500.coins, 500)
        XCTAssertEqual(p500.tokenCost, 300_000_000)

        let p1000 = CoinPackage.all[3]
        XCTAssertEqual(p1000.coins, 1_000)
        XCTAssertEqual(p1000.tokenCost, 550_000_000)

        let p5000 = CoinPackage.all[4]
        XCTAssertEqual(p5000.coins, 5_000)
        XCTAssertEqual(p5000.tokenCost, 2_500_000_000)

        let p10000 = CoinPackage.all[5]
        XCTAssertEqual(p10000.coins, 10_000)
        XCTAssertEqual(p10000.tokenCost, 4_800_000_000)
    }

    func testBuyCoinsDeductsTokensAndAddsCoins() {
        let s = store(used: 500_000_000, spent: 0, casinoCoins: 100)
        let pkg = CoinPackage.all[2] // 500 coins for 300M tokens
        let success = s.buyCasinoCoins(package: pkg)
        XCTAssertTrue(success)
        XCTAssertEqual(s.casinoCoins, 600)
        XCTAssertEqual(s.availableTokens, 500_000_000 - 300_000_000)
    }

    func testBuyCoinsFailsWhenInsufficientTokens() {
        let s = store(used: 10_000, spent: 0, casinoCoins: 0)
        let pkg = CoinPackage.all[0] // 35M tokens needed
        let success = s.buyCasinoCoins(package: pkg)
        XCTAssertFalse(success)
        XCTAssertEqual(s.casinoCoins, 0)
    }

    func testThemeRarityAndRandomRoll() {
        var unlocked: Set<String> = [AppThemeKind.classic.rawValue]

        // Rolling with only classic unlocked should return one of the other 5 themes
        let rolled1 = AppThemeKind.rollRandomTheme(excluding: unlocked)
        XCTAssertNotNil(rolled1)
        XCTAssertNotEqual(rolled1, .classic)

        // Add all themes to unlocked
        for theme in AppThemeKind.allCases {
            unlocked.insert(theme.rawValue)
        }
        // When all themes are unlocked, rolling returns nil
        let rolledAll = AppThemeKind.rollRandomTheme(excluding: unlocked)
        XCTAssertNil(rolledAll)
    }

    // MARK: - Slot Machine Engine

    func testSlotMachineEngineSpinOutput() {
        let res = SlotMachineEngine.spin(lines: 5, multiplier: 1)
        XCTAssertEqual(res.grid.count, 3)
        XCTAssertEqual(res.grid[0].count, 3)
        XCTAssertEqual(res.grid[1].count, 3)
        XCTAssertEqual(res.grid[2].count, 3)
    }

    func testSlotSymbols() {
        XCTAssertEqual(SlotSymbol.seven.lineMultiplier, 300)
        XCTAssertEqual(SlotSymbol.bar.lineMultiplier, 100)
        XCTAssertEqual(SlotSymbol.jigglypuff.lineMultiplier, 30)
        XCTAssertEqual(SlotSymbol.cherry.lineMultiplier, 25)
        XCTAssertEqual(SlotSymbol.pikachu.lineMultiplier, 20)
        XCTAssertEqual(SlotSymbol.pokeBall.lineMultiplier, 10)
        XCTAssertEqual(SlotSymbol.voltorb.lineMultiplier, 0)
    }

    func testSlotMachineOddsDistribution() {
        // Run 1000 spins on max lines (5 lines) to verify hit frequency is realistic (~15% - 30%)
        // and not overflowing (~70% as was the case before rebalancing)
        var wins = 0
        let totalSpins = 1000

        for _ in 0..<totalSpins {
            let res = SlotMachineEngine.spin(lines: 5, multiplier: 1)
            if res.totalWin > 0 {
                wins += 1
            }
        }

        let hitRate = Double(wins) / Double(totalSpins)
        XCTAssertGreaterThan(hitRate, 0.10, "Hit rate should be at least 10% to be engaging")
        XCTAssertLessThan(hitRate, 0.35, "Hit rate should stay under 35% so wins feel genuine")
    }

    func testSlotMachineMultiplierScaling() {
        let res1 = SlotMachineEngine.spin(lines: 5, multiplier: 1)
        XCTAssertGreaterThanOrEqual(res1.totalWin, 0)

        // Spin with 10x multiplier
        let res10 = SlotMachineEngine.spin(lines: 5, multiplier: 10)
        if res10.totalWin > 0 {
            // Wins must be multiples of 10
            XCTAssertEqual(res10.totalWin % 10, 0)
        }
    }

    // MARK: - App Themes

    func testThemesDefaultAndUnlocking() {
        let s = store(casinoCoins: 10_000)
        XCTAssertEqual(s.activeTheme, .classic)
        XCTAssertTrue(s.unlockedThemes.contains(AppThemeKind.classic.rawValue))

        // Unlock Game Boy 1989 theme via achievement
        let unlocked = s.unlockCasinoTheme(.gameBoy1989)
        XCTAssertTrue(unlocked)
        XCTAssertTrue(s.unlockedThemes.contains(AppThemeKind.gameBoy1989.rawValue))

        // Switch to Game Boy 1989
        s.setActiveTheme(.gameBoy1989)
        XCTAssertEqual(s.activeTheme, .gameBoy1989)

        // Re-unlocking should return false (already unlocked)
        let duplicate = s.unlockCasinoTheme(.gameBoy1989)
        XCTAssertFalse(duplicate)

        // Switch back to classic
        s.setActiveTheme(.classic)
        XCTAssertEqual(s.activeTheme, .classic)
    }

    // MARK: - Porygon Exclusion & Prize Corner

    func testPorygonIsCasinoExclusive() {
        XCTAssertTrue(CasinoConstants.exclusiveSpeciesIDs.contains(137))
        let porygonPrize = CasinoPrizeItem.all.first { $0.speciesID == 137 }
        XCTAssertNotNil(porygonPrize)
        XCTAssertEqual(porygonPrize?.coinCost, 9_999)
    }

    func testBuyCasinoPokemonDeductCoinsAndPreparesHatch() {
        let s = store(casinoCoins: 15_000)
        let success = s.buyCasinoPokemon(speciesID: 137, coinCost: 9_999)
        XCTAssertTrue(success)
        XCTAssertEqual(s.casinoCoins, 5_001)
        XCTAssertEqual(s.state.pendingHatchID, 137)
        XCTAssertEqual(s.state.eggUsage, PokemonBalance.eggHatchThreshold)
    }

    // MARK: - Star Prism (Prisme Étoilé)

    func testStarPrismPurchaseAndUsage() {
        let active = MonState(baseID: 4, pathIDs: [4, 5, 6],
                              stageIndex: 0, usedAtStage: 0,
                              rarity: .uncommon, totalForms: 3, isShiny: false,
                              nature: .hardy, profile: nil, hasGrowthBoost: false)
        let dexCharizard = DexEntry(baseID: 4, finalID: 6, chainOrder: [4, 5, 6],
                                    rarity: .uncommon, caughtAt: now, isShiny: false)

        let s = store(casinoCoins: 60_000, active: active, dex: [dexCharizard], starPrisms: 0)

        // Cannot use when none owned
        XCTAssertFalse(s.canUseStarPrism)

        // Buy Star Prism (50,000 coins)
        let bought = s.buyStarPrism()
        XCTAssertTrue(bought)
        XCTAssertEqual(s.casinoCoins, 10_000)
        XCTAssertEqual(s.itemCount(.starPrism), 1)
        XCTAssertTrue(s.canUseStarPrism)

        // Use Star Prism
        let used = s.useStarPrism()
        XCTAssertTrue(used)
        XCTAssertEqual(s.itemCount(.starPrism), 0)
        XCTAssertTrue(s.state.active?.isShiny == true)

        // All chain dex entries are now shiny!
        XCTAssertTrue(s.state.dex[0].isShiny)
        XCTAssertTrue(s.state.ownsShinySpecies(4))
        XCTAssertTrue(s.state.ownsShinySpecies(5))
        XCTAssertTrue(s.state.ownsShinySpecies(6))

        // Cannot use again if already shiny
        XCTAssertFalse(s.canUseStarPrism)
    }
}
