import XCTest
import SwiftUI
@testable import PokeTokenBar

@MainActor
final class TrainerCardTests: XCTestCase {
    func testDeterministicTrainerID() {
        let id1 = TrainerCardData.deterministicTrainerID(from: "RED")
        let id2 = TrainerCardData.deterministicTrainerID(from: "RED")
        XCTAssertEqual(id1, id2)
        XCTAssertEqual(id1.count, 5)

        let idOther = TrainerCardData.deterministicTrainerID(from: "BLUE")
        XCTAssertEqual(idOther.count, 5)
    }

    func testTrainerCardNavigationLifecycle() {
        let nav = PopoverNavigation()
        XCTAssertFalse(nav.showTrainerCard)
        XCTAssertNil(nav.trainerCardPreselectedSpeciesID)

        nav.openTrainerCard(speciesID: 137)
        XCTAssertTrue(nav.showTrainerCard)
        XCTAssertEqual(nav.trainerCardPreselectedSpeciesID, 137)
        XCTAssertFalse(nav.showSettings)

        nav.reset()
        XCTAssertFalse(nav.showTrainerCard)
        XCTAssertNil(nav.trainerCardPreselectedSpeciesID)
        XCTAssertEqual(nav.tab, .home)
    }

    func testTrainerCardDataProps() {
        let card = TrainerCardData(
            trainerName: "Killian",
            trainerID: "12345",
            theme: .celadonNeon,
            pokemonID: 137,
            pokemonName: "Porygon",
            pokemonSubtitle: "RARE · ADAMANT",
            isShiny: true,
            totalTokens: 300_000_000,
            todayTokens: 15_000_000,
            pokedexCount: 50,
            pokedexTotal: 151,
            graduatedCount: 8,
            shinyCount: 2,
            casinoCoins: 1_200
        )

        XCTAssertEqual(card.trainerName, "Killian")
        XCTAssertEqual(card.trainerID, "12345")
        XCTAssertEqual(card.theme, .celadonNeon)
        XCTAssertEqual(card.pokemonID, 137)
        XCTAssertEqual(card.pokemonName, "Porygon")
        XCTAssertEqual(card.pokemonSubtitle, "RARE · ADAMANT")
        XCTAssertTrue(card.isShiny)
        XCTAssertEqual(card.totalTokens, 300_000_000)
        XCTAssertEqual(card.todayTokens, 15_000_000)
        XCTAssertEqual(card.pokedexCount, 50)
        XCTAssertEqual(card.pokedexTotal, 151)
        XCTAssertEqual(card.graduatedCount, 8)
        XCTAssertEqual(card.shinyCount, 2)
        XCTAssertEqual(card.casinoCoins, 1_200)
    }

    func testTrainerCardViewRendersAllThemes() {
        let cardData = TrainerCardData(
            trainerName: "RED",
            trainerID: "00001",
            theme: .classic,
            pokemonID: 25,
            pokemonName: "Pikachu",
            pokemonSubtitle: "BASIC · JOLLY",
            isShiny: false,
            totalTokens: 50_000_000,
            todayTokens: 2_500_000,
            pokedexCount: 30,
            pokedexTotal: 151,
            graduatedCount: 5,
            shinyCount: 1,
            casinoCoins: 800
        )

        for theme in AppThemeKind.allCases {
            let themedData = TrainerCardData(
                trainerName: cardData.trainerName,
                trainerID: cardData.trainerID,
                theme: theme,
                pokemonID: cardData.pokemonID,
                pokemonName: cardData.pokemonName,
                pokemonSubtitle: cardData.pokemonSubtitle,
                isShiny: cardData.isShiny,
                totalTokens: cardData.totalTokens,
                todayTokens: cardData.todayTokens,
                pokedexCount: cardData.pokedexCount,
                pokedexTotal: cardData.pokedexTotal,
                graduatedCount: cardData.graduatedCount,
                shinyCount: cardData.shinyCount,
                casinoCoins: cardData.casinoCoins
            )
            let view = TrainerCardView(data: themedData, l: L(.en))
            let renderer = ImageRenderer(content: view)
            XCTAssertNotNil(renderer.nsImage, "Rendering must succeed for theme \(theme.rawValue)")
        }
    }

    func testTrainerCardLocalizationKeys() {
        for lang in AppLanguage.allCases {
            let l = L(lang)
            XCTAssertFalse(l.trainerCard.isEmpty)
            XCTAssertFalse(l.trainerCardTitle.isEmpty)
            XCTAssertFalse(l.trainerCardCopyImage.isEmpty)
            XCTAssertFalse(l.trainerCardSaveImage.isEmpty)
            XCTAssertFalse(l.trainerCardCopied.isEmpty)
            XCTAssertFalse(l.trainerCardActiveMon.isEmpty)
            XCTAssertFalse(l.trainerCardDexMon.isEmpty)
            XCTAssertFalse(l.trainerCardShiny.isEmpty)
            XCTAssertFalse(l.trainerCardPokemonSource.isEmpty)
            XCTAssertFalse(l.trainerCardCasinoHint.isEmpty)
            XCTAssertFalse(l.trainerCardLifetimeTokens.isEmpty)
            XCTAssertFalse(l.trainerCardTodayTokens.isEmpty)
            XCTAssertFalse(l.trainerCardPokedexLabel.isEmpty)
            XCTAssertFalse(l.trainerCardGraduatedLabel.isEmpty)
            XCTAssertFalse(l.trainerCardShiniesLabel.isEmpty)
            XCTAssertFalse(l.trainerCardCasinoCoinsLabel.isEmpty)
            XCTAssertFalse(l.trainerCardTrainerLabel.isEmpty)
        }
    }
}
