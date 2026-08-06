import AppKit
import SwiftUI
import XCTest
@testable import PokeDexBar

/// 카탈로그는 Showdown 에 실제로 스프라이트가 있는 폼만 담아야 한다 — 그림 없는 폼을 주면
/// 2.5B 짜리 아이템을 쓰고 빈칸을 얻는다.
final class FormCatalogTests: XCTestCase {
    func testCatalogIsNotEmptyAndCoversBothKinds() {
        XCTAssertFalse(FormCatalog.all.isEmpty)
        XCTAssertFalse(FormCatalog.all.filter { $0.kind == .mega }.isEmpty)
        XCTAssertFalse(FormCatalog.all.filter { $0.kind == .gmax }.isEmpty)
    }

    /// 슬러그가 곧 스프라이트 파일명이라 중복되면 서로의 캐시를 덮어쓴다.
    func testSlugsAreUnique() {
        let slugs = FormCatalog.all.map(\.slug)
        XCTAssertEqual(Set(slugs).count, slugs.count)
    }

    /// 같은 종에 폼이 둘이면(리자몽 X/Y) 반드시 구분자가 있어야 한다 — 없으면 버튼 두 개가
    /// 똑같은 이름으로 뜬다.
    func testTwoFormsOfTheSameKindAlwaysHaveVariants() {
        let grouped = Dictionary(grouping: FormCatalog.all) { "\($0.speciesID)-\($0.kind.rawValue)" }
        for (key, forms) in grouped where forms.count > 1 {
            XCTAssertEqual(Set(forms.compactMap(\.variant)).count, forms.count,
                           "\(key): 같은 종·같은 종류의 폼이 여럿인데 구분자가 겹치거나 없다")
        }
    }

    func testCharizardHasBothMegaVariantsAndGmax() {
        let megas = FormCatalog.forms(speciesID: 6, kind: .mega)
        XCTAssertEqual(Set(megas.compactMap(\.variant)), ["X", "Y"])
        XCTAssertEqual(FormCatalog.forms(speciesID: 6, kind: .gmax).count, 1)
    }

    func testMostSpeciesHaveNoForms() {
        XCTAssertFalse(FormCatalog.has(speciesID: 16, kind: .mega))   // 구구
        XCTAssertFalse(FormCatalog.has(speciesID: 16, kind: .gmax))
    }

    /// 슬러그는 `<종슬러그>-mega|megax|megay|gmax` 꼴이어야 한다 — Showdown 경로를 그대로 만든다.
    func testSlugsMatchTheShowdownNamingScheme() {
        for form in FormCatalog.all {
            let suffix = form.slug.split(separator: "-").last.map(String.init) ?? ""
            let expected = form.kind == .gmax ? ["gmax"] : ["mega", "megax", "megay"]
            XCTAssertTrue(expected.contains(suffix), "\(form.slug) 의 접미가 규칙에서 벗어난다")
        }
    }

    func testDisplayNameAddsPrefixAndVariant() {
        let x = FormCatalog.forms(speciesID: 6, kind: .mega).first { $0.variant == "X" }!
        XCTAssertEqual(x.displayName(base: "리자몽", .ko), "메가 리자몽 X")
        XCTAssertEqual(x.displayName(base: "Charizard", .en), "Mega Charizard X")
        XCTAssertEqual(x.displayName(base: "リザードン", .ja), "メガリザードンX")
        let g = FormCatalog.forms(speciesID: 3, kind: .gmax).first!
        XCTAssertEqual(g.displayName(base: "이상해꽃", .ko), "거다이맥스 이상해꽃")
    }
}

/// 스프라이트 경로 — 폼은 종 번호가 아니라 슬러그로 캐시·요청돼야 한다. 종 번호로 키를 잡으면
/// 보통 모습과 메가가 같은 파일을 덮어쓴다.
final class FormSpriteKeyTests: XCTestCase {
    func testFormGetsItsOwnCacheKey() {
        let plain = SpriteStore.cacheKey(speciesID: 6, form: nil, animated: true, shiny: false)
        let mega = SpriteStore.cacheKey(speciesID: 6, form: "charizard-megax", animated: true, shiny: false)
        XCTAssertNotEqual(plain, mega, "폼이 종 번호와 같은 캐시 키를 쓰면 서로 덮어쓴다")
    }

    /// 폼끼리도 서로 달라야 한다(X 와 Y).
    func testEachFormHasADistinctKey() {
        let x = SpriteStore.cacheKey(speciesID: 6, form: "charizard-megax", animated: true, shiny: false)
        let y = SpriteStore.cacheKey(speciesID: 6, form: "charizard-megay", animated: true, shiny: false)
        XCTAssertNotEqual(x, y)
    }

