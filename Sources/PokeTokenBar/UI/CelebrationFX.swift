import SwiftUI

// 연출의 "빛 층" 도구 — 입자·번짐·광선을 `Canvas` 로 그린다.
//
// 왜 따로 두나: 첫 구현은 모든 그림이 76×76 칸 안에 갇혀 있었고(단색 후광·가는 금·입자 없음) 사용자가
// "허접하다"고 했다. 본가(BW) 연출은 빛이 칸 밖까지 터진다. 그래서 연출을 두 층으로 나눈다:
// - 스프라이트 층: 칸 안(알·포켓몬·몬스터볼). 헤더에선 둥근 칸에 잘린다.
// - 빛 층: 칸의 `overflow` 배 크기로 칸 중심에 겹쳐, 칸에 잘리지 않는 오버레이(헤더) 또는 클릭이 통과하는
//   별도 패널(플로팅 펫)에 그린다.
// 입자는 전부 시드 고정 난수 + 경과 시간의 순수 함수다 — 테스트가 임의 순간을 결정적으로 그리고, 모든 입자가
// 빛 층 안에 머무는지(잘리지 않는지) 검사할 수 있다.

enum CelebrationFX {
    /// 빛 층 한 변 / 칸 한 변. 입자는 칸 중심에서 ±overflow/2 칸 안에 머문다(`ParticleTests` 가 고정).
    static let overflow: CGFloat = 2.2
    /// 입자가 머물러야 하는 반경(칸 단위) — 빛 층 가장자리에서 입자 크기만큼 안쪽.
    static let particleBound: Double = Double(overflow) / 2 - 0.06

    /// 시드 고정 난수(SplitMix64) — 같은 연출은 같은 입자 배치로 그린다.
    struct Random {
        private var state: UInt64
        init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
        mutating func next() -> Double {
            state = state &+ 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            z ^= z >> 31
            return Double(z >> 11) / Double(1 << 53)
        }
        mutating func range(_ a: Double, _ b: Double) -> Double { a + (b - a) * next() }
    }

    /// 한 순간의 입자 하나. 좌표는 칸 단위(칸 한 변 = 1), 칸 중심 원점, y 아래로.
    struct Particle: Equatable {
        var x: Double
        var y: Double
        /// 지름(칸 단위).
        var size: Double
        var rotation: Double = 0
        var opacity: Double
        /// 그릴 모양: 별(빛), 점(빛), 껍질 조각, 노란 별.
        enum Shape: Equatable { case sparkle, mote, shell, star }
        var shape: Shape
    }

    // MARK: 이징

