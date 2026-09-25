import XCTest
@testable import PokeTokenBar

private enum SnapshotStubError: Error { case unavailable }

private struct OfflineProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw SnapshotStubError.unavailable }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { throw SnapshotStubError.unavailable }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { throw SnapshotStubError.unavailable }
}

private final class MutableClock: @unchecked Sendable {
    var now: Date
    init(_ now: Date) { self.now = now }
}

@MainActor
final class SaveSnapshotTests: XCTestCase {
    private let baseNow = Date(timeIntervalSince1970: 1_700_000_000)

    private func tempURL(_ tag: String) -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ptb-snapshot-\(tag)-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("companion-state.json")
    }

    private func sampleState(tokens: Int, dexCount: Int) -> CompanionState {
        var s = CompanionState()
        s.installBaselineSet = true
        s.usedSinceInstall = tokens
        s.spentTokens = 1_000
        for i in 1...max(0, dexCount) {
            s.dex.append(DexEntry(baseID: i, finalID: i, chainOrder: [i], rarity: .common, caughtAt: baseNow))
        }
        s.active = MonState(baseID: 1, pathIDs: [1], plannedPathIDs: [1], stageIndex: 0, usedAtStage: 500, rarity: .common, totalForms: 1)
        return s
    }

    func testSnapshotCreationAndListing() throws {
        let url = tempURL("create")
        let clock = MutableClock(baseNow)
        var state = sampleState(tokens: 12_500, dexCount: 3)
        try JSONEncoder().encode(state).write(to: url)

        let store = CompanionStore(provider: OfflineProvider(), clock: { clock.now }, fileURL: url)
        XCTAssertEqual(store.availableSnapshots.count, 0)

        let snapshot = try store.createManualSnapshot()
        XCTAssertEqual(snapshot.dexCount, 3)
        XCTAssertEqual(snapshot.lifetimeTokens, 12_500)
        XCTAssertEqual(snapshot.currentSpeciesID, 1)
        XCTAssertFalse(snapshot.currentIsShiny)
        XCTAssertTrue(FileManager.default.fileExists(atPath: snapshot.fileURL.path))

        XCTAssertEqual(store.availableSnapshots.count, 1)
        XCTAssertEqual(store.availableSnapshots.first?.id, snapshot.id)
    }

    func testSnapshotPruningKeepsAtMostTen() throws {
        let url = tempURL("pruning")
        let state = sampleState(tokens: 20_000, dexCount: 2)
        try JSONEncoder().encode(state).write(to: url)

        for i in 1...15 {
            let date = baseNow.addingTimeInterval(Double(i * 3600))
            try SaveSnapshotManager.createSnapshot(state: state, for: url, date: date)
        }

        let snapshots = SaveSnapshotManager.listSnapshots(for: url)
        XCTAssertEqual(snapshots.count, 10, "Should keep at most 10 snapshots")

        // Newest snapshot should be from the 15th iteration
        let newestDate = baseNow.addingTimeInterval(Double(15 * 3600))
        let oldestKeptDate = baseNow.addingTimeInterval(Double(6 * 3600))
        XCTAssertEqual(snapshots.first?.date, newestDate)
        XCTAssertEqual(snapshots.last?.date, oldestKeptDate)
    }

    func testAutoSnapshotIntervalGuard() throws {
        let url = tempURL("autointerval")
        let clock = MutableClock(baseNow)
        let state = sampleState(tokens: 5_000, dexCount: 1)
        try JSONEncoder().encode(state).write(to: url)

        let store = CompanionStore(provider: OfflineProvider(), clock: { clock.now }, fileURL: url)
        try store.createManualSnapshot()
        XCTAssertEqual(store.availableSnapshots.count, 1)

        // 1 hour later: should not snapshot
        clock.now = baseNow.addingTimeInterval(3600)
        store.autoSnapshotIfNeeded()
        XCTAssertEqual(store.availableSnapshots.count, 1)

        // 13 hours later: should snapshot
        clock.now = baseNow.addingTimeInterval(13 * 3600)
        store.autoSnapshotIfNeeded()
        XCTAssertEqual(store.availableSnapshots.count, 2)
    }

    func testAutoCorruptionRecoveryFromLatestSnapshot() throws {
        let url = tempURL("recovery")
        let clock = MutableClock(baseNow)
        let state = sampleState(tokens: 77_777, dexCount: 5)
        try JSONEncoder().encode(state).write(to: url)

        let store = CompanionStore(provider: OfflineProvider(), clock: { clock.now }, fileURL: url)
        try store.createManualSnapshot()
        XCTAssertEqual(store.availableSnapshots.count, 1)

        // Corrupt main state file
        let garbage = "{ corrupted state json missing brackets..."
        try Data(garbage.utf8).write(to: url)

        // Recreate store at the same URL
        let recoveredStore = CompanionStore(provider: OfflineProvider(), clock: { clock.now }, fileURL: url)

        // Verify state was automatically recovered from the snapshot
        XCTAssertEqual(recoveredStore.state.usedSinceInstall, 77_777)
        XCTAssertEqual(recoveredStore.state.dex.count, 5)
        XCTAssertEqual(recoveredStore.state.active?.baseID, 1)

        // Verify .corrupt backup file was created
        let corruptBackup = url.appendingPathExtension("corrupt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: corruptBackup.path))
        XCTAssertEqual(try String(contentsOf: corruptBackup, encoding: .utf8), garbage)
    }

    func testRestoreSnapshotRollsBackProgressAndPreservesCurrentAsSnapshot() throws {
        let url = tempURL("restore")
        let clock = MutableClock(baseNow)

        // Snapshot 1 (earlier state)
        let state1 = sampleState(tokens: 10_000, dexCount: 1)
        try JSONEncoder().encode(state1).write(to: url)
        let store = CompanionStore(provider: OfflineProvider(), clock: { clock.now }, fileURL: url)
        let snapshot1 = try store.createManualSnapshot()

        // Advance to Snapshot 2 (later state)
        clock.now = baseNow.addingTimeInterval(3600)
        let state2 = sampleState(tokens: 90_000, dexCount: 4)
        try JSONEncoder().encode(state2).write(to: url)
        let store2 = CompanionStore(provider: OfflineProvider(), clock: { clock.now }, fileURL: url)
        XCTAssertEqual(store2.state.usedSinceInstall, 90_000)
        XCTAssertEqual(store2.state.dex.count, 4)

        // Restore Snapshot 1
        clock.now = baseNow.addingTimeInterval(7200)
        try store2.restoreSnapshot(snapshot1)

        // Verify progress is rolled back to snapshot 1
        XCTAssertEqual(store2.state.usedSinceInstall, 10_000)
        XCTAssertEqual(store2.state.dex.count, 1)

        // Verify snapshot of pre-restore state (state 2) was saved
        let snapshots = store2.availableSnapshots
        XCTAssertTrue(snapshots.contains { $0.lifetimeTokens == 90_000 && $0.dexCount == 4 })
    }

    func testRestoreOldestSnapshotAtRetentionLimit() throws {
        let url = tempURL("restore-oldest-at-limit")
        let clock = MutableClock(baseNow)

        // Fill the retention limit exactly; the oldest entry carries distinct progress.
        for i in 0..<SaveSnapshotManager.maxSnapshotsToKeep {
            let state = sampleState(tokens: 10_000 + i * 1_000, dexCount: i + 1)
            try SaveSnapshotManager.createSnapshot(state: state, for: url, date: baseNow.addingTimeInterval(Double(i * 3600)))
        }

        let current = sampleState(tokens: 99_000, dexCount: 12)
        try JSONEncoder().encode(current).write(to: url)
        clock.now = baseNow.addingTimeInterval(Double(SaveSnapshotManager.maxSnapshotsToKeep * 3600))
        let store = CompanionStore(provider: OfflineProvider(), clock: { clock.now }, fileURL: url)
        XCTAssertEqual(store.availableSnapshots.count, SaveSnapshotManager.maxSnapshotsToKeep)
        let oldest = try XCTUnwrap(store.availableSnapshots.last)
        XCTAssertEqual(oldest.lifetimeTokens, 10_000)

        // The pre-restore safety snapshot is the 11th file and prunes the selected one.
        try store.restoreSnapshot(oldest)

        XCTAssertEqual(store.state.usedSinceInstall, 10_000)
        XCTAssertEqual(store.state.dex.count, 1)
        XCTAssertEqual(store.availableSnapshots.count, SaveSnapshotManager.maxSnapshotsToKeep)
        XCTAssertTrue(store.availableSnapshots.contains { $0.lifetimeTokens == 99_000 && $0.dexCount == 12 })
    }

    func testRestoreUnreadableSnapshotLeavesStateAndSnapshotsUntouched() throws {
        let url = tempURL("restore-unreadable")
        let clock = MutableClock(baseNow)

        for i in 0..<SaveSnapshotManager.maxSnapshotsToKeep {
            let state = sampleState(tokens: 10_000 + i * 1_000, dexCount: i + 1)
            try SaveSnapshotManager.createSnapshot(state: state, for: url, date: baseNow.addingTimeInterval(Double(i * 3600)))
        }

        let current = sampleState(tokens: 99_000, dexCount: 12)
        try JSONEncoder().encode(current).write(to: url)
        clock.now = baseNow.addingTimeInterval(Double(SaveSnapshotManager.maxSnapshotsToKeep * 3600))
        let store = CompanionStore(provider: OfflineProvider(), clock: { clock.now }, fileURL: url)
        let selected = try XCTUnwrap(store.availableSnapshots.first)
        let before = store.availableSnapshots.map(\.id)

        // The listed file goes bad before the user confirms the restore.
        try Data("corrupted invalid json".utf8).write(to: selected.fileURL)

        XCTAssertThrowsError(try store.restoreSnapshot(selected))
        XCTAssertEqual(store.state.usedSinceInstall, 99_000)
        XCTAssertEqual(store.state.dex.count, 12)
        // No safety snapshot was written, so nothing valid was pruned for a restore that never happened.
        let after = SaveSnapshotManager.listSnapshots(for: url).map(\.id)
        XCTAssertEqual(Set(after), Set(before).subtracting([selected.id]))
    }

    func testCorruptSnapshotFileIsSkippedGracefully() throws {
        let url = tempURL("corruptsnapshot")
        let dir = SaveSnapshotManager.snapshotsDirectory(for: url)
        let badURL = dir.appendingPathComponent("companion-snapshot-2026-09-18-120000.json")
        try Data("corrupted invalid json".utf8).write(to: badURL)

        let snapshots = SaveSnapshotManager.listSnapshots(for: url)
        XCTAssertEqual(snapshots.count, 0, "Corrupt snapshot files should be ignored without failing")
    }
}
