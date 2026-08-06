import XCTest
@testable import PokeDexBar

/// 리본 — **얻는 기준은 시간, 생산 주기는 토큰**. 두 축이 섞이면 앱을 켜 두는 쪽에 보상이 간다.
final class RibbonTests: XCTestCase {
    func testNoRibbonBeforeADayTogether() {
        XCTAssertNil(Ribbon.earned(partnerSeconds: 0))
        XCTAssertNil(Ribbon.earned(partnerSeconds: 86_399))
    }

    func testEachTierNeedsItsOwnTime() {
        XCTAssertEqual(Ribbon.earned(partnerSeconds: 86_400), .bond)
        XCTAssertEqual(Ribbon.earned(partnerSeconds: 7 * 86_400), .trust)
        XCTAssertEqual(Ribbon.earned(partnerSeconds: 30 * 86_400), .kinship)
        XCTAssertEqual(Ribbon.earned(partnerSeconds: 90 * 86_400), .lifelong)
    }

    /// 최고 단계를 넘겨도 그대로 유지된다 — 더 위가 없다고 리본이 사라지면 안 된다.
    func testStaysAtTheTopTier() {
        XCTAssertEqual(Ribbon.earned(partnerSeconds: 9_999 * 86_400), .lifelong)
        XCTAssertNil(Ribbon.next(after: 9_999 * 86_400))
    }

    /// 단계가 오를수록 사탕이 빨리 나와야 한다 — 이게 뒤집히면 오래 함께한 게 손해가 된다.
    func testHigherTiersProduceFaster() {
        let sorted = Ribbon.allCases.sorted()
        for (lower, higher) in zip(sorted, sorted.dropFirst()) {
            XCTAssertGreaterThan(lower.tokensPerCandy, higher.tokensPerCandy,
                                 "\(higher) 가 \(lower) 보다 느리게 만든다")
            XCTAssertLessThan(lower.requiredPartnerSeconds, higher.requiredPartnerSeconds)
        }
    }

    func testNextTierReportsWhatIsLeft() {
        let next = Ribbon.next(after: 0)
        XCTAssertEqual(next?.ribbon, .bond)
        XCTAssertEqual(next?.remaining, 86_400)
        XCTAssertEqual(Ribbon.next(after: 86_400)?.ribbon, .trust)
    }

    /// 개체에서 바로 읽을 수 있어야 한다 — 리본은 저장하지 않고 함께한 시간에서 파생된다.
    func testIndividualDerivesItsRibbonFromTimeTogether() {
        let start = Date(timeIntervalSince1970: 0)
        var individual = Individual(baseID: 1, speciesID: 1, pathIDs: [1], nature: .serious,
                                    obtainedAt: start, grade: .common)
        XCTAssertNil(individual.ribbon(at: start))
        individual.partnerSeconds = 8 * 86_400
        XCTAssertEqual(individual.ribbon(at: start), .trust)
    }
}

/// 사탕 산출 — 토큰이 쌓이면 나오고, 남은 진행분은 버리지 않는다.
final class CandyYieldTests: XCTestCase {
    func testNothingBelowTheThreshold() {
        let out = PlayerStore.candyYield(progress: 149_999_999, per: 150_000_000)
        XCTAssertEqual(out.count, 0)
        XCTAssertEqual(out.remainder, 149_999_999, "모자란 진행분을 버리면 안 된다")
    }

    func testExactlyAtTheThreshold() {
        let out = PlayerStore.candyYield(progress: 150_000_000, per: 150_000_000)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out.remainder, 0)
    }

    /// 앱을 오래 꺼 뒀다 켜서 델타가 크면 한 번에 여러 개가 나온다.
    func testABigDeltaProducesSeveral() {
        let out = PlayerStore.candyYield(progress: 1_000_000_000, per: 150_000_000)
        XCTAssertEqual(out.count, 6)
        XCTAssertEqual(out.remainder, 100_000_000)
    }

    func testGuardsAgainstNonsense() {
        XCTAssertEqual(PlayerStore.candyYield(progress: 100, per: 0).count, 0)
        XCTAssertEqual(PlayerStore.candyYield(progress: -50, per: 100).remainder, 0)
    }
}

@MainActor
final class RibbonProductionTests: XCTestCase {
    private var clock = Date(timeIntervalSince1970: 1_000_000)

