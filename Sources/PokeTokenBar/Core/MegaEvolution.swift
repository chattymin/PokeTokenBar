import Foundation

/// The legacy XY/ORAS Mega Evolutions that can be collected by the app.
///
/// Mega forms use their numeric PokeAPI sprite IDs instead of bundled artwork. Keeping
/// the mapping here gives the store, UI and tests one source of truth for eligibility and
/// the runtime sprite URL.
enum MegaStone: String, Codable, CaseIterable, Hashable, Sendable {
    case venusaurite
    case charizarditeX
    case charizarditeY
    case blastoisinite
    case alakazite
    case gengarite
    case kangaskhanite
    case pinsirite
    case gyaradosite
    case aerodactylite
    case mewtwoniteX
    case mewtwoniteY
    case ampharosite
    case scizorite
    case heracronite
    case houndoominite
    case tyranitarite
    case blazikenite
    case gardevoirite
    case mawilite
    case aggronite
    case medichamite
    case manectite
    case banettite
    case absolite
    case garchompite
    case lucarionite
    case abomasite
    case latiasite
    case latiosite
    case swampertite
    case sceptilite
    case sablenite
    case altarianite
    case galladite
    case audinite
    case sharpedonite
    case slowbronite
    case steelixite
    case pidgeotite
    case glalitite
    case metagrossite
    case cameruptite
    case lopunnite
    case salamencite
    case beedrillite

    /// The final, owned species required before this stone can be activated.
    var eligibleSpeciesID: Int {
        switch self {
        case .venusaurite: return 3
        case .charizarditeX, .charizarditeY: return 6
        case .blastoisinite: return 9
        case .alakazite: return 65
        case .gengarite: return 94
        case .kangaskhanite: return 115
        case .pinsirite: return 127
        case .gyaradosite: return 130
        case .aerodactylite: return 142
        case .mewtwoniteX, .mewtwoniteY: return 150
        case .ampharosite: return 181
        case .scizorite: return 212
        case .heracronite: return 214
        case .houndoominite: return 229
        case .tyranitarite: return 248
        case .blazikenite: return 257
        case .gardevoirite: return 282
        case .mawilite: return 303
        case .aggronite: return 306
        case .medichamite: return 308
        case .manectite: return 310
        case .banettite: return 354
        case .absolite: return 359
        case .garchompite: return 445
        case .lucarionite: return 448
        case .abomasite: return 460
        case .latiasite: return 380
        case .latiosite: return 381
        case .swampertite: return 260
        case .sceptilite: return 254
        case .sablenite: return 302
        case .altarianite: return 334
        case .galladite: return 475
        case .audinite: return 531
        case .sharpedonite: return 319
        case .slowbronite: return 80
        case .steelixite: return 208
        case .pidgeotite: return 18
        case .glalitite: return 362
        case .metagrossite: return 376
        case .cameruptite: return 323
        case .lopunnite: return 428
        case .salamencite: return 373
        case .beedrillite: return 15
        }
    }

    /// PokeAPI's static form IDs. These are deliberately kept outside the normal
    /// 1...649 animated range, so SpriteLoader falls back to a static PNG.
    var megaSpeciesID: Int {
        switch self {
        case .venusaurite: return 10033
        case .charizarditeX: return 10034
        case .charizarditeY: return 10035
        case .blastoisinite: return 10036
        case .alakazite: return 10037
        case .gengarite: return 10038
        case .kangaskhanite: return 10039
        case .pinsirite: return 10040
        case .gyaradosite: return 10041
        case .aerodactylite: return 10042
        case .mewtwoniteX: return 10043
        case .mewtwoniteY: return 10044
        case .ampharosite: return 10045
        case .scizorite: return 10046
        case .heracronite: return 10047
        case .houndoominite: return 10048
        case .tyranitarite: return 10049
        case .blazikenite: return 10050
        case .gardevoirite: return 10051
        case .mawilite: return 10052
        case .aggronite: return 10053
        case .medichamite: return 10054
        case .manectite: return 10055
        case .banettite: return 10056
        case .absolite: return 10057
        case .garchompite: return 10058
        case .lucarionite: return 10059
        case .abomasite: return 10060
        case .latiasite: return 10062
        case .latiosite: return 10063
        case .swampertite: return 10064
        case .sceptilite: return 10065
        case .sablenite: return 10066
        case .altarianite: return 10067
        case .galladite: return 10068
        case .audinite: return 10069
        case .sharpedonite: return 10070
        case .slowbronite: return 10071
        case .steelixite: return 10072
        case .pidgeotite: return 10073
        case .glalitite: return 10074
        case .metagrossite: return 10076
        case .cameruptite: return 10087
        case .lopunnite: return 10088
        case .salamencite: return 10089
        case .beedrillite: return 10090
        }
    }

