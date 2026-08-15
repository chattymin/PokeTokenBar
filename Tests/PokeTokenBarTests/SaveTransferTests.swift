import XCTest
@testable import PokeTokenBar

// MARK: 스텁 (이 파일 전용 — 다른 테스트 파일의 스텁은 file-private)

private enum TransferStubError: Error { case unavailable }

/// 세이브 이전 테스트는 진화 라인을 필요로 하지 않는다 — 사용량 적립은 라인 미로딩에서도
/// 동작해야 하기 때문(CompanionStore.applyUsage 주석). 전부 실패시켜 그 경로를 강제한다.
private struct OfflineProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw TransferStubError.unavailable }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { throw TransferStubError.unavailable }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { throw TransferStubError.unavailable }
}

private let transferNow = Date(timeIntervalSince1970: 1_700_000_000)

/// 시각을 앞으로 밀 수 있는 주입 시계 — 백업 슬롯이 불러오기마다 갈리는지 보려면 두 번의
/// `applySave` 가 서로 다른 초를 봐야 한다.
private final class MutableClock: @unchecked Sendable {
    var now: Date
    init(_ now: Date) { self.now = now }
}

/// 비동기 경합 테스트용 1회성 신호 — 부화가 네트워크 대기에 들어간 순간을 정확히 잡기 위해
/// sleep 대신 쓴다(타이밍 의존 = flaky).
private actor TransferSignal {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var fired = false
    func fire() { fired = true; waiters.forEach { $0.resume() }; waiters.removeAll() }
    func wait() async {
        if fired { return }
        await withCheckedContinuation { waiters.append($0) }
    }
}

/// **종 롤**(`baseSpeciesIndex`)에서 멈추는 provider — `hatchIfNeeded` 의 첫 await 창을 재현한다.
/// 라인 fetch 창(`GatedProvider`)과는 다른 지점이라 별도 스텁이 필요하다.
private struct GatedIndexProvider: PokeProviding {
    let entered: TransferSignal
    let release: TransferSignal
    let result: EvoLine
    func line(baseSpeciesID: Int) async throws -> EvoLine { result }
    func baseSpeciesIndex() async throws -> [BaseSpecies] {
        await entered.fire()
        await release.wait()
        return [BaseSpecies(id: 1, captureRate: 255)]
    }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

/// 라인 fetch 에서 멈춰 있다가 신호를 받고 반환하는 provider — 부화 중 상태 교체를 재현한다.
private struct GatedProvider: PokeProviding {
    let entered: TransferSignal
    let release: TransferSignal
    let result: EvoLine
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        await entered.fire()
        await release.wait()
        return result
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { throw TransferStubError.unavailable }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { throw TransferStubError.unavailable }
}

@MainActor
final class SaveTransferTests: XCTestCase {

    /// 테스트마다 **전용 디렉토리**를 준다. 불러오기 백업은 상태 파일 이름이 아니라 시각으로 이름이
    /// 정해지므로, 공유 임시 디렉토리를 쓰면 고정 시계를 쓰는 테스트들끼리 같은 백업 파일명을 놓고 충돌한다.
    private func tempURL(_ tag: String) -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ptb-\(tag)-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("companion-state.json")
    }

    private func store(at url: URL) -> CompanionStore {
        CompanionStore(provider: OfflineProvider(), clock: { transferNow }, fileURL: url)
    }

    /// 옛 기기에서 내보낸 것과 같은 모양의 상태 — 오늘 이미 56.8M 을 적립해 둔 시점.
    private func oldMacState(today: String) -> CompanionState {
        var s = CompanionState()
        s.installBaselineSet = true
        s.usedSinceInstall = 8_000_000_000
        s.spentTokens = 3_500_000_000
        s.claimedTodayTokensByProvider = ["test": 56_800_000]
        s.lastDate = today
        s.inventory = ["rareCandy": 2]
        s.collectedFinals = ["1-3"]
        s.dex = [DexEntry(baseID: 1, finalID: 3, chainOrder: [1, 2, 3], rarity: .common, caughtAt: transferNow)]
        return s
    }

    // MARK: 봉투

    func testRoundTripPreservesProgress() throws {
        let original = oldMacState(today: "2026-08-03")
        let data = try SaveTransfer.encode(state: original, appVersion: "2.5.0",
                                           deviceName: "Old Mac", now: transferNow)
        let envelope = try SaveTransfer.decode(data)

        XCTAssertEqual(envelope.format, SaveEnvelope.formatID)
        XCTAssertEqual(envelope.sourceDevice, "Old Mac")
        XCTAssertEqual(envelope.state.usedSinceInstall, original.usedSinceInstall)
        XCTAssertEqual(envelope.state.spentTokens, original.spentTokens)
        XCTAssertEqual(envelope.state.inventory, original.inventory)
        XCTAssertEqual(envelope.state.dex.count, 1)
        XCTAssertEqual(envelope.state.collectedFinals, original.collectedFinals)
    }

