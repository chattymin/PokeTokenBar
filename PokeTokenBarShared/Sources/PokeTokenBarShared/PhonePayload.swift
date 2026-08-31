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
    /// Shop wallet — tokens spendable in the shop (usedSinceInstall − spentTokens).
    public let spendableTokens: Int
    /// Shop listing (read-only on the phone; purchases happen on the Mac).
    public let shop: [PhoneShopEntry]
    /// Week / month cost in USD. nil from Macs that predate the field.
    public let weekCost: Double?
    public let monthCost: Double?
    /// Claude 5h depletion forecast (nil when no forecast can be made).
    public let burn: PhoneBurnForecast?

    public init(todayTokens: Int, todayCost: Double, weekTokens: Int, monthTokens: Int,
                lastUpdated: Date, serverVersion: String, limits: PhoneLimitStatus?,
                companion: PhoneCompanionState?, providers: [PhoneProviderSnapshot],
                bag: [PhoneBagItem] = [], dex: [PhoneDexSpecies] = [],
                spendableTokens: Int = 0, shop: [PhoneShopEntry] = [],
                weekCost: Double? = nil, monthCost: Double? = nil,
                burn: PhoneBurnForecast? = nil) {
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
        self.spendableTokens = spendableTokens
        self.shop = shop
        self.weekCost = weekCost
        self.monthCost = monthCost
        self.burn = burn
    }

    /// Older Mac versions publish payloads without `bag`/`dex`/`shop` — decode them
    /// as empty instead of failing the whole sync.
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
        spendableTokens = try c.decodeIfPresent(Int.self, forKey: .spendableTokens) ?? 0
        shop = try c.decodeIfPresent([PhoneShopEntry].self, forKey: .shop) ?? []
        weekCost = try c.decodeIfPresent(Double.self, forKey: .weekCost)
        monthCost = try c.decodeIfPresent(Double.self, forKey: .monthCost)
        burn = try c.decodeIfPresent(PhoneBurnForecast.self, forKey: .burn)
    }
}

// MARK: - Limit Status

public struct PhoneLimitStatus: Codable, Sendable, Equatable {
    public let claude5h: PhoneLimitWindow?
    public let claudeWeekly: PhoneLimitWindow?
    public let claudeOpusWeekly: PhoneLimitWindow?
    public let claudeSonnetWeekly: PhoneLimitWindow?
    /// 모델별 주간(weekly_scoped — Opus/Sonnet 레거시 필드 밖 창, 예: Fable 주간).
    /// Mac 이 현지화한 label 을 담는다. 구 Mac 페이로드에는 없어 nil 로 디코드된다.
    public let claudeScoped: [PhoneLimitWindow]?
    public let codexPrimary: PhoneLimitWindow?
    public let codexSecondary: PhoneLimitWindow?
    /// OpenCode Go 구독 한도(5h rolling/주간/월간) — 구독+키 보유 사용자만 전송된다.
    /// 구 Mac 이 보낸 페이로드에는 없으므로 옵셔널이며 디코드 시 nil 로 떨어진다.
    public let opencodeGo5h: PhoneLimitWindow?
    public let opencodeGoWeekly: PhoneLimitWindow?
    public let opencodeGoMonthly: PhoneLimitWindow?
    /// Antigravity quota buckets (Gemini / Claude&GPT groups × 5h/weekly), flattened in Mac
    /// display order. nil from Macs that predate the field.
    public let antigravity: [PhoneLimitWindow]?
    public let planDisplay: String?
    /// The Mac's warn / critical utilization thresholds so phone + widget colour rows the same
    /// way. nil → use `PhoneLimitStatus.defaultWarnThreshold` / `defaultCritThreshold`.
    public let warnThreshold: Double?
    public let critThreshold: Double?
    /// Per-window utilization history the Mac recorded locally (no API reports it — see the Mac's
    /// `LimitHistoryStore`). nil from Macs that predate the field; empty is a real answer meaning
    /// "recording, but no window has completed yet".
    public let history: [PhoneLimitHistorySeries]?

