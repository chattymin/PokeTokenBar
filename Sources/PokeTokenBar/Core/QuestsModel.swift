import Foundation

public enum QuestIcon: String, Codable, Sendable {
    case pokeBall = "poke-ball"
    case greatBall = "great-ball"
    case ultraBall = "ultra-ball"
    case masterBall = "master-ball"
    case rareCandy = "rare-candy"
    case mint = "mental-herb"
    case shinyCharm = "shiny-charm"
    case fireStone = "fire-stone"
    case redChain = "red-chain"
    case thunderStone = "thunder-stone"
    case leafStone = "leaf-stone"
    case waterStone = "water-stone"
    case sunStone = "sun-stone"
    case moonStone = "moon-stone"
    case egg = "egg"
    case azureFlute = "azure-flute"
    case silverWing = "silver-wing"
    case oldSeaMap = "old-sea-map"
    case clearBell = "clear-bell"
    case rainbowWing = "rainbow-wing"
    case magmaStone = "magma-stone"
    case soulDew = "soul-dew"
    case jadeOrb = "jade-orb"
    case gracidea = "gracidea"
    case griseousOrb = "griseous-orb"
    case libertyPass = "liberty-pass"
    case revealGlass = "reveal-glass"
    case dnaSplicers = "dna-splicers"
    case badgeBoulder = "badge-1"
    case badgeCascade = "badge-2"
    case badgeThunder = "badge-3"
    case badgeRainbow = "badge-4"
    case badgeSoul = "badge-5"
    case badgeMarsh = "badge-6"
    case badgeVolcano = "badge-7"
    case badgeEarth = "badge-8"
    case badgeZephyr = "badge-9"
    case badgeHive = "badge-10"
    case badgePlain = "badge-11"
    case badgeFog = "badge-12"
    case badgeStorm = "badge-13"
    case badgeMineral = "badge-14"
    case badgeGlacier = "badge-15"
    case badgeRising = "badge-16"
    case badgeDark = "badge-59"
    case badgeFairy = "badge-48"
    case legendCharm = "legend-charm"
    case iceStone = "ice-stone"
    case duskStone = "dusk-stone"
    case dawnStone = "dawn-stone"
    case shinyStone = "shiny-stone"

    public var fallbackEmoji: String {
        switch self {
        case .pokeBall: return "🔴"
        case .greatBall: return "🔵"
        case .ultraBall: return "🟡"
        case .masterBall: return "🟣"
        case .rareCandy: return "🍬"
        case .mint: return "🍃"
        case .shinyCharm: return "✨"
        case .fireStone: return "🔥"
        case .redChain: return "⛓️"
        case .thunderStone: return "⚡"
        case .leafStone: return "🌿"
        case .sunStone: return "☀️"
        case .moonStone: return "🌙"
        case .egg: return "🥚"
        case .azureFlute: return "🪈"
        case .silverWing: return "🪶"
        case .oldSeaMap: return "🗺️"
        case .clearBell: return "🔔"
        case .rainbowWing: return "🌈"
        case .magmaStone: return "🌋"
        case .soulDew: return "💧"
        case .jadeOrb: return "🟢"
        case .gracidea: return "🌸"
        case .griseousOrb: return "🔮"
        case .libertyPass: return "🎟️"
        case .revealGlass: return "🪞"
        case .dnaSplicers: return "🧬"
        case .waterStone, .legendCharm, .iceStone, .duskStone, .dawnStone, .shinyStone: return "★"
        case .badgeBoulder, .badgeCascade, .badgeThunder, .badgeRainbow,
             .badgeSoul, .badgeMarsh, .badgeVolcano, .badgeEarth,
             .badgeZephyr, .badgeHive, .badgePlain, .badgeFog,
             .badgeStorm, .badgeMineral, .badgeGlacier, .badgeRising,
             .badgeDark, .badgeFairy:
            return "★"
        }
    }
}

public struct QuestReward: Codable, Sendable, Equatable {
    public let candies: Int
    public let tokens: Int
    public let item: String?

