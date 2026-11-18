import AppKit
import Observation

/// GitHub `main` 브랜치의 최신 커밋을 확인해 새 커밋이 있으면 팝오버에 알린다.
/// 실제 업데이트는 분리(detached) 스크립트가 소스를 git pull/reset 한 뒤 빌드하여 /Applications 에 설치하고 재실행한다.
@MainActor
@Observable
final class UpdateChecker {
    struct Available: Equatable {
        let version: String
        let url: String
        let message: String
        /// The full commit to build, the one offered: built from `main` as it is when the update runs, a commit pushed
        /// meanwhile (red or not) was installed instead. Nil for a release tag.
        let sha: String?

        init(version: String, url: String, message: String = "", sha: String? = nil) {
            self.version = version
            self.url = url
            self.message = message
            self.sha = sha
        }
    }

    /// What Settings should say after a check. A skipped release is not "up to date".
    enum SettingsNotice: Equatable {
        case offer(String)
        case skipped(String)
        case current
    }

    /// Commit SHA + message + URL from GitHub commits/main endpoint (or test double).
    struct LatestCommit: Equatable, Sendable {
        let sha: String
        let message: String
        let url: String
        /// A merge commit's second parent, the merged pull request's head: the CI ran on the pull request alone, so a
        /// merge commit has no check of its own and is green when that head is (`firstGreen`).
        var mergedHead: String?

        init(sha: String, message: String = "", url: String, mergedHead: String? = nil) {
            self.sha = sha
            self.message = message
            self.url = url
            self.mergedHead = mergedHead
        }

        // Backwards compatibility alias for tests
        init(tag: String, url: String) {
            self.sha = tag
            self.message = ""
            self.url = url
        }
    }

    typealias LatestRelease = LatestCommit

    private(set) var available: Available?
    /// Newer commit the user chose to skip. Hidden from the banner, still shown in Settings.
    private(set) var skipped: Available?
    private(set) var isUpdating = false
    /// The last update's failure ("error: build failed"), shown until dismissed. Read at launch too: the update quits
    /// the app before installing, and the app reopened after a failure knew nothing of it.
    private(set) var updateError: String?
    private let updateStatusURL: URL
    private var updateStatusTask: Task<Void, Never>?

    let currentCommit: String
    let currentVersion: String
    private let clock: () -> Date
    private let defaults: UserDefaults
    /// Injected so tests can fail or succeed without hitting the network.
    private let fetchLatest: () async -> LatestCommit?
    private var lastChecked: Date?
    /// The last check that found nothing (offline, rate limited): the next waits `failedCheckInterval`, not the next
    /// popover opening. Unauthenticated, GitHub allows 60 calls an hour.
    private var lastFailedCheck: Date?
    static let failedCheckInterval: TimeInterval = 600
    /// The check under way: a second one waits for its answer (the owner, 2026-11-18: "Vérifier" clicked while the
    /// popover's own check ran said up to date at once, the update found a moment later).
    private var checkInFlight: Task<Void, Never>?
    /// When the running update started: one whose script never wrote a result is given up after `updateTimeout`,
    /// or "updating" stayed for good.
    private var updateStartedAt: Date?
    static let updateTimeout: TimeInterval = 20 * 60

    static let skippedVersionKey = "skippedUpdateVersion"

    init(currentCommit: String? = nil, currentVersion: String? = nil, clock: @escaping () -> Date = Date.init, defaults: UserDefaults = .standard,
         updateStatusURL: URL = AppStatePaths.directory().appendingPathComponent("update-status"),
         fetchLatest: (() async -> LatestCommit?)? = nil) {
        let embeddedCommit = Bundle.main.object(forInfoDictionaryKey: "PTBCommitSHA") as? String
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String

        self.currentCommit = currentCommit ?? (embeddedCommit != nil && !embeddedCommit!.isEmpty && embeddedCommit != "unknown" ? embeddedCommit! : "dev")
        self.currentVersion = currentVersion ?? (embeddedCommit != nil && !embeddedCommit!.isEmpty && embeddedCommit != "unknown" ? String(embeddedCommit!.prefix(7)) : (shortVersion ?? "2.5.5"))
        self.clock = clock
        self.defaults = defaults
        let installed = self.currentCommit
        self.fetchLatest = fetchLatest ?? { await Self.liveLatestGreenCommit(repo: "KillianHzr/PokeTokenLBI", current: installed) }
        self.updateStatusURL = updateStatusURL
        updateError = Self.recentUpdateError(at: updateStatusURL, now: clock())
    }

