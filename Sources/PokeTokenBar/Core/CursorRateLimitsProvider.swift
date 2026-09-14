import Foundation

/// Cursor 공식 한도(월간 포함 allowance) 조회 추상화.
public protocol CursorLimitsProviding: Sendable {
    func fetch() async throws -> CursorRateLimitStatus?
}

/// Cursor dashboard Connect RPC — `GetCurrentPeriodUsage` on `api2.cursor.sh`.
/// Uses the same local Cursor login as `CursorUsageAPI` (Bearer JWT from `state.vscdb`).
public struct CursorRateLimitsProvider: CursorLimitsProviding, Sendable {
    public static let usageURL = URL(
        string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage")!
    public static let tokenURL = URL(string: "https://api2.cursor.sh/oauth/token")!
    public static let clientID = "KbZUR41cY7W6zRSdpSUJ7I7mLYBKOCmB"

    typealias Transport = @Sendable (URLRequest) async -> (Data, Int)?

    nonisolated(unsafe) static var transportForTesting: Transport?

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.timeoutIntervalForRequest = 10
        return URLSession(configuration: config)
    }()

    public init() {}

    public func fetch() async throws -> CursorRateLimitStatus? {
        guard UsageEnvironment.value("CURSOR_USAGE_API") != "0" else { return nil }
        guard var token = CursorUsageAPI.sessionToken() else {
            AppLog.write("cursor limits: no session token")
            return nil
        }

        do {
            return try await fetchStatus(token: token)
        } catch let error as LimitsError {
            guard case .httpStatus(let code) = error, code == 401 || code == 403 else { throw error }
            guard let refreshed = try await Self.refreshAccessToken() else { throw error }
            token = refreshed
            return try await fetchStatus(token: token)
        }
    }

    private func fetchStatus(token: String) async throws -> CursorRateLimitStatus {
        var request = URLRequest(url: Self.usageURL, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let send = Self.transportForTesting ?? Self.perform
        guard let (data, status) = await send(request) else {
            throw LimitsError.httpStatus(0)
        }
        if status == 429 {
            throw LimitsError.rateLimited(retryAfter: nil)
        }
        guard (200 ... 299).contains(status) else {
            let preview = String(data: data.prefix(120), encoding: .utf8)?
                .replacingOccurrences(of: "\n", with: " ") ?? ""
            AppLog.write("cursor limits: http \(status) \(preview)")
            throw LimitsError.httpStatus(status)
        }
        return try JSONDecoder().decode(CursorRateLimitStatus.self, from: data)
    }

    private static func refreshAccessToken() async throws -> String? {
        guard let refreshToken = LocalAdditionalUsageReader.cursorAuthValue("cursorAuth/refreshToken")?
            .trimmingCharacters(in: .whitespacesAndNewlines), !refreshToken.isEmpty else {
            AppLog.write("cursor limits: no refresh token")
            return nil
        }
        var request = URLRequest(url: tokenURL, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: String] = [
            "grant_type": "refresh_token",
            "client_id": clientID,
            "refresh_token": refreshToken,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let send = transportForTesting ?? perform
        guard let (data, status) = await send(request), (200 ... 299).contains(status),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = object["access_token"] as? String,
              !accessToken.isEmpty else {
            AppLog.write("cursor limits: token refresh failed")
            return nil
        }
        if object["shouldLogout"] as? Bool == true { return nil }
        return accessToken
    }

    private static func perform(_ request: URLRequest) async -> (Data, Int)? {
        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            return (data, status)
        } catch {
            AppLog.write("cursor limits: \(request.url?.absoluteString ?? "?") error \(error.localizedDescription)")
            return nil
        }
    }
}
