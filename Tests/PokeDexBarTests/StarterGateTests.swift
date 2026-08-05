import XCTest
@testable import PokeDexBar

@MainActor
final class StarterGateTests: XCTestCase {
    private func makeStore() -> PlayerStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("gate-\(UUID().uuidString).json")
        return PlayerStore(fileURL: url, rng: SeededRNG(seed: 1),
                           now: { Date(timeIntervalSince1970: 1_700_000_000) })
    }

    /// 관문 판정은 순수 함수여야 테스트할 수 있다 — 뷰 안에 숨기지 않는다.
    func testGateClosedUntilStarterChosen() {
        let store = makeStore()
        XCTAssertTrue(PopoverView.needsStarter(store.state))
        store.chooseStarter(speciesID: 1, grade: .epic)
        XCTAssertFalse(PopoverView.needsStarter(store.state))
    }

    /// 메뉴바·플로팅 펫이 그릴 종 — 파트너가 없으면 nil(스프라이트 대신 기본 아이콘).
    func testDisplayedSpeciesFollowsPartner() {
        let store = makeStore()
        XCTAssertNil(store.displayedSpeciesID)
        store.chooseStarter(speciesID: 7, grade: .epic)
        XCTAssertEqual(store.displayedSpeciesID, 7)
    }
}
