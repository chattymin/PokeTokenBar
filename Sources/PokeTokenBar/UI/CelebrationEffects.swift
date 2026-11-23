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
    static let eggInset: Double = 0.78
    /// 터지기 직전 알이 부푸는 정도 — 커지면 등급색 윤곽이 칸 가장자리에 잘린다(실측: 0.07 에서 좌우가 평평해졌다).
    static let swell: Double = 0.04

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
        // 타입을 못 박아 두면 CI 의 Swift 6.1(Xcode 16.4) 타입 검사기가 시간 초과로 포기한다(실측).
        return (0..<p.wobbles).map { (i: Int) -> TimeInterval in
            let base: TimeInterval = lead + Double(i) * spacing
            let pause: TimeInterval = (i == p.wobbles - 1 && i > 0) ? p.pauseBeforeLast : 0
            return base + pause
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
        /// 깨지기 직전 알이 하얗게 달아오르는 정도(깜빡이다 1 에서 터진다) — 본가 부화의 흰 번쩍임.
        var eggWhite: Double = 0
        /// 막 나온 포켓몬의 흰 실루엣 → 본래 색.
        var hatchWhite: Double = 0
        /// 금이 생기는 순간 알이 움찔하는 정도(눌렸다 펴짐).
        var tap: Double = 0
    }

    static let crackGrowth: TimeInterval = 0.18
    static let tapLength: TimeInterval = 0.14

    /// 칸 좌표(0…1)의 알 위 한 점이 지금 프레임에서 놓이는 자리(칸 중심 원점, 칸 단위) — 알과 같은
    /// 크기·기울기 변환을 적용한다(금 사이로 새는 빛줄기를 빛 층에서 금에 붙이려고).
    static func eggPoint(_ p: CGPoint, scale: Double, tilt: Double) -> CGPoint {
        let pivot = CGPoint(x: 0, y: 0.42)   // rotationEffect 의 anchor (0.5, 0.92)
        let x = (Double(p.x) - 0.5) * scale - pivot.x, y = (Double(p.y) - 0.5) * scale - pivot.y
        let a = tilt * .pi / 180
        return CGPoint(x: pivot.x + x * cos(a) - y * sin(a), y: pivot.y + x * sin(a) + y * cos(a))
    }

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
        f.tap = crackTimes(p).map { at -> Double in
            let x = t - at
            return x < 0 || x > tapLength ? 0 : sin(x / tapLength * .pi)
        }.max() ?? 0
        let firstStart = wobbleStarts(p).first ?? 0
        if f.revealed {
            let fade = 1 - FX.smoothstep(reveal, reveal + tail * 0.7, t)
            f.glow = p.glow * fade
            // 광선은 깨지는 순간 빠르게 걷힌다 — 속도선·고리와 겹치면 화면이 어지럽다.
            f.rays = p.rays ? 1 - FX.smoothstep(reveal, reveal + 0.25, t) : 0
            f.hatchlingScale = FX.springPop(t - reveal)
            f.hatchWhite = 1 - FX.smoothstep(reveal + 0.03, reveal + 0.24, t)
        } else {
            f.glow = p.glow * pow(FX.smoothstep(firstStart, reveal, t), 1.4)
            f.rays = p.rays ? FX.smoothstep(firstStart + 0.3, reveal - 0.2, t) : 0
            let settle = 1 - (1 - eggInset) * FX.smoothstep(0, lead, t)
            f.eggScale = settle + swell * FX.smoothstep(reveal - buildUp, reveal, t)
            // 터지기 직전: 하얗게 달아오르며 빠르게 깜빡이다(주기 0.11초) 공개 순간 완전히 하얘진다.
            let heat = FX.smoothstep(reveal - buildUp - 0.12, reveal, t)
            f.eggWhite = pow(heat, 1.3) * (0.72 + 0.28 * cos((reveal - t) / 0.11 * 2 * .pi))
        }
        f.rayAngle = t * 40
        f.flash = flash(peak: p.flashPeak, reveal: reveal, fade: 0.35, at: t)
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
///
/// 그림 원칙(두 번의 "허접하다" 피드백 뒤): 빛·금·입자는 전부 도트 그림판(`PixelCanvas`)에 찍는다 — 스프라이트와
/// 같은 그림체가 돼야 게임 화면처럼 보인다. 칸을 덮는 섬광 원판은 쓰지 않는다. 대신 알 자체가 하얗게
/// 달아올랐다 터지고, 포켓몬은 흰 실루엣으로 튀어나온다.
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
                if f.revealed, !reduceMotion, f.sinceBreak < 0.7 { cap(f.sinceBreak) }
                burst(f)
            }
        }
    }

    private var line: CGFloat { size / 76 }

    /// 등급 표의 순위(0 = 커먼) — 흔들림 세기·속도선 굵기를 등급과 같이 키운다.
    private var tier: Double { Double(profile.rarity.sortRank) }

    /// 알 그림의 윗부분 — 튀어 오르며 돌아 옆으로 떨어진다.
    private func cap(_ bt: Double) -> some View {
        let rise = (1 - exp(-6 * bt)) / 6
        // 터진 직후엔 껍질도 아직 하얗게 달아 있다가 본래 색으로 식는다(알과 이어지게).
        return egg.brightness(1 - FX.smoothstep(0, 0.12, bt))
            .mask(PolylineShape(points: HatchEffect.shellMask(top: true), centered: true, closed: true))
            .scaleEffect(HatchEffect.eggInset + HatchEffect.swell)
            .frame(width: size, height: size)
            .rotationEffect(.degrees(-200 * bt), anchor: UnitPoint(x: 0.35, y: 0.45))
            .offset(x: size * 0.9 * bt, y: size * (-3.4 * rise + 2.4 * bt * bt))
            .opacity(1 - FX.smoothstep(0.5, 0.7, bt))
    }

    @ViewBuilder
    private func sprite(_ f: HatchEffect.Frame) -> some View {
        let tint = celebrationTint(profile.rarity)
        let shake = reduceMotion ? .zero : FX.shake(f.sinceBreak, amplitude: Double(size) * (0.025 + 0.012 * tier))
        ZStack {
            if f.revealed {
                // 알이 위아래로 쪼개진다 — 윗뚜껑은 튀어 오르며 날아가고, 아랫껍질은 잠깐 남았다 가라앉는다.
                // 포켓몬은 하얀 실루엣으로 튀어나와(늘었다 납작해지며) 본래 색으로 돌아온다.
                let st = reduceMotion ? 0 : FX.stretch(f.sinceBreak)
                hatchling
                    .brightness(f.hatchWhite)
                    .celebrationRim(tint, width: 1.6 * line * f.hatchWhite)
                    .scaleEffect(x: f.hatchlingScale * (1 - 0.6 * st), y: f.hatchlingScale * (1 + st),
                                 anchor: UnitPoint(x: 0.5, y: 0.85))
                if !reduceMotion, f.sinceBreak < 0.6 {
                    let bt = f.sinceBreak
                    egg.brightness(1 - FX.smoothstep(0, 0.12, bt))
                        .mask(PolylineShape(points: HatchEffect.shellMask(top: false), centered: true, closed: true))
                        .scaleEffect(HatchEffect.eggInset + HatchEffect.swell)
                        .offset(y: size * 0.18 * bt * bt * 4)
                        .opacity(1 - FX.smoothstep(0.08, 0.26, bt))
                }
            } else {
                ZStack {
                    egg.brightness(f.eggWhite)
                    cracks(f, tint: tint)
                }
                // 등급색 윤곽 — 번진 그림자 대신 알 모양 그대로의 또렷한 테두리가 차오른다.
                .celebrationRim(tint, width: 1.8 * line * f.glow)
                .scaleEffect(x: 1 + 0.05 * f.tap, y: 1 - 0.06 * f.tap, anchor: UnitPoint(x: 0.5, y: 0.92))
                .scaleEffect(f.eggScale)
                .rotationEffect(.degrees(f.tilt), anchor: UnitPoint(x: 0.5, y: 0.92))
            }
        }
        .offset(shake)
    }

    /// 금 — 알과 같이 기울도록 알 위에 겹친 도트 그림판. 커먼·언커먼은 한 셀 어두운 금 아래 밝은 결(깎인 느낌),
    /// 희귀 이상은 세 셀 어두운 틈 속에 등급색 빛과 흰 마디.
    private func cracks(_ f: HatchEffect.Frame, tint: Color) -> some View {
        let p = profile
        let progress = f.crackProgress
        let reduce = reduceMotion
        return PixelCanvas(box: size) { g in
            for k in 0..<min(p.cracks, HatchEffect.crackPaths.count) {
                let grown = progress.indices.contains(k) ? progress[k] : 0
                guard grown > 0 else { continue }
                let pts = HatchEffect.crackPaths[k].map { (Double($0.x) - 0.5, Double($0.y) - 0.5) }
                let alpha = reduce ? grown : 1, upTo = reduce ? 1 : grown
                if p.leaksLight {
                    g.polyline(pts, upTo: upTo, thickness: 3, color: EggPalette.outline, alpha: alpha)
                    g.polyline(pts, upTo: upTo, thickness: 1, color: tint, alpha: alpha)
                    for (x, y) in pts.dropFirst().dropLast() where upTo >= 1 {
                        g.plot(Int(g.cx(x).rounded(.down)), Int(g.cy(y).rounded(.down)), .white, alpha: alpha)
                    }
                } else {
                    let below = pts.map { ($0.0, $0.1 + g.cellLength) }
                    g.polyline(below, upTo: upTo, color: .white, alpha: alpha * 0.8)
                    g.polyline(pts, upTo: upTo, thickness: p.glow > 0 ? 2 : 1, color: EggPalette.outline, alpha: alpha)
                    if p.glow > 0 { g.polyline(pts, upTo: upTo, color: tint, alpha: alpha) }
                }
            }
        }
    }

    /// 알 뒤·둘레의 빛 — 후광, 전설의 광선, 금 사이로 새는 빛줄기, 피어오르는 금빛.
    private func light(_ f: HatchEffect.Frame) -> some View {
        let p = profile
        let tint = celebrationTint(p.rarity)
        let t = elapsed
        let reduce = reduceMotion
        return PixelCanvas(box: size) { g in
            if f.glow > 0, !f.revealed {
                g.halo(y: 0.03, inner: 0.4, outer: 0.78, color: tint, alpha: f.glow * 0.55)
            }
            if f.rays > 0, !reduce {
                HatchEffect.rays(&g, tint: tint, opacity: f.rays, angle: f.rayAngle)
            }
            if p.leaksLight, !f.revealed, !reduce {
                // 금 사이로 새는 빛 — 다 자란 금마다 바깥쪽으로 빛줄기가 뻗어 떨린다(등급색).
                let center = HatchEffect.eggPoint(CGPoint(x: 0.5, y: 0.55), scale: f.eggScale, tilt: f.tilt)
                for k in 0..<min(p.cracks, HatchEffect.crackPaths.count) {
                    let grown = f.crackProgress.indices.contains(k) ? f.crackProgress[k] : 0
                    guard grown > 0.3 else { continue }
                    let pts = HatchEffect.crackPaths[k]
                    for (j, idx) in [pts.count / 2, pts.count - 1].enumerated() {
                        let o = HatchEffect.eggPoint(pts[idx], scale: f.eggScale, tilt: f.tilt)
                        let angle = atan2(Double(o.y - center.y), Double(o.x - center.x)) + (j == 0 ? -0.25 : 0.2)
                        let flicker = 0.8 + 0.2 * sin(t * 23 + Double(k * 3 + j))
                        let len = (0.22 + 0.3 * f.glow) * flicker * FX.smoothstep(0.3, 1, grown)
                        g.beam(x: Double(o.x), y: Double(o.y), angle: angle, length: len,
                               width: 0.08 + 0.06 * f.glow, color: tint, alpha: 0.95 * flicker)
                    }
                }
            }
            if p.motes > 0, !reduce {
                for m in FX.risingMotes(seed: 31, count: p.motes, at: t, from: 0.4, until: p.revealAt + 0.4) {
                    g.sparkle(x: m.x, y: m.y, size: m.size * 1.8, color: Color(red: 1, green: 0.7, blue: 0.12),
                              opacity: m.opacity)
                }
            }
        }
    }

    /// 깨지는 순간 — 작고 뜨거운 심지, 사방으로 뻗는 속도선, 고리, 껍질 조각, 반짝이.
    private func burst(_ f: HatchEffect.Frame) -> some View {
        let p = profile
        let tint = celebrationTint(p.rarity)
        let reduce = reduceMotion
        let shinyOn = shiny
        let tierRank = tier
        return PixelCanvas(box: size) { g in
            if f.flash > 0 {
                // 칸을 덮는 원판이 아니라 알 크기만 한 뜨거운 심지(공개 뒤 살짝 커지며 꺼진다).
                let grow = f.revealed && !reduce ? FX.easeOutCubic(f.sinceBreak / 0.3) : 0
                g.glow(x: 0, y: 0.02, radius: 0.42 + 0.2 * grow, color: tint, alpha: f.flash * 0.8)
                g.glow(x: 0, y: 0.02, radius: 0.26 + 0.08 * grow, color: .white, alpha: f.flash)
            }
            guard f.revealed, !reduce else { return }
            let bt = f.sinceBreak
            let reach = p.burst / 2
            HatchEffect.speedLines(&g, seed: 41, count: p.sparkles + 4, progress: bt / 0.42, from: 0.44, reach: reach,
                                   thickness: tierRank >= 2 ? 2 : 1, color: tint)
            if bt < 0.5 {
                let u = bt / 0.5
                g.ring(radius: 0.46 + (reach - 0.5) * FX.easeOutCubic(u), width: 0.07 * (1 - u) + 0.02,
                       color: tint, alpha: 1 - u * u)
            }
            if tierRank >= 3, bt > 0.08, bt < 0.6 {
                let u = (bt - 0.08) / 0.52
                g.ring(radius: 0.44 + (reach * 0.8 - 0.44) * FX.easeOutCubic(u), width: 0.04 * (1 - u) + 0.02,
                       color: tint, alpha: 1 - u * u)
            }
            for (i, s) in FX.debris(seed: UInt64(11 + p.fragments), count: p.fragments, at: bt,
                                    speed: 1.1...2.2, spread: 1.45, gravity: 2.6, drag: 3.0, life: 0.95,
                                    origin: (0, -0.04), size: 0.08...0.14).enumerated() {
                g.shard(x: s.x, y: s.y, size: s.size, rotation: s.rotation, seed: i, opacity: s.opacity)
            }
            for s in FX.burst(seed: UInt64(53 + p.sparkles), count: p.sparkles, at: bt - 0.06,
                              reach: reach * 0.85, life: 0.95, size: 0.1...0.18, inner: 0.4) {
                g.sparkle(x: s.x, y: s.y, size: s.size, color: tint, opacity: s.opacity)
            }
            if shinyOn {
                // 이로치: 공개 0.35초 뒤 오른쪽 위에서 따로 반짝인다(✨ 자리).
                for i in 0..<4 {
                    let local = bt - 0.35 - Double(i) * 0.12
                    guard local > 0, local < 0.7 else { continue }
                    let pulse = sin(local / 0.7 * .pi)
                    g.sparkle(x: 0.28 + Double(i % 2) * 0.12, y: -0.32 + Double(i / 2) * 0.1, size: 0.16 + 0.1 * pulse,
                              color: Color(red: 0.35, green: 0.7, blue: 1), opacity: pulse)
                }
            }
        }
    }
}

