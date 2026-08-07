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

    /// 같은 종에 폼이 둘이면(리자몽 X/Y, 아르세우스 17타입) 화면에 **서로 다른 이름**으로
    /// 떠야 한다 — 안 그러면 버튼 여럿이 똑같은 이름으로 뜬다. 구분자가 `variant`(X/Y)든
    /// `label`(폼 이름)이든 상관없이, 최종 표시 이름으로 확인하는 게 실제로 지키려는 것이다.
    func testFormsOfTheSameSpeciesShowDistinctNames() {
        let grouped = Dictionary(grouping: FormCatalog.all, by: \.speciesID)
        for (species, forms) in grouped where forms.count > 1 {
            for lang in AppLanguage.allCases {
                let names = forms.map { $0.displayName(base: "X", lang) }
                XCTAssertEqual(Set(names).count, names.count,
                               "#\(species) \(lang): 폼 이름이 겹친다 — \(names)")
            }
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

    /// 슬러그는 `<종슬러그>-<폼>` 꼴이어야 한다 — Showdown 경로를 그대로 만든다.
    /// 메가·거다이맥스는 접미가 정해져 있고, 나머지는 폼 이름이 그대로 접미가 된다.
    func testSlugsMatchTheShowdownNamingScheme() {
        for form in FormCatalog.all {
            let parts = form.slug.split(separator: "-")
            XCTAssertGreaterThan(parts.count, 1, "\(form.slug) 에 폼 접미가 없다")
            XCTAssertFalse(form.slug.contains(" "), "\(form.slug) 에 공백이 있다 — URL 이 깨진다")
            XCTAssertEqual(form.slug, form.slug.lowercased(), "\(form.slug) 에 대문자가 있다")
            guard form.kind == .mega || form.kind == .gmax else { continue }
            let suffix = String(parts.last!)
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

/// 배선 — 상점에서 파는 메가스톤·다이버섯을 **상세 화면에서 실제로 쓸 수 있는지**.
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

    /// 물어 온 폼 도구도 **실제 화면에서** 버튼이 되어야 한다. 스토어만 잠그면 상세 화면이
    /// 새 갈래를 안 그려도 테스트가 통과한다 — 이 저장소가 이미 두 번 밟은 부류다.
    func testForagedFormsRenderAndWork() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("form-foraged-\(UUID().uuidString).json")
        let store = PlayerStore(fileURL: url, rng: SeededRNG(seed: 5),
                                now: { Date(timeIntervalSince1970: 0) })
        let giratina = Individual(baseID: 487, speciesID: 487, pathIDs: [487], nature: .serious,
                                  exp: 0, obtainedAt: Date(timeIntervalSince1970: 0),
                                  grade: .legendary)
        store.addForTesting(giratina)
        store.grantForTesting(FormItem.griseousCore)

        let buttons = renderedFormButtons(store, giratina)
        XCTAssertEqual(buttons.count, 1, "오리진 버튼이 떠야 한다: \(buttons.map(\.title))")
        // 개수 표기가 붙으면 소모품으로 읽힌다 — 물어 온 도구는 안 없어진다.
        XCTAssertFalse(buttons[0].title.contains("×"), "물어 온 도구에 개수가 붙었다: \(buttons[0].title)")
        buttons[0].action()
        XCTAssertEqual(store.state.box.first { $0.id == giratina.id }?.form, "giratina-origin")
    }

    /// 합체 상대가 없으면 **버튼이 안 나온다** — 대신 이유가 뜬다(그건 별도 테스트).
    func testFusionFormRendersNoButtonWithoutThePartner() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("form-fusion-\(UUID().uuidString).json")
        let store = PlayerStore(fileURL: url, rng: SeededRNG(seed: 5),
                                now: { Date(timeIntervalSince1970: 0) })
        let kyurem = Individual(baseID: 646, speciesID: 646, pathIDs: [646], nature: .serious,
                                exp: 0, obtainedAt: Date(timeIntervalSince1970: 0),
                                grade: .legendary)
        store.addForTesting(kyurem)
        store.grantForTesting(FormItem.dnaSplicers)
        XCTAssertTrue(renderedFormButtons(store, kyurem).isEmpty, "상대가 없는데 누를 수 있다")

        // 제크로무를 넣으면 블랙만 열린다.
        let zekrom = Individual(baseID: 644, speciesID: 644, pathIDs: [644], nature: .serious,
                                exp: 0, obtainedAt: Date(timeIntervalSince1970: 0),
                                grade: .legendary)
        store.addForTesting(zekrom)
        let buttons = renderedFormButtons(store, kyurem)
        XCTAssertEqual(buttons.count, 1, "블랙 하나만 떠야 한다: \(buttons.map(\.title))")
        buttons[0].action()
        XCTAssertEqual(store.state.box.first { $0.id == kyurem.id }?.form, "kyurem-black")
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
        XCTAssertEqual(store.count(of: .dynamaxMushroom), 1, "실패한 사용이 다이버섯을 먹었다")
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

/// 폼 도구 — 진화 도구와 **성격이 반대다**. 진화는 못 되돌리지만 폼은 되돌릴 수 있고,
/// 그래서 도구도 없어지지 않는다.
@MainActor
final class FormItemStoreTests: XCTestCase {
    private func makeStore(_ species: Int...) -> (PlayerStore, [UUID]) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("formitem-\(UUID().uuidString).json")
        let store = PlayerStore(fileURL: url, rng: SeededRNG(seed: 3),
                                now: { Date(timeIntervalSince1970: 0) })
        let ids = species.map { sp -> UUID in
            let i = Individual(baseID: sp, speciesID: sp, pathIDs: [sp], nature: .serious, exp: 0,
                               obtainedAt: Date(timeIntervalSince1970: 0), grade: .legendary)
            store.addForTesting(i)
            return i.id
        }
        return (store, ids)
    }

    private func form(_ slug: String) -> PokemonForm { FormCatalog.form(slug: slug)! }

    /// **물어 온 폼 도구는 없어지지 않는다.** 되돌릴 수 있는 변화를 소모품으로 잠그면
    /// 오리진으로 바꿨다가 되돌린 순간 다시는 못 돌아간다.
    func testForagedFormItemsAreNotConsumed() {
        let (store, ids) = makeStore(487)                   // 기라티나
        store.grantForTesting(.griseousCore)
        XCTAssertTrue(store.changeForm(individualID: ids[0], to: form("giratina-origin")))
        XCTAssertEqual(store.count(of: FormItem.griseousCore), 1, "폼 도구가 없어졌다")
    }

    /// 되돌리고 **다시 바꿀 수 있어야** 한다 — 이게 진화와 갈리는 지점이다.
    func testFormsCanBeRevertedAndReapplied() {
        let (store, ids) = makeStore(487)
        store.grantForTesting(.griseousCore)
        let origin = form("giratina-origin")
        XCTAssertTrue(store.changeForm(individualID: ids[0], to: origin))
        XCTAssertTrue(store.revertForm(individualID: ids[0]))
        XCTAssertNil(store.state.box[0].form)
        XCTAssertTrue(store.changeForm(individualID: ids[0], to: origin), "되돌린 뒤 다시 못 바꾼다")
    }

    /// 도구가 없으면 못 바꾼다.
    func testWithoutTheItemNothingHappens() {
        let (store, ids) = makeStore(487)
        XCTAssertFalse(store.changeForm(individualID: ids[0], to: form("giratina-origin")))
        XCTAssertNil(store.state.box[0].form)
    }

    /// 타입 세트는 **하나가 하나를 연다** — 원작에 플레이트가 17장 따로 있는 그대로다.
    /// 불꽃플레이트로 물 아르세우스가 되면 나머지 16장이 게임에서 의미를 잃는다.
    func testOnePlateOpensExactlyOneArceusType() {
        let (store, ids) = makeStore(493)
        store.grantForTesting(.plateFire)
        let types = FormCatalog.forms(speciesID: 493, kind: .typeSet)
        XCTAssertEqual(types.count, 17)
        let fire = types.first { $0.slug == "arceus-fire" }!
        XCTAssertTrue(store.changeForm(individualID: ids[0], to: fire))
        for other in types where other.slug != "arceus-fire" {
            XCTAssertFalse(store.canChange(store.state.box[0], to: other),
                           "\(other.slug) 가 불꽃플레이트로 열린다")
        }
        XCTAssertEqual(store.count(of: FormItem.plateFire), 1, "플레이트가 없어졌다")
    }

    /// 타입 세트의 도구는 폼과 **일대일**이어야 한다 — 하나가 여럿을 열면 나머지 도구가
    /// 게임에서 사라지고, 규칙이 도구마다 달라진다.
    func testTypeSetItemsMapOneToOne() {
        let typeSet = FormCatalog.all.filter { $0.kind == .typeSet }
        var byItem: [FormItem: Int] = [:]
        for form in typeSet {
            guard case .foraged(let item) = form.source else {
                return XCTFail("\(form.slug) 이 상점 도구를 쓴다")
            }
            byItem[item, default: 0] += 1
        }
        XCTAssertEqual(byItem.count, typeSet.count, "타입 세트 도구가 폼보다 적다")
        XCTAssertTrue(byItem.values.allSatisfy { $0 == 1 })
    }

    /// 빛의거울 하나가 네 종의 영물폼을 연다.
    func testRevealGlassCoversAllFourTherians() {
        for species in [641, 642, 645, 905] {
            let (store, ids) = makeStore(species)
            store.grantForTesting(.revealGlass)
            let therian = FormCatalog.forms(speciesID: species, kind: .legendary)[0]
            XCTAssertTrue(store.changeForm(individualID: ids[0], to: therian), "#\(species)")
        }
    }
}

/// 합체 폼 — 도구만으로는 안 되고 **상대 포켓몬이 박스에 있어야** 한다.
@MainActor
final class FusionFormTests: XCTestCase {
    private func makeStore(_ species: [Int]) -> (PlayerStore, UUID) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("fusion-\(UUID().uuidString).json")
        let store = PlayerStore(fileURL: url, rng: SeededRNG(seed: 3),
                                now: { Date(timeIntervalSince1970: 0) })
        var first: UUID?
        for sp in species {
            let i = Individual(baseID: sp, speciesID: sp, pathIDs: [sp], nature: .serious, exp: 0,
                               obtainedAt: Date(timeIntervalSince1970: 0), grade: .legendary)
            store.addForTesting(i)
            if first == nil { first = i.id }
        }
        return (store, first!)
    }

    /// 카탈로그가 실제로 짝을 맞게 적고 있나 — 큐레무 블랙은 제크로무(644), 화이트는 레시라무(643).
    func testTheSixFusionFormsNameTheRightPartner() {
        let expected: [String: Int] = [
            "kyurem-black": 644, "kyurem-white": 643,
            "necrozma-duskmane": 791, "necrozma-dawnwings": 792,
            "calyrex-ice": 896, "calyrex-shadow": 897,
        ]
        let fusions = FormCatalog.all.filter { $0.fusionPartner != nil }
        XCTAssertEqual(fusions.count, expected.count, "합체 폼 개수가 달라졌다")
        for form in fusions {
            XCTAssertEqual(form.fusionPartner, expected[form.slug], "\(form.slug) 의 상대가 틀렸다")
        }
    }

    /// 상대가 없으면 도구가 있어도 못 바꾼다.
    func testFusionIsBlockedWithoutThePartner() {
        let (store, kyurem) = makeStore([646])              // 큐레무만
        store.grantForTesting(.dnaSplicers)
        let black = FormCatalog.form(slug: "kyurem-black")!
        XCTAssertFalse(store.canChange(store.state.box[0], to: black))
        XCTAssertFalse(store.changeForm(individualID: kyurem, to: black))
        XCTAssertNil(store.state.box[0].form)
    }

    /// 상대가 있으면 바뀌고, **상대는 사라지지 않는다** — 먹어 버리면 폼을 되돌릴 수가 없다.
    func testFusionWorksWithThePartnerAndKeepsIt() {
        let (store, kyurem) = makeStore([646, 644])         // 큐레무 + 제크로무
        store.grantForTesting(.dnaSplicers)
        let black = FormCatalog.form(slug: "kyurem-black")!
        XCTAssertTrue(store.changeForm(individualID: kyurem, to: black))
        XCTAssertEqual(store.state.box[0].form, "kyurem-black")
        XCTAssertTrue(store.state.box.contains { $0.speciesID == 644 }, "제크로무가 사라졌다")
        XCTAssertTrue(store.revertForm(individualID: kyurem))
    }

    /// 짝이 어긋나면 안 된다 — 제크로무를 가졌다고 화이트가 열리면 짝 검사가 무의미하다.
    func testTheWrongPartnerDoesNotUnlockTheOtherForm() {
        let (store, _) = makeStore([646, 644])              // 제크로무만 있다
        store.grantForTesting(.dnaSplicers)
        XCTAssertTrue(store.canChange(store.state.box[0], to: FormCatalog.form(slug: "kyurem-black")!))
        XCTAssertFalse(store.canChange(store.state.box[0], to: FormCatalog.form(slug: "kyurem-white")!))
    }

    /// 못 바꾸는 폼도 **목록에는 남아야** 한다 — 빼 버리면 큐레무 블랙의 존재를 알 수가 없다.
    func testBlockedFusionFormsStayVisible() {
        let (store, _) = makeStore([646])
        let choices = store.formChoices(store.state.box[0], kind: .legendary)
        XCTAssertEqual(Set(choices.map(\.slug)), ["kyurem-black", "kyurem-white"])
    }
}

/// 폼 도구를 얻는 길 — 진화 도구와 같이 파트너가 물어 온다.
final class FormForageTests: XCTestCase {
    /// **화면에 있는 모든 폼 도구는 얻을 수 있어야 한다.** 하나라도 못 얻으면 그 폼은
    /// 목록에만 존재하고 영영 못 쓴다.
    func testEveryFormItemIsObtainable() {
        var reachable: Set<FormItem> = []
        for species in Set(FormCatalog.all.map(\.speciesID)) {
            reachable.formUnion(FormForageCatalog.items(speciesID: species, region: nil).map(\.item))
        }
        for item in FormItem.allCases {
            XCTAssertTrue(reachable.contains(item), "\(item) 을 물어 오는 종이 없다")
        }
    }

    /// 상점에서 파는 메가스톤·다이버섯은 채집 대상이 아니다 — 섞이면 상점이 무의미해진다.
    func testShopFormsAreNotForaged() {
        let charizard = FormForageCatalog.items(speciesID: 6, region: nil)
        XCTAssertTrue(charizard.isEmpty, "메가스톤이 채집으로 샌다")
    }

    /// 지방 모습은 폼을 못 가지므로 폼 도구도 안 물어 온다.
    func testRegionalIndividualsForageNoFormItems() {
        XCTAssertFalse(FormForageCatalog.items(speciesID: 25, region: nil).isEmpty)
        XCTAssertTrue(FormForageCatalog.items(speciesID: 25, region: .alola).isEmpty)
    }

    /// 전설의 폼 도구는 훨씬 드물어야 한다 — 같은 확률이면 기라티나 오리진이 피카츄 모자와
    /// 같은 값이 된다.
    func testLegendaryFormItemsAreRarerThanOrdinaryOnes() {
        for ribbon in Ribbon.allCases {
            XCTAssertLessThan(ribbon.legendaryFormPermille, ribbon.foragePermille, "\(ribbon)")
            XCTAssertGreaterThan(ribbon.legendaryFormPermille, 0, "\(ribbon): 아예 안 나오면 안 된다")
        }
    }

    /// 각 후보는 **자기 갈래의 확률로** 판정돼야 한다.
    func testEachCandidateUsesItsOwnRate() {
        let legendary = [(item: FormItem.griseousCore, kind: FormKind.legendary)]
        let ordinary = [(item: FormItem.plateFire, kind: FormKind.typeSet)]
        let between = Double(Ribbon.bond.legendaryFormPermille + 1) / 1000
        XCTAssertNil(PlayerStore.forageFormItem(ribbon: .bond, candidates: legendary,
                                                roll: between, pick: 0))
        XCTAssertEqual(PlayerStore.forageFormItem(ribbon: .bond, candidates: ordinary,
                                                  roll: between, pick: 0), .plateFire)
    }

    func testNoCandidatesMeansNothing() {
        XCTAssertNil(PlayerStore.forageFormItem(ribbon: .lifelong, candidates: [], roll: 0, pick: 0))
    }
}

/// 인벤토리는 한 사전을 셋이 나눠 쓴다 — 키가 겹치면 한 칸을 두고 다툰다.
final class InventoryKeyCollisionTests: XCTestCase {
    func testShopEvolutionAndFormItemKeysAreDisjoint() {
        let shop = Set(ShopItem.allCases.map(\.rawValue))
        let evo = Set(EvolutionItem.allCases.map(\.rawValue))
        let form = Set(FormItem.allCases.map(\.rawValue))
        XCTAssertTrue(shop.isDisjoint(with: evo), "상점↔진화 키 충돌: \(shop.intersection(evo))")
        XCTAssertTrue(shop.isDisjoint(with: form), "상점↔폼 키 충돌: \(shop.intersection(form))")
        XCTAssertTrue(evo.isDisjoint(with: form), "진화↔폼 키 충돌: \(evo.intersection(form))")
    }
}

/// [회귀] 상세 화면이 폼 목록에 잡아먹히지 않는지. 폼마다 "○○ 필요 · 파트너로 두면 물어 와요"를
/// 붙였더니 피카츄(15개)에서 같은 문장이 14번 반복돼 상세 스크롤이 1,800px 이 됐다 —
/// 팝오버 높이는 320pt 다. 이유는 **섹션에 한 번만** 적고 셋 이상이면 접는다.
@MainActor
final class FormSectionFoldingTests: XCTestCase {
    private func makeStore(_ species: Int) -> (PlayerStore, Individual) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("fold-\(UUID().uuidString).json")
        let store = PlayerStore(fileURL: url, rng: SeededRNG(seed: 1),
                                now: { Date(timeIntervalSince1970: 0) })
        let i = Individual(baseID: species, speciesID: species, pathIDs: [species],
                           nature: .serious, obtainedAt: Date(timeIntervalSince1970: 0),
                           grade: .rare)
        store.addForTesting(i)
        return (store, i)
    }

    /// 못 여는 폼들이 **무엇을 기다리는지** 도구별로 세어 한 줄로 — 15줄이 1줄이 된다.
    func testTheSummaryCountsBlockedFormsByItem() {
        let (store, pikachu) = makeStore(25)
        let forms = FormKind.allCases.flatMap { store.formChoices(pikachu, kind: $0) }
        XCTAssertEqual(forms.count, 15, "피카츄는 변장 14 + 거다이맥스 1")
        let text = IndividualDetailView.formNeedSummary(forms, usable: [], store: store, l: L(.ko))
        XCTAssertNotNil(text)
        XCTAssertTrue(text!.contains("\(FormItem.costumeTrunk.label(.ko)) 14"), text!)
        XCTAssertTrue(text!.contains("\(ShopItem.dynamaxMushroom.label(.ko)) 1"), text!)
        // 한 줄이어야 한다 — 줄바꿈이 들어가면 접은 의미가 없다.
        XCTAssertFalse(text!.contains("\n"))
    }

    /// 전부 열 수 있으면 할 말이 없다.
    func testNoSummaryWhenEverythingIsUsable() {
        let (store, pikachu) = makeStore(25)
        let forms = FormKind.allCases.flatMap { store.formChoices(pikachu, kind: $0) }
        XCTAssertNil(IndividualDetailView.formNeedSummary(forms, usable: forms,
                                                          store: store, l: L(.ko)))
    }

    /// 접는 문턱 — 짧은 목록은 접지 않는다(접으면 한 번 더 누르게만 만든다).
    /// 실제 분포가 5개와 15개 사이에서 갈리므로, 접히는 건 아르세우스·실버디·피카츄 셋뿐이어야 한다.
    func testOnlyTheThreeLongListsFold() {
        var folded: [Int] = [], open: [Int] = []
        for species in Set(FormCatalog.all.map(\.speciesID)) {
            let (store, individual) = makeStore(species)
            let count = FormKind.allCases.flatMap { store.formChoices(individual, kind: $0) }.count
            if count >= IndividualDetailView.formFoldThreshold { folded.append(species) }
            else if count > 0 { open.append(species) }
        }
        XCTAssertEqual(Set(folded), [493, 773, 25], "접히는 종이 달라졌다: \(folded.sorted())")
        XCTAssertTrue(open.contains(6), "리자몽(메가 X/Y + 거다이맥스)이 접혔다")
        XCTAssertTrue(open.contains(646), "큐레무가 접혔다")
    }

    /// 상세가 **스크롤 없이** 들어가야 한다. 팝오버 본문은 320pt 이고, 폼을 펼쳐 두면
    /// 피카츄 하나로 그 다섯 배를 넘겼다.
    func testTheDetailScreenFitsWithoutScrolling() {
        let (store, pikachu) = makeStore(25)
        let host = NSHostingView(rootView: IndividualDetailView(
            store: store, individual: pikachu, line: nil, onNeedLine: { _ in }, onBack: {})
            .frame(width: PopoverMetrics.contentWidth))
        host.layoutSubtreeIfNeeded()
        XCTAssertLessThan(host.fittingSize.height, 420,
                          "상세가 \(Int(host.fittingSize.height))pt 다 — 폼 목록이 다시 펼쳐졌다")
    }
}

