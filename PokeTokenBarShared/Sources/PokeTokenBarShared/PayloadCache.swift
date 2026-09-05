import Foundation

/// Unified cache manager for `PhonePayload` and related sync metadata.
/// Shared between the iOS app and Widget extensions.
public enum PayloadCache: Sendable {
    public static let appGroup = "group.io.github.chattymin.poketokenbar"
    public static let payloadKey = "latestPayload"
    public static let lastFetchTimeKey = "lastFetchTime"
    public static let lastSourceKey = "lastPayloadSource"
    public static let hiddenProvidersKey = "phoneHiddenProviders"

    /// The App Group UserDefaults suite, if accessible.
    public static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroup)
    }

    // MARK: - Payload Loading

    /// Synchronously load the latest cached payload.
    /// Checks the given suite (or App Group suite) first, then falls back to `UserDefaults.standard`.
    public static func loadPayload(suite: UserDefaults? = sharedDefaults) -> PhonePayload? {
        if let suite,
           let data = suite.data(forKey: payloadKey),
           let payload = try? JSONDecoder().decode(PhonePayload.self, from: data) {
            return payload
        }
        if suite == nil || suite == sharedDefaults {
            if let data = UserDefaults.standard.data(forKey: payloadKey),
               let payload = try? JSONDecoder().decode(PhonePayload.self, from: data) {
                return payload
            }
        }
        return nil
    }

    /// Load the timestamp when the payload was last fetched/saved.
    public static func loadLastFetchTime(suite: UserDefaults? = sharedDefaults) -> Date? {
        if let suite, let date = suite.object(forKey: lastFetchTimeKey) as? Date {
            return date
        }
        if suite == nil || suite == sharedDefaults {
            return UserDefaults.standard.object(forKey: lastFetchTimeKey) as? Date
        }
        return nil
    }

    /// Load the source identifier ("iCloud" or "localNetwork") that delivered the cached payload.
    public static func loadLastSource(suite: UserDefaults? = sharedDefaults) -> String? {
        if let suite, let source = suite.string(forKey: lastSourceKey) {
            return source
        }
        if suite == nil || suite == sharedDefaults {
            return UserDefaults.standard.string(forKey: lastSourceKey)
        }
        return nil
    }

    // MARK: - Payload Saving

    /// Persist the payload and sync metadata.
    /// Dual-writes to the App Group container (accessible by widgets) and `UserDefaults.standard` (local fallback).
    public static func save(
        payload: PhonePayload,
        source: String? = nil,
        suite: UserDefaults? = sharedDefaults,
        date: Date = Date()
    ) {
        guard let data = try? JSONEncoder().encode(payload) else { return }

        // Primary: App Group container (or custom suite)
        if let suite {
            suite.set(data, forKey: payloadKey)
            suite.set(date, forKey: lastFetchTimeKey)
            if let source {
                suite.set(source, forKey: lastSourceKey)
            }
        }

        // Secondary: Standard container (fallback if App Group is unavailable)
        if suite == sharedDefaults {
            UserDefaults.standard.set(data, forKey: payloadKey)
            UserDefaults.standard.set(date, forKey: lastFetchTimeKey)
            if let source {
                UserDefaults.standard.set(source, forKey: lastSourceKey)
            }
        }
    }

    // MARK: - Hidden Providers

    /// Load the set of hidden provider IDs.
    public static func loadHiddenProviders(suite: UserDefaults? = sharedDefaults) -> Set<String> {
        if let suite, let array = suite.stringArray(forKey: hiddenProvidersKey) {
            return Set(array)
        }
        if suite == nil || suite == sharedDefaults {
            let standardArray = UserDefaults.standard.stringArray(forKey: hiddenProvidersKey) ?? []
            return Set(standardArray)
        }
        return []
    }

    /// Save the set of hidden provider IDs.
    public static func saveHiddenProviders(_ providers: Set<String>, suite: UserDefaults? = sharedDefaults) {
        let array = Array(providers)
        suite?.set(array, forKey: hiddenProvidersKey)
        if suite == sharedDefaults {
            UserDefaults.standard.set(array, forKey: hiddenProvidersKey)
        }
    }

    // MARK: - Cache Clearing

    /// Clear all cached payload data. Useful for logout, reset, or testing.
    public static func clear(suite: UserDefaults? = sharedDefaults) {
        suite?.removeObject(forKey: payloadKey)
        suite?.removeObject(forKey: lastFetchTimeKey)
        suite?.removeObject(forKey: lastSourceKey)
        if suite == nil || suite == sharedDefaults {
            UserDefaults.standard.removeObject(forKey: payloadKey)
            UserDefaults.standard.removeObject(forKey: lastFetchTimeKey)
            UserDefaults.standard.removeObject(forKey: lastSourceKey)
        }
    }
}
