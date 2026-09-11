import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

private struct CostTestProvider: UsageProvider {
    let id: String
    var displayName: String { id }
    let entries: [LocalUsageReader.Entry]
    func fetchDaily() async throws -> DailyUsage? {
        LocalUsageReader.daily(entries: entries, localDay: LocalUsageReader.todayKey())
    }
    func fetchEnrichment() async -> ProviderEnrichment { .local(entries: entries) }
}

final class UsageCostTests: XCTestCase {
    private func entry(_ model: String = "gpt-5.5", cost: Double? = nil,
                       estimated: Bool? = nil, unavailable: Bool? = nil) -> LocalUsageReader.Entry {
        let now = Date()
        return .init(id: UUID().uuidString, date: now, localDay: LocalUsageReader.todayKey(),
                     model: model, input: 1_000, output: 100, cacheWrite: 0, cacheRead: 500,
                     explicitCost: cost, costIsEstimate: estimated, costUnavailable: unavailable)
    }

    func testExplicitZeroIsNotMissingAndNeverFallsBackToModelRate() throws {
        let zero = try XCTUnwrap(LocalUsageReader.daily(entries: [entry(cost: 0)], localDay: LocalUsageReader.todayKey()))
        XCTAssertEqual(zero.totalCost, 0)
        XCTAssertEqual(zero.costCoverage, .source)
        XCTAssertEqual(zero.usageCost.text(L(.en)), "$0.00")
        let missing = try XCTUnwrap(LocalUsageReader.daily(entries: [entry()], localDay: LocalUsageReader.todayKey()))
        XCTAssertEqual(missing.totalCost, 0.00825, accuracy: 1e-12)
        XCTAssertEqual(missing.costCoverage, .estimate)
        XCTAssertEqual(missing.usageCost.text(L(.en)), "≈$0.01")
    }

    func testUnavailableAndPartialCostsSurviveEveryAggregation() throws {
        let known = entry()
        let unknown = entry("new-model")
        let unavailable = try XCTUnwrap(LocalUsageReader.daily(entries: [unknown], localDay: known.localDay))
        XCTAssertEqual(unavailable.totalTokens, unknown.total)
        XCTAssertEqual(unavailable.costCoverage, .unavailable)
        XCTAssertEqual(unavailable.usageCost.text(L(.ko)), "계산 불가")
        XCTAssertEqual(unavailable.usageCost.text(L(.en), compact: true), "$—")
        let entries = [known, unknown, entry(cost: 0)]
        let daily = try XCTUnwrap(LocalUsageReader.daily(entries: entries, localDay: known.localDay))
        let enrichment = ProviderEnrichment.local(entries: entries)
        let expected = CostCoverage(reported: true, estimated: true, unknown: true)
        XCTAssertEqual(daily.costCoverage, expected)
        XCTAssertEqual(enrichment.weekTotal?.costCoverage, expected)
        XCTAssertEqual(enrichment.monthTotal?.costCoverage, expected)
        XCTAssertEqual(enrichment.activeBlock?.costCoverage, expected)
        XCTAssertEqual(enrichment.monthDaily?.last?.costCoverage, expected)
        XCTAssertEqual(PeriodUsage(period: "test", daily: [daily]).costCoverage, expected)
        XCTAssertEqual(daily.totalTokens, entries.reduce(0) { $0 + $1.total })
        XCTAssertTrue(daily.usageCost.text(L(.en)).hasSuffix("+"))
        XCTAssertTrue(daily.usageCost.explanation(L(.en)).contains("Some usage"))
    }

    func testZeroUsageDoesNotTurnUnknownCostIntoPartialZero() throws {
        let unknown = entry("not-priced")
        let empty = LocalUsageReader.Entry(id: "empty", date: Date(), localDay: unknown.localDay,
                                          model: "gpt-5.5", input: 0, output: 0, cacheWrite: 0, cacheRead: 0)
        let daily = try XCTUnwrap(LocalUsageReader.daily(entries: [empty, unknown], localDay: unknown.localDay))
        XCTAssertEqual(daily.costCoverage, .unavailable)
        XCTAssertEqual(daily.usageCost.text(L(.en)), "Unavailable")
    }

    func testUnrecoverableBucketSplitAndInvalidSourceCost() throws {
        for bad in [Double.nan, .infinity, -1] {
            let value = try XCTUnwrap(LocalUsageReader.daily(entries: [entry(cost: bad)], localDay: LocalUsageReader.todayKey()))
            XCTAssertEqual(value.costCoverage, .estimate)
            XCTAssertTrue(value.totalCost.isFinite)
        }
        let totalOnly = entry(unavailable: true)
        XCTAssertEqual(LocalUsageReader.daily(entries: [totalOnly], localDay: totalOnly.localDay)?.costCoverage, .unavailable)
        let reported = entry(cost: 0.5, unavailable: true)
        XCTAssertEqual(LocalUsageReader.daily(entries: [reported], localDay: reported.localDay)?.costCoverage, .source)
        let sourceEstimate = entry(cost: 0, estimated: true)
        XCTAssertEqual(LocalUsageReader.daily(entries: [sourceEstimate], localDay: sourceEstimate.localDay)?.costCoverage, .estimate)
    }

