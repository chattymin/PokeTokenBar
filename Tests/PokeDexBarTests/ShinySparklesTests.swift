import AppKit
import SwiftUI
import XCTest
@testable import PokeDexBar

/// 이로치 반짝임 — 1/64 짜리 사건이 이름 옆의 작은 ✨ 하나로 지나가지 않게 한다.
/// **이로치일 때만** 나와야 한다: 늘 반짝이면 신호가 아니라 배경 장식이 된다.
final class ShinySparklesTests: XCTestCase {
    /// 자리가 겹치면 별이 아니라 덩어리로 보인다.
    func testSparklesDoNotOverlap() {
        let specs = SparkleSpec.ring(count: 9)
        for (i, a) in specs.enumerated() {
            for b in specs[(i + 1)...] {
                let gap = hypot(a.x - b.x, a.y - b.y)
                XCTAssertGreaterThan(gap, (a.size + b.size) / 2,
                                     "반짝임이 겹친다: \(a) / \(b)")
            }
        }
    }

    /// 판 밖으로 나가면 잘린 별이 된다.
    func testSparklesStayInsideTheFrame() {
        for spec in SparkleSpec.ring(count: 9) {
            XCTAssertLessThanOrEqual(abs(spec.x) + spec.size / 2, 0.5, "\(spec)")
            XCTAssertLessThanOrEqual(abs(spec.y) + spec.size / 2, 0.5, "\(spec)")
        }
    }

    /// 위상이 다 같으면 별이 아니라 조명이 된다.
    func testEachSparkleBlinksOnItsOwnBeat() {
        let phases = SparkleSpec.ring(count: 9).map(\.phase)
        XCTAssertEqual(Set(phases).count, phases.count, "위상이 겹친다: \(phases)")
    }

    /// 난수를 안 쓴다 — 같은 개체는 언제 열어도 같은 그림이어야 하고, 스크린샷도 재현돼야 한다.
    func testTheLayoutIsDeterministic() {
        XCTAssertEqual(SparkleSpec.ring(count: 7), SparkleSpec.ring(count: 7))
    }

    func testGuardsAgainstNonsense() {
        XCTAssertTrue(SparkleSpec.ring(count: 0).isEmpty)
    }

    /// 별 모양이 실제로 네 갈래인지 — 옆구리를 안 당기면 그냥 마름모가 된다.
    /// 같은 거리를 **축 방향과 대각선 방향**으로 재서 비교한다: 별은 축으로 길고 대각으로 짧다.
    /// (처음엔 대각선 위의 한 점만 찍었는데, 그 점이 실제 옆구리보다 안쪽이라 잘못 실패했다.)
    func testTheShapeHasAPinchedWaist() {
        let path = SparkleShape().path(in: CGRect(x: 0, y: 0, width: 100, height: 100))
        XCTAssertFalse(path.isEmpty)
        let reach = 30.0                       // 반지름의 60%
        let diagonal = reach / 2.0.squareRoot()
        XCTAssertTrue(path.contains(CGPoint(x: 50, y: 50 - reach)), "축 방향이 짧다")
        XCTAssertFalse(path.contains(CGPoint(x: 50 - diagonal, y: 50 - diagonal)),
                       "대각선이 축만큼 길다 — 옆구리가 안 당겨져 마름모다")
    }
}

/// [도달성] 반짝임이 **실제 화면에** 닿는지. 부품만 테스트하면 상세 화면이나 부화 연출에서
/// 빠져도 통과한다 — 이 저장소가 반복해서 밟은 형태다.
@MainActor
final class ShinySparklesReachabilityTests: XCTestCase {
    private func make(shiny: Bool) -> (PlayerStore, Individual) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("shiny-\(UUID().uuidString).json")
        let store = PlayerStore(fileURL: url, rng: SeededRNG(seed: 1),
                                now: { Date(timeIntervalSince1970: 0) })
        var individual = Individual(baseID: 25, speciesID: 25, pathIDs: [25], nature: .jolly,
                                    obtainedAt: Date(timeIntervalSince1970: 0), grade: .legendary)
        individual.shiny = shiny
        store.addForTesting(individual)
        return (store, store.state.box[0])
    }

    /// 뷰를 실제로 그려 보고, 그 안에서 `ShinySparkles` 가 만들어졌는지 본다.
    private func sparkleCount<V: View>(_ view: V, height: CGFloat) -> Int {
        ShinySparkles.resetConstructed()
        let host = NSHostingView(rootView: view.frame(width: PopoverMetrics.width))
        host.frame = CGRect(x: 0, y: 0, width: PopoverMetrics.width, height: height)
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.9))
        return ShinySparkles.constructed.count
    }

    /// 상세 화면 — 이로치만 반짝인다. 일반 개체까지 반짝이면 신호가 아니라 장식이 된다.
    func testTheDetailScreenSparklesOnlyForShiny() {
        let (shinyStore, shiny) = make(shiny: true)
        let (plainStore, plain) = make(shiny: false)
        func detail(_ s: PlayerStore, _ i: Individual) -> some View {
            IndividualDetailView(store: s, individual: i, line: nil,
                                 onNeedLine: { _ in }, onBack: {})
        }
        XCTAssertGreaterThan(sparkleCount(detail(shinyStore, shiny), height: 300), 0,
                             "이로치 상세에 반짝임이 안 붙었다")
        XCTAssertEqual(sparkleCount(detail(plainStore, plain), height: 300), 0,
                       "일반 개체가 반짝인다")
    }

    /// 부화 연출 — 처음 알게 되는 자리라 여기가 가장 중요하다.
    func testTheHatchRevealSparklesOnlyForShiny() {
        let (shinyStore, shiny) = make(shiny: true)
        let (plainStore, plain) = make(shiny: false)
        func hatch(_ s: PlayerStore, _ i: Individual) -> some View {
            HatchedRevealView(individual: i, store: s, line: nil, onDone: {})
        }
        // 알이 터진 뒤에 나오므로 연출이 지나갈 만큼 기다린다.
        XCTAssertGreaterThan(sparkleCount(hatch(shinyStore, shiny), height: 250), 0,
                             "이로치 부화에 반짝임이 안 붙었다")
        XCTAssertEqual(sparkleCount(hatch(plainStore, plain), height: 250), 0,
                       "일반 개체 부화가 반짝인다")
    }
}
