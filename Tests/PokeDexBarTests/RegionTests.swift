import XCTest
@testable import PokeDexBar

/// 카탈로그 — 메가와 같은 규율: Showdown 에 실제로 스프라이트가 있는 것만 담는다.
final class RegionalFormCatalogTests: XCTestCase {
    func testCoversAllFourRegions() {
        for region in Region.allCases {
            XCTAssertFalse(RegionalFormCatalog.all.filter { $0.region == region }.isEmpty,
                           "\(region.rawValue) 모습이 하나도 없다")
        }
    }

    func testSlugsAreUnique() {
        let slugs = RegionalFormCatalog.all.map(\.slug)
        XCTAssertEqual(Set(slugs).count, slugs.count)
    }

    /// 슬러그는 `<종슬러그>-<지방>[변형]` 꼴 — Showdown 경로를 그대로 만든다.
    func testSlugsCarryTheirRegion() {
        for form in RegionalFormCatalog.all {
            XCTAssertTrue(form.slug.contains("-\(form.region.rawValue)"),
                          "\(form.slug) 에 지방이 안 들어 있다")
        }
    }

    func testRaichuHasAnAlolanForm() {
        XCTAssertEqual(RegionalFormCatalog.form(speciesID: 26, region: .alola)?.slug, "raichu-alola")
    }

    /// 팔데아 켄타로스는 셋이라 변형 이름으로 갈린다.
    func testPaldeanTaurosHasThreeVariants() {
        let forms = RegionalFormCatalog.forms(speciesID: 128).filter { $0.region == .paldea }
        XCTAssertEqual(forms.count, 3)
        XCTAssertEqual(Set(forms.compactMap(\.variant)).count, 3)
    }

    func testSpeciesWithoutARegionalFormReturnsNothing() {
        XCTAssertTrue(RegionalFormCatalog.regions(speciesID: 1).isEmpty)   // 이상해씨
        XCTAssertNil(RegionalFormCatalog.form(speciesID: 1, region: .alola))
    }

    func testDisplayNamePrefixesTheRegion() {
        XCTAssertEqual(Region.alola.displayName(base: "라이츄", .ko), "알로라 라이츄")
        XCTAssertEqual(Region.galar.displayName(base: "Meowth", .en), "Galarian Meowth")
        XCTAssertEqual(Region.hisui.displayName(base: "ゾロア", .ja), "ヒスイゾロア")
    }
}

/// 스프라이트 선택 — 개체가 어떤 그림을 그려야 하는가.
final class RegionSpriteFormTests: XCTestCase {
    private func meowth(region: Region? = nil, speciesID: Int = 52) -> Individual {
        var i = Individual(baseID: 52, speciesID: speciesID, pathIDs: [52], nature: .serious, exp: 0,
                           obtainedAt: Date(timeIntervalSince1970: 0), grade: .common)
        i.region = region
        return i
    }

    func testPlainIndividualHasNoFormSlug() {
        XCTAssertNil(meowth().spriteForm)
    }

    func testRegionalIndividualUsesTheRegionalSlug() {
        XCTAssertEqual(meowth(region: .galar).spriteForm, "meowth-galar")
    }

    /// 지방 모습이 없는 종으로 진화하면(가라르 나옹 → 나이킹) 원종 스프라이트로 떨어져야 한다.
    /// 여기서 `meowth-galar` 를 계속 쓰면 나이킹 자리에 나옹이 그려진다.
    func testEvolvingIntoASpeciesWithoutARegionalFormFallsBack() {
        XCTAssertNil(meowth(region: .galar, speciesID: 863).spriteForm)
    }

    /// 메가·거다이맥스가 지방보다 우선한다 — 동시에 둘을 그릴 수는 없다.
    func testMegaFormWinsOverRegion() {
        var charizard = Individual(baseID: 4, speciesID: 6, pathIDs: [4, 5, 6], nature: .serious,
                                   exp: 0, obtainedAt: Date(timeIntervalSince1970: 0), grade: .epic)
        charizard.region = .galar
        charizard.form = "charizard-megax"
        XCTAssertEqual(charizard.spriteForm, "charizard-megax")
    }
}

