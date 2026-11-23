import SwiftUI

// 연출 네 가지 — 등급별 알 깨기(부화), 진화, 몬스터볼 회수(졸업), 메타몽 리빌. 본가 BW 연출이 기준이다.
//
// 전부 "경과 시간의 순수 함수"다: 타이밍 표(`profile`·`frame(at:)`)·입자 계(`CelebrationFX`)와 그 값을
// 그리는 뷰가 분리돼 있어, 앱은 `TimelineView(.animation)` 으로 시간을 흘려 넣고 테스트는 임의의 순간을
// 결정적으로 그린다. 각 연출은 두 층이다(`CelebrationLayer`) — 칸 안의 스프라이트 층과 칸 밖으로 넘치는
// 빛 층. 그림은 전부 SwiftUI 도형·그라데이션·Canvas 다 — 저장소에 포켓몬 에셋을 커밋하지 않는 규칙 때문에
// 알 껍질·몬스터볼을 그림으로 그린다(알과 포켓몬 스프라이트는 호출자가 넘긴다).

private typealias FX = CelebrationFX

/// 어느 층을 그리나. 헤더는 칸(둥근 테두리에 잘림) 안에 `.sprite`, 그 바깥 오버레이에 `.light` 를 따로 얹고,
/// 플로팅 펫은 펫 창에 `.sprite`, 클릭이 통과하는 별도 창에 `.light` 를 그린다.
enum CelebrationLayer { case sprite, light, both }

/// `.both` 면 빛 층을 칸 중심에 `overflow` 배로 겹친다(잘리지 않는 오버레이).
@MainActor
private struct Layered<Sprite: View, Light: View>: View {
    let layer: CelebrationLayer
    let size: CGFloat
    @ViewBuilder var sprite: Sprite
    @ViewBuilder var light: Light

    var body: some View {
        let lightSide = size * CelebrationFX.overflow
        switch layer {
        case .sprite:
            sprite.frame(width: size, height: size)
        case .light:
            light.frame(width: lightSide, height: lightSide).allowsHitTesting(false)
        case .both:
            sprite.frame(width: size, height: size)
                .overlay { light.frame(width: lightSide, height: lightSide).allowsHitTesting(false) }
        }
    }
}

// MARK: - 부화 (등급별 알 깨기)

/// 알이 깨지는 모습만 보고 등급을 맞힐 수 있게 하는 등급별 연출 표.
///
/// 플레이어가 학습할 수 있도록 **등급이 오를수록 모든 신호가 단조롭게 커진다**(흔들림 횟수·길이·금·빛·
/// 파편·반짝이·폭발 크기·섬광 색). 이로치는 여기 넣지 않는다 — 공개 뒤 따로 반짝여 놀라게 한다.
enum HatchEffect {
    struct Profile: Equatable, Sendable {
        let rarity: Rarity
        /// 알이 흔들리는 횟수(등급 신호의 중심).
        let wobbles: Int
        /// 껍질이 깨지는 순간 — 섬광이 최고조가 되고 그 밑에서 포켓몬이 나타난다.
        let revealAt: TimeInterval
        /// 마지막(가장 센) 흔들림의 최대 기울기. 앞의 흔들림은 이보다 약하게 점점 세진다.
        let wobbleDegrees: Double
        /// 깨지기 전까지 생기는 금의 개수(`crackPaths` 의 앞에서부터).
        let cracks: Int
        /// 알 둘레 등급색 후광의 세기(0 = 없음).
        let glow: Double
        /// 금 사이로 등급색 빛이 샌다(희귀 이상) — 아니면 어두운 금만 그린다.
        let leaksLight: Bool
        /// 알 뒤에서 회전하는 빛줄기(전설만).
        let rays: Bool
        /// 피어오르는 금빛 티끌 수(전설만).
        let motes: Int
        /// 마지막 흔들림 앞의 뜸 — 전설의 "숨 고르기".
        let pauseBeforeLast: TimeInterval
        /// 섬광의 등급색 비율(0 = 흰 섬광).
        let flashTint: Double
        /// 깨지는 순간 섬광의 불투명도.
        let flashPeak: Double
        /// 튀는 껍질 조각 수.
        let fragments: Int
        /// 공개 때 터지는 등급색 반짝이 수.
        let sparkles: Int
        /// 폭발 번짐의 지름(칸 단위, 최대 `CelebrationFX.overflow`).
        let burst: Double

        /// 깨진 뒤 파편이 떨어지고 반짝이가 사라지는 꼬리까지 포함한 전체 길이.
        var duration: TimeInterval { revealAt + HatchEffect.tail }
    }

    static let tail: TimeInterval = 1.0
    static let wobbleLength: TimeInterval = 0.36
    static let lead: TimeInterval = 0.15
    /// 마지막 흔들림이 끝난 뒤 깨지기까지의 뜸(빛이 차오르는 구간).
    static let buildUp: TimeInterval = 0.25
    static let reducedRevealAt: TimeInterval = 0.55
    static let reducedTail: TimeInterval = 0.5
    /// 연출 중 알 크기. 평소 알은 칸을 꽉 채워(크롭) 그대로 기울이면 칸에 잘리고 후광이 가려진다.
    static let eggInset: Double = 0.82

    static func profile(for rarity: Rarity) -> Profile {
        switch rarity {
        case .common:
            Profile(rarity: rarity, wobbles: 1, revealAt: 1.1, wobbleDegrees: 8, cracks: 1, glow: 0,
                    leaksLight: false, rays: false, motes: 0, pauseBeforeLast: 0, flashTint: 0, flashPeak: 0.85,
                    fragments: 6, sparkles: 6, burst: 1.3)
        case .uncommon:
            Profile(rarity: rarity, wobbles: 2, revealAt: 1.6, wobbleDegrees: 10, cracks: 3, glow: 0.5,
                    leaksLight: false, rays: false, motes: 0, pauseBeforeLast: 0, flashTint: 0.3, flashPeak: 0.9,
                    fragments: 9, sparkles: 10, burst: 1.6)
        case .rare:
            Profile(rarity: rarity, wobbles: 3, revealAt: 2.3, wobbleDegrees: 13, cracks: 4, glow: 0.8,
                    leaksLight: true, rays: false, motes: 0, pauseBeforeLast: 0, flashTint: 0.5, flashPeak: 0.95,
                    fragments: 12, sparkles: 14, burst: 1.9)
        case .legendary:
            Profile(rarity: rarity, wobbles: 4, revealAt: 3.1, wobbleDegrees: 16, cracks: 6, glow: 1,
                    leaksLight: true, rays: true, motes: 18, pauseBeforeLast: 0.55, flashTint: 0.7, flashPeak: 1,
                    fragments: 16, sparkles: 22, burst: 2.2)
        }
    }

    static func revealTime(_ p: Profile, reduceMotion: Bool) -> TimeInterval {
        reduceMotion ? reducedRevealAt : p.revealAt
    }

    static func duration(_ p: Profile, reduceMotion: Bool) -> TimeInterval {
        reduceMotion ? reducedRevealAt + reducedTail : p.duration
    }

