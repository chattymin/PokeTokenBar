import XCTest
@testable import PokeTokenBar

private struct BirthdayProvider: PokeProviding {
    var entries: [BaseSpecies]
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        let legendary = entries.first { $0.id == baseSpeciesID }?.isLegendary == true
        return EvoLine(baseID: baseSpeciesID, tree: EvoNode(speciesID: baseSpeciesID, children: []),
                       rarity: legendary ? .legendary : .common, names: [:])
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { entries }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { entries.first { $0.id == id } }
}

/// The base index unavailable: only the REST answers, for any species asked.
private struct NoIndexProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: baseSpeciesID, tree: EvoNode(speciesID: baseSpeciesID, children: []), rarity: .legendary, names: [:])
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { throw URLError(.badServerResponse) }
    func baseSpecies(id: Int) async throws -> BaseSpecies? {
        let legendary = SpeciesGoal.mythicals.contains(id) || SpeciesGoal.legendaries.contains(id)
        return BaseSpecies(id: id, captureRate: legendary ? 3 : 45, isUnbreedableLegendary: legendary,
                           isLegendary: legendary)
    }
}

/// The birthday gift (#65): the Birthday Egg, claimable for a week from the birthday, or for three months by a save
/// that never got one, once a year; it hatches a mythical not graduated yet, then a legendary, then a shiny one.
@MainActor
final class BirthdayGiftTests: XCTestCase {
    private let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func at(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        utc.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func claimable(_ birthday: Birthday?, lastGift: Int?, _ now: Date) -> (Int, BirthdayGift.Occasion)? {
        BirthdayGift.claimable(birthday: birthday, lastGiftYear: lastGift, now: now, calendar: utc).map { ($0.year, $0.occasion) }
    }

    /// A week from the birthday for a player who already got gifts; three months for a first one.
    func testTheGiftWaitsThreeMonths() throws {
        let march10 = try XCTUnwrap(Birthday(month: 3, day: 10))
        XCTAssertNil(claimable(nil, lastGift: nil, at(2027, 3, 10)), "no birthday, no gift")
        XCTAssertNil(claimable(march10, lastGift: 2026, at(2027, 3, 9)), "not yet")
        XCTAssertEqual(claimable(march10, lastGift: 2026, at(2027, 3, 10, hour: 0))?.0, 2027)
        XCTAssertEqual(claimable(march10, lastGift: 2026, at(2027, 3, 16, hour: 23))?.1, .birthday)
        XCTAssertEqual(claimable(march10, lastGift: 2026, at(2027, 3, 17, hour: 0))?.1, .belated, "after its week")
        XCTAssertEqual(claimable(march10, lastGift: 2026, at(2027, 6, 9))?.0, 2027, "three months, every year")
        XCTAssertNil(claimable(march10, lastGift: 2026, at(2027, 6, 10, hour: 1)), "three months have passed")
        XCTAssertNil(claimable(march10, lastGift: 2027, at(2027, 3, 10)), "once a year")

        XCTAssertEqual(claimable(march10, lastGift: nil, at(2027, 3, 12))?.1, .birthday)
        XCTAssertEqual(claimable(march10, lastGift: nil, at(2027, 6, 9))?.1, .belated, "never got one: three months")
        XCTAssertEqual(claimable(march10, lastGift: nil, at(2027, 6, 9))?.0, 2027)
        XCTAssertNil(claimable(march10, lastGift: nil, at(2027, 6, 10, hour: 1)), "three months have passed")
    }

    /// February 29 comes on February 28 in other years; a birthday in late December claimed in January counts for
    /// the year before.
    func testLeapDaysAndTheTurnOfTheYear() throws {
        let leap = try XCTUnwrap(Birthday(month: 2, day: 29))
        XCTAssertEqual(claimable(leap, lastGift: 2026, at(2027, 2, 28))?.0, 2027)
        XCTAssertNil(claimable(leap, lastGift: 2027, at(2028, 2, 28)), "2028 has its own February 29")
        XCTAssertEqual(claimable(leap, lastGift: 2027, at(2028, 2, 29))?.0, 2028)

        let december30 = try XCTUnwrap(Birthday(month: 12, day: 30))
        XCTAssertEqual(claimable(december30, lastGift: 2025, at(2027, 1, 2))?.0, 2026)
        XCTAssertEqual(claimable(december30, lastGift: 2026, at(2027, 12, 30))?.0, 2027, "the next one still comes")

        XCTAssertNil(Birthday(month: 4, day: 31))
        XCTAssertNil(Birthday(month: 13, day: 1))
    }

    /// The save keeps the birthday and the last year gifted; a day that cannot exist is dropped, not the save.
    func testTheSaveKeepsTheBirthday() throws {
        var st = CompanionState()
        st.birthday = Birthday(month: 7, day: 14)
        st.lastBirthdayGiftYear = 2026
        let kept = try JSONDecoder().decode(CompanionState.self, from: JSONEncoder().encode(st))
        XCTAssertEqual(kept.birthday, Birthday(month: 7, day: 14))
        XCTAssertEqual(kept.lastBirthdayGiftYear, 2026)

        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(st)) as? [String: Any])
        json["birthday"] = ["month": 2, "day": 31]
        let read = try JSONDecoder().decode(CompanionState.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(read.birthday)
        XCTAssertEqual(read.lastBirthdayGiftYear, 2026)
    }

