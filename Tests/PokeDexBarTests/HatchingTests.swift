import XCTest
@testable import PokeDexBar

/// 부화는 두 단계다: 시간이 차면 **알린다**(자동), 사용자가 확인을 누르면 **거둔다**(수동).
/// 익은 알이 저절로 박스로 사라지면 무엇이 나왔는지 못 보고 지나간다 — 그래서 슬롯에 남는다.
@MainActor
final class HatchingTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeStore(slots: Int = 6) -> PlayerStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("hatch-\(UUID().uuidString).json")
        let store = PlayerStore(fileURL: url, rng: SeededRNG(seed: 3), now: { self.now },
                                defaults: UserDefaults(suiteName: "hatch-\(UUID().uuidString)")!)
        store.seedForTesting(wallet: 100_000_000_000, slots: slots, eggs: 0, at: now)
        return store
    }

    private func addEgg(_ store: PlayerStore, grade: Grade, species: Int, shiny: Bool = false) {
        store.startEgg(grade: grade, speciesID: species, shiny: shiny)
    }

    private func ripe(_ grade: Grade) -> Date { now.addingTimeInterval(EggBalance.duration(grade)) }

    // MARK: 익어도 스스로 사라지지 않는다

    /// 이 브랜치의 핵심 변경 — 시간이 차도 알은 슬롯에 남고 박스는 그대로다.
    func testRipeEggStaysInItsSlotUntilClaimed() {
        let store = makeStore()
        addEgg(store, grade: .common, species: 1)
        store.announceReadyEggs(at: ripe(.common))
        XCTAssertEqual(store.state.eggs.count, 1, "확인 전에 알이 사라졌다")
        XCTAssertTrue(store.state.box.isEmpty, "확인 전에 박스로 들어갔다")
        XCTAssertEqual(store.freeSlots, 5, "확인 전에 슬롯이 비었다")
    }

    func testClaimingMovesItToTheBoxAndFreesTheSlot() {
        let store = makeStore()
        addEgg(store, grade: .common, species: 1)
        let egg = store.state.eggs.first!
        let individual = store.claimHatch(eggID: egg.id, at: ripe(.common))
        XCTAssertEqual(individual?.speciesID, 1)
        XCTAssertTrue(store.state.eggs.isEmpty, "거둔 알이 슬롯에 남았다")
        XCTAssertEqual(store.state.box.count, 1)
        XCTAssertTrue(store.state.dex.contains(1))
        XCTAssertEqual(store.freeSlots, 6)
    }

    /// 아직 안 익은 알은 못 거둔다 — 확인 버튼은 익었을 때만 뜨지만, 실행 경로도 막아야 한다.
    func testClaimingBeforeItIsReadyDoesNothing() {
        let store = makeStore()
        addEgg(store, grade: .legendary, species: 144)
        let egg = store.state.eggs.first!
        XCTAssertNil(store.claimHatch(eggID: egg.id, at: now.addingTimeInterval(3600)))
        XCTAssertEqual(store.state.eggs.count, 1)
        XCTAssertTrue(store.state.box.isEmpty)
    }

    func testClaimingAnUnknownEggDoesNothing() {
        let store = makeStore()
        XCTAssertNil(store.claimHatch(eggID: UUID(), at: now))
    }

    /// 두 번 거둘 수 없다 — 첫 번째에 알이 사라지므로 두 번째는 대상이 없다.
    func testClaimingTwiceYieldsOneIndividual() {
        let store = makeStore()
        addEgg(store, grade: .common, species: 7)
        let egg = store.state.eggs.first!
        XCTAssertNotNil(store.claimHatch(eggID: egg.id, at: ripe(.common)))
        XCTAssertNil(store.claimHatch(eggID: egg.id, at: ripe(.common)))
        XCTAssertEqual(store.state.box.count, 1)
    }

    func testClaimAllTakesEveryRipeEggAndLeavesTheRest() {
        let store = makeStore()
        addEgg(store, grade: .common, species: 1)
        addEgg(store, grade: .rare, species: 4)
        addEgg(store, grade: .legendary, species: 144)
        let claimed = store.claimAllReady(at: now.addingTimeInterval(3 * 3600))
        XCTAssertEqual(Set(claimed.map(\.speciesID)), [1, 4], "레전더리는 24시간이라 아직이다")
        XCTAssertEqual(store.state.eggs.count, 1)
        XCTAssertEqual(store.state.eggs.first?.speciesID, 144)
    }

    // MARK: 알림은 한 번만

    /// 익은 알이 슬롯에 계속 남으므로, 알린 표시가 없으면 매 틱마다 같은 알을 다시 알린다.
    func testAnnouncingIsOnlyOncePerEgg() {
        let store = makeStore()
        addEgg(store, grade: .common, species: 1)
        XCTAssertEqual(store.announceReadyEggs(at: ripe(.common)).count, 1)
        XCTAssertEqual(store.announceReadyEggs(at: ripe(.common)).count, 0, "같은 알을 다시 알렸다")
        XCTAssertEqual(store.announceReadyEggs(at: ripe(.common).addingTimeInterval(9999)).count, 0)
    }

    func testNothingIsAnnouncedBeforeItIsReady() {
        let store = makeStore()
        addEgg(store, grade: .common, species: 1)
        XCTAssertTrue(store.announceReadyEggs(at: now).isEmpty)
    }

    /// 알린 표시가 저장돼야 앱을 껐다 켜도 다시 안 알린다.
    func testAnnouncedFlagPersists() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("hatch-\(UUID().uuidString).json")
        let defaults = UserDefaults(suiteName: "hatch-\(UUID().uuidString)")!
        let store = PlayerStore(fileURL: url, rng: SeededRNG(seed: 3), now: { self.now },
                                defaults: defaults)
        store.seedForTesting(wallet: 100_000_000_000, slots: 3, eggs: 0, at: now)
        store.startEgg(grade: .common, speciesID: 25, shiny: false)
        store.announceReadyEggs(at: ripe(.common))

        let reloaded = PlayerStore(fileURL: url, rng: SeededRNG(seed: 3),
                                   now: { self.ripe(.common) }, defaults: defaults)
        XCTAssertEqual(reloaded.state.eggs.count, 1, "알이 재기동으로 사라졌다")
        XCTAssertTrue(reloaded.announceReadyEggs(at: ripe(.common)).isEmpty,
                      "재기동하니 같은 알을 다시 알린다")
    }

    // MARK: 거둔 개체

    func testHatchedIndividualInheritsEggProperties() {
        let store = makeStore()
        addEgg(store, grade: .epic, species: 133, shiny: true)
        let egg = store.state.eggs.first!
        let individual = store.claimHatch(eggID: egg.id, at: ripe(.epic))!
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
        XCTAssertEqual(store.claimAllReady(at: ripe(.common)).count, 2)
        XCTAssertEqual(store.state.box.count, 2)
        XCTAssertNotEqual(store.state.box[0].id, store.state.box[1].id)
        XCTAssertEqual(store.state.dex.count, 1, "도감은 종 단위라 하나만 는다")
    }

    func testReadyEggCount() {
        let store = makeStore()
        addEgg(store, grade: .common, species: 1)
        addEgg(store, grade: .legendary, species: 144)
        XCTAssertEqual(store.readyEggCount(at: now.addingTimeInterval(3600)), 1)
    }

    /// 거둔 결과가 파일에 남아야 앱을 껐다 켜도 유지된다.
    func testClaimPersists() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("hatch-\(UUID().uuidString).json")
        let defaults = UserDefaults(suiteName: "hatch-\(UUID().uuidString)")!
        let store = PlayerStore(fileURL: url, rng: SeededRNG(seed: 3), now: { self.now },
                                defaults: defaults)
        store.seedForTesting(wallet: 100_000_000_000, slots: 3, eggs: 0, at: now)
        store.startEgg(grade: .common, speciesID: 25, shiny: false)
        store.claimAllReady(at: ripe(.common))
        let reloaded = PlayerStore(fileURL: url, rng: SeededRNG(seed: 3), now: { self.now },
                                   defaults: defaults)
        XCTAssertEqual(reloaded.state.box.count, 1)
        XCTAssertTrue(reloaded.state.eggs.isEmpty)
    }
}

