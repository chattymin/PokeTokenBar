import XCTest
@testable import PokeTokenBar

// MARK: Regional Incense
//
// The incense promises one number: the next hatch comes from its region `inRegionSharePercent` of the
// time, for every region and every egg grade. That promise can break in five places, and each one is
// reproduced here on the branch that would break it:
//   ① the rescale itself is not exactly the stated share            → pure arithmetic test
//   ② the weighted roll (chooseBase) does not apply it              → seeded hatches with a control group
//   ③ only the REST fallback (chooseBaseViaREST) skips it           → the index is killed, same check
//   ④ the species was rolled before the incense was lit             → pre-roll and in-flight roll tests
//   ⑤ the incense is spent by a hatch it did not bias, or kept by   → empty-pool, grade-gate and
//      one it did                                                      spend tests

/// A base index with species in every region. Each region gets the same capture rates, so an unbiased
/// roll lands in each region one time in five: far from the incense's share, which is what lets the
/// control groups below prove the bias is real.
private struct RegionPoolProvider: PokeProviding {
    var entries: [BaseSpecies]

    /// `commonOnly` regions hold no Uncommon-or-better species, so a graded egg empties them.
    static func pool(commonOnly: Set<PokedexRegion> = [], without: Set<PokedexRegion> = []) -> [BaseSpecies] {
        PokedexRegion.allCases.filter { !without.contains($0) }.flatMap { region -> [BaseSpecies] in
            let rates = commonOnly.contains(region) ? [255, 190] : [255, 190, 100, 45, 30]
            return rates.enumerated().map {
                BaseSpecies(id: region.dexRange.lowerBound + $0.offset, captureRate: $0.element)
            }
        }
    }

    func baseSpeciesIndex() async throws -> [BaseSpecies] { entries }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { entries.first { $0.id == id } }
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        guard let e = entries.first(where: { $0.id == baseSpeciesID }) else { throw URLError(.badURL) }
        return EvoLine(baseID: e.id, tree: EvoNode(speciesID: e.id, children: []),
                       rarity: Rarity.from(captureRate: e.captureRate, isLegendary: false, isMythical: false),
                       names: [e.id: ["en": "M\(e.id)"]])
    }
}

/// The GraphQL index is down and only REST answers. Every id is a base species.
private struct RestOnlyRegionProvider: PokeProviding {
    static func captureRate(_ id: Int) -> Int { id % 3 == 0 ? 30 : (id % 2 == 0 ? 100 : 255) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { throw URLError(.badServerResponse) }
    func baseSpecies(id: Int) async throws -> BaseSpecies? {
        BaseSpecies(id: id, captureRate: Self.captureRate(id))
    }
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: baseSpeciesID, tree: EvoNode(speciesID: baseSpeciesID, children: []),
                rarity: Rarity.from(captureRate: Self.captureRate(baseSpeciesID),
                                    isLegendary: false, isMythical: false),
                names: [baseSpeciesID: ["en": "M\(baseSpeciesID)"]])
    }
}

/// REST only, and the first species lookup waits until the test releases it: a roll held in flight.
private actor HeldRestProvider: PokeProviding {
    private var held: CheckedContinuation<Void, Never>?
    private var holdNext = true

    func baseSpeciesIndex() async throws -> [BaseSpecies] { throw URLError(.badServerResponse) }
    func baseSpecies(id: Int) async throws -> BaseSpecies? {
        if holdNext {
            holdNext = false
            await withCheckedContinuation { held = $0 }
        }
        return BaseSpecies(id: id, captureRate: 255)
    }
    nonisolated func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: baseSpeciesID, tree: EvoNode(speciesID: baseSpeciesID, children: []),
                rarity: .common, names: [baseSpeciesID: ["en": "M\(baseSpeciesID)"]])
    }
    func isHolding() -> Bool { held != nil }
    func release() {
        held?.resume()
        held = nil
    }
}

