import AppKit
import SwiftUI
import XCTest
@testable import PokeDexBar

/// 알 발견 — 더 진화할 곳이 없는 개체가 경험치를 모아 자기 라인의 알을 부른다. 받는 순간
/// 곧바로 부화 슬롯에 들어간다. 중간에 보관되는 물건은 없다(2026-08-11 개정 — 확정 알
/// 교환권을 없애고 받기·보관·쓰기 3단계를 한 단계로 합쳤다).
@MainActor
final class FoundEggTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeStore(seed: UInt64 = 1) -> PlayerStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("found-egg-\(UUID().uuidString).json")
        return PlayerStore(fileURL: url, rng: SeededRNG(seed: seed), now: { self.now })
    }

    // MARK: 임계

    /// 표에 적힌 절대값. 커먼 5억에서 등급마다 두 배다.
    func testEggThresholdValues() {
        XCTAssertEqual(ExpBalance.eggThreshold(grade: .common), 500_000_000)
        XCTAssertEqual(ExpBalance.eggThreshold(grade: .rare), 1_000_000_000)
        XCTAssertEqual(ExpBalance.eggThreshold(grade: .epic), 2_000_000_000)
        XCTAssertEqual(ExpBalance.eggThreshold(grade: .legendary), 4_000_000_000)
    }

    /// 등급이 오를 때마다 정확히 두 배 — 값이 하나만 조정되어 비율이 무너지는 것을 막는다.
    func testEggThresholdDoublesEachGrade() {
        let ladder: [Grade] = [.common, .rare, .epic, .legendary]
        for (lower, higher) in zip(ladder, ladder.dropFirst()) {
            XCTAssertEqual(ExpBalance.eggThreshold(grade: higher),
                           ExpBalance.eggThreshold(grade: lower) * 2,
                           "\(higher) 가 \(lower) 의 두 배가 아니다")
        }
    }

    /// **진화 임계와 별개다.** 예전엔 알 임계가 `threshold(grade:stageIndex: 0)` 을 그대로 썼다.
    /// 지금은 근거가 다르다 — 진화는 "얼마나 써야 다음 단계인가", 알은 "확정 종 하나가 얼마인가".
    /// 한쪽을 조정할 때 다른 쪽이 딸려 움직이면 안 된다.
    func testEggThresholdIsNotDerivedFromTheEvolutionThreshold() {
        for grade in Grade.allCases {
            XCTAssertNotEqual(ExpBalance.eggThreshold(grade: grade),
                              ExpBalance.threshold(grade: grade, stageIndex: 0),
                              "\(grade) 의 알 임계가 진화 임계에 다시 묶였다")
        }
    }

    // MARK: 슬롯 배치와 값 치르기의 분리

    /// 지갑을 채운다 — `update` 의 기준선을 잡고 그 위로 사용량을 올린다.
    private func giveWallet(_ store: PlayerStore, _ tokens: Int) {
        store.update(todayTokens: 0, todayDate: "d", hasUsageData: true)
        store.update(todayTokens: tokens, todayDate: "d", hasUsageData: true)
    }

    /// **`placeEgg` 는 값을 안 치른다.** 알 발견 경로가 이걸 부른다 — `startEgg` 을 그대로
    /// 부르면 경험치 말고 토큰까지 내게 된다.
    func testPlaceEggCostsNothing() {
        let store = makeStore()
        let before = store.state.spentTokens
        XCTAssertNotNil(store.placeEgg(grade: .common, speciesID: 4, shiny: false))
        XCTAssertEqual(store.state.spentTokens, before, "알 발견에 토큰이 나갔다")
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

    /// 지갑이 비어도 `placeEgg` 는 된다 — 경험치가 값이기 때문이다.
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

    /// **발견한 알도 부화 감면을 받는다.** 감면 계산이 `startEgg` 안에 있으므로, 떼어내면서
    /// 값 치르는 쪽에 남겨두기 쉬운 자리다.
    func testPlaceEggGetsTheHatchSpeedup() throws {
        let store = makeStore()
        // 마그마그(불꽃몸 계열)를 박스에 넣으면 감면이 걸린다.
        store.addForTesting(Individual(baseID: 218, speciesID: 218, pathIDs: [218],
                                       nature: .hardy, obtainedAt: now, grade: .common))
        let egg = try XCTUnwrap(store.placeEgg(grade: .common, speciesID: 4, shiny: false))
        XCTAssertEqual(egg.hatchesAt.timeIntervalSince(now),
                       EggBalance.duration(.common) * HatchSpeedup.multiplier,
                       accuracy: 1, "발견한 알이 감면을 못 받았다")
    }

    // MARK: 받기

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
    func testAnIndividualThatCanStillEvolveTakesNoEgg() {
        let store = makeStore()
        var charmander = Individual(baseID: 4, speciesID: 4, pathIDs: [4],
                                    nature: .hardy, obtainedAt: now, grade: .epic)
        charmander.exp = ExpBalance.eggThreshold(grade: .epic) * 10
        store.addForTesting(charmander)

        XCTAssertFalse(store.canTakeFoundEgg(charmander, line: charLine()))
        XCTAssertNil(store.takeFoundEgg(individualID: charmander.id, line: charLine()))
        XCTAssertTrue(store.state.eggs.isEmpty)
    }

    /// **위장 중인 개체는 알을 못 받는다.** 뷰와 스토어가 같은 술어를 쓰는지 — 예전 갈래
    /// 기능(교환권)에서 이 부분이 실제로 갈린 적이 있다.
    func testADisguisedIndividualTakesNoEgg() {
        let store = makeStore()
        var ditto = Individual(baseID: 132, speciesID: 132, pathIDs: [132],
                               nature: .hardy, obtainedAt: now, grade: .epic)
        ditto.disguisedAs = 151   // 메타몽이 뮤로 위장 중
        ditto.exp = ExpBalance.eggThreshold(grade: .epic)
        store.addForTesting(ditto)
        let mewLine = EvoLine(baseID: 151, tree: EvoNode(speciesID: 151, children: []),
                              rarity: .legendary, names: [:])

        XCTAssertFalse(store.canTakeFoundEgg(ditto, line: mewLine))
        XCTAssertNil(store.takeFoundEgg(individualID: ditto.id, line: mewLine))
        XCTAssertTrue(store.state.eggs.isEmpty)
    }

    /// 최종형이어도 경험치가 모자라면 못 받는다.
    func testNotEnoughExpTakesNoEgg() {
        let store = makeStore()
        let charizard = charizard(store, exp: ExpBalance.eggThreshold(grade: .epic) - 1)
        XCTAssertFalse(store.canTakeFoundEgg(charizard, line: charLine()))
        XCTAssertNil(store.takeFoundEgg(individualID: charizard.id, line: charLine()))
    }

    /// 최종형 + 경험치가 찼으면 받는다. **알의 종은 `baseID` 를 가리킨다** — 리자몽이
    /// 부르는 것은 파이리 알이다. 이게 이 기능의 존재 이유(도감 구멍 메우기)다.
    func testAFullyEvolvedIndividualTakesAnEggForItsBase() {
        let store = makeStore()
        let charizard = charizard(store, exp: ExpBalance.eggThreshold(grade: .epic))
        XCTAssertTrue(store.canTakeFoundEgg(charizard, line: charLine()))
        let egg = store.takeFoundEgg(individualID: charizard.id, line: charLine())
        XCTAssertEqual(egg?.speciesID, 4, "리자몽이 자기 종 알을 불렀다")
        XCTAssertEqual(egg?.grade, .epic)
        XCTAssertEqual(store.state.eggs.count, 1)
    }

    /// **종이 확정이다 — 시드를 바꿔도 같은 종이 나온다.** 이 확정성이 기능의 요점이다.
    func testTheFoundEggIsAlwaysTheIndividualsBase() {
        for seed in UInt64(1)...20 {
            let store = makeStore(seed: seed)
            let charizard = charizard(store, exp: ExpBalance.eggThreshold(grade: .epic))
            let egg = store.takeFoundEgg(individualID: charizard.id, line: charLine())
            XCTAssertEqual(egg?.speciesID, 4, "시드 \(seed) 에서 다른 종이 나왔다")
            XCTAssertEqual(egg?.grade, .epic)
        }
    }

    /// **이로치는 확정이 아니다.** 종만 확정이다 — 이로치까지 확정이면 이로치 부적이 무의미해진다.
    /// 시드를 넓게 돌려 갈리는지 본다.
    func testShinyIsStillRolled() {
        var results = Set<Bool>()
        for seed in UInt64(1)...400 {
            let store = makeStore(seed: seed)
            store.mutate { $0.ownsShinyCharm = true }   // 확률을 올려 400회 안에 양쪽이 나오게 한다
            let charizard = charizard(store, exp: ExpBalance.eggThreshold(grade: .epic))
            if let egg = store.takeFoundEgg(individualID: charizard.id, line: charLine()) {
                results.insert(egg.shiny)
            }
        }
        XCTAssertEqual(results, [true, false], "이로치가 굴려지지 않고 고정돼 있다")
    }

    /// **받으면 0 으로 돌아가고, 한 번에 한 개다.** 이월을 남기면 오래 비워 둔 사용자에게
    /// 알이 두세 개 예약돼 버려, 받는 것이 결정이 아니라 밀린 수령이 된다.
    ///
    /// 경험치를 임계의 두 배로 넣어 두고도 두 번째가 안 나와야 한다 — 실제 경로에서는 상한
    /// (`testExpStopsAtTheEggThreshold`)이 있어 두 배까지 쌓이지도 않지만, 두 장치가 각각
    /// 독립적으로 성립해야 한 쪽이 무너져도 알이 밀리지 않는다.
    func testTakingAnEggResetsExpToZero() {
        let store = makeStore()
        let threshold = ExpBalance.eggThreshold(grade: .epic)
        let charizard = charizard(store, exp: threshold * 2 + 7)

        XCTAssertNotNil(store.takeFoundEgg(individualID: charizard.id, line: charLine()))
        XCTAssertEqual(store.state.box.first { $0.id == charizard.id }?.exp, 0, "이월이 남았다")

        XCTAssertNil(store.takeFoundEgg(individualID: charizard.id, line: charLine()))
        XCTAssertEqual(store.state.eggs.count, 1, "받자마자 두 번째 알이 나왔다")
    }

    /// **경험치는 알 임계에서 멈춘다.** 다 찬 뒤에도 계속 쌓이면 알이 여러 개 예약된다.
    func testExpStopsAtTheEggThreshold() {
        let store = makeStore()
        let charizard = charizard(store, exp: 0)
        store.setPartner(charizard.id)
        let cap = ExpBalance.eggThreshold(grade: .epic)

        store.update(todayTokens: 0, todayDate: "d", hasUsageData: true)      // 기준선
        store.update(todayTokens: cap * 3, todayDate: "d", hasUsageData: true)
        XCTAssertEqual(store.state.box.first { $0.id == charizard.id }?.exp, cap,
                       "상한을 넘어 쌓였다")
    }

    /// **상한은 진화를 막지 않는다.** 알 임계는 어느 등급에서도 그 등급의 최대 진화 임계
    /// (기본값 × 3)보다 훨씬 크므로, 상한에 걸린 개체는 언제나 진화 임계를 이미 넘어 있다.
    /// 이게 깨지면 상한이 진화를 영구히 잠근다 — `EvoLine` 없이 상한을 걸 수 있는 근거다.
    func testTheCapNeverBlocksAnEvolution() {
        for grade in Grade.allCases {
            let deepest = ExpBalance.threshold(grade: grade, stageIndex: 1)
            XCTAssertGreaterThan(ExpBalance.eggThreshold(grade: grade), deepest,
                                 "\(grade) 는 상한에 걸린 채로도 진화를 못 한다")
        }
    }

    /// 박스에 없는 개체는 지급 대상이 아니다.
    func testTakingAnEggForAnUnknownIndividualDoesNothing() {
        let store = makeStore()
        XCTAssertNil(store.takeFoundEgg(individualID: UUID(), line: charLine()))
        XCTAssertTrue(store.state.eggs.isEmpty)
    }

    /// **슬롯이 꽉 차면 실패하고, 경험치도 안 줄어든다.** 알을 먼저 놓고 놓였을 때만 깎는
    /// 순서를 뒤집으면 여기서 깨진다 — 5000만~4억 토큰어치가 조용히 증발한다.
    func testTakingAnEggWithNoFreeSlotKeepsTheExp() {
        let store = makeStore()
        let threshold = ExpBalance.eggThreshold(grade: .epic)
        let charizard = charizard(store, exp: threshold)
        for _ in 0..<store.state.slots {
            store.placeEgg(grade: .common, speciesID: 1, shiny: false)
        }
        XCTAssertFalse(store.canTakeFoundEgg(charizard, line: charLine()))
        XCTAssertNil(store.takeFoundEgg(individualID: charizard.id, line: charLine()))
        XCTAssertEqual(store.state.box.first { $0.id == charizard.id }?.exp, threshold,
                       "알도 못 받고 경험치만 사라졌다")
        XCTAssertEqual(store.state.eggs.count, store.state.slots)
    }

    // MARK: 화면 배선

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    /// 상세 화면이 지급 경로에 닿아 있다 — 안 닿으면 알을 영원히 못 받는다.
    func testTheDetailViewReachesTheTakePath() throws {
        let text = try source("Sources/PokeDexBar/UI/IndividualDetailView.swift")
        XCTAssertTrue(text.contains("takeFoundEgg"), "상세에 알 발견 버튼이 없다")
    }

    /// **`.help()` 를 쓰지 않는다.** 이 팝오버 안에서 툴팁은 뜨지 않는다(실사용 확인).
    /// 설명은 인라인 한 줄로 적는다.
    func testNoTooltipsInTheTouchedViews() throws {
        for path in ["Sources/PokeDexBar/UI/EggSlotsView.swift",
                     "Sources/PokeDexBar/UI/IndividualDetailView.swift",
                     "Sources/PokeDexBar/UI/FoundEggAnnouncementCard.swift"] {
            XCTAssertFalse(try source(path).contains(".help("),
                           "\(path) 에 안 뜨는 툴팁이 들어왔다")
        }
    }

    /// 문구가 세 언어를 다 채운다. `AppLanguage` 는 `ko`·`en`·`ja` 세 케이스다
    /// (`systemDefault` 는 케이스가 아니라 static var 이므로 `allCases` 에 안 들어온다).
    func testStringsCoverAllThreeLanguages() {
        for lang in AppLanguage.allCases {
            let l = L(lang)
            XCTAssertFalse(l.eggFound("파이리").isEmpty, "\(lang)")
            XCTAssertFalse(l.eggFoundNoFreeSlot.isEmpty, "\(lang)")
            XCTAssertFalse(l.partnerFoundEgg("파이리").isEmpty, "\(lang)")
        }
    }

    // MARK: 경험치 막대의 분모 — expSection·foundEggSection 이 공유하는 단일 소스

    /// **알 발견 후보면 알 임계를 쓴다.** 최종형의 진화 임계(등급 기본값 × 3)를 쓰면
    /// 200M 을 채워 버튼이 떴는데 막대는 33%인 결함이 난다.
    func testExpThresholdUsesEggRateWhenEligible() {
        let charizard = charizard(makeStore(), exp: 0)
        XCTAssertEqual(IndividualDetailView.expThreshold(individual: charizard, isFoundEggCandidate: true),
                       ExpBalance.eggThreshold(grade: .epic))
    }

    /// 대조군 — 진화할 곳이 있으면 그 등급·단계의 진화 임계를 그대로 쓴다.
    func testExpThresholdUsesEvolutionRateWhenNotEligible() {
        let charizard = charizard(makeStore(), exp: 0)
        XCTAssertEqual(IndividualDetailView.expThreshold(individual: charizard, isFoundEggCandidate: false),
                       ExpBalance.threshold(grade: .epic, stageIndex: charizard.stageIndex))
    }

    /// 알 발견 후보 판정 — 라인이 있고, 갈 곳이 없고, 위장 중이 아니어야 한다. 셋 중 하나만
    /// 빠져도 대상이 아니다.
    func testIsFoundEggCandidateRequiresLineNoChoicesAndNotDisguised() {
        XCTAssertTrue(IndividualDetailView.isFoundEggCandidate(hasLine: true, hasEvolutionChoices: false,
                                                                isDisguised: false))
        XCTAssertFalse(IndividualDetailView.isFoundEggCandidate(hasLine: false, hasEvolutionChoices: false,
                                                                 isDisguised: false), "라인이 없는데 대상이다")
        XCTAssertFalse(IndividualDetailView.isFoundEggCandidate(hasLine: true, hasEvolutionChoices: true,
                                                                 isDisguised: false), "진화할 곳이 있는데 대상이다")
        XCTAssertFalse(IndividualDetailView.isFoundEggCandidate(hasLine: true, hasEvolutionChoices: false,
                                                                 isDisguised: true), "위장 중인데 대상이다")
    }

    // MARK: 상세 렌더 — 어떤 버튼이 실제로 뜨나
    //
    // `testTheDetailViewReachesTheTakePath` 같은 문자열 스캔은 "코드 어딘가에 이 심볼이
    // 있나"만 본다 — 잘못된 조건이나 빠진 분기는 못 잡는다. `BoxCandyWiringTests` 가 쓰는 것과
    // 같은 패턴으로 뷰를 실제로 그려 `DetailActionButton` 을 수집한다.

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

    /// 최종형 + 임계 도달 → 알 발견 버튼이 뜨고, **누르면 실제로 알이 슬롯에 들어간다.**
    func testFullyEvolvedIndividualAtThresholdOffersFoundEggAndInvokingItPlacesTheEgg() {
        let store = makeStore()
        let charizard = charizard(store, exp: ExpBalance.eggThreshold(grade: .epic))
        let buttons = renderedDetailButtons(store, individual: charizard, line: charLine())
        guard let take = buttons.first(where: { $0.title == store.l.eggFound("#4") }) else {
            return XCTFail("최종형이 임계를 채웠는데 알 발견 버튼이 안 보인다: \(buttons.map(\.title))")
        }
        take.action()
        XCTAssertEqual(store.state.eggs.count, 1, "버튼을 눌렀는데 알이 안 생겼다")
        XCTAssertEqual(store.state.eggs.first?.speciesID, 4)
    }

    /// **위장 중인 개체는 임계를 채워도 알 발견 버튼이 없다.**
    func testDisguisedIndividualOffersNoFoundEggButtonEvenAtThreshold() {
        let store = makeStore()
        var ditto = Individual(baseID: 132, speciesID: 132, pathIDs: [132],
                               nature: .hardy, obtainedAt: now, grade: .epic)
        ditto.disguisedAs = 151   // 메타몽이 뮤로 위장 중
        ditto.exp = ExpBalance.eggThreshold(grade: .epic)
        store.addForTesting(ditto)
        // 위장 중엔 화면이 위장한 종(뮤)의 라인을 받는다.
        let mewLine = EvoLine(baseID: 151, tree: EvoNode(speciesID: 151, children: []),
                              rarity: .legendary, names: [:])
        let buttons = renderedDetailButtons(store, individual: ditto, line: mewLine)
        // 위장 중엔 진화 버튼도 안 뜨므로(정체를 흘린다), 남는 건 "파트너로" 뿐이어야 한다.
        XCTAssertEqual(buttons.map(\.title), [store.l.makePartner],
                       "위장 중인 개체에 알 발견 버튼이 떴다: \(buttons.map(\.title))")
    }

    /// 진화할 곳이 있으면 진화 버튼이지 알 발견 버튼이 아니다.
    func testAnIndividualThatCanStillEvolveOffersEvolveNotFoundEgg() {
        let store = makeStore()
        var charmander = Individual(baseID: 4, speciesID: 4, pathIDs: [4],
                                    nature: .hardy, obtainedAt: now, grade: .epic)
        charmander.exp = ExpBalance.threshold(grade: .epic, stageIndex: 0)
        store.addForTesting(charmander)
        let buttons = renderedDetailButtons(store, individual: charmander, line: charLine())
        XCTAssertNotNil(buttons.first(where: { $0.title == store.l.evolve }),
                        "진화 가능한 개체에 진화 버튼이 없다: \(buttons.map(\.title))")
        XCTAssertNil(buttons.first(where: { $0.title == store.l.eggFound("#4") }),
                     "진화 가능한 개체에 알 발견 버튼이 떴다: \(buttons.map(\.title))")
    }

    /// **빈 슬롯이 없으면 버튼은 뜨지만(숨기지 않는다) 눌러도 아무 일이 없다.**
    ///
    /// `DetailActionButton` 의 `#if DEBUG` 레코더는 (title, action) 만 담고 SwiftUI 의
    /// `.disabled` 상태 자체는 기록하지 않는다 — 그래서 "비활성으로 그려지는가"는 이 레코더로는
    /// 직접 검증할 수 없다(리포트에 기록). 대신 이 테스트는 **눈에 보이는 동작**을 검증한다:
    /// 슬롯이 꽉 찼을 때도 버튼은 여전히 존재하고(숨겨지지 않는다), 그 자리에서 액션을
    /// 그대로 불러도 `canTakeFoundEgg` 가 막아 알도 안 생기고 경험치도 그대로다.
    func testFullyEvolvedIndividualWithNoFreeSlotStillShowsTheButtonButActingDoesNothing() {
        let store = makeStore()
        let threshold = ExpBalance.eggThreshold(grade: .epic)
        let charizard = charizard(store, exp: threshold)
        for _ in 0..<store.state.slots {
            store.placeEgg(grade: .common, speciesID: 1, shiny: false)
        }
        let buttons = renderedDetailButtons(store, individual: charizard, line: charLine())
        guard let take = buttons.first(where: { $0.title == store.l.eggFound("#4") }) else {
            return XCTFail("슬롯이 찼다고 알 발견 버튼이 숨겨졌다(비활성이어야지 숨으면 안 된다): \(buttons.map(\.title))")
        }
        let eggsBefore = store.state.eggs.count
        take.action()
        XCTAssertEqual(store.state.eggs.count, eggsBefore, "비활성이어야 할 버튼을 눌렀는데 알이 생겼다")
        XCTAssertEqual(store.state.box.first { $0.id == charizard.id }?.exp, threshold,
                       "비활성이어야 할 버튼을 눌렀는데 경험치가 깎였다")
    }
}
