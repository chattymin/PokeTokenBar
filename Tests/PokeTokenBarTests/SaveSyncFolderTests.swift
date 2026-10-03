import XCTest
@testable import PokeTokenBar

/// Sync-folder handoff (#257): what counts as "another Mac's save I haven't taken in", and when a
/// write must ask first. Two `SaveSyncFolder`s on separate defaults suites stand in for two Macs
/// sharing one synced folder.
@MainActor
final class SaveSyncFolderTests: XCTestCase {
    // Touched from the nonisolated setUp/tearDown; XCTest runs those and the test serially.
    nonisolated(unsafe) private var folder: URL!
    nonisolated(unsafe) private var suites: [String] = []

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ptb-sync-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
        for suite in suites { UserDefaults().removePersistentDomain(forName: suite) }
        suites = []
    }

    private func mac(sharing folder: URL? = nil) -> SaveSyncFolder {
        let suite = "SaveSyncFolderTests.\(UUID().uuidString)"
        suites.append(suite)
        let sync = SaveSyncFolder(defaults: UserDefaults(suiteName: suite)!)
        sync.folderURL = folder ?? self.folder
        return sync
    }

    private func save(from sync: SaveSyncFolder, dex: Int = 0, at date: Date, name: String = "Mac") throws -> Data {
        var state = CompanionState()
        state.usedSinceInstall = 1_000 + dex
        return try SaveTransfer.encode(state: state, appVersion: "test", deviceName: name, now: date,
                                       deviceID: sync.deviceID)
    }

    func testNoFolderOrNoFileOffersNothing() throws {
        let unset = mac()
        unset.folderURL = nil
        XCTAssertNil(unset.fileURL)
        XCTAssertNil(try unset.read())
        XCTAssertNil(mac().pendingHandoff(), "an empty folder offers nothing")
    }

    func testDeviceIDIsStablePerInstallAndDistinctAcrossMacs() {
        let a = mac(), b = mac()
        XCTAssertEqual(a.deviceID, a.deviceID)
        XCTAssertNotEqual(a.deviceID, b.deviceID)
    }

    /// The core handoff: A writes → B is offered A's save; A itself is not.
    func testSaveFromAnotherMacIsOfferedButOwnSaveIsNot() throws {
        let a = mac(), b = mac()
        let written = try a.write(save(from: a, at: Date(timeIntervalSince1970: 1_800_000_000)))
        XCTAssertEqual(written.sourceDeviceID, a.deviceID)

        XCTAssertNil(a.pendingHandoff(), "the Mac that wrote it is not offered its own save")
        let offered = try XCTUnwrap(b.pendingHandoff())
        XCTAssertEqual(offered.sourceDeviceID, a.deviceID)
        XCTAssertEqual(offered.state.usedSinceInstall, 1_000)
    }

    /// Loaded or declined → not offered again on the next wake; a later write from A is offered again.
    func testMarkSeenStopsRepeatOffersUntilTheFileChanges() throws {
        let a = mac(), b = mac()
        try a.write(save(from: a, at: Date(timeIntervalSince1970: 1_800_000_000)))
        b.markSeen(try XCTUnwrap(b.pendingHandoff()))
        XCTAssertNil(b.pendingHandoff())

        try a.write(save(from: a, dex: 5, at: Date(timeIntervalSince1970: 1_800_000_600)))
        XCTAssertEqual(b.pendingHandoff()?.state.usedSinceInstall, 1_005)
    }

    /// Identity, not "newer than": A's clock runs behind B's, so A's second save carries an *older*
    /// timestamp than what B last saw. It must still be offered.
    func testSaveWithEarlierTimestampFromSkewedClockIsStillOffered() throws {
        let a = mac(), b = mac()
        try a.write(save(from: a, at: Date(timeIntervalSince1970: 1_800_000_600)))
        b.markSeen(try XCTUnwrap(b.pendingHandoff()))
        try a.write(save(from: a, dex: 1, at: Date(timeIntervalSince1970: 1_800_000_000)))
        XCTAssertNotNil(b.pendingHandoff())
    }

    /// Overwrite guard: B writing over A's unseen save asks first; after B has taken it in, or over
    /// B's own save, it does not.
    func testOverwriteConfirmationOnlyForAnotherMacsUnseenSave() throws {
        let a = mac(), b = mac()
        XCTAssertFalse(b.needsOverwriteConfirmation(existing: nil), "empty folder")
        try a.write(save(from: a, at: Date(timeIntervalSince1970: 1_800_000_000)))
        XCTAssertTrue(b.needsOverwriteConfirmation(existing: try b.read()))
        XCTAssertFalse(a.needsOverwriteConfirmation(existing: try a.read()), "own save")

        b.markSeen(try XCTUnwrap(try b.read()))
        XCTAssertFalse(b.needsOverwriteConfirmation(existing: try b.read()), "already taken in")

        try b.write(save(from: b, at: Date(timeIntervalSince1970: 1_800_000_900)))
        XCTAssertTrue(a.needsOverwriteConfirmation(existing: try a.read()), "now B's save is new to A")
    }

    /// A manual export (no device id) dropped into the folder is treated as another Mac's save.
    func testFileWithoutDeviceIDCountsAsAnotherMacs() throws {
        let b = mac()
        let legacy = try SaveTransfer.encode(state: CompanionState(), appVersion: "2.5.3",
                                             deviceName: "Old Mac", now: Date(timeIntervalSince1970: 1_800_000_000))
        try legacy.write(to: try XCTUnwrap(b.fileURL))
        let offered = try XCTUnwrap(b.pendingHandoff())
        XCTAssertNil(offered.sourceDeviceID)
    }

    /// Changing the folder forgets what was seen: a save waiting in the new folder is offered once.
    func testChangingFolderResetsSeenState() throws {
        let a = mac(), b = mac()
        try a.write(save(from: a, at: Date(timeIntervalSince1970: 1_800_000_000)))
        b.markSeen(try XCTUnwrap(b.pendingHandoff()))
        b.folderURL = folder
        XCTAssertNotNil(b.pendingHandoff())
    }

    /// A broken file throws from `read()` (the Settings button reports it) but offers nothing at wake.
    func testUnreadableFileThrowsOnReadButOffersNothing() throws {
        let b = mac()
        try Data("{\"not\":\"a save\"}".utf8).write(to: try XCTUnwrap(b.fileURL))
        XCTAssertThrowsError(try b.read()) { XCTAssertEqual($0 as? SaveTransferError, .notASaveFile) }
        XCTAssertNil(b.pendingHandoff())
    }

    /// `write` refuses data that is not a save, so the folder never holds something `read` rejects.
    func testWriteRejectsNonSaveDataAndLeavesFolderUntouched() throws {
        let a = mac()
        XCTAssertThrowsError(try a.write(Data("[]".utf8)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(a.fileURL).path))
    }

    func testWriteWithoutFolderThrows() throws {
        let a = mac()
        let data = try save(from: a, at: Date())
        a.folderURL = nil
        XCTAssertThrowsError(try a.write(data))
    }

    /// iCloud "Optimize Mac Storage" placeholder: no real file yet → nothing to offer, no throw.
    func testICloudPlaceholderReadsAsEmpty() throws {
        let b = mac()
        try Data().write(to: folder.appendingPathComponent(".\(SaveSyncFolder.fileName).icloud"))
        XCTAssertNil(try b.read())
    }

    /// End to end through two `CompanionStore`s: A's progress, exported with its device id and
    /// written to the folder, is offered to B and lands in B's state via the normal import path.
    func testCompanionProgressHandsOverThroughFolder() throws {
        let a = mac(), b = mac()
        let stateDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ptb-sync-state-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: stateDir) }
        let storeA = CompanionStore(fileURL: stateDir.appendingPathComponent("a.json"), defaults: UserDefaults(suiteName: suiteFor())!)
        let storeB = CompanionStore(fileURL: stateDir.appendingPathComponent("b.json"), defaults: UserDefaults(suiteName: suiteFor())!)
        var progressed = CompanionState()
        progressed.usedSinceInstall = 7_654_321
        try storeA.applySave(SaveTransfer.decode(SaveTransfer.encode(
            state: progressed, appVersion: "t", deviceName: "Seed", now: Date())),
            todayTokensByProvider: [:], todayDate: "2026-10-03", hasUsageData: false)

        try a.write(storeA.exportedSaveData(appVersion: "t", deviceName: "Home Mac", deviceID: a.deviceID))
        let offered = try XCTUnwrap(b.pendingHandoff())
        XCTAssertEqual(offered.sourceDevice, "Home Mac")
        try storeB.applySave(offered, todayTokensByProvider: [:], todayDate: "2026-10-03", hasUsageData: false)
        b.markSeen(offered)

        XCTAssertEqual(storeB.state.usedSinceInstall, 7_654_321)
        XCTAssertNil(b.pendingHandoff())
    }

    private func suiteFor() -> String {
        let suite = "SaveSyncFolderTests.store.\(UUID().uuidString)"
        suites.append(suite)
        return suite
    }

    /// The device id round-trips through the envelope; envelopes without it still decode.
    func testEnvelopeDeviceIDRoundTripsAndIsOptional() throws {
        let withID = try SaveTransfer.decode(SaveTransfer.encode(
            state: CompanionState(), appVersion: "t", deviceName: "M", now: Date(), deviceID: "abc"))
        XCTAssertEqual(withID.sourceDeviceID, "abc")
        let without = try SaveTransfer.decode(SaveTransfer.encode(
            state: CompanionState(), appVersion: "t", deviceName: "M", now: Date()))
        XCTAssertNil(without.sourceDeviceID)
    }
}
