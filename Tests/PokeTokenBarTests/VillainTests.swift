import AppKit
import XCTest
@testable import PokeTokenBar

/// The villains' teams (issue #180, the owner, 2026-11-10): the day's ambush, the defense, the theft, the hideout of
/// the item's tier and its leader's three (Giovanni with Mewtwo and Persian at the top).
@MainActor
final class VillainTests: XCTestCase {
    private final class Clock: @unchecked Sendable { var date: Date; init(_ date: Date) { self.date = date } }

    private func graduated(_ id: Int) -> DexEntry {
        var entry = DexEntry(baseID: SpeciesInfo.baseID(of: id), finalID: id, chainOrder: [id], rarity: .common,
                             caughtAt: Date(timeIntervalSince1970: 1_790_000_000))
        entry.id = "g\(id)"
        return entry
    }

    private func store(dex: [DexEntry], clock: Clock, prepare: (inout CompanionState) -> Void = { _ in }) throws -> CompanionStore {
        var st = CompanionState()
        st.installBaselineSet = true
        st.lastDate = "d"
        st.claimedTodayTokensByProvider = ["test": 0]
        st.dex = dex
        st.active = MonState(baseID: 16, pathIDs: [16, 17, 18], stageIndex: 0, usedAtStage: 0, rarity: .common, totalForms: 3)
        prepare(&st)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("villain-\(UUID().uuidString).json")
        try JSONEncoder().encode(st).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return CompanionStore(provider: StubProvider(value: EvoLine(baseID: 16, tree: EvoNode(speciesID: 16, children: []),
                                                                    rarity: .common, names: [:])),
                              clock: { clock.date }, fileURL: url, rng: SeededRNG(seed: 3), difficulty: 0.1)
    }

