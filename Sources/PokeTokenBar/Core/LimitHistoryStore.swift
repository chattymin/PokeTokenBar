import Foundation

/// Time series of official rate-limit utilization, recorded locally.
///
/// Every limit endpoint we consume (`api/oauth/usage`, the Codex app-server snapshot, …) reports a
/// **current snapshot only** — a percentage plus a reset instant. Once a window resets, how much of
/// it was consumed is gone: Anthropic exposes no per-account limit history (the Admin usage/cost and
/// Claude Code Analytics APIs are org-scoped, need an admin credential, and report tokens/dollars,
/// never window utilization), and Claude Code writes no limit state to disk either. So the only way
/// to answer "am I on the right plan" is to keep the samples ourselves as they go by.
///
/// Storage is a **sample log**, not pre-aggregated windows. Keying records by `resets_at` looks
/// tempting and is wrong: the weekly window is rolling and its `resets_at` moves on every fetch
/// (see the `notifiedTier` comment in `UsageStore` — that same field already caused a re-notify
/// regression). Windows are instead *derived* at read time by finding resets in the utilization
/// series, which holds regardless of how a provider chooses to express its reset instant.
@MainActor
final class LimitHistoryStore {
    static let shared = LimitHistoryStore()

    struct Sample: Codable, Sendable, Equatable {
        let at: Date
        let utilization: Double
    }

    /// One derived limit window: the span between two resets.
    struct Window: Sendable, Equatable {
        let start: Date
        let end: Date
        let peak: Double
        let sampleCount: Int
        /// The window was cut by an observation gap (app not running), so `peak` is a lower bound
        /// on what was really used and the window count around it may be off. Surfaced so the UI
        /// can say "partial" instead of quietly presenting a hole as a fact.
        let truncated: Bool
    }

    struct Summary: Sendable, Equatable {
        let windows: [Window]
        let peak: Double
        let median: Double
        /// Windows whose peak reached `threshold` — a lower bound when `hasTruncated`.
        let atOrAbove: Int
        let hasTruncated: Bool

        var isEmpty: Bool { windows.isEmpty }
    }

    // MARK: - Tuning

    /// Below this the series is noise, not signal: a flat window still gets one sample per
    /// heartbeat so "we were watching and nothing happened" is distinguishable from a gap.
    static let heartbeat: TimeInterval = 15 * 60
    /// Utilization moves smaller than this are not worth a row (the endpoint reports fractions).
    static let minimumDelta: Double = 0.5
    /// Two samples further apart than this did not observe the same window continuously. Slightly
    /// over the 5-hour session window so a normal overnight gap reads as a gap, not as one window.
    static let maxGap: TimeInterval = 6 * 60 * 60
    static let retention: TimeInterval = 90 * 24 * 60 * 60
    /// Backstop against unbounded growth if a provider ever reports jittery utilization: at the
    /// 15-minute heartbeat, 90 days of one window is ~8.6k samples, so this is headroom, not a cap
    /// that bites in normal use. Oldest are dropped first.
    static let maxSamplesPerSeries = 20_000

    // MARK: - State

    private var series: [String: [Sample]] = [:]
    private var loaded = false
    private var dirty = false
    private var lastSave: Date?

    private let fileURL: URL
    private let now: () -> Date
    /// Whether this instance is allowed to touch disk at all — see `persistsToDisk`.
    private let persists: Bool

    init(fileURL: URL? = nil, now: @escaping () -> Date = Date.init) {
        self.fileURL = fileURL ?? Self.defaultFileURL
        self.now = now
        self.persists = Self.persistsToDisk(injectedFileURL: fileURL,
                                            isBundledApp: AppEnv.isBundledApp)
    }

    /// Disk access is a real-app-only side effect (`AppEnv.isBundledApp`, same gate as Keychain
    /// reads and production logging). It matters here because `UsageStore` defaults its history to
    /// `.shared`: without this, every `swift test` run that constructs a store would read and
    /// rewrite the user's actual `limit-history.json` in Application Support. An explicitly
    /// injected path is always live — that is how the tests exercise persistence.
    static func persistsToDisk(injectedFileURL: URL?, isBundledApp: Bool) -> Bool {
        injectedFileURL != nil || isBundledApp
    }

