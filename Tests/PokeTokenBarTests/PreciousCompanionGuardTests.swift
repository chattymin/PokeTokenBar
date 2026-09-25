import XCTest
@testable import PokeTokenBar

private struct NoOpProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

@MainActor
final class PreciousCompanionGuardTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func store(
        active: Bool = true,
        rarity: Rarity = .common,
        shiny: Bool = false,
        dittoDisguise: Int? = nil,
        dittoRevealed: Bool = false
    ) -> CompanionStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("guard-\(UUID().uuidString).json")
        let disguiseField = dittoDisguise != nil ? ",\"dittoDisguise\":\(dittoDisguise!),\"dittoRevealed\":\(dittoRevealed)" : ""
        let mon = "{\"baseID\":10,\"pathIDs\":[10],\"stageIndex\":0,\"usedAtStage\":200000000,"
            + "\"rarity\":\"\(rarity.rawValue)\",\"totalForms\":3,\"isShiny\":\(shiny)\(disguiseField)}"
        let json = "{\"installBaselineSet\":true,\"usedSinceInstall\":5000000000,\"spentTokens\":0,"
            + "\"lastDate\":\"d\",\"active\":\(active ? mon : "null"),\"dex\":[],\"collectedFinals\":[]}"
        try? json.data(using: .utf8)!.write(to: url)
        return CompanionStore(provider: NoOpProvider(), clock: { self.now }, fileURL: url, rng: SeededRNG(seed: 1))
    }

    func testHighValueCompanionIdentifiesLegendaryNonShiny() {
        let s = store(rarity: .legendary, shiny: false)
        XCTAssertEqual(s.rarity, .legendary)
        XCTAssertFalse(s.currentIsShiny)
        XCTAssertTrue(s.isHighValueCompanion, "전설 포켓몬은 비-이로치라도 고가치 개체로 판정되어 2단계 확인을 거친다")
    }

    func testHighValueCompanionIdentifiesShinyNonLegendary() {
        let s = store(rarity: .common, shiny: true)
        XCTAssertEqual(s.rarity, .common)
        XCTAssertTrue(s.currentIsShiny)
        XCTAssertTrue(s.isHighValueCompanion, "이로치 포켓몬은 일반 등급이라도 고가치 개체로 판정된다")
    }

    func testHighValueCompanionIdentifiesShinyLegendary() {
        let s = store(rarity: .legendary, shiny: true)
        XCTAssertEqual(s.rarity, .legendary)
        XCTAssertTrue(s.currentIsShiny)
        XCTAssertTrue(s.isHighValueCompanion, "이로치 전설 포켓몬은 고가치 개체로 판정된다")
    }

    func testHighValueCompanionExcludesCommonNonShiny() {
        let s = store(rarity: .common, shiny: false)
        XCTAssertFalse(s.isHighValueCompanion, "일반 비-이로치 포켓몬은 2단계 경고 없이 즉시 교체 가능")
    }

    func testHighValueCompanionExcludesUncommonNonShiny() {
        let s = store(rarity: .uncommon, shiny: false)
        XCTAssertFalse(s.isHighValueCompanion, "고급 비-이로치 포켓몬은 일반 확인만 거친다")
    }

    func testHighValueCompanionExcludesRareNonShinyToAvoidRerollFatigue() {
        let s = store(rarity: .rare, shiny: false)
        XCTAssertEqual(s.rarity, .rare)
        XCTAssertFalse(s.currentIsShiny)
        XCTAssertFalse(s.isHighValueCompanion, "희귀(rare) 등급은 희귀 알 반복 리롤 피로도를 막기 위해 2단계 경고 대상에서 제외한다")
    }

    func testHighValueCompanionIsFalseWhenNoActive() {
        let s = store(active: false)
        XCTAssertFalse(s.hasActive)
        XCTAssertFalse(s.isHighValueCompanion)
    }

    func testDisguisedDittoDoesNotLeakHighValueStatusBeforeReveal() {
        // 이로치 메타몽이 일반 포켓몬으로 위장 중인 경우
        let s = store(rarity: .common, shiny: true, dittoDisguise: 10, dittoRevealed: false)
        XCTAssertFalse(s.currentIsShiny, "위장 중인 메타몽은 이로치를 숨긴다")
        XCTAssertEqual(s.rarity, .common, "위장 중인 메타몽의 외견 등급은 common")
        XCTAssertFalse(s.isHighValueCompanion, "위장 중에는 고가치 확인을 띄워 정체를 누설(leak)하지 않는다")

        // 리빌된 메타몽인 경우
        let revealed = store(rarity: .rare, shiny: true, dittoDisguise: 10, dittoRevealed: true)
        XCTAssertTrue(revealed.currentIsShiny)
        XCTAssertTrue(revealed.isHighValueCompanion, "리빌 후에는 이로치가 드러나 고가치 개체로 판정된다")
    }

    func testLocalizationStringsCoverAllSevenLanguages() {
        for lang in AppLanguage.allCases {
            let l = L(lang)
            XCTAssertFalse(l.freshEggLegendaryWarning.isEmpty, "전설 경고 문구가 모든 언어(\(lang))에 존재해야 함")
            XCTAssertTrue(l.freshEggLegendaryWarning.hasPrefix("⚠️"), "경고 접두사 ⚠️ 포함")
            XCTAssertFalse(l.freshEggDiscardValuable.isEmpty, "놓아주기 버튼 라벨이 모든 언어(\(lang))에 존재해야 함")
        }

        // 한국어와 영어 문구 특정 검증
        XCTAssertTrue(L(.ko).freshEggLegendaryWarning.contains("전설 포켓몬"))
        XCTAssertEqual(L(.ko).freshEggDiscardValuable, "놓아주기")
        XCTAssertTrue(L(.en).freshEggLegendaryWarning.contains("Legendary"))
        XCTAssertEqual(L(.en).freshEggDiscardValuable, "Send off")
    }
}
