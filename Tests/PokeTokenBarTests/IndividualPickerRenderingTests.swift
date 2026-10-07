import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

private struct PickerRenderProvider: PokeProviding, PokemonDetailProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
    func pokemonDetails(speciesID: Int) async throws -> PokemonDetails {
        PokemonDetails(speciesID: speciesID, name: "parasect", height: 10, weight: 295,
            baseExperience: 142, genderRate: 4, types: ["bug", "grass"],
            baseStats: ["hp": 60, "attack": 95, "defense": 80, "special-attack": 60, "special-defense": 80, "speed": 30],
            abilities: [PokemonAbilityOption(name: "effect-spore", slot: 1, isHidden: false)], moves: [])
    }
}
@MainActor
final class IndividualPickerRenderingTests: XCTestCase {
    func testMountedSingleAndMultipleIndividuals() async throws {
        for count in [1, 2] {
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("individual-picker-\(UUID())")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir) }
            let file = dir.appendingPathComponent("state.json")
            var state = CompanionState()
            state.language = .en
            state.dex = (0..<count).map { i in
                DexEntry(id: "fixture-\(i)", baseID: 46, finalID: 47, chainOrder: [46,47], rarity: .common,
                    caughtAt: Date(timeIntervalSince1970: 1700000000 + Double(i)),
                    profile: PokemonProfile.generate(seed: UInt64(i + 1), instanceID: "fixture-\(i)"),
                    names: [47: ["en": "Parasect"]])
            }
            try JSONEncoder().encode(state).write(to: file)
            let store = CompanionStore(provider: PickerRenderProvider(), fileURL: file)
            await store.loadPokemonDetails(speciesID: 47)
            let species = try XCTUnwrap(store.dexSpecies.first { $0.id == 47 })
            let view = PokemonDetailView(store: store, species: species, onBack: {},
                spriteStore: SpriteStore(directory: dir))
                .frame(width: PopoverMetrics.contentWidth, height: 520)
                .background(Color.white).environment(\.colorScheme, .light)
            let host = NSHostingView(rootView: view)
            host.frame = NSRect(x: 0, y: 0, width: PopoverMetrics.contentWidth, height: 520)
            let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            defer { window.close() }
            window.appearance = NSAppearance(named: .aqua)
            window.contentView = host
            window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
            window.orderFront(nil)
            try await Task.sleep(for: .milliseconds(100))
            host.layoutSubtreeIfNeeded()
            func descendants(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(descendants) }
            let menus = descendants(host).compactMap { $0 as? NSPopUpButton }
            XCTAssertEqual(menus.count, count == 1 ? 0 : 1)
            if count == 2 { XCTAssertEqual(menus.first?.numberOfItems, 2) }
            if let output = ProcessInfo.processInfo.environment["PTB_PICKER_RENDER_DIR"] {
                // Capture only the selector/profile area; no sprite or user save data is included.
                let captureBounds = NSRect(x: 0, y: 140, width: PopoverMetrics.contentWidth, height: 370)
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: captureBounds))
                host.cacheDisplay(in: captureBounds, to: bitmap)
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to:
                    URL(fileURLWithPath: output).appendingPathComponent("individual-\(count).png"))
            }
        }
    }
}
