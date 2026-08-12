import XCTest
@testable import PokeDexBar

final class StarterCatalogTests: XCTestCase {
    func testNineGenerationsOfThree() {
        XCTAssertEqual(StarterCatalog.byGeneration.count, 9)
        XCTAssertEqual(StarterCatalog.all.count, 27)
        for entry in StarterCatalog.byGeneration {
            XCTAssertEqual(entry.speciesIDs.count, 3, "\(entry.generation)세대 스타터가 3마리가 아니다")
        }
    }

    func testKnownStarters() {
        XCTAssertEqual(StarterCatalog.byGeneration.first?.speciesIDs, [1, 4, 7])
        XCTAssertEqual(StarterCatalog.byGeneration.last?.speciesIDs, [906, 909, 912])
        XCTAssertTrue(StarterCatalog.contains(495))
        XCTAssertFalse(StarterCatalog.contains(25))
    }

    /// 스타터는 전부 스프라이트를 그릴 수 있어야 한다 — 못 그리는 칸이 선택지에 있으면 안 된다.
    func testEveryStarterHasASprite() {
        for id in StarterCatalog.all {
            XCTAssertNotNil(SpeciesSlug.slug(id), "종 \(id) 슬러그 없음")
        }
    }
}
