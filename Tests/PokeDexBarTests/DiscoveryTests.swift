import AppKit
import SwiftUI
import XCTest
@testable import PokeDexBar

/// 발견 알림 — 파트너가 물어 온 것을 알려 주되 **흐름은 막지 않는다**. 이게 알(부화)과 갈리는
/// 지점이다: 알은 벽시계로 익고 채집은 토큰으로 돌기 때문에, 확인을 문턱으로 두면 하루 종일
/// 일하고 저녁에 앱을 연 사용자가 실제로 일한 만큼을 못 받는다.
@MainActor
final class DiscoveryTests: XCTestCase {
    private var clock = Date(timeIntervalSince1970: 1_000_000)

    private func makeStore(_ species: Int) -> (PlayerStore, UUID) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("discovery-\(UUID().uuidString).json")
        let store = PlayerStore(fileURL: url, rng: SeededRNG(seed: 6), now: { self.clock },
                                defaults: UserDefaults(suiteName: "disc-\(UUID().uuidString)")!)
        let i = Individual(baseID: species, speciesID: species, pathIDs: [species],
                           nature: .serious, obtainedAt: clock, grade: .common)
        store.addForTesting(i)
        store.setPartner(i.id)
        store.update(todayTokens: 0, todayDate: "2026-01-01", hasUsageData: true)
        return (store, i.id)
    }

    /// 물어 오면 알림이 쌓인다 — 그리고 도구는 **그 즉시** 가방에 들어가 있다.
    func testForagingRecordsADiscoveryAndTheItemIsAlreadyOwned() {
        let (store, _) = makeStore(133)                  // 이브이 — 돌이 다섯이라 금방 걸린다
        clock = clock.addingTimeInterval(95 * 86_400)    // 반려 리본
        store.update(todayTokens: Ribbon.lifelong.tokensPerCandy * 40, todayDate: "2026-01-01",
                     hasUsageData: true)
        let finds = store.pendingDiscoveries
        XCTAssertFalse(finds.isEmpty, "물어 온 게 하나도 기록되지 않았다")
        for find in finds {
            XCTAssertEqual(find.speciesID, 133)
            let owned = EvolutionItem.named(find.itemKey).map { store.count(of: $0) > 0 }
                ?? FormItem.named(find.itemKey).map { store.count(of: $0) > 0 } ?? false
            XCTAssertTrue(owned, "\(find.itemKey) 이 알림에는 있는데 가방에 없다")
        }
    }

    /// **확인은 다음 채집을 막지 않는다.** 확인 안 한 채로 계속 써도 계속 물어 온다 —
    /// 이걸 막으면 앱을 자주 여는 쪽에 보상이 가고, 리본이 세운 축이 뒤집힌다.
    func testUnacknowledgedDiscoveriesDoNotStopForaging() {
        // 아르세우스 — 플레이트가 17장이라 한 번에 다 못 모은다(이브이는 다섯이라 금방 동나서
        // "멈췄다"와 "더 찾을 게 없다"를 구분하지 못한다).
        let (store, _) = makeStore(493)
        clock = clock.addingTimeInterval(95 * 86_400)
        store.update(todayTokens: Ribbon.lifelong.tokensPerCandy * 4, todayDate: "2026-01-01",
                     hasUsageData: true)
        let first = store.pendingDiscoveries.count
        XCTAssertGreaterThan(first, 0)
        XCTAssertLessThan(first, FormItem.allCases.filter { $0.rawValue.hasPrefix("form-plate") }.count,
                          "한 번에 다 모아 버리면 이 테스트가 아무것도 안 지킨다")
        // 확인하지 않은 채로 계속 쓴다.
        store.update(todayTokens: Ribbon.lifelong.tokensPerCandy * 40, todayDate: "2026-01-01",
                     hasUsageData: true)
        XCTAssertGreaterThan(store.pendingDiscoveries.count, first,
                             "확인을 안 했다고 채집이 멈췄다")
    }

    /// 확인하면 알림만 사라지고 **도구는 그대로 남는다** — 알림은 알림일 뿐이다.
    func testAcknowledgingClearsTheNoticeButKeepsTheItems() {
        let (store, _) = makeStore(133)
        clock = clock.addingTimeInterval(95 * 86_400)
        store.update(todayTokens: Ribbon.lifelong.tokensPerCandy * 40, todayDate: "2026-01-01",
                     hasUsageData: true)
        let stones: [EvolutionItem] = [.waterStone, .thunderStone, .fireStone, .leafStone, .iceStone]
        let ownedBefore = stones.filter { store.count(of: $0) > 0 }
        XCTAssertFalse(ownedBefore.isEmpty)

        store.acknowledgeDiscoveries()
        XCTAssertTrue(store.pendingDiscoveries.isEmpty)
        XCTAssertEqual(stones.filter { store.count(of: $0) > 0 }, ownedBefore, "확인했더니 도구가 사라졌다")
    }

    /// 아무것도 없을 때 확인해도 아무 일 없다.
    func testAcknowledgingNothingIsHarmless() {
        let (store, _) = makeStore(1)
        store.acknowledgeDiscoveries()
        XCTAssertTrue(store.pendingDiscoveries.isEmpty)
    }
}

