import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

/// The current-streak badge: the run is read from `UsageLedger`, the recap's day-by-day history.
///
/// The traps are the day boundaries. A run must survive the 1st of the month (providers report the
/// current month only, which is why the ledger exists), must not break on a morning before the
/// first prompt, and must step days through `Calendar` — the DST case below is green in a zone
/// without DST, so it runs in America/Los_Angeles.
final class UsageStreakTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    private let pacific = TimeZone(identifier: "America/Los_Angeles")!

    private func calendar(_ zone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        calendar.firstWeekday = 2
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12, in zone: TimeZone) -> Date {
        calendar(zone).date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    /// A ledger recording since `since`, with usage on `active` days and nothing on the others.
    private func ledger(since: String, active: [String]) -> UsageLedger {
        var ledger = UsageLedger()
        ledger.merge([usage(since, 0)] + active.map { usage($0, 1_000) })
        return ledger
    }

    private func usage(_ day: String, _ tokens: Int) -> DailyUsage {
        DailyUsage(date: day, inputTokens: 0, outputTokens: 0, cacheCreationTokens: 0,
                   cacheReadTokens: 0, totalTokens: tokens, totalCost: 0, costCoverage: .source)
    }

    private func streak(_ ledger: UsageLedger, _ now: Date, _ zone: TimeZone) -> UsageStreak {
        ledger.currentStreak(now: now, calendar: calendar(zone))
    }

    // MARK: Counting

    func testARunEndingTodayCountsToday() {
        let ledger = ledger(since: "2026-09-01", active: ["2026-09-16", "2026-09-17", "2026-09-18"])
        XCTAssertEqual(streak(ledger, date(2026, 9, 18, in: utc), utc),
                       UsageStreak(days: 3, includesToday: true))
    }

    /// Before the first prompt of the day the run is intact and ends yesterday. If an unused
    /// today broke it, the badge would vanish every morning.
    func testAnUnusedTodayDoesNotBreakTheRun() {
        let ledger = ledger(since: "2026-09-01", active: ["2026-09-16", "2026-09-17"])
        XCTAssertEqual(streak(ledger, date(2026, 9, 18, hour: 8, in: utc), utc),
                       UsageStreak(days: 2, includesToday: false))
    }

    func testAWholeDayWithoutUsageEndsTheRun() {
        let ledger = ledger(since: "2026-09-01", active: ["2026-09-14", "2026-09-15", "2026-09-17", "2026-09-18"])
        XCTAssertEqual(streak(ledger, date(2026, 9, 18, in: utc), utc).days, 2, "the 16th was empty")

        let lapsed = self.ledger(since: "2026-09-01", active: ["2026-09-15", "2026-09-16"])
        XCTAssertEqual(streak(lapsed, date(2026, 9, 18, in: utc), utc), .none,
                       "yesterday and today empty: the run is over")
    }

    /// The reason the streak reads the ledger and not the month series: on the 1st the series
    /// holds a single day, which would reset every run once a month.
    func testTheRunCarriesAcrossTheFirstOfTheMonth() {
        let ledger = ledger(since: "2026-09-01",
                            active: ["2026-09-28", "2026-09-29", "2026-09-30", "2026-10-01"])
        XCTAssertEqual(streak(ledger, date(2026, 10, 1, in: utc), utc).days, 4)
    }

    /// Stepping back a fixed 86400 seconds from midnight after the spring-forward day lands on the
    /// day before it, skipping it: an empty 8 March would be jumped over and the run would wrongly
    /// continue. Checked by injecting the 86400 step — this assertion fails with it.
    func testStepsThroughDSTWithoutSkippingADay() {
        let spring = ledger(since: "2026-03-01", active: ["2026-03-06", "2026-03-07", "2026-03-09"])
        XCTAssertEqual(streak(spring, date(2026, 3, 9, in: pacific), pacific).days, 1,
                       "8 March (23 hours long) is empty and must end the run")

        let fall = ledger(since: "2026-10-25", active: ["2026-10-31", "2026-11-01", "2026-11-02"])
        XCTAssertEqual(streak(fall, date(2026, 11, 2, in: pacific), pacific).days, 3,
                       "1 November (25 hours long) must count once")
    }

    /// Same day rule as the recap's best streak: a run that fits inside one week reads the same in
    /// both places.
    func testAgreesWithTheRecapsBestStreak() {
        let now = date(2026, 9, 18, in: utc)
        let ledger = ledger(since: "2026-09-01", active: ["2026-09-15", "2026-09-16", "2026-09-17", "2026-09-18"])
        let week = RecapPeriod(scope: .week, containing: now, calendar: calendar(utc))
        let recap = UsageRecap.make(ledger: ledger, dex: [], period: week, now: now, calendar: calendar(utc))
        XCTAssertEqual(streak(ledger, now, utc).days, recap.bestStreak)
    }

    // MARK: Badge

    func testTheBadgeStartsAtTwoDays() {
        XCTAssertFalse(StreakBadge.isShown(.none))
        XCTAssertFalse(StreakBadge.isShown(UsageStreak(days: 1, includesToday: true)),
                       "one day is just 'used today'")
        XCTAssertTrue(StreakBadge.isShown(UsageStreak(days: 2, includesToday: false)))
    }

    func testEveryLanguageNamesTheCount() {
        for language in AppLanguage.allCases {
            let l = L(language)
            XCTAssertTrue(l.streakDays(12).contains("12"), "\(language.rawValue)")
            XCTAssertTrue(l.streakDaysPending(12).contains("12"), "\(language.rawValue)")
            XCTAssertNotEqual(l.streakDays(12), l.streakDaysPending(12), "\(language.rawValue)")
        }
    }

    /// Hidden takes no space in the period row; shown, today's run and a pending one draw differently
    /// (orange flame vs gray), so the badge says whether today already counts.
    @MainActor
    func testTheBadgeTakesNoSpaceWhenHiddenAndMarksAPendingDay() throws {
        let hidden = NSHostingController(rootView: StreakBadge(streak: UsageStreak(days: 1, includesToday: true),
                                                               l: L(.en)))
        XCTAssertEqual(hidden.view.fittingSize.width, 0)

        let today = try pixels(StreakBadge(streak: UsageStreak(days: 5, includesToday: true), l: L(.en)))
        let pending = try pixels(StreakBadge(streak: UsageStreak(days: 5, includesToday: false), l: L(.en)))
        XCTAssertNotEqual(today, pending)
    }

    @MainActor
    private func pixels<V: View>(_ view: V) throws -> Data {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .dark))
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.cgImage)
        return try XCTUnwrap(image.dataProvider?.data as Data?)
    }
}
