import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

/// The Pokédex detail page shows the evolution line of the selected individual.
@MainActor
final class DexDetailEvolutionLineTests: XCTestCase {
    func testFinishedIndividualShowsItsChainEndingOnThisPage() {
        XCTAssertEqual(PokemonDetailView.evolutionLineItems(chainOrder: [1, 2, 3], speciesID: 3, activeLine: nil), [
            EvoLineItem(.species(1), .done),
            EvoLineItem(.species(2), .done),
            EvoLineItem(.species(3), .current),
        ])
    }

    func testIndividualBeingRaisedShowsTheHomeLine() {
        let home = [EvoLineItem(.species(1), .done), EvoLineItem(.species(2), .current),
                    EvoLineItem(.species(3), .future)]
        XCTAssertEqual(PokemonDetailView.evolutionLineItems(chainOrder: [1, 2], speciesID: 2, activeLine: home), home)
    }

    func testIndividualBeingRaisedFallsBackToItsPathBeforeTheLineLoads() {
        XCTAssertEqual(PokemonDetailView.evolutionLineItems(chainOrder: [1, 2], speciesID: 2, activeLine: []), [
            EvoLineItem(.species(1), .done),
            EvoLineItem(.species(2), .current),
        ])
    }

    func testSingleStageLineIsHidden() {
        XCTAssertEqual(PokemonDetailView.evolutionLineItems(chainOrder: [144], speciesID: 144, activeLine: nil), [])
        XCTAssertEqual(PokemonDetailView.evolutionLineItems(
            chainOrder: [144], speciesID: 144, activeLine: [EvoLineItem(.species(144), .current)]), [])
    }

    // MARK: Whose line an earlier stage's page shows

    private func entry(_ id: String, _ chain: [Int], caughtAt: TimeInterval? = 1_700_000_000,
                       shiny: Bool = false, form: PokemonForm? = nil) -> DexEntry {
        DexEntry(id: id, baseID: chain[0], finalID: chain.last!, chainOrder: chain, rarity: .common,
                 caughtAt: caughtAt.map(Date.init(timeIntervalSince1970:)), isShiny: shiny, form: form)
    }

    private func source(_ entries: [DexEntry], selected: DexEntry? = nil, activeID: String? = nil,
                        speciesID: Int = 2, form: PokemonForm? = nil, shiny: Bool = false) -> String? {
        PokemonDetailView.evolutionSourceEntry(selected: selected, entries: entries, activeID: activeID,
                                               speciesID: speciesID, form: form, shiny: shiny)?.id
    }

    func testEarlierStagePageShowsTheLineOfAnIndividualThatPassedThrough() throws {
        let venusaur = entry("venusaur", [1, 2, 3])
        XCTAssertEqual(source([venusaur]), "venusaur")
        let shown = try XCTUnwrap(PokemonDetailView.evolutionSourceEntry(
            selected: nil, entries: [venusaur], activeID: nil, speciesID: 2, form: nil, shiny: false))
        XCTAssertEqual(PokemonDetailView.evolutionLineItems(chainOrder: shown.chainOrder, speciesID: 2, activeLine: nil), [
            EvoLineItem(.species(1), .done),
            EvoLineItem(.species(2), .current),
            EvoLineItem(.species(3), .done),
        ])
    }

    func testSelectedIndividualThatEvolvedWinsOverALongerLine() {
        let selected = entry("ivysaur", [1, 2])
        XCTAssertEqual(source([selected, entry("venusaur", [1, 2, 3], caughtAt: 1_800_000_000)],
                              selected: selected), "ivysaur")
    }

    func testIndividualReleasedBeforeEvolvingShowsALongerRecordedLine() throws {
        // Nidoran♂'s page: the only individual ending there was released at stage 1.
        let released = entry("released", [32], caughtAt: 1_800_000_000)
        let nidoking = entry("nidoking", [32, 33, 34], caughtAt: 1_600_000_000)
        XCTAssertEqual(source([released, nidoking], selected: released, speciesID: 32), "nidoking")
        let shown = try XCTUnwrap(PokemonDetailView.evolutionSourceEntry(
            selected: released, entries: [released, nidoking], activeID: nil, speciesID: 32, form: nil, shiny: false))
        XCTAssertEqual(PokemonDetailView.evolutionLineItems(chainOrder: shown.chainOrder, speciesID: 32, activeLine: nil), [
            EvoLineItem(.species(32), .current),
            EvoLineItem(.species(33), .done),
            EvoLineItem(.species(34), .done),
        ])
        // Nothing longer recorded: the single stage stays hidden.
        let legendary = entry("legendary", [144])
        let only = try XCTUnwrap(PokemonDetailView.evolutionSourceEntry(
            selected: legendary, entries: [legendary], activeID: nil, speciesID: 144, form: nil, shiny: false))
        XCTAssertEqual(PokemonDetailView.evolutionLineItems(chainOrder: only.chainOrder, speciesID: 144, activeLine: nil), [])
    }

