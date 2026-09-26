import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

// MARK: Fixtures — a fixed UTC calendar whose weeks start on Monday, so nothing depends on the
// machine running the suite.

private let utc = TimeZone(identifier: "UTC")!

private func calendar(firstWeekday: Int = 2) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = utc
    calendar.firstWeekday = firstWeekday
    return calendar
}

private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
    calendar().date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
}

/// Friday 18 September 2026, noon: the week runs Monday 14 to Sunday 20.
private let now = date(2026, 9, 18)

private func key(_ year: Int, _ month: Int, _ day: Int) -> String {
    LocalUsageReader.localDayFormatter(timeZone: utc).string(from: date(year, month, day))
}

private func usage(_ date: String, _ tokens: Int) -> DailyUsage {
    DailyUsage(date: date, inputTokens: 0, outputTokens: 0, cacheCreationTokens: 0,
               cacheReadTokens: 0, totalTokens: tokens, totalCost: 0, costCoverage: .source)
}

/// A ledger that has been recording since `since`, with usage on the given days.
private func ledger(since: String, _ days: [(String, Int)]) -> UsageLedger {
    var ledger = UsageLedger()
    ledger.merge([usage(since, 0)] + days.map { usage($0.0, $0.1) })
    return ledger
}

private func recap(_ ledger: UsageLedger, _ scope: RecapScope, offset: Int = 0, dex: [DexEntry] = [],
                   calendar: Calendar = calendar()) -> UsageRecap {
    let period = RecapPeriod(scope: scope, containing: now, calendar: calendar).shifted(by: offset, calendar: calendar)
    return UsageRecap.make(ledger: ledger, dex: dex, period: period, now: now, calendar: calendar)
}

private func graduate(_ id: String, on day: Date, shiny: Bool = false, released: Bool = false) -> DexEntry {
    DexEntry(id: id, baseID: 10, finalID: 10, chainOrder: [10], rarity: .common, caughtAt: day,
             isShiny: shiny, names: [10: ["en": "S10"]], releasedAt: released ? day : nil)
}

// MARK: Ledger

final class UsageLedgerTests: XCTestCase {
    func testADayNeverGoesDown() {
        var l = UsageLedger()
        l.merge([usage("2026-09-10", 500), usage("2026-09-11", 300)])
        // A rotated log makes the provider report less for a day that really happened.
        l.merge([usage("2026-09-10", 120), usage("2026-09-11", 900)])

        XCTAssertEqual(l.tokens(on: "2026-09-10"), 500)
        XCTAssertEqual(l.tokens(on: "2026-09-11"), 900)
    }

    func testTheSeriesVouchesForItsEmptyDaysToo() {
        var l = UsageLedger()
        l.merge([usage("2026-09-01", 0), usage("2026-09-02", 40)])

        XCTAssertEqual(l.tokensByDay, ["2026-09-02": 40], "an empty day adds no row")
        XCTAssertEqual(l.coveredSince, "2026-09-01", "but it was scanned, so its zero is real")
        XCTAssertTrue(l.covers("2026-09-01"))
        XCTAssertFalse(l.covers("2026-08-31"))

        l.merge([usage("2026-09-05", 10)])
        XCTAssertEqual(l.coveredSince, "2026-09-01", "a later series does not shrink the coverage")
    }

    /// Pruned days are unknown again: without moving the coverage up, a recap would read them as
    /// a stretch with no usage.
    func testPruningForgetsTheCoverageItDrops() {
        var l = ledger(since: "2025-06-01", [("2025-06-10", 100), ("2026-02-01", 200)])
        l.prune(before: "2026-01-01")

        XCTAssertEqual(l.tokensByDay, ["2026-02-01": 200])
        XCTAssertEqual(l.coveredSince, "2026-01-01")
    }

