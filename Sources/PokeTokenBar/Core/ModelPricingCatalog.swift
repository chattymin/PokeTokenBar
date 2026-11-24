import CoreFoundation
import Foundation

/// Standard text-token rates from the models.dev v1 API. Keys are exact, normalized model IDs.
struct ModelPricingCatalog: Equatable, Sendable {
    private enum DecodeError: Error {
        case incompleteCatalog
    }

    private enum Vendor: String, CaseIterable {
        case openai, anthropic, google

        func accepts(_ id: String) -> Bool {
            guard id.range(of: #"^[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?\z"#, options: .regularExpression) != nil
            else { return false }
            switch self {
            case .openai:
                return id.hasPrefix("gpt-") || id.hasPrefix("chatgpt-")
                    || id.range(of: #"^o[0-9]+(-|$)"#, options: .regularExpression) != nil
            case .anthropic:
                return id.hasPrefix("claude-")
            case .google:
                return (id.hasPrefix("gemini-") || id.hasPrefix("gemma-")) && !id.hasPrefix("gemini-embedding")
            }
        }
    }

    static func normalizedID(_ model: String) -> String {
        let id = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let slash = id.firstIndex(of: "/") else { return id }
        let prefix = id[..<slash]
        let name = String(id[id.index(after: slash)...])
        let vendor = Vendor(rawValue: prefix == "models" ? "google" : String(prefix))
        return vendor?.accepts(name) == true ? name : id
    }

    private struct Prices: Equatable, Sendable {
        private static let fields: Set<String> = ["input", "output", "cache_write", "cache_read", "input_audio", "reasoning"]
        let rate: ModelRate
        let hasCacheWrite: Bool
        let hasCacheRead: Bool

        init?(_ raw: [String: Any], ignoring extraFields: Set<String> = []) {
            guard Set(raw.keys).isSubset(of: Self.fields.union(extraFields)),
                  let input = ModelPricingCatalog.number(raw["input"]),
                  let output = ModelPricingCatalog.number(raw["output"]) else { return nil }
            let cacheWrite = ModelPricingCatalog.number(raw["cache_write"])
            let cacheRead = ModelPricingCatalog.number(raw["cache_read"])
            guard raw["cache_write"] == nil || cacheWrite != nil,
                  raw["cache_read"] == nil || cacheRead != nil else { return nil }
            // Media input is outside the text estimate. Thinking tokens share the output count.
            guard raw["input_audio"] == nil || ModelPricingCatalog.number(raw["input_audio"]) != nil,
                  raw["reasoning"] == nil || ModelPricingCatalog.number(raw["reasoning"]) == output else { return nil }
            rate = .perMillion(input, output, cacheWrite ?? 0, cacheRead ?? 0)
            hasCacheWrite = cacheWrite != nil
            hasCacheRead = cacheRead != nil
        }
    }

    private struct Band: Equatable, Sendable {
        let threshold: Int
        let prices: Prices
    }

    private struct Model: Equatable, Sendable {
        let base: Prices
        let bands: [Band]

        init?(_ raw: [String: Any], key: String) {
            guard let modalities = raw["modalities"] as? [String: [String]],
                  modalities["input"]?.contains("text") == true, modalities["output"] == ["text"],
                  let cost = raw["cost"] as? [String: Any],
                  let base = Prices(cost, ignoring: ["tiers", "context_over_200k"]) else { return nil }
            var bands: [Band] = []
            if let rawTiers = cost["tiers"] {
                guard let tiers = rawTiers as? [[String: Any]] else { return nil }
                var seenThresholds: Set<Int> = []
                for tier in tiers {
                    guard let condition = tier["tier"] as? [String: Any], condition.count == 2,
                          condition["type"] as? String == "context",
                          let size = ModelPricingCatalog.number(condition["size"]),
                          let threshold = Int(exactly: size), threshold > 0,
                          seenThresholds.insert(threshold).inserted,
                          let prices = Prices(tier, ignoring: ["tier"]) else { return nil }
                    bands.append(Band(threshold: threshold, prices: prices))
                }
                bands.sort { $0.threshold < $1.threshold }
            }
            if let legacy = cost["context_over_200k"] {
                guard let rawPrices = legacy as? [String: Any], let prices = Prices(rawPrices) else { return nil }
                if let first = bands.first {
                    // V1 also emits the first context band here, even when its threshold differs.
                    guard first.prices == prices else { return nil }
                } else {
                    // With no explicit band, accept only models with a documented 200K threshold.
                    guard ["gemini-2.5-pro", "gemini-3.1-pro-preview", "gemini-3.1-pro-preview-customtools"].contains(key)
                    else { return nil }
                    bands = [Band(threshold: 200_000, prices: prices)]
                }
            }
            self.base = base
            self.bands = bands
        }
    }

    private let models: [String: Model]

    /// Keep only the direct providers and fields used to estimate text-token costs on disk.
    static func compactData(from data: Data) throws -> Data {
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DecodeError.incompleteCatalog
        }
        var result: [String: Any] = [:]
        for vendor in Vendor.allCases {
            guard let provider = payload[vendor.rawValue] as? [String: Any],
                  provider["id"] as? String == vendor.rawValue,
                  let rows = provider["models"] as? [String: Any] else { throw DecodeError.incompleteCatalog }
            let models = rows.compactMapValues { value -> [String: Any]? in
                guard let row = value as? [String: Any] else { return nil }
                return row.filter { ["id", "modalities", "cost"].contains($0.key) }
            }
            result[vendor.rawValue] = ["id": vendor.rawValue, "models": models]
        }
        return try JSONSerialization.data(withJSONObject: result)
    }

