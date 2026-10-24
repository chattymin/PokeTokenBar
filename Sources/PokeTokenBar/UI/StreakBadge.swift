import SwiftUI

/// The current run of days with usage, next to the recap button: a flame and a number.
///
/// It sits in the period row rather than on a line of its own, so the popover does not grow.
/// The flame is orange once today counts and gray while today has no usage yet — the run is not
/// broken, but today's first use is what extends it; the tooltip says so.
@MainActor
struct StreakBadge: View {
    let streak: UsageStreak
    let l: L

    /// Shown from two days. A one-day run only says "used today", which the totals beside it
    /// already say, and it would flicker in and out for anyone who uses the app now and then.
    nonisolated static let minimumDays = 2

    nonisolated static func isShown(_ streak: UsageStreak) -> Bool { streak.days >= minimumDays }

    /// Tooltip and accessibility label: the run, plus the growth bonus it currently gives.
    nonisolated static func label(_ streak: UsageStreak, l: L) -> String {
        let base = streak.includesToday ? l.streakDays(streak.days) : l.streakDaysPending(streak.days)
        let multiplier = PokemonBalance.streakMultiplier(days: streak.days)
        guard multiplier > 1 else { return base }
        return base + " · " + l.streakGrowthBonus(String(format: "×%.2f", multiplier))
    }

    var body: some View {
        if Self.isShown(streak) {
            let label = Self.label(streak, l: l)
            HStack(spacing: 2) {
                Image(systemName: "flame.fill")
                    .foregroundStyle(streak.includesToday ? Color.orange : Color.secondary)
                Text("\(streak.days)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .font(.caption.weight(.medium))
            .help(label)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
        }
    }
}
