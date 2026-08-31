import XCTest
@testable import PokeTokenBar

// 순수 모델/파생 로직 — 네트워크·프로세스 없이 결정적으로 검증.

private func evoNode(_ id: Int, _ children: [EvoNode] = []) -> EvoNode { EvoNode(speciesID: id, children: children) }

// MARK: EvoLine 다국어 이름 폴백

final class EvoLineNameTests: XCTestCase {
    func testPicksLanguageSpecificThenFallsBackToEnglishThenID() {
        let line = EvoLine(
            baseID: 1, tree: evoNode(1), rarity: .common,
            names: [
                1: ["ja-Hrkt": "ピカ", "ja": "ピカチュウ", "en": "Pika", "ko": "피카"],
                2: ["en": "Eevee"],   // ja/ko 없음 → en 폴백
                3: [:],               // 비어 있음 → #id
            ])
        // ja 는 ja-Hrkt 를 ja 보다 먼저 시도
        XCTAssertEqual(line.localizedName(1, .ja), "ピカ")
        XCTAssertEqual(line.localizedName(1, .ko), "피카")
        XCTAssertEqual(line.localizedName(1, .en), "Pika")
        // 해당 언어 없으면 en 폴백
        XCTAssertEqual(line.localizedName(2, .ja), "Eevee")
        XCTAssertEqual(line.localizedName(2, .ko), "Eevee")
        // en 도 없으면 #id
        XCTAssertEqual(line.localizedName(3, .ko), "#3")
        // 아예 없는 id
        XCTAssertEqual(line.localizedName(99, .en), "#99")
    }

    func testJaFallsBackFromHrktToPlainJa() {
        let line = EvoLine(baseID: 1, tree: evoNode(1), rarity: .common,
                           names: [1: ["ja": "ピカチュウ", "en": "Pika"]])
        XCTAssertEqual(line.localizedName(1, .ja), "ピカチュウ")   // ja-Hrkt 없음 → ja
    }

    func testGermanNameUsesGermanThenFallsBackToEnglish() {
        let line = EvoLine(
            baseID: 1, tree: evoNode(1), rarity: .common,
            names: [
                1: ["de": "Bisasam", "en": "Bulbasaur"],
                2: ["en": "Ivysaur"],
            ])

        XCTAssertEqual(line.localizedName(1, .de), "Bisasam")
        XCTAssertEqual(line.localizedName(2, .de), "Ivysaur")
    }
}

final class PokeAPILanguageTests: XCTestCase {
    func testFetchedLanguageCodesMatchAppLanguageAPICodesWithoutDuplicates() {
        let expected = AppLanguage.allCases.flatMap(\.apiCodes)

        XCTAssertEqual(PokeAPIClient.langCodes, expected)
        XCTAssertEqual(Set(PokeAPIClient.langCodes).count, PokeAPIClient.langCodes.count)
        XCTAssertTrue(PokeAPIClient.langCodes.contains("de"))
    }
}

// MARK: EvoLine 에셋 지원 범위

final class EvoLineAssetTests: XCTestCase {
    /// PokéAPI 원본 체인에 Gen-V 이후 진화형이 이어져도, 서비스가 제공하는 GIF가 있는 형태만
    /// 실제 진화 라인과 단계 수에 남아야 한다. 예: 망키(#56) → 성원숭(#57) → 저승갓숭(#979).
    func testKeepsOnlyFormsWithAnimatedAssets() {
        let line = EvoLine(
            baseID: 56,
            tree: evoNode(56, [evoNode(57, [evoNode(979)])]),
            rarity: .common,
            names: [:])

        XCTAssertEqual(line.totalForms, 2)
        XCTAssertEqual(line.tree.finalIDs, [57])
        XCTAssertNil(line.tree.node(withID: 979))
    }
}

// MARK: EvoNode 트리 연산

