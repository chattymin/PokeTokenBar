import XCTest
import AppKit
@testable import PokeTokenBar

// An evolution into a species whose sprites were not cached showed the egg glyph until the GIF
// arrived (seen 2026-11-11: Tyrogue → Hitmonlee, about three seconds on a slow response), which
// read as "the evolution turned it back into an egg". Two guards:
//  1) the forms still ahead are warmed into the sprite cache before the evolution happens;
//  2) if a sprite is still missing, the previous Pokémon stays as a white silhouette, never the egg.

@MainActor
final class EvolutionSpriteTests: XCTestCase {

    private func image(_ side: CGFloat) -> NSImage { NSImage(size: NSSize(width: side, height: side)) }

    // MARK: Silhouette while the new species loads

    func testUncachedEvolutionKeepsThePreviousPokemonAsASilhouette() {
        let tyrogue = image(4)
        let next = SpriteSubject(image: tyrogue, loadedID: 236)
            .startingLoad(cachedImage: nil, outgoing: tyrogue, for: 106, shiny: false, form: nil)
        XCTAssertTrue(next.image === tyrogue)
        XCTAssertTrue(next.isPlaceholder)
        XCTAssertNil(next.loadedID, "the silhouette is not Hitmonlee — a reload must still run")
    }

    func testCachedSpriteWinsOverTheSilhouette() {
        let hitmonlee = image(4)
        let next = SpriteSubject(image: image(4), loadedID: 236)
            .startingLoad(cachedImage: hitmonlee, outgoing: image(4), for: 106, shiny: false, form: nil)
        XCTAssertTrue(next.image === hitmonlee)
        XCTAssertFalse(next.isPlaceholder)
        XCTAssertEqual(next.loadedID, 106)
    }

    func testFailedLoadKeepsTheSilhouetteAndLoadedSpriteReplacesIt() throws {
        let placeholder = SpriteSubject(image: image(4), loadedID: nil, isPlaceholder: true)
        XCTAssertNil(placeholder.applyingLoad(nil, for: 106, cancelled: false),
                     "a failed PNG must not empty the slot while the GIF retry continues")
        let hitmonlee = image(4)
        let loaded = try XCTUnwrap(placeholder.applyingLoad(hitmonlee, for: 106, cancelled: false))
        XCTAssertTrue(loaded.image === hitmonlee)
        XCTAssertFalse(loaded.isPlaceholder)
        XCTAssertEqual(loaded.loadedID, 106)
    }

    func testBecomingEggDropsTheSilhouette() {
        let egg = image(2)
        let next = SpriteSubject(image: image(4), loadedID: nil, isPlaceholder: true).becomingEgg(cachedEgg: egg)
        XCTAssertTrue(next.image === egg, "a graduating silhouette would leave the old Pokémon on the egg (#135)")
        XCTAssertFalse(next.isPlaceholder)
    }

    // MARK: What leaves the screen

    func testOutgoingImageIsTheShownFrameOfAnotherSpecies() {
        let frame = image(4)
        XCTAssertTrue(SpriteView.outgoingImage(subject: SpriteSubject(image: nil, loadedID: nil),
                                               frame: frame, framesID: 236, incoming: 106) === frame)
    }

    func testOutgoingImageFallsBackToTheStaticImageOfAnotherSpecies() {
        let still = image(4)
        XCTAssertTrue(SpriteView.outgoingImage(subject: SpriteSubject(image: still, loadedID: 236),
                                               frame: nil, framesID: nil, incoming: 106) === still)
    }

    func testOutgoingImageKeepsAnEarlierSilhouette() {
        let silhouette = image(4)
        let subject = SpriteSubject(image: silhouette, loadedID: nil, isPlaceholder: true)
        XCTAssertTrue(SpriteView.outgoingImage(subject: subject, frame: nil, framesID: nil, incoming: 107) === silhouette)
    }

    func testNoOutgoingImageForTheSameSpeciesAnEggOrAHatch() {
        let same = SpriteSubject(image: image(4), loadedID: 106)
        XCTAssertNil(SpriteView.outgoingImage(subject: same, frame: image(4), framesID: 106, incoming: 106),
                     "a shiny, form or facing change is not an evolution")
        XCTAssertNil(SpriteView.outgoingImage(subject: same, frame: nil, framesID: nil, incoming: nil),
                     "graduation goes to the egg, not a silhouette")
        let egg = SpriteSubject(image: image(2), loadedID: nil)
        XCTAssertNil(SpriteView.outgoingImage(subject: egg, frame: nil, framesID: nil, incoming: 236),
                     "the egg sprite is not a Pokémon to silhouette")
    }

    // MARK: Evolution sequence (old ⇄ new silhouettes)

    private let now = Date(timeIntervalSince1970: 1_000_000)
    private func cue(seq: Int = 1, to: Int = 106, secondsAgo: TimeInterval = 0) -> CompanionStore.EvolutionCue {
        CompanionStore.EvolutionCue(seq: seq, fromID: 236, toID: to, at: now.addingTimeInterval(-secondsAgo))
    }

