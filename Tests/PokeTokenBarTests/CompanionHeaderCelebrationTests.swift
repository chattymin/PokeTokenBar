import AppKit
import SwiftUI
import Vision
import XCTest
@testable import PokeTokenBar

/// Base 1 = a common 3-form line (the disguise), 132 = Ditto's line, so a seeded disguise can reveal.
private struct HeaderDittoProvider: PokeProviding {
    private static func line(_ ids: [Int], rarity: Rarity) -> EvoLine {
        func node(_ rest: ArraySlice<Int>) -> EvoNode {
            EvoNode(speciesID: rest.first!, children: rest.count > 1 ? [node(rest.dropFirst())] : [])
        }
        return EvoLine(baseID: ids[0], tree: node(ids[...]), rarity: rarity,
                       names: Dictionary(uniqueKeysWithValues: ids.map { ($0, ["en": "P\($0)"]) }))
    }
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        baseSpeciesID == PokemonOdds.dittoSpeciesID ? Self.line([132], rarity: .rare) : Self.line([1, 2, 3], rarity: .common)
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [BaseSpecies(id: 1, captureRate: 255)] }
}

/// The popover header's side of the celebrations: status text, navigation back to Home, the evolve
/// sequence on the sprite, and the egg incubation tiers. Sample data only: species 1 and 2 are renamed
/// Alpha/Beta and drawn as synthetic discs pre-written to a temporary `SpriteStore` directory (no network).
///
/// Set `PTB_HEADER_CELEBRATION_RENDER_DIR` to an existing folder to keep the rendered PNGs.
@MainActor
final class CompanionHeaderCelebrationTests: XCTestCase {
    private static let sourceID = 1
    private static let targetID = 2
    private var windows: [NSWindow] = []

    override func tearDown() async throws {
        windows.forEach { $0.close() }
        windows = []
    }

    // MARK: Pure helpers

    func testStatusTextPrefersCelebration() {
        XCTAssertEqual(CompanionHeader.statusText(celebration: "Huh? Alpha is evolving!", fallback: "Sleeping"),
                       "Huh? Alpha is evolving!")
        XCTAssertEqual(CompanionHeader.statusText(celebration: nil, fallback: "Sleeping"), "Sleeping")
    }

    func testHomeForCelebrationLeavesTabsOnly() {
        let nav = PopoverNavigation()
        for tab in [PopoverTab.shop, .bag, .collection] {
            nav.tab = tab
            PopoverNavigation.homeForCelebration(nav)
            XCTAssertEqual(nav.tab, .home, "\(tab)")
        }
        // An open Pokédex page is dropped with the Collection tab.
        nav.openDexEntry(collectionID: "fixture")
        PopoverNavigation.homeForCelebration(nav)
        XCTAssertEqual(nav.tab, .home)
        XCTAssertNil(nav.dexDetailCollectionID)

        // Settings and the Recap may hold a draft: they stay, and the item waits for Home.
        nav.tab = .bag
        nav.showSettings = true
        PopoverNavigation.homeForCelebration(nav)
        XCTAssertTrue(nav.showSettings, "Settings stays open")
        XCTAssertEqual(nav.tab, .bag)
        nav.showSettings = false
        nav.showingRecap = true
        PopoverNavigation.homeForCelebration(nav)
        XCTAssertTrue(nav.showingRecap, "the Recap stays open")
        XCTAssertEqual(nav.tab, .bag)
    }

    /// The header's side of `CelebrationPresentation` (its rule is in `CelebrationPresentationTests`): the
    /// timeline's own text switch is the reveal boundary (8.0 s evolve, 6.4 s hatch).
    func testPresentationBoundaryIsTheTimelinesTextSwitch() {
        let from = CelebrationSubject(speciesID: 1, form: nil, isShiny: true, name: "Alpha")
        let to = CelebrationSubject(speciesID: 2, form: nil, isShiny: true, name: "Beta")
        var queue = CelebrationQueue()
        queue.enqueue(.evolve(from: from, to: to), deferred: nil)
        queue.enqueue(.hatch(to: to), deferred: nil)
        func shown(_ index: Int, _ text: CelebrationText) -> CelebrationPresentation? {
            CelebrationPresentation.shown(queue: queue, playing: queue.items[index], text: text, surface: .popover,
                                          liveSpeciesID: 2)
        }
        let evolveTimeline = CelebrationTimeline(kind: .evolve, reduced: false, shiny: false)
        XCTAssertEqual(shown(0, evolveTimeline.frame(at: 7.99).text), .subject(from))
        XCTAssertEqual(shown(0, evolveTimeline.frame(at: 8.0).text), .subject(to), "a later item still waits")
        let hatchTimeline = CelebrationTimeline(kind: .hatch, reduced: false, shiny: false)
        XCTAssertEqual(shown(1, hatchTimeline.frame(at: 6.39).text), .egg)
        XCTAssertNil(shown(1, hatchTimeline.frame(at: 6.4).text), "the last reveal: the live state")
    }

    func testGraduationLineWaitsForPendingSequences() {
        XCTAssertEqual(CompanionHeader.graduationLine("Gamma", sequencesPending: false), "Gamma")
        XCTAssertNil(CompanionHeader.graduationLine("Gamma", sequencesPending: true),
                     "a catch-up of the graduated companion plays first")
        XCTAssertNil(CompanionHeader.graduationLine(nil, sequencesPending: false))
    }

    /// One rule on both surfaces: Reduce Motion or Low Power, each alone, means the short version and no wobble.
    func testMotionIsReducedByReduceMotionOrLowPower() {
        XCTAssertFalse(MotionSettings(reduceMotion: false, lowPower: false).reduced)
        XCTAssertTrue(MotionSettings(reduceMotion: true, lowPower: false).reduced, "Reduce Motion alone")
        XCTAssertTrue(MotionSettings(reduceMotion: false, lowPower: true).reduced, "Low Power alone")
        XCTAssertEqual(MotionSettings.system, MotionSettings(
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled))
    }

    func testEggWobbleIntervalFollowsTierAndMotion() {
        let full = MotionSettings(), lowPower = MotionSettings(lowPower: true), reduce = MotionSettings(reduceMotion: true)
        XCTAssertNil(CompanionHeader.eggWobbleInterval(isEgg: true, progress: 0.1, motion: full))
        XCTAssertEqual(CompanionHeader.eggWobbleInterval(isEgg: true, progress: 0.5, motion: full), .seconds(20))
        XCTAssertEqual(CompanionHeader.eggWobbleInterval(isEgg: true, progress: 0.75, motion: full), .seconds(8))
        XCTAssertEqual(CompanionHeader.eggWobbleInterval(isEgg: true, progress: 0.95, motion: full), .seconds(3))
        XCTAssertNil(CompanionHeader.eggWobbleInterval(isEgg: true, progress: 0.95, motion: reduce), "Reduce Motion")
        XCTAssertNil(CompanionHeader.eggWobbleInterval(isEgg: true, progress: 0.95, motion: lowPower), "Low Power")
        XCTAssertNil(CompanionHeader.eggWobbleInterval(isEgg: false, progress: 0.95, motion: full))
    }

