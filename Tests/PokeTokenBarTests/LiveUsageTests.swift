import XCTest
@testable import PokeTokenBar

// Live usage (2026-11-04): a log that grows is read again within seconds, its source alone, without the limits; reads
// are paced by `UsageStore.LiveTiming`; the companion's save waits `usageSaveGap` between usage writes.

/// A source whose folder is watched, counting its reads; its tokens can change between reads.
private final class WatchedProvider: UsageProvider, @unchecked Sendable {
    let id: String
    let displayName: String
    let root: URL
    private let lock = NSLock()
    private var tokensValue: Int
    private var callsValue = 0
    private var readsAt: [Date] = []
    let delay: TimeInterval

    init(id: String, root: URL, tokens: Int, delay: TimeInterval = 0) {
        self.id = id
        self.displayName = id
        self.root = root
        self.tokensValue = tokens
        self.delay = delay
    }

    var tokens: Int {
        get { lock.withLock { tokensValue } }
        set { lock.withLock { tokensValue = newValue } }
    }
    var calls: Int { lock.withLock { callsValue } }
    var readTimes: [Date] { lock.withLock { readsAt } }

    func fetchDaily() async throws -> DailyUsage? {
        let tokens = lock.withLock { () -> Int in
            callsValue += 1
            readsAt.append(Date())
            return tokensValue
        }
        if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
        return DailyUsage(date: LocalUsageReader.todayKey(), inputTokens: 0, outputTokens: 0, cacheCreationTokens: 0,
                          cacheReadTokens: 0, totalTokens: tokens, totalCost: 0)
    }

    func fetchEnrichment() async -> ProviderEnrichment { ProviderEnrichment() }
    func watchedRoots() async -> [URL] { [root] }
}

/// The first read waits until released, and returns the tokens it saw when it started.
private actor GatedWatchedProvider: UsageProvider {
    nonisolated let id = "gated"
    nonisolated let displayName = "Gated"
    nonisolated let root: URL
    private var tokens: Int
    private var calls = 0
    private var gate: CheckedContinuation<Void, Never>?
    private var released = false

    init(root: URL, tokens: Int) {
        self.root = root
        self.tokens = tokens
    }

    func set(_ value: Int) { tokens = value }
    var readCount: Int { calls }
    func release() {
        released = true
        gate?.resume()
        gate = nil
    }

    func fetchDaily() async throws -> DailyUsage? {
        calls += 1
        let seen = tokens
        if calls == 1, !released {
            await withCheckedContinuation { gate = $0 }
        }
        return DailyUsage(date: LocalUsageReader.todayKey(), inputTokens: 0, outputTokens: 0, cacheCreationTokens: 0,
                          cacheReadTokens: 0, totalTokens: seen, totalCost: 0)
    }

    func fetchEnrichment() async -> ProviderEnrichment { ProviderEnrichment() }
    nonisolated func watchedRoots() async -> [URL] { [root] }
}

private final class CountingClaudeLimits: ClaudeLimitsProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var fetches: Int { lock.withLock { count } }
    func fetch(allowKeychainPrompt: Bool) async throws -> LimitStatus {
        lock.withLock { count += 1 }
        throw LimitsError.keychainInteractionNotAllowed
    }
}

private struct NoCodexLimits: CodexLimitsProviding { func fetch() async throws -> CodexRateLimitStatus? { nil } }
private struct NoAntigravityLimits: AntigravityLimitsProviding {
    func fetch(allowKeychainPrompt: Bool) async throws -> AntigravityRateLimitStatus {
        throw LimitsError.keychainInteractionNotAllowed
    }
}
private struct NoCursorLimits: CursorLimitsProviding { func fetch() async throws -> CursorRateLimitStatus? { nil } }
private struct NoStatus: ProviderStatusProviding { func fetch() async -> [String: ProviderStatus] { [:] } }

/// Stands for the FSEvents watcher: the test fires its handler.
private final class FakeWatcher {
    let paths: [String]
    let handler: @Sendable ([String]) -> Void
    init(paths: [String], handler: @escaping @Sendable ([String]) -> Void) {
        self.paths = paths
        self.handler = handler
    }
}

