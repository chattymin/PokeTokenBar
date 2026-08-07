import SwiftUI

/// 등급별 알 모양. 슬롯에서 남은 시간을 읽기 전에 **무엇을 기다리고 있는지** 먼저 보이게 한다.
/// 색만 바꾸지 않고 무늬 수도 함께 늘린다 — 색약이거나 작은 타일에서도 구분되게.
///
/// 전부 순수 SwiftUI 도형이다. `.brightness` 같은 CALayer 필터를 쓰면 스크린샷 생성기의
/// 오프스크린 렌더에서 통째로 사라진다(도감 실루엣에서 실제로 겪었다).
struct EggIcon: View {
    let grade: Grade
    var size: CGFloat = 20
    /// 부화 시각이 지났으면 금이 간 모습으로 — 슬롯을 훑을 때 "확인해야 할 것"이 즉시 보인다.
    var cracked: Bool = false

    /// 껍질 색(위·아래). 위가 밝고 아래가 짙어 입체로 보인다.
    private var shell: (Color, Color) {
        switch grade {
        case .common: (Color(red: 0.96, green: 0.95, blue: 0.92),
                       Color(red: 0.82, green: 0.80, blue: 0.76))
        case .rare: (Color(red: 0.71, green: 0.88, blue: 1.00),
                     Color(red: 0.42, green: 0.66, blue: 0.88))
        case .epic: (Color(red: 0.80, green: 0.66, blue: 1.00),
                     Color(red: 0.53, green: 0.34, blue: 0.82))
        case .legendary: (Color(red: 1.00, green: 0.87, blue: 0.52),
                          Color(red: 0.93, green: 0.58, blue: 0.16))
        }
    }

    /// 무늬 색 — 껍질보다 진하게.
    private var speckle: Color {
        switch grade {
        case .common: Color(red: 0.66, green: 0.63, blue: 0.58)
        case .rare: Color(red: 0.20, green: 0.45, blue: 0.72)
        case .epic: Color(red: 0.34, green: 0.16, blue: 0.62)
        case .legendary: Color(red: 0.72, green: 0.35, blue: 0.03)
        }
    }

    /// 등급이 오를수록 무늬가 늘어난다 — 색과 별개로 세어서 구분할 수 있게.
    private var speckleCount: Int {
        switch grade {
        case .common: 0
        case .rare: 2
        case .epic: 3
        case .legendary: 4
        }
    }

    /// 무늬 위치(알 폭·높이에 대한 비율)와 지름 비율. 난수를 안 쓴다 — 같은 등급의 알은
    /// 언제나 같은 얼굴이어야 슬롯을 훑을 때 무늬 수가 정보로 읽힌다.
    nonisolated static func speckleLayout(_ index: Int) -> (x: Double, y: Double, r: Double) {
        let table: [(Double, Double, Double)] = [
            (0.34, 0.58, 0.17), (0.63, 0.44, 0.13), (0.48, 0.74, 0.11), (0.70, 0.66, 0.09),
        ]
        return table[index % table.count]
    }

    var body: some View {
        ZStack {
            // 알 실루엣 — 위가 좁고 아래가 둥근 타원.
            EggShape()
                .fill(LinearGradient(colors: [shell.0, shell.1],
                                     startPoint: .top, endPoint: .bottom))
            ForEach(0..<speckleCount, id: \.self) { index in
                let spot = Self.speckleLayout(index)
                Circle()
                    .fill(speckle.opacity(0.55))
                    .frame(width: size * spot.r, height: size * spot.r)
                    .offset(x: size * (spot.x - 0.5), y: size * (spot.y - 0.5))
            }
            if cracked {
                CrackShape().stroke(speckle.opacity(0.85), lineWidth: max(1, size * 0.06))
            }
            if grade == .legendary {
                // 전설만 반짝임 하나 — 슬롯 줄에서 눈이 먼저 가는 자리가 하나는 있어야 한다.
                Image(systemName: "sparkle")
                    .font(.system(size: size * 0.32))
                    .foregroundStyle(.white.opacity(0.95))
                    .offset(x: size * 0.28, y: -size * 0.30)
            }
        }
        .frame(width: size * 0.82, height: size)
    }
}

