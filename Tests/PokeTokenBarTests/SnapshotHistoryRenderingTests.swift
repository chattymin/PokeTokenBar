import AppKit
import SwiftUI
import Vision
import XCTest
@testable import PokeTokenBar

private struct SnapshotHistoryOfflineProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

private final class SnapshotHistoryTestWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

/// Drives the production Settings disclosure, including rows outside the scroll viewport.
@MainActor
final class SnapshotHistoryRenderingTests: XCTestCase {
    private var window: NSWindow?
    private var previousKeyWindow: NSWindow?

    override func tearDown() async throws {
        window?.close()
        window = nil
        previousKeyWindow?.makeKey()
        previousKeyWindow = nil
    }

    func testTenSnapshotsStartCollapsedAndExpandAllRowsThenCollapseAndReopen() async throws {
        let (companion, usage) = try makeStores(snapshotCount: 10)
        let root = host(companion, usage)
        let document = try await settingsDocument(in: root)
        try capture(document, name: "snapshots-collapsed")
        try await waitForRows(0, in: document)
        try await assertCreationAvailable(in: document, label: companion.l.createSnapshotButton)
        let collapsedHeight = document.bounds.height

        try await toggleHistory(in: document, l: companion.l, expanded: false)
        try await waitForRows(10, in: document)
        XCTAssertGreaterThan(document.bounds.height, collapsedHeight + 200)
        XCTAssertEqual(companion.availableSnapshots.count, 10)
        try capture(document, name: "snapshots-expanded")
        try await assertCreationAvailable(in: document, label: companion.l.createSnapshotButton)

        try await toggleHistory(in: document, l: companion.l, expanded: true)
        try await waitForRows(0, in: document)
        XCTAssertEqual(document.bounds.height, collapsedHeight, accuracy: 2)
        try capture(document, name: "snapshots-collapsed-again")

        // Reopening Settings starts a new visit, even after leaving its history expanded.
        try await toggleHistory(in: document, l: companion.l, expanded: false)
        try await waitForRows(10, in: document)
        window?.close()
        let reopened = host(companion, usage)
        let reopenedDocument = try await settingsDocument(in: reopened)
        try await waitForRows(0, in: reopenedDocument)
        try await assertCreationAvailable(in: reopenedDocument, label: companion.l.createSnapshotButton)
        XCTAssertEqual(companion.availableSnapshots.count, 10)
        try capture(reopenedDocument, name: "snapshots-reopened")
    }

    func testEmptyHistoryIsDisclosedAndManualCreationRemainsAvailable() async throws {
        let (companion, usage) = try makeStores(snapshotCount: 0)
        let document = try await settingsDocument(in: host(companion, usage))
        try await assertCreationAvailable(in: document, label: companion.l.createSnapshotButton)
        XCTAssertFalse(try words(in: document).contains { $0.reads(companion.l.noSnapshotsYet) })

        try await toggleHistory(in: document, l: companion.l, expanded: false)
        try await waitForText(companion.l.noSnapshotsYet, in: document)
        try await waitForRows(0, in: document)
        try await assertCreationAvailable(in: document, label: companion.l.createSnapshotButton)
        try capture(document, name: "snapshots-empty-expanded")
    }

