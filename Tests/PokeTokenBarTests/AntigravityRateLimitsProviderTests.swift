import XCTest
@testable import PokeTokenBar

final class AntigravityRateLimitsProviderTests: XCTestCase {

    private let sampleJSON = """
    {
      "groups": [
        {
          "displayName": "Gemini Models",
          "description": "Models within this group: Gemini Flash, Gemini Pro",
          "buckets": [
            {
              "bucketId": "gemini-weekly",
              "displayName": "Weekly Limit Remaining",
              "window": "weekly",
              "resetTime": "2026-08-25T08:01:13Z",
              "description": "You have used some of your weekly limit, it will fully refresh in 4 days, 7 hours.",
              "remainingFraction": 0.94
            },
            {
              "bucketId": "gemini-5h",
              "displayName": "Five Hour Limit Remaining",
              "window": "5h",
              "resetTime": "2026-08-21T04:46:04Z",
              "description": "You have used some of your 5-hour limit, it will fully refresh in 3 hours, 53 minutes.",
              "remainingFraction": 0.85
            }
          ]
        },
        {
          "displayName": "Claude and GPT models",
          "description": "Models within this group: Claude Opus, Claude Sonnet, GPT-OSS",
          "buckets": [
            {
              "bucketId": "3p-weekly",
              "displayName": "Weekly Limit Remaining",
              "window": "weekly",
              "resetTime": "2026-08-28T00:52:38Z",
              "remainingFraction": 1.0
            },
            {
              "bucketId": "3p-5h",
              "displayName": "Five Hour Limit Remaining",
              "window": "5h",
              "resetTime": "2026-08-21T05:52:38Z",
              "remainingFraction": 0.50
            }
          ]
        }
      ],
      "description": "Quota summary description"
    }
    """

    func testDecodingQuotaSummary() throws {
        let data = Data(sampleJSON.utf8)
        let status = try JSONDecoder().decode(AntigravityRateLimitStatus.self, from: data)

        XCTAssertTrue(status.hasVisibleLimit)
        XCTAssertEqual(status.groups.count, 2)

        let gemini = try XCTUnwrap(status.geminiGroup)
        XCTAssertEqual(gemini.displayName, "Gemini Models")
        XCTAssertEqual(gemini.buckets.count, 2)
        XCTAssertEqual(gemini.buckets.map(\.bucketId), ["gemini-5h", "gemini-weekly"],
                       "5-hour limit bucket must always be ordered before weekly")

        let gemini5h = try XCTUnwrap(gemini.fiveHourBucket)
        XCTAssertEqual(gemini5h.bucketId, "gemini-5h")
        XCTAssertEqual(gemini5h.remainingFraction, 0.85)
        XCTAssertEqual(gemini5h.usedPercent, 15.0, accuracy: 0.001)
        XCTAssertNotNil(gemini5h.resetDate)

        let geminiWeekly = try XCTUnwrap(gemini.weeklyBucket)
        XCTAssertEqual(geminiWeekly.usedPercent, 6.0, accuracy: 0.001)

        let tp = try XCTUnwrap(status.thirdPartyGroup)
        XCTAssertEqual(tp.displayName, "Claude and GPT models")
        XCTAssertEqual(tp.buckets.map(\.bucketId), ["3p-5h", "3p-weekly"],
                       "5-hour limit bucket must always be ordered before weekly")
        let tp5h = try XCTUnwrap(tp.fiveHourBucket)
        XCTAssertEqual(tp5h.usedPercent, 50.0, accuracy: 0.001)

        // maxPrimaryUsedPercent should be max(15.0, 50.0) = 50.0
        XCTAssertEqual(status.maxPrimaryUsedPercent, 50.0)
    }

    @MainActor
    func testUsageStoreIntegration() async throws {
        let data = Data(sampleJSON.utf8)
        let status = try JSONDecoder().decode(AntigravityRateLimitStatus.self, from: data)

        let suite = "test.antigravity.limits.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(true, forKey: "showLimitInMenu")

        let fakeProvider = FakeAntigravityUsageProvider(id: "antigravity", displayName: "Antigravity", todayTokens: 50_000)
        let fakeLimits = FakeAntigravityLimits(status: status)

        let store = UsageStore(
            providers: [fakeProvider],
            antigravityLimitsProvider: fakeLimits,
            autoRefresh: false,
            defaults: defaults
        )

        await store.refresh()

        XCTAssertNotNil(store.antigravityLimits)
        XCTAssertEqual(store.antigravityLimits?.maxPrimaryUsedPercent, 50.0)

        // Menu lines should include AGY 50%
        let lines = store.menuLines
        XCTAssertTrue(lines.contains(where: { $0.contains("AGY 50%") }))

        // Candy windows
        let byWindow = Dictionary(uniqueKeysWithValues: store.candyEligibleWindows.map { ($0.key, $0) })
        let gemini5h = byWindow["antigravity.gemini.5h"]
        XCTAssertNotNil(gemini5h)
        XCTAssertEqual(try XCTUnwrap(gemini5h?.utilization), 15.0, accuracy: 0.01)

        let tp5h = byWindow["antigravity.3p.5h"]
        XCTAssertNotNil(tp5h)
        XCTAssertEqual(try XCTUnwrap(tp5h?.utilization), 50.0, accuracy: 0.01)

        let geminiWeekly = byWindow["antigravity.gemini.weekly"]
        XCTAssertNotNil(geminiWeekly)
        XCTAssertEqual(try XCTUnwrap(geminiWeekly?.utilization), 6.0, accuracy: 0.01)
    }
}

private struct FakeAntigravityLimits: AntigravityLimitsProviding {
    var status: AntigravityRateLimitStatus?
    func fetch(allowKeychainPrompt: Bool) async throws -> AntigravityRateLimitStatus {
        guard let status else { throw LimitsError.keychainInteractionNotAllowed }
        return status
    }
}

private final class FakeAntigravityUsageProvider: UsageProvider, @unchecked Sendable {
    let id: String
    let displayName: String
    let reportsCost: Bool = false
    let todayTokens: Int

    init(id: String, displayName: String, todayTokens: Int) {
        self.id = id
        self.displayName = displayName
        self.todayTokens = todayTokens
    }

    func fetchDaily() async throws -> DailyUsage? {
        DailyUsage(
            date: LocalUsageReader.todayKey(),
            inputTokens: todayTokens / 2,
            outputTokens: todayTokens / 2,
            cacheCreationTokens: 0,
            cacheReadTokens: 0,
            totalTokens: todayTokens,
            totalCost: 0
        )
    }

    func fetchEnrichment() async -> ProviderEnrichment {
        ProviderEnrichment()
    }
}
