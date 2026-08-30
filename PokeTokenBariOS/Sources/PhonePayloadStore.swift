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

    enum Source { case iCloud, localNetwork }
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

    private var timer: Timer?

    init() {
        self.host = defaults.string(forKey: "phoneHost") ?? ""
        self.pairingCode = defaults.string(forKey: "phonePairingCode") ?? ""
        self.refreshInterval = defaults.object(forKey: "phoneRefreshInterval") as? TimeInterval ?? 120
        self.appearance = AppAppearance(rawValue: defaults.string(forKey: "phoneAppearance") ?? "") ?? .system
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
            lastError = String(localized: "No data source available")
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
            lastError = error.localizedDescription
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

    // MARK: - App Group Sharing (for Widget)

    private func saveToSharedContainer(_ payload: PhonePayload) {
        guard let data = try? JSONEncoder().encode(payload) else { return }
        let suite = UserDefaults(suiteName: "group.io.github.chattymin.poketokenbar")
        suite?.set(data, forKey: "latestPayload")
        suite?.set(Date(), forKey: "lastFetchTime")
        saveSpriteToSharedContainer(companion: payload.companion)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Warm the shared sprite cache so the widget (which never hits the network) can render the
    /// current and representative mon right away.
    private func saveSpriteToSharedContainer(companion: PhoneCompanionState?) {
        guard let companion else { return }
        var pairs: [(id: Int, shiny: Bool)] = []
        if let id = companion.speciesID { pairs.append((id, companion.isShiny)) }
        if let rep = companion.representativeSpeciesID {
            pairs.append((rep, companion.representativeIsShiny ?? false))
        }
        Task.detached(priority: .utility) {
            await SpriteCache.shared.prefetchSpecies(pairs)
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
