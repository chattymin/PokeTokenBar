import XCTest
@testable import PokeTokenBar

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

    // MARK: - Detached upgrade script wait loop (#175)

    func testDetachedUpgradeScriptWaitsOnPidNotProcessName() {
        let script = UpdateChecker.detachedUpgradeScript
        XCTAssertFalse(
            script.contains("pgrep -x"),
            "pgrep -x matches any instance by name and always times out when a duplicate runs"
        )
        XCTAssertTrue(
            script.contains("kill -0 \"$3\""),
            "the wait loop must wait on the specific terminating PID via $3"
        )
    }

    /// "Skip this version" hides the banner, but a later check must still know
    /// the release exists. Settings must not treat that as "already latest".
    @MainActor
    func testSkippedReleaseStaysVisibleAndANewerOneReturnsToTheBanner() {
        let suite = "UpdateCheckerTests.skip.\(UUID().uuidString)"
        let box = UserDefaults(suiteName: suite)!
        defer { box.removePersistentDomain(forName: suite) }
        let checker = UpdateChecker(currentVersion: "2.5.3", defaults: box)

        checker.consider(latest: "2.5.4", url: "https://github.com/chattymin/PokeTokenBar/releases/tag/v2.5.4")
        XCTAssertEqual(checker.available?.version, "2.5.4")
        XCTAssertNil(checker.skipped)
        XCTAssertEqual(checker.settingsNotice, .offer("2.5.4"))

        checker.skipCurrent()
        XCTAssertNil(checker.available, "the popover banner stays hidden")
        XCTAssertEqual(checker.skipped?.version, "2.5.4")
        XCTAssertEqual(checker.settingsNotice, .skipped("2.5.4"))
        XCTAssertEqual(box.string(forKey: "skippedUpdateVersion"), "2.5.4")

        checker.consider(latest: "v2.5.4", url: "https://github.com/chattymin/PokeTokenBar/releases/tag/v2.5.4")
        XCTAssertNil(checker.available)
        XCTAssertEqual(checker.settingsNotice, .skipped("2.5.4"), "a skipped version is not the latest installed")

        checker.consider(latest: "2.5.5", url: "https://github.com/chattymin/PokeTokenBar/releases/tag/v2.5.5")
        XCTAssertEqual(checker.available?.version, "2.5.5")
        XCTAssertNil(checker.skipped)
        XCTAssertEqual(checker.settingsNotice, .offer("2.5.5"))

        checker.consider(latest: "2.5.3", url: "https://github.com/chattymin/PokeTokenBar/releases/tag/v2.5.3")
        XCTAssertEqual(checker.settingsNotice, .current, "the installed release is the latest")
    }

    @MainActor
    func testShowAgainRestoresTheBannerAndUpdateUsesTheSkippedRelease() {
        let suite = "UpdateCheckerTests.restore.\(UUID().uuidString)"
        let box = UserDefaults(suiteName: suite)!
        defer { box.removePersistentDomain(forName: suite) }
        let checker = UpdateChecker(currentVersion: "2.5.3", defaults: box)
        let url = "https://github.com/chattymin/PokeTokenBar/releases/tag/v2.5.4"
        checker.consider(latest: "2.5.4", url: url)
        checker.skipCurrent()

        XCTAssertEqual(checker.updateTarget?.url, url, "Settings can still install a skipped release")

        checker.showSkippedAgain()
        XCTAssertEqual(checker.available?.version, "2.5.4")
        XCTAssertNil(checker.skipped)
        XCTAssertNil(box.string(forKey: "skippedUpdateVersion"))
        XCTAssertEqual(checker.settingsNotice, .offer("2.5.4"))
    }

    func testDetachedUpgradeScriptUsesPositionalParameters() {
        let script = UpdateChecker.detachedUpgradeScript
        XCTAssertTrue(script.contains("\"$1\" update"), "must execute brew via $1 positional arg")
        XCTAssertTrue(script.contains("\"$1\" upgrade"), "must execute brew upgrade via $1 positional arg")
        XCTAssertTrue(script.contains("open \"$2\""), "must open bundlePath via $2 positional arg")
    }
}
