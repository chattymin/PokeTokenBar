import Foundation

/// The Collection's statistics screen (`CollectionStatsScreen`), beside the usage Stats page (`StatsText`).
extension L {
    var dexStatsTitle: String {
        t("도감 통계", "Collection stats", "ずかんのとうけい", "Estadísticas de la colección", "Stats de la collection",
          "Estatísticas da coleção", "Sammlungsstatistik", "Статистика коллекции")
    }
    var dexStatsButtonHint: String {
        t("도감 통계: 이룬 것과 남은 것", "Collection statistics: what is done and what is left",
          "ずかんのとうけい：できたこと、のこっていること", "Estadísticas de la colección: lo hecho y lo que falta",
          "Statistiques de la collection : ce qui est fait et ce qui reste",
          "Estatísticas da coleção: o que já foi feito e o que falta",
          "Sammlungsstatistik: Was geschafft ist und was fehlt", "Статистика коллекции: что сделано и что осталось")
    }
    var dexStatsSpecies: String { t("종", "Species", "しゅるい", "Especies", "Espèces", "Espécies", "Arten", "Виды") }
    var dexStatsForms: String { t("모습", "Forms", "すがた", "Formas", "Formes", "Formas", "Formen", "Формы") }
    var dexStatsLines: String { t("계열", "Lines", "けいとう", "Líneas", "Lignées", "Linhas", "Linien", "Линии") }
    var dexStatsShinies: String {
        t("이로치", "Shinies", "いろちがい", "Variocolores", "Chromatiques", "Brilhantes", "Schillernde", "Шайни")
    }
    var dexStatsMapTitle: String {
        t("지도: 세대 × 타입", "Map: generation × type", "マップ：せだい × タイプ", "Mapa: generación × tipo",
          "Carte : génération × type", "Mapa: geração × tipo", "Karte: Generation × Typ", "Карта: поколение × тип")
    }
    var dexStatsMapHint: String {
        t("칸마다 남은 수, 다 모으면 ✓. 누르면 어떤 포켓몬인지 보여요.",
          "Each cell: how many are left, ✓ once all are there. Click to see which.",
          "マスごとにのこりの数、ぜんぶそろうと ✓。クリックでどのポケモンか見られます。",
          "Cada casilla: cuántos faltan, ✓ cuando están todos. Haz clic para ver cuáles.",
          "Chaque case : combien il en manque, ✓ quand tout y est. Un clic montre lesquels.",
          "Cada casa: quantos faltam, ✓ quando estão todos. Clique para ver quais.",
          "Jedes Feld: wie viele fehlen, ✓ wenn alle da sind. Klicke, um zu sehen, welche.",
          "В каждой клетке: сколько осталось, ✓ когда собраны все. Нажмите, чтобы увидеть, какие.")
    }
    var dexStatsCategories: String {
        t("분류", "Categories", "ぶんるい", "Categorías", "Catégories", "Categorias", "Kategorien", "Категории")
    }
    var dexStatsAlmostDone: String {
        t("거의 다 모음", "Almost done", "もうすこし", "Casi terminado", "Presque fini", "Quase lá", "Fast geschafft",
          "Почти готово")
    }
    var dexStatsAllThere: String {
        t("다 모았어요", "All there", "ぜんぶそろった", "Están todos", "Tout y est", "Estão todos", "Alle da", "Все собраны")
    }
    func dexStatsLeft(_ n: Int) -> String {
        t("\(n)마리 남음", "\(n) left", "のこり\(n)", "Faltan \(n)", "Plus que \(n)", "Faltam \(n)", "Noch \(n)",
          "Осталось: \(n)")
    }
    func dexStatsGeneration(_ n: Int) -> String {
        t("\(n)세대", "Generation \(n)", "だい\(n)せだい", "Generación \(n)", "Génération \(n)", "Geração \(n)",
          "Generation \(n)", "Поколение \(n)")
    }
    func dexStatsGenerationShort(_ n: Int) -> String { t("\(n)세", "G\(n)", "\(n)世", "G\(n)", "G\(n)", "G\(n)", "G\(n)", "П\(n)") }
    func dexStatsCategory(_ category: CollectionStats.Category) -> String {
        switch category {
        case .legendaries: t("전설", "Legendaries", "でんせつ", "Legendarios", "Légendaires", "Lendários", "Legendäre", "Легендарные")
        case .mythicals: t("환상", "Mythicals", "まぼろし", "Singulares", "Fabuleux", "Míticos", "Mysteriöse", "Мифические")
        case .ultraBeasts: t("울트라비스트", "Ultra Beasts", "ウルトラビースト", "Ultraentes", "Ultra-Chimères", "Ultracriaturas",
                             "Ultrabestien", "Ультрабестии")
        case .paradoxes: t("패러독스", "Paradoxes", "パラドックス", "Paradójicos", "Paradoxes", "Paradoxos", "Paradoxe",
                           "Парадоксы")
        case .fossils: t("화석", "Fossils", "かせき", "Fósiles", "Fossiles", "Fósseis", "Fossilien", "Ископаемые")
        case .starters: t("스타팅", "Starters", "さいしょの3びき", "Iniciales", "Starters", "Iniciais", "Starter", "Стартовые")
        }
    }
    func dexStatsBattleKind(_ kind: BattleFormKind) -> String {
        switch kind {
        case .mega: t("메가진화", "Mega Evolutions", "メガシンカ", "Megaevoluciones", "Méga-Évolutions", "Megaevoluções",
                      "Mega-Entwicklungen", "Мегаэволюции")
        case .gigantamax: t("거다이맥스", "Gigantamax", "キョダイマックス", "Gigamax", "Gigamax", "Gigantamax", "Gigadynamax",
                            "Гигантамакс")
        case .primal: t("원시회귀", "Primal Reversions", "ゲンシカイキ", "Regresiones primigenias", "Primo-Résurgences",
                        "Regressões Primitivas", "Proto-Rückentwicklungen", "Первичные формы")
        // Not counted among the collection's kinds (`CollectionStats.battleKinds`): named for completeness.
        case .armor: t("아머", "Armor", "アーマー", "Armadura", "Armure", "Armadura", "Rüstung", "Броня")
        }
    }
    func dexStatsGroup(_ group: CollectionStats.Group) -> String {
        switch group {
        case .generation(let n): dexStatsGeneration(n)
        case .type(let type): typeName(type)
        case .cell(let n, let type): "\(dexStatsGeneration(n)) · \(typeName(type))"
        case .category(let category): dexStatsCategory(category)
        case .battle(let kind): dexStatsBattleKind(kind)
        }
    }
}
