import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

/// Count image-size reads during SpriteView layout with a lock-protected counter.
private final class LayoutCountingImage: NSImage, @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var reads = 0
    var sizeReadCount: Int { lock.withLock { reads } }

    override var size: NSSize {
        get {
            lock.withLock { reads += 1 }
            return super.size
        }
        set { super.size = newValue }
    }
}

@MainActor
final class CatchLogRenderingTests: XCTestCase {
    /// Sorting 1,000 entries does not exercise the SwiftUI list. Render the production screen
    /// repeatedly with a large log: an eager VStack must fail this work-count bound.
    func testOpeningAndReopeningLargeLogOnlyLaysOutViewportSprites() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("catch-log-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        var state = CompanionState()
        state.language = .en
        state.dex = (0..<300).map { i in
            DexEntry(baseID: 25, finalID: 25, chainOrder: [25], rarity: .common,
                     caughtAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(i)),
                     names: [25: ["en": "Fixture \(i)"]])
        }
        try JSONEncoder().encode(state).write(to: file)
        let store = CompanionStore(fileURL: file)
        let image = LayoutCountingImage(size: NSSize(width: 96, height: 96))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 96, height: 96).fill()
        image.unlockFocus()
        let key = SpriteLoader.cacheDir.appendingPathComponent("25-s.png").path as NSString
        let previous = SpriteLoader.imageCache.object(forKey: key)
        SpriteLoader.imageCache.setObject(image, forKey: key)
        defer {
            if let previous { SpriteLoader.imageCache.setObject(previous, forKey: key) }
            else { SpriteLoader.imageCache.removeObject(forKey: key) }
        }

        for attempt in 1...3 {
            autoreleasepool {
                let navigation = PopoverNavigation()
                navigation.collectionSection = .log
                let before = image.sizeReadCount
                let host = NSHostingController(rootView: CollectionView(store: store, navigation: navigation)
                    .frame(width: PopoverMetrics.contentWidth)
                    .environment(\.locale, store.language.displayLocale))
                let size = host.sizeThatFits(in: CGSize(width: PopoverMetrics.contentWidth, height: 520))
                host.view.setFrameSize(NSSize(width: PopoverMetrics.contentWidth, height: 520))
                host.view.layoutSubtreeIfNeeded()
                let reads = image.sizeReadCount - before

                XCTAssertEqual(size.height, 520, accuracy: 0.5, "reopening must preserve the fixed popover height")
                XCTAssertGreaterThan(reads, 0, "the test must actually lay out sprites")
                XCTAssertLessThan(reads, 100,
                                  "attempt \(attempt): \(reads) sprite layouts — opening must not process all 300 entries")
            }
        }
    }
}
