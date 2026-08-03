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

    private func tempURL(_ tag: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ptb-\(tag)-\(UUID().uuidString).json")
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
        s.claimedTodayTokens = 56_800_000
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
    /// `claimedTodayTokens` 는 "이 기기가 오늘 어디까지 적립했나"인데 옛 기기 값(56.8M)이 그대로
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
        raw.update(todayTokens: newMacTodayLater, todayDate: today, monthTotal: 0,
                   burnTier: .idle, limitWarning: false, hasUsageData: true)
        XCTAssertEqual(raw.state.usedSinceInstall - rawBefore, 0,
                       "재현 실패 — 이 대조군이 0 이 아니면 결함 조건이 바뀐 것이므로 테스트가 무의미해진다")

        // 실제 경로: 불러오기 시점의 이 기기 오늘 사용량으로 장부를 다시 잡는다.
        let url = tempURL("rebased")
        let s = store(at: url)
        let data = try SaveTransfer.encode(state: imported, appVersion: "2.5.0",
                                           deviceName: "Old Mac", now: transferNow)
        let envelope = try SaveTransfer.decode(data)
        s.applySave(envelope, todayTokens: newMacTodaySoFar, todayDate: today, hasUsageData: true)

        XCTAssertEqual(s.state.claimedTodayTokens, newMacTodaySoFar)
        XCTAssertEqual(s.state.lastDate, today)
        XCTAssertTrue(s.state.installBaselineSet)

        let before = s.state.usedSinceInstall
        s.update(todayTokens: newMacTodayLater, todayDate: today, monthTotal: 0,
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
        s.applySave(try SaveTransfer.decode(data), todayTokens: 0, todayDate: today, hasUsageData: false)

        XCTAssertFalse(s.state.installBaselineSet)

        // 데이터가 도착하는 첫 틱은 baseline 만 잡고 적립하지 않는다.
        let before = s.state.usedSinceInstall
        s.update(todayTokens: 40_000_000, todayDate: today, monthTotal: 0,
                 burnTier: .idle, limitWarning: false, hasUsageData: true)
        XCTAssertEqual(s.state.usedSinceInstall, before, "도착 시점의 하루치를 소급 적립하지 않는다")
        XCTAssertEqual(s.state.claimedTodayTokens, 40_000_000)

        // 그 다음부터는 정상 적립.
        s.update(todayTokens: 41_000_000, todayDate: today, monthTotal: 0,
                 burnTier: .idle, limitWarning: false, hasUsageData: true)
        XCTAssertEqual(s.state.usedSinceInstall - before, 1_000_000)
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
        s.applySave(try SaveTransfer.decode(data), todayTokens: 1, todayDate: today, hasUsageData: true)

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
        s.applySave(try SaveTransfer.decode(data), todayTokens: 0, todayDate: today, hasUsageData: true)

        let backup = url.deletingPathExtension().appendingPathExtension("pre-import.json")
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
        s.applySave(try SaveTransfer.decode(data), todayTokens: 1,
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
        s.applySave(try SaveTransfer.decode(data), todayTokens: 1,
                    todayDate: "2026-08-03", hasUsageData: true)

        await release.fire()
        await hatching.value

        XCTAssertEqual(s.state.active?.baseID, 403, "종 롤 대기 중 들어온 불러오기를 부화가 덮어쓰면 안 된다")
        XCTAssertEqual(s.state.dex.count, imported.dex.count)
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
        s.applySave(try SaveTransfer.decode(data), todayTokens: 0, todayDate: today, hasUsageData: false)
        XCTAssertFalse(s.state.installBaselineSet, "전제: baseline 판정을 미룬 상태")

        s.update(todayTokens: 0, todayDate: today, monthTotal: 0,
                 burnTier: .idle, limitWarning: false, hasUsageData: false)
        XCTAssertNotNil(s.state.active, "개체는 그대로 있어야 한다")
        XCTAssertEqual(s.displayState, .idle, "개체가 있는데 알로 표시하면 안 된다")

        // 알 상태에서 같은 경로를 타면 여전히 알이어야 한다(반대 방향 고정).
        let eggURL = tempURL("stillegg")
        let e = store(at: eggURL)
        e.update(todayTokens: 0, todayDate: today, monthTotal: 0,
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
        evil.claimedTodayTokens = -42
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
        XCTAssertEqual(s.claimedTodayTokens, 0)
        XCTAssertEqual(s.active?.usedAtStage, SaveTransfer.maxTokenValue)
        XCTAssertEqual(s.active?.totalForms, 12)
        XCTAssertEqual(s.active?.stageIndex, 0, "pathIDs 범위를 넘지 않아야 한다")

        // 정규화된 값으로 실제 산술 경로를 태워 트랩이 안 나는지 확인한다.
        let url = tempURL("clamped")
        let store = store(at: url)
        store.applySave(envelope, todayTokens: 0, todayDate: "2026-08-03", hasUsageData: true)
        XCTAssertGreaterThanOrEqual(store.availableTokens, 0)
        store.update(todayTokens: 1_000, todayDate: "2026-08-03", monthTotal: 0,
                     burnTier: .idle, limitWarning: false, hasUsageData: true)
        XCTAssertLessThanOrEqual(store.state.usedSinceInstall, SaveTransfer.maxTokenValue + 1_000)
    }

    // MARK: 오류 문구 매핑

    /// 매핑이 어긋나면 `SaveTransferError` 는 LocalizedError 가 아니라 "The operation couldn't be
    /// completed. (PokeTokenBar.SaveTransferError error 0.)" 가 그대로 사용자에게 뜬다.
    func testImportErrorMessagesAreLocalizedNotRawSwiftText() {
        for lang in [AppLanguage.ko, .en, .ja] {
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
