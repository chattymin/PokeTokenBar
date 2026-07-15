import XCTest
@testable import PokeTokenBar

// MARK: 민트 (성격 랜덤 재설정) + 상점 구매

/// 라인 로딩이 필요 없는 테스트용 provider — 민트는 currentLine 과 무관(성격은 MonState 에만 있음).
private struct MintNoProvider: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

@MainActor
final class MintTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    /// 활성 포켓몬 + 민트 재고를 지정한 상태 파일 로드 (라인 미로딩이어도 민트는 사용 가능).
    /// nature=nil 이면 성격 미지정(구버전 개체) 재현.
    private func store(nature: String? = "adamant", mint: Int = 1, used: Int = 1_000_000_000,
                       spent: Int = 0, usedAtStage: Int = 50_000_000, shiny: Bool = false,
                       seed: UInt64 = 7) -> CompanionStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mint-\(UUID().uuidString).json")
        let natureField = nature.map { ",\"nature\":\"\($0)\"" } ?? ""
        let active = "{\"baseID\":1,\"pathIDs\":[1],\"stageIndex\":0,\"usedAtStage\":\(usedAtStage),"
            + "\"rarity\":\"common\",\"totalForms\":3,\"isShiny\":\(shiny)\(natureField)}"
        let inv = mint > 0 ? ",\"inventory\":{\"mint\":\(mint)}" : ""
        let json = "{\"installBaselineSet\":true,\"usedSinceInstall\":\(used),\"spentTokens\":\(spent),"
            + "\"lastDate\":\"d\",\"active\":\(active),\"dex\":[],\"collectedFinals\":[]\(inv)}"
        try? json.data(using: .utf8)!.write(to: url)
        return CompanionStore(provider: MintNoProvider(), clock: { self.now }, fileURL: url, rng: SeededRNG(seed: seed))
    }

    // MARK: 사용

    func testUseMintChangesNatureToDifferent() {
        let s = store(nature: "adamant", mint: 1)
        XCTAssertEqual(s.state.active?.nature, .adamant)
        let new = s.useMint()
        XCTAssertNotNil(new)
        XCTAssertNotEqual(new, .adamant, "현재와 다른 성격으로 바뀌어야 함")
        XCTAssertEqual(s.state.active?.nature, new)
        XCTAssertEqual(s.itemCount(.mint), 0, "재고 1 소모")
    }

    /// 여러 번 써도 매번 '직전 성격과 다른' 값으로만 바뀐다(현재 제외 롤).
    func testMintNeverRepeatsCurrentAcrossUses() {
        let s = store(nature: "adamant", mint: 6)
        for _ in 0..<6 {
            let before = s.state.active?.nature
            let new = s.useMint()
            XCTAssertNotNil(new)
            XCTAssertNotEqual(new, before, "매 사용은 직전 성격과 달라야 함")
        }
    }

    /// 성격 nil(구버전 개체) → 유효한 성격이 설정된다.
    func testUseMintFromNilNatureSetsValid() {
        let s = store(nature: nil, mint: 1)
        XCTAssertNil(s.state.active?.nature)
        let new = s.useMint()
        XCTAssertNotNil(new)
        XCTAssertEqual(s.state.active?.nature, new)
    }

    /// 성장·종·shiny·usedAtStage·통계 전부 불변(순수 코스메틱).
    func testUseMintDoesNotAffectGrowthOrIdentity() {
        let s = store(nature: "adamant", mint: 1, used: 1_000_000_000, usedAtStage: 50_000_000, shiny: true)
        let beforeStage = s.state.active?.stageIndex
        let beforeUsed = s.state.usedSinceInstall
        let beforeSpecies = s.currentSpeciesID
        _ = s.useMint()
        XCTAssertEqual(s.state.active?.usedAtStage, 50_000_000, "진화 진행 불변")
        XCTAssertEqual(s.state.active?.stageIndex, beforeStage)
        XCTAssertEqual(s.currentSpeciesID, beforeSpecies)
        XCTAssertTrue(s.currentIsShiny, "shiny 불변")
        XCTAssertEqual(s.state.usedSinceInstall, beforeUsed, "실사용 통계 불변")
    }

    // MARK: 게이트

    func testCannotUseMintOnEgg() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mint-egg-\(UUID().uuidString).json")
        let json = "{\"installBaselineSet\":true,\"usedSinceInstall\":1,\"lastDate\":\"d\","
            + "\"dex\":[],\"collectedFinals\":[],\"inventory\":{\"mint\":2}}"
        try? json.data(using: .utf8)!.write(to: url)
        let s = CompanionStore(provider: MintNoProvider(), clock: { self.now }, fileURL: url, rng: SeededRNG(seed: 1))
        XCTAssertTrue(s.isEgg)
        XCTAssertFalse(s.canUseMint)
        XCTAssertNil(s.useMint())
        XCTAssertEqual(s.itemCount(.mint), 2, "알 상태에선 소모 안 됨")
    }

    func testCannotUseMintWithoutStock() {
        let s = store(nature: "adamant", mint: 0)
        XCTAssertFalse(s.canUseMint)
        XCTAssertNil(s.useMint())
    }

    // MARK: 피드백

    func testMintFeedbackSetAndConsumed() {
        let s = store(nature: "adamant", mint: 1)
        let before = s.mintFeedbackSeq
        let new = s.useMint()
        XCTAssertEqual(s.mintFeedbackNature, new)
        XCTAssertEqual(s.mintFeedbackSeq, before + 1)
        s.consumeMintFeedback()
        XCTAssertNil(s.mintFeedbackNature)
    }

    // MARK: 영속

    func testUseMintPersistsAcrossRestart() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mint-persist-\(UUID().uuidString).json")
        let json = "{\"installBaselineSet\":true,\"usedSinceInstall\":1,\"lastDate\":\"d\","
            + "\"active\":{\"baseID\":1,\"pathIDs\":[1],\"stageIndex\":0,\"usedAtStage\":0,\"rarity\":\"common\",\"totalForms\":3,\"nature\":\"adamant\"},"
            + "\"inventory\":{\"mint\":2},\"dex\":[],\"collectedFinals\":[]}"
        try? json.data(using: .utf8)!.write(to: url)
        let s1 = CompanionStore(provider: MintNoProvider(), clock: { self.now }, fileURL: url, rng: SeededRNG(seed: 3))
        let new = s1.useMint()
        XCTAssertNotNil(new)

        let s2 = CompanionStore(provider: MintNoProvider(), clock: { self.now }, fileURL: url, rng: SeededRNG(seed: 3))
        XCTAssertEqual(s2.state.active?.nature, new, "바뀐 성격 영속")
        XCTAssertEqual(s2.itemCount(.mint), 1, "재고 감소 영속")
    }

    // MARK: 상점 구매

    func testMintShopPriceAndPurchasable() {
        XCTAssertEqual(ItemKind.mint.shopPrice, Mint.price)
        XCTAssertEqual(ItemKind.mint.shopPrice, 100_000_000)
        let s = store(mint: 0)
        XCTAssertTrue(s.purchasableItems.contains(.rareCandy))
        XCTAssertTrue(s.purchasableItems.contains(.mint))
    }

    func testBuyMintDebitsWalletAndCredits() {
        let s = store(mint: 0, used: 300_000_000)
        XCTAssertTrue(s.canBuy(.mint))
        XCTAssertTrue(s.buy(.mint))
        XCTAssertEqual(s.itemCount(.mint), 1)
        XCTAssertEqual(s.state.spentTokens, Mint.price)
        XCTAssertEqual(s.availableTokens, 300_000_000 - Mint.price)
    }

    func testCannotBuyMintBelowPrice() {
        let s = store(mint: 0, used: Mint.price - 1)
        XCTAssertFalse(s.canBuy(.mint))
        XCTAssertFalse(s.buy(.mint))
        XCTAssertEqual(s.itemCount(.mint), 0)
    }
}