    /// 흔들림 시작 시각들 — 사이사이 뜸이 있다. 전설은 마지막 앞에 한 번 더 숨을 고른다.
    static func wobbleStarts(_ p: Profile) -> [TimeInterval] {
        let window = max(0, p.revealAt - buildUp - lead - wobbleLength - p.pauseBeforeLast)
        let spacing = p.wobbles > 1 ? window / Double(p.wobbles - 1) : 0
        return (0..<p.wobbles).map { i in
            lead + Double(i) * spacing + (i == p.wobbles - 1 && i > 0 ? p.pauseBeforeLast : 0)
        }
    }

    /// 금 k 가 생기는 시각 — 흔들림이 알을 "두드리는" 순간(흔들림 중간)에 맞춘다.
    static func crackTimes(_ p: Profile) -> [TimeInterval] {
        let starts = wobbleStarts(p)
        guard !starts.isEmpty else { return [] }
        var perWobble: [Int: Int] = [:]
        return (0..<p.cracks).map { k in
            let w = min(starts.count - 1, k * starts.count / max(1, p.cracks))
            let order = perWobble[w, default: 0]
            perWobble[w] = order + 1
            return starts[w] + wobbleLength * 0.45 + Double(order) * 0.08
        }
    }

    struct Frame: Equatable {
        var tilt: Double = 0
        var crackProgress: [Double] = []
        /// 등급색 후광 0…1.
        var glow: Double = 0
        var rays: Double = 0
        var rayAngle: Double = 0
        /// 섬광(빛 층) 불투명도.
        var flash: Double = 0
        /// 알 대신 포켓몬(깨진 뒤).
        var revealed = false
        var eggScale: Double = 1
        var hatchlingScale: Double = 1
        /// 깨진 뒤 경과(깨지기 전엔 음수).
        var sinceBreak: Double = -1
    }

    static let crackGrowth: TimeInterval = 0.18

    static func frame(_ p: Profile, at t: TimeInterval, reduceMotion: Bool = false) -> Frame {
        var f = Frame()
        let reveal = revealTime(p, reduceMotion: reduceMotion)
        f.revealed = t >= reveal
        f.sinceBreak = t - reveal
        if reduceMotion {
            // 움직임 없이: 금은 옅게 떠오르고, 등급색 후광이 차오른 뒤 섬광. 알 크기도 그대로.
            let appear = FX.smoothstep(0, reveal * 0.6, t)
            f.crackProgress = Array(repeating: f.revealed ? 0 : appear, count: p.cracks)
            f.glow = p.glow * (f.revealed ? 1 - FX.smoothstep(reveal, reveal + reducedTail, t)
                                          : FX.smoothstep(0, reveal, t))
            f.flash = flash(peak: p.flashPeak, reveal: reveal, fade: reducedTail, at: t)
            return f
        }
        for (i, start) in wobbleStarts(p).enumerated() where t >= start && t <= start + wobbleLength {
            let u = (t - start) / wobbleLength
            let amp = p.wobbleDegrees * (0.6 + 0.4 * Double(i + 1) / Double(p.wobbles))
            f.tilt = amp * sin(u * 3 * .pi) * (1 - 0.5 * u)
        }
        f.crackProgress = f.revealed ? Array(repeating: 0, count: p.cracks)
            : crackTimes(p).map { FX.clamp01((t - $0) / crackGrowth) }
        let firstStart = wobbleStarts(p).first ?? 0
        if f.revealed {
            let fade = 1 - FX.smoothstep(reveal, reveal + tail * 0.7, t)
            f.glow = p.glow * fade
            f.rays = p.rays ? fade : 0
            f.hatchlingScale = FX.springPop(t - reveal)
        } else {
            f.glow = p.glow * pow(FX.smoothstep(firstStart, reveal, t), 1.4)
            f.rays = p.rays ? FX.smoothstep(firstStart + 0.3, reveal - 0.2, t) : 0
            let settle = 1 - (1 - eggInset) * FX.smoothstep(0, lead, t)
            f.eggScale = settle + 0.07 * FX.smoothstep(reveal - buildUp, reveal, t)
        }
        f.rayAngle = t * 40
        f.flash = flash(peak: p.flashPeak, reveal: reveal, fade: 0.6, at: t)
        return f
    }

    private static func flash(peak: Double, reveal: TimeInterval, fade: TimeInterval, at t: TimeInterval) -> Double {
        if t < reveal { return peak * FX.smoothstep(reveal - 0.15, reveal, t) }
        let x = FX.clamp01((t - reveal) / fade)
        return peak * (1 - x) * (1 - x)
    }

    /// 금의 꺾은선(칸 기준 0…1 좌표). 0 = 가운데 금, 1·2 = 좌우로 번짐, 3~5 = 위아래 갈래.
    static let crackPaths: [[CGPoint]] = [
        [CGPoint(x: 0.34, y: 0.50), CGPoint(x: 0.40, y: 0.43), CGPoint(x: 0.45, y: 0.51), CGPoint(x: 0.51, y: 0.42),
         CGPoint(x: 0.56, y: 0.52), CGPoint(x: 0.61, y: 0.44), CGPoint(x: 0.66, y: 0.51)],
        [CGPoint(x: 0.34, y: 0.50), CGPoint(x: 0.28, y: 0.44), CGPoint(x: 0.23, y: 0.51), CGPoint(x: 0.19, y: 0.46)],
        [CGPoint(x: 0.66, y: 0.51), CGPoint(x: 0.72, y: 0.45), CGPoint(x: 0.77, y: 0.52), CGPoint(x: 0.81, y: 0.47)],
        [CGPoint(x: 0.40, y: 0.43), CGPoint(x: 0.37, y: 0.35), CGPoint(x: 0.42, y: 0.29), CGPoint(x: 0.39, y: 0.22)],
        [CGPoint(x: 0.56, y: 0.52), CGPoint(x: 0.60, y: 0.60), CGPoint(x: 0.55, y: 0.67), CGPoint(x: 0.59, y: 0.74)],
        [CGPoint(x: 0.72, y: 0.45), CGPoint(x: 0.69, y: 0.37), CGPoint(x: 0.74, y: 0.31)],
    ]

    /// 알 스프라이트를 위·아래로 쪼개는 마스크(칸 중심 원점, 칸 단위) — 지그재그 금 위쪽 전부 / 아래쪽 전부.
    /// 벡터로 그린 껍질은 픽셀 알과 따로 놀아 싸 보였다 → 실제 알 그림을 잘라 윗뚜껑으로 날린다.
    static func shellMask(top: Bool) -> [CGPoint] {
        let zig = -0.02
        let xs = stride(from: -0.6, through: 0.6, by: 0.1)
        let zigzag = xs.enumerated().map { i, x in CGPoint(x: x, y: zig + (i.isMultiple(of: 2) ? 0.04 : -0.04)) }
        let edge = top ? -0.6 : 0.6
        return zigzag + [CGPoint(x: 0.6, y: edge), CGPoint(x: -0.6, y: edge)]
    }
}

