import AppKit
import SwiftUI

// MARK: - Style

/// Colours of the celebration light. Blue on purpose: a white silhouette alone vanishes on a light
/// popover, so the silhouette, stars and orbs always carry this glow and halos/rays are tinted.
enum CelebrationStyle {
    static func glow(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 110 / 255, green: 175 / 255, blue: 1)
                        : Color(red: 70 / 255, green: 150 / 255, blue: 1)
    }
    /// #F2F8FF: the slightly blue white of star and orb cores.
    static let core = Color(red: 0.949, green: 0.973, blue: 1)
}

// MARK: - Egg cracks

/// The hatch cracks, drawn in code. Points are normalised to the egg's bounds from a 22×26 grid.
enum EggCracks {
    private static func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x / 22, y: y / 26) }

    /// Index = crack level − 1: one crack per shake, the third one branching in two.
    static let polylines: [[[CGPoint]]] = [
        [[p(3, 13), p(5, 12), p(7, 14), p(9, 12), p(11, 13)]],
        [[p(11, 13), p(13, 11), p(15, 13), p(17, 12), p(19, 13)]],
        [[p(9, 12), p(8, 9), p(10, 7)], [p(15, 13), p(16, 16), p(14, 18)]],
    ]
    /// Outer crack ends, where light escapes during the light phase.
    static let lightSources: [CGPoint] = [p(3, 13), p(19, 13), p(10, 7), p(14, 18)]
    /// The point the light rays leave from.
    static let center = p(11, 13)
    /// PokéAPI egg outline (#181818); the shell shards reuse the egg's cream and spot colours.
    static let outline = Color(red: 24 / 255, green: 24 / 255, blue: 24 / 255)
    static let shellCream = Color(red: 1, green: 246 / 255, blue: 222 / 255)
    static let shellSpot = Color(red: 156 / 255, green: 205 / 255, blue: 131 / 255)

    static func point(_ normalized: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + normalized.x * rect.width, y: rect.minY + normalized.y * rect.height)
    }

    static func point(_ normalized: CGPoint, in size: CGSize) -> CGPoint {
        point(normalized, in: CGRect(origin: .zero, size: size))
    }

    /// Every crack up to `level`, as one stroke path.
    static func path(level: Int, in rect: CGRect) -> Path {
        var path = Path()
        for line in polylines.prefix(max(0, level)).joined() {
            path.addLines(line.map { point($0, in: rect) })
        }
        return path
    }
}

// MARK: - One-shot wobble

/// One small wobble per change of `trigger` (a resting egg stirring, a prayer): a keyframe animation that
/// runs once, never a repeating animation. Shared by the popover header and the floating pet.
@MainActor
struct OneShotWobble: ViewModifier {
    let trigger: Int

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: 0.0, trigger: trigger) { view, angle in
            view.rotationEffect(.degrees(angle))
        } keyframes: { _ in
            KeyframeTrack {
                LinearKeyframe(-9.0, duration: 0.06)
                LinearKeyframe(9.0, duration: 0.10)
                LinearKeyframe(-5.0, duration: 0.08)
                LinearKeyframe(0.0, duration: 0.06)
            }
        }
    }
}

// MARK: - Player

/// Plays one celebration: owns its start time, the caption and the end. Time-driven only, so a sprite
/// that never loads cannot stall it. One `Task` per playback sleeps to each text boundary and to the end.
@MainActor @Observable
final class CelebrationPlayer {
    private(set) var item: PendingCelebration?
    private(set) var startedAt: Date?
    private(set) var text: CelebrationText = .none
    /// Past the timeline's `lastMotionTime`: only the caption is left, so the stage stops redrawing.
    private(set) var motionEnded = false
    /// Short cross-fade version (Reduce Motion / Low Power). Read by `play`; applies from the next sequence.
    var reduced: Bool
    /// The timeline of the playing item, fixed at `play`.
    private(set) var timeline: CelebrationTimeline?

    @ObservationIgnored private var onFinish: ((Int) -> Void)?
    @ObservationIgnored private var onSkip: ((Int, Date) -> Void)?
    @ObservationIgnored private var onSeen: ((Int) -> Void)?
    @ObservationIgnored private var task: Task<Void, Never>?
    /// Bumped by every play/skip/stop so a stale task can never write text or finish.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private let clock: @MainActor () -> Date
    @ObservationIgnored private let sleep: @MainActor (TimeInterval) async throws -> Void

