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
        MockOAuthURLProtocol.reset()
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

    func testAntigravityAutoPollReadsNestedTokenObject() async throws {
        let file = tempDir.appendingPathComponent("jetski-standalone-oauth-token")
        try writeAntigravityNestedToken(
            to: file,
            accessToken: "ya29.nested-token-value",
            refreshToken: "1//sample-refresh-token",
            expiry: "2099-01-01T00:00:00Z"
        )
        let cache = AntigravityTokenCache(tokenFileURLs: [file])

        let token = try await cache.accessToken(allowKeychainPrompt: false)
        XCTAssertEqual(token, "ya29.nested-token-value")
        XCTAssertEqual(KeychainReader.queryCount, 0)
    }

    func testAntigravityAutoPollPicksUpNestedTokenSwitch() async throws {
        let file = tempDir.appendingPathComponent("jetski-standalone-oauth-token")
        try writeAntigravityNestedToken(to: file, accessToken: "ya29.nested-a")
        let cache = AntigravityTokenCache(tokenFileURLs: [file])

        let first = try await cache.accessToken(allowKeychainPrompt: false)
        XCTAssertEqual(first, "ya29.nested-a")

        try writeAntigravityNestedToken(to: file, accessToken: "ya29.nested-b")
        let second = try await cache.accessToken(allowKeychainPrompt: false)
        XCTAssertEqual(second, "ya29.nested-b")
        XCTAssertEqual(KeychainReader.queryCount, 0)
    }

    func testAntigravityAutoPollReadsTopLevelAccessToken() async throws {
        let file = tempDir.appendingPathComponent("jetski-standalone-oauth-token")
        let json = "{\"access_token\":\"ya29.top-level-token\",\"refresh_token\":\"1//sample\",\"expiry\":\"2099-01-01T00:00:00Z\"}"
        try Data(json.utf8).write(to: file, options: .atomic)
        let cache = AntigravityTokenCache(tokenFileURLs: [file])

        let token = try await cache.accessToken(allowKeychainPrompt: false)
        XCTAssertEqual(token, "ya29.top-level-token")
        XCTAssertEqual(KeychainReader.queryCount, 0)
    }

    func testAntigravityGoogleClientIDAndSecretAreConfigured() {
        XCTAssertFalse(AntigravityRateLimitsProvider.googleClientID.isEmpty)
        XCTAssertFalse(AntigravityRateLimitsProvider.googleClientSecret.isEmpty)
        XCTAssertEqual(AntigravityRateLimitsProvider.googleClientSecret.count, 35)
    }

    func testNearExpiryAccountSwitchDoesNotFallBackToPreviousCachedAccount() async throws {
        let file = tempDir.appendingPathComponent("jetski-standalone-oauth-token")
        // 1. Account A is written with valid lifetime (1 hour).
        let futureDate = Date().addingTimeInterval(3600)
        let formatter = ISO8601DateFormatter()
        try writeAntigravityNestedToken(
            to: file,
            accessToken: "ya29.account-a",
            refreshToken: "1//refresh-a",
            expiry: formatter.string(from: futureDate)
        )
        let cache = AntigravityTokenCache(tokenFileURLs: [file])

        let first = try await cache.accessToken(allowKeychainPrompt: false)
        XCTAssertEqual(first, "ya29.account-a")

        // 2. File switches to Account B whose token is near-expiry (30s remaining <= 60s margin, so isExpired == true).
        let nearExpiryDate = Date().addingTimeInterval(30)
        try writeAntigravityNestedToken(
            to: file,
            accessToken: "ya29.account-b",
            refreshToken: nil,
            expiry: formatter.string(from: nearExpiryDate)
        )

        // 3. Cache must NOT fall back to Account A; it must return Account B.
        let second = try await cache.accessToken(allowKeychainPrompt: false)
        XCTAssertEqual(
            second, "ya29.account-b",
            "Near-expiry account switch in file must return new account token, not previous account's cache"
        )
        XCTAssertEqual(KeychainReader.queryCount, 0)
    }

    func testExpiredFileRefreshesAndSubsequentPollRetainsRefreshedToken() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockOAuthURLProtocol.self]
        let session = URLSession(configuration: config)

        MockOAuthURLProtocol.reset()
        MockOAuthURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url, AntigravityRateLimitsProvider.googleTokenURL)
            let bodyData = MockOAuthURLProtocol.extractBodyData(from: request)
            let bodyString = bodyData.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            XCTAssertTrue(bodyString.contains("grant_type=refresh_token"))
            XCTAssertTrue(bodyString.contains("refresh_token=1%2F%2Frefresh-test"))
            XCTAssertTrue(bodyString.contains("client_id=\(AntigravityRateLimitsProvider.googleClientID)"))
            XCTAssertTrue(bodyString.contains("client_secret=\(AntigravityRateLimitsProvider.googleClientSecret)"))

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let json = """
            {
                "access_token": "ya29.refreshed-token",
                "expires_in": 3600,
                "token_type": "Bearer"
            }
            """
            return (response, Data(json.utf8))
        }

        let file = tempDir.appendingPathComponent("jetski-standalone-oauth-token")
        // Expired token in file (e.g. expired in 2020) with valid refresh_token
        try writeAntigravityNestedToken(
            to: file,
            accessToken: "ya29.initial-expired",
            refreshToken: "1//refresh-test",
            expiry: "2020-01-01T00:00:00Z"
        )

        let cache = AntigravityTokenCache(tokenFileURLs: [file], urlSession: session)

        // 1st poll: expired file triggers HTTP refresh -> receives refreshed token
        let first = try await cache.accessToken(allowKeychainPrompt: false)
        XCTAssertEqual(first, "ya29.refreshed-token")
        XCTAssertEqual(MockOAuthURLProtocol.requestCount, 1)

        // 2nd poll: disk file still contains expired initial token, but cache retains refreshed token without extra network call
        let second = try await cache.accessToken(allowKeychainPrompt: false)
        XCTAssertEqual(second, "ya29.refreshed-token")
        XCTAssertEqual(
            MockOAuthURLProtocol.requestCount, 1,
            "Subsequent poll with matching source credential must retain refreshed cache without extra HTTP call"
        )
        XCTAssertEqual(KeychainReader.queryCount, 0)
    }

    func testExpiredFileRefreshFailsReturnsOriginalToken() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockOAuthURLProtocol.self]
        let session = URLSession(configuration: config)

        MockOAuthURLProtocol.reset()
        MockOAuthURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 400,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let json = "{\"error\": \"invalid_grant\"}"
            return (response, Data(json.utf8))
        }

        let file = tempDir.appendingPathComponent("jetski-standalone-oauth-token")
        try writeAntigravityNestedToken(
            to: file,
            accessToken: "ya29.original-token",
            refreshToken: "1//refresh-fail",
            expiry: "2020-01-01T00:00:00Z"
        )

        let cache = AntigravityTokenCache(tokenFileURLs: [file], urlSession: session)
        let token = try await cache.accessToken(allowKeychainPrompt: false)
        XCTAssertEqual(token, "ya29.original-token")
        XCTAssertEqual(MockOAuthURLProtocol.requestCount, 1)
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

    private func writeAntigravityNestedToken(
        to url: URL,
        accessToken: String,
        refreshToken: String? = nil,
        expiry: String? = nil
    ) throws {
        var tokenDict: [String: Any] = [
            "access_token": accessToken,
            "token_type": "Bearer"
        ]
        if let refreshToken { tokenDict["refresh_token"] = refreshToken }
        if let expiry { tokenDict["expiry"] = expiry }
        let root: [String: Any] = [
            "auth_method": "oauth",
            "token": tokenDict
        ]
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted])
        try data.write(to: url, options: .atomic)
    }
}

final class MockOAuthURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) static var requestCount = 0

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        Self.requestCount += 1
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    static func reset() {
        requestHandler = nil
        requestCount = 0
    }

    static func extractBodyData(from request: URLRequest) -> Data? {
        if let data = request.httpBody {
            return data
        }
        guard let stream = request.httpBodyStream else {
            return nil
        }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let bytesRead = stream.read(buffer, maxLength: bufferSize)
            if bytesRead <= 0 { break }
            data.append(buffer, count: bytesRead)
        }
        return data
    }
}