/// [회귀] `Egg` 에 필드를 더하면 기존 세이브의 **모든 알이 조용히 사라진다** — `Individual` 에서
/// 실제로 박스가 비었던 그 부류다(`LossyEgg` 가 디코드 예외를 "이 알을 버린다"로 바꾼다).
final class EggForwardCompatibilityTests: XCTestCase {
    /// 새 필드가 없는 옛 알 JSON. 새 필드를 더할 때 **이 문자열은 고치지 마라.**
    private let legacy = """
    {"id":"22222222-2222-2222-2222-222222222222","grade":"rare","speciesID":4,"shiny":true,
    "startedAt":0,"hatchesAt":7200}
    """

    func testLegacyEggStillDecodes() throws {
        let egg = try JSONDecoder().decode(Egg.self, from: Data(legacy.utf8))
        XCTAssertEqual(egg.speciesID, 4)
        XCTAssertTrue(egg.shiny)
        XCTAssertFalse(egg.announced, "없던 필드는 기본값으로 들어와야 한다")
    }

    func testLegacyEggSurvivesTheStateDecode() throws {
        let json = """
        {"box":[],"dex":[],"earnedTokens":0,"spentTokens":0,"claimedTodayTokens":0,
        "lastDate":"2026-01-01","installBaselineSet":true,"slots":3,"eggs":[\(legacy)],
        "inventory":{},"ownsShinyCharm":false,"starterChosen":true,"language":"ko"}
        """
        let state = try JSONDecoder().decode(PlayerState.self, from: Data(json.utf8))
        XCTAssertEqual(state.eggs.count, 1, "필드를 더하면서 기존 알을 날렸다")
    }

    /// 정체를 알 수 없는 알은 그대로 버린다 — 관대함이 "아무거나 통과"가 되면 안 된다.
    func testEggWithoutIdentityIsRejected() {
        XCTAssertThrowsError(try JSONDecoder().decode(Egg.self, from: Data(#"{"shiny":true}"#.utf8)))
    }
}