    public init(candies: Int = 0, tokens: Int = 0, item: String? = nil) {
        self.candies = candies
        self.tokens = tokens
        self.item = item
    }
}

public enum DailyQuestType: String, Codable, Sendable, CaseIterable {
    case warmup = "daily_warmup"
    case focus = "daily_focus"
    case power = "daily_power"
    case deepWork = "daily_deep_work"
    case marathon = "daily_marathon"
    case titan = "daily_titan"
    case streak = "daily_streak"
    case incubator = "daily_incubator"

    public var target: Int {
        switch self {
        case .warmup: return 10_000_000
        case .focus: return 50_000_000
        case .power: return 100_000_000
        case .deepWork: return 150_000_000
        case .marathon: return 300_000_000
        case .titan: return 500_000_000
        case .streak: return 1
        case .incubator: return 10_000_000
        }
    }

    public var icon: QuestIcon {
        switch self {
        case .warmup: return .pokeBall
        case .focus: return .greatBall
        case .power: return .ultraBall
        case .deepWork: return .rareCandy
        case .marathon: return .ultraBall
        case .titan: return .masterBall
        case .streak: return .redChain
        case .incubator: return .egg
        }
    }

    public var reward: QuestReward {
        switch self {
        case .warmup: return QuestReward(tokens: 250_000)
        case .focus: return QuestReward(tokens: 1_000_000)
        case .power: return QuestReward(tokens: 2_000_000)
        case .deepWork: return QuestReward(candies: 1, tokens: 4_000_000)
        case .marathon: return QuestReward(candies: 1, tokens: 8_000_000)
        case .titan: return QuestReward(candies: 2, tokens: 15_000_000)
        case .streak: return QuestReward(tokens: 500_000)
        case .incubator: return QuestReward(tokens: 500_000)
        }
    }
}

public struct DailyQuestItem: Identifiable, Sendable {
    public let type: DailyQuestType
    public var id: String { type.rawValue }
    public let progress: Int
    public let target: Int
    public let isCompleted: Bool
    public let isClaimed: Bool

    public init(type: DailyQuestType, progress: Int, isClaimed: Bool) {
        self.type = type
        self.target = type.target
        self.progress = min(progress, type.target)
        self.isCompleted = progress >= type.target
        self.isClaimed = isClaimed
    }
}

public enum WeeklyQuestType: String, Codable, Sendable, CaseIterable {
    case activeDays3 = "weekly_active_3"
    case activeDays5 = "weekly_active_5"
    case tokens100M = "weekly_tokens_100m"
    case tokens300M = "weekly_tokens_300m"
    case tokens1B = "weekly_tokens_1b"
    case tokens2B = "weekly_tokens_2b"
    case tokens3_5B = "weekly_tokens_3_5b"

    public var target: Int {
        switch self {
        case .activeDays3: return 3
        case .activeDays5: return 5
        case .tokens100M: return 100_000_000
        case .tokens300M: return 300_000_000
        case .tokens1B: return 1_000_000_000
        case .tokens2B: return 2_000_000_000
        case .tokens3_5B: return 3_500_000_000
        }
    }

    public var icon: QuestIcon {
        switch self {
        case .activeDays3: return .leafStone
        case .activeDays5: return .sunStone
        case .tokens100M: return .greatBall
        case .tokens300M: return .ultraBall
        case .tokens1B: return .rareCandy
        case .tokens2B: return .moonStone
        case .tokens3_5B: return .masterBall
        }
    }

    public var reward: QuestReward {
        switch self {
        case .activeDays3: return QuestReward(tokens: 1_000_000)
        case .activeDays5: return QuestReward(candies: 1, tokens: 3_000_000)
        case .tokens100M: return QuestReward(tokens: 2_500_000)
        case .tokens300M: return QuestReward(tokens: 6_000_000)
        case .tokens1B: return QuestReward(candies: 1, tokens: 12_000_000)
        case .tokens2B: return QuestReward(candies: 2, tokens: 20_000_000)
        case .tokens3_5B: return QuestReward(candies: 3, tokens: 35_000_000)
        }
    }
}