/// 꺾은선 하나. `trim` 으로 자라나게 그린다.
private struct PolylineShape: Shape {
    let points: [CGPoint]
    /// true = 점이 칸 중심 원점·칸 단위(껍질), false = 칸 0…1 좌표(금).
    var centered = false
    var closed = false
    func path(in rect: CGRect) -> Path {
        var path = Path()
        func map(_ p: CGPoint) -> CGPoint {
            centered ? CGPoint(x: rect.midX + p.x * rect.width, y: rect.midY + p.y * rect.height)
                     : CGPoint(x: rect.minX + p.x * rect.width, y: rect.minY + p.y * rect.height)
        }
        guard let first = points.first else { return path }
        path.move(to: map(first))
        for p in points.dropFirst() { path.addLine(to: map(p)) }
        if closed { path.closeSubpath() }
        return path
    }
}

/// 부화 연출 한 순간. `egg`·`hatchling` 은 호출자가 그린다(앱은 SpriteView, 테스트는 고정 이미지).
@MainActor
struct HatchEffectView<Egg: View, Hatchling: View>: View {
    let profile: HatchEffect.Profile
    let elapsed: TimeInterval
    var size: CGFloat = 76
    var reduceMotion = false
    /// 공개 뒤 따로 반짝인다(등급 신호와 섞지 않는다).
    var shiny = false
    var layer: CelebrationLayer = .both
    @ViewBuilder var egg: Egg
    @ViewBuilder var hatchling: Hatchling

    var body: some View {
        let f = HatchEffect.frame(profile, at: elapsed, reduceMotion: reduceMotion)
        Layered(layer: layer, size: size) { sprite(f) } light: {
            // 윗뚜껑은 빛 층에서 날린다 — 헤더 칸(둥근 테두리)에 잘리지 않고 칸 밖으로 튀어 오르게.
            ZStack {
                light(f)
                if f.revealed, !reduceMotion, f.sinceBreak < 0.6 { cap(f.sinceBreak) }
                flash(f)
            }
        }
    }

    /// 알 그림의 윗부분 — 튀어 오르며 돌아 옆으로 떨어진다.
    private func cap(_ bt: Double) -> some View {
        let rise = (1 - exp(-6 * bt)) / 6
        return egg.mask(PolylineShape(points: HatchEffect.shellMask(top: true), centered: true, closed: true))
            .scaleEffect(HatchEffect.eggInset + 0.07)
            .frame(width: size, height: size)
            .rotationEffect(.degrees(-150 * bt), anchor: UnitPoint(x: 0.35, y: 0.45))
            .offset(x: size * 0.5 * bt, y: size * (-1.8 * rise + 1.9 * bt * bt))
            .opacity(1 - FX.smoothstep(0.4, 0.6, bt))
    }

    /// 깨지는 순간의 섬광 — 파편·뚜껑까지 덮도록 맨 위에.
    private func flash(_ f: HatchEffect.Frame) -> some View {
        let p = profile
        let tint = celebrationTint(p.rarity)
        let reduce = reduceMotion
        return Canvas { ctx, canvas in
            let s = FXSpace(size: canvas, unit: canvas.width / CelebrationFX.overflow)
            guard f.flash > 0 else { return }
            let grow = f.revealed && !reduce ? FX.easeOutCubic(f.sinceBreak / 0.35) : 0
            let radius = 0.55 + (p.burst / 2 - 0.55) * grow
            ctx.glow(s, x: 0, y: 0, radius: radius, color: tint, opacity: f.flash * max(p.flashTint, 0.35))
            ctx.flare(s, radius: 0.85, color: .white, opacity: f.flash)
            if p.flashTint > 0 {
                ctx.flare(s, radius: 0.85, color: tint, opacity: f.flash * p.flashTint * 0.35)
            }
        }
    }

    @ViewBuilder
    private func sprite(_ f: HatchEffect.Frame) -> some View {
        let tint = celebrationTint(profile.rarity)
        let line = size / 76
        ZStack {
            if f.revealed {
                // 알이 위아래로 쪼개진다 — 윗뚜껑은 튀어 오르며 돌아 날아가고, 아랫껍질은 잠깐 남았다 가라앉는다.
                // 포켓몬은 그 사이에서 튀어나온다(아랫껍질이 앞에 있어 껍질에서 나오는 인상).
                hatchling.scaleEffect(f.hatchlingScale, anchor: UnitPoint(x: 0.5, y: 0.8))
                if !reduceMotion, f.sinceBreak < 0.6 {
                    let bt = f.sinceBreak
                    let scale = HatchEffect.eggInset + 0.07
                    egg.mask(PolylineShape(points: HatchEffect.shellMask(top: false), centered: true, closed: true))
                        .scaleEffect(scale)
                        .offset(y: size * 0.18 * bt * bt * 4)
                        .opacity(1 - FX.smoothstep(0.15, 0.4, bt))
                }
            } else {
                ZStack {
                    egg
                    ForEach(0..<min(profile.cracks, HatchEffect.crackPaths.count), id: \.self) { k in
                        let progress = f.crackProgress.indices.contains(k) ? f.crackProgress[k] : 0
                        if progress > 0 { crack(k, progress: progress, tint: tint, line: line) }
                    }
                }
                .shadow(color: tint.opacity(f.glow), radius: 7 * line * f.glow)
                .scaleEffect(f.eggScale)
                .rotationEffect(.degrees(f.tilt), anchor: UnitPoint(x: 0.5, y: 0.92))
            }
        }
    }

    @ViewBuilder
    private func crack(_ k: Int, progress: Double, tint: Color, line: CGFloat) -> some View {
        let shape = PolylineShape(points: HatchEffect.crackPaths[k]).trim(from: 0, to: reduceMotion ? 1 : progress)
        let opacity = reduceMotion ? progress : 1
        if profile.leaksLight {
            // 금 사이로 빛이 샌다 — 넓은 등급색 번짐 위에 흰 심지.
            ZStack {
                shape.stroke(tint, style: StrokeStyle(lineWidth: 6 * line, lineCap: .round, lineJoin: .round))
                    .blur(radius: 2.5 * line)
                shape.stroke(tint, style: StrokeStyle(lineWidth: 3 * line, lineCap: .round, lineJoin: .round))
                shape.stroke(Color.white, style: StrokeStyle(lineWidth: 1.4 * line, lineCap: .round, lineJoin: .round))
            }
            .opacity(opacity)
        } else {
            ZStack {
                shape.stroke(EggPalette.outline, style: StrokeStyle(lineWidth: 2.4 * line, lineCap: .round, lineJoin: .round))
                if profile.glow > 0 {
                    shape.stroke(tint.opacity(0.8), style: StrokeStyle(lineWidth: 0.9 * line, lineCap: .round, lineJoin: .round))
                }
            }
            .opacity(opacity)
        }
    }

