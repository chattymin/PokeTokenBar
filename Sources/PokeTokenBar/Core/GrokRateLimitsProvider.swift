import Foundation

/// Grok subscription credit limits (the Grok CLI `/usage` → Usage limit tab).
public protocol GrokLimitsProviding: Sendable {
    func fetch() async throws -> GrokCreditStatus?
}

/// The billing endpoint the Grok CLI reads for `/usage`. It is not documented, so any failure only
/// hides the limits section; local Grok usage is unaffected. Authenticates with the access token the
/// Grok CLI keeps in `$GROK_HOME/auth.json`. The token lives for hours and only the CLI refreshes it —
/// the app never rotates the CLI's refresh token — so a rejected token asks the user to run Grok once.
public struct GrokRateLimitsProvider: GrokLimitsProviding, Sendable {
    public static let usageURL = URL(string: "https://cli-chat-proxy.grok.com/v1/billing?format=credits")!

    typealias Transport = @Sendable (URLRequest) async throws -> (Data, Int)?

    nonisolated(unsafe) static var transportForTesting: Transport?

    private let accessToken: @Sendable () -> String?

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.timeoutIntervalForRequest = 10
        return URLSession(configuration: config)
    }()

    public init() {
        self.init(accessToken: { Self.accessToken(authFile: LocalUsageReader.grokAuthFile) })
    }

    init(accessToken: @escaping @Sendable () -> String?) {
        self.accessToken = accessToken
    }

    /// nil = no Grok CLI login on this machine.
    public func fetch() async throws -> GrokCreditStatus? {
        guard let token = accessToken() else {
            AppLog.writeIfChanged("grok-limits-token", "grok limits: no grok login")
            return nil
        }

        var request = URLRequest(url: Self.usageURL, timeoutInterval: 10)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let send = Self.transportForTesting ?? Self.perform
        guard let (data, status) = try await send(request) else {
            throw LimitsError.httpStatus(0)
        }
        if status == 429 {
            throw LimitsError.rateLimited(retryAfter: nil)
        }
        guard (200 ... 299).contains(status) else {
            AppLog.write("grok limits: http \(status)")
            throw LimitsError.httpStatus(status)
        }
        return try JSONDecoder().decode(GrokCreditStatus.self, from: data)
    }

    /// `auth.json` maps `<issuer>::<user>` to a login; `key` is its access token. With several logins
    /// the one that expires last is the one the CLI refreshed most recently.
    static func accessToken(authFile: URL) -> String? {
        guard let data = try? Data(contentsOf: authFile),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        let logins: [(key: String, expires: Date)] = object.values.compactMap { value in
            guard let login = value as? [String: Any],
                  let key = (login["key"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !key.isEmpty else { return nil }
            let expires = (login["expires_at"] as? String).flatMap(ISO8601Parser.date(from:)) ?? .distantPast
            return (key, expires)
        }
        return logins.max { $0.expires < $1.expires }?.key
    }

    private static func perform(_ request: URLRequest) async throws -> (Data, Int)? {
        guard AppEnv.allowsLiveLimitsFetch else { throw LimitsError.liveFetchNotPermitted }
        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            return (data, status)
        } catch {
            AppLog.write("grok limits: error \(error.localizedDescription)")
            return nil
        }
    }
}
