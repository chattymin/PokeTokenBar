import XCTest
@testable import PokeDexBar

/// 맞으면 깨지는 겉모습 — 따라큐의 탈, 빙큐보의 얼음머리.
@MainActor
final class BrokenFormTests: XCTestCase {
    private func makeStore() -> PlayerStore {
        PlayerStore(fileURL: FileManager.default.temporaryDirectory
                        .appendingPathComponent("broken-\(UUID().uuidString).json"),
                    rng: SeededRNG(seed: 2), now: { Date(timeIntervalSince1970: 0) },
                    defaults: UserDefaults(suiteName: "ptb-broken-\(UUID().uuidString)")!)
    }

    private func make(_ speciesID: Int) -> Individual {
        Individual(baseID: speciesID, speciesID: speciesID, pathIDs: [speciesID], nature: .hardy,
                   obtainedAt: Date(timeIntervalSince1970: 0), grade: .rare)
    }

    /// 깨지면 그 모습으로 그려진다 — 메뉴바·펫·박스·상세가 전부 `spriteForm` 을 지나므로
    /// 이 한 줄이 모든 화면을 정한다.
    func testABrokenFormChangesThePicture() {
        for (species, slug) in [(778, "mimikyu-busted"), (875, "eiscue-noice")] {
            var individual = make(species)
            XCTAssertNil(individual.spriteForm, "\(species) 가 멀쩡한데 다른 모습이다")
            individual.formBroken = true
            XCTAssertEqual(individual.spriteForm, slug)
        }
    }

    /// 두드릴 수 없는 종은 깨진다고 적혀 있어도 모습이 안 바뀐다.
    func testOtherSpeciesNeverBreak() {
        var pikachu = make(25)
        pikachu.formBroken = true
        XCTAssertNil(pikachu.spriteForm)
        XCTAssertFalse(BrokenForm.breaks(speciesID: 25))
        XCTAssertFalse(BrokenForm.breaks(speciesID: nil))
    }

    /// 파트너를 두드리면 깨진다.
    func testTappingThePartnerBreaksIt() {
        let store = makeStore()
        let mimikyu = make(778)
        store.addForTesting(mimikyu)
        store.setPartner(mimikyu.id)

        store.breakPartnerForm()
        XCTAssertEqual(store.state.box.first { $0.id == mimikyu.id }?.formBroken, true)
    }

    /// **파트너가 아닌 아이는 안 깨진다.** 펫은 파트너를 비추므로, 두드린 대상도 파트너여야 한다.
    func testOnlyThePartnerBreaks() {
        let store = makeStore()
        let partner = make(25), mimikyu = make(778)
        store.addForTesting(partner)
        store.addForTesting(mimikyu)
        store.setPartner(partner.id)

        store.breakPartnerForm()
        XCTAssertEqual(store.state.box.first { $0.id == mimikyu.id }?.formBroken, false,
                       "곁에 없는 아이가 깨졌다")
    }

    /// **파트너에서 내려오면 돌아온다.** 그 아이의 배틀이 끝나는 것에 해당한다 —
    /// 빙큐보는 원작에서도 배틀이 끝나면 회복하므로 규칙이 그대로 맞는다.
    func testLeavingTheFieldRestoresIt() {
        let store = makeStore()
        let mimikyu = make(778), other = make(25)
        store.addForTesting(mimikyu)
        store.addForTesting(other)
        store.setPartner(mimikyu.id)
        store.breakPartnerForm()
        XCTAssertEqual(store.state.box.first { $0.id == mimikyu.id }?.formBroken, true)

        store.setPartner(other.id)
        XCTAssertEqual(store.state.box.first { $0.id == mimikyu.id }?.formBroken, false,
                       "곁에서 내려왔는데 안 돌아왔다")
    }

    /// 같은 아이를 다시 지정하는 건 교체가 아니다 — 시계도 안 끊기고 탈도 안 돌아와야 한다.
    func testReselectingTheSamePartnerDoesNotHeal() {
        let store = makeStore()
        let mimikyu = make(778)
        store.addForTesting(mimikyu)
        store.setPartner(mimikyu.id)
        store.breakPartnerForm()

        store.setPartner(mimikyu.id)
        XCTAssertEqual(store.state.box.first { $0.id == mimikyu.id }?.formBroken, true)
    }

    /// **앱을 껐다 켜도 깨진 채로 남는다.** 디코더에 필드를 안 더하면 저장은 되고 읽기만 빠져서
    /// 다시 켤 때마다 탈이 돌아온다 — 이 저장소가 이미 두 번 밟은 부류다.
    func testItStaysBrokenAcrossARestart() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("broken-save-\(UUID().uuidString).json")
        let now = Date(timeIntervalSince1970: 0)
        let defaults = { UserDefaults(suiteName: "ptb-broken-\(UUID().uuidString)")! }
        let store = PlayerStore(fileURL: url, rng: SeededRNG(seed: 2), now: { now },
                                defaults: defaults())
        let mimikyu = make(778)
        store.addForTesting(mimikyu)
        store.setPartner(mimikyu.id)
        store.breakPartnerForm()

