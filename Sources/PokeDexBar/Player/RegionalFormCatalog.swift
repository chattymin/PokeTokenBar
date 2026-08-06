import Foundation

/// 지방(리전). `nil` 이 아니라 `.kanto` 를 기본으로 두지 않는 이유는, 세이브의 대다수 개체가
/// 리전 없는 원종이고 필드를 비워 두는 편이 구 세이브와의 호환에도 맞기 때문이다.
enum Region: String, Codable, Sendable, CaseIterable {
    case alola, galar, hisui, paldea

    func label(_ lang: AppLanguage) -> String {
        let names: (String, String, String) = switch self {
        case .alola: ("알로라", "Alolan", "アローラ")
        case .galar: ("가라르", "Galarian", "ガラル")
        case .hisui: ("히스이", "Hisuian", "ヒスイ")
        case .paldea: ("팔데아", "Paldean", "パルデア")
        }
        switch lang { case .ko: return names.0; case .en: return names.1; case .ja: return names.2 }
    }

    /// 좁은 자리(부화 확인 카드의 배지)용 짧은 이름 — 지방 이름 그대로. 영어만 형용사형
    /// ("Galarian")이 길어 배지가 줄어든다. 한국어·일본어는 원래 짧아 같은 값이다.
    /// 이름 앞에 붙일 때는 형용사형(`label`)을 쓴다 — "가라르 나옹".
    func shortLabel(_ lang: AppLanguage) -> String {
        let names: (String, String, String) = switch self {
        case .alola: ("알로라", "Alola", "アローラ")
        case .galar: ("가라르", "Galar", "ガラル")
        case .hisui: ("히스이", "Hisui", "ヒスイ")
        case .paldea: ("팔데아", "Paldea", "パルデア")
        }
        switch lang { case .ko: return names.0; case .en: return names.1; case .ja: return names.2 }
    }

    /// 종 이름 앞에 붙인 표시 이름 — `알로라 라이츄` / `Alolan Raichu` / `アローラライチュウ`.
    func displayName(base: String, _ lang: AppLanguage) -> String {
        lang == .ja ? "\(label(lang))\(base)" : "\(label(lang)) \(base)"
    }
}

/// 리전폼 하나 — 어떤 종의 어떤 지방 모습이고, Showdown 슬러그가 무엇인가.
struct RegionalForm: Sendable, Equatable, Hashable {
    let speciesID: Int
    let region: Region
    /// Showdown 슬러그(`raichu-alola`). 스프라이트 요청·캐시 키가 이 값이다.
    let slug: String
    /// 같은 지방에 모습이 여럿인 경우(팔데아 켄타로스 combat/blaze/aqua). 없으면 nil.
    let variant: String?
}

