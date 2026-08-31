import Foundation

/// 폼의 갈래. 종이 바뀌는 게 아니라 **같은 개체의 겉모습이 바뀐다** — 도감 번호도 그대로고
/// (폼은 도감에 따로 안 잡힌다) 진화 단계도 그대로다. 그래서 **폼은 언제든 되돌릴 수 있다**
/// (진화는 못 되돌린다). 갈래를 나누는 기준은 도구를 얻는 난이도다.
enum FormKind: String, Codable, Sendable, CaseIterable {
    /// 상점에서 산다(기존). 아래 셋은 리본 파트너가 물어 온다.
    case mega, gmax
    /// 타입이 갈리는 세트(아르세우스의 플레이트, 실버디의 메모리). 원작대로 타입마다
    /// 도구가 따로 있어, 한 종의 세트를 다 채우는 것이 하나의 긴 목표가 된다.
    case typeSet
    /// 능력과 무관한 겉모습(피카츄의 모자·코스프레).
    case dressUp
    /// 전설의 변신 — 도구가 훨씬 드물게 나온다(`Ribbon.legendaryFormPermille`).
    case legendary

    /// 폼 이름 접두사 — 종 이름 앞에 붙인다(`메가 리자몽`). 새 갈래는 접두 없이
    /// 폼 이름을 뒤에 붙이므로(`기라티나 오리진`) 빈 문자열이다.
    func prefix(_ lang: AppLanguage) -> String {
        let names: (String, String, String) = switch self {
        case .mega: ("메가", "Mega", "メガ")
        case .gmax: ("거다이맥스", "Gigantamax", "キョダイマックス")
        case .typeSet, .dressUp, .legendary: ("", "", "")
        }
        switch lang { case .ko: return names.0; case .en: return names.1; case .ja: return names.2 }
    }
}

/// 폼 이름 — 언어별. 폼은 90개가 넘어 영어를 그대로 쓰면 한국어 화면이 반쯤 영어가 된다.
struct FormLabel: Sendable, Equatable, Hashable {
    let ko: String, en: String, ja: String
    init(_ ko: String, _ en: String, _ ja: String) { self.ko = ko; self.en = en; self.ja = ja }
    func text(_ lang: AppLanguage) -> String {
        switch lang { case .ko: ko; case .en: en; case .ja: ja }
    }
}

/// 폼을 여는 도구가 어디서 오는가. 메가·거다이맥스만 상점이고 나머지는 파트너가 물어 온다.
enum FormSource: Sendable, Equatable, Hashable {
    /// 상점 품목 — 쓰면 없어진다(기존 동작).
    case shop(ShopItem)
    /// 리본 파트너가 물어 온다 — 없어지지 않는다.
    case foraged(FormItem)
}

/// 폼 하나 — 어떤 종의 어떤 폼이고, Showdown 스프라이트 슬러그가 무엇인가.
struct PokemonForm: Sendable, Equatable, Hashable {
    let speciesID: Int
    /// Showdown 슬러그(`charizard-megax`). 세이브에 그대로 저장돼 개체의 폼 정체가 된다.
    let slug: String
    let kind: FormKind
    /// 같은 종에 폼이 둘인 경우의 구분(리자몽·뮤츠의 X/Y). 없으면 nil.
    let variant: String?
    /// 폼 이름(언어별). 없으면 `variant` 를 그대로 붙인다 — 메가 X/Y 가 그 경우다.
    let label: FormLabel?
    let source: FormSource
    /// **합체 폼** — 박스에 이 종이 함께 있어야 바꿀 수 있다(큐레무 블랙은 제크로무가 필요).
    /// 상대는 사라지지 않는다. 폼은 되돌릴 수 있는데 상대를 먹어 버리면 되돌릴 수가 없다.
    let fusionPartner: Int?
    /// 이 성별에게만 열리는 폼. 냐오닉스는 메가가 암수 각각이라, 안 가르면 수컷이
    /// 암컷 메가가 된다. 제한이 없으면 nil(대부분).
    let requiredGender: Gender?

    /// 메가·거다이맥스는 갈래만으로 출처가 정해지므로 기존 목록을 그대로 둔다.
    init(speciesID: Int, slug: String, kind: FormKind, variant: String?,
         label: FormLabel? = nil, source: FormSource? = nil, fusionPartner: Int? = nil,
         requiredGender: Gender? = nil) {
        self.speciesID = speciesID
        self.slug = slug
        self.kind = kind
        self.variant = variant
        self.label = label
        self.source = source ?? (kind == .gmax ? .shop(.dynamaxMushroom) : .shop(.megaStone))
        self.fusionPartner = fusionPartner
        self.requiredGender = requiredGender
    }

