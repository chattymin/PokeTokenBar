import XCTest
@testable import PokeDexBar

/// [회귀] `Individual` 에 필드를 더하면 기존 세이브의 **모든 개체가 조용히 사라진다**.
/// Swift 가 합성하는 디코더는 프로퍼티 기본값을 무시하고 키가 없으면 던지는데, `LossyIndividual`
/// 이 그 예외를 "이 개체를 버린다"로 바꾸기 때문이다. `partnerTokens` 를 더하면서 실제로 그렇게
/// 됐다(박스 전체가 빈 상태로 디코드됐고, 기존 디코드 테스트 셋이 잡았다).
final class IndividualForwardCompatibilityTests: XCTestCase {
    /// 새 필드가 없는 옛 개체 JSON. 새 필드를 더할 때 **이 문자열은 절대 고치지 마라** —
    /// 여기에 새 키를 넣는 순간 이 테스트는 아무것도 지키지 않게 된다.
    private let legacy = """
    {"id":"11111111-1111-1111-1111-111111111111","baseID":16,"speciesID":17,"pathIDs":[16,17],
    "shiny":true,"nature":"brave","exp":1234,"obtainedAt":0,"grade":"common"}
    """

    func testLegacyIndividualStillDecodes() throws {
        let individual = try JSONDecoder().decode(Individual.self, from: Data(legacy.utf8))
        XCTAssertEqual(individual.speciesID, 17)
        // `eggProgress` 키가 없는 옛 세이브라 레벨 이전이 발동한다 — `exp` 는 원래 쓴 토큰이었으므로
        // 알 진행분으로 그대로 물려주고, 경험치는 환율로 나눈다(`Individual.init(from:)` 참고).
        XCTAssertEqual(individual.eggProgress, 1234)
        XCTAssertEqual(individual.exp, 1234 / ExpBalance.tokensPerExp)
        XCTAssertTrue(individual.shiny)
        XCTAssertEqual(individual.partnerTokens, 0, "없던 필드는 기본값으로 들어와야 한다")
    }

    /// 박스를 통째로 지나는 경로로도 확인한다 — 개체 하나만 봐서는 `LossyIndividual` 이
    /// 실제로 살려 내는지 알 수 없다.
    func testLegacyBoxSurvivesTheStateDecode() throws {
        let json = """
        {"box":[\(legacy)],"dex":[17],"earnedTokens":0,"spentTokens":0,"claimedTodayTokens":0,
        "lastDate":"2026-01-01","installBaselineSet":true,"slots":3,"eggs":[],"inventory":{},
        "ownsShinyCharm":false,"starterChosen":true,"language":"ko"}
        """
        let state = try JSONDecoder().decode(PlayerState.self, from: Data(json.utf8))
        XCTAssertEqual(state.box.count, 1, "필드를 더하면서 기존 박스를 날렸다")
        XCTAssertEqual(state.box.first?.partnerTokens, 0)
    }

    /// 정체를 알 수 없는 개체는 그대로 버린다 — 관대함이 "아무거나 통과"가 되면 안 된다.
    func testIndividualWithoutIdentityIsStillRejected() {
        let broken = #"{"id":"11111111-1111-1111-1111-111111111111","shiny":false}"#
        XCTAssertThrowsError(try JSONDecoder().decode(Individual.self, from: Data(broken.utf8)))
    }

    func testRoundTripKeepsPartnerTokens() throws {
        var individual = Individual(baseID: 1, speciesID: 1, pathIDs: [1], nature: .serious,
                                    obtainedAt: Date(timeIntervalSince1970: 0), grade: .common)
        individual.partnerTokens = 987_654_321
        let back = try JSONDecoder().decode(Individual.self,
                                            from: JSONEncoder().encode(individual))
        XCTAssertEqual(back.partnerTokens, 987_654_321)
    }
}

