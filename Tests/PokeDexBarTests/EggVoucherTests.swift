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
}
