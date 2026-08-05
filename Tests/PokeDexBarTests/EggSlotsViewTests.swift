import XCTest
@testable import PokeDexBar

final class EggSlotsViewTests: XCTestCase {
    /// 한국어 표기 — 단위는 큰 것 두 개까지만.
    func testCountdownFormatsKorean() {
        XCTAssertEqual(EggSlotsView.countdownText(0, .ko), "부화!")
        XCTAssertEqual(EggSlotsView.countdownText(45, .ko), "45초")
        XCTAssertEqual(EggSlotsView.countdownText(90, .ko), "1분 30초")
        XCTAssertEqual(EggSlotsView.countdownText(3 * 3600 + 12 * 60, .ko), "3시간 12분")
        XCTAssertEqual(EggSlotsView.countdownText(25 * 3600, .ko), "1일 1시간")
    }

    func testCountdownFormatsEnglish() {
        XCTAssertEqual(EggSlotsView.countdownText(0, .en), "Hatched!")
        XCTAssertEqual(EggSlotsView.countdownText(45, .en), "45s")
        XCTAssertEqual(EggSlotsView.countdownText(90, .en), "1m 30s")
        XCTAssertEqual(EggSlotsView.countdownText(3 * 3600 + 12 * 60, .en), "3h 12m")
        XCTAssertEqual(EggSlotsView.countdownText(25 * 3600, .en), "1d 1h")
    }

    func testCountdownFormatsJapanese() {
        XCTAssertEqual(EggSlotsView.countdownText(0, .ja), "ふ化!")
        XCTAssertEqual(EggSlotsView.countdownText(45, .ja), "45秒")
        XCTAssertEqual(EggSlotsView.countdownText(90, .ja), "1分30秒")
        XCTAssertEqual(EggSlotsView.countdownText(3 * 3600 + 12 * 60, .ja), "3時間12分")
        XCTAssertEqual(EggSlotsView.countdownText(25 * 3600, .ja), "1日1時間")
    }

    /// 남은 시간이 음수로 들어와도(시계 되감김) 부화로 표시한다.
    func testNegativeRemainingIsReady() {
        XCTAssertEqual(EggSlotsView.countdownText(-10, .ko), "부화!")
    }
}