/// 알 윤곽 — 아래가 크고 위가 좁은 달걀형.
struct EggShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width, h = rect.height
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addCurve(to: CGPoint(x: rect.maxX, y: rect.minY + h * 0.62),
                      control1: CGPoint(x: rect.midX + w * 0.34, y: rect.minY),
                      control2: CGPoint(x: rect.maxX, y: rect.minY + h * 0.28))
        path.addCurve(to: CGPoint(x: rect.midX, y: rect.maxY),
                      control1: CGPoint(x: rect.maxX, y: rect.minY + h * 0.88),
                      control2: CGPoint(x: rect.midX + w * 0.30, y: rect.maxY))
        path.addCurve(to: CGPoint(x: rect.minX, y: rect.minY + h * 0.62),
                      control1: CGPoint(x: rect.midX - w * 0.30, y: rect.maxY),
                      control2: CGPoint(x: rect.minX, y: rect.minY + h * 0.88))
        path.addCurve(to: CGPoint(x: rect.midX, y: rect.minY),
                      control1: CGPoint(x: rect.minX, y: rect.minY + h * 0.28),
                      control2: CGPoint(x: rect.midX - w * 0.34, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

/// 다 깬 알에 그리는 지그재그 금.
struct CrackShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width, h = rect.height
        path.move(to: CGPoint(x: rect.minX + w * 0.16, y: rect.minY + h * 0.52))
        path.addLine(to: CGPoint(x: rect.minX + w * 0.40, y: rect.minY + h * 0.42))
        path.addLine(to: CGPoint(x: rect.minX + w * 0.52, y: rect.minY + h * 0.60))
        path.addLine(to: CGPoint(x: rect.minX + w * 0.72, y: rect.minY + h * 0.46))
        path.addLine(to: CGPoint(x: rect.minX + w * 0.86, y: rect.minY + h * 0.56))
        return path
    }
}

/// 거둔 개체를 한 번 보여주는 카드. 확인을 누른 직후에만 잠깐 덮인다 —
/// 이걸 안 보면 무엇이 나왔는지 박스에 들어가서야 알게 된다.
///
/// **알에서 시작한다.** 예전에는 스프라이트가 처음부터 떠 있어서 부화라는 사건이 없었다:
/// 슬롯에서 금 간 알을 눌렀는데 다음 화면에 이미 포켓몬이 있으면, 무엇이 열린 건지 안 보인다.
/// 그래서 금 간 알이 흔들리다 터지고, 그 자리에서 포켓몬이 튀어나오는 순서로 바꿨다.
struct HatchedRevealView: View {
    let individual: Individual
    let store: PlayerStore
    /// 종 이름을 아는 진화 라인. 없으면 번호로 떨어지고 `onNeedLine` 으로 받아온다.
    var line: EvoLine?
    var onNeedLine: (Int) -> Void = { _ in }
    let onDone: () -> Void

    /// 부화 연출의 국면. 알을 흔들다 → 터뜨리고 → 포켓몬을 보여준다.
    private enum Phase { case shaking, cracking, revealed }

    @State private var phase = Phase.shaking
    @State private var shakeBeat = 0
    @State private var burst = false

    private var l: L { store.l }

    /// 터질 때의 색. 등급의 마지막 연출 단계 색을 그대로 쓴다 — 뽑기와 부화가 같은 말을 해야
    /// "주황 = 레전더리"가 학습된다. 이로치만 예외로 노랗게 터뜨려 특별함을 먼저 알린다.
    private var flash: Color {
        individual.shiny ? .yellow
            : (EggReveal.stages(for: individual.grade).last ?? .white).color
    }

    private var displayName: String {
        let species = line?.localizedName(individual.speciesID, store.language)
            ?? "#\(individual.speciesID)"
        return individual.displayName(speciesName: species, store.language)
    }

