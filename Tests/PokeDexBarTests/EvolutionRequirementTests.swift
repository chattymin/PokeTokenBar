import XCTest
@testable import PokeDexBar

/// PokéAPI 진화 조건 파싱 — 실제 응답 모양 그대로 만든 픽스처로 잰다.
final class EvolutionRequirementTests: XCTestCase {

    private func detail(_ json: String) throws -> EvolutionDetail {
        try JSONDecoder().decode(EvolutionDetail.self, from: Data(json.utf8))
    }

    /// 표에 없는 종 — 카탈로그가 끼어들지 않는다는 걸 보장하려고 고정으로 쓴다.
    private let uncatalogued = 4   // 파이리 — PokéAPI 가 레벨을 준다

    /// `min_level` 을 읽는다 — 파이리는 16레벨.
    func testAStatedLevelIsUsedAsIs() throws {
        let d = try detail(#"{"trigger":{"name":"level-up","url":null},"min_level":16}"#)
        XCTAssertEqual(PokeAPIClient.requirement(from: [d], speciesID: uncatalogued, parentLevel: 1), .level(16))
    }

    /// **우선순위는 안 바뀐다** — 도구가 있으면 레벨보다 도구다.
    func testAnItemStillWinsOverALevel() throws {
        let d = try detail(#"""
        {"trigger":{"name":"level-up","url":null},"min_level":30,"item":{"name":"fire-stone","url":null}}
        """#)
        XCTAssertEqual(PokeAPIClient.requirement(from: [d], speciesID: uncatalogued, parentLevel: 1), .item("fire-stone"))
    }

    /// 친밀도도 레벨보다 앞선다.
    func testFriendshipStillWinsOverALevel() throws {
        let d = try detail(#"{"trigger":{"name":"level-up","url":null},"min_level":30,"min_happiness":160}"#)
        XCTAssertEqual(PokeAPIClient.requirement(from: [d], speciesID: uncatalogued, parentLevel: 1), .friendship)
    }

    /// **든 도구도 도구다.** 럭키·포푸니라·글라이온·포푸니크 넷이 여기 걸린다 —
    /// 지금까지는 통신교환일 때만 `held_item` 을 봤다. 원작의 시간대 조건은 버린다.
    func testAHeldItemOnLevelUpCountsAsAnItem() throws {
        let d = try detail(#"""
        {"trigger":{"name":"level-up","url":null},"held_item":{"name":"razor-claw","url":null},
         "time_of_day":"night"}
        """#)
        XCTAssertEqual(PokeAPIClient.requirement(from: [d], speciesID: uncatalogued, parentLevel: 1), .item("razor-claw"))
    }

    /// 통신교환은 지금 그대로 — 든 물건이 있으면 그 물건, 없으면 연결의 끈.
    func testTradeIsUnchanged() throws {
        let plain = try detail(#"{"trigger":{"name":"trade","url":null}}"#)
        XCTAssertEqual(PokeAPIClient.requirement(from: [plain], speciesID: uncatalogued, parentLevel: 1), .item("linking-cord"))
        let held = try detail(#"""
        {"trigger":{"name":"trade","url":null},"held_item":{"name":"metal-coat","url":null}}
        """#)
        XCTAssertEqual(PokeAPIClient.requirement(from: [held], speciesID: uncatalogued, parentLevel: 1), .item("metal-coat"))
    }

    /// **레벨이 안 적힌 갈래는 `max(앞 단계 + 8, 20)`.**
    /// 앞 단계가 알에서 나오면(레벨 1) 20이고, 늦게 오는 앞 단계에서는 그 위로 밀린다.
    /// **카탈로그에 없는 종으로 고정한다** — 983(대도각참)처럼 카탈로그에 있는 종을 쓰면
    /// 규칙값과 카탈로그값이 우연히 같아져 폴백이 실제로 도는지 구분이 안 된다.
    func testAnUnstatedLevelFallsBackToTheRule() throws {
        let d = try detail(#"{"trigger":{"name":"spin","url":null}}"#)
        XCTAssertEqual(PokeAPIClient.requirement(from: [d], speciesID: uncatalogued, parentLevel: 1), .level(20))
        XCTAssertEqual(PokeAPIClient.requirement(from: [d], speciesID: uncatalogued, parentLevel: 52), .level(60))
        XCTAssertEqual(PokeAPIClient.requirement(from: [d], speciesID: uncatalogued, parentLevel: 33), .level(41))
    }

    /// 뿌리(조건 목록 자체가 없음)는 `.none` 이다.
    func testTheRootHasNoRequirement() {
        XCTAssertEqual(PokeAPIClient.requirement(from: nil, speciesID: uncatalogued, parentLevel: 1), .none)
        XCTAssertEqual(PokeAPIClient.requirement(from: [], speciesID: uncatalogued, parentLevel: 1), .none)
    }

    /// 새 도구 셋이 카탈로그에 있다 — 없으면 위 `held_item` 규칙이 조건 없음으로 샌다.
    func testTheThreeNewItemsExist() {
        XCTAssertNotNil(EvolutionItem.named("oval-stone"))
        XCTAssertNotNil(EvolutionItem.named("razor-claw"))
        XCTAssertNotNil(EvolutionItem.named("razor-fang"))
    }

    /// 성장 타입이 종 응답에서 실린다.
    func testGrowthRateComesFromTheSpeciesResponse() throws {
        let json = #"""
        {"capture_rate":45,"is_legendary":false,"is_mythical":false,"names":[],
         "evolution_chain":{"url":"https://pokeapi.co/api/v2/evolution-chain/2/"},
         "evolves_from_species":null,"growth_rate":{"name":"medium-slow","url":null}}
        """#
        let dto = try JSONDecoder().decode(SpeciesDTO.self, from: Data(json.utf8))
        XCTAssertEqual(GrowthRate.fromAPI(dto.growth_rate.name), .mediumSlow)
    }
}
