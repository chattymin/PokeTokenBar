import Security
import XCTest
@testable import PokeTokenBar

// Official limits for additional Claude config folders (`CLAUDE_CONFIG_DIR` logins):
// folder parsing, Keychain naming, per-folder token cache, profile cache, and the store pipeline.

// MARK: Stubs

private final class NilDailyProvider: UsageProvider, @unchecked Sendable {
    let id = "claude_code"
    let displayName = "Claude Code"
    let reportsCost = true
    func fetchDaily() async throws -> DailyUsage? { nil }
    func fetchEnrichment() async -> ProviderEnrichment { ProviderEnrichment() }
}

private struct NoStatuses: ProviderStatusProviding {
    func fetch() async -> [String: ProviderStatus] { [:] }
}

private struct NoCodex: CodexLimitsProviding {
    func fetch() async throws -> CodexRateLimitStatus? { nil }
}

private struct NoAntigravity: AntigravityLimitsProviding {
    func fetch(allowKeychainPrompt: Bool) async throws -> AntigravityRateLimitStatus {
        throw LimitsError.keychainInteractionNotAllowed
    }
}

/// Scripted results, recording the prompt flag of every call. Single-threaded tests only.
private final class ScriptedLimits: ClaudeLimitsProviding, @unchecked Sendable {
    nonisolated(unsafe) var results: [Result<LimitStatus, LimitsError>]
    nonisolated(unsafe) var promptFlags: [Bool] = []
    /// Error thrown only when a prompt is allowed (a declined Keychain dialog).
    nonisolated(unsafe) var promptError: LimitsError?

    init(_ results: [Result<LimitStatus, LimitsError>]) { self.results = results }

    func fetch(allowKeychainPrompt: Bool) async throws -> LimitStatus {
        promptFlags.append(allowKeychainPrompt)
        if allowKeychainPrompt, let promptError { throw promptError }
        let result = results.count > 1 ? results.removeFirst() : results[0]
        return try result.get()
    }
}

/// Provider whose first call waits until the test releases it.
private final class GatedLimits: ClaudeLimitsProviding, @unchecked Sendable {
    nonisolated(unsafe) var calls = 0
    nonisolated(unsafe) var release: CheckedContinuation<Void, Never>?

    func fetch(allowKeychainPrompt: Bool) async throws -> LimitStatus {
        calls += 1
        guard calls == 1 else { return limitStatus(fiveHour: 25, email: "work@example.com") }
        await withCheckedContinuation { release = $0 }
        return limitStatus(fiveHour: 20, email: "work@example.com")
    }
}

private final class SessionKeys: SessionKeyManaging, @unchecked Sendable {
    let stored: SessionKeyCredential?
    init(_ stored: SessionKeyCredential?) { self.stored = stored }
    func credential() -> SessionKeyCredential? { stored }
    func organizations(sessionKey: String) async throws -> [SessionKeyOrganization] { [] }
    func save(key: String, organizationID: String?) throws {}
    func clear() {}
}

private func limitStatus(fiveHour: Double, email: String?) -> LimitStatus {
    let json = "{\"five_hour\":{\"utilization\":\(fiveHour),\"resets_at\":null}}"
    var status = try! JSONDecoder().decode(LimitStatus.self, from: Data(json.utf8))
    status.accountEmail = email
    return status
}

private func fullStatus(fiveHour: Double, sevenDay: Double, fable: Double? = nil,
                        email: String?, org: String? = nil) -> LimitStatus {
    var parts = ["\"five_hour\":{\"utilization\":\(fiveHour)}", "\"seven_day\":{\"utilization\":\(sevenDay)}"]
    if let fable {
        parts.append("\"limits\":[{\"kind\":\"weekly_scoped\",\"percent\":\(fable),\"scope\":{\"model\":{\"display_name\":\"Fable\"}}}]")
    }
    var status = try! JSONDecoder().decode(LimitStatus.self, from: Data("{\(parts.joined(separator: ","))}".utf8))
    status.accountEmail = email
    status.accountOrganizationName = org
    return status
}

// MARK: Account tab titles

final class ClaudeAccountTitleTests: XCTestCase {
    private func account(email: String?, org: String?) -> ClaudeAccountLimits {
        .additional(AdditionalClaudeLimits(
            rootPath: "/Users/example/.claude-work",
            status: fullStatus(fiveHour: 1, sevenDay: 1, email: email, org: org)))
    }

    func testTeamPlanShowsTheOrganization() {
        XCTAssertEqual(account(email: "me@corp.example", org: "Corp").title, "Corp")
    }

    func testPersonalPlanShowsTheEmailNotItsGeneratedOrganization() {
        XCTAssertEqual(account(email: "me@example.com", org: "me@example.com's Organization").title, "me@example.com")
        XCTAssertEqual(account(email: "me@example.com", org: "").title, "me@example.com")
        XCTAssertEqual(account(email: "me@example.com", org: nil).title, "me@example.com")
    }

    func testUnknownAccountShowsTheFolder() {
        XCTAssertEqual(account(email: nil, org: "Corp").title,
                       ("/Users/example/.claude-work" as NSString).abbreviatingWithTildeInPath)
        XCTAssertEqual(ClaudeAccountLimits.defaultAccount(fullStatus(fiveHour: 1, sevenDay: 1, email: "")).title,
                       "~/.claude")
    }

    func testFolderKeyIsThePathHash() {
        let limits = AdditionalClaudeLimits(rootPath: "/Users/example/.claude-work",
                                            status: fullStatus(fiveHour: 1, sevenDay: 1, email: nil))
        XCTAssertEqual(limits.key, "dd1118a7")
    }
}

// MARK: Folder list and Keychain naming

final class ClaudeAccountRootsTests: XCTestCase {
    private var home: URL!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory
            .appendingPathComponent("ptb-accounts-\(UUID().uuidString)", isDirectory: true)
        for folder in [".claude", ".config/claude", ".claude-work", ".claude-personal"] {
            try FileManager.default.createDirectory(
                at: home.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    /// Claude Code hashes `CLAUDE_CONFIG_DIR` as given, so `…/.claude-work/` is another item.
    func testKeychainServicesHashTheFolderPathWithAndWithoutATrailingSlash() {
        // printf '%s' "/Users/example/.claude-work" | shasum -a 256 → dd1118a7…
        // printf '%s' "/Users/example/.claude-work/" | shasum -a 256 → 16c171f6…
        let expected = ["Claude Code-credentials-dd1118a7", "Claude Code-credentials-16c171f6"]
        let plain = URL(fileURLWithPath: "/Users/example/.claude-work")
        let slashed = URL(fileURLWithPath: "/Users/example/.claude-work/", isDirectory: true)
        XCTAssertEqual(ClaudeAccountRoots.keychainServices(for: plain), expected)
        XCTAssertEqual(ClaudeAccountRoots.keychainServices(for: slashed), expected)
        XCTAssertEqual(ClaudeAccountRoots.pathKey(for: slashed), "dd1118a7", "the folder id ignores the slash")
    }

    private func credential(_ token: String, expired: Bool = false) -> OAuthCredentialData.Credential {
        OAuthCredentialData.Credential(accessToken: token, expiresAt: Date().addingTimeInterval(expired ? -60 : 3600),
                                       data: Data(), subscriptionType: nil, rateLimitTier: nil)
    }

    private func firstUsable(_ results: [String: Result<OAuthCredentialData.Credential, LimitsError>],
                             order: [String] = ["a", "b"]) -> (Result<String, LimitsError>, [String]) {
        var read: [String] = []
        let result = Result<OAuthCredentialData.Credential, Error> {
            try OAuthAccessTokenCache.firstUsableCredential(services: order) {
                read.append($0)
                return try results[$0]!.get()
            }
        }
        return (result.map(\.accessToken).mapError { $0 as! LimitsError }, read)
    }

    func testTheFirstLiveCredentialWinsAndAMissingItemMovesOn() {
        let notFound = LimitsError.keychainUnavailable(errSecItemNotFound)
        XCTAssertEqual(firstUsable(["a": .success(credential("A")), "b": .success(credential("B"))]).1, ["a"],
                       "a live credential stops the lookup")
        XCTAssertEqual(firstUsable(["a": .failure(notFound), "b": .success(credential("B"))]).0, .success("B"))
        XCTAssertEqual(firstUsable(["a": .success(credential("A", expired: true)), "b": .success(credential("B"))]).0,
                       .success("B"), "an expired token gives way to a live one")
        XCTAssertEqual(firstUsable(["a": .success(credential("A", expired: true)), "b": .failure(notFound)]).0,
                       .success("A"), "an expired token beats nothing, so the tab can say it expired")
        XCTAssertEqual(firstUsable(["a": .success(credential("A", expired: true)),
                                    "b": .success(credential("B", expired: true))]).0,
                       .success("A"), "between expired tokens, the usual name wins")
        XCTAssertEqual(firstUsable(["a": .failure(notFound), "b": .failure(notFound)]).0, .failure(notFound))
    }

    func testAMissingItemNeverHidesAMoreTellingFailure() {
        let notFound = LimitsError.keychainUnavailable(errSecItemNotFound)
        XCTAssertEqual(firstUsable(["a": .failure(.keychainInteractionNotAllowed), "b": .failure(notFound)]).0,
                       .failure(.keychainInteractionNotAllowed))
        XCTAssertEqual(firstUsable(["a": .failure(notFound), "b": .failure(.credentialMissingAccountOAuth)]).0,
                       .failure(.credentialMissingAccountOAuth))
        XCTAssertEqual(firstUsable(["a": .failure(.credentialFormat), "b": .failure(.keychainInteractionNotAllowed)]).0,
                       .failure(.credentialFormat), "the first telling failure is kept")
        XCTAssertEqual(firstUsable([:], order: []).0, .failure(notFound))
    }

    /// #280: a cancelled or failed password prompt must not be followed by another one.
    func testACancelledPromptOrADisabledKeychainStopsTheLookup() {
        for error in [LimitsError.keychainUnavailable(errSecUserCanceled), .keychainUnavailable(errSecAuthFailed),
                      .keychainAccessDisabled] {
            let (result, read) = firstUsable(["a": .failure(error), "b": .success(credential("B"))])
            XCTAssertEqual(result, .failure(error))
            XCTAssertEqual(read, ["a"], "\(error)")
        }
    }

    func testRootsKeepExistingFoldersInOrderAndDropDefaultsDuplicatesAndInvalidEntries() {
        let raw = """
        ~/.claude-work, ~/.claude-work/
        ~/.claude
        ~/.config/claude,~/missing, relative/path, ,
        \(home.path)/.claude-personal
        """
        let roots = ClaudeAccountRoots.roots(from: raw, home: home)
        XCTAssertEqual(roots.map(\.lastPathComponent), [".claude-work", ".claude-personal"])
    }

    func testRootsAreEmptyWithoutASetting() {
        XCTAssertEqual(ClaudeAccountRoots.roots(from: nil, home: home), [])
        XCTAssertEqual(ClaudeAccountRoots.roots(from: "  \n , ", home: home), [])
    }

    func testAccountFoldersAddTheirOwnProjectsToTheUsageScan() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: home.appendingPathComponent(".claude/projects"), withIntermediateDirectories: true)
        try fm.createDirectory(at: home.appendingPathComponent(".claude-personal/projects"), withIntermediateDirectories: true)
        // A shared `projects/` (a link to the default one) is scanned once.
        try fm.createSymbolicLink(at: home.appendingPathComponent(".claude-work/projects"),
                                  withDestinationURL: home.appendingPathComponent(".claude/projects"))
        let accounts = ["~/.claude-personal", "~/.claude-work"].map {
            home.appendingPathComponent(String($0.dropFirst(2)), isDirectory: true)
        }

        let roots = LocalUsageReader.computeClaudeProjectRoots(configDirValue: nil, accountRoots: accounts, home: home)
        let resolved = { (path: String) in
            self.home.appendingPathComponent(path).resolvingSymlinksInPath().standardizedFileURL.path
        }
        XCTAssertTrue(roots.map(\.path).contains(resolved(".claude-personal/projects")))
        XCTAssertEqual(roots.filter { $0.path == resolved(".claude/projects") }.count, 1)
        XCTAssertEqual(Set(roots.map(\.path)).count, roots.count)
    }

