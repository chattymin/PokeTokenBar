import XCTest
@testable import PokeDexBar

@MainActor
final class EconomyLoopTests: XCTestCase {
    /// 뽑기 → 부화 → 도감 등록 → 슬롯 반환이 한 바퀴 도는지, 하루를 압축해 확인한다.
    func testFullLoopOverOneDay() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("loop-\(UUID().uuidString).json")
        let store = PlayerStore(fileURL: url, rng: SeededRNG(seed: 11), now: { start })
        store.seedForTesting(wallet: EggBalance.drawPrice * 3, slots: 3, eggs: 0, at: start)

        // 뽑기 결과를 바인딩해 non-nil 을 확인한다 — nil 인 채로 넘어가면 아래 단언들이
        // "0개를 부화시켜 0개를 확인"하는 식으로 통과해 버리는 무의미한 테스트가 된다.
        let common = store.startEgg(grade: .common, speciesID: 1, shiny: false)
        let rare = store.startEgg(grade: .rare, speciesID: 4, shiny: false)
        let legendary = store.startEgg(grade: .legendary, speciesID: 144, shiny: true)
        XCTAssertNotNil(common, "슬롯·재화가 충분하니 뽑기가 성사돼야 한다")
        XCTAssertNotNil(rare, "슬롯·재화가 충분하니 뽑기가 성사돼야 한다")
        XCTAssertNotNil(legendary, "슬롯·재화가 충분하니 뽑기가 성사돼야 한다")
        XCTAssertEqual(store.freeSlots, 0)
        XCTAssertFalse(store.canDraw, "슬롯이 꽉 차면 못 뽑는다")

        let hatched = store.settleHatches(at: start.addingTimeInterval(24 * 3600))
        XCTAssertEqual(hatched.count, 3)
        XCTAssertEqual(store.freeSlots, 3, "부화하면 슬롯이 돌아온다")
        XCTAssertEqual(store.state.dex, Set([1, 4, 144]))
        XCTAssertTrue(store.state.box.first { $0.speciesID == 144 }?.shiny ?? false)
    }
}