extension HatchEffect {
    /// 전설의 광선 — 서로 반대로 도는 쐐기 두 벌(등급색 넓은 것, 금빛 가는 것). 알 자리(반경 0.36 안)는
    /// 비우고, 바깥으로 갈수록 디더링으로 옅어진다.
    static func rays(_ g: inout PixelGrid, tint: Color, opacity: Double, angle: Double) {
        let sets: [(count: Int, half: Double, turn: Double, color: Color, alpha: Double)] = [
            (12, 0.07, 1, tint, 0.65), (12, 0.028, -0.6, Color(red: 1, green: 0.88, blue: 0.45), 0.85)]
        let reach = Double(CelebrationFX.overflow) / 2
        let base = angle * .pi / 180
        for set in sets {
            let period = 2 * Double.pi / Double(set.count)
            let pale = PixelGrid.lighten(set.color, 0.45)   // 셀마다 색 변환을 돌리지 않게 밖에서 한 번
            g.fill(x0: -reach, y0: -reach, x1: reach, y1: reach) { x, y, _, _ in
                let r = (x * x + y * y).squareRoot()
                guard r > 0.36, r < reach else { return nil }
                var rel = (atan2(y, x) - set.turn * base).truncatingRemainder(dividingBy: period)
                if rel < 0 { rel += period }
                guard min(rel, period - rel) <= set.half else { return nil }
                // 단색 쐐기 — 안쪽 본색, 바깥 옅은 색. 세기가 약하면 쐐기가 짧아진다. 끝 한 뼘만 바둑판.
                let end = 0.44 + (reach * 0.95 - 0.44) * opacity * set.alpha
                guard r < end else { return nil }
                let color = r < 0.44 + (end - 0.44) * 0.55 ? set.color : pale
                return (color, r > end - 0.06 ? 0.5 : 1)
            }
        }
    }

