import CryptoKit
import Foundation

/// Extra Claude Code config folders (`CLAUDE_CONFIG_DIR` logins) whose official limits are shown
/// next to the default account.
///
/// Folders are detected (`discovered`) and can be completed from Settings (`roots(from:)`), for
/// logins stored outside the detected places. People often set `CLAUDE_CONFIG_DIR` only inside a
/// shell alias, which the app never sees, hence the folder scan.
enum ClaudeAccountRoots {
    static let defaultsKey = "additionalClaudeConfigDirs"

    /// Comma/newline separated, tilde expanded, standardized. Keeps existing directories only,
    /// drops the default roots (they belong to the primary account) and folds duplicates.
    static func roots(
        from raw: String?,
        home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL]
    {
        guard let raw else { return [] }
        let excluded = defaultRootPaths(home: home)
        var seen = Set<String>()
        var out: [URL] = []
        for part in raw.split(whereSeparator: { $0 == "," || $0.isNewline }) {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let expanded = trimmed == "~" || trimmed.hasPrefix("~/")
                ? home.path + trimmed.dropFirst()
                : NSString(string: trimmed).expandingTildeInPath
            guard expanded.hasPrefix("/") else { continue }
            let url = URL(fileURLWithPath: expanded, isDirectory: true).standardizedFileURL
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  isDirectory.boolValue,
                  !excluded.contains(url.path),
                  seen.insert(url.path).inserted
            else { continue }
            out.append(url)
        }
        return out
    }

