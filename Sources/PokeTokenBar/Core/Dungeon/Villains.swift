import Foundation

/// The villains' teams (issue #180, the owner, 2026-11-10): one may ambush the player for an item of the Bag. Beaten, it
/// flies off with nothing; winning, it takes the item to its hideout, a dungeon of the item's tier whose leader keeps it
/// until a team gets it back.
enum VillainTeam: String, Codable, Sendable, CaseIterable {
    /// One team a tier (the owner, 2026-11-10: "une team de méchant pour chaque tier", Team Rocket at the top).
    case skull, magma, aqua, galactic, rocket

    /// The team that goes for an item of this tier.
    static func team(for tier: DungeonTier) -> VillainTeam {
        switch tier {
        case .t1: .skull
        case .t2: .magma
        case .t3: .aqua
        case .t4: .galactic
        case .t5: .rocket
        }
    }

    var tier: DungeonTier {
        switch self {
        case .skull: .t1
        case .magma: .t2
        case .aqua: .t3
        case .galactic: .t4
        case .rocket: .t5
        }
    }

    var themeTypes: [PokemonType] {
        switch self {
        case .skull: [.poison, .bug]
        case .magma: [.fire, .ground]
        case .aqua: [.water, .dark]
        case .galactic: [.poison, .steel]
        case .rocket: [.poison, .normal]
        }
    }

    /// The grunts' Pokémon, as in their games.
    var grunts: [Int] {
        switch self {
        case .skull: [758, 748, 42, 89, 168, 760]
        case .magma: [262, 323, 324, 110, 42, 219]
        case .aqua: [262, 319, 342, 73, 42, 279]
        case .galactic: [435, 454, 432, 437, 42, 426]
        case .rocket: [20, 24, 42, 89, 110, 97]
        }
    }

    /// The leader's three at the end of the hideout: Giovanni with Mewtwo and Persian (the owner), the others their aces.
    var leaderTeam: [Int] {
        switch self {
        case .skull: [768, 168, 127]
        case .magma: [323, 169, 262]
        case .aqua: [319, 342, 73]
        case .galactic: [461, 430, 130]
        case .rocket: [150, 53, 34]
        }
    }

    var hideoutID: DungeonID {
        switch self {
        case .skull: .skullHideout
        case .magma: .magmaHideout
        case .aqua: .aquaHideout
        case .galactic: .galacticHideout
        case .rocket: .rocketHideout
        }
    }

    /// The leader's three as they stand: Giovanni's Mewtwo in its armor (the owner, 2026-11-10), the others as usual.
    var leaderForms: [PokemonForm?] { self == .rocket ? [ArmoredMewtwo.form, nil, nil] : [nil, nil, nil] }

    var gruntPortrait: String { "villain-\(rawValue)-grunt" }
    var leaderPortrait: String { "villain-\(rawValue)-leader" }

    /// The team's color, for its cards.
    var rgb: (red: Double, green: Double, blue: Double) {
        switch self {
        case .skull: (0.55, 0.55, 0.62)
        case .magma: (0.90, 0.32, 0.14)
        case .aqua: (0.16, 0.45, 0.90)
        case .galactic: (0.38, 0.58, 0.72)
        case .rocket: (0.86, 0.16, 0.20)
        }
    }

    /// Their Pokémon Masters EX renders, from WikiDex as Prof. Oak's and the merchants'.
    static let portraitURLs: [String: String] = {
        let base = "https://images.wikidexcdn.net/mwuploads/wikidex/"
        return [
            "villain-rocket-grunt": base + "d/d7/latest/20210914060636/Recluta_del_Team_Rocket_masculino_Masters.png",
            "villain-aqua-grunt": base + "5/51/latest/20220727061405/Recluta_del_Equipo_Aqua_masculino_Masters.png",
            "villain-magma-grunt": base + "4/43/latest/20220727061259/Recluta_del_Equipo_Magma_masculino_Masters.png",
            "villain-galactic-grunt": base + "5/53/latest/20211221094210/Recluta_Galaxia_masculino_Masters.png",
            "villain-skull-grunt": base + "b/ba/latest/20250819193111/Recluta_del_Team_Skull_masculino_Masters.png",
            "villain-rocket-leader": base + "b/b2/latest/20200825103758/Giovanni_Masters.png",
            "villain-aqua-leader": base + "d/d5/latest/20210426062209/Aquiles_Masters.png",
            "villain-magma-leader": base + "6/65/latest/20210426062636/Magno_Masters.png",
            "villain-galactic-leader": base + "a/ad/latest/20200929193057/Helio_Masters.png",
            "villain-skull-leader": base + "3/3b/latest/20200323132750/Guzm%C3%A1n_Masters.png",
        ]
    }()
}

/// A team waiting on Home for the player to defend an item (no time limit), then how it went.
struct VillainAmbush: Codable, Sendable, Equatable, Identifiable {
    /// The day it came and the item, unique: thefts add up (the owner, 2026-11-10).
    var id: String
    var team: VillainTeam
    /// `ItemKind.rawValue`, and how many of it.
    var item: String
    var count: Int
    var at: Date
    var seed: UInt64
    var grunts: [Int]
    /// Nil until the player defends; then whether they won.
    var won: Bool?
    var battle: ExpeditionBattle?
    /// "Later": a low banner on Home until it is settled, never gone before (the owner, 2026-11-10).
    var collapsed: Bool?

