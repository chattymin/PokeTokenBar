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

    // MARK: - A failed update is shown

    /// The update quits the app before installing: the app reopened after a failure reads the error the script left,
    /// if it is recent. "success", an old error or a dismissed one show nothing.
    @MainActor
    func testAFailedUpdateIsShownAfterTheAppReopens() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ptb-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let status = dir.appendingPathComponent("update-status")
        let now = Date()
        func checker() -> UpdateChecker {
            UpdateChecker(currentCommit: "abc1234", clock: { now }, updateStatusURL: status, fetchLatest: { nil })
        }
        try "error: build failed".write(to: status, atomically: true, encoding: .utf8)
        let failed = checker()
        XCTAssertEqual(failed.updateError, "error: build failed")
        failed.dismissUpdateError()
        XCTAssertNil(failed.updateError)
        XCTAssertNil(checker().updateError, "dismissed")

        try "error: install failed".write(to: status, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-7_200)], ofItemAtPath: status.path)
        XCTAssertNil(checker().updateError, "two hours old")
        try "success".write(to: status, atomically: true, encoding: .utf8)
        XCTAssertNil(checker().updateError)
    }

    /// A failure after the build quit the app reopens it: the player is never left without one.
    func testAFailedUpdateReopensTheApp() {
        let script = UpdateChecker.detachedUpgradeScript
        XCTAssertTrue(script.contains("APP_PID=\"$1\""), "the app's pid, kept before fail() takes its own $1")
        let fail = script.components(separatedBy: "fail() {").last?.components(separatedBy: "\n    }").first ?? ""
        XCTAssertTrue(fail.contains("open \"/Applications/PokeTokenLBI.app\""))
        XCTAssertTrue(fail.contains("kill -0 \"$APP_PID\""))
    }

    // MARK: - Detached upgrade script wait loop (#175)

    func testDetachedUpgradeScriptWaitsOnPidNotProcessName() {
        let script = UpdateChecker.detachedUpgradeScript
        XCTAssertFalse(
            script.contains("pgrep -x"),
            "pgrep -x matches any instance by name and always times out when a duplicate runs"
        )
        XCTAssertTrue(
            script.contains("kill -0 \"$1\""),
            "the wait loop must wait on the specific terminating PID via $1"
        )
    }

    // MARK: - Cooldown stamps only after a successful, validated check

    private static let releaseURL = "https://github.com/chattymin/PokeTokenBar/releases/tag/v2.5.5"

    @MainActor
    private func isolatedDefaults() -> UserDefaults {
        let suite = "UpdateCheckerTests.check.\(UUID().uuidString)"
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        return UserDefaults(suiteName: suite)!
    }

    /// A failed GitHub lookup must not start the 30-minute cooldown, but neither is it retried at every popover
    /// opening: unauthenticated, GitHub allows 60 calls an hour. It is retried ten minutes later.
    @MainActor
    func testFailedCheckWaitsTenMinutesNotThirty() async {
        var now = Date(timeIntervalSince1970: 1_700_000_000)
        var fetches = 0
        let checker = UpdateChecker(currentVersion: "2.5.3", clock: { now }, defaults: isolatedDefaults()) {
            fetches += 1
            return nil
        }

        await checker.check(minInterval: 1_800)
        XCTAssertEqual(fetches, 1)
        XCTAssertNil(checker.available)

        now = now.addingTimeInterval(5)
        await checker.check(minInterval: 1_800)
        XCTAssertEqual(fetches, 1, "not again at the next opening")
        now = now.addingTimeInterval(UpdateChecker.failedCheckInterval)
        await checker.check(minInterval: 1_800)
        XCTAssertEqual(fetches, 2, "ten minutes on, well before the half-hour cooldown")
    }

    /// Only a commit whose checks all passed is offered: a red or running one was installed all the same. The walk
    /// stops at the installed commit, and a failed request offers nothing.
    func testOnlyAGreenCommitIsOffered() async {
        func commit(_ sha: String) -> UpdateChecker.LatestCommit {
            UpdateChecker.LatestCommit(sha: sha, url: "https://github.com/KillianHzr/PokeTokenLBI/commit/\(sha)")
        }
        let green: [[String: Any]] = [["status": "completed", "conclusion": "success"],
                                      ["status": "completed", "conclusion": "skipped"]]
        let runs: [String: [[String: Any]]] = [
            "c" + String(repeating: "0", count: 39): [["status": "completed", "conclusion": "failure"]],
            "b" + String(repeating: "0", count: 39): [["status": "in_progress"]],
            "a" + String(repeating: "0", count: 39): green,
        ]
        let commits = ["c", "b", "a"].map { commit($0 + String(repeating: "0", count: 39)) }
        let picked = await UpdateChecker.firstGreen(commits, current: "dev") { runs[$0] }
        XCTAssertEqual(picked?.sha.first, "a", "the newest green one")
        let installed = await UpdateChecker.firstGreen(commits, current: "b000000") { runs[$0] }
        XCTAssertEqual(installed?.sha.first, "b", "the installed one comes first: nothing older is offered")
        let offline = await UpdateChecker.firstGreen(commits, current: "dev") { _ in nil }
        XCTAssertNil(offline)
        XCTAssertFalse(UpdateChecker.isGreen([]), "no check at all is not a pass")
    }

    /// The CI runs on the pull request only (2026-11-06): a merge commit with no check reads its pull request's head,
    /// green or not; one with checks of its own keeps them, and a plain commit with none is still no pass.
    func testAMergeCommitIsGreenWhenItsPullRequestIs() async {
        let sha = { (c: String) in c + String(repeating: "0", count: 39) }
        let green: [[String: Any]] = [["status": "completed", "conclusion": "success"]]
        let red: [[String: Any]] = [["status": "completed", "conclusion": "failure"]]
        let runs: [String: [[String: Any]]] = [sha("m"): [], sha("h"): green, sha("n"): [], sha("r"): red, sha("p"): []]
        let merged = UpdateChecker.LatestCommit(sha: sha("m"), url: "u", mergedHead: sha("h"))
        let picked = await UpdateChecker.firstGreen([merged], current: "dev") { runs[$0] }
        XCTAssertEqual(picked?.sha, sha("m"), "the merge commit itself is offered")
        let redHead = UpdateChecker.LatestCommit(sha: sha("n"), url: "u", mergedHead: sha("r"))
        let fallback = UpdateChecker.LatestCommit(sha: sha("h"), url: "u")
        let skipped = await UpdateChecker.firstGreen([redHead, fallback], current: "dev") { runs[$0] }
        XCTAssertEqual(skipped?.sha, sha("h"), "a red pull request's merge is not offered")
        let plain = UpdateChecker.LatestCommit(sha: sha("p"), url: "u")
        let none = await UpdateChecker.firstGreen([plain], current: "dev") { runs[$0] }
        XCTAssertNil(none, "a commit with no check and no pull request is no pass")
        let ownRed = UpdateChecker.LatestCommit(sha: sha("r"), url: "u", mergedHead: sha("h"))
        let own = await UpdateChecker.firstGreen([ownRed], current: "dev") { runs[$0] }
        XCTAssertNil(own, "its own red checks win over its head's")
    }

    /// [Regression] A build of `release` was offered `main`'s head when it was newer by time but on another line (#94
    /// merged into `main` alone): `main`'s build knows nothing of the save `release` wrote. Only a commit the installed
    /// one leads to is offered; the same, older or diverged reads as the installed one; an unread comparison offers
    /// nothing.
    func testOnlyACommitTheInstalledOneLeadsToIsOffered() async {
        let installed = "d" + String(repeating: "0", count: 39)
        let green = UpdateChecker.LatestCommit(sha: "b" + String(repeating: "0", count: 39),
                                               url: "https://github.com/KillianHzr/PokeTokenLBI/commit/b")
        for (status, offered) in [("ahead", true), ("diverged", false), ("behind", false), ("identical", false)] {
            let result = await UpdateChecker.offered(green, current: installed) { _, _ in status }
            XCTAssertEqual(result?.sha, offered ? green.sha : installed, status)
        }
        let unread = await UpdateChecker.offered(green, current: installed) { _, _ in nil }
        XCTAssertNil(unread, "not known to follow: nothing")
        let dev = await UpdateChecker.offered(green, current: "dev") { _, _ in XCTFail("compared"); return nil }
        XCTAssertEqual(dev?.sha, green.sha, "a build without its commit compares nothing")
        let same = await UpdateChecker.offered(green, current: String(green.sha.prefix(7))) { _, _ in nil }
        XCTAssertEqual(same?.sha, green.sha, "the installed one itself")
    }

    /// [Regression] The owner, 2026-11-18: "Vérifier" clicked while the popover's own check was asking GitHub said up
    /// to date at once. A check under way is waited for: the click reads its answer.
    @MainActor
    func testACheckClickedDuringAnotherWaitsForItsAnswer() async {
        let installed = "d" + String(repeating: "0", count: 39)
        let newer = "e" + String(repeating: "0", count: 39)
        var release: CheckedContinuation<Void, Never>?
        var calls = 0
        let checker = UpdateChecker(currentCommit: installed, defaults: isolatedDefaults(),
                                    updateStatusURL: FileManager.default.temporaryDirectory
                                        .appendingPathComponent("ptb-update-\(UUID().uuidString)"),
                                    fetchLatest: {
                                        calls += 1
                                        await withCheckedContinuation { release = $0 }
                                        return UpdateChecker.LatestCommit(
                                            sha: newer, url: "https://github.com/KillianHzr/PokeTokenLBI/commit/\(newer)")
                                    })
        let popover = Task { await checker.check() }
        while release == nil { await Task.yield() }
        let click = Task { () -> UpdateChecker.Available? in
            await checker.check(minInterval: 0)
            return checker.available
        }
        for _ in 0..<5 { await Task.yield() }
        release?.resume()
        let seen = await click.value
        await popover.value
        XCTAssertEqual(seen?.sha, newer, "the click reads the answer of the check under way")
        XCTAssertEqual(calls, 1, "one request for both")
    }

    /// What the walk returns for an older commit reads as no update.
    @MainActor
    func testTheInstalledCommitReturnedIsNoUpdate() async {
        let installed = "d" + String(repeating: "0", count: 39)
        let returned = UpdateChecker.LatestCommit(sha: installed, url: "https://github.com/KillianHzr/PokeTokenLBI/commit/a")
        let checker = UpdateChecker(currentCommit: installed, defaults: isolatedDefaults(),
                                    updateStatusURL: FileManager.default.temporaryDirectory
                                        .appendingPathComponent("ptb-update-\(UUID().uuidString)"),
                                    fetchLatest: { returned })
        await checker.check(minInterval: 0)
        XCTAssertNil(checker.available)
        XCTAssertNil(checker.skipped)
    }

    /// The script builds the commit offered, applies the local patch once (build-app.sh does), and says success only
    /// once the app reopened.
    func testTheScriptBuildsTheOfferedCommitAndReportsTheReopen() {
        let script = UpdateChecker.detachedUpgradeScript
        XCTAssertTrue(script.contains("TARGET=\"$3\""))
        XCTAssertTrue(script.contains("git reset --hard \"$TARGET\""))
        XCTAssertFalse(script.contains("git apply"), "build-app.sh applies the local patch")
        let tail = script.components(separatedBy: "Re-opening app").last ?? ""
        XCTAssertTrue(tail.contains("OPENED"))
        XCTAssertLessThan(tail.range(of: "did not reopen")?.lowerBound ?? tail.endIndex,
                          tail.range(of: "echo \"success\"")?.lowerBound ?? tail.startIndex)
    }

    @MainActor
    func testSuccessfulCheckStartsTheCooldownAndAppliesTheRelease() async {
        var now = Date(timeIntervalSince1970: 1_700_000_000)
        var fetches = 0
        let checker = UpdateChecker(currentVersion: "2.5.3", clock: { now }, defaults: isolatedDefaults()) {
            fetches += 1
            return UpdateChecker.LatestRelease(tag: "v2.5.5", url: Self.releaseURL)
        }

        await checker.check(minInterval: 1_800)
        XCTAssertEqual(fetches, 1)
        XCTAssertEqual(checker.available?.version, "2.5.5")
        XCTAssertEqual(checker.available?.url, Self.releaseURL)

        now = now.addingTimeInterval(60)
        await checker.check(minInterval: 1_800)
        XCTAssertEqual(fetches, 1, "a successful check must honour minInterval")

        now = now.addingTimeInterval(1_800)
        await checker.check(minInterval: 1_800)
        XCTAssertEqual(fetches, 2, "after the cooldown the next check must fetch again")
    }

    @MainActor
    func testRejectedReleaseUrlDoesNotStartTheCooldown() async {
        var fetches = 0
        var now = Date(timeIntervalSince1970: 1_700_000_000)
        let checker = UpdateChecker(currentVersion: "2.5.3", clock: { now }, defaults: isolatedDefaults()) {
            fetches += 1
            return UpdateChecker.LatestRelease(tag: "v2.5.5", url: "http://evil.example/x")
        }

        await checker.check(minInterval: 1_800)
        XCTAssertNil(checker.available)
        now = now.addingTimeInterval(UpdateChecker.failedCheckInterval)
        await checker.check(minInterval: 1_800)
        XCTAssertEqual(fetches, 2, "an unsafe URL is a failed check: retried after ten minutes, not the cooldown")
    }

    /// Malformed tags and unsupported prerelease tags are failed checks: nothing is applied, and the
    /// attempt ten minutes later fetches again and applies a valid release instead of waiting 30 minutes.
    @MainActor
    func testMalformedOrPrereleaseTagIsAFailedCheckAndDoesNotBlockTheNextOne() async {
        let badTags = ["", "latest", "v", "v2.5", "2.5.5.1", "v2..5", "2.5.x", "release-2.5.5", "v 2.5.5",
                       "v2.6.0-beta.1", "2.6.0-rc1", "v2.6.0+build.5", "v2.6.0.beta", "v-2.6.0",
                       "v1234567890.0.0", "v٢.٥.٥"]
        for bad in badTags {
            var tag = bad
            var fetches = 0
            var now = Date(timeIntervalSince1970: 1_700_000_000)
            let checker = UpdateChecker(currentVersion: "2.5.3", clock: { now }, defaults: isolatedDefaults()) {
                fetches += 1
                return UpdateChecker.LatestRelease(tag: tag, url: Self.releaseURL)
            }

            await checker.check(minInterval: 1_800)
            XCTAssertNil(checker.available, "\(bad.debugDescription) must not be offered")
            XCTAssertEqual(checker.settingsNotice, .current, "\(bad.debugDescription)")

            tag = "v2.5.5"
            now = now.addingTimeInterval(UpdateChecker.failedCheckInterval)
            await checker.check(minInterval: 1_800)
            XCTAssertEqual(fetches, 2, "\(bad.debugDescription) must not start the cooldown")
            XCTAssertEqual(checker.available?.version, "2.5.5", "the next valid release applies at once")
        }
    }

    func testNormalizedReleaseVersion() {
        XCTAssertEqual(UpdateChecker.normalizedReleaseVersion("v2.5.5"), "2.5.5")
        XCTAssertEqual(UpdateChecker.normalizedReleaseVersion("2.5.10"), "2.5.10")
        XCTAssertEqual(UpdateChecker.normalizedReleaseVersion(" V2.05.10\n"), "2.5.10", "trimmed, prefix and leading zeros dropped")
        XCTAssertNil(UpdateChecker.normalizedReleaseVersion("v2.6.0-beta.1"))
        XCTAssertNil(UpdateChecker.normalizedReleaseVersion("v2.5"))
        XCTAssertNil(UpdateChecker.normalizedReleaseVersion("v1234567890.0.0"), "component would overflow comparisons")
    }

    /// With no early stamp, overlapping popover opens would each hit GitHub. One fetch at a time.
    @MainActor
    func testOverlappingChecksShareOneFetch() async {
        var fetches = 0
        var release: CheckedContinuation<Void, Never>?
        var now = Date(timeIntervalSince1970: 1_700_000_000)
        let checker = UpdateChecker(currentVersion: "2.5.3", clock: { now }, defaults: isolatedDefaults()) {
            fetches += 1
            if fetches == 1 { await withCheckedContinuation { release = $0 } }
            return nil
        }
        let first = Task { await checker.check(minInterval: 1_800) }
        while release == nil { await Task.yield() }
        // A check while one is in flight waits for its answer (2026-11-18), without a fetch of its own.
        let second = Task { await checker.check(minInterval: 1_800) }
        for _ in 0..<5 { await Task.yield() }
        XCTAssertEqual(fetches, 1, "a check while one is in flight does not fetch")

        release?.resume()
        await first.value
        await second.value
        XCTAssertEqual(fetches, 1, "it read the in-flight check's answer")
        now = now.addingTimeInterval(UpdateChecker.failedCheckInterval)
        await checker.check(minInterval: 1_800)
        XCTAssertEqual(fetches, 2, "once the in-flight check finished (failed), the next one fetches")
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
        XCTAssertTrue(script.contains("kill -0 \"$1\""), "must wait on terminating pid via $1 positional arg")
        XCTAssertTrue(script.contains("./scripts/build-app.sh"), "must execute build-app.sh")
        XCTAssertTrue(script.contains("open \"$TARGET_APP\"") || script.contains("open \"$2\""), "must reopen target app via $2 positional arg")
    }

    @MainActor
    func testCommitSHAUpdateDetection() async {
        let remoteSHA = "c328d5ceb9ef53221fde58a2b5e97b5c92689a72"
        let remoteURL = "https://github.com/KillianHzr/PokeTokenLBI/commit/\(remoteSHA)"
        let checker = UpdateChecker(currentCommit: "1111111", defaults: isolatedDefaults()) {
            UpdateChecker.LatestCommit(sha: remoteSHA, message: "feat: new commit", url: remoteURL)
        }

        await checker.check(minInterval: 0)
        XCTAssertEqual(checker.available?.version, "c328d5c")
        XCTAssertEqual(checker.settingsNotice, .offer("c328d5c"))

        // When current is already the remote SHA, no update offered
        let upToDateChecker = UpdateChecker(currentCommit: remoteSHA, defaults: isolatedDefaults()) {
            UpdateChecker.LatestCommit(sha: remoteSHA, message: "feat: new commit", url: remoteURL)
        }
        await upToDateChecker.check(minInterval: 0)
        XCTAssertNil(upToDateChecker.available)
        XCTAssertEqual(upToDateChecker.settingsNotice, .current)
    }

    func testDetachedUpgradeScriptWritesStatusFile() {
        let script = UpdateChecker.detachedUpgradeScript
        XCTAssertTrue(script.contains("STATUS_FILE=\"$APP_SUPPORT/update-status\""), "must define STATUS_FILE")
        XCTAssertTrue(script.contains("echo \"running\" > \"$STATUS_FILE\""), "must record running state")
        XCTAssertTrue(script.contains("echo \"success\" > \"$STATUS_FILE\""), "must record success state")
    }

    @MainActor
    func testIsUpdatingState() {
        let checker = UpdateChecker(currentCommit: "1111111", defaults: isolatedDefaults())
        XCTAssertFalse(checker.isUpdating)
        XCTAssertNil(checker.updateError)
    }
}
