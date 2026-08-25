import XCTest
@testable import PokeDexBar

/// 도감 미션 — 마릿수·세대 완성·전국도감 완성에 보상을 건다.
@MainActor
final class DexMissionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeStore() -> PlayerStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mission-\(UUID().uuidString).json")
        return PlayerStore(fileURL: url, rng: SeededRNG(seed: 1), now: { self.now })
    }

    /// 종 번호들을 도감에 바로 심는다 — 개체를 만들 필요 없이 키만 넣으면 된다.
    private func seedDex(_ store: PlayerStore, species: any Sequence<Int>) {
        store.mutate { s in
            for id in species { s.dexForms.insert(String(id)) }
        }
    }

    // MARK: 카탈로그

    /// **세대 경계가 본가 전국도감 그대로다** — 아홉 세대가 1~1025 를 빈틈도 겹침도 없이 덮는다.
    func testGenerationsTileTheDexExactly() {
        var covered: Set<Int> = []
        for range in DexMissions.generations.values {
            XCTAssertTrue(covered.isDisjoint(with: range), "세대 경계가 겹친다")
            covered.formUnion(range)
        }
        XCTAssertEqual(covered, Set(1...1025), "세대가 도감을 다 못 덮는다")
        // 알려진 경계 몇 개 — 표가 통째로 밀리면 여기서 걸린다.
        XCTAssertEqual(DexMissions.generations[1], 1...151)
        XCTAssertEqual(DexMissions.generations[4], 387...493)
        XCTAssertEqual(DexMissions.generations[9], 906...1025)
    }

    /// **반짝사탕 총량은 2개다.** 상점가 3B 짜리라 미션이 쏟으면 상점의 그 품목이 죽는다 —
    /// 처음에 15개(사다리 6 + 세대마다 1)를 뒀다가 "너무 많이 준다"(사용자 지적)로 걷어냈다.
    /// 어느 방향으로든 잠근다: 다시 불어나도, 0 이 되어 큰 고비 보상이 사라져도 깨진다.
    func testShinyCandyStaysScarce() {
        let total = DexMissions.all.flatMap(\.rewards).reduce(0) { sum, reward in
            if case .item(.shinyCandy, let n) = reward { return sum + n }
            return sum
        }
        // 사다리 2(400·800) + 세대 4(2·4·5·9) = 6. 15개이던 첫 판을 "너무 많다" 로 2까지
        // 걷어냈다가, 세대 보상이 약하다는 후속 판단에서 사용자가 직접 4개를 배정해 6이 됐다.
        XCTAssertEqual(total, 6, "미션 전체의 반짝사탕이 6개가 아니다: \(total)")
        // 세대 완성 = 레전더리 확정권 + 대표 아이템 하나(사용자 배정): 메가스톤은 메가진화
        // 세대들(3·6·7), 다이버섯은 다이맥스·거다이맥스(1·8), 나머지(2·4·5·9)는 반짝사탕.
        for mission in DexMissions.all {
            guard case .generation(let generation) = mission.kind else { continue }
            let signature: DexMissionReward = switch generation {
            case 3, 6, 7: .item(.megaStone, 1)
            case 1, 8: .item(.dynamaxMushroom, 1)
            default: .item(.shinyCandy, 1)
            }
            XCTAssertEqual(mission.rewards, [.eggTicket(.legendary), signature],
                           "\(mission.id) 보상이 배정과 다르다")
        }
    }

    /// 세대 대표 아이템이 실제로 지급된다 — 6세대 완성이 메가스톤을 가방에 담는다.
    func testGenerationSixPaysAMegaStone() throws {
        let store = makeStore()
        let mission = try XCTUnwrap(DexMissions.all.first { $0.id == "gen-6" })
        seedDex(store, species: 650...721)
        XCTAssertTrue(store.claimDexMission(mission))
        XCTAssertEqual(store.count(of: ShopItem.megaStone), 1, "메가스톤이 안 들어왔다")
        XCTAssertEqual(store.count(of: ShopItem.legendaryEggTicket), 1)
    }

    /// 미션 id 는 유일하다 — 수령 기록이 id 로 남으므로 겹치면 하나 받고 둘이 지워진다.
    func testMissionIDsAreUnique() {
        let ids = DexMissions.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
        XCTAssertFalse(DexMissions.all.isEmpty)
    }

    /// 100종·250종은 레전더리 확정권(사용자 지정) — 사다리의 큰 고비들이다. 이로써 사다리의
    /// 확정권은 25종 레어 하나 빼고 전부 레전더리다(100·250·600·1000).
    func testTheBigMilestonesPayLegendaryTickets() throws {
        for id in ["species-100", "species-250", "species-600", "species-1000"] {
            let mission = try XCTUnwrap(DexMissions.all.first { $0.id == id })
            XCTAssertEqual(mission.rewards, [.eggTicket(.legendary)], "\(id) 가 레전더리권이 아니다")
        }
    }

    /// 마릿수 사다리는 오름차순이고 도감 크기를 안 넘는다.
    func testTheSpeciesLadderClimbs() {
        let counts = DexMissions.all.compactMap { mission -> Int? in
            if case .species(let n) = mission.kind { return n }
            return nil
        }
        XCTAssertEqual(counts, counts.sorted(), "사다리가 뒤섞였다")
        XCTAssertTrue(counts.allSatisfy { $0 <= 1025 })
    }

    // MARK: 진행과 수령

    /// 달성 전에는 못 받고, 달성하면 받고, **두 번은 못 받는다.**
    func testClaimOnceAndOnlyWhenAchieved() throws {
        let store = makeStore()
        let mission = try XCTUnwrap(DexMissions.all.first { $0.id == "species-10" })
        XCTAssertFalse(store.claimDexMission(mission), "빈 도감인데 받아진다")

        seedDex(store, species: 1...10)
        XCTAssertTrue(store.canClaimDexMission(mission))
        XCTAssertTrue(store.claimDexMission(mission))
        XCTAssertEqual(store.count(of: ShopItem.expCandy), 3, "보상이 안 들어왔다")

        XCTAssertFalse(store.claimDexMission(mission), "같은 미션을 두 번 받는다")
        XCTAssertEqual(store.count(of: ShopItem.expCandy), 3)
    }

    /// 알 보상은 **확정권**으로 온다 — 수령은 가방에 담고 끝이고, 알은 상점에서 태어난다.
    ///
    /// 알을 그 자리에서 주던 첫 판은 "받기를 눌렀는데 알이 받아졌는지 모르겠다"(사용자 지적)
    /// 가 됐다 — 알은 홈 탭 슬롯에 놓이는데 받기는 도감 탭이라서다. 확정권은 그 어긋남 자체를
    /// 없앤다: 수령엔 슬롯 조건이 없고, 개봉은 항상 상점의 알 뽑기 자리에서 일어난다.
    func testAnEggRewardArrivesAsATicket() throws {
        let store = makeStore()
        let mission = try XCTUnwrap(DexMissions.all.first { $0.id == "species-25" })
        seedDex(store, species: 1...25)
        // 슬롯이 꽉 차 있어도 받는다 — 확정권은 아이템이라 슬롯과 무관하다.
        for i in 0..<3 { store.placeEgg(grade: .common, speciesID: 1 + i, shiny: false) }
        XCTAssertEqual(store.freeSlots, 0)

        XCTAssertTrue(store.claimDexMission(mission))
        XCTAssertEqual(store.count(of: ShopItem.rareEggTicket), 1, "확정권이 가방에 안 담겼다")
        XCTAssertEqual(store.state.eggs.count, 3, "수령이 알을 만들었다 — 확정권이어야 한다")
        XCTAssertTrue(store.state.claimedDexMissions.contains("species-25"))
    }

    /// 확정권 사용 — 등급 확정·무료·한 장 차감. 빈 슬롯이 없으면 실패하고 권은 안 준다.
    func testRedeemingATicketPlacesTheEggAndSpendsOneTicket() {
        let store = makeStore()
        store.mutate { $0.inventory[ShopItem.epicEggTicket.rawValue] = 2 }
        let before = store.state.wallet

        let egg = store.redeemEggTicket(grade: .epic, speciesID: 7)
        XCTAssertEqual(egg?.grade, .epic, "확정 등급이 아니다")
        XCTAssertEqual(store.count(of: ShopItem.epicEggTicket), 1, "한 장이 안 줄었다")
        XCTAssertEqual(store.state.wallet, before, "무료여야 하는데 재화가 줄었다")

        // 슬롯을 다 채우면 실패하고 권은 그대로다.
        while store.freeSlots > 0 { store.placeEgg(grade: .common, speciesID: 1, shiny: false) }
        XCTAssertNil(store.redeemEggTicket(grade: .epic, speciesID: 7))
        XCTAssertEqual(store.count(of: ShopItem.epicEggTicket), 1,
                       "알을 못 놓았는데 확정권이 사라졌다")

        // 없는 등급의 권 — 커먼 확정권은 존재하지 않는다.
        XCTAssertNil(store.redeemEggTicket(grade: .common, speciesID: 1))
    }

    /// 세대 완성 — 그 세대의 전 종이라야 달성이고, 다른 세대 종은 안 낀다.
    func testGenerationCompletionCountsOnlyThatGeneration() throws {
        let store = makeStore()
        let mission = try XCTUnwrap(DexMissions.all.first { $0.id == "gen-1" })
        // 1세대 151종 중 150 + 2세대 몇 종 — 달성이 아니어야 한다.
        seedDex(store, species: 1...150)
        seedDex(store, species: 152...160)
        let status = try XCTUnwrap(store.dexMissionStatuses().first { $0.id == "gen-1" })
        XCTAssertEqual(status.done, 150)
        XCTAssertFalse(status.claimable, "다른 세대 종이 1세대 완성에 낀다")

        seedDex(store, species: [151])
        XCTAssertTrue(store.canClaimDexMission(mission))
    }

    /// 전국도감 완성 → 무지개 부적. **이로치 부적 없이도 받고**, 분모가 32가 된다.
    func testCompletionGrantsTheRainbowCharmWithoutTheShinyCharm() throws {
        let store = makeStore()
        let mission = try XCTUnwrap(DexMissions.all.first { $0.id == "completion" })
        XCTAssertFalse(store.state.ownsShinyCharm, "픽스처가 이미 이로치 부적을 갖고 있다")
        seedDex(store, species: 1...1025)

        XCTAssertTrue(store.claimDexMission(mission))
        XCTAssertTrue(store.state.ownsRainbowCharm)
        XCTAssertTrue(store.owns(ShopItem.rainbowCharm), "가방의 부적 판정이 못 본다")
        XCTAssertEqual(store.shinyDenominator, 32)
    }

    /// 무지개 부적·확정권은 상점에 안 선다 — 미션 전용이다.
    func testMissionOnlyItemsAreNotSold() {
        for item in [ShopItem.rainbowCharm, .rareEggTicket, .epicEggTicket, .legendaryEggTicket] {
            XCTAssertFalse(item.isSold, "\(item) 이 상점에 선다")
            for lang in AppLanguage.allCases {
                XCTAssertFalse(item.label(lang).isEmpty)
                XCTAssertFalse(item.detail(lang).isEmpty)
            }
        }
        XCTAssertTrue(ShopItem.rainbowCharm.isCharm)
        // 확정권은 소모품 — 가방의 소모품 칸에 개수로 선다.
        XCTAssertTrue(ShopItem.epicEggTicket.isConsumable)
        // 팔리는 것들은 그대로 팔린다 — 게이트가 뒤집히면 상점이 통째로 빈다.
        XCTAssertTrue(ShopItem.shinyCharm.isSold)
        XCTAssertTrue(ShopItem.expCandy.isSold)
        // 등급 ↔ 확정권 대응 — 커먼은 없다(커먼 확정에 값이 없다).
        XCTAssertEqual(ShopItem.eggTicket(for: .rare), .rareEggTicket)
        XCTAssertEqual(ShopItem.eggTicket(for: .legendary), .legendaryEggTicket)
        XCTAssertNil(ShopItem.eggTicket(for: .common))
    }

    /// 수령 기록·부적이 저장을 오간다 — 만들고 저장을 빼먹는 부류를 잠근다.
    func testClaimsAndCharmSurviveAReload() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mission-reload-\(UUID().uuidString).json")
        let store = PlayerStore(fileURL: url, rng: SeededRNG(seed: 1), now: { self.now })
        let mission = try XCTUnwrap(DexMissions.all.first { $0.id == "species-10" })
        seedDex(store, species: 1...10)
        XCTAssertTrue(store.claimDexMission(mission))
        store.mutate { $0.ownsRainbowCharm = true }

        let back = PlayerStore(fileURL: url, rng: SeededRNG(seed: 1), now: { self.now })
        XCTAssertTrue(back.state.claimedDexMissions.contains("species-10"),
                      "수령 기록이 저장에서 사라진다 — 재수령 구멍")
        XCTAssertTrue(back.state.ownsRainbowCharm)
    }

    /// 미션 키가 없는 기존 세이브가 그대로 열린다 — 관대 디코딩 규칙.
    func testAnOldSaveWithoutMissionKeysDecodes() throws {
        let json = """
        {"earnedTokens": 5}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(PlayerState.self, from: json)
        XCTAssertTrue(decoded.claimedDexMissions.isEmpty)
        XCTAssertFalse(decoded.ownsRainbowCharm)
    }
}
