import Foundation

/// 태어날 때 정해지는 겉모습 하나 — 어떤 종의 어떤 변종이고, Showdown 슬러그와 이름이 무엇인가.
///
/// 지방 모습(`RegionalForm`)과 같은 모양이지만 **지방이 아니라 개체 차이**다. 알로라 라이츄는
/// 어디서 왔는지를 말하지만, 안농의 글자나 비비용의 무늬는 그냥 그 아이가 그렇게 태어난 것이다.
struct BirthForm: Sendable, Equatable, Hashable {
    let speciesID: Int
    /// 개체에 저장되는 키(`"c"` · `"polar"` · `"blue"` · `"east"`).
    /// **슬러그가 아니라 키를 저장한다** — 슬러그는 단계마다 다르기 때문이다
    /// (`flabebe-blue` → `floette-blue` → `florges-blue`).
    let variant: String
    /// Showdown 슬러그. 스프라이트 요청·캐시 키가 이 값이다.
    let slug: String
    /// 배지에 쓸 이름. 공식 번역(PokéAPI `pokemon-form` 의 `form_names`)에서 가져왔다.
    let label: FormLabel
}

/// 태어날 때 정해지는 겉모습 목록.
///
/// **Showdown 에 실제로 스프라이트가 있는 것만 담았다** — 지방 모습·메가와 같은 규칙이다.
/// 안농의 `!` `?` 는 그래서 빠졌다(`unown-exclamation`·`unown-question` 둘 다 404).
///
/// 비비용 팬시·몬스터볼 무늬도 뺐다. 그 둘은 배포로만 얻는 것이라 "태어난 지역이 정한다"는
/// 규칙 밖이고, 섞으면 규칙이 흐려진다.
enum BirthFormCatalog {
    // MARK: 안농 — A부터 Z까지

    /// A 는 기본 슬러그(`unown`), 나머지는 `unown-b` … `unown-z`.
    private static let unown: [BirthForm] = "abcdefghijklmnopqrstuvwxyz".map { letter in
        BirthForm(speciesID: 201, variant: String(letter),
                  slug: letter == "a" ? "unown" : "unown-\(letter)",
                  // 글자는 번역할 것이 없다 — 세 언어가 같다.
                  label: FormLabel(String(letter).uppercased(),
                                   String(letter).uppercased(),
                                   String(letter).uppercased()))
    }

    // MARK: 비비용 — 18가지 무늬

    /// 무늬는 비비용(666)에서만 보인다. 분이벌레(664)·분떠도리(665)는 무늬를 갖고 있어도 겉모습이
    /// 같아서 카탈로그에 항목이 없다 — 그래서 평소 슬러그로 그려지고, **진화가 사건이 된다.**
    static let vivillonPatterns: [(variant: String, slug: String, label: FormLabel)] = [
        ("icysnow", "vivillon-icysnow", .init("빙설의 모양", "Icy Snow", "ひょうせつのもよう")),
        ("polar", "vivillon-polar", .init("설국의 모양", "Polar", "ゆきぐにのもよう")),
        ("tundra", "vivillon-tundra", .init("설원의 모양", "Tundra", "せつげんのもよう")),
        ("continental", "vivillon-continental", .init("대륙의 모양", "Continental", "たいりくのもよう")),
        ("garden", "vivillon-garden", .init("정원의 모양", "Garden", "ていえんのもよう")),
        ("elegant", "vivillon-elegant", .init("우아한 모양", "Elegant", "みやびなもよう")),
        ("meadow", "vivillon", .init("화원의 모양", "Meadow", "はなぞののもよう")),
        ("modern", "vivillon-modern", .init("모던한 모양", "Modern", "モダンなもよう")),
        ("marine", "vivillon-marine", .init("마린의 모양", "Marine", "マリンのもよう")),
        ("archipelago", "vivillon-archipelago", .init("군도의 모양", "Archipelago", "ぐんとうのもよう")),
        ("highplains", "vivillon-highplains", .init("황야의 모양", "High Plains", "こうやのもよう")),
        ("sandstorm", "vivillon-sandstorm", .init("사진의 모양", "Sandstorm", "さじんのもよう")),
        ("river", "vivillon-river", .init("대하의 모양", "River", "たいがのもよう")),
        ("monsoon", "vivillon-monsoon", .init("스콜의 모양", "Monsoon", "スコールのもよう")),
        ("savanna", "vivillon-savanna", .init("사바나의 모양", "Savanna", "サバンナのもよう")),
        ("sun", "vivillon-sun", .init("태양의 모양", "Sun", "たいようのもよう")),
        ("ocean", "vivillon-ocean", .init("오션의 모양", "Ocean", "オーシャンのもよう")),
        ("jungle", "vivillon-jungle", .init("정글의 모양", "Jungle", "ジャングルのもよう")),
    ]

