import XCTest
@testable import PokeTokenBar

// MARK: 번체 중국어(zh-Hant)

/// 언어를 추가할 때 컴파일러가 못 잡는 지점만 고정한다.
/// `t()` 의 인자 개수는 컴파일이 강제하므로 "빠진 문자열"은 여기서 볼 필요가 없다. 대신 조용히
/// 깨지는 네 가지 — (1) 저장 포맷·표시 로케일, (2) 시스템 언어 유추(간체를 번체로 오인),
/// (3) PokéAPI 이름 코드 누락(전부 영어 이름으로 폴백), (4) 다른 언어 문자열 혼입 — 을 검증한다.
final class TraditionalChineseLocalizationTests: XCTestCase {

    // MARK: 저장 포맷 · 로케일

    func testRawValueIsBCP47AndRoundTrips() {
        XCTAssertEqual(AppLanguage.zhHant.rawValue, "zh-Hant")
        XCTAssertTrue(AppLanguage.allCases.contains(.zhHant))
        // rawValue 는 세이브에 그대로 들어간다 — 바뀌면 기존 사용자의 언어 설정이 초기화된다.
        XCTAssertEqual(AppLanguage(rawValue: "zh-Hant"), .zhHant)
        XCTAssertEqual(AppLanguage.zhHant.label, "繁體中文")
    }

    /// 로케일이 어긋나면 팝오버의 자동 생성 문장만 다른 언어로 섞인다("上次更新" 옆에 "3 hours ago").
    func testDisplayLocaleProducesTraditionalRelativeTime() {
        XCTAssertEqual(AppLanguage.zhHant.displayLocale.identifier, "zh-Hant")

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let f = RelativeDateTimeFormatter()
        f.locale = AppLanguage.zhHant.displayLocale
        let relative = f.localizedString(for: now.addingTimeInterval(-3 * 3600), relativeTo: now)

        XCTAssertTrue(relative.contains("小時"), "번체 상대 시각이 아님: \(relative)")
        XCTAssertFalse(relative.contains("小时"), "간체가 새어 들어옴: \(relative)")
    }

    // MARK: 시스템 언어 유추

    /// 간체(zh-Hans/CN/SG) 사용자에게 번체를 주면 시스템 언어와 어긋난 화면이 된다 — 번체권만 매칭.
    func testSystemDefaultMatchesOnlyTraditionalVariants() {
        for tag in ["zh-hant", "zh-hant-tw", "zh-hant-hk", "zh-tw", "zh-hk", "zh-mo", "zh_tw"] {
            XCTAssertTrue(AppLanguage.isTraditionalChinese(tag), "번체로 판정해야 함: \(tag)")
        }
        // 스크립트 태그 없는 "zh" 는 번체라고 단정할 수 없다 → 영어 폴백(기존 동작 유지).
        for tag in ["zh", "zh-hans", "zh-hans-cn", "zh-cn", "zh-sg", "ko-kr", "ja-jp", "en-us", ""] {
            XCTAssertFalse(AppLanguage.isTraditionalChinese(tag), "번체가 아님: \(tag)")
        }
        // 스크립트 태그가 지역보다 우선한다 — zh-Hant-CN 은 번체, zh-Hans-TW 는 간체.
        XCTAssertTrue(AppLanguage.isTraditionalChinese("zh-hant-cn"))
        XCTAssertFalse(AppLanguage.isTraditionalChinese("zh-hans-tw"))
    }

