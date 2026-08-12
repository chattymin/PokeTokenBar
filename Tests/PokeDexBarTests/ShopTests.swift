import XCTest
@testable import PokeDexBar

@MainActor
final class ShopTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeStore(wallet: Int, slots: Int = 3) -> PlayerStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("shop-\(UUID().uuidString).json")
        let store = PlayerStore(fileURL: url, rng: SeededRNG(seed: 5), now: { self.now })
        store.seedForTesting(wallet: wallet, slots: slots, eggs: 0, at: now)
        return store
    }

    private func addIndividual(_ store: PlayerStore, shiny: Bool = false) -> UUID {
        let individual = Individual(baseID: 1, speciesID: 1, pathIDs: [1], shiny: shiny,
                                    nature: .serious, exp: 0, obtainedAt: now, grade: .common)
        store.addForTesting(individual)
        return individual.id
    }

    // MARK: 슬롯

    func testBuyingASlotChargesTheLadderPrice() {
        let store = makeStore(wallet: 500_000_000, slots: 3)
        XCTAssertTrue(store.buySlot())
        XCTAssertEqual(store.state.slots, 4)
        XCTAssertEqual(store.state.wallet, 0)
    }

    func testSlotPriceRisesWithEachPurchase() {
        let store = makeStore(wallet: 6_000_000_000, slots: 3)
        XCTAssertTrue(store.buySlot())   // 4번째 500M
        XCTAssertTrue(store.buySlot())   // 5번째 1.5B
        XCTAssertTrue(store.buySlot())   // 6번째 4B
        XCTAssertEqual(store.state.slots, 6)
        XCTAssertEqual(store.state.wallet, 0)
    }

    /// 상한을 넘겨 살 수 없다.
    func testCannotBuyPastMaxSlots() {
        let store = makeStore(wallet: 100_000_000_000, slots: EggBalance.maxSlots)
        XCTAssertFalse(store.buySlot())
        XCTAssertEqual(store.state.slots, EggBalance.maxSlots)
        XCTAssertEqual(store.state.wallet, 100_000_000_000, "실패한 구매는 재화를 쓰지 않는다")
    }

    func testCannotBuySlotWithoutFunds() {
        let store = makeStore(wallet: 499_999_999, slots: 3)
        XCTAssertFalse(store.buySlot())
        XCTAssertEqual(store.state.slots, 3)
    }

    // MARK: 아이템

    func testBuyingAConsumableAddsToInventory() {
        let store = makeStore(wallet: ShopItem.expCandy.price * 2)
        XCTAssertTrue(store.buy(.expCandy))
        XCTAssertTrue(store.buy(.expCandy))
        XCTAssertEqual(store.count(of: .expCandy), 2)
        XCTAssertEqual(store.state.wallet, 0)
    }

    /// 이로치 부적은 보유형 — 한 번 사면 끝이고 두 번 살 수 없다.
    func testShinyCharmIsBoughtOnce() {
        let store = makeStore(wallet: ShopItem.shinyCharm.price * 2)
        XCTAssertTrue(store.buy(.shinyCharm))
        XCTAssertTrue(store.state.ownsShinyCharm)
        XCTAssertFalse(store.buy(.shinyCharm))
        XCTAssertEqual(store.state.wallet, ShopItem.shinyCharm.price)
    }

    func testCannotBuyWithoutFunds() {
        let store = makeStore(wallet: ShopItem.expCandy.price - 1)
        XCTAssertFalse(store.buy(.expCandy))
        XCTAssertEqual(store.count(of: .expCandy), 0)
    }

    // MARK: 사용

    func testExpCandyRaisesExperienceAndIsConsumed() {
        let store = makeStore(wallet: ShopItem.expCandy.price)
        let id = addIndividual(store)
        XCTAssertTrue(store.buy(.expCandy))
        XCTAssertTrue(store.useExpCandy(on: id))
        XCTAssertEqual(store.state.box.first { $0.id == id }?.exp, ExpBalance.candyExp)
        XCTAssertEqual(store.count(of: .expCandy), 0)
    }

    func testCannotUseCandyYouDoNotHave() {
        let store = makeStore(wallet: 0)
        let id = addIndividual(store)
        XCTAssertFalse(store.useExpCandy(on: id))
        XCTAssertEqual(store.state.box.first { $0.id == id }?.exp, 0)
    }

    func testShinyCandyMakesTheIndividualShiny() {
        let store = makeStore(wallet: ShopItem.shinyCandy.price)
        let id = addIndividual(store)
        XCTAssertTrue(store.buy(.shinyCandy))
        XCTAssertTrue(store.useShinyCandy(on: id))
        XCTAssertTrue(store.state.box.first { $0.id == id }?.shiny ?? false)
        XCTAssertEqual(store.count(of: .shinyCandy), 0)
    }

    /// 이미 이로치면 쓸 수 없다 — 사탕을 헛되이 쓰지 않게.
    func testShinyCandyRejectsAlreadyShiny() {
        let store = makeStore(wallet: ShopItem.shinyCandy.price)
        let id = addIndividual(store, shiny: true)
        XCTAssertTrue(store.buy(.shinyCandy))
        XCTAssertFalse(store.useShinyCandy(on: id))
        XCTAssertEqual(store.count(of: .shinyCandy), 1, "쓰지 못했으면 사탕이 남는다")
    }

    /// 박스에 없는 개체에는 쓸 수 없다.
    func testUsingOnUnknownIndividualFails() {
        let store = makeStore(wallet: ShopItem.expCandy.price)
        XCTAssertTrue(store.buy(.expCandy))
        XCTAssertFalse(store.useExpCandy(on: UUID()))
        XCTAssertEqual(store.count(of: .expCandy), 1)
    }
}