    func testEvolutionPlaysOnceForTheEvolvedSpecies() {
        XCTAssertTrue(SpriteView.playsEvolution(cue: cue(), incoming: 106, played: nil, now: now, reduceMotion: false))
        XCTAssertFalse(SpriteView.playsEvolution(cue: cue(), incoming: 106, played: 1, now: now, reduceMotion: false),
                       "a cue already played here")
        XCTAssertTrue(SpriteView.playsEvolution(cue: cue(seq: 2), incoming: 106, played: 1, now: now, reduceMotion: false))
    }

    func testEvolutionDoesNotPlayForOtherChanges() {
        XCTAssertFalse(SpriteView.playsEvolution(cue: nil, incoming: 106, played: nil, now: now, reduceMotion: false),
                       "no evolution happened (a hatch, a representative or dex change)")
        XCTAssertFalse(SpriteView.playsEvolution(cue: cue(), incoming: 25, played: nil, now: now, reduceMotion: false),
                       "the pet switched to another species, not the evolved one")
        XCTAssertFalse(SpriteView.playsEvolution(cue: cue(secondsAgo: 30), incoming: 106, played: nil, now: now,
                                                 reduceMotion: false),
                       "picking the evolved species later is not the evolution")
        XCTAssertFalse(SpriteView.playsEvolution(cue: cue(), incoming: 106, played: nil, now: now, reduceMotion: true))
    }

    func testEvolutionFlipsSpeedUpAndEndOnTheNewForm() {
        let flips = SpriteView.evolutionFlips
        XCTAssertGreaterThanOrEqual(flips.count, 5)
        XCTAssertTrue(flips.first!.showsNew, "the hold already showed the old form")
        XCTAssertTrue(flips.last!.showsNew, "the colors come in on the new form")
        for (a, b) in zip(flips, flips.dropFirst()) { XCTAssertNotEqual(a.showsNew, b.showsNew) }
        let swaps = flips.dropLast().map(\.duration)
        XCTAssertEqual(swaps, swaps.sorted(by: >), "each swap is shorter than the last")
        let total = SpriteView.evolutionHold + flips.map(\.duration).reduce(0, +) + 0.6
        XCTAssertLessThanOrEqual(total, 4, "done within the 4 s \"evolved into…\" message")
    }

    func testPopoverSkipsItsFlashOnlyWhenTheSpritePlaysTheEvolution() {
        XCTAssertTrue(CompanionHeader.spriteShowsEvolution(.evolve, live: true, reduceMotion: false))
        XCTAssertFalse(CompanionHeader.spriteShowsEvolution(.evolve, live: false, reduceMotion: false),
                       "opened after the evolution: the sprite saw no change, so the flash plays")
        XCTAssertFalse(CompanionHeader.spriteShowsEvolution(.evolve, live: true, reduceMotion: true))
        XCTAssertFalse(CompanionHeader.spriteShowsEvolution(.hatch(shiny: false), live: true, reduceMotion: false))
    }

    // MARK: Which sprites are warmed

    private func mon(planned: [Int], stage: Int, disguise: Int? = nil, revealed: Bool = false) -> MonState {
        MonState(baseID: planned[0], pathIDs: Array(planned.prefix(stage + 1)), plannedPathIDs: planned,
                 stageIndex: stage, usedAtStage: 0, rarity: .common, totalForms: planned.count,
                 dittoDisguise: disguise, dittoRevealed: revealed)
    }

    func testUpcomingSpeciesAreTheRestOfThePlannedPath() {
        XCTAssertEqual(CompanionStore.upcomingSpeciesIDs(mon(planned: [1, 2, 3], stage: 0)), [2, 3])
        XCTAssertEqual(CompanionStore.upcomingSpeciesIDs(mon(planned: [236, 106], stage: 0)), [106],
                       "a branch is chosen at hatch, so only the planned child is warmed")
        XCTAssertEqual(CompanionStore.upcomingSpeciesIDs(mon(planned: [236, 106], stage: 1)), [])
    }

    func testUnrevealedDittoWarmsDittoInstead() {
        XCTAssertEqual(CompanionStore.upcomingSpeciesIDs(mon(planned: [1, 2, 3], stage: 0, disguise: 1)),
                       [PokemonOdds.dittoSpeciesID])
        XCTAssertEqual(CompanionStore.upcomingSpeciesIDs(mon(planned: [132], stage: 0, disguise: 1, revealed: true)), [])
    }

    func testSpriteRequestsCoverFrontBackStaticAndAnimated() {
        let plain = CompanionStore.evolutionSpriteRequests(shiny: false)
        XCTAssertEqual(plain.count, 4)
        XCTAssertFalse(plain.contains { $0.shiny })
        XCTAssertEqual(Set(plain.map { "\($0.animated)-\($0.back)" }).count, 4)
        let shiny = CompanionStore.evolutionSpriteRequests(shiny: true)
        XCTAssertEqual(shiny.count, 8, "shiny sprites plus the plain ones they fall back to")
    }

    // MARK: Prefetch

    func testPrefetchLeavesAnExistingFileAlone() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = SpriteStore(directory: dir)
        let key = SpriteStore.cacheKey(speciesID: 106, animated: false, shiny: false)
        let file = dir.appendingPathComponent("\(key).png")
        let bytes = Data([1, 2, 3])
        try bytes.write(to: file)
        await store.prefetch(speciesID: 106, animated: false, shiny: false)
        XCTAssertEqual(try Data(contentsOf: file), bytes, "a cached sprite must not be fetched again")
    }
}