    public static let defaultWarnThreshold: Double = 80
    public static let defaultCritThreshold: Double = 95
    public var effectiveWarnThreshold: Double { warnThreshold ?? Self.defaultWarnThreshold }
    public var effectiveCritThreshold: Double { critThreshold ?? Self.defaultCritThreshold }

    public init(claude5h: PhoneLimitWindow?, claudeWeekly: PhoneLimitWindow?,
                claudeOpusWeekly: PhoneLimitWindow?, claudeSonnetWeekly: PhoneLimitWindow?,
                claudeScoped: [PhoneLimitWindow]? = nil,
                codexPrimary: PhoneLimitWindow?, codexSecondary: PhoneLimitWindow?,
                opencodeGo5h: PhoneLimitWindow? = nil,
                opencodeGoWeekly: PhoneLimitWindow? = nil,
                opencodeGoMonthly: PhoneLimitWindow? = nil,
                antigravity: [PhoneLimitWindow]? = nil,
                planDisplay: String?,
                warnThreshold: Double? = nil, critThreshold: Double? = nil,
                history: [PhoneLimitHistorySeries]? = nil) {
        self.claude5h = claude5h
        self.claudeWeekly = claudeWeekly
        self.claudeOpusWeekly = claudeOpusWeekly
        self.claudeSonnetWeekly = claudeSonnetWeekly
        self.claudeScoped = claudeScoped
        self.codexPrimary = codexPrimary
        self.codexSecondary = codexSecondary
        self.opencodeGo5h = opencodeGo5h
        self.opencodeGoWeekly = opencodeGoWeekly
        self.opencodeGoMonthly = opencodeGoMonthly
        self.antigravity = antigravity
        self.planDisplay = planDisplay
        self.warnThreshold = warnThreshold
        self.critThreshold = critThreshold
        self.history = history
    }

    /// 표시 순서대로 존재하는 모든 한도 창(nil 제외) — 폰 카드·위젯이 공유하는 단일 순서 소스.
    /// Claude(5h→주간→Opus→Sonnet→모델별) → Codex(5h→주간) → OpenCode Go(5h→주간→월간) → Antigravity.
    /// limitGroups 를 평탄화한 것과 동일 — 순서 소스는 하나다.
    public var orderedWindows: [PhoneLimitWindow] {
        limitGroups.flatMap(\.windows)
    }

    /// 프로바이더별로 묶은 한도 창 — 위젯의 파이+퍼센트 그룹 행용. 빈 그룹은 만들지 않는다.
    /// 창 순서는 orderedWindows 와 동일하다.
    public var limitGroups: [PhoneLimitGroup] {
        filteredLimitGroups(isProviderVisible: { _ in true })
    }

    /// 프로바이더 표시 여부 필터를 적용한 한도 창 묶음.
    public func filteredLimitGroups(isProviderVisible: (String) -> Bool) -> [PhoneLimitGroup] {
        var out: [PhoneLimitGroup] = []
        if isProviderVisible("claude_code") {
            var claude: [PhoneLimitWindow] = []
            if let w = claude5h { claude.append(w) }
            if let w = claudeWeekly { claude.append(w) }
            if let w = claudeOpusWeekly { claude.append(w) }
            if let w = claudeSonnetWeekly { claude.append(w) }
            claude.append(contentsOf: claudeScoped ?? [])
            if !claude.isEmpty { out.append(PhoneLimitGroup(title: "Claude", windows: claude)) }
        }
        if isProviderVisible("codex") {
            var codex: [PhoneLimitWindow] = []
            if let w = codexPrimary { codex.append(w) }
            if let w = codexSecondary { codex.append(w) }
            if !codex.isEmpty { out.append(PhoneLimitGroup(title: "Codex", windows: codex)) }
        }
        if isProviderVisible("opencode") {
            var go: [PhoneLimitWindow] = []
            if let w = opencodeGo5h { go.append(w) }
            if let w = opencodeGoWeekly { go.append(w) }
            if let w = opencodeGoMonthly { go.append(w) }
            if !go.isEmpty { out.append(PhoneLimitGroup(title: "Go", windows: go)) }
        }
        if isProviderVisible("antigravity") {
            if let agy = antigravity, !agy.isEmpty {
                let sortedAgy = Self.sortAntigravityWindows(agy)
                out.append(PhoneLimitGroup(title: "Antigravity", windows: sortedAgy))
            }
        }
        return out
    }

