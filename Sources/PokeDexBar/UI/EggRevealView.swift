import SwiftUI

/// 뽑기 연출의 한 단계. 커먼은 흰색 하나로 끝나고, 등급이 높을수록 그 위에 단계가 더 얹힌다 —
/// "한 번 더 터졌다"가 곧 "더 좋은 게 나왔다"라서, 사용자는 결과 글자를 읽기 전에 이미 안다.
enum RevealStage: Int, CaseIterable, Sendable {
    case white, blue, purple, orange

    var color: Color {
        switch self {
        case .white: Color(red: 1.00, green: 1.00, blue: 1.00)
        case .blue: Color(red: 0.50, green: 0.83, blue: 1.00)
        case .purple: Color(red: 0.69, green: 0.42, blue: 1.00)
        case .orange: Color(red: 1.00, green: 0.61, blue: 0.24)
        }
    }

    /// 마지막 단계만 반짝인다 — 계속 반짝이면 단계가 올라간 걸 못 알아챈다.
    var sparkles: Bool { self == .orange }

    /// 이 단계에서 보여줄 알. 연출 중 알이 **등급을 거슬러 올라간다** — 커먼 알에서 시작해
    /// 레어·에픽을 지나 진짜 등급에 닿는다. 등급 알 그림(`EggIcon`)을 그대로 쓰므로 새 그림이
    /// 필요 없고, 슬롯에서 보던 껍질과 무늬가 그대로 커지며 바뀐다.
    ///
    /// 처음엔 알을 진짜 등급색으로 고정했는데, 레전더리의 금색 껍질이 화면 가운데를 차지해
    /// 단계 색을 덮어 버렸다(스크린샷 생성기의 에스컬레이션 검사가 이걸 잡았다). 알이 같이
    /// 올라가면 그 문제가 사라지고, "한 단계 더 갔다"가 알 자체로 보인다.
    var grade: Grade {
        switch self {
        case .white: .common
        case .blue: .rare
        case .purple: .epic
        case .orange: .legendary
        }
    }
}

/// 뽑기 연출의 단계 표. 타이밍·기하는 `RevealMotion` 에 있다.
enum EggReveal {
    /// 이 등급이 지나갈 단계들. 등급이 높을수록 길어지고, 앞 단계는 그대로 유지된다 —
    /// 레전더리는 흰색 → 하늘색 → 보라색 → 주황색을 다 지난다.
    static func stages(for grade: Grade) -> [RevealStage] {
        let depth = switch grade {
        case .common: 1
        case .rare: 2
        case .epic: 3
        case .legendary: 4
        }
        return Array(RevealStage.allCases.prefix(depth))
    }

    /// 한 단계가 화면에 머무는 시간(초).
    static func duration(stageIndex: Int, of total: Int) -> Double {
        RevealMotion.duration(stageIndex: stageIndex, of: total)
    }

    /// 파티클 하나가 날아갈 방향과 거리.
    static func particleOffset(index: Int, count: Int, radius: Double) -> CGSize {
        RevealMotion.particleOffset(index: index, count: count, radius: radius)
    }

    static let particleCount = RevealMotion.particleCount
    static let particleRadius: Double = RevealMotion.particleRadius
}

/// 뽑기 결과 연출 — 등급이 올라갈 때마다 한 번씩 더 터지고, 마지막에 등급을 알려준다.
/// 팝오버 위에 잠깐 덮였다 사라지는 표면이라 타이머를 남기지 않는다(`.task` 가 끝나면 끝).
///
/// 구조는 **예비동작 → 충격 → 잔향**이다(`RevealMotion`). 예전에는 알이 커졌다 작아지기만 해서
/// 터지는 순간이 없었고, 그래서 "한 번 더 터졌다 = 더 좋은 것"이라는 신호가 전달되지 않았다.
struct EggRevealView: View {
    let grade: Grade
    let shiny: Bool
    let l: L
    let language: AppLanguage
    let onDone: () -> Void

    @State private var stageIndex = 0
    /// 이 값이 바뀔 때마다 한 번 터진다 — `KeyframeAnimator` 와 링·파티클의 방아쇠.
    @State private var beat = 0
    @State private var burst = false
    @State private var showResult = false
    /// 이로치 반짝임의 방아쇠 — 마지막 단계에서 한 번만 올린다.
    @State private var sparkleBeat = 0

    private var stages: [RevealStage] { EggReveal.stages(for: grade) }
    private var stage: RevealStage { stages[min(stageIndex, stages.count - 1)] }

