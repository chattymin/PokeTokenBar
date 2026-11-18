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

    /// 20 species = 2 grid pages: species 1…16, then 17…20.
    private func makeStore() throws -> CompanionStore {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("dex-back-\(UUID()).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: file) }
        var state = CompanionState()
        state.language = .en
        state.dex = (1...20).map { id in
            DexEntry(id: "entry-\(id)", baseID: id, finalID: id, chainOrder: [id], rarity: .common,
                     caughtAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(id)),
                     // A word avoids the ambiguous digit in Mon1, which Vision reads as Mont/Monl.
                     names: [id: ["en": id == 1 ? "Oldest" : "Mon\(id)"]])
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
    private struct Word {
        let candidates: [String]
        let box: CGRect   // normalized, y-up

        /// Spaces are ignored: Vision splits and joins words inconsistently. A vertical edge next to a word can come
        /// back as part of it: CI read Mon1 only as "Mon1|", so edge glyphs are trimmed before comparing. "Mon10|"
        /// still reads Mon10, never Mon1.
        func reads(_ text: String, exactly: Bool) -> Bool {
            let wanted = text.replacingOccurrences(of: " ", with: "")
            return candidates.contains {
                let candidate = $0.replacingOccurrences(of: " ", with: "").trimmingCharacters(in: Self.edgeGlyphs)
                return exactly ? candidate == wanted : candidate.contains(wanted)
            }
        }

        private static let edgeGlyphs = CharacterSet(charactersIn: "|/\\[]()")
    }

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
    private func waitForText(_ text: String, exactly: Bool = false, in host: NSView,
                             file: StaticString = #filePath, line: UInt = #line) async throws -> Word? {
        let deadline = ContinuousClock.now + .seconds(5)
        var seen: [Word] = []
        repeat {
            seen = try words(in: host)
            if let match = seen.first(where: { $0.reads(text, exactly: exactly) }) { return match }
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

    /// Clicks a SwiftUI link under a rendered label the way a mouse does: moved there first, since SwiftUI drops a
    /// press away from where it last saw the pointer, then down and up as distinct events.
    private var eventNumber = 0
    private func click(_ word: Word, in host: NSView) async throws {
        let y = host.isFlipped ? 1 - word.box.midY : word.box.midY   // Vision boxes are y-up
        let point = host.convert(NSPoint(x: word.box.midX * host.bounds.width, y: y * host.bounds.height), to: nil)
        let window = try XCTUnwrap(host.window)
        for type in [NSEvent.EventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
            try await Task.sleep(for: .milliseconds(40))
            eventNumber += 1
            window.sendEvent(try XCTUnwrap(NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: eventNumber, clickCount: 1,
                pressure: type == .leftMouseDown ? 1 : 0)))
        }
    }

    private func isRendered(_ text: String, exactly: Bool = false, in host: NSView) throws -> Bool {
        try words(in: host).contains { $0.reads(text, exactly: exactly) }
    }

    /// Presses the control labeled `text` until the screen changes: `opens` appears, or `text` goes
    /// away. Right after a transition the view tree can still hit-test the previous screen (seen on
    /// CI), so a press that lands there is retried.
    private func press(_ text: String, exactly: Bool = false, opens: String? = nil, in host: NSView,
                       file: StaticString = #filePath, line: UInt = #line) async throws {
        for _ in 0..<5 {
            let word = try await waitForText(text, exactly: exactly, in: host, file: file, line: line)
            try press(XCTUnwrap(word, file: file, line: line), in: host)
            let deadline = ContinuousClock.now + .seconds(1)
            repeat {
                try await Task.sleep(for: .milliseconds(50))
                let changed = try opens.map { try isRendered($0, in: host) }
                    ?? !isRendered(text, exactly: exactly, in: host)
                if changed { return }
            } while ContinuousClock.now < deadline
        }
        XCTFail("Pressing \(text) never changed the screen", file: file, line: line)
    }

    /// Opens #18 (page 2) the way Home's sprite does, then presses the detail page's Back.
    private func openPageTwoSpeciesAndGoBack(_ store: CompanionStore, _ navigation: PopoverNavigation,
                                             _ host: NSView) async throws {
        let species = try XCTUnwrap(store.dexSpecies.first { $0.id == 18 })
        navigation.dexDetailCollectionID = species.collectionID
        try await press(store.l.back, in: host)
    }

    // MARK: Pokédex grid

    /// "Obtenus" is laid out by region like the other scopes (#183): its cells read their number, the page's species
    /// comes back in view after Back.
    func testBackFromDetailReturnsToTheGridWithThatSpecies() async throws {
        let store = try makeStore()
        let navigation = PopoverNavigation()
        navigation.dexScope = .caught
        navigation.tab = .collection
        let root = host(store, navigation)
        try await waitForText("005", in: root)

        try await openPageTwoSpeciesAndGoBack(store, navigation, root)

        try await waitForText("018", in: root)
    }

    /// A segment switch after Back shows the grid from its top.
    func testASegmentSwitchShowsTheGridFromItsTop() async throws {
        let store = try makeStore()
        let navigation = PopoverNavigation()
        navigation.dexScope = .caught
        navigation.tab = .collection
        let root = host(store, navigation)
        try await openPageTwoSpeciesAndGoBack(store, navigation, root)
        try await waitForText("018", in: root)

        navigation.showingCollectionLog = true
        try await Task.sleep(for: .milliseconds(100))
        navigation.showingCollectionLog = false

        try await waitForText("001", in: root)
    }

    /// Back to the log must not leave the grid's return anchor behind for the next segment switch.
    func testBackToTheLogLeavesTheGridOnItsTop() async throws {
        let store = try makeStore()
        let navigation = PopoverNavigation()
        navigation.dexScope = .caught
        navigation.tab = .collection
        navigation.showingCollectionLog = true
        let root = host(store, navigation)
        try await openPageTwoSpeciesAndGoBack(store, navigation, root)
        try await waitForText("Mon20", in: root)   // the log's top row

        navigation.showingCollectionLog = false

        try await waitForText("001", in: root)
    }

    // MARK: Evolution family

    /// A page's evolution family opens the other caught pages of the line, and Back walks back through them before
    /// the grid. Oldest (#1), Mon2 and Mon3 are the Bulbasaur line.
    func testFamilyLineOpensItsPagesAndBackWalksBackThroughThem() async throws {
        let store = try makeStore()
        let navigation = PopoverNavigation()
        navigation.dexScope = .caught   // the caught species page by page
        navigation.tab = .collection
        let root = host(store, navigation)
        navigation.dexDetailCollectionID = "2"
        try await waitForText("Mon3", exactly: true, in: root)
        func waitForPage(_ id: String?) async throws {
            let deadline = ContinuousClock.now + .seconds(3)
            while navigation.dexDetailCollectionID != id && ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(50))
            }
            XCTAssertEqual(navigation.dexDetailCollectionID, id)
        }
        /// Every page has a Back label, so the press is retried until the page changes, not until a label shows.
        func goBack(to id: String?) async throws {
            for _ in 0..<5 where navigation.dexDetailCollectionID != id {
                let back = try await waitForText(store.l.back, in: root)
                try press(XCTUnwrap(back), in: root)
                try await Task.sleep(for: .milliseconds(300))
            }
            try await waitForPage(id)
        }
        // Oldest (#1) from Mon2's family; Mon2's page is where Back returns.
        let mon1 = try await waitForText("Oldest", exactly: true, in: root)
        try await click(XCTUnwrap(mon1), in: root)
        try await waitForPage("1")
        XCTAssertEqual(navigation.dexDetailHistory, [PopoverNavigation.DexPage(collectionID: "2", form: nil)])
        // Mon3 from Oldest's family: two pages to come back through.
        try await waitForText("Mon2", exactly: true, in: root)
        let mon3 = try await waitForText("Mon3", exactly: true, in: root)
        try await click(XCTUnwrap(mon3), in: root)
        try await waitForPage("3")
        try await goBack(to: "1")
        try await goBack(to: "2")
        try await goBack(to: nil)
        try await waitForText("005", in: root)
        XCTAssertTrue(navigation.dexDetailHistory.isEmpty)
    }

    // MARK: Catch log

    /// Oldest is the first catch, so it is the log's last row — off screen until scrolled to.
    func testBackFromDetailReturnsTheLogToWhereItWas() async throws {
        let store = try makeStore()
        let navigation = PopoverNavigation()
        navigation.dexScope = .caught   // the caught species page by page
        navigation.tab = .collection
        navigation.showingCollectionLog = true
        let root = host(store, navigation)
        try await waitForText("Mon20", in: root)
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let log = try XCTUnwrap(descendants(root).compactMap { $0 as? NSScrollView }
            .max { ($0.documentView?.frame.height ?? 0) < ($1.documentView?.frame.height ?? 0) })
        // LazyVStack grows the document as rows are realized, so keep scrolling to the end.
        var row: Word?
        for _ in 0..<20 where row == nil {
            let clip = log.contentView
            let bottom = (log.documentView?.frame.height ?? 0) - clip.bounds.height
            clip.scroll(to: NSPoint(x: 0, y: clip.isFlipped ? bottom : 0))
            log.reflectScrolledClipView(clip)
            try await Task.sleep(for: .milliseconds(100))
            row = try words(in: root).first { $0.reads("Oldest", exactly: true) }
        }
        XCTAssertNotNil(row, "scrolling never reached Oldest")
        try await press("Oldest", exactly: true, opens: store.l.back, in: root)
        try await press(store.l.back, in: root)

        try await waitForText("Oldest", exactly: true, in: root)

        // Like the grid's page, the position does not survive a segment switch.
        navigation.showingCollectionLog = false
        try await Task.sleep(for: .milliseconds(100))
        navigation.showingCollectionLog = true
        try await waitForText("Mon20", in: root)
    }
}
