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

    /// 미션 id 는 유일하다 — 수령 기록이 id 로 남으므로 겹치면 하나 받고 둘이 지워진다.
    func testMissionIDsAreUnique() {
        let ids = DexMissions.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
        XCTAssertFalse(DexMissions.all.isEmpty)
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

    /// 알 보상 — 종 수가 안 맞으면 실패, 맞으면 슬롯에 알이 놓이고 수령 처리된다.
    func testAnEggRewardLandsInAHatchSlot() throws {
        let store = makeStore()
        let mission = try XCTUnwrap(DexMissions.all.first { $0.id == "species-25" })
        seedDex(store, species: 1...25)

        XCTAssertFalse(store.claimDexMission(mission), "알 종 없이 받아진다")
        XCTAssertTrue(store.claimDexMission(mission, eggSpecies: [(7, .mediumFast)]))
        XCTAssertEqual(store.state.eggs.count, 1, "알이 슬롯에 안 놓였다")
        XCTAssertEqual(store.state.eggs.first?.grade, .rare, "보상 등급과 알 등급이 다르다")
        XCTAssertTrue(store.state.claimedDexMissions.contains("species-25"))
    }

    /// **알 보상은 빈 슬롯이 있어야 받는다** — 꽉 찼으면 판정부터 막힌다.
    func testAnEggRewardNeedsAFreeSlot() throws {
        let store = makeStore()
        let mission = try XCTUnwrap(DexMissions.all.first { $0.id == "species-25" })
        seedDex(store, species: 1...25)
        // 기본 3슬롯을 다 채운다.
        for i in 0..<3 { store.placeEgg(grade: .common, speciesID: 1 + i, shiny: false) }
        XCTAssertEqual(store.freeSlots, 0)

        XCTAssertFalse(store.canClaimDexMission(mission))
        XCTAssertFalse(store.claimDexMission(mission, eggSpecies: [(7, .mediumFast)]))
        XCTAssertFalse(store.state.claimedDexMissions.contains("species-25"),
                       "못 받았는데 수령 처리됐다")
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

    /// 무지개 부적은 상점에 안 선다 — 미션 전용이다.
    func testTheRainbowCharmIsNotSold() {
        XCTAssertFalse(ShopItem.rainbowCharm.isSold)
        XCTAssertTrue(ShopItem.rainbowCharm.isCharm)
        // 팔리는 것들은 그대로 팔린다 — 게이트가 뒤집히면 상점이 통째로 빈다.
        XCTAssertTrue(ShopItem.shinyCharm.isSold)
        for lang in AppLanguage.allCases {
            XCTAssertFalse(ShopItem.rainbowCharm.label(lang).isEmpty)
            XCTAssertFalse(ShopItem.rainbowCharm.detail(lang).isEmpty)
        }
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
