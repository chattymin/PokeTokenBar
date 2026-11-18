import XCTest
@testable import PokeTokenBar

private struct EventProvider: PokeProviding {
    var entries: [BaseSpecies]
    /// The base index is down: the hatch takes the REST fallback, which knows every species.
    var indexDown = false
    struct Down: Error {}
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: baseSpeciesID, tree: EvoNode(speciesID: baseSpeciesID, children: []),
                rarity: entries.first { $0.id == baseSpeciesID }?.rarity ?? .common, names: [:])
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] {
        if indexDown { throw Down() }
        return entries
    }
    func baseSpecies(id: Int) async throws -> BaseSpecies? {
        indexDown ? BaseSpecies(id: id, captureRate: 45) : entries.first { $0.id == id }
    }
}

/// The year's event eggs (`EventEgg`): each waits during its event and two weeks after, once a year, and hatches the
/// event's Pokémon, shiny when the event promises it.
@MainActor
final class EventEggTests: XCTestCase {
    private let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func at(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12, calendar: Calendar? = nil) -> Date {
        (calendar ?? utc).date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func waiting(_ now: Date, claimed: Set<String> = [], firstCatch: Date? = nil) -> [String] {
        EventEgg.claimable(now: now, claimed: claimed, firstCatch: firstCatch, calendar: utc).map { $0.egg.key(year: $0.year) }
    }

    // MARK: When

    /// During the event and the two weeks after it, then gone; once claimed, gone for the year.
    func testAnEggWaitsTwoWeeksAfterItsEvent() {
        XCTAssertEqual(waiting(at(2026, 12, 19)), ["autumn@2026"], "the season's egg alone")
        XCTAssertEqual(waiting(at(2026, 12, 20, hour: 0)), ["autumn@2026", "christmas@2026"], "the earliest event first")
        XCTAssertEqual(waiting(at(2026, 12, 22)), ["christmas@2026", "winter@2026"])
        XCTAssertTrue(EventEgg.christmas.isOn(year: 2026, now: at(2026, 12, 26, hour: 23), firstCatch: nil, calendar: utc))
        XCTAssertFalse(EventEgg.christmas.isOn(year: 2026, now: at(2026, 12, 27, hour: 0), firstCatch: nil, calendar: utc))
        XCTAssertTrue(waiting(at(2027, 1, 9, hour: 23)).contains("christmas@2026"), "December 27 plus two weeks")
        XCTAssertFalse(waiting(at(2027, 1, 10, hour: 0)).contains("christmas@2026"))
        XCTAssertFalse(waiting(at(2026, 12, 22), claimed: ["christmas@2026"]).contains("christmas@2026"))
        XCTAssertTrue(waiting(at(2027, 12, 22), claimed: ["christmas@2026"]).contains("christmas@2027"), "every year")
    }

    /// A season's egg waits the whole season, once: 2026's autumn one came for three days and was gone before the
    /// eggs shipped. The winter's crosses the year under the year it starts.
    func testASeasonsEggWaitsTheWholeSeason() {
        XCTAssertFalse(waiting(at(2026, 9, 21, hour: 23)).contains("autumn@2026"))
        XCTAssertTrue(waiting(at(2026, 9, 22, hour: 0)).contains("autumn@2026"))
        XCTAssertTrue(waiting(at(2026, 10, 28)).contains("autumn@2026"), "any day of the season")
        XCTAssertTrue(waiting(at(2026, 12, 20, hour: 23)).contains("autumn@2026"))
        XCTAssertFalse(waiting(at(2026, 12, 21, hour: 0)).contains("autumn@2026"), "the winter's takes over")
        XCTAssertFalse(waiting(at(2026, 10, 28), claimed: ["autumn@2026"]).contains("autumn@2026"), "once")
        XCTAssertTrue(EventEgg.autumn.isOn(year: 2026, now: at(2026, 11, 15), firstCatch: nil, calendar: utc))
        XCTAssertTrue(waiting(at(2027, 3, 19, hour: 23)).contains("winter@2026"))
        XCTAssertEqual(waiting(at(2027, 3, 20, hour: 0)).filter { $0.hasPrefix("winter") || $0.hasPrefix("spring") },
                       ["spring@2027"])
        XCTAssertTrue(waiting(at(2027, 8, 1)).contains("summer@2027"))
    }

    /// The New Year's egg starts on December 31 and counts for the year beginning.
    func testTheNewYearCrossesTheYear() {
        XCTAssertEqual(waiting(at(2026, 12, 31)).first { $0.hasPrefix("newYear") }, "newYear@2027")
        XCTAssertTrue(EventEgg.newYear.isOn(year: 2027, now: at(2027, 1, 3, hour: 23), firstCatch: nil, calendar: utc))
        XCTAssertFalse(EventEgg.newYear.isOn(year: 2027, now: at(2027, 1, 4, hour: 0), firstCatch: nil, calendar: utc))
        XCTAssertTrue(waiting(at(2027, 1, 17, hour: 23)).contains("newYear@2027"))
        XCTAssertFalse(waiting(at(2027, 1, 18, hour: 0)).contains("newYear@2027"))
        XCTAssertFalse(waiting(at(2027, 1, 2), claimed: ["newYear@2027"]).contains { $0.hasPrefix("newYear") })
    }

    /// Easter moves: from Good Friday to Easter Monday.
    func testEasterFollowsTheComputus() {
        XCTAssertEqual(EventEgg.easterSunday(2024).month, 3)
        XCTAssertEqual(EventEgg.easterSunday(2024).day, 31)
        XCTAssertEqual(EventEgg.easterSunday(2025).month, 4)
        XCTAssertEqual(EventEgg.easterSunday(2025).day, 20)
        XCTAssertEqual(EventEgg.easterSunday(2026).day, 5)
        XCTAssertEqual(EventEgg.easterSunday(2027).month, 3)
        XCTAssertEqual(EventEgg.easterSunday(2027).day, 28)
        XCTAssertEqual(EventEgg.easterSunday(2028).day, 16)
        let days = EventEgg.easter.days(in: 2027, firstCatch: nil, calendar: utc)
        XCTAssertEqual(days?.start, at(2027, 3, 26, hour: 0), "Good Friday")
        XCTAssertEqual(days?.end, at(2027, 3, 30, hour: 0), "after Easter Monday")
    }

    /// The friendship anniversary follows the first catch, from the year after it; February 29 on February 28.
    func testTheFriendshipDayFollowsTheFirstCatch() {
        let first = at(2025, 3, 10)
        XCTAssertNil(EventEgg.companion.days(in: 2025, firstCatch: first, calendar: utc), "not in its own year")
        XCTAssertNil(EventEgg.companion.days(in: 2026, firstCatch: nil, calendar: utc))
        XCTAssertEqual(EventEgg.companion.days(in: 2026, firstCatch: first, calendar: utc)?.start, at(2026, 3, 10, hour: 0))
        XCTAssertEqual(EventEgg.companion.days(in: 2027, firstCatch: at(2024, 2, 29), calendar: utc)?.start,
                       at(2027, 2, 28, hour: 0))
        XCTAssertEqual(EventEgg.companion.days(in: 2028, firstCatch: at(2024, 2, 29), calendar: utc)?.start,
                       at(2028, 2, 29, hour: 0))
        XCTAssertTrue(waiting(at(2026, 3, 20), firstCatch: first).contains("companion@2026"))
    }

    /// Every egg is an item of the Bag, its own, never sold.
    func testEveryEventHasItsItem() {
        XCTAssertEqual(Set(EventEgg.allCases.map(\.item)).count, EventEgg.allCases.count)
        for egg in EventEgg.allCases {
            XCTAssertEqual(EventEgg(item: egg.item), egg)
            XCTAssertNil(egg.item.shopPrice, "\(egg) is never sold")
            XCTAssertFalse(egg.item.isAchievement)
            XCTAssertEqual(BagView.Section.of(egg.item), .raising)
        }
        XCTAssertNil(EventEgg(item: .birthdayEgg))
    }

    // MARK: The store

    /// Ice lines (Lapras rare, Swinub common, Articuno legendary), Ghost, Kanto and Johto, love, Easter and seasons.
    private let bases = [BaseSpecies(id: 131, captureRate: 45), BaseSpecies(id: 220, captureRate: 225),
                         BaseSpecies(id: 144, captureRate: 3, isUnbreedableLegendary: true),
                         BaseSpecies(id: 92, captureRate: 190), BaseSpecies(id: 1, captureRate: 45),
                         BaseSpecies(id: 4, captureRate: 45), BaseSpecies(id: 252, captureRate: 45),
                         BaseSpecies(id: 370, captureRate: 225), BaseSpecies(id: 175, captureRate: 190),
                         BaseSpecies(id: 585, captureRate: 190), BaseSpecies(id: 37, captureRate: 190),
                         BaseSpecies(id: 361, captureRate: 190), BaseSpecies(id: 138, captureRate: 45)]

    private let christmas21 = Calendar.current.date(from: DateComponents(year: 2026, month: 12, day: 21, hour: 12))!

    private func store(seed: UInt64 = 1, now: Date? = nil, indexDown: Bool = false,
                       _ edit: (inout CompanionState) -> Void = { _ in }) throws -> CompanionStore {
        var st = CompanionState()
        st.installBaselineSet = true
        st.lastDate = "2026-12-21"
        edit(&st)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("event-egg-\(UUID().uuidString).json")
        try JSONEncoder().encode(st).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let clock = now ?? christmas21
        return CompanionStore(provider: EventProvider(entries: bases, indexDown: indexDown), clock: { clock },
                              fileURL: url, rng: SeededRNG(seed: seed))
    }

    /// Taken once for its year, kept by the save, announced once.
    func testAnEggIsTakenOncePerYear() throws {
        let s = try store()
        XCTAssertEqual(s.eventEggs.map(\.egg), [.christmas, .winter])
        XCTAssertTrue(s.isEventOn(.christmas, year: 2026))
        XCTAssertTrue(s.claimEventEgg(.christmas))
        XCTAssertEqual(s.itemCount(.christmasEgg), 1)
        XCTAssertEqual(s.eventEggs.map(\.egg), [.winter])
        XCTAssertFalse(s.claimEventEgg(.christmas), "once a year")
        XCTAssertEqual(s.itemCount(.christmasEgg), 1)
        let kept = try JSONDecoder().decode(CompanionState.self, from: JSONEncoder().encode(s.state))
        XCTAssertEqual(kept.claimedEventEggs, ["christmas@2026"])

        s.update(todayTokensByProvider: [:], todayDate: "2026-12-21", monthTotal: 0, burnTier: .idle,
                 limitWarning: false, hasUsageData: false)
        XCTAssertEqual(s.state.eventEggsNotified, ["winter@2026"], "the egg taken needs no notification")
    }

    /// Used, the egg sends the Pokémon off for an egg drawn as the event's, then hatches.
    private func hatch(_ egg: EventEgg, seed: UInt64, _ edit: (inout CompanionState) -> Void = { _ in }) async throws -> MonState {
        let mon = try await tryHatch(egg, seed: seed, edit)
        return try XCTUnwrap(mon, "\(egg) seed \(seed) kept its egg")
    }

    private func tryHatch(_ egg: EventEgg, seed: UInt64, indexDown: Bool = false,
                          _ edit: (inout CompanionState) -> Void = { _ in }) async throws -> MonState? {
        let s = try store(seed: seed, indexDown: indexDown) {
            edit(&$0)
            $0.active = MonState(baseID: 252, pathIDs: [252], stageIndex: 0, usedAtStage: 0, rarity: .common, totalForms: 1)
            $0.inventory = [egg.item.rawValue: 1]
        }
        XCTAssertTrue(s.useEventEgg(egg))
        XCTAssertEqual(s.itemCount(egg.item), 0)
        XCTAssertEqual(s.eggKind, .event(egg))
        s.setEggUsageForTesting(s.eggHatchThreshold)
        await s.hatchIfNeeded()
        // nil when no candidate came (the REST fallback's tries), the egg kept for the next tick.
        guard let mon = s.state.active else { return nil }
        XCTAssertNil(s.state.eggEvent, "consumed by the hatch")
        return mon
    }

    func testEachEggHatchesItsEventsPokemon() async throws {
        for seed: UInt64 in 1...8 {
            let ice = try await hatch(.christmas, seed: seed)
            XCTAssertTrue([131, 144].contains(ice.baseID), "Ice, rare or better: \(ice.baseID)")
            XCTAssertTrue(ice.isShiny)

            let ghost = try await hatch(.halloween, seed: seed)
            XCTAssertEqual(ghost.baseID, 92)
            XCTAssertTrue(ghost.isShiny)

            let legend = try await hatch(.newYear, seed: seed)
            XCTAssertEqual(legend.baseID, 144)

            let kanto = try await hatch(.pokemonDay, seed: seed)
            XCTAssertLessThanOrEqual(kanto.baseID, 151)
            XCTAssertTrue(kanto.isShiny)

            let love = try await hatch(.valentine, seed: seed)
            XCTAssertEqual(love.baseID, 370)
            XCTAssertTrue(love.isShiny)

            let easter = try await hatch(.easter, seed: seed)
            XCTAssertEqual(easter.baseID, 175)
            XCTAssertTrue(easter.isShiny)
        }
    }

    /// The friendship egg hatches the first catch's line again, shiny.
    /// [Regression] Pokémon Day's egg admits the lines that grow into Kanto Pokémon from a later baby: taking number
    /// 151 or lower only, it could never hatch Pikachu, Clefairy, Jigglypuff, the Hitmons, Jynx, Electabuzz, Magmar,
    /// Mr. Mime, Chansey or Snorlax.
    func testPokemonDaysEggAdmitsKantoLinesFromALaterBaby() {
        func admits(_ id: Int) -> Bool { EventEgg.pokemonDay.admits(BaseSpecies(id: id, captureRate: 45), companionLine: nil) }
        for baby in [172, 173, 174, 236, 238, 239, 240, 439, 440, 446] { XCTAssertTrue(admits(baby), "\(baby)") }
        XCTAssertTrue(admits(1))
        XCTAssertTrue(admits(151))
        XCTAssertFalse(admits(175), "Togepi grows into Johto and Sinnoh Pokémon only")
        XCTAssertFalse(admits(298), "Azurill grows into Marill, a Johto Pokémon")
        XCTAssertFalse(admits(152))
    }

    func testTheFriendshipEggBringsTheFirstCatchBack() async throws {
        let long = Date(timeIntervalSince1970: 1_700_000_000)
        for seed: UInt64 in 1...4 {
            let mon = try await hatch(.companion, seed: seed) {
                $0.dex = [DexEntry(baseID: 4, finalID: 4, chainOrder: [4], rarity: .common, caughtAt: long),
                          DexEntry(baseID: 1, finalID: 1, chainOrder: [1], rarity: .common,
                                   caughtAt: long.addingTimeInterval(86_400))]
            }
            XCTAssertEqual(mon.baseID, 4)
            XCTAssertTrue(mon.isShiny)
        }
    }

    /// Regression: a first catch that was a Ditto (its record carries Ditto's number once revealed, which no egg's
    /// pool holds) kept the Friendship Egg waiting forever, and nothing else could be used meanwhile. The next catch's
    /// line comes instead. An event whose Pokémon the pool lacks hatches as a plain egg.
    func testTheFriendshipEggNeverWaitsForever() async throws {
        let long = Date(timeIntervalSince1970: 1_700_000_000)
        let ditto = DexEntry(baseID: 132, finalID: 132, chainOrder: [132], rarity: .common, caughtAt: long)
        let charmander = DexEntry(baseID: 4, finalID: 4, chainOrder: [4], rarity: .common,
                                  caughtAt: long.addingTimeInterval(86_400))
        for seed: UInt64 in 1...4 {
            let mon = try await tryHatch(.companion, seed: seed) { $0.dex = [ditto, charmander] }
            XCTAssertEqual(mon?.baseID, 4, "seed \(seed): the first catch that is no Ditto")
            XCTAssertEqual(mon?.isShiny, true)

            let missing = DexEntry(baseID: 25, finalID: 25, chainOrder: [25], rarity: .common, caughtAt: long)
            let plain = try await tryHatch(.companion, seed: seed) { $0.dex = [missing] }
            XCTAssertNotNil(plain, "seed \(seed): a line the pool lacks hatches as a plain egg")
        }
    }

    /// A first catch that is a fossil line sent off before it graduated hatches from no egg but a Fossil Egg; the
    /// Friendship Egg still brings it back, from the index and from the REST fallback.
    func testTheFriendshipEggHatchesAFossilFirstCatchNotGraduated() async throws {
        let long = Date(timeIntervalSince1970: 1_700_000_000)
        let omanyte = DexEntry(baseID: 138, finalID: 138, chainOrder: [138], rarity: .common, caughtAt: long)
        let later = DexEntry(baseID: 1, finalID: 1, chainOrder: [1], rarity: .common, caughtAt: long.addingTimeInterval(86_400))
        for seed: UInt64 in 1...4 {
            for indexDown in [false, true] {
                let mon = try await tryHatch(.companion, seed: seed, indexDown: indexDown) {
                    $0.dex = [omanyte.releasedNow(at: long.addingTimeInterval(3_600)), later]
                }
                XCTAssertEqual(mon?.baseID, 138, "seed \(seed) indexDown \(indexDown)")
                XCTAssertEqual(mon?.isShiny, true)
            }
        }
    }

    /// An event egg's type and rarity are the event's: the Tera Orb and the Sea Incense, which speed a stone's and a
    /// Shop egg, leave it as it is.
    func testTheEggSpeedItemsLeaveAnEventEgg() throws {
        let raising = MonState(baseID: 252, pathIDs: [252], stageIndex: 0, usedAtStage: 0, rarity: .common, totalForms: 1)
        let plain = try store {
            $0.active = raising
            $0.inventory = [EventEgg.christmas.item.rawValue: 1]
        }
        let s = try store {
            $0.active = raising
            $0.inventory = [EventEgg.christmas.item.rawValue: 1, ItemKind.teraOrb.rawValue: 1, ItemKind.seaIncense.rawValue: 1]
        }
        XCTAssertTrue(plain.useEventEgg(.christmas))
        XCTAssertTrue(s.useEventEgg(.christmas))
        XCTAssertNotNil(s.state.eggTier)
        XCTAssertNotNil(s.state.eggTypeGuarantee)
        XCTAssertEqual(s.eggHatchThreshold, plain.eggHatchThreshold)
        // The same guarantees from no event: both items halve it.
        let stone = try store {
            $0.active = nil
            $0.eggTier = .rare
            $0.eggTypeGuarantee = .ice
            $0.inventory = [ItemKind.teraOrb.rawValue: 1, ItemKind.seaIncense.rawValue: 1]
        }
        XCTAssertEqual(stone.eggHatchThreshold, plain.eggHatchThreshold / 4)
    }

    /// A season's Deerling follows the rules of every egg: not the line hatched last, and with the Oval Charm, not a
    /// form already collected.
    func testTheSeasonsDeerlingKeepsTheLastHatchedRuleAndTheOvalCharm() async throws {
        for seed: UInt64 in 1...24 {
            let afterDeerling = try await hatch(.winter, seed: seed) { $0.lastHatchedBaseID = EventEgg.deerlingID }
            XCTAssertNotEqual(afterDeerling.baseID, EventEgg.deerlingID, "seed \(seed)")
            // `hatch` sets the Bag itself: the charm goes in by hand.
            let s = try store(seed: seed) {
                $0.dex = [DexEntry(baseID: EventEgg.deerlingID, finalID: 586, chainOrder: [585, 586], rarity: .common,
                                   caughtAt: Date(timeIntervalSince1970: 1_700_000_000), form: PokemonForm("winter"))]
                $0.active = MonState(baseID: 252, pathIDs: [252], stageIndex: 0, usedAtStage: 0, rarity: .common, totalForms: 1)
                $0.inventory = [EventEgg.winter.item.rawValue: 1, ItemKind.ovalCharm.rawValue: 1]
            }
            XCTAssertTrue(s.useEventEgg(.winter))
            s.setEggUsageForTesting(s.eggHatchThreshold)
            await s.hatchIfNeeded()
            let charmed = try XCTUnwrap(s.state.active, "seed \(seed)")
            XCTAssertNotEqual(charmed.baseID, EventEgg.deerlingID, "winter Deerling already collected, seed \(seed)")
        }
    }

    /// A season's egg: Deerling in the season's form one time in three, else a Pokémon of the season's types, in a
    /// form that has one, Uncommon or better (asked on 2026-10-29): the Common ones, an Alolan Vulpix among them, no
    /// longer come; Deerling, Common, stays the exception.
    func testASeasonEggHatchesDeerlingOrTheSeasonsTypes() async throws {
        var seen = Set<Int>()
        for seed: UInt64 in 1...24 {
            let mon = try await hatch(.winter, seed: seed)
            seen.insert(mon.baseID)
            if mon.baseID == EventEgg.deerlingID {
                XCTAssertEqual(mon.form, PokemonForm("winter"), "seed \(seed)")
            } else {
                let types = PokemonTypeData.types(forSpeciesID: mon.baseID, form: mon.form)
                XCTAssertTrue(types.contains { [.ice, .steel, .dragon].contains($0) },
                              "\(mon.baseID) \(String(describing: mon.form)) is \(types), seed \(seed)")
            }
        }
        XCTAssertTrue(seen.contains(EventEgg.deerlingID))
        XCTAssertTrue(seen.isDisjoint(with: [37, 220, 361]), "no Common but Deerling: \(seen.sorted())")
        XCTAssertTrue(seen.contains(131), "Lapras, Rare, comes")
        XCTAssertFalse(seen.contains(1))
        XCTAssertEqual(EventEgg.autumn.tier, .uncommon)
        XCTAssertNil(EventEgg.halloween.tier)
    }

    /// The base index down, the REST fallback keeps the event's pool and its shiny promise.
    func testTheRestFallbackKeepsTheShinyPromise() async throws {
        var hatched = 0
        for seed: UInt64 in 1...6 {
            guard let mon = try await tryHatch(.pokemonDay, seed: seed, indexDown: true) else { continue }
            hatched += 1
            XCTAssertLessThanOrEqual(mon.baseID, 151)
            XCTAssertTrue(mon.isShiny, "seed \(seed)")
        }
        XCTAssertGreaterThan(hatched, 0)
    }

    /// The base index down, an egg of a few lines asks for them: it hatches one on every try. It used to draw 32
    /// random numbers among 1,025 and seldom met one, the Friendship Egg's single line least of all.
    func testTheRestFallbackOfAnEggOfFewLinesHatchesEveryTime() async throws {
        let first = DexEntry(baseID: 4, finalID: 4, chainOrder: [4], rarity: .common, caughtAt: Date(timeIntervalSince1970: 1_700_000_000))
        for seed: UInt64 in 1...8 {
            let love = try await tryHatch(.valentine, seed: seed, indexDown: true)
            XCTAssertTrue(EventEgg.valentineLines.contains(try XCTUnwrap(love, "seed \(seed)").baseID))
            let easter = try await tryHatch(.easter, seed: seed, indexDown: true) { $0.lastHatchedBaseID = 175 }
            let easterLine = try XCTUnwrap(easter, "seed \(seed)").baseID
            XCTAssertTrue(EventEgg.easterLines.contains(easterLine))
            XCTAssertNotEqual(easterLine, 175, "not the line hatched last while another is left")
            let friend = try await tryHatch(.companion, seed: seed, indexDown: true) {
                $0.dex = [first]
                $0.lastHatchedBaseID = 4
            }
            XCTAssertEqual(friend?.baseID, 4, "its only line, even hatched last")
        }
    }

    /// An imported save with a Pokémon being raised drops an event guarantee left beside it.
    func testAnImportedSaveDropsAStrayEventGuarantee() {
        var st = CompanionState()
        st.active = MonState(baseID: 1, pathIDs: [1], stageIndex: 0, usedAtStage: 0, rarity: .common, totalForms: 1)
        st.eggEvent = .christmas
        st.claimedEventEggs = ["christmas@2026"]
        let clean = SaveTransfer.sanitized(st)
        XCTAssertNil(clean.eggEvent)
        XCTAssertEqual(clean.claimedEventEggs, ["christmas@2026"], "the record of eggs taken travels")
    }
}

private extension DexEntry {
    /// The record of a Pokémon sent off for an egg before it graduated.
    func releasedNow(at date: Date) -> DexEntry {
        var entry = self
        entry.releasedAt = date
        return entry
    }
}
