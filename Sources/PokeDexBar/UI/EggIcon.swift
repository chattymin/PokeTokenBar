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
struct HatchedRevealView: View {
    let individual: Individual
    let store: PlayerStore
    /// 종 이름을 아는 진화 라인. 없으면 번호로 떨어지고 `onNeedLine` 으로 받아온다.
    var line: EvoLine?
    var onNeedLine: (Int) -> Void = { _ in }
    let onDone: () -> Void

    private var l: L { store.l }

    private var displayName: String {
        let species = line?.localizedName(individual.speciesID, store.language)
            ?? "#\(individual.speciesID)"
        return individual.displayName(speciesName: species, store.language)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.84)
            VStack(spacing: 6) {
                SpriteView(speciesID: individual.speciesID, form: individual.spriteForm,
                           size: 64, animated: true, shiny: individual.shiny, antialias: true)
                    .frame(width: 64, height: 64)
                HStack(spacing: 5) {
                    Text(displayName).font(.system(size: 12, weight: .semibold))
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
        }
        .contentShape(Rectangle())
        .onTapGesture { onDone() }
        .task(id: individual.baseID) {
            if line == nil { onNeedLine(individual.baseID) }
        }
        .task {
            try? await Task.sleep(for: .seconds(2.4))
            if !Task.isCancelled { onDone() }
        }
    }
}