    func testInstalledAccountRootsReadTheSettingOutsideTheApp() throws {
        let suite = "ptb-account-roots-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(ClaudeAccountRoots.installedAccountRoots(defaults: defaults), [])
        let personal = home.appendingPathComponent(".claude-personal").path
        defaults.set(personal, forKey: ClaudeAccountRoots.defaultsKey)
        XCTAssertEqual(ClaudeAccountRoots.installedAccountRoots(defaults: defaults).map(\.path), [personal],
                       "detection is off in tests, the listed folder stays")
    }

    func testKeychainQueriesTargetTheRequestedServiceAndKeepTheDefault() {
        let service = "Claude Code-credentials-dd1118a7"
        let accounts = OAuthCredentialData.claudeKeychainAccountsQuery(service: service, allowKeychainPrompt: false)
        let data = OAuthCredentialData.claudeKeychainDataQuery(account: "me", service: service, allowKeychainPrompt: true)
        XCTAssertEqual(accounts[kSecAttrService as String] as? String, service)
        XCTAssertEqual(data[kSecAttrService as String] as? String, service)

        let defaultQuery = OAuthCredentialData.claudeKeychainDataQuery(account: nil, allowKeychainPrompt: false)
        XCTAssertEqual(defaultQuery[kSecAttrService as String] as? String, "Claude Code-credentials")
    }
}

// MARK: Folder detection

final class ClaudeConfigDiscoveryTests: XCTestCase {
    private var home: URL!
    private let loggedIn = #"{"oauthAccount":{"emailAddress":"me@example.com"},"projects":{}}"#

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory
            .appendingPathComponent("ptb-discovery-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    private func folder(_ name: String, claudeJSON: String?) throws {
        let url = home.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        if let claudeJSON {
            try Data(claudeJSON.utf8).write(to: url.appendingPathComponent(".claude.json"))
        }
    }