    private func makeStore() -> (PlayerStore, UUID) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ribbon-\(UUID().uuidString).json")
        let store = PlayerStore(fileURL: url, rng: SeededRNG(seed: 6), now: { self.clock },
                                defaults: UserDefaults(suiteName: "ribbon-\(UUID().uuidString)")!)
        let individual = Individual(baseID: 1, speciesID: 1, pathIDs: [1], nature: .serious,
                                    obtainedAt: clock, grade: .common)
        store.addForTesting(individual)
        store.setPartner(individual.id)
        store.update(todayTokens: 0, todayDate: "2026-01-01", hasUsageData: true)   // 기준선
        return (store, individual.id)
    }

    private func find(_ store: PlayerStore, _ id: UUID) -> Individual {
        store.state.box.first { $0.id == id }!
    }

    /// 리본이 없으면 아무리 써도 사탕이 안 나온다 — 시간을 들여야 열리는 보상이다.
    func testNoCandyWithoutARibbon() {
        let (store, id) = makeStore()
        store.update(todayTokens: 900_000_000, todayDate: "2026-01-01", hasUsageData: true)
        XCTAssertEqual(store.count(of: .expCandy), 0)
        XCTAssertEqual(find(store, id).candyProgress, 0, "리본 없이 진행분을 쌓아 두지 않는다")
    }

    func testRibbonedPartnerProducesCandyFromTokens() {
        let (store, id) = makeStore()
        clock = clock.addingTimeInterval(2 * 86_400)   // 인연 리본
        store.update(todayTokens: Ribbon.bond.tokensPerCandy, todayDate: "2026-01-01",
                     hasUsageData: true)
        XCTAssertEqual(store.count(of: .expCandy), 1)
        XCTAssertEqual(find(store, id).candyProgress, 0)
    }

    /// 모자란 만큼은 다음 갱신으로 이어진다 — 한 번에 못 채웠다고 버리면 조금씩 쓰는 사용자가 손해다.
    func testProgressCarriesAcrossUpdates() {
        let (store, id) = makeStore()
        clock = clock.addingTimeInterval(2 * 86_400)
        let half = Ribbon.bond.tokensPerCandy / 2
        store.update(todayTokens: half, todayDate: "2026-01-01", hasUsageData: true)
        XCTAssertEqual(store.count(of: .expCandy), 0)
        XCTAssertEqual(find(store, id).candyProgress, half)
        store.update(todayTokens: half * 2, todayDate: "2026-01-01", hasUsageData: true)
        XCTAssertEqual(store.count(of: .expCandy), 1, "이어붙인 진행분으로 사탕이 나와야 한다")
    }

    /// 단계가 오르면 같은 토큰으로 더 많이 나온다.
    func testHigherRibbonProducesMoreForTheSameTokens() {
        let (low, _) = makeStore()
        clock = clock.addingTimeInterval(2 * 86_400)
        low.update(todayTokens: 300_000_000, todayDate: "2026-01-01", hasUsageData: true)
        let lowCount = low.count(of: .expCandy)

        clock = Date(timeIntervalSince1970: 1_000_000)
        let (high, _) = makeStore()
        clock = clock.addingTimeInterval(95 * 86_400)   // 반려 리본
        high.update(todayTokens: 300_000_000, todayDate: "2026-01-01", hasUsageData: true)
        XCTAssertGreaterThan(high.count(of: .expCandy), lowCount)
    }

    /// 파트너만 만든다 — 벤치에 앉은 개체는 리본이 있어도 생산하지 않는다.
    func testOnlyThePartnerProduces() {
        let (store, partner) = makeStore()
        var bench = Individual(baseID: 4, speciesID: 4, pathIDs: [4], nature: .calm,
                               obtainedAt: clock, grade: .rare)
        bench.partnerSeconds = 95 * 86_400   // 최고 리본을 달았지만 지금은 파트너가 아니다
        store.addForTesting(bench)
        clock = clock.addingTimeInterval(2 * 86_400)
        store.update(todayTokens: 600_000_000, todayDate: "2026-01-01", hasUsageData: true)
        XCTAssertEqual(find(store, bench.id).candyProgress, 0, "벤치 개체가 생산했다")
        XCTAssertGreaterThan(find(store, partner).candyProgress + store.count(of: .expCandy), 0)
    }

    /// 만들어진 사탕은 **다른 개체**에게 먹일 수 있어야 한다 — 그게 이 설계의 요점이다.
    func testProducedCandyCanBeFedToAnotherIndividual() {
        let (store, _) = makeStore()
        let other = Individual(baseID: 7, speciesID: 7, pathIDs: [7], nature: .bold,
                               obtainedAt: clock, grade: .common)
        store.addForTesting(other)
        clock = clock.addingTimeInterval(2 * 86_400)
        store.update(todayTokens: Ribbon.bond.tokensPerCandy, todayDate: "2026-01-01",
                     hasUsageData: true)
        XCTAssertEqual(store.count(of: .expCandy), 1)
        XCTAssertTrue(store.useExpCandy(on: other.id))
        XCTAssertEqual(find(store, other.id).exp, PlayerStore.expCandyAmount)
    }

    /// 생산이 지갑이나 함께 쓴 토큰 기록을 건드리지 않는다 — 사탕은 덤이지 대체가 아니다.
    func testProductionDoesNotDisturbTheWalletOrLedger() {
        let (store, id) = makeStore()
        clock = clock.addingTimeInterval(2 * 86_400)
        let spend = Ribbon.bond.tokensPerCandy
        store.update(todayTokens: spend, todayDate: "2026-01-01", hasUsageData: true)
        XCTAssertEqual(store.state.wallet, spend)
        XCTAssertEqual(find(store, id).partnerTokens, spend)
    }
}

