import SwiftUI

/// 연출의 순수 규칙 — 타이밍과 기하만. 뷰 없이 테스트한다.
///
/// 예전 연출이 "베타 같다"고 읽힌 이유는 셋이었다:
/// ① 알이 시스템 이모지(🥚)라 슬롯에서 보던 등급 알과 다른 물건이었고,
/// ② 리듬이 없어서(scale 0.94 ↔ 1.16 왕복) 터지는 순간이 없었고,
/// ③ 파티클이 4pt 로 작고 0.42초 만에 사라져 사실상 후광만 보였다.
///
/// 그래서 **예비동작 → 충격 → 잔향**이라는 구조를 넣고, 읽히는 신호를 파티클 하나에
/// 걸지 않는다(링이 작은 화면에서 훨씬 잘 읽힌다).
enum RevealMotion {
    // MARK: 타이밍

    /// 한 단계의 구간별 길이(초). 합이 `stageDuration`.
    ///
    /// 총 길이는 예전(레전더리 2.11초)과 거의 같게 유지한다 — 뽑기는 반복하는 동작이라
    /// 길어지면 그대로 벌이 된다(`testEvenTheLongestRevealIsShort` 가 2.2초로 잠가 둔다).
    /// 바뀐 것은 길이가 아니라 **구조**다: 같은 예산 안에 예비동작·충격·잔향을 넣었다.
    /// 굼뜬 연출도 미완성으로 읽히므로, 짧고 또렷한 쪽이 옳다.
    static let anticipation = 0.13   // 움츠러든다 — 곧 뭔가 온다
    static let impact = 0.09         // 터진다
    static let settle = 0.18         // 잔향

    static var stageDuration: Double { anticipation + impact + settle }

    /// 마지막 단계는 결과를 읽을 시간이 더 붙는다.
    static let finalHold = 0.55

    /// 링·파티클이 사그라드는 시간. **단계 길이와 따로 둔다** — 충격의 잔상이 다음 단계의
    /// 예비동작까지 넘어와야 연속된 폭발로 읽힌다. 구간에 딱 맞추면 매번 끊겨 깜빡임이 된다.
    static let burstDecay = 0.40

    static func duration(stageIndex: Int, of total: Int) -> Double {
        stageIndex == total - 1 ? stageDuration + finalHold : stageDuration
    }

    /// 연출 전체 길이 — 스크린샷 생성기가 몇 초를 찍을지 정할 때 쓴다.
    static func totalDuration(stages: Int) -> Double {
        (0..<stages).reduce(0) { $0 + duration(stageIndex: $1, of: stages) }
    }

    // MARK: 부화

    /// 알이 흔들리는 시간 — 짧으면 사건이 안 되고, 길면 확인 버튼을 누른 보람이 늦는다.
    static let hatchShake = 0.62
    /// 터진 뒤 포켓몬을 보는 시간.
    static let hatchHold = 2.1

    // MARK: 파티클

    /// 예전보다 늘리고 키웠다 — 16개 4pt 는 140pt 판에서 안 읽혔다.
    static let particleCount = 22
    static let particleRadius: Double = 62

    /// 파티클 하나가 날아갈 방향과 거리. 난수 대신 인덱스에서 만든다 — 매번 같은 그림이어야
    /// 스크린샷이 재현되고, 테스트가 "판 밖으로 안 나간다"를 확인할 수 있다.
    /// 각도를 황금비로 돌려 배수 개수에서도 뭉치지 않게 한다.
    static func particleOffset(index: Int, count: Int, radius: Double) -> CGSize {
        guard count > 0 else { return .zero }
        let golden = 2.399963   // 황금각(rad)
        let angle = Double(index) * golden
        // 거리를 조금씩 다르게 줘야 원이 아니라 흩어진 폭발로 보인다.
        let spread = 0.62 + 0.38 * Double((index * 7) % count) / Double(count)
        return CGSize(width: cos(angle) * radius * spread,
                      height: sin(angle) * radius * spread)
    }

    /// 파티클이 향하는 각도(도) — 원이 아니라 **바깥을 향한 짧은 획**으로 그리면 속도가 보인다.
    static func particleAngle(index: Int) -> Double {
        Double(index) * 2.399963 * 180 / .pi
    }

    /// 파티클 길이 — 인덱스로 조금씩 달리해 같은 획이 반복되지 않게.
    static func particleLength(index: Int) -> Double { 7 + Double(index % 3) * 3 }

    // MARK: 링

    /// 링은 둘을 조금 어긋나게 띄운다 — 하나면 고리가, 둘이면 충격파로 읽힌다.
    static let ringCount = 2
    static func ringDelay(_ index: Int) -> Double { Double(index) * 0.07 }
    static let ringMaxScale: Double = 2.3
}

/// 알이 지나가는 자세. `KeyframeAnimator` 가 이 값을 보간한다.
struct EggPose: Equatable, Sendable {
    var scale: Double = 1
    var rotation: Double = 0
    var lift: Double = 0

    /// 정지 자세 — 연출이 끝난 뒤 돌아오는 곳.
    static let rest = EggPose()
}
