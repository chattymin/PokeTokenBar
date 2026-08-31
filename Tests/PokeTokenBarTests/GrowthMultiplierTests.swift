import XCTest
@testable import PokeTokenBar

/// 성장 비용 배율(growthMultiplier) — 부화·진화·졸업 임계 전부에 곱해지는 비율. 본가 상수는
/// PokemonBalance 에 그대로 두고, 임계를 읽는 지점(CompanionStore)에서만 배율을 곱한다.
@MainActor
final class GrowthMultiplierTests: XCTestCase {
    private let gmNow = Date(timeIntervalSince1970: 1_700_000_000)

    /// 3단 선형 common: 1→2→3.
    private let gmLine = EvoLine(baseID: 1,
                                 tree: EvoNode(speciesID: 1, children: [
                                    EvoNode(speciesID: 2, children: [EvoNode(speciesID: 3, children: [])])]),
                                 rarity: .common, names: [:])

    private func makeSuite() -> (String, UserDefaults) {
        let name = "ptb.growth.\(UUID().uuidString)"
        return (name, UserDefaults(suiteName: name)!)
    }

    private func makeStore(defaults: UserDefaults) -> CompanionStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("gm-\(UUID().uuidString).json")
        return CompanionStore(provider: StubProvider(value: gmLine), clock: { [gmNow] in gmNow },
                              fileURL: url, rng: SeededRNG(seed: 7), defaults: defaults)
    }

    func testDefaultsToFullCostWhenUnset() async {
        let (suite, defaults) = makeSuite()
        defer { defaults.removePersistentDomain(forName: suite) }
        let s = makeStore(defaults: defaults)

        XCTAssertEqual(s.growthMultiplier, 1.0)
        XCTAssertEqual(s.eggTokensToHatch, PokemonBalance.eggHatchThreshold)

        await s.hatch(baseID: 1)
        XCTAssertEqual(s.threshold, PokemonBalance.phaseThreshold(rarity: .common, totalForms: 3, stageIndex: 0))
    }

    func testMultiplierScalesEvolutionThreshold() async {
        let (suite, defaults) = makeSuite()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(0.1, forKey: CompanionStore.growthMultiplierDefaultsKey)
        let s = makeStore(defaults: defaults)

        await s.hatch(baseID: 1)
        XCTAssertEqual(s.threshold, 12_500_000)   // 커먼 1단계 125M × 0.1

        s.applyUsage(12_499_999)
        XCTAssertEqual(s.state.active?.stageIndex, 0)
        s.applyUsage(1)
        XCTAssertEqual(s.state.active?.stageIndex, 1)
    }

    /// 같은 배율이 총 졸업량에도 적용돼야 한다 — 초대형 델타가 축소된 임계들을 연속으로 돌파해 1회 졸업.
    func testMultiplierScalesFullGraduation() async {
        let (suite, defaults) = makeSuite()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(0.1, forKey: CompanionStore.growthMultiplierDefaultsKey)
        let s = makeStore(defaults: defaults)

        await s.hatch(baseID: 1)
        s.applyUsage(100_000_000)   // 축소된 총량(75M) 초과
        XCTAssertNil(s.state.active)
        XCTAssertEqual(s.dexEntries.count, 1)
        XCTAssertEqual(s.dexEntries[0].chainOrder, [1, 2, 3])
    }

    func testMultiplierScalesEggThreshold() {
        let (suite, defaults) = makeSuite()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(0.05, forKey: CompanionStore.growthMultiplierDefaultsKey)
        let s = makeStore(defaults: defaults)

        XCTAssertEqual(s.eggTokensToHatch, 250_000)   // 5M × 0.05
        XCTAssertEqual(s.eggProgress, 0)
    }

    func testMultiplierIsClamped() {
        let (suite, defaults) = makeSuite()
        defer { defaults.removePersistentDomain(forName: suite) }
        let s = makeStore(defaults: defaults)

        s.growthMultiplier = 2.0
        XCTAssertEqual(s.growthMultiplier, 1.0, "빠르기 상한 — 본가 속도(100%)를 넘길 수 없다")
        s.growthMultiplier = 0
        XCTAssertEqual(s.growthMultiplier, 1.0, "0/음수는 기본값(100%)으로 복구")
        s.growthMultiplier = 0.0001
        XCTAssertEqual(s.growthMultiplier, 0.01)
        s.growthMultiplier = 0.25
        XCTAssertEqual(s.growthMultiplier, 0.25)
    }

    func testPersistsAcrossStoreInstances() {
        let (suite, defaults) = makeSuite()
        defer { defaults.removePersistentDomain(forName: suite) }

        makeStore(defaults: defaults).growthMultiplier = 0.25
        XCTAssertEqual(defaults.double(forKey: CompanionStore.growthMultiplierDefaultsKey), 0.25)
        XCTAssertEqual(makeStore(defaults: defaults).growthMultiplier, 0.25)
    }
}