@MainActor
final class LiveUsageTests: XCTestCase {
    // Set up and torn down outside the main actor on older toolchains (CI's Swift 6.1).
    nonisolated(unsafe) private var base: URL!
    nonisolated(unsafe) private var defaults: UserDefaults!
    nonisolated(unsafe) private var suite = ""

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("LiveUsageTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        suite = "LiveUsageTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: base)
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private func folder(_ name: String) throws -> URL {
        let url = base.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private var watchers: [FakeWatcher] = []

    private func store(_ providers: [any UsageProvider], limits: CountingClaudeLimits = CountingClaudeLimits(),
                       timing: UsageStore.LiveTiming = .init(debounce: 0.05, minimumGap: 0, maximumDuty: 1)) -> UsageStore {
        UsageStore(providers: providers, claudeLimitsProvider: limits,
                   discoverClaudeConfigDirs: { [] },
                   codexLimitsProvider: NoCodexLimits(), antigravityLimitsProvider: NoAntigravityLimits(),
                   cursorLimitsProvider: NoCursorLimits(), statusProvider: NoStatus(),
                   autoRefresh: false, defaults: defaults, displaysAsleep: { false },
                   liveTiming: timing,
                   makeLiveWatcher: { [weak self] paths, handler in
                       let watcher = FakeWatcher(paths: paths, handler: handler)
                       self?.watchers.append(watcher)
                       return watcher
                   })
    }

    private func waitUntil(_ timeout: TimeInterval = 5, _ condition: () -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }

    /// Reports a change to `name` under `root`, as FSEvents does: under the folder's canonical path.
    private func fire(_ root: URL, _ name: String = "session.jsonl") throws {
        let watcher = try XCTUnwrap(watchers.last, "a watcher")
        watcher.handler([changed(root, name)])
    }

    private func changed(_ root: URL, _ name: String = "session.jsonl") -> String {
        UsageFileWatcher.canonicalPath(root.path) + "/" + name
    }

    /// A file that changes under a source's folder reads that source again, and only it: not the other sources, not
    /// the limits. The companion takes the new number (`onRefresh`).
    func testAChangeReadsItsSourceAloneWithoutTheLimits() async throws {
        let a = WatchedProvider(id: "a", root: try folder("a"), tokens: 100)
        let b = WatchedProvider(id: "b", root: try folder("b"), tokens: 50)
        let limits = CountingClaudeLimits()
        let s = store([a, b], limits: limits)
        var refreshed = 0
        s.onRefresh = { refreshed += 1 }
        await s.updateLiveWatcher()
        XCTAssertEqual(Set(try XCTUnwrap(watchers.last).paths),
                       Set([a.root, b.root].map { UsageFileWatcher.canonicalPath($0.path) }))

        a.tokens = 1_234
        try fire(a.root, "session.jsonl")
        let read = await waitUntil { s.liveReadCount == 1 }
        XCTAssertTrue(read)
        XCTAssertEqual(a.calls, 1)
        XCTAssertEqual(b.calls, 0, "the other source is not read")
        XCTAssertEqual(limits.fetches, 0, "no network")
        XCTAssertEqual(s.todayTokensByProvider["a"], 1_234)
        XCTAssertEqual(refreshed, 1)
    }

    /// Many writes in a row (a step writes several lines) make one read.
    func testABurstOfChangesIsOneRead() async throws {
        let a = WatchedProvider(id: "a", root: try folder("a"), tokens: 1)
        // A long wait: a slow runner stretches the writes' spacing (CI read 7 times with 0.3 s).
        let s = store([a], timing: .init(debounce: 3, minimumGap: 0, maximumDuty: 1))
        await s.updateLiveWatcher()
        // Ten writes 10 ms apart, as a step writes its lines: all inside the wait.
        for i in 0..<10 {
            try fire(a.root, "\(i).jsonl")
            try? await Task.sleep(for: .milliseconds(10))
        }
        let read = await waitUntil(10) { s.liveReadCount >= 1 }
        XCTAssertTrue(read)
        try? await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(a.calls, 1)
    }

    /// A source is read again no sooner than its gap after the last read, and a slow read waits in proportion (a read
    /// of 0.1 s at a 25 % share waits 0.4 s): the reads keep to that share of the time.
    func testReadsArePacedByTheGapAndTheirCost() async throws {
        let a = WatchedProvider(id: "a", root: try folder("a"), tokens: 1, delay: 0.1)
        let s = store([a], timing: .init(debounce: 0, minimumGap: 0.2, maximumDuty: 0.25))
        await s.updateLiveWatcher()
        try fire(a.root, "x.jsonl")
        let first = await waitUntil { s.liveReadCount == 1 }
        XCTAssertTrue(first)
        a.tokens = 2
        try fire(a.root, "x.jsonl")
        let second = await waitUntil { s.liveReadCount == 2 }
        XCTAssertTrue(second)
        let times = a.readTimes
        XCTAssertEqual(times.count, 2)
        // The first read took about 0.1 s and ended about then: the second starts 0.4 s after that end at least.
        XCTAssertGreaterThanOrEqual(times[1].timeIntervalSince(times[0]), 0.48)
    }

    /// Refreshed by hand (interval 0) or with the screens asleep, nothing is watched and a change reads nothing.
    func testTheWatchFollowsTheAutomaticRefresh() async throws {
        let a = WatchedProvider(id: "a", root: try folder("a"), tokens: 1)
        let s = store([a])
        await s.updateLiveWatcher()
        XCTAssertTrue(s.isWatchingLive)
        s.refreshInterval = 0
        XCTAssertFalse(s.isWatchingLive)
        s.liveFilesChanged([changed(a.root, "x.jsonl")])
        try? await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(a.calls, 0)

        s.refreshInterval = 120
        let back = await waitUntil { s.isWatchingLive }
        XCTAssertTrue(back)
        s.suspendPolling()
        XCTAssertFalse(s.isWatchingLive)
    }

    /// A live read that started before a full refresh and ends after it keeps its older number to itself.
    func testALiveReadOlderThanARefreshIsDropped() async throws {
        let gated = GatedWatchedProvider(root: try folder("g"), tokens: 100)
        let s = store([gated])
        await s.updateLiveWatcher()
        try fire(gated.root, "x.jsonl")
        // The live read is under way, holding 100.
        var started = false
        for _ in 0..<250 where !started {
            started = await gated.readCount == 1
            if !started { try? await Task.sleep(for: .milliseconds(20)) }
        }
        XCTAssertTrue(started)
        // Never a hang: without the live read under way, the refresh would wait at the gate.
        guard started else { return await gated.release() }
        await gated.set(500)
        await s.refresh()
        XCTAssertEqual(s.todayTokensByProvider["gated"], 500)
        await gated.release()
        let ended = await waitUntil { s.liveReadCount == 1 }
        XCTAssertTrue(ended)
        XCTAssertEqual(s.todayTokensByProvider["gated"], 500, "the refresh's newer number stays")
    }

    /// The real watcher: a line appended to a log under a watched folder is reported, under its canonical path.
    func testAWatchedFileThatGrowsIsReported() throws {
        let root = try folder("watched")
        let file = root.appendingPathComponent("session.jsonl")
        try Data("{}\n".utf8).write(to: file)
        let reported = expectation(description: "the change is reported")
        reported.assertForOverFulfill = false
        let canonicalRoot = UsageFileWatcher.canonicalPath(root.path)
        let watcher = UsageFileWatcher(paths: [canonicalRoot], latency: 0.1) { paths in
            if paths.contains(where: { UsageFileWatcher.path($0, isUnder: canonicalRoot) }) { reported.fulfill() }
        }
        XCTAssertNotNil(watcher)
        // FSEvents starts after the stream is scheduled; a write right away can come before it.
        Thread.sleep(forTimeInterval: 0.5)
        let handle = try FileHandle(forWritingTo: file)
        handle.seekToEndOfFile()
        handle.write(Data("{\"usage\":1}\n".utf8))
        try handle.close()
        wait(for: [reported], timeout: 10)
        watcher?.stop()
    }

    /// End to end: a real watcher on a real log reader. A Pi session that grows by an assistant message raises today's
    /// tokens with no refresh called.
    func testAGrowingLogRaisesTodayWithoutARefresh() async throws {
        let root = try folder("pi")
        let file = root.appendingPathComponent("session.jsonl")
        func line(_ id: String, input: Int) throws -> String {
            let object: [String: Any] = [
                "type": "message", "id": id, "parentId": NSNull(),
                "timestamp": ISO8601DateFormatter().string(from: Date()),
                "message": ["role": "assistant", "provider": "example", "model": "model-name", "content": [],
                            "usage": ["input": input, "output": 0, "cacheWrite": 0, "cacheRead": 0]],
            ]
            return String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self) + "\n"
        }
        try line("m1", input: 10).write(to: file, atomically: true, encoding: .utf8)
        let provider = LocalPiProvider(cache: LocalUsageCache(piRoots: [root], fileURL: base.appendingPathComponent("cache.json")))
        let s = UsageStore(providers: [provider], claudeLimitsProvider: CountingClaudeLimits(),
                           discoverClaudeConfigDirs: { [] },
                           codexLimitsProvider: NoCodexLimits(), antigravityLimitsProvider: NoAntigravityLimits(),
                           cursorLimitsProvider: NoCursorLimits(), statusProvider: NoStatus(),
                           autoRefresh: false, defaults: defaults, displaysAsleep: { false },
                           liveTiming: .init(debounce: 0.1, minimumGap: 0, maximumDuty: 1),
                           makeLiveWatcher: { paths, handler in UsageFileWatcher(paths: paths, handler: handler) as AnyObject? })
        await s.refresh()
        XCTAssertEqual(s.todayTokensByProvider["pi"], 10)
        XCTAssertTrue(s.isWatchingLive)
        try? await Task.sleep(for: .milliseconds(500))

        let handle = try FileHandle(forWritingTo: file)
        handle.seekToEndOfFile()
        handle.write(Data(try line("m2", input: 25).utf8))
        try handle.close()
        let raised = await waitUntil(10) { s.todayTokensByProvider["pi"] == 35 }
        XCTAssertTrue(raised, "today is \(s.todayTokensByProvider["pi"] ?? -1)")
    }
}

