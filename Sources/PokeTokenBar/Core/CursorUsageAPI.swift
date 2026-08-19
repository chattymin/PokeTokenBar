import Foundation

/// Cursor dashboard usage API (unofficial personal-account endpoints).
/// Auth comes from the local Cursor login (`cursorAuth/accessToken`) or
/// `CURSOR_SESSION_TOKEN` / browser cookie `WorkosCursorSessionToken`.
enum CursorUsageAPI {
    private static let filteredURL = URL(string: "https://cursor.com/api/dashboard/get-filtered-usage-events")!

    private struct DiskCache: Codable {
        var fetchedAt: Date
        var entries: [LocalUsageReader.Entry]
    }

    nonisolated(unsafe) private static var memoryCache: DiskCache?
    private static let cacheLock = NSLock()

    /// Session token for dashboard API calls.
    /// 1. `CURSOR_SESSION_TOKEN` env (also read from login shell via `UsageEnvironment`)
    /// 2. `cursorAuth/accessToken` in Cursor's `state.vscdb` when logged into Cursor IDE
    static func sessionToken() -> String? {
        if let override = UsageEnvironment.value("CURSOR_SESSION_TOKEN")?
            .trimmingCharacters(in: .whitespacesAndNewlines), !override.isEmpty {
            return override
        }
        return LocalAdditionalUsageReader.cursorAuthAccessToken()
    }

    static func fetchEntries(modifiedSince: Date) async -> [LocalUsageReader.Entry] {
        guard UsageEnvironment.value("CURSOR_USAGE_API") != "0" else { return [] }
        guard let token = sessionToken() else {
            AppLog.write("cursor api: no session token — \(LocalAdditionalUsageReader.cursorAuthDiagnostics())")
            return []
        }
        AppLog.write("cursor api: session token ready (\(token.count) chars)")

        if let fresh = await fetchFromNetwork(modifiedSince: modifiedSince), !fresh.isEmpty {
            storeCache(entries: fresh)
            AppLog.write("cursor api: fetched \(fresh.count) events")
            return fresh.filter { $0.date >= modifiedSince }
        }

        if let stale = cachedEntries() {
            AppLog.write("cursor api: network failed, using stale cache (\(stale.entries.count) events)")
            return stale.entries.filter { $0.date >= modifiedSince }
        }
        AppLog.write("cursor api: fetch failed and no cache")
        return []
    }

    // MARK: - Network

    private static func fetchFromNetwork(modifiedSince: Date) async -> [LocalUsageReader.Entry]? {
        guard let token = sessionToken() else { return nil }
        return await fetchFilteredEvents(token: token, modifiedSince: modifiedSince)
    }

    private static func fetchFilteredEvents(
        token: String,
        modifiedSince: Date
    ) async -> [LocalUsageReader.Entry]? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let startDate = formatter.string(from: modifiedSince)
        let endDate = formatter.string(from: Date())
        var page = 1
        var collected: [LocalUsageReader.Entry] = []
        var authMode = AuthMode.allCases[0]
        var authIndex = 0

        while page <= 200 {
            let body: [String: Any] = [
                "teamId": 0,
                "startDate": startDate,
                "endDate": endDate,
                "page": page,
                "pageSize": 100,
            ]
            guard let payload = try? JSONSerialization.data(withJSONObject: body) else { break }

            var request = URLRequest(url: filteredURL)
            request.httpMethod = "POST"
            request.httpBody = payload
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
            request.setValue("https://cursor.com", forHTTPHeaderField: "Origin")
            request.setValue("https://cursor.com/dashboard/usage", forHTTPHeaderField: "Referer")
            authMode.apply(to: &request, token: token)

            guard let (data, status) = await perform(request) else { break }
            if status == 401 || status == 403 {
                AppLog.write("cursor api: filtered events \(authMode) http \(status)")
                authIndex += 1
                guard authIndex < AuthMode.allCases.count else { break }
                authMode = AuthMode.allCases[authIndex]
                continue
            }
            guard (200 ... 299).contains(status),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { break }

            let events = (object["usageEvents"] as? [[String: Any]])
                ?? (object["events"] as? [[String: Any]])
                ?? []
            for (index, event) in events.enumerated() {
                if let entry = parseUsageEvent(event, rowIndex: index, modifiedSince: modifiedSince) {
                    collected.append(entry)
                }
            }

            let pagination = object["pagination"] as? [String: Any]
            let hasNext = (pagination?["hasNextPage"] as? Bool)
                ?? ((pagination?["numPages"] as? Int).map { page < $0 } ?? false)
            guard hasNext, !events.isEmpty else { break }
            page += 1
        }

