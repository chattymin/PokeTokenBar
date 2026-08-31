import XCTest
@testable import PokeDexBar

/// 원종과 지방 모습의 진화 조건이 다른 갈래 — 모래사원·야도란·붐볼·불카모스 네 종.
///
/// PokéAPI 는 이 넷을 **한 갈래에 조건 두 개**로 준다(레벨 22 그리고 얼음의돌). 어느 쪽이
/// 누구 것인지는 응답에 안 적혀 있어서, 하나로 접으면 한쪽이 통째로 사라진다.
@MainActor
final class RegionalRequirementTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeStore() -> PlayerStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("rr-\(UUID().uuidString).json")
        return PlayerStore(fileURL: url, rng: SeededRNG(seed: 1), now: { self.now })
    }

    /// 모래두지의 실제 응답 모양 — 한 갈래(#28)에 레벨 22 와 얼음의돌이 함께 온다.
    private func sandshrewDetails() -> [EvolutionDetail] {
        [EvolutionDetail(trigger: NamedRef(name: "level-up", url: nil), item: nil,
                         held_item: nil, min_happiness: nil, min_level: 22, gender: nil),
         EvolutionDetail(trigger: NamedRef(name: "use-item", url: nil),
                         item: NamedRef(name: "ice-stone", url: nil),
                         held_item: nil, min_happiness: nil, min_level: nil, gender: nil)]
    }

    private func sandshrewLine() -> EvoLine {
        let details = sandshrewDetails()
        let child = EvoNode(speciesID: 28, children: [],
                            requirementRaw: PokeAPIClient.requirement(from: details, speciesID: 28,
                                                                     parentLevel: 1),
                            regionalRequirementRaw: PokeAPIClient.regionalRequirement(from: details))
        return EvoLine(baseID: 27, tree: EvoNode(speciesID: 27, children: [child]),
                       rarity: .common, names: [:])
    }

    private func sandshrew(region: Region?) -> Individual {
        var made = Individual(baseID: 27, speciesID: 27, pathIDs: [27], nature: .hardy,
                              obtainedAt: now, grade: .common)   // 레벨 1
        made.region = region
        return made
    }

    /// **관동 모래두지는 얼음의돌로 진화하지 않는다.** 도구를 레벨보다 먼저 집으면 레벨 22
    /// 조건이 통째로 사라져, 돌만 있으면 **레벨 1에** 진화한다(사용자 제보).
    func testAKantoSandshrewCannotEvolveAtLevelOneWithAStone() {
        let store = makeStore()
        let line = sandshrewLine()
        let kanto = sandshrew(region: nil)
        XCTAssertEqual(kanto.level, 1)
        store.mutate { $0.inventory[EvolutionItem.iceStone.rawValue] = 1 }

        XCTAssertEqual(store.requirement(for: 28, line: line, region: nil), .level(22))
        XCTAssertFalse(store.canEvolve(kanto, to: 28, line: line),
                       "관동 모래두지가 얼음의돌만으로 레벨 1에 진화한다")
        XCTAssertFalse(store.isReadyToEvolve(kanto, line: line), "배지도 같이 켜지면 안 된다")
    }

    /// 레벨 22 에 닿으면 돌 없이 진화한다 — **레벨 경로가 살아 있는지**(고치면서 막지 않았는지).
    func testAKantoSandshrewStillEvolvesByLevel() {
        let store = makeStore()
        var kanto = sandshrew(region: nil)
        kanto.exp = kanto.growthRate.totalExp(at: 22)
        XCTAssertGreaterThanOrEqual(kanto.level, 22)
        XCTAssertTrue(store.canEvolve(kanto, to: 28, line: sandshrewLine()),
                      "레벨을 채웠는데 진화가 막혔다")
    }

    /// **알로라 모래두지는 여전히 얼음의돌로 진화한다** — 한쪽만 고치면 반대쪽이 막힌다.
    func testAnAlolanSandshrewStillEvolvesWithTheStone() {
        let store = makeStore()
        let line = sandshrewLine()
        let alolan = sandshrew(region: .alola)
        XCTAssertEqual(store.requirement(for: 28, line: line, region: .alola),
                       .item(.iceStone))

        XCTAssertFalse(store.canEvolve(alolan, to: 28, line: line), "돌도 없는데 진화한다")
        store.mutate { $0.inventory[EvolutionItem.iceStone.rawValue] = 1 }
        XCTAssertTrue(store.canEvolve(alolan, to: 28, line: line), "알로라 경로가 막혔다")
    }

    /// 도구가 **유일한** 조건인 갈래(돌 진화 56갈래)는 그대로여야 한다 — 이 수정이 그쪽까지
    /// 건드리면 이브이 계열이 통째로 막힌다.
    func testAStoneOnlyBranchIsUntouched() {
        let details = [EvolutionDetail(trigger: NamedRef(name: "use-item", url: nil),
                                       item: NamedRef(name: "water-stone", url: nil),
                                       held_item: nil, min_happiness: nil, min_level: nil,
                                       gender: nil)]
        XCTAssertEqual(PokeAPIClient.requirement(from: details, speciesID: 134, parentLevel: 1),
                       .item("water-stone"))
        XCTAssertNil(PokeAPIClient.regionalRequirement(from: details),
                     "도구뿐인 갈래에 지방 조건이 생기면 안 된다")
    }

    /// 레벨만 있는 갈래도 그대로 — 지방 조건이 붙으면 안 된다.
    func testALevelOnlyBranchGetsNoRegionalOverride() {
        let details = [EvolutionDetail(trigger: NamedRef(name: "level-up", url: nil), item: nil,
                                       held_item: nil, min_happiness: nil, min_level: 16,
                                       gender: nil)]
        XCTAssertEqual(PokeAPIClient.requirement(from: details, speciesID: 2, parentLevel: 1),
                       .level(16))
        XCTAssertNil(PokeAPIClient.regionalRequirement(from: details))
    }

    /// **같은 줄 안의 레벨은 도구를 못 이긴다** — 기존 규칙(`testAnItemStillWinsOverALevel`)이
    /// 그대로여야 한다. 두 경우를 뭉뚱그려 고치면 그 규칙이 조용히 뒤집힌다(실제로 한 번 깼다).
    /// 실제 응답에 이런 줄은 0건이지만, 규칙이 뒤집히는 것 자체가 결함이다.
    func testALevelInsideTheSameDetailStillLosesToTheItem() {
        let one = [EvolutionDetail(trigger: NamedRef(name: "level-up", url: nil),
                                   item: NamedRef(name: "fire-stone", url: nil),
                                   held_item: nil, min_happiness: nil, min_level: 30, gender: nil)]
        XCTAssertEqual(PokeAPIClient.requirement(from: one, speciesID: 4, parentLevel: 1),
                       .item("fire-stone"), "같은 줄인데 레벨이 도구를 이겼다")
        XCTAssertNil(PokeAPIClient.regionalRequirement(from: one),
                     "같은 줄짜리에 지방 조건이 생기면 안 된다")
        // 줄이 갈리면 반대 — 그때만 레벨이 원종의 것이 된다.
        XCTAssertEqual(PokeAPIClient.requirement(from: sandshrewDetails(), speciesID: 28,
                                                 parentLevel: 1), .level(22))
    }

    /// 지방 조건이 트리를 다시 만드는 자리에서 새지 않는다 — 여기서 새면 **모든 라인에서** 샌다
    /// (성별 제한이 같은 자리에서 샜던 부류).
    func testTheRegionalRequirementSurvivesTreePruning() throws {
        let line = sandshrewLine()   // EvoLine.init 이 keepingSupportedSpecies 를 지난다
        let node = try XCTUnwrap(line.tree.node(withID: 28))
        XCTAssertEqual(node.regionalRequirementRaw, .item("ice-stone"),
                       "가지치기가 지방 조건을 떨어뜨렸다")
        XCTAssertEqual(node.requirementRaw, .level(22))
    }
}
