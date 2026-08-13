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

    /// [정산 경로] **같은 도구를 두 번 물어 오지 않는다.** 순수 함수(`forage`)만 잠그면
    /// 부족하다 — 한 번의 정산에서 사탕이 여러 개 나오면 채집도 여러 번 굴러가므로, 루프가
    /// 인벤토리를 매번 다시 읽지 않으면 같은 정산 안에서 중복이 생긴다.
    func testOneSettlementNeverBringsTheSameItemTwice() {
        let (store, _) = makeStore()
        // 이브이를 파트너로 — 갈래가 다섯이라 중복이 날 여지가 가장 크다.
        let eevee = Individual(baseID: 133, speciesID: 133, pathIDs: [133], nature: .serious,
                               obtainedAt: clock, grade: .common)
        store.addForTesting(eevee)
        store.setPartner(eevee.id)
        clock = clock.addingTimeInterval(95 * 86_400)   // 반려 리본 — 가장 자주 물어 온다
        // 한 번에 사탕 수백 개가 나올 만큼 몰아 준다 = 채집도 그만큼 굴러간다.
        store.update(todayTokens: Ribbon.lifelong.tokensPerCandy * 400, todayDate: "2026-01-01",
                     hasUsageData: true)

        let stones: [EvolutionItem] = [.waterStone, .thunderStone, .fireStone, .leafStone, .iceStone]
        for stone in stones {
            XCTAssertLessThanOrEqual(store.count(of: stone), 1,
                                     "\(stone) 을 \(store.count(of: stone))개 물어 왔다 — 중복이다")
        }
        // 이 정도 굴리면 다섯 개를 다 모았어야 한다(안 모였으면 확률이 아니라 필터가 고장난 것).
        XCTAssertEqual(stones.filter { store.count(of: $0) > 0 }.count, stones.count,
                       "다 모으지 못했다")
        // 이브이가 쓸 수 없는 도구는 하나도 없어야 한다.
        for item in EvolutionItem.allCases where !stones.contains(item) {
            XCTAssertEqual(store.count(of: item), 0, "\(item) 은 이브이가 쓸 수 없다")
        }
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
        XCTAssertEqual(find(store, other.id).exp, ExpBalance.candyExp)
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
        let spent = ExpBalance.tokensPerExp * 2
        store.update(todayTokens: spent, todayDate: "2026-01-01", hasUsageData: true)
        XCTAssertEqual(store.state.wallet, after + spent + spent / 2, "재화가 1.5배가 아니다")
        let individual = store.state.box.first { $0.id == id }!
        // 환율만 걸린 값이다 — 행운의 부적은 재화 전용이라 경험치엔 안 걸린다(걸렸으면 3).
        XCTAssertEqual(individual.exp, 2, "행운의 부적이 경험치까지 늘렸다")
        XCTAssertEqual(individual.partnerTokens, spent, "기록은 실제 쓴 토큰만 센다")
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

/// 리본 그림이 실제로 번들에서 나오는지. 리소스 누락은 이 레포가 이미 한 번 겪은 부류다
/// (`Bundle.module` 이 배포 앱에서 못 찾아 죽었다) — 배지가 조용히 빈칸이 되는 것도 같은 뿌리다.
@MainActor
final class RibbonArtworkTests: XCTestCase {
    func testEveryTierHasArtwork() {
        for ribbon in Ribbon.allCases {
            XCTAssertNotNil(RibbonIcon.resourceURL(for: ribbon),
                            "\(ribbon) 리본 그림을 번들에서 못 찾는다")
            XCTAssertNotNil(RibbonIcon.image(for: ribbon), "\(ribbon) 리본 그림을 못 읽는다")
        }
    }

    /// 단계마다 다른 그림이어야 한다 — 같은 파일을 네 번 쓰면 단계가 안 보인다.
    func testTiersUseDistinctArtwork() {
        let names = Ribbon.allCases.compactMap { RibbonIcon.resourceURL(for: $0)?.lastPathComponent }
        XCTAssertEqual(names.count, Ribbon.allCases.count)
        XCTAssertEqual(Set(names).count, names.count, "리본 그림이 겹친다: \(names)")
    }

    /// 그림이 비어 있지 않은지 — 0×0 이미지는 로드에 성공하고도 아무것도 안 그린다.
    func testArtworkHasPixels() {
        for ribbon in Ribbon.allCases {
            let size = RibbonIcon.image(for: ribbon)?.size ?? .zero
            XCTAssertGreaterThan(size.width, 0, "\(ribbon) 그림이 비어 있다")
            XCTAssertGreaterThan(size.height, 0)
        }
    }
}

/// 리본 화면이 **하는 일 둘을 다 말하는지** — 예전에는 "20M마다 사탕 1개"만 적혀 있어
/// 리본이 사탕 공장으로만 읽혔고, 도구가 어디서 오는지는 화면 어디에도 없었다.
@MainActor
final class RibbonForageDisclosureTests: XCTestCase {
    private func makeStore(_ species: Int) -> (PlayerStore, Individual) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ribbon-ui-\(UUID().uuidString).json")
        let store = PlayerStore(fileURL: url, rng: SeededRNG(seed: 1),
                                now: { Date(timeIntervalSince1970: 0) })
        let i = Individual(baseID: species, speciesID: species, pathIDs: [species],
                           nature: .serious, obtainedAt: Date(timeIntervalSince1970: 0),
                           grade: .common)
        store.addForTesting(i)
        return (store, i)
    }

    /// 진화 도구와 폼 도구를 **둘 다** 센다 — 한쪽만 세면 그 종은 "다 모았다"로 잘못 읽힌다.
    func testTargetsCoverBothEvolutionAndFormItems() {
        let (store, pikachu) = makeStore(25)          // 번개의돌(진화) + 변장 트렁크(폼)
        let targets = store.forageTargets(pikachu)
        XCTAssertTrue(targets.contains(EvolutionItem.thunderStone.label(.ko)))
        XCTAssertTrue(targets.contains(FormItem.costumeTrunk.label(.ko)))
    }

    /// 이미 가진 건 빠진다 — 안 빠지면 다 모으고도 영원히 "찾는 중"으로 남는다.
    func testOwnedItemsDropOutOfTheTargets() {
        let (store, pikachu) = makeStore(25)
        store.grantForTesting(EvolutionItem.thunderStone)
        store.grantForTesting(FormItem.costumeTrunk)
        XCTAssertTrue(store.forageTargets(pikachu).isEmpty)
    }

    /// 도구가 아예 없는 종은 처음부터 빈 목록 — 화면은 "다 모았어요"를 낸다.
    func testSpeciesWithNothingToFindHasNoTargets() {
        let (store, bulbasaur) = makeStore(1)
        XCTAssertTrue(store.forageTargets(bulbasaur).isEmpty)
    }

    /// 아르세우스는 17개라 전부 적으면 카드를 잡아먹는다 — 둘만 적고 접는다.
    func testLongTargetListsAreFolded() {
        let l = L(.ko)
        XCTAssertEqual(IndividualDetailView.targetSummary(["가", "나"], l), "가, 나")
        let folded = IndividualDetailView.targetSummary(["가", "나", "다", "라"], l)
        XCTAssertTrue(folded.hasPrefix("가, 나"), folded)
        XCTAssertTrue(folded.contains("2"), "남은 개수를 안 알려준다: \(folded)")
        XCTAssertFalse(folded.contains("다"), "접혔어야 할 항목이 그대로 있다")
    }

    /// 표기 확률은 실제 확률에서 나와야 한다 — 밸런스를 고치면 문구도 같이 움직인다.
    func testTheShownPercentComesFromTheRibbon() {
        for ribbon in Ribbon.allCases {
            let shown = L(.ko).ribbonForageRate(ribbon.foragePermille / 10)
            XCTAssertTrue(shown.contains("\(ribbon.foragePermille / 10)%"), shown)
        }
    }

    func testForageCopyIsLocalized() {
        for text in [L(.ko).ribbonForageDone, L(.en).ribbonForageDone, L(.ja).ribbonForageDone] {
            XCTAssertFalse(text.isEmpty)
        }
        XCTAssertEqual(Set([L(.ko), L(.en), L(.ja)].map { $0.ribbonForageRate(25) }).count, 3)
    }
}
