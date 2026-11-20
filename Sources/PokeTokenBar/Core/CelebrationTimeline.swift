import Foundation

/// Which caption the celebration shows at a given moment.
enum CelebrationText: Equatable {
    case none, evolveAnnounce, evolveDone, hatchOh, hatchDone
}

/// One rendered instant of a celebration. Pure data: a renderer maps it to views.
struct CelebrationFrame: Equatable {
    var showsTarget = false
    var scale = 1.0
    var whiteness = 0.0
    var haloAlpha = 0.0
    var raysAlpha = 0.0
    // Optionals below: `nil` means "effect not active".
    var orbsProgress: Double?
    var flashProgress: Double?
    var starsProgress: Double?
    var sparkleProgress: Double?
    var crackLevel = 0
    var crackGlow = 0.0
    var eggRotation = 0.0   // radians
    var eggHop = 0.0        // pt, <= 0
    var eggOpacity = 1.0
    var targetOpacity = 1.0
    var shardsTime: Double?
    var text: CelebrationText = .none
}

private func clamp01(_ x: Double) -> Double { min(1, max(0, x)) }
private func easeOut(_ p: Double) -> Double { 1 - pow(1 - p, 3) }
private func easeIn(_ p: Double) -> Double { p * p }
private func backOut(_ p: Double) -> Double {
    let q = p - 1
    return 1 + 2.9 * q * q * q + 1.9 * q * q
}
private func lerp(_ a: Double, _ b: Double, _ p: Double) -> Double { a + (b - a) * p }
/// Progress of `t` through `[start, end]`, clamped to 0...1.
private func progress(_ t: Double, _ start: Double, _ end: Double) -> Double {
    clamp01((t - start) / (end - start))
}

struct CelebrationTimeline {
    enum Kind { case evolve, hatch }

    let kind: Kind
    let reduced: Bool
    let shiny: Bool

    init(kind: Kind, reduced: Bool, shiny: Bool) {
        self.kind = kind
        self.reduced = reduced
        self.shiny = shiny
    }

    /// The timeline of a queued celebration; nil for a Ditto reveal, which has no stage sequence.
    init?(_ celebration: CelebrationKind, reduced: Bool) {
        switch celebration {
        case .evolve(_, let to): self.init(kind: .evolve, reduced: reduced, shiny: to.isShiny)
        case .hatch(let to): self.init(kind: .hatch, reduced: reduced, shiny: to.isShiny)
        case .dittoReveal: return nil
        }
    }

    // MARK: Constants

    private static let reducedTotal = 4.5
    private static let reducedFade = 1.2
    private static let alternationStart = 2.4
    private static let burstStart = 7.4
    private static let evolveTextSwitch = 8.0
    private static let evolveEnd = 12.0
    private static let hatchTextSwitch = 6.4
    private static let hatchEnd = 10.0
    private static let shakes: [(start: Double, end: Double)] = [(1.0, 1.6), (2.8, 3.4), (4.2, 4.8)]
    private static let evolveWhitenessEnd = 8.6
    private static let evolveSparkleEnd = 9.5
    private static let hatchShardsEnd = 7.8
    private static let hatchSparkleEnd = 8.0

    /// 15 geometric intervals 0.8 -> 0.08, rescaled so they sum to exactly 5.0 s.
    static let alternationIntervals: [TimeInterval] = {
        let n = 15
        let ratio = pow(0.08 / 0.8, 1.0 / Double(n - 1))
        let raw = (0..<n).map { 0.8 * pow(ratio, Double($0)) }
        let scale = 5.0 / raw.reduce(0, +)
        return raw.map { $0 * scale }
    }()

    /// Cumulative end time of each alternation interval, in absolute seconds. The last one is pinned to
    /// `burstStart`, so every instant of the alternation phase lies inside an interval by construction.
    static let alternationEnds: [TimeInterval] = {
        var acc = alternationStart
        var ends = alternationIntervals.map { acc += $0; return acc }
        ends[ends.count - 1] = burstStart
        return ends
    }()

    // MARK: Public surface

    var total: TimeInterval {
        if reduced { return Self.reducedTotal }
        return kind == .evolve ? Self.evolveEnd : Self.hatchEnd
    }

    var skipTarget: TimeInterval {
        if reduced { return Self.reducedFade }
        return kind == .evolve ? 7.4 : 5.8
    }

    /// The reveal: from here the result is fully shown (the "Congratulations" / "hatched" caption, or the end
    /// of the cross-fade). A surface that stops after this point has shown the item: it counts as seen even if
    /// the caption hold is cut short. A sequence that keeps playing still finishes at `total`.
    var seenTime: TimeInterval {
        if reduced { return Self.reducedFade }
        return kind == .evolve ? Self.evolveTextSwitch : Self.hatchTextSwitch
    }

    /// From this time on, nothing the stage draws changes any more (only the caption, which it does not draw):
    /// the end of the cross-fade, the whiteness fading out of the revealed form, the last shell shard, the
    /// shiny sparkle. The stage stops redrawing there.
    var lastMotionTime: TimeInterval {
        if reduced { return Self.reducedFade }
        switch kind {
        case .evolve: return shiny ? Self.evolveSparkleEnd : Self.evolveWhitenessEnd
        case .hatch: return shiny ? Self.hatchSparkleEnd : Self.hatchShardsEnd
        }
    }

