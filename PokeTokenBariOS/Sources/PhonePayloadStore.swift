import Foundation
import Observation
import PokeTokenBarShared
import WidgetKit

/// Observable store that holds the latest phone payload and manages connection settings.
@MainActor
@Observable
final class PhonePayloadStore {
    private let client = PhonePayloadClient()
    private let defaults = UserDefaults.standard

    var payload: PhonePayload?
    var isLoading = false
    var lastError: String?
    var isConnected = false

    enum Source: String { case iCloud, localNetwork }
    /// Which channel delivered the current payload (nil before the first successful fetch).
    var source: Source?

    /// Whether the first data-source determination (iCloud or local HTTP) has finished.
    /// Until then the app has not yet decided between setup and dashboard, so the UI
    /// shows an entry screen instead of flashing the setup view.
    var hasCompletedInitialFetch = false

    /// Mac host IP address or hostname.
    var host: String {
        didSet { defaults.set(host, forKey: "phoneHost") }
    }

    /// Pairing code shown in the Mac app's Settings. The Mac server serves `/stats` to the
    /// whole LAN and advertises itself over Bonjour, so this is what distinguishes this phone
    /// from anyone else on the network. Stored uppercased — the code alphabet is uppercase.
    var pairingCode: String {
        didSet { defaults.set(pairingCode, forKey: "phonePairingCode") }
    }

    /// Auto-refresh interval in seconds (0 = manual only).
    var refreshInterval: TimeInterval {
        didSet { defaults.set(refreshInterval, forKey: "phoneRefreshInterval") }
    }

    /// App appearance preference (system, light, or dark).
    var appearance: AppAppearance {
        didSet { defaults.set(appearance.rawValue, forKey: "phoneAppearance") }
    }

    /// Hidden provider IDs preference.
    var hiddenProviderIDs: Set<String> {
        didSet {
            PayloadCache.saveHiddenProviders(hiddenProviderIDs)
            if let payload {
                saveToSharedContainer(payload)
            }
        }
    }

    func isProviderVisible(_ id: String) -> Bool {
        !hiddenProviderIDs.contains(id)
    }

    func setProvider(_ id: String, visible: Bool) {
        if visible {
            hiddenProviderIDs.remove(id)
        } else {
            hiddenProviderIDs.insert(id)
        }
    }

    var visibleProviders: [PhoneProviderSnapshot] {
        guard let providers = payload?.providers else { return [] }
        return providers.filter { isProviderVisible($0.id) }
    }

    var configurableProviders: [ProviderMetadata] {
        var result = ProviderMetadata.allKnown
        if let payloadProviders = payload?.providers {
            for p in payloadProviders {
                if !result.contains(where: { $0.id == p.id }) {
                    result.append(ProviderMetadata(id: p.id, displayName: p.displayName))
                }
            }
        }
        return result
    }

    private var timer: Timer?

    init() {
        self.host = defaults.string(forKey: "phoneHost") ?? ""
        self.pairingCode = defaults.string(forKey: "phonePairingCode") ?? ""
        self.refreshInterval = defaults.object(forKey: "phoneRefreshInterval") as? TimeInterval ?? 120
        self.appearance = AppAppearance(rawValue: defaults.string(forKey: "phoneAppearance") ?? "") ?? .system
        self.hiddenProviderIDs = PayloadCache.loadHiddenProviders()

        // Hydrate from cache immediately for 0ms cold-start
        if let cached = PayloadCache.loadPayload() {
            self.payload = cached
            self.hasCompletedInitialFetch = true
            if let savedSource = PayloadCache.loadLastSource(), let s = Source(rawValue: savedSource) {
                self.source = s
            }
        }

        reschedule()
    }

    func fetch() async {
        guard !isLoading else { return }
        isLoading = true
        lastError = nil
        defer {
            isLoading = false
            hasCompletedInitialFetch = true
        }

        // iCloud primary
        if await CloudKitSync.isAvailable() {
            do {
                if let newPayload = try await CloudKitSync.fetch() {
                    payload = newPayload
                    source = .iCloud
                    isConnected = true
                    saveToSharedContainer(newPayload)
                    return
                }
            } catch { /* fall through to HTTP */ }
        }

        // Local HTTP fallback
        guard !host.isEmpty else {
            if payload == nil {
                lastError = String(localized: "No data source available")
            }
            isConnected = false
            return
        }
        do {
            let newPayload = try await client.fetch(host: host, pairingCode: pairingCode)
            payload = newPayload
            source = .localNetwork
            isConnected = true
            saveToSharedContainer(newPayload)
        } catch {
            if payload == nil {
                lastError = error.localizedDescription
            }
            isConnected = false
        }
    }

    func checkConnection() async {
        guard !host.isEmpty else {
            isConnected = false
            return
        }
        isConnected = (try? await client.checkHealth(host: host)) ?? false
    }

    /// Called when the app resumes into foreground.
    /// Hydrates from the shared cache immediately if the widget or background fetch updated it,
    /// and triggers a background refresh.
    func handleAppForeground() {
        if let cached = PayloadCache.loadPayload() {
            let cachedDate = cached.lastUpdated
            let currentDate = payload?.lastUpdated ?? .distantPast
            if cachedDate > currentDate {
                payload = cached
                if let savedSource = PayloadCache.loadLastSource(), let s = Source(rawValue: savedSource) {
                    source = s
                }
            }
        }
        Task { await fetch() }
    }

    // MARK: - App Group Sharing (for Widget)

    private func saveToSharedContainer(_ payload: PhonePayload) {
        PayloadCache.save(payload: payload, source: source?.rawValue)
        PayloadCache.saveHiddenProviders(hiddenProviderIDs)
        prefetchAssets(for: payload)
    }

    /// Warm the shared sprite cache for companion, dex, and shop/bag item sprites
    /// so the widget and offline tabs can render right away.
    private func prefetchAssets(for payload: PhonePayload) {
        var pairs: [(id: Int, shiny: Bool)] = []
        if let companion = payload.companion {
            if let id = companion.speciesID { pairs.append((id, companion.isShiny)) }
            if let rep = companion.representativeSpeciesID {
                pairs.append((rep, companion.representativeIsShiny ?? false))
            }
        }
        // Prefetch collection species so dex works offline
        for sp in payload.dex {
            pairs.append((sp.id, sp.isShiny))
        }

        var itemNames: Set<String> = []
        for item in payload.bag {
            if let icon = item.iconName, !icon.isEmpty { itemNames.insert(icon) }
        }
        for entry in payload.shop {
            if let icon = entry.iconName, !icon.isEmpty { itemNames.insert(icon) }
        }

        Task.detached(priority: .utility) {
            await SpriteCache.shared.prefetchSpecies(pairs)
            if !itemNames.isEmpty {
                await SpriteCache.shared.prefetchItems(Array(itemNames))
            }
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    // MARK: - Auto-refresh

    private func reschedule() {
        timer?.invalidate()
        timer = nil
        guard refreshInterval > 0 else { return }
        let t = Timer(timeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.fetch() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
}
