import XCTest
@testable import PokeDexBar

@MainActor
final class EvolutionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeStore() -> PlayerStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("evo-\(UUID().uuidString).json")
        return PlayerStore(fileURL: url, rng: SeededRNG(seed: 1), now: { self.now })
    }

    /// 이상해씨 → 이상해풀 → 이상해꽃 (일직선)
    private func bulbaLine() -> EvoLine {
        EvoLine(baseID: 1,
                tree: EvoNode(speciesID: 1, children: [
                    EvoNode(speciesID: 2, children: [EvoNode(speciesID: 3, children: [])]),
                ]),
                rarity: .rare, names: [:])
    }

    /// 이브이 → (샤미드 | 쥬피썬더) 분기
    private func eeveeLine() -> EvoLine {
        EvoLine(baseID: 133,
                tree: EvoNode(speciesID: 133, children: [
                    EvoNode(speciesID: 134, children: []),
                    EvoNode(speciesID: 135, children: []),
                ]),
                rarity: .rare, names: [:])
    }

    private func partner(of store: PlayerStore) -> Individual { store.state.partner! }

    private func giveExp(_ store: PlayerStore, _ amount: Int) {
        store.update(todayTokens: 0, todayDate: "d", hasUsageData: true)   // 기준선
        store.update(todayTokens: amount, todayDate: "d", hasUsageData: true)
    }

    // MARK: 임계 판정

    func testCannotEvolveBelowThreshold() {
        let store = makeStore()
        store.chooseStarter(speciesID: 1, grade: .common)
        giveExp(store, 49_999_999)
        XCTAssertFalse(store.canEvolve(partner(of: store)))
    }

    func testCanEvolveAtThreshold() {
        let store = makeStore()
        store.chooseStarter(speciesID: 1, grade: .common)
        giveExp(store, 50_000_000)
        XCTAssertTrue(store.canEvolve(partner(of: store)))
    }

    // MARK: 진화

    func testEvolvingAdvancesPathAndCarriesOverflow() {
        let store = makeStore()
        store.chooseStarter(speciesID: 1, grade: .common)
        giveExp(store, 60_000_000)
        XCTAssertTrue(store.evolve(individualID: partner(of: store).id, to: 2, line: bulbaLine()))
        let p = partner(of: store)
        XCTAssertEqual(p.speciesID, 2)
        XCTAssertEqual(p.pathIDs, [1, 2])
        XCTAssertEqual(p.exp, 10_000_000, "초과분은 다음 단계로 이월된다")
        XCTAssertTrue(store.state.dex.contains(2), "진화한 형태도 도감에 등록된다")
    }

    /// 임계에 못 미치면 진화하지 않는다 — UI 가 실수로 불러도 상태가 변하면 안 된다.
    func testEvolveRejectedBelowThreshold() {
        let store = makeStore()
        store.chooseStarter(speciesID: 1, grade: .common)
        giveExp(store, 1_000)
        XCTAssertFalse(store.evolve(individualID: partner(of: store).id, to: 2, line: bulbaLine()))
        XCTAssertEqual(partner(of: store).speciesID, 1)
    }

    /// 트리에 없는 종으로는 진화할 수 없다.
    func testEvolveRejectsUnreachableSpecies() {
        let store = makeStore()
        store.chooseStarter(speciesID: 1, grade: .common)
        giveExp(store, 60_000_000)
        XCTAssertFalse(store.evolve(individualID: partner(of: store).id, to: 25, line: bulbaLine()))
        XCTAssertEqual(partner(of: store).speciesID, 1)
    }

    /// 최종형은 진화 후보가 없다 — 배지가 뜨면 안 된다.
    func testFinalFormHasNoChoices() {
        let store = makeStore()
        store.chooseStarter(speciesID: 1, grade: .common)
        giveExp(store, 200_000_000)
        store.evolve(individualID: partner(of: store).id, to: 2, line: bulbaLine())
        store.evolve(individualID: partner(of: store).id, to: 3, line: bulbaLine())
        XCTAssertEqual(store.evolutionChoices(partner(of: store), line: bulbaLine()), [])
    }

    // MARK: 분기

    func testBranchOffersEveryChild() {
        let store = makeStore()
        store.addForTesting(Individual(baseID: 133, speciesID: 133, pathIDs: [133],
                                       nature: .serious, obtainedAt: now, grade: .rare))
        let eevee = store.state.box.last!
        XCTAssertEqual(store.evolutionChoices(eevee, line: eeveeLine()).sorted(), [134, 135])
    }

    /// 분기에서 고른 쪽만 경로에 남는다.
    func testBranchTakesTheChosenPath() {
        let store = makeStore()
        var eevee = Individual(baseID: 133, speciesID: 133, pathIDs: [133],
                               nature: .serious, obtainedAt: now, grade: .rare)
        eevee.exp = ExpBalance.threshold(grade: .rare, stageIndex: 0)
        store.addForTesting(eevee)
        XCTAssertTrue(store.evolve(individualID: eevee.id, to: 135, line: eeveeLine()))
        let after = store.state.box.first { $0.id == eevee.id }!
        XCTAssertEqual(after.speciesID, 135)
        XCTAssertEqual(after.pathIDs, [133, 135])
    }
}