    /// 폼 없는 키는 예전 그대로여야 한다 — 바뀌면 사용자의 스프라이트 캐시가 통째로 무효가 된다.
    func testPlainKeyIsUnchanged() {
        XCTAssertEqual(SpriteStore.cacheKey(speciesID: 25, form: nil, animated: true, shiny: false), "25-a")
        XCTAssertEqual(SpriteStore.cacheKey(speciesID: 25, form: nil, animated: false, shiny: true), "25-shs")
    }

    func testFormURLUsesTheFormSlug() {
        let url = SpriteStore.spriteURL(slug: "charizard-megax", animated: true, shiny: false)
        XCTAssertEqual(url?.absoluteString,
                       "https://play.pokemonshowdown.com/sprites/ani/charizard-megax.gif")
    }
}

@MainActor
final class FormStoreTests: XCTestCase {
    private func makeStore(speciesID: Int, items: [ShopItem: Int] = [:]) -> (PlayerStore, UUID) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("form-\(UUID().uuidString).json")
        let store = PlayerStore(fileURL: url, rng: SeededRNG(seed: 3),
                                now: { Date(timeIntervalSince1970: 0) })
        let individual = Individual(baseID: speciesID, speciesID: speciesID, pathIDs: [speciesID],
                                    nature: .serious, exp: 0,
                                    obtainedAt: Date(timeIntervalSince1970: 0), grade: .epic)
        store.addForTesting(individual)
        store.seedForTesting(wallet: 100_000_000_000, slots: 3, eggs: 0,
                             at: Date(timeIntervalSince1970: 0))
        for (item, count) in items {
            for _ in 0..<count { XCTAssertTrue(store.buy(item)) }
        }
        return (store, individual.id)
    }

    private func box(_ store: PlayerStore, _ id: UUID) -> Individual {
        store.state.box.first { $0.id == id }!
    }

    func testMegaStoneChangesTheFormAndIsConsumed() {
        let (store, id) = makeStore(speciesID: 6, items: [.megaStone: 1])
        let x = FormCatalog.forms(speciesID: 6, kind: .mega).first { $0.variant == "X" }!
        XCTAssertTrue(store.changeForm(individualID: id, to: x))
        XCTAssertEqual(box(store, id).form, "charizard-megax")
        XCTAssertEqual(store.count(of: .megaStone), 0, "쓴 메가스톤이 재고에서 빠져야 한다")
    }

    func testDynamaxMushroomUsesItsOwnItem() {
        let (store, id) = makeStore(speciesID: 6, items: [.dynamaxMushroom: 1])
        let g = FormCatalog.forms(speciesID: 6, kind: .gmax).first!
        XCTAssertTrue(store.changeForm(individualID: id, to: g))
        XCTAssertEqual(box(store, id).form, "charizard-gmax")
        XCTAssertEqual(store.count(of: .dynamaxMushroom), 0)
    }

    /// 메가스톤으로 거다이맥스를 살 수 없다 — 아이템이 종류마다 따로다.
    func testMegaStoneCannotBuyGigantamax() {
        let (store, id) = makeStore(speciesID: 6, items: [.megaStone: 1])
        let g = FormCatalog.forms(speciesID: 6, kind: .gmax).first!
        XCTAssertFalse(store.changeForm(individualID: id, to: g))
        XCTAssertNil(box(store, id).form)
        XCTAssertEqual(store.count(of: .megaStone), 1, "실패한 사용은 아이템을 쓰지 않는다")
    }

    /// 폼이 없는 종에는 못 쓴다 — 아이템만 날리면 안 된다.
    func testSpeciesWithoutAFormRejectsTheItem() {
        let (store, id) = makeStore(speciesID: 16, items: [.megaStone: 1])
        let anyMega = FormCatalog.all.first { $0.kind == .mega }!
        XCTAssertFalse(store.changeForm(individualID: id, to: anyMega))
        XCTAssertNil(box(store, id).form)
        XCTAssertEqual(store.count(of: .megaStone), 1)
    }

    /// 아이템이 없으면 바꿀 수 없다.
    func testWithoutTheItemNothingChanges() {
        let (store, id) = makeStore(speciesID: 6)
        let x = FormCatalog.forms(speciesID: 6, kind: .mega).first!
        XCTAssertFalse(store.changeForm(individualID: id, to: x))
        XCTAssertNil(box(store, id).form)
    }

    /// 이미 그 폼이면 후보에서 빠진다 — 같은 폼에 두 번째 스톤을 쓰게 두지 않는다.
    func testAlreadyInThatFormIsNotOfferedAgain() {
        let (store, id) = makeStore(speciesID: 6, items: [.megaStone: 2])
        let x = FormCatalog.forms(speciesID: 6, kind: .mega).first { $0.variant == "X" }!
        XCTAssertTrue(store.changeForm(individualID: id, to: x))
        XCTAssertFalse(store.formChoices(box(store, id), kind: .mega).contains(x))
        XCTAssertFalse(store.changeForm(individualID: id, to: x))
        XCTAssertEqual(store.count(of: .megaStone), 1, "두 번째 스톤은 그대로 남아야 한다")
    }

    /// 되돌리기는 공짜다 — X/Y 를 잘못 고른 게 영영 굳으면 안 된다.
    func testRevertIsFreeAndRestoresTheNormalForm() {
        let (store, id) = makeStore(speciesID: 6, items: [.megaStone: 1])
        let x = FormCatalog.forms(speciesID: 6, kind: .mega).first!
        XCTAssertTrue(store.changeForm(individualID: id, to: x))
        XCTAssertTrue(store.revertForm(individualID: id))
        XCTAssertNil(box(store, id).form)
        XCTAssertEqual(store.count(of: .megaStone), 0, "되돌리기가 아이템을 돌려주지는 않는다")
    }

    func testRevertingANormalIndividualDoesNothing() {
        let (store, id) = makeStore(speciesID: 6)
        XCTAssertFalse(store.revertForm(individualID: id))
    }

    /// 폼은 종에 달린 것 — 진화하면 풀려야 한다. 안 그러면 라이츄가 피카츄의 거다이맥스 슬러그를
    /// 물고 가 스프라이트가 안 나온다.
    func testEvolvingClearsTheForm() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("form-evo-\(UUID().uuidString).json")
        let store = PlayerStore(fileURL: url, rng: SeededRNG(seed: 3),
                                now: { Date(timeIntervalSince1970: 0) })
        // 피카츄(25) — 거다이맥스가 있고 라이츄(26)로 진화한다.
        let pikachu = Individual(baseID: 25, speciesID: 25, pathIDs: [25], nature: .serious,
                                 exp: 999_000_000, obtainedAt: Date(timeIntervalSince1970: 0),
                                 grade: .common)
        store.addForTesting(pikachu)
        store.seedForTesting(wallet: 100_000_000_000, slots: 3, eggs: 0,
                             at: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(store.buy(.dynamaxMushroom))
        let g = FormCatalog.forms(speciesID: 25, kind: .gmax).first!
        XCTAssertTrue(store.changeForm(individualID: pikachu.id, to: g))

        let line = EvoLine(baseID: 25,
                           tree: EvoNode(speciesID: 25, children: [EvoNode(speciesID: 26, children: [])]),
                           rarity: .common, names: [:])
        XCTAssertTrue(store.evolve(individualID: pikachu.id, to: 26, line: line))
        XCTAssertNil(store.state.box.first { $0.id == pikachu.id }?.form,
                     "진화했는데 옛 폼 슬러그가 남아 있다")
    }
}

