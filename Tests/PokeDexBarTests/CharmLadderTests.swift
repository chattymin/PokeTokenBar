import XCTest
@testable import PokeDexBar

/// 부적 사다리 — 값·효과·옛 세이브 이전.
@MainActor
final class CharmLadderTests: XCTestCase {
    private func makeStore(wallet: Int) -> PlayerStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("charm-\(UUID().uuidString).json")
        let store = PlayerStore(fileURL: url, rng: SeededRNG(seed: 3),
                                now: { Date(timeIntervalSince1970: 1_700_000_000) })
        store.seedForTesting(wallet: wallet, slots: 3, eggs: 0,
                             at: Date(timeIntervalSince1970: 1_700_000_000))
        return store
    }

    /// 세이브 JSON 을 만들어 디코드한다 — 이전은 디코드 자리에 살아서, 이 경로가 아니면
    /// 물어볼 수가 없다.
    private func decode(_ fields: [String: Any]) throws -> PlayerState {
        let data = try JSONSerialization.data(withJSONObject: fields)
        return try JSONDecoder().decode(PlayerState.self, from: data)
    }

    // MARK: 값

    func testEachTierCostsDoubleTheOneBelow() {
        XCTAssertEqual(CharmLadder.price(tier: 1), 250_000_000)
        XCTAssertEqual(CharmLadder.price(tier: 2), 500_000_000)
        XCTAssertEqual(CharmLadder.price(tier: 3), 1_000_000_000)
        XCTAssertEqual(CharmLadder.price(tier: 10), 250_000_000 * 512)
        XCTAssertNil(CharmLadder.price(tier: 0), "0단계는 사는 것이 아니라 미보유다")
        XCTAssertNil(CharmLadder.price(tier: CharmLadder.maxSafeTier + 1),
                     "안전 상한을 넘는 값은 없다 — 곱셈이 오버플로로 프로세스를 죽인다")
    }

    func testCumulativeIsTheSumOfEveryTierBelow() {
        for top in 1...12 {
            let summed = (1...top).compactMap { CharmLadder.price(tier: $0) }.reduce(0, +)
            XCTAssertEqual(CharmLadder.cumulative(through: top), summed, "\(top)단계 누적")
        }
        XCTAssertEqual(CharmLadder.cumulative(through: 0), 0)
    }

    // MARK: 효과

    func testTierZeroChangesNothing() {
        for item in [ShopItem.expCharm, .fortuneCharm, .shinyCharm] {
            XCTAssertEqual(CharmLadder.multiplier(item, tier: 0), 1.0, accuracy: 1e-9,
                           "\(item) 미보유는 아무 효과가 없어야 한다")
        }
        XCTAssertEqual(ShinyOdds.denominator(shinyTier: 0, rainbowCharm: false), 64)
    }

    /// **이전의 기준점.** 4단계가 옛 효과와 같아야 기존 구매자를 거기 놓는 것이 손해도
    /// 이득도 아니게 된다. 이 값이 흔들리면 이전 전체의 근거가 사라진다.
    func testTierFourReproducesTheOldCharms() {
        XCTAssertEqual(CharmLadder.multiplier(.expCharm, tier: CharmLadder.legacyTier),
                       2.0, accuracy: 1e-9, "옛 경험치 부적은 2배였다")
        XCTAssertEqual(CharmLadder.multiplier(.fortuneCharm, tier: CharmLadder.legacyTier),
                       1.5, accuracy: 1e-9, "옛 행운의 부적은 1.5배였다")
        XCTAssertEqual(ShinyOdds.denominator(shinyTier: CharmLadder.legacyTier,
                                             rainbowCharm: false),
                       48, "옛 이로치 부적은 1/48 이었다")
    }

    func testTheLadderKeepsClimbing() {
        XCTAssertGreaterThan(CharmLadder.multiplier(.expCharm, tier: 5),
                             CharmLadder.multiplier(.expCharm, tier: 4))
        XCTAssertEqual(CharmLadder.multiplier(.expCharm, tier: 8), 3.0, accuracy: 1e-9)
        // 효과는 선형인데 값은 기하급수 — 단위 이득당 비용이 매 단계 두 배다(설계 근거).
        let gainPerToken = { (tier: Int) -> Double in
            (CharmLadder.multiplier(.expCharm, tier: tier) - 1)
                / Double(CharmLadder.cumulative(through: tier))
        }
        XCTAssertGreaterThan(gainPerToken(4), gainPerToken(8),
                             "올릴수록 단위 이득당 비용이 비싸져야 경제가 스스로 멈춘다")
    }

    func testTheMultipliersReachTheGainFunctions() {
        XCTAssertEqual(PlayerStore.expGain(100, multiplier: CharmLadder.multiplier(.expCharm, tier: 4)), 200)
        XCTAssertEqual(PlayerStore.expGain(100, multiplier: CharmLadder.multiplier(.expCharm, tier: 8)), 300)
        XCTAssertEqual(PlayerStore.currencyGain(100, multiplier: CharmLadder.multiplier(.fortuneCharm, tier: 4)), 150)
        XCTAssertEqual(PlayerStore.expGain(100, multiplier: CharmLadder.multiplier(.expCharm, tier: 0)), 100,
                       "미보유면 배율이 없어야 한다")
    }

    // MARK: 이로치 분모

    func testTheShinyDenominatorFallsAndThenStopsAtTheFloor() {
        var previous = ShinyOdds.denominator(shinyTier: 0, rainbowCharm: false)
        for tier in 1...CharmLadder.maxSafeTier {
            let now = ShinyOdds.denominator(shinyTier: tier, rainbowCharm: false)
            XCTAssertLessThanOrEqual(now, previous, "\(tier)단계에서 분모가 되레 올랐다")
            XCTAssertGreaterThanOrEqual(now, ShinyOdds.floor, "\(tier)단계가 바닥을 뚫었다")
            previous = now
        }
        XCTAssertEqual(ShinyOdds.denominator(shinyTier: CharmLadder.maxSafeTier,
                                             rainbowCharm: true),
                       ShinyOdds.floor, "최고 단계 + 무지개는 바닥값에 닿는다")
    }

    /// 무지개 부적은 **단계와 무관하게** 한 번 더 깎는다 — 예전처럼 고정값이면 이로치 부적을
    /// 올리는 순간 무의미해지는 구간이 생긴다.
    func testTheRainbowCharmStillHelpsAtEveryTier() {
        for tier in 0...CharmLadder.maxSafeTier {
            let plain = ShinyOdds.denominator(shinyTier: tier, rainbowCharm: false)
            let withRainbow = ShinyOdds.denominator(shinyTier: tier, rainbowCharm: true)
            if plain > ShinyOdds.floor {
                XCTAssertLessThan(withRainbow, plain, "\(tier)단계에서 무지개가 아무 일도 안 했다")
            } else {
                XCTAssertEqual(withRainbow, ShinyOdds.floor)
            }
        }
    }

    /// 옛 무지개 부적은 분모를 1/32 로 고정했다. −8 만으로는 1/56 이라 **도감을 채운 사람이
    /// 손해를 본다** — 딸려 오는 단계가 그 간극을 정확히 메운다.
    func testTheRainbowCharmStillMeansOneInThirtyTwo() {
        XCTAssertEqual(ShinyOdds.denominator(shinyTier: CharmLadder.rainbowShinyTier,
                                             rainbowCharm: true),
                       32, "무지개 부적의 옛 효과가 그대로 나와야 한다")
    }

    // MARK: 옛 세이브 이전

    func testLegacyCharmsLandOnTierFour() throws {
        let state = try decode(["ownsExpCharm": true, "ownsFortuneCharm": true,
                                "ownsShinyCharm": true])
        XCTAssertEqual(state.charmTiers[ShopItem.expCharm.rawValue], CharmLadder.legacyTier)
        XCTAssertEqual(state.charmTiers[ShopItem.fortuneCharm.rawValue], CharmLadder.legacyTier)
        XCTAssertEqual(state.charmTiers[ShopItem.shinyCharm.rawValue], CharmLadder.legacyTier)
    }

    /// 안 산 부적은 이전이 만들어 주지 않는다 — 대조군. 이게 없으면 "전부 4단계로 채운다"는
    /// 잘못된 구현도 위 테스트를 통과한다.
    func testUnownedLegacyCharmsStayAtZero() throws {
        let state = try decode(["ownsExpCharm": true])
        XCTAssertEqual(state.charmTiers[ShopItem.expCharm.rawValue], CharmLadder.legacyTier)
        XCTAssertNil(state.charmTiers[ShopItem.fortuneCharm.rawValue])
        XCTAssertNil(state.charmTiers[ShopItem.shinyCharm.rawValue])
    }

    func testTheLegacyRainbowCharmKeepsItsOdds() throws {
        let state = try decode(["ownsRainbowCharm": true])
        XCTAssertEqual(ShinyOdds.denominator(
            shinyTier: state.charmTiers[ShopItem.shinyCharm.rawValue] ?? 0,
            rainbowCharm: state.ownsRainbowCharm), 32, "옛 무지개 부적 보유자가 손해를 봤다")
    }

    /// 옛 규칙도 "겹쳐도 32" 였다 — 둘 다 가진 세이브가 이전에서 갈라지지 않아야 한다.
    func testTheLegacyRainbowAndShinyCharmsTogetherKeepTheirOdds() throws {
        let state = try decode(["ownsRainbowCharm": true, "ownsShinyCharm": true])
        XCTAssertEqual(state.charmTiers[ShopItem.shinyCharm.rawValue],
                       CharmLadder.rainbowShinyTier, "높은 쪽을 써야 한다")
        XCTAssertEqual(ShinyOdds.denominator(
            shinyTier: state.charmTiers[ShopItem.shinyCharm.rawValue] ?? 0,
            rainbowCharm: true), 32)
    }

    /// 이전은 **한 번만** 돈다. 이미 단계가 있는 세이브를 다시 열 때 옛 불리언이 단계를
    /// 도로 4로 끌어내리면, 올린 만큼이 매 기동 사라진다.
    func testTiersAlreadySavedSurviveTheLegacyBooleans() throws {
        let state = try decode(["ownsExpCharm": true,
                                "charmTiers": [ShopItem.expCharm.rawValue: 9]])
        XCTAssertEqual(state.charmTiers[ShopItem.expCharm.rawValue], 9)
    }

    func testABrokenTierIsClampedAtTheBoundary() throws {
        let state = try decode(["charmTiers": [ShopItem.expCharm.rawValue: 9_999,
                                               ShopItem.shinyCharm.rawValue: -3]])
        XCTAssertEqual(state.charmTiers[ShopItem.expCharm.rawValue], CharmLadder.maxSafeTier,
                       "거대한 단계가 그대로 들어오면 다음 값 계산이 오버플로로 앱을 죽인다")
        XCTAssertEqual(state.charmTiers[ShopItem.shinyCharm.rawValue], 0)
        // 잘린 뒤에도 값 계산이 살아 있어야 한다(트랩 없이).
        XCTAssertNotNil(CharmLadder.price(tier: CharmLadder.maxSafeTier))
    }

    /// **상한이 실제로 안전한가.** 손으로 적은 40 은 안전하지 않았다 — 누적이 `Int.max` 를
    /// 넘겨 곱셈이 트랩으로 프로세스를 죽였다(테스트 실행이 SIGTRAP 으로 통째로 죽는다).
    /// 상한 바로 위가 정말 안 들어가는지도 같이 잠근다 — 안 그러면 너무 낮게 잡아도 통과한다.
    func testTheSafeTierIsTheLastOneThatFitsInAnInt() {
        let top = CharmLadder.maxSafeTier
        XCTAssertGreaterThan(CharmLadder.cumulative(through: top), 0, "누적이 음수면 이미 넘긴 것이다")
        XCTAssertLessThanOrEqual(CharmLadder.cumulative(through: top), Int.max)
        // 한 단계 더 갔으면 넘쳤다 — 곱셈 대신 나눗셈으로 물어본다(물어보다가 죽지 않게).
        XCTAssertLessThan(Int.max / CharmLadder.basePrice, (1 << (top + 1)) - 1,
                          "상한을 한 단계 더 올릴 여유가 남아 있다 — 상한이 너무 낮다")
    }

    // MARK: 상점 동작

    func testUpgradingSpendsTheTierPriceAndClimbsOneStep() {
        let store = makeStore(wallet: 750_000_000)   // 1단계 + 2단계 = 250M + 500M
        XCTAssertFalse(store.owns(.expCharm))
        XCTAssertEqual(store.nextCharmPrice(.expCharm), 250_000_000)

        XCTAssertTrue(store.upgradeCharm(.expCharm))
        XCTAssertEqual(store.charmTier(.expCharm), 1)
        XCTAssertTrue(store.owns(.expCharm), "한 단계라도 올렸으면 보유다")
        XCTAssertEqual(store.state.wallet, 500_000_000)
        XCTAssertEqual(store.nextCharmPrice(.expCharm), 500_000_000, "다음 단계는 두 배다")

        XCTAssertTrue(store.upgradeCharm(.expCharm))
        XCTAssertEqual(store.charmTier(.expCharm), 2)
        XCTAssertEqual(store.state.wallet, 0)

        XCTAssertFalse(store.canUpgradeCharm(.expCharm))
        XCTAssertFalse(store.upgradeCharm(.expCharm), "지갑이 모자라면 단계가 안 오른다")
        XCTAssertEqual(store.charmTier(.expCharm), 2)
    }

    /// 부적은 이제 `item.price` 로 안 판다 — 옛 경로로 사도 사다리 값이 나가야 한다.
    func testBuyingACharmGoesThroughTheLadder() {
        let store = makeStore(wallet: ShopItem.expCharm.price)
        XCTAssertTrue(store.buy(.expCharm))
        XCTAssertEqual(store.charmTier(.expCharm), 1)
        XCTAssertEqual(store.state.wallet, ShopItem.expCharm.price - 250_000_000,
                       "옛 고정가(\(ShopItem.expCharm.price))가 아니라 1단계 값이 나가야 한다")
    }

    /// 소모품은 사다리를 안 탄다 — 대조군.
    func testConsumablesStillCostTheirFixedPrice() {
        let store = makeStore(wallet: ShopItem.expCandy.price)
        XCTAssertNil(store.nextCharmPrice(.expCandy))
        XCTAssertTrue(store.buy(.expCandy))
        XCTAssertEqual(store.count(of: .expCandy), 1)
        XCTAssertEqual(store.state.wallet, 0)
    }

    /// 무지개 부적은 사다리를 안 탄다(팔지 않는 물건이다).
    func testTheRainbowCharmHasNoTier() {
        XCTAssertFalse(CharmLadder.isTiered(.rainbowCharm))
        let store = makeStore(wallet: 0)
        XCTAssertNil(store.nextCharmPrice(.rainbowCharm))
        XCTAssertFalse(store.canUpgradeCharm(.rainbowCharm))
    }

    // MARK: 표시

    /// 상점 줄이 **지금 값과 다음 값**을 함께 말한다 — 이로치만 분모로.
    func testTheShopLineNamesBothTheCurrentAndTheNextStep() {
        let l = L(.en)
        XCTAssertEqual(ShopTabView.charmEffectLine(.expCharm, tier: 4, l: l), "2.00× → 2.25×")
        XCTAssertEqual(ShopTabView.charmEffectLine(.shinyCharm, tier: 0, l: l), "1/64 → 1/59")
        let top = String(format: "%.2f×", CharmLadder.multiplier(.expCharm, tier: CharmLadder.maxSafeTier))
        XCTAssertEqual(ShopTabView.charmEffectLine(.expCharm, tier: CharmLadder.maxSafeTier, l: l),
                       top, "더 올릴 데가 없으면 화살표가 없다")
    }
}
