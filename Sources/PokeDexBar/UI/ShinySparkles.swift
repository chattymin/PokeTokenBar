import SwiftUI

/// 네 갈래 반짝임 하나. 가운데가 굵고 끝이 뾰족한 별 — 옆구리를 안쪽으로 당겨 만든다.
///
/// GIF 를 얹지 않고 직접 그리는 이유가 둘 있다. 받은 참고 그림은 검은 배경이라 화면에 얹으려면
/// 키잉이나 블렌드 모드가 필요한데, **블렌드는 CALayer 로 내려가 스크린샷 생성기의 오프스크린
/// 렌더에서 통째로 사라진다**(도감 실루엣에서 이미 겪었다). 그리고 도형이면 개수·크기·박자를
/// 자리마다 다르게 줄 수 있다.
///
/// 같은 이유로 **후광에 `.blur` 를 쓰지 않는다** — 그리기 단계에 남는 방사형 그라디언트로 낸다.
struct SparkleShape: Shape {
    /// 옆구리를 얼마나 당길지(0에 가까울수록 뾰족하다).
    var waist: Double = 0.12

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

/// 반짝임 하나의 자리·크기·순서. 난수를 안 쓴다 — 같은 개체는 언제 열어도 같은 그림이어야 하고,
/// 스크린샷도 그래야 재현된다.
struct SparkleSpec: Equatable, Sendable {
    /// 판 크기에 대한 비율(-0.5~0.5).
    let x: Double, y: Double
    /// 판 크기에 대한 지름 비율.
    let size: Double
    /// 터지는 순서(0~1) — 다 같이 뜨면 "뾰로롱"이 아니라 한 번의 플래시가 된다.
    let phase: Double
    /// 기울기(도). 전부 축에 정렬돼 있으면 도장을 찍은 것처럼 보인다.
    let tilt: Double
    /// 큰 별인가. 몇 개만 크게 두고 나머지를 작게 둬야 무리에 위계가 생긴다 —
    /// 같은 크기가 늘어서면 장식용 점처럼 보인다.
    let isHero: Bool

    /// `count` 개를 스프라이트 둘레에 흩는다. 황금각으로 돌려 뭉치지 않게 하고, 반지름을
    /// 조금씩 달리해 원으로 안 보이게 한다.
    static func ring(count: Int, radius: Double = 0.42) -> [SparkleSpec] {
        guard count > 0 else { return [] }
        let goldenAngle = 2.399963, goldenRatio = 0.6180339887
        return (0..<count).map { index in
            let angle = Double(index) * goldenAngle
            let spread = radius * (0.72 + 0.28 * Double((index * 5) % count) / Double(count))
            // 셋 중 하나만 크게. 전부 크면 겹치고, 전부 작으면 눈에 안 띈다.
            let hero = index % 3 == 1
            return SparkleSpec(
                x: cos(angle) * spread, y: sin(angle) * spread,
                // 큰 별은 작은 별의 1.5배 넘게 — 차이가 작으면 위계가 안 읽힌다.
                // 값은 '같이 떠 있는 별끼리 안 겹친다' 를 6·7·9개에서 전수 계산해 골랐다.
                size: hero ? 0.22 : 0.080 + 0.030 * Double(index % 3),
                // 순서는 황금비로 흩는다. 예전엔 `(index * 7) % count` 였는데 **7개일 때 전부 0**
                // 이 되어(7과 7이 서로소가 아니다) 하나씩 뜨는 대신 한꺼번에 번쩍이고 사라졌다.
                phase: (Double(index) * goldenRatio).truncatingRemainder(dividingBy: 1),
                tilt: (Double(index) * goldenRatio * 90).truncatingRemainder(dividingBy: 45) - 22.5,
                isHero: hero)
        }
    }
}

/// 반짝임 하나가 지나가는 자세. `KeyframeAnimator` 가 보간한다.
struct SparklePose: Equatable, Sendable {
    var scale: Double = 0
    var opacity: Double = 0
    /// 뜨는 동안 살짝 돈다 — 제자리에서 커졌다 작아지기만 하면 스티커처럼 보인다.
    var spin: Double = -18
    /// 바깥으로 조금 흘러간다. 멈춰 있는 반짝임은 붙여 놓은 것처럼 보인다.
    var drift: Double = 0
}

/// 이로치 반짝임 — **한 번 터지고 사라진다.**
///
/// 원작의 이로치 이펙트는 그 포켓몬이 *등장하는 순간* 한 번만 난다. 계속 반짝이면 "이 아이는
/// 특별하다"가 아니라 배경 장식이 되고, 상세 화면을 열어 둔 내내 시선이 그쪽으로 끌린다.
///
/// 결이 싸구려로 보이지 않게 넣은 것들: **크기 위계**(큰 별 몇 개 + 작은 별), **기울기**(축
/// 정렬을 깨서 도장 느낌 제거), **회전과 흘러감**(제자리 확대·축소는 스티커처럼 보인다),
/// **후광**(별 뒤에 옅은 방사형 빛), **비대칭 감속**(빨리 뜨고 천천히 진다).
///
/// `trigger` 가 바뀔 때마다 다시 터진다 — 다른 개체를 열면 그 개체의 반짝임이 새로 난다.
struct ShinySparkles: View {
    var specs: [SparkleSpec] = SparkleSpec.ring(count: 7)
    /// 값이 바뀌면 한 번 터진다.
    var trigger: Int