/// The companion's save during live usage: a usage update writes at most once per `usageSaveGap`, the numbers it
/// waits with are written by the next write of any kind, and at quit.
@MainActor
final class CompanionUsageSaveTests: XCTestCase {
    private func store(tree: EvoNode = EvoNode(speciesID: 1, children: [])) throws -> (CompanionStore, URL) {
        var st = CompanionState()
        st.installBaselineSet = true
        st.lastDate = LocalUsageReader.todayKey()
        st.active = MonState(baseID: 1, pathIDs: [1], stageIndex: 0, usedAtStage: 0, rarity: .common, totalForms: 1)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("usage-save-\(UUID().uuidString).json")
        try JSONEncoder().encode(st).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let s = CompanionStore(provider: StubProvider(value: EvoLine(baseID: 1, tree: tree, rarity: .common, names: [:])),
                               fileURL: url, rng: SeededRNG(seed: 1))
        return (s, url)
    }

    private func update(_ s: CompanionStore, _ tokens: Int) {
        s.update(todayTokensByProvider: ["claude_code": tokens], todayDate: LocalUsageReader.todayKey(),
                 monthTotal: tokens, burnTier: .idle, limitWarning: false, hasUsageData: true)
    }

    private func saved(_ url: URL) throws -> CompanionState {
        try JSONDecoder().decode(CompanionState.self, from: Data(contentsOf: url))
    }

