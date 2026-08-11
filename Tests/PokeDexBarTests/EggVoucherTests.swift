import XCTest
@testable import PokeDexBar

/// 확정 알 교환권 — 더 진화할 곳이 없는 개체가 경험치를 모아 자기 라인의 알을 부른다.
@MainActor
final class EggVoucherTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeStore(seed: UInt64 = 1) -> PlayerStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voucher-\(UUID().uuidString).json")
        return PlayerStore(fileURL: url, rng: SeededRNG(seed: seed), now: { self.now })
    }

    // MARK: 임계

    /// **진화 임계와 같은 환율이다.** 최종진화체에 갇힌 경험치가 새 환율이 아니라
    /// 진화와 같은 값으로 다시 흐르게 하는 것이 이 기능의 요점이라, 등급 기본값을 그대로 쓴다.
    func testThresholdMatchesTheFirstEvolutionStep() {
        for grade in Grade.allCases {
            XCTAssertEqual(EggVoucher.threshold(grade: grade),
                           ExpBalance.threshold(grade: grade, stageIndex: 0),
                           "\(grade) 의 교환권 임계가 진화 기본값과 다르다")
        }
    }

    /// 표에 적힌 절대값 — 위 테스트는 두 식이 같이 틀려도 통과하므로 값 자체를 따로 못박는다.
    func testThresholdValues() {
        XCTAssertEqual(EggVoucher.threshold(grade: .common), 50_000_000)
        XCTAssertEqual(EggVoucher.threshold(grade: .rare), 100_000_000)
        XCTAssertEqual(EggVoucher.threshold(grade: .epic), 200_000_000)
        XCTAssertEqual(EggVoucher.threshold(grade: .legendary), 400_000_000)
    }

    // MARK: 저장

    /// **앱을 껐다 켜도 교환권이 남는다.** 관대 디코더에 줄을 안 더하면 저장은 되고 읽기만
    /// 빠져서 재기동마다 교환권이 사라진다 — 이 저장소가 세 번 밟은 부류다.
    func testVouchersSurviveARestart() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voucher-save-\(UUID().uuidString).json")
        let store = PlayerStore(fileURL: url, rng: SeededRNG(seed: 1), now: { self.now })
        store.mutate { $0.eggVouchers = [EggVoucher(baseID: 4, grade: .epic),
                                         EggVoucher(baseID: 4, grade: .epic)] }

        let reloaded = PlayerStore(fileURL: url, rng: SeededRNG(seed: 1), now: { self.now })
        XCTAssertEqual(reloaded.state.eggVouchers,
                       [EggVoucher(baseID: 4, grade: .epic), EggVoucher(baseID: 4, grade: .epic)],
                       "다시 켜니 교환권이 사라졌다")
    }

    /// 말이 안 되는 종 번호는 경계에서 버린다 — 관대 디코딩의 짝.
    /// **개수는 안 자른다**(도감·인벤토리와 같은 이유로, 항목을 자르면 데이터 손실이다).
    func testBogusVouchersAreDroppedButValidOnesSurvive() throws {
        let json = """
        {"eggVouchers":[{"baseID":0,"grade":"epic"},{"baseID":4,"grade":"epic"}]}
        """
        let state = try JSONDecoder().decode(PlayerState.self, from: Data(json.utf8))
        XCTAssertEqual(state.eggVouchers, [EggVoucher(baseID: 4, grade: .epic)])
    }

    /// 한 장이 깨져도 나머지는 살아남는다 — 박스·알과 같은 원소 단위 관대 디코딩.
    func testOneMalformedVoucherDoesNotDropTheRest() throws {
        let json = """
        {"eggVouchers":[{"baseID":4},{"baseID":25,"grade":"common"}]}
        """
        let state = try JSONDecoder().decode(PlayerState.self, from: Data(json.utf8))
        XCTAssertEqual(state.eggVouchers, [EggVoucher(baseID: 25, grade: .common)],
                       "깨진 한 장 때문에 전부 날아갔다")
    }

    // MARK: 슬롯 배치와 값 치르기의 분리

    /// 지갑을 채운다 — `update` 의 기준선을 잡고 그 위로 사용량을 올린다.
    private func giveWallet(_ store: PlayerStore, _ tokens: Int) {
        store.update(todayTokens: 0, todayDate: "d", hasUsageData: true)
        store.update(todayTokens: tokens, todayDate: "d", hasUsageData: true)
    }

    /// **`placeEgg` 는 값을 안 치른다.** 교환권 경로가 이걸 부른다 — `startEgg` 을 그대로
    /// 부르면 교환권을 쓰고 토큰까지 내게 된다.
    func testPlaceEggCostsNothing() {
        let store = makeStore()
        let before = store.state.spentTokens
        XCTAssertNotNil(store.placeEgg(grade: .common, speciesID: 4, shiny: false))
        XCTAssertEqual(store.state.spentTokens, before, "교환권 알에 토큰이 나갔다")
        XCTAssertEqual(store.state.eggs.count, 1)
    }

    /// **대조군 — `startEgg` 은 여전히 값을 치른다.** 떼어내다 상점 뽑기가 공짜가 되는 것이
    /// 이 변경에서 가장 그럴듯한 사고다.
    func testStartEggStillCharges() {
        let store = makeStore()
        giveWallet(store, EggBalance.drawPrice * 2)
        let before = store.state.spentTokens
        XCTAssertNotNil(store.startEgg(grade: .common, speciesID: 4, shiny: false))
        XCTAssertEqual(store.state.spentTokens, before + EggBalance.drawPrice,
                       "상점 뽑기가 공짜가 됐다")
    }

    /// 지갑이 비어도 `placeEgg` 는 된다 — 교환권이 값이기 때문이다.
    func testPlaceEggWorksWithAnEmptyWallet() {
        let store = makeStore()
        XCTAssertEqual(store.state.wallet, 0)
        XCTAssertNotNil(store.placeEgg(grade: .common, speciesID: 4, shiny: false))
    }

    /// 빈 슬롯이 없으면 둘 다 못 넣는다.
    func testPlaceEggNeedsAFreeSlot() {
        let store = makeStore()
        for _ in 0..<store.state.slots {
            XCTAssertNotNil(store.placeEgg(grade: .common, speciesID: 4, shiny: false))
        }
        XCTAssertNil(store.placeEgg(grade: .common, speciesID: 4, shiny: false))
    }

    /// **교환권 알도 부화 감면을 받는다.** 감면 계산이 `startEgg` 안에 있으므로, 떼어내면서
    /// 값 치르는 쪽에 남겨두기 쉬운 자리다.
    func testPlaceEggGetsTheHatchSpeedup() throws {
        let store = makeStore()
        // 마그마그(불꽃몸 계열)를 박스에 넣으면 감면이 걸린다.
        store.addForTesting(Individual(baseID: 218, speciesID: 218, pathIDs: [218],
                                       nature: .hardy, obtainedAt: now, grade: .common))
        let egg = try XCTUnwrap(store.placeEgg(grade: .common, speciesID: 4, shiny: false))
        XCTAssertEqual(egg.hatchesAt.timeIntervalSince(now),
                       EggBalance.duration(.common) * HatchSpeedup.multiplier,
                       accuracy: 1, "교환권 알이 감면을 못 받았다")
    }
}
