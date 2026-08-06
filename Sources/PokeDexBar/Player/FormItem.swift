import Foundation

/// 폼을 바꾸는 도구. 진화 도구(`EvolutionItem`)와 **성격이 반대다**:
///
/// - 진화는 종이 바뀌므로 **되돌릴 수 없다**. 도구는 그 갈래를 여는 열쇠고, 한 번 지나면 끝이다.
/// - 폼은 같은 개체의 겉모습이라 **언제든 되돌린다**. 그래서 도구도 없어지지 않고 계속 쓴다.
///
/// 얻는 방법은 진화 도구와 같다 — 리본을 단 파트너가 **자기가 쓸 것을** 물어 온다
/// (`FormForageCatalog`). 다만 전설의 폼은 훨씬 낮은 확률로 나온다(`Ribbon.legendaryFormPermille`).
///
/// 하나가 여러 종을 여는 경우가 있다: 빛의거울은 토네로스·볼트로스·랜드로스·러브로스 넷의
/// 영물폼을 전부 열고, 플레이트 하나가 아르세우스의 17타입을 전부 연다. 폼은 도감에 따로
/// 잡히지 않으므로 17개를 따로 모으게 하면 도감에 남지 않는 순수 노동이 된다.
enum FormItem: String, CaseIterable, Codable, Sendable {
    // 타입 세트 — 하나가 그 종의 모든 타입을 연다.
    case plate = "form-plate"                 // 아르세우스
    case memory = "form-memory"               // 실버디
    case drive = "form-drive"                 // 게노세크트
    case appliance = "form-appliance"         // 로토무
    case mask = "form-mask"                   // 오거폰

    // 변장 — 능력과 무관한 겉모습.
    case costumeTrunk = "form-costume-trunk"  // 피카츄
    case gsBall = "form-gs-ball"              // 피츄

    // 전설 — 종마다 자기 물건이 있다.
    case meteorite = "form-meteorite"                 // 데오키시스
    case griseousCore = "form-griseous-core"          // 기라티나
    case gracidea = "form-gracidea"                   // 쉐이미
    case adamantCrystal = "form-adamant-crystal"      // 디아루가
    case lustrousGlobe = "form-lustrous-globe"        // 펄기아
    case redOrb = "form-red-orb"                      // 그란돈
    case blueOrb = "form-blue-orb"                    // 가이오가
    case prisonBottle = "form-prison-bottle"          // 후파
    case revealGlass = "form-reveal-glass"            // 토네로스·볼트로스·랜드로스·러브로스
    case dnaSplicers = "form-dna-splicers"            // 큐레무
    case zygardeCube = "form-zygarde-cube"            // 지가르데
    case ultranecroziumZ = "form-ultranecrozium-z"    // 네크로즈마
    case reinsOfUnity = "form-reins-of-unity"         // 버드렉스
    case rustedSword = "form-rusted-sword"            // 자시안
    case rustedShield = "form-rusted-shield"          // 자마젠타
    case soulHeart = "form-soul-heart"                // 마기아나

    /// 저장 키가 상점 품목·진화 도구와 겹치면 인벤토리 한 칸을 두고 다툰다.
    /// 접두사 `form-` 이 그 방어이고, 테스트가 실제로 안 겹치는지 확인한다.
    static func named(_ key: String) -> FormItem? { FormItem(rawValue: key) }

    func label(_ lang: AppLanguage) -> String {
        let names: (String, String, String) = switch self {
        case .plate: ("플레이트", "Plate", "プレート")
        case .memory: ("메모리", "Memory", "メモリ")
        case .drive: ("카세트", "Drive", "カセット")
        case .appliance: ("가전제품", "Appliance", "かでんせいひん")
        case .mask: ("가면", "Mask", "おめん")
        case .costumeTrunk: ("변장 트렁크", "Costume Trunk", "へんそうトランク")
        case .gsBall: ("GS볼", "GS Ball", "GSボール")
        case .meteorite: ("유석", "Meteorite", "いんせき")
        case .griseousCore: ("백금옥", "Griseous Core", "はっきんだま")
        case .gracidea: ("그라시데아", "Gracidea", "グラシデア")
        case .adamantCrystal: ("큰빛나는옥", "Adamant Crystal", "だいこんごうだま")
        case .lustrousGlobe: ("큰조각옥", "Lustrous Globe", "だいしらたま")
        case .redOrb: ("붉은구슬", "Red Orb", "あかいたま")
        case .blueOrb: ("푸른구슬", "Blue Orb", "あおいたま")
        case .prisonBottle: ("이차원의 병", "Prison Bottle", "いましめのツボ")
        case .revealGlass: ("빛의거울", "Reveal Glass", "うつしかがみ")
        case .dnaSplicers: ("DNA쐐기", "DNA Splicers", "いでんしのくさび")
        case .zygardeCube: ("젠 큐브", "Zygarde Cube", "ジガルデキューブ")
        case .ultranecroziumZ: ("울트라네크로Z", "Ultranecrozium Z", "ウルトラネクロZ")
        case .reinsOfUnity: ("유대의 고삐", "Reins of Unity", "たづな")
        case .rustedSword: ("녹슨 검", "Rusted Sword", "くちたけん")
        case .rustedShield: ("녹슨 방패", "Rusted Shield", "くちたたて")
        case .soulHeart: ("소울하트", "Soul-Heart", "ソウルハート")
        }
        switch lang { case .ko: return names.0; case .en: return names.1; case .ja: return names.2 }
    }
}
