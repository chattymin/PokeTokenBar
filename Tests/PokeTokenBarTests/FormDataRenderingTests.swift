import AppKit
import SwiftUI
import Vision
import XCTest
@testable import PokeTokenBar

private struct FormDataProvider: PokeProviding, PokemonDetailProviding {
    let detailsAvailable: Bool

    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: baseSpeciesID, tree: EvoNode(speciesID: baseSpeciesID, children: []),
                rarity: .legendary, names: [baseSpeciesID: ["en": "Shaymin"]])
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
    func pokemonDetails(speciesID: Int) async throws -> PokemonDetails {
        try await pokemonDetails(pokemonID: speciesID, speciesID: speciesID)
    }
    /// Each variety its own data: Land Shaymin (492) is 0.2 m and 2.1 kg, Sky Shaymin (10006) 0.4 m and 5.2 kg.
    func pokemonDetails(pokemonID: Int, speciesID: Int) async throws -> PokemonDetails {
        guard detailsAvailable else { throw URLError(.notConnectedToInternet) }
        let sky = pokemonID == 10006
        return PokemonDetails(speciesID: speciesID, name: sky ? "shaymin-sky" : "shaymin", height: sky ? 4 : 2,
            weight: sky ? 52 : 21, baseExperience: 270, genderRate: -1, types: sky ? ["grass", "flying"] : ["grass"],
            baseStats: Dictionary(uniqueKeysWithValues: PokemonStatCalculator.order.map { ($0, 100) }),
            abilities: [PokemonAbilityOption(name: sky ? "serene-grace" : "natural-cure", slot: 1, isHidden: false)],
            moves: [])
    }
}

/// Reads the real Home and Pokédex pixels: a helper-only test would miss either missing call site. A form shows its
/// own types and data; they used to be the default form's, with a "Data uses the default form" note.
@MainActor
final class FormDataRenderingTests: XCTestCase {
    private var windows: [NSWindow] = []

    override func tearDown() async throws {
        windows.forEach { $0.close() }
        windows = []
    }

    private func store(form: PokemonForm?, speciesID: Int = 492, egg: Bool = false,
                       detailsAvailable: Bool = true) async throws -> CompanionStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("form-note-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("state.json")
        let suite = "FormData-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        var state = CompanionState()
        state.language = .en
        if !egg {
            state.active = MonState(baseID: speciesID, pathIDs: [speciesID], stageIndex: 0,
                usedAtStage: 0, rarity: .legendary, totalForms: 1, form: form)
            let forms: [PokemonForm?] = speciesID == 492 ? [PokemonForm("land"), PokemonForm("sky")] : [nil]
            state.dex = forms.map {
                DexEntry(baseID: speciesID, finalID: speciesID, chainOrder: [speciesID], rarity: .legendary,
                         caughtAt: Date(timeIntervalSince1970: 1_700_000_000),
                         names: [speciesID: ["en": "Shaymin"]], form: $0)
            }
            state.representativeSpeciesID = speciesID
            state.representativeForm = form
        }
        try JSONEncoder().encode(state).write(to: file)
        let store = CompanionStore(provider: FormDataProvider(detailsAvailable: detailsAvailable),
                                   fileURL: file, defaults: defaults)
        if !egg && detailsAvailable { await store.loadPokemonDetails(speciesID: speciesID, form: form) }
        return store
    }

    private func mount<V: View>(_ view: V, height: CGFloat) -> NSView {
        let host = NSHostingView(rootView: view.frame(width: PopoverMetrics.contentWidth, height: height)
            .background(Color.white).environment(\.colorScheme, .light))
        host.frame = NSRect(x: 0, y: 0, width: PopoverMetrics.contentWidth, height: height)
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000,
            width: host.frame.width, height: height), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        window.orderFront(nil)
        windows.append(window)
        return host
    }

    private func renderedText(_ host: NSView) throws -> String {
        host.layoutSubtreeIfNeeded()
        // Keep caption OCR at 2x regardless of the runner's screen backing scale.
        let bounds = host.bounds
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int((bounds.width * 2).rounded(.up)),
            pixelsHigh: Int((bounds.height * 2).rounded(.up)),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.size = bounds.size
        XCTAssertGreaterThanOrEqual(CGFloat(bitmap.pixelsWide) / bounds.width, 2)
        XCTAssertGreaterThanOrEqual(CGFloat(bitmap.pixelsHigh) / bounds.height, 2)
        host.cacheDisplay(in: bounds, to: bitmap)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        try VNImageRequestHandler(cgImage: XCTUnwrap(bitmap.cgImage)).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: " ").lowercased()
    }

    /// The rendered text once `ready` holds, or after five seconds.
    private func renderedText(_ host: NSView, until ready: (String) -> Bool) async throws -> String {
        let deadline = ContinuousClock.now + .seconds(5)
        var text = ""
        repeat {
            text = try renderedText(host)
            if ready(text) { break }
            try await Task.sleep(for: .milliseconds(50))
        } while ContinuousClock.now < deadline
        return text
    }

    /// Home shows the form's own types, with or without PokéAPI's data.
    func testHomeShowsTheFormsOwnTypes() async throws {
        let cases: [(form: PokemonForm?, speciesID: Int, egg: Bool, loaded: Bool, shown: [String], hidden: [String])] = [
            (PokemonForm("sky"), 492, false, true, ["grass", "flying"], []),
            (PokemonForm("land"), 492, false, true, ["grass"], ["flying"]),
            (PokemonForm("sky"), 25, false, true, ["electric"], ["grass"]),
            (PokemonForm("sky"), 492, false, false, ["grass", "flying"], []),
            (nil, 492, true, false, [], ["grass"]),
        ]
        for item in cases {
            let store = try await store(form: item.form, speciesID: item.speciesID, egg: item.egg,
                                        detailsAvailable: item.loaded)
            let host = mount(CompanionHeader(store: store), height: 260)
            let text = try await renderedText(host) { !$0.isEmpty && item.shown.allSatisfy($0.contains) }
            for type in item.shown { XCTAssertTrue(text.contains(type), "\(type) in: \(text)") }
            for type in item.hidden { XCTAssertFalse(text.contains(type), "\(type) in: \(text)") }
        }
    }

    /// The Pokédex shows the displayed form's own types and data: a Sky Shaymin is 0.4 m and 5.2 kg, not the Land
    /// form's 0.2 m and 2.1 kg. The page loads the form's details itself. Size, not the ability: ability names come
    /// from PokéAPI and may still be loading on a CI runner (`FormDetailsTests` checks the ability).
    func testDexShowsTheDisplayedFormsOwnData() async throws {
        for form in [PokemonForm("land"), PokemonForm("sky")] {
            let store = try await store(form: form, detailsAvailable: true)
            // Pass the aggregate/default species, as CollectionView does; the representative is the form.
            let species = try XCTUnwrap(store.dexSpecies.first { $0.id == 492 })
            // The species data stands in the Species tab (#183).
            let host = mount(PokemonDetailView(store: store, species: species, onBack: {}, initialTab: .species), height: 900)
            let sky = form == PokemonForm("sky")
            // Type names load asynchronously: wait for the second badge's too.
            let text = try await renderedText(host) {
                $0.contains(sky ? "5.2 kg" : "2.1 kg") && (!sky || $0.contains("flying"))
            }
            XCTAssertEqual(text.contains("5.2 kg"), sky, text)
            XCTAssertEqual(text.contains("2.1 kg"), !sky, text)
            XCTAssertEqual(text.contains("flying"), sky, text)
            XCTAssertFalse(text.contains("default form"), text)
        }
    }
}
