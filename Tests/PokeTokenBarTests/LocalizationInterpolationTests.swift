import XCTest
@testable import PokeTokenBar

/// Interpolation-parity guard: the compiler enforces only the `t(...)` arg count, not that a
/// translation kept its `\(...)` placeholders — a dropped one still compiles. Sentinels catch it.
final class LocalizationInterpolationTests: XCTestCase {
    func testStringArgInterpolationsSurviveEveryLanguage() {
        let A = "SNTA"
        let B = "SNTB"
        for lang in AppLanguage.allCases {
            let l = L(lang)
            func check(_ label: String, _ produced: String, _ expected: String...) {
                for e in expected {
                    XCTAssertTrue(produced.contains(e),
                                  "\(lang.rawValue) \(label): '\(e)' missing → '\(produced)'")
                }
            }
            check("forecastReach", l.forecastReach(A), A)
            check("claudeLimitEntry", l.claudeLimitEntry(kind: "weekly_scoped", model: A), A)
            check("percentRemaining", l.percentRemaining(A), A)
            check("floatingPetHoverTokensOnly", l.floatingPetHoverTokensOnly(A), A)
            check("floatingPetHoverWithLimit", l.floatingPetHoverWithLimit(A, B), A, B)
            check("importSaveDone", l.importSaveDone(dex: 4242, tokens: A), "4242", A)
            check("reportMailFallback", l.reportMailFallback(A), A)
            check("reportMailSubject", l.reportMailSubject(A), A)
            check("reportMailBody", l.reportMailBody(version: A, os: B), A, B)
            check("eggToHatch", l.eggToHatch(A), A)
            check("toNextEvolution", l.toNextEvolution(A), A)
            check("toGraduation", l.toGraduation(A), A)
            check("graduated", l.graduated(A), A)
            check("statusEvolved", l.statusEvolved(A), A)
            check("notifHatchBody", l.notifHatchBody(A), A)
            check("notifShinyHatchBody", l.notifShinyHatchBody(A), A)
            check("notifEvolveBody", l.notifEvolveBody(A), A)
            check("notifDittoRevealBody", l.notifDittoRevealBody(A), A)
            check("notifShinyDittoRevealBody", l.notifShinyDittoRevealBody(A), A)
            check("notifGraduateBody", l.notifGraduateBody(A), A)
            check("limitRefreshHTTPError401", l.limitRefreshHTTPError(401), "401")
            check("limitRefreshHTTPError404", l.limitRefreshHTTPError(404), "404")
            check("updateAvailable", l.updateAvailable(A, current: B), A, B)
            check("updateFound", l.updateFound(A), A)
            check("upToDate", l.upToDate(A), A)
            check("notifBody", l.notifBody(A, B), A, B)
            check("useOnCurrent", l.useOnCurrent(A), A)
            check("buyConfirm", l.buyConfirm(A), A)
            check("eggConfirm", l.eggConfirm(A, B), A, B)
            check("notifCandyTitle", l.notifCandyTitle(item: A, count: 4242), A, "4242")
            check("notifCandyBody", l.notifCandyBody(window: A), A)
            check("plan", l.plan(A), A)
            check("stage", l.stage(4242, 1717), "4242", "1717")
            check("dexTotal", l.dexTotal(4242), "4242")
            check("dexSpeciesTotal", l.dexSpeciesTotal(4242), "4242")
            check("dexPageLabel", l.dexPageLabel(4242, 1717), "4242", "1717")
            check("ownedCount", l.ownedCount(4242), "4242")
            check("intervalLabel", l.intervalLabel(1860), "31")          // 1860s → 31 min
            check("codexWindow-hours", l.codexWindow(420), "7")          // 420 min → 7 h
            check("codexWindow-mins", l.codexWindow(37), "37")
            check("importConfirmBody",
                  l.importConfirmBody(incomingDex: 4242, incomingTokens: A,
                                      exportedAt: "EXPAT", sourceDevice: "SRCDEV",
                                      currentDex: 1717, currentTokens: B),
                  "4242", A, "EXPAT", "SRCDEV", "1717", B)
            check("eggDescription", l.eggDescription(.rare), l.rarityRare)
            check("eggGuaranteeHint", l.eggGuaranteeHint(.uncommon), l.rarityUncommon)
        }
    }
}
