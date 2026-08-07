import Foundation

/// 상점 진열 분류. **화면이 아니라 품목이 자기 자리를 안다** — 뷰에 목록을 손으로 나열하면
/// 품목을 더할 때 어느 칸에 넣을지 매번 다시 정해야 하고, 빠뜨리면 조용히 안 팔린다.
enum ShopCategory: Int, CaseIterable, Sendable {
    case candy, form, charm

    func title(_ lang: AppLanguage) -> String {
        let names: (String, String, String) = switch self {
        case .candy: ("사탕", "Candy", "アメ")
        case .form: ("모습 바꾸기", "Forms", "すがた")
        case .charm: ("부적", "Charms", "おまもり")
        }
        switch lang { case .ko: return names.0; case .en: return names.1; case .ja: return names.2 }
    }
}

/// 상점 품목(알 뽑기·슬롯 확장 제외 — 그 둘은 값이 상황에 따라 달라 따로 다룬다).
enum ShopItem: String, CaseIterable, Sendable {
    case expCandy, shinyCandy, megaStone, dynamaxMushroom, shinyCharm, expCharm, fortuneCharm

    var price: Int {
        switch self {
        case .expCandy: 500_000_000
        case .shinyCandy: 3_000_000_000
        case .megaStone: 2_000_000_000
        case .dynamaxMushroom: 2_000_000_000
        case .shinyCharm: 3_000_000_000
        case .expCharm: 4_000_000_000
        case .fortuneCharm: 5_000_000_000
        }
    }

    /// 표시용 이름 — 언어별(ko/en/ja). `Grade.label(_:)`/`PokemonNature.name(_:)` 와 같은 관례.
    func label(_ lang: AppLanguage) -> String {
        let names: (String, String, String)
        switch self {
        case .expCandy: names = ("경험치 사탕", "EXP Candy", "けいけんちアメ")
        case .shinyCandy: names = ("반짝이는 사탕", "Shiny Candy", "ひかるアメ")
        case .megaStone: names = ("메가스톤", "Mega Stone", "メガストーン")
        case .dynamaxMushroom: names = ("다이버섯", "Max Mushroom", "ダイマックスウキノコ")
        case .shinyCharm: names = ("이로치 부적", "Shiny Charm", "ひかるおまもり")
        case .expCharm: names = ("경험치 부적", "EXP Charm", "けいけんちおまもり")
        case .fortuneCharm: names = ("행운의 부적", "Fortune Charm", "こううんのおまもり")
        }
        switch lang { case .ko: return names.0; case .en: return names.1; case .ja: return names.2 }
    }

    /// 진열 분류. 부적은 보유형이라 한 칸에 모으고, 사탕과 모습 바꾸기는 쓰임이 달라 나눈다.
    var category: ShopCategory {
        switch self {
        case .expCandy, .shinyCandy: .candy
        case .megaStone, .dynamaxMushroom: .form
        case .shinyCharm, .expCharm, .fortuneCharm: .charm
        }
    }

    /// 부적은 보유형이라 개수를 세지 않고 한 번만 산다.
    var isConsumable: Bool { !isCharm }
    /// 보유형(한 번 사면 계속 효과가 있는 것). 재고를 세지 않는다.
    var isCharm: Bool { self == .shinyCharm || self == .expCharm || self == .fortuneCharm }

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
        case .expCharm:
            texts = ("토큰과 사탕으로 얻는 경험치가 2배가 됩니다",
                     "Doubles the experience from tokens and candy",
                     "トークンとアメで得られる経験値が2倍になります")
        case .fortuneCharm:
            texts = ("재화 획득량이 1.5배가 됩니다",
                     "Earns 1.5x the currency",
                     "所持金の獲得量が1.5倍になります")
        }
        switch lang { case .ko: return texts.0; case .en: return texts.1; case .ja: return texts.2 }
    }
}