final class EvoNodeTests: XCTestCase {
    // 1 → {2 → 3, 4}  (분기: 3단 경로 + 2단 경로)
    private let tree = EvoNode(speciesID: 1, children: [
        EvoNode(speciesID: 2, children: [EvoNode(speciesID: 3, children: [])]),
        EvoNode(speciesID: 4, children: []),
    ])

    func testDepthIsLongestPath() {
        XCTAssertEqual(tree.depth, 3)            // 1-2-3
        XCTAssertEqual(evoNode(20).depth, 1)     // 무진화
    }

    func testNodeLookupByID() {
        XCTAssertEqual(tree.node(withID: 3)?.speciesID, 3)
        XCTAssertEqual(tree.node(withID: 4)?.speciesID, 4)
        XCTAssertNil(tree.node(withID: 99))
    }

    func testFinalIDsAreLeaves() {
        XCTAssertEqual(Set(tree.finalIDs), [3, 4])
        XCTAssertEqual(evoNode(20).finalIDs, [20])   // 잎이 곧 최종체
    }
}

// MARK: 희귀도 경계

final class RarityBoundaryTests: XCTestCase {
    func testCaptureRateBoundaries() {
        XCTAssertEqual(Rarity.from(captureRate: 45, isLegendary: false, isMythical: false), .rare)      // <=45
        XCTAssertEqual(Rarity.from(captureRate: 46, isLegendary: false, isMythical: false), .uncommon)
        XCTAssertEqual(Rarity.from(captureRate: 120, isLegendary: false, isMythical: false), .uncommon) // <=120
        XCTAssertEqual(Rarity.from(captureRate: 121, isLegendary: false, isMythical: false), .common)
    }

    func testLegendaryAndMythicalOverrideCaptureRate() {
        XCTAssertEqual(Rarity.from(captureRate: 255, isLegendary: true, isMythical: false), .legendary)
        XCTAssertEqual(Rarity.from(captureRate: 255, isLegendary: false, isMythical: true), .legendary)
    }
}

// MARK: OAuth expiresAt 단위 휴리스틱 (초 vs 밀리초)

final class OAuthExpiresAtTests: XCTestCase {
    private func credential(expiresAt raw: String) -> OAuthCredentialData.Credential? {
        let json = "{\"claudeAiOauth\":{\"accessToken\":\"t\",\"expiresAt\":\(raw)}}"
        return OAuthCredentialData.credential(from: Data(json.utf8))
    }

    func testSecondsFormNotTreatedAsMillis() {
        // 10^10 이하면 초 단위로 본다 (밀리초 변환 안 함)
        let future = Int(Date().addingTimeInterval(3600).timeIntervalSince1970)
        XCTAssertEqual(credential(expiresAt: "\(future)")?.isExpired, false)
    }

    func testMillisFormDividedByThousand() {
        let futureMillis = Int(Date().addingTimeInterval(3600).timeIntervalSince1970 * 1000)
        XCTAssertEqual(credential(expiresAt: "\(futureMillis)")?.isExpired, false)
        let pastMillis = Int(Date().addingTimeInterval(-3600).timeIntervalSince1970 * 1000)
        XCTAssertEqual(credential(expiresAt: "\(pastMillis)")?.isExpired, true)
    }

    func testStringFormParsed() {
        let futureMillis = Int(Date().addingTimeInterval(3600).timeIntervalSince1970 * 1000)
        XCTAssertEqual(credential(expiresAt: "\"\(futureMillis)\"")?.isExpired, false)
    }