/// 카드 문구 — 뷰에서 떼어 낸 순수 함수라 그대로 잠근다.
final class DiscoveryCardCopyTests: XCTestCase {
    private func find(_ key: String, _ species: Int) -> Discovery {
        Discovery(itemKey: key, speciesID: species)
    }

    /// 한 마리가 물어 왔으면 그 이름을 부른다.
    func testHeadlineNamesTheFinderWhenThereIsOne() {
        let finds = [find("fire-stone", 25), find("form-costume-trunk", 25)]
        let text = DiscoveryCard.headline(finds, l: L(.ko)) { _ in "피카츄" }
        XCTAssertTrue(text.contains("피카츄"), text)
        XCTAssertTrue(text.contains("2"), text)
    }

    /// 이름을 아직 못 받았으면 #번호로 — 빈칸을 남기지 않는다.
    func testHeadlineFallsBackToTheDexNumber() {
        let text = DiscoveryCard.headline([find("fire-stone", 25)], l: L(.ko)) { _ in nil }
        XCTAssertTrue(text.contains("#25"), text)
    }

    /// 여러 파트너가 물어 왔으면 마리 수로 — 며칠 안 열어 보고 파트너를 바꾼 경우다.
    func testHeadlineCountsSpeciesWhenThereAreSeveral() {
        let finds = [find("fire-stone", 25), find("metal-coat", 133)]
        let text = DiscoveryCard.headline(finds, l: L(.ko)) { _ in "이름" }
        XCTAssertTrue(text.contains("2"), text)
    }

    /// 진화 도구와 폼 도구를 **둘 다** 이름으로 풀 수 있어야 한다 — 한쪽만 알면 나머지는
    /// 카드에서 조용히 사라진다.
    func testNamesResolveBothItemFamilies() {
        let finds = [find(EvolutionItem.fireStone.rawValue, 25),
                     find(FormItem.costumeTrunk.rawValue, 25)]
        let names = DiscoveryCard.names(finds, l: L(.ko))
        XCTAssertEqual(names, [EvolutionItem.fireStone.label(.ko), FormItem.costumeTrunk.label(.ko)])
    }

    /// 못 알아보는 키는 뺀다 — 빈 줄이 남으면 뭘 얻었는지 더 헷갈린다.
    func testUnknownKeysAreDropped() {
        XCTAssertTrue(DiscoveryCard.names([find("who-knows", 1)], l: L(.ko)).isEmpty)
    }

    func testCopyIsLocalized() {
        let texts = [AppLanguage.ko, .en, .ja].map { L($0).discoveryAcknowledge }
        XCTAssertEqual(Set(texts).count, 3, texts.description)
        XCTAssertFalse(texts.contains { $0.isEmpty })
    }
}

/// 세이브 — 알림은 저장돼야 한다(앱을 껐다 켜도 "물어 왔어요"가 남아 있어야 한다).
/// 그리고 **필드를 더해도 옛 세이브의 박스가 날아가면 안 된다** — 이 저장소가 두 번 밟은 자리다.
@MainActor
final class DiscoveryPersistenceTests: XCTestCase {
    func testDiscoveriesSurviveAReload() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("disc-save-\(UUID().uuidString).json")
        let defaults = UserDefaults(suiteName: "disc-save-\(UUID().uuidString)")!
        let store = PlayerStore(fileURL: url, rng: SeededRNG(seed: 1),
                                now: { Date(timeIntervalSince1970: 0) }, defaults: defaults)
        let i = Individual(baseID: 133, speciesID: 133, pathIDs: [133], nature: .serious,
                           obtainedAt: Date(timeIntervalSince1970: 0), grade: .common)
        store.addForTesting(i)
        store.setPartner(i.id)
        store.update(todayTokens: 0, todayDate: "2026-01-01", hasUsageData: true)