    private func light(_ f: HatchEffect.Frame) -> some View {
        let p = profile
        let tint = celebrationTint(p.rarity)
        let t = elapsed
        let reduce = reduceMotion
        let shinyOn = shiny
        return Canvas { ctx, canvas in
            let s = FXSpace(size: canvas, unit: canvas.width / CelebrationFX.overflow)
            // 알 둘레 후광(가운데는 비워 알을 덮지 않는다).
            if f.glow > 0, !f.revealed {
                ctx.halo(s, radius: 0.42, outer: 0.9, color: tint, opacity: f.glow * 0.7)
            }
            if f.rays > 0, !reduce {
                Self.rays(ctx, s, tint: tint, opacity: f.rays, angle: f.rayAngle)
            }
            if p.motes > 0, !reduce {
                for m in FX.risingMotes(seed: 31, count: p.motes, at: t, from: 0.4, until: p.revealAt + 0.4) {
                    ctx.glow(s, x: m.x, y: m.y, radius: m.size * 1.6, color: Color(red: 1, green: 0.78, blue: 0.25),
                             opacity: m.opacity * 0.8)
                    ctx.glow(s, x: m.x, y: m.y, radius: m.size * 0.45, color: .white, opacity: m.opacity)
                }
            }
            guard f.revealed, !reduce else { return }
            let bt = f.sinceBreak
            if bt < 0.6 {
                let u = bt / 0.6
                ctx.shockwave(s, radius: 0.3 + (p.burst / 2 - 0.35) * FX.easeOutCubic(u), width: 0.08 + 0.06 * u,
                              color: tint, opacity: 0.85 * (1 - u))
            }
            for (i, shard) in FX.debris(seed: UInt64(11 + p.fragments), count: p.fragments, at: bt,
                                        speed: 1.1...2.2, spread: 1.45, gravity: 2.6, drag: 3.0, life: 0.95,
                                        origin: (0, -0.08)).enumerated() {
                ctx.shellShard(s, shard, seed: i)
            }
            for spark in FX.burst(seed: UInt64(53 + p.sparkles), count: p.sparkles, at: bt - 0.05,
                                  reach: p.burst / 2 * 0.85, life: 0.9) {
                ctx.sparkle(s, spark, color: tint)
            }
            if shinyOn {
                // 이로치: 공개 0.35초 뒤 오른쪽 위에서 따로 반짝인다(✨ 자리).
                for i in 0..<4 {
                    let local = bt - 0.35 - Double(i) * 0.12
                    guard local > 0, local < 0.7 else { continue }
                    let pulse = sin(local / 0.7 * .pi)
                    ctx.sparkle(s, FX.Particle(x: 0.28 + Double(i % 2) * 0.12, y: -0.32 + Double(i / 2) * 0.1,
                                               size: 0.12 + 0.08 * pulse, rotation: local * 2, opacity: pulse,
                                               shape: .sparkle),
                                color: Color(red: 0.55, green: 0.85, blue: 1))
                }
            }
        }
    }

    private static func rays(_ ctx: GraphicsContext, _ s: FXSpace, tint: Color, opacity: Double, angle: Double) {
        let count = 12
        let r = s.length(Double(CelebrationFX.overflow) / 2)
        var path = Path()
        let half = Double.pi / Double(count) * 0.3
        for i in 0..<count {
            let a = Double(i) / Double(count) * 2 * .pi + angle * .pi / 180
            path.move(to: s.center)
            path.addLine(to: CGPoint(x: s.center.x + r * CGFloat(cos(a - half)), y: s.center.y + r * CGFloat(sin(a - half))))
            path.addLine(to: CGPoint(x: s.center.x + r * CGFloat(cos(a + half)), y: s.center.y + r * CGFloat(sin(a + half))))
            path.closeSubpath()
        }
        // 가운데(알 자리)는 비우고 바깥으로 갈수록 옅어지는 광선 — 흐리게 번져 딱딱한 부채꼴로 안 보이게.
        ctx.drawLayer { layer in
            layer.opacity = opacity * 0.6
            layer.addFilter(.blur(radius: s.unit * 0.035))
            layer.fill(path, with: .radialGradient(Gradient(stops: [
                .init(color: tint.opacity(0), location: 0.24), .init(color: tint.opacity(0.85), location: 0.4),
                .init(color: tint.opacity(0.25), location: 0.72), .init(color: tint.opacity(0), location: 1)]),
                center: s.center, startRadius: 0, endRadius: r))
        }
    }
}

// MARK: - 진화 (BW 진화 신)

/// 주위가 어두워지고 빛이 소용돌이치며 모여들어 흰 실루엣이 되고, 옛·새 실루엣이 점점 빨리 번갈아 보이다가,
/// 칸 밖까지 퍼지는 흰 섬광과 함께 새 모습이 튀어나오는 진화 연출의 타이밍 표.
enum EvolutionEffect {
    static let whitenStart: TimeInterval = 0.35
    static let whitenEnd: TimeInterval = 0.85
    static let alternateEnd: TimeInterval = 2.35
    /// 섬광 최고조 = 새 모습 공개(정보 칸도 이때 새 단계로 바뀐다).
    static let revealAt: TimeInterval = 2.55
    static let tail: TimeInterval = 0.65
    static var duration: TimeInterval { revealAt + tail }
    /// 번갈아 보이는 횟수(반주기 단위 4.5회 = 옛→새로 끝난다). 시작 1Hz 에서 선형으로 빨라진다.
    static let alternationCycles: Double = 4.5
    static let startFrequency: Double = 1
    static let reducedRevealAt: TimeInterval = 0.5
    static let reducedTail: TimeInterval = 0.5

    static func revealTime(reduceMotion: Bool) -> TimeInterval { reduceMotion ? reducedRevealAt : revealAt }
    static func duration(reduceMotion: Bool) -> TimeInterval {
        reduceMotion ? reducedRevealAt + reducedTail : duration
    }

    struct Frame: Equatable {
        var mix: Double = 0
        var oldScale: Double = 1
        var newScale: Double = 1
        var whiteness: Double = 0
        /// 주위가 어두워지는 정도 0…1.
        var dim: Double = 0
        /// 가운데로 모이는 빛 0…1.
        var gather: Double = 0
        var flash: Double = 0
        var revealed = false
        var popScale: Double = 1
        var sinceReveal: Double = -1
    }

    static func cycles(at t: TimeInterval) -> Double {
        let span = alternateEnd - whitenEnd
        let tau = min(max(0, t - whitenEnd), span)
        let endFrequency = 2 * alternationCycles / span - startFrequency
        return startFrequency * tau + (endFrequency - startFrequency) * tau * tau / (2 * span)
    }

    static func frame(at t: TimeInterval, reduceMotion: Bool = false) -> Frame {
        var f = Frame()
        let reveal = revealTime(reduceMotion: reduceMotion)
        f.revealed = t >= reveal
        f.sinceReveal = t - reveal
        if reduceMotion {
            f.mix = FX.smoothstep(0, reveal, t)
            f.flash = t < reveal ? 0.85 * FX.smoothstep(reveal - 0.15, reveal, t)
                                 : 0.85 * pow(1 - FX.clamp01((t - reveal) / reducedTail), 2)
            return f
        }
        f.dim = FX.smoothstep(0, 0.45, t) * (1 - FX.smoothstep(reveal + 0.05, reveal + 0.5, t))
        if f.revealed {
            let tau = t - reveal
            f.mix = 1
            f.whiteness = 1 - FX.smoothstep(reveal, reveal + 0.3, t)
            f.popScale = FX.springPop(tau)
            f.flash = pow(1 - FX.clamp01(tau / (tail * 0.85)), 2)
            return f
        }
        f.whiteness = FX.smoothstep(whitenStart, whitenEnd, t)
        f.mix = t >= alternateEnd ? 1 : (1 - cos(2 * .pi * cycles(at: t))) / 2
        // 옛 모습은 줄며 사라지고 새 모습은 커지며 나타난다 — 형태가 줄었다 늘었다 하는 인상.
        f.oldScale = 1 - 0.18 * f.mix
        f.newScale = 0.82 + 0.18 * f.mix
        f.gather = FX.smoothstep(alternateEnd - 0.4, reveal, t)
        f.flash = FX.smoothstep(alternateEnd, reveal, t)
        return f
    }
}