    func testJunkIsDroppedOnLoad() {
        let defaults = UserDefaults(suiteName: "ledger-junk-\(UUID().uuidString)")!
        defaults.set(["2026-09-10": 400, "nope": 10, "0000-00-00": 10, "2026-09-11": 0],
                     forKey: UsageLedger.defaultsKey)
        defaults.set("0000-00-00", forKey: UsageLedger.coverageKey)

        let loaded = UsageLedger.load(from: defaults)

        XCTAssertEqual(loaded.tokensByDay, ["2026-09-10": 400])
        XCTAssertNil(loaded.coveredSince, "a key that is not a day must not backdate the coverage")
    }

    func testSaveAndLoadRoundTrip() {
        let defaults = UserDefaults(suiteName: "ledger-round-\(UUID().uuidString)")!
        let l = ledger(since: "2026-09-01", [("2026-09-10", 700)])
        l.save(to: defaults)

        XCTAssertEqual(UsageLedger.load(from: defaults), l)
    }
}

// MARK: Refresh stubs (so the ledger test touches neither Keychain nor the network)

private enum LedgerStubError: Error { case unavailable }

private struct NoClaudeLimits: ClaudeLimitsProviding {
    func fetch(allowKeychainPrompt: Bool) async throws -> LimitStatus { throw LedgerStubError.unavailable }
}
private struct NoCodexLimits: CodexLimitsProviding {
    func fetch() async throws -> CodexRateLimitStatus? { nil }
}
private struct NoAntigravityLimits: AntigravityLimitsProviding {
    func fetch(allowKeychainPrompt: Bool) async throws -> AntigravityRateLimitStatus {
        throw LedgerStubError.unavailable
    }
}
private struct NoStatus: ProviderStatusProviding {
    func fetch() async -> [String: ProviderStatus] { [:] }
}

/// Reports today in `fetchDaily` and the month series only in `fetchEnrichment` — like the real
/// providers, where the series lands one phase later than the snapshot.
private final class LedgerProvider: UsageProvider, @unchecked Sendable {
    let id = "claude_code"
    let displayName = "Claude Code"
    let reportsCost = true
    private let daily: DailyUsage
    private let series: [DailyUsage]
    init(daily: DailyUsage, series: [DailyUsage]) { self.daily = daily; self.series = series }
    func fetchDaily() async throws -> DailyUsage? { daily }
    func fetchEnrichment() async -> ProviderEnrichment {
        var enrichment = ProviderEnrichment()
        enrichment.periodsOK = true
        enrichment.monthDaily = series
        return enrichment
    }
}

@MainActor
final class UsageLedgerRecordingTests: XCTestCase {
    /// Regression: the ledger used to be written right after phase 1, where `monthDaily` is still
    /// nil, so the first refresh after an install recorded nothing and the recap came out empty.
    func testTheFirstRefreshAlreadyFillsTheLedger() async {
        let formatter = LocalUsageReader.localDayFormatter()
        let today = formatter.string(from: Date())
        let yesterday = formatter.string(from: Date().addingTimeInterval(-86_400))
        let defaults = UserDefaults(suiteName: "ledger-refresh-\(UUID().uuidString)")!
        let store = UsageStore(
            providers: [LedgerProvider(daily: usage(today, 300),
                                       series: [usage(yesterday, 900), usage(today, 300)])],
            claudeLimitsProvider: NoClaudeLimits(), codexLimitsProvider: NoCodexLimits(),
            antigravityLimitsProvider: NoAntigravityLimits(), statusProvider: NoStatus(),
            autoRefresh: false, defaults: defaults)

        await store.refresh(scheduleEmptyRetry: false)

        XCTAssertEqual(store.dailyLedger.tokens(on: today), 300)
        XCTAssertEqual(store.dailyLedger.tokens(on: yesterday), 900)
        XCTAssertEqual(store.dailyLedger.coveredSince, yesterday)
        XCTAssertEqual(UsageLedger.load(from: defaults), store.dailyLedger, "and it survives a relaunch")
    }
}

