import XCTest
@testable import PokeDexBar

final class DexKeyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func individual(baseID: Int, speciesID: Int, nature: PokemonNature = .hardy,
                            region: Region? = nil, regionVariant: String? = nil,
                            birthForm: String? = nil) -> Individual {
        var made = Individual(baseID: baseID, speciesID: speciesID, pathIDs: [speciesID],
                              nature: nature, obtainedAt: now, grade: .common,
                              region: region, regionVariant: regionVariant)
        made.birthForm = birthForm
        return made
    }

    // MARK: 개체 → 키

    func testAPlainIndividualGetsABareKey() {
        XCTAssertEqual(DexKey.key(for: individual(baseID: 37, speciesID: 37)), "37")
    }

    func testARegionalIndividualGetsAFormKey() {
        let vulpix = individual(baseID: 37, speciesID: 37, region: .alola)
        XCTAssertEqual(DexKey.key(for: vulpix), "37/vulpix-alola")
    }

    func testAPaldeaTaurosVariantGetsItsOwnKey() {
        let tauros = individual(baseID: 128, speciesID: 128, region: .paldea, regionVariant: "aqua")
        XCTAssertEqual(DexKey.key(for: tauros), "128/tauros-paldeaaqua")
    }

    /// 지방 혈통인데 그 단계에 지방 모습이 없는 종(가라르 나옹 → 나이킹)은 원종 키다 —
    /// 스프라이트 규칙(`Individual.spriteForm`)과 같은 기준.
    func testARegionalLineageWithoutAFormAtThisStageFallsToBare() {
        let perrserker = individual(baseID: 52, speciesID: 863, region: .galar)
        XCTAssertEqual(DexKey.key(for: perrserker), "863")
    }

    /// 기본 슬러그 변종은 bare 키로 접힌다 — 같은 그림에 키 두 개를 만들지 않는다.
    func testTheBaseSlugVariantFoldsIntoTheBareKey() {
        let unownA = individual(baseID: 201, speciesID: 201, birthForm: "a")
        XCTAssertEqual(DexKey.key(for: unownA), "201")
        let unownC = individual(baseID: 201, speciesID: 201, birthForm: "c")
        XCTAssertEqual(DexKey.key(for: unownC), "201/unown-c")
    }

    /// 무늬를 갖고 있어도 그 단계에 카탈로그 항목이 없으면(분이벌레) 원종 키다.
    func testAPatternCarrierWithoutAStageEntryFallsToBare() {
        let scatterbug = individual(baseID: 664, speciesID: 664, birthForm: "polar")
        XCTAssertEqual(DexKey.key(for: scatterbug), "664")
        let vivillon = individual(baseID: 664, speciesID: 666, birthForm: "polar")
        XCTAssertEqual(DexKey.key(for: vivillon), "666/vivillon-polar")
    }

    /// 스트린더 — 성격에서 갈린다. amped 는 기본 슬러그라 bare 키.
    func testToxtricityKeysFromNature() {
        XCTAssertEqual(DexKey.key(for: individual(baseID: 848, speciesID: 849, nature: .hardy)), "849")
        XCTAssertEqual(DexKey.key(for: individual(baseID: 848, speciesID: 849, nature: .modest)),
                       "849/toxtricity-lowkey")
    }

    // MARK: 키 → 종

    func testSpeciesParsingFromKeys() {
        XCTAssertEqual(DexKey.speciesID(of: "37"), 37)
        XCTAssertEqual(DexKey.speciesID(of: "37/vulpix-alola"), 37)
        XCTAssertNil(DexKey.speciesID(of: "abc"))
        XCTAssertEqual(DexKey.species(of: ["37", "37/vulpix-alola", "25"]), [37, 25])
    }

    // MARK: 후보 행

    func testCandidateRowsPerSpeciesShape() {
        XCTAssertEqual(DexKey.candidates(speciesID: 1).count, 1)      // 이상해씨 — 원종뿐
        XCTAssertEqual(DexKey.candidates(speciesID: 37).count, 2)     // 식스테일 — 원종 + 알로라
        XCTAssertEqual(DexKey.candidates(speciesID: 128).count, 4)    // 켄타로스 — 원종 + 팔데아 3
        XCTAssertEqual(DexKey.candidates(speciesID: 201).count, 26)   // 안농 — A~Z (원종 행 없음)
        XCTAssertEqual(DexKey.candidates(speciesID: 849).count, 2)    // 스트린더 — 하이/로우
    }

    func testCandidateKeysMatchIndividualKeys() {
        // 후보의 key 와 그 폼으로 태어난 개체의 key 가 일치해야 UI 판정이 맞는다.
        let alola = DexKey.candidates(speciesID: 37).first { $0.slug == "vulpix-alola" }
        XCTAssertEqual(alola?.key, DexKey.key(for: individual(baseID: 37, speciesID: 37, region: .alola)))
        // 안농 행에는 bare 키 행이 정확히 하나(A) 있고 라벨은 "A" 다.
        let bare = DexKey.candidates(speciesID: 201).filter { $0.key == "201" }
        XCTAssertEqual(bare.count, 1)
        XCTAssertEqual(bare.first?.label?.en, "A")
        XCTAssertNil(bare.first?.slug, "bare 행은 종 기본 그림으로 그린다")
    }

    // MARK: 경계 검증

    func testSanitizeDropsBogusKeysAndKeepsRealOnes() {
        let cleaned = DexKey.sanitized(["37/vulpix-alola", "25", "9999", "0", "abc",
                                        "37/charizard-mega", "664/vivillon-polar", "6/charizard-mega"])
        // 메가는 도감 항목이 아니고(6/charizard-mega), 분이벌레 단계엔 무늬 항목이 없다.
        XCTAssertEqual(cleaned, ["37/vulpix-alola", "25"])
    }
}
