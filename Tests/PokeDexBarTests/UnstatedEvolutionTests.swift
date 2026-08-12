import XCTest
@testable import PokeDexBar

/// PokéAPI 가 레벨을 안 주는 종들 — 표가 그대로 실렸나.
final class UnstatedEvolutionTests: XCTestCase {

    /// 기술을 배운 채 레벨업하는 14종. 값의 근거는 설계 문서 §3-A 표.
    func testMoveGatedSpeciesUseTheMoveLearnLevel() {
        let expected: [Int: Int] = [
            122: 25,   // 마임맨 — 흉내내기 L25
            185: 20,   // 꼬지모 — 흉내내기 L16 이지만 하한 20
            424: 32,   // 겟핸보숭 — 더블어택
            463: 34,   // 내룸벨트 — 구르기
            465: 34,   // 덩쿠림보 — 고대의힘
            469: 33,   // 메가자리 — 고대의힘
            473: 41,   // 맘모꾸리 — 고대의힘은 L1 습득이라 앞 단계(L33)+8
            763: 28,   // 달코퀸 — 밟기
            804: 20,   // 아고용 — 용의파동 L1 습득이라 하한
            853: 35,   // 케오퍼스 — 도발
            979: 36,   // 저승갓숭 — 분노의주먹 L35, 앞 단계(L28)+8
            981: 32,   // 키키링 — 트윈빔
            982: 32,   // 노고고치 — 하이퍼드릴
            1019: 20,  // 과미드라 — 드래곤치어는 레벨업 습득이 없다
        ]
        for (species, level) in expected {
            XCTAssertEqual(UnstatedEvolutionCatalog.override(speciesID: species), .level(level),
                           "#\(species)")
        }
    }

    /// 옮길 자리가 없어 레벨로 떨어뜨린 8종.
    func testUnportableConditionsBecomeLevels() {
        for species in [869, 1000, 865, 902, 899, 904, 867] {
            XCTAssertEqual(UnstatedEvolutionCatalog.override(speciesID: species), .level(20),
                           "#\(species)")
        }
        // **대도각참만 60이다.** 앞 단계인 절각참이 52레벨이라, 20으로 두면 절각참이 되는
        // 순간 이미 넘겨 두 단계가 한 번에 터진다.
        XCTAssertEqual(UnstatedEvolutionCatalog.override(speciesID: 983), .level(60))
    }

    /// 고유 규칙 5종 중 요구 조건을 갖는 넷.
    func testTheSpecialCasesGetTheirOwnRequirements() {
        XCTAssertEqual(UnstatedEvolutionCatalog.override(speciesID: 226), .owns(223))  // 만타인 ← 총어
        for species in [923, 947, 954] {                                              // 빠르모트·공푸리·베라카스
            XCTAssertEqual(UnstatedEvolutionCatalog.override(speciesID: species), .walked, "#\(species)")
        }
    }

    /// **껍질몬은 요구 조건이 아니다.** 토중몬이 진화할 때 딸려 나오는 부수 효과라
    /// 카탈로그가 아무것도 돌려주면 안 된다(돌려주면 껍질몬이 진화로도 얻어진다).
    func testShedinjaIsNotARequirement() {
        XCTAssertNil(UnstatedEvolutionCatalog.override(speciesID: 292))
    }

    /// 표에 없는 종은 건드리지 않는다 — 파이리는 PokéAPI 가 레벨을 준다.
    func testUnlistedSpeciesAreUntouched() {
        XCTAssertNil(UnstatedEvolutionCatalog.override(speciesID: 5))
        XCTAssertNil(UnstatedEvolutionCatalog.override(speciesID: 964))   // 돌핀맨 — min_level 38
    }

    /// 카탈로그는 파서가 실제로 본다 — 표만 맞고 안 불리면 아무 일도 안 난다.
    func testTheParserConsultsTheCatalog() throws {
        let d = try JSONDecoder().decode(EvolutionDetail.self,
                                         from: Data(#"{"trigger":{"name":"spin","url":null}}"#.utf8))
        // 마휘핑(#869) — 규칙대로면 앞 단계 1 → 20 이고 카탈로그도 20이라 구분이 안 된다.
        // 대도각참(#983)은 규칙(앞 단계를 1로 주면 20)과 카탈로그(60)가 갈린다.
        XCTAssertEqual(PokeAPIClient.requirement(from: [d], speciesID: 983, parentLevel: 1),
                       .level(60), "카탈로그를 안 본다")
        XCTAssertEqual(PokeAPIClient.requirement(from: [d], speciesID: 999_999, parentLevel: 1),
                       .level(20), "표에 없는 종까지 카탈로그가 가로챈다")
    }
}
