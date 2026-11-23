import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

/// The whole Settings screen in one tall image, for the PR's before/after of the sound-effects toggle.
/// **Skipped unless `PTB_SETTINGS_RENDER_DIR` names a directory.** Hosted in an off-screen window and captured
/// with `cacheDisplay`, so the AppKit-backed toggles draw as they do in the app. Throwaway defaults and save file.
private final class KeyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class CelebrationSettingsRenderTests: XCTestCase {
    func testWriteSettingsScreen() async throws {
        guard let path = ProcessInfo.processInfo.environment["PTB_SETTINGS_RENDER_DIR"], !path.isEmpty else {
            throw XCTSkip("PTB_SETTINGS_RENDER_DIR not set — render only when asked")
        }
        let suite = "CelebrationSettingsRender-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(suite).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let usage = UsageStore(providers: [], autoRefresh: false, defaults: defaults)
        let companion = CompanionStore(fileURL: file, defaults: defaults)
        companion.setLanguage(.en)
        let height: CGFloat = 2600
        let host = NSHostingView(rootView: SettingsView(onClose: {}, onChooseRepresentative: {}, startExpanded: false)
            .environment(usage).environment(companion).environment(UpdateChecker())
            .frame(width: PopoverMetrics.width, height: height)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, .light))
        let window = KeyWindow(contentRect: NSRect(x: -10000, y: -10000, width: PopoverMetrics.width, height: height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        // Key window: an inactive window draws every switch grey, as if it were off.
        let previousKeyWindow = NSApp.keyWindow
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil); previousKeyWindow?.makeKey() }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(600))
        host.layoutSubtreeIfNeeded()
        // Settings scrolls inside a fixed-height area: capture one page per scroll step (settings-0.png, …).
        let scroll = try XCTUnwrap(descendants(of: host).compactMap { $0 as? NSScrollView }.first)
        let document = try XCTUnwrap(scroll.documentView)
        let maximum = max(0, document.bounds.height - scroll.contentView.bounds.height)
        for (page, offset) in stride(from: 0.0, through: maximum + 299, by: 300).enumerated() {
            scroll.contentView.scroll(to: NSPoint(x: 0, y: min(offset, maximum)))
            scroll.reflectScrolledClipView(scroll.contentView)
            try await Task.sleep(for: .milliseconds(150))
            host.layoutSubtreeIfNeeded()
            let rect = scroll.convert(scroll.bounds, to: host)
            let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: rect))
            host.cacheDisplay(in: rect, to: rep)
            let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: path).appendingPathComponent("settings-\(page).png"))
        }
    }

    /// **Illustration / mockup, not a capture of Notification Center:** a notification-like card with the
    /// real localized strings, before (the hatch line names the hatchling) and after (the teaser).
    func testWriteNotificationIllustration() throws {
        guard let path = ProcessInfo.processInfo.environment["PTB_SETTINGS_RENDER_DIR"], !path.isEmpty else {
            throw XCTSkip("PTB_SETTINGS_RENDER_DIR not set — render only when asked")
        }
        let l = L(.en)
        func card(_ title: String, _ body: String) -> some View {
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 7).fill(Color.orange.opacity(0.85)).frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text("PokeTokenBar").font(.system(size: 11)).foregroundStyle(.secondary)
                    Text(title).font(.system(size: 13, weight: .semibold))
                    Text(body).font(.system(size: 13))
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(width: 330)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.96)))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.black.opacity(0.08)))
            .padding(12)
            .background(Color(white: 0.86))
            .environment(\.colorScheme, .light)
        }
        for (name, view) in [("notification-before", AnyView(card(l.notifHatchTitle, l.notifHatchBody("Dratini")))),
                             ("notification-after", AnyView(card(l.notifHatchTeaserTitle, l.notifHatchTeaserBody)))] {
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.cgImage)
            let png = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: path).appendingPathComponent("\(name).png"))
        }
    }

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap(descendants(of:))
    }
}
