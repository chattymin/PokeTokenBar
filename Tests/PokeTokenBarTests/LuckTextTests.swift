import XCTest
@testable import PokeTokenBar

/// The Luck screen's words and figures (`LuckText`), as TokenDex shows them.
final class LuckTextTests: XCTestCase {
    private let fr = L(.fr)
    private let en = L(.en)

    func testOdds() {
        XCTAssertEqual(fr.luckOdds(.init(low: 0.1, high: 1)), "10 à 100\u{00A0}%")
        XCTAssertEqual(en.luckOdds(.init(low: 0.1, high: 1)), "10 to 100%")
        XCTAssertEqual(fr.luckOdds(.init(low: 0.79, high: 0.79)), "79\u{00A0}%")
        XCTAssertEqual(fr.luckOdds(.init(low: 0.054, high: 0.054)), "5\u{00A0}%", "whole percents from 1 %")
        XCTAssertEqual(fr.luckOdds(.init(low: 0.0054, high: 0.0054)), "0,5\u{00A0}%", "one decimal under 1 %")
        XCTAssertEqual(fr.luckOdds(.init(low: 0.0004, high: 0.0004)), "< 0,1\u{00A0}%")
        XCTAssertEqual(fr.luckPercent(0.844), "84\u{00A0}%")
        XCTAssertEqual(en.luckPercent(0.846), "85%")
    }

    func testOneIn() {
        XCTAssertEqual(en.luckOneIn(1 / 19_591.4), "1 chance in 19,591")
        XCTAssertEqual(fr.luckOneIn(1 / 16_837.6), "1 chance sur 16\u{202F}838")
    }

    /// TokenDex's moods, on the score as shown.
    func testMood() {
        XCTAssertEqual(fr.luckMood(65), "plutôt gâté")
        XCTAssertEqual(fr.luckMood(64), "un peu au-dessus de la moyenne")
        XCTAssertEqual(fr.luckMood(55), "un peu au-dessus de la moyenne")
        XCTAssertEqual(fr.luckMood(54), "pile dans la moyenne")
        XCTAssertEqual(fr.luckMood(46), "pile dans la moyenne")
        XCTAssertEqual(fr.luckMood(45), "un peu en dessous")
        XCTAssertEqual(fr.luckMood(36), "un peu en dessous")
        XCTAssertEqual(fr.luckMood(35), "plutôt malchanceux")
        XCTAssertEqual(fr.luckSentence(hatches: 329, score: 50, best: (.legendary, 0.84), worst: (.new, 0.14)),
                       "Sur 329 éclosions, tu es **pile dans la moyenne**. Ton point fort : **Légendaires** (84\u{00A0}%). "
                           + "Ton point faible : **Du nouveau** (14\u{00A0}%).")
    }

    func testCounts() {
        XCTAssertEqual(fr.luckCounts(hits: 26, expected: 30.43), "26 obtenus · 30,4 attendus")
        XCTAssertEqual(fr.luckCounts(hits: 1, expected: 1.8), "1 obtenu · 1,8 attendu")
        XCTAssertEqual(fr.luckCounts(hits: 0, expected: 2), "0 obtenu · 2 attendus")
        XCTAssertEqual(fr.luckCounts(hits: 3, expected: 0.426), "3 obtenus · 0,43 attendu", "two decimals under one")
        XCTAssertEqual(en.luckCounts(hits: 26, expected: 30.43), "26 caught · 30.4 expected")
    }

    func testSinceLast() {
        XCTAssertEqual(fr.luckSinceLast(nil), "pas encore")
        XCTAssertEqual(fr.luckSinceLast(0), "à la dernière éclosion")
        XCTAssertEqual(fr.luckSinceLast(1), "dernier il y a 1 éclosion")
        XCTAssertEqual(fr.luckSinceLast(8), "dernier il y a 8 éclosions")
    }

    /// An effect on the score, to a tenth: green from +0.5, red from -0.5.
    func testEffect() {
        XCTAssertEqual(fr.luckEffect(2.24), "+2,2")
        XCTAssertEqual(fr.luckEffect(-0.04), "0,0")
        XCTAssertEqual(fr.luckEffect(0), "0,0")
        XCTAssertTrue(fr.luckEffect(-0.6).hasSuffix("0,6"))
        XCTAssertFalse(fr.luckEffect(-0.6).hasPrefix("+"))
        XCTAssertEqual(HatchLuck.effectDirection(0.5), 1)
        XCTAssertEqual(HatchLuck.effectDirection(0.44), 0)
        XCTAssertEqual(HatchLuck.effectDirection(0.46), 1, "as shown: +0,5")
        XCTAssertEqual(HatchLuck.effectDirection(-0.46), -1)
        XCTAssertEqual(HatchLuck.effectDirection(-0.44), 0)
        XCTAssertEqual(HatchLuck.effectDirection(-0.5), -1)
    }

