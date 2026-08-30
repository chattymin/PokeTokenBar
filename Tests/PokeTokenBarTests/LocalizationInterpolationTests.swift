import XCTest
@testable import PokeTokenBar

/// Placeholder-parity guard. `t(...)` enforces only the *number* of arguments —
/// nothing checks that a translation kept its `\(...)` placeholders, so a line
/// that dropped one still compiles. A defect like "the token count vanished, but
/// only in Portuguese" is caught by neither the build nor the existing tests, and
/// the gap widens with every language added.
/// Here each interpolated member is fed a sentinel that cannot occur in natural
/// copy, and every language's output must still contain it. Never a literal list
/// of languages: only `allCases` keeps coverage from silently stopping when a
/// sixth language lands.
/// (The French PR #185 proposes an equivalent guard. Whichever merges first, the
/// other copy can simply be dropped — the guard is not specific to a language.)
///
/// 치환자 보존 가드 — `t(...)` 가 강제하는 건 인자 *개수*뿐이라, 번역문이 `\(...)` 를 하나
/// 흘려도 컴파일은 그대로 통과한다. "포르투갈어 알림에서만 토큰 수가 사라진" 류의 결함은
/// 빌드도 기존 테스트도 못 잡고 그대로 출시된다 — 언어를 늘릴 때마다 커지는 공백이다.
/// 자연어에 절대 나타나지 않는 센티널을 넣고 모든 언어의 산출물에 살아있는지 확인한다.
/// 리터럴 언어 목록은 쓰지 않는다 — `allCases` 라야 언어가 늘어도 커버가 조용히 멈추지 않는다.
final class LocalizationInterpolationTests: XCTestCase {
    private static let a = "ZQXSENTINELA"
    private static let b = "ZQXSENTINELB"

    /// Failure text carries language, member and output, so a red run names the
    /// exact translation and the exact placeholder without any digging.
    /// 실패 메시지에 언어·멤버·산출물을 모두 담는다 — 어느 번역의 어느 치환자인지 바로 보이도록.
    private func expect(_ lang: AppLanguage, _ member: String, _ produced: String,
                        _ needles: String...,
                        file: StaticString = #filePath, line: UInt = #line) {
        for needle in needles {
            XCTAssertTrue(produced.contains(needle),
                          "\(lang.rawValue).\(member): '\(needle)' is missing → '\(produced)'",
                          file: file, line: line)
        }
    }

