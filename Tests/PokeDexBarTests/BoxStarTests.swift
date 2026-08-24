import XCTest
@testable import PokeDexBar

/// 별표 — 즐겨찾기 겸 보호(포켓몬 GO 규칙). 별표한 개체는 박사에게 보낼 수 없다.
@MainActor
final class BoxStarTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeStore() -> PlayerStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("star-\(UUID().uuidString).json")
        return PlayerStore(fileURL: url, rng: SeededRNG(seed: 1), now: { self.now })
    }

    private func make(starred: Bool = false, species: Int = 1) -> Individual {
        Individual(baseID: species, speciesID: species, pathIDs: [species],
                   starred: starred, nature: .hardy, obtainedAt: now, grade: .common)
    }

    // MARK: 보호

    /// **별표면 보낼 수 없다.** 판정은 `releaseValue` 하나 — 단건·대량·선택 모드 셀 판정이
    /// 전부 이걸 읽으므로, 여기 하나로 모든 경로가 막힌다.
    func testAStarredIndividualCannotBeSent() {
        let store = makeStore()
        let starred = make(starred: true)
        let plain = make(species: 4)
        store.mutate { $0.box.append(contentsOf: [starred, plain]) }

        XCTAssertNil(store.releaseValue(starred), "별표인데 보내기 값이 나온다")
        XCTAssertNotNil(store.releaseValue(plain), "별표가 아닌데도 막혔다 — 가드가 뒤집혔다")

        // 단건 — 거부되고 박스가 그대로다.
        XCTAssertNil(store.releaseToProfessor(individualID: starred.id))
        XCTAssertTrue(store.state.box.contains { $0.id == starred.id }, "별표한 개체가 사라졌다")
        XCTAssertEqual(store.state.researchPoints, 0, "보내지도 않았는데 포인트가 들어왔다")
    }

    /// 대량 보내기 — 별표는 건너뛰고 나머지만 나간다.
    func testBulkSendSkipsStarredAndSendsTheRest() {
        let store = makeStore()
        let starred = make(starred: true)
        let a = make(species: 4), b = make(species: 7)
        store.mutate { $0.box.append(contentsOf: [starred, a, b]) }

        let points = store.releaseManyToProfessor(individualIDs: [starred.id, a.id, b.id])
        XCTAssertGreaterThan(points, 0, "아무도 안 나갔다")
        XCTAssertTrue(store.state.box.contains { $0.id == starred.id }, "별표한 개체가 나갔다")
        XCTAssertFalse(store.state.box.contains { $0.id == a.id })
        XCTAssertFalse(store.state.box.contains { $0.id == b.id })
    }

    /// 토글 — 켜고, 끄면 다시 보낼 수 있다. "해제해야만 보낼 수 있다" 의 양방향이다.
    func testTogglingTheStarRestoresSendability() {
        let store = makeStore()
        let individual = make()
        store.mutate { $0.box.append(individual) }
        XCTAssertNotNil(store.releaseValue(store.state.box[0]))

        store.toggleStar(individualID: individual.id)
        XCTAssertTrue(store.state.box[0].starred)
        XCTAssertNil(store.releaseValue(store.state.box[0]))

        store.toggleStar(individualID: individual.id)
        XCTAssertFalse(store.state.box[0].starred)
        XCTAssertNotNil(store.releaseValue(store.state.box[0]), "해제했는데 여전히 못 보낸다")
    }

    /// 선택 모드에서 별표 칸은 못 고른다 — 셀 판정이 `releaseValue` 를 읽으므로 자동이다.
    func testAStarredCellIsNotPickableInSelectionMode() {
        XCTAssertEqual(BoxTabView.cellTap(selecting: true, isPickable: false), .ignore)
        XCTAssertEqual(BoxTabView.cellTap(selecting: false, isPickable: false), .openDetail,
                       "모드 밖에서는 별표여도 상세가 열려야 한다")
    }

    // MARK: 저장

    /// **별표 키가 없는 기존 세이브가 그대로 열린다** — 관대 디코딩 규칙.
    func testAnOldSaveWithoutTheKeyDecodesUnstarred() throws {
        let json = """
        {"baseID": 1, "speciesID": 1, "nature": "hardy", "grade": "common"}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(Individual.self, from: json)
        XCTAssertFalse(decoded.starred)
    }

    /// 별표가 저장을 오간다 — 만들고 저장을 빼먹는 부류를 잠근다.
    func testTheStarSurvivesARoundTrip() throws {
        var individual = make()
        individual.starred = true
        let data = try JSONEncoder().encode(individual)
        let back = try JSONDecoder().decode(Individual.self, from: data)
        XCTAssertTrue(back.starred, "별표가 저장에서 사라진다")
    }

    // MARK: 정렬

    /// 별표 먼저 — 동률은 획득순(기존 규칙 그대로).
    func testSortPutsStarredFirst() {
        let old = Individual(baseID: 1, speciesID: 1, pathIDs: [1], nature: .hardy,
                             obtainedAt: now.addingTimeInterval(-100), grade: .common)
        let starredNew = Individual(baseID: 4, speciesID: 4, pathIDs: [4], starred: true,
                                    nature: .hardy, obtainedAt: now, grade: .common)
        let starredOld = Individual(baseID: 7, speciesID: 7, pathIDs: [7], starred: true,
                                    nature: .hardy, obtainedAt: now.addingTimeInterval(-50),
                                    grade: .common)
        let sorted = BoxSort.starred.apply(to: [old, starredNew, starredOld], at: now)
        XCTAssertEqual(sorted.map(\.speciesID), [7, 4, 1],
                       "별표가 앞으로 안 온다(동률은 획득순): \(sorted.map(\.speciesID))")
    }

    /// 정렬 메뉴에 실제로 떠 있고, 세 언어 라벨이 있다.
    func testStarredSortIsInTheMenuWithLabels() {
        XCTAssertTrue(BoxSort.allCases.contains(.starred))
        for lang in AppLanguage.allCases {
            XCTAssertFalse(BoxSort.starred.label(lang).isEmpty)
        }
    }
}
