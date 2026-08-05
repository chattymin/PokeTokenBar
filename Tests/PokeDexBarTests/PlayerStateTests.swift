import XCTest
@testable import PokeDexBar

final class GradeTests: XCTestCase {
    /// 등급 경계는 스펙 표 그대로 — 커먼 ≥121, 레어 46~120, 에픽 ≤45, 레전더리는 전설·환상.
    func testGradeFromCaptureRate() {
        XCTAssertEqual(Grade.from(captureRate: 255, isLegendary: false, isMythical: false), .common)
        XCTAssertEqual(Grade.from(captureRate: 121, isLegendary: false, isMythical: false), .common)
        XCTAssertEqual(Grade.from(captureRate: 120, isLegendary: false, isMythical: false), .rare)
        XCTAssertEqual(Grade.from(captureRate: 46, isLegendary: false, isMythical: false), .rare)
        XCTAssertEqual(Grade.from(captureRate: 45, isLegendary: false, isMythical: false), .epic)
        XCTAssertEqual(Grade.from(captureRate: 3, isLegendary: false, isMythical: false), .epic)
        XCTAssertEqual(Grade.from(captureRate: 3, isLegendary: true, isMythical: false), .legendary)
        XCTAssertEqual(Grade.from(captureRate: 255, isLegendary: false, isMythical: true), .legendary)
    }

    /// 업스트림 Rarity 와의 대응 — uncommon 이 레어, rare 가 에픽이다(이름만 다르고 경계는 같다).
    func testGradeFromRarity() {
        XCTAssertEqual(Grade(rarity: .common), .common)
        XCTAssertEqual(Grade(rarity: .uncommon), .rare)
        XCTAssertEqual(Grade(rarity: .rare), .epic)
        XCTAssertEqual(Grade(rarity: .legendary), .legendary)
    }
}

final class IndividualTests: XCTestCase {
    private func make(path: [Int]) -> Individual {
        Individual(baseID: path.first ?? 1, speciesID: path.last ?? 1, pathIDs: path,
                   nature: .serious, obtainedAt: Date(timeIntervalSince1970: 0), grade: .common)
    }

    func testStageIndexFollowsPath() {
        XCTAssertEqual(make(path: [1]).stageIndex, 0)
        XCTAssertEqual(make(path: [1, 2]).stageIndex, 1)
        XCTAssertEqual(make(path: [1, 2, 3]).stageIndex, 2)
    }

    /// 경로가 비어 있어도(손상 상태) 음수 단계로 새지 않는다.
    func testEmptyPathIsStageZero() {
        XCTAssertEqual(make(path: []).stageIndex, 0)
    }
}

final class PlayerStateTests: XCTestCase {
    private func individual(_ id: UUID) -> Individual {
        Individual(id: id, baseID: 1, speciesID: 1, pathIDs: [1],
                   nature: .serious, obtainedAt: Date(timeIntervalSince1970: 0), grade: .common)
    }

    func testWalletIsEarnedMinusSpent() {
        var s = PlayerState()
        s.earnedTokens = 1_000
        s.spentTokens = 400
        XCTAssertEqual(s.wallet, 600)
    }

    /// 지출이 적립을 넘는 손상 상태에서도 음수로 새지 않는다.
    func testWalletNeverNegative() {
        var s = PlayerState()
        s.earnedTokens = 100
        s.spentTokens = 500
        XCTAssertEqual(s.wallet, 0)
    }

    func testPartnerResolvesFromBox() {
        let id = UUID()
        var s = PlayerState()
        s.box = [individual(UUID()), individual(id)]
        s.partnerID = id
        XCTAssertEqual(s.partner?.id, id)
    }

    /// 파트너가 박스에서 사라졌으면 nil — 매달린 포인터로 크래시하지 않는다.
    func testMissingPartnerIsNil() {
        var s = PlayerState()
        s.partnerID = UUID()
        XCTAssertNil(s.partner)
    }

    func testCodableRoundTrip() throws {
        var s = PlayerState()
        s.starterChosen = true
        s.earnedTokens = 12_345
        s.box = [individual(UUID())]
        s.dex = [1, 4, 7]
        s.slots = 4
        s.inventory = ["expCandy": 2]
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(PlayerState.self, from: data)
        XCTAssertTrue(back.starterChosen)
        XCTAssertEqual(back.earnedTokens, 12_345)
        XCTAssertEqual(back.box.count, 1)
        XCTAssertEqual(back.dex, [1, 4, 7])
        XCTAssertEqual(back.slots, 4)
        XCTAssertEqual(back.inventory["expCandy"], 2)
    }

    /// 필드가 빠진 저장분(형식이 자라는 중)도 기본값으로 읽힌다 — 한 필드 때문에 박스를 날리지 않는다.
    func testLenientDecodeOfMissingFields() throws {
        let json = #"{"starterChosen":true,"earnedTokens":50}"#
        let s = try JSONDecoder().decode(PlayerState.self, from: Data(json.utf8))
        XCTAssertTrue(s.starterChosen)
        XCTAssertEqual(s.earnedTokens, 50)
        XCTAssertEqual(s.slots, 3)
        XCTAssertTrue(s.box.isEmpty)
        XCTAssertTrue(s.dex.isEmpty)
    }
}
