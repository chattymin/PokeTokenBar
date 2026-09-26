import XCTest
@testable import PokeTokenBar

final class ModelPricingTests: XCTestCase {
    func testCurrentOpenAIStandardRates() {
        XCTAssertEqual(ModelPricing.rate(for: "gpt-6-astra"), .perMillion(10, 50, 12.5, 1))
        XCTAssertEqual(ModelPricing.rate(for: "gpt-5.6-sol"), .perMillion(4, 20, 5, 0.4))
        XCTAssertEqual(ModelPricing.rate(for: "gpt-5.6-terra"), .perMillion(2, 12, 2.5, 0.2))
        XCTAssertEqual(ModelPricing.rate(for: "gpt-5.6-luna"), .perMillion(0.2, 1.2, 0.25, 0.02))
        XCTAssertEqual(ModelPricing.rate(for: "gpt-5.5"), .perMillion(5, 30, 0, 0.5))
        XCTAssertEqual(ModelPricing.rate(for: "gpt-5.3-codex"), .perMillion(1.75, 14, 0, 0.175))
        XCTAssertEqual(ModelPricing.rate(for: "gpt-5.1-codex"), .perMillion(1.25, 10, 0, 0.125))
    }

    func testCurrentClaudeStandardRates() {
        // https://platform.claude.com/docs/en/about-claude/pricing — base input, output, 5m cache write, cache read.
        XCTAssertEqual(ModelPricing.rate(for: "claude-opus-5"), .perMillion(5, 25, 6.25, 0.5))
        XCTAssertEqual(ModelPricing.rate(for: "claude-opus-5-5"), .perMillion(4, 20, 5, 0.2))
        XCTAssertEqual(ModelPricing.rate(for: "claude-sonnet-5"), .perMillion(2, 10, 2.5, 0.2))
    }

    /// The inverse of `testUnknownNamesNeverBorrowFamilyPrices`: that test guards against a
    /// *wrong* price, this one against *no* price. #289 dropped the model-family fallback
    /// without adding exact rows for the identities it had been covering, so the whole Claude 5
    /// family became unpriced and every Claude cost rendered as "unavailable" (#303) — a table
    /// that only asserts the rows it already contains cannot catch that. Add an identity here
    /// as soon as a provider starts reporting it.
    func testModelsReadFromProviderLogsAreAllPriced() throws {
        // A real Claude Code bucket split: every request logs cache creation and cache reads,
        // so a row without a cache-write rate is unpriced in practice even when its input and
        // output columns are filled in.
        for model in ["claude-opus-5", "claude-opus-5-5", "claude-sonnet-5", "claude-opus-4-8", "claude-opus-4-7",
                      "claude-sonnet-4-6", "claude-haiku-4-5", "claude-fable-5", "claude-fable-5-1"] {
            let cost = try XCTUnwrap(
                ModelPricing.estimatedCost(model: model, input: 2, output: 175,
                                           cacheWrite: 26_939, cacheRead: 42_676),
                "\(model) resolves to no price — the usage cost row renders as unavailable")
            XCTAssertGreaterThan(cost, 0, model)
        }
    }

    /// An unpriced model is logged once per identity, not once per log entry — Bucket.add runs per request.
    func testUnpricedModelIsReportedOnlyOnFirstSighting() {
        let model = "claude-unpriced-\(UUID().uuidString.lowercased())"
        XCTAssertTrue(ModelPricing.firstUnpricedSighting(model))
        XCTAssertFalse(ModelPricing.firstUnpricedSighting(model))
        XCTAssertFalse(ModelPricing.firstUnpricedSighting("ANTHROPIC/" + model.uppercased()), "normalized like the price lookup")
    }

    /// The wiring: `AppLog` is a no-op under `swift test`, so observe it through the dedupe instead.
    /// Aggregating an unpriced model must consume its first sighting (it was reported); a row whose
    /// source says no estimate is possible must not, since a missing table row is not the cause there.
    func testAggregatingAnUnpricedModelReportsItButNotASourceUnavailableRow() {
        func entry(_ model: String, costUnavailable: Bool? = nil) -> LocalUsageReader.Entry {
            LocalUsageReader.Entry(id: UUID().uuidString, date: Date(), localDay: "2026-09-25", model: model,
                                   input: 10, output: 5, cacheWrite: 0, cacheRead: 0,
                                   costUnavailable: costUnavailable)
        }
        let unpriced = "claude-unpriced-\(UUID().uuidString.lowercased())"
        let sourceUnavailable = "claude-unpriced-\(UUID().uuidString.lowercased())"
        var bucket = LocalUsageReader.Bucket()
        bucket.add(entry(unpriced))
        bucket.add(entry(sourceUnavailable, costUnavailable: true))

        XCTAssertFalse(ModelPricing.firstUnpricedSighting(unpriced), "an unpriced model was not reported")
        XCTAssertTrue(ModelPricing.firstUnpricedSighting(sourceUnavailable),
                      "a source-unavailable row was reported as a missing price")
    }

    func testUnknownNamesNeverBorrowFamilyPrices() {
        for model in ["gpt-5.3-codex-spark", "gpt-99", "codex", "o3", "o4", "grok-codex-next",
                      "claude-opus-4-99", "claude-fable-6", "gemini-99-pro", "custom/claude-opus-4-8",
                      "antigravity/claude-opus-4-8", "gpt-5.5-pro", "gpt-5.5-2026-99-99"] {
            XCTAssertNil(ModelPricing.estimatedCost(model: model, input: 100, output: 20, cacheWrite: 0, cacheRead: 40), model)
            XCTAssertEqual(ModelPricing.cost(model: model, input: 100, output: 20, cacheWrite: 0, cacheRead: 40), 0, model)
        }
    }

