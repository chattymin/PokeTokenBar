import XCTest
@testable import PokeTokenBar

private enum TradeCommitStubError: Error { case unavailable }

private struct TradeCommitOfflineProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw TradeCommitStubError.unavailable }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { throw TradeCommitStubError.unavailable }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { throw TradeCommitStubError.unavailable }
}

@MainActor
final class TradeCommitTests: XCTestCase {
    /// Seeds the store's persisted state the same way `DifficultySaveTests` does — encode a
    /// `CompanionState` to the fixture file before construction — instead of a production-visible
    /// setter that would let any app-target code bypass the backup guarantee this task establishes.
    private func fixture(state: CompanionState = CompanionState()) throws -> (CompanionStore, URL) {
        // Own subdirectory per test so a test that removes the state directory
        // (to simulate a backup write failure) never touches the shared temp root.
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("trade-commit-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("companion-state.json")
        try JSONEncoder().encode(state).write(to: url)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "trade-commit-\(UUID())"))
        let store = CompanionStore(provider: TradeCommitOfflineProvider(), fileURL: url,
                                   dittoDisguiseRollingEnabled: false, defaults: defaults)
        return (store, url)
    }

    func testOverwriteWarningIsNilWhenReceivingDexEntry() throws {
        let (store, _) = try fixture()
        let entry = DexEntry(baseID: 1, finalID: 1, chainOrder: [1], rarity: .common, caughtAt: Date())
        XCTAssertNil(store.tradeOverwriteWarning(forReceiving: .dexEntry(entry)))
    }

    func testOverwriteWarningIsNilWhenIHaveNoActiveMonAndNoEggProgress() throws {
        let (store, _) = try fixture()
        let mon = MonState(baseID: 4, pathIDs: [4], stageIndex: 0, usedAtStage: 0, rarity: .common, totalForms: 1)
        XCTAssertNil(store.tradeOverwriteWarning(forReceiving: .activeMon(mon)))
    }

    func testOverwriteWarningPresentWhenReceivingActiveMonWhileGrowingOne() throws {
        var seed = CompanionState()
        seed.active = MonState(baseID: 1, pathIDs: [1, 2], stageIndex: 0, usedAtStage: 100,
                               rarity: .common, totalForms: 2)
        let (store, _) = try fixture(state: seed)
        let mon = MonState(baseID: 4, pathIDs: [4], stageIndex: 0, usedAtStage: 0, rarity: .common, totalForms: 1)
        XCTAssertNotNil(store.tradeOverwriteWarning(forReceiving: .activeMon(mon)))
    }

    /// R17 — no active mon growing, but a paid egg guarantee (or hatch progress) would be lost.
    func testOverwriteWarningPresentWhenReceivingActiveMonWouldLoseEggGuarantee() throws {
        var seed = CompanionState()
        seed.eggTier = .rare
        let (store, _) = try fixture(state: seed)
        let mon = MonState(baseID: 4, pathIDs: [4], stageIndex: 0, usedAtStage: 0, rarity: .common, totalForms: 1)
        XCTAssertNotNil(store.tradeOverwriteWarning(forReceiving: .activeMon(mon)))
    }

    /// R17 — same, but via egg-hatching progress rather than a purchased guarantee.
    func testOverwriteWarningPresentWhenReceivingActiveMonWouldLoseEggProgress() throws {
        var seed = CompanionState()
        seed.eggUsage = 500
        let (store, _) = try fixture(state: seed)
        let mon = MonState(baseID: 4, pathIDs: [4], stageIndex: 0, usedAtStage: 0, rarity: .common, totalForms: 1)
        XCTAssertNotNil(store.tradeOverwriteWarning(forReceiving: .activeMon(mon)))
    }

    func testApplyTradeCommitCreatesBackupBeforeMutatingState() throws {
        let sent = DexEntry(baseID: 1, finalID: 1, chainOrder: [1], rarity: .common, caughtAt: Date())
        var seed = CompanionState()
        seed.dex = [sent]
        let (store, url) = try fixture(state: seed)
        let received = DexEntry(baseID: 4, finalID: 4, chainOrder: [4], rarity: .common, caughtAt: Date())

        let backupURL = try store.applyTradeCommit(sending: .dexEntry(sent), receiving: .dexEntry(received))

        let dir = url.deletingLastPathComponent()
        let backups = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasPrefix(SaveTransfer.tradeBackupFilePrefix) }
        XCTAssertEqual(backups.count, 1)
        XCTAssertEqual(backupURL.deletingLastPathComponent(), dir)

        // R15 — the backup must be the PRE-trade snapshot, not merely "a backup exists". Decoding it
        // and checking for the sent/received items proves ordering; a post-trade backup would pass
        // the file-exists checks above just as well but recover nothing.
        let backedUpState = try JSONDecoder().decode(CompanionState.self, from: Data(contentsOf: backupURL))
        XCTAssertTrue(backedUpState.dex.contains { $0.id == sent.id })
        XCTAssertFalse(backedUpState.dex.contains { $0.id == received.id })

        XCTAssertFalse(store.state.dex.contains { $0.id == sent.id })
        XCTAssertTrue(store.state.dex.contains { $0.id == received.id })
    }

    func testApplyTradeCommitReplacingActiveMonClearsEggGuarantee() throws {
        var seed = CompanionState()
        seed.active = MonState(baseID: 1, pathIDs: [1], stageIndex: 0, usedAtStage: 0,
                               rarity: .common, totalForms: 1)
        seed.eggTier = .rare
        let (store, _) = try fixture(state: seed)
        let received = MonState(baseID: 4, pathIDs: [4], stageIndex: 0, usedAtStage: 0,
                                rarity: .common, totalForms: 1)
        let sent = DexEntry(baseID: 1, finalID: 1, chainOrder: [1], rarity: .common, caughtAt: Date())

        try store.applyTradeCommit(sending: .dexEntry(sent), receiving: .activeMon(received))

        XCTAssertEqual(store.state.active?.baseID, 4)
        XCTAssertNil(store.state.eggTier)
    }

    /// The give-away direction had no coverage at all — every other test sends a dex entry.
    /// Giving away the active mon must clear it and leave the egg-guarantee fields consistent
    /// (no guarantee/progress left dangling for the next free egg to inherit).
    func testApplyTradeCommitGivingAwayActiveMonClearsActiveAndEggGuarantee() throws {
        var seed = CompanionState()
        seed.active = MonState(baseID: 1, pathIDs: [1], stageIndex: 0, usedAtStage: 0,
                               rarity: .common, totalForms: 1)
        seed.eggTier = .rare
        seed.pendingHatchID = 7
        seed.eggUsage = 250
        let (store, _) = try fixture(state: seed)
        let sent = MonState(baseID: 1, pathIDs: [1], stageIndex: 0, usedAtStage: 0,
                            rarity: .common, totalForms: 1)
        let received = DexEntry(baseID: 4, finalID: 4, chainOrder: [4], rarity: .common, caughtAt: Date())

        try store.applyTradeCommit(sending: .activeMon(sent), receiving: .dexEntry(received))

        XCTAssertNil(store.state.active)
        XCTAssertNil(store.state.eggTier)
        XCTAssertNil(store.state.pendingHatchID)
        XCTAssertNil(store.state.pendingUnownForm)
        XCTAssertEqual(store.state.eggUsage, 0)
    }

    /// R14 — receiving an active mon while none is currently growing must flip the presentation
    /// state to `.idle`; leaving it at `.egg` (its pre-trade value) would show an empty egg slot
    /// even though `state.active` now holds a Pokémon.
    func testApplyTradeCommitReceivingActiveMonUpdatesDisplayStateToIdle() throws {
        let (store, _) = try fixture()
        XCTAssertEqual(store.displayState, .egg)
        let received = MonState(baseID: 4, pathIDs: [4], stageIndex: 0, usedAtStage: 0,
                                rarity: .common, totalForms: 1)
        let sent = DexEntry(baseID: 1, finalID: 1, chainOrder: [1], rarity: .common, caughtAt: Date())

        try store.applyTradeCommit(sending: .dexEntry(sent), receiving: .activeMon(received))

        XCTAssertEqual(store.displayState, .idle)
    }

    /// R14 — the mirror direction: giving away the active mon must flip presentation back to
    /// `.egg`; leaving it at `.idle` would keep showing a Pokémon that no longer exists.
    func testApplyTradeCommitGivingAwayActiveMonUpdatesDisplayStateToEgg() throws {
        var seed = CompanionState()
        seed.active = MonState(baseID: 1, pathIDs: [1], stageIndex: 0, usedAtStage: 0,
                               rarity: .common, totalForms: 1)
        let (store, _) = try fixture(state: seed)
        XCTAssertEqual(store.displayState, .idle)
        let sent = MonState(baseID: 1, pathIDs: [1], stageIndex: 0, usedAtStage: 0,
                            rarity: .common, totalForms: 1)
        let received = DexEntry(baseID: 4, finalID: 4, chainOrder: [4], rarity: .common, caughtAt: Date())

        try store.applyTradeCommit(sending: .activeMon(sent), receiving: .dexEntry(received))

        XCTAssertEqual(store.displayState, .egg)
    }

    func testApplyTradeCommitAbortsWhenBackupCannotBeWritten() throws {
        let sent = DexEntry(baseID: 1, finalID: 1, chainOrder: [1], rarity: .common, caughtAt: Date())
        var seed = CompanionState()
        seed.dex = [sent]
        let (store, url) = try fixture(state: seed)
        let dir = url.deletingLastPathComponent()
        let received = DexEntry(baseID: 4, finalID: 4, chainOrder: [4], rarity: .common, caughtAt: Date())

        // Replace the state directory with a file so any backup write into it fails.
        try FileManager.default.removeItem(at: dir)
        try Data().write(to: dir)
        defer { try? FileManager.default.removeItem(at: dir) }

        XCTAssertThrowsError(try store.applyTradeCommit(sending: .dexEntry(sent), receiving: .dexEntry(received))) { error in
            XCTAssertEqual(error as? SaveTransferError, .backupFailed)
        }
        XCTAssertTrue(store.state.dex.contains { $0.id == sent.id })
        XCTAssertFalse(store.state.dex.contains { $0.id == received.id })
    }

    // MARK: I5 — if the same DexEntry.id ends up twice in the dex, a single exchange erases both.

    /// Because the spec allows a one-sided commit (covered by the backup), the same id can
    /// legitimately exist on two devices, and receiving it back creates a duplicate id in my dex —
    /// afterward removeAll { $0.id == } erases both.
    func testReceivingAnEntryWhoseIdIsAlreadyInTheDexReissuesTheId() throws {
        var seed = CompanionState()
        let mine = DexEntry(baseID: 1, finalID: 1, chainOrder: [1], rarity: .common, caughtAt: Date())
        let sent = DexEntry(baseID: 7, finalID: 7, chainOrder: [7], rarity: .common, caughtAt: Date())
        seed.dex = [mine, sent]
        let (store, _) = try fixture(state: seed)

        var returning = DexEntry(baseID: 4, finalID: 4, chainOrder: [4], rarity: .common, caughtAt: Date())
        returning.id = mine.id   // simulates the same item, still held on the peer's device, coming back
        try store.applyTradeCommit(sending: .dexEntry(sent), receiving: .dexEntry(returning))

        XCTAssertEqual(store.state.dex.count, 2)
        XCTAssertEqual(Set(store.state.dex.map(\.id)).count, 2, "a received entry must not share an id with an owned one")
    }

    func testALaterTradeRemovesOnlyTheEntryItSent() throws {
        var seed = CompanionState()
        let mine = DexEntry(baseID: 1, finalID: 1, chainOrder: [1], rarity: .common, caughtAt: Date())
        let sent = DexEntry(baseID: 7, finalID: 7, chainOrder: [7], rarity: .common, caughtAt: Date())
        seed.dex = [mine, sent]
        let (store, _) = try fixture(state: seed)

        var returning = DexEntry(baseID: 4, finalID: 4, chainOrder: [4], rarity: .common, caughtAt: Date())
        returning.id = mine.id
        try store.applyTradeCommit(sending: .dexEntry(sent), receiving: .dexEntry(returning))

        let laterOffer = try XCTUnwrap(store.state.dex.first { $0.id == mine.id })
        let other = DexEntry(baseID: 10, finalID: 10, chainOrder: [10], rarity: .common, caughtAt: Date())
        try store.applyTradeCommit(sending: .dexEntry(laterOffer), receiving: .dexEntry(other))

        XCTAssertEqual(store.state.dex.count, 2, "one trade must not erase two owned Pokémon")
        XCTAssertEqual(store.state.dex.filter { $0.baseID == 4 }.count, 1, "the earlier received entry must survive")
    }
}
