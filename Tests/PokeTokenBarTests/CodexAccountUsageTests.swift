import XCTest
@testable import PokeTokenBar

private enum AccountFixtureError: Error { case unavailable }

private actor AccountFixtureProvider: CodexAccountUsageProviding {
    enum Reply: Sendable { case report(CodexAccountUsage?), failure }
    private var replies: [Reply]
    init(_ replies: [Reply]) { self.replies = replies }
    func fetch() async throws -> CodexAccountUsage? {
        guard !replies.isEmpty else { return nil }
        switch replies.removeFirst() {
        case .report(let usage): return usage
        case .failure: throw AccountFixtureError.unavailable
        }
    }
}

private struct AccountLocalFixture: UsageProvider {
    let id = "codex"
    let displayName = "Codex"
    let daily: DailyUsage
    func fetchDaily() async throws -> DailyUsage? { daily }
    func fetchEnrichment() async -> ProviderEnrichment {
        ProviderEnrichment(activeBlock: BlockUsage(id: "local", startTime: "", endTime: "",
            isActive: true, totalTokens: daily.totalTokens, costUSD: daily.totalCost,
            tokensPerMinute: 2_000), blocksOK: true,
            weekTotal: PeriodUsage(period: "week", totalTokens: 2_000, totalCost: 4),
            monthTotal: PeriodUsage(period: LocalUsageReader.monthKey(Date()), totalTokens: 3_000, totalCost: 6),
            monthDaily: [daily], periodsOK: true)
    }
}
private struct AccountQuietClaude: ClaudeLimitsProviding {
    func fetch(allowKeychainPrompt: Bool) async throws -> LimitStatus {
        throw LimitsError.keychainInteractionNotAllowed
    }
}
private struct AccountQuietCodex: CodexLimitsProviding {
    func fetch() async throws -> CodexRateLimitStatus? { nil }
}
private struct AccountQuietAntigravity: AntigravityLimitsProviding {
    func fetch(allowKeychainPrompt: Bool) async throws -> AntigravityRateLimitStatus {
        throw LimitsError.keychainInteractionNotAllowed
    }
}
private struct AccountQuietCursor: CursorLimitsProviding {
    func fetch() async throws -> CursorRateLimitStatus? { nil }
}
private struct AccountQuietStatus: ProviderStatusProviding {
    func fetch() async -> [String: ProviderStatus] { [:] }
}

/// Synthetic supported-service responses; no live login, network or user files are used.
@MainActor
final class CodexAccountUsageTests: XCTestCase {
    private var reportedJSON: String {
        """
        {"summary":{"lifetimeTokens":5000000001,"peakDailyTokens":700000000,
        "longestRunningTurnSec":9000,"currentStreakDays":30,"longestStreakDays":30},
        "dailyUsageBuckets":[{"startDate":"2026-10-07","tokens":70000000},
        {"startDate":"2026-10-05","tokens":500000000}],"threadUsage":null}
        """
    }
    private var unavailableJSON: String {
        """
        {"summary":{"lifetimeTokens":null,"peakDailyTokens":null,"longestRunningTurnSec":null,
        "currentStreakDays":null,"longestStreakDays":null},"dailyUsageBuckets":null,"threadUsage":null}
        """
    }

    private func decode(_ json: String) throws -> CodexAccountUsage {
        try JSONDecoder().decode(CodexAccountUsage.self, from: Data(json.utf8))
    }

