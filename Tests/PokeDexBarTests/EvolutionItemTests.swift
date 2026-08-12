import XCTest
@testable import PokeDexBar

/// 진화 도구 41종 — **전부 리본 파트너가 물어 오고, 재화로는 못 산다.** 규칙이 하나여야 한다는
/// 게 요점이다: 돌만 상점에 두면 "똑같이 며칠 걸려 얻었는데 돌만 사라지는" 모순이 생긴다.
final class EvolutionItemCatalogTests: XCTestCase {
    /// **모든 도구가 채집으로 얻어져야 한다.** 상점이 없으므로 표에서 빠진 도구는 영영 못 얻고,
    /// 그 도구를 요구하는 진화는 영영 막힌다 — 이 앱에서 가장 조용히 번지는 결함 유형이다.
    func testEveryItemIsObtainableByForaging() {
        let obtainable = Set(ForageCatalog.bySpecies.values.flatMap { $0 }.map(\.item))
        for item in EvolutionItem.allCases {
            XCTAssertTrue(obtainable.contains(item), "\(item) 을 물어 오는 종이 없다 — 영영 못 얻는다")
        }
    }

    /// 반대 방향 — 표에 있는 도구는 전부 enum 에 있어야 한다(타입이 보장하지만 개수로도 확인).
    func testCatalogAndEnumAgreeOnTheItemSet() {
        let obtainable = Set(ForageCatalog.bySpecies.values.flatMap { $0 }.map(\.item))
        XCTAssertEqual(obtainable.count, EvolutionItem.allCases.count)
    }

    /// 재화로 사는 길이 없어야 한다 — 상점 경로가 되살아나면 리본이 할 일이 없어진다.
    /// `ShopItem` 은 사는 것, `EvolutionItem` 은 모으는 것으로 갈라 둔 게 그 방어다.
    func testEvolutionItemsAreNotShopItems() {
        let shopKeys = Set(ShopItem.allCases.map(\.rawValue))
        for item in EvolutionItem.allCases {
            XCTAssertFalse(shopKeys.contains(item.rawValue),
                           "\(item) 이 상점 품목과 키가 겹친다 — 인벤토리가 한 칸을 두고 다툰다")
        }
    }

    /// PokéAPI 이름으로 찾을 수 있어야 한다 — 못 찾으면 그 진화가 조건 없이 열려 버린다.
    func testLookupByAPIName() {
        XCTAssertEqual(EvolutionItem.named("water-stone"), .waterStone)
        XCTAssertEqual(EvolutionItem.named("black-augurite"), .blackAugurite)
        XCTAssertNil(EvolutionItem.named("rare-candy"))
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
        XCTAssertEqual(PokeAPIClient.requirement(from: [detail(trigger: "use-item", item: "fire-stone")],
                                                 parentLevel: 1),
                       .item("fire-stone"))
    }

    /// 통신교환은 도구가 없다 — 이 앱에는 교환 상대가 없으므로 연결의 끈으로 대신한다.
    func testTradeBecomesTheLinkingCord() {
        XCTAssertEqual(PokeAPIClient.requirement(from: [detail(trigger: "trade")], parentLevel: 1),
                       .item(EvolutionItem.linkingCord.rawValue))
    }

    func testHappinessBecomesFriendship() {
        XCTAssertEqual(PokeAPIClient.requirement(from: [detail(trigger: "level-up", happiness: 160)],
                                                 parentLevel: 1),
                       .friendship)
    }

    /// 재현할 수 없는 조건(장소·특정 기술)은 막다른 벽이 되면 안 된다 — 명시된 레벨이 없으면
    /// `EvoBalance` 규칙(앞 단계 레벨 + 여유분, 하한 20)으로 떨어져 여전히 진화할 길이 남는다.
    func testUnreproducibleConditionsFallBackToALevel() {
        XCTAssertEqual(PokeAPIClient.requirement(from: [detail(trigger: "level-up")], parentLevel: 1),
                       .level(20))
        XCTAssertEqual(PokeAPIClient.requirement(from: [], parentLevel: 1), .none)
        XCTAssertEqual(PokeAPIClient.requirement(from: nil, parentLevel: 1), .none)
    }

