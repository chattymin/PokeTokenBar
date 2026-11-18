import Foundation

/// The Shop's and the Bag's tabs (#183): the eggs, the raising and the dungeons under Prof. Oak's card; the raising,
/// the dungeons, the badges and the artifacts in the Bag.
extension L {
    /// The raising tab: the Pokémon raised, the graduated ones and what is kept for good (the Bag's eggs too). Short
    /// enough for one of the Bag's four segments with its count ("Выращивание" was not, `ShopBagTabsTests`).
    var raisingTab: String {
        t("육성", "Raising", "育成", "Crianza", "Élevage", "Criação", "Aufzucht", "Рост")
    }

    /// The section of what a graduated Pokémon uses (the Mint), in the raising tab.
    var shopGraduatedSection: String {
        t("졸업한 포켓몬에게", "For graduated Pokémon", "卒業したポケモンに", "Para los Pokémon graduados",
          "Pour les Pokémon diplômés", "Para os Pokémon formados", "Für verabschiedete Pokémon", "Для выпускников")
    }

    /// A Shop tab's title.
    func shopTab(_ tab: CompanionStore.ShopTab) -> String {
        switch tab {
        case .eggs: shopSection(.eggs)
        case .raising: raisingTab
        case .dungeons: dungeonsTab
        }
    }
}
