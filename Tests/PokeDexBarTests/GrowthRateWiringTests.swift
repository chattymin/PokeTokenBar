import XCTest
@testable import PokeDexBar

/// 새로 만들어지는 개체가 자기 곡선을 갖고 태어나나.
@MainActor
final class GrowthRateWiringTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeStore() -> PlayerStore {
        PlayerStore(fileURL: FileManager.default.temporaryDirectory
                        .appendingPathComponent("gr-\(UUID().uuidString).json"),
                    rng: SeededRNG(seed: 1), now: { self.now })
    }

    /// **알이 성장 타입을 들고 있다가 부화한 개체에 넘긴다.**
    func testAHatchedIndividualInheritsTheEggsGrowthRate() {
        let store = makeStore()
        store.seedForTesting(wallet: 0, slots: 3, eggs: 0, at: now)
        let egg = store.placeEgg(grade: .common, speciesID: 4, shiny: false, growthRate: .mediumSlow)
        XCTAssertEqual(egg?.growthRate, .mediumSlow, "알이 성장 타입을 안 적었다")

        store.mutate { $0.eggs[0].hatchesAt = self.now.addingTimeInterval(-1) }
        let hatched = store.claimHatch(eggID: egg!.id, at: now)

        XCTAssertEqual(hatched?.growthRate, .mediumSlow, "부화한 개체가 물려받지 못했다")
    }

    /// **대조군** — 다른 값이면 다르게 실린다. 하나만 검사하면 하드코딩도 통과한다.
    func testADifferentGrowthRateArrivesDifferently() {
        let store = makeStore()
        store.seedForTesting(wallet: 0, slots: 3, eggs: 0, at: now)
        let egg = store.placeEgg(grade: .common, speciesID: 4, shiny: false, growthRate: .fluctuating)
        store.mutate { $0.eggs[0].hatchesAt = self.now.addingTimeInterval(-1) }

        XCTAssertEqual(store.claimHatch(eggID: egg!.id, at: now)?.growthRate, .fluctuating)
    }

    /// **박사의 제안도 후보의 성장 타입을 싣는다.**
    func testAProfessorOfferCarriesTheGrowthRate() {
        let store = makeStore()
        store.update(todayTokens: 0, todayDate: "2026-08-12", hasUsageData: true)
        let index = [BaseSpecies(id: 4, captureRate: 45, isLegendary: false, isMythical: false,
                                 growthRate: .mediumSlow)]
        store.refreshProfessorOffers(index: index)

        XCTAssertEqual(store.state.professorOffers.first?.individual.growthRate, .mediumSlow)
    }

    /// [회귀] **마이그레이션된 개체는 진화 전까지 곡선이 안 맞았다.** `growthRate` 갱신 자리가
    /// `evolve` 뿐이던 시절, 이미 최종형이거나 아직 안 진화한 개체는 그 자리를 영영 안 지나
    /// `.mediumFast` 에 갇혔다(레거시 전설이 실제로는 `slow` 인데도). 라인이 도착하면 여기서
    /// 바로잡는다.
    func testABoxMemberWithTheWrongCurveIsCorrectedWhenItsLineArrives() {
        let store = makeStore()
        let individual = Individual(baseID: 144, speciesID: 144, pathIDs: [144], nature: .hardy,
                                    obtainedAt: now, grade: .legendary, growthRate: .mediumFast)
        store.addForTesting(individual)
        let line = EvoLine(baseID: 144, tree: EvoNode(speciesID: 144, children: []),
                           rarity: .legendary, names: [:], growthRates: [144: .slow])

        store.backfillGrowthRates(from: line)

        XCTAssertEqual(store.state.box.first { $0.id == individual.id }?.growthRate, .slow,
                       "라인이 도착했는데 잘못된 곡선이 안 바로잡혔다")
    }

    /// 그 라인이 모르는 종은 손대지 않는다 — 다른 라인 소속 개체까지 건드리면 안 된다.
    func testUnrelatedSpeciesAreUntouchedByABackfill() {
        let store = makeStore()
        let individual = Individual(baseID: 1, speciesID: 1, pathIDs: [1], nature: .hardy,
                                    obtainedAt: now, grade: .common, growthRate: .mediumFast)
        store.addForTesting(individual)
        let line = EvoLine(baseID: 144, tree: EvoNode(speciesID: 144, children: []),
                           rarity: .legendary, names: [:], growthRates: [144: .slow])

        store.backfillGrowthRates(from: line)

        XCTAssertEqual(store.state.box.first { $0.id == individual.id }?.growthRate, .mediumFast)
    }

    /// 구 세이브의 알에는 필드가 없다 — 없다고 알을 버리면 부화 중인 것이 다 날아간다.
    func testAnOldEggStillDecodes() throws {
        let json = """
        {"id":"\(UUID().uuidString)","grade":"common","speciesID":4,"shiny":false,
         "startedAt":0,"hatchesAt":100}
        """
        let egg = try JSONDecoder().decode(Egg.self, from: Data(json.utf8))
        XCTAssertEqual(egg.speciesID, 4)
        XCTAssertEqual(egg.growthRate, .mediumFast)
    }
}