    /// 모르는 아이템이면 그 조건은 없는 셈 치고 레벨 규칙으로 떨어진다 — 카탈로그에 없는 도구를
    /// 요구한다고 못 넘는 벽이 되면 안 된다.
    func testUnknownItemFallsBackToALevel() {
        XCTAssertEqual(PokeAPIClient.requirement(from: [detail(trigger: "use-item", item: "odd-rock")],
                                                 parentLevel: 1),
                       .level(20))
    }

    /// 여러 건이면 재현 가능한 첫 번째를 쓴다 — 본가도 그중 하나만 만족하면 된다.
    func testPicksTheFirstReproducibleCondition() {
        let details = [detail(trigger: "level-up"), detail(trigger: "use-item", item: "moon-stone")]
        XCTAssertEqual(PokeAPIClient.requirement(from: details, parentLevel: 1), .item("moon-stone"))
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

    /// 도구가 있으면 간다.
    func testItemEvolutionProceedsWithTheItem() {
        let store = makeStore()
        let individual = ready(store)
        store.grantForTesting(.fireStone)
        XCTAssertTrue(store.evolve(individualID: individual.id, to: 2, line: line(.item("fire-stone"))))
        XCTAssertEqual(store.state.box.first?.speciesID, 2)
    }

    /// 실패한 진화는 도구를 먹지 않는다 — 경험치가 모자란 경우.
    func testAFailedEvolutionKeepsTheItem() {
        let store = makeStore()
        let young = Individual(baseID: 1, speciesID: 1, pathIDs: [1], nature: .serious, exp: 0,
                               obtainedAt: clock, grade: .common)
        store.addForTesting(young)
        store.grantForTesting(.fireStone)
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

    /// 도구는 진화에 써도 남고, **다른 개체에게 다시 쓸 수 있다.** 이게 구조의 핵심이다 —
    /// 없어지면 두 번째 개체를 위해 또 며칠을 기다려야 하고, 그건 사실상 막힌 것과 같다.
    func testItemsSurviveAndWorkOnTheNextIndividual() {
        for item in [EvolutionItem.metalCoat, .fireStone] {
            let store = makeStore()
            let first = ready(store), second = ready(store)
            store.grantForTesting(item)
            let need = line(.item(item.rawValue))
            XCTAssertTrue(store.evolve(individualID: first.id, to: 2, line: need))
            XCTAssertEqual(store.count(of: item), 1, "\(item) 이 없어졌다")
            XCTAssertTrue(store.evolve(individualID: second.id, to: 2, line: need),
                          "\(item) 을 두 번째 개체에 못 쓴다")
        }
    }

    /// 조건이 없으면 예전처럼 경험치만으로 간다 — 대부분(346종)이 여기 해당한다.
    func testUnconditionalEvolutionStillWorks() {
        let store = makeStore()
        let individual = ready(store)
        XCTAssertTrue(store.evolve(individualID: individual.id, to: 2, line: line(.none)))
    }
}

/// 리본 파트너가 **자기에게 필요한** 도구를 물어 온다.
final class ForageTests: XCTestCase {
    /// 마그마그(126)는 마그마부스터 하나만 필요하다 — 갈래가 하나인 대표.
    private let magby: [EvolutionItem] = ForageCatalog.needs(speciesID: 126, region: nil)

    func testNothingBelowTheChance() {
        XCTAssertNil(PlayerStore.forage(ribbon: .bond, needs: magby, roll: 0.99, pick: 0))
    }

    /// 경계는 선언한 확률에서 파생해야 한다 — 숫자를 박아 두면 밸런스를 고칠 때마다
    /// 테스트가 깨지기만 하고 무엇을 지키는지는 알려주지 않는다.
    func testBoundaryMatchesTheDeclaredChance() {
        for ribbon in Ribbon.allCases {
            let inside = Double(ribbon.foragePermille - 1) / 1000
            let outside = Double(ribbon.foragePermille) / 1000
            XCTAssertNotNil(PlayerStore.forage(ribbon: ribbon, needs: magby, roll: inside, pick: 0),
                            "\(ribbon): 선언한 확률 안인데 안 나온다")
            XCTAssertNil(PlayerStore.forage(ribbon: ribbon, needs: magby, roll: outside, pick: 0),
                         "\(ribbon): 선언한 확률 밖인데 나온다")
        }
    }

    /// 단계가 오를수록 자주 물어 와야 한다 — 뒤집히면 오래 함께한 게 손해가 된다.
    func testHigherRibbonsForageMoreOften() {
        let sorted = Ribbon.allCases.sorted()
        for (lower, higher) in zip(sorted, sorted.dropFirst()) {
            XCTAssertLessThan(lower.foragePermille, higher.foragePermille)
        }
    }

    /// 자기가 쓸 것만 나온다. 이게 이 구조의 전부다 — 마그마그가 심해의비늘을 물어 오면
    /// 예전의 무작위 잡화로 돌아간 것이다.
    func testOnlyBringsWhatThisIndividualNeeds() {
        XCTAssertEqual(magby, [.magmarizer])
        for i in 0..<200 {
            let pick = Double(i) / 200
            let item = PlayerStore.forage(ribbon: .lifelong, needs: magby, roll: 0, pick: pick)
            XCTAssertEqual(item, .magmarizer, "pick=\(pick) 에서 엉뚱한 걸 물어 왔다")
        }
    }

    /// 도구가 필요 없는 종은 아무것도 못 물어 온다 — 확률이 아무리 높아도.
    func testSpeciesThatNeedNothingForageNothing() {
        let none = ForageCatalog.needs(speciesID: 1, region: nil)   // 이상해씨는 레벨업 진화
        XCTAssertTrue(none.isEmpty)
        XCTAssertNil(PlayerStore.forage(ribbon: .lifelong, needs: none, roll: 0, pick: 0))
    }

    /// 갈래가 여럿이면 그 중에서만 고른다 — 이브이는 돌이 다섯이다.
    func testMultipleBranchesStayWithinTheSet() {
        let eevee = Set(ForageCatalog.needs(speciesID: 133, region: nil))
        XCTAssertEqual(eevee, [.waterStone, .thunderStone, .fireStone, .leafStone, .iceStone])
        for i in 0..<200 {
            guard let item = PlayerStore.forage(ribbon: .lifelong, needs: Array(eevee),
                                                roll: 0, pick: Double(i) / 200) else {
                return XCTFail("이브이가 아무것도 못 물어 왔다")
            }
            XCTAssertTrue(eevee.contains(item), "\(item) 은 이브이의 갈래가 아니다")
        }
    }

    /// pick 이 1.0 이어도 배열 밖으로 나가지 않는다.
    func testPickAtTheTopDoesNotOverflow() {
        XCTAssertNotNil(PlayerStore.forage(ribbon: .lifelong, needs: magby, roll: 0, pick: 1.0))
    }

    /// **이미 가진 도구는 다시 안 물어 온다.** 도구는 없어지지 않으므로 두 번째는 쓸모가 없고,
    /// 그대로 두면 다 모은 개체의 채집 굴림이 영원히 헛돈다.
    func testAlreadyOwnedItemsAreNotBroughtAgain() {
        XCTAssertNil(PlayerStore.forage(ribbon: .lifelong, needs: magby, owned: [.magmarizer],
                                        roll: 0, pick: 0))
    }

    /// 갈래가 여럿이면 **아직 없는 것 중에서만** 고른다 — 이브이가 돌 넷을 가졌으면 남은 하나.
    func testOnlyMissingBranchesRemainCandidates() {
        let eevee = ForageCatalog.needs(speciesID: 133, region: nil)
        let owned: Set<EvolutionItem> = [.waterStone, .thunderStone, .fireStone, .leafStone]
        for i in 0..<50 {
            XCTAssertEqual(PlayerStore.forage(ribbon: .lifelong, needs: eevee, owned: owned,
                                              roll: 0, pick: Double(i) / 50),
                           .iceStone, "안 가진 하나만 나와야 한다")
        }
    }
}

/// 같은 종이라도 지방에 따라 필요한 도구가 갈리는 10건. `RegionBalance.branchesByRegion` 이
/// *도착 종*이 갈리는 경우를 다루는 것과 짝이다 — 여기는 도착 종이 같고 도구만 갈린다.
final class ForageRegionScopeTests: XCTestCase {
    /// 알로라 식스테일은 얼음의돌, 관동 식스테일은 불꽃의돌. 서로의 것을 물어 오면 안 된다.
    func testVulpixNeedsDifferentStonesByRegion() {
        XCTAssertEqual(ForageCatalog.needs(speciesID: 37, region: nil), [.fireStone])
        XCTAssertEqual(ForageCatalog.needs(speciesID: 37, region: .alola), [.iceStone])
    }

    /// 원종은 도구 없이 레벨업으로 진화하는 쪽 — 관동 모래두지·찌리리공·달막화는 빈손이어야 한다.
    func testOriginalFormsThatEvolveByLevelForageNothing() {
        for (species, region) in [(27, Region.alola), (100, .hisui), (554, .galar)] {
            XCTAssertTrue(ForageCatalog.needs(speciesID: species, region: nil).isEmpty,
                          "#\(species) 원종은 도구가 필요 없는데 물어 온다")
            XCTAssertFalse(ForageCatalog.needs(speciesID: species, region: region).isEmpty,
                           "#\(species) \(region) 는 도구가 필요한데 못 물어 온다")
        }
    }

    /// 가라두구 계열은 가라르 야돈만, 왕의징표석은 관동 야돈만.
    func testSlowpokeBranchesAreRegionExclusive() {
        XCTAssertEqual(ForageCatalog.needs(speciesID: 79, region: nil), [.kingsRock])
        XCTAssertEqual(Set(ForageCatalog.needs(speciesID: 79, region: .galar)),
                       [.galaricaCuff, .galaricaWreath])
    }

    /// 양쪽이 같은 도구를 쓰는 종은 좁히지 않는다 — 히스이 가디도 불꽃의돌로 진화한다.
    func testSharedItemBranchesAreNotNarrowed() {
        XCTAssertEqual(ForageCatalog.needs(speciesID: 58, region: nil), [.fireStone])
        XCTAssertEqual(ForageCatalog.needs(speciesID: 58, region: .hisui), [.fireStone])
    }
}

/// 표 자체가 성립하는가. 채집(`ForageCatalog`)과 진화 게이트(`PokeAPIClient.requirement`)는
/// 같은 PokéAPI 필드에서 나오지만 **인코딩이 둘이다** — 한쪽만 고치면 "쓸 수도 없는 걸 물어
/// 오거나", 반대로 "필요한데 영영 못 얻는" 상태가 된다. 여기서 그 둘을 맞대 본다.
final class ForageCatalogIntegrityTests: XCTestCase {
    /// 표의 모든 갈래는 진화 게이트가 같은 도구를 요구해야 한다. 통신교환은 지닌 물건이
    /// 조건이므로(`trade` + `held_item`) 게이트가 보는 모양 그대로 넣어 확인한다.
    func testEveryEntryMatchesTheEvolutionGate() {
        for (from, needs) in ForageCatalog.bySpecies {
            for need in needs {
                let byItem: EvoRequirementRaw = PokeAPIClient.requirement(from: [
                    EvolutionDetail(trigger: NamedRef(name: "use-item", url: nil),
                                    item: NamedRef(name: need.item.rawValue, url: nil),
                                    held_item: nil, min_happiness: nil, min_level: nil),
                ], parentLevel: 1)
                XCTAssertEqual(byItem, .item(need.item.rawValue),
                               "#\(from) → #\(need.to): 게이트가 \(need.item) 을 못 알아본다")
            }
        }
    }

    /// 갈래가 비어 있는 종을 표에 남기면 "필요한 게 있다"고 잘못 읽힌다.
    func testNoEmptyEntries() {
        for (from, needs) in ForageCatalog.bySpecies {
            XCTAssertFalse(needs.isEmpty, "#\(from) 이 빈 갈래로 남아 있다")
        }
    }

    /// 같은 (도착 종, 도구) 가 두 번 들어가면 그 갈래만 뽑힐 확률이 두 배가 된다 —
    /// PokéAPI 는 지방 변형을 별개 행으로 돌려주므로 생성기에서 걸러야 한다.
    func testNoDuplicateBranches() {
        for (from, needs) in ForageCatalog.bySpecies {
            let keys = needs.map { "\($0.to)-\($0.item.rawValue)" }
            XCTAssertEqual(Set(keys).count, keys.count, "#\(from) 에 같은 갈래가 두 번 있다")
        }
    }

    /// 지방을 좁힌 갈래는 실제로 그 지방 모습이 있는 종이어야 한다.
    func testNarrowedBranchesPointAtRealRegionalForms() {
        for (from, needs) in ForageCatalog.bySpecies {
            for need in needs {
                guard case .only(let region) = need.scope, let region else { continue }
                XCTAssertTrue(RegionalFormCatalog.forms(speciesID: from).contains { $0.region == region },
                              "#\(from) 에 \(region) 모습이 없는데 그 지방 전용 갈래가 있다")
            }
        }
    }
}

/// 상점에 없는 도구는 **얻는 길이 파트너뿐**이라 화면이 그 말을 해야 한다. 안 하면
/// "마그마부스터 필요"에서 끝나 어디서 구하는지 알 수 없고, 진화가 고장난 것처럼 보인다.
///
/// 그 일은 두 곳이 나눠 맡는다: **이름은 갈래 줄**(`shortNeed`), **얻는 방법은 섹션 안내**
/// (`evolutionLockedHint`) 한 줄. 갈래마다 문장을 붙이면 이브이(8갈래)에서 화면을 먹는다.
final class ForagedItemHintTests: XCTestCase {
    func testEachBranchNamesTheItemItWaitsFor() {
        for lang in AppLanguage.allCases {
            // 돌이든 특수 도구든 얻는 길은 하나뿐이므로 표기도 같아야 한다.
            for item in [EvolutionItem.magmarizer, .fireStone, .linkingCord] {
                XCTAssertEqual(IndividualDetailView.shortNeed(.item(item), l: L(lang)),
                               item.label(lang), "\(lang) \(item): 갈래 줄에 이름이 없다")
            }
        }
    }

    /// 안내가 실제로 파트너를 가리키는지 — 한국어에서만 문자열로 확인한다(번역은 빈 문구만).
    func testTheHintPointsAtThePartner() {
        XCTAssertTrue(L(.ko).evolutionLockedHint.contains("파트너"),
                      "도구 안내가 얻는 방법을 안 알려준다: \(L(.ko).evolutionLockedHint)")
        for lang in AppLanguage.allCases {
            XCTAssertFalse(L(lang).evolutionLockedHint.isEmpty, "\(lang): 안내가 비었다")
        }
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

    /// 분류 기준은 **쓰면 없어지는가** 하나다 — 상점과 가방이 같은 칸 이름을 쓰게 하려고
    /// 종류별(사탕·폼)로 나누던 것을 합쳤다. 같은 물건이 화면마다 다른 칸에 있으면 안 된다.
    func testCategoriesFollowWhetherTheItemIsSpent() {
        for item in ShopItem.allCases {
            XCTAssertEqual(item.category, item.isCharm ? .charm : .consumable, "\(item)")
        }
        XCTAssertEqual(ShopItem.expCandy.category, ShopItem.megaStone.category,
                       "사탕과 메가스톤은 둘 다 쓰면 없어진다 — 같은 칸이어야 한다")
    }

    /// 상점과 가방이 **같은 이름**을 써야 한다. 각자 문구를 들고 있으면 다시 갈라진다.
    @MainActor
    func testShopAndBagShareCategoryNames() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cat-\(UUID().uuidString).json")
        let store = PlayerStore(fileURL: url, rng: SeededRNG(seed: 1),
                                now: { Date(timeIntervalSince1970: 0) })
        store.seedForTesting(wallet: 100_000_000_000, slots: 3, eggs: 0,
                             at: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(store.buy(ShopItem.expCandy))
        XCTAssertTrue(store.buy(ShopItem.shinyCharm))
        let titles = Set(BagTabView.sections(store).filter { !$0.rows.isEmpty }.map(\.title))
        XCTAssertTrue(titles.contains(ShopCategory.consumable.title(.ko)), titles.description)
        XCTAssertTrue(titles.contains(ShopCategory.charm.title(.ko)), titles.description)
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

/// 통신교환 — 25종 중 15종은 특정 물건을 들고 교환해야 한다. 연결의 끈 하나로 뭉뚱그리면
/// 금속코트·에레키부스터 같은 것이 게임에서 아예 사라진다(사용자 지적).
final class TradeHeldItemTests: XCTestCase {
    private func tradeDetail(held: String?) -> EvolutionDetail {
        let json = """
        {"trigger":{"name":"trade"},"item":null,
         "held_item":\(held.map { "{\"name\":\"\($0)\"}" } ?? "null"),"min_happiness":null}
        """
        return try! JSONDecoder().decode(EvolutionDetail.self, from: Data(json.utf8))
    }

    func testHeldItemWinsOverTheCord() {
        XCTAssertEqual(PokeAPIClient.requirement(from: [tradeDetail(held: "metal-coat")], parentLevel: 1),
                       .item("metal-coat"))
        XCTAssertEqual(PokeAPIClient.requirement(from: [tradeDetail(held: "electirizer")], parentLevel: 1),
                       .item("electirizer"))
    }

    /// 물건 없이 교환하는 10종만 연결의 끈이 담당한다.
    func testPlainTradeStillUsesTheCord() {
        XCTAssertEqual(PokeAPIClient.requirement(from: [tradeDetail(held: nil)], parentLevel: 1),
                       .item(EvolutionItem.linkingCord.rawValue))
    }

    /// 모르는 물건이면 연결의 끈으로 떨어진다 — 못 넘는 벽을 만들지 않는다.
    func testUnknownHeldItemFallsBackToTheCord() {
        XCTAssertEqual(PokeAPIClient.requirement(from: [tradeDetail(held: "odd-charm")], parentLevel: 1),
                       .item(EvolutionItem.linkingCord.rawValue))
    }

    /// 실제로 쓰이는 13종류가 전부 카탈로그에 있어야 한다 — 하나라도 빠지면 그 진화가
    /// 조건 없이 열리거나(모르는 이름) 연결의 끈으로 뭉뚱그려진다.
    func testEveryTradeHeldItemIsCatalogued() {
        let used = ["metal-coat", "electirizer", "magmarizer", "kings-rock", "dragon-scale",
                    "dubious-disc", "protector", "reaper-cloth", "deep-sea-tooth",
                    "deep-sea-scale", "sachet", "whipped-dream", "up-grade"]
        let obtainable = Set(ForageCatalog.bySpecies.values.flatMap { $0 }.map(\.item))
        for name in used {
            guard let item = EvolutionItem.named(name) else {
                return XCTFail("\(name) 이 카탈로그에 없다")
            }
            XCTAssertTrue(obtainable.contains(item), "\(name) 을 물어 오는 종이 없다")
        }
    }
}