    /// 중심에서 사방으로 뻗는 도트 속도선 — 머리는 감속하며 바깥으로, 꼬리는 따라붙어 짧아진다. 머리는 흰 셀.
    static func speedLines(_ g: inout PixelGrid, seed: UInt64, count: Int, progress u: Double, from inner: Double,
                           reach: Double, thickness: Int, color: Color) {
        guard u >= 0, u < 0.92 else { return }
        var rng = CelebrationFX.Random(seed: seed)
        let pale = PixelGrid.lighten(color, 0.45)
        for i in 0..<count {
            let a = Double(i) / Double(count) * 2 * .pi + rng.range(-0.18, 0.18)
            let len = rng.range(0.6, 1)
            let head = inner + (reach - inner) * len * FX.easeOutCubic(u * 1.15)
            let tail = inner + (head - inner) * (0.2 + 0.7 * u)
            // 단색 마디(옅은 꼬리 → 본색 → 흰 머리) — 디더링한 꼬리는 점선처럼 끊겨 보였다.
            let mid = tail + (head - tail) * 0.45, tip = max(tail, head - g.cellLength * 2)
            let width = u > 0.55 ? 1 : thickness
            g.line(tail * cos(a), tail * sin(a), mid * cos(a), mid * sin(a), thickness: width, color: pale)
            g.line(mid * cos(a), mid * sin(a), head * cos(a), head * sin(a), thickness: width, color: color)
            g.line(tip * cos(a), tip * sin(a), head * cos(a), head * sin(a), thickness: width, color: .white)
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
        // 실루엣이 숨 쉬듯 줄었다 커진다 — 가장 작아지는 순간(mix 0.5)에 옛↔새가 바뀐다. 그리는 쪽은
        // mix 를 날카롭게 잘라 흐물거리는 교차 페이드 대신 "탁" 바뀌게 한다(본가 BW 처럼).
        let breathe = t >= whitenEnd && t < alternateEnd ? 0.8 + 0.2 * abs(cos(2 * .pi * cycles(at: t))) : 1
        f.oldScale = breathe
        f.newScale = breathe
        f.gather = FX.smoothstep(alternateEnd - 0.4, reveal, t)
        f.flash = FX.smoothstep(alternateEnd, reveal, t)
        return f
    }
}

/// 진화 연출 한 순간. `from`·`to` 는 진화 전·후 스프라이트.
///
/// 두 스프라이트는 **항상 둘 다** 그리고 불투명도로만 고른다 — `if` 로 넣고 빼면 바뀔 때마다 SpriteView 가
/// 새로 만들어져(상태 초기화·GIF 재로딩) 깜빡일 수 있다.
@MainActor
struct EvolutionEffectView<From: View, To: View>: View {
    let elapsed: TimeInterval
    var size: CGFloat = 76
    var reduceMotion = false
    var layer: CelebrationLayer = .both
    @ViewBuilder var from: From
    @ViewBuilder var to: To

