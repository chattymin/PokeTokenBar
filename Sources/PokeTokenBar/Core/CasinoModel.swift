import Foundation
import SwiftUI

// MARK: - Casino Coins & Packages

public struct CoinPackage: Identifiable, Sendable {
    public let id: String
    public let coins: Int
    public let tokenCost: Int
    public let bonusPercent: Int

    public init(id: String, coins: Int, tokenCost: Int, bonusPercent: Int = 0) {
        self.id = id
        self.coins = coins
        self.tokenCost = tokenCost
        self.bonusPercent = bonusPercent
    }

    public static let all: [CoinPackage] = [
        CoinPackage(id: "coins_50", coins: 50, tokenCost: 35_000_000),
        CoinPackage(id: "coins_100", coins: 100, tokenCost: 65_000_000, bonusPercent: 8),
        CoinPackage(id: "coins_500", coins: 500, tokenCost: 300_000_000, bonusPercent: 15),
        CoinPackage(id: "coins_1000", coins: 1_000, tokenCost: 550_000_000, bonusPercent: 25),
        CoinPackage(id: "coins_5000", coins: 5_000, tokenCost: 2_500_000_000, bonusPercent: 40),
        CoinPackage(id: "coins_10000", coins: 10_000, tokenCost: 4_800_000_000, bonusPercent: 50),
    ]
}

// MARK: - Slot Machine (Machine à sous de Céladopole)

public enum SlotSymbol: String, CaseIterable, Sendable {
    case seven = "777"
    case bar = "BAR"
    case jigglypuff = "jigglypuff"
    case pikachu = "pikachu"
    case pokeBall = "pokeball"
    case cherry = "cherry"
    case voltorb = "voltorb"

    public enum Visual: Sendable, Equatable {
        case text(String)
        case pokemon(speciesID: Int)
        case item(name: String)
    }

    public var visual: Visual {
        switch self {
        case .seven: return .text("777")
        case .bar: return .text("BAR")
        case .jigglypuff: return .pokemon(speciesID: 39)
        case .pikachu: return .pokemon(speciesID: 25)
        case .pokeBall: return .item(name: "poke-ball")
        case .cherry: return .item(name: "cheri-berry")
        case .voltorb: return .pokemon(speciesID: 100)
        }
    }

    public var name: String {
        switch self {
        case .seven: return "Jackpot 777"
        case .bar: return "Bar Rocket"
        case .jigglypuff: return "Rondoudou"
        case .pikachu: return "Pikachu"
        case .pokeBall: return "Poké Ball"
        case .cherry: return "Cerise"
        case .voltorb: return "Voltorbe"
        }
    }

    public var lineMultiplier: Int {
        switch self {
        case .seven: return 300
        case .bar: return 100
        case .jigglypuff: return 30
        case .cherry: return 25
        case .pikachu: return 20
        case .pokeBall: return 10
        case .voltorb: return 0
        }
    }
}

public struct SlotResult: Sendable {
    public let grid: [[SlotSymbol]] // 3 rows, 3 cols
    public let winningLines: [Int]   // 0: mid, 1: top, 2: bot, 3: diag1, 4: diag2
    public let totalWin: Int
    public let isJackpot: Bool
    public let unlockedTheme: AppThemeKind?

    public init(grid: [[SlotSymbol]], winningLines: [Int], totalWin: Int, isJackpot: Bool, unlockedTheme: AppThemeKind? = nil) {
        self.grid = grid
        self.winningLines = winningLines
        self.totalWin = totalWin
        self.isJackpot = isJackpot
        self.unlockedTheme = unlockedTheme
    }
}

public enum SlotMachineEngine {
    // 3 authentic 21-stop reels with realistic distribution
    // ~28.6% Voltorb blanks (6 per reel) to create authentic near-misses and house edge
    private static let reel1: [SlotSymbol] = [
        .seven, .voltorb, .cherry, .pokeBall, .voltorb,
        .pikachu, .cherry, .voltorb, .jigglypuff, .pokeBall,
        .bar, .voltorb, .pikachu, .cherry, .pokeBall,
        .voltorb, .jigglypuff, .cherry, .voltorb, .pikachu, .pokeBall
    ]
    private static let reel2: [SlotSymbol] = [
        .bar, .voltorb, .cherry, .pikachu, .voltorb,
        .pokeBall, .cherry, .voltorb, .seven, .jigglypuff,
        .voltorb, .cherry, .pokeBall, .pikachu, .voltorb,
        .cherry, .pokeBall, .voltorb, .jigglypuff, .pikachu, .pokeBall
    ]
    private static let reel3: [SlotSymbol] = [
        .cherry, .voltorb, .seven, .pokeBall, .voltorb,
        .pikachu, .cherry, .voltorb, .bar, .jigglypuff,
        .voltorb, .cherry, .pokeBall, .voltorb, .pikachu,
        .cherry, .voltorb, .pokeBall, .jigglypuff, .pikachu, .pokeBall
    ]

