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

    func testSuggestedFileNameCarriesDate() {
        // 2026-08-03 12:00 UTC — 정오라 표준시대가 달라도 날짜 경계를 넘지 않는다(파일명은 로컬 날짜).
        let name = SaveTransfer.suggestedFileName(date: Date(timeIntervalSince1970: 1_785_758_400))
        XCTAssertTrue(name.hasPrefix("PokeTokenBar-Save-"))
        XCTAssertTrue(name.hasSuffix(".json"))
        XCTAssertTrue(name.contains("2026-08-03"), "실제 이름: \(name)")
    }
}
