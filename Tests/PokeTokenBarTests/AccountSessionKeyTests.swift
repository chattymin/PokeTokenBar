import XCTest
@testable import PokeTokenBar

// A claude.ai session key per additional Claude folder. Without one, a folder's limits come from its
// Keychain token, which automatic polls never read, so they stopped at every token expiry.

// MARK: Stubs

private let validKey = "sk-ant-sid01-" + String(repeating: "a", count: 40)

private let usageJSON = #"{"five_hour":{"utilization":42,"resets_at":null},"seven_day":{"utilization":10,"resets_at":null}}"#

private func ok(_ json: String) -> SessionKeyHTTPResponse {
    SessionKeyHTTPResponse(status: 200, data: Data(json.utf8), retryAfter: nil)
}

private actor StubHTTP: SessionKeyHTTPClient {
    private let responses: [String: SessionKeyHTTPResponse]
    init(_ responses: [String: SessionKeyHTTPResponse]) { self.responses = responses }
    func get(_ url: URL, sessionKey: String) async throws -> SessionKeyHTTPResponse {
        responses[url.path] ?? SessionKeyHTTPResponse(status: 404, data: Data(), retryAfter: nil)
    }
}

private func status(fiveHour: Double, email: String? = nil) -> LimitStatus {
    var status = try! JSONDecoder().decode(
        LimitStatus.self, from: Data("{\"five_hour\":{\"utilization\":\(fiveHour),\"resets_at\":null}}".utf8))
    status.accountEmail = email
    return status
}

/// Scripted results, recording the prompt flag of every call. The last result repeats.
private final class ScriptedLimits: ClaudeLimitsProviding, @unchecked Sendable {
    nonisolated(unsafe) var results: [Result<LimitStatus, LimitsError>]
    nonisolated(unsafe) var promptFlags: [Bool] = []
    init(_ results: [Result<LimitStatus, LimitsError>]) { self.results = results }
    func fetch(allowKeychainPrompt: Bool) async throws -> LimitStatus {
        promptFlags.append(allowKeychainPrompt)
        let result = results.count > 1 ? results.removeFirst() : results[0]
        return try result.get()
    }
}

private final class AccountKeys: SessionKeyManaging, @unchecked Sendable {
    nonisolated(unsafe) var stored: SessionKeyCredential?
    let listed: [SessionKeyOrganization]
    init(stored: SessionKeyCredential? = nil, organizations: [SessionKeyOrganization] = []) {
        self.stored = stored
        self.listed = organizations
    }
    func credential() -> SessionKeyCredential? { stored }
    func organizations(sessionKey: String) async throws -> [SessionKeyOrganization] { listed }
    func save(key: String, organizationID: String?) throws {
        stored = SessionKeyCredential(key: key, organizationID: organizationID)
    }
    func clear() { stored = nil }
}

private func organization(_ id: String, hasUsageData: Bool) -> SessionKeyOrganization {
    SessionKeyOrganization(id: id, name: id, hasUsageData: hasUsageData, limits: LimitStatus())
}

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

// MARK: Key file and limits chain

final class AccountSessionKeyChainTests: XCTestCase {
    private var directory: URL!
    private let root = URL(fileURLWithPath: "/Users/example/.claude-personal", isDirectory: true)

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ptb-account-keys-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func saveKey(organizationID: String) throws {
        try SessionKeyStore.forConfigRoot(root, directory: directory)
            .save(SessionKeyCredential(key: validKey, organizationID: organizationID))
    }

    func testEachFolderHasItsOwnKeyFileNextToTheDefaultOne() {
        let store = SessionKeyStore.forConfigRoot(root, directory: directory)
        XCTAssertEqual(store.fileURL.lastPathComponent, "session-key-\(ClaudeAccountRoots.pathKey(for: root)).json")
        XCTAssertEqual(store.fileURL.deletingLastPathComponent().path, directory.path)
        let work = SessionKeyStore.forConfigRoot(URL(fileURLWithPath: "/Users/example/.claude-work"), directory: directory)
        XCTAssertNotEqual(work.fileURL, store.fileURL)
    }

    /// The point of the key: an automatic poll, which never reads the Keychain, still loads the account.
    func testAnAutomaticPollUsesTheFolderKeyInsteadOfItsToken() async throws {
        try saveKey(organizationID: "org-personal")
        let token = ScriptedLimits([.failure(.keychainInteractionNotAllowed)])
        let chain = ChainedLimitsProvider.forConfigRoot(
            root, sessionKeyDirectory: directory,
            http: StubHTTP(["/api/organizations/org-personal/usage": ok(usageJSON)]), fallback: token)

        let status = try await chain.fetch(allowKeychainPrompt: false)
        XCTAssertEqual(status.fiveHour?.utilization, 42)
        XCTAssertEqual(token.promptFlags, [], "the folder's token is not needed")
    }

