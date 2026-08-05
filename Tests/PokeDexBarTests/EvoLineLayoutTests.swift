import XCTest
import SwiftUI
@testable import PokeDexBar

// 진화 라인 가로 오버플로 가드.
// 긴 진화 라인은 폭 제한이 없으면 팝오버 콘텐츠 폭(332pt)을 훌쩍 넘고, 넘친 자식이 부모 VStack 폭을
// 부풀려 팝오버 콘텐츠 "전체"가 좌우로 잘렸다. maxWidth 를 주면 그 폭 안에서 가로 스크롤한다.
//
// 트리거 브랜치를 직접 재현한다: maxWidth 없는 라인이 실제로 넘치는지까지 확인해야
// "fit 어서션이 애초에 통과할 조건이었다"는 false confidence 를 막는다.
@MainActor
final class EvoLineLayoutTests: XCTestCase {

    /// 긴 라인 합성 입력. 홈 화면의 미확정 분기는 `?` 하나로 숨기지만, EvoLineView 자체의
    /// 오버플로 방어는 어떤 긴 노드 배열에도 유지돼야 한다.
    private var longNodes: [EvoLineItem] {
        [EvoLineItem(.species(133), .current)]
            + [134, 135, 136, 196, 197, 470, 471, 700].map { EvoLineItem(.species($0), .future) }
    }

    /// 3단계 일반 라인(이상해씨 계열) — 스크롤이 붙으면 안 되는 대조군.
    private var threeStageNodes: [EvoLineItem] {
        [EvoLineItem(.species(1), .done), EvoLineItem(.species(2), .current), EvoLineItem(.species(3), .future)]
    }

    /// 팝오버가 실제로 제안하는 폭으로 뷰를 재어 렌더 폭을 얻는다.
    private func renderedWidth(_ view: some View, proposing: CGFloat) -> CGFloat {
        NSHostingController(rootView: view)
            .sizeThatFits(in: CGSize(width: proposing, height: 600)).width
    }

    // MARK: 렌더 폭 — 실제 레이아웃 회귀

    /// 트리거 재현: 폭 제한이 없으면 긴 라인은 팝오버 콘텐츠 폭을 넘는다(= 버그 조건).
    func testLongEvolutionLineWithoutMaxWidthOverflowsPopoverContent() {
        let w = renderedWidth(EvoLineView(nodes: longNodes, mysteryLabel: L(.en).unknownNextEvolution),
                              proposing: PopoverMetrics.contentWidth)
        XCTAssertGreaterThan(w, PopoverMetrics.contentWidth,
                             "폭 제한 없는 진화 라인은 넘쳐야 한다 — 안 넘치면 아래 fit 검증이 무의미해진다")
    }

    /// 수정 후: 팝오버가 주는 폭을 넘지 않는다(→ 부모 VStack 이 안 부풀고 팝오버가 안 잘린다).
    func testLongEvolutionLineFitsPopoverContentWidth() {
        let w = renderedWidth(EvoLineView(nodes: longNodes, mysteryLabel: L(.en).unknownNextEvolution,
                                          maxWidth: PopoverMetrics.contentWidth),
                              proposing: PopoverMetrics.contentWidth)
        XCTAssertLessThanOrEqual(w, PopoverMetrics.contentWidth)
    }

    /// 도감 행(썸네일 56 + 이름 라벨)도 카드 안쪽 폭을 넘지 않는다.
    func testLongDexChainFitsCardWidth() {
        let cardWidth = PopoverMetrics.contentWidth - 16   // DexEntryRow 카드 좌우 패딩 8pt
        let ids = [1, 2, 3, 4, 5]
        let nodes = ids.map { EvoLineItem(.species($0), .done) }
        let names = Dictionary(uniqueKeysWithValues: ids.map { ($0, "이상해씨") })
        let w = renderedWidth(
            EvoLineView(nodes: nodes, mysteryLabel: L(.ko).unknownNextEvolution,
                        thumb: 56, names: names, maxWidth: cardWidth),
            proposing: cardWidth)
        XCTAssertLessThanOrEqual(w, cardWidth)
    }

    /// 짧은 라인은 스크롤 컨테이너 없이 예전과 똑같은 폭으로 그려진다(일반 라인 시각 회귀 방지).
    func testShortChainRendersInlineAtNaturalWidth() {
        // 3칸 = 40*3 + 화살표 10*2 + 간격 2*4 = 148pt
        let expected = EvoLineView.rowWidth(count: 3, thumb: 40, hasNames: false)
        XCTAssertEqual(expected, 148)
        let w = renderedWidth(EvoLineView(nodes: threeStageNodes, mysteryLabel: L(.en).unknownNextEvolution,
                                          maxWidth: PopoverMetrics.contentWidth),
                              proposing: PopoverMetrics.contentWidth)
        XCTAssertEqual(w, expected, accuracy: 0.5)
    }

    // MARK: 순수 판정 — 스크롤 전환 경계

    /// rowWidth 는 레이아웃과 같은 식이어야 한다(측정값과 일치 — 어긋나면 스크롤 판정이 틀어진다).
    func testRowWidthMatchesRenderedWidth() {
        for count in 1...9 {
            let nodes = (1...count).map { i in
                i == count ? EvoLineItem(.mystery, .future) : EvoLineItem(.species(i), .done)
            }
            let rendered = renderedWidth(EvoLineView(nodes: nodes, mysteryLabel: L(.en).unknownNextEvolution),
                                         proposing: 4000)
            XCTAssertEqual(rendered,
                           EvoLineView.rowWidth(count: count, thumb: 40, hasNames: false),
                           accuracy: 0.5, "count=\(count)")
        }
    }