public struct WeeklyQuestItem: Identifiable, Sendable {
    public let type: WeeklyQuestType
    public var id: String { type.rawValue }
    public let progress: Int
    public let target: Int
    public let isCompleted: Bool
    public let isClaimed: Bool

    public init(type: WeeklyQuestType, progress: Int, isClaimed: Bool) {
        self.type = type
        self.target = type.target
        self.progress = min(progress, type.target)
        self.isCompleted = progress >= type.target
        self.isClaimed = isClaimed
    }
}

public enum AchievementCategory: String, Codable, Sendable, CaseIterable, Identifiable {
    case adventure = "adventure"
    case starters = "starters"
    case legendaries = "legendaries"
    case gymBadges = "gym_badges"
    case productivity = "productivity"

    public var id: String { rawValue }

    public var icon: QuestIcon {
        switch self {
        case .adventure: return .pokeBall
        case .starters: return .egg
        case .legendaries: return .masterBall
        case .gymBadges: return .badgeRainbow
        case .productivity: return .redChain
        }
    }
}

public enum AchievementType: String, Codable, Sendable, CaseIterable {
    case firstHatch = "ach_first_hatch"
    case firstEvolve = "ach_first_evolve"
    case firstGraduate = "ach_first_graduate"
    case squad5 = "ach_squad_5"
    case dex15 = "ach_dex_15"
    case dex30 = "ach_dex_30"
    case shinyHunter = "ach_shiny_hunter"
    case streak3 = "ach_streak_3"
    case streak7 = "ach_streak_7"
    case streak14 = "ach_streak_14"
    case streak30 = "ach_streak_30"
    case tokens100M = "ach_tokens_100m"
    case tokens1B = "ach_tokens_1b"
    case tokens5B = "ach_tokens_5b"
    case tokens10B = "ach_tokens_10b"
    case candyUser = "ach_candy_user"
    case shopSpender = "ach_shop_spender"
    case limitBreaker = "ach_limit_breaker"
    case duplicateLegendary = "ach_duplicate_legendary"
    case legendaryBirds = "ach_legendary_birds"
    case kantoDuo = "ach_kanto_duo"
    case legendaryBeasts = "ach_legendary_beasts"
    case towerDuo = "ach_tower_duo"
    case legendaryTitans = "ach_legendary_titans"
    case eonDuo = "ach_eon_duo"
    case weatherTrio = "ach_weather_trio"
    case lakeGuardians = "ach_lake_guardians"
    case creationTrio = "ach_creation_trio"
    case swordsOfJustice = "ach_swords_of_justice"
    case forcesOfNature = "ach_forces_of_nature"
    case taoDuo = "ach_tao_duo"
    case badgeBoulder = "ach_badge_boulder"
    case badgeCascade = "ach_badge_cascade"
    case badgeThunder = "ach_badge_thunder"
    case badgeRainbow = "ach_badge_rainbow"
    case badgeSoul = "ach_badge_soul"
    case badgeMarsh = "ach_badge_marsh"
    case badgeVolcano = "ach_badge_volcano"
    case badgeEarth = "ach_badge_earth"
    case badgeZephyr = "ach_badge_zephyr"
    case badgeHive = "ach_badge_hive"
    case badgePlain = "ach_badge_plain"
    case badgeFog = "ach_badge_fog"
    case badgeStorm = "ach_badge_storm"
    case badgeMineral = "ach_badge_mineral"
    case badgeGlacier = "ach_badge_glacier"
    case badgeRising = "ach_badge_rising"
    case badgeDark = "ach_badge_dark"
    case badgeFairy = "ach_badge_fairy"
    case kantoStarters = "ach_kanto_starters"
    case johtoStarters = "ach_johto_starters"
    case hoennStarters = "ach_hoenn_starters"
    case sinnohStarters = "ach_sinnoh_starters"
    case unovaStarters = "ach_unova_starters"
    case starterMaster = "ach_starter_master"
    case eeveeKantoTrio = "ach_eevee_kanto_trio"
    case eeveeJohtoDuo = "ach_eevee_johto_duo"
    case eeveeSinnohDuo = "ach_eevee_sinnoh_duo"
    case eeveeMaster = "ach_eevee_master"
    case firstFossil = "ach_first_fossil"
    case fossilCollector = "ach_fossil_collector"
    case fossilMaster = "ach_fossil_master"
    case elementalStones = "ach_elemental_stones"
    case allStonesUsed = "ach_all_stones_used"
    case bagCollector = "ach_bag_collector"
    case shinyTrio = "ach_shiny_trio"
    case shinySquad = "ach_shiny_squad"
    case shinyLegendOrStarter = "ach_shiny_legend_starter"
    case streak60 = "ach_streak_60"
    case streak100 = "ach_streak_100"
    case tokens25B = "ach_tokens_25b"
    case dailyMarathon = "ach_daily_marathon"
    case nightOwl = "ach_night_owl"
    case earlyBird = "ach_early_bird"

