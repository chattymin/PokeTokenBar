import XCTest
@testable import PokeDexBar

final class ShopViewTests: XCTestCase {
    /// 확률은 숨기지 않는다 — 표기 문자열을 테스트로 잠근다.
    func testOddsTextListsEveryGrade() {
        let text = ShopTabView.oddsText(.ko)
        XCTAssertTrue(text.contains("커먼 60%"), text)
        XCTAssertTrue(text.contains("레어 22%"), text)
        XCTAssertTrue(text.contains("에픽 15%"), text)
        XCTAssertTrue(text.contains("레전더리 3%"), text)
    }

    /// 표기 확률의 합은 100% 여야 한다 — 밸런스를 고치면 문구도 같이 틀어지는 걸 막는다.
    func testOddsSumToOne() {
        let total = EggBalance.odds.reduce(0) { $0 + $1.probability }
        XCTAssertEqual(total, 1.0, accuracy: 0.0001)
    }
}

/// 진화 도구 수집 현황 — 상점에서 파는 게 아니라 모은 것을 보는 유일한 화면이다.
@MainActor
final class ShopEvolutionItemListTests: XCTestCase {
    private func makeStore() -> PlayerStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("shop-items-\(UUID().uuidString).json")
        return PlayerStore(fileURL: url, rng: SeededRNG(seed: 1),
                           now: { Date(timeIntervalSince1970: 0) })
    }

    /// **아직 못 얻은 것까지 전부** 나와야 한다 — 가진 것만 보여 주면 무엇이 남았는지 알 수 없고,
    /// 도구가 41종을 모으는 목표라는 사실 자체가 화면에서 사라진다.
    func testListsEveryItemIncludingUnowned() {
        let rows = ShopTabView.evolutionItemStatus(makeStore())
        XCTAssertEqual(rows.count, EvolutionItem.allCases.count)
        XCTAssertEqual(Set(rows.map(\.item)), Set(EvolutionItem.allCases))
        XCTAssertTrue(rows.allSatisfy { !$0.owned }, "아무것도 안 얻었는데 보유로 나온다")
    }

    /// 얻은 것만 보유로 표시된다.
    func testOwnedFlagFollowsTheInventory() {
        let store = makeStore()
        store.grantForTesting(.magmarizer)
        let rows = ShopTabView.evolutionItemStatus(store)
        XCTAssertEqual(rows.filter(\.owned).map(\.item), [.magmarizer])
    }

    /// 못 산다는 사실을 세 언어 모두에서 말해야 한다 — 상점 안에 있는 목록이라 특히.
    func testTheNotForSaleHintIsLocalized() {
        let texts = [AppLanguage.ko, .en, .ja].map { L($0).shopEvolutionHint }
        XCTAssertEqual(Set(texts).count, 3, texts.description)
        XCTAssertFalse(texts.contains { $0.isEmpty })
    }
}

/// 뽑기 착지 — 실패를 삼키지 않는지. 후보를 받아오는 동안에도 슬롯·아이템 버튼이 살아 있어
/// 지갑이 뽑기 값 아래로 내려갈 수 있고, 그때 `startEgg` 이 돌려주는 nil 을 버리면 사용자에겐
/// 아무 일도 안 일어난다(재화도 그대로, 알도 없음, 안내도 없음).
@MainActor
final class ShopDrawLandingTests: XCTestCase {
    private func makeStore(wallet: Int, slots: Int = 3, eggs: Int = 0) -> PlayerStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("shop-draw-\(UUID().uuidString).json")
        let store = PlayerStore(fileURL: url, rng: SeededRNG(seed: 1),
                                now: { Date(timeIntervalSince1970: 0) })
        store.seedForTesting(wallet: wallet, slots: slots, eggs: eggs,
                             at: Date(timeIntervalSince1970: 0))
        return store
    }

    func testSuccessfulDrawReportsNoError() {
        let store = makeStore(wallet: EggBalance.drawPrice)
        XCTAssertNil(ShopTabView.landDraw(store, grade: .common, speciesID: 1, shiny: false))
        XCTAssertEqual(store.state.eggs.count, 1)
    }

    /// 조회를 기다리는 사이 지갑이 값 아래로 내려간 경우 — 조용한 무동작 대신 안내가 나와야 한다.
    func testDrawThatCannotLandReportsLocalizedError() {
        let store = makeStore(wallet: EggBalance.drawPrice - 1)
        XCTAssertEqual(ShopTabView.landDraw(store, grade: .common, speciesID: 1, shiny: false),
                       store.l.shopDrawUnavailable)
        XCTAssertTrue(store.state.eggs.isEmpty)
    }

    /// 슬롯이 다 찬 경우도 같은 안내 — 지갑만이 착지 실패 사유가 아니다.
    func testDrawWithNoFreeSlotReportsLocalizedError() {
        let store = makeStore(wallet: 100_000_000_000, slots: 3, eggs: 3)
        XCTAssertNotNil(ShopTabView.landDraw(store, grade: .common, speciesID: 1, shiny: false))
    }

    /// 안내는 세 언어 모두 있어야 한다(빈 문자열·미번역 방지).
    func testDrawUnavailableIsLocalized() {
        let texts = [AppLanguage.ko, .en, .ja].map { L($0).shopDrawUnavailable }
        XCTAssertEqual(Set(texts).count, 3, texts.description)
        XCTAssertFalse(texts.contains { $0.isEmpty })
    }
}

/// 폼 도구 수집 현황 — 진화 도구와 같은 자리, 같은 규칙. 화면이 없으면 24종을 모아도
/// 어디에도 안 보인다.
@MainActor
final class ShopFormItemListTests: XCTestCase {
    private func makeStore() -> PlayerStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("shop-forms-\(UUID().uuidString).json")
        return PlayerStore(fileURL: url, rng: SeededRNG(seed: 1),
                           now: { Date(timeIntervalSince1970: 0) })
    }

    func testListsEveryFormItem() {
        let rows = ShopTabView.formItemStatus(makeStore())
        XCTAssertEqual(Set(rows.map(\.item)), Set(FormItem.allCases))
        XCTAssertTrue(rows.allSatisfy { !$0.owned })
    }

    func testOwnedFlagFollowsTheInventory() {
        let store = makeStore()
        store.grantForTesting(FormItem.griseousCore)
        XCTAssertEqual(ShopTabView.formItemStatus(store).filter(\.owned).map(\.item),
                       [.griseousCore])
    }

    /// 두 목록이 같은 품목을 서로 보여 주면 안 된다 — 인벤토리를 나눠 쓰는 만큼 표시도 갈려야 한다.
    func testTheTwoListsDoNotOverlap() {
        let store = makeStore()
        let evo = Set(ShopTabView.evolutionItemStatus(store).map(\.item.rawValue))
        let form = Set(ShopTabView.formItemStatus(store).map(\.item.rawValue))
        XCTAssertTrue(evo.isDisjoint(with: form))
    }
}
