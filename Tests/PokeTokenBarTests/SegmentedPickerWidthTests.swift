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

    /// `buttonSizing(.flexible)` stretches a picker but never compresses it below its intrinsic width
    /// (equal segments × the widest label). At the regular size the Japanese tabs are wider than the
    /// column, which widens it, and the fixed popover frame then centres it and clips both edges.
    func testFullWidthPickersFitTheColumnInEveryLanguage() async throws {
        guard #available(macOS 26, *) else { throw XCTSkip("macOS 15 compresses segmented pickers to the proposal") }
        var failures: [String] = []
        for language in AppLanguage.allCases {
            for collection in [false, true] {
                let suite = "SegmentedFit-\(UUID())"
                let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
                defer { defaults.removePersistentDomain(forName: suite) }
                let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(suite).json")
                defer { try? FileManager.default.removeItem(at: file) }
                var state = CompanionState()
                state.language = language
                state.dex = [DexEntry(baseID: 129, finalID: 130, chainOrder: [129, 130], rarity: .common,
                                      caughtAt: Date(timeIntervalSince1970: 1_700_000_000), nature: .hardy,
                                      names: [130: ["en": "Gyarados"]])]
                try JSONEncoder().encode(state).write(to: file)
                let companion = CompanionStore(provider: OfflinePokemon(), fileURL: file, defaults: defaults)
                let navigation = PopoverNavigation()
                if collection { navigation.tab = .collection }
                let host = NSHostingView(rootView: PopoverView()
                    .environment(UsageStore(providers: [], autoRefresh: false, defaults: defaults))
                    .environment(companion).environment(UpdateChecker(defaults: defaults))
                    .environment(navigation))
                let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: PopoverMetrics.width, height: 640),
                                      styleMask: .borderless, backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.contentView = host
                window.orderFront(nil)
                defer { window.close() }
                try await Task.sleep(for: .milliseconds(100))
                host.layoutSubtreeIfNeeded()

                let pickers = segmentedControls(in: host).filter { collection ? $0.segmentCount <= 4 : $0.segmentCount == 4 }
                if pickers.count != (collection ? 2 : 1) {
                    failures.append("\(language.rawValue): expected the full-width pickers, found \(pickers.count)")
                }
                for picker in pickers where picker.intrinsicContentSize.width > PopoverMetrics.contentWidth + 0.5 {
                    failures.append("\(language.rawValue) \(picker.segmentCount)-segment picker: intrinsic width "
                        + "\(picker.intrinsicContentSize.width) exceeds the \(PopoverMetrics.contentWidth)pt column")
                }
            }
        }
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n"))
    }
}
