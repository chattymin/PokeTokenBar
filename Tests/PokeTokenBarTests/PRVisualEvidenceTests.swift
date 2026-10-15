import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

@MainActor
final class PRVisualEvidenceTests: XCTestCase {
    func testGenerateSettingsEvidence() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_PR_SETTINGS_SCREENSHOT"] else {
            throw XCTSkip("PTB_PR_SETTINGS_SCREENSHOT is not set")
        }
        let suite = "PRVisualEvidence-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let stateURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(suite).json")
        defer { try? FileManager.default.removeItem(at: stateURL) }
        var state = CompanionState()
        state.language = .en
        try JSONEncoder().encode(state).write(to: stateURL)

        let usage = UsageStore(providers: [], autoRefresh: false, defaults: defaults)
        let companion = CompanionStore(fileURL: stateURL, defaults: defaults)
        let content = SettingsView(onClose: {}, onChooseRepresentative: {})
            .environment(usage)
            .environment(companion)
            .environment(UpdateChecker())
            .frame(width: PopoverMetrics.width)
            .environment(\.colorScheme, .dark)

        let host = NSHostingController(rootView: content)
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000,
                                                   width: PopoverMetrics.width, height: 640),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentViewController = host
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }

        host.view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(300))
        host.view.layoutSubtreeIfNeeded()

        let scroll = try XCTUnwrap(descendants(of: host.view).compactMap { $0 as? NSScrollView }.first)
        let documentHeight = scroll.documentView?.bounds.height ?? 0
        let maximumOffset = max(0, documentHeight - scroll.contentView.bounds.height)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: maximumOffset * 0.55))
        scroll.reflectScrolledClipView(scroll.contentView)
        host.view.layoutSubtreeIfNeeded()

        let bounds = host.view.bounds
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(bounds.width) * 2,
            pixelsHigh: Int(bounds.height) * 2, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = bounds.size
        host.view.cacheDisplay(in: bounds, to: rep)
        let data = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try data.write(to: URL(fileURLWithPath: output))
    }

    private func descendants(of view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { descendants(of: $0) }
    }
}
