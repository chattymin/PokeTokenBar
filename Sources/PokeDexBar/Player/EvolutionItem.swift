import Foundation

/// 진화에 쓰는 도구 41종. **전부 리본을 단 파트너가 자기에게 필요한 것을 물어 온다**
/// (`ForageCatalog`). 재화로는 살 수 없고, **한 번 얻으면 없어지지 않아 다른 개체에도 계속 쓴다.**
///
/// 규칙이 하나인 게 요점이다. 예전에는 돌 10종만 상점에서 팔고 소모품으로 뒀는데, 채집이
/// "그 개체가 필요로 하는 것"으로 바뀌면서 돌도 물어 오게 됐다 — 이브이는 물의돌을, 쥬레곤은
/// 왕의징표석을 물어 온다. 그러면 **똑같이 며칠 걸려 얻은 도구인데 돌만 사라지는** 모순이 생긴다.
/// 품목별로 소모 여부를 나누는 대신 경로와 규칙을 하나로 합쳤다.
///
/// 그래서 도구 41종을 모으는 것 자체가 영구 해금이 된다 — 어떤 이브이가 물의돌을 한 번
/// 물어 오면 이후 모든 이브이가 그 돌을 쓴다.
///
/// 통신교환 25종 중 **15종은 특정 물건을 들고** 교환해야 한다(금속코트·에레키부스터 등 13종류).
/// 그걸 연결의 끈 하나로 뭉뚱그리면 그 물건들이 게임에서 아예 사라지므로 따로 둔다.
enum EvolutionItem: String, CaseIterable, Codable, Sendable {
    // 상점 — 여러 종을 여는 돌.
    case fireStone = "fire-stone"
    case waterStone = "water-stone"
    case thunderStone = "thunder-stone"
    case leafStone = "leaf-stone"
    case moonStone = "moon-stone"
    case sunStone = "sun-stone"
    case shinyStone = "shiny-stone"
    case duskStone = "dusk-stone"
    case dawnStone = "dawn-stone"
    case iceStone = "ice-stone"
    /// 통신교환 대체 — 이 앱에는 교환 상대가 없다. 본가에도 실제로 있는 도구를 그 자리에 놓는다.
    /// **물건을 들고 교환하는 15종에는 안 쓴다** — 그쪽은 각자의 물건이 따로 있다.
    case linkingCord = "linking-cord"

    // 리본 파트너가 물어 오는 특수 도구 — 각각 한 종만 연다.
    case tartApple = "tart-apple"
    case sweetApple = "sweet-apple"
    case syrupyApple = "syrupy-apple"
    case crackedPot = "cracked-pot"
    case chippedPot = "chipped-pot"
    case unremarkableTeacup = "unremarkable-teacup"
    case masterpieceTeacup = "masterpiece-teacup"
    case blackAugurite = "black-augurite"
    case peatBlock = "peat-block"
    case auspiciousArmor = "auspicious-armor"
    case maliciousArmor = "malicious-armor"
    case metalAlloy = "metal-alloy"
    case galaricaCuff = "galarica-cuff"
    case galaricaWreath = "galarica-wreath"
    case scrollOfDarkness = "scroll-of-darkness"
    case scrollOfWaters = "scroll-of-waters"

    // 통신교환/레벨업 때 들고 있어야 하는 물건. 통신교환 25종 중 15종, 레벨업 4종
    // (럭키·글라이온·포푸니라·포푸니크)이 이걸 요구한다. 연결의 끈으로 뭉뚱그리면
    // 에레키부스터·금속코트 같은 것이 게임에서 아예 사라진다.
    case metalCoat = "metal-coat"
    case electirizer = "electirizer"
    case magmarizer = "magmarizer"
    case kingsRock = "kings-rock"
    case dragonScale = "dragon-scale"
    case dubiousDisc = "dubious-disc"
    case protector = "protector"
    case reaperCloth = "reaper-cloth"
    case deepSeaTooth = "deep-sea-tooth"
    case deepSeaScale = "deep-sea-scale"
    case sachet = "sachet"
    case whippedDream = "whipped-dream"
    case upGrade = "up-grade"
    case prismScale = "prism-scale"
    case ovalStone = "oval-stone"
    case razorClaw = "razor-claw"
    case razorFang = "razor-fang"

    /// PokéAPI 가 돌려주는 아이템 이름 → 도구. 모르는 이름이면 nil(그 진화는 조건 없이 둔다).
    static func named(_ apiName: String) -> EvolutionItem? { EvolutionItem(rawValue: apiName) }

