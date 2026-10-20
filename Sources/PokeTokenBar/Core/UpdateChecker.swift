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

        init(version: String, url: String, message: String = "") {
            self.version = version
            self.url = url
            self.message = message
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

        init(sha: String, message: String = "", url: String) {
            self.sha = sha
            self.message = message
            self.url = url
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
    private(set) var updateError: String?
    private var updateStatusTask: Task<Void, Never>?

    let currentCommit: String
    let currentVersion: String
    private let clock: () -> Date
    private let defaults: UserDefaults
    /// Injected so tests can fail or succeed without hitting the network.
    private let fetchLatest: () async -> LatestCommit?
    private var lastChecked: Date?
    private var checkInFlight = false

    static let skippedVersionKey = "skippedUpdateVersion"

    init(currentCommit: String? = nil, currentVersion: String? = nil, clock: @escaping () -> Date = Date.init, defaults: UserDefaults = .standard,
         fetchLatest: (() async -> LatestCommit?)? = nil) {
        let embeddedCommit = Bundle.main.object(forInfoDictionaryKey: "PTBCommitSHA") as? String
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String

        self.currentCommit = currentCommit ?? (embeddedCommit != nil && !embeddedCommit!.isEmpty && embeddedCommit != "unknown" ? embeddedCommit! : "dev")
        self.currentVersion = currentVersion ?? (embeddedCommit != nil && !embeddedCommit!.isEmpty && embeddedCommit != "unknown" ? String(embeddedCommit!.prefix(7)) : (shortVersion ?? "2.5.5"))
        self.clock = clock
        self.defaults = defaults
        self.fetchLatest = fetchLatest ?? { await Self.liveLatestCommit(repo: "KillianHzr/PokeTokenLBI") }
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
        if checkInFlight { return }
        if let last = lastChecked, clock().timeIntervalSince(last) < minInterval { return }
        checkInFlight = true
        defer { checkInFlight = false }

        guard let commit = await fetchLatest(),
              Self.isTrustedReleaseURL(commit.url),
              let validated = Self.validatedVersionOrCommit(commit.sha) else { return }
        lastChecked = clock()
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

    /// Live GitHub latest commit fetch.
    private nonisolated static func liveLatestCommit(repo: String) async -> LatestCommit? {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/commits/main") else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sha = json["sha"] as? String,
              let html = json["html_url"] as? String else { return nil }
        let commitObj = json["commit"] as? [String: Any]
        let message = (commitObj?["message"] as? String)?
            .components(separatedBy: .newlines).first ?? ""
        return LatestCommit(sha: sha, message: message, url: html)
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
        let release = Available(version: short, url: url, message: message)
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
            let statusURL = AppStatePaths.directory().appendingPathComponent("update-status")
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
            }
        }
    }

    /// 업데이트 적용: 분리(detached) 스크립트로 git pull/reset + rebuild + reopen.
    func applyUpdate() {
        guard updateTarget != nil, !isUpdating else { return }
        isUpdating = true
        updateError = nil
        Task { @MainActor in
            Self.launchDetachedUpgrade()
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

    APP_SUPPORT="$HOME/Library/Application Support/PokeTokenBar"
    SRC_DIR="$APP_SUPPORT/src"
    LOG_FILE="$HOME/Library/Logs/PokeTokenLBI-update.log"
    STATUS_FILE="$APP_SUPPORT/update-status"
    mkdir -p "$APP_SUPPORT"
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "running" > "$STATUS_FILE"
    echo "=== Update started at $(date) ===" >> "$LOG_FILE"

    fail() {
      echo "error: $1" > "$STATUS_FILE"
      echo "Update failed: $1" >> "$LOG_FILE"
      exit 1
    }

    if [ ! -d "$SRC_DIR/.git" ]; then
      echo "Cloning repository..." >> "$LOG_FILE"
      git clone "https://github.com/KillianHzr/PokeTokenLBI.git" "$SRC_DIR" >> "$LOG_FILE" 2>&1 || fail "clone failed"
    fi

    cd "$SRC_DIR" || fail "cd failed"
    echo "Fetching and resetting to origin/main..." >> "$LOG_FILE"
    git fetch origin main >> "$LOG_FILE" 2>&1 || fail "fetch failed"
    git reset --hard origin/main >> "$LOG_FILE" 2>&1 || fail "reset failed"
    git clean -fd >> "$LOG_FILE" 2>&1 || fail "clean failed"

    PATCH_FILE="$APP_SUPPORT/local.patch"
    if [ -f "$PATCH_FILE" ]; then
      echo "Applying local private patch..." >> "$LOG_FILE"
      git apply "$PATCH_FILE" >> "$LOG_FILE" 2>&1 || true
    fi

    echo "Building app..." >> "$LOG_FILE"
    PTB_NATIVE_ARCH_ONLY=1 ./scripts/build-app.sh >> "$LOG_FILE" 2>&1 || fail "build failed"

    # Terminate the running instance ($1) right before reopening the new app
    kill "$1" 2>/dev/null || true
    for i in $(seq 1 40); do kill -0 "$1" 2>/dev/null || break; sleep 0.5; done

    echo "Re-opening app..." >> "$LOG_FILE"
    TARGET_APP="/Applications/PokeTokenLBI.app"
    for i in $(seq 1 15); do
      open "$TARGET_APP" 2>/dev/null && break
      open "$2" 2>/dev/null && break
      sleep 1
    done
    echo "success" > "$STATUS_FILE"
    echo "=== Update finished at $(date) ===" >> "$LOG_FILE"
    """

    nonisolated static func launchDetachedUpgrade(
        pid: pid_t = ProcessInfo.processInfo.processIdentifier,
        bundlePath: String = Bundle.main.bundlePath
    ) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", detachedUpgradeScript, "sh", String(pid), bundlePath]
        try? task.run()
    }
}
