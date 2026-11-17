import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

/// Stroking the floating pet: pure detector + priority/sizing logic. Real mouse strokes
/// cannot be simulated here; the detector is fed the (x, timestamp) samples they produce.
final class PettingDetectorTests: XCTestCase {
    private let stroke: CGFloat = 14

    /// Feed samples every 50 ms along the given x waypoints; returns how many samples triggered.
    private func triggers(_ waypoints: [CGFloat], step: TimeInterval = 0.05,
                          detector: inout PettingDetector) -> Int {
        var time: TimeInterval = 100
        var count = 0
        for x in waypoints {
            if detector.feed(x: x, at: time, minStroke: stroke) { count += 1 }
            time += step
        }
        return count
    }

    func testWiggleTriggers() {
        var detector = PettingDetector()
        // Four 15pt back-and-forth turns (at samples 3, 5, 7, 9) = 4 reversals.
        // Every reversal from the third on fires, so a longer wiggle keeps refreshing the bubble.
        XCTAssertEqual(triggers([10, 25, 40, 25, 10, 25, 40, 25, 10, 25, 40], detector: &detector), 2,
                       "the third and fourth reversal both qualify")
    }

    func testStraightPassDoesNotTrigger() {
        var detector = PettingDetector()
        XCTAssertEqual(triggers(Array(stride(from: CGFloat(0), through: 200, by: 10)), detector: &detector), 0)
    }

    func testSlowBackAndForthDoesNotTrigger() {
        var detector = PettingDetector()
        // Same 30pt strokes at 0.8 s per stroke: three reversals span 1.6 s, outside the 1.2 s window.
        // (0.5 s per stroke is a legitimate 2 Hz wiggle: three reversals in 1.0 s do trigger.)
        XCTAssertEqual(triggers([10, 40, 10, 40, 10, 40, 10, 40], step: 0.8, detector: &detector), 0)
    }

    func testLongPauseResetsState() {
        var detector = PettingDetector()
        XCTAssertEqual(triggers([10, 40, 10, 40], detector: &detector), 0, "only 2 reversals so far")
        var time: TimeInterval = 100 + PettingDetector.window + 1
        // After the pause one more reversal must not complete the old count.
        XCTAssertFalse(detector.feed(x: 10, at: time, minStroke: stroke))
        time += 0.05
        XCTAssertFalse(detector.feed(x: 40, at: time, minStroke: stroke))
        time += 0.05
        XCTAssertFalse(detector.feed(x: 10, at: time, minStroke: stroke))
    }

    func testJitterBelowMinimumStrokeDoesNotTrigger() {
        var detector = PettingDetector()
        // 8pt strokes against a 14pt minimum, fast and many.
        let jitter = (0..<30).map { CGFloat($0 % 2 == 0 ? 10 : 18) }
        XCTAssertEqual(triggers(jitter, detector: &detector), 0)
    }

    func testMinimumStrokeScalesTheThreshold() {
        // 20pt strokes: enough for a 14pt minimum, too short for a 40pt one (big pet).
        let wiggle: [CGFloat] = [10, 30, 10, 30, 10, 30, 10]
        var small = PettingDetector()
        var big = PettingDetector()
        var time: TimeInterval = 100
        var smallHits = 0, bigHits = 0
        for x in wiggle {
            if small.feed(x: x, at: time, minStroke: 14) { smallHits += 1 }
            if big.feed(x: x, at: time, minStroke: 40) { bigHits += 1 }
            time += 0.05
        }
        XCTAssertGreaterThan(smallHits, 0)
        XCTAssertEqual(bigHits, 0)
    }

    func testResetForgetsReversals() {
        var detector = PettingDetector()
        XCTAssertEqual(triggers([10, 40, 10, 40], detector: &detector), 0)
        detector.reset()   // mouse exit or mouse down
        // Continuing at the same instant: one more reversal alone must not trigger.
        XCTAssertEqual(triggers([10, 40, 10], detector: &detector), 0)
    }
}

/// The heart bubble: Bool state decision, priority, tooltip suppression and the pixel art.
@MainActor
final class StrokeHeartBubbleTests: XCTestCase {
    func testStrokeShowsHeartsUnlessALimitAlertIsActive() {
        XCTAssertTrue(FloatingPetController.heartsShowing(afterStrokeWithAlertActive: false))
        XCTAssertFalse(FloatingPetController.heartsShowing(afterStrokeWithAlertActive: true))
    }

    func testHeartsDurationIsAboutTwoSeconds() {
        XCTAssertEqual(FloatingPetController.heartDuration, .milliseconds(1800))
    }

