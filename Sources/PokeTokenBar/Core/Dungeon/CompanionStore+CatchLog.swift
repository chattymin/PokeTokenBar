import Foundation

/// A battle form the daily or weekly dungeon gave: a new form, so a line of the catch log (the owner, 2026-11-10: "vu
/// que c'est une nouvelle forme faut qu'elle soit dans le journal"). The bosses caught through their egg are Pokémon
/// like the others, in the log already; the Pokédex counts the forms apart.
struct BattleFormCatch: Sendable, Equatable, Identifiable {
    let form: BattleForm
    /// Nil for a form won before its date was kept, whose challenge left the history.
    let wonAt: Date?
    var id: String { "form:\(form.key)" }
    /// The dungeon that gave it.
    var dungeon: DungeonID { BattleForms.daily.contains(form) ? .daily : .weekly }
}

/// One line of the catch log: a Pokémon raised, or a battle form won.
enum CatchLogItem: Sendable, Equatable, Identifiable {
    case entry(DexEntry)
    case battleForm(BattleFormCatch)

    var id: String {
        switch self {
        case .entry(let entry): entry.id
        case .battleForm(let form): form.id
        }
    }
}

extension CompanionStore {
    /// The battle forms won, a line each in the catch log.
    var battleFormCatches: [BattleFormCatch] {
        let progress = state.dungeons
        return progress.battleForms.compactMap { key in
            BattleForms.form(key: key).map { BattleFormCatch(form: $0, wonAt: progress.battleFormsWonAt[key]) }
        }
    }

    /// The catch log: the Pokédex records (`filteredDexEntries`) and the battle forms won, under the same filters and
    /// sort. A form is never shiny; it stands after its species' records when they tie.
    func catchLogItems(
        query: String = "",
        rarity: Rarity? = nil,
        shinyOnly: Bool = false,
        favoritesOnly: Bool = false,
        evolutionFamily: Bool = false,
        sort: CatchLogSortOption = .recentFirst
    ) -> [CatchLogItem] {
        let entries = filteredDexEntries(query: query, rarity: rarity, shinyOnly: shinyOnly, favoritesOnly: favoritesOnly,
                                         evolutionFamily: evolutionFamily, sort: sort)
        // A battle form won is no individual: neither shiny nor liked.
        var forms = shinyOnly || favoritesOnly ? [] : battleFormCatches
        guard !forms.isEmpty else { return entries.map(CatchLogItem.entry) }
        let records = dexEntries
        // Once per form: the sort compares them often.
        let facts = Dictionary(forms.map { ($0.form.key, battleFormFacts($0.form, records: records)) },
                               uniquingKeysWith: { a, _ in a })
        func fact(_ f: BattleFormCatch) -> BattleFormFacts { facts[f.form.key] ?? battleFormFacts(f.form, records: records) }
        if let rarity { forms = forms.filter { fact($0).rarity == rarity } }
        if let matcher = DexSearchMatcher(query) {
            if evolutionFamily {
                let family = evolutionFamilySpeciesIDs(for: matcher)
                forms = forms.filter { family.contains($0.form.speciesID) }
            } else {
                forms = forms.filter { matcher.matches(speciesID: $0.form.speciesID, names: fact($0).searchNames) }
            }
        }
        func date(_ f: BattleFormCatch) -> Date { f.wonAt ?? .distantPast }
        let sorted = forms.sorted { a, b in
            switch sort {
            case .recentFirst, .countDesc: if date(a) != date(b) { return date(a) > date(b) }
            case .oldestFirst: if date(a) != date(b) { return date(a) < date(b) }
            case .numberAsc: if a.form.speciesID != b.form.speciesID { return a.form.speciesID < b.form.speciesID }
            case .numberDesc: if a.form.speciesID != b.form.speciesID { return a.form.speciesID > b.form.speciesID }
            case .nameAsc, .nameDesc:
                let order = fact(a).speciesName.localizedCompare(fact(b).speciesName)
                if order != .orderedSame { return order == (sort == .nameAsc ? .orderedAscending : .orderedDescending) }
            case .rarityDesc:
                let ra = fact(a).rarity.sortRank, rb = fact(b).rarity.sortRank
                if ra != rb { return ra > rb }
                if date(a) != date(b) { return date(a) > date(b) }
            }
            return a.form.key < b.form.key
        }
        // Whether a form stands before this record. The Pokémon raised keeps its place (first, or last oldest first);
        // a form is no duplicate, so it comes after the records counted.
        return Self.merge(entries, sorted) { form, entry in
            let wonAt = date(form), caughtAt = entry.caughtAt ?? .distantPast
            switch sort {
            case .recentFirst: return !isActiveDexEntry(entry) && wonAt > caughtAt
            case .oldestFirst: return isActiveDexEntry(entry) || wonAt < caughtAt
            case .numberAsc: return form.form.speciesID < entry.finalID
            case .numberDesc: return form.form.speciesID > entry.finalID
            case .nameAsc, .nameDesc:
                let order = fact(form).speciesName.localizedCompare(dexEntryName(entry))
                return order == (sort == .nameAsc ? .orderedAscending : .orderedDescending)
            case .rarityDesc:
                let rank = fact(form).rarity.sortRank
                return rank > entry.rarity.sortRank || (rank == entry.rarity.sortRank && wonAt > caughtAt)
            case .countDesc: return false
            }
        }
    }

    /// What a form's line shows and is found by: its species' name in the app's language, its rarity as the records
    /// show it, and its names in every language with the form's own ("Méga" finds the Megas).
    struct BattleFormFacts {
        let speciesName: String
        let rarity: Rarity
        let searchNames: [String: String]
    }

    func battleFormFacts(_ form: BattleForm, records: [DexEntry]? = nil) -> BattleFormFacts {
        let records = records ?? dexEntries
        var names = records.lazy.compactMap { $0.names?[form.speciesID] }.first ?? [:]
        let species = state.language.resolveName(names) ?? "#\(form.speciesID)"
        let rarity = records.first { $0.finalID == form.speciesID }?.rarity ?? SpeciesInfo.lineRarity(of: form.speciesID)
        names["form"] = PokemonForm.displayName(species, speciesID: form.speciesID, form: form.form, language: state.language)
        return BattleFormFacts(speciesName: species, rarity: rarity, searchNames: names)
    }

    /// The records in their order, each form slipped in before the first record it goes before. Both lists are sorted
    /// on the same key, so a form that goes before a record goes before every one after it.
    static func merge(_ entries: [DexEntry], _ forms: [BattleFormCatch],
                      before: (BattleFormCatch, DexEntry) -> Bool) -> [CatchLogItem] {
        var items: [CatchLogItem] = []
        items.reserveCapacity(entries.count + forms.count)
        var left = forms[...]
        for entry in entries {
            while let form = left.first, before(form, entry) {
                items.append(.battleForm(form))
                left = left.dropFirst()
            }
            items.append(.entry(entry))
        }
        items += left.map(CatchLogItem.battleForm)
        return items
    }
}
