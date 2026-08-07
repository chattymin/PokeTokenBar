import SwiftUI

/// 네 갈래 반짝임 하나. 가운데가 굵고 끝이 뾰족한 별 — 옆구리를 안쪽으로 당겨 만든다.
///
/// GIF 를 얹지 않고 직접 그리는 이유가 둘 있다. 받은 참고 그림은 검은 배경이라 화면에 얹으려면
/// 키잉이나 블렌드 모드가 필요한데, **블렌드는 CALayer 로 내려가 스크린샷 생성기의 오프스크린
/// 렌더에서 통째로 사라진다**(도감 실루엣에서 이미 겪었다). 그리고 도형이면 개수·크기·박자를
/// 자리마다 다르게 줄 수 있다 — 부화 순간에는 터뜨리고, 상세 화면에서는 잔잔하게.
struct SparkleShape: Shape {
    /// 옆구리를 얼마나 당길지(0에 가까울수록 뾰족하다).
    var waist: Double = 0.14

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let rx = rect.width / 2, ry = rect.height / 2
        let wx = rx * waist, wy = ry * waist
        var path = Path()
        path.move(to: CGPoint(x: c.x, y: c.y - ry))
        path.addQuadCurve(to: CGPoint(x: c.x + rx, y: c.y),
                          control: CGPoint(x: c.x + wx, y: c.y - wy))
        path.addQuadCurve(to: CGPoint(x: c.x, y: c.y + ry),
                          control: CGPoint(x: c.x + wx, y: c.y + wy))
        path.addQuadCurve(to: CGPoint(x: c.x - rx, y: c.y),
                          control: CGPoint(x: c.x - wx, y: c.y + wy))
        path.addQuadCurve(to: CGPoint(x: c.x, y: c.y - ry),
                          control: CGPoint(x: c.x - wx, y: c.y - wy))
        path.closeSubpath()
        return path
    }
}

/// 반짝임 하나의 자리와 박자. 난수를 안 쓴다 — 같은 개체는 언제 열어도 같은 그림이어야 하고,
/// 스크린샷도 그래야 재현된다.
struct SparkleSpec: Equatable, Sendable {
    /// 판 크기에 대한 비율(-0.5~0.5).
    let x: Double, y: Double
    /// 판 크기에 대한 지름 비율.
    let size: Double
    /// 깜빡임 위상(0~1) — 다 같이 깜빡이면 별이 아니라 조명이 된다.
    let phase: Double

    /// `count` 개를 스프라이트 둘레에 흩는다. 황금각으로 돌려 뭉치지 않게 하고, 반지름을
    /// 조금씩 달리해 원으로 안 보이게 한다.
    static func ring(count: Int, radius: Double = 0.42) -> [SparkleSpec] {
        guard count > 0 else { return [] }
        let golden = 2.399963
        return (0..<count).map { index in
            let angle = Double(index) * golden
            let spread = radius * (0.72 + 0.28 * Double((index * 5) % count) / Double(count))
            // 크기는 겹치지 않는 선에서 가장 크게 잡았다(6·7·9개 조합을 전수로 계산).
            // 예전 값(0.16~0.26)은 이웃과 최대 0.043 만큼 겹쳐 덩어리로 보였다.
            return SparkleSpec(x: cos(angle) * spread, y: sin(angle) * spread,
                               size: 0.10 + 0.08 * Double((index * 3) % 4) / 3,
                               phase: Double((index * 7) % count) / Double(count))
        }
    }
}

/// 이로치 반짝임. 스프라이트 위에 겹쳐 쓴다.
///
/// **이로치일 때만 쓴다** — 늘 반짝이면 이로치라는 신호가 아니라 배경 장식이 된다.
struct ShinySparkles: View {
    var specs: [SparkleSpec] = SparkleSpec.ring(count: 7)
    /// 한 번 깜빡이는 데 걸리는 시간. 짧으면 산만하고, 길면 멈춘 것처럼 보인다.
    var period: Double = 1.8
    /// 켜져 있는가. 부화 연출은 터지는 순간에만 켠다.
    var active: Bool = true

    #if DEBUG
    /// 반짝임이 **실제 화면에** 닿는지 테스트가 확인할 수 있게 생성 기록을 남긴다.
    /// 픽셀 색으로 재려 했더니 스프라이트 자체의 노랑에 묻혔고, 테스트 환경에서는 이로치
    /// 스프라이트가 캐시에 없어 오히려 색이 *줄어* 판정이 뒤집혔다.
    @MainActor static var constructed: [Int] = []
    @MainActor static func resetConstructed() { constructed = [] }
    #endif

    /// 금색 — 참고 그림과 같은 결로, 가운데가 희고 끝으로 갈수록 호박색.
    private var gold: RadialGradient {
        RadialGradient(colors: [Color(red: 1.0, green: 0.99, blue: 0.90),
                                Color(red: 1.0, green: 0.84, blue: 0.30),
                                Color(red: 0.98, green: 0.66, blue: 0.05)],
                       center: .center, startRadius: 0, endRadius: 12)
    }

    var body: some View {
        #if DEBUG
        let _ = { Self.constructed.append(specs.count) }()
        #endif
        return GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                ForEach(specs.indices, id: \.self) { index in
                    let spec = specs[index]
                    SparkleShape()
                        .fill(gold)
                        .frame(width: side * spec.size, height: side * spec.size)
                        .offset(x: side * spec.x, y: side * spec.y)
                        .scaleEffect(active ? 1 : 0.2)
                        .opacity(active ? 1 : 0)
                        // 위상이 다르므로 각자 다른 시점에 뜬다 — 한꺼번에 깜빡이면 조명이 된다.
                        .animation(.easeInOut(duration: period / 2)
                            .repeatForever(autoreverses: true)
                            .delay(period * spec.phase), value: active)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}