    /// The error the update script left, if it wrote it within the last hour: an older one is no news.
    nonisolated static func recentUpdateError(at url: URL, now: Date) -> String? {
        guard let content = try? String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
              content.hasPrefix("error"),
              let written = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date,
              now.timeIntervalSince(written) < 3600 else { return nil }
        return content
    }

    /// Hides the failure, for this launch and the next ones.
    func dismissUpdateError() {
        updateError = nil
        try? "dismissed".write(to: updateStatusURL, atomically: true, encoding: .utf8)
    }

    var settingsNotice: SettingsNotice {
        if let available { return .offer(available.version) }
        if let skipped { return .skipped(skipped.version) }
        return .current
    }

    /// Release Settings can install. A skip hides the banner; it does not throw the URL away.
    var updateTarget: Available? { available ?? skipped }

    /// 최신 릴리스/커밋 조회. 스킵한 버전은 배너(`available`)에 안 올리고 Settings(`skipped`)에만 남긴다.
    func check(minInterval: TimeInterval = 1800) async {
        if let running = checkInFlight { await running.value; return }
        if let last = lastChecked, clock().timeIntervalSince(last) < minInterval { return }
        if let failed = lastFailedCheck, clock().timeIntervalSince(failed) < min(minInterval, Self.failedCheckInterval) {
            return
        }
        let running = Task { await fetchAndConsider() }
        checkInFlight = running
        await running.value
        checkInFlight = nil
    }

    private func fetchAndConsider() async {
        guard let commit = await fetchLatest(),
              Self.isTrustedReleaseURL(commit.url),
              let validated = Self.validatedVersionOrCommit(commit.sha) else {
            lastFailedCheck = clock()
            return
        }
        lastChecked = clock()
        lastFailedCheck = nil
        consider(latest: validated, message: commit.message, url: commit.url)
    }

    /// Validates semver (major.minor.patch) or full/short git commit SHA (hex).
    nonisolated static func validatedVersionOrCommit(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let semver = normalizedReleaseVersion(trimmed) {
            return semver
        }
        if (trimmed.count == 40 || trimmed.count == 7) && trimmed.allSatisfy({ $0.isHexDigit }) {
            return trimmed
        }
        return nil
    }

    /// NSWorkspace.open 으로 가는 릴리스 URL — https + github.com 만 허용.
    nonisolated static func isTrustedReleaseURL(_ string: String) -> Bool {
        guard let url = URL(string: string), url.scheme == "https", url.host == "github.com" else { return false }
        return true
    }

    /// Release tag → comparable version, or nil when the tag is not a plain `MAJOR.MINOR.PATCH`
    nonisolated static func normalizedReleaseVersion(_ tag: String) -> String? {
        var version = Substring(tag.trimmingCharacters(in: .whitespacesAndNewlines))
        if version.first == "v" || version.first == "V" { version = version.dropFirst() }
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts.allSatisfy({ part in
                  !part.isEmpty && part.count <= 9 && part.allSatisfy { $0.isASCII && $0.isNumber }
              }) else { return nil }
        return parts.map { String(Int($0)!) }.joined(separator: ".")
    }

    /// The newest commit of `main` whose CI passed: a commit whose checks failed, or still run, was offered and
    /// installed all the same (a red one on 15/10). The installed commit stops the walk: nothing older is offered.
    private nonisolated static func liveLatestGreenCommit(repo: String, current: String) async -> LatestCommit? {
        guard let json = await githubJSON("https://api.github.com/repos/\(repo)/commits?sha=main&per_page=10"),
              let list = json as? [[String: Any]] else { return nil }
        let commits = list.compactMap { item -> LatestCommit? in
            guard let sha = item["sha"] as? String, let html = item["html_url"] as? String else { return nil }
            let message = ((item["commit"] as? [String: Any])?["message"] as? String)?
                .components(separatedBy: .newlines).first ?? ""
            let parents = (item["parents"] as? [[String: Any]])?.compactMap { $0["sha"] as? String } ?? []
            return LatestCommit(sha: sha, message: message, url: html, mergedHead: parents.count == 2 ? parents[1] : nil)
        }
        let green = await firstGreen(commits, current: current) { sha in
            (await githubJSON("https://api.github.com/repos/\(repo)/commits/\(sha)/check-runs") as? [String: Any])?["check_runs"]
                as? [[String: Any]]
        }
        guard let green else { return nil }
        return await offered(green, current: current) { base, head in
            (await githubJSON("https://api.github.com/repos/\(repo)/compare/\(base)...\(head)") as? [String: Any])?["status"]
                as? String
        }
    }

