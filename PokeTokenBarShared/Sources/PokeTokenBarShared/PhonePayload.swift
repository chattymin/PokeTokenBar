import Foundation

// MARK: - Mac → iPhone Sync Payload

/// Top-level payload served by the Mac HTTP server and consumed by the iPhone app + widget.
public struct PhonePayload: Codable, Sendable, Equatable {
    public let todayTokens: Int
    public let todayCost: Double
    public let weekTokens: Int
    public let monthTokens: Int
    public let lastUpdated: Date
    public let serverVersion: String
    public let limits: PhoneLimitStatus?
    public let companion: PhoneCompanionState?
    public let providers: [PhoneProviderSnapshot]
    /// Owned inventory items (read-only on the phone; items are used on the Mac).
    public let bag: [PhoneBagItem]
    /// Collected species (graduated + current) for the read-only phone dex.
    public let dex: [PhoneDexSpecies]

    public init(todayTokens: Int, todayCost: Double, weekTokens: Int, monthTokens: Int,
                lastUpdated: Date, serverVersion: String, limits: PhoneLimitStatus?,
                companion: PhoneCompanionState?, providers: [PhoneProviderSnapshot],
                bag: [PhoneBagItem] = [], dex: [PhoneDexSpecies] = []) {
        self.todayTokens = todayTokens
        self.todayCost = todayCost
        self.weekTokens = weekTokens
        self.monthTokens = monthTokens
        self.lastUpdated = lastUpdated
        self.serverVersion = serverVersion
        self.limits = limits
        self.companion = companion
        self.providers = providers
        self.bag = bag
        self.dex = dex
    }

    /// Older Mac versions publish payloads without `bag`/`dex` — decode them as empty
    /// instead of failing the whole sync.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        todayTokens = try c.decode(Int.self, forKey: .todayTokens)
        todayCost = try c.decode(Double.self, forKey: .todayCost)
        weekTokens = try c.decode(Int.self, forKey: .weekTokens)
        monthTokens = try c.decode(Int.self, forKey: .monthTokens)
        lastUpdated = try c.decode(Date.self, forKey: .lastUpdated)
        serverVersion = try c.decode(String.self, forKey: .serverVersion)
        limits = try c.decodeIfPresent(PhoneLimitStatus.self, forKey: .limits)
        companion = try c.decodeIfPresent(PhoneCompanionState.self, forKey: .companion)
        providers = try c.decodeIfPresent([PhoneProviderSnapshot].self, forKey: .providers) ?? []
        bag = try c.decodeIfPresent([PhoneBagItem].self, forKey: .bag) ?? []
        dex = try c.decodeIfPresent([PhoneDexSpecies].self, forKey: .dex) ?? []
    }
}

// MARK: - Limit Status

public struct PhoneLimitStatus: Codable, Sendable, Equatable {
    public let claude5h: PhoneLimitWindow?
    public let claudeWeekly: PhoneLimitWindow?
    public let claudeOpusWeekly: PhoneLimitWindow?
    public let claudeSonnetWeekly: PhoneLimitWindow?
    public let codexPrimary: PhoneLimitWindow?
    public let codexSecondary: PhoneLimitWindow?
    public let planDisplay: String?

    public init(claude5h: PhoneLimitWindow?, claudeWeekly: PhoneLimitWindow?,
                claudeOpusWeekly: PhoneLimitWindow?, claudeSonnetWeekly: PhoneLimitWindow?,
                codexPrimary: PhoneLimitWindow?, codexSecondary: PhoneLimitWindow?,
                planDisplay: String?) {
        self.claude5h = claude5h
        self.claudeWeekly = claudeWeekly
        self.claudeOpusWeekly = claudeOpusWeekly
        self.claudeSonnetWeekly = claudeSonnetWeekly
        self.codexPrimary = codexPrimary
        self.codexSecondary = codexSecondary
        self.planDisplay = planDisplay
    }
}

public struct PhoneLimitWindow: Codable, Sendable, Equatable {
    public let label: String
    public let utilization: Double
    public let resetsAt: Date?

    public init(label: String, utilization: Double, resetsAt: Date?) {
        self.label = label
        self.utilization = utilization
        self.resetsAt = resetsAt
    }
}

// MARK: - Companion State

public struct PhoneCompanionState: Codable, Sendable, Equatable {
    public let name: String
    public let speciesID: Int?
    public let isShiny: Bool
    public let isEgg: Bool
    public let progress: Double
    public let stageText: String
    public let rarity: String?
    public let dexCount: Int
    public let eggProgress: Double
    public let displayState: String
    public let evolutionTokens: Int?
    public let graduationTokens: Int?

