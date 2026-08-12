import AppKit
import SwiftUI
import XCTest
@testable import PokeDexBar

/// 제안 화면 렌더 테스트가 쓰는 프로바이더 — 빈 인덱스를 돌려줘 `ProfessorOfferSection.task` 가
/// `refreshProfessorOffers` 를 다시 부르지 않게 한다(`ProfessorTests.StubOfferProvider` 와 같은
/// 패턴 — `private` 라 파일을 넘어 재사용을 못 해 이 파일에도 하나 둔다).
private struct StubOfferProvider: PokeProviding {
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: baseSpeciesID, tree: EvoNode(speciesID: baseSpeciesID, children: []),
                rarity: .common, names: [:])
    }
}

/// 가려진 채로 오는 제안 — 한 칸씩 연다.
@MainActor
final class BlindOfferTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeStore() -> PlayerStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("blind-\(UUID().uuidString).json")
        return PlayerStore(fileURL: url, rng: SeededRNG(seed: 1), now: { self.now })
    }

    private func index() -> [BaseSpecies] {
        [BaseSpecies(id: 1, captureRate: 255, isLegendary: false, isMythical: false),
         BaseSpecies(id: 4, captureRate: 45, isLegendary: false, isMythical: false),
         BaseSpecies(id: 25, captureRate: 190, isLegendary: false, isMythical: false),
         BaseSpecies(id: 133, captureRate: 35, isLegendary: false, isMythical: false),
         BaseSpecies(id: 150, captureRate: 3, isLegendary: true, isMythical: false)]
    }

    private func prepared() -> PlayerStore {
        let store = makeStore()
        store.update(todayTokens: 0, todayDate: "2026-08-12", hasUsageData: true)
        store.refreshProfessorOffers(index: index())
        return store
    }

    /// 새로 뽑힌 제안은 셋 다 닫혀 있다.
    func testFreshOffersArriveClosed() {
        let store = prepared()
        XCTAssertEqual(store.state.professorOffers.count, 3)
        XCTAssertTrue(store.state.professorOffers.allSatisfy { !$0.opened })
    }

    /// 열면 그 칸만 열리고, **포인트는 안 줄어든다** — 값은 데려갈 때 치른다.
    func testOpeningCostsNothingAndOpensOnlyThatSlot() {
        let store = prepared()
        store.mutate { $0.researchPoints = 500 }
        let first = store.state.professorOffers[0]

        XCTAssertEqual(store.openProfessorOffer(offerID: first.id)?.id, first.individual.id)
        XCTAssertEqual(store.state.researchPoints, 500, "여는 데 값이 나갔다")
        XCTAssertTrue(store.state.professorOffers[0].opened)
        XCTAssertFalse(store.state.professorOffers[1].opened, "옆 칸까지 열렸다")
        XCTAssertFalse(store.state.professorOffers[2].opened)
    }

    /// 같은 칸을 두 번 열어도 아무 일 없다 — 두 번째는 nil 이라 연출도 다시 안 뜬다.
    func testOpeningTwiceIsHarmless() {
        let store = prepared()
        let first = store.state.professorOffers[0]
        XCTAssertNotNil(store.openProfessorOffer(offerID: first.id))
        XCTAssertNil(store.openProfessorOffer(offerID: first.id))
        XCTAssertTrue(store.state.professorOffers[0].opened)
    }

    /// 없는 자리는 아무 일 없다.
    func testOpeningAnUnknownSlotDoesNothing() {
        let store = prepared()
        XCTAssertNil(store.openProfessorOffer(offerID: UUID()))
        XCTAssertTrue(store.state.professorOffers.allSatisfy { !$0.opened })
    }

    /// **안 연 카드는 못 데려간다 + 포인트 미차감.** 화면이 버튼을 안 그리지만 스토어가
    /// 마지막 방어선이다 — 이 기능에서 화면이 스토어 조건을 다시 적었다가 갈린 적이 있다.
    func testAnUnopenedOfferCannotBeTaken() {
        let store = prepared()
        store.mutate { $0.researchPoints = 1000 }
        let first = store.state.professorOffers[0]

        XCTAssertNil(store.acceptProfessorOffer(offerID: first.id))
        XCTAssertEqual(store.state.researchPoints, 1000, "안 열었는데 포인트가 나갔다")
        XCTAssertTrue(store.state.box.isEmpty)
        XCTAssertFalse(store.state.professorOffers[0].claimed)
    }

    /// 열고 나면 평소대로 데려갈 수 있다 — 가드가 늘 꺼져 있으면 안 된다(대조군).
    func testAnOpenedOfferCanBeTaken() {
        let store = prepared()
        store.mutate { $0.researchPoints = 1000 }
        let first = store.state.professorOffers[0]
        store.openProfessorOffer(offerID: first.id)

        XCTAssertNotNil(store.acceptProfessorOffer(offerID: first.id))
        XCTAssertEqual(store.state.box.count, 1)
    }

    /// **재기동해도 연 것은 열린 채, 안 연 것은 닫힌 채.** 합성 디코더가 기본값 있는 새 필드를
    /// 읽긴 하지만, 이 저장소는 저장은 되고 읽기만 빠지는 부류를 세 번 밟았다 — 실제 파일로 왕복한다.
    func testOpenStateSurvivesARestart() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("blind-save-\(UUID().uuidString).json")
        let store = PlayerStore(fileURL: url, rng: SeededRNG(seed: 1), now: { self.now })
        store.update(todayTokens: 0, todayDate: "2026-08-12", hasUsageData: true)
        store.refreshProfessorOffers(index: index())
        store.openProfessorOffer(offerID: store.state.professorOffers[1].id)

        let reloaded = PlayerStore(fileURL: url, rng: SeededRNG(seed: 1), now: { self.now })
        XCTAssertEqual(reloaded.state.professorOffers.map(\.opened), [false, true, false])
    }

    /// 날짜가 바뀌면 셋 다 다시 닫힌다.
    func testANewDayClosesThemAgain() {
        let store = prepared()
        for offer in store.state.professorOffers { store.openProfessorOffer(offerID: offer.id) }
        XCTAssertTrue(store.state.professorOffers.allSatisfy(\.opened))

        store.update(todayTokens: 1, todayDate: "2026-08-13", hasUsageData: true)
        store.refreshProfessorOffers(index: index())
        XCTAssertTrue(store.state.professorOffers.allSatisfy { !$0.opened },
                      "새 날인데 열린 채로 왔다")
    }

    /// **마이그레이션:** 업그레이드 전 저장에 opened 키가 없어도 제안을 버리지 않고 닫힌 상태로 복구한다.
    /// 손쓴 디코더 없이는 DecodingError.keyNotFound 로 제안 전체가 nil 이 되고, LossyProfessorOffer 의
    /// try? 가 걸러 같은 날 업그레이드한 사용자는 제안 패널이 비어 있다가 자정까지 기다린다.
    func testLegacySaveWithoutOpenedFieldSurvivesAndLoadsAsClosed() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("legacy-offer-\(UUID().uuidString).json")

        // 오래된 저장 형식 — opened 키 없음
        let legacyJSON = """
        {
            "professorOfferDate": "2026-08-12",
            "professorOffers": [
                {
                    "id": "550E8400-E29B-41D4-A716-446655440000",
                    "individual": {
                        "id": "12345678-1234-1234-1234-123456789001",
                        "baseID": 1,
                        "speciesID": 1,
                        "pathIDs": [1],
                        "shiny": false,
                        "nature": "hardy",
                        "exp": 0,
                        "partnerTokens": 0,
                        "partnerSeconds": 0,
                        "candyProgress": 0,
                        "partnerSince": null,
                        "obtainedAt": "2023-11-14T22:13:20Z",
                        "grade": "common",
                        "form": null,
                        "region": null,
                        "regionVariant": null,
                        "partnerStintsEnded": 0,
                        "formBroken": false,
                        "birthForm": null,
                        "disguisedAs": null
                    },
                    "claimed": false
                }
            ]
        }
        """

        try? legacyJSON.data(using: .utf8)?.write(to: url)

        // 레거시 저장 로드 — opened 키가 없어도 제안이 살아남는다
        let decoder = JSONDecoder()
        if let data = try? Data(contentsOf: url),
           let state = try? decoder.decode(PlayerState.self, from: data) {
            XCTAssertEqual(state.professorOffers.count, 1, "제안이 드러났다")
            XCTAssertFalse(state.professorOffers[0].opened, "레거시 제안이 열린 상태로 왔다")
            XCTAssertFalse(state.professorOffers[0].claimed, "클레임 상태가 안 맞는다")
        } else {
            XCTFail("레거시 저장을 디코드할 수 없다")
        }
    }

    // MARK: 닫힌 카드가 무엇을 말하나

    /// **닫힌 카드는 종·등급·가격을 한 글자도 안 말한다.** 블라인드가 새는 것은 "안 보이게
    /// 했다고 생각했는데 라벨에 남아 있는" 식으로 일어나므로, 소스 스캔이 아니라 **닫힌 상태에서
    /// 실제로 그리는 문자열**을 검사한다.
    func testAClosedCardSaysNothingAboutWhatIsInside() {
        let store = prepared()
        let offer = store.state.professorOffers[0]
        let l = store.l
        let shown = ProfessorOfferSection.closedCardText(l: l)

        let grade = offer.individual.grade
        XCTAssertFalse(shown.contains(grade.label(store.language)), "등급이 샜다: \(shown)")
        XCTAssertFalse(shown.contains("\(ProfessorBalance.price(grade: grade))"),
                       "가격이 샜다: \(shown)")
        XCTAssertFalse(shown.contains("\(offer.individual.displaySpeciesID)"),
                       "종 번호가 샜다: \(shown)")
    }

    /// 세 칸이 **같은 문구**를 쓴다 — 칸마다 다르면 그 차이가 곧 힌트다.
    func testEveryClosedCardLooksTheSame() {
        let store = prepared()
        let texts = store.state.professorOffers.map { _ in
            ProfessorOfferSection.closedCardText(l: store.l)
        }
        XCTAssertEqual(Set(texts).count, 1, "닫힌 카드가 서로 다르다: \(texts)")
    }

    /// 문구가 세 언어를 다 채운다.
    func testBlindStringsCoverAllThreeLanguages() {
        for lang in AppLanguage.allCases {
            XCTAssertFalse(L(lang).offerOpen.isEmpty, "\(lang)")
        }
    }

    /// 화면이 여는 경로와 연출에 닿아 있다 — 안 닿으면 영원히 못 연다.
    ///
    /// **소스 스캔이라 배선의 옳고 그름은 못 잰다** — `openProfessorOffer`/`onReveal` 이라는
    /// 글자가 파일 어딘가에 있다는 것만 본다. 엉뚱한 자리를 열거나 잘못된 등급을 연출에 넘겨도
    /// 이 테스트는 그대로 통과한다. 그 구멍은 아래 "실제로 그려 본다" 절의 네 테스트가 메운다.
    /// 그래도 남겨 두는 이유는 둘: ① 배선 자체가 통째로 삭제되는 큰 퇴행을 값싸게 잡고, ②
    /// `ShopTabView` 가 `onReveal:` 을 실제로 받는지는 `ProfessorOfferSection` 만 그리는 아래
    /// 렌더 테스트로는 못 본다 — 상점까지 올라가는 배선은 여전히 이 문자열 검사가 유일하다.
    func testTheSectionReachesTheOpenPathAndTheReveal() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let section = try String(contentsOf: root.appendingPathComponent(
            "Sources/PokeDexBar/UI/ProfessorOfferSection.swift"), encoding: .utf8)
        XCTAssertTrue(section.contains("openProfessorOffer"), "여는 경로에 안 닿는다")
        XCTAssertTrue(section.contains("onReveal"), "연출을 요청하지 않는다")
        XCTAssertFalse(section.contains(".help("), "안 뜨는 툴팁이 들어왔다")

        let shop = try String(contentsOf: root.appendingPathComponent(
            "Sources/PokeDexBar/UI/ShopTabView.swift"), encoding: .utf8)
        XCTAssertTrue(shop.contains("onReveal:"), "상점이 연출 요청을 안 받는다")
    }

    // MARK: 닫힌 카드 — 실제로 그려 본다
    //
    // 위 `testTheSectionReachesTheOpenPathAndTheReveal` 은 문자열만 본다 — 버튼이 엉뚱한 자리를
    // 열거나, `onReveal` 에 잘못된 등급·이로치를 넘기거나, 이미 연 카드에 열기 버튼이 새로 그려지는
    // 결함은 못 잡는다(`ProfessorOfferButton` 계열 결함과 같은 부류). `ProfessorTests.hostedOfferSection`
    // 과 같은 패턴으로 실제 뷰를 그리고, `ProfessorClosedOfferButton` 이 기록한 동작을 직접 불러
    // 배선 자체를 검증한다.

    private func hostedOfferSection(
        _ store: PlayerStore, onReveal: @escaping (Grade, Bool) -> Void = { _, _ in }
    ) -> NSHostingView<AnyView> {
        ProfessorClosedOfferButton.resetConstructed()
        let host = NSHostingView(rootView: AnyView(
            ProfessorOfferSection(store: store, provider: StubOfferProvider(), onReveal: onReveal)
                .frame(width: PopoverMetrics.width)))
        host.layoutSubtreeIfNeeded()
        return host
    }

    /// **세 자리가 서로 다른 등급·이로치를 갖는 제안.** 무작위 뽑기(`prepared`)는 세 자리가 같은
    /// 등급으로 겹치거나 셋 다 이로치가 아닐 수 있다 — 그러면 "엉뚱한 자리를 열어도 등급이 우연히
    /// 맞는다" 류의 결함을 테스트가 못 잡는다. 등급을 common/rare/legendary 로, 이로치는 가운데
    /// 자리에만 걸어 둔다.
    private func distinctOfferStore() -> PlayerStore {
        let store = makeStore()
        let a = Individual(baseID: 1, speciesID: 1, pathIDs: [1], shiny: false,
                           nature: .hardy, exp: 0, obtainedAt: now, grade: .common)
        let b = Individual(baseID: 4, speciesID: 4, pathIDs: [4], shiny: true,
                           nature: .hardy, exp: 0, obtainedAt: now, grade: .rare)
        let c = Individual(baseID: 25, speciesID: 25, pathIDs: [25], shiny: false,
                           nature: .hardy, exp: 0, obtainedAt: now, grade: .legendary)
        store.mutate {
            $0.professorOfferDate = "2026-08-12"
            $0.professorOffers = [ProfessorOffer(individual: a), ProfessorOffer(individual: b),
                                  ProfessorOffer(individual: c)]
        }
        return store
    }

    /// **닫힌 카드 세 칸이 열기 버튼 세 개를 남긴다.** 카드 하나라도 여는 수단 없이 그려지면
    /// 그 자리는 영영 못 연다.
    func testThreeClosedCardsRecordThreeOpenButtons() {
        let store = prepared()

        _ = hostedOfferSection(store)

        let ids = Set(ProfessorClosedOfferButton.constructed.map(\.offerID))
        XCTAssertEqual(ids, Set(store.state.professorOffers.map(\.id)),
                       "닫힌 카드 세 칸의 열기 버튼이 안 맞는다: \(ProfessorClosedOfferButton.constructed.map(\.offerID))")
    }

    /// **기록된 동작을 부르면 그 자리만 열린다.** "값은 맞는데 화면이 엉뚱한 자리를 연다" 류의
    /// 결함은 소스 그렙으로 못 잡는다 — 여기서 자리를 결정적으로 지목해 그 자리만 바뀌었는지 본다.
    func testInvokingTheRecordedOpenActionOpensOnlyThatOffer() {
        let store = prepared()
        let target = store.state.professorOffers[1]   // 가운데 자리 — 결정적으로 지목한다

        _ = hostedOfferSection(store)
        guard let recorded = ProfessorClosedOfferButton.constructed.first(where: {
            $0.offerID == target.id
        }) else {
            return XCTFail("그 자리의 열기 버튼이 안 떴다: \(ProfessorClosedOfferButton.constructed.map(\.offerID))")
        }
        recorded.action()

        XCTAssertEqual(store.state.professorOffers.map(\.opened), [false, true, false],
                       "지목한 자리가 아니라 엉뚱한 자리가 열렸다")
    }

    /// **`onReveal` 이 그 자리의 등급·이로치를 그대로 받는다.** 세 자리가 서로 다른
    /// (`distinctOfferStore`) 상태에서 검사해야 한다 — 셋이 같은 등급이면 엉뚱한 자리를 열어도,
    /// 값을 하드코딩해도 이 단언이 우연히 참이 되어 아무것도 증명하지 못한다.
    func testOnRevealFiresWithThatOffersGradeAndShiny() {
        let store = distinctOfferStore()
        let target = store.state.professorOffers[1]   // rare, 이로치 — 나머지 두 자리와 둘 다 다르다
        var revealed: (grade: Grade, shiny: Bool)?

        _ = hostedOfferSection(store, onReveal: { grade, shiny in revealed = (grade, shiny) })
        guard let recorded = ProfessorClosedOfferButton.constructed.first(where: {
            $0.offerID == target.id
        }) else {
            return XCTFail("그 자리의 열기 버튼이 안 떴다: \(ProfessorClosedOfferButton.constructed.map(\.offerID))")
        }
        recorded.action()

        XCTAssertEqual(revealed?.grade, target.individual.grade, "연출에 넘긴 등급이 그 자리 것이 아니다")
        XCTAssertEqual(revealed?.shiny, target.individual.showsShiny, "연출에 넘긴 이로치 여부가 그 자리 것이 아니다")
    }

    /// **이미 연 카드는 열기 버튼을 안 남긴다.** 닫힌 분기가 열린 상태로 새면 이미 연 자리에
    /// 또 열기 버튼이 뜬다 — `if !offer.opened` 가드 자체가 살아 있는지 렌더로 확인한다.
    func testAnAlreadyOpenCardRecordsNoOpenButton() {
        let store = prepared()
        let opened = store.state.professorOffers[0]
        store.openProfessorOffer(offerID: opened.id)

        _ = hostedOfferSection(store)

        let ids = Set(ProfessorClosedOfferButton.constructed.map(\.offerID))
        XCTAssertFalse(ids.contains(opened.id), "연 카드에도 열기 버튼이 그려졌다")
        XCTAssertEqual(ids, Set([store.state.professorOffers[1].id, store.state.professorOffers[2].id]),
                       "안 연 두 자리의 열기 버튼이 안 맞는다")
    }
}
