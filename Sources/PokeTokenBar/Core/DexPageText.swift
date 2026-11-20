import Foundation

/// The Pokédex page's tabs, under its identity and evolution line (#183).
extension L {
    var dexTabIndividual: String { t("개체", "Individual", "個体", "Ejemplar", "Individu", "Indivíduo", "Individuum", "Особь") }
    var dexTabBattle: String { t("배틀", "Battle", "バトル", "Combate", "Combat", "Batalha", "Kampf", "Бой") }
    var dexTabSpecies: String { t("종", "Species", "種", "Especie", "Espèce", "Espécie", "Art", "Вид") }
    var dexTabMoves: String { t("기술", "Moves", "技", "Movimientos", "Attaques", "Golpes", "Attacken", "Приёмы") }
    var dexTabCostumes: String { t("코스튬", "Costumes", "コスチューム", "Disfraces", "Costumes", "Fantasias", "Kostüme", "Костюмы") }
}

/// The catch log's dates, said in full on each card (#183): "17 nov. à 16:18" did not say what it was.
extension L {
    func logGraduatedOn(_ date: String) -> String {
        t("\(date) 졸업", "Graduated \(date)", "\(date) 卒業", "Graduado el \(date)", "Diplômé le \(date)", "Formado em \(date)",
          "Verabschiedet am \(date)", "Выпущен \(date)")
    }

    func logHatchedOn(_ date: String) -> String {
        t("\(date) 부화", "Hatched \(date)", "\(date) 孵化", "Eclosionado el \(date)", "Éclos le \(date)", "Chocou em \(date)",
          "Geschlüpft am \(date)", "Вылупился \(date)")
    }

    func logReleasedOn(_ date: String) -> String {
        t("\(date) 놓아줌", "Released \(date)", "\(date) 逃がした", "Liberado el \(date)", "Relâché le \(date)", "Solto em \(date)",
          "Freigelassen am \(date)", "Отпущен \(date)")
    }

    /// A one-region dungeon's region filter (the owner, 2026-11-20): every region.
    var dexRegionAll: String {
        t("모든 지방", "Every region", "すべての地方", "Todas las regiones", "Toutes les régions", "Todas as regiões",
          "Alle Regionen", "Все регионы")
    }

    var dexRegionFilter: String {
        t("지방으로 거르기: 포켓몬을 고르면 그 지방이 돼요", "Filter by region: picking a Pokémon sets its own",
          "地方で絞り込む：ポケモンを選ぶとその地方になります", "Filtrar por región: elegir un Pokémon pone la suya",
          "Filtrer par région : choisir un Pokémon met la sienne", "Filtrar por região: escolher um Pokémon põe a dele",
          "Nach Region filtern: Ein gewähltes Pokémon setzt seine", "Фильтр по региону: выбранный покемон задаёт свой")
    }
}