    /// The popover's player follows the same rule: under Low Power alone it plays the short cross-fade.
    func testPopoverPlaysTheShortVersionUnderLowPower() async throws {
        for (name, motion, short) in [("low power", MotionSettings(lowPower: true), true),
                                      ("reduce motion", MotionSettings(reduceMotion: true), true),
                                      ("full", MotionSettings(), false)] {
            let store = try await evolvingStore()
            let player = CelebrationPlayer(sleep: { _ in try await Task.sleep(for: .seconds(3600)) })
            defer { player.cancel() }
            _ = mount(CompanionHeader(store: store, spriteStore: try spriteStore(), celebrationPlayer: player,
                                      motion: { motion }), height: 170, dark: false)
            try await waitUntil { player.item != nil }
            XCTAssertEqual(player.timeline?.reduced, short, name)
        }
    }

    func testWobbleLoopWobblesOncePerIntervalUntilCancelled() async {
        var slept: [Duration] = []
        var wobbles = 0
        await EggIncubationTier.wobbleLoop(every: .seconds(8), sleep: { interval in
            if slept.count == 3 { throw CancellationError() }
            slept.append(interval)
        }, wobble: { wobbles += 1 })
        XCTAssertEqual(slept, [.seconds(8), .seconds(8), .seconds(8)])
        XCTAssertEqual(wobbles, 3, "one wobble per completed pause, none after cancellation")
    }

    // MARK: Fixtures

