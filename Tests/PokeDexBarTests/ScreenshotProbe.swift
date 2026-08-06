import AppKit
import SwiftUI
import XCTest
@testable import PokeDexBar

@MainActor
final class ScreenshotProbeTests: XCTestCase {
    private func scrollViews(_ view: NSView) -> [NSScrollView] {
        (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap(scrollViews)
    }

    private func inspect(_ label: String, _ host: NSView) {
        guard let scroll = scrollViews(host).first else { return print("PROBE \(label): no scroll") }
        print("PROBE \(label) host=\(host.frame.size) clipInHost=\(scroll.convert(scroll.contentView.frame, to: host))")
        print("PROBE \(label) documentRect=\(scroll.contentView.documentRect) contentSize=\(scroll.contentSize)")
        print("PROBE \(label) knob=\(String(describing: scroll.verticalScroller?.knobProportion)) docViewFitting=\(String(describing: scroll.documentView?.fittingSize))")
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 100_000))
        scroll.reflectScrolledClipView(scroll.contentView)
        host.layoutSubtreeIfNeeded()
        print("PROBE \(label) afterHugeScroll visible=\(scroll.documentVisibleRect) documentRect=\(scroll.contentView.documentRect)")
    }

    private func capture(_ host: NSView, offsets: [CGFloat], label: String) throws {
        guard let scroll = scrollViews(host).first else { return }
        for o in offsets {
            scroll.contentView.scroll(to: NSPoint(x: 0, y: o))
            scroll.reflectScrolledClipView(scroll.contentView)
            host.layoutSubtreeIfNeeded()
            let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: rep)
            let out = FileManager.default.temporaryDirectory
                .appendingPathComponent("probe-\(label)-\(Int(o)).png")
            try rep.representation(using: .png, properties: [:])!.write(to: out)
            print("PROBE capture \(label) \(o) -> \(out.path)")
        }
    }

    func testProbe() throws {
        guard ProcessInfo.processInfo.environment["PTB_PROBE"] == "1" else { throw XCTSkip("probe") }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("probe-\(UUID().uuidString).json")
        let base = Date(timeIntervalSince1970: 1_767_225_600)
        let player = PlayerStore(fileURL: url, rng: SeededRNG(seed: 42), now: { base })
        player.setLanguage(.en)
        player.seedForTesting(wallet: 12_000_000_000, slots: 5, eggs: 2, at: base)
        let defaults = UserDefaults(suiteName: "probe-\(UUID().uuidString)")!
        let usage = UsageStore(providers: [], autoRefresh: false, defaults: defaults)
        let updater = UpdateChecker(currentVersion: "2.9.0")

        let settings = NSHostingView(rootView: SettingsView(onClose: { })
            .environment(usage).environment(player).environment(updater)
            .frame(width: PopoverMetrics.width))
        settings.appearance = NSAppearance(named: .darkAqua)
        settings.layoutSubtreeIfNeeded()
        settings.frame = CGRect(origin: .zero, size: settings.fittingSize)
        settings.layoutSubtreeIfNeeded()
        inspect("settings", settings)
        try capture(settings, offsets: [0, 389, 778, 1167, 1556, 50_000], label: "settings")

        let shop = NSHostingView(rootView: ShopTabView(store: player, provider: ProbeShopProvider())
            .padding(PopoverMetrics.padding)
            .frame(width: PopoverMetrics.width))
        shop.appearance = NSAppearance(named: .darkAqua)
        shop.layoutSubtreeIfNeeded()
        shop.frame = CGRect(origin: .zero, size: shop.fittingSize)
        shop.layoutSubtreeIfNeeded()
        inspect("shop", shop)
    }
}

private struct ProbeShopProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: 1, tree: EvoNode(speciesID: 1, children: []), rarity: .common, names: [:])
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}
