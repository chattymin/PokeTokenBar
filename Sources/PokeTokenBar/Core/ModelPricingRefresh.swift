import Foundation

/// Refreshes the public model catalog without sending usage or model names.
/// Call `cachedCatalog()` first, then publish any non-nil `refreshIfNeeded()` result.
actor ModelPricingRefresh {
    static let shared = ModelPricingRefresh()
    static let maximumBytes = 16 * 1024 * 1024
    private static let refreshInterval: TimeInterval = 24 * 60 * 60
    private static let failureBackoff: TimeInterval = 60 * 60
    private static let defaultURL = URL(string: "https://models.dev/api.json")!
    private static let defaultFileURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("PokeTokenBar/model-pricing-catalog.json")

    typealias Fetch = @Sendable (URL) async throws -> Data
    private struct Cache: Codable {
        var data: Data?
        var lastSuccess: Date?
        var lastFailure: Date?
    }

    private let url: URL
    private let fileURL: URL
    private let persists: Bool
    private let enabled: Bool
    private let now: @Sendable () -> Date
    private let fetch: Fetch
    private var loaded = false
    private var cache = Cache()
    private var catalog: ModelPricingCatalog?
    private var inFlight: Task<ModelPricingCatalog?, Never>?

    init(url: URL = ModelPricingRefresh.defaultURL, fileURL: URL? = nil,
         now: @escaping @Sendable () -> Date = Date.init, fetch: Fetch? = nil) {
        self.url = url
        self.fileURL = fileURL ?? Self.defaultFileURL
        self.persists = AppEnv.persistsToUserLocation(injectedFileURL: fileURL)
        self.enabled = fetch != nil || fileURL != nil || AppEnv.isBundledApp || AppEnv.isParityRun
        self.now = now
        self.fetch = fetch ?? Self.download
    }

    func cachedCatalog() -> ModelPricingCatalog? {
        loadIfNeeded()
        return catalog
    }

    /// Only changed prices require a new usage pass. An identical response still renews the cache.
    func refreshIfNeeded() async -> ModelPricingCatalog? {
        loadIfNeeded()
        if let inFlight { return await inFlight.value }
        guard enabled else { return nil }
        let date = now()
        if catalog != nil, let success = cache.lastSuccess,
           date.timeIntervalSince(success) >= 0, date.timeIntervalSince(success) < Self.refreshInterval { return nil }
        if let failure = cache.lastFailure,
           date.timeIntervalSince(failure) >= 0, date.timeIntervalSince(failure) < Self.failureBackoff { return nil }
        let task = Task { await self.performRefresh() }
        inFlight = task
        let result = await task.value
        inFlight = nil
        return result
    }

    private func performRefresh() async -> ModelPricingCatalog? {
        do {
            let data = try await fetch(url)
            guard data.count <= Self.maximumBytes else { throw RefreshError.tooLarge }
            let compact = try ModelPricingCatalog.compactData(from: data)
            let updated = try ModelPricingCatalog.decode(compact)
            let changed = updated != catalog
            catalog = updated
            cache = Cache(data: compact, lastSuccess: now(), lastFailure: nil)
            save()
            return changed ? updated : nil
        } catch {
            cache.lastFailure = now()
            save()
            return nil
        }
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard persists, let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let size = attributes[.size] as? NSNumber, size.intValue <= Self.maximumBytes * 2,
              let data = try? Data(contentsOf: fileURL),
              let stored = try? JSONDecoder().decode(Cache.self, from: data) else { return }
        if let raw = stored.data {
            guard raw.count <= Self.maximumBytes, let decoded = try? ModelPricingCatalog.decode(raw) else { return }
            catalog = decoded
        }
        cache = stored
    }

    private func save() {
        guard persists, let data = try? JSONEncoder().encode(cache) else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
        } catch { /* A failed cache write must not discard the in-memory catalog. */ }
    }

    private enum RefreshError: Error { case invalidResponse, tooLarge }

    private final class NoRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }

    private static func download(_ url: URL) async throws -> Data {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        let session = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.httpMethod = "GET"
        request.setValue("PokeTokenBar", forHTTPHeaderField: "User-Agent")
        request.httpShouldHandleCookies = false
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              response.expectedContentLength <= Int64(maximumBytes) else { throw RefreshError.invalidResponse }
        var data = Data()
        for try await byte in bytes {
            guard data.count < maximumBytes else { throw RefreshError.tooLarge }
            data.append(byte)
        }
        return data
    }
}
