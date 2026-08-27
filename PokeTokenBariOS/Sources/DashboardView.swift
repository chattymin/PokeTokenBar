import SwiftUI
import PokeTokenBarShared

struct DashboardView: View {
    @Environment(PhonePayloadStore.self) private var store

    var body: some View {
        NavigationStack {
            Group {
                if !store.hasCompletedInitialFetch {
                    LaunchView()
                        .task { await store.fetch() }
                } else if store.host.isEmpty && store.payload == nil {
                    SetupView()
                } else if let payload = store.payload {
                    dashboardContent(payload)
                } else if store.isLoading {
                    ProgressView("Connecting to Mac...")
                } else if let error = store.lastError {
                    errorView(error)
                } else {
                    ProgressView("Connecting to Mac...")
                        .task { await store.fetch() }
                }
            }
            .navigationTitle("PokeTokenBar")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(destination: SettingsView().environment(store)) {
                        Image(systemName: "gear")
                    }
                }
            }
            .refreshable { await store.fetch() }
        }
    }

    @ViewBuilder
    private func dashboardContent(_ payload: PhonePayload) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                SourceIndicator(source: store.source, connected: store.isConnected, lastUpdated: payload.lastUpdated)

                if let companion = payload.companion {
                    CompanionCard(companion: companion)
                }

                UsageCard(payload: payload)

                if let limits = payload.limits {
                    LimitsCard(limits: limits)
                }

                if !payload.providers.isEmpty {
                    ForEach(payload.providers, id: \.id) { provider in
                        ProviderDetailCard(provider: provider)
                    }
                }

                Text("Mac app v\(payload.serverVersion)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding()
        }
    }

    @ViewBuilder
    private func errorView(_ error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.slash")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Cannot connect to Mac")
                .font(.headline)
            Text(error)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") { Task { await store.fetch() } }
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

// MARK: - Source indicator

/// Where the payload came from and how fresh it is. "Connected" was misleading for iCloud
/// (there is no live connection) — show the source and the Mac-side timestamp instead.
struct SourceIndicator: View {
    let source: PhonePayloadStore.Source?
    let connected: Bool
    let lastUpdated: Date

    private var isStale: Bool { Date().timeIntervalSince(lastUpdated) > 30 * 60 }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: source == .localNetwork ? "wifi" : "icloud")
                .font(.caption2)
                .foregroundStyle(connected && !isStale ? Color.green : (isStale ? Color.orange : Color.red))
            Text(sourceLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("·")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Text("updated \(lastUpdated, style: .relative) ago")
                .font(.caption)
                .foregroundStyle(isStale ? .orange : .secondary)
        }
    }

    private var sourceLabel: String {
        switch source {
        case .iCloud: return String(localized: "iCloud")
        case .localNetwork: return String(localized: "Local network")
        case nil: return String(localized: "Cached")
        }
    }
}

// MARK: - Companion Card

struct CompanionCard: View {
    let companion: PhoneCompanionState

