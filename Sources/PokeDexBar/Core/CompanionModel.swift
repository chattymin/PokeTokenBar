import Foundation

/// 앱 언어. 포켓몬 이름은 PokéAPI 다국어 names 에서 가져온다.
enum AppLanguage: String, Codable, Sendable, CaseIterable {
    case ko, en, ja
    /// PokéAPI language.name 후보(첫 매칭 사용)
    var apiCodes: [String] {
        switch self {
        case .ko: return ["ko"]
        case .en: return ["en"]
        case .ja: return ["ja-Hrkt", "ja"]
        }
    }
    var label: String {
        switch self { case .ko: return "한국어"; case .en: return "English"; case .ja: return "日本語" }
    }

    /// byLang(langCode→name) 에서 이 언어의 이름을 고른다(apiCodes 첫 매칭 → 영어 폴백).
    func resolveName(_ byLang: [String: String]) -> String? {
        for code in apiCodes { if let n = byLang[code] { return n } }
        return byLang["en"]
    }

    /// 신규 설치 기본 언어 — 시스템 선호 언어에서 유추(글로벌 출시: 한국어 강제 금지).
    /// ko/ja 만 매칭, 그 외 전부 영어(fallback-of-fallback). 기존 사용자는 저장된 언어를 그대로 쓴다.
    static var systemDefault: AppLanguage {
        switch Locale.preferredLanguages.first?.prefix(2).lowercased() {
        case "ko": return .ko
        case "ja": return .ja
        default:   return .en
        }
    }
}

/// 희귀도 — PokéAPI capture_rate / is_legendary 로 판정.
enum Rarity: String, Codable, Sendable {
    case common, uncommon, rare, legendary
    static func from(captureRate: Int, isLegendary: Bool, isMythical: Bool) -> Rarity {
        if isLegendary || isMythical { return .legendary }
        if captureRate <= 45 { return .rare }
        if captureRate <= 120 { return .uncommon }
        return .common
    }
}

enum PokemonAssets {
    /// 다루는 종 번호 범위. 과거엔 Gen-V 애니메이션 스프라이트가 649까지뿐이라 거기 묶여 있었지만,
    /// Showdown 은 9세대까지 제공한다. 애니메이션이 없는 소수 종은 정적 스프라이트로 떨어진다.
    static let speciesIDs = 1...1025

    static func hasSprite(speciesID: Int) -> Bool {
        speciesIDs.contains(speciesID)
    }
}

/// 저장·전송용 요구 조건. `EvoRequirement` 는 카탈로그를 참조하는 계산값이라 Codable 로 두지 않는다
/// — 아이템 이름만 남겨 두면 카탈로그가 자라도 옛 캐시가 그대로 유효하다.
enum EvoRequirementRaw: Codable, Sendable, Equatable {
    case none
    case item(String)
    case friendship
    /// 이 레벨에 닿아야 한다 — 본가 `min_level`(명시가 없으면 `EvoBalance` 규칙으로 채운 값).
    case level(Int)
    /// 이 종(speciesID)을 박스에 갖고 있어야 한다.
    case owns(Int)
    /// 충분히 걸어야 한다 — 본가의 1000걸음.
    case walked
}

/// PokéAPI evolution-chain 을 파싱한 트리. 분기(evolves_to 다수)를 children 으로.
struct EvoNode: Codable, Sendable {
    let speciesID: Int
    let children: [EvoNode]
    /// **이 종이 되기 위해** 필요한 것(부모에서 이 노드로 오는 갈래의 조건).
    /// 뿌리는 항상 `.none` — 아무것도 거치지 않고 존재한다.
    var requirementRaw: EvoRequirementRaw = .none

    var requirement: EvoRequirement {
        switch requirementRaw {
        case .none: .none
        case .friendship: .friendship
        case .item(let name): EvolutionItem.named(name).map(EvoRequirement.item) ?? .none
        case .level(let n): .level(n)
        case .owns(let id): .owns(id)
        case .walked: .walked
        }
    }

    /// 최장 경로 길이(형태 수). 분기는 보통 같은 깊이라 대표값으로 사용.
    var depth: Int { 1 + (children.map(\.depth).max() ?? 0) }
    func node(withID id: Int) -> EvoNode? {
        if speciesID == id { return self }
        for c in children { if let f = c.node(withID: id) { return f } }
        return nil
    }
    /// 이 노드에서 도달 가능한 모든 최종체 id
    var finalIDs: [Int] {
        children.isEmpty ? [speciesID] : children.flatMap(\.finalIDs)
    }

    /// 다루는 범위 밖 종을 잘라낸 진화 트리(잘린 종의 하위 체인도 함께 제외).
    func keepingSupportedSpecies() -> EvoNode? {
        guard PokemonAssets.hasSprite(speciesID: speciesID) else { return nil }
        // 요구 조건을 함께 옮긴다 — 트리를 다시 만들면서 빠뜨리면 돌·연결의 끈이 필요한 진화가
        // 조건 없이 열린다. `EvoLine.init` 이 항상 이 함수를 지나므로 여기서 새면 전부 샌다.
        return EvoNode(speciesID: speciesID,
                       children: children.compactMap { $0.keepingSupportedSpecies() },
                       requirementRaw: requirementRaw)
    }
}

