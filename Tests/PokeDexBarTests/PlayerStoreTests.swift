import XCTest
@testable import PokeDexBar

@MainActor
final class PlayerStoreTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeStore(seed: UInt64 = 1) -> (PlayerStore, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("player-\(UUID().uuidString).json")
        return (PlayerStore(fileURL: url, rng: SeededRNG(seed: seed), now: { self.now }), url)
    }

    // MARK: 스타터

    func testChoosingAStarterFillsBoxPartnerAndDex() {
        let (store, _) = makeStore()
        let picked = store.chooseStarter(speciesID: 4, grade: .epic)
        XCTAssertNotNil(picked)
        XCTAssertTrue(store.state.starterChosen)
        XCTAssertEqual(store.state.box.count, 1)
        XCTAssertEqual(store.state.partner?.speciesID, 4)
        XCTAssertEqual(store.state.partner?.pathIDs, [4])
        XCTAssertTrue(store.state.dex.contains(4))
    }

    /// 스타터는 이로치가 아니다 — 첫 개체는 복구할 수 없으니 운에 맡기지 않는다.
    func testStarterIsNeverShiny() {
        for seed in UInt64(1)...20 {
            let (store, _) = makeStore(seed: seed)
            store.chooseStarter(speciesID: 1, grade: .epic)
            XCTAssertFalse(store.state.partner?.shiny ?? true)
        }
    }

    /// 스타터 목록 밖의 종은 고를 수 없다.
    func testRejectsNonStarter() {
        let (store, _) = makeStore()
        XCTAssertNil(store.chooseStarter(speciesID: 25, grade: .common))
        XCTAssertFalse(store.state.starterChosen)
        XCTAssertTrue(store.state.box.isEmpty)
    }

    /// 두 번 고를 수 없다 — 이미 골랐으면 무시한다.
    func testCannotChooseTwice() {
        let (store, _) = makeStore()
        store.chooseStarter(speciesID: 1, grade: .epic)
        XCTAssertNil(store.chooseStarter(speciesID: 4, grade: .epic))
        XCTAssertEqual(store.state.box.count, 1)
        XCTAssertEqual(store.state.partner?.speciesID, 1)
    }

    // MARK: 지갑·경험치 적립

    /// 설치 기준선 — 데이터가 도착한 시점의 오늘 사용량은 적립하지 않는다(설치 이전 사용분 제외).
    func testFirstUpdateSetsBaselineWithoutEarning() {
        let (store, _) = makeStore()
        store.update(todayTokens: 5_000, todayDate: "2026-08-05", hasUsageData: true)
        XCTAssertTrue(store.state.installBaselineSet)
        XCTAssertEqual(store.state.earnedTokens, 0)
        XCTAssertEqual(store.state.claimedTodayTokens, 5_000)
    }

    /// 데이터가 도착하기 전에는 기준선을 잡지 않는다 — 기동 직후 빈 새로고침에 0을 못박으면
    /// 그날 사용분이 통째로 적립된다.
    func testBaselineWaitsForRealData() {
        let (store, _) = makeStore()
        store.update(todayTokens: 0, todayDate: "2026-08-05", hasUsageData: false)
        XCTAssertFalse(store.state.installBaselineSet)
    }

    func testDeltaAccruesToWalletAndPartnerExp() {
        let (store, _) = makeStore()
        store.chooseStarter(speciesID: 1, grade: .common)
        // 델타를 환율의 배수로 잡는다 — 환율을 조정해도 이 테스트가 뜻을 유지한다.
        let delta = ExpBalance.tokensPerExp * 3
        store.update(todayTokens: 1_000, todayDate: "2026-08-05", hasUsageData: true)
        store.update(todayTokens: 1_000 + delta, todayDate: "2026-08-05", hasUsageData: true)
        XCTAssertEqual(store.state.earnedTokens, delta)
        XCTAssertEqual(store.state.wallet, delta)
        // 경험치만 환율을 거친다 — 지갑·장부는 토큰 그대로다.
        XCTAssertEqual(store.state.partner?.exp, 3)
    }

    /// 파트너만 경험치를 얻는다 — 박스의 다른 개체는 그대로다.
    func testOnlyPartnerEarnsExp() {
        let (store, _) = makeStore()
        store.chooseStarter(speciesID: 1, grade: .common)
        let other = Individual(baseID: 4, speciesID: 4, pathIDs: [4], nature: .serious,
                               obtainedAt: self.now, grade: .epic)
        store.addForTesting(other)
        store.update(todayTokens: 1_000, todayDate: "2026-08-05", hasUsageData: true)
        store.update(todayTokens: 1_000 + ExpBalance.tokensPerExp * 2,
                     todayDate: "2026-08-05", hasUsageData: true)
        // 경험치는 환율을 거친다: 환율 두 배어치를 썼으니 2EXP.
        XCTAssertEqual(store.state.partner?.exp, 2)
        XCTAssertEqual(store.state.box.first(where: { $0.id == other.id })?.exp, 0)
    }

    /// 날짜가 바뀌면 그날 장부만 0으로 — 누적 적립은 유지된다.
    func testDayRolloverKeepsEarnedTotal() {
        let (store, _) = makeStore()
        store.update(todayTokens: 1_000, todayDate: "2026-08-05", hasUsageData: true)
        store.update(todayTokens: 3_000, todayDate: "2026-08-05", hasUsageData: true)
        store.update(todayTokens: 500, todayDate: "2026-08-06", hasUsageData: true)
        XCTAssertEqual(store.state.earnedTokens, 2_500)
    }

    /// 새 날짜의 오늘 총량이 0이면(아직 그날 사용량이 안 잡혔거나 새로고침이 빈 값을 보고할 때)
    /// 델타 적립은 없지만 롤오버로 리셋된 lastDate·claimedTodayTokens 는 그래도 디스크에 남아야
    /// 한다 — 메모리에만 남으면 프로세스가 죽었을 때 그 리셋이 사라진다.
    func testDayRolloverWithZeroTotalPersists() {
        let (store, url) = makeStore()
        store.update(todayTokens: 1_000, todayDate: "2026-08-05", hasUsageData: true)
        store.update(todayTokens: 3_000, todayDate: "2026-08-05", hasUsageData: true)
        store.update(todayTokens: 0, todayDate: "2026-08-06", hasUsageData: true)
        let reloaded = PlayerStore(fileURL: url, rng: SeededRNG(seed: 1), now: { self.now })
        XCTAssertEqual(reloaded.state.lastDate, "2026-08-06")
        XCTAssertEqual(reloaded.state.claimedTodayTokens, 0)
    }

    // MARK: 도감·파트너·영속

    func testRegisterInDexIsIdempotent() {
        let (store, _) = makeStore()
        store.registerInDex(25)
        store.registerInDex(25)
        XCTAssertEqual(store.state.dex, [25])
    }

    func testSetPartnerOnlyAcceptsOwnedIndividuals() {
        let (store, _) = makeStore()
        store.chooseStarter(speciesID: 1, grade: .common)
        let first = store.state.partner!.id
        store.setPartner(UUID())
        XCTAssertEqual(store.state.partnerID, first, "박스에 없는 개체는 파트너가 될 수 없다")
    }

    func testStatePersistsAcrossReload() {
        let (store, url) = makeStore()
        store.chooseStarter(speciesID: 7, grade: .epic)
        store.update(todayTokens: 100, todayDate: "2026-08-05", hasUsageData: true)
        store.update(todayTokens: 900, todayDate: "2026-08-05", hasUsageData: true)
        let reloaded = PlayerStore(fileURL: url, rng: SeededRNG(seed: 1), now: { self.now })
        XCTAssertTrue(reloaded.state.starterChosen)
        XCTAssertEqual(reloaded.state.partner?.speciesID, 7)
        XCTAssertEqual(reloaded.state.earnedTokens, 800)
        XCTAssertTrue(reloaded.state.dex.contains(7))
    }
}
