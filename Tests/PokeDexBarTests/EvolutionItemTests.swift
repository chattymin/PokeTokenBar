import XCTest
@testable import PokeDexBar

/// 진화 도구 — **얻는 방법이 곧 분류다**. 여러 종을 여는 돌은 상점에, 한 종만 여는 특수 도구는
/// 리본 파트너가 물어 온다. 20종류를 전부 상점에 늘어놓으면 절반이 한 번 쓰고 마는 품목이다.
final class EvolutionItemCatalogTests: XCTestCase {
    func testEveryItemIsEitherSoldOrForaged() {
        for item in EvolutionItem.allCases {
            let sold = EvolutionItem.shopItems.contains(item)
            let foraged = EvolutionItem.foraged.contains(item)
            XCTAssertNotEqual(sold, foraged, "\(item) 이 양쪽에 있거나 어느 쪽에도 없다")
            XCTAssertEqual(item.isSold, sold)
        }
    }

    /// 상점에는 돌과 연결의 끈만. 특수 도구가 섞여 들어오면 목록이 잡화점이 된다.
    func testShopSellsOnlyStonesAndTheCord() {
        for item in EvolutionItem.shopItems where item != .linkingCord {
            XCTAssertTrue(item.rawValue.hasSuffix("-stone"), "\(item) 은 돌이 아닌데 상점에 있다")
        }
        XCTAssertTrue(EvolutionItem.shopItems.contains(.linkingCord))
    }

    /// 특수 도구는 상점에 없어야 한다 — 리본이 그것들을 얻는 유일한 길이라는 게 설계의 핵심이다.
    func testForagedItemsAreNotBuyable() {
        for item in EvolutionItem.foraged {
            XCTAssertFalse(item.isSold, "\(item) 을 살 수 있으면 리본이 할 일이 없어진다")
        }
        XCTAssertFalse(EvolutionItem.foraged.isEmpty)
    }

    /// PokéAPI 이름으로 찾을 수 있어야 한다 — 못 찾으면 그 진화가 조건 없이 열려 버린다.
    func testLookupByAPIName() {
        XCTAssertEqual(EvolutionItem.named("water-stone"), .waterStone)
        XCTAssertEqual(EvolutionItem.named("black-augurite"), .blackAugurite)
        XCTAssertNil(EvolutionItem.named("rare-candy"))
    }

    /// 연결의 끈은 25종을 혼자 여는 만능이라 돌보다 비싸야 한다.
    func testTheCordCostsMoreThanAStone() {
        XCTAssertGreaterThan(EvolutionItem.linkingCord.price, EvolutionItem.waterStone.price)
    }

    /// 진화는 이 게임의 기본 동작이다 — 도구가 부적보다 비싸면 아무도 못 쓴다.
    func testEvolutionItemsAreCheaperThanCharms() {
        for item in EvolutionItem.shopItems {
            XCTAssertLessThan(item.price, ShopItem.expCharm.price, "\(item) 이 부적보다 비싸다")
        }
    }
}

/// 조건 해석 — PokéAPI 의 `evolution_details` 중 이 앱이 재현할 수 있는 것만 옮긴다.
final class EvoRequirementParsingTests: XCTestCase {
    private func detail(trigger: String? = nil, item: String? = nil,
                        happiness: Int? = nil) -> EvolutionDetail {
        let json = """
        {"trigger":\(trigger.map { "{\"name\":\"\($0)\"}" } ?? "null"),
         "item":\(item.map { "{\"name\":\"\($0)\"}" } ?? "null"),
         "min_happiness":\(happiness.map(String.init) ?? "null")}
        """
        return try! JSONDecoder().decode(EvolutionDetail.self, from: Data(json.utf8))
    }

    func testItemBecomesAnItemRequirement() {
        XCTAssertEqual(PokeAPIClient.requirement(from: [detail(trigger: "use-item", item: "fire-stone")]),
                       .item("fire-stone"))
    }

