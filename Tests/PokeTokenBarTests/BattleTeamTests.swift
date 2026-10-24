import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

private let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)
private let singleStage = EvoLine(baseID: 20, tree: EvoNode(speciesID: 20, children: []), rarity: .common,
                                  names: [20: ["en": "P20"]])

private func dexEntry(_ instanceID: String, speciesID: Int = 25, level: Int = 30) -> DexEntry {
    var profile = PokemonProfile.generate(seed: PokemonProfileMigration.seed(instanceID), instanceID: instanceID)
    profile.level = level
    return DexEntry(id: instanceID, baseID: speciesID, finalID: speciesID, chainOrder: [speciesID], rarity: .common,
                    caughtAt: fixedNow, profile: profile, names: [speciesID: ["en": "Mon \(instanceID)"]])
}

@MainActor
final class BattleTeamTests: XCTestCase {
    private func stateFile(_ state: CompanionState) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("battle-team-\(UUID().uuidString).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        try JSONEncoder().encode(state).write(to: url)
        return url
    }

    private func store(dex: [DexEntry], team: [String] = []) throws -> CompanionStore {
        var state = CompanionState()
        state.language = .en
        state.dex = dex
        state.battleTeam = team
        return CompanionStore(provider: StubProvider(value: singleStage), clock: { fixedNow },
                              fileURL: try stateFile(state), rng: SeededRNG(seed: 7))
    }

    func testTogglingKeepsPickOrderAndStopsAtSix() throws {
        let entries = (1...7).map { dexEntry("m\($0)") }
        let s = try store(dex: entries)
        for entry in entries.prefix(6) { XCTAssertTrue(s.toggleBattleTeamMember(entry)) }
        XCTAssertTrue(s.isBattleTeamFull)
        XCTAssertFalse(s.toggleBattleTeamMember(entries[6]), "a seventh member must be refused")
        XCTAssertEqual(s.battleTeamEntries.map(\.id), ["m1", "m2", "m3", "m4", "m5", "m6"])

        XCTAssertTrue(s.toggleBattleTeamMember(entries[2]), "removing works on a full team")
        XCTAssertEqual(s.battleTeamEntries.map(\.id), ["m1", "m2", "m4", "m5", "m6"])
        XCTAssertNil(s.battleTeamSlot(entries[2]))
        XCTAssertEqual(s.battleTeamSlot(entries[3]), 2)
    }

    func testEntryWithoutProfileCannotJoin() throws {
        var legacy = dexEntry("legacy")
        legacy.profile = nil
        let s = try store(dex: [dexEntry("m1")])
        XCTAssertFalse(s.toggleBattleTeamMember(legacy))
        XCTAssertTrue(s.state.battleTeam.isEmpty)
    }

    func testMakeLeadMovesMemberToFrontAndLeadIsNoOp() throws {
        let entries = ["a", "b", "c"].map { dexEntry($0) }
        let s = try store(dex: entries, team: ["a", "b", "c"])
        s.makeBattleLead(entries[2])
        XCTAssertEqual(s.state.battleTeam, ["c", "a", "b"])
        s.makeBattleLead(entries[2])
        XCTAssertEqual(s.state.battleTeam, ["c", "a", "b"])
        s.makeBattleLead(dexEntry("not-in-team"))
        XCTAssertEqual(s.state.battleTeam, ["c", "a", "b"])
    }

    func testTeamPersistsAcrossRelaunch() throws {
        let entries = ["a", "b"].map { dexEntry($0) }
        var state = CompanionState()
        state.dex = entries
        let url = try stateFile(state)
        let s = CompanionStore(provider: StubProvider(value: singleStage), clock: { fixedNow },
                               fileURL: url, rng: SeededRNG(seed: 7))
        s.toggleBattleTeamMember(entries[1])
        s.toggleBattleTeamMember(entries[0])
        let reopened = CompanionStore(provider: StubProvider(value: singleStage), clock: { fixedNow },
                                      fileURL: url, rng: SeededRNG(seed: 7))
        XCTAssertEqual(reopened.battleTeamEntries.map(\.id), ["b", "a"])
    }

    /// The team stores instance IDs, so the Pokémon being raised stays in its slot after graduating.
    func testRaisedMemberKeepsItsSlotAfterGraduation() async throws {
        let s = try store(dex: [dexEntry("a")])
        await s.hatch(baseID: 20)
        let raised = try XCTUnwrap(s.battleCandidates.first { s.isActiveDexEntry($0) })
        s.toggleBattleTeamMember(raised)
        s.toggleBattleTeamMember(dexEntry("a"))
        let raisedID = try XCTUnwrap(raised.profile?.instanceID)

        s.applyUsage(PokemonBalance.phaseThreshold(rarity: .common, totalForms: 1, stageIndex: 0))

        XCTAssertEqual(s.state.dex.count, 2, "the raised Pokémon graduated")
        XCTAssertEqual(s.state.battleTeam, [raisedID, "a"])
        XCTAssertEqual(s.battleTeamEntries.map { $0.profile?.instanceID }, [raisedID, "a"])
        XCTAssertFalse(s.battleTeamEntries.contains { s.isActiveDexEntry($0) })
    }

    func testLoadDropsUnknownDuplicateAndOverflowingMembers() throws {
        let entries = (1...7).map { dexEntry("m\($0)") }
        let s = try store(dex: entries, team: ["ghost", "m1", "m1", "m2", "m3", "m4", "m5", "m6", "m7"])
        XCTAssertEqual(s.state.battleTeam, ["m1", "m2", "m3", "m4", "m5", "m6"])
    }

    func testImportedSaveIsReconciledToOwnedIndividuals() {
        var state = CompanionState()
        state.dex = [dexEntry("m1")]
        state.battleTeam = ["m1", "from-other-save"]
        XCTAssertEqual(SaveTransfer.sanitized(state).battleTeam, ["m1"])
    }

    func testOldAndCorruptSavesDecodeWithEmptyTeam() throws {
        let old = try JSONDecoder().decode(CompanionState.self, from: Data(#"{"inventory":{"mint":1}}"#.utf8))
        XCTAssertEqual(old.battleTeam, [])
        let corrupt = try JSONDecoder().decode(CompanionState.self,
                                               from: Data(#"{"battleTeam":5,"inventory":{"mint":1}}"#.utf8))
        XCTAssertEqual(corrupt.battleTeam, [])
        XCTAssertEqual(corrupt.inventory["mint"], 1, "a bad team must not cost the rest of the save")
    }

    func testTeamCountCopyKeepsCountInEveryLanguage() {
        for language in AppLanguage.allCases {
            XCTAssertTrue(L(language).battleTeamCount(4).contains("4/6"), language.rawValue)
        }
    }

    func testBattleTabKeepsFixedPopoverHeight() throws {
        let entries = (1...40).map { dexEntry("m\($0)", level: $0 + 5) }
        let s = try store(dex: entries, team: ["m3", "m1"])
        let host = NSHostingController(rootView: BattleView(store: s)
            .frame(width: PopoverMetrics.contentWidth)
            .environment(\.locale, s.language.displayLocale))
        let size = host.sizeThatFits(in: CGSize(width: PopoverMetrics.contentWidth, height: 800))
        XCTAssertEqual(size.height, 520, accuracy: 0.5)
    }
}