    /// [핵심] 봉투가 없으면 `CompanionState` 의 관대 디코딩이 아무 JSON 이나 빈 상태로 흡수해
    /// "불러오기 성공 → 도감이 사라짐"이 된다. 포맷 id 로 먼저 거른다.
    func testForeignJSONIsRejectedRatherThanImportedAsEmptyState() throws {
        // 관대 디코딩이면 통째로 통과해 버릴 모양의 JSON.
        let foreign = Data(#"{"some":"other app","dex":123}"#.utf8)
        XCTAssertThrowsError(try SaveTransfer.decode(foreign)) { error in
            XCTAssertEqual(error as? SaveTransferError, .notASaveFile)
        }

        // 상태만 담긴(봉투 없는) 예전식 파일도 세이브로 인정하지 않는다.
        let bare = try JSONEncoder().encode(oldMacState(today: "2026-08-03"))
        XCTAssertThrowsError(try SaveTransfer.decode(bare)) { error in
            XCTAssertEqual(error as? SaveTransferError, .notASaveFile)
        }
    }

    /// [회귀·딥리뷰 H4] `decode` 는 "디코딩 실패 **또는** format 불일치"라는 `A || B` 게이트인데,
    /// 기존 두 케이스는 모두 필수 키 누락이라 A 로만 통과했다 — `format` 비교를 통째로 삭제해도
    /// 전체 스위트가 그대로 통과했다(뮤테이션으로 확인). 여기서 **B 단독**을 고정한다:
    /// 6개 필드가 전부 유효하고 `format` 값만 다른 완전한 봉투.
    func testValidEnvelopeWithWrongFormatIDIsRejected() throws {
        let data = try SaveTransfer.encode(state: oldMacState(today: "2026-08-03"),
                                           appVersion: "2.5.0", deviceName: "Other App", now: transferNow)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["format"] as? String, SaveEnvelope.formatID, "전제: 원본은 유효한 포맷")
        json["format"] = "someotherapp.save"
        let patched = try JSONSerialization.data(withJSONObject: json)

        // 디코딩 자체는 성공해야 한다 — 그래야 B 분기(포맷 값 비교)만 단독으로 검증된다.
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        XCTAssertNotNil(try? decoder.decode(SaveEnvelope.self, from: patched),
                        "전제: 필드 구조는 유효 — 여기서 nil 이면 A 분기로 새어 테스트가 무의미해진다")

        XCTAssertThrowsError(try SaveTransfer.decode(patched)) { error in
            XCTAssertEqual(error as? SaveTransferError, .notASaveFile)
        }
    }

    func testNewerSchemaIsRejected() throws {
        var data = try SaveTransfer.encode(state: CompanionState(), appVersion: "2.5.0",
                                           deviceName: "Future Mac", now: transferNow)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["schema"] = SaveEnvelope.schemaVersion + 1
        data = try JSONSerialization.data(withJSONObject: json)

        XCTAssertThrowsError(try SaveTransfer.decode(data)) { error in
            XCTAssertEqual(error as? SaveTransferError,
                           .newerSchema(found: SaveEnvelope.schemaVersion + 1,
                                        supported: SaveEnvelope.schemaVersion))
        }
    }

    // MARK: 기기 기준 재정렬 (회귀)

    /// [회귀] 이전 당일에 새 Mac 에서 쓴 토큰이 조용히 누락되던 결함.
    ///
    /// `claimedTodayTokensByProvider` 는 "이 기기가 프로바이더별로 오늘 어디까지 적립했나"인데 옛 기기 값(56.8M)이 그대로
    /// 따라오면 `update` 의 `todayTokens > claimedTodayTokens` 게이트가 하루 종일 거짓이 된다.
    /// 대조군(재정렬 없음)을 같이 돌려 트리거 브랜치를 실제로 밟는지 확인한다.
    func testTransferDayTokensStillCountAfterRebase() throws {
        let today = "2026-08-03"
        let imported = oldMacState(today: today)
        let newMacTodaySoFar = 5_000_000
        let newMacTodayLater = 8_000_000

        // 대조군: 재정렬 없이 그대로 들여온 경우 — 델타가 적립되지 않아야 한다(결함 재현).
        let rawURL = tempURL("raw")
        try JSONEncoder().encode(imported).write(to: rawURL)
        let raw = store(at: rawURL)
        let rawBefore = raw.state.usedSinceInstall
        raw.update(todayTokensByProvider: ["test": newMacTodayLater], todayDate: today, monthTotal: 0,
                   burnTier: .idle, limitWarning: false, hasUsageData: true)
        XCTAssertEqual(raw.state.usedSinceInstall - rawBefore, 0,
                       "재현 실패 — 이 대조군이 0 이 아니면 결함 조건이 바뀐 것이므로 테스트가 무의미해진다")

        // 실제 경로: 불러오기 시점의 이 기기 오늘 사용량으로 장부를 다시 잡는다.
        let url = tempURL("rebased")
        let s = store(at: url)
        let data = try SaveTransfer.encode(state: imported, appVersion: "2.5.0",
                                           deviceName: "Old Mac", now: transferNow)
        let envelope = try SaveTransfer.decode(data)
        try s.applySave(envelope, todayTokensByProvider: ["test": newMacTodaySoFar], todayDate: today, hasUsageData: true)

        XCTAssertEqual(s.state.claimedTodayTokensByProvider?["test"], newMacTodaySoFar)
        XCTAssertEqual(s.state.lastDate, today)
        XCTAssertTrue(s.state.installBaselineSet)

        let before = s.state.usedSinceInstall
        s.update(todayTokensByProvider: ["test": newMacTodayLater], todayDate: today, monthTotal: 0,
                 burnTier: .idle, limitWarning: false, hasUsageData: true)
        XCTAssertEqual(s.state.usedSinceInstall - before, newMacTodayLater - newMacTodaySoFar,
                       "이전 당일에도 새 Mac 에서 쓴 증분이 적립돼야 한다")
    }

