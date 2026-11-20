import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

/// Player scheduling and key rendered instants of the evolve/hatch celebration.
/// Sample data only: sprites are synthetic discs written to a temporary `SpriteStore` directory,
/// the egg is a synthetic cream oval, and renders go through `ImageRenderer` (no `.task`, no network).
@MainActor
final class CelebrationStageRenderTests: XCTestCase {
    // MARK: Fixtures

    private static let source = CelebrationSubject(speciesID: 9_001, form: nil, isShiny: false, name: "Source")
    private static let target = CelebrationSubject(speciesID: 9_002, form: nil, isShiny: false, name: "Target")
    private static let sourceColor = NSColor(srgbRed: 1, green: 0.15, blue: 0.15, alpha: 1)
    private static let targetColor = NSColor(srgbRed: 0.1, green: 0.8, blue: 0.2, alpha: 1)

    private func evolveItem(id: Int = 1) -> PendingCelebration {
        PendingCelebration(id: id, kind: .evolve(from: Self.source, to: Self.target), deferred: nil)
    }

    private func hatchItem(id: Int = 2) -> PendingCelebration {
        PendingCelebration(id: id, kind: .hatch(to: Self.target), deferred: nil)
    }

    private func emptyDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("celebration-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    /// A 96×96 transparent canvas with a centred opaque disc, like a static PokéAPI sprite.
    private func disc(_ color: NSColor) throws -> Data {
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 96, pixelsHigh: 96, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: 96, height: 96).fill()
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: 16, y: 16, width: 64, height: 64)).fill()
        NSGraphicsContext.restoreGraphicsState()
        return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    }

    /// Store whose directory holds the static sprites of both synthetic species.
    private func spriteStore() throws -> SpriteStore {
        let directory = try emptyDirectory()
        for (subject, color) in [(Self.source, Self.sourceColor), (Self.target, Self.targetColor)] {
            let key = SpriteStore.cacheKey(speciesID: try XCTUnwrap(subject.speciesID), animated: false, shiny: false)
            try disc(color).write(to: directory.appendingPathComponent(key + ".png"))
        }
        return SpriteStore(directory: directory)
    }

    /// A cropped-egg stand-in: a 30×30 cream oval filling its canvas.
    private func eggImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 30, height: 30))
        image.lockFocus()
        NSColor(srgbRed: 1, green: 0.965, blue: 0.87, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: 30, height: 30)).fill()
        image.unlockFocus()
        return image
    }

    // MARK: Rendering helpers

    private struct Pixels {
        let bitmap: NSBitmapImageRep
        let scale: CGFloat
        func at(_ point: CGPoint) -> (r: Double, g: Double, b: Double) {
            let color = bitmap.colorAt(x: Int(point.x * scale), y: Int(point.y * scale))?.usingColorSpace(.sRGB)
            return (Double(color?.redComponent ?? 0), Double(color?.greenComponent ?? 0),
                    Double(color?.blueComponent ?? 0))
        }
        /// Pixels that differ from the white background.
        var inkedPixels: Int {
            var count = 0
            for y in 0..<bitmap.pixelsHigh {
                for x in 0..<bitmap.pixelsWide {
                    guard let c = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                    if min(c.redComponent, c.greenComponent, c.blueComponent) < 0.95 { count += 1 }
                }
            }
            return count
        }
    }

    private func render<V: View>(_ view: V, side: CGFloat, dark: Bool = false, writingTo url: URL? = nil) throws -> Pixels {
        let content = view
            .frame(width: side, height: side)
            .background(dark ? Color(white: 0.16) : Color.white)
            .environment(\.colorScheme, dark ? .dark : .light)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        let cgImage = try XCTUnwrap(renderer.cgImage)
        // Normalise through PNG so components read the same way as the evidence files.
        let png = try XCTUnwrap(NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]))
        if let url { try png.write(to: url) }
        return Pixels(bitmap: try XCTUnwrap(NSBitmapImageRep(data: png)), scale: 2)
    }

    private func scene(_ item: PendingCelebration, at t: TimeInterval, size: CGFloat,
                       store: SpriteStore, egg: NSImage? = nil, shiny: Bool = false) -> CelebrationScene {
        let kind: CelebrationTimeline.Kind = if case .hatch = item.kind { .hatch } else { .evolve }
        return CelebrationScene(kind: item.kind, timeline: CelebrationTimeline(kind: kind, reduced: false, shiny: shiny),
                                t: t, size: size, spriteStore: store, eggImage: egg)
    }

    /// Writes PNGs of key instants when `PTB_CELEBRATION_RENDER_DIR` names an existing folder; skipped otherwise.
    func testWriteCelebrationFrames() throws {
        guard let directory = ProcessInfo.processInfo.environment["PTB_CELEBRATION_RENDER_DIR"] else {
            throw XCTSkip("PTB_CELEBRATION_RENDER_DIR not set")
        }
        let size: CGFloat = 76, side = size + 2 * CelebrationStage.effectsMargin
        let store = try spriteStore()
        let instants: [(String, PendingCelebration, TimeInterval, Bool)] = [
            ("evolve-0.6-announce", evolveItem(), 0.6, false), ("evolve-1.8-orbs", evolveItem(), 1.8, false),
            ("evolve-5.0-alternation", evolveItem(), 5.0, false), ("evolve-7.7-burst", evolveItem(), 7.7, false),
            ("evolve-8.25-bounce", evolveItem(), 8.25, false), ("evolve-8.8-shiny", evolveItem(), 8.8, true),
            ("hatch-4.5-cracks", hatchItem(), 4.5, false), ("hatch-5.6-light", hatchItem(), 5.6, false),
            ("hatch-6.3-shatter", hatchItem(), 6.3, false), ("hatch-6.6-appear", hatchItem(), 6.6, false),
        ]
        for (name, item, t, shiny) in instants {
            for dark in [false, true] {
                let url = URL(fileURLWithPath: directory).appendingPathComponent("\(name)-\(dark ? "dark" : "light").png")
                _ = try render(scene(item, at: t, size: size, store: store, egg: eggImage(), shiny: shiny),
                               side: side, dark: dark, writingTo: url)
            }
        }
    }

    // MARK: Player

    func testPlayerTextFollowsTimeline() {
        let player = CelebrationPlayer(sleep: { _ in try await Task.sleep(for: .seconds(3600)) })
        defer { player.cancel() }
        player.play(evolveItem(), now: Date().addingTimeInterval(-7.9), onFinish: { _ in })
        XCTAssertEqual(player.text, .evolveAnnounce)
        player.skip()
        XCTAssertGreaterThanOrEqual(player.elapsed(at: Date()), 7.4)

        // Skip from the start jumps exactly to the skip target and never goes backwards.
        let start = Date(timeIntervalSince1970: 1_000)
        let fixed = CelebrationPlayer(clock: { start }, sleep: { _ in try await Task.sleep(for: .seconds(3600)) })
        defer { fixed.cancel() }
        fixed.play(hatchItem(), now: start, onFinish: { _ in })
        XCTAssertEqual(fixed.text, .hatchOh)
        fixed.skip(now: start.addingTimeInterval(1))
        XCTAssertEqual(fixed.elapsed(at: start.addingTimeInterval(1)), 5.8, accuracy: 1e-6)
        XCTAssertEqual(fixed.text, .hatchOh)
        fixed.skip(now: start.addingTimeInterval(2))
        XCTAssertEqual(fixed.elapsed(at: start.addingTimeInterval(2)), 6.8, accuracy: 1e-6)
    }

    func testPlayerFinishesOnceAndCancelDoesNot() async {
        // Deterministic clock: each injected sleep advances it by exactly the requested time.
        final class Clock { var now = Date(timeIntervalSince1970: 5_000) }
        let clock = Clock()
        let player = CelebrationPlayer(reduced: true, clock: { clock.now },
                                       sleep: { clock.now = clock.now.addingTimeInterval($0) })
        var finished: [Int] = []
        let done = expectation(description: "finished")
        player.play(evolveItem(id: 7), now: clock.now, onFinish: { finished.append($0); done.fulfill() })
        XCTAssertEqual(player.text, .evolveDone)
        await fulfillment(of: [done], timeout: 2)
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(finished, [7])
        XCTAssertNil(player.item)
        XCTAssertNil(player.startedAt)
        XCTAssertEqual(player.text, .none)
        XCTAssertEqual(clock.now.timeIntervalSince(Date(timeIntervalSince1970: 5_000)), 4.5, accuracy: 1e-9)

        // Cancelled before its task ever runs: the instant sleep must not let it finish anyway.
        var cancelled: [Int] = []
        player.play(evolveItem(id: 8), now: clock.now, onFinish: { cancelled.append($0) })
        player.cancel()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(cancelled, [])
        XCTAssertNil(player.item)

        // Replacing a playing item cancels the first without finishing it, and the first item's stale
        // task must not end the second early (it would wake 2 s into the second item's 4.5 s).
        var replaced: [(id: Int, elapsed: TimeInterval)] = []
        let second = expectation(description: "second finished")
        player.play(evolveItem(id: 9), now: clock.now, onFinish: { replaced.append(($0, -1)) })
        clock.now = clock.now.addingTimeInterval(2)
        let secondStart = clock.now
        player.play(hatchItem(id: 10), now: secondStart, onFinish: {
            replaced.append(($0, clock.now.timeIntervalSince(secondStart)))
            second.fulfill()
        })
        await fulfillment(of: [second], timeout: 2)
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(replaced.map(\.id), [10])
        XCTAssertGreaterThanOrEqual(replaced.first?.elapsed ?? 0, 4.5 - 1e-6)
    }

    /// The stage redraws only while something moves: at the timeline's last moving frame the player says so,
    /// while the caption stays up until the end.
    func testPlayerEndsTheMotionAtTheLastMovingFrame() async throws {
        final class Clock { var now = Date(timeIntervalSince1970: 9_000) }
        let clock = Clock()
        let start = clock.now
        var woke: [TimeInterval] = []
        let player = CelebrationPlayer(clock: { clock.now }, sleep: { seconds in
            clock.now = clock.now.addingTimeInterval(seconds)
            woke.append(clock.now.timeIntervalSince(start))
            if woke.count >= 3 { try await Task.sleep(for: .seconds(3600)) }   // parks at the end mark
        })
        defer { player.cancel() }
        player.play(evolveItem(), now: start, onFinish: { _ in })
        XCTAssertFalse(player.motionEnded)
        for _ in 0..<100 where woke.count < 3 { await Task.yield() }
        XCTAssertEqual(woke.count, 3)
        XCTAssertEqual(woke.first ?? 0, 8.0, accuracy: 1e-5, "the reveal caption")
        XCTAssertEqual(woke.dropFirst().first ?? 0, 8.6, accuracy: 1e-5, "the last moving frame")
        XCTAssertTrue(player.motionEnded, "nothing moves from 8.6 s")
        XCTAssertNotNil(player.item, "the caption still holds until 12 s")
        XCTAssertEqual(player.text, .evolveDone)
        player.cancel()
        XCTAssertFalse(player.motionEnded)

        // A skip under Reduce Motion lands on the end of the cross-fade: motion is over at once.
        let reduced = CelebrationPlayer(reduced: true, clock: { start },
                                        sleep: { _ in try await Task.sleep(for: .seconds(3600)) })
        defer { reduced.cancel() }
        reduced.play(evolveItem(), now: start, onFinish: { _ in })
        reduced.skip(now: start)
        for _ in 0..<100 where !reduced.motionEnded { await Task.yield() }
        XCTAssertTrue(reduced.motionEnded)
    }

    /// A paused schedule has no next entry: the stage's TimelineView stops redrawing.
    func testStageScheduleStopsOnceMotionEnded() throws {
        let start = Date(timeIntervalSince1970: 0)
        var running = CelebrationStage.schedule(minimumInterval: nil, paused: false)
            .entries(from: start, mode: .normal).makeIterator()
        XCTAssertNotNil(running.next())
        XCTAssertNotNil(running.next(), "frames keep coming while something moves")
        var paused = CelebrationStage.schedule(minimumInterval: nil, paused: true)
            .entries(from: start, mode: .normal).makeIterator()
        _ = paused.next()
        XCTAssertNil(paused.next(), "no more frames once paused")
        XCTAssertEqual(CelebrationStage.drawnTime(elapsed: 10.3, motionEnded: true, lastMotionTime: 8.6), 8.6,
                       "the still frame is the last moving one, not where the last redraw happened to land")
        XCTAssertEqual(CelebrationStage.drawnTime(elapsed: 5.0, motionEnded: false, lastMotionTime: 8.6), 5.0)
    }

    /// The per-frame rebuild must compare equal so SwiftUI skips `SpriteView.init`; only a real input
    /// change (another subject, size, fps floor or store) may rebuild the sprite.
    func testCelebrationSpriteIsEqualAcrossFramesOnly() throws {
        let store = try spriteStore()
        let sprite = CelebrationSprite(subject: Self.source, size: 76, minFrameDelay: 0, spriteStore: store)
        XCTAssertEqual(sprite, CelebrationSprite(subject: Self.source, size: 76, minFrameDelay: 0, spriteStore: store))
        XCTAssertNotEqual(sprite, CelebrationSprite(subject: Self.target, size: 76, minFrameDelay: 0, spriteStore: store))
        XCTAssertNotEqual(sprite, CelebrationSprite(subject: Self.source, size: 80, minFrameDelay: 0, spriteStore: store))
        XCTAssertNotEqual(sprite, CelebrationSprite(subject: Self.source, size: 76, minFrameDelay: 0.2, spriteStore: store))
        XCTAssertNotEqual(sprite, CelebrationSprite(subject: Self.source, size: 76, minFrameDelay: 0,
                                                    spriteStore: SpriteStore(directory: try emptyDirectory())))
    }

    /// Without explicit dates, `play` and `skip` read the injected clock, not the wall clock.
    func testDefaultDatesUseTheInjectedClock() {
        final class Clock { var now = Date(timeIntervalSince1970: 42) }
        let clock = Clock()
        let player = CelebrationPlayer(clock: { clock.now }, sleep: { _ in try await Task.sleep(for: .seconds(3600)) })
        defer { player.cancel() }
        player.play(evolveItem(), onFinish: { _ in })
        XCTAssertEqual(player.startedAt, clock.now)
        clock.now = clock.now.addingTimeInterval(1)
        player.skip()
        XCTAssertEqual(player.elapsed(at: clock.now), 7.4, accuracy: 1e-6)
    }

    func testPlayerFinishesDittoImmediately() {
        let player = CelebrationPlayer()
        var finished: [Int] = []
        player.play(PendingCelebration(id: 4, kind: .dittoReveal(shiny: false), deferred: nil),
                    onFinish: { finished.append($0) })
        XCTAssertEqual(finished, [4])
        XCTAssertNil(player.item)
        XCTAssertEqual(player.elapsed(at: Date()), 0)
    }

    func testStageFinishesWithoutSprite() async throws {
        let empty = SpriteStore(directory: try emptyDirectory())
        let player = CelebrationPlayer(reduced: true)   // real clock and sleep
        let done = expectation(description: "finished")
        var finished: [Int] = []
        player.play(hatchItem(id: 3), now: Date().addingTimeInterval(-4.3),
                    onFinish: { finished.append($0); done.fulfill() })
        let side = 76 + 2 * CelebrationStage.effectsMargin
        // While playing, the missing sprite falls back to the egg glyph instead of an empty stage.
        let playing = try render(CelebrationStage(player: player, size: 76, spriteStore: empty), side: side)
        XCTAssertGreaterThan(playing.inkedPixels, 50)
        await fulfillment(of: [done], timeout: 3)
        XCTAssertEqual(finished, [3])
        XCTAssertNil(player.item)
        // Finished: the stage (and its TimelineView) is gone.
        let idle = try render(CelebrationStage(player: player, size: 76, spriteStore: empty), side: side)
        XCTAssertEqual(idle.inkedPixels, 0)
    }

    // MARK: Rendered instants

    func testWhiteSilhouetteKeepsContourAndBlueGlow() throws {
        let size: CGFloat = 120, side = size + 2 * CelebrationStage.effectsMargin
        let store = try spriteStore()
        let frame = CelebrationTimeline(kind: .evolve, reduced: false, shiny: false).frame(at: 5.0)
        XCTAssertEqual(frame.whiteness, 1)
        let center = CGPoint(x: side / 2, y: side / 2)
        let radius = frame.scale * size / 2   // the disc fills the cropped sprite box

        let light = try render(scene(evolveItem(), at: 5.0, size: size, store: store), side: side)
        let c = light.at(center)
        XCTAssertGreaterThan(min(c.r, c.g, c.b), 0.9, "silhouette centre must be white, got \(c)")
        let glow = light.at(CGPoint(x: center.x + radius + 3, y: center.y))
        XCTAssertGreaterThan(glow.b - glow.r, 60.0 / 255, "glow next to the silhouette must be blue, got \(glow)")

        // Transparent sprite pixels stay transparent: a box corner outside the disc is not white.
        let dark = try render(scene(evolveItem(), at: 5.0, size: size, store: store), side: side, dark: true)
        let corner = dark.at(CGPoint(x: center.x + radius * 0.85, y: center.y + radius * 0.85))
        XCTAssertLessThan(min(corner.r, corner.g, corner.b), 0.8, "box corner must not be whitened, got \(corner)")
        XCTAssertGreaterThan(min(dark.at(center).r, dark.at(center).g, dark.at(center).b), 0.9)
    }

    func testHatchDrawsOneCrackPerShake() throws {
        let size: CGFloat = 120, side = size + 2 * CelebrationStage.effectsMargin
        let store = try spriteStore()
        let timeline = CelebrationTimeline(kind: .hatch, reduced: false, shiny: false)
        XCTAssertEqual(EggCracks.polylines.count, 3)
        XCTAssertEqual(EggCracks.polylines.map(\.count), [1, 1, 2])

        func isDark(_ p: (r: Double, g: Double, b: Double)) -> Bool { max(p.r, p.g, p.b) < 0.45 }
        /// Midpoint of each polyline's middle segment, in rendered coordinates, per crack level.
        func samples(at t: TimeInterval) -> [[CGPoint]] {
            let frame = timeline.frame(at: t)
            let transform = CelebrationScene.eggTransform(frame: frame, size: size)
            return EggCracks.polylines.map { level in
                level.map { line in
                    let i = (line.count - 1) / 2
                    let a = EggCracks.point(line[i], in: CGSize(width: size, height: size))
                    let b = EggCracks.point(line[i + 1], in: CGSize(width: size, height: size))
                    let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2).applying(transform)
                    return CGPoint(x: mid.x + CelebrationStage.effectsMargin, y: mid.y + CelebrationStage.effectsMargin)
                }
            }
        }

        for (t, level) in [(1.29, 0), (3.1, 2), (4.5, 3)] {
            XCTAssertEqual(timeline.frame(at: t).crackLevel, level)
            let pixels = try render(scene(hatchItem(), at: t, size: size, store: store, egg: eggImage()), side: side)
            for (index, points) in samples(at: t).enumerated() {
                for point in points {
                    XCTAssertEqual(isDark(pixels.at(point)), index < level,
                                   "t=\(t) crack level \(index + 1) at \(point): \(pixels.at(point))")
                }
            }
        }
    }

    func testHatchLightEscapesFromCracksThenShellShatters() throws {
        let size: CGFloat = 120, margin = CelebrationStage.effectsMargin, side = size + 2 * margin
        let store = try spriteStore()
        let timeline = CelebrationTimeline(kind: .hatch, reduced: false, shiny: false)
        let light = timeline.frame(at: 5.5)
        XCTAssertEqual(light.crackLevel, 3)
        XCTAssertEqual(light.crackGlow, 1)
        XCTAssertEqual(light.eggRotation, 0)

        let lit = try render(scene(hatchItem(), at: 5.5, size: size, store: store, egg: eggImage()), side: side)
        // The cracks glow white instead of staying dark…
        let crack = EggCracks.point(CGPoint(x: 8.0 / 22, y: 13.0 / 26), in: CGSize(width: size, height: size))
        let onCrack = lit.at(CGPoint(x: crack.x + margin, y: crack.y + margin))
        XCTAssertGreaterThan(min(onCrack.r, onCrack.g, onCrack.b), 0.8, "glowing crack, got \(onCrack)")
        // …and a blue beam leaves the left crack end, beyond the egg (sampled beside its white core line).
        let u = CelebrationScene.unit(size)
        let beam = lit.at(CGPoint(x: margin - 10, y: margin + size / 2 + 2.4 * u))
        XCTAssertGreaterThan(beam.b - beam.r, 40.0 / 255, "blue beam from the crack, got \(beam)")
        let beside = lit.at(CGPoint(x: margin - 10, y: margin + size / 2 + 12 * u))
        XCTAssertLessThan(beside.b - beside.r, 20.0 / 255, "nothing but the faint halo beside the beam, got \(beside)")

        // Just after the shatter, outlined shell shards fly around; nothing else on the stage is dark.
        XCTAssertNotNil(timeline.frame(at: 6.3).shardsTime)
        let shattered = try render(scene(hatchItem(), at: 6.3, size: size, store: store, egg: eggImage()), side: side)
        var outlined = 0
        for y in 0..<shattered.bitmap.pixelsHigh {
            for x in 0..<shattered.bitmap.pixelsWide {
                let p = shattered.at(CGPoint(x: CGFloat(x) / 2, y: CGFloat(y) / 2))
                if max(p.r, p.g, p.b) < 0.35 { outlined += 1 }
            }
        }
        XCTAssertGreaterThan(outlined, 20, "shard outlines expected after the shatter")
    }

    func testEvolveRevealShowsTargetColours() throws {
        let size: CGFloat = 120, side = size + 2 * CelebrationStage.effectsMargin
        let store = try spriteStore()
        let frame = CelebrationTimeline(kind: .evolve, reduced: false, shiny: false).frame(at: 9.5)
        XCTAssertTrue(frame.showsTarget)
        XCTAssertEqual(frame.whiteness, 0)
        let pixels = try render(scene(evolveItem(), at: 9.5, size: size, store: store), side: side)
        let center = CGPoint(x: side / 2, y: side / 2)
        for (dx, dy) in [(0.0, 0.0), (0.35, 0), (-0.35, 0), (0, 0.35), (0, -0.35), (0.2, 0.2)] {
            let p = pixels.at(CGPoint(x: center.x + dx * size, y: center.y + dy * size))
            XCTAssertGreaterThan(p.g, 0.6, "target green expected at (\(dx),\(dy)), got \(p)")
            XCTAssertLessThan(p.r, 0.3, "no white or source red at (\(dx),\(dy)), got \(p)")
        }
    }
}
