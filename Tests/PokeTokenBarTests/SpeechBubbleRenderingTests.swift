import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

/// The dialogue box is drawn by SwiftUI but sized by `measureSpeechBubbleLayout` (#167). Render
/// the real view and hold the two together, so the truncation guard keeps describing what is drawn.
/// Set `PTB_BUBBLE_RENDER_DIR` to also write PNGs of each bubble (PR images; not committed).
@MainActor
final class SpeechBubbleRenderingTests: XCTestCase {
    private typealias C = FloatingPetController

    private func render(_ content: C.SpeechBubbleContent, animates: Bool = false, scale: CGFloat = 2) throws -> CGImage {
        let renderer = ImageRenderer(content: SpeechBubbleView(content: content, animates: animates))
        renderer.scale = scale
        return try XCTUnwrap(renderer.cgImage, "render failed")
    }

    private func contents(_ l: L) -> [(name: String, content: C.SpeechBubbleContent)] {
        let warning = UsageStore.LimitAlert(key: "w", window: l.claudeWeekly, isCritical: false, utilization: 85)
        let critical = UsageStore.LimitAlert(key: "c", window: l.claudeFiveHour, isCritical: true, utilization: 96)
        return [
            ("waiting", C.bubbleContent(.agentWaiting(label: nil, message: nil, others: 0), l: l)),
            ("done", C.bubbleContent(.agentDone(label: nil, message: nil), l: l)),
            ("done-long", C.bubbleContent(.agentDone(label: nil, message: String(repeating: "W", count: 80)), l: l)),
            ("waiting-labeled", C.bubbleContent(.agentWaiting(label: "my-web-app", message: nil, others: 0), l: l)),
            ("waiting-labeled-plus1", C.bubbleContent(.agentWaiting(label: "my-web-app", message: nil, others: 1), l: l)),
            ("done-labeled", C.bubbleContent(.agentDone(label: "my-web-app", message: nil), l: l)),
            ("waiting-long-label-plus7", C.bubbleContent(
                .agentWaiting(label: String(repeating: "W", count: 23) + "…", message: nil, others: 7), l: l)),
            ("limit-warning", C.bubbleContent(.limit(warning), l: l)),
            ("limit-critical", C.bubbleContent(.limit(critical), l: l)),
        ]
    }

    func testRenderedBubbleMatchesTheMeasuredLayout() throws {
        for lang in AppLanguage.allCases {
            for (name, content) in contents(L(lang)) {
                let image = try render(content)
                let layout = C.measureSpeechBubbleLayout(title: content.title, body: content.body)
                XCTAssertEqual(CGFloat(image.width) / 2, C.bubbleMinWidth, accuracy: 0.5, "\(lang.rawValue) \(name)")
                XCTAssertEqual(CGFloat(image.height) / 2, layout.size.height, accuracy: 2,
                               "\(lang.rawValue) \(name): drawn height must match the measured chrome")
                XCTAssertLessThanOrEqual(CGFloat(image.height) / 2 + C.bubbleSpacing, C.bubbleHeadroom,
                                         "\(lang.rawValue) \(name) does not fit above the pet")
            }
        }
    }

    func testCriticalTitleStaysRed() throws {
        let l = L(.en)
        let alert = { (critical: Bool) in
            UsageStore.LimitAlert(key: "k", window: l.claudeWeekly, isCritical: critical, utilization: 96)
        }
        // Whole bubble: the title is the only red, so a warning bubble has none at all.
        let critical = try Self.count(in: render(C.bubbleContent(.limit(alert(true)), l: l)), where: Self.isRed)
        let warning = try Self.count(in: render(C.bubbleContent(.limit(alert(false)), l: l)), where: Self.isRed)
        XCTAssertGreaterThan(critical, 50, "the critical title must be visibly red")
        XCTAssertEqual(warning, 0)
    }

