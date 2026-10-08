import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

final class PokemonTypeColorTests: XCTestCase {
    private func hex(_ color: Color) -> UInt32? {
        guard let c = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        let r = UInt32((c.redComponent * 255).rounded())
        let g = UInt32((c.greenComponent * 255).rounded())
        let b = UInt32((c.blueComponent * 255).rounded())
        return (r << 16) | (g << 8) | b
    }

    private func color(_ apiName: String) -> Color { BadgeTint.type(PokemonType(apiName: apiName)).color }

    func testKnownTypesUseClassicTypeChartColors() {
        XCTAssertEqual(hex(color("fire")), 0xFF4422)
        XCTAssertEqual(hex(color("water")), 0x3399FF)
        XCTAssertEqual(hex(color("fairy")), 0xEE99EE)
    }

    func testEnumCoversAllEighteenMainSeriesTypes() {
        let types = ["normal", "fire", "water", "electric", "grass", "ice", "fighting", "poison", "ground",
                     "flying", "psychic", "bug", "rock", "ghost", "dragon", "dark", "steel", "fairy"]
        XCTAssertEqual(Set(PokemonType.allCases.map(\.rawValue)), Set(types))
    }

    func testLookupIsCaseInsensitive() {
        XCTAssertEqual(hex(color("Electric")), 0xFFCC33)
        XCTAssertEqual(hex(color("GRASS")), 0x77CC55)
    }

    func testUnknownTypesFallBackToGray() {
        for type in ["stellar", "shadow", "unknown", ""] {
            XCTAssertNil(PokemonType(apiName: type), type)
            XCTAssertEqual(color(type), .gray, type)
        }
    }
}