    var body: some View {
        ZStack {
            // 가운데로 시선을 모으는 어둠 — 평평한 검정보다 무대처럼 읽힌다.
            RadialGradient(colors: [stage.color.opacity(0.16), .black.opacity(0.93)],
                           center: .center, startRadius: 0, endRadius: 190)
                .ignoresSafeArea()
            VStack(spacing: 16) {
                ZStack {
                    rings
                    particles
                    egg
                    // 이로치는 결과를 말할 때 한 번 더 반짝인다 — 글자보다 이게 먼저 읽힌다.
                    if shiny {
                        ShinySparkles(specs: SparkleSpec.ring(count: 9, radius: 0.46),
                                      trigger: sparkleBeat)
                    }
                }
                .frame(width: 150, height: 150)
                result
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onDone() }   // 기다리기 싫으면 눌러서 건너뛴다
        .task { await run() }
    }

    /// 알 — **슬롯에서 보던 그 알**이 그대로 커진다. 예전에는 시스템 이모지라 등급 껍질도
    /// 무늬도 없어서, 뽑기 화면과 부화 슬롯이 서로 다른 물건을 보여 주고 있었다.
    private var egg: some View {
        KeyframeAnimator(initialValue: EggPose.rest, trigger: beat) { pose in
            EggIcon(grade: stage.grade, size: 78)
                .scaleEffect(pose.scale)
                .rotationEffect(.degrees(pose.rotation))
                .offset(y: pose.lift)
                .shadow(color: stage.color.opacity(0.85), radius: burst ? 22 : 8)
        } keyframes: { _ in
            // 움츠렸다가(예비동작) 튀어오르고(충격) 두어 번 흔들리며 가라앉는다.
            KeyframeTrack(\.scale) {
                CubicKeyframe(0.88, duration: RevealMotion.anticipation)
                SpringKeyframe(1.24, duration: RevealMotion.impact, spring: .bouncy)
                SpringKeyframe(1.0, duration: RevealMotion.settle, spring: .snappy)
            }
            KeyframeTrack(\.rotation) {
                CubicKeyframe(-7, duration: RevealMotion.anticipation)
                CubicKeyframe(6, duration: RevealMotion.impact)
                CubicKeyframe(-3, duration: RevealMotion.settle * 0.5)
                CubicKeyframe(0, duration: RevealMotion.settle * 0.5)
            }
            KeyframeTrack(\.lift) {
                CubicKeyframe(4, duration: RevealMotion.anticipation)
                SpringKeyframe(-14, duration: RevealMotion.impact, spring: .bouncy)
                SpringKeyframe(0, duration: RevealMotion.settle, spring: .snappy)
            }
        }
    }

    /// 충격파 링 — 작은 판에서는 파티클보다 이쪽이 훨씬 잘 읽힌다. 둘을 어긋나게 띄운다.
    private var rings: some View {
        ForEach(0..<RevealMotion.ringCount, id: \.self) { index in
            Circle()
                .strokeBorder(stage.color, lineWidth: burst ? 1 : 3)
                .frame(width: 74, height: 74)
                .scaleEffect(burst ? RevealMotion.ringMaxScale : 0.35)
                .opacity(burst ? 0 : 0.85)
                .animation(.easeOut(duration: RevealMotion.burstDecay)
                    .delay(RevealMotion.ringDelay(index)), value: burst)
        }
    }

    /// 바깥으로 뻗는 짧은 획 — 동그라미보다 방향과 속도가 보인다.
    private var particles: some View {
        ForEach(0..<RevealMotion.particleCount, id: \.self) { index in
            let offset = RevealMotion.particleOffset(index: index,
                                                     count: RevealMotion.particleCount,
                                                     radius: RevealMotion.particleRadius)
            Capsule()
                .fill(stage.color)
                .frame(width: RevealMotion.particleLength(index: index),
                       height: stage.sparkles && index.isMultiple(of: 3) ? 4 : 3)
                .rotationEffect(.degrees(RevealMotion.particleAngle(index: index)))
                .offset(x: burst ? offset.width : 0, y: burst ? offset.height : 0)
                .opacity(burst ? 0 : 1)
                .animation(.easeOut(duration: RevealMotion.burstDecay), value: burst)
        }
    }

    @ViewBuilder
    private var result: some View {
        if showResult {
            VStack(spacing: 3) {
                Text(grade.label(language))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(stage.color)
                Text(shiny ? l.drawResultShiny : l.drawResultHatching)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .transition(.opacity.combined(with: .offset(y: 8)))
        }
    }

    /// 단계를 하나씩 지나간다. 각 단계는 예비동작이 끝나는 시점에 터진다 —
    /// 그래야 "움츠렸다가 터졌다"로 읽히고, 동시에 터지면 그냥 깜빡임이 된다.
    private func run() async {
        for index in stages.indices {
            stageIndex = index
            burst = false
            beat += 1                                     // 알이 움츠러들기 시작
            try? await Task.sleep(for: .seconds(RevealMotion.anticipation))
            if Task.isCancelled { return }
            burst = true                                  // 링·파티클이 터진다
            if index == stages.count - 1 {
                withAnimation(.easeOut(duration: 0.28).delay(0.18)) { showResult = true }
                if shiny { sparkleBeat += 1 }
            }
            let rest = EggReveal.duration(stageIndex: index, of: stages.count)
                - RevealMotion.anticipation
            try? await Task.sleep(for: .seconds(rest))
            if Task.isCancelled { return }
        }
        onDone()
    }
}