    /// 불러올 때 이 기기의 오늘 사용량을 아직 모르면(파싱 전·프로바이더 없음) baseline 판정을
    /// 신규 설치 경로에 넘긴다 — 여기서 0 으로 잡으면 첫 파싱 때 하루치가 통째로 델타가 된다.
    func testImportWithoutUsageDataDefersBaselineInsteadOfCreditingWholeDay() throws {
        let today = "2026-08-03"
        let url = tempURL("nodata")
        let s = store(at: url)
        let data = try SaveTransfer.encode(state: oldMacState(today: today), appVersion: "2.5.0",
                                           deviceName: "Old Mac", now: transferNow)
        try s.applySave(try SaveTransfer.decode(data), todayTokensByProvider: ["test": 0], todayDate: today, hasUsageData: false)

        XCTAssertFalse(s.state.installBaselineSet)

        // 데이터가 도착하는 첫 틱은 baseline 만 잡고 적립하지 않는다.
        let before = s.state.usedSinceInstall
        s.update(todayTokensByProvider: ["test": 40_000_000], todayDate: today, monthTotal: 0,
                 burnTier: .idle, limitWarning: false, hasUsageData: true)
        XCTAssertEqual(s.state.usedSinceInstall, before, "도착 시점의 하루치를 소급 적립하지 않는다")
        XCTAssertEqual(s.state.claimedTodayTokensByProvider?["test"], 40_000_000)

        // 그 다음부터는 정상 적립.
        s.update(todayTokensByProvider: ["test": 41_000_000], todayDate: today, monthTotal: 0,
                 burnTier: .idle, limitWarning: false, hasUsageData: true)
        XCTAssertEqual(s.state.usedSinceInstall - before, 1_000_000)
    }

    /// [회귀] stale snapshot만 남아 `hasUsageData`는 true인데 오늘 map은 비어 있는 상태로
    /// 세이브를 불러와도, 빈 provider ledger를 유효한 기준점으로 저장하면 안 된다.
    /// 첫 정상 snapshot은 baseline으로만 잡고, 그 이후 증가분부터 적립해야 한다.
    func testImportWithStaleOnlyUsageDefersBaselineInsteadOfSeedingEmptyLedger() throws {
        let today = "2026-08-03"
        let url = tempURL("stale-only")
        let s = store(at: url)
        let data = try SaveTransfer.encode(state: oldMacState(today: today), appVersion: "2.5.0",
                                           deviceName: "Old Mac", now: transferNow)

        // snapshots가 stale이거나 carrier만 남은 상태: 표시용 hasUsageData는 true지만
        // 오늘 날짜가 확인된 provider 데이터는 없다.
        try s.applySave(try SaveTransfer.decode(data), todayTokensByProvider: [:], todayDate: today,
                        hasUsageData: true)

        XCTAssertFalse(s.state.installBaselineSet)
        XCTAssertNil(s.state.claimedTodayTokensByProvider)
        XCTAssertEqual(s.state.lastDate, "")

        let before = s.state.usedSinceInstall
        s.update(todayTokensByProvider: ["test": 40_000_000], todayDate: today, monthTotal: 0,
                 burnTier: .idle, limitWarning: false, hasUsageData: true)
        XCTAssertEqual(s.state.usedSinceInstall, before, "첫 정상 snapshot은 baseline만 설정해야 한다")
        XCTAssertEqual(s.state.claimedTodayTokensByProvider?["test"], 40_000_000)

        s.update(todayTokensByProvider: ["test": 41_000_000], todayDate: today, monthTotal: 0,
                 burnTier: .idle, limitWarning: false, hasUsageData: true)
        XCTAssertEqual(s.state.usedSinceInstall - before, 1_000_000,
                       "빈 ledger로 import해도 이후 증가분은 정상 적립돼야 한다")
    }

    // MARK: 진행 보존 · 가드레일

    func testImportKeepsProgressAndCandyGrantLedger() throws {
        let today = "2026-08-03"
        var imported = oldMacState(today: today)
        // 한도는 계정 전역이라 같은 창 key 가 새 기기에서도 유효하다 — 원장을 버리면 사탕이 중복 지급된다.
        imported.candyGrantTier = ["five_hour|2026-08-03T00:00:00Z": 100]
        imported.candyFeatureSeeded = true

        let url = tempURL("progress")
        let s = store(at: url)
        let data = try SaveTransfer.encode(state: imported, appVersion: "2.5.0",
                                           deviceName: "Old Mac", now: transferNow)
        try s.applySave(try SaveTransfer.decode(data), todayTokensByProvider: ["test": 1], todayDate: today, hasUsageData: true)

        XCTAssertEqual(s.state.usedSinceInstall, 8_000_000_000)
        XCTAssertEqual(s.state.spentTokens, 3_500_000_000)
        XCTAssertEqual(s.state.dex.count, 1)
        XCTAssertEqual(s.state.inventory["rareCandy"], 2)
        XCTAssertEqual(s.state.candyGrantTier["five_hour|2026-08-03T00:00:00Z"], 100,
                       "사탕 지급 원장 보존 — 버리면 같은 창에서 재지급된다")
        XCTAssertTrue(s.state.candyFeatureSeeded)
    }

