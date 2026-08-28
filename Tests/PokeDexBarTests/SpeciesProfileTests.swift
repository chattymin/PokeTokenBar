import XCTest
@testable import PokeDexBar

/// 도감 상세의 프로필 — 파싱·표시 헬퍼·소속 컬렉션.
final class SpeciesProfileTests: XCTestCase {

    /// **실제 PokéAPI 응답의 모양 그대로** 만든 픽스처다(2026-08-26 live 캡처에서 축약) —
    /// "이렇게 생겼을 것" 픽스처는 파서와 오해를 공유한다(CLAUDE.md 외부 포맷 규칙).
    /// flavor_text 의 `\n`·`\u{0C}` 제어문자와 (언어 × 버전) 중복이 실물의 핵심이다.
    private let speciesJSON = """
    {
      "capture_rate": 190,
      "is_legendary": false,
      "is_mythical": false,
      "names": [
        {"name": "피카츄", "language": {"name": "ko", "url": null}},
        {"name": "Pikachu", "language": {"name": "en", "url": null}},
        {"name": "ピカチュウ", "language": {"name": "ja", "url": null}}
      ],
      "evolution_chain": {"url": "https://pokeapi.co/api/v2/evolution-chain/10/"},
      "evolves_from_species": null,
      "growth_rate": {"name": "medium", "url": null},
      "gender_rate": 4,
      "genera": [
        {"genus": "쥐포켓몬", "language": {"name": "ko", "url": null}},
        {"genus": "Mouse Pokémon", "language": {"name": "en", "url": null}}
      ],
      "flavor_text_entries": [
        {"flavor_text": "Old entry.", "language": {"name": "en", "url": null},
         "version": {"name": "red", "url": null}},
        {"flavor_text": "X 문장.", "language": {"name": "ko", "url": null},
         "version": {"name": "x", "url": null}},
        {"flavor_text": "서로의 꼬리를 붙여서\\n전기를 흐르게 하는 게\\u000c피카츄 사이의 인사법이다.",
         "language": {"name": "ko", "url": null},
         "version": {"name": "sword", "url": null}}
      ]
    }
    """.data(using: .utf8)!

    private let pokemonJSON = """
    {
      "height": 4,
      "weight": 60,
      "types": [
        {"slot": 1, "type": {"name": "electric", "url": null}}
      ]
    }
    """.data(using: .utf8)!

    /// 실물 모양의 두 응답이 부분 디코드를 통과한다 — 안 읽는 필드가 없어도 된다.
    func testTheRealPayloadShapeDecodes() throws {
        let species = try JSONDecoder().decode(SpeciesDTO.self, from: speciesJSON)
        XCTAssertEqual(species.genera?.first?.genus, "쥐포켓몬")
        XCTAssertEqual(species.flavor_text_entries?.count, 3)
        XCTAssertEqual(species.flavor_text_entries?.last?.version?.name, "sword")
        let size = try JSONDecoder().decode(PokemonSizeDTO.self, from: pokemonJSON)
        XCTAssertEqual(size.height, 4)
        XCTAssertEqual(size.weight, 60)
        XCTAssertEqual(size.types.first?.type.name, "electric")
    }

    /// **버전 → 세대 표가 아홉 세대를 다 안다.** 모르는 버전(미래 게임)은 nil —
    /// 그 항목만 조용히 빠지고 화면은 선다.
    func testEveryKnownVersionMapsToItsGeneration() {
        XCTAssertEqual(SpeciesProfile.generation(ofVersion: "red"), 1)
        XCTAssertEqual(SpeciesProfile.generation(ofVersion: "crystal"), 2)
        XCTAssertEqual(SpeciesProfile.generation(ofVersion: "firered"), 3)
        XCTAssertEqual(SpeciesProfile.generation(ofVersion: "soulsilver"), 4)
        XCTAssertEqual(SpeciesProfile.generation(ofVersion: "black-2"), 5)
        XCTAssertEqual(SpeciesProfile.generation(ofVersion: "alpha-sapphire"), 6)
        XCTAssertEqual(SpeciesProfile.generation(ofVersion: "lets-go-eevee"), 7)
        XCTAssertEqual(SpeciesProfile.generation(ofVersion: "legends-arceus"), 8)
        XCTAssertEqual(SpeciesProfile.generation(ofVersion: "violet"), 9)
        XCTAssertNil(SpeciesProfile.generation(ofVersion: "future-game"))
    }