/// 부화 굴림 — 지방 모습은 태어날 때 정해진다.
final class RegionRollTests: XCTestCase {
    func testSpeciesWithoutRegionalFormsNeverRolls() {
        XCTAssertNil(RegionBalance.rollRegion(speciesID: 1, roll: 0, pick: 0))
        XCTAssertNil(RegionBalance.rollRegion(speciesID: 1, roll: 0.999, pick: 0.999))
    }

    /// 확률 경계 — 원종이 기본이어야 한다.
    func testRollBoundary() {
        XCTAssertNotNil(RegionBalance.rollRegion(speciesID: 52, roll: 0.199, pick: 0))
        XCTAssertNil(RegionBalance.rollRegion(speciesID: 52, roll: 0.2, pick: 0),
                     "경계값이 지방으로 넘어가면 원종보다 지방이 흔해질 수 있다")
        XCTAssertNil(RegionBalance.rollRegion(speciesID: 52, roll: 0.99, pick: 0))
    }

    /// 지방이 여럿인 종은 굴림 하나로 갈린다.
    func testPickSpreadsAcrossTheAvailableForms() {
        // 나옹은 알로라·가라르 둘.
        let low = RegionBalance.rollRegion(speciesID: 52, roll: 0, pick: 0)
        let high = RegionBalance.rollRegion(speciesID: 52, roll: 0, pick: 0.99)
        XCTAssertNotEqual(low?.0, high?.0, "굴림이 달라도 같은 지방만 나오면 한쪽을 영영 못 본다")
    }

    /// pick 이 1.0 이어도 배열 밖으로 나가지 않는다.
    func testPickAtTheTopDoesNotOverflow() {
        XCTAssertNotNil(RegionBalance.rollRegion(speciesID: 52, roll: 0, pick: 1.0))
    }

    func testVariantIsCarriedForTaurosLikeSpecies() {
        let rolled = RegionBalance.rollRegion(speciesID: 128, roll: 0, pick: 0)
        XCTAssertEqual(rolled?.0, .paldea)
        XCTAssertNotNil(rolled?.1, "팔데아 켄타로스는 변형 이름이 있어야 어느 모습인지 정해진다")
    }
}

/// 진화 갈래 — 이게 리전폼의 핵심이다. PokéAPI 는 두 갈래를 한꺼번에 준다.
final class RegionEvolutionTests: XCTestCase {
    /// 관동 나옹은 페르시온만. 나이킹이 뜨면 안 된다.
    func testKantoMeowthCannotBecomePerrserker() {
        XCTAssertEqual(RegionBalance.allowedChoices([53, 863], speciesID: 52, region: nil), [53])
    }

    func testGalarianMeowthOnlyBecomesPerrserker() {
        XCTAssertEqual(RegionBalance.allowedChoices([53, 863], speciesID: 52, region: .galar), [863])
    }

    /// 알로라 나옹은 알로라 페르시온 — 종 번호가 같아 원종과 같은 갈래다.
    func testAlolanMeowthFollowsTheKantoBranch() {
        XCTAssertEqual(RegionBalance.allowedChoices([53, 863], speciesID: 52, region: .alola), [53])
    }

    func testPaldeanWooperOnlyBecomesClodsire() {
        XCTAssertEqual(RegionBalance.allowedChoices([195, 980], speciesID: 194, region: .paldea), [980])
        XCTAssertEqual(RegionBalance.allowedChoices([195, 980], speciesID: 194, region: nil), [195])
    }

    func testHisuianSneaselOnlyBecomesSneasler() {
        XCTAssertEqual(RegionBalance.allowedChoices([461, 903], speciesID: 215, region: .hisui), [903])
    }

    /// 표에 없는 종은 지방과 무관하게 원래 후보를 그대로 쓴다 — 대부분이 여기 해당한다.
    func testUnlistedSpeciesKeepAllChoices() {
        XCTAssertEqual(RegionBalance.allowedChoices([2], speciesID: 1, region: nil), [2])
        XCTAssertEqual(RegionBalance.allowedChoices([2], speciesID: 1, region: .alola), [2])
    }

    /// 표에 적힌 종은 전부 실제 진화 갈래를 갖고 있어야 한다 — 오타 하나로 진화가 통째로 막힌다.
    func testTableEntriesAreInternallyConsistent() {
        for (parent, byRegion) in RegionBalance.branchesByRegion {
            let all = Set(byRegion.values.flatMap { $0 })
            XCTAssertFalse(all.isEmpty, "#\(parent) 의 모든 지방이 진화 불가로 적혀 있다")
            for (region, children) in byRegion {
                let subset = RegionBalance.allowedChoices(Array(all), speciesID: parent, region: region)
                XCTAssertEqual(Set(subset), Set(children),
                               "#\(parent) \(region?.rawValue ?? "원종") 갈래가 표와 어긋난다")
            }
        }
    }
}

