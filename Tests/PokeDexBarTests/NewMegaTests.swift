import XCTest
@testable import PokeDexBar

/// Legends Z-A 의 새 메가 — 기존 메가스톤 장치에 표만 더한 것.
@MainActor
final class NewMegaTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeStore() -> PlayerStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mega-\(UUID().uuidString).json")
        return PlayerStore(fileURL: url, rng: SeededRNG(seed: 1), now: { self.now })
    }

    private func made(_ speciesID: Int, gender: Gender? = nil) -> Individual {
        Individual(baseID: speciesID, speciesID: speciesID, pathIDs: [speciesID],
                   gender: gender, nature: .hardy, obtainedAt: now, grade: .epic)
    }

    /// 새 메가가 실제로 표에 들어왔고, **메가스톤으로 열린다**(출처를 안 적어도 기본이 그것).
    func testTheNewMegasOpenWithTheSameStone() throws {
        for speciesID in [149, 160, 609, 970] {
            let forms = FormCatalog.forms(speciesID: speciesID, kind: .mega)
            XCTAssertFalse(forms.isEmpty, "#\(speciesID) 의 메가가 없다")
            for form in forms {
                XCTAssertEqual(form.source, .shop(.megaStone), "\(form.slug) 이 메가스톤이 아니다")
            }
        }
    }

    /// **모든 폼 슬러그는 그 종의 것이어야 한다** — 손으로 적은 표라 오타 하나가 빈 그림이 된다.
    func testEveryFormSlugBelongsToItsSpecies() {
        for form in FormCatalog.all {
            guard let base = SpeciesSlug.slug(form.speciesID) else {
                return XCTFail("#\(form.speciesID) 의 종 슬러그가 없다")
            }
            XCTAssertTrue(form.slug.hasPrefix(base + "-"),
                          "#\(form.speciesID) 의 \(form.slug) 이 \(base) 의 폼이 아니다")
        }
    }

    /// 같은 종에 슬러그가 겹치면 안 된다(복붙 사고).
    func testNoDuplicateFormSlugs() {
        let slugs = FormCatalog.all.map(\.slug)
        XCTAssertEqual(slugs.count, Set(slugs).count, "폼 슬러그가 겹친다")
    }

    // MARK: 냐오닉스 — 성별로 갈리는 메가

    /// **수컷은 수컷 메가만, 암컷은 암컷 메가만.** 안 가르면 수컷이 암컷 메가가 된다.
    func testMeowsticMegaFollowsGender() {
        let store = makeStore()
        store.mutate { $0.inventory[ShopItem.megaStone.rawValue] = 1 }

        let male = store.formChoices(made(678, gender: .male), kind: .mega).map(\.slug)
        XCTAssertEqual(male, ["meowstic-mmega"], "수컷에게 암컷 메가가 열렸다")

        let female = store.formChoices(made(678, gender: .female), kind: .mega).map(\.slug)
        XCTAssertEqual(female, ["meowstic-fmega"], "암컷에게 수컷 메가가 열렸다")
    }

    /// 성별을 아직 모르는 개체(옛 세이브)에는 **아무것도 안 연다** — 되돌릴 수 있어도
    /// 그림이 거짓말을 하는 건 막는다.
    func testAnUnknownGenderGetsNoGatedForm() {
        let store = makeStore()
        store.mutate { $0.inventory[ShopItem.megaStone.rawValue] = 1 }
        XCTAssertTrue(store.formChoices(made(678, gender: nil), kind: .mega).isEmpty)
    }

    /// 제한 없는 폼은 성별과 무관하게 열린다(게이트가 전부를 막고 있지 않은지 — 대조군).
    func testUngatedFormsIgnoreGender() {
        let store = makeStore()
        store.mutate { $0.inventory[ShopItem.megaStone.rawValue] = 1 }
        for gender in [Gender.male, .female, .genderless, nil] {
            let slugs = store.formChoices(made(149, gender: gender), kind: .mega).map(\.slug)
            XCTAssertEqual(slugs, ["dragonite-mega"], "\(String(describing: gender)) 가 막혔다")
        }
    }

    /// 성별 제한이 걸린 폼은 **냐오닉스 둘뿐**이어야 한다 — 다른 데 잘못 붙으면 그 종의
    /// 폼이 조용히 사라진다.
    func testOnlyMeowsticHasAGenderGate() {
        let gated = FormCatalog.all.filter { $0.requiredGender != nil }
        XCTAssertEqual(Set(gated.map(\.speciesID)), [678])
        XCTAssertEqual(gated.count, 2)
    }
}
