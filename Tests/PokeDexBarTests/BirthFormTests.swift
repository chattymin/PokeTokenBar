import XCTest
@testable import PokeDexBar

/// 카탈로그의 모양 — 라인 안에서 어긋나면 진화할 때 겉모습이 사라진다.
final class BirthFormCatalogTests: XCTestCase {
    /// `(종, 변종)` 은 유일해야 한다. 겹치면 어느 쪽이 그려질지가 사전 순서에 달린다.
    func testEveryEntryIsUnique() {
        let keys = BirthFormCatalog.all.map { "\($0.speciesID)-\($0.variant)" }
        XCTAssertEqual(Set(keys).count, keys.count, "중복 항목이 있다")
    }

    /// **라인 안의 단계들이 같은 변종 집합을 써야 한다.** 플라베베가 다섯 색인데 플라제스가 넷이면
    /// 그 색으로 진화하는 순간 겉모습이 없어진다 — 조용히 기본 모습이 되고 원인이 안 보인다.
    func testEveryStageInALineOffersTheSameVariants() {
        for line in [[669, 670, 671], [422, 423]] {
            let sets = line.map { Set(BirthFormCatalog.forms(speciesID: $0).map(\.variant)) }
            XCTAssertEqual(Set(sets).count, 1, "라인 \(line) 의 단계마다 변종이 다르다: \(sets)")
        }
    }

    /// 무늬를 갖고 있어도 **비비용이 되어야 보인다.** 스카바·스피아에 항목이 있으면 진화가
    /// 사건이 아니게 되고, 있지도 않은 슬러그를 요청하게 된다.
    func testThePatternOnlyShowsOnVivillon() {
        XCTAssertTrue(BirthFormCatalog.forms(speciesID: 664).isEmpty, "스카바에 무늬가 붙어 있다")
        XCTAssertTrue(BirthFormCatalog.forms(speciesID: 665).isEmpty, "스피아에 무늬가 붙어 있다")
        XCTAssertEqual(BirthFormCatalog.forms(speciesID: 666).count, 18)
    }

    /// 기본형은 접미 없는 슬러그다 — 언노운 A, 빨간 꽃, 서쪽바다, 화원의 모양.
    func testDefaultVariantsUseThePlainSlug() {
        XCTAssertEqual(BirthFormCatalog.form(speciesID: 201, variant: "a")?.slug, "unown")
        XCTAssertEqual(BirthFormCatalog.form(speciesID: 669, variant: "red")?.slug, "flabebe")
        XCTAssertEqual(BirthFormCatalog.form(speciesID: 422, variant: "west")?.slug, "shellos")
        XCTAssertEqual(BirthFormCatalog.form(speciesID: 666, variant: "meadow")?.slug, "vivillon")
    }

    /// 언노운은 A–Z 26자. `!` `?` 는 Showdown 에 스프라이트가 없어 뺐다(실측 404) —
    /// 이 저장소는 그림이 있는 것만 담는다.
    func testUnownHasTwentySixLetters() {
        let letters = BirthFormCatalog.forms(speciesID: 201)
        XCTAssertEqual(letters.count, 26)
        XCTAssertEqual(Set(letters.map(\.variant)), Set("abcdefghijklmnopqrstuvwxyz".map(String.init)))
    }

    /// 라벨은 세 언어가 다 채워져 있어야 한다 — 한 언어만 비어도 그 언어에서 배지가 빈칸이 된다.
    /// 언노운 글자는 예외다(세 언어가 같은 글자 하나).
    func testEveryLabelIsFilledInAllThreeLanguages() {
        for form in BirthFormCatalog.all where form.speciesID != 201 {
            for lang in AppLanguage.allCases where lang != .systemDefault {
                XCTAssertFalse(form.label.text(lang).isEmpty,
                               "\(form.slug) 의 \(lang) 라벨이 비었다")
            }
        }
    }
}