    public var badgeType: PokemonType? {
        switch self {
        case .badgeBoulder: return .rock
        case .badgeCascade: return .water
        case .badgeThunder: return .electric
        case .badgeRainbow: return .grass
        case .badgeSoul:    return .poison
        case .badgeMarsh:   return .psychic
        case .badgeVolcano: return .fire
        case .badgeEarth:   return .ground
        case .badgeZephyr:  return .flying
        case .badgeHive:    return .bug
        case .badgePlain:   return .normal
        case .badgeFog:     return .ghost
        case .badgeStorm:   return .fighting
        case .badgeMineral: return .steel
        case .badgeGlacier: return .ice
        case .badgeRising:  return .dragon
        case .badgeDark:    return .dark
        case .badgeFairy:   return .fairy
        default:            return nil
        }
    }

    public var category: AchievementCategory {
        if badgeType != nil { return .gymBadges }
        switch self {
        case .kantoStarters, .johtoStarters, .hoennStarters, .sinnohStarters, .unovaStarters, .starterMaster:
            return .starters
        case .duplicateLegendary, .legendaryBirds, .kantoDuo, .legendaryBeasts, .towerDuo,
             .legendaryTitans, .eonDuo, .weatherTrio, .lakeGuardians, .creationTrio,
             .swordsOfJustice, .forcesOfNature, .taoDuo:
            return .legendaries
        case .streak3, .streak7, .streak14, .streak30,
             .tokens100M, .tokens1B, .tokens5B, .tokens10B, .limitBreaker,
             .streak60, .streak100, .tokens25B, .dailyMarathon, .nightOwl, .earlyBird:
            return .productivity
        case .firstHatch, .firstEvolve, .firstGraduate, .squad5,
             .dex15, .dex30, .shinyHunter, .candyUser, .shopSpender,
             .eeveeKantoTrio, .eeveeJohtoDuo, .eeveeSinnohDuo, .eeveeMaster,
             .firstFossil, .fossilCollector, .fossilMaster,
             .elementalStones, .allStonesUsed, .bagCollector,
             .shinyTrio, .shinySquad, .shinyLegendOrStarter:
            return .adventure
        default:
            return .adventure
        }
    }