    /// mystery 는 이름이 없더라도 도감 라인의 이름 열 폭을 예약해야 rowWidth 기반 스크롤 판정과 일치한다.
    func testNamedMysteryCellReservesNameColumnWidth() {
        let nodes = [EvoLineItem(.species(1), .done), EvoLineItem(.mystery, .future)]
        let names = [1: String(repeating: "W", count: 20)]
        let rendered = renderedWidth(EvoLineView(nodes: nodes, mysteryLabel: L(.en).unknownNextEvolution, names: names),
                                     proposing: 4000)

        XCTAssertEqual(rendered,
                       EvoLineView.rowWidth(count: nodes.count, thumb: 40, hasNames: true),
                       accuracy: 0.5)
    }

    /// 홈 라인(썸네일 40)은 6칸까지 그대로, 7칸부터 스크롤.
    func testNeedsScrollBoundaryForHomeLine() {
        let w = PopoverMetrics.contentWidth
        XCTAssertFalse(EvoLineView.needsScroll(count: 6, thumb: 40, hasNames: false, maxWidth: w))
        XCTAssertTrue(EvoLineView.needsScroll(count: 7, thumb: 40, hasNames: false, maxWidth: w))
        XCTAssertTrue(EvoLineView.needsScroll(count: 9, thumb: 40, hasNames: false, maxWidth: w))
    }

    /// 도감 행(썸네일 56 + 이름)은 4칸까지 그대로, 5칸부터 스크롤.
    func testNeedsScrollBoundaryForDexRow() {
        let w = PopoverMetrics.contentWidth - 16
        XCTAssertFalse(EvoLineView.needsScroll(count: 4, thumb: 56, hasNames: true, maxWidth: w))
        XCTAssertTrue(EvoLineView.needsScroll(count: 5, thumb: 56, hasNames: true, maxWidth: w))
    }

    /// maxWidth 를 안 주면(기본 .infinity) 스크롤을 붙이지 않는다 — 폭이 고정되지 않은 호출부용 기본값.
    func testUnboundedWidthNeverScrolls() {
        XCTAssertFalse(EvoLineView.needsScroll(count: 99, thumb: 40, hasNames: false, maxWidth: .infinity))
    }

    // MARK: 스크롤 가능 신호 — 남은 방향에만 뜬다

    /// 페이드·셰브론은 "그쪽에 더 있을 때만" 떠야 한다. 스냅샷으로는 첫 프레임(맨 왼쪽)밖에 못 봐서
    /// 스크롤 중간/끝 상태는 이 순수 판정으로 잠근다.
    func testAffordanceShowsOnlyWhereContentRemains() {
        let content = EvoLineView.rowWidth(count: 9, thumb: 40, hasNames: false)   // 472
        let view = PopoverMetrics.contentWidth                                      // 332

        // 맨 왼쪽 — 오른쪽으로만 더 있다
        var a = EvoLineView.scrollAffordance(scrollX: 0, contentWidth: content, maxWidth: view)
        XCTAssertFalse(a.back); XCTAssertTrue(a.forward)

        // 중간 — 양쪽 다
        a = EvoLineView.scrollAffordance(scrollX: 70, contentWidth: content, maxWidth: view)
        XCTAssertTrue(a.back); XCTAssertTrue(a.forward)

        // 끝까지 스크롤 — 왼쪽으로만 (끝에서 오른쪽 셰브론이 남으면 눌러도 안 움직인다)
        a = EvoLineView.scrollAffordance(scrollX: content - view, contentWidth: content, maxWidth: view)
        XCTAssertTrue(a.back); XCTAssertFalse(a.forward)
    }

    /// 셰브론은 누를 때마다 더 나아가야 한다 — 목표가 현재 위치에 따라 바뀌는지, 범위를 안 넘는지.
    /// (고정 목표로 두면 한 번 이동한 뒤 다시 눌러도 제자리가 된다.)
    func testPageTargetAdvancesAndStaysInBounds() {
        let w = PopoverMetrics.contentWidth
        func target(_ forward: Bool, at scrollX: CGFloat) -> Int {
            EvoLineView.pageTarget(forward: forward, scrollX: scrollX, count: 9,
                                   thumb: 40, hasNames: false, maxWidth: w)
        }
        // 맨 왼쪽에서 앞으로 = 한 화면(332/54 = 6칸)만큼
        XCTAssertEqual(target(true, at: 0), 6)
        // 이동한 뒤 또 누르면 더 앞으로 (제자리 금지)
        XCTAssertGreaterThan(target(true, at: 54), target(true, at: 0))
        // 마지막 칸을 안 넘음
        XCTAssertEqual(target(true, at: 300), 8)
        // 0 아래로 안 내려감
        XCTAssertEqual(target(false, at: 0), 0)
        XCTAssertEqual(target(false, at: 140), 0)
    }

    /// 넘치지 않는 줄에는 어느 쪽 신호도 뜨지 않는다.
    func testAffordanceHiddenWhenContentFits() {
        let a = EvoLineView.scrollAffordance(scrollX: 0, contentWidth: 148,
                                             maxWidth: PopoverMetrics.contentWidth)
        XCTAssertFalse(a.back); XCTAssertFalse(a.forward)
    }
}
