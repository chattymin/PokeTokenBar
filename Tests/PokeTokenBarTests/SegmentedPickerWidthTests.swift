import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

private struct OfflinePokemon: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

@MainActor
func segmentedControls(in view: NSView) -> [NSSegmentedControl] {
    (view as? NSSegmentedControl).map { [$0] } ?? view.subviews.flatMap(segmentedControls)
}

/// macOS 27.2 shrank full-width segmented pickers to their segments, leaving them left-aligned.
@MainActor
final class SegmentedPickerWidthTests: XCTestCase {
    func testCollectionModePickerSpansContentWidth() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("segmented-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: file) }
        var state = CompanionState()
        state.dex = [DexEntry(baseID: 129, finalID: 130, chainOrder: [129, 130], rarity: .common,
                              caughtAt: Date(timeIntervalSince1970: 1_700_000_000), nature: .hardy,
                              names: [130: ["en": "Gyarados"]])]
        try JSONEncoder().encode(state).write(to: file)
        let store = CompanionStore(provider: OfflinePokemon(), fileURL: file)
        let host = NSHostingView(rootView: CollectionView(store: store, navigation: PopoverNavigation())
            .frame(width: PopoverMetrics.contentWidth, height: 520))
        host.frame = NSRect(x: 0, y: 0, width: PopoverMetrics.contentWidth, height: 520)
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: PopoverMetrics.contentWidth, height: 520),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        host.layoutSubtreeIfNeeded()

        let picker = try XCTUnwrap(segmentedControls(in: host).first { $0.segmentCount == 2 })
        let frame = picker.convert(picker.bounds, to: host)
        XCTAssertEqual(frame.minX, 0, accuracy: 0.5, "dex/catch-log picker must start at the leading edge")
        XCTAssertEqual(frame.width, PopoverMetrics.contentWidth, accuracy: 0.5,
                       "dex/catch-log picker must span the popover content width")
    }
}