/// 진화 연출 한 순간. `from`·`to` 는 진화 전·후 스프라이트.
@MainActor
struct EvolutionEffectView<From: View, To: View>: View {
    let elapsed: TimeInterval
    var size: CGFloat = 76
    var reduceMotion = false
    var layer: CelebrationLayer = .both
    @ViewBuilder var from: From
    @ViewBuilder var to: To

    var body: some View {
        let f = EvolutionEffect.frame(at: elapsed, reduceMotion: reduceMotion)
        Layered(layer: layer, size: size) { sprite(f) } light: { light(f) }
    }

    @ViewBuilder
    private func sprite(_ f: EvolutionEffect.Frame) -> some View {
        let glowRadius = 6 * size / 76 * f.whiteness
        ZStack {
            // 어두워진 무대 — 가운데가 짙고 가장자리로 풀린다(플로팅 펫에선 바탕 없이 둥근 어둠).
            Circle()
                .fill(RadialGradient(colors: [Color(red: 0.05, green: 0.07, blue: 0.2).opacity(0.9),
                                              Color(red: 0.05, green: 0.07, blue: 0.2).opacity(0)],
                                     center: .center, startRadius: size * 0.1, endRadius: size * 0.62))
                .frame(width: size * 1.3, height: size * 1.3)
                .opacity(f.dim)
            if f.revealed {
                to.brightness(f.whiteness).scaleEffect(f.popScale, anchor: UnitPoint(x: 0.5, y: 0.8))
            } else {
                // brightness(1) 은 알파를 지키고 색만 하얗게 민다 → 스프라이트 모양 그대로의 흰 실루엣.
                ZStack {
                    if f.mix < 1 {
                        from.brightness(f.whiteness).scaleEffect(f.oldScale).opacity(1 - f.mix)
                    }
                    if f.mix > 0 {
                        to.brightness(f.whiteness).scaleEffect(f.newScale).opacity(f.mix)
                    }
                }
                .shadow(color: Color(red: 0.75, green: 0.9, blue: 1).opacity(f.whiteness), radius: glowRadius)
                .shadow(color: Color.white.opacity(f.whiteness * 0.8), radius: glowRadius * 0.4)
            }
        }
    }

    private func light(_ f: EvolutionEffect.Frame) -> some View {
        let t = elapsed
        let reduce = reduceMotion
        return Canvas { ctx, canvas in
            let s = FXSpace(size: canvas, unit: canvas.width / CelebrationFX.overflow)
            let pale = Color(red: 0.7, green: 0.88, blue: 1)
            if !reduce {
                for m in FX.converging(seed: 7, count: 30, at: t, from: 0.05, until: 1.9) {
                    ctx.glow(s, x: m.x, y: m.y, radius: m.size * 2.2, color: pale, opacity: m.opacity * 0.85)
                    ctx.glow(s, x: m.x, y: m.y, radius: m.size * 0.6, color: .white, opacity: m.opacity)
                }
                if f.gather > 0 {
                    ctx.glow(s, x: 0, y: 0, radius: 0.35 + 0.25 * f.gather, color: pale, opacity: f.gather * 0.8)
                }
            }
            if f.flash > 0 {
                let grow = f.revealed && !reduce ? FX.easeOutCubic(f.sinceReveal / 0.4) : 0
                let radius = 0.5 + 0.58 * grow
                ctx.glow(s, x: 0, y: 0, radius: radius, color: pale, opacity: f.flash * 0.8)
                ctx.flare(s, radius: 0.6 + 0.3 * grow, color: .white, opacity: f.flash)
            }
            guard f.revealed, !reduce else { return }
            let rt = f.sinceReveal
            if rt < 0.55 {
                let u = rt / 0.55
                ctx.shockwave(s, radius: 0.35 + 0.6 * FX.easeOutCubic(u), width: 0.07 + 0.05 * u,
                              color: Color(red: 0.8, green: 0.92, blue: 1), opacity: 0.9 * (1 - u))
            }
            for (i, spark) in FX.burst(seed: 19, count: 14, at: rt - 0.05, reach: 0.85, life: 0.6).enumerated() {
                ctx.sparkle(s, spark, color: i.isMultiple(of: 2) ? Color(red: 1, green: 0.92, blue: 0.5) : pale)
            }
        }
    }
}

// MARK: - 졸업 (몬스터볼 회수)

/// 본가의 회수 연출: 볼이 나타나 위 덮개가 열리고, 흰 빛을 맞은 포켓몬이 붉은 빛 실루엣이 되어 휘어진 빛줄기로
/// 볼 속에 빨려 든다("슈욱"). 볼이 닫히며 번쩍, 떨어져 한 번 튀고, 뜸을 두고 세 번 흔들리며(버튼이 붉게 깜빡),
/// "딸깍" — 버튼이 꺼지고 노란 별이 튄다. 볼이 사라지며 새 알이 나타난다.
enum GraduationEffect {
    static let duration: TimeInterval = 3.5
    static let reducedDuration: TimeInterval = 1.1
    /// 볼이 놓이는 자리(칸 중심 원점, 칸 단위)와 지름.
    static let ballCenter = CGPoint(x: 0, y: 0.24)
    static let ballDiameter: Double = 0.4
    static let wobbleStarts: [TimeInterval] = [1.8, 2.15, 2.5]
    static let wobbleLength: TimeInterval = 0.22
    static let wobbleDegrees: Double = 18
    static let clickAt: TimeInterval = 2.8

    static func duration(reduceMotion: Bool) -> TimeInterval { reduceMotion ? reducedDuration : duration }

    struct Frame: Equatable {
        var ballScale: Double = 0
        var ballOpacity: Double = 0
        /// 쉬는 자리에서 아래로 내려간 정도(칸 단위, 음수 = 떠 있음).
        var ballDrop: Double = 0
        var ballOpen: Double = 0
        var ballTilt: Double = 0
        /// 흔들림 동안 버튼이 붉게 빛나는 정도.
        var buttonRed: Double = 0
        /// 딸깍 뒤 버튼이 꺼진 정도.
        var buttonDark: Double = 0
        /// 닫힐 때 이음매의 번쩍임.
        var closeFlash: Double = 0
        var monWhite: Double = 0
        var monRed: Double = 0
        var monScale: Double = 1
        /// 볼까지의 휘어진 길을 간 정도 0…1.
        var monPull: Double = 0
        var monOpacity: Double = 1
        /// 빨려 드는 붉은 빛줄기 0…1.
        var beam: Double = 0
        var eggOpacity: Double = 0
        var eggScale: Double = 1
    }