    /// With motion, the bubble starts empty and types in; without it, the text is all there at once.
    func testAnimatedBubbleStartsEmptyAndStaticBubbleStartsFull() throws {
        let content = C.bubbleContent(.agentWaiting(label: nil, message: nil, others: 0), l: L(.en))
        // Only the text column: the frame is black too.
        let column = CGRect(x: C.bubbleHorizontalPadding, y: C.bubbleTopPadding,
                            width: C.bubbleContentWidth, height: 30)
        let full = try Self.count(in: render(content, animates: false), region: column, where: Self.isText)
        let typing = try Self.count(in: render(content, animates: true), region: column, where: Self.isText)
        XCTAssertGreaterThan(full, 100)
        XCTAssertLessThan(typing, full / 10, "nothing is revealed before the first tick")
    }

    /// The frame and its corner balls are whole-point rectangles: at 1× and 2× the band holds
    /// only ink, paper, the exact ball grey or nothing — no anti-aliased grey, no red.
    func testFrameIsPixelCrispAtOneAndTwoTimes() throws {
        let content = C.bubbleContent(.agentDone(label: nil, message: nil), l: L(.en))
        let edge = C.bubbleHorizontalPadding
        for scale: CGFloat in [1, 2] {
            let image = try render(content, scale: scale)
            let size = CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
            let band: [CGRect] = [
                CGRect(x: 0, y: 0, width: size.width, height: edge),
                CGRect(x: 0, y: size.height - edge, width: size.width, height: edge),
                CGRect(x: 0, y: 0, width: edge, height: size.height),
                CGRect(x: size.width - edge, y: 0, width: edge, height: size.height),
            ]
            var ink = 0
            for region in band {
                XCTAssertEqual(try Self.count(in: image, region: region, scale: scale, includeTranslucent: true,
                                              where: { !Self.isInk($0, $1, $2) && !Self.isPaper($0, $1, $2) && !Self.isBallGrey($0, $1, $2) }),
                               0, "\(scale)x: grey or half-covered pixels in the frame band \(region)")
                ink += try Self.count(in: image, region: region, scale: scale, where: Self.isInk)
            }
            XCTAssertGreaterThan(ink, Int(400 * scale), "\(scale)x: the frame must actually be drawn")
        }
    }

    /// Each corner carries a monochrome Poké Ball: grey top, white bottom, black outline and band.
    func testEveryCornerHasAPokeBall() throws {
        let content = C.bubbleContent(.agentWaiting(label: nil, message: nil, others: 0), l: L(.ko))
        for scale: CGFloat in [1, 2] {
            let image = try render(content, scale: scale)
            let size = CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
            let corners = [CGPoint(x: 0, y: 0), CGPoint(x: size.width - 10, y: 0),
                           CGPoint(x: 0, y: size.height - 10), CGPoint(x: size.width - 10, y: size.height - 10)]
            for corner in corners {
                let top = CGRect(x: corner.x, y: corner.y, width: 10, height: 4)
                let bottom = CGRect(x: corner.x, y: corner.y + 6, width: 10, height: 4)
                let ball = CGRect(x: corner.x, y: corner.y, width: 10, height: 10)
                let px = scale * scale
                XCTAssertGreaterThanOrEqual(try Self.count(in: image, region: top, scale: scale, where: Self.isBallGrey),
                                            Int(20 * px), "\(scale)x \(corner): grey top half")
                XCTAssertGreaterThanOrEqual(try Self.count(in: image, region: bottom, scale: scale, where: Self.isPaper),
                                            Int(10 * px), "\(scale)x \(corner): white bottom half")
                XCTAssertGreaterThanOrEqual(try Self.count(in: image, region: ball, scale: scale, where: Self.isInk),
                                            Int(30 * px), "\(scale)x \(corner): black outline and band")
                XCTAssertEqual(try Self.count(in: image, region: bottom, scale: scale, where: Self.isBallGrey), 0,
                               "\(scale)x \(corner): the white half is the bottom one")
            }
        }
    }

