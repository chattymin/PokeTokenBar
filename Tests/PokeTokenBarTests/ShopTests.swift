import XCTest
@testable import PokeTokenBar

// MARK: 상점 (재화 = usedSinceInstall − spentTokens, 이상한 사탕 구매)

/// 라인 로딩이 필요 없는 상점 테스트용 provider(항상 throw — 지갑/구매는 라인과 무관).
private struct ShopNoProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

@MainActor
final class ShopTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    /// usedSinceInstall/spentTokens 를 직접 지정한 상태 파일을 만들어 로드 — 지갑 잔액을 결정적으로
    /// 세팅(update() 의 delta 적립 경로를 우회). testCannotUseWhileLineUnloaded 와 동일한 JSON 시드 패턴.
    private func store(used: Int, spent: Int = 0, rareCandy: Int = 0,
                       file: String = #filePath) -> CompanionStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("shop-\(UUID().uuidString).json")
        let inv = rareCandy > 0 ? ",\"inventory\":{\"rareCandy\":\(rareCandy)}" : ""
        let json = "{\"installBaselineSet\":true,\"usedSinceInstall\":\(used),\"spentTokens\":\(spent),"
            + "\"lastDate\":\"d\",\"dex\":[],\"collectedFinals\":[]\(inv)}"
        try? json.data(using: .utf8)!.write(to: url)
        return CompanionStore(provider: ShopNoProvider(), clock: { self.now }, fileURL: url, rng: SeededRNG(seed: 1))
    }

    // MARK: 잔액 계산

    func testAvailableEqualsUsedWhenNothingSpent() {
        XCTAssertEqual(store(used: 1_000_000_000).availableTokens, 1_000_000_000)
    }

    func testAvailableSubtractsSpent() {
        XCTAssertEqual(store(used: 1_000_000_000, spent: 300_000_000).availableTokens, 700_000_000)
    }

    /// spent > used(비정상 상태 파일)이어도 음수로 새지 않는다(max 가드).
    func testAvailableNeverNegative() {
        XCTAssertEqual(store(used: 100_000_000, spent: 500_000_000).availableTokens, 0)
    }

    /// 하위호환: spentTokens 키 없는 구버전 저장 → 0 으로 로드(잔액 = used).
    func testDecodesWithoutSpentTokens() throws {
        let json = #"{"installBaselineSet":true,"usedSinceInstall":900,"lastDate":"d","dex":[]}"#
        let s = try JSONDecoder().decode(CompanionState.self, from: Data(json.utf8))
        XCTAssertEqual(s.spentTokens, 0)
        XCTAssertEqual(s.usedSinceInstall, 900)
    }

    func testSpentTokensRoundTrip() throws {
        var st = CompanionState()
        st.usedSinceInstall = 1000
        st.spentTokens = 400
        let round = try JSONDecoder().decode(CompanionState.self, from: JSONEncoder().encode(st))
        XCTAssertEqual(round.spentTokens, 400)
    }

    // MARK: 구매 가능 판정 (경계)

    func testCanBuyAtExactPrice() {
        XCTAssertTrue(store(used: RareCandy.price).canBuyRareCandy)
    }

    func testCannotBuyOneBelowPrice() {
        XCTAssertFalse(store(used: RareCandy.price - 1).canBuyRareCandy)
    }

    // MARK: 구매 (차감 + 적립 + 영속)

    func testBuyDebitsWalletAndCreditsInventory() {
        let s = store(used: 1_000_000_000)
        XCTAssertTrue(s.buyRareCandy())
        XCTAssertEqual(s.rareCandyCount, 1)
        XCTAssertEqual(s.state.spentTokens, RareCandy.price)
        XCTAssertEqual(s.availableTokens, 1_000_000_000 - RareCandy.price)
        XCTAssertEqual(s.state.usedSinceInstall, 1_000_000_000, "성장 미터(usedSinceInstall)는 불변")
    }

    /// 잔액 부족이면 no-op — 인벤토리·지출 원장 불변, false 반환.
    func testBuyInsufficientIsNoOp() {
        let s = store(used: 400_000_000)
        XCTAssertFalse(s.buyRareCandy())
        XCTAssertEqual(s.rareCandyCount, 0)
        XCTAssertEqual(s.state.spentTokens, 0)
    }

    /// 여러 번 구매하면 잔액이 바닥날 때까지만 성공(가드가 매번 재평가).
    func testMultipleBuysUntilBroke() {
        let s = store(used: 1_200_000_000)          // 2개까지 가능(1B), 3번째 실패(잔액 200M)
        XCTAssertTrue(s.buyRareCandy())
        XCTAssertTrue(s.buyRareCandy())
        XCTAssertFalse(s.buyRareCandy())
        XCTAssertEqual(s.rareCandyCount, 2)
        XCTAssertEqual(s.state.spentTokens, 2 * RareCandy.price)
        XCTAssertEqual(s.availableTokens, 200_000_000)
    }

    /// 구매는 이미 가진 사탕에 합산된다(무료 지급분과 같은 인벤토리).
    func testBuyAddsToExistingStock() {
        let s = store(used: 1_000_000_000, rareCandy: 3)
        XCTAssertTrue(s.buyRareCandy())
        XCTAssertEqual(s.rareCandyCount, 4)
        XCTAssertEqual(s.ownedItems.first?.kind, .rareCandy)
        XCTAssertEqual(s.ownedItems.first?.count, 4)
    }

    /// [영속] 재시작(같은 파일 재로드) 후 지출·재고가 유지된다.
    func testBuyPersistsAcrossRestart() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("shop-persist-\(UUID().uuidString).json")
        let json = "{\"installBaselineSet\":true,\"usedSinceInstall\":1000000000,\"spentTokens\":0,"
            + "\"lastDate\":\"d\",\"dex\":[],\"collectedFinals\":[]}"
        try? json.data(using: .utf8)!.write(to: url)
        let s1 = CompanionStore(provider: ShopNoProvider(), clock: { self.now }, fileURL: url, rng: SeededRNG(seed: 1))
        XCTAssertTrue(s1.buyRareCandy())

        let s2 = CompanionStore(provider: ShopNoProvider(), clock: { self.now }, fileURL: url, rng: SeededRNG(seed: 1))
        XCTAssertEqual(s2.rareCandyCount, 1, "재고 영속")
        XCTAssertEqual(s2.state.spentTokens, RareCandy.price, "지출 영속")
        XCTAssertEqual(s2.availableTokens, 1_000_000_000 - RareCandy.price)
    }
}