    #if DEBUG
    /// 반짝임이 **실제 화면에** 닿는지 테스트가 확인할 수 있게 생성 기록을 남긴다.
    /// 픽셀 색으로 재려 했더니 스프라이트 자체의 노랑에 묻혔고, 테스트 환경에서는 이로치
    /// 스프라이트가 캐시에 없어 오히려 색이 *줄어* 판정이 뒤집혔다.
    @MainActor static var constructed: [Int] = []
    @MainActor static func resetConstructed() { constructed = [] }
    #endif

    // 타이밍 상수는 `nonisolated` 이다. `View` 는 메인 액터에 묶이지만 이 값들은 그냥 숫자라,
    // 묶어 두면 스크린샷 생성기처럼 액터 밖에서 길이를 계산하는 곳이 전부 경고가 된다.

    /// 별 하나가 뜨고 지는 데 걸리는 시간.
    nonisolated static let pop = 0.62
    /// 첫 별과 마지막 별 사이의 간격 — 이게 "뾰로롱"의 정체다. 0이면 한 번의 플래시가 된다.
    nonisolated static let stagger = 0.34
    /// 연출 전체 길이.
    nonisolated static var duration: Double { stagger + pop }

    /// 금색 — 가운데가 희고 끝으로 갈수록 호박색. 끝을 완전히 투명하게 두어 뾰족한 끝이
    /// 잘린 것처럼 보이지 않게 한다.
    private var gold: RadialGradient {
        RadialGradient(colors: [Color(red: 1.00, green: 1.00, blue: 0.96),
                                Color(red: 1.00, green: 0.90, blue: 0.55),
                                Color(red: 0.99, green: 0.72, blue: 0.16)],
                       center: .center, startRadius: 0, endRadius: 14)
    }

    /// 별 뒤에 까는 옅은 빛. `.blur` 대신 방사형 그라디언트라 오프스크린 렌더에서도 남는다.
    private var halo: RadialGradient {
        RadialGradient(colors: [Color(red: 1.0, green: 0.93, blue: 0.62).opacity(0.55),
                                Color(red: 1.0, green: 0.80, blue: 0.35).opacity(0.16),
                                .clear],
                       center: .center, startRadius: 0, endRadius: 22)
    }

    var body: some View {
        #if DEBUG
        let _ = { Self.constructed.append(specs.count) }()
        #endif
        return GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                ForEach(specs.indices, id: \.self) { index in
                    star(specs[index], side: side)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .allowsHitTesting(false)   // 지나가는 연출이라 아래 버튼을 가리면 안 된다
    }

    private func star(_ spec: SparkleSpec, side: CGFloat) -> some View {
        let wait = Self.stagger * spec.phase      // 순서대로 조금씩 늦게 터진다
        let box = side * spec.size
        // 바깥을 향해 흘러간다 — 중심에서 멀어지는 방향이 자연스럽다.
        let length = max(0.0001, hypot(spec.x, spec.y))
        let drift = CGSize(width: spec.x / length, height: spec.y / length)
        return KeyframeAnimator(initialValue: SparklePose(), trigger: trigger) { pose in
            ZStack {
                // 후광이 먼저 — 큰 별에만 붙인다. 전부 붙이면 뿌연 덩어리가 된다.
                if spec.isHero {
                    Circle().fill(halo).frame(width: box * 2.2, height: box * 2.2)
                        .opacity(pose.opacity * 0.85)
                }
                SparkleShape()
                    .fill(gold)
                    .frame(width: box, height: box)
                    .rotationEffect(.degrees(spec.tilt + pose.spin))
                    .opacity(pose.opacity)
            }
            .scaleEffect(pose.scale)
            .offset(x: side * spec.x + drift.width * pose.drift,
                    y: side * spec.y + drift.height * pose.drift)
        } keyframes: { _ in
            // 빨리 뜨고 천천히 진다 — 대칭이면 깜빡이는 전구처럼 보인다.
            KeyframeTrack(\.scale) {
                LinearKeyframe(0, duration: wait)
                SpringKeyframe(1.18, duration: Self.pop * 0.26, spring: .bouncy)
                CubicKeyframe(1.0, duration: Self.pop * 0.16)
                CubicKeyframe(0, duration: Self.pop * 0.58)
            }
            KeyframeTrack(\.opacity) {
                LinearKeyframe(0, duration: wait)
                LinearKeyframe(1, duration: Self.pop * 0.18)
                LinearKeyframe(1, duration: Self.pop * 0.30)
                CubicKeyframe(0, duration: Self.pop * 0.52)
            }
            KeyframeTrack(\.spin) {
                LinearKeyframe(-18, duration: wait)
                CubicKeyframe(4, duration: Self.pop * 0.42)
                CubicKeyframe(14, duration: Self.pop * 0.58)
            }
            KeyframeTrack(\.drift) {
                LinearKeyframe(0, duration: wait)
                CubicKeyframe(2, duration: Self.pop * 0.42)
                CubicKeyframe(9, duration: Self.pop * 0.58)
            }
        }
    }
}
