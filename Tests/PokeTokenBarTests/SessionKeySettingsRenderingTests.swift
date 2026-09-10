import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

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
        let navigation = PopoverNavigation()
        navigation.openSessionKeySettings()
        let host = NSHostingController(rootView: SettingsView(
            onClose: {}, onChooseRepresentative: {}, startExpanded: navigation.expandAdvancedOnOpen)
            .environment(usage).environment(companion).environment(UpdateChecker())
            .frame(width: PopoverMetrics.width))
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: PopoverMetrics.width, height: 460),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentViewController = host
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        host.view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(500))
        host.view.layoutSubtreeIfNeeded()
        let views = descendants(of: host.view)
        let secure = try XCTUnwrap(views.compactMap { $0 as? NSSecureTextField }.first)
        let rect = secure.convert(secure.bounds, to: host.view)
        XCTAssertTrue(host.view.bounds.contains(rect), "session key entry must be visible after scrolling")
        XCTAssertNotNil(secure.currentEditor(), "session key entry must receive keyboard focus")
        XCTAssertTrue(secure.currentEditor() === window.firstResponder)
        // Two difficulty sliders plus the existing size/opacity sliders.
        XCTAssertEqual(views.compactMap { $0 as? NSSlider }.count, 4,
                                    "growth and shop difficulty controls must survive the Settings merge")
        XCTAssertTrue(navigation.showSettings)
        navigation.reset()
        XCTAssertFalse(navigation.expandAdvancedOnOpen)
    }

    private func descendants(of view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { descendants(of: $0) }
    }
}