    func testHeartsOrAlertReserveBubbleHeadroom() {
        XCTAssertTrue(FloatingPetController.isShowingBubble(alertActive: false, heartsShowing: true))
        XCTAssertTrue(FloatingPetController.isShowingBubble(alertActive: true, heartsShowing: false))
        XCTAssertFalse(FloatingPetController.isShowingBubble(alertActive: false, heartsShowing: false))
    }

    func testNativeToolTipIsClearedOnlyWhileHeartsShow() {
        XCTAssertNil(FloatingPetController.nativeToolTip("Today: 1 tokens", heartsShowing: true))
        XCTAssertEqual(FloatingPetController.nativeToolTip("Today: 1 tokens", heartsShowing: false),
                       "Today: 1 tokens", "a limit alert alone keeps the tooltip, as on main")
    }

    func testHeartStateStartsHidden() {
        XCTAssertFalse(PetHeartState().isShowing)
    }

    func testHeartBubbleArtRowsShareOneWidth() {
        let rows = HeartBubbleArt.rows
        XCTAssertTrue(rows.allSatisfy { $0.count == rows[0].count })
    }

    func testBubbleHeartAndTailAreSymmetricExceptShadeAndHighlight() {
        for row in HeartBubbleArt.rows {
            let plain = row.map { "RDH".contains($0) ? Character("R") : $0 }
            XCTAssertEqual(String(plain.reversed()), String(plain), row)
        }
    }

    func testTailTipSitsAtTheHorizontalCenter() throws {
        let rows = HeartBubbleArt.rows
        let tip = try XCTUnwrap(rows.last)
        XCTAssertEqual(tip.firstIndex(of: "O").map { tip.distance(from: tip.startIndex, to: $0) }, rows[0].count / 2)
        XCTAssertEqual(tip.filter { $0 == "O" }.count, 1, "tail ends in a single pixel")
    }

    func testHeartBubbleFitsThePanelAndHeadroom() {
        let rows = HeartBubbleArt.rows
        XCTAssertLessThanOrEqual(CGFloat(rows[0].count) * HeartBubbleArt.pixel, FloatingPetController.bubbleMinWidth)
        // Worst case: the sprite touches its box top (visible top 0), so the bubble sits highest.
        XCTAssertLessThanOrEqual(HeartBubbleArt.height - HeartBubbleArt.tailOverlap,
                                 FloatingPetController.bubbleHeadroom)
        let top = SpriteVisibleTop.bubbleTopOffset(visibleTop: 0, bubbleHeight: HeartBubbleArt.height,
                                                   overlap: HeartBubbleArt.tailOverlap)
        XCTAssertGreaterThanOrEqual(top, -FloatingPetController.bubbleHeadroom, "never clipped by the panel top")
    }

    // MARK: anchoring to the visible sprite

    func testTallSpriteTopIsNearTheBoxTop() {
        // 36×66 canvas (Jackie-like) fills the 96pt box height; sprite starts 5% below the canvas top.
        let inset = SpriteVisibleTop.inset(box: 96, imageSize: CGSize(width: 36, height: 66),
                                           opaqueTopFraction: 0.05)
        XCTAssertEqual(inset, 4.8, accuracy: 0.001)
    }

    func testWideShortSpriteTopSitsBelowTheBoxTop() {
        // 60×30 canvas fits 96×48: 24pt of empty box above, then 10% of the canvas is transparent.
        let inset = SpriteVisibleTop.inset(box: 96, imageSize: CGSize(width: 60, height: 30),
                                           opaqueTopFraction: 0.1)
        XCTAssertEqual(inset, 24 + 4.8, accuracy: 0.001)
    }

    func testEggTopUsesItsOwnOpaqueBounds() {
        // Cropped 30×30 egg: square, so no letterboxing; the top 3 rows are empty.
        let inset = SpriteVisibleTop.inset(box: 96, imageSize: CGSize(width: 30, height: 30),
                                           opaqueTopFraction: 0.1)
        XCTAssertEqual(inset, 9.6, accuracy: 0.001)
    }

    func testBubbleTailLandsJustInsideTheVisibleTop() {
        let height = HeartBubbleArt.height
        let top = SpriteVisibleTop.bubbleTopOffset(visibleTop: 24, bubbleHeight: height, overlap: 3)
        XCTAssertEqual(top + height, 24 + 3, accuracy: 0.001, "tail tip 3pt below the visible top")
    }

    func testBubbleOffsetSnapsToWholePoints() {
        let top = SpriteVisibleTop.bubbleTopOffset(visibleTop: 3.84, bubbleHeight: 32, overlap: 3)
        XCTAssertEqual(top, top.rounded())
        XCTAssertEqual(top, -25)
    }

