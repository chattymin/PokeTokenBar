import AppKit
import SwiftUI
import XCTest
@testable import PokeDexBar

/// 연출의 순수 규칙. 예전 연출이 "베타 같다"고 읽힌 이유는 리듬이 없어서였다 — 알이 커졌다
/// 작아지기만 하고 터지는 순간이 없었다. 그 구조(예비동작 → 충격 → 잔향)를 여기서 잠근다.
final class RevealMotionTests: XCTestCase {
    /// 세 구간이 곧 한 단계다 — 하나만 늘리고 합을 안 고치면 마지막에 멈춰 선 알을 보게 된다.
    func testAStageIsItsThreeBeats() {
        XCTAssertEqual(RevealMotion.stageDuration,
                       RevealMotion.anticipation + RevealMotion.impact + RevealMotion.settle,
                       accuracy: 0.0001)
        // 예비동작이 충격보다 길어야 "움츠렸다가 터졌다"로 읽힌다.
        XCTAssertGreaterThan(RevealMotion.anticipation, RevealMotion.impact)
        // 잔향이 가장 길다 — 여운 없이 다음 단계로 넘어가면 깜빡임이 된다.
        XCTAssertGreaterThan(RevealMotion.settle, RevealMotion.impact)
    }

    /// 마지막 단계만 길다 — 결과를 읽을 시간이 필요하다.
    func testTheFinalStageHoldsLonger() {
        XCTAssertEqual(RevealMotion.duration(stageIndex: 0, of: 4), RevealMotion.stageDuration)
        XCTAssertEqual(RevealMotion.duration(stageIndex: 3, of: 4),
                       RevealMotion.stageDuration + RevealMotion.finalHold)
    }

    /// 등급이 높을수록 길어진다 — 뽑기의 무게가 시간으로도 느껴져야 한다.
    func testHigherGradesTakeLonger() {
        let lengths = Grade.allCases.map {
            RevealMotion.totalDuration(stages: EggReveal.stages(for: $0).count)
        }
        for (short, long) in zip(lengths, lengths.dropFirst()) {
            XCTAssertLessThan(short, long)
        }
        // 커먼은 자주 보는 화면이라 짧아야 한다.
        XCTAssertLessThan(RevealMotion.totalDuration(stages: 1), 1.6)
    }

    /// 파티클이 판 밖으로 나가면 잘려서 획이 반쯤 사라진다.
    func testParticlesStayInsideTheStage() {
        for index in 0..<RevealMotion.particleCount {
            let offset = RevealMotion.particleOffset(index: index,
                                                     count: RevealMotion.particleCount,
                                                     radius: RevealMotion.particleRadius)
            XCTAssertLessThanOrEqual(hypot(offset.width, offset.height),
                                     RevealMotion.particleRadius + 0.001, "\(index)")
        }
    }

    /// 방향이 겹치면 폭발이 아니라 몇 개의 선으로 보인다. 재는 것은 **가장 가까운 두 획의
    /// 사이각** — 칸으로 세면 경계에 걸친 둘이 우연히 붙어도 실패하고, 정작 실제로 겹치는 건
    /// 못 잡는다(황금각 22개의 실측 최소 간격은 7.7도다).
    func testNoTwoParticlesPointTheSameWay() {
        let angles = (0..<RevealMotion.particleCount)
            .map { RevealMotion.particleAngle(index: $0).truncatingRemainder(dividingBy: 360) }
            .sorted()
        let gaps = angles.indices.map { index -> Double in
            let next = angles[(index + 1) % angles.count]
            return (next - angles[index] + 360).truncatingRemainder(dividingBy: 360)
        }
        XCTAssertGreaterThan(gaps.min() ?? 0, 5, "두 획이 사실상 겹친다: \(gaps.min() ?? 0)도")
    }

    func testGuardsAgainstNonsense() {
        XCTAssertEqual(RevealMotion.particleOffset(index: 0, count: 0, radius: 40), .zero)
    }
}

/// 연출 중 알이 등급을 거슬러 올라간다 — 커먼 알에서 시작해 진짜 등급에 닿는다.
final class RevealStageEggTests: XCTestCase {
    /// **연출이 끝난 알이 진짜 등급이어야 한다.** 이게 어긋나면 레전더리를 뽑았는데 마지막에
    /// 에픽 알이 서 있게 된다 — 조용히 거짓말하는 화면이다.
    func testTheLastStageShowsTheRealGrade() {
        for grade in Grade.allCases {
            let last = EggReveal.stages(for: grade).last
            XCTAssertEqual(last?.grade, grade, "\(grade) 연출이 다른 등급 알로 끝난다")
        }
    }

    /// 단계가 오를수록 알 등급도 오른다 — 중간에 내려가면 에스컬레이션이 깨진다.
    func testStagesEscalateThroughTheGrades() {
        let grades = RevealStage.allCases.map(\.grade)
        XCTAssertEqual(grades, [.common, .rare, .epic, .legendary])
    }

