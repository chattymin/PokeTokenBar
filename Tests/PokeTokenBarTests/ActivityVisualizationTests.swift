import XCTest
import SwiftUI
@testable import PokeTokenBar

/// Contract guards for the visualization choice (`ActivityVisualization`) and the calendar grid
/// (`ActivityHeatmapMetrics`).
///
/// The real traps in this feature are two.
/// ① **Date arithmetic in the grid.** Advancing a day by a fixed 86400 seconds slips the grid in a
///    month with DST, and that bug is green or red depending on the contributor's time zone — it
///    passes in Asia/Seoul and fails only in America/Los_Angeles. So the tests inject a DST zone.
/// ② **Is the extension point really that narrow.** "Just add a case" is a lie unless checked.
final class ActivityVisualizationTests: XCTestCase {

    // MARK: Choice — the extension point

    /// The default is the existing bar chart. If it changed, an update alone would silently change
    /// people's popover.
    func testDefaultVisualizationIsTheExistingBarChart() {
        XCTAssertEqual(ActivityVisualization.default, .monthlyBars)
        XCTAssertEqual(ActivityVisualization.allCases.first, .monthlyBars,
                       "the cycle must start at the default too")
    }

    /// The cycle visits `allCases` once and comes back. No hardcoded count — a contributor adding a
    /// visualization should not have to touch this test.
    func testCyclingVisitsEveryVisualizationExactlyOnceAndWrapsAround() {
        var seen: [ActivityVisualization] = []
        var current = ActivityVisualization.default
        for _ in ActivityVisualization.allCases {
            seen.append(current)
            current = current.next
        }
        XCTAssertEqual(Set(seen), Set(ActivityVisualization.allCases), "every visualization must be visited")
        XCTAssertEqual(seen.count, Set(seen).count, "nothing may be visited twice in one lap")
        XCTAssertEqual(current, .default, "one lap must come back to the start")
    }

    /// Every visualization has a name in every language. The exhaustive `switch` catches a missing
    /// case at compile time, but not one that returns an empty string.
    func testEveryVisualizationHasANonEmptyTitleInEveryLanguage() {
        for visualization in ActivityVisualization.allCases {
            for lang in AppLanguage.allCases {
                let title = visualization.title(L(lang))
                XCTAssertFalse(title.trimmingCharacters(in: .whitespaces).isEmpty,
                               "\(visualization.rawValue) has no \(lang.rawValue) title")
            }
        }
    }

    /// Save and restore. An unknown rawValue falls back to the default — going back to a build
    /// without that visualization, or a stray `defaults write`, must not leave the popover empty.
    func testSelectionRoundTripsAndUnknownValuesFallBack() {
        let name = "vis-\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        defer { suite.removePersistentDomain(forName: name) }

        suite.set(ActivityVisualization.recentHeatmap.rawValue, forKey: "activityVisualization")
        XCTAssertEqual(stored(in: suite), .recentHeatmap)

        suite.set("someVisualizationFromTheFuture", forKey: "activityVisualization")
        XCTAssertEqual(stored(in: suite), .default, "unknown values fall back to the default, never an empty popover")
    }

    private func stored(in suite: UserDefaults) -> ActivityVisualization {
        ActivityVisualization(rawValue: suite.string(forKey: "activityVisualization") ?? "")
            ?? .default
    }

    // MARK: Grid geometry

    private let zone = TimeZone(identifier: "America/Los_Angeles")!

