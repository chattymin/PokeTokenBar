import XCTest
@testable import PokeDexBar

/// 토큰이 경험치와 알로 나뉘어 들어간다.
@MainActor
final class LevelEconomyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeStore() -> PlayerStore {
        PlayerStore(fileURL: FileManager.default.temporaryDirectory
                        .appendingPathComponent("lvl-\(UUID().uuidString).json"),
                    rng: SeededRNG(seed: 1), now: { self.now })
    }

    private func partnered(_ store: PlayerStore, rate: GrowthRate = .mediumFast) -> UUID {
        let individual = Individual(baseID: 4, speciesID: 4, pathIDs: [4], nature: .hardy,
                                    obtainedAt: now, grade: .common, growthRate: rate)
        store.addForTesting(individual)
        store.setPartner(individual.id)
        return individual.id
    }

    private func partner(_ store: PlayerStore, _ id: UUID) -> Individual {
        store.state.box.first { $0.id == id }!
    }

    /// **500토큰이 1EXP 다.**
    /// 입력을 **환율의 배수**로 준다 — 그래야 환율을 조정해도 이 테스트가 뜻을 유지한다.
    /// 기대값(1,000)은 상수에서 파생하지 않는다: 양변이 같은 상수에서 나오면 환율을 아예
    /// 안 걸어도 통과한다.
    func testTokensBecomeExperienceAtTheStatedRate() {
        let store = makeStore()
        let id = partnered(store)
        store.update(todayTokens: 0, todayDate: "2026-08-12", hasUsageData: true)   // 기준선
        store.update(todayTokens: ExpBalance.tokensPerExp * 1_000,
                     todayDate: "2026-08-12", hasUsageData: true)

        XCTAssertEqual(partner(store, id).exp, 1_000, "환율이 안 걸렸다")
    }

    /// **지금 배포되는 환율을 못으로 박는다.** 다른 테스트는 전부 `tokensPerExp` 상대값이라
    /// 환율이 실수로 바뀌어도 통과한다 — 밸런스 상수는 그 자체가 결정이므로 한 곳에서 값을 고정한다
    /// (`ReleaseBalance.testReleaseBaseValues` 와 같은 이유). 바꿀 때는 이 줄도 같이 바꾼다.
    func testTheShippedExchangeRate() {
        XCTAssertEqual(ExpBalance.tokensPerExp, 8_000)
        // 사탕은 토큰 값어치로 못 박혀 있어 환율을 바꿔도 지갑 기준 값어치가 안 변한다.
        XCTAssertEqual(ExpBalance.candyExp * ExpBalance.tokensPerExp, 100_000_000)
        // mediumFast 만렙 = 80억 토큰. 커먼 알(5억)의 16배 — 레벨이 알보다 훨씬 긴 프로젝트다.
        XCTAssertEqual(GrowthRate.mediumFast.totalExp(at: 100) * ExpBalance.tokensPerExp,
                       8_000_000_000)
    }

    /// **알은 토큰 그대로 찬다.** 경험치와 같은 수가 되면 분리가 안 된 것이다.
    func testTheEggMeterCountsRawTokens() {
        let store = makeStore()
        let id = partnered(store)
        store.update(todayTokens: 0, todayDate: "2026-08-12", hasUsageData: true)   // 기준선
        store.update(todayTokens: 500_000, todayDate: "2026-08-12", hasUsageData: true)

        let p = partner(store, id)
        XCTAssertEqual(p.eggProgress, 500_000, "알 계량기가 토큰을 그대로 안 센다")
        XCTAssertNotEqual(p.eggProgress, p.exp, "두 계량기가 같은 값이다 — 분리가 안 됐다")
    }

    /// **파트너가 아니면 둘 다 안 찬다.**
    func testANonPartnerGainsNothing() {
        let store = makeStore()
        let bench = Individual(baseID: 1, speciesID: 1, pathIDs: [1], nature: .hardy,
                               obtainedAt: now, grade: .common)
        store.addForTesting(bench)
        _ = partnered(store)   // 다른 개체가 파트너다
        store.update(todayTokens: 0, todayDate: "2026-08-12", hasUsageData: true)   // 기준선
        store.update(todayTokens: 500_000, todayDate: "2026-08-12", hasUsageData: true)

        let idle = store.state.box.first { $0.id == bench.id }!
        XCTAssertEqual(idle.exp, 0)
        XCTAssertEqual(idle.eggProgress, 0)
    }

    /// **최종진화가 아니어도 알이 찬다.** 예전 규칙(최종형만)이 남아 있으면 여기서 걸린다.
    func testAnUnevolvedPartnerFillsTheEggMeter() {
        let store = makeStore()
        let id = partnered(store)   // 파이리 — 최종형이 아니다
        store.update(todayTokens: 0, todayDate: "2026-08-12", hasUsageData: true)   // 기준선
        store.update(todayTokens: 1_000_000, todayDate: "2026-08-12", hasUsageData: true)

        XCTAssertGreaterThan(partner(store, id).eggProgress, 0)
    }

    /// **경험치 부적은 경험치에만 걸린다.** 알까지 2배가 되면 분리가 샌 것이다.
    func testTheExpCharmDoublesExperienceButNotTheEgg() {
        let store = makeStore()
        let id = partnered(store)
        store.mutate { $0.charmTiers[ShopItem.expCharm.rawValue] = CharmLadder.legacyTier }
        store.update(todayTokens: 0, todayDate: "2026-08-12", hasUsageData: true)   // 기준선
        let spent = ExpBalance.tokensPerExp * 1_000
        store.update(todayTokens: spent, todayDate: "2026-08-12", hasUsageData: true)

        let p = partner(store, id)
        XCTAssertEqual(p.exp, 2_000, "부적이 경험치에 안 걸렸다")   // 부적이 없으면 1,000
        XCTAssertEqual(p.eggProgress, spent, "부적이 알까지 불렸다")
    }

    /// **두 계량기 모두 자기 상한에서 멈춘다.**
    func testBothMetersStopAtTheirOwnCeiling() {
        let store = makeStore()
        let id = partnered(store)
        store.update(todayTokens: 0, todayDate: "2026-08-12", hasUsageData: true)   // 기준선
        store.update(todayTokens: 10_000_000_000, todayDate: "2026-08-12", hasUsageData: true)

        let p = partner(store, id)
        XCTAssertEqual(p.exp, GrowthRate.mediumFast.totalExp(at: 100))
        XCTAssertEqual(p.level, 100)
        XCTAssertEqual(p.eggProgress, ExpBalance.eggThreshold(grade: .common))
    }

    /// **알을 받으면 알 계량기만 0이 된다.** 경험치는 그대로다 — 이게 "분리"의 뜻이다.
    func testTakingTheEggResetsOnlyTheEggMeter() {
        let store = makeStore()
        let id = partnered(store)
        store.update(todayTokens: 0, todayDate: "2026-08-12", hasUsageData: true)   // 기준선
        store.update(todayTokens: 10_000_000_000, todayDate: "2026-08-12", hasUsageData: true)
        let expBefore = partner(store, id).exp
        let line = EvoLine(baseID: 4, tree: EvoNode(speciesID: 4, children: []),
                           rarity: .common, names: [:])

        XCTAssertTrue(store.canTakeFoundEgg(partner(store, id), line: line))
        store.takeFoundEgg(individualID: id, line: line)

        let p = partner(store, id)
        XCTAssertEqual(p.eggProgress, 0, "알 계량기가 안 비었다")
        XCTAssertEqual(p.exp, expBefore, "알을 받았더니 경험치가 깎였다")
    }

    /// [회귀] **작은 델타가 반복돼도 나머지가 이월돼야 한다.** 갱신은 짧은 주기(기본 120초)로
    /// 자주 불리는데, 델타가 환율(500)에 못 미치면 정수 나눗셈이 매번 0이 된다 — 이월이 없으면
    /// 하루 10만 토큰을 쓰는 가벼운 사용자는 exp 가 영원히 0이다. 300토큰씩 열 번(3,000토큰)이면
    /// 정확히 6EXP 여야 한다.
    func testTenSmallDeltasCarryTheRemainderIntoWholeExp() {
        let store = makeStore()
        let id = partnered(store)
        var claimed = 0
        store.update(todayTokens: claimed, todayDate: "2026-08-12", hasUsageData: true)   // 기준선
        // 한 번에 1EXP 에 못 미치는 델타를 열 번. 이월이 없으면 매번 0으로 잘려 영원히 0이다.
        let perTick = ExpBalance.tokensPerExp * 3 / 5           // 환율의 60% — 혼자서는 절대 1EXP 가 안 된다
        for _ in 0..<10 {
            claimed += perTick
            store.update(todayTokens: claimed, todayDate: "2026-08-12", hasUsageData: true)
        }
        XCTAssertEqual(partner(store, id).exp, 6,
                       "환율의 60%씩 열 번이면 6EXP 여야 한다 — 나머지 이월이 없으면 0에 머문다")
    }

    /// **사탕은 EXP 를 준다.** 값어치는 **토큰으로** 못 박혀 있어 환율을 바꿔도 안 움직인다.
    func testCandyGivesExperienceNotTokens() {
        let store = makeStore()
        let id = partnered(store)
        store.mutate { $0.inventory[ShopItem.expCandy.rawValue] = 1 }

        XCTAssertTrue(store.useExpCandy(on: id))
        let p = partner(store, id)
        XCTAssertEqual(p.exp, ExpBalance.candyExp)
        XCTAssertEqual(ExpBalance.candyExp * ExpBalance.tokensPerExp, 100_000_000,
                       "사탕의 토큰 값어치가 환율을 따라 움직였다")
        XCTAssertEqual(p.eggProgress, 0, "사탕이 알까지 채웠다")
    }
}
