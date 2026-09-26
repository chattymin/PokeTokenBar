import AppKit
import SwiftUI
import ImageIO
import UniformTypeIdentifiers
import Vision
import XCTest
@testable import PokeTokenBar

private struct ColorRenderingProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

@MainActor
final class DexColorRenderingTests: XCTestCase {
    // Synthetic pixels make the two appearances unambiguous without network or user saves.
    private func solidImage(_ color: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: 96, height: 96))
        image.lockFocus()
        color.setFill()
        NSRect(x: 0, y: 0, width: 96, height: 96).fill()
        image.unlockFocus()
        return image
    }

    private func withSprites(_ body: () throws -> Void) throws {
        let keys = [false, true].map {
            SpriteLoader.cacheDir.appendingPathComponent(
                SpriteStore.cacheKey(speciesID: 606, animated: false, shiny: $0) + ".png").path as NSString
        }
        let previous = keys.map { SpriteLoader.imageCache.object(forKey: $0) }
        for (key, color) in zip(keys, [NSColor.red, NSColor.blue]) {
            SpriteLoader.imageCache.setObject(solidImage(color), forKey: key)
        }
        defer {
            for (key, image) in zip(keys, previous) {
                if let image { SpriteLoader.imageCache.setObject(image, forKey: key) }
                else { SpriteLoader.imageCache.removeObject(forKey: key) }
            }
        }
        try body()
    }

    private func fixture(shinyLast: Bool) throws -> (CompanionStore, URL) {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("dex-color-\(UUID()).json")
        var state = CompanionState()
        state.language = .en
        state.dex = [!shinyLast, shinyLast].enumerated().map { index, shiny in
            DexEntry(baseID: 606, finalID: 606, chainOrder: [606], rarity: .common,
                     caughtAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(index)),
                     isShiny: shiny, names: [606: ["en": "Elgyem"]])
        }
        try JSONEncoder().encode(state).write(to: file)
        return (CompanionStore(provider: ColorRenderingProvider(), fileURL: file), file)
    }

    private func colorRows(_ captured: NSBitmapImageRep, shiny: Bool) -> [Int] {
        // AppKit display caches may use float/extended color formats. Normalize via PNG
        // before reading components, matching the pixels written to the evidence file.
        guard let data = captured.representation(using: .png, properties: [:]),
              let bitmap = NSBitmapImageRep(data: data) else { return [] }
        var rows: [Int] = []
        for y in 0..<bitmap.pixelsHigh {
            var matches = 0
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                if color.greenComponent < 0.4,
                   (shiny ? color.blueComponent > 0.8 && color.redComponent < 0.3
                          : color.redComponent > 0.8 && color.blueComponent < 0.3) {
                    matches += 1
                }
            }
            if matches >= 20 { rows.append(y) }
        }
        return rows
    }

    /// The selector's header updates synchronously, but SpriteView changes its cached image in
    /// .task(id:). Wait for those rendered pixels rather than assuming one 100ms sleep is enough.
    /// The deadline only bounds a broken test; the full pixel and badge assertions remain below.
    private func waitForDetailSprite(_ host: NSView, shiny: Bool) async throws -> NSBitmapImageRep {
        let deadline = ContinuousClock.now + .seconds(5)
        while true {
            host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            let normalized = try XCTUnwrap(NSBitmapImageRep(data: png))
            let scale = CGFloat(bitmap.pixelsWide) / host.bounds.width
            // Center of the synthetic 82pt identity sprite, below the appearance picker.
            let pixel = try XCTUnwrap(normalized.colorAt(x: Int(41 * scale), y: Int(101 * scale))?
                .usingColorSpace(.deviceRGB))
            let ready = pixel.greenComponent < 0.4
                && (shiny ? pixel.blueComponent > 0.8 && pixel.redComponent < 0.3
                           : pixel.redComponent > 0.8 && pixel.blueComponent < 0.3)
            if ready || ContinuousClock.now >= deadline { return bitmap }
            // Yield the main actor so the appearance's .task and following SwiftUI render can run.
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    func testDetailSelectorChangesMountedPixelsAndReturnsToNormal() async throws {
        let (store, file) = try fixture(shinyLast: true)
        defer { try? FileManager.default.removeItem(at: file) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("detail-colors-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for (shiny, color) in zip([false, true], [NSColor.red, NSColor.blue]) {
            let cgImage = try XCTUnwrap(solidImage(color).cgImage(forProposedRect: nil, context: nil, hints: nil))
            let bitmap = NSBitmapImageRep(cgImage: cgImage)
            let key = SpriteStore.cacheKey(speciesID: 606, animated: false, shiny: shiny)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: directory.appendingPathComponent(key + ".png"))
            let data = NSMutableData()
            let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString, 1, nil))
            CGImageDestinationAddImage(destination, cgImage, nil)
            XCTAssertTrue(CGImageDestinationFinalize(destination))
            let animatedKey = SpriteStore.cacheKey(speciesID: 606, animated: true, shiny: shiny)
            try (data as Data).write(to: directory.appendingPathComponent(animatedKey + ".gif"))
        }
        let species = try XCTUnwrap(store.dexSpecies.first)
        let view = PokemonDetailView(store: store, species: species, onBack: {}, selectedShiny: false,
                                     spriteStore: SpriteStore(directory: directory))
            .frame(width: PopoverMetrics.contentWidth, height: 520)
            .background(Color.white)
            .environment(\.colorScheme, .light)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: PopoverMetrics.contentWidth, height: 520)
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000,
            width: PopoverMetrics.contentWidth, height: 520), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        for (step, shiny) in [false, true, false].enumerated() {
            host.layoutSubtreeIfNeeded()
            let segmented = try XCTUnwrap(descendants(host).compactMap { $0 as? NSSegmentedControl }.first)
            segmented.selectedSegment = shiny ? 1 : 0
            segmented.sendAction(segmented.action, to: segmented.target)
            let bitmap = try await waitForDetailSprite(host, shiny: shiny)
            XCTAssertGreaterThan(colorRows(bitmap, shiny: shiny).count, 40,
                                 "step \(step): selected \(shiny ? "shiny" : "normal") sprite must appear within 5 seconds")
            XCTAssertEqual(colorRows(bitmap, shiny: !shiny).count, 0,
                           "step \(step): selected \(shiny ? "shiny" : "normal") must not retain the previous appearance")
            let scale = CGFloat(bitmap.pixelsWide) / PopoverMetrics.contentWidth
            let header = try XCTUnwrap(bitmap.cgImage?.cropping(to:
                CGRect(x: 90 * scale, y: 58 * scale, width: 220 * scale, height: 85 * scale)))
            let recognition = VNRecognizeTextRequest()
            recognition.recognitionLevel = .accurate
            recognition.recognitionLanguages = ["en-US"]
            try VNImageRequestHandler(cgImage: header).perform([recognition])
            let text = recognition.results?.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ") ?? ""
            XCTAssertTrue(text.contains("Elgyem"), "header crop must contain the rendered identity: \(text)")
            XCTAssertEqual(text.contains("Shiny"), shiny, "badge must follow the displayed individual: \(text)")
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to:
                URL(fileURLWithPath: "/private/tmp/dex-color-detail-\(shiny ? "shiny" : "normal").png"))
        }
    }

    func testCatchLogRendersEachIndividualsColorInBothAcquisitionOrdersAndOnReentry() throws {
        try withSprites {
            for shinyLast in [false, true] {
                let (store, file) = try fixture(shinyLast: shinyLast)
                defer { try? FileManager.default.removeItem(at: file) }
                for visit in 0..<2 {
                    let navigation = PopoverNavigation()
                    navigation.showingCollectionLog = true
                    let view = CollectionView(store: store, navigation: navigation)
                        .frame(width: PopoverMetrics.contentWidth, height: 520)
                        .background(Color.white)
                        .environment(\.colorScheme, .light)
                        .environment(\.locale, store.language.displayLocale)
                    let host = NSHostingView(rootView: view)
                    host.frame = NSRect(x: 0, y: 0, width: PopoverMetrics.contentWidth, height: 520)
                    let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000,
                        width: PopoverMetrics.contentWidth, height: 520),
                        styleMask: .borderless, backing: .buffered, defer: false)
                    window.isReleasedWhenClosed = false
                    window.appearance = NSAppearance(named: .aqua)
                    window.contentView = host
                    window.orderFront(nil)
                    defer { window.close() }
                    host.layoutSubtreeIfNeeded()
                    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
                    host.layoutSubtreeIfNeeded()
                    let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to:
                        URL(fileURLWithPath: "/private/tmp/dex-color-log-shiny-last-\(shinyLast).png"))
                    let normalRows = colorRows(bitmap, shiny: false)
                    let shinyRows = colorRows(bitmap, shiny: true)
                    XCTAssertGreaterThan(normalRows.count, 20, "normal catch must retain normal pixels")
                    XCTAssertGreaterThan(shinyRows.count, 20, "shiny catch must retain shiny pixels")
                    let firstNormal = try XCTUnwrap(normalRows.first)
                    let firstShiny = try XCTUnwrap(shinyRows.first)
                    XCTAssertEqual(firstShiny < firstNormal, shinyLast, "newest catch is first; colors must follow its individual")
                    if visit == 0 {
                        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to:
                            URL(fileURLWithPath: "/private/tmp/dex-color-log-shiny-last-\(shinyLast).png"))
                    }
                }
            }
        }
    }
}