    // MARK: The store

    private let now = Date(timeIntervalSince1970: 1_793_000_000)
    /// Two mythicals, a legendary and a common line.
    private let bases = [BaseSpecies(id: 151, captureRate: 45, isUnbreedableLegendary: true),
                         BaseSpecies(id: 251, captureRate: 45, isUnbreedableLegendary: true),
                         BaseSpecies(id: 144, captureRate: 3, isUnbreedableLegendary: true),
                         BaseSpecies(id: 1, captureRate: 45)]

    private func store(seed: UInt64 = 1, _ edit: (inout CompanionState) -> Void) throws -> CompanionStore {
        var st = CompanionState()
        st.installBaselineSet = true
        st.lastDate = "2026-10-26"
        edit(&st)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("birthday-\(UUID().uuidString).json")
        try JSONEncoder().encode(st).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return CompanionStore(provider: BirthdayProvider(entries: bases), clock: { self.now }, fileURL: url,
                              rng: SeededRNG(seed: seed))
    }

    private var todaysBirthday: Birthday {
        let parts = Calendar.current.dateComponents([.month, .day], from: now)
        return Birthday(month: parts.month!, day: parts.day!)!
    }

    private func graduated(_ ids: [Int]) -> [DexEntry] {
        ids.map { DexEntry(baseID: $0, finalID: $0, chainOrder: [$0], rarity: .legendary, caughtAt: now) }
    }

    /// The gift goes to the Bag once; changing the date the same year brings no second one.
    func testTheGiftIsClaimedOncePerYear() throws {
        let s = try store { _ in }
        XCTAssertNil(s.birthdayGift)
        s.setBirthday(todaysBirthday)
        let year = Calendar.current.component(.year, from: now)
        XCTAssertEqual(s.birthdayGift?.year, year)
        XCTAssertEqual(s.birthdayGift?.occasion, .birthday)
        XCTAssertTrue(s.claimBirthdayGift())
        XCTAssertEqual(s.itemCount(.birthdayEgg), 1)
        XCTAssertEqual(s.state.lastBirthdayGiftYear, year)
        XCTAssertNil(s.birthdayGift)
        XCTAssertFalse(s.claimBirthdayGift())
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        let parts = Calendar.current.dateComponents([.month, .day], from: yesterday)
        s.setBirthday(Birthday(month: parts.month!, day: parts.day!))
        if Calendar.current.component(.year, from: yesterday) == year {
            XCTAssertNil(s.birthdayGift, "another date the same year brings nothing")
        }
        XCTAssertFalse(ItemKind.birthdayEgg.isAchievement)
        XCTAssertNil(ItemKind.birthdayEgg.shopPrice, "never sold")
        XCTAssertEqual(BagView.Section.of(.birthdayEgg), .raising)
    }