@MainActor
final class PartnerTokenLedgerTests: XCTestCase {
    private func makeStore() -> PlayerStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ledger-\(UUID().uuidString).json")
        return PlayerStore(fileURL: url, rng: SeededRNG(seed: 4),
                           now: { Date(timeIntervalSince1970: 0) },
                           defaults: UserDefaults(suiteName: "ledger-\(UUID().uuidString)")!)
    }

    private func partnered(_ store: PlayerStore) -> UUID {
        let individual = Individual(baseID: 1, speciesID: 1, pathIDs: [1], nature: .serious,
                                    obtainedAt: Date(timeIntervalSince1970: 0), grade: .common)
        store.addForTesting(individual)
        store.setPartner(individual.id)
        store.update(todayTokens: 0, todayDate: "2026-01-01", hasUsageData: true)   // 기준선
        return individual.id
    }

    private func find(_ store: PlayerStore, _ id: UUID) -> Individual {
        store.state.box.first { $0.id == id }!
    }

    func testPartnerTokensAccumulate() {
        let store = makeStore()
        let id = partnered(store)
        store.update(todayTokens: 300, todayDate: "2026-01-01", hasUsageData: true)
        store.update(todayTokens: 500, todayDate: "2026-01-01", hasUsageData: true)
        XCTAssertEqual(find(store, id).partnerTokens, 500)
    }

    /// 파트너가 아닌 개체는 안 쌓인다 — 경험치와 같은 규칙이다.
    func testOnlyThePartnerAccumulates() {
        let store = makeStore()
        let partner = partnered(store)
        let bench = Individual(baseID: 4, speciesID: 4, pathIDs: [4], nature: .calm,
                               obtainedAt: Date(timeIntervalSince1970: 0), grade: .rare)
        store.addForTesting(bench)
        store.update(todayTokens: 700, todayDate: "2026-01-01", hasUsageData: true)
        XCTAssertEqual(find(store, partner).partnerTokens, 700)
        XCTAssertEqual(find(store, bench.id).partnerTokens, 0)
    }

    /// 진화해도 안 줄어든다 — 경험치와 달리 이건 "함께 일한 기록"이다.
    func testPartnerTokensSurviveEvolution() {
        let store = makeStore()
        let id = partnered(store)
        store.update(todayTokens: 90_000_000, todayDate: "2026-01-01", hasUsageData: true)
        // 진화 게이트가 레벨로 바뀌면서(Task 7) 경험치 자체는 더 이상 진화 조건이 아니다 —
        // 조건 없는 라인(`.none`)이면 경험치가 얼마든 바로 진화한다. 이 테스트가 보는 것은
        // "진화해도 함께 쓴 토큰 기록(`partnerTokens`)은 안 줄고, 경험치(`exp`)도 안 깎인다"이므로
        // 경험치 값 자체는 임의로 둔다.
        let index = store.state.box.firstIndex { $0.id == id }!
        store.mutate { $0.box[index].exp = 90_000_000 }
        let line = EvoLine(baseID: 1,
                           tree: EvoNode(speciesID: 1, children: [EvoNode(speciesID: 2, children: [])]),
                           rarity: .common, names: [:])
        XCTAssertTrue(store.evolve(individualID: id, to: 2, line: line))
        XCTAssertEqual(find(store, id).exp, 90_000_000, "진화가 경험치를 깎았다")
        XCTAssertEqual(find(store, id).partnerTokens, 90_000_000, "함께 쓴 토큰이 진화로 줄었다")
    }

    /// 경험치 부적은 경험치만 2배로 만든다 — 토큰 기록과 지갑은 그대로다.
    func testExpCharmDoublesExperienceButNotTheLedgerOrWallet() {
        let store = makeStore()
        let id = partnered(store)
        store.seedForTesting(wallet: ShopItem.expCharm.price, slots: 3, eggs: 0,
                             at: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(store.buy(.expCharm))
        let walletAfterPurchase = store.state.wallet
        let spent = ExpBalance.tokensPerExp * 2
        store.update(todayTokens: spent, todayDate: "2026-01-01", hasUsageData: true)
        // 부적이 먼저 걸리고 환율은 그 다음이다: 환율 두 배어치 → 부적으로 2배 → 4EXP.
        // (이 순서가 자투리를 덜 버린다 — 나눗셈을 먼저 하면 자투리가 사라진다.)
        XCTAssertEqual(find(store, id).exp, 4, "부적이 경험치를 2배로 안 만든다")
        XCTAssertEqual(find(store, id).partnerTokens, spent, "기록은 실제 쓴 토큰만 세야 한다")
        XCTAssertEqual(store.state.wallet, walletAfterPurchase + spent, "부적이 재화까지 2배로 만들었다")
    }
}

