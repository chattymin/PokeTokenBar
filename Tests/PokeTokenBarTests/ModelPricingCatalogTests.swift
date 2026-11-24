import Foundation
import XCTest
@testable import PokeTokenBar

final class ModelPricingCatalogTests: XCTestCase {
    func testExplicitContextTierTakesPrecedenceOverLegacyField() throws {
        let long: [String: Any] = ["input": 4, "output": 15, "cache_read": 0.2, "cache_write": 5]
        let catalog = try catalog(openai: [
            "gpt-6.2-sol": row("gpt-6.2-sol", cost: [
                "input": 2, "output": 10, "cache_read": 0.1, "cache_write": 2.5,
                "tiers": [band(272_000, prices: long)], "context_over_200k": long,
            ]),
        ])

        XCTAssertEqual(catalog.rate(for: "gpt-6.2-sol"), .perMillion(2, 10, 2.5, 0.1))
        XCTAssertEqual(try XCTUnwrap(catalog.estimatedCost(
            model: "gpt-6.2-sol", input: 210_000, output: 0, cacheWrite: 0, cacheRead: 0)), 0.42, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(catalog.estimatedCost(
            model: "gpt-6.2-sol", input: 2_000, output: 1_000, cacheWrite: 0, cacheRead: 270_000)), 0.041, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(catalog.estimatedCost(
            model: "gpt-6.2-sol", input: 2_000, output: 1_000, cacheWrite: 1, cacheRead: 270_000)), 0.077005, accuracy: 1e-12)
    }

    func testLargestCrossedContextTierPricesTheWholeRequest() throws {
        let short: [String: Any] = ["input": 0.1, "output": 0.5, "cache_read": 0.01, "cache_write": 0.125]
        let long: [String: Any] = ["input": 0.5, "output": 2.5, "cache_read": 0.05, "cache_write": 0.625]
        let longer: [String: Any] = ["input": 1, "output": 5, "cache_read": 0.1, "cache_write": 1.25]
        let catalog = try catalog(anthropic: [
            "claude-haiku-5-5": row("claude-haiku-5-5", cost: short.merging([
                "tiers": [band(200_000, prices: longer), band(100_000, prices: long)],
            ]) { _, new in new }),
        ])

        XCTAssertEqual(try XCTUnwrap(catalog.estimatedCost(
            model: "claude-haiku-5-5", input: 50_000, output: 100_001, cacheWrite: 0, cacheRead: 50_000)),
                       0.0555005, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(catalog.estimatedCost(
            model: "claude-haiku-5-5", input: 50_000, output: 1_000, cacheWrite: 0, cacheRead: 150_000)),
                       0.035, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(catalog.estimatedCost(
            model: "claude-haiku-5-5", input: 50_000, output: 1_000, cacheWrite: 1, cacheRead: 150_000)),
                       0.07000125, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(catalog.estimatedCost(
            model: "claude-haiku-5-5", input: Int.max, output: 0, cacheWrite: Int.max, cacheRead: Int.max)),
                       Double(Int.max) * 2.35 / 1_000_000, accuracy: 0.01)
    }

    func testCostKeepsMissingCacheRatesDistinctFromExplicitlyFreeRates() throws {
        let catalog = try catalog(openai: [
            "gpt-no-cache-rate": row("gpt-no-cache-rate"),
            "gpt-free-cache": row("gpt-free-cache", cost: [
                "input": 1, "output": 2, "cache_read": 0, "cache_write": 0,
            ]),
            "gpt-missing-tier-cache": row("gpt-missing-tier-cache", cost: [
                "input": 1, "output": 2, "cache_read": 0, "cache_write": 0,
                "tiers": [band(100_000, prices: ["input": 2, "output": 3])],
            ]),
        ])

        XCTAssertNil(catalog.estimatedCost(model: "gpt-no-cache-rate", input: 1, output: 0, cacheWrite: 1, cacheRead: 0))
        XCTAssertNil(catalog.estimatedCost(model: "gpt-no-cache-rate", input: 1, output: 0, cacheWrite: 0, cacheRead: 1))
        XCTAssertEqual(catalog.estimatedCost(model: "gpt-free-cache", input: 0, output: 0, cacheWrite: 1, cacheRead: 1), 0)
        XCTAssertNil(catalog.estimatedCost(model: "gpt-missing-tier-cache", input: 100_000, output: 0, cacheWrite: 0, cacheRead: 1))
        XCTAssertNil(catalog.estimatedCost(model: "gpt-free-cache", input: -1, output: 0, cacheWrite: 0, cacheRead: 0))
    }