        guard !collected.isEmpty else { return nil }
        return LocalUsageReader.dedupKeepMax(collected)
    }

    static func parseUsageEvent(
        _ event: [String: Any],
        rowIndex: Int,
        modifiedSince: Date
    ) -> LocalUsageReader.Entry? {
        guard let date = usageEventDate(event), date >= modifiedSince else { return nil }
        let model = stringValue(event["model"]) ?? "unknown"
        let usage = event["tokenUsage"] as? [String: Any] ?? [:]
        let input = intValue(usage["inputTokens"])
        let output = intValue(usage["outputTokens"])
        let cacheWrite = intValue(usage["cacheWriteTokens"])
        let cacheRead = intValue(usage["cacheReadTokens"])
        let costCents = doubleValue(usage["totalCents"]).map { $0 / 100 }
        let stamp = stringValue(event["timestamp"]) ?? ISO8601DateFormatter().string(from: date)
        return LocalAdditionalUsageReader.makeUsageEntry(
            id: "cursor|api|\(stamp)|\(model)|\(rowIndex)",
            date: date,
            model: model,
            input: input,
            output: output,
            cacheWrite: cacheWrite,
            cacheRead: cacheRead,
            cost: costCents)
    }

    private static func usageEventDate(_ event: [String: Any]) -> Date? {
        if let raw = stringValue(event["timestamp"]), let ms = Double(raw), ms > 1_000_000_000_000 {
            return Date(timeIntervalSince1970: ms / 1000)
        }
        if let raw = stringValue(event["timestamp"]) {
            return flexibleDateValue(raw)
        }
        if let ms = doubleValue(event["timestamp"]), ms > 1_000_000_000_000 {
            return Date(timeIntervalSince1970: ms / 1000)
        }
        return nil
    }

    // MARK: - Cache

    private static func cacheFileURL() -> URL {
        CompanionStore.defaultURL().deletingLastPathComponent()
            .appendingPathComponent("cursor-usage-api-cache.json")
    }

    private static func cachedEntries() -> DiskCache? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let memoryCache { return memoryCache }
        guard let data = try? Data(contentsOf: cacheFileURL()),
              let decoded = try? JSONDecoder().decode(DiskCache.self, from: data) else { return nil }
        memoryCache = decoded
        return decoded
    }

    private static func storeCache(entries: [LocalUsageReader.Entry]) {
        let cache = DiskCache(fetchedAt: Date(), entries: LocalUsageReader.dedupKeepMax(entries))
        cacheLock.lock()
        memoryCache = cache
        cacheLock.unlock()
        if let data = try? JSONEncoder().encode(cache) {
            try? data.write(to: cacheFileURL(), options: .atomic)
        }
    }

    // MARK: - HTTP helpers

    /// Dashboard cookie is `sub::jwt`, not the bare accessToken JWT.
    static func workosSessionCookie(from accessToken: String) -> String {
        if accessToken.contains("::") || accessToken.contains("%3A%3A") {
            return accessToken
        }
        if let sub = jwtSubject(accessToken) {
            return "\(sub)::\(accessToken)"
        }
        return accessToken
    }

    static func jwtSubject(_ jwt: String) -> String? {
        let parts = jwt.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1])
        let pad = (4 - payload.count % 4) % 4
        if pad > 0 { payload += String(repeating: "=", count: pad) }
        payload = payload
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sub = json["sub"] as? String, !sub.isEmpty else { return nil }
        return sub
    }

    private enum AuthMode: CaseIterable, CustomStringConvertible {
        case cookie
        case bearer

        var description: String {
            switch self {
            case .cookie: return "cookie"
            case .bearer: return "bearer"
            }
        }

        func apply(to request: inout URLRequest, token: String) {
            switch self {
            case .cookie:
                let value = workosSessionCookie(from: token)
                request.setValue("WorkosCursorSessionToken=\(value)", forHTTPHeaderField: "Cookie")
            case .bearer:
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
        }
    }

    private static func perform(_ request: URLRequest) async -> (Data, Int)? {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            return (data, status)
        } catch {
            AppLog.write("cursor api: \(request.url?.absoluteString ?? "?") error \(error.localizedDescription)")
            return nil
        }
    }

    private static func stringValue(_ value: Any?) -> String? {
        switch value {
        case let string as String where !string.isEmpty: return string
        case let number as NSNumber: return number.stringValue
        default: return nil
        }
    }

    private static func intValue(_ value: Any?) -> Int {
        switch value {
        case let number as NSNumber: return max(0, number.intValue)
        case let string as String: return Int(string.replacingOccurrences(of: ",", with: "")) ?? 0
        default: return 0
        }
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber: return number.doubleValue
        case let string as String: return Double(string)
        default: return nil
        }
    }

    private static func flexibleDateValue(_ raw: String) -> Date? {
        if let ms = Double(raw), ms > 1_000_000_000_000 {
            return Date(timeIntervalSince1970: ms / 1000)
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: raw) { return date }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: raw)
    }
}
