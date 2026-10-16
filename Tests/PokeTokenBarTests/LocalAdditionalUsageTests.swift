import SQLite3
import XCTest
@testable import PokeTokenBar

final class LocalAdditionalUsageTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PokeTokenBar-LocalAdditionalUsageTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
        temporaryDirectory = nil
    }

    func testOpenCodeReadsSQLiteAndPreservesReportedTotalAndCost() throws {
        let database = temporaryDirectory.appendingPathComponent("opencode.db")
        try execute(database, sql: """
        CREATE TABLE message (
            id TEXT PRIMARY KEY,
            session_id TEXT NOT NULL,
            time_created INTEGER NOT NULL,
            data TEXT NOT NULL
        );
        INSERT INTO message VALUES (
            'msg-1', 'session-1', 1767312000000,
            '{"id":"msg-1","sessionID":"session-1","providerID":"anthropic","modelID":"claude-sonnet-4-20250514","time":{"created":1767312000000},"tokens":{"input":100,"output":50,"total":250,"cache":{"read":10,"write":20}},"cost":0.25}'
        );
        """)

        let entries = LocalAdditionalUsageReader.openCodeEntries(
            modifiedSince: try date("2026-01-01T00:00:00Z"), roots: [temporaryDirectory])

        let entry = try XCTUnwrap(entries.first)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entry.input, 100)
        XCTAssertEqual(entry.output, 120, "unclassified total tokens are retained as output")
        XCTAssertEqual(entry.cacheWrite, 20)
        XCTAssertEqual(entry.cacheRead, 10)
        XCTAssertEqual(entry.total, 250)
        XCTAssertEqual(entry.explicitCost, 0.25)

        let daily = try XCTUnwrap(LocalUsageReader.daily(entries: entries, localDay: entry.localDay))
        XCTAssertEqual(daily.totalTokens, 250)
        XCTAssertEqual(daily.totalCost, 0.25, accuracy: 0.000_001)
    }

    func testOpenCodeFallsBackToLegacyDatabaseWithoutTimeCreatedColumn() throws {
        let database = temporaryDirectory.appendingPathComponent("opencode.db")
        try execute(database, sql: """
        CREATE TABLE message (id TEXT PRIMARY KEY, session_id TEXT NOT NULL, data TEXT NOT NULL);
        INSERT INTO message VALUES (
            'legacy-1', 'session-1',
            '{"id":"legacy-1","sessionID":"session-1","providerID":"openai","modelID":"gpt-5","time":{"created":1767312000000},"tokens":{"input":7,"output":3,"cache":{"read":2,"write":1}},"cost":0}'
        );
        """)

        let entries = LocalAdditionalUsageReader.openCodeEntries(
            modifiedSince: try date("2026-01-01T00:00:00Z"), roots: [temporaryDirectory])

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.total, 13)
    }

    func testOpenCodeReadsV2SessionMessagesAndMergesLegacyUsage() throws {
        let database = temporaryDirectory.appendingPathComponent("opencode.db")
        try execute(database, sql: """
        CREATE TABLE message (
            id TEXT PRIMARY KEY, session_id TEXT NOT NULL, time_created INTEGER NOT NULL, data TEXT NOT NULL
        );
        CREATE TABLE session_message (
            id TEXT PRIMARY KEY, session_id TEXT NOT NULL, type TEXT NOT NULL, seq INTEGER NOT NULL,
            time_created INTEGER NOT NULL, time_updated INTEGER NOT NULL, data TEXT NOT NULL
        );
        CREATE INDEX session_message_time_created_idx ON session_message (time_created);
        INSERT INTO message VALUES (
            'msg-v1', 'session-v1', 1767312000000,
            '{"id":"msg-v1","sessionID":"session-v1","providerID":"anthropic","modelID":"claude-sonnet-4-20250514","time":{"created":1767312000000},"tokens":{"input":100,"output":50,"total":180,"cache":{"read":10,"write":20}},"cost":0.25}'
        );
        INSERT INTO session_message VALUES (
            'msg-v2', 'session-v2', 'assistant', 1, 1767312000000, 1767312000000,
            '{"model":{"id":"gpt-5","providerID":"openai"},"time":{"created":1767312000000},"tokens":{"input":100,"output":50,"reasoning":30,"cache":{"read":10,"write":20}},"cost":0.5}'
        );
        INSERT INTO session_message VALUES (
            'msg-user', 'session-v2', 'user', 2, 1767312000000, 1767312000000,
            '{"time":{"created":1767312000000},"text":"not usage"}'
        );
        """)

        let entries = LocalAdditionalUsageReader.openCodeEntries(
            modifiedSince: try date("2026-01-01T00:00:00Z"), roots: [temporaryDirectory])

        XCTAssertEqual(entries.count, 2)
        let v1 = try XCTUnwrap(entries.first { $0.id == "opencode|msg-v1" })
        XCTAssertEqual(v1.total, 180)
        XCTAssertEqual(v1.explicitCost, 0.25)

        let v2 = try XCTUnwrap(entries.first { $0.id == "opencode|msg-v2" })
        XCTAssertEqual(v2.model, "gpt-5")
        XCTAssertEqual(v2.input, 100)
        XCTAssertEqual(v2.output, 80, "V2 stores reasoning separately from output")
        XCTAssertEqual(v2.cacheRead, 10)
        XCTAssertEqual(v2.cacheWrite, 20)
        XCTAssertEqual(v2.total, 210)
        XCTAssertEqual(v2.explicitCost, 0.5)
    }

    // MARK: Claude Code mirror rows (OpenChamber's `claude-code` provider)

    private let mirrorSchema = """
    CREATE TABLE message (
        id TEXT PRIMARY KEY, session_id TEXT NOT NULL, time_created INTEGER NOT NULL, data TEXT NOT NULL
    );
    CREATE TABLE session_message (
        id TEXT PRIMARY KEY, session_id TEXT NOT NULL, type TEXT NOT NULL, seq INTEGER NOT NULL,
        time_created INTEGER NOT NULL, time_updated INTEGER NOT NULL, data TEXT NOT NULL
    );
    """

    private func v2Row(_ id: String, provider: String, created: Date, completed: Date? = nil,
                       tokens: String = #"{"input":100,"output":50,"reasoning":30,"cache":{"read":10,"write":20}}"#) -> String {
        let ms = Int64(created.timeIntervalSince1970 * 1000)
        let end = Int64((completed ?? created).timeIntervalSince1970 * 1000)
        return """
        INSERT INTO session_message VALUES ('\(id)', 'session', 'assistant', 1, \(ms), \(ms),
        '{"model":{"id":"claude-sonnet-5-5","providerID":"\(provider)"},"time":{"created":\(ms),"completed":\(end)},"tokens":\(tokens)}');
        """
    }

    private func claudeEntry(at date: Date) -> LocalUsageReader.Entry {
        LocalUsageReader.Entry(
            id: "claude-\(date.timeIntervalSince1970)", date: date,
            localDay: LocalUsageReader.localDayFormatter().string(from: date),
            model: "claude-sonnet-5-5", input: 1, output: 1, cacheWrite: 0, cacheRead: 0)
    }

    func testOpenCodeDropsClaudeCodeMirrorRowsOnlyWhenClaudeUsageCoversThem() throws {
        let database = temporaryDirectory.appendingPathComponent("opencode.db")
        let t = try date("2026-01-05T10:00:00Z")
        try execute(database, sql: mirrorSchema + """
        \(v2Row("covered", provider: "claude-code", created: t, completed: t.addingTimeInterval(10)))
        \(v2Row("uncovered", provider: "claude-code", created: t.addingTimeInterval(3600)))
        \(v2Row("native", provider: "openai", created: t.addingTimeInterval(7200)))
        INSERT INTO message VALUES (
            'legacy-covered', 'session-v1', \(Int64(t.addingTimeInterval(1800).timeIntervalSince1970 * 1000)),
            '{"id":"legacy-covered","providerID":"claude-code","modelID":"claude-sonnet-5-5","time":{"created":\(Int64(t.addingTimeInterval(1800).timeIntervalSince1970 * 1000))},"tokens":{"input":100,"output":50,"total":180,"cache":{"read":10,"write":20}}}'
        );
        """)
        let claude = [claudeEntry(at: t.addingTimeInterval(4)), claudeEntry(at: t.addingTimeInterval(1800))]

        let entries = LocalAdditionalUsageReader.openCodeEntries(
            modifiedSince: try date("2026-01-01T00:00:00Z"), roots: [temporaryDirectory],
            claudeEntries: claude)

        XCTAssertEqual(entries.map(\.id).sorted(), ["opencode|native", "opencode|uncovered"],
                       "covered mirror rows are Claude's own usage; an uncovered one is the only record left")
    }

    func testOpenCodeKeepsMirrorUsageWhenThereIsNoClaudeTranscript() throws {
        let database = temporaryDirectory.appendingPathComponent("opencode.db")
        let t = try date("2026-01-05T10:00:00Z")
        try execute(database, sql: mirrorSchema + "\n" + v2Row("only", provider: "claude-code", created: t))

        let entries = LocalAdditionalUsageReader.openCodeEntries(
            modifiedSince: try date("2026-01-01T00:00:00Z"), roots: [temporaryDirectory])

        XCTAssertEqual(entries.map(\.total), [210])
    }

    func testRecentUnmatchedMirrorRowsAreHeldBackUntilTheGracePeriodPasses() throws {
        let database = temporaryDirectory.appendingPathComponent("opencode.db")
        let t = try date("2026-01-05T10:00:00Z")
        try execute(database, sql: mirrorSchema + "\n" + v2Row("fresh", provider: "claude-code", created: t))
        let scan = LocalAdditionalUsageReader.openCodeScan(
            modifiedSince: try date("2026-01-01T00:00:00Z"), roots: [temporaryDirectory])
        XCTAssertEqual(scan.mirrors.count, 1)

        let early = LocalAdditionalUsageReader.resolveOpenCodeMirrors(
            scan.mirrors, claudeEntries: [], now: t.addingTimeInterval(20))
        XCTAssertTrue(early.retained.isEmpty, "the Claude transcript may not be flushed yet")
        XCTAssertEqual(early.pendingSince, scan.mirrors[0].entry.date)

        let late = LocalAdditionalUsageReader.resolveOpenCodeMirrors(
            scan.mirrors, claudeEntries: [], now: t.addingTimeInterval(600))
        XCTAssertEqual(late.retained.map(\.id), ["opencode|fresh"])
        XCTAssertNil(late.pendingSince)
    }

    func testOpenCodeCacheTracksTheDaysThatHadMirrorRows() async throws {
        let database = temporaryDirectory.appendingPathComponent("opencode.db")
        let t = try date("2026-01-05T10:00:00Z")
        let now = t.addingTimeInterval(3600)
        try execute(database, sql: mirrorSchema + "\n"
            + v2Row("covered", provider: "claude-code", created: t, completed: t.addingTimeInterval(10)))
        let claude = [claudeEntry(at: t.addingTimeInterval(4))]
        let cache = LocalAdditionalUsageCache(
            openCodeRootsOverride: [temporaryDirectory],
            claudeEntriesSource: { _ in claude },
            clock: { now })

        let entries = await cache.entries(for: .opencode)
        let days = await cache.mirroredDays(for: .opencode)

        XCTAssertTrue(entries.isEmpty)
        XCTAssertEqual(days, [LocalUsageReader.localDayFormatter().string(from: t)])
    }

    private final class MirrorClock: @unchecked Sendable {
        var now: Date
        init(_ now: Date) { self.now = now }
    }

    private final class ScanLog: @unchecked Sendable { var claudeReadsFrom: [Date] = [] }

    func testOpenCodeCacheRetainsAPendingMirrorRowOnALaterScanWithoutDuplicating() async throws {
        let database = temporaryDirectory.appendingPathComponent("opencode.db")
        let t = try date("2026-01-05T10:00:00Z")
        // A native row newer than the pending mirror row would move a plain "newest entry" watermark
        // past it; only the pending-row pin lets a later scan resolve it.
        try execute(database, sql: mirrorSchema + "\n"
            + v2Row("late", provider: "claude-code", created: t, completed: t.addingTimeInterval(10)) + "\n"
            + v2Row("native", provider: "openai", created: t.addingTimeInterval(15)))
        let clock = MirrorClock(t.addingTimeInterval(20))
        let cache = LocalAdditionalUsageCache(
            openCodeRootsOverride: [temporaryDirectory],
            claudeEntriesSource: { _ in [] },
            clock: { clock.now })

        let waiting = await cache.entries(for: .opencode)
        XCTAssertEqual(waiting.map(\.id), ["opencode|native"],
                       "inside the grace period the Claude transcript may still be flushed")

        clock.now = t.addingTimeInterval(600)
        let resolved = await cache.entries(for: .opencode)
        XCTAssertEqual(resolved.map(\.id).sorted(), ["opencode|late", "opencode|native"])

        clock.now = t.addingTimeInterval(1200)
        let again = await cache.entries(for: .opencode)
        XCTAssertEqual(again.map(\.total), [210, 210], "re-reading a kept row must not count it twice")
    }

    func testOpenCodeCacheResumesAfterDroppedMirrorRowsInsteadOfTheLastNativeEntry() async throws {
        let database = temporaryDirectory.appendingPathComponent("opencode.db")
        let t = try date("2026-01-05T10:00:00Z")
        let mirrorAt = t.addingTimeInterval(3600)
        try execute(database, sql: mirrorSchema + "\n"
            + v2Row("native", provider: "openai", created: t) + "\n"
            + v2Row("covered", provider: "claude-code", created: mirrorAt, completed: mirrorAt.addingTimeInterval(10)))
        let claude = [claudeEntry(at: mirrorAt.addingTimeInterval(4))]
        let log = ScanLog()
        let clock = MirrorClock(mirrorAt.addingTimeInterval(200))
        let cache = LocalAdditionalUsageCache(
            openCodeRootsOverride: [temporaryDirectory],
            claudeEntriesSource: { from in log.claudeReadsFrom.append(from); return claude },
            clock: { clock.now })

        _ = await cache.entries(for: .opencode)
        clock.now = mirrorAt.addingTimeInterval(400)
        let entries = await cache.entries(for: .opencode)

        XCTAssertEqual(entries.map(\.id), ["opencode|native"])
        XCTAssertEqual(log.claudeReadsFrom.count, 2)
        // Resuming from the native row (an hour earlier) would re-read every dropped mirror row each refresh.
        XCTAssertGreaterThan(try XCTUnwrap(log.claudeReadsFrom.last), t.addingTimeInterval(3000))
    }

    func testMirrorWindowReachesFiveSecondsBeforeAndThirtySecondsAfterTheMessage() throws {
        let database = temporaryDirectory.appendingPathComponent("opencode.db")
        let t = try date("2026-01-05T10:00:00Z")
        try execute(database, sql: mirrorSchema + "\n"
            + v2Row("edge", provider: "claude-code", created: t, completed: t.addingTimeInterval(10)))
        let scan = LocalAdditionalUsageReader.openCodeScan(
            modifiedSince: try date("2026-01-01T00:00:00Z"), roots: [temporaryDirectory])
        let later = t.addingTimeInterval(10_000)

        func kept(claudeAt offset: TimeInterval) -> Bool {
            !LocalAdditionalUsageReader.resolveOpenCodeMirrors(
                scan.mirrors, claudeEntries: [claudeEntry(at: t.addingTimeInterval(offset))], now: later)
                .retained.isEmpty
        }
        XCTAssertFalse(kept(claudeAt: -5), "inclusive lower edge")
        XCTAssertTrue(kept(claudeAt: -6))
        XCTAssertFalse(kept(claudeAt: 40), "completion + 30s is the inclusive upper edge")
        XCTAssertTrue(kept(claudeAt: 41))
    }

    func testOpenCodeProviderReportsExplicitZeroWhenOnlyMirrorRowsRemainToday() async throws {
        let database = temporaryDirectory.appendingPathComponent("opencode.db")
        let t = Date().addingTimeInterval(-300)
        try XCTSkipUnless(
            LocalUsageReader.localDayFormatter().string(from: t) == LocalUsageReader.todayKey(),
            "fixture would straddle midnight")
        try execute(database, sql: mirrorSchema + "\n"
            + v2Row("covered", provider: "claude-code", created: t, completed: t.addingTimeInterval(10)))
        let claude = [claudeEntry(at: t.addingTimeInterval(4))]
        let cache = LocalAdditionalUsageCache(
            openCodeRootsOverride: [temporaryDirectory],
            claudeEntriesSource: { _ in claude })

        let daily = try await LocalOpenCodeProvider(cache: cache).fetchDaily()

        // Not nil: an absent provider would leave a saved mirror baseline in the companion ledger.
        XCTAssertEqual(try XCTUnwrap(daily).totalTokens, 0)
    }

    func testHermesReadsSessionTokensReasoningAndActualCost() throws {
        let database = temporaryDirectory.appendingPathComponent("state.db")
        try execute(database, sql: """
        CREATE TABLE sessions (
            id TEXT PRIMARY KEY,
            model TEXT,
            billing_provider TEXT,
            started_at REAL NOT NULL,
            message_count INTEGER DEFAULT 0,
            input_tokens INTEGER DEFAULT 0,
            output_tokens INTEGER DEFAULT 0,
            cache_read_tokens INTEGER DEFAULT 0,
            cache_write_tokens INTEGER DEFAULT 0,
            reasoning_tokens INTEGER DEFAULT 0,
            estimated_cost_usd REAL,
            actual_cost_usd REAL
        );
        INSERT INTO sessions VALUES (
            'session-1', 'claude-sonnet-4-20250514', 'anthropic', 1767312000, 42,
            100, 50, 10, 20, 5, 0.12, 0.34
        );
        """)

        let entries = LocalAdditionalUsageReader.hermesEntries(
            modifiedSince: try date("2026-01-01T00:00:00Z"), roots: [database])

        let entry = try XCTUnwrap(entries.first)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entry.input, 100)
        XCTAssertEqual(entry.output, 55)
        XCTAssertEqual(entry.cacheWrite, 20)
        XCTAssertEqual(entry.cacheRead, 10)
        XCTAssertEqual(entry.total, 185)
        XCTAssertEqual(entry.explicitCost, 0.34)
    }

    func testHermesPreservesActualZeroAndDistinguishesMissingSessionCost() throws {
        let database = temporaryDirectory.appendingPathComponent("state.db")
        try execute(database, sql: """
        CREATE TABLE sessions (
            id TEXT PRIMARY KEY, model TEXT, billing_provider TEXT, started_at REAL NOT NULL,
            message_count INTEGER, input_tokens INTEGER, output_tokens INTEGER,
            cache_read_tokens INTEGER, cache_write_tokens INTEGER, reasoning_tokens INTEGER,
            estimated_cost_usd REAL, actual_cost_usd REAL
        );
        INSERT INTO sessions VALUES ('zero', 'gpt-5.5', 'openai', 1767312000, 1, 1000000, 100, 0, 0, 0, 8, 0);
        INSERT INTO sessions VALUES ('estimate', 'gpt-5.5', 'openai', 1767312000, 1, 1000000, 100, 0, 0, 0, 8, NULL);
        INSERT INTO sessions VALUES ('missing', 'gpt-5.5', 'openai', 1767312000, 1, 1000000, 100, 0, 0, 0, NULL, NULL);
        """)
        let entries = LocalAdditionalUsageReader.hermesEntries(
            modifiedSince: try date("2026-01-01T00:00:00Z"), roots: [database])
        XCTAssertEqual(entries.count, 3)
        let zero = try XCTUnwrap(entries.first { $0.id == "hermes|zero" })
        XCTAssertEqual(zero.explicitCost, 0)
        XCTAssertEqual(LocalUsageReader.daily(entries: [zero], localDay: zero.localDay)?.costCoverage, .source)
        let estimate = try XCTUnwrap(entries.first { $0.id == "hermes|estimate" })
        XCTAssertEqual(estimate.explicitCost, 8)
        XCTAssertEqual(LocalUsageReader.daily(entries: [estimate], localDay: estimate.localDay)?.costCoverage, .estimate)
        let missing = try XCTUnwrap(entries.first { $0.id == "hermes|missing" })
        XCTAssertNil(missing.explicitCost)
        XCTAssertEqual(LocalUsageReader.daily(entries: [missing], localDay: missing.localDay)?.costCoverage, .unavailable,
                       "Session totals cannot be priced as one long-context request")
    }

    func testHermesAcceptsMillisecondStartedAt() throws {
        let database = temporaryDirectory.appendingPathComponent("state.db")
        try execute(database, sql: """
        CREATE TABLE sessions (
            id TEXT PRIMARY KEY, model TEXT, billing_provider TEXT, started_at REAL NOT NULL,
            message_count INTEGER, input_tokens INTEGER, output_tokens INTEGER,
            cache_read_tokens INTEGER, cache_write_tokens INTEGER, reasoning_tokens INTEGER,
            estimated_cost_usd REAL, actual_cost_usd REAL
        );
        INSERT INTO sessions VALUES (
            'session-ms', 'gpt-5', 'openai', 1767312000000, 1,
            10, 5, 0, 0, 0, 0, 0
        );
        """)

        let entries = LocalAdditionalUsageReader.hermesEntries(
            modifiedSince: try date("2026-01-01T00:00:00Z"), roots: [database])

        XCTAssertEqual(entries.count, 1)
        // The value lands exactly on midnight UTC, so a hardcoded day breaks in timezones west of UTC.
        XCTAssertEqual(entries.first?.localDay,
                       LocalUsageReader.localDayFormatter()
                           .string(from: Date(timeIntervalSince1970: 1_767_312_000)))
        XCTAssertEqual(entries.first?.total, 15)
    }

    @MainActor
    func testDefaultRegistryIncludesOnlyRequestedAdditionalProviders() {
        let suite = "LocalAdditionalUsageTests.registry.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UsageStore(autoRefresh: false, defaults: defaults)

        XCTAssertEqual(
            Set(store.registeredProviderIDs),
            Set(["claude_code", "codex", "gemini", "antigravity",
                 "opencode", "hermes", "cursor", "grok", "copilot", "kiro", "pi", "omp", "aside", "kimi_code"]))
    }

    /// Extra-provider logs are external files. A `1e30` token count must clamp, not trap
    /// on the add that follows the extractor. Split from the OpenCode case: a trap kills
    /// the process, so a later assertion in the same test never runs.
    func testCursorHugeTokenCountsDoNotTrapOnTheAdd() throws {
        let huge = NSNumber(value: 1e30)
        let cursor = LocalAdditionalUsageReader.parseCursorBubble(
            [
                "tokenCount": ["inputTokens": huge, "outputTokens": huge],
                "createdAt": "2026-01-02T00:00:00Z",
                "modelType": "gpt-5",
            ],
            key: "bubble-huge",
            modifiedSince: Date(timeIntervalSince1970: 0))
        let cap = LocalUsageReader.maxParsedTokenValue
        let cursorEntry = try XCTUnwrap(cursor)
        XCTAssertEqual(cursorEntry.input, cap)
        XCTAssertEqual(cursorEntry.output, cap)
    }

    func testOpenCodeHugeTokenCountsDoNotTrapOnTheBucketSum() throws {
        let huge = NSNumber(value: 1e30)
        let openCode = LocalAdditionalUsageReader.parseOpenCodeMessage(
            [
                "id": "msg-huge",
                "modelID": "gpt-5",
                "providerID": "openai",
                "time": ["created": 1_767_312_000_000],
                "tokens": [
                    "input": huge, "output": huge,
                    "cache": ["read": huge, "write": huge],
                ],
            ],
            fallbackID: "huge")
        let cap = LocalUsageReader.maxParsedTokenValue
        let openCodeEntry = try XCTUnwrap(openCode)
        XCTAssertEqual(openCodeEntry.input, cap)
        XCTAssertEqual(openCodeEntry.output, cap)
        XCTAssertEqual(openCodeEntry.cacheRead, cap)
        XCTAssertEqual(openCodeEntry.cacheWrite, cap)
    }

    func testHermesHugeSessionTokensDoNotTrapOnTheReasoningAdd() throws {
        let database = temporaryDirectory.appendingPathComponent("state.db")
        let maxInt = "9223372036854775807"
        try execute(database, sql: """
        CREATE TABLE sessions (
            id TEXT PRIMARY KEY, model TEXT, billing_provider TEXT, started_at REAL NOT NULL,
            message_count INTEGER, input_tokens INTEGER, output_tokens INTEGER,
            cache_read_tokens INTEGER, cache_write_tokens INTEGER, reasoning_tokens INTEGER,
            estimated_cost_usd REAL, actual_cost_usd REAL
        );
        INSERT INTO sessions VALUES (
            'huge', 'gpt-5', 'openai', 1767312000, 1,
            \(maxInt), \(maxInt), 0, 0, \(maxInt), NULL, NULL
        );
        """)

        let entries = LocalAdditionalUsageReader.hermesEntries(
            modifiedSince: try date("2026-01-01T00:00:00Z"), roots: [database])

        let entry = try XCTUnwrap(entries.first)
        let cap = LocalUsageReader.maxParsedTokenValue
        XCTAssertEqual(entry.input, cap)
        // Each column is clamped, then output and reasoning are still added. The add must not trap.
        XCTAssertEqual(entry.output, cap * 2)
    }

    func testPrintRealOpenCodeAggregate() throws {
        guard ProcessInfo.processInfo.environment["PTB_PARITY"] == "1" else {
            throw XCTSkip("set PTB_PARITY=1 for the local OpenCode smoke test")
        }
        let roots = LocalAdditionalUsageReader.defaultOpenCodeRoots
        guard roots.contains(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            throw XCTSkip("no local OpenCode data directory")
        }
        let entries = LocalAdditionalUsageReader.openCodeEntries(
            modifiedSince: LocalUsageReader.startOfMonth(Date()))
        XCTAssertFalse(entries.isEmpty)
        let today = LocalUsageReader.todayKey()
        let todayTotal = entries.filter { $0.localDay == today }.reduce(0) { $0 + $1.total }
        print("OPENCODE_NATIVE_PARITY entries=\(entries.count) today=\(todayTotal) month=\(entries.reduce(0) { $0 + $1.total })")
    }

    func testPrintRealHermesAggregate() throws {
        guard ProcessInfo.processInfo.environment["PTB_PARITY"] == "1" else {
            throw XCTSkip("set PTB_PARITY=1 for the local Hermes smoke test")
        }
        let database = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".hermes/state.db")
        guard FileManager.default.fileExists(atPath: database.path) else {
            throw XCTSkip("no local Hermes state database")
        }
        let entries = LocalAdditionalUsageReader.hermesEntries(
            modifiedSince: LocalUsageReader.startOfMonth(Date()), roots: [database])
        XCTAssertFalse(entries.isEmpty)
        let today = LocalUsageReader.todayKey()
        let todayTotal = entries.filter { $0.localDay == today }.reduce(0) { $0 + $1.total }
        print("HERMES_NATIVE_PARITY entries=\(entries.count) today=\(todayTotal) month=\(entries.reduce(0) { $0 + $1.total })")
    }

    private func date(_ value: String) throws -> Date {
        try XCTUnwrap(ISO8601DateFormatter().date(from: value))
    }

    private func execute(_ databaseURL: URL, sql: String) throws {
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &database), SQLITE_OK)
        guard let database else { throw NSError(domain: "SQLite", code: 1) }
        defer { sqlite3_close(database) }
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(database, sql, nil, nil, &errorMessage)
        let message = errorMessage.map { String(cString: $0) }
        sqlite3_free(errorMessage)
        XCTAssertEqual(result, SQLITE_OK, message ?? "SQLite statement failed")
        if result != SQLITE_OK { throw NSError(domain: "SQLite", code: Int(result)) }
    }
}
