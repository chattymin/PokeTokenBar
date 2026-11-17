import Foundation

/// OpenCode Go subscription limits (rolling 5h / weekly / monthly allowance).
public protocol OpenCodeGoLimitsProviding: Sendable {
    func fetch() async throws -> OpenCodeGoRateLimitStatus?
}

/// The endpoint the opencode.ai console reads. It is not documented, so any failure only hides the
/// limits section; local OpenCode usage is unaffected. Authenticates with the Go API key OpenCode
/// already stores locally (`LocalAdditionalUsageReader.openCodeAPIKey`).
public struct OpenCodeGoRateLimitsProvider: OpenCodeGoLimitsProviding, Sendable {
    public static let usageURL = URL(string: "https://opencode.ai/zen/go/v1/usage")!
    static let integrationID = "opencode-go"

    typealias Transport = @Sendable (URLRequest) async throws -> (Data, Int)?

    nonisolated(unsafe) static var transportForTesting: Transport?

    private let apiKey: @Sendable () -> String?

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.timeoutIntervalForRequest = 10
        return URLSession(configuration: config)
    }()

    public init() {
        self.init(apiKey: { LocalAdditionalUsageReader.openCodeAPIKey(integrationID: Self.integrationID) })
    }

    init(apiKey: @escaping @Sendable () -> String?) {
        self.apiKey = apiKey
    }

    /// nil = no OpenCode Go key on this machine (not a Go subscriber).
    public func fetch() async throws -> OpenCodeGoRateLimitStatus? {
        guard let key = apiKey() else {
            AppLog.writeIfChanged("opencode-go-limits-key", "opencode go limits: no api key")
            return nil
        }

        var request = URLRequest(url: Self.usageURL, timeoutInterval: 10)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let send = Self.transportForTesting ?? Self.perform
        guard let (data, status) = try await send(request) else {
            throw LimitsError.httpStatus(0)
        }
        if status == 429 {
            throw LimitsError.rateLimited(retryAfter: nil)
        }
        guard (200 ... 299).contains(status) else {
            AppLog.write("opencode go limits: http \(status)")
            throw LimitsError.httpStatus(status)
        }
        return try JSONDecoder().decode(OpenCodeGoRateLimitStatus.self, from: data)
    }

    private static func perform(_ request: URLRequest) async throws -> (Data, Int)? {
        guard AppEnv.allowsLiveLimitsFetch else { throw LimitsError.liveFetchNotPermitted }
        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            return (data, status)
        } catch {
            AppLog.write("opencode go limits: error \(error.localizedDescription)")
            return nil
        }
    }
}
