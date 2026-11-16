import XCTest
@testable import PokeTokenBar

/// Home while a team explores, as Prof. Oak's card (the owner, 2026-11-10, choice C): a circle a floor with what happened
/// there, its journal line on hover, nothing for a floor ahead; the guide's words.
@MainActor
final class ExpeditionGuideTests: XCTestCase {
    private func battle(_ kind: ExpeditionEventKind, won: Bool, foes: Int) throws -> ExpeditionBattle {
        let ours = try XCTUnwrap(BattlerSpec.make(id: "a", speciesID: 248, level: 100))
        let theirs = try (0..<foes).map { try XCTUnwrap(BattlerSpec.make(id: "f\($0)", speciesID: 41, level: 50)) }
        let setup = BattleSetup(sides: [BattleSideSpec(battlers: [ours], active: 1), BattleSideSpec(battlers: theirs, active: 1)],
                                seed: 1)
        return ExpeditionBattle(kind: kind, setup: setup, won: won, duration: 1000, foes: theirs.map(\.speciesID))
    }

    private func entry(_ floor: Int, _ kind: ExpeditionLogKind) -> ExpeditionLogEntry {
        ExpeditionLogEntry(id: floor * 10, floor: floor, date: Date(timeIntervalSince1970: 0), kind: kind)
    }

    func testEachFloorShowsWhatHappenedThere() throws {
        let log = [entry(1, .battle(try battle(.wild, won: true, foes: 1))),
                   entry(2, .battle(try battle(.horde, won: true, foes: 4))),
                   entry(2, .chest(ExpeditionLoot(candies: 2))),
                   entry(3, .trap(percent: 10, item: nil)),
                   entry(4, .shiny(speciesID: 41, caught: true)),
                   entry(4, .battle(try battle(.trainer, won: false, foes: 3)))]
        XCTAssertEqual(ExpeditionLogText.symbol(floor: 1, log: log)?.0, "bolt.fill")
        XCTAssertEqual(ExpeditionLogText.symbol(floor: 2, log: log)?.0, "shippingbox.fill", "a find before a fight")
        XCTAssertEqual(ExpeditionLogText.symbol(floor: 3, log: log)?.0, "exclamationmark.triangle.fill")
        XCTAssertEqual(ExpeditionLogText.symbol(floor: 4, log: log)?.0, "sparkles", "a shiny first")
        XCTAssertNil(ExpeditionLogText.symbol(floor: 5, log: log), "nothing written there")
    }

    func testTheTooltipIsTheFloorsJournal() throws {
        var s = CompanionState()
        s.language = .fr
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("guide-\(UUID()).json")
        try JSONEncoder().encode(s).write(to: file)
        addTeardownBlock { try? FileManager.default.removeItem(at: file) }
        let store = CompanionStore(provider: StubProvider(value: EvoLine(baseID: 16, tree: EvoNode(speciesID: 16, children: []),
                                                                         rarity: .common, names: [:])), fileURL: file)
        let log = [entry(2, .battle(try battle(.horde, won: true, foes: 4))), entry(2, .chest(ExpeditionLoot(candies: 2)))]
        XCTAssertEqual(ExpeditionLogText.floor(2, log: log, floors: 12, store: store),
                       "Horde · 4 adversaires · Victoire\nCoffre · Super Bonbon ×2")
        XCTAssertEqual(ExpeditionLogText.floor(3, log: log, floors: 12, store: store), "", "a floor ahead says nothing")
    }

    /// The return's prize (the owner, 2026-11-10): the boss's own egg, else the one in its place, else none (the boss
    /// beaten is shown); a challenge and a hideout show their boss.
    func testTheReturnsPrize() throws {
        let start = Date(timeIntervalSince1970: 0)
        func result(_ dungeon: DungeonID, caught: Bool, reward: Expedition.BossReward?, eggs: [DungeonEgg] = []) -> ExpeditionResult {
            var loot = ExpeditionLoot()
            loot.eggs = eggs
            return ExpeditionResult(dungeon: dungeon, won: true, startedAt: start, endedAt: start, tokens: 1, battles: 1,
                                    boss: ExpeditionBoss(speciesID: 150, form: nil, isShiny: false), caught: caught, loot: loot,
                                    firstVictory: false, unlocked: [], unlockedMove: nil, bossReward: reward, log: [])
        }
        let own = DungeonEgg(id: "a", baseID: 150, form: nil, isShiny: false, sourceSpeciesID: 150)
        XCTAssertEqual(ExpeditionResultGuide.egg(result(.ceruleanCave, caught: true, reward: nil, eggs: [own]))?.kind, .dungeon(150))
        XCTAssertEqual(ExpeditionResultGuide.egg(result(.ceruleanCave, caught: true, reward: .legendaryEgg))?.item, .legendaryEgg)
        XCTAssertNil(ExpeditionResultGuide.egg(result(.ceruleanCave, caught: false, reward: nil)), "not caught: the boss is shown")
        XCTAssertNil(ExpeditionResultGuide.egg(result(.daily, caught: false, reward: nil)), "a challenge shows its form")
        XCTAssertNil(ExpeditionResultGuide.egg(result(.rocketHideout, caught: false, reward: nil)), "a hideout shows its leader's ace")
    }

