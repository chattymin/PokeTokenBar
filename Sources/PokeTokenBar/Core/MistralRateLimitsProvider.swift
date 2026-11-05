import Foundation
#if os(macOS)
import Security
#endif

/// Mistral subscription allowances: the monthly included Vibe and API budgets that
/// admin.mistral.ai → Subscription shows, plus the plan name.
public protocol MistralLimitsProviding: Sendable {
    /// `allowKeychainPrompt` is true only for a user action. The automatic path never reads the
    /// Keychain (`KeychainReader` contract) and answers from the environment, Vibe's `.env`, or a
    /// key a user action already loaded. nil = no Mistral key is reachable.
    func fetch(allowKeychainPrompt: Bool) async throws -> MistralBudgetStatus?
}

/// Reads `GET api.mistral.ai/v1/billing/budget` with the Mistral API key Mistral Vibe uses. The
/// endpoint is not documented, so any failure only hides the limits section; local Vibe usage is
/// unaffected. The plan comes from `console.mistral.ai/api/vibe/whoami`, the lookup Vibe itself
/// makes, and is best effort: without it the budgets still show.
public struct MistralRateLimitsProvider: MistralLimitsProviding, Sendable {
    public static let budgetURL = URL(string: "https://api.mistral.ai/v1/billing/budget")!
    public static let whoamiURL = URL(string: "https://console.mistral.ai/api/vibe/whoami")!

    typealias Transport = @Sendable (URLRequest) async throws -> (Data, Int)?

    nonisolated(unsafe) static var transportForTesting: Transport?

    private let keys: MistralKeyCache

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.timeoutIntervalForRequest = 10
        return URLSession(configuration: config)
    }()

    public init() {
        self.init(keys: .shared)
    }

    init(keys: MistralKeyCache) {
        self.keys = keys
    }

    public func fetch(allowKeychainPrompt: Bool) async throws -> MistralBudgetStatus? {
        guard let key = try await keys.apiKey(allowKeychainPrompt: allowKeychainPrompt) else {
            AppLog.writeIfChanged("mistral-limits-key", "mistral limits: no mistral api key")
            return nil
        }

        let send = Self.transportForTesting ?? Self.perform
        guard let (data, status) = try await send(Self.request(Self.budgetURL, key: key)) else {
            throw LimitsError.httpStatus(0)
        }
        if status == 429 {
            throw LimitsError.rateLimited(retryAfter: nil)
        }
        guard (200 ... 299).contains(status) else {
            AppLog.write("mistral limits: http \(status)")
            throw LimitsError.httpStatus(status)
        }
        var budget = try JSONDecoder().decode(MistralBudgetStatus.self, from: data)
        budget.plan = await plan(key: key, send: send)
        return budget
    }

    /// The plan changes rarely, so it is looked up once per key. Cloudflare sometimes answers the
    /// console host with a challenge page; that decode failure is retried on a later refresh.
    private func plan(key: String, send: Transport) async -> MistralPlan? {
        if let cached = await keys.plan(for: key) { return cached }
        guard let (data, status) = try? await send(Self.request(Self.whoamiURL, key: key)),
              (200 ... 299).contains(status),
              let plan = try? JSONDecoder().decode(MistralPlan.self, from: data) else {
            AppLog.writeIfChanged("mistral-plan", "mistral plan unavailable")
            return nil
        }
        await keys.remember(plan, for: key)
        return plan
    }

    private static func request(_ url: URL, key: String) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private static func perform(_ request: URLRequest) async throws -> (Data, Int)? {
        guard AppEnv.allowsLiveLimitsFetch else { throw LimitsError.liveFetchNotPermitted }
        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            return (data, status)
        } catch {
            AppLog.write("mistral limits: error \(error.localizedDescription)")
            return nil
        }
    }
}

