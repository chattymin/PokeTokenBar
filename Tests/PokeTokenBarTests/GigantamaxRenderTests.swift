import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

private let renderNames: [Int: [String: String]] = [
    4: ["en": "Charmander"], 5: ["en": "Charmeleon"], 6: ["en": "Charizard"],
    172: ["en": "Pichu"], 25: ["en": "Pikachu"], 16: ["en": "Pidgey"],
]

private struct GigantamaxRenderProvider: PokeProviding, PokemonDetailProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        let tree: EvoNode
        switch baseSpeciesID {
        case 4: tree = EvoNode(speciesID: 4, children: [EvoNode(speciesID: 5, children: [EvoNode(speciesID: 6, children: [])])])
        case 172: tree = EvoNode(speciesID: 172, children: [EvoNode(speciesID: 25, children: [])])
        default: tree = EvoNode(speciesID: baseSpeciesID, children: [])
        }
        return EvoLine(baseID: baseSpeciesID, tree: tree, rarity: .common, names: renderNames)
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
    func pokemonDetails(speciesID: Int) async throws -> PokemonDetails {
        // Charizard's default-form data; the Gigantamax form deliberately keeps it.
        PokemonDetails(speciesID: speciesID, name: "charizard", height: 17, weight: 905,
            baseExperience: 267, genderRate: 1, types: ["fire", "flying"],
            baseStats: ["hp": 78, "attack": 84, "defense": 78, "special-attack": 109,
                        "special-defense": 85, "speed": 100],
            abilities: [PokemonAbilityOption(name: "blaze", slot: 1, isHidden: false)], moves: [])
    }
}

/// Opt-in sample-data renders of the Gigantamax screens for PR evidence. The same file runs on the
/// commit before Gigantamax (forms resolve to the single look there) and after it. Temporary saves,
/// defaults and sprite caches only — never the user's collection or sprite cache.
@MainActor
final class GigantamaxRenderTests: XCTestCase {
    private let caughtAt = Date(timeIntervalSince1970: 1_700_000_000)
    private let normal = PokemonForm("normal"), gmax = PokemonForm("gmax")

