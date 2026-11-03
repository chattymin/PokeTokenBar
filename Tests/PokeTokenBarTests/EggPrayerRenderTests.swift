import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

private struct PrayerRenderProvider: PokeProviding, PokemonDetailProviding {
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

/// Writes PNGs of the prayer UI when `PTB_PRAYER_RENDER_DIR` names an existing folder; skipped otherwise.
/// Sample data only: sprites come from an empty directory, so no network is used.
@MainActor
final class EggPrayerRenderTests: XCTestCase {
    private var windows: [NSWindow] = []

    override func tearDown() async throws {
        windows.forEach { $0.close() }
        windows = []
    }

    private func store(language: AppLanguage, prayers: PrayerRecord?, egg: Bool) async throws -> CompanionStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("prayer-render-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let suite = "PrayerRender-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        var state = CompanionState()
        state.language = language
        if egg {
            state.eggUsage = 1_000_000
            state.eggPrayers = prayers
        } else {
            state.dex = [DexEntry(id: "fixture", baseID: 46, finalID: 47, chainOrder: [46, 47], rarity: .common,
                                  caughtAt: Date(timeIntervalSince1970: 1_700_000_000),
                                  profile: PokemonProfile.generate(seed: 1, instanceID: "fixture"),
                                  names: [47: ["en": "Parasect", "ko": "파라섹트"]], prayers: prayers)]
        }
        let file = directory.appendingPathComponent("state.json")
        try JSONEncoder().encode(state).write(to: file)
        let store = CompanionStore(provider: PrayerRenderProvider(), fileURL: file, defaults: defaults)
        if !egg { await store.loadPokemonDetails(speciesID: 47) }
        return store
    }

    private func writePNG<V: View>(_ view: V, height: CGFloat, to url: URL, dark: Bool = false) async throws {
        let host = NSHostingView(rootView: view.frame(width: PopoverMetrics.contentWidth, height: height)
            .background(dark ? Color(white: 0.16) : Color.white)
            .environment(\.colorScheme, dark ? .dark : .light))
        host.frame = NSRect(x: 0, y: 0, width: PopoverMetrics.contentWidth, height: height)
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: host.frame.width, height: height),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        window.orderFront(nil)
        windows.append(window)
        try await Task.sleep(for: .milliseconds(150))
        host.layoutSubtreeIfNeeded()
        let bounds = host.bounds
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(bounds.width * 2), pixelsHigh: Int(bounds.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.size = bounds.size
        host.cacheDisplay(in: bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: url)
        XCTAssertGreaterThan(png.count, 1000)
    }

    func testWritePrayerScreens() async throws {
        guard let directory = ProcessInfo.processInfo.environment["PTB_PRAYER_RENDER_DIR"] else {
            throw XCTSkip("PTB_PRAYER_RENDER_DIR not set")
        }
        let output = URL(fileURLWithPath: directory)
        let prayed = PrayerRecord(count: 37, wasFutile: false, eggWasPurchased: false)
        let futile = PrayerRecord(count: 37, wasFutile: true, eggWasPurchased: true)
        for (language, tag) in [(AppLanguage.ko, "ko"), (.en, "en")] {
            for (record, name) in [(nil, "detail-no-prayers"), (prayed, "detail-37-prayers"),
                                   (futile, "detail-37-prayers-futile-purchased-egg")] as [(PrayerRecord?, String)] {
                let store = try await store(language: language, prayers: record, egg: false)
                let species = try XCTUnwrap(store.dexSpecies.first { $0.id == 47 })
                let spriteDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("prayer-sprites-\(UUID())")
                try FileManager.default.createDirectory(at: spriteDirectory, withIntermediateDirectories: true)
                addTeardownBlock { try? FileManager.default.removeItem(at: spriteDirectory) }
                let view = PokemonDetailView(store: store, species: species, onBack: {},
                                             spriteStore: SpriteStore(directory: spriteDirectory))
                try await writePNG(view, height: 520, to: output.appendingPathComponent("\(name)-\(tag).png"))
            }
        }
    }

    /// The floating egg with three 🙏 frozen mid-flight at fixed spots (the live ones use random x).
    func testWriteFloatingEggWithPrayers() async throws {
        guard let directory = ProcessInfo.processInfo.environment["PTB_PRAYER_RENDER_DIR"] else {
            throw XCTSkip("PTB_PRAYER_RENDER_DIR not set")
        }
        let petSize: CGFloat = 128
        let emoji = PrayerEmojiLayer.emojiSize(petSize: petSize)
        let egg = ZStack {
            SpriteView(speciesID: nil, size: petSize, animated: false, shiny: false)
                .frame(width: petSize, height: petSize)
            ForEach([(0.2, 0.3), (0.55, 0.55), (0.85, 0.8)], id: \.0) { fraction, progress in
                PrayerEmojiFrame(xFraction: fraction, petSize: petSize, emojiSize: emoji, progress: progress)
            }
        }
        .frame(width: petSize, height: petSize)
        for (dark, tag) in [(false, "light"), (true, "dark")] {
            try await writePNG(egg, height: 200,
                               to: URL(fileURLWithPath: directory).appendingPathComponent("floating-egg-3-prayer-emojis-\(tag).png"),
                               dark: dark)
        }
    }
}
