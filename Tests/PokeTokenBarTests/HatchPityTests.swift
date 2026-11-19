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
}