    func testLongestLineWinsOverAMoreRecentShorterOne() {
        let ivysaur = entry("ivysaur", [1, 2], caughtAt: 1_800_000_000)
        let venusaur = entry("venusaur", [1, 2, 3], caughtAt: 1_600_000_000)
        XCTAssertEqual(source([ivysaur, venusaur], speciesID: 1), "venusaur")
        XCTAssertEqual(source([venusaur, ivysaur], speciesID: 1), "venusaur")
    }

    func testChoiceAmongSeveralEntriesIsDeterministic() {
        let old = entry("old", [1, 2, 3], caughtAt: 1_600_000_000)
        let new = entry("new", [1, 2, 3], caughtAt: 1_700_000_000)
        let raising = entry("raising", [1, 2], caughtAt: nil)
        // The individual being raised first, else (equal lengths) the most recent record, whatever the input order.
        XCTAssertEqual(source([old, new, raising], activeID: "raising"), "raising")
        XCTAssertEqual(source([old, new, raising]), "new")
        XCTAssertEqual(source([new, old]), "new")
        // Equal times fall back to the id.
        XCTAssertEqual(source([entry("a", [1, 2, 3]), entry("b", [1, 2, 3])]), "b")
        XCTAssertEqual(source([entry("b", [1, 2, 3]), entry("a", [1, 2, 3])]), "b")
    }

    func testOnlyEntriesInTheDisplayedAppearanceAndFormCount() {
        let normal = entry("normal", [1, 2, 3], caughtAt: 1_600_000_000)
        let shiny = entry("shiny", [1, 2, 3], caughtAt: 1_700_000_000, shiny: true)
        XCTAssertEqual(source([normal, shiny], shiny: false), "normal")
        XCTAssertEqual(source([normal, shiny], shiny: true), "shiny")
        let plant = entry("plant", [412, 413], caughtAt: 1_800_000_000, form: PokemonForm("plant"))
        let sandy = entry("sandy", [412, 413], form: PokemonForm("sandy"))
        XCTAssertEqual(source([plant, sandy], speciesID: 412, form: PokemonForm("sandy")), "sandy")
    }

    func testNoEntryThroughThisSpeciesHidesTheLine() {
        XCTAssertNil(source([entry("charizard", [4, 5, 6])]))
        XCTAssertNil(source([]))
    }

    // MARK: Links

    func testLinksSkipThisPageAndNeedACallback() {
        let links = [1: "c1", 2: "c2", 3: "c3"]
        XCTAssertEqual(PokemonDetailView.evolutionDexLinks(links, pageSpeciesID: 2, canOpen: true), [1: "c1", 3: "c3"])
        XCTAssertEqual(PokemonDetailView.evolutionDexLinks(links, pageSpeciesID: 2, canOpen: false), [:])
    }
}

private struct EvolutionRenderProvider: PokeProviding, PokemonDetailProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: 1, tree: EvoNode(speciesID: 1, children: [
            EvoNode(speciesID: 2, children: [EvoNode(speciesID: 3, children: [])]),
        ]), rarity: .common, names: [1: ["en": "Bulbasaur"], 2: ["en": "Ivysaur"], 3: ["en": "Venusaur"]])
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
    func pokemonDetails(speciesID: Int) async throws -> PokemonDetails {
        PokemonDetails(speciesID: speciesID, name: "fixture", height: 10, weight: 130,
            baseExperience: 142, genderRate: 1, types: ["grass", "poison"],
            baseStats: ["hp": 60, "attack": 62, "defense": 63, "special-attack": 80, "special-defense": 80, "speed": 60],
            abilities: [PokemonAbilityOption(name: "overgrow", slot: 1, isHidden: false)], moves: [])
    }
}

