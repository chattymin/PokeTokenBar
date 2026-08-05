import XCTest
@testable import PokeDexBar

/// 번들 매핑이 실제로 Showdown 철자와 맞는지 잠근다. 문장부호가 사라지는 종
/// (Nidoran♀·Farfetch'd·Mr. Mime·Ho-Oh·Porygon-Z·Type: Null)이 사고가 잦다.
final class SpeciesSlugTests: XCTestCase {
    func testKnownSlugs() {
        XCTAssertEqual(SpeciesSlug.slug(1), "bulbasaur")
        XCTAssertEqual(SpeciesSlug.slug(6), "charizard")
        XCTAssertEqual(SpeciesSlug.slug(29), "nidoranf")
        XCTAssertEqual(SpeciesSlug.slug(32), "nidoranm")
        XCTAssertEqual(SpeciesSlug.slug(83), "farfetchd")
        XCTAssertEqual(SpeciesSlug.slug(122), "mrmime")
        XCTAssertEqual(SpeciesSlug.slug(250), "hooh")
        XCTAssertEqual(SpeciesSlug.slug(474), "porygonz")
        XCTAssertEqual(SpeciesSlug.slug(772), "typenull")
    }

    /// 9세대까지 빠짐없이 들어 있어야 한다 — 이게 이번 포크의 목적이다.
    func testCoversEveryGeneration() {
        XCTAssertEqual(SpeciesSlug.slug(908), "meowscarada")
        XCTAssertEqual(SpeciesSlug.slug(1025), "pecharunt")
        for id in 1...1025 {
            XCTAssertNotNil(SpeciesSlug.slug(id), "종 \(id) 슬러그 없음")
        }
    }

    /// 폼(메가·리전폼)이 기본 폼 자리를 덮으면 안 된다 — 리자몽이 charizard-gmax가 되던 사고.
    func testBaseFormsOnly() {
        for id in 1...1025 {
            XCTAssertFalse(SpeciesSlug.slug(id)!.contains("-"),
                           "종 \(id) 이 폼 슬러그다: \(SpeciesSlug.slug(id)!)")
        }
    }

    func testUnknownIDIsNil() {
        XCTAssertNil(SpeciesSlug.slug(0))
        XCTAssertNil(SpeciesSlug.slug(9999))
    }
}