    private func date(_ day: Int, hour: Int, minute: Int = 0, month: Int = 11) throws -> Date {
        var parts = DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute)
        parts.timeZone = .current
        return try XCTUnwrap(Calendar(identifier: .iso8601).date(from: parts))
    }

    private var strong: [DexEntry] { [150, 384, 248, 445, 149, 376].map(graduated) }
    private var achievementArtifact: ItemKind {
        ItemKind.allCases.first { $0.isPassive && $0.isAchievement && !$0.isRegional && $0.moreFormsSpecies == nil }!
    }

    func testWhatTheyGoFor() {
        XCTAssertEqual(VillainRules.tier(of: .rareCandy), .t1)
        XCTAssertEqual(VillainRules.tier(of: .leafStone), .t2)
        XCTAssertEqual(VillainRules.tier(of: .rareEgg), .t3)
        XCTAssertEqual(VillainRules.tier(of: .masterBall), .t4)
        XCTAssertEqual(VillainRules.tier(of: achievementArtifact), .t5, "an achievement's artifact, the big prize")
        XCTAssertNil(VillainRules.tier(of: .boulderBadge), "a badge's steps are counted apart")
        XCTAssertNil(VillainRules.tier(of: .discoveryMedal))
        var random = BattleRandom(seed: 1)
        let target = try? XCTUnwrap(VillainRules.target([.rareCandy: 7, .boulderBadge: 1], random: &random))
        XCTAssertEqual(target?.kind, .rareCandy)
        XCTAssertEqual(target?.count, 3, "half the stack of an everyday item, three at least")
        XCTAssertNil(VillainRules.target([.boulderBadge: 1], random: &random), "nothing they would take")
    }

    /// Every day, at a minute from 8:00 to 17:30 (the owner, 2026-11-13), the same on every launch; one team a tier,
    /// Team Rocket at the top.
    func testTheDaysDraw() throws {
        let calendar = Calendar(identifier: .iso8601)
        let days = (0..<3000).map { n -> String in
            let c = calendar.dateComponents([.year, .month, .day], from: Date(timeIntervalSince1970: 1_790_000_000 + Double(n) * 86_400))
            return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        }
        let minutes = days.map(VillainRules.minute)
        XCTAssertTrue(minutes.allSatisfy { (480...1050).contains($0) }, "8:00 to 17:30")
        XCTAssertTrue(minutes.contains { $0 < 9 * 60 } && minutes.contains { $0 > 17 * 60 }, "the whole span drawn")
        XCTAssertEqual(minutes.filter { $0 < 12 * 60 + 45 }.count, 1500, accuracy: 150, "evenly")
        XCTAssertEqual(VillainRules.minute("2026-11-10"), VillainRules.minute("2026-11-10"))
        XCTAssertEqual(DungeonTier.allCases.map(VillainTeam.team), [.skull, .magma, .aqua, .galactic, .rocket])
        XCTAssertTrue(VillainTeam.allCases.allSatisfy { VillainTeam.team(for: $0.tier) == $0 })
    }

    /// The day 2026-11-`day` and the minute its team comes at.
    private func coming(_ day: Int = 14) -> (day: Int, hour: Int, minute: Int) {
        let minute = VillainRules.minute(String(format: "2026-11-%02d", day))
        return (day, minute / 60, minute % 60)
    }

    private func ambush(_ team: VillainTeam, _ item: ItemKind, count: Int = 1, at: Date) -> VillainAmbush {
        VillainAmbush(id: "x-\(item.rawValue)", team: team, item: item.rawValue, count: count, at: at, seed: 7, grunts: team.grunts.prefix(3).map { $0 })
    }

    /// They come at their hour and take the item as they come (the owner, 2026-11-10: else no one would fight them).
    func testTheyTakeItAsTheyCome() throws {
        let (day, hour, minute) = coming()
        let clock = Clock(try date(day, hour: hour, minute: minute).addingTimeInterval(-60))
        let s = try store(dex: strong, clock: clock) {
            $0.dungeons.wins[DungeonID.viridianForest.rawValue] = 1
            $0.inventory = ["rareCandy": 5]
        }
        s.settleVillainAmbush()
        XCTAssertTrue(s.villainAmbushes.isEmpty, "a minute before their minute")
        clock.date = try date(day, hour: hour, minute: minute)
        s.settleVillainAmbush()
        let theft = try XCTUnwrap(s.villainAmbushes.first)
        XCTAssertEqual(theft.kind, .rareCandy)
        XCTAssertEqual(theft.team, .skull, "a T1 item, Team Skull")
        XCTAssertEqual(theft.count, 3)
        XCTAssertEqual(s.itemCount(.rareCandy), 2, "taken as they came")
        XCTAssertEqual(s.villainStash(.skull)?.items, ["rareCandy": 3])
        XCTAssertTrue(s.isDungeonOpen(.skullHideout), "their hideout opens at once")
        XCTAssertFalse(s.isDungeonOpen(.rocketHideout))
        s.settleVillainAmbush()
        XCTAssertEqual(s.villainAmbushes.count, 1, "once a day")
        // No dungeon won yet: no team comes, and the day is settled.
        let newcomer = try store(dex: strong, clock: clock) { $0.inventory = ["rareCandy": 5] }
        newcomer.settleVillainAmbush()
        XCTAssertTrue(newcomer.villainAmbushes.isEmpty)
        XCTAssertEqual(newcomer.itemCount(.rareCandy), 5)
        XCTAssertEqual(newcomer.dungeonProgress.villainDay, String(format: "2026-11-%02d", day))
    }

    /// "Later" folds the card to a banner; it stays until the theft is settled (the owner, 2026-11-10).
    func testLaterFoldsItNeverDrops() throws {
        let clock = Clock(try date(10, hour: 12))
        let s = try store(dex: strong, clock: clock) {
            $0.dungeons.stashes = [VillainStash(team: .skull, items: ["rareCandy": 3])]
            $0.dungeons.ambushes = [self.ambush(.skull, .rareCandy, count: 3, at: clock.date)]
        }
        let id = try XCTUnwrap(s.villainAmbushes.first?.id)
        s.setVillainAmbushCollapsed(id, true)
        XCTAssertEqual(s.villainAmbushes.first?.collapsed, true)
        s.dismissVillainAmbush(id)
        XCTAssertEqual(s.villainAmbushes.count, 1, "not settled: it stays, folded")
        s.setVillainAmbushCollapsed(id, false)
        XCTAssertNil(s.villainAmbushes.first?.collapsed)
        XCTAssertEqual(s.defendAgainstAmbush(id), true)
        s.dismissVillainAmbush(id)
        XCTAssertTrue(s.villainAmbushes.isEmpty, "settled: it goes")
    }

    /// Thefts add up, ignored or not, each team to its hideout, one a day and every day (the owner, 2026-11-13); none
    /// once nothing is left to take, and a team only for what it is after (no Team Rocket without an achievement's
    /// artifact).
    func testTheftsAddUp() throws {
        let clock = Clock(try date(10, hour: 0))
        let s = try store(dex: strong, clock: clock) {
            $0.dungeons.wins[DungeonID.viridianForest.rawValue] = 1
            $0.inventory = ["rareCandy": 2, "leafStone": 1]
        }
        var thefts: [String] = []
        for day in 10...14 {
            clock.date = try date(day, hour: 17, minute: 30)
            let before = s.villainAmbushes.count
            s.settleVillainAmbush()
            s.settleVillainAmbush()
            XCTAssertLessThanOrEqual(s.villainAmbushes.count - before, 1, "one a day")
            if s.villainAmbushes.count > before { thefts.append(s.villainAmbushes[0].item) }
        }
        XCTAssertEqual(thefts.count, 2, "two days running, then nothing left: \(thefts)")
        XCTAssertEqual(Set(thefts), ["rareCandy", "leafStone"], "both taken, the first theft never chased")
        XCTAssertEqual(s.itemCount(.rareCandy) + s.itemCount(.leafStone), 0, "nothing left: no one comes any more")
        XCTAssertEqual(Set(s.villainStashes.map(\.team)), [.skull, .magma], "each team to its hideout")
        XCTAssertFalse(s.villainAmbushes.contains { $0.team == .rocket }, "no artifact, no Team Rocket")
    }

    /// [Regression] Their minute passing while a team explored, the day was lost: the owner's two-day Cerulean Cave run
    /// of 2026-11-10 took both days they were due. They now wait for the team's return (the owner, 2026-11-13), then
    /// come once, even days later.
    func testTheyWaitForTheTeamsReturn() throws {
        let (day, hour, minute) = coming()
        let clock = Clock(try date(day, hour: 7))
        let s = try store(dex: strong, clock: clock) {
            $0.dungeons.wins[DungeonID.viridianForest.rawValue] = 1
            $0.inventory = ["rareCandy": 9]
        }
        XCTAssertTrue(s.startExpedition(.viridianForest, team: strong.prefix(3).map(\.id)))
        clock.date = try date(day, hour: hour, minute: minute)
        s.settleVillainAmbush()
        XCTAssertTrue(s.villainAmbushes.isEmpty, "the team away")
        clock.date = try date(day + 1, hour: 18)
        s.settleVillainAmbush()
        XCTAssertTrue(s.villainAmbushes.isEmpty, "still away the next day")
        s.changeDungeons { $0.expedition = nil }
        s.settleVillainAmbush()
        XCTAssertEqual(s.villainAmbushes.count, 1, "back: they come")
        s.settleVillainAmbush()
        XCTAssertEqual(s.villainAmbushes.count, 1, "once, not once for each day away")
        clock.date = try date(day + 2, hour: 17, minute: 30)
        s.settleVillainAmbush()
        XCTAssertEqual(s.villainAmbushes.count, 2, "the next day, at their minute")
    }

    /// The chase lost: the item stays at the hideout, with no key. Won: it comes back and the hideout closes.
    func testTheChase() throws {
        let artifact = achievementArtifact
        let clock = Clock(try date(10, hour: 12))
        let weak = [129, 349, 10].map(graduated)
        func stolen(_ dex: [DexEntry]) throws -> CompanionStore {
            try store(dex: dex, clock: clock) {
                $0.dungeons.stashes = [VillainStash(team: .rocket, items: [artifact.rawValue: 1])]
                $0.dungeons.ambushes = [self.ambush(.rocket, artifact, at: clock.date)]
            }
        }
        let s = try stolen(weak)
        let id = try XCTUnwrap(s.villainAmbushes.first?.id)
        XCTAssertEqual(s.defendAgainstAmbush(id), false, "three Magikarp and kin against Team Rocket's grunts")
        XCTAssertEqual(s.itemCount(artifact), 0)
        XCTAssertEqual(s.villainStash(.rocket)?.items, [artifact.rawValue: 1])
        XCTAssertTrue(s.isDungeonOpen(.rocketHideout))
        XCTAssertEqual(s.keysToEnter(.rocketHideout), 0)
        XCTAssertEqual(s.dungeonInfo(.rocketHideout).tier, .t5)
        XCTAssertEqual(s.dungeonInfo(.rocketHideout).bosses, [150], "Giovanni's Mewtwo")
        XCTAssertNotNil(s.villainAmbushes.first?.battle, "the fight can be watched")
        XCTAssertNil(s.defendAgainstAmbush(id), "chased once")
        // Team Skull's grunts (T1) against Mewtwo, Rayquaza and kin: a chase they win nine times in ten, here with seed 7.
        let caught = try store(dex: strong, clock: clock) {
            $0.inventory = ["rareCandy": 2]
            $0.dungeons.stashes = [VillainStash(team: .skull, items: ["rareCandy": 3])]
            $0.dungeons.ambushes = [self.ambush(.skull, .rareCandy, count: 3, at: clock.date)]
        }
        XCTAssertEqual(caught.defendAgainstAmbush(try XCTUnwrap(caught.villainAmbushes.first?.id)), true)
        XCTAssertEqual(caught.itemCount(.rareCandy), 5, "back in the Bag")
        XCTAssertNil(caught.villainStash(.skull))
        XCTAssertFalse(caught.isDungeonOpen(.skullHideout))
    }

    /// An achievement's artifact taken as they come stays claimed: never claimed twice.
    func testAStolenArtifactStaysClaimed() throws {
        let artifact = achievementArtifact
        let (day, hour, minute) = coming()
        let clock = Clock(try date(day, hour: hour, minute: minute))
        let s = try store(dex: strong, clock: clock) {
            $0.dungeons.wins[DungeonID.viridianForest.rawValue] = 1
            $0.inventory = [artifact.rawValue: 1]
            $0.claimedAchievements = []
        }
        s.settleVillainAmbush()
        XCTAssertEqual(s.villainAmbushes.first?.team, .rocket, "an achievement's artifact, Team Rocket")
        XCTAssertEqual(s.itemCount(artifact), 0)
        XCTAssertTrue(s.isClaimed(artifact))
    }

    /// The hideout's leader beaten gives everything back, settles its team's thefts and closes it; it counts for no
    /// dungeon's wins nor bosses.
    func testTheHideoutGivesItAllBack() throws {
        let clock = Clock(try date(10, hour: 12))
        let s = try store(dex: strong, clock: clock) {
            $0.dungeons.stashes = [VillainStash(team: .rocket, items: ["shinyCharm": 1, "masterBall": 1]),
                                   VillainStash(team: .skull, items: ["rareCandy": 3])]
            $0.dungeons.ambushes = [self.ambush(.rocket, .shinyCharm, at: clock.date)]
        }
        XCTAssertTrue(s.startExpedition(.rocketHideout, team: strong.map(\.id)))
        XCTAssertEqual(s.expedition?.boss.speciesID, 150, "Giovanni's Mewtwo leads")
        XCTAssertEqual(s.expedition?.boss.form, ArmoredMewtwo.form)
        // Half the tier's floors, at half its price (the owner, 2026-11-17).
        XCTAssertEqual(s.expedition?.floors, 8)
        XCTAssertEqual(DungeonCatalog.dungeon(.rocketHideout).cost(difficulty: 1),
                       DungeonTier.t5.cost(difficulty: 1) * 8 / DungeonTier.t5.floors)
        XCTAssertEqual(DungeonCatalog.dungeon(.skullHideout).floors, 3)
        XCTAssertEqual(DungeonCatalog.dungeon(.mtMoon).floors, DungeonTier.t2.floors, "a dungeon keeps its own")
        XCTAssertNil(s.expedition?.bossReward)
        s.changeDungeons { $0.expedition?.phase = .capture(throwsLeft: 3) }
        s.endCapture()
        XCTAssertEqual(s.itemCount(.shinyCharm), 1)
        XCTAssertGreaterThanOrEqual(s.itemCount(.masterBall), 2, "the one taken back, and the leader's chest's (2026-11-16)")
        XCTAssertGreaterThanOrEqual(s.itemCount(.legendaryEgg), 1, "Team Rocket's chest: a Legendary Egg")
        XCTAssertEqual(s.dungeonProgress.lastResult?.loot.items[ItemKind.legendaryEgg.rawValue].map { $0 >= 1 }, true)
        XCTAssertNil(s.villainStash(.rocket))
        XCTAssertNotNil(s.villainStash(.skull), "another team's hideout stays")
        XCTAssertTrue(s.villainAmbushes.isEmpty, "its theft is settled with it")
        XCTAssertFalse(s.isDungeonOpen(.rocketHideout))
        XCTAssertEqual(s.dungeonProgress.lastResult?.recovered, ["shinyCharm": 1, "masterBall": 1])
        XCTAssertEqual(s.dungeonProgress.lastResult?.villain, .rocket)
        XCTAssertEqual(s.dungeonProgress.wins(.rocketHideout), 0)
        XCTAssertTrue(s.dungeonProgress.bossesBeaten.isEmpty, "Giovanni's Mewtwo opens nothing")
    }

    /// The owner, 2026-11-16: "les vols les moins oufs plus chiants". Half the stack of an everyday item, three at
    /// least and twenty at most; up to three of a T2 item; one of the rest.
    func testTheyTakeMoreOfAnEverydayItem() {
        XCTAssertEqual([2, 5, 10, 40, 100].map { VillainRules.count(of: .rareCandy, have: $0) }, [2, 3, 5, 20, 20])
        XCTAssertEqual([1, 2, 7].map { VillainRules.count(of: .ultraBall, have: $0) }, [1, 2, 3])
        XCTAssertEqual(VillainRules.count(of: .rareEgg, have: 4), 1)
        XCTAssertEqual(VillainRules.count(of: .masterBall, have: 3), 1)
    }

    /// [Regression] The owner, 2026-11-16: back from a dungeon, a player used its loot and set off again, never robbed.
    /// The thieves due strike at the team's return and take what it brought: every Rare Candy, else its most precious
    /// item; nothing they would take, a Bag item as before.
    func testTheyStrikeAtTheReturnOnTheLoot() throws {
        let (day, hour, minute) = coming()
        let clock = Clock(try date(day, hour: hour, minute: minute).addingTimeInterval(60))
        func robbed(_ loot: ExpeditionLoot, bag: [String: Int]) throws -> VillainAmbush? {
            let s = try store(dex: strong, clock: clock) {
                $0.dungeons.wins[DungeonID.viridianForest.rawValue] = 1
                $0.inventory = bag
            }
            s.settleVillainAmbush(runLoot: loot)
            return s.villainAmbushes.first
        }
        let candies = try XCTUnwrap(robbed(ExpeditionLoot(candies: 4), bag: ["rareCandy": 10, "ultraBall": 1]))
        XCTAssertEqual(candies.kind, .rareCandy)
        XCTAssertEqual(candies.count, 4, "every candy the run brought")
        let best = try XCTUnwrap(robbed(ExpeditionLoot(items: ["ultraBall": 1, "oranBerry": 2]), bag: ["ultraBall": 1, "oranBerry": 2]))
        XCTAssertEqual(best.kind, .ultraBall, "the most precious item it brought")
        XCTAssertEqual(best.count, 1)
        XCTAssertNotNil(try robbed(ExpeditionLoot(), bag: ["rareCandy": 5]), "nothing brought: a Bag item, as before")
        // A whole run: the team set off before their minute and comes back after it; they strike as it returns.
        clock.date = try date(day, hour: 7)
        let s = try store(dex: strong, clock: clock) {
            $0.dungeons.wins[DungeonID.viridianForest.rawValue] = 1
            $0.inventory = ["rareCandy": 5]
        }
        XCTAssertTrue(s.startExpedition(.viridianForest, team: strong.prefix(3).map(\.id)))
        clock.date = try date(day, hour: hour, minute: minute).addingTimeInterval(60)
        var total = 0
        for _ in 0..<200 where s.expedition != nil {
            total += DungeonTier.t1.cost(difficulty: 0.1) / 5
            s.update(todayTokensByProvider: ["test": total], todayDate: "d", monthTotal: 0, burnTier: .idle,
                     limitWarning: false, hasUsageData: true)
            if case .awaitingHeal? = s.expedition?.phase { s.answerEmergencyHeal(pay: false) }
        }
        XCTAssertNil(s.expedition, "back")
        XCTAssertEqual(s.villainAmbushes.count, 1, "robbed at the return, no popover opened")
    }

    /// The owner, 2026-11-16: what they took may be given up, gone for good, its thefts settled; never an artifact, and
    /// the hideout closes once nothing is left.
    func testWhatTheyTookCanBeGivenUp() throws {
        let clock = Clock(try date(10, hour: 12))
        let s = try store(dex: strong, clock: clock) {
            $0.dungeons.stashes = [VillainStash(team: .rocket, items: ["rareCandy": 3, "shinyCharm": 1]),
                                   VillainStash(team: .skull, items: ["rareCandy": 3])]
            $0.dungeons.ambushes = [self.ambush(.rocket, .rareCandy, count: 3, at: clock.date),
                                    self.ambush(.rocket, .shinyCharm, at: clock.date)]
        }
        XCTAssertTrue(s.abandonStolen(.rocket))
        XCTAssertEqual(s.villainStash(.rocket)?.items, ["shinyCharm": 1], "the artifact stays to win back")
        XCTAssertEqual(s.villainAmbushes.map(\.item), ["shinyCharm"], "the candies' theft settled with them")
        XCTAssertFalse(s.abandonStolen(.rocket), "an artifact is never given up")
        XCTAssertTrue(s.isDungeonOpen(.rocketHideout))
        XCTAssertTrue(s.abandonStolen(.skull))
        XCTAssertNil(s.villainStash(.skull))
        XCTAssertFalse(s.isDungeonOpen(.skullHideout), "nothing left: the hideout closes")
        XCTAssertEqual(s.itemCount(.rareCandy), 0, "gone for good")
    }

    /// [Regression] The owner, 2026-11-16: beaten by Team Skull's grunts with the six highest base stats, two Slaking
    /// (Truant) and Regigigas (Slow Start) among them, 8% of the chases won. Without Mon équipe, the chase takes the team
    /// that wins it most, each species once.
    func testTheChaseTakesTheTeamThatWins() throws {
        var dex = [150, 384, 248, 445, 149, 376, 486].map(graduated)
        for i in 0..<2 {
            var slaking = graduated(289)
            slaking.id = "slaking\(i)"
            dex.append(slaking)
        }
        let clock = Clock(try date(10, hour: 12))
        let s = try store(dex: dex, clock: clock)
        let theft = VillainAmbush(id: "x", team: .skull, item: "oranBerry", count: 3, at: clock.date, seed: 7, grunts: [758, 760, 89])
        let mine = s.ambushDefenders(for: theft)
        XCTAssertEqual(mine.count, 6)
        XCTAssertEqual(Set(mine.map(\.speciesID)).count, 6, "each species once")
        let foes = VillainRules.gruntSpecs(theft.grunts, tier: theft.tier, seed: theft.seed)
        func wins(_ team: [BattlerSpec]) -> Int {
            (0..<16).filter { run in
                BattleEngine.run(BattleSetup(sides: [BattleSideSpec(battlers: team, active: 1), BattleSideSpec(battlers: foes, active: 1)],
                                             seed: 31 &+ UInt64(run) &* 104_729)).winner == 0
            }.count
        }
        let targets = (theme: theft.team.themeTypes, bosses: theft.grunts.map { PokemonTypeData.types(forSpeciesID: $0) })
        let strongest = dex.sorted {
            (SpeciesBattleTable.data(speciesID: $0.finalID, form: nil)?.baseStats.reduce(0, +) ?? 0)
                > (SpeciesBattleTable.data(speciesID: $1.finalID, form: nil)?.baseStats.reduce(0, +) ?? 0)
        }.prefix(6).compactMap { s.dungeonSpec($0, for: nil, targets: targets) }
        XCTAssertGreaterThanOrEqual(wins(mine), wins(strongest), "at least the old pick's chases")
    }

    func testTheLeaderComesWithThree() throws {
        var random = BattleRandom(seed: 3)
        let giovanni = VillainRules.leaderSpecs(.rocket, tier: .t5, random: &random)
        XCTAssertEqual(giovanni.map(\.speciesID), [150, 53, 34], "Mewtwo, Persian and Nidoking (the owner)")
        XCTAssertEqual(giovanni.first?.form, ArmoredMewtwo.form, "Team Rocket's armored Mewtwo")
        let plain = try XCTUnwrap(BattlerSpec.make(id: "m", speciesID: 150, level: 100))
        let armored = try XCTUnwrap(BattlerSpec.make(id: "m", speciesID: 150, form: ArmoredMewtwo.form, level: 100))
        XCTAssertEqual(armored.stats, plain.stats, "Mewtwo's own battle data")
        XCTAssertEqual(SpriteStore.spriteURLs(speciesID: 150, animated: true, shiny: false, form: ArmoredMewtwo.form).first?.absoluteString,
                       ArmoredMewtwo.spriteURL)
        XCTAssertTrue(giovanni.allSatisfy(\.isBoss))
        for team in VillainTeam.allCases {
            XCTAssertEqual(VillainRules.leaderSpecs(team, tier: team.tier, random: &random).count, 3, "\(team)")
            XCTAssertTrue(team.grunts.allSatisfy { SpeciesBattleTable.data(speciesID: $0, form: nil) != nil }, "\(team)")
            XCTAssertNotNil(VillainTeam.portraitURLs[team.gruntPortrait])
            XCTAssertNotNil(VillainTeam.portraitURLs[team.leaderPortrait])
        }
    }

    /// Each team's hideout has its own diorama (the owner, 2026-11-10), for its card and the menu bar.
    func testEachHideoutHasItsDiorama() throws {
        var seen: [Data] = []
        for team in VillainTeam.allCases {
            let image = try XCTUnwrap(DungeonSprites.hideoutImage(team), "\(team)")
            XCTAssertNotNil(DungeonSprites.trimmedHideoutImage(team), "\(team)")
            let data = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
            XCTAssertFalse(seen.contains(data), "\(team) drawn as another")
            seen.append(data)
        }
    }

    func testTheHideoutCountsForNothingElse() throws {
        for tier in DungeonTier.allCases {
            XCTAssertFalse(DungeonMedals.dungeons(tier).contains { $0.isHideout })
        }
        let s = try store(dex: strong, clock: Clock(try date(10, hour: 12))) { $0.dungeons.wins[DungeonID.skullHideout.rawValue] = 3 }
        XCTAssertFalse(s.isMet(.wonTier(.t1)))
        XCTAssertFalse(s.isDungeonOpen(.skullHideout), "no stash, no hideout")
        XCTAssertEqual(VillainTeam.allCases.map { DungeonCatalog.dungeon($0.hideoutID).tier }, DungeonTier.allCases)
    }

    func testTheirWordsInEveryLanguage() {
        for language in AppLanguage.allCases {
            let l = L(language)
            var words = [l.villainAmbushBubble, l.villainTheirPokemon, l.villainDefend, l.villainDefendWith, l.villainLater, l.villainSeeFight,
                         l.villainToHideout, l.villainKeeps, l.villainTakenBack] + VillainTeam.allCases.map { l.dungeonName($0.hideoutID) }
            for team in VillainTeam.allCases {
                words += [l.villainTeamName(team), l.villainLeaderName(team), l.villainAmbushTitle(team),
                          l.villainStoleLine(team, item: "X"), l.villainBeaten(team, item: "X"), l.villainGotAway(team, item: "X"),
                          l.villainHideoutName(team), l.villainWaitsAtTheEnd(team)]
            }
            for text in words {
                XCTAssertFalse(text.isEmpty || text.contains("\u{2014}") || text.contains("\u{2013}"), "\(language): \(text)")
            }
        }
    }
}