    /// Folders found without any setting: the `CLAUDE_CONFIG_DIR` entries the login shell exports,
    /// then the `~/.claude-*` and `~/.claude_*` folders Claude Code is logged in to. Default roots
    /// are never returned, they are the primary account.
    static func discovered(home: URL, configDirValue: String?) -> [URL] {
        let excluded = defaultRootPaths(home: home)
        var seen = Set<String>()
        var out = roots(from: configDirValue, home: home).filter { seen.insert($0.path).inserted }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: home.path)) ?? []
        for name in names.sorted() where name.hasPrefix(".claude-") || name.hasPrefix(".claude_") {
            let url = home.appendingPathComponent(name, isDirectory: true).standardizedFileURL
            guard !excluded.contains(url.path), hasLogin(url), seen.insert(url.path).inserted else { continue }
            out.append(url)
        }
        return out
    }

    /// The folder holds a `.claude.json` with an `oauthAccount` object, as every config folder
    /// Claude Code is logged in to does. A logged-out or foreign folder is skipped.
    static func hasLogin(_ root: URL) -> Bool {
        savedLogins.login(file: root.appendingPathComponent(".claude.json")) != nil
    }

    /// Email and organization Claude Code saved for this folder's login. Used when the profile
    /// endpoint gives nothing, typically because the token expired. Local read, no network.
    static func savedIdentity(in root: URL) -> AccountIdentity? {
        savedIdentity(file: root.appendingPathComponent(".claude.json"))
    }

    /// Login saved for the default folder (`~/.claude.json`), to name its tab before its limits load.
    /// App only, like `installedDiscovery`: tests must not read the developer's own login.
    static func installedDefaultIdentity(
        isBundledApp: Bool = AppEnv.isBundledApp,
        home: URL = FileManager.default.homeDirectoryForCurrentUser) -> AccountIdentity?
    {
        guard isBundledApp else { return nil }
        return savedIdentity(file: home.appendingPathComponent(".claude.json"))
    }

    static func savedIdentity(file: URL) -> AccountIdentity? {
        savedLogins.login(file: file)?.identity
    }

    /// Organization of this folder's login, to pick the same one among a session key's organizations.
    static func savedOrganizationID(in root: URL) -> String? {
        savedLogins.login(file: root.appendingPathComponent(".claude.json"))?.organizationID
    }

    private struct SavedLogin {
        let identity: AccountIdentity?
        var organizationID: String? = nil
    }

    private static let savedLogins = SavedLoginCache()

    /// `.claude.json` also keeps per-project state and grows with use, while only its `oauthAccount`
    /// matters here: the file is parsed again only when it changed.
    private final class SavedLoginCache: @unchecked Sendable {
        private struct Hit {
            let mtime: Date
            let size: Int
            let login: SavedLogin?
        }

        private let lock = NSLock()
        private var hits: [String: Hit] = [:]

        func login(file: URL) -> SavedLogin? {
            guard let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                  let mtime = values.contentModificationDate else { return nil }
            let size = values.fileSize ?? 0
            lock.lock()
            let hit = hits[file.path]
            lock.unlock()
            if let hit, hit.mtime == mtime, hit.size == size { return hit.login }
            let login = Self.read(file)
            lock.lock()
            hits[file.path] = Hit(mtime: mtime, size: size, login: login)
            lock.unlock()
            return login
        }

        private static func read(_ file: URL) -> SavedLogin? {
            guard let data = try? Data(contentsOf: file),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let account = json["oauthAccount"] as? [String: Any]
            else { return nil }
            guard let email = account["emailAddress"] as? String, !email.isEmpty else {
                return SavedLogin(identity: nil)
            }
            let org = (account["organizationName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let orgID = (account["organizationUuid"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            return SavedLogin(identity: AccountIdentity(email: email, organizationName: org), organizationID: orgID)
        }
    }

    /// Detection for the running app only. `swift test` and raw `swift build` binaries get nothing:
    /// another login's folder can lead to a Keychain prompt on a manual refresh, which must never
    /// happen inside the test suite (same rule as the other `AppEnv.isBundledApp` guards).
    static func installedDiscovery(
        isBundledApp: Bool = AppEnv.isBundledApp,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        configDirValue: () -> String? = { LocalUsageReader.shellAwareClaudeConfigDir() }) -> [URL]
    {
        guard isBundledApp else { return [] }
        return discovered(home: home, configDirValue: configDirValue())
    }

    /// Every additional folder the running app follows, for the usage scan (see `installedDiscovery`).
    static func installedAccountRoots(defaults: UserDefaults = .standard) -> [URL] {
        merged(detected: installedDiscovery(), setting: defaults.string(forKey: defaultsKey))
    }

    /// Detected folders first, then the Settings extras, without duplicates.
    static func merged(detected: [URL], setting: String?,
                       home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        var seen = Set<String>()
        return (detected + roots(from: setting, home: home)).filter { seen.insert($0.path).inserted }
    }

    private static func defaultRootPaths(home: URL) -> Set<String> {
        [
            home.appendingPathComponent(".claude").standardizedFileURL.path,
            home.appendingPathComponent(".config/claude").standardizedFileURL.path,
        ]
    }

    /// Keychain services Claude Code may use for a folder set through `CLAUDE_CONFIG_DIR`:
    /// the default service name plus the first 8 hex characters of the SHA-256 of the variable's
    /// raw value (`/Users/example/.claude-work` → `-dd1118a7`). Claude Code does not normalize that
    /// value (checked with 2.1.274: the same folder with a trailing slash is logged out), so the
    /// folder is also tried the way shell completion writes it, with a trailing slash.
    static func keychainServices(for root: URL) -> [String] {
        let path = root.standardizedFileURL.path
        return [path, path + "/"].map { "\(OAuthCredentialData.claudeKeychainService)-\(hashPrefix($0))" }
    }

    /// First 8 hex characters of the SHA-256 of the folder path. Also the folder's stable id for
    /// tab selection and alert/candy keys, so no path ends up in the save file.
    static func pathKey(for root: URL) -> String {
        hashPrefix(root.standardizedFileURL.path)
    }

    private static func hashPrefix(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return String(digest.map { String(format: "%02x", $0) }.joined().prefix(8))
    }

    static func credentialsFileURL(for root: URL) -> URL {
        root.appendingPathComponent(".credentials.json")
    }

    /// The default login's config folder (Claude Code without `CLAUDE_CONFIG_DIR`).
    static func defaultConfigDir(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent(".claude", isDirectory: true)
    }

    /// When this login last received a prompt: Claude Code appends one line per prompt to the
    /// folder's own `history.jsonl`, which is never shared between logins. Metadata only.
    static func lastPromptDate(configDir: URL) -> Date? {
        let file = configDir.appendingPathComponent("history.jsonl")
        return (try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date
    }

    /// App only, like `installedDiscovery`: tests must not read the developer's own history.
    static func installedLastPromptDate(configDir: URL, isBundledApp: Bool = AppEnv.isBundledApp) -> Date? {
        isBundledApp ? lastPromptDate(configDir: configDir) : nil
    }
}

/// Which Claude account drives the single-account surfaces when several are shown:
/// menu bar percentage, warning state (and the companion's tired mood), floating pet hover, 5h forecast.
enum ClaudeTrackedAccountMode: Equatable, Sendable, Hashable {
    /// The account that received the latest prompt.
    case automatic
    case defaultAccount
    /// The account with the highest official window.
    case highest
    case account(String)

    static let defaultsKey = "claudeTrackedAccount"

    init(storedValue: String?) {
        switch storedValue {
        case "default": self = .defaultAccount
        case "highest": self = .highest
        case let value? where value.hasPrefix("account:"): self = .account(String(value.dropFirst("account:".count)))
        default: self = .automatic
        }
    }

    var storedValue: String {
        switch self {
        case .automatic: return "automatic"
        case .defaultAccount: return "default"
        case .highest: return "highest"
        case .account(let id): return "account:\(id)"
        }
    }
}

extension LimitStatus {
    /// Names the account from its saved login when the profile endpoint gave nothing.
    mutating func fillIdentity(from saved: AccountIdentity?) {
        guard accountEmail == nil, let saved else { return }
        accountEmail = saved.email
        accountOrganizationName = saved.organizationName
    }

    /// Every official window this status carries: legacy fields, then the scoped entries.
    var allUtilizations: [Double] {
        [fiveHour?.utilization, sevenDay?.utilization, sevenDayOpus?.utilization, sevenDaySonnet?.utilization]
            .compactMap { $0 } + scopedLimitEntries.compactMap(\.percent)
    }
}

/// Official limits of one additional Claude config folder.
struct AdditionalClaudeLimits: Sendable {
    let rootPath: String
    let key: String
    var status: LimitStatus
    /// Last successful fetch; nil for an expired folder shown without values.
    var updatedAt: Date?
    /// The folder's token was rejected. Only Claude Code running on that folder renews it, so a
    /// refresh alone cannot help: the tab shows the last values dimmed, with what to do.
    var isExpired: Bool
    /// The rejected credential is the folder's own session key: the fix is a fresh key in Settings,
    /// not Claude Code, and a retry would only read the Keychain the key is there to avoid.
    var sessionKeyExpired: Bool

    init(rootPath: String, status: LimitStatus, isExpired: Bool = false, sessionKeyExpired: Bool = false,
         updatedAt: Date? = nil) {
        self.rootPath = rootPath
        self.key = ClaudeAccountRoots.pathKey(for: URL(fileURLWithPath: rootPath))
        self.status = status
        self.isExpired = isExpired
        self.sessionKeyExpired = sessionKeyExpired
        self.updatedAt = updatedAt
    }
}

/// One Claude account with official limits, as the popover tabs, alerts and candy see it:
/// the default login first, then the additional folders.
struct ClaudeAccountLimits: Sendable, Identifiable {
    static let defaultID = "default"

    let id: String
    /// Prefix of the alert and candy keys. The default login keeps its historical `claude.*`
    /// keys, so existing saves and notification tiers carry over unchanged.
    let windowKeyPrefix: String
    /// Shown when the profile gave no email (the folder, abbreviated).
    let fallbackTitle: String
    let status: LimitStatus
    let isDefault: Bool
    let isExpired: Bool
    var updatedAt: Date? = nil
    /// See `AdditionalClaudeLimits.sessionKeyExpired`. The default account keeps `UsageStore.limitsAuthExpiry`.
    var sessionKeyExpired = false

    static func defaultAccount(_ status: LimitStatus, isExpired: Bool = false,
                               updatedAt: Date? = nil) -> ClaudeAccountLimits {
        ClaudeAccountLimits(id: defaultID, windowKeyPrefix: "claude", fallbackTitle: "~/.claude",
                            status: status, isDefault: true, isExpired: isExpired, updatedAt: updatedAt)
    }

    static func additional(_ account: AdditionalClaudeLimits) -> ClaudeAccountLimits {
        ClaudeAccountLimits(id: account.key, windowKeyPrefix: "claude.\(account.key)",
                            fallbackTitle: (account.rootPath as NSString).abbreviatingWithTildeInPath,
                            status: account.status, isDefault: false, isExpired: account.isExpired,
                            updatedAt: account.updatedAt, sessionKeyExpired: account.sessionKeyExpired)
    }

    /// The account has at least one official window to show (a placeholder tab has none).
    var hasLimits: Bool { !status.allUtilizations.isEmpty }

    /// Same 15-minute rule as the default account's stale label.
    func isStale(now: Date = Date()) -> Bool {
        guard hasLimits, !isExpired, let updatedAt else { return false }
        return now.timeIntervalSince(updatedAt) > 15 * 60
    }

    /// Short tab title: the organization for a team plan, the email for a personal plan
    /// (its generated organization name repeats the email), the folder when both are unknown.
    var title: String {
        guard let email = status.accountEmail, !email.isEmpty else { return fallbackTitle }
        if let org = status.accountOrganizationName, !org.isEmpty, !org.contains(email) { return org }
        return email
    }
}
