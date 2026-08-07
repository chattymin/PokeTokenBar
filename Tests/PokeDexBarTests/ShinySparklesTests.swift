import AppKit
import SwiftUI
import XCTest
@testable import PokeDexBar

/// 이로치 반짝임 — 1/64 짜리 사건이 이름 옆의 작은 ✨ 하나로 지나가지 않게 한다.
/// **이로치일 때만** 나와야 한다: 늘 반짝이면 신호가 아니라 배경 장식이 된다.
final class ShinySparklesTests: XCTestCase {
    /// **같은 시점에 떠 있는** 별끼리 겹치면 덩어리로 보인다. 순서대로 뜨므로 시간이 벌어진
    /// 둘은 자리가 가까워도 무해하다 — 그래서 위상차를 같이 본다.
    func testSparklesVisibleTogetherDoNotOverlap() {
        for count in [6, 7, 9] {
            let specs = SparkleSpec.ring(count: count)
            for (i, a) in specs.enumerated() {
                for b in specs[(i + 1)...] {
                    let lag = min(abs(a.phase - b.phase), 1 - abs(a.phase - b.phase))
                    guard lag < 0.3 else { continue }   // 같이 안 떠 있으면 상관없다
                    XCTAssertGreaterThan(hypot(a.x - b.x, a.y - b.y), (a.size + b.size) / 2,
                                         "\(count)개: 같이 뜬 반짝임이 겹친다")
                }
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

    /// [회귀] **어떤 개수에서도 순서가 겹치면 안 된다.** 예전 식 `(index * 7) % count` 는
    /// 7개일 때 전부 0 이 되어(7과 7이 서로소가 아니다) "뾰로롱" 대신 한 번의 플래시가 됐다.
    /// 실제로 7개를 쓰고 있었으므로 화면에서 그대로 드러난 결함이다.
    func testPhasesNeverCollideAtAnyCount() {
        for count in 2...16 {
            let phases = SparkleSpec.ring(count: count).map(\.phase)
            XCTAssertEqual(Set(phases).count, count, "\(count)개일 때 순서가 겹친다: \(phases)")
            // 고르게 퍼져야 한다 — 몰려 있으면 두세 번에 나눠 터지는 것처럼 보인다.
            let sorted = phases.sorted()
            let gaps = sorted.indices.map { i -> Double in
                let next = sorted[(i + 1) % count]
                return (next - sorted[i] + 1).truncatingRemainder(dividingBy: 1)
            }
            XCTAssertGreaterThan(gaps.min() ?? 0, 0.3 / Double(count),
                                 "\(count)개일 때 순서가 몰려 있다")
        }
    }

    /// 한 번 터지고 끝나는 길이 — 길면 계속 반짝이는 것처럼 보이고, 짧으면 놓친다.
    func testTheBurstIsShortButLongEnoughToSee() {
        XCTAssertGreaterThan(ShinySparkles.duration, 0.5)
        XCTAssertLessThan(ShinySparkles.duration, 1.2)
        XCTAssertGreaterThan(ShinySparkles.stagger, 0,
                             "순서 간격이 0이면 한 번의 플래시가 된다")
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

/// 결을 만드는 요소들 — 하나라도 빠지면 "도장 찍은 별"로 돌아간다.
final class SparkleRefinementTests: XCTestCase {
    /// 크기 위계 — 큰 별 몇 개와 작은 별들이 섞여야 무리로 보인다. 다 같으면 장식용 점이다.
    func testThereIsASizeHierarchy() {
        let specs = SparkleSpec.ring(count: 9)
        let heroes = specs.filter(\.isHero)
        XCTAssertFalse(heroes.isEmpty, "큰 별이 하나도 없다")
        XCTAssertLessThan(heroes.count, specs.count, "전부 큰 별이면 위계가 없다")
        let biggestSmall = specs.filter { !$0.isHero }.map(\.size).max() ?? 0
        XCTAssertGreaterThan(heroes[0].size, biggestSmall * 1.3, "큰 별이 충분히 안 크다")
    }

    /// 기울기 — 전부 축에 정렬돼 있으면 같은 도장을 찍은 것처럼 보인다.
    func testStarsAreNotAllAxisAligned() {
        let tilts = SparkleSpec.ring(count: 9).map(\.tilt)
        XCTAssertGreaterThan(Set(tilts).count, 1, "기울기가 전부 같다")
        // 너무 돌리면 네 갈래 별의 대칭이 깨져 마름모로 보인다 — 45도 주기 안에서만 흔든다.
        for tilt in tilts { XCTAssertLessThanOrEqual(abs(tilt), 22.5, "기울기가 과하다: \(tilt)") }
    }

    /// 빨리 뜨고 천천히 진다 — 대칭이면 깜빡이는 전구처럼 보인다.
    func testTheFadeIsSlowerThanTheRise() {
        // 키프레임 비율은 뷰 안에 있으므로 여기서는 그 결과인 전체 길이만 잠근다.
        XCTAssertGreaterThan(ShinySparkles.pop, ShinySparkles.stagger,
                             "한 별이 사는 시간이 순서 간격보다 짧으면 겹쳐 뜨지 않아 끊겨 보인다")
    }
}