    /// `clock` and `sleep` are injectable so tests do not wait for a 12 s sequence.
    init(reduced: Bool = false,
         clock: @escaping @MainActor () -> Date = { Date() },
         sleep: @escaping @MainActor (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }) {
        self.reduced = reduced
        self.clock = clock
        self.sleep = sleep
    }

    /// Starts `item` at `now` (default: the player's clock). `onFinish(item.id)` is called once, at the end.
    ///
    /// Any item already playing is replaced **without** its `onFinish`: it stays unseen, exactly as with
    /// `cancel()`. This holds for every kind, `.dittoReveal` included: the current item is stopped first,
    /// then the Ditto reveal (which has no stage sequence) calls its own `onFinish` immediately.
    /// `onSkip(item.id, newStart)` reports a click's jump to the reveal, so another surface can follow.
    /// `onSeen(item.id)` reports the reveal (`CelebrationTimeline.seenTime`), once per playback.
    func play(_ item: PendingCelebration, now: Date? = nil, onFinish: @escaping (Int) -> Void,
              onSkip: ((Int, Date) -> Void)? = nil, onSeen: ((Int) -> Void)? = nil) {
        stop()
        let now = now ?? clock()
        guard let timeline = CelebrationTimeline(item.kind, reduced: reduced) else {
            onFinish(item.id)   // the Ditto reveal has no stage sequence
            return
        }
        self.item = item
        self.timeline = timeline
        self.startedAt = now
        self.onFinish = onFinish
        self.onSkip = onSkip
        self.onSeen = onSeen
        text = timeline.frame(at: elapsed(at: clock())).text
        schedule(timeline, from: now)
    }

    /// Jumps to the reveal at `now` (default: the player's clock); never moves backwards.
    func skip(now: Date? = nil) {
        let now = now ?? clock()
        guard let timeline, let startedAt, now.timeIntervalSince(startedAt) < timeline.skipTarget else { return }
        let start = now.addingTimeInterval(-timeline.skipTarget)
        self.startedAt = start
        text = timeline.frame(at: timeline.skipTarget).text
        schedule(timeline, from: start)
        if let id = item?.id { onSkip?(id, start) }
    }

    /// Stops without calling `onFinish`: the item stays unseen and replays later.
    func cancel() { stop() }

    /// The player's clock now (injectable in tests), for a start shared with another surface.
    var now: Date { clock() }

    func elapsed(at date: Date) -> TimeInterval {
        startedAt.map { max(0, date.timeIntervalSince($0)) } ?? 0
    }

    private func schedule(_ timeline: CelebrationTimeline, from startedAt: Date) {
        task?.cancel()
        generation += 1
        let token = generation, clock = clock, sleep = sleep
        let marks = Array(Set(timeline.textBoundaries + [timeline.seenTime, timeline.lastMotionTime,
                                                          timeline.total])).sorted()
        task = Task { [weak self] in
            for mark in marks {
                let remaining = mark - clock().timeIntervalSince(startedAt)
                if remaining > 0 {
                    do { try await sleep(remaining) } catch { return }
                }
                guard !Task.isCancelled, let self, self.generation == token else { return }
                if mark >= timeline.total {
                    self.finish()
                } else {
                    self.text = timeline.frame(at: mark).text
                    if mark >= timeline.lastMotionTime { self.motionEnded = true }
                    if mark == timeline.seenTime, let id = self.item?.id { self.onSeen?(id) }
                }
            }
        }
    }

    private func finish() {
        let id = item?.id, callback = onFinish
        stop()
        if let id { callback?(id) }
    }

    private func stop() {
        task?.cancel()
        task = nil
        generation += 1
        item = nil
        timeline = nil
        startedAt = nil
        onFinish = nil
        onSkip = nil
        onSeen = nil
        text = .none
        motionEnded = false
    }
}

// MARK: - Stage

/// The playing celebration on the sprite. Exists only while `player` plays: no `TimelineView` at rest, and
/// its `TimelineView` pauses once nothing moves any more (the caption may stay up a few seconds longer).
/// Its frame is the sprite box grown by `effectsMargin` on every side. Only the centred sprite box takes
/// clicks (a tap skips to the reveal): the effects margin may cover other controls, which stay usable.
@MainActor
struct CelebrationStage: View {
    let player: CelebrationPlayer
    let size: CGFloat
    var minFrameDelay: TimeInterval = 0
    var spriteStore: SpriteStore = .shared
    /// Shortest gap between redrawn frames of the effects; nil = every display frame (the popover).
    /// The always-on floating pet passes its named cap (`FloatingPetController.celebrationFrameInterval`).
    var minimumInterval: TimeInterval? = nil
    static let effectsMargin: CGFloat = 28

