import AppKit
import SwiftUI
import Vision
import XCTest
@testable import PokeTokenBar

private struct OfflineProvider: PokeProviding, PokemonDetailProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
    func pokemonDetails(speciesID: Int) async throws -> PokemonDetails { throw URLError(.notConnectedToInternet) }
}

/// The detail page replaces the grid/log, so Back rebuilds them. These drive the real `CollectionView`
/// through that round trip and read the result off the rendered pixels.
@MainActor
final class DexBackNavigationTests: XCTestCase {
    private var window: NSWindow?

    override func tearDown() async throws {
        window?.close()
        window = nil
    }

    /// 20 species = 2 grid pages: Mon1…Mon16, then Mon17…Mon20.
    private func makeStore() throws -> CompanionStore {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("dex-back-\(UUID()).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: file) }
        var state = CompanionState()
        state.language = .en
        state.dex = (1...20).map { id in
            DexEntry(id: "entry-\(id)", baseID: id, finalID: id, chainOrder: [id], rarity: .common,
                     caughtAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(id)),
                     names: [id: ["en": "Mon\(id)"]])
        }
        try JSONEncoder().encode(state).write(to: file)
        return CompanionStore(provider: OfflineProvider(), fileURL: file)
    }

    private func host(_ store: CompanionStore, _ navigation: PopoverNavigation) -> NSView {
        let host = NSHostingView(rootView: CollectionView(store: store, navigation: navigation)
            .frame(width: PopoverMetrics.contentWidth, height: 520)
            .background(Color.white)
            .environment(\.colorScheme, .light))
        host.frame = NSRect(x: 0, y: 0, width: PopoverMetrics.contentWidth, height: 520)
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: PopoverMetrics.contentWidth, height: 520),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        window.orderFront(nil)
        self.window = window
        return host
    }

    // MARK: Rendered text (the accessibility tree stays empty without an AX client)

    /// `candidates`: Vision's top readings. The pager's "2/2" still reads as "212", so tests check
    /// which species a page shows instead.
    private struct Word { let candidates: [String]; let box: CGRect }   // box: normalized, y-up

    private func words(in host: NSView) throws -> [Word] {
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        try VNImageRequestHandler(cgImage: XCTUnwrap(bitmap.cgImage)).perform([request])
        return request.results?.compactMap { observation in
            let candidates = observation.topCandidates(10).map(\.string)
            return candidates.isEmpty ? nil : Word(candidates: candidates, box: observation.boundingBox)
        } ?? []
    }

    /// Polls: SwiftUI renders a state change a run-loop turn or two later.
    @discardableResult
    private func waitForText(_ text: String, exactly: Bool = false, in host: NSView, footerOnly: Bool = false,
                             file: StaticString = #filePath, line: UInt = #line) async throws -> Word? {
        let deadline = ContinuousClock.now + .seconds(5)
        var seen: [Word] = []
        repeat {
            seen = try words(in: host).filter { !footerOnly || $0.box.midY < 0.05 }
            let wanted = text.replacingOccurrences(of: " ", with: "")
            let match = seen.first { word in
                word.candidates.contains {
                    let candidate = $0.replacingOccurrences(of: " ", with: "")
                    return exactly ? candidate == wanted : candidate.contains(wanted)
                }
            }
            if let match { return match }
            try await Task.sleep(for: .milliseconds(50))
        } while ContinuousClock.now < deadline
        XCTFail("\(text) not rendered. Seen: \(seen.map(\.candidates))", file: file, line: line)
        return nil
    }

    /// Clicks the control under a rendered label. Back is a borderless button that AppKit backs with an
    /// untitled `NSButton`; a synthetic mouse-down there blocks in its tracking loop waiting for a
    /// queued mouse-up, so that one is pressed directly. Plain SwiftUI buttons take the events.
    private func press(_ word: Word, in host: NSView) throws {
        let y = host.isFlipped ? 1 - word.box.midY : word.box.midY   // Vision boxes are y-up
        let point = NSPoint(x: word.box.midX * host.bounds.width, y: y * host.bounds.height)
        var view = host.hitTest(host.convert(point, to: host.superview))
        while let current = view, !(current is NSButton) { view = current.superview }
        if let button = view as? NSButton {
            button.performClick(nil)
            return
        }
        let window = try XCTUnwrap(host.window)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            window.sendEvent(try XCTUnwrap(NSEvent.mouseEvent(
                with: type, location: host.convert(point, to: nil), modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, clickCount: 1, pressure: 1)))
        }
    }

    /// Opens #18 (page 2) the way Home's sprite does, then presses the detail page's Back.
    private func openPageTwoSpeciesAndGoBack(_ store: CompanionStore, _ navigation: PopoverNavigation,
                                             _ host: NSView) async throws {
        let species = try XCTUnwrap(store.dexSpecies.first { $0.id == 18 })
        navigation.dexDetailCollectionID = species.collectionID
        let back = try await waitForText(store.l.back, in: host)
        try press(XCTUnwrap(back), in: host)
    }

    // MARK: Pokédex grid

    func testBackFromDetailReturnsToThePageOfThatSpecies() async throws {
        let store = try makeStore()
        let navigation = PopoverNavigation()
        navigation.tab = .collection
        let root = host(store, navigation)
        try await waitForText("Mon5", in: root)

        try await openPageTwoSpeciesAndGoBack(store, navigation, root)

        try await waitForText("Mon20", in: root)
        // The species stays selected, so the footer names it.
        try await waitForText("#18 Mon18", in: root, footerOnly: true)
    }

    func testReturnPageIsUsedOnlyOnce() async throws {
        let store = try makeStore()
        let navigation = PopoverNavigation()
        navigation.tab = .collection
        let root = host(store, navigation)
        try await openPageTwoSpeciesAndGoBack(store, navigation, root)
        try await waitForText("Mon20", in: root)

        navigation.showingCollectionLog = true
        try await Task.sleep(for: .milliseconds(100))
        navigation.showingCollectionLog = false

        try await waitForText("Mon5", in: root)
    }
}
