import XCTest
@testable import PokeTokenBar

final class CursorLimitsTests: XCTestCase {
    override func tearDown() {
        CursorRateLimitsProvider.transportForTesting = nil
        CursorAuthentication.configurationForTesting = nil
        CursorAuthentication.resetForTesting()
        super.tearDown()
    }

    func testCursorPlanUsageUsedPercentPrefersTotalPercentUsed() {
        let usage = CursorPlanUsage(includedSpend: 10_000, limit: 40_000, totalPercentUsed: 42.5)
        XCTAssertEqual(usage.usedPercent, 42.5)
    }

    func testCursorPlanUsageUsedPercentFallsBackToIncludedSpendOverLimit() {
        let usage = CursorPlanUsage(includedSpend: 10_000, limit: 40_000)
        XCTAssertEqual(usage.usedPercent, 25)
    }

    func testCursorRateLimitStatusParsesBillingCycleEndEpochMilliseconds() throws {
        let payload = """
        {
          "billingCycleEnd": "1771077734000",
          "planUsage": {
            "remaining": 16778,
            "limit": 40000,
            "totalPercentUsed": 58.055
          }
        }
        """.data(using: .utf8)!
        let status = try JSONDecoder().decode(CursorRateLimitStatus.self, from: payload)
        XCTAssertTrue(status.hasVisibleLimit)
        XCTAssertNotNil(status.billingCycleEndDate)
        XCTAssertEqual(status.planUsage?.remainingDollars, 167.78)
        XCTAssertEqual(status.planUsage?.usedPercent, 58.055)
    }

    func testFetchCurrentPeriodUsageUsesBearerAndConnectHeaders() async throws {
        CursorAuthentication.configurationForTesting = .init(environment: ["CURSOR_SESSION_TOKEN": "test-jwt"])
        let expectation = expectation(description: "transport called")
        CursorRateLimitsProvider.transportForTesting = { request in
            defer { expectation.fulfill() }
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(
                request.url?.absoluteString,
                CursorRateLimitsProvider.usageURL.absoluteString)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Connect-Protocol-Version"), "1")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-jwt")
            let payload = """
            {
              "planUsage": {
                "remaining": 10000,
                "limit": 40000,
                "totalPercentUsed": 75
              }
            }
            """.data(using: .utf8)!
            return (payload, 200)
        }

        let provider = CursorRateLimitsProvider()
        let status = try await provider.fetch()
        await fulfillment(of: [expectation], timeout: 1)
        XCTAssertEqual(status?.planUsage?.usedPercent, 75)
    }
}
