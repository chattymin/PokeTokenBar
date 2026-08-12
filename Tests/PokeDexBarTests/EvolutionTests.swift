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

    /// 구구 → 피죤 → 피죤투 (일직선). 같은 종 개체 두 마리가 서로 독립적으로 진화하는지 확인하는 데 쓴다.
    private func pidgeyLine() -> EvoLine {
        EvoLine(baseID: 16,
                tree: EvoNode(speciesID: 16, children: [
                    EvoNode(speciesID: 17, children: [EvoNode(speciesID: 18, children: [])]),
                ]),
                rarity: .common, names: [:])
    }

    private func partner(of store: PlayerStore) -> Individual { store.state.partner! }

    /// 파트너의 경험치를 직접 끌어올린다. 진화는 이제 경험치 임계가 아니라 조건(레벨·도구·
    /// 친밀도 등, `canEvolve(_:to:line:)`)이 게이트라 대부분의 테스트에서 값 자체는 의미가
    /// 없다 — 이 스위트가 보는 것은 진화 자체의 동작이지 토큰→경험치 환산이 아니므로, 경험치는
    /// (필요한 곳에서만) 직접 꽂는다.
    private func giveExp(_ store: PlayerStore, _ amount: Int) {
        guard let index = store.state.box.firstIndex(where: { $0.id == store.state.partnerID })
        else { return }
        store.mutate { $0.box[index].exp = amount }
    }

    // MARK: 진화

    /// 진화는 경로만 진전시킨다 — **경험치를 깎지 않는다.** `bulbaLine()` 은 조건 없는(`.none`)
    /// 라인이라 얼마를 들고 있든 그대로 이월된다(옛 임계 초과분 이월은 Task 7 로 없어졌다).
    func testEvolvingAdvancesPathAndKeepsExperience() {
        let store = makeStore()
        store.chooseStarter(speciesID: 1, grade: .common)
        giveExp(store, 60_000_000)
        XCTAssertTrue(store.evolve(individualID: partner(of: store).id, to: 2, line: bulbaLine()))
        let p = partner(of: store)
        XCTAssertEqual(p.speciesID, 2)
        XCTAssertEqual(p.pathIDs, [1, 2])
        XCTAssertEqual(p.exp, 60_000_000, "진화가 경험치를 깎았다")
        XCTAssertTrue(store.state.dex.contains(2), "진화한 형태도 도감에 등록된다")
    }

    /// 조건(여기선 레벨)을 못 채우면 진화하지 않는다 — UI 가 실수로 불러도 상태가 변하면 안 된다.
    /// `bulbaLine()` 은 조건 없는 라인이라 여기서만 레벨 조건을 실은 별도 라인을 쓴다.
    func testEvolveRejectedWithoutMeetingTheRequirement() {
        let store = makeStore()
        store.chooseStarter(speciesID: 1, grade: .common)
        let levelGatedLine = EvoLine(baseID: 1,
                                     tree: EvoNode(speciesID: 1, children: [
                                         EvoNode(speciesID: 2, children: [], requirementRaw: .level(16)),
                                     ]),
                                     rarity: .rare, names: [:])
        XCTAssertFalse(store.evolve(individualID: partner(of: store).id, to: 2, line: levelGatedLine))
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
        let eevee = Individual(baseID: 133, speciesID: 133, pathIDs: [133],
                               nature: .serious, obtainedAt: now, grade: .rare)
        store.addForTesting(eevee)
        XCTAssertTrue(store.evolve(individualID: eevee.id, to: 135, line: eeveeLine()))
        let after = store.state.box.first { $0.id == eevee.id }!
        XCTAssertEqual(after.speciesID, 135)
        XCTAssertEqual(after.pathIDs, [133, 135])
    }

    // MARK: 개체 독립성 — 같은 종이라도 개체별로 진화 상태가 갈린다

    /// 구구 → 피죤(L18) 한 갈래짜리, 레벨로 막힌 라인. 개체 독립성 스위트가 "레벨을 채운
    /// 쪽만 진화 가능"을 보이는 데 쓴다.
    private func levelGatedPidgeyLine() -> EvoLine {
        EvoLine(baseID: 16,
                tree: EvoNode(speciesID: 16, children: [
                    EvoNode(speciesID: 17, children: [], requirementRaw: .level(18)),
                ]),
                rarity: .common, names: [:])
    }

    /// 구구 두 마리가 서로 다른 레벨을 쌓으면 한쪽만 진화 가능해야 한다.
    func testSameSpeciesIndividualsDivergeIndependently() {
        let store = makeStore()
        let line = levelGatedPidgeyLine()
        let ready = Individual(baseID: 16, speciesID: 16, pathIDs: [16], nature: .serious,
                               exp: GrowthRate.mediumFast.totalExp(at: 18),   // 조건 도달
                               obtainedAt: now, grade: .common)
        let notReady = Individual(baseID: 16, speciesID: 16, pathIDs: [16], nature: .jolly,
                                  exp: GrowthRate.mediumFast.totalExp(at: 17),   // 조건 미달
                                  obtainedAt: now, grade: .common)
        store.addForTesting(ready)
        store.addForTesting(notReady)

        XCTAssertTrue(store.canEvolve(ready, to: 17, line: line))
        XCTAssertFalse(store.canEvolve(notReady, to: 17, line: line))
    }

    /// 한쪽 구구를 진화시켜도 다른 쪽 구구는 그대로 남는다 — 종 단위가 아니라 개체 단위로 진화한다.
    func testEvolvingOneLeavesOtherUntouched() {
        let store = makeStore()
        let ready = Individual(baseID: 16, speciesID: 16, pathIDs: [16],
                               nature: .serious, obtainedAt: now, grade: .common)
        var notReady = Individual(baseID: 16, speciesID: 16, pathIDs: [16],
                                  nature: .jolly, obtainedAt: now, grade: .common)
        notReady.exp = 10_000_000
        store.addForTesting(ready)
        store.addForTesting(notReady)

        XCTAssertTrue(store.evolve(individualID: ready.id, to: 17, line: pidgeyLine()))

        let evolved = store.state.box.first { $0.id == ready.id }!
        let untouched = store.state.box.first { $0.id == notReady.id }!
        XCTAssertEqual(evolved.speciesID, 17)
        XCTAssertEqual(evolved.pathIDs, [16, 17])
        XCTAssertEqual(untouched.speciesID, 16, "다른 개체는 종이 바뀌면 안 된다")
        XCTAssertEqual(untouched.pathIDs, [16], "다른 개체는 경로가 바뀌면 안 된다")
        XCTAssertEqual(untouched.exp, 10_000_000, "다른 개체의 경험치도 그대로여야 한다")
        XCTAssertEqual(store.state.box.count, 2)
        XCTAssertNotEqual(evolved.id, untouched.id)
    }

    /// 진화 후에도 박스와 도감에 16 번(구구)과 17 번(피죤)이 동시에 존재해야 한다.
    func testBothFormsCoexistAfterEvolution() {
        let store = makeStore()
        let ready = Individual(baseID: 16, speciesID: 16, pathIDs: [16],
                               nature: .serious, obtainedAt: now, grade: .common)
        var notReady = Individual(baseID: 16, speciesID: 16, pathIDs: [16],
                                  nature: .jolly, obtainedAt: now, grade: .common)
        notReady.exp = 10_000_000
        store.addForTesting(ready)
        store.addForTesting(notReady)

        XCTAssertTrue(store.evolve(individualID: ready.id, to: 17, line: pidgeyLine()))

        XCTAssertTrue(store.state.box.contains { $0.speciesID == 16 })
        XCTAssertTrue(store.state.box.contains { $0.speciesID == 17 })
        XCTAssertTrue(store.state.dex.contains(16))
        XCTAssertTrue(store.state.dex.contains(17))
    }
}
