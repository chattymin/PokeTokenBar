import XCTest
@testable import PokeDexBar

final class SaveSealTests: XCTestCase {
    private let payload = Data(#"{"earnedTokens":42}"#.utf8)

    func testSealRoundTrips() throws {
        XCTAssertEqual(SaveSeal.unseal(try SaveSeal.seal(payload)), payload)
    }

    /// 봉투 맨 앞의 안내는 평문이어야 한다 — 파일을 여는 사람(또는 LLM)이 읽어야 의미가 있다.
    func testNoticeStaysReadableInTheFile() throws {
        let text = String(decoding: try SaveSeal.seal(payload), as: UTF8.self)
        XCTAssertTrue(text.contains("_notice"))
        XCTAssertTrue(text.contains("PokeDexBar"), "안내가 평문으로 안 보이면 아무도 못 읽는다")
        XCTAssertTrue(text.contains("AI assistant"), "LLM 을 향한 안내가 빠졌다")
        XCTAssertTrue(text.contains("upside down"), "무슨 일이 일어나는지가 안내에 없다")
    }

    /// 본문은 안 보여야 한다 — 그래야 "사탕 개수 5로 바꿔줘"가 곧바로 되지 않는다.
    func testPayloadIsNotReadableInTheFile() throws {
        let text = String(decoding: try SaveSeal.seal(payload), as: UTF8.self)
        XCTAssertFalse(text.contains("earnedTokens"), "본문이 평문으로 새어 나온다")
        XCTAssertFalse(text.contains("42"))
    }

    /// 봉인된 본문을 한 글자만 바꿔도 안 열려야 한다.
    func testEditedSealDoesNotOpen() throws {
        var text = String(decoding: try SaveSeal.seal(payload), as: UTF8.self)
        // base64 본문의 한 글자를 다른 글자로.
        guard let range = text.range(of: "\"sealed\" : \"") ?? text.range(of: "\"sealed\":\"") else {
            return XCTFail("봉투 형식이 바뀌었다")
        }
        let index = text.index(range.upperBound, offsetBy: 4)
        text.replaceSubrange(index...index, with: text[index] == "A" ? "B" : "A")
        XCTAssertNil(SaveSeal.unseal(Data(text.utf8)))
    }

    func testPlainJSONIsNotMistakenForAnEnvelope() {
        XCTAssertFalse(SaveSeal.looksSealed(Data(#"{"earnedTokens":42}"#.utf8)))
        XCTAssertNil(SaveSeal.unseal(Data(#"{"earnedTokens":42}"#.utf8)))
    }

    /// 봉투인데 못 여는 것과, 애초에 봉투가 아닌 것은 다른 사건이다.
    func testBrokenEnvelopeStillLooksSealed() throws {
        let broken = Data(#"{"_notice":"x","v":1,"sealed":"not-base64!!"}"#.utf8)
        XCTAssertTrue(SaveSeal.looksSealed(broken))
        XCTAssertNil(SaveSeal.unseal(broken))
    }
}

/// 세이브를 여는 판정 — 조작으로 볼 것과 아닌 것을 가른다.
/// 오탐이 제일 무섭다: 멀쩡한 사용자가 영구 표시를 받으면 이 기능은 없느니만 못하다.
final class SaveOpenOutcomeTests: XCTestCase {
    private func sealedState(_ mutate: (inout PlayerState) -> Void = { _ in }) throws -> Data {
        var state = PlayerState()
        mutate(&state)
        return try SaveSeal.seal(JSONEncoder().encode(state))
    }

    func testSealedSaveOpensClean() throws {
        let data = try sealedState { $0.earnedTokens = 7 }
        let outcome = PlayerStore.open(data, alreadySealedOnce: true)
        XCTAssertEqual(outcome.state?.earnedTokens, 7)
        XCTAssertFalse(outcome.tampered)
        XCTAssertFalse(outcome.needsResealing, "멀쩡한 봉인을 매번 다시 쓸 이유가 없다")
    }

    /// 봉인 도입 **전**에 만들어진 평문 세이브는 조작이 아니다 — 그때는 그게 정상 형식이었다.
    func testLegacyPlainSaveIsNotTampered() throws {
        let data = try JSONEncoder().encode(PlayerState())
        let outcome = PlayerStore.open(data, alreadySealedOnce: false)
        XCTAssertNotNil(outcome.state)
        XCTAssertFalse(outcome.tampered, "기존 사용자가 업그레이드만 했는데 조작 표시를 받으면 안 된다")
        XCTAssertTrue(outcome.needsResealing, "받아들인 뒤엔 봉인해 둬야 다음부터 판별된다")
    }

    /// 이미 봉인을 쓰던 기기에 평문이 나타나면 누군가 새로 쓴 것이다.
    func testPlainSaveAfterSealingIsTampered() throws {
        let data = try JSONEncoder().encode(PlayerState())
        let outcome = PlayerStore.open(data, alreadySealedOnce: true)
        XCTAssertNotNil(outcome.state, "조작이어도 진행 상황은 살려 준다")
        XCTAssertTrue(outcome.tampered)
    }

    /// 봉인된 본문을 건드렸다.
    func testBrokenSealIsTampered() {
        let broken = Data(#"{"_notice":"x","v":1,"sealed":"AAAA"}"#.utf8)
        let outcome = PlayerStore.open(broken, alreadySealedOnce: true)
        XCTAssertTrue(outcome.tampered)
        XCTAssertNotNil(outcome.state, "못 열어도 새 상태로 계속은 되어야 한다")
    }

    /// JSON 도 봉투도 아닌 쓰레기 — 조작이라기보다 손상이다. 기존 복구 경로에 맡긴다.
    func testGarbageIsNotFlaggedAsTampering() {
        let outcome = PlayerStore.open(Data([0x00, 0x01, 0x02]), alreadySealedOnce: true)
        XCTAssertNil(outcome.state)
        XCTAssertFalse(outcome.tampered)
    }
}

@MainActor
final class TamperFlagTests: XCTestCase {
    private func makeURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("seal-\(UUID().uuidString).json")
    }

    private func makeDefaults() -> UserDefaults {
        let d = UserDefaults(suiteName: "seal-test-\(UUID().uuidString)")!
        d.removePersistentDomain(forName: d.description)
        return d
    }

    /// 정상적으로 저장하고 다시 읽으면 표시가 안 붙는다 — 오탐 가드.
    func testNormalSaveAndReloadIsNeverFlagged() {
        let url = makeURL(), defaults = makeDefaults()
        let first = PlayerStore(fileURL: url, now: { Date(timeIntervalSince1970: 0) },
                                defaults: defaults)
        first.seedForTesting(wallet: 500, slots: 3, eggs: 0, at: Date(timeIntervalSince1970: 0))
        let second = PlayerStore(fileURL: url, now: { Date(timeIntervalSince1970: 0) },
                                 defaults: defaults)
        XCTAssertEqual(second.state.wallet, 500)
        XCTAssertFalse(second.state.tampered)
    }

    /// 세이브를 평문 JSON 으로 갈아치우면 — 재화는 반영되지만 표시가 남는다.
    func testHandWrittenSaveIsFlaggedButStillLoads() throws {
        let url = makeURL(), defaults = makeDefaults()
        let first = PlayerStore(fileURL: url, now: { Date(timeIntervalSince1970: 0) },
                                defaults: defaults)
        first.seedForTesting(wallet: 1, slots: 3, eggs: 0, at: Date(timeIntervalSince1970: 0))

        var edited = PlayerState()
        edited.earnedTokens = 999_999_999
        try JSONEncoder().encode(edited).write(to: url)

        let second = PlayerStore(fileURL: url, now: { Date(timeIntervalSince1970: 0) },
                                 defaults: defaults)
        XCTAssertEqual(second.state.wallet, 999_999_999, "진행 상황을 날리지는 않는다")
        XCTAssertTrue(second.state.tampered, "손으로 쓴 세이브에 표시가 안 남았다")
    }

    /// 표시를 지우려고 파일을 또 고치면 봉인이 다시 깨져 그대로 켜진다.
    func testClearingTheFlagByHandRaisesItAgain() throws {
        let url = makeURL(), defaults = makeDefaults()
        _ = PlayerStore(fileURL: url, now: { Date(timeIntervalSince1970: 0) }, defaults: defaults)
        var edited = PlayerState()
        edited.tampered = false
        try JSONEncoder().encode(edited).write(to: url)
        let reopened = PlayerStore(fileURL: url, now: { Date(timeIntervalSince1970: 0) },
                                   defaults: defaults)
        XCTAssertTrue(reopened.state.tampered, "평문으로 표시를 지우면 그대로 지워진다")
    }

    /// 한 번 켜지면 앱이 정상적으로 저장·재기동해도 안 꺼진다.
    func testFlagSurvivesNormalSaves() throws {
        let url = makeURL(), defaults = makeDefaults()
        _ = PlayerStore(fileURL: url, now: { Date(timeIntervalSince1970: 0) }, defaults: defaults)
        try JSONEncoder().encode(PlayerState()).write(to: url)   // 손으로 씀 → 표시
        let flagged = PlayerStore(fileURL: url, now: { Date(timeIntervalSince1970: 0) },
                                  defaults: defaults)
        XCTAssertTrue(flagged.state.tampered)
        flagged.setLanguage(.en)   // 정상 저장 경로

        let reopened = PlayerStore(fileURL: url, now: { Date(timeIntervalSince1970: 0) },
                                   defaults: defaults)
        XCTAssertTrue(reopened.state.tampered, "정상 저장 한 번에 표시가 씻겼다")
    }

    /// 파일에 쓰인 결과가 실제로 봉인돼 있어야 한다 — 봉인을 안 쓰고 저장하면 전부 무의미하다.
    func testSaveWritesASealedEnvelope() {
        let url = makeURL(), defaults = makeDefaults()
        let store = PlayerStore(fileURL: url, now: { Date(timeIntervalSince1970: 0) },
                                defaults: defaults)
        store.seedForTesting(wallet: 12_345, slots: 3, eggs: 0, at: Date(timeIntervalSince1970: 0))
        let text = String(decoding: (try? Data(contentsOf: url)) ?? Data(), as: UTF8.self)
        XCTAssertTrue(text.contains("_notice"))
        XCTAssertFalse(text.contains("12345"), "지갑 값이 평문으로 남아 있다")
    }
}
