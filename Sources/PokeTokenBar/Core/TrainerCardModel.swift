import Foundation
import SwiftUI

/// 트레이너 카드 데이터 스냅샷
public struct TrainerCardData: Sendable {
    public let trainerName: String
    public let trainerID: String
    public let theme: AppThemeKind
    public let pokemonID: Int?
    public let pokemonName: String
    public let pokemonSubtitle: String?
    public let isShiny: Bool
    public let totalTokens: Int
    public let todayTokens: Int
    public let pokedexCount: Int
    public let pokedexTotal: Int
    public let graduatedCount: Int
    public let shinyCount: Int
    public let casinoCoins: Int

    public init(
        trainerName: String,
        trainerID: String,
        theme: AppThemeKind,
        pokemonID: Int?,
        pokemonName: String,
        pokemonSubtitle: String? = nil,
        isShiny: Bool,
        totalTokens: Int,
        todayTokens: Int = 0,
        pokedexCount: Int,
        pokedexTotal: Int = 151,
        graduatedCount: Int = 0,
        shinyCount: Int,
        casinoCoins: Int
    ) {
        self.trainerName = trainerName
        self.trainerID = trainerID
        self.theme = theme
        self.pokemonID = pokemonID
        self.pokemonName = pokemonName
        self.pokemonSubtitle = pokemonSubtitle
        self.isShiny = isShiny
        self.totalTokens = totalTokens
        self.todayTokens = todayTokens
        self.pokedexCount = pokedexCount
        self.pokedexTotal = pokedexTotal
        self.graduatedCount = graduatedCount
        self.shinyCount = shinyCount
        self.casinoCoins = casinoCoins
    }

    /// 기본 트레이너 이름 생성
    public static func defaultTrainerName() -> String {
        let full = NSFullUserName()
        if !full.isEmpty { return full }
        let user = NSUserName()
        if !user.isEmpty { return user }
        return "RED"
    }

    /// 안정적인 5자리 트레이너 ID 생성
    public static func deterministicTrainerID(from name: String) -> String {
        var hash: UInt32 = 5381
        for byte in name.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt32(byte)
        }
        return String(format: "%05d", hash % 100000)
    }
}
