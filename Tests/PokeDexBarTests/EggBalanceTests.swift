import XCTest
@testable import PokeDexBar

final class EggBalanceTests: XCTestCase {
    /// 확률표는 등급별 실제 종 수에 맞춘 값이다 — 누적 경계로 검증한다.
    func testGradeRollBoundaries() {
        XCTAssertEqual(EggBalance.rollGrade(0.0), .common)
        XCTAssertEqual(EggBalance.rollGrade(0.549), .common)
        XCTAssertEqual(EggBalance.rollGrade(0.55), .rare)
        XCTAssertEqual(EggBalance.rollGrade(0.699), .rare)
        XCTAssertEqual(EggBalance.rollGrade(0.70), .epic)
        XCTAssertEqual(EggBalance.rollGrade(0.949), .epic)
        XCTAssertEqual(EggBalance.rollGrade(0.95), .legendary)
        XCTAssertEqual(EggBalance.rollGrade(0.999), .legendary)
    }

    /// 범위 밖 입력(부동소수 오차)에도 등급이 나온다 — nil 이나 크래시로 새지 않는다.
    func testGradeRollClamps() {
        XCTAssertEqual(EggBalance.rollGrade(-0.5), .common)
        XCTAssertEqual(EggBalance.rollGrade(1.5), .legendary)
    }

    func testDurations() {
        XCTAssertEqual(EggBalance.duration(.common), 30 * 60)
        XCTAssertEqual(EggBalance.duration(.rare), 2 * 3600)
        XCTAssertEqual(EggBalance.duration(.epic), 6 * 3600)
        XCTAssertEqual(EggBalance.duration(.legendary), 24 * 3600)
    }

    /// 등급이 높을수록 오래 걸린다.
    func testDurationsIncreaseWithGrade() {
        XCTAssertLessThan(EggBalance.duration(.common), EggBalance.duration(.rare))
        XCTAssertLessThan(EggBalance.duration(.rare), EggBalance.duration(.epic))
        XCTAssertLessThan(EggBalance.duration(.epic), EggBalance.duration(.legendary))
    }

    /// 슬롯 가격은 4·5·6번째만 있고 그 위는 없다(상한 6).
    func testSlotPriceLadder() {
        XCTAssertEqual(EggBalance.slotPrice(forSlotNumber: 4), 500_000_000)
        XCTAssertEqual(EggBalance.slotPrice(forSlotNumber: 5), 1_500_000_000)
        XCTAssertEqual(EggBalance.slotPrice(forSlotNumber: 6), 4_000_000_000)
        XCTAssertNil(EggBalance.slotPrice(forSlotNumber: 7))
        XCTAssertNil(EggBalance.slotPrice(forSlotNumber: 3), "기본 3슬롯은 사는 게 아니다")
    }

    /// 이로치는 1/64, 부적이 있으면 1/48 — 경계 바로 안팎을 잠근다.
    func testShinyOdds() {
        XCTAssertTrue(EggBalance.rollShiny(1.0 / 64 - 0.0001, hasCharm: false))
        XCTAssertFalse(EggBalance.rollShiny(1.0 / 64 + 0.0001, hasCharm: false))
        XCTAssertTrue(EggBalance.rollShiny(1.0 / 48 - 0.0001, hasCharm: true))
        XCTAssertFalse(EggBalance.rollShiny(1.0 / 48 + 0.0001, hasCharm: true))
    }

    /// 부적은 확률을 낮추지 않는다 — 같은 굴림이면 부적 쪽이 더 자주 이로치다.
    func testCharmNeverHurts() {
        for step in 0...100 {
            let roll = Double(step) / 100
            if EggBalance.rollShiny(roll, hasCharm: false) {
                XCTAssertTrue(EggBalance.rollShiny(roll, hasCharm: true))
            }
        }
    }

    /// 기본 슬롯 수는 `EggBalance.baseSlots` 와 `PlayerState().slots` 두 리터럴로 따로 적혀
    /// 있다(주석으로만 연결) — 이 테스트가 둘을 묶어 드리프트를 막는다.
    func testBaseSlotsMatchesPlayerStateDefault() {
        XCTAssertEqual(EggBalance.baseSlots, PlayerState().slots)
    }
}

final class EggTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func egg(hatchesIn seconds: TimeInterval) -> Egg {
        Egg(grade: .common, speciesID: 1, shiny: false,
            startedAt: now, hatchesAt: now.addingTimeInterval(seconds))
    }

    func testReadyOnlyAfterHatchTime() {
        XCTAssertFalse(egg(hatchesIn: 10).isReady(at: now))
        XCTAssertTrue(egg(hatchesIn: 10).isReady(at: now.addingTimeInterval(10)))
        XCTAssertTrue(egg(hatchesIn: 10).isReady(at: now.addingTimeInterval(999)))
    }

    func testRemainingNeverNegative() {
        XCTAssertEqual(egg(hatchesIn: 60).remaining(at: now), 60, accuracy: 0.001)
        XCTAssertEqual(egg(hatchesIn: 60).remaining(at: now.addingTimeInterval(999)), 0)
    }
}