    /// 덮어쓰기 전 직전 상태를 남긴다 — 잘못 불러왔을 때 손으로 되돌릴 수단.
    func testPreviousStateIsBackedUpBeforeOverwrite() throws {
        let today = "2026-08-03"
        let url = tempURL("backup")

        var mine = CompanionState()
        mine.installBaselineSet = true
        mine.usedSinceInstall = 123_456_789
        try JSONEncoder().encode(mine).write(to: url)

        let s = store(at: url)
        XCTAssertEqual(s.state.usedSinceInstall, 123_456_789)

        let data = try SaveTransfer.encode(state: oldMacState(today: today), appVersion: "2.5.0",
                                           deviceName: "Old Mac", now: transferNow)
        try s.applySave(try SaveTransfer.decode(data), todayTokensByProvider: ["test": 0], todayDate: today, hasUsageData: true)

        let backup = url.deletingLastPathComponent()
            .appendingPathComponent(SaveTransfer.backupFileName(date: transferNow))
        let restored = try JSONDecoder().decode(CompanionState.self, from: Data(contentsOf: backup))
        XCTAssertEqual(restored.usedSinceInstall, 123_456_789, "덮어쓰기 전 상태가 그대로 남아야 한다")
        XCTAssertEqual(s.state.usedSinceInstall, 8_000_000_000)
    }

    /// [회귀] 불러오기가 진행 중인 부화의 네트워크 대기 창에 들어오면, 뒤늦게 끝난 부화가 방금 불러온
    /// 개체를 덮어썼다. `isHatching` 락은 같은 앱 안의 중복 부화만 막을 뿐 상태 통째 교체는 못 막는다.
    func testImportDuringHatchDiscardsTheHatch() async throws {
        let entered = TransferSignal()
        let release = TransferSignal()
        let evo = EvoLine(baseID: 1, tree: EvoNode(speciesID: 1, children: []), rarity: .common,
                          names: [1: ["en": "P1", "ko": "포1", "ja": "ポ1"]])
        let url = tempURL("hatchrace")
        let s = CompanionStore(provider: GatedProvider(entered: entered, release: release, result: evo),
                               clock: { transferNow }, fileURL: url)

        let hatching = Task { await s.hatch(baseID: 1) }
        await entered.wait()   // 부화가 라인 fetch(네트워크) 대기 지점에 도달

        var imported = oldMacState(today: "2026-08-03")
        imported.active = MonState(baseID: 403, pathIDs: [403], plannedPathIDs: [403],
                                   stageIndex: 0, usedAtStage: 0, rarity: .common, totalForms: 1)
        let data = try SaveTransfer.encode(state: imported, appVersion: "2.5.0",
                                           deviceName: "Old Mac", now: transferNow)
        try s.applySave(try SaveTransfer.decode(data), todayTokensByProvider: ["test": 1],
                    todayDate: "2026-08-03", hasUsageData: true)

        await release.fire()
        await hatching.value

        XCTAssertEqual(s.state.active?.baseID, 403, "뒤늦게 끝난 부화가 불러온 개체를 덮어쓰면 안 된다")
        XCTAssertEqual(s.state.dex.count, imported.dex.count, "도감도 부화 경로에 밀려나면 안 된다")
    }

    /// [회귀·딥리뷰 B1] 부화의 **첫** await(`chooseBase`) 창에 불러오기가 들어오면, 그 뒤 진입하는
    /// `hatchCore` 는 *교체 이후*의 세대를 캡처해 자기 가드가 무조건 통과한다 — 옛 롤 결과가 불러온
    /// 개체를 덮어쓰고 디스크에 박혔다. 위의 `testImportDuringHatchDiscardsTheHatch` 는 `hatch(baseID:)`
    /// 경로라 이 브랜치를 지나지 않는다(통과하면서 아무것도 지키지 않던 상태).
    func testImportDuringSpeciesRollDiscardsTheHatch() async throws {
        let entered = TransferSignal()
        let release = TransferSignal()
        let evo = EvoLine(baseID: 1, tree: EvoNode(speciesID: 1, children: []), rarity: .common,
                          names: [1: ["en": "P1", "ko": "포1", "ja": "ポ1"]])
        let url = tempURL("rollrace")

        // 알 상태 + 부화 임계 도달 + pre-roll 없음 → `chooseBase()` 로 들어간다.
        var egg = CompanionState()
        egg.installBaselineSet = true
        egg.eggUsage = PokemonBalance.eggHatchThreshold
        try JSONEncoder().encode(egg).write(to: url)

        let s = CompanionStore(provider: GatedIndexProvider(entered: entered, release: release, result: evo),
                               clock: { transferNow }, fileURL: url)
        XCTAssertNil(s.state.active, "전제: 알 상태에서 시작")

        let hatching = Task { await s.hatchIfNeeded() }
        await entered.wait()   // 종 롤이 인덱스 대기 지점에 도달

        var imported = oldMacState(today: "2026-08-03")
        imported.active = MonState(baseID: 403, pathIDs: [403], plannedPathIDs: [403],
                                   stageIndex: 0, usedAtStage: 0, rarity: .common, totalForms: 1)
        let data = try SaveTransfer.encode(state: imported, appVersion: "2.5.0",
                                           deviceName: "Old Mac", now: transferNow)
        try s.applySave(try SaveTransfer.decode(data), todayTokensByProvider: ["test": 1],
                    todayDate: "2026-08-03", hasUsageData: true)

        await release.fire()
        await hatching.value

        XCTAssertEqual(s.state.active?.baseID, 403, "종 롤 대기 중 들어온 불러오기를 부화가 덮어쓰면 안 된다")
        XCTAssertEqual(s.state.dex.count, imported.dex.count)
    }

