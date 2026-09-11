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

    func testGeminiTextCacheAndLongContext() throws {
        XCTAssertEqual(ModelPricing.rate(for: "gemini-2.5-flash"), .perMillion(0.3, 2.5, 0, 0.03))
        let at = try XCTUnwrap(ModelPricing.estimatedCost(model: "gemini-2.5-pro", input: 100_000, output: 1_000, cacheWrite: 0, cacheRead: 100_000))
        XCTAssertEqual(at, 0.1475, accuracy: 1e-12)
        let over = try XCTUnwrap(ModelPricing.estimatedCost(model: "gemini-2.5-pro", input: 100_001, output: 1_000, cacheWrite: 0, cacheRead: 100_000))
        XCTAssertEqual(over, 0.2900025, accuracy: 1e-12)
    }

    func testCacheWriteAndInvalidBuckets() throws {
        XCTAssertEqual(try XCTUnwrap(ModelPricing.estimatedCost(model: "gpt-5.6-luna", input: 100_000, output: 1_000, cacheWrite: 10_000, cacheRead: 100_000)), 0.0257, accuracy: 1e-12)
        XCTAssertNil(ModelPricing.estimatedCost(model: "gpt-5.5", input: -1, output: 0, cacheWrite: 0, cacheRead: 0))
        XCTAssertEqual(ModelPricing.estimatedCost(model: "gpt-5.5", input: 0, output: 0, cacheWrite: 0, cacheRead: 0), 0)
    }
}