    /// 표시 이름 — `메가 리자몽 X` / `기라티나 오리진` / `アルセウス ほのお`.
    /// 종 이름은 진화 라인에서 오므로(아직 못 받았으면 #번호) 여기서는 접두·접미만 얹는다.
    func displayName(base: String, _ lang: AppLanguage) -> String {
        let head = kind.prefix(lang)
        let joined = head.isEmpty ? base : (lang == .ja ? "\(head)\(base)" : "\(head) \(base)")
        guard let tail = label?.text(lang) ?? variant else { return joined }
        return lang == .ja ? "\(joined)\(tail)" : "\(joined) \(tail)"
    }
}

/// 폼 목록. **Showdown 에 스프라이트가 실제로 있는 것만** 담았다 — 목록은
/// `scripts/probe-forms.sh` 로 ani/gen5 응답을 직접 확인해 만들었고, 없는 폼
/// (`urshifu-rapidstrike-gmax`)은 뺐다. 폼을 줬는데 그림이 안 나오면 아이템만 날린 셈이 된다.
enum FormCatalog {
    static let all: [PokemonForm] = [
        // MARK: Legends Z-A 의 새 메가 — 기존 메가스톤으로 그대로 열린다.
        // **Showdown 에 정적 스프라이트가 있는 것만 담았다**(실측: 신규 메가 49개 중 24개).
        // 나머지는 애니메이션만 있거나 아예 없어서, 넣으면 그 폼만 빈 칸이 된다 —
        // 카탈로그 전체가 지키는 규칙 그대로다. 그림이 생기면 그때 더한다.
        .init(speciesID: 36, slug: "clefable-mega", kind: .mega, variant: nil),
        .init(speciesID: 71, slug: "victreebel-mega", kind: .mega, variant: nil),
        .init(speciesID: 121, slug: "starmie-mega", kind: .mega, variant: nil),
        .init(speciesID: 149, slug: "dragonite-mega", kind: .mega, variant: nil),
        .init(speciesID: 154, slug: "meganium-mega", kind: .mega, variant: nil),
        .init(speciesID: 160, slug: "feraligatr-mega", kind: .mega, variant: nil),
        .init(speciesID: 227, slug: "skarmory-mega", kind: .mega, variant: nil),
        .init(speciesID: 358, slug: "chimecho-mega", kind: .mega, variant: nil),
        .init(speciesID: 478, slug: "froslass-mega", kind: .mega, variant: nil),
        .init(speciesID: 500, slug: "emboar-mega", kind: .mega, variant: nil),
        .init(speciesID: 530, slug: "excadrill-mega", kind: .mega, variant: nil),
        .init(speciesID: 609, slug: "chandelure-mega", kind: .mega, variant: nil),
        .init(speciesID: 623, slug: "golurk-mega", kind: .mega, variant: nil),
        .init(speciesID: 652, slug: "chesnaught-mega", kind: .mega, variant: nil),
        .init(speciesID: 655, slug: "delphox-mega", kind: .mega, variant: nil),
        .init(speciesID: 658, slug: "greninja-mega", kind: .mega, variant: nil),
        .init(speciesID: 670, slug: "floette-mega", kind: .mega, variant: nil),
        .init(speciesID: 678, slug: "meowstic-fmega", kind: .mega, variant: "♀",
              requiredGender: .female),
        .init(speciesID: 678, slug: "meowstic-mmega", kind: .mega, variant: "♂",
              requiredGender: .male),
        .init(speciesID: 701, slug: "hawlucha-mega", kind: .mega, variant: nil),
        .init(speciesID: 740, slug: "crabominable-mega", kind: .mega, variant: nil),
        .init(speciesID: 780, slug: "drampa-mega", kind: .mega, variant: nil),
        .init(speciesID: 952, slug: "scovillain-mega", kind: .mega, variant: nil),
        .init(speciesID: 970, slug: "glimmora-mega", kind: .mega, variant: nil),
        .init(speciesID: 3, slug: "venusaur-gmax", kind: .gmax, variant: nil),
        .init(speciesID: 3, slug: "venusaur-mega", kind: .mega, variant: nil),
        .init(speciesID: 6, slug: "charizard-gmax", kind: .gmax, variant: nil),
        .init(speciesID: 6, slug: "charizard-megax", kind: .mega, variant: "X"),
        .init(speciesID: 6, slug: "charizard-megay", kind: .mega, variant: "Y"),
        .init(speciesID: 9, slug: "blastoise-gmax", kind: .gmax, variant: nil),
        .init(speciesID: 9, slug: "blastoise-mega", kind: .mega, variant: nil),
        .init(speciesID: 12, slug: "butterfree-gmax", kind: .gmax, variant: nil),
        .init(speciesID: 15, slug: "beedrill-mega", kind: .mega, variant: nil),
        .init(speciesID: 18, slug: "pidgeot-mega", kind: .mega, variant: nil),
        .init(speciesID: 25, slug: "pikachu-gmax", kind: .gmax, variant: nil),
        .init(speciesID: 52, slug: "meowth-gmax", kind: .gmax, variant: nil),
        .init(speciesID: 65, slug: "alakazam-mega", kind: .mega, variant: nil),
        .init(speciesID: 68, slug: "machamp-gmax", kind: .gmax, variant: nil),
        .init(speciesID: 80, slug: "slowbro-mega", kind: .mega, variant: nil),
        .init(speciesID: 94, slug: "gengar-gmax", kind: .gmax, variant: nil),
        .init(speciesID: 94, slug: "gengar-mega", kind: .mega, variant: nil),
        .init(speciesID: 99, slug: "kingler-gmax", kind: .gmax, variant: nil),
        .init(speciesID: 115, slug: "kangaskhan-mega", kind: .mega, variant: nil),
        .init(speciesID: 127, slug: "pinsir-mega", kind: .mega, variant: nil),
        .init(speciesID: 130, slug: "gyarados-mega", kind: .mega, variant: nil),
        .init(speciesID: 131, slug: "lapras-gmax", kind: .gmax, variant: nil),
        .init(speciesID: 133, slug: "eevee-gmax", kind: .gmax, variant: nil),
        .init(speciesID: 142, slug: "aerodactyl-mega", kind: .mega, variant: nil),
        .init(speciesID: 143, slug: "snorlax-gmax", kind: .gmax, variant: nil),
        .init(speciesID: 150, slug: "mewtwo-megax", kind: .mega, variant: "X"),
        .init(speciesID: 150, slug: "mewtwo-megay", kind: .mega, variant: "Y"),
        .init(speciesID: 181, slug: "ampharos-mega", kind: .mega, variant: nil),
        .init(speciesID: 208, slug: "steelix-mega", kind: .mega, variant: nil),
        .init(speciesID: 212, slug: "scizor-mega", kind: .mega, variant: nil),
        .init(speciesID: 214, slug: "heracross-mega", kind: .mega, variant: nil),
        .init(speciesID: 229, slug: "houndoom-mega", kind: .mega, variant: nil),
        .init(speciesID: 248, slug: "tyranitar-mega", kind: .mega, variant: nil),
        .init(speciesID: 254, slug: "sceptile-mega", kind: .mega, variant: nil),
        .init(speciesID: 257, slug: "blaziken-mega", kind: .mega, variant: nil),
        .init(speciesID: 260, slug: "swampert-mega", kind: .mega, variant: nil),
        .init(speciesID: 282, slug: "gardevoir-mega", kind: .mega, variant: nil),
        .init(speciesID: 302, slug: "sableye-mega", kind: .mega, variant: nil),
        .init(speciesID: 303, slug: "mawile-mega", kind: .mega, variant: nil),
        .init(speciesID: 306, slug: "aggron-mega", kind: .mega, variant: nil),
        .init(speciesID: 308, slug: "medicham-mega", kind: .mega, variant: nil),
        .init(speciesID: 310, slug: "manectric-mega", kind: .mega, variant: nil),
        .init(speciesID: 319, slug: "sharpedo-mega", kind: .mega, variant: nil),
        .init(speciesID: 323, slug: "camerupt-mega", kind: .mega, variant: nil),
        .init(speciesID: 334, slug: "altaria-mega", kind: .mega, variant: nil),
        .init(speciesID: 354, slug: "banette-mega", kind: .mega, variant: nil),
        .init(speciesID: 359, slug: "absol-mega", kind: .mega, variant: nil),
        .init(speciesID: 362, slug: "glalie-mega", kind: .mega, variant: nil),
        .init(speciesID: 373, slug: "salamence-mega", kind: .mega, variant: nil),
        .init(speciesID: 376, slug: "metagross-mega", kind: .mega, variant: nil),
        .init(speciesID: 380, slug: "latias-mega", kind: .mega, variant: nil),
        .init(speciesID: 381, slug: "latios-mega", kind: .mega, variant: nil),
        .init(speciesID: 384, slug: "rayquaza-mega", kind: .mega, variant: nil),
        .init(speciesID: 428, slug: "lopunny-mega", kind: .mega, variant: nil),
        .init(speciesID: 445, slug: "garchomp-mega", kind: .mega, variant: nil),
        .init(speciesID: 448, slug: "lucario-mega", kind: .mega, variant: nil),
        .init(speciesID: 460, slug: "abomasnow-mega", kind: .mega, variant: nil),
        .init(speciesID: 475, slug: "gallade-mega", kind: .mega, variant: nil),
        .init(speciesID: 531, slug: "audino-mega", kind: .mega, variant: nil),
        .init(speciesID: 569, slug: "garbodor-gmax", kind: .gmax, variant: nil),
        .init(speciesID: 719, slug: "diancie-mega", kind: .mega, variant: nil),
        .init(speciesID: 809, slug: "melmetal-gmax", kind: .gmax, variant: nil),
        .init(speciesID: 812, slug: "rillaboom-gmax", kind: .gmax, variant: nil),
        .init(speciesID: 815, slug: "cinderace-gmax", kind: .gmax, variant: nil),
        .init(speciesID: 818, slug: "inteleon-gmax", kind: .gmax, variant: nil),
        .init(speciesID: 823, slug: "corviknight-gmax", kind: .gmax, variant: nil),
        .init(speciesID: 826, slug: "orbeetle-gmax", kind: .gmax, variant: nil),
        .init(speciesID: 834, slug: "drednaw-gmax", kind: .gmax, variant: nil),
        .init(speciesID: 839, slug: "coalossal-gmax", kind: .gmax, variant: nil),
        .init(speciesID: 841, slug: "flapple-gmax", kind: .gmax, variant: nil),
        .init(speciesID: 842, slug: "appletun-gmax", kind: .gmax, variant: nil),
        .init(speciesID: 844, slug: "sandaconda-gmax", kind: .gmax, variant: nil),
        .init(speciesID: 849, slug: "toxtricity-gmax", kind: .gmax, variant: nil),
        .init(speciesID: 851, slug: "centiskorch-gmax", kind: .gmax, variant: nil),
        .init(speciesID: 858, slug: "hatterene-gmax", kind: .gmax, variant: nil),
        .init(speciesID: 861, slug: "grimmsnarl-gmax", kind: .gmax, variant: nil),
        .init(speciesID: 869, slug: "alcremie-gmax", kind: .gmax, variant: nil),
        .init(speciesID: 879, slug: "copperajah-gmax", kind: .gmax, variant: nil),
        .init(speciesID: 884, slug: "duraludon-gmax", kind: .gmax, variant: nil),
        .init(speciesID: 892, slug: "urshifu-gmax", kind: .gmax, variant: nil),

        // 아래는 파트너가 물어 오는 도구로 바꾸는 폼 — 도구가 없어지지 않으므로 자유롭게
        // 오갈 수 있다. 합체 폼(`fusionPartner`)은 상대가 박스에 있어야 한다.
        .init(speciesID: 25, slug: "pikachu-cosplay", kind: .dressUp, variant: nil,
              label: .init("코스프레", "Cosplay", "コスプレ"), source: .foraged(.costumeTrunk)),
        .init(speciesID: 25, slug: "pikachu-rockstar", kind: .dressUp, variant: nil,
              label: .init("록스타", "Rock Star", "ロックスター"), source: .foraged(.costumeTrunk)),
        .init(speciesID: 25, slug: "pikachu-belle", kind: .dressUp, variant: nil,
              label: .init("마돈나", "Belle", "マドンナ"), source: .foraged(.costumeTrunk)),
        .init(speciesID: 25, slug: "pikachu-popstar", kind: .dressUp, variant: nil,
              label: .init("아이돌", "Pop Star", "アイドル"), source: .foraged(.costumeTrunk)),
        .init(speciesID: 25, slug: "pikachu-phd", kind: .dressUp, variant: nil,
              label: .init("박사", "PhD", "はかせ"), source: .foraged(.costumeTrunk)),
        .init(speciesID: 25, slug: "pikachu-libre", kind: .dressUp, variant: nil,
              label: .init("마스크드", "Libre", "マスクド"), source: .foraged(.costumeTrunk)),
        .init(speciesID: 25, slug: "pikachu-original", kind: .dressUp, variant: nil,
              label: .init("오리지널캡", "Original Cap", "オリジナルキャップ"), source: .foraged(.costumeTrunk)),
        .init(speciesID: 25, slug: "pikachu-hoenn", kind: .dressUp, variant: nil,
              label: .init("호연캡", "Hoenn Cap", "ホウエンキャップ"), source: .foraged(.costumeTrunk)),
        .init(speciesID: 25, slug: "pikachu-sinnoh", kind: .dressUp, variant: nil,
              label: .init("신오캡", "Sinnoh Cap", "シンオウキャップ"), source: .foraged(.costumeTrunk)),
        .init(speciesID: 25, slug: "pikachu-unova", kind: .dressUp, variant: nil,
              label: .init("하나캡", "Unova Cap", "イッシュキャップ"), source: .foraged(.costumeTrunk)),
        .init(speciesID: 25, slug: "pikachu-kalos", kind: .dressUp, variant: nil,
              label: .init("칼로스캡", "Kalos Cap", "カロスキャップ"), source: .foraged(.costumeTrunk)),
        .init(speciesID: 25, slug: "pikachu-partner", kind: .dressUp, variant: nil,
              label: .init("파트너캡", "Partner Cap", "パートナーキャップ"), source: .foraged(.costumeTrunk)),
        .init(speciesID: 25, slug: "pikachu-starter", kind: .dressUp, variant: nil,
              label: .init("레츠고", "Let's Go", "レッツゴー"), source: .foraged(.costumeTrunk)),
        .init(speciesID: 25, slug: "pikachu-world", kind: .dressUp, variant: nil,
              label: .init("월드캡", "World Cap", "ワールドキャップ"), source: .foraged(.costumeTrunk)),
        .init(speciesID: 493, slug: "arceus-fire", kind: .typeSet, variant: nil,
              label: .init("불꽃", "Fire", "ほのお"), source: .foraged(.plateFire)),
        .init(speciesID: 493, slug: "arceus-water", kind: .typeSet, variant: nil,
              label: .init("물", "Water", "みず"), source: .foraged(.plateWater)),
        .init(speciesID: 493, slug: "arceus-electric", kind: .typeSet, variant: nil,
              label: .init("전기", "Electric", "でんき"), source: .foraged(.plateElectric)),
        .init(speciesID: 493, slug: "arceus-grass", kind: .typeSet, variant: nil,
              label: .init("풀", "Grass", "くさ"), source: .foraged(.plateGrass)),
        .init(speciesID: 493, slug: "arceus-ice", kind: .typeSet, variant: nil,
              label: .init("얼음", "Ice", "こおり"), source: .foraged(.plateIce)),
        .init(speciesID: 493, slug: "arceus-fighting", kind: .typeSet, variant: nil,
              label: .init("격투", "Fighting", "かくとう"), source: .foraged(.plateFighting)),
        .init(speciesID: 493, slug: "arceus-poison", kind: .typeSet, variant: nil,
              label: .init("독", "Poison", "どく"), source: .foraged(.platePoison)),
        .init(speciesID: 493, slug: "arceus-ground", kind: .typeSet, variant: nil,
              label: .init("땅", "Ground", "じめん"), source: .foraged(.plateGround)),
        .init(speciesID: 493, slug: "arceus-flying", kind: .typeSet, variant: nil,
              label: .init("비행", "Flying", "ひこう"), source: .foraged(.plateFlying)),
        .init(speciesID: 493, slug: "arceus-psychic", kind: .typeSet, variant: nil,
              label: .init("에스퍼", "Psychic", "エスパー"), source: .foraged(.platePsychic)),
        .init(speciesID: 493, slug: "arceus-bug", kind: .typeSet, variant: nil,
              label: .init("벌레", "Bug", "むし"), source: .foraged(.plateBug)),
        .init(speciesID: 493, slug: "arceus-rock", kind: .typeSet, variant: nil,
              label: .init("바위", "Rock", "いわ"), source: .foraged(.plateRock)),
        .init(speciesID: 493, slug: "arceus-ghost", kind: .typeSet, variant: nil,
              label: .init("고스트", "Ghost", "ゴースト"), source: .foraged(.plateGhost)),
        .init(speciesID: 493, slug: "arceus-dragon", kind: .typeSet, variant: nil,
              label: .init("드래곤", "Dragon", "ドラゴン"), source: .foraged(.plateDragon)),
        .init(speciesID: 493, slug: "arceus-dark", kind: .typeSet, variant: nil,
              label: .init("악", "Dark", "あく"), source: .foraged(.plateDark)),
        .init(speciesID: 493, slug: "arceus-steel", kind: .typeSet, variant: nil,
              label: .init("강철", "Steel", "はがね"), source: .foraged(.plateSteel)),
        .init(speciesID: 493, slug: "arceus-fairy", kind: .typeSet, variant: nil,
              label: .init("페어리", "Fairy", "フェアリー"), source: .foraged(.plateFairy)),
        .init(speciesID: 773, slug: "silvally-fire", kind: .typeSet, variant: nil,
              label: .init("불꽃", "Fire", "ほのお"), source: .foraged(.memoryFire)),
        .init(speciesID: 773, slug: "silvally-water", kind: .typeSet, variant: nil,
              label: .init("물", "Water", "みず"), source: .foraged(.memoryWater)),
        .init(speciesID: 773, slug: "silvally-electric", kind: .typeSet, variant: nil,
              label: .init("전기", "Electric", "でんき"), source: .foraged(.memoryElectric)),
        .init(speciesID: 773, slug: "silvally-grass", kind: .typeSet, variant: nil,
              label: .init("풀", "Grass", "くさ"), source: .foraged(.memoryGrass)),
        .init(speciesID: 773, slug: "silvally-ice", kind: .typeSet, variant: nil,
              label: .init("얼음", "Ice", "こおり"), source: .foraged(.memoryIce)),
        .init(speciesID: 773, slug: "silvally-fighting", kind: .typeSet, variant: nil,
              label: .init("격투", "Fighting", "かくとう"), source: .foraged(.memoryFighting)),
        .init(speciesID: 773, slug: "silvally-poison", kind: .typeSet, variant: nil,
              label: .init("독", "Poison", "どく"), source: .foraged(.memoryPoison)),
        .init(speciesID: 773, slug: "silvally-ground", kind: .typeSet, variant: nil,
              label: .init("땅", "Ground", "じめん"), source: .foraged(.memoryGround)),
        .init(speciesID: 773, slug: "silvally-flying", kind: .typeSet, variant: nil,
              label: .init("비행", "Flying", "ひこう"), source: .foraged(.memoryFlying)),
        .init(speciesID: 773, slug: "silvally-psychic", kind: .typeSet, variant: nil,
              label: .init("에스퍼", "Psychic", "エスパー"), source: .foraged(.memoryPsychic)),
        .init(speciesID: 773, slug: "silvally-bug", kind: .typeSet, variant: nil,
              label: .init("벌레", "Bug", "むし"), source: .foraged(.memoryBug)),
        .init(speciesID: 773, slug: "silvally-rock", kind: .typeSet, variant: nil,
              label: .init("바위", "Rock", "いわ"), source: .foraged(.memoryRock)),
        .init(speciesID: 773, slug: "silvally-ghost", kind: .typeSet, variant: nil,
              label: .init("고스트", "Ghost", "ゴースト"), source: .foraged(.memoryGhost)),
        .init(speciesID: 773, slug: "silvally-dragon", kind: .typeSet, variant: nil,
              label: .init("드래곤", "Dragon", "ドラゴン"), source: .foraged(.memoryDragon)),
        .init(speciesID: 773, slug: "silvally-dark", kind: .typeSet, variant: nil,
              label: .init("악", "Dark", "あく"), source: .foraged(.memoryDark)),
        .init(speciesID: 773, slug: "silvally-steel", kind: .typeSet, variant: nil,
              label: .init("강철", "Steel", "はがね"), source: .foraged(.memorySteel)),
        .init(speciesID: 773, slug: "silvally-fairy", kind: .typeSet, variant: nil,
              label: .init("페어리", "Fairy", "フェアリー"), source: .foraged(.memoryFairy)),
        .init(speciesID: 479, slug: "rotom-heat", kind: .typeSet, variant: nil,
              label: .init("히트", "Heat", "ヒート"), source: .foraged(.applianceHeat)),
        .init(speciesID: 479, slug: "rotom-wash", kind: .typeSet, variant: nil,
              label: .init("워시", "Wash", "ウォッシュ"), source: .foraged(.applianceWash)),
        .init(speciesID: 479, slug: "rotom-frost", kind: .typeSet, variant: nil,
              label: .init("프로스트", "Frost", "フロスト"), source: .foraged(.applianceFrost)),
        .init(speciesID: 479, slug: "rotom-fan", kind: .typeSet, variant: nil,
              label: .init("스핀", "Fan", "スピン"), source: .foraged(.applianceFan)),
        .init(speciesID: 479, slug: "rotom-mow", kind: .typeSet, variant: nil,
              label: .init("커트", "Mow", "カット"), source: .foraged(.applianceMow)),
        .init(speciesID: 649, slug: "genesect-douse", kind: .typeSet, variant: nil,
              label: .init("샤워", "Douse", "シャワー"), source: .foraged(.driveDouse)),
        .init(speciesID: 649, slug: "genesect-shock", kind: .typeSet, variant: nil,
              label: .init("번개", "Shock", "イナズマ"), source: .foraged(.driveShock)),
        .init(speciesID: 649, slug: "genesect-burn", kind: .typeSet, variant: nil,
              label: .init("화염", "Burn", "バーニング"), source: .foraged(.driveBurn)),
        .init(speciesID: 649, slug: "genesect-chill", kind: .typeSet, variant: nil,
              label: .init("냉동", "Chill", "フリーズ"), source: .foraged(.driveChill)),
        .init(speciesID: 1017, slug: "ogerpon-wellspring", kind: .typeSet, variant: nil,
              label: .init("우물의가면", "Wellspring", "いどのめん"), source: .foraged(.maskWellspring)),
        .init(speciesID: 1017, slug: "ogerpon-hearthflame", kind: .typeSet, variant: nil,
              label: .init("화덕의가면", "Hearthflame", "かまどのめん"), source: .foraged(.maskHearthflame)),
        .init(speciesID: 1017, slug: "ogerpon-cornerstone", kind: .typeSet, variant: nil,
              label: .init("주춧돌의가면", "Cornerstone", "いしずえのめん"), source: .foraged(.maskCornerstone)),
        .init(speciesID: 172, slug: "pichu-spikyeared", kind: .dressUp, variant: nil,
              label: .init("뾰족귀", "Spiky-eared", "ギザみみ"), source: .foraged(.gsBall)),
        .init(speciesID: 386, slug: "deoxys-attack", kind: .legendary, variant: nil,
              label: .init("어택", "Attack", "アタック"), source: .foraged(.meteorite)),
        .init(speciesID: 386, slug: "deoxys-defense", kind: .legendary, variant: nil,
              label: .init("디펜스", "Defense", "ディフェンス"), source: .foraged(.meteorite)),
        .init(speciesID: 386, slug: "deoxys-speed", kind: .legendary, variant: nil,
              label: .init("스피드", "Speed", "スピード"), source: .foraged(.meteorite)),
        .init(speciesID: 487, slug: "giratina-origin", kind: .legendary, variant: nil,
              label: .init("오리진", "Origin", "オリジン"), source: .foraged(.griseousCore)),
        .init(speciesID: 492, slug: "shaymin-sky", kind: .legendary, variant: nil,
              label: .init("스카이", "Sky", "スカイ"), source: .foraged(.gracidea)),
        .init(speciesID: 483, slug: "dialga-origin", kind: .legendary, variant: nil,
              label: .init("오리진", "Origin", "オリジン"), source: .foraged(.adamantCrystal)),
        .init(speciesID: 484, slug: "palkia-origin", kind: .legendary, variant: nil,
              label: .init("오리진", "Origin", "オリジン"), source: .foraged(.lustrousGlobe)),
        .init(speciesID: 383, slug: "groudon-primal", kind: .legendary, variant: nil,
              label: .init("원시", "Primal", "ゲンシ"), source: .foraged(.redOrb)),
        .init(speciesID: 382, slug: "kyogre-primal", kind: .legendary, variant: nil,
              label: .init("원시", "Primal", "ゲンシ"), source: .foraged(.blueOrb)),
        .init(speciesID: 720, slug: "hoopa-unbound", kind: .legendary, variant: nil,
              label: .init("해방된 모습", "Unbound", "ときはなたれし"), source: .foraged(.prisonBottle)),
        .init(speciesID: 641, slug: "tornadus-therian", kind: .legendary, variant: nil,
              label: .init("영물폼", "Therian", "れいじゅう"), source: .foraged(.revealGlass)),
        .init(speciesID: 642, slug: "thundurus-therian", kind: .legendary, variant: nil,
              label: .init("영물폼", "Therian", "れいじゅう"), source: .foraged(.revealGlass)),
        .init(speciesID: 645, slug: "landorus-therian", kind: .legendary, variant: nil,
              label: .init("영물폼", "Therian", "れいじゅう"), source: .foraged(.revealGlass)),
        .init(speciesID: 905, slug: "enamorus-therian", kind: .legendary, variant: nil,
              label: .init("영물폼", "Therian", "れいじゅう"), source: .foraged(.revealGlass)),
        .init(speciesID: 646, slug: "kyurem-black", kind: .legendary, variant: nil,
              label: .init("블랙", "Black", "ブラック"), source: .foraged(.dnaSplicers), fusionPartner: 644),
        .init(speciesID: 646, slug: "kyurem-white", kind: .legendary, variant: nil,
              label: .init("화이트", "White", "ホワイト"), source: .foraged(.dnaSplicers), fusionPartner: 643),
        .init(speciesID: 718, slug: "zygarde-10", kind: .legendary, variant: nil,
              label: .init("10%", "10%", "10%"), source: .foraged(.zygardeCube)),
        .init(speciesID: 800, slug: "necrozma-duskmane", kind: .legendary, variant: nil,
              label: .init("황혼의 갈기", "Dusk Mane", "たそがれのたてがみ"), source: .foraged(.ultranecroziumZ), fusionPartner: 791),
        .init(speciesID: 800, slug: "necrozma-dawnwings", kind: .legendary, variant: nil,
              label: .init("새벽의 날개", "Dawn Wings", "あかつきのつばさ"), source: .foraged(.ultranecroziumZ), fusionPartner: 792),
        .init(speciesID: 800, slug: "necrozma-ultra", kind: .legendary, variant: nil,
              label: .init("울트라", "Ultra", "ウルトラ"), source: .foraged(.ultranecroziumZ)),
        .init(speciesID: 898, slug: "calyrex-ice", kind: .legendary, variant: nil,
              label: .init("백마", "Ice Rider", "はくばじょう"), source: .foraged(.reinsOfUnity), fusionPartner: 896),
        .init(speciesID: 898, slug: "calyrex-shadow", kind: .legendary, variant: nil,
              label: .init("흑마", "Shadow Rider", "こくばじょう"), source: .foraged(.reinsOfUnity), fusionPartner: 897),
        .init(speciesID: 888, slug: "zacian-crowned", kind: .legendary, variant: nil,
              label: .init("검의 왕", "Crowned", "けんのおう"), source: .foraged(.rustedSword)),
        // 테라파고스 — 스텔라 폼.
        //
        // 스텔라는 테라파고스가 **테라스탈했을 때** 나오고, 테라스탈을 일으키는 도구가 테라스탈
        // 오브다. 그래서 원인이 그대로 맞는다 — 처음엔 테라피스를 쓰려 했는데, 그건 테라스탈
        // *타입*을 바꾸는 도구라 무관한 데다 테라파고스는 그 대상에서 아예 빠져 있다(타입이
        // 스텔라로 고정돼 있어서, 오거폰과 함께 명시적으로 제외).
        //
        // 트레이너가 쓰는 키 아이템이지만 앞선 선례가 있다 — 유전자쐐기·지가르데큐브·감옥병.
        // 노말 → 테라스탈은 도구가 아니라 곁에 두는 것으로 일어난다(특성 「테라체인지」).
        .init(speciesID: 1024, slug: "terapagos-stellar", kind: .legendary, variant: nil,
              label: .init("스텔라", "Stellar", "ステラ"), source: .foraged(.teraOrb)),
        .init(speciesID: 889, slug: "zamazenta-crowned", kind: .legendary, variant: nil,
              label: .init("방패의 왕", "Crowned", "たてのおう"), source: .foraged(.rustedShield)),
        .init(speciesID: 801, slug: "magearna-original", kind: .legendary, variant: nil,
              label: .init("옛 모습", "Original", "むかしのすがた"), source: .foraged(.soulHeart)),
    ]

