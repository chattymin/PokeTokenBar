import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

private struct SegmentedWidthPokemon: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: 129, tree: EvoNode(speciesID: 129, children: [EvoNode(speciesID: 130, children: [])]),
                rarity: .common, names: [129: ["en": "Magikarp"], 130: ["en": "Gyarados"]])
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

/// Every segmented picker the popover mounts must stay inside it, in every language.
///
/// macOS 26+ lays a segmented `Picker` out at its intrinsic width (equal segments × the widest
/// label) instead of compressing it to the proposal. Japanese tabs measured 386pt against the
/// 332pt column, so the picker widened the column, `PopoverView`'s 360pt frame centred it, and
/// every row shifted left with both edges clipped. Layout timing decides when SwiftUI adopts the
/// intrinsic width (the reported shift appeared after switching tabs), so the deterministic check
/// is the control's intrinsic width; the frame checks cover the systems where layout already fills.
@MainActor
final class PopoverSegmentedPickerWidthTests: XCTestCase {
    private enum Screen: String, CaseIterable { case home, collection, settings, recap }

    func testSegmentedPickersFitThePopoverInEveryLanguage() async throws {
        var failures: [String] = []
        for language in AppLanguage.allCases {
            for screen in Screen.allCases {
                failures += try await measure(language: language, screen: screen)
            }
        }
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n"))
    }

    private func measure(language: AppLanguage, screen: Screen) async throws -> [String] {
        let suite = "SegmentedWidth-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(suite).json")
        defer { try? FileManager.default.removeItem(at: file) }
        var state = CompanionState()
        state.language = language
        state.active = MonState(baseID: 129, pathIDs: [129, 130], stageIndex: 1,
                                usedAtStage: 170_100_000, rarity: .common, totalForms: 2, nature: .hardy)
        try JSONEncoder().encode(state).write(to: file)
        let companion = CompanionStore(provider: SegmentedWidthPokemon(), fileURL: file, defaults: defaults)
        let store = UsageStore(providers: [], autoRefresh: false, defaults: defaults)
        let navigation = PopoverNavigation()
        switch screen {
        case .home: break
        case .collection: navigation.tab = .collection
        case .settings: navigation.showSettings = true
        case .recap: navigation.showingRecap = true
        }
        let controller = NSHostingController(rootView: PopoverView()
            .environment(store).environment(companion).environment(UpdateChecker(defaults: defaults))
            .environment(navigation))
        let window = NSWindow(contentViewController: controller)
        window.isReleasedWhenClosed = false
        window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
        window.orderFront(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(300))
        let host = controller.view
        host.layoutSubtreeIfNeeded()

        let controls = segmentedControls(in: host)
        let context = "\(language.rawValue) \(screen.rawValue)"
        var failures: [String] = []
        if controls.isEmpty { failures.append("\(context): no segmented control mounted") }
        if screen == .collection, controls.count < 2 {
            failures.append("\(context): the Pokédex / catch-log picker is not mounted")
        }
        for (index, control) in controls.enumerated() {
            let frame = control.convert(control.bounds, to: host)
            let name = "\(context) picker \(index) [\(labels(of: control))] frame=\(NSStringFromRect(frame))"
            // The control must be readable in full, not just inside the popover.
            if #available(macOS 26, *), control.intrinsicContentSize.width > frame.width + 0.5 {
                failures.append("\(name): intrinsic width \(control.intrinsicContentSize.width) exceeds its frame")
            }
            if frame.minX < -0.5 || frame.maxX > PopoverMetrics.width + 0.5 {
                failures.append("\(name): extends past the \(PopoverMetrics.width)pt popover")
            }
        }
        // The tab bar and the Pokédex / catch-log switch are the column's full-width pickers.
        if screen == .home || screen == .collection {
            for control in controls.prefix(screen == .home ? 1 : 2) {
                let frame = control.convert(control.bounds, to: host)
                let name = "\(context) [\(labels(of: control))] frame=\(NSStringFromRect(frame))"
                if #available(macOS 26, *), control.intrinsicContentSize.width > PopoverMetrics.contentWidth + 0.5 {
                    failures.append("\(name): intrinsic width \(control.intrinsicContentSize.width) exceeds "
                        + "the \(PopoverMetrics.contentWidth)pt column, which widens and shifts every row")
                }
                if abs(frame.minX - PopoverMetrics.padding) > 0.5
                    || abs(frame.width - PopoverMetrics.contentWidth) > 0.5 {
                    failures.append("\(name): must span the \(PopoverMetrics.contentWidth)pt column "
                        + "from x=\(PopoverMetrics.padding)")
                }
            }
        }
        return failures
    }

    private func segmentedControls(in view: NSView) -> [NSSegmentedControl] {
        var found: [NSSegmentedControl] = []
        func walk(_ view: NSView) {
            if let control = view as? NSSegmentedControl { found.append(control); return }
            view.subviews.forEach(walk)
        }
        walk(view)
        // Top to bottom in the flipped SwiftUI host, so the tab bar comes first.
        return found.sorted { $0.convert($0.bounds, to: view).minY < $1.convert($1.bounds, to: view).minY }
    }

    private func labels(of control: NSSegmentedControl) -> String {
        (0..<control.segmentCount).map { control.label(forSegment: $0) ?? "" }.joined(separator: "|")
    }
}
