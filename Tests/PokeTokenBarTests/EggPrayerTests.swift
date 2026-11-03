import XCTest
@testable import PokeTokenBar

// MARK: 알 기도하기 (위약 버튼) — 세는 것 말고는 아무것도 바꾸지 않는다.

private struct PrayerOfflineProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

@MainActor
final class EggPrayerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let line = EvoLine(
        baseID: 1,
        tree: EvoNode(speciesID: 1, children: [EvoNode(speciesID: 2, children: [EvoNode(speciesID: 3, children: [])])]),
        rarity: .common,
        names: [1: ["en": "P1"], 2: ["en": "P2"], 3: ["en": "P3"]])

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("prayer-\(UUID().uuidString).json")
    }

    /// Egg at the hatch threshold; `pending` = species already rolled (the prefetched case).
    private func hatchReadyEgg(seed: UInt64 = 7, pending: Bool,
                               provider: (any PokeProviding)? = nil) -> CompanionStore {
        let url = tempURL()
        let json = "{\"installBaselineSet\":true,\"usedSinceInstall\":10000000,\"spentTokens\":0,"
            + "\"lastDate\":\"d\",\"active\":null,\"dex\":[],\"collectedFinals\":[],"
            + "\"eggUsage\":\(PokemonBalance.eggHatchThreshold)"
            + (pending ? ",\"pendingHatchID\":1" : "") + "}"
        try? json.data(using: .utf8)!.write(to: url)
        return CompanionStore(provider: provider ?? StubProvider(value: line), clock: { self.now },
                              fileURL: url, rng: SeededRNG(seed: seed))
    }

    private func activeStoreWithWallet() -> CompanionStore {
        let url = tempURL()
        let mon = "{\"baseID\":10,\"pathIDs\":[10],\"stageIndex\":0,\"usedAtStage\":200000000,"
            + "\"rarity\":\"common\",\"totalForms\":3,\"isShiny\":false}"
        let json = "{\"installBaselineSet\":true,\"usedSinceInstall\":5000000000,\"spentTokens\":0,"
            + "\"lastDate\":\"d\",\"active\":\(mon),\"dex\":[],\"collectedFinals\":[]}"
        try? json.data(using: .utf8)!.write(to: url)
        return CompanionStore(provider: PrayerOfflineProvider(), clock: { self.now }, fileURL: url,
                              rng: SeededRNG(seed: 7))
    }

    /// The hatched individual with the one field prayers may differ in, and the random id, normalised.
    private func rollSignature(_ store: CompanionStore) throws -> Data {
        var mon = try XCTUnwrap(store.state.active)
        mon.prayers = nil
        mon.profile?.instanceID = ""
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(mon)
    }

    // MARK: pray()

    func testPrayCounts() {
        let store = hatchReadyEgg(pending: true)
        store.pray(); store.pray(); store.pray()
        XCTAssertEqual(store.state.eggPrayers, PrayerRecord(count: 3))
    }

    func testPrayIsIgnoredWhileRaisingAPokemon() {
        let store = activeStoreWithWallet()
        store.pray()
        XCTAssertNil(store.state.eggPrayers)
    }

    // MARK: no effect on the roll

    func testPrayersDoNotChangeTheHatchResult() async throws {
        for pending in [true, false] {
            let plain = hatchReadyEgg(pending: pending)
            let prayed = hatchReadyEgg(pending: pending)
            for _ in 0..<50 { prayed.pray() }
            await plain.hatchIfNeeded()
            await prayed.hatchIfNeeded()
            XCTAssertNotNil(plain.state.active)
            XCTAssertEqual(try rollSignature(plain), try rollSignature(prayed),
                           "pending=\(pending): prayers must not alter species/rarity/shiny/nature/form/profile")
        }
    }

    // MARK: copy on hatch, reset on every new egg

    func testHatchCopiesPrayersAndClearsEggScope() async throws {
        let store = hatchReadyEgg(pending: true)
        store.pray(); store.pray()
        await store.hatchIfNeeded()
        XCTAssertEqual(store.state.active?.prayers, PrayerRecord(count: 2))
        XCTAssertNil(store.state.eggPrayers)
    }

    func testGraduationKeepsPrayersOnTheDexEntryAndStartsAPlainEgg() async throws {
        let store = hatchReadyEgg(pending: true)
        store.pray()
        await store.hatchIfNeeded()
        for stage in 0..<3 {
            store.applyUsage(PokemonBalance.phaseThreshold(rarity: .common, totalForms: 3, stageIndex: stage))
        }
        XCTAssertNil(store.state.active)
        XCTAssertEqual(store.state.dex.first?.prayers?.count, 1)
        XCTAssertNil(store.state.eggPrayers, "the next egg starts without prayers")
    }

    func testBuyEggStartsWithoutPrayers() {
        let store = activeStoreWithWallet()
        XCTAssertTrue(store.buyFreshEgg())
        XCTAssertNil(store.state.eggPrayers)
        store.pray()
        XCTAssertEqual(store.state.eggPrayers?.count, 1)
    }

    func testReleasedEntryKeepsThePrayersOfTheIndividual() {
        let store = activeStoreWithWallet()
        var state = store.state
        state.active?.prayers = PrayerRecord(count: 4)
        let url = tempURL()
        try? JSONEncoder().encode(state).write(to: url)
        let reloaded = CompanionStore(provider: PrayerOfflineProvider(), clock: { self.now }, fileURL: url,
                                      rng: SeededRNG(seed: 7))
        XCTAssertEqual(reloaded.dexEntries.first?.prayers?.count, 4, "detail view reads the synthesized active entry")
        XCTAssertTrue(reloaded.buyFreshEgg())
        XCTAssertEqual(reloaded.state.dex.last?.prayers?.count, 4)
    }

    func testImportedSaveWithAnActivePokemonDropsEggPrayers() {
        var state = CompanionState()
        state.active = MonState(baseID: 4, pathIDs: [4], stageIndex: 0, usedAtStage: 0, rarity: .common, totalForms: 1)
        state.eggPrayers = PrayerRecord(count: 9)
        XCTAssertNil(SaveTransfer.sanitized(state).eggPrayers)
    }

    func testSanitizeClampsAnAbsurdPrayerCount() {
        var state = CompanionState()
        state.eggPrayers = PrayerRecord(count: Int.max)
        XCTAssertEqual(SaveTransfer.sanitized(state).eggPrayers?.count, SaveTransfer.maxTokenValue)
    }

    // MARK: persistence

    func testPrayerFieldsSurviveEncodeAndSaveTransfer() throws {
        var state = CompanionState()
        state.eggPrayers = PrayerRecord(count: 5)
        let envelope = try SaveTransfer.decode(
            SaveTransfer.encode(state: state, appVersion: "x", deviceName: "d", now: now))
        XCTAssertEqual(envelope.state.eggPrayers, state.eggPrayers)

        let mon = MonState(baseID: 1, pathIDs: [1], stageIndex: 0, usedAtStage: 0, rarity: .common, totalForms: 1,
                           prayers: PrayerRecord(count: 2))
        let decodedMon = try JSONDecoder().decode(MonState.self, from: JSONEncoder().encode(mon))
        XCTAssertEqual(decodedMon.prayers, mon.prayers)
        let entry = DexEntry(baseID: 1, finalID: 1, chainOrder: [1], rarity: .common, caughtAt: nil,
                             prayers: mon.prayers)
        let decodedEntry = try JSONDecoder().decode(DexEntry.self, from: JSONEncoder().encode(entry))
        XCTAssertEqual(decodedEntry.prayers, mon.prayers)
    }

    /// Dev builds once stored extra prayer fields (futility flags); they are gone, but those saves must still load.
    func testSavesWithRemovedPrayerKeysStillDecode() throws {
        let record = "{\"count\":7,\"wasFutile\":true,\"rolledSpeciesID\":1,\"eggWasPurchased\":true}"
        let state = try JSONDecoder().decode(CompanionState.self, from: Data(
            "{\"eggUsage\":5,\"eggWasPurchased\":true,\"eggPrayers\":\(record)}".utf8))
        XCTAssertEqual(state.eggPrayers, PrayerRecord(count: 7))
        let mon = try JSONDecoder().decode(MonState.self, from: Data(
            ("{\"baseID\":1,\"pathIDs\":[1],\"stageIndex\":0,\"usedAtStage\":0,\"rarity\":\"common\","
             + "\"totalForms\":1,\"prayers\":\(record)}").utf8))
        XCTAssertEqual(mon.prayers, PrayerRecord(count: 7))
    }

    func testOldSavesDecodeWithoutPrayers() throws {
        let state = try JSONDecoder().decode(CompanionState.self, from: Data("{\"eggUsage\":5}".utf8))
        XCTAssertNil(state.eggPrayers)
        let mon = try JSONDecoder().decode(MonState.self, from: Data(
            "{\"baseID\":1,\"pathIDs\":[1],\"stageIndex\":0,\"usedAtStage\":0,\"rarity\":\"common\",\"totalForms\":1}".utf8))
        XCTAssertNil(mon.prayers)
        let entry = try JSONDecoder().decode(DexEntry.self, from: Data(
            "{\"baseID\":1,\"finalID\":1,\"chainOrder\":[1],\"rarity\":\"common\"}".utf8))
        XCTAssertNil(entry.prayers)
        let broken = try JSONDecoder().decode(CompanionState.self, from: Data("{\"eggPrayers\":\"oops\"}".utf8))
        XCTAssertNil(broken.eggPrayers, "a damaged field must not take the whole save down")
    }

    // MARK: text

    func testPrayerHatchNotificationFollowsTheOutcome() {
        let ko = L(.ko), en = L(.en)
        XCTAssertEqual(ko.notifPrayerHatchBody("뮤", prayers: 37, shiny: true, rarity: .legendary),
                       "기도 37번… 하늘이 진심이었다. 이로치 뮤!")
        XCTAssertEqual(en.notifPrayerHatchBody("Mew", prayers: 37, shiny: true, rarity: .legendary),
                       "37 prayers… heaven went all in. Shiny Mew!")
        XCTAssertEqual(ko.notifPrayerHatchBody("뮤", prayers: 37, shiny: false, rarity: .legendary),
                       "기도 37번… 통했다?! 뮤가 나왔어요!")
        XCTAssertEqual(en.notifPrayerHatchBody("Mew", prayers: 37, shiny: false, rarity: .legendary),
                       "37 prayers… it worked?! Mew hatched!")
        XCTAssertEqual(ko.notifPrayerHatchBody("피카츄", prayers: 37, shiny: true, rarity: .rare),
                       "기도 37번에 이로치까지?! 피카츄가 나왔어요!")
        XCTAssertEqual(en.notifPrayerHatchBody("Pikachu", prayers: 37, shiny: true, rarity: .common),
                       "37 prayers AND it's shiny?! Pikachu hatched!")
        for rarity in [Rarity.uncommon, .rare] {
            XCTAssertEqual(ko.notifPrayerHatchBody("피카츄", prayers: 37, shiny: false, rarity: rarity),
                           "기도 37번 끝에 피카츄가 나왔어요. 반은 통한 걸로 칩시다.")
            XCTAssertEqual(en.notifPrayerHatchBody("Pikachu", prayers: 37, shiny: false, rarity: rarity),
                           "37 prayers later: Pikachu. Let's call it half a miracle.")
        }
        XCTAssertEqual(ko.notifPrayerHatchBody("꼬렛", prayers: 3, shiny: false, rarity: .common),
                       "기도 3번 끝에 꼬렛이 나왔어요. 하늘도 오늘 바빴나 봐요.")
        XCTAssertEqual(en.notifPrayerHatchBody("Rattata", prayers: 3, shiny: false, rarity: .common),
                       "3 prayers later: Rattata. Heaven must be swamped today.")
    }

    func testEveryLanguageHasACopyForEveryPrayerOutcome() {
        for language in AppLanguage.allCases {
            let l = L(language)
            for (shiny, rarity) in [(true, Rarity.legendary), (false, .legendary), (true, .rare),
                                    (false, .rare), (false, .common)] {
                XCTAssertTrue(l.notifPrayerHatchBody("X", prayers: 5, shiny: shiny, rarity: rarity).contains("5"))
            }
            for n in [1, 3, 30, 70, 130, 200, 400] {
                XCTAssertFalse(l.prayerQuip(n).isEmpty)
                XCTAssertTrue(l.prayerHoverLine(n).contains("\(n)"))
            }
        }
    }

    func testQuipIndexAdvancesEveryThirtyPrayersAndStopsAtTheLast() {
        XCTAssertNil(L.prayerQuipIndex(0), "nothing to say before the first prayer")
        XCTAssertNil(L.prayerQuipIndex(-1))
        let expected: [(Int, Int)] = [(1, 0), (29, 0), (30, 1), (59, 1), (60, 2), (299, 9), (300, 10), (10_000, 10)]
        for (prayers, index) in expected {
            XCTAssertEqual(L.prayerQuipIndex(prayers), index, "\(prayers) prayers")
        }
        XCTAssertEqual(L.prayerQuipCount, 11)
    }

    func testEveryQuipExistsInEveryLanguageAndTheyAreAllDifferent() {
        for language in AppLanguage.allCases {
            let l = L(language)
            let quips = (0..<L.prayerQuipCount).map { l.prayerQuip($0 * L.prayersPerQuip + 1) }
            XCTAssertTrue(quips.allSatisfy { !$0.isEmpty }, "\(language) has an empty quip")
            XCTAssertEqual(Set(quips).count, quips.count, "\(language) repeats a quip")
        }
    }

    func testHoverLineCopy() {
        XCTAssertEqual(L(.ko).prayerHoverLine(0), "")
        XCTAssertEqual(L(.ko).prayerHoverLine(1), "기도 1회 · 일단 한번 빌어봄")
        XCTAssertEqual(L(.ko).prayerHoverLine(30), "기도 30회 · 하늘이 아직 확인 안 함")
        XCTAssertEqual(L(.ko).prayerHoverLine(150), "기도 150회 · 하늘 대기열 3,812번째")
        XCTAssertEqual(L(.ko).prayerHoverLine(240), "기도 240회 · 하늘: \"접수했습니다. 검토 후 답변드릴게요\"")
        XCTAssertEqual(L(.ko).prayerHoverLine(299), "기도 299회 · 알이 방금 \"그만…\"이라고 한 것 같음")
        XCTAssertEqual(L(.en).prayerHoverLine(1), "1 prayer · just trying it out")
        XCTAssertEqual(L(.en).prayerHoverLine(31), "31 prayers · heaven hasn't checked yet")
        XCTAssertEqual(L(.en).prayerHoverLine(120), "120 prayers · heaven's servers are lagging")
        XCTAssertEqual(L(.en).prayerHoverLine(180), "180 prayers · your palms are wearing thin")
        XCTAssertEqual(L(.en).prayerHoverLine(300), "300 prayers · if a legendary hatches, that's pure skill")
    }

    func testDetailCopy() {
        XCTAssertEqual(L(.ko).prayerBornWith(37), "기도 37번 받고 태어남")
        XCTAssertEqual(L(.en).prayerBornWith(37), "Born after 37 prayers")
        XCTAssertEqual(L(.ko).prayerReachedHeaven, "기도가 하늘에 닿았다")
        XCTAssertEqual(L(.en).prayerReachedHeaven, "Your prayers reached the heavens.")
        for language in AppLanguage.allCases {
            XCTAssertFalse(L(language).prayerReachedHeaven.isEmpty, "\(language)")
        }
    }

    // MARK: floating pet click routing and particles

    func testClickPraysOverAnEggAndOpensThePopoverForAPokemon() {
        XCTAssertEqual(FloatingPetController.clickAction(subjectIsEgg: true), .pray)
        XCTAssertEqual(FloatingPetController.clickAction(subjectIsEgg: false), .openPopover)
    }

    func testBurstSpawnsClampedParticlesAndRemovesThemItself() async throws {
        let burst = PrayerBurst()
        burst.spawn(xFraction: -3)
        burst.spawn(xFraction: 7)
        burst.spawn()
        XCTAssertEqual(burst.particles.count, 3, "rapid clicks stack up")
        XCTAssertEqual(burst.wobbleCount, 3)
        XCTAssertEqual(burst.particles[0].xFraction, 0)
        XCTAssertEqual(burst.particles[1].xFraction, 1)
        XCTAssertTrue(burst.particles.allSatisfy { (0...1).contains($0.xFraction) })
        try await Task.sleep(for: PrayerBurst.lifetime + .milliseconds(300))
        XCTAssertTrue(burst.particles.isEmpty, "each particle removes itself")
        XCTAssertEqual(burst.wobbleCount, 3)
    }

    func testEmojiStaysInsideThePetFrameAtEverySize() {
        for petSize in stride(from: CGFloat(48), through: 384, by: 8) {
            let emoji = PrayerEmojiLayer.emojiSize(petSize: petSize)
            XCTAssertLessThanOrEqual(emoji, petSize)
            for fraction in [0.0, 1.0] {
                let centre = emoji / 2 + CGFloat(fraction) * (petSize - emoji)
                XCTAssertGreaterThanOrEqual(centre - emoji / 2, 0)
                XCTAssertLessThanOrEqual(centre + emoji / 2, petSize)
            }
        }
    }

    func testHoverTextShowsPrayersOnlyWhenThereAreSome() {
        let l = L(.ko)
        let plain = FloatingPetView.hoverTooltip(todayTokens: 1, limitUtilization: nil, mode: .used, l: l)
        let prayed = FloatingPetView.hoverTooltip(todayTokens: 1, limitUtilization: nil, mode: .used, l: l, prayers: 3)
        XCTAssertFalse(plain.contains("기도"))
        XCTAssertEqual(prayed, plain + "\n기도 3회 · 일단 한번 빌어봄")
    }

    // MARK: prayer-triggered usage refresh

    private func makeRouter(clock: @escaping () -> Date, log: PrayerCallLog) -> PetClickRouter {
        PetClickRouter(pray: { log.prays += 1; log.eggPrayers += 1 }, prayerCount: { log.eggPrayers },
                       didPray: { log.didPray += 1 },
                       spawnEmoji: { log.emojis += 1 }, refreshUsage: { log.refreshes += 1 },
                       openPopover: { log.opens += 1 }, clock: clock)
    }

    private func pray(_ times: Int, on router: PetClickRouter) {
        for _ in 0..<times { router.handle(subjectIsEgg: true) }
    }

    func testMilestonesAreEveryThirtyPrayers() {
        let milestones = [0: 0, 1: 0, 29: 0, 30: 1, 59: 1, 60: 2, 89: 2, 90: 3, 120: 4]
        for (count, milestone) in milestones {
            XCTAssertEqual(FloatingPetController.prayerRefreshMilestone(for: count), milestone, "\(count) prayers")
        }
        XCTAssertEqual(FloatingPetController.prayersPerRefresh, 30)
        XCTAssertEqual(FloatingPetController.prayerRefreshMilestone(for: Int.max), Int.max / 30, "huge counts do not trap")
    }

    func testPrayerRefreshFollowsTheMilestones() {
        var current = now
        let log = PrayerCallLog()
        let router = makeRouter(clock: { current }, log: log)
        let floor = FloatingPetController.prayerRefreshInterval

        pray(29, on: router)
        XCTAssertEqual(log.refreshes, 0, "29 prayers: no refresh")
        pray(1, on: router)
        XCTAssertEqual(log.refreshes, 1, "the 30th prayer refreshes")
        current = now.addingTimeInterval(floor)
        pray(29, on: router)
        XCTAssertEqual(log.refreshes, 1, "59 prayers: no new refresh")
        pray(1, on: router)
        XCTAssertEqual(log.refreshes, 2, "the 60th prayer refreshes")
        current = now.addingTimeInterval(floor * 2)
        pray(29, on: router)
        XCTAssertEqual(log.refreshes, 2)
        pray(1, on: router)
        XCTAssertEqual(log.refreshes, 3, "the 90th prayer refreshes")
        XCTAssertEqual(log.emojis, log.prays, "every click still spawns its emoji")
        XCTAssertEqual(log.didPray, log.prays, "every click rebuilds the hover text")
    }

    func testAMilestoneInsideTheFloorIsRefreshedByTheFirstClickAfterIt() {
        var current = now
        let log = PrayerCallLog()
        let router = makeRouter(clock: { current }, log: log)
        pray(30, on: router)
        XCTAssertEqual(log.refreshes, 1)
        current = now.addingTimeInterval(5)
        pray(30, on: router)   // reaches 60 only 5 s after the last refresh
        XCTAssertEqual(log.refreshes, 1, "the floor holds the 60th-prayer refresh back")
        current = now.addingTimeInterval(FloatingPetController.prayerRefreshInterval)
        pray(1, on: router)
        XCTAssertEqual(log.refreshes, 2, "the first click after the floor does not lose the milestone")
        pray(1, on: router)
        XCTAssertEqual(log.refreshes, 2, "and it is not refreshed twice")
    }

    func testANewEggStartsTheMilestonesOver() {
        var current = now
        let log = PrayerCallLog()
        let router = makeRouter(clock: { current }, log: log)
        pray(60, on: router)   // refreshes at 30; the 60th is held back by the floor
        XCTAssertEqual(log.refreshes, 1)
        current = now.addingTimeInterval(FloatingPetController.prayerRefreshInterval * 2)
        log.eggPrayers = 0     // a new egg: the persisted prayer count starts over
        pray(29, on: router)
        XCTAssertEqual(log.refreshes, 1)
        pray(1, on: router)
        XCTAssertEqual(log.refreshes, 2, "the new egg's 30th prayer refreshes again")
    }

    func testClickingAHatchedPokemonOpensThePopoverWithoutPrayingOrRefreshing() {
        let log = PrayerCallLog()
        let router = makeRouter(clock: { self.now }, log: log)
        pray(29, on: router)
        for _ in 0..<50 { router.handle(subjectIsEgg: false) }
        XCTAssertEqual(log.opens, 50)
        XCTAssertEqual(log.prays, 29)
        XCTAssertEqual(log.didPray, 29, "hatched clicks do not touch the prayer hover text")
        XCTAssertEqual(log.refreshes, 0, "hatched-Pokémon clicks never count")
        pray(1, on: router)
        XCTAssertEqual(log.refreshes, 1, "the 30th real prayer still refreshes")
    }

    func testShouldRefreshOnPrayerDecision() {
        let later = now.addingTimeInterval(FloatingPetController.prayerRefreshInterval)
        func decide(_ count: Int, last: Int, at: Date?, _ moment: Date) -> Bool {
            FloatingPetController.shouldRefreshOnPrayer(count: count, lastRefreshedMilestone: last,
                                                        lastRefreshAt: at, now: moment)
        }
        XCTAssertFalse(decide(29, last: 0, at: nil, now))
        XCTAssertTrue(decide(30, last: 0, at: nil, now))
        XCTAssertFalse(decide(30, last: 1, at: nil, now), "already refreshed at this milestone")
        XCTAssertFalse(decide(30, last: 0, at: now, now), "inside the floor")
        XCTAssertTrue(decide(30, last: 0, at: now, later))
        XCTAssertTrue(decide(60, last: 1, at: now, later))
    }
}

@MainActor
private final class PrayerCallLog {
    var prays = 0, emojis = 0, refreshes = 0, opens = 0, didPray = 0
    /// The persisted prayer count of the current egg (reset by the test to simulate a new egg).
    var eggPrayers = 0
}
