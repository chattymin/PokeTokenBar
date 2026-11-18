import Foundation

enum HatchEgg: Codable, Sendable, Hashable {
    /// A Pokémon Egg (nil: the egg after a graduation, or the Shop's plain egg), or an egg of a guaranteed rarity, bought
    /// or given by an achievement: the same Bag item.
    case tier(Rarity?)
    case stone(PokemonType)
    case legendary
    case typeNull
    case birthday
    case fossil
    /// `key`: the claim it came from (`CompanionState.eggEventKey`).
    case event(EventEgg, key: String?)
    /// A dungeon boss's egg (`DungeonEgg`): its line, in its form, shiny when the boss was.
    case dungeon(baseID: Int, form: PokemonForm?, shiny: Bool)
    /// A Costume Egg (`CostumeEgg`): its first stage, in its costume; shiny as any egg's roll.
    case costume(code: String, speciesID: Int)

    /// The guarantees its pool keeps; nil for the eggs with a draw of their own.
    var spec: CompanionStore.EggSpec? {
        switch self {
        case .tier(let tier): return .init(tier: tier)
        case .stone(let type): return .init(type: type)
        case .legendary: return .init(legendaryEgg: true)
        case .event(let event, _): return .init(tier: event.tier, type: event.type, event: event)
        case .typeNull, .birthday, .fossil, .dungeon, .costume: return nil
        }
    }

    init?(item: ItemKind) {
        switch item {
        case .typeNullEgg: self = .typeNull
        case .fossilEgg: self = .fossil
        case .birthdayEgg: self = .birthday
        case .legendaryEgg: self = .legendary
        default:
            if item.isShopEgg { self = .tier(item.bagEggTier) }
            else if let type = item.stoneType { self = .stone(type) }
            else if let event = EventEgg(item: item) { self = .event(event, key: nil) }
            else { return nil }
        }
    }

    /// The same egg whatever claim it came from.
    var withoutKey: HatchEgg {
        if case .event(let event, _) = self { return .event(event, key: nil) }
        return self
    }
}

/// How a Pokémon hatched, kept with it from its hatch to its graduation or release, for the Luck screen to replay its
/// rolls (`HatchDraw`): its egg, and the draw items each roll met.
struct HatchRecord: Codable, Sendable, Equatable {
    enum Source: String, Codable, Sendable {
        /// The app, at the hatch.
        case hatch
        /// The player, for a hatch from before the record.
        case player
        /// The log, for a hatch from before the record (`EggJournal`).
        case journal
        /// The app's best guess, which the player asked for.
        case deduced
    }

    var egg: HatchEgg
    /// The draw items owned when its species was rolled, its form with it: as the egg started, or at the hatch when
    /// nothing was rolled before.
    var rollItems: Set<ItemKind> = []
    /// The draw items owned when it hatched: its shiny and Ditto rolls.
    var hatchItems: Set<ItemKind> = []
    var source = Source.hatch
    /// The line its egg rolled when it became something else: a Ditto's disguise, the next egg's line hatched last.
    var rolledBaseID: Int?

    /// A hatch from before the record: nothing noted its draw items, which come from their dates.
    var itemsFromDates: Bool { source != .hatch }
    /// The player may still say otherwise.
    var isOpenToPlayer: Bool { source == .player || source == .deduced }

    init(egg: HatchEgg, rollItems: Set<ItemKind> = [], hatchItems: Set<ItemKind> = [], source: Source = .hatch,
         rolledBaseID: Int? = nil) {
        self.egg = egg
        self.rollItems = rollItems
        self.hatchItems = hatchItems
        self.source = source
        self.rolledBaseID = rolledBaseID
    }

    /// An item a later build added is left out, not the record.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        egg = try c.decode(HatchEgg.self, forKey: .egg)
        func items(_ key: CodingKeys) -> Set<ItemKind> {
            Set(((try? c.decodeIfPresent([String].self, forKey: key)) ?? nil)?.compactMap(ItemKind.init(rawValue:)) ?? [])
        }
        rollItems = items(.rollItems)
        hatchItems = items(.hatchItems)
        source = ((try? c.decodeIfPresent(Source.self, forKey: .source)) ?? nil) ?? .hatch
        rolledBaseID = (try? c.decodeIfPresent(Int.self, forKey: .rolledBaseID)) ?? nil
    }
}

extension CompanionState {
    /// The egg incubating, as its record names it.
    var incubatingHatchEgg: HatchEgg {
        if let egg = eggFromDungeon { return egg.hatchEgg }
        if let egg = eggFromCostume { return .costume(code: egg.code, speciesID: egg.speciesID) }
        if let eggEvent { return .event(eggEvent, key: eggEventKey) }
        if eggFromTypeNullEgg { return .typeNull }
        if eggFromBirthdayEgg { return .birthday }
        if eggFromFossilEgg { return .fossil }
        if eggFromLegendaryEgg { return .legendary }
        if let eggTypeGuarantee { return .stone(eggTypeGuarantee) }
        return .tier(eggTier)
    }
}

extension DungeonEgg {
    var hatchEgg: HatchEgg { .dungeon(baseID: baseID, form: form, shiny: isShiny) }
}
