import XCTest
@testable import PokeDexBar

/// 박스 정리가 **저장된 순서**를 바꾼다.
@MainActor
final class BoxTidyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeStore(url: URL? = nil) -> PlayerStore {
        PlayerStore(fileURL: url ?? FileManager.default.temporaryDirectory
                        .appendingPathComponent("tidy-\(UUID().uuidString).json"),
                    rng: SeededRNG(seed: 1), now: { self.now },
                    defaults: UserDefaults(suiteName: UUID().uuidString)!)
    }

    private func seed(_ store: PlayerStore) {
        let box = [
            Individual(baseID: 1, speciesID: 1, pathIDs: [1], nature: .hardy, exp: 0,
                       obtainedAt: now, grade: .common),
            Individual(baseID: 4, speciesID: 4, pathIDs: [4], nature: .hardy,
                       exp: GrowthRate.mediumFast.totalExp(at: 60),
                       obtainedAt: now.addingTimeInterval(10), grade: .legendary),
            Individual(baseID: 7, speciesID: 7, pathIDs: [7], nature: .hardy,
                       exp: GrowthRate.mediumFast.totalExp(at: 30),
                       obtainedAt: now.addingTimeInterval(20), grade: .rare),
        ]
        store.mutate { $0.box = box }
    }

    /// **저장된 순서가 실제로 바뀐다.** 보기만 바뀌는 구현이면 여기서 걸린다.
    func testSortingRearrangesTheStoredBox() {
        let store = makeStore()
        seed(store)
        XCTAssertEqual(store.state.box.map(\.speciesID), [1, 4, 7])

        store.sortBox(.grade)

        XCTAssertEqual(store.state.box.map(\.speciesID), [4, 7, 1], "저장된 배열이 안 바뀌었다")
    }

    /// **재시작해도 그 배치가 남는다.** 저장을 빼먹으면 다음에 열 때 원래대로 돌아온다.
    func testTheNewArrangementSurvivesARestart() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tidy-save-\(UUID().uuidString).json")
        let store = makeStore(url: url)
        seed(store)
        store.sortBox(.levelHigh)
        let expected = store.state.box.map(\.speciesID)
        XCTAssertEqual(expected, [4, 7, 1])

        let reloaded = makeStore(url: url)
        XCTAssertEqual(reloaded.state.box.map(\.speciesID), expected, "정렬이 저장이 안 됐다")
    }

    /// **정렬 뒤에 들어온 개체는 맨 뒤에 붙는다** — 정렬 기준 자리에 끼면 안 된다(결정 2).
    /// 레벨 높은 순으로 정리해 둔 박스에 1레벨을 넣어도 맨 앞이 아니라 맨 뒤다.
    func testANewIndividualLandsAtTheEndNotInSortedPosition() {
        let store = makeStore()
        seed(store)
        store.sortBox(.levelHigh)

        let newborn = Individual(baseID: 25, speciesID: 25, pathIDs: [25], nature: .hardy,
                                 exp: 0, obtainedAt: now.addingTimeInterval(30), grade: .common)
        store.addForTesting(newborn)

        XCTAssertEqual(store.state.box.map(\.speciesID), [4, 7, 1, 25],
                       "새 개체가 정렬 기준 자리에 끼어들었다")
    }

    /// **획득순이 되돌리기다.** 어떤 정렬을 거쳤든 원래 배치로 돌아온다.
    func testObtainedOrderRestoresTheOriginalArrangement() {
        let store = makeStore()
        seed(store)
        let original = store.state.box.map(\.speciesID)

        store.sortBox(.grade)
        store.sortBox(.dex)
        store.sortBox(.levelLow)
        XCTAssertNotEqual(store.state.box.map(\.speciesID), original, "정렬이 아무 일도 안 했다")

        store.sortBox(.obtained)
        XCTAssertEqual(store.state.box.map(\.speciesID), original, "되돌아오지 않는다")
    }

    /// 파트너·도감·부화 슬롯은 정렬과 무관하다 — 재배치일 뿐 아무것도 잃지 않는다.
    func testTidyingTouchesNothingButTheOrder() {
        let store = makeStore()
        seed(store)
        let partnerID = store.state.box[2].id
        store.setPartner(partnerID)
        store.mutate { $0.dexForms = ["1", "4", "7"]; $0.researchPoints = 42 }

        store.sortBox(.dex)

        XCTAssertEqual(store.state.partnerID, partnerID, "파트너가 바뀌었다")
        XCTAssertEqual(store.state.dex, [1, 4, 7])
        XCTAssertEqual(store.state.researchPoints, 42)
        XCTAssertEqual(store.state.box.count, 3)
    }
}
