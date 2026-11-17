import Foundation

extension BattlerSpec {
    /// A battler from the species' table (`SpeciesBattleTable`): its stats at `level` with these IVs and nature, its
    /// first ability unless one is given, its loop unless one is given. Nil for a species the table lacks.
    static func make(id: String, speciesID: Int, form: PokemonForm? = nil, level: Int, ivs: [Int] = Array(repeating: 31, count: 6),
                     evs: [Int] = [], nature: PokemonNature? = nil, ability: String? = nil, moves: [String]? = nil,
                     isShiny: Bool = false, isBoss: Bool = false, hpFactor: Double = 1, statFactor: Double = 1) -> BattlerSpec? {
        guard let data = SpeciesBattleTable.data(speciesID: speciesID, form: form) else { return nil }
        var stats = BattleStats.computed(base: data.baseStats, ivs: ivs, evs: evs, level: level, nature: nature, speciesID: speciesID)
        if hpFactor != 1 || statFactor != 1 { stats = stats.scaled(hp: hpFactor, stats: statFactor) }
        let loop = (moves ?? data.loop).filter { MoveTable.move($0) != nil }
        var spec = BattlerSpec(id: id, speciesID: speciesID, form: form, level: level,
                               types: PokemonTypeData.types(forSpeciesID: speciesID, form: form).isEmpty
                                   ? data.types : PokemonTypeData.types(forSpeciesID: speciesID, form: form),
                               stats: stats, hp: stats.hp, ability: ability ?? data.abilities.first?.slug,
                               moves: loop.isEmpty ? ["struggle"] : Array(loop.prefix(4)), isShiny: isShiny, isBoss: isBoss)
        spec.hiddenPowerType = BattlerSpec.hiddenPowerType(ivs: ivs)
        return spec
    }
}
