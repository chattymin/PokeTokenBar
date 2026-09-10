import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

@MainActor
final class LimitProgressRenderingTests: XCTestCase {
    func testRemainingModeReversesRenderedFillAndClampsExhaustedQuota() throws {
        let suite = "LimitProgressRendering-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UsageStore(providers: [], autoRefresh: false, defaults: defaults)

        func renderedPercent(_ used: Double) throws -> Double {
            let view = LimitProgressBar(usedPercent: used, tint: .blue)
                .environment(store).frame(width: 240, height: 20)
            let host = NSHostingController(rootView: view)
            host.view.frame = NSRect(x: 0, y: 0, width: 240, height: 20)
            host.view.layoutSubtreeIfNeeded()
            func descendants(_ view: NSView) -> [NSView] {
                [view] + view.subviews.flatMap(descendants)
            }
            let views = descendants(host.view)
            let bar = try XCTUnwrap(views.compactMap { $0 as? NSProgressIndicator }.first,
                                   views.map { String(describing: type(of: $0)) }.joined(separator: ","))
            return bar.doubleValue / bar.maxValue * 100
        }

        store.limitDisplayMode = .used
        XCTAssertEqual(try renderedPercent(25), 25, accuracy: 0.01)
        store.limitDisplayMode = .remaining
        XCTAssertEqual(try renderedPercent(25), 75, accuracy: 0.01)
        XCTAssertEqual(try renderedPercent(125), 0, accuracy: 0.01)
        XCTAssertEqual(try renderedPercent(0), 100, accuracy: 0.01)
        store.limitDisplayMode = .used
        XCTAssertEqual(try renderedPercent(25), 25, accuracy: 0.01)
    }
}
