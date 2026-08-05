import XCTest
@testable import PokeDexBar

final class UpdateCheckerTests: XCTestCase {
    func testNewerPatch() {
        XCTAssertTrue(UpdateChecker.isNewer("2.0.2", than: "2.0.1"))
    }
    func testSameIsNotNewer() {
        XCTAssertFalse(UpdateChecker.isNewer("2.0.1", than: "2.0.1"))
    }
    func testOlderIsNotNewer() {
        XCTAssertFalse(UpdateChecker.isNewer("2.0.0", than: "2.0.1"))
        XCTAssertFalse(UpdateChecker.isNewer("2.0.9", than: "2.1.0"))
    }
    func testNumericNotLexical() {
        // "2.0.10" 은 "2.0.9" 보다 높다 (문자열 비교면 반대로 틀림)
        XCTAssertTrue(UpdateChecker.isNewer("2.0.10", than: "2.0.9"))
    }
    func testMinorAndMajor() {
        XCTAssertTrue(UpdateChecker.isNewer("2.1.0", than: "2.0.9"))
        XCTAssertTrue(UpdateChecker.isNewer("3.0.0", than: "2.9.9"))
    }
    func testDifferentComponentCounts() {
        XCTAssertTrue(UpdateChecker.isNewer("2.0.1", than: "2.0"))   // 2.0.1 > 2.0.0
        XCTAssertFalse(UpdateChecker.isNewer("2.0", than: "2.0.0"))  // 동일
    }

    /// brew cask 이름은 이 앱 고유의 것이어야 한다 — 리브랜딩 때 kebab-case 리터럴이 rename 정규식에
    /// 안 걸려 upstream fork 의 cask 를 대신 확인/업그레이드하던 회귀(#task1 리뷰)의 가드.
    /// brewCaskPath()/launchDetachedUpgrade() 둘 다 이 상수 하나만 참조하므로, 이후 이름이 바뀌어도
    /// 두 사용처가 따로 놀 수 없다 — 이 테스트는 그 단일 소스가 여전히 우리 앱을 가리키는지만 고정한다.
    func testCaskNameIsOwnApp() {
        XCTAssertEqual(UpdateChecker.caskName, "poke-dex-bar")
    }
}