/// 행운의 부적 — 재화만 늘린다. 경험치와는 별개 트랙이라 서로 안 겹쳐야 한다.
@MainActor
final class FortuneCharmTests: XCTestCase {
    private func makeStore(wallet: Int) -> (PlayerStore, UUID) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("fortune-\(UUID().uuidString).json")
        let store = PlayerStore(fileURL: url, rng: SeededRNG(seed: 8),
                                now: { Date(timeIntervalSince1970: 0) },
                                defaults: UserDefaults(suiteName: "fortune-\(UUID().uuidString)")!)
        let individual = Individual(baseID: 1, speciesID: 1, pathIDs: [1], nature: .serious,
                                    obtainedAt: Date(timeIntervalSince1970: 0), grade: .common)
        store.addForTesting(individual)
        store.setPartner(individual.id)
        store.seedForTesting(wallet: wallet, slots: 3, eggs: 0, at: Date(timeIntervalSince1970: 0))
        store.update(todayTokens: 0, todayDate: "2026-01-01", hasUsageData: true)
        return (store, individual.id)
    }

    func testCurrencyGainIsPureAndRoundsDown() {
        XCTAssertEqual(PlayerStore.currencyGain(100, charm: false), 100)
        XCTAssertEqual(PlayerStore.currencyGain(100, charm: true), 150)
        XCTAssertEqual(PlayerStore.currencyGain(1, charm: true), 1, "소수 재화는 없다 — 내림")
        XCTAssertEqual(PlayerStore.currencyGain(0, charm: true), 0)
    }

    /// 재화만 1.5배가 되고 경험치·기록은 그대로여야 한다.
    func testCharmRaisesCurrencyOnly() {
        let (store, id) = makeStore(wallet: ShopItem.fortuneCharm.price)
        XCTAssertTrue(store.buy(.fortuneCharm))
        let after = store.state.wallet
        store.update(todayTokens: 1_000, todayDate: "2026-01-01", hasUsageData: true)
        XCTAssertEqual(store.state.wallet, after + 1_500, "재화가 1.5배가 아니다")
        let individual = store.state.box.first { $0.id == id }!
        XCTAssertEqual(individual.exp, 1_000, "행운의 부적이 경험치까지 늘렸다")
        XCTAssertEqual(individual.partnerTokens, 1_000, "기록은 실제 쓴 토큰만 센다")
    }

    func testCharmIsBoughtOnlyOnceAndIsIndependent() {
        let (store, _) = makeStore(wallet: ShopItem.fortuneCharm.price + ShopItem.expCharm.price)
        XCTAssertTrue(store.buy(.fortuneCharm))
        XCTAssertFalse(store.buy(.fortuneCharm), "보유형을 두 번 샀다")
        XCTAssertFalse(store.owns(.expCharm))
        XCTAssertTrue(store.buy(.expCharm))
        XCTAssertTrue(store.owns(.fortuneCharm), "경험치 부적을 사면서 행운의 부적이 사라졌다")
    }

    func testCharmSurvivesReload() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("fortune-reload-\(UUID().uuidString).json")
        let defaults = UserDefaults(suiteName: "fortune-reload-\(UUID().uuidString)")!
        let first = PlayerStore(fileURL: url, now: { Date(timeIntervalSince1970: 0) },
                                defaults: defaults)
        first.seedForTesting(wallet: ShopItem.fortuneCharm.price, slots: 3, eggs: 0,
                             at: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(first.buy(.fortuneCharm))
        let second = PlayerStore(fileURL: url, now: { Date(timeIntervalSince1970: 0) },
                                 defaults: defaults)
        XCTAssertTrue(second.owns(.fortuneCharm))
    }
}
