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

    public init(todayTokens: Int, todayCost: Double, weekTokens: Int, monthTokens: Int,
                lastUpdated: Date, serverVersion: String, limits: PhoneLimitStatus?,
                companion: PhoneCompanionState?, providers: [PhoneProviderSnapshot]) {
        self.todayTokens = todayTokens
        self.todayCost = todayCost
        self.weekTokens = weekTokens
        self.monthTokens = monthTokens
        self.lastUpdated = lastUpdated
        self.serverVersion = serverVersion
        self.limits = limits
        self.companion = companion
        self.providers = providers
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
