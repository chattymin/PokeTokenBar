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
}