    /// A new date after a gift never brings a second egg within a year. A December 30 gift claimed on January 2
    /// counts for the year before; moved to February 1, the birthday would bring another in February.
    func testANewDateAfterAGiftWaitsForALaterYear() throws {
        let february = try XCTUnwrap(Birthday(month: 2, day: 1))
        let gift = { (changed: Int?, now: Date) in
            BirthdayGift.claimable(birthday: february, lastGiftYear: 2026, changedAfterGiftYear: changed, now: now,
                                   calendar: self.utc)?.year
        }
        XCTAssertEqual(gift(nil, at(2027, 2, 3)), 2027, "a player who kept February 1 gets it")
        XCTAssertNil(gift(2027, at(2027, 2, 3)), "changed after a gift claimed in January 2027")
        XCTAssertEqual(gift(2027, at(2028, 2, 3)), 2028)

        // In the app: the claim's calendar year is kept, and a change after it waits for a later birthday year.
        let s = try store { _ in }
        s.setBirthday(todaysBirthday)
        XCTAssertTrue(s.claimBirthdayGift())
        let year = Calendar.current.component(.year, from: now)
        XCTAssertEqual(s.state.lastBirthdayGiftClaimedAt, now)
        XCTAssertNil(s.state.birthdayChangedAfterGiftYear, "no change yet")
        let earlier = Calendar.current.date(byAdding: .day, value: -2, to: now)!
        let parts = Calendar.current.dateComponents([.month, .day], from: earlier)
        s.setBirthday(Birthday(month: parts.month!, day: parts.day!))
        XCTAssertEqual(s.state.birthdayChangedAfterGiftYear, year)
        XCTAssertNil(s.birthdayGift)
        let kept = try JSONDecoder().decode(CompanionState.self, from: JSONEncoder().encode(s.state))
        XCTAssertEqual(kept.birthdayChangedAfterGiftYear, year)
        XCTAssertEqual(kept.lastBirthdayGiftClaimedAt, now)
    }

    /// Regression (#83): Settings clear the date, then set a month, then a day. Typing the gift's date again that way
    /// is no change: a December 30 gift claimed on January 2, 2028 still lets December 30, 2028 bring one.
    func testTypingTheSameDateAgainKeepsNextYearsGift() throws {
        let december30 = try XCTUnwrap(Birthday(month: 12, day: 30))
        let s = try store {
            $0.birthday = december30
            $0.lastBirthdayGiftYear = 2027
            $0.lastBirthdayGiftClaimedAt = self.at(2028, 1, 2)
        }
        s.setBirthday(nil)
        s.setBirthday(Birthday(month: 12, day: 1))
        s.setBirthday(december30)
        XCTAssertNil(s.state.birthdayChangedAfterGiftYear, "back to the gift's date")
        XCTAssertEqual(s.state.lastBirthdayGiftDate, december30)
        XCTAssertEqual(BirthdayGift.claimable(birthday: s.state.birthday, lastGiftYear: s.state.lastBirthdayGiftYear,
                                              changedAfterGiftYear: s.state.birthdayChangedAfterGiftYear,
                                              now: at(2028, 12, 30), calendar: utc)?.year, 2028)
        s.setBirthday(Birthday(month: 2, day: 1))
        XCTAssertEqual(s.state.birthdayChangedAfterGiftYear, 2028, "a really new date still waits")
    }

