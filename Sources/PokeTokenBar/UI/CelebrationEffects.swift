import SwiftUI

// 홈 헤더 스프라이트 칸의 두 연출 — 등급별 알 깨기(부화)와 몬스터볼 회수(졸업).
//
// 둘 다 "경과 시간의 순수 함수"다: 타이밍 표(`profile`·`frame(at:)`)와 그 값을 그리는 뷰가 분리돼 있어,
// 앱은 `TimelineView(.animation)` 으로 시간을 흘려 넣고 테스트는 임의의 순간을 결정적으로 그린다.
// 그림은 전부 SwiftUI 도형·그라데이션이다 — 저장소에 포켓몬 에셋을 커밋하지 않는 규칙 때문에
// 금 간 알·몬스터볼 이미지를 따로 두지 않는다(알과 포켓몬 스프라이트는 호출자가 넘긴다).

private func clamp01(_ x: Double) -> Double { min(1, max(0, x)) }
/// a→b 구간에서 0→1 로 부드럽게(바깥은 0/1 고정).
private func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
    guard b > a else { return x >= b ? 1 : 0 }
    let t = clamp01((x - a) / (b - a))
    return t * t * (3 - 2 * t)
}

// MARK: - 부화 (등급별 알 깨기)

/// 알이 깨지는 모습만 보고 등급을 맞힐 수 있게 하는 등급별 연출 표.
///
/// 플레이어가 학습할 수 있도록 **등급이 오를수록 모든 신호가 단조롭게 커진다**(흔들림 횟수·길이·금·빛·
/// 섬광 색). 이로치는 여기 넣지 않는다 — 공개 뒤의 ✨ 버스트로 따로 놀라게 한다.
enum HatchEffect {
    struct Profile: Equatable, Sendable {
        let rarity: Rarity
        /// 알이 흔들리는 횟수(등급 신호의 중심).
        let wobbles: Int
        /// 금 가는 구간의 길이 — 이 순간 섬광이 최고조가 되고 그 밑에서 포켓몬이 나타난다.
        let revealAt: TimeInterval
        /// 마지막(가장 센) 흔들림의 최대 기울기. 앞의 흔들림은 이보다 약하게 점점 세진다.
        let wobbleDegrees: Double
        /// 공개 직전까지 생기는 금의 개수(`crackPaths` 의 앞에서부터).
        let cracks: Int
        /// 알 주위 등급색 후광의 세기(0 = 없음).
        let glow: Double
        /// 금 사이로 등급색 빛이 샌다(희귀 이상) — 아니면 어두운 금만 그린다.
        let leaksLight: Bool
        /// 알 뒤에서 회전하는 빛줄기(전설만).
        let rays: Bool
        /// 마지막 흔들림 앞의 뜸 — 전설의 "숨 고르기".
        let pauseBeforeLast: TimeInterval
        /// 섬광의 등급색 비율(0 = 흰 섬광).
        let flashTint: Double
        /// 공개 순간 섬광의 불투명도.
        let flashPeak: Double

        /// 공개 뒤 섬광이 걷히고 포켓몬이 튀어나오는 꼬리까지 포함한 전체 길이.
        var duration: TimeInterval { revealAt + HatchEffect.tail }
    }

    /// 공개 뒤 꼬리(섬광 페이드 + 스프링 팝).
    static let tail: TimeInterval = 0.8
    /// 흔들림 한 번의 길이.
    static let wobbleLength: TimeInterval = 0.36
    /// 첫 흔들림 전 뜸.
    static let lead: TimeInterval = 0.12
    /// 마지막 흔들림이 끝난 뒤 섬광까지 남기는 뜸(빛이 차오르는 구간).
    static let buildUp: TimeInterval = 0.2
    /// 동작 줄이기: 흔들림·빛줄기 없이 등급색 후광과 섬광만 짧게.
    static let reducedRevealAt: TimeInterval = 0.55
    static let reducedTail: TimeInterval = 0.5

