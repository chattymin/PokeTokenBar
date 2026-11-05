import XCTest
@testable import PokeTokenBar

final class GrokLimitsTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("grok-limits-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        GrokRateLimitsProvider.transportForTesting = nil
        try? FileManager.default.removeItem(at: root)
    }

    /// Shape captured from the live endpoint (2026-10-29), account balance fields removed.
    private let livePayload = """
    {"config":{"currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY","start":"2026-10-28T20:51:37.352+00:00",\
    "end":"2026-11-04T20:51:37.352+00:00"},"creditUsagePercent":12.0,"productUsage":[\
    {"product":"GrokBot","usagePercent":7.0},{"product":"GrokBuild","usagePercent":3.0},\
    {"product":"Api","usagePercent":2.0}],"isUnifiedBillingUser":true,\
    "billingPeriodStart":"2026-10-28T20:51:37.352+00:00","billingPeriodEnd":"2026-11-04T20:51:37.352+00:00"}}
    """

    private func status(percent: Double, start: Date, end: Date, type: String = "USAGE_PERIOD_TYPE_WEEKLY",
                        products: [GrokCreditStatus.ProductUsage] = []) -> GrokCreditStatus {
        let f = ISO8601DateFormatter()
        return GrokCreditStatus(currentPeriod: .init(type: type, start: f.string(from: start), end: f.string(from: end)),
                                creditUsagePercent: percent, productUsage: products)
    }

    // MARK: Decoding and period state

    func testDecodesTheBillingCreditsPayload() throws {
        let status = try JSONDecoder().decode(GrokCreditStatus.self, from: Data(livePayload.utf8))
        XCTAssertTrue(status.hasVisibleLimit)
        XCTAssertEqual(status.creditUsagePercent, 12)
        XCTAssertTrue(status.isWeekly)
        XCTAssertFalse(status.isMonthly)
        XCTAssertEqual(try XCTUnwrap(status.periodSpan), 7 * 86400, accuracy: 1)
        XCTAssertEqual(status.productUsage.map(\.product), ["GrokBot", "GrokBuild", "Api"])
    }

    func testMissingPercentHasNoVisibleLimit() throws {
        let json = #"{"config":{"currentPeriod":{"type":"USAGE_PERIOD_TYPE_SOMETHING_NEW"}}}"#
        let status = try JSONDecoder().decode(GrokCreditStatus.self, from: Data(json.utf8))
        XCTAssertFalse(status.hasVisibleLimit)
        XCTAssertFalse(status.isWeekly)
        XCTAssertNil(status.periodSpan)
    }

    func testRunningPeriodKeepsPercentResetAndProducts() {
        let now = Date()
        let end = now.addingTimeInterval(86400)
        let s = status(percent: 12, start: now.addingTimeInterval(-6 * 86400), end: end,
                       products: [.init(product: "GrokBot", usagePercent: 7), .init(product: "Api", usagePercent: 0)])
        XCTAssertEqual(s.utilization(now: now), 12)
        XCTAssertEqual(s.activeReset(now: now)?.timeIntervalSince1970 ?? 0, end.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(s.usedProducts(now: now).map(\.product), ["GrokBot"], "unused products are dropped")
    }

    /// A status kept past its period (token expired, nothing newer arrived) must not show old usage.
    func testEndedPeriodCountsAsUnused() {
        let now = Date()
        let s = status(percent: 80, start: now.addingTimeInterval(-8 * 86400), end: now.addingTimeInterval(-60),
                       products: [.init(product: "GrokBot", usagePercent: 80)])
        XCTAssertEqual(s.utilization(now: now), 0)
        XCTAssertNil(s.activeReset(now: now))
        XCTAssertEqual(s.usedProducts(now: now), [])
    }

    // MARK: Provider

    func testNoLoginReturnsNilWithoutARequest() async throws {
        GrokRateLimitsProvider.transportForTesting = { _ in
            XCTFail("no request without a login")
            return nil
        }
        let result = try await GrokRateLimitsProvider(accessToken: { nil }).fetch()
        XCTAssertNil(result)
    }

    func testFetchSendsTheTokenAsBearer() async throws {
        let payload = livePayload
        GrokRateLimitsProvider.transportForTesting = { request in
            XCTAssertEqual(request.url, GrokRateLimitsProvider.usageURL)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
            return (Data(payload.utf8), 200)
        }
        let result = try await GrokRateLimitsProvider(accessToken: { "tok" }).fetch()
        XCTAssertEqual(result?.creditUsagePercent, 12)
    }

    func testRejectedTokenThrowsTheStatusCode() async {
        GrokRateLimitsProvider.transportForTesting = { _ in (Data(), 401) }
        do {
            _ = try await GrokRateLimitsProvider(accessToken: { "old" }).fetch()
            XCTFail("expected a throw")
        } catch {
            XCTAssertEqual(error as? LimitsError, .httpStatus(401))
        }
    }

    func testRateLimitedThrowsRateLimited() async {
        GrokRateLimitsProvider.transportForTesting = { _ in (Data(), 429) }
        do {
            _ = try await GrokRateLimitsProvider(accessToken: { "tok" }).fetch()
            XCTFail("expected a throw")
        } catch {
            XCTAssertEqual(error as? LimitsError, .rateLimited(retryAfter: nil))
        }
    }

    /// The real transport stops at the gate inside `swift test`, so the token never reaches the network.
    func testLiveTransportIsGatedUnderSwiftTest() async throws {
        if AppEnv.isParityRun { throw XCTSkip("PTB_PARITY=1 opens the gate on purpose") }
        do {
            _ = try await GrokRateLimitsProvider(accessToken: { "tok" }).fetch()
            XCTFail("a live Grok limits call ran inside swift test")
        } catch {
            XCTAssertEqual(error as? LimitsError, .liveFetchNotPermitted)
        }
    }

    // MARK: Token lookup

    func testTokenIsTheLoginThatExpiresLast() throws {
        let file = root.appendingPathComponent("auth.json")
        try Data("""
        {"https://auth.x.ai::a":{"key":"older","expires_at":"2026-10-29T10:00:00.000000Z"},
         "https://auth.x.ai::b":{"key":" newer ","expires_at":"2026-10-29T22:57:09.463749Z"},
         "https://auth.x.ai::c":{"refresh_token":"no-key"}}
        """.utf8).write(to: file)
        XCTAssertEqual(GrokRateLimitsProvider.accessToken(authFile: file), "newer")
    }

    func testNoAuthFileIsNil() {
        XCTAssertNil(GrokRateLimitsProvider.accessToken(authFile: root.appendingPathComponent("auth.json")))
    }

    func testAuthFileSitsNextToTheSessionsFolder() {
        XCTAssertEqual(LocalUsageReader.grokAuthFile.deletingLastPathComponent(),
                       LocalUsageReader.grokSessionsDir.deletingLastPathComponent())
        XCTAssertEqual(LocalUsageReader.grokAuthFile.lastPathComponent, "auth.json")
    }
}