    func testRenderGigantamaxScreens() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_GIGANTAMAX_RENDER_DIR"] else {
            throw XCTSkip("Set PTB_GIGANTAMAX_RENDER_DIR to render the Gigantamax screens")
        }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gigantamax-render-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let sprites = SpriteStore(directory: dir.appendingPathComponent("sprites"))

        // Grid: a shiny usual Charizard, a usual and a Gigantamax Pikachu, and a single-look Pidgey.
        var collection = CompanionState()
        collection.language = .en
        collection.dex = [
            entry("charizard", [4, 5, 6], shiny: true, form: normal),
            entry("pikachu", [172, 25], form: normal),
            entry("pikachu-gmax", [172, 25], form: gmax),
            entry("pidgey", [16]),
        ]
        let collectionStore = try store(collection, in: dir, name: "collection")
        try await withGridSprites([4, 5, 6, 172, 25, 16], loadedFrom: sprites) {
            let navigation = PopoverNavigation()
            navigation.showingCollectionLog = false
            try await render(CollectionView(store: collectionStore, navigation: navigation),
                             height: 520, to: output, name: "grid")
        }

        // Detail: Charizard owned as a shiny usual look and as Gigantamax, Gigantamax selected.
        var detail = CompanionState()
        detail.language = .en
        detail.dex = [entry("charizard", [4, 5, 6], shiny: true, form: normal),
                      entry("charizard-gmax", [4, 5, 6], form: gmax)]
        detail.representativeSpeciesID = 6
        detail.representativeForm = gmax
        let detailStore = try store(detail, in: dir, name: "detail")
        await detailStore.loadPokemonDetails(speciesID: 6)
        let species = try XCTUnwrap(detailStore.formSpecies(speciesID: 6).first { $0.form == gmax }
            ?? detailStore.dexSpecies.first { $0.id == 6 })
        try await render(PokemonDetailView(store: detailStore, species: species, onBack: {}, spriteStore: sprites),
                         height: 560, to: output, name: "detail")

        // Home: a Gigantamax Charizard being raised.
        var home = CompanionState()
        home.language = .en
        home.active = MonState(baseID: 4, pathIDs: [4, 5, 6], plannedPathIDs: [4, 5, 6], stageIndex: 2,
                               usedAtStage: 0, rarity: .common, totalForms: 3, nature: .modest, form: gmax)
        let homeStore = try store(home, in: dir, name: "home")
        homeStore.update(todayTokensByProvider: ["sample": 0], todayDate: "d1", monthTotal: 0,
                         burnTier: .idle, limitWarning: false, hasUsageData: true)
        for _ in 0..<100 where homeStore.currentLine == nil { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertNotNil(homeStore.currentLine, "the line names the title")
        await homeStore.loadPokemonDetails(speciesID: 6)
        try await render(CompanionHeader(store: homeStore, spriteStore: sprites).padding(12),
                         height: 240, to: output, name: "home")
    }

    private func entry(_ id: String, _ chain: [Int], shiny: Bool = false, form: PokemonForm? = nil) -> DexEntry {
        DexEntry(id: "fixture-\(id)", baseID: chain[0], finalID: chain.last!, chainOrder: chain, rarity: .common,
                 caughtAt: caughtAt, isShiny: shiny, nature: .modest,
                 profile: PokemonProfile.generate(seed: 6, instanceID: "fixture-\(id)"),
                 names: renderNames.filter { chain.contains($0.key) }, form: form)
    }

    private func store(_ state: CompanionState, in dir: URL, name: String) throws -> CompanionStore {
        let file = dir.appendingPathComponent("\(name).json")
        try JSONEncoder().encode(state).write(to: file)
        let suite = "gigantamax-render-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suite) }
        return CompanionStore(provider: GigantamaxRenderProvider(), detailProvider: GigantamaxRenderProvider(),
                              fileURL: file, rng: SeededRNG(seed: 6), defaults: defaults)
    }

    /// The grid cells use the shared sprite store. Their static PNGs are fetched into the temporary
    /// store and placed in the in-memory image cache under the shared keys, so the grid never reads
    /// or writes the user's sprite cache; the previous cache entries are restored afterwards.
    private func withGridSprites(_ ids: [Int], loadedFrom sprites: SpriteStore,
                                 _ body: () async throws -> Void) async throws {
        var previous: [(NSString, NSImage?)] = []
        for id in ids {
            for shiny in [false, true] {
                let fetched = await sprites.data(speciesID: id, animated: false, shiny: shiny)
                let data = try XCTUnwrap(fetched, "#\(id) shiny=\(shiny) did not download")
                let key = SpriteLoader.cacheDir.appendingPathComponent(
                    SpriteStore.cacheKey(speciesID: id, animated: false, shiny: shiny) + ".png").path as NSString
                previous.append((key, SpriteLoader.imageCache.object(forKey: key)))
                SpriteLoader.imageCache.setObject(try XCTUnwrap(NSImage(data: data)), forKey: key)
            }
        }
        defer {
            for (key, image) in previous {
                if let image { SpriteLoader.imageCache.setObject(image, forKey: key) }
                else { SpriteLoader.imageCache.removeObject(forKey: key) }
            }
        }
        try await body()
    }

    private func render<V: View>(_ view: V, height: CGFloat, to output: String, name: String) async throws {
        let size = NSSize(width: PopoverMetrics.contentWidth, height: height)
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height)
            .background(Color.white).environment(\.colorScheme, .light)
            .environment(\.locale, Locale(identifier: "en")))
        host.frame = NSRect(origin: .zero, size: size)
        // Borderless and far off-screen: never visible, never key, never takes focus.
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -10000, y: -10000), size: size),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        window.orderFront(nil)
        // Sprites (Showdown GIFs are up to 0.85 MB) load from the network into the temporary cache.
        try await Task.sleep(for: .seconds(8))
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            .write(to: URL(fileURLWithPath: output).appendingPathComponent("\(name).png"))
    }
}