/// 세이브 경계 — 관대 디코딩의 짝(CLAUDE.md). 모르는 폼 슬러그는 들이지 않는다.
final class FormDecodeGuardTests: XCTestCase {
    func testUnknownSlugIsDropped() {
        var individual = Individual(baseID: 6, speciesID: 6, pathIDs: [6], nature: .serious, exp: 0,
                                    obtainedAt: Date(timeIntervalSince1970: 0), grade: .epic)
        individual.form = "charizard-megaz"   // 존재하지 않는 폼
        XCTAssertNil(individual.sanitized().form)
    }

    /// 다른 종의 폼도 버린다 — 리자몽이 이상해꽃 메가 그림으로 뜨면 안 된다.
    func testFormOfAnotherSpeciesIsDropped() {
        var individual = Individual(baseID: 6, speciesID: 6, pathIDs: [6], nature: .serious, exp: 0,
                                    obtainedAt: Date(timeIntervalSince1970: 0), grade: .epic)
        individual.form = "venusaur-mega"
        XCTAssertNil(individual.sanitized().form)
    }

    func testKnownFormSurvives() {
        var individual = Individual(baseID: 6, speciesID: 6, pathIDs: [6], nature: .serious, exp: 0,
                                    obtainedAt: Date(timeIntervalSince1970: 0), grade: .epic)
        individual.form = "charizard-megax"
        XCTAssertEqual(individual.sanitized().form, "charizard-megax")
    }

