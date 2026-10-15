import Foundation

/// What changes hands in a trade — either a graduated dex entry or the mon currently being raised.
enum TradeItem: Codable, Sendable {
    case dexEntry(DexEntry)
    case activeMon(MonState)

    /// Values coming from the peer are trust-boundary data. Following the same principle as
    /// `SaveTransfer.sanitized`, normalize once right before commit — guarding every downstream
    /// arithmetic site instead would recur each time a new site is added.
    func sanitized() -> TradeItem {
        switch self {
        case .dexEntry(var entry):
            entry.profile?.sanitize()
            return .dexEntry(entry)
        case .activeMon(var mon):
            mon.usedAtStage = min(max(0, mon.usedAtStage), SaveTransfer.maxTokenValue)
            mon.totalForms = min(max(1, mon.totalForms), 12)
            mon.stageIndex = min(max(0, mon.stageIndex), max(0, mon.pathIDs.count - 1))
            mon.profile?.sanitize()
            return .activeMon(mon)
        }
    }

    var rarity: Rarity {
        switch self {
        case .dexEntry(let entry): return entry.rarity
        case .activeMon(let mon): return mon.rarity
        }
    }

    /// Display name for the approval screen to show "what" is being exchanged — rarity alone
    /// doesn't tell you what you're giving up in a trade that can't be undone. `DexEntry.names`
    /// travels with the payload, so the peer's item's species name resolves without a network
    /// call too. An active mon doesn't carry a name map, so it falls back to `#id`.
    func displayName(language: AppLanguage) -> String {
        switch self {
        case .dexEntry(let entry):
            return entry.names?[entry.finalID].flatMap { language.resolveName($0) } ?? "#\(entry.finalID)"
        case .activeMon(let mon):
            return "#\(mon.currentID)"
        }
    }

    /// The pre-approval warning text is only needed when receiving an active (in-progress) mon.
    var isActiveMon: Bool {
        if case .activeMon = self { return true }
        return false
    }

    /// The species whose sprite the approval screen / offer picker should draw — for a dex entry
    /// that's the `finalID` the dex itself shows, for an active mon it's the `currentID` at its
    /// current stage. The screen passes this value straight to `SpriteView` alongside the name.
    var displaySpeciesID: Int {
        switch self {
        case .dexEntry(let entry): return entry.finalID
        case .activeMon(let mon): return mon.currentID
        }
    }

    var displayIsShiny: Bool {
        switch self {
        case .dexEntry(let entry): return entry.isShiny
        case .activeMon(let mon): return mon.isShiny
        }
    }

    var displayUnownForm: UnownForm? {
        switch self {
        case .dexEntry(let entry): return entry.unownForm
        case .activeMon(let mon): return mon.unownForm
        }
    }

    /// The baseline line for name lookup — `PokeProviding.line(baseSpeciesID:)` returns the whole
    /// evolution chain's names keyed off the pre-evolution stage.
    var displayBaseID: Int {
        switch self {
        case .dexEntry(let entry): return entry.baseID
        case .activeMon(let mon): return mon.baseID
        }
    }
}