    /// 마지막 단계만 반짝인다 — 계속 반짝이면 단계가 올라간 걸 못 알아챈다.
    func testOnlyTheFinalStageSparkles() {
        XCTAssertEqual(RevealStage.allCases.filter(\.sparkles), [.orange])
    }
}

/// 부화 연출 — 알에서 시작해야 부화라는 사건이 생긴다.
@MainActor
final class HatchRevealTests: XCTestCase {
    /// 흔들림 구간과 키프레임 길이가 어긋나면 마지막에 멈춰 선 알을 보고 있게 된다.
    func testTheShakeIsLongEnoughToRead() {
        XCTAssertGreaterThan(RevealMotion.hatchShake, 0.4)
        XCTAssertLessThan(RevealMotion.hatchShake, 1.0, "확인을 누른 보람이 너무 늦다")
    }

    /// 터진 뒤 포켓몬을 보는 시간이 흔들림보다 길어야 한다 — 주인공은 알이 아니다.
    func testTheHatchlingIsOnScreenLongerThanTheEgg() {
        XCTAssertGreaterThan(RevealMotion.hatchHold, RevealMotion.hatchShake)
    }

    /// 실제로 그려지는지 — 뷰가 비면 확인 버튼을 눌러도 아무 일이 없는 것처럼 보인다.
    func testTheRevealRenders() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("hatch-\(UUID().uuidString).json")
        let store = PlayerStore(fileURL: url, rng: SeededRNG(seed: 1),
                                now: { Date(timeIntervalSince1970: 0) })
        let individual = Individual(baseID: 25, speciesID: 25, pathIDs: [25], nature: .jolly,
                                    obtainedAt: Date(timeIntervalSince1970: 0), grade: .legendary)
        store.addForTesting(individual)
        let host = NSHostingView(rootView: HatchedRevealView(
            individual: individual, store: store, line: nil, onDone: {})
            .frame(width: PopoverMetrics.width, height: 240))
        host.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(host.fittingSize.height, 0)
    }
}

/// 알 그림 — 등급마다 파일이 하나씩 있어야 한다. 하나라도 없으면 그 등급 알이 **아무것도 안
/// 그려진 채** 슬롯에 앉는다(`EggIcon` 은 그림이 없으면 조용히 비운다).
@MainActor
final class EggArtTests: XCTestCase {
    func testEveryGradeHasArt() {
        for grade in Grade.allCases {
            XCTAssertNotNil(EggIcon.resourceURL(for: grade), "\(grade) 알 그림 경로가 없다")
            XCTAssertNotNil(EggIcon.image(for: grade), "\(grade) 알 그림을 못 읽는다")
        }
    }

    /// 등급마다 다른 그림이어야 한다 — 같은 파일을 가리키면 슬롯에서 등급을 구분할 수 없다.
    func testGradesUseDistinctArt() {
        let names = Grade.allCases.compactMap { EggIcon.resourceURL(for: $0)?.lastPathComponent }
        XCTAssertEqual(Set(names).count, Grade.allCases.count, names.description)
    }

    /// **배경이 투명해야 한다.** 원본은 흰 배경 위에 그려져 있어, 그대로 실으면 어두운 팝오버에
    /// 흰 사각형이 뜬다. 네 귀퉁이가 모두 비어 있는지로 확인한다.
    func testTheBackgroundWasRemoved() throws {
        for grade in Grade.allCases {
            let url = try XCTUnwrap(EggIcon.resourceURL(for: grade))
            let rep = try XCTUnwrap(NSBitmapImageRep(data: try Data(contentsOf: url)))
            XCTAssertTrue(rep.hasAlpha, "\(grade) 그림에 알파 채널이 없다")
            let corners = [(0, 0), (rep.pixelsWide - 1, 0),
                           (0, rep.pixelsHigh - 1), (rep.pixelsWide - 1, rep.pixelsHigh - 1)]
            for (x, y) in corners {
                let alpha = try XCTUnwrap(rep.colorAt(x: x, y: y)).alphaComponent
                XCTAssertEqual(alpha, 0, accuracy: 0.02,
                               "\(grade) 그림의 모서리(\(x),\(y))가 불투명하다 — 흰 배경이 남았다")
            }
        }
    }

    /// 안쪽 하이라이트까지 뚫리면 안 된다 — 커먼 알은 위쪽이 순백이라 흰색을 통째로 지우면
    /// 구멍이 난다(테두리에서 번지는 flood fill 을 쓴 이유다).
    func testTheInteriorSurvived() throws {
        let url = try XCTUnwrap(EggIcon.resourceURL(for: .common))
        let rep = try XCTUnwrap(NSBitmapImageRep(data: try Data(contentsOf: url)))
        // 알 위쪽 하이라이트 자리 — 가로 중앙, 세로 20% 지점.
        let alpha = try XCTUnwrap(rep.colorAt(x: rep.pixelsWide / 2,
                                              y: rep.pixelsHigh / 5)).alphaComponent
        XCTAssertEqual(alpha, 1, accuracy: 0.02, "커먼 알 안쪽 흰 하이라이트가 뚫렸다")
    }
}