    /// 실제 세이브 디코드 경로를 지난다 — `sanitized()` 를 직접 부르는 위 테스트들은
    /// 디코더가 그것을 호출하지 않아도 통과한다.
    func testDecodeStripsAnUnknownFormFromTheSave() throws {
        let json = """
        {"box":[{"id":"\(UUID().uuidString)","baseID":6,"speciesID":6,"pathIDs":[6],"shiny":false,
        "nature":"serious","exp":0,"obtainedAt":0,"grade":"epic","form":"charizard-megaz"}],
        "dex":[6],"earnedTokens":0,"spentTokens":0,"claimedTodayTokens":0,"lastDate":"2026-01-01",
        "installBaselineSet":true,"slots":3,"eggs":[],"inventory":{},"ownsShinyCharm":false,
        "starterChosen":true,"language":"ko"}
        """
        let state = try JSONDecoder().decode(PlayerState.self, from: Data(json.utf8))
        XCTAssertEqual(state.box.count, 1, "개체 자체는 버리지 않는다 — 폼만 떼어낸다")
        XCTAssertNil(state.box.first?.form)
    }
}

/// 배선 — 상점에서 파는 메가스톤·다이맥스 버섯을 **상세 화면에서 실제로 쓸 수 있는지**.
/// 스토어 메서드만 부르는 테스트는 UI 가 통째로 빠져도 통과한다(이 앱에서 그렇게 한 번 나갔다).
@MainActor
final class FormWiringTests: XCTestCase {
    private func makeStore(items: [ShopItem: Int]) -> (PlayerStore, Individual) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("form-wiring-\(UUID().uuidString).json")
        let store = PlayerStore(fileURL: url, rng: SeededRNG(seed: 5),
                                now: { Date(timeIntervalSince1970: 0) })
        let charizard = Individual(baseID: 6, speciesID: 6, pathIDs: [6], nature: .serious, exp: 0,
                                   obtainedAt: Date(timeIntervalSince1970: 0), grade: .epic)
        store.addForTesting(charizard)
        store.seedForTesting(wallet: 100_000_000_000, slots: 3, eggs: 0,
                             at: Date(timeIntervalSince1970: 0))
        for (item, count) in items {
            for _ in 0..<count { XCTAssertTrue(store.buy(item)) }
        }
        return (store, charizard)
    }

    private func renderedFormButtons(_ store: PlayerStore,
                                     _ individual: Individual) -> [(title: String, action: () -> Void)] {
        FormButton.resetConstructed()
        let current = store.state.box.first { $0.id == individual.id }!
        let host = NSHostingView(rootView: IndividualDetailView(
            store: store, individual: current, line: nil, onNeedLine: { _ in }, onBack: { })
            .frame(width: PopoverMetrics.width))
        host.layoutSubtreeIfNeeded()
        // SwiftUI 는 레이아웃 중 body 를 여러 번 평가한다 — 같은 버튼이 여러 번 기록되므로
        // 제목 기준으로 접는다(어떤 버튼이 있나를 재는 것이지 몇 번 그렸나를 재는 게 아니다).
        var seen = Set<String>()
        return FormButton.constructed.filter { seen.insert($0.title).inserted }
    }

    /// 메가스톤을 들고 리자몽 상세를 열면 X·Y 버튼이 뜨고, 누르면 실제로 폼이 바뀐다.
    func testMegaButtonsAppearAndChangeTheForm() {
        let (store, charizard) = makeStore(items: [.megaStone: 1])
        let buttons = renderedFormButtons(store, charizard)
        XCTAssertEqual(buttons.count, 2, "리자몽은 메가 X/Y 두 개가 떠야 한다: \(buttons.map(\.title))")
        buttons[0].action()
        XCTAssertNotNil(store.state.box.first { $0.id == charizard.id }?.form,
                        "버튼을 눌렀는데 폼이 안 바뀐다 — 버튼이 스토어에 안 이어져 있다")
    }

    func testGigantamaxButtonAppearsWithTheMushroom() {
        let (store, charizard) = makeStore(items: [.dynamaxMushroom: 1])
        let buttons = renderedFormButtons(store, charizard)
        XCTAssertEqual(buttons.count, 1, buttons.map(\.title).description)
        buttons[0].action()
        XCTAssertEqual(store.state.box.first { $0.id == charizard.id }?.form, "charizard-gmax")
    }

    /// 아이템이 없으면 버튼을 내지 않는다 — 눌러도 아무 일 없는 버튼을 두지 않는다.
    func testNoFormButtonsWithoutItems() {
        let (store, charizard) = makeStore(items: [:])
        XCTAssertTrue(renderedFormButtons(store, charizard).isEmpty)
    }
}