    private static let defaultFileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PokeTokenBar")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("limit-history.json")
    }()

    /// Series key. Provider-scoped so adding Codex/OpenCode/Antigravity history is a call site
    /// rather than a new subsystem — no provider literal lives inside this store
    /// (`docs/reference/provider-extension.md`).
    static func key(providerID: String, window: String) -> String { "\(providerID)/\(window)" }

    // MARK: - Recording

    /// Append one observation per window, subject to the downsampling policy.
    /// `windows` is `(window key, utilization 0…100)`; nil utilizations are dropped by the caller.
    func record(providerID: String, windows: [(window: String, utilization: Double)]) {
        guard !windows.isEmpty else { return }
        ensureLoaded()
        let at = now()
        for (window, utilization) in windows {
            let key = Self.key(providerID: providerID, window: window)
            let candidate = Sample(at: at, utilization: utilization)
            guard Self.shouldRecord(previous: series[key]?.last, candidate: candidate,
                                    heartbeat: Self.heartbeat, minimumDelta: Self.minimumDelta)
            else { continue }
            series[key, default: []].append(candidate)
            dirty = true
        }
        saveIfNeeded()
    }

    /// Downsampling policy. Deliberately does **not** trigger on a changed reset instant: the
    /// rolling weekly window reports a new `resets_at` on every single fetch, so keying off it
    /// would store every poll and defeat the whole policy.
    static func shouldRecord(previous: Sample?, candidate: Sample,
                             heartbeat: TimeInterval, minimumDelta: Double) -> Bool
    {
        guard let previous else { return true }
        // Clock moved backwards (sleep/wake, NTP step): keep the series monotonic in time rather
        // than appending a sample that would read as a gap-then-jump to the window splitter.
        if candidate.at <= previous.at { return false }
        if abs(candidate.utilization - previous.utilization) >= minimumDelta { return true }
        return candidate.at.timeIntervalSince(previous.at) >= heartbeat
    }

    // MARK: - Reading

    func samples(providerID: String, window: String) -> [Sample] {
        ensureLoaded()
        return series[Self.key(providerID: providerID, window: window)] ?? []
    }

    /// Derived windows for one series, newest last.
    func windows(providerID: String, window: String) -> [Window] {
        Self.windows(from: samples(providerID: providerID, window: window), maxGap: Self.maxGap)
    }

    func summary(providerID: String, window: String, threshold: Double, limit: Int) -> Summary {
        Self.summarize(windows(providerID: providerID, window: window),
                       threshold: threshold, limit: limit)
    }

    // MARK: - Derivation (pure)

    /// Split a sample series into windows at resets and at observation gaps.
    static func windows(from samples: [Sample], maxGap: TimeInterval) -> [Window] {
        guard !samples.isEmpty else { return [] }
        var result: [Window] = []
        var current: [Sample] = [samples[0]]
        var truncated = false

        func flush(truncatedByGap: Bool) {
            guard let first = current.first, let last = current.last else { return }
            result.append(Window(
                start: first.at, end: last.at,
                peak: current.map(\.utilization).max() ?? 0,
                sampleCount: current.count,
                truncated: truncated || truncatedByGap))
        }

        for sample in samples.dropFirst() {
            let previous = current[current.count - 1]
            let gapped = sample.at.timeIntervalSince(previous.at) > maxGap
            if gapped {
                // A gap hides whatever happened while we were not looking. The window we were in
                // ends here with an understated peak, and the one we resume into started blind.
                flush(truncatedByGap: true)
                current = [sample]
                truncated = true
                continue
            }
            if isReset(previous: previous.utilization, current: sample.utilization) {
                flush(truncatedByGap: false)
                current = [sample]
                truncated = false
                continue
            }
            current.append(sample)
        }
        flush(truncatedByGap: false)
        return result
    }

    /// Did the window reset between these two utilizations?
    ///
    /// Not simply "it went down". The weekly window is rolling, so its utilization *drifts*
    /// downward as old usage ages out; treating any decrease as a boundary shatters the weekly
    /// history into dozens of fake windows. A reset drops utilization to near zero, so require the
    /// value to at least halve **and** the absolute fall to be material.
    static func isReset(previous: Double, current: Double) -> Bool {
        current <= previous / 2 && (previous - current) >= 5.0
    }

    static func summarize(_ windows: [Window], threshold: Double, limit: Int) -> Summary {
        let recent = Array(windows.suffix(limit))
        guard !recent.isEmpty else {
            return Summary(windows: [], peak: 0, median: 0, atOrAbove: 0, hasTruncated: false)
        }
        let peaks = recent.map(\.peak).sorted()
        let median = peaks.count % 2 == 1
            ? peaks[peaks.count / 2]
            : (peaks[peaks.count / 2 - 1] + peaks[peaks.count / 2]) / 2
        return Summary(
            windows: recent,
            peak: peaks.last ?? 0,
            median: median,
            atOrAbove: recent.filter { $0.peak >= threshold }.count,
            hasTruncated: recent.contains(where: \.truncated))
    }

    static func pruned(_ samples: [Sample], now: Date,
                       retention: TimeInterval, maxCount: Int) -> [Sample]
    {
        let cutoff = now.addingTimeInterval(-retention)
        var kept = samples.filter { $0.at >= cutoff }
        if kept.count > maxCount { kept.removeFirst(kept.count - maxCount) }
        return kept
    }

    // MARK: - Persistence

    private func ensureLoaded() {
        guard !loaded else { return }
        loaded = true
        guard persists,
              let data = try? Data(contentsOf: fileURL),
              let stored = try? JSONDecoder().decode([String: [Sample]].self, from: data)
        else { return }
        series = stored
    }

    private func saveIfNeeded() {
        guard dirty else { return }
        if let lastSave, now().timeIntervalSince(lastSave) < 60 { return }
        flush()
    }

    /// Write now, ignoring the throttle. Called on app termination so the tail of the series
    /// survives a quit — without it, up to a minute of samples is lost on every launch/quit cycle.
    func flush() {
        guard dirty else { return }
        let at = now()
        for (key, samples) in series {
            series[key] = Self.pruned(samples, now: at, retention: Self.retention,
                                      maxCount: Self.maxSamplesPerSeries)
        }
        series = series.filter { !$0.value.isEmpty }
        // Pruning above still runs so an unbundled run stays memory-bounded; only the write stops.
        guard persists else { dirty = false; lastSave = at; return }
        guard let data = try? JSONEncoder().encode(series) else { return }
        try? data.write(to: fileURL, options: .atomic)
        dirty = false
        lastSave = at
    }
}

// MARK: - Claude adapter

extension LimitHistoryStore {
    /// Window keys for the Claude limit response. Stable identifiers — they are persisted, so
    /// renaming one orphans that history.
    enum ClaudeWindow {
        static let fiveHour = "five_hour"
        static let sevenDay = "seven_day"

        /// Display order for the history section, matching the live limit rows above it.
        static let displayed = [fiveHour, sevenDay]
    }

    /// Flatten a `LimitStatus` into recordable windows. Only the two windows every plan reports are
    /// kept: the model-scoped weekly entries come and go with plan changes and would leave dangling
    /// series, and the session/weekly pair is what actually answers "is my tier right".
    static func claudeWindows(from status: LimitStatus) -> [(window: String, utilization: Double)] {
        var result: [(window: String, utilization: Double)] = []
        if let utilization = status.fiveHour?.utilization {
            result.append((ClaudeWindow.fiveHour, utilization))
        }
        if let utilization = status.sevenDay?.utilization {
            result.append((ClaudeWindow.sevenDay, utilization))
        }
        return result
    }
}
