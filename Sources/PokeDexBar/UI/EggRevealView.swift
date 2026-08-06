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
}

/// 뽑기 연출의 순수 규칙. 뷰 없이 테스트한다.
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

    /// 한 단계가 화면에 머무는 시간(초). 마지막 단계는 결과를 읽을 시간이 필요해 조금 길다.
    static func duration(stageIndex: Int, of total: Int) -> Double {
        stageIndex == total - 1 ? 0.85 : 0.42
    }

    /// 파티클 하나가 날아갈 방향과 거리. 난수 대신 인덱스에서 만든다 — 매번 같은 그림이어야
    /// 스크린샷이 재현되고, 테스트가 "칸 밖으로 안 나간다"를 확인할 수 있다.
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

    static let particleCount = 16
    static let particleRadius: Double = 46
}

/// 뽑기 결과 연출 — 등급이 올라갈 때마다 파티클이 한 번씩 더 터지고, 마지막에 등급을 알려준다.
/// 팝오버 위에 잠깐 덮였다 사라지는 표면이라 타이머를 남기지 않는다(`.task` 가 끝나면 끝).
struct EggRevealView: View {
    let grade: Grade
    let shiny: Bool
    let l: L
    let language: AppLanguage
    let onDone: () -> Void

    @State private var stageIndex = 0
    @State private var burst = false
    @State private var showResult = false

    private var stages: [RevealStage] { EggReveal.stages(for: grade) }
    private var stage: RevealStage { stages[min(stageIndex, stages.count - 1)] }

    var body: some View {
        ZStack {
            Color.black.opacity(0.82).ignoresSafeArea()
            VStack(spacing: 14) {
                ZStack {
                    particles
                    // 알 자체는 단계 색으로 물든다 — 파티클이 사라진 뒤에도 지금 어디까지 왔는지 남는다.
                    Text("🥚")
                        .font(.system(size: 48))
                        .shadow(color: stage.color.opacity(0.9), radius: burst ? 18 : 6)
                        .scaleEffect(burst ? 1.16 : 0.94)
                }
                .frame(width: 140, height: 140)

                if showResult {
                    VStack(spacing: 3) {
                        Text(grade.label(language))
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(stage.color)
                        Text(shiny ? l.drawResultShiny : l.drawResultHatching)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onDone() }   // 기다리기 싫으면 눌러서 건너뛴다
        .task {
            for index in stages.indices {
                stageIndex = index
                withAnimation(.easeOut(duration: 0.22)) { burst = true }
                if index == stages.count - 1 {
                    withAnimation(.easeOut(duration: 0.3).delay(0.12)) { showResult = true }
                }
                try? await Task.sleep(for: .seconds(EggReveal.duration(stageIndex: index,
                                                                      of: stages.count)))
                if Task.isCancelled { return }
                withAnimation(.easeIn(duration: 0.16)) { burst = false }
            }
            try? await Task.sleep(for: .seconds(0.5))
            if Task.isCancelled { return }
            onDone()
        }
    }

    private var particles: some View {
        ForEach(0..<EggReveal.particleCount, id: \.self) { index in
            let offset = EggReveal.particleOffset(index: index, count: EggReveal.particleCount,
                                                  radius: EggReveal.particleRadius)
            Circle()
                .fill(stage.color)
                .frame(width: stage.sparkles && index.isMultiple(of: 2) ? 6 : 4)
                .offset(x: burst ? offset.width : 0, y: burst ? offset.height : 0)
                .opacity(burst ? 0 : 0.95)
                .scaleEffect(burst ? 0.4 : 1)
                .animation(.easeOut(duration: 0.42), value: burst)
        }
    }
}
