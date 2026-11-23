import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import XCTest
@testable import PokeTokenBar

/// Frame strips and GIFs of the home-header celebrations. **Skipped unless `PTB_CELEBRATION_RENDER_DIR`
/// names a directory:**
///
///     PTB_CELEBRATION_RENDER_DIR=/some/dir swift test --filter CelebrationRenderTests
///
/// Sample data: sprites are downloaded into a throwaway `SpriteStore` directory (never the real cache)
/// and drawn as fixed images, so every frame is a deterministic function of elapsed time. A failed
/// download falls back to a labelled placeholder and the log says which one.
@MainActor
final class CelebrationRenderTests: XCTestCase {
    private static let box: CGFloat = 76
    private static let pad: CGFloat = 10
    private static let scale: CGFloat = 3
    private func outputDirectory() throws -> URL {
        guard let path = ProcessInfo.processInfo.environment["PTB_CELEBRATION_RENDER_DIR"], !path.isEmpty else {
            throw XCTSkip("PTB_CELEBRATION_RENDER_DIR not set — render only when asked")
        }
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: Sprites

    private func placeholder(_ label: String, color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 96, height: 96), flipped: false) { _ in
            color.setFill()
            NSBezierPath(ovalIn: NSRect(x: 18, y: 14, width: 60, height: 68)).fill()
            (label as NSString).draw(at: NSPoint(x: 30, y: 40), withAttributes: [
                .font: NSFont.boldSystemFont(ofSize: 13), .foregroundColor: NSColor.white])
            return true
        }
    }

    /// Crops to the opaque content, the way the app's egg is cropped (`SpriteLoader.eggImage`).
    private func cropped(_ image: NSImage) -> NSImage {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let rep = Optional(NSBitmapImageRep(cgImage: cg)) else { return image }
        var minX = rep.pixelsWide, minY = rep.pixelsHigh, maxX = -1, maxY = -1
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.01 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, let part = cg.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1,
                                                               height: maxY - minY + 1)) else { return image }
        return NSImage(cgImage: part, size: NSSize(width: part.width, height: part.height))
    }

    private struct Sprites {
        var egg: NSImage
        var mons: [Int: NSImage]
    }

    private func sprites(_ ids: [Int]) async throws -> Sprites {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("celebration-render-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let store = SpriteStore(directory: directory)
        var egg = placeholder("EGG", color: .systemGray)
        if let data = await store.eggData(), let image = NSImage(data: data) {
            egg = cropped(image)
        } else {
            print("celebration-render egg: PLACEHOLDER (download failed)")
        }
        var mons: [Int: NSImage] = [:]
        for id in ids {
            if let data = await store.data(speciesID: id, animated: false), let image = NSImage(data: data) {
                mons[id] = image
            } else {
                mons[id] = placeholder("#\(id)", color: .systemBlue)
                print("celebration-render #\(id): PLACEHOLDER (download failed)")
            }
        }
        return Sprites(egg: egg, mons: mons)
    }

    /// Same fit as `SpriteView.fitted`: aspect-preserving inside the slot, pixel art kept crisp.
    private func fitted(_ image: NSImage, box: CGFloat = CelebrationRenderTests.box) -> some View {
        let fit = SpriteFit.size(for: image.size, box: box)
        return Image(nsImage: image).resizable().interpolation(.none)
            .frame(width: fit.width, height: fit.height)
            .frame(width: box, height: box)
    }

    // MARK: Hosting

    /// The header's sprite-box chrome around an effect frame.
    private func chrome<V: View>(_ content: V) -> some View {
        content
            .frame(width: Self.box, height: Self.box)
            .background(Color.secondary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    /// `ImageRenderer`, not `cacheDisplay`: the latter drops layer filters (`brightness`, `colorMultiply`),
    /// so the white evolution silhouette and the red Poké Ball tint would silently vanish from the frames.
    private func snapshot(_ view: some View, width: CGFloat, height: CGFloat,
                          scale: CGFloat = CelebrationRenderTests.scale) throws -> CGImage {
        let renderer = ImageRenderer(content: view.frame(width: width, height: height)
            .environment(\.colorScheme, .light))
        renderer.scale = scale
        return try XCTUnwrap(renderer.cgImage)
    }

    private func writePNG(_ image: CGImage, to url: URL) throws {
        let data = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        try data.write(to: url)
    }

    private func writeGIF(_ frames: [CGImage], delay: Double, to url: URL) throws {
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString,
                                                                        frames.count, nil))
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [
            kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for frame in frames {
            CGImageDestinationAddImage(destination, frame, [kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: delay]] as CFDictionary)
        }
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }

    /// One labelled strip of frames (PNG, 2x) plus a GIF of the whole sequence (15 fps), sized for a PR body.
    /// `scene` draws one moment into a `cell`×`cell` square.
    private func render(name: String, duration: TimeInterval, strip times: [TimeInterval], into dir: URL,
                        cell: CGFloat = CelebrationRenderTests.box + CelebrationRenderTests.pad * 2,
                        background: Color = .white, gifStart: TimeInterval = 0, gifScale: CGFloat = 2,
                        scene: @escaping (TimeInterval) -> AnyView) throws {
        let stripView = HStack(spacing: 0) {
            ForEach(Array(times.enumerated()), id: \.offset) { _, t in
                VStack(spacing: 2) {
                    scene(t).frame(width: cell, height: cell)
                    Text(String(format: "%.2fs", t)).font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .frame(width: cell, height: cell + 16)
            }
        }
        .background(background)
        try writePNG(try snapshot(stripView, width: cell * CGFloat(times.count), height: cell + 16, scale: 2),
                     to: dir.appendingPathComponent("\(name).png"))

        let step = 1.0 / 15
        var frames: [CGImage] = []
        for t in stride(from: gifStart, through: duration + 0.3, by: step) {
            frames.append(try snapshot(scene(t).frame(width: cell, height: cell).background(background),
                                       width: cell, height: cell, scale: gifScale))
        }
        try writeGIF(frames, delay: step, to: dir.appendingPathComponent("\(name).gif"))
    }

    typealias Sprite = CelebrationPlayer.Sprite

    /// The popover header: the sprite layer inside the clipped 76pt box, the light layer overflowing it
    /// (as `CompanionHeader` composes them), over the popover's light background. Evolution dims the header.
    private func headerScene(_ kind: CelebrationPlayer.Kind, images: [Sprite: NSImage],
                             reduce: Bool) -> (TimeInterval) -> AnyView {
        let sprites = images.mapValues { AnyView(self.fitted($0)) }
        return { t in
            var dim = 0.0
            if case .evolve = kind { dim = EvolutionEffect.frame(at: t, reduceMotion: reduce).dim }
            return AnyView(ZStack {
                RoundedRectangle(cornerRadius: 12).fill(Color(red: 0.05, green: 0.07, blue: 0.18).opacity(0.6 * dim))
                    .frame(width: Self.box * 1.9, height: Self.box * 1.5)
                self.chrome(CelebrationSequenceView(kind: kind, elapsed: t, size: Self.box, reduceMotion: reduce,
                                                    layer: .sprite, sprites: sprites))
                    .overlay {
                        CelebrationSequenceView(kind: kind, elapsed: t, size: Self.box, reduceMotion: reduce,
                                                layer: .light, sprites: sprites)
                    }
            })
        }
    }

    static let petSize: CGFloat = 128
    /// A stand-in desktop behind the transparent floating pet. Flat: a gradient dithers into a GIF twice the size.
    static let desktop = Color(red: 0.3, green: 0.36, blue: 0.52)

    /// The floating pet: no chrome, the sprite layer at the pet size and the light layer around it (the
    /// controller's click-through effect panel) over a desktop.
    private func petScene(_ kind: CelebrationPlayer.Kind, images: [Sprite: NSImage],
                          reduce: Bool) -> (TimeInterval) -> AnyView {
        let sprites = images.mapValues { AnyView(self.fitted($0, box: Self.petSize)) }
        return { t in
            AnyView(ZStack {
                Self.desktop
                CelebrationSequenceView(kind: kind, elapsed: t, size: Self.petSize, reduceMotion: reduce,
                                        layer: .both, sprites: sprites)
            })
        }
    }

    private var headerCell: CGFloat { Self.box * CelebrationFX.overflow + 4 }
    private var petCell: CGFloat { Self.petSize * CelebrationFX.overflow }

    // MARK: Renders

    private static let headerBackground = Color(white: 0.93)

    func testWriteHatchByRarity() async throws {
        let dir = try outputDirectory()
        let hatchlings: [Rarity: Int] = [.common: 10, .uncommon: 133, .rare: 147, .legendary: 150]
        let s = try await sprites(Array(hatchlings.values))
        for rarity in [Rarity.common, .uncommon, .rare, .legendary] {
            let p = HatchEffect.profile(for: rarity)
            let id = try XCTUnwrap(hatchlings[rarity])
            let kind = CelebrationPlayer.Kind.hatch(p, egg: Sprite(speciesID: nil), reveal: Sprite(speciesID: id))
            let images = [Sprite(speciesID: nil): s.egg, Sprite(speciesID: id): try XCTUnwrap(s.mons[id])]
            for reduce in [false, true] {
                let reveal = HatchEffect.revealTime(p, reduceMotion: reduce)
                let duration = HatchEffect.duration(p, reduceMotion: reduce)
                var times = reduce ? [0, reveal * 0.5, reveal - 0.05]
                    : HatchEffect.wobbleStarts(p).map { $0 + HatchEffect.wobbleLength / 6 } + [reveal - 0.1]
                times += reduce ? [reveal, reveal + 0.2, duration] : [reveal, reveal + 0.12, reveal + 0.3, reveal + 0.55, duration]
                try render(name: "hatch-\(rarity.rawValue)\(reduce ? "-reduced" : "")", duration: duration,
                           strip: times, into: dir, cell: headerCell, background: Self.headerBackground,
                           gifScale: 1.25, scene: headerScene(kind, images: images, reduce: reduce))
                if rarity == .legendary, !reduce {
                    // The busiest sequence (rays, motes, shards): a smaller GIF keeps it under ~600 KB.
                    try render(name: "floating-hatch-legendary", duration: duration, strip: times, into: dir,
                               cell: petCell, gifScale: 0.75, scene: petScene(kind, images: images, reduce: false))
                }
            }
        }
    }

    func testWriteEvolution() async throws {
        let dir = try outputDirectory()
        let s = try await sprites([4, 5])
        let kind = CelebrationPlayer.Kind.evolve(from: Sprite(speciesID: 4), to: Sprite(speciesID: 5))
        let images = [Sprite(speciesID: 4): try XCTUnwrap(s.mons[4]), Sprite(speciesID: 5): try XCTUnwrap(s.mons[5])]
        for reduce in [false, true] {
            let reveal = EvolutionEffect.revealTime(reduceMotion: reduce)
            let duration = EvolutionEffect.duration(reduceMotion: reduce)
            let times: [TimeInterval] = reduce ? [0, 0.25, reveal, reveal + 0.2, duration]
                : [0, 0.35, 0.7, 1.05, 1.45, 1.85, 2.2, 2.45, reveal, reveal + 0.12, reveal + 0.3, duration]
            try render(name: "evolve\(reduce ? "-reduced" : "")", duration: duration, strip: times, into: dir,
                       cell: headerCell, background: Self.headerBackground, gifScale: 1.25,
                       scene: headerScene(kind, images: images, reduce: reduce))
        }
    }

    func testWriteDittoReveal() async throws {
        let dir = try outputDirectory()
        let s = try await sprites([16, PokemonOdds.dittoSpeciesID])
        let ditto = PokemonOdds.dittoSpeciesID
        let kind = CelebrationPlayer.Kind.dittoReveal(disguise: Sprite(speciesID: 16), ditto: Sprite(speciesID: ditto))
        let images = [Sprite(speciesID: 16): try XCTUnwrap(s.mons[16]), Sprite(speciesID: ditto): try XCTUnwrap(s.mons[ditto])]
        for reduce in [false, true] {
            let r = DittoRevealEffect.revealAt
            let duration = DittoRevealEffect.duration(reduceMotion: reduce)
            try render(name: "ditto-reveal\(reduce ? "-reduced" : "")", duration: duration,
                       strip: [0, r * 0.6, r, r + 0.1, r + 0.3, r + 0.55, duration], into: dir,
                       cell: headerCell, background: Self.headerBackground, gifScale: 1.25,
                       scene: headerScene(kind, images: images, reduce: reduce))
        }
    }

    /// **Illustration of main's behavior (38e3e55), not production code** — for the PR's "before" images.
    /// main's `playCelebrationIfNeeded` was driven by `withAnimation`, not a function of time, so this
    /// re-creates it from its parameters: at the update (t = 0) the sprite box already shows the result,
    /// a white flash 0.85 → 0 (easeOut 0.8s) covers it and the whole box springs 0.6 → 1 (response 0.5,
    /// damping 0.55). Hatch and evolve used exactly that; graduation had no effect (the egg just replaced
    /// the Pokémon). Negative times are the moment before the update.
    func testWriteMainBehaviorIllustrations() async throws {
        let dir = try outputDirectory()
        let s = try await sprites([150, 4, 5, 6])
        let mewtwo = try XCTUnwrap(s.mons[150]), charmander = try XCTUnwrap(s.mons[4])
        let charmeleon = try XCTUnwrap(s.mons[5]), charizard = try XCTUnwrap(s.mons[6])
        let times: [TimeInterval] = [-0.1, 0, 0.1, 0.2, 0.35, 0.5, 0.8]
        let cases: [(String, NSImage, NSImage, Bool)] = [
            ("before-hatch-illustration", s.egg, mewtwo, true),
            ("before-evolve-illustration", charmander, charmeleon, true),
            ("before-graduate-illustration", charizard, s.egg, false),
        ]
        for (name, before, after, animated) in cases {
            try render(name: name, duration: 1.0, strip: animated ? times : [-0.1, 0, 0.5], into: dir,
                       gifStart: -0.6) { t in
                AnyView(MainCelebrationIllustration(elapsed: t, animated: animated, box: Self.box) {
                    self.fitted(before)
                } after: { self.fitted(after) })
            }
        }
    }

    func testWriteGraduation() async throws {
        let dir = try outputDirectory()
        let s = try await sprites([6])
        let kind = CelebrationPlayer.Kind.graduate(Sprite(speciesID: 6), egg: Sprite(speciesID: nil))
        let images = [Sprite(speciesID: 6): try XCTUnwrap(s.mons[6]), Sprite(speciesID: nil): s.egg]
        for reduce in [false, true] {
            let duration = GraduationEffect.duration(reduceMotion: reduce)
            let times: [TimeInterval] = reduce ? [0, 0.3, 0.6, 0.9, duration]
                : [0.1, 0.3, 0.42, 0.62, 0.85, 1.05, 1.25, 1.55, 1.85, 2.2, 2.88, 3.0, 3.3, duration]
            try render(name: "graduate\(reduce ? "-reduced" : "")", duration: duration, strip: times, into: dir,
                       cell: headerCell, background: Self.headerBackground, gifScale: 1.25,
                       scene: headerScene(kind, images: images, reduce: reduce))
            if !reduce {
                try render(name: "floating-graduate", duration: duration, strip: times, into: dir,
                           cell: petCell, gifScale: 1, scene: petScene(kind, images: images, reduce: false))
            }
        }
    }
}

/// main(38e3e55)의 연출을 파라미터로 다시 그린 **설명용 그림**(제품 코드 아님). main 은 칸 전체에
/// `.scaleEffect(celebScale)` 를 걸고 그 위에 칸 크기 흰 플래시를 얹었다 — 그래서 칸 테두리까지 같이 커진다.
private struct MainCelebrationIllustration<Before: View, After: View>: View {
    let elapsed: TimeInterval
    let animated: Bool
    let box: CGFloat
    @ViewBuilder var before: Before
    @ViewBuilder var after: After

    /// SwiftUI `.spring(response: 0.5, dampingFraction: 0.55)` 의 감쇠 진동(0.6 → 1).
    static func springScale(_ t: Double) -> Double {
        let omega = 2 * Double.pi / 0.5, zeta = 0.55
        let damped = omega * (1 - zeta * zeta).squareRoot()
        return 1 - 0.4 * exp(-zeta * omega * t) * (cos(damped * t) + zeta * omega / damped * sin(damped * t))
    }

    /// `.easeOut` = cubic-bezier(0, 0, 0.58, 1) 의 진행률.
    static func easeOut(_ x: Double) -> Double {
        let x = min(1, max(0, x))
        var lo = 0.0, hi = 1.0
        for _ in 0..<40 {
            let u = (lo + hi) / 2
            let bx = 3 * (1 - u) * u * u * 0.58 + u * u * u
            if bx < x { lo = u } else { hi = u }
        }
        let u = (lo + hi) / 2
        return 3 * (1 - u) * u * u + u * u * u
    }

    var body: some View {
        let shown = elapsed >= 0
        let scale = animated && shown ? Self.springScale(elapsed) : 1
        let flash = animated && shown ? 0.85 * (1 - Self.easeOut(elapsed / 0.8)) : 0
        ZStack {
            ZStack {
                if shown { after } else { before }
            }
            .frame(width: box, height: box)
            .background(Color.secondary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .scaleEffect(scale)
            RoundedRectangle(cornerRadius: 12).fill(Color.white).opacity(flash)
        }
        .frame(width: box, height: box)
    }
}
