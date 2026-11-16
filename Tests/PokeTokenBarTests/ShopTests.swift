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
        return CompanionStore(provider: ShopNoProvider(), clock: { self.now }, fileURL: url, rng: SeededRNG(seed: 1), difficulty: 1)
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
        let s1 = CompanionStore(provider: ShopNoProvider(), clock: { self.now }, fileURL: url, rng: SeededRNG(seed: 1), difficulty: 1)
        XCTAssertTrue(s1.buyRareCandy())

        let s2 = CompanionStore(provider: ShopNoProvider(), clock: { self.now }, fileURL: url, rng: SeededRNG(seed: 1), difficulty: 1)
        XCTAssertEqual(s2.rareCandyCount, 1, "재고 영속")
        XCTAssertEqual(s2.state.spentTokens, RareCandy.price, "지출 영속")
        XCTAssertEqual(s2.availableTokens, 1_000_000_000 - RareCandy.price)
    }

    // MARK: 수량 구매 (buy(_:count:) / maxBuyCount)

    /// 최대 수량 = 잔액 ÷ 가격(내림). 가격 미만이면 0.
    func testMaxBuyCountIsFloorOfWalletOverPrice() {
        XCTAssertEqual(store(used: 1_200_000_000).maxBuyCount(.rareCandy), 2)
        XCTAssertEqual(store(used: 1_200_000_000).maxBuyCount(.mint), 6, "the Mint is back (2026-11-09)")
        XCTAssertEqual(store(used: RareCandy.price - 1).maxBuyCount(.rareCandy), 0)
    }

    /// 보유형은 잔액이 여러 개 값이어도 최대 1, 보유 후엔 0(재구매 불가).
    func testMaxBuyCountCapsPassiveAtOne() {
        let s = store(used: 10 * ShinyCharm.price)
        XCTAssertEqual(s.maxBuyCount(.shinyCharm), 1)
        XCTAssertFalse(s.buy(.shinyCharm, count: 2), "보유형 2개 구매는 거부")
        XCTAssertEqual(s.state.spentTokens, 0)
        XCTAssertTrue(s.buy(.shinyCharm))
        XCTAssertEqual(s.maxBuyCount(.shinyCharm), 0)
    }

    /// N개 구매 = 지갑 price×N 차감, 인벤토리 +N(기존 재고에 합산), 성장 미터 불변.
    func testBuyCountDebitsTotalAndCreditsInventory() {
        let s = store(used: 2_000_000_000, rareCandy: 1)
        XCTAssertTrue(s.buy(.rareCandy, count: 3))
        XCTAssertEqual(s.rareCandyCount, 4)
        XCTAssertEqual(s.state.spentTokens, 3 * RareCandy.price)
        XCTAssertEqual(s.availableTokens, 2_000_000_000 - 3 * RareCandy.price)
        XCTAssertEqual(s.state.usedSinceInstall, 2_000_000_000, "성장 미터(usedSinceInstall)는 불변")
    }

    /// 잔액을 정확히 소진하는 최대 수량까지는 성공.
    func testBuyExactlyMaxCountEmptiesWallet() {
        let s = store(used: 3 * RareCandy.price)
        XCTAssertTrue(s.buy(.rareCandy, count: s.maxBuyCount(.rareCandy)))
        XCTAssertEqual(s.rareCandyCount, 3)
        XCTAssertEqual(s.availableTokens, 0)
    }

    /// 잔액을 넘는 수량은 부분 구매 없이 전부 거부 — 살 수 있는 만큼만 사고 끝나면 안 된다.
    func testBuyCountAboveAffordableIsNoOp() {
        let s = store(used: 1_200_000_000)   // 2개까지 가능
        XCTAssertFalse(s.buy(.rareCandy, count: 3))
        XCTAssertEqual(s.rareCandyCount, 0)
        XCTAssertEqual(s.state.spentTokens, 0)
    }

    /// 0·음수 수량은 no-op(음수 차감으로 잔액이 늘어나는 경로 차단).
    func testBuyNonPositiveCountIsNoOp() {
        let s = store(used: 1_000_000_000)
        XCTAssertFalse(s.buy(.rareCandy, count: 0))
        XCTAssertFalse(s.buy(.rareCandy, count: -1))
        XCTAssertEqual(s.rareCandyCount, 0)
        XCTAssertEqual(s.state.spentTokens, 0)
    }

    /// [영속] 수량 구매도 재시작 후 지출·재고가 유지된다.
    func testBuyCountPersistsAcrossRestart() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("shop-bulk-\(UUID().uuidString).json")
        let json = "{\"installBaselineSet\":true,\"usedSinceInstall\":1000000000,\"spentTokens\":0,"
            + "\"lastDate\":\"d\",\"dex\":[],\"collectedFinals\":[]}"
        try? json.data(using: .utf8)!.write(to: url)
        let s1 = CompanionStore(provider: ShopNoProvider(), clock: { self.now }, fileURL: url, rng: SeededRNG(seed: 1), difficulty: 1)
        XCTAssertTrue(s1.buy(.rareCandy, count: 2))

        let s2 = CompanionStore(provider: ShopNoProvider(), clock: { self.now }, fileURL: url, rng: SeededRNG(seed: 1), difficulty: 1)
        XCTAssertEqual(s2.itemCount(.rareCandy), 2, "재고 영속")
        XCTAssertEqual(s2.state.spentTokens, 2 * RareCandy.price, "지출 영속")
    }

    // MARK: 정렬 (가격 저렴한 순 + 구매 완료 보유형 맨 아래)

    /// 상점 목록은 가격 오름차순(사탕 500M < 이로치 부적 3B). The Mint is back with the Rare Candy's neighbours.
    func testItemsSortedByPriceAscending() {
        let items = store(used: 0).purchasableItems
        XCTAssertEqual(items, [.mint, .rareCandy, .greatBall, .ultraBall, .shinyCharm])
        XCTAssertFalse(ItemKind.mint.isRetired)
        let prices = items.compactMap(\.shopPrice)
        XCTAssertEqual(prices, prices.sorted(), "shopPrice 오름차순 — 가격 상수가 바뀌어도 정렬 불변식 유지")
    }

    /// A passive item bought (the Shiny Charm) leaves the Shop: it is in the Bag, and it cannot be bought twice.
    func testOwnedPassiveLeavesTheShop() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("shop-sort-\(UUID().uuidString).json")
        let json = "{\"installBaselineSet\":true,\"usedSinceInstall\":0,\"spentTokens\":0,"
            + "\"lastDate\":\"d\",\"dex\":[],\"collectedFinals\":[],\"inventory\":{\"shinyCharm\":1}}"
        try? json.data(using: .utf8)!.write(to: url)
        let s = CompanionStore(provider: ShopNoProvider(), clock: { self.now }, fileURL: url, rng: SeededRNG(seed: 1), difficulty: 1)
        XCTAssertTrue(s.itemCount(.shinyCharm) > 0)
        XCTAssertFalse(s.purchasableItems.contains(.shinyCharm))
        XCTAssertFalse(s.shopEntries.contains(.item(.shinyCharm)))
        XCTAssertTrue(s.ownedItems.contains { $0.kind == .shinyCharm }, "in the Bag")
    }

    // MARK: shopEntries: the Shop in sections (the owner, 2026-11-05: "range mieux la boutique")

    /// The eggs, then what helps the Pokémon raised, then the dungeons' items, then what is kept for good, each section
    /// by price. The order is the sections', not one price list across them, where a ball fell between two eggs.
    func testShopEntriesGoBySectionThenPrice() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("shop-entries-\(UUID().uuidString).json")
        let mon = "{\"baseID\":10,\"pathIDs\":[10],\"stageIndex\":0,\"usedAtStage\":200000000,"
            + "\"rarity\":\"common\",\"totalForms\":3,\"isShiny\":false}"
        let json = "{\"installBaselineSet\":true,\"usedSinceInstall\":5000000000,\"spentTokens\":0,"
            + "\"lastDate\":\"d\",\"active\":\(mon),\"dex\":[],\"collectedFinals\":[]}"
        try? json.data(using: .utf8)!.write(to: url)
        let s = CompanionStore(provider: ShopNoProvider(), clock: { self.now }, fileURL: url, rng: SeededRNG(seed: 1), difficulty: 1)
        XCTAssertTrue(s.hasActive)
        XCTAssertEqual(s.shopEntries, Self.sectioned)
        XCTAssertEqual(s.shopSections.map(\.section), [.eggs, .raising, .dungeons, .keptForGood])
        for group in s.shopSections {
            let prices = group.entries.map(\.price)
            XCTAssertEqual(prices, prices.sorted(), "\(group.section) by price")
        }
        XCTAssertEqual(s.shopSections.flatMap(\.entries), s.shopEntries)
    }

    private static let sectioned: [ShopEntry] = [
        .egg(nil), .egg(.uncommon), .egg(.rare),      // 1B, 2.5B, 4B
        .item(.rareCandy),                            // 500M
        .item(.mint), .item(.greatBall), .item(.ultraBall),   // 200M, 2.5B, 4B: the Mint with the dungeons' items
        .item(.shinyCharm),                           // 3B
    ]

    /// While incubating, the three eggs stay in the Shop and can be bought: they wait in the Bag, and the egg being
    /// incubated is left alone.
    func testShopEggsCanBeBoughtWhileIncubating() {
        let s = store(used: 10_000_000_000)   // active 없음, 잔액은 세 알 가격의 합 이상
        XCTAssertFalse(s.hasActive)
        XCTAssertEqual(s.shopEntries, Self.sectioned)
        for tier in FreshEgg.shopTiers {
            XCTAssertTrue(s.shopEntries.contains(.egg(tier)), "알 상태에서도 \(tier?.rawValue ?? "기본") 알은 노출 유지")
            XCTAssertTrue(s.buyEgg(tier), "\(tier?.rawValue ?? "기본") 알")
            XCTAssertEqual(s.itemCount(ItemKind(shopEgg: tier)!), 1, "in the Bag")
        }
        XCTAssertFalse(s.hasActive)
        XCTAssertNil(s.state.eggTier, "the egg being incubated keeps its own guarantee")
        XCTAssertEqual(s.availableTokens, 10_000_000_000 - FreshEgg.shopTiers.map { s.price(of: .egg($0)) }.reduce(0, +))
    }
}
