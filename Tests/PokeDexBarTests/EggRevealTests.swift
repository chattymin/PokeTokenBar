import SwiftUI
import XCTest
@testable import PokeDexBar

/// 뽑기 연출 규칙 — "한 번 더 터졌다"가 곧 "더 좋은 게 나왔다"라서, 단계 수가 곧 정보다.
final class EggRevealTests: XCTestCase {
    func testCommonStopsAtWhite() {
        XCTAssertEqual(EggReveal.stages(for: .common), [.white])
    }

    func testEachGradeAddsExactlyOneStage() {
        XCTAssertEqual(EggReveal.stages(for: .rare), [.white, .blue])
        XCTAssertEqual(EggReveal.stages(for: .epic), [.white, .blue, .purple])
        XCTAssertEqual(EggReveal.stages(for: .legendary), [.white, .blue, .purple, .orange])
    }

    /// 앞 단계는 사라지지 않고 그대로 유지된다 — 높은 등급이 낮은 등급의 연출을 건너뛰면
    /// "올라갔다"가 아니라 "다른 연출"로 보인다.
    func testHigherGradesContainTheLowerSequence() {
        let ordered: [Grade] = [.common, .rare, .epic, .legendary]
        for (a, b) in zip(ordered, ordered.dropFirst()) {
            let lower = EggReveal.stages(for: a), higher = EggReveal.stages(for: b)
            XCTAssertEqual(Array(higher.prefix(lower.count)), lower,
                           "\(b) 가 \(a) 의 단계를 그대로 안 지난다")
            XCTAssertEqual(higher.count, lower.count + 1)
        }
    }

    /// 모든 등급이 서로 다른 길이여야 한다 — 같으면 등급을 눈으로 구분할 수 없다.
    func testEveryGradeHasADistinctLength() {
        let lengths = Grade.allCases.map { EggReveal.stages(for: $0).count }
        XCTAssertEqual(Set(lengths).count, Grade.allCases.count)
    }

    /// 반짝임은 마지막 색에만 — 계속 반짝이면 단계가 올라간 순간을 못 알아챈다.
    func testOnlyTheLastStageSparkles() {
        XCTAssertTrue(RevealStage.orange.sparkles)
        for stage in RevealStage.allCases where stage != .orange {
            XCTAssertFalse(stage.sparkles, "\(stage) 가 반짝인다")
        }
    }

    /// 단계마다 색이 달라야 한다 — 같은 색이 두 번 터지면 올라간 게 아니라 반복으로 보인다.
    func testStageColorsAreDistinct() {
        let colors = RevealStage.allCases.map { NSColor($0.color).usingColorSpace(.sRGB)! }
        for (i, a) in colors.enumerated() {
            for b in colors[(i + 1)...] {
                XCTAssertGreaterThan(
                    abs(a.redComponent - b.redComponent) + abs(a.greenComponent - b.greenComponent)
                        + abs(a.blueComponent - b.blueComponent),
                    0.2, "두 단계 색이 사실상 같다")
            }
        }
    }

    func testLastStageLingersLongest() {
        XCTAssertGreaterThan(EggReveal.duration(stageIndex: 3, of: 4),
                             EggReveal.duration(stageIndex: 0, of: 4))
        // 커먼처럼 단계가 하나뿐이어도 그 하나가 "마지막"이라 읽을 시간을 준다.
        XCTAssertEqual(EggReveal.duration(stageIndex: 0, of: 1),
                       EggReveal.duration(stageIndex: 3, of: 4), accuracy: 1e-9)
    }

    /// 연출 전체 길이 — 레전더리도 2.2초 안에 끝나야 한다. 길면 뽑을 때마다 기다리는 벌이 된다.
    func testEvenTheLongestRevealIsShort() {
        for grade in Grade.allCases {
            let stages = EggReveal.stages(for: grade)
            let total = stages.indices
                .map { EggReveal.duration(stageIndex: $0, of: stages.count) }
                .reduce(0, +)
            XCTAssertLessThan(total, 2.2, "\(grade) 연출이 너무 길다: \(total)초")
        }
    }

    // MARK: 파티클

    /// 파티클은 난수가 아니라 인덱스에서 나온다 — 매번 같아야 스크린샷이 재현된다.
    func testParticleOffsetsAreDeterministic() {
        let a = EggReveal.particleOffset(index: 3, count: 16, radius: 46)
        let b = EggReveal.particleOffset(index: 3, count: 16, radius: 46)
        XCTAssertEqual(a.width, b.width, accuracy: 1e-9)
        XCTAssertEqual(a.height, b.height, accuracy: 1e-9)
    }

    /// 어떤 파티클도 반경 밖으로 나가지 않는다 — 나가면 팝오버 밖으로 새서 잘린다.
    func testParticlesStayInsideTheRadius() {
        let radius = EggReveal.particleRadius
        for index in 0..<EggReveal.particleCount {
            let o = EggReveal.particleOffset(index: index, count: EggReveal.particleCount,
                                             radius: radius)
            XCTAssertLessThanOrEqual((o.width * o.width + o.height * o.height).squareRoot(),
                                     radius + 0.001, "파티클 \(index) 가 반경을 넘었다")
        }
    }

    /// 서로 다른 방향으로 흩어져야 한다 — 겹치면 폭발이 아니라 점 하나로 보인다.
    func testParticlesDoNotOverlap() {
        let points = (0..<EggReveal.particleCount).map {
            EggReveal.particleOffset(index: $0, count: EggReveal.particleCount,
                                     radius: EggReveal.particleRadius)
        }
        for (i, a) in points.enumerated() {
            for b in points[(i + 1)...] {
                let d = ((a.width - b.width) * (a.width - b.width)
                         + (a.height - b.height) * (a.height - b.height)).squareRoot()
                XCTAssertGreaterThan(d, 4, "파티클 둘이 겹친다")
            }
        }
    }

    func testZeroCountDoesNotDivideByZero() {
        XCTAssertEqual(EggReveal.particleOffset(index: 0, count: 0, radius: 46), .zero)
    }
}
