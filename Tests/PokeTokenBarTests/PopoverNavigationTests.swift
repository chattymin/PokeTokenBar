import XCTest
@testable import PokeTokenBar

// 팝오버 내비게이션 리셋 계약 — 닫혔다 열릴 때 AppDelegate.togglePopover 가 reset()을 불러
// 항상 Home 으로 돌아가게 한다(설정 화면 잔류 방지).
@MainActor
final class PopoverNavigationTests: XCTestCase {
    func testDefaultsToHome() {
        let nav = PopoverNavigation()
        XCTAssertFalse(nav.showSettings)
        XCTAssertEqual(nav.tab, .home)
        XCTAssertFalse(nav.showingCollectionLog)
    }

    func testResetReturnsToHomeFromSettings() {
        let nav = PopoverNavigation()
        nav.showSettings = true
        nav.tab = .collection
        nav.showingCollectionLog = true
        nav.reset()
        XCTAssertFalse(nav.showSettings)   // 설정 화면 닫힘
        XCTAssertEqual(nav.tab, .home)     // 탭도 Home 으로
        XCTAssertTrue(nav.showingCollectionLog, "일반 재진입은 사용자가 보던 컬렉션 세그먼트를 유지")
    }

    func testOpenRepresentativeDexLeavesSettingsForCollection() {
        let nav = PopoverNavigation()
        nav.showSettings = true
        nav.showingCollectionLog = true

        nav.openRepresentativeDex()

        XCTAssertFalse(nav.showSettings)
        XCTAssertEqual(nav.tab, .collection)
        XCTAssertFalse(nav.showingCollectionLog, "포획 로그에서 설정을 열었어도 대표 선택은 도감으로 이동")
    }

    /// Clicking a sprite on Home opens that species' Pokédex page, even from Settings. The segment
    /// is kept so Back lands where the Collection tab would normally reopen.
    func testOpenDexEntryShowsDetailInCollection() {
        let nav = PopoverNavigation()
        nav.showSettings = true
        nav.showingCollectionLog = true

        nav.openDexEntry(collectionID: "25")

        XCTAssertFalse(nav.showSettings)
        XCTAssertEqual(nav.tab, .collection)
        XCTAssertEqual(nav.dexDetailCollectionID, "25", "set after the tab/settings changes that clear it")
        XCTAssertTrue(nav.showingCollectionLog, "segment is left as it was")
    }

    /// The detail page used to be `CollectionView` `@State`, dropped whenever the collection
    /// content left the screen. Each trigger must still drop it.
    func testDexDetailDroppedWhenCollectionContentLeavesScreen() {
        let triggers: [(String, (PopoverNavigation) -> Void)] = [
            ("other tab", { $0.tab = .home }),
            ("settings", { $0.showSettings = true }),
            ("recap", { $0.showingRecap = true }),
            ("segment switch", { $0.showingCollectionLog.toggle() }),
            ("popover reopen", { $0.reset() }),
        ]
        for (name, trigger) in triggers {
            let nav = PopoverNavigation()
            nav.openDexEntry(collectionID: "25")
            trigger(nav)
            XCTAssertNil(nav.dexDetailCollectionID, name)
        }
    }

    /// Writes that leave the collection content on screen must keep the page — otherwise the
    /// didSets would clear it on no-op assignments (a re-tapped tab or segment).
    func testDexDetailKeptWhileCollectionContentStaysOnScreen() {
        let keepers: [(String, (PopoverNavigation) -> Void)] = [
            ("same tab", { $0.tab = .collection }),
            ("same segment", { $0.showingCollectionLog = $0.showingCollectionLog }),
            ("settings closed", { $0.showSettings = false }),
            ("recap closed", { $0.showingRecap = false }),
        ]
        for (name, keep) in keepers {
            let nav = PopoverNavigation()
            nav.openDexEntry(collectionID: "25")
            keep(nav)
            XCTAssertEqual(nav.dexDetailCollectionID, "25", name)
        }
    }