    func testUsageWritesWaitTheirGapThenLand() async throws {
        let (s, url) = try store()
        s.usageSaveGap = 0.4
        update(s, 1_000)
        let first = s.savesWritten
        XCTAssertGreaterThan(first, 0, "the first usage write goes at once")
        update(s, 2_000)
        update(s, 3_000)
        XCTAssertEqual(s.savesWritten, first, "the next ones wait")
        XCTAssertNotEqual(try saved(url), s.state)
        try? await Task.sleep(for: .milliseconds(700))
        XCTAssertEqual(s.savesWritten, first + 1, "one write once the gap is over")
        XCTAssertEqual(try saved(url), s.state)
    }

    func testAQuitWritesWhatWaits() throws {
        let (s, url) = try store()
        s.usageSaveGap = 60
        update(s, 1_000)
        update(s, 5_000)
        XCTAssertNotEqual(try saved(url), s.state)
        s.flushPendingSave()
        XCTAssertEqual(try saved(url), s.state)
    }

    func testWithoutAGapEachUsageWrites() throws {
        let (s, _) = try store()
        update(s, 1_000)
        let first = s.savesWritten
        update(s, 2_000)
        XCTAssertEqual(s.savesWritten, first + 1)
    }

    /// A usage update loads the line, as the app's first refresh does.
    private func lineLoaded(_ s: CompanionStore) async throws {
        update(s, 0)
        for _ in 0..<100 where s.currentLine == nil { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertNotNil(s.currentLine)
    }

    /// As in the app, the line loaded: tokens' growth waits its gap too (#182: each live read wrote the whole save, the
    /// test above ran before the line had loaded and took the only path that waited).
    func testUsageWritesWaitWithTheLineLoaded() async throws {
        let (s, url) = try store()
        try await lineLoaded(s)
        s.usageSaveGap = 60
        update(s, 1_000)
        let first = s.savesWritten
        update(s, 2_000)
        update(s, 3_000)
        XCTAssertEqual(s.savesWritten, first, "token growth waits its gap")
        XCTAssertNotEqual(try saved(url), s.state)
    }

    /// An evolution is written at once, within the gap.
    func testAnEvolutionIsWrittenAtOnce() async throws {
        let (s, url) = try store(tree: EvoNode(speciesID: 1, children: [EvoNode(speciesID: 2, children: [EvoNode(speciesID: 3, children: [])])]))
        try await lineLoaded(s)
        s.usageSaveGap = 60
        update(s, 1_000)
        let first = s.savesWritten
        update(s, 5_000_000_000)
        XCTAssertTrue((s.state.active?.stageIndex ?? 0) > 0 || !s.state.dex.isEmpty, "it evolved or graduated")
        XCTAssertEqual(s.savesWritten, first + 1)
        XCTAssertEqual(try saved(url), s.state)
    }
}