/// 지방 모습에는 메가·거다이맥스가 없다. 메가는 칼로스, 거다이맥스는 가라르 지방의 현상이고
/// 둘 다 원종에만 붙는다 — 가라르 나옹은 거다이맥스하지 못한다(사용자 지적).
@MainActor
final class RegionalFormsHaveNoMegaOrGmaxTests: XCTestCase {
    private func makeStore(region: Region?) -> (PlayerStore, UUID) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("region-form-\(UUID().uuidString).json")
        let store = PlayerStore(fileURL: url, rng: SeededRNG(seed: 7),
                                now: { Date(timeIntervalSince1970: 0) })
        var meowth = Individual(baseID: 52, speciesID: 52, pathIDs: [52], nature: .serious, exp: 0,
                                obtainedAt: Date(timeIntervalSince1970: 0), grade: .common)
        meowth.region = region
        store.addForTesting(meowth)
        store.seedForTesting(wallet: 100_000_000_000, slots: 3, eggs: 0,
                             at: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(store.buy(.dynamaxMushroom))
        return (store, meowth.id)
    }

    private func individual(_ store: PlayerStore, _ id: UUID) -> Individual {
        store.state.box.first { $0.id == id }!
    }

    func testKantonianMeowthCanGigantamax() {
        let (store, id) = makeStore(region: nil)
        XCTAssertTrue(store.hasForms(individual(store, id), kind: .gmax))
        let g = FormCatalog.forms(speciesID: 52, kind: .gmax).first!
        XCTAssertTrue(store.changeForm(individualID: id, to: g))
        XCTAssertEqual(individual(store, id).form, "meowth-gmax")
    }

    func testGalarianMeowthCannotGigantamax() {
        let (store, id) = makeStore(region: .galar)
        XCTAssertFalse(store.hasForms(individual(store, id), kind: .gmax),
                       "가라르 나옹에 거다이맥스 칸이 뜬다")
        XCTAssertTrue(store.formChoices(individual(store, id), kind: .gmax).isEmpty)
    }

    /// 버튼을 숨기는 것만으로는 부족하다 — 실행 경로도 막아야 아이템이 안 날아간다.
    func testGalarianMeowthRejectsTheMushroomAndKeepsIt() {
        let (store, id) = makeStore(region: .galar)
        let g = FormCatalog.forms(speciesID: 52, kind: .gmax).first!
        XCTAssertFalse(store.changeForm(individualID: id, to: g))
        XCTAssertNil(individual(store, id).form)
        XCTAssertEqual(store.count(of: .dynamaxMushroom), 1, "실패한 사용이 다이맥스 버섯을 먹었다")
    }

    /// 알로라 나옹도 마찬가지 — 지방이 어디든 규칙은 같다.
    func testAlolanMeowthCannotGigantamaxEither() {
        let (store, id) = makeStore(region: .alola)
        XCTAssertFalse(store.hasForms(individual(store, id), kind: .gmax))
    }

    /// 겹치는 종을 앞으로도 놓치지 않게 — 메가·거다이맥스와 지방 모습을 둘 다 가진 종은
    /// 반드시 이 규칙을 지나야 한다. 지금은 나옹뿐이지만 카탈로그가 늘어도 이 테스트가 잡는다.
    func testEverySpeciesWithBothCatalogsIsGatedByRegion() {
        let formSpecies = Set(FormCatalog.all.map(\.speciesID))
        let regionSpecies = Set(RegionalFormCatalog.all.map(\.speciesID))
        let overlap = formSpecies.intersection(regionSpecies)
        XCTAssertFalse(overlap.isEmpty, "겹치는 종이 없으면 이 테스트가 아무것도 안 지킨다")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("overlap-\(UUID().uuidString).json")
        let store = PlayerStore(fileURL: url, rng: SeededRNG(seed: 7),
                                now: { Date(timeIntervalSince1970: 0) })
        for speciesID in overlap {
            for region in RegionalFormCatalog.regions(speciesID: speciesID) {
                var i = Individual(baseID: speciesID, speciesID: speciesID, pathIDs: [speciesID],
                                   nature: .serious, exp: 0,
                                   obtainedAt: Date(timeIntervalSince1970: 0), grade: .common)
                i.region = region
                for kind in FormKind.allCases {
                    XCTAssertFalse(store.hasForms(i, kind: kind),
                                   "#\(speciesID) \(region.rawValue) 에 \(kind.rawValue) 이 열려 있다")
                }
            }
        }
    }
}