    /// Regression (#92): a save from before #88 keeps no gift date. Changed after a gift, its date is not the gift's, and
    /// was taken for it: cleared and typed again, February 10 lifted the block, and February 10, 2028 brought a second
    /// egg five weeks after a December 30 gift claimed on January 2, 2028. The gift's date is unknown there, so no date
    /// typed lifts the block, the gift's own included. A save whose date never moved since its gift keeps #83's rule
    /// (`testTypingTheSameDateAgainKeepsNextYearsGift`).
    func testRetypingADateChangedAfterAGiftOnAnOldSaveKeepsTheBlock() throws {
        let february10 = try XCTUnwrap(Birthday(month: 2, day: 10))
        let december30 = try XCTUnwrap(Birthday(month: 12, day: 30))
        let june1 = try XCTUnwrap(Birthday(month: 6, day: 1))
        func oldSave() throws -> CompanionStore {
            try store {
                $0.birthday = february10
                $0.lastBirthdayGiftYear = 2027
                $0.lastBirthdayGiftClaimedAt = self.at(2028, 1, 2)
                $0.birthdayChangedAfterGiftYear = 2028
            }
        }
        func gift(_ s: CompanionStore, _ now: Date) -> Int? {
            BirthdayGift.claimable(birthday: s.state.birthday, lastGiftYear: s.state.lastBirthdayGiftYear,
                                   changedAfterGiftYear: s.state.birthdayChangedAfterGiftYear, now: now, calendar: utc)?.year
        }

        // As Settings do it: clear the date, then a month, then the day.
        let s = try oldSave()
        XCTAssertNil(gift(s, at(2028, 2, 10)), "blocked before the update")
        s.setBirthday(nil)
        XCTAssertEqual(s.state.birthdayChangedAfterGiftYear, 2028, "clearing lifts nothing")
        s.setBirthday(Birthday(month: 2, day: 1))
        s.setBirthday(february10)
        XCTAssertEqual(s.state.birthdayChangedAfterGiftYear, 2028)
        XCTAssertNil(s.state.lastBirthdayGiftDate, "the gift's date stays unknown")
        XCTAssertNil(gift(s, at(2028, 2, 10)), "no second egg five weeks after the first")
        XCTAssertEqual(gift(s, at(2029, 2, 10)), 2029, "next year's still comes")
        let kept = try JSONDecoder().decode(CompanionState.self, from: JSONEncoder().encode(s.state))
        XCTAssertEqual(kept.birthdayChangedAfterGiftYear, 2028, "kept by the save")

        // No date lifts it, typed straight or after clearing, the gift's real date included.
        for date in [february10, december30, june1] {
            for clearsFirst in [true, false] {
                let t = try oldSave()
                if clearsFirst { t.setBirthday(nil) }
                t.setBirthday(date)
                XCTAssertEqual(t.state.birthdayChangedAfterGiftYear, 2028, "\(date), cleared first: \(clearsFirst)")
                XCTAssertNil(gift(t, at(2028, date.month, date.day)), "\(date), cleared first: \(clearsFirst)")
            }
        }

        // Once a gift keeps its date (every claim since #88), typing it again lifts the block, as #83 wants.
        let next = try store {
            $0.birthday = Birthday(month: 7, day: 1)
            $0.lastBirthdayGiftYear = 2029
            $0.lastBirthdayGiftDate = june1
            $0.lastBirthdayGiftClaimedAt = self.at(2029, 6, 2)
            $0.birthdayChangedAfterGiftYear = 2029
        }
        next.setBirthday(nil)
        next.setBirthday(june1)
        XCTAssertNil(next.state.birthdayChangedAfterGiftYear, "back to the gift's date")
    }

    /// Used, it sends off the Pokémon for the Birthday Egg, which hatches a mythical while one is missing.
    private func hatch(seed: UInt64, graduated ids: [Int], also: [DexEntry] = []) async throws -> MonState {
        let s = try store(seed: seed) {
            $0.dex = self.graduated(ids) + also
            $0.active = MonState(baseID: 1, pathIDs: [1], stageIndex: 0, usedAtStage: 0, rarity: .common, totalForms: 1)
            $0.inventory = [ItemKind.birthdayEgg.rawValue: 1]
        }
        XCTAssertTrue(s.useBirthdayEgg())
        XCTAssertEqual(s.eggKind, .birthday)
        XCTAssertNil(s.eggGuarantee, "it doesn't tell what hatches")
        s.setEggUsageForTesting(s.eggHatchThreshold)
        await s.hatchIfNeeded()
        XCTAssertFalse(s.state.eggFromBirthdayEgg, "consumed by the hatch")
        XCTAssertFalse(s.state.pendingShiny)
        return try XCTUnwrap(s.state.active, "seed \(seed)")
    }

