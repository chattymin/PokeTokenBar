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
        XCTAssertEqual(individual.exp, 1234)
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

    /// 진화해도 안 줄어든다 — 경험치는 초기화되지만 이건 "함께 일한 기록"이다.
    func testPartnerTokensSurviveEvolution() {
        let store = makeStore()
        let id = partnered(store)
        store.update(todayTokens: 90_000_000, todayDate: "2026-01-01", hasUsageData: true)
        let line = EvoLine(baseID: 1,
                           tree: EvoNode(speciesID: 1, children: [EvoNode(speciesID: 2, children: [])]),
                           rarity: .common, names: [:])
        XCTAssertTrue(store.evolve(individualID: id, to: 2, line: line))
        XCTAssertEqual(find(store, id).exp, 40_000_000, "경험치는 초과분만 이월된다")
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
        store.update(todayTokens: 1_000, todayDate: "2026-01-01", hasUsageData: true)
        XCTAssertEqual(find(store, id).exp, 2_000, "부적이 경험치를 2배로 안 만든다")
        XCTAssertEqual(find(store, id).partnerTokens, 1_000, "기록은 실제 쓴 토큰만 세야 한다")
        XCTAssertEqual(store.state.wallet, walletAfterPurchase + 1_000, "부적이 재화까지 2배로 만들었다")
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
        XCTAssertEqual(store.state.box.first { $0.id == id }?.exp, PlayerStore.expCandyAmount)

        XCTAssertTrue(store.buy(.expCharm))
        XCTAssertTrue(store.buy(.expCandy))
        XCTAssertTrue(store.useExpCandy(on: id))
        XCTAssertEqual(store.state.box.first { $0.id == id }?.exp,
                       PlayerStore.expCandyAmount * 3, "부적을 산 뒤의 사탕이 2배가 아니다")
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

    func testExpCharmIsTheMostExpensive() {
        XCTAssertEqual(ShopItem.expCharm.price, 4_000_000_000)
        for item in ShopItem.allCases where item != .expCharm {
            XCTAssertLessThan(item.price, ShopItem.expCharm.price)
        }
    }
}