    func testDetectsExportedFoldersThenLoggedInClaudeFolders() throws {
        try folder(".claude-work", claudeJSON: loggedIn)
        try folder(".claude_team", claudeJSON: loggedIn)
        try folder("configs/claude", claudeJSON: nil)          // exported: trusted as is
        try folder(".claude", claudeJSON: loggedIn)            // default root
        try folder(".claude-old", claudeJSON: #"{"oauthAccount":null}"#)
        try folder(".claude-broken", claudeJSON: "{not json")
        try folder(".claude-empty", claudeJSON: nil)
        try folder(".claudex", claudeJSON: loggedIn)           // not a CLAUDE_CONFIG_DIR naming

        let found = ClaudeAccountRoots.discovered(
            home: home, configDirValue: "\(home.path)/configs/claude, ~/.claude, ~/.claude-work")

        XCTAssertEqual(found.map { $0.path.replacingOccurrences(of: home.path + "/", with: "") },
                       ["configs/claude", ".claude-work", ".claude_team"])
    }

    func testNothingIsDetectedOutsideTheInstalledApp() throws {
        try folder(".claude-work", claudeJSON: loggedIn)
        var shellLookups = 0
        let outside = ClaudeAccountRoots.installedDiscovery(
            isBundledApp: false, home: home, configDirValue: { shellLookups += 1; return nil })
        XCTAssertEqual(outside, [])
        XCTAssertEqual(shellLookups, 0, "no login shell spawn when detection is off")

        let inside = ClaudeAccountRoots.installedDiscovery(isBundledApp: true, home: home, configDirValue: { nil })
        XCTAssertEqual(inside.map(\.lastPathComponent), [".claude-work"])
    }

    func testTheDefaultLoginIsReadFromHomeOnlyInsideTheApp() throws {
        try Data(#"{"oauthAccount":{"emailAddress":"me@corp.example","organizationName":"Corp"}}"#.utf8)
            .write(to: home.appendingPathComponent(".claude.json"))
        XCTAssertNil(ClaudeAccountRoots.installedDefaultIdentity(isBundledApp: false, home: home))
        XCTAssertEqual(ClaudeAccountRoots.installedDefaultIdentity(isBundledApp: true, home: home),
                       AccountIdentity(email: "me@corp.example", organizationName: "Corp"))

        try Data(#"{"oauthAccount":{"emailAddress":"me@example.com","organizationName":""}}"#.utf8)
            .write(to: home.appendingPathComponent(".claude.json"))
        XCTAssertEqual(ClaudeAccountRoots.installedDefaultIdentity(isBundledApp: true, home: home),
                       AccountIdentity(email: "me@example.com", organizationName: nil), "an empty organization is no organization")

        try Data(#"{"oauthAccount":{"emailAddress":""}}"#.utf8).write(to: home.appendingPathComponent(".claude.json"))
        XCTAssertNil(ClaudeAccountRoots.installedDefaultIdentity(isBundledApp: true, home: home))
    }

    func testTheSavedLoginIsReadAgainOnlyWhenTheFileChanges() throws {
        let file = home.appendingPathComponent(".claude.json")
        let stamp = Date(timeIntervalSince1970: 1_790_000_000)
        func save(_ email: String) throws {
            try Data("{\"oauthAccount\":{\"emailAddress\":\"\(email)\"}}".utf8).write(to: file)
            try FileManager.default.setAttributes([.modificationDate: stamp], ofItemAtPath: file.path)
        }
        try save("aa@example.com")
        XCTAssertEqual(ClaudeAccountRoots.savedIdentity(in: home)?.email, "aa@example.com")
        try save("bb@example.com")
        XCTAssertEqual(ClaudeAccountRoots.savedIdentity(in: home)?.email, "aa@example.com", "same size and date: cached")
        try save("ccc@example.com")
        XCTAssertEqual(ClaudeAccountRoots.savedIdentity(in: home)?.email, "ccc@example.com")
        XCTAssertTrue(ClaudeAccountRoots.hasLogin(home))
        try FileManager.default.removeItem(at: file)
        XCTAssertFalse(ClaudeAccountRoots.hasLogin(home))
    }

    func testMergedListPutsDetectedFoldersFirstWithoutDuplicates() throws {
        try folder(".claude-work", claudeJSON: loggedIn)
        try folder("elsewhere", claudeJSON: nil)
        let detected = [home.appendingPathComponent(".claude-work", isDirectory: true).standardizedFileURL]
        let merged = ClaudeAccountRoots.merged(
            detected: detected, setting: "~/elsewhere, ~/.claude-work", home: home)
        XCTAssertEqual(merged.map(\.lastPathComponent), [".claude-work", "elsewhere"])
    }
}

// MARK: Per-folder token cache

final class ConfigRootTokenCacheTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ptb-root-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        KeychainReader.resetQueryCountForTesting()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testFolderCacheReadsThatFoldersCredentialsFile() async throws {
        let expiresAt = Int(Date().addingTimeInterval(3600).timeIntervalSince1970)
        let json = "{\"claudeAiOauth\":{\"accessToken\":\"token-work\",\"expiresAt\":\(expiresAt),\"subscriptionType\":\"team\"}}"
        try Data(json.utf8).write(to: root.appendingPathComponent(".credentials.json"))

        let cache = OAuthAccessTokenCache.forConfigRoot(root)
        let token = try await cache.accessToken(allowKeychainPrompt: false)
        XCTAssertEqual(token, "token-work")
        let plan = await cache.planInfo()
        XCTAssertEqual(plan.subscriptionType, "team")
        XCTAssertEqual(KeychainReader.queryCount, 0)
    }

    /// The folder's own file decides the re-login hint, whatever `CLAUDE_CONFIG_DIR` says.
    func testFolderFileWithoutAccountOAuthAsksForReLogin() async throws {
        try Data("{\"mcpOAuth\":{}}".utf8).write(to: root.appendingPathComponent(".credentials.json"))
        do {
            _ = try await OAuthAccessTokenCache.forConfigRoot(root).accessToken(allowKeychainPrompt: false)
            XCTFail("expected credentialMissingAccountOAuth")
        } catch let error as LimitsError {
            XCTAssertEqual(error, .credentialMissingAccountOAuth)
        }
        XCTAssertEqual(KeychainReader.queryCount, 0)
    }

    func testFolderWithoutFileWaitsForAManualRefresh() async {
        do {
            _ = try await OAuthAccessTokenCache.forConfigRoot(root).accessToken(allowKeychainPrompt: false)
            XCTFail("expected keychainInteractionNotAllowed")
        } catch let error as LimitsError {
            XCTAssertEqual(error, .keychainInteractionNotAllowed)
        } catch {
            XCTFail("unexpected \(error)")
        }
        XCTAssertEqual(KeychainReader.queryCount, 0, "the automatic path never reads the Keychain")
    }
}

// MARK: Profile cache

final class OAuthProfileCacheTests: XCTestCase {
    private actor Counter {
        var calls: [String] = []
        func record(_ token: String) { calls.append(token) }
    }

    func testOneFetchPerTokenWhenAccountsAlternate() async {
        let counter = Counter()
        let cache = OAuthProfileCache { token in
            await counter.record(token)
            return AccountIdentity(email: "\(token)@example.com", organizationName: nil)
        }
        for token in ["a", "b", "a", "b"] {
            let identity = await cache.identity(accessToken: token)
            XCTAssertEqual(identity?.email, "\(token)@example.com")
        }
        let calls = await counter.calls
        XCTAssertEqual(calls, ["a", "b"])
    }

    func testFailuresAreNotCached() async {
        let counter = Counter()
        let cache = OAuthProfileCache { token in
            await counter.record(token)
            let attempts = await counter.calls.count
            return attempts == 1 ? nil : AccountIdentity(email: "late@example.com", organizationName: nil)
        }
        let first = await cache.identity(accessToken: "t")
        let second = await cache.identity(accessToken: "t")
        XCTAssertNil(first)
        XCTAssertEqual(second?.email, "late@example.com")
        let calls = await counter.calls
        XCTAssertEqual(calls.count, 2)
    }

    func testCacheIsBounded() async {
        let counter = Counter()
        let cache = OAuthProfileCache { token in
            await counter.record(token)
            return AccountIdentity(email: token, organizationName: nil)
        }
        for i in 0...OAuthProfileCache.maxEntries {
            _ = await cache.identity(accessToken: "t\(i)")
        }
        _ = await cache.identity(accessToken: "t0")
        let calls = await counter.calls
        XCTAssertEqual(calls.count, OAuthProfileCache.maxEntries + 2,
                       "a full cache is cleared, so the first token is fetched again")
    }
}

// MARK: Store pipeline

@MainActor
final class AdditionalClaudeAccountsStoreTests: XCTestCase {
    nonisolated(unsafe) private var testDefaults: UserDefaults!
    nonisolated(unsafe) private var suiteName: String!
    nonisolated(unsafe) private var base: URL!

    override func setUpWithError() throws {
        suiteName = "ptb-accounts-\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)
        KeychainAccessGate.isDisabled = false
        base = FileManager.default.temporaryDirectory
            .appendingPathComponent("ptb-accounts-store-\(UUID().uuidString)", isDirectory: true)
        for folder in ["work", "personal"] {
            try FileManager.default.createDirectory(
                at: base.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
    }

    override func tearDownWithError() throws {
        testDefaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: base)
    }

    private var work: String { base.appendingPathComponent("work").standardizedFileURL.path }
    private var personal: String { base.appendingPathComponent("personal").standardizedFileURL.path }

    private func makeStore(primary: ScriptedLimits,
                           folders: [String: ScriptedLimits],
                           defaultIdentity: AccountIdentity? = nil) -> UsageStore {
        testDefaults.set(folders.keys.sorted(by: >).joined(separator: ","),
                         forKey: ClaudeAccountRoots.defaultsKey)
        return UsageStore(
            providers: [NilDailyProvider()],
            claudeLimitsProvider: primary,
            additionalClaudeLimitsProvider: { root in folders[root.path]! },
            readDefaultIdentity: { defaultIdentity },
            codexLimitsProvider: NoCodex(),
            antigravityLimitsProvider: NoAntigravity(),
            statusProvider: NoStatuses(),
            sessionKeys: SessionKeys(nil),
            autoRefresh: false,
            defaults: testDefaults)
    }

    func testAdditionalAccountsFollowTheSettingsOrder() async {
        let primary = ScriptedLimits([.success(limitStatus(fiveHour: 10, email: "main@example.com"))])
        let store = makeStore(primary: primary, folders: [
            work: ScriptedLimits([.success(limitStatus(fiveHour: 20, email: "work@example.com"))]),
            personal: ScriptedLimits([.success(limitStatus(fiveHour: 30, email: "personal@example.com"))]),
        ])
        await store.refresh(scheduleEmptyRetry: false)

        // Setting is "work,personal" (sorted descending in makeStore).
        XCTAssertEqual(store.additionalLimits.map(\.rootPath), [work, personal])
        XCTAssertEqual(store.additionalLimits.map(\.status.fiveHour?.utilization), [20, 30])
        XCTAssertFalse(store.additionalLimitsPending)
        XCTAssertEqual(store.limits?.fiveHour?.utilization, 10, "the primary account is unchanged")
    }

    func testAnAccountAlreadyShownIsListedOnce() async {
        let primary = ScriptedLimits([.success(limitStatus(fiveHour: 10, email: "main@example.com"))])
        let store = makeStore(primary: primary, folders: [
            work: ScriptedLimits([.success(limitStatus(fiveHour: 10, email: "main@example.com"))]),
            personal: ScriptedLimits([.success(limitStatus(fiveHour: 30, email: nil))]),
        ])
        await store.refresh(scheduleEmptyRetry: false)

        XCTAssertEqual(store.additionalLimits.map(\.rootPath), [personal],
                       "same email as the primary is dropped; an unknown email is kept")
    }

    /// A team seat and a personal plan can share an email: they are two accounts.
    func testTheSameEmailInAnotherOrganizationIsAnotherAccount() async {
        let primary = ScriptedLimits([.success(fullStatus(fiveHour: 10, sevenDay: 1, email: "me@example.com", org: "Corp"))])
        let store = makeStore(primary: primary, folders: [
            work: ScriptedLimits([.success(fullStatus(fiveHour: 20, sevenDay: 1, email: "me@example.com",
                                                      org: "me@example.com's Organization"))]),
            personal: ScriptedLimits([.success(fullStatus(fiveHour: 30, sevenDay: 1, email: "me@example.com", org: "Corp"))]),
        ])
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(store.additionalLimits.map(\.rootPath), [work])
    }

    /// A manual refresh started during a poll waits for it: the poll's older values must not
    /// overwrite the manual ones.
    func testOverlappingRefreshesRunOneAfterTheOther() async throws {
        testDefaults.set(work, forKey: ClaudeAccountRoots.defaultsKey)
        let folder = GatedLimits()
        let store = UsageStore(
            providers: [NilDailyProvider()],
            claudeLimitsProvider: ScriptedLimits([.success(limitStatus(fiveHour: 10, email: "main@example.com"))]),
            additionalClaudeLimitsProvider: { _ in folder },
            codexLimitsProvider: NoCodex(),
            antigravityLimitsProvider: NoAntigravity(),
            statusProvider: NoStatuses(),
            sessionKeys: SessionKeys(nil),
            autoRefresh: false,
            defaults: testDefaults)

        let poll = Task { await store.refresh(scheduleEmptyRetry: false) }
        for _ in 0..<200 where folder.release == nil { try await Task.sleep(for: .milliseconds(5)) }
        let manual = Task { await store.refreshLimitTokenFromKeychain() }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(folder.calls, 1, "the manual refresh waits for the running one")

        folder.release?.resume()
        await poll.value
        await manual.value
        XCTAssertEqual(folder.calls, 2)
        XCTAssertEqual(store.additionalLimits.map(\.status.fiveHour?.utilization), [25])
    }

    func testTurningTheKeychainOffClearsAndSkipsTheOtherAccounts() async {
        let primary = ScriptedLimits([.success(limitStatus(fiveHour: 10, email: "main@example.com"))])
        let folder = ScriptedLimits([.success(limitStatus(fiveHour: 20, email: "work@example.com"))])
        let store = makeStore(primary: primary, folders: [work: folder])
        defer { KeychainAccessGate.isDisabled = false }
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(store.additionalLimits.count, 1)

        store.disableKeychainAccess = true
        XCTAssertTrue(store.additionalLimits.isEmpty, "cleared at once, like the default account")
        await store.refreshLimitTokenFromKeychain()
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(folder.promptFlags, [false], "no token read while the Keychain is off")
        XCTAssertTrue(store.additionalLimits.isEmpty)
        XCTAssertFalse(store.additionalLimitsPending)
    }

    /// A session key is there to avoid Keychain dialogs: detected folders never prompt then,
    /// and a detected folder that needs one does not pin the refresh row.
    func testWithASessionKeyOnlyListedFoldersPrompt() async {
        testDefaults.set(personal, forKey: ClaudeAccountRoots.defaultsKey)
        let detected = ScriptedLimits([.failure(.keychainInteractionNotAllowed)])
        let listed = ScriptedLimits([.success(limitStatus(fiveHour: 30, email: "personal@example.com"))])
        let workPath = work
        let store = UsageStore(
            providers: [NilDailyProvider()],
            claudeLimitsProvider: ScriptedLimits([.success(limitStatus(fiveHour: 10, email: "main@example.com"))]),
            additionalClaudeLimitsProvider: { $0.path == workPath ? detected : listed },
            discoverClaudeConfigDirs: { [URL(fileURLWithPath: workPath)] },
            codexLimitsProvider: NoCodex(),
            antigravityLimitsProvider: NoAntigravity(),
            statusProvider: NoStatuses(),
            sessionKeys: SessionKeys(SessionKeyCredential(key: "sk-ant-sid01-test", organizationID: "org")),
            autoRefresh: false,
            defaults: testDefaults)

        await store.refreshLimitTokenFromKeychain()
        XCTAssertEqual(detected.promptFlags, [false])
        XCTAssertEqual(listed.promptFlags, [true])
        XCTAssertFalse(store.additionalLimitsPending)
    }

    func testAnAutomaticSuccessClearsTheManualRefreshError() async {
        let primary = ScriptedLimits([
            .failure(.httpStatus(500)),
            .success(limitStatus(fiveHour: 10, email: "main@example.com")),
        ])
        let store = makeStore(primary: primary, folders: [:])
        await store.refreshLimitTokenFromKeychain()
        XCTAssertNotNil(store.limitTokenRefreshError)
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertNil(store.limitTokenRefreshError, "the refresh row must not show an old failure")
    }

    /// The row sits above the tabs: next to another account, a 429 must say whose check failed.
    func testTheManualRefreshErrorNamesTheDefaultAccountNextToOthers() async {
        let alone = makeStore(primary: ScriptedLimits([
            .success(limitStatus(fiveHour: 10, email: "main@example.com")),
            .failure(.rateLimited(retryAfter: nil)),
        ]), folders: [:])
        await alone.refresh(scheduleEmptyRetry: false)
        await alone.refreshLimitTokenFromKeychain()
        XCTAssertEqual(alone.claudeAccounts.count, 1, "the loaded default account keeps its values")
        let plain = alone.limitTokenRefreshError
        XCTAssertNotNil(plain)
        XCTAssertEqual(alone.limitTokenRefreshMessage, plain)

        let both = makeStore(
            primary: ScriptedLimits([.failure(.rateLimited(retryAfter: nil))]),
            folders: [work: ScriptedLimits([.success(limitStatus(fiveHour: 20, email: "work@example.com"))])],
            defaultIdentity: AccountIdentity(email: "main@example.com", organizationName: "Main Corp"))
        await both.refreshLimitTokenFromKeychain()
        XCTAssertEqual(both.claudeAccounts.map(\.title), ["Main Corp", "work@example.com"])
        XCTAssertEqual(both.limitTokenRefreshMessage, "Main Corp · \(plain ?? "")")
    }

    /// The default account's refresh row: pointless for someone using `CLAUDE_CONFIG_DIR` logins only.
    func testMissingDefaultLimitsNeedADefaultLoginNextToOtherAccounts() async {
        let folders = { [self] in [work: ScriptedLimits([.success(limitStatus(fiveHour: 20, email: "work@example.com"))])] }
        let failing = { ScriptedLimits([.failure(.keychainInteractionNotAllowed)]) }

        let alone = makeStore(primary: failing(), folders: [:])
        await alone.refresh(scheduleEmptyRetry: false)
        XCTAssertTrue(alone.claudeLimitsMissing)

        let configDirOnly = makeStore(primary: failing(), folders: folders())
        await configDirOnly.refresh(scheduleEmptyRetry: false)
        XCTAssertFalse(configDirOnly.claudeLimitsMissing)

        let both = makeStore(primary: failing(), folders: folders(),
                             defaultIdentity: AccountIdentity(email: "main@example.com", organizationName: nil))
        await both.refresh(scheduleEmptyRetry: false)
        XCTAssertTrue(both.claudeLimitsMissing)

        let loaded = makeStore(primary: ScriptedLimits([.success(limitStatus(fiveHour: 10, email: "main@example.com"))]),
                               folders: folders())
        await loaded.refresh(scheduleEmptyRetry: false)
        XCTAssertFalse(loaded.claudeLimitsMissing)
    }

    func testAutomaticRefreshNeverPromptsManualRefreshDoes() async {
        let primary = ScriptedLimits([.success(limitStatus(fiveHour: 10, email: "main@example.com"))])
        let folder = ScriptedLimits([.success(limitStatus(fiveHour: 20, email: "work@example.com"))])
        let store = makeStore(primary: primary, folders: [work: folder])

        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(folder.promptFlags, [false])

        await store.refreshLimitTokenFromKeychain()
        XCTAssertEqual(folder.promptFlags, [false, true])
    }

    func testADeclinedPromptStopsTheRemainingPrompts() async {
        let primary = ScriptedLimits([.success(limitStatus(fiveHour: 10, email: "main@example.com"))])
        let workLimits = ScriptedLimits([.failure(.keychainInteractionNotAllowed)])
        workLimits.promptError = .keychainUnavailable(errSecUserCanceled)
        let personalLimits = ScriptedLimits([.failure(.keychainInteractionNotAllowed)])
        let store = makeStore(primary: primary, folders: [work: workLimits, personal: personalLimits])

        await store.refreshLimitTokenFromKeychain()
        XCTAssertEqual(workLimits.promptFlags, [true])
        XCTAssertEqual(personalLimits.promptFlags, [false], "no second dialog after a cancel (#280)")
    }

    func testADeclinedPrimaryPromptStopsTheAdditionalPrompts() async {
        let primary = ScriptedLimits([.failure(.keychainUnavailable(errSecAuthFailed))])
        let folder = ScriptedLimits([.failure(.keychainInteractionNotAllowed)])
        let store = makeStore(primary: primary, folders: [work: folder])

        await store.refreshLimitTokenFromKeychain()
        XCTAssertEqual(folder.promptFlags, [false])
    }

    func testAFailingAccountKeepsItsLastValueAndAsksForARefresh() async {
        let primary = ScriptedLimits([.success(limitStatus(fiveHour: 10, email: "main@example.com"))])
        let folder = ScriptedLimits([
            .success(limitStatus(fiveHour: 20, email: "work@example.com")),
            .failure(.keychainInteractionNotAllowed),
            .success(limitStatus(fiveHour: 25, email: "work@example.com")),
        ])
        let store = makeStore(primary: primary, folders: [work: folder])

        await store.refresh(scheduleEmptyRetry: false)
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(store.additionalLimits.map(\.status.fiveHour?.utilization), [20])
        XCTAssertTrue(store.additionalLimitsPending)

        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(store.additionalLimits.map(\.status.fiveHour?.utilization), [25])
        XCTAssertFalse(store.additionalLimitsPending)
    }

    func testAFailingAccountWithoutHistoryIsNotShown() async {
        let primary = ScriptedLimits([.success(limitStatus(fiveHour: 10, email: "main@example.com"))])
        let folder = ScriptedLimits([.failure(.keychainInteractionNotAllowed)])
        let store = makeStore(primary: primary, folders: [work: folder])

        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertTrue(store.additionalLimits.isEmpty)
        XCTAssertTrue(store.additionalLimitsPending)
    }

    /// Rate limits apply per account: the default account's 429 must not pause the other folders.
    func testADefaultAccountRateLimitDoesNotPauseTheOtherAccounts() async {
        let primary = ScriptedLimits([.failure(.rateLimited(retryAfter: 600))])
        let folder = ScriptedLimits([.success(limitStatus(fiveHour: 20, email: "work@example.com"))])
        let store = makeStore(primary: primary, folders: [work: folder])

        await store.refresh(scheduleEmptyRetry: false)
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(primary.promptFlags, [false], "the default account is backing off")
        XCTAssertEqual(folder.promptFlags, [false, false], "the other account keeps polling")
    }

    func testAFolderRateLimitPausesOnlyThatFolderAndKeepsItsValues() async {
        let primary = ScriptedLimits([.success(limitStatus(fiveHour: 10, email: "main@example.com"))])
        let workLimits = ScriptedLimits([
            .success(limitStatus(fiveHour: 20, email: "work@example.com")),
            .failure(.rateLimited(retryAfter: 600)),
            .success(limitStatus(fiveHour: 21, email: "work@example.com")),
        ])
        let personalLimits = ScriptedLimits([.success(limitStatus(fiveHour: 30, email: "personal@example.com"))])
        let store = makeStore(primary: primary, folders: [work: workLimits, personal: personalLimits])

        await store.refresh(scheduleEmptyRetry: false)
        await store.refresh(scheduleEmptyRetry: false)   // work: 429
        await store.refresh(scheduleEmptyRetry: false)   // work: paused
        XCTAssertEqual(workLimits.promptFlags, [false, false])
        XCTAssertEqual(personalLimits.promptFlags, [false, false, false])
        XCTAssertEqual(primary.promptFlags, [false, false, false])
        XCTAssertEqual(store.additionalLimits.map(\.status.fiveHour?.utilization), [20, 30], "paused folder keeps its values")

        await store.refreshLimitTokenFromKeychain()
        XCTAssertEqual(workLimits.promptFlags, [false, false, true], "a manual refresh bypasses the pause")
        XCTAssertEqual(store.additionalLimits.map(\.status.fiveHour?.utilization), [21, 30])

        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(workLimits.promptFlags, [false, false, true, false], "a success lifts the pause")
    }

    func testRemovingTheFoldersClearsTheAccounts() async {
        let primary = ScriptedLimits([.success(limitStatus(fiveHour: 10, email: "main@example.com"))])
        let folder = ScriptedLimits([.failure(.keychainInteractionNotAllowed)])
        let store = makeStore(primary: primary, folders: [work: folder])
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertTrue(store.additionalLimitsPending)

        // The setter refreshes on its own. Wait for that refresh inside the test: left running,
        // it outlives the test and breaks the timing of later UI tests.
        store.additionalClaudeConfigDirs = ""
        for _ in 0..<100 where store.additionalLimitsPending || store.isRefreshing {
            try? await Task.sleep(for: .milliseconds(10))
        }
        // The setter also starts a refresh; let it finish inside this test.
        for _ in 0..<50 where store.isRefreshing { try? await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(store.additionalLimits.isEmpty)
        XCTAssertFalse(store.additionalLimitsPending)
        XCTAssertEqual(testDefaults.string(forKey: ClaudeAccountRoots.defaultsKey), "")
    }

    private var workKey: String { ClaudeAccountRoots.pathKey(for: URL(fileURLWithPath: work)) }

    func testAccountsListTheDefaultLoginFirstWithItsHistoricalKeys() async {
        let primary = ScriptedLimits([.success(fullStatus(fiveHour: 2, sevenDay: 45, email: "me@corp.example", org: "Corp"))])
        let store = makeStore(primary: primary, folders: [
            work: ScriptedLimits([.success(fullStatus(fiveHour: 32, sevenDay: 4, email: "me@example.com"))]),
        ])
        await store.refresh(scheduleEmptyRetry: false)

        XCTAssertEqual(store.claudeAccounts.map(\.id), [ClaudeAccountLimits.defaultID, workKey])
        XCTAssertEqual(store.claudeAccounts.map(\.title), ["Corp", "me@example.com"])
        XCTAssertEqual(store.claudeAccounts.map(\.windowKeyPrefix), ["claude", "claude.\(workKey)"])
        XCTAssertEqual(store.claudeAccounts.map(\.isDefault), [true, false])
    }

    func testCandyWindowsCoverEveryAccountAndKeepTheDefaultKeys() async {
        let primary = ScriptedLimits([.success(fullStatus(fiveHour: 100, sevenDay: 45, fable: 100, email: "me@corp.example", org: "Corp"))])
        let store = makeStore(primary: primary, folders: [
            work: ScriptedLimits([.success(fullStatus(fiveHour: 50, sevenDay: 50, email: "me@example.com")),
                                  .success(fullStatus(fiveHour: 100, sevenDay: 100, email: "me@example.com"))]),
        ])
        await store.refresh(scheduleEmptyRetry: false)
        await store.refresh(scheduleEmptyRetry: false)
        let l = L(store.localizationLanguage)
        let byKey = Dictionary(store.candyEligibleWindows.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })

        XCTAssertEqual(store.candyEligibleWindows.count, byKey.count, "candy tiers are keyed by window")
        XCTAssertEqual(Set(byKey.keys), ["claude.fiveHour", "claude.sevenDay",
                                         "claude.\(workKey).fiveHour", "claude.\(workKey).sevenDay"],
                       "scoped weekly windows stay out of candy, as before")
        XCTAssertEqual(byKey["claude.fiveHour"]?.name, "\(l.claudeFiveHour) (Corp)", "next to another account, each name says whose")
        XCTAssertEqual(byKey["claude.\(workKey).fiveHour"]?.name, "\(l.claudeFiveHour) (me@example.com)")
        XCTAssertEqual(byKey["claude.\(workKey).sevenDay"]?.kind, .weekly)
    }

    /// Candy is decided per window key: each account's full gauge pays once, and a folder removed
    /// then added back at 100% does not pay again, because its key is the folder's path hash.
    func testCandyIsGrantedPerAccountAndNotAgainAfterReAddingAFolder() async {
        let primary = ScriptedLimits([.success(fullStatus(fiveHour: 100, sevenDay: 10, email: "me@corp.example"))])
        let store = makeStore(primary: primary, folders: [
            work: ScriptedLimits([.success(fullStatus(fiveHour: 99, sevenDay: 99, email: "me@example.com")),
                                  .success(fullStatus(fiveHour: 100, sevenDay: 100, email: "me@example.com"))]),
        ])
        await store.refresh(scheduleEmptyRetry: false)
        await store.refresh(scheduleEmptyRetry: false)
        var tiers: [String: Int] = [:]

        let grants = CompanionStore.evaluateCandyGrants(windows: store.candyEligibleWindows, grantTier: &tiers)
        XCTAssertEqual(grants.map(\.count).reduce(0, +), 1 + 1 + RareCandy.weeklyGrant)

        let defaultOnly = store.candyEligibleWindows.filter { !$0.key.contains(workKey) }
        XCTAssertTrue(CompanionStore.evaluateCandyGrants(windows: defaultOnly, grantTier: &tiers).isEmpty)
        XCTAssertTrue(CompanionStore.evaluateCandyGrants(windows: store.candyEligibleWindows, grantTier: &tiers).isEmpty)
    }

    /// The first-run seed only covers the windows known at first launch: an account found later
    /// at its limit pays nothing until it has been seen below it, and that is remembered.
    func testAnAccountFoundAtItsLimitEarnsNoCandyUntilSeenBelowIt() async {
        let primary = ScriptedLimits([.success(fullStatus(fiveHour: 10, sevenDay: 10, email: "me@corp.example"))])
        let store = makeStore(primary: primary, folders: [
            work: ScriptedLimits([.success(fullStatus(fiveHour: 100, sevenDay: 40, email: "me@example.com")),
                                  .success(fullStatus(fiveHour: 20, sevenDay: 100, email: "me@example.com")),
                                  .success(fullStatus(fiveHour: 100, sevenDay: 100, email: "me@example.com"))]),
        ])
        let keys = { Set(store.candyEligibleWindows.map(\.key)) }
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(keys(), ["claude.fiveHour", "claude.sevenDay", "claude.\(workKey).sevenDay"])
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(keys(), ["claude.fiveHour", "claude.sevenDay",
                                "claude.\(workKey).fiveHour", "claude.\(workKey).sevenDay"])

        let restarted = makeStore(primary: primary, folders: [
            work: ScriptedLimits([.success(fullStatus(fiveHour: 100, sevenDay: 100, email: "me@example.com"))]),
        ])
        await restarted.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(Set(restarted.candyEligibleWindows.map(\.key)), keys(), "armed windows survive a restart")
    }

    func testAlertWindowsCoverEveryAccountAndKeepTheDefaultKeys() async {
        let primary = ScriptedLimits([.success(fullStatus(fiveHour: 2, sevenDay: 45, fable: 77, email: "me@corp.example", org: "Corp"))])
        let store = makeStore(primary: primary, folders: [
            work: ScriptedLimits([.success(fullStatus(fiveHour: 32, sevenDay: 4, fable: 12, email: "me@example.com"))]),
        ])
        await store.refresh(scheduleEmptyRetry: false)
        let l = L(store.localizationLanguage)
        let (windows, accounts) = store.buildLimitWindows()
        XCTAssertEqual(Set(windows.map(\.key)).count, windows.count,
                       "alert tiers are keyed by window: two accounts must never share a key")
        let byKey = Dictionary(windows.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })

        XCTAssertEqual(byKey["claude.fiveHour"]?.utilization, 2)
        XCTAssertEqual(byKey["claude.scoped.weekly_scoped.Fable.0"]?.utilization, 77)
        XCTAssertEqual(byKey["claude.\(workKey).fiveHour"]?.utilization, 32)
        XCTAssertEqual(byKey["claude.\(workKey).sevenDay"]?.name, l.claudeWeekly, "the account is not part of the name")
        XCTAssertEqual(byKey["claude.\(workKey).scoped.weekly_scoped.Fable.0"]?.utilization, 12)
        XCTAssertEqual(windows.count, 6)
        XCTAssertEqual(accounts, [
            "claude.fiveHour": "Corp", "claude.sevenDay": "Corp", "claude.scoped.weekly_scoped.Fable.0": "Corp",
            "claude.\(workKey).fiveHour": "me@example.com", "claude.\(workKey).sevenDay": "me@example.com",
            "claude.\(workKey).scoped.weekly_scoped.Fable.0": "me@example.com",
        ])

        let alone = makeStore(primary: ScriptedLimits([.success(fullStatus(fiveHour: 2, sevenDay: 45, email: "me@corp.example", org: "Corp"))]),
                              folders: [:])
        await alone.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(alone.buildLimitWindows().accounts, [:], "a single account needs no name")
        XCTAssertEqual(alone.candyEligibleWindows.first { $0.key == "claude.fiveHour" }?.name, l.claudeFiveHour)
    }

    /// Next to other accounts, an alert says whose limit it is, after the percentage.
    func testAlertsNameTheirAccountAfterThePercentage() {
        var tiers: [String: Int] = [:]
        let alerts = UsageStore.evaluateLimitAlerts(
            windows: [("claude.fiveHour", "Claude 5-hour session", 96), ("codex.x.primary", "Codex 5h", 85)],
            accounts: ["claude.fiveHour": "Corp"], warn: 80, crit: 95, tiers: &tiers)
        XCTAssertEqual(alerts.map(\.account), ["Corp", nil])
        XCTAssertEqual(alerts.map { $0.body(L(.en)) }, ["Claude 5-hour session at 96% · Corp", "Codex 5h at 85%"])
        XCTAssertEqual(alerts[0].body(L(.en), withAccount: false), "Claude 5-hour session at 96%")
    }

    /// The floating pet bubble cuts its text at two lines: a long account name must never cost the percentage.
    @MainActor
    func testTheBubbleDropsAnAccountThatDoesNotFit() {
        for lang in AppLanguage.allCases {
            let l = L(lang)
            for window in [l.claudeFiveHour, l.claudeWeekly, "Claude \(l.claudeLimitEntry(kind: "weekly_scoped", model: "Opus"))"] {
                for account in ["Corp", "firstname.lastname@corp.example"] {
                    let alert = UsageStore.LimitAlert(key: "k", window: window, isCritical: true, utilization: 96, account: account)
                    let body = FloatingPetController.bubbleBody(for: alert, title: l.notifCritical, l: l)
                    XCTAssertFalse(FloatingPetController.measureSpeechBubbleLayout(title: l.notifCritical, body: body).wouldTruncate,
                                   "\(lang.rawValue): \(body)")
                    XCTAssertTrue(body.contains(TokenFormatter.percent(96)))
                }
            }
        }
        let l = L(.en)
        let short = UsageStore.LimitAlert(key: "k", window: l.claudeWeekly, isCritical: false, utilization: 85, account: "Corp")
        XCTAssertEqual(FloatingPetController.bubbleBody(for: short, title: l.notifWarning, l: l), "Claude weekly at 85% · Corp")
        let long = UsageStore.LimitAlert(key: "k", window: l.claudeFiveHour, isCritical: true, utilization: 96,
                                         account: "firstname.lastname@corp.example")
        XCTAssertEqual(FloatingPetController.bubbleBody(for: long, title: l.notifCritical, l: l), "Claude 5-hour session at 96%")
    }

    func testLimitsAreReadyWithOnlyAnAdditionalAccount() async {
        let primary = ScriptedLimits([.failure(.keychainInteractionNotAllowed)])
        let store = makeStore(primary: primary, folders: [
            work: ScriptedLimits([.success(fullStatus(fiveHour: 32, sevenDay: 4, email: "me@example.com"))]),
        ])
        XCTAssertFalse(store.limitsReady)
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertNil(store.limits)
        XCTAssertTrue(store.limitsReady, "candy seeding must not wait for a default login that never loads")
        XCTAssertEqual(store.claudeAccounts.map(\.id), [workKey], "no default login saved: no placeholder tab")
    }

    func testDetectedFoldersAreShownWithoutAnySetting() async {
        let primary = ScriptedLimits([.success(limitStatus(fiveHour: 10, email: "main@example.com"))])
        let folder = ScriptedLimits([.success(limitStatus(fiveHour: 20, email: "work@example.com"))])
        let workPath = work
        let detectedWork = URL(fileURLWithPath: workPath)
        let store = UsageStore(
            providers: [NilDailyProvider()],
            claudeLimitsProvider: primary,
            additionalClaudeLimitsProvider: { root in root.path == workPath ? folder : ScriptedLimits([.failure(.httpStatus(500))]) },
            discoverClaudeConfigDirs: { [detectedWork] },
            codexLimitsProvider: NoCodex(),
            antigravityLimitsProvider: NoAntigravity(),
            statusProvider: NoStatuses(),
            autoRefresh: false,
            defaults: testDefaults)

        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(store.additionalLimits.map(\.rootPath), [work])
        XCTAssertEqual(store.detectedClaudeConfigDirs, [work])
        XCTAssertNil(testDefaults.string(forKey: ClaudeAccountRoots.defaultsKey), "detection writes no setting")
    }

    func testSettingFoldersComeAfterTheDetectedOnes() async {
        testDefaults.set("\(work),\(personal)", forKey: ClaudeAccountRoots.defaultsKey)
        let detectedPersonal = URL(fileURLWithPath: personal)
        let store = UsageStore(
            providers: [NilDailyProvider()],
            claudeLimitsProvider: ScriptedLimits([.success(limitStatus(fiveHour: 10, email: "main@example.com"))]),
            additionalClaudeLimitsProvider: { root in
                ScriptedLimits([.success(limitStatus(fiveHour: 20, email: root.lastPathComponent))])
            },
            discoverClaudeConfigDirs: { [detectedPersonal] },
            codexLimitsProvider: NoCodex(),
            antigravityLimitsProvider: NoAntigravity(),
            statusProvider: NoStatuses(),
            autoRefresh: false,
            defaults: testDefaults)

        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(store.additionalLimits.map(\.rootPath), [personal, work])
    }

    private func saveLogin(in folder: String, email: String, org: String? = nil) throws {
        let orgField = org.map { ",\"organizationName\":\"\($0)\"" } ?? ""
        let json = "{\"oauthAccount\":{\"emailAddress\":\"\(email)\"\(orgField)}}"
        try Data(json.utf8).write(to: URL(fileURLWithPath: folder).appendingPathComponent(".claude.json"))
    }

    /// A rejected token cannot be fixed by a refresh: the account stays visible, dimmed, and does
    /// not pin the refresh row. It stays expired through automatic failures, until a fetch succeeds.
    func testARejectedTokenMarksTheAccountExpiredUntilAFetchSucceeds() async {
        let primary = ScriptedLimits([.success(limitStatus(fiveHour: 10, email: "main@example.com"))])
        let folder = ScriptedLimits([
            .success(limitStatus(fiveHour: 20, email: "work@example.com")),
            .failure(.httpStatus(401)),
            .failure(.keychainInteractionNotAllowed),
            .success(limitStatus(fiveHour: 25, email: "work@example.com")),
        ])
        let store = makeStore(primary: primary, folders: [work: folder])

        await store.refresh(scheduleEmptyRetry: false)
        await store.refreshLimitTokenFromKeychain()
        XCTAssertEqual(store.additionalLimits.map(\.isExpired), [true])
        XCTAssertEqual(store.additionalLimits.map(\.status.fiveHour?.utilization), [20], "last values kept")
        XCTAssertFalse(store.additionalLimitsPending, "a refresh cannot renew this token")
        XCTAssertEqual(store.claudeAccounts.map(\.isExpired), [false, true])

        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(store.additionalLimits.map(\.isExpired), [true])
        XCTAssertFalse(store.additionalLimitsPending)

        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(store.additionalLimits.map(\.isExpired), [false])
        XCTAssertEqual(store.additionalLimits.map(\.status.fiveHour?.utilization), [25])
    }

    func testAnExpiredAccountWithoutHistoryKeepsATabNamedFromItsSavedLogin() async throws {
        try saveLogin(in: work, email: "work@example.com", org: "work@example.com's Organization")
        let primary = ScriptedLimits([.success(limitStatus(fiveHour: 10, email: "main@example.com"))])
        let store = makeStore(primary: primary, folders: [work: ScriptedLimits([.failure(.httpStatus(403))])])

        await store.refresh(scheduleEmptyRetry: false)
        let account = try XCTUnwrap(store.claudeAccounts.last)
        XCTAssertTrue(account.isExpired)
        XCTAssertEqual(account.title, "work@example.com")
        XCTAssertNil(account.status.fiveHour, "no values to show yet")
        XCTAssertFalse(store.additionalLimitsPending)
    }

    func testAnExpiredFolderOfTheDefaultLoginIsNotShown() async throws {
        try saveLogin(in: work, email: "main@example.com")
        let primary = ScriptedLimits([.success(limitStatus(fiveHour: 10, email: "main@example.com"))])
        let store = makeStore(primary: primary, folders: [work: ScriptedLimits([.failure(.httpStatus(401))])])

        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertTrue(store.additionalLimits.isEmpty)
    }

    func testTheSavedLoginNamesAnAccountWhenTheProfileIsUnknown() async throws {
        try saveLogin(in: work, email: "work@example.com", org: "Work Corp")
        let primary = ScriptedLimits([.success(limitStatus(fiveHour: 10, email: "main@example.com"))])
        let store = makeStore(primary: primary, folders: [work: ScriptedLimits([.success(limitStatus(fiveHour: 20, email: nil))])])

        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(store.additionalLimits.first?.status.accountEmail, "work@example.com")
        XCTAssertEqual(store.claudeAccounts.last?.title, "Work Corp")
    }

    func testTheProfileNameWinsOverTheSavedLogin() async throws {
        try saveLogin(in: work, email: "old@example.com", org: "Old Corp")
        let primary = ScriptedLimits([.success(limitStatus(fiveHour: 10, email: "main@example.com"))])
        let store = makeStore(primary: primary, folders: [
            work: ScriptedLimits([.success(fullStatus(fiveHour: 20, sevenDay: 1, email: "work@example.com", org: "Work Corp"))]),
        ])

        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(store.additionalLimits.first?.status.accountEmail, "work@example.com")
        XCTAssertEqual(store.claudeAccounts.last?.title, "Work Corp")
    }

    func testTheDefaultAccountTabFollowsTheDefaultExpiry() async {
        let primary = ScriptedLimits([
            .success(limitStatus(fiveHour: 10, email: "main@example.com")),
            .failure(.httpStatus(401)),
        ])
        let store = makeStore(primary: primary, folders: [work: ScriptedLimits([.success(limitStatus(fiveHour: 20, email: "work@example.com"))])])

        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(store.claudeAccounts.first?.isExpired, false)
        await store.refreshLimitTokenFromKeychain()
        XCTAssertEqual(store.claudeAccounts.first?.isExpired, true)
    }

    /// Next to another account, the default login keeps a tab (named from its saved login) while
    /// its limits are not loaded; alone, nothing changes (no tab, refresh row only).
    func testTheDefaultTabStaysWhileItsLimitsAreNotLoaded() async throws {
        let identity = AccountIdentity(email: "main@example.com", organizationName: "Corp")
        let store = makeStore(
            primary: ScriptedLimits([.failure(.rateLimited(retryAfter: 60))]),
            folders: [work: ScriptedLimits([.success(limitStatus(fiveHour: 20, email: "work@example.com"))])],
            defaultIdentity: identity)

        await store.refresh(scheduleEmptyRetry: false)
        let first = try XCTUnwrap(store.claudeAccounts.first)
        XCTAssertTrue(first.isDefault)
        XCTAssertEqual(first.title, "Corp")
        XCTAssertNil(first.status.fiveHour, "no values until the default limits load")
        XCTAssertTrue(store.candyEligibleWindows.allSatisfy { !$0.key.hasPrefix("claude.fiveHour") })
        XCTAssertEqual(store.defaultSavedIdentity, identity)

        let alone = makeStore(primary: ScriptedLimits([.failure(.rateLimited(retryAfter: 60))]), folders: [:],
                              defaultIdentity: identity)
        await alone.refresh(scheduleEmptyRetry: false)
        XCTAssertTrue(alone.claudeAccounts.isEmpty)
    }

    func testAFolderOfTheDefaultLoginIsHiddenEvenBeforeTheDefaultLimitsLoad() async {
        let store = makeStore(
            primary: ScriptedLimits([.failure(.keychainInteractionNotAllowed)]),
            folders: [work: ScriptedLimits([.success(limitStatus(fiveHour: 20, email: "main@example.com"))])],
            defaultIdentity: AccountIdentity(email: "main@example.com", organizationName: nil))

        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertTrue(store.additionalLimits.isEmpty)
    }

    func testOnlyUnauthorizedOrForbiddenCountsAsARejectedToken() {
        XCTAssertTrue(UsageStore.isAuthRejection(LimitsError.httpStatus(401)))
        XCTAssertTrue(UsageStore.isAuthRejection(LimitsError.httpStatus(403)))
        XCTAssertFalse(UsageStore.isAuthRejection(LimitsError.httpStatus(500)))
        XCTAssertFalse(UsageStore.isAuthRejection(LimitsError.keychainInteractionNotAllowed))
    }

    func testOnlyACancelledOrFailedAuthenticationCountsAsDeclined() {
        XCTAssertTrue(UsageStore.isKeychainPromptDeclined(LimitsError.keychainUnavailable(errSecUserCanceled)))
        XCTAssertTrue(UsageStore.isKeychainPromptDeclined(LimitsError.keychainUnavailable(errSecAuthFailed)))
        XCTAssertFalse(UsageStore.isKeychainPromptDeclined(LimitsError.keychainUnavailable(errSecItemNotFound)))
        XCTAssertFalse(UsageStore.isKeychainPromptDeclined(LimitsError.httpStatus(401)))
    }
}

// MARK: Tracked account

private final class TodayUsage: UsageProvider, @unchecked Sendable {
    let id = "claude_code"
    let displayName = "Claude Code"
    let reportsCost = true
    let block: BlockUsage?
    let tokens: Int
    init(block: BlockUsage? = nil, tokens: Int = 1_000) { self.block = block; self.tokens = tokens }
    func fetchDaily() async throws -> DailyUsage? {
        DailyUsage(date: LocalUsageReader.todayKey(), inputTokens: 0, outputTokens: 0,
                   cacheCreationTokens: 0, cacheReadTokens: 0, totalTokens: tokens, totalCost: 0)
    }
    func fetchEnrichment() async -> ProviderEnrichment {
        var enrichment = ProviderEnrichment()
        enrichment.activeBlock = block
        enrichment.blocksOK = true
        return enrichment
    }
}

final class ClaudeTrackedAccountModeTests: XCTestCase {
    private func account(_ id: String, fiveHour: Double?, weekly: Double? = nil, isDefault: Bool = false) -> ClaudeAccountLimits {
        var parts: [String] = []
        if let fiveHour { parts.append("\"five_hour\":{\"utilization\":\(fiveHour)}") }
        if let weekly { parts.append("\"seven_day\":{\"utilization\":\(weekly)}") }
        let status = try! JSONDecoder().decode(LimitStatus.self, from: Data("{\(parts.joined(separator: ","))}".utf8))
        return ClaudeAccountLimits(id: id, windowKeyPrefix: "claude.\(id)", fallbackTitle: id,
                                   status: status, isDefault: isDefault, isExpired: false)
    }

    private func tracked(_ accounts: [ClaudeAccountLimits], _ mode: ClaudeTrackedAccountMode,
                         _ activity: [String: Date] = [:]) -> String? {
        UsageStore.trackedAccount(among: accounts, mode: mode, activity: activity)?.id
    }

    func testStoredValueRoundTripsAndUnknownValuesMeanAutomatic() {
        for mode in [ClaudeTrackedAccountMode.automatic, .defaultAccount, .highest, .account("dd1118a7")] {
            XCTAssertEqual(ClaudeTrackedAccountMode(storedValue: mode.storedValue), mode)
        }
        XCTAssertEqual(ClaudeTrackedAccountMode(storedValue: nil), .automatic)
        XCTAssertEqual(ClaudeTrackedAccountMode(storedValue: "something-else"), .automatic)
    }

    func testAutomaticFollowsTheLatestPrompt() {
        let accounts = [account("default", fiveHour: 90, isDefault: true), account("personal", fiveHour: 10)]
        let now = Date()
        XCTAssertEqual(tracked(accounts, .automatic, ["default": now.addingTimeInterval(-60), "personal": now]), "personal")
        XCTAssertEqual(tracked(accounts, .automatic, ["default": now, "personal": now.addingTimeInterval(-60)]), "default")
        XCTAssertEqual(tracked(accounts, .automatic, ["personal": now]), "personal", "a dated account beats an undated one")
        XCTAssertEqual(tracked(accounts, .automatic), "default", "no activity: list order")
    }

    func testOnlyAccountsWithValuesCanBeTracked() {
        let accounts = [account("default", fiveHour: nil, isDefault: true), account("personal", fiveHour: 10)]
        XCTAssertEqual(tracked(accounts, .automatic, ["default": Date()]), "personal")
        XCTAssertEqual(tracked(accounts, .defaultAccount, ["personal": Date()]), "personal",
                       "the default placeholder has nothing to show: the last used account instead")
        XCTAssertNil(tracked([], .automatic))
    }

    func testDefaultHighestAndPinnedModes() {
        let accounts = [account("default", fiveHour: 20, isDefault: true),
                        account("work", fiveHour: 10, weekly: 95),
                        account("personal", fiveHour: 60)]
        let recent = ["personal": Date()]
        XCTAssertEqual(tracked(accounts, .defaultAccount, recent), "default")
        XCTAssertEqual(tracked(accounts, .highest, recent), "work", "any official window counts")
        XCTAssertEqual(tracked(accounts, .account("work"), recent), "work")
        XCTAssertEqual(tracked(accounts, .account("gone"), recent), "personal", "a missing pin falls back to automatic")
    }

    func testHighestModeCountsPerModelWeeklyWindows() {
        let scoped = fullStatus(fiveHour: 10, sevenDay: 20, fable: 97, email: "work@example.com")
        let work = ClaudeAccountLimits(id: "work", windowKeyPrefix: "claude.work", fallbackTitle: "work",
                                       status: scoped, isDefault: false, isExpired: false)
        XCTAssertEqual(scoped.allUtilizations, [10, 20, 97])
        XCTAssertEqual(tracked([account("default", fiveHour: 90, isDefault: true), work], .highest), "work")
    }

    func testLastPromptDateIsTheHistoryFileDate() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ptb-history-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        XCTAssertNil(ClaudeAccountRoots.lastPromptDate(configDir: folder))

        let file = folder.appendingPathComponent("history.jsonl")
        try Data("{}\n".utf8).write(to: file)
        let stamp = Date(timeIntervalSince1970: 1_790_000_000)
        try FileManager.default.setAttributes([.modificationDate: stamp], ofItemAtPath: file.path)
        XCTAssertEqual(ClaudeAccountRoots.lastPromptDate(configDir: folder), stamp)
    }

    func testStaleMeansLoadedFreshOrNotOlderThanFifteenMinutes() {
        let now = Date()
        var loaded = account("personal", fiveHour: 10)
        loaded.updatedAt = now.addingTimeInterval(-16 * 60)
        XCTAssertTrue(loaded.isStale(now: now))
        loaded.updatedAt = now.addingTimeInterval(-14 * 60)
        XCTAssertFalse(loaded.isStale(now: now))
        var empty = account("empty", fiveHour: nil)
        empty.updatedAt = now.addingTimeInterval(-3600)
        XCTAssertFalse(empty.isStale(now: now), "nothing shown, nothing stale")
        let expired = ClaudeAccountLimits(id: "x", windowKeyPrefix: "claude.x", fallbackTitle: "x",
                                          status: loaded.status, isDefault: false, isExpired: true,
                                          updatedAt: now.addingTimeInterval(-3600))
        XCTAssertFalse(expired.isStale(now: now), "the expired banner already says it")
    }
}

@MainActor
final class ClaudeTrackedAccountStoreTests: XCTestCase {
    nonisolated(unsafe) private var testDefaults: UserDefaults!
    nonisolated(unsafe) private var suiteName: String!
    nonisolated(unsafe) private var base: URL!

    override func setUpWithError() throws {
        suiteName = "ptb-tracked-\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)
        KeychainAccessGate.isDisabled = false
        base = FileManager.default.temporaryDirectory
            .appendingPathComponent("ptb-tracked-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base.appendingPathComponent("personal"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        testDefaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: base)
    }

    private var personal: String { base.appendingPathComponent("personal").standardizedFileURL.path }
    private var personalKey: String { ClaudeAccountRoots.pathKey(for: URL(fileURLWithPath: personal)) }

    private func makeStore(primary: LimitStatus, personal personalStatus: LimitStatus?,
                           lastPrompt: [String: Date],
                           usage: [LocalUsageReader.Entry] = [],
                           prompts: [String: ClaudeAccountUsageAttribution.Prompts] = [:],
                           machineBlock: BlockUsage? = nil, todayTokens: Int = 1_000) -> UsageStore {
        if personalStatus != nil { testDefaults.set(personal, forKey: ClaudeAccountRoots.defaultsKey) }
        let personalPath = personal
        return UsageStore(
            providers: [TodayUsage(block: machineBlock, tokens: todayTokens)],
            claudeLimitsProvider: ScriptedLimits([.success(primary)]),
            additionalClaudeLimitsProvider: { _ in
                ScriptedLimits([personalStatus.map { .success($0) } ?? .failure(.keychainInteractionNotAllowed)])
            },
            readLastPrompt: { folder in
                folder.standardizedFileURL.path == personalPath ? lastPrompt["personal"] : lastPrompt["default"]
            },
            claudeUsageEntries: { _ in usage },
            readPromptHistory: { folder in
                prompts[folder.standardizedFileURL.path == personalPath ? "personal" : "default"] ?? [:]
            },
            codexLimitsProvider: NoCodex(),
            antigravityLimitsProvider: NoAntigravity(),
            statusProvider: NoStatuses(),
            autoRefresh: false,
            defaults: testDefaults)
    }

    func testAutomaticModeFollowsTheLastUsedAccountEverywhere() async throws {
        let now = Date()
        let store = makeStore(
            primary: fullStatus(fiveHour: 100, sevenDay: 100, email: "me@corp.example", org: "Corp"),
            personal: fullStatus(fiveHour: 61, sevenDay: 21, email: "me@example.com"),
            lastPrompt: ["default": now.addingTimeInterval(-3600), "personal": now])
        store.showLimitInMenu = true
        store.showTokensInMenu = false
        store.localizationLanguage = .en
        await store.refresh(scheduleEmptyRetry: false)

        XCTAssertEqual(store.claudeAccountActivity[ClaudeAccountLimits.defaultID], now.addingTimeInterval(-3600))
        XCTAssertEqual(store.trackedClaudeAccount?.id, personalKey)
        XCTAssertEqual(store.menuLines, ["Claude 61%"])
        XCTAssertEqual(store.menuToolTip, "Tracked Claude account: me@example.com")
        XCTAssertFalse(store.isLimitWarning, "the exhausted default account is not the one in use")
        XCTAssertEqual(try XCTUnwrap(store.highestLimitUtilization), 61, accuracy: 0.01)

        store.claudeTrackedAccountMode = .defaultAccount
        XCTAssertEqual(store.menuLines, ["Claude 100%"])
        XCTAssertEqual(store.menuToolTip, "Tracked Claude account: Corp")
        XCTAssertTrue(store.isLimitWarning)
        XCTAssertEqual(store.fiveHourForecast?.beforeReset, nil, "no reset date, no forecast")
        XCTAssertEqual(testDefaults.string(forKey: ClaudeTrackedAccountMode.defaultsKey), "default")
    }

    func testTheMenuToolTipOnlyNamesAnAccountBehindAShownPercentage() async throws {
        let alone = makeStore(primary: fullStatus(fiveHour: 40, sevenDay: 10, email: "me@corp.example", org: "Corp"),
                              personal: nil, lastPrompt: [:])
        alone.showLimitInMenu = true
        await alone.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(alone.menuLines.last, "Claude 40%")
        XCTAssertNil(alone.menuToolTip, "a single account needs no name")

        let both = makeStore(primary: fullStatus(fiveHour: 40, sevenDay: 10, email: "me@corp.example", org: "Corp"),
                             personal: fullStatus(fiveHour: 61, sevenDay: 21, email: "me@example.com"),
                             lastPrompt: ["personal": Date()])
        both.localizationLanguage = .fr
        both.showLimitInMenu = false
        await both.refresh(scheduleEmptyRetry: false)
        XCTAssertNil(both.menuToolTip, "no percentage in the menu bar, nothing to name")
        both.showLimitInMenu = true
        XCTAssertEqual(both.menuToolTip, "Compte Claude suivi : me@example.com")

        let idle = makeStore(primary: fullStatus(fiveHour: 40, sevenDay: 10, email: "me@corp.example", org: "Corp"),
                             personal: fullStatus(fiveHour: 61, sevenDay: 21, email: "me@example.com"),
                             lastPrompt: ["personal": Date()], todayTokens: 0)
        idle.showLimitInMenu = true
        await idle.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(idle.trackedClaudeAccount?.id, personalKey)
        XCTAssertEqual(idle.menuLines.filter { $0.hasPrefix("Claude") }, [], "Claude was not used today")
        XCTAssertNil(idle.menuToolTip)

        var weeklyOnly = try JSONDecoder().decode(LimitStatus.self, from: Data(#"{"seven_day":{"utilization":30}}"#.utf8))
        weeklyOnly.accountEmail = "me@example.com"
        let noFiveHour = makeStore(primary: fullStatus(fiveHour: 40, sevenDay: 10, email: "me@corp.example", org: "Corp"),
                                   personal: weeklyOnly, lastPrompt: ["personal": Date()])
        noFiveHour.showLimitInMenu = true
        await noFiveHour.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(noFiveHour.trackedClaudeAccount?.id, personalKey)
        XCTAssertEqual(noFiveHour.menuLines.filter { $0.hasPrefix("Claude") }, [])
        XCTAssertNil(noFiveHour.menuToolTip, "the tracked account shows no 5h percentage")
    }

    func testTheForecastUsesTheTrackedAccount() async {
        let reset = ISO8601DateFormatter().string(from: Date().addingTimeInterval(3600))
        func status(_ utilization: Double, _ email: String) -> LimitStatus {
            var s = try! JSONDecoder().decode(LimitStatus.self, from: Data(
                "{\"five_hour\":{\"utilization\":\(utilization),\"resets_at\":\"\(reset)\"}}".utf8))
            s.accountEmail = email
            return s
        }
        let store = makeStore(primary: status(40, "me@corp.example"), personal: status(100, "me@example.com"),
                              lastPrompt: ["personal": Date()])
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(store.fiveHourForecast?.beforeReset, true, "the tracked personal account is at 100%")

        store.claudeTrackedAccountMode = .defaultAccount
        XCTAssertNil(store.fiveHourForecast, "40% without a local block: no forecast")
    }

    /// With several accounts the machine-wide block mixes their burn: each forecast uses its own.
    func testTheForecastUsesTheTrackedAccountsOwnBurn() async {
        let now = Date()
        let reset = ISO8601DateFormatter().string(from: now.addingTimeInterval(3600))
        func status(_ utilization: Double, _ email: String) -> LimitStatus {
            var s = try! JSONDecoder().decode(LimitStatus.self, from: Data(
                "{\"five_hour\":{\"utilization\":\(utilization),\"resets_at\":\"\(reset)\"}}".utf8))
            s.accountEmail = email
            return s
        }
        // 600k tokens in the last 10 minutes on the personal login: 15 minutes left at 40%.
        let burst = entry("b", session: "home", at: now.addingTimeInterval(-600), tokens: 600_000,
                          day: LocalUsageReader.todayKey())
        let machine = BlockUsage(id: "m", startTime: "", endTime: "", isActive: true, totalTokens: 600_000,
                                 costUSD: 0, tokensPerMinute: 60_000)
        let store = makeStore(primary: status(40, "me@corp.example"), personal: status(40, "me@example.com"),
                              lastPrompt: ["personal": now], usage: [burst],
                              prompts: ["personal": ["home": [now.addingTimeInterval(-700)]]],
                              machineBlock: machine)
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(store.trackedClaudeAccount?.id, personalKey)
        XCTAssertEqual(store.fiveHourForecast?.beforeReset, true)

        store.claudeTrackedAccountMode = .defaultAccount
        XCTAssertNil(store.fiveHourForecast, "the default login burned nothing: the personal burst is not its own")
    }

    func testASingleAccountForecastUsesTheMachineBlock() async {
        let reset = ISO8601DateFormatter().string(from: Date().addingTimeInterval(3600))
        var status = try! JSONDecoder().decode(LimitStatus.self, from: Data(
            "{\"five_hour\":{\"utilization\":40,\"resets_at\":\"\(reset)\"}}".utf8))
        status.accountEmail = "me@corp.example"
        let machine = BlockUsage(id: "m", startTime: "", endTime: "", isActive: true, totalTokens: 600_000,
                                 costUSD: 0, tokensPerMinute: 60_000)
        let store = makeStore(primary: status, personal: nil, lastPrompt: [:], machineBlock: machine)
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(store.fiveHourForecast?.beforeReset, true)
    }

    func testChangingTheTrackedAccountUpdatesTheCompanionAtOnce() {
        let store = makeStore(primary: fullStatus(fiveHour: 10, sevenDay: 1, email: "me@corp.example"),
                              personal: nil, lastPrompt: [:])
        var updates = 0
        store.onRefresh = { updates += 1 }
        store.claudeTrackedAccountMode = .highest
        XCTAssertEqual(updates, 1)
    }

    func testTheSavedModeIsReadBackAndSingleAccountsIgnoreIt() async {
        testDefaults.set("account:\(personalKey)", forKey: ClaudeTrackedAccountMode.defaultsKey)
        let store = makeStore(primary: fullStatus(fiveHour: 10, sevenDay: 1, email: "me@corp.example"),
                              personal: nil, lastPrompt: [:])
        XCTAssertEqual(store.claudeTrackedAccountMode, .account(personalKey))

        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(store.trackedClaudeAccount?.id, ClaudeAccountLimits.defaultID, "single account: always that one")
        XCTAssertTrue(store.claudeAccountActivity.isEmpty, "no history read without other accounts")
    }

    func testAdditionalValuesAreDatedAndFlaggedStale() async throws {
        let store = makeStore(primary: fullStatus(fiveHour: 10, sevenDay: 1, email: "me@corp.example"),
                              personal: fullStatus(fiveHour: 61, sevenDay: 21, email: "me@example.com"),
                              lastPrompt: [:])
        let before = Date()
        await store.refresh(scheduleEmptyRetry: false)
        let updatedAt = try XCTUnwrap(store.additionalLimits.first?.updatedAt)
        XCTAssertGreaterThanOrEqual(updatedAt, before)
        XCTAssertFalse(store.additionalLimitsStale)
        let account = try XCTUnwrap(store.claudeAccounts.last)
        XCTAssertTrue(account.isStale(now: updatedAt.addingTimeInterval(16 * 60)))
        XCTAssertEqual(store.claudeAccounts.first?.updatedAt, store.limitsUpdatedAt)
    }
}

// MARK: Usage per account

private func entry(_ id: String, session: String?, at date: Date, tokens: Int, day: String,
                   model: String = "claude-sonnet-4-6") -> LocalUsageReader.Entry {
    var e = LocalUsageReader.Entry(id: id, date: date, localDay: day, model: model,
                                   input: tokens, output: 0, cacheWrite: 0, cacheRead: 0)
    e.sessionID = session
    return e
}

final class ClaudeSessionIDTests: XCTestCase {
    func testSessionComesFromTheTranscriptPath() {
        let project = URL(fileURLWithPath: "/Users/example/.claude/projects/-Users-example-app")
        XCTAssertEqual(LocalUsageReader.claudeSessionID(forTranscript: project.appendingPathComponent("abc-123.jsonl")), "abc-123")
        XCTAssertEqual(LocalUsageReader.claudeSessionID(
            forTranscript: project.appendingPathComponent("abc-123/subagents/agent-9.jsonl")), "abc-123",
                       "a subagent counts with its parent session")
    }

    func testParsedAndCachedEntriesCarryTheirSession() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ptb-session-\(UUID().uuidString)", isDirectory: true)
        let project = root.appendingPathComponent("-Users-example-app", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let line = #"{"type":"assistant","timestamp":"2026-09-16T10:00:00Z","requestId":"r1","message":{"id":"m1","model":"claude-sonnet-4-6","usage":{"input_tokens":10,"output_tokens":5}}}"#
        let transcript = project.appendingPathComponent("sess-1.jsonl")
        try Data(line.utf8).write(to: transcript)
        // Whole seconds, so the signature survives the cache's Double round trip.
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_790_000_000)],
                                              ofItemAtPath: transcript.path)

        let parsed = LocalUsageReader.parseClaudeFile(transcript, fmt: LocalUsageReader.localDayFormatter())
        XCTAssertEqual(parsed.map(\.sessionID), ["sess-1"])

        // A blob cached before `sessionID` existed: same signature, entry without the field.
        let values = try transcript.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        // Different from the file on purpose: seeing 1_000 proves the entry was served from the cache.
        var legacy = LocalUsageReader.Entry(id: parsed[0].id, date: parsed[0].date, localDay: parsed[0].localDay,
                                            model: parsed[0].model, input: 1_000, output: 0, cacheWrite: 0, cacheRead: 0)
        legacy.sessionID = nil
        let entries = try JSONSerialization.jsonObject(with: JSONEncoder().encode([legacy]))
        // The cache keys blobs by the enumerated path (/var resolves to /private/var): take it the same way.
        let key = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.first { $0.lastPathComponent == "sess-1.jsonl" }).path
        let snapshot: [String: Any] = ["claude": [key: [
            "mtime": try XCTUnwrap(values.contentModificationDate).timeIntervalSinceReferenceDate,
            "size": try XCTUnwrap(values.fileSize),
            "entries": entries,
        ]]]
        let cacheFile = root.appendingPathComponent("usage-cache.json")
        try JSONSerialization.data(withJSONObject: snapshot).write(to: cacheFile)
        XCTAssertFalse(String(decoding: try Data(contentsOf: cacheFile), as: UTF8.self).contains("sessionID"))

        let cached = await LocalUsageCache(claudeRoot: root, fileURL: cacheFile)
            .claudeEntries(modifiedSince: .distantPast)
        XCTAssertEqual(cached.map(\.sessionID), ["sess-1"], "legacy blobs get their session from the path")
        XCTAssertEqual(cached.map(\.total), [1_000], "served from the legacy blob, not re-parsed")
    }
}

final class ClaudePromptHistoryTests: XCTestCase {
    func testPromptsAreGroupedBySessionAndSorted() {
        let text = """
        {"display":"b","timestamp":1790000060000,"sessionId":"s1","project":"/p"}
        {"display":"a","timestamp":1790000000000,"sessionId":"s1","project":"/p"}
        {"display":"c","timestamp":"2026-09-16T10:00:00Z","sessionId":"s2"}
        {"display":"old line without a session","timestamp":1790000000000}
        {"display":"bad timestamp","timestamp":0,"sessionId":"s3"}
        not json
        """
        let prompts = ClaudePromptHistory.parse(text)
        XCTAssertEqual(Set(prompts.keys), ["s1", "s2"])
        XCTAssertEqual(prompts["s1"], [Date(timeIntervalSince1970: 1_790_000_000), Date(timeIntervalSince1970: 1_790_000_060)])
        XCTAssertEqual(prompts["s2"]?.count, 1)
    }