/// 굴림 규칙.
final class BirthFormBalanceTests: XCTestCase {
    /// 겉모습이 갈리지 않는 종은 아무것도 안 붙는다.
    func testOrdinarySpeciesGetNothing() {
        XCTAssertNil(BirthFormBalance.rollBirthForm(baseID: 25, roll: 0, pick: 0, homeRegion: "KR"))
    }

    /// **확률 게이트가 없다.** 지방 모습은 "20%로 변종, 아니면 원종"이지만 여기엔 원종이 없다 —
    /// 모든 언노운은 어떤 글자다. 어떤 난수를 줘도 항상 나와야 한다.
    func testEveryUnownGetsALetter() {
        for step in 0..<20 {
            let value = Double(step) / 20
            XCTAssertNotNil(BirthFormBalance.rollBirthForm(baseID: 201, roll: value, pick: value,
                                                           homeRegion: "KR"),
                            "roll=\(value) 에서 글자가 안 붙었다")
        }
    }

    /// 26글자가 고르게 나오는지 — `pick` 을 훑어 전부 한 번씩은 나와야 한다.
    func testEveryLetterIsReachable() {
        let got = (0..<260).compactMap {
            BirthFormBalance.rollBirthForm(baseID: 201, roll: 0.5,
                                           pick: Double($0) / 260, homeRegion: "KR")
        }
        XCTAssertEqual(Set(got).count, 26, "못 나오는 글자가 있다")
    }

    /// 플라베베 라인은 부화하는 종(669)으로 굴려도 다섯 색이 다 나온다.
    func testFlowerColorsAreAllReachable() {
        let got = (0..<50).compactMap {
            BirthFormBalance.rollBirthForm(baseID: 669, roll: 0.5,
                                           pick: Double($0) / 50, homeRegion: "KR")
        }
        XCTAssertEqual(Set(got), ["red", "yellow", "orange", "blue", "white"])
    }

    // MARK: 비비용 — 지역

    /// 한국 기기는 **대륙의 모양만** 나온다. 원작에서 한국 지역에 배정된 무늬가 그 하나뿐이다.
    func testKoreaOnlyGetsContinental() {
        for step in 0..<20 {
            let variant = BirthFormBalance.rollBirthForm(
                baseID: 664, roll: 0.99, pick: Double(step) / 20, homeRegion: "KR")
            XCTAssertEqual(variant, "continental", "한국인데 다른 무늬가 나왔다")
        }
    }

    /// **해외 무늬 굴림이 그 벽을 연다.** 이게 없으면 한국 사용자는 18종 중 1종만 평생 본다.
    /// 경계를 정확히 잠근다 — 확률이 조용히 바뀌면 이 이스터에그의 리듬이 달라진다.
    func testTheForeignRollOpensTheOtherPatterns() {
        let threshold = Double(BirthFormBalance.foreignPermille) / 1000
        // 문턱 바로 안쪽 — 전체가 후보다.
        XCTAssertEqual(BirthFormBalance.candidateVariants(baseID: 664, roll: threshold - 0.001,
                                                          homeRegion: "KR").count, 18)
        // 문턱 밖 — 내 지역뿐이다.
        XCTAssertEqual(BirthFormBalance.candidateVariants(baseID: 664, roll: threshold,
                                                          homeRegion: "KR"), ["continental"])
    }

    /// 지역별 후보 집합이 원본 표와 같은지. 개수가 어긋나면 표를 잘못 옮긴 것이다.
    func testEachRegionGetsItsOwnPatterns() {
        XCTAssertEqual(VivillonRegions.patterns(forCountry: "KR").count, 1)
        XCTAssertEqual(VivillonRegions.patterns(forCountry: "JP").count, 3)
        XCTAssertEqual(VivillonRegions.patterns(forCountry: "TW").count, 1)
        XCTAssertEqual(VivillonRegions.patterns(forCountry: "US").count, 11)
        XCTAssertEqual(VivillonRegions.patterns(forCountry: "DE").count, 15)
        // 모르는 나라·설정 없음 → PAL(가장 넓은 집합).
        XCTAssertEqual(VivillonRegions.patterns(forCountry: nil),
                       VivillonRegions.patterns(forCountry: "DE"))
    }

