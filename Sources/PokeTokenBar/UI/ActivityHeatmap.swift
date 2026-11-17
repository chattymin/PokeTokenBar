import AppKit
import SwiftUI

/// One cell of the heatmap.
struct ActivityCell: Equatable, Sendable {
    let date: String
    let tokens: Int
    /// Inside the grid but not part of the range. The grid is cut into whole weeks so the weekday
    /// rows line up, which puts days outside the range into the first and last columns.
    /// Dropping them shortens a column and shifts every weekday below; drawing them as zero reads
    /// as "unused day".
    let isOutsideRange: Bool
}

/// Grid geometry and shading, as pure functions outside the view: inside SwiftUI they could not be
/// tested headless, and this math goes quietly wrong at week boundaries, DST and month starts
/// (the same reason `DailyTrendMetrics` exists).
enum ActivityHeatmapMetrics {
    /// Row height. Cells take the row's width, so the grid fills the popover like the bars do
    /// instead of sitting as a small block at the left edge.
    static let cell: CGFloat = 10
    static let spacing: CGFloat = 2

    /// One-letter weekday names for the rows, starting at `firstWeekday` like `columns`. Without them
    /// nothing says which row is the weekend — the pattern the grid exists to show. The names come
    /// from the display language; the first weekday from the region, as in `columns`.
    static func weekdayLabels(firstWeekday: Int, locale: Locale) -> [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        let symbols = calendar.veryShortStandaloneWeekdaySymbols    // Sunday first
        let start = (firstWeekday - 1) % symbols.count
        return Array(symbols[start...] + symbols[..<start])
    }

    /// Weeks (columns) × weekdays (rows): the fewest whole weeks covering `first`…`last`.
    ///
    /// The weekday a column starts on is `calendar.firstWeekday` — Monday in some regions, Sunday
    /// in others, and that is the locale's call, not this code's.
    ///
    /// Days advance through `Calendar` rather than a fixed 86400 seconds: on a DST day the local day
    /// is 23 or 25 hours long and the grid would slip a day. Worse, that bug is green or red
    /// depending on the contributor's time zone — it passes in Asia/Seoul — so `calendar` and
    /// `timeZone` are injectable.
    static func columns(days: [String: Int], first: String, last: String,
                        calendar: Calendar = .current,
                        timeZone: TimeZone = .current) -> [[ActivityCell]] {
        var cal = calendar
        cal.timeZone = timeZone
        let formatter = LocalUsageReader.localDayFormatter(timeZone: timeZone)
        // Not a day key: give up on the grid (empty rather than a crash). Production passes the
        // window's first day and today, so this does not happen; the optionals are the API's.
        guard first <= last,
              let firstDate = formatter.date(from: first),
              let lastDate = formatter.date(from: last),
              let gridStart = cal.dateInterval(of: .weekOfYear, for: firstDate)?.start
        else { return [] }

        var columns: [[ActivityCell]] = []
        var cursor = gridStart
        while cursor <= lastDate {
            var column: [ActivityCell] = []
            for offset in 0..<7 {
                // The optional is the API's — it does not fail in the Gregorian calendar.
                guard let date = cal.date(byAdding: .day, value: offset, to: cursor) else { continue }
                let key = formatter.string(from: date)
                // "yyyy-MM-dd" sorts lexicographically the same way it sorts chronologically.
                column.append(ActivityCell(date: key, tokens: days[key] ?? 0,
                                           isOutsideRange: key < first || key > last))
            }
            columns.append(column)
            guard let nextWeek = cal.date(byAdding: .weekOfYear, value: 1, to: cursor) else { break }
            cursor = nextWeek
        }
        return columns
    }

    /// How far back the popover's grid reaches. Long enough that a weekday habit shows over more
    /// than one month, short enough that the cells keep the bars' row height in the popover's width
    /// (a year, 53 columns, would not fit).
    static let weeks = 16

