import XCTest
@testable import PokeTokenBar

private func questNode(_ id: Int, _ ch: [EvoNode] = []) -> EvoNode { EvoNode(speciesID: id, children: ch) }
private func questLine(base: Int) -> EvoLine {
    EvoLine(baseID: base, tree: questNode(base), rarity: .common,
            names: [base: ["en": "P\(base)", "ko": "포\(base)", "fr": "P\(base)"]])
}
private struct QuestStubProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { questLine(base: baseSpeciesID) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [BaseSpecies(id: 1, captureRate: 255)] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { BaseSpecies(id: id, captureRate: 255) }
}

private struct StoneStubProvider: PokeProviding {
    let entries = [
        BaseSpecies(id: 1, captureRate: 45),   // Bulbasaur (Grass)
        BaseSpecies(id: 4, captureRate: 45),   // Charmander (Fire)
        BaseSpecies(id: 7, captureRate: 45),   // Squirtle (Water)
        BaseSpecies(id: 25, captureRate: 190)  // Pikachu (Electric)
    ]
    func line(baseSpeciesID: Int) async throws -> EvoLine { questLine(base: baseSpeciesID) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { entries }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { entries.first { $0.id == id } }
}

@MainActor
final class QuestsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeStore(used: Int = 0, spent: Int = 0) -> CompanionStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("quests-\(UUID().uuidString).json")
        let json = "{\"installBaselineSet\":true,\"usedSinceInstall\":\(used),\"spentTokens\":\(spent),"
            + "\"lastDate\":\"2026-09-15\",\"active\":null,\"dex\":[],\"collectedFinals\":[]}"
        try? json.data(using: .utf8)!.write(to: url)
        return CompanionStore(provider: QuestStubProvider(), clock: { self.now }, fileURL: url)
    }

    func testInitialQuestState() {
        let store = makeStore()
        XCTAssertEqual(store.currentStreak, 0)
        XCTAssertEqual(store.bestStreak, 0)
        XCTAssertFalse(store.isStreakActiveToday)
        XCTAssertEqual(store.dailyQuests.count, DailyQuestType.allCases.count)
        XCTAssertEqual(store.weeklyQuests.count, WeeklyQuestType.allCases.count)
        XCTAssertEqual(store.achievements.count, AchievementType.allCases.count)
    }

    func testStreakProgressionAndReset() {
        let store = makeStore()

        // Day 1
        store.update(todayTokensByProvider: ["claude": 10_000_000], todayDate: "2026-09-15",
                     monthTotal: 10_000_000, burnTier: .normal, limitWarning: false, hasUsageData: true)
        XCTAssertEqual(store.currentStreak, 1)
        XCTAssertEqual(store.bestStreak, 1)
        XCTAssertTrue(store.isStreakActiveToday)

        // Same day activity does not advance streak
        store.update(todayTokensByProvider: ["claude": 20_000_000], todayDate: "2026-09-15",
                     monthTotal: 20_000_000, burnTier: .normal, limitWarning: false, hasUsageData: true)
        XCTAssertEqual(store.currentStreak, 1)

        // Consecutive Day (Day 2)
        store.update(todayTokensByProvider: ["claude": 5_000_000], todayDate: "2026-09-16",
                     monthTotal: 25_000_000, burnTier: .normal, limitWarning: false, hasUsageData: true)
        XCTAssertEqual(store.currentStreak, 2)
        XCTAssertEqual(store.bestStreak, 2)

        // Skipped day: Day 4 (missed Day 3)
        store.update(todayTokensByProvider: ["claude": 5_000_000], todayDate: "2026-09-18",
                     monthTotal: 30_000_000, burnTier: .normal, limitWarning: false, hasUsageData: true)
        XCTAssertEqual(store.currentStreak, 1)
        XCTAssertEqual(store.bestStreak, 2)
    }

    func testDailyQuestCompletionAndClaim() {
        let store = makeStore()
        store.update(todayTokensByProvider: ["claude": 30_000_000], todayDate: "2026-09-15",
                     monthTotal: 30_000_000, burnTier: .normal, limitWarning: false, hasUsageData: true)

        let warmup = store.dailyQuests.first { $0.type == .warmup }!
        XCTAssertTrue(warmup.isCompleted)
        XCTAssertFalse(warmup.isClaimed)

        let initialCandies = store.rareCandyCount
        let initialTokens = store.availableTokens

        // Claim warmup
        let claimed = store.claimDailyQuest(.warmup)
        XCTAssertTrue(claimed)

        let updatedWarmup = store.dailyQuests.first { $0.type == .warmup }!
        XCTAssertTrue(updatedWarmup.isClaimed)
        XCTAssertEqual(store.availableTokens, initialTokens + DailyQuestType.warmup.reward.tokens)
        XCTAssertEqual(store.rareCandyCount, initialCandies + DailyQuestType.warmup.reward.candies)

        // Double claim should fail
        XCTAssertFalse(store.claimDailyQuest(.warmup))
    }

    func testDeepWork150MRewardHasCandy() {
        let store = makeStore()
        XCTAssertEqual(DailyQuestType.deepWork.reward.candies, 1)

        store.update(todayTokensByProvider: ["claude": 150_000_000], todayDate: "2026-09-15",
                     monthTotal: 150_000_000, burnTier: .normal, limitWarning: false, hasUsageData: true)

        let deepWork = store.dailyQuests.first { $0.type == .deepWork }!
        XCTAssertTrue(deepWork.isCompleted)
        XCTAssertFalse(deepWork.isClaimed)

        let candyBefore = store.rareCandyCount
        XCTAssertTrue(store.claimDailyQuest(.deepWork))
        XCTAssertEqual(store.rareCandyCount, candyBefore + 1)
    }

    func testWeeklyQuestsProgressionAndReset() {
        let store = makeStore()

        // Week 1 - Day 1
        store.update(todayTokensByProvider: ["claude": 50_000_000], todayDate: "2026-09-15",
                     monthTotal: 50_000_000, burnTier: .normal, limitWarning: false, hasUsageData: true,
                     weekTotal: 50_000_000)

        // Week 1 - Day 2
        store.update(todayTokensByProvider: ["claude": 60_000_000], todayDate: "2026-09-16",
                     monthTotal: 110_000_000, burnTier: .normal, limitWarning: false, hasUsageData: true,
                     weekTotal: 110_000_000)

        let weekly100M = store.weeklyQuests.first { $0.type == .tokens100M }!
        XCTAssertTrue(weekly100M.isCompleted)
        XCTAssertFalse(weekly100M.isClaimed)

        XCTAssertTrue(store.claimWeeklyQuest(.tokens100M))
        let updatedWeekly = store.weeklyQuests.first { $0.type == .tokens100M }!
        XCTAssertTrue(updatedWeekly.isClaimed)

        // Week 2 transition
        store.update(todayTokensByProvider: ["claude": 5_000_000], todayDate: "2026-09-22",
                     monthTotal: 115_000_000, burnTier: .normal, limitWarning: false, hasUsageData: true,
                     weekTotal: 5_000_000)

        let newWeekQuest = store.weeklyQuests.first { $0.type == .tokens100M }!
        XCTAssertFalse(newWeekQuest.isClaimed)
        XCTAssertFalse(newWeekQuest.isCompleted)
    }

    func testDailyAndWeeklyMaxMilestones() {
        let store = makeStore()
        XCTAssertEqual(DailyQuestType.titan.target, 500_000_000)
        XCTAssertEqual(DailyQuestType.titan.reward.candies, 2)
        XCTAssertEqual(WeeklyQuestType.tokens3_5B.target, 3_500_000_000)
        XCTAssertEqual(WeeklyQuestType.tokens3_5B.reward.candies, 3)

        store.update(todayTokensByProvider: ["claude": 500_000_000], todayDate: "2026-09-15",
                     monthTotal: 500_000_000, burnTier: .blazing, limitWarning: false, hasUsageData: true,
                     weekTotal: 3_500_000_000)

        let dailyTitan = store.dailyQuests.first { $0.type == .titan }!
        XCTAssertTrue(dailyTitan.isCompleted)

        let weekly3_5B = store.weeklyQuests.first { $0.type == .tokens3_5B }!
        XCTAssertTrue(weekly3_5B.isCompleted)
    }

    func testBatchClaimAll() {
        let store = makeStore(used: 150_000_000)
        store.update(todayTokensByProvider: ["claude": 30_000_000], todayDate: "2026-09-15",
                     monthTotal: 30_000_000, burnTier: .normal, limitWarning: false, hasUsageData: true)

        let claimedQuestsCount = store.claimAllQuests()
        XCTAssertGreaterThan(claimedQuestsCount, 0)

        let claimedAchCount = store.claimAllAchievements()
        XCTAssertGreaterThan(claimedAchCount, 0)
    }

    func testAchievementsClaim() {
        let store = makeStore(used: 150_000_000)

        let ach100M = store.achievements.first { $0.type == .tokens100M }!
        XCTAssertTrue(ach100M.isCompleted)
        XCTAssertFalse(ach100M.isClaimed)

        let initialCandies = store.rareCandyCount
        let initialTokens = store.availableTokens
        let claimed = store.claimAchievement(.tokens100M)
        XCTAssertTrue(claimed)

        XCTAssertEqual(store.rareCandyCount, initialCandies + AchievementType.tokens100M.reward.candies)
        XCTAssertEqual(store.availableTokens, initialTokens + AchievementType.tokens100M.reward.tokens)
        let updatedAch = store.achievements.first { $0.type == .tokens100M }!
        XCTAssertTrue(updatedAch.isClaimed)

        // Double claim should fail
        XCTAssertFalse(store.claimAchievement(.tokens100M))
    }

    func testDuplicateLegendaryAchievementAndLegendCharm() {
        let store = makeStore()

        let achInitial = store.achievements.first { $0.type == .duplicateLegendary }!
        XCTAssertEqual(achInitial.progress, 0)
        XCTAssertFalse(achInitial.isCompleted)
        XCTAssertFalse(achInitial.isClaimed)
        XCTAssertFalse(store.ownsLegendCharm)

        // Having 1 Mewtwo graduated -> progress 1
        let mewtwo1 = DexEntry(baseID: 150, finalID: 150, chainOrder: [150], rarity: .legendary, caughtAt: now)
        store.addDexEntry(mewtwo1)
        let ach1 = store.achievements.first { $0.type == .duplicateLegendary }!
        XCTAssertEqual(ach1.progress, 1)
        XCTAssertFalse(ach1.isCompleted)

        // Having a different legendary (Rayquaza) -> progress is still 1 (not duplicate yet)
        let rayquaza = DexEntry(baseID: 384, finalID: 384, chainOrder: [384], rarity: .legendary, caughtAt: now)
        store.addDexEntry(rayquaza)
        let achStill1 = store.achievements.first { $0.type == .duplicateLegendary }!
        XCTAssertEqual(achStill1.progress, 1)
        XCTAssertFalse(achStill1.isCompleted)

        // Graduating a 2nd Mewtwo (duplicate legendary raised) -> progress 2!
        let mewtwo2 = DexEntry(baseID: 150, finalID: 150, chainOrder: [150], rarity: .legendary, caughtAt: now)
        store.addDexEntry(mewtwo2)
        let ach2 = store.achievements.first { $0.type == .duplicateLegendary }!
        XCTAssertEqual(ach2.progress, 2)
        XCTAssertTrue(ach2.isCompleted)
        XCTAssertFalse(ach2.isClaimed)

        let candyBefore = store.rareCandyCount
        let tokensBefore = store.availableTokens
        XCTAssertTrue(store.claimAchievement(.duplicateLegendary))

        XCTAssertTrue(store.ownsLegendCharm)
        XCTAssertEqual(store.itemCount(.legendCharm), 1)
        XCTAssertEqual(store.rareCandyCount, candyBefore)
        XCTAssertEqual(store.availableTokens, tokensBefore)

        let achClaimed = store.achievements.first { $0.type == .duplicateLegendary }!
        XCTAssertTrue(achClaimed.isClaimed)
        XCTAssertFalse(store.claimAchievement(.duplicateLegendary))
    }

    func testLegendaryGroupAchievementsAndPassiveItems() {
        let store = makeStore()

        // Legendary birds (144, 145, 146)
        let bird1 = DexEntry(baseID: 144, finalID: 144, chainOrder: [144], rarity: .legendary, caughtAt: now)
        let bird2 = DexEntry(baseID: 145, finalID: 145, chainOrder: [145], rarity: .legendary, caughtAt: now)
        store.addDexEntries([bird1, bird2])

        let birdsAch = store.achievements.first { $0.type == .legendaryBirds }!
        XCTAssertEqual(birdsAch.progress, 2)
        XCTAssertFalse(birdsAch.isCompleted)

        let bird3 = DexEntry(baseID: 146, finalID: 146, chainOrder: [146], rarity: .legendary, caughtAt: now)
        store.addDexEntry(bird3)

        let birdsAchComplete = store.achievements.first { $0.type == .legendaryBirds }!
        XCTAssertEqual(birdsAchComplete.progress, 3)
        XCTAssertTrue(birdsAchComplete.isCompleted)

        XCTAssertTrue(store.claimAchievement(.legendaryBirds))
        XCTAssertTrue(store.ownsSilverWing)

        // Silver wing halves hatch threshold
        let defaultThreshold = PokemonBalance.scaled(PokemonBalance.eggHatchThreshold, by: store.growthDifficulty)
        XCTAssertEqual(store.eggTokensToHatch, max(1_000_000, defaultThreshold / 2))

        // Tao duo (Reshiram 643, Zekrom 644)
        let reshiram = DexEntry(baseID: 643, finalID: 643, chainOrder: [643], rarity: .legendary, caughtAt: now)
        let zekrom = DexEntry(baseID: 644, finalID: 644, chainOrder: [644], rarity: .legendary, caughtAt: now)
        store.addDexEntries([reshiram, zekrom])

        let taoAch = store.achievements.first { $0.type == .taoDuo }!
        XCTAssertEqual(taoAch.progress, 2)
        XCTAssertTrue(taoAch.isCompleted)
        XCTAssertTrue(store.claimAchievement(.taoDuo))
        XCTAssertTrue(store.ownsDnaSplicers)
    }

    func testQuestStateLenientDecoding() throws {
        let legacyJson = "{\"installBaselineSet\":true,\"usedSinceInstall\":50000000,\"spentTokens\":0,"
            + "\"lastDate\":\"2026-09-15\",\"active\":null,\"dex\":[],\"collectedFinals\":[]}"
        let decoded = try JSONDecoder().decode(CompanionState.self, from: legacyJson.data(using: .utf8)!)
        XCTAssertEqual(decoded.questState.currentStreak, 0)
        XCTAssertEqual(decoded.questState.bestStreak, 0)
        XCTAssertTrue(decoded.questState.claimedDailyQuestIDs.isEmpty)
        XCTAssertTrue(decoded.questState.claimedWeeklyQuestIDs.isEmpty)
    }

    func testTypeBadgeAchievementsAndWeaknessSpeedBoost() {
        let store = makeStore()

        // 1. Verify 18 badge achievements exist in achievements list
        let badgeAchievements = store.achievements.filter { $0.type.badgeType != nil }
        XCTAssertEqual(badgeAchievements.count, 18)

        // Fairy type has 22 species
        let fairySpecies = PokemonTypeData.species(for: .fairy)
        XCTAssertEqual(fairySpecies.count, 22)

        let initialFairyAch = store.achievements.first { $0.type == .badgeFairy }!
        XCTAssertEqual(initialFairyAch.progress, 0)
        XCTAssertEqual(initialFairyAch.target, 22)
        XCTAssertFalse(initialFairyAch.isCompleted)

        // Add 21 fairy entries -> progress 21 (incomplete)
        let entries21 = fairySpecies.dropFirst().map {
            DexEntry(baseID: $0, finalID: $0, chainOrder: [$0], rarity: .common, caughtAt: now)
        }
        store.addDexEntries(entries21)
        let prog21Ach = store.achievements.first { $0.type == .badgeFairy }!
        XCTAssertEqual(prog21Ach.progress, 21)
        XCTAssertFalse(prog21Ach.isCompleted)

        // Add the last fairy entry -> progress 22 (completed!)
        let lastFairyID = fairySpecies.first!
        store.addDexEntry(DexEntry(baseID: lastFairyID, finalID: lastFairyID, chainOrder: [lastFairyID], rarity: .common, caughtAt: now))
        let completedFairyAch = store.achievements.first { $0.type == .badgeFairy }!
        XCTAssertEqual(completedFairyAch.progress, 22)
        XCTAssertTrue(completedFairyAch.isCompleted)

        // Claim fairy badge
        XCTAssertTrue(store.claimAchievement(.badgeFairy))
        XCTAssertEqual(store.itemCount(.fairyBadge), 1)

        // Fairy is super effective against Dragon, Fighting, Dark!
        // Dragonite (Dragon/Flying, #149): Fairy is 2.0x, Flying is neutral -> weak to Fairy!
        XCTAssertTrue(PokemonTypeData.isWeak(to: .fairy, speciesID: 149))
        XCTAssertEqual(store.ownedBadgeCount(weakAgainst: 149), 1)
        XCTAssertEqual(store.typeBadgeSpeedMultiplier(forSpeciesID: 149), 1.20)

        // Add all Ice species and claim Glacier badge
        store.addDexEntries(PokemonTypeData.species(for: .ice).map {
            DexEntry(baseID: $0, finalID: $0, chainOrder: [$0], rarity: .common, caughtAt: now)
        })
        XCTAssertTrue(store.claimAchievement(.badgeGlacier))
        XCTAssertEqual(store.itemCount(.glacierBadge), 1)

        // Now Dragonite is weak to BOTH Fairy Badge and Glacier Badge -> 2 effective badges!
        XCTAssertEqual(store.ownedBadgeCount(weakAgainst: 149), 2)
        XCTAssertEqual(store.typeBadgeSpeedMultiplier(forSpeciesID: 149), 1.40)

        // Normal badge boosts Normal types
        XCTAssertTrue(PokemonTypeData.isWeak(to: .normal, speciesID: 143))
        XCTAssertFalse(PokemonTypeData.isWeak(to: .normal, speciesID: 6))
    }

    func testStarterTrioAchievements() {
        let store = makeStore()

        // 1. Initial state check
        let kantoAch = store.achievements.first { $0.type == .kantoStarters }!
        XCTAssertEqual(kantoAch.progress, 0)
        XCTAssertEqual(kantoAch.target, 3)
        XCTAssertFalse(kantoAch.isCompleted)

        let masterAch = store.achievements.first { $0.type == .starterMaster }!
        XCTAssertEqual(masterAch.progress, 0)
        XCTAssertEqual(masterAch.target, 15)
        XCTAssertFalse(masterAch.isCompleted)

        // 2. Add Venusaur (#3)
        store.addDexEntry(DexEntry(baseID: 1, finalID: 3, chainOrder: [1, 2, 3], rarity: .starter, caughtAt: now))
        XCTAssertEqual(store.achievements.first { $0.type == .kantoStarters }!.progress, 1)
        XCTAssertEqual(store.achievements.first { $0.type == .starterMaster }!.progress, 1)

        // 3. Add Charizard (#6)
        store.addDexEntry(DexEntry(baseID: 4, finalID: 6, chainOrder: [4, 5, 6], rarity: .starter, caughtAt: now))
        XCTAssertEqual(store.achievements.first { $0.type == .kantoStarters }!.progress, 2)
        XCTAssertEqual(store.achievements.first { $0.type == .starterMaster }!.progress, 2)

        // 4. Add Blastoise (#9) -> Completes Kanto Starters!
        store.addDexEntry(DexEntry(baseID: 7, finalID: 9, chainOrder: [7, 8, 9], rarity: .starter, caughtAt: now))
        let completedKanto = store.achievements.first { $0.type == .kantoStarters }!
        XCTAssertEqual(completedKanto.progress, 3)
        XCTAssertTrue(completedKanto.isCompleted)

        // 5. Claim Kanto Starters achievement (awards Leaf Stone)
        let initialCandies = store.rareCandyCount
        let initialTokens = store.availableTokens
        XCTAssertEqual(store.itemCount(.leafStone), 0)
        XCTAssertTrue(store.claimAchievement(.kantoStarters))
        XCTAssertEqual(store.rareCandyCount, initialCandies)
        XCTAssertEqual(store.availableTokens, initialTokens)
        XCTAssertEqual(store.itemCount(.leafStone), 1)

        // 6. Add Johto starters (#154, #157, #160)
        store.addDexEntries([
            DexEntry(baseID: 152, finalID: 154, chainOrder: [152, 153, 154], rarity: .starter, caughtAt: now),
            DexEntry(baseID: 155, finalID: 157, chainOrder: [155, 156, 157], rarity: .starter, caughtAt: now),
            DexEntry(baseID: 158, finalID: 160, chainOrder: [158, 159, 160], rarity: .starter, caughtAt: now)
        ])
        XCTAssertTrue(store.achievements.first { $0.type == .johtoStarters }!.isCompleted)
        XCTAssertEqual(store.itemCount(.fireStone), 0)
        XCTAssertTrue(store.claimAchievement(.johtoStarters))
        XCTAssertEqual(store.itemCount(.fireStone), 1)

        // 7. Add Hoenn starters (#254, #257, #260)
        store.addDexEntries([
            DexEntry(baseID: 252, finalID: 254, chainOrder: [252, 253, 254], rarity: .starter, caughtAt: now),
            DexEntry(baseID: 255, finalID: 257, chainOrder: [255, 256, 257], rarity: .starter, caughtAt: now),
            DexEntry(baseID: 258, finalID: 260, chainOrder: [258, 259, 260], rarity: .starter, caughtAt: now)
        ])
        XCTAssertTrue(store.achievements.first { $0.type == .hoennStarters }!.isCompleted)
        XCTAssertEqual(store.itemCount(.waterStone), 0)
        XCTAssertTrue(store.claimAchievement(.hoennStarters))
        XCTAssertEqual(store.itemCount(.waterStone), 1)

        // 8. Add Sinnoh starters (#389, #392, #395)
        store.addDexEntries([
            DexEntry(baseID: 387, finalID: 389, chainOrder: [387, 388, 389], rarity: .starter, caughtAt: now),
            DexEntry(baseID: 390, finalID: 392, chainOrder: [390, 391, 392], rarity: .starter, caughtAt: now),
            DexEntry(baseID: 393, finalID: 395, chainOrder: [393, 394, 395], rarity: .starter, caughtAt: now)
        ])
        XCTAssertTrue(store.achievements.first { $0.type == .sinnohStarters }!.isCompleted)
        XCTAssertEqual(store.itemCount(.sunStone), 0)
        XCTAssertTrue(store.claimAchievement(.sinnohStarters))
        XCTAssertEqual(store.itemCount(.sunStone), 1)

        // 9. Add Unova starters (#497, #500, #503)
        store.addDexEntries([
            DexEntry(baseID: 495, finalID: 497, chainOrder: [495, 496, 497], rarity: .starter, caughtAt: now),
            DexEntry(baseID: 498, finalID: 500, chainOrder: [498, 499, 500], rarity: .starter, caughtAt: now),
            DexEntry(baseID: 501, finalID: 503, chainOrder: [501, 502, 503], rarity: .starter, caughtAt: now)
        ])
        XCTAssertTrue(store.achievements.first { $0.type == .unovaStarters }!.isCompleted)
        XCTAssertEqual(store.itemCount(.moonStone), 0)
        XCTAssertTrue(store.claimAchievement(.unovaStarters))
        XCTAssertEqual(store.itemCount(.moonStone), 1)

        // 10. Starter Master is now completed (15/15)!
        let completedMaster = store.achievements.first { $0.type == .starterMaster }!
        XCTAssertEqual(completedMaster.progress, 15)
        XCTAssertTrue(completedMaster.isCompleted)

        let candiesBeforeMaster = store.rareCandyCount
        let tokensBeforeMaster = store.availableTokens
        XCTAssertTrue(store.claimAchievement(.starterMaster))
        XCTAssertEqual(store.rareCandyCount, candiesBeforeMaster + 5)
        XCTAssertEqual(store.availableTokens, tokensBeforeMaster + 500_000_000)
    }

    func testEvolutionStoneUsageAndEggTypeGuarantee() async {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("stone-test-\(UUID().uuidString).json")
        let mon = "{\"baseID\":25,\"pathIDs\":[25],\"stageIndex\":0,\"usedAtStage\":0,"
            + "\"rarity\":\"common\",\"totalForms\":1,\"isShiny\":false}"
        let json = "{\"installBaselineSet\":true,\"usedSinceInstall\":10000000,\"spentTokens\":0,"
            + "\"lastDate\":\"d\",\"active\":\(mon),\"dex\":[],\"collectedFinals\":[],"
            + "\"inventory\":{\"fireStone\":1,\"waterStone\":2}}"
        try? json.data(using: .utf8)!.write(to: url)
        let store = CompanionStore(provider: StoneStubProvider(), clock: { self.now }, fileURL: url)

        XCTAssertFalse(store.isEgg)
        XCTAssertEqual(store.currentSpeciesID, 25)
        XCTAssertTrue(store.canUseStone(.fireStone))
        XCTAssertTrue(store.canUseStone(.waterStone))
        XCTAssertFalse(store.canUseStone(.leafStone)) // 0 in inventory

        // Use fire stone
        let used = store.useStone(.fireStone)
        XCTAssertTrue(used)
        XCTAssertEqual(store.itemCount(.fireStone), 0)
        XCTAssertTrue(store.isEgg)
        XCTAssertEqual(store.eggTypeGuarantee, .fire)
        XCTAssertEqual(store.state.dex.count, 1) // Pikachu archived
        XCTAssertEqual(store.state.dex.first?.baseID, 25)

        // While incubating as egg, cannot use another stone
        XCTAssertFalse(store.canUseStone(.waterStone))
        XCTAssertFalse(store.useStone(.waterStone))

        // Progress egg to hatch threshold
        store.setEggUsageForTesting(store.eggHatchThreshold)
        await store.hatchIfNeeded()

        // Hatched companion should be Charmander (#4) because it's Fire type
        XCTAssertFalse(store.isEgg)
        XCTAssertEqual(store.currentSpeciesID, 4)
        XCTAssertNil(store.eggTypeGuarantee)

        // Now use water stone
        XCTAssertTrue(store.canUseStone(.waterStone))
        XCTAssertTrue(store.useStone(.waterStone))
        XCTAssertEqual(store.itemCount(.waterStone), 1)
        XCTAssertTrue(store.isEgg)
        XCTAssertEqual(store.eggTypeGuarantee, .water)

        // Progress and hatch water egg
        store.setEggUsageForTesting(store.eggHatchThreshold)
        await store.hatchIfNeeded()

        // Hatched companion should be Squirtle (#7) because it's Water type
        XCTAssertFalse(store.isEgg)
        XCTAssertEqual(store.currentSpeciesID, 7)
        XCTAssertNil(store.eggTypeGuarantee)
    }

    func testAchievementCategories() {
        let store = makeStore()
        for category in AchievementCategory.allCases {
            let inCat = store.achievements.filter { $0.type.category == category }
            XCTAssertFalse(inCat.isEmpty, "Category \(category.rawValue) should not be empty")
        }
        XCTAssertEqual(store.achievements.filter { $0.type.category == .starters }.count, 6)
        XCTAssertEqual(store.achievements.filter { $0.type.category == .legendaries }.count, 13)
        XCTAssertEqual(store.achievements.filter { $0.type.category == .gymBadges }.count, 18)
        XCTAssertEqual(store.achievements.filter { $0.type.category == .productivity }.count, 15)
        XCTAssertEqual(store.achievements.filter { $0.type.category == .adventure }.count, 22)
        XCTAssertEqual(store.achievements.count, 74)

        let l = store.l
        for category in AchievementCategory.allCases {
            XCTAssertFalse(l.achievementCategoryTitle(category).isEmpty)
            XCTAssertFalse(l.achievementCategorySubtitle(category).isEmpty)
        }
        XCTAssertFalse(l.allCategories.isEmpty)
    }

    func testEeveeAchievements() {
        let store = makeStore()
        let kanto = store.achievements.first { $0.type == .eeveeKantoTrio }!
        let master = store.achievements.first { $0.type == .eeveeMaster }!
        XCTAssertEqual(kanto.target, 3)
        XCTAssertEqual(master.target, 7)
        XCTAssertFalse(kanto.isCompleted)

        // Add Vaporeon (134), Jolteon (135), Flareon (136)
        store.addDexEntries([
            DexEntry(baseID: 133, finalID: 134, chainOrder: [133, 134], rarity: .rare, caughtAt: now),
            DexEntry(baseID: 133, finalID: 135, chainOrder: [133, 135], rarity: .rare, caughtAt: now),
            DexEntry(baseID: 133, finalID: 136, chainOrder: [133, 136], rarity: .rare, caughtAt: now)
        ])
        XCTAssertTrue(store.achievements.first { $0.type == .eeveeKantoTrio }!.isCompleted)
        XCTAssertEqual(store.achievements.first { $0.type == .eeveeMaster }!.progress, 3)

        // Claim Kanto Eevees -> awards water stone
        XCTAssertEqual(store.itemCount(.waterStone), 0)
        XCTAssertTrue(store.claimAchievement(.eeveeKantoTrio))
        XCTAssertEqual(store.itemCount(.waterStone), 1)

        // Add Espeon (196), Umbreon (197), Leafeon (470), Glaceon (471)
        store.addDexEntries([
            DexEntry(baseID: 133, finalID: 196, chainOrder: [133, 196], rarity: .rare, caughtAt: now),
            DexEntry(baseID: 133, finalID: 197, chainOrder: [133, 197], rarity: .rare, caughtAt: now),
            DexEntry(baseID: 133, finalID: 470, chainOrder: [133, 470], rarity: .rare, caughtAt: now),
            DexEntry(baseID: 133, finalID: 471, chainOrder: [133, 471], rarity: .rare, caughtAt: now)
        ])
        XCTAssertTrue(store.achievements.first { $0.type == .eeveeJohtoDuo }!.isCompleted)
        XCTAssertTrue(store.achievements.first { $0.type == .eeveeSinnohDuo }!.isCompleted)
        XCTAssertTrue(store.achievements.first { $0.type == .eeveeMaster }!.isCompleted)

        let initialCandies = store.rareCandyCount
        let initialTokens = store.availableTokens
        XCTAssertTrue(store.claimAchievement(.eeveeMaster))
        XCTAssertEqual(store.rareCandyCount, initialCandies + 3)
        XCTAssertEqual(store.availableTokens, initialTokens + 100_000_000)
    }

    func testFossilAchievements() {
        let store = makeStore()
        let first = store.achievements.first { $0.type == .firstFossil }!
        let master = store.achievements.first { $0.type == .fossilMaster }!
        XCTAssertEqual(first.target, 1)
        XCTAssertEqual(master.target, 9)

        // Add Omastar (139)
        store.addDexEntry(DexEntry(baseID: 138, finalID: 139, chainOrder: [138, 139], rarity: .rare, caughtAt: now))
        XCTAssertTrue(store.achievements.first { $0.type == .firstFossil }!.isCompleted)
        XCTAssertEqual(store.achievements.first { $0.type == .fossilCollector }!.progress, 1)

        // Add Kabutops (141), Aerodactyl (142), Cradily (346), Armaldo (348), Rampardos (409), Bastiodon (411), Carracosta (565), Archeops (567)
        store.addDexEntries([
            DexEntry(baseID: 140, finalID: 141, chainOrder: [140, 141], rarity: .rare, caughtAt: now),
            DexEntry(baseID: 142, finalID: 142, chainOrder: [142], rarity: .rare, caughtAt: now),
            DexEntry(baseID: 345, finalID: 346, chainOrder: [345, 346], rarity: .rare, caughtAt: now),
            DexEntry(baseID: 347, finalID: 348, chainOrder: [347, 348], rarity: .rare, caughtAt: now),
            DexEntry(baseID: 408, finalID: 409, chainOrder: [408, 409], rarity: .rare, caughtAt: now),
            DexEntry(baseID: 410, finalID: 411, chainOrder: [410, 411], rarity: .rare, caughtAt: now),
            DexEntry(baseID: 564, finalID: 565, chainOrder: [564, 565], rarity: .rare, caughtAt: now),
            DexEntry(baseID: 566, finalID: 567, chainOrder: [566, 567], rarity: .rare, caughtAt: now)
        ])
        XCTAssertTrue(store.achievements.first { $0.type == .fossilCollector }!.isCompleted)
        XCTAssertTrue(store.achievements.first { $0.type == .fossilMaster }!.isCompleted)

        XCTAssertTrue(store.claimAchievement(.fossilCollector))
        XCTAssertEqual(store.itemCount(.magmaStone), 1)
    }

    func testStoneAndBagAchievements() {
        let store = makeStore()
        XCTAssertFalse(store.achievements.first { $0.type == .elementalStones }!.isCompleted)
        XCTAssertFalse(store.achievements.first { $0.type == .allStonesUsed }!.isCompleted)

        let testMon = MonState(
            baseID: 1,
            pathIDs: [1, 2, 3],
            stageIndex: 0,
            usedAtStage: 0,
            rarity: .starter,
            totalForms: 3
        )

        // Seed stones and active companion to use
        store.setInventoryForTesting([
            ItemKind.fireStone.rawValue: 1,
            ItemKind.waterStone.rawValue: 1,
            ItemKind.thunderStone.rawValue: 1
        ])
        store.setActiveForTesting(testMon)

        XCTAssertTrue(store.useStone(.fireStone))
        store.setActiveForTesting(testMon)
        XCTAssertTrue(store.useStone(.waterStone))
        store.setActiveForTesting(testMon)
        XCTAssertTrue(store.useStone(.thunderStone))

        XCTAssertTrue(store.achievements.first { $0.type == .elementalStones }!.isCompleted)
        XCTAssertEqual(store.achievements.first { $0.type == .allStonesUsed }!.progress, 3)

        // Bag collector (8 items)
        var bagItems: [String: Int] = [:]
        for kind in [ItemKind.rareCandy, .mint, .shinyCharm, .legendCharm, .silverWing, .clearBell, .rainbowWing, .magmaStone] {
            bagItems[kind.rawValue] = 1
        }
        store.setInventoryForTesting(bagItems)
        XCTAssertTrue(store.achievements.first { $0.type == .bagCollector }!.isCompleted)
    }

    func testShinyAndProductivityAchievements() {
        let store = makeStore()

        // Shiny starter
        store.addDexEntry(DexEntry(baseID: 1, finalID: 3, chainOrder: [1, 2, 3], rarity: .starter, caughtAt: now, isShiny: true))
        XCTAssertTrue(store.achievements.first { $0.type == .shinyLegendOrStarter }!.isCompleted)
        XCTAssertEqual(store.achievements.first { $0.type == .shinyTrio }!.progress, 1)

        // Streaks and tokens
        store.setQuestStateForTesting(bestStreak: 100)
        XCTAssertTrue(store.achievements.first { $0.type == .streak60 }!.isCompleted)
        XCTAssertTrue(store.achievements.first { $0.type == .streak100 }!.isCompleted)

        // Routine
        store.setQuestStateForTesting(
            nightOwlTriggered: true,
            earlyBirdTriggered: true,
            maxDailyTokens: 150_000_000
        )
        XCTAssertTrue(store.achievements.first { $0.type == .nightOwl }!.isCompleted)
        XCTAssertTrue(store.achievements.first { $0.type == .earlyBird }!.isCompleted)
        XCTAssertTrue(store.achievements.first { $0.type == .dailyMarathon }!.isCompleted)
    }
}

