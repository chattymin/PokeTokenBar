import XCTest
@testable import PokeDexBar

@MainActor
final class HatchingTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeStore() -> PlayerStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("hatch-\(UUID().uuidString).json")
        let store = PlayerStore(fileURL: url, rng: SeededRNG(seed: 3), now: { self.now })
        store.seedForTesting(wallet: 100_000_000_000, slots: 6, eggs: 0, at: now)
        return store
    }

    private func addEgg(_ store: PlayerStore, grade: Grade, species: Int, shiny: Bool = false) {
        store.startEgg(grade: grade, speciesID: species, shiny: shiny)
    }

    func testEggHatchesAfterItsDuration() {
        let store = makeStore()
        addEgg(store, grade: .common, species: 1)
        XCTAssertTrue(store.settleHatches(at: now).isEmpty, "아직 시간이 안 됐다")
        let hatched = store.settleHatches(at: now.addingTimeInterval(EggBalance.duration(.common)))
        XCTAssertEqual(hatched.count, 1)
        XCTAssertEqual(hatched.first?.speciesID, 1)
        XCTAssertTrue(store.state.eggs.isEmpty, "부화한 알은 슬롯을 비운다")
        XCTAssertEqual(store.state.box.count, 1)
        XCTAssertTrue(store.state.dex.contains(1))
    }

    /// 앱이 꺼져 있는 동안 여러 개가 동시에 익어도 한 번에 정산한다.
    func testAllRipeEggsHatchAtOnce() {
        let store = makeStore()
        addEgg(store, grade: .common, species: 1)
        addEgg(store, grade: .rare, species: 4)
        addEgg(store, grade: .legendary, species: 144)
        let hatched = store.settleHatches(at: now.addingTimeInterval(3 * 3600))
        XCTAssertEqual(Set(hatched.map(\.speciesID)), [1, 4], "레전더리는 24시간이라 아직이다")
        XCTAssertEqual(store.state.eggs.count, 1)
        XCTAssertEqual(store.state.eggs.first?.speciesID, 144)
    }

    /// 부화한 개체는 알이 들고 있던 등급·이로치를 그대로 이어받는다.
    func testHatchedIndividualInheritsEggProperties() {
        let store = makeStore()
        addEgg(store, grade: .epic, species: 133, shiny: true)
        let hatched = store.settleHatches(at: now.addingTimeInterval(EggBalance.duration(.epic)))
        let individual = hatched.first!
        XCTAssertEqual(individual.grade, .epic)
        XCTAssertTrue(individual.shiny)
        XCTAssertEqual(individual.baseID, 133)
        XCTAssertEqual(individual.pathIDs, [133])
        XCTAssertEqual(individual.exp, 0)
    }

    /// 같은 종이 또 나와도 새 개체로 들어간다 — 중복이 정상이다.
    func testDuplicatesBecomeSeparateIndividuals() {
        let store = makeStore()
        addEgg(store, grade: .common, species: 1)
        addEgg(store, grade: .common, species: 1)
        let hatched = store.settleHatches(at: now.addingTimeInterval(EggBalance.duration(.common)))
        XCTAssertEqual(hatched.count, 2)
        XCTAssertEqual(store.state.box.count, 2)
        XCTAssertNotEqual(store.state.box[0].id, store.state.box[1].id)
        XCTAssertEqual(store.state.dex.count, 1, "도감은 종 단위라 하나만 는다")
    }

    /// 정산은 여러 번 불러도 같은 알을 두 번 부화시키지 않는다.
    func testSettlingTwiceIsIdempotent() {
        let store = makeStore()
        addEgg(store, grade: .common, species: 7)
        let later = now.addingTimeInterval(EggBalance.duration(.common))
        XCTAssertEqual(store.settleHatches(at: later).count, 1)
        XCTAssertEqual(store.settleHatches(at: later).count, 0)
        XCTAssertEqual(store.state.box.count, 1)
    }

    func testReadyEggCount() {
        let store = makeStore()
        addEgg(store, grade: .common, species: 1)
        addEgg(store, grade: .legendary, species: 144)
        XCTAssertEqual(store.readyEggCount(at: now.addingTimeInterval(3600)), 1)
    }

    /// 부화 결과가 파일에 남아야 앱을 껐다 켜도 유지된다.
    func testHatchPersists() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("hatch-\(UUID().uuidString).json")
        let store = PlayerStore(fileURL: url, rng: SeededRNG(seed: 3), now: { self.now })
        store.seedForTesting(wallet: 100_000_000_000, slots: 3, eggs: 0, at: now)
        store.startEgg(grade: .common, speciesID: 25, shiny: false)
        store.settleHatches(at: now.addingTimeInterval(EggBalance.duration(.common)))
        let reloaded = PlayerStore(fileURL: url, rng: SeededRNG(seed: 3), now: { self.now })
        XCTAssertEqual(reloaded.state.box.count, 1)
        XCTAssertTrue(reloaded.state.eggs.isEmpty)
    }
}
