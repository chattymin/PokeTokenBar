import Foundation

/// Standard token rates in USD. These estimate API-equivalent usage, not subscription bills.
struct ModelRate: Equatable, Sendable {
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
    // Historical models absent from the upstream catalog. These six predate context tiers.
    private static let legacyRates: [String: ModelRate] = [
        "claude-opus-4-20250514":   .perMillion(15, 75, 18.75, 1.5),
        "claude-sonnet-4-20250514": .perMillion(3, 15, 3.75, 0.3),
        "gpt-5-codex":              .perMillion(1.25, 10, 0, 0.125),
        "gpt-5.1-codex":            .perMillion(1.25, 10, 0, 0.125),
        "gpt-5.2-codex":            .perMillion(1.75, 14, 0, 0.175),
        "gemini-2.0-flash":         .perMillion(0.10, 0.4, 0, 0.025),
    ]

    // SwiftPM supplies the resource bundle for development. The distributed .app
    // copies the same resource into Contents/Resources when assembling the bundle.
    private static let bundledCatalog: ModelPricingCatalog? = {
        let bundle = AppEnv.isBundledApp ? Bundle.main : Bundle.module
        guard let url = bundle.url(forResource: "model-prices", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? ModelPricingCatalog.decode(data)
    }()

    private static let catalogLock = NSLock()
    nonisolated(unsafe) private static var activeCatalog = bundledCatalog

    static func install(_ update: ModelPricingCatalog?) {
        let merged = update.map { bundledCatalog?.overlaying($0) ?? $0 } ?? bundledCatalog
        catalogLock.withLock { activeCatalog = merged }
    }

    // Only documented model identities and simple provider namespaces are normalized.
    // A model containing "gpt"/"opus" is not evidence that it shares another model's price.
    private static let aliases: [String: String] = [
        "gpt-5.6": "gpt-5.6-sol",
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

    // Google keeps these retired endpoints available by routing requests to their successors.
    // https://ai.google.dev/gemini-api/docs/deprecations#gemini-3-models
    private static let redirectedEndpoints = [
        "gemini-3.5-flash": "gemini-3.6-flash",
        "gemini-3.7-flash": "gemini-3.8-flash",
    ]

    private static func lookup(_ model: String) -> (ModelPricingCatalog?, String) {
        let catalog = catalogLock.withLock { activeCatalog }
        let id = ModelPricingCatalog.normalizedID(model)
        if let target = redirectedEndpoints[id] { return (catalog, target) }
        if let fallback = aliases[id], catalog?.contains(id) != true, legacyRates[id] == nil {
            return (catalog, fallback)
        }
        return (catalog, id)
    }

    /// Compatibility for callers that only need a numeric rate. New aggregation uses
    /// estimatedCost so an unknown model remains distinguishable from a genuine zero.
    static func rate(for model: String) -> ModelRate {
        let (catalog, key) = lookup(model)
        return catalog?.rate(for: key) ?? legacyRates[key] ?? .zero
    }

    /// Estimate each request before aggregation because its prompt size selects the price tier.
    static func estimatedCost(model: String, input: Int, output: Int,
                              cacheWrite: Int, cacheRead: Int) -> Double? {
        let (catalog, key) = lookup(model)
        if let catalog, catalog.contains(key) {
            return catalog.estimatedCost(model: key, input: input, output: output,
                                         cacheWrite: cacheWrite, cacheRead: cacheRead)
        }
        guard let rate = legacyRates[key], input >= 0, output >= 0, cacheWrite >= 0, cacheRead >= 0,
              cacheWrite == 0 || rate.cacheWrite > 0 else { return nil }
        return Double(input) * rate.input + Double(output) * rate.output
            + Double(cacheWrite) * rate.cacheWrite + Double(cacheRead) * rate.cacheRead
    }

    /// A model the table cannot price renders as "Unavailable" with no other trace — Opus 5.5
    /// went unnoticed until a screenshot. Log each unpriced identity once per process so a new
    /// model shows up in the log the first time a provider reports it.
    static func noteUnpriced(_ model: String) {
        guard firstUnpricedSighting(model) else { return }
        AppLog.write("Unpriced model: \(model) — its cost shows as Unavailable until a standard price is available")
    }

    /// True only the first time `model` is seen (normalized) — the dedupe behind `noteUnpriced`.
    static func firstUnpricedSighting(_ model: String) -> Bool {
        let key = ModelPricingCatalog.normalizedID(model)
        unpricedLock.lock(); defer { unpricedLock.unlock() }
        return unpricedSeen.insert(key).inserted
    }

    nonisolated(unsafe) private static var unpricedSeen: Set<String> = []
    private static let unpricedLock = NSLock()

    static func cost(model: String, input: Int, output: Int, cacheWrite: Int, cacheRead: Int) -> Double {
        estimatedCost(model: model, input: input, output: output,
                      cacheWrite: cacheWrite, cacheRead: cacheRead) ?? 0
    }
}