    func testZeroOrMissingExpiryNeverExpires() {
        XCTAssertEqual(credential(expiresAt: "0")?.isExpired, false)
        let noExpiry = OAuthCredentialData.credential(from: Data(#"{"claudeAiOauth":{"accessToken":"t"}}"#.utf8))
        XCTAssertEqual(noExpiry?.isExpired, false)
    }

    func testRejectsMissingOrEmptyToken() {
        XCTAssertNil(OAuthCredentialData.credential(from: Data(#"{"claudeAiOauth":{"accessToken":""}}"#.utf8)))
        XCTAssertNil(OAuthCredentialData.credential(from: Data(#"{"other":{}}"#.utf8)))
        XCTAssertNil(OAuthCredentialData.credential(from: Data("not json".utf8)))
    }
}

// MARK: ISO8601 가변 정밀도 파서

final class ISO8601ParserTests: XCTestCase {
    func testParsesMicroMilliAndPlainSeconds() {
        XCTAssertNotNil(ISO8601Parser.date(from: "2026-06-10T11:10:00.034464+00:00")) // 마이크로초
        XCTAssertNotNil(ISO8601Parser.date(from: "2026-06-10T11:10:00.303Z"))         // 밀리초
        XCTAssertNotNil(ISO8601Parser.date(from: "2026-06-10T11:10:00Z"))             // 소수점 없음
    }

    func testReturnsNilForGarbage() {
        XCTAssertNil(ISO8601Parser.date(from: "not-a-date"))
        XCTAssertNil(ISO8601Parser.date(from: ""))
    }

    func testMicroAndMilliResolveToSameInstant() {
        let micro = ISO8601Parser.date(from: "2026-06-10T11:10:00.000000Z")
        let plain = ISO8601Parser.date(from: "2026-06-10T11:10:00Z")
        XCTAssertEqual(micro?.timeIntervalSince1970, plain?.timeIntervalSince1970)
    }
}

// MARK: Codex 한도 표시/파생

final class CodexLimitDerivationTests: XCTestCase {
    func testWindowDisplayName() {
        func name(_ mins: Int?) -> String {
            CodexRateLimitWindow(usedPercent: 0, windowDurationMins: mins, resetsAt: nil).displayName
        }
        XCTAssertEqual(name(300), "5시간 세션")
        XCTAssertEqual(name(10_080), "주간")
        XCTAssertEqual(name(120), "2시간")    // 분 단위 → 시간
        XCTAssertEqual(name(90), "90분")      // 시간으로 안 떨어짐
        XCTAssertEqual(name(nil), "한도")
    }

    func testSpendControlUsedPercentClamped() {
        func used(_ remaining: Int) -> Int {
            CodexSpendControlLimit(limit: "$10", remainingPercent: remaining, resetsAt: 0, used: "$3").usedPercent
        }
        XCTAssertEqual(used(30), 70)
        XCTAssertEqual(used(-10), 100)   // 음수 remaining → 100 클램프
        XCTAssertEqual(used(150), 0)     // >100 → 0 클램프
    }

    func testHasVisibleLimitReflectsWindows() {
        let none = CodexRateLimitSnapshot(limitId: nil, limitName: nil, primary: nil, secondary: nil,
                                          credits: nil, individualLimit: nil, planType: nil, rateLimitReachedType: nil)
        XCTAssertFalse(none.hasVisibleLimit)
        let some = CodexRateLimitSnapshot(
            limitId: nil, limitName: nil,
            primary: CodexRateLimitWindow(usedPercent: 10, windowDurationMins: 300, resetsAt: nil),
            secondary: nil, credits: nil, individualLimit: nil, planType: nil, rateLimitReachedType: nil)
        XCTAssertTrue(some.hasVisibleLimit)
    }
}

// MARK: MonState / CompanionState 영속

final class StatePersistenceLogicTests: XCTestCase {
    func testCurrentIDClampsToPath() {
        let m = MonState(baseID: 1, pathIDs: [1, 2, 3], stageIndex: 1, usedAtStage: 0, rarity: .common, totalForms: 3)
        XCTAssertEqual(m.currentID, 2)
        // stageIndex 가 경로를 넘어가도 마지막으로 클램프 (방어)
        let over = MonState(baseID: 1, pathIDs: [1], stageIndex: 5, usedAtStage: 0, rarity: .common, totalForms: 1)
        XCTAssertEqual(over.currentID, 1)
    }

    func testMonStateDecodeClampsStageIndexToRealizedPathBounds() throws {
        let upper = #"{"baseID":1,"pathIDs":[1,2],"stageIndex":5,"usedAtStage":0,"rarity":"common","totalForms":2}"#
        let lower = #"{"baseID":1,"pathIDs":[1,2],"stageIndex":-1,"usedAtStage":0,"rarity":"common","totalForms":2}"#

        let decodedUpper = try JSONDecoder().decode(MonState.self, from: Data(upper.utf8))
        let decodedLower = try JSONDecoder().decode(MonState.self, from: Data(lower.utf8))

        XCTAssertEqual(decodedUpper.stageIndex, 1)
        XCTAssertEqual(decodedLower.stageIndex, 0)
    }

    func testMonStateRoundTripPreservesDistinctPlannedPath() throws {
        let state = MonState(baseID: 265, pathIDs: [265], plannedPathIDs: [265, 266, 267],
                             stageIndex: 0, usedAtStage: 0, rarity: .common, totalForms: 3)

        let decoded = try JSONDecoder().decode(MonState.self, from: JSONEncoder().encode(state))

        XCTAssertEqual(decoded.pathIDs, [265])
        XCTAssertEqual(decoded.plannedPathIDs, [265, 266, 267])
    }

    func testMonStateLegacyDecodeUsesRealizedPathAsPlan() throws {
        let legacy = """
        {"baseID":265,"pathIDs":[265,266],"stageIndex":1,"usedAtStage":0,"rarity":"common","totalForms":3}
        """

        let decoded = try JSONDecoder().decode(MonState.self, from: Data(legacy.utf8))

        XCTAssertEqual(decoded.pathIDs, [265, 266])
        XCTAssertEqual(decoded.plannedPathIDs, [265, 266])
    }

    func testMonStateEmptySavedPlanUsesRealizedPath() throws {
        let saved = """
        {"baseID":265,"pathIDs":[265,266],"plannedPathIDs":[],"stageIndex":1,"usedAtStage":0,"rarity":"common","totalForms":3}
        """

        let decoded = try JSONDecoder().decode(MonState.self, from: Data(saved.utf8))

        XCTAssertEqual(decoded.plannedPathIDs, [265, 266])
    }

    func testMonStateEmptyInitialPlanUsesRealizedPath() {
        let state = MonState(baseID: 265, pathIDs: [265, 266], plannedPathIDs: [],
                             stageIndex: 1, usedAtStage: 0, rarity: .common, totalForms: 3)

        XCTAssertEqual(state.plannedPathIDs, [265, 266])
    }

    func testCompanionStateEncodeDecodeRoundTrip() throws {
        var st = CompanionState()
        st.installBaselineSet = true
        st.usedSinceInstall = 42
        st.eggUsage = 1234
        st.claimedTodayTokensByProvider = ["test": 7]
        st.lastDate = "2026-06-27"
        st.collectedFinals = ["1:3", "10:12"]
        st.language = .ja
        st.dex = [DexEntry(baseID: 1, finalID: 3, chainOrder: [1, 2, 3], rarity: .rare, caughtAt: nil)]

        let data = try JSONEncoder().encode(st)
        let back = try JSONDecoder().decode(CompanionState.self, from: data)

        XCTAssertEqual(back.installBaselineSet, true)
        XCTAssertEqual(back.usedSinceInstall, 42)
        XCTAssertEqual(back.eggUsage, 1234)
        XCTAssertEqual(back.claimedTodayTokensByProvider, ["test": 7])
        XCTAssertEqual(back.lastDate, "2026-06-27")
        XCTAssertEqual(back.collectedFinals, ["1:3", "10:12"])
        XCTAssertEqual(back.language, .ja)
        XCTAssertEqual(back.dex.count, 1)
        XCTAssertEqual(back.dex[0].chainOrder, [1, 2, 3])
    }
}
