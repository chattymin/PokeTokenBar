import XCTest
@testable import PokeDexBar

/// 성별 — 부화 시 한 번 정해져 평생 가고, 여섯 갈래의 진화를 가른다.
@MainActor
final class GenderTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeStore() -> PlayerStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("gender-\(UUID().uuidString).json")
        return PlayerStore(fileURL: url, rng: SeededRNG(seed: 1), now: { self.now })
    }

    // MARK: 성비 굴림

    /// 확정 성별은 **굴림과 무관하게 확정**이다. 경계를 정수로 접으면 `rate == 8` 에서
    /// `roll == 1.0` 이 수컷으로 새는데, 그건 "암컷만"이라는 사실을 깨는 것이다.
    func testFixedGendersIgnoreTheRollEntirely() {
        for roll in [0.0, 0.5, 0.999_999, 1.0] {
            XCTAssertEqual(GenderBalance.roll(rate: 8, roll: roll), .female, "굴림 \(roll)")
            XCTAssertEqual(GenderBalance.roll(rate: 0, roll: roll), .male, "굴림 \(roll)")
            XCTAssertEqual(GenderBalance.roll(rate: -1, roll: roll), .genderless, "굴림 \(roll)")
        }
    }

    /// 절반은 절반에서 갈린다 — 경계가 밀리면 성비가 통째로 틀어진다.
    func testTheHalfRateSplitsAtHalf() {
        XCTAssertEqual(GenderBalance.roll(rate: 4, roll: 0.499), .female)
        XCTAssertEqual(GenderBalance.roll(rate: 4, roll: 0.5), .male)
        // 12.5% — 스타터의 성비. 8분의 1 경계.
        XCTAssertEqual(GenderBalance.roll(rate: 1, roll: 0.124), .female)
        XCTAssertEqual(GenderBalance.roll(rate: 1, roll: 0.125), .male)
    }

    /// 범위 밖 성비는 경계에서 기본값으로 잘린다(관대 디코딩의 짝).
    func testABogusRateIsClampedAtTheBoundary() {
        XCTAssertEqual(GenderBalance.sanitizedRate(Int.max), GenderBalance.defaultRate)
        XCTAssertEqual(GenderBalance.sanitizedRate(-99), GenderBalance.defaultRate)
        XCTAssertEqual(GenderBalance.sanitizedRate(-1), -1, "무성별은 유효한 값이라 안 자른다")
        XCTAssertEqual(GenderBalance.sanitizedRate(8), 8)
    }

    // MARK: 부화

    /// 알에 적힌 성비로 부화 시점에 굴린다 — **알에는 성별이 안 적힌다**(확인 전에 새면 안 된다).
    func testGenderIsRolledAtHatchNotStoredOnTheEgg() throws {
        let store = makeStore()
        let egg = try XCTUnwrap(store.placeEgg(grade: .common, speciesID: 1, shiny: false,
                                               genderRate: 8))
        // 알 자체는 성비만 안다.
        XCTAssertEqual(egg.genderRate, 8)
        store.mutate { s in
            for i in s.eggs.indices { s.eggs[i].hatchesAt = self.now }
        }
        let hatched = try XCTUnwrap(store.claimHatch(eggID: egg.id, at: now))
        XCTAssertEqual(hatched.gender, .female, "성비 8(암컷만)인데 수컷이 나왔다")
    }

    /// 무성별 종은 무성별로 태어난다 — `nil`(미배정)과 구분된다.
    func testAGenderlessSpeciesHatchesGenderlessNotNil() throws {
        let store = makeStore()
        let egg = try XCTUnwrap(store.placeEgg(grade: .common, speciesID: 81, shiny: false,
                                               genderRate: GenderBalance.genderless))
        store.mutate { s in
            for i in s.eggs.indices { s.eggs[i].hatchesAt = self.now }
        }
        let hatched = try XCTUnwrap(store.claimHatch(eggID: egg.id, at: now))
        XCTAssertEqual(hatched.gender, .genderless)
        XCTAssertNotNil(hatched.gender, "무성별을 nil 로 적으면 보정이 매번 다시 굴린다")
    }

    /// 스타터도 성별을 갖고 태어난다 — 여기엔 인덱스가 없어서 기본값에 맡기면 영영 안 정해진다.
    func testTheStarterIsBornWithAGender() throws {
        let store = makeStore()
        let starter = try XCTUnwrap(store.chooseStarter(speciesID: 1, grade: .common))
        XCTAssertNotNil(starter.gender, "스타터의 성별이 안 정해졌다")
        XCTAssertNotEqual(starter.gender, .genderless, "스타터 27마리는 전부 성별이 있다")
    }

    // MARK: 옛 세이브 보정

    /// 성별 키가 없는 개체가 그대로 열리고(박스가 안 비고), 라인이 오면 채워진다.
    func testAnOldIndividualDecodesThenGetsBackfilled() throws {
        let json = """
        {"baseID": 1, "speciesID": 1, "nature": "hardy", "grade": "common"}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(Individual.self, from: json)
        XCTAssertNil(decoded.gender, "성별 없는 세이브는 nil 로 열려야 한다(개체를 버리면 안 된다)")

        let store = makeStore()
        store.mutate { $0.box = [decoded] }
        let line = EvoLine(baseID: 1, tree: EvoNode(speciesID: 1, children: []),
                           rarity: .common, names: [:], genderRates: [1: 4])
        store.backfillGenders(from: line)
        XCTAssertNotNil(store.state.box[0].gender, "보정이 성별을 안 채웠다")
    }

    /// **보정은 이미 있는 성별을 절대 다시 굴리지 않는다.** 다시 굴리면 켤 때마다 성별이 바뀌고
    /// 성별 진화가 그때그때 달라진다.
    func testBackfillNeverRerollsAGenderItAlreadyHas() {
        let store = makeStore()
        var male = Individual(baseID: 1, speciesID: 1, pathIDs: [1], gender: .male,
                              nature: .hardy, obtainedAt: now, grade: .common)
        male.id = UUID(uuidString: "00000000-0000-0000-0000-0000000000FF")!
        store.mutate { $0.box = [male] }
        // 성비 8(암컷만)로 보정을 돌려도 이미 정해진 수컷은 안 바뀐다.
        let line = EvoLine(baseID: 1, tree: EvoNode(speciesID: 1, children: []),
                           rarity: .common, names: [:], genderRates: [1: 8])
        store.backfillGenders(from: line)
        XCTAssertEqual(store.state.box[0].gender, .male, "이미 있는 성별을 다시 굴렸다")
    }

    /// **인덱스 보정은 박스를 한 번에 덮는다.** 라인 기반 보정은 그때 열린 계보만 훑어서,
    /// 여러 계보가 섞인 박스는 계보를 하나씩 열어야 채워졌다 — 사실상 "다 적용"이 안 됐다.
    /// 진화한 개체도 `baseID` 로 찾으므로 함께 덮인다.
    func testTheIndexBackfillCoversTheWholeBoxAtOnce() {
        let store = makeStore()
        store.mutate { s in
            s.box = [
                // 서로 다른 계보 셋 + 진화한 개체(리자몽: baseID 4) — 라인 하나로는 못 덮는다.
                Individual(baseID: 1, speciesID: 1, pathIDs: [1], nature: .hardy,
                           obtainedAt: self.now, grade: .common),
                Individual(baseID: 4, speciesID: 6, pathIDs: [4, 5, 6], nature: .hardy,
                           obtainedAt: self.now, grade: .epic),
                Individual(baseID: 172, speciesID: 25, pathIDs: [172, 25], nature: .hardy,
                           obtainedAt: self.now, grade: .common),
            ]
        }
        let index = [
            BaseSpecies(id: 1, captureRate: 45, isLegendary: false, isMythical: false, genderRate: 1),
            BaseSpecies(id: 4, captureRate: 45, isLegendary: false, isMythical: false, genderRate: 1),
            BaseSpecies(id: 172, captureRate: 190, isLegendary: false, isMythical: false, genderRate: 4),
        ]
        store.backfillGenders(from: index)
        XCTAssertTrue(store.state.box.allSatisfy { $0.gender != nil },
                      "박스에 성별이 안 채워진 개체가 남았다 — 계보를 하나씩 열어야 하는 상태다")
    }

    /// **보정은 기동 경로(`applicationDidFinishLaunching`)에서 불려야 한다.** 두 번 연속
    /// 뷰에 매달았다가 놓쳤다 — 처음엔 상점 탭, 다음엔 팝오버 루트. 둘 다 "그 화면을 열어야"
    /// 도는 자리라, 안 여는 사람에게는 성별이 영영 안 붙었다. 소스를 직접 봐서 잠근다:
    /// 화면 코드가 아니라 앱 기동 코드에 호출이 있어야 한다.
    func testTheBackfillIsCalledFromAppLaunchNotOnlyFromAView() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let app = root.appendingPathComponent("Sources/PokeDexBar/PokeDexBarApp.swift")
        // **주석은 걷어내고 본다.** 처음엔 통짜 문자열 검사였는데, 바로 위 주석에 같은 이름이
        // 적혀 있어서 호출을 지워도 통과했다 — 가드가 아무것도 안 지키고 있었다(뮤테이션으로 발각).
        let code = try String(contentsOf: app, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        XCTAssertTrue(code.contains("backfillGenders(from:"),
                      "기동 경로에 성별 보정 **호출**이 없다 — 뷰에만 매달면 그 화면을 안 여는 사용자에게는 영영 안 돈다")
        let source = code
        XCTAssertTrue(source.contains("applicationDidFinishLaunching"),
                      "기동 훅 자체가 사라졌다 — 이 테스트가 무엇을 잠그는지 다시 확인할 것")
    }

    /// 메타몽은 인덱스에서 빠져 있다(일반 부화 풀 제외) — 안 채우면 영영 미배정으로 남는다.
    func testDittoIsFilledEvenThoughTheIndexExcludesIt() {
        let store = makeStore()
        store.mutate { s in
            s.box = [Individual(baseID: 132, speciesID: 132, pathIDs: [132], nature: .hardy,
                                obtainedAt: self.now, grade: .common)]
        }
        let index = [
            BaseSpecies(id: 1, captureRate: 45, isLegendary: false, isMythical: false, genderRate: 4),
        ]
        store.backfillGenders(from: index)
        XCTAssertEqual(store.state.box[0].gender, .genderless, "메타몽이 미배정으로 남았다")
    }

    /// 보정 굴림은 개체 id 에서 나오므로 몇 번을 돌려도 같다(난수기를 쓰면 기기마다 갈린다).
    func testTheBackfillRollIsStableForTheSameIndividual() {
        let id = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let first = PlayerStore.stableUnit(from: id)
        XCTAssertEqual(first, PlayerStore.stableUnit(from: id))
        XCTAssertNotEqual(first, PlayerStore.stableUnit(from: UUID()))
        XCTAssertTrue((0..<1).contains(first), "0…1 밖으로 나가면 굴림이 아니다")
    }

    // MARK: 존재할 수 없는 성별

    /// **암컷 엘레이드·수컷 염뉴트는 만들어질 수 없다.** 보정은 base 종 성비로 굴리는데
    /// (랄토스 절반이 암컷), 성별 갈래는 정의상 base 와 진화형의 성비가 다르다 — 잠금이
    /// 없으면 여섯 종 전부에서 불가능 조합이 나온다. 어떤 굴림값에서도 안 나와야 한다.
    func testLockedSpeciesNeverGetTheImpossibleGender() {
        for (speciesID, locked) in GenderBalance.locked {
            for rate in [0, 1, 2, 4, 6, 7, 8, GenderBalance.genderless] {
                for r in [0.0, 0.3, 0.5, 0.87, 1.0] {
                    XCTAssertEqual(GenderBalance.roll(species: speciesID, rate: rate, roll: r),
                                   locked,
                                   "#\(speciesID) 가 성비 \(rate)·굴림 \(r) 에서 어긋났다")
                }
            }
        }
    }

    /// 잠금 표가 **정확히 성별 갈래 여섯**이어야 한다. 퍼퓨돈(916)이 들어오면 암컷 퍼퓨돈이
    /// 사라진다 — PokéAPI 는 916 을 수컷만으로 적어 두지만 그건 틀린 데이터다.
    func testTheLockTableIsExactlyTheSixGatedEvolutions() {
        XCTAssertEqual(Set(GenderBalance.locked.keys), [413, 414, 416, 475, 478, 758])
        XCTAssertNil(GenderBalance.lockedGender(916), "퍼퓨돈을 잠그면 암컷 퍼퓨돈이 사라진다")
        XCTAssertNil(GenderBalance.lockedGender(25))
    }

    /// 이미 잘못 적힌 세이브도 **열 때 바로잡힌다** — 값이 들어오는 경계에서 잡는다.
    func testAnImpossibleGenderInASaveIsCorrectedOnLoad() throws {
        let json = Data(#"{"baseID":280,"speciesID":475,"nature":"hardy","grade":"epic","gender":"female"}"#.utf8)
        let decoded = try JSONDecoder().decode(Individual.self, from: json).sanitized()
        XCTAssertEqual(decoded.gender, .male, "암컷 엘레이드가 그대로 살아남았다")
    }

    /// 잠기지 않은 종은 손대지 않는다(잠금이 전부를 덮어쓰고 있지 않은지 — 대조군).
    func testAnUnlockedSpeciesKeepsWhateverGenderItHas() throws {
        let json = Data(#"{"baseID":172,"speciesID":25,"nature":"hardy","grade":"common","gender":"female"}"#.utf8)
        let decoded = try JSONDecoder().decode(Individual.self, from: json).sanitized()
        XCTAssertEqual(decoded.gender, .female, "잠기지 않은 종의 성별이 덮어써졌다")
    }

    /// 보정 경로 전체로도 확인 — base 성비를 그대로 얹던 그 경로다.
    func testTheBackfillNeverProducesAnImpossibleGallade() {
        let store = makeStore()
        store.mutate { s in
            s.box = (0..<40).map { _ in
                Individual(baseID: 280, speciesID: 475, pathIDs: [280, 281, 475],
                           nature: .hardy, obtainedAt: self.now, grade: .epic)
            }
        }
        // 랄토스(280)는 절반이 암컷 — 잠금이 없으면 여기서 절반쯤 암컷 엘레이드가 된다.
        let index = [BaseSpecies(id: 280, captureRate: 235, isLegendary: false,
                                 isMythical: false, genderRate: 4)]
        store.backfillGenders(from: index)
        XCTAssertTrue(store.state.box.allSatisfy { $0.gender == .male },
                      "보정이 암컷 엘레이드를 만들었다")
    }

    // MARK: 개발 시드

    /// 시드는 **지정한 성별 그대로** 넣는다 — 굴리면 시험하려던 성별이 안 나온다.
    /// 도감에도 넣는다: 암수가 별개 폼인 넷은 도감이 갈리는지가 확인 대상이라, 박스에만
    /// 넣으면 정작 볼 것을 못 본다.
    func testTheGenderSeedPlacesTheExactGenderAndRegistersIt() throws {
        let store = makeStore()
        store.applyGenderSeed(speciesID: 25, gender: .female)
        let made = try XCTUnwrap(store.state.box.first { $0.speciesID == 25 })
        XCTAssertEqual(made.gender, .female, "시드가 성별을 굴려 버렸다")
        XCTAssertEqual(made.spriteForm, "pikachu-f", "암컷 그림이 안 걸렸다")
        XCTAssertTrue(store.state.dexForms.contains(DexKey.key(for: made)), "도감에 안 들어갔다")

        // 폼으로 세는 종은 도감 키가 갈린다 — 이게 시드로 확인하려는 것이다.
        store.applyGenderSeed(speciesID: 678, gender: .female)
        XCTAssertTrue(store.state.dexForms.contains("678/meowstic-f"))
    }

    // MARK: 성별로 갈리는 진화 (여섯 갈래)

    /// 눈꼬마(361) — 암컷만 눈여아(478)가 된다. 수컷은 눈설왕(460)만.
    func testOnlyAFemaleSnoruntCanBecomeFroslass() {
        let store = makeStore()
        // 새벽의돌 갈래(눈여아)와 레벨 갈래(눈설왕)를 함께 둔 트리.
        let tree = EvoNode(speciesID: 361, children: [
            EvoNode(speciesID: 460, children: [], requirementRaw: .level(42)),
            EvoNode(speciesID: 478, children: [], requirementRaw: .level(42),
                    requiredGender: .female),
        ])
        let line = EvoLine(baseID: 361, tree: tree, rarity: .common, names: [:])

        let female = Individual(baseID: 361, speciesID: 361, pathIDs: [361], gender: .female,
                                nature: .hardy, obtainedAt: now, grade: .common)
        XCTAssertEqual(Set(store.evolutionChoices(female, line: line)), [460, 478])

        let male = Individual(baseID: 361, speciesID: 361, pathIDs: [361], gender: .male,
                              nature: .hardy, obtainedAt: now, grade: .common)
        XCTAssertEqual(store.evolutionChoices(male, line: line), [460],
                       "수컷 눈꼬마가 눈여아가 된다")
    }

    /// 성별을 아직 모르는 개체는 제한 있는 갈래가 막힌다 — 열어 두면 되돌릴 수 없는 진화를 한다.
    func testAnUnknownGenderCannotTakeAGatedBranch() {
        let store = makeStore()
        let tree = EvoNode(speciesID: 361, children: [
            EvoNode(speciesID: 460, children: [], requirementRaw: .level(42)),
            EvoNode(speciesID: 478, children: [], requirementRaw: .level(42),
                    requiredGender: .female),
        ])
        let line = EvoLine(baseID: 361, tree: tree, rarity: .common, names: [:])
        let unknown = Individual(baseID: 361, speciesID: 361, pathIDs: [361],
                                 nature: .hardy, obtainedAt: now, grade: .common)
        XCTAssertNil(unknown.gender)
        XCTAssertEqual(store.evolutionChoices(unknown, line: line), [460],
                       "성별을 모르는데 암컷 전용 갈래가 열렸다")
    }

    /// 제한이 없는 갈래는 성별과 무관하게 늘 열린다(게이트가 전부를 막고 있지 않은지 — 대조군).
    func testAnUngatedBranchStaysOpenForEveryGender() {
        let store = makeStore()
        let tree = EvoNode(speciesID: 1, children: [
            EvoNode(speciesID: 2, children: [], requirementRaw: .level(16)),
        ])
        let line = EvoLine(baseID: 1, tree: tree, rarity: .common, names: [:])
        for gender in [Gender.male, .female, .genderless] {
            let individual = Individual(baseID: 1, speciesID: 1, pathIDs: [1], gender: gender,
                                        nature: .hardy, obtainedAt: now, grade: .common)
            XCTAssertEqual(store.evolutionChoices(individual, line: line), [2],
                           "\(gender) 가 제한 없는 갈래에서 막혔다")
        }
    }

    /// 성별 제한이 트리를 다시 만드는 자리(`keepingSupportedSpecies`)에서 새지 않는다 —
    /// 여기서 새면 **모든 라인에서** 새고, 수컷 눈꼬마가 눈여아가 된다.
    func testTheGenderGateSurvivesTreePruning() throws {
        let tree = EvoNode(speciesID: 361, children: [
            EvoNode(speciesID: 478, children: [], requirementRaw: .level(42),
                    requiredGender: .female),
        ])
        // EvoLine.init 이 항상 keepingSupportedSpecies 를 지난다.
        let line = EvoLine(baseID: 361, tree: tree, rarity: .common, names: [:])
        let node = try XCTUnwrap(line.tree.node(withID: 478))
        XCTAssertEqual(node.requiredGender, .female, "가지치기가 성별 제한을 떨어뜨렸다")
    }

    /// API 응답의 성별 코드가 올바로 읽힌다(1=암컷, 2=수컷, 없으면 제한 없음).
    func testTheAPIGenderCodeMapsCorrectly() {
        func detail(_ gender: Int?) -> [EvolutionDetail] {
            [EvolutionDetail(trigger: nil, item: nil, held_item: nil, min_happiness: nil,
                             min_level: nil, gender: gender)]
        }
        XCTAssertEqual(PokeAPIClient.gender(from: detail(1)), .female)
        XCTAssertEqual(PokeAPIClient.gender(from: detail(2)), .male)
        XCTAssertNil(PokeAPIClient.gender(from: detail(nil)))
        XCTAssertNil(PokeAPIClient.gender(from: nil))
    }

    // MARK: 그림과 도감

    /// 암컷 그림은 **실측한 98종에만** 붙는다. 없는 종에 붙이면 그 칸이 통째로 빈다.
    func testFemaleSlugsOnlyExistForMeasuredSpecies() {
        XCTAssertEqual(GenderSpriteCatalog.femaleSprite.count, 98)
        XCTAssertEqual(GenderSpriteCatalog.femaleSlug(25), "pikachu-f")
        XCTAssertNil(GenderSpriteCatalog.femaleSlug(1), "이상해씨엔 암컷 그림이 없다")
        // 폼으로 세는 넷은 모두 그림이 있는 종의 부분집합이어야 한다.
        XCTAssertTrue(GenderSpriteCatalog.formSpecies.isSubset(of: GenderSpriteCatalog.femaleSprite))
    }

    /// **지방 모습이 암컷 그림을 이긴다** — `raichu-alola-f` 는 존재하지 않아서, 여기서
    /// 가로채면 알로라 라이츄의 그림이 사라진다.
    func testARegionalFormBeatsTheFemaleSprite() {
        var alolan = Individual(baseID: 172, speciesID: 26, pathIDs: [26], gender: .female,
                                nature: .hardy, obtainedAt: now, grade: .common)
        alolan.region = .alola
        XCTAssertEqual(alolan.spriteForm, "raichu-alola")

        var plain = Individual(baseID: 172, speciesID: 26, pathIDs: [26], gender: .female,
                               nature: .hardy, obtainedAt: now, grade: .common)
        plain.region = nil
        XCTAssertEqual(plain.spriteForm, "raichu-f")
    }

    /// 도감은 **폼으로 세는 넷만** 나눈다 — 나머지 94종은 겉모습 차이라 한 칸을 공유한다.
    func testOnlyTheFourFormSpeciesSplitTheDex() {
        func key(_ id: Int, _ gender: Gender) -> String {
            DexKey.key(for: Individual(baseID: id, speciesID: id, pathIDs: [id], gender: gender,
                                       nature: .hardy, obtainedAt: now, grade: .common))
        }
        // 냐오닉스 — 본가도 별개 폼이라 도감이 갈린다.
        XCTAssertEqual(key(678, .female), "678/meowstic-f")
        XCTAssertEqual(key(678, .male), "678")
        // 피카츄 — 하트 꼬리 하나로 두 번 모으게 하지 않는다.
        XCTAssertEqual(key(25, .female), "25")
        XCTAssertEqual(key(25, .male), "25")
    }
}