    /// 포켓몬 중심 → 볼 입구의 휘어진 길(이차 베지어). 칸 단위.
    static func pullPoint(_ u: Double) -> CGPoint {
        let p0 = CGPoint(x: 0, y: -0.02)
        let c = CGPoint(x: 0.42, y: -0.32)
        let p2 = CGPoint(x: ballCenter.x, y: ballCenter.y - ballDiameter * 0.18)
        let a = (1 - u) * (1 - u), b = 2 * (1 - u) * u, d = u * u
        return CGPoint(x: a * p0.x + b * c.x + d * p2.x, y: a * p0.y + b * c.y + d * p2.y)
    }

    static func frame(at t: TimeInterval, reduceMotion: Bool = false) -> Frame {
        var f = Frame()
        if reduceMotion {
            f.ballScale = 1
            f.ballOpacity = FX.smoothstep(0, 0.2, t) * (1 - FX.smoothstep(0.8, 1.1, t))
            f.monRed = FX.smoothstep(0.2, 0.5, t)
            f.monWhite = 0.4 * f.monRed
            f.monOpacity = 1 - FX.smoothstep(0.2, 0.7, t)
            f.eggOpacity = FX.smoothstep(0.8, 1.1, t)
            return f
        }
        f.ballScale = FX.easeOutBack(t / 0.25) * (1 - 0.4 * FX.smoothstep(3.15, 3.5, t))
        f.ballOpacity = FX.smoothstep(0, 0.08, t) * (1 - FX.smoothstep(3.15, 3.45, t))
        // 떠 있다가(-0.08) 닫힌 뒤 떨어져 한 번 튄다.
        if t < 1.3 {
            f.ballDrop = -0.08
        } else if t < 1.48 {
            f.ballDrop = -0.08 + 0.08 * FX.easeInCubic((t - 1.3) / 0.18)
        } else if t < 1.72 {
            let u = (t - 1.48) / 0.24
            f.ballDrop = -0.055 * sin(u * .pi)
        }
        f.ballOpen = FX.easeOutBack(FX.clamp01((t - 0.2) / 0.2), overshoot: 1.2) * (1 - FX.smoothstep(1.18, 1.28, t))
        f.closeFlash = t >= 1.22 ? max(0, 1 - (t - 1.22) / 0.25) : 0
        f.monWhite = FX.smoothstep(0.32, 0.45, t) * (1 - 0.45 * FX.smoothstep(0.5, 0.7, t))
        f.monRed = FX.smoothstep(0.5, 0.72, t)
        let pull = FX.clamp01((t - 0.72) / 0.48)
        f.monPull = FX.easeInCubic(pull) * 0.7 + pull * 0.3
        f.monScale = 1 - 0.95 * f.monPull
        f.monOpacity = t < 1.2 ? 1 : 0
        f.beam = FX.smoothstep(0.66, 0.78, t) * (1 - FX.smoothstep(1.12, 1.25, t))
        for start in wobbleStarts where t >= start && t <= start + wobbleLength {
            let u = (t - start) / wobbleLength
            f.ballTilt = wobbleDegrees * sin(u * 2 * .pi) * (1 - 0.3 * u)
            f.buttonRed = sin(u * .pi)
        }
        f.buttonDark = FX.smoothstep(clickAt, clickAt + 0.06, t)
        f.eggOpacity = FX.smoothstep(3.2, 3.45, t)
        f.eggScale = 0.85 + 0.15 * FX.easeOutBack((t - 3.2) / 0.3)
        return f
    }
}

/// 몬스터볼 — 구형 음영(방사 그라데이션), 반사광, 굵은 검은 띠, 흰 고리를 두른 버튼. `open` 만큼 위 덮개가
/// 뒤쪽 경첩을 축으로 젖혀지고 안쪽 빛이 보인다.
@MainActor
struct PokeBallView: View {
    let diameter: CGFloat
    var open: Double = 0
    var buttonRed: Double = 0
    var buttonDark: Double = 0
    var closeFlash: Double = 0

    var body: some View {
        let d = diameter
        let band = d * 0.12
        let outline = max(1, d * 0.055)
        ZStack {
            // 안쪽(열렸을 때만 보인다) — 빛이 새어 나오는 입구. 아랫부분 위에 얹는다(아래 ZStack 순서).
            EmptyView()
            // 아랫부분 + 아래쪽 띠.
            HalfBall(top: false)
                .fill(RadialGradient(colors: [Color.white, Color(red: 0.82, green: 0.83, blue: 0.88)],
                                     center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: d * 0.75))
                .overlay(HalfBall(top: false, bandFraction: 0.12).fill(Color(white: 0.08)))
                .overlay(HalfBall(top: false).stroke(Color(white: 0.08), lineWidth: outline))
            Ellipse()
                .fill(RadialGradient(colors: [Color.white, Color(red: 1, green: 0.55, blue: 0.5), Color(red: 0.45, green: 0.02, blue: 0.04)],
                                     center: .center, startRadius: 0, endRadius: d * 0.42))
                .frame(width: d * 0.9, height: d * 0.32)
                .shadow(color: Color(red: 1, green: 0.4, blue: 0.35).opacity(open), radius: d * 0.15)
                .opacity(open)
            // 위 덮개 — 뒤쪽 경첩으로 열린다.
            HalfBall(top: true)
                .fill(RadialGradient(colors: [Color(red: 1, green: 0.45, blue: 0.4), Color(red: 0.88, green: 0.1, blue: 0.13),
                                              Color(red: 0.5, green: 0.02, blue: 0.05)],
                                     center: UnitPoint(x: 0.32, y: 0.22), startRadius: 0, endRadius: d * 0.8))
                .overlay(HalfBall(top: true, bandFraction: 0.12).fill(Color(white: 0.08)))
                .overlay(HalfBall(top: true).stroke(Color(white: 0.08), lineWidth: outline))
                .overlay(alignment: .topLeading) {
                    // 반사광.
                    Ellipse().fill(Color.white.opacity(0.85))
                        .frame(width: d * 0.22, height: d * 0.12)
                        .rotationEffect(.degrees(-30))
                        .offset(x: d * 0.2, y: d * 0.13)
                        .blur(radius: d * 0.012)
                }
                // 앞에서 보면 뒤쪽 경첩으로 젖혀지는 덮개는 위로 들리며 짧아진다(뒤로 누운 만큼 앞면이 줄어든다).
                .scaleEffect(x: 1, y: 1 - 0.35 * open, anchor: .bottom)
                .rotationEffect(.degrees(-14 * open), anchor: UnitPoint(x: 0.1, y: 0.5))
                .offset(y: -d * 0.34 * open)
            // 버튼 — 이음매 앞쪽(열리면 아랫부분 쪽에 남는다).
            ZStack {
                Circle().fill(Color(white: 0.08)).frame(width: d * 0.36, height: d * 0.36)
                Circle().fill(Color.white).frame(width: d * 0.27, height: d * 0.27)
                Circle()
                    .fill(RadialGradient(colors: [Color.white, Color(white: 0.82)], center: UnitPoint(x: 0.35, y: 0.3),
                                         startRadius: 0, endRadius: d * 0.12))
                    .overlay(Circle().fill(Color(red: 1, green: 0.2, blue: 0.2)).opacity(buttonRed * 0.85))
                    .overlay(Circle().fill(Color(white: 0.35)).opacity(buttonDark * 0.75))
                    .overlay(Circle().stroke(Color(white: 0.3), lineWidth: max(0.6, d * 0.02)))
                    .frame(width: d * 0.17, height: d * 0.17)
                    .shadow(color: Color.red.opacity(buttonRed), radius: d * 0.12)
            }
            // 닫히는 순간 이음매가 번쩍.
            Capsule().fill(Color.white)
                .frame(width: d * 1.1, height: band * 1.4)
                .blur(radius: d * 0.05)
                .opacity(closeFlash)
        }
        .frame(width: d, height: d)
    }
}

