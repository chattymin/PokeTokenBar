import XCTest
@testable import PokeDexBar

/// 배틀 상태 폼 — 윽우지(먹이)와 모르페코(배고픔).
@MainActor
final class BattleStateFormTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeStore() -> PlayerStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bsf-\(UUID().uuidString).json")
        return PlayerStore(fileURL: url, rng: SeededRNG(seed: 1), now: { self.now })
    }

    private func cramorant(partner: Bool, stints: Int = 0) -> Individual {
        var made = Individual(baseID: 845, speciesID: 845, pathIDs: [845],
                              nature: .hardy, obtainedAt: now, grade: .rare)
        made.partnerSince = partner ? now : nil
        made.partnerStintsEnded = stints
        return made
    }

    // MARK: 윽우지

    /// **박스에 있는 동안은 절대 물지 않는다** — 사냥은 곁에 데리고 나갈 때의 일이다.
    func testCramorantNeverHoldsPreyWhileInTheBox() {
        for stints in 0..<200 {
            XCTAssertNil(cramorant(partner: false, stints: stints).spriteForm,
                         "박스에 있는데 먹이를 물었다(stints \(stints))")
        }
    }

    /// 곁에 두면 확률로 문다 — 세 모습이 **전부** 나와야 한다(한쪽으로 굳으면 확률이 죽은 것).
    func testCramorantEventuallyShowsAllThreeLooks() {
        var seen: Set<String> = []
        for stints in 0..<400 {
            seen.insert(cramorant(partner: true, stints: stints).spriteForm ?? "cramorant")
        }
        XCTAssertEqual(seen, ["cramorant", "cramorant-gulping", "cramorant-gorging"])
    }

    /// **한 번 곁에 둔 동안에는 안 바뀐다** — 매번 다시 굴리면 입에 든 것이 깜빡인다.
    func testThePreyStaysPutForTheWholeStint() {
        let one = cramorant(partner: true, stints: 3)
        let first = one.spriteForm
        for _ in 0..<50 { XCTAssertEqual(one.spriteForm, first, "같은 구간인데 물고 있는 게 바뀐다") }
    }

    /// 내렸다 다시 올리면(카운터 증가) 새로 굴린다.
    ///
    /// **같은 개체로 구간만 바꾼다** — 처음엔 매번 새 개체를 만들어 비교했는데, 그러면 id 축만으로도
    /// 값이 갈려서 구간 축을 빼도 통과했다(뮤테이션으로 발각). 결정적 굴림은 축마다 따로 물어야 한다.
    func testANewStintRollsAgain() {
        var one = cramorant(partner: true, stints: 0)
        var looks: Set<String> = []
        for stint in 0..<400 {
            one.partnerStintsEnded = stint
            looks.insert(one.spriteForm ?? "-")
        }
        XCTAssertGreaterThan(looks.count, 1, "같은 개체인데 구간이 바뀌어도 늘 같은 것을 물고 있다")
    }

    /// 개체가 다르면 같은 구간이어도 다를 수 있다 — 굴림에 "누구" 축이 들어 있는지(CLAUDE.md).
    func testTwoCramorantsDoNotShareOneRoll() {
        let looks = (0..<200).map { _ in cramorant(partner: true, stints: 0).spriteForm ?? "-" }
        XCTAssertGreaterThan(Set(looks).count, 1, "개체가 달라도 결과가 같다 — id 축이 빠졌다")
    }

    // MARK: 모르페코

    /// 기록이 없으면 배고프지 않다 — 켜자마자 배고픈 모습이면 그게 기본값처럼 보인다.
    func testNoRecordMeansNotHangry() {
        XCTAssertNil(BattleStateForm.activity(lastTokenAt: nil, now: now), "기록이 없으면 어느 쪽도 아니다")
    }

    /// 문턱 경계 — 딱 30분에 배고파진다.
    func testHungerCrossesExactlyAtTheThreshold() {
        let idle = now.addingTimeInterval(-BattleStateForm.idleAfter)
        XCTAssertEqual(BattleStateForm.activity(lastTokenAt: idle, now: now), false)
        let justFed = now.addingTimeInterval(-BattleStateForm.idleAfter + 1)
        XCTAssertEqual(BattleStateForm.activity(lastTokenAt: justFed, now: now), true)
    }

    /// 배고프면 다른 모습, 아니면 기본. **모르페코가 아닌 종은 배고파도 안 바뀐다.**
    func testOnlyMorpekoShowsHunger() {
        var morpeko = Individual(baseID: 877, speciesID: 877, pathIDs: [877],
                                 nature: .hardy, obtainedAt: now, grade: .rare)
        morpeko.recentlyActive = false
        XCTAssertEqual(morpeko.spriteForm, "morpeko-hangry")
        morpeko.recentlyActive = true
        XCTAssertNil(morpeko.spriteForm)

        var pikachu = Individual(baseID: 25, speciesID: 25, pathIDs: [25],
                                 nature: .hardy, obtainedAt: now, grade: .common)
        pikachu.recentlyActive = false
        XCTAssertNil(pikachu.spriteForm, "모르페코가 아닌데 배고픈 모습이 붙었다")
    }

    /// 토큰이 들어오면 배부르고, **델타가 없는 틱에도** 시간이 지나면 배고파진다.
    /// 들어올 때만 갱신하면 배부른 채로 영영 안 바뀐다(정확히 반대로 동작한다).
    func testTheTickFeedsThenLetsItGetHangry() {
        var clock = now
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bsf-tick-\(UUID().uuidString).json")
        let store = PlayerStore(fileURL: url, rng: SeededRNG(seed: 1), now: { clock })
        let morpeko = Individual(baseID: 877, speciesID: 877, pathIDs: [877],
                                 nature: .hardy, obtainedAt: now, grade: .rare)
        store.mutate { s in
            s.box = [morpeko]
            s.partnerID = morpeko.id
            s.installBaselineSet = true
            s.lastDate = "2026-01-01"
        }
        store.update(todayTokens: 1_000, todayDate: "2026-01-01", hasUsageData: true)
        XCTAssertEqual(store.state.box[0].recentlyActive, true, "방금 일했는데 쉬는 중이다")

        // 델타 없이 시간만 흐른 틱 — 여기서 배고파져야 한다.
        clock = now.addingTimeInterval(BattleStateForm.idleAfter + 60)
        store.update(todayTokens: 1_000, todayDate: "2026-01-01", hasUsageData: true)
        XCTAssertEqual(store.state.box[0].recentlyActive, false, "30분이 지났는데 계속 일하는 중이다")

        // 다시 토큰이 들어오면 배부름으로 돌아온다.
        store.update(todayTokens: 2_000, todayDate: "2026-01-01", hasUsageData: true)
        XCTAssertEqual(store.state.box[0].recentlyActive, true, "다시 일했는데 쉬는 상태로 남았다")
    }

    /// 배고픔 키가 없는 기존 세이브가 그대로 열린다(개체가 버려지면 안 된다).
    func testAnOldSaveWithoutHungerDecodes() throws {
        let json = Data(#"{"baseID":877,"speciesID":877,"nature":"hardy","grade":"rare"}"#.utf8)
        let decoded = try JSONDecoder().decode(Individual.self, from: json)
        XCTAssertNil(decoded.recentlyActive)
    }

    /// **도감은 이 모습들을 안 센다** — 상태이지 종이 아니다(메가·깨짐·히어로와 같은 규칙).
    func testTheseStatesNeverSplitTheDex() {
        var cram = cramorant(partner: true, stints: 0)
        cram.partnerSince = now
        XCTAssertEqual(DexKey.key(for: cram), "845")
        var morpeko = Individual(baseID: 877, speciesID: 877, pathIDs: [877],
                                 nature: .hardy, obtainedAt: now, grade: .rare)
        morpeko.recentlyActive = false
        XCTAssertEqual(DexKey.key(for: morpeko), "877")
    }

    // MARK: 킬가르도 — 일하면 칼

    /// **모르페코와 정확히 반대다.** 같은 신호를 반대로 읽으므로, 기록이 없을 때 둘 다
    /// 기본 모습이어야 한다 — 불리언 하나로 접으면 한쪽이 켜자마자 특수 모습이 된다.
    func testAegislashDrawsWhileWorkingAndMorpekoStarvesWhileIdle() {
        func made(_ speciesID: Int, _ active: Bool?) -> Individual {
            var i = Individual(baseID: speciesID, speciesID: speciesID, pathIDs: [speciesID],
                               nature: .hardy, obtainedAt: now, grade: .rare)
            i.recentlyActive = active
            return i
        }
        XCTAssertEqual(made(681, true).spriteForm, "aegislash-blade")
        XCTAssertNil(made(681, false).spriteForm, "쉬는 중인데 칼을 뽑았다")
        XCTAssertEqual(made(877, false).spriteForm, "morpeko-hangry")
        XCTAssertNil(made(877, true).spriteForm, "일하는 중인데 배고픈 모습이다")
        // 기록이 없으면 **둘 다** 기본 모습.
        XCTAssertNil(made(681, nil).spriteForm, "새 세이브인데 칼이 기본이 됐다")
        XCTAssertNil(made(877, nil).spriteForm, "새 세이브인데 배고픔이 기본이 됐다")
    }

    /// 틱이 킬가르도에게도 걸린다 — 모르페코만 갱신하면 칼이 영영 안 나온다.
    func testTheTickAlsoUpdatesAegislash() {
        var clock = now
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bsf-aeg-\(UUID().uuidString).json")
        let store = PlayerStore(fileURL: url, rng: SeededRNG(seed: 1), now: { clock })
        let aegis = Individual(baseID: 679, speciesID: 681, pathIDs: [679, 680, 681],
                               nature: .hardy, obtainedAt: now, grade: .epic)
        store.mutate { s in
            s.box = [aegis]; s.partnerID = aegis.id
            s.installBaselineSet = true; s.lastDate = "2026-01-01"
        }
        store.update(todayTokens: 1_000, todayDate: "2026-01-01", hasUsageData: true)
        XCTAssertEqual(store.state.box[0].recentlyActive, true)
        XCTAssertEqual(store.state.box[0].spriteForm, "aegislash-blade")

        clock = now.addingTimeInterval(BattleStateForm.idleAfter + 60)
        store.update(todayTokens: 1_000, todayDate: "2026-01-01", hasUsageData: true)
        XCTAssertNil(store.state.box[0].spriteForm, "손을 뗐는데 칼을 계속 들고 있다")
    }

    // MARK: 메테노·약어리 — 세 번 두드리기

    /// **메테노는 방향이 반대다.** 평소엔 유성 껍질이고 두드리면 코어(종 기본 그림)가 드러난다 —
    /// 따라큐처럼 다루면 거꾸로 그린다.
    func testMiniorWearsItsShellUntilTapped() {
        var minior = Individual(baseID: 774, speciesID: 774, pathIDs: [774],
                                nature: .hardy, obtainedAt: now, grade: .rare)
        XCTAssertEqual(minior.spriteForm, "minior-meteor", "안 두드렸는데 코어가 드러났다")
        minior.formBroken = true
        XCTAssertNil(minior.spriteForm, "깨졌는데 껍질을 계속 쓰고 있다")
    }

    /// 약어리는 두드리면 무리를 부른다 — 따라큐와 같은 방향.
    func testWishiwashiSchoolsWhenTapped() {
        var fish = Individual(baseID: 746, speciesID: 746, pathIDs: [746],
                              nature: .hardy, obtainedAt: now, grade: .common)
        XCTAssertNil(fish.spriteForm)
        fish.formBroken = true
        XCTAssertEqual(fish.spriteForm, "wishiwashi-school")
    }

    /// **네 종 다 펫을 두드릴 수 있어야 한다** — 탭 경로가 이 술어 하나로 게이트된다.
    /// 표에만 넣고 이걸 안 보면 두드려도 아무 일이 안 난다.
    func testEveryTapReactingSpeciesIsTappable() {
        for speciesID in [778, 875, 746, 774] {
            XCTAssertTrue(BrokenForm.breaks(speciesID: speciesID), "#\(speciesID) 를 두드릴 수 없다")
        }
        XCTAssertFalse(BrokenForm.breaks(speciesID: 25))
        XCTAssertFalse(BrokenForm.breaks(speciesID: nil))
    }

    /// 반응하지 않는 종에 깨짐이 적혀 있으면 경계에서 지운다 — 새 표로도 그대로 동작해야 한다.
    func testABogusBrokenFlagIsStillDropped() {
        var pikachu = Individual(baseID: 25, speciesID: 25, pathIDs: [25],
                                 nature: .hardy, obtainedAt: now, grade: .common)
        pikachu.formBroken = true
        XCTAssertFalse(pikachu.sanitized().formBroken)
        // 반응하는 종은 그대로 둔다(대조군).
        var minior = Individual(baseID: 774, speciesID: 774, pathIDs: [774],
                                nature: .hardy, obtainedAt: now, grade: .rare)
        minior.formBroken = true
        XCTAssertTrue(minior.sanitized().formBroken)
    }

    // MARK: 체리꼬 — 확률로 꽃이 핀다

    /// 박스에서는 안 핀다(윽우지와 같은 규칙), 곁에 두면 확률로 핀다.
    func testCherrimBloomsOnlyBesideYou() {
        func cherrim(partner: Bool, stints: Int) -> Individual {
            var i = Individual(baseID: 420, speciesID: 421, pathIDs: [420, 421],
                               nature: .hardy, obtainedAt: now, grade: .common)
            i.partnerSince = partner ? now : nil
            i.partnerStintsEnded = stints
            return i
        }
        for stints in 0..<200 {
            XCTAssertNil(cherrim(partner: false, stints: stints).spriteForm,
                         "박스에 있는데 꽃이 폈다")
        }
        let looks = (0..<400).map { cherrim(partner: true, stints: $0).spriteForm }
        XCTAssertEqual(Set(looks.map { $0 ?? "-" }), ["-", "cherrim-sunshine"])
        // 20% 언저리여야 한다 — 정확히 20%는 아니지만 절반이나 5% 면 배분이 틀린 것이다.
        let bloomed = looks.count { $0 == "cherrim-sunshine" }
        XCTAssertTrue((40...120).contains(bloomed), "400번 중 \(bloomed)번 폈다 — 20% 배분이 아니다")
    }
}
