import XCTest
import AppKit
@testable import PokeTokenBar

final class EggStyleByRarityTests: XCTestCase {

    // MARK: - Cache Keys & URLs

    func testEggCacheKeysByRarity() {
        XCTAssertEqual(SpriteStore.eggCacheKey(rarity: .common), "egg-common")
        XCTAssertEqual(SpriteStore.eggCacheKey(rarity: .uncommon), "egg-uncommon")
        XCTAssertEqual(SpriteStore.eggCacheKey(rarity: .rare), "egg-rare")
        XCTAssertEqual(SpriteStore.eggCacheKey(rarity: .legendary), "egg-legendary")
    }

    func testEggURLsByRarity() {
        XCTAssertEqual(
            SpriteStore.eggURL(rarity: .common)?.absoluteString,
            "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/items/lucky-egg.png"
        )
        XCTAssertEqual(
            SpriteStore.eggURL(rarity: .uncommon)?.absoluteString,
            "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/egg.png"
        )
        XCTAssertEqual(
            SpriteStore.eggURL(rarity: .rare)?.absoluteString,
            "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/egg-manaphy.png"
        )
        XCTAssertNil(SpriteStore.eggURL(rarity: .legendary), "Legendary egg is embedded locally without network dependency")
    }

    // MARK: - Embedded Egg Assets

    func testEmbeddedEggData() {
        guard let legData = SpriteStore.legendaryEggData else {
            XCTFail("legendaryEggData must not be nil")
            return
        }
        let legImg = NSImage(data: legData)
        XCTAssertNotNil(legImg, "legendaryEggData must decode into a valid NSImage")

        guard let commonData = SpriteStore.commonEggData else {
            XCTFail("commonEggData fallback must not be nil")
            return
        }
        let commonImg = NSImage(data: commonData)
        XCTAssertNotNil(commonImg, "commonEggData must decode into a valid NSImage")
    }

    // MARK: - SpriteView Task Identity

    func testFrameTaskIDDistinguishesEggRarityWhenSpeciesIsNil() {
        let commonID = SpriteView.frameTaskID(speciesID: nil, eggRarity: .common, shiny: false, floor: 0)
        let uncommonID = SpriteView.frameTaskID(speciesID: nil, eggRarity: .uncommon, shiny: false, floor: 0)
        let rareID = SpriteView.frameTaskID(speciesID: nil, eggRarity: .rare, shiny: false, floor: 0)
        let legendaryID = SpriteView.frameTaskID(speciesID: nil, eggRarity: .legendary, shiny: false, floor: 0)

        XCTAssertNotEqual(commonID, uncommonID)
        XCTAssertNotEqual(uncommonID, rareID)
        XCTAssertNotEqual(rareID, legendaryID)
    }

    func testFrameTaskIDIgnoresEggRarityWhenSpeciesIsPresent() {
        let pikachuCommon = SpriteView.frameTaskID(speciesID: 25, eggRarity: .common, shiny: false, floor: 0)
        let pikachuLegendary = SpriteView.frameTaskID(speciesID: 25, eggRarity: .legendary, shiny: false, floor: 0)

        XCTAssertEqual(pikachuCommon, pikachuLegendary)
    }

    // MARK: - SpriteSubject Transitions

    func testSpriteSubjectTransitions() {
        let dummyImage = NSImage()
        let subject = SpriteSubject(image: nil, loadedID: nil)
        let applied = subject.applyingEgg(dummyImage, rarity: .rare, cancelled: false)

        XCTAssertNotNil(applied)
        XCTAssertEqual(applied?.loadedEggRarity, .rare)
        XCTAssertNil(applied?.loadedID)

        let switched = applied?.becomingEgg(cachedEgg: dummyImage, rarity: .legendary)
        XCTAssertEqual(switched?.loadedEggRarity, .legendary)
    }
}