/// 사탕 진행도 — 홈과 상세가 같은 계산을 쓴다.
final class CandyProgressDisplayTests: XCTestCase {
    private func individual(progress: Int) -> Individual {
        var i = Individual(baseID: 25, speciesID: 25, pathIDs: [25], nature: .serious,
                           obtainedAt: Date(timeIntervalSince1970: 0), grade: .common)
        i.candyProgress = progress
        return i
    }

    func testProgressIsTheFractionOfTheNextCandy() {
        let half = Ribbon.bond.tokensPerCandy / 2
        XCTAssertEqual(IndividualDetailView.candyProgress(individual(progress: half), .bond),
                       0.5, accuracy: 0.01)
        XCTAssertEqual(IndividualDetailView.candyProgress(individual(progress: 0), .bond), 0)
    }

    /// 리본이 오르면 필요량이 줄어 이미 쌓은 진행분이 100% 를 넘을 수 있다 — 게이지가 넘치면 안 된다.
    func testProgressIsClampedWhenTheRibbonUpgrades() {
        let carried = Ribbon.bond.tokensPerCandy      // 반려 기준으로는 필요량의 7.5배
        XCTAssertEqual(IndividualDetailView.candyProgress(individual(progress: carried), .lifelong), 1)
    }
}

/// [회귀] 경험치 바와 사탕 게이지가 **서로 다른 물건으로 보여야** 한다. 처음엔 둘 다 같은
/// `ProgressView` 였고 홈에서는 색까지 주황으로 같아서, 어느 쪽이 무엇인지 읽히지 않았다.
/// 색·높이·폭 셋 중 하나만 갈라도 부족해서 세 가지를 한꺼번에 나눴다.
@MainActor
final class ExpVersusCandyHierarchyTests: XCTestCase {
    /// 사탕 게이지는 경험치 바(5pt)보다 확실히 얇아야 한다 — 1pt 차이는 눈에 안 띈다.
    func testTheCandyMeterIsThinnerThanTheExpBar() {
        XCTAssertLessThanOrEqual(CandyMeter.height, 3)
        XCTAssertLessThan(CandyMeter.height, 5, "경험치 바와 두께가 같아지면 다시 헷갈린다")
    }