    /// Antigravity 창 정렬: Gemini 그룹 먼저, 각 그룹 내에서는 5시간 한도가 주간 한도보다 항상 앞에 오도록 정렬한다.
    public static func sortAntigravityWindows(_ windows: [PhoneLimitWindow]) -> [PhoneLimitWindow] {
        windows.sorted { a, b in
            let aIsGemini = a.label.localizedCaseInsensitiveContains("gemini")
            let bIsGemini = b.label.localizedCaseInsensitiveContains("gemini")
            if aIsGemini && !bIsGemini { return true }
            if !aIsGemini && bIsGemini { return false }

            let aIs5h = a.label.contains("5h") || a.label.contains("5시간") || a.label.contains("5時間") || a.label.contains("5 h")
            let bIs5h = b.label.contains("5h") || b.label.contains("5시간") || b.label.contains("5時間") || b.label.contains("5 h")
            if aIs5h && !bIs5h { return true }
            if !aIs5h && bIs5h { return false }

            return a.label < b.label
        }
    }

    /// Colour tier for a utilization value using the Mac's thresholds.
    public func tier(for utilization: Double) -> PhoneLimitTier {
        if utilization >= effectiveCritThreshold { return .critical }
        if utilization >= effectiveWarnThreshold { return .warning }
        return .normal
    }
}

public enum PhoneLimitTier: Sendable, Equatable {
    case normal, warning, critical
}

/// 한 프로바이더의 한도 창 묶음 — 제목(브랜드명, 위젯 그룹 헤더)과 orderedWindows 순서 창들.
public struct PhoneLimitGroup: Sendable, Equatable {
    public let title: String
    public let windows: [PhoneLimitWindow]

