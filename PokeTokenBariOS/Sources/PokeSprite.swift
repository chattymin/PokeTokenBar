import Foundation

/// Single source for PokéAPI sprite URLs used across the phone app
/// (companion card, bag item icons, collection grid).
enum PokeSprite {
    private static let base = "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites"

    static func speciesURL(id: Int, shiny: Bool) -> URL? {
        let file = shiny ? "shiny/\(id).png" : "\(id).png"
        return URL(string: "\(base)/pokemon/\(file)")
    }

    static func itemURL(name: String) -> URL? {
        URL(string: "\(base)/items/\(name).png")
    }
}