    public static func spin(lines: Int = 5, multiplier: Int = 1, currentUnlocked: Set<String> = []) -> SlotResult {
        let r1 = Int.random(in: 0..<reel1.count)
        let r2 = Int.random(in: 0..<reel2.count)
        let r3 = Int.random(in: 0..<reel3.count)

        func symbol(reel: [SlotSymbol], centerIndex: Int, offset: Int) -> SlotSymbol {
            let idx = (centerIndex + offset + reel.count) % reel.count
            return reel[idx]
        }

        // rows: 0 = top, 1 = middle, 2 = bottom
        let row0: [SlotSymbol] = [symbol(reel: reel1, centerIndex: r1, offset: -1),
                                  symbol(reel: reel2, centerIndex: r2, offset: -1),
                                  symbol(reel: reel3, centerIndex: r3, offset: -1)]
        let row1: [SlotSymbol] = [symbol(reel: reel1, centerIndex: r1, offset: 0),
                                  symbol(reel: reel2, centerIndex: r2, offset: 0),
                                  symbol(reel: reel3, centerIndex: r3, offset: 0)]
        let row2: [SlotSymbol] = [symbol(reel: reel1, centerIndex: r1, offset: 1),
                                  symbol(reel: reel2, centerIndex: r2, offset: 1),
                                  symbol(reel: reel3, centerIndex: r3, offset: 1)]

        let grid = [row0, row1, row2]

        // Lines:
        // Line 0: row 1 (middle) -> enabled on lines >= 1
        // Line 1: row 0 (top)    -> enabled on lines >= 3
        // Line 2: row 2 (bottom) -> enabled on lines >= 3
        // Line 3: diag top-left to bot-right -> enabled on lines >= 5
        // Line 4: diag bot-left to top-right -> enabled on lines >= 5
        var activeLines: [(id: Int, symbols: [SlotSymbol])] = []
        if lines >= 1 { activeLines.append((0, row1)) }
        if lines >= 3 {
            activeLines.append((1, row0))
            activeLines.append((2, row2))
        }
        if lines >= 5 {
            activeLines.append((3, [row0[0], row1[1], row2[2]]))
            activeLines.append((4, [row2[0], row1[1], row0[2]]))
        }

        var winningLines: [Int] = []
        var totalWin = 0
        var jackpot = false
        var hasThemeTrigger = false

        for line in activeLines {
            let syms = line.symbols
            if syms[0] == syms[1] && syms[1] == syms[2] {
                let s = syms[0]
                if s != .voltorb {
                    let win = s.lineMultiplier * multiplier
                    totalWin += win
                    winningLines.append(line.id)
                    if s == .seven { jackpot = true }
                    if s == .jigglypuff { hasThemeTrigger = true }
                }
            } else if syms[0] == .cherry && syms[1] == .cherry {
                // 2 Cherries (Reel 1 & 2) pays 7x multiplier
                totalWin += 7 * multiplier
                winningLines.append(line.id)
            }
        }

        // ONE winning condition triggers a random theme roll based on rarity: 3 Jigglypuffs!
        var wonTheme: AppThemeKind? = nil
        if hasThemeTrigger {
            if let rolled = AppThemeKind.rollRandomTheme(excluding: currentUnlocked) {
                wonTheme = rolled
            } else {
                // All themes are already unlocked: bonus jackpot prize!
                totalWin += 250 * multiplier
            }
        }

        return SlotResult(grid: grid, winningLines: winningLines, totalWin: totalWin, isJackpot: jackpot, unlockedTheme: wonTheme)
    }

    public static func spin(bet: Int) -> SlotResult {
        let lines: Int
        switch bet {
        case 1: lines = 1
        case 2: lines = 3
        default: lines = 5
        }
        return spin(lines: lines, multiplier: 1, currentUnlocked: [])
    }
}

// MARK: - App Themes (Thèmes d'application)

public enum AppThemeKind: String, CaseIterable, Codable, Sendable {
    case classic = "classic"
    case celadonNeon = "celadon_neon"
    case teamRocket = "team_rocket"
    case indigoPlateau = "indigo_plateau"
    case masterBall = "master_ball"
    case gameBoy1989 = "gameboy_1989"

    public var itemSprite: String {
        switch self {
        case .classic: return "poke-ball"
        case .celadonNeon: return "coin-case"
        case .teamRocket: return "silph-scope"
        case .indigoPlateau: return "ss-ticket"
        case .masterBall: return "master-ball"
        case .gameBoy1989: return "town-map"
        }
    }

    public var accentColor: Color {
        switch self {
        case .classic: return .accentColor
        case .celadonNeon: return Color(red: 0.0, green: 0.85, blue: 0.85)
        case .teamRocket: return Color(red: 0.90, green: 0.15, blue: 0.20)
        case .indigoPlateau: return Color(red: 0.85, green: 0.65, blue: 0.15)
        case .masterBall: return Color(red: 0.70, green: 0.20, blue: 0.85)
        case .gameBoy1989: return Color(red: 0.35, green: 0.45, blue: 0.15)
        }
    }

