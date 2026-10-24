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
        guard CursorAuthentication.isEnabled else { return nil }
        guard let credential = CursorAuthentication.current() else {
            AppLog.writeIfChanged("cursor-limits-session", "cursor limits: no session token")
            return nil
        }

        do {
            return try await fetchStatus(token: credential.accessToken)
        } catch let error as LimitsError {
            guard case .httpStatus(let code) = error, code == 401 || code == 403 else { throw error }
            guard let refreshed = await CursorAuthentication.refresh(afterRejecting: credential) else { throw error }
            return try await fetchStatus(token: refreshed.accessToken)
        }
    }

    private func fetchStatus(token: String) async throws -> CursorRateLimitStatus {
        var request = URLRequest(url: Self.usageURL, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.setValue("Bearer \(CursorAuthentication.bearerToken(from: token))", forHTTPHeaderField: "Authorization")

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

    private static func perform(_ request: URLRequest) async -> (Data, Int)? {
        // Limits network boundary; token grants are gated separately in CursorAuthentication.
        guard AppEnv.allowsLiveLimitsFetch else { return nil }
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