    func testTheHistoryIsReadAgainOnlyForItsNewLines() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ptb-prompts-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("history.jsonl")
        let stamp = Date(timeIntervalSince1970: 1_790_000_000)
        func line(_ session: String, _ seconds: Int = 1_790_000_000) -> String {
            #"{"timestamp":"# + "\(seconds)000" + #","sessionId":""# + session + #""}"# + "\n"
        }
        func write(_ text: String) throws {
            try Data(text.utf8).write(to: file)
            try FileManager.default.setAttributes([.modificationDate: stamp], ofItemAtPath: file.path)
        }
        func sessions() -> [String] { ClaudePromptHistory.prompts(configDir: folder).keys.sorted() }

        XCTAssertEqual(sessions(), [], "no history, no prompts")
        try write(line("s1"))
        XCTAssertEqual(sessions(), ["s1"])
        // Same size and date: the cached result is served even though the content differs.
        try write(line("s9"))
        XCTAssertEqual(sessions(), ["s1"])
        // Appended lines only: the first line is not parsed again (s9 stays unseen).
        try write(line("s9") + line("s22") + line("s1", 1_789_999_000))
        XCTAssertEqual(sessions(), ["s1", "s22"])
        XCTAssertEqual(ClaudePromptHistory.prompts(configDir: folder)["s1"],
                       [Date(timeIntervalSince1970: 1_789_999_000), stamp], "merged prompts stay sorted")
        // A line still being written waits for its line break.
        let complete = line("s9") + line("s22") + line("s1", 1_789_999_000)
        let partial = line("s3")
        try write(complete + partial.dropLast(5))
        XCTAssertEqual(sessions(), ["s1", "s22"])
        try write(complete + partial)
        XCTAssertEqual(sessions(), ["s1", "s22", "s3"])
        // A shorter file was rewritten: read it all again.
        try write(line("s4"))
        XCTAssertEqual(sessions(), ["s4"])
        // So was a longer one that no longer breaks a line where the last read ended.
        try write(#"{"display":"a longer first prompt","timestamp":1790000000000,"sessionId":"s5"}"# + "\n")
        XCTAssertEqual(sessions(), ["s5"])
    }

