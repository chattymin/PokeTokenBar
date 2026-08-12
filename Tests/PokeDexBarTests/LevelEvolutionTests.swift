import XCTest
@testable import PokeDexBar

/// 진화가 레벨로 열린다.
@MainActor
final class LevelEvolutionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeStore() -> PlayerStore {
        PlayerStore(fileURL: FileManager.default.temporaryDirectory
                        .appendingPathComponent("evo-\(UUID().uuidString).json"),
                    rng: SeededRNG(seed: 1), now: { self.now })
    }

    /// 파이리 → 리자드(L16) 한 갈래짜리 라인.
    private func charmanderLine() -> EvoLine {
        EvoLine(baseID: 4,
                tree: EvoNode(speciesID: 4,
                              children: [EvoNode(speciesID: 5, children: [],
                                                 requirementRaw: .level(16))]),
                rarity: .common, names: [:])
    }

    private func add(_ store: PlayerStore, exp: Int, rate: GrowthRate = .mediumSlow) -> Individual {
        let individual = Individual(baseID: 4, speciesID: 4, pathIDs: [4], nature: .hardy,
                                    exp: exp, obtainedAt: now, grade: .common, growthRate: rate)
        store.addForTesting(individual)
        return individual
    }

    /// **레벨이 모자라면 못 한다.** L15 에서는 아직이다.
    func testBelowTheLevelItCannotEvolve() {
        let store = makeStore()
        let individual = add(store, exp: GrowthRate.mediumSlow.totalExp(at: 15))
        XCTAssertEqual(individual.level, 15)
        XCTAssertFalse(store.canEvolve(individual, to: 5, line: charmanderLine()))
        XCTAssertFalse(store.evolve(individualID: individual.id, to: 5, line: charmanderLine()))
        XCTAssertEqual(store.state.box.first?.speciesID, 4)
    }

    /// **레벨을 채우면 된다.** 대조군이 없으면 "항상 false" 구현도 위 테스트를 통과한다.
    func testAtTheLevelItEvolves() {
        let store = makeStore()
        let individual = add(store, exp: GrowthRate.mediumSlow.totalExp(at: 16))
        XCTAssertEqual(individual.level, 16)
        XCTAssertTrue(store.canEvolve(individual, to: 5, line: charmanderLine()))
        XCTAssertTrue(store.evolve(individualID: individual.id, to: 5, line: charmanderLine()))
        XCTAssertEqual(store.state.box.first?.speciesID, 5)
    }

    /// **진화해도 경험치는 안 깎인다.** 본가에서 진화는 레벨을 되돌리지 않는다.
    func testEvolvingKeepsTheExperience() {
        let store = makeStore()
        let exp = GrowthRate.mediumSlow.totalExp(at: 30)
        let individual = add(store, exp: exp)
        store.evolve(individualID: individual.id, to: 5, line: charmanderLine())

        XCTAssertEqual(store.state.box.first?.exp, exp, "진화가 경험치를 깎았다")
        XCTAssertEqual(store.state.box.first?.level, 30)
    }

    /// **진화해도 알 진행분은 안 깎인다.** 두 계량기가 서로를 안 건드린다는 주장의 반쪽이다.
    func testEvolvingKeepsTheEggProgress() {
        let store = makeStore()
        var individual = add(store, exp: GrowthRate.mediumSlow.totalExp(at: 20))
        individual.eggProgress = 123_456_789
        store.mutate { $0.box = [individual] }
        store.evolve(individualID: individual.id, to: 5, line: charmanderLine())

        XCTAssertEqual(store.state.box.first?.eggProgress, 123_456_789)
    }

    /// **도구 진화는 레벨을 안 본다** — 본가가 그렇다. 갓 부화한 개체도 돌만 있으면 된다.
    func testAnItemEvolutionIgnoresTheLevel() {
        let store = makeStore()
        let line = EvoLine(baseID: 4,
                           tree: EvoNode(speciesID: 4,
                                         children: [EvoNode(speciesID: 5, children: [],
                                                            requirementRaw: .item("fire-stone"))]),
                           rarity: .common, names: [:])
        let individual = add(store, exp: 0)
        XCTAssertEqual(individual.level, 1)
        XCTAssertFalse(store.canEvolve(individual, to: 5, line: line), "도구가 없는데 된다")

        store.mutate { $0.inventory["fire-stone"] = 1 }
        XCTAssertTrue(store.canEvolve(store.state.box.first!, to: 5, line: line))
    }

    /// **`.owns` — 만타인은 박스에 총어가 있어야 한다.**
    func testTheOwnsRequirementLooksAtTheBox() {
        let store = makeStore()
        let line = EvoLine(baseID: 458,
                           tree: EvoNode(speciesID: 458,
                                         children: [EvoNode(speciesID: 226, children: [],
                                                            requirementRaw: .owns(223))]),
                           rarity: .common, names: [:])
        let mantyke = Individual(baseID: 458, speciesID: 458, pathIDs: [458], nature: .hardy,
                                 obtainedAt: now, grade: .common)
        store.addForTesting(mantyke)
        XCTAssertFalse(store.canEvolve(mantyke, to: 226, line: line), "총어가 없는데 된다")

        store.addForTesting(Individual(baseID: 223, speciesID: 223, pathIDs: [223], nature: .hardy,
                                       obtainedAt: now, grade: .common))
        XCTAssertTrue(store.canEvolve(store.state.box.first!, to: 226, line: line))
    }

    /// **`.walked` — 함께한 시간 6시간.**
    func testTheWalkedRequirementUsesPartnerTime() {
        let store = makeStore()
        let line = EvoLine(baseID: 921,
                           tree: EvoNode(speciesID: 921,
                                         children: [EvoNode(speciesID: 923, children: [],
                                                            requirementRaw: .walked)]),
                           rarity: .common, names: [:])
        var pawmi = Individual(baseID: 921, speciesID: 921, pathIDs: [921], nature: .hardy,
                               obtainedAt: now, grade: .common)
        pawmi.partnerSeconds = EvoRequirement.walkSeconds - 1
        store.mutate { $0.box = [pawmi] }
        XCTAssertFalse(store.canEvolve(pawmi, to: 923, line: line), "1초 모자란데 된다")

        pawmi.partnerSeconds = EvoRequirement.walkSeconds
        store.mutate { $0.box = [pawmi] }
        XCTAssertTrue(store.canEvolve(pawmi, to: 923, line: line))
    }

    /// **토중몬이 아이스크가 되면 껍질몬이 박스에 하나 더 생긴다.**
    func testEvolvingNincadaAlsoLeavesAShedinja() {
        let store = makeStore()
        let line = EvoLine(baseID: 290,
                           tree: EvoNode(speciesID: 290,
                                         children: [EvoNode(speciesID: 291, children: [],
                                                            requirementRaw: .level(20))]),
                           rarity: .common, names: [:])
        var nincada = Individual(baseID: 290, speciesID: 290, pathIDs: [290], nature: .hardy,
                                 exp: GrowthRate.erratic.totalExp(at: 20), obtainedAt: now,
                                 grade: .common, growthRate: .erratic)
        nincada.id = UUID()
        store.mutate { $0.box = [nincada] }

        XCTAssertTrue(store.evolve(individualID: nincada.id, to: 291, line: line))
        XCTAssertEqual(store.state.box.count, 2, "껍질몬이 안 생겼다")
        XCTAssertTrue(store.state.box.contains { $0.speciesID == 292 })
        XCTAssertTrue(store.state.dex.contains(292), "도감에 껍질몬이 안 들어갔다")
        // 껍질몬은 `state.box[index]`(아이스크가 된 그 슬롯)를 통째로 복사해 만든다 — `id` 를
        // 새로 갈아 끼우지 않으면 두 개체가 같은 id 를 공유해, id 로 찾는 모든 경로(파트너 지정,
        // 박사에게 보내기, 재진화)가 둘 중 아무거나를 집거나 둘 다를 건드리는 식으로 어긋난다.
        XCTAssertEqual(Set(store.state.box.map(\.id)).count, store.state.box.count,
                       "껍질몬이 아이스크와 id 를 공유한다")
    }

    /// 껍질몬은 **토중몬일 때만** 생긴다 — 아무 진화에나 딸려 나오면 안 된다.
    func testOtherEvolutionsDoNotLeaveAShedinja() {
        let store = makeStore()
        let individual = add(store, exp: GrowthRate.mediumSlow.totalExp(at: 16))
        store.evolve(individualID: individual.id, to: 5, line: charmanderLine())
        XCTAssertEqual(store.state.box.count, 1)
    }

    /// 껍질몬은 **이싱카가 쌓은 파트너 시간·사탕 진행분을 물려받지 않는다.**
    ///
    /// 셀프리뷰에서 나온 위험 — 껍질몬은 `state.box[index]`(이 시점엔 이미 아이스크로 바뀐 값)를
    /// 통째로 복사해 만든다. `id`·`speciesID`·`eggProgress` 만 갈아 끼우고 나머지를 그대로 두면,
    /// 함께한 시간(`partnerSeconds`/`partnerSince`)과 사탕 진행분(`partnerTokens`/`candyProgress`)이
    /// 그대로 복사돼 방금 생긴 껍질몬이 이미 리본을 달고 사탕을 코앞에 둔 채 등장한다 — 실제로
    /// 함께한 적이 없는데 함께한 기록을 물려받는 부정 출발이다.
    func testShedinjaDoesNotInheritNincadasPartnerProgress() {
        let store = makeStore()
        let line = EvoLine(baseID: 290,
                           tree: EvoNode(speciesID: 290,
                                         children: [EvoNode(speciesID: 291, children: [],
                                                            requirementRaw: .level(20))]),
                           rarity: .common, names: [:])
        var nincada = Individual(baseID: 290, speciesID: 290, pathIDs: [290], nature: .hardy,
                                 exp: GrowthRate.erratic.totalExp(at: 20), obtainedAt: now,
                                 grade: .common, growthRate: .erratic)
        nincada.partnerSeconds = 999_999
        nincada.partnerSince = now
        nincada.partnerTokens = 42
        nincada.candyProgress = 12_345
        nincada.partnerStintsEnded = 3
        nincada.eggProgress = 555_555
        store.mutate { $0.box = [nincada] }

        XCTAssertTrue(store.evolve(individualID: nincada.id, to: 291, line: line))
        let shedinja = store.state.box.first { $0.speciesID == 292 }
        XCTAssertEqual(shedinja?.partnerSeconds, 0, "껍질몬이 이싱카의 파트너 시간을 물려받았다")
        XCTAssertNil(shedinja?.partnerSince, "껍질몬이 진행 중인 파트너 구간을 물려받았다")
        XCTAssertEqual(shedinja?.partnerTokens, 0, "껍질몬이 이싱카의 사탕 진행 토큰을 물려받았다")
        XCTAssertEqual(shedinja?.candyProgress, 0, "껍질몬이 이싱카의 사탕 진행분을 물려받았다")
        XCTAssertEqual(shedinja?.partnerStintsEnded, 0, "껍질몬이 이싱카의 파트너 교체 횟수를 물려받았다")
        // eggProgress 도 같은 부류의 "공짜 출발" 이다 — 이미 쌓인 알 진행분을 물려받으면 방금 생긴
        // 껍질몬이 부화 직전 상태로 등장한다.
        XCTAssertEqual(shedinja?.eggProgress, 0, "껍질몬이 이싱카의 알 진행분을 물려받았다")

        // 대조군 — 껍질몬을 낳은 아이스크 본체는 이싱카의 기록을 그대로 이어받아야 한다
        // (같은 개체가 진화한 것이지, 새로 생긴 것이 아니다).
        let ninjask = store.state.box.first { $0.speciesID == 291 }
        XCTAssertEqual(ninjask?.partnerSeconds, 999_999, "아이스크는 이싱카의 파트너 시간을 이어받아야 한다")
        XCTAssertEqual(ninjask?.partnerTokens, 42)
        XCTAssertEqual(ninjask?.eggProgress, 555_555, "아이스크는 이싱카의 알 진행분을 이어받아야 한다")
    }
}