    func testAcceptsOnlyEligibleExactDirectVendorIDs() throws {
        let catalog = try catalog(
            openai: [
                "gpt-5.4-mini": row("gpt-5.4-mini"),
                "gpt-conflict": row("gpt-conflict"),
                "gpt-wrong-key": row("gpt-other"),
                "auto": row("auto"),
                "openai/gpt-5": row("openai/gpt-5"),
            ],
            anthropic: ["gpt-conflict": row("gpt-conflict")],
            google: [
                "gemini-embedding-001": row("gemini-embedding-001"),
                "gemini-audio-out": row("gemini-audio-out", output: ["text", "audio"]),
                "gemini-audio-in": row("gemini-audio-in", input: ["audio"]),
                "gemini-text": row("gemini-text", cost: ["input": 1, "output": 2, "input_audio": 5],
                                   input: ["text", "audio"]),
                "gemma-free": row("gemma-free", cost: ["input": 0, "output": 0]),
            ],
            relay: ["gpt-relay-only": row("gpt-relay-only")])

        XCTAssertEqual(ModelPricingCatalog.normalizedID("OPENAI/CHATGPT-LATEST"), "chatgpt-latest")
        XCTAssertEqual(ModelPricingCatalog.normalizedID("anthropic/chatgpt-latest"), "anthropic/chatgpt-latest")
        XCTAssertTrue(catalog.contains("gpt-5.4-mini"))
        XCTAssertEqual(catalog.rate(for: "gemini-text"), .perMillion(1, 2, 0, 0))
        XCTAssertEqual(catalog.rate(for: "gemma-free"), .zero)
        for key in ["gpt-conflict", "gpt-wrong-key", "gpt-other", "auto", "openai/gpt-5",
                    "gemini-embedding-001", "gemini-audio-out", "gemini-audio-in", "gpt-relay-only",
                    "openai/gpt-5.4-mini", "gpt-5.4-mini-custom"] {
            XCTAssertFalse(catalog.contains(key), key)
            XCTAssertNil(catalog.rate(for: key), key)
        }
    }

    func testMalformedOrAmbiguousPricingDoesNotFallBackToBase() throws {
        let base: [String: Any] = ["input": 1, "output": 2]
        let duplicateBands = [band(200_000, prices: base), band(200_000, prices: base)]
        let catalog = try catalog(openai: [
            "gpt-negative": row("gpt-negative", cost: ["input": -1, "output": 2]),
            "gpt-bool": row("gpt-bool", cost: ["input": true, "output": 2]),
            "gpt-null-price": row("gpt-null-price", cost: ["input": 1, "output": 2, "cache_read": NSNull()]),
            "gpt-missing-output": row("gpt-missing-output", cost: ["input": 1]),
            "gpt-thinking": row("gpt-thinking", cost: ["input": 1, "output": 2, "reasoning": 5]),
            "gpt-unknown-price": row("gpt-unknown-price", cost: ["input": 1, "output": 2, "input_image": 4]),
            "gpt-unknown-tier": row("gpt-unknown-tier", cost: ["input": 1, "output": 2, "tiers": [
                ["input": 3, "output": 4, "tier": ["type": "new", "size": 200_000]],
            ]]),
            "gpt-duplicate-tier": row("gpt-duplicate-tier", cost: ["input": 1, "output": 2, "tiers": duplicateBands]),
            "gpt-incomplete-tier": row("gpt-incomplete-tier", cost: ["input": 1, "output": 2, "tiers": [
                band(200_000, prices: ["input": 2]),
            ]]),
        ])

        for key in ["gpt-negative", "gpt-bool", "gpt-null-price", "gpt-missing-output", "gpt-thinking",
                    "gpt-unknown-price", "gpt-unknown-tier", "gpt-duplicate-tier", "gpt-incomplete-tier"] {
            XCTAssertFalse(catalog.contains(key), key)
        }
    }

    func testLegacyOnlyBandRequiresAKnownThreshold() throws {
        let short: [String: Any] = ["input": 1, "output": 2, "context_over_200k": ["input": 3, "output": 4]]
        let catalog = try catalog(
            openai: ["gpt-6.2-sol": row("gpt-6.2-sol", cost: short)],
            google: ["gemini-2.5-pro": row("gemini-2.5-pro", cost: short)])

        XCTAssertFalse(catalog.contains("gpt-6.2-sol"))
        XCTAssertEqual(try XCTUnwrap(catalog.estimatedCost(
            model: "gemini-2.5-pro", input: 200_000, output: 0, cacheWrite: 0, cacheRead: 0)), 0.2, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(catalog.estimatedCost(
            model: "gemini-2.5-pro", input: 200_001, output: 0, cacheWrite: 0, cacheRead: 0)), 0.600003, accuracy: 1e-12)
    }