    /// 통신교환은 도구가 없다 — 이 앱에는 교환 상대가 없으므로 연결의 끈으로 대신한다.
    func testTradeBecomesTheLinkingCord() {
        XCTAssertEqual(PokeAPIClient.requirement(from: [detail(trigger: "trade")]),
                       .item(EvolutionItem.linkingCord.rawValue))
    }

    func testHappinessBecomesFriendship() {
        XCTAssertEqual(PokeAPIClient.requirement(from: [detail(trigger: "level-up", happiness: 160)]),
                       .friendship)
    }

    /// 재현할 수 없는 조건(장소·특정 기술)은 조건 없음이어야 한다 — 막으면 그 종을 영영 못 얻는다.
    func testUnreproducibleConditionsFallThroughToNone() {
        XCTAssertEqual(PokeAPIClient.requirement(from: [detail(trigger: "level-up")]), .none)
        XCTAssertEqual(PokeAPIClient.requirement(from: []), .none)
        XCTAssertEqual(PokeAPIClient.requirement(from: nil), .none)
    }

    /// 모르는 아이템이면 그 조건은 없는 셈 친다 — 카탈로그에 없는 도구를 요구하면 못 넘는 벽이 된다.
    func testUnknownItemDoesNotBlockTheEvolution() {
        XCTAssertEqual(PokeAPIClient.requirement(from: [detail(trigger: "use-item", item: "odd-rock")]),
                       .none)
    }

    /// 여러 건이면 재현 가능한 첫 번째를 쓴다 — 본가도 그중 하나만 만족하면 된다.
    func testPicksTheFirstReproducibleCondition() {
        let details = [detail(trigger: "level-up"), detail(trigger: "use-item", item: "moon-stone")]
        XCTAssertEqual(PokeAPIClient.requirement(from: details), .item("moon-stone"))
    }
}

@MainActor
final class EvolutionGateTests: XCTestCase {
    private var clock = Date(timeIntervalSince1970: 1_000_000)