    private func makeStores(snapshotCount: Int) throws -> (CompanionStore, UsageStore) {
        let suite = "SnapshotHistoryRendering-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let file = directory.appendingPathComponent("companion-state.json")
        let now = Date(timeIntervalSince1970: 1_700_100_000)
        var state = CompanionState()
        state.language = .en
        state.installBaselineSet = true
        state.active = MonState(baseID: 1, pathIDs: [1], plannedPathIDs: [1], stageIndex: 0,
                                usedAtStage: 0, rarity: .common, totalForms: 1)
        for index in 0..<snapshotCount {
            state.usedSinceInstall = 10_000 + index * 1_000
            try SaveSnapshotManager.createSnapshot(state: state, for: file,
                date: now.addingTimeInterval(Double(index - snapshotCount) * 3600),
                appVersion: "sample", deviceName: "Sample data")
        }
        state.usedSinceInstall = 99_000
        try JSONEncoder().encode(state).write(to: file)

        // Sample screenshots use a generated geometric icon, never downloaded Pokémon artwork.
        let image = NSImage(size: NSSize(width: 28, height: 28), flipped: false) { rect in
            NSColor.systemBlue.setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: 5, dy: 5), xRadius: 4, yRadius: 4).fill()
            return true
        }
        let key = SpriteLoader.cacheDir.appendingPathComponent("1-s.png").path as NSString
        let previous = SpriteLoader.imageCache.object(forKey: key)
        SpriteLoader.imageCache.setObject(image, forKey: key)
        addTeardownBlock { @MainActor in
            if let previous { SpriteLoader.imageCache.setObject(previous, forKey: key) }
            else { SpriteLoader.imageCache.removeObject(forKey: key) }
        }
        return (CompanionStore(provider: SnapshotHistoryOfflineProvider(), clock: { now },
                               fileURL: file, defaults: defaults),
                UsageStore(providers: [], autoRefresh: false, defaults: defaults))
    }

    private func host(_ companion: CompanionStore, _ usage: UsageStore) -> NSView {
        _ = NSApplication.shared
        if previousKeyWindow == nil { previousKeyWindow = NSApp.keyWindow }
        let host = NSHostingView(rootView: SettingsView(onClose: {}, onChooseRepresentative: {})
            .environment(companion).environment(usage).environment(UpdateChecker())
            .environment(\.colorScheme, .light)
            .frame(width: PopoverMetrics.width))
        host.frame = NSRect(x: 0, y: 0, width: PopoverMetrics.width, height: 460)
        let window = SnapshotHistoryTestWindow(
            contentRect: NSRect(x: -10000, y: -10000, width: PopoverMetrics.width, height: 460),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        self.window = window
        return host
    }

    private func settingsDocument(in root: NSView) async throws -> NSView {
        try await Task.sleep(for: .milliseconds(300))
        root.layoutSubtreeIfNeeded()
        let scroll = try XCTUnwrap(descendants(root).compactMap { $0 as? NSScrollView }.first)
        return try XCTUnwrap(scroll.documentView)
    }

    private func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }

    private struct Word {
        let candidates: [String]
        static func normalized(_ text: String) -> String {
            text.lowercased().filter { $0.isLetter || $0.isNumber }
        }
        func reads(_ wanted: String, exactly: Bool = false) -> Bool {
            let normalized = Self.normalized(wanted)
            return candidates.contains {
                let text = Self.normalized($0)
                return exactly ? text == normalized : text.contains(normalized)
            }
        }
    }

    private func bitmap(of view: NSView) throws -> NSBitmapImageRep {
        view.window?.contentView?.layoutSubtreeIfNeeded()
        view.layoutSubtreeIfNeeded()
        // Render native text at 2x even when the runner's screen backing is only 1x.
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int((view.bounds.width * 2).rounded(.up)),
            pixelsHigh: Int((view.bounds.height * 2).rounded(.up)), bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.size = view.bounds.size
        view.cacheDisplay(in: view.bounds, to: bitmap)
        XCTAssertGreaterThanOrEqual(CGFloat(bitmap.pixelsWide) / view.bounds.width, 2)
        XCTAssertGreaterThanOrEqual(CGFloat(bitmap.pixelsHigh) / view.bounds.height, 2)
        return bitmap
    }

    private func words(in view: NSView) throws -> [Word] {
        let image = try XCTUnwrap(bitmap(of: view).cgImage)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        try VNImageRequestHandler(cgImage: image).perform([request])
        return request.results?.compactMap {
            let candidates = $0.topCandidates(10).map(\.string)
            return candidates.isEmpty ? nil : Word(candidates: candidates)
        } ?? []
    }

    @discardableResult
    private func waitForText(_ text: String, in view: NSView) async throws -> Word {
        let deadline = ContinuousClock.now + .seconds(5)
        repeat {
            if let match = try words(in: view).first(where: { $0.reads(text) }) { return match }
            try await Task.sleep(for: .milliseconds(100))
        } while ContinuousClock.now < deadline
        XCTFail("Missing rendered text: \(text)")
        throw URLError(.cannotParseResponse)
    }

    private func waitForRows(_ count: Int, in document: NSView) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        var actual = -1
        repeat {
            document.window?.contentView?.layoutSubtreeIfNeeded()
            actual = try words(in: document).filter { $0.reads("Restore", exactly: true) }.count
            if actual == count {
                try await Task.sleep(for: .milliseconds(300))
                document.window?.contentView?.layoutSubtreeIfNeeded()
                return
            }
            try await Task.sleep(for: .milliseconds(100))
        } while ContinuousClock.now < deadline
        XCTFail("Expected \(count) restore rows, rendered \(actual)")
    }

    private func assertCreationAvailable(in document: NSView, label: String) async throws {
        _ = try await waitForText(label, in: document)
    }

    private func toggleHistory(in document: NSView, l: L, expanded: Bool) async throws {
        let root = try XCTUnwrap(document.window?.contentView)
        let deadline = ContinuousClock.now + .seconds(5)
        var buttons = [NSButton]()
        repeat {
            root.layoutSubtreeIfNeeded()
            buttons = descendants(root).compactMap { $0 as? NSButton }
            if let button = buttons.first(where: { $0.accessibilityIdentifier() == "snapshotHistory" }) {
                XCTAssertEqual(button.title, l.snapshotsSectionTitle)
                XCTAssertEqual(button.accessibilityLabel(), l.snapshotsSectionTitle)
                XCTAssertEqual(button.accessibilityValue() as? String, l.snapshotHistoryState(expanded: expanded))
                XCTAssertTrue(button.isEnabled, "Snapshot history must remain actionable")
                button.scrollToVisible(button.bounds)
                button.performClick(nil)
                try await Task.sleep(for: .milliseconds(200))
                return
            }
            try await Task.sleep(for: .milliseconds(100))
        } while ContinuousClock.now < deadline
        let diagnostic = buttons.map {
            "title=\($0.title), label=\(String(describing: $0.accessibilityLabel())), identifier=\(String(describing: $0.accessibilityIdentifier()))"
        }.joined(separator: "\n")
        XCTFail("Missing native snapshot history button: \(l.snapshotsSectionTitle)\n\(diagnostic)")
        throw URLError(.cannotParseResponse)
    }

    private func capture(_ view: NSView, name: String) throws {
        guard let path = ProcessInfo.processInfo.environment["PTB_SNAPSHOT_SCREENSHOT_DIR"] else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = try XCTUnwrap(bitmap(of: view).cgImage)
        let context = try XCTUnwrap(CGContext(data: nil, width: source.width, height: source.height,
            bitsPerComponent: 8, bytesPerRow: source.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        let rect = CGRect(x: 0, y: 0, width: source.width, height: source.height)
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            context.setFillColor(NSColor.windowBackgroundColor.cgColor)
            context.fill(rect)
        }
        context.draw(source, in: rect)
        let opaque = NSBitmapImageRep(cgImage: try XCTUnwrap(context.makeImage()))
        let data = try XCTUnwrap(opaque.representation(using: .png, properties: [:]))
        try data.write(to: directory.appendingPathComponent("\(name).png"))
    }
}