    func testRejectsBrokenOrIncompleteCatalogs() throws {
        for payload in ["{", "{}", "[]"] {
            XCTAssertThrowsError(try ModelPricingCatalog.decode(Data(payload.utf8)))
        }
        var broken = payload()
        broken["openai"] = ["id": "openrouter", "models": ["gpt-5": row("gpt-5")]]
        XCTAssertThrowsError(try ModelPricingCatalog.decode(JSONSerialization.data(withJSONObject: broken)))
        broken["openai"] = ["id": "openai", "models": ["bad": 1]]
        XCTAssertThrowsError(try ModelPricingCatalog.decode(JSONSerialization.data(withJSONObject: broken)))
    }

    func testOverlayUsesUpdatedRatesAndKeepsOmittedExistingModels() throws {
        let bundled = try catalog(openai: ["gpt-older": row("gpt-older")])
        let fetched = try catalog(openai: [
            "gpt-5": row("gpt-5", cost: ["input": 3, "output": 4]),
            "gpt-newer": row("gpt-newer"),
        ])
        let combined = bundled.overlaying(fetched)

        XCTAssertEqual(combined.rate(for: "gpt-5"), .perMillion(3, 4, 0, 0))
        XCTAssertEqual(combined.rate(for: "gpt-older"), .perMillion(1, 2, 0, 0))
        XCTAssertEqual(combined.rate(for: "gpt-newer"), .perMillion(1, 2, 0, 0))
    }

    @MainActor
    func testRefreshRepricesTheSameTokensAndPreservesReportedCosts() async throws {
        let day = LocalUsageReader.todayKey()
        let id = "gpt-catalog-test"
        let entry = LocalUsageReader.Entry(id: "sample", date: Date(), localDay: day, model: id,
                                           input: 100_000, output: 10_000, cacheWrite: 0, cacheRead: 100_000)
        let reported = LocalUsageReader.Entry(id: "reported", date: entry.date, localDay: day, model: id,
                                              input: entry.input, output: entry.output, cacheWrite: 0,
                                              cacheRead: entry.cacheRead, explicitCost: 0.07)
        let suite = "CatalogStore-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "disableKeychainAccess")
        defaults.set(false, forKey: "statusChecksEnabled")
        let store = UsageStore(providers: [CostTestProvider(id: "sample", entries: [entry, reported])],
                               autoRefresh: false, defaults: defaults)
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(store.todayTotalTokens, 420_000)
        XCTAssertEqual(store.todayUsageCost.amount, 0.07, accuracy: 1e-12)

        let update = try catalog(openai: [
            id: row(id, cost: ["input": 2, "output": 10, "cache_read": 0.1]),
            "gpt-5.6": row("gpt-5.6", cost: ["input": 3, "output": 15]),
        ])
        defer { ModelPricing.install(nil) }
        await store.refresh(scheduleEmptyRetry: false, pricingCatalog: update)
        XCTAssertEqual(store.todayTotalTokens, 420_000)
        XCTAssertEqual(store.todayUsageCost.amount, 0.38, accuracy: 1e-12)
        XCTAssertEqual(store.weekUsageCost.amount, 0.38, accuracy: 1e-12)
        XCTAssertEqual(store.todayUsageCost.coverage, CostCoverage(reported: true, estimated: true))
        XCTAssertEqual(ModelPricing.rate(for: "openai/gpt-5.6"), .perMillion(3, 15, 0, 0),
                       "a published exact rate takes precedence over the historical alias")
        XCTAssertEqual(ModelPricing.rate(for: "anthropic/gpt-5.6"), .zero)
    }

    private func catalog(openai: [String: Any] = [:], anthropic: [String: Any] = [:],
                         google: [String: Any] = [:], relay: [String: Any] = [:]) throws -> ModelPricingCatalog {
        let payload = payload(openai: openai, anthropic: anthropic, google: google, relay: relay)
        return try ModelPricingCatalog.decode(JSONSerialization.data(withJSONObject: payload))
    }

    private func payload(openai: [String: Any] = [:], anthropic: [String: Any] = [:],
                         google: [String: Any] = [:], relay: [String: Any] = [:]) -> [String: Any] {
        [
            "openai": ["id": "openai", "models": openai.merging(["gpt-5": row("gpt-5")]) { first, _ in first }],
            "anthropic": ["id": "anthropic", "models": anthropic.merging(["claude-sonnet-5": row("claude-sonnet-5")]) { first, _ in first }],
            "google": ["id": "google", "models": google.merging(["gemini-3.6-flash": row("gemini-3.6-flash")]) { first, _ in first }],
            "openrouter": ["id": "openrouter", "models": relay],
        ]
    }

    private func row(_ id: String, cost: [String: Any] = ["input": 1, "output": 2],
                     input: [String] = ["text"], output: [String] = ["text"]) -> [String: Any] {
        ["id": id, "modalities": ["input": input, "output": output], "cost": cost]
    }

    private func band(_ threshold: Int, prices: [String: Any]) -> [String: Any] {
        prices.merging(["tier": ["type": "context", "size": threshold]]) { _, condition in condition }
    }
}
