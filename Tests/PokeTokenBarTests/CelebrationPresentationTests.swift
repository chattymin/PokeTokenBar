import XCTest
@testable import PokeTokenBar

/// The one presentation rule both surfaces share: no result before its reveal, across a whole queue.
/// A chain is the trigger: the store is already at its end while the first item plays.
@MainActor
final class CelebrationPresentationTests: XCTestCase {
    private typealias P = CelebrationPresentation

    private let egg = CelebrationSubject(speciesID: nil, form: nil, isShiny: false, name: CompanionStore.eggName)
    private let a = CelebrationSubject(speciesID: 1, form: nil, isShiny: true, name: "A")
    private let b = CelebrationSubject(speciesID: 2, form: nil, isShiny: true, name: "B")
    private let c = CelebrationSubject(speciesID: 3, form: nil, isShiny: true, name: "C")

    private func queue(_ kinds: [CelebrationKind]) -> CelebrationQueue {
        var q = CelebrationQueue()
        for kind in kinds { q.enqueue(kind, deferred: nil) }
        return q
    }

    /// `live`: the store's companion now; by default the end of the queued chain (the store switches species
    /// before any sequence plays).
    private func shown(_ q: CelebrationQueue, playing index: Int?, _ text: CelebrationText,
                       on surface: CelebrationSurface = .popover, live: Int?? = .none) -> P? {
        let endOfChain: Int? = switch q.items.last?.kind {
        case .evolve(_, let to)?, .hatch(let to)?: to.speciesID
        default: nil
        }
        return P.shown(queue: q, playing: index.map { q.items[$0] }, text: text, surface: surface,
                       liveSpeciesID: live ?? endOfChain)
    }

    func testRevealIsTheDoneCaption() {
        XCTAssertTrue(P.isRevealed(.evolveDone))
        XCTAssertTrue(P.isRevealed(.hatchDone))
        XCTAssertFalse(P.isRevealed(.evolveAnnounce))
        XCTAssertFalse(P.isRevealed(.hatchOh))
        XCTAssertFalse(P.isRevealed(.none))
    }

    func testSingleItemShowsTheSourceUntilTheRevealThenTheLiveState() {
        let evolve = queue([.evolve(from: a, to: b)])
        XCTAssertEqual(shown(evolve, playing: 0, .evolveAnnounce), .subject(a))
        XCTAssertNil(shown(evolve, playing: 0, .evolveDone), "the live state is the target")
        let hatch = queue([.hatch(to: a)])
        XCTAssertEqual(shown(hatch, playing: 0, .hatchOh), .egg)
        XCTAssertEqual(shown(hatch, playing: 0, .none), .egg)
        XCTAssertNil(shown(hatch, playing: 0, .hatchDone))
        XCTAssertNil(shown(CelebrationQueue(), playing: nil, .none), "nothing pending: the live state")
    }

    /// Hatch then a carry-over evolve: at `hatchDone` the store already shows the evolved form.
    func testHatchThenEvolveShowsTheHatchedFormAtHatchDone() {
        let q = queue([.hatch(to: a), .evolve(from: a, to: b)])
        XCTAssertEqual(shown(q, playing: 0, .hatchOh), .egg)
        XCTAssertEqual(shown(q, playing: 0, .hatchDone), .subject(a), "not B: its evolve has not played yet")
        XCTAssertEqual(shown(q, playing: 0, .hatchDone, on: .floatingPet), .subject(a))
    }

    /// Two rare candies: A → B → C. At the first `evolveDone` the store already shows C.
    func testCandyChainShowsEachResultUntilTheNextItemPlays() {
        let q = queue([.evolve(from: a, to: b), .evolve(from: b, to: c)])
        XCTAssertEqual(shown(q, playing: 0, .evolveAnnounce), .subject(a))
        XCTAssertEqual(shown(q, playing: 0, .evolveDone), .subject(b), "not C")
        XCTAssertEqual(shown(q, playing: 1, .evolveAnnounce), .subject(b))
        XCTAssertNil(shown(q, playing: 1, .evolveDone), "the last reveal is the live state")
    }

    /// Reduce Motion / Low Power reveal at t = 0: the chain still holds the later results back.
    func testReducedMotionRevealsAtOnceButNotTheLaterItems() {
        let text = CelebrationTimeline(kind: .evolve, reduced: true, shiny: false).frame(at: 0).text
        let q = queue([.evolve(from: a, to: b), .evolve(from: b, to: c)])
        XCTAssertEqual(shown(q, playing: 0, text), .subject(b))
        XCTAssertNil(shown(q, playing: 1, text))
    }

    /// Between two items nothing plays for a moment: the next item's source stays, never the live state.
    func testBetweenItemsTheNextSourceStays() {
        let q = queue([.evolve(from: b, to: c)])
        XCTAssertEqual(shown(q, playing: nil, .none), .subject(b))
        XCTAssertEqual(shown(queue([.hatch(to: a)]), playing: nil, .none), .egg)
    }