    /// 두 화면이 같은 부품을 써야 한다 — 홈과 상세가 따로 그리면 한쪽만 고쳐지고 갈라진다.
    func testBothScreensRenderTheSameMeter() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("meter-\(UUID().uuidString).json")
        let store = PlayerStore(fileURL: url, rng: SeededRNG(seed: 1),
                                now: { Date(timeIntervalSince1970: 0) })
        var pikachu = Individual(baseID: 25, speciesID: 25, pathIDs: [25], nature: .serious,
                                 obtainedAt: Date(timeIntervalSince1970: 0), grade: .rare)
        pikachu.candyProgress = Ribbon.lifelong.tokensPerCandy / 4
        pikachu.partnerSeconds = Ribbon.lifelong.requiredPartnerSeconds
        store.addForTesting(pikachu)
        store.setPartner(pikachu.id)

        // 같은 계산을 쓴다 — 화면마다 다른 분모를 쓰면 같은 개체가 두 값을 갖게 된다.
        let shown = store.state.box[0]
        XCTAssertEqual(IndividualDetailView.candyProgress(shown, .lifelong), 0.25, accuracy: 0.01)

        let host = NSHostingView(rootView: CandyMeter(progress: 0.25, remaining: "15M",
                                                      label: "다음 사탕")
            .frame(width: PopoverMetrics.contentWidth))
        host.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(host.fittingSize.height, 0)
        // 한 줄에 들어가야 한다 — 두 줄이 되면 경험치 블록만큼 자리를 먹는다.
        XCTAssertLessThan(host.fittingSize.height, 20,
                          "사탕 줄이 \(Int(host.fittingSize.height))pt 다 — 한 줄을 넘었다")
    }
}