    public var icon: QuestIcon {
        if let badgeType { return badgeType.badgeIcon }
        switch self {
        case .firstHatch: return .egg
        case .firstEvolve: return .thunderStone
        case .firstGraduate: return .masterBall
        case .squad5: return .greatBall
        case .dex15: return .ultraBall
        case .dex30: return .masterBall
        case .shinyHunter: return .shinyCharm
        case .streak3: return .redChain
        case .streak7: return .greatBall
        case .streak14: return .ultraBall
        case .streak30: return .masterBall
        case .tokens100M: return .pokeBall
        case .tokens1B: return .greatBall
        case .tokens5B: return .ultraBall
        case .tokens10B: return .masterBall
        case .candyUser: return .rareCandy
        case .shopSpender: return .mint
        case .limitBreaker: return .masterBall
        case .duplicateLegendary: return .azureFlute
        case .legendaryBirds: return .silverWing
        case .kantoDuo: return .oldSeaMap
        case .legendaryBeasts: return .clearBell
        case .towerDuo: return .rainbowWing
        case .legendaryTitans: return .magmaStone
        case .eonDuo: return .soulDew
        case .weatherTrio: return .jadeOrb
        case .lakeGuardians: return .gracidea
        case .creationTrio: return .griseousOrb
        case .swordsOfJustice: return .libertyPass
        case .forcesOfNature: return .revealGlass
        case .taoDuo: return .dnaSplicers
        case .kantoStarters: return .leafStone
        case .johtoStarters: return .fireStone
        case .hoennStarters: return .waterStone
        case .sinnohStarters: return .sunStone
        case .unovaStarters: return .moonStone
        case .starterMaster: return .masterBall
        case .eeveeKantoTrio: return .waterStone
        case .eeveeJohtoDuo: return .duskStone
        case .eeveeSinnohDuo: return .iceStone
        case .eeveeMaster: return .leafStone
        case .firstFossil: return .ultraBall
        case .fossilCollector: return .magmaStone
        case .fossilMaster: return .masterBall
        case .elementalStones: return .thunderStone
        case .allStonesUsed: return .shinyStone
        case .bagCollector: return .greatBall
        case .shinyTrio: return .shinyCharm
        case .shinySquad: return .ultraBall
        case .shinyLegendOrStarter: return .masterBall
        case .streak60: return .ultraBall
        case .streak100: return .legendCharm
        case .tokens25B: return .masterBall
        case .dailyMarathon: return .rareCandy
        case .nightOwl: return .duskStone
        case .earlyBird: return .sunStone
        default: return .masterBall
        }
    }

    public var target: Int {
        if let badgeType { return PokemonTypeData.species(for: badgeType).count }
        switch self {
        case .firstHatch: return 1
        case .firstEvolve: return 1
        case .firstGraduate: return 1
        case .squad5: return 5
        case .dex15: return 15
        case .dex30: return 30
        case .shinyHunter: return 1
        case .streak3: return 3
        case .streak7: return 7
        case .streak14: return 14
        case .streak30: return 30
        case .tokens100M: return 100_000_000
        case .tokens1B: return 1_000_000_000
        case .tokens5B: return 5_000_000_000
        case .tokens10B: return 10_000_000_000
        case .candyUser: return 5
        case .shopSpender: return 1_000_000_000
        case .limitBreaker: return 1
        case .duplicateLegendary: return 2
        case .legendaryBirds: return 3
        case .kantoDuo: return 2
        case .legendaryBeasts: return 3
        case .towerDuo: return 2
        case .legendaryTitans: return 3
        case .eonDuo: return 2
        case .weatherTrio: return 3
        case .lakeGuardians: return 3
        case .creationTrio: return 3
        case .swordsOfJustice: return 3
        case .forcesOfNature: return 3
        case .taoDuo: return 2
        case .kantoStarters, .johtoStarters, .hoennStarters, .sinnohStarters, .unovaStarters: return 3
        case .starterMaster: return 15
        case .eeveeKantoTrio: return 3
        case .eeveeJohtoDuo: return 2
        case .eeveeSinnohDuo: return 2
        case .eeveeMaster: return 7
        case .firstFossil: return 1
        case .fossilCollector: return 4
        case .fossilMaster: return 9
        case .elementalStones: return 3
        case .allStonesUsed: return 10
        case .bagCollector: return 8
        case .shinyTrio: return 3
        case .shinySquad: return 6
        case .shinyLegendOrStarter: return 1
        case .streak60: return 60
        case .streak100: return 100
        case .tokens25B: return 25_000_000_000
        case .dailyMarathon: return 100_000_000
        case .nightOwl: return 1
        case .earlyBird: return 1
        default: return 1
        }
    }

