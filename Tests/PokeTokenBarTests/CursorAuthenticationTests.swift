import SQLite3
import XCTest
@testable import PokeTokenBar

/// Drive both production fetchers with synthetic SQLite logins and injected network boundaries.
final class CursorAuthenticationTests: XCTestCase {
    private var directory: URL!
    private var root: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("CursorAuth-\(UUID().uuidString)")
        root = directory.appendingPathComponent("Stable")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        CursorAuthentication.configurationForTesting = .init(roots: [root])
        CursorAuthentication.resetForTesting()
        CursorUsageAPI.cacheFileURLForTesting = directory.appendingPathComponent("usage-cache.json")
        CursorUsageAPI.resetCacheForTesting()
        // An unexpected request fails locally; no test may fall through to a user's credentials.
        CursorAuthentication.transportForTesting = { _ in XCTFail("unexpected refresh"); return nil }
        CursorUsageAPI.transportForTesting = { _ in XCTFail("unexpected usage request"); return nil }
        CursorRateLimitsProvider.transportForTesting = { _ in XCTFail("unexpected limits request"); return nil }
    }

    override func tearDownWithError() throws {
        CursorAuthentication.configurationForTesting = nil
        CursorAuthentication.transportForTesting = nil
        CursorAuthentication.resetForTesting()
        CursorUsageAPI.transportForTesting = nil
        CursorUsageAPI.cacheFileURLForTesting = nil
        CursorUsageAPI.resetCacheForTesting()
        CursorRateLimitsProvider.transportForTesting = nil
        try FileManager.default.removeItem(at: directory)
        directory = nil
        root = nil
    }

    func testUsageRefreshesExpiredLocalLoginAndSharesItWithLimits() async throws {
        try seed(root, access: "expired", refresh: "refresh-one")
        let calls = CallLog()
        CursorAuthentication.transportForTesting = Self.grantTransport(calls: calls)
        CursorUsageAPI.transportForTesting = { request in
            let header = Self.authHeader(request)
            calls.append(header)
            return header.contains("fresh") ? Self.usageResponse() : (Data(), 401)
        }
        CursorRateLimitsProvider.transportForTesting = { request in
            XCTAssertEqual(Self.authHeader(request), "Bearer fresh")
            return Self.limitsResponse()
        }

        let usage = await fetchUsage()
        let limits = try await CursorRateLimitsProvider().fetch()
        XCTAssertTrue(usage.isAuthoritative)
        XCTAssertEqual(usage.entries.count, 1)
        XCTAssertEqual(limits?.planUsage?.usedPercent, 25)
        XCTAssertEqual(calls.values, ["WorkosCursorSessionToken=expired", "Bearer expired", "grant:refresh-one", "WorkosCursorSessionToken=fresh"])
        XCTAssertEqual(LocalAdditionalUsageReader.cursorAuthAccessToken(roots: [root]), "expired", "Cursor owns its SQLite login")
    }

    func testLimitsRefreshIsSharedWithNextUsageFetch() async throws {
        try seed(root, access: "expired", refresh: "refresh-one")
        let calls = CallLog()
        CursorAuthentication.transportForTesting = Self.grantTransport(calls: calls)
        CursorRateLimitsProvider.transportForTesting = { request in
            let header = Self.authHeader(request)
            calls.append(header)
            return header == "Bearer fresh" ? Self.limitsResponse() : (Data(), 403)
        }
        CursorUsageAPI.transportForTesting = { request in
            XCTAssertEqual(Self.authHeader(request), "WorkosCursorSessionToken=fresh")
            return Self.usageResponse()
        }
        let limits = try await CursorRateLimitsProvider().fetch()
        let usage = await fetchUsage()
        XCTAssertEqual(limits?.planUsage?.usedPercent, 25)
        XCTAssertTrue(usage.isAuthoritative)
        XCTAssertEqual(calls.values, ["Bearer expired", "grant:refresh-one", "Bearer fresh"])
    }

    func testBrowserOverridesPreserveCookieAndNormalizeBothBearerPaths() async throws {
        for token in ["user-test::test-jwt", "user-test%3A%3Atest-jwt", "user-test%3a%3atest-jwt"] {
            CursorAuthentication.configurationForTesting?.environment = ["CURSOR_SESSION_TOKEN": token]
            let calls = CallLog()
            CursorUsageAPI.transportForTesting = { request in
                let header = Self.authHeader(request)
                calls.append(header)
                return header == "Bearer test-jwt" ? Self.usageResponse() : (Data(), 401)
            }
            CursorRateLimitsProvider.transportForTesting = { request in
                XCTAssertEqual(Self.authHeader(request), "Bearer test-jwt")
                return Self.limitsResponse()
            }
            let usage = await fetchUsage()
            let limits = try await CursorRateLimitsProvider().fetch()
            XCTAssertTrue(usage.isAuthoritative)
            XCTAssertNotNil(limits)
            XCTAssertEqual(calls.values, ["WorkosCursorSessionToken=\(token)", "Bearer test-jwt"])
        }
    }

    func testRejectedOverrideNeverRefreshesUnrelatedLocalLogin() async throws {
        try seed(root, access: "local-account", refresh: "local-refresh")
        CursorAuthentication.configurationForTesting?.environment = ["CURSOR_SESSION_TOKEN": "other-account::override-jwt"]
        CursorUsageAPI.transportForTesting = { _ in (Data(), 401) }
        CursorRateLimitsProvider.transportForTesting = { _ in (Data(), 403) }
        let usage = await fetchUsage()
        XCTAssertFalse(usage.isAuthoritative)
        await assertLimitsError(403)
        XCTAssertEqual(CursorUsageAPI.sessionToken(), "other-account::override-jwt")
    }

    func testRefreshTokenMustBelongToSelectedDatabaseRoot() async throws {
        try seed(root, access: "stable-account", refresh: nil)
        let nightly = directory.appendingPathComponent("Nightly")
        try seed(nightly, access: "nightly-account", refresh: "nightly-refresh")
        CursorAuthentication.configurationForTesting?.roots = [root, nightly]
        CursorRateLimitsProvider.transportForTesting = { request in
            XCTAssertEqual(Self.authHeader(request), "Bearer stable-account")
            return (Data(), 401)
        }
        await assertLimitsError(401)
    }

    func testRefreshedCredentialInvalidatesForChangedRootAccessRefreshOverrideAndLogout() async throws {
        try seed(root, access: "old", refresh: "refresh-one")
        let other = directory.appendingPathComponent("Other")
        try seed(other, access: "old", refresh: "refresh-one")
        CursorAuthentication.transportForTesting = Self.grantTransport(calls: CallLog())
        CursorRateLimitsProvider.transportForTesting = { request in
            Self.authHeader(request) == "Bearer fresh" ? Self.limitsResponse() : (Data(), 401)
        }

        _ = try await CursorRateLimitsProvider().fetch()
        XCTAssertEqual(CursorUsageAPI.sessionToken(), "fresh")
        CursorAuthentication.configurationForTesting?.roots = [other]
        XCTAssertEqual(CursorUsageAPI.sessionToken(), "old", "same token in another root is another selection")
        _ = try await CursorRateLimitsProvider().fetch()
        try seed(other, access: "changed-account", refresh: "refresh-one")
        XCTAssertEqual(CursorUsageAPI.sessionToken(), "changed-account")
        _ = try await CursorRateLimitsProvider().fetch()
        try seed(other, access: "changed-account", refresh: "refresh-two")
        XCTAssertEqual(CursorUsageAPI.sessionToken(), "changed-account", "refresh-token changes also invalidate")
        _ = try await CursorRateLimitsProvider().fetch()
        CursorAuthentication.configurationForTesting?.environment = ["CURSOR_SESSION_TOKEN": "override"]
        XCTAssertEqual(CursorUsageAPI.sessionToken(), "override")
        CursorAuthentication.configurationForTesting?.environment = [:]
        XCTAssertEqual(CursorUsageAPI.sessionToken(), "changed-account", "returning from override must not resurrect fresh state")
        _ = try await CursorRateLimitsProvider().fetch()
        try seed(other, access: nil, refresh: nil)
        XCTAssertNil(CursorUsageAPI.sessionToken())
        try seed(other, access: "changed-account", refresh: "refresh-two")
        XCTAssertEqual(CursorUsageAPI.sessionToken(), "changed-account", "logout discards refreshed state")
    }

    func testRejectedRefreshedTokenCanRefreshAgainUsingRotatedRefreshToken() async throws {
        try seed(root, access: "expired", refresh: "refresh-one")
        let grants = CallLog()
        CursorAuthentication.transportForTesting = { request in
            let body = try! JSONSerialization.jsonObject(with: request.httpBody!) as! [String: String]
            grants.append(body["refresh_token"]!)
            let access = body["refresh_token"] == "refresh-one" ? "first-fresh" : "second-fresh"
            return (Data("{\"access_token\":\"\(access)\",\"refresh_token\":\"refresh-two\"}".utf8), 200)
        }
        CursorRateLimitsProvider.transportForTesting = { request in
            Self.authHeader(request) == "Bearer expired" ? (Data(), 401) : Self.limitsResponse()
        }
        _ = try await CursorRateLimitsProvider().fetch()
        CursorRateLimitsProvider.transportForTesting = { request in
            Self.authHeader(request) == "Bearer second-fresh" ? Self.limitsResponse() : (Data(), 401)
        }
        _ = try await CursorRateLimitsProvider().fetch()
        XCTAssertEqual(grants.values, ["refresh-one", "refresh-two"])
        XCTAssertEqual(CursorUsageAPI.sessionToken(), "second-fresh")
        XCTAssertEqual(LocalAdditionalUsageReader.cursorAuthValue("cursorAuth/refreshToken", roots: [root]), "refresh-one")
    }

    func testEmptyReplacementRefreshTokenKeepsOriginalForNextGrant() async throws {
        try seed(root, access: "expired", refresh: "refresh-one")
        let calls = CallLog()
        CursorAuthentication.transportForTesting = { request in
            let body = try! JSONSerialization.jsonObject(with: request.httpBody!) as! [String: String]
            calls.append(body["refresh_token"]!)
            return (Data(#"{"access_token":"fresh","refresh_token":"  "}"#.utf8), 200)
        }
        CursorRateLimitsProvider.transportForTesting = { _ in (Data(), 401) }
        await assertLimitsError(401)
        await assertLimitsError(401)
        XCTAssertEqual(calls.values, ["refresh-one", "refresh-one"])
    }

    func testAlreadyRefreshedRejectedCredentialReusesSharedTokenUntilSourceChanges() async throws {
        try seed(root, access: "expired", refresh: "refresh-one")
        let rejected = try XCTUnwrap(CursorAuthentication.current())
        let calls = CallLog()
        CursorAuthentication.transportForTesting = Self.grantTransport(calls: calls)
        CursorRateLimitsProvider.transportForTesting = { request in
            Self.authHeader(request) == "Bearer fresh" ? Self.limitsResponse() : (Data(), 401)
        }
        _ = try await CursorRateLimitsProvider().fetch()
        let shared = await CursorAuthentication.refresh(afterRejecting: rejected)
        XCTAssertEqual(shared?.accessToken, "fresh")
        XCTAssertEqual(calls.values, ["grant:refresh-one"])
        CursorAuthentication.configurationForTesting?.environment = ["CURSOR_SESSION_TOKEN": "other-account"]
        let obsolete = await CursorAuthentication.refresh(afterRejecting: rejected)
        XCTAssertNil(obsolete)
        XCTAssertEqual(calls.values, ["grant:refresh-one"])
    }

    func testFailedGrantPreservesCredentialForNextAutomaticAttempt() async throws {
        let failures: [(Data, Int)?] = [nil, (Data(), 503), (Data("invalid-json".utf8), 200),
            (Data(#"{"access_token":"","refresh_token":"ignored"}"#.utf8), 200),
            (Data(#"{"access_token":"ignored","shouldLogout":true}"#.utf8), 200)]
        for failure in failures {
            CursorAuthentication.resetForTesting()
            try seed(root, access: "expired", refresh: "refresh-one")
            CursorAuthentication.transportForTesting = { _ in failure }
            CursorRateLimitsProvider.transportForTesting = { request in
                Self.authHeader(request) == "Bearer fresh" ? Self.limitsResponse() : (Data(), 401)
            }
            await assertLimitsError(401)
            XCTAssertEqual(CursorUsageAPI.sessionToken(), "expired")
            CursorAuthentication.transportForTesting = Self.grantTransport(calls: CallLog())
            let recovered = try await CursorRateLimitsProvider().fetch()
            XCTAssertNotNil(recovered)
        }
    }

    func testNonAuthFailuresNeverRefresh() async throws {
        try seed(root, access: "valid", refresh: "refresh-one")
        let responses: [(Data, Int)?] = [nil, (Data(), 429), (Data(), 500), (Data("invalid-json".utf8), 200)]
        for response in responses {
            CursorUsageAPI.transportForTesting = { _ in response }
            CursorRateLimitsProvider.transportForTesting = { _ in response }
            let usage = await fetchUsage()
            XCTAssertFalse(usage.isAuthoritative)
            do {
                _ = try await CursorRateLimitsProvider().fetch()
                XCTFail("expected failure")
            } catch { /* original error is retained; the unexpected-refresh stub must remain unused */ }
        }
    }

    func testRefreshedRejectionIsBoundedToOneGrantPerFetch() async throws {
        try seed(root, access: "expired", refresh: "refresh-one")
        let calls = CallLog()
        CursorAuthentication.transportForTesting = Self.grantTransport(calls: calls)
        CursorUsageAPI.transportForTesting = { _ in (Data(), 403) }
        let usage = await fetchUsage()
        XCTAssertFalse(usage.isAuthoritative)
        XCTAssertEqual(calls.values, ["grant:refresh-one"])
        CursorRateLimitsProvider.transportForTesting = { _ in (Data(), 401) }
        await assertLimitsError(401)
        XCTAssertEqual(calls.values, ["grant:refresh-one", "grant:refresh-one"])
    }

    func testDisabledAndMissingLoginSkipNetwork() async throws {
        CursorAuthentication.configurationForTesting?.environment = ["CURSOR_USAGE_API": "0"]
        let disabledUsage = await fetchUsage()
        XCTAssertFalse(disabledUsage.isAuthoritative)
        let disabled = try await CursorRateLimitsProvider().fetch()
        XCTAssertNil(disabled)
        CursorAuthentication.configurationForTesting?.environment = ["CURSOR_SESSION_TOKEN": "  "]
        let missingUsage = await fetchUsage()
        XCTAssertFalse(missingUsage.isAuthoritative)
        let missing = try await CursorRateLimitsProvider().fetch()
        XCTAssertNil(missing)
    }

    func testLiveRefreshBoundaryStaysClosedUnderSwiftTest() async throws {
        if AppEnv.allowsLiveLimitsFetch { throw XCTSkip("live limits fetch explicitly enabled") }
        try seed(root, access: "expired", refresh: "synthetic-refresh")
        CursorAuthentication.transportForTesting = nil
        CursorRateLimitsProvider.transportForTesting = { _ in (Data(), 401) }
        await assertLimitsError(401)
    }

    func testPendingGrantCannotRestoreChangedLogin() async throws {
        try seed(root, access: "expired", refresh: "refresh-one")
        let changedRoot = directory.appendingPathComponent("Changed")
        try seed(changedRoot, access: "other-account", refresh: "other-refresh")
        CursorAuthentication.transportForTesting = { _ in
            CursorAuthentication.configurationForTesting?.roots = [changedRoot]
            return (Data(#"{"access_token":"old-account-fresh"}"#.utf8), 200)
        }
        CursorRateLimitsProvider.transportForTesting = { _ in (Data(), 401) }
        await assertLimitsError(401)
        XCTAssertEqual(CursorUsageAPI.sessionToken(), "other-account")
    }

    private func fetchUsage() async -> CursorUsageAPI.UsageResult {
        await CursorUsageAPI.fetchEntries(modifiedSince: Date().addingTimeInterval(-3600))
    }

    private func assertLimitsError(_ expected: Int, file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await CursorRateLimitsProvider().fetch()
            XCTFail("expected HTTP \(expected)", file: file, line: line)
        } catch LimitsError.httpStatus(let code) {
            XCTAssertEqual(code, expected, file: file, line: line)
        } catch {
            XCTFail("unexpected error: \(error)", file: file, line: line)
        }
    }

    private func seed(_ root: URL, access: String?, refresh: String?) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(root.appendingPathComponent("state.vscdb").path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        XCTAssertEqual(sqlite3_exec(db, "CREATE TABLE IF NOT EXISTS ItemTable (key TEXT UNIQUE, value BLOB); DELETE FROM ItemTable;", nil, nil, nil), SQLITE_OK)
        for (key, value) in [("cursorAuth/accessToken", access), ("cursorAuth/refreshToken", refresh)] {
            guard let value else { continue }
            XCTAssertEqual(sqlite3_exec(db, "INSERT INTO ItemTable VALUES ('\(key)', '\(value)');", nil, nil, nil), SQLITE_OK)
        }
    }

    private static func authHeader(_ request: URLRequest) -> String {
        request.value(forHTTPHeaderField: "Authorization") ?? request.value(forHTTPHeaderField: "Cookie") ?? ""
    }

    private static func grantTransport(calls: CallLog) -> CursorAuthentication.Transport {
        { request in
            XCTAssertEqual(request.url, CursorRateLimitsProvider.tokenURL)
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            let body = try! JSONSerialization.jsonObject(with: request.httpBody!) as! [String: String]
            XCTAssertEqual(body["grant_type"], "refresh_token")
            XCTAssertEqual(body["client_id"], CursorRateLimitsProvider.clientID)
            calls.append("grant:\(body["refresh_token"]!)")
            return (Data(#"{"access_token":"fresh"}"#.utf8), 200)
        }
    }

    private static func usageResponse() -> (Data, Int) {
        let event: [String: Any] = [
            "timestamp": String(Int64(Date().timeIntervalSince1970 * 1000)),
            "id": "synthetic-usage", "model": "test-model",
            "tokenUsage": ["inputTokens": 100, "outputTokens": 50],
        ]
        return (try! JSONSerialization.data(withJSONObject: ["usageEventsDisplay": [event], "totalUsageEventsCount": 1]), 200)
    }

    private static func limitsResponse() -> (Data, Int) {
        (Data(#"{"planUsage":{"remaining":1500,"limit":2000,"totalPercentUsed":25}}"#.utf8), 200)
    }
}

private final class CallLog: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String] = []
    func append(_ value: String) { lock.withLock { stored.append(value) } }
    var values: [String] { lock.withLock { stored } }
}