    var body: some View {
        VStack(spacing: 12) {
            if companion.isEgg {
                Text("🥚")
                    .font(.system(size: 64))
                Text("Token Egg")
                    .font(.title2.bold())
                ProgressView(value: companion.eggProgress)
                    .tint(.purple)
                Text("\(Int(companion.eggProgress * 100))% hatched")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                if let id = companion.speciesID {
                    SpeciesSprite(speciesID: id, shiny: companion.isShiny, size: 96)
                }

                HStack {
                    Text(companion.name)
                        .font(.title2.bold())
                    if companion.isShiny {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                    }
                }

                if let rarity = companion.rarity {
                    Text(RarityStyle.label(rarity).uppercased())
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(rarityColor.opacity(0.2))
                        .foregroundStyle(rarityColor)
                        .clipShape(Capsule())
                }

                // Stage + nature on one line, same as the Mac header ("Stage 1/3 · Jolly").
                Text([companion.stageText, companion.natureText].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ProgressView(value: companion.progress)
                    .tint(companion.isShiny ? .yellow : .blue)

                if let evo = companion.evolutionTokens, evo > 0 {
                    Text("\(TokenFormatter.compact(evo)) to next evolution")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let nodes = companion.lineNodes, nodes.count > 1 {
                    EvolutionLineStrip(nodes: nodes)
                }
            }

            if let status = companion.statusText, !status.isEmpty {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .italic()
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var rarityColor: Color {
        RarityStyle.color(companion.rarity ?? "")
    }
}

/// Evolution line — done / current / future sprites with a "?" for an unrevealed branch,
/// mirroring the Mac's line strip. Scrolls horizontally for long lines.
struct EvolutionLineStrip: View {
    let nodes: [PhoneEvoNode]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(nodes.enumerated()), id: \.offset) { index, node in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    VStack(spacing: 2) {
                        Group {
                            if let id = node.speciesID {
                                SpeciesSprite(speciesID: id, shiny: false, size: 40)
                                    .saturation(node.state == .future ? 0 : 1)
                                    .opacity(node.state == .future ? 0.45 : 1)
                            } else {
                                Text("?")
                                    .font(.title3.bold())
                                    .foregroundStyle(.tertiary)
                                    .frame(width: 40, height: 40)
                            }
                        }
                        .padding(2)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(node.state == .current ? Color.accentColor : .clear, lineWidth: 1.5)
                        )
                        Text(node.name ?? "???")
                            .font(.system(size: 9))
                            .foregroundStyle(node.state == .current ? .primary : .secondary)
                            .lineLimit(1)
                    }
                    .frame(width: 56)
                }
            }
            .padding(.horizontal, 4)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Usage Card

struct UsageCard: View {
    let payload: PhonePayload

    var body: some View {
        VStack(spacing: 0) {
            statRow(icon: "calendar", title: String(localized: "Today"),
                    value: TokenFormatter.compact(payload.todayTokens),
                    cost: TokenFormatter.costCompact(payload.todayCost))
            Divider().padding(.horizontal)
            statRow(icon: "calendar.badge.clock", title: String(localized: "This Week"),
                    value: TokenFormatter.compact(payload.weekTokens),
                    cost: payload.weekCost.map(TokenFormatter.costCompact))
            Divider().padding(.horizontal)
            statRow(icon: "calendar.badge.plus", title: String(localized: "This Month"),
                    value: TokenFormatter.compact(payload.monthTokens),
                    cost: payload.monthCost.map(TokenFormatter.costCompact))
            if let burn = payload.burn, burn.depletionDate != nil || burn.tokensPerMinute != nil {
                Divider().padding(.horizontal)
                burnRow(burn)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func statRow(icon: String, title: String, value: String, cost: String?) -> some View {
        HStack {
            Label(title, systemImage: icon)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            if let cost {
                Text(cost)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.body.monospacedDigit().bold())
        }
        .padding(.vertical, 10)
    }

    /// Mac's "will hit the 5h limit at HH:mm" forecast row, plus the current burn rate.
    @ViewBuilder
    private func burnRow(_ burn: PhoneBurnForecast) -> some View {
        HStack {
            Label(String(localized: "Burn"), systemImage: "flame")
                .font(.subheadline)
                .foregroundStyle(burn.beforeReset ? .orange : .secondary)
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                if let at = burn.depletionDate {
                    Text(burn.beforeReset
                         ? String(localized: "5h limit at \(at.formatted(date: .omitted, time: .shortened))")
                         : String(localized: "Won't reach the 5h limit before reset"))
                        .font(.caption.weight(burn.beforeReset ? .semibold : .regular))
                        .foregroundStyle(burn.beforeReset ? .orange : .secondary)
                }
                if let tpm = burn.tokensPerMinute, tpm > 0 {
                    Text("\(TokenFormatter.compact(Int(tpm)))/min")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 10)
    }
}

// MARK: - Limits Card

/// One card per provider group (Claude / Codex / Go / Antigravity) driven by `limitGroups`, so any
/// window the Mac adds to the payload shows up here without another hand-written `if let`.
struct LimitsCard: View {
    let limits: PhoneLimitStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Rate Limits")
                    .font(.headline)
                Spacer()
                if let plan = limits.planDisplay {
                    Text(plan)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.blue.opacity(0.15))
                        .foregroundStyle(.blue)
                        .clipShape(Capsule())
                }
            }

            let groups = limits.limitGroups
            if groups.isEmpty {
                Text("No rate limits active")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                if index > 0 { Divider() }
                VStack(alignment: .leading, spacing: 8) {
                    if groups.count > 1 {
                        Text(group.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(Array(group.windows.enumerated()), id: \.offset) { _, w in
                        LimitRow(window: w, label: shortLabel(w.label, group: group.title), limits: limits)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    /// With a group header above, drop the repeated brand prefix ("Claude Weekly" → "Weekly").
    private func shortLabel(_ label: String, group: String) -> String {
        guard limits.limitGroups.count > 1, label.hasPrefix(group + " ") else { return label }
        let trimmed = String(label.dropFirst(group.count + 1))
        return trimmed.isEmpty ? label : trimmed
    }
}

struct LimitRow: View {
    let window: PhoneLimitWindow
    var label: String? = nil
    var limits: PhoneLimitStatus? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label ?? window.label)
                    .font(.subheadline)
                Spacer()
                if let resetsAt = window.resetsAt {
                    Text("resets \(resetsAt, style: .relative)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(TokenFormatter.percent(window.utilization))
                    .font(.subheadline.monospacedDigit().bold())
                    .foregroundStyle(utilizationColor)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.quaternary)
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(utilizationColor)
                        .frame(width: geo.size.width * min(1, window.utilization / 100), height: 8)
                        .animation(.easeInOut(duration: 0.3), value: window.utilization)
                }
            }
            .frame(height: 8)
        }
    }

    private var utilizationColor: Color {
        LimitColor.color(for: window.utilization, limits: limits)
    }
}

/// Utilization colour using the Mac's thresholds when the payload carries them.
enum LimitColor {
    static func color(for utilization: Double, limits: PhoneLimitStatus?) -> Color {
        let tier = limits?.tier(for: utilization) ?? fallbackTier(utilization)
        switch tier {
        case .critical: return .red
        case .warning: return .orange
        case .normal: return .blue
        }
    }

    private static func fallbackTier(_ u: Double) -> PhoneLimitTier {
        if u >= PhoneLimitStatus.defaultCritThreshold { return .critical }
        if u >= PhoneLimitStatus.defaultWarnThreshold { return .warning }
        return .normal
    }
}

// MARK: - Provider Detail Card (token breakdown)

struct ProviderDetailCard: View {
    let provider: PhoneProviderSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(provider.displayName)
                    .font(.headline)
                Spacer()
                Text(TokenFormatter.compact(provider.todayTokens))
                    .font(.subheadline.monospacedDigit().bold())
                if provider.reportsCost && provider.todayCost > 0 {
                    Text(TokenFormatter.cost(provider.todayCost))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if provider.inputTokens > 0 || provider.outputTokens > 0 {
                VStack(spacing: 4) {
                    tokenBar(label: "Input", value: provider.inputTokens, color: .blue)
                    tokenBar(label: "Output", value: provider.outputTokens, color: .green)
                    if provider.cacheWriteTokens > 0 {
                        tokenBar(label: "Cache Write", value: provider.cacheWriteTokens, color: .orange)
                    }
                    if provider.cacheReadTokens > 0 {
                        tokenBar(label: "Cache Read", value: provider.cacheReadTokens, color: .purple)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func tokenBar(label: String, value: Int, color: Color) -> some View {
        HStack {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color.opacity(0.15))
                        .frame(height: 6)
                    if provider.todayTokens > 0 {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(color)
                            .frame(width: geo.size.width * min(1, Double(value) / Double(max(provider.todayTokens, 1))), height: 6)
                    }
                }
            }
            .frame(height: 6)
            Text(TokenFormatter.compact(value))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .trailing)
        }
    }
}

// MARK: - Launch View

/// Entry screen shown while the first data-source determination (iCloud or local HTTP)
/// is in flight, so the setup view never flashes before a CloudKit payload lands.
struct LaunchView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "desktopcomputer.and.iphone")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("PokeTokenBar")
                .font(.title2.bold())
            ProgressView()
            Text("Looking for data source…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

// MARK: - Setup View

struct SetupView: View {
    @Environment(PhonePayloadStore.self) private var store
    @State private var hostInput = ""

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "desktopcomputer")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("Connect to Mac")
                .font(.title.bold())

            Text("Data syncs automatically via iCloud when both devices share the same Apple ID.\n\nFor local network sync, enter your Mac's IP address below.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            TextField("Mac IP Address (e.g. 192.168.1.42)", text: $hostInput)
                .textFieldStyle(.roundedBorder)
                .autocapitalization(.none)
                .autocorrectionDisabled()
                .keyboardType(.numbersAndPunctuation)
                .padding(.horizontal, 32)

            Button("Connect") {
                hostInput = hostInput.trimmingCharacters(in: .whitespaces)
                store.host = hostInput
                Task { await store.fetch() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(hostInput.trimmingCharacters(in: .whitespaces).isEmpty)

            Text("Find your Mac's IP in System Settings → Network, or enable the iPhone companion server in PokeTokenBar settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .navigationTitle("Setup")
    }
}