    public var reward: QuestReward {
        if let badgeType { return QuestReward(item: badgeType.badgeItem.rawValue) }
        switch self {
        case .firstHatch: return QuestReward(candies: 1)
        case .firstEvolve: return QuestReward(item: ItemKind.thunderStone.rawValue)
        case .firstGraduate: return QuestReward(candies: 1, tokens: 10_000_000)
        case .squad5: return QuestReward(candies: 2, tokens: 25_000_000)
        case .dex15: return QuestReward(candies: 3, tokens: 50_000_000)
        case .dex30: return QuestReward(candies: 5, tokens: 100_000_000)
        case .shinyHunter: return QuestReward(candies: 3, tokens: 50_000_000)
        case .streak3: return QuestReward(tokens: 2_000_000)
        case .streak7: return QuestReward(candies: 1, tokens: 5_000_000)
        case .streak14: return QuestReward(candies: 2, tokens: 15_000_000)
        case .streak30: return QuestReward(candies: 3, tokens: 30_000_000)
        case .tokens100M: return QuestReward(tokens: 5_000_000)
        case .tokens1B: return QuestReward(candies: 1, tokens: 25_000_000)
        case .tokens5B: return QuestReward(candies: 2, tokens: 50_000_000)
        case .tokens10B: return QuestReward(candies: 3, tokens: 100_000_000)
        case .candyUser: return QuestReward(tokens: 10_000_000)
        case .shopSpender: return QuestReward(tokens: 25_000_000)
        case .limitBreaker: return QuestReward(candies: 1, tokens: 5_000_000)
        case .duplicateLegendary: return QuestReward(item: ItemKind.legendCharm.rawValue)
        case .legendaryBirds: return QuestReward(item: ItemKind.silverWing.rawValue)
        case .kantoDuo: return QuestReward(item: ItemKind.oldSeaMap.rawValue)
        case .legendaryBeasts: return QuestReward(item: ItemKind.clearBell.rawValue)
        case .towerDuo: return QuestReward(item: ItemKind.rainbowWing.rawValue)
        case .legendaryTitans: return QuestReward(item: ItemKind.magmaStone.rawValue)
        case .eonDuo: return QuestReward(item: ItemKind.soulDew.rawValue)
        case .weatherTrio: return QuestReward(item: ItemKind.jadeOrb.rawValue)
        case .lakeGuardians: return QuestReward(item: ItemKind.gracidea.rawValue)
        case .creationTrio: return QuestReward(item: ItemKind.griseousOrb.rawValue)
        case .swordsOfJustice: return QuestReward(item: ItemKind.libertyPass.rawValue)
        case .forcesOfNature: return QuestReward(item: ItemKind.revealGlass.rawValue)
        case .taoDuo: return QuestReward(item: ItemKind.dnaSplicers.rawValue)
        case .kantoStarters:
            return QuestReward(item: ItemKind.leafStone.rawValue)
        case .johtoStarters:
            return QuestReward(item: ItemKind.fireStone.rawValue)
        case .hoennStarters:
            return QuestReward(item: ItemKind.waterStone.rawValue)
        case .sinnohStarters:
            return QuestReward(item: ItemKind.sunStone.rawValue)
        case .unovaStarters:
            return QuestReward(item: ItemKind.moonStone.rawValue)
        case .starterMaster:
            return QuestReward(candies: 5, tokens: 500_000_000)
        case .eeveeKantoTrio:
            return QuestReward(item: ItemKind.waterStone.rawValue)
        case .eeveeJohtoDuo:
            return QuestReward(item: ItemKind.duskStone.rawValue)
        case .eeveeSinnohDuo:
            return QuestReward(item: ItemKind.iceStone.rawValue)
        case .eeveeMaster:
            return QuestReward(candies: 3, tokens: 100_000_000)
        case .firstFossil:
            return QuestReward(candies: 1, tokens: 15_000_000)
        case .fossilCollector:
            return QuestReward(item: ItemKind.magmaStone.rawValue)
        case .fossilMaster:
            return QuestReward(candies: 5, tokens: 200_000_000)
        case .elementalStones:
            return QuestReward(item: ItemKind.fireStone.rawValue)
        case .allStonesUsed:
            return QuestReward(candies: 4, tokens: 150_000_000)
        case .bagCollector:
            return QuestReward(tokens: 25_000_000)
        case .shinyTrio:
            return QuestReward(item: ItemKind.shinyCharm.rawValue)
        case .shinySquad:
            return QuestReward(candies: 3, tokens: 150_000_000)
        case .shinyLegendOrStarter:
            return QuestReward(candies: 5, tokens: 300_000_000)
        case .streak60:
            return QuestReward(candies: 3, tokens: 100_000_000)
        case .streak100:
            return QuestReward(item: ItemKind.legendCharm.rawValue)
        case .tokens25B:
            return QuestReward(candies: 5, tokens: 250_000_000)
        case .dailyMarathon:
            return QuestReward(candies: 2, tokens: 50_000_000)
        case .nightOwl:
            return QuestReward(item: ItemKind.moonStone.rawValue)
        case .earlyBird:
            return QuestReward(item: ItemKind.sunStone.rawValue)
        default: return QuestReward()
        }
    }
}