    func testAnchorIsTheMedianFrame() {
        // Rotom-Heat-like: most frames start ~0.3 down the canvas, a few jump to the top.
        let fractions: [CGFloat] = [0, 0, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3, 0.3]
        XCTAssertEqual(SpriteVisibleTop.anchorFraction(of: fractions), 0.3, accuracy: 0.001)
        XCTAssertEqual(SpriteVisibleTop.anchorFraction(of: [0.2]), 0.2, accuracy: 0.001)
        XCTAssertEqual(SpriteVisibleTop.anchorFraction(of: []), 0)
    }

    func testOpaqueTopFractionScansTheFirstVisibleRow() throws {
        let side = 10
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0))
        let data = try XCTUnwrap(rep.bitmapData)
        for i in 0..<(rep.bytesPerRow * side) { data[i] = 0 }
        // One opaque pixel on row 3 (row 0 is the top of the bitmap).
        let index = 3 * rep.bytesPerRow + 4 * 4
        data[index] = 255; data[index + 1] = 0; data[index + 2] = 0; data[index + 3] = 255
        let image = NSImage(size: NSSize(width: side, height: side))
        image.addRepresentation(rep)
        XCTAssertEqual(SpriteVisibleTop.opaqueTopFraction(of: image), 0.3, accuracy: 0.001)
    }

    /// 10×10 test image from per-pixel opaque flags; row 0 is the top.
    private func image(opaque: (_ row: Int, _ column: Int) -> Bool) throws -> NSImage {
        let side = 10
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0))
        let data = try XCTUnwrap(rep.bitmapData)
        for i in 0..<(rep.bytesPerRow * side) { data[i] = 0 }
        for row in 0..<side {
            for column in 0..<side where opaque(row, column) {
                let index = row * rep.bytesPerRow + column * 4
                data[index] = 255; data[index + 3] = 255
            }
        }
        let image = NSImage(size: NSSize(width: side, height: side))
        image.addRepresentation(rep)
        return image
    }

    func testSideColumnsDoNotDecideTheAnchor() throws {
        // Tall side columns (raised arms) from row 0; the center (horn/head) only starts at row 5.
        let sides = try image { row, column in
            (column == 0 || column == 9) ? true : (column >= 4 && column <= 5 && row >= 5)
        }
        XCTAssertEqual(SpriteVisibleTop.opaqueTopFraction(of: sides), 0.5, accuracy: 0.001)
    }

    func testEmptyCentralBandFallsBackToTheFullWidth() throws {
        let sidesOnly = try image { row, column in (column == 0 || column == 9) && row >= 2 }
        XCTAssertEqual(SpriteVisibleTop.opaqueTopFraction(of: sidesOnly), 0.2, accuracy: 0.001)
    }

    func testEveryArtCellHasAColorOrIsTransparent() {
        let cells = Set(HeartBubbleArt.rows.joined())
        XCTAssertEqual(cells, ["O", "W", "R", "D", "H", "."])
        for cell in cells where cell != "." { XCTAssertNotNil(HeartBubbleArt.color(for: cell)) }
    }

    func testHeartsLabelIsLocalizedInEveryLanguage() {
        let labels = AppLanguage.allCases.map { L($0).floatingPetHeartsLabel }
        XCTAssertFalse(labels.contains(""))
        XCTAssertGreaterThan(Set(labels).count, 1)
    }
}

/// Optional sample-data renders of the heart bubble alone and above the floating egg.
/// Set `PTB_PETTING_RENDER_DIR` to write PNGs; otherwise skipped.
@MainActor
final class FloatingPetPettingRenderingTests: XCTestCase {
    func testRenderHeartBubble() throws {
        guard let directory = ProcessInfo.processInfo.environment["PTB_PETTING_RENDER_DIR"] else {
            throw XCTSkip("PTB_PETTING_RENDER_DIR not set")
        }
        let petSize: CGFloat = 96
        let l = L(.en)
        for (scheme, name, desktop) in [
            (ColorScheme.light, "light", NSColor(calibratedWhite: 0.78, alpha: 1)),
            (ColorScheme.dark, "dark", NSColor(calibratedWhite: 0.16, alpha: 1)),
        ] {
            let variants: [(String, AnyView)] = [
                ("bubble", AnyView(HeartBubbleView(l: l))),
                ("before", AnyView(SpriteView(speciesID: nil, size: petSize, animated: false, shiny: false)
                    .frame(width: petSize, height: petSize))),
                ("after", AnyView(
                    SpriteView(speciesID: nil, size: petSize, animated: false, shiny: false,
                               reportsVisibleTop: true)
                        .frame(width: petSize, height: petSize)
                        .overlayPreferenceValue(SpriteVisibleTopKey.self, alignment: .top) { visibleTop in
                            HeartBubbleView(l: l)
                                .offset(y: SpriteVisibleTop.bubbleTopOffset(
                                    visibleTop: visibleTop ?? 0, bubbleHeight: HeartBubbleArt.height,
                                    overlap: HeartBubbleArt.tailOverlap))
                        }
                        .padding(.top, HeartBubbleArt.height))),
            ]
            for (label, content) in variants {
                let renderer = ImageRenderer(content: content
                    .padding(24)
                    .background(Color(nsColor: desktop))
                    .environment(\.colorScheme, scheme))
                renderer.scale = 4
                let image = try XCTUnwrap(renderer.nsImage)
                let rep = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
                let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
                try png.write(to: URL(fileURLWithPath: directory)
                    .appendingPathComponent("pet-\(label)-\(name).png"))
            }
        }
    }

