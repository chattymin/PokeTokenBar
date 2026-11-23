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

    /// Same fit as `SpriteView.fitted`: aspect-preserving inside the 76pt slot, pixel art kept crisp.
    private func fitted(_ image: NSImage) -> some View {
        let fit = SpriteFit.size(for: image.size, box: Self.box)
        return Image(nsImage: image).resizable().interpolation(.none)
            .frame(width: fit.width, height: fit.height)
            .frame(width: Self.box, height: Self.box)
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
    private func snapshot(_ view: some View, width: CGFloat, height: CGFloat) throws -> CGImage {
        let renderer = ImageRenderer(content: view.frame(width: width, height: height)
            .environment(\.colorScheme, .light))
        renderer.scale = Self.scale
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

    /// One labelled strip of frames (PNG) plus a GIF of the whole sequence.
    private func render(name: String, duration: TimeInterval, strip times: [TimeInterval], into dir: URL,
                        frame: @escaping (TimeInterval) -> AnyView) throws {
        let cell = Self.box + Self.pad * 2
        let stripView = HStack(spacing: 0) {
            ForEach(Array(times.enumerated()), id: \.offset) { _, t in
                VStack(spacing: 2) {
                    self.chrome(frame(t))
                    Text(String(format: "%.2fs", t)).font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .frame(width: cell, height: cell + 14)
            }
        }
        .background(Color.white)
        try writePNG(try snapshot(stripView, width: cell * CGFloat(times.count), height: cell + 14),
                     to: dir.appendingPathComponent("\(name).png"))

        let step = 1.0 / 20
        var frames: [CGImage] = []
        for t in stride(from: 0.0, through: duration + 0.3, by: step) {
            frames.append(try snapshot(chrome(frame(t)).frame(width: cell, height: cell).background(Color.white),
                                       width: cell, height: cell))
        }
        try writeGIF(frames, delay: step, to: dir.appendingPathComponent("\(name).gif"))
    }

    // MARK: Renders

    func testWriteHatchByRarity() async throws {
        let dir = try outputDirectory()
        let hatchlings: [Rarity: Int] = [.common: 10, .uncommon: 133, .rare: 147, .legendary: 150]
        let s = try await sprites(Array(hatchlings.values))
        for rarity in [Rarity.common, .uncommon, .rare, .legendary] {
            let p = HatchEffect.profile(for: rarity)
            let mon = try XCTUnwrap(s.mons[hatchlings[rarity]!])
            for reduce in [false, true] {
                let reveal = HatchEffect.revealTime(p, reduceMotion: reduce)
                let duration = HatchEffect.duration(p, reduceMotion: reduce)
                // Wobble peaks, then the build-up, the flash peak and the pop.
                var times = reduce ? [0, reveal * 0.5, reveal - 0.05]
                    : HatchEffect.wobbleStarts(p).map { $0 + HatchEffect.wobbleLength / 6 } + [reveal - 0.12]
                times += [reveal, reveal + 0.15, reveal + 0.35, duration]
                try render(name: "hatch-\(rarity.rawValue)\(reduce ? "-reduced" : "")", duration: duration,
                           strip: times, into: dir) { t in
                    AnyView(HatchEffectView(profile: p, elapsed: t, reduceMotion: reduce) {
                        self.fitted(s.egg)
                    } hatchling: { self.fitted(mon) })
                }
            }
        }
    }

    func testWriteEvolution() async throws {
        let dir = try outputDirectory()
        let s = try await sprites([4, 5])
        let from = try XCTUnwrap(s.mons[4]), to = try XCTUnwrap(s.mons[5])
        for reduce in [false, true] {
            let reveal = EvolutionEffect.revealTime(reduceMotion: reduce)
            let duration = EvolutionEffect.duration(reduceMotion: reduce)
            let times: [TimeInterval] = reduce ? [0, 0.25, reveal, reveal + 0.2, duration]
                : [0, 0.25, 0.4, 0.65, 0.9, 1.2, 1.5, 1.7, reveal, reveal + 0.15, reveal + 0.4, duration]
            try render(name: "evolve\(reduce ? "-reduced" : "")", duration: duration, strip: times, into: dir) { t in
                AnyView(EvolutionEffectView(elapsed: t, reduceMotion: reduce) { self.fitted(from) } to: { self.fitted(to) })
            }
        }
    }

    func testWriteDittoReveal() async throws {
        let dir = try outputDirectory()
        let s = try await sprites([16, PokemonOdds.dittoSpeciesID])
        let disguise = try XCTUnwrap(s.mons[16]), ditto = try XCTUnwrap(s.mons[PokemonOdds.dittoSpeciesID])
        for reduce in [false, true] {
            let r = DittoRevealEffect.revealAt
            let duration = DittoRevealEffect.duration(reduceMotion: reduce)
            try render(name: "ditto-reveal\(reduce ? "-reduced" : "")", duration: duration,
                       strip: [0, r * 0.6, r, r + 0.1, r + 0.3, duration], into: dir) { t in
                AnyView(DittoRevealEffectView(elapsed: t, reduceMotion: reduce) { self.fitted(disguise) }
                            ditto: { self.fitted(ditto) })
            }
        }
    }

    func testWriteGraduation() async throws {
        let dir = try outputDirectory()
        let s = try await sprites([6])
        let mon = try XCTUnwrap(s.mons[6])
        for reduce in [false, true] {
            let duration = GraduationEffect.duration(reduceMotion: reduce)
            let times: [TimeInterval] = reduce ? [0, 0.3, 0.6, 0.9, duration]
                : [0, 0.12, 0.35, 0.5, 0.65, 0.8, 0.97, 1.31, 1.65, 1.95, 2.1, duration]
            try render(name: "graduate\(reduce ? "-reduced" : "")", duration: duration, strip: times, into: dir) { t in
                AnyView(GraduationEffectView(elapsed: t, reduceMotion: reduce) { self.fitted(mon) } egg: { self.fitted(s.egg) })
            }
        }
    }
}
