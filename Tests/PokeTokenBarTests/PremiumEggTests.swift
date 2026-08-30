import XCTest
@testable import PokeTokenBar

// MARK: 등급 보증 알 (고급 이상 / 희귀 이상)
//
// 보증의 구현은 "capture_rate 상한 = 등급 하한"이라는 등식에 통째로 기대고 있다. 그 등식이 깨지는
// 경로가 넷이라 각각을 트리거 브랜치로 재현한다:
//   ① Rarity.captureRateCeiling 과 Rarity.from 의 임계가 갈림       → 전수 불변식 테스트
//   ② 가중 선택(chooseBase)이 하한 미만을 뽑음                       → 대조군과 함께 반복 부화
//   ③ REST 폴백(chooseBaseViaREST)만 필터를 안 탐                    → 인덱스를 죽이고 같은 검증
//   ④ 인덱스가 stale 이라 뽑은 종의 실제 등급이 하한 미만            → 부화 직전 최종 관문

/// capture_rate 로 등급이 갈리는 다종 인덱스. 라인의 등급은 인덱스와 **같은 규칙**으로 계산한다.
private struct TieredProvider: PokeProviding {
    static let entries = [
        BaseSpecies(id: 1, captureRate: 255),   // common
        BaseSpecies(id: 2, captureRate: 100),   // uncommon
        BaseSpecies(id: 3, captureRate: 30),    // rare
        BaseSpecies(id: 4, captureRate: 3),     // legendary (아래 legendaryIDs)
    ]
    var legendaryIDs: Set<Int> = [4]
    var indexThrows = false

    func baseSpeciesIndex() async throws -> [BaseSpecies] {
        if indexThrows { throw URLError(.badServerResponse) }
        return Self.entries
    }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { Self.entries.first { $0.id == id } }
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        guard let e = Self.entries.first(where: { $0.id == baseSpeciesID }) else { throw URLError(.badURL) }
        return EvoLine(baseID: e.id, tree: EvoNode(speciesID: e.id, children: []),
                       rarity: Rarity.from(captureRate: e.captureRate,
                                           isLegendary: legendaryIDs.contains(e.id), isMythical: false),
                       names: [e.id: ["en": "M\(e.id)"]])
    }
}

/// GraphQL 인덱스는 죽고 REST 만 사는 상황. 모든 id 가 base 이고 capture_rate 는 id 로 결정된다
/// (3의 배수 = rare 30 · 그 외 짝수 = uncommon 100 · 나머지 = common 255) → 폴백의 rejection sampling 이
/// 실제로 여러 번 돌면서 필터를 밟는다.
private struct RestOnlyTieredProvider: PokeProviding {
    static func captureRate(_ id: Int) -> Int { id % 3 == 0 ? 30 : (id % 2 == 0 ? 100 : 255) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { throw URLError(.badServerResponse) }
    func baseSpecies(id: Int) async throws -> BaseSpecies? {
        BaseSpecies(id: id, captureRate: Self.captureRate(id))
    }
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: baseSpeciesID, tree: EvoNode(speciesID: baseSpeciesID, children: []),
                rarity: Rarity.from(captureRate: Self.captureRate(baseSpeciesID),
                                    isLegendary: false, isMythical: false),
                names: [baseSpeciesID: ["en": "M\(baseSpeciesID)"]])
    }
}

/// 인덱스는 "희귀(capture_rate 30)"라고 하는데 실제 라인은 common — stale 인덱스 시뮬.
private struct LyingIndexProvider: PokeProviding {
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [BaseSpecies(id: 7, captureRate: 30)] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { BaseSpecies(id: 7, captureRate: 30) }
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: 7, tree: EvoNode(speciesID: 7, children: []),
                rarity: .common, names: [7: ["en": "Liar"]])
    }
}

