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

    /// Whether the first data-source determination (iCloud or local HTTP) has finished.
    /// Until then the app has not yet decided between setup and dashboard, so the UI
    /// shows an entry screen instead of flashing the setup view.
    var hasCompletedInitialFetch = false

    /// Mac host IP address or hostname.
    var host: String {
        didSet { defaults.set(host, forKey: "phoneHost") }
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
                    isConnected = true
                    saveToSharedContainer(newPayload)
                    return
                }
            } catch { /* fall through to HTTP */ }
        }

        // Local HTTP fallback
        guard !host.isEmpty else {
            lastError = "No data source available"
            isConnected = false
            return
        }
        do {
            let newPayload = try await client.fetch(host: host)
            payload = newPayload
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

    private func saveSpriteToSharedContainer(companion: PhoneCompanionState?) {
        guard let companion, let id = companion.speciesID else { return }
        let groupDir = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.io.github.chattymin.poketokenbar")?
            .appendingPathComponent("WidgetSprites", isDirectory: true)
        guard let groupDir else { return }
        try? FileManager.default.createDirectory(at: groupDir, withIntermediateDirectories: true)
        let file = groupDir.appendingPathComponent("\(id)_\(companion.isShiny).png")
        guard !FileManager.default.fileExists(atPath: file.path) else { return }
        let base = "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon"
        let suffix = companion.isShiny ? "shiny/\(id)" : "\(id)"
        guard let url = URL(string: "\(base)/\(suffix).png"),
              let imgData = try? Data(contentsOf: url) else { return }
        try? imgData.write(to: file)
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
