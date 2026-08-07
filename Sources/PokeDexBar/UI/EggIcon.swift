import SwiftUI

/// 등급별 알. **그림 파일**이다(`Resources/eggs/egg-<등급>.png`) — 예전에는 SwiftUI 도형으로
/// 껍질과 무늬를 직접 그렸는데, 손으로 그린 일러스트가 훨씬 알처럼 보인다.
///
/// 금 간 표시(`cracked`)만 그림 위에 도형으로 얹는다. 등급마다 금 간 그림을 따로 두면 파일이
/// 여덟 장이 되고, 금은 "지금 확인할 수 있다"는 상태 표시라 껍질 무늬와 성격이 다르다.
///
/// 그림 로딩은 `RibbonIcon` 과 같은 방식이다 — 배포 `.app` 에서는 `Bundle.module` 을 못 쓴다.
struct EggIcon: View {
    let grade: Grade
    var size: CGFloat = 20
    /// 부화 시각이 지났으면 금이 간 모습으로 — 슬롯을 훑을 때 "확인해야 할 것"이 즉시 보인다.
    var cracked: Bool = false

    /// 금 색 — 껍질 위에 얹히므로 어느 등급에서도 보이도록 어둡게.
    private var crackColor: Color { Color(red: 0.16, green: 0.14, blue: 0.13) }

    var body: some View {
        ZStack {
            if let image = Self.image(for: grade) {
                Image(nsImage: image)
                    .resizable().interpolation(.high)
                    .scaledToFit()
            }
            if cracked {
                CrackShape().stroke(crackColor.opacity(0.9), lineWidth: max(1, size * 0.055))
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

    /// 등급별 그림. 한 번 읽으면 캐시한다 — 박스·슬롯 그리드가 칸마다 디스크를 때리지 않게.
    @MainActor private static var cache: [Grade: NSImage] = [:]

    @MainActor static func image(for grade: Grade) -> NSImage? {
        if let cached = cache[grade] { return cached }
        guard let url = resourceURL(for: grade), let image = NSImage(contentsOf: url) else {
            return nil
        }
        cache[grade] = image
        return image
    }

    /// 리소스 번들 위치. 배포 `.app` 에서 `Bundle.module` 이 찾는 자리(번들 루트)에는 번들을 둘 수
    /// 없다 — codesign 이 거부한다. 그래서 서명 가능한 `Contents/Resources/` 를 직접 찾는다.
    /// (`RibbonIcon.resourceURL` 과 같은 이유·같은 모양.)
    nonisolated static func resourceURL(for grade: Grade) -> URL? {
        let name = "egg-\(grade.rawValue)"
        guard AppEnv.isBundledApp else {
            return Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "eggs")
                ?? Bundle.module.url(forResource: name, withExtension: "png")
        }
        let bundlePath = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/PokeDexBar_PokeDexBar.bundle")
        guard let bundle = Bundle(path: bundlePath.path) else { return nil }
        return bundle.url(forResource: name, withExtension: "png", subdirectory: "eggs")
            ?? bundle.url(forResource: name, withExtension: "png")
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

    /// 껍질이 터진 자리에서 튀어나온다. **이로치면 반짝임이 둘러싼다** — 이름 옆의 ✨ 하나로는
    /// 1/64 짜리 사건이 그냥 지나간다. 여기가 그걸 처음 알게 되는 자리다.
    private var hatchling: some View {
        ZStack {
            if individual.shiny {
                ShinySparkles(specs: SparkleSpec.ring(count: 9, radius: 0.46), period: 1.4)
                    .frame(width: 128, height: 128)
            }
            SpriteView(speciesID: individual.speciesID, form: individual.spriteForm,
                       size: 76, animated: true, shiny: individual.shiny, antialias: true)
                .frame(width: 76, height: 76)
        }
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