    private func temporaryDirectory(_ prefix: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("\(prefix)-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func defaults() throws -> UserDefaults {
        let suite = "HeaderCelebration-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    /// A 96×96 transparent canvas with a centred opaque disc, like a static PokéAPI sprite.
    private func disc(_ color: NSColor) throws -> Data {
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 96, pixelsHigh: 96, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: 96, height: 96).fill()
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: 16, y: 16, width: 64, height: 64)).fill()
        NSGraphicsContext.restoreGraphicsState()
        return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    }

    private func spriteStore() throws -> SpriteStore {
        let directory = try temporaryDirectory("header-celebration-sprites")
        for (id, color) in [(Self.sourceID, NSColor.systemRed), (Self.targetID, NSColor.systemGreen)] {
            for shiny in [false, true] {
                // The disc also stands in for the animated GIF (image decoding reads the bytes, not the name).
                for animated in [false, true] {
                    let key = SpriteStore.cacheKey(speciesID: id, animated: animated, shiny: shiny)
                    try disc(color).write(to: directory.appendingPathComponent(key + (animated ? ".gif" : ".png")))
                }
            }
        }
        return SpriteStore(directory: directory)
    }

    /// An active "Alpha" with an evolve to "Beta" queued for the popover (the hatch already played).
    private func evolvingStore(finishHatch: Bool = true, evolve: Bool = true) async throws -> CompanionStore {
        let names = [Self.sourceID: ["en": "Alpha"], Self.targetID: ["en": "Beta"]]
        let line = EvoLine(baseID: Self.sourceID,
                           tree: EvoNode(speciesID: Self.sourceID, children: [EvoNode(speciesID: Self.targetID, children: [])]),
                           rarity: .common, names: names)
        let file = try temporaryDirectory("header-celebration-state").appendingPathComponent("state.json")
        let store = CompanionStore(provider: StubProvider(value: line), fileURL: file, rng: SeededRNG(seed: 3),
                                   defaults: try defaults())
        store.setLanguage(.en)
        store.popoverOpen = true
        await store.hatch(baseID: Self.sourceID)
        if finishHatch { store.celebrations.items.forEach { store.finishCelebration(id: $0.id) } }
        if evolve { store.applyUsage(store.threshold) }
        return store
    }

    /// An egg at `progress` of its hatch threshold.
    private func eggStore(progress: Double) throws -> CompanionStore {
        var state = CompanionState()
        state.language = .en
        state.eggUsage = Int(Double(PokemonBalance.eggHatchThreshold) * progress)
        let file = try temporaryDirectory("header-egg-state").appendingPathComponent("state.json")
        try JSONEncoder().encode(state).write(to: file)
        return CompanionStore(provider: StubProvider(value: EvoLine(
            baseID: Self.sourceID, tree: EvoNode(speciesID: Self.sourceID, children: []), rarity: .common, names: [:])),
                              fileURL: file, defaults: try defaults())
    }

    // MARK: Hosting

    private func mount<V: View>(_ view: V, height: CGFloat, dark: Bool) -> NSView {
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
        return host
    }

    private func bitmap(_ host: NSView) throws -> NSBitmapImageRep {
        host.layoutSubtreeIfNeeded()
        let bounds = host.bounds
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(bounds.width * 2), pixelsHigh: Int(bounds.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = bounds.size
        host.cacheDisplay(in: bounds, to: rep)
        return rep
    }

    private func text(in rep: NSBitmapImageRep) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        try VNImageRequestHandler(cgImage: XCTUnwrap(rep.cgImage)).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
    }

    private func keep(_ rep: NSBitmapImageRep, as name: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["PTB_HEADER_CELEBRATION_RENDER_DIR"] else { return }
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name))
    }

    /// Near-white and clearly blue pixels in the 76 pt sprite column (the name column starts after it).
    private func spriteColumn(_ rep: NSBitmapImageRep) -> (white: Int, blue: Int) {
        var white = 0, blue = 0
        for y in 0..<rep.pixelsHigh {
            for x in 0..<(76 * 2) {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                if min(c.redComponent, c.greenComponent, c.blueComponent) > 0.92 { white += 1 }
                if c.blueComponent - c.redComponent > 60.0 / 255 { blue += 1 }
            }
        }
        return (white, blue)
    }

    // MARK: Rendered header

    /// `ImageRenderer`, not `cacheDisplay`: the latter drops the `brightness` filter that whitens the sprite.
    private func renderImage<V: View>(_ view: V, width: CGFloat = PopoverMetrics.contentWidth, height: CGFloat,
                                      dark: Bool) throws -> NSBitmapImageRep {
        let renderer = ImageRenderer(content: view
            .frame(width: width, height: height, alignment: .topLeading)
            .background(dark ? Color(white: 0.16) : Color.white)
            .environment(\.colorScheme, dark ? .dark : .light))
        renderer.scale = 2
        let png = try XCTUnwrap(NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.cgImage))
            .representation(using: .png, properties: [:]))
        return try XCTUnwrap(NSBitmapImageRep(data: png))
    }

    /// The header under a drawn stand-in of the popover's tab picker (an illustration: the real picker is
    /// an AppKit control `ImageRenderer` cannot draw), padded like the popover.
    private func popoverIllustration<V: View>(_ header: V) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 0) {
                ForEach(["Home", "Shop", "Bag", "Collection"], id: \.self) { tab in
                    Text(tab).font(.system(size: 12))
                        .frame(maxWidth: .infinity, minHeight: 22)
                        .background(tab == "Home" ? Color.gray.opacity(0.35) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 5))
                }
            }
            .padding(2)
            .background(Color.gray.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
            header
        }
        .padding(PopoverMetrics.padding)
        .frame(width: PopoverMetrics.width, alignment: .topLeading)
    }

    func testEvolveAtFiveSecondsShowsWhiteSilhouetteAndAnnounceText() async throws {
        let store = try await evolvingStore()
        let item = try XCTUnwrap(store.celebrations.next(for: .popover))
        guard case .evolve(let from, _) = item.kind else { return XCTFail("expected an evolve, got \(item.kind)") }
        let sprites = try spriteStore()
        let player = CelebrationPlayer(sleep: { _ in try await Task.sleep(for: .seconds(3600)) })
        defer { player.cancel() }
        player.play(item, now: Date().addingTimeInterval(-5), onFinish: { _ in })

        let header = CompanionHeader(store: store, spriteStore: sprites, celebrationPlayer: player)
            .celebrationStageHost()
        let rep = try renderImage(header, height: 170, dark: true)
        for dark in [true, false] {
            // A finished `ImageRenderer` can deliver the header's onDisappear (cancel): restart at t = 5.
            player.play(item, now: Date().addingTimeInterval(-5), onFinish: { _ in })
            try keep(try renderImage(popoverIllustration(header), width: PopoverMetrics.width, height: 200, dark: dark),
                     as: "header-evolve-5s-\(dark ? "dark" : "light").png")
        }

        let column = spriteColumn(rep)
        XCTAssertGreaterThan(column.white, 1_500, "white silhouette expected in the sprite slot")
        XCTAssertGreaterThan(column.blue, 100, "blue glow expected around the silhouette")
        let rendered = try text(in: rep)
        XCTAssertTrue(rendered.contains(store.l.celebrationEvolveAnnounce(from.name)), "status line: \(rendered)")
        XCTAssertTrue(rendered.contains("Alpha"), "name shows the source until evolveDone: \(rendered)")
        XCTAssertFalse(rendered.contains("Beta"), "target name hidden until evolveDone: \(rendered)")
        XCTAssertFalse(rendered.contains(store.l.finalForm), "no target stage line before evolveDone: \(rendered)")
        XCTAssertFalse(rendered.lowercased().contains("graduation"), "no target progress copy: \(rendered)")

        // After the reveal caption the column switches to the live (target) state.
        player.play(item, now: Date().addingTimeInterval(-8.5), onFinish: { _ in })
        XCTAssertEqual(player.text, .evolveDone)
        let revealed = try text(in: try renderImage(header, height: 170, dark: true))
        XCTAssertTrue(revealed.contains("Beta"), revealed)
        XCTAssertTrue(revealed.contains(store.l.finalForm), revealed)

        // At rest (sequence done, queue empty): no silhouette, the target's name, the normal status line.
        player.cancel()
        store.celebrations.items.forEach { store.finishCelebration(id: $0.id) }
        let resting = try renderImage(header, height: 170, dark: true)
        XCTAssertNil(player.item)
        XCTAssertLessThan(spriteColumn(resting).white, 200)
        let restingText = try text(in: resting)
        XCTAssertFalse(restingText.contains("evolving"), restingText)
        XCTAssertTrue(restingText.contains("Beta"), restingText)
    }

    func testHatchShowsTheEggLayoutUntilHatchDone() async throws {
        let store = try await evolvingStore(finishHatch: false, evolve: false)
        let item = try XCTUnwrap(store.celebrations.next(for: .popover))
        guard case .hatch = item.kind else { return XCTFail("expected a hatch, got \(item.kind)") }
        let player = CelebrationPlayer(sleep: { _ in try await Task.sleep(for: .seconds(3600)) })
        defer { player.cancel() }
        player.play(item, now: Date().addingTimeInterval(-3), onFinish: { _ in })
        let header = CompanionHeader(store: store, spriteStore: try spriteStore(), celebrationPlayer: player)
            .celebrationStageHost()
        let shakingImage = try renderImage(header, height: 170, dark: false)
        var red = 0   // Alpha's disc only appears in the evolution line under the header
        for y in 0..<shakingImage.pixelsHigh {
            for x in 0..<shakingImage.pixelsWide {
                guard let c = shakingImage.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                if c.redComponent > 0.8, c.greenComponent < 0.4, c.blueComponent < 0.4 { red += 1 }
            }
        }
        XCTAssertLessThan(red, 20, "no evolution line (the hatched species) before hatchDone")
        let shaking = try text(in: shakingImage)
        XCTAssertTrue(shaking.contains(CompanionStore.eggName), shaking)
        XCTAssertTrue(shaking.contains(store.l.eggTierImminent), shaking)
        XCTAssertFalse(shaking.contains("Alpha"), "no hatched name before hatchDone: \(shaking)")
        XCTAssertFalse(shaking.uppercased().contains("COMMON"), "no species badge before hatchDone: \(shaking)")

        player.play(item, now: Date().addingTimeInterval(-7), onFinish: { _ in })
        XCTAssertEqual(player.text, .hatchDone)
        let hatched = try text(in: try renderImage(header, height: 170, dark: false))
        XCTAssertTrue(hatched.contains("Alpha"), hatched)
        XCTAssertFalse(hatched.contains(CompanionStore.eggName), hatched)
    }

    /// Hatch then its carry-over evolve: the store is already at Beta while the hatch plays. Neither the
    /// reveal of the hatch nor the moment between the two items may show Beta.
    func testChainedItemsNeverShowTheLiveEndOfTheChain() async throws {
        let store = try await evolvingStore(finishHatch: false)
        let items = store.celebrations.items
        XCTAssertEqual(items.count, 2, "hatch then evolve")
        XCTAssertEqual(store.displayName, "Beta", "the live state is the end of the chain")
        let player = CelebrationPlayer(sleep: { _ in try await Task.sleep(for: .seconds(3600)) })
        defer { player.cancel() }
        let header = CompanionHeader(store: store, spriteStore: try spriteStore(), celebrationPlayer: player)
            .celebrationStageHost()

        player.play(items[0], now: Date().addingTimeInterval(-7), onFinish: { _ in })
        XCTAssertEqual(player.text, .hatchDone)
        let hatched = try text(in: try renderImage(header, height: 170, dark: false))
        XCTAssertTrue(hatched.contains("Alpha"), "the hatched form is named at hatchDone: \(hatched)")
        XCTAssertFalse(hatched.contains("Beta"), "its evolve has not played yet: \(hatched)")

        // Between the items nothing plays: the resting sprite and name stay on Alpha (red disc), not Beta (green).
        // Rendering would start the next item at once (onAppear), so the popover is made not to own the queue
        // here: the same "nothing playing, an item pending" branch, held still long enough to look at.
        player.cancel()
        store.finishCelebration(id: items[0].id)
        store.popoverOpen = false
        let between = try renderImage(header, height: 170, dark: false)
        XCTAssertNil(player.item, "nothing plays while the popover does not own the queue")
        var red = 0, green = 0
        for y in 0..<between.pixelsHigh {
            for x in 0..<(76 * 2) {
                guard let c = between.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                if c.redComponent > 0.8, c.greenComponent < 0.4, c.blueComponent < 0.4 { red += 1 }
                if c.greenComponent > 0.6, c.redComponent < 0.4, c.blueComponent < 0.5 { green += 1 }
            }
        }
        XCTAssertGreaterThan(red, 1_000, "Alpha's disc in the sprite slot")
        XCTAssertLessThan(green, 50, "no Beta before its evolve plays")
        let betweenText = try text(in: between)
        XCTAssertTrue(betweenText.contains("Alpha"), betweenText)
        XCTAssertFalse(betweenText.contains("Beta"), "nor in the level-up status line: \(betweenText)")
    }

    /// Blue-tinted pixels in a band of the host, in points (`top..<bottom`, `left..<right`).
    private func bluePixels(_ rep: NSBitmapImageRep, top: CGFloat, bottom: CGFloat, left: CGFloat, right: CGFloat) -> Int {
        var count = 0
        for y in Int(top * 2)..<Int(bottom * 2) {
            for x in Int(left * 2)..<Int(right * 2) {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                if c.blueComponent - c.redComponent > 10.0 / 255 { count += 1 }
            }
        }
        return count
    }

    /// The top of the (single or tallest) NSScrollView, in the host's top-left coordinates.
    private func scrollViews(_ view: NSView) -> [NSScrollView] {
        (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap(scrollViews)
    }

    private func scrollTop(in host: NSView) throws -> CGFloat {
        let scroll = try XCTUnwrap(scrollViews(host).max { $0.frame.height < $1.frame.height })
        let frame = host.convert(scroll.bounds, from: scroll)
        return host.isFlipped ? frame.minY : host.bounds.height - frame.maxY
    }

    /// The stage is drawn above the ScrollView that holds the header, so its effects reach past the
    /// ScrollView's top edge (inside the scroll content they were clipped there).
    func testStageEffectsExtendAboveTheScrollView() async throws {
        let store = try await evolvingStore()
        let item = try XCTUnwrap(store.celebrations.next(for: .popover))
        let player = CelebrationPlayer(sleep: { _ in try await Task.sleep(for: .seconds(3600)) })
        defer { player.cancel() }
        player.play(item, now: Date().addingTimeInterval(-5), onFinish: { _ in })
        let sprites = try spriteStore()
        let layout = VStack(spacing: 0) {
            Color(white: 0.93).frame(height: 60)   // stands in for the tab picker
            ScrollView {
                CompanionHeader(store: store, spriteStore: sprites, celebrationPlayer: player)
            }
            .frame(height: 180)
            Spacer(minLength: 0)
        }
        .celebrationStageHost()
        let host = mount(layout, height: 260, dark: false)
        await settle(host)
        let top = try scrollTop(in: host)
        XCTAssertEqual(top, 60, accuracy: 1)
        let rep = try await eventually({ try bitmap(host) }) {
            bluePixels($0, top: top - CelebrationStage.effectsMargin, bottom: top, left: 0, right: 76) > 300
        }
        let above = bluePixels(rep, top: top - CelebrationStage.effectsMargin, bottom: top, left: 0, right: 76)
        XCTAssertGreaterThan(above, 300, "stage effects must reach above the ScrollView's top edge")
        let below = bluePixels(rep, top: top, bottom: top + 76, left: 0, right: 76)
        XCTAssertGreaterThan(below, 300, "the stage is still grounded on the sprite slot")
    }

    /// End to end in `PopoverView`: the header's own player starts the queued evolve on Home, and its
    /// halo shows in the gap above the Home ScrollView (between it and the tab picker).
    func testPopoverDrawsTheStageAboveItsScrollView() async throws {
        let store = try await evolvingStore(evolve: false)
        let defaults = try defaults()
        let host = mount(PopoverView(motion: { MotionSettings() })
            .environment(UsageStore(providers: [], autoRefresh: false, defaults: defaults))
            .environment(store).environment(UpdateChecker(defaults: defaults)).environment(PopoverNavigation()),
                         height: 600, dark: false)
        await settle(host)
        store.applyUsage(store.threshold)
        XCTAssertNotNil(store.celebrations.next(for: .popover))
        // The header's own player runs on the wall clock (PopoverView builds it); poll until the halo
        // has risen rather than sleeping a fixed time.
        let top = try scrollTop(in: host)
        let left = PopoverMetrics.padding
        let rep = try await eventually({ try bitmap(host) }) {
            bluePixels($0, top: top - 10, bottom: top, left: left, right: left + 76) > 100
        }
        let gap = bluePixels(rep, top: top - 10, bottom: top, left: left, right: left + 76)
        XCTAssertGreaterThan(gap, 100, "halo expected above the ScrollView (top \(top))")
    }

    /// Mounted in a window so `onAppear` runs: an injected playback of the head is not restarted.
    func testHeaderKeepsTheHeadAlreadyPlaying() async throws {
        let store = try await evolvingStore()
        let item = try XCTUnwrap(store.celebrations.next(for: .popover))
        let player = CelebrationPlayer(sleep: { _ in try await Task.sleep(for: .seconds(3600)) })
        defer { player.cancel() }
        let start = Date().addingTimeInterval(-5)
        player.play(item, now: start, onFinish: { _ in })
        let host = mount(CompanionHeader(store: store, spriteStore: try spriteStore(), celebrationPlayer: player)
            .celebrationStageHost(), height: 170, dark: true)
        await settle(host)
        XCTAssertEqual(player.item?.id, item.id)
        XCTAssertEqual(player.startedAt, start, "the header must not restart the injected playback")
    }

    // MARK: Lifecycle (mounted, so onAppear / onChange / onDisappear run)

    /// A player whose sleeps return at once and advance its clock: whole sequences end in a few yields.
    private func instantPlayer() -> CelebrationPlayer {
        final class Clock { var now = Date(timeIntervalSince1970: 10_000) }
        let clock = Clock()
        return CelebrationPlayer(clock: { clock.now }, sleep: { clock.now = clock.now.addingTimeInterval($0) })
    }

    private func waitUntil(_ condition: () -> Bool, timeout: Duration = .seconds(3)) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
    }

    /// Re-evaluates `value` until `done` accepts it (or the timeout passes) and returns the last value:
    /// waits only as long as the rendering actually needs, instead of a fixed wall-clock sleep.
    private func eventually<T>(timeout: Duration = .seconds(3), _ value: () throws -> T,
                               until done: (T) -> Bool) async throws -> T {
        let deadline = ContinuousClock.now + timeout
        var last = try value()
        while !done(last), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
            last = try value()
        }
        return last
    }

    /// Flushes the hosting view's pending SwiftUI update (layout, onAppear, onChange) without waiting
    /// on the wall clock; used before asserting that something did *not* happen.
    private func settle(_ host: NSView) async {
        for _ in 0..<5 {
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            await Task.yield()
        }
    }

    func testQueuedSequencesChainUntilTheQueueIsEmpty() async throws {
        let store = try await evolvingStore(finishHatch: false)
        XCTAssertEqual(store.celebrations.items.count, 2, "hatch then evolve queued")
        let player = instantPlayer()
        _ = mount(CompanionHeader(store: store, spriteStore: try spriteStore(), celebrationPlayer: player),
                  height: 170, dark: false)
        try await waitUntil { store.celebrations.items.isEmpty }
        XCTAssertTrue(store.celebrations.items.isEmpty, "the evolve must start after the hatch finishes")
        XCTAssertEqual(store.latestEvent?.text, store.l.notifEvolveBody(from: "Alpha", to: "Beta"),
                       "held notifications go out as each sequence ends")
        XCTAssertNil(player.item)
    }

    func testClosingThePopoverOrLeavingHomeCancelsWithoutFinishing() async throws {
        for leave in ["popover closed", "header removed"] {
            let store = try await evolvingStore()
            let item = try XCTUnwrap(store.celebrations.next(for: .popover))
            let player = CelebrationPlayer(sleep: { _ in try await Task.sleep(for: .seconds(3600)) })
            defer { player.cancel() }
            let host = mount(CompanionHeader(store: store, spriteStore: try spriteStore(), celebrationPlayer: player),
                             height: 170, dark: false)
            try await waitUntil { player.item != nil }
            XCTAssertEqual(player.item?.id, item.id, "\(leave): the header plays the queue head on appear")
            if leave == "popover closed" {
                store.popoverOpen = false
            } else {
                host.window?.contentView = nil
            }
            try await waitUntil { player.item == nil }
            XCTAssertNil(player.item, "\(leave): playback cancelled")
            XCTAssertEqual(store.celebrations.next(for: .popover)?.id, item.id, "\(leave): the item stays unseen")
        }
    }

    /// The popover can stop owning the queue (closed, display asleep, locked) between the end of a sequence
    /// and its finish callback: only the owner marks an item seen.
    func testFinishAfterThePopoverLostTheQueueDoesNotMarkItSeen() async throws {
        let store = try await evolvingStore()
        let item = try XCTUnwrap(store.celebrations.next(for: .popover))
        final class Gate {
            var open = false
            var waiters: [CheckedContinuation<Void, Never>] = []
            var onWake: (() -> Void)?
        }
        let gate = Gate()
        let player = CelebrationPlayer(sleep: { _ in
            if !gate.open { await withCheckedContinuation { gate.waiters.append($0) } }
            gate.onWake?()
        })
        defer { player.cancel() }
        _ = mount(CompanionHeader(store: store, spriteStore: try spriteStore(), celebrationPlayer: player),
                  height: 170, dark: false)
        try await waitUntil { player.item != nil }
        XCTAssertEqual(player.item?.id, item.id)
        // The popover stops owning the queue inside the player's sleep: its end fires before the header can cancel.
        gate.onWake = { store.popoverOpen = false }
        gate.open = true
        gate.waiters.forEach { $0.resume() }
        try await waitUntil { player.item == nil }
        XCTAssertEqual(store.celebrations.items.map(\.id), [item.id], "not seen: it replays on the next owner")
        XCTAssertNil(store.celebrationPlayback, "R1: no stale shared start left for the replay to join")
    }

    /// R6, pet off: the popover is the only live surface. Closed after the reveal, the item has been shown: it is
    /// finished at once (one notification) and never replays. Closed before it, it stays unseen and replays.
    /// The same with Reduce Motion, whose reveal is the end of the 1.2 s cross-fade.
    func testClosingThePopoverAfterTheRevealCountsTheItemAsSeen() async throws {
        let cases: [(String, MotionSettings, Int, Bool)] = [
            ("after evolveDone", MotionSettings(), 2, true),      // sleeps to 8.0 and 8.6 return, the 12 s one parks
            ("just before the reveal", MotionSettings(), 0, false),
            ("reduced, after the cross-fade", MotionSettings(reduceMotion: true), 1, true),
            ("reduced, before it", MotionSettings(reduceMotion: true), 0, false),
        ]
        for (name, motion, sleepsBeforeParking, seen) in cases {
            let store = try await evolvingStore()
            let item = try XCTUnwrap(store.celebrations.next(for: .popover))
            var texts: [String] = []
            store.companionEventObserver = { texts.append($0.text) }
            final class Calls { var count = 0 }
            let calls = Calls()
            let player = CelebrationPlayer(sleep: { _ in
                calls.count += 1
                if calls.count > sleepsBeforeParking { try await Task.sleep(for: .seconds(3600)) }
            })
            defer { player.cancel() }
            let host = mount(CompanionHeader(store: store, spriteStore: try spriteStore(), celebrationPlayer: player,
                                             motion: { motion }), height: 170, dark: false)
            try await waitUntil { player.item != nil && calls.count > sleepsBeforeParking }
            XCTAssertEqual(store.celebrationPlayback?.revealed, seen, "\(name): reveal reached")

            store.popoverOpen = false   // closed; the hosting tree goes at once
            host.window?.contentView = nil
            XCTAssertEqual(store.celebrations.items.isEmpty, seen, "\(name): seen = reveal")
            XCTAssertEqual(texts, [store.l.notifEvolveBody(from: "Alpha", to: "Beta")],
                           "\(name): one notification (seen, or nobody left to play it)")
            XCTAssertNil(store.celebrationPlayback, name)

            store.popoverOpen = true   // opened again
            let replay = CelebrationPlayer(sleep: { _ in try await Task.sleep(for: .seconds(3600)) })
            defer { replay.cancel() }
            _ = mount(CompanionHeader(store: store, spriteStore: try spriteStore(), celebrationPlayer: replay),
                      height: 170, dark: false)
            if seen {
                try await Task.sleep(for: .milliseconds(150))
                XCTAssertNil(replay.item, "\(name): never replays")
            } else {
                try await waitUntil { replay.item != nil }
                XCTAssertEqual(replay.item?.id, item.id, "\(name): unseen, it replays")
                XCTAssertLessThan(replay.elapsed(at: Date()), 1, "\(name): from 0")
            }
            XCTAssertEqual(texts.count, 1, "\(name): never twice")
        }
    }

    /// Behind a sleeping display or a lock screen the popover does not own the queue (M5): its header starts
    /// nothing, and starts the head again once it is live again.
    func testHeaderPlaysOnlyWhileThePopoverOwnsTheQueue() async throws {
        let store = try await evolvingStore()
        store.popoverOpen = false
        let item = try XCTUnwrap(store.celebrations.next(for: .popover))
        let player = CelebrationPlayer(sleep: { _ in try await Task.sleep(for: .seconds(3600)) })
        defer { player.cancel() }
        let host = mount(CompanionHeader(store: store, spriteStore: try spriteStore(), celebrationPlayer: player),
                         height: 170, dark: false)
        await settle(host)
        XCTAssertNil(player.item, "not the owner: nothing starts")
        store.popoverOpen = true
        try await waitUntil { player.item != nil }
        XCTAssertEqual(player.item?.id, item.id, "owner again: the head plays")
    }

    func testPopoverOwnsTheQueueOnlyWhileSomeoneCanSeeIt() {
        for shown in [false, true] {
            for awake in [false, true] {
                for interactive in [false, true] {
                    XCTAssertEqual(CelebrationQueue.popoverLive(shown: shown, displayAwake: awake,
                                                                sessionInteractive: interactive),
                                   shown && awake && interactive, "shown \(shown) awake \(awake) interactive \(interactive)")
                }
            }
        }
    }

    func testDittoRevealHeadFinishesRightAway() async throws {
        for shiny in [false, true] {
            let file = try temporaryDirectory("header-ditto").appendingPathComponent("state.json")
            let active = "{\"baseID\":1,\"pathIDs\":[1],\"stageIndex\":0,\"usedAtStage\":300000000,"
                + "\"rarity\":\"common\",\"totalForms\":3,\"isShiny\":\(shiny),\"dittoDisguise\":1,\"dittoRevealed\":false}"
            let json = "{\"installBaselineSet\":true,\"usedSinceInstall\":1000000000,\"spentTokens\":0,"
                + "\"lastDate\":\"d1\",\"active\":\(active),\"dex\":[],\"collectedFinals\":[]}"
            try Data(json.utf8).write(to: file)
            let store = CompanionStore(provider: HeaderDittoProvider(), fileURL: file, rng: SeededRNG(seed: 7),
                                       defaults: try defaults())
            store.update(todayTokensByProvider: ["test": 0], todayDate: "d1", monthTotal: 0, burnTier: .idle,
                         limitWarning: false, hasUsageData: true)
            try await waitUntil { !store.celebrations.items.isEmpty }
            XCTAssertEqual(store.celebrations.next(for: .popover)?.kind, .dittoReveal(shiny: shiny))
            store.popoverOpen = true   // the header plays only while the popover is live
            let player = CelebrationPlayer(sleep: { _ in try await Task.sleep(for: .seconds(3600)) })
            _ = mount(CompanionHeader(store: store, spriteStore: try spriteStore(), celebrationPlayer: player),
                      height: 170, dark: false)
            try await waitUntil { store.celebrations.items.isEmpty }
            XCTAssertTrue(store.celebrations.items.isEmpty, "shiny=\(shiny): the reveal is finished by the flash")
            XCTAssertNil(player.item, "shiny=\(shiny): the stage never plays a Ditto reveal")
        }
    }

    func testEggTierTextReplacesIncubating() async throws {
        let store = try eggStore(progress: 0.75)
        XCTAssertEqual(EggIncubationTier.tier(progress: store.eggProgress), .sounds)
        let host = mount(CompanionHeader(store: store, spriteStore: try spriteStore()), height: 170, dark: false)
        let rep = try await eventually({ try bitmap(host) }) { (try? self.text(in: $0).contains(store.l.eggTierSounds)) == true }
        try keep(rep, as: "header-egg-75-light.png")
        let rendered = try text(in: rep)
        XCTAssertTrue(rendered.contains(store.l.eggTierSounds), "tier copy expected: \(rendered)")
        XCTAssertFalse(rendered.contains("Incubating"), "old incubation copy must be gone: \(rendered)")
    }

    /// The imminent tier keeps the orange of the old "About to hatch!" line; earlier tiers stay grey.
    func testImminentEggTierIsOrange() async throws {
        func orangePixels(progress: Double, expecting copy: (L) -> String) async throws -> Int {
            let store = try eggStore(progress: progress)
            let host = mount(CompanionHeader(store: store, spriteStore: try spriteStore()), height: 170, dark: false)
            let rep = try await eventually({ try bitmap(host) }) { (try? self.text(in: $0).contains(copy(store.l))) == true }
            XCTAssertTrue(try text(in: rep).contains(copy(store.l)))
            // Orange glyph pixels, skipping the rows of the (always orange) progress bar fill.
            var orange = 0
            for y in 0..<rep.pixelsHigh {
                var row = 0
                for x in (76 * 2)..<rep.pixelsWide {
                    guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                    if c.redComponent > 0.8, c.greenComponent > 0.35, c.greenComponent < 0.75, c.blueComponent < 0.3 {
                        row += 1
                    }
                }
                if row < 250 { orange += row }
            }
            return orange
        }
        let sounds = try await orangePixels(progress: 0.75) { $0.eggTierSounds }
        let imminent = try await orangePixels(progress: 0.95) { $0.eggTierImminent }
        XCTAssertLessThan(sounds, 50, "sounds tier copy is grey (\(sounds) orange pixels)")
        XCTAssertGreaterThan(imminent - sounds, 100, "imminent copy drawn in orange (sounds \(sounds), imminent \(imminent))")
    }

    /// A sequence queued while the popover shows another tab brings Home back; the queue emptying does not.
    func testPopoverReturnsHomeForAQueuedSequence() async throws {
        let store = try await evolvingStore(evolve: false)
        XCTAssertNil(store.celebrations.next(for: .popover))
        let nav = PopoverNavigation()
        nav.tab = .bag
        let defaults = try defaults()
        let host = mount(PopoverView(motion: { MotionSettings() })
            .environment(UsageStore(providers: [], autoRefresh: false, defaults: defaults))
            .environment(store).environment(UpdateChecker(defaults: defaults)).environment(nav),
                  height: 600, dark: false)
        await settle(host)
        XCTAssertEqual(nav.tab, .bag)

        store.applyUsage(store.threshold)   // Alpha evolves while the popover shows the Bag
        XCTAssertNotNil(store.celebrations.next(for: .popover))
        try await waitUntil { nav.tab == .home }
        XCTAssertEqual(nav.tab, .home)

        nav.tab = .shop
        store.celebrations.items.forEach { store.finishCelebration(id: $0.id) }
        await settle(host)
        XCTAssertEqual(nav.tab, .shop, "an emptied queue leaves navigation alone")
    }

    /// End to end: a sequence arriving while Settings is open does not close it (its draft would be lost).
    func testSettingsStaysOpenWhenASequenceArrives() async throws {
        let store = try await evolvingStore(evolve: false)
        let nav = PopoverNavigation()
        nav.showSettings = true
        let defaults = try defaults()
        let host = mount(PopoverView(motion: { MotionSettings() })
            .environment(UsageStore(providers: [], autoRefresh: false, defaults: defaults))
            .environment(store).environment(UpdateChecker(defaults: defaults)).environment(nav),
                         height: 600, dark: false)
        await settle(host)
        store.applyUsage(store.threshold)
        XCTAssertNotNil(store.celebrations.next(for: .popover))
        try await Task.sleep(for: .milliseconds(200))
        await settle(host)
        XCTAssertTrue(nav.showSettings, "Settings stays open; the sequence waits for Home")
    }

    /// A new item behind an unseen head (it waited while Settings was open) still brings Home back.
    func testANewItemBehindAnUnseenHeadReturnsHome() async throws {
        let store = try await evolvingStore(finishHatch: false, evolve: false)   // the hatch waits, unseen
        let nav = PopoverNavigation()
        nav.tab = .bag
        nav.showSettings = true
        let defaults = try defaults()
        let host = mount(PopoverView(motion: { MotionSettings() })
            .environment(UsageStore(providers: [], autoRefresh: false, defaults: defaults))
            .environment(store).environment(UpdateChecker(defaults: defaults)).environment(nav),
                         height: 600, dark: false)
        await settle(host)
        nav.showSettings = false   // closed onto the Bag: the head did not change, nothing moves
        await settle(host)
        XCTAssertEqual(nav.tab, .bag)
        let head = store.celebrations.next(for: .popover)?.id
        store.applyUsage(store.threshold)   // a rare candy from the Bag: the evolve queues behind the hatch
        XCTAssertEqual(store.celebrations.next(for: .popover)?.id, head, "the head is unchanged")
        try await waitUntil { nav.tab == .home }
        XCTAssertEqual(nav.tab, .home)
    }

    /// While a popover sequence is pending the Home ScrollView does not scroll, so the stage (drawn above it)
    /// cannot drift over other controls.
    func testHomeDoesNotScrollWhileASequenceIsPending() async throws {
        let store = try await evolvingStore(evolve: false)
        XCTAssertFalse(CelebrationScrollView<EmptyView>.scrollLocked(companion: store))
        store.applyUsage(store.threshold)
        XCTAssertTrue(CelebrationScrollView<EmptyView>.scrollLocked(companion: store))
        store.popoverOpen = false
        XCTAssertFalse(CelebrationScrollView<EmptyView>.scrollLocked(companion: store), "not the owner: nothing plays")
    }

    // MARK: Fix round 1

    func testPreEvolveLineShowsTheSourceAsCurrent() {
        // Linear A → B → C, evolved A → B: B goes back to a future node, A is current again.
        let linear = EvoNode(speciesID: 1, children: [EvoNode(speciesID: 2, children: [EvoNode(speciesID: 3, children: [])])])
        XCTAssertEqual(CompanionStore.preEvolveLineItems(tree: linear, pathIDs: [1, 2], stageIndex: 1, currentID: 2,
                                                         sourceID: 1),
                       [EvoLineItem(.species(1), .current), EvoLineItem(.species(2), .future),
                        EvoLineItem(.species(3), .future)])
        // Two evolves queued at once (A → B → C): each plays on the line as it was before it.
        XCTAssertEqual(CompanionStore.preEvolveLineItems(tree: linear, pathIDs: [1, 2, 3], stageIndex: 2, currentID: 3,
                                                         sourceID: 2),
                       [EvoLineItem(.species(1), .done), EvoLineItem(.species(2), .current),
                        EvoLineItem(.species(3), .future)])

        // Branching (Wurmple-like): 10 → {11 → 12, 13 → 14}. Evolved 10 → 11: the line after 10 is a
        // mystery again, and 11's own child is not shown yet.
        let branching = EvoNode(speciesID: 10, children: [
            EvoNode(speciesID: 11, children: [EvoNode(speciesID: 12, children: [])]),
            EvoNode(speciesID: 13, children: [EvoNode(speciesID: 14, children: [])]),
        ])
        XCTAssertEqual(CompanionStore.lineItems(tree: branching, pathIDs: [10, 11], stageIndex: 1, currentID: 11),
                       [EvoLineItem(.species(10), .done), EvoLineItem(.species(11), .current),
                        EvoLineItem(.species(12), .future)])
        XCTAssertEqual(CompanionStore.preEvolveLineItems(tree: branching, pathIDs: [10, 11], stageIndex: 1, currentID: 11,
                                                         sourceID: 10),
                       [EvoLineItem(.species(10), .current), EvoLineItem(.mystery, .future)])

        // A current species missing from the (pruned) tree shows the realized stages only, as before.
        XCTAssertEqual(CompanionStore.lineItems(tree: linear, pathIDs: [1, 7], stageIndex: 1, currentID: 7),
                       [EvoLineItem(.species(1), .done), EvoLineItem(.species(7), .current)])
        // A source that is not on the realized path keeps the live line.
        XCTAssertEqual(CompanionStore.preEvolveLineItems(tree: linear, pathIDs: [1, 2], stageIndex: 1, currentID: 2,
                                                         sourceID: 99),
                       CompanionStore.lineItems(tree: linear, pathIDs: [1, 2], stageIndex: 1, currentID: 2))
    }

    /// Without an active Pokémon (graduated while the evolve still plays) there is no line to show.
    func testPreEvolveLineIsEmptyWithoutAnActivePokemon() throws {
        let store = try eggStore(progress: 0.5)
        XCTAssertEqual(store.lineNodes(beforeEvolvingFrom: 1), [])
        XCTAssertEqual(store.lineNodes, [])
    }

    /// A Home scrolled down is brought back to the header when a live evolve arrives, so the stage plays
    /// at the slot inside the viewport (not clamped over the picker or above the popover). Built like
    /// `PopoverView.mainContent` (picker, `CelebrationScrollView` starting with the header, stage host
    /// above) with content tall enough to scroll; the sample popover Home is shorter than its viewport.
    func testHomeScrollsToTheHeaderWhenASequenceArrives() async throws {
        let store = try await evolvingStore(evolve: false)
        let sprites = try spriteStore()
        let layout = VStack(alignment: .leading, spacing: 0) {
            Color(white: 0.93).frame(height: 60)   // stands in for the tab picker
            CelebrationScrollView(companion: store) {
                VStack(alignment: .leading, spacing: 12) {
                    CompanionHeader(store: store, spriteStore: sprites)
                    Color(white: 0.97).frame(height: 900)   // the rest of Home
                }
            }
            .frame(height: 300)
            Spacer(minLength: 0)
        }
        .celebrationStageHost()
        let host = mount(layout, height: 380, dark: false)
        await settle(host)
        let scroll = try XCTUnwrap(scrollViews(host).first)
        let maxOffset = try XCTUnwrap(scroll.documentView).frame.height - scroll.contentView.bounds.height
        XCTAssertGreaterThan(maxOffset, 200)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: maxOffset))
        scroll.reflectScrolledClipView(scroll.contentView)
        await settle(host)
        XCTAssertEqual(scroll.contentView.bounds.origin.y, maxOffset, accuracy: 1, "scrolled down before the evolve")

        store.applyUsage(store.threshold)   // the header's own player starts the evolve
        try await waitUntil { scroll.contentView.bounds.origin.y < 1 }
        XCTAssertEqual(scroll.contentView.bounds.origin.y, 0, accuracy: 1, "Home scrolled back to the header")
        let top = try scrollTop(in: host)
        XCTAssertEqual(top, 60, accuracy: 1)
        // The stage (halo, then whitening sprite) is drawn on the slot inside the viewport.
        let rep = try await eventually({ try bitmap(host) }) {
            bluePixels($0, top: top, bottom: top + 76, left: 0, right: 76) > 300
        }
        XCTAssertGreaterThan(bluePixels(rep, top: top, bottom: top + 76, left: 0, right: 76), 300,
                             "the stage is drawn at the slot, inside the viewport")
    }

    /// Clicks on the effects margin go to what is underneath (here a stand-in tab button); only the
    /// 76 pt sprite box skips the sequence.
    func testOnlyTheSpriteBoxSkips() async throws {
        let store = try await evolvingStore()
        let item = try XCTUnwrap(store.celebrations.next(for: .popover))
        let player = CelebrationPlayer(sleep: { _ in try await Task.sleep(for: .seconds(3600)) })
        defer { player.cancel() }
        player.play(item, now: Date().addingTimeInterval(-1), onFinish: { _ in })
        final class Taps { var count = 0 }
        let taps = Taps()
        let sprites = try spriteStore()
        let layout = VStack(alignment: .leading, spacing: 0) {
            Button { taps.count += 1 } label: { Color(white: 0.9).frame(width: 200, height: 60) }
                .buttonStyle(.plain)
            CompanionHeader(store: store, spriteStore: sprites, celebrationPlayer: player)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .celebrationStageHost()
        let host = mount(layout, height: 260, dark: false)
        await settle(host)
        let window = try XCTUnwrap(host.window)

        func click(_ point: CGPoint) async {
            // Host points are top-left; window coordinates are bottom-left.
            let location = NSPoint(x: point.x, y: host.bounds.height - point.y)
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                if let event = NSEvent.mouseEvent(with: type, location: location, modifierFlags: [],
                                                  timestamp: ProcessInfo.processInfo.systemUptime,
                                                  windowNumber: window.windowNumber, context: nil,
                                                  eventNumber: 0, clickCount: 1, pressure: 1) {
                    window.sendEvent(event)
                }
            }
            await settle(host)
        }

        // 10 pt above the sprite box: inside the stage's margin, over the button.
        await click(CGPoint(x: 38, y: 50))
        XCTAssertLessThan(player.elapsed(at: Date()), 7, "a click on the margin must not skip")
        XCTAssertEqual(taps.count, 1, "the control under the margin keeps its clicks")
        // The sprite box itself skips to the reveal.
        await click(CGPoint(x: 38, y: 60 + 38))
        XCTAssertGreaterThanOrEqual(player.elapsed(at: Date()), 7.4, "a click on the sprite skips")
    }

    /// A header that comes back after a cancel replays the item from the start.
    func testReappearingHeaderReplaysFromTheStart() async throws {
        let store = try await evolvingStore()
        let item = try XCTUnwrap(store.celebrations.next(for: .popover))
        final class Clock { var now = Date(timeIntervalSince1970: 20_000) }
        let clock = Clock()
        let player = CelebrationPlayer(clock: { clock.now }, sleep: { _ in try await Task.sleep(for: .seconds(3600)) })
        defer { player.cancel() }
        let host = mount(CompanionHeader(store: store, spriteStore: try spriteStore(), celebrationPlayer: player)
            .celebrationStageHost(), height: 170, dark: false)
        try await waitUntil { player.item != nil }
        XCTAssertEqual(player.startedAt, clock.now)

        clock.now = clock.now.addingTimeInterval(4)   // 4 s in, then the header goes away
        let window = try XCTUnwrap(host.window)
        window.contentView = nil
        try await waitUntil { player.item == nil }
        XCTAssertNil(player.item)
        XCTAssertEqual(store.celebrations.next(for: .popover)?.id, item.id)

        clock.now = clock.now.addingTimeInterval(60)
        window.contentView = host
        try await waitUntil { player.item != nil }
        XCTAssertEqual(player.item?.id, item.id, "the same item plays again")
        XCTAssertEqual(player.startedAt, clock.now, "from t = 0")
        XCTAssertEqual(player.elapsed(at: clock.now), 0)
    }
}
