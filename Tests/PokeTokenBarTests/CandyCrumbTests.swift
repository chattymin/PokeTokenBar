import XCTest
@testable import PokeTokenBar

private func crumbLine(_ tree: EvoNode) -> EvoLine {
    func ids(_ n: EvoNode) -> [Int] { [n.speciesID] + n.children.flatMap(ids) }
    return EvoLine(baseID: tree.speciesID, tree: tree, rarity: .common,
                   names: Dictionary(uniqueKeysWithValues: ids(tree).map { ($0, ["en": "P\($0)"]) }))
}
private let oneStage = crumbLine(EvoNode(speciesID: 20, children: []))
private let threeStages = crumbLine(EvoNode(speciesID: 1, children: [EvoNode(speciesID: 2, children: [EvoNode(speciesID: 3, children: [])])]))

private struct FixedRNG: RandomNumberGenerator {
    let value: UInt64
    mutating func next() -> UInt64 { value }
}

/// A Rare Candy's EXP thrown away at a graduation leaves a crumb per tenth of a candy; a hundred make a Rare Candy.
@MainActor
final class CandyCrumbTests: XCTestCase {
    private func store(_ line: EvoLine = oneStage, candies: Int = 5, crumbs: Int = 0, items: [ItemKind] = [],
                       difficulty: Double = PokemonBalance.difficulty,
                       rng: any RandomNumberGenerator = SeededRNG(seed: 7)) -> CompanionStore {
        var st = CompanionState()
        st.installBaselineSet = true
        st.inventory = [ItemKind.rareCandy.rawValue: candies]
        for item in items { st.inventory[item.rawValue] = 1 }
        st.candyCrumbs = crumbs
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("crumbs-\(UUID().uuidString).json")
        try? JSONEncoder().encode(st).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return CompanionStore(provider: StubProvider(value: line), fileURL: url, rng: rng, difficulty: difficulty)
    }

    /// A fresh Common line takes 75M: a 100M candy throws 25M away, two crumbs, as its preview said.
    func testAFreshCommonLeavesTwoCrumbs() async throws {
        let s = store()
        await s.hatch(baseID: 20)
        let preview = try XCTUnwrap(s.planRareCandyUse(count: 1))
        XCTAssertEqual(preview.discardedXP, 25_000_000)
        XCTAssertEqual(preview.crumbs, 2)
        XCTAssertEqual(s.useRareCandy(), .graduated)
        XCTAssertEqual(s.state.candyCrumbs, 2)
        XCTAssertEqual(s.candyFeedbackCrumbs, 2)
        XCTAssertEqual(s.candyFeedbackCrumbCandies, 0)
        XCTAssertEqual(s.rareCandyCount, 4)
    }

    /// Rounded down at each graduation, the rest lost: 31M is 3 crumbs, 8M none, 50M (three candies) 5.
    func testEachTenthOfACandyThrownAwayIsACrumb() async throws {
        for (remaining, count, crumbs) in [(69_000_000, 1, 3), (92_000_000, 1, 0), (250_000_000, 3, 5)] {
            let s = store(difficulty: 1)
            await s.hatch(baseID: 20)
            s.applyUsage(750_000_000 - remaining)
            XCTAssertEqual(try XCTUnwrap(s.planRareCandyUse(count: count)).crumbs, crumbs, "\(remaining)")
            XCTAssertEqual(s.useRareCandy(count: count), .graduated)
            XCTAssertEqual(s.state.candyCrumbs, crumbs, "\(remaining)")
        }
    }

    /// The Soul Dew's 150M candy throws 75M away on a fresh Common: 7 crumbs, a tenth of a plain candy each.
    func testTheSoulDewsLargerCandyLeavesMoreCrumbs() async {
        let s = store(items: [.soulDew])
        await s.hatch(baseID: 20)
        XCTAssertEqual(s.useRareCandy(), .graduated)
        XCTAssertEqual(s.state.candyCrumbs, 7)
    }

    /// The hundredth crumb makes a Rare Candy at once; what is past it stays.
    func testAHundredCrumbsMakeARareCandy() async {
        let s = store(crumbs: 99)
        await s.hatch(baseID: 20)
        XCTAssertEqual(s.useRareCandy(), .graduated)
        XCTAssertEqual(s.state.candyCrumbs, 1)
        XCTAssertEqual(s.rareCandyCount, 5, "one used, one made")
        XCTAssertEqual(s.candyFeedbackCrumbs, 2)
        XCTAssertEqual(s.candyFeedbackCrumbCandies, 1)
    }

    /// A candy the Shock Drive recharged threw its EXP away all the same: its crumbs fall.
    func testAShockDriveRechargeStillLeavesCrumbs() async {
        let s = store(items: [.shockDrive], rng: FixedRNG(value: 0))
        await s.hatch(baseID: 20)
        XCTAssertEqual(s.useRareCandy(), .graduated)
        XCTAssertEqual(s.candyFeedbackRecharged, 1)
        XCTAssertEqual(s.state.candyCrumbs, 2)
    }

    /// An evolution carries the rest over: nothing thrown away, no crumb.
    func testAnEvolutionLeavesNoCrumb() async {
        let s = store(threeStages, difficulty: 1)
        await s.hatch(baseID: 1)
        XCTAssertEqual(s.useRareCandy(count: 2), .evolved)
        XCTAssertEqual(s.state.candyCrumbs, 0)
        XCTAssertEqual(s.candyFeedbackCrumbs, 0)
    }

    /// The Bag keeps the Rare Candy's card, at 0, while crumbs wait for the next candy.
    func testTheBagKeepsTheCandyCardWhileCrumbsWait() async {
        let s = store(candies: 1)
        await s.hatch(baseID: 20)
        XCTAssertEqual(s.useRareCandy(), .graduated)
        XCTAssertEqual(s.rareCandyCount, 0)
        XCTAssertFalse(s.ownedItems.contains { $0.kind == .rareCandy })
        XCTAssertEqual(s.bagItems.first?.kind, .rareCandy)
        XCTAssertEqual(s.bagItems.first?.count, 0)
        XCTAssertFalse(store(candies: 0).bagItems.contains { $0.kind == .rareCandy }, "no crumb, no card")
    }

    func testASaveWithoutCrumbsReadsZeroAndKeepsThem() throws {
        let json = #"{"installBaselineSet":true,"usedSinceInstall":5,"lastDate":"d","dex":[],"language":"ko"}"#
        XCTAssertEqual(try JSONDecoder().decode(CompanionState.self, from: Data(json.utf8)).candyCrumbs, 0)
        var st = CompanionState()
        st.candyCrumbs = 37
        XCTAssertEqual(try JSONDecoder().decode(CompanionState.self, from: JSONEncoder().encode(st)).candyCrumbs, 37)
    }

    /// An imported save's count is added to: a negative or huge one is brought back in range.
    func testAnImportedSavesCrumbsAreClamped() {
        var st = CompanionState()
        st.candyCrumbs = -5
        XCTAssertEqual(SaveTransfer.sanitized(st).candyCrumbs, 0)
        st.candyCrumbs = .max
        XCTAssertEqual(SaveTransfer.sanitized(st).candyCrumbs, SaveTransfer.maxItemCount)
    }
}