    static func profile(for rarity: Rarity) -> Profile {
        switch rarity {
        case .common:
            Profile(rarity: rarity, wobbles: 1, revealAt: 1.0, wobbleDegrees: 7, cracks: 1, glow: 0,
                    leaksLight: false, rays: false, pauseBeforeLast: 0, flashTint: 0, flashPeak: 0.85)
        case .uncommon:
            Profile(rarity: rarity, wobbles: 2, revealAt: 1.5, wobbleDegrees: 9, cracks: 3, glow: 0.55,
                    leaksLight: false, rays: false, pauseBeforeLast: 0, flashTint: 0, flashPeak: 0.9)
        case .rare:
            Profile(rarity: rarity, wobbles: 3, revealAt: 2.2, wobbleDegrees: 12, cracks: 4, glow: 0.75,
                    leaksLight: true, rays: false, pauseBeforeLast: 0, flashTint: 0.45, flashPeak: 0.95)
        case .legendary:
            Profile(rarity: rarity, wobbles: 4, revealAt: 3.0, wobbleDegrees: 15, cracks: 6, glow: 1,
                    leaksLight: true, rays: true, pauseBeforeLast: 0.55, flashTint: 0.7, flashPeak: 1)
        }
    }

    static func revealTime(_ p: Profile, reduceMotion: Bool) -> TimeInterval {
        reduceMotion ? reducedRevealAt : p.revealAt
    }

    static func duration(_ p: Profile, reduceMotion: Bool) -> TimeInterval {
        reduceMotion ? reducedRevealAt + reducedTail : p.duration
    }

    /// 흔들림 시작 시각들. 첫 흔들림은 `lead` 에, 마지막은 공개 `buildUp` 전에 끝나도록 고르게 편다.
    /// 전설은 마지막 앞에 뜸을 둔다(그만큼 앞의 간격이 좁아진다).
    static func wobbleStarts(_ p: Profile) -> [TimeInterval] {
        let window = max(0, p.revealAt - buildUp - lead - wobbleLength - p.pauseBeforeLast)
        let spacing = p.wobbles > 1 ? window / Double(p.wobbles - 1) : 0
        return (0..<p.wobbles).map { i in
            lead + Double(i) * spacing + (i == p.wobbles - 1 && i > 0 ? p.pauseBeforeLast : 0)
        }
    }

    /// 금 k 가 생기는 시각 — 흔들림이 알을 "두드리는" 순간(흔들림 중간)에 맞춘다. 금이 흔들림보다
    /// 많으면 같은 흔들림에서 조금씩 시차를 두고 번진다.
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

    /// 한 순간의 모습. 뷰는 이 값만 그린다.
    struct Frame: Equatable {
        /// 알의 기울기(도).
        var tilt: Double = 0
        /// 금마다 0…1(그려진 길이 비율).
        var crackProgress: [Double] = []
        /// 등급색 후광 0…1.
        var glow: Double = 0
        /// 빛줄기 불투명도와 회전각.
        var rays: Double = 0
        var rayAngle: Double = 0
        /// 섬광 불투명도.
        var flash: Double = 0
        /// 알 대신 포켓몬을 그린다(섬광 최고조부터).
        var revealed = false
        var eggScale: Double = 1
        var hatchlingScale: Double = 1
    }

    /// 연출 중 알 크기. 평소 알은 칸을 꽉 채워(크롭) 그대로 기울이면 모서리가 칸에 잘리고 뒤의 후광·빛줄기가
    /// 가려진다 → 시작하자마자(`lead` 동안) 이만큼 줄여 흔들릴 여백과 빛이 보일 둘레를 만든다.
    static let eggInset: Double = 0.82

    static let crackGrowth: TimeInterval = 0.18