    public init(name: String, speciesID: Int?, isShiny: Bool, isEgg: Bool,
                progress: Double, stageText: String, rarity: String?,
                dexCount: Int, eggProgress: Double, displayState: String,
                evolutionTokens: Int? = nil, graduationTokens: Int? = nil) {
        self.name = name
        self.speciesID = speciesID
        self.isShiny = isShiny
        self.isEgg = isEgg
        self.progress = progress
        self.stageText = stageText
        self.rarity = rarity
        self.dexCount = dexCount
        self.eggProgress = eggProgress
        self.displayState = displayState
        self.evolutionTokens = evolutionTokens
        self.graduationTokens = graduationTokens
    }
}

// MARK: - Provider Snapshot

public struct PhoneProviderSnapshot: Codable, Sendable, Equatable {
    public let id: String
    public let displayName: String
    public let todayTokens: Int
    public let todayCost: Double
    public let inputTokens: Int
    public let outputTokens: Int
    public let cacheWriteTokens: Int
    public let cacheReadTokens: Int
    public let reportsCost: Bool

    public init(id: String, displayName: String, todayTokens: Int, todayCost: Double,
                inputTokens: Int = 0, outputTokens: Int = 0,
                cacheWriteTokens: Int = 0, cacheReadTokens: Int = 0,
                reportsCost: Bool = true) {
        self.id = id
        self.displayName = displayName
        self.todayTokens = todayTokens
        self.todayCost = todayCost
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheWriteTokens = cacheWriteTokens
        self.cacheReadTokens = cacheReadTokens
        self.reportsCost = reportsCost
    }
}

// MARK: - Burn Forecast

public struct PhoneBurnForecast: Codable, Sendable, Equatable {
    public let depletionDate: Date?
    public let beforeReset: Bool
    public let tokensPerMinute: Double?

    public init(depletionDate: Date?, beforeReset: Bool, tokensPerMinute: Double?) {
        self.depletionDate = depletionDate
        self.beforeReset = beforeReset
        self.tokensPerMinute = tokensPerMinute
    }
}

// MARK: - Bag (inventory, read-only)

/// One owned inventory item. Display strings are pre-localized by the Mac (the phone
/// renders them as-is), mirroring how `PhoneCompanionState` carries display text.
public struct PhoneBagItem: Codable, Sendable, Equatable, Identifiable {
    /// Stable identifier (ItemKind rawValue, e.g. "rareCandy").
    public let id: String
    public let name: String
    public let itemDescription: String
    /// Owned count. Passive items are one-time purchases (count stays 1).
    public let count: Int
    /// Passive items have no use action — they apply while owned.
    public let isPassive: Bool
    /// Effect hint for passive items (e.g. shiny charm). Empty for consumables.
    public let effectHint: String
    /// PokéAPI item sprite filename (…/sprites/items/{name}.png). nil = no sprite.
    public let iconName: String?
    /// Emoji fallback when the sprite is unavailable.
    public let fallbackEmoji: String

    public init(id: String, name: String, itemDescription: String, count: Int,
                isPassive: Bool, effectHint: String, iconName: String?, fallbackEmoji: String) {
        self.id = id
        self.name = name
        self.itemDescription = itemDescription
        self.count = count
        self.isPassive = isPassive
        self.effectHint = effectHint
        self.iconName = iconName
        self.fallbackEmoji = fallbackEmoji
    }
}

// MARK: - Collection (dex, read-only)

/// One collected species — graduated records ∪ the current mon's reached stages.
/// Species-level only (nature/catch-time are Mac-side catch-log details).
public struct PhoneDexSpecies: Codable, Sendable, Equatable, Identifiable {
    /// Species ID = national dex number (sort key).
    public let id: Int
    /// Pre-localized species name from the Mac.
    public let name: String
    /// Rarity rawValue ("common"/"uncommon"/"rare"/"legendary").
    public let rarity: String
    /// This species has been owned shiny at some point.
    public let isShiny: Bool
    /// The only evidence is the currently-raised mon — the cell can disappear.
    public let isRaising: Bool

    public init(id: Int, name: String, rarity: String, isShiny: Bool, isRaising: Bool) {
        self.id = id
        self.name = name
        self.rarity = rarity
        self.isShiny = isShiny
        self.isRaising = isRaising
    }
}
