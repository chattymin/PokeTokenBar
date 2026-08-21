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
                ConnectionIndicator(connected: store.isConnected)

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

                Text("Updated \(payload.lastUpdated, style: .relative) ago")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

// MARK: - Connection

struct ConnectionIndicator: View {
    let connected: Bool
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(connected ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            Text(connected ? "Connected" : "Disconnected")
                .font(.caption)
                .foregroundStyle(.secondary)
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
                AsyncImage(url: spriteURL) { image in
                    image.resizable().interpolation(.none)
                } placeholder: {
                    ProgressView()
                }
                .frame(width: 96, height: 96)

                HStack {
                    Text(companion.name)
                        .font(.title2.bold())
                    if companion.isShiny {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                    }
                }

                if let rarity = companion.rarity {
                    Text(rarity.uppercased())
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(rarityColor.opacity(0.2))
                        .foregroundStyle(rarityColor)
                        .clipShape(Capsule())
                }

                Text(companion.stageText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ProgressView(value: companion.progress)
                    .tint(companion.isShiny ? .yellow : .blue)

                if let evo = companion.evolutionTokens, evo > 0 {
                    Text("\(TokenFormatter.compact(evo)) to next evolution")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var spriteURL: URL? {
        guard let id = companion.speciesID else { return nil }
        return PokeSprite.speciesURL(id: id, shiny: companion.isShiny)
    }

    private var rarityColor: Color {
        RarityStyle.color(companion.rarity ?? "")
    }
}

// MARK: - Usage Card

struct UsageCard: View {
    let payload: PhonePayload

    var body: some View {
        VStack(spacing: 0) {
            statRow(icon: "calendar", title: "Today",
                    value: TokenFormatter.compact(payload.todayTokens))
            Divider().padding(.horizontal)
            statRow(icon: "dollarsign.circle", title: "Cost",
                    value: TokenFormatter.costCompact(payload.todayCost))
            Divider().padding(.horizontal)
            statRow(icon: "calendar.badge.clock", title: "This Week",
                    value: TokenFormatter.compact(payload.weekTokens))
            Divider().padding(.horizontal)
            statRow(icon: "calendar.badge.plus", title: "This Month",
                    value: TokenFormatter.compact(payload.monthTokens))
        }
        .padding(.vertical, 4)
        .padding(.horizontal)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func statRow(icon: String, title: String, value: String) -> some View {
        HStack {
            Label(title, systemImage: icon)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.body.monospacedDigit().bold())
        }
        .padding(.vertical, 10)
    }
}

// MARK: - Limits Card

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

            if let w = limits.claude5h {
                LimitRow(window: w)
            }
            if let w = limits.claudeWeekly {
                LimitRow(window: w)
            }
            if let w = limits.claudeOpusWeekly {
                LimitRow(window: w)
            }
            if let w = limits.claudeSonnetWeekly {
                LimitRow(window: w)
            }
            if let w = limits.codexPrimary {
                LimitRow(window: w)
            }
            if let w = limits.codexSecondary {
                LimitRow(window: w)
            }
            if let w = limits.opencodeGo5h {
                LimitRow(window: w)
            }
            if let w = limits.opencodeGoWeekly {
                LimitRow(window: w)
            }
            if let w = limits.opencodeGoMonthly {
                LimitRow(window: w)
            }

            if limits.claude5h == nil && limits.claudeWeekly == nil && limits.claudeOpusWeekly == nil
                && limits.claudeSonnetWeekly == nil && limits.codexPrimary == nil && limits.codexSecondary == nil
                && limits.opencodeGo5h == nil && limits.opencodeGoWeekly == nil && limits.opencodeGoMonthly == nil {
                Text("No rate limits active")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct LimitRow: View {
    let window: PhoneLimitWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(window.label)
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
        if window.utilization >= 95 { return .red }
        if window.utilization >= 80 { return .orange }
        return .blue
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