    public var secondaryAccentColor: Color {
        switch self {
        case .classic: return .orange
        case .celadonNeon: return Color(red: 0.95, green: 0.30, blue: 0.85)
        case .teamRocket: return Color(red: 0.30, green: 0.30, blue: 0.35)
        case .indigoPlateau: return Color(red: 0.20, green: 0.40, blue: 0.85)
        case .masterBall: return Color(red: 0.95, green: 0.40, blue: 0.70)
        case .gameBoy1989: return Color(red: 0.20, green: 0.30, blue: 0.10)
        }
    }

    public var windowBackground: Color {
        switch self {
        case .classic:
            return .clear
        case .celadonNeon:
            return Color(red: 0.05, green: 0.08, blue: 0.18).opacity(0.25)
        case .teamRocket:
            return Color(red: 0.12, green: 0.05, blue: 0.06).opacity(0.25)
        case .indigoPlateau:
            return Color(red: 0.06, green: 0.10, blue: 0.25).opacity(0.20)
        case .masterBall:
            return Color(red: 0.18, green: 0.06, blue: 0.22).opacity(0.22)
        case .gameBoy1989:
            return Color(red: 0.55, green: 0.65, blue: 0.25).opacity(0.12)
        }
    }

    public var cardBackground: Color {
        switch self {
        case .classic: return Color.secondary.opacity(0.08)
        case .celadonNeon: return Color(red: 0.05, green: 0.12, blue: 0.22).opacity(0.40)
        case .teamRocket: return Color(red: 0.15, green: 0.15, blue: 0.18).opacity(0.50)
        case .indigoPlateau: return Color(red: 0.10, green: 0.18, blue: 0.35).opacity(0.35)
        case .masterBall: return Color(red: 0.25, green: 0.10, blue: 0.30).opacity(0.40)
        case .gameBoy1989: return Color(red: 0.60, green: 0.70, blue: 0.30).opacity(0.18)
        }
    }

    public var borderGradient: LinearGradient {
        LinearGradient(
            colors: [accentColor, secondaryAccentColor],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    public var rarityWeight: Int {
        switch self {
        case .classic: return 0 // Default unlocked
        case .celadonNeon: return 38 // Common
        case .teamRocket: return 28  // Uncommon
        case .indigoPlateau: return 18 // Rare
        case .masterBall: return 10  // Epic
        case .gameBoy1989: return 4   // Legendary (rarest)
        }
    }

    public var rarityColor: Color {
        switch self {
        case .classic: return .secondary
        case .celadonNeon: return Color(red: 0.10, green: 0.85, blue: 0.70)
        case .teamRocket: return Color(red: 0.90, green: 0.25, blue: 0.30)
        case .indigoPlateau: return Color(red: 0.40, green: 0.60, blue: 0.95)
        case .masterBall: return Color(red: 0.78, green: 0.30, blue: 0.88)
        case .gameBoy1989: return Color(red: 0.95, green: 0.75, blue: 0.15) // Legendary Gold
        }
    }

    public static func rollRandomTheme(excluding unlocked: Set<String>) -> AppThemeKind? {
        let available = AppThemeKind.allCases.filter { $0 != .classic && !unlocked.contains($0.rawValue) }
        guard !available.isEmpty else { return nil }

        let totalWeight = available.reduce(0) { $0 + $1.rarityWeight }
        guard totalWeight > 0 else { return available.randomElement() }

        var pick = Int.random(in: 0..<totalWeight)
        for theme in available {
            if pick < theme.rarityWeight {
                return theme
            }
            pick -= theme.rarityWeight
        }
        return available.last
    }
}

public enum CasinoConstants {
    public static let exclusiveSpeciesIDs: Set<Int> = [137] // Porygon (#137) is strictly exclusive to the Game Corner
    public static let starPrismCost: Int = 50_000
}

// MARK: - Prize Corner Items

public struct CasinoPrizeItem: Identifiable, Sendable {
    public let id: String
    public let coinCost: Int
    public let speciesID: Int?
    public let isStarPrism: Bool

    public init(id: String, coinCost: Int, speciesID: Int? = nil, isStarPrism: Bool = false) {
        self.id = id
        self.coinCost = coinCost
        self.speciesID = speciesID
        self.isStarPrism = isStarPrism
    }

    public static let all: [CasinoPrizeItem] = [
        CasinoPrizeItem(id: "prize_abra", coinCost: 180, speciesID: 63),
        CasinoPrizeItem(id: "prize_cleffa", coinCost: 500, speciesID: 173),
        CasinoPrizeItem(id: "prize_dratini", coinCost: 2_800, speciesID: 147),
        CasinoPrizeItem(id: "prize_scyther", coinCost: 5_500, speciesID: 123),
        CasinoPrizeItem(id: "prize_porygon", coinCost: 9_999, speciesID: 137),
        CasinoPrizeItem(id: "prize_star_prism", coinCost: 50_000, isStarPrism: true),
    ]
}
