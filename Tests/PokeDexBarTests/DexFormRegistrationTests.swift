import XCTest
@testable import PokeDexBar

@MainActor
final class DexFormRegistrationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeStore() -> PlayerStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dexform-\(UUID().uuidString).json")
        return PlayerStore(fileURL: url, rng: SeededRNG(seed: 1), now: { self.now })
    }

    private func alolanVulpix() -> Individual {
        Individual(baseID: 37, speciesID: 37, pathIDs: [37], nature: .hardy,
                   obtainedAt: now, grade: .common, region: .alola)
    }

    // MARK: 폼별 등록

    /// 알로라 개체를 얻으면 알로라 키만 등록된다 — 원종 키가 따라 들어오면 이 기능이 무의미하다.
    func testARegionalIndividualRegistersOnlyItsForm() {
        let store = makeStore()
        store.addForTesting(alolanVulpix())
        XCTAssertEqual(store.state.dexForms, ["37/vulpix-alola"])
        XCTAssertTrue(store.state.dex.contains(37), "종 단위 파생은 여전히 잡은 것으로 센다")
    }

    /// 대조군 — 원종 개체는 bare 키만.
    func testAPlainIndividualRegistersTheBareKey() {
        let store = makeStore()
        store.addForTesting(Individual(baseID: 37, speciesID: 37, pathIDs: [37], nature: .hardy,
                                       obtainedAt: now, grade: .common))
        XCTAssertEqual(store.state.dexForms, ["37"])
    }

    /// 같은 종의 두 폼은 종 단위로 1로 센다 — 도감 카운터(`N / 1025`)가 부풀면 안 된다.
    func testTwoFormsOfOneSpeciesCountAsOneSpecies() {
        let store = makeStore()
        store.addForTesting(alolanVulpix())
        store.addForTesting(Individual(baseID: 37, speciesID: 37, pathIDs: [37], nature: .hardy,
                                       obtainedAt: now, grade: .common))
        XCTAssertEqual(store.state.dexForms.count, 2)
        XCTAssertEqual(store.state.dex, [37])
    }

    /// 스트린더 — 성격이 로우 계열이면 로우 키로 등록된다.
    func testALowKeyToxtricityRegistersTheLowKeyForm() {
        let store = makeStore()
        store.addForTesting(Individual(baseID: 848, speciesID: 849, pathIDs: [848, 849],
                                       nature: .modest, obtainedAt: now, grade: .common))
        XCTAssertEqual(store.state.dexForms, ["849/toxtricity-lowkey"])
    }

    // MARK: 진화가 폼을 잇는다

    func testEvolutionCarriesTheRegionalFormIntoTheDex() {
        let store = makeStore()
        store.addForTesting(alolanVulpix())
        let vulpix = store.state.box[0]
        let line = EvoLine(baseID: 37,
                           tree: EvoNode(speciesID: 37,
                                         children: [EvoNode(speciesID: 38, children: [])]),
                           rarity: .rare, names: [:])
        XCTAssertTrue(store.evolve(individualID: vulpix.id, to: 38, line: line))
        XCTAssertTrue(store.state.dexForms.contains("38/ninetales-alola"),
                      "알로라 식스테일은 알로라 나인테일즈로 등록돼야 한다")
        XCTAssertFalse(store.state.dexForms.contains("38"), "원종 나인테일즈가 따라 들어오면 안 된다")
    }

    // MARK: 옛 세이브 이전

    /// 옛 세이브의 종 번호는 원종 키로 이전되고("원종 인정"), 박스의 폼은 재스캔으로 붙는다.
    func testLegacyDexMigratesAndTheBoxRescanAddsOwnedForms() throws {
        let json = """
        {"dex": [37, 25],
         "box": [{"baseID": 37, "speciesID": 37, "nature": "hardy", "grade": "common",
                  "region": "alola"}]}
        """
        let state = try JSONDecoder().decode(PlayerState.self, from: Data(json.utf8))
        XCTAssertEqual(state.dexForms, ["37", "25", "37/vulpix-alola"])
        XCTAssertEqual(state.dex, [37, 25])
    }

    /// 대조군 — 박스가 비면 재스캔이 더할 것이 없다(결함 조건이 살아 있는지 보증).
    func testLegacyDexMigrationWithoutABoxAddsNoFormKeys() throws {
        let json = """
        {"dex": [37, 25], "box": []}
        """
        let state = try JSONDecoder().decode(PlayerState.self, from: Data(json.utf8))
        XCTAssertEqual(state.dexForms, ["37", "25"])
    }

    /// 위장 중인 개체는 재스캔이 등록하지 않는다 — 정체가 도감에서 먼저 새면 안 된다
    /// (`claimHatch` 의 유예와 같은 규칙).
    func testTheBoxRescanSkipsDisguisedIndividuals() throws {
        let json = """
        {"box": [{"baseID": 132, "speciesID": 132, "nature": "hardy", "grade": "common",
                  "disguisedAs": 151}]}
        """
        let state = try JSONDecoder().decode(PlayerState.self, from: Data(json.utf8))
        XCTAssertEqual(state.dexForms, [])
    }

    /// 새 형식 세이브 디코드 — 경계 검증이 유령 키만 버리고 정상 키는 지킨다.
    func testBogusDexKeysAreDroppedAtTheDecodeBoundary() throws {
        let json = """
        {"dexForms": ["37/vulpix-alola", "25", "9999", "abc", "6/charizard-mega"], "box": []}
        """
        let state = try JSONDecoder().decode(PlayerState.self, from: Data(json.utf8))
        XCTAssertEqual(state.dexForms, ["37/vulpix-alola", "25"])
    }

    /// 저장 → 재로드 왕복 — dexForms 가 그대로 살아난다(인코딩 누락 방지).
    func testDexFormsSurviveASaveAndReload() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dexform-roundtrip-\(UUID().uuidString).json")
        let store = PlayerStore(fileURL: url, rng: SeededRNG(seed: 1), now: { self.now })
        store.addForTesting(alolanVulpix())
        let reloaded = PlayerStore(fileURL: url, rng: SeededRNG(seed: 1), now: { self.now })
        XCTAssertEqual(reloaded.state.dexForms, ["37/vulpix-alola"])
    }
}
