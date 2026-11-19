import Foundation

/// An individual's appearance within a species: Unown's letter, Shaymin's Sky Forme, Shellos's sea.
///
/// The value belongs to the individual and is resolved per species of its line, so a Sandy Burmy
/// becomes a Sandy Wormadam while the Mothim branch keeps Mothim's single appearance. Species IDs
/// and evolution paths are unchanged; the form only selects sprites, names and collection slots.
struct PokemonForm: RawRepresentable, Codable, Hashable, Sendable {
    let rawValue: String

    init(rawValue: String) { self.rawValue = rawValue }
    init(_ rawValue: String) { self.rawValue = rawValue }

    static let unownSpeciesID = 201

    /// Unown shows its letter instead of a localized form name.
    var symbol: String {
        switch rawValue {
        case "exclamation": return "!"
        case "question": return "?"
        default: return rawValue.uppercased()
        }
    }

    // MARK: Catalog

    /// Where a form's animated GIF lives on the PokeAPI sprites repository.
    enum AnimatedSource: Sendable {
        /// Gen V Black/White, named like the cache (`492-sky.gif`). Every regular form is here.
        case blackWhite
        /// Showdown, named by the variety id (`10196.gif`). Gen V never had Gigantamax, so its
        /// animation only exists here. Back GIFs are missing for some (10195, 10197); the existing
        /// 404 back-to-front fallback covers them.
        case showdown
    }

    /// Form names the app localizes itself, for forms whose PokéAPI `form_names` miss most of the
    /// app's languages (Gigantamax: only en/ja/fr/de, so ko/es/pt/ru would fall back to English).
    enum AppLabel: Sendable {
        case gigantamax
    }

    /// `pokemonID` is the PokéAPI variety whose static PNG holds this form (`10006.png` for Sky
    /// Shaymin); nil means the static sprite is named like the animated one (`412-sandy.png`).
    /// `formID` is the PokéAPI `pokemon-form` resource that carries the localized form names.
    /// `isFactor` marks an individual trait with its own odds (`uncollectedFactorDenominator`,
    /// `collectedFactorDenominator`) instead of the regular form weighting, like the Gigantamax Factor.
    struct Entry: Sendable {
        let form: PokemonForm
        let formID: Int
        let pokemonID: Int?
        let isFactor: Bool
        let animatedSource: AnimatedSource
        let appLabel: AppLabel?

        init(_ rawValue: String, formID: Int, pokemonID: Int? = nil, isFactor: Bool = false,
             animatedSource: AnimatedSource = .blackWhite, appLabel: AppLabel? = nil) {
            form = PokemonForm(rawValue)
            self.formID = formID
            self.pokemonID = pokemonID
            self.isFactor = isFactor
            self.animatedSource = animatedSource
            self.appLabel = appLabel
        }

        /// Gigantamax is a rare factor of the individual, animated only on Showdown and labelled by the app.
        static func gigantamax(formID: Int, pokemonID: Int) -> Entry {
            Entry("gmax", formID: formID, pokemonID: pokemonID, isFactor: true, animatedSource: .showdown,
                  appLabel: .gigantamax)
        }
    }

