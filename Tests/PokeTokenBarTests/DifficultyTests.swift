import XCTest
@testable import PokeTokenBar

/// 난이도 배율 — 검증 배율이 표시가 아니라 **실제 동작**을 바꾸는지 확인한다.
/// 핵심 형태: 같은 토큰 입력에 배율만 다르게 줘서 결과(진화/부화/구매 성사)가 갈리는지 본다.
@MainActor
final class DifficultyTests: XCTestCase {

    private func line() -> EvoLine {
        var names: [Int: [String: String]] = [:]
        for id in [1, 2, 3] { names[id] = ["en": "P\(id)"] }
        return EvoLine(baseID: 1,
                       tree: EvoNode(speciesID: 1, children: [EvoNode(speciesID: 2, children: [EvoNode(speciesID: 3, children: [])])]),
                       rarity: .common, names: names)
    }

    /// `used` 를 주면 지갑 잔액이 시드된 상태 파일로 시작한다(ShopTests 와 같은 JSON 시드 패턴).
    private func store(growth: Double = 1.0, shop: Double = 1.0, used: Int = 0) -> CompanionStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ptb-diff-\(UUID().uuidString).json")
        let json = "{\"installBaselineSet\":true,\"usedSinceInstall\":\(used),\"spentTokens\":0,"
            + "\"lastDate\":\"d\",\"dex\":[],\"collectedFinals\":[]}"
        try? json.data(using: .utf8)!.write(to: url)
        let suite = UserDefaults(suiteName: "ptb-diff-\(UUID().uuidString)")!
        suite.set(growth, forKey: "growthDifficulty")
        suite.set(shop, forKey: "shopDifficulty")
        return CompanionStore(provider: StubDiffProvider(value: line()),
                              clock: { Date(timeIntervalSince1970: 1_700_000_000) },
                              fileURL: url, rng: SeededDiffRNG(seed: 7),
                              dittoDisguiseRollingEnabled: false,
                              defaults: suite)
    }

    private func hatched(growth: Double = 1.0, shop: Double = 1.0, used: Int = 0) async -> CompanionStore {
        let s = store(growth: growth, shop: shop, used: used)
        await s.hatch(baseID: 1)
        return s
    }

    // MARK: 1. 진화 — 같은 토큰, 다른 결과 (표시가 아니라 상태 전이)

    func testSameTokensEvolveOnlyWhenDifficultyLowered() async {
        let baseThreshold = PokemonBalance.phaseThreshold(rarity: .common, totalForms: 3, stageIndex: 0)
        let half = baseThreshold / 2

        let normal = await hatched(growth: 1.0)
        normal.applyUsage(half)
        XCTAssertEqual(normal.state.active?.stageIndex, 0, "1.0x: 절반으론 진화하면 안 된다")
        XCTAssertEqual(normal.state.active?.currentID, 1)

        let easy = await hatched(growth: 0.5)
        easy.applyUsage(half)
        XCTAssertEqual(easy.state.active?.stageIndex, 1, "0.5x: 같은 절반으로 진화해야 한다")
        XCTAssertEqual(easy.state.active?.currentID, 2, "실제 종이 바뀌었는가(표시가 아니라 상태)")
    }

    func testHarderDifficultyBlocksEvolutionThatWouldOtherwiseHappen() async {
        let baseThreshold = PokemonBalance.phaseThreshold(rarity: .common, totalForms: 3, stageIndex: 0)

        let normal = await hatched(growth: 1.0)
        normal.applyUsage(baseThreshold)
        XCTAssertEqual(normal.state.active?.stageIndex, 1, "1.0x: 정확히 임계면 진화")

        let hard = await hatched(growth: 2.0)
        hard.applyUsage(baseThreshold)
        XCTAssertEqual(hard.state.active?.stageIndex, 0, "2.0x: 같은 양으론 진화 못 한다")
    }

    /// 표시값(tokensToNext/progress)이 상태 전이와 같은 임계를 쓰는가 — 둘이 어긋나면
    /// "다음 단계까지" 문구만 바뀌고 실제 진화는 안 바뀌는 표면적 구현이 된다.
    func testDisplayedTokensToNextMatchesTheThresholdThatActuallyEvolves() async {
        let s = await hatched(growth: 0.5)
        let shown = s.tokensToNext
        XCTAssertEqual(shown, PokemonBalance.phaseThreshold(rarity: .common, totalForms: 3, stageIndex: 0) / 2,
                       "표시값이 배율을 반영")
        // 표시된 양보다 1 적게 주면 진화 안 하고, 딱 맞추면 진화한다 → 표시 = 실제 임계.
        s.applyUsage(shown - 1)
        XCTAssertEqual(s.state.active?.stageIndex, 0)
        XCTAssertEqual(s.tokensToNext, 1, "남은 양도 배율 기준으로 줄어든다")
        s.applyUsage(1)
        XCTAssertEqual(s.state.active?.stageIndex, 1, "표시된 양을 채우면 실제로 진화한다")
    }

    // MARK: 2. 부화 — 알이 실제로 깨지는 지점이 바뀌는가

    func testEggHatchPointMovesWithDifficulty() async {
        let half = PokemonBalance.eggHatchThreshold / 2

        let normal = store(growth: 1.0)
        normal.update(todayTokensByProvider: ["t": 0], todayDate: "d1", monthTotal: 0,
                      burnTier: .idle, limitWarning: false, hasUsageData: true)
        normal.update(todayTokensByProvider: ["t": half], todayDate: "d1", monthTotal: 0,
                      burnTier: .idle, limitWarning: false, hasUsageData: true)
        await normal.hatchIfNeeded()
        XCTAssertNil(normal.state.active, "1.0x: 절반으론 안 깨진다")

        let easy = store(growth: 0.5)
        easy.update(todayTokensByProvider: ["t": 0], todayDate: "d1", monthTotal: 0,
                    burnTier: .idle, limitWarning: false, hasUsageData: true)
        easy.update(todayTokensByProvider: ["t": half], todayDate: "d1", monthTotal: 0,
                    burnTier: .idle, limitWarning: false, hasUsageData: true)
        await easy.hatchIfNeeded()
        XCTAssertNotNil(easy.state.active, "0.5x: 같은 양으로 부화")
    }

    // MARK: 3. 상점 — 결제 금액과 구매 가능 판정이 바뀌는가

    func testShopGateAndChargedAmountFollowDifficulty() async {
        let halfPrice = RareCandy.price / 2

        let normal = await hatched(shop: 1.0, used: halfPrice)
        XCTAssertFalse(normal.canBuy(.rareCandy), "1.0x: 절반 잔액으론 못 산다")

        let cheap = await hatched(shop: 0.5, used: halfPrice)
        XCTAssertTrue(cheap.canBuy(.rareCandy), "0.5x: 같은 잔액으로 살 수 있다")
        XCTAssertTrue(cheap.buy(.rareCandy))
        XCTAssertEqual(cheap.state.spentTokens, halfPrice, "실제 차감액도 배율 적용")
        XCTAssertEqual(cheap.itemCount(.rareCandy), 1, "물건이 실제로 들어왔는가")
    }

    func testEggPriceScalesAndIsActuallyCharged() async {
        let s = await hatched(shop: 0.5, used: FreshEgg.price)
        XCTAssertEqual(s.price(of: .egg(nil)), FreshEgg.price / 2)
        XCTAssertTrue(s.buyEgg(Rarity?.none))
        XCTAssertEqual(s.state.spentTokens, FreshEgg.price / 2)
    }

    // MARK: 4. 두 슬라이더는 서로 독립인가 (등급 알 가격이 graduationTotal 비율에서 파생되므로 중요)

    func testGrowthSliderDoesNotMoveShopPricesAndViceVersa() async {
        let growthOnly = await hatched(growth: 0.1, shop: 1.0)
        XCTAssertEqual(growthOnly.price(of: .item(.rareCandy)), RareCandy.price, "성장 배율이 가격을 건드리면 안 된다")
        XCTAssertEqual(growthOnly.price(of: .egg(.rare)), FreshEgg.price(guaranteeing: .rare))

        let shopOnly = await hatched(growth: 1.0, shop: 0.1)
        XCTAssertEqual(shopOnly.tokensToNext,
                       PokemonBalance.phaseThreshold(rarity: .common, totalForms: 3, stageIndex: 0),
                       "상점 배율이 성장 임계를 건드리면 안 된다")
    }

    /// 등급 알의 상대 가격비(1 : 2.5 : 4)는 배율과 무관하게 보존돼야 한다.
    func testGradedEggRatioSurvivesScaling() async {
        let s = await hatched(shop: 0.4)
        let plain = Double(s.price(of: .egg(nil)))
        XCTAssertEqual(Double(s.price(of: .egg(.uncommon))) / plain, 2.5, accuracy: 0.001)
        XCTAssertEqual(Double(s.price(of: .egg(.rare))) / plain, 4.0, accuracy: 0.001)
    }

    // MARK: 5. 라이브 반영 — 재시작 없이 그 자리에서

    func testLoweringDifficultyLiveTriggersEvolutionImmediately() async {
        let s = await hatched(growth: 1.0)
        let baseThreshold = PokemonBalance.phaseThreshold(rarity: .common, totalForms: 3, stageIndex: 0)
        s.applyUsage(baseThreshold - 1)
        XCTAssertEqual(s.state.active?.stageIndex, 0, "아직 진화 전")

        s.setGrowthDifficulty(0.5)   // 슬라이더를 내리는 순간
        XCTAssertEqual(s.state.active?.stageIndex, 1, "폴링을 기다리지 않고 즉시 진화")
    }

    func testShopPriceChangesLiveWithoutRestart() async {
        let s = await hatched(shop: 1.0)
        XCTAssertEqual(s.price(of: .item(.rareCandy)), RareCandy.price)
        s.setShopDifficulty(0.5)
        XCTAssertEqual(s.price(of: .item(.rareCandy)), RareCandy.price / 2)
    }

    func testDifficultyPersistsToDefaults() async {
        let s = await hatched()
        s.setGrowthDifficulty(0.3)
        s.setShopDifficulty(1.7)
        XCTAssertEqual(s.growthDifficulty, 0.3, accuracy: 0.0001)
        XCTAssertEqual(s.shopDifficulty, 1.7, accuracy: 0.0001)
    }

    // MARK: 6. 클램프 — 외부에서 쓰인 쓰레기 값

    /// 경계값은 상수에서 파생한다 — 범위를 조정해도 테스트가 같이 따라오게(하드코딩 드리프트 방지).
    func testGarbageDefaultsAreClamped() {
        let lo = PokemonBalance.difficultyRange.lowerBound
        let hi = PokemonBalance.difficultyRange.upperBound
        XCTAssertEqual(PokemonBalance.clampDifficulty(0), lo, accuracy: 1e-9)
        XCTAssertEqual(PokemonBalance.clampDifficulty(-5), lo, accuracy: 1e-9)
        XCTAssertEqual(PokemonBalance.clampDifficulty(hi * 10), hi, accuracy: 1e-9)
        // 유한하지 않은 값은 "아주 어려움"이 아니라 손상된 값 → 상·하한이 아니라 기본값으로 되돌린다.
        XCTAssertEqual(PokemonBalance.clampDifficulty(.nan), PokemonBalance.defaultDifficulty, accuracy: 1e-9)
        XCTAssertEqual(PokemonBalance.clampDifficulty(.infinity), PokemonBalance.defaultDifficulty, accuracy: 1e-9)
        XCTAssertEqual(PokemonBalance.clampDifficulty(-.infinity), PokemonBalance.defaultDifficulty, accuracy: 1e-9)
    }

    /// 배율 0 이 저장돼 있어도 임계가 0 이 되지 않는다(진행률 0 나눗셈·퇴화 루프 방지).
    func testZeroInDefaultsCannotProduceZeroThreshold() async {
        let s = await hatched(growth: 0)
        XCTAssertEqual(s.growthDifficulty, PokemonBalance.difficultyRange.lowerBound, accuracy: 1e-9)
        XCTAssertGreaterThan(s.tokensToNext, 0)
        XCTAssertGreaterThan(s.eggTokensToHatch, 0)
    }

    /// 가장 낮은 배율에서도 어떤 임계·가격도 0 으로 무너지지 않는다(가장 작은 기준값이 알 5M).
    func testNothingCollapsesToZeroAtMinimumDifficulty() async {
        let lo = PokemonBalance.difficultyRange.lowerBound
        XCTAssertGreaterThan(PokemonBalance.scaled(PokemonBalance.eggHatchThreshold, by: lo), 0)
        for rarity in [Rarity.common, .uncommon, .rare, .legendary] {
            for k in 1...3 {
                for i in 0..<k {
                    let t = PokemonBalance.scaled(
                        PokemonBalance.phaseThreshold(rarity: rarity, totalForms: k, stageIndex: i), by: lo)
                    XCTAssertGreaterThan(t, 0, "rarity=\(rarity) k=\(k) i=\(i)")
                }
            }
        }
        let s = await hatched(shop: lo)
        for entry in s.shopEntries { XCTAssertGreaterThan(s.price(of: entry), 0, "\(entry)") }
    }

    // MARK: 7. 슬라이더 위치 매핑 (로그) + 퍼센트 표기

    func testPositionRoundTripsThroughDifficulty() {
        for value in [0.001, 0.01, 0.1, 0.5, 1.0, 2.0, 5.0, 20.0] {
            let back = PokemonBalance.difficulty(atPosition: PokemonBalance.difficultyPosition(value))
            XCTAssertEqual(back, value, accuracy: value * 0.02, "value=\(value)")
        }
    }

    func testPositionEndpointsMapToRangeBounds() {
        XCTAssertEqual(PokemonBalance.difficulty(atPosition: 0),
                       PokemonBalance.difficultyRange.lowerBound, accuracy: 1e-9)
        XCTAssertEqual(PokemonBalance.difficulty(atPosition: 1),
                       PokemonBalance.difficultyRange.upperBound, accuracy: 1e-6)
        XCTAssertEqual(PokemonBalance.difficultyPosition(PokemonBalance.difficultyRange.lowerBound), 0, accuracy: 1e-9)
        XCTAssertEqual(PokemonBalance.difficultyPosition(PokemonBalance.difficultyRange.upperBound), 1, accuracy: 1e-9)
    }

    /// 로그 슬라이더에서도 기본값(100%)으로 되돌릴 수 있어야 한다 — 스냅이 없으면 도달 불가.
    func testDefaultIsReachableByDragging() {
        let exactPosition = PokemonBalance.difficultyPosition(1.0)
        for offset in [-0.009, -0.005, 0.0, 0.005, 0.009] {
            XCTAssertEqual(PokemonBalance.difficulty(atPosition: exactPosition + offset), 1.0,
                           accuracy: 1e-9, "offset=\(offset) 에서 100% 로 붙어야 한다")
        }
    }

    /// 스냅 결과는 유효숫자 2자리 — 표시가 1.0473 같은 값으로 지저분해지지 않는다.
    func testSnapKeepsTwoSignificantDigits() {
        XCTAssertEqual(PokemonBalance.snapDifficulty(1.234), 1.2, accuracy: 1e-9)
        XCTAssertEqual(PokemonBalance.snapDifficulty(15.7), 16, accuracy: 1e-9)
        XCTAssertEqual(PokemonBalance.snapDifficulty(0.0123), 0.012, accuracy: 1e-9)
    }

    func testPercentFormatting() {
        let l = L(.en)
        XCTAssertEqual(l.difficultyValue(1.0), "100%")
        XCTAssertEqual(l.difficultyValue(0.5), "50%")
        XCTAssertEqual(l.difficultyValue(20), "2000%")
        XCTAssertEqual(l.difficultyValue(0.05), "5.0%")
        // 작은 쪽이 전부 "0%" 로 뭉개지지 않는가 — 범위 하한이 0.01% 라 자릿수가 필요하다.
        XCTAssertEqual(l.difficultyValue(0.0001), "0.01%")
        XCTAssertNotEqual(l.difficultyValue(0.0001), l.difficultyValue(0.0005))
    }
}

// MARK: 스텁

private struct StubDiffProvider: PokeProviding {
    let value: EvoLine
    func line(baseSpeciesID: Int) async throws -> EvoLine { value }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [BaseSpecies(id: value.baseID, captureRate: 255)] }
}

private struct SeededDiffRNG: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
