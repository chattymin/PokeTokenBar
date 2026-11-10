import XCTest
@testable import PokeTokenBar

@MainActor
final class HatchRegionFilterTests: XCTestCase {

    private func store(regions: [String]? = nil,
                       pendingHatchID: Int? = nil) throws -> (CompanionStore, UserDefaults) {
        var state = CompanionState()
        state.installBaselineSet = true
        state.pendingHatchID = pendingHatchID
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("hatch-regions-\(UUID()).json")
        try JSONEncoder().encode(state).write(to: url)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "hatch-regions-\(UUID())"))
        if let regions { defaults.set(regions, forKey: CompanionStore.hatchRegionsKey) }
        let s = CompanionStore(fileURL: url, dittoDisguiseRollingEnabled: false, defaults: defaults)
        return (s, defaults)
    }

    // MARK: 기본값 — 켜지 않은 사용자의 동작은 바뀌지 않아야 한다

    func testDefaultsToEveryRegionSoExistingBehaviourIsUnchanged() throws {
        let (s, _) = try store()
        XCTAssertEqual(s.hatchRegions, Set(PokedexRegion.allCases))
        for id in [1, 152, 252, 387, 494, 649] {
            XCTAssertTrue(s.allowsHatching(speciesID: id), "#\(id)")
        }
    }

    func testUnknownStoredValuesAreDroppedAndAnEmptyResultFallsBackToEveryRegion() throws {
        let (s, _) = try store(regions: ["kanto", "atlantis"])
        XCTAssertEqual(s.hatchRegions, [.kanto])

        let (all, _) = try store(regions: ["atlantis"])
        XCTAssertEqual(all.hatchRegions, Set(PokedexRegion.allCases),
                       "후보 0 은 영원히 안 깨지는 알이다 — 전체로 되돌려야 한다")
    }

    // MARK: 필터 자체

    func testOnlySelectedRegionsMayHatch() throws {
        let (s, _) = try store(regions: ["kanto", "sinnoh"])
        XCTAssertTrue(s.allowsHatching(speciesID: 1))      // Kanto 하한
        XCTAssertTrue(s.allowsHatching(speciesID: 151))    // Kanto 상한
        XCTAssertTrue(s.allowsHatching(speciesID: 387))    // Sinnoh 하한
        XCTAssertTrue(s.allowsHatching(speciesID: 493))    // Sinnoh 상한
        XCTAssertFalse(s.allowsHatching(speciesID: 152))   // Johto
        XCTAssertFalse(s.allowsHatching(speciesID: 386))   // Hoenn
        XCTAssertFalse(s.allowsHatching(speciesID: 494))   // Unova
    }

    func testSpeciesOutsideGenOneToFiveNeverHatch() throws {
        let (s, _) = try store()
        XCTAssertFalse(s.allowsHatching(speciesID: 0))
        XCTAssertFalse(s.allowsHatching(speciesID: 650))
    }

    // MARK: 설정 변경

    func testSettingAnEmptySelectionRestoresEveryRegion() throws {
        let (s, d) = try store(regions: ["kanto"])
        s.setHatchRegions([])
        XCTAssertEqual(s.hatchRegions, Set(PokedexRegion.allCases))
        XCTAssertEqual(d.array(forKey: CompanionStore.hatchRegionsKey) as? [String],
                       PokedexRegion.allCases.map(\.rawValue).sorted())
    }

    func testChangingRegionsDiscardsAPreRolledSpeciesThatNoLongerQualifies() throws {
        // 하나(494)를 미리 뽑아둔 상태에서 관동만 남기면, 그 pre-roll 은 버려져야 한다.
        // 안 버리면 설정을 바꿔도 다음 한 번은 옛 선택대로 부화한다.
        let (s, _) = try store(regions: ["unova"], pendingHatchID: 494)
        XCTAssertEqual(s.state.pendingHatchID, 494)
        s.setHatchRegions([.kanto])
        XCTAssertNil(s.state.pendingHatchID)
    }

    func testChangingRegionsKeepsAPreRolledSpeciesThatStillQualifies() throws {
        let (s, _) = try store(regions: ["kanto"], pendingHatchID: 25)
        s.setHatchRegions([.kanto, .johto])
        XCTAssertEqual(s.state.pendingHatchID, 25, "여전히 유효한 pre-roll 까지 버릴 이유는 없다")
    }

    // MARK: 드래프트 (설정 UI)

    func testDraftRefusesToClearTheLastRegion() throws {
        let (s, _) = try store(regions: ["kanto"])
        var draft = HatchRegionDraft(companion: s)
        draft.toggle(.kanto)
        XCTAssertEqual(draft.regions, [.kanto], "마지막 하나는 끌 수 없다")
        draft.toggle(.johto)
        XCTAssertEqual(draft.regions, [.kanto, .johto])
        draft.toggle(.kanto)
        XCTAssertEqual(draft.regions, [.johto])
    }

    func testDraftDoesNotApplyUntilSave() throws {
        let (s, d) = try store(regions: ["kanto", "johto"])
        var draft = HatchRegionDraft(companion: s)
        draft.toggle(.johto)
        XCTAssertTrue(draft.differs(from: s))
        XCTAssertEqual(s.hatchRegions, [.kanto, .johto], "저장 전에는 스토어가 그대로여야 한다")
        draft.save(to: s)
        XCTAssertFalse(draft.differs(from: s))
        XCTAssertEqual(s.hatchRegions, [.kanto])
        XCTAssertEqual(d.array(forKey: CompanionStore.hatchRegionsKey) as? [String], ["kanto"])
    }
}