@MainActor
final class RegionStoreTests: XCTestCase {
    private func makeStore() -> PlayerStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("region-\(UUID().uuidString).json")
        return PlayerStore(fileURL: url, rng: SeededRNG(seed: 9),
                           now: { Date(timeIntervalSince1970: 0) })
    }

    private func line(_ parent: Int, _ children: [Int]) -> EvoLine {
        EvoLine(baseID: parent,
                tree: EvoNode(speciesID: parent, children: children.map { EvoNode(speciesID: $0, children: []) }),
                rarity: .common, names: [:])
    }

    /// 스토어 경로로도 갈래가 좁혀지는지 — 순수 함수만 테스트하면 배선이 빠져도 통과한다.
    func testEvolutionChoicesAreNarrowedByRegion() {
        let store = makeStore()
        var galar = Individual(baseID: 52, speciesID: 52, pathIDs: [52], nature: .serious, exp: 0,
                               obtainedAt: Date(timeIntervalSince1970: 0), grade: .common)
        galar.region = .galar
        store.addForTesting(galar)
        XCTAssertEqual(store.evolutionChoices(galar, line: line(52, [53, 863])), [863])

        let kanto = Individual(baseID: 52, speciesID: 52, pathIDs: [52], nature: .serious, exp: 0,
                               obtainedAt: Date(timeIntervalSince1970: 0), grade: .common)
        store.addForTesting(kanto)
        XCTAssertEqual(store.evolutionChoices(kanto, line: line(52, [53, 863])), [53])
    }

    /// 진화를 실제로 실행해도 막혀야 한다 — 후보 목록만 좁히고 `evolve` 가 통과시키면 무의미하다.
    func testEvolveRejectsTheOtherRegionsBranch() {
        let store = makeStore()
        var kanto = Individual(baseID: 52, speciesID: 52, pathIDs: [52], nature: .serious,
                               exp: 999_000_000, obtainedAt: Date(timeIntervalSince1970: 0),
                               grade: .common)
        kanto.region = nil
        store.addForTesting(kanto)
        XCTAssertFalse(store.evolve(individualID: kanto.id, to: 863, line: line(52, [53, 863])),
                       "관동 나옹이 나이킹이 됐다")
        XCTAssertTrue(store.evolve(individualID: kanto.id, to: 53, line: line(52, [53, 863])))
    }

    /// 지방은 진화해도 이어진다 — 알로라 식스테일은 알로라 나인테일이 된다.
    func testRegionSurvivesEvolution() {
        let store = makeStore()
        var vulpix = Individual(baseID: 37, speciesID: 37, pathIDs: [37], nature: .serious,
                                exp: 999_000_000, obtainedAt: Date(timeIntervalSince1970: 0),
                                grade: .common)
        vulpix.region = .alola
        store.addForTesting(vulpix)
        XCTAssertTrue(store.evolve(individualID: vulpix.id, to: 38, line: line(37, [38])))
        let after = store.state.box.first { $0.id == vulpix.id }
        XCTAssertEqual(after?.region, .alola, "진화하면서 지방이 사라졌다")
        XCTAssertEqual(after?.spriteForm, "ninetales-alola")
    }

    /// 부화 경로에서 지방이 실제로 붙는지 — 굴림 함수만 테스트하면 배선이 빠져도 통과한다.
    func testHatchingCanProduceARegionalIndividual() {
        let store = makeStore()
        let start = Date(timeIntervalSince1970: 0)
        store.seedForTesting(wallet: 100_000_000_000, slots: 6, eggs: 0, at: start)
        // 나옹 알을 여러 개 깨서 적어도 하나는 지방 모습이 나오는지 본다(확률 20%).
        var sawRegional = false
        for _ in 0..<40 {
            store.startEgg(grade: .common, speciesID: 52, shiny: false)
            let hatched = store.claimAllReady(at: start.addingTimeInterval(48 * 3600))
            if hatched.contains(where: { $0.region != nil }) { sawRegional = true; break }
        }
        XCTAssertTrue(sawRegional, "40번 깨는 동안 지방 모습이 한 번도 안 나왔다 — 굴림이 배선 안 됐다")
    }

    /// 지방 모습이 없는 종은 절대 지방이 붙지 않는다.
    func testHatchingNeverGivesARegionToASpeciesWithoutOne() {
        let store = makeStore()
        let start = Date(timeIntervalSince1970: 0)
        store.seedForTesting(wallet: 100_000_000_000, slots: 6, eggs: 0, at: start)
        for _ in 0..<30 {
            store.startEgg(grade: .common, speciesID: 1, shiny: false)   // 이상해씨
            for hatched in store.claimAllReady(at: start.addingTimeInterval(48 * 3600)) {
                XCTAssertNil(hatched.region, "이상해씨에 지방이 붙었다")
            }
        }
    }
}