    static func frame(_ p: Profile, at t: TimeInterval, reduceMotion: Bool = false) -> Frame {
        var f = Frame()
        let reveal = revealTime(p, reduceMotion: reduceMotion)
        f.revealed = t >= reveal
        if reduceMotion {
            // 크기 변화도 움직임이라 알은 평소 크기 그대로 둔다(기울지 않으니 잘릴 일도 없다).
            // 움직임 없이: 금은 한 번에 옅게 떠오르고, 등급색 후광이 차오른 뒤 섬광.
            let appear = smoothstep(0, reveal * 0.6, t)
            f.crackProgress = Array(repeating: f.revealed ? 0 : appear, count: p.cracks)
            f.glow = p.glow * (f.revealed ? 1 - smoothstep(reveal, reveal + reducedTail, t)
                                          : smoothstep(0, reveal, t))
            f.flash = flash(peak: p.flashPeak, reveal: reveal, fade: reducedTail, at: t)
            return f
        }
        for (i, start) in wobbleStarts(p).enumerated() where t >= start && t <= start + wobbleLength {
            let u = (t - start) / wobbleLength
            // 갈수록 세지는 흔들림 — 앞쪽은 마지막의 60%에서 시작해 점점 커진다.
            let amp = p.wobbleDegrees * (0.6 + 0.4 * Double(i + 1) / Double(p.wobbles))
            f.tilt = amp * sin(u * 3 * .pi) * (1 - 0.5 * u)
        }
        f.crackProgress = f.revealed ? Array(repeating: 0, count: p.cracks)
            : crackTimes(p).map { clamp01((t - $0) / crackGrowth) }
        let firstStart = wobbleStarts(p).first ?? 0
        if f.revealed {
            let fade = 1 - smoothstep(reveal, reveal + tail, t)
            f.glow = p.glow * fade
            f.rays = p.rays ? fade : 0
            // 스프링 팝(0.6→1) — 감쇠 진동. 기존 진화 연출의 spring 과 같은 인상.
            let tau = t - reveal
            f.hatchlingScale = 1 - 0.4 * exp(-5 * tau) * cos(9 * tau)
        } else {
            f.glow = p.glow * pow(smoothstep(firstStart, reveal, t), 1.4)
            f.rays = p.rays ? smoothstep(firstStart + 0.3, reveal - 0.2, t) : 0
            // 줄어든 채 시작해(첫 프레임만 평소 크기에서 이어짐) 터지기 직전 살짝 부푼다.
            let settle = 1 - (1 - eggInset) * smoothstep(0, lead, t)
            f.eggScale = settle + 0.06 * smoothstep(reveal - 0.3, reveal, t)
        }
        f.rayAngle = t * 40
        f.flash = flash(peak: p.flashPeak, reveal: reveal, fade: tail * 0.9, at: t)
        return f
    }

    /// 공개 0.15초 전부터 차올라 공개 순간 최고조, 이후 `fade` 동안 걷힌다.
    private static func flash(peak: Double, reveal: TimeInterval, fade: TimeInterval, at t: TimeInterval) -> Double {
        if t < reveal { return peak * smoothstep(reveal - 0.15, reveal, t) }
        let x = clamp01((t - reveal) / fade)
        return peak * (1 - x) * (1 - x)
    }

    /// 금의 꺾은선(스프라이트 칸 기준 0…1 좌표). 0 = 가운데 짧은 금, 1·2 = 좌우로 번짐, 3~5 = 위아래 갈래.
    /// 알 스프라이트는 콘텐츠 크롭돼 칸을 꽉 채우므로(SpriteLoader.eggImage) 이 띠가 알 몸통 위에 놓인다.
    static let crackPaths: [[CGPoint]] = [
        [CGPoint(x: 0.36, y: 0.50), CGPoint(x: 0.43, y: 0.44), CGPoint(x: 0.50, y: 0.52),
         CGPoint(x: 0.57, y: 0.45), CGPoint(x: 0.64, y: 0.51)],
        [CGPoint(x: 0.36, y: 0.50), CGPoint(x: 0.29, y: 0.45), CGPoint(x: 0.22, y: 0.52)],
        [CGPoint(x: 0.64, y: 0.51), CGPoint(x: 0.71, y: 0.46), CGPoint(x: 0.78, y: 0.53)],
        [CGPoint(x: 0.43, y: 0.44), CGPoint(x: 0.40, y: 0.36), CGPoint(x: 0.45, y: 0.29)],
        [CGPoint(x: 0.50, y: 0.52), CGPoint(x: 0.54, y: 0.61), CGPoint(x: 0.50, y: 0.69)],
        [CGPoint(x: 0.71, y: 0.46), CGPoint(x: 0.68, y: 0.38), CGPoint(x: 0.73, y: 0.31)],
    ]
}

