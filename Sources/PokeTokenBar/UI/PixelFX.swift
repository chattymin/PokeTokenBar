import SwiftUI

// 도트 그림판 — 연출의 빛·입자·몬스터볼을 스프라이트와 같은 "도트"로 그린다.
//
// 왜: 매끈한 벡터 선·그라데이션을 도트 스프라이트 위에 얹으면 아무리 다듬어도 두 그림체가 섞여 "앱 효과"로
// 보였다(사용자: "허접한 느낌이 가시질 않네"). 그래서 연출을 저해상도 격자(칸 한 변 ≈ 48셀)에 직접 찍고,
// 셀을 그대로 키워 그린다. 반투명은 섞지 않는다 — 게임 화면처럼 **바둑판 디더링(Bayer 4×4)** 으로 표현해
// 셀마다 색이 하나다. 격자는 값 타입이고 그리기는 전부 순수 함수라, 테스트가 셀 단위로 결정적으로 검사한다.
//
// 좌표: 다른 연출 코드와 같은 "칸 단위"(칸 한 변 = 1, 격자 중심 원점, y 아래로). `unit` 이 칸 단위 1 의 셀 수다.

struct PixelGrid {
    let cols: Int
    let rows: Int
    /// 칸 단위 1 이 몇 셀인가.
    let unit: Double
    /// 셀마다 팔레트 번호(0 = 빈 칸). 나중에 찍은 것이 덮는다.
    private(set) var cells: [UInt8]
    private(set) var palette: [Color] = []
    private var lookup: [Color: UInt8] = [:]

    init(cols: Int, rows: Int, unit: Double) {
        self.cols = max(0, cols)
        self.rows = max(0, rows)
        self.unit = unit
        cells = Array(repeating: 0, count: self.cols * self.rows)
    }

    /// 칸 한 변이 `box` pt 일 때의 셀 크기(pt). 칸 한 변 ≈ 48셀을 목표로 하되 0.5pt 단위로 맞춘다 —
    /// 레티나에서 셀이 정수 픽셀이 돼야 셀마다 굵기가 들쭉날쭉하지 않다.
    static func cellSize(box: CGFloat) -> CGFloat {
        max(0.5, (box / 48 * 2).rounded() / 2)
    }

    // MARK: 디더링