    /// 언어 추가로 기존 사용자의 기본값이 흔들리면 안 된다 — ko/ja/es/en 유추는 그대로.
    /// 실행 기기의 언어에 좌우되지 않게 선호 언어 목록을 주입해 전 분기를 밟는다.
    func testResolveCoversEveryLanguageBranch() {
        XCTAssertEqual(AppLanguage.resolve(preferredLanguages: ["zh-Hant-TW", "en-US"]), .zhHant)
        XCTAssertEqual(AppLanguage.resolve(preferredLanguages: ["zh-TW"]), .zhHant)
        XCTAssertEqual(AppLanguage.resolve(preferredLanguages: ["ko-KR"]), .ko)
        XCTAssertEqual(AppLanguage.resolve(preferredLanguages: ["ja-JP"]), .ja)
        XCTAssertEqual(AppLanguage.resolve(preferredLanguages: ["es-ES"]), .es)
        XCTAssertEqual(AppLanguage.resolve(preferredLanguages: ["en-US"]), .en)
        // 간체·미지원 언어·빈 목록은 영어 폴백(기존 동작).
        XCTAssertEqual(AppLanguage.resolve(preferredLanguages: ["zh-Hans-CN"]), .en)
        XCTAssertEqual(AppLanguage.resolve(preferredLanguages: ["fr-FR"]), .en)
        XCTAssertEqual(AppLanguage.resolve(preferredLanguages: []), .en)
        // 첫 항목만 본다 — 2순위 언어가 결과를 바꾸면 안 된다.
        XCTAssertEqual(AppLanguage.resolve(preferredLanguages: ["en-US", "zh-Hant-TW"]), .en)

        XCTAssertTrue(AppLanguage.allCases.contains(AppLanguage.systemDefault))
    }

    /// 언어 선택 메뉴에 쓰이는 표시명 — 비면 고를 수 없는 항목이 되고, 겹치면 구분할 수 없다.
    func testEveryLanguageHasDistinctLabel() {
        let labels = AppLanguage.allCases.map(\.label)
        XCTAssertEqual(Set(labels).count, AppLanguage.allCases.count)
        XCTAssertFalse(labels.contains(where: \.isEmpty))
    }

    // MARK: PokéAPI 이름

    /// PokéAPI 응답의 `language.name` 은 소문자다("zh-hant"). 대문자만 넣으면 매칭이 실패해
    /// 조용히 영어 이름(Pikachu)이 표시된다 — 그 경로를 실제 매칭으로 고정한다.
    func testSpeciesNameResolvesFromLowercaseAPICode() {
        // 소문자 하나만 둔다 — 대문자 변형은 응답에 존재하지 않아 매칭되지 않는 죽은 항목이고,
        // `PokeAPIClient.langCodes` 에도 그대로 실린다.
        XCTAssertEqual(AppLanguage.zhHant.apiCodes, ["zh-hant"])

        let byLang = ["en": "Pikachu", "ja": "ピカチュウ", "ko": "피카츄", "zh-hant": "皮卡丘"]
        XCTAssertEqual(AppLanguage.zhHant.resolveName(byLang), "皮卡丘")
        // 번체 이름이 없는 종은 영어로 폴백 — 빈 칸이 되지 않는다.
        XCTAssertEqual(AppLanguage.zhHant.resolveName(["en": "Pikachu"]), "Pikachu")
    }

    /// 클라이언트가 저장하는 언어 코드가 `apiCodes` 를 덮지 못하면 위 폴백이 항상 영어가 된다.
    /// 리터럴 목록으로 되돌리는 회귀를 막기 위해 전 언어를 순회한다.
    func testClientKeepsEveryLanguageAPICode() {
        for lang in AppLanguage.allCases {
            for code in lang.apiCodes {
                XCTAssertTrue(PokeAPIClient.langCodes.contains(code), "\(lang.rawValue) 의 \(code) 가 누락됨")
            }
        }
    }

    // MARK: UI 문자열 혼입

