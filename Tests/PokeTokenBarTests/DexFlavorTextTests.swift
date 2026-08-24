import XCTest
@testable import PokeTokenBar

// 도감 상세 — 버전별 도감 설명(PokéAPI flavor text)의 정제·접기·언어 선택.
// 네트워크 없이 순수 변환과 스토어 주입 경로만 결정적으로 검증.

private func row(_ version: String, _ lang: String, _ text: String,
                 labels: [String: String] = [:]) -> FlavorRow {
    FlavorRow(versionKey: version, languageCode: lang, text: text, labels: labels)
}

// MARK: 원문 정제

final class DexFlavorSanitizeTests: XCTestCase {
    /// 게임 줄바꿈·페이지 구분은 의미 단위가 아니라 전부 공백으로 흡수. 실제 원문(#25 red) 사용.
    func testCollapsesGameLineBreaksAndPageFeeds() {
        let raw = "When several of\nthese POKéMON\ngather, their\u{000C}electricity could\nbuild"
        XCTAssertEqual(PokeAPIClient.sanitizeFlavorText(raw),
                       "When several of these POKéMON gather, their electricity could build")
    }

    /// soft hyphen 은 게임 폰트용 분철 표시 — 남으면 단어 가운데 하이픈으로 보임.
    func testRemovesSoftHyphen() {
        XCTAssertEqual(PokeAPIClient.sanitizeFlavorText("elec\u{00AD}tricity"), "electricity")
    }

    /// 일본어의 전각 공백(U+3000)은 의도된 표기라 유지, 줄바꿈만 반각 공백으로(#25 sword 원문 모양).
    func testKeepsIdeographicSpaceWhileCollapsingNewlines() {
        let raw = "つくる\u{3000}電気が\u{3000}強力な\nピカチュウほど\u{3000}ほっぺの"
        XCTAssertEqual(PokeAPIClient.sanitizeFlavorText(raw),
                       "つくる\u{3000}電気が\u{3000}強力な ピカチュウほど\u{3000}ほっぺの")
    }

    /// 제어문자가 붙어 있으면 공백이 연달아 생김 — 하나로 접고 양끝은 잘라냄.
    func testCollapsesRunsAndTrimsEdges() {
        XCTAssertEqual(PokeAPIClient.sanitizeFlavorText("\n a \u{000C}\n b \n"), "a b")
    }
}

// MARK: 버전 라벨 폴백

final class DexVersionLabelTests: XCTestCase {
    /// 현지화 이름을 못 얻었을 때만 쓰는 모양 — 슬러그를 읽을 형태로만 정돈.
    func testSluggedLabelIsHumanReadable() {
        XCTAssertEqual(PokeAPIClient.versionLabelFallback("omega-ruby"), "Omega Ruby")
        XCTAssertEqual(PokeAPIClient.versionLabelFallback("black-2"), "Black 2")
        XCTAssertEqual(PokeAPIClient.versionLabelFallback("lets-go-pikachu"), "Lets Go Pikachu")
        XCTAssertEqual(PokeAPIClient.versionLabelFallback("x"), "X")
    }
}

// MARK: 언어별 접기

final class DexFlavorCollapseTests: XCTestCase {
    /// 일본어는 한 버전에 `ja`(한자)·`ja-hrkt`(가나) 두 벌이 오는데 한자가 우선.
    /// 도착 순서가 아니라 `apiCodes` 우선순위로 정해져야 하므로 두 순서 모두 확인.
    func testJapanesePrefersKanjiOverKana() {
        let kanaFirst = [row("x", "ja-hrkt", "かな"), row("x", "ja", "漢字")]
        XCTAssertEqual(PokeAPIClient.collapse(kanaFirst, language: .ja).map(\.text), ["漢字"])

        let kanjiFirst = [row("x", "ja", "漢字"), row("x", "ja-hrkt", "かな")]
        XCTAssertEqual(PokeAPIClient.collapse(kanjiFirst, language: .ja).map(\.text), ["漢字"])
    }