    static func clamp01(_ x: Double) -> Double { min(1, max(0, x)) }
    static func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
        guard b > a else { return x >= b ? 1 : 0 }
        let t = clamp01((x - a) / (b - a))
        return t * t * (3 - 2 * t)
    }
    static func easeOutCubic(_ x: Double) -> Double { let u = 1 - clamp01(x); return 1 - u * u * u }
    static func easeInCubic(_ x: Double) -> Double { let u = clamp01(x); return u * u * u }
    /// 살짝 넘쳤다 돌아오는 등장(back-out).
    static func easeOutBack(_ x: Double, overshoot s: Double = 1.7) -> Double {
        let u = clamp01(x) - 1
        return 1 + (s + 1) * u * u * u + s * u * u
    }
    /// 감쇠 스프링 0.6 → 1(기존 진화 팝과 같은 인상).
    static func springPop(_ t: Double) -> Double {
        guard t > 0 else { return 0.6 }
        return 1 - 0.4 * exp(-5.5 * t) * cos(10 * t)
    }

    // MARK: 입자 계

    /// 중심에서 방사형으로 터지는 반짝이(공기 저항으로 감속, 깜빡이며 사라짐).
    static func burst(seed: UInt64, count: Int, at t: Double, reach: Double, life: Double = 0.9,
                      size: ClosedRange<Double> = 0.07...0.13, shape: Particle.Shape = .sparkle) -> [Particle] {
        guard t >= 0, t <= life else { return [] }
        var rng = Random(seed: seed)
        return (0..<count).map { i in
            let angle = Double(i) / Double(count) * 2 * .pi + rng.range(-0.25, 0.25)
            let dist = min(reach, particleBound - 0.05) * rng.range(0.55, 1.0)
            let d = dist * easeOutCubic(t / (life * 0.75))
            let sz = rng.range(size.lowerBound, size.upperBound)
            let twinkle = 0.75 + 0.25 * sin(t * 26 + Double(i))
            let fade = 1 - smoothstep(life * 0.45, life, t)
            return Particle(x: d * cos(angle), y: d * sin(angle) - 0.05,
                            size: sz * (1 - 0.35 * t / life), rotation: t * 3 + Double(i),
                            opacity: fade * twinkle, shape: shape)
        }
    }

    /// 중력·공기 저항을 받는 파편(껍질 조각·노란 별). `spread` 는 위쪽 부채꼴 반각(라디안).
    static func debris(seed: UInt64, count: Int, at t: Double, speed: ClosedRange<Double>,
                       spread: Double = 1.3, gravity: Double = 2.4, drag: Double = 3.2, life: Double = 1.0,
                       origin: (x: Double, y: Double) = (0, -0.1), size: ClosedRange<Double> = 0.06...0.11,
                       shape: Particle.Shape = .shell) -> [Particle] {
        guard t >= 0, t <= life else { return [] }
        var rng = Random(seed: seed)
        return (0..<count).map { i in
            let angle = -Double.pi / 2 + (Double(i) / Double(max(1, count - 1)) - 0.5) * 2 * spread
                + rng.range(-0.18, 0.18)
            let v = rng.range(speed.lowerBound, speed.upperBound)
            // 저항: 이동 = v/k (1 - e^-kt) — 처음 빠르고 곧 감속. 중력은 그 위에 더한다.
            let travel = v / drag * (1 - exp(-drag * t))
            var x = origin.x + travel * cos(angle)
            var y = origin.y + travel * sin(angle) + 0.5 * gravity * t * t
            // 빛 층 밖으로 나가기 전에 사라지도록 — 경계 근처에선 투명해지고 좌표도 경계에 묶는다.
            let r = (x * x + y * y).squareRoot()
            let edgeFade = 1 - smoothstep(particleBound - 0.2, particleBound, r)
            if r > particleBound { x *= particleBound / r; y *= particleBound / r }
            let fade = 1 - smoothstep(life * 0.6, life, t)
            return Particle(x: x, y: y, size: rng.range(size.lowerBound, size.upperBound),
                            rotation: rng.range(-3, 3) + t * rng.range(-9, 9),
                            opacity: fade * edgeFade, shape: shape)
        }
    }

    /// 아래에서 피어올라 흔들리며 사라지는 금빛 티끌(전설 부화).
    static func risingMotes(seed: UInt64, count: Int, at t: Double, from start: Double, until end: Double) -> [Particle] {
        var rng = Random(seed: seed)
        var out: [Particle] = []
        for i in 0..<count {
            let born = rng.range(start, max(start, end - 0.6))
            let x0 = rng.range(-0.75, 0.75)
            let speed = rng.range(0.45, 0.75)
            let sway = rng.range(0.03, 0.07)
            let size = rng.range(0.035, 0.07)
            let age = t - born
            let life = 1.3
            guard age >= 0, age <= life else { continue }
            let y = min(particleBound, 0.75) - speed * age
            let x = x0 + sway * sin(age * 5 + Double(i))
            let alpha = smoothstep(0, 0.25, age) * (1 - smoothstep(life * 0.6, life, age))
            out.append(Particle(x: x, y: max(-particleBound, y), size: size, opacity: alpha * (0.7 + 0.3 * sin(age * 18)),
                                shape: .mote))
        }
        return out
    }

    /// 바깥에서 소용돌이치며 중심으로 모여드는 빛(진화 시작).
    static func converging(seed: UInt64, count: Int, at t: Double, from start: Double, until end: Double,
                           radius: Double = 0.95) -> [Particle] {
        var rng = Random(seed: seed)
        var out: [Particle] = []
        for _ in 0..<count {
            let born = rng.range(start, max(start, end - 0.7))
            let travel = rng.range(0.55, 0.8)
            let theta0 = rng.range(0, 2 * .pi)
            let size = rng.range(0.04, 0.08)
            let r0 = min(radius, particleBound - 0.05) * rng.range(0.8, 1.0)
            let u = (t - born) / travel
            guard u >= 0, u <= 1 else { continue }
            let r = r0 * (1 - easeInCubic(u) * 0.92)
            let theta = theta0 + 2.4 * u
            out.append(Particle(x: r * cos(theta), y: r * sin(theta), size: size * (1 - 0.4 * u),
                                opacity: smoothstep(0, 0.2, u) * (1 - smoothstep(0.85, 1, u)), shape: .mote))
        }
        return out
    }
}

