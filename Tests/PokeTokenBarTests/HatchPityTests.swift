import XCTest
@testable import PokeTokenBar

private let pityNow = Date(timeIntervalSince1970: 1_700_000_000)

/// Index with a rarity per capture rate, so graded eggs hatch (IndexProvider lines are always common).
private struct TieredIndexProvider: PokeProviding {
    let index: [BaseSpecies]
    func baseSpeciesIndex() async throws -> [BaseSpecies] { index }
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        let rate = index.first { $0.id == baseSpeciesID }?.captureRate ?? 255
        return EvoLine(baseID: baseSpeciesID, tree: EvoNode(speciesID: baseSpeciesID, children: []),
                       rarity: Rarity.from(captureRate: rate, isLegendary: false, isMythical: false),
                       names: [baseSpeciesID: ["en": "P\(baseSpeciesID)"]])
    }
}

/// Index-backed down, REST up — the fallback has no index, so pity cannot apply there.
private struct RestOnlyProvider: PokeProviding {
    func baseSpeciesIndex() async throws -> [BaseSpecies] { throw URLError(.badServerResponse) }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { BaseSpecies(id: id, captureRate: 100) }
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: baseSpeciesID, tree: EvoNode(speciesID: baseSpeciesID, children: []),
                rarity: .uncommon, names: [baseSpeciesID: ["en": "P\(baseSpeciesID)"]])
    }
}

/// First raw roll of a seed — `chooseBase` consumes exactly this value.
private func firstRoll(_ seed: UInt64) -> UInt64 {
    var r = SeededRNG(seed: seed)
    return r.next()
}