    static var rimColor: Color { Color(red: 0.42, green: 0.72, blue: 1) }

    var body: some View {
        let f = EvolutionEffect.frame(at: elapsed, reduceMotion: reduceMotion)
        Layered(layer: layer, size: size) { sprite(f) } light: { light(f) }
    }

    @ViewBuilder
    private func sprite(_ f: EvolutionEffect.Frame) -> some View {
        let line = size / 76
        // 움직임을 줄이면 부드러운 교차 페이드, 아니면 mix 0.5 근처에서 날카롭게 바뀐다.
        let swap = f.revealed ? 1 : (reduceMotion ? f.mix : FX.smoothstep(0.44, 0.56, f.mix))
        let st = reduceMotion || !f.revealed ? 0 : FX.stretch(f.sinceReveal)
        let shake = reduceMotion ? .zero : FX.shake(f.sinceReveal, amplitude: Double(size) * 0.03)
        ZStack {
            // 어두워진 무대 — 짙은 밤의 원판, 가장자리만 바둑판으로 풀린다(도트 그림판 — 매끈한 그라데이션
            // 가장자리는 도트 연출 사이에서 혼자 튀었다). 헤더에선 무대에, 플로팅 펫에선 펫 둘레에 깔린다.
            // 예전엔 헤더 전체에 반투명 남색 카드를 덮어 밝은 팝오버 위에서 탁한 회색 판으로 보였다.
            PixelCanvas(box: size) { g in
                let night = Color(red: 0.05, green: 0.07, blue: 0.19)
                g.fill(x0: -0.74, y0: -0.74, x1: 0.74, y1: 0.74) { x, y, _, _ in
                    let r = (x * x + y * y).squareRoot()
                    return r < 0.6 ? (night, 1) : (r < 0.67 ? (night, 0.5) : (r < 0.73 ? (night, 0.25) : nil))
                }
            }
            .frame(width: size * 1.5, height: size * 1.5)
            .opacity(f.dim)
            // brightness(1) 은 알파를 지키고 색만 하얗게 민다 → 스프라이트 모양 그대로의 흰 실루엣 + 푸른 윤곽.
            ZStack {
                from.brightness(f.whiteness).scaleEffect(f.oldScale).opacity(1 - swap)
                to.brightness(f.whiteness).scaleEffect(f.revealed ? 1 : f.newScale).opacity(swap)
            }
            .celebrationRim(Self.rimColor, width: 1.8 * line * f.whiteness)
            .scaleEffect(x: f.popScale * (1 - 0.6 * st), y: f.popScale * (1 + st), anchor: UnitPoint(x: 0.5, y: 0.85))
        }
        .offset(shake)
    }

