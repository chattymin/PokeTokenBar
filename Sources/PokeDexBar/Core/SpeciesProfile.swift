import Foundation

/// 도감 상세가 보여주는 한 종의 프로필 — PokéAPI 두 엔드포인트(`pokemon-species` + `pokemon`)를
/// 합친 것. 세 언어 문자열을 전부 담아 두므로 언어를 바꿔도 재요청이 없다.
struct SpeciesProfile: Codable, Sendable, Equatable {
    let speciesID: Int
    /// 이름 — ko/en/ja. 이 화면 밖의 이름은 진화라인 캐시(`EvoLine`)에서 오지만, 도감 상세는
    /// 라인을 안 불러도 열리므로 프로필이 직접 든다.
    let nameKo: String
    let nameEn: String
    let nameJa: String
    /// 타입 슬러그("electric") — 표시는 `SpeciesProfile.typeLabel` 이 로컬 표로 옮긴다.
    let typeSlugs: [String]
    /// 키(데시미터) — 본가 단위 그대로 저장하고 표시할 때 m 로 바꾼다.
    let heightDm: Int
    /// 몸무게(헥토그램) — 표시할 때 kg 로.
    let weightHg: Int
    /// 분류("쥐포켓몬") — ko/en/ja.
    let genusKo: String
    let genusEn: String
    let genusJa: String
    /// 도감설명 — **버전별 전부**. 처음엔 언어별 최신 한 건만 골라 담았는데, 세대별로 문장이
    /// 다른 것이 본가 도감의 재미라 전부 싣는다(사용자 지적). API 배열 순서(버전 순)를 보존한다.
    let flavors: [FlavorRecord]

    func name(_ lang: AppLanguage) -> String {
        switch lang { case .ko: nameKo; case .en: nameEn; case .ja: nameJa }
    }

    func typesText(_ lang: AppLanguage) -> String {
        typeSlugs.map { Self.typeLabel($0, lang) }.joined(separator: " · ")
    }

    /// 타입 이름 — 본가 공식 번역 18종. 모르는 슬러그는 그대로 보인다(가리는 것보다 낫다).
    static func typeLabel(_ slug: String, _ lang: AppLanguage) -> String {
        let names: (String, String, String)
        switch slug {
        case "normal":   names = ("노말", "Normal", "ノーマル")
        case "fire":     names = ("불꽃", "Fire", "ほのお")
        case "water":    names = ("물", "Water", "みず")
        case "electric": names = ("전기", "Electric", "でんき")
        case "grass":    names = ("풀", "Grass", "くさ")
        case "ice":      names = ("얼음", "Ice", "こおり")
        case "fighting": names = ("격투", "Fighting", "かくとう")
        case "poison":   names = ("독", "Poison", "どく")
        case "ground":   names = ("땅", "Ground", "じめん")
        case "flying":   names = ("비행", "Flying", "ひこう")
        case "psychic":  names = ("에스퍼", "Psychic", "エスパー")
        case "bug":      names = ("벌레", "Bug", "むし")
        case "rock":     names = ("바위", "Rock", "いわ")
        case "ghost":    names = ("고스트", "Ghost", "ゴースト")
        case "dragon":   names = ("드래곤", "Dragon", "ドラゴン")
        case "dark":     names = ("악", "Dark", "あく")
        case "steel":    names = ("강철", "Steel", "はがね")
        case "fairy":    names = ("페어리", "Fairy", "フェアリー")
        default:         names = (slug, slug, slug)
        }
        switch lang { case .ko: return names.0; case .en: return names.1; case .ja: return names.2 }
    }

    func genus(_ lang: AppLanguage) -> String {
        switch lang { case .ko: genusKo; case .en: genusEn; case .ja: genusJa }
    }

    private static func code(_ lang: AppLanguage) -> String {
        switch lang { case .ko: "ko"; case .en: "en"; case .ja: "ja" }
    }

    /// 이 언어로 도감설명이 있는 세대들(오름차순). 그 언어에 아예 없으면 영어의 세대들 —
    /// 한국어 도감은 6세대(X/Y)부터라, ko 사용자에게 1~5세대 영어 문장을 섞어 보이는 것보다
    /// "한국어 도감은 여기부터" 를 정직하게 보이는 쪽을 골랐다.
    func flavorGenerations(_ lang: AppLanguage) -> [Int] {
        func gens(_ code: String) -> [Int] {
            Set(flavors.filter { $0.language == code }
                .compactMap { Self.generation(ofVersion: $0.version) }).sorted()
        }
        let own = gens(Self.code(lang))
        return own.isEmpty ? gens("en") : own
    }

    /// 그 세대의 문장 — 세대 안에 여러 버전이 있으면 **마지막 것**(배열이 버전 순이라 최신).
    /// 요청 언어에 없으면 영어로 떨어진다.
    func flavor(_ lang: AppLanguage, generation: Int) -> String? {
        func find(_ code: String) -> String? {
            flavors.last {
                $0.language == code && Self.generation(ofVersion: $0.version) == generation
            }?.text
        }
        return find(Self.code(lang)) ?? find("en")
    }

    /// 게임 버전 → 세대. 모르는 버전(미래 게임)은 nil — 표를 넓히기 전까지 그 항목만 안 보인다.
    static func generation(ofVersion slug: String) -> Int? {
        switch slug {
        case "red", "blue", "yellow": 1
        case "gold", "silver", "crystal": 2
        case "ruby", "sapphire", "emerald", "firered", "leafgreen": 3
        case "diamond", "pearl", "platinum", "heartgold", "soulsilver": 4
        case "black", "white", "black-2", "white-2": 5
        case "x", "y", "omega-ruby", "alpha-sapphire": 6
        case "sun", "moon", "ultra-sun", "ultra-moon",
             "lets-go-pikachu", "lets-go-eevee": 7
        case "sword", "shield", "brilliant-diamond", "shining-pearl",
             "legends-arceus": 8
        case "scarlet", "violet": 9
        default: nil
        }
    }

    /// 표시용 키 — "0.4 m". 본가처럼 소수 첫째 자리.
    var heightText: String { String(format: "%.1f m", Double(heightDm) / 10) }
    /// 표시용 몸무게 — "6.0 kg".
    var weightText: String { String(format: "%.1f kg", Double(weightHg) / 10) }

    /// 도감설명 원문의 제어문자 정리 — 본가 롬에서 온 텍스트라 `\n`(줄바꿈)·`\u{0C}`(페이지
    /// 넘김)이 박혀 있다. 화면 폭이 다른 이 앱에서는 전부 공백으로 접는 것이 맞다.
    static func cleaned(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\u{0C}", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

}

/// 도감설명 한 건 — 어느 게임(버전)의, 어느 언어의, 무슨 문장인가.
struct FlavorRecord: Codable, Sendable, Equatable {
    let version: String
    let language: String
    let text: String
}