    private func makeStore() -> PlayerStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("evogate-\(UUID().uuidString).json")
        return PlayerStore(fileURL: url, rng: SeededRNG(seed: 11), now: { self.clock },
                           defaults: UserDefaults(suiteName: "evogate-\(UUID().uuidString)")!)
    }

    /// 조건이 실린 라인 — 1 이 2 가 되려면 `requirement` 가 필요하다.
    private func line(_ requirement: EvoRequirementRaw) -> EvoLine {
        EvoLine(baseID: 1,
                tree: EvoNode(speciesID: 1, children: [
                    EvoNode(speciesID: 2, children: [], requirementRaw: requirement),
                ]),
                rarity: .common, names: [:])
    }

    private func ready(_ store: PlayerStore) -> Individual {
        let individual = Individual(baseID: 1, speciesID: 1, pathIDs: [1], nature: .serious,
                                    exp: 999_000_000, obtainedAt: clock, grade: .common)
        store.addForTesting(individual)
        return individual
    }

    /// 도구가 없으면 못 간다 — 경험치가 넘쳐도.
    func testItemEvolutionIsBlockedWithoutTheItem() {
        let store = makeStore()
        let individual = ready(store)
        XCTAssertFalse(store.evolve(individualID: individual.id, to: 2, line: line(.item("fire-stone"))))
        XCTAssertEqual(store.state.box.first?.speciesID, 1)
    }

    /// 도구가 있으면 가고, **그때 하나 소모된다**.
    func testItemEvolutionConsumesExactlyOne() {
        let store = makeStore()
        let individual = ready(store)
        store.seedForTesting(wallet: EvolutionItem.fireStone.price * 2, slots: 3, eggs: 0, at: clock)
        XCTAssertTrue(store.buy(.fireStone))
        XCTAssertTrue(store.buy(.fireStone))
        XCTAssertTrue(store.evolve(individualID: individual.id, to: 2, line: line(.item("fire-stone"))))
        XCTAssertEqual(store.state.box.first?.speciesID, 2)
        XCTAssertEqual(store.count(of: .fireStone), 1, "정확히 하나만 써야 한다")
    }

    /// 실패한 진화는 도구를 먹지 않는다 — 경험치가 모자란 경우.
    func testAFailedEvolutionKeepsTheItem() {
        let store = makeStore()
        let young = Individual(baseID: 1, speciesID: 1, pathIDs: [1], nature: .serious, exp: 0,
                               obtainedAt: clock, grade: .common)
        store.addForTesting(young)
        store.seedForTesting(wallet: EvolutionItem.fireStone.price, slots: 3, eggs: 0, at: clock)
        XCTAssertTrue(store.buy(.fireStone))
        XCTAssertFalse(store.evolve(individualID: young.id, to: 2, line: line(.item("fire-stone"))))
        XCTAssertEqual(store.count(of: .fireStone), 1, "실패한 진화가 도구를 먹었다")
    }

    /// 친밀도는 **함께한 시간**으로 판단한다 — 리본 1단계와 같은 문턱이라 화면에서 이미 익숙하다.
    func testFriendshipNeedsTimeTogether() {
        let store = makeStore()
        let individual = ready(store)
        store.setPartner(individual.id)
        XCTAssertFalse(store.evolve(individualID: individual.id, to: 2, line: line(.friendship)))
        clock = clock.addingTimeInterval(Double(EvoRequirement.friendshipSeconds) + 60)
        XCTAssertTrue(store.evolve(individualID: individual.id, to: 2, line: line(.friendship)))
    }

    /// 특수 도구는 못 산다 — 리본 파트너가 물어 오는 것이 유일한 경로다.
    func testForagedItemsCannotBeBought() {
        let store = makeStore()
        store.seedForTesting(wallet: 100_000_000_000, slots: 3, eggs: 0, at: clock)
        XCTAssertFalse(store.buy(.blackAugurite))
        XCTAssertEqual(store.count(of: .blackAugurite), 0)
    }

    /// 조건이 없으면 예전처럼 경험치만으로 간다 — 대부분(346종)이 여기 해당한다.
    func testUnconditionalEvolutionStillWorks() {
        let store = makeStore()
        let individual = ready(store)
        XCTAssertTrue(store.evolve(individualID: individual.id, to: 2, line: line(.none)))
    }
}

/// 리본 파트너가 물어 오는 특수 도구.
final class ForageTests: XCTestCase {
    func testNothingBelowTheChance() {
        XCTAssertNil(PlayerStore.forage(ribbon: .bond, roll: 0.99, pick: 0))
    }

    func testBoundaryMatchesTheDeclaredChance() {
        XCTAssertNotNil(PlayerStore.forage(ribbon: .bond, roll: 0.039, pick: 0))
        XCTAssertNil(PlayerStore.forage(ribbon: .bond, roll: 0.040, pick: 0))
    }

    /// 단계가 오를수록 자주 물어 와야 한다 — 뒤집히면 오래 함께한 게 손해가 된다.
    func testHigherRibbonsForageMoreOften() {
        let sorted = Ribbon.allCases.sorted()
        for (lower, higher) in zip(sorted, sorted.dropFirst()) {
            XCTAssertLessThan(lower.foragePermille, higher.foragePermille)
        }
    }

    /// 특수 도구만 나온다 — 상점에서 파는 걸 물어 오면 리본이 상점을 대체해 버린다.
    func testOnlyForagedItemsCanBeFound() {
        for i in 0..<200 {
            let pick = Double(i) / 200
            guard let item = PlayerStore.forage(ribbon: .lifelong, roll: 0, pick: pick) else { continue }
            XCTAssertFalse(item.isSold, "\(item) 은 상점에서 파는 것이다")
        }
    }