    /// Persistent unlock key. Mega stones live beside the existing ItemKind
    /// inventory so unlocks travel through the same local and transfer saves.
    static let inventoryPrefix = "megaStone:"
    var inventoryKey: String { Self.inventoryPrefix + rawValue }

    /// PokeAPI's item sprite filename. These are loaded at runtime and cached by
    /// the same SpriteStore used for the existing shop items.
    var spriteName: String {
        switch self {
        case .venusaurite: return "venusaurite"
        case .charizarditeX: return "charizardite-x"
        case .charizarditeY: return "charizardite-y"
        case .blastoisinite: return "blastoisinite"
        case .alakazite: return "alakazite"
        case .gengarite: return "gengarite"
        case .kangaskhanite: return "kangaskhanite"
        case .pinsirite: return "pinsirite"
        case .gyaradosite: return "gyaradosite"
        case .aerodactylite: return "aerodactylite"
        case .mewtwoniteX: return "mewtwonite-x"
        case .mewtwoniteY: return "mewtwonite-y"
        case .ampharosite: return "ampharosite"
        case .scizorite: return "scizorite"
        case .heracronite: return "heracronite"
        case .houndoominite: return "houndoominite"
        case .tyranitarite: return "tyranitarite"
        case .blazikenite: return "blazikenite"
        case .gardevoirite: return "gardevoirite"
        case .mawilite: return "mawilite"
        case .aggronite: return "aggronite"
        case .medichamite: return "medichamite"
        case .manectite: return "manectite"
        case .banettite: return "banettite"
        case .absolite: return "absolite"
        case .garchompite: return "garchompite"
        case .lucarionite: return "lucarionite"
        case .abomasite: return "abomasite"
        case .latiasite: return "latiasite"
        case .latiosite: return "latiosite"
        case .swampertite: return "swampertite"
        case .sceptilite: return "sceptilite"
        case .sablenite: return "sablenite"
        case .altarianite: return "altarianite"
        case .galladite: return "galladite"
        case .audinite: return "audinite"
        case .sharpedonite: return "sharpedonite"
        case .slowbronite: return "slowbronite"
        case .steelixite: return "steelixite"
        case .pidgeotite: return "pidgeotite"
        case .glalitite: return "glalitite"
        case .metagrossite: return "metagrossite"
        case .cameruptite: return "cameruptite"
        case .lopunnite: return "lopunnite"
        case .salamencite: return "salamencite"
        case .beedrillite: return "beedrillite"
        }
    }

    var fallbackEmoji: String { "💎" }

    /// A permanent cosmetic unlock with no growth bonus.
    static let price = 500_000_000

    var price: Int { Self.price }
}

/// Persisted overlay state for the one currently active Mega Evolution.
/// The underlying representative selection remains untouched while this exists.
struct MegaEvolutionState: Codable, Equatable, Sendable {
    let stone: MegaStone
    let isShiny: Bool

    /// The form ID is derived from the stone so old hand-edited or transferred
    /// IDs cannot make the overlay point at a different sprite.
    var megaSpeciesID: Int { stone.megaSpeciesID }
}
