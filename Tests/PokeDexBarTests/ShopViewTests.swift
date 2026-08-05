import XCTest
@testable import PokeDexBar

final class ShopViewTests: XCTestCase {
    /// 확률은 숨기지 않는다 — 표기 문자열을 테스트로 잠근다.
    func testOddsTextListsEveryGrade() {
        let text = ShopTabView.oddsText(.ko)
        XCTAssertTrue(text.contains("커먼 55%"), text)
        XCTAssertTrue(text.contains("레어 15%"), text)
        XCTAssertTrue(text.contains("에픽 25%"), text)
        XCTAssertTrue(text.contains("레전더리 5%"), text)
    }

    /// 표기 확률의 합은 100% 여야 한다 — 밸런스를 고치면 문구도 같이 틀어지는 걸 막는다.
    func testOddsSumToOne() {
        let total = EggBalance.odds.reduce(0) { $0 + $1.probability }
        XCTAssertEqual(total, 1.0, accuracy: 0.0001)
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