    func label(_ lang: AppLanguage) -> String {
        let names: (String, String, String) = switch self {
        case .fireStone: ("불꽃의돌", "Fire Stone", "ほのおのいし")
        case .waterStone: ("물의돌", "Water Stone", "みずのいし")
        case .thunderStone: ("번개의돌", "Thunder Stone", "かみなりのいし")
        case .leafStone: ("리프의돌", "Leaf Stone", "リーフのいし")
        case .moonStone: ("달의돌", "Moon Stone", "つきのいし")
        case .sunStone: ("태양의돌", "Sun Stone", "たいようのいし")
        case .shinyStone: ("빛의돌", "Shiny Stone", "ひかりのいし")
        case .duskStone: ("어둠의돌", "Dusk Stone", "やみのいし")
        case .dawnStone: ("각성의돌", "Dawn Stone", "めざめいし")
        case .iceStone: ("얼음의돌", "Ice Stone", "こおりのいし")
        case .linkingCord: ("연결의 끈", "Linking Cord", "つながりのヒモ")
        case .tartApple: ("새콤한 사과", "Tart Apple", "すっぱいりんご")
        case .sweetApple: ("달콤한 사과", "Sweet Apple", "あまーいりんご")
        case .syrupyApple: ("꿀맛 사과", "Syrupy Apple", "みつあまりんご")
        case .crackedPot: ("깨진 포트", "Cracked Pot", "われたポット")
        case .chippedPot: ("이빠진 포트", "Chipped Pot", "かけたポット")
        case .unremarkableTeacup: ("범작 찻잔", "Unremarkable Teacup", "ボンサクのちゃわん")
        case .masterpieceTeacup: ("걸작 찻잔", "Masterpiece Teacup", "ケッサクのちゃわん")
        case .blackAugurite: ("검은 휘석", "Black Augurite", "くろのきせき")
        case .peatBlock: ("이탄 덩어리", "Peat Block", "ピートブロック")
        case .auspiciousArmor: ("축복의 갑옷", "Auspicious Armor", "えんぎのよろい")
        case .maliciousArmor: ("저주의 갑옷", "Malicious Armor", "のろいのよろい")
        case .metalAlloy: ("복합금속", "Metal Alloy", "ふくごうきんぞく")
        case .galaricaCuff: ("가라두구 팔찌", "Galarica Cuff", "ガラナツブレス")
        case .galaricaWreath: ("가라두구 머리장식", "Galarica Wreath", "ガラナツリース")
        case .scrollOfDarkness: ("악의 족자", "Scroll of Darkness", "あくのかけじく")
        case .scrollOfWaters: ("물의 족자", "Scroll of Waters", "みずのかけじく")
        case .metalCoat: ("금속코트", "Metal Coat", "メタルコート")
        case .electirizer: ("에레키부스터", "Electirizer", "エレキブースター")
        case .magmarizer: ("마그마부스터", "Magmarizer", "マグマブースター")
        case .kingsRock: ("왕의징표석", "King's Rock", "おうじゃのしるし")
        case .dragonScale: ("용의비늘", "Dragon Scale", "りゅうのウロコ")
        case .dubiousDisc: ("수상한패치", "Dubious Disc", "あやしいパッチ")
        case .protector: ("프로텍터", "Protector", "プロテクター")
        case .reaperCloth: ("영혼의천", "Reaper Cloth", "れいかいのぬの")
        case .deepSeaTooth: ("심해의이빨", "Deep Sea Tooth", "しんかいのキバ")
        case .deepSeaScale: ("심해의비늘", "Deep Sea Scale", "しんかいのウロコ")
        case .sachet: ("향기주머니", "Sachet", "においぶくろ")
        case .whippedDream: ("생크림", "Whipped Dream", "ホイップポップ")
        case .upGrade: ("업그레이드", "Up-Grade", "アップグレード")
        case .prismScale: ("고운비늘", "Prism Scale", "きれいなウロコ")
        case .ovalStone: ("둥근돌", "Oval Stone", "まるいいし")
        case .razorClaw: ("예리한손톱", "Razor Claw", "するどいツメ")
        case .razorFang: ("예리한이빨", "Razor Fang", "するどいキバ")
        }
        switch lang { case .ko: return names.0; case .en: return names.1; case .ja: return names.2 }
    }
}

/// 한 진화 갈래를 지나가려면 무엇이 필요한가. PokéAPI 의 `evolution_details` 를 이 앱이 재현할 수
/// 있는 것만 남기고 옮긴 값이다 — 장소·특정 기술처럼 대응물이 없는 조건은 `.none` 으로 떨어뜨려
/// 경험치만으로 진화하게 둔다(막아 두면 그 종을 영영 못 얻는다).
enum EvoRequirement: Equatable, Sendable {
    /// 경험치만 있으면 된다.
    case none
    /// 이 도구를 써야 한다(돌·연결의 끈·특수 도구).
    case item(EvolutionItem)
    /// 충분히 오래 함께 다녀야 한다 — 본가의 친밀도를 이 앱의 "함께한 시간"으로 옮긴 것.
    case friendship
    /// 이 레벨에 닿아야 한다 — 본가 `min_level`.
    case level(Int)
    /// 이 종을 박스에 갖고 있어야 한다(만타인 ← 총어). 본가의 "파티 동행" 을 옮긴 것.
    case owns(Int)
    /// 충분히 걸어야 한다 — 본가의 1000걸음. 친밀도보다 가볍다.
    case walked

    /// 친밀도 진화에 요구하는 함께한 시간. 인연 리본과 같은 문턱이라 화면에서 이미 익숙한 값이다.
    static let friendshipSeconds = Ribbon.bond.requiredPartnerSeconds

    /// 걸음 진화가 요구하는 함께한 시간. 친밀도(1일)보다 짧게 잡는다 —
    /// 본가에서 1000걸음이 친밀도보다 훨씬 가벼운 것과 같은 비율이다.
    static let walkSeconds = 6 * 3600
}

/// 진화 레벨 규칙의 손잡이 — 본가 값이 아니라 이 앱이 정한 값이다.
enum EvoBalance {
    /// 레벨이 안 적힌 갈래의 하한. 앞 단계가 알에서 바로 나오는 25종이 여기 걸린다.
    static let unstatedLevel = 20
    /// 앞 단계 레벨 위로 얼마나 띄울지. 이게 없으면 절각참(L52)이 되는 순간
    /// 대도각참 문턱(20)을 이미 넘겨 두 단계가 한 번에 터진다.
    static let marginOverParent = 8
}