/// 리전폼 목록. 메가·거다이맥스와 마찬가지로 **Showdown 에 실제로 스프라이트가 있는 것만** 담았다
/// (`scripts/probe-forms.sh` 로 ani/gen5 응답을 직접 확인). 리전은 메가와 달리 아이템으로 바꾸는
/// 게 아니라 **태어날 때 정해져 평생 간다** — 알로라 라이츄는 변신이 아니라 태생이다.
enum RegionalFormCatalog {
    static let all: [RegionalForm] = [
        .init(speciesID: 19, region: .alola, slug: "rattata-alola", variant: nil),
        .init(speciesID: 20, region: .alola, slug: "raticate-alola", variant: nil),
        .init(speciesID: 26, region: .alola, slug: "raichu-alola", variant: nil),
        .init(speciesID: 27, region: .alola, slug: "sandshrew-alola", variant: nil),
        .init(speciesID: 28, region: .alola, slug: "sandslash-alola", variant: nil),
        .init(speciesID: 37, region: .alola, slug: "vulpix-alola", variant: nil),
        .init(speciesID: 38, region: .alola, slug: "ninetales-alola", variant: nil),
        .init(speciesID: 50, region: .alola, slug: "diglett-alola", variant: nil),
        .init(speciesID: 51, region: .alola, slug: "dugtrio-alola", variant: nil),
        .init(speciesID: 52, region: .alola, slug: "meowth-alola", variant: nil),
        .init(speciesID: 52, region: .galar, slug: "meowth-galar", variant: nil),
        .init(speciesID: 53, region: .alola, slug: "persian-alola", variant: nil),
        .init(speciesID: 58, region: .hisui, slug: "growlithe-hisui", variant: nil),
        .init(speciesID: 59, region: .hisui, slug: "arcanine-hisui", variant: nil),
        .init(speciesID: 74, region: .alola, slug: "geodude-alola", variant: nil),
        .init(speciesID: 75, region: .alola, slug: "graveler-alola", variant: nil),
        .init(speciesID: 76, region: .alola, slug: "golem-alola", variant: nil),
        .init(speciesID: 77, region: .galar, slug: "ponyta-galar", variant: nil),
        .init(speciesID: 78, region: .galar, slug: "rapidash-galar", variant: nil),
        .init(speciesID: 79, region: .galar, slug: "slowpoke-galar", variant: nil),
        .init(speciesID: 80, region: .galar, slug: "slowbro-galar", variant: nil),
        .init(speciesID: 83, region: .galar, slug: "farfetchd-galar", variant: nil),
        .init(speciesID: 88, region: .alola, slug: "grimer-alola", variant: nil),
        .init(speciesID: 89, region: .alola, slug: "muk-alola", variant: nil),
        .init(speciesID: 100, region: .hisui, slug: "voltorb-hisui", variant: nil),
        .init(speciesID: 101, region: .hisui, slug: "electrode-hisui", variant: nil),
        .init(speciesID: 103, region: .alola, slug: "exeggutor-alola", variant: nil),
        .init(speciesID: 105, region: .alola, slug: "marowak-alola", variant: nil),
        .init(speciesID: 110, region: .galar, slug: "weezing-galar", variant: nil),
        .init(speciesID: 122, region: .galar, slug: "mrmime-galar", variant: nil),
        .init(speciesID: 128, region: .paldea, slug: "tauros-paldeaaqua", variant: "aqua"),
        .init(speciesID: 128, region: .paldea, slug: "tauros-paldeablaze", variant: "blaze"),
        .init(speciesID: 128, region: .paldea, slug: "tauros-paldeacombat", variant: "combat"),
        .init(speciesID: 144, region: .galar, slug: "articuno-galar", variant: nil),
        .init(speciesID: 145, region: .galar, slug: "zapdos-galar", variant: nil),
        .init(speciesID: 146, region: .galar, slug: "moltres-galar", variant: nil),
        .init(speciesID: 157, region: .hisui, slug: "typhlosion-hisui", variant: nil),
        .init(speciesID: 194, region: .paldea, slug: "wooper-paldea", variant: nil),
        .init(speciesID: 199, region: .galar, slug: "slowking-galar", variant: nil),
        .init(speciesID: 211, region: .hisui, slug: "qwilfish-hisui", variant: nil),
        .init(speciesID: 215, region: .hisui, slug: "sneasel-hisui", variant: nil),
        .init(speciesID: 222, region: .galar, slug: "corsola-galar", variant: nil),
        .init(speciesID: 263, region: .galar, slug: "zigzagoon-galar", variant: nil),
        .init(speciesID: 264, region: .galar, slug: "linoone-galar", variant: nil),
        .init(speciesID: 503, region: .hisui, slug: "samurott-hisui", variant: nil),
        .init(speciesID: 549, region: .hisui, slug: "lilligant-hisui", variant: nil),
        .init(speciesID: 554, region: .galar, slug: "darumaka-galar", variant: nil),
        .init(speciesID: 555, region: .galar, slug: "darmanitan-galar", variant: nil),
        .init(speciesID: 562, region: .galar, slug: "yamask-galar", variant: nil),
        .init(speciesID: 570, region: .hisui, slug: "zorua-hisui", variant: nil),
        .init(speciesID: 571, region: .hisui, slug: "zoroark-hisui", variant: nil),
        .init(speciesID: 618, region: .galar, slug: "stunfisk-galar", variant: nil),
        .init(speciesID: 628, region: .hisui, slug: "braviary-hisui", variant: nil),
        .init(speciesID: 705, region: .hisui, slug: "sliggoo-hisui", variant: nil),
        .init(speciesID: 706, region: .hisui, slug: "goodra-hisui", variant: nil),
        .init(speciesID: 713, region: .hisui, slug: "avalugg-hisui", variant: nil),
        .init(speciesID: 724, region: .hisui, slug: "decidueye-hisui", variant: nil),
    ]

    /// 이 종이 가질 수 있는 지방 모습들.
    static func forms(speciesID: Int) -> [RegionalForm] { all.filter { $0.speciesID == speciesID } }

    /// 이 종이 그 지방 모습을 갖고 있나 — 없으면 진화 후 원종 스프라이트로 떨어진다
    /// (가라르 나옹 → 나이킹처럼 지방 모습이 따로 없는 종으로 진화하는 경우).
    static func form(speciesID: Int, region: Region, variant: String? = nil) -> RegionalForm? {
        let candidates = forms(speciesID: speciesID).filter { $0.region == region }
        if let variant { return candidates.first { $0.variant == variant } ?? candidates.first }
        return candidates.first
    }

    static func regions(speciesID: Int) -> [Region] {
        Array(Set(forms(speciesID: speciesID).map(\.region))).sorted { $0.rawValue < $1.rawValue }
    }

    static func form(slug: String) -> RegionalForm? { all.first { $0.slug == slug } }
}