extension UsageLedgerRecordingTests {
    /// The year view compares against last year, so the refresh must keep all of it — and nothing
    /// older, or the defaults would grow forever.
    func testARefreshKeepsLastYearAndDropsTheYearBefore() async {
        let calendar = RecapPeriod.calendar()
        let formatter = LocalUsageReader.localDayFormatter()
        let thisYear = RecapPeriod(scope: .year, containing: Date(), calendar: calendar)
        let lastYearStart = formatter.string(from: thisYear.shifted(by: -1, calendar: calendar).start)
        let lastDayTwoYearsAgo = formatter.string(from: thisYear.shifted(by: -1, calendar: calendar).start
            .addingTimeInterval(-12 * 3600))
        let today = formatter.string(from: Date())
        let defaults = UserDefaults(suiteName: "ledger-retention-\(UUID().uuidString)")!
        var seeded = UsageLedger()
        seeded.merge([usage(lastDayTwoYearsAgo, 70), usage(lastYearStart, 80)])
        seeded.save(to: defaults)
        let store = UsageStore(
            providers: [LedgerProvider(daily: usage(today, 5), series: [usage(today, 5)])],
            claudeLimitsProvider: NoClaudeLimits(), codexLimitsProvider: NoCodexLimits(),
            antigravityLimitsProvider: NoAntigravityLimits(), statusProvider: NoStatus(),
            autoRefresh: false, defaults: defaults)

        await store.refresh(scheduleEmptyRetry: false)

        XCTAssertEqual(store.dailyLedger.tokens(on: lastYearStart), 80, "1 January of last year stays")
        XCTAssertEqual(store.dailyLedger.tokens(on: lastDayTwoYearsAgo), 0, "31 December the year before goes")
        XCTAssertEqual(store.dailyLedger.coveredSince, lastYearStart)
    }
}

// MARK: Periods

final class RecapPeriodTests: XCTestCase {
    func testAWeekStartsOnTheRegionsFirstWeekday() {
        let monday = RecapPeriod(scope: .week, containing: now, calendar: calendar(firstWeekday: 2))
        XCTAssertEqual(monday.start, date(2026, 9, 14, hour: 0))
        XCTAssertEqual(monday.end, date(2026, 9, 21, hour: 0))

        let sunday = RecapPeriod(scope: .week, containing: now, calendar: calendar(firstWeekday: 1))
        XCTAssertEqual(sunday.start, date(2026, 9, 13, hour: 0))
    }

    func testSteppingBackLandsOnWholePeriods() {
        let cal = calendar()
        let march = RecapPeriod(scope: .month, containing: date(2026, 3, 31), calendar: cal)
        let february = march.shifted(by: -1, calendar: cal)
        XCTAssertEqual(february.start, date(2026, 2, 1, hour: 0), "not 31 February rolled into March")
        XCTAssertEqual(february.end, date(2026, 3, 1, hour: 0))

        let lastYear = RecapPeriod(scope: .year, containing: now, calendar: cal).shifted(by: -1, calendar: cal)
        XCTAssertEqual(lastYear.start, date(2025, 1, 1, hour: 0))
        XCTAssertEqual(lastYear.end, date(2026, 1, 1, hour: 0))
    }
}

// MARK: Recap

final class UsageRecapTests: XCTestCase {
    func testEachScopeDrawsItsOwnMeters() {
        let l = ledger(since: key(2026, 1, 1), [(key(2026, 9, 2), 10), (key(2026, 9, 17), 20),
                                                (key(2026, 8, 30), 5)])

        let week = recap(l, .week)
        XCTAssertEqual(week.buckets.map(\.key).first, key(2026, 9, 14))
        XCTAssertEqual(week.buckets.count, 7)
        XCTAssertEqual(week.buckets.filter(\.isCurrent).map(\.key), [key(2026, 9, 18)])

        XCTAssertEqual(recap(l, .month).buckets.count, 30)
        XCTAssertEqual(recap(l, .month, offset: -7).buckets.count, 28, "February 2026")

        let year = recap(l, .year)
        XCTAssertEqual(year.buckets.count, 12)
        XCTAssertEqual(year.buckets[8].tokens, 30, "September sums its days")
        XCTAssertEqual(year.buckets[7].tokens, 5)
        XCTAssertTrue(year.buckets[8].isCurrent)
        XCTAssertEqual(year.total, 35)
    }