    /// 다른 언어 칸을 복사해 넣는 실수(한글·가나 잔류, 간체 혼입)를 걸러낸다.
    /// 이 앱의 UI 문자열은 전부 한자를 포함하므로 "한자 있음 + 한글/가나 없음"이 성립한다.
    func testStringsAreTraditionalChineseWithNoOtherScript() {
        let l = L(.zhHant)
        for (key, value) in Self.samples(l) {
            XCTAssertFalse(value.isEmpty, "\(key) 비어 있음")
            XCTAssertTrue(value.unicodeScalars.contains(where: Self.isHan), "\(key) 에 한자가 없음: \(value)")
            XCTAssertFalse(value.unicodeScalars.contains(where: Self.isHangul), "\(key) 에 한글 잔류: \(value)")
            XCTAssertFalse(value.unicodeScalars.contains(where: Self.isKana), "\(key) 에 가나 잔류: \(value)")
        }
    }

    /// 보간값이 번역 과정에서 사라지면 숫자·이름 없는 문장이 된다(컴파일은 통과한다).
    func testInterpolationsSurviveTranslation() {
        let l = L(.zhHant)
        XCTAssertTrue(l.stage(2, 3).contains("2") && l.stage(2, 3).contains("3"))
        XCTAssertTrue(l.eggToHatch("1.2M").contains("1.2M"))
        XCTAssertTrue(l.notifBody("Claude 每週", "85%").contains("Claude 每週"))
        XCTAssertTrue(l.notifBody("Claude 每週", "85%").contains("85%"))
        XCTAssertTrue(l.notifCandyTitle(item: l.itemName(.rareCandy), count: 3).contains("3"))
        XCTAssertTrue(l.updateAvailable("2.6.0", current: "2.5.1").contains("2.6.0"))
        XCTAssertTrue(l.upToDate("2.5.1").contains("2.5.1"))
        XCTAssertTrue(l.limitRefreshHTTPError(500).contains("500"))
        XCTAssertTrue(l.reportMailFallback("a@b.c").contains("a@b.c"))
        XCTAssertTrue(l.dexPageLabel(2, 7).contains("2") && l.dexPageLabel(2, 7).contains("7"))

        let mail = l.reportMailBody(version: "2.5.1", os: "26.3.1")
        XCTAssertTrue(mail.contains("2.5.1") && mail.contains("26.3.1"))
        XCTAssertTrue(mail.contains("~/Library/Logs/PokeTokenBar.log"), "로그 경로가 번역돼 사라지면 안 된다")

        let confirm = l.importConfirmBody(incomingDex: 12, incomingTokens: "5.0M",
                                          exportedAt: "2026-08-19", sourceDevice: "MacBook",
                                          currentDex: 3, currentTokens: "1.0M")
        for token in ["12", "5.0M", "2026-08-19", "MacBook", "3", "1.0M"] {
            XCTAssertTrue(confirm.contains(token), "\(token) 누락: \(confirm)")
        }
    }

    /// 성격 25종의 번체 명칭 — 본가 공식 표기이고 서로 겹치지 않아야 한다(도감 표시 식별자).
    func testNatureNamesAreDistinctTraditionalChinese() {
        let names = PokemonNature.allCases.map { $0.name(.zhHant) }
        XCTAssertEqual(Set(names).count, 25)
        XCTAssertEqual(PokemonNature.hardy.name(.zhHant), "勤奮")
        XCTAssertEqual(PokemonNature.quirky.name(.zhHant), "浮躁")
        for name in names {
            XCTAssertTrue(name.unicodeScalars.allSatisfy(Self.isHan), "한자 외 문자 포함: \(name)")
        }
    }

    // MARK: 헬퍼

    private static func isHan(_ s: Unicode.Scalar) -> Bool { (0x4E00...0x9FFF).contains(Int(s.value)) }
    private static func isHangul(_ s: Unicode.Scalar) -> Bool {
        let v = Int(s.value)
        return (0xAC00...0xD7A3).contains(v) || (0x1100...0x11FF).contains(v) || (0x3130...0x318F).contains(v)
    }
    private static func isKana(_ s: Unicode.Scalar) -> Bool {
        let v = Int(s.value)
        return (0x3040...0x309F).contains(v) || (0x30A0...0x30FF).contains(v)
    }

