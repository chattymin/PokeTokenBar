import AppKit
import SwiftUI
import Vision
import XCTest
@testable import PokeTokenBar

private struct AccountRenderLocalUsage: UsageProvider {
    let id = "codex"
    let displayName = "Codex"
    let reportsCost = false
    let tokens: Int
    func fetchDaily() async throws -> DailyUsage? {
        guard tokens > 0 else { return nil }
        return DailyUsage(date: LocalUsageReader.todayKey(), inputTokens: tokens, outputTokens: 0,
                          cacheCreationTokens: 0, cacheReadTokens: 0, totalTokens: tokens, totalCost: 0)
    }
    func fetchEnrichment() async -> ProviderEnrichment { ProviderEnrichment() }
}
private struct AccountRenderFailure: CodexAccountUsageProviding {
    func fetch() async throws -> CodexAccountUsage? { throw URLError(.notConnectedToInternet) }
}
private struct AccountRenderReport: CodexAccountUsageProviding {
    let usage: CodexAccountUsage
    func fetch() async throws -> CodexAccountUsage? { usage }
}
private struct AccountRenderClaude: ClaudeLimitsProviding {
    func fetch(allowKeychainPrompt: Bool) async throws -> LimitStatus {
        throw LimitsError.keychainInteractionNotAllowed
    }
}
private struct AccountRenderCodex: CodexLimitsProviding {
    func fetch() async throws -> CodexRateLimitStatus? { nil }
}
private struct AccountRenderAntigravity: AntigravityLimitsProviding {
    func fetch(allowKeychainPrompt: Bool) async throws -> AntigravityRateLimitStatus {
        throw LimitsError.keychainInteractionNotAllowed
    }
}
private struct AccountRenderCursor: CursorLimitsProviding {
    func fetch() async throws -> CursorRateLimitStatus? { nil }
}
private struct AccountRenderStatus: ProviderStatusProviding {
    func fetch() async -> [String: ProviderStatus] { [:] }
}
private struct AccountRenderPokemon: PokeProviding {
    func line(baseSpeciesID: Int) async throws -> EvoLine { throw URLError(.notConnectedToInternet) }
    func baseSpeciesIndex() async throws -> [BaseSpecies] { [] }
    func baseSpecies(id: Int) async throws -> BaseSpecies? { nil }
}

/// Renders the production account view and home at their real widths. All counters, sources and saves are synthetic fixtures.
@MainActor
final class CodexAccountUsageRenderingTests: XCTestCase {
    private let fixture = CodexAccountUsage(
        summary: .init(lifetimeTokens: 5_000_000_001, peakDailyTokens: 700_000_000,
                       longestRunningTurnSec: 9_000, currentStreakDays: 30, longestStreakDays: 30),
        dailyUsageBuckets: [.init(startDate: "2026-10-05", tokens: 500_000_000),
                            .init(startDate: "2026-10-06", tokens: 700_000_000),
                            .init(startDate: "2026-10-07", tokens: 70_000_000)])