/// 원의 위/아래 반쪽. `bandFraction` 이 있으면 이음매 쪽 띠(지름 대비 두께의 절반)만.
private struct HalfBall: Shape {
    let top: Bool
    var bandFraction: CGFloat? = nil
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        var full = Path()
        full.addArc(center: c, radius: r, startAngle: .degrees(top ? 180 : 0), endAngle: .degrees(top ? 360 : 180),
                    clockwise: false)
        full.closeSubpath()
        guard let band = bandFraction else { return full }
        let h = rect.height * band / 2
        let strip = Path(CGRect(x: rect.minX, y: top ? c.y - h : c.y, width: rect.width, height: h))
        return full.intersection(strip)
    }
}

/// 졸업 연출 한 순간. `pokemon`·`egg` 는 호출자가 그린다.
@MainActor
struct GraduationEffectView<Pokemon: View, Egg: View>: View {
    let elapsed: TimeInterval
    var size: CGFloat = 76
    var reduceMotion = false
    var layer: CelebrationLayer = .both
    @ViewBuilder var pokemon: Pokemon
    @ViewBuilder var egg: Egg

    var body: some View {
        let f = GraduationEffect.frame(at: elapsed, reduceMotion: reduceMotion)
        Layered(layer: layer, size: size) { sprite(f) } light: { light(f) }
    }

    @ViewBuilder
    private func sprite(_ f: GraduationEffect.Frame) -> some View {
        let ball = size * GraduationEffect.ballDiameter
        let rest = GraduationEffect.ballCenter
        let pos = GraduationEffect.pullPoint(f.monPull)
        ZStack {
            egg.scaleEffect(f.eggScale).opacity(f.eggOpacity)
            // 볼 그림자 — 볼이 떠 있으면 작고 옅다.
            Ellipse().fill(Color.black.opacity(0.28 * f.ballOpacity * (1 + f.ballDrop * 4)))
                .frame(width: ball * 0.85 * (1 + f.ballDrop * 2), height: ball * 0.2)
                .blur(radius: ball * 0.05)
                .offset(x: 0, y: size * (rest.y + GraduationEffect.ballDiameter * 0.5))
            if f.monOpacity > 0 {
                pokemon
                    // 흰 빛을 맞고(밝기) → 붉은 빛 실루엣(밝힌 뒤 빨강을 곱한다).
                    .brightness(max(f.monWhite, 0.45 * f.monRed))
                    .colorMultiply(Color(red: 1, green: 1 - 0.7 * f.monRed, blue: 1 - 0.7 * f.monRed))
                    .shadow(color: Color(red: 1, green: 0.25, blue: 0.2).opacity(f.monRed), radius: size * 0.06)
                    .scaleEffect(f.monScale)
                    .offset(x: size * pos.x, y: size * (pos.y + 0.02))
                    .opacity(f.monOpacity)
            }
            PokeBallView(diameter: ball, open: f.ballOpen, buttonRed: f.buttonRed, buttonDark: f.buttonDark,
                         closeFlash: f.closeFlash)
                .scaleEffect(f.ballScale)
                .rotationEffect(.degrees(f.ballTilt), anchor: .bottom)
                .offset(x: size * rest.x, y: size * (rest.y + f.ballDrop))
                .opacity(f.ballOpacity)
        }
    }

    private func light(_ f: GraduationEffect.Frame) -> some View {
        let t = elapsed
        let reduce = reduceMotion
        return Canvas { ctx, canvas in
            let s = FXSpace(size: canvas, unit: canvas.width / CelebrationFX.overflow)
            guard !reduce else { return }
            let red = Color(red: 1, green: 0.18, blue: 0.15)
            // 흰 빛이 포켓몬을 친다.
            if t > 0.3, t < 0.75 {
                let hit = FX.smoothstep(0.3, 0.42, t) * (1 - FX.smoothstep(0.5, 0.75, t))
                ctx.glow(s, x: 0, y: 0, radius: 0.6, color: .white, opacity: hit * 0.9)
            }
            // 붉은 에너지 실루엣의 번짐 + 빛줄기.
            if f.monOpacity > 0, f.monRed > 0 {
                let p = GraduationEffect.pullPoint(f.monPull)
                ctx.glow(s, x: p.x, y: p.y, radius: 0.45 * f.monScale + 0.08, color: red, opacity: f.monRed * 0.55)
            }
            if f.beam > 0 {
                // 붉은 빛의 띠 — 포켓몬 쪽이 굵고 볼 입구로 갈수록 가늘어진다(빨려 드는 방향이 보이게).
                let steps = 28
                let from = f.monPull
                let pts = (0...steps).map { i -> CGPoint in
                    let q = GraduationEffect.pullPoint(from + (1 - from) * Double(i) / Double(steps))
                    return s.point(q.x, q.y)
                }
                let bodyWidth = 0.08 + 0.28 * f.monScale
                ctx.drawLayer { layer in
                    layer.addFilter(.blur(radius: s.unit * 0.02))
                    for i in 0..<steps {
                        var seg = Path()
                        seg.move(to: pts[i]); seg.addLine(to: pts[i + 1])
                        let taper = 1 - Double(i) / Double(steps) * 0.75
                        let layers: [(Double, Color, Double)] = [(bodyWidth * taper, red, 0.35),
                                                                 (bodyWidth * 0.5 * taper, red, 0.7),
                                                                 (0.04 * taper, Color(red: 1, green: 0.78, blue: 0.74), 0.95)]
                        for (width, color, alpha) in layers {
                            var c = layer
                            c.opacity = f.beam * alpha
                            c.stroke(seg, with: .color(color), style: StrokeStyle(lineWidth: s.length(width), lineCap: .round))
                        }
                    }
                }
                // 빛줄기를 타고 흘러드는 입자.
                for i in 0..<10 {
                    let phase = (t * 2.2 + Double(i) / 10).truncatingRemainder(dividingBy: 1)
                    let u = f.monPull + (1 - f.monPull) * phase
                    let q = GraduationEffect.pullPoint(u)
                    ctx.glow(s, x: q.x, y: q.y, radius: 0.05, color: .white, opacity: f.beam * (1 - phase * 0.5))
                }
            }
            let ball = GraduationEffect.ballCenter
            if f.closeFlash > 0 {
                ctx.glow(s, x: ball.x, y: ball.y - 0.08, radius: 0.32, color: .white, opacity: f.closeFlash)
            }
            if f.buttonRed > 0 {
                ctx.glow(s, x: ball.x, y: ball.y, radius: 0.12, color: red, opacity: f.buttonRed * 0.7)
            }
            // 딸깍 — 볼 위로 노란 별이 튀고 작은 반짝이가 흩어진다.
            let ct = t - GraduationEffect.clickAt
            if ct >= 0 {
                let top = ball.y - GraduationEffect.ballDiameter * 0.55
                for star in FX.debris(seed: 5, count: 5, at: ct, speed: 1.5...1.9, spread: 0.95, gravity: 2.8,
                                      drag: 2.6, life: 0.62, origin: (ball.x, top), size: 0.13...0.16, shape: .star) {
                    ctx.star(s, star)
                }
                for spark in FX.burst(seed: 9, count: 6, at: ct - 0.05, reach: 0.32, life: 0.45, size: 0.05...0.08) {
                    var q = spark
                    q.y += top
                    ctx.sparkle(s, q, color: Color(red: 1, green: 0.9, blue: 0.4))
                }
            }
        }
    }
}