    static func schedule(minimumInterval: TimeInterval?, paused: Bool = false) -> AnimationTimelineSchedule {
        .animation(minimumInterval: minimumInterval, paused: paused)
    }

    /// The instant drawn: once motion ended, exactly the last moving frame (the paused schedule's last redraw
    /// could have landed a little before it).
    static func drawnTime(elapsed: TimeInterval, motionEnded: Bool, lastMotionTime: TimeInterval) -> TimeInterval {
        motionEnded ? lastMotionTime : elapsed
    }

    var body: some View {
        if let item = player.item, let timeline = player.timeline {
            TimelineView(Self.schedule(minimumInterval: minimumInterval, paused: player.motionEnded)) { context in
                CelebrationScene(kind: item.kind, timeline: timeline,
                                 t: Self.drawnTime(elapsed: player.elapsed(at: context.date),
                                                   motionEnded: player.motionEnded,
                                                   lastMotionTime: timeline.lastMotionTime),
                                 size: size, minFrameDelay: minFrameDelay, spriteStore: spriteStore)
            }
            .allowsHitTesting(false)
            .overlay {
                Color.clear
                    .frame(width: size, height: size)
                    .contentShape(Rectangle())
                    .onTapGesture { player.skip() }
            }
        }
    }
}

/// One instant `t` of a celebration, drawn: halo/rays/crack light behind, the sprite(s), then orbs,
/// flash, stars, shell shards and sparkles. Pure function of its inputs, so tests render exact instants.
@MainActor
struct CelebrationScene: View {
    let kind: CelebrationKind
    let timeline: CelebrationTimeline
    let t: TimeInterval
    let size: CGFloat
    var minFrameDelay: TimeInterval = 0
    var spriteStore: SpriteStore = .shared
    /// Egg pixels to use instead of the shared egg sprite (tests); nil loads `SpriteLoader`'s egg.
    var eggImage: NSImage? = nil
    @Environment(\.colorScheme) private var scheme

    /// The prototype was drawn around a 76 pt sprite; every effect distance scales with the sprite.
    static func unit(_ size: CGFloat) -> CGFloat { size / 76 }

    /// The egg's shake: rotation about its bottom centre plus the hop, in the sprite box's coordinates.
    static func eggTransform(frame: CelebrationFrame, size: CGFloat) -> CGAffineTransform {
        let anchor = CGPoint(x: size / 2, y: size)
        return CGAffineTransform(translationX: -anchor.x, y: -anchor.y)
            .concatenating(CGAffineTransform(rotationAngle: frame.eggRotation))
            .concatenating(CGAffineTransform(translationX: anchor.x, y: anchor.y + frame.eggHop * unit(size)))
    }

    private var subjects: (source: CelebrationSubject?, target: CelebrationSubject?) {
        switch kind {
        case .evolve(let from, let to): (from, to)
        case .hatch(let to): (nil, to)
        case .dittoReveal: (nil, nil)
        }
    }

    var body: some View {
        let frame = timeline.frame(at: t)
        let glow = CelebrationStyle.glow(scheme)
        let side = size + 2 * CelebrationStage.effectsMargin
        let scale = max(0.01, frame.scale)
        // Full mode shows one form at a time; the reduced cross-fade draws both with their opacities.
        let sourceOpacity = frame.showsTarget ? 0 : frame.eggOpacity
        let targetOpacity = frame.showsTarget || timeline.reduced ? frame.targetOpacity : 0
        ZStack {
            Canvas { context, canvas in drawBehind(&context, canvas, frame: frame, glow: glow) }
                .frame(width: side, height: side)
                .allowsHitTesting(false)
            ZStack {
                Group {
                    if let source = subjects.source {
                        sprite(source).modifier(Silhouette(whiteness: frame.whiteness, glow: glow))
                    } else {
                        CelebrationEgg(override: eggImage, size: size, frame: frame, glow: glow)
                    }
                }
                .opacity(sourceOpacity)
                if let target = subjects.target {
                    sprite(target)
                        .modifier(Silhouette(whiteness: frame.whiteness, glow: glow))
                        .opacity(targetOpacity)
                }
            }
            // One shared centre: both forms scale around the sprite box centre, grounded at scale 1.
            .scaleEffect(scale, anchor: UnitPoint(x: 0.5, y: 0.5))
            .frame(width: size, height: size)
            .contentShape(Rectangle())
            Canvas { context, canvas in drawFront(&context, canvas, frame: frame, glow: glow) }
                .frame(width: side, height: side)
                .allowsHitTesting(false)
        }
        .frame(width: side, height: side)
    }

