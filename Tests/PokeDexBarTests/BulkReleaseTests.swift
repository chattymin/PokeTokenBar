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

    // MARK: 보내기 버튼의 게이트 — grep 이 아니라 값으로 잠근다
    //
    // `testTheBoxReachesTheBulkPath` 는 소스에 "BulkRelease.confirmSteps" 문자열이 있는지만
    // 본다. `let steps = …` 바인딩만 있으면 `steps` 를 한 번도 안 읽어도 통과하므로, 게이트를
    // `bulkStep < steps ? … : send` 에서 `steps` 비교를 지우고 첫 클릭에 바로 보내도 안 걸린다.
    // `bulkSendPress` 를 직접 테스트해 이 부류를 잡는다.

    /// 마지막 단계 전까지는 다음 단계로만 간다. **첫 클릭도 예외가 아니다** — 담은 것만
    /// 있고 아직 한 번도 안 누른 상태(`step == 0`)에서 처음 누르면 확인 화면을 여는 것으로
    /// 끝난다(평범한 배치도 마찬가지다), 곧바로 보내지 않는다.
    func testBulkSendPressAdvancesBeforeTheFinalStep() {
        XCTAssertEqual(BoxTabView.bulkSendPress(step: 0, steps: 1), .advance,
                       "담기만 하고 아직 한 번도 안 누른 상태에서 곧바로 보내면 안 된다")
        XCTAssertEqual(BoxTabView.bulkSendPress(step: 0, steps: 2), .advance)
        XCTAssertEqual(BoxTabView.bulkSendPress(step: 1, steps: 2), .advance)
    }

    /// 마지막 단계에 이르면 보낸다 — 평범한 배치(steps=1)는 확인 화면(step=1)이 곧 마지막
    /// 단계라 거기서 한 번 더 누르면 나간다.
    func testBulkSendPressSendsAtTheFinalStep() {
        XCTAssertEqual(BoxTabView.bulkSendPress(step: 1, steps: 1), .send)
        XCTAssertEqual(BoxTabView.bulkSendPress(step: 2, steps: 2), .send)
    }

    // MARK: 확인 문구 — 첫 확인과 마지막 확인이 화면에서 실제로 갈려야 한다
    //
    // 전에는 `bulkStep > 0` 하나로만 갈라 이로치·전설이 섞인 배치(steps=2)의 1단계·2단계
    // 화면이 완전히 같은 문구를 냈다 — 세 번 연타해도 첫 클릭이 먹었는지 알 길이 없었다.

    /// 첫 확인은 마릿수를 담은 `bulkConfirm`.
    func testBulkConfirmTextAtFirstStepCarriesTheCount() {
        let l = L(.ko)
        XCTAssertEqual(BoxTabView.bulkConfirmText(step: 1, count: 3, l: l), l.bulkConfirm(3))
    }

    /// 마지막 확인(이로치·전설이 섞였을 때만 도달)은 단일 보내기의 재확인 문구를 그대로
    /// 재사용한다 — 여기서 세 번째 문구 규칙을 새로 적지 않는다.
    func testBulkConfirmTextAtFinalStepReusesTheSingleSendWording() {
        let l = L(.ko)
        XCTAssertEqual(BoxTabView.bulkConfirmText(step: 2, count: 3, l: l), l.sendConfirmAgain)
    }

    /// **두 화면이 실제로 다른 문구를 낸다.** 이게 없으면 게이트는 맞아도 화면이 똑같아
    /// 사용자가 몇 번째 클릭인지 못 느낀다 — 이 리뷰가 잡은 결함 그 자체다.
    func testBulkConfirmTextDiffersBetweenFirstAndFinalStep() {
        let l = L(.ko)
        XCTAssertNotEqual(BoxTabView.bulkConfirmText(step: 1, count: 3, l: l),
                          BoxTabView.bulkConfirmText(step: 2, count: 3, l: l))
    }

    // MARK: 모드 전환 — "모드를 나가면 선택이 비워지고, 보낸 뒤에는 모드는 남고 선택만 비워진다"

    /// 모드 안으로 들어갈 때는 담은 것·확인 단계를 그대로 둔다(들어가는 순간엔 비어 있으니
    /// 사실상 항상 빈 채로 시작하지만, 이 함수가 나갈 때만 비운다는 것 자체를 잠근다).
    func testAfterToggleModeEnteringLeavesPickedAndStepUntouched() {
        let entering = BoxTabView.BulkSelection(selecting: false, picked: [], bulkStep: 0)
        let next = BoxTabView.afterToggleMode(entering)
        XCTAssertTrue(next.selecting)
        XCTAssertTrue(next.picked.isEmpty)
        XCTAssertEqual(next.bulkStep, 0)
    }

    /// 모드를 나가면 담은 것과 확인 단계가 **둘 다** 비워진다 — 다음에 열었을 때 지난 선택이
    /// 남아 있으면 무엇을 보내는지 모르는 채로 누르게 된다.
    func testAfterToggleModeExitingClearsBothPickedAndStep() {
        let leaving = BoxTabView.BulkSelection(selecting: true, picked: [UUID(), UUID()], bulkStep: 2)
        let next = BoxTabView.afterToggleMode(leaving)
        XCTAssertFalse(next.selecting)
        XCTAssertTrue(next.picked.isEmpty)
        XCTAssertEqual(next.bulkStep, 0)
    }

    /// 보낸 뒤에는 **모드에 머무른다** — 정리는 보통 한 번에 안 끝나고, 보낸 직후가 다음 것을
    /// 고르기 가장 좋은 순간이다. 담은 것과 확인 단계만 비운다.
    func testAfterSendClearsPickedAndStepButKeepsMode() {
        let midConfirm = BoxTabView.BulkSelection(selecting: true, picked: [UUID(), UUID()], bulkStep: 2)
        let next = BoxTabView.afterSend(midConfirm)
        XCTAssertTrue(next.selecting, "보낸 뒤 모드가 꺼지면 다음 정리를 또 처음부터 열어야 한다")
        XCTAssertTrue(next.picked.isEmpty)
        XCTAssertEqual(next.bulkStep, 0)
    }

    // MARK: 위험한 아이 이름의 표식 — 이름만으론 "왜 불려 있는지" 안 보인다

    /// 이로치는 표식이 붙고, 평범한 아이는 이름 그대로다.
    func testRiskyLabelMarksShiny() {
        let l = L(.ko)
        let shiny = make(.rare, path: [4], shiny: true)
        XCTAssertEqual(BulkRelease.riskyLabel(shiny, name: "파이리", l: l), "이로치 파이리")

        let plain = make(.common, path: [1])
        XCTAssertEqual(BulkRelease.riskyLabel(plain, name: "이상해씨", l: l), "이상해씨")
    }

    /// 전설은 등급 이름이 표식으로 붙는다 — `Grade.label` 하나만 쓴다(두 번째 등급 이름을
    /// 새로 안 적는다).
    func testRiskyLabelMarksLegendaryWithItsGradeLabel() {
        let l = L(.ko)
        let legendary = make(.legendary, path: [150])
        XCTAssertEqual(BulkRelease.riskyLabel(legendary, name: "뮤츠", l: l),
                       "\(Grade.legendary.label(.ko)) 뮤츠")
    }

    /// 이로치 전설은 두 표식이 다 붙는다.
    func testRiskyLabelMarksBothWhenShinyAndLegendary() {
        let l = L(.ko)
        let both = make(.legendary, path: [150], shiny: true)
        XCTAssertEqual(BulkRelease.riskyLabel(both, name: "뮤츠", l: l),
                       "이로치 \(Grade.legendary.label(.ko)) 뮤츠")
    }

    /// **위장 중인 아이는 표식을 안 붙인다.** 이름이 이미 "???" 라, 표식을 더 붙이면 정체는
    /// 몰라도 "뭔가 특별한 게 숨어 있다"는 힌트가 반쯤 샌다.
    func testRiskyLabelLeavesDisguisedNameAlone() {
        var disguised = make(.legendary, path: [132], shiny: true)
        disguised.disguisedAs = 151
        XCTAssertEqual(BulkRelease.riskyLabel(disguised, name: Individual.unknownName, l: L(.ko)),
                       Individual.unknownName)
    }

    /// 세 언어 모두 표식이 비어 있지 않다.
    func testRiskyShinyMarkCoversAllThreeLanguages() {
        for lang in AppLanguage.allCases {
            XCTAssertFalse(L(lang).riskyShinyMark.isEmpty, "\(lang)")
        }
    }
}
