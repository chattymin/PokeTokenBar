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
                        // 프로바이더별 그룹 행 — 제목 뒤에 파이+퍼센트 칩이 이어지고, 좁으면 다음 줄로 흐른다.
                        // 창 라벨("Claude 5h")을 매 칩마다 반복하는 대신 그룹 제목("Claude")으로 접두어 반복을 없앤다.
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(Array(limits.limitGroups.enumerated()), id: \.offset) { _, group in
                                FlowLayout(spacing: 5) {
                                    Text(group.title)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    ForEach(Array(group.windows.enumerated()), id: \.offset) { _, w in
                                        limitChip(w)
                                    }
                                }
                            }
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

                // 프로바이더 카테고리(claude/codex/go) 아래 모든 timeframe 을 한 줄로 — 각 칩은
                // 파이 표시기(한눈에 빈/참 파악) + 퍼센트. 창 순서 = orderedWindows(5h→주간→월간…).
                if let limits = payload.limits, !limits.orderedWindows.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(limits.limitGroups.enumerated()), id: \.offset) { _, group in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(group.title)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                FlowLayout(spacing: 6) {
                                    ForEach(Array(group.windows.enumerated()), id: \.offset) { _, w in
                                        limitChip(w)
                                    }
                                }
                            }
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

    /// 한도 칩 — 파이 표시기(퍼센트 텍스트와 같은 높이, 빈/참을 한눈에) + 퍼센트. 색은 임계 공통 규칙.
    @ViewBuilder
    private func limitChip(_ w: PhoneLimitWindow) -> some View {
        HStack(spacing: 2) {
            LimitPieIndicator(utilization: w.utilization)
                .frame(width: 10, height: 10)
            Text(TokenFormatter.percent(w.utilization))
                .font(.caption2.monospacedDigit().bold())
                .foregroundStyle(limitBarColor(w.utilization))
        }
    }

    private func limitBarColor(_ utilization: Double) -> Color {
        if utilization >= 95 { return .red }
        if utilization >= 80 { return .orange }
        return .blue
    }
}

/// 미니 파이 표시기 — 12시 방향에서 시계 방향으로 사용률만큼 채운 원. 퍼센트 텍스트와 나란히
/// 같은 높이로 놓여 "읽기 전에" 빈/참을 보여 준다.
private struct LimitPieIndicator: View {
    let utilization: Double

    var body: some View {
        ZStack {
            Circle().fill(.quaternary)
            PieShape(fraction: min(1, max(0, utilization / 100)))
                .fill(color)
        }
    }

    private var color: Color {
        if utilization >= 95 { return .red }
        if utilization >= 80 { return .orange }
        return .blue
    }
}

/// 사용률 비율의 부채꼴(wedge) — fraction 0…1.
private struct PieShape: Shape {
    var fraction: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard fraction > 0 else { return path }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        path.move(to: center)
        path.addArc(
            center: center, radius: radius,
            startAngle: .degrees(-90),
            endAngle: .degrees(-90 + 360 * fraction),
            clockwise: false)
        path.closeSubpath()
        return path
    }
}

/// 좁으면 다음 줄로 흐르는 HStack — 위젯 폭에서 칩 개수가 가변일 때(그룹 제목+칩들) 잘린다.
private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        layout(subviews: subviews, maxWidth: proposal.width ?? .infinity).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(subviews: subviews, maxWidth: bounds.width)
        for (subview, origin) in zip(subviews, result.origins) {
            subview.place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                anchor: .topLeading,
                proposal: .unspecified)
        }
    }

    private func layout(subviews: Subviews, maxWidth: CGFloat) -> (size: CGSize, origins: [CGPoint]) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxRowWidth: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                maxRowWidth = max(maxRowWidth, x)
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        maxRowWidth = max(maxRowWidth, x - spacing)
        return (CGSize(width: maxRowWidth, height: y + rowHeight), origins)
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