    func testInterpolationsSurviveInEverySupportedLanguage() {
        let a = Self.a
        let b = Self.b

        for lang in AppLanguage.allCases {
            let l = L(lang)

            // Limits & forecast / 한도 · 예측
            expect(lang, "plan", l.plan(a), a)
            expect(lang, "forecastReach", l.forecastReach(a), a)
            expect(lang, "claudeLimitEntry",
                   l.claudeLimitEntry(kind: "weekly_scoped", model: a), a)
            expect(lang, "limitsAccount", l.limitsAccount(a), a)

            // Limit history (locally recorded) / 한도 이력
            expect(lang, "limitHistoryPeak", l.limitHistoryPeak(a), a)
            expect(lang, "limitHistoryMedian", l.limitHistoryMedian(a), a)
            expect(lang, "limitHistoryAtOrAbove",
                   l.limitHistoryAtOrAbove(count: 3, total: 12, threshold: a), a, "3", "12")
            expect(lang, "codexWindow(h)", l.codexWindow(420), "7")     // 420 min → 7 h / 420분 → 7시간
            expect(lang, "codexWindow(m)", l.codexWindow(37), "37")
            expect(lang, "percentRemaining", l.percentRemaining(a), a)
            expect(lang, "limitRefreshHTTPError(401)", l.limitRefreshHTTPError(401), "401")
            expect(lang, "limitRefreshHTTPError(404)", l.limitRefreshHTTPError(404), "404")

            // Floating pet & settings / 플로팅 펫 · 설정
            expect(lang, "floatingPetHoverTokensOnly", l.floatingPetHoverTokensOnly(a), a)
            expect(lang, "floatingPetHoverWithLimit", l.floatingPetHoverWithLimit(a, b), a, b)
            expect(lang, "intervalLabel", l.intervalLabel(1860), "31")  // 1860 s → 31 min / 1860초 → 31분
            expect(lang, "customScanRootsMatches", l.customScanRootsMatches(4242), "4242")

            // Save transfer / 세이브 이전
            expect(lang, "importConfirmBody",
                   l.importConfirmBody(incomingDex: 4242, incomingTokens: a,
                                       exportedAt: "ZQXEXPORTEDAT", sourceDevice: "ZQXDEVICE",
                                       currentDex: 1717, currentTokens: b),
                   "4242", a, "ZQXEXPORTEDAT", "ZQXDEVICE", "1717", b)
            expect(lang, "importSaveDone", l.importSaveDone(dex: 4242, tokens: a), "4242", a)

            // Mail report / 메일 리포트
            expect(lang, "reportMailFallback", l.reportMailFallback(a), a)
            expect(lang, "reportMailSubject", l.reportMailSubject(a), a)
            expect(lang, "reportMailBody", l.reportMailBody(version: a, os: b), a, b)

            // Companion progress & status / 컴패니언 진행 · 상태
            expect(lang, "stage", l.stage(4242, 1717), "4242", "1717")
            expect(lang, "eggToHatch", l.eggToHatch(a), a)
            expect(lang, "toNextEvolution", l.toNextEvolution(a), a)
            expect(lang, "toGraduation", l.toGraduation(a), a)
            expect(lang, "graduated", l.graduated(a), a)
            expect(lang, "statusEvolved", l.statusEvolved(a), a)

            // Pokédex / 도감
            expect(lang, "dexTotal", l.dexTotal(4242), "4242")
            expect(lang, "dexSpeciesTotal", l.dexSpeciesTotal(4242), "4242")
            expect(lang, "dexPageLabel", l.dexPageLabel(4242, 1717), "4242", "1717")

            // System notifications / 시스템 알림
            expect(lang, "notifHatchBody", l.notifHatchBody(a), a)
            expect(lang, "notifShinyHatchBody", l.notifShinyHatchBody(a), a)
            expect(lang, "notifEvolveBody", l.notifEvolveBody(a), a)
            expect(lang, "notifDittoRevealBody", l.notifDittoRevealBody(a), a)
            expect(lang, "notifShinyDittoRevealBody", l.notifShinyDittoRevealBody(a), a)
            expect(lang, "notifGraduateBody", l.notifGraduateBody(a), a)
            expect(lang, "notifBody", l.notifBody(a, b), a, b)
            expect(lang, "notifCandyTitle", l.notifCandyTitle(item: a, count: 4242), a, "4242")
            expect(lang, "notifCandyBody", l.notifCandyBody(window: a), a)

            // Updates / 업데이트
            expect(lang, "updateAvailable", l.updateAvailable(a, current: b), a, b)
            expect(lang, "updateFound", l.updateFound(a), a)
            expect(lang, "upToDate", l.upToDate(a), a)

            // Bag, shop, eggs / 가방 · 상점 · 알
            expect(lang, "useOnCurrent", l.useOnCurrent(a), a)
            expect(lang, "buyConfirm", l.buyConfirm(a), a)
            expect(lang, "ownedCount", l.ownedCount(4242), "4242")
            expect(lang, "eggConfirm", l.eggConfirm(a, b), a, b)
            // Constant-derived substitution: hardcode it and the candy blurb drifts
            // away from the real XP value.
            // 상수 파생 치환 — 하드코딩으로 드리프트하면 사탕 설명이 실제 XP 와 어긋난다.
            expect(lang, "itemDescription(.rareCandy)", l.itemDescription(.rareCandy),
                   TokenFormatter.compact(RareCandy.xp))
            // Rarity label spliced into copy: a translation that spells the tier out
            // instead of substituting it is caught here.
            // 등급 라벨을 끼워 넣는 문구 — 번역이 치환 대신 등급을 고정 표기하면 여기서 걸린다.
            expect(lang, "eggDescription(.rare)", l.eggDescription(.rare), l.rarityRare)
            expect(lang, "eggGuaranteeHint(.uncommon)", l.eggGuaranteeHint(.uncommon), l.rarityUncommon)
        }
    }

    /// Proves the guard above actually rejects a translation that dropped its
    /// placeholder — a test that only ever passes is indistinguishable from one
    /// that checks nothing. The defect is injected independently of Localization,
    /// so a green localized run cannot hide a broken predicate.
    /// 위 가드가 "치환자가 빠진 번역"에 실제로 실패하는지 — 통과만 보면 아무것도 안 지키는
    /// 테스트와 구별할 수 없다. Localization 과 독립적으로 결함을 주입해 판정부만 확인한다.
    func testGuardRejectsATranslationThatDroppedItsPlaceholder() {
        let intact = "Hoje: \(Self.a) tokens"
        let dropped = "Hoje: tokens"                     // \(tokens) dropped / \(tokens) 를 흘린 번역
        XCTAssertTrue(intact.contains(Self.a))
        XCTAssertFalse(dropped.contains(Self.a),
                       "letting a sentinel-less string pass would make the guard meaningless")
    }
}
