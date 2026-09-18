import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

private struct CardLineProvider: PokeProviding {
    let line = EvoLine(
        baseID: 1,
        tree: EvoNode(speciesID: 1, children: [EvoNode(speciesID: 2, children: [EvoNode(speciesID: 3, children: [])])]),
        rarity: .common,
        names: [1: ["en": "P1"], 2: ["en": "P2"], 3: ["en": "P3"]])
    func line(baseSpeciesID: Int) async throws -> EvoLine { line }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [BaseSpecies(id: 1, captureRate: 255)] }
}

private let cardNow = Date(timeIntervalSince1970: 1_700_000_000)

private func graduate(_ id: String, species: Int, rarity: Rarity = .common, shiny: Bool = false,
                      daysAgo: Double, released: Bool = false) -> DexEntry {
    let date = cardNow.addingTimeInterval(-daysAgo * 86_400)
    return DexEntry(id: id, baseID: species, finalID: species, chainOrder: [species], rarity: rarity,
                    caughtAt: date, isShiny: shiny, names: [species: ["en": "S\(species)"]],
                    releasedAt: released ? date : nil)
}

@MainActor
final class TrainerCardTests: XCTestCase {
    // Immutable and set inline: `setUp`/`tearDown` are nonisolated, so a @MainActor test cannot
    // touch a mutable property from them (Swift 6.0 rejects it, 6.2 lets it through).
    private let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("card-\(UUID().uuidString).json")

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: url)
    }

    private func store(dex: [DexEntry], active: MonState? = nil, extra: String = "",
                       used: Int = 0) throws -> CompanionStore {
        let dexJSON = String(decoding: try JSONEncoder().encode(dex), as: UTF8.self)
        let activeJSON = try active.map { String(decoding: try JSONEncoder().encode($0), as: UTF8.self) } ?? "null"
        let json = #"{"installBaselineSet":true,"usedSinceInstall":\#(used),"lastDate":"d","language":"en","dex":\#(dexJSON),"active":\#(activeJSON)\#(extra)}"#
        try Data(json.utf8).write(to: url)
        return reload()
    }

    private func reload() -> CompanionStore {
        CompanionStore(provider: CardLineProvider(), clock: { cardNow }, fileURL: url, rng: SeededRNG(seed: 7))
    }

    private var eightGraduates: [DexEntry] {
        [graduate("common-old", species: 10, daysAgo: 9),
         graduate("common-new", species: 11, daysAgo: 1),
         graduate("rare", species: 12, rarity: .rare, daysAgo: 5),
         graduate("legend", species: 13, rarity: .legendary, daysAgo: 7),
         graduate("shiny-common", species: 14, shiny: true, daysAgo: 8),
         graduate("uncommon", species: 15, rarity: .uncommon, daysAgo: 3),
         graduate("released-legend", species: 16, rarity: .legendary, daysAgo: 2, released: true),
         graduate("common-mid", species: 17, daysAgo: 4)]
    }

    // MARK: Team

    func testTheAutomaticTeamListsShiniesThenTheRarestGraduates() throws {
        let raised = MonState(baseID: 1, pathIDs: [1], stageIndex: 0, usedAtStage: 0,
                              rarity: .legendary, totalForms: 3, isShiny: true)
        let s = try store(dex: eightGraduates, active: raised)

        XCTAssertFalse(s.isTeamPicked)
        XCTAssertEqual(s.trainerTeam.map(\.id),
                       ["shiny-common", "legend", "rare", "uncommon", "common-new", "common-mid"],
                       "the raised Pokémon and released ones stay out, newest first on ties")
        XCTAssertTrue(s.isTeamFull)
    }

    func testTheFirstEditKeepsTheAutomaticPicksInPlace() throws {
        let s = try store(dex: eightGraduates)
        let rare = try XCTUnwrap(s.trainerTeam.first { $0.id == "rare" })

        s.removeFromTeam(rare)

        XCTAssertTrue(s.isTeamPicked)
        XCTAssertEqual(s.trainerTeam.map(\.id),
                       ["shiny-common", "legend", "uncommon", "common-new", "common-mid"])
    }

    func testAddingReplacingAndMovingMembers() throws {
        let s = try store(dex: eightGraduates)
        for member in s.trainerTeam { s.removeFromTeam(member) }
        XCTAssertTrue(s.isTeamPicked)
        XCTAssertTrue(s.trainerTeam.isEmpty, "an emptied team does not refill itself")

        let byID = Dictionary(uniqueKeysWithValues: s.teamCandidates.map { ($0.id, $0) })
        for id in ["common-old", "rare", "legend"] { XCTAssertTrue(s.addToTeam(try XCTUnwrap(byID[id]))) }
        XCTAssertFalse(s.addToTeam(try XCTUnwrap(byID["rare"])), "no duplicates")
        XCTAssertNil(byID["released-legend"], "released individuals are not candidates")
        let released = try XCTUnwrap(s.dexEntries.first { $0.id == "released-legend" })
        XCTAssertFalse(s.addToTeam(released))
        XCTAssertFalse(s.isInTeam(released))

        XCTAssertTrue(s.addToTeam(try XCTUnwrap(byID["uncommon"]), slot: 1))
        XCTAssertEqual(s.trainerTeam.map(\.id), ["common-old", "uncommon", "legend"])
        XCTAssertTrue(s.isInTeam(try XCTUnwrap(byID["uncommon"])))
        XCTAssertFalse(s.isInTeam(try XCTUnwrap(byID["rare"])))

        s.moveInTeam(try XCTUnwrap(byID["legend"]), by: -1)
        XCTAssertEqual(s.trainerTeam.map(\.id), ["common-old", "legend", "uncommon"])
        s.moveInTeam(try XCTUnwrap(byID["common-old"]), by: -1)
        s.moveInTeam(try XCTUnwrap(byID["uncommon"]), by: 1)
        XCTAssertEqual(s.trainerTeam.map(\.id), ["common-old", "legend", "uncommon"], "edges do not move")

        for id in ["rare", "common-new", "shiny-common"] { XCTAssertTrue(s.addToTeam(try XCTUnwrap(byID[id]))) }
        XCTAssertTrue(s.isTeamFull)
        XCTAssertFalse(s.addToTeam(try XCTUnwrap(byID["common-mid"])), "six members at most")
        XCTAssertTrue(s.addToTeam(try XCTUnwrap(byID["common-mid"]), slot: 5), "a full team still takes a swap")
        XCTAssertEqual(s.trainerTeam.last?.id, "common-mid")
    }

    func testThePickedTeamIsSavedAndCanGoBackToAutomatic() throws {
        let s = try store(dex: eightGraduates)
        for member in s.trainerTeam { s.removeFromTeam(member) }
        XCTAssertTrue(s.addToTeam(try XCTUnwrap(s.teamCandidates.first { $0.id == "common-old" })))

        var reloaded = reload()
        XCTAssertTrue(reloaded.isTeamPicked)
        XCTAssertEqual(reloaded.trainerTeam.map(\.id), ["common-old"])

        reloaded.setAutomaticTeam(true)
        reloaded = reload()
        XCTAssertFalse(reloaded.isTeamPicked)
        XCTAssertEqual(reloaded.trainerTeam.count, 6)
    }

    func testGoingBackToAutomaticKeepsThePickedTeamAside() throws {
        let s = try store(dex: eightGraduates)
        for member in s.trainerTeam { s.removeFromTeam(member) }
        for id in ["legend", "rare"] {
            XCTAssertTrue(s.addToTeam(try XCTUnwrap(s.teamCandidates.first { $0.id == id })))
        }

        s.setAutomaticTeam(true)
        XCTAssertEqual(s.trainerTeam.count, 6, "the automatic team is shown again")

        var reloaded = reload()
        reloaded.setAutomaticTeam(false)
        XCTAssertEqual(reloaded.trainerTeam.map(\.id), ["legend", "rare"], "the picks survive the round trip")

        // An emptied team is a choice too, and coming back must not refill it.
        for member in reloaded.trainerTeam { reloaded.removeFromTeam(member) }
        reloaded.setAutomaticTeam(true)
        reloaded.setAutomaticTeam(false)
        XCTAssertTrue(reloaded.trainerTeam.isEmpty)

        reloaded = reload()
        XCTAssertTrue(reloaded.isTeamPicked)
        XCTAssertTrue(reloaded.trainerTeam.isEmpty)
    }

    func testTurningOffTheAutomaticTeamStartsFromWhatIsShown() throws {
        let s = try store(dex: eightGraduates)
        let automatic = s.trainerTeam.map(\.id)

        s.setAutomaticTeam(false)

        XCTAssertTrue(s.isTeamPicked)
        XCTAssertEqual(s.trainerTeam.map(\.id), automatic)
        XCTAssertEqual(reload().trainerTeam.map(\.id), automatic)
    }

    func testTheRaisedPokemonKeepsItsSlotWhenItGraduates() async throws {
        let s = reload()
        await s.hatch(baseID: 1)
        let raised = try XCTUnwrap(s.teamCandidates.first { s.isActiveDexEntry($0) })
        let key = try XCTUnwrap(s.teamKey(for: raised))
        XCTAssertNotEqual(key, raised.id, "the synthesized row id changes as it evolves")
        XCTAssertTrue(s.addToTeam(raised))
        XCTAssertTrue(s.isInTeam(raised))

        for stage in 0..<3 {
            s.applyUsage(PokemonBalance.phaseThreshold(rarity: .common, totalForms: 3, stageIndex: stage))
        }

        XCTAssertFalse(s.hasActive)
        XCTAssertEqual(s.trainerTeam.map(\.id), [key])
        XCTAssertEqual(s.trainerTeam.first?.finalID, 3)
    }

    func testTheTeamBadgeFollowsAGraduationWithoutAReload() async throws {
        // The badge reads a set folded at the save boundary; a graduation joining the automatic
        // team must refresh it, or the log would keep showing yesterday's team.
        let s = try store(dex: Array(eightGraduates.prefix(2)))
        XCTAssertEqual(s.trainerTeam.count, 2)

        await s.hatch(baseID: 1)
        for stage in 0..<3 {
            s.applyUsage(PokemonBalance.phaseThreshold(rarity: .common, totalForms: 3, stageIndex: stage))
        }

        let graduated = try XCTUnwrap(s.dexEntries.first { $0.finalID == 3 })
        XCTAssertTrue(s.isInTeam(graduated), "the fresh graduate joined the automatic team")
        XCTAssertEqual(s.teamKeySet.count, 3)
    }

    func testAReleasedPokemonLeavesTheTeam() throws {
        let raised = MonState(baseID: 1, pathIDs: [1], stageIndex: 0, usedAtStage: 0,
                              rarity: .common, totalForms: 3)
        let s = try store(dex: [graduate("kept", species: 10, daysAgo: 1)], active: raised,
                          used: 5_000_000_000)
        let row = try XCTUnwrap(s.teamCandidates.first { s.isActiveDexEntry($0) })
        XCTAssertTrue(s.addToTeam(row))
        XCTAssertEqual(s.trainerTeam.count, 2)

        XCTAssertTrue(s.buyFreshEgg())

        XCTAssertEqual(s.trainerTeam.map(\.id), ["kept"])
        XCTAssertEqual(s.state.teamEntryIDs, ["kept"])
    }

    func testLoadingDropsUnknownDuplicateAndReleasedTeamIDs() throws {
        let extra = #","teamEntryIDs":["made-up","rare","rare","released-legend","legend","common-old","uncommon","common-new","common-mid"]"#
        let s = try store(dex: eightGraduates, extra: extra)

        XCTAssertEqual(s.state.teamEntryIDs, ["rare", "legend", "common-old", "uncommon", "common-new", "common-mid"])
    }

    func testAnUnreadableTeamFallsBackToAutomatic() throws {
        let s = try store(dex: eightGraduates, extra: #","teamEntryIDs":5,"trainerName":7"#)

        XCTAssertFalse(s.isTeamPicked)
        XCTAssertEqual(s.trainerName, "")
        XCTAssertEqual(s.trainerTeam.count, 6)
    }

    // MARK: Trainer identity

    func testTheTrainerNumberIsAssignedOnceAndKept() throws {
        let s = try store(dex: [])
        XCTAssertNil(s.trainerID)

        s.ensureTrainerID()
        let id = try XCTUnwrap(s.trainerID)
        XCTAssertTrue(TrainerCard.idRange.contains(id))
        s.ensureTrainerID()
        XCTAssertEqual(s.trainerID, id)
        XCTAssertEqual(reload().trainerID, id)
    }

    func testAnOutOfRangeTrainerNumberIsDropped() throws {
        let s = try store(dex: [], extra: #","trainerID":123456789"#)
        XCTAssertNil(s.trainerID)
    }

    func testTheTrainerNameIsTrimmedCappedAndSaved() throws {
        let s = try store(dex: [])
        s.setTrainerName("  Sam  ")
        XCTAssertEqual(s.trainerName, "Sam")
        s.setTrainerName("A name that is far too long")
        XCTAssertEqual(s.trainerName, "A name that is f")
        XCTAssertEqual(reload().trainerName, "A name that is f")

        s.setTrainerName("A name that is far too long")
        XCTAssertEqual(s.trainerName, "A name that is f", "setting the same name again changes nothing")

        let edited = try store(dex: [], extra: #","trainerName":"An edited save with a long name""#)
        XCTAssertEqual(edited.trainerName.count, TrainerCard.nameLimit)
    }

    // MARK: Stats

    func testStatsCountIndividualsAndSpecies() throws {
        let raised = MonState(baseID: 1, pathIDs: [1, 2], stageIndex: 1, usedAtStage: 0,
                              rarity: .rare, totalForms: 3, isShiny: true)
        let s = try store(dex: eightGraduates, active: raised, used: 2_410_000_000)

        let stats = s.trainerCardStats
        XCTAssertEqual(stats.lifetimeTokens, 2_410_000_000)
        XCTAssertEqual(stats.speciesCount, 10, "eight graduate species plus the two reached forms")
        XCTAssertEqual(stats.speciesTotal, 649)
        XCTAssertEqual(stats.shinyCount, 2)
        XCTAssertEqual(stats.graduatedCount, 7)
        XCTAssertEqual(stats.duplicateCount, 0, "every line was raised once")
        XCTAssertEqual(stats.firstCatch, cardNow.addingTimeInterval(-9 * 86_400))
        XCTAssertEqual(stats.rarityCounts, [.common: 4, .uncommon: 1, .rare: 2, .legendary: 1],
                       "the released legendary is gone, so it counts nowhere but the Pokédex")
    }

    func testReleasedIndividualsCountNowhereButThePokedex() throws {
        let shinyThenReleased = graduate("let-go", species: 30, rarity: .legendary, shiny: true,
                                         daysAgo: 1, released: true)
        let s = try store(dex: [graduate("kept", species: 10, daysAgo: 4), shinyThenReleased,
                                graduate("same-line-as-released", species: 30, daysAgo: 2)])

        let stats = s.trainerCardStats
        XCTAssertEqual(stats.shinyCount, 0, "the shiny was let go")
        XCTAssertEqual(stats.duplicateCount, 0, "the released one does not make the line a duplicate")
        XCTAssertEqual(stats.rarityCounts, [.common: 2])
        XCTAssertEqual(stats.firstCatch, cardNow.addingTimeInterval(-4 * 86_400))
        XCTAssertEqual(stats.speciesCount, 2, "the Pokédex keeps the species either way")
    }

    func testDuplicatesCountIndividualsOfALineAlreadyOwned() throws {
        var dex = eightGraduates
        dex.append(graduate("second-legend", species: 13, rarity: .legendary, daysAgo: 1))
        dex.append(graduate("third-legend", species: 13, rarity: .legendary, daysAgo: 0))
        // Raising species 10 again makes the log hold two of that line as well.
        let raised = MonState(baseID: 10, pathIDs: [10], stageIndex: 0, usedAtStage: 0,
                              rarity: .common, totalForms: 1)
        let s = try store(dex: dex, active: raised)

        XCTAssertEqual(s.trainerCardStats.duplicateCount, 3)
        XCTAssertEqual(s.trainerCardStats.speciesCount, 8, "duplicates add nothing to the Pokédex")
    }

    func testSpeciesBeyondTheAnimatedRangeStayOutOfTheCount() throws {
        // Eevee's chain reaches Sylveon (#700), past the range the Pokédex total covers.
        let sylveon = DexEntry(id: "eeveelution", baseID: 133, finalID: 700, chainOrder: [133, 700],
                               rarity: .rare, caughtAt: cardNow, names: nil)
        let s = try store(dex: [sylveon])

        let stats = s.trainerCardStats
        XCTAssertEqual(stats.speciesCount, 1, "Eevee counts, Sylveon is a bonus past the total")
        XCTAssertLessThanOrEqual(stats.speciesCount, stats.speciesTotal)
    }

    func testTheCardFramesThePinnedPokemonAndFallsBackToTheRaisedOne() throws {
        let raised = MonState(baseID: 1, pathIDs: [1, 2], stageIndex: 1, usedAtStage: 0,
                              rarity: .rare, totalForms: 3, isShiny: true)
        let s = try store(dex: eightGraduates, active: raised)

        XCTAssertEqual(s.cardSubject.speciesID, 2, "no pin, so the raised Pokémon is framed")
        XCTAssertTrue(s.cardSubject.isShiny)

        XCTAssertTrue(s.setRepresentativeSpeciesID(13))
        let pinned = s.cardSubject
        XCTAssertEqual(pinned.speciesID, 13)
        XCTAssertFalse(pinned.isShiny, "that species was never owned shiny")
        XCTAssertEqual(pinned.name, "S13")
        XCTAssertEqual(pinned.detail, L(.en).rarityLabel(.legendary),
                       "a pin is a species, so the raised individual's stage and nature are dropped")
    }

    func testAPinnedPokemonKeepsTheCardOffTheEgg() throws {
        let s = try store(dex: eightGraduates)   // no active Pokémon: an egg is incubating
        XCTAssertEqual(s.cardSubject.name, "Token Egg")

        XCTAssertTrue(s.setRepresentativeSpeciesID(14))
        XCTAssertEqual(s.cardSubject.speciesID, 14)
        XCTAssertTrue(s.cardSubject.isShiny, "that species was graduated shiny")
    }

    func testTheCardRowsFollowTheNameAndTokenSettings() throws {
        let s = try store(dex: [], used: 1_500)
        let shown = TrainerCardFront.rows(TrainerCardContent(store: s, showsTokens: true))
        XCTAssertEqual(shown.map(\.label), ["Tokens", "Pokédex", "Shiny", "Graduated", "Duplicates"],
                       "no name row without a name, no first catch before any catch")
        XCTAssertEqual(shown.first { $0.label == "Pokédex" }?.value, "0 / 649")

        s.setTrainerName("Sam")
        let hidden = TrainerCardFront.rows(TrainerCardContent(store: s, showsTokens: false))
        XCTAssertEqual(hidden.map(\.label), ["Name", "Pokédex", "Shiny", "Graduated", "Duplicates"])
        XCTAssertEqual(hidden.first?.value, "Sam")
    }

    // MARK: Save transfer

    func testASaveTransferCarriesTheCard() throws {
        let s = try store(dex: eightGraduates)
        s.ensureTrainerID()
        s.setTrainerName("Sam")
        s.removeFromTeam(try XCTUnwrap(s.trainerTeam.first))

        let data = try SaveTransfer.encode(state: s.state, appVersion: "t", deviceName: "d", now: cardNow)
        let imported = try SaveTransfer.decode(data).state
        let rebased = SaveTransfer.rebasedForThisDevice(imported, current: CompanionState(),
                                                        todayTokensByProvider: [:], todayDate: "d",
                                                        hasUsageData: false)

        XCTAssertEqual(rebased.trainerID, s.trainerID)
        XCTAssertEqual(rebased.trainerName, "Sam")
        XCTAssertEqual(rebased.teamEntryIDs, s.state.teamEntryIDs)
    }

    // MARK: Rendering

    func testTheCardRendersInEveryLanguage() throws {
        let s = try store(dex: eightGraduates)
        s.ensureTrainerID()
        for language in AppLanguage.allCases {
            s.setLanguage(language)
            let l = L(language)
            for text in [l.trainerCardTitle, l.trainerTeamTitle, l.trainerTeamAdd, l.trainerTeamFull,
                         l.trainerCardCopy, l.trainerCardSave, l.trainerCardCopyMenu, l.trainerNamePlaceholder] {
                XCTAssertFalse(text.isEmpty, "\(language)")
            }
            XCTAssertTrue(l.trainerIDLabel("01234").contains("01234"))
            let content = TrainerCardContent(store: s, showsTokens: true)
            let renderer = ImageRenderer(content: TrainerCardExport.sheet(content))
            renderer.scale = 1
            let image = try XCTUnwrap(renderer.cgImage, "\(language)")
            XCTAssertEqual(image.width, Int(TrainerCardStyle.size.width) + 24)
            XCTAssertEqual(image.height, Int(TrainerCardStyle.size.height) * 2 + 36)
        }
    }

    func testThePickedTeamSideRendersEmptySlotsAndTheChip() throws {
        // A line with no stored names falls back to the species number on the slot.
        let nameless = DexEntry(id: "nameless", baseID: 20, finalID: 20, chainOrder: [20],
                                rarity: .rare, caughtAt: cardNow, names: nil)
        let s = try store(dex: eightGraduates + [nameless])
        for member in s.trainerTeam.dropFirst(2) { s.removeFromTeam(member) }
        XCTAssertTrue(s.addToTeam(try XCTUnwrap(s.teamCandidates.first { $0.id == "nameless" })))

        let content = TrainerCardContent(store: s, showsTokens: true)
        XCTAssertTrue(content.teamPicked)
        XCTAssertEqual(content.team.count, 3, "three slots filled, three empty")
        XCTAssertEqual(content.team.last?.name, "#20")

        let renderer = ImageRenderer(content: TrainerCardBack(content: content))
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.cgImage)
        XCTAssertEqual(image.width, Int(TrainerCardStyle.size.width))
        XCTAssertEqual(image.height, Int(TrainerCardStyle.size.height))
    }

    func testAShinyCardIsHoloOnBothSides() throws {
        let plain = try store(dex: eightGraduates)
        let shiny = try store(dex: eightGraduates,
                              active: MonState(baseID: 1, pathIDs: [1], stageIndex: 0, usedAtStage: 0,
                                               rarity: .common, totalForms: 1, isShiny: true))
        XCTAssertTrue(shiny.cardSubject.isShiny)

        func pixels(_ view: some View) throws -> Data {
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1
            let image = try XCTUnwrap(renderer.cgImage)
            return try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        }
        let plainContent = TrainerCardContent(store: plain, showsTokens: true)
        let shinyContent = TrainerCardContent(store: shiny, showsTokens: true)
        XCTAssertNotEqual(try pixels(TrainerCardFront(content: plainContent)),
                          try pixels(TrainerCardFront(content: shinyContent)))
        XCTAssertNotEqual(try pixels(TrainerCardBack(content: plainContent)),
                          try pixels(TrainerCardBack(content: shinyContent)),
                          "the team side carries the holo frame too")
    }

    func testTypeColorsFallBackToOrange() {
        XCTAssertEqual(TrainerCardStyle.accent(forType: nil), .systemOrange)
        XCTAssertEqual(TrainerCardStyle.accent(forType: "shadow"), .systemOrange)
        XCTAssertNotEqual(TrainerCardStyle.accent(forType: "water"), .systemOrange)
    }

    func testOpeningTheRepresentativePickerLeavesTheCard() {
        let nav = PopoverNavigation()
        nav.showingTrainerCard = true
        nav.openRepresentativeDex()
        XCTAssertFalse(nav.showingTrainerCard)
    }
}
