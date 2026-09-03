import XCTest
@testable import PokeTokenBar

// MARK: 이로치 부적 (보유형 · 부화 shiny 확률↑)

private func scNode(_ id: Int, _ ch: [EvoNode] = []) -> EvoNode { EvoNode(speciesID: id, children: ch) }
private func scLine(base: Int) -> EvoLine {
    EvoLine(baseID: base, tree: scNode(base), rarity: .common,
            names: [base: ["en": "P\(base)", "ko": "포\(base)", "ja": "ポ\(base)"]])
}
private struct CharmStubProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { scLine(base: baseSpeciesID) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [BaseSpecies(id: 1, captureRate: 255)] }
}

@MainActor
final class ShinyCharmTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    /// 지갑/부적 보유를 지정한 알(active=null) 상태 스토어.
    private func store(used: Int = 5_000_000_000, spent: Int = 0, charm: Bool = false, seed: UInt64 = 7) -> CompanionStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("charm-\(UUID().uuidString).json")
        let inv = charm ? ",\"inventory\":{\"shinyCharm\":1}" : ""
        let json = "{\"installBaselineSet\":true,\"usedSinceInstall\":\(used),\"spentTokens\":\(spent),"
            + "\"lastDate\":\"d\",\"active\":null,\"dex\":[],\"collectedFinals\":[]\(inv)}"
        try? json.data(using: .utf8)!.write(to: url)
        return CompanionStore(provider: CharmStubProvider(), clock: { self.now }, fileURL: url, rng: SeededRNG(seed: seed))
    }

    // MARK: 순수 판정 — 부적 유무로 분모가 48/64 로 바뀌며 판정이 뒤집힌다

    func testRollsShinyFlipsWithCharm() {
        // roll=48: 부적 있으면 shiny(48%48==0), 없으면 아님(48%64≠0)
        XCTAssertTrue(CompanionStore.rollsShiny(roll: 48, charmOwned: true))
        XCTAssertFalse(CompanionStore.rollsShiny(roll: 48, charmOwned: false))
        // roll=64: 부적 없으면 shiny, 있으면 아님(64%48≠0)
        XCTAssertTrue(CompanionStore.rollsShiny(roll: 64, charmOwned: false))
        XCTAssertFalse(CompanionStore.rollsShiny(roll: 64, charmOwned: true))
        // roll=96: 부적 있으면 shiny(96%48==0), 없으면 아님(96%64≠0)
        XCTAssertTrue(CompanionStore.rollsShiny(roll: 96, charmOwned: true))
        XCTAssertFalse(CompanionStore.rollsShiny(roll: 96, charmOwned: false))
        // roll=0: 둘 다 shiny · roll=1: 둘 다 아님
        XCTAssertTrue(CompanionStore.rollsShiny(roll: 0, charmOwned: true))
        XCTAssertTrue(CompanionStore.rollsShiny(roll: 0, charmOwned: false))
        XCTAssertFalse(CompanionStore.rollsShiny(roll: 1, charmOwned: true))
        XCTAssertFalse(CompanionStore.rollsShiny(roll: 1, charmOwned: false))
    }

    func testConstantsAndPassiveFlag() {
        XCTAssertEqual(ShinyCharm.price, 3_000_000_000)
        XCTAssertEqual(ShinyCharm.shinyDenominator, 48)
        XCTAssertTrue(ItemKind.shinyCharm.isPassive)
        XCTAssertFalse(ItemKind.rareCandy.isPassive)
        XCTAssertFalse(ItemKind.mint.isPassive)
        XCTAssertEqual(ItemKind.shinyCharm.spriteName, "shiny-charm")
    }

    // MARK: 구매 / 보유 (보유형 = 1회 구매)

    func testBuyDeductsAndOwns() {
        let s = store(used: 5_000_000_000, spent: 0, charm: false)
        XCTAssertFalse(s.ownsShinyCharm)
        XCTAssertTrue(s.purchasableItems.contains(.shinyCharm), "상점에 노출")
        XCTAssertTrue(s.canBuy(.shinyCharm))
        XCTAssertTrue(s.buy(.shinyCharm))
        XCTAssertTrue(s.ownsShinyCharm)
        XCTAssertEqual(s.itemCount(.shinyCharm), 1)
        XCTAssertEqual(s.state.spentTokens, ShinyCharm.price, "지갑에서 3B 차감")
        XCTAssertEqual(s.availableTokens, 5_000_000_000 - ShinyCharm.price)
    }

    /// 보유형은 재구매 불가 — canBuy false, buy no-op, 지출/개수 불변.
    func testBuyOnceNoRepurchase() {
        let s = store(used: 10_000_000_000, charm: true)
        XCTAssertTrue(s.ownsShinyCharm)
        XCTAssertFalse(s.canBuy(.shinyCharm), "보유형은 재구매 불가")
        let spentBefore = s.state.spentTokens
        XCTAssertFalse(s.buy(.shinyCharm), "재구매 no-op")
        XCTAssertEqual(s.state.spentTokens, spentBefore, "지출 불변")
        XCTAssertEqual(s.itemCount(.shinyCharm), 1, "개수 1 유지(2 안 됨)")
    }

    func testCanBuyNeedsEnoughTokens() {
        let s = store(used: 2_000_000_000)   // 3B 미만
        XCTAssertFalse(s.canBuy(.shinyCharm))
        XCTAssertFalse(s.buy(.shinyCharm))
        XCTAssertFalse(s.ownsShinyCharm)
    }

    func testOwnsReflectsInventory() {
        XCTAssertFalse(store(charm: false).ownsShinyCharm)
        XCTAssertTrue(store(charm: true).ownsShinyCharm)
    }

    // MARK: 부화 통합 (스모크) — 부적 보유 상태에서 hatchCore 경로가 정상 동작

    func testHatchWorksWithCharmOwned() async {
        let s = store(used: 5_000_000_000, charm: true, seed: 7)
        await s.hatch(baseID: 1)
        XCTAssertNotNil(s.state.active, "부적 보유 상태에서도 정상 부화")
        XCTAssertEqual(s.currentSpeciesID, 1)
    }
}