    func testWithoutAKeyTheFolderTokenWorksAsBefore() async throws {
        let token = ScriptedLimits([.success(status(fiveHour: 5))])
        let chain = ChainedLimitsProvider.forConfigRoot(
            root, sessionKeyDirectory: directory, http: StubHTTP([:]), fallback: token)

        let status = try await chain.fetch(allowKeychainPrompt: true)
        XCTAssertEqual(status.fiveHour?.utilization, 5)
        XCTAssertEqual(token.promptFlags, [true], "a manual refresh may still read the Keychain")
    }

    /// A dead key is fixed in Settings: even a manual refresh must not fall back to a Keychain prompt.
    func testADeadKeyNeverFallsBackToAKeychainPrompt() async throws {
        try saveKey(organizationID: "org-personal")
        let token = ScriptedLimits([.failure(.keychainInteractionNotAllowed)])
        let chain = ChainedLimitsProvider.forConfigRoot(
            root, sessionKeyDirectory: directory,
            http: StubHTTP([
                "/api/organizations/org-personal/usage": SessionKeyHTTPResponse(status: 401, data: Data(), retryAfter: nil),
            ]),
            fallback: token)

        do {
            _ = try await chain.fetch(allowKeychainPrompt: true)
            XCTFail("a dead key must fail")
        } catch {
            XCTAssertEqual(error as? LimitsError, .sessionKeyInvalid)
        }
        XCTAssertEqual(token.promptFlags, [false])
    }

    func testTheFolderOrganizationWinsThenTheDefaultRule() {
        let personal = organization("org-personal", hasUsageData: true)
        let team = organization("org-team", hasUsageData: false)
        XCTAssertEqual(UsageStore.accountOrganization([personal, team], loggedIn: "org-team")?.id, "org-team")
        XCTAssertEqual(UsageStore.accountOrganization([team, personal], loggedIn: "org-gone")?.id, "org-personal",
                       "an unknown login falls back to the organization with usage data")
        XCTAssertEqual(UsageStore.accountOrganization([team], loggedIn: nil)?.id, "org-team")
        XCTAssertNil(UsageStore.accountOrganization([], loggedIn: "org-team"))
    }
}

// MARK: Store pipeline

@MainActor
final class AccountSessionKeyStoreTests: XCTestCase {
    nonisolated(unsafe) private var testDefaults: UserDefaults!
    nonisolated(unsafe) private var suiteName: String!
    nonisolated(unsafe) private var base: URL!