    func testSupportedResponsePreservesLargeCountsAndLaggingSourceDates() throws {
        let usage = try decode(reportedJSON)
        XCTAssertEqual(usage.summary?.lifetimeTokens, 5_000_000_001)
        XCTAssertEqual(usage.summary?.peakDailyTokens, 700_000_000)
        XCTAssertEqual(usage.summary?.longestRunningTurnSec, 9_000)
        XCTAssertEqual(usage.summary?.currentStreakDays, 30)
        XCTAssertEqual(usage.summary?.longestStreakDays, 30)
        XCTAssertEqual(usage.dailyUsageBuckets?.map(\.startDate), ["2026-10-07", "2026-10-05"])
        XCTAssertEqual(usage.latestReportedDay, "2026-10-07")
        XCTAssertFalse(usage.dailyUsageBuckets?.contains { $0.startDate == "2026-10-08" } ?? true,
                       "An absent current day must not be inferred from lifetime tokens")
        XCTAssertTrue(usage.hasReportedTokens)
    }

    func testNullMetricsAreUnavailableAndExplicitZeroRemainsReported() throws {
        let usage = try decode(unavailableJSON)
        XCTAssertNil(usage.summary?.lifetimeTokens)
        XCTAssertNil(usage.summary?.peakDailyTokens)
        XCTAssertNil(usage.summary?.longestRunningTurnSec)
        XCTAssertNil(usage.summary?.currentStreakDays)
        XCTAssertNil(usage.summary?.longestStreakDays)
        XCTAssertNil(usage.dailyUsageBuckets)
        XCTAssertNil(usage.latestReportedDay)
        XCTAssertFalse(usage.hasReportedTokens)

        let zero = try decode(#"{"summary":{"lifetimeTokens":0},"dailyUsageBuckets":[]}"#)
        XCTAssertEqual(zero.summary?.lifetimeTokens, 0)
        XCTAssertTrue(zero.hasReportedTokens)
        XCTAssertNil(zero.latestReportedDay)
        let dailyOnly = try decode(#"{"summary":null,"dailyUsageBuckets":[{"startDate":"2026-10-07","tokens":0}]}"#)
        XCTAssertNil(dailyOnly.summary)
        XCTAssertTrue(dailyOnly.hasReportedTokens, "Daily source records remain available without lifetime totals")
    }

    func testDefaultLiveGateStopsBinaryDiscoveryAndTransportUnderSwiftTest() async throws {
        if AppEnv.isParityRun { throw XCTSkip("Parity explicitly permits live fetches") }
        XCTAssertFalse(AppEnv.allowsLiveLimitsFetch)
        let provider = CodexAccountUsageProvider(resolveBinary: {
            XCTFail("Default gate must stop even CLI discovery")
            return "/unused"
        }, transport: { _, _ in
            XCTFail("A default account provider must never contact the live service in tests")
            return Data()
        })
        let result = try await provider.fetch()
        XCTAssertNil(result)
    }

    func testProviderUsesSupportedRPCHandshakeAndAccountOnlyRequest() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AccountRPC-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("fixture-cli")
        // Reads exactly the three initialization/request messages, then supplies an RPC fixture.
        // The fixture is executable only inside the isolated temporary directory.
        let script = """
        #!/bin/sh
        IFS= read -r first
        IFS= read -r second
        IFS= read -r third
        printf '%s\\n%s\\n%s\\n' "$first" "$second" "$third" > "$(dirname "$0")/requests.jsonl"
        printf '%s\\n' '{"id":0,"result":{"userAgent":"fixture"}}'
        printf '%s\\n' '{"method":"fixture/notification","params":{}}'
        printf '%s\\n' '{"id":1,"result":\(reportedJSON.replacingOccurrences(of: "\n", with: ""))}'
        """
        try script.write(to: executable, atomically: false, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let provider = CodexAccountUsageProvider(resolveBinary: { executable.path }, allowsFetch: { true })
        let usage = try await provider.fetch()
        XCTAssertEqual(usage, try decode(reportedJSON))
        let lines = try String(contentsOf: directory.appendingPathComponent("requests.jsonl"), encoding: .utf8)
            .split(separator: "\n")
        XCTAssertEqual(lines.count, 3)
        let messages = try lines.map {
            try XCTUnwrap(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any])
        }
        XCTAssertEqual(messages[0]["method"] as? String, "initialize")
        let initParams = try XCTUnwrap(messages[0]["params"] as? [String: Any])
        let capabilities = try XCTUnwrap(initParams["capabilities"] as? [String: Any])
        XCTAssertEqual(capabilities["experimentalApi"] as? Bool, true)
        XCTAssertEqual(messages[1]["method"] as? String, "initialized")
        XCTAssertEqual(messages[2]["method"] as? String, "account/usage/read")
        XCTAssertEqual(messages[2]["id"] as? Int, 1)
        XCTAssertTrue(try XCTUnwrap(messages[2]["params"] as? [String: Any]).isEmpty,
                      "Account source must not make unsupported per-dot attribution claims")
    }

    func testMalformedResponseThrowsInsteadOfReportingZeroUsage() async throws {
        let provider = CodexAccountUsageProvider(resolveBinary: { "/fixture" }, allowsFetch: { true },
            transport: { _, _ in Data(#"{"summary":{"lifetimeTokens":"invalid"}}"#.utf8) })
        do {
            _ = try await provider.fetch()
            XCTFail("Malformed token metrics must fail the refresh")
        } catch is DecodingError { }
    }

    func testPersistenceUsesInjectedPathAndPreservesNullsAndSourceDates() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("AccountSave-\(UUID())/report.json")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let report = CodexAccountUsageSnapshot(usage: try decode(reportedJSON), fetchedAt: Date(timeIntervalSince1970: 123))
        report.save(to: file)
        XCTAssertEqual(CodexAccountUsageSnapshot.load(from: file), report)
        let nullReport = CodexAccountUsageSnapshot(usage: try decode(unavailableJSON), fetchedAt: report.fetchedAt)
        nullReport.save(to: file)
        XCTAssertEqual(CodexAccountUsageSnapshot.load(from: file), nullReport)
        XCTAssertNil(CodexAccountUsageSnapshot.load(from: nil), "Tests never read the user's account snapshot")
    }

    func testRefreshFailureNullAndMissingSourceKeepLastSuccessfulReportAcrossRestart() async throws {
        let suite = "AccountLastGood-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(suite).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let usage = try decode(reportedJSON)
        var recovered = usage
        recovered.summary?.lifetimeTokens = 5_000_000_002
        let provider = AccountFixtureProvider([.report(usage), .failure, .report(try decode(unavailableJSON)),
                                              .report(nil), .report(recovered)])
        let store = makeStore(account: provider, file: file, defaults: defaults)
        await store.refresh(scheduleEmptyRetry: false)
        let first = try XCTUnwrap(store.codexAccountUsageSnapshot)
        XCTAssertEqual(first.usage, usage)
        XCTAssertFalse(store.codexAccountUsageUnavailable)
        XCTAssertFalse(store.codexAccountUsageRefreshFailed)
        XCTAssertEqual(CodexAccountUsageSnapshot.load(from: file), first)
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(store.codexAccountUsageSnapshot, first)
        XCTAssertTrue(store.codexAccountUsageRefreshFailed)
        XCTAssertNil(store.lastErrorDescription, "Account failures do not invalidate local usage")
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(store.codexAccountUsageSnapshot, first)
        XCTAssertTrue(store.codexAccountUsageUnavailable)
        XCTAssertFalse(store.codexAccountUsageRefreshFailed)
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(store.codexAccountUsageSnapshot, first)
        XCTAssertTrue(store.codexAccountUsageUnavailable)
        XCTAssertEqual(CodexAccountUsageSnapshot.load(from: file), first, "Failures must not rewrite fetchedAt")
        let restarted = makeStore(account: AccountFixtureProvider([.failure]), file: file, defaults: defaults)
        XCTAssertEqual(restarted.codexAccountUsageSnapshot, first)
        await restarted.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(restarted.codexAccountUsageSnapshot, first)
        XCTAssertTrue(restarted.codexAccountUsageRefreshFailed)
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertEqual(store.codexAccountUsageSnapshot?.usage, recovered)
        XCTAssertFalse(store.codexAccountUsageUnavailable)
        XCTAssertFalse(store.codexAccountUsageRefreshFailed)
    }

    func testUnavailableFirstReportDoesNotPersistOrInventZeroMetrics() async throws {
        let suite = "AccountNull-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(suite).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let store = makeStore(account: AccountFixtureProvider([.report(try decode(unavailableJSON))]),
                              file: file, defaults: defaults)
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertTrue(store.codexAccountUsageChecked)
        XCTAssertTrue(store.codexAccountUsageUnavailable)
        XCTAssertNil(store.codexAccountUsageSnapshot)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testAccountHistoryNeverChangesLocalTotalsMenuLedgerOrBurn() async throws {
        let suite = "AccountSeparate-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let day = LocalUsageReader.todayKey()
        let daily = DailyUsage(date: day, inputTokens: 1_234, outputTokens: 0,
            cacheCreationTokens: 0, cacheReadTokens: 0, totalTokens: 1_234, totalCost: 2)
        let account = AccountFixtureProvider([.report(nil), .report(try decode(reportedJSON))])
        let store = makeStore(account: account, providers: [AccountLocalFixture(daily: daily)], defaults: defaults)
        await store.refresh(scheduleEmptyRetry: false)
        let menu = store.menuLines
        let ledger = store.dailyLedger
        let cost = store.todayUsageCost
        await store.refresh(scheduleEmptyRetry: false)
        XCTAssertNotNil(store.codexAccountUsageSnapshot)
        XCTAssertEqual(store.snapshots.map(\.providerID), ["codex"])
        XCTAssertEqual(store.todayTotalTokens, 1_234)
        XCTAssertEqual(store.todayTokensByProvider, ["codex": 1_234], "Companion credit remains local-only")
        XCTAssertEqual(store.weekTotalTokens, 2_000)
        XCTAssertEqual(store.monthTotalTokens, 3_000)
        XCTAssertEqual(store.todayUsageCost, cost)
        XCTAssertEqual(store.weekCostTotal, 4)
        XCTAssertEqual(store.monthCostTotal, 6)
        XCTAssertEqual(store.menuLines, menu)
        XCTAssertEqual(store.burnTier, .normal)
        XCTAssertEqual(store.dailyLedger, ledger)
        XCTAssertEqual(store.dailyLedger.tokens(on: day), 1_234)
        XCTAssertEqual(store.monthDailyTotals.map(\.date), [day])
        let empty = makeStore(account: AccountFixtureProvider([.report(try decode(reportedJSON))]), defaults: defaults)
        await empty.refresh(scheduleEmptyRetry: false)
        XCTAssertNotNil(empty.codexAccountUsageSnapshot)
        XCTAssertEqual(empty.todayTotalTokens, 0)
        XCTAssertEqual(empty.weekTotalTokens, 0)
        XCTAssertEqual(empty.monthTotalTokens, 0)
        XCTAssertEqual(empty.todayTokensByProvider, [:])
        XCTAssertFalse(empty.hasUsageData)
        XCTAssertEqual(empty.burnTier, .idle)
    }

    private func makeStore(account: any CodexAccountUsageProviding, providers: [any UsageProvider] = [],
                           file: URL? = nil, defaults: UserDefaults) -> UsageStore {
        UsageStore(providers: providers, claudeLimitsProvider: AccountQuietClaude(),
            discoverClaudeConfigDirs: { [] }, readDefaultIdentity: { nil }, claudeUsageEntries: { _ in [] },
            codexLimitsProvider: AccountQuietCodex(), codexAccountUsageProvider: account,
            codexAccountUsageFileURL: file, antigravityLimitsProvider: AccountQuietAntigravity(),
            cursorLimitsProvider: AccountQuietCursor(), statusProvider: AccountQuietStatus(),
            autoRefresh: false, defaults: defaults)
    }
}
