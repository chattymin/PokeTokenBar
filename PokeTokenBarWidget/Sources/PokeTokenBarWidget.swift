import WidgetKit
import SwiftUI
import PokeTokenBarShared

@main
struct PokeTokenBarWidget: Widget {
    let kind: String = "PokeTokenBarWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WidgetTimelineProvider()) { entry in
            PokeTokenBarWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("PokeTokenBar")
        .description("Your AI token usage at a glance.")
        .supportedFamilies([.systemMedium])
    }
}

// MARK: - Timeline Provider

struct WidgetTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> WidgetEntry {
        WidgetEntry(date: Date(), payload: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (WidgetEntry) -> Void) {
        completion(WidgetEntry(date: Date(), payload: loadPayload()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetEntry>) -> Void) {
        let entry = WidgetEntry(date: Date(), payload: loadPayload())
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)

        Task.detached(priority: .utility) {
            guard let ck = try? await CloudKitSync.fetch() else { return }
            WidgetTimelineProvider.persistPayload(ck)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    private func loadPayload() -> PhonePayload? {
        guard let data = UserDefaults(suiteName: "group.io.github.chattymin.poketokenbar")?
            .data(forKey: "latestPayload") else { return nil }
        return try? JSONDecoder().decode(PhonePayload.self, from: data)
    }

    static func persistPayload(_ payload: PhonePayload) {
        guard let data = try? JSONEncoder().encode(payload) else { return }
        let suite = UserDefaults(suiteName: "group.io.github.chattymin.poketokenbar")
        suite?.set(data, forKey: "latestPayload")
        suite?.set(Date(), forKey: "lastFetchTime")
    }
}

// MARK: - Timeline Entry

struct WidgetEntry: TimelineEntry {
    let date: Date
    let payload: PhonePayload?
}

// MARK: - Widget Views

/// Medium-only widget. Left: companion sprite + name + stage progress + sync age.
/// Right: headline usage row (Today / Cost / Week) and one bar per limit window,
/// switching to two columns when there are more than four windows so nothing is dropped.
struct PokeTokenBarWidgetEntryView: View {
    let entry: WidgetEntry

    var body: some View {
        if let payload = entry.payload {
            mediumView(payload)
        } else {
            emptyView
        }
    }

    private var emptyView: some View {
        VStack(spacing: 6) {
            Image(systemName: "gamecontroller")
                .font(.title)
            Text("PokeTokenBar")
                .font(.headline)
            Text("Open the app to sync from your Mac")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Medium Widget

    private func mediumView(_ payload: PhonePayload) -> some View {
        HStack(alignment: .top, spacing: 12) {
            companionColumn(payload)
                .frame(width: 78)

            VStack(alignment: .leading, spacing: 6) {
                headlineRow(payload)

                if let limits = payload.limits, !limits.orderedWindows.isEmpty {
                    Divider()
                    limitBars(limits)
                } else {
                    Spacer(minLength: 0)
                    Text("No rate limits active")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func companionColumn(_ payload: PhonePayload) -> some View {
        VStack(spacing: 4) {
            if let companion = payload.companion {
                spriteImage(companion: companion)
                    .frame(width: 56, height: 56)

                HStack(spacing: 2) {
                    Text(companion.name)
                        .font(.caption.bold())
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if companion.representativeSpeciesID != nil ? (companion.representativeIsShiny ?? false) : companion.isShiny {
                        Image(systemName: "sparkles")
                            .font(.system(size: 9))
                            .foregroundStyle(.yellow)
                    }
                }

                // Egg hatch or evolution progress — same bar the app's dashboard shows.
                let progress = companion.isEgg ? companion.eggProgress : companion.progress
                ProgressView(value: min(1, max(0, progress)))
                    .tint(companion.isEgg ? .orange : .blue)
                    .scaleEffect(x: 1, y: 0.6, anchor: .center)
            } else {
                Image(systemName: "gamecontroller")
                    .font(.title)
                    .frame(height: 56)
                Text("No companion")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            // Staleness at a glance: the widget only re-renders when the app/CloudKit hands it a payload.
            Text(payload.lastUpdated, style: .relative)
                .font(.system(size: 9).monospacedDigit())
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxHeight: .infinity)
    }

    /// Today tokens dominant, cost and week as smaller companions on the same baseline.
    private func headlineRow(_ payload: PhonePayload) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            stat(label: String(localized: "Today"), value: TokenFormatter.compact(payload.todayTokens), prominent: true)
            stat(label: String(localized: "Cost"), value: TokenFormatter.costCompact(payload.todayCost), prominent: false)
            stat(label: String(localized: "Week"), value: TokenFormatter.compact(payload.weekTokens), prominent: false)
            Spacer(minLength: 0)
        }
    }

    private func stat(label: String, value: String, prominent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(value)
                .font(prominent ? .title3.monospacedDigit().bold() : .subheadline.monospacedDigit().weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    /// One bar per window in orderedWindows order. ≤4 windows: single column with reset countdown.
    /// >4: two columns (countdown dropped for room) so every provider stays visible.
    @ViewBuilder
    private func limitBars(_ limits: PhoneLimitStatus) -> some View {
        let rows = limits.limitGroups.flatMap { group in
            group.windows.map { LimitBarRow(title: shortLabel($0.label, group: group.title), window: $0) }
        }
        if rows.count <= 4 {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    limitBar(row, showsReset: true)
                }
            }
        } else {
            // Five two-column rows is the most the medium height holds; anything beyond is summarised.
            // Column-major so provider groups stay together (Claude ×3 | Go ×3) instead of
            // interleaving row by row.
            let visible = Array(rows.prefix(Self.maxDenseRows))
            let half = (visible.count + 1) / 2
            let columns = [Array(visible[0..<half]), Array(visible[half...])]
            HStack(alignment: .top, spacing: 10) {
                ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(column.enumerated()), id: \.offset) { _, row in
                            limitBar(row, showsReset: false, dense: true)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            if rows.count > visible.count {
                Text("+\(rows.count - visible.count) more in app")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    /// "Claude Weekly" → "Claude · Weekly": keeps the brand prefix the Mac already localised
    /// but visually separates it from the window so the eye can scan the column.
    private func shortLabel(_ label: String, group: String) -> String {
        let trimmed = label.hasPrefix(group + " ")
            ? String(label.dropFirst(group.count + 1)) : label
        return trimmed.isEmpty ? group : "\(group) · \(trimmed)"
    }

    private static let maxDenseRows = 10

    private func limitBar(_ row: LimitBarRow, showsReset: Bool, dense: Bool = false) -> some View {
        let color = limitBarColor(row.window.utilization)
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(row.title)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 2)
                if showsReset, let resetsAt = row.window.resetsAt, resetsAt > entry.date {
                    Text(resetsAt, style: .timer)
                        .font(.system(size: 9).monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Text(TokenFormatter.percent(row.window.utilization))
                    .font(.system(size: 10, weight: .bold).monospacedDigit())
                    .foregroundStyle(color)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(color)
                        .frame(width: geo.size.width * min(1, max(0, row.window.utilization / 100)))
                }
            }
            .frame(height: dense ? 4 : 5)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    /// Mirrors the Mac menu bar: the pinned representative species when set, else the current mon.
    @ViewBuilder
    private func spriteImage(companion: PhoneCompanionState) -> some View {
        let id = companion.representativeSpeciesID ?? companion.speciesID
        let shiny = companion.representativeSpeciesID != nil
            ? (companion.representativeIsShiny ?? false) : companion.isShiny
        if let id, let img = SpriteCache.shared.cachedImage(key: PokeSpriteURL.speciesKey(id: id, shiny: shiny)) {
            Image(uiImage: img)
                .resizable()
                .interpolation(.none)
        } else if companion.isEgg {
            Text("🥚").font(.system(size: 40))
        } else if let id {
            // Not cached yet (app hasn't run since this mon appeared) — the widget may not get
            // network, so fall back to the Mac-side name over a placeholder rather than spinning.
            AsyncImage(url: PokeSpriteURL.species(id: id, shiny: shiny)) { image in
                image.resizable().interpolation(.none)
            } placeholder: {
                Image(systemName: "questionmark.circle").font(.title).foregroundStyle(.tertiary)
            }
        } else {
            Image(systemName: "questionmark")
        }
    }

    /// Same colour rule as the Mac — thresholds travel in the payload.
    private func limitBarColor(_ utilization: Double) -> Color {
        switch entry.payload?.limits?.tier(for: utilization) {
        case .critical: return .red
        case .warning: return .orange
        default:
            if utilization >= PhoneLimitStatus.defaultCritThreshold { return .red }
            if utilization >= PhoneLimitStatus.defaultWarnThreshold { return .orange }
            return .blue
        }
    }
}

// MARK: - Preview

#Preview("Basic", as: .systemMedium) {
    PokeTokenBarWidget()
} timeline: {
    WidgetEntry(date: Date(), payload: PhonePayload(
        todayTokens: 1_500_000, todayCost: 12.34, weekTokens: 10_000_000,
        monthTokens: 40_000_000, lastUpdated: Date(), serverVersion: "1.0",
        limits: PhoneLimitStatus(claude5h: PhoneLimitWindow(label: "5h", utilization: 65, resetsAt: Date().addingTimeInterval(2 * 3600 + 720)),
                                  claudeWeekly: PhoneLimitWindow(label: "Weekly", utilization: 32, resetsAt: Date().addingTimeInterval(3 * 86400)),
                                  claudeOpusWeekly: nil, claudeSonnetWeekly: nil,
                                  codexPrimary: nil, codexSecondary: nil, planDisplay: "Max 20x"),
        companion: PhoneCompanionState(name: "Pikachu", speciesID: 25, isShiny: true, isEgg: false,
                                        progress: 0.42, stageText: "Stage 1/3", rarity: "rare",
                                        dexCount: 12, eggProgress: 0, displayState: "working"),
        providers: [
            PhoneProviderSnapshot(id: "claude_code", displayName: "Claude", todayTokens: 1_000_000, todayCost: 10.0),
            PhoneProviderSnapshot(id: "codex", displayName: "Codex", todayTokens: 500_000, todayCost: 2.34),
        ]))
}

#Preview("Many windows", as: .systemMedium) {
    PokeTokenBarWidget()
} timeline: {
    WidgetEntry(date: Date(), payload: PhonePayload(
        todayTokens: 1_500_000, todayCost: 12.34, weekTokens: 10_000_000,
        monthTokens: 40_000_000, lastUpdated: Date(), serverVersion: "1.0",
        limits: PhoneLimitStatus(claude5h: PhoneLimitWindow(label: "Claude 5h", utilization: 82, resetsAt: nil),
                                  claudeWeekly: PhoneLimitWindow(label: "Claude Weekly", utilization: 45, resetsAt: nil),
                                  claudeOpusWeekly: nil,
                                  claudeSonnetWeekly: nil,
                                  claudeScoped: [PhoneLimitWindow(label: "Claude Weekly Fable", utilization: 97, resetsAt: nil)],
                                  codexPrimary: PhoneLimitWindow(label: "Codex 5h", utilization: 61, resetsAt: nil),
                                  codexSecondary: nil,
                                  opencodeGo5h: PhoneLimitWindow(label: "Go 5h", utilization: 92, resetsAt: nil),
                                  opencodeGoWeekly: PhoneLimitWindow(label: "Go Weekly", utilization: 74, resetsAt: nil),
                                  opencodeGoMonthly: PhoneLimitWindow(label: "Go Monthly", utilization: 38, resetsAt: nil),
                                  planDisplay: "Max 20x"),
        companion: PhoneCompanionState(name: "Pikachu", speciesID: 25, isShiny: true, isEgg: false,
                                        progress: 0.42, stageText: "Stage 1/3", rarity: "rare",
                                        dexCount: 12, eggProgress: 0, displayState: "working"),
        providers: [
            PhoneProviderSnapshot(id: "claude_code", displayName: "Claude", todayTokens: 1_000_000, todayCost: 10.0),
            PhoneProviderSnapshot(id: "codex", displayName: "Codex", todayTokens: 500_000, todayCost: 2.34),
        ]))
}

/// A limit window paired with its display title (group-prefixed).
private struct LimitBarRow {
    let title: String
    let window: PhoneLimitWindow
}