    static func decode(_ data: Data) throws -> ModelPricingCatalog {
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DecodeError.incompleteCatalog
        }
        var models: [String: Model] = [:]
        var eligibleKeys: [Vendor: Set<String>] = [:]
        var declaredKeys: Set<String> = []
        var collisions: Set<String> = []
        for vendor in Vendor.allCases {
            guard let provider = payload[vendor.rawValue] as? [String: Any],
                  provider["id"] as? String == vendor.rawValue,
                  let rows = provider["models"] as? [String: Any] else { throw DecodeError.incompleteCatalog }
            for (key, value) in rows {
                guard let row = value as? [String: Any], row["id"] as? String == key else { continue }
                if !declaredKeys.insert(key).inserted { collisions.insert(key) }
                guard vendor.accepts(key), let model = Model(row, key: key) else { continue }
                models[key] = model
                eligibleKeys[vendor, default: []].insert(key)
            }
        }
        guard Vendor.allCases.allSatisfy({ eligibleKeys[$0]?.isSubset(of: collisions) == false })
        else { throw DecodeError.incompleteCatalog }
        for key in collisions { models.removeValue(forKey: key) }
        return ModelPricingCatalog(models: models)
    }

    func overlaying(_ updated: Self) -> Self {
        Self(models: models.merging(updated.models) { _, new in new })
    }

    func contains(_ key: String) -> Bool { models[key] != nil }

    func rate(for key: String) -> ModelRate? { models[key]?.base.rate }

    func estimatedCost(model key: String, input: Int, output: Int, cacheWrite: Int, cacheRead: Int) -> Double? {
        guard let model = models[key], input >= 0, output >= 0, cacheWrite >= 0, cacheRead >= 0 else { return nil }
        let prompt = Double(input) + Double(cacheWrite) + Double(cacheRead)
        let band = model.bands.last { prompt > Double($0.threshold) }
        let prices = band?.prices ?? model.base
        guard cacheWrite == 0 || prices.hasCacheWrite, cacheRead == 0 || prices.hasCacheRead else { return nil }
        let rate = prices.rate
        let total = Double(input) * rate.input + Double(output) * rate.output
            + Double(cacheWrite) * rate.cacheWrite + Double(cacheRead) * rate.cacheRead
        return total.isFinite ? total : nil
    }

    private static func number(_ value: Any?) -> Double? {
        guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() else { return nil }
        let amount = value.doubleValue
        return amount.isFinite && amount >= 0 ? amount : nil
    }
}
