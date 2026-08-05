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