@MainActor
final class ExpCharmTests: XCTestCase {
    private func makeStore(wallet: Int) -> (PlayerStore, UUID) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("charm-\(UUID().uuidString).json")
        let store = PlayerStore(fileURL: url, rng: SeededRNG(seed: 4),
                                now: { Date(timeIntervalSince1970: 0) },
                                defaults: UserDefaults(suiteName: "charm-\(UUID().uuidString)")!)
        let individual = Individual(baseID: 1, speciesID: 1, pathIDs: [1], nature: .serious,
                                    obtainedAt: Date(timeIntervalSince1970: 0), grade: .common)
        store.addForTesting(individual)
        store.seedForTesting(wallet: wallet, slots: 3, eggs: 0, at: Date(timeIntervalSince1970: 0))
        return (store, individual.id)
    }

    func testExpGainIsPureAndDoubles() {
        XCTAssertEqual(PlayerStore.expGain(50, charm: false), 50)
        XCTAssertEqual(PlayerStore.expGain(50, charm: true), 100)
        XCTAssertEqual(PlayerStore.expGain(0, charm: true), 0)
    }

    /// 부적은 보유형 — 한 번만 산다.
    func testCharmIsBoughtOnlyOnce() {
        let (store, _) = makeStore(wallet: ShopItem.expCharm.price * 3)
        XCTAssertTrue(store.buy(.expCharm))
        XCTAssertTrue(store.owns(.expCharm))
        XCTAssertFalse(store.buy(.expCharm), "보유형을 두 번 샀다")
    }

    /// 두 부적은 서로 독립이다 — 하나를 샀다고 다른 하나가 딸려오면 안 된다.
    func testTheTwoCharmsAreIndependent() {
        let (store, _) = makeStore(wallet: ShopItem.expCharm.price + ShopItem.shinyCharm.price)
        XCTAssertTrue(store.buy(.expCharm))
        XCTAssertFalse(store.owns(.shinyCharm))
        XCTAssertTrue(store.buy(.shinyCharm))
        XCTAssertTrue(store.owns(.expCharm), "이로치 부적을 사면서 경험치 부적이 사라졌다")
    }

    func testExpCandyIsDoubledByTheCharm() {
        let (store, id) = makeStore(wallet: ShopItem.expCharm.price + ShopItem.expCandy.price * 2)
        XCTAssertTrue(store.buy(.expCandy))
        XCTAssertTrue(store.useExpCandy(on: id))
        XCTAssertEqual(store.state.box.first { $0.id == id }?.exp, ExpBalance.candyExp)

        XCTAssertTrue(store.buy(.expCharm))
        XCTAssertTrue(store.buy(.expCandy))
        XCTAssertTrue(store.useExpCandy(on: id))
        XCTAssertEqual(store.state.box.first { $0.id == id }?.exp,
                       ExpBalance.candyExp * 3, "부적을 산 뒤의 사탕이 2배가 아니다")
    }

    /// 부적은 재고를 세지 않는다 — 상점 표시가 개수형과 갈린다.
    func testCharmIsNotConsumable() {
        XCTAssertTrue(ShopItem.expCharm.isCharm)
        XCTAssertFalse(ShopItem.expCharm.isConsumable)
        XCTAssertTrue(ShopItem.expCandy.isConsumable)
    }

    /// 세이브를 오갔을 때 부적이 남아 있어야 한다.
    func testCharmSurvivesReload() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("charm-reload-\(UUID().uuidString).json")
        let defaults = UserDefaults(suiteName: "charm-reload-\(UUID().uuidString)")!
        let first = PlayerStore(fileURL: url, now: { Date(timeIntervalSince1970: 0) },
                                defaults: defaults)
        first.seedForTesting(wallet: ShopItem.expCharm.price, slots: 3, eggs: 0,
                             at: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(first.buy(.expCharm))
        let second = PlayerStore(fileURL: url, now: { Date(timeIntervalSince1970: 0) },
                                 defaults: defaults)
        XCTAssertTrue(second.owns(.expCharm))
    }
}

/// 가격표 — 사용자가 정한 값이라 소스에 그대로 있는지 잠근다.
final class ShopPriceTests: XCTestCase {
    func testCharmsCostTheSame() {
        XCTAssertEqual(ShopItem.shinyCandy.price, 3_000_000_000)
        XCTAssertEqual(ShopItem.shinyCharm.price, 3_000_000_000)
    }

    func testFormItemsCostTheSame() {
        XCTAssertEqual(ShopItem.megaStone.price, 2_000_000_000)
        XCTAssertEqual(ShopItem.dynamaxMushroom.price, 2_000_000_000)
    }

    /// 소모품이 부적보다 비싸지는 않아야 한다 — 영구 효과가 더 싸면 소모품을 살 이유가 없다.
    /// 같은 값은 허용한다: 반짝이는 사탕과 이로치 부적은 의도적으로 둘 다 3B 다.
    func testNoConsumableCostsMoreThanACharm() {
        XCTAssertEqual(ShopItem.expCharm.price, 4_000_000_000)
        XCTAssertEqual(ShopItem.fortuneCharm.price, 5_000_000_000)
        let cheapestCharm = ShopItem.allCases.filter(\.isCharm).map(\.price).min()!
        for item in ShopItem.allCases where !item.isCharm {
            XCTAssertLessThanOrEqual(item.price, cheapestCharm, "\(item) 이 부적보다 비싸다")
        }
    }

    /// 뽑기 한 번이 어떤 아이템보다도 싸야 한다 — 뽑기가 이 게임의 기본 동작이다.
    func testADrawIsCheaperThanAnyItem() {
        for item in ShopItem.allCases {
            XCTAssertLessThan(EggBalance.drawPrice, item.price, "\(item) 보다 뽑기가 비싸다")
        }
    }
}

