import AppKit
import SwiftUI
import XCTest
import Vision
@testable import PokeTokenBar

private struct ReadabilityProvider: PokeProviding, PokemonDetailProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
    func pokemonDetails(speciesID: Int) async throws -> PokemonDetails {
        PokemonDetails(speciesID: speciesID, name: "fixture", height: 12, weight: 360,
                       baseExperience: 63, genderRate: 4, types: ["water", "psychic"],
                       baseStats: ["hp": 90, "attack": 65, "defense": 65,
                                   "special-attack": 40, "special-defense": 40, "speed": 15],
                       abilities: [PokemonAbilityOption(name: "oblivious", slot: 1, isHidden: false)],
                       moves: [PokemonMoveOption(name: "tackle", learnMethods: [
                           PokemonMoveLearnMethod(method: "level-up", level: 1)])])
    }
}

/// Opt-in native captures use temporary saves and existing sprite cache, never the user's collection.
@MainActor
final class CollectionReadabilityRenderingTests: XCTestCase {
    func testGenerateCollectionReadabilityEvidence() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_COLLECTION_SCREENSHOT_DIR"] else {
            throw XCTSkip("Set PTB_COLLECTION_SCREENSHOT_DIR for native collection layout evidence")
        }
        let directory = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let ids = [13, 14, 114, 129, 130, 131, 140, 141, 165, 166, 169, 177, 178, 265, 266, 267, 287, 15]
        let korean = [13: "뿔충이", 14: "딱충이", 15: "독침붕", 114: "덩쿠리", 129: "잉어킹", 130: "갸라도스", 131: "라프라스", 140: "투구", 141: "투구푸스", 165: "레디바", 166: "레디안", 169: "크로뱃", 177: "네이티", 178: "네이티오", 265: "개무소", 266: "실쿤", 267: "뷰티플라이", 287: "게을로"]
        // Long translated names intentionally stress the labels; Korean captures use real names.
        let names = Dictionary(uniqueKeysWithValues: ids.map { id in
            (id, ["en": "Crabominable", "ko": korean[id]!, "ja": "ケケンカニ", "ja-hrkt": "ケケンカニ", "es": "Crabominable", "fr": "Crabominable", "pt": "Crabominable", "pt-br": "Crabominable", "de": "Krawell"])
        })
        let requestedLanguage = ProcessInfo.processInfo.environment["PTB_COLLECTION_SCREENSHOT_LANGUAGE"]
        for language in AppLanguage.allCases where requestedLanguage == nil || language.rawValue == requestedLanguage {
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("collection-readability-\(UUID()).json")
            defer { try? FileManager.default.removeItem(at: file) }
            var state = CompanionState()
            state.language = language
            state.dex = ids.enumerated().map { offset, id in
                DexEntry(baseID: id == 15 ? 13 : id, finalID: id, chainOrder: id == 15 ? [13, 14, 15] : [id], rarity: [.common, .uncommon, .rare, .legendary][offset % 4],
                         caughtAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(offset)),
                         nature: .adamant, names: names)
            }
            try JSONEncoder().encode(state).write(to: file)
            let store = CompanionStore(provider: ReadabilityProvider(), fileURL: file)
            for log in [false, true] {
                let navigation = PopoverNavigation()
                navigation.showingCollectionLog = log
                try await capture(CollectionView(store: store, navigation: navigation), language: language,
                                  expectedTexts: [.common, .uncommon, .rare, .legendary].map(store.l.rarityLabel),
                                  to: directory.appendingPathComponent("\(language.rawValue)-\(log ? "log" : "grid").png"))
            }
            let species = try XCTUnwrap(store.dexSpecies.first)
            await store.loadPokemonDetails(speciesID: species.id)
            try await capture(PokemonDetailView(store: store, species: species, onBack: {}), language: language,
                              expectedTexts: [store.l.pokemonIndividual],
                              to: directory.appendingPathComponent("\(language.rawValue)-detail.png"))
        }
    }

    private func capture<V: View>(_ view: V, language: AppLanguage, expectedTexts: [String], to file: URL) async throws {
        let host = NSHostingView(rootView: view
            .frame(width: PopoverMetrics.contentWidth, height: 520)
            .background(Color.white)
            .environment(\.colorScheme, .light)
            .environment(\.locale, language.displayLocale))
        host.frame = NSRect(x: 0, y: 0, width: PopoverMetrics.contentWidth, height: 520)
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: PopoverMetrics.contentWidth, height: 520),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        XCTAssertEqual(host.bounds.width, 332, accuracy: 0.5)
        XCTAssertEqual(host.bounds.height, 520, accuracy: 0.5)
        let deadline = ContinuousClock.now + .seconds(5)
        var recognized = ""
        repeat {
            try await Task.sleep(for: .milliseconds(100))
            host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = [language == .ko ? "ko-KR" : language == .ja ? "ja-JP" : language.rawValue]
            try VNImageRequestHandler(cgImage: XCTUnwrap(bitmap.cgImage)).perform([request])
            recognized = request.results?.filter { expectedTexts.count == 1 || $0.boundingBox.midY > 0.75 }
                .compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ") ?? ""
            if expectedTexts.allSatisfy({ recognized.localizedCaseInsensitiveContains($0) }) {
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: file)
                if file.lastPathComponent == "en-grid.png" {
                    try await verifyPagination(host: host, window: window, directory: file.deletingLastPathComponent())
                }
                return
            }
        } while ContinuousClock.now < deadline
        XCTFail("Missing visible content \(expectedTexts) in \(file.lastPathComponent): \(recognized)")
    }

    private func verifyPagination(host: NSView, window: NSWindow, directory: URL) async throws {
        for (x, expected, name) in [(326.0, "2/2", "next"), (273.0, "1/2", "back")] {
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: 9),
                    modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
                window.sendEvent(event)
            }
            try await Task.sleep(for: .milliseconds(300))
            host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            try VNImageRequestHandler(cgImage: XCTUnwrap(bitmap.cgImage)).perform([request])
            let text = request.results?.filter { $0.boundingBox.midY < 0.05 }.flatMap { $0.topCandidates(10).map(\.string) }.joined(separator: " | ").replacingOccurrences(of: " ", with: "") ?? ""
            XCTAssertTrue(text.contains(expected), "Pagination \(name) must visibly show \(expected): \(text)")
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: directory.appendingPathComponent("en-grid-\(name).png"))
        }
    }
}