    func testNoHistoryIsReadOutsideTheApp() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ptb-prompts-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data(#"{"timestamp":1790000000000,"sessionId":"s1"}"#.utf8 + [0x0A])
            .write(to: folder.appendingPathComponent("history.jsonl"))
        XCTAssertEqual(ClaudePromptHistory.installedPrompts(configDir: folder, isBundledApp: false), [:])
        XCTAssertEqual(ClaudePromptHistory.installedPrompts(configDir: folder, isBundledApp: true).keys.sorted(), ["s1"])
        XCTAssertNil(ClaudeAccountRoots.installedLastPromptDate(configDir: folder, isBundledApp: false))
        XCTAssertNotNil(ClaudeAccountRoots.installedLastPromptDate(configDir: folder, isBundledApp: true))
    }

    func testNoUsageIsScannedOutsideTheApp() async {
        let entries = await UsageStore.installedClaudeUsageEntries(modifiedSince: .distantPast, isBundledApp: false)
        XCTAssertTrue(entries.isEmpty)
    }
}

final class ClaudeAccountUsageAttributionTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)
    private func at(_ minutes: Double) -> Date { t0.addingTimeInterval(minutes * 60) }

    private var accounts: [ClaudeAccountUsageAttribution.Account] {
        [.init(id: "default", prompts: ["work": [at(0)], "resumed": [at(0), at(10)], "tie": [at(5)],
                                        "pingpong": [at(0), at(40)]]),
         .init(id: "personal", prompts: ["mine": [at(0)], "resumed": [at(20), at(30)], "tie": [at(5)],
                                      "pingpong": [at(20)]])]
    }

    private func owner(_ session: String, _ minutes: Double) -> String? {
        ClaudeAccountUsageAttribution.owner(session: session, at: at(minutes), accounts: accounts)
    }

    func testASessionBelongsToItsOnlyLogin() {
        XCTAssertEqual(owner("work", 3), "default")
        XCTAssertEqual(owner("mine", 3), "personal")
        XCTAssertNil(owner("unknown", 3))
    }

    func testAResumedSessionChangesOwnerAtTheFirstPromptOfTheOtherLogin() {
        XCTAssertEqual(owner("resumed", 15), "default")
        XCTAssertEqual(owner("resumed", 20), "personal", "a prompt and its turn share the minute")
        XCTAssertEqual(owner("resumed", 45), "personal")
        XCTAssertEqual(owner("pingpong", 30), "personal")
        XCTAssertEqual(owner("pingpong", 45), "default", "back on the first login: its latest prompt wins")
    }

    func testEdgeCasesStayDeterministic() {
        XCTAssertEqual(owner("resumed", -1), "default", "before any prompt: the login that started the session")
        XCTAssertEqual(owner("tie", 6), "default", "equal prompt times: the first account in order")
    }

    func testTotalsPerAccountTodayAndThisMonth() {
        let entries = [
            entry("1", session: "work", at: at(1), tokens: 100, day: "2026-09-17"),
            entry("2", session: "work", at: at(1), tokens: 40, day: "2026-09-02"),
            entry("3", session: "resumed", at: at(25), tokens: 7, day: "2026-09-17"),
            entry("4", session: "unknown", at: at(1), tokens: 5, day: "2026-09-17"),
            entry("5", session: nil, at: at(1), tokens: 3, day: "2026-09-10"),
            entry("6", session: "work", at: at(1), tokens: 1_000, day: "2026-08-31"),
        ]
        let result = ClaudeAccountUsageAttribution.usage(
            entries: entries, accounts: accounts, now: at(30), todayKey: "2026-09-17", monthStartKey: "2026-09-01")

        XCTAssertEqual(result.byAccount["default"]?.todayTokens, 100)
        XCTAssertEqual(result.byAccount["default"]?.monthTokens, 140, "last month's turns are left out")
        XCTAssertEqual(result.byAccount["personal"]?.todayTokens, 7)
        XCTAssertEqual(result.unattributed.todayTokens, 5)
        XCTAssertEqual(result.unattributed.monthTokens, 8)
        XCTAssertEqual(Set(result.byAccount.keys), ["default", "personal"])
        XCTAssertGreaterThan(result.byAccount["default"]?.monthCost.amount ?? 0, 0, "priced like the header totals")
        XCTAssertTrue(result.byAccount["default"]?.monthCost.coverage.estimated ?? false)

        let allKnown = ClaudeAccountUsageAttribution.usage(
            entries: [entries[0]], accounts: accounts, now: at(30), todayKey: "2026-09-17", monthStartKey: "2026-09-01")
        XCTAssertEqual(allKnown.unattributed, ClaudeAccountUsage(), "nothing unattributed: an empty total")
    }

    func testEachAccountGetsItsOwnActiveBlock() {
        let entries = [
            entry("1", session: "work", at: at(1), tokens: 100, day: "2026-09-17"),
            entry("2", session: "work", at: at(-240), tokens: 40, day: "2026-08-31"),
            entry("3", session: "resumed", at: at(25), tokens: 7, day: "2026-09-17"),
            entry("4", session: "unknown", at: at(1), tokens: 5, day: "2026-09-17"),
            entry("5", session: "work", at: at(-400), tokens: 1_000, day: "2026-09-17"),
        ]
        let result = ClaudeAccountUsageAttribution.usage(
            entries: entries, accounts: accounts, now: at(30), todayKey: "2026-09-17", monthStartKey: "2026-09-01")
        XCTAssertEqual(result.activeBlocks["default"]?.totalTokens, 140,
                       "a block started last month still counts; older turns do not")
        XCTAssertEqual(result.activeBlocks["personal"]?.totalTokens, 7)
        XCTAssertEqual(Set(result.activeBlocks.keys), ["default", "personal"], "unattributed turns have no block")

        let later = ClaudeAccountUsageAttribution.usage(
            entries: entries, accounts: accounts, now: at(600), todayKey: "2026-09-17", monthStartKey: "2026-09-01")
        XCTAssertTrue(later.activeBlocks.isEmpty)
    }

    func testTotalsAddUp() {
        var total = ClaudeAccountUsage(todayTokens: 1, todayCost: UsageCost(amount: 0.5, coverage: .source),
                                       monthTokens: 10, monthCost: UsageCost(amount: 2, coverage: .source))
        total.add(ClaudeAccountUsage(todayTokens: 2, todayCost: UsageCost(amount: 0.25, coverage: .source),
                                     monthTokens: 20, monthCost: UsageCost(amount: 1, coverage: .source)))
        XCTAssertEqual(total.todayTokens, 3)
        XCTAssertEqual(total.todayCost.amount, 0.75)
        XCTAssertEqual(total.monthTokens, 30)
        XCTAssertEqual(total.monthCost.amount, 3)
    }
}

