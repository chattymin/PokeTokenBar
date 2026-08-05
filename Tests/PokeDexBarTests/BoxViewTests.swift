import AppKit
import SwiftUI
import XCTest
@testable import PokeDexBar

@MainActor
final class BoxViewTests: XCTestCase {
    private func individual(grade: Grade, exp: Int, path: [Int]) -> Individual {
        Individual(baseID: path.first ?? 1, speciesID: path.last ?? 1, pathIDs: path,
                   nature: .serious, exp: exp,
                   obtainedAt: Date(timeIntervalSince1970: 0), grade: grade)
    }

    func testProgressIsExpOverThreshold() {
        let half = individual(grade: .common, exp: 25_000_000, path: [1])
        XCTAssertEqual(BoxTabView.progress(half), 0.5, accuracy: 0.001)
    }

    /// 임계를 넘겨도 1을 넘지 않는다 — 게이지가 칸 밖으로 나가면 안 된다.
    func testProgressClampsAtOne() {
        let over = individual(grade: .common, exp: 999_000_000, path: [1])
        XCTAssertEqual(BoxTabView.progress(over), 1.0, accuracy: 0.001)
    }

    func testProgressIsZeroForFreshIndividual() {
        XCTAssertEqual(BoxTabView.progress(individual(grade: .epic, exp: 0, path: [4])), 0)
    }

    // MARK: 진화 라인 fetch 중복방지 — 같은 종 여럿이 동시에 화면에 뜨는 게 박스의 정상 시나리오.

    func testShouldStartLoadingLineWhenNeitherLoadedNorLoading() {
        XCTAssertTrue(PopoverView.shouldStartLoadingLine(1, loadedIDs: [], loadingIDs: []))
    }

    /// 같은 종 개체 여럿이 동시에 `.task` 를 발화해도, 첫 호출이 등록해 둔 loadingIDs 를 보고
    /// 나머지 호출은 새 fetch 를 시작하지 않는다 — 이게 없으면 Pidgey 세 마리가 라인을 세 번 받아온다.
    func testShouldNotStartLoadingLineWhileAlreadyLoading() {
        XCTAssertFalse(PopoverView.shouldStartLoadingLine(1, loadedIDs: [], loadingIDs: [1]))
    }

    func testShouldNotStartLoadingLineWhenAlreadyLoaded() {
        XCTAssertFalse(PopoverView.shouldStartLoadingLine(1, loadedIDs: [1], loadingIDs: []))
    }

    func testShouldStartLoadingLineIsPerBaseID() {
        // 다른 baseID 는 서로의 로딩 상태에 영향받지 않는다.
        XCTAssertTrue(PopoverView.shouldStartLoadingLine(2, loadedIDs: [], loadingIDs: [1]))
    }
}

/// 사탕 배선 — 상점에서 파는 사탕을 **박스 화면에서 실제로 쓸 수 있는지**를 잰다.
/// `store.useExpCandy(on:)` 를 직접 부르는 테스트는 스토어만 확인해 UI 가 통째로 빠져도 통과한다
/// (실제로 그렇게 나갔다). 그래서 뷰를 호스팅해 버튼이 만들어지는지 + 그 버튼의 동작이 사탕을
/// 쓰는지까지 확인한다(`SpriteView.constructionCount` 와 같은 계측 패턴).
@MainActor
final class BoxCandyWiringTests: XCTestCase {
    private func makeStore(shiny: Bool = false, expCandies: Int = 0, shinyCandies: Int = 0) -> PlayerStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("box-candy-\(UUID().uuidString).json")
        let store = PlayerStore(fileURL: url, rng: SeededRNG(seed: 1),
                                now: { Date(timeIntervalSince1970: 0) })
        store.addForTesting(Individual(baseID: 1, speciesID: 1, pathIDs: [1], shiny: shiny,
                                       nature: .serious, exp: 0,
                                       obtainedAt: Date(timeIntervalSince1970: 0), grade: .common))
        // 사탕은 실제 구매 경로로 넣는다 — 인벤토리를 직접 심으면 상점 가격과 어긋날 수 있다.
        store.seedForTesting(wallet: 100_000_000_000, slots: 3, eggs: 0,
                             at: Date(timeIntervalSince1970: 0))
        for _ in 0..<expCandies { XCTAssertTrue(store.buy(.expCandy)) }
        for _ in 0..<shinyCandies { XCTAssertTrue(store.buy(.shinyCandy)) }
        return store
    }

    /// 박스 행을 실제로 그려 사탕 버튼을 수집한다.
    private func renderedCandyButtons(_ store: PlayerStore) -> [(title: String, action: () -> Void)] {
        CandyButton.resetConstructed()
        let host = NSHostingView(rootView: BoxTabView(store: store, lines: [:], onNeedLine: { _ in })
            .frame(width: PopoverMetrics.width))
        host.layoutSubtreeIfNeeded()
        return CandyButton.constructed
    }

    /// 경험치 사탕: 박스 행에 버튼이 뜨고, 누르면 그 개체에 경험치가 들어가고 재고가 준다.
    func testExpCandyButtonAppliesExpToThatIndividual() {
        let store = makeStore(expCandies: 2)
        let buttons = renderedCandyButtons(store)
        guard let button = buttons.first(where: { $0.title == store.l.useExpCandy(2) }) else {
            return XCTFail("경험치 사탕 버튼이 박스에 없다 — 산 사탕을 쓸 수 있는 화면이 없다: \(buttons.map(\.title))")
        }
        button.action()
        XCTAssertEqual(store.state.box.first?.exp, PlayerStore.expCandyAmount)
        XCTAssertEqual(store.count(of: .expCandy), 1, "쓴 사탕이 재고에서 빠져야 한다")
    }

    /// 반짝이는 사탕: 버튼이 뜨고, 누르면 그 개체가 이로치가 된다.
    func testShinyCandyButtonMakesThatIndividualShiny() {
        let store = makeStore(shinyCandies: 1)
        let buttons = renderedCandyButtons(store)
        guard let button = buttons.first(where: { $0.title == store.l.useShinyCandy(1) }) else {
            return XCTFail("반짝이는 사탕 버튼이 박스에 없다: \(buttons.map(\.title))")
        }
        button.action()
        XCTAssertEqual(store.state.box.first?.shiny, true)
        XCTAssertEqual(store.count(of: .shinyCandy), 0)
    }

    /// 안 가진 사탕의 버튼은 안 보인다 — 눌러도 아무 일 없는 버튼을 두지 않는다.
    func testNoCandyButtonsWithoutInventory() {
        XCTAssertTrue(renderedCandyButtons(makeStore()).isEmpty)
    }

    /// 이미 이로치인 개체에는 반짝이는 사탕을 권하지 않는다(`useShinyCandy` 가 거절하는 조건).
    /// 경험치 사탕은 그대로 보인다 — 이로치 여부와 무관하다.
    func testShinyCandyHiddenForAlreadyShinyIndividual() {
        let store = makeStore(shiny: true, expCandies: 1, shinyCandies: 1)
        let titles = renderedCandyButtons(store).map(\.title)
        XCTAssertFalse(titles.contains(store.l.useShinyCandy(1)), titles.description)
        XCTAssertTrue(titles.contains(store.l.useExpCandy(1)), titles.description)
    }
}
