import XCTest
@testable import PokeDexBar

final class SpriteSourceTests: XCTestCase {
    func testAnimatedURLs() {
        XCTAssertEqual(SpriteStore.spriteURL(slug: "pikachu", animated: true, shiny: false)?.absoluteString,
                       "https://play.pokemonshowdown.com/sprites/ani/pikachu.gif")
        XCTAssertEqual(SpriteStore.spriteURL(slug: "pikachu", animated: true, shiny: true)?.absoluteString,
                       "https://play.pokemonshowdown.com/sprites/ani-shiny/pikachu.gif")
    }

    func testStaticURLs() {
        XCTAssertEqual(SpriteStore.spriteURL(slug: "mew", animated: false, shiny: false)?.absoluteString,
                       "https://play.pokemonshowdown.com/sprites/gen5/mew.png")
        XCTAssertEqual(SpriteStore.spriteURL(slug: "mew", animated: false, shiny: true)?.absoluteString,
                       "https://play.pokemonshowdown.com/sprites/gen5-shiny/mew.png")
    }

    /// 캐시 키는 종 번호 기반을 유지한다 — 슬러그가 바뀌어도 기존 캐시가 무효화되지 않게.
    func testCacheKeyStaysNumeric() {
        XCTAssertEqual(SpriteStore.cacheKey(speciesID: 25, animated: true, shiny: false), "25-a")
        XCTAssertEqual(SpriteStore.cacheKey(speciesID: 25, animated: true, shiny: true), "25-sha")
    }
}