    /// A Ditto reveal has no stage: on the popover it holds the hatched disguise back until it flashes. The pet
    /// never plays it, so it shows Ditto once the hatch sequence is over; during that sequence the live companion
    /// (Ditto, 132) is not its result, so the disguise stays (R4) and Ditto never shows inside the hatch.
    func testALaterDittoRevealCountsOnlyWhereItPlays() {
        let q = queue([.hatch(to: a), .dittoReveal(shiny: false)])
        XCTAssertEqual(shown(q, playing: 0, .hatchDone, on: .popover, live: 132), .subject(a))
        XCTAssertEqual(shown(q, playing: 0, .hatchDone, on: .floatingPet, live: 132), .subject(a))
        XCTAssertNil(shown(queue([.dittoReveal(shiny: false)]), playing: nil, .none, on: .floatingPet, live: 132),
                     "after the hatch: the live Ditto")
        XCTAssertNil(shown(queue([.dittoReveal(shiny: false)]), playing: nil, .none), "no stage source for a Ditto reveal")
    }

    /// R4: the chain's last evolution ended in a graduation. During its reveal caption the store is already the
    /// new egg: the result stays on screen, never the egg (that would announce the graduation early).
    func testLastItemOfAGraduatingChainKeepsItsResultUntilItEnds() {
        let q = queue([.evolve(from: b, to: c)])
        XCTAssertEqual(shown(q, playing: 0, .evolveDone, live: .some(nil)), .subject(c), "graduated: live is the egg")
        XCTAssertEqual(shown(q, playing: 0, .evolveDone, on: .floatingPet, live: .some(nil)), .subject(c))
        XCTAssertNil(shown(q, playing: 0, .evolveDone, live: 3), "still C: the live state is the result")
        XCTAssertEqual(shown(q, playing: nil, .none, live: .some(nil)), .subject(b), "nothing playing: the next source")
    }

    func testNameAndSpecies() {
        XCTAssertEqual(P.egg.name, CompanionStore.eggName)
        XCTAssertNil(P.egg.speciesID)
        XCTAssertEqual(P.subject(b).name, "B")
        XCTAssertEqual(P.subject(b).speciesID, 2)
    }

    // MARK: With a real store (the trigger: its state is already at the end of the chain)

    private func names(_ ids: [Int]) -> [Int: [String: String]] {
        Dictionary(uniqueKeysWithValues: ids.map { ($0, ["en": "P\($0)"]) })
    }

    private func chainStore() async -> CompanionStore {
        let line = EvoLine(baseID: 1, tree: EvoNode(speciesID: 1, children: [EvoNode(speciesID: 2, children: [
            EvoNode(speciesID: 3, children: [])])]), rarity: .common, names: names([1, 2, 3]))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("presentation-\(UUID()).json")
        let s = CompanionStore(provider: StubProvider(value: line), fileURL: url, rng: SeededRNG(seed: 7))
        s.setLanguage(.en)
        s.popoverOpen = true
        await s.hatch(baseID: 1)
        let total = s.threshold + PokemonBalance.phaseThreshold(rarity: .common, totalForms: 3, stageIndex: 1)
        s.applyUsage(total)   // hatch, 1 → 2, 2 → 3 queued; the store is at 3
        return s
    }

    /// R4 against a store: two candies to the final form, then the graduation (held behind the evolutions).
    func testGraduatingChainAgainstTheStore() async {
        let s = await chainStore()
        s.applyUsage(10_000_000_000)   // 3 graduates while everything still waits for the popover
        XCTAssertNil(s.currentSpeciesID, "the store is already the new egg")
        let last = try? XCTUnwrap(s.celebrations.items.last)
        let shown = last.flatMap {
            P.shown(queue: s.celebrations, playing: $0, text: .evolveDone, surface: .popover, liveSpeciesID: s.currentSpeciesID)
        }
        XCTAssertEqual(shown?.speciesID, 3, "the last result stays during its caption")
        XCTAssertNil(s.justGraduated, "the graduation is still held")
    }

    func testHatchAndChainAgainstTheStore() async {
        let s = await chainStore()
        XCTAssertEqual(s.currentSpeciesID, 3)
        let items = s.celebrations.items
        XCTAssertEqual(items.count, 3)
        func at(_ index: Int, _ text: CelebrationText) -> P? {
            P.shown(queue: s.celebrations, playing: items[index], text: text, surface: .popover,
                    liveSpeciesID: s.currentSpeciesID)
        }
        XCTAssertEqual(at(0, .hatchDone)?.speciesID, 1)
        XCTAssertEqual(at(1, .evolveDone)?.speciesID, 2)
        XCTAssertEqual(s.lineNodes(presenting: 1),
                       [EvoLineItem(.species(1), .current), EvoLineItem(.species(2), .future),
                        EvoLineItem(.species(3), .future)], "the line before 1 evolved")
        XCTAssertEqual(s.lineNodes(presenting: 2),
                       [EvoLineItem(.species(1), .done), EvoLineItem(.species(2), .current),
                        EvoLineItem(.species(3), .future)])
        XCTAssertEqual(s.lineNodes(presenting: 3), s.lineNodes, "the current species: the live line")
        XCTAssertEqual(s.lineNodes(presenting: 99), [], "not on the companion's path: no line rather than a spoiler")
        XCTAssertEqual(s.lineNodes(presenting: nil), [], "the egg has no line")

        // The pet shares the rule: between items it keeps the next item's source.
        s.finishCelebration(id: items[0].id)
        s.finishCelebration(id: items[1].id)
        let pet = FloatingPetController.displayedSubject(
            representative: s.representativeSubject, queue: s.celebrations, player: CelebrationPlayer(),
            liveSpeciesID: s.currentSpeciesID)
        XCTAssertEqual(pet.speciesID, 2, "the pet shows 2 until 2 → 3 is seen, not the live 3")
    }
}
