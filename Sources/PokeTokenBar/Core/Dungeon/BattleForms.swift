import Foundation

/// The battle forms (validated by the owner on 2026-11-02): Mega Evolutions, Primal Reversions and Gigantamax forms, won
/// in the daily and weekly dungeons and never used up. Once won, one is in the Pokédex with the species' other forms,
/// counts toward every form, and any graduated Pokémon of its species can take it in a dungeon. None hatches from an
/// egg: they stay out of `PokemonForm.catalog`, whose forms eggs roll.
enum BattleFormKind: String, Codable, Sendable {
    case mega, gigantamax, primal
    /// Giovanni's armored Mewtwo, from Team Rocket's chest (the owner, 2026-11-17): a Mega's ×1.25, and perfect IVs and
    /// EVs whatever the Mewtwo wearing it (`DungeonTeamBuilder.spec`).
    case armor

    /// What a player's Pokémon gains in this form (the owner, 2026-11-12: "x1.25 sur toutes les stats des méga vu
    /// qu'ils sont méga"): a Mega or a Primal, already 100 base stats higher, every stat ×1.25; a Gigantamax, at its
    /// Pokémon's own base stats, its HP doubled as the games' Dynamax and the rest ×1.25. The challenges' bosses keep
    /// their own tuning (`ExpeditionEngine.challengeFactors`).
    var playerFactors: (hp: Double, stats: Double) {
        switch self {
        case .mega, .primal, .armor: (1.25, 1.25)
        case .gigantamax: (2, 1.25)
        }
    }
}

struct BattleForm: Hashable, Sendable {
    /// The PokéAPI variety: its sprites and its battle data (`SpeciesBattleTable`).
    let pokemonID: Int
    let speciesID: Int
    let form: PokemonForm
    /// The PokéAPI `pokemon-form` holding its localized names.
    let formID: Int
    let kind: BattleFormKind
    let isLegendary: Bool
    /// Whether Showdown has its GIF; without one, the still stays (the Mega Evolutions of Legends Z-A).
    let isAnimated: Bool

    /// How a won form is kept in the save (`DungeonProgress.battleForms`).
    var key: String { "\(speciesID)-\(form.rawValue)" }
}

enum BattleForms {
    /// Every battle form PokéAPI shows a sprite for, in its order (`BattleForms.generated.swift`).
    static let all: [BattleForm] = table.split(separator: "\n").compactMap { line in
        let f = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard f.count == 7, let pokemonID = Int(f[0]), let speciesID = Int(f[1]), let formID = Int(f[3]),
              let kind = BattleFormKind(rawValue: f[4]) else { return nil }
        return BattleForm(pokemonID: pokemonID, speciesID: speciesID, form: PokemonForm(f[2]), formID: formID, kind: kind,
                          isLegendary: f[5] == "1", isAnimated: f[6] == "1")
    }

    /// The forms PokéAPI has not: Giovanni's armored Mewtwo, worn as a battle form but outside the catalog's counts, the
    /// challenges' bosses and the Battle Forms Medal (`all`).
    static let extras: [BattleForm] = [ArmoredMewtwo.battleForm]

    private static let bySpecies: [Int: [BattleForm]] = Dictionary(grouping: all + extras, by: \.speciesID)
    private static let byKey: [String: BattleForm] = Dictionary((all + extras).map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })

    static func forms(speciesID: Int) -> [BattleForm] { bySpecies[speciesID] ?? [] }

    static func form(speciesID: Int, form: PokemonForm?) -> BattleForm? {
        guard let form else { return nil }
        return byKey["\(speciesID)-\(form.rawValue)"]
    }

    static func form(key: String) -> BattleForm? { byKey[key] }

    /// The daily dungeon's bosses: the Mega Evolutions of species that are neither legendary nor mythical.
    static let daily: [BattleForm] = all.filter { $0.kind == .mega && !$0.isLegendary }

    /// The weekly dungeon's: every Gigantamax and Primal form, and the legendary and mythical Megas.
    static let weekly: [BattleForm] = all.filter { $0.kind != .mega || $0.isLegendary }
}
