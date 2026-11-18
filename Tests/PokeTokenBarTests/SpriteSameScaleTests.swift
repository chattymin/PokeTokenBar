import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

private struct SameScaleProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

/// Pokémon shown side by side keep their sizes. Since the stills became Showdown's tightly framed 3D renders, fitting
/// each one to its box made a Charmander (48×57 px) as big as a Charizard (133×140 px) in the Pokédex grid.
@MainActor
final class SpriteSameScaleTests: XCTestCase {
    private static let charmander = CGSize(width: 48, height: 57)
    private static let charizard = CGSize(width: 133, height: 140)

    func testOneScaleKeepsSizesAndFitsOnlyTheLargest() {
        let small = SpriteFit.sameScaleSize(for: Self.charmander, box: 56)
        XCTAssertEqual(small.height, 57 * 56 / SpriteFit.sameScaleReference, accuracy: 0.001)
        XCTAssertEqual(small.width / small.height, 48 / 57, accuracy: 0.001, "the aspect ratio stays")
        XCTAssertLessThan(small.height, 56 / 2, "a Charmander takes under half the box")
        let large = SpriteFit.sameScaleSize(for: Self.charizard, box: 56)
        XCTAssertEqual(large.height, 56, accuracy: 0.001, "a Charizard is fitted to the box")
        XCTAssertEqual(SpriteFit.sameScaleSize(for: .zero, box: 56), CGSize(width: 56, height: 56))
        // Filling the box is still what Home's big sprite does.
        XCTAssertEqual(SpriteView.imageSize(for: Self.solid(Self.charmander), box: 56).height, 56, accuracy: 0.001)
        XCTAssertEqual(SpriteView.imageSize(for: Self.solid(Self.charmander), box: 56, sameScale: true).height,
                       small.height, accuracy: 0.001)
    }

    /// Reads the rendered pixels of an evolution line: the call site must ask for one scale, not only the helper.
    func testAnEvolutionLineDrawsACharmanderSmallerThanACharizard() throws {
        let keys = seedCharmanderAndCharizard()
        defer { for key in keys { SpriteLoader.imageCache.removeObject(forKey: key) } }
        let line = EvoLineView(nodes: [EvoLineItem(.species(4), .done), EvoLineItem(.species(6), .done)],
                               mysteryLabel: "", thumb: 40)
        let host = NSHostingView(rootView: line.background(Color.white))
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        let heights = try spriteHeights(host)
        XCTAssertEqual(heights.count, 2, "two green sprites: \(heights)")
        XCTAssertEqual(heights.last ?? 0, 40, accuracy: 1.5, "the Charizard fills its 40 pt box")
        XCTAssertEqual(heights.first ?? 0, 57 * 40 / SpriteFit.sameScaleReference, accuracy: 1.5,
                       "the Charmander keeps its scale")
    }

    /// The Pokédex grid, where the player saw a Charmander as big as the Charizard two cells away.
    func testThePokedexGridDrawsACharmanderSmallerThanACharizard() async throws {
        let keys = seedCharmanderAndCharizard()
        defer { for key in keys { SpriteLoader.imageCache.removeObject(forKey: key) } }
        var state = CompanionState()
        state.language = .en
        state.dex = [4, 6].map {
            DexEntry(baseID: 4, finalID: $0, chainOrder: $0 == 4 ? [4] : [4, 5, 6], rarity: .common,
                     caughtAt: Date(timeIntervalSince1970: 1_790_000_000), names: [$0: ["en": "Fixture"]])
        }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("same-scale-\(UUID().uuidString).json")
        try JSONEncoder().encode(state).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let store = CompanionStore(provider: SameScaleProvider(), fileURL: file)
        let caught = PopoverNavigation()
        caught.dexScope = .caught   // laid out by region like the whole Pokédex (#183)
        let host = NSHostingView(rootView: CollectionView(store: store, navigation: caught)
            .frame(width: PopoverMetrics.contentWidth, height: 400).background(Color.white))
        host.frame = NSRect(x: 0, y: 0, width: PopoverMetrics.contentWidth, height: 400)
        let heights = try spriteHeights(host)
        XCTAssertEqual(heights.count, 2, "two green sprites: \(heights)")
        // The same cells as the whole Pokédex: 42 pt sprites.
        XCTAssertEqual(heights.max() ?? 0, 42, accuracy: 1.5, "the Charizard fills its 42 pt sprite box")
        XCTAssertEqual(heights.min() ?? 0, 57 * 42 / SpriteFit.sameScaleReference, accuracy: 1.5,
                       "the Charmander keeps its scale")
    }

