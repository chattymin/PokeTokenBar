import XCTest
@testable import PokeDexBar

/// 태생폼 일괄 확장 — 크기·도롱·깃털·모습·진작·가족 수·마디.
@MainActor
final class BirthFormExpansionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func made(_ speciesID: Int, base: Int, variant: String?) -> Individual {
        var i = Individual(baseID: base, speciesID: speciesID, pathIDs: [base, speciesID],
                           nature: .hardy, obtainedAt: now, grade: .common)
        i.birthForm = variant
        return i
    }

    /// **모든 슬러그가 종 슬러그 + 폼 접미사 꼴이어야 한다.** 손으로 적은 표라 오타 하나가
    /// 그 개체만 영영 빈 그림으로 남는데, 앱은 안 죽으니 원인이 안 보인다.
    func testEverySlugBelongsToItsSpecies() {
        for form in BirthFormCatalog.all {
            guard let base = SpeciesSlug.slug(form.speciesID) else {
                return XCTFail("#\(form.speciesID) 의 종 슬러그가 없다")
            }
            XCTAssertTrue(form.slug == base || form.slug.hasPrefix(base + "-"),
                          "#\(form.speciesID) 의 \(form.slug) 이 \(base) 의 폼이 아니다")
        }
    }

    /// 세 언어 이름이 다 있어야 한다 — 하나라도 비면 그 언어에서 배지가 빈칸이 된다.
    func testEveryLabelHasAllThreeLanguages() {
        for form in BirthFormCatalog.all {
            for lang in AppLanguage.allCases {
                XCTAssertFalse(form.label.text(lang).isEmpty,
                               "\(form.slug) 의 \(lang) 이름이 비었다")
            }
        }
    }

    /// 라인마다 굴릴 후보가 **카탈로그에 실제로 있는 변종**이어야 한다. 표를 두 곳에 적어서
    /// 생기는 부류 — 후보에만 있고 카탈로그에 없으면 그 변종은 영원히 기본 그림이다.
    func testEveryRolledVariantExistsSomewhereInTheLine() {
        for base in [201, 664, 669, 422, 710, 412, 550, 931, 978, 854, 1012, 924, 206] {
            let variants = BirthFormCatalog.variants(forLineStartingAt: base)
            XCTAssertFalse(variants.isEmpty, "라인 \(base) 의 후보가 비었다")
            for variant in variants {
                let found = BirthFormCatalog.all.contains { $0.variant == variant }
                XCTAssertTrue(found, "라인 \(base) 의 후보 \(variant) 가 카탈로그에 없다")
            }
        }
    }

    /// 크기는 진화로 이어진다 — 작은 호바귀는 작은 펌킨인이 된다.
    func testTheSizeCarriesThroughEvolution() {
        XCTAssertEqual(made(710, base: 710, variant: "small").spriteForm, "pumpkaboo-small")
        XCTAssertEqual(made(711, base: 710, variant: "small").spriteForm, "gourgeist-small")
        // 보통 크기는 종 기본 그림이라 항목이 없다.
        XCTAssertNil(made(710, base: 710, variant: "average").spriteForm)
    }

    /// 도롱은 도롱마담까지 이어지고 **나메일에는 안 붙는다** — 수컷은 도롱을 안 두른다.
    func testTheCloakReachesWormadamButNotMothim() {
        XCTAssertEqual(made(413, base: 412, variant: "trash").spriteForm, "wormadam-trash")
        XCTAssertNil(made(414, base: 412, variant: "trash").spriteForm, "나메일에 도롱이 붙었다")
    }

    /// 가족 수와 마디는 **진화해야 드러난다**(분이벌레 구조) — 두리쥐·노고치는 기본 그림.
    func testFamilyAndSegmentsOnlyShowAfterEvolving() {
        XCTAssertNil(made(924, base: 924, variant: "fourfamily").spriteForm)
        XCTAssertEqual(made(925, base: 924, variant: "fourfamily").spriteForm, "maushold-four")
        XCTAssertNil(made(206, base: 206, variant: "threesegment").spriteForm)
        XCTAssertEqual(made(982, base: 206, variant: "threesegment").spriteForm,
                       "dudunsparce-threesegment")
    }

    /// **파밀리쥐만 기본 그림이 희귀한 쪽이다** — Showdown 의 `maushold` 가 3마리 가족이라
    /// (`baseForme: "Three"`), 흔한 4마리에 슬러그를 달아야 한다. 뒤집으면 라벨과 그림이 어긋난다.
    func testMausholdKeepsTheRareThreeOnTheBaseSprite() throws {
        let three = try XCTUnwrap(BirthFormCatalog.form(speciesID: 925, variant: "threefamily"))
        let four = try XCTUnwrap(BirthFormCatalog.form(speciesID: 925, variant: "fourfamily"))
        XCTAssertEqual(three.slug, "maushold", "3마리는 종 기본 슬러그여야 한다")
        XCTAssertEqual(four.slug, "maushold-four")
        XCTAssertTrue(BirthFormCatalog.isRare("threefamily"))
        XCTAssertFalse(BirthFormCatalog.isRare("fourfamily"))
    }

    // MARK: 희귀 변종

    /// **희귀 변종이 흔해지면 안 된다.** 균등하게 굴리면 절반이 진작이 되어 희귀함이 사라진다.
    func testRareVariantsStayRare() {
        var rare = 0
        let tries = 1000
        for i in 0..<tries {
            let roll = Double(i) / Double(tries)
            let picked = BirthFormBalance.rollBirthForm(baseID: 854, roll: roll, pick: 0.5,
                                                        homeRegion: nil)
            if picked == "antique" { rare += 1 }
        }
        let percent = rare * 100 / tries
        XCTAssertTrue((3...15).contains(percent), "진작이 \(percent)% 로 나온다 — 희귀 게이트가 죽었다")
    }

    /// 게이트가 **전부를 막고 있지도** 않아야 한다(대조군) — 흔한 쪽이 실제로 나온다.
    func testTheCommonVariantIsStillTheDefault() {
        let common = (0..<200).compactMap {
            BirthFormBalance.rollBirthForm(baseID: 931, roll: Double($0) / 200, pick: 0.5,
                                           homeRegion: nil)
        }
        XCTAssertFalse(common.isEmpty)
        XCTAssertTrue(common.allSatisfy { !BirthFormCatalog.isRare($0) },
                      "시비꼬엔 희귀 변종이 없는데 희귀로 굴렸다")
    }

    /// 희귀 게이트가 다른 라인의 굴림을 안 건드린다 — 비비용 지역 규칙이 그대로여야 한다.
    func testTheRareGateLeavesVivillonAlone() {
        let patterns = BirthFormBalance.candidateVariants(baseID: 664, roll: 0.5,
                                                          homeRegion: "KR")
        XCTAssertFalse(patterns.isEmpty)
        XCTAssertTrue(patterns.allSatisfy { !BirthFormCatalog.isRare($0) })
    }

    /// 새로 는 도감 칸 — 태생폼은 도감을 나눈다. 기본 슬러그를 쓰는 변종은 bare 키로 접힌다.
    func testTheDexSplitsOnlyForNonBaseSlugs() {
        XCTAssertEqual(DexKey.key(for: made(925, base: 924, variant: "fourfamily")),
                       "925/maushold-four")
        XCTAssertEqual(DexKey.key(for: made(925, base: 924, variant: "threefamily")), "925",
                       "종 기본 슬러그인 변종은 도감을 안 나눠야 한다")
        XCTAssertEqual(DexKey.key(for: made(711, base: 710, variant: "super")),
                       "711/gourgeist-super")
    }
}