/// 세이브 경계 — 관대 디코딩의 짝.
final class RegionDecodeGuardTests: XCTestCase {
    /// 그 지방에 없는 변형 이름은 떼어낸다. 지방 자체는 남긴다 — 진화 뒤 모습이 없는 종이
    /// 되는 건 정상이라(가라르 나옹 → 나이킹) 지방까지 버리면 혈통이 사라진다.
    func testUnknownVariantIsStrippedButRegionSurvives() {
        var tauros = Individual(baseID: 128, speciesID: 128, pathIDs: [128], nature: .serious,
                                exp: 0, obtainedAt: Date(timeIntervalSince1970: 0), grade: .rare)
        tauros.region = .paldea
        tauros.regionVariant = "nonsense"
        let fixed = tauros.sanitized()
        XCTAssertEqual(fixed.region, .paldea)
        XCTAssertNil(fixed.regionVariant)
    }

    func testRegionOfAnEvolvedSpeciesWithoutAFormIsKept() {
        var perrserker = Individual(baseID: 52, speciesID: 863, pathIDs: [52, 863], nature: .serious,
                                    exp: 0, obtainedAt: Date(timeIntervalSince1970: 0), grade: .common)
        perrserker.region = .galar
        XCTAssertEqual(perrserker.sanitized().region, .galar)
    }

    /// 구 세이브(지방 필드 자체가 없음)는 그대로 원종으로 읽힌다.
    func testLegacySaveWithoutRegionDecodes() throws {
        let json = """
        {"box":[{"id":"\(UUID().uuidString)","baseID":52,"speciesID":52,"pathIDs":[52],"shiny":false,
        "nature":"serious","exp":0,"obtainedAt":0,"grade":"common"}],
        "dex":[52],"earnedTokens":0,"spentTokens":0,"claimedTodayTokens":0,"lastDate":"2026-01-01",
        "installBaselineSet":true,"slots":3,"eggs":[],"inventory":{},"ownsShinyCharm":false,
        "starterChosen":true,"language":"ko"}
        """
        let state = try JSONDecoder().decode(PlayerState.self, from: Data(json.utf8))
        XCTAssertEqual(state.box.count, 1)
        XCTAssertNil(state.box.first?.region)
    }
}

/// 좁은 배지(부화 확인 카드)에 들어가야 한다 — 영어 형용사형("Galarian")이 길어 축소되던 것을
/// 지방 이름으로 바꿨다. 이름이 길어지면 배지만 작아져 옆의 것과 다르게 보인다.
final class RegionShortLabelTests: XCTestCase {
    func testShortLabelUsesThePlaceName() {
        XCTAssertEqual(Region.galar.shortLabel(.en), "Galar")
        XCTAssertEqual(Region.alola.shortLabel(.en), "Alola")
    }

    /// 이름 앞에 붙일 때는 형용사형 그대로 — 짧은 이름은 배지 전용이다.
    func testFullLabelIsUnchanged() {
        XCTAssertEqual(Region.galar.label(.en), "Galarian")
    }

    /// 어느 언어에서도 배지가 한 칸에 들어갈 만큼 짧아야 한다.
    func testEveryShortLabelIsShort() {
        for region in Region.allCases {
            for lang in [AppLanguage.ko, .en, .ja] {
                XCTAssertLessThanOrEqual(region.shortLabel(lang).count, 6,
                                         "\(region.rawValue)/\(lang) 배지가 칸을 넘칠 만큼 길다")
            }
        }
    }
}
