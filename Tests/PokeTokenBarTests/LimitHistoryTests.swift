import XCTest
@testable import PokeTokenBar

/// Local limit-utilization history. No endpoint reports past window usage, so everything this
/// covers is derivation from a series we recorded ourselves — which makes the *boundary* rule the
/// load-bearing part: get it wrong and the history is silently made of fake windows.
@MainActor
final class LimitHistoryTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("limit-history-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func file(_ name: String = "history.json") -> URL {
        tempDir.appendingPathComponent(name)
    }

    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

    private func sample(_ minutes: Double, _ utilization: Double) -> LimitHistoryStore.Sample {
        LimitHistoryStore.Sample(at: epoch.addingTimeInterval(minutes * 60),
                                 utilization: utilization)
    }

    // MARK: - Reset detection

    /// A reset drops utilization to ~zero, so "at least halved and fell materially" reads it.
    func testResetDetectedOnDropToZero() {
        XCTAssertTrue(LimitHistoryStore.isReset(previous: 80, current: 0))
        XCTAssertTrue(LimitHistoryStore.isReset(previous: 100, current: 3))
        XCTAssertTrue(LimitHistoryStore.isReset(previous: 80, current: 39))
    }

    /// The whole reason the rule is not "it went down".
    ///
    /// The weekly window is rolling: old usage ages out and utilization drifts downward between
    /// polls with no reset in sight (the `notifiedTier` comment in `UsageStore` records the same
    /// field misbehaving). A naive `current < previous` boundary would shatter one real week into
    /// dozens of fake windows, and every "you reached 90% in N windows" number built on top would
    /// be inflated garbage.
    func testRollingDecayIsNotAReset() {
        XCTAssertFalse(LimitHistoryStore.isReset(previous: 80, current: 79))
        XCTAssertFalse(LimitHistoryStore.isReset(previous: 80, current: 74))
        // Halved but the absolute fall is trivial — a near-empty window, not worth splitting.
        XCTAssertFalse(LimitHistoryStore.isReset(previous: 4, current: 0))
        // Fell a lot but nowhere near halved: still the same window.
        XCTAssertFalse(LimitHistoryStore.isReset(previous: 80, current: 41))
    }

    func testResetRequiresBothHalvingAndMaterialDrop() {
        XCTAssertTrue(LimitHistoryStore.isReset(previous: 10, current: 5),
                      "halved and fell 5pp — the boundary of both conditions")
        XCTAssertFalse(LimitHistoryStore.isReset(previous: 9, current: 4.5),
                       "halved but fell only 4.5pp")
    }

    // MARK: - Downsampling policy

    func testShouldRecordFirstSampleAlways() {
        XCTAssertTrue(LimitHistoryStore.shouldRecord(
            previous: nil, candidate: sample(0, 12), heartbeat: 900, minimumDelta: 0.5))
    }

    func testShouldRecordOnMeaningfulChange() {
        XCTAssertTrue(LimitHistoryStore.shouldRecord(
            previous: sample(0, 12), candidate: sample(1, 12.5),
            heartbeat: 900, minimumDelta: 0.5))
        XCTAssertFalse(LimitHistoryStore.shouldRecord(
            previous: sample(0, 12), candidate: sample(1, 12.4),
            heartbeat: 900, minimumDelta: 0.5),
            "sub-threshold jitter must not fill the log")
    }

    func testShouldRecordHeartbeatKeepsFlatWindowsObserved() {
        // Identical utilization, but past the heartbeat: without this a quiet stretch looks
        // indistinguishable from the app being closed, and the gap rule would split it.
        XCTAssertTrue(LimitHistoryStore.shouldRecord(
            previous: sample(0, 12), candidate: sample(15, 12),
            heartbeat: 900, minimumDelta: 0.5))
        XCTAssertFalse(LimitHistoryStore.shouldRecord(
            previous: sample(0, 12), candidate: sample(14, 12),
            heartbeat: 900, minimumDelta: 0.5))
    }

    /// Sleep/wake and NTP steps move the clock backwards. An out-of-order sample would read to the
    /// splitter as a gap followed by a jump, inventing a window boundary out of a clock artifact.
    func testShouldRecordRejectsBackwardsClock() {
        XCTAssertFalse(LimitHistoryStore.shouldRecord(
            previous: sample(10, 12), candidate: sample(5, 80),
            heartbeat: 900, minimumDelta: 0.5))
        XCTAssertFalse(LimitHistoryStore.shouldRecord(
            previous: sample(10, 12), candidate: sample(10, 80),
            heartbeat: 900, minimumDelta: 0.5))
    }

    // MARK: - Window derivation

    func testEmptyAndSingleSampleSeries() {
        XCTAssertTrue(LimitHistoryStore.windows(from: [], maxGap: 3600).isEmpty)
        let one = LimitHistoryStore.windows(from: [sample(0, 42)], maxGap: 3600)
        XCTAssertEqual(one.count, 1)
        XCTAssertEqual(one.first?.peak, 42)
        XCTAssertEqual(one.first?.sampleCount, 1)
        XCTAssertEqual(one.first?.truncated, false)
    }

    func testSplitsAtResetAndKeepsPerWindowPeak() {
        let samples = [
            sample(0, 10), sample(15, 45), sample(30, 88), sample(45, 60),
            sample(60, 2),                                   // reset → new window
            sample(75, 30), sample(90, 51),
        ]
        let windows = LimitHistoryStore.windows(from: samples, maxGap: 6 * 3600)
        XCTAssertEqual(windows.count, 2)
        XCTAssertEqual(windows[0].peak, 88)
        XCTAssertEqual(windows[0].sampleCount, 4)
        XCTAssertEqual(windows[1].peak, 51)
        XCTAssertEqual(windows[1].sampleCount, 3)
        XCTAssertFalse(windows.contains(where: \.truncated))
    }

    /// The regression the reset rule exists to prevent, exercised end-to-end rather than on the
    /// predicate alone: a whole rolling week of gentle decay must stay one window.
    func testRollingDecaySeriesStaysOneWindow() {
        // 90 → 62 over seven hours, never halving, never falling 5pp between polls.
        let samples = (0..<28).map { step in sample(Double(step) * 15, 90 - Double(step)) }
        let windows = LimitHistoryStore.windows(from: samples, maxGap: 6 * 3600)
        XCTAssertEqual(windows.count, 1, "rolling decay must not read as repeated resets")
        XCTAssertEqual(windows[0].peak, 90)
    }

    func testGapSplitsAndMarksBothSidesTruncated() {
        let samples = [
            sample(0, 20), sample(15, 55),
            sample(60 * 12, 70), sample(60 * 12 + 15, 75),   // 12h later: app was closed
        ]
        let windows = LimitHistoryStore.windows(from: samples, maxGap: 6 * 3600)
        XCTAssertEqual(windows.count, 2)
        XCTAssertTrue(windows[0].truncated, "peak before the gap is only a lower bound")
        XCTAssertTrue(windows[1].truncated, "the window we resumed into started unobserved")
        XCTAssertEqual(windows[0].peak, 55)
        XCTAssertEqual(windows[1].peak, 75)
    }

    /// A reset observed *after* a gap must clear the truncated flag: that window was watched from
    /// its start, so its peak is exact and should not be dimmed as partial forever after.
    func testResetAfterGapClearsTruncation() {
        let samples = [
            sample(0, 20),
            sample(60 * 12, 70),          // gap → truncated window starts
            sample(60 * 12 + 15, 1),      // reset → a fully observed window begins
            sample(60 * 12 + 30, 44),
        ]
        let windows = LimitHistoryStore.windows(from: samples, maxGap: 6 * 3600)
        XCTAssertEqual(windows.count, 3)
        XCTAssertTrue(windows[1].truncated)
        XCTAssertFalse(windows[2].truncated, "observed from its own reset onward")
        XCTAssertEqual(windows[2].peak, 44)
    }

    // MARK: - Summary

    func testSummarizeMedianPeakAndThresholdCount() {
        let windows = [10.0, 90.0, 50.0, 95.0].map {
            LimitHistoryStore.Window(start: epoch, end: epoch, peak: $0,
                                     sampleCount: 1, truncated: false)
        }
        let summary = LimitHistoryStore.summarize(windows, threshold: 80, limit: 10)
        XCTAssertEqual(summary.peak, 95)
        XCTAssertEqual(summary.median, 70, "even count → mean of the two middles (50, 90)")
        XCTAssertEqual(summary.atOrAbove, 2)
        XCTAssertFalse(summary.hasTruncated)
    }

    func testSummarizeOddMedianAndLimitKeepsNewest() {
        let windows = [1.0, 2.0, 3.0, 4.0, 5.0].map {
            LimitHistoryStore.Window(start: epoch, end: epoch, peak: $0,
                                     sampleCount: 1, truncated: false)
        }
        XCTAssertEqual(LimitHistoryStore.summarize(windows, threshold: 80, limit: 10).median, 3)
        let limited = LimitHistoryStore.summarize(windows, threshold: 80, limit: 2)
        XCTAssertEqual(limited.windows.map(\.peak), [4, 5], "limit keeps the newest windows")
        XCTAssertEqual(limited.median, 4.5)
    }

    func testSummarizeEmptyIsEmptyNotZeroFilled() {
        let summary = LimitHistoryStore.summarize([], threshold: 80, limit: 10)
        XCTAssertTrue(summary.isEmpty)
        XCTAssertEqual(summary.atOrAbove, 0)
    }

    func testSummarizeFlagsTruncation() {
        let windows = [
            LimitHistoryStore.Window(start: epoch, end: epoch, peak: 30,
                                     sampleCount: 1, truncated: false),
            LimitHistoryStore.Window(start: epoch, end: epoch, peak: 40,
                                     sampleCount: 1, truncated: true),
        ]
        XCTAssertTrue(LimitHistoryStore.summarize(windows, threshold: 80, limit: 10).hasTruncated)
    }

    // MARK: - Pruning

    func testPruneDropsSamplesPastRetention() {
        let now = epoch.addingTimeInterval(100 * 24 * 3600)
        let samples = [sample(0, 1), sample(60 * 24 * 95, 2), sample(60 * 24 * 99, 3)]
        let kept = LimitHistoryStore.pruned(samples, now: now,
                                            retention: 90 * 24 * 3600, maxCount: 1000)
        XCTAssertEqual(kept.map(\.utilization), [2, 3], "only the >90-day-old sample is dropped")
    }

    func testPruneCapsCountDroppingOldestFirst() {
        let samples = (0..<10).map { sample(Double($0), Double($0)) }
        let kept = LimitHistoryStore.pruned(samples, now: epoch.addingTimeInterval(600),
                                            retention: 90 * 24 * 3600, maxCount: 3)
        XCTAssertEqual(kept.map(\.utilization), [7, 8, 9])
    }

    // MARK: - Recording & persistence

    func testRecordDownsamplesFlatPolling() {
        var clock = epoch
        let store = LimitHistoryStore(fileURL: file(), now: { clock })
        // 60 polls two minutes apart, utilization pinned: only the heartbeat should fire.
        for _ in 0..<60 {
            store.record(providerID: "claude_code", windows: [("five_hour", 33)])
            clock = clock.addingTimeInterval(120)
        }
        let samples = store.samples(providerID: "claude_code", window: "five_hour")
        // Polls land on 2-minute marks, so each heartbeat fires at the first mark past 15 minutes
        // (t = 0, 960, 1920, … 6720s). 60 raw polls collapse to 8 rows.
        XCTAssertEqual(samples.count, 8, "1 initial + 7 heartbeats across the 118-minute span")
        XCTAssertTrue(samples.allSatisfy { $0.utilization == 33 })
    }

    func testRecordKeepsSeriesSeparatePerWindowAndProvider() {
        var clock = epoch
        let store = LimitHistoryStore(fileURL: file(), now: { clock })
        store.record(providerID: "claude_code", windows: [("five_hour", 10), ("seven_day", 60)])
        clock = clock.addingTimeInterval(120)
        store.record(providerID: "codex", windows: [("five_hour", 90)])

        XCTAssertEqual(store.samples(providerID: "claude_code", window: "five_hour")
            .map(\.utilization), [10])
        XCTAssertEqual(store.samples(providerID: "claude_code", window: "seven_day")
            .map(\.utilization), [60])
        XCTAssertEqual(store.samples(providerID: "codex", window: "five_hour")
            .map(\.utilization), [90],
            "provider-scoped keys — Codex must not land in Claude's series")
    }

    func testHistorySurvivesRelaunch() {
        var clock = epoch
        let url = file()
        let writer = LimitHistoryStore(fileURL: url, now: { clock })
        writer.record(providerID: "claude_code", windows: [("five_hour", 12)])
        clock = clock.addingTimeInterval(1800)
        writer.record(providerID: "claude_code", windows: [("five_hour", 77)])
        writer.flush()

        let reader = LimitHistoryStore(fileURL: url, now: { clock })
        XCTAssertEqual(reader.samples(providerID: "claude_code", window: "five_hour")
            .map(\.utilization), [12, 77])
    }

    /// Samples recorded inside the one-minute save throttle sit in memory only — which is exactly
    /// why `applicationWillTerminate` calls `flush()`. Without that hook, quitting drops the tail
    /// of the series, and the tail is where the interesting peaks live.
    func testFlushPersistsSamplesHeldBackByTheThrottle() {
        var clock = epoch
        let url = file()
        let store = LimitHistoryStore(fileURL: url, now: { clock })
        store.record(providerID: "claude_code", windows: [("five_hour", 12)])
        clock = clock.addingTimeInterval(30)          // inside the throttle
        store.record(providerID: "claude_code", windows: [("five_hour", 91)])

        func onDisk() -> [Double] {
            LimitHistoryStore(fileURL: url, now: { clock })
                .samples(providerID: "claude_code", window: "five_hour").map(\.utilization)
        }
        XCTAssertEqual(onDisk(), [12], "the throttled second sample has not been written yet")
        store.flush()
        XCTAssertEqual(onDisk(), [12, 91])
    }

    func testWindowsDerivedThroughTheStore() {
        var clock = epoch
        let store = LimitHistoryStore(fileURL: file(), now: { clock })
        for utilization in [10.0, 55.0, 92.0, 1.0, 40.0] {
            store.record(providerID: "claude_code", windows: [("five_hour", utilization)])
            clock = clock.addingTimeInterval(1800)
        }
        let summary = store.summary(providerID: "claude_code", window: "five_hour",
                                    threshold: 80, limit: 14)
        XCTAssertEqual(summary.windows.count, 2)
        XCTAssertEqual(summary.peak, 92)
        XCTAssertEqual(summary.atOrAbove, 1)
    }

    // MARK: - Disk-access gate

    /// `UsageStore` defaults its history to `.shared`, and several existing tests build a store
    /// without injecting one. Under `swift test` that instance must stay purely in memory, or the
    /// suite silently reads and rewrites the developer's real Application Support history.
    func testDefaultLocationIsInertOutsideTheBundledApp() {
        // The store no longer owns this rule — it is `AppEnv.persistsToUserLocation`, shared with
        // LocalUsageCache so the two cannot drift apart.
        XCTAssertFalse(LimitHistoryStore(now: { self.epoch }).persists,
                       "a raw test binary must not touch the user's history file")
        XCTAssertTrue(LimitHistoryStore(fileURL: file(), now: { self.epoch }).persists,
                      "an injected path is always live — the persistence tests rely on it")
    }

    /// The gate must not make the store useless in-process: recording and derivation still work,
    /// they just never reach disk.
    func testInertStoreStillRecordsInMemory() {
        var clock = epoch
        let store = LimitHistoryStore(now: { clock })   // default location → inert under tests
        store.record(providerID: "test_provider", windows: [("five_hour", 40)])
        clock = clock.addingTimeInterval(1800)
        store.record(providerID: "test_provider", windows: [("five_hour", 3)])
        XCTAssertEqual(store.windows(providerID: "test_provider", window: "five_hour").count, 2)
    }

    // MARK: - Claude adapter

    func testClaudeWindowsFlattensBothWindows() throws {
        let json = """
        {"five_hour":{"utilization":21,"resets_at":"2099-01-01T00:00:00Z"},
         "seven_day":{"utilization":64}}
        """
        let status = try JSONDecoder().decode(LimitStatus.self, from: Data(json.utf8))
        let windows = LimitHistoryStore.claudeWindows(from: status)
        XCTAssertEqual(windows.map(\.window), ["five_hour", "seven_day"])
        XCTAssertEqual(windows.map(\.utilization), [21, 64])
    }

    /// A plan that reports only the session window must not write a phantom weekly `0`, which
    /// would render as a full row of empty bars implying the weekly limit was never touched.
    func testClaudeWindowsSkipsMissingWindows() throws {
        let status = try JSONDecoder().decode(
            LimitStatus.self, from: Data("""
            {"five_hour":{"utilization":21}}
            """.utf8))
        XCTAssertEqual(LimitHistoryStore.claudeWindows(from: status).map(\.window), ["five_hour"])
    }

    func testClaudeWindowsEmptyStatusRecordsNothing() throws {
        let status = try JSONDecoder().decode(LimitStatus.self, from: Data("{}".utf8))
        XCTAssertTrue(LimitHistoryStore.claudeWindows(from: status).isEmpty)

        let store = LimitHistoryStore(fileURL: file(), now: { self.epoch })
        store.record(providerID: "claude_code",
                     windows: LimitHistoryStore.claudeWindows(from: status))
        XCTAssertTrue(store.samples(providerID: "claude_code", window: "five_hour").isEmpty)
    }
}
