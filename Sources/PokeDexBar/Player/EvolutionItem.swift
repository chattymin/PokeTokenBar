import Foundation

/// 진화에 쓰는 도구. **얻는 방법이 곧 분류다**: 돌은 상점에서 사고, 나머지 특수 도구는
/// 리본을 단 파트너가 이따금 물어 온다.
///
/// 갈래를 그렇게 잡은 근거는 실제 분포다(PokéAPI 전수 조회, 도감 1025 기준):
/// 돌 10종류가 **42종**의 진화를 열고, 나머지 23종류는 **각각 한두 종씩**만 연다.
/// 전부 상점에 늘어놓으면 대부분이 한 번 쓰고 마는 품목이라 목록이 잡화점이 된다.
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
    case unremarkableTeacup = "unremarkable-teacup"
    case blackAugurite = "black-augurite"
    case peatBlock = "peat-block"
    case auspiciousArmor = "auspicious-armor"
    case maliciousArmor = "malicious-armor"
    case metalAlloy = "metal-alloy"

    // 통신교환에 들고 가는 물건 — 25종 중 15종이 이걸 요구한다. 연결의 끈으로 뭉뚱그리면
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

    /// PokéAPI 가 돌려주는 아이템 이름 → 도구. 모르는 이름이면 nil(그 진화는 조건 없이 둔다).
    static func named(_ apiName: String) -> EvolutionItem? { EvolutionItem(rawValue: apiName) }

    /// 상점에서 파는가. 아니면 리본을 단 파트너가 물어 온다.
    var isSold: Bool { Self.shopItems.contains(self) }

    /// 상점 목록 — 여러 종을 여는 돌과, 통신교환을 대신하는 연결의 끈.
    static let shopItems: [EvolutionItem] = [
        .fireStone, .waterStone, .thunderStone, .leafStone, .moonStone,
        .sunStone, .shinyStone, .duskStone, .dawnStone, .iceStone, .linkingCord,
    ]

    /// 리본 파트너가 물어 오는 것들 — 하나가 한 종만 열어서 상점에 두면 목록만 길어진다.
    static let foraged: [EvolutionItem] = allCases.filter { !shopItems.contains($0) }

    /// 값. 돌은 뽑기 몇 번 값이면 충분하다 — 진화는 이 게임의 기본 동작이지 사치가 아니다.
    /// 연결의 끈은 물건 없이 교환하는 10종을 여는 만능이라 돌보다 비싸게 둔다.
    var price: Int {
        switch self {
        case .linkingCord: 800_000_000
        default: 300_000_000
        }
    }

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
        case .unremarkableTeacup: ("평범한 찻잔", "Unremarkable Teacup", "かけたポット")
        case .blackAugurite: ("검은 휘석", "Black Augurite", "くろのきせき")
        case .peatBlock: ("이탄 덩어리", "Peat Block", "ピートブロック")
        case .auspiciousArmor: ("축복의 갑옷", "Auspicious Armor", "えんぎのよろい")
        case .maliciousArmor: ("저주의 갑옷", "Malicious Armor", "のろいのよろい")
        case .metalAlloy: ("복합금속", "Metal Alloy", "ふくごうきんぞく")
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

    /// 친밀도 진화에 요구하는 함께한 시간. 인연 리본과 같은 문턱이라 화면에서 이미 익숙한 값이다.
    static let friendshipSeconds = Ribbon.bond.requiredPartnerSeconds
}