    /// Built every display frame, but cheap: `CelebrationSprite` is equatable on inputs that do not change
    /// during a sequence, so SwiftUI skips its body and `SpriteView.init` (with its cache lookups) runs once.
    private func sprite(_ subject: CelebrationSubject) -> some View {
        CelebrationSprite(subject: subject, size: size, minFrameDelay: minFrameDelay, spriteStore: spriteStore)
            .equatable()
    }

    // MARK: Effects

    private func drawBehind(_ context: inout GraphicsContext, _ canvas: CGSize, frame: CelebrationFrame, glow: Color) {
        let u = Self.unit(size), center = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
        let reach = min(canvas.width, canvas.height) / 2
        if frame.haloAlpha > 0 {
            // The hatch halo rises to 1 in the timeline; the prototype draws it at 45 % of that.
            let hatch = timeline.kind == .hatch
            let alpha = frame.haloAlpha * (hatch ? 0.45 : 1)
            let radius = min(reach, (hatch ? 70 + 20 * frame.haloAlpha : 80 + 10 * min(1, max(0, (t - 1.2) / 1.2))) * u)
            radial(&context, center: center, radius: radius,
                   stops: [.init(color: glow.opacity(alpha), location: 0), .init(color: glow.opacity(0), location: 1)])
        }
        if frame.raysAlpha > 0 {
            let length = min(reach, 100 * u)
            var rays = context
            rays.translateBy(x: center.x, y: center.y)
            rays.rotate(by: .radians(t * 0.7))
            var wedges = Path()
            for i in 0..<12 {
                let angle = Double(i) * 2 * .pi / 12
                wedges.move(to: .zero)
                wedges.addArc(center: .zero, radius: length, startAngle: .radians(angle - 0.07),
                              endAngle: .radians(angle + 0.07), clockwise: false)
                wedges.closeSubpath()
            }
            rays.fill(wedges, with: .radialGradient(
                Gradient(stops: [.init(color: glow.opacity(frame.raysAlpha), location: 0),
                                 .init(color: glow.opacity(0), location: 1)]),
                center: .zero, startRadius: 8 * u, endRadius: length))
        }
        // Light escaping from the cracks while the egg whitens.
        if frame.crackLevel > 0, frame.whiteness > 0, frame.eggOpacity > 0 {
            let margin = CelebrationStage.effectsMargin
            let box = CGRect(x: 0, y: 0, width: size, height: size)
            let transform = Self.eggTransform(frame: frame, size: size)
                .concatenating(CGAffineTransform(translationX: margin, y: margin))
            let origin = EggCracks.point(EggCracks.center, in: box).applying(transform)
            var beams = Path()
            for source in EggCracks.lightSources {
                let start = EggCracks.point(source, in: box).applying(transform)
                // Explicit Double: Swift 6.1 (CI) finds `cos`/`sin` ambiguous on an inferred CGFloat angle.
                let angle: Double = atan2(Double(start.y - origin.y), Double(start.x - origin.x))
                let length = (18 + 34 * frame.whiteness) * u
                beams.move(to: start)
                beams.addLine(to: CGPoint(x: start.x + cos(angle) * length, y: start.y + sin(angle) * length))
            }
            context.stroke(beams, with: .color(glow.opacity(0.7 * frame.whiteness)),
                           style: StrokeStyle(lineWidth: 7 * u, lineCap: .round))
            context.stroke(beams, with: .color(CelebrationStyle.core.opacity(0.9 * frame.whiteness)),
                           style: StrokeStyle(lineWidth: 2.5 * u, lineCap: .round))
        }
    }