    private static let bayer: [Double] = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5].map { ($0 + 0.5) / 16 }

    /// 이 셀이 불투명도 `alpha` 에서 칠해지나(Bayer 4×4 순차 디더링 — 격자에 고정된 무늬라 반짝이지 않는다).
    ///
    /// 불투명도는 **네 단계(¼·½·¾·1)로 끊는다.** 16단계를 다 쓰면 셀마다 무늬가 달라 화면 전체가 자잘한 점
    /// 노이즈가 됐다(실측). 단계를 줄이면 바둑판·¼ 격자 같은 또렷한 무늬만 남아 도트 게임의 디더링처럼 읽힌다.
    static func covers(_ alpha: Double, _ i: Int, _ j: Int) -> Bool {
        let level = quantized(alpha)
        if level >= 1 { return true }
        guard level > 0 else { return false }
        return level > bayer[(j & 3) * 4 + (i & 3)]
    }

    static func quantized(_ alpha: Double) -> Double {
        switch alpha {
        case ..<0.12: 0
        case ..<0.37: 0.25
        case ..<0.62: 0.5
        case ..<0.87: 0.75
        default: 1
        }
    }

    /// 색을 흰색 쪽으로 `t`(0…1)만큼 — 빛의 띠(심지·바깥 번짐)를 같은 계열의 단색으로 만든다.
    static func lighten(_ color: Color, _ t: Double) -> Color {
        guard let c = NSColor(color).usingColorSpace(.sRGB) else { return color }
        let k = CGFloat(t)
        return Color(red: Double(c.redComponent + (1 - c.redComponent) * k),
                     green: Double(c.greenComponent + (1 - c.greenComponent) * k),
                     blue: Double(c.blueComponent + (1 - c.blueComponent) * k))
    }

    /// 빛의 세기(0…1) → 단색 띠. 가운데는 거의 흰색, 그다음 본색, 바깥은 옅은 색 — 반투명으로 섞는 대신
    /// 도트 게임처럼 단색 띠를 겹치고, 띠 경계만 바둑판으로 잇는다. 세기가 약해지면 띠가 **줄어든다**.
    static func band(_ a: Double, core: Color, mid: Color, outer: Color) -> (Color, Double)? {
        let edge = 0.06
        if a >= 0.62 { return (core, 1) }
        if a >= 0.62 - edge { return (core, 0.5) }
        if a >= 0.34 { return (mid, 1) }
        if a >= 0.34 - edge { return (mid, 0.5) }
        if a >= 0.15 { return (outer, 1) }
        if a >= 0.15 - edge { return (outer, 0.5) }
        return nil
    }

    // MARK: 셀

    /// 칸 단위 → 셀 좌표(실수). 셀 (i, j) 의 중심은 (i + 0.5, j + 0.5).
    func cx(_ x: Double) -> Double { Double(cols) / 2 + x * unit }
    func cy(_ y: Double) -> Double { Double(rows) / 2 + y * unit }
    /// 셀 (i, j) 중심의 칸 단위 좌표.
    func boxX(_ i: Int) -> Double { (Double(i) + 0.5 - Double(cols) / 2) / unit }
    func boxY(_ j: Int) -> Double { (Double(j) + 0.5 - Double(rows) / 2) / unit }
    /// 셀 한 개의 칸 단위 길이.
    var cellLength: Double { 1 / unit }

    func color(at i: Int, _ j: Int) -> Color? {
        guard i >= 0, j >= 0, i < cols, j < rows else { return nil }
        let k = cells[j * cols + i]
        return k == 0 ? nil : palette[Int(k) - 1]
    }

    private mutating func index(of color: Color) -> UInt8 {
        if let k = lookup[color] { return k }
        guard palette.count < 255 else { return UInt8(palette.count) }   // 넘치면 마지막 색으로(연출엔 수십 색이면 충분)
        palette.append(color)
        let k = UInt8(palette.count)
        lookup[color] = k
        return k
    }

    /// 셀 하나 — 불투명도는 디더링으로. 격자 밖은 조용히 버린다(입자가 가장자리를 넘어도 안전).
    mutating func plot(_ i: Int, _ j: Int, _ color: Color, alpha: Double = 1) {
        guard i >= 0, j >= 0, i < cols, j < rows, Self.covers(alpha, i, j) else { return }
        cells[j * cols + i] = index(of: color)
    }

    /// 칸 단위 사각 범위 안의 셀마다 `shade(x, y)` 가 돌려준 (색, 불투명도)로 찍는다 — 모든 도형의 바탕.
    mutating func fill(x0: Double, y0: Double, x1: Double, y1: Double,
                       _ shade: (_ x: Double, _ y: Double, _ i: Int, _ j: Int) -> (Color, Double)?) {
        let i0 = max(0, Int(cx(x0).rounded(.down))), i1 = min(cols - 1, Int(cx(x1).rounded(.up)))
        let j0 = max(0, Int(cy(y0).rounded(.down))), j1 = min(rows - 1, Int(cy(y1).rounded(.up)))
        guard i0 <= i1, j0 <= j1 else { return }
        for j in j0...j1 {
            let y = boxY(j)
            for i in i0...i1 {
                if let (color, alpha) = shade(boxX(i), y, i, j) { plot(i, j, color, alpha: alpha) }
            }
        }
    }

    // MARK: 도형

    /// 빛 번짐 — 가운데 세기 `alpha`, 반경 끝에서 0. 세기를 단색 띠(심지·본색·옅은 색)로 그린다.
    mutating func glow(x: Double, y: Double, radius r: Double, color: Color, alpha: Double) {
        guard alpha > 0.01, r > 0 else { return }
        let core = Self.lighten(color, 0.8), outer = Self.lighten(color, 0.45)
        fill(x0: x - r, y0: y - r, x1: x + r, y1: y + r) { px, py, _, _ in
            let d = ((px - x) * (px - x) + (py - y) * (py - y)).squareRoot() / r
            return d < 1 ? Self.band(alpha * pow(1 - d, 1.1), core: core, mid: color, outer: outer) : nil
        }
    }

    /// 가운데가 빈 후광 — `inner` 에서 가장 짙고 `outer` 에서 0(본색 → 옅은 색 띠).
    mutating func halo(x: Double = 0, y: Double = 0, inner: Double, outer: Double, color: Color, alpha: Double) {
        guard alpha > 0.01, outer > inner else { return }
        let pale = Self.lighten(color, 0.45)
        fill(x0: x - outer, y0: y - outer, x1: x + outer, y1: y + outer) { px, py, _, _ in
            let d = ((px - x) * (px - x) + (py - y) * (py - y)).squareRoot()
            guard d >= inner, d < outer else { return nil }
            return Self.band(alpha * (1 - (d - inner) / (outer - inner)), core: color, mid: color, outer: pale)
        }
    }

    mutating func ellipse(x: Double, y: Double, rx: Double, ry: Double, color: Color, alpha: Double = 1) {
        guard alpha > 0.01, rx > 0, ry > 0 else { return }
        fill(x0: x - rx, y0: y - ry, x1: x + rx, y1: y + ry) { px, py, _, _ in
            let u = (px - x) / rx, v = (py - y) / ry
            return u * u + v * v <= 1 ? (color, alpha) : nil
        }
    }

    /// 고리 — 등급색 띠, 두께가 셀 셋 이상이면 흰 심지. 사라질 땐 디더링하지 않고 **가늘어진다**
    /// (디더링한 고리는 점선처럼 끊겨 보였다).
    mutating func ring(x: Double = 0, y: Double = 0, radius: Double, width: Double, color: Color, alpha: Double) {
        guard alpha > 0.15, radius > 0 else { return }
        let half = max(width / 2 * min(1, alpha * 1.3), cellLength * 0.55)
        let core = width * unit >= 3 ? half * 0.4 : -1
        let outer = radius + half
        fill(x0: x - outer, y0: y - outer, x1: x + outer, y1: y + outer) { px, py, _, _ in
            let off = abs(((px - x) * (px - x) + (py - y) * (py - y)).squareRoot() - radius)
            guard off <= half else { return nil }
            return (off <= core ? .white : color, 1)
        }
    }

    /// 굵기 `thickness` 셀의 선 — 불투명도는 시작 `alpha0` 에서 끝 `alpha1` 로.
    mutating func line(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, thickness: Int = 1, color: Color,
                       alpha0: Double = 1, alpha1: Double = 1) {
        let dx = cx(x1) - cx(x0), dy = cy(y1) - cy(y0)
        let steps = max(1, Int(max(abs(dx), abs(dy)).rounded(.up)))
        let lo = -(thickness - 1) / 2, hi = thickness / 2
        var last: (Int, Int)?
        for s in 0...steps {
            let u = Double(s) / Double(steps)
            let i = Int((cx(x0) + dx * u).rounded(.down)), j = Int((cy(y0) + dy * u).rounded(.down))
            if let l = last, l == (i, j) { continue }
            last = (i, j)
            let a = alpha0 + (alpha1 - alpha0) * u
            for oj in lo...hi { for oi in lo...hi { plot(i + oi, j + oj, color, alpha: a) } }
        }
    }

    /// 꺾은선의 앞 `upTo`(0…1, 길이 비율)만큼.
    mutating func polyline(_ points: [(Double, Double)], upTo: Double = 1, thickness: Int = 1, color: Color,
                           alpha: Double = 1) {
        guard points.count > 1, upTo > 0 else { return }
        let lengths = zip(points, points.dropFirst()).map { a, b in hypot(b.0 - a.0, b.1 - a.1) }
        var remain = lengths.reduce(0, +) * min(1, upTo)
        for (k, len) in lengths.enumerated() where remain > 0 {
            let a = points[k], b = points[k + 1]
            let u = min(1, remain / max(len, 1e-9))
            line(a.0, a.1, a.0 + (b.0 - a.0) * u, a.1 + (b.1 - a.1) * u, thickness: thickness, color: color,
                 alpha0: alpha, alpha1: alpha)
            remain -= len
        }
    }

    /// 다각형 채우기(짝홀 규칙). `alphaAt` 이 있으면 셀마다 불투명도를 정한다.
    mutating func polygon(_ points: [(Double, Double)], color: Color, alpha: Double = 1,
                          alphaAt: ((Double, Double) -> Double)? = nil) {
        guard points.count > 2, alpha > 0.01 else { return }
        let xs = points.map(\.0), ys = points.map(\.1)
        fill(x0: xs.min()!, y0: ys.min()!, x1: xs.max()!, y1: ys.max()!) { px, py, _, _ in
            var inside = false
            var k = points.count - 1
            for n in 0..<points.count {
                let (xi, yi) = points[n], (xk, yk) = points[k]
                if (yi > py) != (yk > py), px < (xk - xi) * (py - yi) / (yk - yi) + xi { inside.toggle() }
                k = n
            }
            guard inside else { return nil }
            return (color, alpha * (alphaAt?(px, py) ?? 1))
        }
    }

    /// 한 점에서 뻗는 빛줄기 — 뿌리는 희고 가늘며, 끝으로 갈수록 넓어지고 옅어진다.
    mutating func beam(x: Double, y: Double, angle: Double, length: Double, width: Double, color: Color,
                       alpha: Double) {
        guard alpha > 0.01, length > 0 else { return }
        let dx = cos(angle), dy = sin(angle)
        let r = length + width
        let minHalf = cellLength * 0.5   // 닫힘 안에서 self 를 읽으면 fill(mutating)과 접근이 겹친다
        let pale = Self.lighten(color, 0.45)
        fill(x0: x - r, y0: y - r, x1: x + r, y1: y + r) { px, py, _, _ in
            let along = (px - x) * dx + (py - y) * dy
            guard along >= 0, along <= length else { return nil }
            let t = along / length
            let across = abs(-(px - x) * dy + (py - y) * dx)
            guard across <= max(minHalf, width / 2 * (0.15 + 0.85 * t)) else { return nil }
            // 단색 마디: 흰 뿌리 → 본색 → 옅은 끝. 세기가 약하면 빛줄기가 짧아진다(옅어지지 않고).
            guard t <= alpha else { return nil }
            return (t < 0.2 ? .white : (t < 0.65 ? color : pale), t > alpha - 0.08 ? 0.5 : 1)
        }
    }

    /// 도트 반짝이 — 십자 팔(안쪽 흰색, 끝 등급색), 클수록 대각선 점. 사라질 땐 옅어지지 않고 **작아진다**
    /// (도트 게임의 반짝이처럼 — 디더링된 반짝이는 부서진 점으로 보인다).
    mutating func sparkle(x: Double, y: Double, size: Double, color: Color, opacity: Double) {
        guard opacity > 0.05 else { return }
        let i = Int(cx(x).rounded(.down)), j = Int(cy(y).rounded(.down))
        let arm = Int((size * unit / 2 * 1.3 * min(1, opacity * 1.2)).rounded())
        guard arm >= 1 else { plot(i, j, .white); return }
        plot(i, j, .white)
        for k in 1...arm {
            let c: Color = k <= max(1, arm / 2) ? .white : color
            plot(i + k, j, c); plot(i - k, j, c); plot(i, j + k, c); plot(i, j - k, c)
        }
        if arm >= 3 {
            for (oi, oj) in [(1, 1), (1, -1), (-1, 1), (-1, -1)] { plot(i + oi, j + oj, color) }
        }
    }

    /// 다섯 갈래 노란 별 — 주황 테두리 + 노란 속(같은 별을 한 셀 줄여 겹친다).
    mutating func star(x: Double, y: Double, size: Double, rotation: Double, opacity: Double) {
        guard opacity > 0.05 else { return }
        func points(_ r: Double) -> [(Double, Double)] {
            (0..<10).map { k in
                let a = -Double.pi / 2 + Double(k) * .pi / 5 + rotation
                let len = k.isMultiple(of: 2) ? r : r * 0.45
                return (x + len * cos(a), y + len * sin(a))
            }
        }
        let r = size / 2 * min(1, opacity * 1.3)
        polygon(points(r), color: Color(red: 0.78, green: 0.42, blue: 0.02))
        polygon(points(max(0, r - cellLength * 1.2)), color: Color(red: 1, green: 0.86, blue: 0.2))
        plot(Int(cx(x).rounded(.down)), Int(cy(y - r * 0.2).rounded(.down)), Color(red: 1, green: 0.98, blue: 0.75))
    }

    /// 알 껍질 조각 — 크림색(가끔 초록 무늬) 속에 한 셀 짙은 테두리.
    mutating func shard(x: Double, y: Double, size: Double, rotation: Double, seed: Int, opacity: Double) {
        guard opacity > 0.05 else { return }
        var rng = CelebrationFX.Random(seed: UInt64(seed))
        let corners = 3 + seed % 2
        let jitter = (0..<corners).map { _ in (rng.range(-0.35, 0.35), rng.range(0.7, 1.15)) }
        func points(_ r: Double) -> [(Double, Double)] {
            (0..<corners).map { k in
                let a = rotation + Double(k) / Double(corners) * 2 * .pi + jitter[k].0
                return (x + r * jitter[k].1 * cos(a), y + r * jitter[k].1 * sin(a))
            }
        }
        let r = size / 2 * min(1, opacity * 1.5)
        polygon(points(r), color: EggPalette.outline)
        polygon(points(max(0, r - cellLength)), color: seed % 3 == 0 ? EggPalette.spot : EggPalette.shell)
    }

    // MARK: 몬스터볼

    struct Ball {
        var x: Double, y: Double, diameter: Double
        var spin: Double = 0, tilt: Double = 0
        var open: Double = 0, buttonRed: Double = 0, buttonDark: Double = 0
        /// 닫힐 때 볼 전체가 하얗게 번쩍이는 정도.
        var flash: Double = 0
        var alpha: Double = 1
    }

    /// 도트 몬스터볼 — 셀마다 "볼 좌표"로 되돌려(기울기·회전의 역변환) 영역별 색을 고른다. 그래서 돌고
    /// 기울어도 도트가 깨지지 않는다. 위 덮개는 열린 만큼 들리며 납작해지고, 그 아래로 빛나는 입구가 보인다.
    mutating func pokeBall(_ b: Ball) {
        guard b.alpha > 0.01, b.diameter > 0 else { return }
        let r = b.diameter / 2
        let o = cellLength / r                      // 한 셀(볼 반지름 단위)
        let lift = 0.85 * b.open, squash = 1 - 0.45 * b.open
        let reach = r * (1.25 + lift)
        let tilt = b.tilt * .pi / 180, spin = b.spin * .pi / 180
        let black = Color(white: 0.09)
        let redLight = Color(red: 1, green: 0.45, blue: 0.4), red = Color(red: 0.9, green: 0.1, blue: 0.13)
        let redDark = Color(red: 0.55, green: 0.03, blue: 0.06)
        let white = Color.white, gray = Color(red: 0.74, green: 0.75, blue: 0.8)
        fill(x0: b.x - reach, y0: b.y - reach, x1: b.x + reach, y1: b.y + reach) { px, py, i, j in
            // 화면 → 볼 좌표: 바닥점 기준 기울기, 중심 기준 회전을 되돌린다.
            var u = (px - b.x) / r, v = (py - b.y) / r - 1
            (u, v) = (u * cos(-tilt) - v * sin(-tilt), u * sin(-tilt) + v * cos(-tilt))
            v += 1
            (u, v) = (u * cos(-spin) - v * sin(-spin), u * sin(-spin) + v * cos(-spin))
            func shellColor(_ u: Double, _ v: Double, top: Bool) -> Color {
                let d = (u * u + v * v).squareRoot()
                if d > 1 - o * 1.1 || abs(v) < 0.13 { return black }
                if top, pow((u + 0.4) / 0.2, 2) + pow((v + 0.55) / 0.11, 2) <= 1 { return white }
                let lit = -0.6 * u - 0.8 * v
                if top { return lit > 0.55 ? redLight : (lit < -0.15 ? redDark : red) }
                return lit < -0.45 || (lit < -0.2 && PixelGrid.covers(0.5, i, j)) ? gray : white
            }
            func button(_ u: Double, _ v: Double) -> Color? {
                let d = (u * u + v * v).squareRoot()
                guard d <= 0.36 else { return nil }
                if d > 0.27 { return black }
                if d > 0.17 { return white }
                if PixelGrid.covers(b.buttonDark, i, j) { return Color(white: 0.42) }
                return PixelGrid.covers(b.buttonRed, i, j) ? Color(red: 1, green: 0.18, blue: 0.18) : white
            }
            var c: Color?
            if b.open > 0.01 {
                let vl = (v + lift) / squash
                if vl <= 0, u * u + vl * vl <= 1 {
                    c = shellColor(u, vl, top: true)
                } else if let bt = button(u, v) {
                    c = bt
                } else if pow(u / 0.88, 2) + pow(v / (0.32 * b.open + 0.01), 2) <= 1 {
                    let d = (pow(u / 0.88, 2) + pow(v / (0.32 * b.open + 0.01), 2)).squareRoot()
                    c = d > 0.86 ? black : (d < 0.4 ? white : (d < 0.7 ? Color(red: 1, green: 0.6, blue: 0.55) : redDark))
                } else if v >= 0, u * u + v * v <= 1 {
                    c = shellColor(u, v, top: false)
                }
            } else if u * u + v * v <= 1 {
                c = button(u, v) ?? shellColor(u, v, top: v < 0)
            }
            guard var color = c else { return nil }
            if PixelGrid.covers(b.flash, i, j) { color = .white }
            return (color, b.alpha)
        }
    }

    // MARK: 출력

    /// 같은 색이 가로로 이어진 셀을 한 사각형으로 묶어 색마다 경로 하나로 칠한다(채우기 호출 = 색 수).
    func paths(origin: CGPoint, cell: CGFloat) -> [(Color, Path)] {
        var paths = Array(repeating: Path(), count: palette.count + 1)
        for j in 0..<rows {
            var i = 0
            while i < cols {
                let k = cells[j * cols + i]
                guard k != 0 else { i += 1; continue }
                var end = i + 1
                while end < cols, cells[j * cols + end] == k { end += 1 }
                paths[Int(k)].addRect(CGRect(x: origin.x + CGFloat(i) * cell, y: origin.y + CGFloat(j) * cell,
                                             width: CGFloat(end - i) * cell, height: cell))
                i = end
            }
        }
        return palette.enumerated().map { ($0.element, paths[$0.offset + 1]) }
    }
}

/// 도트 그림판을 그리는 뷰 — 크기는 부모가 정한다(칸 또는 빛 층). `box` 는 칸 한 변(pt)으로, 셀 크기와
/// 칸 단위를 정한다(헤더 칸 76pt → 셀 1.5pt, 펫 128pt → 셀 2.5pt).
@MainActor
struct PixelCanvas: View {
    let box: CGFloat
    let draw: (inout PixelGrid) -> Void

    var body: some View {
        Canvas { ctx, size in
            let cell = PixelGrid.cellSize(box: box)
            // 셀 수를 짝수로 — 격자 중심이 셀 경계에 와야 칸 중심 대칭 도형이 한쪽으로 치우치지 않는다.
            let cols = Int(size.width / cell) & ~1, rows = Int(size.height / cell) & ~1
            var grid = PixelGrid(cols: cols, rows: rows, unit: Double(box / cell))
            draw(&grid)
            let origin = CGPoint(x: (size.width - CGFloat(cols) * cell) / 2, y: (size.height - CGFloat(rows) * cell) / 2)
            for (color, path) in grid.paths(origin: origin, cell: cell) {
                ctx.fill(path, with: .color(color))
            }
        }
        .allowsHitTesting(false)
    }
}