    /// [회귀·딥리뷰 H3] 부화가 폐기된 뒤 불러온 개체의 진화 라인이 다시 로드돼야 한다.
    /// `applySave` 가 띄우는 로드는 `loadCurrentLine` 의 `!isHatching` 가드에 막혀 조용히 실패하는데,
    /// 아무도 재시도하지 않으면 다음 update 틱(기본 120초)까지 이름이 "Token Egg" 로 남았다.
    /// 위 두 경합 테스트는 `state.active`·`dex` 만 단언해 이 경로를 통과시킨다.
    func testImportDuringHatchStillLoadsTheImportedLine() async throws {
        let entered = TransferSignal()
        let release = TransferSignal()
        // 불러올 개체(403)의 라인을 제공하는 provider — 부화용 라인 fetch 에서 한 번 멈춘다.
        let evo = EvoLine(baseID: 403, tree: EvoNode(speciesID: 403, children: []), rarity: .common,
                          names: [403: ["en": "Shinx", "ko": "꼬링크", "ja": "コリンク"]])
        let url = tempURL("linereload")
        let s = CompanionStore(provider: GatedProvider(entered: entered, release: release, result: evo),
                               clock: { transferNow }, fileURL: url)

        let hatching = Task { await s.hatch(baseID: 1) }
        await entered.wait()

        var imported = oldMacState(today: "2026-08-03")
        imported.active = MonState(baseID: 403, pathIDs: [403], plannedPathIDs: [403],
                                   stageIndex: 0, usedAtStage: 0, rarity: .common, totalForms: 1)
        let data = try SaveTransfer.encode(state: imported, appVersion: "2.5.0",
                                           deviceName: "Old Mac", now: transferNow)
        try s.applySave(try SaveTransfer.decode(data), todayTokensByProvider: ["test": 1],
                    todayDate: "2026-08-03", hasUsageData: true)
        XCTAssertNil(s.currentLine, "전제: 부화 락에 막혀 라인이 아직 없다")

        await release.fire()
        await hatching.value

        // 폐기 후 재점화된 로드가 끝날 때까지 양보(sleep 아님 — 이벤트 루프만 돌린다).
        var spins = 0
        while s.currentLine == nil, spins < 500 { await Task.yield(); spins += 1 }

        XCTAssertNotNil(s.currentLine, "부화가 폐기됐으면 불러온 개체의 라인을 다시 로드해야 한다")
        XCTAssertEqual(s.currentLine?.baseID, 403)
        XCTAssertNotEqual(s.displayName, "Token Egg", "이름이 알 표기로 남으면 안 된다")
    }

    /// [회귀·딥리뷰 H1] 새 Mac 에서 AI CLI 를 아직 안 쓴 시점(hasUsageData=false)에 불러오면,
    /// 개체가 있는데도 알로 표시되고 진화 라인 로드 재시도가 도달 불가였다.
    func testImportedCompanionIsNotShownAsEggBeforeUsageArrives() throws {
        let today = "2026-08-03"
        let url = tempURL("noegg")
        let s = store(at: url)
        var imported = oldMacState(today: today)
        imported.active = MonState(baseID: 403, pathIDs: [403], plannedPathIDs: [403],
                                   stageIndex: 0, usedAtStage: 0, rarity: .common, totalForms: 1)
        let data = try SaveTransfer.encode(state: imported, appVersion: "2.5.0",
                                           deviceName: "Old Mac", now: transferNow)
        try s.applySave(try SaveTransfer.decode(data), todayTokensByProvider: ["test": 0], todayDate: today, hasUsageData: false)
        XCTAssertFalse(s.state.installBaselineSet, "전제: baseline 판정을 미룬 상태")

        s.update(todayTokensByProvider: ["test": 0], todayDate: today, monthTotal: 0,
                 burnTier: .idle, limitWarning: false, hasUsageData: false)
        XCTAssertNotNil(s.state.active, "개체는 그대로 있어야 한다")
        XCTAssertEqual(s.displayState, .idle, "개체가 있는데 알로 표시하면 안 된다")

        // 알 상태에서 같은 경로를 타면 여전히 알이어야 한다(반대 방향 고정).
        let eggURL = tempURL("stillegg")
        let e = store(at: eggURL)
        e.update(todayTokensByProvider: ["test": 0], todayDate: today, monthTotal: 0,
                 burnTier: .idle, limitWarning: false, hasUsageData: false)
        XCTAssertEqual(e.displayState, .egg)
    }

    // MARK: 신뢰경계 값 정규화 (딥리뷰 H2)

    /// [회귀·딥리뷰 H2] 극단값 세이브가 그대로 저장되면 이후 산술이 오버플로 트랩으로 프로세스를 죽이고,
    /// 재기동해도 같은 파일을 읽어 다시 죽는다(수동 삭제 전까지 복구 불가).
    func testExtremeValuesAreClampedAtTheTrustBoundary() throws {
        var evil = CompanionState()
        evil.installBaselineSet = true
        evil.usedSinceInstall = Int.max
        evil.spentTokens = Int.min
        evil.eggUsage = Int.max
        evil.claimedTodayTokensByProvider = ["test": -42]
        evil.active = MonState(baseID: 1, pathIDs: [1], plannedPathIDs: [1],
                               stageIndex: Int.max, usedAtStage: Int.max, rarity: .common,
                               totalForms: Int.max)

        let data = try SaveTransfer.encode(state: evil, appVersion: "2.5.0",
                                           deviceName: "Corrupt", now: transferNow)
        let envelope = try SaveTransfer.decode(data)
        let s = envelope.state

        XCTAssertEqual(s.usedSinceInstall, SaveTransfer.maxTokenValue)
        XCTAssertEqual(s.spentTokens, 0, "음수는 0 으로")
        XCTAssertEqual(s.eggUsage, SaveTransfer.maxTokenValue)
        XCTAssertEqual(s.claimedTodayTokensByProvider?["test"], 0)
        XCTAssertEqual(s.active?.usedAtStage, SaveTransfer.maxTokenValue)
        XCTAssertEqual(s.active?.totalForms, 12)
        XCTAssertEqual(s.active?.stageIndex, 0, "pathIDs 범위를 넘지 않아야 한다")

        // 정규화된 값으로 실제 산술 경로를 태워 트랩이 안 나는지 확인한다.
        let url = tempURL("clamped")
        let store = store(at: url)
        try store.applySave(envelope, todayTokensByProvider: ["test": 0], todayDate: "2026-08-03", hasUsageData: true)
        XCTAssertGreaterThanOrEqual(store.availableTokens, 0)
        store.update(todayTokensByProvider: ["test": 1_000], todayDate: "2026-08-03", monthTotal: 0,
                     burnTier: .idle, limitWarning: false, hasUsageData: true)
        XCTAssertLessThanOrEqual(store.state.usedSinceInstall, SaveTransfer.maxTokenValue + 1_000)
    }