    public init(title: String, windows: [PhoneLimitWindow]) {
        self.title = title
        self.windows = windows
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

// MARK: - Limit History

/// One completed limit window, reduced to what a phone chart needs.
///
/// The Mac ships *derived* windows rather than the raw sample log behind them: the log is thousands
/// of rows over the 90-day retention, and every consumer here only ever draws the per-window peak.
public struct PhoneLimitHistoryWindow: Codable, Sendable, Equatable {
    /// Highest utilization observed during the window. A lower bound when `truncated`.
    public let peak: Double
    public let end: Date
    /// The Mac was not running for part of this window, so `peak` understates it.
    public let truncated: Bool

    public init(peak: Double, end: Date, truncated: Bool) {
        self.peak = peak
        self.end = end
        self.truncated = truncated
    }
}

/// History for one limit window kind (5-hour session, weekly, …), oldest window first.
///
/// `atOrAbove` is counted on the Mac against the same `PhoneLimitStatus.effectiveWarnThreshold`
/// that ships in this payload, so the phone can render the count and the threshold together
/// without recomputing either — recomputing is how the two drift apart.
public struct PhoneLimitHistorySeries: Codable, Sendable, Equatable {
    /// Mac-localized, matching the live limit row above it (same convention as `PhoneLimitWindow`).
    public let label: String
    public let windows: [PhoneLimitHistoryWindow]
    public let peak: Double
    public let median: Double
    public let atOrAbove: Int

    public init(label: String, windows: [PhoneLimitHistoryWindow],
                peak: Double, median: Double, atOrAbove: Int) {
        self.label = label
        self.windows = windows
        self.peak = peak
        self.median = median
        self.atOrAbove = atOrAbove
    }

    /// Any window whose peak is only a lower bound — the phone says so rather than presenting a
    /// hole as a fact.
    public var hasTruncated: Bool { windows.contains(where: \.truncated) }
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
    /// Species the Mac shows in its menu bar / Dock — the user's pinned representative, or the
    /// current mon when nothing is pinned. Widgets mirror this; the dashboard shows the current mon.
    public let representativeSpeciesID: Int?
    public let representativeIsShiny: Bool?
    /// Pre-localized one-line status ("In focus mode now.") matching the Mac companion header.
    public let statusText: String?
    /// Pre-localized nature name of the current mon (nil for eggs / old Macs).
    public let natureText: String?
    /// Evolution line strip: realized path + guaranteed next stages (+ one mystery node on a branch).
    public let lineNodes: [PhoneEvoNode]?

    public init(name: String, speciesID: Int?, isShiny: Bool, isEgg: Bool,
                progress: Double, stageText: String, rarity: String?,
                dexCount: Int, eggProgress: Double, displayState: String,
                evolutionTokens: Int? = nil, graduationTokens: Int? = nil,
                representativeSpeciesID: Int? = nil, representativeIsShiny: Bool? = nil,
                statusText: String? = nil, natureText: String? = nil,
                lineNodes: [PhoneEvoNode]? = nil) {
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
        self.representativeSpeciesID = representativeSpeciesID
        self.representativeIsShiny = representativeIsShiny
        self.statusText = statusText
        self.natureText = natureText
        self.lineNodes = lineNodes
    }
}

/// One node of the evolution line strip. `speciesID == nil` is the "?" mystery node.
public struct PhoneEvoNode: Codable, Sendable, Equatable {
    public enum State: String, Codable, Sendable { case done, current, future }
    public let speciesID: Int?
    /// Pre-localized species name (nil for the mystery node).
    public let name: String?
    public let state: State

    public init(speciesID: Int?, name: String?, state: State) {
        self.speciesID = speciesID
        self.name = name
        self.state = state
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

// MARK: - Shop (read-only)

/// One shop listing — a purchasable item or an egg reroll. The phone renders the
/// catalog read-only; buying happens on the Mac. Display strings are pre-localized
/// by the Mac, mirroring `PhoneBagItem`'s convention.
public struct PhoneShopEntry: Codable, Sendable, Equatable, Identifiable {
    /// Stable identifier: "item:<ItemKind rawValue>" or "egg:<tier|plain>".
    public let id: String
    /// Egg reroll listing (vs. inventory item).
    public let isEgg: Bool
    public let name: String
    public let itemDescription: String
    /// Price in spendable tokens.
    public let price: Int
    /// Egg tier floor rawValue ("uncommon"/"rare") for the rarity badge;
    /// nil = plain egg (no guarantee) or a regular item.
    public let rarity: String?
    /// Owned consumable count (passive items report 1 while owned). 0 = none.
    public let ownedCount: Int
    /// Passive (own-to-apply) item — no use action, permanently effective.
    public let isPassive: Bool
    /// A passive item already purchased — renders as "Owned" instead of a price CTA.
    public let isOwned: Bool
    /// Spendable tokens currently cover the price.
    public let canAfford: Bool
    /// PokéAPI item sprite filename (…/sprites/items/{name}.png). nil = emoji fallback.
    public let iconName: String?
    /// Emoji fallback when the sprite is unavailable (eggs always use this).
    public let fallbackEmoji: String

    public init(id: String, isEgg: Bool, name: String, itemDescription: String,
                price: Int, rarity: String?, ownedCount: Int, isPassive: Bool,
                isOwned: Bool, canAfford: Bool, iconName: String?, fallbackEmoji: String) {
        self.id = id
        self.isEgg = isEgg
        self.name = name
        self.itemDescription = itemDescription
        self.price = price
        self.rarity = rarity
        self.ownedCount = ownedCount
        self.isPassive = isPassive
        self.isOwned = isOwned
        self.canAfford = canAfford
        self.iconName = iconName
        self.fallbackEmoji = fallbackEmoji
    }
}