    /// pick 이 1.0 이어도 배열 밖으로 나가지 않는다.
    func testPickAtTheTopDoesNotOverflow() {
        XCTAssertNotNil(PlayerStore.forage(ribbon: .lifelong, roll: 0, pick: 1.0))
    }
}

/// [회귀] `EvoLine.init` 은 항상 `keepingSupportedSpecies()` 로 트리를 다시 만든다. 그 재구성이
/// 요구 조건을 안 옮기면 돌·연결의 끈이 필요한 진화가 **조건 없이 열린다** — 실제로 그랬다.
final class EvoTreePruningKeepsRequirementsTests: XCTestCase {
    func testPruningCarriesTheRequirement() {
        let tree = EvoNode(speciesID: 1, children: [
            EvoNode(speciesID: 2, children: [], requirementRaw: .item("fire-stone")),
        ])
        let pruned = tree.keepingSupportedSpecies()
        XCTAssertEqual(pruned?.node(withID: 2)?.requirementRaw, .item("fire-stone"),
                       "가지치기가 요구 조건을 버렸다 — 조건이 필요한 진화가 그냥 열린다")
    }

    /// 라인을 만드는 실제 경로로도 확인한다 — `keepingSupportedSpecies` 만 보면 배선이 빠져도 통과한다.
    func testTheLineKeepsRequirementsToo() {
        let line = EvoLine(baseID: 1,
                           tree: EvoNode(speciesID: 1, children: [
                               EvoNode(speciesID: 2, children: [], requirementRaw: .friendship),
                           ]),
                           rarity: .common, names: [:])
        XCTAssertEqual(line.tree.node(withID: 2)?.requirementRaw, .friendship)
    }
}

/// 상점 진열 — 품목이 자기 분류를 알아야 한다. 뷰가 목록을 손으로 나열하면 새 품목이
/// 어느 칸에도 안 들어가 **팔리지 않는 채로** 조용히 남는다(사탕이 그런 식으로 한 번 새어 나갔다).
final class ShopCategoryTests: XCTestCase {
    /// 모든 품목이 정확히 한 칸에 속한다 — 빠진 품목이 있으면 상점에서 사라진다.
    func testEveryItemLandsInExactlyOneSection() {
        let placed = ShopCategory.allCases.flatMap { c in ShopItem.allCases.filter { $0.category == c } }
        XCTAssertEqual(Set(placed), Set(ShopItem.allCases), "어느 칸에도 없는 품목이 있다")
        XCTAssertEqual(placed.count, ShopItem.allCases.count, "두 칸에 걸친 품목이 있다")
    }

    func testCategoriesGroupWhatBelongsTogether() {
        XCTAssertEqual(ShopItem.expCandy.category, .candy)
        XCTAssertEqual(ShopItem.shinyCandy.category, .candy)
        XCTAssertEqual(ShopItem.megaStone.category, .form)
        XCTAssertEqual(ShopItem.dynamaxMushroom.category, .form)
        for charm in ShopItem.allCases.filter(\.isCharm) {
            XCTAssertEqual(charm.category, .charm, "\(charm) 이 부적 칸에 없다")
        }
    }

    /// 진화 도구는 `ShopItem` 이 아니라 별도 카탈로그다 — 두 목록이 겹치면 같은 것이 두 번 팔린다.
    func testEvolutionItemsAreNotShopItems() {
        let shopKeys = Set(ShopItem.allCases.map(\.rawValue))
        for item in EvolutionItem.allCases {
            XCTAssertFalse(shopKeys.contains(item.rawValue), "\(item) 이 두 목록에 다 있다")
        }
    }

    func testEverySectionHasATitleInEveryLanguage() {
        for category in ShopCategory.allCases {
            for lang in [AppLanguage.ko, .en, .ja] {
                XCTAssertFalse(category.title(lang).isEmpty)
            }
        }
    }
}
