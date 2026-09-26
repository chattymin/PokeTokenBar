import XCTest
@testable import PokeTokenBar

/// 페이스 대비 6단계 판정 — 경계값 양쪽, crit 우선, 페이스 없음/창 초반 보류.
/// pace 0.5 를 기준으로 삼는다: 0.5 × 100 = 50 이 정확히 표현돼 delta 가 부동소수 오차 없이 떨어진다.
final class PaceTierTests: XCTestCase {
    private let crit = 95.0

    private func tier(_ utilization: Double, pace: Double? = 0.5) -> PaceTier? {
        PaceTier.tier(utilization: utilization, pace: pace, critThreshold: crit)
    }

    func testBoundariesOnBothSides() {
        let cases: [(Double, PaceTier)] = [
            (0, .wayUnder),
            (24, .wayUnder),     // delta −26
            (25, .under),        // −25
            (39, .under),        // −11
            (40, .onPace),       // −10
            (54, .onPace),       // +4
            (55, .slightlyOver), // +5
            (64, .slightlyOver), // +14
            (65, .over),         // +15
            (79, .over),         // +29
            (80, .wayOver),      // +30
        ]
        for (utilization, expected) in cases {
            XCTAssertEqual(tier(utilization), expected, "utilization=\(utilization)")
        }
    }

    /// 판정은 반올림한 delta 로 한다 — 툴팁에 찍히는 정수와 단계가 경계에서 어긋나지 않게.
    func testTierFollowsRoundedDelta() {
        XCTAssertEqual(tier(54.6), .slightlyOver)  // +4.6 → "5 pts over" 이므로 조금 빠름
        XCTAssertEqual(tier(54.4), .onPace)
        XCTAssertEqual(PaceTier.roundedDelta(utilization: 54.6, pace: 0.5), 5)
        XCTAssertEqual(PaceTier.roundedDelta(utilization: 38.5, pace: 0.5), -12)
    }

    /// delta 가 작아도(여기선 여유 쪽) crit 이상이면 최상위 단계.
    func testCritOverridesPace() {
        XCTAssertEqual(tier(95, pace: 0.99), .wayOver)
        XCTAssertEqual(tier(94, pace: 0.99), .onPace)
    }

    func testNoPaceMeansNoTier() {
        XCTAssertNil(tier(50, pace: nil))
    }

    /// 창 초반엔 한 번의 요청으로도 delta 가 크게 흔들리므로 보류 — 호출부가 절대 임계색으로 돌아간다.
    func testHeldEarlyInWindow() {
        XCTAssertNil(tier(10, pace: 0.02))
        XCTAssertNil(tier(99, pace: PaceTier.minimumPace - 0.001))  // crit 도 보류 — limitColor 가 빨강을 준다
        XCTAssertEqual(tier(10, pace: PaceTier.minimumPace), .onPace)
    }

    /// 차이 문구는 부호 대신 "더/덜"로 방향을 말한다 — 음수 기호가 새어 나오면 "−12 pts under" 같은 이중 부정.
    /// 0 이면 단계 이름("페이스대로")만으로 충분해 문구를 내지 않는다.
    func testDeltaTextCarriesNoSignAndSkipsZero() {
        for lang in AppLanguage.allCases {
            let l = L(lang)
            XCTAssertNil(l.paceDelta(0), "\(lang)")
            XCTAssertNotEqual(l.paceDelta(12), l.paceDelta(-12), "\(lang)")
            XCTAssertFalse(l.paceDelta(-12)?.contains("-12") ?? true, "\(lang)")
        }
    }

    /// 여섯 단계 이름이 언어마다 모두 달라야 색 없이 글만으로도 단계가 구분된다.
    func testTierLabelsDistinctInEveryLanguage() {
        for lang in AppLanguage.allCases {
            let labels = PaceTier.allCases.map { L(lang).paceTier($0) }
            XCTAssertEqual(Set(labels).count, PaceTier.allCases.count, "\(lang): \(labels)")
        }
    }
}

/// The gauge color shared by the popover row and the menu bar.
final class PaceTierGaugeTests: XCTestCase {
    private func gauge(_ utilization: Double, pace: Double?) -> PaceTier {
        PaceTier.gauge(utilization: utilization, pace: pace, warnThreshold: 80, critThreshold: 95)
    }

    func testAKnownPaceUsesTheSixTiers() {
        XCTAssertEqual(gauge(20, pace: 0.5), .wayUnder)
        XCTAssertEqual(gauge(70, pace: 0.5), .over)
    }

    /// No pace, or the early-window hold: both sides of warn and crit.
    func testWithoutAPaceTheThresholdsPickTheColor() {
        for pace in [nil, 0.05] as [Double?] {
            XCTAssertEqual(gauge(79, pace: pace), .onPace, "pace=\(String(describing: pace))")
            XCTAssertEqual(gauge(80, pace: pace), .over)
            XCTAssertEqual(gauge(94, pace: pace), .over)
            XCTAssertEqual(gauge(95, pace: pace), .wayOver)
        }
    }

    /// The fallback lands on the colors `limitColor` draws, so rows without a pace look as before.
    func testTheFallbackTiersMatchTheThresholdColors() {
        XCTAssertEqual(PaceTier.onPace.color, .green)
        XCTAssertEqual(PaceTier.over.color, .orange)
        XCTAssertEqual(PaceTier.wayOver.color, .red)
    }

    func testCalmMeansOnPaceOrSlower() {
        XCTAssertEqual(PaceTier.allCases.filter(\.isCalm), [.wayUnder, .under, .onPace])
    }
}