/// [회귀] 진화 갈래가 많은 종의 상세가 길어지지 않는지. 갈래마다 전폭 버튼과
/// "○○의돌 필요 · 파트너로 두면 물어 와요" 한 줄을 냈더니 이브이(8갈래)에서 605pt 가 됐다 —
/// 팝오버 본문은 320pt 다. 갈 수 있는 곳만 버튼으로 내고 나머지는 한 줄로 접는다.
@MainActor
final class EvolutionBranchFoldingTests: XCTestCase {
    /// 이브이의 여덟 갈래 — 돌 다섯(그중 물의돌만 보유), 친밀도 셋.
    private func eeveeLine() -> EvoLine {
        let stones: [(Int, String)] = [(134, "water-stone"), (135, "thunder-stone"),
                                       (136, "fire-stone"), (470, "leaf-stone"), (471, "ice-stone")]
        var children = stones.map { EvoNode(speciesID: $0.0, children: [], requirementRaw: .item($0.1)) }
        children += [196, 197, 700].map { EvoNode(speciesID: $0, children: [], requirementRaw: .friendship) }
        return EvoLine(baseID: 133, tree: EvoNode(speciesID: 133, children: children),
                       rarity: .common, names: [:])
    }

    private func makeEevee() -> (PlayerStore, Individual) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("eevee-\(UUID().uuidString).json")
        let store = PlayerStore(fileURL: url, rng: SeededRNG(seed: 1),
                                now: { Date(timeIntervalSince1970: 1_000_000) })
        var eevee = Individual(baseID: 133, speciesID: 133, pathIDs: [133], nature: .serious,
                               exp: 400_000_000, obtainedAt: Date(timeIntervalSince1970: 0),
                               grade: .common)
        eevee.partnerSeconds = Ribbon.lifelong.requiredPartnerSeconds
        store.addForTesting(eevee)
        store.setPartner(eevee.id)
        store.grantForTesting(EvolutionItem.waterStone)
        return (store, store.state.box[0])
    }

    /// 막힌 갈래들이 **한 줄**로 접힌다 — 필요한 것만 중복 없이.
    func testBlockedBranchesFoldIntoOneLine() {
        let (store, _) = makeEevee()
        let line = eeveeLine()
        let text = IndividualDetailView.blockedSummary([135, 136, 470, 471], line: line, store: store)
        XCTAssertFalse(text.contains("\n"), "접힌 줄이 여러 줄이다: \(text)")
        XCTAssertTrue(text.contains(EvolutionItem.thunderStone.label(.ko)), text)
        XCTAssertTrue(text.contains(EvolutionItem.iceStone.label(.ko)), text)
        // 물의돌은 이미 가졌으니 막힌 목록에 없다.
        XCTAssertFalse(text.contains(EvolutionItem.waterStone.label(.ko)), text)
    }

    /// 같은 조건이 여럿이면 한 번만 적는다 — 친밀도 셋이 "함께한 시간"을 세 번 쓰면 안 된다.
    func testTheSummaryDeduplicates() {
        let (store, _) = makeEevee()
        let text = IndividualDetailView.blockedSummary([196, 197, 700], line: eeveeLine(), store: store)
        XCTAssertEqual(text, L(.ko).evolveNeedsFriendshipShort, text)
    }

    /// 조건 이름은 문장이 아니라 **이름**이어야 한 줄에 여럿이 들어간다.
    func testShortNeedIsANameNotASentence() {
        let short = IndividualDetailView.shortNeed(.item(.thunderStone), l: L(.ko))
        XCTAssertEqual(short, EvolutionItem.thunderStone.label(.ko))
        XCTAssertFalse(short.contains("파트너"), "짧은 이름에 안내 문장이 섞였다: \(short)")
    }

    /// 갈래가 가장 많은 종에서도 상세가 감당할 높이여야 한다. 접기 전에는 605pt 였다.
    func testTheMostBranchedSpeciesStaysManageable() {
        let (store, eevee) = makeEevee()
        let host = NSHostingView(rootView: IndividualDetailView(
            store: store, individual: eevee, line: eeveeLine(), onNeedLine: { _ in }, onBack: {})
            .frame(width: PopoverMetrics.contentWidth))
        host.layoutSubtreeIfNeeded()
        XCTAssertLessThan(host.fittingSize.height, 500,
                          "이브이 상세가 \(Int(host.fittingSize.height))pt 다 — 막힌 갈래가 다시 펼쳐졌다")
    }
}