    /// 지역 표의 무늬가 전부 카탈로그에 있어야 한다. 오타 하나면 그 지역 사용자가
    /// **영영 기본 모습만** 보게 되고, 값은 저장돼 있어 원인이 안 보인다.
    func testEveryRegionalPatternExistsInTheCatalog() {
        let known = Set(BirthFormCatalog.forms(speciesID: 666).map(\.variant))
        for group in [VivillonRegions.american, VivillonRegions.japanese, VivillonRegions.korean,
                      VivillonRegions.taiwanese, VivillonRegions.pal] {
            XCTAssertTrue(Set(group).isSubset(of: known), "카탈로그에 없는 무늬: \(Set(group).subtracting(known))")
        }
    }

    // MARK: 스트린더 — 성격 파생

    /// **25종 성격이 정확히 두 갈래로 나뉘어야 한다.** 하나라도 빠지면 그 성격의 스트린더가
    /// 폼 없이 나오고, 겹치면 규칙이 모순이다.
    func testEveryNatureLandsOnExactlyOneForm() {
        let low = BirthFormBalance.lowKeyNatures
        XCTAssertEqual(low.count, 12)
        XCTAssertEqual(PokemonNature.allCases.count, 25)
        let amped = Set(PokemonNature.allCases).subtracting(low)
        XCTAssertEqual(amped.count, 13)
        // 모든 성격이 둘 중 하나로 간다.
        for nature in PokemonNature.allCases {
            let slug = BirthFormBalance.toxtricitySlug(nature: nature)
            XCTAssertTrue(slug == "toxtricity" || slug == "toxtricity-lowkey", "\(nature) → \(slug)")
        }
    }

    /// 원작이 정한 분류 그대로인지 — 대표적인 몇 개만 짚는다.
    func testTheNatureSplitMatchesTheGames() {
        XCTAssertEqual(BirthFormBalance.toxtricitySlug(nature: .adamant), "toxtricity")
        XCTAssertEqual(BirthFormBalance.toxtricitySlug(nature: .jolly), "toxtricity")
        XCTAssertEqual(BirthFormBalance.toxtricitySlug(nature: .modest), "toxtricity-lowkey")
        XCTAssertEqual(BirthFormBalance.toxtricitySlug(nature: .calm), "toxtricity-lowkey")
    }
}

/// 개체에 붙었을 때.
@MainActor
final class BirthFormIndividualTests: XCTestCase {
    private func make(speciesID: Int, baseID: Int, variant: String?,
                      nature: PokemonNature = .modest) -> Individual {
        var individual = Individual(baseID: baseID, speciesID: speciesID, pathIDs: [baseID, speciesID],
                                    nature: nature, obtainedAt: Date(timeIntervalSince1970: 0),
                                    grade: .common)
        individual.birthForm = variant
        return individual
    }

    /// **진화해도 색이 이어진다.** 키를 저장하고 슬러그를 카탈로그에서 찾는 이유가 이것이다 —
    /// 슬러그를 저장했다면 플라베베 슬러그를 든 플라제스가 된다.
    func testTheFlowerColorSurvivesEvolution() {
        XCTAssertEqual(make(speciesID: 669, baseID: 669, variant: "blue").spriteForm, "flabebe-blue")
        XCTAssertEqual(make(speciesID: 670, baseID: 669, variant: "blue").spriteForm, "floette-blue")
        XCTAssertEqual(make(speciesID: 671, baseID: 669, variant: "blue").spriteForm, "florges-blue")
    }

    /// 무늬를 가진 스카바는 **평소 모습으로 그려진다** — 그 단계엔 그림이 없다.
    /// 슬러그를 만들어 내면 404 를 계속 요청하게 된다.
    func testAScatterbugWithAPatternStillLooksOrdinary() {
        XCTAssertNil(make(speciesID: 664, baseID: 664, variant: "polar").spriteForm)
        XCTAssertEqual(make(speciesID: 666, baseID: 664, variant: "polar").spriteForm, "vivillon-polar")
    }