    /// Real sprites (downloaded into a scratch directory, never the user's cache) under the bubble,
    /// each rendered twice: plain, and with a green 1pt guide at the computed visible top.
    /// Logs the numbers behind the anchor. Needs network.
    func testRenderRealSpeciesWithHeartBubble() async throws {
        guard let directory = ProcessInfo.processInfo.environment["PTB_PETTING_RENDER_DIR"] else {
            throw XCTSkip("PTB_PETTING_RENDER_DIR not set")
        }
        let output = URL(fileURLWithPath: directory)
        let sprites = FileManager.default.temporaryDirectory.appendingPathComponent("petting-sprites-\(UUID())")
        try FileManager.default.createDirectory(at: sprites, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sprites) }
        let store = SpriteStore(directory: sprites)
        let base = "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/"
        let l = L(.en)

        // speciesID nil = the egg (loaded through the shared store, as the prayer render does).
        let cases: [(name: String, species: Int?, form: PokemonForm?)] = [
            ("pikachu", 25, nil), ("snorlax", 143, nil), ("onix", 95, nil),
            ("rotom-heat", 479, PokemonForm("heat")), ("egg", nil, nil),
        ]
        for (name, species, form) in cases {
            if let species {
                let asset = PokemonForm.assetName(speciesID: species, form: form)
                let url = try XCTUnwrap(URL(string: base + "versions/generation-v/black-white/animated/\(asset).gif"))
                let (data, response) = try await URLSession.shared.data(from: url)
                XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200, name)
                let key = SpriteStore.cacheKey(speciesID: species, animated: true, shiny: false, form: form)
                try data.write(to: sprites.appendingPathComponent("\(key).gif"))
                let frames = GIFDecoder.capFrameRate(GIFDecoder.frames(from: data), floor: 0.4)
                let fractions = frames.map { SpriteVisibleTop.opaqueTopFraction(of: $0.image) }
                for petSize in [96.0, 192.0] {
                    let top = SpriteVisibleTop.inset(
                        box: CGFloat(petSize), imageSize: frames[0].image.size,
                        opaqueTopFraction: SpriteVisibleTop.anchorFraction(of: fractions))
                    print("[petting] \(name) size=\(Int(petSize)) frames=\(frames.count) image=\(frames[0].image.size) "
                          + "fractions min=\(fractions.min() ?? 0) max=\(fractions.max() ?? 0) "
                          + "anchor=\(SpriteVisibleTop.anchorFraction(of: fractions)) visibleTop=\(top)")
                }
            }
            for petSize in [CGFloat(96), 192] {
                for guide in [false, true] {
                    let sprite = SpriteView(speciesID: species, size: petSize, animated: species != nil,
                                            minFrameDelay: 0.4, spriteStore: store, form: form,
                                            reportsVisibleTop: true)
                        .frame(width: petSize, height: petSize)
                        .overlayPreferenceValue(SpriteVisibleTopKey.self, alignment: .top) { visibleTop in
                            ZStack(alignment: .top) {
                                HeartBubbleView(l: l)
                                    .offset(y: SpriteVisibleTop.bubbleTopOffset(
                                        visibleTop: visibleTop ?? 0, bubbleHeight: HeartBubbleArt.height,
                                        overlap: HeartBubbleArt.tailOverlap))
                                if guide {
                                    Rectangle().fill(Color.green).frame(height: 1)
                                        .offset(y: visibleTop ?? 0)
                                }
                            }
                        }
                        .padding(.top, HeartBubbleArt.height)
                    let renderer = ImageRenderer(content: sprite
                        .padding(24)
                        .background(Color(nsColor: NSColor(calibratedWhite: 0.78, alpha: 1)))
                        .environment(\.colorScheme, .light))
                    renderer.scale = 4
                    let image = try XCTUnwrap(renderer.nsImage)
                    let rep = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
                    let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
                    try png.write(to: output.appendingPathComponent(
                        "real-\(name)-\(Int(petSize))\(guide ? "-guide" : "").png"))
                }
            }
        }
    }
}
