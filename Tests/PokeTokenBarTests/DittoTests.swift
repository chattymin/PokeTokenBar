import XCTest
@testable import PokeTokenBar

// MARK: 메타몽 위장/리빌

private func dNode(_ id: Int, _ children: [EvoNode] = []) -> EvoNode { EvoNode(speciesID: id, children: children) }
private func dLine(base: Int, tree: EvoNode, rarity: Rarity) -> EvoLine {
    func ids(_ n: EvoNode) -> [Int] { [n.speciesID] + n.children.flatMap(ids) }
    var names: [Int: [String: String]] = [:]
    for id in ids(tree) { names[id] = ["en": "P\(id)", "ko": "포\(id)", "ja": "ポ\(id)"] }
    return EvoLine(baseID: base, tree: tree, rarity: rarity, names: names)
}
private let disguiseLine = dLine(base: 1, tree: dNode(1, [dNode(2, [dNode(3)])]), rarity: .common) // 커먼 3형태: 첫 진화 125M
private let dittoLine = dLine(base: 132, tree: dNode(132), rarity: .rare)                           // 메타몽: rare 단일형태
private let dNow = Date(timeIntervalSince1970: 1_700_000_000)

/// base 1=위장체 라인, 132=메타몽 라인 반환(리빌 시 필요). StubProvider 는 단일 라인이라 부적합.
private struct DittoTestProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        baseSpeciesID == PokemonOdds.dittoSpeciesID ? dittoLine : disguiseLine
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [BaseSpecies(id: 1, captureRate: 255)] }
}

// MARK: 위장 롤 판정(순수) — 부화 롤은 .app 게이트라 실앱에서만 발동, 판정 로직은 순수 함수로 검증

final class DittoDisguiseRollTests: XCTestCase {
    func testHitCommonMultiFormOnMultipleOfDenominator() {
        XCTAssertTrue(CompanionStore.dittoDisguiseHit(rarity: .common, totalForms: 2, roll: 0))
        XCTAssertTrue(CompanionStore.dittoDisguiseHit(rarity: .common, totalForms: 3, roll: 128))
        XCTAssertTrue(CompanionStore.dittoDisguiseHit(rarity: .common, totalForms: 3, roll: 256))
    }
    func testMissWhenRollNotMultipleOfDenominator() {
        XCTAssertFalse(CompanionStore.dittoDisguiseHit(rarity: .common, totalForms: 3, roll: 1))
        XCTAssertFalse(CompanionStore.dittoDisguiseHit(rarity: .common, totalForms: 3, roll: 127))
        XCTAssertFalse(CompanionStore.dittoDisguiseHit(rarity: .common, totalForms: 3, roll: 129))
    }
    /// 단일형태 제외 — 진화를 못 하면 리빌 트리거(첫 진화 순간)가 없다.
    func testExcludesSingleForm() {
        XCTAssertFalse(CompanionStore.dittoDisguiseHit(rarity: .common, totalForms: 1, roll: 0))
    }
    /// common 만 — uncommon/rare/legendary 위장 불가.
    func testExcludesNonCommon() {
        XCTAssertFalse(CompanionStore.dittoDisguiseHit(rarity: .uncommon, totalForms: 3, roll: 0))
        XCTAssertFalse(CompanionStore.dittoDisguiseHit(rarity: .rare, totalForms: 3, roll: 0))
        XCTAssertFalse(CompanionStore.dittoDisguiseHit(rarity: .legendary, totalForms: 3, roll: 0))
    }
    func testDenominatorIs128() {
        XCTAssertEqual(PokemonOdds.dittoDisguiseDenominator, 128)
    }
}

// MARK: 위장 → 리빌 상태 전환