    var kind: ItemKind? { ItemKind(rawValue: item) }
    var tier: DungeonTier { kind.flatMap(VillainRules.tier) ?? .t1 }
}

/// What a team took to its hideout, given back when its leader falls.
struct VillainStash: Codable, Sendable, Equatable {
    var team: VillainTeam
    var items: [String: Int]
    /// The hideout's tier: its team's.
    var tier: DungeonTier { team.tier }
}

enum VillainRules {
    /// Every day, at a minute drawn between 8:00 and 17:30 (the owner, 2026-11-13: "1 fois par jour mais à une heure
    /// random entre 8h et 17h30"; one day in three at most before, a rule he never asked for).
    static let earliestMinute = 8 * 60
    static let latestMinute = 17 * 60 + 30

    /// What an item is worth to a thief: the hideout's tier. Nil: never stolen (badges, medals, form rewards, whose
    /// steps are counted apart).
    static func tier(of kind: ItemKind) -> DungeonTier? {
        switch kind {
        case .rareCandy, .oranBerry, .sitrusBerry, .greatBall, .revive: return .t1
        case .ultraBall, .maxRevive, .mint, .silverCapsule, .pokemonEgg, .uncommonEgg, .explorerChest, .treasureMap:
            return .t2
        case .rareEgg, .goldCapsule, .legendaryKey, .fossilEgg: return .t3
        case .masterBall, .legendaryEgg, .typeNullEgg, .birthdayEgg: return .t4
        default: break
        }
        if kind.stoneType != nil { return .t2 }
        if EventEgg(item: kind) != nil { return .t3 }
        guard kind.isPassive, !kind.isRegional, kind.moreFormsSpecies == nil else { return nil }
        // The achievements' artifacts are the big prize; the Shop's a step below.
        return kind.isAchievement ? .t5 : .t4
    }

    /// The draw's weights by tier, among the tiers the Bag holds: a candy most often, an artifact rarely.
    static let tierWeights: [DungeonTier: Int] = [.t1: 40, .t2: 28, .t3: 18, .t4: 9, .t5: 5]

    /// How many they take (the owner, 2026-11-16: "les vols les moins oufs plus chiants"): half the stack of an
    /// everyday item, three at least and twenty at most; up to three of a T2 item; one of anything else. Three of an
    /// everyday item and one of the rest before.
    static func count(of kind: ItemKind, have: Int) -> Int {
        switch tier(of: kind) {
        case .t1?: min(have, min(20, max(3, have / 2)))
        case .t2?: min(have, 3)
        default: min(have, 1)
        }
    }

    /// What they take from a team just back from a dungeon (the owner, 2026-11-16): every Rare Candy the run brought,
    /// else the most precious item it brought, as many as `count` allows of what it brought; nil when the run brought
    /// nothing they would take, or none of it is left in the Bag.
    static func target(fromRun loot: ExpeditionLoot, bag: [ItemKind: Int]) -> (kind: ItemKind, count: Int)? {
        if loot.candies > 0, let have = bag[.rareCandy], have > 0 { return (.rareCandy, min(loot.candies, have)) }
        let brought = loot.items.compactMap { key, count -> (kind: ItemKind, count: Int, tier: DungeonTier)? in
            guard count > 0, let kind = ItemKind(rawValue: key), let tier = tier(of: kind), (bag[kind] ?? 0) > 0 else { return nil }
            return (kind, count, tier)
        }
        guard let best = brought.max(by: { ($0.tier, $1.kind.rawValue) < ($1.tier, $0.kind.rawValue) }) else { return nil }
        return (best.kind, min(best.count, count(of: best.kind, have: bag[best.kind] ?? 0)))
    }

    /// The leader's chest, given with all the team took once its leader falls (the owner, 2026-11-16).
    static func leaderChest(_ tier: DungeonTier) -> (candies: Int, items: [(kind: ItemKind, count: Int)]) {
        switch tier {
        case .t1: (3, [(.greatBall, 2)])
        case .t2: (0, [(.silverCapsule, 1), (.ultraBall, 2)])
        case .t3: (0, [(.goldCapsule, 1), (.legendaryKey, 1)])
        case .t4: (0, [(.rareEgg, 1), (.masterBall, 1)])
        case .t5: (0, [(.legendaryEgg, 1), (.masterBall, 1)])
        }
    }

    /// What may be abandoned to a team: anything but an artifact, which they can never keep for good.
    static func canAbandon(_ kind: ItemKind) -> Bool { !kind.isPassive }

    /// The minute of the day (`yyyy-MM-dd`) they come at, from midnight, the same all day on every launch: FNV-1a, as the
    /// merchant's. The team is the one of the item it takes (`VillainTeam.team(for:)`).
    static func minute(_ day: String) -> Int {
        var random = random(day)
        return earliestMinute + random.below(latestMinute - earliestMinute + 1)
    }

