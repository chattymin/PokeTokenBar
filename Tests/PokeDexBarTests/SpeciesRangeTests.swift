import XCTest
@testable import PokeDexBar

final class SpeciesRangeTests: XCTestCase {
    /// 9세대까지가 부화 풀에 들어와야 한다.
    func testRangeCoversGenNine() {
        XCTAssertEqual(PokemonAssets.speciesIDs, 1...1025)
        XCTAssertTrue(PokemonAssets.hasSprite(speciesID: 906))
        XCTAssertTrue(PokemonAssets.hasSprite(speciesID: 1025))
    }

    func testOutOfRangeIsRejected() {
        XCTAssertFalse(PokemonAssets.hasSprite(speciesID: 0))
        XCTAssertFalse(PokemonAssets.hasSprite(speciesID: 1026))
    }

    /// 진화 트리 필터는 범위 밖 종만 잘라낸다 — 9세대 체인은 온전히 남아야 한다.
    func testEvolutionTreeKeepsGenNineChain() {
        let tree = EvoNode(speciesID: 906, children: [
            EvoNode(speciesID: 907, children: [EvoNode(speciesID: 908, children: [])]),
        ])
        let kept = tree.keepingSupportedSpecies()
        XCTAssertEqual(kept?.speciesID, 906)
        XCTAssertEqual(kept?.finalIDs, [908])
    }
}
