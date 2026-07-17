import XCTest
@testable import PokeTokenBar

// MARK: 경제

final class PokemonBalanceTests: XCTestCase {
    func testGraduationTotalIsConstantPerRarityRegardlessOfStages() {
        for rarity in [Rarity.common, .uncommon, .rare, .legendary] {
            let T = PokemonBalance.graduationTotal(rarity)
            for k in 1...3 {
                let sum = (0..<k).reduce(0) { $0 + PokemonBalance.phaseThreshold(rarity: rarity, totalForms: k, stageIndex: $1) }
                // 반올림 오차 허용
                XCTAssertLessThanOrEqual(abs(sum - T), 2, "rarity=\(rarity) k=\(k) sum=\(sum) T=\(T)")
            }
        }
    }
    func testHigherStageCostsMore() {
        for k in 2...3 {
            for i in 0..<(k - 1) {
                XCTAssertLessThan(
                    PokemonBalance.phaseThreshold(rarity: .common, totalForms: k, stageIndex: i),
                    PokemonBalance.phaseThreshold(rarity: .common, totalForms: k, stageIndex: i + 1))
            }
        }
    }
    func testRarerCostsMore() {
        XCTAssertLessThan(PokemonBalance.graduationTotal(.common), PokemonBalance.graduationTotal(.uncommon))
        XCTAssertLessThan(PokemonBalance.graduationTotal(.uncommon), PokemonBalance.graduationTotal(.rare))
        XCTAssertLessThan(PokemonBalance.graduationTotal(.rare), PokemonBalance.graduationTotal(.legendary))
    }
    func testRarityDerivation() {
        XCTAssertEqual(Rarity.from(captureRate: 255, isLegendary: false, isMythical: false), .common)
        XCTAssertEqual(Rarity.from(captureRate: 90, isLegendary: false, isMythical: false), .uncommon)
        XCTAssertEqual(Rarity.from(captureRate: 45, isLegendary: false, isMythical: false), .rare)
        XCTAssertEqual(Rarity.from(captureRate: 3, isLegendary: true, isMythical: false), .legendary)
    }
}

// (부화 풀 하드코딩 제거 — 선정 로직 테스트는 CompanionIdentityTests 의 샘플러 테스트로 대체)

// MARK: 헬퍼

struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

struct StubProvider: PokeProviding {
    let value: EvoLine
    func line(baseSpeciesID: Int) async throws -> EvoLine { value }
    // 인덱스 = 자기 라인 base 단일 항목 → 선택 롤 1회 소비 후 항상 그 base (테스트 rng 재생 단순화)
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [BaseSpecies(id: value.baseID, captureRate: 255)] }
}

// 테스트 스텁 공통 — base 판정을 주입 인덱스에서 파생. REST 폴백 경로는 실클라이언트만 override.
extension PokeProviding {
    func baseSpecies(id: Int) async throws -> BaseSpecies? {
        try await baseSpeciesIndex().first { $0.id == id }
    }
}

private enum PokeStubError: Error { case boom }

/// GraphQL base 인덱스 장애 시뮬 — baseSpeciesIndex 는 throw(엔드포인트 다운), REST 폴백(baseSpecies)은 성공.
private struct FallbackOnlyProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { makeLine(base: baseSpeciesID, tree: node(baseSpeciesID)) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { throw PokeStubError.boom }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { BaseSpecies(id: id, captureRate: 100) }
}

/// line() 자체가 실패(오프라인) — 도감 이름 조회 폴백 검증용.
private struct LineThrowsProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw PokeStubError.boom }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
}

/// 샘플러 테스트용 — 주입한 base 인덱스 + 요청 id 그대로의 무진화 라인 반환.
final class IndexProvider: PokeProviding, @unchecked Sendable {
    nonisolated(unsafe) var index: [BaseSpecies] = []
    nonisolated(unsafe) var failAll = false
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        makeLine(base: baseSpeciesID, tree: node(baseSpeciesID))
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] {
        if failAll { throw PokeStubError.boom }
        return index
    }
}

private func allIDs(_ n: EvoNode) -> [Int] { [n.speciesID] + n.children.flatMap(allIDs) }
private func makeLine(base: Int, tree: EvoNode, rarity: Rarity = .common) -> EvoLine {
    var names: [Int: [String: String]] = [:]
    for id in allIDs(tree) { names[id] = ["en": "P\(id)", "ko": "포\(id)", "ja": "ポ\(id)"] }
    return EvoLine(baseID: base, tree: tree, rarity: rarity, names: names)
}
private func node(_ id: Int, _ children: [EvoNode] = []) -> EvoNode { EvoNode(speciesID: id, children: children) }
// 3단 선형: 1→2→3
private let linear3 = makeLine(base: 1, tree: node(1, [node(2, [node(3)])]))
// 분기: 10 → {11,12,13}
private let branch3 = makeLine(base: 10, tree: node(10, [node(11), node(12), node(13)]))
// 무진화: 20
private let noEvo = makeLine(base: 20, tree: node(20))
private let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)

// MARK: 스토어