    static func random(_ text: String) -> BattleRandom {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in "villain:\(text)".utf8 { hash = (hash ^ UInt64(byte)) &* 0x100_0000_01b3 }
        return BattleRandom(seed: hash)
    }

    /// The item a team goes for, and how many: a tier by its weight among those the Bag holds, then one of its items.
    static func target(_ bag: [ItemKind: Int], random: inout BattleRandom) -> (kind: ItemKind, count: Int)? {
        let held = bag.filter { $0.value > 0 && tier(of: $0.key) != nil }.keys.sorted { $0.rawValue < $1.rawValue }
        let byTier = Dictionary(grouping: held) { tier(of: $0) ?? .t1 }
        let tiers = DungeonTier.allCases.filter { byTier[$0] != nil }
        let total = tiers.reduce(0) { $0 + (tierWeights[$1] ?? 0) }
        guard total > 0 else { return nil }
        var roll = random.below(total)
        for tier in tiers {
            let weight = tierWeights[tier] ?? 0
            if roll < weight, let items = byTier[tier] {
                let kind = items[random.below(items.count)]
                return (kind, count(of: kind, have: bag[kind] ?? 0))
            }
            roll -= weight
        }
        return nil
    }

    /// Three grunts' Pokémon, none twice.
    static func grunts(_ team: VillainTeam, random: inout BattleRandom) -> [Int] {
        var pool = team.grunts
        var picked: [Int] = []
        while picked.count < 3, !pool.isEmpty { picked.append(pool.remove(at: random.below(pool.count))) }
        return picked
    }

    /// The ambush's HP and stats: they come three against six, so each stands longer, more so for a precious item (the
    /// owner: "faut pas que tu les battes tout le temps"). Measured on 2026-11-10 over 420 fights a tier, a team of
    /// legendaries wins 91, 80, 72, 57 and 44 % from T1 to T5, Charizard and friends 49, 27, 13, 8 and 4 %.
    static func ambushFactors(_ tier: DungeonTier) -> (hp: Double, stats: Double) {
        switch tier {
        case .t1: (2.6, 1.15)
        case .t2: (2.8, 1.19)
        case .t3: (3.0, 1.23)
        case .t4: (3.2, 1.27)
        case .t5: (3.4, 1.31)
        }
    }

    static func gruntSpecs(_ species: [Int], tier: DungeonTier, seed: UInt64) -> [BattlerSpec] {
        var random = BattleRandom(seed: seed)
        let (hp, stats) = ambushFactors(tier)
        return species.enumerated().compactMap { i, id in
            let ivs = (0..<6).map { _ in 16 + random.below(16) }
            return BattlerSpec.make(id: "grunt-\(i)-\(id)", speciesID: id, level: 100, ivs: ivs, hpFactor: hp, statFactor: stats)
        }
    }

    /// The leader's three at the hideout's end, each a boss of its tier at two thirds of a lone boss's HP (three in a row),
    /// their legendary as one (`ExpeditionEngine.bossSpec`).
    static func leaderSpecs(_ team: VillainTeam, tier: DungeonTier, random: inout BattleRandom) -> [BattlerSpec] {
        var specs: [BattlerSpec] = []
        for (i, id) in team.leaderTeam.enumerated() {
            let form = team.leaderForms[i]
            guard var spec = ExpeditionEngine.bossSpec(ExpeditionBoss(speciesID: id, form: form, isShiny: false), tier: tier,
                                                       random: &random) else { continue }
            spec.id = "leader-\(i)-\(id)"
            if !(SpeciesInfo.all[id]?.isLegendary ?? false) {
                spec.stats.hp = max(1, spec.stats.hp * 2 / 3)
                spec.hp = spec.stats.hp
            }
            specs.append(spec)
        }
        return specs
    }

    /// The hideout as a dungeon: its tier's floors and team size, no rule, the team's Pokémon on its floors, its
    /// leader's ace as the boss (the other two join it, `leaderSpecs`).
    static func hideout(_ team: VillainTeam) -> Dungeon {
        let tier = team.tier
        let size = tier == .t1 ? 3 : tier == .t2 ? 4 : 6
        return Dungeon(id: team.hideoutID, tier: tier, teamSize: size, rules: [], themeTypes: team.themeTypes,
                       wild: team.grunts, bosses: [team.leaderTeam[0]], unlocks: [])
    }
}

/// Team Rocket's armored Mewtwo (the owner, 2026-11-10: "le mewtwo de la team rocket avec l'armure", for Giovanni).
/// Neither PokéAPI nor Showdown has it: its sprite is Pokémon GO's render (PokeMiners), its battle data Mewtwo's own
/// (`SpeciesBattleTable.data` falls back to the species for a form it does not know).
enum ArmoredMewtwo {
    static let speciesID = 150
    static let form = PokemonForm("armor")
    static let spriteURL = "https://raw.githubusercontent.com/PokeMiners/pogo_assets/master/Images/Pokemon%20-%20256x256/Addressable%20Assets/pm150.fA.icon.png"

    static func matches(speciesID: Int, form: PokemonForm?) -> Bool { speciesID == Self.speciesID && form == Self.form }
}