@MainActor
final class PremiumEggTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func url() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("premium-egg-\(UUID().uuidString).json")
    }

    /// 활성 포켓몬이 있는 상태(리롤 가능) + 지갑.
    private func activeStore(used: Int = 20_000_000_000, provider: any PokeProviding = TieredProvider(),
                             at file: URL? = nil) -> CompanionStore {
        let f = file ?? url()
        let mon = "{\"baseID\":10,\"pathIDs\":[10],\"stageIndex\":0,\"usedAtStage\":200000000,"
            + "\"rarity\":\"common\",\"totalForms\":3,\"isShiny\":false}"
        let json = "{\"installBaselineSet\":true,\"usedSinceInstall\":\(used),\"spentTokens\":0,"
            + "\"lastDate\":\"d\",\"active\":\(mon),\"dex\":[],\"collectedFinals\":[]}"
        try? json.data(using: .utf8)!.write(to: f)
        return CompanionStore(provider: provider, clock: { self.now }, fileURL: f, rng: SeededRNG(seed: 7))
    }

    /// 부화 직전 알(임계 충족) + 보증 등급. seed 로 롤을 바꾼다.
    private func eggStore(tier: Rarity?, seed: UInt64, provider: any PokeProviding) -> CompanionStore {
        let f = url()
        let tierJSON = tier.map { "\"\($0.rawValue)\"" } ?? "null"
        let json = "{\"installBaselineSet\":true,\"usedSinceInstall\":10000000,\"spentTokens\":0,"
            + "\"lastDate\":\"d\",\"active\":null,\"dex\":[],\"collectedFinals\":[],"
            + "\"eggUsage\":\(PokemonBalance.eggHatchThreshold),\"eggTier\":\(tierJSON)}"
        try? json.data(using: .utf8)!.write(to: f)
        return CompanionStore(provider: provider, clock: { self.now }, fileURL: f, rng: SeededRNG(seed: seed))
    }

    // MARK: ① 임계 단일 소스 — 필터와 분류가 갈리면 보증이 조용히 깨진다

    /// capture_rate 전 구간 × 등급 전수. `includes(captureRate:)` 가 참인 것과 `from` 이 그 등급 이상으로
    /// 분류하는 것이 **정확히 일치**해야 한다. 한쪽 임계만 바꾸면 여기서 깨진다.
    func testCaptureRateCeilingIsTheSameThresholdAsClassification() {
        for cr in 0...255 {
            let classified = Rarity.from(captureRate: cr, isLegendary: false, isMythical: false)
            for tier in [Rarity.common, .uncommon, .rare] {
                XCTAssertEqual(tier.includes(captureRate: cr),
                               classified.sortRank >= tier.sortRank,
                               "capture_rate \(cr) 이 \(tier) 이상인지 판정이 분류와 어긋남(분류=\(classified))")
            }
        }
    }

    /// 전설은 capture_rate 로 판정할 수 없다(인덱스에 is_legendary 가 없음) → 필터 대상 아님.
    /// 동시에 전설은 전원 capture_rate ≤ 45 라 고급·희귀 필터에 **자연히 포함**된다("이상" 규칙 성립).
    func testLegendaryHasNoCaptureRateCeilingButPassesLowerTierFilters() {
        XCTAssertNil(Rarity.legendary.captureRateCeiling)
        XCTAssertFalse(Rarity.legendary.includes(captureRate: 3))
        // 실제 전설의 capture_rate 대역(3·30·45)은 고급/희귀 필터를 모두 통과한다.
        for cr in [3, 30, 45] {
            XCTAssertTrue(Rarity.rare.includes(captureRate: cr))
            XCTAssertTrue(Rarity.uncommon.includes(captureRate: cr))
        }
        XCTAssertFalse(FreshEgg.shopTiers.contains(.legendary), "전설 전용 알은 팔지 않는다")
    }

    // MARK: 가격 — 졸업 총량 배율(새 상수 금지)

    func testPricesFollowGraduationTotalRatio() {
        XCTAssertEqual(FreshEgg.price(guaranteeing: nil), 1_000_000_000)
        XCTAssertEqual(FreshEgg.price(guaranteeing: .uncommon), 2_500_000_000)
        XCTAssertEqual(FreshEgg.price(guaranteeing: .rare), 4_000_000_000)
        XCTAssertEqual(FreshEgg.shopTiers, [nil, .uncommon, .rare])
    }

    /// 상위 티어가 하위 티어 반복 구매보다 싸야 존재 이유가 있다(희귀+ 1마리당 비용).
    ///
    /// 비율을 상수로 적어 두고 단언하면 가격 상수만 지키는 동어반복이 된다 — 실제 풀이 어떻든 통과한다.
    /// 그래서 **측정한 풀 가중치에서 비율을 계산**해 손익분기와 비교한다. 가중은 `chooseBase` 와 같은 식
    /// (capture_rate 합).
    ///
    /// 미수집 부스트(`chooseBase` 가 이미 수집한 base 의 가중을 절반으로)는 정가 계산에서 뺐다. 그 방향은
    /// 중립이 아니라 **불리**하다 — 고급 밴드가 먼저 포화되면 그쪽 가중만 깎여 희귀+ 비중이 올라간다:
    /// 고급 ×0.75 → 0.5906, ×0.70 → 0.6072, ×0.5 → 0.6839. 뒤집히는 지점은 **×0.6492**이고 그보다
    /// 낮아지면 손익분기 0.625를 넘는다. 도감을 많이 채운 후반일수록 마진이 준다는 뜻이다.
    /// 그 너머(고급 밴드 거의 수집 + 희귀 밴드 거의 미수집)는 뒤집히지만 재가격하지 않는다 — 1인 로컬·
    /// 금전가치 없음이라 후반 코너에서 상위 알이 약간 손해인 것은 수용 범위다.
    ///
    /// 출처: PokéAPI GraphQL v1beta2, `evolves_from_species_id IS NULL` · id ≤ 649 · 메타몽 제외,
    /// 2026-08-04 측정(base 328종). 풀이 크게 바뀌면 이 값을 다시 재고 결론을 재확인해야 한다.
    func testRareEggIsNotDominatedAtMeasuredPoolComposition() {
        let weight: [Rarity: Double] = [.common: 37_240, .uncommon: 3_135, .rare: 3_053, .legendary: 339]
        // 고급 알 = 고급 이상 풀(전설 포함). 그 안에서 희귀 이상이 나올 확률.
        let uncommonEggPool = weight[.uncommon]! + weight[.rare]! + weight[.legendary]!
        let rarePlusShare = (weight[.rare]! + weight[.legendary]!) / uncommonEggPool

        let uncommonPrice = Double(FreshEgg.price(guaranteeing: .uncommon))
        let rarePrice = Double(FreshEgg.price(guaranteeing: .rare))
        // 희귀+ 1마리당 비용: 고급 알 반복(확률적) vs 희귀 알 1개(확정).
        XCTAssertLessThan(rarePrice, uncommonPrice / rarePlusShare,
                          "희귀 알이 고급 알 반복 구매보다 비싸면 상위 티어가 완전 열등재가 된다")
        // 손익분기 = 고급가/희귀가. 실측 비율이 이 선을 넘으면 위 부등식이 뒤집힌다.
        XCTAssertLessThan(rarePlusShare, uncommonPrice / rarePrice,
                          "실측 희귀+ 비중 \(rarePlusShare) 가 손익분기 \(uncommonPrice / rarePrice) 를 넘었다 — 가격 재조정 필요")

        // 후반 코너의 안전 경계 — 고급 밴드만 미수집 부스트로 30% 깎여도 아직 지배당하지 않는다.
        // 계수는 flip 지점(×0.6492)이 아니라 **그보다 위**로 잡는다: 정확히 flip 에 걸면 여유가 0.0003 이라
        // 풀을 다시 잴 때 고급 가중이 0.13%(≈4)만 움직여도 설계와 무관하게 실패한다(오탐). ×0.70 은 여유
        // 0.018 이라 재측정을 견디면서도 "부스트가 마진을 깎는다"는 성질은 그대로 잡는다.
        let boostedUncommon = weight[.uncommon]! * 0.70
        let boostedShare = (weight[.rare]! + weight[.legendary]!)
            / (boostedUncommon + weight[.rare]! + weight[.legendary]!)
        XCTAssertLessThan(boostedShare, uncommonPrice / rarePrice,
                          "고급 밴드가 부분 포화된 구간에서 이미 희귀 알이 열등재가 된다")
    }

    // MARK: 구매 — 게이트·차감·보증 기록

    func testBuyPremiumEggRecordsGuaranteeAndDebitsTierPrice() {
        let s = activeStore()
        XCTAssertTrue(s.canBuyEgg(.rare))
        XCTAssertTrue(s.buyEgg(.rare))
        XCTAssertEqual(s.state.eggTier, .rare, "보증이 상태에 기록됨")
        XCTAssertEqual(s.eggGuarantee, .rare)
        XCTAssertEqual(s.state.spentTokens, FreshEgg.price(guaranteeing: .rare))
        XCTAssertNil(s.state.active, "현재 포켓몬은 더 이상 활성이 아니다")
        XCTAssertEqual(s.state.eggUsage, 0, "새 알은 처음부터 인큐베이션")
        // 등급 알도 새 알과 같은 놓아줌 경로를 쓴다 — 종은 남기되 졸업으로 세지는 않는다.
        XCTAssertEqual(s.state.dex.count, 1, "놓아준 개체가 기록으로 남는다")
        XCTAssertTrue(s.state.dex.first?.isReleased ?? false, "졸업이 아니라 놓아줌")
        XCTAssertTrue(s.state.collectedFinals.isEmpty, "최종체 완성으로 세지 않는다")
    }

    /// 알 상태에선 등급 알도 못 산다 — 기존 새 알과 게이트 통일.
    func testCannotBuyAnyEggWhileIncubating() {
        let s = eggStore(tier: nil, seed: 1, provider: TieredProvider())
        XCTAssertFalse(s.hasActive)
        for tier in FreshEgg.shopTiers {
            XCTAssertFalse(s.canBuyEgg(tier))
            XCTAssertFalse(s.buyEgg(tier))
        }
        XCTAssertEqual(s.state.spentTokens, 0, "no-op")
    }

    /// 잔액이 그 **티어의** 가격에 미달이면 불가 — 기본 알은 살 수 있어도 희귀 알은 못 산다.
    func testFundsAreCheckedAgainstTierPrice() {
        let s = activeStore(used: 3_000_000_000)   // 1B·2.5B 는 되고 4B 는 안 되는 잔액
        XCTAssertTrue(s.canBuyEgg(nil))
        XCTAssertTrue(s.canBuyEgg(.uncommon))
        XCTAssertFalse(s.canBuyEgg(.rare))
        XCTAssertFalse(s.buyEgg(.rare))
        XCTAssertNotNil(s.state.active, "실패 시 활성 유지")
        XCTAssertEqual(s.state.spentTokens, 0)
    }

    /// 이전 보증으로 미리 뽑아둔 종(pendingHatchID)은 구매 시 버려야 한다 — 안 버리면 보증 없이 뽑은
    /// 종이 그대로 프리미엄 알에서 부화한다.
    /// 구매한 알은 깨끗한 롤 상태에서 출발한다 — 보증이 걸리고, 미리 뽑아둔 종은 남아 있지 않다.
    /// (활성 포켓몬과 pre-roll 은 애초에 공존하지 않는다: 프리패치는 알 상태에서만 돌고 `hatchIfNeeded`
    /// 가 부화 직전 비운다. 그 불변식이 밖에서 들어온 파일에도 유지되는지는
    /// `testSanitizedDropsGuaranteeAndItsPreRollWhenActiveExists` 가 지킨다.)
    func testPurchaseStartsFromCleanRollState() {
        let s = activeStore()
        XCTAssertNil(s.state.pendingHatchID, "활성 포켓몬이 있는 동안엔 pre-roll 이 없다")
        XCTAssertTrue(s.buyEgg(.rare))
        XCTAssertEqual(s.state.eggTier, .rare)
        XCTAssertNil(s.state.pendingHatchID, "새 보증으로 다시 롤한다")
        XCTAssertEqual(s.state.eggUsage, 0)
    }

    /// 보증은 재시작을 건너 살아남아야 한다 — 구매 시점엔 종을 못 정하기 때문(롤에 네트워크 필요).
    func testGuaranteeSurvivesRestart() {
        let f = url()
        let s1 = activeStore(at: f)
        XCTAssertTrue(s1.buyEgg(.uncommon))
        let s2 = CompanionStore(provider: TieredProvider(), clock: { self.now }, fileURL: f, rng: SeededRNG(seed: 7))
        XCTAssertEqual(s2.state.eggTier, .uncommon, "재시작 후에도 산 보증 유지")
        XCTAssertEqual(s2.eggGuarantee, .uncommon)
    }

    // MARK: ② 가중 선택이 하한 미만을 뽑지 않는다 (대조군 포함)

    /// 희귀 알로 20회 부화 → 전부 희귀 이상. 같은 seed 집합의 **무보증 대조군**은 common 을 실제로 뽑아야
    /// 한다 — 대조군이 common 을 못 뽑으면 이 테스트는 필터를 밟지 않고 통과하는 셈이다.
    func testWeightedRollNeverGoesBelowGuarantee() async {
        var guaranteedRarities: [Rarity] = []
        var controlRarities: [Rarity] = []
        for seed in UInt64(1)...20 {
            let g = eggStore(tier: .rare, seed: seed, provider: TieredProvider())
            await g.hatchIfNeeded()
            if let r = g.state.active?.rarity { guaranteedRarities.append(r) }
            let c = eggStore(tier: nil, seed: seed, provider: TieredProvider())
            await c.hatchIfNeeded()
            if let r = c.state.active?.rarity { controlRarities.append(r) }
        }
        XCTAssertEqual(guaranteedRarities.count, 20, "20회 모두 부화해야 필터가 실제로 검증된다")
        for r in guaranteedRarities {
            XCTAssertGreaterThanOrEqual(r.sortRank, Rarity.rare.sortRank, "희귀 알에서 \(r) 부화")
        }
        XCTAssertTrue(controlRarities.contains(.common),
                      "대조군이 common 을 한 번도 안 뽑으면 결함 조건이 살아있지 않은 것")
    }

    /// 고급 알은 common **만** 배제한다 — 고급·희귀·전설은 모두 정상 결과다(전설 포함이 의도).
    ///
    /// `r != .common` 만 보면 **과잉 필터**를 못 잡는다: 두 롤 경로가 `tier` 를 무시하고 늘 희귀로
    /// 걸러도 이 단언은 통과하고, 그러면 2.5B 고급 알과 4B 희귀 알의 풀이 같아져 희귀 알이 완전
    /// 열등재가 된다(가격 근거가 통째로 무너지는데 테스트는 초록). 그래서 **고급이 실제로 나오는지**를
    /// 함께 못박는다 — 산 티어가 그대로 필터에 전달된다는 증거.
    func testUncommonEggHatchesUncommonAndExcludesOnlyCommon() async {
        var sawUncommon = false
        for seed in UInt64(1)...20 {
            let s = eggStore(tier: .uncommon, seed: seed, provider: TieredProvider())
            await s.hatchIfNeeded()
            guard let r = s.state.active?.rarity else { return XCTFail("부화 실패 seed \(seed)") }
            XCTAssertNotEqual(r, .common)
            if r == .uncommon { sawUncommon = true }
        }
        XCTAssertTrue(sawUncommon,
                      "고급 알이 고급을 한 번도 안 뽑으면 산 티어가 아니라 더 좁은 등급으로 걸러지고 있는 것")
    }

    /// 전설은 등급 알에서 배제되지 않는다 — "고급/희귀 이상"에 자연 가중으로 포함된다.
    func testLegendaryStillReachableFromPremiumEgg() async {
        var sawLegendary = false
        for seed in UInt64(1)...60 {
            let s = eggStore(tier: .rare, seed: seed, provider: TieredProvider())
            await s.hatchIfNeeded()
            if s.state.active?.rarity == .legendary { sawLegendary = true; break }
        }
        XCTAssertTrue(sawLegendary, "희귀 알 풀에 전설이 남아 있어야 한다(전설 전용 상품만 금지)")
    }

    // MARK: ③ REST 폴백 단독 — 가중 경로가 통과해도 이 경로가 통과하지는 않는다

    func testRestFallbackRespectsGuarantee() async {
        var hatched = 0
        for seed in UInt64(1)...10 {
            let s = eggStore(tier: .rare, seed: seed, provider: RestOnlyTieredProvider())
            await s.hatchIfNeeded()
            guard let r = s.state.active?.rarity else { continue }   // 16회 소진(≈0.15%)은 알 유지가 정상
            hatched += 1
            XCTAssertEqual(r, .rare, "REST 폴백이 보증을 무시하고 \(r) 를 뽑음")
        }
        XCTAssertGreaterThan(hatched, 0, "폴백 경로가 한 번도 안 돌면 검증이 아니다")
    }

    /// 폴백 경로도 **산 티어 그대로** 걸러야 한다 — 여기서 tier 를 무시하고 늘 희귀로 좁히면 고급 알이
    /// 희귀 알과 같은 풀이 된다. common 미출현 + 고급 실제 출현을 함께 못박아 과잉 필터를 잡는다.
    func testRestFallbackHonoursUncommonTierWithoutOverFiltering() async {
        var sawUncommon = false
        for seed in UInt64(1)...20 {
            let s = eggStore(tier: .uncommon, seed: seed, provider: RestOnlyTieredProvider())
            await s.hatchIfNeeded()
            guard let r = s.state.active?.rarity else { continue }
            XCTAssertNotEqual(r, .common, "REST 폴백이 고급 알에 common 을 내줌")
            if r == .uncommon { sawUncommon = true }
        }
        XCTAssertTrue(sawUncommon, "폴백에서 고급이 한 번도 안 나오면 희귀로 과잉 필터되고 있는 것")
    }

    /// 대조군 — 같은 폴백 provider 에서 보증이 없으면 common 도 나온다(위 테스트가 필터를 밟는다는 증거).
    func testRestFallbackWithoutGuaranteeCanHatchCommon() async {
        var sawCommon = false
        for seed in UInt64(1)...20 {
            let s = eggStore(tier: nil, seed: seed, provider: RestOnlyTieredProvider())
            await s.hatchIfNeeded()
            if s.state.active?.rarity == .common { sawCommon = true; break }
        }
        XCTAssertTrue(sawCommon)
    }

    // MARK: ④ 최종 관문 — 인덱스가 거짓말해도 산 보증을 내주지 않는다

    /// 인덱스는 capture_rate 30(희귀)이라 했는데 실제 라인이 common 인 경우: 부화시키지 말고 알을 유지한 채
    /// pre-roll 만 버려 다음 틱에 다시 뽑는다. 낮은 등급을 내주면 사용자는 산 것을 못 받는다.
    func testHatchDiscardsSpeciesBelowGuaranteeWhenIndexIsStale() async {
        let s = eggStore(tier: .rare, seed: 1, provider: LyingIndexProvider())
        await s.hatchIfNeeded()
        XCTAssertNil(s.state.active, "하한 미만이면 부화시키지 않는다")
        XCTAssertNil(s.state.pendingHatchID, "다음 틱에 다시 뽑도록 pre-roll 폐기")
        XCTAssertEqual(s.state.eggTier, .rare, "보증은 그대로 유지")
        XCTAssertEqual(s.state.eggUsage, PokemonBalance.eggHatchThreshold, "인큐베이션 진행도 유지")
    }

    /// 대조군 — 같은 provider 라도 보증이 없으면 그 common 이 정상 부화한다(위 테스트가 가드를 밟는 증거).
    func testSameSpeciesHatchesNormallyWithoutGuarantee() async {
        let s = eggStore(tier: nil, seed: 1, provider: LyingIndexProvider())
        await s.hatchIfNeeded()
        XCTAssertEqual(s.state.active?.rarity, .common)
    }

    // MARK: 보증 소비 — 다음 알로 새면 영구 프리미엄이 된다

    func testHatchConsumesGuarantee() async {
        let s = eggStore(tier: .rare, seed: 1, provider: TieredProvider())
        await s.hatchIfNeeded()
        XCTAssertNotNil(s.state.active)
        XCTAssertNil(s.state.eggTier, "부화로 보증 소비")
        XCTAssertNil(s.eggGuarantee)
    }

    /// 졸업으로 받는 다음 알은 무료 알이어야 한다 — 보증이 따라가면 산 적 없는 프리미엄이 영구히 붙는다.
    /// 구매→부화→졸업 전 구간에서 보증이 되살아나지 않는지 실제 흐름으로 확인한다.
    func testGuaranteeDoesNotSurviveIntoTheNextEgg() async {
        let s = eggStore(tier: .rare, seed: 1, provider: TieredProvider())
        await s.hatchIfNeeded()
        guard let active = s.state.active else { return XCTFail("부화 실패") }
        XCTAssertNil(s.state.eggTier, "부화 시점에 보증 소비")
        s.applyUsage(PokemonBalance.graduationTotal(active.rarity) * 2)   // 단일 형태 → 졸업
        XCTAssertNil(s.state.active, "졸업")
        XCTAssertEqual(s.state.dex.count, 1)
        XCTAssertNil(s.state.eggTier, "졸업으로 받는 알에는 보증이 없다")
        XCTAssertNil(s.eggGuarantee)
    }

    // MARK: 세이브 이전 / 정규화

    /// 보증은 산 물건이지 기기 장부가 아니다 — 기기를 옮겨도 따라간다.
    func testGuaranteeTravelsWithSave() {
        var imported = CompanionState()
        imported.eggTier = .uncommon
        imported.usedSinceInstall = 1_000_000
        let rebased = SaveTransfer.rebasedForThisDevice(imported, current: CompanionState(),
                                                        todayTokensByProvider: ["test": 0], todayDate: "d", hasUsageData: true)
        XCTAssertEqual(rebased.eggTier, .uncommon)
    }

    /// 활성 포켓몬과 알 보증은 공존할 수 없다(알이 없으니까). 손편집·구버전 조합으로 둘 다 오면 떨군다 —
    /// 안 그러면 지금 개체가 졸업할 때 그 보증이 다음 알로 새어 영구 프리미엄이 된다.
    /// 그 보증으로 미리 뽑아둔 종(pendingHatchID)도 같이 버려야 한다: 보증만 지우면 졸업으로 받는 **무료**
    /// 알이 그 pre-roll 로 부화해 아무도 사지 않은 프리미엄 결과가 나온다.
    func testSanitizedDropsGuaranteeAndItsPreRollWhenActiveExists() {
        var s = CompanionState()
        s.eggTier = .rare
        s.pendingHatchID = 3
        s.active = MonState(baseID: 1, pathIDs: [1], stageIndex: 0, usedAtStage: 0,
                            rarity: .common, totalForms: 1)
        let cleaned = SaveTransfer.sanitized(s)
        XCTAssertNil(cleaned.eggTier)
        XCTAssertNil(cleaned.pendingHatchID, "보증으로 뽑아둔 종이 남으면 다음 무료 알이 그 결과를 받는다")
        // 알 상태(active 없음)에선 그대로 보존.
        var egg = CompanionState()
        egg.eggTier = .rare
        egg.pendingHatchID = 3
        XCTAssertEqual(SaveTransfer.sanitized(egg).eggTier, .rare)
        XCTAssertEqual(SaveTransfer.sanitized(egg).pendingHatchID, 3)
    }

    // MARK: 만족 불가능한 보증 — 알이 영구히 안 깨지는 벽돌 상태 방지

    /// 전설은 capture_rate 로 표현할 수 없어(ceiling nil) 두 롤 경로 모두 후보가 0개가 된다. 부화가 없으니
    /// 보증도 소비되지 않고, 새 알 구매는 `hasActive` 에 막혀 빠져나갈 수단이 없다 — 파일을 손으로 지우기
    /// 전엔 앱을 못 쓴다(디코드가 *성공*하므로 load() 의 .corrupt 복구도 안 걸린다).
    /// **디코드되는지가 아니라 실제로 부화하는지**를 검증한다 — 정규화가 빠지면 여기서 걸린다.
    func testUnsatisfiableGuaranteeIsNormalizedAwayAndEggStillHatches() async {
        let s = eggStore(tier: .legendary, seed: 1, provider: TieredProvider())
        XCTAssertNil(s.state.eggTier, "만족 불가능한 보증은 읽는 순간 떨어져 나간다")
        await s.hatchIfNeeded()
        XCTAssertNotNil(s.state.active, "알이 정상적으로 부화해야 한다(벽돌 상태 아님)")
    }

    /// 판매 목록에 없는 티어는 살 수 없다 — 가격만 계산되면(전설 8B) 호출부 하나가 실수했을 때 토큰이
    /// 통째로 사라지고 그 알은 영영 안 깨진다.
    func testCannotBuyTierThatIsNotSold() {
        let s = activeStore()
        XCTAssertFalse(FreshEgg.shopTiers.contains(.legendary))
        XCTAssertFalse(s.canBuyEgg(.legendary))
        XCTAssertFalse(s.buyEgg(.legendary))
        XCTAssertEqual(s.state.spentTokens, 0, "차감 없음")
        XCTAssertNotNil(s.state.active, "폐기 없음")
        XCTAssertFalse(s.canBuyEgg(.common), "기본 알은 tier nil 로만 판다")
    }

    /// 모르는 등급 rawValue 는 nil(보증 없음)로 강등 — 관대 디코딩의 안전한 방향.
    func testUnknownGuaranteeDecodesAsNoGuarantee() throws {
        let json = "{\"installBaselineSet\":true,\"usedSinceInstall\":0,\"spentTokens\":0,"
            + "\"lastDate\":\"d\",\"dex\":[],\"collectedFinals\":[],\"eggTier\":\"mythic\"}"
        let decoded = try JSONDecoder().decode(CompanionState.self, from: Data(json.utf8))
        XCTAssertNil(decoded.eggTier)
    }
}