    /// 이 종이 바꿀 수 있는 폼들(같은 종에 X/Y 처럼 여럿일 수 있다).
    static func forms(speciesID: Int, kind: FormKind) -> [PokemonForm] {
        all.filter { $0.speciesID == speciesID && $0.kind == kind }
    }

    static func form(slug: String) -> PokemonForm? { all.first { $0.slug == slug } }

    /// 종별 폼 보유 여부 — 상세 화면이 버튼을 낼지 판단한다.
    static func has(speciesID: Int, kind: FormKind) -> Bool {
        !forms(speciesID: speciesID, kind: kind).isEmpty
    }
}

/// 폼 도구도 진화 도구처럼 **그 도구를 쓸 수 있는 종이 물어 온다**(`ForageCatalog` 와 같은 원리).
/// 표를 따로 두지 않고 `FormCatalog` 에서 뽑아 쓰는 건, 폼을 추가할 때 채집 표를 같이 고치는 걸
/// 잊으면 "화면에는 있는데 도구를 얻을 길이 없는" 폼이 조용히 생기기 때문이다.
enum FormForageCatalog {
    /// 이 종이 물어 올 수 있는 폼 도구들. 상점에서 파는 메가스톤·다이버섯은 빠진다.
    /// 지방 모습은 폼을 못 가지므로(`hasForms`) 지방이 있으면 빈 배열이다.
    static func items(speciesID: Int, region: Region?) -> [(item: FormItem, kind: FormKind)] {
        guard region == nil else { return [] }
        var seen: Set<FormItem> = []
        return FormCatalog.all.compactMap { form in
            guard form.speciesID == speciesID, case .foraged(let item) = form.source,
                  seen.insert(item).inserted else { return nil }
            return (item, form.kind)
        }
    }
}