/// The index calls id 7 (Kanto) Rare, but its real line is Common: the grade gate rejects the hatch.
private struct StaleKantoIndexProvider: PokeProviding {
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [BaseSpecies(id: 7, captureRate: 30)] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { BaseSpecies(id: 7, captureRate: 30) }
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: 7, tree: EvoNode(speciesID: 7, children: []), rarity: .common, names: [7: ["en": "Liar"]])
    }
}

/// Plays back fixed draws, then a constant. For the branches a seed cannot aim at.
private struct ScriptedRNG: RandomNumberGenerator {
    var script: [UInt64]
    private var index = 0
    init(_ script: [UInt64]) { self.script = script }
    mutating func next() -> UInt64 {
        defer { index += 1 }
        return index < script.count ? script[index] : 1_000_003
    }
}

@MainActor
final class RegionalIncenseTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let incenses: [ItemKind] = [.kantoIncense, .johtoIncense, .hoennIncense, .sinnohIncense, .unovaIncense]
    private let share = Double(RegionalIncense.inRegionSharePercent) / 100

    private func url() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("incense-\(UUID().uuidString).json")
    }

    private func store(_ fields: String, provider: any PokeProviding = RegionPoolProvider(entries: RegionPoolProvider.pool()),
                       rng: any RandomNumberGenerator = SeededRNG(seed: 7), at file: URL? = nil,
                       used: Int = 20_000_000_000) -> CompanionStore {
        let f = file ?? url()
        let json = "{\"installBaselineSet\":true,\"usedSinceInstall\":\(used),\"spentTokens\":0,"
            + "\"lastDate\":\"d\",\"dex\":[],\"collectedFinals\":[],\(fields)}"
        try? json.data(using: .utf8)!.write(to: f)
        return CompanionStore(provider: provider, clock: { self.now }, fileURL: f, rng: rng)
    }

    private static let mon = "{\"baseID\":10,\"pathIDs\":[10],\"stageIndex\":0,\"usedAtStage\":200000000,"
        + "\"rarity\":\"common\",\"totalForms\":3,\"isShiny\":false}"

    /// An egg ready to hatch, with no species rolled yet.
    private func readyEgg(incense: PokedexRegion?, tier: Rarity? = nil) -> String {
        "\"active\":null,\"eggUsage\":\(PokemonBalance.eggHatchThreshold),"
            + "\"eggTier\":\(tier.map { "\"\($0.rawValue)\"" } ?? "null"),"
            + "\"pendingIncense\":\(incense.map { "\"\($0.rawValue)\"" } ?? "null")"
    }

    /// Hatches one ready egg per seed and returns what hatched.
    private func hatches(seeds: ClosedRange<UInt64> = 1...200, incense: PokedexRegion?, tier: Rarity? = nil,
                         provider: any PokeProviding = RegionPoolProvider(entries: RegionPoolProvider.pool())) async -> [MonState] {
        var result: [MonState] = []
        for seed in seeds {
            let s = store(readyEgg(incense: incense, tier: tier), provider: provider, rng: SeededRNG(seed: seed))
            await s.hatchIfNeeded()
            if let active = s.state.active { result.append(active) }
        }
        return result
    }

    private func inRegionShare(_ hatched: [MonState], _ region: PokedexRegion) -> Double {
        Double(hatched.filter { region.dexRange.contains($0.baseID) }.count) / Double(max(1, hatched.count))
    }

    /// The seeds are fixed, so this is not a flaky statistical test: the band only has to be narrow
    /// enough to reject "no bias" (0.20 here) and wide enough for 200 draws (σ ≈ 0.028).
    private func assertIncenseShare(_ value: Double, _ message: String, line: UInt = #line) {
        XCTAssertEqual(value, share, accuracy: 0.08, message, line: line)
    }

    /// Polls with a real sleep: the work waited for hops off the main actor, so yields alone can spin
    /// through their budget before it comes back.
    private func waitUntil(_ condition: () async -> Bool) async {
        for _ in 0..<2000 {
            if await condition() { return }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }

    private func waitForPreRoll(_ s: CompanionStore) async {
        await waitUntil { s.state.pendingHatchID != nil }
    }

    /// What the refresh tick does for a ready egg, until it hatches. A pre-roll started elsewhere may
    /// hold the lock for a moment, so one call is not always enough.
    private func hatchWhenReady(_ s: CompanionStore) async {
        await waitUntil {
            await s.hatchIfNeeded()
            return s.state.active != nil
        }
    }

    // MARK: ① the rescale is exactly the stated share

    func testBiasedWeightsGiveTheRegionExactlyTheStatedShare() throws {
        // Realistic weights: capture rates, some already halved for collected species.
        let weights = [255, 127, 190, 45, 3, 100, 22, 255]
        let inRegion = [true, false, true, false, false, true, false, false]
        let biased = try XCTUnwrap(RegionalIncense.biasedWeights(weights, inRegion: inRegion))
        let inTotal = zip(biased, inRegion).filter { $0.1 }.map { $0.0 }.reduce(0, +)
        let total = biased.reduce(0, +)
        XCTAssertEqual(inTotal * 100, total * RegionalIncense.inRegionSharePercent,
                       "in-region weight must be exactly the stated share of the total")
        // Inside a group the ratios stay: capture rate and the collected ½ still pick the species.
        for i in weights.indices {
            for j in weights.indices where inRegion[i] == inRegion[j] {
                XCTAssertEqual(biased[i] * weights[j], biased[j] * weights[i], "ratio \(i):\(j) changed")
            }
        }
    }

    func testBiasedWeightsReportsAnEmptyRegionInsteadOfInventingOne() {
        XCTAssertNil(RegionalIncense.biasedWeights([255, 100], inRegion: [false, false]))
        XCTAssertNil(RegionalIncense.biasedWeights([], inRegion: []))
    }

    func testBiasedWeightsLeavesAnAllInRegionPoolUnchanged() {
        XCTAssertEqual(RegionalIncense.biasedWeights([255, 100, 3], inRegion: [true, true, true]), [255, 100, 3])
    }

    // MARK: ② the weighted roll applies it (with a control group)

    func testIncenseShiftsHatchesToItsRegionForEveryRegion() async {
        let control = await hatches(incense: nil)
        XCTAssertEqual(control.count, 200)
        for region in PokedexRegion.allCases {
            let hatched = await hatches(incense: region)
            XCTAssertEqual(hatched.count, 200, "every egg must hatch or the share is measured on a subset")
            assertIncenseShare(inRegionShare(hatched, region), "\(region) incense")
            XCTAssertLessThan(inRegionShare(control, region), 0.35,
                              "without an incense \(region) must stay near its natural 1/5, or this test proves nothing")
        }
    }

    /// Stacking: the grade is still a guarantee, and the region share holds inside it.
    func testIncenseStacksWithEveryEggGrade() async {
        for tier in [Rarity.uncommon, .rare] {
            let hatched = await hatches(incense: .hoenn, tier: tier)
            XCTAssertEqual(hatched.count, 200)
            for mon in hatched {
                XCTAssertGreaterThanOrEqual(mon.rarity.sortRank, tier.sortRank, "\(tier) egg hatched \(mon.rarity)")
            }
            assertIncenseShare(inRegionShare(hatched, .hoenn), "hoenn incense on a \(tier) egg")
        }
    }

    /// Duplicates stay allowed: a collected species keeps its ½ weight and can still hatch.
    func testCollectedSpeciesInTheRegionCanStillHatch() async {
        let kantoIDs = RegionPoolProvider.pool().map(\.id).filter { PokedexRegion.kanto.dexRange.contains($0) }
        let collected = kantoIDs.map { "\"\($0):\($0)\"" }.joined(separator: ",")
        var hatched: [MonState] = []
        for seed in UInt64(1)...200 {
            let f = url()
            let json = "{\"installBaselineSet\":true,\"usedSinceInstall\":1,\"spentTokens\":0,\"lastDate\":\"d\","
                + "\"dex\":[],\"collectedFinals\":[\(collected)],\(readyEgg(incense: .kanto))}"
            try? json.data(using: .utf8)!.write(to: f)
            let s = CompanionStore(provider: RegionPoolProvider(entries: RegionPoolProvider.pool()),
                                   clock: { self.now }, fileURL: f, rng: SeededRNG(seed: seed))
            await s.hatchIfNeeded()
            if let active = s.state.active { hatched.append(active) }
        }
        assertIncenseShare(inRegionShare(hatched, .kanto), "a fully collected region still holds the share")
        XCTAssertTrue(hatched.contains { $0.hasGrowthBoost }, "a collected Kanto species hatched again")
    }

    // MARK: ③ the REST fallback alone

    func testRestFallbackAppliesTheIncense() async {
        let hatched = await hatches(incense: .kanto, provider: RestOnlyRegionProvider())
        XCTAssertGreaterThan(hatched.count, 190, "the fallback must run or nothing is checked")
        assertIncenseShare(inRegionShare(hatched, .kanto), "REST fallback")
        let control = await hatches(incense: nil, provider: RestOnlyRegionProvider())
        XCTAssertLessThan(inRegionShare(control, .kanto), 0.35, "control: REST without an incense stays near 151/649")
    }

    func testRestFallbackKeepsTheGradeGuaranteeUnderAnIncense() async {
        let hatched = await hatches(incense: .sinnoh, tier: .rare, provider: RestOnlyRegionProvider())
        XCTAssertGreaterThan(hatched.count, 150)
        for mon in hatched { XCTAssertEqual(mon.rarity, .rare) }
        assertIncenseShare(inRegionShare(hatched, .sinnoh), "REST fallback on a rare egg")
    }

    /// The in-region branch draws ids from the region's own range. Draws: 0 → below the share, then
    /// 5 → the sixth id of 1...151.
    func testRestFallbackInRegionBranchSamplesTheRegionRange() async {
        let s = store(readyEgg(incense: .kanto), provider: RestOnlyRegionProvider(), rng: ScriptedRNG([0, 5]))
        await s.hatchIfNeeded()
        XCTAssertEqual(s.state.active?.baseID, 6)
        XCTAssertNil(s.state.pendingIncense, "a biased roll spends the incense whichever branch it took")
    }

    /// The other branch must stay out of the region, or the share creeps above what the shop states.
    /// Draws: 99 → not below the share; 0 → id 1 (Kanto, skipped); 199 → id 200 (Johto).
    func testRestFallbackOutOfRegionBranchSkipsTheRegion() async {
        let s = store(readyEgg(incense: .kanto), provider: RestOnlyRegionProvider(), rng: ScriptedRNG([99, 0, 199]))
        await s.hatchIfNeeded()
        XCTAssertEqual(s.state.active?.baseID, 200)
        XCTAssertNil(s.state.pendingIncense, "the 1-in-5 miss is still the incense's roll")
    }

    // MARK: ④ the species is rolled before the hatch

    /// An incubating egg already holds a species. Lighting an incense must drop it and roll again.
    func testIncenseOnAnIncubatingEggDropsItsPreRoll() async {
        let johtoID = PokedexRegion.johto.dexRange.lowerBound
        let s = store("\"active\":null,\"eggUsage\":0,\"pendingHatchID\":\(johtoID),"
                      + "\"inventory\":{\"kantoIncense\":1}")
        XCTAssertEqual(s.state.pendingHatchID, johtoID)
        XCTAssertTrue(s.useIncense(.kantoIncense))
        XCTAssertNil(s.state.pendingHatchID, "the species rolled before the incense must not hatch")
        XCTAssertEqual(s.state.pendingIncense, .kanto)
        await waitForPreRoll(s)
        XCTAssertNotNil(s.state.pendingHatchID, "a new species is rolled for the same egg")
        XCTAssertEqual(s.state.pendingHatchIncense, .kanto, "and that roll was made under the incense")
    }

    /// A roll already in flight was started without the incense. It must be discarded, not hatched.
    /// The REST path is the one that can do this: it reads the incense before its network waits.
    func testIncenseLitDuringARollDiscardsThatRoll() async {
        let provider = HeldRestProvider()
        let s = store(readyEgg(incense: nil) + ",\"inventory\":{\"kantoIncense\":1}", provider: provider)
        let hatch = Task { await s.hatchIfNeeded() }
        await waitUntil { await provider.isHolding() }
        let holding = await provider.isHolding()
        XCTAssertTrue(holding, "the roll must be in flight when the incense is lit")
        XCTAssertTrue(s.useIncense(.kantoIncense))
        await provider.release()
        await hatch.value
        XCTAssertNil(s.state.active, "the roll made without the incense must not hatch this egg")
        XCTAssertEqual(s.state.pendingIncense, .kanto)

        await hatchWhenReady(s)   // the next ticks
        XCTAssertNotNil(s.state.active)
        XCTAssertNil(s.state.pendingIncense, "the new roll was made under the incense and spent it")
    }

    /// While a Pokémon is growing there is no egg to roll: the incense waits, across a restart, for the
    /// egg that comes next.
    func testIncenseLitWhileRaisingWaitsForTheNextEgg() async {
        let f = url()
        let s = store("\"active\":\(Self.mon),\"inventory\":{\"unovaIncense\":1}", at: f)
        XCTAssertTrue(s.useIncense(.unovaIncense))
        XCTAssertNotNil(s.state.active, "lighting an incense does not touch the Pokémon being raised")
        XCTAssertNil(s.state.pendingHatchID)

        let restarted = CompanionStore(provider: RegionPoolProvider(entries: RegionPoolProvider.pool()),
                                       clock: { self.now }, fileURL: f, rng: SeededRNG(seed: 7))
        XCTAssertEqual(restarted.burningIncense, .unova, "the incense survives a restart")

        XCTAssertTrue(restarted.buyEgg(.rare))
        XCTAssertEqual(restarted.state.pendingIncense, .unova, "buying the egg does not spend it")
        await waitForPreRoll(restarted)
        XCTAssertEqual(restarted.state.pendingHatchIncense, .unova, "the new egg is rolled under it")
    }

    // MARK: ⑤ spent by the hatch it biased, and only by that one

    func testHatchSpendsTheIncenseAndTheNextEggIsUnbiased() async {
        let s = store(readyEgg(incense: .johto))
        await s.hatchIfNeeded()
        let active = try? XCTUnwrap(s.state.active)
        XCTAssertNil(s.state.pendingIncense, "spent by the hatch")
        XCTAssertNil(s.state.pendingHatchIncense)
        XCTAssertNil(s.burningIncense)

        s.applyUsage(PokemonBalance.graduationTotal(active?.rarity ?? .common) * 2)   // single form → graduates
        XCTAssertNil(s.state.active)
        await waitForPreRoll(s)
        XCTAssertNotNil(s.state.pendingHatchID)
        XCTAssertNil(s.state.pendingHatchIncense, "the next egg is rolled with no incense")
    }

    /// No candidate in the region: the hatch goes ahead and the incense is kept. This is the opposite
    /// of a graded egg, which keeps the egg and rolls again.
    func testEmptyRegionPoolHatchesNormallyAndKeepsTheIncense() async {
        let provider = RegionPoolProvider(entries: RegionPoolProvider.pool(without: [.sinnoh]))
        let s = store(readyEgg(incense: .sinnoh) + ",\"inventory\":{\"sinnohIncense\":2}", provider: provider)
        await s.hatchIfNeeded()
        XCTAssertNotNil(s.state.active, "a region is a bias, not a guarantee: the egg still hatches")
        XCTAssertEqual(s.state.pendingIncense, .sinnoh, "an incense that biased nothing is not spent")
        XCTAssertEqual(s.itemCount(.sinnohIncense), 2)
        XCTAssertFalse(s.canUseIncense(.sinnohIncense), "it is still the one that burns")
    }

    /// The same path through the grade filter, which is how a real pool can run dry: the region has
    /// species, but none of the egg's grade. The incense then waits for an egg it can bias.
    func testIncenseKeptWhenTheGradeEmptiesTheRegionThenSpentOnTheNextEgg() async {
        let provider = RegionPoolProvider(entries: RegionPoolProvider.pool(commonOnly: [.kanto]))
        let s = store(readyEgg(incense: .kanto, tier: .rare), provider: provider)
        await s.hatchIfNeeded()
        let active = try? XCTUnwrap(s.state.active)
        XCTAssertEqual(active?.rarity, .rare, "the grade guarantee is kept")
        XCTAssertFalse(PokedexRegion.kanto.dexRange.contains(active?.baseID ?? 1))
        XCTAssertEqual(s.state.pendingIncense, .kanto)

        s.applyUsage(PokemonBalance.graduationTotal(.rare) * 2)
        XCTAssertNil(s.state.active)
        await waitForPreRoll(s)
        XCTAssertEqual(s.state.pendingHatchIncense, .kanto, "the plain egg that follows has Kanto candidates")
    }

    /// The grade gate throws a pre-roll away and rolls again. The incense must still be there for
    /// that second roll.
    func testGradeGateRerollKeepsTheIncense() async {
        let s = store(readyEgg(incense: .kanto, tier: .rare), provider: StaleKantoIndexProvider())
        await s.hatchIfNeeded()
        XCTAssertNil(s.state.active, "below the guarantee: no hatch")
        XCTAssertNil(s.state.pendingHatchID)
        XCTAssertNil(s.state.pendingHatchIncense)
        XCTAssertEqual(s.state.pendingIncense, .kanto, "a discarded roll does not spend the incense")
    }

    // MARK: one incense at a time

    func testOnlyOneIncenseBurnsAtATime() {
        let s = store("\"active\":\(Self.mon),\"inventory\":{\"kantoIncense\":2,\"johtoIncense\":1}")
        XCTAssertTrue(s.canUseIncense(.kantoIncense))
        XCTAssertTrue(s.useIncense(.kantoIncense))
        XCTAssertEqual(s.itemCount(.kantoIncense), 1)

        XCTAssertFalse(s.canUseIncense(.kantoIncense), "same region")
        XCTAssertFalse(s.canUseIncense(.johtoIncense), "another region")
        XCTAssertFalse(s.useIncense(.kantoIncense))
        XCTAssertFalse(s.useIncense(.johtoIncense))
        XCTAssertEqual(s.itemCount(.kantoIncense), 1, "a blocked use spends nothing")
        XCTAssertEqual(s.itemCount(.johtoIncense), 1)
        XCTAssertEqual(s.burningIncense, .kanto, "and does not replace the one burning")
    }

    func testIncenseNeedsStockAndIsNotAnotherItem() {
        let s = store("\"active\":\(Self.mon),\"inventory\":{\"mint\":1}")
        XCTAssertFalse(s.useIncense(.hoennIncense), "none owned")
        XCTAssertFalse(s.useIncense(.mint), "a Mint is not an incense")
        XCTAssertNil(s.burningIncense)
        XCTAssertEqual(s.itemCount(.mint), 1)
    }

    // MARK: the whole flow, through the calls the views make

    func testBuyBurnHatchFlow() async {
        let s = store("\"active\":\(Self.mon)")
        XCTAssertTrue(s.buy(.kantoIncense, count: 2))
        XCTAssertEqual(s.state.spentTokens, 2 * RegionalIncense.price)
        XCTAssertEqual(s.ownedItems.map(\.kind), [.kantoIncense])

        XCTAssertTrue(s.useIncense(.kantoIncense))
        XCTAssertFalse(s.useIncense(.kantoIncense), "blocked while one burns")
        XCTAssertEqual(s.itemCount(.kantoIncense), 1)

        XCTAssertTrue(s.buyEgg(nil))
        XCTAssertEqual(s.burningIncense, .kanto, "still burning over the new egg")
        // The first refresh only sets each provider's baseline; the second one is usage.
        s.update(todayTokensByProvider: ["test": 0], todayDate: "d", monthTotal: 0, burnTier: .idle,
                 limitWarning: false, hasUsageData: true)
        s.update(todayTokensByProvider: ["test": PokemonBalance.eggHatchThreshold], todayDate: "d", monthTotal: 0,
                 burnTier: .idle, limitWarning: false, hasUsageData: true)
        XCTAssertGreaterThanOrEqual(s.state.eggUsage, s.eggHatchThreshold, "the usage reached the egg")
        await hatchWhenReady(s)
        XCTAssertNotNil(s.state.active, "the egg hatched")
        XCTAssertNil(s.burningIncense, "the hatch spent the incense")
        XCTAssertTrue(s.canUseIncense(.kantoIncense), "the second one can be lit now")
    }

    // MARK: saves

    func testOldSaveWithoutIncenseFieldsDecodes() throws {
        let json = "{\"installBaselineSet\":true,\"usedSinceInstall\":5,\"inventory\":{\"mint\":2}}"
        let state = try JSONDecoder().decode(CompanionState.self, from: json.data(using: .utf8)!)
        XCTAssertNil(state.pendingIncense)
        XCTAssertNil(state.pendingHatchIncense)
        XCTAssertEqual(state.inventory["mint"], 2, "the rest of the save is intact")
    }

    /// An unknown region must not become a bias nobody bought, and must not cost the rest of the save.
    func testUnknownRegionDecodesAsNoIncense() throws {
        let json = "{\"usedSinceInstall\":5,\"pendingIncense\":\"orre\",\"pendingHatchIncense\":7}"
        let state = try JSONDecoder().decode(CompanionState.self, from: json.data(using: .utf8)!)
        XCTAssertNil(state.pendingIncense)
        XCTAssertNil(state.pendingHatchIncense)
        XCTAssertEqual(state.usedSinceInstall, 5)
    }

    func testIncenseFieldsRoundTrip() throws {
        var state = CompanionState()
        state.pendingIncense = .hoenn
        state.pendingHatchID = 252
        state.pendingHatchIncense = .hoenn
        let decoded = try JSONDecoder().decode(CompanionState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(decoded.pendingIncense, .hoenn)
        XCTAssertEqual(decoded.pendingHatchIncense, .hoenn)
    }

    /// A pre-roll cannot exist beside an active Pokémon, so its incense mark goes with it. The burning
    /// incense itself stays: it may wait while a Pokémon grows.
    func testSanitizedDropsThePreRollMarkButKeepsTheBurningIncense() throws {
        let json = "{\"active\":\(Self.mon),\"pendingHatchID\":4,\"pendingHatchIncense\":\"kanto\","
            + "\"pendingIncense\":\"kanto\"}"
        let state = try JSONDecoder().decode(CompanionState.self, from: json.data(using: .utf8)!)
        let clean = SaveTransfer.sanitized(state)
        XCTAssertNil(clean.pendingHatchID)
        XCTAssertNil(clean.pendingHatchIncense)
        XCTAssertEqual(clean.pendingIncense, .kanto)
    }

    // MARK: shop, sprites, names

    func testEveryRegionHasOneIncenseAtThePriceOfAPlainEgg() {
        XCTAssertEqual(incenses.compactMap(\.incenseRegion), PokedexRegion.allCases)
        for kind in incenses {
            XCTAssertEqual(kind.shopPrice, 1_000_000_000)
            XCTAssertEqual(kind.shopPrice, FreshEgg.price)
            XCTAssertFalse(kind.isPassive)
        }
        for kind in [ItemKind.rareCandy, .mint, .shinyCharm] { XCTAssertNil(kind.incenseRegion) }
    }

    func testIncensesBorrowTheAgreedSprites() {
        XCTAssertEqual(incenses.map(\.spriteName),
                       ["full-incense", "luck-incense", "wave-incense", "pure-incense", "rock-incense"])
    }

    /// The canon names of the borrowed sprites must never reach the player.
    func testIncensesAreNamedAfterTheirRegionInEveryLanguage() {
        XCTAssertEqual(incenses.map { L(.en).itemName($0) },
                       ["Kanto Incense", "Johto Incense", "Hoenn Incense", "Sinnoh Incense", "Unova Incense"])
        for language in AppLanguage.allCases {
            let l = L(language)
            for kind in incenses {
                let region = l.regionName(kind.incenseRegion!)
                XCTAssertTrue(l.itemName(kind).contains(region), "\(language) \(kind)")
                XCTAssertTrue(l.itemDescription(kind).contains(region), "\(language) \(kind)")
                // Shop text describes the effect in words, like the Shiny Charm: no odds, no numbers.
                for text in [l.itemDescription(kind), l.incenseEffectHint(kind.incenseRegion!)] {
                    XCTAssertNil(text.rangeOfCharacter(from: .decimalDigits), "\(language) \(kind): \(text)")
                    XCTAssertFalse(text.contains("%"), "\(language) \(kind): \(text)")
                }
                XCTAssertTrue(l.incenseEffectHint(kind.incenseRegion!).contains(region), "\(language) \(kind)")
                XCTAssertTrue(l.incenseBurning(kind.incenseRegion!).contains(l.itemName(kind)))
                XCTAssertTrue(l.incenseAlreadyBurning(kind.incenseRegion!).contains(l.itemName(kind)))
                XCTAssertTrue(l.notifIncenseKeptBody(kind.incenseRegion!).contains(l.itemName(kind)))
            }
            XCTAssertFalse(l.incenseUseConfirm.isEmpty)
            XCTAssertFalse(l.notifIncenseKeptTitle.isEmpty)
        }
    }

    /// Five items share one price with the plain egg. The order must be the same on every render.
    func testIncensesKeepRegionOrderInTheShop() {
        let s = store("\"active\":\(Self.mon)")
        for _ in 0..<20 {
            XCTAssertEqual(s.purchasableItems, [.mint, .rareCandy] + incenses + [.shinyCharm])
            XCTAssertEqual(s.shopEntries,
                           [.item(.mint), .item(.rareCandy)] + incenses.map { ShopEntry.item($0) }
                           + [.egg(nil), .egg(.uncommon), .item(.shinyCharm), .egg(.rare)])
        }
    }

    // MARK: price

    /// The incense must beat what it replaces: rerolling plain eggs until the region comes up.
    ///
    /// Asserting the price constant alone would be a tautology, so the comparison uses the pool as
    /// measured: capture-rate sums per region over the live base index (PokéAPI, 328 bases with Ditto
    /// excluded, 2026-11-16), the same weights `chooseBase` uses with nothing collected.
    func testIncenseBeatsRerollingPlainEggsForEveryRegion() {
        let measured: [PokedexRegion: Int] = [.kanto: 10_262, .johto: 6_210, .hoenn: 10_780,
                                              .sinnoh: 5_516, .unova: 10_999]
        let total = measured.values.reduce(0, +)
        XCTAssertEqual(total, 43_767)
        // One incense and the egg it is used on, repeated until the region comes up.
        let incenseCost = Double(RegionalIncense.price + FreshEgg.price) / share
        for region in PokedexRegion.allCases {
            let naturalShare = Double(measured[region]!) / Double(total)
            let rerollCost = Double(FreshEgg.price) / naturalShare
            XCTAssertLessThan(incenseCost, rerollCost, "\(region): rerolling plain eggs is cheaper than the incense")
        }
    }
}