    var body: some View {
        ZStack {
            RadialGradient(colors: [flash.opacity(0.16), .black.opacity(0.93)],
                           center: .center, startRadius: 0, endRadius: 190)
            VStack(spacing: 14) {
                ZStack {
                    rings
                    particles
                    if phase == .revealed { hatchling } else { shakingEgg }
                }
                .frame(width: 150, height: 150)
                if phase == .revealed { caption }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onDone() }
        .task(id: individual.baseID) {
            if line == nil { onNeedLine(individual.baseID) }
        }
        .task { await run() }
    }

    /// 금 간 알이 좌우로 흔들린다 — 안에서 뭔가 나오려 한다는 신호.
    private var shakingEgg: some View {
        KeyframeAnimator(initialValue: EggPose.rest, trigger: shakeBeat) { pose in
            EggIcon(grade: individual.grade, size: 78, cracked: true)
                .scaleEffect(pose.scale)
                .rotationEffect(.degrees(pose.rotation))
                .offset(y: pose.lift)
                .shadow(color: flash.opacity(0.8), radius: phase == .cracking ? 24 : 8)
        } keyframes: { _ in
            // 흔들림은 점점 잦아들며 커진다 — 안에서 밀고 있는 것처럼. 구간 합이
            // `hatchShake` 와 같아야 마지막에 멈춰 선 알을 보고 있지 않는다.
            KeyframeTrack(\.rotation) {
                CubicKeyframe(-11, duration: 0.14)
                CubicKeyframe(12, duration: 0.16)
                CubicKeyframe(-9, duration: 0.14)
                CubicKeyframe(7, duration: 0.10)
                CubicKeyframe(0, duration: 0.08)
            }
            KeyframeTrack(\.scale) {
                CubicKeyframe(1.05, duration: 0.30)
                CubicKeyframe(0.96, duration: 0.32)
            }
            KeyframeTrack(\.lift) {
                CubicKeyframe(-3, duration: 0.14)
                CubicKeyframe(2, duration: 0.16)
                CubicKeyframe(-2, duration: 0.14)
                CubicKeyframe(0, duration: 0.18)
            }
        }
    }

    /// 껍질이 터진 자리에서 튀어나온다.
    private var hatchling: some View {
        SpriteView(speciesID: individual.speciesID, form: individual.spriteForm,
                   size: 76, animated: true, shiny: individual.shiny, antialias: true)
            .frame(width: 76, height: 76)
            .transition(.scale(scale: 0.35).combined(with: .opacity))
    }

    private var rings: some View {
        ForEach(0..<RevealMotion.ringCount, id: \.self) { index in
            Circle()
                .strokeBorder(flash, lineWidth: burst ? 1 : 3)
                .frame(width: 74, height: 74)
                .scaleEffect(burst ? RevealMotion.ringMaxScale : 0.35)
                .opacity(burst ? 0 : 0.85)
                .animation(.easeOut(duration: RevealMotion.burstDecay)
                    .delay(RevealMotion.ringDelay(index)), value: burst)
        }
    }

    /// 껍질 조각처럼 흩어진다.
    private var particles: some View {
        ForEach(0..<RevealMotion.particleCount, id: \.self) { index in
            let offset = RevealMotion.particleOffset(index: index,
                                                     count: RevealMotion.particleCount,
                                                     radius: RevealMotion.particleRadius)
            Capsule()
                .fill(flash)
                .frame(width: RevealMotion.particleLength(index: index), height: 3)
                .rotationEffect(.degrees(RevealMotion.particleAngle(index: index)))
                .offset(x: burst ? offset.width : 0, y: burst ? offset.height : 0)
                .opacity(burst ? 0 : 1)
                .animation(.easeOut(duration: RevealMotion.burstDecay), value: burst)
        }
    }

    private var caption: some View {
        VStack(spacing: 4) {
            HStack(spacing: 5) {
                Text(displayName).font(.system(size: 13, weight: .semibold))
                if individual.shiny { Text("✨").font(.system(size: 11)) }
                Text(individual.grade.label(store.language))
                    .font(.system(size: 8, weight: .bold))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.22), in: Capsule())
                if let region = individual.region {
                    Text(region.shortLabel(store.language))
                        .font(.system(size: 8, weight: .bold))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.22), in: Capsule())
                }
            }
            Text(l.hatchedMovedToBox).font(.system(size: 9)).foregroundStyle(.secondary)
        }
        .transition(.opacity.combined(with: .offset(y: 8)))
    }

    private func run() async {
        shakeBeat += 1
        try? await Task.sleep(for: .seconds(RevealMotion.hatchShake))
        if Task.isCancelled { return }
        phase = .cracking
        burst = true
        withAnimation(.spring(duration: 0.42, bounce: 0.45)) { phase = .revealed }
        try? await Task.sleep(for: .seconds(RevealMotion.hatchHold))
        if !Task.isCancelled { onDone() }
    }
}