    private static let vivillon: [BirthForm] = vivillonPatterns.map {
        BirthForm(speciesID: 666, variant: $0.variant, slug: $0.slug, label: $0.label)
    }

    // MARK: 플라베베 — 꽃 색 다섯. 진화해도 색이 이어진다.

    private static let flowerColors: [(variant: String, label: FormLabel)] = [
        ("red", .init("빨간 꽃", "Red Flower", "あかいはな")),
        ("yellow", .init("노란 꽃", "Yellow Flower", "きいろのはな")),
        ("orange", .init("오렌지색 꽃", "Orange Flower", "オレンジいろのはな")),
        ("blue", .init("파란 꽃", "Blue Flower", "あおいはな")),
        ("white", .init("하얀 꽃", "White Flower", "しろいはな")),
    ]

    /// 세 단계 모두 같은 다섯 색을 쓴다. 빨강이 기본 슬러그다.
    private static let flabebeLine: [BirthForm] = [669: "flabebe", 670: "floette", 671: "florges"]
        .flatMap { species, base in
            flowerColors.map { color in
                BirthForm(speciesID: species, variant: color.variant,
                          slug: color.variant == "red" ? base : "\(base)-\(color.variant)",
                          label: color.label)
            }
        }

    // MARK: 베가베가 — 서쪽바다·동쪽바다

    private static let shellosLine: [BirthForm] = [422: "shellos", 423: "gastrodon"]
        .flatMap { species, base -> [BirthForm] in
            [BirthForm(speciesID: species, variant: "west", slug: base,
                       label: .init("서쪽바다", "West Sea", "にしのうみ")),
             BirthForm(speciesID: species, variant: "east", slug: "\(base)-east",
                       label: .init("동쪽바다", "East Sea", "ひがしのうみ"))]
        }

    /// 전체 목록.
    static let all: [BirthForm] = unown + vivillon + flabebeLine + shellosLine

    private static let bySpecies: [Int: [BirthForm]] = Dictionary(grouping: all, by: \.speciesID)

    /// 이 종이 태어날 때 겉모습이 갈리는가 — 갈린다면 그 후보들.
    /// **어느 단계에서 물어보느냐에 따라 다르다**: 분이벌레는 비었고 비비용은 18개다.
    static func forms(speciesID: Int) -> [BirthForm] { bySpecies[speciesID] ?? [] }

    /// 이 종의 이 변종. 그 단계에 해당 겉모습이 없으면 nil(평소 슬러그로 떨어진다).
    static func form(speciesID: Int, variant: String) -> BirthForm? {
        bySpecies[speciesID]?.first { $0.variant == variant }
    }

    /// 이 라인이 태어날 때 겉모습이 갈리는가 — **어느 단계에서 물어도** 답이 같아야 하는 질문.
    /// 분이벌레로 태어난 개체에 무늬를 심을지 정할 때 쓴다(분이벌레 자신은 후보가 없다).
    static func variants(forLineStartingAt baseID: Int) -> [String] {
        switch baseID {
        case 201: unown.map(\.variant)
        case 664: vivillon.map(\.variant)              // 분이벌레 → 비비용
        case 669: flowerColors.map(\.variant)          // 플라베베 라인
        case 422: ["west", "east"]                     // 베가베가 라인
        default: []
        }
    }
}