/// Pity after repeat hatches (#253 follow-up): normal odds are unchanged, only droughts are bounded.
@MainActor
final class HatchPityTests: XCTestCase {
    private func store(_ provider: any PokeProviding, seed: UInt64 = 7, streak: Int = 0,
                       collected: Set<String> = [], tier: Rarity? = nil,
                       eggReady: Bool = true) -> CompanionStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pity-\(UUID().uuidString).json")
        var st = CompanionState()
        st.installBaselineSet = true
        st.lastDate = "d1"
        st.eggUsage = eggReady ? PokemonBalance.eggHatchThreshold + 1 : 0
        st.collectedFinals = collected
        st.repeatHatchStreak = streak
        st.eggTier = tier
        try? JSONEncoder().encode(st).write(to: url)
        return CompanionStore(provider: provider, clock: { pityNow }, fileURL: url, rng: SeededRNG(seed: seed))
    }

    private func indexProvider(_ index: [BaseSpecies]) -> IndexProvider {
        let p = IndexProvider()
        p.index = index
        return p
    }

    // MARK: Counter

    func testStreakCountsRepeatHatchesAndResetsOnANewLine() async {
        let s = store(indexProvider([]), streak: 2, collected: ["10:10"])

        await s.hatch(baseID: 10)
        XCTAssertEqual(s.state.active?.hasGrowthBoost, true)
        XCTAssertEqual(s.state.repeatHatchStreak, 3, "a repeat hatch adds one")

        await s.hatch(baseID: 20)
        XCTAssertEqual(s.state.active?.hasGrowthBoost, false)
        XCTAssertEqual(s.state.repeatHatchStreak, 0, "a new line resets the streak")
    }

    /// Discarded hatches are not hatches: a graded egg that rolled below its tier keeps the streak.
    func testDiscardedBelowTierHatchLeavesTheStreak() async {
        let s = store(TieredIndexProvider(index: [BaseSpecies(id: 1, captureRate: 255)]),
                      streak: 3, collected: ["1:1"], tier: .rare)

        await s.hatch(baseID: 1)

        XCTAssertNil(s.state.active, "a common rolled into a Rare Egg is discarded")
        XCTAssertEqual(s.state.repeatHatchStreak, 3)
    }

    func testStreakPersistsThroughJSONAndAMissingKeyDecodesToZero() throws {
        var st = CompanionState()
        st.repeatHatchStreak = 4
        let data = try JSONEncoder().encode(st)
        XCTAssertEqual(try JSONDecoder().decode(CompanionState.self, from: data).repeatHatchStreak, 4)

        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(object.removeValue(forKey: "repeatHatchStreak"))
        let older = try JSONSerialization.data(withJSONObject: object)
        XCTAssertEqual(try JSONDecoder().decode(CompanionState.self, from: older).repeatHatchStreak, 0)
    }

    func testStreakTravelsWithASaveTransfer() throws {
        var st = CompanionState()
        st.repeatHatchStreak = 4
        let data = try SaveTransfer.encode(state: st, appVersion: "2.5.7", deviceName: "Old Mac", now: pityNow)
        let imported = try SaveTransfer.decode(data).state
        XCTAssertEqual(imported.repeatHatchStreak, 4)

        let rebased = SaveTransfer.rebasedForThisDevice(imported, current: CompanionState(),
                                                        todayTokensByProvider: ["test": 1],
                                                        todayDate: "d1", hasUsageData: true)
        XCTAssertEqual(rebased.repeatHatchStreak, 4, "progress, not a device ledger")
    }

    /// hatchCore increments the streak, so a hand-edited Int.max would trap on the next repeat hatch.
    func testSanitizeClampsAnAbsurdStreak() {
        var huge = CompanionState()
        huge.repeatHatchStreak = .max
        XCTAssertEqual(SaveTransfer.sanitized(huge).repeatHatchStreak, SaveTransfer.maxTokenValue)
        var negative = CompanionState()
        negative.repeatHatchStreak = -3
        XCTAssertEqual(SaveTransfer.sanitized(negative).repeatHatchStreak, 0)
    }

    // MARK: Draw

    /// Below the threshold the collected common still wins this roll; at the threshold it cannot.
    func testPityStartsAtExactlyTheThreshold() async throws {
        // Normal weights [127, 3] (total 130); pity pool is only id 2.
        let index = [BaseSpecies(id: 1, captureRate: 255), BaseSpecies(id: 2, captureRate: 3)]
        let seed = try XCTUnwrap((UInt64(0)..<500).first { firstRoll($0) % 130 < 127 })
        let threshold = PokemonOdds.repeatHatchPityThreshold
        XCTAssertEqual(threshold, 5)

        let below = store(indexProvider(index), seed: seed, streak: threshold - 1, collected: ["1:1"])
        await below.hatchIfNeeded()
        XCTAssertEqual(below.state.active?.baseID, 1, "four repeats still use the normal odds")
        XCTAssertEqual(below.state.repeatHatchStreak, threshold)

        let due = store(indexProvider(index), seed: seed, streak: threshold, collected: ["1:1"])
        await due.hatchIfNeeded()
        XCTAssertEqual(due.state.active?.baseID, 2, "five repeats draw only uncollected bases")
        XCTAssertEqual(due.state.repeatHatchStreak, 0)
    }

    /// Among uncollected bases the draw stays capture-rate weighted — not uniform, legendaries stay rare.
    func testPityDrawIsCaptureRateWeightedAmongUncollected() async throws {
        // Pity weights [200, 50] (total 250). A uniform pick would map the roll by parity instead.
        let index = [BaseSpecies(id: 1, captureRate: 255),
                     BaseSpecies(id: 2, captureRate: 200),
                     BaseSpecies(id: 3, captureRate: 50)]
        let toTwo = try XCTUnwrap((UInt64(0)..<2000).first { firstRoll($0) % 250 < 200 && firstRoll($0) % 2 == 1 })
        let toThree = try XCTUnwrap((UInt64(0)..<2000).first { firstRoll($0) % 250 >= 200 && firstRoll($0) % 2 == 0 })

        for (seed, expected) in [(toTwo, 2), (toThree, 3)] {
            let s = store(indexProvider(index), seed: seed, streak: 5, collected: ["1:1"])
            await s.hatchIfNeeded()
            XCTAssertEqual(s.state.active?.baseID, expected, "seed \(seed)")
        }
    }

    /// A complete Pokédex has nothing to guarantee: the egg still hatches with the normal odds.
    func testCompleteDexFallsBackToTheNormalDraw() async {
        let index = [BaseSpecies(id: 1, captureRate: 200), BaseSpecies(id: 2, captureRate: 100)]
        for seed in UInt64(1)...10 {
            let expected = firstRoll(seed) % 150 < 100 ? 1 : 2   // normal weights [100, 50]
            let s = store(indexProvider(index), seed: seed, streak: 7, collected: ["1:1", "2:2"])
            await s.hatchIfNeeded()
            XCTAssertEqual(s.state.active?.baseID, expected, "seed \(seed)")
            XCTAssertEqual(s.state.repeatHatchStreak, 8)
        }
    }

    /// Pity narrows after the tier filter: a Rare Egg never trades its guarantee for an uncollected common,
    /// and when its tier has something uncollected, pity picks from that.
    func testGradedEggKeepsItsTierUnderPity() async {
        let noneInTier = [BaseSpecies(id: 1, captureRate: 45), BaseSpecies(id: 2, captureRate: 255)]
        let someInTier = noneInTier + [BaseSpecies(id: 3, captureRate: 30)]
        for seed in UInt64(1)...10 {
            let fallback = store(TieredIndexProvider(index: noneInTier), seed: seed, streak: 5,
                                 collected: ["1:1"], tier: .rare)
            await fallback.hatchIfNeeded()
            XCTAssertEqual(fallback.state.active?.baseID, 1, "nothing uncollected in tier → normal tier draw")

            let pity = store(TieredIndexProvider(index: someInTier), seed: seed, streak: 5,
                             collected: ["1:1"], tier: .rare)
            await pity.hatchIfNeeded()
            XCTAssertEqual(pity.state.active?.baseID, 3, "the uncollected base inside the tier")
        }
    }

    /// The REST fallback has no index, so pity is skipped (and logged) — the egg must still hatch.
    func testRestFallbackStillHatchesWhenPityIsDue() async {
        let s = store(RestOnlyProvider(), streak: 5)
        await s.hatchIfNeeded()
        XCTAssertNotNil(s.state.active)
        XCTAssertEqual(s.state.repeatHatchStreak, 0, "an uncollected REST pick is a new line")
    }

    // MARK: End to end

    /// Overflow that graduates the Pokémon inside the hatch itself: the next egg is rolled from that
    /// graduation, and it must already see the streak this hatch produced (4 → 5 → pity).
    func testOverflowGraduationRollsTheNextEggWithTheUpdatedStreak() async throws {
        // Without pity id 1 wins 127 of 130 rolls; pick a seed whose hatch roll does draw the repeat.
        let index = [BaseSpecies(id: 1, captureRate: 255), BaseSpecies(id: 2, captureRate: 3)]
        let seed = try XCTUnwrap((UInt64(0)..<500).first { firstRoll($0) % 130 < 127 })
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pity-\(UUID().uuidString).json")
        var st = CompanionState()
        st.installBaselineSet = true
        st.lastDate = "d1"
        st.eggUsage = PokemonBalance.eggHatchThreshold + PokemonBalance.graduationTotal(.common)
        st.collectedFinals = ["1:1"]
        st.repeatHatchStreak = 4
        try JSONEncoder().encode(st).write(to: url)
        let overflowing = CompanionStore(provider: indexProvider(index), clock: { pityNow }, fileURL: url,
                                         rng: SeededRNG(seed: seed))

        await overflowing.hatchIfNeeded()

        XCTAssertNil(overflowing.state.active, "the overflow graduated the repeat inside the hatch")
        XCTAssertEqual(overflowing.state.dex.last?.baseID, 1)
        XCTAssertEqual(overflowing.state.repeatHatchStreak, 5)
        for _ in 0..<200 where overflowing.state.pendingHatchID == nil { await Task.yield() }
        XCTAssertEqual(overflowing.state.pendingHatchID, 2, "the next egg's roll saw streak 5")
    }

    /// Five repeat hatches through the real graduation path, then the egg prepared next is a new line.
    func testFiveRepeatHatchesThenThePreparedEggIsAnUncollectedLine() async throws {
        // Without pity id 1 wins 127 of 130 rolls.
        let s = store(indexProvider([BaseSpecies(id: 1, captureRate: 255), BaseSpecies(id: 2, captureRate: 3)]),
                      collected: ["1:1"], eggReady: false)
        for n in 1...PokemonOdds.repeatHatchPityThreshold {
            await s.hatch(baseID: 1)
            XCTAssertEqual(s.state.repeatHatchStreak, n)
            s.applyUsage(s.tokensToNext)   // graduates and prefetches the next egg
            XCTAssertNil(s.state.active, "repeat \(n) graduated")
        }
        for _ in 0..<200 where s.state.pendingHatchID == nil { await Task.yield() }
        XCTAssertEqual(s.state.pendingHatchID, 2, "the egg prepared after five repeats is uncollected")

        s.update(todayTokensByProvider: ["test": 0], todayDate: "d1", monthTotal: 0,
                 burnTier: .idle, limitWarning: false, hasUsageData: true)
        s.update(todayTokensByProvider: ["test": PokemonBalance.eggHatchThreshold], todayDate: "d1",
                 monthTotal: 0, burnTier: .idle, limitWarning: false, hasUsageData: true)
        await s.hatchIfNeeded()
        for _ in 0..<200 where s.state.active == nil { await Task.yield() }
        let hatched = try XCTUnwrap(s.state.active)
        XCTAssertEqual(hatched.baseID, 2)
        XCTAssertFalse(hatched.hasGrowthBoost)
        XCTAssertEqual(s.state.repeatHatchStreak, 0)
    }
}
