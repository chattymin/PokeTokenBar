import XCTest
@testable import PokeTokenBar

private let mirrorNow = Date(timeIntervalSince1970: 1_700_000_000)

private enum MirrorStubError: Error { case unavailable }

/// 진화 라인은 이 테스트와 무관하다 — 전부 실패시켜 네트워크 없는 경로로 고정한다.
private struct MirrorOfflineProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw MirrorStubError.unavailable }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { throw MirrorStubError.unavailable }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { throw MirrorStubError.unavailable }
}

@MainActor
final class ICloudSaveMirrorTests: XCTestCase {

    private var dir: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ptb-icloud-\(UUID().uuidString)", isDirectory: true)
        suiteName = "ptb.icloud.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func makeMirror(enabled: Bool = true) -> ICloudSaveMirror {
        let mirror = ICloudSaveMirror(directory: dir, defaults: defaults)
        mirror.isEnabled = enabled
        return mirror
    }

    private func mirror(_ m: ICloudSaveMirror, _ state: CompanionState, at now: Date) -> Bool {
        m.mirror(state: state, appVersion: "9.9.9", deviceName: "Test Mac", now: now)
    }

    private func state(dexCount: Int = 0, tokens: Int = 0) -> CompanionState {
        var s = CompanionState()
        s.usedSinceInstall = tokens
        s.dex = (0..<dexCount).map { i in
            DexEntry(baseID: i + 1, finalID: i + 1, chainOrder: [i + 1],
                     rarity: .common, caughtAt: mirrorNow, isShiny: false, nature: .hardy,
                     names: [:])
        }
        return s
    }

    // MARK: 쓰기 게이트

    func testFirstMirrorWritesTheEnvelope() throws {
        let m = makeMirror()
        XCTAssertTrue(mirror(m, state(dexCount: 2, tokens: 500), at: mirrorNow))

        let url = try XCTUnwrap(m.ownFileURL)
        let envelope = try SaveTransfer.decode(try Data(contentsOf: url))
        XCTAssertEqual(envelope.sourceDevice, "Test Mac")
        XCTAssertEqual(envelope.appVersion, "9.9.9")
        XCTAssertEqual(envelope.state.dex.count, 2)
        XCTAssertEqual(envelope.state.usedSinceInstall, 500)
    }

    /// 내용 게이트. 120초 하트비트가 상태를 안 바꾼 채 계속 부르는 흔한 경로 — 여기서 안 걸러내면
    /// 사용량이 없어도 하루 수백 번 업로드된다.
    func testUnchangedStateIsNotRewrittenEvenAfterTheInterval() {
        let m = makeMirror()
        let s = state(dexCount: 1, tokens: 10)
        XCTAssertTrue(mirror(m, s, at: mirrorNow))
        let later = mirrorNow.addingTimeInterval(ICloudSaveMirror.minimumWriteInterval + 60)
        XCTAssertFalse(mirror(m, s, at: later), "상태가 그대로면 간격이 지나도 다시 쓰지 않는다")
    }

    /// 간격 게이트의 **트리거 브랜치** — 상태가 실제로 바뀌었는데도 창 안이면 안 쓴다.
    /// (내용 게이트만 있으면 이 케이스가 통과해 버려 상한이 사라진다.)
    func testChangedStateInsideTheIntervalIsHeld() {
        let m = makeMirror()
        XCTAssertTrue(mirror(m, state(tokens: 10), at: mirrorNow))
        let inside = mirrorNow.addingTimeInterval(ICloudSaveMirror.minimumWriteInterval - 1)
        XCTAssertFalse(mirror(m, state(tokens: 999), at: inside), "창 안이면 변경돼도 보류한다")
    }

    /// 그리고 창이 끝나면 그 변경이 실제로 올라간다 — 보류가 유실이 되지 않는지.
    func testChangedStateAfterTheIntervalIsWritten() throws {
        let m = makeMirror()
        XCTAssertTrue(mirror(m, state(tokens: 10), at: mirrorNow))
        let after = mirrorNow.addingTimeInterval(ICloudSaveMirror.minimumWriteInterval)
        XCTAssertTrue(mirror(m, state(tokens: 999), at: after))

        let url = try XCTUnwrap(m.ownFileURL)
        let envelope = try SaveTransfer.decode(try Data(contentsOf: url))
        XCTAssertEqual(envelope.state.usedSinceInstall, 999)
    }

    func testDisabledMirrorNeverWrites() {
        let m = makeMirror(enabled: false)
        XCTAssertFalse(mirror(m, state(tokens: 10), at: mirrorNow))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path),
                       "꺼져 있으면 iCloud Drive 에 폴더조차 만들지 않는다")
    }

    /// iCloud Drive 가 꺼진 Mac(경로 없음) — 켜져 있어도 쓸 곳이 없다.
    func testUnavailableMirrorNeverWrites() {
        let m = ICloudSaveMirror(directory: nil, defaults: defaults)
        m.isEnabled = true
        XCTAssertFalse(m.isAvailable)
        XCTAssertFalse(mirror(m, state(tokens: 10), at: mirrorNow))
    }

    /// 쓰기 실패(iCloud 용량 초과·권한)는 삼키되 **기록을 남기지 않는다** — 남기면 다음 틱이
    /// 성공한 것으로 알고 건너뛰어, 그 변경이 영영 안 올라간다.
    func testWriteFailureIsNotRecordedSoTheNextTickRetries() throws {
        // 부모가 일반 파일이면 그 아래 디렉터리를 만들 수 없다 → createDirectory 가 실패한다.
        let blocker = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ptb-blocker-\(UUID().uuidString)")
        try Data("x".utf8).write(to: blocker)
        defer { try? FileManager.default.removeItem(at: blocker) }

        let m = ICloudSaveMirror(directory: blocker.appendingPathComponent("PokeTokenBar"),
                                 defaults: defaults)
        m.isEnabled = true
        XCTAssertFalse(mirror(m, state(tokens: 1), at: mirrorNow))
        // 같은 시각에 다시 불러도 간격 게이트에 막히지 않는다 = 실패가 기록되지 않았다.
        XCTAssertFalse(mirror(m, state(tokens: 1), at: mirrorNow))
    }

    /// 토글은 재시작을 건너 살아남아야 한다(같은 defaults 로 새 인스턴스).
    func testEnabledFlagPersistsAcrossInstances() {
        makeMirror(enabled: true)
        XCTAssertTrue(ICloudSaveMirror(directory: dir, defaults: defaults).isEnabled)
    }

    /// 기기 식별자는 한 번 만들면 고정 — 갈리면 같은 Mac 의 백업이 매번 새 파일이 되어 쌓인다.
    func testDeviceIDIsStableAcrossInstances() {
        let first = makeMirror().deviceID
        XCTAssertEqual(ICloudSaveMirror(directory: dir, defaults: defaults).deviceID, first)
    }

    // MARK: 정규 인코딩 (내용 게이트의 근거)

    /// 같은 내용이면 바이트가 같아야 한다. 기본 `JSONEncoder` 는 키 순서를 보장하지 않아
    /// `inventory`·`candyGrantTier`·`collectedFinals` 가 같은 상태로도 다른 바이트를 낼 수 있고,
    /// 그러면 내용 게이트가 항상 "바뀜"으로 읽혀 상한이 사라진다.
    func testCanonicalEncodingIsStableForEqualState() throws {
        var s = CompanionState()
        s.inventory = ["rareCandy": 3, "mint": 1, "shinyCharm": 1]
        s.candyGrantTier = ["w3": 2, "w1": 1, "w2": 3]
        s.collectedFinals = ["1:3", "4:6", "7:9"]

        let a = try XCTUnwrap(ICloudSaveMirror.canonicalStateEncoding(s))
        for _ in 0..<20 {
            // 재인코딩마다 Dictionary/Set 순회 순서가 달라질 수 있는 지점을 반복해서 밟는다.
            var copy = CompanionState()
            copy.inventory = s.inventory
            copy.candyGrantTier = s.candyGrantTier
            copy.collectedFinals = s.collectedFinals
            XCTAssertEqual(ICloudSaveMirror.canonicalStateEncoding(copy), a)
        }
    }

    func testCanonicalEncodingDiffersWhenStateDiffers() {
        let a = ICloudSaveMirror.canonicalStateEncoding(state(tokens: 1))
        let b = ICloudSaveMirror.canonicalStateEncoding(state(tokens: 2))
        XCTAssertNotNil(a)
        XCTAssertNotEqual(a, b)
    }

    // MARK: 원격 목록

    private func writeRemote(deviceID: String, deviceName: String, exportedAt: Date,
                             dexCount: Int, tokens: Int, fileName: String? = nil) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try SaveTransfer.encode(state: state(dexCount: dexCount, tokens: tokens),
                                           appVersion: "1.0.0", deviceName: deviceName, now: exportedAt)
        let name = fileName ?? "\(ICloudSaveMirror.fileNamePrefix)\(deviceID)\(ICloudSaveMirror.fileNameSuffix)"
        try data.write(to: dir.appendingPathComponent(name))
    }

    func testRemoteSavesExcludeThisDevicesOwnFile() throws {
        let m = makeMirror()
        XCTAssertTrue(mirror(m, state(dexCount: 5), at: mirrorNow))
        try writeRemote(deviceID: "other", deviceName: "Other Mac", exportedAt: mirrorNow,
                        dexCount: 3, tokens: 42)

        let found = ICloudSaveMirror.remoteSaves(in: dir, excludingDeviceID: m.deviceID)
        XCTAssertEqual(found.map(\.deviceName), ["Other Mac"])
    }

    func testRemoteSavesReportDeviceDateAndSummary() throws {
        try writeRemote(deviceID: "a", deviceName: "Studio", exportedAt: mirrorNow,
                        dexCount: 7, tokens: 12_345)

        let found = ICloudSaveMirror.remoteSaves(in: dir, excludingDeviceID: "self")
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found[0].deviceName, "Studio")
        XCTAssertEqual(found[0].exportedAt.timeIntervalSince1970, mirrorNow.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(found[0].summary.dexCount, 7)
        XCTAssertEqual(found[0].summary.lifetimeTokens, 12_345)
    }

    func testRemoteSavesAreSortedNewestFirst() throws {
        try writeRemote(deviceID: "old", deviceName: "Old", exportedAt: mirrorNow, dexCount: 1, tokens: 1)
        try writeRemote(deviceID: "new", deviceName: "New",
                        exportedAt: mirrorNow.addingTimeInterval(86_400), dexCount: 1, tokens: 1)

        XCTAssertEqual(ICloudSaveMirror.remoteSaves(in: dir, excludingDeviceID: "self").map(\.deviceName),
                       ["New", "Old"])
    }

    /// 남의 JSON 이 그 폴더에 들어와도 목록에 뜨면 안 된다 — `SaveTransfer` 의 봉투 검사가 그 역할이고,
    /// 여기서는 그게 실제로 걸리는지를 본다(관대 디코딩은 아무 JSON 이나 빈 상태로 흡수한다).
    func testForeignJSONInTheFolderIsSkipped() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = "\(ICloudSaveMirror.fileNamePrefix)bogus\(ICloudSaveMirror.fileNameSuffix)"
        try Data(#"{"hello":"world"}"#.utf8).write(to: dir.appendingPathComponent(name))
        try writeRemote(deviceID: "good", deviceName: "Good", exportedAt: mirrorNow, dexCount: 1, tokens: 1)

        XCTAssertEqual(ICloudSaveMirror.remoteSaves(in: dir, excludingDeviceID: "self").map(\.deviceName),
                       ["Good"])
    }

    /// 관계없는 파일명은 애초에 후보가 아니다.
    func testUnrelatedFileNamesAreIgnored() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: dir.appendingPathComponent("notes.txt"))
        XCTAssertTrue(ICloudSaveMirror.remoteSaves(in: dir, excludingDeviceID: "self").isEmpty)
    }

    func testMissingDirectoryYieldsNoRemoteSaves() {
        XCTAssertTrue(ICloudSaveMirror.remoteSaves(in: nil, excludingDeviceID: "self").isEmpty)
        XCTAssertTrue(ICloudSaveMirror.remoteSaves(in: dir, excludingDeviceID: "self").isEmpty)
    }

    // MARK: CompanionStore 배선

    /// 미러가 실제로 `save()` 에 걸려 있는지 — 게이트를 아무리 잘 만들어도 호출이 없으면 무의미하다.
    func testCompanionStoreSaveMirrorsToICloud() throws {
        let stateFile = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ptb-state-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: stateFile) }

        let m = makeMirror()
        let store = CompanionStore(provider: MirrorOfflineProvider(), clock: { mirrorNow },
                                   fileURL: stateFile, iCloudMirror: m)
        store.setLanguage(.en)   // 상태를 바꾸는 가장 짧은 save() 경로

        let url = try XCTUnwrap(m.ownFileURL)
        let envelope = try SaveTransfer.decode(try Data(contentsOf: url))
        XCTAssertEqual(envelope.state.language, .en)
    }

    /// 그리고 꺼져 있으면 `save()` 가 아무것도 내보내지 않는다(옵트인이 실제로 옵트인인지).
    func testCompanionStoreSaveWritesNothingWhenSyncIsOff() {
        let stateFile = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ptb-state-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: stateFile) }

        let m = makeMirror(enabled: false)
        let store = CompanionStore(provider: MirrorOfflineProvider(), clock: { mirrorNow },
                                   fileURL: stateFile, iCloudMirror: m)
        store.setLanguage(.en)

        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: stateFile.path), "로컬 저장은 그대로 동작한다")
    }

    /// evicted 항목은 `.save-x.json.icloud` 플레이스홀더로 열거된다. 이름을 복원하지 않으면
    /// 접두/접미 판정에 걸려 다른 Mac 의 백업이 통째로 안 보인다(조용한 0건).
    func testEvictedPlaceholderNamesResolveToTheRealFile() {
        XCTAssertEqual(ICloudSaveMirror.materializedName(".save-abc.json.icloud"), "save-abc.json")
        XCTAssertEqual(ICloudSaveMirror.materializedName("save-abc.json"), "save-abc.json")
        XCTAssertEqual(ICloudSaveMirror.materializedName("notes.txt"), "notes.txt")
    }
}
