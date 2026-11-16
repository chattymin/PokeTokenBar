import XCTest
@testable import PokeTokenBar

private struct DungeonIndexProvider: PokeProviding {
    var index: [BaseSpecies] = []
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: baseSpeciesID, tree: EvoNode(speciesID: baseSpeciesID, children: []), rarity: .common, names: [:])
    }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { index }
}

private final class Runs {
    var count = 0
}

@MainActor
final class OakDungeonTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func graduated(_ id: Int, rarity: Rarity = .common, shiny: Bool = false, chain: [Int]? = nil) -> DexEntry {
        var entry = DexEntry(baseID: SpeciesInfo.baseID(of: id), finalID: id, chainOrder: chain ?? [id], rarity: rarity, caughtAt: now)
        entry.id = "e\(id)\(shiny ? "s" : "")"
        entry.isShiny = shiny
        return entry
    }

    private var strong: [DexEntry] { [6, 9, 3, 25, 143, 130].map { graduated($0) } }

    private let belowT4: [DungeonID] = [.viridianForest, .diglettsCave, .mtMoon, .mtEmber, .victoryRoad, .pokemonTower,
                                        .dragonsDen, .powerPlant]

    private var doorCaught: Set<String> {
        Set(DungeonCatalog.bossDungeons(before: .mtCoronet).flatMap { id in
            DungeonCatalog.dungeon(id).bosses.map { DungeonProgress.bossKey(id, $0) }
        })
    }

    private func wins(_ ids: [DungeonID]) -> [String: Int] {
        Dictionary(uniqueKeysWithValues: ids.map { ($0.rawValue, 1) })
    }

    private func store(dex: [DexEntry]? = nil, inventory: [ItemKind: Int] = [:], index: [BaseSpecies] = [], used: Int = 0,
                       prepare: (inout CompanionState) -> Void = { _ in }) throws -> CompanionStore {
        var st = CompanionState()
        st.installBaselineSet = true
        st.lastDate = "d"
        st.claimedTodayTokensByProvider = ["test": 0]
        st.usedSinceInstall = used
        st.dex = dex ?? strong
        st.active = MonState(baseID: 16, pathIDs: [16, 17, 18], stageIndex: 0, usedAtStage: 0, rarity: .common, totalForms: 3)
        st.inventory = Dictionary(uniqueKeysWithValues: inventory.map { ($0.key.rawValue, $0.value) })
        prepare(&st)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("oak-dungeon-\(UUID().uuidString).json")
        try JSONEncoder().encode(st).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let s = CompanionStore(provider: DungeonIndexProvider(index: index), clock: { self.now }, fileURL: url,
                               rng: SeededRNG(seed: 3), difficulty: 0.1)
        s.oakComposeSearch = { $0.teams.first?.map(\.entryID) ?? [] }
        return s
    }

    private func settle(_ s: CompanionStore) async {
        while true {
            _ = s.oakDungeon
            let pending = s.oakSearchTasks.values.map { $0.task }
            guard !pending.isEmpty else { return }
            for task in pending { await task.value }
        }
    }

    private func credit(_ s: CompanionStore, total: Int) {
        s.update(todayTokensByProvider: ["test": total], todayDate: "d", monthTotal: 0, burnTier: .idle,
                 limitWarning: false, hasUsageData: true)
    }

    // MARK: The Dungeon Budget

    func testTheDungeonBudgetCountsFromTheFirstTokensOfThisBuild() throws {
        let before = DungeonRunRecord(dungeon: .viridianForest, endedAt: now, won: true, left: false, floor: 5, floors: 5,
                                      tokens: 9_000_000, candies: 0, eggs: 0, items: 0, bossSpeciesID: 15, caught: false,
                                      log: nil, team: nil)
        let s = try store(used: 5_000_000) { $0.dungeons.history = [before] }
        XCTAssertNil(s.state.dungeons.budget)
        credit(s, total: 1_000_000)
        XCTAssertEqual(s.state.dungeons.budget, DungeonBudget(start: 5_000_000, dungeonTokens: 0),
                       "the runs before it are not counted")
        XCTAssertTrue(s.startExpedition(.viridianForest, team: Array(strong.prefix(3)).map(\.id)))
        credit(s, total: 1_400_000)
        XCTAssertEqual(s.state.dungeons.budget, DungeonBudget(start: 5_000_000, dungeonTokens: 400_000))
        let back = try JSONDecoder().decode(CompanionState.self, from: JSONEncoder().encode(s.state))
        XCTAssertEqual(back.dungeons.budget, s.state.dungeons.budget)
    }

    func testNoDungeonOnceTheDungeonsTookFifteenPercentOfTheTokens() async throws {
        let spent = try store(used: 1_000) { $0.dungeons.budget = DungeonBudget(start: 0, dungeonTokens: 150) }
        spent.oakWinOdds = { _ in 1 }
        XCTAssertNil(spent.oakDungeon)
        let under = try store(used: 1_000) { $0.dungeons.budget = DungeonBudget(start: 0, dungeonTokens: 149) }
        under.oakWinOdds = { _ in 1 }
        await settle(under)
        XCTAssertEqual(under.oakDungeon?.id, .viridianForest)
        XCTAssertEqual(under.oakDungeon?.reason, .firstWin)
        XCTAssertEqual(under.oakSteps.last, under.oakDungeon.map(OakStep.dungeon))
    }

    func testTheBudgetGoesOnceEveryEggFormKeyIsHeld() async throws {
        let index = [BaseSpecies(id: 16, captureRate: 255)]
        let held = try store(dex: strong + [graduated(18, chain: [16, 17, 18]), graduated(132)], index: index, used: 1_000) {
            $0.dungeons.budget = DungeonBudget(start: 0, dungeonTokens: 900)
        }
        await held.loadHatchIndex()
        held.oakWinOdds = { _ in 1 }
        await settle(held)
        XCTAssertEqual(held.oakDungeon?.id, .viridianForest)
        let missing = try store(dex: strong + [graduated(17, chain: [16, 17]), graduated(132)], index: index, used: 1_000) {
            $0.dungeons.budget = DungeonBudget(start: 0, dungeonTokens: 900)
        }
        await missing.loadHatchIndex()
        missing.oakWinOdds = { _ in 1 }
        XCTAssertNil(missing.oakDungeon, "Pidgeot's Egg Form Key is missing")
    }

    // MARK: The order

    func testAFirstWinComesBeforeTheChallengeAndTheChallengeBeforeTheBosses() async throws {
        let firstWin = try store { $0.dungeons.wins = self.wins(Array(self.belowT4.prefix(6))) }
        firstWin.oakWinOdds = { _ in 1 }
        await settle(firstWin)
        XCTAssertEqual(firstWin.oakDungeon?.id, .dragonsDen)
        XCTAssertEqual(firstWin.oakDungeon?.reason, .firstWin)

        let challenge = try store { $0.dungeons.wins = self.wins(self.belowT4) }
        challenge.oakWinOdds = { _ in 1 }
        await settle(challenge)
        XCTAssertEqual(challenge.oakDungeon?.id, .daily)
        XCTAssertEqual(challenge.oakDungeon?.reason, .challenge)

        let formsWon = try store {
            $0.dungeons.wins = self.wins(self.belowT4)
            $0.dungeons.battleForms = Set(BattleForms.all.map(\.key))
        }
        formsWon.oakWinOdds = { _ in 1 }
        await settle(formsWon)
        XCTAssertEqual(formsWon.oakDungeon?.id, .dragonsDen, "no challenge once its forms are won")
        XCTAssertEqual(formsWon.oakDungeon?.reason, .boss)
    }

    func testACaughtBossIsNoLongerProposed() async throws {
        let tierOne: (DungeonTeamBuilder.ReachEstimate) -> Double = { $0.dungeon.tier == .t1 ? 1 : 0 }
        let t1 = try store { $0.dungeons.wins = self.wins([.viridianForest, .diglettsCave]) }
        t1.oakWinOdds = tierOne
        await settle(t1)
        XCTAssertEqual(t1.oakDungeon?.id, .diglettsCave)
        XCTAssertEqual(t1.oakDungeon?.reason, .boss)

        let diglett = try store(dex: strong + [51, 76, 208].map { graduated($0) }) {
            $0.dungeons.wins = self.wins([.viridianForest, .diglettsCave])
        }
        diglett.oakWinOdds = tierOne
        await settle(diglett)
        XCTAssertEqual(diglett.oakDungeon?.id, .viridianForest, "Diglett's Cave's bosses are caught")

        let caught = strong + [15, 12, 45, 76, 208].map { graduated($0) }
        let one = try store(dex: caught) { $0.dungeons.wins = self.wins([.viridianForest, .diglettsCave]) }
        one.oakWinOdds = tierOne
        await settle(one)
        XCTAssertEqual(one.oakDungeon?.id, .diglettsCave, "Dugtrio is still to catch")

        let hatching = try store(dex: caught) {
            $0.dungeons.wins = self.wins([.viridianForest, .diglettsCave])
            $0.dungeons.bossesCaught = self.doorCaught
            $0.active = nil
            $0.eggFromDungeon = DungeonEgg(id: "egg", baseID: 50, form: nil, isShiny: false, sourceSpeciesID: 51)
        }
        hatching.oakWinOdds = tierOne
        await settle(hatching)
        XCTAssertNil(hatching.oakDungeon, "Dugtrio's egg is hatching")
    }

    func testTheBossesMtCoronetsDoorWaitsForAreProposedUntilCaughtThere() async throws {
        let dex = strong + [51, 76, 208].map { graduated($0) }
        let keys = Set([51, 76, 208].map { DungeonProgress.bossKey(.diglettsCave, $0) })
        let cave: (DungeonTeamBuilder.ReachEstimate) -> Double = { $0.dungeon.id == .diglettsCave ? 1 : 0 }
        let door = try store(dex: dex) { $0.dungeons.wins = self.wins([.diglettsCave]) }
        door.oakWinOdds = cave
        await settle(door)
        XCTAssertEqual(door.oakDungeon?.id, .diglettsCave, "Diglett's Cave's bosses are had from eggs")
        XCTAssertEqual(door.oakDungeon?.reason, .coronetDoor)

        let beaten = try store(dex: dex) {
            $0.dungeons.wins = self.wins([.diglettsCave])
            $0.dungeons.bossesBeaten = keys
        }
        beaten.oakWinOdds = cave
        await settle(beaten)
        XCTAssertEqual(beaten.oakDungeon?.reason, .coronetDoor, "beaten, never caught there")

        let caught = try store(dex: dex) {
            $0.dungeons.wins = self.wins([.diglettsCave])
            $0.dungeons.bossesBeaten = keys
            $0.dungeons.bossesCaught = keys
        }
        caught.oakWinOdds = cave
        await settle(caught)
        XCTAssertNil(caught.oakDungeon)

        let open = try store(dex: dex) { $0.dungeons.wins = self.wins([.diglettsCave, .mtCoronet]) }
        open.oakWinOdds = cave
        await settle(open)
        XCTAssertNil(open.oakDungeon, "Mt. Coronet is open")
    }

    func testTheAdviceSaysWhatTheDungeonTakes() async throws {
        let s = try store { $0.dungeons.wins = self.wins([.viridianForest, .diglettsCave]) }
        s.oakWinOdds = { $0.dungeon.tier == .t1 ? 1 : 0 }
        await settle(s)
        let dungeon = try XCTUnwrap(s.oakDungeon)
        XCTAssertGreaterThan(dungeon.tokens, 0)
        XCTAssertEqual(dungeon.tokens, s.dungeonCost(dungeon.id), "what the dungeon's card shows")
    }

    private var hallDex: [DexEntry] {
        [144, 145, 146, 483, 484, 487].map { graduated($0, rarity: .legendary) }
            + [graduated(6), graduated(6, shiny: true), graduated(9), graduated(3, shiny: true)]
            + [25, 143, 130].map { graduated($0, shiny: true) }
    }

    private func hallStore(beaten: [Int], forms: [String], odds: Double, won: [DungeonID] = []) throws -> CompanionStore {
        let s = try store(dex: hallDex, inventory: [.legendaryKey: 1]) { st in
            st.dungeons.wins = self.wins([.mtCoronet] + won)
            st.dungeons.bossesBeaten = Set(beaten.map { DungeonProgress.bossKey(.mtCoronet, $0) })
            st.dungeons.battleForms = Set(forms)
            st.dungeons.battleFormsWonAt = Dictionary(uniqueKeysWithValues: forms.enumerated().map {
                ($0.element, self.now.addingTimeInterval(Double($0.offset - 10) * 86_400))
            })
        }
        s.oakWinOdds = { $0.dungeon.id == .mtCoronet ? 1 : $0.dungeon.id == .hallOfOrigin ? odds : 0 }
        return s
    }

    func testMtCoronetComesBeforeTheHallOfOrigin() async throws {
        let coronet = try hallStore(beaten: [483, 484], forms: ["6-mega-x", "3-mega", "9-gmax"], odds: 1)
        await settle(coronet)
        XCTAssertEqual(coronet.oakDungeon?.id, .mtCoronet)
        XCTAssertEqual(coronet.oakDungeon?.reason, .coronet, "Giratina is caught, not beaten")
        let hall = try hallStore(beaten: [483, 484, 487], forms: ["6-mega-x", "3-mega", "9-gmax"], odds: 1)
        await settle(hall)
        XCTAssertEqual(hall.oakDungeon?.id, .hallOfOrigin)
        XCTAssertEqual(hall.oakDungeon?.reason, .hall)
    }

    func testABossToCatchComesBeforeTheHallOfOrigin() async throws {
        let s = try hallStore(beaten: [483, 484, 487], forms: ["6-mega-x", "3-mega", "9-gmax"], odds: 1, won: [.diglettsCave])
        s.oakWinOdds = { [.diglettsCave, .hallOfOrigin].contains($0.dungeon.id) ? 1 : 0 }
        await settle(s)
        XCTAssertEqual(s.oakDungeon?.id, .diglettsCave)
        XCTAssertEqual(s.oakDungeon?.reason, .boss)
    }

    func testTheHallOfOriginComesWithTheFormsToSet() async throws {
        let hall = try hallStore(beaten: [483, 484, 487], forms: ["6-mega-x", "3-mega", "9-gmax"], odds: 0.1)
        await settle(hall)
        let forms = hall.oakDungeon?.forms.map { "\($0.entryID):\($0.form.key)" }
        XCTAssertEqual(forms, ["e6s:6-mega-x", "e9:9-gmax"], "the first Mega won, on a shiny of its species")
        let under = try hallStore(beaten: [483, 484, 487], forms: ["6-mega-x", "3-mega", "9-gmax"], odds: 0.09)
        await settle(under)
        XCTAssertNil(under.oakDungeon)
        let noGmax = try hallStore(beaten: [483, 484, 487], forms: ["6-mega-x", "3-mega"], odds: 1)
        await settle(noGmax)
        XCTAssertNil(noGmax.oakDungeon, "no Gigantamax won")
    }

    func testTheKeyIsAdvisedOnlyWhenADungeonWaitsForIt() async throws {
        let dex = strong + [94, 442, 609, 149, 445, 635, 462, 466, 101].map { graduated($0) }
        func odds(seafoam: Double) -> (DungeonTeamBuilder.ReachEstimate) -> Double {
            { estimate in
                switch estimate.dungeon.id {
                case .seafoamIslands: seafoam
                case .pokemonTower: 0.6
                case .dragonsDen: 0.8
                case .powerPlant: 0.7
                default: 0
                }
            }
        }
        let waits = try store(dex: dex) {
            $0.dungeons.wins = self.wins(self.belowT4)
            $0.dungeons.battleForms = Set(BattleForms.all.map(\.key))
            $0.dungeons.bossesCaught = self.doorCaught
        }
        waits.oakWinOdds = odds(seafoam: 1)
        await settle(waits)
        XCTAssertEqual(waits.oakDungeon?.id, .dragonsDen)
        XCTAssertEqual(waits.oakDungeon?.reason, .key(for: .seafoamIslands))

        let none = try store(dex: dex) {
            $0.dungeons.wins = self.wins(self.belowT4)
            $0.dungeons.battleForms = Set(BattleForms.all.map(\.key))
            $0.dungeons.bossesCaught = self.doorCaught
        }
        none.oakWinOdds = odds(seafoam: 0.4)
        await settle(none)
        XCTAssertNil(none.oakDungeon)
    }

    // MARK: The odds

    func testADungeonWonFortyPercentOfTheTimeIsNotProposed() async throws {
        let forty = try store()
        forty.oakWinOdds = { _ in 0.4 }
        await settle(forty)
        XCTAssertNil(forty.oakDungeon)
        let half = try store()
        half.oakWinOdds = { _ in 0.5 }
        await settle(half)
        XCTAssertEqual(half.oakDungeon?.id, .viridianForest)
        XCTAssertEqual(half.oakDungeon?.win, 0.5)
    }

    func testALostChallengeComesBackTheNextDayWhileItsOddsHold() async throws {
        let yesterday = DungeonProgress.challengePeriod(.daily, at: now.addingTimeInterval(-86_400))
        let today = DungeonProgress.challengePeriod(.daily, at: now)
        func challenge(tried: String, odds: Double) async throws -> CompanionStore {
            let s = try store {
                $0.dungeons.wins = self.wins(self.belowT4)
                $0.dungeons.dailyTried = tried
            }
            s.oakWinOdds = { $0.dungeon.id == .daily ? odds : 0 }
            await settle(s)
            return s
        }
        let half = try await challenge(tried: yesterday, odds: 0.5)
        XCTAssertEqual(half.oakDungeon?.id, .daily)
        let under = try await challenge(tried: yesterday, odds: 0.49)
        XCTAssertNil(under.oakDungeon)
        let tried = try await challenge(tried: today, odds: 1)
        XCTAssertNil(tried.oakDungeon)
    }

    func testTheOddsRunOnceUntilTheTeamChanges() async throws {
        var dex = strong
        var profile = PokemonProfile.generate(seed: 1)
        profile.ivs = PokemonIVs(hp: 31, attack: 10, defense: 31, specialAttack: 31, specialDefense: 31, speed: 31)
        dex[0].profile = profile
        let s = try store(dex: dex, inventory: [.goldCapsule: 1])
        let runs = Runs()
        s.oakWinOdds = { _ in
            runs.count += 1
            return 1
        }
        await settle(s)
        XCTAssertNotNil(s.oakDungeon)
        let first = runs.count
        credit(s, total: 1_000)
        XCTAssertNotNil(s.oakDungeon)
        XCTAssertEqual(runs.count, first, "the tokens changed, not the team")
        XCTAssertTrue(s.useCapsule(.goldCapsule, on: "e6"))
        await settle(s)
        XCTAssertNotNil(s.oakDungeon)
        XCTAssertGreaterThan(runs.count, first, "Charizard's IVs changed")
    }

    func testTheOddsRunAgainOnceABossIsCaughtThere() async throws {
        let s = try store()
        let runs = Runs()
        s.oakWinOdds = { _ in
            runs.count += 1
            return 1
        }
        await settle(s)
        let first = runs.count
        let boss = try XCTUnwrap(DungeonCatalog.dungeon(.viridianForest).bosses.first)
        s.changeDungeons { $0.bossesCaught = [DungeonProgress.bossKey(.viridianForest, boss)] }
        await settle(s)
        XCTAssertNotNil(s.oakDungeon)
        XCTAssertGreaterThan(runs.count, first, "Viridian Forest's draw lost a boss")
    }

    // MARK: While a team explores

    func testNoDungeonWhileATeamExplores() throws {
        let s = try store()
        s.oakWinOdds = { _ in 1 }
        XCTAssertTrue(s.startExpedition(.viridianForest, team: Array(strong.prefix(3)).map(\.id)))
        XCTAssertNil(s.oakDungeon)
        XCTAssertFalse(s.oakSteps.contains { if case .dungeon = $0 { true } else { false } })
    }

    // MARK: The Capsules

    func testTheCapsulesGoDownTheTeamInItsOrder() async throws {
        func entry(_ id: Int, _ ivs: PokemonIVs) -> DexEntry {
            var e = graduated(id)
            var profile = PokemonProfile.generate(seed: UInt64(id))
            profile.ivs = ivs
            e.profile = profile
            return e
        }
        let dex = [
            entry(6, PokemonIVs(hp: 31, attack: 31, defense: 31, specialAttack: 31, specialDefense: 31, speed: 31)),
            entry(9, PokemonIVs(hp: 31, attack: 10, defense: 31, specialAttack: 31, specialDefense: 31, speed: 31)),
            entry(3, PokemonIVs(hp: 31, attack: 31, defense: 5, specialAttack: 31, specialDefense: 31, speed: 2)),
            entry(25, PokemonIVs(hp: 0, attack: 31, defense: 31, specialAttack: 31, specialDefense: 31, speed: 31)),
            graduated(143), graduated(130),
        ]
        let s = try store(dex: dex, inventory: [.goldCapsule: 1, .silverCapsule: 5])
        XCTAssertEqual(s.oakCapsules(for: ["e6", "e9", "e3", "e25"]), [
            OakCapsule(entryID: "e9", kind: .goldCapsule, stat: nil),
            OakCapsule(entryID: "e3", kind: .silverCapsule, stat: 2),
            OakCapsule(entryID: "e25", kind: .silverCapsule, stat: 0),
        ])
        s.oakWinOdds = { _ in 1 }
        await settle(s)
        let advice = try XCTUnwrap(s.oakDungeon)
        XCTAssertEqual(advice.capsules, s.oakCapsules(for: advice.team))
    }

    // MARK: The team "Compose for me" picks

    private var withIVs: [DexEntry] {
        (strong + [graduated(149)]).map { entry in
            var entry = entry
            var profile = PokemonProfile.generate(seed: 1)
            profile.ivs = PokemonIVs(hp: 31, attack: 10, defense: 31, specialAttack: 31, specialDefense: 31, speed: 31)
            entry.profile = profile
            return entry
        }
    }

    func testTheDungeonStepWaitsForTheSearch() async throws {
        let s = try store()
        s.oakWinOdds = { _ in 1 }
        XCTAssertNil(s.oakDungeon, "the search runs")
        XCTAssertEqual(Array(s.oakSearchTasks.keys), [.viridianForest], "one search at a time")
        await settle(s)
        XCTAssertEqual(s.oakDungeon?.id, .viridianForest)
    }

    func testTheDungeonProposedGoesWithTheTeamComposeForMePicks() async throws {
        let s = try store(dex: withIVs, inventory: [.goldCapsule: 1])
        let greedy = s.composeTeam(for: .viridianForest)
        let left = try XCTUnwrap(withIVs.map(\.id).first { !greedy.contains($0) })
        let picked = [left] + greedy.dropFirst()
        XCTAssertNotEqual(s.oakCapsules(for: picked), s.oakCapsules(for: greedy))
        s.oakComposeSearch = { _ in picked }
        s.oakWinOdds = { _ in 1 }
        await settle(s)
        let advice = try XCTUnwrap(s.oakDungeon)
        XCTAssertEqual(advice.team, picked)
        XCTAssertEqual(advice.capsules, s.oakCapsules(for: picked))

        s.oakWinOdds = { Set($0.team.map(\.entryID)) == Set(picked) ? 1 : 0 }
        await settle(s)
        XCTAssertNil(s.oakDungeon, "a dungeon's threshold reads Prof. Oak's own team")
    }

    func testAChallengeIsJudgedOnTheTeamComposeForMePicks() async throws {
        let s = try store(dex: withIVs) { $0.dungeons.wins = self.wins(self.belowT4) }
        let greedy = s.composeTeam(for: .daily)
        let left = try XCTUnwrap(withIVs.map(\.id).first { !greedy.contains($0) })
        let picked = [left] + greedy.dropFirst()
        s.oakComposeSearch = { _ in picked }
        s.oakWinOdds = { $0.dungeon.id == .daily && Set($0.team.map(\.entryID)) == Set(picked) ? 0.6 : 0 }
        await settle(s)
        XCTAssertEqual(s.oakDungeon?.id, .daily)
        XCTAssertEqual(s.oakDungeon?.reason, .challenge)
        XCTAssertEqual(s.oakDungeon?.team, picked)
        XCTAssertEqual(s.oakDungeon?.win, 0.6)
    }
}