    /// [회귀·딥리뷰 H2 후속] 불러오기 경계만 막으면 **이미 디스크에 있는** 극단값은 남아, 매 기동마다
    /// 같은 값을 읽어 산술 트랩으로 죽는 상태를 벗어나지 못한다(디코드가 성공하므로 `.corrupt` 복구도
    /// 발동 안 함). 상태 파일을 읽는 경로에서도 같은 정규화가 걸려야 자가 복구된다.
    func testCorruptStateOnDiskIsClampedOnLoadNotJustOnImport() throws {
        let url = tempURL("diskclamp")
        // 앱이 아니라 손편집·이전 버전이 남긴 것처럼 극단값을 직접 파일에 심는다.
        let json = #"{"installBaselineSet":true,"usedSinceInstall":9223372036854775807,"#
            + #""spentTokens":-9223372036854775808,"eggUsage":9223372036854775807,"#
            + #""claimedTodayTokens":-1,"lastDate":"2026-08-03"}"#
        try Data(json.utf8).write(to: url)

        let s = store(at: url)
        XCTAssertEqual(s.state.usedSinceInstall, SaveTransfer.maxTokenValue)
        XCTAssertEqual(s.state.spentTokens, 0)
        XCTAssertEqual(s.state.eggUsage, SaveTransfer.maxTokenValue)
        XCTAssertNil(s.state.claimedTodayTokensByProvider, "구버전 aggregate field는 프로바이더별 ledger로 추정하지 않는다")

        // 정규화된 값으로 실제 산술 경로를 태워 트랩이 안 나는지 확인(이 줄이 예전엔 SIGTRAP).
        XCTAssertGreaterThanOrEqual(s.availableTokens, 0)
        s.update(todayTokensByProvider: ["test": 1_000], todayDate: "2026-08-03", monthTotal: 0,
                 burnTier: .idle, limitWarning: false, hasUsageData: true)
        XCTAssertLessThanOrEqual(s.state.usedSinceInstall, SaveTransfer.maxTokenValue + 1_000)
    }

    // MARK: 필드 부류 (딥리뷰 M-c·M-e·M-g)

    /// [딥리뷰 M-g] 이전 시 필드 분류가 산문 규약뿐이라, 새 필드가 추가되면 아무 판단 없이 "진행"으로
    /// 딸려 들어간다(`language` 가 실제로 그랬다). 필드 목록을 테스트로 고정해 **분류를 강제**한다.
    func testEveryCompanionStateFieldIsClassifiedForTransfer() {
        // eggTier(알 등급 보증) = 진행 — 산 물건이지 이 기기의 장부가 아니라 기기를 옮겨도 따라간다.
        let progress: Set<String> = ["usedSinceInstall", "spentTokens", "eggUsage", "eggTier",
                                     "pendingHatchID", "active", "dex", "collectedFinals", "inventory"]
        let deviceLedger: Set<String> = ["installBaselineSet", "claimedTodayTokensByProvider", "lastDate"]
        let accountLedger: Set<String> = ["candyGrantTier", "candyFeatureSeeded"]
        let devicePreference: Set<String> = ["language"]

        let classified = progress.union(deviceLedger).union(accountLedger).union(devicePreference)
        let actual = Set(Mirror(reflecting: CompanionState()).children.compactMap(\.label))
        XCTAssertEqual(actual, classified, """
            CompanionState 필드가 바뀌었다. 세이브 이전에서 이 필드가 무엇인지 정하고 목록을 갱신하라 —
            진행(그대로) / 로컬 장부(새 기기 기준 재설정) / 계정 원장(병합) / 기기 환경설정(현재 값 유지).
            """)
    }

    /// [딥리뷰 M-c] `language` 는 진행이 아니라 이 기기에서 보는 방식이다. 일본어 Mac 의 세이브가
    /// 영어 Mac 의 UI 언어를 조용히 바꾸면 안 된다.
    func testImportKeepsThisDevicesLanguage() throws {
        let today = "2026-08-03"
        let url = tempURL("lang")
        var mine = CompanionState()
        mine.installBaselineSet = true
        mine.language = .en
        try JSONEncoder().encode(mine).write(to: url)
        let s = store(at: url)
        XCTAssertEqual(s.language, .en)

        var imported = oldMacState(today: today)
        imported.language = .ja
        let data = try SaveTransfer.encode(state: imported, appVersion: "2.5.0",
                                           deviceName: "JA Mac", now: transferNow)
        try s.applySave(try SaveTransfer.decode(data), todayTokensByProvider: ["test": 1],
                        todayDate: today, hasUsageData: true)

        XCTAssertEqual(s.language, .en, "불러온 세이브의 언어가 이 기기 설정을 덮으면 안 된다")
        XCTAssertEqual(s.state.dex.count, imported.dex.count, "진행은 그대로 들어와야 한다")
    }