enum EvoLineItemContent: Equatable, Sendable {
    case species(Int)
    case mystery
}

enum EvoLineItemState: Equatable, Sendable {
    case done
    case current
    case future
}

struct EvoLineItem: Equatable, Sendable {
    let content: EvoLineItemContent
    let state: EvoLineItemState

    init(_ content: EvoLineItemContent, _ state: EvoLineItemState) {
        self.content = content
        self.state = state
    }
}

/// 부화 시 확정되는 라인 정보(트리 + 희귀도 + 다국어 이름).
struct EvoLine: Sendable {
    let baseID: Int
    let tree: EvoNode
    let rarity: Rarity
    /// speciesID → (langCode → name)
    let names: [Int: [String: String]]
    /// speciesID → 성장 곡선. 진화 후 개체가 새 종의 곡선으로 갈아 끼우는 데 쓴다(Task 7).
    /// 기본값 `[:]` 인 이유는 이 라인을 손으로 구성하는 기존 테스트가 대부분이라서다 — 실제
    /// 라인은 `PokeAPIClient.line(baseSpeciesID:)` 이 매 종마다 채워 넣는다.
    let growthRates: [Int: GrowthRate]
    var totalForms: Int { tree.depth }

    init(baseID: Int, tree: EvoNode, rarity: Rarity, names: [Int: [String: String]],
         growthRates: [Int: GrowthRate] = [:]) {
        self.baseID = baseID
        self.tree = tree.keepingSupportedSpecies() ?? EvoNode(speciesID: baseID, children: [])
        self.rarity = rarity
        self.names = names
        self.growthRates = growthRates
    }

    func localizedName(_ id: Int, _ lang: AppLanguage) -> String {
        lang.resolveName(names[id] ?? [:]) ?? "#\(id)"   // 폴백 순서는 AppLanguage.resolveName 단일 소스
    }

    /// `speciesID` 의 성장 곡선. 라인 fetch 가 안 됐거나 오래된 캐시라면 nil.
    func growthRate(of speciesID: Int) -> GrowthRate? { growthRates[speciesID] }
}

/// 성격 — 본가 25종. 부화 시 확정, 능력치 영향 없음(개체 아이덴티티 표시용).
enum PokemonNature: String, Codable, Sendable, CaseIterable {
    case hardy, lonely, brave, adamant, naughty
    case bold, docile, relaxed, impish, lax
    case timid, hasty, serious, jolly, naive
    case modest, mild, quiet, bashful, rash
    case calm, gentle, sassy, careful, quirky

    /// 본가 공식 번역 명칭 (ko/en/ja).
    func name(_ lang: AppLanguage) -> String {
        let names: (String, String, String)
        switch self {
        case .hardy:   names = ("노력", "Hardy", "がんばりや")
        case .lonely:  names = ("외로움", "Lonely", "さみしがり")
        case .brave:   names = ("용감", "Brave", "ゆうかん")
        case .adamant: names = ("고집", "Adamant", "いじっぱり")
        case .naughty: names = ("개구쟁이", "Naughty", "やんちゃ")
        case .bold:    names = ("대담", "Bold", "ずぶとい")
        case .docile:  names = ("온순", "Docile", "すなお")
        case .relaxed: names = ("무사태평", "Relaxed", "のんき")
        case .impish:  names = ("장난꾸러기", "Impish", "わんぱく")
        case .lax:     names = ("촐랑", "Lax", "のうてんき")
        case .timid:   names = ("겁쟁이", "Timid", "おくびょう")
        case .hasty:   names = ("성급", "Hasty", "せっかち")
        case .serious: names = ("성실", "Serious", "まじめ")
        case .jolly:   names = ("명랑", "Jolly", "ようき")
        case .naive:   names = ("천진난만", "Naive", "むじゃき")
        case .modest:  names = ("조심", "Modest", "ひかえめ")
        case .mild:    names = ("의젓", "Mild", "おっとり")
        case .quiet:   names = ("냉정", "Quiet", "れいせい")
        case .bashful: names = ("수줍음", "Bashful", "てれや")
        case .rash:    names = ("덜렁", "Rash", "うっかりや")
        case .calm:    names = ("차분", "Calm", "おだやか")
        case .gentle:  names = ("얌전", "Gentle", "おとなしい")
        case .sassy:   names = ("건방", "Sassy", "なまいき")
        case .careful: names = ("신중", "Careful", "しんちょう")
        case .quirky:  names = ("변덕", "Quirky", "きまぐれ")
        }
        switch lang { case .ko: return names.0; case .en: return names.1; case .ja: return names.2 }
    }
}