/// Opt-in sample-data renders of the detail page for PR evidence. Temporary saves and a temporary
/// sprite cache only — never the user's collection or sprite cache.
@MainActor
final class DexDetailEvolutionLineRenderingTests: XCTestCase {
    func testRenderDetailPageEvolutionLine() async throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_DEX_EVOLUTION_RENDER_DIR"] else {
            throw XCTSkip("Set PTB_DEX_EVOLUTION_RENDER_DIR to render the Pokédex detail evolution line")
        }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("dex-evolution-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let sprites = SpriteStore(directory: dir)

        // A finished Venusaur that went through the whole line.
        var finished = CompanionState()
        finished.language = .en
        finished.dex = [DexEntry(id: "fixture-finished", baseID: 1, finalID: 3, chainOrder: [1, 2, 3], rarity: .common,
            caughtAt: Date(timeIntervalSince1970: 1_700_000_000), nature: .modest,
            profile: PokemonProfile.generate(seed: 3, instanceID: "fixture-finished"),
            names: [1: ["en": "Bulbasaur"], 2: ["en": "Ivysaur"], 3: ["en": "Venusaur"]])]
        let finishedFile = dir.appendingPathComponent("finished.json")
        try JSONEncoder().encode(finished).write(to: finishedFile)
        let finishedStore = CompanionStore(provider: EvolutionRenderProvider(), fileURL: finishedFile)
        try await render(finishedStore, speciesID: 3, sprites: sprites, to: output, name: "finished")
        // Ivysaur's page when only that Venusaur is owned: no individual ends on Ivysaur.
        try await render(finishedStore, speciesID: 2, sprites: sprites, to: output, name: "earlier-stage")

        // Bulbasaur's page when its only individual was released before evolving, next to that Venusaur.
        var released = finished
        let releasedAt = Date(timeIntervalSince1970: 1_700_100_000)
        released.dex.append(DexEntry(id: "fixture-released", baseID: 1, finalID: 1, chainOrder: [1], rarity: .common,
            caughtAt: releasedAt, nature: .bold,
            profile: PokemonProfile.generate(seed: 5, instanceID: "fixture-released"),
            names: [1: ["en": "Bulbasaur"]], releasedAt: releasedAt))
        let releasedFile = dir.appendingPathComponent("released.json")
        try JSONEncoder().encode(released).write(to: releasedFile)
        let releasedStore = CompanionStore(provider: EvolutionRenderProvider(), fileURL: releasedFile)
        try await render(releasedStore, speciesID: 1, sprites: sprites, to: output, name: "released-first-stage")

        // An Ivysaur being raised, one evolution away from Venusaur.
        var raising = CompanionState()
        raising.language = .en
        let raisingFile = dir.appendingPathComponent("raising.json")
        try JSONEncoder().encode(raising).write(to: raisingFile)
        let raisingStore = CompanionStore(provider: EvolutionRenderProvider(), fileURL: raisingFile,
                                          rng: SeededRNG(seed: 7))
        await raisingStore.hatch(baseID: 1)
        raisingStore.applyUsage(PokemonBalance.phaseThreshold(rarity: .common, totalForms: 3, stageIndex: 0))
        XCTAssertEqual(raisingStore.state.active?.currentID, 2)
        try await render(raisingStore, speciesID: 2, sprites: sprites, to: output, name: "raising")
    }

    private func render(_ store: CompanionStore, speciesID: Int, sprites: SpriteStore,
                        to output: String, name: String) async throws {
        await store.loadPokemonDetails(speciesID: speciesID)
        let species = try XCTUnwrap(store.dexSpecies.first { $0.id == speciesID })
        let size = NSSize(width: PopoverMetrics.contentWidth, height: 560)
        let view = PokemonDetailView(store: store, species: species, onBack: {}, spriteStore: sprites)
            .frame(width: size.width, height: size.height)
            .background(Color.white).environment(\.colorScheme, .light)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: size)
        // Borderless and far off-screen: never visible, never key, never takes focus.
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -10000, y: -10000), size: size),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        window.orderFront(nil)
        // Sprites load from the network into the temporary cache.
        try await Task.sleep(for: .seconds(3))
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            .write(to: URL(fileURLWithPath: output).appendingPathComponent("\(name).png"))
    }
}
