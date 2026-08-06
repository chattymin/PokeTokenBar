import Foundation

/// 메가진화·거다이맥스 폼. 종이 바뀌는 게 아니라 **같은 개체의 겉모습이 바뀐다** —
/// 도감 번호도 그대로고(폼은 도감에 따로 안 잡힌다) 진화 단계도 그대로다.
enum FormKind: String, Codable, Sendable, CaseIterable {
    case mega, gmax

    /// 이 폼으로 바꾸는 데 쓰는 상점 품목.
    var item: ShopItem {
        switch self {
        case .mega: .megaStone
        case .gmax: .dynamaxMushroom
        }
    }

    /// 폼 이름 접두사 — 종 이름 앞에 붙인다(`메가 리자몽`). 종 이름은 진화 라인에서 온다.
    func prefix(_ lang: AppLanguage) -> String {
        let names: (String, String, String) = switch self {
        case .mega: ("메가", "Mega", "メガ")
        case .gmax: ("거다이맥스", "Gigantamax", "キョダイマックス")
        }
        switch lang { case .ko: return names.0; case .en: return names.1; case .ja: return names.2 }
    }
}

/// 폼 하나 — 어떤 종의 어떤 폼이고, Showdown 스프라이트 슬러그가 무엇인가.
struct PokemonForm: Sendable, Equatable, Hashable {
    let speciesID: Int
    /// Showdown 슬러그(`charizard-megax`). 세이브에 그대로 저장돼 개체의 폼 정체가 된다.
    let slug: String
    let kind: FormKind
    /// 같은 종에 폼이 둘인 경우의 구분(리자몽·뮤츠의 X/Y). 없으면 nil.
    let variant: String?

    /// 표시 이름 — `메가 리자몽 X` / `Mega Charizard X` / `メガリザードンX`.
    /// 종 이름은 진화 라인에서 오므로(아직 못 받았으면 #번호) 여기서는 접두·접미만 얹는다.
    func displayName(base: String, _ lang: AppLanguage) -> String {
        let head = kind.prefix(lang)
        let joined = lang == .ja ? "\(head)\(base)" : "\(head) \(base)"
        guard let variant else { return joined }
        return lang == .ja ? "\(joined)\(variant)" : "\(joined) \(variant)"
    }
}

/// 폼 목록. **Showdown 에 스프라이트가 실제로 있는 것만** 담았다 — 목록은
/// `scripts/probe-forms.sh` 로 ani/gen5 응답을 직접 확인해 만들었고, 없는 폼
/// (`urshifu-rapidstrike-gmax`)은 뺐다. 폼을 줬는데 그림이 안 나오면 아이템만 날린 셈이 된다.
enum FormCatalog {
    static let all: [PokemonForm] = [
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
