import XCTest
@testable import PokeTokenBar

/// The dungeons in the game: the save, what opens them, the departure, the tokens walking the team, the answers and
/// the end, its loot in the Bag.
@MainActor
final class DungeonStoreTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func graduated(_ id: Int, rarity: Rarity = .common) -> DexEntry {
        var entry = DexEntry(baseID: SpeciesInfo.baseID(of: id), finalID: id, chainOrder: [id], rarity: rarity, caughtAt: now)
        entry.id = "e\(id)"
        return entry
    }

    private func store(dex: [DexEntry], inventory: [ItemKind: Int] = [:], used: Int = 0,
                       prepare: (inout CompanionState) -> Void = { _ in }) throws -> CompanionStore {
        var st = CompanionState()
        st.installBaselineSet = true
        st.lastDate = "d"
        st.claimedTodayTokensByProvider = ["test": 0]
        st.usedSinceInstall = used
        st.dex = dex
        st.active = MonState(baseID: 16, pathIDs: [16, 17, 18], stageIndex: 0, usedAtStage: 0, rarity: .common, totalForms: 3)
        st.inventory = Dictionary(uniqueKeysWithValues: inventory.map { ($0.key.rawValue, $0.value) })
        // The day's thieves already came: they would rob a run's return (2026-11-16), which these tests do not test.
        st.dungeons.villainDay = DungeonProgress.challengePeriod(.daily, at: now)
        prepare(&st)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("dungeon-\(UUID().uuidString).json")
        try JSONEncoder().encode(st).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return CompanionStore(provider: StubProvider(value: EvoLine(baseID: 16, tree: EvoNode(speciesID: 16, children: []),
                                                                    rarity: .common, names: [:])),
                              clock: { self.now }, fileURL: url, rng: SeededRNG(seed: 3), difficulty: 0.1)
    }

    private var strong: [DexEntry] { [6, 9, 3, 25, 143, 130].map { graduated($0) } }

    private func credit(_ s: CompanionStore, total: Int) {
        s.update(todayTokensByProvider: ["test": total], todayDate: "d", monthTotal: 0, burnTier: .idle,
                 limitWarning: false, hasUsageData: true)
    }

    // MARK: The save

    /// A save from before the dungeons decodes with none, and a dungeon's state comes back whole.
    func testTheSaveKeepsTheDungeons() throws {
        let old = #"{"installBaselineSet":true,"usedSinceInstall":5,"dex":[],"inventory":{}}"#
        let decoded = try JSONDecoder().decode(CompanionState.self, from: Data(old.utf8))
        XCTAssertEqual(decoded.dungeons, DungeonProgress())
        var st = CompanionState()
        st.dungeons.wins["viridianForest"] = 2
        st.dungeons.unlockedMoves = ["earthquake"]
        st.dungeons.moveLoops["e6"] = ["flamethrower"]
        st.dungeons.eggs = [DungeonEgg(id: "x", baseID: 4, form: nil, isShiny: true, sourceSpeciesID: 6)]
        let back = try JSONDecoder().decode(CompanionState.self, from: JSONEncoder().encode(st))
        XCTAssertEqual(back.dungeons, st.dungeons)
        let broken = #"{"dungeons":{"wins":"oops","unlockedMoves":["surf"]}}"#
        let lenient = try JSONDecoder().decode(CompanionState.self, from: Data(broken.utf8))
        XCTAssertEqual(lenient.dungeons.unlockedMoves, ["surf"], "a damaged field costs only itself")
    }

    // MARK: Opening

    /// Every dungeon of a tier won, as a save holds it.
    private static func winEvery(_ tier: DungeonTier, _ st: inout CompanionState) {
        for id in DungeonMedals.dungeons(tier) { st.dungeons.wins[id.rawValue] = 1 }
    }

    /// A tier opens once every dungeon of the one before is won (the owner, 2026-11-05), not one of them; a dungeon won
    /// before that rule stays open.
    func testWhatOpensTheDungeons() throws {
        let five = try store(dex: Array(strong.prefix(5)))
        XCTAssertFalse(five.isDungeonOpen(.viridianForest), "six graduated open the first dungeons")
        let six = try store(dex: strong)
        XCTAssertTrue(six.isDungeonOpen(.viridianForest))
        XCTAssertTrue(six.isDungeonOpen(.diglettsCave))
        XCTAssertFalse(six.isDungeonOpen(.mtMoon))
        let one = try store(dex: strong) { $0.dungeons.wins["viridianForest"] = 1 }
        XCTAssertFalse(one.isDungeonOpen(.mtMoon), "one T1 of two no longer opens the T2")
        XCTAssertFalse(one.isDungeonOpen(.mtEmber))
        let both = try store(dex: strong) { Self.winEvery(.t1, &$0) }
        XCTAssertTrue(both.isDungeonOpen(.mtMoon))
        XCTAssertTrue(both.isDungeonOpen(.mtEmber))
        XCTAssertFalse(both.isDungeonOpen(.victoryRoad), "Mt. Moon and Mt. Ember both")
        let threeOfFour = try store(dex: strong) {
            Self.winEvery(.t1, &$0)
            Self.winEvery(.t2, &$0)
            for id in DungeonMedals.dungeons(.t3).dropLast() { $0.dungeons.wins[id.rawValue] = 1 }
        }
        XCTAssertFalse(threeOfFour.isDungeonOpen(.seafoamIslands), "every T3, not three of four")
        XCTAssertTrue(threeOfFour.isDungeonOpen(DungeonMedals.dungeons(.t3).last!), "its own tier opened by the T2")
        let seafoam = try store(dex: strong) { Self.winEvery(.t3, &$0) }
        XCTAssertTrue(seafoam.isDungeonOpen(.seafoamIslands))
        XCTAssertFalse(seafoam.canEnter(.seafoamIslands), "a T4 takes a Legendary Key")
        let keyed = try store(dex: strong, inventory: [.legendaryKey: 1]) { Self.winEvery(.t3, &$0) }
        XCTAssertTrue(keyed.canEnter(.seafoamIslands))
        let grandfathered = try store(dex: strong) {
            $0.dungeons.wins["dragonsDen"] = 1
            $0.dungeons.wins["seafoamIslands"] = 1
        }
        XCTAssertTrue(grandfathered.isDungeonOpen(.seafoamIslands), "won under the former rule, still open")
        XCTAssertFalse(grandfathered.isDungeonOpen(.ceruleanCave))
        XCTAssertFalse(try store(dex: strong).isDungeonOpen(.ruinsOfAlph))
        XCTAssertTrue(try store(dex: strong, inventory: [.treasureMap: 1]).isDungeonOpen(.ruinsOfAlph))
        let origin = try store(dex: strong) {
            Self.winEvery(.t4, &$0)
            $0.dungeons.bossesBeaten = ["mtCoronet:483", "mtCoronet:484"]
        }
        XCTAssertFalse(origin.isDungeonOpen(.hallOfOrigin))
        let all = try store(dex: strong) {
            Self.winEvery(.t4, &$0)
            $0.dungeons.bossesBeaten = ["mtCoronet:483", "mtCoronet:484", "mtCoronet:487"]
        }
        XCTAssertTrue(all.isDungeonOpen(.hallOfOrigin))
        // One Legendary Key, as a T4, since 2026-11-09 (the owner): three made Arceus about 5B tokens away.
        XCTAssertEqual(all.keysToEnter(.hallOfOrigin), 1)
        XCTAssertFalse(all.canEnter(.hallOfOrigin), "no key in the Bag")
        let oneKey = try store(dex: strong, inventory: [.legendaryKey: 1]) {
            Self.winEvery(.t4, &$0)
            $0.dungeons.bossesBeaten = ["mtCoronet:483", "mtCoronet:484", "mtCoronet:487"]
        }
        XCTAssertTrue(oneKey.canEnter(.hallOfOrigin), "one key is enough")
        // Mt. Coronet's three bosses are its only door (the owner, 2026-11-10): no T4 to win besides.
        let bossesOnly = try store(dex: strong) { $0.dungeons.bossesBeaten = ["mtCoronet:483", "mtCoronet:484", "mtCoronet:487"] }
        XCTAssertTrue(bossesOnly.isDungeonOpen(.hallOfOrigin), "the three bosses alone")
        XCTAssertEqual(DungeonCatalog.dungeon(.hallOfOrigin).unlocks, [.beatBosses([483, 484, 487])])
    }

    /// [Regression] The owner, 2026-11-13: Viridian Forest gave him the same boss twice while two were never caught there.
    /// The draw takes the bosses not caught in the dungeon first, all of them once every one is.
    func testTheBossesNotCaughtComeFirst() throws {
        let s = try store(dex: strong) { $0.dungeons.bossesCaught = ["viridianForest:15", "viridianForest:12"] }
        XCTAssertEqual(s.dungeonInfo(.viridianForest).bosses, [45], "only Pidgeot is left to catch")
        let context = ExpeditionContext(tier: .t1, shinyDenominator: 64, now: now)
        let members = strong.prefix(3).compactMap { entry in
            DungeonTeamBuilder.spec(for: entry).map { ExpeditionMember(entryID: entry.id, spec: $0) }
        }
        for seed in 0..<40 as Range<UInt64> {
            let e = ExpeditionEngine.start(dungeon: s.dungeonInfo(.viridianForest), team: members, rules: [], teamSize: 3,
                                           seed: seed, cost: 1, berries: [:], revives: [:], context: context)
            XCTAssertEqual(e.boss.speciesID, 45, "seed \(seed)")
        }
        XCTAssertTrue(s.startExpedition(.viridianForest, team: strong.prefix(3).map(\.id)))
        XCTAssertEqual(s.expedition?.boss.speciesID, 45)
        let all = try store(dex: strong) { $0.dungeons.bossesCaught = ["viridianForest:15", "viridianForest:12", "viridianForest:45"] }
        XCTAssertEqual(all.dungeonInfo(.viridianForest).bosses, [15, 12, 45], "all caught: any of them again")
        let caughtElsewhere = try store(dex: strong) { $0.dungeons.bossesCaught = ["diglettsCave:15"] }
        XCTAssertEqual(caughtElsewhere.dungeonInfo(.viridianForest).bosses, [15, 12, 45], "caught in its own dungeon only")
        XCTAssertEqual(s.dungeonInfo(.daily).bosses, DungeonCatalog.dungeon(.daily).bosses)
    }

    /// Mt. Coronet opens once every boss of the ten dungeons listed before it is caught in its dungeon (the owner,
    /// 2026-11-10, then 2026-11-12: one had from an egg counted, so it opened with no boss caught), its other doors still
    /// asked; the Ruins of Alph, the challenges and the hideouts count for nothing.
    func testMtCoronetWaitsForEveryBossBeforeIt() throws {
        let before = DungeonCatalog.bossDungeons(before: .mtCoronet)
        XCTAssertEqual(before, [.viridianForest, .diglettsCave, .mtMoon, .mtEmber, .victoryRoad, .pokemonTower, .dragonsDen,
                                .powerPlant, .seafoamIslands, .ceruleanCave])
        let bosses = DungeonCatalog.bosses(of: before)
        XCTAssertEqual(bosses.count, 28)
        let legendaries = [144, 145, 146, 150, 243, 244, 245, 249, 250, 380].map { graduated($0, rarity: .legendary) }
        let owned = bosses.map { graduated($0) } + legendaries
        func keys(_ species: [Int]) -> Set<String> {
            Set(before.flatMap { id in DungeonCatalog.dungeon(id).bosses.filter(species.contains).map { DungeonProgress.bossKey(id, $0) } })
        }
        let ready = try store(dex: owned) {
            Self.winEvery(.t3, &$0)
            $0.dungeons.bossesBeaten = keys(bosses)
            $0.dungeons.bossesCaught = keys(bosses)
        }
        XCTAssertTrue(ready.isDungeonOpen(.mtCoronet))
        XCTAssertTrue(ready.bossesLeft(before).isEmpty)
        // Every boss beaten and in the Pokédex, Electrode (#101) never caught in the Power Plant: closed.
        let fromEggs = try store(dex: owned) {
            Self.winEvery(.t3, &$0)
            $0.dungeons.bossesBeaten = keys(bosses)
            $0.dungeons.bossesCaught = keys(bosses.filter { $0 != 101 })
        }
        XCTAssertFalse(fromEggs.isDungeonOpen(.mtCoronet))
        XCTAssertEqual(fromEggs.bossesLeft(before), [101])
        XCTAssertEqual(fromEggs.unmetUnlocks(.mtCoronet), [.caughtBosses(before)], "its other doors are open")
        // Won under the former doors, it stays open.
        let won = try store(dex: strong) { $0.dungeons.wins["mtCoronet"] = 1 }
        XCTAssertTrue(won.isDungeonOpen(.mtCoronet))
        XCTAssertEqual(won.unlockLine(.caughtBosses(before)), won.l.dungeonUnlock(.caughtBosses(before)) + " · 0/28")
    }

    /// A save from before the record keeps the captures it can tell: a run whose throws hit, a legendary boss's egg won,
    /// a boss's egg in the Bag, a Pokémon hatched from one. Not a Pokémon hatched from any other egg, nor a secret's.
    func testASaveFromBeforeKeepsItsCaptures() throws {
        var hatchedFromBoss = graduated(6)
        hatchedFromBoss.hatch = HatchRecord(egg: .dungeon(baseID: 4, form: nil, shiny: false))
        let plainCharizard = graduated(3)
        let s = try store(dex: [hatchedFromBoss, plainCharizard] + strong) {
            $0.dungeons.legendaryEggsWon = [249]
            $0.dungeons.eggs = [DungeonEgg(id: "boss-1", baseID: 100, form: nil, isShiny: false, sourceSpeciesID: 101),
                                DungeonEgg(id: "secret-1", baseID: 144, form: PokemonForm("galar"), isShiny: false,
                                           sourceSpeciesID: 144, isSecret: true)]
            $0.dungeons.history = [DungeonRunRecord(dungeon: .viridianForest, endedAt: self.now, won: true, left: false, floor: 6,
                                                    floors: 6, tokens: 1, candies: 0, eggs: 1, items: 0, bossSpeciesID: 15,
                                                    caught: true),
                                   DungeonRunRecord(dungeon: .viridianForest, endedAt: self.now, won: true, left: false, floor: 6,
                                                    floors: 6, tokens: 1, candies: 0, eggs: 0, items: 0, bossSpeciesID: 12,
                                                    caught: false)]
            $0.dungeons.bossesCaught = nil
        }
        let caught = try XCTUnwrap(s.dungeonProgress.bossesCaught)
        XCTAssertTrue(caught.contains("viridianForest:15"), "its throws hit")
        XCTAssertFalse(caught.contains("viridianForest:12"), "missed")
        XCTAssertTrue(caught.contains("seafoamIslands:249"), "Lugia's egg won")
        XCTAssertTrue(caught.contains("powerPlant:101"), "Electrode's egg in the Bag")
        XCTAssertTrue(caught.contains("victoryRoad:6"), "a Charmander hatched from Charizard's egg")
        XCTAssertFalse(caught.contains("victoryRoad:3"), "a Venusaur from a plain egg")
        XCTAssertFalse(caught.contains("seafoamIslands:144"), "Galarian Articuno's Secret Egg is no Articuno")
    }

    // MARK: Departure and tokens

    /// The team sets off with the Bag's berries and Revives; the tokens then walk it and the Pokémon raised stops
    /// growing, while the wallet still counts them (Q1).
    func testTokensWalkTheTeamWhileGrowthPauses() throws {
        let s = try store(dex: strong, inventory: [.oranBerry: 2, .revive: 1])
        let team = Array(strong.prefix(3)).map(\.id)
        XCTAssertFalse(s.startExpedition(.viridianForest, team: Array(team.prefix(2))), "three, the forest's size")
        XCTAssertTrue(s.startExpedition(.viridianForest, team: team))
        XCTAssertFalse(s.startExpedition(.diglettsCave, team: team), "one expedition at a time")
        XCTAssertEqual(s.itemCount(.oranBerry), 0)
        XCTAssertEqual(s.itemCount(.revive), 0)
        XCTAssertEqual(s.expedition?.berries[.oran], 2)
        let growth = s.state.active?.usedAtStage
        credit(s, total: 1_000_000)
        XCTAssertEqual(s.state.active?.usedAtStage, growth, "growth pauses")
        XCTAssertEqual(s.expedition?.tokensIn, 1_000_000)
        XCTAssertEqual(s.availableTokens, 1_000_000, "the Shop still counts them")
        XCTAssertTrue(s.growthPaused, "Prof. Oak reads the pause")
    }

    /// While the team waits for the heal's answer, the tokens grow the Pokémon raised as usual (the owner, 2026-11-09:
    /// a player away for a day lost that day's growth); the team walks on with the next ones once answered.
    func testTheHealsWaitGrowsThePokemonRaised() throws {
        let s = try store(dex: strong)
        XCTAssertTrue(s.startExpedition(.viridianForest, team: Array(strong.prefix(3)).map(\.id)))
        credit(s, total: 1_000_000)
        s.changeDungeons { $0.expedition?.phase = .awaitingHeal(price: 1) }
        let growth = try XCTUnwrap(s.state.active?.usedAtStage)
        let walked = s.expedition?.tokensIn
        credit(s, total: 3_000_000)
        XCTAssertNotEqual(s.state.active?.usedAtStage, growth, "the wait's tokens grow the Pokémon raised")
        XCTAssertEqual(s.expedition?.tokensIn, walked, "the team takes none")
        XCTAssertEqual(s.expedition?.reserve, 0)
        XCTAssertTrue(s.answerEmergencyHeal(pay: false))
        let grown = s.state.active?.usedAtStage
        credit(s, total: 3_500_000)
        XCTAssertEqual(s.state.active?.usedAtStage, grown, "answered, the team walks again")
        XCTAssertGreaterThan(s.expedition?.tokensIn ?? 0, walked ?? 0)
    }

    /// The whole dungeon walked: the boss falls to a strong team, the throws go by themselves with the best ball (an
    /// Ultra Ball, sure at a common boss; the Master Ball stays for a legendary one), its loot goes to the Bag with what
    /// was not used, a first victory doubles the candies, and Mt. Moon opens (Diglett's Cave won before: the whole T1).
    func testAVictoryFillsTheBag() throws {
        let s = try store(dex: strong, inventory: [.oranBerry: 3, .masterBall: 1, .ultraBall: 3]) {
            $0.dungeons.wins["diglettsCave"] = 1
        }
        XCTAssertTrue(s.startExpedition(.viridianForest, team: Array(strong.prefix(3)).map(\.id)))
        let cost = DungeonTier.t1.cost(difficulty: 0.1)
        var total = 0
        while s.expedition.map({ if case .exploring = $0.phase { return true }; if case .awaitingHeal = $0.phase { return true }; return false }) == true {
            total += cost / 5
            credit(s, total: total)
            if case .awaitingHeal? = s.expedition?.phase { s.answerEmergencyHeal(pay: false) }
        }
        XCTAssertNil(s.expedition, "the throws went by themselves: \(String(describing: s.expedition?.phase))")
        let result = try XCTUnwrap(s.dungeonProgress.lastResult)
        XCTAssertTrue(result.won)
        XCTAssertTrue(result.caught)
        XCTAssertTrue(result.firstVictory)
        XCTAssertEqual(result.loot.candies % 2, 0, "doubled")
        XCTAssertEqual(s.dungeonProgress.wins(.viridianForest), 1)
        XCTAssertTrue(result.unlocked.contains(.mtMoon))
        XCTAssertEqual(s.itemCount(.masterBall), 1, "never at a boss that is not legendary")
        XCTAssertEqual(s.itemCount(.ultraBall), 3, "a common boss: the Poké Ball, no Ultra Ball spent (#197)")
        XCTAssertEqual(s.dungeonProgress.eggs.count, result.loot.eggs.count)
        XCTAssertTrue(s.dungeonProgress.eggs.contains { $0.sourceSpeciesID == result.boss.speciesID })
        XCTAssertGreaterThanOrEqual(s.itemCount(.oranBerry), 0)
        s.dismissExpeditionResult()
        XCTAssertNil(s.dungeonProgress.lastResult)
    }

    /// Leaving keeps the loot of the floors crossed (the owner, 2026-11-04: the Escape Rope is gone).
    func testLeavingKeepsTheFloorsLoot() throws {
        let s = try store(dex: strong)
        XCTAssertTrue(s.startExpedition(.viridianForest, team: Array(strong.prefix(3)).map(\.id)))
        s.changeDungeons {
            $0.expedition?.loot.candies = 4
            $0.expedition?.loot.add(.sitrusBerry)
        }
        let candies = s.itemCount(.rareCandy), sitrus = s.itemCount(.sitrusBerry)
        s.abandonExpedition()
        XCTAssertNil(s.expedition)
        XCTAssertEqual(s.itemCount(.rareCandy), candies + 4)
        XCTAssertEqual(s.itemCount(.sitrusBerry), sitrus + 1)
        let result = try XCTUnwrap(s.dungeonProgress.lastResult)
        XCTAssertTrue(result.roped, "left early")
        XCTAssertFalse(result.won)
        XCTAssertEqual(result.loot.candies, 4)
        XCTAssertEqual(s.dungeonProgress.wins(.viridianForest), 0)
    }

    /// A defeat keeps what the floors crossed gave (the owner, 2026-11-04): their tokens are paid. Not the boss's
    /// candies, which only its fall gives.
    func testADefeatKeepsTheFloorsLoot() throws {
        let s = try store(dex: strong)
        XCTAssertTrue(s.startExpedition(.viridianForest, team: Array(strong.prefix(3)).map(\.id)))
        s.changeDungeons {
            $0.expedition?.loot.candies = 2
            $0.expedition?.loot.add(.sitrusBerry)
            $0.expedition?.candiesLeft = 5
            for i in $0.expedition!.team.indices { $0.expedition!.team[i].spec.hp = 0 }
        }
        let candies = s.itemCount(.rareCandy)
        let sitrus = s.itemCount(.sitrusBerry)
        // One floor's tokens: none left over for the growth, which has candies of its own to give.
        credit(s, total: DungeonTier.t1.cost(difficulty: 0.1) / 5)
        XCTAssertNil(s.expedition)
        let result = try XCTUnwrap(s.dungeonProgress.lastResult)
        XCTAssertFalse(result.won)
        XCTAssertEqual(result.loot.candies, 2)
        XCTAssertEqual(s.itemCount(.rareCandy), candies + 2, "the floors' two candies, not the boss's five")
        XCTAssertEqual(s.itemCount(.sitrusBerry), sitrus + 1)
    }

    /// Eggs of every boss of a dungeon waiting in the Bag: whichever is drawn was caught already.
    private func eggsOf(_ id: DungeonID) -> [DungeonEgg] {
        DungeonCatalog.dungeon(id).bosses.map {
            DungeonEgg(id: "had-\($0)", baseID: SpeciesInfo.baseID(of: $0), form: nil, isShiny: false, sourceSpeciesID: $0)
        }
    }

    /// Fells the boss and lets the throws go.
    private func catchTheBoss(_ s: CompanionStore) {
        s.changeDungeons { $0.expedition?.phase = .capture(throwsLeft: 3) }
        s.throwAutomatically()
    }

    /// A boss already caught that is no legendary gives an egg of the tier's rarity in place of its own (the owner,
    /// 2026-11-04): in the Pokédex or in the Bag, it counts.
    func testABossCaughtAlreadyGivesTheTiersEgg() throws {
        for inDex in [false, true] {
            let bosses = DungeonCatalog.dungeon(.viridianForest).bosses
            let s = try store(dex: strong + (inDex ? bosses.map { graduated($0) } : []), inventory: [.ultraBall: 3]) {
                $0.dungeons.wins["viridianForest"] = 1
                if !inDex { $0.dungeons.eggs = self.eggsOf(.viridianForest) }
            }
            XCTAssertTrue(s.startExpedition(.viridianForest, team: Array(strong.prefix(3)).map(\.id)))
            XCTAssertEqual(s.expedition?.bossReward, .tierEgg)
            let eggs = s.dungeonProgress.eggs.count
            catchTheBoss(s)
            let result = try XCTUnwrap(s.dungeonProgress.lastResult)
            XCTAssertTrue(result.caught)
            XCTAssertEqual(result.bossReward, .tierEgg)
            XCTAssertEqual(ExpeditionResultCard.bossLine(result, s.l), s.l.dungeonBossCaughtAgain(s.l.itemName(.pokemonEgg)))
            XCTAssertEqual(result.loot.items[ItemKind.pokemonEgg.rawValue], 1)
            XCTAssertEqual(s.itemCount(.pokemonEgg), 1)
            XCTAssertEqual(s.dungeonProgress.eggs.count, eggs, "no second egg of its own")
        }
        // Not caught yet: its own egg, as before.
        let s = try store(dex: strong, inventory: [.ultraBall: 3]) { $0.dungeons.wins["viridianForest"] = 1 }
        XCTAssertTrue(s.startExpedition(.viridianForest, team: Array(strong.prefix(3)).map(\.id)))
        XCTAssertNil(s.expedition?.bossReward)
        catchTheBoss(s)
        let result = try XCTUnwrap(s.dungeonProgress.lastResult)
        XCTAssertNil(result.bossReward)
        XCTAssertEqual(ExpeditionResultCard.bossLine(result, s.l), s.l.dungeonBossCaught)
        XCTAssertEqual(s.itemCount(.pokemonEgg), 0)
        XCTAssertTrue(s.dungeonProgress.eggs.contains { $0.sourceSpeciesID == result.boss.speciesID })
    }

    /// A legendary boss gives its egg once (the owner, 2026-11-04): shiny when the player has it, a Legendary Egg when
    /// the player has it shiny; one only, a first victory doubling none of it.
    func testALegendaryBossGivesItsEggOnce() throws {
        enum Had { case nothing, caught, caughtShiny }
        let bosses = DungeonCatalog.dungeon(.seafoamIslands).bosses
        for had in [Had.nothing, .caught, .caughtShiny] {
            let owned = had == .nothing ? [] : bosses.map { id -> DexEntry in
                var entry = graduated(id, rarity: .legendary)
                entry.isShiny = had == .caughtShiny
                return entry
            }
            let s = try store(dex: strong + owned, inventory: [.legendaryKey: 1, .masterBall: 1]) {
                Self.winEvery(.t3, &$0)
            }
            XCTAssertTrue(s.mayMeetALegendary(.seafoamIslands, boss: nil))
            XCTAssertTrue(s.startExpedition(.seafoamIslands, team: strong.map(\.id)))
            let boss = try XCTUnwrap(s.expedition?.boss)
            XCTAssertEqual(SpeciesInfo.lineRarity(of: boss.speciesID), .legendary)
            XCTAssertEqual(s.expedition?.bossReward, had == .caughtShiny ? .legendaryEgg : nil, "\(had)")
            if had == .caught { XCTAssertTrue(boss.isShiny, "fought shiny") }
            let eggs = s.dungeonProgress.eggs.count
            catchTheBoss(s)
            let result = try XCTUnwrap(s.dungeonProgress.lastResult)
            XCTAssertTrue(result.caught, "the Master Ball")
            XCTAssertTrue(result.firstVictory)
            XCTAssertEqual(s.dungeonProgress.legendaryEggsWon, [boss.speciesID], "won once")
            if had == .caughtShiny {
                XCTAssertEqual(result.loot.items[ItemKind.legendaryEgg.rawValue], 1, "one, not doubled")
                XCTAssertEqual(s.dungeonProgress.eggs.count, eggs, "no egg of its own")
                XCTAssertEqual(ExpeditionResultCard.bossLine(result, s.l), s.l.dungeonBossCaughtAgain(s.l.itemName(.legendaryEgg)))
            } else {
                let egg = try XCTUnwrap(s.dungeonProgress.eggs.dropFirst(eggs).first { $0.sourceSpeciesID == boss.speciesID })
                XCTAssertEqual(egg.isShiny, boss.isShiny)
                if had == .caught { XCTAssertTrue(egg.isShiny) }
                XCTAssertTrue(s.hasWonLegendaryEgg(boss.speciesID))
            }
        }
    }

    /// A legendary whose egg was won gives the loot only (the owner, 2026-11-04): no throw, so no ball spent, and the
    /// Master Ball's box is not offered. An egg in the Bag or incubating counts as won.
    func testALegendaryWhoseEggWasWonGivesTheLootOnly() throws {
        let bosses = DungeonCatalog.dungeon(.seafoamIslands).bosses
        let s = try store(dex: strong, inventory: [.legendaryKey: 1, .masterBall: 1]) {
            Self.winEvery(.t3, &$0)
            $0.dungeons.legendaryEggsWon = Set(bosses)
        }
        XCTAssertFalse(s.mayMeetALegendary(.seafoamIslands, boss: nil))
        XCTAssertTrue(s.startExpedition(.seafoamIslands, team: strong.map(\.id)))
        XCTAssertEqual(s.expedition?.bossReward, .lootOnly)
        let bag = try store(dex: strong) { $0.dungeons.eggs = self.eggsOf(.seafoamIslands) }
        XCTAssertTrue(bosses.allSatisfy { bag.bossReward($0) == .lootOnly })
        let incubating = try store(dex: strong) {
            $0.active = nil
            $0.eggFromDungeon = DungeonEgg(id: "boss", baseID: 144, form: nil, isShiny: false, sourceSpeciesID: 144)
        }
        XCTAssertEqual(incubating.bossReward(144), .lootOnly)
        XCTAssertEqual(incubating.bossReward(249), .ownEgg)

        // Walked to its end: the boss falls, the expedition ends at once.
        let walk = try store(dex: strong, inventory: [.ultraBall: 3])
        XCTAssertTrue(walk.startExpedition(.viridianForest, team: Array(strong.prefix(3)).map(\.id)))
        walk.changeDungeons { $0.expedition?.bossReward = .lootOnly }
        let cost = DungeonTier.t1.cost(difficulty: 0.1)
        var total = 0
        while walk.expedition.map({ if case .exploring = $0.phase { return true }; if case .awaitingHeal = $0.phase { return true }; return false }) == true {
            total += cost / 5
            credit(walk, total: total)
            if case .awaitingHeal? = walk.expedition?.phase { walk.answerEmergencyHeal(pay: false) }
        }
        XCTAssertNil(walk.expedition)
        let result = try XCTUnwrap(walk.dungeonProgress.lastResult)
        XCTAssertTrue(result.won)
        XCTAssertFalse(result.caught)
        XCTAssertEqual(result.bossReward, .lootOnly)
        XCTAssertFalse(result.log.contains { if case .capture = $0.kind { return true }; return false }, "no throw")
        XCTAssertEqual(walk.itemCount(.ultraBall), 3, "no ball spent")
        XCTAssertTrue(result.loot.eggs.isEmpty)
        XCTAssertEqual(ExpeditionResultCard.bossLine(result, walk.l), walk.l.dungeonBossEggWonBefore)
    }

    /// Rare Candies wait for the team (the owner, 2026-11-05): the Pokémon raised is paused while it explores.
    func testCandiesWaitWhileATeamExplores() async throws {
        let s = try store(dex: strong, inventory: [.rareCandy: 3]) { $0.active = nil }
        await s.hatch(baseID: 16)
        XCTAssertGreaterThan(s.maxRareCandyUseCount, 0, "usable at home")
        XCTAssertTrue(s.startExpedition(.viridianForest, team: Array(strong.prefix(3)).map(\.id)))
        XCTAssertEqual(s.maxRareCandyUseCount, 0)
        XCTAssertFalse(s.canUseRareCandy)
        XCTAssertEqual(s.useRareCandy(), .unavailable)
        XCTAssertEqual(s.itemCount(.rareCandy), 3, "none spent")
        s.abandonExpedition()
        XCTAssertGreaterThan(s.maxRareCandyUseCount, 0, "back home")
    }

    /// Eggs and stones wait too while a team explores (the owner, 2026-11-05: an egg used on the way sent the Pokémon
    /// raised off while its growth was paused): none can replace it until the team is back.
    func testEggsAndStonesWaitWhileATeamExplores() throws {
        let s = try store(dex: strong, inventory: [.pokemonEgg: 1, .fireStone: 1, .legendaryEgg: 1]) {
            $0.dungeons.eggs = [DungeonEgg(id: "x", baseID: 4, form: nil, isShiny: false, sourceSpeciesID: 6)]
        }
        XCTAssertTrue(s.canSendOffActive, "at home")
        XCTAssertTrue(s.canUseBagEgg(.pokemonEgg))
        XCTAssertTrue(s.canUseStone(.fireStone))
        XCTAssertTrue(s.canUseLegendaryEgg())
        XCTAssertTrue(s.canUseDungeonEgg("x"))
        XCTAssertTrue(s.startExpedition(.viridianForest, team: Array(strong.prefix(3)).map(\.id)))
        XCTAssertFalse(s.canSendOffActive)
        XCTAssertFalse(s.useBagEgg(.pokemonEgg))
        XCTAssertFalse(s.useStone(.fireStone))
        XCTAssertFalse(s.useLegendaryEgg())
        XCTAssertFalse(s.useDungeonEgg("x"))
        XCTAssertEqual(s.state.active?.baseID, 16, "the Pokémon raised stays")
        XCTAssertEqual(s.itemCount(.pokemonEgg), 1)
        XCTAssertEqual(s.itemCount(.fireStone), 1)
        XCTAssertEqual(s.dungeonProgress.eggs.count, 1)
        s.abandonExpedition()
        XCTAssertTrue(s.canUseBagEgg(.pokemonEgg), "back home")
    }

    /// The general team (a player, 2026-11-05): six at most, one per species, kept in the save; a dungeon's team screen
    /// starts with its members the rules admit, as many as it takes.
    func testTheGeneralTeamStartsTheTeamScreen() throws {
        var copy = graduated(6)
        copy.id = "copy6"
        let legend = graduated(144, rarity: .legendary)
        let s = try store(dex: strong + [copy, legend])
        XCTAssertEqual(s.startingTeam(for: .diglettsCave), [], "none saved")
        s.setSavedTeam([legend.id, "e6", "copy6", "e9", "e3", "e25", "e143", "e130", "gone"])
        XCTAssertEqual(s.savedTeam, [legend.id, "e6", "e9", "e3", "e25", "e143"], "six, one per species, only candidates")
        XCTAssertEqual(s.state.dungeons.savedTeam, s.savedTeam, "in the save")
        XCTAssertEqual(s.startingTeam(for: .diglettsCave), ["e6", "e9", "e3"], "no legendary there, three")
        XCTAssertEqual(s.startingTeam(for: .mtCoronet), [legend.id], "only legendaries there")
        let back = try JSONDecoder().decode(CompanionState.self, from: JSONEncoder().encode(s.state))
        XCTAssertEqual(back.dungeons.savedTeam, s.savedTeam)
    }

    /// Each expedition that ends is kept for its dungeon's page, the latest first, the last hundred only.
    func testAnEndedExpeditionIsKeptForItsPage() throws {
        let old = DungeonRunRecord(dungeon: .diglettsCave, endedAt: now, won: true, left: false, floor: 5, floors: 5,
                                   tokens: 1, candies: 2, eggs: 1, items: 3, bossSpeciesID: 51, caught: true)
        let s = try store(dex: strong) { $0.dungeons.history = Array(repeating: old, count: DungeonRunRecord.kept) }
        XCTAssertTrue(s.runs(of: .viridianForest).isEmpty)
        XCTAssertTrue(s.startExpedition(.viridianForest, team: Array(strong.prefix(3)).map(\.id)))
        s.abandonExpedition()
        let run = try XCTUnwrap(s.runs(of: .viridianForest).first)
        XCTAssertFalse(run.won)
        XCTAssertTrue(run.left)
        XCTAssertFalse(run.caught)
        XCTAssertEqual(s.dungeonProgress.history.count, DungeonRunRecord.kept, "the oldest goes")
        XCTAssertEqual(s.runs(of: .diglettsCave).count, DungeonRunRecord.kept - 1)
        let back = try JSONDecoder().decode(CompanionState.self, from: JSONEncoder().encode(s.state))
        XCTAssertEqual(back.dungeons.history, s.dungeonProgress.history)
        // #133: its journal and team kept, the older records' dropped past the last thirty.
        XCTAssertEqual(run.log, s.dungeonProgress.history.last?.log)
        XCTAssertFalse(run.log?.isEmpty ?? true, "the journal")
        XCTAssertEqual(run.team?.count, 3)
        XCTAssertEqual(s.allRuns.first, run, "the latest first")
    }

    /// #133: the last thirty records keep their journal, the hundred kept a line each; a save from before decodes.
    func testTheLastJournalsAreKept() throws {
        let entry = ExpeditionLogEntry(id: 0, floor: 1, date: now, kind: .victory)
        let full = DungeonRunRecord(dungeon: .mtMoon, endedAt: now, won: true, left: false, floor: 8, floors: 8, tokens: 1,
                                    candies: 0, eggs: 0, items: 0, bossSpeciesID: 36, caught: false, log: [entry], team: [])
        let trimmed = DungeonRunRecord.trimmed(Array(repeating: full, count: 120))
        XCTAssertEqual(trimmed.count, DungeonRunRecord.kept)
        XCTAssertEqual(trimmed.filter { $0.log != nil }.count, DungeonRunRecord.journalsKept)
        XCTAssertNotNil(trimmed.last?.log, "the latest keep theirs")
        XCTAssertNil(trimmed.first?.log)
        XCTAssertNil(trimmed.first?.team)
        let old = #"{"dungeon":"mtMoon","endedAt":0,"won":true,"left":false,"floor":8,"floors":8,"tokens":1,"candies":0,"eggs":0,"items":0,"bossSpeciesID":36,"caught":false}"#
        XCTAssertNil(try JSONDecoder().decode(DungeonRunRecord.self, from: Data(old.utf8)).log, "a record from before")
    }

    /// One cell per species, form and shininess on the team screen (a player saw nine identical Seedot): the copy picked,
    /// else the one whose moves were chosen, else the best IVs.
    func testTheTeamScreenShowsEachSpeciesOnce() {
        func copy(_ id: String, _ species: Int, ivs: Int, shiny: Bool = false) -> DexEntry {
            var e = graduated(species)
            e.id = id
            e.isShiny = shiny
            var profile = PokemonProfile.generate(seed: 1)
            profile.ivs = PokemonIVs(hp: ivs, attack: ivs, defense: ivs, specialAttack: ivs, specialDefense: ivs, speed: ivs)
            e.profile = profile
            return e
        }
        let entries = [copy("a", 273, ivs: 10), copy("b", 273, ivs: 31), copy("c", 273, ivs: 20), copy("d", 273, ivs: 5, shiny: true),
                       copy("e", 18, ivs: 12)]
        let plain = DungeonTeamScreen.candidateGroups(entries, picked: [], loops: [:])
        XCTAssertEqual(plain.map(\.entry.id), ["b", "d", "e"], "the best IVs stand for the Seedot")
        XCTAssertEqual(plain.map(\.count), [3, 1, 1])
        XCTAssertEqual(DungeonTeamScreen.candidateGroups(entries, picked: [], loops: ["c": ["tackle"]]).first?.entry.id, "c",
                       "the copy whose moves were chosen")
        XCTAssertEqual(DungeonTeamScreen.candidateGroups(entries, picked: ["a"], loops: ["c": ["tackle"]]).first?.entry.id, "a",
                       "the copy already in the team")
    }

    /// A legendary boss, so a throw can miss: the expedition at its throws.
    private func atALegendaryBoss(_ inventory: [ItemKind: Int], keepsMasterBall: Bool = false) throws -> CompanionStore {
        let s = try store(dex: strong, inventory: inventory)
        XCTAssertTrue(s.startExpedition(.viridianForest, team: Array(strong.prefix(3)).map(\.id), keepsMasterBall: keepsMasterBall))
        s.changeDungeons {
            $0.expedition?.boss = ExpeditionBoss(speciesID: 144, form: nil, isShiny: false)
            $0.expedition?.phase = .capture(throwsLeft: 3)
        }
        return s
    }

    private func thrownBalls(_ s: CompanionStore) -> [String?] {
        var balls: [String?] = []
        for entry in s.dungeonProgress.lastResult?.log ?? [] {
            if case .capture(_, let ball, _) = entry.kind { balls.append(ball) }
        }
        return balls
    }

    /// The throws go by themselves (the owner, 2026-11-04), each with the best ball left: Ultra, Great, then the free
    /// Poké Ball.
    func testTheThrowsTakeTheBestBallFirst() throws {
        let s = try atALegendaryBoss([.greatBall: 1, .ultraBall: 1])
        s.throwAutomatically()
        XCTAssertNil(s.expedition, "the throws ended it")
        let balls = thrownBalls(s)
        XCTAssertFalse(balls.isEmpty)
        let order: [String?] = [ItemKind.ultraBall.rawValue, ItemKind.greatBall.rawValue, nil]
        XCTAssertEqual(balls, Array(order.prefix(balls.count)))
        XCTAssertEqual(s.itemCount(.ultraBall), 0)
    }

    /// [Regression] Issue #197 (the owner's pick, 2026-11-16): the throws took an Ultra Ball at every boss, a common one
    /// the Poké Ball catches 94% of the time over the three. They take the cheapest ball that reaches 90%: the Poké Ball
    /// at a common boss, a Great Ball at an uncommon one, an Ultra Ball at a rare one; else the best the Bag has.
    func testTheThrowsTakeTheCheapestBallThatCatches() throws {
        func boss(_ rarity: Rarity) throws -> Int {
            try XCTUnwrap(DungeonCatalog.all.flatMap(\.bosses).first { SpeciesInfo.lineRarity(of: $0) == rarity }, "\(rarity)")
        }
        let s = try store(dex: strong, inventory: [.greatBall: 2, .ultraBall: 2])
        XCTAssertTrue(s.startExpedition(.viridianForest, team: Array(strong.prefix(3)).map(\.id)))
        func ball(_ species: Int) throws -> ItemKind? {
            var e = try XCTUnwrap(s.expedition)
            e.boss = ExpeditionBoss(speciesID: species, form: nil, isShiny: false)
            return s.automaticBall(for: e)
        }
        XCTAssertNil(try ball(boss(.common)), "the free Poké Ball")
        XCTAssertEqual(try ball(boss(.uncommon)), .greatBall)
        XCTAssertEqual(try ball(boss(.rare)), .ultraBall)
        XCTAssertEqual(try ball(boss(.legendary)), .ultraBall, "none reaches 90%: the best the Bag has")
        let noUltra = try store(dex: strong, inventory: [.greatBall: 1])
        XCTAssertTrue(noUltra.startExpedition(.viridianForest, team: Array(strong.prefix(3)).map(\.id)))
        var e = try XCTUnwrap(noUltra.expedition)
        e.boss = ExpeditionBoss(speciesID: try boss(.rare), form: nil, isShiny: false)
        XCTAssertEqual(noUltra.automaticBall(for: e), .greatBall, "a rare boss, no Ultra Ball: the best left")
    }

    /// The owner, 2026-11-16: after two missed throws the last one takes the ball above, the Great Ball after Poké Balls,
    /// the Ultra Ball after Great Balls, the best held when the one above is not; never before the last throw.
    func testTheLastThrowTakesTheBallAbove() throws {
        func boss(_ rarity: Rarity) throws -> Int {
            try XCTUnwrap(DungeonCatalog.all.flatMap(\.bosses).first { SpeciesInfo.lineRarity(of: $0) == rarity }, "\(rarity)")
        }
        func ball(_ s: CompanionStore, _ species: Int, left: Int) throws -> ItemKind? {
            var e = try XCTUnwrap(s.expedition)
            e.boss = ExpeditionBoss(speciesID: species, form: nil, isShiny: false)
            e.phase = .capture(throwsLeft: left)
            return s.automaticBall(for: e)
        }
        let s = try store(dex: strong, inventory: [.greatBall: 2, .ultraBall: 2])
        XCTAssertTrue(s.startExpedition(.viridianForest, team: Array(strong.prefix(3)).map(\.id)))
        XCTAssertNil(try ball(s, boss(.common), left: 3))
        XCTAssertNil(try ball(s, boss(.common), left: 2), "not before the last throw")
        XCTAssertEqual(try ball(s, boss(.common), left: 1), .greatBall, "after two Poké Balls")
        XCTAssertEqual(try ball(s, boss(.uncommon), left: 1), .ultraBall, "after two Great Balls")
        XCTAssertEqual(try ball(s, boss(.rare), left: 1), .ultraBall, "nothing above the Ultra Ball")
        let onlyUltra = try store(dex: strong, inventory: [.ultraBall: 1])
        XCTAssertTrue(onlyUltra.startExpedition(.viridianForest, team: Array(strong.prefix(3)).map(\.id)))
        XCTAssertEqual(try ball(onlyUltra, boss(.common), left: 1), .ultraBall, "no Great Ball: the best held")
        let none = try store(dex: strong, inventory: [:])
        XCTAssertTrue(none.startExpedition(.viridianForest, team: Array(strong.prefix(3)).map(\.id)))
        XCTAssertNil(try ball(none, boss(.common), left: 1), "the Poké Ball when the Bag has none")
    }

    /// At a legendary boss the Master Ball goes first, unless the player kept it home at the departure.
    func testTheMasterBallGoesAtALegendaryUnlessKeptHome() throws {
        for keep in [false, true] {
            let s = try atALegendaryBoss([.masterBall: 1, .ultraBall: 3], keepsMasterBall: keep)
            s.throwAutomatically()
            XCTAssertEqual(s.itemCount(.masterBall), keep ? 1 : 0, "kept home: \(keep)")
            XCTAssertEqual(thrownBalls(s).first ?? nil, keep ? ItemKind.ultraBall.rawValue : ItemKind.masterBall.rawValue)
            if !keep { XCTAssertEqual(s.dungeonProgress.lastResult?.caught, true, "a Master Ball never misses") }
        }
        let common = try store(dex: strong, inventory: [.masterBall: 1])
        XCTAssertTrue(common.mayMeetALegendary(.seafoamIslands, boss: nil))
        XCTAssertFalse(common.mayMeetALegendary(.viridianForest, boss: nil), "no Master Ball box where it never goes")
    }

    /// A save left at the boss's throws, from before they were automatic, throws them as the app opens.
    func testASaveWaitingAtTheThrowsThrowsThemAtLaunch() throws {
        let s = try atALegendaryBoss([:])
        var st = s.state
        st.dungeons.expedition = s.expedition
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("dungeon-throws-\(UUID().uuidString).json")
        try JSONEncoder().encode(st).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let reopened = CompanionStore(provider: StubProvider(value: EvoLine(baseID: 16, tree: EvoNode(speciesID: 16, children: []),
                                                                           rarity: .common, names: [:])),
                                      clock: { self.now }, fileURL: url, rng: SeededRNG(seed: 3), difficulty: 0.1)
        XCTAssertNil(reopened.expedition)
        XCTAssertEqual(reopened.dungeonProgress.lastResult?.won, true)
        XCTAssertFalse(thrownBalls(reopened).isEmpty)
    }

    /// R5: the heal costs a quarter of the dungeon's cost, from the wallet; refused without the tokens.
    func testTheEmergencyHealIsPaidFromTheWallet() throws {
        let cost = DungeonTier.t1.cost(difficulty: 0.1)
        let poor = try store(dex: strong)
        XCTAssertTrue(poor.startExpedition(.viridianForest, team: Array(strong.prefix(3)).map(\.id)))
        poor.changeDungeons { $0.expedition?.phase = .awaitingHeal(price: cost / 4) }
        XCTAssertFalse(poor.answerEmergencyHeal(pay: true))
        let rich = try store(dex: strong, used: cost)
        XCTAssertTrue(rich.startExpedition(.viridianForest, team: Array(strong.prefix(3)).map(\.id)))
        rich.changeDungeons { $0.expedition?.phase = .awaitingHeal(price: cost / 4) }
        XCTAssertTrue(rich.answerEmergencyHeal(pay: true))
        XCTAssertEqual(rich.availableTokens, cost - cost / 4)
        XCTAssertEqual(rich.expedition?.healUsed, true)
    }

    /// R13: the dungeon waits for the player while the heal or the throws wait, and while the return is not closed;
    /// not while the team walks. The menu bar shows the floor of the expedition under way.
    func testWhatWaitsForThePlayer() throws {
        let s = try store(dex: strong)
        XCTAssertFalse(s.dungeonNeedsAttention)
        XCTAssertNil(s.dungeonMenuFloor)
        XCTAssertTrue(s.startExpedition(.viridianForest, team: Array(strong.prefix(3)).map(\.id)))
        XCTAssertFalse(s.dungeonNeedsAttention, "the team walks on its own")
        XCTAssertEqual(s.dungeonMenuFloor, "1/\(DungeonTier.t1.floors)", "no letter before it (#136)")
        for language in AppLanguage.allCases {
            XCTAssertEqual(L(language).dungeonFloorTag(3, 8), "3/8", "\(language)")
        }
        s.changeDungeons { $0.expedition?.phase = .awaitingHeal(price: 1) }
        XCTAssertTrue(s.dungeonNeedsAttention, "the heal waits for its answer")
        s.changeDungeons { $0.expedition?.phase = .capture(throwsLeft: 3) }
        XCTAssertTrue(s.dungeonNeedsAttention, "the throws wait")
        s.endCapture()
        XCTAssertNil(s.expedition)
        XCTAssertNotNil(s.dungeonProgress.lastResult)
        XCTAssertTrue(s.dungeonNeedsAttention, "the return waits to be seen")
        XCTAssertNil(s.dungeonMenuFloor)
        s.dismissExpeditionResult()
        XCTAssertFalse(s.dungeonNeedsAttention)
    }

    /// Home shrinks the Pokémon raised to a strip only while its growth waits for the team exploring; it grows again,
    /// its card back, while the team waits for the heal's answer (2026-11-09) and as soon as the boss falls or the team
    /// loses, the result still shown above it.
    func testGrowthComesBackWhenTheTeamIsDone() throws {
        for won in [true, false] {
            let s = try store(dex: strong)
            XCTAssertFalse(s.growthPaused)
            XCTAssertTrue(s.startExpedition(.viridianForest, team: Array(strong.prefix(3)).map(\.id)))
            XCTAssertTrue(s.growthPaused, "exploring")
            s.changeDungeons { $0.expedition?.phase = .awaitingHeal(price: 1) }
            XCTAssertFalse(s.growthPaused, "the heal's wait: growth goes on")
            XCTAssertNil(s.feedExpedition(1_000), "no team takes the wait's tokens")
            s.changeDungeons { $0.expedition?.phase = .exploring }
            XCTAssertTrue(s.growthPaused, "the answer given, the team walks again")
            if won {
                s.changeDungeons { $0.expedition?.phase = .capture(throwsLeft: 3) }
                XCTAssertFalse(s.growthPaused, "the boss fell: growth again while the throws wait")
                s.endCapture()
            } else {
                s.abandonExpedition()
            }
            XCTAssertNil(s.expedition)
            XCTAssertFalse(s.growthPaused, won ? "won" : "lost")
            XCTAssertNotNil(s.dungeonProgress.lastResult, "the result stays above until closed")
        }
    }

    /// A Silver Capsule raises the one IV chosen to 31, a Gold Capsule all six; neither is spent for nothing.
    func testCapsulesRaiseIVs() throws {
        var low = graduated(143)
        low.profile = PokemonProfile.generate(seed: 1)
        low.profile?.ivs = PokemonIVs(hp: 3, attack: 31, defense: 10, specialAttack: 0, specialDefense: 31, speed: 7)
        var perfect = graduated(130)
        perfect.profile = PokemonProfile.generate(seed: 2)
        perfect.profile?.ivs = PokemonIVs(hp: 31, attack: 31, defense: 31, specialAttack: 31, specialDefense: 31, speed: 31)
        let s = try store(dex: [low, perfect], inventory: [.silverCapsule: 1, .goldCapsule: 1])
        XCTAssertEqual(s.capsuleCandidates.map(\.id), [low.id], "only an IV under 31 can be raised")
        XCTAssertFalse(s.useCapsule(.silverCapsule, on: low.id, stat: 1), "Attack is already 31")
        XCTAssertFalse(s.useCapsule(.silverCapsule, on: perfect.id, stat: 0))
        XCTAssertFalse(s.useCapsule(.silverCapsule, on: low.id), "a Silver Capsule needs its IV")
        XCTAssertEqual(s.itemCount(.silverCapsule), 1)
        XCTAssertTrue(s.useCapsule(.silverCapsule, on: low.id, stat: 3))
        var ivs = try XCTUnwrap(s.state.dex.first { $0.id == low.id }?.profile?.ivs)
        XCTAssertEqual([ivs.hp, ivs.attack, ivs.defense, ivs.specialAttack, ivs.specialDefense, ivs.speed], [3, 31, 10, 31, 31, 7])
        XCTAssertEqual(s.itemCount(.silverCapsule), 0)
        XCTAssertFalse(s.useCapsule(.silverCapsule, on: low.id, stat: 0), "none left")
        XCTAssertTrue(s.useCapsule(.goldCapsule, on: low.id))
        ivs = try XCTUnwrap(s.state.dex.first { $0.id == low.id }?.profile?.ivs)
        XCTAssertEqual([ivs.hp, ivs.attack, ivs.defense, ivs.specialAttack, ivs.specialDefense, ivs.speed], Array(repeating: 31, count: 6))
        XCTAssertTrue(s.capsuleCandidates.isEmpty)
        XCTAssertEqual(s.itemCount(.goldCapsule), 0)
        // The battle self follows: every IV at 31.
        let spec = try XCTUnwrap(s.dungeonSpec(try XCTUnwrap(s.state.dex.first { $0.id == low.id }), for: .viridianForest))
        XCTAssertEqual(spec.stats, BattlerSpec.make(id: "x", speciesID: 143, level: 100, nature: low.nature)?.stats)
    }

    /// Q23: an Explorer's Chest gives one of the Explorer Kit's treasures and is gone.
    func testAnExplorersChestHoldsAKitTreasure() throws {
        let s = try store(dex: strong, inventory: [.explorerChest: 1])
        let before = Dictionary(uniqueKeysWithValues: [ItemKind.rareCandy, .uncommonEgg, .rareEgg, .legendaryEgg].map { ($0, s.itemCount($0)) })
        let found = try XCTUnwrap(s.openExplorerChest())
        XCTAssertEqual(s.itemCount(.explorerChest), 0)
        XCTAssertTrue([ItemKind.rareCandy, .uncommonEgg, .rareEgg, .legendaryEgg].contains(found.kind))
        XCTAssertEqual(s.itemCount(found.kind), (before[found.kind] ?? 0) + found.count)
        XCTAssertNil(s.openExplorerChest(), "no chest left")
    }

    /// R4: a loop is set outside an expedition, a locked move refused until unlocked.
    func testMoveLoopsKeepTheLocks() throws {
        let s = try store(dex: strong)
        XCTAssertFalse(s.setMoveLoop(["fire-blast", "flamethrower"], for: "e6"), "Fire Blast, 110, is locked")
        XCTAssertTrue(s.setMoveLoop(["flamethrower", "air-slash"], for: "e6"))
        XCTAssertEqual(s.dungeonProgress.moveLoops["e6"], ["flamethrower", "air-slash"])
        let unlocked = try store(dex: strong) { $0.dungeons.unlockedMoves = ["fire-blast"] }
        XCTAssertTrue(unlocked.setMoveLoop(["fire-blast"], for: "e6"))
        XCTAssertEqual(s.dungeonSpec(graduated(6), for: .mtEmber)?.moves, ["flamethrower", "air-slash"])
        // Frozen while it explores, free for the Pokémon left home.
        XCTAssertTrue(s.startExpedition(.viridianForest, team: ["e6", "e9", "e3"]))
        XCTAssertTrue(s.isExploring("e6"))
        XCTAssertFalse(s.setMoveLoop(["flamethrower"], for: "e6"))
        XCTAssertEqual(s.dungeonProgress.moveLoops["e6"], ["flamethrower", "air-slash"])
        XCTAssertFalse(s.isExploring("e25"))
        XCTAssertTrue(s.setMoveLoop(["thunderbolt"], for: "e25"))
    }

    // MARK: Eggs

    /// Builds each line asked for, so a hatch is the line rolled.
    private struct LineProvider: PokeProviding {
        let index: [BaseSpecies]
        func line(baseSpeciesID id: Int) async throws -> EvoLine {
            EvoLine(baseID: id, tree: EvoNode(speciesID: id, children: []), rarity: SpeciesInfo.lineRarity(of: id), names: [:])
        }
        func baseSpecies(id: Int) async throws -> BaseSpecies? { index.first { $0.id == id } }
        func baseSpeciesIndex() async throws -> [BaseSpecies] { index }
    }

    private func hatchingStore(index: [BaseSpecies], prepare: (inout CompanionState) -> Void) throws -> CompanionStore {
        var st = CompanionState()
        st.installBaselineSet = true
        st.lastDate = "d"
        st.dex = strong
        prepare(&st)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("dungeon-egg-\(UUID().uuidString).json")
        try JSONEncoder().encode(st).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return CompanionStore(provider: LineProvider(index: index), clock: { self.now }, fileURL: url, rng: SeededRNG(seed: 5),
                              difficulty: 0.1)
    }

    /// Q20 B, R9 B: a boss's egg sends the Pokémon raised off and hatches the boss's line, shiny as the boss was.
    func testADungeonEggHatchesItsLine() async throws {
        let s = try hatchingStore(index: [BaseSpecies(id: 1, captureRate: 45)]) {
            $0.active = MonState(baseID: 16, pathIDs: [16], stageIndex: 0, usedAtStage: 0, rarity: .common, totalForms: 3)
            $0.dungeons.eggs = [DungeonEgg(id: "dratini", baseID: 147, form: nil, isShiny: true, sourceSpeciesID: 149)]
        }
        XCTAssertTrue(s.useDungeonEgg("dratini"))
        XCTAssertNil(s.state.active)
        XCTAssertTrue(s.dungeonProgress.eggs.isEmpty)
        XCTAssertEqual(s.eggKind, .dungeon(149))
        // Named by the Pokémon it hatches, Dratini, never "dungeon egg".
        XCTAssertEqual(s.incubatingEggName, DungeonEggTitle.text(147, l: s.l, language: s.language))
        s.setEggUsageForTesting(s.eggHatchThreshold)
        await s.hatchIfNeeded()
        XCTAssertEqual(s.state.active?.baseID, 147)
        XCTAssertEqual(s.state.active?.isShiny, true)
        XCTAssertNil(s.state.eggFromDungeon)
        // The Luck screen replays it as the boss's egg, a sure draw, not as a Pokémon Egg.
        let egg = HatchEgg.dungeon(baseID: 147, form: nil, shiny: true)
        XCTAssertEqual(s.state.active?.hatch?.egg, egg)
        let outcomes = s.hatchDraw.outcomes(egg, index: [BaseSpecies(id: 147, captureRate: 45)])
        XCTAssertEqual(outcomes.map(\.id), [147])
        XCTAssertEqual(outcomes.first?.alwaysShiny, true)
    }

    /// A legendary boss's egg hatches as any egg; its Pokémon graduates for 200M, a third of a legendary's 600M, and is
    /// never sent off before it graduates: no egg, no stone, no dungeon egg (the owner, 2026-11-04 and 2026-11-05).
    func testALegendaryBossEggsPokemonGraduatesForLessAndStays() async throws {
        let event = EventEgg.allCases[0]
        let s = try hatchingStore(index: [BaseSpecies(id: 1, captureRate: 45)]) {
            $0.active = MonState(baseID: 16, pathIDs: [16], stageIndex: 0, usedAtStage: 0, rarity: .common, totalForms: 3)
            $0.dungeons.eggs = [DungeonEgg(id: "mewtwo", baseID: 150, form: nil, isShiny: false, sourceSpeciesID: 150),
                                DungeonEgg(id: "dratini", baseID: 147, form: nil, isShiny: false, sourceSpeciesID: 149)]
            let items: [ItemKind] = [.silverWing, .rareEgg, .fireStone, .legendaryEgg, .typeNullEgg, .birthdayEgg, .fossilEgg, event.item]
            $0.inventory = Dictionary(uniqueKeysWithValues: items.map { ($0.rawValue, 1) })
        }
        func sendOffs() -> [Bool] {
            [s.canUseDungeonEgg("dratini"), s.canUseBagEgg(.rareEgg), s.canUseStone(.fireStone), s.canUseLegendaryEgg(),
             s.canUseTypeNullEgg(), s.canUseBirthdayEgg(), s.canUseFossilEgg(), s.canUseEventEgg(event)]
        }
        XCTAssertEqual(sendOffs(), Array(repeating: true, count: 8), "another Pokémon raised: each can send it off")
        XCTAssertTrue(s.useDungeonEgg("dratini"))
        let hatch = s.eggHatchThreshold
        s.setEggUsageForTesting(hatch)
        await s.hatchIfNeeded()
        XCTAssertEqual(s.state.active?.fromLegendaryBossEgg, false)
        XCTAssertTrue(s.useDungeonEgg("mewtwo"))
        XCTAssertEqual(s.eggHatchThreshold, hatch, "a legendary boss's egg hatches as any egg")
        s.setEggUsageForTesting(hatch)
        await s.hatchIfNeeded()
        let mewtwo = try XCTUnwrap(s.state.active)
        XCTAssertEqual(mewtwo.baseID, 150)
        XCTAssertTrue(mewtwo.fromLegendaryBossEgg)
        XCTAssertTrue(s.isRaisingLegendaryBossPokemon)
        // Its whole growth: 200M as the player reads it, where a legendary takes 600M.
        let growth = (0..<mewtwo.totalForms).reduce(0) { total, stage in
            var at = mewtwo
            at.stageIndex = stage
            return total + at.phaseThreshold
        }
        XCTAssertEqual(PokemonBalance.scaled(growth), 200_000_000, "\(mewtwo.totalForms) stages")
        var plain = mewtwo
        plain.fromLegendaryBossEgg = false
        XCTAssertEqual(PokemonBalance.scaled(plain.graduationTotal), 600_000_000)
        // The growth bonuses still speed it, as any Pokémon.
        XCTAssertLessThanOrEqual(s.stageThreshold(for: mewtwo), PokemonBalance.scaled(mewtwo.phaseThreshold, by: 0.1))
        XCTAssertEqual(sendOffs(), Array(repeating: false, count: 8), "nothing sends it off")
        XCTAssertFalse(s.useLegendaryEgg())
        XCTAssertEqual(s.state.active?.baseID, 150)
        // The save keeps it.
        let back = try JSONDecoder().decode(MonState.self, from: JSONEncoder().encode(mewtwo))
        XCTAssertTrue(back.fromLegendaryBossEgg)
        XCTAssertEqual(back.phaseThreshold, mewtwo.phaseThreshold)
    }

    /// R13: Arceus hatches from no egg: not a plain one, not a Legendary Egg, not a Birthday Egg.
    func testArceusHatchesFromNoEgg() throws {
        let index = [BaseSpecies(id: 493, captureRate: 3, isLegendary: true), BaseSpecies(id: 150, captureRate: 3, isLegendary: true),
                     BaseSpecies(id: 16, captureRate: 255)]
        let s = try hatchingStore(index: index) { _ in }
        XCTAssertFalse(s.hatchDraw.hatchPool(index, egg: CompanionStore.EggSpec()).contains { $0.base.id == 493 })
        XCTAssertFalse(s.hatchDraw.hatchPool(index, egg: CompanionStore.EggSpec(legendaryEgg: true)).contains { $0.base.id == 493 })
        XCTAssertFalse(BirthdayGift.pool(index, graduated: []).lines.contains { $0.id == 493 })
    }

    /// A save that pre-rolled Arceus rolls again.
    func testAPreRolledArceusRollsAgain() async throws {
        let s = try hatchingStore(index: [BaseSpecies(id: 16, captureRate: 255)]) {
            $0.pendingHatchID = 493
            $0.eggUsage = 10_000_000
        }
        await s.hatchIfNeeded()
        XCTAssertNotEqual(s.state.active?.baseID, 493)
    }

    /// Once the player has an Arceus, one pre-rolled hatches: Arceus is back in the eggs (the owner, 2026-11-05).
    func testAPreRolledArceusHatchesOnceCaught() async throws {
        let s = try hatchingStore(index: [BaseSpecies(id: 16, captureRate: 255)]) {
            $0.dex += [self.graduated(493, rarity: .legendary)]
            $0.pendingHatchID = 493
            $0.eggUsage = 10_000_000
        }
        await s.hatchIfNeeded()
        XCTAssertEqual(s.state.active?.baseID, 493)
    }

    /// The artifacts in the dungeons (the owner, 2026-11-06): those for everyone, those of a type the dungeon has and
    /// the badges its types are weak to speed its floors up, added up as growth is; the others do nothing.
    func testArtifactsSpeedTheFloorsUp() throws {
        let plain = try store(dex: strong)
        XCTAssertEqual(plain.dungeonSpeed(.pokemonTower), 1)
        XCTAssertEqual(plain.dungeonCost(.pokemonTower), DungeonCatalog.dungeon(.pokemonTower).cost(difficulty: 0.1))
        let s = try store(dex: strong, inventory: [.griseousOrb: 1, .silverWing: 1, .sunFlute: 1, .rustedSword: 1, .zRing: 1]) {
            $0.claimedAchievements.insert(CompanionState.regionTierKey(.boulderBadge, generation: 1))
        }
        XCTAssertEqual(s.dungeonSpeed(.pokemonTower), 1 + 0.3 + 0.25, accuracy: 1e-9, "Ghost: the Orb and the Wing")
        XCTAssertEqual(s.dungeonSpeed(.mtCoronet), 1 + 0.3 + 0.25 + 0.3, accuracy: 1e-9, "the Orb, the Wing and the Z-Ring, added")
        XCTAssertEqual(s.dungeonSpeed(.viridianForest), 1 + 0.25 + 0.025, accuracy: 1e-9, "Bug is weak to Rock: Kanto's Boulder Badge")
        XCTAssertEqual(s.dungeonSpeed(.daily), 1.25, accuracy: 1e-9, "no theme: the Wing only")
        XCTAssertTrue(s.dungeonGrowthFactors(.pokemonTower).allSatisfy { $0.source != .item(.sunFlute) && $0.source != .item(.rustedSword) },
                      "a stage or a rarity fits no dungeon")
        let cost = DungeonCatalog.dungeon(.pokemonTower).cost(difficulty: 0.1)
        XCTAssertEqual(s.dungeonCost(.pokemonTower), Int((Double(cost) / 1.55).rounded(.up)))
        let forest = try store(dex: strong, inventory: [.tealMask: 1])
        XCTAssertTrue(forest.startExpedition(.viridianForest, team: Array(strong.prefix(3)).map(\.id)))
        let forestCost = DungeonCatalog.dungeon(.viridianForest).cost(difficulty: 0.1)
        XCTAssertEqual(forest.expedition?.cost, Int((Double(forestCost) / 1.2).rounded(.up)), "the expedition sets off with the lower cost")
    }

    /// The Shiny Charm and the Reveal Glass raise the floors' shiny meeting as every shiny roll.
    func testTheShinyMeetingFollowsTheShinyOdds() {
        XCTAssertEqual(ExpeditionEngine.shinyEncounterPerTenThousand(shinyDenominator: 64), 100)
        XCTAssertEqual(ExpeditionEngine.shinyEncounterPerTenThousand(shinyDenominator: 48), 133)
        XCTAssertEqual(ExpeditionEngine.shinyEncounterPerTenThousand(shinyDenominator: 24), 267)
        XCTAssertEqual(ExpeditionEngine.eventOdds(tier: .t3, risky: false, shinyDenominator: 24).first?.percent ?? 0, 2.67, accuracy: 1e-9)
    }

    /// The team screen asked the candidates for every row and member of each render, each time filtering the whole
    /// Pokédex: 3.2 s a render on 742 Pokémon, the app frozen on a hover (a player, 2026-11-06). Made once per state
    /// now, a team's species once per render.
    func testTheCandidatesAreMadeOncePerState() throws {
        let s = try store(dex: strong)
        let first = s.dungeonCandidates
        for _ in 0..<500 { _ = s.dungeonCandidates }
        XCTAssertEqual(s.dungeonCandidatesBuilds, 1, "one build for every read")
        XCTAssertEqual(s.teamSpecies(["e6", "e9", "gone"]), [6, 9])
        XCTAssertEqual(s.dungeonCandidatesBuilds, 1)
        s.setSavedTeam(["e6"])
        XCTAssertEqual(s.dungeonCandidates, first, "the same Pokémon")
        XCTAssertEqual(s.dungeonCandidatesBuilds, 2, "made again once the state changed")
    }

    func testVictoryExtras() {
        var random = BattleRandom(seed: 1)
        XCTAssertEqual(CompanionStore.technicalCapsuleChance(.t1), 10)
        XCTAssertEqual(CompanionStore.technicalCapsuleChance(.t2), 20)
        XCTAssertEqual(CompanionStore.technicalCapsuleChance(.t3), 35)
        XCTAssertEqual(CompanionStore.technicalCapsuleChance(.t4), 20)
        XCTAssertEqual(CompanionStore.technicalCapsuleChance(.t5), 15)
        // One T3 victory in two gives a key, the first as the fifteenth (the owner, 2026-11-06 and 2026-11-09; one in
        // ten before, and the first one sure until 2026-11-09).
        var keys = 0
        for _ in 0..<2_000 {
            keys += CompanionStore.victoryExtras(tier: .t3, random: &random).items[ItemKind.legendaryKey.rawValue] ?? 0
        }
        XCTAssertEqual(Double(keys) / 2_000, 0.50, accuracy: 0.03)
        XCTAssertEqual(CompanionStore.victoryExtraOdds(.t3).first { $0.item == .legendaryKey }?.percent, 50)
    }

    /// The Dungeons medals sit with the Artifacts: a step per dungeon won once, then the whole tier, each its reward
    /// and never a Legendary Key; nothing without a victory, and the Ruins of Alph stay out.
    func testTheMedalsCountTheDungeonsWon() throws {
        XCTAssertEqual(ItemKind.discoveryMedal.collectorGroup, .legendaryArtifacts)
        XCTAssertFalse(DungeonMedals.dungeons(.t4).contains(.ruinsOfAlph))
        XCTAssertEqual(DungeonTier.allCases.map { DungeonMedals.goals($0).count }.reduce(0, +), 16)
        for tier in DungeonTier.allCases {
            for (step, _) in DungeonMedals.goals(tier) {
                XCTAssertFalse(DungeonMedals.rewards(tier, step: step).contains { $0.kind == .legendaryKey }, "T\(tier.rawValue) #\(step)")
            }
        }

        let none = try store(dex: strong)
        XCTAssertEqual(none.regionTiers(.discoveryMedal).filter(\.isReady).count, 0)
        XCTAssertFalse(none.claimAchievement(.discoveryMedal))

        let one = try store(dex: strong) { $0.dungeons.wins[DungeonID.viridianForest.rawValue] = 1 }
        XCTAssertEqual(one.regionTiers(.discoveryMedal).map(\.isReady), [true, false, false], "a dungeon, not the tier")
        XCTAssertTrue(one.claimAchievement(.discoveryMedal))
        XCTAssertEqual(one.itemCount(.greatBall), 1)
        XCTAssertEqual(one.itemCount(.discoveryMedal), 0, "the medal gives, it is not kept")

        let both = try store(dex: strong) {
            $0.dungeons.wins[DungeonID.viridianForest.rawValue] = 3
            $0.dungeons.wins[DungeonID.diglettsCave.rawValue] = 1
        }
        XCTAssertTrue(both.claimAchievement(.discoveryMedal))
        XCTAssertEqual(both.itemCount(.greatBall), 2)
        XCTAssertEqual(both.itemCount(.pokemonEgg), 1, "the whole T1")
        XCTAssertTrue(both.isClaimed(.discoveryMedal))
        XCTAssertFalse(both.claimAchievement(.discoveryMedal), "claimed once")

        let origin = try store(dex: strong) { $0.dungeons.wins[DungeonID.hallOfOrigin.rawValue] = 1 }
        XCTAssertEqual(origin.regionTiers(.originMedal).count, 1, "a single dungeon has no whole-tier step")
        XCTAssertTrue(origin.claimAchievement(.originMedal))
        XCTAssertEqual(origin.itemCount(.goldCapsule), 1)
    }

    // MARK: Battle forms (2026-11-02)

    /// PokéAPI's Megas, Primals and Gigantamax forms with a sprite: Mega Zygarde has none and stays out. The daily
    /// dungeon gives the Megas of non-legendary species, the weekly one the rest.
    func testTheBattleFormsTable() {
        XCTAssertEqual(BattleForms.all.count, 132)
        XCTAssertEqual(Set(BattleForms.all.map(\.key)).count, 132, "one key each")
        let charizardX = try? XCTUnwrap(BattleForms.form(speciesID: 6, form: PokemonForm("mega-x")))
        XCTAssertEqual(charizardX?.pokemonID, 10034)
        XCTAssertEqual(BattleForms.form(speciesID: 25, form: PokemonForm("gmax"))?.kind, .gigantamax)
        XCTAssertEqual(BattleForms.form(speciesID: 382, form: PokemonForm("primal"))?.kind, .primal)
        XCTAssertNil(BattleForms.forms(speciesID: 718).first { $0.form.rawValue == "mega" }, "no sprite, left out")
        XCTAssertTrue(BattleForms.daily.allSatisfy { $0.kind == .mega && !$0.isLegendary })
        XCTAssertTrue(BattleForms.weekly.contains { $0.speciesID == 150 }, "Mewtwo's Megas are the week's")
        XCTAssertEqual(BattleForms.daily.count + BattleForms.weekly.count, BattleForms.all.count)
    }

    /// A battle form takes its variety's stats, types, ability and sprites, and no egg ever hatches it.
    func testABattleFormIsItsVariety() throws {
        let x = PokemonForm("mega-x")
        XCTAssertEqual(PokemonForm.resolved(speciesID: 6, form: x), x)
        XCTAssertEqual(PokemonForm.detailsID(speciesID: 6, form: x), 10034)
        XCTAssertEqual(PokemonForm.staticAssetName(speciesID: 6, form: x), "10034")
        XCTAssertEqual(PokemonTypeData.types(forSpeciesID: 6, form: x), [.fire, .dragon])
        let mega = try XCTUnwrap(BattlerSpec.make(id: "x", speciesID: 6, form: x, level: 100))
        let usual = try XCTUnwrap(BattlerSpec.make(id: "u", speciesID: 6, level: 100))
        XCTAssertGreaterThan(mega.stats.attack, usual.stats.attack)
        XCTAssertEqual(mega.ability, "tough-claws")
        XCTAssertFalse(PokemonForm.lineForms(baseID: 4).contains(x), "never rolled by an egg")
        XCTAssertFalse(PokemonForm.lineForms(baseID: 79).contains { $0.rawValue.contains("mega") })
        // Every form the app can count: the catalog's and the battle forms.
        let catalog = PokemonAssets.animatedSpeciesIDs.reduce(0) { $0 + max(1, PokemonForm.forms(speciesID: $1).count) }
        XCTAssertEqual(CompanionStore.collectableFormCount, catalog + BattleForms.all.count)
    }

    /// The daily dungeon opens with a first T3 victory, costs no key, draws a Mega of a graduated species, and gives
    /// it when its boss falls: one try a day, the form never used up, in the Pokédex's count, chosen for a member.
    func testTheDailyDungeonGivesAMega() throws {
        let charizard = graduated(6)
        let team = [charizard] + [9, 3, 25, 143, 130].map { graduated($0) }
        let s = try store(dex: team) { $0.dungeons.wins[DungeonID.victoryRoad.rawValue] = 1 }
        XCTAssertTrue(s.isDungeonOpen(.daily))
        XCTAssertFalse(s.isDungeonOpen(.weekly), "a T4 victory opens the week's")
        XCTAssertEqual(s.keysToEnter(.daily), 0)
        let boss = try XCTUnwrap(s.challengeBoss(.daily))
        XCTAssertTrue(team.map(\.finalID).contains(boss.speciesID))
        XCTAssertEqual(s.challengeBoss(.daily), boss, "the same all day")
        let formsBefore = s.graduatedCollectionProgress.forms
        XCTAssertNil(s.challengeOutcome(.daily), "not tried yet")
        XCTAssertTrue(s.startExpedition(.daily, team: team.map(\.id)))
        XCTAssertNil(s.challengeOutcome(.daily), "under way: neither won nor lost")
        XCTAssertEqual(s.expedition?.boss.form, boss.form)
        XCTAssertEqual(s.expedition?.floors, 8)
        XCTAssertNil(s.expedition?.bossReward, "a challenge's boss, always one of the player's, gives its form")
        XCTAssertEqual(s.expedition?.boss.isShiny, false)
        XCTAssertTrue(s.challengeTried(.daily))
        s.changeDungeons { $0.expedition?.phase = .capture(throwsLeft: 3) }
        s.endCapture()
        XCTAssertEqual(s.dungeonProgress.lastResult?.battleForm, boss.key)
        XCTAssertEqual(s.challengeOutcome(.daily), true, "won today (the owner, 2026-11-09)")
        XCTAssertTrue(s.dungeonProgress.battleForms.contains(boss.key))
        XCTAssertEqual(s.graduatedCollectionProgress.forms, formsBefore + 1)
        XCTAssertFalse(s.canEnter(.daily), "one try a day")
        XCTAssertEqual(s.challengeBoss(.daily), boss, "won: still the day's boss (the owner, 2026-11-10)")
        s.settleChallengeBosses()
        XCTAssertEqual(s.challengeBoss(.daily), boss, "kept once settled")
        // The owner of the species takes it in a dungeon, never using it up.
        let owner = try XCTUnwrap(s.state.dex.first { $0.finalID == boss.speciesID })
        XCTAssertTrue(s.setBattleForm(boss, for: owner.id))
        XCTAssertEqual(s.dungeonCandidates.first { $0.id == owner.id }?.form, boss.form)
        XCTAssertTrue(s.dungeonProgress.battleForms.contains(boss.key))
        XCTAssertTrue(s.setBattleForm(nil, for: owner.id))
        XCTAssertNil(s.dungeonCandidates.first { $0.id == owner.id }?.form)
        // The save keeps it, and a form this build does not know is not read.
        var progress = s.dungeonProgress
        progress.battleForms.insert("6-mega-w")
        let back = try JSONDecoder().decode(DungeonProgress.self, from: JSONEncoder().encode(progress))
        XCTAssertEqual(back.battleForms, s.dungeonProgress.battleForms)
        XCTAssertEqual(back.dailyTried, s.dungeonProgress.dailyTried)
    }

    /// A defeat spends the one try too; the week's has its own, by ISO week.
    func testAChallengeTryIsSpentWhateverTheEnd() throws {
        let team = [6, 9, 3, 25, 143, 130].map { graduated($0) }
        let s = try store(dex: team) { $0.dungeons.wins[DungeonID.seafoamIslands.rawValue] = 1 }
        XCTAssertTrue(s.isDungeonOpen(.weekly))
        XCTAssertTrue(s.startExpedition(.weekly, team: team.map(\.id)))
        s.abandonExpedition()
        XCTAssertTrue(s.dungeonProgress.battleForms.isEmpty)
        XCTAssertTrue(s.challengeTried(.weekly))
        XCTAssertEqual(s.challengeOutcome(.weekly), false, "lost this week: the card crosses its boss out (2026-11-09)")
        XCTAssertNil(s.challengeOutcome(.daily))
        XCTAssertFalse(s.canEnter(.weekly))
        XCTAssertTrue(s.challengePeriod(.weekly).contains("-W"))
        XCTAssertFalse(s.challengeTried(.daily), "the day's is apart")
    }

    /// The Battle Forms Medal counts the forms won, in steps at 5, 15, 30, 60, 100 and all, each its reward.
    func testTheBattleFormsMedalCountsTheFormsWon() throws {
        XCTAssertEqual(BattleFormsMedal.steps, [5, 15, 30, 60, 100, BattleForms.all.count])
        let five = Set(BattleForms.all.prefix(5).map(\.key))
        let s = try store(dex: strong) { $0.dungeons.battleForms = five }
        XCTAssertEqual(s.regionTiers(.battleFormsMedal).map(\.isReady), [true, false, false, false, false, false])
        XCTAssertTrue(s.claimAchievement(.battleFormsMedal))
        XCTAssertEqual(s.itemCount(.ultraBall), 2)
        XCTAssertFalse(s.claimAchievement(.battleFormsMedal), "the next step asks for 15")
        XCTAssertEqual(ItemKind.battleFormsMedal.collectorGroup, .legendaryArtifacts)
    }

    // MARK: The review of 2026-11-02

    /// [Regression] A challenge has no boss list: its odds estimate indexed an empty one and crashed the Prepare screen.
    /// The estimate now carries the day's boss, the Bag's berries and Revives, and the members' battle forms.
    func testAChallengesOddsDoNotCrash() throws {
        let team = [6, 9, 3, 25, 143, 130].map { graduated($0) }
        let members = team.compactMap { entry in
            DungeonTeamBuilder.spec(for: entry).map { ExpeditionMember(entryID: entry.id, spec: $0) }
        }
        for id in [DungeonID.daily, .weekly] {
            let odds = DungeonTeamBuilder.reachOdds(team: members, dungeon: DungeonCatalog.dungeon(id), runs: 2)
            XCTAssertTrue((0...1).contains(odds), id.rawValue)
        }
        let s = try store(dex: team, inventory: [.sitrusBerry: 3]) { $0.dungeons.wins[DungeonID.victoryRoad.rawValue] = 1 }
        let estimate = try XCTUnwrap(s.reachEstimate(team: team.map(\.id), for: .daily))
        XCTAssertEqual(estimate.boss?.form, s.challengeBoss(.daily)?.form)
        XCTAssertEqual(estimate.berries[.sitrus], 3, "the berries the departure takes")
    }

    /// [Regression] The owner's day dungeon of 2026-11-13: "Compose for me" played its teams without the Bag's
    /// berries and kept one winning 88% of the runs over one winning 96% with the six Sitrus Berries he took along.
    /// Its runs now carry the berries and Revives the departure takes, and a bench to swap from.
    func testComposeCarriesTheBagAndABench() throws {
        let dex = [6, 9, 3, 25, 143, 130, 149, 65, 94, 248].map { graduated($0) }
        let s = try store(dex: dex, inventory: [.sitrusBerry: 6, .revive: 2]) {
            $0.dungeons.wins[DungeonID.victoryRoad.rawValue] = 1
        }
        let choice = s.composeChoice(for: .daily)
        XCTAssertEqual(choice.berries[.sitrus], 6, "the berries the departure takes")
        XCTAssertEqual(choice.revives[ItemKind.revive.rawValue], 2)
        let benched = Set(choice.bench.map(\.member.entryID))
        XCTAssertFalse(choice.teams.isEmpty)
        for team in choice.teams { XCTAssertTrue(Set(team.map(\.entryID)).isSubset(of: benched)) }
        XCTAssertGreaterThan(choice.bench.count, 6, "more than a team to swap from")
    }

    /// [Regression] Tokens past the boss's fall walked nowhere: a morning's catch-up finishing the last floor lost the
    /// rest. What the dungeon does not take goes back to the growth it paused.
    func testTokensPastTheEndGoBackToGrowth() throws {
        let team = Array(strong.prefix(3))
        let s = try store(dex: strong)
        XCTAssertTrue(s.startExpedition(.viridianForest, team: team.map(\.id)))
        var e = try XCTUnwrap(s.expedition)
        let context = ExpeditionContext(tier: .t1, shinyDenominator: 64, now: now)
        let left = ExpeditionEngine.feed(&e, tokens: e.floorCost * e.floors * 10, context: context)
        XCTAssertFalse({ if case .exploring = e.phase { return true }; return false }(), "the dungeon is done")
        XCTAssertGreaterThan(left, e.floorCost * e.floors, "most of it left over")
        let before = s.state.active?.usedAtStage ?? 0
        XCTAssertEqual(s.feedExpedition(e.floorCost * e.floors * 10).map { $0 > 0 }, true)
        _ = before
        XCTAssertNil(s.feedExpedition(1).flatMap { $0 > 0 ? $0 : nil }, "once over, nothing more walks it")
    }

    /// [Regression] The day's boss stays as first shown: a graduation in the day changed the draw's list, and the boss.
    func testTheDaysBossStaysAllDay() throws {
        let morning = [6, 9, 3, 25, 143, 130].map { graduated($0) }
        let s = try store(dex: morning) { $0.dungeons.wins[DungeonID.victoryRoad.rawValue] = 1 }
        s.settleChallengeBosses()
        let boss = try XCTUnwrap(s.challengeBoss(.daily))
        let draws = s.dungeonProgress.challengeDraws
        XCTAssertEqual(draws["daily:\(s.challengePeriod(.daily))"], boss.key)
        // Later the same day, more Mega-capable species graduated: the kept draw wins over a new one.
        let noon = morning + [94, 65, 248, 448, 445, 376, 257, 282, 306, 359].map { graduated($0) }
        let later = try store(dex: noon) {
            $0.dungeons.wins[DungeonID.victoryRoad.rawValue] = 1
            $0.dungeons.challengeDraws = draws
        }
        XCTAssertEqual(later.challengeBoss(.daily), boss)
    }

    /// [Regression] A hand-edited throw count past three is clamped at the import: a throw then counted backwards.
    func testAnImportedCaptureKeepsThreeThrows() throws {
        var state = CompanionState()
        state.installBaselineSet = true
        let spec = try XCTUnwrap(BattlerSpec.make(id: "e6", speciesID: 6, level: 100))
        var e = ExpeditionEngine.start(dungeon: DungeonCatalog.dungeon(.viridianForest),
                                       team: [ExpeditionMember(entryID: "e6", spec: spec)], rules: [], teamSize: 1, seed: 1,
                                       cost: 75_000_000, berries: [:], revives: [:],
                                       context: ExpeditionContext(tier: .t1, shinyDenominator: 64, now: now))
        e.phase = .capture(throwsLeft: 1000)
        state.dungeons.expedition = e
        let data = try SaveTransfer.encode(state: state, appVersion: "2.5.0", deviceName: "Mac", now: now)
        let back = try SaveTransfer.decode(data).state.dungeons.expedition
        XCTAssertEqual(back?.phase, .capture(throwsLeft: 3))
    }

    /// [Regression] Leaving is refused once the boss fell: it turned a victory, its throws waiting, into a defeat.
    func testNoLeavingOnceTheBossFell() throws {
        let s = try store(dex: strong)
        XCTAssertTrue(s.startExpedition(.viridianForest, team: Array(strong.prefix(3)).map(\.id)))
        s.changeDungeons { $0.expedition?.phase = .capture(throwsLeft: 3) }
        s.abandonExpedition()
        XCTAssertNotNil(s.expedition, "still at the throws")
    }

    // MARK: Past midnight and the week's turn (the owner, 2026-11-03)

    private final class Clock: @unchecked Sendable { var date: Date; init(_ date: Date) { self.date = date } }

    private func store(dex: [DexEntry], clock: Clock, prepare: (inout CompanionState) -> Void) throws -> CompanionStore {
        var st = CompanionState()
        st.installBaselineSet = true
        st.lastDate = "d"
        st.claimedTodayTokensByProvider = ["test": 0]
        st.dex = dex
        st.active = MonState(baseID: 16, pathIDs: [16, 17, 18], stageIndex: 0, usedAtStage: 0, rarity: .common, totalForms: 3)
        prepare(&st)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("dungeon-clock-\(UUID().uuidString).json")
        try JSONEncoder().encode(st).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return CompanionStore(provider: StubProvider(value: EvoLine(baseID: 16, tree: EvoNode(speciesID: 16, children: []),
                                                                    rarity: .common, names: [:])),
                              clock: { clock.date }, fileURL: url, rng: SeededRNG(seed: 3), difficulty: 0.1)
    }

    /// [Regression, review of 2026-11-04] Set off a minute past midnight from a screen opened before it, a challenge
    /// fought the new day's boss, not the one shown and estimated, and spent the new day's try on it. The departure now
    /// waits for the boss the screen showed.
    func testAChallengeDepartureWaitsForTheBossItShowed() throws {
        let calendar = Calendar(identifier: .iso8601)
        let team = [6, 9, 3, 25, 143, 130].map { graduated($0) }
        var played = false
        for day in 8...14 {
            var parts = DateComponents(year: 2026, month: 11, day: day, hour: 23, minute: 59)
            parts.timeZone = .current
            let clock = Clock(try XCTUnwrap(calendar.date(from: parts)))
            let s = try store(dex: team, clock: clock) { $0.dungeons.wins[DungeonID.victoryRoad.rawValue] = 1 }
            let shown = try XCTUnwrap(s.challengeBoss(.daily))
            clock.date = clock.date.addingTimeInterval(2 * 60)
            let current = try XCTUnwrap(s.challengeBoss(.daily))
            guard current != shown else { continue }
            played = true
            XCTAssertFalse(s.startExpedition(.daily, team: team.map(\.id), expectedBoss: shown))
            XCTAssertNil(s.expedition)
            XCTAssertFalse(s.challengeTried(.daily), "the new day's try is still there")
            XCTAssertTrue(s.startExpedition(.daily, team: team.map(\.id), expectedBoss: current))
            XCTAssertEqual(s.expedition?.boss.form, current.form)
            break
        }
        XCTAssertTrue(played, "no midnight in the week changed the day's boss")
    }

    /// [Regression, review of 2026-11-04] Capture with no throw left (only an import makes one) took the ball and threw
    /// nothing.
    func testNoThrowLeftTakesNoBall() throws {
        let s = try store(dex: strong, inventory: [.ultraBall: 2])
        XCTAssertTrue(s.startExpedition(.viridianForest, team: Array(strong.prefix(3)).map(\.id)))
        s.changeDungeons { $0.expedition?.phase = .capture(throwsLeft: 0) }
        XCTAssertNil(s.throwAtBoss(.ultraBall))
        XCTAssertEqual(s.itemCount(.ultraBall), 2)
    }

    /// [Regression, review of 2026-11-04] A battle that crashed the app replayed at every launch (its seed, team and
    /// floor are saved). A step that never came back ends its expedition at the next launch; a step that comes back
    /// leaves no mark.
    func testAStepThatNeverCameBackEndsItsExpedition() throws {
        let suite = "dungeon-step-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("dungeon-step-\(UUID().uuidString).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        func open() -> CompanionStore {
            CompanionStore(provider: StubProvider(value: EvoLine(baseID: 16, tree: EvoNode(speciesID: 16, children: []),
                                                                 rarity: .common, names: [:])),
                           clock: { self.now }, fileURL: url, rng: SeededRNG(seed: 3), defaults: defaults, difficulty: 0.1)
        }
        var st = CompanionState()
        st.installBaselineSet = true
        st.lastDate = "d"
        st.claimedTodayTokensByProvider = ["test": 0]
        st.dex = strong
        st.active = MonState(baseID: 16, pathIDs: [16, 17, 18], stageIndex: 0, usedAtStage: 0, rarity: .common, totalForms: 3)
        try JSONEncoder().encode(st).write(to: url)
        let s = open()
        XCTAssertTrue(s.startExpedition(.viridianForest, team: Array(strong.prefix(3)).map(\.id)))
        _ = s.feedExpedition(1_000_000)
        XCTAssertFalse(defaults.bool(forKey: CompanionStore.stepInFlightKey), "a step that came back leaves no mark")
        XCTAssertNotNil(s.expedition)
        // The app died inside the next step: the mark stayed, the save is the step's before.
        defaults.set(true, forKey: CompanionStore.stepInFlightKey)
        let relaunched = open()
        XCTAssertNil(relaunched.expedition, "the expedition ends instead of replaying the battle")
        XCTAssertEqual(relaunched.dungeonProgress.lastResult?.won, false)
        XCTAssertFalse(relaunched.dungeonProgress.lastResult?.log.contains {
            if case .abandon = $0.kind { return true } else { return false }
        } ?? true, "a defeat, which keeps the floors' loot, not a departure without a rope")
        XCTAssertFalse(defaults.bool(forKey: CompanionStore.stepInFlightKey))
    }

    /// A challenge set off before midnight (or before the week turns) goes on unchanged: its boss, its floors and the
    /// form it gives are the departure's, whatever the day's draw has become; the next try is the new period's.
    /// The team screen's filters find the shinies and the species with a Mega, Primal or Gigantamax won, chosen or
    /// not; a Pokémon that is not shiny joins the Hall of Origin once its form is chosen from the list (2026-11-10).
    func testTheFiltersFindTheFormsTheHallAsksFor() throws {
        var pikachu = graduated(25)
        pikachu.isShiny = true
        let s = try store(dex: [graduated(6), graduated(94), pikachu]) {
            $0.dungeons.battleForms = ["6-mega-x", "94-gmax"]
        }
        func entry(_ id: Int) throws -> DexEntry { try XCTUnwrap(s.dungeonCandidates.first { $0.finalID == id }) }
        XCTAssertTrue(s.matches(try entry(6), .megaOrPrimal))
        XCTAssertFalse(s.matches(try entry(6), .gigantamax))
        XCTAssertTrue(s.matches(try entry(94), .gigantamax))
        XCTAssertFalse(s.matches(try entry(94), .megaOrPrimal))
        XCTAssertTrue(s.matches(try entry(25), .shiny))
        XCTAssertFalse(s.matches(try entry(6), .shiny))
        let rules = DungeonCatalog.dungeon(.hallOfOrigin).rules
        XCTAssertFalse(DungeonTeamRules.admits(DungeonCandidate(try entry(6)), rules: rules), "its usual form, not shiny")
        let mega = try XCTUnwrap(s.wonBattleForms(speciesID: 6).first)
        XCTAssertTrue(s.setBattleForm(mega, for: "e6"))
        XCTAssertTrue(DungeonTeamRules.admits(DungeonCandidate(try entry(6)), rules: rules), "as its Mega")
        XCTAssertTrue(s.matches(try entry(6), .megaOrPrimal), "still found once chosen")
    }

    /// The week's dungeon has one try a day, its boss the week's (the owner, 2026-11-10: "une tentative par jour
    /// possible pas 1 par semaine").
    func testTheWeeksDungeonHasATryADay() throws {
        let calendar = Calendar(identifier: .iso8601)
        var parts = DateComponents(year: 2026, month: 11, day: 10, hour: 10)
        parts.timeZone = .current
        let clock = Clock(try XCTUnwrap(calendar.date(from: parts)))
        let team = [6, 9, 3, 25, 143, 130].map { graduated($0) }
        let s = try store(dex: team, clock: clock) { $0.dungeons.wins[DungeonID.seafoamIslands.rawValue] = 1 }
        let boss = try XCTUnwrap(s.challengeBoss(.weekly))
        XCTAssertTrue(s.startExpedition(.weekly, team: team.map(\.id)))
        s.abandonExpedition()
        XCTAssertTrue(s.challengeTried(.weekly))
        XCTAssertFalse(s.canEnter(.weekly), "one try today")
        XCTAssertEqual(s.challengeOutcome(.weekly), false)
        clock.date = clock.date.addingTimeInterval(86_400)
        XCTAssertFalse(s.challengeTried(.weekly), "a new try the next day")
        XCTAssertTrue(s.canEnter(.weekly))
        XCTAssertNil(s.challengeOutcome(.weekly))
        XCTAssertEqual(s.challengeBoss(.weekly), boss, "the same week, the same boss")
        // The save keeps the day's key.
        XCTAssertTrue(s.startExpedition(.weekly, team: team.map(\.id)))
        var state = s.state
        state.dungeons.expedition = nil
        XCTAssertEqual(SaveTransfer.sanitized(state).dungeons.weeklyTried, s.challengeTryPeriod())
    }

    /// Today's try is read from today's run, never the day before's: a won yesterday does not make today's lost try a
    /// win (the owner, 2026-11-09: a lost daily dungeon shows as such).
    func testTodaysOutcomeIsTodaysRun() throws {
        let calendar = Calendar(identifier: .iso8601)
        var parts = DateComponents(year: 2026, month: 11, day: 9, hour: 18)
        parts.timeZone = .current
        let now = try XCTUnwrap(calendar.date(from: parts))
        let clock = Clock(now)
        let team = [6, 9, 3, 25, 143, 130].map { graduated($0) }
        func record(_ won: Bool, _ endedAt: Date) -> DungeonRunRecord {
            DungeonRunRecord(dungeon: .daily, endedAt: endedAt, won: won, left: false, floor: 8, floors: 8, tokens: 1,
                             candies: 0, eggs: 0, items: 0, bossSpeciesID: 6, caught: false)
        }
        let s = try store(dex: team, clock: clock) {
            $0.dungeons.wins[DungeonID.victoryRoad.rawValue] = 1
            $0.dungeons.history = [record(true, now.addingTimeInterval(-86_400))]
        }
        XCTAssertNil(s.challengeOutcome(.daily), "yesterday's win, today not tried")
        s.changeDungeons { $0.dailyTried = s.challengePeriod(.daily) }
        XCTAssertEqual(s.challengeOutcome(.daily), false, "tried today, its boss not won: yesterday's win does not count")
        s.changeDungeons { $0.history.append(record(true, now.addingTimeInterval(-60))) }
        XCTAssertEqual(s.challengeOutcome(.daily), true)
    }

    /// The boss a try beat stays its period's boss (the owner, 2026-11-10: Mega Staraptor beaten, the card showed
    /// another boss under "won today"): the day's until the next day, the week's until Monday, its dungeon closed till
    /// then ("une forme de la semaine par semaine au plus").
    func testTheBossBeatenStaysItsPeriodsBoss() throws {
        let calendar = Calendar(identifier: .iso8601)
        // Tuesday 10:00, local time.
        var parts = DateComponents(year: 2026, month: 11, day: 10, hour: 10)
        parts.timeZone = .current
        let team = [6, 9, 3, 25, 143, 130].map { graduated($0) }
        for id in [DungeonID.daily, .weekly] {
            let clock = Clock(try XCTUnwrap(calendar.date(from: parts)))
            let s = try store(dex: team, clock: clock) {
                $0.dungeons.wins[DungeonID.victoryRoad.rawValue] = 1
                $0.dungeons.wins[DungeonID.seafoamIslands.rawValue] = 1
            }
            let boss = try XCTUnwrap(s.challengeBoss(id))
            s.settleChallengeBosses()
            XCTAssertTrue(s.startExpedition(id, team: team.map(\.id)), id.rawValue)
            clock.date = clock.date.addingTimeInterval(600)
            s.changeDungeons { $0.expedition?.phase = .capture(throwsLeft: 3) }
            s.endCapture()
            XCTAssertEqual(s.dungeonProgress.battleFormsWonAt[boss.key], clock.date, id.rawValue)
            XCTAssertEqual(s.challengeOutcome(id), true, id.rawValue)
            XCTAssertEqual(s.challengeBoss(id), boss, "\(id.rawValue): won, still the day's boss")
            s.settleChallengeBosses()
            XCTAssertEqual(s.challengeBoss(id), boss, "\(id.rawValue): and once settled")
            clock.date = clock.date.addingTimeInterval(86_400)
            if id == .daily {
                let next = try XCTUnwrap(s.challengeBoss(id))
                XCTAssertNotEqual(next, boss, "the next day, a form not won")
                XCTAssertTrue(s.challengeCandidates(id).contains(next))
                XCTAssertNil(s.challengeOutcome(id))
                XCTAssertTrue(s.canEnter(id))
            } else {
                XCTAssertEqual(s.challengeBoss(id), boss, "the week's boss, beaten, stays the week's")
                XCTAssertEqual(s.challengeOutcome(id), true, "still won on Wednesday")
                XCTAssertFalse(s.canEnter(id), "one of its forms a week at most")
                XCTAssertFalse(s.startExpedition(id, team: team.map(\.id)))
                // Monday: a new week, a new boss, a new try.
                clock.date = clock.date.addingTimeInterval(5 * 86_400)
                let next = try XCTUnwrap(s.challengeBoss(id))
                XCTAssertNotEqual(next, boss)
                XCTAssertTrue(s.challengeCandidates(id).contains(next))
                XCTAssertNil(s.challengeOutcome(id))
                XCTAssertTrue(s.canEnter(id))
            }
        }
    }

    /// The owner's save (2026-11-10): Mega Staraptor won at 11:04 before the date was kept, the day's draw already moved
    /// on to Mega Absol. Its win in the history gives its date back, and the day's boss with it.
    func testASaveFromBeforeFindsTheBossItBeat() throws {
        let calendar = Calendar(identifier: .iso8601)
        var parts = DateComponents(year: 2026, month: 11, day: 10, hour: 11, minute: 17)
        parts.timeZone = .current
        let clock = Clock(try XCTUnwrap(calendar.date(from: parts)))
        let wonAt = clock.date.addingTimeInterval(-13 * 60)
        let team = [398, 359, 9, 25, 143, 130].map { graduated($0) }
        let staraptor = try XCTUnwrap(BattleForms.daily.first { $0.speciesID == 398 })
        let absol = try XCTUnwrap(BattleForms.daily.first { $0.speciesID == 359 })
        let won = DungeonRunRecord(dungeon: .daily, endedAt: wonAt, won: true, left: false, floor: 8, floors: 8, tokens: 1,
                                   candies: 0, eggs: 0, items: 0, bossSpeciesID: 398, caught: false)
        let s = try store(dex: team, clock: clock) {
            $0.dungeons.wins[DungeonID.victoryRoad.rawValue] = 1
            $0.dungeons.battleForms = [staraptor.key]
            $0.dungeons.history = [won]
            $0.dungeons.dailyTried = "2026-11-10"
            $0.dungeons.challengeDraws = ["daily:2026-11-10": absol.key]
        }
        XCTAssertEqual(s.dungeonProgress.battleFormsWonAt, [staraptor.key: wonAt])
        XCTAssertEqual(s.challengeBoss(.daily), staraptor)
        XCTAssertEqual(s.challengeOutcome(.daily), true)
    }

    func testAChallengeGoesOnPastMidnightAndTheWeeksTurn() throws {
        let calendar = Calendar(identifier: .iso8601)
        // Sunday 23:50, local time: the day and the ISO week both turn at the next midnight.
        var parts = DateComponents(year: 2026, month: 11, day: 8, hour: 23, minute: 50)
        parts.timeZone = .current
        let clock = Clock(try XCTUnwrap(calendar.date(from: parts)))
        let team = [6, 9, 3, 25, 143, 130].map { graduated($0) }
        for id in [DungeonID.daily, .weekly] {
            let s = try store(dex: team, clock: clock) {
                $0.dungeons.wins[DungeonID.victoryRoad.rawValue] = 1
                $0.dungeons.wins[DungeonID.seafoamIslands.rawValue] = 1
            }
            clock.date = try XCTUnwrap(calendar.date(from: parts))
            let boss = try XCTUnwrap(s.challengeBoss(id))
            let period = s.challengePeriod(id)
            XCTAssertTrue(s.startExpedition(id, team: team.map(\.id)), id.rawValue)
            let floors = try XCTUnwrap(s.expedition?.floors)
            // Past midnight, into Monday: a new day, a new ISO week.
            clock.date = clock.date.addingTimeInterval(20 * 60)
            XCTAssertNotEqual(s.challengePeriod(id), period, "\(id.rawValue): the period turned")
            XCTAssertEqual(s.expedition?.boss.form, boss.form, "\(id.rawValue): the same boss")
            XCTAssertEqual(s.expedition?.floors, floors)
            XCTAssertFalse(s.canEnter(id), "\(id.rawValue): one run at a time")
            // The run ends the next day, won: the form is the departure's boss.
            s.changeDungeons { $0.expedition?.phase = .capture(throwsLeft: 3) }
            s.endCapture()
            XCTAssertEqual(s.dungeonProgress.lastResult?.battleForm, boss.key, id.rawValue)
            XCTAssertTrue(s.dungeonProgress.battleForms.contains(boss.key))
            // The new period's try is untouched; its boss is another form, the one won is out of the draw.
            XCTAssertFalse(s.challengeTried(id), "\(id.rawValue): the new period's try is still there")
            XCTAssertTrue(s.canEnter(id))
            XCTAssertNotEqual(s.challengeBoss(id), boss)
        }
    }
}