// MARK: - 그리기 도우미

/// 빛 층 캔버스 안의 좌표계 — 칸 중심 원점, 칸 단위 → 캔버스 점.
struct FXSpace {
    let size: CGSize
    /// 칸 한 변(pt).
    let unit: CGFloat
    var center: CGPoint { CGPoint(x: size.width / 2, y: size.height / 2) }
    func point(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: center.x + CGFloat(x) * unit, y: center.y + CGFloat(y) * unit)
    }
    func length(_ v: Double) -> CGFloat { CGFloat(v) * unit }
}

extension GraphicsContext {
    /// 부드러운 번짐 — 바깥은 투명, 안쪽은 색. 겹쳐 그리면 "빛"이 된다(밝은 배경에서도 보이도록 일반 합성).
    func glow(_ space: FXSpace, x: Double, y: Double, radius: Double, color: Color, opacity: Double) {
        guard opacity > 0.001, radius > 0 else { return }
        let c = space.point(x, y)
        let r = space.length(radius)
        var ctx = self
        ctx.opacity = opacity
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                 with: .radialGradient(Gradient(stops: [
                    .init(color: color, location: 0), .init(color: color.opacity(0.55), location: 0.35),
                    .init(color: color.opacity(0), location: 1)]),
                    center: c, startRadius: 0, endRadius: r))
    }

    /// 섬광 — 가운데가 평평하게 하얗게 차고 가장자리만 풀린다(번짐보다 확실히 덮는다).
    func flare(_ space: FXSpace, radius: Double, color: Color, opacity: Double) {
        guard opacity > 0.001, radius > 0 else { return }
        let c = space.center
        let r = space.length(radius)
        var ctx = self
        ctx.opacity = opacity
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                 with: .radialGradient(Gradient(stops: [
                    .init(color: color, location: 0), .init(color: color, location: 0.45),
                    .init(color: color.opacity(0), location: 1)]),
                    center: c, startRadius: 0, endRadius: r))
    }

    /// 가운데가 빈 고리 모양 번짐(알 둘레 후광·광선 구멍 — 스프라이트를 덮지 않게).
    func halo(_ space: FXSpace, radius inner: Double, outer: Double, color: Color, opacity: Double) {
        guard opacity > 0.001 else { return }
        let c = space.center
        let r = space.length(outer)
        let start = CGFloat(inner / outer)
        var ctx = self
        ctx.opacity = opacity
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                 with: .radialGradient(Gradient(stops: [
                    .init(color: color.opacity(0), location: 0), .init(color: color.opacity(0), location: start * 0.85),
                    .init(color: color, location: start + (1 - start) * 0.15), .init(color: color.opacity(0), location: 1)]),
                    center: c, startRadius: 0, endRadius: r))
    }

    /// 퍼져 나가는 충격파 — 선이 아니라 가장자리가 풀린 빛의 띠(딱딱한 원 테두리는 싸 보인다).
    func shockwave(_ space: FXSpace, radius: Double, width: Double, color: Color, opacity: Double) {
        guard opacity > 0.001, radius > 0 else { return }
        let outer = radius + width
        let c = space.center
        let r = space.length(outer)
        let inner = CGFloat(max(0, radius - width) / outer), peak = CGFloat(radius / outer)
        var ctx = self
        ctx.opacity = opacity
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                 with: .radialGradient(Gradient(stops: [
                    .init(color: color.opacity(0), location: inner), .init(color: color, location: peak),
                    .init(color: color.opacity(0), location: 1)]),
                    center: c, startRadius: 0, endRadius: r))
    }

    /// 네 갈래 반짝이 — 색 번짐 + 흰 심지. 크기는 지름(칸 단위).
    func sparkle(_ space: FXSpace, _ p: CelebrationFX.Particle, color: Color) {
        guard p.opacity > 0.01 else { return }
        glow(space, x: p.x, y: p.y, radius: p.size * 0.9, color: color, opacity: p.opacity * 0.7)
        let c = space.point(p.x, p.y)
        let r = space.length(p.size / 2)
        var path = Path()
        for k in 0..<8 {
            let a = Double(k) * .pi / 4 + p.rotation * 0.2
            let len = k.isMultiple(of: 2) ? r : r * 0.28
            let pt = CGPoint(x: c.x + len * CGFloat(cos(a)), y: c.y + len * CGFloat(sin(a)))
            if k == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        path.closeSubpath()
        var ctx = self
        ctx.opacity = p.opacity
        ctx.fill(path, with: .color(.white))
    }

    /// 다섯 갈래 노란 별(포획 확정 "딸깍" — 본가의 별 튀김).
    func star(_ space: FXSpace, _ p: CelebrationFX.Particle) {
        guard p.opacity > 0.01 else { return }
        let c = space.point(p.x, p.y)
        let r = space.length(p.size / 2)
        var path = Path()
        for k in 0..<10 {
            let a = -Double.pi / 2 + Double(k) * .pi / 5 + p.rotation
            let len = k.isMultiple(of: 2) ? r : r * 0.45
            let pt = CGPoint(x: c.x + len * CGFloat(cos(a)), y: c.y + len * CGFloat(sin(a)))
            if k == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        path.closeSubpath()
        glow(space, x: p.x, y: p.y, radius: p.size * 0.85, color: Color(red: 1, green: 0.85, blue: 0.2),
             opacity: p.opacity * 0.6)
        var ctx = self
        ctx.opacity = p.opacity
        ctx.fill(path, with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.97, blue: 0.6),
                                                               Color(red: 1, green: 0.74, blue: 0.1)]),
                                             startPoint: CGPoint(x: c.x, y: c.y - r), endPoint: CGPoint(x: c.x, y: c.y + r)))
        ctx.stroke(path, with: .color(Color(red: 0.75, green: 0.45, blue: 0.05)), lineWidth: max(0.6, r * 0.12))
    }

    /// 알 껍질 조각 — 크림색 다각형 + 어두운 테두리(BW 알 스프라이트의 색).
    func shellShard(_ space: FXSpace, _ p: CelebrationFX.Particle, seed: Int) {
        guard p.opacity > 0.01 else { return }
        let c = space.point(p.x, p.y)
        let r = space.length(p.size / 2)
        var rng = CelebrationFX.Random(seed: UInt64(seed))
        var path = Path()
        let corners = 3 + seed % 2
        for k in 0..<corners {
            let a = p.rotation + Double(k) / Double(corners) * 2 * .pi + rng.range(-0.35, 0.35)
            let len = r * CGFloat(rng.range(0.7, 1.15))
            let pt = CGPoint(x: c.x + len * CGFloat(cos(a)), y: c.y + len * CGFloat(sin(a)))
            if k == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        path.closeSubpath()
        var ctx = self
        ctx.opacity = p.opacity
        ctx.fill(path, with: .color(seed % 3 == 0 ? EggPalette.spot : EggPalette.shell))
        ctx.stroke(path, with: .color(EggPalette.outline), lineWidth: max(0.8, space.unit / 70))
    }
}

/// BW 알 스프라이트의 색 — 벡터 껍질 조각이 실제 알과 이어져 보이게.
enum EggPalette {
    static let shell = Color(red: 0.98, green: 0.95, blue: 0.84)
    static let shade = Color(red: 0.86, green: 0.79, blue: 0.6)
    static let spot = Color(red: 0.49, green: 0.78, blue: 0.42)
    static let outline = Color(red: 0.2, green: 0.17, blue: 0.12)
}

/// 등급 색 — 배지와 같은 색(공개 뒤 보이는 등급 배지와 방금 본 빛이 이어지게). 커먼은 은빛 흰색.
/// 커먼은 배지의 회색 대신 은은한 청회색 — 밝은 팝오버 바탕에서도 반짝이가 보이게(흰색은 묻힌다).
func celebrationTint(_ rarity: Rarity) -> Color {
    rarity == .common ? Color(red: 0.55, green: 0.62, blue: 0.76) : rarityColor(rarity)
}
