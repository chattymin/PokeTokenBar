import XCTest
@testable import PokeDexBar

/// 골라서 한 번에 보내기.
@MainActor
final class BulkReleaseTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeStore() -> PlayerStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bulk-\(UUID().uuidString).json")
        return PlayerStore(fileURL: url, rng: SeededRNG(seed: 1), now: { self.now })
    }

    private func make(_ grade: Grade, path: [Int], shiny: Bool = false) -> Individual {
        Individual(baseID: path.first ?? 1, speciesID: path.last ?? 1, pathIDs: path,
                   shiny: shiny, nature: .hardy, obtainedAt: now, grade: grade)
    }

    // MARK: 확인 단계 — 배치는 그 안에서 가장 엄한 규칙을 따른다

    /// 평범한 아이들만 있으면 한 번만 묻는다.
    func testAnOrdinaryBatchAsksOnce() {
        let batch = [make(.common, path: [1]), make(.rare, path: [25])]
        XCTAssertEqual(BulkRelease.confirmSteps(for: batch), 1)
    }

    /// **이로치가 하나라도 섞이면 배치 전체가 한 번 더 묻는다.** 20마리 중 이로치 하나가
    /// 딸려 나가는 것이 이 기능의 유일한 진짜 사고다.
    func testOneShinyMakesTheWholeBatchAskTwice() {
        let batch = [make(.common, path: [1]), make(.common, path: [4], shiny: true),
                     make(.common, path: [7])]
        XCTAssertEqual(BulkRelease.confirmSteps(for: batch), 2)
    }

    /// 전설도 마찬가지.
    func testOneLegendaryMakesTheWholeBatchAskTwice() {
        XCTAssertEqual(BulkRelease.confirmSteps(for: [make(.common, path: [1]),
                                                      make(.legendary, path: [150])]), 2)
    }

    /// **단일 보내기와 같은 규칙을 쓴다.** 규칙을 두 군데 적으면 갈린다 — 한 마리짜리 배치는
    /// 그 한 마리의 단계와 반드시 같아야 한다.
    func testASingleItemBatchMatchesTheSingleSendRule() {
        for grade in Grade.allCases {
            for shiny in [true, false] {
                let one = make(grade, path: [1], shiny: shiny)
                XCTAssertEqual(BulkRelease.confirmSteps(for: [one]),
                               IndividualDetailView.releaseConfirmSteps(shiny: shiny, grade: grade),
                               "\(grade) shiny=\(shiny)")
            }
        }
    }

    /// 빈 배치는 1 — 확인 화면 자체가 안 뜨지만, 0 을 돌려주면 호출부가 단계 비교에서 헷갈린다.
    func testAnEmptyBatchIsOneStep() {
        XCTAssertEqual(BulkRelease.confirmSteps(for: []), 1)
    }

    /// 이름으로 불러 줄 아이들 — 이로치와 전설만. 20개를 다 나열하면 아무도 안 읽는다.
    func testRiskyPicksOnlyShiniesAndLegendaries() {
        let plain = make(.common, path: [1])
        let shiny = make(.rare, path: [4], shiny: true)
        let legendary = make(.legendary, path: [150])
        XCTAssertEqual(BulkRelease.risky([plain, shiny, legendary, plain]).map(\.id),
                       [shiny.id, legendary.id])
        XCTAssertTrue(BulkRelease.risky([plain]).isEmpty)
    }

    // MARK: 한 번에 보내기

    /// 여러 마리가 한 번에 나가고 포인트는 개별 합과 같다.
    func testSendingSeveralPaysTheSumOfTheirValues() {
        let store = makeStore()
        let keep = make(.common, path: [1])
        let a = make(.epic, path: [4, 5, 6]), b = make(.rare, path: [25])
        for individual in [keep, a, b] { store.addForTesting(individual) }
        store.setPartner(keep.id)

        let expected = store.releaseValue(a)! + store.releaseValue(b)!
        XCTAssertEqual(store.releaseManyToProfessor(individualIDs: [a.id, b.id]), expected)
        XCTAssertEqual(store.state.box.map(\.id), [keep.id])
        XCTAssertEqual(store.state.researchPoints, expected)
    }

    /// **파트너는 목록에 섞여 있어도 절대 안 나간다.** 화면이 못 고르게 돼 있지만 스토어가
    /// 마지막 방어선이다 — 파트너가 사라지면 시계·폼 상태가 통째로 없어진다.
    func testThePartnerIsNeverSentEvenIfListed() {
        let store = makeStore()
        let partner = make(.common, path: [1]), other = make(.common, path: [4])
        store.addForTesting(partner); store.addForTesting(other)
        store.setPartner(partner.id)

        let points = store.releaseManyToProfessor(individualIDs: [partner.id, other.id])
        XCTAssertEqual(points, store.releaseValue(other) ?? -1, "파트너 값이 합계에 섞였다")
        XCTAssertTrue(store.state.box.contains { $0.id == partner.id }, "파트너가 나갔다")
        XCTAssertFalse(store.state.box.contains { $0.id == other.id })
    }

    /// 없는 id 가 섞여 있어도 나머지는 나간다.
    func testUnknownIDsAreSkipped() {
        let store = makeStore()
        let keep = make(.common, path: [1]), send = make(.rare, path: [25])
        store.addForTesting(keep); store.addForTesting(send)
        store.setPartner(keep.id)

        XCTAssertEqual(store.releaseManyToProfessor(individualIDs: [UUID(), send.id]),
                       store.releaseValue(send) ?? -1)
        XCTAssertEqual(store.state.box.map(\.id), [keep.id])
    }

    /// 빈 목록은 아무 일도 안 일으킨다.
    func testAnEmptyListDoesNothing() {
        let store = makeStore()
        let keep = make(.common, path: [1])
        store.addForTesting(keep)
        XCTAssertEqual(store.releaseManyToProfessor(individualIDs: []), 0)
        XCTAssertEqual(store.state.box.count, 1)
        XCTAssertEqual(store.state.researchPoints, 0)
    }

    /// 같은 id 가 두 번 들어와도 한 번만 나간다 — 값이 두 배로 잡히면 포인트가 공짜로 는다.
    func testADuplicateIDIsOnlyCountedOnce() {
        let store = makeStore()
        let keep = make(.common, path: [1]), send = make(.rare, path: [25])
        store.addForTesting(keep); store.addForTesting(send)
        store.setPartner(keep.id)

        XCTAssertEqual(store.releaseManyToProfessor(individualIDs: [send.id, send.id]),
                       store.releaseValue(send) ?? -1)
        XCTAssertEqual(store.state.box.map(\.id), [keep.id])
    }

    /// **부화 감면도 한 번에 정리된다.** 유일한 불꽃몸이 배치에 섞여 있으면 보낸 뒤 감면이 끝난다 —
    /// 단일 보내기와 같은 규칙이고, 감면 판정이 박스를 보므로 저절로 따라온다.
    func testSendingTheOnlyWarmPokemonInABatchEndsTheDiscount() {
        let store = makeStore()
        let keep = make(.common, path: [1])
        let slugma = make(.common, path: [218]), other = make(.common, path: [4])
        for individual in [keep, slugma, other] { store.addForTesting(individual) }
        store.setPartner(keep.id)
        XCTAssertTrue(HatchSpeedup.present(in: store.state.box))

        store.releaseManyToProfessor(individualIDs: [slugma.id, other.id])
        XCTAssertFalse(HatchSpeedup.present(in: store.state.box), "보냈는데 감면이 남았다")
    }

    // MARK: 선택 모드

    /// 고를 수 있는 아이인가 — **판정은 `releaseValue` 하나**다. 화면이 조건을 따로 적으면
    /// 스토어와 갈린다(이 기능에서 실제로 한 번 났다).
    func testOnlySendableIndividualsArePickable() {
        let store = makeStore()
        let partner = make(.common, path: [1]), other = make(.common, path: [4])
        store.addForTesting(partner); store.addForTesting(other)
        store.setPartner(partner.id)

        XCTAssertFalse(BoxTabView.isPickable(partner, store: store), "파트너를 고를 수 있다")
        XCTAssertTrue(BoxTabView.isPickable(other, store: store))
    }

    /// 고른 아이들의 합계 — 바에 적히는 값이다.
    func testPickedTotalIsTheSumOfTheirValues() {
        let store = makeStore()
        let keep = make(.common, path: [1])
        let a = make(.epic, path: [4, 5, 6]), b = make(.rare, path: [25])
        for individual in [keep, a, b] { store.addForTesting(individual) }
        store.setPartner(keep.id)

        XCTAssertEqual(BoxTabView.pickedTotal([a, b], store: store),
                       store.releaseValue(a)! + store.releaseValue(b)!)
        XCTAssertEqual(BoxTabView.pickedTotal([], store: store), 0)
    }

    /// 화면이 실제로 일괄 경로에 닿아 있다 — 안 닿으면 고를 수는 있는데 보낼 수가 없다.
    func testTheBoxReachesTheBulkPath() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent(
            "Sources/PokeDexBar/UI/BoxTabView.swift"), encoding: .utf8)
        XCTAssertTrue(text.contains("releaseManyToProfessor"), "박스에 일괄 보내기가 없다")
        XCTAssertTrue(text.contains("BulkRelease.confirmSteps"), "확인 단계 규칙을 안 쓴다")
        XCTAssertFalse(text.contains(".help("), "안 뜨는 툴팁이 들어왔다")
    }

    /// 문구가 세 언어를 다 채운다.
    func testBulkStringsCoverAllThreeLanguages() {
        for lang in AppLanguage.allCases {
            let l = L(lang)
            XCTAssertFalse(l.bulkSelect.isEmpty, "\(lang)")
            XCTAssertFalse(l.bulkDone.isEmpty, "\(lang)")
            XCTAssertFalse(l.bulkPicked(3, 18).isEmpty, "\(lang)")
            XCTAssertFalse(l.bulkConfirm(3).isEmpty, "\(lang)")
            XCTAssertFalse(l.bulkConfirmRisky("파이리").isEmpty, "\(lang)")
        }
    }

    /// 칸 탭의 안전장치 — 이 네 조합이 선택 모드의 전부다. 셋째·넷째가 뒤집힌 게이트를 잡는다.
    /// 모드 밖에서는 `isPickable` 을 아예 안 봐야 한다 — 파트너도 상세는 지금처럼 열려야 한다.
    func testCellTapOutsideSelectingAlwaysOpensDetailRegardlessOfPickability() {
        XCTAssertEqual(BoxTabView.cellTap(selecting: false, isPickable: true), .openDetail)
        XCTAssertEqual(BoxTabView.cellTap(selecting: false, isPickable: false), .openDetail,
                       "파트너도 모드 밖에서는 상세가 열려야 한다")
    }

    func testCellTapInsideSelectingTogglesPickableAndIgnoresTheRest() {
        XCTAssertEqual(BoxTabView.cellTap(selecting: true, isPickable: true), .toggle)
        XCTAssertEqual(BoxTabView.cellTap(selecting: true, isPickable: false), .ignore,
                       "선택 모드에서 파트너를 눌러 상세로 새면 안 된다")
    }
}
