import XCTest
@testable import PokeDexBar

final class HatchNotifierTests: XCTestCase {
    /// 알림은 개체가 아니라 **익은 알**을 받는다 — 개체는 사용자가 확인을 눌러야 생기고,
    /// 알림은 그보다 먼저 나간다.
    private func egg(_ species: Int, shiny: Bool = false) -> Egg {
        Egg(grade: .common, speciesID: species, shiny: shiny,
            startedAt: Date(timeIntervalSince1970: 0),
            hatchesAt: Date(timeIntervalSince1970: 60))
    }

    func testNoMessageWhenNothingHatched() {
        XCTAssertNil(HatchNotifier.message(for: [], language: .ko))
    }

    func testSingleHatchNamesTheSpecies() {
        let message = HatchNotifier.message(for: [egg(1)], language: .ko)
        XCTAssertEqual(message?.title, "알이 부화했어요")
        XCTAssertTrue(message?.body.contains("#1") ?? false, message?.body ?? "")
    }

    /// 이로치는 문구에서 티가 나야 한다 — 놓치면 아까운 정보다.
    func testShinyIsCalledOut() {
        let message = HatchNotifier.message(for: [egg(25, shiny: true)], language: .ko)
        XCTAssertTrue(message?.body.contains("✨") ?? false, message?.body ?? "")
    }

    /// 여러 개가 한꺼번에 깨면 하나로 묶는다 — 알림 폭탄을 만들지 않는다.
    func testMultipleHatchesAreSummarised() {
        let message = HatchNotifier.message(for: [egg(1), egg(4), egg(7)], language: .ko)
        XCTAssertTrue(message?.body.contains("3") ?? false, message?.body ?? "")
    }

    /// 언어 파라미터를 명시적으로 고정 — 실행 기기 로케일에 결과가 좌우되지 않는다.
    func testMessageRespectsExplicitLanguage() {
        let message = HatchNotifier.message(for: [egg(1)], language: .en)
        XCTAssertEqual(message?.title, "An egg hatched")
        XCTAssertTrue(message?.body.contains("#1") ?? false, message?.body ?? "")
    }
}