    func testExplicitAliasesAndProviderPrefixes() {
        XCTAssertEqual(ModelPricing.rate(for: "openai/gpt-5.4-2026-03-05"), ModelPricing.rate(for: "gpt-5.4"))
        XCTAssertEqual(ModelPricing.rate(for: " ANTHROPIC/CLAUDE-FABLE-5-1 "), .perMillion(10, 50, 12.5, 0.25))
        XCTAssertEqual(ModelPricing.rate(for: "models/gemini-2.5-pro"), ModelPricing.rate(for: "gemini-2.5-pro"))
    }

    func testRequestContextThresholdIncludesCacheRead() throws {
        let at = try XCTUnwrap(ModelPricing.estimatedCost(model: "gpt-5.5", input: 2_000, output: 1_000, cacheWrite: 0, cacheRead: 270_000))
        XCTAssertEqual(at, 0.175, accuracy: 1e-12)
        let over = try XCTUnwrap(ModelPricing.estimatedCost(model: "gpt-5.5", input: 2_001, output: 1_000, cacheWrite: 0, cacheRead: 270_000))
        XCTAssertEqual(over, 0.33501, accuracy: 1e-12)
        // An older model does not inherit the newer model's long-context surcharge.
        XCTAssertEqual(try XCTUnwrap(ModelPricing.estimatedCost(model: "gpt-5.3-codex", input: 300_000, output: 0, cacheWrite: 0, cacheRead: 0)), 0.525, accuracy: 1e-12)
    }

    /// Official standard text rates. Flash-Lite is a different SKU from Flash;
    /// leaving it out of the table makes its cost Unavailable.
    func testGemini25FlashLiteUsesOfficialTextRates() throws {
        XCTAssertEqual(ModelPricing.rate(for: "gemini-2.5-flash-lite"), .perMillion(0.10, 0.40, 0, 0.01))
        XCTAssertEqual(ModelPricing.rate(for: "models/gemini-2.5-flash-lite"), .perMillion(0.10, 0.40, 0, 0.01))
        XCTAssertEqual(try XCTUnwrap(ModelPricing.estimatedCost(
            model: "gemini-2.5-flash-lite", input: 1_000_000, output: 0, cacheWrite: 0, cacheRead: 0)), 0.10, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(ModelPricing.estimatedCost(
            model: "gemini-2.5-flash-lite", input: 0, output: 1_000_000, cacheWrite: 0, cacheRead: 0)), 0.40, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(ModelPricing.estimatedCost(
            model: "gemini-2.5-flash-lite", input: 0, output: 0, cacheWrite: 0, cacheRead: 1_000_000)), 0.01, accuracy: 1e-12)
        XCTAssertNil(ModelPricing.estimatedCost(
            model: "gemini-2.5-flash-lite", input: 0, output: 0, cacheWrite: 1, cacheRead: 0),
                     "audio and cache-write rates are not in these logs")
        XCTAssertNil(ModelPricing.estimatedCost(
            model: "gemini-3-flash-lite", input: 1_000_000, output: 0, cacheWrite: 0, cacheRead: 0),
                     "an unknown lite id must not inherit Flash or Flash-Lite rates")
    }

    func testGeminiTextCacheAndLongContext() throws {
        XCTAssertEqual(ModelPricing.rate(for: "gemini-2.5-flash"), .perMillion(0.3, 2.5, 0, 0.03))
        let at = try XCTUnwrap(ModelPricing.estimatedCost(model: "gemini-2.5-pro", input: 100_000, output: 1_000, cacheWrite: 0, cacheRead: 100_000))
        XCTAssertEqual(at, 0.1475, accuracy: 1e-12)
        let over = try XCTUnwrap(ModelPricing.estimatedCost(model: "gemini-2.5-pro", input: 100_001, output: 1_000, cacheWrite: 0, cacheRead: 100_000))
        XCTAssertEqual(over, 0.2900025, accuracy: 1e-12)
    }

    func testUnsupportedCacheWriteRateIsUnavailableInsteadOfFree() throws {
        for model in ["gpt-5.5", "gpt-5.3-codex", "gemini-2.5-pro"] {
            XCTAssertNil(ModelPricing.estimatedCost(model: model, input: 0, output: 0, cacheWrite: 100_000, cacheRead: 0))
        }
        XCTAssertEqual(try XCTUnwrap(ModelPricing.estimatedCost(model: "gpt-6-astra", input: 0, output: 0,
                                                               cacheWrite: 100_000, cacheRead: 0)), 1.25, accuracy: 1e-12)
    }

    func testCacheWriteAndInvalidBuckets() throws {
        XCTAssertEqual(try XCTUnwrap(ModelPricing.estimatedCost(model: "gpt-5.6-luna", input: 100_000, output: 1_000, cacheWrite: 10_000, cacheRead: 100_000)), 0.0257, accuracy: 1e-12)
        XCTAssertNil(ModelPricing.estimatedCost(model: "gpt-5.5", input: -1, output: 0, cacheWrite: 0, cacheRead: 0))
        XCTAssertEqual(ModelPricing.estimatedCost(model: "gpt-5.5", input: 0, output: 0, cacheWrite: 0, cacheRead: 0), 0)
    }
}