// MARK: 이로치 스프라이트 갱신 (도감 이로치 토글)

/// 도감은 기본 일반색이고, 이로치 스위치를 켜면 speciesID 는 그대로인 채 shiny 만 뒤집힘.
/// 갱신 판정이 종만 비교하면 플래시 방지 가드가 토글을 삼켜 색이 안 바뀜.
@MainActor
final class SpriteShinyReloadTests: XCTestCase {
    func testShinyFlipReloadsSpriteForSameSpecies() {
        // 도감 토글의 두 방향 — 이 두 줄이 회귀의 본체다.
        XCTAssertTrue(SpriteView.needsReload(loadedID: 1, loadedShiny: false, id: 1, shiny: true),
                      "일반 → 이로치 토글이 갱신을 트리거해야 한다")
        XCTAssertTrue(SpriteView.needsReload(loadedID: 1, loadedShiny: true, id: 1, shiny: false),
                      "이로치 → 일반 토글도 마찬가지")
    }

    func testUnchangedSpriteSkipsReload() {
        // 같은 종·같은 이로치 여부면 재요청하지 않는다(재렌더 플래시 방지 가드 유지).
        XCTAssertFalse(SpriteView.needsReload(loadedID: 1, loadedShiny: false, id: 1, shiny: false))
        XCTAssertFalse(SpriteView.needsReload(loadedID: 1, loadedShiny: true, id: 1, shiny: true))
    }

    func testSpeciesChangeReloadsRegardlessOfShiny() {
        XCTAssertTrue(SpriteView.needsReload(loadedID: 1, loadedShiny: false, id: 2, shiny: false))
        XCTAssertTrue(SpriteView.needsReload(loadedID: nil, loadedShiny: false, id: 1, shiny: false),
                      "미로드(캐시 미스) 상태에서는 항상 불러온다")
    }

    /// [회귀] 토글이 켜진 상태에서 **새로 만들어지는 뷰**(토글 ON 뒤 상세 진입, 필터로 칸이 사라졌다
    /// 다시 생김)가 이로치를 영영 안 불러오던 결함 — init 이 폴백 이미지를 받고도 요청값을 그대로
    /// `loadedShiny` 에 적어 `needsReload` 가 거짓이 됐음. 위 테스트들은 그 값을 입력으로 주는 터라
    /// 어떻게 정해지는지는 안 봄.
    func testShinySeedIsFalseWhenOnlyNonShinyCacheExists() {
        // 트리거 조건 — 이로치를 요청했는데 캐시가 없어 일반 폴백을 받는 경우.
        XCTAssertFalse(SpriteView.seededShiny(requestedShiny: true, shinyCacheHit: false),
                       "일반 폴백을 받고 이로치라고 기록하면 재로드가 영영 안 돎")
        // 그래서 첫 판정이 반드시 '불러와라' — 결함이 실제로 막히는 지점.
        XCTAssertTrue(SpriteView.needsReload(
            loadedID: 25,
            loadedShiny: SpriteView.seededShiny(requestedShiny: true, shinyCacheHit: false),
            id: 25, shiny: true))
    }

    func testShinySeedIsTrueOnlyWhenShinyCacheActuallyHit() {
        // 진짜 이로치 캐시가 있으면 참 — 시드의 존재 이유(재요청·플래시 방지)는 유지.
        XCTAssertTrue(SpriteView.seededShiny(requestedShiny: true, shinyCacheHit: true))
        XCTAssertFalse(SpriteView.needsReload(
            loadedID: 25,
            loadedShiny: SpriteView.seededShiny(requestedShiny: true, shinyCacheHit: true),
            id: 25, shiny: true), "이로치 캐시 적중이면 재요청 없음")
        // 일반색으로 그리는 뷰는 이로치 캐시 유무와 무관하게 항상 거짓.
        XCTAssertFalse(SpriteView.seededShiny(requestedShiny: false, shinyCacheHit: true))
        XCTAssertFalse(SpriteView.seededShiny(requestedShiny: false, shinyCacheHit: false))
    }
}