    /// 스트린더는 저장된 값 없이 성격만으로 갈린다.
    func testToxtricityComesFromNatureAlone() {
        let amped = make(speciesID: 849, baseID: 848, variant: nil, nature: .adamant)
        let lowKey = make(speciesID: 849, baseID: 848, variant: nil, nature: .modest)
        XCTAssertNil(amped.birthForm, "저장할 값이 없어야 한다")
        XCTAssertEqual(amped.spriteForm, "toxtricity")
        XCTAssertEqual(lowKey.spriteForm, "toxtricity-lowkey")
        // 일레즌은 아직 갈리지 않는다.
        XCTAssertNil(make(speciesID: 848, baseID: 848, variant: nil, nature: .modest).spriteForm)
    }

    /// 배지에 이름이 뜬다.
    func testTheBadgeShowsTheOfficialName() {
        XCTAssertEqual(make(speciesID: 666, baseID: 664, variant: "polar").birthFormLabel(.ko),
                       "설국의 모양")
        XCTAssertEqual(make(speciesID: 201, baseID: 201, variant: "c").birthFormLabel(.en), "C")
        XCTAssertEqual(make(speciesID: 849, baseID: 848, variant: nil, nature: .calm)
                        .birthFormLabel(.ko), "로우한 모습")
        XCTAssertNil(make(speciesID: 25, baseID: 25, variant: nil).birthFormLabel(.ko))
    }

    /// 위장 중인 개체는 배지를 안 내민다 — 정체를 알려 주는 단서가 된다.
    func testADisguisedIndividualShowsNoBadge() {
        var ditto = make(speciesID: DittoDisguise.speciesID, baseID: DittoDisguise.speciesID,
                         variant: nil)
        ditto.disguisedAs = DittoDisguise.disguisedAs
        XCTAssertNil(ditto.birthFormLabel(.ko))
    }

    /// 말이 안 되는 변종은 경계에서 버린다 — 관대 디코딩의 짝.
    func testABogusVariantIsDropped() {
        XCTAssertNil(make(speciesID: 201, baseID: 201, variant: "9").sanitized().birthForm)
        XCTAssertEqual(make(speciesID: 201, baseID: 201, variant: "c").sanitized().birthForm, "c")
        // 라인 기준이라 스카바의 무늬도 살아남아야 한다(자기 단계엔 항목이 없다).
        XCTAssertEqual(make(speciesID: 664, baseID: 664, variant: "polar").sanitized().birthForm,
                       "polar")
    }

    /// **세이브를 건너도 남아야 한다.** 디코더에 필드를 안 더하면 저장은 되고 읽기만 빠져서,
    /// 앱을 다시 켤 때마다 모습이 사라진다 — 메타몽 위장에서 실제로 낸 결함이다.
    func testTheBirthFormSurvivesASaveRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("birth-\(UUID().uuidString).json")
        let now = Date(timeIntervalSince1970: 0)
        let defaults = { UserDefaults(suiteName: "ptb-birth-\(UUID().uuidString)")! }
        let store = PlayerStore(fileURL: url, rng: SeededRNG(seed: 4), now: { now },
                                defaults: defaults())
        var unown = make(speciesID: 201, baseID: 201, variant: "q")
        unown.birthForm = "q"
        store.addForTesting(unown)

        let reloaded = PlayerStore(fileURL: url, rng: SeededRNG(seed: 4), now: { now },
                                   defaults: defaults())
        XCTAssertEqual(reloaded.state.box.first { $0.id == unown.id }?.birthForm, "q",
                       "다시 켜니 글자가 사라졌다")
    }

    /// 구 세이브의 개체는 필드가 없다 — 지금과 똑같이 보여야 한다.
    /// 이미 가진 언노운이 갑자기 글자를 얻지는 않는다.
    func testOlderIndividualsAreUnaffected() {
        let old = make(speciesID: 201, baseID: 201, variant: nil)
        XCTAssertNil(old.spriteForm)
        XCTAssertNil(old.birthFormLabel(.ko))
    }
}
