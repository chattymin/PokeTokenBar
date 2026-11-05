import AppKit
import XCTest
@testable import PokeTokenBar

// "Neglected? It turns its back": sulk state after three hours without token usage, its hover text, and
// back-sprite URL/cache/fallback. StubProvider / SeededRNG come from CompanionTests.swift.

private let sulkNow = Date(timeIntervalSince1970: 1_700_000_000)
private let threshold = PokemonBalance.sulkAfterIdle

private final class SulkClock: @unchecked Sendable {
    nonisolated(unsafe) var now = sulkNow
}

@MainActor
final class SulkStateTests: XCTestCase {
    private let clock = SulkClock()

    private func makeStore(expireHatchWindow: Bool = true) async -> CompanionStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-sulk-\(UUID().uuidString).json")
        let line = EvoLine(baseID: 1, tree: EvoNode(speciesID: 1, children: []), rarity: .common, names: [:])
        let store = CompanionStore(provider: StubProvider(value: line), clock: { self.clock.now },
                                   fileURL: url, rng: SeededRNG(seed: 5))
        await store.hatch(baseID: 1)
        if expireHatchWindow { clock.now = sulkNow.addingTimeInterval(60) }
        return store
    }

    private func update(_ store: CompanionStore, today: Int = 0, idle: TimeInterval?, hasData: Bool = true,
                        limitWarning: Bool = false, date: String = "d") {
        store.update(todayTokensByProvider: ["test": today], todayDate: date, monthTotal: 0, burnTier: .idle,
                     limitWarning: limitWarning, hasUsageData: hasData, timeSinceLastUsage: idle)
    }

    func testThresholdBoundary() async {
        let store = await makeStore()
        update(store, idle: threshold - 1)
        XCTAssertEqual(store.displayState, .sleep, "just under the threshold does not sulk")
        XCTAssertFalse(store.facesBack)
        update(store, idle: threshold)
        XCTAssertEqual(store.displayState, .sulk, "exactly the threshold sulks")
        XCTAssertTrue(store.facesBack)
        XCTAssertEqual(store.sulkIdle, threshold)
    }

    func testThresholdIsThreeHours() {
        XCTAssertEqual(threshold, 3 * 3600)
    }

    func testFacesBackTruthTable() async {
        let store = await makeStore()
        for (always, idle, expected) in [(false, 0.0, false), (false, threshold, true),
                                         (true, 0.0, true), (true, threshold, true)] {
            store.alwaysFacesBack = always
            update(store, idle: idle)
            XCTAssertEqual(store.facesBack, expected, "always=\(always) idle=\(idle)")
            XCTAssertEqual(store.displayState, idle >= threshold ? .sulk : .sleep,
                           "the preference never changes the state kind")
            XCTAssertEqual(store.sulkIdle, idle >= threshold ? idle : 0, "nor the sulk text input")
        }
    }

    func testAlwaysFacesBackDoesNotAffectAnEgg() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-sulk-\(UUID().uuidString).json")
        let line = EvoLine(baseID: 1, tree: EvoNode(speciesID: 1, children: []), rarity: .common, names: [:])
        let store = CompanionStore(provider: StubProvider(value: line), clock: { sulkNow },
                                   fileURL: url, rng: SeededRNG(seed: 1))
        store.alwaysFacesBack = true
        XCTAssertFalse(store.facesBack)
    }

    func testUnknownLastUsageNeverSulks() async {
        let store = await makeStore()
        update(store, idle: nil)
        XCTAssertEqual(store.displayState, .sleep)
        XCTAssertFalse(store.facesBack)
        XCTAssertEqual(store.sulkIdle, 0)
    }

    func testNoUsageDataDoesNotSulk() async {
        let store = await makeStore()
        // The first update only fixes the install baseline, so run one with data before losing it.
        update(store, idle: 0)
        update(store, idle: 3 * threshold, hasData: false)
        XCTAssertEqual(store.displayState, .sleep)
        XCTAssertFalse(store.facesBack)
    }

    func testTiredBeatsSulk() async {
        let store = await makeStore()
        update(store, idle: 3 * threshold, limitWarning: true)
        XCTAssertEqual(store.displayState, .tired)
    }

    func testSulkBeatsSleepAndResumingFlipsBack() async {
        let store = await makeStore()
        update(store, idle: 2 * threshold)
        XCTAssertEqual(store.displayState, .sulk)
        // Usage resumes: today's total rises before the scan's last-usage time catches up.
        update(store, today: 500, idle: 2 * threshold)
        XCTAssertNotEqual(store.displayState, .sulk)
        XCTAssertFalse(store.facesBack)
        XCTAssertEqual(store.sulkIdle, 0)
        // And once the scan catches up, the idle time is small again.
        update(store, idle: 60)
        XCTAssertEqual(store.displayState, .sleep)
    }

    func testSameDayIdleSulksEvenThoughTodayHasUsage() async {
        let store = await makeStore()
        // Worked 09:00-12:00, away since: today's total is positive but the last usage is 4 h old.
        update(store, today: 40_000, idle: 4 * 3600)
        XCTAssertEqual(store.displayState, .sulk)
        XCTAssertTrue(store.facesBack)
        XCTAssertEqual(store.sulkIdle, 4 * 3600)
        update(store, today: 40_000, idle: 3 * 3600 - 1)
        XCTAssertNotEqual(store.displayState, .sulk, "just under three hours")
    }

    func testRisingTodayTotalUnSulksBeforeTheScanCatchesUp() async {
        let store = await makeStore()
        update(store, today: 40_000, idle: 4 * 3600)
        XCTAssertEqual(store.displayState, .sulk)
        update(store, today: 40_500, idle: 4 * 3600)   // the scan still reports the old last usage
        XCTAssertNotEqual(store.displayState, .sulk)
        XCTAssertFalse(store.facesBack)
        XCTAssertEqual(store.sulkIdle, 0)
        // Nothing further happens for three hours: the observed usage ages like any other.
        clock.now = clock.now.addingTimeInterval(3 * 3600)
        update(store, today: 40_500, idle: 7 * 3600)
        XCTAssertEqual(store.displayState, .sulk)
    }

    func testFirstSightingAfterLaunchIsNotUsage() async {
        let store = await makeStore()
        update(store, today: 0, idle: nil, hasData: false)   // launch: no data in yet
        update(store, today: 40_000, idle: 4 * 3600)         // the first total with data
        XCTAssertEqual(store.displayState, .sulk, "the first total with data is a baseline, not a rise")
    }

    func testMidnightRolloverNeitherUnSulksNorSulksByItself() async {
        let store = await makeStore()
        update(store, today: 40_000, idle: 4 * 3600, date: "2026-09-01")
        XCTAssertEqual(store.displayState, .sulk)
        // A new day starts from a different (even larger) total: a new baseline, not a rise.
        update(store, today: 90_000, idle: 5 * 3600, date: "2026-09-02")
        XCTAssertEqual(store.displayState, .sulk)
        update(store, today: 0, idle: 5 * 3600, date: "2026-09-03")
        XCTAssertEqual(store.displayState, .sulk)
        // Only a rise within the same day counts.
        update(store, today: 300, idle: 5 * 3600, date: "2026-09-03")
        XCTAssertNotEqual(store.displayState, .sulk)
        // And an active companion is not pushed into sulking by the rollover.
        update(store, today: 0, idle: 60, date: "2026-09-04")
        XCTAssertNotEqual(store.displayState, .sulk)
    }

    func testLevelUpBeatsSulk() async {
        let store = await makeStore(expireHatchWindow: false)   // the hatch event window is still open
        update(store, idle: 3 * threshold)
        XCTAssertEqual(store.displayState, .levelUp)
    }

    func testEggNeverSulks() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-sulk-\(UUID().uuidString).json")
        let line = EvoLine(baseID: 1, tree: EvoNode(speciesID: 1, children: []), rarity: .common, names: [:])
        let store = CompanionStore(provider: StubProvider(value: line), clock: { sulkNow },
                                   fileURL: url, rng: SeededRNG(seed: 1))
        update(store, idle: 3 * threshold)
        XCTAssertEqual(store.displayState, .egg)
    }

    func testHoverTextShowsHoursBelowFortyEightAndDaysFromThere() {
        let l = L(.en)
        func tooltip(_ hours: Double) -> String {
            FloatingPetView.hoverTooltip(todayTokens: 0, limitUtilization: nil, mode: .used, l: l,
                                         sulkIdle: hours * 3600)
        }
        XCTAssertEqual(tooltip(0), l.floatingPetHoverTokensOnly("0"))
        XCTAssertTrue(tooltip(3).hasSuffix(l.floatingPetHoverSulkHours(3)))
        XCTAssertTrue(tooltip(24).hasSuffix(l.floatingPetHoverSulkHours(24)))
        XCTAssertTrue(tooltip(47.9).hasSuffix(l.floatingPetHoverSulkHours(47)))
        XCTAssertTrue(tooltip(48).hasSuffix(l.floatingPetHoverSulkDays(2)))
        XCTAssertTrue(tooltip(100).hasSuffix(l.floatingPetHoverSulkDays(4)))
        XCTAssertEqual(L(.ko).floatingPetHoverSulkHours(30), "30시간째 삐져 있어요")
        XCTAssertEqual(L(.ko).floatingPetHoverSulkDays(3), "3일째 삐져 있어요")
    }
}