    /// Every catalogued species lists its default appearance first; that one keeps the plain
    /// `<id>.png`/`<id>.gif` sprites. Only forms with an animated sprite are listed: Gen V for
    /// regular forms (the same source that bounds hatchable species), Showdown for Gigantamax.
    /// Gender differences are not forms.
    static let catalog: [Int: [Entry]] = {
        let letters = "abcdefghijklmnopqrstuvwxyz".map(String.init) + ["exclamation", "question"]
        let unown = letters.enumerated().map { index, letter in
            Entry(letter, formID: index == 0 ? unownSpeciesID : 10000 + index)
        }
        // Species id → (pokemon-form id, variety id) of its Gigantamax form, Gen 1–5 only.
        // The default form is named `normal`: PokéAPI's default form of these species has no name.
        let gigantamax: [Int: (formID: Int, pokemonID: Int)] = [
            3: (10364, 10195), 6: (10365, 10196), 9: (10366, 10197), 12: (10367, 10198), 25: (10368, 10199),
            52: (10369, 10200), 68: (10370, 10201), 94: (10371, 10202), 99: (10372, 10203),
            131: (10373, 10204), 133: (10374, 10205), 143: (10375, 10206), 569: (10376, 10207),
        ]
        var catalog: [Int: [Entry]] = [
            unownSpeciesID: unown,
            351: [.init("normal", formID: 351), .init("sunny", formID: 10028, pokemonID: 10013),
                  .init("rainy", formID: 10029, pokemonID: 10014), .init("snowy", formID: 10030, pokemonID: 10015)],
            386: [.init("normal", formID: 386), .init("attack", formID: 10031, pokemonID: 10001),
                  .init("defense", formID: 10032, pokemonID: 10002), .init("speed", formID: 10033, pokemonID: 10003)],
            412: [.init("plant", formID: 412), .init("sandy", formID: 10034), .init("trash", formID: 10035)],
            413: [.init("plant", formID: 413), .init("sandy", formID: 10036, pokemonID: 10004),
                  .init("trash", formID: 10037, pokemonID: 10005)],
            421: [.init("overcast", formID: 421), .init("sunshine", formID: 10038)],
            422: [.init("west", formID: 422), .init("east", formID: 10039)],
            423: [.init("west", formID: 423), .init("east", formID: 10040)],
            479: [.init("normal", formID: 479), .init("heat", formID: 10058, pokemonID: 10008),
                  .init("wash", formID: 10059, pokemonID: 10009), .init("frost", formID: 10060, pokemonID: 10010),
                  .init("fan", formID: 10061, pokemonID: 10011), .init("mow", formID: 10062, pokemonID: 10012)],
            487: [.init("altered", formID: 487), .init("origin", formID: 10063, pokemonID: 10007)],
            492: [.init("land", formID: 492), .init("sky", formID: 10064, pokemonID: 10006)],
            493: [.init("normal", formID: 493), .init("fighting", formID: 10045), .init("flying", formID: 10047),
                  .init("poison", formID: 10052), .init("ground", formID: 10050), .init("rock", formID: 10054),
                  .init("bug", formID: 10041), .init("ghost", formID: 10048), .init("steel", formID: 10055),
                  .init("fire", formID: 10046), .init("water", formID: 10056), .init("grass", formID: 10049),
                  .init("electric", formID: 10044), .init("psychic", formID: 10053), .init("ice", formID: 10051),
                  .init("dragon", formID: 10043), .init("dark", formID: 10042), .init("fairy", formID: 10085)],
            550: [.init("red-striped", formID: 550), .init("blue-striped", formID: 10066, pokemonID: 10016)],
            555: [.init("standard", formID: 555), .init("zen", formID: 10067, pokemonID: 10017)],
            585: [.init("spring", formID: 585), .init("summer", formID: 10068),
                  .init("autumn", formID: 10069), .init("winter", formID: 10070)],
            586: [.init("spring", formID: 586), .init("summer", formID: 10071),
                  .init("autumn", formID: 10072), .init("winter", formID: 10073)],
            641: [.init("incarnate", formID: 641), .init("therian", formID: 10079, pokemonID: 10019)],
            642: [.init("incarnate", formID: 642), .init("therian", formID: 10080, pokemonID: 10020)],
            645: [.init("incarnate", formID: 645), .init("therian", formID: 10081, pokemonID: 10021)],
            646: [.init("normal", formID: 646), .init("black", formID: 10082, pokemonID: 10022),
                  .init("white", formID: 10083, pokemonID: 10023)],
            647: [.init("ordinary", formID: 647), .init("resolute", formID: 10084, pokemonID: 10024)],
            648: [.init("aria", formID: 648), .init("pirouette", formID: 10074, pokemonID: 10018)],
            649: [.init("normal", formID: 649), .init("douse", formID: 10075), .init("shock", formID: 10076),
                  .init("burn", formID: 10077), .init("chill", formID: 10078)],
        ]
        // Appended after any regular forms, so a species with both keeps its own default first.
        for (speciesID, ids) in gigantamax {
            catalog[speciesID, default: [Entry("normal", formID: speciesID)]]
                .append(.gigantamax(formID: ids.formID, pokemonID: ids.pokemonID))
        }
        return catalog
    }()