/// 꺾은선 하나. `trim` 으로 자라나게 그린다.
private struct PolylineShape: Shape {
    let points: [CGPoint]
    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: CGPoint(x: rect.minX + first.x * rect.width, y: rect.minY + first.y * rect.height))
        for p in points.dropFirst() {
            path.addLine(to: CGPoint(x: rect.minX + p.x * rect.width, y: rect.minY + p.y * rect.height))
        }
        return path
    }
}

/// 칸 중심에서 뻗는 빛줄기 부채꼴들.
private struct RaysShape: Shape {
    let count: Int
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = max(rect.width, rect.height)
        let half = Double.pi / Double(count) * 0.45
        for i in 0..<count {
            let a = Double(i) / Double(count) * 2 * .pi
            path.move(to: c)
            path.addLine(to: CGPoint(x: c.x + r * cos(a - half), y: c.y + r * sin(a - half)))
            path.addLine(to: CGPoint(x: c.x + r * cos(a + half), y: c.y + r * sin(a + half)))
            path.closeSubpath()
        }
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
    @ViewBuilder var egg: Egg
    @ViewBuilder var hatchling: Hatchling

    var body: some View {
        let f = HatchEffect.frame(profile, at: elapsed, reduceMotion: reduceMotion)
        // 배지와 같은 색 — 공개 뒤 플레이어가 보는 등급 배지가 방금 본 빛의 색과 이어지게.
        let tint = rarityColor(profile.rarity)
        let line = size / 76
        ZStack {
            if f.rays > 0 {
                RaysShape(count: 12)
                    .fill(RadialGradient(colors: [tint.opacity(0.75), tint.opacity(0)],
                                         center: .center, startRadius: size * 0.08, endRadius: size * 0.62))
                    .rotationEffect(.degrees(f.rayAngle))
                    .opacity(f.rays)
            }
            if f.glow > 0 {
                Circle()
                    .fill(RadialGradient(colors: [tint.opacity(0.85), tint.opacity(0)],
                                         center: .center, startRadius: 0, endRadius: size * 0.55))
                    .frame(width: size * 1.1, height: size * 1.1)
                    .opacity(f.glow)
            }
            if f.revealed {
                hatchling.scaleEffect(f.hatchlingScale)
            } else {
                ZStack {
                    egg
                    ForEach(0..<min(profile.cracks, HatchEffect.crackPaths.count), id: \.self) { k in
                        let progress = f.crackProgress.indices.contains(k) ? f.crackProgress[k] : 0
                        if progress > 0 { crack(k, progress: progress, tint: tint, line: line) }
                    }
                }
                .shadow(color: tint.opacity(f.glow * 0.9), radius: 6 * line * f.glow)
                .scaleEffect(f.eggScale)
                // 바닥을 축으로 흔들린다(굴러가지 않고 제자리에서 들썩이게).
                .rotationEffect(.degrees(f.tilt), anchor: UnitPoint(x: 0.5, y: 0.9))
            }
            ZStack {
                Color.white
                tint.opacity(profile.flashTint)
            }
            .opacity(f.flash)
            .allowsHitTesting(false)
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private func crack(_ k: Int, progress: Double, tint: Color, line: CGFloat) -> some View {
        let shape = PolylineShape(points: HatchEffect.crackPaths[k]).trim(from: 0, to: progress)
        let style = StrokeStyle(lineWidth: 1.6 * line, lineCap: .round, lineJoin: .round)
        // 동작 줄이기에선 trim 대신 불투명도로 떠오른다(progress 가 전 금에 같은 값).
        let opacity = reduceMotion ? progress : 1
        if profile.leaksLight {
            // 희귀 이상: 금 사이로 빛이 샌다 — 등급색 번짐 위에 흰 심지.
            ZStack {
                shape.stroke(tint, style: StrokeStyle(lineWidth: 4 * line, lineCap: .round, lineJoin: .round))
                    .blur(radius: 1.5 * line)
                shape.stroke(Color.white, style: style)
            }
            .opacity(opacity)
        } else {
            shape.stroke(Color(red: 0.25, green: 0.18, blue: 0.12), style: style).opacity(opacity)
        }
    }
}

// MARK: - 졸업 (몬스터볼 회수)

/// 졸업한 포켓몬이 몬스터볼로 빨려 들어가는("슈욱") 연출의 타이밍 표.
enum GraduationEffect {
    static let duration: TimeInterval = 2.3
    static let reducedDuration: TimeInterval = 1.1
    /// 볼 중심(칸 기준 0…1)과 지름 비율 — 포켓몬 앞쪽 아래에 놓인다.
    static let ballCenter = CGPoint(x: 0.5, y: 0.7)
    static let ballDiameter: CGFloat = 0.4
    static let wobbleStarts: [TimeInterval] = [0.9, 1.24, 1.58]
    static let wobbleLength: TimeInterval = 0.28
    static let wobbleDegrees: Double = 15
    static let clickAt: TimeInterval = 1.86

    static func duration(reduceMotion: Bool) -> TimeInterval { reduceMotion ? reducedDuration : duration }

    struct Frame: Equatable {
        var ballScale: Double = 0
        var ballOpacity: Double = 0
        /// 볼 윗덮개가 열린 정도 0…1.
        var ballOpen: Double = 0
        var ballTilt: Double = 0
        var monScale: Double = 1
        /// 포켓몬이 볼 쪽으로 끌려간 정도 0…1.
        var monPull: Double = 0
        /// 빨갛게 물드는 정도 0…1.
        var monRed: Double = 0
        var monOpacity: Double = 1
        /// 잠금 "딸깍" 반짝임 0…1(진행률 — 0 이면 안 보임).
        var sparkle: Double = 0
        var eggOpacity: Double = 0
    }

    static func frame(at t: TimeInterval, reduceMotion: Bool = false) -> Frame {
        var f = Frame()
        if reduceMotion {
            // 움직임 없이: 볼이 떠오르고, 포켓몬은 붉게 물들며 사라지고, 볼이 걷히며 새 알.
            f.ballScale = 1
            f.ballOpacity = smoothstep(0, 0.2, t) * (1 - smoothstep(0.8, 1.1, t))
            f.monRed = smoothstep(0.2, 0.5, t)
            f.monOpacity = 1 - smoothstep(0.2, 0.7, t)
            f.eggOpacity = smoothstep(0.8, 1.1, t)
            return f
        }
        // 등장: 살짝 넘쳤다 자리 잡는 팝.
        let appear = clamp01(t / 0.22)
        f.ballScale = appear >= 1 ? 1 : 1 + 2.2 * pow(appear - 1, 3) + 1.2 * pow(appear - 1, 2)
        f.ballOpacity = smoothstep(0, 0.1, t) * (1 - smoothstep(2.0, 2.3, t))
        // 덮개: 열렸다가(0.15–0.3) 빨아들인 뒤 닫힌다(0.75–0.85).
        f.ballOpen = smoothstep(0.15, 0.3, t) * (1 - smoothstep(0.75, 0.85, t))
        // 슈욱: 붉게 물들며 작아지고 볼 입구로 끌려간다(가속).
        f.monRed = smoothstep(0.25, 0.45, t)
        let pull = clamp01((t - 0.3) / 0.45)
        f.monPull = pull * pull
        f.monScale = 1 - 0.95 * f.monPull
        f.monOpacity = t < 0.75 ? 1 : 0
        for start in wobbleStarts where t >= start && t <= start + wobbleLength {
            let u = (t - start) / wobbleLength
            f.ballTilt = wobbleDegrees * sin(u * 2 * .pi)
        }
        f.sparkle = t >= clickAt && t <= clickAt + 0.3 ? (t - clickAt) / 0.3 : 0
        f.eggOpacity = smoothstep(2.0, 2.3, t)
        return f
    }
}

/// 몬스터볼 — 빨간 윗덮개, 흰 아랫부분, 검은 띠, 가운데 버튼. `open` 만큼 윗덮개가 뒤로 젖혀진다.
@MainActor
struct PokeBallView: View {
    let diameter: CGFloat
    var open: Double = 0
    /// 잠길 때 버튼이 빛난다.
    var buttonGlow: Double = 0

    var body: some View {
        let d = diameter
        let stroke = max(1, d * 0.06)
        ZStack {
            // 아랫부분
            HalfCircle(top: false).fill(Color.white)
                .overlay(HalfCircle(top: false).stroke(Color.black, lineWidth: stroke))
            // 윗덮개 — 열릴 때 뒤쪽(왼쪽) 경첩을 축으로 젖혀진다.
            HalfCircle(top: true).fill(Color(red: 0.89, green: 0.16, blue: 0.16))
                .overlay(HalfCircle(top: true).stroke(Color.black, lineWidth: stroke))
                .rotationEffect(.degrees(-38 * open), anchor: UnitPoint(x: 0.08, y: 0.5))
                .offset(y: -d * 0.08 * open)
            // 띠 + 버튼(닫혔을 때만 이어져 보이도록 덮개와 함께 살짝 흐려진다)
            Rectangle().fill(Color.black).frame(width: d, height: stroke * 1.4)
                .opacity(1 - open * 0.6)
            Circle().fill(Color.white)
                .overlay(Circle().fill(Color.yellow.opacity(buttonGlow)))
                .overlay(Circle().stroke(Color.black, lineWidth: stroke))
                .frame(width: d * 0.32, height: d * 0.32)
                .shadow(color: Color.white.opacity(buttonGlow), radius: d * 0.2)
        }
        .frame(width: d, height: d)
    }
}

/// 원의 위/아래 반쪽(둘레까지 닫힌 도형).
private struct HalfCircle: Shape {
    let top: Bool
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        p.addArc(center: c, radius: r, startAngle: .degrees(top ? 180 : 0), endAngle: .degrees(top ? 360 : 180),
                 clockwise: false)
        p.closeSubpath()
        return p
    }
}

/// 졸업 연출 한 순간. `pokemon`·`egg` 는 호출자가 그린다.
@MainActor
struct GraduationEffectView<Pokemon: View, Egg: View>: View {
    let elapsed: TimeInterval
    var size: CGFloat = 76
    var reduceMotion = false
    @ViewBuilder var pokemon: Pokemon
    @ViewBuilder var egg: Egg

