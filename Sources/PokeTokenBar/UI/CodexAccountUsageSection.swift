import SwiftUI

/// A separate service history view: these account totals are not additive local usage.
@MainActor
struct CodexAccountUsageSection: View {
    let usage: CodexAccountUsage?
    let updatedAt: Date?
    let isUnavailable: Bool
    let refreshFailed: Bool
    let l: L

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(l.accountUsageTitle).font(.callout.weight(.semibold))
            HStack(alignment: .firstTextBaseline) {
                Text(l.accountUsageLifetime).foregroundStyle(.secondary)
                Spacer()
                Text(usage?.summary?.lifetimeTokens.map { TokenFormatter.grouped($0, locale: l.lang.displayLocale) }
                     ?? l.accountUsageUnavailable)
                    .monospacedDigit()
            }
            .font(.caption)
            HStack {
                Text(l.accountUsageLatestDay).foregroundStyle(.secondary)
                Spacer()
                Text(usage?.latestReportedDay ?? l.accountUsageUnavailable).monospacedDigit()
            }
            .font(.caption)
            Text(l.accountUsageScopeHint)
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if refreshFailed || isUnavailable {
                Label(usage == nil ? l.accountUsageUnavailable : l.accountUsageLastReport,
                      systemImage: "exclamationmark.triangle")
                    .font(.caption2).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let updatedAt {
                (Text("\(l.updated) ") + Text(updatedAt, style: .relative))
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            if let buckets = usage?.dailyUsageBuckets, !buckets.isEmpty {
                DisclosureGroup(l.accountUsageDailyHistory) {
                    VStack(spacing: 4) {
                        Text(l.accountUsageDatesHint)
                            .font(.caption2).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        ForEach(Array(buckets.sorted { $0.startDate > $1.startDate }.enumerated()), id: \.offset) { _, bucket in
                            HStack {
                                Text(bucket.startDate)
                                Spacer()
                                Text(TokenFormatter.grouped(bucket.tokens, locale: l.lang.displayLocale))
                            }
                            .font(.caption2).monospacedDigit()
                        }
                    }
                    .padding(.top, 4)
                }
                .font(.caption)
            }
        }
        .accessibilityElement(children: .contain)
    }
}