    /// **폴백 단독 분기** — 설명문은 `ja`, 버전 이름은 `ja-hrkt` 뿐인 경우(PokéAPI `/version` 의 실제 모양).
    /// `apiCodes` 에서 `ja-hrkt` 후보가 죽으면 라벨이 슬러그로 떨어지는, 일본어가 실제로 밟는 경로.
    func testJapaneseVersionLabelFallsBackToKanaOnlyName() {
        let rows = [row("sword", "ja", "電気を つくる。", labels: ["ja-hrkt": "ソード"])]
        let out = PokeAPIClient.collapse(rows, language: .ja)
        XCTAssertEqual(out.map(\.versionLabel), ["ソード"],
                       "ja 라벨이 없으면 ja-hrkt 로 내려가야 함 — 슬러그로 새면 일본어 화면에 영어 제목")
    }

    /// REST 폴백은 전 언어가 섞인 응답을 그대로 넘김 — 요청 언어만 남아야 함.
    func testDropsLanguagesThatWereNotRequested() {
        let rows = [row("x", "en", "English"), row("x", "fr", "Français"), row("x", "ko", "한국어")]
        let out = PokeAPIClient.collapse(rows, language: .ko)
        XCTAssertEqual(out.map(\.text), ["한국어"])
    }

    /// 버전 순서는 입력(version_id 오름차순 = 발매순) 유지, 현지화 이름이 없으면 슬러그 정돈본이 라벨.
    /// REST 폴백 경로의 모양.
    func testKeepsReleaseOrderAndUsesSluggedLabelWithoutLocalizedNames() {
        let rows = [row("x", "ko", "설명1"), row("omega-ruby", "ko", "설명2"), row("sword", "ko", "설명3")]
        let out = PokeAPIClient.collapse(rows, language: .ko)
        XCTAssertEqual(out.map(\.versionKey), ["x", "omega-ruby", "sword"])
        XCTAssertEqual(out.map(\.versionLabel), ["X", "Omega Ruby", "Sword"])
    }

    /// 요청 언어 설명이 없으면 빈 목록 — 뷰의 "설명 없음" 입력.
    /// 영어로 대신 채우지 않음(한 화면에 두 언어가 섞이지 않게).
    func testEmptyWhenRequestedLanguageHasNoEntries() {
        let rows = [row("scarlet", "en", "English only")]
        XCTAssertTrue(PokeAPIClient.collapse(rows, language: .ko).isEmpty)
    }

    /// 설명문도 접기 안에서 정제 — 결과가 뷰로 그대로 가므로 여기서 안 하면 아무도 안 함.
    func testSanitizesTextWhileCollapsing() {
        let rows = [row("x", "ko", "꼬리를 세우고\n주변의\u{000C}상황을 살핀다.")]
        XCTAssertEqual(PokeAPIClient.collapse(rows, language: .ko).map(\.text),
                       ["꼬리를 세우고 주변의 상황을 살핀다."])
    }
}

// MARK: 영어 폴백 판정

final class DexEnglishFallbackTests: XCTestCase {
    /// **트리거 분기** — 요청 언어에 한 줄도 없을 때만 영어로 대체.
    /// PokéAPI 에 `pt` 라는 언어 자체가 없어서 브라질 포르투갈어가 실제로 밟는 경로다.
    func testEmptyNonEnglishLanguageFallsBackToEnglish() {
        XCTAssertTrue(PokeAPIClient.needsEnglishFallback(entries: [], language: .pt))
        XCTAssertTrue(PokeAPIClient.needsEnglishFallback(entries: [], language: .ko))
    }

    /// 영어가 비면 더 갈 곳이 없다 — 대체하면 같은 조회를 무한 반복한다.
    func testEmptyEnglishDoesNotFallBack() {
        XCTAssertFalse(PokeAPIClient.needsEnglishFallback(entries: [], language: .en))
    }