    /// [딥리뷰 M-e] 사탕 지급 원장은 계정 전역(한도 창 key)이라 통째 교체하면 안 된다.
    /// **더 오래된** 세이브를 불러오면 이미 지급한 창의 기록이 사라져 같은 창에서 재지급된다.
    func testCandyGrantLedgerMergesInsteadOfBeingReplacedByAnOlderSave() throws {
        let today = "2026-08-03"
        let url = tempURL("candy")
        var mine = CompanionState()
        mine.installBaselineSet = true
        mine.candyGrantTier = ["five_hour|A": 100, "weekly|B": 80]
        try JSONEncoder().encode(mine).write(to: url)
        let s = store(at: url)

        // 옛 세이브: A 창을 아직 못 봤고, B 는 더 낮은 tier 에서 찍혔다.
        var older = oldMacState(today: today)
        older.candyGrantTier = ["weekly|B": 50, "five_hour|C": 100]
        let data = try SaveTransfer.encode(state: older, appVersion: "2.5.0",
                                           deviceName: "Old Mac", now: transferNow)
        try s.applySave(try SaveTransfer.decode(data), todayTokensByProvider: ["test": 1],
                        todayDate: today, hasUsageData: true)

        XCTAssertEqual(s.state.candyGrantTier["five_hour|A"], 100, "이 기기가 이미 지급한 창이 사라지면 재지급된다")
        XCTAssertEqual(s.state.candyGrantTier["weekly|B"], 80, "같은 창은 더 높은 tier 를 남긴다")
        XCTAssertEqual(s.state.candyGrantTier["five_hour|C"], 100, "세이브 쪽 창도 들어와야 한다")
    }

    // MARK: 백업 가드레일 (딥리뷰 M-a·M-b)

    /// [딥리뷰 M-a] 확인창은 3개 언어로 "직전 상태가 남는다"고 약속한다. 백업을 못 남기면 그 약속을
    /// 못 지키는 것이므로 **덮어쓰지 않고 중단**해야 한다(예전엔 `try?` 로 삼키고 그냥 진행했다).
    func testImportAbortsWhenBackupCannotBeWritten() throws {
        let today = "2026-08-03"
        let url = tempURL("nobackup")
        var mine = CompanionState()
        mine.installBaselineSet = true
        mine.usedSinceInstall = 123_456_789
        try JSONEncoder().encode(mine).write(to: url)
        let s = store(at: url)

        // 백업이 쓰일 자리를 디렉토리로 막아 쓰기를 실패시킨다.
        let blocked = url.deletingLastPathComponent()
            .appendingPathComponent(SaveTransfer.backupFileName(date: transferNow))
        try FileManager.default.createDirectory(at: blocked, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: blocked) }