        let reloaded = PlayerStore(fileURL: url, rng: SeededRNG(seed: 2), now: { now },
                                   defaults: defaults())
        XCTAssertEqual(reloaded.state.box.first { $0.id == mimikyu.id }?.formBroken, true,
                       "다시 켜니 탈이 돌아와 있다")
    }

    /// 말이 안 되는 값은 경계에서 버린다 — 관대 디코딩의 짝.
    func testABogusBrokenFlagIsDropped() {
        var pikachu = make(25)
        pikachu.formBroken = true
        XCTAssertFalse(pikachu.sanitized().formBroken)
        var mimikyu = make(778)
        mimikyu.formBroken = true
        XCTAssertTrue(mimikyu.sanitized().formBroken)
    }

    /// 두 번 두드려도 저장이 두 번 일어나지 않는다.
    func testBreakingTwiceIsHarmless() {
        let store = makeStore()
        let mimikyu = make(778)
        store.addForTesting(mimikyu)
        store.setPartner(mimikyu.id)
        store.breakPartnerForm()
        store.breakPartnerForm()
        XCTAssertEqual(store.state.box.first { $0.id == mimikyu.id }?.formBroken, true)
    }

    /// 문턱은 한 번보다 커야 한다 — 펫 클릭은 팝오버를 여는 기존 조작이라, 한 번에 깨지면
    /// 팝오버를 열려다 실수로 깨뜨리게 된다.
    func testItTakesMoreThanOneTap() {
        XCTAssertGreaterThan(BrokenForm.tapsToBreak, 1)
    }
}

/// 곁에 두는 것으로 바뀌는 폼 — 돌핀맨과 테라파고스.
@MainActor
final class PartnerFormTests: XCTestCase {
    private func makeStore() -> PlayerStore {
        PlayerStore(fileURL: FileManager.default.temporaryDirectory
                        .appendingPathComponent("pform-\(UUID().uuidString).json"),
                    rng: SeededRNG(seed: 6), now: { Date(timeIntervalSince1970: 0) },
                    defaults: UserDefaults(suiteName: "ptb-pform-\(UUID().uuidString)")!)
    }

    private func make(_ speciesID: Int) -> Individual {
        Individual(baseID: speciesID, speciesID: speciesID, pathIDs: [speciesID], nature: .hardy,
                   obtainedAt: Date(timeIntervalSince1970: 0), grade: .legendary)
    }

    // MARK: 돌핀맨 — 곁에 뒀다 내렸다 할 때마다 번갈아

    /// 원작의 「제로 투 히어로」는 **물러날 때** 발동한다 — 처음 내보낼 때가 아니다.
    func testPalafinTogglesEachTimeItStandsDown() {
        let store = makeStore()
        let palafin = make(964), other = make(25)
        store.addForTesting(palafin)
        store.addForTesting(other)
        func form() -> String? { store.state.box.first { $0.id == palafin.id }?.spriteForm }

        store.setPartner(palafin.id)
        XCTAssertNil(form(), "처음 곁에 뒀는데 벌써 바뀌었다 — 물러나야 바뀐다")

        store.setPartner(other.id)                    // 한 번 물러남
        XCTAssertEqual(form(), "palafin-hero")
        store.setPartner(palafin.id)
        XCTAssertEqual(form(), "palafin-hero", "다시 데려왔다고 풀리면 안 된다")

        store.setPartner(other.id)                    // 두 번째 물러남
        XCTAssertNil(form(), "번갈아 안 바뀐다")
        store.setPartner(palafin.id)
        store.setPartner(other.id)                    // 세 번째
        XCTAssertEqual(form(), "palafin-hero")
    }

    /// **횟수를 담는다.** 뒤집힌 상태를 불리언으로 담으면 저장된 값이 "몇 번 물러났나"가 아니라
    /// "지금 어느 폼인가"가 되어, 규칙을 바꾸는 순간 옛 세이브의 뜻이 달라진다.
    func testItStoresTheCountNotTheForm() {
        let store = makeStore()
        let palafin = make(964), other = make(25)
        store.addForTesting(palafin); store.addForTesting(other)
        store.setPartner(palafin.id); store.setPartner(other.id)
        store.setPartner(palafin.id); store.setPartner(other.id)
        XCTAssertEqual(store.state.box.first { $0.id == palafin.id }?.partnerStintsEnded, 2)
    }

    // MARK: 테라파고스 — 곁에 있으면 테라스탈

    /// 특성 「테라체인지」는 *배틀에 나오면* 발동한다 — 테라스탈 기믹과 별개로 등장이 트리거다.
    func testTerapagosIsTerastalWhileAtYourSide() {
        let store = makeStore()
        let terapagos = make(1024), other = make(25)
        store.addForTesting(terapagos); store.addForTesting(other)
        func form() -> String? { store.state.box.first { $0.id == terapagos.id }?.spriteForm }

        XCTAssertNil(form(), "곁에 없는데 테라스탈이다")
        store.setPartner(terapagos.id)
        XCTAssertEqual(form(), "terapagos-terastal")
        store.setPartner(other.id)
        XCTAssertNil(form(), "곁에서 내려왔는데 안 돌아왔다")
    }

    /// **도구로 연 스텔라가 이긴다.** 원작에서도 스텔라는 테라스탈 폼에서 한 단계 더 간 모습이라,
    /// 곁에 있다고 테라스탈로 되돌아가면 안 된다.
    func testStellarOutranksTerastal() {
        var terapagos = make(1024)
        terapagos.form = "terapagos-stellar"
        terapagos.partnerSince = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(terapagos.spriteForm, "terapagos-stellar")
    }

    /// 스텔라를 여는 도구가 카탈로그에 이어져 있는지 — 파트너가 물어 오는 경로다.
    func testTheStellarShardReachesTerapagos() {
        let items = FormForageCatalog.items(speciesID: 1024, region: nil).map(\.item)
        XCTAssertTrue(items.contains(.stellarTeraShard), "테라파고스가 테라피스를 못 물어온다")
    }
}
