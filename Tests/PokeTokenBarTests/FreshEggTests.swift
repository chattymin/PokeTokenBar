import XCTest
@testable import PokeTokenBar

// MARK: 새 알 (리롤 — 현재 포켓몬 폐기, 도감·확률 무영향)

private struct FreshEggNoProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

@MainActor
final class FreshEggTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    /// 활성 포켓몬(baseID 10, common 3형태, 성장 200M) + 도감 1개 + 수집기록 1개(1:3) + 지갑.
    /// active=false 면 알(활성 없음) 상태.
    private func store(active: Bool = true, shiny: Bool = false, used: Int = 5_000_000_000,
                       spent: Int = 0) -> CompanionStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("egg-\(UUID().uuidString).json")
        let mon = "{\"baseID\":10,\"pathIDs\":[10],\"stageIndex\":0,\"usedAtStage\":200000000,"
            + "\"rarity\":\"common\",\"totalForms\":3,\"isShiny\":\(shiny)}"
        let dex = "{\"baseID\":1,\"finalID\":3,\"chainOrder\":[1,2,3],\"rarity\":\"common\"}"
        let json = "{\"installBaselineSet\":true,\"usedSinceInstall\":\(used),\"spentTokens\":\(spent),"
            + "\"lastDate\":\"d\",\"active\":\(active ? mon : "null"),\"dex\":[\(dex)],\"collectedFinals\":[\"1:3\"]}"
        try? json.data(using: .utf8)!.write(to: url)
        return CompanionStore(provider: FreshEggNoProvider(), clock: { self.now }, fileURL: url, rng: SeededRNG(seed: 7))
    }

    func testPriceIsOneBillion() { XCTAssertEqual(FreshEgg.price, 1_000_000_000) }

    /// [핵심] 리롤 = 폐기: active 사라지고 새 알(eggUsage 0). **도감·확률(collectedFinals) 불변** = "뽑은 적 없던 것처럼".
    func testBuyFreshEggDiscardsWithoutDexOrProbabilityImpact() {
        let s = store(used: 5_000_000_000, spent: 0)
        let dexBefore = s.dexEntries.count
        let collectedBefore = s.state.collectedFinals
        XCTAssertTrue(s.hasActive)
        XCTAssertTrue(s.buyFreshEgg())
        XCTAssertNil(s.state.active, "현재 포켓몬 폐기")
        XCTAssertTrue(s.isEgg)
        XCTAssertEqual(s.state.eggUsage, 0, "새 알은 처음부터 인큐베이션")
        XCTAssertNil(s.state.pendingHatchID)
        XCTAssertEqual(s.dexEntries.count, dexBefore, "도감 불변 — 졸업이 아니라 폐기")
        XCTAssertEqual(s.state.collectedFinals, collectedBefore, "확률 가중(collectedFinals) 불변")
        XCTAssertEqual(s.state.spentTokens, FreshEgg.price, "지갑에서 1B 차감")
        XCTAssertEqual(s.availableTokens, 5_000_000_000 - FreshEgg.price)
    }

    /// 폐기한 개체(baseID 10)의 종은 collectedFinals 에 들어가지 않는다(이후 부화 확률에 영향 없음).
    func testDiscardedSpeciesNotCollected() {
        let s = store()
        XCTAssertTrue(s.buyFreshEgg())
        XCTAssertFalse(s.state.collectedFinals.contains { $0.hasPrefix("10:") },
                       "폐기 개체 종은 수집 기록에 없어야 함")
    }

    /// 알 상태(활성 없음)에선 리롤할 게 없어 불가.
    func testCannotRerollWhenEgg() {
        let s = store(active: false, used: 5_000_000_000)
        XCTAssertFalse(s.hasActive)
        XCTAssertFalse(s.canBuyFreshEgg)
        XCTAssertFalse(s.buyFreshEgg())
        XCTAssertEqual(s.state.spentTokens, 0, "no-op")
    }

    /// 잔액이 가격 미만이면 불가 — 활성 유지.
    func testCannotRerollWithoutFunds() {
        let s = store(used: 500_000_000)   // 1B 미만
        XCTAssertFalse(s.canBuyFreshEgg)
        XCTAssertFalse(s.buyFreshEgg())
        XCTAssertNotNil(s.state.active, "활성 유지")
        XCTAssertEqual(s.state.spentTokens, 0)
    }

    /// 이로치도 폐기 가능(추가 경고는 UI 단계, 로직은 동일) — 리롤 후 흔적 없음.
    func testShinyCanBeRerolled() {
        let s = store(shiny: true)
        XCTAssertTrue(s.currentIsShiny)
        XCTAssertTrue(s.buyFreshEgg())
        XCTAssertNil(s.state.active)
        XCTAssertFalse(s.currentIsShiny)
    }
}
