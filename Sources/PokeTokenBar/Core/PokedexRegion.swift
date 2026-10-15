import Foundation

/// A Pokémon generation, identified by its home region. Named "region" (not "generation") on purpose:
/// the companion code already uses `generation`/`activeGeneration` for egg-hatch attempt tokens.
///
/// Membership is derived purely from the National Dex number — Gen 1 = 1–151, Gen 2 = 152–251,
/// Gen 3 = 252–386, Gen 4 = 387–493, Gen 5 = 494–649 — so no PokéAPI call is needed to place a species.
enum PokedexRegion: String, CaseIterable, Codable, Sendable, Identifiable {
    case kanto, johto, hoenn, sinnoh, unova

    var id: String { rawValue }

    /// National Dex numbers that belong to this region.
    var dexRange: ClosedRange<Int> {
        switch self {
        case .kanto: return 1...151
        case .johto: return 152...251
        case .hoenn: return 252...386
        case .sinnoh: return 387...493
        case .unova: return 494...649
        }
    }

    /// Number of species in the generation (what a complete regional dex requires).
    var total: Int { dexRange.count }

    /// The region a National Dex number belongs to, or `nil` outside Gen 1–5.
    static func region(forDexNumber dexNumber: Int) -> PokedexRegion? {
        allCases.first { $0.dexRange.contains(dexNumber) }
    }

    /// The full Gen 1–5 National Dex.
    static let nationalRange = 1...649
    static var nationalTotal: Int { nationalRange.count }
}

/// Owned/total progress for one region, including the harder shiny tier.
struct DexCompletion: Sendable, Equatable, Identifiable {
    let region: PokedexRegion
    let owned: Int
    let shinyOwned: Int

    var total: Int { region.total }
    var isComplete: Bool { owned >= total }
    var isShinyComplete: Bool { shinyOwned >= total }
    var id: String { region.rawValue }
}

/// A cosmetic completion achievement. Cases carry a stable `notificationKey` because the
/// "already notified" set is persisted — the keys must never drift across releases.
enum DexBadge: Equatable, Hashable, Sendable {
    case region(PokedexRegion)
    case regionShiny(PokedexRegion)
    case unown
    case national
    case nationalShiny

    var notificationKey: String {
        switch self {
        case .region(let r): return "region.\(r.rawValue)"
        case .regionShiny(let r): return "regionShiny.\(r.rawValue)"
        case .unown: return "unown"
        case .national: return "national"
        case .nationalShiny: return "nationalShiny"
        }
    }
}

/// Pure computation of dex completion from the set of owned species. Kept store-independent so the
/// generation math is unit-testable without spinning up the whole companion store.
enum DexProgress {
    /// Number of Unown letter forms required for the Unown badge (all 28).
    static var unownTotal: Int { UnownForm.allCases.count }

    /// Per-region owned/total (and shiny-owned) counts. Duplicate ids contribute once per form;
    /// a species counts as shiny-owned if any owned individual of it is shiny.
    static func regionCompletions(owned: [(id: Int, isShiny: Bool)]) -> [DexCompletion] {
        var shinyByID: [Int: Bool] = [:]
        for species in owned {
            shinyByID[species.id, default: false] = shinyByID[species.id, default: false] || species.isShiny
        }
        return PokedexRegion.allCases.map { region in
            let ids = shinyByID.keys.filter { region.dexRange.contains($0) }
            let shiny = ids.filter { shinyByID[$0] == true }.count
            return DexCompletion(region: region, owned: ids.count, shinyOwned: shiny)
        }
    }

    /// National (Gen 1–5) owned/total, reusing `DexCompletion` with a nil-less synthetic region slot
    /// is avoided — national progress is returned as a plain tuple the header formats directly.
    static func nationalProgress(owned: [(id: Int, isShiny: Bool)]) -> (owned: Int, shinyOwned: Int, total: Int) {
        var shinyByID: [Int: Bool] = [:]
        for species in owned where PokedexRegion.nationalRange.contains(species.id) {
            shinyByID[species.id, default: false] = shinyByID[species.id, default: false] || species.isShiny
        }
        let shiny = shinyByID.values.filter { $0 }.count
        return (owned: shinyByID.count, shinyOwned: shiny, total: PokedexRegion.nationalTotal)
    }

    /// Every badge the player has currently earned, in a stable order (regions, then Unown, then national).
    static func earnedBadges(owned: [(id: Int, isShiny: Bool)], unownFormsCollected: Int) -> [DexBadge] {
        var badges: [DexBadge] = []
        for completion in regionCompletions(owned: owned) {
            if completion.isComplete { badges.append(.region(completion.region)) }
            if completion.isShinyComplete { badges.append(.regionShiny(completion.region)) }
        }
        if unownFormsCollected >= unownTotal { badges.append(.unown) }
        let national = nationalProgress(owned: owned)
        if national.owned >= national.total { badges.append(.national) }
        if national.shinyOwned >= national.total { badges.append(.nationalShiny) }
        return badges
    }

    /// Badges that are earned but not yet announced — the ones a completion notification should fire for.
    /// Order is preserved so the notifications arrive in the stable badge order.
    static func newlyEarnedBadges(earned: [DexBadge], alreadyNotified: Set<String>) -> [DexBadge] {
        earned.filter { !alreadyNotified.contains($0.notificationKey) }
    }
}