    /// The popover's grid: the last `weeks` weeks, ending with the week `today` falls in. The window
    /// rolls with today rather than resetting on the 1st, so the grid never opens nearly empty.
    ///
    /// `days` reaches past this month only through `UsageLedger` — providers report the current
    /// month alone. Days before `recordedSince` the app was not recording, and days after `today`
    /// have not happened: both are marked outside the range, so neither reads as an unused day.
    static func recentGrid(days: [String: Int], recordedSince: String?, today: String,
                           calendar: Calendar = .current,
                           timeZone: TimeZone = .current) -> [[ActivityCell]] {
        var cal = calendar
        cal.timeZone = timeZone
        let formatter = LocalUsageReader.localDayFormatter(timeZone: timeZone)
        guard let todayDate = formatter.date(from: today),
              let thisWeek = cal.dateInterval(of: .weekOfYear, for: todayDate)?.start,
              let firstWeek = cal.date(byAdding: .weekOfYear, value: -(weeks - 1), to: thisWeek)
        else { return [] }
        let windowStart = formatter.string(from: firstWeek)
        // With nothing recorded yet, only today can be vouched for (the series is about to fill it).
        let first = max(windowStart, recordedSince ?? today)
        // Lay the grid out from the window's first week even when recording began later, so the
        // width stays `weeks` columns, then mark the unrecorded days.
        return columns(days: days, first: windowStart, last: today,
                       calendar: calendar, timeZone: timeZone)
            .map { column in
                column.map { cell in
                    cell.date < first
                        ? ActivityCell(date: cell.date, tokens: cell.tokens, isOutsideRange: true)
                        : cell
                }
            }
    }

    /// The ledger's days with this month's live series laid over them. The ledger is written once
    /// per refresh, so today in the ledger can trail the series the bars draw; taking the larger
    /// keeps the two views agreeing on today (the same rule as `UsageLedger.merge`).
    static func days(ledger: UsageLedger, series: [DailyUsage]) -> [String: Int] {
        var days = ledger.tokensByDay
        for day in series where day.totalTokens > 0 {
            days[day.date] = max(days[day.date] ?? 0, day.totalTokens)
        }
        return days
    }

    /// The first day the grid can vouch for: the ledger's coverage, or the 1st of this month when
    /// the series reaches back further (a fresh ledger that has not been saved yet).
    static func recordedSince(ledger: UsageLedger, series: [DailyUsage]) -> String? {
        [ledger.coveredSince, series.map(\.date).min()].compactMap { $0 }.min()
    }

    /// Shade level 0…4: 0 is an unused day, 1…4 are quartiles of the peak.
    ///
    /// No `peak == 0` guard: `peak` is the window's maximum, so once `tokens > 0` holds,
    /// `peak >= tokens > 0` does too (and the caller only draws when `peak > 0`).
    static func level(tokens: Int, peak: Int) -> Int {
        guard tokens > 0 else { return 0 }
        let ratio = Double(tokens) / Double(peak)
        if ratio <= 0.25 { return 1 }
        if ratio <= 0.50 { return 2 }
        if ratio <= 0.75 { return 3 }
        return 4
    }

    /// Level → color: the contribution-graph greens developers already read without a legend
    /// ("darker = less, brighter = more"). Not the accent color — the grid is a total, and the accent
    /// (blue by default) would read as a provider in the bars' palette.
    /// Light and dark each get their own scale, as on GitHub, so level 1 never vanishes into the
    /// background. Only 0 is near the background, so that edge alone says "used that day".
    static func fill(level: Int) -> Color {
        switch level {
        case 0...4:    return contributionGreens[level]
        default:       return Color.clear      // outside the range or still to come: holds a place, claims nothing
        }
    }

