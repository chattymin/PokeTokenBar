import Foundation

/// A costumed Pokémon of Pokémon GO (the owner, 2026-11-13: "la collection qui se renouvelle"): a species, its form
/// when the costume is on one, and the costume's code (`HOLIDAY_2016`), back each year in its month
/// (`Costumes.generated.swift`, from PokeMiners).
struct CostumeEntry: Sendable, Hashable {
    let code: String
    let speciesID: Int
    /// Its form at that species (a Galarian Zigzagoon, a small Pumpkaboo); nil for the species' usual look.
    let form: PokemonForm?
    let month: Int

    init(_ code: String, _ speciesID: Int, form: String? = nil, month: Int) {
        self.code = code
        self.speciesID = speciesID
        self.form = form.map { PokemonForm($0) }
        self.month = month
    }

    /// Pokémon GO's "can't evolve" costumes: each stays at its stage, a lot of its own.
    var evolves: Bool { !code.hasSuffix("_NOEVOLVE") }

    /// What a Pokédex record of it is known by: `HOLIDAY_2016:172`, `FALL_2022:710:small`.
    var key: String { CostumeCatalog.key(code: code, speciesID: speciesID, form: form) }

    /// The look its sprites show (`CostumeCatalog.displayForm`).
    var displayForm: PokemonForm { CostumeCatalog.displayForm(code: code, form: form) }
}

/// The costumes and their months, the lot of each month, how a costumed Pokémon grows, and its images.
enum CostumeCatalog {
    /// One Costume Egg every 300M tokens used (the owner's pick, 2026-11-13).
    static let tokensPerEgg = 300_000_000

    static let byKey: [String: CostumeEntry] = Dictionary(entries.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })

    static func key(code: String, speciesID: Int, form: PokemonForm?) -> String {
        form.map { "\(code):\(speciesID):\($0.rawValue)" } ?? "\(code):\(speciesID)"
    }

    /// The costume `code` at this species, in this form: an entry without a form matches the species' usual look.
    static func entry(code: String, speciesID: Int, form: PokemonForm?) -> CostumeEntry? {
        let own = PokemonForm.resolved(speciesID: speciesID, form: form)
        if let own, !PokemonForm.isDefault(own, speciesID: speciesID) {
            return byKey[key(code: code, speciesID: speciesID, form: own)]
        }
        // The usual look: written without a form, or with the default spelled out (a Pumpkaboo's average size).
        return byKey[key(code: code, speciesID: speciesID, form: nil)]
            ?? own.flatMap { byKey[key(code: code, speciesID: speciesID, form: $0)] }
    }

    /// The month's lot, in the catalog's order.
    static func lot(month: Int) -> [CostumeEntry] { entries.filter { $0.month == month } }

    /// The stages that wear the same costume one evolution on, in the same form; none for a "can't evolve" costume.
    static func children(of entry: CostumeEntry) -> [CostumeEntry] {
        guard entry.evolves else { return [] }
        return entries.filter { other in
            other.code == entry.code && other.form == entry.form
                && SpeciesInfo.all[other.speciesID]?.evolvesFrom == entry.speciesID
        }
    }

    /// What a Costume Egg can hold: the first stage wearing each costume of the month (a Pichu for the Pichu, Pikachu
    /// and Raichu in the same hat), each "can't evolve" one alone.
    static func starts(month: Int) -> [CostumeEntry] {
        lot(month: month).filter { entry in
            guard entry.evolves, let parent = SpeciesInfo.all[entry.speciesID]?.evolvesFrom else { return true }
            return byKey[key(code: entry.code, speciesID: parent, form: entry.form)] == nil
        }
    }

    /// The stages of a chain wearing the costume `code`, in this line form.
    static func stages(code: String, chain: some Sequence<Int>, form: PokemonForm?) -> [CostumeEntry] {
        chain.compactMap { entry(code: code, speciesID: $0, form: form) }
    }

    /// The entry and every stage it may grow into wearing its costume.
    static func family(of start: CostumeEntry) -> [CostumeEntry] {
        [start] + children(of: start).flatMap(family)
    }

    /// The month of a day (`yyyy-MM-dd`), its event's: the egg earned that day holds that month's lot.
    static func month(ofDay day: String) -> Int? {
        let parts = day.split(separator: "-")
        guard parts.count == 3, let month = Int(parts[1]), (1...12).contains(month) else { return nil }
        return month
    }

    // MARK: Images

    /// A costume's look passed to the sprite views only, never stored as a form: `costume.HOLIDAY_2016`, or
    /// `costume.FALL_2022.small` with its form.
    static func displayForm(code: String, form: PokemonForm?) -> PokemonForm {
        PokemonForm("costume.\(code)" + (form.map { ".\($0.rawValue)" } ?? ""))
    }

    /// The costume and form a display form carries, nil for any other form.
    static func parse(_ form: PokemonForm?) -> (code: String, form: PokemonForm?)? {
        guard let raw = form?.rawValue, raw.hasPrefix("costume.") else { return nil }
        let parts = raw.dropFirst("costume.".count).split(separator: ".", maxSplits: 1).map(String.init)
        guard let code = parts.first, !code.isEmpty else { return nil }
        return (code, parts.count > 1 ? PokemonForm(parts[1]) : nil)
    }

    /// PokeMiners' 256 px icon of a costumed Pokémon, its shiny's with `.s`: a still, never animated.
    static func spriteURL(speciesID: Int, display: PokemonForm?, shiny: Bool) -> URL? {
        guard let look = parse(display) else { return nil }
        let entry = entry(code: look.code, speciesID: speciesID, form: look.form)
        let formPart = entry?.form.flatMap { PokeMinersForm.code(for: $0) }.map { ".f\($0)" } ?? ""
        let name = "pm\(speciesID)\(formPart).c\(look.code)\(shiny ? ".s" : "").icon.png"
        return URL(string: "https://raw.githubusercontent.com/PokeMiners/pogo_assets/master/Images/"
            + "Pokemon%20-%20256x256/Addressable%20Assets/" + name)
    }
}