@MainActor
final class BackSpriteTests: XCTestCase {
    private let base = "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon"

    func testBackURLs() {
        let gif = "\(base)/versions/generation-v/black-white/animated"
        XCTAssertEqual(SpriteStore.spriteURL(speciesID: 25, animated: true, shiny: false, back: true).absoluteString,
                       "\(gif)/back/25.gif")
        XCTAssertEqual(SpriteStore.spriteURL(speciesID: 25, animated: true, shiny: true, back: true).absoluteString,
                       "\(gif)/back/shiny/25.gif")
        XCTAssertEqual(SpriteStore.spriteURL(speciesID: 25, animated: false, shiny: false, back: true).absoluteString,
                       "\(base)/back/25.png")
        XCTAssertEqual(SpriteStore.spriteURL(speciesID: 25, animated: false, shiny: true, back: true).absoluteString,
                       "\(base)/back/shiny/25.png")
        XCTAssertEqual(SpriteStore.spriteURL(speciesID: 25, animated: true, shiny: false).absoluteString,
                       "\(gif)/25.gif")   // front is unchanged
    }

    func testBackCacheKeyDiffersFromFrontAndFrontKeyIsUnchanged() {
        for animated in [false, true] {
            for shiny in [false, true] {
                XCTAssertNotEqual(SpriteStore.cacheKey(speciesID: 25, animated: animated, shiny: shiny, back: true),
                                  SpriteStore.cacheKey(speciesID: 25, animated: animated, shiny: shiny))
            }
        }
        XCTAssertEqual(SpriteStore.cacheKey(speciesID: 25, animated: false, shiny: false), "25-s")
        XCTAssertEqual(SpriteStore.cacheKey(speciesID: 25, animated: true, shiny: true, back: true), "25-back-sha")
    }

