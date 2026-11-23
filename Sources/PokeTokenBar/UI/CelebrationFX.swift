import SwiftUI

// 연출의 "빛 층" 도구 — 입자 계(시간의 순수 함수)와 이징. 그리기는 도트 그림판(`PixelFX.swift`)이 한다.
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

    /// 튀어나올 때의 찌그러짐 — 세로로 늘었다(+) 납작해졌다(−) 가라앉는다. 가로는 반대로(부피 보존 인상).
    static func stretch(_ t: Double) -> Double {
        guard t > 0 else { return 0 }
        return 0.2 * exp(-7 * t) * sin(13 * t + 0.4)
    }

    /// 터지는 순간의 화면 흔들림(칸 단위 변위) — 짧게, 빠르게 줄어든다. 결정적(시간의 함수).
    static func shake(_ t: Double, amplitude: Double, length: Double = 0.3) -> CGSize {
        guard t >= 0, t < length, amplitude > 0 else { return .zero }
        let decay = pow(1 - t / length, 2)
        return CGSize(width: amplitude * decay * sin(t * 97), height: amplitude * 0.6 * decay * cos(t * 73))
    }

    // MARK: 입자 계

    /// 중심에서 방사형으로 터지는 반짝이(공기 저항으로 감속, 깜빡이며 사라짐).
    static func burst(seed: UInt64, count: Int, at t: Double, reach: Double, life: Double = 0.9,
                      size: ClosedRange<Double> = 0.07...0.13, shape: Particle.Shape = .sparkle,
                      inner: Double = 0) -> [Particle] {
        guard t >= 0, t <= life else { return [] }
        var rng = Random(seed: seed)
        return (0..<count).map { i in
            let angle = Double(i) / Double(count) * 2 * .pi + rng.range(-0.25, 0.25)
            let dist = min(reach, particleBound - 0.05) * rng.range(0.55, 1.0)
            // `inner` 에서 출발 — 가운데(막 나온 포켓몬) 위에 반짝이가 뭉쳐 덮지 않게.
            let d = min(inner, dist) + (dist - min(inner, dist)) * easeOutCubic(t / (life * 0.75))
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

extension View {
    /// 스프라이트 모양 그대로의 또렷한 테두리(흰 실루엣의 푸른 윤곽, 붉은 에너지의 윤곽 등).
    ///
    /// 번진 그림자(`shadow(radius:)`)는 픽셀 스프라이트 둘레에 흐린 얼룩을 남겨 싸 보였다. 반경 0 그림자를
    /// 네 방향으로 겹치면 알파 모양을 `width` 만큼 넓힌 선명한 윤곽이 된다 — 뷰를 복제하지 않으므로 움직이는
    /// GIF 스프라이트가 여러 벌 로드되지 않는다. `width` 가 0 이면 그림자가 뒤에 숨어 아무것도 안 보인다
    /// (분기하지 않는다 — 분기하면 뷰 정체가 바뀌어 스프라이트 상태가 초기화된다).
    func celebrationRim(_ color: Color, width: CGFloat) -> some View {
        compositingGroup()
            .shadow(color: color, radius: 0, x: width, y: 0)
            .shadow(color: color, radius: 0, x: -width, y: 0)
            .shadow(color: color, radius: 0, x: 0, y: width)
            .shadow(color: color, radius: 0, x: 0, y: -width)
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