        let reopened = PlayerStore(fileURL: url, rng: SeededRNG(seed: 1),
                                   now: { Date(timeIntervalSince1970: 0) }, defaults: defaults)
        XCTAssertEqual(reopened.state.box.count, 1, "필드를 더했더니 박스가 날아갔다")
    }

    /// `discoveries` 키가 아예 없는 옛 세이브도 박스를 지켜야 한다.
    func testALegacySaveWithoutTheFieldStillLoadsTheBox() throws {
        let json = """
        {"starterChosen":true,"earnedTokens":100,"spentTokens":0,"slots":3,
         "box":[{"id":"\(UUID().uuidString)","baseID":25,"speciesID":25,"pathIDs":[25],
                 "nature":"serious","grade":"common","obtainedAt":0}],
         "dex":[25],"inventory":{}}
        """
        let state = try JSONDecoder().decode(PlayerState.self, from: Data(json.utf8))
        XCTAssertEqual(state.box.count, 1, "새 필드가 없다고 박스를 날렸다")
        XCTAssertTrue(state.discoveries.isEmpty)
    }
}

/// [도달성] 카드가 **실제 뷰로** 그려지는지. 스토어만 잠그면 홈이 카드를 안 그려도 통과한다 —
/// 이 저장소가 반복해서 밟은 "기능은 있는데 화면이 없다"의 형태다.
@MainActor
final class DiscoveryCardRenderTests: XCTestCase {
    private func makeStore(with finds: [Discovery]) -> PlayerStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("disc-render-\(UUID().uuidString).json")
        let store = PlayerStore(fileURL: url, rng: SeededRNG(seed: 1),
                                now: { Date(timeIntervalSince1970: 0) })
        let i = Individual(baseID: 25, speciesID: 25, pathIDs: [25], nature: .serious,
                           obtainedAt: Date(timeIntervalSince1970: 0), grade: .common)
        store.addForTesting(i)
        store.setPartner(i.id)
        for find in finds { store.grantDiscoveryForTesting(find) }
        return store
    }

    private func render(_ store: PlayerStore) -> NSView {
        let host = NSHostingView(rootView: DiscoveryCard(store: store) { _ in "피카츄" }
            .frame(width: PopoverMetrics.contentWidth))
        host.layoutSubtreeIfNeeded()
        return host
    }

    /// 발견이 없으면 카드가 아예 안 그려진다 — 빈 카드가 홈에 상주하면 안 된다.
    func testNoCardWithoutDiscoveries() {
        let host = render(makeStore(with: []))
        XCTAssertEqual(host.fittingSize.height, 0, "발견이 없는데 카드가 자리를 차지한다")
    }

    /// 발견이 있으면 카드가 자리를 차지한다.
    func testCardAppearsWithDiscoveries() {
        let host = render(makeStore(with: [Discovery(itemKey: EvolutionItem.thunderStone.rawValue,
                                                     speciesID: 25)]))
        XCTAssertGreaterThan(host.fittingSize.height, 0, "발견이 있는데 카드가 안 그려진다")
    }

    /// **홈 탭이 실제로 카드를 품고 있나.** 위 두 테스트는 카드 자체만 그려 보므로, 홈에서
    /// 떼어내도 통과한다(실측으로 확인했다). 그래서 팝오버를 통째로 렌더해 그 안에서 카드가
    /// 만들어지는지를 본다 — 이 저장소가 반복해서 밟은 결함이 정확히 이 형태다.
    func testTheHomeTabBuildsTheCard() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("disc-home-\(UUID().uuidString).json")
        let store = PlayerStore(fileURL: url, rng: SeededRNG(seed: 1),
                                now: { Date(timeIntervalSince1970: 0) })
        // 스타터를 안 고르면 팝오버가 홈이 아니라 스타터 픽커를 낸다 — 카드가 안 나오는 게 맞다.
        let starter = StarterCatalog.all[0]
        XCTAssertNotNil(store.chooseStarter(speciesID: starter, grade: .common))
        store.grantDiscoveryForTesting(Discovery(itemKey: EvolutionItem.thunderStone.rawValue,
                                                 speciesID: starter))
        DiscoveryCard.resetConstructed()
        let host = NSHostingView(rootView: PopoverView(player: store, provider: StubDiscoveryProvider())
            .environment(UsageStore())
            .environment(store)
            .environment(UpdateChecker())
            .environment(PopoverNavigation())
            .frame(width: PopoverMetrics.width))
        host.layoutSubtreeIfNeeded()
        XCTAssertFalse(DiscoveryCard.constructed.isEmpty,
                       "홈 탭이 발견 카드를 안 만든다 — 화면에 닿지 않는 기능이 된다")
    }
}

/// 팝오버를 띄우기만 하면 되므로 네트워크는 아무것도 안 한다.
private struct StubDiscoveryProvider: PokeProviding {
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: baseSpeciesID, tree: EvoNode(speciesID: baseSpeciesID, children: []),
                rarity: .common, names: [:])
    }
}
