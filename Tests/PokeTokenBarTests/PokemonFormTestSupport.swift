@testable import PokeTokenBar

extension PokemonForm {
    static var unownLetters: [PokemonForm] { forms(speciesID: unownSpeciesID) }

    static let a = PokemonForm("a"), b = PokemonForm("b"), c = PokemonForm("c"), d = PokemonForm("d")
    static let e = PokemonForm("e"), f = PokemonForm("f"), g = PokemonForm("g"), h = PokemonForm("h")
    static let i = PokemonForm("i"), j = PokemonForm("j"), k = PokemonForm("k"), l = PokemonForm("l")
    static let m = PokemonForm("m"), n = PokemonForm("n"), o = PokemonForm("o"), p = PokemonForm("p")
    static let q = PokemonForm("q"), r = PokemonForm("r"), s = PokemonForm("s"), t = PokemonForm("t")
    static let u = PokemonForm("u"), v = PokemonForm("v"), w = PokemonForm("w"), x = PokemonForm("x")
    static let y = PokemonForm("y"), z = PokemonForm("z")
    static let exclamation = PokemonForm("exclamation"), question = PokemonForm("question")
}