    /// Catalogued species whose line starts elsewhere. The individual's form is chosen at hatch,
    /// so Cherubi and Darumaka eggs already know which Cherrim or Darmanitan they will become.
    /// The base is the species PokéAPI lists without `evolves_from`, like the hatch index: Pichu for
    /// Pikachu and Munchlax for Snorlax. Meowth, Lapras and Eevee are their own bases.
    private static let lineBaseIDs: [Int: Int] = [
        413: 412, 421: 420, 423: 422, 555: 554, 586: 585,
        3: 1, 6: 4, 9: 7, 12: 10, 25: 172, 68: 66, 94: 92, 99: 98, 143: 446, 569: 568,
    ]

    static func entries(speciesID: Int) -> [Entry] { catalog[speciesID] ?? [] }

    /// The species' forms, default first. Empty when the species has a single appearance.
    static func forms(speciesID: Int) -> [PokemonForm] { entries(speciesID: speciesID).map(\.form) }

    static func hasForms(speciesID: Int) -> Bool { catalog[speciesID] != nil }

    /// Species whose only other looks are factors such as Gigantamax (Charizard, Pikachu…): their
    /// default is the usual species look, not one form among several.
    static func hasOnlyFactorForms(speciesID: Int) -> Bool {
        let others = entries(speciesID: speciesID).dropFirst()
        return !others.isEmpty && others.allSatisfy(\.isFactor)
    }

    /// Species of the line that change appearance with the individual's form, in line order.
    static func formSpecies(baseID: Int) -> [Int] {
        catalog.keys.filter { (lineBaseIDs[$0] ?? $0) == baseID }.sorted()
    }

    /// Everything an individual of this line can carry, default first.
    static func lineForms(baseID: Int) -> [PokemonForm] {
        var seen = Set<PokemonForm>()
        return formSpecies(baseID: baseID).flatMap(forms(speciesID:)).filter { seen.insert($0).inserted }
    }

    /// The appearance of an individual at one species: its own form when that species has it,
    /// otherwise the species default. Nil for species without forms.
    static func resolved(speciesID: Int, form: PokemonForm?) -> PokemonForm? {
        let forms = forms(speciesID: speciesID)
        guard let first = forms.first else { return nil }
        return form.flatMap { forms.contains($0) ? $0 : nil } ?? first
    }

    /// Normalizes the form an individual stores: nil for lines without forms, and the line default
    /// for records written before this line had forms (older Unown saves keep their A).
    static func resolved(baseID: Int, form: PokemonForm?) -> PokemonForm? {
        let forms = lineForms(baseID: baseID)
        guard let first = forms.first else { return nil }
        return form.flatMap { forms.contains($0) ? $0 : nil } ?? first
    }

    static func isDefault(_ form: PokemonForm?, speciesID: Int) -> Bool {
        forms(speciesID: speciesID).first == resolved(speciesID: speciesID, form: form)
    }

    static func sortOrder(_ form: PokemonForm?, speciesID: Int) -> Int {
        guard let form else { return 0 }
        return forms(speciesID: speciesID).firstIndex(of: form) ?? 0
    }

