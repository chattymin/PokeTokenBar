import AppKit
import SwiftUI
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

    // MARK: 지급

    /// 파이리 → 리자드 → 리자몽 (일직선). 리자몽 노드에는 자식이 없다 = 최종형.
    private func charLine() -> EvoLine {
        EvoLine(baseID: 4,
                tree: EvoNode(speciesID: 4, children: [
                    EvoNode(speciesID: 5, children: [EvoNode(speciesID: 6, children: [])]),
                ]),
                rarity: .rare, names: [:])
    }

    /// 리자몽 한 마리를 박스에 넣고 돌려준다.
    private func charizard(_ store: PlayerStore, exp: Int) -> Individual {
        var individual = Individual(baseID: 4, speciesID: 6, pathIDs: [4, 5, 6],
                                    nature: .hardy, obtainedAt: now, grade: .epic)
        individual.exp = exp
        store.addForTesting(individual)
        return individual
    }

    /// **진화할 곳이 있으면 못 받는다.** 경험치는 진화에 쓰는 것이 먼저다.
    func testAnIndividualThatCanStillEvolveEarnsNothing() {
        let store = makeStore()
        var charmander = Individual(baseID: 4, speciesID: 4, pathIDs: [4],
                                    nature: .hardy, obtainedAt: now, grade: .epic)
        charmander.exp = EggVoucher.threshold(grade: .epic) * 10
        store.addForTesting(charmander)

        XCTAssertFalse(store.canClaimEggVoucher(charmander, line: charLine()))
        XCTAssertFalse(store.claimEggVoucher(individualID: charmander.id, line: charLine()))
        XCTAssertTrue(store.state.eggVouchers.isEmpty)
    }

    /// 최종형이어도 경험치가 모자라면 못 받는다.
    func testNotEnoughExpEarnsNothing() {
        let store = makeStore()
        let charizard = charizard(store, exp: EggVoucher.threshold(grade: .epic) - 1)
        XCTAssertFalse(store.canClaimEggVoucher(charizard, line: charLine()))
        XCTAssertFalse(store.claimEggVoucher(individualID: charizard.id, line: charLine()))
    }

    /// 최종형 + 경험치가 찼으면 받는다. **교환권은 `baseID` 를 가리킨다** — 리자몽이
    /// 부르는 것은 파이리 알이다. 이게 이 기능의 존재 이유(도감 구멍 메우기)다.
    func testAFullyEvolvedIndividualClaimsAVoucherForItsBase() {
        let store = makeStore()
        let charizard = charizard(store, exp: EggVoucher.threshold(grade: .epic))
        XCTAssertTrue(store.canClaimEggVoucher(charizard, line: charLine()))
        XCTAssertTrue(store.claimEggVoucher(individualID: charizard.id, line: charLine()))
        XCTAssertEqual(store.state.eggVouchers, [EggVoucher(baseID: 4, grade: .epic)])
    }

    /// **경험치는 임계만큼만 줄고 초과분은 남는다** — 진화의 이월과 같다.
    /// 이게 없으면 오래 비워 둔 사용자가 쌓아 둔 경험치를 한 장에 통째로 잃는다.
    func testExpCarriesOverSoVouchersCanBeClaimedInARow() {
        let store = makeStore()
        let threshold = EggVoucher.threshold(grade: .epic)
        let charizard = charizard(store, exp: threshold * 2 + 7)

        XCTAssertTrue(store.claimEggVoucher(individualID: charizard.id, line: charLine()))
        XCTAssertEqual(store.state.box.first { $0.id == charizard.id }?.exp, threshold + 7)

        XCTAssertTrue(store.claimEggVoucher(individualID: charizard.id, line: charLine()))
        XCTAssertEqual(store.state.box.first { $0.id == charizard.id }?.exp, 7)
        XCTAssertEqual(store.state.eggVouchers.count, 2)

        XCTAssertFalse(store.claimEggVoucher(individualID: charizard.id, line: charLine()))
        XCTAssertEqual(store.state.eggVouchers.count, 2, "경험치가 없는데 세 장째가 나왔다")
    }

    /// 박스에 없는 개체는 지급 대상이 아니다.
    func testClaimingForAnUnknownIndividualDoesNothing() {
        let store = makeStore()
        XCTAssertFalse(store.claimEggVoucher(individualID: UUID(), line: charLine()))
        XCTAssertTrue(store.state.eggVouchers.isEmpty)
    }

    // MARK: 사용

    /// **종이 확정이다 — 시드를 바꿔도 같은 종이 나온다.** 이 확정성이 기능의 이름 그 자체다.
    func testTheRedeemedEggIsAlwaysTheVouchersSpecies() {
        for seed in UInt64(1)...20 {
            let store = makeStore(seed: seed)
            store.mutate { $0.eggVouchers = [EggVoucher(baseID: 4, grade: .epic)] }
            let egg = store.redeemEggVoucher(baseID: 4)
            XCTAssertEqual(egg?.speciesID, 4, "시드 \(seed) 에서 다른 종이 나왔다")
            XCTAssertEqual(egg?.grade, .epic)
        }
    }

    /// 쓰면 한 장만 없어진다.
    func testRedeemingConsumesExactlyOneVoucher() {
        let store = makeStore()
        store.mutate { $0.eggVouchers = [EggVoucher(baseID: 4, grade: .epic),
                                         EggVoucher(baseID: 4, grade: .epic),
                                         EggVoucher(baseID: 25, grade: .common)] }
        XCTAssertNotNil(store.redeemEggVoucher(baseID: 4))
        XCTAssertEqual(store.state.eggVouchers,
                       [EggVoucher(baseID: 4, grade: .epic), EggVoucher(baseID: 25, grade: .common)])
    }

    /// 없는 교환권을 쓰려 하면 실패하고, 알도 안 생긴다.
    func testRedeemingAVoucherYouDoNotHaveFails() {
        let store = makeStore()
        XCTAssertNil(store.redeemEggVoucher(baseID: 4))
        XCTAssertTrue(store.state.eggs.isEmpty)
    }

    /// **슬롯이 꽉 차면 실패하고 교환권은 그대로 남는다.** 차감만 되고 알이 안 생기면
    /// 5000만 토큰어치가 조용히 증발한다.
    func testRedeemingWithNoFreeSlotKeepsTheVoucher() {
        let store = makeStore()
        store.mutate { $0.eggVouchers = [EggVoucher(baseID: 4, grade: .epic)] }
        for _ in 0..<store.state.slots {
            store.placeEgg(grade: .common, speciesID: 1, shiny: false)
        }
        XCTAssertNil(store.redeemEggVoucher(baseID: 4))
        XCTAssertEqual(store.state.eggVouchers, [EggVoucher(baseID: 4, grade: .epic)],
                       "알도 못 받고 교환권만 사라졌다")
    }

    /// **이로치는 확정이 아니다.** 종만 확정이다 — 이로치까지 확정이면 이로치 부적이 무의미해진다.
    /// 시드를 넓게 돌려 갈리는지 본다.
    func testShinyIsStillRolled() {
        var results = Set<Bool>()
        for seed in UInt64(1)...400 {
            let store = makeStore(seed: seed)
            store.mutate {
                $0.ownsShinyCharm = true      // 확률을 올려 400회 안에 양쪽이 나오게 한다
                $0.eggVouchers = [EggVoucher(baseID: 4, grade: .epic)]
            }
            if let egg = store.redeemEggVoucher(baseID: 4) { results.insert(egg.shiny) }
        }
        XCTAssertEqual(results, [true, false], "이로치가 굴려지지 않고 고정돼 있다")
    }

    // MARK: 화면 배선

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    /// 상세 화면이 지급 경로에 닿아 있다 — 안 닿으면 교환권을 영원히 못 받는다.
    func testTheDetailViewReachesTheClaimPath() throws {
        let text = try source("Sources/PokeDexBar/UI/IndividualDetailView.swift")
        XCTAssertTrue(text.contains("claimEggVoucher"), "상세에 교환권 받기 버튼이 없다")
    }

    /// 알 슬롯이 사용 경로에 닿아 있다 — 안 닿으면 받은 교환권을 영원히 못 쓴다.
    func testTheEggSlotsReachTheRedeemPath() throws {
        let text = try source("Sources/PokeDexBar/UI/EggSlotsView.swift")
        XCTAssertTrue(text.contains("redeemEggVoucher"), "알 슬롯에 교환권 쓰기가 없다")
    }

    /// 박스 칸이 배지를 그린다 — 개체를 하나씩 열어보지 않아도 받을 수 있는 아이가 보인다.
    func testTheBoxCellShowsAVoucherBadge() throws {
        let text = try source("Sources/PokeDexBar/UI/BoxTabView.swift")
        XCTAssertTrue(text.contains("canClaimVoucher"), "박스 칸에 교환권 배지가 없다")
    }

    /// **`.help()` 를 쓰지 않는다.** 이 팝오버 안에서 툴팁은 뜨지 않는다(실사용 확인).
    /// 설명은 인라인 한 줄로 적는다 — 부화 감면 안내에서 이미 한 번 밟았다.
    func testNoTooltipsInTheTouchedViews() throws {
        for path in ["Sources/PokeDexBar/UI/EggSlotsView.swift",
                     "Sources/PokeDexBar/UI/IndividualDetailView.swift"] {
            XCTAssertFalse(try source(path).contains(".help("),
                           "\(path) 에 안 뜨는 툴팁이 들어왔다")
        }
    }

    /// 문구가 세 언어를 다 채운다. `AppLanguage` 는 `ko`·`en`·`ja` 세 케이스다
    /// (`systemDefault` 는 케이스가 아니라 static var 이므로 `allCases` 에 안 들어온다).
    func testStringsCoverAllThreeLanguages() {
        for lang in AppLanguage.allCases {
            let l = L(lang)
            XCTAssertFalse(l.voucherSectionTitle.isEmpty, "\(lang)")
            XCTAssertFalse(l.voucherClaim.isEmpty, "\(lang)")
            XCTAssertFalse(l.voucherExplain.isEmpty, "\(lang)")
            XCTAssertFalse(l.voucherSlotBadge.isEmpty, "\(lang)")
        }
    }

    /// **빈 슬롯마다 같은 교환권을 가리키면 안 된다.** 교환권 1장 + 빈 칸 3개면 눌리는 칸은
    /// 딱 하나여야 한다 — 전부 눌리면 실제로는 1장인데 3장을 가진 것처럼 보인다.
    func testOnlyOneEmptySlotOffersASingleVoucher() {
        let vouchers = [EggVoucher(baseID: 4, grade: .epic)]
        XCTAssertEqual(EggSlotsView.voucher(forEmptySlotIndex: 0, in: vouchers), vouchers[0])
        XCTAssertNil(EggSlotsView.voucher(forEmptySlotIndex: 1, in: vouchers))
        XCTAssertNil(EggSlotsView.voucher(forEmptySlotIndex: 2, in: vouchers))
    }

    /// 종이 다른 교환권 두 장은 각자 자기 칸을 가져야 한다 — 둘 다 `.first` 를 보면 두 번째
    /// 종은 슬롯 줄에서 영영 손이 안 닿는다.
    func testEachVoucherGetsItsOwnSlotByIndex() {
        let vouchers = [EggVoucher(baseID: 4, grade: .epic), EggVoucher(baseID: 6, grade: .rare)]
        XCTAssertEqual(EggSlotsView.voucher(forEmptySlotIndex: 0, in: vouchers), vouchers[0])
        XCTAssertEqual(EggSlotsView.voucher(forEmptySlotIndex: 1, in: vouchers), vouchers[1])
        XCTAssertNil(EggSlotsView.voucher(forEmptySlotIndex: 2, in: vouchers))
    }

    // MARK: 경험치 막대의 분모 (finding 2) — expSection·voucherSection 이 공유하는 단일 소스

    /// **교환권 대상이면 교환권 임계를 쓴다.** 최종형의 진화 임계(등급 기본값 × 3)를 쓰면
    /// 200M 을 채워 버튼이 떴는데 막대는 33%인 결함이 난다.
    func testExpThresholdUsesVoucherRateWhenEligible() {
        let charizard = charizard(makeStore(), exp: 0)
        XCTAssertEqual(IndividualDetailView.expThreshold(individual: charizard, isVoucherCandidate: true),
                       EggVoucher.threshold(grade: .epic))
    }

    /// 대조군 — 진화할 곳이 있으면 그 등급·단계의 진화 임계를 그대로 쓴다.
    func testExpThresholdUsesEvolutionRateWhenNotEligible() {
        let charizard = charizard(makeStore(), exp: 0)
        XCTAssertEqual(IndividualDetailView.expThreshold(individual: charizard, isVoucherCandidate: false),
                       ExpBalance.threshold(grade: .epic, stageIndex: charizard.stageIndex))
    }

    /// 교환권 대상 판정 — 라인이 있고, 갈 곳이 없고, 위장 중이 아니어야 한다. 셋 중 하나만
    /// 빠져도 대상이 아니다(finding 1 이 지적한 위장 케이스 포함).
    func testIsVoucherCandidateRequiresLineNoChoicesAndNotDisguised() {
        XCTAssertTrue(IndividualDetailView.isVoucherCandidate(hasLine: true, hasEvolutionChoices: false,
                                                               isDisguised: false))
        XCTAssertFalse(IndividualDetailView.isVoucherCandidate(hasLine: false, hasEvolutionChoices: false,
                                                                isDisguised: false), "라인이 없는데 대상이다")
        XCTAssertFalse(IndividualDetailView.isVoucherCandidate(hasLine: true, hasEvolutionChoices: true,
                                                                isDisguised: false), "진화할 곳이 있는데 대상이다")
        XCTAssertFalse(IndividualDetailView.isVoucherCandidate(hasLine: true, hasEvolutionChoices: false,
                                                                isDisguised: true), "위장 중인데 대상이다")
    }

    // MARK: 상세 렌더 — 어떤 버튼이 실제로 뜨나 (finding 1·4)
    //
    // `testTheDetailViewReachesTheClaimPath` 같은 문자열 스캔은 "코드 어딘가에 이 심볼이
    // 있나"만 본다 — 잘못된 조건이나 빠진 분기는 못 잡는다(그게 이번 리뷰의 finding 1이었다).
    // `BoxCandyWiringTests` 가 쓰는 것과 같은 패턴으로 뷰를 실제로 그려 `DetailActionButton`
    // 을 수집한다.

    private func renderedDetailButtons(_ store: PlayerStore, individual: Individual,
                                       line: EvoLine?) -> [(title: String, action: () -> Void)] {
        DetailActionButton.resetConstructed()
        let host = NSHostingView(rootView: IndividualDetailView(
            store: store, individual: individual, line: line,
            onNeedLine: { _ in }, onBack: {}
        ).frame(width: PopoverMetrics.width))
        host.layoutSubtreeIfNeeded()
        return DetailActionButton.constructed
    }

    /// 최종형 + 임계 도달 → 교환권 버튼이 뜨고, **누르면 실제로 지급된다.**
    func testFullyEvolvedIndividualAtThresholdOffersClaimAndInvokingItGrantsTheVoucher() {
        let store = makeStore()
        let charizard = charizard(store, exp: EggVoucher.threshold(grade: .epic))
        let buttons = renderedDetailButtons(store, individual: charizard, line: charLine())
        guard let claim = buttons.first(where: { $0.title == store.l.voucherClaim }) else {
            return XCTFail("최종형이 임계를 채웠는데 교환권 버튼이 안 보인다: \(buttons.map(\.title))")
        }
        claim.action()
        XCTAssertEqual(store.state.eggVouchers, [EggVoucher(baseID: 4, grade: .epic)],
                       "버튼을 눌렀는데 교환권이 안 생겼다")
    }

    /// **위장 중인 개체는 임계를 채워도 교환권 버튼이 없다** — finding 1 이 지적한, 이전엔
    /// 아무 테스트도 없던 자리.
    func testDisguisedIndividualOffersNoClaimButtonEvenAtThreshold() {
        let store = makeStore()
        var ditto = Individual(baseID: 132, speciesID: 132, pathIDs: [132],
                               nature: .hardy, obtainedAt: now, grade: .epic)
        ditto.disguisedAs = 151   // 메타몽이 뮤로 위장 중
        ditto.exp = EggVoucher.threshold(grade: .epic)
        store.addForTesting(ditto)
        // 위장 중엔 화면이 위장한 종(뮤)의 라인을 받는다.
        let mewLine = EvoLine(baseID: 151, tree: EvoNode(speciesID: 151, children: []),
                              rarity: .legendary, names: [:])
        let buttons = renderedDetailButtons(store, individual: ditto, line: mewLine)
        XCTAssertNil(buttons.first(where: { $0.title == store.l.voucherClaim }),
                     "위장 중인 개체에 교환권 버튼이 떴다: \(buttons.map(\.title))")
    }

    /// 진화할 곳이 있으면 진화 버튼이지 교환권 버튼이 아니다.
    func testAnIndividualThatCanStillEvolveOffersEvolveNotClaim() {
        let store = makeStore()
        var charmander = Individual(baseID: 4, speciesID: 4, pathIDs: [4],
                                    nature: .hardy, obtainedAt: now, grade: .epic)
        charmander.exp = ExpBalance.threshold(grade: .epic, stageIndex: 0)
        store.addForTesting(charmander)
        let buttons = renderedDetailButtons(store, individual: charmander, line: charLine())
        XCTAssertNotNil(buttons.first(where: { $0.title == store.l.evolve }),
                        "진화 가능한 개체에 진화 버튼이 없다: \(buttons.map(\.title))")
        XCTAssertNil(buttons.first(where: { $0.title == store.l.voucherClaim }),
                     "진화 가능한 개체에 교환권 버튼이 떴다: \(buttons.map(\.title))")
    }
}