    /// 버전 단위 누락은 대체 대상이 **아니다** — 한 줄이라도 있으면 그 언어 그대로 둔다
    /// (없는 세대를 영어로 끼워 넣으면 한 화면에 두 언어가 섞인다).
    func testPartialCoverageKeepsTheRequestedLanguage() {
        let one = [DexFlavorText(versionKey: "x", versionLabel: "X", text: "설명")]
        XCTAssertFalse(PokeAPIClient.needsEnglishFallback(entries: one, language: .ko))
    }
}

// MARK: 스토어 경유(언어 주입·실패 전파)

private enum FlavorStubError: Error { case boom }

/// 도감 설명 요청만 기록하는 스텁 — 부화 경로는 안 쓰므로 line/index 는 최소 구현.
private final class FlavorStubProvider: PokeProviding, @unchecked Sendable {
    let result: DexEntries
    let shouldThrow: Bool
    nonisolated(unsafe) private(set) var receivedLanguage: AppLanguage?
    nonisolated(unsafe) private(set) var receivedSpeciesID: Int?

    init(result: DexEntries = DexEntries(entries: [], language: .en), shouldThrow: Bool = false) {
        self.result = result
        self.shouldThrow = shouldThrow
    }
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw FlavorStubError.boom }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func flavorTexts(speciesID: Int, language: AppLanguage) async throws -> DexEntries {
        receivedSpeciesID = speciesID
        receivedLanguage = language
        if shouldThrow { throw FlavorStubError.boom }
        return result
    }
}

@MainActor
final class DexFlavorStoreTests: XCTestCase {
    private func store(_ provider: FlavorStubProvider) -> CompanionStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("poke-flavor-\(UUID().uuidString).json")
        return CompanionStore(provider: provider, fileURL: url)
    }

    /// 설명은 **앱 언어를 따라감**. 스토어가 언어를 안 넘기면 클라이언트가 조용히 영어로 조회.
    func testPassesCurrentAppLanguageToProvider() async throws {
        let entry = DexFlavorText(versionKey: "sword", versionLabel: "ソード", text: "電気")
        let provider = FlavorStubProvider(result: DexEntries(entries: [entry], language: .ja))
        let s = store(provider)
        s.setLanguage(.ja)

        let out = try await s.dexFlavorTexts(speciesID: 25)

        XCTAssertEqual(provider.receivedLanguage, .ja)
        XCTAssertEqual(provider.receivedSpeciesID, 25)
        XCTAssertEqual(out.entries, [entry])
        XCTAssertFalse(out.isFallback(from: .ja), "요청 언어로 채워졌으면 안내를 띄우지 않는다")
    }

    /// PokéAPI 에 그 언어 도감 설명이 아예 없는 경우(`pt`) — 영어로 채우고 뷰가 안내를 띄울 수 있어야 한다.
    func testEnglishFallbackIsReportedToTheView() async throws {
        let entry = DexFlavorText(versionKey: "sword", versionLabel: "Sword", text: "Electricity")
        let provider = FlavorStubProvider(result: DexEntries(entries: [entry], language: .en))
        let s = store(provider)
        s.setLanguage(.pt)

        let out = try await s.dexFlavorTexts(speciesID: 25)

        XCTAssertEqual(provider.receivedLanguage, .pt, "요청은 앱 언어 그대로 나가야 한다")
        XCTAssertTrue(out.isFallback(from: .pt), "영어로 채워졌으면 안내를 띄워야 한다")
    }

    /// 실패를 삼키지 않음 — `[]` 로 접으면 "설명 없음"과 "못 불러옴"을 구분할 방법이 사라짐.
    func testPropagatesProviderFailureInsteadOfReturningEmpty() async {
        let s = store(FlavorStubProvider(shouldThrow: true))
        do {
            let out = try await s.dexFlavorTexts(speciesID: 25)
            XCTFail("실패가 빈 목록으로 접힘: \(out)")
        } catch {
            // 기대 경로 — 뷰가 실패 화면을 그림.
        }
    }
}