    func testTheEggHatchesAMissingMythicalThenALegendaryThenAShiny() async throws {
        var mythicals = Set<Int>()
        for seed: UInt64 in 1...12 { mythicals.insert(try await hatch(seed: seed, graduated: []).baseID) }
        XCTAssertEqual(mythicals, [151, 251], "only mythicals, each as likely")

        for seed: UInt64 in 1...6 {
            let missing = try await hatch(seed: seed, graduated: [151])
            XCTAssertEqual(missing.baseID, 251, "the mythical still missing")
            let legend = try await hatch(seed: seed, graduated: [151, 251])
            XCTAssertEqual(legend.baseID, 144, "every mythical graduated: a legendary")
        }

        var every = Set<Int>()
        for seed: UInt64 in 1...16 {
            let mon = try await hatch(seed: seed, graduated: [151, 251, 144])
            XCTAssertTrue(mon.isShiny, "all graduated: a shiny one")
            XCTAssertTrue([151, 251, 144].contains(mon.baseID))
            every.insert(mon.baseID)
        }
        XCTAssertGreaterThan(every.count, 1)
    }

    /// [Regression] Without the base index the egg keeps its rule: the REST fallback took any legendary it met, one
    /// graduated while another was missing, and never kept the shiny promised once all are graduated.
    func testWithoutTheIndexTheEggKeepsItsRule() async throws {
        func hatch(seed: UInt64, graduated ids: [Int]) async throws -> MonState {
            var st = CompanionState()
            st.installBaselineSet = true
            st.lastDate = "2026-10-26"
            st.dex = graduated(ids)
            st.active = MonState(baseID: 1, pathIDs: [1], stageIndex: 0, usedAtStage: 0, rarity: .common, totalForms: 1)
            st.inventory = [ItemKind.birthdayEgg.rawValue: 1]
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("birthday-rest-\(UUID().uuidString).json")
            try JSONEncoder().encode(st).write(to: url)
            addTeardownBlock { try? FileManager.default.removeItem(at: url) }
            let s = CompanionStore(provider: NoIndexProvider(), clock: { self.now }, fileURL: url, rng: SeededRNG(seed: seed))
            XCTAssertTrue(s.useBirthdayEgg())
            s.setEggUsageForTesting(s.eggHatchThreshold)
            await s.hatchIfNeeded()
            return try XCTUnwrap(s.state.active, "seed \(seed)")
        }
        let mythicalMissing = try await hatch(seed: 1, graduated: SpeciesGoal.mythicals.filter { $0 != 494 })
        XCTAssertEqual(mythicalMissing.baseID, 494, "the mythical still missing")
        // [Regression, review of 2026-11-02] Arceus the only mythical left: the fallback drew 493, which only the Hall of
        // Origin gives (R13); it goes on to the legendary still missing.
        let arceusLeft = try await hatch(seed: 4, graduated: SpeciesGoal.mythicals.filter { $0 != 493 }
                                                    + SpeciesGoal.legendaries.filter { $0 != 150 })
        XCTAssertEqual(arceusLeft.baseID, 150)
        let legendaryMissing = try await hatch(seed: 2, graduated: SpeciesGoal.mythicals + SpeciesGoal.legendaries.filter { $0 != 150 })
        XCTAssertEqual(legendaryMissing.baseID, 150, "then the legendary still missing")
        XCTAssertFalse(legendaryMissing.isShiny)
        let all = try await hatch(seed: 3, graduated: SpeciesGoal.mythicals + SpeciesGoal.legendaries)
        XCTAssertTrue(all.isShiny, "all graduated: a shiny one")
        XCTAssertTrue((SpeciesGoal.mythicals + SpeciesGoal.legendaries).contains(all.baseID))
        XCTAssertTrue(Set(SpeciesGoal.mythicals).isDisjoint(with: SpeciesGoal.legendaries))
        XCTAssertEqual(SpeciesGoal.legendaries.count, 66)
    }

    /// A released mythical is not graduated: it can still come from the egg.
    func testAReleasedMythicalCanStillCome() async throws {
        var released = graduated([151])[0]
        released.releasedAt = now
        for seed: UInt64 in 1...4 {
            let mon = try await hatch(seed: seed, graduated: [251], also: [released])
            XCTAssertEqual(mon.baseID, 151)
        }
        XCTAssertEqual(SpeciesGoal.mythicals.count, 22)
        XCTAssertTrue(Set(SpeciesGoal.mythicals).isDisjoint(with: [144, 150, 249, 250, 384]))
    }
}
