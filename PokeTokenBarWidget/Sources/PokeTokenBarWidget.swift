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

                    if let limits = payload.limits, !limits.orderedWindows.isEmpty {
                        Divider()
                        // 중간 위젯은 높이가 빠듯해 상위 3개 창만(전체는 large 위젯에서).
                        ForEach(Array(limits.orderedWindows.prefix(3).enumerated()), id: \.offset) { _, w in
                            limitLine(label: w.label, utilization: w.utilization)
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
                }

                // 모든 프로바이더의 한도 창을 한 줄씩 condense 해 표시(라벨은 Mac 이 프로바이더 접두어와
                // 함께 현지화해 보낸다). 창이 많아도 large 위젯 높이에 맞도록 바 대신 한 줄 행을 쓴다.
                if let limits = payload.limits, !limits.orderedWindows.isEmpty {
                    Divider()
                    VStack(spacing: 3) {
                        ForEach(Array(limits.orderedWindows.enumerated()), id: \.offset) { _, w in
                            limitLine(label: w.label, utilization: w.utilization)
                        }
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