    func testTypewriterAndBlinkAreBounded() {
        for count in [1, 5, 12, 20, 40, 120, 500] {
            let steps = C.typewriterSteps(characterCount: count)
            XCTAssertGreaterThanOrEqual(steps, 1)
            XCTAssertLessThanOrEqual(Double(steps) * C.typewriterTick, 0.8 + 1e-9, "\(count) chars")
            if count >= 12 {
                XCTAssertGreaterThanOrEqual(Double(steps) * C.typewriterTick, 0.4 - 1e-9, "\(count) chars")
            }
            let revealed = (0...steps).map { C.revealedCount(step: $0, of: steps, characterCount: count) }
            XCTAssertEqual(revealed.first, 0)
            XCTAssertEqual(revealed.last, count, "the last tick shows everything")
            XCTAssertEqual(revealed, revealed.sorted(), "never un-types")
        }
        XCTAssertGreaterThan(C.dialogueBlinkInterval, 0)
        XCTAssertGreaterThan(C.dialogueBlinkLimit, 0)
        XCTAssertLessThanOrEqual(C.dialogueBlinkLimit, 15, "a waiting bubble may stay up for hours; the blink must not")
    }

    /// PR images. Skipped unless `PTB_BUBBLE_RENDER_DIR` is set.
    func testWriteBubbleRenders() throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_BUBBLE_RENDER_DIR"] else {
            throw XCTSkip("set PTB_BUBBLE_RENDER_DIR to write bubble PNGs")
        }
        let dir = URL(fileURLWithPath: output, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for lang in [AppLanguage.ko, .en, .ja] {
            for (name, content) in contents(L(lang)) {
                let rep = NSBitmapImageRep(cgImage: try render(content))
                let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
                try png.write(to: dir.appendingPathComponent("new-\(name)-\(lang.rawValue).png"))
            }
        }
        // Close-up for checking the frame's pixel edges.
        let zoom = NSBitmapImageRep(cgImage: try render(contents(L(.ko))[0].content, scale: 4))
        try XCTUnwrap(zoom.representation(using: .png, properties: [:]))
            .write(to: dir.appendingPathComponent("new-waiting-ko-zoom.png"))
    }

    // MARK: Pixels

    private static func isRed(_ r: Double, _ g: Double, _ b: Double) -> Bool { r > 0.6 && g < 0.3 && b < 0.3 }
    /// The ball's grey (0.45) within rendering tolerance; a half-point ink/white blend is ~0.53.
    private static func isBallGrey(_ r: Double, _ g: Double, _ b: Double) -> Bool {
        max(r, g, b) - min(r, g, b) < 0.02 && abs(r - 0.45) < 0.025
    }
    private static func isInk(_ r: Double, _ g: Double, _ b: Double) -> Bool { max(r, g, b) < 0.1 }
    private static func isPaper(_ r: Double, _ g: Double, _ b: Double) -> Bool { min(r, g, b) > 0.97 }
    private static func isText(_ r: Double, _ g: Double, _ b: Double) -> Bool { max(r, g, b) < 0.35 }

    /// Pixels matching `match`. `region` is in points from the top-left; nil means the whole image.
    /// Translucent pixels are skipped unless `includeTranslucent`, which then counts them all.
    private static func count(in image: CGImage, region: CGRect? = nil, scale: CGFloat = 2,
                              includeTranslucent: Bool = false,
                              where match: (Double, Double, Double) -> Bool) throws -> Int {
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let context = try XCTUnwrap(CGContext(
            data: &data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let area = region.map {
            CGRect(x: $0.minX * scale, y: $0.minY * scale, width: $0.width * scale, height: $0.height * scale)
        } ?? CGRect(x: 0, y: 0, width: width, height: height)
        var hits = 0
        for y in max(0, Int(area.minY))..<min(height, Int(area.maxY)) {
            for x in max(0, Int(area.minX))..<min(width, Int(area.maxX)) {
                let i = (y * width + x) * 4
                let alpha = data[i + 3]
                if alpha == 0 { continue }
                if alpha < 250 {
                    if includeTranslucent { hits += 1 }
                    continue
                }
                if match(Double(data[i]) / 255, Double(data[i + 1]) / 255, Double(data[i + 2]) / 255) { hits += 1 }
            }
        }
        return hits
    }
}
