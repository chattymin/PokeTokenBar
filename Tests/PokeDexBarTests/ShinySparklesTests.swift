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

    // MARK: - 특이행렬 abort (사용자 제보 2건, macOS 15.6)

    /// **AppKit 이 실제로 무엇에 죽는지를 AppKit 에 물어본다.**
    ///
    /// 여기서 내 짐작으로 "0 이면 죽겠지" 하고 픽스처를 쓰면, 픽스처와 코드가 같은 오해를
    /// 공유해 둘 다 통과하면서 실기기에서는 계속 죽는다(이 레포의 #133 부류). 그래서 문제의
    /// 그 메서드를 런타임으로 직접 부른다 — `-[NSView setFrameTransform:]` 는 Swift 에
    /// 노출돼 있지 않고 `CGAffineTransform` **구조체**를 받으므로 IMP 를 타입 지어 부른다
    /// (`perform(_:with:)` 로 부르면 포인터가 구조체로 해석돼 엉뚱하게 죽는다 — 실제로 겪었다).
    ///
    /// 이 테스트는 **살아남는 값만** 넣는다. 배율 0 을 넣으면 실제로 abort 하는데, 그러면
    /// 스위트 전체가 리포트 없이 죽는다. "0 이 죽는다" 는 사실은 `xform2` 프로브로 따로
    /// 실측했고(0·NaN → SIGABRT, identity·1e-8 → 통과), 여기서는 **우리가 넣는 값이
    /// 그 문턱 위에 있는지**를 지킨다.
    @MainActor
    func testAppKitAcceptsTheScaleWeActuallyApply() throws {
        let sel = NSSelectorFromString("setFrameTransform:")
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
        XCTAssertTrue(view.responds(to: sel), "setFrameTransform: 이 사라졌다 — 이 방어의 전제가 바뀐 것")
        typealias Fn = @convention(c) (NSView, Selector, CGAffineTransform) -> Void
        let apply = unsafeBitCast(class_getMethodImplementation(NSView.self, sel)!, to: Fn.self)

        // 연출이 실제로 지나가는 배율 — 하한, 최대 오버슈트, 그리고 그 사이.
        for raw in [SparklePose.minScale, 0.5, 1.0, 1.18] {
            let s = SparklePose.safeScale(raw)
            apply(view, sel, CGAffineTransform(scaleX: s, y: s))
        }
        // 여기 도달했으면 전부 통과한 것이다.
    }

    /// 변환에 들어가는 배율은 **어떤 입력에도** 0 이 아니고 유한해야 한다.
    ///
    /// 0 만 막으면 부족하다 — 스프링은 목표 아래로 내려갔다 오고, 길이 0 짜리 키프레임은
    /// 0/0 으로 NaN 을 낼 수 있다. 둘 다 같은 abort 로 간다.
    func testTheAppliedScaleIsNeverSingularOrNaN() {
        let hostile = [0.0, -0.0, -1e-30, -5.0, .nan, .infinity, -.infinity,
                       Double.leastNonzeroMagnitude]
        for raw in hostile {
            let s = SparklePose.safeScale(raw)
            XCTAssertTrue(s.isFinite, "배율이 유한하지 않다: \(raw) -> \(s)")
            XCTAssertGreaterThanOrEqual(s, SparklePose.minScale, "배율이 하한 아래다: \(raw) -> \(s)")
        }
        // 정상값은 손대지 않는다 — 하한이 연출을 눌러 버리면 안 된다.
        XCTAssertEqual(SparklePose.safeScale(1.18), 1.18, accuracy: 1e-12)
    }

    /// 쉬고 있는 자세도 화면에 올라간다(연출 전·후). 여기가 0 이면 여는 즉시 죽는다.
    func testTheRestPoseIsNotSingular() {
        XCTAssertGreaterThan(SparklePose().scale, 0, "쉬는 자세의 배율이 0 이다")
    }

    /// **결함을 만든 조건 그 자체.** 첫 별은 `phase` 가 0 이라 대기 시간이 0 이 되고,
    /// 그러면 길이 0 짜리 키프레임이 만들어진다. 조건이 살아 있음을 먼저 확인하고,
    /// 뷰가 그 값을 바닥으로 끌어올리는지를 소스에서 확인한다 —
    /// `KeyframeTrack` 의 내부 보간값은 밖에서 읽을 방법이 없다.
    func testTheFirstSparkleWouldOtherwiseGetAZeroLengthKeyframe() throws {
        let first = try XCTUnwrap(SparkleSpec.ring(count: 7).first)
        XCTAssertEqual(first.phase, 0, accuracy: 1e-12,
                       "첫 별의 위상이 더는 0 이 아니다 — 이 방어의 전제가 바뀐 것")

        let text = try String(contentsOf: Self.uiSource("ShinySparkles.swift"), encoding: .utf8)
        XCTAssertTrue(text.contains("let wait = max("),
                      "대기 시간에 하한이 없다 — 첫 별이 길이 0 키프레임을 만든다")
        XCTAssertFalse(text.contains(".scaleEffect(pose.scale)"),
                       "보간값을 그대로 변환에 넣고 있다 — safeScale 을 지나야 한다")
    }

    /// [부류 스윕] **어떤 화면에서도 배율 0 을 변환에 넣지 않는다.**
    ///
    /// 이 결함은 반짝임 하나의 실수가 아니라 "0 배율은 그리기가 아니라 abort" 라는 사실을
    /// 몰랐던 것이다. 다른 화면이 같은 값을 쓰면 같은 방식으로 죽는다.
    func testNoViewScalesToExactlyZero() throws {
        let dir = Self.uiSource(".").deletingLastPathComponent()
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        var offenders: [String] = []
        for file in files where file.pathExtension == "swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            for (n, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
            where line.contains(".scaleEffect(") {
                // 배율 자리에 0 리터럴이 오는 형태만 잡는다.
                for bad in [".scaleEffect(0)", ".scaleEffect(0.0)", ".scaleEffect(0,",
                            "scale: 0)", "scale: 0,"] where line.contains(bad) {
                    offenders.append("\(file.lastPathComponent):\(n + 1) \(line.trimmingCharacters(in: .whitespaces))")
                }
            }
        }
        XCTAssertTrue(offenders.isEmpty,
                      "배율 0 은 역행렬이 없어 NSView 로 내려가면 abort 한다:\n" + offenders.joined(separator: "\n"))
    }

    private static func uiSource(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/PokeDexBar/UI/").appendingPathComponent(name)
    }
}