    /// `green` when the installed commit leads to it (GitHub's "ahead"), else the installed one: the same, older, or on
    /// another line (a build of `release` and a merge made on `main` alone, newer but without `release`, whose build
    /// knows nothing of the save `release` wrote). nil when the comparison could not be read: nothing is offered rather
    /// than a commit not known to follow. A build without its commit (`dev`) compares nothing.
    nonisolated static func offered(_ green: LatestCommit, current: String,
                                    compareStatus: (String, String) async -> String?) async -> LatestCommit? {
        guard current.count >= 7, !green.sha.hasPrefix(current) else { return green }
        guard let status = await compareStatus(current, green.sha) else { return nil }
        return status == "ahead" ? green : LatestCommit(sha: current, message: green.message, url: green.url)
    }

    /// The first of `commits` (newest first) whose check runs all passed, or the installed one when it comes first.
    /// `checkRuns` nil: the request failed, so nothing is offered rather than a commit not known to pass. A merge
    /// commit with no check at all reads its pull request's head (the owner, 2026-11-06: the CI runs on the pull
    /// request only; `main` takes an up-to-date one, so what is merged is what was tested).
    nonisolated static func firstGreen(_ commits: [LatestCommit], current: String,
                                       checkRuns: (String) async -> [[String: Any]]?) async -> LatestCommit? {
        for commit in commits {
            if current.count >= 7, commit.sha.hasPrefix(current) { return commit }
            guard var runs = await checkRuns(commit.sha) else { return nil }
            if runs.isEmpty, let head = commit.mergedHead {
                guard let headRuns = await checkRuns(head) else { return nil }
                runs = headRuns
            }
            if isGreen(runs) { return commit }
        }
        return nil
    }

    /// Every check run completed and passed (or was skipped or neutral), and there is at least one.
    nonisolated static func isGreen(_ runs: [[String: Any]]) -> Bool {
        !runs.isEmpty && runs.allSatisfy { run in
            run["status"] as? String == "completed"
                && ["success", "skipped", "neutral"].contains(run["conclusion"] as? String ?? "")
        }
    }

    private nonisolated static func githubJSON(_ address: String) async -> Any? {
        guard let url = URL(string: address) else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    /// Apply one fetched release/commit.
    func consider(latest shaOrTag: String, message: String = "", url: String) {
        let trimmed = shaOrTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            available = nil
            skipped = nil
            return
        }

        let isSemVer = trimmed.contains(".")
        let short = isSemVer ? (trimmed.hasPrefix("v") ? String(trimmed.dropFirst()) : trimmed) : String(trimmed.prefix(7))

        let isAlreadyCurrent: Bool
        if isSemVer {
            isAlreadyCurrent = !Self.isNewer(short, than: currentVersion)
        } else {
            isAlreadyCurrent = (currentCommit == trimmed || (currentCommit.count >= 7 && trimmed.hasPrefix(currentCommit)))
        }

        guard !isAlreadyCurrent else {
            available = nil
            skipped = nil
            return
        }

        let skippedVersion = defaults.string(forKey: Self.skippedVersionKey)
        let release = Available(version: short, url: url, message: message, sha: isSemVer ? nil : trimmed)
        if short == skippedVersion || trimmed == skippedVersion {
            available = nil
            skipped = release
        } else {
            available = release
            skipped = nil
        }
    }

    /// Hide the banner for this version. Settings can still see it and install it.
    func skipCurrent() {
        guard let release = available else { return }
        defaults.set(release.version, forKey: Self.skippedVersionKey)
        skipped = release
        available = nil
    }

    /// Undo a skip so the banner can show the same release again.
    func showSkippedAgain() {
        defaults.removeObject(forKey: Self.skippedVersionKey)
        if let release = skipped {
            available = release
            skipped = nil
        }
    }

