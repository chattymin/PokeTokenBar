import Foundation

/// 상점 품목(알 뽑기·슬롯 확장 제외 — 그 둘은 값이 상황에 따라 달라 따로 다룬다).
enum ShopItem: String, CaseIterable, Sendable {
    case expCandy, shinyCandy, megaStone, dynamaxMushroom, shinyCharm

    var price: Int {
        switch self {
        case .expCandy: 500_000_000
        case .shinyCandy: 2_000_000_000
        case .megaStone: 2_500_000_000
        case .dynamaxMushroom: 2_500_000_000
        case .shinyCharm: 3_000_000_000
        }
    }

    /// 표시용 이름 — 언어별(ko/en/ja). `Grade.label(_:)`/`PokemonNature.name(_:)` 와 같은 관례.
    func label(_ lang: AppLanguage) -> String {
        let names: (String, String, String)
        switch self {
        case .expCandy: names = ("경험치 사탕", "EXP Candy", "けいけんちアメ")
        case .shinyCandy: names = ("반짝이는 사탕", "Shiny Candy", "ひかるアメ")
        case .megaStone: names = ("메가스톤", "Mega Stone", "メガストーン")
        case .dynamaxMushroom: names = ("다이맥스 버섯", "Dynamax Mushroom", "ダイマックスたけ")
        case .shinyCharm: names = ("이로치 부적", "Shiny Charm", "ひかるおまもり")
        }
        switch lang { case .ko: return names.0; case .en: return names.1; case .ja: return names.2 }
    }

    /// 부적은 보유형이라 개수를 세지 않고 한 번만 산다.
    var isConsumable: Bool { self != .shinyCharm }

    func detail(_ lang: AppLanguage) -> String {
        let texts: (String, String, String)
        switch self {
        case .expCandy:
            texts = ("지정한 포켓몬에게 경험치를 줍니다",
                     "Gives experience to a chosen Pokémon",
                     "指定したポケモンに経験値を与えます")
        case .shinyCandy:
            texts = ("지정한 포켓몬을 이로치로 만듭니다",
                     "Turns a chosen Pokémon shiny",
                     "指定したポケモンをひかるポケモンにします")
        case .megaStone:
            texts = ("메가진화할 수 있는 포켓몬의 모습을 바꿉니다",
                     "Mega Evolves a Pokémon that has a Mega Form",
                     "メガシンカできるポケモンのすがたを変えます")
        case .dynamaxMushroom:
            texts = ("거다이맥스할 수 있는 포켓몬의 모습을 바꿉니다",
                     "Gigantamaxes a Pokémon that has a G-Max Form",
                     "キョダイマックスできるポケモンのすがたを変えます")
        case .shinyCharm:
            texts = ("이후 부화의 이로치 확률이 올라갑니다",
                     "Raises the shiny odds for future hatches",
                     "以降のふ化のひかる確率が上がります")
        }
        switch lang { case .ko: return texts.0; case .en: return texts.1; case .ja: return texts.2 }
    }
}
