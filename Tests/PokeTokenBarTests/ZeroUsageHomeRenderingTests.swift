import AppKit
import SwiftUI
import Vision
import XCTest
@testable import PokeTokenBar

private struct QuietHomeProvider: UsageProvider {
    let id = "fixture"
    let displayName = "Fixture"
    let reportsCost = false
    let enrichment: ProviderEnrichment
    func fetchDaily() async throws -> DailyUsage? { nil }
    func fetchEnrichment() async -> ProviderEnrichment { enrichment }
}

private struct QuietHomeClaude: ClaudeLimitsProviding {
    func fetch(allowKeychainPrompt: Bool) async throws -> LimitStatus {
        throw LimitsError.keychainInteractionNotAllowed
    }
}
private struct QuietHomeCodex: CodexLimitsProviding {
    func fetch() async throws -> CodexRateLimitStatus? { nil }
}
private struct QuietHomeAntigravity: AntigravityLimitsProviding {
    func fetch(allowKeychainPrompt: Bool) async throws -> AntigravityRateLimitStatus {
        throw LimitsError.keychainInteractionNotAllowed
    }
}
private struct QuietHomeCursor: CursorLimitsProviding {
    func fetch() async throws -> CursorRateLimitStatus? { nil }
}
private struct QuietHomeStatus: ProviderStatusProviding {
    func fetch() async -> [String: ProviderStatus] { [:] }
}
private struct QuietHomePokemon: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine {
        EvoLine(baseID: 129, tree: EvoNode(speciesID: 129, children: [EvoNode(speciesID: 130, children: [])]),
                rarity: .common, names: [129: ["ko": "잉어킹"], 130: ["ko": "갸라도스"]])
    }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

/// Render the production home after the real refresh pipeline returns no usage today.
/// Optional PNG output is fixture data, isolated from the user's saves and credentials.
@MainActor
final class ZeroUsageHomeRenderingTests: XCTestCase {
    func testQuietDayKeepsHistoricalGraphVisible() async throws {
        try await render(history: true)
    }

    func testEmptyHistoryStillShowsZeroPeriodSummaries() async throws {
        try await render(history: false)
    }

    private func render(history: Bool) async throws {
        let suite = "QuietHome-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(suite).json")
        defer { try? FileManager.default.removeItem(at: file) }
        var state = CompanionState()
        state.language = .ko
        state.active = MonState(baseID: 129, pathIDs: [129, 130], stageIndex: 1,
                                usedAtStage: 170_100_000, rarity: .common, totalForms: 2, nature: .hardy)
        try JSONEncoder().encode(state).write(to: file)
        let companion = CompanionStore(provider: QuietHomePokemon(), fileURL: file, defaults: defaults)
        companion.update(todayTokensByProvider: [:], todayDate: LocalUsageReader.todayKey(), monthTotal: 0,
                         burnTier: .idle, limitWarning: false, hasUsageData: false)
        let formatter = LocalUsageReader.localDayFormatter()
        let now = Date()
        let monthStart = LocalUsageReader.startOfMonth(now)
        let day = Calendar.current.component(.day, from: now)
        let series = (0..<day).map { offset in
            let date = Calendar.current.date(byAdding: .day, value: offset, to: monthStart)!
            let tokens = history && offset < day - 1 ? (offset % 6 + 1) * 230_000 : 0
            return DailyUsage(date: formatter.string(from: date), inputTokens: tokens, outputTokens: 0,
                              cacheCreationTokens: 0, cacheReadTokens: 0, totalTokens: tokens, totalCost: 0)
        }
        let weekKey = formatter.string(from: LocalUsageReader.startOfWeek(now))
        let enrichment = ProviderEnrichment(blocksOK: true,
            weekTotal: PeriodUsage(period: weekKey, daily: series.filter { $0.date >= weekKey }),
            monthTotal: PeriodUsage(period: LocalUsageReader.monthKey(now), daily: series),
            monthDaily: series, periodsOK: true)
        let store = UsageStore(providers: [QuietHomeProvider(enrichment: enrichment)],
            claudeLimitsProvider: QuietHomeClaude(), discoverClaudeConfigDirs: { [] },
            readDefaultIdentity: { nil }, claudeUsageEntries: { _ in [] },
            codexLimitsProvider: QuietHomeCodex(), antigravityLimitsProvider: QuietHomeAntigravity(),
            cursorLimitsProvider: QuietHomeCursor(), statusProvider: QuietHomeStatus(),
            autoRefresh: false, defaults: defaults)
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(store.todayTotalTokens, 0)
        XCTAssertEqual(store.monthTotalTokens, series.reduce(0) { $0 + $1.totalTokens })

        let height = 604.0
        let host = NSHostingView(rootView: PopoverView()
            .environment(store).environment(companion).environment(UpdateChecker(defaults: defaults))
            .environment(PopoverNavigation()).environment(\.colorScheme, .dark)
            .environment(\.controlActiveState, .active)
            .frame(width: PopoverMetrics.width, height: height)
            .background(Color(nsColor: NSColor(calibratedWhite: 0.07, alpha: 1))))
        host.frame = NSRect(x: 0, y: 0, width: PopoverMetrics.width, height: height)
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: PopoverMetrics.width, height: height),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(500))
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let request = VNRecognizeTextRequest()
        request.recognitionLanguages = ["ko-KR", "en-US"]
        request.recognitionLevel = .accurate
        try VNImageRequestHandler(cgImage: XCTUnwrap(bitmap.cgImage)).perform([request])
        let text = request.results?.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ") ?? ""
        let normalizedText = text.replacingOccurrences(of: " ", with: "")
        for label in [companion.l.todayTokens, companion.l.thisWeek, companion.l.thisMonth] {
            XCTAssertTrue(normalizedText.contains(label.replacingOccurrences(of: " ", with: "")),
                          "Missing visible \(label): \(text)")
        }
        if history && day > 1 {
            XCTAssertTrue(normalizedText.contains(companion.l.dailyTrend.replacingOccurrences(of: " ", with: "")),
                          "Historical chart missing: \(text)")
        } else {
            XCTAssertFalse(normalizedText.contains(companion.l.dailyTrend.replacingOccurrences(of: " ", with: "")),
                           "Empty history must not invent a chart")
        }
        if let output = ProcessInfo.processInfo.environment["PTB_ZERO_USAGE_SCREENSHOT_DIR"] {
            let directory = URL(fileURLWithPath: output)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let name = history ? "ko-zero-today-with-history.png" : "ko-zero-all-periods.png"
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: directory.appendingPathComponent(name))
        }
    }
}