/// [회귀] 정적 스프라이트가 먼저 떴다가 움직이는 스프라이트로 바뀌는 교체가 어색하다는 지적.
/// 기다리는 동안에는 아무것도 안 그리되, **기다릴 이유가 없을 때는 기다리면 안 된다** —
/// 정적 스크린샷은 `.task` 를 안 돌리므로 init 의 캐시 시드가 유일한 그림이다.
@MainActor
final class SpriteAnimationWaitTests: XCTestCase {
    /// 움직이는 스프라이트를 요청하지 않았으면 기다릴 일이 없다.
    func testStaticRequestsNeverWait() {
        XCTAssertFalse(SpriteView.needsToWait(speciesID: 25, form: nil,
                                              animated: false, shiny: false))
    }

    /// 알 상태(종 없음)도 기다리지 않는다 — 기다리면 알 자리가 영영 빈칸이 된다.
    func testTheEggStateNeverWaits() {
        XCTAssertFalse(SpriteView.needsToWait(speciesID: nil, form: nil,
                                              animated: true, shiny: false))
    }

    /// 캐시에 GIF 가 있으면 기다리지 않는다. 이게 정적 스크린샷을 지키는 조건이다 —
    /// 여기가 참이 되면 박스·도감·상세 PNG 가 전부 빈칸으로 생성된다.
    func testACachedAnimationDoesNotWait() throws {
        let species = 9_001                       // 실제 종과 안 겹치는 번호
        let key = SpriteStore.cacheKey(speciesID: species, form: nil, animated: true, shiny: false)
        let file = SpriteLoader.cacheDir.appendingPathComponent("\(key).gif")
        try FileManager.default.createDirectory(at: SpriteLoader.cacheDir,
                                                withIntermediateDirectories: true)
        try Data([0x47, 0x49, 0x46]).write(to: file)      // 존재만 보므로 내용은 상관없다
        defer { try? FileManager.default.removeItem(at: file) }

        XCTAssertFalse(SpriteView.needsToWait(speciesID: species, form: nil,
                                              animated: true, shiny: false),
                       "캐시가 있는데 기다린다 — 정적 스크린샷이 빈칸이 된다")
        XCTAssertTrue(SpriteView.needsToWait(speciesID: species + 1, form: nil,
                                             animated: true, shiny: false),
                      "캐시가 없는데 안 기다린다 — 정적→애니 교체가 그대로 보인다")
    }

    /// 이로치 GIF 가 없는 종은 일반 GIF 로 폴백하므로, 일반 캐시가 있으면 기다리지 않는다.
    func testShinyFallsBackToThePlainAnimationCache() throws {
        let species = 9_003
        let key = SpriteStore.cacheKey(speciesID: species, form: nil, animated: true, shiny: false)
        let file = SpriteLoader.cacheDir.appendingPathComponent("\(key).gif")
        try FileManager.default.createDirectory(at: SpriteLoader.cacheDir,
                                                withIntermediateDirectories: true)
        try Data([0x47, 0x49, 0x46]).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        XCTAssertFalse(SpriteView.needsToWait(speciesID: species, form: nil,
                                              animated: true, shiny: true))
    }
}