    func testLegacyDecodingAndEntryMetadataRoundTrip() throws {
        let decoder = JSONDecoder()
        let old = Data(#"{"date":"2026-09-11","totalTokens":500,"totalCost":0}"#.utf8)
        XCTAssertEqual(try decoder.decode(DailyUsage.self, from: old).costCoverage, .unavailable)
        XCTAssertEqual(try decoder.decode(PeriodUsage.self, from: old).costCoverage, .unavailable)
        XCTAssertEqual(try decoder.decode(BlockUsage.self, from: old).costCoverage, .unavailable)
        let positive = Data(#"{"totalTokens":500,"totalCost":1,"costUSD":1}"#.utf8)
        XCTAssertEqual(try decoder.decode(DailyUsage.self, from: positive).costCoverage, .estimate)
        XCTAssertEqual(try decoder.decode(PeriodUsage.self, from: positive).costCoverage, .estimate)
        XCTAssertEqual(try decoder.decode(BlockUsage.self, from: positive).costCoverage, .estimate)
        let empty = Data("{}".utf8)
        XCTAssertEqual(try decoder.decode(DailyUsage.self, from: empty).costCoverage, .empty)
        let value = entry(cost: 0, estimated: true, unavailable: true)
        let restored = try decoder.decode(LocalUsageReader.Entry.self, from: JSONEncoder().encode(value))
        XCTAssertEqual(restored.explicitCost, 0)
        XCTAssertEqual(restored.costIsEstimate, true)
        XCTAssertEqual(restored.costUnavailable, true)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
        object.removeValue(forKey: "costIsEstimate")
        object.removeValue(forKey: "costUnavailable")
        let legacy = try decoder.decode(LocalUsageReader.Entry.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(legacy.costIsEstimate)
        XCTAssertNil(legacy.costUnavailable)
    }

    func testOpenCodeExplicitZeroAndMissingCostThroughParser() throws {
        var row: [String: Any] = ["id": "test", "providerID": "openai", "modelID": "gpt-5.5", "time": ["created": Date().timeIntervalSince1970 * 1_000],
                                   "tokens": ["input": 1_000, "output": 100], "cost": 0]
        let zero = try XCTUnwrap(LocalAdditionalUsageReader.parseOpenCodeMessage(row, fallbackID: "test"))
        XCTAssertEqual(zero.explicitCost, 0)
        XCTAssertEqual(LocalUsageReader.daily(entries: [zero], localDay: zero.localDay)?.costCoverage, .source)
        row.removeValue(forKey: "cost")
        let missing = try XCTUnwrap(LocalAdditionalUsageReader.parseOpenCodeMessage(row, fallbackID: "test"))
        XCTAssertNil(missing.explicitCost)
        XCTAssertEqual(LocalUsageReader.daily(entries: [missing], localDay: missing.localDay)?.costCoverage, .estimate)
    }

    func testCursorLocalBubbleWithoutCacheSplitIsUnavailable() throws {
        let bubble: [String: Any] = ["tokenCount": ["inputTokens": 1000, "outputTokens": 100],
                                     "modelType": "gpt-5.5", "createdAt": ISO8601DateFormatter().string(from: Date())]
        let value = try XCTUnwrap(LocalAdditionalUsageReader.parseCursorBubble(bubble, key: "test", modifiedSince: .distantPast))
        XCTAssertEqual(LocalUsageReader.daily(entries: [value], localDay: value.localDay)?.costCoverage, .unavailable)
    }

    func testCodexProviderPricesColdAndWarmCacheAndMarksTotalOnlyUnknown() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CostCodex-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let stamp = ISO8601DateFormatter().string(from: Date())
        let rows: [[String: Any]] = [
            ["timestamp": stamp, "type": "turn_context", "payload": ["model": "gpt-5.5"]],
            ["timestamp": stamp, "type": "event_msg", "payload": ["type": "token_count", "info": ["last_token_usage": ["input_tokens": 1_500, "cached_input_tokens": 500, "output_tokens": 100, "total_tokens": 1_600]]]],
            ["timestamp": stamp, "type": "event_msg", "payload": ["type": "token_count", "info": ["last_token_usage": ["total_tokens": 70]]]]
        ]
        let data = try rows.map { String(decoding: try JSONSerialization.data(withJSONObject: $0), as: UTF8.self) }.joined(separator: "\n") + "\n"
        try data.write(to: root.appendingPathComponent("rollout-test.jsonl"), atomically: true, encoding: .utf8)
        let cacheURL = root.appendingPathComponent("cache.json")
        for _ in 0..<2 {
            let cache = LocalUsageCache(codexRoots: [root], fileURL: cacheURL)
            let provider = LocalCodexProvider(cache: cache)
            let fetched = try await provider.fetchDaily()
            let daily = try XCTUnwrap(fetched)
            XCTAssertEqual(daily.totalTokens, 1_670)
            XCTAssertEqual(daily.totalCost, 0.00825, accuracy: 1e-12)
            XCTAssertEqual(daily.costCoverage, CostCoverage(estimated: true, unknown: true))
            let enrichment = await provider.fetchEnrichment()
            XCTAssertEqual(enrichment.monthTotal?.costCoverage, daily.costCoverage)
            XCTAssertEqual(enrichment.weekTotal?.totalCost, daily.totalCost)
        }
    }

    @MainActor
    func testStoreCarriesCoverageToMenuAndDailyTrend() async throws {
        let suite = "CostStore-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "disableKeychainAccess")
        defaults.set(false, forKey: "statusChecksEnabled")
        defaults.set(true, forKey: "showCostInMenu")
        let providers = [CostTestProvider(id: "priced", entries: [entry()]), CostTestProvider(id: "unknown", entries: [entry("new-model")])]
        let store = UsageStore(providers: providers, autoRefresh: false, defaults: defaults)
        await store.refresh(scheduleEmptyRetry: false)
        let expected = CostCoverage(estimated: true, unknown: true)
        XCTAssertEqual(store.todayUsageCost.coverage, expected)
        XCTAssertEqual(store.weekUsageCost.coverage, expected)
        XCTAssertEqual(store.monthUsageCost.coverage, expected)
        XCTAssertEqual(store.monthDailyTotals.last?.costCoverage, expected)
        XCTAssertTrue(store.menuTitle.contains("≈"))
        XCTAssertTrue(store.menuTitle.contains("+"))
        XCTAssertEqual(store.todayTotalTokens, 3_200)
    }

    func testOptionalLocalCodexCostAudit() async throws {
        guard ProcessInfo.processInfo.environment["PTB_COST_AUDIT"] == "1" else {
            throw XCTSkip("Set PTB_COST_AUDIT=1 for a read-only local-log audit")
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CostAudit-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = LocalUsageCache(fileURL: root.appendingPathComponent("cache.json"))
        let entries = await cache.codexEntries(modifiedSince: Calendar.current.startOfDay(for: Date()))
        let today = entries.filter { $0.localDay == LocalUsageReader.todayKey() }
        let daily = try XCTUnwrap(LocalUsageReader.daily(entries: today, localDay: LocalUsageReader.todayKey()))
        XCTAssertEqual(daily.totalTokens, today.reduce(0) { $0 + $1.total })
        XCTAssertGreaterThan(daily.totalCost, 0)
        XCTAssertTrue(daily.costCoverage.estimated)
        let unknown = today.filter {
            $0.costUnavailable == true || ModelPricing.estimatedCost(model: $0.model, input: $0.input,
                output: $0.output, cacheWrite: $0.cacheWrite, cacheRead: $0.cacheRead) == nil
        }.reduce(0) { $0 + $1.total }
        print("Local cost audit: tokens=\(daily.totalTokens), unpricedTokens=\(unknown), cost=\(daily.usageCost.text(L(.en)))")
    }

    @MainActor
    func testNativeCostRenderingAndAllLocalizedStates() throws {
        let examples = [UsageCost(amount: 12.5, coverage: .estimate), UsageCost(amount: 0, coverage: .source),
                        UsageCost(coverage: .unavailable), UsageCost(amount: 12.5, coverage: CostCoverage(estimated: true, unknown: true))]
        for language in AppLanguage.allCases {
            let l = L(language)
            for cost in examples {
                XCTAssertFalse(cost.text(l).isEmpty)
                XCTAssertFalse(cost.explanation(l).isEmpty)
            }
            let view = VStack(alignment: .leading, spacing: 8) {
                Text(l.costLegend)
                ForEach(examples.indices, id: \.self) { i in UsageCostText(cost: examples[i], l: l) }
            }.padding(16).frame(width: 320).background(Color.white).foregroundStyle(.black)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.cgImage)
            XCTAssertGreaterThan(image.height, 160)
            XCTAssertEqual(image.width, 640)
            if let output = ProcessInfo.processInfo.environment["PTB_COST_PREVIEW"], language == .ko {
                let bitmap = NSBitmapImageRep(cgImage: image)
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: output))
            }
        }
    }
}