    private func drawFront(_ context: inout GraphicsContext, _ canvas: CGSize, frame: CelebrationFrame, glow: Color) {
        let u = Self.unit(size), center = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
        let reach = min(canvas.width, canvas.height) / 2
        if let p = frame.orbsProgress {
            // Ten orbs converge on the sprite while it fills with white.
            for i in 0..<10 {
                let l = min(1, max(0, (p - Double(i) * 0.04) / 0.6))
                guard l < 1 else { continue }
                let distance = min(reach - 4 * u, 96 * u) * (1 - l * l)
                let angle = Double(i) * .pi / 5 + t * 1.4
                let at = CGPoint(x: center.x + cos(angle) * distance, y: center.y + sin(angle) * distance)
                glowing(&context, glow: glow, opacity: min(1, l * 4)) {
                    $0.fill(Path(ellipseIn: CGRect(x: at.x - 3.5 * u, y: at.y - 3.5 * u, width: 7 * u, height: 7 * u)),
                            with: .color(CelebrationStyle.core))
                }
            }
        }
        if let p = frame.flashProgress {
            let radius = min(reach, (30 + 95 * easeOut(p)) * u)
            radial(&context, center: center, radius: radius, stops: [
                .init(color: .white.opacity(0.95 * (1 - p)), location: 0),
                .init(color: glow.opacity(0.6 * (1 - p)), location: 0.55),
                .init(color: glow.opacity(0), location: 1),
            ])
        }
        if let p = frame.starsProgress {
            let radius = 7 * (1 - p * 0.7) * u
            for i in 0..<12 {
                let angle = Double(i) * 2 * .pi / 12 + 1
                let distance = min(reach - radius, (22 + 82 * easeOut(p) * (i % 2 == 1 ? 0.8 : 1)) * u)
                star(&context, at: CGPoint(x: center.x + cos(angle) * distance, y: center.y + sin(angle) * distance),
                     radius: radius, opacity: 1 - p, glow: glow)
            }
        }
        if let time = frame.shardsTime { shards(&context, center: center, time: time) }
        if let p = frame.sparkleProgress {
            let spots: [(Double, Double, Double)] = [(-38, -30, 0), (34, -40, 0.2), (40, 10, 0.4), (-30, 18, 0.55), (4, -58, 0.3)]
            for (dx, dy, delay) in spots {
                let q = min(1, max(0, (p - delay) / 0.45)), wave = sin(q * .pi)
                star(&context, at: CGPoint(x: center.x + dx * u, y: center.y + (dy - 6) * u),
                     radius: 9 * wave * u, opacity: wave, glow: glow)
            }
        }
    }

    /// Eleven shell fragments thrown up and falling back, in the egg's colours.
    private func shards(_ context: inout GraphicsContext, center: CGPoint, time: Double) {
        let u = Self.unit(size), pixel = size / 30   // one egg-sprite pixel
        let opacity = min(1, max(0, 1.5 - time))
        for i in 0..<11 {
            let angle = -Double.pi / 2 + Double(i - 5) * 0.28 + (i % 2 == 1 ? 0.1 : -0.1)
            let speed = Double(120 + (i * 37) % 70) * u
            let x = center.x + cos(angle) * speed * time
            let y = center.y + sin(angle) * speed * time + 0.5 * 520 * u * time * time
            let side = Double(2 + i % 3) * pixel
            var shard = context
            shard.opacity = opacity
            shard.translateBy(x: x, y: y)
            shard.rotate(by: .radians(Double(i) + Double(i % 2 == 1 ? 1 : -1) * Double(4 + i % 3) * time))
            var triangle = Path()
            triangle.move(to: CGPoint(x: -side / 2, y: side / 2))
            triangle.addLine(to: CGPoint(x: side / 2, y: side / 2))
            triangle.addLine(to: CGPoint(x: 0, y: -side / 2))
            triangle.closeSubpath()
            shard.fill(triangle, with: .color(i % 4 == 0 ? EggCracks.shellSpot : EggCracks.shellCream))
            shard.stroke(triangle, with: .color(EggCracks.outline), lineWidth: max(1, pixel * 0.6))
        }
    }

    private func star(_ context: inout GraphicsContext, at point: CGPoint, radius: Double, opacity: Double, glow: Color) {
        guard opacity > 0, radius > 0 else { return }
        var path = Path()
        for i in 0..<8 {
            let angle = Double(i) * .pi / 4, r = i % 2 == 1 ? radius * 0.28 : radius
            let vertex = CGPoint(x: point.x + cos(angle) * r, y: point.y + sin(angle) * r)
            if i == 0 { path.move(to: vertex) } else { path.addLine(to: vertex) }
        }
        path.closeSubpath()
        glowing(&context, glow: glow, opacity: opacity) { $0.fill(path, with: .color(CelebrationStyle.core)) }
    }