    func testTheGuidesWordsInEveryLanguage() {
        for language in AppLanguage.allCases {
            let l = L(language)
            let words = [l.guideFloors(done: 0), l.guideFloors(done: 5), l.guideFainted(["A"]), l.guideFainted(["A", "B"]),
                         l.guideWeak(["A"]), l.guideWeak(["A", "B", "C"]), l.guideBoss(at: 12), l.guideNeedsHeal, l.guideFoes(1),
                         l.guideFoes(4), l.guideResult(won: true, roped: false), l.guideResult(won: false, roped: true),
                         l.guideResult(won: false, roped: false), l.listed(["A", "B", "C"]), l.guideKOAlert,
                         l.guideFell(floor: 5, of: 12, against: nil), l.guideFell(floor: 5, of: 12, against: .horde),
                         l.guideFell(floor: 5, of: 12, against: .trainer), l.guideFell(floor: 12, of: 12, against: .boss),
                         l.guideTurnedBack(floor: 4, of: 12), l.guideKept(true), l.guideKept(false), l.guideTryAgain]
            for text in words {
                XCTAssertFalse(text.isEmpty || text.contains("\u{2014}") || text.contains("\u{2013}"), "\(language): \(text)")
            }
        }
        XCTAssertEqual(L(.fr).listed(["Léviator", "Mégagnathe", "Ectoplasma"]), "Léviator, Mégagnathe et Ectoplasma")
    }

    /// The owner, 2026-11-16 (the floor cards): the floor crossed, the one under way, the next, the boss; none crossed on
    /// the first floor, no next one when only the boss's floor is left, past the last floor the last one.
    func testTheFloorCardsFollowTheTeam() {
        typealias Slot = ExpeditionFloorCards.Slot
        XCTAssertEqual(ExpeditionFloorCards.slots(floor: 1, floors: 5), [Slot.current(1), .ahead(2), .boss])
        XCTAssertEqual(ExpeditionFloorCards.slots(floor: 3, floors: 5), [Slot.crossed(2), .current(3), .ahead(4), .boss])
        XCTAssertEqual(ExpeditionFloorCards.slots(floor: 4, floors: 5), [Slot.crossed(3), .current(4), .boss])
        XCTAssertEqual(ExpeditionFloorCards.slots(floor: 5, floors: 5), [Slot.crossed(4), .current(5), .boss])
        XCTAssertEqual(ExpeditionFloorCards.slots(floor: 6, floors: 5), [Slot.crossed(4), .current(5), .boss], "the boss's fight")
    }

    /// A floor's card names its main event as its stroke colors it: a find before a fight.
    func testAFloorIsNamedByItsMainEvent() {
        let chest = ExpeditionLogEntry(id: 1, floor: 2, date: Date(), kind: .chest(ExpeditionLoot(candies: 1)))
        let spring = ExpeditionLogEntry(id: 2, floor: 2, date: Date(), kind: .spring(percent: 50))
        XCTAssertEqual(ExpeditionLogText.eventKind(floor: 2, log: [spring, chest]), .chest)
        XCTAssertEqual(ExpeditionLogText.eventKind(floor: 2, log: [spring]), .spring)
        XCTAssertNil(ExpeditionLogText.eventKind(floor: 3, log: [spring, chest]))
    }

    /// [Regression] The owner, 2026-11-16: the boss card showed the silhouette of a boss never met, which the dungeon's
    /// page keeps as a "?". Not reached on the run: a silhouette once met in this dungeon, a "?" before; a challenge's
    /// and a hideout leader's are known.
    func testTheBossCardNeverGivesAwayABossNeverMet() {
        var progress = DungeonProgress()
        typealias Card = ExpeditionFloorCards
        XCTAssertEqual(Card.bossLook(dungeon: .ceruleanCave, speciesID: 150, reachedHere: false, progress: progress), .unknown)
        XCTAssertEqual(Card.bossLook(dungeon: .ceruleanCave, speciesID: 150, reachedHere: true, progress: progress), .whole)
        progress.bossesReached.insert(DungeonProgress.bossKey(.ceruleanCave, 150))
        XCTAssertEqual(Card.bossLook(dungeon: .ceruleanCave, speciesID: 150, reachedHere: false, progress: progress), .silhouette)
        XCTAssertEqual(Card.bossLook(dungeon: .mtMoon, speciesID: 150, reachedHere: false, progress: progress), .unknown,
                       "met in another dungeon")
        XCTAssertEqual(Card.bossLook(dungeon: .daily, speciesID: 448, reachedHere: false, progress: DungeonProgress()), .whole)
        XCTAssertEqual(Card.bossLook(dungeon: .rocketHideout, speciesID: 150, reachedHere: false, progress: DungeonProgress()), .whole)
    }
}
