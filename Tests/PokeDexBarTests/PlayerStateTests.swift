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

    /// 신규 설치 기본 언어는 시스템 로케일에서 유추 — 유효한 케이스이고 크래시 없음(한국어 강제 아님).
    func testSystemDefaultLanguageResolves() {
        XCTAssertTrue(AppLanguage.allCases.contains(AppLanguage.systemDefault))
        XCTAssertEqual(PlayerState().language, AppLanguage.systemDefault)
    }

    /// 박스 원소 하나가 깨져도(2b 에서 필드가 느는 시점 등) 나머지 개체는 살아남는다 — 배열을
    /// 통째로 디코드하면 이 한 원소 때문에 박스 전체가 빈 채로 떨어진다(all-or-nothing 회귀).
    func testLossyBoxDecodeKeepsGoodIndividualAndDropsMalformedOne() throws {
        let goodID = UUID()
        let json = """
        {"starterChosen":true,"box":[
          {"id":"\(goodID.uuidString)","baseID":1,"speciesID":1,"pathIDs":[1],"shiny":false,
           "nature":"serious","exp":0,"obtainedAt":0,"grade":"common"},
          {"id":"not-a-uuid","baseID":"not-a-number"}
        ]}
        """
        let s = try JSONDecoder().decode(PlayerState.self, from: Data(json.utf8))
        XCTAssertEqual(s.box.count, 1, "깨진 원소 하나 때문에 박스 전체가 비면 안 된다")
        XCTAssertEqual(s.box.first?.id, goodID)
    }

    /// 알 원소 하나가 깨져도 나머지 부화 중인 알은 살아남는다 — box 와 같은 이유의
    /// 원소 단위 관대 디코딩(all-or-nothing 회귀 방지).
    func testLossyEggsDecodeKeepsGoodEggAndDropsMalformedOne() throws {
        let goodID = UUID()
        let json = """
        {"starterChosen":true,"eggs":[
          {"id":"\(goodID.uuidString)","grade":"common","speciesID":1,"shiny":false,
           "startedAt":0,"hatchesAt":1800},
          {"id":"not-a-uuid","grade":"not-a-grade"}
        ]}
        """
        let s = try JSONDecoder().decode(PlayerState.self, from: Data(json.utf8))
        XCTAssertEqual(s.eggs.count, 1, "깨진 알 하나 때문에 eggs 전체가 비면 안 된다")
        XCTAssertEqual(s.eggs.first?.id, goodID)
    }

    // MARK: 신뢰경계 값 범위 검증 (관대 디코딩의 짝)

    private func decodeEgg(startedAt: String, hatchesAt: String) throws -> Egg {
        let json = """
        {"eggs":[{"id":"\(UUID().uuidString)","grade":"common","speciesID":1,"shiny":false,
         "startedAt":\(startedAt),"hatchesAt":\(hatchesAt)}]}
        """
        let s = try JSONDecoder().decode(PlayerState.self, from: Data(json.utf8))
        return try XCTUnwrap(s.eggs.first, "수치가 이상해도 알을 버리면 안 된다 — 자르기만 한다")
    }

    /// 터무니없는 부화 시각은 디코드에 *성공*하므로(`load()` 의 손상 복구가 안 뜬다) 여기서 잘라야 한다.
    /// 안 자르면 카운트다운의 `Int(remaining.rounded(.up))` 이 변환 트랩으로 프로세스를 죽이고,
    /// 재기동해도 같은 파일을 다시 읽어 또 죽는다.
    func testDecodeClampsAbsurdHatchDate() throws {
        let egg = try decodeEgg(startedAt: "0", hatchesAt: "1e300")
        let remaining = egg.remaining(at: Date(timeIntervalSinceReferenceDate: 0))
        XCTAssertLessThanOrEqual(remaining, EggBalance.duration(.legendary),
                                 "부화는 아무리 늦어도 시작 + 최장 등급 시간이다")
        // 잘린 값이면 카운트다운 표기가 트랩 없이 만들어진다(결함 재현 경로 그대로).
        XCTAssertFalse(EggSlotsView.countdownText(remaining, .ko).isEmpty)
    }

    /// 시작 시각도 같은 이유로 자른다 — 시작이 터무니없으면 부화도 따라간다.
    func testDecodeClampsAbsurdStartDate() throws {
        let egg = try decodeEgg(startedAt: "1e300", hatchesAt: "1e300")
        XCTAssertTrue(egg.startedAt.timeIntervalSince1970.isFinite)
        XCTAssertLessThan(egg.startedAt, Date(timeIntervalSince1970: 7_258_118_401))
        XCTAssertLessThanOrEqual(egg.hatchesAt.timeIntervalSince(egg.startedAt),
                                 EggBalance.duration(.legendary))
    }

    /// 부화 시각이 시작보다 이를 수는 없다(음수 시각으로 저장된 손상분).
    func testDecodeClampsHatchDateBeforeStart() throws {
        let egg = try decodeEgg(startedAt: "1800", hatchesAt: "-1e300")
        XCTAssertGreaterThanOrEqual(egg.hatchesAt, egg.startedAt)
    }

    /// 멀쩡한 알은 손대지 않는다 — 자르기가 정상 저장분을 흔들면 안 된다.
    func testDecodeLeavesValidEggDatesAlone() throws {
        let egg = try decodeEgg(startedAt: "0", hatchesAt: "1800")
        XCTAssertEqual(egg.startedAt, Date(timeIntervalSinceReferenceDate: 0))
        XCTAssertEqual(egg.hatchesAt, Date(timeIntervalSinceReferenceDate: 1800))
    }

    /// `"slots": 0` 은 디코드에 성공하고 경제를 영구히 잠근다 — freeSlots 0 이라 다시는 못 뽑는데
    /// 상점은 "최대까지 늘렸어요"라고 말한다(nextSlotPrice 가 nil). 경계에서 자른다.
    /// 하한은 기본 슬롯(3) — 1·2 로 자르면 뽑기는 되살아나도 가격표(`slotPrice` 는 4~6 만 매긴다)가
    /// 다시 안 이어져 상점의 거짓말이 남는다.
    func testDecodeClampsSlotsIntoBuyableRange() throws {
        func slots(_ raw: String) throws -> Int {
            try JSONDecoder().decode(PlayerState.self, from: Data(#"{"slots":\#(raw)}"#.utf8)).slots
        }
        XCTAssertEqual(try slots("0"), EggBalance.baseSlots)
        XCTAssertEqual(try slots("2"), EggBalance.baseSlots)
        XCTAssertEqual(try slots("-5"), EggBalance.baseSlots)
        XCTAssertEqual(try slots("9999"), EggBalance.maxSlots)
        XCTAssertEqual(try slots("4"), 4, "정상 범위는 그대로")
    }

    /// 잘린 슬롯으로 ① 다시 뽑을 수 있고 ② 상점이 "최대까지 늘렸어요"라고 거짓말하지 않아야 한다.
    /// ②는 `PlayerStore.nextSlotPrice` 가 그대로 위임하는 `EggBalance.slotPrice` 로 확인한다.
    func testClampedSlotsRestoreDrawingAndTheSlotPriceTable() throws {
        for raw in ["0", "2"] {
            var state = try JSONDecoder().decode(PlayerState.self, from: Data(#"{"slots":\#(raw)}"#.utf8))
            state.earnedTokens = EggBalance.drawPrice
            XCTAssertGreaterThan(state.slots - state.eggs.count, 0, "slots: \(raw) — 빈 슬롯이 없으면 영영 못 뽑는다")
            XCTAssertGreaterThanOrEqual(state.wallet, EggBalance.drawPrice)
            XCTAssertNotNil(EggBalance.slotPrice(forSlotNumber: state.slots + 1),
                            "slots: \(raw) — 다음 슬롯 값이 없으면 상점이 '최대까지 늘렸어요'라고 거짓말한다")
        }
    }
}