@MainActor
final class ClaudeAccountUsageStoreTests: XCTestCase {
    nonisolated(unsafe) private var testDefaults: UserDefaults!
    nonisolated(unsafe) private var suiteName: String!
    nonisolated(unsafe) private var base: URL!

    override func setUpWithError() throws {
        suiteName = "ptb-account-usage-\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)
        KeychainAccessGate.isDisabled = false
        base = FileManager.default.temporaryDirectory
            .appendingPathComponent("ptb-account-usage-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base.appendingPathComponent("personal"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        testDefaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: base)
    }

    func testUsageIsSplitBetweenTheListedAccounts() async throws {
        let personal = base.appendingPathComponent("personal").standardizedFileURL.path
        let personalKey = ClaudeAccountRoots.pathKey(for: URL(fileURLWithPath: personal))
        testDefaults.set(personal, forKey: ClaudeAccountRoots.defaultsKey)
        let now = Date()
        let today = LocalUsageReader.todayKey()
        let asked = ScanRecorder()
        let store = UsageStore(
            providers: [NilDailyProvider()],
            claudeLimitsProvider: ScriptedLimits([.success(limitStatus(fiveHour: 10, email: "me@corp.example"))]),
            additionalClaudeLimitsProvider: { _ in ScriptedLimits([.success(limitStatus(fiveHour: 20, email: "me@example.com"))]) },
            readLastPrompt: { _ in nil },
            claudeUsageEntries: { since in
                await asked.record(since)
                return [entry("1", session: "corp", at: now, tokens: 100, day: today),
                        entry("2", session: "home", at: now, tokens: 30, day: today),
                        entry("3", session: "cli-print", at: now, tokens: 4, day: today)]
            },
            readPromptHistory: { folder in
                folder.standardizedFileURL.path == personal ? ["home": [now.addingTimeInterval(-60)]]
                                                         : ["corp": [now.addingTimeInterval(-60)]]
            },
            codexLimitsProvider: NoCodex(),
            antigravityLimitsProvider: NoAntigravity(),
            statusProvider: NoStatuses(),
            autoRefresh: false,
            defaults: testDefaults)

        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(store.claudeAccountUsage[ClaudeAccountLimits.defaultID]?.todayTokens, 100)
        XCTAssertEqual(store.claudeAccountUsage[personalKey]?.todayTokens, 30)
        XCTAssertEqual(store.unattributedClaudeUsage.todayTokens, 4)
        let recorded = await asked.values.first
        let scannedFrom = try XCTUnwrap(recorded)
        let expected = UsageStore.claudeUsageScanStart(now: now)
        XCTAssertEqual(scannedFrom.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 5)

        store.additionalClaudeConfigDirs = ""
        for _ in 0..<100 where !store.claudeAccountUsage.isEmpty || store.isRefreshing {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(store.claudeAccountUsage.isEmpty, "a single account needs no split")
        XCTAssertEqual(store.unattributedClaudeUsage, ClaudeAccountUsage())
    }
}

extension ClaudeAccountUsageStoreTests {
    /// A folder hidden as a duplicate still counts for its account, and an account without a tab
    /// is not shown under another name.
    func testDuplicateFoldersAddUpAndTablessAccountsAreUnattributed() async throws {
        let fm = FileManager.default
        let work = base.appendingPathComponent("work").standardizedFileURL.path
        let team = base.appendingPathComponent("team").standardizedFileURL.path
        try fm.createDirectory(atPath: work, withIntermediateDirectories: true)
        try fm.createDirectory(atPath: team, withIntermediateDirectories: true)
        let personal = base.appendingPathComponent("personal").standardizedFileURL.path
        let personalKey = ClaudeAccountRoots.pathKey(for: URL(fileURLWithPath: personal))
        testDefaults.set([work, personal, team].joined(separator: ","), forKey: ClaudeAccountRoots.defaultsKey)
        let now = Date()
        let today = LocalUsageReader.todayKey()
        let byFolder: [String: (String, Date)] = [
            work: ("w", now.addingTimeInterval(-30)), personal: ("p", now.addingTimeInterval(-50)),
            team: ("t", now.addingTimeInterval(-10)),
        ]
        let store = UsageStore(
            providers: [NilDailyProvider()],
            claudeLimitsProvider: ScriptedLimits([.success(limitStatus(fiveHour: 10, email: "me@corp.example"))]),
            additionalClaudeLimitsProvider: { root in
                switch root.path {
                case work: ScriptedLimits([.success(limitStatus(fiveHour: 10, email: "me@corp.example"))])
                case personal: ScriptedLimits([.success(limitStatus(fiveHour: 20, email: "me@example.com"))])
                default: ScriptedLimits([.failure(.keychainInteractionNotAllowed)])
                }
            },
            readLastPrompt: { folder in
                byFolder[folder.standardizedFileURL.path]?.1 ?? now.addingTimeInterval(-20)
            },
            claudeUsageEntries: { _ in
                ["c", "w", "p", "t"].map { entry($0, session: $0, at: now, tokens: 10, day: today) }
            },
            readPromptHistory: { folder in
                let (session, date) = byFolder[folder.standardizedFileURL.path] ?? ("c", now.addingTimeInterval(-20))
                return [session: [date]]
            },
            codexLimitsProvider: NoCodex(),
            antigravityLimitsProvider: NoAntigravity(),
            statusProvider: NoStatuses(),
            sessionKeys: SessionKeys(nil),
            autoRefresh: false,
            defaults: testDefaults)

        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(store.claudeAccounts.map(\.id), [ClaudeAccountLimits.defaultID, personalKey])
        XCTAssertEqual(store.claudeAccountUsage[ClaudeAccountLimits.defaultID]?.todayTokens, 20,
                       "the default login's turns plus those of its second folder")
        XCTAssertEqual(store.claudeAccountUsage[personalKey]?.todayTokens, 10)
        XCTAssertEqual(Set(store.claudeAccountUsage.keys), [ClaudeAccountLimits.defaultID, personalKey])
        XCTAssertEqual(store.unattributedClaudeUsage.todayTokens, 10, "the team folder has no tab yet")
        XCTAssertEqual(store.claudeAccountActivity[ClaudeAccountLimits.defaultID], now.addingTimeInterval(-20),
                       "the latest prompt of both folders, not the last folder's")
    }

    func testTheScanCoversTheMonthAndABlockStartedLastMonth() {
        let monthStart = LocalUsageReader.startOfMonth(Date())
        let early = monthStart.addingTimeInterval(2 * 3600)
        XCTAssertEqual(UsageStore.claudeUsageScanStart(now: early), early.addingTimeInterval(-LocalUsageReader.blockWindow))
        let later = monthStart.addingTimeInterval(10 * 86_400)
        XCTAssertEqual(UsageStore.claudeUsageScanStart(now: later), monthStart)
    }
}

private actor ScanRecorder {
    var values: [Date] = []
    func record(_ date: Date) { values.append(date) }
}