@MainActor
final class CompanionStoreTests: XCTestCase {
    private func store(_ line: EvoLine, seed: UInt64 = 7) -> CompanionStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-\(UUID().uuidString).json")
        return CompanionStore(provider: StubProvider(value: line), clock: { fixedNow }, fileURL: url, rng: SeededRNG(seed: seed))
    }

    // MARK: 도감 이름 (컬렉션 표시)

    /// 저장된 체인 종별 다국어 이름을 현재 언어로 해석 — 없으면 nil(뷰가 async 조회로 폴백).
    func testDexStoredChainNamesResolvePerLanguage() {
        let s = store(linear3)
        let named = DexEntry(baseID: 1, finalID: 3, chainOrder: [1, 2, 3], rarity: .common, caughtAt: nil,
                             names: [1: ["ko": "포1", "en": "P1"], 2: ["ko": "포2", "en": "P2"], 3: ["ko": "포3", "en": "P3"]])
        s.setLanguage(.ko); XCTAssertEqual(s.dexStoredChainNames(named), [1: "포1", 2: "포2", 3: "포3"])
        s.setLanguage(.en); XCTAssertEqual(s.dexStoredChainNames(named), [1: "P1", 2: "P2", 3: "P3"])
        // 저장 이름 없음 → nil
        XCTAssertNil(s.dexStoredChainNames(DexEntry(baseID: 1, finalID: 3, chainOrder: [1, 2, 3],
                                                    rarity: .common, caughtAt: nil)))
    }

    /// 이름 미저장(구버전) 항목은 line 조회로 체인 전 종의 이름을 얻는다(chainOrder 전부 채움).
    func testDexResolveChainNamesFetchesWhenUnstored() async {
        let s = store(linear3)   // line 이름: 포1/포2/포3
        s.setLanguage(.ko)
        let bare = DexEntry(baseID: 1, finalID: 3, chainOrder: [1, 2, 3], rarity: .common, caughtAt: nil)
        let names = await s.dexResolveChainNames(bare)
        XCTAssertEqual(names, [1: "포1", 2: "포2", 3: "포3"])
    }

    /// 졸업 시 체인 각 종의 다국어 이름이 도감 항목에 저장된다 → 단계별 표시가 네트워크 없이 즉시.
    func testGraduationStoresChainNames() async {
        let s = store(linear3)
        await s.hatch(baseID: 1)
        s.applyUsage(PokemonBalance.phaseThreshold(rarity: .common, totalForms: 3, stageIndex: 0))  // →2
        s.applyUsage(PokemonBalance.phaseThreshold(rarity: .common, totalForms: 3, stageIndex: 1))  // →3(최종)
        s.applyUsage(PokemonBalance.phaseThreshold(rarity: .common, totalForms: 3, stageIndex: 2))  // 졸업
        XCTAssertEqual(s.state.dex.count, 1)
        XCTAssertEqual(s.state.dex.first?.chainOrder, [1, 2, 3])
        XCTAssertEqual(s.state.dex.first?.names?[1]?["ko"], "포1")   // 초기 단계도 저장
        XCTAssertEqual(s.state.dex.first?.names?[3]?["ja"], "ポ3")   // 최종 단계도 저장
        s.setLanguage(.ko)
        XCTAssertEqual(s.state.dex.first.map { s.dexStoredChainNames($0) }, [1: "포1", 2: "포2", 3: "포3"])
    }

    /// 백필(트리거 브랜치): 이름 미저장(구버전) 항목을 조회하면 line 에서 체인 이름을 얻어 **항목에 저장**
    /// 한다. 구버전 저장 JSON(“names” 키 없음)을 로드해 실제 마이그레이션 경로를 재현한다.
    func testDexResolveChainNamesBackfillsLegacyEntry() async {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-\(UUID().uuidString).json")
        let json = #"{"dex":[{"id":"e1","baseID":1,"finalID":3,"chainOrder":[1,2,3],"rarity":"common"}]}"#
        try? json.data(using: .utf8)!.write(to: url)
        let s = CompanionStore(provider: StubProvider(value: linear3), clock: { fixedNow },
                               fileURL: url, rng: SeededRNG(seed: 7))
        s.setLanguage(.ko)
        XCTAssertEqual(s.state.dex.count, 1)                        // 구버전 JSON 로드 성공
        XCTAssertNil(s.state.dex.first?.names)                      // 이름 없음(구버전)
        let names = await s.dexResolveChainNames(s.state.dex[0])
        XCTAssertEqual(names, [1: "포1", 2: "포2", 3: "포3"])       // fetch 로 체인 전부
        XCTAssertEqual(s.state.dex.first?.names?[2]?["ko"], "포2")  // 항목에 백필 저장됨(트리거 브랜치)
    }

    /// 오프라인(line fetch 실패) + 저장 없음 → chainOrder 전 종을 종 번호(#id)로 폴백.
    func testDexResolveChainNamesOfflineFallback() async {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-\(UUID().uuidString).json")
        let s = CompanionStore(provider: LineThrowsProvider(), clock: { fixedNow },
                               fileURL: url, rng: SeededRNG(seed: 7))
        let bare = DexEntry(baseID: 1, finalID: 3, chainOrder: [1, 2, 3], rarity: .common, caughtAt: nil)
        let names = await s.dexResolveChainNames(bare)
        XCTAssertEqual(names, [1: "#1", 2: "#2", 3: "#3"])
    }

    func testInstallBaselineExcludesPreInstallUsage() {
        let s = store(linear3)
        // 데이터 도착 전 → baseline 미설정
        s.update(todayTokens: 0, todayDate: "d1", monthTotal: 0, burnTier: .idle, limitWarning: false, hasUsageData: false)
        XCTAssertFalse(s.state.installBaselineSet)
        // 첫 실데이터 → baseline = 그 시점 today(이전 사용량 미카운트)
        s.update(todayTokens: 48_000_000, todayDate: "d1", monthTotal: 0, burnTier: .idle, limitWarning: false, hasUsageData: true)
        XCTAssertTrue(s.state.installBaselineSet)
        XCTAssertEqual(s.state.usedSinceInstall, 0)
        // 이후 증가분만 누적
        s.update(todayTokens: 148_000_000, todayDate: "d1", monthTotal: 0, burnTier: .idle, limitWarning: false, hasUsageData: true)
        XCTAssertEqual(s.state.usedSinceInstall, 100_000_000)
    }

    private func base(_ s: CompanionStore) {
        s.update(todayTokens: 0, todayDate: "d1", monthTotal: 0, burnTier: .idle, limitWarning: false, hasUsageData: true)
    }
    private func use(_ s: CompanionStore, _ today: Int) {
        s.update(todayTokens: today, todayDate: "d1", monthTotal: 0, burnTier: .idle, limitWarning: false, hasUsageData: true)
    }

    func testEggDoesNotHatchBelowThreshold() async {
        let s = store(linear3)
        base(s)
        use(s, 500_000)   // < 1M
        XCTAssertEqual(s.state.eggUsage, 500_000)
        XCTAssertTrue(s.isEgg)
        await s.hatchIfNeeded()
        XCTAssertNil(s.state.active)   // 임계 미만 → 미부화
    }

    func testEggHatchesAtThreshold() async {
        let s = store(linear3)
        base(s)
        use(s, PokemonBalance.eggHatchThreshold)   // = 1M
        XCTAssertEqual(s.state.eggUsage, PokemonBalance.eggHatchThreshold)
        await s.hatchIfNeeded()
        XCTAssertNotNil(s.state.active)
        XCTAssertEqual(s.state.eggUsage, 0)
    }

    func testEggOverflowCarriesToHatchedMon() async {
        let s = store(linear3)
        base(s)
        use(s, PokemonBalance.eggHatchThreshold + 500_000)   // 임계 초과 0.5M
        await s.hatchIfNeeded()
        XCTAssertEqual(s.state.active?.usedAtStage, 500_000)   // 초과분 이월
    }

    /// GraphQL base 인덱스 엔드포인트가 죽어도 REST 폴백으로 부화한다 (2026-07 실장애 회귀 방지).
    func testEggHatchesViaRESTFallbackWhenIndexDown() async {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-\(UUID().uuidString).json")
        let s = CompanionStore(provider: FallbackOnlyProvider(),
                               clock: { fixedNow }, fileURL: url, rng: SeededRNG(seed: 7))
        base(s)
        use(s, PokemonBalance.eggHatchThreshold)
        await s.hatchIfNeeded()
        XCTAssertNotNil(s.state.active, "인덱스 장애 시 REST 폴백으로 부화해야 함")
        XCTAssertEqual(s.state.eggUsage, 0)
    }

    func testNewEggAfterGraduationReincubates() async {
        let s = store(noEvo)
        base(s)
        use(s, PokemonBalance.eggHatchThreshold)
        await s.hatchIfNeeded()
        XCTAssertNotNil(s.state.active)
        s.applyUsage(PokemonBalance.graduationTotal(.common))   // 무진화 졸업
        XCTAssertNil(s.state.active)
        XCTAssertEqual(s.state.eggUsage, 0)                     // 새 알 인큐베이션 리셋
        await s.hatchIfNeeded()                                 // eggUsage=0 → 즉시 부화 안 함
        XCTAssertNil(s.state.active)
    }

    func testStateDecodesWithoutEggUsage() throws {
        // 기존 저장(필드 없음)도 깨지지 않고 eggUsage=0 으로 로드
        let json = #"{"installBaselineSet":true,"usedSinceInstall":5,"claimedTodayTokens":5,"lastDate":"d","active":null,"dex":[],"collectedFinals":[],"language":"ko"}"#
        let state = try JSONDecoder().decode(CompanionState.self, from: Data(json.utf8))
        XCTAssertEqual(state.eggUsage, 0)
        XCTAssertEqual(state.usedSinceInstall, 5)
    }

    func testEvolvesThroughLineAndGraduatesWithFullChain() async {
        let s = store(linear3)
        s.setLanguage(.ko)   // 로케일 무관하게 한국어 표시명("포3") 검증 (CI 는 영어 로케일)
        await s.hatch(baseID: 1)
        XCTAssertEqual(s.currentSpeciesID, 1)
        XCTAssertEqual(s.state.active?.totalForms, 3)
        s.applyUsage(PokemonBalance.phaseThreshold(rarity: .common, totalForms: 3, stageIndex: 0)) // →2
        XCTAssertEqual(s.currentSpeciesID, 2)
        s.applyUsage(PokemonBalance.phaseThreshold(rarity: .common, totalForms: 3, stageIndex: 1)) // →3 (final)
        XCTAssertEqual(s.currentSpeciesID, 3)
        XCTAssertTrue(s.isFinalStage)
        s.applyUsage(PokemonBalance.phaseThreshold(rarity: .common, totalForms: 3, stageIndex: 2)) // 졸업
        XCTAssertNil(s.state.active)
        XCTAssertEqual(s.dexEntries.count, 1)
        XCTAssertEqual(s.dexEntries[0].chainOrder, [1, 2, 3])   // 라인 전체 보존
        XCTAssertEqual(s.justGraduated, "포3")
    }

    func testNoEvolutionGraduatesAtSingleThreshold() async {
        let s = store(noEvo)
        await s.hatch(baseID: 20)
        XCTAssertTrue(s.isFinalStage)
        s.applyUsage(PokemonBalance.graduationTotal(.common))   // 무진화: 단일 임계 = T
        XCTAssertEqual(s.dexEntries.count, 1)
        XCTAssertEqual(s.dexEntries[0].chainOrder, [20])
    }

    func testBranchingPrefersUncollectedFinals() async {
        let s = store(branch3)
        let evo = PokemonBalance.phaseThreshold(rarity: .common, totalForms: 2, stageIndex: 0)
        let grad = PokemonBalance.phaseThreshold(rarity: .common, totalForms: 2, stageIndex: 1)
        var finals: [Int] = []
        for _ in 0..<3 {
            await s.hatch(baseID: 10)
            s.applyUsage(evo)    // 분기 진화
            s.applyUsage(grad)   // 졸업
            finals.append(s.dexEntries.last!.finalID)
        }
        XCTAssertEqual(Set(finals).count, 3)   // 같은 base 재부화 시 매번 다른 분기
        XCTAssertEqual(Set(finals), [11, 12, 13])
    }

    func testPersistenceRoundTrip() async {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-persist-\(UUID().uuidString).json")
        let s1 = CompanionStore(provider: StubProvider(value: linear3), clock: { fixedNow }, fileURL: url, rng: SeededRNG(seed: 1))
        await s1.hatch(baseID: 1)
        s1.applyUsage(PokemonBalance.phaseThreshold(rarity: .common, totalForms: 3, stageIndex: 0))
        s1.setLanguage(.ja)
        let s2 = CompanionStore(provider: StubProvider(value: linear3), clock: { fixedNow }, fileURL: url, rng: SeededRNG(seed: 1))
        XCTAssertEqual(s2.state.active?.currentID, 2)
        XCTAssertEqual(s2.state.active?.stageIndex, 1)
        XCTAssertEqual(s2.language, .ja)
    }

    func testLocalizedName() async {
        let s = store(linear3)
        await s.hatch(baseID: 1)
        s.setLanguage(.ko); XCTAssertEqual(s.displayName, "포1")
        s.setLanguage(.en); XCTAssertEqual(s.displayName, "P1")
        s.setLanguage(.ja); XCTAssertEqual(s.displayName, "ポ1")
    }

    /// [문서화] 비대칭 깊이 분기 — totalForms=tree.depth(최장 경로)라 짧은 분기를 뽑으면 실제 경로가
    /// totalForms 보다 짧다. 실 Gen1-5 라인은 분기 깊이가 대칭(뷰티플라이·이브이 등)이라 발생하지 않는다
    /// (CompanionModel depth 주석 "분기는 보통 같은 깊이" 가정). 크래시·무한루프 없이 최종체에서 졸업하고
    /// 실제 경로가 보존됨을 잠근다.
    func testAsymmetricBranchGraduatesSafely() async {
        let line = makeLine(base: 1, tree: node(1, [node(2), node(3, [node(4)])]))   // depth=3, 분기 {2, 3→4}
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-asym-\(UUID().uuidString).json")
        let s = CompanionStore(provider: StubProvider(value: line), clock: { fixedNow }, fileURL: url, rng: SeededRNG(seed: 7))
        await s.hatch(baseID: 1)
        XCTAssertEqual(s.state.active?.totalForms, 3, "totalForms = 최장 경로 깊이")
        var guardCount = 0
        while s.state.active != nil, guardCount < 12 {
            guardCount += 1
            let stage = s.state.active!.stageIndex
            s.applyUsage(PokemonBalance.phaseThreshold(rarity: .common, totalForms: 3, stageIndex: stage))
        }
        XCTAssertNil(s.state.active, "어느 분기든 최종체에서 졸업(크래시·무한루프 없음)")
        XCTAssertEqual(s.dexEntries.count, 1)
        let chain = s.dexEntries[0].chainOrder
        XCTAssertTrue(chain == [1, 2] || chain == [1, 3, 4], "실제 진화 경로 보존: \(chain)")
    }
}

