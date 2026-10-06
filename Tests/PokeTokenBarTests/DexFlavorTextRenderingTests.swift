import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import Vision
import XCTest
@testable import PokeTokenBar

private struct OfflineLines: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

private enum RenderingTestError: Error { case unavailable }

/// No types, abilities or moves: those rows fetch translated names from PokéAPI, and these tests
/// must stay offline. The individual, nature, stat and move sections still render their headings.
private let pikachuDetails = PokemonDetails(
    speciesID: 25, name: "pikachu", height: 4, weight: 60, baseExperience: 112, genderRate: 4, types: [],
    baseStats: ["hp": 35, "attack": 55, "defense": 40, "special-attack": 50, "special-defense": 50, "speed": 90],
    abilities: [], moves: [])

private struct LoadedDetails: PokemonDetailProviding {
    func pokemonDetails(speciesID: Int) async throws -> PokemonDetails { pikachuDetails }
}

private struct FailingDetails: PokemonDetailProviding {
    func pokemonDetails(speciesID: Int) async throws -> PokemonDetails { throw RenderingTestError.unavailable }
}

private actor StalledDetails: PokemonDetailProviding {
    private var continuation: CheckedContinuation<PokemonDetails, Never>?
    func pokemonDetails(speciesID: Int) async throws -> PokemonDetails {
        await withCheckedContinuation { continuation = $0 }
    }
    func release() {
        continuation?.resume(returning: pikachuDetails)
        continuation = nil
    }
}

private actor StalledFlavor: PokemonFlavorTextProviding {
    private var continuation: CheckedContinuation<DexEntries, Never>?
    func flavorTexts(speciesID: Int, language: AppLanguage) async throws -> DexEntries {
        await withCheckedContinuation { continuation = $0 }
    }
    func release() {
        continuation?.resume(returning: DexEntries(entries: [], language: .en))
        continuation = nil
    }
}

/// Answers each call with the next scripted result.
private actor ScriptedFlavor: PokemonFlavorTextProviding {
    private var script: [Result<DexEntries, Error>]
    init(_ script: [Result<DexEntries, Error>]) { self.script = script }
    func flavorTexts(speciesID: Int, language: AppLanguage) async throws -> DexEntries {
        try script.removeFirst().get()
    }
}

private let flavorSentence = "Sample entry for the newest version"

@MainActor
final class DexFlavorTextRenderingTests: XCTestCase {
    /// Every temporary file lives here. CI's Swift 6.1 runs the synchronous tearDown nonisolated, so it
    /// may only touch Sendable constants (see defect-log); the main-actor sprite cache is cleaned in `close(_:)`.
    private let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("flavor-render-\(UUID().uuidString)", isDirectory: true)
    private var spriteDirectory: URL { directory.appendingPathComponent("sprites", isDirectory: true) }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Closes the window and, like the other rendering tests, leaves the shared sprite cache as it was:
    /// its entries are keyed by file path, and these temporary paths would otherwise stay in its 64 slots.
    private func close(_ window: NSWindow) {
        window.close()
        for animated in [false, true] {
            let file = SpriteStore.cacheKey(speciesID: 25, animated: animated, shiny: false) + (animated ? ".gif" : ".png")
            SpriteLoader.imageCache.removeObject(forKey: spriteDirectory.appendingPathComponent(file).path as NSString)
        }
    }

    private func makeStore(language: AppLanguage = .en, details: any PokemonDetailProviding,
                           flavor: any PokemonFlavorTextProviding) throws -> CompanionStore {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("\(UUID().uuidString).json")
        var state = CompanionState()
        state.language = language
        state.dex = [DexEntry(baseID: 25, finalID: 25, chainOrder: [25], rarity: .common,
                              caughtAt: Date(timeIntervalSince1970: 1_700_000_000), nature: .adamant,
                              names: [25: ["en": "Pikachu", "pt": "Pikachu"]])]
        try JSONEncoder().encode(state).write(to: file)
        return CompanionStore(provider: OfflineLines(), detailProvider: details, flavorProvider: flavor, fileURL: file)
    }