    /// Index = level. Light / dark hex pairs of the contribution graph.
    static let contributionGreens: [Color] = [
        (0xEBEDF0, 0x161B22), (0x9BE9A8, 0x0E4429), (0x40C463, 0x006D32),
        (0x30A14E, 0x26A641), (0x216E39, 0x39D353),
    ].map { light, dark in
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

/// The last 16 weeks of usage as a calendar grid — `ActivityVisualization.recentHeatmap`.
///
/// Bars compare this month's amounts by height; the grid's rows are fixed weekdays, so a habit like
/// "barely anything on weekends" shows at a glance, and over more than one month. The two are
/// alternatives, not a hierarchy.
///
/// The cells are one green per level, not split by provider like the bars: before this month the
/// only source is `UsageLedger`, which keeps daily totals, so a split would stop at the 1st.
///
/// The display gate is a meaningful value (`peak > 0`), not an empty dictionary — a window with no
/// usage draws nothing, like the bars.
@MainActor
struct ActivityHeatmap: View {
    /// This month's totals, for today's readout with cost and for days the ledger has not saved yet.
    let series: [DailyUsage]
    /// The days before this month. `UsageStore.dailyLedger`.
    let history: UsageLedger
    let showsCost: Bool
    /// Today's `localDay` key, injected so the view does not read the clock again.
    let today: String
    let l: L
    /// The switch dots, as in `MonthDailyTrend.trailing`.
    var trailing = AnyView(EmptyView())

    /// The hovered cell. The cells are too small to carry a tooltip of their own, so the caption's
    /// readout follows the pointer and falls back to today.
    @State private var hovered: String?

    var body: some View {
        let grid = ActivityHeatmapMetrics.recentGrid(
            days: ActivityHeatmapMetrics.days(ledger: history, series: series),
            recordedSince: ActivityHeatmapMetrics.recordedSince(ledger: history, series: series),
            today: today)
        let used = grid.joined().filter { !$0.isOutsideRange && $0.tokens > 0 }
        let peak = used.map(\.tokens).max() ?? 0
        if peak > 0 {
            VStack(alignment: .leading, spacing: 3) {
                // The peak hides on a single used day for the bars' reason (`DailyTrendMetrics.showsPeak`).
                captionRow(grid, peak: peak, showsPeak: used.count > 1)
                gridView(grid, peak: peak)
            }
            .padding(.top, 4)
        }
    }

    /// Same layout as the bars' caption — title, readout, peak, switch dots. The peak stays for the
    /// same reason: shades are relative, so one place has to state the absolute scale.
    private func captionRow(_ grid: [[ActivityCell]], peak: Int, showsPeak: Bool) -> some View {
        HStack(spacing: 5) {
            // If anything has to give in a narrow language, it is the title: the readout (the
            // number people open the popover for) stays on one line.
            Text(l.recentHeatmap)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            Text(readout(grid, day: hovered ?? today))
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
            Spacer()
            if showsPeak {
                Text(l.peakDay)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(TokenFormatter.compact(peak))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            trailing
        }
    }

    /// This month's days read like the bars', cost included. Earlier days have tokens only — the
    /// ledger does not keep cost.
    private func readout(_ grid: [[ActivityCell]], day: String) -> String {
        if series.contains(where: { $0.date == day }) {
            return MonthDailyTrend.readout(series: series, today: day, showsCost: showsCost, l: l)
        }
        guard let cell = grid.joined().first(where: { $0.date == day }) else { return "" }
        return "\(DailyTrendMetrics.dayStamp(day, language: l.lang)) \(TokenFormatter.compact(cell.tokens))"
    }

    private func gridView(_ grid: [[ActivityCell]], peak: Int) -> some View {
        HStack(alignment: .top, spacing: ActivityHeatmapMetrics.spacing + 2) {
            VStack(alignment: .leading, spacing: ActivityHeatmapMetrics.spacing) {
                ForEach(Array(ActivityHeatmapMetrics.weekdayLabels(
                    firstWeekday: Calendar.current.firstWeekday,
                    locale: l.lang.displayLocale).enumerated()), id: \.offset) { _, label in
                    Text(label)
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                        .frame(height: ActivityHeatmapMetrics.cell)
                }
            }
            HStack(spacing: ActivityHeatmapMetrics.spacing) {
                ForEach(Array(grid.enumerated()), id: \.offset) { _, column in
                    VStack(spacing: ActivityHeatmapMetrics.spacing) {
                        ForEach(column, id: \.date) { cell in
                            self.cellView(cell, peak: peak)
                        }
                    }
                }
            }
        }
    }

    private func cellView(_ cell: ActivityCell, peak: Int) -> some View {
        let level = cell.isOutsideRange ? -1
                                        : ActivityHeatmapMetrics.level(tokens: cell.tokens, peak: peak)
        return RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(ActivityHeatmapMetrics.fill(level: level))
            .overlay(
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .strokeBorder(cell.date == today ? Color.primary.opacity(0.55) : Color.clear,
                                  lineWidth: 1)
            )
            .frame(maxWidth: .infinity, minHeight: ActivityHeatmapMetrics.cell,
                   maxHeight: ActivityHeatmapMetrics.cell)
            .contentShape(Rectangle())
            .onHover { inside in
                guard !cell.isOutsideRange else { return }
                hovered = inside ? cell.date : nil
            }
    }
}

private extension NSColor {
    convenience init(hex: Int) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
