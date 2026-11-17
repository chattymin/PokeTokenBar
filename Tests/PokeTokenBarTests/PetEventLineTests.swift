import XCTest
@testable import PokeTokenBar

private struct EventLineProvider: PokeProviding {
    let value: EvoLine
    func line(baseSpeciesID: Int) async throws -> EvoLine { value }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [BaseSpecies(id: value.baseID, captureRate: 255)] }
}

/// Base 1 is a common three-stage line (the disguise); 132 is Ditto.
private struct DittoEventProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        if baseSpeciesID == PokemonOdds.dittoSpeciesID {
            return EvoLine(baseID: 132, tree: EvoNode(speciesID: 132, children: []), rarity: .rare,
                           names: [132: ["en": "Ditto"]])
        }
        return EvoLine(baseID: 1,
                       tree: EvoNode(speciesID: 1, children: [EvoNode(speciesID: 2, children: [EvoNode(speciesID: 3, children: [])])]),
                       rarity: .common, names: [1: ["en": "Bulb"], 2: ["en": "Ivy"], 3: ["en": "Venu"]])
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [BaseSpecies(id: 1, captureRate: 255)] }
}

/// The floating pet pops its hover callout once with the latest hatch / evolution line.
@MainActor
final class PetEventLineTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private var line: EvoLine {
        EvoLine(baseID: 1,
                tree: EvoNode(speciesID: 1, children: [EvoNode(speciesID: 2, children: [EvoNode(speciesID: 3, children: [])])]),
                rarity: .common,
                names: [1: ["en": "Bulb", "ko": "이상해씨"], 2: ["en": "Ivy", "ko": "이상해풀"], 3: ["en": "Venu", "ko": "이상해꽃"]])
    }

    private func store(clock: @escaping () -> Date) -> CompanionStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("event-line-\(UUID()).json")
        let store = CompanionStore(provider: EventLineProvider(value: line), clock: clock, fileURL: url,
                                   rng: SeededRNG(seed: 7))
        store.setLanguage(.en)
        return store
    }

    // MARK: when the callout pops

    func testPopsOnlyForANewEventWhileVisibleAndWithoutABubble() {
        func pop(_ seq: Int?, seen: Int?, visible: Bool = true, bubble: Bool = false) -> Bool {
            FloatingPetController.shouldPopEvent(eventSeq: seq, lastSeenSeq: seen, petVisible: visible, bubbleShowing: bubble)
        }
        XCTAssertTrue(pop(1, seen: nil), "the first event")
        XCTAssertTrue(pop(2, seen: 1), "a newer event")
        XCTAssertFalse(pop(1, seen: 1), "the same event is not popped twice")
        XCTAssertFalse(pop(nil, seen: nil), "no event")
        XCTAssertFalse(pop(2, seen: 1, visible: false), "the pet is hidden")
        XCTAssertFalse(pop(2, seen: 1, bubble: true), "a limit alert or hearts bubble wins")
        XCTAssertEqual(FloatingPetController.eventPopDuration, .seconds(6))
    }

    func testHoverTextPutsTheEventBetweenTheUsageLineAndThePrayerLine() {
        let l = L(.en)
        let plain = FloatingPetView.hoverTooltip(todayTokens: 1, limitUtilization: nil, mode: .used, l: l)
        let full = FloatingPetView.hoverTooltip(todayTokens: 1, limitUtilization: nil, mode: .used, l: l,
                                                eventLine: "EVENT", prayers: 3)
        XCTAssertEqual(full, plain + "\nEVENT\n" + l.prayerHoverLine(3))
        XCTAssertEqual(FloatingPetView.hoverTooltip(todayTokens: 1, limitUtilization: nil, mode: .used, l: l,
                                                    eventLine: nil), plain)
    }

    // MARK: what the store records (the dev build has no system notifications, so this is the only trace)

    func testHatchAndEvolutionAreRecordedAndTheNewerReplacesTheOlder() async {
        var current = now
        let store = store(clock: { current })
        XCTAssertNil(store.latestEvent)

        await store.hatch(baseID: 1)
        XCTAssertEqual(store.latestEvent?.text, "Bulb hatched from the egg!")
        XCTAssertEqual(store.latestEvent?.at, now)
        let hatchSeq = store.latestEvent?.seq

        current = now.addingTimeInterval(120)
        store.applyUsage(PokemonBalance.phaseThreshold(rarity: .common, totalForms: 3, stageIndex: 0))
        XCTAssertEqual(store.latestEvent?.text, "Bulb evolved into Ivy!")
        XCTAssertEqual(store.latestEvent?.at, current)
        XCTAssertNotEqual(store.latestEvent?.seq, hatchSeq, "a new event gets a new id")
    }

    func testGraduationIsRecordedToo() async {
        let store = store(clock: { self.now })
        await store.hatch(baseID: 1)
        for stage in 0..<3 {
            store.applyUsage(PokemonBalance.phaseThreshold(rarity: .common, totalForms: 3, stageIndex: stage))
        }
        XCTAssertEqual(store.latestEvent?.text, L(.en).notifGraduateBody("Venu"))
    }

    // MARK: the evolution line names both Pokémon

    func testEvolutionLineNamesBothWithTheRightKoreanParticles() {
        let ko = L(.ko)
        XCTAssertEqual(ko.notifEvolveBody(from: "피카츄", to: "라이츄"), "피카츄가 라이츄로 진화했어요!")
        XCTAssertEqual(ko.notifEvolveBody(from: "리자드", to: "리자몽"), "리자드가 리자몽으로 진화했어요!")
        XCTAssertEqual(ko.notifEvolveBody(from: "이상해씨", to: "이상해풀"), "이상해씨가 이상해풀로 진화했어요!")
        XCTAssertEqual(L(.en).notifEvolveBody(from: "Pichu", to: "Pikachu"), "Pichu evolved into Pikachu!")
        for language in AppLanguage.allCases {
            let text = L(language).notifEvolveBody(from: "AAA", to: "BBB")
            XCTAssertTrue(text.contains("AAA") && text.contains("BBB"), "\(language) drops a name")
        }
    }

    // MARK: a disguised Ditto must not be spoiled by the event line

    /// Found once with a plain script using this RNG and the hatch roll order (shiny, nature, Ditto disguise):
    /// the hatch is a shiny, disguised Ditto. Not searched at test time (about 1 in 8192 seeds).
    private static let shinyDisguisedDittoSeed: UInt64 = 2466

    private func dittoStore(seed: UInt64) -> CompanionStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("event-ditto-\(UUID()).json")
        let store = CompanionStore(provider: DittoEventProvider(), clock: { self.now }, fileURL: url,
                                   rng: SeededRNG(seed: seed), dittoDisguiseRollingEnabled: true)
        store.setLanguage(.en)
        return store
    }

    func testDisguisedDittoHatchEventShowsTheDisguiseAndHidesShiny() async throws {
        let seed = Self.shinyDisguisedDittoSeed

        let plain = dittoStore(seed: seed)
        await plain.hatch(baseID: 1)
        XCTAssertNotNil(plain.state.active?.dittoDisguise)
        XCTAssertEqual(plain.latestEvent?.text, L(.en).notifHatchBody("Bulb"), "same line as the notification")

        let prayed = dittoStore(seed: seed)
        prayed.pray(); prayed.pray()
        await prayed.hatch(baseID: 1)
        XCTAssertEqual(prayed.latestEvent?.text,
                       L(.en).notifPrayerHatchBody("Bulb", prayers: 2, shiny: false, rarity: .common))
        XCTAssertFalse(prayed.latestEvent?.text.contains("Ditto") ?? true)
        XCTAssertFalse(prayed.latestEvent?.text.lowercased().contains("shiny") ?? true, "a disguised shiny stays hidden")
    }

    func testRevealEventReplacesTheHatchLineAndNeverShowsAnEvolution() async throws {
        let store = dittoStore(seed: Self.shinyDisguisedDittoSeed)
        await store.hatch(baseID: 1)
        store.applyUsage(130_000_000)   // past the first evolution threshold: the disguise breaks instead of evolving
        let deadline = Date().addingTimeInterval(2)
        while store.state.active?.dittoRevealed != true, Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertEqual(store.state.active?.dittoRevealed, true)
        XCTAssertEqual(store.latestEvent?.text, L(.en).notifShinyDittoRevealBody("Bulb"))
        XCTAssertFalse(store.latestEvent?.text.contains("evolved") ?? true)
    }
}
