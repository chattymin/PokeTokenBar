import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

/// Before/after renders for the sulk state. **Skipped unless `PTB_SULK_RENDER_DIR` names a directory:**
///
///     PTB_SULK_RENDER_DIR=/some/dir swift test --filter SulkRenderTests
///
/// The sprites come from a throwaway `SpriteStore` directory, never the real cache. Pikachu's front and
/// back sprites are downloaded into it (the runner has network); if a download fails, a labelled
/// placeholder PNG stands in so the layout is still rendered, and the test log says which one.
@MainActor
final class SulkRenderTests: XCTestCase {
    private static let speciesID = 25
    private var windows: [NSWindow] = []

    override func tearDown() async throws {
        windows.forEach { $0.close() }
        windows = []
    }

    private func outputDirectory() throws -> URL {
        guard let path = ProcessInfo.processInfo.environment["PTB_SULK_RENDER_DIR"], !path.isEmpty else {
            throw XCTSkip("PTB_SULK_RENDER_DIR not set — render only when asked")
        }
        return URL(fileURLWithPath: path)
    }

    // MARK: Sprites

    private func placeholderPNG(label: String, color: NSColor) throws -> Data {
        let side = 96
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: rep))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        color.setFill()
        NSBezierPath(roundedRect: NSRect(x: 16, y: 16, width: 64, height: 64), xRadius: 12, yRadius: 12).fill()
        (label as NSString).draw(at: NSPoint(x: 26, y: 40), withAttributes: [
            .font: NSFont.boldSystemFont(ofSize: 14), .foregroundColor: NSColor.white])
        NSGraphicsContext.restoreGraphicsState()
        return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    }

    /// A private sprite directory holding Pikachu front and back; reports which came from the network.
    private func spriteStore() async throws -> SpriteStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("sulk-render-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let store = SpriteStore(directory: directory)
        for back in [false, true] {
            let id = Self.speciesID
            let gif = await store.data(speciesID: id, animated: true, back: back)
            let png = await store.data(speciesID: id, animated: false, back: back)
            print("sulk-render sprite \(back ? "back" : "front"): gif=\(gif != nil) png=\(png != nil)")
            if png == nil {
                let key = SpriteStore.cacheKey(speciesID: id, animated: false, shiny: false, back: back)
                let placeholder = try placeholderPNG(label: back ? "BACK" : "FRONT",
                                                     color: back ? .systemOrange : .systemBlue)
                try placeholder.write(to: directory.appendingPathComponent(key + ".png"))
                print("sulk-render sprite \(back ? "back" : "front"): PLACEHOLDER (download failed)")
            }
        }
        return store
    }

    // MARK: Stores

    private final class ClockBox: @unchecked Sendable {
        nonisolated(unsafe) var now = Date(timeIntervalSince1970: 1_700_000_000)
    }

    /// An active Pikachu whose state is driven through `update`, exactly as the app does it.
    private func makeCompanion(language: AppLanguage, sulking: Bool) async throws -> CompanionStore {
        let clock = ClockBox()
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("sulk-render-\(UUID()).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: file) }
        let suite = "SulkRender-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let names = [Self.speciesID: ["en": "Pikachu", "ko": "피카츄"]]
        let line = EvoLine(baseID: Self.speciesID, tree: EvoNode(speciesID: Self.speciesID, children: []),
                           rarity: .common, names: names)
        let store = CompanionStore(provider: StubProvider(value: line), clock: { clock.now },
                                   fileURL: file, rng: SeededRNG(seed: 5), defaults: defaults)
        store.setLanguage(language)
        await store.hatch(baseID: Self.speciesID)
        clock.now = clock.now.addingTimeInterval(60)   // let the hatch event window expire
        store.update(todayTokensByProvider: ["test": 0], todayDate: "d", monthTotal: 0, burnTier: .idle,
                     limitWarning: false, hasUsageData: true,
                     timeSinceLastUsage: sulking ? 3 * 86_400 : 3_600)
        XCTAssertEqual(store.displayState, sulking ? .sulk : .sleep)
        return store
    }

    // MARK: Hosting

    private func mount<V: View>(_ view: V, width: CGFloat, height: CGFloat) -> NSHostingView<AnyView> {
        let host = NSHostingView(rootView: AnyView(
            view.frame(width: width, height: height).background(Color.white).environment(\.colorScheme, .light)))
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: width, height: height),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        window.orderFront(nil)
        windows.append(window)
        return host
    }

    /// Lets the sprite `.task` finish (cached file → GIF/PNG decode), then snapshots at 2x.
    private func snapshot(_ host: NSView) async throws -> Data {
        for _ in 0..<40 {
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(50))
        }
        let bounds = host.bounds
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(bounds.width * 2), pixelsHigh: Int(bounds.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = bounds.size
        host.cacheDisplay(in: bounds, to: rep)
        return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    }

    // MARK: Renders

    func testRenderPopoverHomeCardSleepVersusSulk() async throws {
        let directory = try outputDirectory()
        let sprites = try await spriteStore()
        for language in [AppLanguage.ko, .en] {
            var images: [Bool: Data] = [:]
            for sulking in [false, true] {
                let store = try await makeCompanion(language: language, sulking: sulking)
                let host = mount(CompanionHeader(store: store, spriteStore: sprites), width: PopoverMetrics.contentWidth,
                                 height: 150)
                let png = try await snapshot(host)
                images[sulking] = png
                let name = "popover-home-\(sulking ? "sulk-back" : "sleep-front")-\(language.rawValue).png"
                try png.write(to: directory.appendingPathComponent(name))
                print("wrote \(name) (\(png.count) bytes)")
            }
            XCTAssertNotEqual(images[false], images[true], "\(language): sulk must change the rendered pixels")
        }
    }

    func testRenderFloatingPetAndHoverTextNormalVersusSulk() async throws {
        let directory = try outputDirectory()
        let sprites = try await spriteStore()
        for language in [AppLanguage.ko, .en] {
            var images: [Bool: Data] = [:]
            for sulking in [false, true] {
                let companion = try await makeCompanion(language: language, sulking: sulking)
                let suite = "SulkRenderUsage-\(UUID())"
                let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
                addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
                let usage = UsageStore(providers: [], autoRefresh: false, defaults: defaults)
                // The same text the hover callout shows; the chrome here only approximates the NSPanel's.
                let hover = FloatingPetView.hoverTooltip(
                    todayTokens: 0, limitUtilization: nil, mode: usage.limitDisplayMode,
                    l: L(language), sulkIdle: companion.sulkIdle)
                let view = VStack(spacing: 8) {
                    Text(hover).font(.system(size: 11))
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .windowBackgroundColor)))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
                    FloatingPetView(spriteStore: sprites)
                        .environment(usage).environment(companion)
                        .frame(width: 96, height: 96)
                }
                let host = mount(view, width: 240, height: 170)
                let png = try await snapshot(host)
                images[sulking] = png
                let name = "floating-pet-\(sulking ? "sulk-back-with-hover" : "normal-with-hover")-\(language.rawValue).png"
                try png.write(to: directory.appendingPathComponent(name))
                print("wrote \(name) (\(png.count) bytes) hover=\(hover)")
            }
            XCTAssertNotEqual(images[false], images[true], "\(language): sulk must change the rendered pixels")
        }
    }

    // MARK: Menu illustrations

    /// One menu row: checkmark column, title, optional shortcut. Greyed when it is information only.
    private struct MenuRow: Identifiable {
        let id = UUID()
        let title: String
        var checked = false
        var shortcut = ""
        var enabled = true
        var isSeparator = false
    }

    private func menuIllustration(_ rows: [MenuRow], width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(rows) { row in
                if row.isSeparator {
                    Divider().padding(.vertical, 4)
                } else {
                    HStack(spacing: 0) {
                        Text(row.checked ? "✓" : "").frame(width: 20)
                        Text(row.title)
                        Spacer(minLength: 16)
                        Text(row.shortcut).foregroundColor(.secondary)
                    }
                    .font(.system(size: 13))
                    .foregroundColor(row.enabled ? .primary : .secondary)
                    .frame(height: 22)
                    .padding(.horizontal, 6)
                }
            }
        }
        .padding(6)
        .frame(width: width)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .windowBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
        .padding(12)
    }

    private func writeIllustration<V: View>(_ view: V, name: String, size: CGSize, to directory: URL) async throws {
        let host = mount(view, width: size.width, height: size.height)
        let png = try await snapshot(host)
        try png.write(to: directory.appendingPathComponent(name))
        print("wrote \(name) (\(png.count) bytes)")
    }

    /// Illustrations built from the real localized titles; the menus themselves are native NSMenus.
    func testRenderMenuIllustrations() async throws {
        let directory = try outputDirectory()
        let l = L(.en)
        for checked in [false, true] {
            let rows = [MenuRow(title: l.floatingPetMenuOpen), MenuRow(title: l.floatingPetMenuHide),
                        MenuRow(title: l.backViewLabel, checked: checked)]
            try await writeIllustration(menuIllustration(rows, width: 220),
                                        name: "illustration-pet-menu-\(checked ? "checked" : "unchecked")-en.png",
                                        size: CGSize(width: 244, height: 120), to: directory)
        }
        let entries = StatusItemMenu.entries(l: l, todayTokens: 19_400_000, todayCost: nil,
                                             floatingPetEnabled: false, alwaysFacesBack: true)
        let rows = entries.map { entry -> MenuRow in
            guard let entry else { return MenuRow(title: "", isSeparator: true) }
            return MenuRow(title: entry.title, checked: entry.isChecked,
                           shortcut: entry.keyEquivalent.isEmpty ? "" : "⌘" + entry.keyEquivalent.uppercased(),
                           enabled: entry.action != nil)
        }
        try await writeIllustration(menuIllustration(rows, width: 280),
                                    name: "illustration-status-menu-checked-en.png",
                                    size: CGSize(width: 304, height: 240), to: directory)
    }

    // MARK: Settings section

    /// The Floating Pet section alone, at the width it has inside Settings (the page's 16 pt padding on
    /// both sides) and as tall as its rows need. No cropping, so before and after share one recipe.
    private func renderFloatingPetSection(backView: Bool, name: String, to directory: URL) async throws {
        let suite = "SulkRenderSettings-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(suite).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: file) }
        let usage = UsageStore(providers: [], autoRefresh: false, defaults: defaults)
        usage.floatingPetEnabled = true
        usage.alwaysFacesBack = backView
        let companion = CompanionStore(fileURL: file, defaults: defaults)
        companion.setLanguage(.en)
        let content = FloatingPetSettingsSection()
            .environment(usage).environment(companion)
            .padding(16)
            .frame(width: PopoverMetrics.width)
            .fixedSize(horizontal: false, vertical: true)
        let height = ceil(NSHostingView(rootView: content).fittingSize.height)
        let png = try await snapshot(mount(content, width: PopoverMetrics.width, height: height))
        try png.write(to: directory.appendingPathComponent(name))
        print("wrote \(name) (\(png.count) bytes, \(Int(PopoverMetrics.width))x\(Int(height)) pt)")
    }

    func testRenderSettingsFloatingPetSection() async throws {
        let directory = try outputDirectory()
        try await renderFloatingPetSection(backView: false, name: "settings-floating-pet-after-en.png", to: directory)
        try await renderFloatingPetSection(backView: true, name: "settings-floating-pet-after-back-on-en.png",
                                           to: directory)
    }
}
