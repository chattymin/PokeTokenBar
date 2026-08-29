import XCTest
@testable import PokeTokenBar

/// #227: `/login` to a second Team email rewrites `~/.claude/.credentials.json` with a
/// new still-valid token. The in-memory cache used to return the previous token until
/// `expiresAt`, so official 5h/weekly bars (and the #199 account label) stayed on the
/// old account while companion EXP kept moving from local jsonl.
///
/// These tests call the production `accessToken` path with an injected file URL.
/// Restoring the cache-before-file early return reintroduces the bug and must fail
/// `testClaudeAutoPollPicksUpInPlaceAccountSwitch` (verified by injection).
final class CredentialSwitchCacheTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ptb-cred-switch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        KeychainReader.resetQueryCountForTesting()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
    }

    // MARK: Claude

    func testClaudeAutoPollPicksUpInPlaceAccountSwitch() async throws {
        let file = tempDir.appendingPathComponent("credentials.json")
        try writeClaudeCredentials(to: file, token: "token-account-a", subscription: "max")
        let cache = OAuthAccessTokenCache(credentialsFileURL: file)

        let first = try await cache.accessToken(allowKeychainPrompt: false)
        XCTAssertEqual(first, "token-account-a")
        let planA = await cache.planInfo()
        XCTAssertEqual(planA.subscriptionType, "max")

        try writeClaudeCredentials(to: file, token: "token-account-b", subscription: "team")
        let second = try await cache.accessToken(allowKeychainPrompt: false)
        XCTAssertEqual(
            second, "token-account-b",
            "auto-poll must re-read the credentials file; a still-unexpired cached token is the #227 bug")
        let planB = await cache.planInfo()
        XCTAssertEqual(planB.subscriptionType, "team")
        XCTAssertEqual(KeychainReader.queryCount, 0, "account switch via file must not touch Keychain")
    }

    /// File gone after a successful load (logout / CLAUDE_CONFIG_DIR leftover mop-up):
    /// keep serving the cached token on the auto path. Do not fall through to Keychain.
    func testClaudeAutoPollKeepsCacheWhenCredentialsFileDisappears() async throws {
        let file = tempDir.appendingPathComponent("credentials.json")
        try writeClaudeCredentials(to: file, token: "token-account-a", subscription: "max")
        let cache = OAuthAccessTokenCache(credentialsFileURL: file)

        _ = try await cache.accessToken(allowKeychainPrompt: false)
        try FileManager.default.removeItem(at: file)

        let stillCached = try await cache.accessToken(allowKeychainPrompt: false)
        XCTAssertEqual(stillCached, "token-account-a")
        XCTAssertEqual(KeychainReader.queryCount, 0)
    }

    /// `"claudeAiOauth": null` is logout-in-place, not "no file". Must not wipe a live
    /// cache — leftover mcpOAuth-only files under the default path are why
    /// `credentialsFileIsAccountOAuthMissing` already ignores CLAUDE_CONFIG_DIR.
    func testClaudeAutoPollKeepsCacheWhenFileDropsAccountOAuth() async throws {
        let file = tempDir.appendingPathComponent("credentials.json")
        try writeClaudeCredentials(to: file, token: "token-account-a", subscription: "max")
        let cache = OAuthAccessTokenCache(credentialsFileURL: file)

        _ = try await cache.accessToken(allowKeychainPrompt: false)
        try Data(#"{"claudeAiOauth":null}"#.utf8).write(to: file)

        let stillCached = try await cache.accessToken(allowKeychainPrompt: false)
        XCTAssertEqual(stillCached, "token-account-a")
        XCTAssertEqual(KeychainReader.queryCount, 0)
    }

    // MARK: Antigravity (same class)

    func testAntigravityAutoPollPicksUpTokenFileSwitch() async throws {
        let file = tempDir.appendingPathComponent("jetski-standalone-oauth-token")
        try writeAntigravityToken(to: file, token: "agy-account-a")
        let cache = AntigravityTokenCache(tokenFileURLs: [file])

        let first = try await cache.accessToken(allowKeychainPrompt: false)
        XCTAssertEqual(first, "agy-account-a")

        try writeAntigravityToken(to: file, token: "agy-account-b")
        let second = try await cache.accessToken(allowKeychainPrompt: false)
        XCTAssertEqual(
            second, "agy-account-b",
            "Antigravity file tokens are stored with expiresAt=nil, so cache-until-expiry never refreshes")
        XCTAssertEqual(KeychainReader.queryCount, 0)
    }

    func testAntigravityAutoPollKeepsCacheWhenTokenFileDisappears() async throws {
        let file = tempDir.appendingPathComponent("jetski-standalone-oauth-token")
        try writeAntigravityToken(to: file, token: "agy-account-a")
        let cache = AntigravityTokenCache(tokenFileURLs: [file])

        _ = try await cache.accessToken(allowKeychainPrompt: false)
        try FileManager.default.removeItem(at: file)

        let stillCached = try await cache.accessToken(allowKeychainPrompt: false)
        XCTAssertEqual(stillCached, "agy-account-a")
        XCTAssertEqual(KeychainReader.queryCount, 0)
    }

    // MARK: fixtures

    private func writeClaudeCredentials(
        to url: URL, token: String, subscription: String, expiresIn: TimeInterval = 3600
    ) throws {
        let expiresAt = Int(Date().addingTimeInterval(expiresIn).timeIntervalSince1970)
        let json = """
        {"claudeAiOauth":{"accessToken":"\(token)","expiresAt":\(expiresAt),"subscriptionType":"\(subscription)"}}
        """
        try Data(json.utf8).write(to: url, options: .atomic)
    }

    private func writeAntigravityToken(to url: URL, token: String) throws {
        let json = "{\"token\":\"\(token)\"}"
        try Data(json.utf8).write(to: url, options: .atomic)
    }
}