    func startMonitoringUpdateStatus() {
        updateStatusTask?.cancel()
        updateStatusTask = Task { @MainActor [weak self] in
            guard let statusURL = self?.updateStatusURL else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, self.isUpdating else { break }
                if let content = try? String(contentsOf: statusURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines) {
                    if content.hasPrefix("error") {
                        self.isUpdating = false
                        self.updateError = content
                        break
                    }
                }
                if let started = self.updateStartedAt, self.clock().timeIntervalSince(started) > Self.updateTimeout {
                    self.isUpdating = false
                    self.updateError = "error: the update did not finish"
                    break
                }
            }
        }
    }

    /// 업데이트 적용: 분리(detached) 스크립트로 git pull/reset + rebuild + reopen.
    func applyUpdate() {
        guard let target = updateTarget, !isUpdating else { return }
        isUpdating = true
        updateError = nil
        updateStartedAt = clock()
        Task { @MainActor in
            guard Self.launchDetachedUpgrade(target: target.sha ?? "") else {
                self.isUpdating = false
                self.updateError = "error: the update could not start"
                return
            }
            self.startMonitoringUpdateStatus()
        }
    }

    // MARK: 버전 비교 (기존 호환성)
    nonisolated static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// 백그라운드에서 repo fetch + build-app.sh + reopen을 수행하는 분리(detached) 스크립트.
    nonisolated static let detachedUpgradeScript = """
    export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
    APP_PID="$1"
    APP_BUNDLE="$2"
    TARGET="$3"

    APP_SUPPORT="$HOME/Library/Application Support/PokeTokenBar"
    SRC_DIR="$APP_SUPPORT/src"
    LOG_FILE="$HOME/Library/Logs/PokeTokenLBI-update.log"
    STATUS_FILE="$APP_SUPPORT/update-status"
    mkdir -p "$APP_SUPPORT"
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "running" > "$STATUS_FILE"
    echo "=== Update started at $(date) ===" >> "$LOG_FILE"

    # The build quits the app before installing: a failure after that must reopen it, or the player is left
    # without one. The reopened app reads the error from the status file.
    fail() {
      echo "error: $1" > "$STATUS_FILE"
      echo "Update failed: $1" >> "$LOG_FILE"
      if ! kill -0 "$APP_PID" 2>/dev/null; then
        open "/Applications/PokeTokenLBI.app" 2>/dev/null || open "$APP_BUNDLE" 2>/dev/null
      fi
      exit 1
    }

    if [ ! -d "$SRC_DIR/.git" ]; then
      echo "Cloning repository..." >> "$LOG_FILE"
      git clone "https://github.com/KillianHzr/PokeTokenLBI.git" "$SRC_DIR" >> "$LOG_FILE" 2>&1 || fail "clone failed"
    fi

    cd "$SRC_DIR" || fail "cd failed"
    echo "Fetching and resetting to origin/main..." >> "$LOG_FILE"
    git fetch origin main >> "$LOG_FILE" 2>&1 || fail "fetch failed"
    # The commit offered, not main as it is now: one pushed meanwhile was built in its place.
    if [ -n "$TARGET" ]; then
      git cat-file -e "$TARGET^{commit}" 2>/dev/null || fail "commit $TARGET not found"
      git reset --hard "$TARGET" >> "$LOG_FILE" 2>&1 || fail "reset failed"
    else
      git reset --hard origin/main >> "$LOG_FILE" 2>&1 || fail "reset failed"
    fi
    git clean -fd >> "$LOG_FILE" 2>&1 || fail "clean failed"
    # The local patch is applied by build-app.sh: applied here too, it ran twice.

    echo "Building app..." >> "$LOG_FILE"
    PTB_NATIVE_ARCH_ONLY=1 ./scripts/build-app.sh >> "$LOG_FILE" 2>&1 || fail "build failed"

    # Terminate the running instance ($1) right before reopening the new app
    kill "$1" 2>/dev/null || true
    for i in $(seq 1 40); do kill -0 "$1" 2>/dev/null || break; sleep 0.5; done

    echo "Re-opening app..." >> "$LOG_FILE"
    TARGET_APP="/Applications/PokeTokenLBI.app"
    OPENED=0
    for i in $(seq 1 15); do
      if open "$TARGET_APP" 2>/dev/null || open "$2" 2>/dev/null; then OPENED=1; break; fi
      sleep 1
    done
    # Success only once the new app opened: "success" was written whether it reopened or not.
    if [ "$OPENED" != "1" ]; then
      echo "error: installed, but the app did not reopen" > "$STATUS_FILE"
      echo "Update installed, reopening failed" >> "$LOG_FILE"
      exit 1
    fi
    echo "success" > "$STATUS_FILE"
    echo "=== Update finished at $(date) ===" >> "$LOG_FILE"
    """

    /// Whether the script started. `target`: the commit to build, empty for `main` as it is.
    @discardableResult
    nonisolated static func launchDetachedUpgrade(
        target: String,
        pid: pid_t = ProcessInfo.processInfo.processIdentifier,
        bundlePath: String = Bundle.main.bundlePath
    ) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", detachedUpgradeScript, "sh", String(pid), bundlePath, target]
        do {
            try task.run()
            return true
        } catch {
            AppLog.write("update: the script did not start: \(error)")
            return false
        }
    }
}