// MARK: 도감 정렬 / 요약

@MainActor
final class DexSortingTests: XCTestCase {
    func testSortRankOrdersRarityAscendingByValue() {
        XCTAssertLessThan(Rarity.common.sortRank, Rarity.uncommon.sortRank)
        XCTAssertLessThan(Rarity.uncommon.sortRank, Rarity.rare.sortRank)
        XCTAssertLessThan(Rarity.rare.sortRank, Rarity.legendary.sortRank)
    }

    func testDexEntriesSortedLegendaryFirstThenRecency() async {
        // common 라인 2개(시각 다름) + legendary 라인 1개를 같은 store 에 졸업시킨다.
        // StubProvider 는 라인 1개만 주므로, 라인별로 store 를 분리하지 않고
        // 직접 졸업 흐름을 재현: 무진화(단일 임계) 라인을 hatch→applyUsage 로 졸업.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-\(UUID().uuidString).json")
        var tick = 0
        // 라인을 바꿔가며 졸업시키기 위해 가변 provider 사용.
        let provider = MutableProvider()
        let s = CompanionStore(provider: provider,
                               clock: { fixedNow.addingTimeInterval(TimeInterval(tick)) },
                               fileURL: url, rng: SeededRNG(seed: 3))

        // common #1 (가장 먼저)
        provider.line = makeLine(base: 100, tree: node(100), rarity: .common)
        tick = 1; await s.hatch(baseID: 100)
        s.applyUsage(PokemonBalance.graduationTotal(.common))

        // common #2 (더 나중)
        provider.line = makeLine(base: 101, tree: node(101), rarity: .common)
        tick = 2; await s.hatch(baseID: 101)
        s.applyUsage(PokemonBalance.graduationTotal(.common))

        // legendary (가장 나중이지만 희귀도가 더 높음)
        provider.line = makeLine(base: 200, tree: node(200), rarity: .legendary)
        tick = 3; await s.hatch(baseID: 200)
        s.applyUsage(PokemonBalance.graduationTotal(.legendary))

        XCTAssertEqual(s.dexEntries.count, 3)
        let sorted = s.dexEntriesSorted
        // legendary 가 맨 앞
        XCTAssertEqual(sorted[0].rarity, .legendary)
        XCTAssertEqual(sorted[0].finalID, 200)
        // 그다음 common 끼리는 최신(101)이 먼저
        XCTAssertEqual(sorted[1].rarity, .common)
        XCTAssertEqual(sorted[1].finalID, 101)
        XCTAssertEqual(sorted[2].finalID, 100)

        // 희귀도별 카운트
        XCTAssertEqual(s.dexCount(.common), 2)
        XCTAssertEqual(s.dexCount(.legendary), 1)
        XCTAssertEqual(s.dexCount(.rare), 0)
    }
}

