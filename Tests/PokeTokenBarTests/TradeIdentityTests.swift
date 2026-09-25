import XCTest
@testable import PokeTokenBar

final class TradeIdentityTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "TradeIdentityTests-\(UUID().uuidString)")!
    }

    func testNicknameDefaultsToComputerNameWhenUnset() {
        let defaults = freshDefaults()
        XCTAssertFalse(TradeIdentity.nickname(defaults: defaults).isEmpty)
    }

    func testSetNicknameOverridesDefault() {
        let defaults = freshDefaults()
        TradeIdentity.setNickname("테스트기기", defaults: defaults)
        XCTAssertEqual(TradeIdentity.nickname(defaults: defaults), "테스트기기")
    }

    func testSetNicknameToBlankClearsOverride() {
        let defaults = freshDefaults()
        TradeIdentity.setNickname("테스트기기", defaults: defaults)
        TradeIdentity.setNickname("   ", defaults: defaults)
        XCTAssertNotEqual(TradeIdentity.nickname(defaults: defaults), "테스트기기")
    }

    func testCodeIsGeneratedOnceAndPersists() {
        let defaults = freshDefaults()
        let first = TradeIdentity.code(defaults: defaults)
        let second = TradeIdentity.code(defaults: defaults)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.count, 8)
    }

    func testCodeDiffersAcrossDefaultsInstances() {
        let a = TradeIdentity.code(defaults: freshDefaults())
        let b = TradeIdentity.code(defaults: freshDefaults())
        XCTAssertNotEqual(a, b)
    }
}