    /// Seeds the header sprite so the detail page never downloads one.
    private func offlineSprites() throws -> SpriteStore {
        let directory = spriteDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let image = NSImage(size: NSSize(width: 96, height: 96))
        image.lockFocus()
        NSColor.gray.setFill()
        NSRect(x: 0, y: 0, width: 96, height: 96).fill()
        image.unlockFocus()
        let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        try XCTUnwrap(NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]))
            .write(to: directory.appendingPathComponent(SpriteStore.cacheKey(speciesID: 25, animated: false, shiny: false) + ".png"))
        let gif = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(gif, UTType.gif.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, cgImage, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        try (gif as Data).write(to: directory.appendingPathComponent(SpriteStore.cacheKey(speciesID: 25, animated: true, shiny: false) + ".gif"))
        return SpriteStore(directory: directory)
    }

    /// Letters and digits only, case- and accent-folded, so OCR punctuation and accents do not matter.
    private func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .unicodeScalars.filter(CharacterSet.alphanumerics.contains).map(String.init).joined()
    }

    /// Mounts the real detail page in an offscreen window — by default tall enough to show every section.
    private func mount(_ store: CompanionStore, height: CGFloat = 1500) throws -> (NSHostingView<some View>, NSWindow) {
        let species = try XCTUnwrap(store.dexSpecies.first)
        let size = NSSize(width: PopoverMetrics.contentWidth, height: height)
        let view = PokemonDetailView(store: store, species: species, onBack: {}, spriteStore: try offlineSprites())
            .frame(width: size.width, height: size.height)
            .background(Color.white)
            .environment(\.colorScheme, .light)
            .environment(\.locale, store.language.displayLocale)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -10000, y: -10000), size: size),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        window.orderFront(nil)
        return (host, window)
    }

    /// OCR misreads body-size text at low resolution ("Sample" as "Samole"), and CI renders at a lower
    /// scale than a Retina Mac, so its reads are worse. Capture at 2×, enlarge before OCR, prime Vision with
    /// the words a test looks for, and let text that must be present differ by a few misread letters.
    private static let captureScale: CGFloat = 2
    private static let ocrScale: CGFloat = 3

    private func capture(_ host: NSView) throws -> CGImage {
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(host.bounds.width * Self.captureScale),
            pixelsHigh: Int(host.bounds.height * Self.captureScale), bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.size = host.bounds.size
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let image = try XCTUnwrap(bitmap.cgImage)
        let width = Int(host.bounds.width * Self.ocrScale), height = Int(host.bounds.height * Self.ocrScale)
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(context.makeImage())
    }

    private func recognize(_ host: NSView, words: [String], languages: [String]) throws -> [VNRecognizedTextObservation] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = languages
        request.usesLanguageCorrection = true
        request.customWords = words.flatMap { $0.split { !$0.isLetter }.map(String.init) }
        try VNImageRequestHandler(cgImage: capture(host)).perform([request])
        return request.results ?? []
    }

    /// End offset of the closest match of `needle` inside `haystack` (both normalized), if at most 15% of
    /// its characters differ: OCR slips such as "Samole" still match, different strings do not.
    private func fuzzyMatch(_ needle: String, in haystack: String) -> Int? {
        let n = Array(needle), h = Array(haystack)
        guard !n.isEmpty, !h.isEmpty else { return nil }
        let budget = max(1, n.count * 15 / 100)
        var previous = [Int](repeating: 0, count: h.count + 1)
        for i in 1...n.count {
            var current = [Int](repeating: i, count: h.count + 1)
            for j in 1...h.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (n[i - 1] == h[j - 1] ? 0 : 1))
            }
            previous = current
        }
        guard let best = previous.indices.min(by: { previous[$0] < previous[$1] }), previous[best] <= budget else {
            return nil
        }
        return best
    }

    /// Reads the page back with OCR until every expected string is on screen and every absent one is
    /// gone, or five seconds pass. Returns the last text and what still did not match.
    private func waitForScreen(_ host: NSView, expecting expected: [String], absent: [String] = [],
                               languages: [String] = ["en-US"]) async throws -> (text: String, mismatched: [String]) {
        let deadline = ContinuousClock.now + .seconds(5)
        var text = ""
        var mismatched = expected + absent
        repeat {
            try await Task.sleep(for: .milliseconds(50))
            let observations = try recognize(host, words: expected + absent, languages: languages)
            text = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
            let screen = normalized(text)
            // Text that must be present tolerates misread letters; text that must be gone is matched exactly.
            mismatched = expected.filter { fuzzyMatch(normalized($0), in: screen) == nil }
                + absent.filter { screen.contains(normalized($0)) }
        } while !mismatched.isEmpty && ContinuousClock.now < deadline
        return (text, mismatched)
    }

    private func screenText(of store: CompanionStore, expecting expected: [String],
                            languages: [String] = ["en-US"]) async throws -> (text: String, missing: [String]) {
        let (host, window) = try mount(store)
        defer { close(window) }
        let screen = try await waitForScreen(host, expecting: expected, languages: languages)
        return (screen.text, screen.mismatched)
    }

    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }

    /// Center of the first OCR line containing `text`, in the host's (window's) coordinates.
    private func locate(_ text: String, in host: NSView, languages: [String] = ["en-US"]) throws -> NSPoint? {
        let box = try recognize(host, words: [text], languages: languages).first {
            fuzzyMatch(normalized(text), in: normalized($0.topCandidates(1).first?.string ?? "")) != nil
        }?.boundingBox
        return box.map { NSPoint(x: $0.midX * host.bounds.width, y: $0.midY * host.bounds.height) }
    }

    /// Some controls track the mouse inside mouseDown and pull the mouseUp from the event queue (a
    /// borderless button); others expect it as a separate event (a bordered one). Queue the mouseUp
    /// first so a tracking loop can finish, then deliver it directly if nothing took it — that also
    /// leaves no event behind for a later test.
    private func click(_ window: NSWindow, at point: NSPoint) async throws {
        func event(_ type: NSEvent.EventType) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        }
        NSApp.postEvent(try event(.leftMouseUp), atStart: false)
        window.sendEvent(try event(.leftMouseDown))
        if let unclaimed = NSApp.nextEvent(matching: .leftMouseUp, until: nil, inMode: .default, dequeue: true) {
            window.sendEvent(unclaimed)
        }
        try await Task.sleep(for: .milliseconds(30))
    }

    private func entries(language: AppLanguage = .en, degraded: Bool = false) -> DexEntries {
        DexEntries(entries: [DexFlavorText(versionKey: "sword", versionID: 33, versionLabel: "Sword",
                                           text: flavorSentence)],
                   language: language, isDegraded: degraded)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
    }

    func testFlavorFailureKeepsEveryExistingDetailSection() async throws {
        let store = try makeStore(details: LoadedDetails(),
                                  flavor: ScriptedFlavor([.failure(RenderingTestError.unavailable)]))
        let l = store.l
        // OCR reads the count's "0" as "O"; the heading without it is enough.
        let moveList = l.completeMoveList(0).replacingOccurrences(of: "0", with: "")
        let screen = try await screenText(of: store, expecting: [
            l.pokemonIndividual, l.nature, PokemonNature.adamant.name(.en), l.ability, l.actualStats,
            l.activeMoves, l.speciesData, l.possibleAbilities, moveList, l.dexFlavorFailed, l.retry,
        ])
        XCTAssertEqual(screen.missing, [], screen.text)
        // The failure stays inside the species data card, above the move list.
        let text = normalized(screen.text)
        let positions = [l.speciesData, l.dexFlavorFailed, moveList].compactMap {
            fuzzyMatch(normalized($0), in: text)
        }
        XCTAssertEqual(positions.count, 3, screen.text)
        XCTAssertEqual(positions, positions.sorted(), screen.text)
    }

    /// A stalled entries request shows its loading row inside the card, not an empty page.
    func testBattleDetailsDoNotWaitForPokedexEntries() async throws {
        let flavor = StalledFlavor()
        let store = try makeStore(details: LoadedDetails(), flavor: flavor)
        let screen = try await screenText(of: store, expecting: [
            store.l.actualStats, store.l.speciesData, store.l.dexFlavorLoading,
        ])
        await flavor.release()
        XCTAssertEqual(screen.missing, [], screen.text)
    }

    /// The entries are requested in their own task, so they are ready while battle details still load
    /// and appear together with the species card.
    func testEntriesLoadAlongsideBattleDetails() async throws {
        let details = StalledDetails()
        let store = try makeStore(details: details, flavor: ScriptedFlavor([.success(entries())]))
        let request = store.flavorTextRequest(speciesID: 25)
        let (host, window) = try mount(store)
        defer { close(window) }
        try await waitUntil { store.flavorTextsByRequest[request] != nil }
        XCTAssertNotNil(store.flavorTextsByRequest[request], "entries must not wait for battle details")
        XCTAssertNil(store.pokemonDetailsByID[25])
        await details.release()
        let screen = try await waitForScreen(host, expecting: [flavorSentence, store.l.dexFlavorShowAll])
        XCTAssertEqual(screen.mismatched, [], screen.text)
    }

    /// REST entry shown → revisit refetches and fails → the entry stays beside retry → retry succeeds and
    /// the localized version name replaces the slug.
    func testFailedRefetchKeepsTheDegradedEntryUntilRetryRestoresLocalizedLabels() async throws {
        let localized = DexEntries(entries: [DexFlavorText(versionKey: "sword", versionID: 33,
                                                           versionLabel: "Localized Sword", text: flavorSentence)],
                                   language: .en)
        let store = try makeStore(details: LoadedDetails(), flavor: ScriptedFlavor([
            .success(entries(degraded: true)), .failure(RenderingTestError.unavailable), .success(localized),
        ]))
        await store.loadFlavorTexts(speciesID: 25)
        let l = store.l
        let (host, window) = try mount(store)
        defer { close(window) }
        var screen = try await waitForScreen(host, expecting: [
            "Sword", flavorSentence, l.dexFlavorShowAll, l.dexFlavorFailed, l.retry,
        ])
        XCTAssertEqual(screen.mismatched, [], screen.text)
        XCTAssertTrue(store.failedFlavorTextRequests.contains(store.flavorTextRequest(speciesID: 25)),
                      "the page must have refetched the degraded result on entry")

        try await click(window, at: XCTUnwrap(locate(l.retry, in: host)))
        screen = try await waitForScreen(host, expecting: ["Localized Sword", flavorSentence],
                                         absent: [l.dexFlavorFailed])
        XCTAssertEqual(screen.mismatched, [], screen.text)
        XCTAssertFalse(store.flavorTextsByRequest[store.flavorTextRequest(speciesID: 25)]?.isDegraded ?? true)
    }

    /// PokéAPI has no Portuguese entries; both the card and the entries page say why the text is English.
    func testEnglishFallbackIsAnnouncedOnTheCardAndThePage() async throws {
        let store = try makeStore(language: .pt, details: LoadedDetails(),
                                  flavor: ScriptedFlavor([.success(entries(language: .en))]))
        let l = store.l
        let languages = ["pt-BR", "en-US"]
        let (host, window) = try mount(store)
        defer { close(window) }
        var screen = try await waitForScreen(host, expecting: [l.dexFlavorEnglishFallback, flavorSentence, l.dexFlavorShowAll],
                                             languages: languages)
        XCTAssertEqual(screen.mismatched, [], screen.text)

        try await click(window, at: XCTUnwrap(locate(l.dexFlavorShowAll, in: host, languages: languages)))
        screen = try await waitForScreen(host, expecting: [l.dexFlavorTitle, l.dexFlavorEnglishFallback, flavorSentence],
                                         absent: [l.speciesData], languages: languages)
        XCTAssertEqual(screen.mismatched, [], screen.text)
    }

    /// "All Pokédex entries" opens every version oldest first; Back returns to the same detail page —
    /// still mounted, at the same scroll position.
    func testAllEntriesPageListsEveryVersionOldestFirstAndBackRestoresTheDetail() async throws {
        // Different first words, so a tolerant match cannot mistake one entry for another.
        let texts = ["Amber entry text", "Cobalt entry text", "Jade entry text"]
        let all = DexEntries(entries: [
            DexFlavorText(versionKey: "red", versionID: 1, versionLabel: "Red", text: texts[0]),
            DexFlavorText(versionKey: "x", versionID: 23, versionLabel: "X", text: texts[1]),
            DexFlavorText(versionKey: "sword", versionID: 33, versionLabel: "Sword", text: texts[2]),
        ], language: .en)
        let store = try makeStore(details: LoadedDetails(), flavor: ScriptedFlavor([.success(all)]))
        let l = store.l
        let (host, window) = try mount(store, height: 520)
        defer { close(window) }
        try await waitUntil {
            store.pokemonDetailsByID[25] != nil && store.flavorTextsByRequest[store.flavorTextRequest(speciesID: 25)] != nil
        }

        // The species card sits below the fold of the real 520pt page; scroll to it like a user would.
        host.layoutSubtreeIfNeeded()
        let detailScroll = try XCTUnwrap(descendants(host).compactMap { $0 as? NSScrollView }.first)
        let bottom = (detailScroll.documentView?.frame.height ?? 0) - detailScroll.contentView.bounds.height
        XCTAssertGreaterThan(bottom, 0, "the detail page must be taller than the popover")
        detailScroll.contentView.scroll(to: NSPoint(x: 0, y: bottom))
        detailScroll.reflectScrolledClipView(detailScroll.contentView)
        var screen = try await waitForScreen(host, expecting: [texts[2], l.dexFlavorShowAll],
                                             absent: [texts[0], texts[1]])
        XCTAssertEqual(screen.mismatched, [], "the card shows only the newest entry: \(screen.text)")
        let offset = detailScroll.documentVisibleRect.origin.y

        try await click(window, at: XCTUnwrap(locate(l.dexFlavorShowAll, in: host)))
        screen = try await waitForScreen(host, expecting: texts + [l.dexFlavorTitle],
                                         absent: [l.speciesData, l.actualStats])
        XCTAssertEqual(screen.mismatched, [], screen.text)
        let page = normalized(screen.text)
        let positions = texts.compactMap { fuzzyMatch(normalized($0), in: page) }
        XCTAssertEqual(positions.count, 3, screen.text)
        XCTAssertEqual(positions, positions.sorted(), "oldest first: \(screen.text)")

        try await click(window, at: XCTUnwrap(locate(l.back, in: host)))
        screen = try await waitForScreen(host, expecting: [l.speciesData, texts[2]], absent: [texts[0], texts[1]])
        XCTAssertEqual(screen.mismatched, [], screen.text)
        XCTAssertNotNil(detailScroll.window, "the detail page stays mounted under the entries page")
        XCTAssertEqual(detailScroll.documentVisibleRect.origin.y, offset, accuracy: 1)
    }
}