    /// #301: Hide is a right-click. Show has to live on the popover footer, bound to the same
    /// `floatingPetEnabled` the Settings checkbox already uses. Removing the button must fail this.
    func testPopoverFooterTogglesFloatingPetWithoutOpeningSettings() throws {
        let source = try String(contentsOf: Self.popoverSource, encoding: .utf8)
        let footer = try XCTUnwrap(source.range(of: "private var footer"))
        let body = String(source[footer.lowerBound...])
        XCTAssertTrue(
            body.contains("store.floatingPetEnabled.toggle()"),
            "footer must flip floatingPetEnabled — Hide already does; Show had only Settings")
        XCTAssertTrue(body.contains("l.floatingPetHideLabel"))
        XCTAssertTrue(body.contains("l.floatingPetEnableLabel"))
        XCTAssertFalse(
            body.contains("nav.showSettings = true\n            }\n            .buttonStyle(.borderless)\n            .help(l.floatingPet"),
            "the pet control must not be a second door into Settings")
    }

    private static let popoverSource: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/PokeTokenBar/UI/PopoverView.swift")
    }()
}

final class RepresentativeLocalizationTests: XCTestCase {
    func testGermanSettingsLabelsIncludeLatestMainStrings() {
        let l = L(.de)

        XCTAssertEqual(l.todayTokensShort, "Heutige Tokens")
        XCTAssertEqual(l.todayCost, "Heutige Kosten ($)")
        XCTAssertEqual(l.limitPercent, "Limit %")
        XCTAssertEqual(l.animationQualityLabel, "Animation")
        XCTAssertEqual(l.animationQualityHint, "Flüssigere Animationen verbrauchen mehr Batterie")
        XCTAssertEqual(l.animationPowerSaver, "Energiesparmodus")
        XCTAssertEqual(l.animationBalanced, "Ausgewogen")
        XCTAssertEqual(l.animationSmooth, "Flüssig")
    }

    /// 대표 포켓몬은 메뉴바와 플로팅 펫에 함께 쓰이는 독립 개념이다. 모든 언어가 pet 전용 표현으로
    /// 되돌아가거나 스페인어 추가 뒤 한 언어만 빠지지 않도록 사용자가 보는 핵심 액션을 고정한다.
    func testRepresentativeActionsAreLocalizedInEverySupportedLanguage() {
        let expected: [(AppLanguage, label: String, follow: String, choose: String, set: String)] = [
            (.ko, "대표 포켓몬", "현재 포켓몬 따라가기", "도감에서 선택…", "대표로 설정"),
            (.en, "Representative Pokémon", "Follow current companion", "Choose in Pokédex…",
             "Set as representative"),
            (.ja, "代表ポケモン", "現在のポケモンに合わせる", "図鑑で選ぶ…", "代表ポケモンに設定"),
            (.es, "Pokémon representativo", "Seguir al compañero actual", "Elegir en la Pokédex…",
             "Establecer como representante"),
            (.fr, "Pokémon représentatif", "Suivre le compagnon actuel", "Choisir dans le Pokédex…",
             "Définir comme représentatif"),
            (.pt, "Pokémon representativo", "Seguir o companheiro atual", "Escolher na Pokédex…",
             "Definir como representante"),
            (.de, "Repräsentatives Pokémon", "Aktuellem Begleiter folgen", "Im Pokédex auswählen…",
             "Als repräsentativ festlegen"),
        ]

        XCTAssertEqual(expected.map(\.0), AppLanguage.allCases)
        for item in expected {
            let l = L(item.0)
            XCTAssertEqual(l.representativePokemonLabel, item.label)
            XCTAssertEqual(l.representativeFollowCurrent, item.follow)
            XCTAssertEqual(l.representativeChooseFromDex, item.choose)
            XCTAssertEqual(l.representativeSet, item.set)
            XCTAssertFalse(l.representativeBadge.isEmpty)
        }
    }
}