    /// The whole Pokédex, the default since it came: the test above opens the caught grid, so this one went back to
    /// filling each cell and a Charmander stood as tall as a Charizard.
    func testTheWholePokedexDrawsACharmanderSmallerThanACharizard() async throws {
        let keys = seedCharmanderAndCharizard()
        defer { for key in keys { SpriteLoader.imageCache.removeObject(forKey: key) } }
        var state = CompanionState()
        state.language = .en
        state.dex = [4, 6].map {
            DexEntry(baseID: $0, finalID: $0, chainOrder: [$0], rarity: .common,
                     caughtAt: Date(timeIntervalSince1970: 1_790_000_000), names: [$0: ["en": "Fixture"]])
        }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("same-scale-\(UUID().uuidString).json")
        try JSONEncoder().encode(state).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let store = CompanionStore(provider: SameScaleProvider(), fileURL: file)
        // Searched by their name, so no missing species shows: each would fetch its sprite for a silhouette, and the
        // load would land in the shared sprite cache during a later test.
        let host = NSHostingView(rootView: FullDexView(store: store, searchText: "Fixture", missingOnly: false,
                                                       scope: .constant(.all), onSelectSpecies: { _ in })
            .frame(width: PopoverMetrics.contentWidth, height: 400).background(Color.white))
        host.frame = NSRect(x: 0, y: 0, width: PopoverMetrics.contentWidth, height: 400)
        let heights = try spriteHeights(host)
        XCTAssertEqual(heights.count, 2, "two green sprites: \(heights)")
        // Its cells' sprites are 42 pt.
        XCTAssertEqual(heights.max() ?? 0, 42, accuracy: 1.5, "the Charizard fills its 42 pt sprite box")
        XCTAssertEqual(heights.min() ?? 0, 57 * 42 / SpriteFit.sameScaleReference, accuracy: 1.5,
                       "the Charmander keeps its scale")
    }

    /// Solid green stills for Charmander and Charizard at their Showdown sizes, where `SpriteView` looks first.
    private func seedCharmanderAndCharizard() -> [NSString] {
        [(4, Self.charmander), (6, Self.charizard)].map { id, size in
            let key = SpriteStore.shared.directory
                .appendingPathComponent("\(SpriteStore.cacheKey(speciesID: id, animated: false, shiny: false)).png").path as NSString
            SpriteLoader.imageCache.setObject(Self.solid(size), forKey: key)
            return key
        }
    }

    /// Heights in points of the green sprites, left to right: green columns grouped where they touch.
    private func spriteHeights(_ host: NSView) throws -> [CGFloat] {
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        var groups: [(lastX: Int, rows: Set<Int>)] = []
        for x in 0..<bitmap.pixelsWide {
            var rows = Set<Int>()
            for y in 0..<bitmap.pixelsHigh {
                guard let c = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                // Vivid green: no type dot of a Charmander or a Charizard (Fire, Flying) is.
                if c.greenComponent > 0.85, c.redComponent < 0.45, c.blueComponent < 0.45 { rows.insert(y) }
            }
            guard !rows.isEmpty else { continue }
            if let last = groups.last, x - last.lastX <= 1 {
                groups[groups.count - 1] = (x, last.rows.union(rows))
            } else {
                groups.append((x, rows))
            }
        }
        let pointsPerPixel = host.bounds.width / CGFloat(bitmap.pixelsWide)
        return groups.map { CGFloat($0.rows.count) * pointsPerPixel }
    }

    private static func solid(_ size: CGSize) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.green.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()
        return image
    }
}
