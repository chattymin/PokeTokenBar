import XCTest
@testable import PokeDexBar

/// 개발 시드 — **세이브를 손으로 고치지 않기 위한** 경로다. 봉인을 우회하는 게 아니라 앱이
/// 스스로 쓰게 해서, 시간으로만 열리는 상태(리본)를 기다리지 않고 확인한다.
final class DevSeedParsingTests: XCTestCase {
    func testParsesEveryRibbonName() {
        let expected: [String: Ribbon] = ["bond": .bond, "trust": .trust,
                                          "kinship": .kinship, "lifelong": .lifelong]
        for (name, ribbon) in expected {
            XCTAssertEqual(DevSeed.parse(["PTB_SEED_RIBBON": name])?.ribbon, ribbon)
        }
        // 리본을 더하면 여기도 같이 늘어야 한다 — 안 그러면 새 리본은 시드로 못 만든다.
        XCTAssertEqual(expected.count, Ribbon.allCases.count)
    }

    func testIsCaseAndWhitespaceTolerant() {
        XCTAssertEqual(DevSeed.parse(["PTB_SEED_RIBBON": "  Lifelong "])?.ribbon, .lifelong)
    }

    /// 환경변수가 없거나 못 알아들으면 **아무것도 안 한다** — 오타 하나로 조용히 엉뚱한
    /// 상태가 만들어지면 시험 결과를 믿을 수 없다.
    func testUnknownOrMissingValuesSeedNothing() {
        XCTAssertNil(DevSeed.parse([:]))
        XCTAssertNil(DevSeed.parse(["PTB_SEED_RIBBON": ""]))
        XCTAssertNil(DevSeed.parse(["PTB_SEED_RIBBON": "best"]))
        XCTAssertNil(DevSeed.parse(["PTB_SEED_SPECIES": "25"]), "종만 있고 리본이 없으면 안 된다")
    }

    func testSpeciesIsOptionalAndNumeric() {
        XCTAssertNil(DevSeed.parse(["PTB_SEED_RIBBON": "bond"])?.speciesID)
        XCTAssertEqual(DevSeed.parse(["PTB_SEED_RIBBON": "bond", "PTB_SEED_SPECIES": "25"])?.speciesID, 25)
        XCTAssertNil(DevSeed.parse(["PTB_SEED_RIBBON": "bond", "PTB_SEED_SPECIES": "피카츄"])?.speciesID)
    }
}

@MainActor
final class DevSeedApplyTests: XCTestCase {
    private var clock = Date(timeIntervalSince1970: 1_000_000)

    private func makeStore(_ species: [Int]) -> (PlayerStore, [UUID]) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("devseed-\(UUID().uuidString).json")
        let store = PlayerStore(fileURL: url, rng: SeededRNG(seed: 1), now: { self.clock })
        let ids = species.map { sp -> UUID in
            let i = Individual(baseID: sp, speciesID: sp, pathIDs: [sp], nature: .serious,
                               obtainedAt: self.clock, grade: .common)
            store.addForTesting(i)
            return i.id
        }
        return (store, ids)
    }

    private func find(_ store: PlayerStore, _ id: UUID) -> Individual {
        store.state.box.first { $0.id == id }!
    }

    /// 종을 지정하면 그 종만 리본을 단다.
    func testSeedingBySpeciesGivesThatSpeciesTheRibbon() {
        let (store, ids) = makeStore([25, 1])
        store.applyDevSeed(DevSeed(ribbon: .lifelong, speciesID: 25))
        XCTAssertEqual(find(store, ids[0]).ribbon(at: clock), .lifelong)
        XCTAssertNil(find(store, ids[1]).ribbon(at: clock), "지정 안 한 종까지 바뀌었다")
    }

    /// 종을 안 주면 지금 파트너에게.
    func testSeedingWithoutSpeciesTargetsThePartner() {
        let (store, ids) = makeStore([25, 1])
        store.setPartner(ids[1])
        store.applyDevSeed(DevSeed(ribbon: .trust, speciesID: nil))
        XCTAssertEqual(find(store, ids[1]).ribbon(at: clock), .trust)
        XCTAssertNil(find(store, ids[0]).ribbon(at: clock))
    }

    /// **기록을 깎지 않는다** — 이미 더 오래 함께한 개체를 낮은 리본으로 시드해도 그대로다.
    func testSeedingNeverReducesAnExistingRecord() {
        let (store, ids) = makeStore([25])
        store.applyDevSeed(DevSeed(ribbon: .lifelong, speciesID: 25))
        store.applyDevSeed(DevSeed(ribbon: .bond, speciesID: 25))
        XCTAssertEqual(find(store, ids[0]).ribbon(at: clock), .lifelong, "반려가 인연으로 깎였다")
    }

    /// 진행 중인 파트너 시간을 이중으로 세지 않는다 — `partnerDuration` 은 지금 붙어 있는
    /// 구간까지 더하므로, 그걸 빼지 않고 문턱을 통째로 대입하면 리본이 한 단계 넘어간다.
    func testOngoingStintIsCountedOnce() {
        let (store, ids) = makeStore([25])
        store.setPartner(ids[0])
        clock = clock.addingTimeInterval(2 * 86_400)      // 이미 이틀 함께
        store.applyDevSeed(DevSeed(ribbon: .trust, speciesID: 25))
        XCTAssertEqual(find(store, ids[0]).partnerDuration(at: clock),
                       Ribbon.trust.requiredPartnerSeconds, "문턱을 정확히 맞춰야 한다")
    }

    /// 대상이 없으면 아무것도 안 한다.
    func testSeedingAnAbsentSpeciesDoesNothing() {
        let (store, ids) = makeStore([25])
        store.applyDevSeed(DevSeed(ribbon: .lifelong, speciesID: 999))
        XCTAssertNil(find(store, ids[0]).ribbon(at: clock))
    }
}
