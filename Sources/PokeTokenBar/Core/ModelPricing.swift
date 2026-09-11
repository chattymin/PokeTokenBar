import Foundation

/// Standard token rates in USD. These estimate API-equivalent usage, not subscription bills.
struct ModelRate: Equatable {
    let input: Double        // USD per token
    let output: Double
    let cacheWrite: Double   // cache creation
    let cacheRead: Double

    static let zero = ModelRate(input: 0, output: 0, cacheWrite: 0, cacheRead: 0)

    /// USD per **million** tokens 로 선언(가독성) → per-token 으로 변환.
    static func perMillion(_ input: Double, _ output: Double, _ cacheWrite: Double, _ cacheRead: Double) -> ModelRate {
        ModelRate(input: input / 1_000_000, output: output / 1_000_000,
                  cacheWrite: cacheWrite / 1_000_000, cacheRead: cacheRead / 1_000_000)
    }
}

enum ModelPricing {
    /// Standard API prices, checked 2026-09-11: https://developers.openai.com/api/docs/pricing
    /// Historical GPT rates: https://developers.openai.com/api/docs/models/<model-id>
    /// The table is a current-price estimate, not a historical invoice ledger.
    static let table: [String: ModelRate] = [
        "claude-opus-4-20250514":     .perMillion(15, 75, 18.75, 1.5),
        "claude-sonnet-4-20250514":   .perMillion(3, 15, 3.75, 0.3),
        "claude-sonnet-4-5-20250929": .perMillion(3, 15, 3.75, 0.3),
        "claude-opus-4-8":            .perMillion(5, 25, 6.25, 0.5),
        "claude-opus-4-7":            .perMillion(5, 25, 6.25, 0.5),
        "claude-sonnet-4-6":          .perMillion(3, 15, 3.75, 0.3),
        "claude-haiku-4-5-20251001":  .perMillion(1, 5, 1.25, 0.1),
        "claude-fable-5":             .perMillion(10, 50, 12.5, 1.0), // LiteLLM 스냅샷 가격 등재됨(2026-08) — 기존 미가격 $0 플레이스홀더 대체
        // Fable 5.1: same base rates as Fable 5, cache read cut to $0.25/MTok (0.025× input).
        "claude-fable-5-1":           .perMillion(10, 50, 12.5, 0.25),
        "gpt-6-astra":                .perMillion(10, 50, 12.5, 1),
        "gpt-5.6-sol":                .perMillion(4, 20, 5, 0.4),
        "gpt-5.6-terra":              .perMillion(2, 12, 2.5, 0.2),
        "gpt-5.6-luna":               .perMillion(0.2, 1.2, 0.25, 0.02),
        "gpt-5":                      .perMillion(1.25, 10, 0, 0.125),
        "gpt-5-codex":                .perMillion(1.25, 10, 0, 0.125),
        "gpt-5.1":                    .perMillion(1.25, 10, 0, 0.125),
        "gpt-5.1-codex":              .perMillion(1.25, 10, 0, 0.125),
        "gpt-5.2":                    .perMillion(1.75, 14, 0, 0.175),
        "gpt-5.2-codex":              .perMillion(1.75, 14, 0, 0.175),
        "gpt-5.3-codex":              .perMillion(1.75, 14, 0, 0.175),
        "gpt-5.4":                    .perMillion(2.5, 15, 0, 0.25),
        "gpt-5.5":                    .perMillion(5, 30, 0, 0.5),
        // Text token rates: https://ai.google.dev/gemini-api/docs/pricing
        // Cache storage duration and audio rates cannot be recovered from these logs.
        "gemini-2.5-pro":             .perMillion(1.25, 10, 0, 0.125),
        "gemini-2.5-flash":           .perMillion(0.30, 2.5, 0, 0.03),
        "gemini-2.0-flash":           .perMillion(0.10, 0.4, 0, 0.025),
    ]

    // Only documented model identities and simple provider namespaces are normalized.
    // A model containing "gpt"/"opus" is not evidence that it shares another model's price.
    private static let aliases: [String: String] = [
        "claude-sonnet-4": "claude-sonnet-4-20250514",
        "claude-opus-4": "claude-opus-4-20250514",
        "claude-sonnet-4-5": "claude-sonnet-4-5-20250929",
        "claude-haiku-4-5": "claude-haiku-4-5-20251001",
        "gpt-5-2025-08-07": "gpt-5",
        "gpt-5.1-2025-11-13": "gpt-5.1",
        "gpt-5.2-2025-12-11": "gpt-5.2",
        "gpt-5.4-2026-03-05": "gpt-5.4",
        "gpt-5.5-2026-04-23": "gpt-5.5",
    ]

    private static func modelKey(_ model: String) -> String {
        var key = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for prefix in ["openai/", "anthropic/", "google/", "models/"] where key.hasPrefix(prefix) {
            key = String(key.dropFirst(prefix.count))
            break
        }
        return aliases[key] ?? key
    }

    /// Compatibility for callers that only need a numeric rate. New aggregation uses
    /// estimatedCost so an unknown model remains distinguishable from a genuine zero.
    static func rate(for model: String) -> ModelRate { table[modelKey(model)] ?? .zero }

    /// One request's disjoint token buckets. Never pass daily/session aggregates here:
    /// request size controls long-context pricing. Total-only logs cannot reconstruct
    /// the bucket split; callers must mark those estimates as unavailable.
    /// Excludes Fast/Batch/Flex, regional uplift, tools, storage and subscription terms.
    /// In particular Codex's Astra allowance differs from this API-equivalent estimate.
    static func estimatedCost(model: String, input: Int, output: Int,
                              cacheWrite: Int, cacheRead: Int) -> Double? {
        let key = modelKey(model)
        guard let r = table[key], input >= 0, output >= 0, cacheWrite >= 0, cacheRead >= 0 else { return nil }
        let prompt = Double(input) + Double(cacheRead) + Double(cacheWrite)
        let longContext = ["gpt-6-astra", "gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna",
                           "gpt-5.5", "gpt-5.4"].contains(key) && prompt > 272_000
            || key == "gemini-2.5-pro" && prompt > 200_000
        let inputMultiplier = longContext ? 2.0 : 1.0
        let outputMultiplier = longContext ? 1.5 : 1.0
        return (Double(input) * r.input + Double(cacheWrite) * r.cacheWrite
                + Double(cacheRead) * r.cacheRead) * inputMultiplier
            + Double(output) * r.output * outputMultiplier
    }

    static func cost(model: String, input: Int, output: Int, cacheWrite: Int, cacheRead: Int) -> Double {
        estimatedCost(model: model, input: input, output: output,
                      cacheWrite: cacheWrite, cacheRead: cacheRead) ?? 0
    }
}