    override func setUpWithError() throws {
        suiteName = "ptb-account-keys-\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)
        KeychainAccessGate.isDisabled = false
        base = FileManager.default.temporaryDirectory
            .appendingPathComponent("ptb-account-keys-store-\(UUID().uuidString)", isDirectory: true)
        for folder in ["work", "personal"] {
            try FileManager.default.createDirectory(
                at: base.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
    }

    override func tearDownWithError() throws {
        KeychainAccessGate.isDisabled = false
        testDefaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: base)
    }

    private var work: String { base.appendingPathComponent("work").standardizedFileURL.path }
    private var personal: String { base.appendingPathComponent("personal").standardizedFileURL.path }

    private func makeStore(folders: [String: ScriptedLimits], keys: [String: AccountKeys]) -> UsageStore {
        testDefaults.set(folders.keys.sorted(by: >).joined(separator: ","), forKey: ClaudeAccountRoots.defaultsKey)
        return UsageStore(
            providers: [NilDailyProvider()],
            claudeLimitsProvider: ScriptedLimits([.success(status(fiveHour: 10, email: "main@example.com"))]),
            additionalClaudeLimitsProvider: { folders[$0.path]! },
            codexLimitsProvider: NoCodex(),
            antigravityLimitsProvider: NoAntigravity(),
            statusProvider: NoStatuses(),
            sessionKeys: AccountKeys(),
            accountSessionKeys: { keys[$0.path] ?? AccountKeys() },
            autoRefresh: false,
            defaults: testDefaults)
    }

    /// The key sees the personal and the team organization: the folder's own login decides,
    /// even against the default rule (the one with usage data).
    func testSavingAKeyPicksTheFolderOrganizationAndShowsTheAccount() async throws {
        try Data(#"{"oauthAccount":{"emailAddress":"me@example.com","organizationUuid":"org-team"}}"#.utf8)
            .write(to: URL(fileURLWithPath: personal).appendingPathComponent(".claude.json"))
        let keys = AccountKeys(organizations: [organization("org-personal", hasUsageData: true),
                                               organization("org-team", hasUsageData: false)])
        let store = makeStore(folders: [personal: ScriptedLimits([.success(status(fiveHour: 42))])],
                              keys: [personal: keys])

        await store.saveAccountSessionKey(" \(validKey)\n", for: personal)

        XCTAssertNil(store.accountSessionKeyError(for: personal))
        XCTAssertEqual(keys.stored, SessionKeyCredential(key: validKey, organizationID: "org-team"))
        XCTAssertEqual(store.accountSessionKeyPaths, [personal])
        XCTAssertEqual(store.additionalLimits.map(\.status.fiveHour?.utilization), [42], "shown at once")
    }

    func testAMalformedKeyIsRejectedAndNothingIsSaved() async {
        let keys = AccountKeys(organizations: [organization("org-personal", hasUsageData: true)])
        let store = makeStore(folders: [personal: ScriptedLimits([.success(status(fiveHour: 42))])],
                              keys: [personal: keys])

        await store.saveAccountSessionKey("not-a-key", for: personal)

        XCTAssertNotNil(store.accountSessionKeyError(for: personal))
        XCTAssertNil(keys.stored)
        XCTAssertTrue(store.accountSessionKeyPaths.isEmpty)
    }

    /// A rejected key keeps the tab with its last values and points to Settings; a rejected token
    /// (the folder's Claude Code login) keeps the Claude Code advice.
    func testARejectedKeyExpiresTheTabUntilAnotherCauseReplacesIt() async {
        let folder = ScriptedLimits([
            .success(status(fiveHour: 20, email: "me@example.com")),
            .failure(.sessionKeyInvalid),
            .failure(.rateLimited(retryAfter: nil)),
            .failure(.httpStatus(401)),
        ])
        let store = makeStore(folders: [personal: folder],
                              keys: [personal: AccountKeys(stored: SessionKeyCredential(key: validKey))])
        func account() -> ClaudeAccountLimits? { store.claudeAccounts.first { !$0.isDefault } }

        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(account()?.isExpired, false)

        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(account()?.isExpired, true)
        XCTAssertEqual(account()?.sessionKeyExpired, true)
        XCTAssertEqual(account()?.status.fiveHour?.utilization, 20, "last values kept")

        await store.refreshLimitTokenFromKeychain()   // bypasses the 429 backoff
        XCTAssertEqual(account()?.sessionKeyExpired, true, "another failure keeps the known cause")

        await store.refreshLimitTokenFromKeychain()
        XCTAssertEqual(account()?.isExpired, true)
        XCTAssertEqual(account()?.sessionKeyExpired, false, "a token rejection is not the key's")
    }

    func testClearingAKeyDropsItsExpiry() async {
        let keys = AccountKeys(stored: SessionKeyCredential(key: validKey))
        let folder = ScriptedLimits([.success(status(fiveHour: 20)), .failure(.sessionKeyInvalid)])
        let store = makeStore(folders: [personal: folder], keys: [personal: keys])
        await store.refresh(scheduleEmptyRetry: false)
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(store.additionalLimits.first?.sessionKeyExpired, true)

        store.clearAccountSessionKey(for: personal)

        XCTAssertNil(keys.stored)
        XCTAssertTrue(store.accountSessionKeyPaths.isEmpty)
        XCTAssertEqual(store.additionalLimits.first?.isExpired, false)
        XCTAssertEqual(store.additionalLimits.first?.sessionKeyExpired, false)
    }

    /// Only the key's own expiry goes with it: a rejected folder token still needs Claude Code.
    func testClearingAKeyKeepsATokenExpiry() async {
        let keys = AccountKeys(stored: SessionKeyCredential(key: validKey))
        let folder = ScriptedLimits([.success(status(fiveHour: 20)), .failure(.httpStatus(401))])
        let store = makeStore(folders: [personal: folder], keys: [personal: keys])
        await store.refresh(scheduleEmptyRetry: false)
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(store.additionalLimits.first?.isExpired, true)

        store.clearAccountSessionKey(for: personal)

        XCTAssertEqual(store.additionalLimits.first?.isExpired, true)
    }

    /// Like the default key, a folder's own key needs no Keychain: turning the Keychain off keeps
    /// that account, while a folder without a key is cleared and never asked for its token.
    func testAKeyedFolderStillLoadsWithTheKeychainOff() async {
        let workFolder = ScriptedLimits([.success(status(fiveHour: 20, email: "work@example.com"))])
        let personalFolder = ScriptedLimits([.success(status(fiveHour: 30, email: "personal@example.com"))])
        let store = makeStore(folders: [work: workFolder, personal: personalFolder],
                              keys: [personal: AccountKeys(stored: SessionKeyCredential(key: validKey))])
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(store.additionalLimits.map(\.rootPath), [work, personal])

        store.disableKeychainAccess = true
        XCTAssertEqual(store.additionalLimits.map(\.rootPath), [personal], "kept at once")

        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(store.additionalLimits.map(\.rootPath), [personal])
        XCTAssertEqual(workFolder.promptFlags, [false], "the folder without a key is not fetched again")
        XCTAssertEqual(store.additionalClaudeConfigRoots, [work, personal],
                       "both folders keep their key row in Settings")
    }
}
