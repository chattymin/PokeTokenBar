import SwiftUI

/// One way of drawing recent activity in the popover.
///
/// **Adding a visualization starts and ends in this file.** Add a `case` and the compiler points
/// at the two remaining spots — `title(_:)` and `ActivityPanel.chart`, both below — then add one
/// name string to `Localization.swift`. The view itself can live anywhere.
///
/// **Do not add `default:` to either `switch`.** It is the only thing that turns this extension
/// point into a compile error instead of a comment: with a `default`, a new case without a view
/// still builds and the user who picks it gets an empty row.
///
/// Nothing outside this file branches on a specific visualization by name — the same kind of
/// extension point as a `UsageProvider` or `BinaryLocator.commonToolDirectories()`.
enum ActivityVisualization: String, CaseIterable, Sendable {
    /// Day-by-day bars for this month. **The default and first in the cycle** — an existing
    /// install's popover must not change on update.
    case monthlyBars
    /// The last 16 weeks as a calendar grid. Bars compare this month's amounts; the grid shows
    /// weekday patterns ("barely anything on weekends") at a glance, across months.
    case recentHeatmap

    static let `default` = ActivityVisualization.monthlyBars

    /// The next one in the click cycle. It follows `allCases`, so a new case joins the cycle on its own.
    var next: ActivityVisualization {
        let all = Self.allCases
        // The optional is the API's: `self` is always in `allCases`.
        guard let index = all.firstIndex(of: self) else { return Self.default }
        return all[(index + 1) % all.count]
    }

    func title(_ l: L) -> String {
        switch self {
        case .monthlyBars:    return l.dailyTrend
        case .recentHeatmap: return l.recentHeatmap
        }
    }
}

/// Draws the visualization the user picked; a click moves on to the next one.
///
/// **Why not draw both.** Both answer "how has usage been going". Stacking them
/// would spend half the popover's height on two replies to one question. Showing one keeps the
/// popover quiet, and because visualizations do not compete for space, a third or fourth can be
/// added later.
@MainActor
struct ActivityPanel: View {
    let visualization: ActivityVisualization
    let series: [DailyUsage]
    /// The bars split by provider when more than one was used. The grid does not: before this
    /// month only daily totals exist (`history`).
    var providers: [DailyTrendStack.ProviderSeries] = []
    var providerOrder: [String] = []
    /// Days before this month, for the grid. `UsageStore.dailyLedger`.
    var history = UsageLedger()
    let showsCost: Bool
    let today: String
    let l: L
    let onCycle: () -> Void

    var body: some View {
        chart
            .contentShape(Rectangle())      // make the gaps clickable too
            .onTapGesture(perform: onCycle)
            .help(l.activitySwitchHint)
    }

    @ViewBuilder
    private var chart: some View {
        switch visualization {
        case .monthlyBars:
            MonthDailyTrend(series: series, providers: providers, providerOrder: providerOrder,
                            showsCost: showsCost, today: today, l: l,
                            trailing: AnyView(PageDots(current: visualization)))
        case .recentHeatmap:
            ActivityHeatmap(series: series, history: history,
                            showsCost: showsCost, today: today, l: l,
                            trailing: AnyView(PageDots(current: visualization)))
        }
    }
}

/// The only visual hint that there is another view. A click cycle is hard to discover; without
/// the dots most people never learn it can switch.
///
/// The count comes from `allCases`, so a contributor adding a case gets another dot for free.
@MainActor
struct PageDots: View {
    let current: ActivityVisualization

    var body: some View {
        HStack(spacing: 3) {
            ForEach(ActivityVisualization.allCases, id: \.self) { item in
                Circle()
                    .fill(item == current ? Color.secondary.opacity(0.75)
                                          : Color.secondary.opacity(0.25))
                    .frame(width: 4, height: 4)
            }
        }
    }
}