/// 테스트용 — 라인을 호출 전에 갈아끼울 수 있는 provider. 단일 스레드 테스트 한정.
private final class MutableProvider: PokeProviding, @unchecked Sendable {
    nonisolated(unsafe) var line: EvoLine = makeLine(base: 1, tree: node(1))
    func line(baseSpeciesID: Int) async throws -> EvoLine { line }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [BaseSpecies(id: line.baseID, captureRate: 255)] }
}

// MARK: 개체 아이덴티티 (shiny / nature) — v2.2.0

@MainActor
final class CompanionIdentityTests: XCTestCase {
    private func store(_ line: EvoLine, seed: UInt64) -> CompanionStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-\(UUID().uuidString).json")
        return CompanionStore(provider: StubProvider(value: line), clock: { fixedNow }, fileURL: url, rng: SeededRNG(seed: seed))
    }

    /// 직접 hatch(baseID:) 는 rng 를 shiny → nature 순으로 소비한다. 같은 시드 재생으로 기대값 산출.
    private func expectedRoll(seed: UInt64) -> (shiny: Bool, nature: PokemonNature) {
        var rng = SeededRNG(seed: seed)
        let shiny = rng.next() % PokemonOdds.shinyDenominator == 0
        let nature = PokemonNature.allCases[Int(rng.next() % UInt64(PokemonNature.allCases.count))]
        return (shiny, nature)
    }

    /// 임의 시드에서 부화 롤이 결정적이고 성격이 항상 부여되는지.
    func testHatchAssignsDeterministicShinyAndNature() async {
        for seed: UInt64 in [1, 7, 42, 12345] {
            let s = store(linear3, seed: seed)
            let expected = expectedRoll(seed: seed)
            await s.hatch(baseID: 1)
            XCTAssertEqual(s.state.active?.isShiny, expected.shiny, "seed \(seed)")
            XCTAssertEqual(s.state.active?.nature, expected.nature, "seed \(seed)")
        }
    }

    /// shiny 가 실제로 나오는 시드를 탐색해 true 경로를 검증(1/64 확률이 코드에 존재함을 보장).
    func testShinyPathReachable() async {
        var shinySeed: UInt64?
        for seed: UInt64 in 0..<5000 where expectedRoll(seed: seed).shiny { shinySeed = seed; break }
        guard let seed = shinySeed else { return XCTFail("5000개 시드 중 shiny 없음 — 분모 확인") }
        let s = store(linear3, seed: seed)
        await s.hatch(baseID: 1)
        XCTAssertEqual(s.state.active?.isShiny, true)
        XCTAssertTrue(s.currentIsShiny)
    }

    /// 진화를 거쳐 졸업해도 shiny/nature 가 도감 항목에 보존되는지.
    func testGraduateCarriesIdentityToDex() async {
        let s = store(noEvo, seed: 3)   // 무진화 → 임계 도달 시 바로 졸업
        await s.hatch(baseID: 20)
        let shiny = s.state.active!.isShiny
        let nature = s.state.active!.nature
        XCTAssertNotNil(nature)
        s.applyUsage(PokemonBalance.graduationTotal(.common))
        XCTAssertNil(s.state.active)   // 졸업
        XCTAssertEqual(s.state.dex.count, 1)
        XCTAssertEqual(s.state.dex[0].isShiny, shiny)
        XCTAssertEqual(s.state.dex[0].nature, nature)
    }

    /// 구버전 저장(shiny/nature 키 없음) 디코딩 — 기본값(false/nil)으로 로드.
    func testBackwardCompatibleDecode() throws {
        let old = """
        {"installBaselineSet":true,"usedSinceInstall":100,"eggUsage":0,
         "claimedTodayTokens":100,"lastDate":"d1",
         "active":{"baseID":1,"pathIDs":[1],"stageIndex":0,"usedAtStage":5,"rarity":"common","totalForms":3},
         "dex":[{"id":"x","baseID":4,"finalID":6,"chainOrder":[4,5,6],"rarity":"rare"}],
         "collectedFinals":["4:6"],"language":"ko"}
        """
        let s = try JSONDecoder().decode(CompanionState.self, from: Data(old.utf8))
        XCTAssertEqual(s.active?.isShiny, false)
        XCTAssertNil(s.active?.nature)
        XCTAssertEqual(s.dex[0].isShiny, false)
        XCTAssertNil(s.dex[0].nature)
        // 재인코딩 후 재디코딩도 안정적(라운드트립)
        let round = try JSONDecoder().decode(CompanionState.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(round.active?.isShiny, false)
    }

    /// [출시 안전] 손상된 상태 파일: active.pathIDs 가 비면 디코드가 실패해야 한다
    /// (→ load() 가 기본 알 상태로 폴백 → currentID out-of-bounds 크래시 방지).
    func testEmptyPathIDsRejectedOnDecode() {
        let corrupt = """
        {"installBaselineSet":true,"eggUsage":0,"lastDate":"d1",
         "active":{"baseID":1,"pathIDs":[],"stageIndex":0,"usedAtStage":0,"rarity":"common","totalForms":3}}
        """
        XCTAssertThrowsError(try JSONDecoder().decode(CompanionState.self, from: Data(corrupt.utf8)),
                             "빈 pathIDs 는 디코드 거부돼야 한다")
    }

    /// currentID 는 pathIDs 가 비어도(방어) baseID 로 폴백 — 크래시 없음.
    func testCurrentIDFallsBackToBaseWhenPathEmpty() {
        let m = MonState(baseID: 42, pathIDs: [], stageIndex: 0, usedAtStage: 0, rarity: .common, totalForms: 1)
        XCTAssertEqual(m.currentID, 42)
    }

    /// 신규 설치 기본 언어는 시스템 로케일에서 유추 — 유효한 케이스이고 크래시 없음(한국어 강제 아님).
    func testSystemDefaultLanguageResolves() {
        XCTAssertTrue(AppLanguage.allCases.contains(AppLanguage.systemDefault))
        XCTAssertEqual(CompanionState().language, AppLanguage.systemDefault)
    }

    /// 부화/진화가 연출 트리거(celebrationSeq)를 올리고, consume 후 비워지는지.
    func testCelebrationFiresOnHatchAndEvolve() async {
        let s = store(linear3, seed: 9)
        XCTAssertEqual(s.celebrationSeq, 0)
        await s.hatch(baseID: 1)
        XCTAssertEqual(s.celebrationSeq, 1)
        if case .hatch = s.celebration {} else { XCTFail("hatch 연출이어야 함: \(String(describing: s.celebration))") }
        s.consumeCelebration()
        XCTAssertNil(s.celebration)
        // 1단계 임계 도달 → 진화 연출
        let thr = PokemonBalance.phaseThreshold(rarity: .common, totalForms: 3, stageIndex: 0)
        s.applyUsage(thr)
        XCTAssertEqual(s.celebrationSeq, 2)
        XCTAssertEqual(s.celebration, .evolve)
    }

    /// [회귀] 라인 미로딩(재시작 직후/오프라인) 중 델타가 유실되지 않고 적립, 라인 로드 후 진화 판정.
    func testUsageAccruesWhileLineUnloadedThenEvolvesOnLoad() async {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-\(UUID().uuidString).json")
        // 1차 스토어: 부화 후 저장
        let s1 = CompanionStore(provider: StubProvider(value: linear3), clock: { fixedNow },
                                fileURL: url, rng: SeededRNG(seed: 5))
        s1.update(todayTokens: 0, todayDate: "d1", monthTotal: 0, burnTier: .idle, limitWarning: false, hasUsageData: true)
        await s1.hatch(baseID: 1)
        XCTAssertNotNil(s1.state.active)

        // 2차 스토어(재시작 시뮬레이션): active 는 로드됐지만 currentLine 은 nil
        let s2 = CompanionStore(provider: StubProvider(value: linear3), clock: { fixedNow },
                                fileURL: url, rng: SeededRNG(seed: 5))
        XCTAssertNotNil(s2.state.active)
        XCTAssertNil(s2.currentLine)
        // 라인 없는 상태에서 stage0 임계(125M) 초과 델타 → 유실 없이 적립, 진화는 보류
        s2.applyUsage(300_000_000)
        XCTAssertEqual(s2.state.active?.usedAtStage, 300_000_000, "라인 미로딩 중 델타가 유실되면 안 된다")
        XCTAssertEqual(s2.state.active?.stageIndex, 0)
        // update → loadCurrentLine 완료 시 적립분으로 진화 판정(드레인)
        s2.update(todayTokens: 0, todayDate: "d1", monthTotal: 0, burnTier: .idle, limitWarning: false, hasUsageData: true)
        for _ in 0..<50 where s2.currentLine == nil { await Task.yield() }
        XCTAssertNotNil(s2.currentLine)
        XCTAssertEqual(s2.state.active?.stageIndex, 1, "라인 로드 후 적립분으로 진화해야 한다")
        XCTAssertEqual(s2.state.active?.usedAtStage, 300_000_000 - 125_000_000)   // 초과분 이월
    }

    /// [회귀] 부화 이월(overflow)로 즉시 진화해도 마지막 연출은 hatch(shiny) — evolve 가 버스트를 덮지 않는다.
    func testShinyBurstSurvivesOverflowEvolve() async {
        // hatchIfNeeded 경로: chooseBase(1) → shiny(2) → nature(3) 순 rng 소비. shiny 시드 탐색.
        func rollsShinyViaHatchIfNeeded(_ seed: UInt64) -> Bool {
            var r = SeededRNG(seed: seed)
            _ = r.next()   // chooseBase: 가중 선택 롤(정확히 1회)
            return r.next() % PokemonOdds.shinyDenominator == 0
        }
        var seed: UInt64?
        for s: UInt64 in 0..<20000 where rollsShinyViaHatchIfNeeded(s) { seed = s; break }
        guard let seed else { return XCTFail("shiny 시드 탐색 실패") }

        let s = store(linear3, seed: seed)
        s.update(todayTokens: 0, todayDate: "d1", monthTotal: 0, burnTier: .idle, limitWarning: false, hasUsageData: true)
        // 알 임계(5M) + stage0 임계(125M) 초과 → 부화 즉시 1회 진화하는 이월
        s.update(todayTokens: 135_000_000, todayDate: "d1", monthTotal: 0, burnTier: .idle, limitWarning: false, hasUsageData: true)
        await s.hatchIfNeeded()
        XCTAssertEqual(s.state.active?.isShiny, true)
        XCTAssertEqual(s.state.active?.stageIndex, 1, "이월로 1회 진화했어야 함")
        XCTAssertEqual(s.celebration, .hatch(shiny: true), "evolve 가 shiny 부화 버스트를 덮으면 안 된다")
    }

    /// [회귀] 이월이 졸업 총량을 넘어 부화 즉시 졸업한 극단 케이스 — hatch 연출은 생략(이미 도감행).
    func testHatchCelebrationSkippedOnInstantGraduate() async {
        let s = store(noEvo, seed: 11)
        s.update(todayTokens: 0, todayDate: "d1", monthTotal: 0, burnTier: .idle, limitWarning: false, hasUsageData: true)
        // 알 임계 + 졸업 총량(750M) 초과
        s.update(todayTokens: 800_000_000, todayDate: "d1", monthTotal: 0, burnTier: .idle, limitWarning: false, hasUsageData: true)
        await s.hatchIfNeeded()
        XCTAssertNil(s.state.active, "즉시 졸업")
        XCTAssertEqual(s.state.dex.count, 1)
        XCTAssertNil(s.celebration, "떠난 mon 의 hatch 연출을 재생하면 안 된다")
    }

    // MARK: 부화 샘플러 (PokéAPI rejection sampling — 하드코딩 풀 대체)

    private func samplerStore(_ provider: any PokeProviding, seed: UInt64,
                              preloadState: CompanionState? = nil) -> CompanionStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-\(UUID().uuidString).json")
        if let st = preloadState, let data = try? JSONEncoder().encode(st) { try? data.write(to: url) }
        return CompanionStore(provider: provider, clock: { fixedNow }, fileURL: url, rng: SeededRNG(seed: seed))
    }

    /// 알을 임계 이상으로 채운 상태(installBaseline 포함) — rng 미소비 경로.
    private func eggReadyState(collected: Set<String> = []) -> CompanionState {
        var st = CompanionState()
        st.installBaselineSet = true
        st.lastDate = "d1"
        st.eggUsage = PokemonBalance.eggHatchThreshold + 1
        st.collectedFinals = collected
        return st
    }

    /// 누적 가중 선택이 결정적이다 — 정확히 1롤, 롤 값이 가중 구간에 매핑.
    func testSamplerWeightedPickDeterministic() async {
        let index = [BaseSpecies(id: 10, captureRate: 100),
                     BaseSpecies(id: 20, captureRate: 100),
                     BaseSpecies(id: 30, captureRate: 100)]
        for seed: UInt64 in [1, 7, 42, 999] {
            var r = SeededRNG(seed: seed)
            let roll = Int(r.next() % 300)
            let expected = index[roll / 100].id      // 구간: [0,100)→10, [100,200)→20, [200,300)→30
            let p = IndexProvider(); p.index = index
            let s = samplerStore(p, seed: seed, preloadState: eggReadyState())
            await s.hatchIfNeeded()
            XCTAssertEqual(s.state.active?.baseID, expected, "seed \(seed) roll \(roll)")
        }
    }

    /// capture_rate 가 곧 가중치 — cr 비율만큼 선택 구간이 좁아진다 (희귀種 낮은 확률).
    func testSamplerCaptureRateIsWeight() async {
        // [common 254, legendary 2] → roll 0..253 → common, 254..255 → legendary
        let index = [BaseSpecies(id: 100, captureRate: 254), BaseSpecies(id: 200, captureRate: 2)]
        var legendarySeed: UInt64?, commonSeed: UInt64?
        for seed: UInt64 in 0..<3000 {
            var r = SeededRNG(seed: seed)
            let roll = Int(r.next() % 256)
            if roll >= 254, legendarySeed == nil { legendarySeed = seed }
            if roll < 254, commonSeed == nil { commonSeed = seed }
            if legendarySeed != nil, commonSeed != nil { break }
        }
        for (seed, expected) in [(commonSeed!, 100), (legendarySeed!, 200)] {
            let p = IndexProvider(); p.index = index
            let s = samplerStore(p, seed: seed, preloadState: eggReadyState())
            await s.hatchIfNeeded()
            XCTAssertEqual(s.state.active?.baseID, expected)
        }
    }

    /// 이미 수집한 base 는 가중치 ½ — 경계 롤에서 선택 구간이 바뀌는 것으로 검증.
    func testSamplerHalvesCollectedWeight() async {
        // 미수집: [200, 200] → 경계 200. id=1 수집 시: [100, 200] → 경계 100.
        // roll ∈ [100, 200) 인 시드는 수집 전엔 id=1, 수집 후엔 id=2 를 뽑는다.
        let index = [BaseSpecies(id: 1, captureRate: 200), BaseSpecies(id: 2, captureRate: 200)]
        // 같은 시드 → 같은 원시 롤값 v. 미수집 총합 400 / 수집 후 총합 300 으로 모듈로만 달라진다.
        // v%400 < 200 (미수집 → id=1) 이면서 v%300 ≥ 100 (수집 후 → id=2) 인 시드를 찾는다.
        var found: UInt64?
        for seed: UInt64 in 0..<5000 {
            var r = SeededRNG(seed: seed)
            let v = r.next()
            if v % 400 < 200, v % 300 >= 100 { found = seed; break }
        }
        guard let seed = found else { return XCTFail("시드 탐색 실패") }
        // 수집 전: id=1 구간
        let p1 = IndexProvider(); p1.index = index
        let s1 = samplerStore(p1, seed: seed, preloadState: eggReadyState())
        await s1.hatchIfNeeded()
        XCTAssertEqual(s1.state.active?.baseID, 1)
        // id=1 수집 후: 같은 시드가 id=2 구간으로 밀림 (가중치 ½ 효과)
        let p2 = IndexProvider(); p2.index = index
        let s2 = samplerStore(p2, seed: seed, preloadState: eggReadyState(collected: ["1:1"]))
        await s2.hatchIfNeeded()
        XCTAssertEqual(s2.state.active?.baseID, 2, "수집済 가중치 ½ 로 선택 구간이 이동해야 한다")
    }

    /// 알 상태 프리패칭 — update 틱에 종이 pre-roll 되어 영속되고, 부화는 pending 을 그대로 사용.
    func testEggPrefetchStoresPendingAndHatchUsesIt() async {
        let p = IndexProvider()
        p.index = [BaseSpecies(id: 77, captureRate: 255)]
        var st = CompanionState()
        st.installBaselineSet = true
        st.lastDate = "d1"
        let s = samplerStore(p, seed: 5, preloadState: st)
        // 임계 미만 사용 → 부화는 안 되지만 프리패칭은 돌아야 한다
        s.update(todayTokens: 1_000, todayDate: "d1", monthTotal: 0, burnTier: .idle, limitWarning: false, hasUsageData: true)
        for _ in 0..<50 where s.state.pendingHatchID == nil { await Task.yield() }
        XCTAssertEqual(s.state.pendingHatchID, 77, "알 상태에서 종이 미리 롤/저장돼야 한다")
        // 임계 도달 → 부화는 pending 그대로 (추가 선택 롤 없음: shiny/nature 만 소비)
        s.update(todayTokens: 6_000_000, todayDate: "d1", monthTotal: 0, burnTier: .idle, limitWarning: false, hasUsageData: true)
        await s.hatchIfNeeded()
        XCTAssertEqual(s.state.active?.baseID, 77)
        XCTAssertNil(s.state.pendingHatchID, "부화 후 pending 은 비워져야 한다")
        XCTAssertNotNil(s.state.active?.nature)
    }

    /// 프리패칭이 오프라인으로 실패해도 부화 시점 롤로 폴백 — 알이 막히지 않는다.
    func testPrefetchOfflineFallsBackToHatchTimeRoll() async {
        let p = IndexProvider()
        p.index = [BaseSpecies(id: 88, captureRate: 255)]
        p.failAll = true
        let s = samplerStore(p, seed: 9, preloadState: eggReadyState())
        s.update(todayTokens: 0, todayDate: "d1", monthTotal: 0, burnTier: .idle, limitWarning: false, hasUsageData: true)
        for _ in 0..<10 { await Task.yield() }        // 프리패치 시도 소진(실패)
        XCTAssertNil(s.state.pendingHatchID)
        await s.hatchIfNeeded()                        // 여전히 오프라인 → 알 유지
        XCTAssertNil(s.state.active)
        p.failAll = false                              // 네트워크 복구
        // 초기 update() 가 띄운 프리패치 Task 가 아직 in-flight 면 hatchIfNeeded 가 prefetchInFlight
        // 가드로 조기 반환할 수 있다(고정 yield 횟수로는 CI 스케줄 지연에서 못 소진 — 플래키 원인).
        // 부화할 때까지 재시도해 결정적으로 만든다(in-flight 는 몇 틱 내 실패로 해제됨).
        for _ in 0..<50 where s.state.active == nil {
            await s.hatchIfNeeded()                    // 부화 시점 롤 폴백
            await Task.yield()
        }
        XCTAssertEqual(s.state.active?.baseID, 88)
    }

    /// 오프라인(인덱스 취득 실패) — 알 진행 보존, isHatching 해제, 다음 틱 재시도 가능.
    func testSamplerOfflineKeepsEgg() async {
        let p = IndexProvider()
        p.failAll = true
        let s = samplerStore(p, seed: 1, preloadState: eggReadyState())
        await s.hatchIfNeeded()
        XCTAssertNil(s.state.active)
        XCTAssertGreaterThanOrEqual(s.state.eggUsage, PokemonBalance.eggHatchThreshold, "알 진행 보존")
        XCTAssertFalse(s.isHatching)
    }

    /// 스프라이트 캐시 키 — 기존 키("25-a"/"25-s") 불변 + shiny 접두.
    func testSpriteCacheKeyScheme() {
        XCTAssertEqual(SpriteStore.cacheKey(speciesID: 25, animated: true, shiny: false), "25-a")
        XCTAssertEqual(SpriteStore.cacheKey(speciesID: 25, animated: false, shiny: false), "25-s")
        XCTAssertEqual(SpriteStore.cacheKey(speciesID: 25, animated: true, shiny: true), "25-sha")
        XCTAssertEqual(SpriteStore.cacheKey(speciesID: 25, animated: false, shiny: true), "25-shs")
    }

    /// 성격 25종 — 3개 언어 명칭이 전부 비어있지 않고 중복 없는지.
    func testNatureNamesComplete() {
        XCTAssertEqual(PokemonNature.allCases.count, 25)
        for lang in AppLanguage.allCases {
            let names = PokemonNature.allCases.map { $0.name(lang) }
            XCTAssertEqual(Set(names).count, 25, "\(lang) 중복/누락")
            XCTAssertFalse(names.contains(where: \.isEmpty))
        }
    }
}

// MARK: PokéAPI SSRF 가드 (evolution_chain URL 검증 — 응답 변조 시 임의 호스트 fetch 방지)

final class PokeAPIGuardTests: XCTestCase {
    func testValidatedChainURLAcceptsPokeapiHttps() {
        XCTAssertNotNil(PokeAPIClient.validatedChainURL("https://pokeapi.co/api/v2/evolution-chain/1/"))
    }
    func testValidatedChainURLRejectsUntrusted() {
        XCTAssertNil(PokeAPIClient.validatedChainURL("https://evil.example.com/x"), "임의 호스트 거부(SSRF)")
        XCTAssertNil(PokeAPIClient.validatedChainURL("https://pokeapi.co.evil.com/x"), "유사 호스트 거부")
        XCTAssertNil(PokeAPIClient.validatedChainURL("http://pokeapi.co/x"), "http 거부(https 고정)")
        XCTAssertNil(PokeAPIClient.validatedChainURL(""), "빈 문자열 거부")
    }
}