    private func calendar(firstWeekday: Int = 2) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        cal.firstWeekday = firstWeekday
        return cal
    }

    private func days(_ pairs: [String: Int] = [:]) -> [String: Int] { pairs }

    func testEveryColumnHasSevenDaysSoWeekdayRowsLineUp() {
        let columns = ActivityHeatmapMetrics.columns(
            days: days(), first: "2026-09-01", last: "2026-09-30",
            calendar: calendar(), timeZone: zone)
        XCTAssertFalse(columns.isEmpty)
        XCTAssertTrue(columns.allSatisfy { $0.count == 7 },
                      "a column without seven days shifts every weekday below it")
    }

    /// Days outside the range at the start of the first column and the end of the last are marked.
    /// Without the flag last month's final day draws as a zero and reads as an unused day.
    func testDaysOutsideTheMonthAreMarkedRatherThanDrawnAsZero() {
        let columns = ActivityHeatmapMetrics.columns(
            days: days(), first: "2026-09-01", last: "2026-09-30",
            calendar: calendar(), timeZone: zone)
        let cells = columns.flatMap { $0 }
        // 2026-09-01 is a Tuesday, so a Monday-first grid starts with August 31.
        XCTAssertEqual(cells.filter(\.isOutsideRange).map(\.date).first, "2026-08-31")
        XCTAssertTrue(cells.filter { !$0.isOutsideRange }.allSatisfy { $0.date.hasPrefix("2026-09") },
                      "every cell marked in range must belong to the month")
        XCTAssertEqual(cells.filter { !$0.isOutsideRange }.count, 30, "September has 30 days")
    }

    /// Walks **every** combination where adding a fixed 86400 seconds would break the grid.
    ///
    /// Checking only March (spring forward) with a Monday start stayed **green** with 86400
    /// injected: the US transition (Sunday 02:00) is the last day of a Monday-first week, so the
    /// stride never crosses it. The break is **Sunday start + fall back** — 86400 seconds after
    /// Nov 1 00:00 PDT is **Nov 1 23:00 PST**, not Nov 2, so the same date appears twice.
    ///
    /// Hence both week starts × both transition months. With one combination there is no telling
    /// a guard that protects nothing from one that works.
    func testGridStaysContiguousAcrossDSTInEveryWeekStartAndDirection() {
        let months = [("2026-03-01", "2026-03-31"),    // spring forward (23 hours)
                      ("2026-11-01", "2026-11-30")]    // fall back (25 hours)
        for firstWeekday in [1, 2] {
            for (first, last) in months {
                let cal = calendar(firstWeekday: firstWeekday)
                let columns = ActivityHeatmapMetrics.columns(days: days(), first: first, last: last,
                                                          calendar: cal, timeZone: zone)
                let dates = columns.flatMap { $0.map(\.date) }
                XCTAssertEqual(Set(dates).count, dates.count,
                               "firstWeekday=\(firstWeekday) \(first): a date repeats — the grid slipped a day")

                let formatter = LocalUsageReader.localDayFormatter(timeZone: zone)
                for index in 1..<dates.count {
                    let previous = formatter.date(from: dates[index - 1])!
                    let expected = formatter.string(
                        from: cal.date(byAdding: .day, value: 1, to: previous)!)
                    XCTAssertEqual(dates[index], expected,
                                   "firstWeekday=\(firstWeekday): \(dates[index - 1]) → \(dates[index]) breaks the sequence")
                }
            }
        }
    }

    func testGridStartDayFollowsTheCalendarFirstWeekday() {
        let monday = ActivityHeatmapMetrics.columns(
            days: days(), first: "2026-09-01", last: "2026-09-30",
            calendar: calendar(firstWeekday: 2), timeZone: zone)
        let sunday = ActivityHeatmapMetrics.columns(
            days: days(), first: "2026-09-01", last: "2026-09-30",
            calendar: calendar(firstWeekday: 1), timeZone: zone)
        XCTAssertNotEqual(monday.first?.first?.date, sunday.first?.first?.date,
                          "the first weekday is the locale's call — hardcoded, these two would match")
    }

    /// The grid covers the whole month whatever its length and starting weekday. Checking one month
    /// would pass on the case where February fits exactly four weeks.
    func testGridCoversEveryDayOfEveryMonthInAYear() throws {
        let formatter = LocalUsageReader.localDayFormatter(timeZone: zone)
        var cal = calendar()
        for month in 1...12 {
            let start = String(format: "2026-%02d-01", month)
            let startDate = try XCTUnwrap(formatter.date(from: start))
            let range = try XCTUnwrap(cal.range(of: .day, in: .month, for: startDate))
            let last = String(format: "2026-%02d-%02d", month, range.count)

            let inRange = ActivityHeatmapMetrics.columns(days: days(), first: start, last: last,
                                                      calendar: cal, timeZone: zone)
                .flatMap { $0 }.filter { !$0.isOutsideRange }.map(\.date)
            XCTAssertEqual(inRange.count, range.count, "month \(month) is not fully in the grid")
            XCTAssertEqual(inRange.first, start)
            XCTAssertEqual(inRange.last, last)
        }
    }

    func testUnparseableRangeYieldsAnEmptyGridRatherThanCrashing() {
        XCTAssertTrue(ActivityHeatmapMetrics.columns(days: days(), first: "nope", last: "2026-09-30",
                                                  calendar: calendar(), timeZone: zone).isEmpty)
        XCTAssertTrue(ActivityHeatmapMetrics.columns(days: days(), first: "2026-09-30",
                                                  last: "2026-09-01",
                                                  calendar: calendar(), timeZone: zone).isEmpty,
                      "a reversed range makes no grid")
    }

    /// Row labels start where the grid's columns start, or every row is labeled with the wrong day.
    func testWeekdayLabelsFollowTheFirstWeekdayAndTheDisplayLanguage() {
        let mondayFirst = ActivityHeatmapMetrics.weekdayLabels(firstWeekday: 2,
                                                            locale: Locale(identifier: "en_US"))
        XCTAssertEqual(mondayFirst, ["M", "T", "W", "T", "F", "S", "S"])
        let sundayFirst = ActivityHeatmapMetrics.weekdayLabels(firstWeekday: 1,
                                                            locale: Locale(identifier: "ko_KR"))
        XCTAssertEqual(sundayFirst.first, "일")
        XCTAssertEqual(sundayFirst.last, "토")
    }

    // MARK: Shade levels

    /// 0 (unused) splits from 1 (a little). Boundaries are inclusive (`<=`), so a day at exactly 25%
    /// does not leak a level up.
    func testLevelSeparatesUnusedDaysAndSplitsTheRestIntoQuartiles() {
        let peak = 100_000_000
        XCTAssertEqual(ActivityHeatmapMetrics.level(tokens: 0, peak: peak), 0)
        XCTAssertEqual(ActivityHeatmapMetrics.level(tokens: 1, peak: peak), 1)
        XCTAssertEqual(ActivityHeatmapMetrics.level(tokens: 25_000_000, peak: peak), 1)
        XCTAssertEqual(ActivityHeatmapMetrics.level(tokens: 25_000_001, peak: peak), 2)
        XCTAssertEqual(ActivityHeatmapMetrics.level(tokens: 50_000_000, peak: peak), 2)
        XCTAssertEqual(ActivityHeatmapMetrics.level(tokens: 75_000_000, peak: peak), 3)
        XCTAssertEqual(ActivityHeatmapMetrics.level(tokens: peak, peak: peak), 4)
    }

    /// Cells outside the range (-1) are clear — any color would claim something about that day.
    /// The levels use the contribution greens, not the accent color, which would read as one
    /// provider's color in the bars' palette.
    func testOutsideRangeCellsAreDrawnAsNothing() {
        XCTAssertEqual(ActivityHeatmapMetrics.fill(level: -1), Color.clear)
        XCTAssertNotEqual(ActivityHeatmapMetrics.fill(level: 0), Color.clear,
                          "an unused day is drawn, not clear — the day existed")
        XCTAssertEqual(Set((0...4).map { ActivityHeatmapMetrics.fill(level: $0) }).count, 5,
                       "every level needs its own green")
        for level in 0...4 {
            XCTAssertNotEqual(ActivityHeatmapMetrics.fill(level: level), Color.accentColor,
                              "level \(level) uses the accent color")
        }
    }

    // MARK: The popover's window

    private func series(through today: String) -> [DailyUsage] {
        let day = Int(today.suffix(2))!
        return (1...day).map { index in
            usage(String(format: "%@-%02d", String(today.prefix(7)), index), 1_000)
        }
    }

    private func usage(_ date: String, _ tokens: Int) -> DailyUsage {
        DailyUsage(date: date, inputTokens: 0, outputTokens: tokens, cacheCreationTokens: 0,
                   cacheReadTokens: 0, totalTokens: tokens, totalCost: 0)
    }

    /// A ledger that has recorded every day of the months given, at 1,000 tokens a day.
    private func ledger(months: [String]) -> UsageLedger {
        var ledger = UsageLedger()
        for month in months {
            let number = Int(month.suffix(2))!
            let days = number == 2 ? 28 : [4, 6, 9, 11].contains(number) ? 30 : 31
            ledger.merge(series(through: "\(month)-\(days)"))
        }
        return ledger
    }

    private func grid(ledger: UsageLedger, series: [DailyUsage], today: String,
                      firstWeekday: Int = 2) -> [[ActivityCell]] {
        ActivityHeatmapMetrics.recentGrid(
            days: ActivityHeatmapMetrics.days(ledger: ledger, series: series),
            recordedSince: ActivityHeatmapMetrics.recordedSince(ledger: ledger, series: series),
            today: today, calendar: calendar(firstWeekday: firstWeekday), timeZone: zone)
    }

    /// The grid is `weeks` columns whatever the day, and its last column is the week of today —
    /// on the 1st, mid-month, and in November with Sunday-first weeks (the DST combination that
    /// breaks fixed-length arithmetic, see `columns`).
    func testGridIsAlwaysSixteenWeeksEndingWithTodaysWeek() {
        let history = ledger(months: ["2026-06", "2026-07", "2026-08", "2026-09", "2026-10"])
        for (today, firstWeekday) in [("2026-10-01", 2), ("2026-10-19", 2), ("2026-11-03", 1),
                                      ("2026-10-31", 1)] {
            let cells = grid(ledger: history, series: [], today: today, firstWeekday: firstWeekday)
            XCTAssertEqual(cells.count, ActivityHeatmapMetrics.weeks, "\(today): wrong width")
            XCTAssertTrue(cells.last?.contains { $0.date == today } == true,
                          "\(today): the last column is not today's week")
            XCTAssertEqual(cells.joined().filter { !$0.isOutsideRange }.last?.date, today,
                           "\(today): today must be the last day in range")
            XCTAssertEqual(Set(cells.joined().map(\.date)).count, ActivityHeatmapMetrics.weeks * 7,
                           "\(today): a day repeats or is missing")
        }
    }

    /// The point of the window: the 1st of the month does not empty the grid. September comes from
    /// the ledger, October from the live series.
    func testTheFirstOfTheMonthKeepsLastMonthsDays() {
        let cells = grid(ledger: ledger(months: ["2026-08", "2026-09"]),
                         series: series(through: "2026-10-01"), today: "2026-10-01").joined()
        let used = cells.filter { !$0.isOutsideRange && $0.tokens > 0 }.map(\.date)
        XCTAssertTrue(used.contains("2026-09-30"), "last month vanished on the 1st")
        XCTAssertTrue(used.contains("2026-10-01"))
        XCTAssertGreaterThan(used.count, 7 * 8, "the window should be filled from the ledger")
    }

    /// Before the app started recording there is no data, which is not the same as no usage: those
    /// days are outside the range (drawn as nothing), while the grid keeps its width.
    func testDaysBeforeRecordingBeganAreOutsideTheRange() {
        let cells = grid(ledger: UsageLedger(), series: series(through: "2026-10-19"),
                         today: "2026-10-19")
        XCTAssertEqual(cells.count, ActivityHeatmapMetrics.weeks)
        let inRange = cells.joined().filter { !$0.isOutsideRange }.map(\.date)
        XCTAssertEqual(inRange.first, "2026-10-01", "September was not recorded, so it is unknown")
        XCTAssertTrue(cells.joined().contains { $0.date == "2026-09-30" && $0.isOutsideRange })
    }

    /// The ledger saves once per refresh, so its today can trail the live series. The grid takes the
    /// larger, like `UsageLedger.merge`, so it never shows less than the bars for the same day.
    func testLiveSeriesWinsWhenTheLedgerTrails() {
        var history = UsageLedger()
        history.merge([usage("2026-10-19", 500)])
        let days = ActivityHeatmapMetrics.days(ledger: history, series: [usage("2026-10-19", 2_000)])
        XCTAssertEqual(days["2026-10-19"], 2_000)
        let lower = ActivityHeatmapMetrics.days(ledger: history, series: [usage("2026-10-19", 100)])
        XCTAssertEqual(lower["2026-10-19"], 500, "a day never goes down")
    }

    /// The title states the window, so its number has to follow `weeks` in every language.
    func testTitleStatesTheWindowLength() {
        for lang in AppLanguage.allCases {
            XCTAssertTrue(L(lang).recentHeatmap.contains("\(ActivityHeatmapMetrics.weeks)"),
                          "\(lang.rawValue) title does not say \(ActivityHeatmapMetrics.weeks)")
        }
    }

    // MARK: Panel

    /// The bars inside the panel still stack by provider. `ActivityPanel` sits between the popover
    /// and `MonthDailyTrend`, so a dropped `providers` argument would silently fall back to
    /// single-color bars and still compile.
    @MainActor
    func testPanelBarsDrawTheSameAsTheTrendItWraps() throws {
        let one = series(through: "2026-08-24")
        let two = [DailyTrendStack.ProviderSeries(id: "a", name: "A", days: one, reportsCost: false),
                   DailyTrendStack.ProviderSeries(id: "b", name: "B", days: one, reportsCost: false)]
        let total = one.map { usage($0.date, 2_000) }
        let panel = try pixels(ActivityPanel(visualization: .monthlyBars, series: total,
                                             providers: two, providerOrder: ["a", "b"],
                                             showsCost: false, today: "2026-08-24", l: L(.en),
                                             onCycle: {}))
        let stacked = try pixels(MonthDailyTrend(series: total, providers: two,
                                                 providerOrder: ["a", "b"], showsCost: false,
                                                 today: "2026-08-24", l: L(.en),
                                                 trailing: AnyView(PageDots(current: .monthlyBars))))
        let flat = try pixels(MonthDailyTrend(series: total, showsCost: false,
                                              today: "2026-08-24", l: L(.en),
                                              trailing: AnyView(PageDots(current: .monthlyBars))))
        XCTAssertNotEqual(stacked, flat, "two providers must stack, or this test proves nothing")
        XCTAssertEqual(panel, stacked, "the panel dropped the provider stack")
    }

    /// The panel hands the ledger to the grid. `history` has a default, so dropping it would compile
    /// and quietly bring back a grid that empties on the 1st.
    @MainActor
    func testPanelGridDrawsTheLedgersEarlierMonths() throws {
        let history = ledger(months: ["2026-07"])
        let total = series(through: "2026-08-24")
        let dots = AnyView(PageDots(current: .recentHeatmap))
        let panel = try pixels(ActivityPanel(visualization: .recentHeatmap, series: total,
                                             history: history, showsCost: false,
                                             today: "2026-08-24", l: L(.en), onCycle: {}))
        let withHistory = try pixels(ActivityHeatmap(series: total, history: history, showsCost: false,
                                                     today: "2026-08-24", l: L(.en), trailing: dots))
        let monthOnly = try pixels(ActivityHeatmap(series: total, history: UsageLedger(),
                                                   showsCost: false, today: "2026-08-24", l: L(.en),
                                                   trailing: dots))
        XCTAssertNotEqual(withHistory, monthOnly, "July must show, or this test proves nothing")
        XCTAssertEqual(panel, withHistory, "the panel dropped the ledger")
    }

    @MainActor
    private func pixels<V: View>(_ view: V) throws -> Data {
        let renderer = ImageRenderer(content: view.frame(width: PopoverMetrics.contentWidth))
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.cgImage)
        return try XCTUnwrap(image.dataProvider?.data as Data?)
    }
}