    /// Draws `body` with the blue glow around it, so white cores stay visible on a light background.
    private func glowing(_ context: inout GraphicsContext, glow: Color, opacity: Double,
                         _ body: (inout GraphicsContext) -> Void) {
        context.drawLayer { layer in
            layer.opacity = opacity
            // Two stacked shadows: one alone leaves a white core nearly invisible on a light popover.
            layer.addFilter(.shadow(color: glow, radius: 2))
            layer.addFilter(.shadow(color: glow, radius: 5))
            body(&layer)
        }
    }

    private func radial(_ context: inout GraphicsContext, center: CGPoint, radius: Double, stops: [Gradient.Stop]) {
        context.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius)),
                     with: .radialGradient(Gradient(stops: stops), center: center, startRadius: 0, endRadius: radius))
    }

    private func easeOut(_ p: Double) -> Double { 1 - pow(1 - p, 3) }
}

/// One form of the celebrating Pokémon. Equatable on everything but time, so the per-frame `TimelineView`
/// rebuild never re-runs `SpriteView.init` (a disk read per frame when the sprite is not cached).
@MainActor
struct CelebrationSprite: View, Equatable {
    let subject: CelebrationSubject
    let size: CGFloat
    let minFrameDelay: TimeInterval
    let spriteStore: SpriteStore

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.subject == rhs.subject && lhs.size == rhs.size && lhs.minFrameDelay == rhs.minFrameDelay
            && lhs.spriteStore === rhs.spriteStore
    }

    var body: some View {
        SpriteView(speciesID: subject.speciesID, size: size, animated: true, shiny: subject.isShiny,
                   minFrameDelay: minFrameDelay, spriteStore: spriteStore, form: subject.form)
            .frame(width: size, height: size)
    }
}

/// Whitens a sprite by `whiteness` while keeping its alpha contour, with the blue glow around it.
@MainActor
private struct Silhouette: ViewModifier {
    let whiteness: Double
    let glow: Color

    func body(content: Content) -> some View {
        // Modifiers stay unconditional: an `if` here would recreate the SpriteView and restart its GIF.
        content
            .brightness(whiteness)
            .shadow(color: glow.opacity(whiteness > 0 ? 0.95 * min(1, whiteness * 2) : 0), radius: 8)
    }
}

/// The egg during the hatch: shakes, cracks clipped to the egg's own alpha, and their glow.
@MainActor
private struct CelebrationEgg: View {
    let override: NSImage?
    let size: CGFloat
    let frame: CelebrationFrame
    let glow: Color
    @State private var loaded: NSImage? = SpriteLoader.cachedEggImage()

    private var image: NSImage? { override ?? loaded }

    /// The egg image's rect inside the sprite box (aspect kept, like `SpriteView`).
    private var eggRect: CGRect {
        guard let image else { return CGRect(x: 0, y: 0, width: size, height: size) }
        let fit = SpriteFit.size(for: image.size, box: size)
        return CGRect(x: (size - fit.width) / 2, y: (size - fit.height) / 2, width: fit.width, height: fit.height)
    }

    /// One sprite pixel of the egg, the crack stroke width.
    private var pixel: CGFloat {
        guard let image, image.size.width > 0 else { return size / 30 }
        return eggRect.width / image.size.width
    }

    @ViewBuilder
    private var shell: some View {
        if let image {
            Image(nsImage: image).resizable().interpolation(.none)
                .frame(width: eggRect.width, height: eggRect.height)
                .frame(width: size, height: size)
        } else {
            Text("🥚").font(.system(size: size * 0.62)).frame(width: size, height: size)
        }
    }

    private func cracks(_ color: Color) -> some View {
        let path = EggCracks.path(level: frame.crackLevel, in: eggRect)
        return Canvas { context, _ in
            context.stroke(path, with: .color(color),
                           style: StrokeStyle(lineWidth: pixel, lineCap: .square, lineJoin: .miter))
        }
        .frame(width: size, height: size)
        .mask { shell }
    }

    var body: some View {
        ZStack {
            ZStack {
                shell
                cracks(EggCracks.outline)
            }
            .modifier(Silhouette(whiteness: frame.whiteness, glow: glow))
            // Light from inside, over the whitened shell: glowing lines whose glow is not clipped.
            cracks(CelebrationStyle.core)
                .shadow(color: glow, radius: 4)
                .opacity(frame.crackGlow)
        }
        .frame(width: size, height: size)
        .transformEffect(CelebrationScene.eggTransform(frame: frame, size: size))
        .task {
            guard override == nil, loaded == nil else { return }
            loaded = await SpriteLoader.eggImage()
        }
    }
}
