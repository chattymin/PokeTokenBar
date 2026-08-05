import XCTest
@testable import PokeDexBar

@MainActor
final class EggDrawTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeStore(wallet: Int, slots: Int = 3, eggs: Int = 0) -> PlayerStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("draw-\(UUID().uuidString).json")
        let store = PlayerStore(fileURL: url, rng: SeededRNG(seed: 7), now: { self.now })
        store.seedForTesting(wallet: wallet, slots: slots, eggs: eggs, at: now)
        return store
    }

    func testDrawSpendsWalletAndFillsASlot() {
        let store = makeStore(wallet: EggBalance.drawPrice)
        let egg = store.startEgg(grade: .rare, speciesID: 152, shiny: false)
        XCTAssertNotNil(egg)
        XCTAssertEqual(store.state.eggs.count, 1)
        XCTAssertEqual(store.state.wallet, 0)
        XCTAssertEqual(store.state.eggs.first?.speciesID, 152)
    }

    /// 부화 시각은 뽑은 시점 + 등급별 소요시간이다.
    func testHatchTimeComesFromGrade() {
        let store = makeStore(wallet: EggBalance.drawPrice)
        store.startEgg(grade: .epic, speciesID: 4, shiny: false)
        let egg = store.state.eggs.first!
        XCTAssertEqual(egg.startedAt, now)
        XCTAssertEqual(egg.hatchesAt.timeIntervalSince(now),
                       EggBalance.duration(.epic), accuracy: 1)
    }

    /// 재화가 모자라면 아무 일도 없다 — 지갑도 슬롯도 그대로다.
    func testCannotDrawWithoutFunds() {
        let store = makeStore(wallet: EggBalance.drawPrice - 1)
        XCTAssertFalse(store.canDraw)
        XCTAssertNil(store.startEgg(grade: .common, speciesID: 1, shiny: false))
        XCTAssertTrue(store.state.eggs.isEmpty)
        XCTAssertEqual(store.state.wallet, EggBalance.drawPrice - 1)
    }

    /// 슬롯이 꽉 차면 못 뽑는다 — 미부화 알 보관함은 없다.
    func testCannotDrawWithoutAFreeSlot() {
        let store = makeStore(wallet: 10_000_000_000, slots: 3, eggs: 3)
        XCTAssertEqual(store.freeSlots, 0)
        XCTAssertFalse(store.canDraw)
        XCTAssertNil(store.startEgg(grade: .common, speciesID: 1, shiny: false))
        XCTAssertEqual(store.state.eggs.count, 3)
        XCTAssertEqual(store.state.wallet, 10_000_000_000, "실패한 뽑기는 재화를 쓰지 않는다")
    }

    func testFreeSlotsCountsRemaining() {
        XCTAssertEqual(makeStore(wallet: 0, slots: 3, eggs: 1).freeSlots, 2)
        XCTAssertEqual(makeStore(wallet: 0, slots: 6, eggs: 6).freeSlots, 0)
    }

    /// 굴림은 주입한 난수를 쓴다 — 같은 시드면 같은 결과가 나와야 재현이 된다.
    func testRollIsDeterministicUnderSeed() {
        let a = makeStore(wallet: 0)
        let b = makeStore(wallet: 0)
        let first = a.rollGradeAndShiny()
        let second = b.rollGradeAndShiny()
        XCTAssertEqual(first.grade, second.grade)
        XCTAssertEqual(first.shiny, second.shiny)
    }

    func testDrawPersistsAcrossReload() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("draw-\(UUID().uuidString).json")
        let store = PlayerStore(fileURL: url, rng: SeededRNG(seed: 7), now: { self.now })
        store.seedForTesting(wallet: EggBalance.drawPrice, slots: 3, eggs: 0, at: now)
        store.startEgg(grade: .legendary, speciesID: 144, shiny: true)
        let reloaded = PlayerStore(fileURL: url, rng: SeededRNG(seed: 7), now: { self.now })
        XCTAssertEqual(reloaded.state.eggs.count, 1)
        XCTAssertEqual(reloaded.state.eggs.first?.speciesID, 144)
        XCTAssertTrue(reloaded.state.eggs.first?.shiny ?? false)
    }
}