    /// 세대 목록과 세대별 문장 — 그 언어에 있는 세대만 뜨고(한국어는 6세대부터),
    /// 세대 안에 버전이 여럿이면 최신 것, 그 언어에 없으면 영어로 떨어진다.
    func testGenerationsAndPerGenerationFlavor() {
        let profile = SpeciesProfile(
            speciesID: 25, nameKo: "피카츄", nameEn: "Pikachu", nameJa: "ピカチュウ",
            typeSlugs: ["electric"], heightDm: 4, weightHg: 60,
            genusKo: "쥐포켓몬", genusEn: "Mouse Pokémon", genusJa: "ねずみポケモン",
            flavors: [
                FlavorRecord(version: "red", language: "en", text: "Gen1 English."),
                FlavorRecord(version: "x", language: "ko", text: "X 문장."),
                FlavorRecord(version: "sun", language: "ko", text: "썬 문장."),
                FlavorRecord(version: "ultra-sun", language: "ko", text: "울트라썬 문장."),
            ])
        // 한국어 — 6·7세대만. 1세대(영어뿐)는 안 뜬다.
        XCTAssertEqual(profile.flavorGenerations(.ko), [6, 7])
        // 같은 세대에 버전이 둘이면 마지막(최신) 것.
        XCTAssertEqual(profile.flavor(.ko, generation: 7), "울트라썬 문장.")
        XCTAssertEqual(profile.flavor(.ko, generation: 6), "X 문장.")
        // 일본어는 아예 없다 — 영어의 세대들로 떨어진다.
        XCTAssertEqual(profile.flavorGenerations(.ja), [1])
        XCTAssertEqual(profile.flavor(.ja, generation: 1), "Gen1 English.")
        XCTAssertNil(profile.flavor(.ko, generation: 3), "없는 세대의 문장이 나온다")
    }

    /// 키·몸무게는 본가 단위(dm·hg) 그대로 저장하고 표시만 m·kg 로 — 피카츄 0.4 m·6.0 kg.
    func testSizeFormatting() {
        let profile = SpeciesProfile(
            speciesID: 25, nameKo: "피카츄", nameEn: "Pikachu", nameJa: "ピカチュウ",
            typeSlugs: ["electric"], heightDm: 4, weightHg: 60,
            genusKo: "쥐포켓몬", genusEn: "Mouse Pokémon", genusJa: "ねずみポケモン",
            flavors: [])
        XCTAssertEqual(profile.heightText, "0.4 m")
        XCTAssertEqual(profile.weightText, "6.0 kg")
        XCTAssertEqual(profile.typesText(.ko), "전기")
        XCTAssertEqual(profile.name(.ja), "ピカチュウ")
    }

    /// 타입 라벨 — 18종 전부 세 언어가 있고, 모르는 슬러그는 그대로 나온다.
    func testTypeLabelsCoverAllEighteen() {
        let slugs = ["normal", "fire", "water", "electric", "grass", "ice", "fighting",
                     "poison", "ground", "flying", "psychic", "bug", "rock", "ghost",
                     "dragon", "dark", "steel", "fairy"]
        for slug in slugs {
            for lang in AppLanguage.allCases {
                XCTAssertNotEqual(SpeciesProfile.typeLabel(slug, lang), slug,
                                  "\(slug) 의 \(lang) 라벨이 없다")
            }
        }
        XCTAssertEqual(SpeciesProfile.typeLabel("stellar", .ko), "stellar",
                       "모르는 슬러그를 가리면 새 타입이 생겼을 때 빈 칸이 된다")
    }

    /// 소속 컬렉션 조회 — 뮤츠는 클론의 진실에 있고, 어디에도 없는 종은 빈 배열이다.
    func testCollectionMembership() {
        let mewtwo = CollectionCatalog.containing(species: 150).map(\.id)
        XCTAssertTrue(mewtwo.contains("clone-truth"))
        XCTAssertTrue(CollectionCatalog.containing(species: 16).isEmpty, "구구가 어딘가 속해 있다?")
        // 이브이는 이브이 프렌즈에 — 여러 세트에 겹치는 종도 전부 나온다(피카츄: 닮은꼴).
        XCTAssertTrue(CollectionCatalog.containing(species: 25).map(\.id).contains("pika-clones"))
    }
}