public struct AchievementItem: Identifiable, Sendable {
    public let type: AchievementType
    public var id: String { type.rawValue }
    public let progress: Int
    public let target: Int
    public let isCompleted: Bool
    public let isClaimed: Bool
    public var category: AchievementCategory { type.category }

    public init(type: AchievementType, progress: Int, isClaimed: Bool) {
        self.type = type
        self.target = type.target
        self.progress = min(progress, type.target)
        self.isCompleted = progress >= type.target
        self.isClaimed = isClaimed
    }
}

public struct QuestState: Codable, Sendable, Equatable {
    public var dailyQuestDate: String = ""
    public var weeklyQuestKey: String = ""
    public var claimedDailyQuestIDs: Set<String> = []
    public var claimedWeeklyQuestIDs: Set<String> = []
    public var claimedAchievementIDs: Set<String> = []
    public var currentStreak: Int = 0
    public var bestStreak: Int = 0
    public var lastActiveDate: String = ""
    public var weeklyActiveDays: Set<String> = []
    public var weeklyTokens: Int = 0
    public var totalCandiesUsed: Int = 0
    public var limitsHitCount: Int = 0
    public var usedStoneKinds: Set<String> = []
    public var maxDailyTokens: Int = 0
    public var nightOwlTriggered: Bool = false
    public var earlyBirdTriggered: Bool = false

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        dailyQuestDate = (try? c.decode(String.self, forKey: .dailyQuestDate)) ?? ""
        weeklyQuestKey = (try? c.decode(String.self, forKey: .weeklyQuestKey)) ?? ""
        claimedDailyQuestIDs = (try? c.decode(Set<String>.self, forKey: .claimedDailyQuestIDs)) ?? []
        claimedWeeklyQuestIDs = (try? c.decode(Set<String>.self, forKey: .claimedWeeklyQuestIDs)) ?? []
        claimedAchievementIDs = (try? c.decode(Set<String>.self, forKey: .claimedAchievementIDs)) ?? []
        currentStreak = (try? c.decode(Int.self, forKey: .currentStreak)) ?? 0
        bestStreak = (try? c.decode(Int.self, forKey: .bestStreak)) ?? 0
        lastActiveDate = (try? c.decode(String.self, forKey: .lastActiveDate)) ?? ""
        weeklyActiveDays = (try? c.decode(Set<String>.self, forKey: .weeklyActiveDays)) ?? []
        weeklyTokens = (try? c.decode(Int.self, forKey: .weeklyTokens)) ?? 0
        totalCandiesUsed = (try? c.decode(Int.self, forKey: .totalCandiesUsed)) ?? 0
        limitsHitCount = (try? c.decode(Int.self, forKey: .limitsHitCount)) ?? 0
        usedStoneKinds = (try? c.decode(Set<String>.self, forKey: .usedStoneKinds)) ?? []
        maxDailyTokens = (try? c.decode(Int.self, forKey: .maxDailyTokens)) ?? 0
        nightOwlTriggered = (try? c.decode(Bool.self, forKey: .nightOwlTriggered)) ?? false
        earlyBirdTriggered = (try? c.decode(Bool.self, forKey: .earlyBirdTriggered)) ?? false
    }
}
