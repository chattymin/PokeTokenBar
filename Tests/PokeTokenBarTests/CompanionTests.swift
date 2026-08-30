import XCTest
import Observation
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

final class CountingRNG: RandomNumberGenerator {
    private var base: SeededRNG
    private(set) var callCount = 0

    init(seed: UInt64) { base = SeededRNG(seed: seed) }

    func next() -> UInt64 {
        callCount += 1
        return base.next()
    }
}

@MainActor
private func waitUntil(timeout: TimeInterval = 1, _ condition: @escaping () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(nanoseconds: 1_000_000)
    }
    return condition()
}

struct StubProvider: PokeProviding {
    let value: EvoLine
    func line(baseSpeciesID: Int) async throws -> EvoLine { value }
    // 인덱스 = 자기 라인 base 단일 항목 → 선택 롤 1회 소비 후 항상 그 base (테스트 rng 재생 단순화)
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [BaseSpecies(id: value.baseID, captureRate: 255)] }
}

private actor SuspendedLineProvider: PokeProviding {
    private let value: EvoLine
    private var continuation: CheckedContinuation<EvoLine, Never>?
    private var suspended = false

    init(value: EvoLine) { self.value = value }

    func line(baseSpeciesID: Int) async throws -> EvoLine {
        await withCheckedContinuation { continuation in
            precondition(self.continuation == nil, "only one line request may be suspended")
            self.continuation = continuation
            suspended = true
        }
    }

    func baseSpeciesIndex() async throws -> [BaseSpecies] {
        [BaseSpecies(id: value.baseID, captureRate: 255)]
    }

    func isSuspended() -> Bool { suspended }

    func resume() {
        let pending = continuation
        continuation = nil
        suspended = false
        pending?.resume(returning: value)
    }
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

/// line() 호출 횟수를 센다 — 이미 저장된 항목에 불필요한 조회가 붙는지 검증용.
private final class CountingLineProvider: PokeProviding, @unchecked Sendable {
    let value: EvoLine
    nonisolated(unsafe) private(set) var lineCalls = 0
    init(value: EvoLine) { self.value = value }
    func line(baseSpeciesID: Int) async throws -> EvoLine { lineCalls += 1; return value }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [BaseSpecies(id: value.baseID, captureRate: 255)] }
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
// Wurmple: 265 → {266 → 267, 268 → 269}
private let wurmpleLine = makeLine(base: 265, tree: node(265, [node(266, [node(267)]), node(268, [node(269)])]))
// Oddish: 43 → 44 → {45, 182}
private let delayedBranchLine = makeLine(base: 43, tree: node(43, [node(44, [node(45), node(182)])]))
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

    // MARK: 상태 파일 decode 복원력 (회귀)

    /// [회귀] 도감 항목 하나가 손상돼도(구버전/필드 누락) 나머지 도감·companion·인벤토리를 지킨다 —
    /// 예전엔 `[DexEntry]` 배열 전체 decode 가 throw 돼 상태가 전면 초기화됐다(항목별 격리로 수정).
    func testCorruptDexEntryDroppedWhileRestSurvives() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-dex-\(UUID().uuidString).json")
        // 유효 2개 + 손상 1개(finalID/chainOrder 누락).
        let json = #"{"dex":[{"baseID":1,"finalID":3,"chainOrder":[1,2,3],"rarity":"common"},"#
            + #"{"baseID":99,"rarity":"rare"},"#
            + #"{"baseID":7,"finalID":9,"chainOrder":[7,8,9],"rarity":"uncommon"}],"inventory":{"rareCandy":2}}"#
        try Data(json.utf8).write(to: url)

        let s = CompanionStore(provider: StubProvider(value: linear3), clock: { fixedNow },
                               fileURL: url, rng: SeededRNG(seed: 7))

        XCTAssertEqual(s.state.dex.count, 2, "손상 항목만 드롭, 유효 2개 유지")
        XCTAssertEqual(Set(s.state.dex.map(\.baseID)), [1, 7])
        XCTAssertEqual(s.state.inventory["rareCandy"], 2, "도감 손상이 다른 상태(인벤토리)를 날리지 않음")
    }

    /// [회귀] 전면 손상 상태 파일은 fresh 로 시작하되, 다음 save() 가 덮어써 영구 유실되기 전에
    /// 원본을 `.corrupt` 로 백업해 수동 복구 여지를 남긴다.
    func testCorruptStateFileBackedUpBeforeReset() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-corrupt-\(UUID().uuidString).json")
        let garbage = "this is not valid json {{{ 손상"
        try Data(garbage.utf8).write(to: url)

        let s = CompanionStore(provider: StubProvider(value: linear3), clock: { fixedNow },
                               fileURL: url, rng: SeededRNG(seed: 7))

        XCTAssertTrue(s.state.dex.isEmpty)
        XCTAssertNil(s.state.active)
        XCTAssertEqual(s.state.usedSinceInstall, 0, "fresh state 로 시작")

        let backup = url.appendingPathExtension("corrupt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path), "손상 원본이 .corrupt 로 백업돼야 한다")
        XCTAssertEqual(try String(contentsOf: backup, encoding: .utf8), garbage, "백업 내용 = 원본 그대로")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "원본은 이동돼 사라짐")
        try? FileManager.default.removeItem(at: backup)
    }

    /// [회귀] active(현재 포켓몬)가 손상돼도(pathIDs 누락 등) 알로 폴백하되 도감·인벤토리·누적은 보존한다 —
    /// 예전엔 active decode 실패가 CompanionState 전체를 throw 시켜 전면 초기화됐다(필드별 관대화로 수정).
    func testCorruptActiveFallsBackToEggWhileRestSurvives() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-active-corrupt-\(UUID().uuidString).json")
        // active 는 pathIDs 누락 → MonState decode 실패. dex/inventory/usedSinceInstall 은 유효.
        let json = #"{"active":{"baseID":1},"#
            + #""dex":[{"baseID":1,"finalID":3,"chainOrder":[1,2,3],"rarity":"common"}],"#
            + #""inventory":{"rareCandy":3},"usedSinceInstall":5000}"#
        try Data(json.utf8).write(to: url)

        let s = CompanionStore(provider: StubProvider(value: linear3), clock: { fixedNow },
                               fileURL: url, rng: SeededRNG(seed: 7))

        XCTAssertNil(s.state.active, "손상 active 는 nil(알)로 폴백")
        XCTAssertEqual(s.state.dex.count, 1, "도감 보존")
        XCTAssertEqual(s.state.inventory["rareCandy"], 3, "인벤토리 보존")
        XCTAssertEqual(s.state.usedSinceInstall, 5000, "누적 토큰 보존")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.appendingPathExtension("corrupt").path),
                       "부분 복원 — 전면 리셋/백업 아님")
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

    // MARK: 도감 (종 단위 집계 — 로그의 개체 단위와 축이 다르다)

    /// 같은 라인을 두 번 졸업해도 종은 한 칸으로 접힌다 — 로그가 2행인 게 정상이고, 중복은 도감
    /// 쪽에서 구조적으로 사라진다. 도감은 종 정보만 담으므로 성격·획득 횟수는 여기서 보지 않는다.
    func testDexSpeciesFoldsDuplicateLinesToOneCellPerSpecies() throws {
        let entries = [
            DexEntry(baseID: 1, finalID: 3, chainOrder: [1, 2, 3], rarity: .common, caughtAt: fixedNow,
                     nature: .rash,
                     names: [1: ["ko": "포1"], 2: ["ko": "포2"], 3: ["ko": "포3"]]),
            DexEntry(baseID: 1, finalID: 3, chainOrder: [1, 2, 3], rarity: .common, caughtAt: fixedNow,
                     nature: .lax),
        ]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-\(UUID().uuidString).json")
        let dexJSON = String(decoding: try JSONEncoder().encode(entries), as: UTF8.self)
        try Data(#"{"dex":\#(dexJSON),"language":"ko"}"#.utf8).write(to: url)

        let s = CompanionStore(provider: StubProvider(value: linear3), clock: { fixedNow },
                               fileURL: url, rng: SeededRNG(seed: 7))
        XCTAssertEqual(s.state.dex.count, 2, "로그(개체 단위)는 2건")

        let folded = s.dexSpecies
        XCTAssertEqual(folded.map(\.id), [1, 2, 3], "6칸이 아니라 종별 1칸, 도감 번호 오름차순")
        XCTAssertEqual(folded.map(\.name), ["포1", "포2", "포3"], "저장된 이름을 현재 언어로")
        XCTAssertEqual(folded.map(\.rarity), [.common, .common, .common])
    }

    /// 현재 개체는 **도달분**만 보유로 잡힌다. 졸업분을 비워 두면 누수가 종 목록에 그대로 드러난다 —
    /// pathIDs 전체를 쓰면 [1,2], plannedPathIDs(계획 경로)를 쓰면 [1,2,3] 이 되므로 한 상태로
    /// 두 오용을 동시에 가드한다.
    func testDexSpeciesCountsOnlyReachedStagesOfActive() throws {
        let active = MonState(baseID: 1, pathIDs: [1, 2], plannedPathIDs: [1, 2, 3], stageIndex: 0,
                              usedAtStage: 0, rarity: .common, totalForms: 3, nature: .brave)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-\(UUID().uuidString).json")
        let json = String(decoding: try JSONEncoder().encode(active), as: UTF8.self)
        try Data(#"{"active":\#(json),"language":"ko"}"#.utf8).write(to: url)

        let s = CompanionStore(provider: StubProvider(value: linear3), clock: { fixedNow },
                               fileURL: url, rng: SeededRNG(seed: 7))
        XCTAssertTrue(s.state.dex.isEmpty)
        XCTAssertEqual(s.state.active?.stageIndex, 0)
        XCTAssertEqual(s.dexSpecies.map(\.id), [1], "미도달 단계가 보유로 새지 않는다")
    }

    /// 이로치는 종 단위 플래그다 — 개체 하나가 이로치면 그 개체가 지나온 체인 전 종에 표식이 선다.
    /// 일반 개체와 이로치 개체를 둘 다 가진 종도 한 칸으로 접히되 플래그가 서고, 칸은 기본 일반색으로
    /// 그려 두었다가 선택하면 이로치색으로 바꾼다(두 모습을 다 볼 수 있게).
    func testDexSpeciesMarksShinyAcrossTheChain() throws {
        let entries = [
            DexEntry(baseID: 1, finalID: 2, chainOrder: [1, 2], rarity: .common, caughtAt: fixedNow,
                     isShiny: false),
            DexEntry(baseID: 1, finalID: 2, chainOrder: [1, 2], rarity: .common, caughtAt: fixedNow,
                     isShiny: true),
        ]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-\(UUID().uuidString).json")
        let dexJSON = String(decoding: try JSONEncoder().encode(entries), as: UTF8.self)
        try Data(#"{"dex":\#(dexJSON),"language":"ko"}"#.utf8).write(to: url)
        let s = CompanionStore(provider: StubProvider(value: linear3), clock: { fixedNow },
                              fileURL: url, rng: SeededRNG(seed: 7))

        let folded = s.dexSpecies
        XCTAssertEqual(folded.map(\.id), [1, 2], "이로치 개체가 지나온 체인 전 종")
        XCTAssertEqual(folded.map(\.isShiny), [true, true], "한 개체라도 이로치면 종에 플래그")
    }

    // MARK: 대표 플로팅 펫 (육성 대상과 표시 대상 분리)

    /// 구버전 세이브에는 선택 키가 없다. nil 은 기존 동작을 뜻하므로 현재 개체와 shiny 를 그대로 따른다.
    func testRepresentativeDefaultsToCurrentCompanionForLegacySave() throws {
        let active = MonState(baseID: 1, pathIDs: [1], stageIndex: 0, usedAtStage: 0,
                              rarity: .common, totalForms: 3, isShiny: true)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-\(UUID().uuidString).json")
        let activeJSON = String(decoding: try JSONEncoder().encode(active), as: UTF8.self)
        try Data(#"{"active":\#(activeJSON)}"#.utf8).write(to: url)

        let s = CompanionStore(provider: StubProvider(value: linear3), clock: { fixedNow },
                               fileURL: url, rng: SeededRNG(seed: 7))
        XCTAssertNil(s.representativeSpeciesID)
        XCTAssertEqual(s.representativeSubject,
                       CompanionStore.RepresentativeSubject(speciesID: 1, isShiny: true))
    }

    /// 대표 종은 현재 개체와 무관하게 그 종을 그리고, 도감에서 이로치를 보유했다면 이로치 색을 쓴다.
    /// 선택은 companion-state.json 에 저장돼 재실행 후에도 유지된다.
    func testRepresentativeSelectionUsesOwnedShinySpeciesAndPersists() throws {
        let dex = [DexEntry(baseID: 1, finalID: 3, chainOrder: [1, 2, 3], rarity: .common,
                            caughtAt: fixedNow, isShiny: true,
                            names: [1: ["en": "P1"], 2: ["en": "P2"], 3: ["en": "P3"]])]
        let active = MonState(baseID: 20, pathIDs: [20], stageIndex: 0, usedAtStage: 0,
                              rarity: .common, totalForms: 1)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-\(UUID().uuidString).json")
        let dexJSON = String(decoding: try JSONEncoder().encode(dex), as: UTF8.self)
        let activeJSON = String(decoding: try JSONEncoder().encode(active), as: UTF8.self)
        try Data(#"{"dex":\#(dexJSON),"active":\#(activeJSON),"language":"en"}"#.utf8).write(to: url)

        let s = CompanionStore(provider: StubProvider(value: linear3), clock: { fixedNow },
                               fileURL: url, rng: SeededRNG(seed: 7))
        XCTAssertTrue(s.setRepresentativeSpeciesID(2))
        XCTAssertEqual(s.currentSpeciesID, 20, "육성 대상은 그대로")
        XCTAssertEqual(s.representativeSubject,
                       CompanionStore.RepresentativeSubject(speciesID: 2, isShiny: true))

        let reloaded = CompanionStore(provider: StubProvider(value: linear3), clock: { fixedNow },
                                      fileURL: url, rng: SeededRNG(seed: 7))
        XCTAssertEqual(reloaded.representativeSpeciesID, 2)
        XCTAssertEqual(reloaded.representativeSubject,
                       CompanionStore.RepresentativeSubject(speciesID: 2, isShiny: true))
    }

    /// 현재 개체에서 고른 종도 졸업 순간 같은 체인이 영구 dex 로 이동하므로 대표 선택이 끊기지 않는다.
    func testRepresentativeSelectionSurvivesGraduation() async {
        let s = store(linear3)
        await s.hatch(baseID: 1)
        XCTAssertTrue(s.setRepresentativeSpeciesID(1))

        for stage in 0..<3 {
            s.applyUsage(PokemonBalance.phaseThreshold(rarity: .common, totalForms: 3, stageIndex: stage))
            XCTAssertEqual(s.representativeSubject.speciesID, 1,
                           "진화·졸업·새 알 전환이 고정한 대표 포켓몬을 덮어쓰면 안 된다")
        }

        XCTAssertNil(s.state.active, "졸업 후 새 알")
        XCTAssertEqual(s.state.dex.first?.chainOrder, [1, 2, 3])
        XCTAssertEqual(s.representativeSpeciesID, 1, "도감에 영구 보존됐으므로 고정 유지")
        XCTAssertEqual(s.representativeSubject.speciesID, 1)
    }

    /// 메뉴바 관찰자는 이 캐시 하나만 구독한다. 대표 선택을 해제하는 즉시 캐시가 바뀌고
    /// Observation 콜백이 발화해야 다음 사용량 폴링을 기다리지 않고 메뉴바도 현재 개체로 돌아간다.
    func testRepresentativeSubjectNotifiesImmediatelyWhenSelectionChanges() throws {
        let dex = [DexEntry(baseID: 1, finalID: 1, chainOrder: [1], rarity: .common,
                            caughtAt: fixedNow)]
        let active = MonState(baseID: 20, pathIDs: [20], stageIndex: 0, usedAtStage: 0,
                              rarity: .common, totalForms: 1)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-\(UUID().uuidString).json")
        let dexJSON = String(decoding: try JSONEncoder().encode(dex), as: UTF8.self)
        let activeJSON = String(decoding: try JSONEncoder().encode(active), as: UTF8.self)
        try Data(#"{"dex":\#(dexJSON),"active":\#(activeJSON),"representativeSpeciesID":1}"#.utf8)
            .write(to: url)
        let s = CompanionStore(provider: StubProvider(value: linear3), clock: { fixedNow },
                               fileURL: url, rng: SeededRNG(seed: 7))

        nonisolated(unsafe) var didChange = false   // onChange는 동기 발화; 테스트 스레드 밖 접근 없음
        withObservationTracking {
            _ = s.representativeSubject
        } onChange: {
            didChange = true
        }

        XCTAssertTrue(s.setRepresentativeSpeciesID(nil))
        XCTAssertTrue(didChange)
        XCTAssertEqual(s.representativeSubject.speciesID, 20)
    }

    /// Fresh Egg 로 놓아준 개체도 이제 도감에 남으므로, 그 종을 가리키던 대표 선택은 **유지된다**.
    ///
    /// 예전에는 여기서 선택이 해제됐다 — 놓아주면 종이 도감에서 사라져 존재하지 않는 종을 가리키게
    /// 됐기 때문이다. 종이 남는 지금 해제하면 오히려 사용자가 고른 대표가 이유 없이 풀린다.
    func testFreshEggKeepsRepresentativeSelectionOfReleasedSpecies() throws {
        let active = MonState(baseID: 1, pathIDs: [1], stageIndex: 0, usedAtStage: 0,
                              rarity: .common, totalForms: 3)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-\(UUID().uuidString).json")
        let activeJSON = String(decoding: try JSONEncoder().encode(active), as: UTF8.self)
        try Data(#"{"active":\#(activeJSON),"representativeSpeciesID":1,"usedSinceInstall":1000000000}"#.utf8)
            .write(to: url)

        let s = CompanionStore(provider: StubProvider(value: linear3), clock: { fixedNow },
                               fileURL: url, rng: SeededRNG(seed: 7))
        XCTAssertEqual(s.representativeSpeciesID, 1)
        XCTAssertTrue(s.buyFreshEgg())
        XCTAssertEqual(s.representativeSpeciesID, 1, "놓아준 종도 보유분이라 선택이 유지된다")
        XCTAssertEqual(s.representativeSubject.speciesID, 1, "메뉴바도 그 종을 계속 그린다")
    }

    /// 외부에서 손편집했거나 다른 상태와 잘못 합쳐진 선택은 로드 경계에서 제거한다.
    func testUnavailableRepresentativeSelectionIsDroppedAtLoad() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-\(UUID().uuidString).json")
        try Data(#"{"representativeSpeciesID":999}"#.utf8).write(to: url)

        let s = CompanionStore(provider: StubProvider(value: linear3), clock: { fixedNow },
                               fileURL: url, rng: SeededRNG(seed: 7))
        XCTAssertNil(s.representativeSpeciesID)
        XCTAssertFalse(s.setRepresentativeSpeciesID(999), "도감 밖 종은 새로 저장할 수도 없다")
    }

    /// 위장 메타몽은 리빌 전까지 이로치를 숨긴다 — 도감도 그 규칙을 따라야 한다
    /// (currentIsShiny 를 재사용하는 지점. 직접 isShiny 를 읽으면 정체가 미리 새어 나간다).
    func testDexSpeciesHidesShinyWhileDittoIsDisguised() throws {
        func store(revealed: Bool) throws -> CompanionStore {
            let active = MonState(baseID: 1, pathIDs: [1], stageIndex: 0, usedAtStage: 0,
                                  rarity: .common, totalForms: 3, isShiny: true,
                                  dittoDisguise: 1, dittoRevealed: revealed)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("poke-\(UUID().uuidString).json")
            let json = String(decoding: try JSONEncoder().encode(active), as: UTF8.self)
            try Data(#"{"active":\#(json),"language":"ko"}"#.utf8).write(to: url)
            return CompanionStore(provider: StubProvider(value: linear3), clock: { fixedNow },
                                  fileURL: url, rng: SeededRNG(seed: 7))
        }
        let disguised = try store(revealed: false)
        XCTAssertTrue(disguised.state.active?.isShiny ?? false, "내부적으론 이로치")
        XCTAssertEqual(disguised.dexSpecies.first?.isShiny, false, "위장 중엔 도감에도 숨김")

        let revealed = try store(revealed: true)
        XCTAssertEqual(revealed.dexSpecies.first?.isShiny, true, "리빌 후엔 도감에 공개")
    }

    /// 지금 키우는 종의 이름은 **로드된 라인**에서 온다 — 졸업분이 아직 없어도 `#id` 로 떨어지지 않는다.
    /// (부화 직후가 이 경로다. 파일 주입 테스트는 currentLine 이 nil 이라 이 분기를 밟지 못한다.)
    func testDexSpeciesNamesActiveSpeciesFromLoadedLine() async {
        let s = store(linear3)
        s.setLanguage(.ko)
        await s.hatch(baseID: 1)
        let sp = s.dexSpecies
        XCTAssertEqual(sp.map(\.id), [1], "도달분만 — 아직 진화 전이라 2·3 은 미보유")
        XCTAssertEqual(sp.first?.name, "포1")
    }

    // MARK: 도감 이름 백필 (격자는 저장분만 읽는다)

    /// 이름이 저장되기 전 버전의 졸업분은 격자에서 `#id` 로 뜬다 — 격자 진입 시 백필이 이를 채운다.
    /// 백필 전/후를 한 테스트에서 함께 본다: 백필 호출을 지우면 첫 단언에서 멈추므로 가드가 살아 있다.
    func testBackfillFillsNamesForEntriesSavedBeforeNamesExisted() async throws {
        let s = try storeWithNamelessEntry()
        XCTAssertNil(s.state.dex.first?.names, "구버전 저장분엔 이름이 없다")
        XCTAssertEqual(s.dexSpecies.map(\.name), ["#1", "#2", "#3"], "백필 전엔 종 번호")

        await s.backfillMissingDexNames()

        XCTAssertEqual(s.dexSpecies.map(\.name), ["포1", "포2", "포3"])
        XCTAssertNotNil(s.state.dex.first?.names, "항목에 저장돼 다음 실행부터 네트워크 0")
    }

    /// 이미 이름이 저장된 항목은 조회하지 않는다 — 격자를 열 때마다 도감 전체를 다시 받아오면 안 된다.
    func testBackfillDoesNotFetchWhenNamesAreAlreadyStored() async throws {
        let entry = DexEntry(baseID: 1, finalID: 3, chainOrder: [1, 2, 3], rarity: .common, caughtAt: fixedNow,
                             names: [1: ["ko": "포1"], 2: ["ko": "포2"], 3: ["ko": "포3"]])
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-\(UUID().uuidString).json")
        let dexJSON = String(decoding: try JSONEncoder().encode([entry]), as: UTF8.self)
        try Data(#"{"dex":\#(dexJSON),"language":"ko"}"#.utf8).write(to: url)
        let provider = CountingLineProvider(value: linear3)
        let s = CompanionStore(provider: provider, clock: { fixedNow }, fileURL: url, rng: SeededRNG(seed: 7))

        await s.backfillMissingDexNames()

        XCTAssertEqual(provider.lineCalls, 0, "저장분은 건너뛴다")
        XCTAssertEqual(s.dexSpecies.map(\.name), ["포1", "포2", "포3"])
    }

    /// 오프라인이면 폴백(`#id`)을 **저장하지 않는다** — 저장해 버리면 이름이 영원히 번호로 굳는다.
    /// 다음 진입(온라인)에서 다시 시도해 채워지는 것까지 확인한다.
    func testBackfillRetriesAfterAnOfflineAttempt() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-\(UUID().uuidString).json")
        let bare = DexEntry(baseID: 1, finalID: 3, chainOrder: [1, 2, 3], rarity: .common, caughtAt: fixedNow)
        let dexJSON = String(decoding: try JSONEncoder().encode([bare]), as: UTF8.self)
        try Data(#"{"dex":\#(dexJSON),"language":"ko"}"#.utf8).write(to: url)

        let offline = CompanionStore(provider: LineThrowsProvider(), clock: { fixedNow },
                                     fileURL: url, rng: SeededRNG(seed: 7))
        await offline.backfillMissingDexNames()
        XCTAssertNil(offline.state.dex.first?.names, "폴백은 저장하지 않는다")
        XCTAssertEqual(offline.dexSpecies.map(\.name), ["#1", "#2", "#3"])

        // 같은 저장 파일을 온라인 provider 로 다시 연다(= 다음 진입).
        let online = CompanionStore(provider: StubProvider(value: linear3), clock: { fixedNow },
                                    fileURL: url, rng: SeededRNG(seed: 7))
        await online.backfillMissingDexNames()
        XCTAssertEqual(online.dexSpecies.map(\.name), ["포1", "포2", "포3"])
    }

    // MARK: 도감 "키우는 중" 표식 (현재 형태 한 칸)

    /// 진화 뒤에도 Raising 은 현재 형태에만 선다. 지나온 형태를 함께 표시하면 두 포켓몬을 동시에
    /// 키우는 것처럼 읽히므로, 도감 포함 여부와 현재 상태 표식은 서로 다른 규칙이다.
    func testDexSpeciesMarksOnlyCurrentEvolutionStageAsRaising() async {
        let s = store(linear3)
        s.setLanguage(.ko)
        await s.hatch(baseID: 1)
        s.applyUsage(PokemonBalance.phaseThreshold(rarity: .common, totalForms: 3, stageIndex: 0))
        XCTAssertEqual(s.state.active?.stageIndex, 1, "2단계까지 진화")

        let sp = s.dexSpecies
        XCTAssertEqual(sp.map(\.id), [1, 2])
        XCTAssertEqual(sp.map(\.isRaising), [false, true])
    }

    /// 같은 라인을 이미 졸업했어도 현재 다시 키우는 형태에는 Raising 이 선다. 이 뱃지는 기록의
    /// 영구 보존 여부가 아니라 지금 키우는 포켓몬을 뜻한다.
    func testAlreadyGraduatedLineStillMarksOnlyCurrentStageAsRaising() throws {
        let graduated = DexEntry(baseID: 1, finalID: 3, chainOrder: [1, 2, 3], rarity: .common, caughtAt: fixedNow,
                                 names: [1: ["ko": "포1"], 2: ["ko": "포2"], 3: ["ko": "포3"]])
        let active = MonState(baseID: 1, pathIDs: [1, 2, 3], stageIndex: 1,
                              usedAtStage: 0, rarity: .common, totalForms: 3, nature: .brave)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-\(UUID().uuidString).json")
        let dexJSON = String(decoding: try JSONEncoder().encode([graduated]), as: UTF8.self)
        let activeJSON = String(decoding: try JSONEncoder().encode(active), as: UTF8.self)
        try Data(#"{"dex":\#(dexJSON),"active":\#(activeJSON),"language":"ko"}"#.utf8).write(to: url)

        let s = CompanionStore(provider: StubProvider(value: linear3), clock: { fixedNow },
                               fileURL: url, rng: SeededRNG(seed: 7))
        XCTAssertEqual(s.dexSpecies.map(\.isRaising), [false, true, false])
    }

    // MARK: 놓아줌 (알 구매로 포기한 개체의 영구 기록)

    /// [회귀·트리거] 3단 라인을 2단까지 키우다 놓아주면 **도달한 두 형태만** 남는다.
    ///
    /// 트리거 분기: `pathIDs` 는 실현 경로, `plannedPathIDs` 는 전체 계획이다. 놓아줌 기록에
    /// 계획을 쓰면 한 번도 본 적 없는 최종 진화형이 보유로 잡힌다 — 알을 사서 포기하는 것이
    /// 도감을 채우는 지름길이 된다. `dexSpecies` 가 육성 중 쓰는 prefix 규칙과 같아야 한다.
    func testReleasingMidChainCreditsOnlyReachedForms() throws {
        let active = MonState(baseID: 1, pathIDs: [1, 2], plannedPathIDs: [1, 2, 3], stageIndex: 1,
                              usedAtStage: 0, rarity: .common, totalForms: 3)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-\(UUID().uuidString).json")
        let activeJSON = String(decoding: try JSONEncoder().encode(active), as: UTF8.self)
        try Data(#"{"active":\#(activeJSON),"usedSinceInstall":5000000000}"#.utf8).write(to: url)

        let s = CompanionStore(provider: StubProvider(value: linear3), clock: { fixedNow },
                               fileURL: url, rng: SeededRNG(seed: 7))
        XCTAssertEqual(s.dexSpecies.map(\.id), [1, 2], "육성 중 도달분")
        XCTAssertTrue(s.buyFreshEgg())

        XCTAssertEqual(s.dexSpecies.map(\.id), [1, 2], "놓아준 뒤에도 같은 두 종")
        let released = try XCTUnwrap(s.state.dex.last)
        XCTAssertEqual(released.chainOrder, [1, 2])
        XCTAssertEqual(released.finalID, 2, "도달한 마지막 형태")
        XCTAssertFalse(s.dexSpecies.contains { $0.id == 3 }, "미도달 진화형은 보유가 아니다")
    }

    /// 위장 중인 메타몽을 놓아주면 이로치는 계속 숨겨진다 — `currentIsShiny` 단일 판정을 따른다.
    /// 기록에 `a.isShiny` 를 그대로 쓰면 놓아주는 것이 리빌 수단이 된다.
    func testReleasingDisguisedDittoKeepsShinyHidden() throws {
        let active = MonState(baseID: 1, pathIDs: [1], stageIndex: 0, usedAtStage: 0,
                              rarity: .common, totalForms: 3, isShiny: true,
                              dittoDisguise: 1, dittoRevealed: false)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-\(UUID().uuidString).json")
        let activeJSON = String(decoding: try JSONEncoder().encode(active), as: UTF8.self)
        try Data(#"{"active":\#(activeJSON),"usedSinceInstall":5000000000}"#.utf8).write(to: url)

        let s = CompanionStore(provider: StubProvider(value: linear3), clock: { fixedNow },
                               fileURL: url, rng: SeededRNG(seed: 7))
        XCTAssertTrue(s.buyFreshEgg())
        let released = try XCTUnwrap(s.state.dex.last)
        XCTAssertFalse(released.isShiny, "위장 중이면 리빌 전까지 숨김")
    }

    /// 이 필드 이전에 저장된 항목은 전부 졸업분으로 읽힌다 — 별도 마이그레이션 없이 nil = 졸업.
    func testLegacyDexEntriesDecodeAsGraduated() throws {
        let json = #"{"baseID":1,"finalID":3,"chainOrder":[1,2,3],"rarity":"common"}"#
        let entry = try JSONDecoder().decode(DexEntry.self, from: Data(json.utf8))
        XCTAssertNil(entry.releasedAt)
        XCTAssertFalse(entry.isReleased, "구버전 저장분은 졸업분")
    }

    /// 졸업분만 있고 현재 개체가 없으면 표식은 하나도 없다(모두 영구 기록).
    func testGraduatedOnlyDexHasNoRaisingMark() throws {
        let s = try storeWithNamelessEntry()
        XCTAssertNil(s.state.active)
        XCTAssertTrue(s.dexSpecies.allSatisfy { !$0.isRaising })
    }

    /// 이름 없는 구버전 졸업분 1건(체인 1→2→3)만 담긴 store — 백필/표식 테스트 공용.
    private func storeWithNamelessEntry() throws -> CompanionStore {
        let bare = DexEntry(baseID: 1, finalID: 3, chainOrder: [1, 2, 3], rarity: .common, caughtAt: fixedNow)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-\(UUID().uuidString).json")
        let dexJSON = String(decoding: try JSONEncoder().encode([bare]), as: UTF8.self)
        try Data(#"{"dex":\#(dexJSON),"language":"ko"}"#.utf8).write(to: url)
        return CompanionStore(provider: StubProvider(value: linear3), clock: { fixedNow },
                              fileURL: url, rng: SeededRNG(seed: 7))
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
        s.update(todayTokensByProvider: ["test": 0], todayDate: "d1", monthTotal: 0, burnTier: .idle, limitWarning: false, hasUsageData: false)
        XCTAssertFalse(s.state.installBaselineSet)
        // 첫 실데이터 → baseline = 그 시점 today(이전 사용량 미카운트)
        s.update(todayTokensByProvider: ["test": 48_000_000], todayDate: "d1", monthTotal: 0, burnTier: .idle, limitWarning: false, hasUsageData: true)
        XCTAssertTrue(s.state.installBaselineSet)
        XCTAssertEqual(s.state.usedSinceInstall, 0)
        // 이후 증가분만 누적
        s.update(todayTokensByProvider: ["test": 148_000_000], todayDate: "d1", monthTotal: 0, burnTier: .idle, limitWarning: false, hasUsageData: true)
        XCTAssertEqual(s.state.usedSinceInstall, 100_000_000)
    }

    /// [회귀] 로컬 사용량 재집계가 기존 값보다 낮아진 뒤에도, 새 기준점 이후의 증가분은 알에 반영한다.
    /// 예전에는 aggregate high-water mark 로만 유지해 감소 후 증가가 영구히 무시됐다.
    func testUsageIncreaseAfterValidDropContinuesEggProgress() {
        let s = store(linear3)
        base(s)
        use(s, 200)
        XCTAssertEqual(s.state.eggUsage, 200)

        // 유효한 낮은 스냅샷: 이 자체는 토큰 사용량으로 지급하지 않고 기준점만 재설정한다.
        use(s, 40)
        XCTAssertEqual(s.state.eggUsage, 200)
        XCTAssertEqual(s.state.claimedTodayTokensByProvider?["test"], 40)

        // 새 기준점 이후의 증가분만 반영한다.
        use(s, 75)
        XCTAssertEqual(s.state.eggUsage, 235)
        XCTAssertEqual(s.state.usedSinceInstall, 235)
    }

    /// [회귀] 데이터 공백/조회 실패로 today=0 이 들어와도 당일 기준점을 0으로 낮추지 않는다.
    /// 다음 정상 조회 때 당일 전체를 중복 지급하면 안 된다.
    func testEmptyUsageSnapshotDoesNotRebaseDailyLedger() {
        let s = store(linear3)
        base(s)
        use(s, 200)

        use(s, 0, hasUsageData: false) // 빈 스냅샷/조회 공백
        XCTAssertEqual(s.state.eggUsage, 200)
        XCTAssertEqual(s.state.claimedTodayTokensByProvider?["test"], 200)

        use(s, 250)
        XCTAssertEqual(s.state.eggUsage, 250)
        XCTAssertEqual(s.state.usedSinceInstall, 250)
    }

    /// [회귀] 프로바이더 하나가 일시적으로 snapshot을 내놓지 않아도 다른 프로바이더의
    /// 증가분만 적립하고, 사라졌던 프로바이더가 복구될 때 과거 사용량을 중복 지급하지 않는다.
    func testProviderLedgerDoesNotRecreditMissingProviderAfterPartialSnapshotLoss() {
        let s = store(linear3)
        useMap(s, ["claude_code": 0, "codex": 0])
        useMap(s, ["claude_code": 1_000, "codex": 500])
        XCTAssertEqual(s.state.usedSinceInstall, 1_500)

        // codex today == nil인 carrier snapshot은 map에서 빠진다. codex line은 그대로 보존한다.
        useMap(s, ["claude_code": 1_000], hasUsageData: true)
        XCTAssertEqual(s.state.usedSinceInstall, 1_500)
        XCTAssertEqual(s.state.claimedTodayTokensByProvider,
                       ["claude_code": 1_000, "codex": 500])

        // 복구된 codex의 기존 500을 다시 지급하지 않고 이후 증가분만 지급한다.
        useMap(s, ["claude_code": 1_000, "codex": 500])
        XCTAssertEqual(s.state.usedSinceInstall, 1_500)
        useMap(s, ["claude_code": 1_000, "codex": 700])
        XCTAssertEqual(s.state.usedSinceInstall, 1_700)
    }

    /// [회귀] carrier만 남아 오늘 map이 비어도 프로바이더별 ledger를 0으로 낮추지 않는다.
    /// 정상 snapshot 복구 뒤에는 복구 시점 이후 증가분만 적립한다.
    func testCarrierWithoutTodayDataDoesNotRebaseProviderLedger() {
        let s = store(linear3)
        useMap(s, ["codex": 0])
        useMap(s, ["codex": 2_000])
        XCTAssertEqual(s.state.usedSinceInstall, 2_000)

        useMap(s, [:], hasUsageData: false)
        XCTAssertEqual(s.state.usedSinceInstall, 2_000)
        XCTAssertEqual(s.state.claimedTodayTokensByProvider, ["codex": 2_000])

        useMap(s, ["codex": 2_200])
        XCTAssertEqual(s.state.usedSinceInstall, 2_200)
    }

    /// [회귀] 날짜가 바뀌면 이전 날짜의 provider별 기준값과 비교하지 않고,
    /// 새 날짜에 이미 사용한 누적값 전체를 적립한 뒤 이후 증가분을 이어서 적립한다.
    func testDateRolloverCreditsCurrentDayUsage() {
        let s = store(linear3)
        useMap(s, ["codex": 0], date: "d1")
        useMap(s, ["codex": 200], date: "d1")
        XCTAssertEqual(s.state.usedSinceInstall, 200)

        useMap(s, ["codex": 100], date: "d2")
        XCTAssertEqual(s.state.usedSinceInstall, 300)
        XCTAssertEqual(s.state.claimedTodayTokensByProvider, ["codex": 100])

        useMap(s, ["codex": 150], date: "d2")
        XCTAssertEqual(s.state.usedSinceInstall, 350)
    }

    /// [회귀] 날짜 경계의 첫 refresh에서 provider 하나가 빠져도, 같은 날 복구된 현재 사용량을
    /// 누락하지 않는다. 이전 날짜의 ledger 값은 새 날짜와 비교할 수 없으므로 복구 provider의
    /// 새 날짜 기준은 0으로 열고, 그 날 처음 확인된 누적값을 적립한다.
    func testLateProviderRecoveryAfterDateRolloverCreditsCurrentDayUsage() {
        let s = store(linear3)
        useMap(s, ["claude_code": 0, "codex": 0], date: "d1")
        useMap(s, ["claude_code": 1_000, "codex": 500], date: "d1")
        XCTAssertEqual(s.state.usedSinceInstall, 1_500)

        // 날짜가 바뀐 첫 응답에는 codex가 빠졌다. Claude의 d2 사용량만 먼저 적립한다.
        useMap(s, ["claude_code": 100], date: "d2")
        XCTAssertEqual(s.state.usedSinceInstall, 1_600)
        XCTAssertEqual(s.state.claimedTodayTokensByProvider,
                       ["claude_code": 100, "codex": 0])

        // 같은 날 codex가 복구되면 d2의 현재 누적값 전체가 적립되어야 한다.
        useMap(s, ["claude_code": 100, "codex": 700], date: "d2")
        XCTAssertEqual(s.state.usedSinceInstall, 2_300)

        // 이후에는 복구 시점 기준의 증가분만 적립한다.
        useMap(s, ["claude_code": 100, "codex": 900], date: "d2")
        XCTAssertEqual(s.state.usedSinceInstall, 2_500)
    }

    /// [회귀] stale snapshot처럼 오늘 provider map이 비어 있는 refresh는 날짜 경계를 소비하지
    /// 않는다. 다음 유효한 새 날짜 snapshot이 들어오면 그 시점의 오늘 사용량을 적립한다.
    func testStaleSnapshotDoesNotConsumeDateBoundary() {
        let s = store(linear3)
        useMap(s, ["codex": 0], date: "d1")
        useMap(s, ["codex": 200], date: "d1")

        useMap(s, [:], date: "d2", hasUsageData: true)
        XCTAssertEqual(s.state.usedSinceInstall, 200)
        XCTAssertEqual(s.state.lastDate, "d1")
        XCTAssertEqual(s.state.claimedTodayTokensByProvider, ["codex": 200])

        useMap(s, ["codex": 100], date: "d2")
        XCTAssertEqual(s.state.usedSinceInstall, 300)
    }

    /// [마이그레이션] aggregate high-water mark만 가진 구버전 세이브는 값을 프로바이더별로
    /// 추정하지 않고 첫 유효 snapshot을 seed한다. 이후 증가분은 새 ledger로 정상 적립한다.
    func testLegacyAggregateLedgerSeedsProviderMapWithoutRetrospectiveCredit() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-\(UUID().uuidString).json")
        let legacy = #"{"installBaselineSet":true,"usedSinceInstall":10000,"claimedTodayTokens":9000,"lastDate":"d1"}"#
        try Data(legacy.utf8).write(to: url)

        let s = CompanionStore(provider: StubProvider(value: linear3), clock: { fixedNow }, fileURL: url,
                               rng: SeededRNG(seed: 7))
        XCTAssertNil(s.state.claimedTodayTokensByProvider)

        s.update(todayTokensByProvider: ["codex": 500], todayDate: "d1", monthTotal: 0,
                 burnTier: .idle, limitWarning: false, hasUsageData: true)
        XCTAssertEqual(s.state.usedSinceInstall, 10_000)
        XCTAssertEqual(s.state.claimedTodayTokensByProvider, ["codex": 500])

        s.update(todayTokensByProvider: ["codex": 700], todayDate: "d1", monthTotal: 0,
                 burnTier: .idle, limitWarning: false, hasUsageData: true)
        XCTAssertEqual(s.state.usedSinceInstall, 10_200)
    }

    private func base(_ s: CompanionStore) {
        s.update(todayTokensByProvider: ["test": 0], todayDate: "d1", monthTotal: 0, burnTier: .idle, limitWarning: false, hasUsageData: true)
    }
    private func use(_ s: CompanionStore, _ today: Int, hasUsageData: Bool = true) {
        s.update(todayTokensByProvider: ["test": today], todayDate: "d1", monthTotal: 0, burnTier: .idle, limitWarning: false, hasUsageData: hasUsageData)
    }
    private func useMap(_ s: CompanionStore, _ todayTokensByProvider: [String: Int], date: String = "d1",
                        hasUsageData: Bool = true) {
        s.update(todayTokensByProvider: todayTokensByProvider, todayDate: date, monthTotal: 0,
                 burnTier: .idle, limitWarning: false, hasUsageData: hasUsageData)
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

    /// [회귀] 부화한 현재 포켓몬은 졸업 전에도 도감에 보여야 한다. 영구 dex 에 미리 저장하지 않고
    /// 화면용 엔트리로 합쳐, 진화 경로는 즉시 갱신되고 졸업 시 중복이 생기지 않는다.
    func testActiveCompanionAppearsInDexBeforeGraduationWithoutDuplicate() async {
        let s = store(linear3)
        await s.hatch(baseID: 1)

        XCTAssertTrue(s.state.dex.isEmpty, "졸업 전 영구 dex 는 비어 있어야 함")
        XCTAssertEqual(s.dexEntries.count, 1, "현재 포켓몬도 도감 화면에는 즉시 보여야 함")
        XCTAssertEqual(s.dexEntries[0].chainOrder, [1])
        XCTAssertEqual(s.dexEntries[0].finalID, 1)

        s.applyUsage(PokemonBalance.phaseThreshold(rarity: .common, totalForms: 3, stageIndex: 0))
        XCTAssertEqual(s.dexEntries.count, 1)
        XCTAssertEqual(s.dexEntries[0].chainOrder, [1, 2], "진화한 현재 경로가 도감에 반영돼야 함")
        XCTAssertEqual(s.dexEntries[0].finalID, 2)

        s.applyUsage(PokemonBalance.phaseThreshold(rarity: .common, totalForms: 3, stageIndex: 1))
        s.applyUsage(PokemonBalance.phaseThreshold(rarity: .common, totalForms: 3, stageIndex: 2))
        XCTAssertNil(s.state.active)
        XCTAssertEqual(s.state.dex.count, 1, "졸업 시 영구 엔트리 하나만 저장")
        XCTAssertEqual(s.dexEntries.count, 1, "화면용 active 가 영구 엔트리와 중복되면 안 됨")
        XCTAssertEqual(s.dexEntries[0].chainOrder, [1, 2, 3])
    }

    /// 사용자 리포트와 같은 재시작 상태: active 는 저장돼 있지만 dex=[] 인 기존 상태 파일도
    /// 도감 빈 화면으로 떨어지지 않는다.
    func testLoadedActiveCompanionPreventsEmptyDexState() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-active-\(UUID().uuidString).json")
        let json = #"{"active":{"baseID":529,"pathIDs":[529],"stageIndex":0,"usedAtStage":148344233,"rarity":"uncommon","totalForms":2,"isShiny":false,"nature":"timid"},"dex":[]}"#
        try json.data(using: .utf8)!.write(to: url)

        let s = CompanionStore(provider: StubProvider(value: linear3), clock: { fixedNow },
                               fileURL: url, rng: SeededRNG(seed: 7))
        XCTAssertTrue(s.state.dex.isEmpty)
        XCTAssertEqual(s.dexEntries.count, 1)
        XCTAssertEqual(s.dexEntries[0].baseID, 529)
        XCTAssertEqual(s.dexCount(.uncommon), 1)
    }

    /// [회귀] 현재 키우는 common 포켓몬은 더 희귀한 졸업 항목보다도 위에 고정된다.
    /// caughtAt 이 없는 구버전 졸업 항목은 active 로 오인하지 않는다.
    func testActiveCompanionPinnedBeforeGraduatedEntries() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-active-sort-\(UUID().uuidString).json")
        let json = #"{"active":{"baseID":1,"pathIDs":[1],"stageIndex":0,"usedAtStage":5,"rarity":"common","totalForms":3},"dex":[{"id":"legacy-graduated","baseID":150,"finalID":150,"chainOrder":[150],"rarity":"legendary"}]}"#
        try json.data(using: .utf8)!.write(to: url)

        let s = CompanionStore(provider: StubProvider(value: linear3), clock: { fixedNow },
                               fileURL: url, rng: SeededRNG(seed: 7))
        let sorted = s.dexEntriesSorted

        XCTAssertEqual(sorted.map(\.id), ["active-1-1", "legacy-graduated"])
        XCTAssertTrue(s.isActiveDexEntry(sorted[0]))
        XCTAssertFalse(s.isActiveDexEntry(sorted[1]), "caughtAt=nil 만으로 active 를 판별하면 안 됨")
    }

    func testDexRaisingLabelLocalized() {
        XCTAssertEqual(L(.en).dexRaising, "Raising")
        XCTAssertEqual(L(.ko).dexRaising, "키우는 중")
        XCTAssertEqual(L(.ja).dexRaising, "育成中")
    }

    func testUnknownNextEvolutionAccessibilityLabelLocalized() {
        XCTAssertEqual(L(.ko).unknownNextEvolution, "알 수 없는 다음 진화")
        XCTAssertEqual(L(.en).unknownNextEvolution, "Unknown next evolution")
        XCTAssertEqual(L(.ja).unknownNextEvolution, "次の進化先は不明")
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
        XCTAssertNil(state.claimedTodayTokensByProvider)
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

    func testLineNodesPreviewsCompleteLinearEvolution() async {
        let s = store(linear3)
        await s.hatch(baseID: 1)

        XCTAssertEqual(s.lineNodes, [
            EvoLineItem(.species(1), .current),
            EvoLineItem(.species(2), .future),
            EvoLineItem(.species(3), .future),
        ])
    }

    func testRealizedLineItemsUsesStageIndexForCurrentMarker() {
        XCTAssertEqual(CompanionStore.realizedLineItems(pathIDs: [1, 2], stageIndex: 0), [
            EvoLineItem(.species(1), .current),
            EvoLineItem(.species(2), .done),
        ])
    }

    func testRepairedPlanAppendsFallbackRouteToCurrentPath() {
        XCTAssertEqual(CompanionStore.repairedPlan(
            realizedPath: [265], stageIndex: 0, fallbackRoute: [265, 266, 267]),
            [265, 266, 267])
    }

    func testLineNodesHidesUnresolvedWurmpleBranchAsSingleMystery() async {
        let s = store(wurmpleLine)
        await s.hatch(baseID: 265)

        XCTAssertEqual(s.lineNodes, [
            EvoLineItem(.species(265), .current),
            EvoLineItem(.mystery, .future),
        ])
    }

    func testLineNodesShowsKnownPrefixBeforeDownstreamBranchAsMystery() async {
        let s = store(delayedBranchLine)
        await s.hatch(baseID: 43)

        XCTAssertEqual(s.lineNodes, [
            EvoLineItem(.species(43), .current),
            EvoLineItem(.species(44), .future),
            EvoLineItem(.mystery, .future),
        ])
    }

    func testLineNodesRevealsChosenWurmpleBranchAfterEvolution() async throws {
        let s = store(wurmpleLine)
        await s.hatch(baseID: 265)
        let plan = try XCTUnwrap(s.state.active?.plannedPathIDs)
        XCTAssertEqual(plan.count, 3)
        guard plan.count == 3 else { return }

        s.applyUsage(PokemonBalance.phaseThreshold(
            rarity: .common, totalForms: plan.count, stageIndex: 0))

        XCTAssertEqual(s.lineNodes, [
            EvoLineItem(.species(265), .done),
            EvoLineItem(.species(plan[1]), .current),
            EvoLineItem(.species(plan[2]), .future),
        ])
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

    func testHatchPreselectsWurmpleRouteAndEvolutionDoesNotConsumeRNG() async {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-\(UUID().uuidString).json")
        let rng = CountingRNG(seed: 7)
        let s = CompanionStore(provider: StubProvider(value: wurmpleLine), clock: { fixedNow }, fileURL: url, rng: rng)

        await s.hatch(baseID: 265)

        guard let hatched = s.state.active else { return XCTFail("Wurmple should hatch") }
        let plan = hatched.plannedPathIDs
        XCTAssertTrue([[265, 266, 267], [265, 268, 269]].contains(plan), "plan must be one complete root-to-leaf route")
        XCTAssertEqual(hatched.pathIDs, [265], "realized path starts at the base only")
        XCTAssertEqual(hatched.totalForms, plan.count)

        guard plan.count > 1 else { return }

        let callsAfterHatch = rng.callCount
        s.applyUsage(PokemonBalance.phaseThreshold(rarity: hatched.rarity, totalForms: hatched.totalForms, stageIndex: 0))

        XCTAssertEqual(rng.callCount, callsAfterHatch, "evolution must consume the stored plan without rolling RNG")
        XCTAssertEqual(s.state.active?.pathIDs, Array(plan.prefix(2)))
        XCTAssertEqual(s.currentSpeciesID, plan[1])
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

    func testReloadPreservesCompleteShortPlannedRouteLength() async {
        let line = makeLine(base: 1, tree: node(1, [node(2), node(3, [node(4)])]))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-reload-plan-\(UUID().uuidString).json")
        let s1 = CompanionStore(provider: StubProvider(value: line), clock: { fixedNow }, fileURL: url, rng: SeededRNG(seed: 7))
        await s1.hatch(baseID: 1)
        XCTAssertEqual(s1.state.active?.plannedPathIDs, [1, 2], "seed selects the short complete route")

        var opposing = SeededRNG(seed: 1)
        XCTAssertEqual(opposing.next() % 2, 1, "a reroll would select the opposite branch (3)")
        let rng = CountingRNG(seed: 1)
        let s2 = CompanionStore(provider: StubProvider(value: line), clock: { fixedNow }, fileURL: url, rng: rng)
        s2.update(todayTokensByProvider: ["test": 0], todayDate: "d1", monthTotal: 0,
                  burnTier: .idle, limitWarning: false, hasUsageData: true)
        let loaded = await waitUntil { s2.currentLine != nil }
        XCTAssertTrue(loaded, "line should load before evolution")

        XCTAssertNotNil(s2.currentLine)
        XCTAssertEqual(s2.state.active?.plannedPathIDs, [1, 2])
        XCTAssertEqual(s2.state.active?.totalForms, 2)
        let callsAfterLoad = rng.callCount
        s2.applyUsage(PokemonBalance.phaseThreshold(rarity: .common, totalForms: 2, stageIndex: 0))
        XCTAssertEqual(s2.currentSpeciesID, 2, "persisted route must beat the post-restart RNG branch")
        XCTAssertEqual(rng.callCount, callsAfterLoad, "load and evolution must not reroll the persisted route")
    }

    func testReloadLegacyIncompletePlanMigratesToPersistedCompleteRoute() async throws {
        let line = wurmpleLine
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-reload-legacy-\(UUID().uuidString).json")
        let legacy = #"{"active":{"baseID":265,"pathIDs":[265],"stageIndex":0,"usedAtStage":0,"rarity":"common","totalForms":1}}"#
        try Data(legacy.utf8).write(to: url)
        let rng = CountingRNG(seed: 7)
        let s = CompanionStore(provider: StubProvider(value: line), clock: { fixedNow }, fileURL: url, rng: rng)

        s.update(todayTokensByProvider: ["test": 0], todayDate: "d1", monthTotal: 0,
                 burnTier: .idle, limitWarning: false, hasUsageData: true)
        let loaded = await waitUntil { s.currentLine != nil }
        XCTAssertTrue(loaded, "line should load legacy state")

        let migratedPlan = s.state.active?.plannedPathIDs
        XCTAssertTrue([[265, 266, 267], [265, 268, 269]].contains(migratedPlan ?? []))
        XCTAssertEqual(s.state.active?.pathIDs, [265], "realized path must remain intact")
        XCTAssertEqual(s.state.active?.totalForms, migratedPlan?.count)
        XCTAssertEqual(rng.callCount, 2, "Wurmple suffix selection rolls once per evolution edge")

        let reloadRNG = CountingRNG(seed: 1)
        let reloaded = CompanionStore(provider: StubProvider(value: line), clock: { fixedNow }, fileURL: url, rng: reloadRNG)
        reloaded.update(todayTokensByProvider: ["test": 0], todayDate: "d1", monthTotal: 0,
                        burnTier: .idle, limitWarning: false, hasUsageData: true)
        let reloadedLine = await waitUntil { reloaded.currentLine != nil }
        XCTAssertTrue(reloadedLine)
        XCTAssertEqual(reloaded.state.active?.plannedPathIDs, migratedPlan, "migration must persist its one-time choice")
        XCTAssertEqual(reloadRNG.callCount, 0, "a persisted complete route must not reroll on restart")
    }

    func testReloadRepairsInvalidPlanSuffixWithoutRewindingRealizedPath() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-invalid-plan-\(UUID().uuidString).json")
        let saved = #"{"active":{"baseID":265,"pathIDs":[265,266],"plannedPathIDs":[265,266,269],"stageIndex":1,"usedAtStage":42,"rarity":"common","totalForms":3}}"#
        try Data(saved.utf8).write(to: url)
        let s = CompanionStore(provider: StubProvider(value: wurmpleLine), clock: { fixedNow }, fileURL: url, rng: SeededRNG(seed: 9))

        s.update(todayTokensByProvider: ["test": 0], todayDate: "d1", monthTotal: 0,
                 burnTier: .idle, limitWarning: false, hasUsageData: true)
        let loaded = await waitUntil { s.currentLine != nil }
        XCTAssertTrue(loaded)

        XCTAssertEqual(s.state.active?.pathIDs, [265, 266])
        XCTAssertEqual(s.state.active?.plannedPathIDs, [265, 266, 267])
        XCTAssertEqual(s.state.active?.stageIndex, 1)
        XCTAssertEqual(s.state.active?.totalForms, 3)
        XCTAssertEqual(s.state.active?.usedAtStage, 42)
    }

    func testReloadWrongRootNormalizesPathWithoutChangingIdentityOrDisguise() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-wrong-root-\(UUID().uuidString).json")
        let saved = #"{"active":{"baseID":265,"pathIDs":[999],"plannedPathIDs":[999],"stageIndex":0,"usedAtStage":42,"rarity":"common","totalForms":1,"isShiny":true,"nature":"timid","dittoDisguise":265}}"#
        try Data(saved.utf8).write(to: url)
        let s = CompanionStore(provider: StubProvider(value: wurmpleLine), clock: { fixedNow }, fileURL: url, rng: SeededRNG(seed: 9))

        s.update(todayTokensByProvider: ["test": 0], todayDate: "d1", monthTotal: 0,
                 burnTier: .idle, limitWarning: false, hasUsageData: true)
        let loaded = await waitUntil { s.currentLine != nil }
        XCTAssertTrue(loaded)

        XCTAssertEqual(s.state.active?.pathIDs, [265])
        XCTAssertTrue([[265, 266, 267], [265, 268, 269]].contains(s.state.active?.plannedPathIDs ?? []))
        XCTAssertEqual(s.state.active?.usedAtStage, 42)
        XCTAssertTrue(s.state.active?.isShiny ?? false)
        XCTAssertEqual(s.state.active?.nature, .timid)
        XCTAssertEqual(s.state.active?.dittoDisguise, 265)
        XCTAssertFalse(s.state.active?.dittoRevealed ?? true)
    }

    func testReloadLeafCurrentPlanDoesNotConsumeRNG() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-leaf-plan-\(UUID().uuidString).json")
        let saved = #"{"active":{"baseID":265,"pathIDs":[265,266,267],"plannedPathIDs":[265,266,267],"stageIndex":2,"usedAtStage":42,"rarity":"common","totalForms":3}}"#
        try Data(saved.utf8).write(to: url)
        let rng = CountingRNG(seed: 9)
        let s = CompanionStore(provider: StubProvider(value: wurmpleLine), clock: { fixedNow }, fileURL: url, rng: rng)

        s.update(todayTokensByProvider: ["test": 0], todayDate: "d1", monthTotal: 0,
                 burnTier: .idle, limitWarning: false, hasUsageData: true)
        let loaded = await waitUntil { s.currentLine != nil }
        XCTAssertTrue(loaded)

        XCTAssertEqual(s.state.active?.pathIDs, [265, 266, 267])
        XCTAssertEqual(s.state.active?.plannedPathIDs, [265, 266, 267])
        XCTAssertEqual(rng.callCount, 0)
    }

    func testLineLoadPreservesUpdatesMadeWhileProviderIsSuspended() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-load-race-\(UUID().uuidString).json")
        let saved = #"{"active":{"baseID":1,"pathIDs":[1],"stageIndex":0,"usedAtStage":0,"rarity":"common","totalForms":1,"nature":"adamant"},"inventory":{"mint":1}}"#
        try Data(saved.utf8).write(to: url)
        let provider = SuspendedLineProvider(value: linear3)
        let s = CompanionStore(provider: provider, clock: { fixedNow }, fileURL: url, rng: SeededRNG(seed: 7))

        s.update(todayTokensByProvider: ["test": 0], todayDate: "d1", monthTotal: 0,
                 burnTier: .idle, limitWarning: false, hasUsageData: true)
        let suspensionDeadline = Date().addingTimeInterval(1)
        while !(await provider.isSuspended()), Date() < suspensionDeadline {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        let isSuspended = await provider.isSuspended()
        XCTAssertTrue(isSuspended, "line fetch should be suspended")

        s.applyUsage(42)
        let changedNature = try XCTUnwrap(s.useMint())
        XCTAssertEqual(s.state.active?.usedAtStage, 42)
        XCTAssertEqual(s.state.active?.nature, changedNature)

        await provider.resume()
        let loaded = await waitUntil { s.currentLine != nil }
        XCTAssertTrue(loaded)

        XCTAssertEqual(s.state.active?.usedAtStage, 42)
        XCTAssertEqual(s.state.active?.nature, changedNature)
        let persisted = try JSONDecoder().decode(CompanionState.self, from: Data(contentsOf: url))
        XCTAssertEqual(persisted.active?.usedAtStage, 42)
        XCTAssertEqual(persisted.active?.nature, changedNature)
    }

    func testLocalizedName() async {
        let s = store(linear3)
        await s.hatch(baseID: 1)
        s.setLanguage(.ko); XCTAssertEqual(s.displayName, "포1")
        s.setLanguage(.en); XCTAssertEqual(s.displayName, "P1")
        s.setLanguage(.ja); XCTAssertEqual(s.displayName, "ポ1")
    }

    /// [문서화] 비대칭 깊이 분기에서도 부화 시 선택한 경로 길이를 totalForms 로 고정한다.
    /// 크래시·무한루프 없이 최종체에서 졸업하고 실제 경로가 보존됨을 잠근다.
    func testAsymmetricBranchGraduatesSafely() async {
        let line = makeLine(base: 1, tree: node(1, [node(2), node(3, [node(4)])]))   // depth=3, 분기 {2, 3→4}
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-asym-\(UUID().uuidString).json")
        let s = CompanionStore(provider: StubProvider(value: line), clock: { fixedNow }, fileURL: url, rng: SeededRNG(seed: 7))
        await s.hatch(baseID: 1)
        XCTAssertEqual(s.state.active?.totalForms, s.state.active?.plannedPathIDs.count,
                       "totalForms = 선택된 계획 경로 길이")
        var guardCount = 0
        while s.state.active != nil, guardCount < 12 {
            guardCount += 1
            let stage = s.state.active!.stageIndex
            s.applyUsage(PokemonBalance.phaseThreshold(rarity: .common, totalForms: s.state.active!.totalForms, stageIndex: stage))
        }
        XCTAssertNil(s.state.active, "어느 분기든 최종체에서 졸업(크래시·무한루프 없음)")
        XCTAssertEqual(s.dexEntries.count, 1)
        let chain = s.dexEntries[0].chainOrder
        XCTAssertTrue(chain == [1, 2] || chain == [1, 3, 4], "실제 진화 경로 보존: \(chain)")
    }
}

// MARK: 표시 로케일 (자동 생성 문장)

final class AppLanguageTests: XCTestCase {
    func testGermanLanguageMetadata() {
        XCTAssertEqual(AppLanguage.de.rawValue, "de")
        XCTAssertEqual(AppLanguage.de.apiCodes, ["de"])
        XCTAssertEqual(AppLanguage.de.label, "Deutsch")
    }

    func testGermanLanguagePersistsInCompanionState() throws {
        var state = CompanionState()
        state.language = .de

        let data = try JSONEncoder().encode(state)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains(#""language":"de""#))
        XCTAssertEqual(try JSONDecoder().decode(CompanionState.self, from: data).language, .de)
    }

    func testGermanPreferredLanguagesMapToGerman() {
        for identifier in ["de", "de-DE", "de-AT", "DE-de"] {
            XCTAssertEqual(AppLanguage.systemDefault(for: identifier), .de, identifier)
        }
        XCTAssertEqual(AppLanguage.systemDefault(for: "it-IT"), .en)
        XCTAssertEqual(AppLanguage.systemDefault(for: nil), .en)
    }
}

/// 앱 언어와 시스템 로케일이 다를 때 `Text(_, style: .relative)` 같은 자동 문장이 시스템을 따라가면
/// 한 화면에 두 언어가 섞인다(한국어 Mac + 영어 앱 → "Catch log" 옆에 "3시간 46분").
/// 팝오버 루트가 `\.locale` 로 앱 언어를 내려주므로, 그 매핑이 실제로 해당 언어의 상대 시각을
/// 만들어내는지까지 고정한다 — 코드만 비교하면 잘못 매핑해도 통과한다.
final class DisplayLocaleTests: XCTestCase {
    func testDisplayLocaleMatchesLanguageCode() {
        XCTAssertEqual(AppLanguage.ko.displayLocale.identifier, "ko")
        XCTAssertEqual(AppLanguage.en.displayLocale.identifier, "en")
        XCTAssertEqual(AppLanguage.ja.displayLocale.identifier, "ja")
        XCTAssertEqual(AppLanguage.de.displayLocale.identifier, "de")
    }

    func testRelativeTimeFollowsAppLanguageNotSystem() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let past = now.addingTimeInterval(-3 * 3600)

        func relative(_ lang: AppLanguage) -> String {
            let f = RelativeDateTimeFormatter()
            f.locale = lang.displayLocale
            return f.localizedString(for: past, relativeTo: now)
        }

        XCTAssertTrue(relative(.en).contains("hour"), "영어: \(relative(.en))")
        XCTAssertTrue(relative(.ko).contains("시간"), "한국어: \(relative(.ko))")
        XCTAssertTrue(relative(.ja).contains("時間"), "일본어: \(relative(.ja))")
        XCTAssertTrue(relative(.de).lowercased().contains("stund"), "독일어: \(relative(.de))")
        // 네 언어가 서로 달라야 한다 — 하나로 고정돼 있으면 매핑이 죽은 것이다.
        XCTAssertEqual(Set([relative(.en), relative(.ko), relative(.ja), relative(.de)]).count, 4)
    }
}

// MARK: 포획 로그 정렬 / 요약

@MainActor
final class DexSortingTests: XCTestCase {
    /// sortRank 는 목록 정렬 키가 아니지만(로그는 시각순) 프리미엄 알의 등급 게이트가
    /// `line.rarity.sortRank < tier.sortRank` 로 쓴다 — 순서가 뒤집히면 고급/희귀 알이 조용히
    /// 낮은 등급을 통과시킨다. 그래서 순서 보증만 여기 남긴다.
    func testSortRankOrdersRarityAscendingByValue() {
        XCTAssertLessThan(Rarity.common.sortRank, Rarity.uncommon.sortRank)
        XCTAssertLessThan(Rarity.uncommon.sortRank, Rarity.rare.sortRank)
        XCTAssertLessThan(Rarity.rare.sortRank, Rarity.legendary.sortRank)
    }

    /// 로그는 시간순 기록이다 — 희귀도가 높아도 오래되면 아래로 내려간다.
    /// legendary 를 **가장 먼저** 졸업시켜, 희귀도 우선 정렬이면 통과하지 못하게 한다
    /// (과거 정렬은 legendary 를 맨 앞에 고정해 오래된 상위 희귀도가 최신 일반 위에 남았다).
    func testDexEntriesSortedByRecencyRegardlessOfRarity() async {
        // legendary 1개 + common 라인 2개(시각 다름)를 같은 store 에 졸업시킨다.
        // StubProvider 는 라인 1개만 주므로, 라인별로 store 를 분리하지 않고
        // 직접 졸업 흐름을 재현: 무진화(단일 임계) 라인을 hatch→applyUsage 로 졸업.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-\(UUID().uuidString).json")
        var tick = 0
        // 라인을 바꿔가며 졸업시키기 위해 가변 provider 사용.
        let provider = MutableProvider()
        let s = CompanionStore(provider: provider,
                               clock: { fixedNow.addingTimeInterval(TimeInterval(tick)) },
                               fileURL: url, rng: SeededRNG(seed: 3))

        // legendary (가장 먼저 — 희귀도 우선 정렬이면 맨 앞으로 올라온다)
        provider.line = makeLine(base: 200, tree: node(200), rarity: .legendary)
        tick = 1; await s.hatch(baseID: 200)
        s.applyUsage(PokemonBalance.graduationTotal(.legendary))

        // common #1
        provider.line = makeLine(base: 100, tree: node(100), rarity: .common)
        tick = 2; await s.hatch(baseID: 100)
        s.applyUsage(PokemonBalance.graduationTotal(.common))

        // common #2 (가장 나중)
        provider.line = makeLine(base: 101, tree: node(101), rarity: .common)
        tick = 3; await s.hatch(baseID: 101)
        s.applyUsage(PokemonBalance.graduationTotal(.common))

        XCTAssertEqual(s.dexEntries.count, 3)
        let sorted = s.dexEntriesSorted
        // 순수 시간 역순 — 희귀도는 순서에 관여하지 않는다.
        XCTAssertEqual(sorted.map(\.finalID), [101, 100, 200])
        XCTAssertEqual(sorted[2].rarity, .legendary, "가장 오래된 legendary 는 맨 뒤")

        // 희귀도별 카운트(요약 헤더 — 정렬과 무관하게 개체 수 기준)
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
        XCTAssertEqual(s.active?.plannedPathIDs, [1])
        XCTAssertEqual(s.active?.isShiny, false)
        XCTAssertNil(s.active?.nature)
        XCTAssertNil(s.claimedTodayTokensByProvider, "구버전 aggregate ledger는 프로바이더별 값으로 추정하지 않는다")
        XCTAssertEqual(s.dex[0].isShiny, false)
        XCTAssertNil(s.dex[0].nature)
        // 재인코딩 후 재디코딩도 안정적(라운드트립)
        let round = try JSONDecoder().decode(CompanionState.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(round.active?.isShiny, false)
    }

    /// [출시 안전] 손상된 상태 파일: active.pathIDs 가 비면 그 active 만 nil(알)로 폴백하되 나머지 상태는
    /// 보존한다(필드별 관대화). 깨진 active 를 살려두면 currentID out-of-bounds 위험이므로 nil 이어야 한다
    /// (예전엔 전체 디코드를 throw 시켜 상태 전면 초기화 → 도감·인벤토리까지 유실됐다).
    func testEmptyPathIDsActiveFallsBackToNilPreservingRest() {
        let corrupt = """
        {"installBaselineSet":true,"eggUsage":0,"lastDate":"d1",
         "active":{"baseID":1,"pathIDs":[],"stageIndex":0,"usedAtStage":0,"rarity":"common","totalForms":3}}
        """
        let state = try? JSONDecoder().decode(CompanionState.self, from: Data(corrupt.utf8))
        XCTAssertNotNil(state, "빈 pathIDs 는 active 만 무효화 — 전체 디코드는 성공(부분 복원)")
        XCTAssertNil(state?.active, "빈 pathIDs active 는 nil(알)로 폴백 — 깨진 active 를 살려두지 않는다")
        XCTAssertEqual(state?.installBaselineSet, true, "나머지 필드는 보존")
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
        s1.update(todayTokensByProvider: ["test": 0], todayDate: "d1", monthTotal: 0, burnTier: .idle, limitWarning: false, hasUsageData: true)
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
        s2.update(todayTokensByProvider: ["test": 0], todayDate: "d1", monthTotal: 0, burnTier: .idle, limitWarning: false, hasUsageData: true)
        for _ in 0..<50 where s2.currentLine == nil { await Task.yield() }
        XCTAssertNotNil(s2.currentLine)
        XCTAssertEqual(s2.state.active?.stageIndex, 1, "라인 로드 후 적립분으로 진화해야 한다")
        XCTAssertEqual(s2.state.active?.usedAtStage, 300_000_000 - 125_000_000)   // 초과분 이월
    }

    /// [회귀] 구버전 상태가 GIF 미지원 후대 진화형까지 진행했어도, 라인 재로딩 시 마지막 지원 형태로
    /// 복구하고 단계 수를 현재 에셋 개수에 맞춘다. 그렇지 않으면 트리에서 현재 종을 못 찾아 성장이 멈춘다.
    func testLineLoadMigratesPersistedUnsupportedEvolution() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("poke-assets-\(UUID().uuidString).json")
        let json = #"{"installBaselineSet":true,"lastDate":"d1","active":{"baseID":56,"pathIDs":[56,57,979],"stageIndex":2,"usedAtStage":123,"rarity":"common","totalForms":3},"dex":[]}"#
        try Data(json.utf8).write(to: url)
        let supportedLine = makeLine(base: 56, tree: node(56, [node(57, [node(979)])]))
        let s = CompanionStore(provider: StubProvider(value: supportedLine), clock: { fixedNow },
                               fileURL: url, rng: SeededRNG(seed: 5))

        s.update(todayTokensByProvider: ["test": 0], todayDate: "d1", monthTotal: 0,
                 burnTier: .idle, limitWarning: false, hasUsageData: true)
        for _ in 0..<50 where s.currentLine == nil { await Task.yield() }

        XCTAssertNotNil(s.currentLine)
        XCTAssertEqual(s.state.active?.pathIDs, [56, 57])
        XCTAssertEqual(s.state.active?.plannedPathIDs, [56, 57])
        XCTAssertEqual(s.state.active?.stageIndex, 1)
        XCTAssertEqual(s.state.active?.totalForms, 2)
        XCTAssertEqual(s.state.active?.usedAtStage, 123)
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
        s.update(todayTokensByProvider: ["test": 0], todayDate: "d1", monthTotal: 0, burnTier: .idle, limitWarning: false, hasUsageData: true)
        // 알 임계(5M) + stage0 임계(125M) 초과 → 부화 즉시 1회 진화하는 이월
        s.update(todayTokensByProvider: ["test": 135_000_000], todayDate: "d1", monthTotal: 0, burnTier: .idle, limitWarning: false, hasUsageData: true)
        await s.hatchIfNeeded()
        XCTAssertEqual(s.state.active?.isShiny, true)
        XCTAssertEqual(s.state.active?.stageIndex, 1, "이월로 1회 진화했어야 함")
        XCTAssertEqual(s.celebration, .hatch(shiny: true), "evolve 가 shiny 부화 버스트를 덮으면 안 된다")
    }

    /// [회귀] 이월이 졸업 총량을 넘어 부화 즉시 졸업한 극단 케이스 — hatch 연출은 생략(이미 도감행).
    func testHatchCelebrationSkippedOnInstantGraduate() async {
        let s = store(noEvo, seed: 11)
        s.update(todayTokensByProvider: ["test": 0], todayDate: "d1", monthTotal: 0, burnTier: .idle, limitWarning: false, hasUsageData: true)
        // 알 임계 + 졸업 총량(750M) 초과
        s.update(todayTokensByProvider: ["test": 800_000_000], todayDate: "d1", monthTotal: 0, burnTier: .idle, limitWarning: false, hasUsageData: true)
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
        s.update(todayTokensByProvider: ["test": 1_000], todayDate: "d1", monthTotal: 0, burnTier: .idle, limitWarning: false, hasUsageData: true)
        for _ in 0..<50 where s.state.pendingHatchID == nil { await Task.yield() }
        XCTAssertEqual(s.state.pendingHatchID, 77, "알 상태에서 종이 미리 롤/저장돼야 한다")
        // 임계 도달 → 부화는 pending 그대로 (추가 선택 롤 없음: shiny/nature 만 소비)
        s.update(todayTokensByProvider: ["test": 6_000_000], todayDate: "d1", monthTotal: 0, burnTier: .idle, limitWarning: false, hasUsageData: true)
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
        s.update(todayTokensByProvider: ["test": 0], todayDate: "d1", monthTotal: 0, burnTier: .idle, limitWarning: false, hasUsageData: true)
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

    func testGermanNatureNamesMatchOfficialMainlineNames() {
        let expected = [
            "Robust", "Solo", "Mutig", "Hart", "Frech",
            "Kühn", "Sanft", "Locker", "Pfiffig", "Lasch",
            "Scheu", "Hastig", "Ernst", "Froh", "Naiv",
            "Mäßig", "Mild", "Ruhig", "Zaghaft", "Hitzig",
            "Still", "Zart", "Forsch", "Sacht", "Kauzig",
        ]

        XCTAssertEqual(PokemonNature.allCases.map { $0.name(.de) }, expected)
    }

    func testGermanItemNamesUseOfficialMainlineTerms() {
        let l = L(.de)
        XCTAssertEqual(l.itemName(.rareCandy), "Sonderbonbon")
        XCTAssertEqual(l.itemName(.shinyCharm), "Schillerpin")
    }

    /// 성격 25종 — 모든 지원 언어 명칭이 전부 비어있지 않고 중복 없는지.
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