/// Where Mistral Vibe keeps its API key, in Vibe's own order: the `MISTRAL_API_KEY` environment
/// variable, then `$VIBE_HOME/.env`, then the Keychain item Vibe's setup writes. A key read from
/// the Keychain stays in memory so the automatic path keeps refreshing without reading it again.
actor MistralKeyCache {
    static let shared = MistralKeyCache()

    static let environmentName = "MISTRAL_API_KEY"
    /// Vibe 3 writes `ai.mistral.vibe`; earlier releases wrote `vibe`.
    static let keychainServices = ["ai.mistral.vibe", "vibe"]

    private let environmentKey: @Sendable () -> String?
    private let envFiles: @Sendable () -> [URL]
    private var keychainKey: String?
    private var plans: [String: MistralPlan] = [:]

    init(
        environmentKey: @escaping @Sendable () -> String? = { UsageEnvironment.value(MistralKeyCache.environmentName) },
        envFiles: @escaping @Sendable () -> [URL] = { MistralKeyCache.defaultEnvFiles }
    ) {
        self.environmentKey = environmentKey
        self.envFiles = envFiles
    }

    static var defaultEnvFiles: [URL] {
        let homes = UsageEnvironment.value("VIBE_HOME").map { raw in
            raw.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
        } ?? [FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".vibe")]
        return homes.map { $0.appendingPathComponent(".env") }
    }

    func apiKey(allowKeychainPrompt: Bool) throws -> String? {
        if let key = Self.normalized(environmentKey()) { return key }
        for file in envFiles() {
            if let key = Self.envFileValue(Self.environmentName, in: file) { return key }
        }
        guard allowKeychainPrompt else { return keychainKey }
        // A user action re-reads the item, so a key replaced with `vibe --setup` is picked up.
        if let key = try Self.readKeychain() {
            keychainKey = key
            return key
        }
        keychainKey = nil
        return nil
    }

    func plan(for key: String) -> MistralPlan? { plans[key] }

    func remember(_ plan: MistralPlan, for key: String) { plans[key] = plan }

    /// `KEY=value` lines as python-dotenv reads them: optional `export`, optional quotes, `#` comments.
    static func envFileValue(_ name: String, in file: URL) -> String? {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        var found: String?
        for rawLine in text.split(whereSeparator: \.isNewline) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("export ") { line = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces) }
            guard !line.hasPrefix("#"), let equals = line.firstIndex(of: "="),
                  line[..<equals].trimmingCharacters(in: .whitespaces) == name else { continue }
            var value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            if let quote = value.first, quote == "\"" || quote == "'" {
                value.removeFirst()
                if let end = value.firstIndex(of: quote) { value = String(value[..<end]) }
            } else if let comment = value.range(of: " #") {
                value = String(value[..<comment.lowerBound])
            }
            // The last assignment wins, as in a shell.
            found = normalized(value) ?? found
        }
        return found
    }

    private static func normalized(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// Silent first: Vibe creates the item for any app (`security add-generic-password -A`), so this
    /// normally succeeds without a dialog. Only an item that needs approval falls back to the prompt.
    private static func readKeychain() throws -> String? {
        #if os(macOS)
        if KeychainAccessGate.isDisabled { throw LimitsError.keychainAccessDisabled }
        for service in keychainServices {
            if let key = try? copyPassword(service: service, allowPrompt: false) { return key }
        }
        for service in keychainServices {
            if let key = try copyPassword(service: service, allowPrompt: true) { return key }
        }
        #endif
        return nil
    }

    #if os(macOS)
    /// nil = no such item. Throws when the item exists but could not be read.
    private static func copyPassword(service: String, allowPrompt: Bool) throws -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: environmentName,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        if !allowPrompt { KeychainNoUIQuery.apply(to: &query) }
        var item: CFTypeRef?
        let status = KeychainReader.copyMatching(query, &item)
        if status == errSecItemNotFound { return nil }
        if status == errSecInteractionNotAllowed { throw LimitsError.keychainInteractionNotAllowed }
        guard status == errSecSuccess, let data = item as? Data else {
            throw LimitsError.keychainUnavailable(status)
        }
        guard let key = normalized(String(data: data, encoding: .utf8)) else { throw LimitsError.credentialFormat }
        return key
    }
    #endif
}
