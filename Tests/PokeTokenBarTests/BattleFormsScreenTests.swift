import XCTest
@testable import PokeTokenBar

/// The Battle Forms screen (the owner, 2026-11-24): every Mega, Primal and Gigantamax form by kind, a filter of the
/// won ones, and a won form's page that goes back to the screen.
@MainActor
final class BattleFormsScreenTests: XCTestCase {
    func testEveryCatalogFormShowsOnceUnderItsKind() {
        let sections = BattleForms.sections(won: [], wonOnly: false)
        XCTAssertEqual(sections.map(\.kind), [.mega, .primal, .gigantamax])
        XCTAssertEqual(sections.flatMap(\.forms).count, BattleForms.all.count)
        XCTAssertEqual(Set(sections.flatMap(\.forms).map(\.key)).count, BattleForms.all.count)
        for section in sections {
            XCTAssertTrue(section.forms.allSatisfy { $0.kind == section.kind })
            XCTAssertEqual(section.total, BattleForms.all.filter { $0.kind == section.kind }.count)
            XCTAssertEqual(section.won, 0)
        }
    }

    func testWonOnlyKeepsTheWonFormsAndCountsTheWholeKind() throws {
        let megaX = try XCTUnwrap(BattleForms.form(speciesID: 6, form: PokemonForm("mega-x")))
        let gengar = try XCTUnwrap(BattleForms.form(speciesID: 94, form: PokemonForm("gmax")))
        let won: Set<String> = [megaX.key, gengar.key]

        let shown = BattleForms.sections(won: won, wonOnly: true)
        XCTAssertEqual(shown.map(\.kind), [.mega, .gigantamax], "a kind with nothing won is left out")
        XCTAssertEqual(shown.map { $0.forms.map(\.key) }, [[megaX.key], [gengar.key]])
        XCTAssertEqual(shown.map(\.won), [1, 1])
        XCTAssertEqual(shown.map(\.total), [BattleForms.all.filter { $0.kind == .mega }.count,
                                            BattleForms.all.filter { $0.kind == .gigantamax }.count])

        let all = BattleForms.sections(won: won, wonOnly: false)
        XCTAssertEqual(all.first { $0.kind == .mega }?.won, 1)
        XCTAssertEqual(all.first { $0.kind == .primal }?.won, 0)
    }

    func testGiovannisArmorShowsOnlyOnceWon() {
        let armor = ArmoredMewtwo.battleForm
        XCTAssertFalse(BattleForms.sections(won: [], wonOnly: false).contains { $0.kind == .armor })
        let sections = BattleForms.sections(won: [armor.key], wonOnly: true)
        XCTAssertEqual(sections.map(\.kind), [.armor])
        XCTAssertEqual(sections.first?.forms, [armor])
        XCTAssertEqual(sections.first?.total, 1)
    }

    func testAPageOpenedFromTheScreenGoesBackToIt() throws {
        let form = try XCTUnwrap(BattleForms.form(speciesID: 6, form: PokemonForm("mega-x")))
        let nav = PopoverNavigation()
        nav.showingBattleForms = true
        nav.openBattleForm(form, collectionID: "6")
        XCTAssertFalse(nav.showingBattleForms)
        XCTAssertEqual(nav.tab, .collection)
        XCTAssertEqual(nav.dexDetailCollectionID, "6")
        XCTAssertEqual(nav.dexDetailForm, form.form)

        XCTAssertTrue(nav.returnToBattleForms())
        XCTAssertTrue(nav.showingBattleForms)
        XCTAssertNil(nav.dexDetailCollectionID)
        XCTAssertFalse(nav.returnToBattleForms(), "once back, nothing more to return to")
    }

    func testAPageOpenedElsewhereGoesBackToTheGrid() throws {
        let form = try XCTUnwrap(BattleForms.form(speciesID: 6, form: PokemonForm("mega-x")))
        let nav = PopoverNavigation()
        nav.tab = .collection
        nav.dexDetailCollectionID = "6"
        XCTAssertFalse(nav.returnToBattleForms())

        // Leaving the page another way forgets where it came from.
        nav.openBattleForm(form, collectionID: "6")
        nav.tab = .home
        nav.tab = .collection
        nav.dexDetailCollectionID = "25"
        XCTAssertFalse(nav.returnToBattleForms())
        XCTAssertFalse(nav.showingBattleForms)
    }
}
