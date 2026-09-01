import XCTest
@testable import PokeDexBar

/// 쓰다듬기 — 펫을 길게 누르면 파트너와 함께한 시간이 쌓인다(숨은 조작).
@MainActor
final class PettingTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeStore() -> (PlayerStore, Individual) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pet-\(UUID().uuidString).json")
        let store = PlayerStore(fileURL: url, rng: SeededRNG(seed: 1), now: { self.now })
        let partner = Individual(baseID: 25, speciesID: 25, pathIDs: [25], nature: .hardy,
                                 obtainedAt: now, grade: .common)
        store.mutate { s in
            s.box = [partner]
            s.partnerID = partner.id
        }
        return (store, partner)
    }

    // MARK: 클릭과의 경계

    /// **짧게 누르면 아무 일도 없다** — 클릭(팝오버 열기)과 연타(폼 깨기)를 뺏으면 안 된다.
    func testAShortPressIsStillJustAClick() {
        XCTAssertEqual(Petting.earnedSeconds(held: 0), 0)
        XCTAssertEqual(Petting.earnedSeconds(held: 0.2), 0)
        XCTAssertEqual(Petting.earnedSeconds(held: Petting.holdThreshold - 0.01), 0)
    }

    /// 문턱 **바로 위**에서 값이 튀지 않는다 — 문턱을 뺀 만큼만 세기 때문이다.
    /// 안 그러면 0.5초에서 90초가 한꺼번에 붙어 클릭과 쓰다듬기의 경계가 불연속이 된다.
    func testTheRateIsContinuousAtTheThreshold() {
        XCTAssertEqual(Petting.earnedSeconds(held: Petting.holdThreshold), 0)
        XCTAssertEqual(Petting.earnedSeconds(held: Petting.holdThreshold + 0.01), 1)
    }

    /// 1초 쓰다듬으면 3분(사용자 결정).
    func testOneSecondIsThreeMinutes() {
        XCTAssertEqual(Petting.earnedSeconds(held: Petting.holdThreshold + 1), 180)
        XCTAssertEqual(Petting.earnedSeconds(held: Petting.holdThreshold + 10), 1800)
    }

    // MARK: 실제 적립

    /// 함께한 시간이 실제로 늘고, **리본도 같이 앞당겨진다** — 둘 다
    /// `partnerDuration` 에서 파생되므로 한 곳만 늘리면 따라와야 한다.
    func testPettingAdvancesBothTimeAndRibbon() {
        let (store, partner) = makeStore()
        XCTAssertNil(store.state.box[0].ribbon(at: now), "처음엔 리본이 없다")

        // 인연 리본(1일)까지 필요한 만큼 쓰다듬는다.
        let needed = Ribbon.bond.requiredPartnerSeconds
        let held = Petting.holdThreshold + Double(needed) / Petting.secondsPerSecondHeld
        let gained = store.petPartner(heldFor: held)

        XCTAssertGreaterThanOrEqual(gained, needed)
        XCTAssertEqual(store.state.box[0].partnerDuration(at: now), gained)
        XCTAssertEqual(store.state.box[0].ribbon(at: now), .bond, "리본이 안 따라왔다")
        XCTAssertEqual(store.state.box[0].id, partner.id)
    }

    /// **리본 문턱 자체는 안 건드린다** — 문턱을 낮추면 사탕 생산 속도와 채집 확률까지 밀린다.
    func testTheRibbonLadderItselfIsUnchanged() {
        let (store, _) = makeStore()
        store.petPartner(heldFor: 100)
        XCTAssertEqual(Ribbon.bond.requiredPartnerSeconds, 86_400)
        XCTAssertEqual(Ribbon.lifelong.requiredPartnerSeconds, 90 * 86_400)
    }

    /// 짧게 누르면 시간도 안 붙고 **하트 박자도 안 오른다**(화면이 헛하트를 띄우면 안 된다).
    func testAShortPressAddsNothingAndBeatsNothing() {
        let (store, _) = makeStore()
        let before = store.pettedBeat
        XCTAssertEqual(store.petPartner(heldFor: 0.2), 0)
        XCTAssertEqual(store.state.box[0].partnerSeconds, 0)
        XCTAssertEqual(store.pettedBeat, before, "안 쓰다듬었는데 하트가 떴다")
    }

    /// 쓰다듬으면 하트 박자가 오른다.
    func testPettingRaisesTheHeartBeat() {
        let (store, _) = makeStore()
        let before = store.pettedBeat
        XCTAssertGreaterThan(store.petPartner(heldFor: 2), 0)
        XCTAssertEqual(store.pettedBeat, before + 1)
    }

    /// 파트너가 없으면 아무 일도 없다(크래시하지 않는다).
    func testPettingWithNoPartnerDoesNothing() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pet-none-\(UUID().uuidString).json")
        let store = PlayerStore(fileURL: url, rng: SeededRNG(seed: 1), now: { self.now })
        XCTAssertEqual(store.petPartner(heldFor: 5), 0)
        XCTAssertEqual(store.pettedBeat, 0)
    }

    /// 쓰다듬은 시간은 **진행 중인 구간과 더해진다** — 곁에 둔 채로 쓰다듬어도
    /// 한쪽이 다른 쪽을 덮어쓰지 않는다.
    func testPettingAddsOnTopOfTheOpenStint() {
        let (store, _) = makeStore()
        store.mutate { $0.box[0].partnerSince = self.now.addingTimeInterval(-3600) }
        store.petPartner(heldFor: Petting.holdThreshold + 1)   // +180초
        XCTAssertEqual(store.state.box[0].partnerDuration(at: now), 3600 + 180)
    }

    /// 쓰다듬기는 저장된다 — 껐다 켜도 남아야 리본이 도로 내려가지 않는다.
    func testPettingSurvivesAReload() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pet-reload-\(UUID().uuidString).json")
        let store = PlayerStore(fileURL: url, rng: SeededRNG(seed: 1), now: { self.now })
        let partner = Individual(baseID: 25, speciesID: 25, pathIDs: [25], nature: .hardy,
                                 obtainedAt: now, grade: .common)
        store.mutate { s in s.box = [partner]; s.partnerID = partner.id }
        store.petPartner(heldFor: Petting.holdThreshold + 10)   // +1800초

        let back = PlayerStore(fileURL: url, rng: SeededRNG(seed: 1), now: { self.now })
        XCTAssertEqual(back.state.box.first?.partnerSeconds, 1800)
    }
}
