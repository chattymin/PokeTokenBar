import XCTest
@testable import PokeDexBar

/// 컬렉션 — 주제별 수집 세트. 배지는 도감에서 파생되고, 보상 수령이 세트마다 한 번 있다.
@MainActor
final class CollectionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeStore() -> PlayerStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("coll-\(UUID().uuidString).json")
        return PlayerStore(fileURL: url, rng: SeededRNG(seed: 1), now: { self.now })
    }

    private func seedDex(_ store: PlayerStore, species: any Sequence<Int>) {
        store.mutate { s in
            for id in species { s.dexForms.insert(String(id)) }
        }
    }

    // MARK: 카탈로그

    /// id·구성원이 성하다 — id 유일, 종 번호는 도감 범위 안, 세트 안 중복 없음.
    func testTheCatalogIsSound() {
        let ids = CollectionCatalog.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "세트 id 가 겹친다")
        for entry in CollectionCatalog.all {
            XCTAssertFalse(entry.speciesIDs.isEmpty, "\(entry.id) 가 비었다")
            XCTAssertEqual(entry.speciesIDs.count, Set(entry.speciesIDs).count,
                           "\(entry.id) 안에 같은 종이 두 번 있다")
            XCTAssertTrue(entry.speciesIDs.allSatisfy { (1...1025).contains($0) },
                          "\(entry.id) 에 도감 밖 번호가 있다")
            // 모든 세트가 뭔가를 준다(사용자 결정 — "경험치 사탕이라도"). 빈 배열이면
            // 받기 버튼이 눌리는데 아무 일도 안 일어난다.
            XCTAssertFalse(entry.rewards.isEmpty, "\(entry.id) 의 보상이 비었다")
            for lang in AppLanguage.allCases {
                XCTAssertNotEqual(CollectionCatalog.label(entry.id, lang), entry.id,
                                  "\(entry.id) 의 \(lang) 이름이 없다")
            }
        }
    }

    /// **반짝사탕은 컬렉션 보상에 못 온다.** 미션 쪽 희소성 가드(총 6개)와 별개 경로로
    /// 새면 그 가드가 장식이 된다.
    func testNoShinyCandyLeaksThroughCollections() {
        for entry in CollectionCatalog.all {
            for reward in entry.rewards {
                if case .item(.shinyCandy, _) = reward {
                    XCTFail("\(entry.id) 가 반짝사탕을 준다 — 희소성 가드를 우회한다")
                }
            }
        }
    }

    /// 알려진 세트 몇 개 — 전승 구성을 잠근다(표가 밀리면 여기서 걸린다).
    func testKnownSetsMatchTheLore() throws {
        let clone = try XCTUnwrap(CollectionCatalog.all.first { $0.id == "clone-truth" })
        XCTAssertEqual(Set(clone.speciesIDs), [132, 150, 151], "뮤·뮤츠·메타몽이어야 한다")
        let eevee = try XCTUnwrap(CollectionCatalog.all.first { $0.id == "eevee-friends" })
        XCTAssertEqual(eevee.speciesIDs.count, 9, "이브이 + 진화형 8종이어야 한다")
        XCTAssertTrue(eevee.speciesIDs.contains(700), "님피아가 빠졌다")
        let ub = try XCTUnwrap(CollectionCatalog.all.first { $0.id == "ultra-beasts" })
        XCTAssertEqual(ub.speciesIDs.count, 11)
        // 화석 — 여섯 세대 25종(복원 라인 포함). 세대를 하나 빼먹으면 여기서 걸린다.
        let fossils = try XCTUnwrap(CollectionCatalog.all.first { $0.id == "fossils" })
        XCTAssertEqual(fossils.speciesIDs.count, 25)
        XCTAssertTrue(fossils.speciesIDs.contains(142), "프테라가 빠졌다")
        XCTAssertTrue(fossils.speciesIDs.contains(880), "8세대 화석이 빠졌다")
        // 600족 — 최종 진화형만. 미뇽(147)이 들어오면 이름이 거짓말이 된다.
        let pseudo = try XCTUnwrap(CollectionCatalog.all.first { $0.id == "pseudo-legendaries" })
        XCTAssertEqual(pseudo.speciesIDs.count, 10)
        XCTAssertTrue(pseudo.speciesIDs.contains(149))
        XCTAssertFalse(pseudo.speciesIDs.contains(147), "600족에 미진화형이 들어왔다")
        // 파라독스 — 고대와 미래는 겹치지 않는다(본가 구분 그대로).
        let past = try XCTUnwrap(CollectionCatalog.all.first { $0.id == "paradox-past" })
        let future = try XCTUnwrap(CollectionCatalog.all.first { $0.id == "paradox-future" })
        XCTAssertEqual(past.speciesIDs.count, 10)
        XCTAssertEqual(future.speciesIDs.count, 10)
        XCTAssertTrue(Set(past.speciesIDs).isDisjoint(with: future.speciesIDs),
                      "고대와 미래가 겹친다")
        XCTAssertTrue(future.speciesIDs.contains(1006), "테츠노브지나(미래)가 빠졌다")
    }

    // MARK: 진행과 배지

    /// 배지는 도감에서 파생된다 — 수령 없이 완성 즉시 켜진다. 보상(사탕)은 따로 한 번 받는다.
    func testTheBadgeDerivesFromTheDex() {
        let store = makeStore()
        seedDex(store, species: [144, 145])
        var status = store.collectionStatuses().first { $0.id == "legendary-birds" }!
        XCTAssertEqual(status.done, 2)
        XCTAssertFalse(status.completed)
        XCTAssertFalse(store.canClaimCollection(status.collection), "다 안 모았는데 받아진다")

        seedDex(store, species: [146])
        status = store.collectionStatuses().first { $0.id == "legendary-birds" }!
        XCTAssertTrue(status.completed)
        // 전승 세트도 이제 보상이 있다(사용자 결정) — 완성 즉시 받을 수 있어야 한다.
        XCTAssertTrue(status.claimable)
        XCTAssertTrue(store.claimCollection(status.collection))
        XCTAssertEqual(store.count(of: .expCandy), 20, "전승 세트의 사탕이 안 들어왔다")
    }

    /// 확정권을 주는 세트 — 완성 전엔 못 받고, 받으면 가방에 담기고, 두 번은 못 받는다.
    func testARewardSetClaimsOnceIntoTheBag() throws {
        let store = makeStore()
        let beasts = try XCTUnwrap(CollectionCatalog.all.first { $0.id == "ultra-beasts" })
        seedDex(store, species: beasts.speciesIDs.dropLast())
        XCTAssertFalse(store.claimCollection(beasts), "다 안 모았는데 받아진다")

        seedDex(store, species: beasts.speciesIDs)
        XCTAssertTrue(store.claimCollection(beasts))
        XCTAssertEqual(store.count(of: ShopItem.legendaryEggTicket), 1, "확정권이 안 들어왔다")
        XCTAssertFalse(store.claimCollection(beasts), "같은 세트를 두 번 받는다")
        XCTAssertEqual(store.count(of: ShopItem.legendaryEggTicket), 1)
    }

    /// 레지 패밀리 — 다섯 기둥을 모으면 **레지기가스가 깨어나** 박스와 도감에 합류한다.
    /// 알에서는 안 나오는 종이라(`EggBalance.rewardOnlySpecies`) 이 경로가 유일한 입수처다.
    func testTheRegiFamilyAwakensRegigigas() throws {
        let store = makeStore()
        let regis = try XCTUnwrap(CollectionCatalog.all.first { $0.id == "regi-family" })
        // 레지기가스(486)는 구성원이 아니라 **보상**이다 — 구성원이면 완성이 불가능해진다.
        XCTAssertEqual(Set(regis.speciesIDs), [377, 378, 379, 894, 895])
        seedDex(store, species: [377, 378, 379, 894])
        XCTAssertFalse(store.claimCollection(regis), "다 안 모았는데 깨어난다")

        seedDex(store, species: [895])
        XCTAssertTrue(store.claimCollection(regis))
        let gigas = try XCTUnwrap(store.state.box.first { $0.speciesID == 486 },
                                  "레지기가스가 박스에 없다")
        XCTAssertEqual(gigas.grade, .legendary)
        XCTAssertEqual(gigas.growthRate, .slow)
        XCTAssertTrue(store.state.dex.contains(486), "도감에 등록이 안 됐다")
        XCTAssertFalse(store.claimCollection(regis), "두 번 깨어난다")
        XCTAssertEqual(store.state.box.count(where: { $0.speciesID == 486 }), 1)
    }

    /// 수령 기록이 저장을 오간다.
    func testClaimsSurviveAReload() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("coll-reload-\(UUID().uuidString).json")
        let store = PlayerStore(fileURL: url, rng: SeededRNG(seed: 1), now: { self.now })
        let eevee = try XCTUnwrap(CollectionCatalog.all.first { $0.id == "eevee-friends" })
        seedDex(store, species: eevee.speciesIDs)
        XCTAssertTrue(store.claimCollection(eevee))

        let back = PlayerStore(fileURL: url, rng: SeededRNG(seed: 1), now: { self.now })
        XCTAssertTrue(back.state.claimedCollections.contains("eevee-friends"),
                      "수령 기록이 저장에서 사라진다 — 재수령 구멍")
    }

    /// 컬렉션 키가 없는 기존 세이브가 그대로 열린다.
    func testAnOldSaveWithoutTheKeyDecodes() throws {
        let json = """
        {"earnedTokens": 5}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(PlayerState.self, from: json)
        XCTAssertTrue(decoded.claimedCollections.isEmpty)
    }
}
