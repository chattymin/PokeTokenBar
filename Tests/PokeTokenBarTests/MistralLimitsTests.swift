import XCTest
@testable import PokeTokenBar

/// Mistral budgets with an injected transport and Keychain; nothing here reads the real key.
final class MistralLimitsTests: XCTestCase, @unchecked Sendable {
    private var temporaryDirectory: URL!
    private var savedGate = false

    /// The response `api.mistral.ai/v1/billing/budget` returned for a Pro (Education) plan.
    private let budgetJSON = #"""
    {"vibe_budget":{"usage_percentage":8.106912566666667,"initial_budget":150.0,"currency":"USD",
    "reset_at":"2026-12-01T00:00:00Z","payg_enabled":false},
    "api_budget":{"usage_percentage":0.4943100266666667,"initial_budget":15.0,"currency":"USD",
    "reset_at":"2026-12-01T00:00:00Z","payg_enabled":false},
    "usage_percentage":0.4943100266666667,"initial_budget":15.0,"currency":"USD","reset_at":"2026-12-01T00:00:00Z"}
    """#
    private let whoamiJSON = #"""
    {"plan_type":"CHAT","plan_name":"EDU","prompt_switching_to_pro_plan":false,"organization_kind":"S",
    "api_base":"https://api.mistral.ai","vibe_base":"https://chat.mistral.ai"}
    """#

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PokeTokenBar-MistralLimitsTests-\(UUID())")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        savedGate = KeychainAccessGate.isDisabled
        KeychainAccessGate.isDisabled = false
        KeychainReader.resetQueryCountForTesting()
    }

    override func tearDownWithError() throws {
        MistralRateLimitsProvider.transportForTesting = nil
        KeychainReader.copyMatchingForTesting = nil
        KeychainAccessGate.isDisabled = savedGate
        try FileManager.default.removeItem(at: temporaryDirectory)
    }

    // MARK: Decoding

    func testBudgetResponseDecodesBothAllowances() throws {
        let status = try JSONDecoder().decode(MistralBudgetStatus.self, from: Data(budgetJSON.utf8))
        let now = try XCTUnwrap(ISO8601Parser.date(from: "2026-11-06T00:00:00Z"))
        XCTAssertTrue(status.hasVisibleLimit)
        XCTAssertEqual(try XCTUnwrap(status.vibe?.utilization(now: now)), 8.1069, accuracy: 0.0001)
        XCTAssertEqual(status.vibe?.initialBudget, 150)
        XCTAssertEqual(status.api?.initialBudget, 15)
        XCTAssertEqual(status.vibe?.activeReset(now: now), ISO8601Parser.date(from: "2026-12-01T00:00:00Z"))
        XCTAssertEqual(status.vibe?.amountText(now: now), "$12.16 / $150")
        XCTAssertEqual(status.api?.amountText(now: now), "$0.07 / $15")
        XCTAssertEqual(status.headline, status.vibe)
        XCTAssertNil(status.plan, "the plan comes from whoami, not from the budget response")
    }

    /// The reset is always the 1st at 00:00 UTC; the pace marker needs that month's length.
    func testPeriodSpanIsTheCalendarMonthEndingAtTheReset() throws {
        let november = MistralBudgetStatus.Budget(usagePercentage: 1, initialBudget: 1, resetAt: "2026-12-01T00:00:00Z")
        XCTAssertEqual(try XCTUnwrap(november.periodSpan), 30 * 86400)
        let february = MistralBudgetStatus.Budget(usagePercentage: 1, initialBudget: 1, resetAt: "2027-03-01T00:00:00Z")
        XCTAssertEqual(try XCTUnwrap(february.periodSpan), 28 * 86400)
    }

    /// A status kept past its reset (the key stopped working) must not keep showing last month.
    func testEndedMonthReadsAsUnusedWithoutAReset() throws {
        let budget = MistralBudgetStatus.Budget(usagePercentage: 80, initialBudget: 150, resetAt: "2026-12-01T00:00:00Z")
        let after = try XCTUnwrap(ISO8601Parser.date(from: "2026-12-01T00:00:01Z"))
        XCTAssertEqual(budget.utilization(now: after), 0)
        XCTAssertNil(budget.activeReset(now: after))
        XCTAssertEqual(budget.amountText(now: after), "$0.00 / $150")
    }

    func testZeroBudgetIsHiddenAndMissingFieldsDoNotFailTheDecode() throws {
        let json = #"{"vibe_budget":{"usage_percentage":0,"initial_budget":0},"api_budget":{"currency":"USD"},"extra":1}"#
        let status = try JSONDecoder().decode(MistralBudgetStatus.self, from: Data(json.utf8))
        XCTAssertFalse(status.hasVisibleLimit)
        XCTAssertNil(status.headline)
        XCTAssertNil(status.vibe?.utilization(now: Date()))
        let empty = try JSONDecoder().decode(MistralBudgetStatus.self, from: Data("{}".utf8))
        XCTAssertFalse(empty.hasVisibleLimit)
    }

    func testNonUSDAmountsKeepTheirCurrencyCode() {
        let budget = MistralBudgetStatus.Budget(usagePercentage: 50, initialBudget: 20, currency: "EUR")
        XCTAssertEqual(budget.amountText(now: Date()), "10.00 / 20 EUR")
        let fractional = MistralBudgetStatus.Budget(usagePercentage: 10, initialBudget: 12.5)
        XCTAssertEqual(fractional.amountText(now: Date()), "$1.25 / $12.50")
    }

    func testPlanNamesFollowVibesAccountView() {
        let cases: [(String, String, String?)] = [
            ("CHAT", "FREE", "Free"), ("CHAT", "INDIVIDUAL", "Pro"), ("chat", " edu ", "Pro (Education)"),
            ("CHAT", "TEAM", "Team"), ("CHAT", "ENTERPRISE", "Enterprise"), ("CHAT", "", nil),
            ("API", "FREE_TRIAL", "API Free"), ("API", "SCALE", "API Scale"),
            ("MISTRAL_CODE", "F", "Mistral Code Free"), ("MISTRAL_CODE", "E", "Mistral Code Enterprise"),
            ("MISTRAL_CODE", "X", nil), ("OTHER", "PRO", nil),
        ]
        for (type, name, expected) in cases {
            XCTAssertEqual(MistralPlan(planType: type, planName: name).displayName, expected, "\(type)/\(name)")
        }
    }

    // MARK: Key sources

    func testEnvFileParsingFollowsDotenvRules() throws {
        let file = temporaryDirectory.appendingPathComponent(".env")
        try Data("""
        # comment
        OTHER=1
        MISTRAL_API_KEY=first
        export MISTRAL_API_KEY = "quoted value" # trailing
        MISTRAL_API_KEY_OLD=nope
        """.utf8).write(to: file)
        XCTAssertEqual(MistralKeyCache.envFileValue("MISTRAL_API_KEY", in: file), "quoted value")

        try Data("MISTRAL_API_KEY=bare # note\n".utf8).write(to: file)
        XCTAssertEqual(MistralKeyCache.envFileValue("MISTRAL_API_KEY", in: file), "bare")

        try Data("MISTRAL_API_KEY=\nMISTRAL_API_KEY='   '\n".utf8).write(to: file)
        XCTAssertNil(MistralKeyCache.envFileValue("MISTRAL_API_KEY", in: file))
        XCTAssertNil(MistralKeyCache.envFileValue("MISTRAL_API_KEY", in: temporaryDirectory.appendingPathComponent("none")))
    }

    func testEnvironmentWinsOverEnvFileAndNeitherTouchesTheKeychain() async throws {
        let file = temporaryDirectory.appendingPathComponent(".env")
        try Data("MISTRAL_API_KEY=from-file\n".utf8).write(to: file)
        injectKeychain(["ai.mistral.vibe": "from-keychain"])

        let withEnvironment = MistralKeyCache(environmentKey: { " from-env " }, envFiles: { [file] })
        let key = try await withEnvironment.apiKey(allowKeychainPrompt: true)
        XCTAssertEqual(key, "from-env")
        let fileOnly = MistralKeyCache(environmentKey: { nil }, envFiles: { [file] })
        let fileKey = try await fileOnly.apiKey(allowKeychainPrompt: true)
        XCTAssertEqual(fileKey, "from-file")
        XCTAssertEqual(KeychainReader.queryCount, 0)
    }

    /// The contract `KeychainAutoPathTests` guards: the automatic path answers from memory only.
    func testAutomaticPathUsesOnlyAKeyAUserActionLoaded() async throws {
        injectKeychain(["ai.mistral.vibe": "vibe-key"])
        let keys = MistralKeyCache(environmentKey: { nil }, envFiles: { [] })

        let before = try await keys.apiKey(allowKeychainPrompt: false)
        XCTAssertNil(before)
        XCTAssertEqual(KeychainReader.queryCount, 0)

        let loaded = try await keys.apiKey(allowKeychainPrompt: true)
        XCTAssertEqual(loaded, "vibe-key")
        XCTAssertEqual(KeychainReader.queryCount, 1, "silent read first; it succeeds, so no prompt query")

        let after = try await keys.apiKey(allowKeychainPrompt: false)
        XCTAssertEqual(after, "vibe-key")
        XCTAssertEqual(KeychainReader.queryCount, 1)
    }

    func testLegacyServiceIsReadWhenTheCurrentOneIsMissing() async throws {
        injectKeychain(["vibe": "legacy-key"])
        let keys = MistralKeyCache(environmentKey: { nil }, envFiles: { [] })
        let key = try await keys.apiKey(allowKeychainPrompt: true)
        XCTAssertEqual(key, "legacy-key")
    }

    /// Silent reads fail for an item that needs approval; only then the prompting query runs.
    func testPromptingQueryRunsOnlyAfterTheSilentReadsFail() async throws {
        var promptQueries = 0
        KeychainReader.copyMatchingForTesting = { query, result in
            let silent = query[kSecUseAuthenticationContext as String] != nil
            guard query[kSecAttrService as String] as? String == "ai.mistral.vibe" else { return errSecItemNotFound }
            if silent { return errSecInteractionNotAllowed }
            promptQueries += 1
            result = Data("approved-key".utf8) as CFData
            return errSecSuccess
        }
        let keys = MistralKeyCache(environmentKey: { nil }, envFiles: { [] })
        let key = try await keys.apiKey(allowKeychainPrompt: true)
        XCTAssertEqual(key, "approved-key")
        XCTAssertEqual(promptQueries, 1)
    }

    /// A key removed from the Keychain must not keep refreshing from memory after the next tap.
    func testUserActionThatFindsNoItemDropsTheCachedKey() async throws {
        injectKeychain(["ai.mistral.vibe": "vibe-key"])
        let keys = MistralKeyCache(environmentKey: { nil }, envFiles: { [] })
        _ = try await keys.apiKey(allowKeychainPrompt: true)
        injectKeychain([:])
        let gone = try await keys.apiKey(allowKeychainPrompt: true)
        XCTAssertNil(gone)
        let auto = try await keys.apiKey(allowKeychainPrompt: false)
        XCTAssertNil(auto)
    }

    func testDisabledKeychainAccessIsReportedOnTheUserPath() async {
        KeychainAccessGate.isDisabled = true
        injectKeychain(["ai.mistral.vibe": "vibe-key"])
        let keys = MistralKeyCache(environmentKey: { nil }, envFiles: { [] })
        do {
            _ = try await keys.apiKey(allowKeychainPrompt: true)
            XCTFail("expected keychainAccessDisabled")
        } catch {
            XCTAssertEqual(error as? LimitsError, .keychainAccessDisabled)
        }
        XCTAssertEqual(KeychainReader.queryCount, 0)
    }

    // MARK: Provider

    func testFetchSendsTheKeyAndAttachesThePlanOncePerKey() async throws {
        let requests = RequestLog()
        MistralRateLimitsProvider.transportForTesting = { [budgetJSON, whoamiJSON] request in
            requests.append(request)
            let body = request.url == MistralRateLimitsProvider.whoamiURL ? whoamiJSON : budgetJSON
            return (Data(body.utf8), 200)
        }
        let provider = MistralRateLimitsProvider(keys: MistralKeyCache(environmentKey: { "env-key" }, envFiles: { [] }))

        let first = try await provider.fetch(allowKeychainPrompt: false)
        XCTAssertEqual(first?.plan?.displayName, "Pro (Education)")
        XCTAssertEqual(requests.urls, [MistralRateLimitsProvider.budgetURL, MistralRateLimitsProvider.whoamiURL])
        XCTAssertEqual(requests.all.first?.value(forHTTPHeaderField: "Authorization"), "Bearer env-key")

        let second = try await provider.fetch(allowKeychainPrompt: false)
        XCTAssertEqual(second?.plan?.displayName, "Pro (Education)")
        XCTAssertEqual(requests.urls.count, 3, "the plan is not looked up again for the same key")
    }

    /// Cloudflare can answer the console host with a challenge page. The budgets still show,
    /// and the plan is tried again on the next refresh.
    func testPlanFailureKeepsTheBudgetsAndRetriesLater() async throws {
        let requests = RequestLog()
        MistralRateLimitsProvider.transportForTesting = { [budgetJSON] request in
            requests.append(request)
            if request.url == MistralRateLimitsProvider.whoamiURL {
                return (Data("<!DOCTYPE html><title>Just a moment...</title>".utf8), 403)
            }
            return (Data(budgetJSON.utf8), 200)
        }
        let provider = MistralRateLimitsProvider(keys: MistralKeyCache(environmentKey: { "env-key" }, envFiles: { [] }))
        let status = try await provider.fetch(allowKeychainPrompt: false)
        XCTAssertNil(status?.plan)
        XCTAssertEqual(status?.hasVisibleLimit, true)
        _ = try await provider.fetch(allowKeychainPrompt: false)
        XCTAssertEqual(requests.urls.filter { $0 == MistralRateLimitsProvider.whoamiURL }.count, 2)
    }

    func testNoKeyMeansNoRequest() async throws {
        let requests = RequestLog()
        MistralRateLimitsProvider.transportForTesting = { request in
            requests.append(request)
            return (Data(), 200)
        }
        let provider = MistralRateLimitsProvider(keys: MistralKeyCache(environmentKey: { nil }, envFiles: { [] }))
        let status = try await provider.fetch(allowKeychainPrompt: false)
        XCTAssertNil(status)
        XCTAssertTrue(requests.urls.isEmpty)
    }

    func testHTTPFailuresMapToLimitsErrors() async {
        let provider = MistralRateLimitsProvider(keys: MistralKeyCache(environmentKey: { "env-key" }, envFiles: { [] }))
        for (status, expected) in [(401, LimitsError.httpStatus(401)), (403, .httpStatus(403)),
                                   (429, .rateLimited(retryAfter: nil)), (500, .httpStatus(500))] {
            MistralRateLimitsProvider.transportForTesting = { _ in (Data("{}".utf8), status) }
            do {
                _ = try await provider.fetch(allowKeychainPrompt: false)
                XCTFail("status \(status) must throw")
            } catch {
                XCTAssertEqual(error as? LimitsError, expected)
            }
        }
        MistralRateLimitsProvider.transportForTesting = { _ in nil }
        do {
            _ = try await provider.fetch(allowKeychainPrompt: false)
            XCTFail("a transport error must throw")
        } catch {
            XCTAssertEqual(error as? LimitsError, .httpStatus(0))
        }
    }

    /// The real provider stops at the network gate inside `swift test`.
    func testLiveFetchIsGatedUnderSwiftTest() async throws {
        if AppEnv.isParityRun { throw XCTSkip("PTB_PARITY=1 opens the gate on purpose") }
        let provider = MistralRateLimitsProvider(keys: MistralKeyCache(environmentKey: { "env-key" }, envFiles: { [] }))
        do {
            _ = try await provider.fetch(allowKeychainPrompt: false)
            XCTFail("a live Mistral limits call ran inside swift test")
        } catch {
            XCTAssertEqual(error as? LimitsError, .liveFetchNotPermitted)
        }
    }

    // MARK: Helpers

    private func injectKeychain(_ items: [String: String]) {
        KeychainReader.copyMatchingForTesting = { query, result in
            guard query[kSecAttrAccount as String] as? String == "MISTRAL_API_KEY",
                  let service = query[kSecAttrService as String] as? String,
                  let value = items[service] else { return errSecItemNotFound }
            result = Data(value.utf8) as CFData
            return errSecSuccess
        }
    }

    private final class RequestLog: @unchecked Sendable {
        private let lock = NSLock()
        private var requests: [URLRequest] = []
        func append(_ request: URLRequest) { lock.lock(); requests.append(request); lock.unlock() }
        var all: [URLRequest] { lock.lock(); defer { lock.unlock() }; return requests }
        var urls: [URL] { all.compactMap(\.url) }
    }
}
