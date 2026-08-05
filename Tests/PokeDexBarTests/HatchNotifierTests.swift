import XCTest
@testable import PokeDexBar

final class HatchNotifierTests: XCTestCase {
    private func individual(_ species: Int, shiny: Bool = false) -> Individual {
        Individual(baseID: species, speciesID: species, pathIDs: [species], shiny: shiny,
                   nature: .serious, exp: 0, obtainedAt: Date(timeIntervalSince1970: 0),
                   grade: .common)
    }

    func testNoMessageWhenNothingHatched() {
        XCTAssertNil(HatchNotifier.message(for: [], language: .ko))
    }

    func testSingleHatchNamesTheSpecies() {
        let message = HatchNotifier.message(for: [individual(1)], language: .ko)
        XCTAssertEqual(message?.title, "알이 부화했어요")
        XCTAssertTrue(message?.body.contains("#1") ?? false, message?.body ?? "")
    }

    /// 이로치는 문구에서 티가 나야 한다 — 놓치면 아까운 정보다.
    func testShinyIsCalledOut() {
        let message = HatchNotifier.message(for: [individual(25, shiny: true)], language: .ko)
        XCTAssertTrue(message?.body.contains("✨") ?? false, message?.body ?? "")
    }

    /// 여러 개가 한꺼번에 깨면 하나로 묶는다 — 알림 폭탄을 만들지 않는다.
    func testMultipleHatchesAreSummarised() {
        let message = HatchNotifier.message(for: [individual(1), individual(4), individual(7)], language: .ko)
        XCTAssertTrue(message?.body.contains("3") ?? false, message?.body ?? "")
    }

    /// 언어 파라미터를 명시적으로 고정 — 실행 기기 로케일에 결과가 좌우되지 않는다.
    func testMessageRespectsExplicitLanguage() {
        let message = HatchNotifier.message(for: [individual(1)], language: .en)
        XCTAssertEqual(message?.title, "An egg hatched")
        XCTAssertTrue(message?.body.contains("#1") ?? false, message?.body ?? "")
    }
}