    func testFutureAndUnrecordedDaysAreNotZeros() {
        let week = recap(ledger(since: key(2026, 9, 16), [(key(2026, 9, 17), 50)]), .week)

        XCTAssertEqual(week.buckets.map(\.hasData), [false, false, true, true, true, false, false],
                       "Mon-Tue before the ledger, Sat-Sun still ahead")
        XCTAssertEqual(week.activeDays, 1)
        XCTAssertEqual(week.countedDays, 3)

        let year = recap(ledger(since: key(2026, 9, 1), []), .year)
        XCTAssertEqual(year.buckets.map(\.hasData), Array(repeating: false, count: 8) + [true] + Array(repeating: false, count: 3))
    }

    /// The 18th of the month against a whole previous month would read as a drop; a running period
    /// is compared over the same number of days.
    func testARunningPeriodIsComparedOverTheSameDays() {
        let l = ledger(since: key(2026, 8, 1), [(key(2026, 9, 10), 100), (key(2026, 8, 18), 40),
                                                (key(2026, 8, 19), 1_000)])
        let month = recap(l, .month)

        XCTAssertTrue(month.isInProgress)
        XCTAssertEqual(month.previousTotal, 40, "the 19th of August is past the 18th")
        XCTAssertEqual(try XCTUnwrap(month.delta), 1.5, accuracy: 0.0001)
    }

    func testAFinishedPeriodIsComparedWhole() {
        let l = ledger(since: key(2026, 7, 1), [(key(2026, 8, 5), 300), (key(2026, 7, 31), 100)])
        let august = recap(l, .month, offset: -1)

        XCTAssertFalse(august.isInProgress)
        XCTAssertEqual(august.previousTotal, 100)
        XCTAssertEqual(try XCTUnwrap(august.delta), 2.0, accuracy: 0.0001)
    }

    /// Regression: coverage used to be judged on the *newest* day of the previous window, so a
    /// ledger starting inside it counted the days before as zero and inflated the delta.
    func testAHalfCoveredPreviousPeriodIsNotAComparison() {
        let week = recap(ledger(since: key(2026, 9, 9), [(key(2026, 9, 15), 150), (key(2026, 9, 10), 50)]), .week)

        XCTAssertNil(week.previousTotal, "the ledger starts on the Wednesday of the previous week")
        XCTAssertNil(week.delta)
    }

    func testTheBestStreakStaysInsideThePeriod() {
        // Friday 11 to Wednesday 16 without a gap, then Friday 18 alone.
        let days = [11, 12, 13, 14, 15, 16, 18].map { (key(2026, 9, $0), 5) }
        let week = recap(ledger(since: key(2026, 9, 1), days), .week)

        XCTAssertEqual(week.bestStreak, 3, "Monday 14 to Wednesday 16; the days before the week do not count")
        XCTAssertEqual(recap(ledger(since: key(2026, 9, 1), days), .month).bestStreak, 6)
    }

    func testGraduationsInThePeriodOnly() {
        let dex = [graduate("this-week", on: date(2026, 9, 17)),
                   graduate("monday", on: date(2026, 9, 14, hour: 0), shiny: true),
                   graduate("let-go", on: date(2026, 9, 16), released: true),
                   graduate("last-week", on: date(2026, 9, 13, hour: 23))]
        let l = ledger(since: key(2026, 9, 1), [])

        XCTAssertEqual(recap(l, .week, dex: dex).graduated.map(\.id), ["this-week", "monday"],
                       "newest first, released out, Sunday 13 is last week")
        XCTAssertEqual(recap(l, .month, dex: dex).graduated.count, 3)
    }