    /// Odds of a factor form such as Gigantamax. Both are rarer than a regular form (which the
    /// collection weighting hands out about every other hatch in a two-form line) and more common
    /// than a shiny (1/64). Like `CollectionWeight`, the chance doubles while the line's factor is
    /// still missing from the collection, so players get the appearance they do not have yet sooner,
    /// and halves once it is owned. The maintainer may tune both; they only change how often
    /// factor lines hit.
    static let uncollectedFactorDenominator: UInt64 = 8
    static let collectedFactorDenominator: UInt64 = 16

    /// Forms of the line that are factor traits rather than collection-weighted forms.
    static func factorForms(baseID: Int) -> Set<PokemonForm> {
        Set(formSpecies(baseID: baseID).flatMap { entries(speciesID: $0).filter(\.isFactor).map(\.form) })
    }

    /// Chosen only after the species roll, from one random value so a hatch consumes a single draw.
    /// A line with factor forms first spends `roll % denominator`: zero picks a factor. The
    /// denominator is 8 while any factor of the line is uncollected and 16 once all are. Otherwise
    /// the remaining bits pick among the other forms, where uncollected forms weigh 2 and collected
    /// forms weigh 1.
    static func roll(_ roll: UInt64, among forms: [PokemonForm], factors: Set<PokemonForm> = [],
                     collected: Set<PokemonForm>) -> PokemonForm {
        let factorForms = forms.filter(factors.contains)
        let regular = forms.filter { !factors.contains($0) }
        var roll = roll
        if !factorForms.isEmpty {
            let denominator = factorForms.allSatisfy(collected.contains)
                ? collectedFactorDenominator : uncollectedFactorDenominator
            let factorHit = roll % denominator == 0
            roll /= denominator
            if factorHit { return factorForms[Int(roll % UInt64(factorForms.count))] }
        }
        let weights = regular.map { CollectionWeight.adjusted(2, isCollected: collected.contains($0)) }
        var remaining = Int(roll % UInt64(weights.reduce(0, +)))
        for (form, weight) in zip(regular.dropLast(), weights) {
            remaining -= weight
            if remaining < 0 { return form }
        }
        // Any remaining roll belongs to the last form. A line always has a regular form: the
        // catalog's defaults are never factors.
        return regular.last!
    }

    // MARK: Sprites and names

    /// Animated GIFs and cache files use `<id>-<form>`; the default keeps the plain `<id>` names
    /// (and so the cache keys of saves written before forms existed).
    static func assetName(speciesID: Int, form: PokemonForm?) -> String {
        guard let form = resolved(speciesID: speciesID, form: form), !isDefault(form, speciesID: speciesID) else {
            return String(speciesID)
        }
        return "\(speciesID)-\(form.rawValue)"
    }

    /// The catalog entry of the form this species shows. Nil for species without forms.
    static func entry(speciesID: Int, form: PokemonForm?) -> Entry? {
        let resolved = resolved(speciesID: speciesID, form: form)
        return entries(speciesID: speciesID).first { $0.form == resolved }
    }

    /// Static PNGs of forms that are separate PokéAPI varieties live under the variety id.
    static func staticAssetName(speciesID: Int, form: PokemonForm?) -> String {
        if let pokemonID = entry(speciesID: speciesID, form: form)?.pokemonID { return String(pokemonID) }
        return assetName(speciesID: speciesID, form: form)
    }

    /// Folder (under `sprites/pokemon/`) and file name of the animated GIF. Showdown names files by
    /// the variety id; the cache still uses `assetName` (`6-gmax`), so cache keys do not depend on it.
    static func animatedAsset(speciesID: Int, form: PokemonForm?) -> (folder: String, name: String) {
        let entry = entry(speciesID: speciesID, form: form)
        if entry?.animatedSource == .showdown, let pokemonID = entry?.pokemonID {
            return ("other/showdown/", String(pokemonID))
        }
        return ("versions/generation-v/black-white/animated/", assetName(speciesID: speciesID, form: form))
    }