    func testViewIdentityKeysIncludeBack() {
        XCTAssertNotEqual(SpriteView.frameTaskID(speciesID: 25, shiny: false, floor: 0, back: true),
                          SpriteView.frameTaskID(speciesID: 25, shiny: false, floor: 0))
        XCTAssertNotEqual(AppDelegate.menuSpriteKey(id: 25, shiny: false, floor: 0.4, back: true),
                          AppDelegate.menuSpriteKey(id: 25, shiny: false, floor: 0.4))
        XCTAssertTrue(SpriteView.needsReload(loadedID: 25, loadedShiny: false, id: 25, shiny: false,
                                             loadedBack: false, back: true))
    }

    private func pngData(_ color: NSColor) -> Data {
        let image = NSImage(size: NSSize(width: 4, height: 4))
        image.lockFocus()
        color.setFill()
        NSRect(x: 0, y: 0, width: 4, height: 4).fill()
        image.unlockFocus()
        let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
        return rep.representation(using: .png, properties: [:])!
    }

    func testMissingBackFallsBackToFrontAndBackWinsWhenCached() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sulk-sprites-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        SpriteLoader.imageCache.removeAllObjects()

        try pngData(.red).write(to: dir.appendingPathComponent("25-s.png"))
        let fallback = SpriteLoader.cachedImage(speciesID: 25, directory: dir, back: true)
        XCTAssertNotNil(fallback, "no back sprite cached: the front sprite must show instead of nothing")
        XCTAssertNotNil(SpriteLoader.cachedImage(speciesID: 25, shiny: true, directory: dir, back: true),
                        "shiny + back miss falls through plain back to the plain front")

        try pngData(.blue).write(to: dir.appendingPathComponent("25-back-s.png"))
        let back = SpriteLoader.cachedImage(speciesID: 25, directory: dir, back: true)
        XCTAssertNotNil(back)
        XCTAssertNotEqual(back?.tiffRepresentation, fallback?.tiffRepresentation)
        XCTAssertNil(SpriteLoader.cachedImage(speciesID: 26, directory: dir, back: true))
    }
}
