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
