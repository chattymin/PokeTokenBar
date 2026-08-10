import Foundation

/// 폼을 바꾸는 도구. 진화 도구(`EvolutionItem`)와 **성격이 반대다**:
///
/// - 진화는 종이 바뀌므로 **되돌릴 수 없다**. 도구는 그 갈래를 여는 열쇠고, 한 번 지나면 끝이다.
/// - 폼은 같은 개체의 겉모습이라 **언제든 되돌린다**. 그래서 도구도 없어지지 않고 계속 쓴다.
///
/// 얻는 방법은 진화 도구와 같다 — 리본을 단 파트너가 **자기가 쓸 것을** 물어 온다
/// (`FormForageCatalog`). 다만 전설의 폼은 훨씬 낮은 확률로 나온다(`Ribbon.legendaryFormPermille`).
///
/// 개수는 **원작을 따른다**: 유석 하나가 데오키시스 세 모습을 열고 빛의거울 하나가 영물폼 넷을
/// 열지만, 아르세우스의 플레이트는 원작에 17장이 따로 있으므로 여기서도 17개다.
/// 묶어 두면 이 게임에서 플레이트만 유독 '한 장으로 17개'가 되어 규칙이 도구마다 달라진다.
enum FormItem: String, CaseIterable, Codable, Sendable {
    // 타입 세트 — 원작에 플레이트가 17장 따로 있듯, 하나가 하나를 연다.
    // 아르세우스
    case plateFire = "form-plate-fire"
    case plateWater = "form-plate-water"
    case plateElectric = "form-plate-electric"
    case plateGrass = "form-plate-grass"
    case plateIce = "form-plate-ice"
    case plateFighting = "form-plate-fighting"
    case platePoison = "form-plate-poison"
    case plateGround = "form-plate-ground"
    case plateFlying = "form-plate-flying"
    case platePsychic = "form-plate-psychic"
    case plateBug = "form-plate-bug"
    case plateRock = "form-plate-rock"
    case plateGhost = "form-plate-ghost"
    case plateDragon = "form-plate-dragon"
    case plateDark = "form-plate-dark"
    case plateSteel = "form-plate-steel"
    case plateFairy = "form-plate-fairy"
    // 실버디
    case memoryFire = "form-memory-fire"
    case memoryWater = "form-memory-water"
    case memoryElectric = "form-memory-electric"
    case memoryGrass = "form-memory-grass"
    case memoryIce = "form-memory-ice"
    case memoryFighting = "form-memory-fighting"
    case memoryPoison = "form-memory-poison"
    case memoryGround = "form-memory-ground"
    case memoryFlying = "form-memory-flying"
    case memoryPsychic = "form-memory-psychic"
    case memoryBug = "form-memory-bug"
    case memoryRock = "form-memory-rock"
    case memoryGhost = "form-memory-ghost"
    case memoryDragon = "form-memory-dragon"
    case memoryDark = "form-memory-dark"
    case memorySteel = "form-memory-steel"
    case memoryFairy = "form-memory-fairy"
    // 로토무
    case applianceHeat = "form-appliance-heat"
    case applianceWash = "form-appliance-wash"
    case applianceFrost = "form-appliance-frost"
    case applianceFan = "form-appliance-fan"
    case applianceMow = "form-appliance-mow"
    // 게노세크트
    case driveDouse = "form-drive-douse"
    case driveShock = "form-drive-shock"
    case driveBurn = "form-drive-burn"
    case driveChill = "form-drive-chill"
    // 오거폰
    case maskWellspring = "form-mask-wellspring"
    case maskHearthflame = "form-mask-hearthflame"
    case maskCornerstone = "form-mask-cornerstone"

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
    case stellarTeraShard = "form-stellar-tera-shard"  // 테라파고스
    case soulHeart = "form-soul-heart"                // 마기아나

    /// 저장 키가 상점 품목·진화 도구와 겹치면 인벤토리 한 칸을 두고 다툰다.
    /// 접두사 `form-` 이 그 방어이고, 테스트가 실제로 안 겹치는지 확인한다.
    static func named(_ key: String) -> FormItem? { FormItem(rawValue: key) }