    var body: some View {
        let f = GraduationEffect.frame(at: elapsed, reduceMotion: reduceMotion)
        let ball = size * GraduationEffect.ballDiameter
        // 볼 중심까지의 거리(칸 중심 기준) — 포켓몬이 그만큼 끌려간다.
        let toBall = CGSize(width: (GraduationEffect.ballCenter.x - 0.5) * size,
                            height: (GraduationEffect.ballCenter.y - 0.5) * size)
        ZStack {
            egg.opacity(f.eggOpacity)
            if f.monOpacity > 0 {
                pokemon
                    // 밝게 띄운 뒤 빨강을 곱하면 실루엣 전체가 붉은 빛으로 바뀐다(본가의 회수 빔 인상).
                    .brightness(0.35 * f.monRed)
                    .colorMultiply(Color(red: 1, green: 1 - 0.78 * f.monRed, blue: 1 - 0.78 * f.monRed))
                    .scaleEffect(f.monScale)
                    .offset(x: toBall.width * f.monPull, y: toBall.height * f.monPull)
                    .opacity(f.monOpacity)
            }
            PokeBallView(diameter: ball, open: f.ballOpen, buttonGlow: f.sparkle > 0 ? 1 - f.sparkle : 0)
                .scaleEffect(f.ballScale)
                // 바닥을 축으로 흔들린다.
                .rotationEffect(.degrees(f.ballTilt), anchor: .bottom)
                .opacity(f.ballOpacity)
                .offset(toBall)
            if f.sparkle > 0 {
                ForEach(0..<4, id: \.self) { i in
                    let a = Double(i) * .pi / 2 + .pi / 4
                    let r = Double(ball) * (0.35 + 0.45 * f.sparkle)
                    Image(systemName: "sparkle")
                        .font(.system(size: ball * 0.32, weight: .bold))
                        .foregroundStyle(Color.yellow)
                        .offset(x: toBall.width + r * cos(a), y: toBall.height - ball * 0.25 + r * sin(a) * 0.8)
                        .opacity(1 - f.sparkle)
                }
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - 진화 (본가 진화 신 오마주)

/// 옛 모습이 흰 실루엣이 되고, 옛·새 실루엣이 처음엔 느리게 점점 빠르게 번갈아 보이다가, 섬광과 함께
/// 새 모습이 튀어나오는 진화 연출의 타이밍 표.
enum EvolutionEffect {
    /// 흰 실루엣으로 변하는 구간 끝.
    static let whitenEnd: TimeInterval = 0.4
    /// 번갈아 보이기 구간 끝 — 여기서 새 모습(흰 실루엣)으로 멈추고 섬광이 차오른다.
    static let alternateEnd: TimeInterval = 1.7
    /// 섬광 최고조 = 새 모습 공개(정보 칸도 이때 새 단계로 바뀐다).
    static let revealAt: TimeInterval = 1.85
    static let tail: TimeInterval = 0.7
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
        /// 0 = 옛 모습, 1 = 새 모습(교차 비율).
        var mix: Double = 0
        var oldScale: Double = 1
        var newScale: Double = 1
        /// 흰 실루엣 정도 0…1.
        var whiteness: Double = 0
        var glow: Double = 0
        var flash: Double = 0
        var revealed = false
        var popScale: Double = 1
        /// 공개 뒤 반짝이 진행률(0 = 안 보임).
        var sparkle: Double = 0
    }

    /// 번갈아 보이기 구간에서 지나간 주기 수 — 주파수가 시작값에서 선형으로 올라 정확히
    /// `alternationCycles` 에서 끝나도록 끝 주파수를 맞춘다.
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
        if reduceMotion {
            // 움직임 없이: 옛→새 교차 페이드 + 섬광.
            f.mix = smoothstep(0, reveal, t)
            f.flash = t < reveal ? 0.85 * smoothstep(reveal - 0.15, reveal, t)
                                 : 0.85 * pow(1 - clamp01((t - reveal) / reducedTail), 2)
            return f
        }
        if f.revealed {
            let tau = t - reveal
            f.mix = 1
            f.whiteness = 1 - smoothstep(reveal, reveal + 0.3, t)
            f.glow = 1 - smoothstep(reveal, reveal + tail, t)
            f.popScale = 1 - 0.4 * exp(-5 * tau) * cos(9 * tau)
            f.flash = pow(1 - clamp01(tau / (tail * 0.9)), 2)
            f.sparkle = tau >= 0.1 && tau <= 0.6 ? (tau - 0.1) / 0.5 : 0
            return f
        }
        f.whiteness = smoothstep(0.05, whitenEnd, t)
        f.glow = smoothstep(0.05, whitenEnd + 0.3, t)
        f.mix = t >= alternateEnd ? 1 : (1 - cos(2 * .pi * cycles(at: t))) / 2
        // 옛 모습은 작아지며 사라지고 새 모습은 커지며 나타난다 — 형태가 줄었다 늘었다 하는 인상.
        f.oldScale = 1 - 0.25 * f.mix
        f.newScale = 0.75 + 0.25 * f.mix
        f.flash = smoothstep(alternateEnd, reveal, t)
        return f
    }
}

/// 진화 연출 한 순간. `from`·`to` 는 진화 전·후 스프라이트(호출자가 그린다).
@MainActor
struct EvolutionEffectView<From: View, To: View>: View {
    let elapsed: TimeInterval
    var size: CGFloat = 76
    var reduceMotion = false
    @ViewBuilder var from: From
    @ViewBuilder var to: To

    var body: some View {
        let f = EvolutionEffect.frame(at: elapsed, reduceMotion: reduceMotion)
        let glowColor = Color(red: 0.72, green: 0.86, blue: 1)
        ZStack {
            if f.glow > 0 {
                Circle()
                    .fill(RadialGradient(colors: [glowColor.opacity(0.9), glowColor.opacity(0)],
                                         center: .center, startRadius: 0, endRadius: size * 0.55))
                    .frame(width: size * 1.1, height: size * 1.1)
                    .opacity(f.glow)
            }
            if f.revealed {
                to.brightness(f.whiteness).scaleEffect(f.popScale)
            } else {
                // brightness(1) 은 알파를 지키고 색만 하얗게 민다 → 스프라이트 모양 그대로의 흰 실루엣.
                if f.mix < 1 {
                    from.brightness(f.whiteness).scaleEffect(f.oldScale).opacity(1 - f.mix)
                }
                if f.mix > 0 {
                    to.brightness(f.whiteness).scaleEffect(f.newScale).opacity(f.mix)
                }
            }
            if f.sparkle > 0 {
                ForEach(0..<4, id: \.self) { i in
                    let a = Double(i) * .pi / 2 + .pi / 5
                    let r = Double(size) * (0.22 + 0.2 * f.sparkle)
                    Image(systemName: "sparkle")
                        .font(.system(size: size * 0.14, weight: .bold))
                        .foregroundStyle(Color.yellow)
                        .offset(x: r * cos(a), y: r * sin(a))
                        .opacity(1 - f.sparkle)
                }
            }
            Color.white.opacity(f.flash).allowsHitTesting(false)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - 메타몽 리빌

/// 위장체 → 메타몽 교체를 섬광이 덮고 스프링 팝(🎭 버스트는 헤더가 칸 밖에 띄운다). 예전엔 평소 스프라이트
/// 위에 플래시만 얹었는데, 큐에 부화와 리빌이 함께 쌓이면 재생 시점의 상태가 이미 메타몽이라 위장 모습이
/// 한 번도 안 보였다 → 위장체를 직접 그리고 섬광 아래서 바꾼다.
enum DittoRevealEffect {
    /// 섬광 최고조 = 교체 순간(정보 칸도 이때 메타몽으로 바뀐다).
    static let revealAt: TimeInterval = 0.15
    static let tail: TimeInterval = 0.85
    static let reducedTail: TimeInterval = 0.5

    static func duration(reduceMotion: Bool) -> TimeInterval { revealAt + (reduceMotion ? reducedTail : tail) }

    struct Frame: Equatable {
        var revealed = false
        var flash: Double = 0
        var popScale: Double = 1
    }

    static func frame(at t: TimeInterval, reduceMotion: Bool = false) -> Frame {
        var f = Frame()
        f.revealed = t >= revealAt
        guard f.revealed else {
            f.flash = 0.85 * smoothstep(0, revealAt, t)
            return f
        }
        let tau = t - revealAt
        let fade = reduceMotion ? reducedTail : tail * 0.95
        f.flash = 0.85 * pow(1 - clamp01(tau / fade), 2)
        // 동작 줄이기: 팝 없이 섬광만.
        f.popScale = reduceMotion ? 1 : 1 - 0.4 * exp(-5 * tau) * cos(9 * tau)
        return f
    }
}

/// 메타몽 리빌 한 순간. `disguise`·`ditto` 는 호출자가 그린다.
@MainActor
struct DittoRevealEffectView<Disguise: View, Ditto: View>: View {
    let elapsed: TimeInterval
    var size: CGFloat = 76
    var reduceMotion = false
    @ViewBuilder var disguise: Disguise
    @ViewBuilder var ditto: Ditto

    var body: some View {
        let f = DittoRevealEffect.frame(at: elapsed, reduceMotion: reduceMotion)
        ZStack {
            if f.revealed {
                ditto.scaleEffect(f.popScale)
            } else {
                disguise
            }
            Color.white.opacity(f.flash).allowsHitTesting(false)
        }
        .frame(width: size, height: size)
    }
}