    private func light(_ f: EvolutionEffect.Frame) -> some View {
        let t = elapsed
        let reduce = reduceMotion
        return PixelCanvas(box: size) { g in
            let pale = Self.rimColor
            let gold = Color(red: 1, green: 0.78, blue: 0.2)
            if !reduce {
                // 소용돌이치며 모여드는 빛 — 바깥쪽으로 꼬리를 끄는 도트 알갱이(머리는 흰 셀).
                for m in FX.converging(seed: 7, count: 30, at: t, from: 0.05, until: 1.9, radius: 0.78) {
                    let r = (m.x * m.x + m.y * m.y).squareRoot()
                    let theta = atan2(m.y, m.x) - 0.22
                    let tail = min(1.04, r * 1.4 + 0.04)
                    guard m.opacity > 0.3 else { continue }
                    // 단색 꼬리 + 흰 머리(디더링한 꼬리는 끊긴 점선이 됐다). 꼬리 길이로 세기를 보인다.
                    let tr = r + (tail - r) * m.opacity
                    g.line(tr * cos(theta), tr * sin(theta), m.x, m.y, color: pale)
                    g.plot(Int(g.cx(m.x).rounded(.down)), Int(g.cy(m.y).rounded(.down)), .white)
                }
                if f.gather > 0 {
                    g.glow(x: 0, y: 0, radius: 0.3 + 0.2 * f.gather, color: pale, alpha: f.gather * 0.8)
                }
            }
            if f.flash > 0 {
                let grow = f.revealed && !reduce ? FX.easeOutCubic(f.sinceReveal / 0.3) : 0
                g.glow(x: 0, y: 0, radius: 0.46 + 0.2 * grow, color: pale, alpha: f.flash * 0.85)
                g.glow(x: 0, y: 0, radius: 0.3 + 0.1 * grow, color: .white, alpha: f.flash)
            }
            guard f.revealed, !reduce else { return }
            let rt = f.sinceReveal
            HatchEffect.speedLines(&g, seed: 29, count: 20, progress: rt / 0.45, from: 0.36, reach: 1.02,
                                   thickness: 2, color: pale)
            if rt < 0.5 {
                let u = rt / 0.5
                g.ring(radius: 0.4 + 0.58 * FX.easeOutCubic(u), width: 0.07 * (1 - u) + 0.02, color: pale, alpha: 1 - u * u)
            }
            if rt > 0.1, rt < 0.6 {
                let u = (rt - 0.1) / 0.5
                g.ring(radius: 0.36 + 0.42 * FX.easeOutCubic(u), width: 0.04 * (1 - u) + 0.02, color: gold,
                       alpha: 1 - u * u)
            }
            for (i, s) in FX.burst(seed: 19, count: 16, at: rt - 0.06, reach: 0.9, life: 0.8, size: 0.1...0.17,
                                   inner: 0.36).enumerated() {
                g.sparkle(x: s.x, y: s.y, size: s.size, color: i.isMultiple(of: 2) ? gold : pale, opacity: s.opacity)
            }
        }
    }
}

// MARK: - 졸업 (몬스터볼 회수)

/// 본가의 포획·회수 연출: 몬스터볼이 날아와 포켓몬 머리 위에 떠서 덮개가 열리고, 빛을 맞은 포켓몬이 붉은 빛
/// 실루엣이 되어 휘어진 빛줄기를 타고 볼 속으로 빨려 든다("슈욱"). 볼이 닫히며 번쩍, 바닥으로 떨어져 한 번
/// 튀고, 뜸을 두고 세 번 흔들리며(버튼이 붉게 깜빡) "딸깍" — 버튼이 꺼지고 노란 별이 튄다. 볼이 사라지며 새 알.
///
/// 예전엔 볼이 처음부터 포켓몬 발치에 겹쳐 있어 무엇이 일어나는지 안 읽혔다(사용자: "실제 포켓몬 안 봤어?").
/// 볼은 빛 층에 그린다 — 칸 밖에서 날아 들어오고, 열린 덮개가 헤더 칸에 잘리지 않게.
enum GraduationEffect {
    static let duration: TimeInterval = 3.5
    static let reducedDuration: TimeInterval = 1.1
    /// 볼이 바닥에 놓이는 자리(칸 중심 원점, 칸 단위)와 지름.
    static let ballCenter = CGPoint(x: 0, y: 0.27)
    static let ballDiameter: Double = 0.38
    /// 날아온 볼이 떠서 열리는 높이(포켓몬 머리 위, 칸 단위).
    static let hoverY: Double = -0.34
    static let throwLength: TimeInterval = 0.3
    static let throwFrom = CGPoint(x: 0.98, y: -0.95)
    static let wobbleStarts: [TimeInterval] = [1.8, 2.15, 2.5]
    static let wobbleLength: TimeInterval = 0.22
    static let wobbleDegrees: Double = 18
    static let clickAt: TimeInterval = 2.8