    func label(_ lang: AppLanguage) -> String {
        let names: (String, String, String) = switch self {
        case .plateFire: ("불꽃플레이트", "Flame Plate", "ひのたまプレート")
        case .plateWater: ("물방울플레이트", "Splash Plate", "しずくプレート")
        case .plateElectric: ("번개플레이트", "Zap Plate", "いかずちプレート")
        case .plateGrass: ("초록플레이트", "Meadow Plate", "みどりのプレート")
        case .plateIce: ("고드름플레이트", "Icicle Plate", "つららのプレート")
        case .plateFighting: ("주먹플레이트", "Fist Plate", "こぶしのプレート")
        case .platePoison: ("독플레이트", "Toxic Plate", "もうどくプレート")
        case .plateGround: ("대지플레이트", "Earth Plate", "だいちのプレート")
        case .plateFlying: ("푸른하늘플레이트", "Sky Plate", "あおぞらプレート")
        case .platePsychic: ("이상한플레이트", "Mind Plate", "ふしぎなプレート")
        case .plateBug: ("옥충플레이트", "Insect Plate", "たまむしプレート")
        case .plateRock: ("암석플레이트", "Stone Plate", "がんせきプレート")
        case .plateGhost: ("원령플레이트", "Spooky Plate", "もののけプレート")
        case .plateDragon: ("용의플레이트", "Draco Plate", "りゅうのプレート")
        case .plateDark: ("공포플레이트", "Dread Plate", "こわもてプレート")
        case .plateSteel: ("강철플레이트", "Iron Plate", "こうてつプレート")
        case .plateFairy: ("요정플레이트", "Pixie Plate", "せいれいプレート")
        case .memoryFire: ("불꽃메모리", "Fire Memory", "ほのおメモリ")
        case .memoryWater: ("물메모리", "Water Memory", "みずメモリ")
        case .memoryElectric: ("전기메모리", "Electric Memory", "でんきメモリ")
        case .memoryGrass: ("풀메모리", "Grass Memory", "くさメモリ")
        case .memoryIce: ("얼음메모리", "Ice Memory", "こおりメモリ")
        case .memoryFighting: ("격투메모리", "Fighting Memory", "かくとうメモリ")
        case .memoryPoison: ("독메모리", "Poison Memory", "どくメモリ")
        case .memoryGround: ("땅메모리", "Ground Memory", "じめんメモリ")
        case .memoryFlying: ("비행메모리", "Flying Memory", "ひこうメモリ")
        case .memoryPsychic: ("에스퍼메모리", "Psychic Memory", "エスパーメモリ")
        case .memoryBug: ("벌레메모리", "Bug Memory", "むしメモリ")
        case .memoryRock: ("바위메모리", "Rock Memory", "いわメモリ")
        case .memoryGhost: ("고스트메모리", "Ghost Memory", "ゴーストメモリ")
        case .memoryDragon: ("드래곤메모리", "Dragon Memory", "ドラゴンメモリ")
        case .memoryDark: ("악메모리", "Dark Memory", "あくメモリ")
        case .memorySteel: ("강철메모리", "Steel Memory", "はがねメモリ")
        case .memoryFairy: ("페어리메모리", "Fairy Memory", "フェアリーメモリ")
        case .applianceHeat: ("전자레인지", "Microwave", "でんしレンジ")
        case .applianceWash: ("세탁기", "Washing Machine", "せんたっき")
        case .applianceFrost: ("냉장고", "Refrigerator", "れいぞうこ")
        case .applianceFan: ("선풍기", "Electric Fan", "せんぷうき")
        case .applianceMow: ("잔디깎이", "Lawn Mower", "しばかりき")
        case .driveDouse: ("샤워카세트", "Douse Drive", "シャワーカセット")
        case .driveShock: ("번개카세트", "Shock Drive", "イナズマカセット")
        case .driveBurn: ("화염카세트", "Burn Drive", "バーニングカセット")
        case .driveChill: ("냉동카세트", "Chill Drive", "フリーズカセット")
        case .maskWellspring: ("우물의가면", "Wellspring Mask", "いどのめん")
        case .maskHearthflame: ("화덕의가면", "Hearthflame Mask", "かまどのめん")
        case .maskCornerstone: ("주춧돌의가면", "Cornerstone Mask", "いしずえのめん")
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
        case .stellarTeraShard: ("스텔라 테라피스", "Stellar Tera Shard", "テラピースステラ")
        case .soulHeart: ("소울하트", "Soul-Heart", "ソウルハート")
        }
        switch lang { case .ko: return names.0; case .en: return names.1; case .ja: return names.2 }
    }
}