/// 함께한 시간 — 파트너를 바꿔 가며 데리고 다녀도 누적이 맞아야 한다.
@MainActor
final class PartnerTimeTests: XCTestCase {
    private var clock = Date(timeIntervalSince1970: 1_000_000)

    private func makeStore() -> PlayerStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("time-\(UUID().uuidString).json")
        return PlayerStore(fileURL: url, rng: SeededRNG(seed: 2), now: { self.clock },
                           defaults: UserDefaults(suiteName: "time-\(UUID().uuidString)")!)
    }

    private func add(_ store: PlayerStore, species: Int) -> UUID {
        let individual = Individual(baseID: species, speciesID: species, pathIDs: [species],
                                    nature: .serious, obtainedAt: clock, grade: .common)
        store.addForTesting(individual)
        return individual.id
    }

    private func find(_ store: PlayerStore, _ id: UUID) -> Individual {
        store.state.box.first { $0.id == id }!
    }

    func testDurationGrowsWhileItIsThePartner() {
        let store = makeStore()
        let id = add(store, species: 1)
        store.setPartner(id)
        clock = clock.addingTimeInterval(3_600)
        XCTAssertEqual(find(store, id).partnerDuration(at: clock), 3_600)
    }

    /// 파트너에서 내려오면 시계가 멈춘다 — 안 멈추면 벤치에 앉은 개체도 계속 시간이 는다.
    func testDurationStopsWhenAnotherBecomesPartner() {
        let store = makeStore()
        let first = add(store, species: 1)
        let second = add(store, species: 4)
        store.setPartner(first)
        clock = clock.addingTimeInterval(7_200)
        store.setPartner(second)
        clock = clock.addingTimeInterval(10_000)
        XCTAssertEqual(find(store, first).partnerDuration(at: clock), 7_200, "내려온 뒤에도 시간이 늘었다")
        XCTAssertEqual(find(store, second).partnerDuration(at: clock), 10_000)
    }

    /// 다시 데리고 나오면 이어서 쌓인다 — 초기화되면 안 된다.
    func testDurationResumesOnASecondStint() {
        let store = makeStore()
        let first = add(store, species: 1)
        let second = add(store, species: 4)
        store.setPartner(first)
        clock = clock.addingTimeInterval(100)
        store.setPartner(second)
        clock = clock.addingTimeInterval(500)
        store.setPartner(first)
        clock = clock.addingTimeInterval(50)
        XCTAssertEqual(find(store, first).partnerDuration(at: clock), 150, "두 번째 구간이 이어지지 않는다")
    }

    /// 같은 개체를 다시 지정해도 구간이 끊기지 않는다.
    func testReassigningTheSamePartnerKeepsTheClockRunning() {
        let store = makeStore()
        let id = add(store, species: 1)
        store.setPartner(id)
        clock = clock.addingTimeInterval(600)
        store.setPartner(id)
        clock = clock.addingTimeInterval(600)
        XCTAssertEqual(find(store, id).partnerDuration(at: clock), 1_200)
    }

    /// 시계가 뒤로 뛰어도 음수가 되지 않는다.
    func testBackwardClockDoesNotGoNegative() {
        let store = makeStore()
        let id = add(store, species: 1)
        store.setPartner(id)
        XCTAssertEqual(find(store, id).partnerDuration(at: clock.addingTimeInterval(-9_999)), 0)
    }

    /// 봉인 이전 세이브의 파트너는 시작 시각이 없다 — 사용량 갱신에서 늦게라도 시계를 건다.
    func testLegacyPartnerStartsCountingOnTheNextUpdate() {
        let store = makeStore()
        let id = add(store, species: 1)
        store.setPartner(id)
        store.mutate { $0.box[0].partnerSince = nil }   // 구 세이브 흉내
        store.update(todayTokens: 0, todayDate: "2026-01-01", hasUsageData: true)
        store.update(todayTokens: 10, todayDate: "2026-01-01", hasUsageData: true)
        XCTAssertNotNil(find(store, id).partnerSince, "구 세이브 파트너의 시계가 영영 안 걸린다")
    }

    func testTogetherTextPicksTheTwoLargestUnits() {
        let l = L(.ko)
        XCTAssertEqual(Individual.togetherText(seconds: 0, l), "0분")
        XCTAssertEqual(Individual.togetherText(seconds: 90, l), "1분")
        XCTAssertEqual(Individual.togetherText(seconds: 3_600 * 5 + 60 * 7, l), "5시간 7분")
        XCTAssertEqual(Individual.togetherText(seconds: 86_400 * 3 + 3_600 * 4, l), "3일 4시간")
        XCTAssertEqual(Individual.togetherText(seconds: -50, l), "0분")
    }
}