@MainActor
final class DittoRevealTests: XCTestCase {
    /// 활성 = 커먼 3형태 위장 메타몽(정체). currentLine 은 nil(재시작류) → update 로 로드해 리빌 트리거.
    private func seedDisguise(usedAtStage: Int = 0, shiny: Bool = false, revealed: Bool = false) -> CompanionStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ditto-\(UUID().uuidString).json")
        let active = "{\"baseID\":1,\"pathIDs\":[1],\"stageIndex\":0,\"usedAtStage\":\(usedAtStage),"
            + "\"rarity\":\"common\",\"totalForms\":3,\"isShiny\":\(shiny),"
            + "\"dittoDisguise\":1,\"dittoRevealed\":\(revealed)}"
        let json = "{\"installBaselineSet\":true,\"usedSinceInstall\":1000000000,\"spentTokens\":0,"
            + "\"lastDate\":\"d1\",\"active\":\(active),\"dex\":[],\"collectedFinals\":[]}"
        try? json.data(using: .utf8)!.write(to: url)
        return CompanionStore(provider: DittoTestProvider(), clock: { dNow }, fileURL: url, rng: SeededRNG(seed: 7))
    }

    /// update → loadCurrentLine → applyUsage(0) → (임계 초과 시) revealDitto 비동기 체인을 드레인.
    private func drainReveal(_ s: CompanionStore) async {
        s.update(todayTokens: 0, todayDate: "d1", monthTotal: 0, burnTier: .idle, limitWarning: false, hasUsageData: true)
        for _ in 0..<200 where !(s.state.active?.dittoRevealed ?? false) { await Task.yield() }
    }

    /// 위장 중엔 이로치가 표시상 숨겨진다(내부 isShiny 는 유지 — 리빌 때 공개).
    func testShinyHiddenDuringDisguise() {
        let s = seedDisguise(shiny: true)
        XCTAssertTrue(s.state.active?.isShiny ?? false, "내부적으론 이로치")
        XCTAssertFalse(s.currentIsShiny, "위장 중엔 표시상 숨김")
    }

    /// [트리거 브랜치] 첫 진화 임계에서 진화 대신 메타몽으로 리빌 — 진화 자체를 밟지 않는다.
    func testRevealAtFirstEvolution() async {
        let s = seedDisguise()
        s.applyUsage(300_000_000)   // 라인 미로딩 중 적립(첫 진화 125M 초과) — 진화/리빌 보류
        XCTAssertEqual(s.state.active?.usedAtStage, 300_000_000)
        XCTAssertEqual(s.currentSpeciesID, 1, "아직 위장체 표시")
        XCTAssertFalse(s.state.active?.dittoRevealed ?? true)
        await drainReveal(s)
        XCTAssertTrue(s.state.active?.dittoRevealed ?? false, "첫 진화 임계에서 리빌돼야 한다")
        XCTAssertEqual(s.state.active?.baseID, PokemonOdds.dittoSpeciesID, "메타몽으로 전환")
        XCTAssertEqual(s.currentSpeciesID, PokemonOdds.dittoSpeciesID)
        XCTAssertNotEqual(s.currentSpeciesID, 2, "위장체는 진화하지 않는다")
        XCTAssertEqual(s.state.active?.rarity, .rare, "메타몽 rare")
        XCTAssertEqual(s.state.active?.totalForms, 1, "메타몽 단일형태")
        XCTAssertEqual(s.state.active?.stageIndex, 0)
        XCTAssertEqual(s.state.active?.usedAtStage, 300_000_000 - 125_000_000, "첫 진화 초과분 이월")
        XCTAssertNotNil(s.state.active?.dittoDisguise, "위장 마커 보존")
        XCTAssertEqual(s.celebration, .dittoReveal(shiny: false), "리빌 연출 발화")
    }

    /// 리빌 후 이로치가 공개된다(위장 중 숨겼던 것) + 이로치 리빌 연출.
    func testShinyUnmaskedAfterReveal() async {
        let s = seedDisguise(shiny: true)
        s.applyUsage(300_000_000)
        XCTAssertFalse(s.currentIsShiny, "리빌 전 숨김")
        await drainReveal(s)
        XCTAssertTrue(s.state.active?.dittoRevealed ?? false)
        XCTAssertTrue(s.currentIsShiny, "리빌 후 이로치 공개")
        XCTAssertEqual(s.celebration, .dittoReveal(shiny: true), "이로치 리빌 연출")
    }

    /// 임계 미달이면 리빌하지 않는다(위장 유지).
    func testNoRevealBelowThreshold() async {
        let s = seedDisguise()
        s.applyUsage(100_000_000)   // 첫 진화 125M 미달
        await drainReveal(s)        // (드레인해도 리빌 조건 미충족)
        XCTAssertFalse(s.state.active?.dittoRevealed ?? true, "임계 미달 → 위장 유지")
        XCTAssertEqual(s.currentSpeciesID, 1, "여전히 위장체")
    }

    /// 구버전 저장(ditto 필드 없음) → nil/false, 일반 포켓몬으로 동작(이로치는 그대로 표시).
    func testBackwardCompatDecodeNoDittoFields() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ditto-bc-\(UUID().uuidString).json")
        let active = "{\"baseID\":1,\"pathIDs\":[1],\"stageIndex\":0,\"usedAtStage\":0,"
            + "\"rarity\":\"common\",\"totalForms\":3,\"isShiny\":true}"   // ditto 필드 없음
        let json = "{\"installBaselineSet\":true,\"usedSinceInstall\":0,\"spentTokens\":0,"
            + "\"lastDate\":\"d1\",\"active\":\(active),\"dex\":[],\"collectedFinals\":[]}"
        try? json.data(using: .utf8)!.write(to: url)
        let s = CompanionStore(provider: DittoTestProvider(), clock: { dNow }, fileURL: url, rng: SeededRNG(seed: 7))
        XCTAssertNil(s.state.active?.dittoDisguise)
        XCTAssertFalse(s.state.active?.dittoRevealed ?? true)
        XCTAssertTrue(s.currentIsShiny, "위장 아님 → 이로치 그대로 표시")
    }

    /// 메타몽(#132)은 REST 폴백 부화 후보에서 제외(위장 리빌 전용) — 가드는 네트워크 전 조기 반환.
    func testDittoExcludedFromRestFallback() async throws {
        let result = try await PokeAPIClient().baseSpecies(id: PokemonOdds.dittoSpeciesID)
        XCTAssertNil(result, "메타몽은 일반 부화 후보 아님")
    }
}
