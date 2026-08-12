import XCTest
@testable import PokeDexBar

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
}