    /// 섹션별 대표 문자열 — L 의 프로퍼티는 계산 프로퍼티라 Mirror 로 순회할 수 없어 직접 나열한다.
    private static func samples(_ l: L) -> [(String, String)] {
        [
            ("home", l.home), ("collection", l.collection),
            ("todayTokens", l.todayTokens), ("thisWeek", l.thisWeek), ("thisMonth", l.thisMonth),
            ("limitsOfficial", l.limitsOfficial), ("fiveHourSession", l.fiveHourSession),
            ("weekly", l.weekly), ("reset", l.reset), ("limitReached", l.limitReached),
            ("personalSpendLimit", l.personalSpendLimit), ("staleLimits", l.staleLimits),
            ("refresh", l.refresh), ("limitsTapToLoad", l.limitsTapToLoad),
            ("providerStatus.operational", l.providerStatusLabel(.operational)),
            ("providerStatus.major", l.providerStatusLabel(.major)),
            ("providerStatus.unknown", l.providerStatusLabel(.unknown)),
            ("plan", l.plan("Max")), ("forecastReach", l.forecastReach("14:00")),
            ("forecastNoReach", l.forecastNoReach),
            ("claudeLimitEntry.session", l.claudeLimitEntry(kind: "session", model: nil)),
            ("claudeLimitEntry.scoped", l.claudeLimitEntry(kind: "weekly_scoped", model: nil)),
            ("codexWindow.300", l.codexWindow(300)), ("codexWindow.90", l.codexWindow(90)),
            ("codexWindow.nil", l.codexWindow(nil)),
            ("refreshNow", l.refreshNow), ("updated", l.updated), ("settings", l.settings),
            ("back", l.back), ("quit", l.quit), ("close", l.close),
            ("generalSectionTitle", l.generalSectionTitle), ("menuBarSectionTitle", l.menuBarSectionTitle),
            ("advancedSectionTitle", l.advancedSectionTitle), ("advancedDisclosureLabel", l.advancedDisclosureLabel),
            ("aboutSupportSectionTitle", l.aboutSupportSectionTitle),
            ("refreshInterval", l.refreshInterval), ("language", l.language),
            ("menuBarItems", l.menuBarItems), ("todayCost", l.todayCost),
            ("limitDisplayModeLabel", l.limitDisplayModeLabel), ("limitDisplayUsed", l.limitDisplayUsed),
            ("limitDisplayRemaining", l.limitDisplayRemaining), ("percentRemaining", l.percentRemaining("20%")),
            ("allOffHint", l.allOffHint),
            ("floatingPetSectionTitle", l.floatingPetSectionTitle), ("floatingPetEnableLabel", l.floatingPetEnableLabel),
            ("floatingPetHint", l.floatingPetHint), ("floatingPetSizeLabel", l.floatingPetSizeLabel),
            ("floatingPetBubbleAlertsLabel", l.floatingPetBubbleAlertsLabel),
            ("floatingPetMenuOpen", l.floatingPetMenuOpen), ("floatingPetMenuHide", l.floatingPetMenuHide),
            ("floatingPetHoverTokensOnly", l.floatingPetHoverTokensOnly("1.2M")),
            ("floatingPetHoverWithLimit", l.floatingPetHoverWithLimit("1.2M", "80%")),
            ("disableKeychain", l.disableKeychain), ("disableKeychainHint", l.disableKeychainHint),
            ("refreshLimitToken", l.refreshLimitToken), ("onlyOnPress", l.onlyOnPress),
            ("launchAtLogin", l.launchAtLogin), ("bundledOnly", l.bundledOnly),
            ("notificationsSection", l.notificationsSection), ("limitNotificationsLabel", l.limitNotificationsLabel),
            ("companionNotificationsLabel", l.companionNotificationsLabel),
            ("statusChecksLabel", l.statusChecksLabel), ("statusChecksHint", l.statusChecksHint),
            ("warning", l.warning), ("critical", l.critical), ("aggregationNote", l.aggregationNote),
            ("transferSectionTitle", l.transferSectionTitle), ("exportSaveLabel", l.exportSaveLabel),
            ("exportSaveHint", l.exportSaveHint), ("exportSaveButton", l.exportSaveButton),
            ("importSaveLabel", l.importSaveLabel), ("importSaveHint", l.importSaveHint),
            ("importSaveButton", l.importSaveButton), ("importConfirmTitle", l.importConfirmTitle),
            ("importConfirmReplace", l.importConfirmReplace),
            ("importSaveDone", l.importSaveDone(dex: 1, tokens: "1M")),
            ("importErrorNotSaveFile", l.importErrorNotSaveFile), ("importErrorNewerSchema", l.importErrorNewerSchema),
            ("importErrorTooLarge", l.importErrorTooLarge), ("importErrorBackupFailed", l.importErrorBackupFailed),
            ("reportProblem", l.reportProblem), ("showLogFile", l.showLogFile),
            ("reportAttachHint", l.reportAttachHint), ("reportMailSubject", l.reportMailSubject("2.5.1")),
            ("intervalLabel.0", l.intervalLabel(0)), ("intervalLabel.300", l.intervalLabel(300)),
            ("finalForm", l.finalForm), ("stage", l.stage(1, 2)),
            ("unknownNextEvolution", l.unknownNextEvolution), ("eggIncubating", l.eggIncubating),
            ("eggToHatch", l.eggToHatch("1M")), ("toNextEvolution", l.toNextEvolution("1M")),
            ("toGraduation", l.toGraduation("1M")), ("graduated", l.graduated("皮卡丘")),
            ("dexEmptyTitle", l.dexEmptyTitle), ("dexEmptyHint", l.dexEmptyHint),
            ("dexTitle", l.dexTitle), ("dexTotal", l.dexTotal(3)), ("catchLogTitle", l.catchLogTitle),
            ("dexSpeciesTotal", l.dexSpeciesTotal(3)), ("dexPageLabel", l.dexPageLabel(1, 2)),
            ("dexPagePrev", l.dexPagePrev), ("dexPageNext", l.dexPageNext), ("dexRaising", l.dexRaising),
            ("rarity.common", l.rarityLabel(.common)), ("rarity.uncommon", l.rarityLabel(.uncommon)),
            ("rarity.rare", l.rarityLabel(.rare)), ("rarity.legendary", l.rarityLabel(.legendary)),
            ("dexFilterHint", l.dexFilterHint), ("dexShinyLabel", l.dexShinyLabel),
            ("statusEgg", l.statusEgg), ("statusIdle", l.statusIdle), ("statusWorking", l.statusWorking),
            ("statusFocus", l.statusFocus), ("statusTired", l.statusTired), ("statusSleep", l.statusSleep),
            ("statusEvolved", l.statusEvolved("皮卡丘")), ("statusGrew", l.statusGrew),
            ("notifHatchTitle", l.notifHatchTitle), ("notifHatchBody", l.notifHatchBody("皮卡丘")),
            ("notifShinyHatchTitle", l.notifShinyHatchTitle), ("notifShinyHatchBody", l.notifShinyHatchBody("皮卡丘")),
            ("eggImminent", l.eggImminent), ("eggFirstRunHint", l.eggFirstRunHint),
            ("notifEvolveTitle", l.notifEvolveTitle), ("notifEvolveBody", l.notifEvolveBody("雷丘")),
            ("notifDittoRevealTitle", l.notifDittoRevealTitle), ("notifDittoRevealBody", l.notifDittoRevealBody("皮卡丘")),
            ("notifShinyDittoRevealTitle", l.notifShinyDittoRevealTitle),
            ("notifShinyDittoRevealBody", l.notifShinyDittoRevealBody("皮卡丘")),
            ("notifGraduateTitle", l.notifGraduateTitle), ("notifGraduateBody", l.notifGraduateBody("雷丘")),
            ("limitRefreshHTTPError.401", l.limitRefreshHTTPError(401)),
            ("limitRefreshHTTPError.500", l.limitRefreshHTTPError(500)),
            ("limitRefreshNoCredential", l.limitRefreshNoCredential),
            ("limitRefreshReauthNeeded", l.limitRefreshReauthNeeded),
            ("limitRefreshGeneric", l.limitRefreshGeneric), ("limitRefreshRateLimited", l.limitRefreshRateLimited),
            ("claudeAuthExpiredTitle", l.claudeAuthExpiredTitle), ("claudeAuthExpiredHint", l.claudeAuthExpiredHint),
            ("retry", l.retry), ("updateAvailable", l.updateAvailable("2.6.0", current: "2.5.1")),
            ("updateButton", l.updateButton), ("updateLater", l.updateLater), ("updating", l.updating),
            ("updateSectionTitle", l.updateSectionTitle), ("updateNotificationsLabel", l.updateNotificationsLabel),
            ("checkForUpdatesLabel", l.checkForUpdatesLabel), ("checkNowButton", l.checkNowButton),
            ("updateFound", l.updateFound("2.6.0")), ("upToDate", l.upToDate("2.5.1")),
            ("notifCritical", l.notifCritical), ("notifWarning", l.notifWarning),
            ("claudeFiveHour", l.claudeFiveHour), ("claudeWeekly", l.claudeWeekly),
            ("codexPersonalLimit", l.codexPersonalLimit),
            ("bag", l.bag), ("bagEmptyTitle", l.bagEmptyTitle), ("useItem", l.useItem), ("use", l.use),
            ("cancel", l.cancel), ("useOnCurrent", l.useOnCurrent("皮卡丘")),
            ("useAfterHatch", l.useAfterHatch), ("useNeedsPokemon", l.useNeedsPokemon),
            ("item.rareCandy", l.itemName(.rareCandy)), ("item.mint", l.itemName(.mint)),
            ("item.shinyCharm", l.itemName(.shinyCharm)),
            ("itemDesc.rareCandy", l.itemDescription(.rareCandy)), ("itemDesc.mint", l.itemDescription(.mint)),
            ("itemDesc.shinyCharm", l.itemDescription(.shinyCharm)), ("mintEffectHint", l.mintEffectHint),
            ("shop", l.shop), ("spendableTokens", l.spendableTokens), ("shopHint", l.shopHint),
            ("buy", l.buy), ("buyConfirm", l.buyConfirm("薄荷")), ("notEnoughTokens", l.notEnoughTokens),
            ("ownedCount", l.ownedCount(2)), ("shopPriceLabel", l.shopPriceLabel), ("ownedAlready", l.ownedAlready),
            ("shinyCharmEffectHint", l.shinyCharmEffectHint),
            ("eggName.nil", l.eggName(nil)), ("eggName.uncommon", l.eggName(.uncommon)),
            ("eggName.rare", l.eggName(.rare)), ("eggName.legendary", l.eggName(.legendary)),
            ("eggDescription.nil", l.eggDescription(nil)), ("eggDescription.rare", l.eggDescription(.rare)),
            ("eggGuaranteeHint", l.eggGuaranteeHint(.rare)), ("eggConfirm", l.eggConfirm("皮卡丘", "稀有的蛋")),
            ("freshEggShinyWarning", l.freshEggShinyWarning), ("freshEggDiscardShiny", l.freshEggDiscardShiny),
            ("notifCandyTitle", l.notifCandyTitle(item: "神奇糖果", count: 2)),
            ("notifCandyBody", l.notifCandyBody(window: "Claude 每週")),
        ]
    }
}
