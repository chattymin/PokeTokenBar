import XCTest
@testable import PokeDexBar

final class GrowthRateTests: XCTestCase {
    /// 100레벨 도달치 — 본가 표 그대로. 이 여섯이 맞으면 곡선 전체가 맞다고 본다.
    func testTotalExpAtOneHundredMatchesTheGames() {
        XCTAssertEqual(GrowthRate.erratic.totalExp(at: 100), 600_000)
        XCTAssertEqual(GrowthRate.fast.totalExp(at: 100), 800_000)
        XCTAssertEqual(GrowthRate.mediumFast.totalExp(at: 100), 1_000_000)
        XCTAssertEqual(GrowthRate.mediumSlow.totalExp(at: 100), 1_059_860)
        XCTAssertEqual(GrowthRate.slow.totalExp(at: 100), 1_250_000)
        XCTAssertEqual(GrowthRate.fluctuating.totalExp(at: 100), 1_640_000)
    }

    /// 중간 지점도 본가 표와 맞는지 — 100레벨만 맞고 중간이 틀린 공식이 있을 수 있다.
    func testMidCurveValuesMatchTheGames() {
        XCTAssertEqual(GrowthRate.mediumSlow.totalExp(at: 16), 2_535)
        XCTAssertEqual(GrowthRate.mediumSlow.totalExp(at: 36), 40_007)
        XCTAssertEqual(GrowthRate.mediumFast.totalExp(at: 16), 4_096)
        XCTAssertEqual(GrowthRate.slow.totalExp(at: 16), 5_120)
        XCTAssertEqual(GrowthRate.erratic.totalExp(at: 16), 6_881)
        XCTAssertEqual(GrowthRate.fluctuating.totalExp(at: 16), 2_457)
    }

    /// **1레벨은 언제나 0이다.** `mediumSlow` 공식은 n=1 에서 −53.8 을 낸다 —
    /// 특수 처리를 안 하면 음수 경험치가 생겨 레벨 계산이 통째로 깨진다.
    func testLevelOneIsAlwaysZeroEvenWhereTheFormulaGoesNegative() {
        for rate in GrowthRate.allCases {
            XCTAssertEqual(rate.totalExp(at: 1), 0, "\(rate)")
            XCTAssertEqual(rate.totalExp(at: 0), 0, "\(rate)")
            XCTAssertEqual(rate.totalExp(at: -5), 0, "\(rate)")
        }
    }

    /// 곡선은 단조 증가한다 — 어느 구간에서든 레벨이 오르면 필요 경험치도 오른다.
    /// (`erratic`·`fluctuating` 은 구간이 나뉘어 있어 이음매에서 역전하기 쉽다.)
    func testCurvesNeverGoBackwards() {
        for rate in GrowthRate.allCases {
            for level in 2...GrowthRate.maxLevel {
                XCTAssertGreaterThan(rate.totalExp(at: level), rate.totalExp(at: level - 1),
                                     "\(rate) L\(level)")
            }
        }
    }

    /// `level(forExp:)` 은 `totalExp(at:)` 의 역이다 — 정확히 그 값에서 그 레벨이 된다.
    func testLevelIsTheInverseOfTotalExp() {
        for rate in GrowthRate.allCases {
            for level in 1...GrowthRate.maxLevel {
                let exp = rate.totalExp(at: level)
                XCTAssertEqual(rate.level(forExp: exp), level, "\(rate) L\(level)")
                if level > 1 {
                    XCTAssertEqual(rate.level(forExp: exp - 1), level - 1,
                                   "\(rate) L\(level) 직전 1EXP")
                }
            }
        }
    }

    /// 100을 넘는 경험치가 들어와도 레벨은 100에서 멈춘다.
    func testLevelStopsAtOneHundred() {
        XCTAssertEqual(GrowthRate.mediumFast.level(forExp: 999_999_999), 100)
        XCTAssertEqual(GrowthRate.mediumFast.level(forExp: 0), 1)
        XCTAssertEqual(GrowthRate.mediumFast.level(forExp: -1), 1)
    }

    /// PokéAPI 문자열 매핑. 여섯 개가 전부이고, 모르는 값은 `mediumFast` 로 떨어진다.
    func testAPINamesMapToEveryCase() {
        XCTAssertEqual(GrowthRate.fromAPI("slow-then-very-fast"), .erratic)
        XCTAssertEqual(GrowthRate.fromAPI("fast"), .fast)
        XCTAssertEqual(GrowthRate.fromAPI("medium"), .mediumFast)
        XCTAssertEqual(GrowthRate.fromAPI("medium-slow"), .mediumSlow)
        XCTAssertEqual(GrowthRate.fromAPI("slow"), .slow)
        XCTAssertEqual(GrowthRate.fromAPI("fast-then-very-slow"), .fluctuating)
        XCTAssertEqual(GrowthRate.fromAPI("나중에 생긴 무언가"), .mediumFast)
    }
}