    /// PokéAPI `pokemon-form` id holding the localized form names. Nil for species without forms.
    static func formID(speciesID: Int, form: PokemonForm?) -> Int? {
        entry(speciesID: speciesID, form: form)?.formID
    }

    /// Unown always names its letter; other species name only a non-default form.
    static func displayName(_ name: String, speciesID: Int, form: PokemonForm?, label: String?) -> String {
        guard let form = resolved(speciesID: speciesID, form: form) else { return name }
        if speciesID == unownSpeciesID { return "\(name) [\(form.symbol)]" }
        guard !isDefault(form, speciesID: speciesID), let label, !label.isEmpty else { return name }
        return "\(name) [\(label)]"
    }
}

extension PokemonForm {
    private struct StoredKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    /// Reads the first present key; saves written before other species had forms used `unownForm`.
    /// Malformed values read as nil so the caller's resolution falls back to the default form.
    static func decoded(from decoder: Decoder, keys: String...) -> PokemonForm? {
        guard let c = try? decoder.container(keyedBy: StoredKey.self) else { return nil }
        for key in keys {
            if let form = try? c.decodeIfPresent(PokemonForm.self, forKey: StoredKey(stringValue: key)) {
                return form
            }
        }
        return nil
    }
}

extension PokemonForm {
    /// Castform, Rotom, Kyurem and Genesect have no official name for their usual look:
    /// PokéAPI only says "Forme de Motisma" or nothing at all. The same goes for species whose only
    /// other look is a factor such as Gigantamax: PokéAPI's default form of Charizard or Pikachu has
    /// an empty `form_name` and no `form_names`.
    private static let unnamedDefaultSpecies: Set<Int> = Set([351, 479, 646, 649]).union(
        catalog.keys.filter(hasOnlyFactorForms(speciesID:))
    )

    private static func hasUnnamedDefault(speciesID: Int, form: PokemonForm?) -> Bool {
        unnamedDefaultSpecies.contains(speciesID) && isDefault(form, speciesID: speciesID)
    }

    /// PokéAPI resource with the localized name of the form this species shows.
    /// Unown, the unnamed usual looks and forms the app labels itself need none.
    static func nameResource(speciesID: Int, form: PokemonForm?) -> PokemonNameResource? {
        guard speciesID != unownSpeciesID, !hasUnnamedDefault(speciesID: speciesID, form: form),
              let entry = entry(speciesID: speciesID, form: form), entry.appLabel == nil else { return nil }
        return PokemonNameResource(kind: .pokemonForm, name: String(entry.formID))
    }

    /// Every form of the species, for pickers that label all of them.
    static func nameResources(speciesID: Int) -> [PokemonNameResource] {
        forms(speciesID: speciesID).compactMap { nameResource(speciesID: speciesID, form: $0) }
    }

    /// Localized form name ("Forme Céleste"), Unown's letter, or the identifier until PokéAPI answers.
    /// Nil for species without forms.
    @MainActor
    static func label(speciesID: Int, form: PokemonForm?, language: AppLanguage,
                      names: PokemonNameDisplayStore = .shared) -> String? {
        guard let form = resolved(speciesID: speciesID, form: form) else { return nil }
        if speciesID == unownSpeciesID { return form.symbol }
        if hasUnnamedDefault(speciesID: speciesID, form: form) { return L(language).normalForm }
        switch entry(speciesID: speciesID, form: form)?.appLabel {
        case .gigantamax: return L(language).gigantamaxForm
        case nil: break
        }
        let translations = nameResource(speciesID: speciesID, form: form).flatMap { names.names[$0] }
        return translations.flatMap(language.resolveName) ?? PokemonNameLocalization.identifier(form.rawValue)
    }

    @MainActor
    static func displayName(_ name: String, speciesID: Int, form: PokemonForm?, language: AppLanguage) -> String {
        displayName(name, speciesID: speciesID, form: form,
                    label: label(speciesID: speciesID, form: form, language: language))
    }
}