    /// Times (ascending, > 0) at which `frame(at:).text` changes.
    var textBoundaries: [TimeInterval] {
        if reduced { return [total] }
        return kind == .evolve ? [Self.evolveTextSwitch, Self.evolveEnd] : [Self.hatchTextSwitch, Self.hatchEnd]
    }

    func frame(at rawT: TimeInterval) -> CelebrationFrame {
        let t = min(total, max(0, rawT))
        if reduced { return reducedFrame(t) }
        return kind == .evolve ? evolveFrame(t) : hatchFrame(t)
    }

    // MARK: Reduced motion

    private func reducedFrame(_ t: Double) -> CelebrationFrame {
        var f = CelebrationFrame()
        let p = progress(t, 0, Self.reducedFade)
        f.eggOpacity = 1 - p
        f.targetOpacity = p
        f.showsTarget = p >= 1
        f.text = t < total ? (kind == .evolve ? .evolveDone : .hatchDone) : .none
        return f
    }

    // MARK: Evolve

    private func evolveFrame(_ t: Double) -> CelebrationFrame {
        var f = CelebrationFrame()
        f.text = t < Self.evolveTextSwitch ? .evolveAnnounce : (t < Self.evolveEnd ? .evolveDone : .none)

        if t < 1.2 {
            f.haloAlpha = lerp(0, 0.35, progress(t, 0, 1.2))
        } else if t < Self.alternationStart {
            let p = progress(t, 1.2, 2.4)
            f.whiteness = easeOut(p)
            f.orbsProgress = p
            f.haloAlpha = lerp(0.35, 0.5, p)
        } else if t < Self.burstStart {
            f.whiteness = 1
            f.haloAlpha = 0.5
            f.raysAlpha = lerp(0.12, 0.52, progress(t, Self.alternationStart, Self.burstStart))
            let ends = Self.alternationEnds
            let k = ends.prefix { $0 <= t }.count   // t < burstStart = ends.last: always a valid interval
            let start = k == 0 ? Self.alternationStart : ends[k - 1]
            let p = progress(t, start, ends[k])
            if p < 0.5 {
                f.showsTarget = k % 2 == 1
                f.scale = lerp(1, 0.5, easeIn(p * 2))
            } else {
                f.showsTarget = (k + 1) % 2 == 1
                f.scale = lerp(0.5, 1, easeOut((p - 0.5) * 2))
            }
        } else if t < 8.0 {
            let p = progress(t, Self.burstStart, 8.0)
            f.showsTarget = true
            f.whiteness = 1
            f.flashProgress = p
            f.starsProgress = p
            f.raysAlpha = lerp(0.52, 0, p)
            f.haloAlpha = lerp(0.5, 0, p)
        } else {
            f.showsTarget = true
            f.whiteness = 1 - progress(t, 8.0, Self.evolveWhitenessEnd)
            if t < 8.5 { f.scale = 1 + 0.12 * sin(.pi * (t - 8) / 0.5) }
            if shiny, t >= 8.1, t < Self.evolveSparkleEnd { f.sparkleProgress = progress(t, 8.1, Self.evolveSparkleEnd) }
        }
        return f
    }

    // MARK: Hatch

    private func hatchFrame(_ t: Double) -> CelebrationFrame {
        var f = CelebrationFrame()
        f.text = t < Self.hatchTextSwitch ? .hatchOh : (t < Self.hatchEnd ? .hatchDone : .none)
        f.showsTarget = t >= 6.2
        f.targetOpacity = 0

        // Shakes (egg only, before the shatter).
        for s in Self.shakes where t >= s.start && t <= s.end {
            let p = (t - s.start) / (s.end - s.start)
            f.eggRotation = sin(p * 3 * .pi) * 0.2 * (1 - 0.3 * p)
            f.eggHop = -abs(sin(p * 3 * .pi)) * 3
        }
        f.crackLevel = Self.shakes.filter { t + 1e-9 >= $0.start + 0.3 }.count

        if t < 6.0 {
            let light = progress(t, 5.0, 6.0)
            f.whiteness = light
            f.haloAlpha = light
            f.crackGlow = progress(t, 4.4, 5.0)
        } else {
            f.eggOpacity = 0
            f.crackLevel = 0
            f.haloAlpha = lerp(1, 0, progress(t, 6.0, 6.8))
            if t <= 6.5 { f.flashProgress = progress(t, 6.0, 6.5) }
            if t < Self.hatchShardsEnd { f.shardsTime = t - 6 }
        }
        if t >= 6.2 {
            let p = progress(t, 6.2, 6.8)
            f.targetOpacity = min(1, 2 * p)
            f.scale = backOut(p)
        }
        if shiny, t >= 6.6, t < Self.hatchSparkleEnd { f.sparkleProgress = progress(t, 6.6, Self.hatchSparkleEnd) }
        return f
    }
}