    static func duration(reduceMotion: Bool) -> TimeInterval { reduceMotion ? reducedDuration : duration }

    struct Frame: Equatable {
        var ballScale: Double = 0
        var ballOpacity: Double = 0
        /// 볼의 가로 자리(칸 단위, 날아오는 동안만 0 이 아니다).
        var ballX: Double = 0
        /// 바닥 자리(`ballCenter`)에서 아래로 내려간 정도(칸 단위, 음수 = 떠 있음).
        var ballDrop: Double = 0
        /// 날아오며 도는 각(도).
        var ballSpin: Double = 0
        var ballOpen: Double = 0
        var ballTilt: Double = 0
        /// 흔들림 동안 버튼이 붉게 빛나는 정도.
        var buttonRed: Double = 0
        /// 딸깍 뒤 버튼이 꺼진 정도.
        var buttonDark: Double = 0
        /// 닫힐 때 이음매의 번쩍임.
        var closeFlash: Double = 0
        /// 열린 볼에서 포켓몬에게 쏟아지는 빛.
        var lightCone: Double = 0
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

    /// 포켓몬 중심 → 떠 있는 볼 입구의 휘어진 길(이차 베지어). 칸 단위.
    static func pullPoint(_ u: Double) -> CGPoint {
        let p0 = CGPoint(x: 0, y: 0)
        let c = CGPoint(x: 0.36, y: -0.04)
        let p2 = CGPoint(x: 0, y: hoverY + ballDiameter * 0.05)
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
        f.ballScale = 1 - 0.4 * FX.smoothstep(3.15, 3.5, t)
        f.ballOpacity = FX.smoothstep(0, 0.05, t) * (1 - FX.smoothstep(3.15, 3.45, t))
        let hover = hoverY - Double(ballCenter.y)
        if t < throwLength {
            // 오른쪽 위 칸 밖에서 포물선을 그리며 돌아 날아온다(도착하며 감속).
            let u = 1 - pow(1 - t / throwLength, 2)
            f.ballX = Double(throwFrom.x) * (1 - u)
            let y = Double(throwFrom.y) + (hoverY - Double(throwFrom.y)) * u - 0.25 * sin(.pi * u)
            f.ballDrop = y - Double(ballCenter.y)
            f.ballSpin = -720 * (1 - u)
        } else if t < 1.3 {
            // 포켓몬에게 맞고 살짝 튕겨 올랐다 머리 위에 뜬다.
            let bob = t < 0.46 ? -0.04 * sin(.pi * (t - throwLength) / 0.16) : 0
            f.ballDrop = hover + bob
        } else if t < 1.48 {
            let u = (t - 1.3) / 0.18
            f.ballDrop = hover * (1 - u * u)   // 중력처럼 점점 빨라지며 떨어진다
        } else if t < 1.72 {
            let u = (t - 1.48) / 0.24
            f.ballDrop = -0.06 * sin(u * .pi)
        }
        f.ballOpen = FX.easeOutBack(FX.clamp01((t - 0.3) / 0.14), overshoot: 1.2) * (1 - FX.smoothstep(1.18, 1.28, t))
        f.closeFlash = t >= 1.22 ? max(0, 1 - (t - 1.22) / 0.25) : 0
        f.lightCone = FX.smoothstep(0.32, 0.4, t) * (1 - FX.smoothstep(0.6, 0.78, t))
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

/// 졸업 연출 한 순간. `pokemon`·`egg` 는 호출자가 그린다.
@MainActor
struct GraduationEffectView<Pokemon: View, Egg: View>: View {
    let elapsed: TimeInterval
    var size: CGFloat = 76
    var reduceMotion = false
    var layer: CelebrationLayer = .both
    @ViewBuilder var pokemon: Pokemon
    @ViewBuilder var egg: Egg

    private static var red: Color { Color(red: 1, green: 0.16, blue: 0.14) }

    var body: some View {
        let f = GraduationEffect.frame(at: elapsed, reduceMotion: reduceMotion)
        Layered(layer: layer, size: size) { sprite(f) } light: { light(f) }
    }

    @ViewBuilder
    private func sprite(_ f: GraduationEffect.Frame) -> some View {
        let pos = GraduationEffect.pullPoint(f.monPull)
        ZStack {
            egg.scaleEffect(f.eggScale).opacity(f.eggOpacity)
            pokemon
                // 빛을 맞고(밝기) → 붉은 빛 실루엣(밝힌 뒤 빨강을 곱한다) + 또렷한 붉은 윤곽.
                .brightness(max(f.monWhite, 0.5 * f.monRed))
                .colorMultiply(Color(red: 1, green: 1 - 0.75 * f.monRed, blue: 1 - 0.75 * f.monRed))
                .celebrationRim(Self.red, width: CGFloat(1.6 * f.monRed) * size / 76)   // CGFloat·Double 섞으면 Swift 6.1 이 모호하다고 거부
                .scaleEffect(f.monScale)
                .offset(x: size * pos.x, y: size * pos.y)
                .opacity(f.monOpacity)
        }
    }

    /// 빛 층 — 바닥 그림자, 쏟아지는 빛, 붉은 빛줄기, 도트 몬스터볼, 닫힘 번쩍임, 딸깍 별. 볼까지 전부 한
    /// 도트 그림판에 찍는다(벡터 볼은 도트 포켓몬 옆에서 혼자 매끈해 떠 보였다).
    private func light(_ f: GraduationEffect.Frame) -> some View {
        let t = elapsed
        let reduce = reduceMotion
        return PixelCanvas(box: size) { g in
            let red = Self.red
            let ballY = Double(GraduationEffect.ballCenter.y) + f.ballDrop
            let ground = Double(GraduationEffect.ballCenter.y) + GraduationEffect.ballDiameter * 0.5
            // 바닥 그림자 — 볼이 높이 떠 있을수록 작고 옅다(디더링된 검은 타원).
            let height = max(0, -f.ballDrop)
            // 높이 뜬 볼의 그림자는 몇 셀짜리 점 두 개로만 남아 지저분했다 — 내려오고 나서만 그린다.
            if f.ballOpacity > 0, f.ballX < 0.3, height < 0.3 {
                let w = GraduationEffect.ballDiameter * 0.42 * (1 - 0.5 * min(1, height / 0.6))
                g.ellipse(x: f.ballX, y: ground, rx: w, ry: w * 0.24, color: Color(white: 0.15),
                          alpha: f.ballOpacity * 0.45 * (1 - 0.6 * min(1, height / 0.6)))
            }
            if !reduce, f.lightCone > 0 {
                // 열린 볼에서 포켓몬에게 쏟아지는 빛의 원뿔(아래로 갈수록 디더링으로 옅어진다).
                let top = GraduationEffect.hoverY + 0.02, bottom = 0.42
                g.polygon([(-0.1, top), (0.1, top), (0.42, bottom), (-0.42, bottom)],
                          color: Color(red: 1, green: 0.93, blue: 0.75), alpha: f.lightCone * 0.85) { _, y in
                    1 - (y - top) / (bottom - top)
                }
            }
            if !reduce, f.monRed > 0, f.monOpacity > 0 {
                for s in FX.burst(seed: 77, count: 8, at: t - 0.5, reach: 0.5, life: 0.5, size: 0.07...0.11) {
                    g.sparkle(x: s.x, y: s.y, size: s.size, color: red, opacity: s.opacity)
                }
            }
            if !reduce, f.beam > 0 {
                // 붉은 빛의 띠 — 포켓몬 쪽이 굵고 볼 입구로 갈수록 가늘어진다. 원을 촘촘히 찍어 띠를 만든다.
                let from = f.monPull
                let steps = 40
                let bodyWidth = 0.06 + 0.26 * f.monScale
                for (scale, color) in [(1.0, red), (0.45, Color(red: 1, green: 0.55, blue: 0.5)),
                                       (0.16, Color.white)] {
                    for i in 0...steps {
                        let u = Double(i) / Double(steps)
                        let q = GraduationEffect.pullPoint(from + (1 - from) * u)
                        let w = (bodyWidth + (0.035 - bodyWidth) * u) * scale / 2
                        g.ellipse(x: Double(q.x), y: Double(q.y), rx: max(w, g.cellLength * 0.5),
                                  ry: max(w, g.cellLength * 0.5), color: color, alpha: f.beam)
                    }
                }
                // 빛줄기를 타고 흘러드는 흰 알갱이.
                for i in 0..<9 {
                    let phase = (t * 2.4 + Double(i) / 9).truncatingRemainder(dividingBy: 1)
                    let u = from + (1 - from) * phase
                    let q = GraduationEffect.pullPoint(u), tail = GraduationEffect.pullPoint(max(from, u - 0.1))
                    g.line(Double(tail.x), Double(tail.y), Double(q.x), Double(q.y), color: .white,
                           alpha0: 0.3 * f.beam, alpha1: f.beam)
                }
            }
            if !reduce, f.buttonRed > 0 {
                g.glow(x: f.ballX, y: ballY, radius: 0.16, color: red, alpha: f.buttonRed * 0.9)
            }
            g.pokeBall(PixelGrid.Ball(x: f.ballX, y: ballY, diameter: GraduationEffect.ballDiameter * f.ballScale,
                                      spin: f.ballSpin, tilt: f.ballTilt, open: f.ballOpen, buttonRed: f.buttonRed,
                                      buttonDark: f.buttonDark, flash: f.closeFlash, alpha: f.ballOpacity))
            guard !reduce else { return }
            if f.closeFlash > 0 {
                let u = 1 - f.closeFlash
                g.ring(x: f.ballX, y: ballY, radius: 0.24 + 0.3 * FX.easeOutCubic(u), width: 0.05 * (1 - u) + 0.02,
                       color: red, alpha: f.closeFlash)
            }
            // 딸깍 — 볼 위로 노란 별 셋이 튀고 작은 반짝이가 흩어진다.
            let ct = t - GraduationEffect.clickAt
            guard ct >= 0 else { return }
            let top = ballY - GraduationEffect.ballDiameter * 0.55
            if ct < 0.3 {
                g.ring(x: f.ballX, y: ballY, radius: 0.24 + 0.2 * FX.easeOutCubic(ct / 0.3), width: 0.025,
                       color: Color(red: 1, green: 0.78, blue: 0.15), alpha: 1 - ct / 0.3)
            }
            for s in FX.debris(seed: 5, count: 3, at: ct, speed: 1.6...1.9, spread: 0.8, gravity: 2.6,
                               drag: 2.6, life: 0.7, origin: (f.ballX, top), size: 0.17...0.2, shape: .star) {
                g.star(x: s.x, y: s.y, size: s.size, rotation: s.rotation * 0.3, opacity: s.opacity)
            }
            for s in FX.burst(seed: 9, count: 6, at: ct - 0.05, reach: 0.32, life: 0.45, size: 0.07...0.1) {
                g.sparkle(x: s.x, y: s.y + top, size: s.size, color: Color(red: 1, green: 0.72, blue: 0.1),
                          opacity: s.opacity)
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
        return ZStack {
            PixelCanvas(box: size) { g in
                let pink = Color(red: 0.8, green: 0.45, blue: 0.95)
                if f.flash > 0 {
                    let grow = f.revealed && !reduce ? FX.easeOutCubic(f.sinceReveal / 0.3) : 0
                    g.glow(x: 0, y: 0, radius: 0.42 + 0.35 * grow, color: pink, alpha: f.flash * 0.8)
                    g.glow(x: 0, y: 0, radius: 0.3 + 0.2 * grow, color: .white, alpha: f.flash)
                }
                guard f.revealed, !reduce else { return }
                if f.sinceReveal < 0.45 {
                    let u = f.sinceReveal / 0.45
                    g.ring(radius: 0.38 + 0.4 * FX.easeOutCubic(u), width: 0.05 * (1 - u) + 0.02, color: pink,
                           alpha: 1 - u * u)
                }
                for s in FX.burst(seed: 23, count: 9, at: f.sinceReveal, reach: 0.7, life: 0.7, inner: 0.3) {
                    g.sparkle(x: s.x, y: s.y, size: s.size * 1.3, color: pink, opacity: s.opacity)
                }
                if shinyOn {
                    for i in 0..<3 {
                        let local = f.sinceReveal - 0.25 - Double(i) * 0.12
                        guard local > 0, local < 0.6 else { continue }
                        let pulse = sin(local / 0.6 * .pi)
                        g.sparkle(x: 0.3, y: -0.3 + Double(i) * 0.1, size: 0.14 + 0.08 * pulse,
                                  color: Color(red: 0.35, green: 0.7, blue: 1), opacity: pulse)
                    }
                }
            }
            // 🎭 — 칸 위로 튀어 올랐다 사라진다(이모지는 도트로 못 그리니 따로 얹는다).
            Canvas { ctx, canvas in
                let mt = f.sinceReveal - 0.05
                guard f.revealed, !reduce, mt > 0, mt < 0.85 else { return }
                let unit = canvas.width / CelebrationFX.overflow
                var c = ctx
                c.opacity = 1 - FX.smoothstep(0.6, 0.85, mt)
                let pop = FX.easeOutBack(mt / 0.25)
                c.translateBy(x: canvas.width / 2, y: canvas.height / 2 + unit * (-0.58 - 0.08 * FX.easeOutCubic(mt / 0.85)))
                c.scaleBy(x: pop, y: pop)
                c.draw(Text("🎭").font(.system(size: unit * 0.34)), at: .zero)
            }
            .allowsHitTesting(false)
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
