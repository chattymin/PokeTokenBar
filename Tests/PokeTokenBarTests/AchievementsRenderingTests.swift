import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

private struct AchievementsStubProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: baseSpeciesID, tree: EvoNode(speciesID: baseSpeciesID, children: []), rarity: .legendary,
                names: [baseSpeciesID: ["en": "P\(baseSpeciesID)"]])
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

/// The Achievements tab gets the same 520 pt as the other tabs. A fixed list height under the header, the claim
/// banner and the category picker made the stack taller than that frame: SwiftUI centered it, so the header slid
/// under the tab bar and the list ran under the footer.
@MainActor
final class AchievementsRenderingTests: XCTestCase {
    func testPickerAndListStayInsideTheTabFrameWithTheClaimBanner() async throws {
        let suite = "AchievementsLayout-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(suite).json")
        defer { try? FileManager.default.removeItem(at: file) }
        var state = CompanionState()
        state.language = .en
        state.installBaselineSet = true
        // Articuno, Zapdos, Moltres: the Silver Wing is ready, so the banner (the tallest header) is shown.
        state.dex = [144, 145, 146].map {
            DexEntry(baseID: $0, finalID: $0, chainOrder: [$0], rarity: .legendary,
                     caughtAt: Date(timeIntervalSince1970: 1_790_000_000))
        }
        try JSONEncoder().encode(state).write(to: file)
        let store = CompanionStore(provider: AchievementsStubProvider(), fileURL: file, defaults: defaults)
        XCTAssertGreaterThan(store.unclaimedAchievementsCount, 0)

        let host = NSHostingView(rootView: AchievementsView(store: store, nav: PopoverNavigation())
            .frame(width: PopoverMetrics.contentWidth))
        let size = NSSize(width: PopoverMetrics.contentWidth, height: 520)
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -10000, y: -10000), size: size),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(300))
        host.layoutSubtreeIfNeeded()

        let picker = try XCTUnwrap(descendants(of: host, NSSegmentedControl.self).first)
        let list = try XCTUnwrap(descendants(of: host, NSScrollView.self).first)
        // Vertical only: the segmented control draws its bezel 2 pt past its SwiftUI frame on each side.
        for (name, view) in [("category picker", picker as NSView), ("list", list)] {
            let frame = host.convert(view.bounds, from: view)
            XCTAssertGreaterThanOrEqual(frame.minY, -0.5, "\(name) \(frame) leaves the tab frame \(host.bounds)")
            XCTAssertLessThanOrEqual(frame.maxY, host.bounds.maxY + 0.5,
                                     "\(name) \(frame) leaves the tab frame \(host.bounds)")
        }
    }

    /// Three segments with their counts used to be wider than the popover: SwiftUI centered the wider stack,
    /// so the whole tab slid off both edges. Checked in every language, with the widest counts (all claimed).
    func testCategoryPickerFitsTheTabWidthInEveryLanguage() async throws {
        for language in AppLanguage.allCases {
            let suite = "AchievementsWidth-\(UUID())"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(suite).json")
            defer { try? FileManager.default.removeItem(at: file) }
            var state = CompanionState()
            state.language = language
            state.installBaselineSet = true
            state.claimedAchievements = Set(CompanionStore.achievementItems.map(\.rawValue))
            try JSONEncoder().encode(state).write(to: file)
            let store = CompanionStore(provider: AchievementsStubProvider(), fileURL: file, defaults: defaults)

            let host = NSHostingView(rootView: AchievementsView(store: store, nav: PopoverNavigation())
                .frame(width: PopoverMetrics.contentWidth))
            let size = NSSize(width: PopoverMetrics.contentWidth, height: 520)
            host.frame = NSRect(origin: .zero, size: size)
            let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -10000, y: -10000), size: size),
                                  styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            window.orderFront(nil)
            defer { window.close() }
            try await Task.sleep(for: .milliseconds(100))
            host.layoutSubtreeIfNeeded()

            let picker = try XCTUnwrap(descendants(of: host, NSSegmentedControl.self).first)
            let frame = host.convert(picker.bounds, from: picker)
            // The bezel is drawn 2 pt past the SwiftUI frame on each side.
            XCTAssertGreaterThanOrEqual(frame.minX, -2.5, "\(language): picker \(frame) leaves \(host.bounds)")
            XCTAssertLessThanOrEqual(frame.maxX, host.bounds.maxX + 2.5, "\(language): picker \(frame) leaves \(host.bounds)")
        }
    }

    /// The Achievements tab made the popover's segmented tab bar five labels wide. With a two-digit count it was
    /// wider than the popover in German, and Russian overflowed even without one.
    func testTabBarFitsThePopoverInEveryLanguage() async throws {
        for language in AppLanguage.allCases {
            var tab = PopoverTab.home
            let picker = PopoverTabPicker(tab: Binding(get: { tab }, set: { tab = $0 }), l: L(language),
                                          unclaimedAchievements: 41)
            let host = NSHostingView(rootView: picker.frame(width: PopoverMetrics.contentWidth))
            let size = NSSize(width: PopoverMetrics.contentWidth, height: 40)
            host.frame = NSRect(origin: .zero, size: size)
            let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -10000, y: -10000), size: size),
                                  styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            window.orderFront(nil)
            defer { window.close() }
            try await Task.sleep(for: .milliseconds(50))
            host.layoutSubtreeIfNeeded()

            let control = try XCTUnwrap(descendants(of: host, NSSegmentedControl.self).first)
            let frame = host.convert(control.bounds, from: control)
            // The bezel is drawn 2 pt past the SwiftUI frame on each side.
            XCTAssertGreaterThanOrEqual(frame.minX, -2.5, "\(language): tab bar \(frame) leaves \(host.bounds)")
            XCTAssertLessThanOrEqual(frame.maxX, host.bounds.maxX + 2.5, "\(language): tab bar \(frame) leaves \(host.bounds)")
        }
    }

    private func descendants<T: NSView>(of view: NSView, _ type: T.Type) -> [T] {
        view.subviews.compactMap { $0 as? T } + view.subviews.flatMap { descendants(of: $0, type) }
    }
}
