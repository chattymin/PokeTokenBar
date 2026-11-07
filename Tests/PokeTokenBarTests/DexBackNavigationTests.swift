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
        let readings: [VNRecognizedText]

        /// Spaces are ignored: Vision splits and joins words inconsistently.
        func reads(_ text: String, exactly: Bool) -> Bool {
            let wanted = text.replacingOccurrences(of: " ", with: "")
            return candidates.contains {
                let candidate = $0.replacingOccurrences(of: " ", with: "")
                return exactly ? candidate == wanted : candidate.contains(wanted)
            }
        }

        /// Vision may combine neighboring chips into one observation. Click this label's glyphs,
        /// rather than the midpoint of that whole row (which can be a different, disabled chip).
        func focused(on text: String) throws -> Word? {
            for reading in readings {
                guard let range = reading.string.range(of: text),
                      let rectangle = try reading.boundingBox(for: range) else { continue }
                return Word(candidates: candidates, box: rectangle.boundingBox, readings: readings)
            }
            return nil
        }
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
            let readings = observation.topCandidates(10)
            return readings.isEmpty ? nil : Word(candidates: readings.map(\.string),
                                                 box: observation.boundingBox, readings: readings)
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

    /// Uses the same complete rendered state before and after each attempt. Checking the state
    /// before retrying avoids toggling a selection back off when the first click has just settled.
    private func pressRegionChip(_ label: String, showing: [String], hiding: [String] = [],
                                 in root: NSView, file: StaticString = #filePath,
                                 line: UInt = #line) async throws -> Bool {
        func reached(_ seen: [Word]) -> Bool {
            showing.allSatisfy { text in seen.contains { $0.reads(text, exactly: true) } }
                && hiding.allSatisfy { text in !seen.contains { $0.reads(text, exactly: true) } }
        }
        var seen = try words(in: root)
        for attempt in 1...5 {
            if reached(seen) { return true }
            let chip = try XCTUnwrap(try seen.compactMap { try $0.focused(on: label) }
                .max { $0.box.midY < $1.box.midY },
                "No glyph bounds for \(label). Seen: \(seen.map(\.candidates))", file: file, line: line)
            print("Region click \(attempt): candidates=\(chip.candidates) glyphBox=\(chip.box)")
            try press(chip, in: root)
            let deadline = ContinuousClock.now + .seconds(1)
            repeat {
                try await Task.sleep(for: .milliseconds(50))
                seen = try words(in: root)
                if reached(seen) { return true }
            } while ContinuousClock.now < deadline
        }
        try saveRegionRender(root, phase: "failed")
        XCTFail("Pressing \(label) did not show \(showing) / hide \(hiding). Seen: \(seen.map(\.candidates))",
                file: file, line: line)
        return false
    }

    /// CI already uploads this directory. Keep exact pixels alongside the click/OCR diagnostics.
    private func saveRegionRender(_ root: NSView, phase: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["PTB_SNAPSHOT_SCREENSHOT_DIR"] else { return }
        let destination = URL(fileURLWithPath: directory)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        root.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(root.bitmapImageRepForCachingDisplay(in: root.bounds))
        root.cacheDisplay(in: root.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: destination.appendingPathComponent("dex-region-\(phase).png"))
    }

    func testClickBoundsFocusOnTheRequestedTextInsideAMergedObservation() throws {
        let renderer = ImageRenderer(content: Text("Before Middle After")
            .font(.system(size: 24)).foregroundStyle(.black)
            .padding(16).background(Color.white))
        renderer.scale = 2
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        try VNImageRequestHandler(cgImage: XCTUnwrap(renderer.cgImage)).perform([request])
        let observation = try XCTUnwrap(request.results?.first { result in
            result.topCandidates(10).contains { $0.string.contains("Before Middle After") }
        })
        let readings = observation.topCandidates(10)
        let merged = Word(candidates: readings.map(\.string), box: observation.boundingBox, readings: readings)
        let middle = try XCTUnwrap(try merged.focused(on: "Middle"))
        XCTAssertGreaterThan(middle.box.minX, merged.box.minX)
        XCTAssertLessThan(middle.box.maxX, merged.box.maxX)
    }

    func testRegionChipFiltersMountedCollectionAndTogglesBack() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("dex-region-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: file) }
        var state = CompanionState()
        state.language = .en
        state.dex = [
            DexEntry(baseID: 1, finalID: 1, chainOrder: [1], rarity: .common,
                     caughtAt: Date(), names: [1: ["en": "Maple"]]),
            DexEntry(baseID: 152, finalID: 152, chainOrder: [152], rarity: .common,
                     caughtAt: Date(), names: [152: ["en": "Willow"]]),
        ]
        try JSONEncoder().encode(state).write(to: file)
        let store = CompanionStore(provider: OfflineProvider(), fileURL: file)
        let navigation = PopoverNavigation()
        navigation.tab = .collection
        let root = host(store, navigation)
        try await waitForText("Maple", exactly: true, in: root)
        try await waitForText("Willow", exactly: true, in: root)
        try saveRegionRender(root, phase: "before")

        guard try await pressRegionChip("Johto", showing: ["Willow"], hiding: ["Maple"], in: root) else { return }
        XCTAssertFalse(try isRendered("Maple", exactly: true, in: root))
        try await waitForText("Willow", exactly: true, in: root)
        try saveRegionRender(root, phase: "johto")

        guard try await pressRegionChip("Johto", showing: ["Maple", "Willow"], in: root) else { return }
        try await waitForText("Maple", exactly: true, in: root)
        try await waitForText("Willow", exactly: true, in: root)
        try saveRegionRender(root, phase: "restored")
    }

    func testBackFromDetailReturnsToThePageOfThatSpecies() async throws {
        let store = try makeStore()
        let navigation = PopoverNavigation()
        navigation.tab = .collection
        let root = host(store, navigation)
        try await waitForText("Mon5", in: root)

        try await openPageTwoSpeciesAndGoBack(store, navigation, root)

        try await waitForText("Mon20", in: root)
        // Only the page comes back: the species is not selected, so the footer does not name it.
        let footer = try words(in: root).filter { $0.box.midY < 0.05 }   // y-up: the bottom strip
        XCTAssertFalse(footer.contains { $0.reads("Mon18", exactly: false) }, "Seen: \(footer.map(\.candidates))")
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

    /// Back to the log must not leave the grid's return page behind for the next segment switch.
    func testBackToTheLogLeavesTheGridOnItsFirstPage() async throws {
        let store = try makeStore()
        let navigation = PopoverNavigation()
        navigation.tab = .collection
        navigation.showingCollectionLog = true
        let root = host(store, navigation)
        try await openPageTwoSpeciesAndGoBack(store, navigation, root)
        try await waitForText("Mon20", in: root)   // the log's top row

        navigation.showingCollectionLog = false

        try await waitForText("Mon5", in: root)
    }

    // MARK: Catch log

    /// Oldest is the first catch, so it is the log's last row — off screen until scrolled to.
    func testBackFromDetailReturnsTheLogToWhereItWas() async throws {
        let store = try makeStore()
        let navigation = PopoverNavigation()
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
