import AppKit
import SwiftUI
import XCTest
import Vision
@testable import PokeTokenBar

/// Used for the optional keyboard-focus check on an interactive desktop.
private final class SessionKeyTestWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class SessionKeySettingsRenderingTests: XCTestCase {
    func testSessionKeyEntryOpensInsideViewportAndPreservesDifficultyControls() async throws {
        let suite = "SessionKeySettingsRendering-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(suite).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let usage = UsageStore(providers: [], autoRefresh: false, defaults: defaults)
        let companion = CompanionStore(fileURL: file, defaults: defaults)
        companion.setLanguage(.en)
        let navigation = PopoverNavigation()
        navigation.openSessionKeySettings()
        let host = NSHostingController(rootView: SettingsView(
            onClose: {}, onChooseRepresentative: {}, startExpanded: navigation.expandAdvancedOnOpen)
            .environment(usage).environment(companion).environment(UpdateChecker())
            .frame(width: PopoverMetrics.width)
            .environment(\.colorScheme, .light))
        let previousKeyWindow = NSApp.keyWindow
        let window = SessionKeyTestWindow(contentRect: NSRect(x: -10000, y: -10000, width: PopoverMetrics.width, height: 460),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentViewController = host
        window.makeKeyAndOrderFront(nil)
        defer {
            window.orderOut(nil)
            previousKeyWindow?.makeKey()
        }
        host.view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(500))
        host.view.layoutSubtreeIfNeeded()
        let views = descendants(of: host.view)
        let secure = try XCTUnwrap(views.compactMap { $0 as? NSSecureTextField }.first)
        let rect = secure.convert(secure.bounds, to: host.view)
        XCTAssertTrue(host.view.bounds.contains(rect), "session key entry must be visible after scrolling")
        // Hosted CI renders the layout but does not grant this XCTest window an editor.
        // Verify keyboard focus on an interactive Mac with PTB_VERIFY_KEYBOARD_FOCUS=1.
        if ProcessInfo.processInfo.environment["PTB_VERIFY_KEYBOARD_FOCUS"] == "1" {
            XCTAssertNotNil(secure.currentEditor(), "session key entry must receive keyboard focus")
            XCTAssertTrue(secure.currentEditor() === window.firstResponder)
        }
        let nativeSliders = views.compactMap { $0 as? NSSlider }
        if nativeSliders.isEmpty {
            // Newer SwiftUI runtimes draw sliders without NSSlider backing views.
            // Verify each actual track; labels alone must not satisfy this fallback.
            let scroll = try XCTUnwrap(views.compactMap { $0 as? NSScrollView }.first)
            for label in [companion.l.difficultyGrowthLabel, companion.l.difficultyShopLabel,
                          companion.l.warning, companion.l.critical] {
                try await assertVisibleSlider(label: label, host: host.view, scroll: scroll)
            }
        } else {
            // Growth, shop prices, warning, and critical controls on AppKit-backed runtimes.
            XCTAssertEqual(nativeSliders.count, 4,
                           "growth and shop difficulty controls must survive the Settings merge")
        }
        XCTAssertTrue(navigation.showSettings)
        navigation.reset()
        XCTAssertFalse(navigation.expandAdvancedOnOpen)
    }

    private func assertVisibleSlider(label: String, host: NSView, scroll: NSScrollView) async throws {
        let document = try XCTUnwrap(scroll.documentView)
        let maximum = max(0, document.bounds.height - scroll.contentView.bounds.height)
        for offset in stride(from: 0.0, through: maximum + 250, by: 250) {
            scroll.contentView.scroll(to: NSPoint(x: 0, y: min(offset, maximum)))
            scroll.reflectScrolledClipView(scroll.contentView)
            try await Task.sleep(for: .milliseconds(100))
            host.layoutSubtreeIfNeeded()
            guard let rect = try textRect(label, in: host),
                  scroll.convert(scroll.contentView.bounds, from: scroll.contentView)
                    .contains(host.convert(rect, to: scroll)) else { continue }
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let scaleX = Double(bitmap.pixelsWide) / host.bounds.width
            let scaleY = Double(bitmap.pixelsHigh) / host.bounds.height
            let centerY = (host.isFlipped ? rect.midY : host.bounds.height - rect.midY) * scaleY
            // The central track lies to the right of the label and before the value.
            // Search a narrow band for a continuous horizontal stroke; labels alone cannot pass.
            var longestRun = 0
            for y in Int(centerY - 6 * scaleY)...Int(centerY + 6 * scaleY) {
                var run = 0
                for x in Int(host.bounds.width * 0.34 * scaleX)...Int(host.bounds.width * 0.74 * scaleX) {
                    let color = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                    let brightness = (color.redComponent + color.greenComponent + color.blueComponent) / 3
                    if color.alphaComponent > 0.9 && brightness > 0.05 && brightness < 0.9 {
                        run += 1
                        longestRun = max(longestRun, run)
                    } else { run = 0 }
                }
            }
            XCTAssertGreaterThan(Double(longestRun) / scaleX, 60, "Missing rendered slider track: \(label)")
            return
        }
        XCTFail("Missing visible slider row: \(label)")
    }

    private func textRect(_ text: String, in host: NSView) throws -> NSRect? {
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        try VNImageRequestHandler(cgImage: XCTUnwrap(bitmap.cgImage)).perform([request])
        guard let observation = request.results?.first(where: {
            $0.topCandidates(1).first?.string == text
        }) else { return nil }
        let rect = observation.boundingBox
        return NSRect(x: rect.minX * host.bounds.width,
                      y: (host.isFlipped ? 1 - rect.maxY : rect.minY) * host.bounds.height,
                      width: rect.width * host.bounds.width, height: rect.height * host.bounds.height)
    }

    private func descendants(of view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { descendants(of: $0) }
    }
}
