import AppKit
import SwiftUI
import XCTest
@testable import PokeDexBar

@MainActor
final class BoxViewTests: XCTestCase {
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

    /// 개체를 선택한 상태의 박스를 실제로 그려 사탕 버튼을 수집한다 — 사탕은 상세 화면에 있으므로
    /// 선택이 없으면 나오지 않는다. 그리드에서 상세로 가는 길 자체는 `testTappingACellOpensTheDetail`.
    private func renderedCandyButtons(_ store: PlayerStore) -> [(title: String, action: () -> Void)] {
        CandyButton.resetConstructed()
        let selected = store.state.box.first!.id
        let host = NSHostingView(rootView: BoxTabView(store: store, lines: [:], onNeedLine: { _ in },
                                                      selection: .constant(selected))
            .frame(width: PopoverMetrics.width))
        host.layoutSubtreeIfNeeded()
        return CandyButton.constructed
    }

    /// 그리드 칸을 누르면 그 개체의 상세가 열린다 — 이 연결이 끊기면 사탕·진화 화면에 갈 길이 없다.
    /// 위 테스트들은 선택을 고정해 두고 그리므로 이 경로를 안 밟는다.
    func testTappingACellOpensTheDetail() {
        let store = makeStore()
        let target = store.state.box.first!.id
        var selection: UUID?
        BoxCell.resetConstructed()
        let host = NSHostingView(rootView: BoxTabView(
            store: store, lines: [:], onNeedLine: { _ in },
            selection: Binding(get: { selection }, set: { selection = $0 })
        ).frame(width: PopoverMetrics.width))
        host.layoutSubtreeIfNeeded()

        guard let cell = BoxCell.constructed.first(where: { $0.id == target }) else {
            return XCTFail("박스 그리드에 개체 칸이 없다 — 상세로 들어갈 길이 없다")
        }
        cell.onTap()
        XCTAssertEqual(selection, target, "칸을 눌렀는데 상세가 안 열린다")
    }

    /// 경험치 사탕: 박스 행에 버튼이 뜨고, 누르면 그 개체에 경험치가 들어가고 재고가 준다.
    func testExpCandyButtonAppliesExpToThatIndividual() {
        let store = makeStore(expCandies: 2)
        let buttons = renderedCandyButtons(store)
        guard let button = buttons.first(where: { $0.title == store.l.useExpCandy(2) }) else {
            return XCTFail("경험치 사탕 버튼이 박스에 없다 — 산 사탕을 쓸 수 있는 화면이 없다: \(buttons.map(\.title))")
        }
        button.action()
        XCTAssertEqual(store.state.box.first?.exp, ExpBalance.candyExp)
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

/// 표시 이름 — 홈 카드는 진화 라인을 이미 받아 두고도 번호만 보여주고 있었다(사용자 지적).
/// 이름 조립 규칙을 개체 한 곳에 두고 화면들이 같은 규칙을 쓰는지 잠근다.
final class IndividualDisplayNameTests: XCTestCase {
    private func make(species: Int, base: Int = 1) -> Individual {
        Individual(baseID: base, speciesID: species, pathIDs: [base, species], nature: .serious,
                   obtainedAt: Date(timeIntervalSince1970: 0), grade: .common)
    }

    func testPlainIndividualUsesTheSpeciesName() {
        XCTAssertEqual(make(species: 6).displayName(speciesName: "리자몽", .ko), "리자몽")
    }

    /// 라인을 아직 못 받았으면 호출부가 번호를 넘긴다 — 그대로 나와야 한다.
    func testFallsBackToWhateverTheCallerPassed() {
        XCTAssertEqual(make(species: 6).displayName(speciesName: "#6", .ko), "#6")
    }

    func testRegionPrefixesTheName() {
        var meowth = make(species: 52, base: 52)
        meowth.region = .galar
        XCTAssertEqual(meowth.displayName(speciesName: "나옹", .ko), "가라르 나옹")
    }

    /// 메가·거다이맥스가 지방보다 우선한다 — 접두는 하나만 붙는다.
    func testFormWinsOverRegion() {
        var charizard = make(species: 6, base: 4)
        charizard.region = .galar
        charizard.form = "charizard-megax"
        XCTAssertEqual(charizard.displayName(speciesName: "Charizard", .en), "Mega Charizard X")
    }

    /// 그 종에 지방 모습이 없으면 접두를 안 붙인다 — 나이킹은 "가라르 나이킹"이 아니다.
    /// (혈통은 남지만 그 종의 모습 이름은 아니다.)
    func testNoPrefixWhenTheSpeciesHasNoRegionalLook() {
        var perrserker = make(species: 863, base: 52)
        perrserker.region = .galar
        XCTAssertEqual(perrserker.displayName(speciesName: "나이킹", .ko), "나이킹")
    }
}

/// 보관함 페이지 — 본가 PC 처럼 고정 30칸(6×5) 상자를 넘긴다.
final class BoxPagingTests: XCTestCase {
    func testEmptyBoxStillHasOnePage() {
        XCTAssertEqual(BoxTabView.pageCount(forBoxCount: 0), 1, "빈 보관함도 상자는 하나 있다")
    }

    func testAFullPageDoesNotSpillIntoTheNext() {
        XCTAssertEqual(BoxTabView.pageCount(forBoxCount: BoxTabView.pageSize), 1)
        XCTAssertEqual(BoxTabView.pageCount(forBoxCount: BoxTabView.pageSize + 1), 2)
    }

    func testGridIsSixByFive() {
        XCTAssertEqual(BoxTabView.columnCount, 6)
        XCTAssertEqual(BoxTabView.rowCount, 5)
        XCTAssertEqual(BoxTabView.pageSize, 30)
    }

    /// 마지막 상자를 보다가 개체가 줄면(진화가 아니라 정리 등) 빈 페이지에 갇히면 안 된다.
    func testPageIsClampedWhenPagesShrink() {
        XCTAssertEqual(BoxTabView.clampedPage(3, pageCount: 2), 1)
        XCTAssertEqual(BoxTabView.clampedPage(0, pageCount: 1), 0)
        XCTAssertEqual(BoxTabView.clampedPage(-1, pageCount: 3), 0, "음수 페이지로 새면 안 된다")
        XCTAssertEqual(BoxTabView.clampedPage(5, pageCount: 0), 0)
    }

    /// 한 칸에 폭 48 + 간격 5 로 6열이 팝오버 콘텐츠 폭(332pt) 안에 들어가야 한다.
    /// 넘으면 마지막 열이 잘리는데, 스크롤이 없어서 영영 못 본다.
    func testARowFitsInsideThePopover() {
        let width = CGFloat(BoxTabView.columnCount) * 48
            + CGFloat(BoxTabView.columnCount - 1) * 5
            + 12   // 상자 안쪽 여백(좌우 6)
        XCTAssertLessThanOrEqual(width, PopoverMetrics.contentWidth,
                                 "6열이 팝오버 폭을 넘어 마지막 칸이 잘린다")
    }
}