    func testGoingBackStopsWhereTheLedgerStarts() {
        let l = ledger(since: key(2026, 9, 1), [(key(2026, 9, 2), 10)])

        XCTAssertFalse(recap(l, .month).canGoBack, "August was never recorded")
        XCTAssertTrue(recap(l, .week, offset: -1).canGoBack, "the week of 31 August holds 1 September")
        XCTAssertFalse(recap(l, .week, offset: -2).canGoBack)
        XCTAssertFalse(recap(l, .year).canGoBack)
    }

    func testAnEmptyLedgerStillDrawsThePeriod() {
        let week = recap(UsageLedger(), .week)

        XCTAssertEqual(week.buckets.count, 7)
        XCTAssertFalse(week.buckets.contains(where: \.hasData))
        XCTAssertEqual(week.total, 0)
        XCTAssertNil(week.bestDay)
        XCTAssertNil(week.previousTotal)
        XCTAssertFalse(week.canGoBack)
    }
}

// MARK: Rendering

@MainActor
final class UsageRecapRenderingTests: XCTestCase {
    private let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("recap-\(UUID().uuidString).json")

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: url)
    }

    func testTheCardRendersInEveryLanguageAndScope() throws {
        let dex = [graduate("a", on: date(2026, 9, 17)), graduate("b", on: date(2026, 9, 15), shiny: true)]
        let dexJSON = String(decoding: try JSONEncoder().encode(dex), as: UTF8.self)
        try Data(#"{"installBaselineSet":true,"usedSinceInstall":1000,"lastDate":"d","dex":\#(dexJSON)}"#.utf8)
            .write(to: url)
        let defaults = UserDefaults(suiteName: "recap-render-\(UUID().uuidString)")!
        ledger(since: key(2026, 8, 1), [(key(2026, 9, 17), 5_000), (key(2026, 8, 20), 900)]).save(to: defaults)
        let usageStore = UsageStore(providers: [], autoRefresh: false, defaults: defaults)

        for language in AppLanguage.allCases {
            let companion = CompanionStore(fileURL: url, defaults: defaults)
            companion.setLanguage(language)
            for scope in RecapScope.allCases {
                let content = RecapContent(store: usageStore, companion: companion, scope: scope, offset: 0,
                                           now: now, calendar: calendar())
                XCTAssertFalse(content.periodLabel().isEmpty, "\(language) \(scope)")
                XCTAssertFalse(content.l.recapCompareSoFar(scope).isEmpty)
                XCTAssertEqual(content.bucketLabels().count, content.recap.buckets.count)
                let renderer = ImageRenderer(content: RecapCard(content: content))
                renderer.scale = 1
                let image = try XCTUnwrap(renderer.cgImage, "\(language) \(scope)")
                XCTAssertEqual(image.width, Int(PopoverMetrics.contentWidth))
            }
        }
    }

    func testTheGraduateStripCarriesTheUnownLetter() throws {
        let unown = DexEntry(id: "unown-q", baseID: UnownForm.speciesID, finalID: UnownForm.speciesID,
                             chainOrder: [UnownForm.speciesID], rarity: .rare, caughtAt: date(2026, 9, 17),
                             names: [UnownForm.speciesID: ["en": "Unown"]], unownForm: .q)
        let dexJSON = String(decoding: try JSONEncoder().encode([unown]), as: UTF8.self)
        try Data(#"{"installBaselineSet":true,"usedSinceInstall":1000,"lastDate":"d","language":"en","dex":\#(dexJSON)}"#.utf8)
            .write(to: url)
        let defaults = UserDefaults(suiteName: "recap-unown-\(UUID().uuidString)")!
        ledger(since: key(2026, 9, 1), [(key(2026, 9, 17), 5_000)]).save(to: defaults)
        let content = RecapContent(store: UsageStore(providers: [], autoRefresh: false, defaults: defaults),
                                   companion: CompanionStore(fileURL: url, defaults: defaults),
                                   scope: .week, offset: 0, now: now, calendar: calendar())

        let graduate = try XCTUnwrap(content.graduates.first)
        XCTAssertEqual(graduate.entry.unownForm, .q, "the strip would otherwise draw the default A sprite")
        XCTAssertEqual(graduate.name, "Unown [Q]")
    }
}
