import Foundation

/// Shared Cursor login for dashboard cookies and API2 Bearer requests. Refreshed tokens stay in
/// memory; Cursor owns its SQLite login. A changed login/root invalidates the refreshed credential.
enum CursorAuthentication {
    struct Source: Equatable, Sendable {
        let root: String? // nil identifies an explicit, non-refreshable environment override.
        let accessToken: String
        let refreshToken: String?
    }

    struct Credential: Sendable {
        let source: Source
        let accessToken: String
        let refreshToken: String?
    }

    struct TestConfiguration {
        var environment: [String: String] = [:]
        var roots: [URL] = []
    }

    typealias Transport = @Sendable (URLRequest) async -> (Data, Int)?
    nonisolated(unsafe) static var configurationForTesting: TestConfiguration?
    nonisolated(unsafe) static var transportForTesting: Transport?
    nonisolated(unsafe) private static var refreshedCredential: Credential?
    private static let lock = NSLock()
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.timeoutIntervalForRequest = 10
        return URLSession(configuration: config)
    }()

    static var isEnabled: Bool { environmentValue("CURSOR_USAGE_API") != "0" }
    static var roots: [URL] { configurationForTesting?.roots ?? LocalAdditionalUsageReader.configuredCursorRoots }

    private static func environmentValue(_ name: String) -> String? {
        if let configurationForTesting { return configurationForTesting.environment[name] }
        return UsageEnvironment.value(name)
    }

    private static func selectedSource() -> Source? {
        if let token = environmentValue("CURSOR_SESSION_TOKEN")?
            .trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            return Source(root: nil, accessToken: token, refreshToken: nil)
        }
        for root in roots {
            guard let accessToken = LocalAdditionalUsageReader.cursorAuthAccessToken(roots: [root]) else { continue }
            // Never combine Stable's access token with Nightly's (or another custom root's) refresh.
            let refreshToken = LocalAdditionalUsageReader.cursorAuthValue("cursorAuth/refreshToken", roots: [root])
            return Source(root: root.standardizedFileURL.path, accessToken: accessToken, refreshToken: refreshToken)
        }
        return nil
    }

    static func current() -> Credential? {
        let source = selectedSource()
        lock.lock()
        defer { lock.unlock() }
        guard let source else {
            refreshedCredential = nil
            return nil
        }
        if let refreshedCredential, refreshedCredential.source == source { return refreshedCredential }
        refreshedCredential = nil
        return Credential(source: source, accessToken: source.accessToken, refreshToken: source.refreshToken)
    }

    /// Refresh only the selected local login, once per rejected request. A rejected refreshed JWT
    /// may be refreshed again later; a transient grant failure leaves its refresh token available.
    static func refresh(afterRejecting rejected: Credential) async -> Credential? {
        guard rejected.source.root != nil,
              let current = current(), current.source == rejected.source else { return nil }
        if current.accessToken != rejected.accessToken { return current }
        guard let refreshToken = current.refreshToken else { return nil }

        var request = URLRequest(url: CursorRateLimitsProvider.tokenURL, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "grant_type": "refresh_token",
            "client_id": CursorRateLimitsProvider.clientID,
            "refresh_token": refreshToken,
        ])
        let send = transportForTesting ?? perform
        guard let (data, status) = await send(request), (200 ... 299).contains(status),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["shouldLogout"] as? Bool != true,
              let accessToken = (object["access_token"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !accessToken.isEmpty else {
            AppLog.write("cursor auth: token refresh failed")
            return nil
        }
        let replacement = (object["refresh_token"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let refreshed = Credential(
            source: rejected.source, accessToken: accessToken,
            refreshToken: replacement.flatMap { $0.isEmpty ? nil : $0 } ?? refreshToken)
        // A logout/root/account change while the request was pending must not restore the old login.
        guard selectedSource() == rejected.source else { return nil }
        lock.withLock { refreshedCredential = refreshed }
        return refreshed
    }

    static func bearerToken(from token: String) -> String {
        let decoded = token.removingPercentEncoding ?? token
        if let separator = decoded.range(of: "::") { return String(decoded[separator.upperBound...]) }
        return decoded
    }

    static func sessionCookie(from token: String) -> String {
        let decoded = token.removingPercentEncoding ?? token
        if decoded.contains("::") { return token }
        if let subject = CursorUsageAPI.jwtSubject(decoded) { return "\(subject)::\(decoded)" }
        return token
    }

    static func resetForTesting() {
        lock.lock()
        refreshedCredential = nil
        lock.unlock()
    }

    private static func perform(_ request: URLRequest) async -> (Data, Int)? {
        guard AppEnv.allowsLiveLimitsFetch else { return nil }
        do {
            let (data, response) = try await session.data(for: request)
            return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
        } catch {
            AppLog.write("cursor auth: token refresh transport failed")
            return nil
        }
    }
}
