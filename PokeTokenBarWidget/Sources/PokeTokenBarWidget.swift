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
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
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

struct PokeTokenBarWidgetEntryView: View {
    let entry: WidgetEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:
            smallView
        case .systemMedium:
            mediumView
        case .systemLarge:
            largeView
        default:
            smallView
        }
    }

    // MARK: - Small Widget

    private var smallView: some View {
        VStack(spacing: 4) {
            if let payload = entry.payload, let companion = payload.companion {
                spriteImage(companion: companion)
                    .frame(width: 48, height: 48)

                Text(companion.name)
                    .font(.caption.bold())
                    .lineLimit(1)

                if companion.isShiny {
                    Text("★ Shiny")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                }

                Divider()

                statLine(label: "Today", value: TokenFormatter.compact(payload.todayTokens))

                if let limits = payload.limits, let w = limits.claude5h {
                    Divider()
                    HStack {
                        Text("5h")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(TokenFormatter.percent(w.utilization))
                            .font(.caption2.monospacedDigit().bold())
                            .foregroundStyle(w.utilization >= 95 ? .red :
                                                w.utilization >= 80 ? .orange : .primary)
                    }
                }
            } else {
                Image(systemName: "gamecontroller")
                    .font(.title2)
                Text("PokeTokenBar")
                    .font(.caption)
                Text("Open app to sync")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Medium Widget

    private var mediumView: some View {
        HStack(spacing: 10) {
            VStack(spacing: 4) {
                if let payload = entry.payload, let companion = payload.companion {
                    spriteImage(companion: companion)
                        .frame(width: 52, height: 52)

                    Text(companion.name)
                        .font(.caption.bold())
                        .lineLimit(1)

                    if companion.isShiny {
                        Text("★")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }
                } else {
                    Image(systemName: "gamecontroller")
                        .font(.title)
                    Text("No Data")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minWidth: 80)

            Divider()

            VStack(alignment: .leading, spacing: 5) {
                if let payload = entry.payload {
                    statLine(label: "Today", value: TokenFormatter.compact(payload.todayTokens))
                    statLine(label: "Cost", value: TokenFormatter.costCompact(payload.todayCost))
                    statLine(label: "Week", value: TokenFormatter.compact(payload.weekTokens))

                    if let limits = payload.limits {
                        Divider()
                        if let w = limits.claude5h {
                            limitLine(label: "Claude 5h", utilization: w.utilization)
                        }
                        if let w = limits.claudeWeekly {
                            limitLine(label: "Weekly", utilization: w.utilization)
                        }
                        if let w = limits.codexPrimary {
                            limitLine(label: "Codex", utilization: w.utilization)
                        }
                    }
                } else {
                    Text("Open app to fetch")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // MARK: - Large Widget

    private var largeView: some View {
        VStack(spacing: 8) {
            if let payload = entry.payload, let companion = payload.companion {
                HStack(spacing: 12) {
                    spriteImage(companion: companion)
                        .frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(companion.name).font(.headline)
                            if companion.isShiny {
                                Image(systemName: "star.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.yellow)
                            }
                        }
                        Text(companion.stageText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        ProgressView(value: companion.progress)
                            .tint(.blue)
                            .frame(height: 4)
                    }
                }

                Divider()

                VStack(spacing: 4) {
                    statLine(label: "Today", value: TokenFormatter.compact(payload.todayTokens))
                    statLine(label: "Cost", value: TokenFormatter.costCompact(payload.todayCost))
                    statLine(label: "Week", value: TokenFormatter.compact(payload.weekTokens))
                    statLine(label: "Month", value: TokenFormatter.compact(payload.monthTokens))
                }

                if let limits = payload.limits {
                    Divider()
                    VStack(spacing: 6) {
                        if let w = limits.claude5h {
                            limitBar(label: "Claude 5h", utilization: w.utilization)
                        }
                        if let w = limits.claudeWeekly {
                            limitBar(label: "Weekly", utilization: w.utilization)
                        }
                        if let w = limits.claudeOpusWeekly {
                            limitBar(label: "Weekly Fable", utilization: w.utilization)
                        } else if let w = limits.claudeSonnetWeekly {
                            limitBar(label: "Weekly Fable", utilization: w.utilization)
                        }
                    }
                }

                if !payload.providers.isEmpty {
                    Divider()
                    ForEach(payload.providers, id: \.id) { p in
                        statLine(label: p.displayName, value: TokenFormatter.compact(p.todayTokens))
                    }
                }
            } else {
                Image(systemName: "gamecontroller")
                    .font(.largeTitle)
                Text("PokeTokenBar")
                    .font(.headline)
                Text("Open app to sync data")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func spriteImage(companion: PhoneCompanionState) -> some View {
        if companion.isEgg {
            Text("🥚").font(.system(size: 40))
        } else if let id = companion.speciesID {
            if let img = loadSprite(id: id, shiny: companion.isShiny) {
                Image(uiImage: img)
                    .resizable()
                    .interpolation(.none)
            } else {
                AsyncImage(url: URL(string: "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/\(companion.isShiny ? "shiny/" : "")\(id).png")) { image in
                    image.resizable().interpolation(.none)
                } placeholder: {
                    ProgressView()
                }
            }
        } else {
            Image(systemName: "questionmark")
        }
    }

    private func loadSprite(id: Int, shiny: Bool) -> UIImage? {
        guard let groupDir = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.io.github.chattymin.poketokenbar")?
            .appendingPathComponent("WidgetSprites", isDirectory: true) else { return nil }
        let file = groupDir.appendingPathComponent("\(id)_\(shiny).png")
        guard let data = try? Data(contentsOf: file) else { return nil }
        return UIImage(data: data)
    }

    @ViewBuilder
    private func statLine(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.monospacedDigit().bold())
        }
    }

    @ViewBuilder
    private func limitLine(label: String, utilization: Double) -> some View {
        HStack {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Text(TokenFormatter.percent(utilization))
                .font(.caption2.monospacedDigit().bold())
                .foregroundStyle(utilization >= 95 ? .red :
                                    utilization >= 80 ? .orange : .primary)
        }
    }

    @ViewBuilder
    private func limitBar(label: String, utilization: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(TokenFormatter.percent(utilization))
                    .font(.caption2.monospacedDigit().bold())
                    .foregroundStyle(limitBarColor(utilization))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.quaternary)
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(limitBarColor(utilization))
                        .frame(width: geo.size.width * min(1, utilization / 100), height: 6)
                }
            }
            .frame(height: 6)
        }
    }

    private func limitBarColor(_ utilization: Double) -> Color {
        if utilization >= 95 { return .red }
        if utilization >= 80 { return .orange }
        return .blue
    }
}

// MARK: - Preview

#Preview(as: .systemSmall) {
    PokeTokenBarWidget()
} timeline: {
    WidgetEntry(date: Date(), payload: PhonePayload(
        todayTokens: 1_500_000, todayCost: 12.34, weekTokens: 10_000_000,
        monthTokens: 40_000_000, lastUpdated: Date(), serverVersion: "1.0",
        limits: PhoneLimitStatus(claude5h: PhoneLimitWindow(label: "5h", utilization: 65, resetsAt: nil),
                                  claudeWeekly: nil, claudeOpusWeekly: nil, claudeSonnetWeekly: nil,
                                  codexPrimary: nil, codexSecondary: nil, planDisplay: "Max 20x"),
        companion: PhoneCompanionState(name: "Pikachu", speciesID: 25, isShiny: false, isEgg: false,
                                        progress: 0.42, stageText: "Stage 1/3", rarity: "common",
                                        dexCount: 12, eggProgress: 0, displayState: "working"),
        providers: [PhoneProviderSnapshot(id: "claude_code", displayName: "Claude",
                                          todayTokens: 1_000_000, todayCost: 10.0)]))
}

#Preview(as: .systemMedium) {
    PokeTokenBarWidget()
} timeline: {
    WidgetEntry(date: Date(), payload: PhonePayload(
        todayTokens: 1_500_000, todayCost: 12.34, weekTokens: 10_000_000,
        monthTokens: 40_000_000, lastUpdated: Date(), serverVersion: "1.0",
        limits: PhoneLimitStatus(claude5h: PhoneLimitWindow(label: "5h", utilization: 65, resetsAt: nil),
                                  claudeWeekly: PhoneLimitWindow(label: "Weekly", utilization: 32, resetsAt: nil),
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

#Preview(as: .systemLarge) {
    PokeTokenBarWidget()
} timeline: {
    WidgetEntry(date: Date(), payload: PhonePayload(
        todayTokens: 1_500_000, todayCost: 12.34, weekTokens: 10_000_000,
        monthTokens: 40_000_000, lastUpdated: Date(), serverVersion: "1.0",
        limits: PhoneLimitStatus(claude5h: PhoneLimitWindow(label: "5h", utilization: 82, resetsAt: nil),
                                  claudeWeekly: PhoneLimitWindow(label: "Weekly", utilization: 45, resetsAt: nil),
                                  claudeOpusWeekly: PhoneLimitWindow(label: "Weekly Fable", utilization: 97, resetsAt: nil),
                                  claudeSonnetWeekly: nil,
                                  codexPrimary: nil, codexSecondary: nil, planDisplay: "Max 20x"),
        companion: PhoneCompanionState(name: "Pikachu", speciesID: 25, isShiny: true, isEgg: false,
                                        progress: 0.42, stageText: "Stage 1/3", rarity: "rare",
                                        dexCount: 12, eggProgress: 0, displayState: "working"),
        providers: [
            PhoneProviderSnapshot(id: "claude_code", displayName: "Claude", todayTokens: 1_000_000, todayCost: 10.0),
            PhoneProviderSnapshot(id: "codex", displayName: "Codex", todayTokens: 500_000, todayCost: 2.34),
        ]))
}