// MARK: - 메타몽 리빌

/// 위장체 → 메타몽 교체를 섬광이 덮고 작은 폭발과 함께 튀어나온다.
enum DittoRevealEffect {
    static let revealAt: TimeInterval = 0.18
    static let tail: TimeInterval = 0.85
    static let reducedTail: TimeInterval = 0.5

    static func duration(reduceMotion: Bool) -> TimeInterval { revealAt + (reduceMotion ? reducedTail : tail) }

    struct Frame: Equatable {
        var revealed = false
        var flash: Double = 0
        var popScale: Double = 1
        var sinceReveal: Double = -1
    }

    static func frame(at t: TimeInterval, reduceMotion: Bool = false) -> Frame {
        var f = Frame()
        f.revealed = t >= revealAt
        f.sinceReveal = t - revealAt
        guard f.revealed else {
            f.flash = 0.9 * FX.smoothstep(0, revealAt, t)
            return f
        }
        let tau = t - revealAt
        f.flash = 0.9 * pow(1 - FX.clamp01(tau / (reduceMotion ? reducedTail : tail * 0.7)), 2)
        f.popScale = reduceMotion ? 1 : FX.springPop(tau)
        return f
    }
}

@MainActor
struct DittoRevealEffectView<Disguise: View, Ditto: View>: View {
    let elapsed: TimeInterval
    var size: CGFloat = 76
    var reduceMotion = false
    var shiny = false
    var layer: CelebrationLayer = .both
    @ViewBuilder var disguise: Disguise
    @ViewBuilder var ditto: Ditto

    var body: some View {
        let f = DittoRevealEffect.frame(at: elapsed, reduceMotion: reduceMotion)
        Layered(layer: layer, size: size) {
            ZStack {
                if f.revealed {
                    ditto.scaleEffect(f.popScale, anchor: UnitPoint(x: 0.5, y: 0.8))
                } else {
                    disguise
                }
            }
        } light: {
            light(f)
        }
    }

    private func light(_ f: DittoRevealEffect.Frame) -> some View {
        let reduce = reduceMotion
        let shinyOn = shiny
        return Canvas { ctx, canvas in
            let s = FXSpace(size: canvas, unit: canvas.width / CelebrationFX.overflow)
            let pink = Color(red: 0.86, green: 0.55, blue: 0.98)
            if f.flash > 0 {
                let grow = f.revealed && !reduce ? FX.easeOutCubic(f.sinceReveal / 0.3) : 0
                ctx.glow(s, x: 0, y: 0, radius: 0.42 + 0.35 * grow, color: pink, opacity: f.flash * 0.7)
                ctx.glow(s, x: 0, y: 0, radius: 0.34 + 0.25 * grow, color: .white, opacity: f.flash)
            }
            guard f.revealed, !reduce else { return }
            for spark in FX.burst(seed: 23, count: 9, at: f.sinceReveal, reach: 0.7, life: 0.7) {
                ctx.sparkle(s, spark, color: pink)
            }
            // 🎭 — 칸 위로 튀어 올랐다 사라진다(예전 헤더 버스트를 빛 층으로 옮겼다 — 플로팅 펫에서도 보이게).
            let mt = f.sinceReveal - 0.05
            if mt > 0, mt < 0.85 {
                var c = ctx
                c.opacity = 1 - FX.smoothstep(0.6, 0.85, mt)
                let pop = FX.easeOutBack(mt / 0.25)
                let at = s.point(0, -0.58 - 0.08 * FX.easeOutCubic(mt / 0.85))
                c.translateBy(x: at.x, y: at.y)
                c.scaleBy(x: pop, y: pop)
                c.draw(Text("🎭").font(.system(size: s.unit * 0.34)), at: .zero)
            }
            if shinyOn {
                for i in 0..<3 {
                    let local = f.sinceReveal - 0.25 - Double(i) * 0.12
                    guard local > 0, local < 0.6 else { continue }
                    let pulse = sin(local / 0.6 * .pi)
                    ctx.sparkle(s, FX.Particle(x: 0.3, y: -0.3 + Double(i) * 0.1, size: 0.12 + 0.07 * pulse,
                                               opacity: pulse, shape: .sparkle),
                                color: Color(red: 0.55, green: 0.85, blue: 1))
                }
            }
        }
    }
}

// MARK: - 디스패처

/// 재생 중인 연출 하나를 그린다 — 헤더·플로팅 펫·렌더 하네스가 함께 쓴다. 스프라이트 뷰는 호출자가 연출마다
/// **한 번** 만들어 넘긴다(TimelineView 가 매 프레임 이 뷰를 다시 만들어도 SpriteView.init 이 돌지 않게).
@MainActor
struct CelebrationSequenceView: View {
    let kind: CelebrationPlayer.Kind
    let elapsed: TimeInterval
    var size: CGFloat = 76
    var reduceMotion = false
    var layer: CelebrationLayer = .both
    let sprites: [CelebrationPlayer.Sprite: AnyView]

    private func view(_ s: CelebrationPlayer.Sprite) -> AnyView { sprites[s] ?? AnyView(Color.clear) }

    var body: some View {
        switch kind {
        case .hatch(let profile, let egg, let reveal):
            HatchEffectView(profile: profile, elapsed: elapsed, size: size, reduceMotion: reduceMotion,
                            shiny: reveal.shiny, layer: layer) { view(egg) } hatchling: { view(reveal) }
        case .evolve(let from, let to):
            EvolutionEffectView(elapsed: elapsed, size: size, reduceMotion: reduceMotion, layer: layer) {
                view(from)
            } to: { view(to) }
        case .graduate(let mon, let egg):
            GraduationEffectView(elapsed: elapsed, size: size, reduceMotion: reduceMotion, layer: layer) {
                view(mon)
            } egg: { view(egg) }
        case .dittoReveal(let disguise, let ditto):
            DittoRevealEffectView(elapsed: elapsed, size: size, reduceMotion: reduceMotion, shiny: ditto.shiny,
                                  layer: layer) { view(disguise) } ditto: { view(ditto) }
        }
    }
}

extension CelebrationPlayer.Kind {
    /// 이 연출에 필요한 스프라이트들(뷰를 한 번씩만 만들기 위해).
    var sprites: [CelebrationPlayer.Sprite] {
        switch self {
        case .hatch(_, let egg, let reveal): [egg, reveal]
        case .evolve(let from, let to): [from, to]
        case .graduate(let mon, let egg): [mon, egg]
        case .dittoReveal(let disguise, let ditto): [disguise, ditto]
        }
    }
}
