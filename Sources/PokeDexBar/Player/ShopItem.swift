import Foundation

/// 품목 분류. **화면이 아니라 품목이 자기 자리를 안다** — 뷰에 목록을 손으로 나열하면
/// 품목을 더할 때 어느 칸에 넣을지 매번 다시 정해야 하고, 빠뜨리면 조용히 안 팔린다.
///
/// 기준은 **쓰면 없어지는가**다. 예전에는 상점이 사탕·모습 바꾸기·부적 셋으로, 가방이
/// 소모품·부적 둘로 나뉘어 같은 물건이 화면마다 다른 칸에 있었다. 사탕과 메가스톤은 종류가
/// 달라 보여도 사용자에게는 똑같이 "사면 없어지는 것"이라, 그 하나가 실제로 쓰이는 구분이다.
///
/// 이름은 여기 한 곳에만 둔다 — 상점과 가방이 각자 문구를 들고 있으면 다시 갈라진다.
enum ShopCategory: Int, CaseIterable, Sendable {
    case consumable, charm

    func title(_ lang: AppLanguage) -> String {
        let names: (String, String, String) = switch self {
        case .consumable: ("소모품", "Consumables", "しょうひんアイテム")
        case .charm: ("부적", "Charms", "おまもり")
        }
        switch lang { case .ko: return names.0; case .en: return names.1; case .ja: return names.2 }
    }
}

/// 상점 품목(알 뽑기·슬롯 확장 제외 — 그 둘은 값이 상황에 따라 달라 따로 다룬다).
enum ShopItem: String, CaseIterable, Sendable {
    case expCandy, shinyCandy, megaStone, dynamaxMushroom, shinyCharm, expCharm, fortuneCharm
    /// 무지개 부적 — 이로치 부적의 업그레이드(1/64 → 1/32). **팔지 않는다** — 전국도감 완성
    /// 미션에서만 나온다. 가방의 부적 칸에는 다른 부적처럼 선다.
    case rainbowCharm
    /// 알 뽑기 확정권 — 그 등급이 확정으로 나오는 무료 뽑기 한 번. **팔지 않는다** — 도감
    /// 미션에서만 나오고, 상점의 알 뽑기 자리에서 쓴다. 소모품이라 가방 소모품 칸에 선다.
    case rareEggTicket, epicEggTicket, legendaryEggTicket

    var price: Int {
        switch self {
        case .expCandy: 500_000_000
        case .shinyCandy: 3_000_000_000
        case .megaStone: 2_000_000_000
        case .dynamaxMushroom: 2_000_000_000
        case .shinyCharm: 3_000_000_000
        case .expCharm: 4_000_000_000
        case .fortuneCharm: 5_000_000_000
        // 못 사는 물건의 가격 — 상점 목록에서 빠지므로 표시될 일이 없고, 혹시 새 화면이
        // 실수로 노출해도 살 수 없는 값이다.
        case .rainbowCharm, .rareEggTicket, .epicEggTicket, .legendaryEggTicket: Int.max
        }
    }

    /// 상점에 진열되는가. 무지개 부적·알 확정권은 미션 보상 전용이라 상점에 안 선다.
    var isSold: Bool {
        switch self {
        case .rainbowCharm, .rareEggTicket, .epicEggTicket, .legendaryEggTicket: false
        default: true
        }
    }

    /// 확정권이 보장하는 등급. 확정권이 아니면 nil.
    var guaranteedGrade: Grade? {
        switch self {
        case .rareEggTicket: .rare
        case .epicEggTicket: .epic
        case .legendaryEggTicket: .legendary
        default: nil
        }
    }

    /// 등급 → 그 등급의 확정권.
    static func eggTicket(for grade: Grade) -> ShopItem? {
        switch grade {
        case .rare: .rareEggTicket
        case .epic: .epicEggTicket
        case .legendary: .legendaryEggTicket
        case .common: nil
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
        case .rainbowCharm: names = ("무지개 부적", "Rainbow Charm", "にじいろおまもり")
        case .rareEggTicket: names = ("레어 알 확정권", "Rare Egg Ticket", "レアタマゴかくていけん")
        case .epicEggTicket: names = ("에픽 알 확정권", "Epic Egg Ticket", "エピックタマゴかくていけん")
        case .legendaryEggTicket:
            names = ("레전더리 알 확정권", "Legendary Egg Ticket", "でんせつタマゴかくていけん")
        }
        switch lang { case .ko: return names.0; case .en: return names.1; case .ja: return names.2 }
    }

    /// 진열 분류 — 쓰면 없어지는가로 갈린다(`isConsumable` 과 같은 기준이다).
    var category: ShopCategory { isCharm ? .charm : .consumable }

    /// 부적은 보유형이라 개수를 세지 않고 한 번만 산다.
    var isConsumable: Bool { !isCharm }
    /// 보유형(한 번 사면 계속 효과가 있는 것). 재고를 세지 않는다.
    var isCharm: Bool {
        self == .shinyCharm || self == .expCharm || self == .fortuneCharm || self == .rainbowCharm
    }

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
        case .rainbowCharm:
            texts = ("이로치 부적의 업그레이드 — 이로치 확률이 1/32이 됩니다. 전국도감 완성의 증표",
                     "The Shiny Charm perfected — shiny odds become 1/32. Proof of a complete Dex",
                     "ひかるおまもりの上位版 — ひかる確率が1/32に。全国図鑑完成のあかし")
        case .rareEggTicket, .epicEggTicket, .legendaryEggTicket:
            texts = ("그 등급이 확정인 무료 알 뽑기 한 번 — 상점의 알 뽑기에서 씁니다",
                     "One free egg draw with the grade guaranteed — used at the Shop's egg draw",
                     "その等級かくていの無料タマゴ抽選1回 — ショップのタマゴ抽選でつかいます")
        }
        switch lang { case .ko: return texts.0; case .en: return texts.1; case .ja: return texts.2 }
    }
}