    /// How long a draw would take at the player's pace, in the unit that reads best.
    func testWait() {
        XCTAssertEqual(HatchLuck.averageWait(odds: 1.0 / 10, perWeek: 38), .init(count: 2, unit: .day))
        XCTAssertEqual(HatchLuck.averageWait(odds: 1.0 / 100, perWeek: 38), .init(count: 3, unit: .week))
        XCTAssertEqual(HatchLuck.averageWait(odds: 1.0 / 1_000, perWeek: 38), .init(count: 6, unit: .month))
        XCTAssertEqual(HatchLuck.averageWait(odds: 1.0 / 19_591, perWeek: 38), .init(count: 10, unit: .year))
        XCTAssertEqual(HatchLuck.averageWait(odds: 1.0 / 2, perWeek: 38), .init(count: 1, unit: .day), "a day at least")
        XCTAssertEqual(fr.luckWait(.init(count: 10, unit: .year)), "environ 10 ans à ton rythme")
        XCTAssertEqual(en.luckWait(.init(count: 3, unit: .week)), "about 3 weeks at your pace")
    }

    func testEggNames() {
        XCTAssertEqual(fr.hatchEggName(nil), "Œuf inconnu")
        XCTAssertEqual(fr.hatchEggName(.tier(nil)), fr.eggName(nil))
        XCTAssertEqual(fr.hatchEggName(.tier(.rare)), fr.eggName(.rare))
        XCTAssertEqual(fr.hatchEggName(.fossil), fr.itemName(.fossilEgg))
        XCTAssertEqual(fr.hatchEggName(.legendary), fr.itemName(.legendaryEgg))
        let fire = ItemKind.allCases.first { $0.stoneType == .fire }!
        XCTAssertEqual(fr.hatchEggName(.stone(.fire)), fr.itemName(fire))
        let summer = ItemKind.allCases.first { EventEgg(item: $0) == .summer }!
        XCTAssertEqual(fr.hatchEggName(.event(.summer, key: "summer@2026")), fr.itemName(summer))
    }

    func testACostumeEggIsNamedAsTheBagNamesIt() throws {
        let costumes = [("FALL_2022", 37, 10), ("GOFEST_2021_NOEVOLVE", 263, 6)]
        for (code, speciesID, month) in costumes {
            XCTAssertNotNil(CostumeCatalog.entries.first { $0.code == code && $0.speciesID == speciesID && $0.month == month })
            for language in AppLanguage.allCases {
                let l = L(language)
                let name = l.hatchEggName(.costume(code: code, speciesID: speciesID))
                XCTAssertEqual(name, l.costumeEggName(month), "\(code) \(language)")
                XCTAssertNotEqual(name, l.eggName(nil), "\(code) \(language)")
            }
        }
        XCTAssertEqual(fr.hatchEggName(.costume(code: "RETIRED_COSTUME", speciesID: 133)), fr.eggName(nil))
    }

    /// The shiny criterion uses the app's own word in each language.
    func testShinyIsTheAppsWord() {
        XCTAssertEqual(fr.luckCriterion(.shiny), "Chromatiques")
        XCTAssertEqual(fr.luckCriterion(.rare), "Rares ou mieux")
        for language in AppLanguage.allCases {
            XCTAssertEqual(L(language).luckCriterion(.shiny), L(language).bonusThemeTitle(.shiny), "\(language)")
        }
    }

    /// Every language has every criterion, and no dash.
    func testEveryLanguage() {
        for language in AppLanguage.allCases {
            let l = L(language)
            var words = HatchLuck.Criterion.allCases.map(l.luckCriterion) + PopoverNavigation.LuckTab.allCases.map(l.luckTab)
            words += [l.luckTitle, l.luckScoreTitle, l.luckByCriterionHint, l.luckTooFew, l.luckCurveTitle,
                      l.luckImprobableTitle, l.luckHistoryTitle, l.luckShowMore(321), l.luckUnknownEggs(27),
                      l.luckSentence(hatches: 3, score: 50, best: (.rare, 0.6), worst: (.new, 0.2)),
                      l.luckCurvePoint(number: 3, name: "Pidgey", score: 50), l.luckWait(.init(count: 2, unit: .month)),
                      l.luckEggOfHatch, l.luckDrawItemsTitle, l.luckDrawItemsHint, l.luckObtainedOn,
                      l.luckApproximate, l.luckPickEggsAction, l.luckEggsToPick, l.luckDontRemember,
                      l.luckDontRememberHint, l.luckDeduced]
            for word in words {
                XCTAssertFalse(word.isEmpty, "\(language)")
                XCTAssertFalse(word.contains("\u{2014}") || word.contains("\u{2013}"), "\(language): \(word)")
            }
        }
    }
}
