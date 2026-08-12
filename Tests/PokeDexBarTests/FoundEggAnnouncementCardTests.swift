import AppKit
import SwiftUI
import XCTest
@testable import PokeDexBar

/// 홈의 알 발견 알림 — 파트너가 임계를 채우면 그 개체가 알을 가져왔다고 알린다.
///
/// 예전엔 이 알림이 박스 칸 배지였다. 경험치는 파트너에게만 쌓이므로(`PlayerStore.update`)
/// 그 배지가 실제로 뜨는 경우는 "파트너를 바꾼 옛 개체가 슬쩍 임계를 채운" 희귀 케이스뿐이었다.
/// 홈으로 옮기고, 빈 슬롯이 없어도 배지가 숨는 문제(구 리비전의 concern)도 같이 사라졌다 —
/// 카드는 이제 "임계를 채웠나"만 보고, 빈 슬롯 여부는 버튼의 활성/비활성만 가른다.
@MainActor
final class FoundEggAnnouncementCardTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeStore(seed: UInt64 = 1) -> PlayerStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("found-egg-card-\(UUID().uuidString).json")
        return PlayerStore(fileURL: url, rng: SeededRNG(seed: seed), now: { self.now })
    }

    /// 파이리 → 리자드 → 리자몽 (일직선). 리자몽 노드에는 자식이 없다 = 최종형.
    private func charLine() -> EvoLine {
        EvoLine(baseID: 4,
                tree: EvoNode(speciesID: 4, children: [
                    EvoNode(speciesID: 5, children: [EvoNode(speciesID: 6, children: [])]),
                ]),
                rarity: .rare, names: [:])
    }

    /// 리자몽을 박스에 넣고 **파트너로 지정한** 뒤 돌려준다 — 경험치는 파트너에게만 쌓이므로
    /// 이 카드가 보는 것은 항상 파트너다. 카드의 판정은 `eggProgress` 다(`exp` 가 아니다) —
    /// `exp` 도 같이 심어 두는 것은 이 값을 그대로 여러 값 확인에 재사용하는 다른 테스트와의
    /// 호환을 위해서일 뿐, 카드 자체는 `eggProgress` 만 본다.
    @discardableResult
    private func charizardPartner(_ store: PlayerStore, exp: Int) -> Individual {
        var individual = Individual(baseID: 4, speciesID: 6, pathIDs: [4, 5, 6],
                                    nature: .hardy, obtainedAt: now, grade: .epic)
        individual.exp = exp
        individual.eggProgress = exp
        store.addForTesting(individual)
        store.setPartner(individual.id)
        return individual
    }

    private func render(_ store: PlayerStore, partner: Individual?, line: EvoLine?) -> NSView {
        let host = NSHostingView(rootView: FoundEggAnnouncementCard(
            store: store, partner: partner, line: line
        ).frame(width: PopoverMetrics.contentWidth))
        host.layoutSubtreeIfNeeded()
        return host
    }

    // MARK: 뜨는 조건 — 컴포넌트를 직접 렌더해 순수 판정을 눈에 보이는 크기로 잠근다.
    // (`DiscoveryCardRenderTests` 와 같은 패턴: 카드 자체만 렌더해 fittingSize 로 존재를 잰다.)

    func testNoCardWithoutAPartner() {
        let store = makeStore()
        let host = render(store, partner: nil, line: nil)
        XCTAssertEqual(host.fittingSize.height, 0, "파트너가 없는데 카드가 자리를 차지한다")
    }

    /// 라인은 네트워크에서 비동기로 온다 — 아직 없으면 판단을 보류하고 아무것도 안 보여준다
    /// (`PopoverView.showsEvolutionBadge` 와 같은 원칙).
    func testNoCardWithoutTheLine() {
        let store = makeStore()
        let partner = charizardPartner(store, exp: ExpBalance.eggThreshold(grade: .epic))
        let host = render(store, partner: partner, line: nil)
        XCTAssertEqual(host.fittingSize.height, 0, "라인이 아직 없는데 카드가 자리를 차지한다")
    }

    func testNoCardWhenNotEnoughExp() {
        let store = makeStore()
        let partner = charizardPartner(store, exp: ExpBalance.eggThreshold(grade: .epic) - 1)
        let host = render(store, partner: partner, line: charLine())
        XCTAssertEqual(host.fittingSize.height, 0, "경험치가 안 찼는데 카드가 뜬다")
    }

    /// **더 진화할 곳이 있어도 이제는 카드가 뜬다.** 예전엔 "최종형만"이었지만, `exp` 와
    /// `eggProgress` 가 분리된 뒤로는 파트너 조건 하나로 충분하다.
    func testCardAppearsEvenWhenEvolutionIsStillAvailable() {
        let store = makeStore()
        var charmander = Individual(baseID: 4, speciesID: 4, pathIDs: [4],
                                    nature: .hardy, obtainedAt: now, grade: .epic)
        charmander.eggProgress = ExpBalance.eggThreshold(grade: .epic)
        store.addForTesting(charmander)
        store.setPartner(charmander.id)
        XCTAssertFalse(store.evolutionChoices(charmander, line: charLine()).isEmpty,
                       "이 테스트는 진화할 곳이 남은 개체를 전제로 한다")
        let host = render(store, partner: charmander, line: charLine())
        XCTAssertGreaterThan(host.fittingSize.height, 0, "진화할 곳이 있다고 카드가 안 뜬다")
    }

    /// **위장 중인 파트너는 카드가 없다.** 상세 화면의 `canTakeFoundEgg`/`isFoundEggCandidate`
    /// 와 같은 술어를 쓰는지 — 이 저장소에서 위장 판정이 실제로 한 번 갈린 적이 있다.
    func testNoCardWhenDisguised() {
        let store = makeStore()
        var ditto = Individual(baseID: 132, speciesID: 132, pathIDs: [132],
                               nature: .hardy, obtainedAt: now, grade: .epic)
        ditto.disguisedAs = 151   // 메타몽이 뮤로 위장 중
        ditto.exp = ExpBalance.eggThreshold(grade: .epic)
        store.addForTesting(ditto)
        store.setPartner(ditto.id)
        let mewLine = EvoLine(baseID: 151, tree: EvoNode(speciesID: 151, children: []),
                              rarity: .legendary, names: [:])
        let host = render(store, partner: ditto, line: mewLine)
        XCTAssertEqual(host.fittingSize.height, 0, "위장 중인데 카드가 뜬다")
    }

    func testCardAppearsWhenReady() {
        let store = makeStore()
        let partner = charizardPartner(store, exp: ExpBalance.eggThreshold(grade: .epic))
        let host = render(store, partner: partner, line: charLine())
        XCTAssertGreaterThan(host.fittingSize.height, 0, "받을 수 있는데 카드가 안 뜬다")
    }

    /// **빈 슬롯이 없어도 카드는 뜬다** — 예전 박스 배지의 결함(슬롯이 차면 안 보임)이 다시
    /// 나면 안 된다. 카드는 뜨되 버튼이 비활성이어야 한다(아래 테스트).
    func testCardStillAppearsWithNoFreeSlot() {
        let store = makeStore()
        let partner = charizardPartner(store, exp: ExpBalance.eggThreshold(grade: .epic))
        for _ in 0..<store.state.slots {
            store.placeEgg(grade: .common, speciesID: 1, shiny: false)
        }
        let host = render(store, partner: partner, line: charLine())
        XCTAssertGreaterThan(host.fittingSize.height, 0,
                             "슬롯이 찼다고 카드가 숨었다 — 숨지 않고 비활성이어야 한다")
    }

    // MARK: 버튼 — 실제로 뜨는지와, 눌렀을 때 진짜로 알을 받는지

    /// 최종형 + 임계 도달 → 버튼이 뜨고 활성이며, **누르면 실제로 알이 슬롯에 들어간다.**
    func testReadyPartnerOffersAnEnabledButtonAndInvokingItPlacesTheEgg() {
        let store = makeStore()
        let partner = charizardPartner(store, exp: ExpBalance.eggThreshold(grade: .epic))
        FoundEggAnnouncementCard.resetConstructed()
        _ = render(store, partner: partner, line: charLine())

        guard let button = FoundEggAnnouncementCard.constructed.first else {
            return XCTFail("받을 수 있는데 버튼이 안 만들어졌다")
        }
        XCTAssertEqual(button.name, "#4", "카드 이름이 파트너의 baseID(파이리) 기준이 아니다")
        XCTAssertTrue(button.canTake, "빈 슬롯이 있는데 비활성으로 기록됐다")

        button.action()
        XCTAssertEqual(store.state.eggs.count, 1, "버튼을 눌렀는데 알이 안 생겼다")
        XCTAssertEqual(store.state.eggs.first?.speciesID, 4)
        // **알 계량기만 0 이 된다.** 경험치(`exp`)는 그대로다 — 두 계량기 분리의 뜻이다.
        XCTAssertEqual(store.state.box.first { $0.id == partner.id }?.eggProgress, 0,
                       "알 계량기가 임계만큼 안 깎였다")
    }

    /// **빈 슬롯이 없으면 버튼은 뜨지만(숨지 않는다) 비활성으로 기록되고, 눌러도 아무 일이 없다.**
    func testNoFreeSlotOffersADisabledButtonAndInvokingItDoesNothing() {
        let store = makeStore()
        let partner = charizardPartner(store, exp: ExpBalance.eggThreshold(grade: .epic))
        for _ in 0..<store.state.slots {
            store.placeEgg(grade: .common, speciesID: 1, shiny: false)
        }
        FoundEggAnnouncementCard.resetConstructed()
        _ = render(store, partner: partner, line: charLine())

        guard let button = FoundEggAnnouncementCard.constructed.first else {
            return XCTFail("슬롯이 찼다고 버튼 자체가 안 만들어졌다 — 숨지 않고 비활성이어야 한다")
        }
        XCTAssertFalse(button.canTake, "슬롯이 꽉 찼는데 활성으로 기록됐다")

        let eggsBefore = store.state.eggs.count
        button.action()
        XCTAssertEqual(store.state.eggs.count, eggsBefore, "비활성이어야 할 버튼을 눌렀는데 알이 생겼다")
        XCTAssertEqual(store.state.box.first { $0.id == partner.id }?.eggProgress,
                       ExpBalance.eggThreshold(grade: .epic),
                       "비활성이어야 할 버튼을 눌렀는데 알 계량기가 깎였다")
    }

    // MARK: 홈 탭 배선 — 실제로 만드는지 (도달성)

    /// [도달성] 컴포넌트 테스트는 이 뷰를 직접 렌더하므로, 홈에서 떼어내도 통과한다
    /// (`DiscoveryCardRenderTests.testTheHomeTabBuildsTheCard` 와 같은 이유). 팝오버를 통째로
    /// 렌더해 홈 탭이 실제로 `FoundEggAnnouncementCard` 를 만드는지 본다.
    ///
    /// **라인이 로드되기 전 상태만 잰다.** 라인은 `provider.line(baseSpeciesID:)` 로 비동기로
    /// 오고, 이 스텁이 실제로 응답을 채워 넣는 시점은 `Task` 스케줄링에 달려 있어 결정적으로
    /// 기다릴 방법이 이 코드베이스에 없다(`TimelineView` 틱과 달리 이 async 로드를 실제 시간으로
    /// 기다리는 패턴이 없다 — `pump()` 는 이 저장소에서 `TimelineView`/GIF 프레임 루프에만 쓰인다).
    /// 그래서 이 테스트는 **body 가 최소 한 번은 평가됐다**(=팝오버가 이 뷰를 실제로 만들었다)만
    /// 확인한다 — "라인이 오기 전엔 아무것도 안 보여준다"(`isReady == false`, 라인이 nil 이므로)
    /// 는 이미 컴포넌트 테스트(`testNoCardWithoutTheLine`)가 순수 판정으로 잠갔다.
    func testTheHomeTabBuildsTheCard() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("found-egg-home-\(UUID().uuidString).json")
        let store = PlayerStore(fileURL: url, rng: SeededRNG(seed: 1), now: { self.now })
        let starter = StarterCatalog.all[0]
        XCTAssertNotNil(store.chooseStarter(speciesID: starter, grade: .common))

        FoundEggAnnouncementCard.resetConstructed()
        let host = NSHostingView(rootView: PopoverView(player: store, provider: StubFoundEggProvider())
            .environment(UsageStore())
            .environment(store)
            .environment(UpdateChecker())
            .environment(PopoverNavigation())
            .frame(width: PopoverMetrics.width))
        host.layoutSubtreeIfNeeded()

        XCTAssertFalse(FoundEggAnnouncementCard.bodyEvaluations.isEmpty,
                       "홈 탭이 알 발견 카드를 안 만든다 — 화면에 닿지 않는 기능이 된다")
    }

    /// 소스 스캔 — 부화 슬롯(`EggSlotsView`)이 조건 분기 안에 있지 않은지에 대한 회귀 가드는
    /// `TimelineBranchGuardTests` 가 이미 잠근다. 여기서는 알림 카드가 그 가드를 깨지 않고
    /// **형제로만** 추가됐는지(= `EggSlotsView(` 생성이 여전히 한 번)를 다시 확인한다.
    func testAddingTheAnnouncementCardDidNotDuplicateTheEggSlotsConstruction() throws {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/PokeDexBar/UI/PopoverView.swift")
        let text = try String(contentsOf: source, encoding: .utf8)
        XCTAssertEqual(text.components(separatedBy: "EggSlotsView(").count - 1, 1,
                       "EggSlotsView 생성이 여러 곳으로 늘었다")
        XCTAssertEqual(text.components(separatedBy: "FoundEggAnnouncementCard(").count - 1, 1,
                       "알림 카드가 홈에 안 붙어 있거나 여러 번 붙어 있다")
    }
}

/// 팝오버를 띄우기만 하면 되므로 네트워크는 아무것도 안 한다 — `DiscoveryTests.StubDiscoveryProvider`
/// 와 같은 역할.
private struct StubFoundEggProvider: PokeProviding {
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: baseSpeciesID, tree: EvoNode(speciesID: baseSpeciesID, children: []),
                rarity: .common, names: [:])
    }
}