    func testSourceDateAndLargeLifetimeFitAndDailyReportsExpand() async throws {
        for language in [AppLanguage.en, .ko, .ru] {
            let l = L(language)
            let view = CodexAccountUsageSection(usage: fixture, updatedAt: nil, isUnavailable: false,
                                               refreshFailed: false, l: l)
                .frame(width: PopoverMetrics.scrollContentWidth, alignment: .leading)
                .padding(PopoverMetrics.padding)
            let (host, window) = mount(view, language: language, height: 420)
            defer { window.close() }
            let (bitmap, observations) = try await capture(host: host, language: language)
            let text = joined(observations)
            assertVisible(l.accountUsageTitle, in: text)
            assertVisible(l.accountUsageLifetime, in: text)
            assertVisible("2026-10-07", in: text)
            assertVisibleDigits("5000000001", in: text)
            try save(bitmap, named: "\(language.rawValue)-account-success.png")

            let history = try XCTUnwrap(observations.first {
                normalized($0.topCandidates(1).first?.string ?? "")
                    .contains(normalized(l.accountUsageDailyHistory))
            }, "Daily disclosure must be visible before opening: \(text)")
            // Native events exercise the production DisclosureGroup, rather than its view model.
            let location = NSPoint(x: PopoverMetrics.padding + 9,
                                   y: history.boundingBox.midY * host.bounds.height)
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: location,
                    modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                    clickCount: 1, pressure: 1))
                window.sendEvent(event)
            }
            let (expanded, expandedObservations) = try await capture(host: host, language: language)
            let expandedText = joined(expandedObservations)
            assertVisible("2026-10-05", in: expandedText)
            assertVisibleDigits("700000000", in: expandedText)
            assertVisible(l.accountUsageDatesHint, in: expandedText)
            try save(expanded, named: "\(language.rawValue)-account-history-expanded.png")
        }
    }

    func testHomeKeepsLastReportAfterFailureWithoutChangingLocalTokens() async throws {
        try await renderHome(localTokens: 12_345_678, failing: true, language: .en)
    }

    func testHomeShowsAccountReportWithoutAnyLocalProviders() async throws {
        try await renderHome(localTokens: 0, failing: false, language: .ko)
    }

    func testMissingAccountCountersRenderUnavailableWithoutInventingZero() async throws {
        let l = L(.en)
        let view = CodexAccountUsageSection(usage: nil,
                                           updatedAt: nil, isUnavailable: true, refreshFailed: false, l: l)
            .frame(width: PopoverMetrics.scrollContentWidth, alignment: .leading)
            .padding(PopoverMetrics.padding)
        let (host, window) = mount(view, language: .en, height: 260)
        defer { window.close() }
        let (bitmap, observations) = try await capture(host: host, language: .en)
        let text = joined(observations)
        assertVisible(l.accountUsageUnavailable, in: text)
        XCTAssertFalse(text.contains("2026-10-07"))
        XCTAssertFalse(normalized(text).contains(normalized(l.accountUsageDailyHistory)))
        try save(bitmap, named: "en-account-unavailable.png")
    }

    private func renderHome(localTokens: Int, failing: Bool, language: AppLanguage) async throws {
        let suite = "AccountHomeRender-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let accountFile = directory.appendingPathComponent("account.json")
        let saved = CodexAccountUsageSnapshot(usage: fixture, fetchedAt: Date(timeIntervalSince1970: 1_791_435_600))
        if failing { saved.save(to: accountFile) }
        let provider: any CodexAccountUsageProviding = failing ? AccountRenderFailure() : AccountRenderReport(usage: fixture)
        let usage = UsageStore(providers: localTokens == 0 ? [] : [AccountRenderLocalUsage(tokens: localTokens)],
            claudeLimitsProvider: AccountRenderClaude(), discoverClaudeConfigDirs: { [] },
            readDefaultIdentity: { nil }, claudeUsageEntries: { _ in [] },
            codexLimitsProvider: AccountRenderCodex(), codexAccountUsageProvider: provider,
            codexAccountUsageFileURL: accountFile, antigravityLimitsProvider: AccountRenderAntigravity(),
            cursorLimitsProvider: AccountRenderCursor(), statusProvider: AccountRenderStatus(),
            autoRefresh: false, defaults: defaults)
        await usage.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(usage.todayTotalTokens, localTokens)
        XCTAssertEqual(usage.codexAccountUsageSnapshot?.usage, fixture)
        XCTAssertEqual(usage.codexAccountUsageRefreshFailed, failing)
        if failing { XCTAssertEqual(usage.codexAccountUsageSnapshot?.fetchedAt, saved.fetchedAt) }

        var state = CompanionState()
        state.language = language
        state.active = MonState(baseID: 129, pathIDs: [129, 130], stageIndex: 1,
                                usedAtStage: 170_100_000, rarity: .common, totalForms: 2, nature: .hardy)
        let stateFile = directory.appendingPathComponent("companion.json")
        try JSONEncoder().encode(state).write(to: stateFile)
        let companion = CompanionStore(provider: AccountRenderPokemon(), fileURL: stateFile, defaults: defaults)
        let view = PopoverView().environment(usage).environment(companion)
            .environment(UpdateChecker(defaults: defaults)).environment(PopoverNavigation())
        let (host, window) = mount(view, language: language, height: 604)
        defer { window.close() }
        let (top, topObservations) = try await capture(host: host, language: language)
        assertVisible(companion.l.todayTokens, in: joined(topObservations))
        if localTokens > 0 { assertVisibleDigits(String(localTokens), in: joined(topObservations)) }
        try save(top, named: "\(language.rawValue)-home-\(failing ? "last-report" : "empty-local")-top.png")

        // The actual home keeps its 520pt viewport. Scroll its production scroll view to account history.
        let scroll = try XCTUnwrap(descendants(host).compactMap { $0 as? NSScrollView }.first)
        let document = try XCTUnwrap(scroll.documentView)
        let bottom = max(0, document.bounds.height - scroll.contentView.bounds.height)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: document.isFlipped ? bottom : 0))
        scroll.reflectScrolledClipView(scroll.contentView)
        let (account, accountObservations) = try await capture(host: host, language: language)
        let text = joined(accountObservations)
        assertVisible(companion.l.accountUsageTitle, in: text)
        assertVisible("2026-10-07", in: text)
        assertVisibleDigits("5000000001", in: text)
        if failing { assertVisible(companion.l.accountUsageLastReport, in: text) }
        XCTAssertEqual(usage.todayTotalTokens, localTokens)
        try save(account, named: "\(language.rawValue)-home-\(failing ? "last-report" : "empty-local")-account.png")
    }

    private func mount<V: View>(_ view: V, language: AppLanguage, height: CGFloat) -> (NSHostingView<some View>, NSWindow) {
        let host = NSHostingView(rootView: view.frame(width: PopoverMetrics.width, height: height)
            .background(Color(nsColor: NSColor(calibratedWhite: 0.07, alpha: 1)))
            .environment(\.colorScheme, .dark).environment(\.controlActiveState, .active)
            .environment(\.locale, language.displayLocale))
        host.frame = NSRect(x: 0, y: 0, width: PopoverMetrics.width, height: height)
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: PopoverMetrics.width, height: height),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        window.orderFront(nil)
        return (host, window)
    }

    private func capture(host: NSView, language: AppLanguage) async throws -> (NSBitmapImageRep, [VNRecognizedTextObservation]) {
        try await Task.sleep(for: .milliseconds(500))
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        switch language {
        case .ko: request.recognitionLanguages = ["ko-KR", "en-US"]
        case .ru: request.recognitionLanguages = ["ru-RU", "en-US"]
        default: request.recognitionLanguages = ["en-US"]
        }
        try VNImageRequestHandler(cgImage: XCTUnwrap(bitmap.cgImage)).perform([request])
        return (bitmap, request.results ?? [])
    }

    private func joined(_ observations: [VNRecognizedTextObservation]) -> String {
        observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
    }
    private func normalized(_ string: String) -> String {
        // Vision can recognize the printed middle dot as a bullet; compare the visible words.
        string.filter { $0.isLetter || $0.isNumber }.lowercased()
    }
    private func assertVisible(_ expected: String, in text: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(normalized(text).contains(normalized(expected)), "Missing visible \(expected): \(text)", file: file, line: line)
    }
    private func assertVisibleDigits(_ digits: String, in text: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(text.filter(\.isNumber).contains(digits), "Missing visible counter \(digits): \(text)", file: file, line: line)
    }
    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    private func save(_ bitmap: NSBitmapImageRep, named name: String) throws {
        guard let output = ProcessInfo.processInfo.environment["PTB_CODEX_ACCOUNT_SCREENSHOT_DIR"] else { return }
        let directory = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: directory.appendingPathComponent(name))
    }
}
