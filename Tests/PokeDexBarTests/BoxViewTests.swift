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
}