        let data = try SaveTransfer.encode(state: oldMacState(today: today), appVersion: "2.5.0",
                                           deviceName: "Old Mac", now: transferNow)
        let envelope = try SaveTransfer.decode(data)
        XCTAssertThrowsError(try s.applySave(envelope, todayTokensByProvider: ["test": 1], todayDate: today, hasUsageData: true)) {
            XCTAssertEqual($0 as? SaveTransferError, .backupFailed)
        }
        XCTAssertEqual(s.state.usedSinceInstall, 123_456_789, "중단했으면 진행이 그대로여야 한다")
        XCTAssertTrue(s.state.dex.isEmpty)
    }

    /// [딥리뷰 M-b] 백업 슬롯이 하나면 두 번째 불러오기가 **원본**을 덮어써, 되돌리려는 바로 그
    /// 순간 되돌릴 대상이 사라진다. 불러올 때마다 새 슬롯이어야 한다.
    func testSecondImportDoesNotDestroyTheOriginalBackup() throws {
        let today = "2026-08-03"
        let url = tempURL("twoimports")
        var original = CompanionState()
        original.installBaselineSet = true
        original.usedSinceInstall = 111
        try JSONEncoder().encode(original).write(to: url)

        let clock = MutableClock(transferNow)
        let s = CompanionStore(provider: OfflineProvider(), clock: { clock.now }, fileURL: url)

        var first = oldMacState(today: today); first.usedSinceInstall = 222
        try s.applySave(try SaveTransfer.decode(
            try SaveTransfer.encode(state: first, appVersion: "2.5.0", deviceName: "A", now: transferNow)),
                        todayTokensByProvider: ["test": 1], todayDate: today, hasUsageData: true)

        clock.now = transferNow.addingTimeInterval(60)   // 다음 백업은 다른 슬롯
        var second = oldMacState(today: today); second.usedSinceInstall = 333
        try s.applySave(try SaveTransfer.decode(
            try SaveTransfer.encode(state: second, appVersion: "2.5.0", deviceName: "B", now: transferNow)),
                        todayTokensByProvider: ["test": 1], todayDate: today, hasUsageData: true)

        let dir = url.deletingLastPathComponent()
        let backups = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasPrefix(SaveTransfer.backupFilePrefix) }.sorted()
        XCTAssertEqual(backups.count, 2, "불러오기마다 새 슬롯이어야 한다")
        let oldest = try JSONDecoder().decode(
            CompanionState.self, from: Data(contentsOf: dir.appendingPathComponent(backups[0])))
        XCTAssertEqual(oldest.usedSinceInstall, 111, "가장 오래된 백업이 원본이어야 한다")
        for name in backups { try? FileManager.default.removeItem(at: dir.appendingPathComponent(name)) }
    }

    // MARK: 확인창 정책 · 표시 상태 (딥리뷰 M-f·M-h)

    /// [딥리뷰 M-f] 파괴적 버튼이 기본이면 Return 한 키로 진행이 대체된다. `NSAlert` 구성은 XCTest 에서
    /// 도달 불가라 규칙만 순수 함수로 빼 고정한다.
    func testCancelIsTheDefaultButtonOnTheImportConfirmation() {
        XCTAssertEqual(ImportConfirmPolicy.keyEquivalent(forButtonAt: ImportConfirmPolicy.cancelButtonIndex), "\r")
        XCTAssertEqual(ImportConfirmPolicy.keyEquivalent(forButtonAt: ImportConfirmPolicy.replaceButtonIndex), "",
                       "대체(파괴적) 버튼이 기본이면 안 된다")
    }

    /// [딥리뷰 M-h] `applySave` 가 정하는 표시 상태가 어떤 테스트에서도 단언되지 않아, 삼항을 뒤집어도
    /// 통과했다.
    func testApplySaveSetsDisplayStateFromWhetherACompanionCameIn() throws {
        let today = "2026-08-03"
        var withMon = oldMacState(today: today)
        withMon.active = MonState(baseID: 403, pathIDs: [403], plannedPathIDs: [403],
                                  stageIndex: 0, usedAtStage: 0, rarity: .common, totalForms: 1)
        let a = store(at: tempURL("dispA"))
        try a.applySave(try SaveTransfer.decode(
            try SaveTransfer.encode(state: withMon, appVersion: "2.5.0", deviceName: "A", now: transferNow)),
                        todayTokensByProvider: ["test": 1], todayDate: today, hasUsageData: true)
        XCTAssertEqual(a.displayState, .idle)

        let eggOnly = oldMacState(today: today)   // active == nil
        let b = store(at: tempURL("dispB"))
        try b.applySave(try SaveTransfer.decode(
            try SaveTransfer.encode(state: eggOnly, appVersion: "2.5.0", deviceName: "B", now: transferNow)),
                        todayTokensByProvider: ["test": 1], todayDate: today, hasUsageData: true)
        XCTAssertEqual(b.displayState, .egg)
    }

    // MARK: 파일 경계 (딥리뷰 LOW)

    /// 거대한 JSON 은 메인스레드 파싱을 수 초간 잡는다(실측 39MB ≈ 1.8초). 세이브는 수 KB 라 상한이 안전하다.
    func testOversizedFileIsRejectedBeforeParsing() {
        let huge = Data(count: SaveTransfer.maxFileBytes + 1)
        XCTAssertThrowsError(try SaveTransfer.decode(huge)) { error in
            XCTAssertEqual(error as? SaveTransferError,
                           .fileTooLarge(bytes: SaveTransfer.maxFileBytes + 1, limit: SaveTransfer.maxFileBytes))
        }
    }

    /// 상위 스키마 세이브는 본문 모양이 달라 전체 디코드가 실패할 수 있다. 그래도 "세이브 파일이
    /// 아니에요"가 아니라 "앱을 업데이트하라"로 안내해야 한다 — 헤더를 먼저 읽는 이유다.
    func testNewerSchemaIsReportedEvenWhenTheBodyIsUnreadable() throws {
        let json = #"{"format":"poketokenbar.save","schema":99,"whatever":{"unknown":true}}"#
        XCTAssertThrowsError(try SaveTransfer.decode(Data(json.utf8))) { error in
            XCTAssertEqual(error as? SaveTransferError,
                           .newerSchema(found: 99, supported: SaveEnvelope.schemaVersion))
        }
    }

    // MARK: 오류 문구 매핑

    /// 매핑이 어긋나면 `SaveTransferError` 는 LocalizedError 가 아니라 "The operation couldn't be
    /// completed. (PokeTokenBar.SaveTransferError error 0.)" 가 그대로 사용자에게 뜬다.
    /// 언어는 `allCases` 로 돈다 — 리터럴 목록은 언어가 늘어난 순간 조용히 커버를 멈춘다.
    func testImportErrorMessagesAreLocalizedNotRawSwiftText() {
        for lang in AppLanguage.allCases {
            let l = L(lang)
            let notSave = l.importErrorMessage(SaveTransferError.notASaveFile)
            let newer = l.importErrorMessage(SaveTransferError.newerSchema(found: 2, supported: 1))
            XCTAssertEqual(notSave, l.importErrorNotSaveFile, "\(lang)")
            XCTAssertEqual(newer, l.importErrorNewerSchema, "\(lang)")
            for message in [notSave, newer] {
                XCTAssertFalse(message.contains("SaveTransferError"), "원문 노출: \(message)")
                XCTAssertFalse(message.contains("couldn't be completed"), "원문 노출: \(message)")
            }
        }
        // 그 외 오류는 시스템 문구로 폴백(파일 읽기 실패 등).
        let other = NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError)
        XCTAssertEqual(L(.en).importErrorMessage(other), other.localizedDescription)
    }

    func testSuggestedFileNameCarriesDate() {
        // 2026-08-03 12:00 UTC — 정오라 표준시대가 달라도 날짜 경계를 넘지 않는다(파일명은 로컬 날짜).
        let name = SaveTransfer.suggestedFileName(date: Date(timeIntervalSince1970: 1_785_758_400))
        XCTAssertTrue(name.hasPrefix("PokeTokenBar-Save-"))
        XCTAssertTrue(name.hasSuffix(".json"))
        XCTAssertTrue(name.contains("2026-08-03"), "실제 이름: \(name)")
    }
}
