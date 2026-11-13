import XCTest
@testable import PokeTokenBar

/// The Pokédex detail page shows the evolution line of the selected individual.
@MainActor
final class DexDetailEvolutionLineTests: XCTestCase {
    func testFinishedIndividualShowsItsChainEndingOnThisPage() {
        XCTAssertEqual(PokemonDetailView.evolutionLineItems(chainOrder: [1, 2, 3], speciesID: 3, activeLine: nil), [
            EvoLineItem(.species(1), .done),
            EvoLineItem(.species(2), .done),
            EvoLineItem(.species(3), .current),
        ])
    }

    func testIndividualBeingRaisedShowsTheHomeLine() {
        let home = [EvoLineItem(.species(1), .done), EvoLineItem(.species(2), .current),
                    EvoLineItem(.species(3), .future)]
        XCTAssertEqual(PokemonDetailView.evolutionLineItems(chainOrder: [1, 2], speciesID: 2, activeLine: home), home)
    }

    func testIndividualBeingRaisedFallsBackToItsPathBeforeTheLineLoads() {
        XCTAssertEqual(PokemonDetailView.evolutionLineItems(chainOrder: [1, 2], speciesID: 2, activeLine: []), [
            EvoLineItem(.species(1), .done),
            EvoLineItem(.species(2), .current),
        ])
    }

    func testSingleStageLineIsHidden() {
        XCTAssertEqual(PokemonDetailView.evolutionLineItems(chainOrder: [144], speciesID: 144, activeLine: nil), [])
        XCTAssertEqual(PokemonDetailView.evolutionLineItems(
            chainOrder: [144], speciesID: 144, activeLine: [EvoLineItem(.species(144), .current)]), [])
    }
}