/// PokeMiners' names of the forms costumes are on, the inverse of `scripts/generate-costumes.py`'s `FORMS`.
enum PokeMinersForm {
    static func code(for form: PokemonForm) -> String? {
        ["galar": "GALARIAN", "average": "AVERAGE", "small": "SMALL", "large": "LARGE", "super": "SUPER"][form.rawValue]
    }
}

/// A Costume Egg of the Bag: its content fixed when earned, the first stage of one of its month's costumes
/// (`CompanionStore.earnCostumeEggs`); shiny or not is drawn at the hatch, as any egg's.
struct CostumeEgg: Codable, Sendable, Equatable, Identifiable {
    var id: String
    var code: String
    var speciesID: Int
    var form: PokemonForm?
    var month: Int

    var entry: CostumeEntry? { CostumeCatalog.entry(code: code, speciesID: speciesID, form: form) }
}

/// The costumed collection's two medals (the owner, 2026-11-13: "OK pour ta proposition"): a step at 25, 50, 100
/// costumed Pokémon and all of them, and a step at each monthly lot completed. Their goals count stand-in ids, one per
/// costume or month (`CompanionStore.regionTiers`), as the Battle Forms Medal counts its forms' varieties.
enum CostumeMedals {
    static let steps = [25, 50, 100, CostumeCatalog.entries.count]

    /// A costume's stand-in id in the medal's goal, a month's in the lots medal's.
    static func id(_ entry: CostumeEntry) -> Int { 900_000 + (CostumeCatalog.entries.firstIndex(of: entry) ?? 0) }
    static func lotID(_ month: Int) -> Int { 910_000 + month }

    static let goals: [(generation: Int, goal: SpeciesGoal)] = steps.enumerated().map {
        ($0.offset + 1, SpeciesGoal(CostumeCatalog.entries.map(id), needed: $0.element))
    }
    static let lotGoals: [(generation: Int, goal: SpeciesGoal)] = (1...12).map {
        ($0, SpeciesGoal((1...12).map(lotID), needed: $0))
    }

    /// Rare Eggs and Rare Candies, more at each step, a Legendary Egg for the whole collection.
    static func rewards(step: Int) -> [(kind: ItemKind, count: Int)] {
        switch step {
        case 1: [(.rareEgg, 1), (.rareCandy, 3)]
        case 2: [(.rareEgg, 2), (.rareCandy, 5)]
        case 3: [(.rareEgg, 3), (.rareCandy, 8)]
        default: [(.legendaryEgg, 1), (.rareCandy, 10)]
        }
    }

    /// A Rare Egg and two Rare Candies a lot completed, a Legendary Egg for the twelfth.
    static func lotRewards(step: Int) -> [(kind: ItemKind, count: Int)] {
        step >= 12 ? [(.legendaryEgg, 1), (.rareCandy, 5)] : [(.rareEgg, 1), (.rareCandy, 2)]
    }
}
