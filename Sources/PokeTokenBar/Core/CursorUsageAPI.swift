import CryptoKit
import Foundation

/// Cursor dashboard usage API (unofficial personal-account endpoints).
/// Auth comes from the local Cursor login (`cursorAuth/accessToken`) or
/// `CURSOR_SESSION_TOKEN` / browser cookie `WorkosCursorSessionToken`.
enum CursorUsageAPI {
    private static let filteredURL = URL(string: "https://cursor.com/api/dashboard/get-filtered-usage-events")!
    private static let pageSize = 100
    private static let maxPages = 200
    private static let requestTimeout: TimeInterval = 10
    private static let fetchDeadline: TimeInterval = 120
    private static let cacheMaxAge: TimeInterval = 6 * 60 * 60

    private struct DiskCache: Codable {
        var fetchedAt: Date
        var accountIdentifier: String?
        /// Earliest `modifiedSince` this cache was fetched for.
        var coveredSince: Date?
        var entries: [LocalUsageReader.Entry]

        func covers(modifiedSince: Date) -> Bool {
            guard let coveredSince else { return true }
            return coveredSince <= modifiedSince
        }
    }

    struct UsageResult: Sendable {
        let entries: [LocalUsageReader.Entry]
        let isAuthoritative: Bool
    }

    private enum NetworkResult {
        case success([LocalUsageReader.Entry])
        case failure(String)
    }

    typealias Transport = @Sendable (URLRequest) async -> (Data, Int)?

    nonisolated(unsafe) private static var memoryCache: DiskCache?
    private static let cacheLock = NSLock()

    /// Test hook — inject canned HTTP responses for pagination/auth tests.
    nonisolated(unsafe) static var transportForTesting: Transport?

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.timeoutIntervalForRequest = requestTimeout
        config.timeoutIntervalForResource = fetchDeadline
        return URLSession(configuration: config)
    }()

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

    static func fetchEntries(modifiedSince: Date) async -> UsageResult {
        guard UsageEnvironment.value("CURSOR_USAGE_API") != "0" else {
            return UsageResult(entries: [], isAuthoritative: false)
        }
        guard let token = sessionToken() else {
            AppLog.write("cursor api: no session token — \(LocalAdditionalUsageReader.cursorAuthDiagnostics())")
            return UsageResult(entries: [], isAuthoritative: false)
        }
        AppLog.write("cursor api: session token ready (\(token.count) chars)")
        let accountIdentifier = cacheAccountIdentifier(from: token)

        switch await fetchFilteredEvents(token: token, modifiedSince: modifiedSince) {
        case .success(let fresh):
            storeCache(
                entries: fresh,
                accountIdentifier: accountIdentifier,
                coveredSince: modifiedSince)
            AppLog.write("cursor api: fetched \(fresh.count) events")
            return UsageResult(
                entries: fresh.filter { $0.date >= modifiedSince },
                isAuthoritative: true)
        case .failure(let reason):
            AppLog.write("cursor api: fetch failed — \(reason)")
            if let stale = cachedEntries(accountIdentifier: accountIdentifier, modifiedSince: modifiedSince) {
                let age = Date().timeIntervalSince(stale.fetchedAt)
                if age > cacheMaxAge {
                    AppLog.write("cursor api: disk cache expired (\(Int(age))s old), skipping")
                    return UsageResult(entries: [], isAuthoritative: false)
                }
                let authoritative = stale.covers(modifiedSince: modifiedSince)
                AppLog.write(
                    "cursor api: using disk cache (\(stale.entries.count) events, "
                    + "authoritative=\(authoritative), age=\(Int(age))s)")
                return UsageResult(
                    entries: stale.entries.filter { $0.date >= modifiedSince },
                    isAuthoritative: authoritative)
            }
            AppLog.write("cursor api: fetch failed and no cache")
            return UsageResult(entries: [], isAuthoritative: false)
        }
    }

    // MARK: - Network

    static func fetchFilteredEventsForTesting(
        token: String,
        modifiedSince: Date,
        transport: @escaping Transport
    ) async -> (entries: [LocalUsageReader.Entry]?, failureReason: String?) {
        switch await fetchFilteredEvents(
            token: token,
            modifiedSince: modifiedSince,
            transport: transport) {
        case .success(let entries):
            return (entries, nil)
        case .failure(let reason):
            return (nil, reason)
        }
    }

    static func epochMillisecondString(_ date: Date) -> String {
        String(Int64((date.timeIntervalSince1970 * 1000).rounded()))
    }

    private static func fetchFilteredEvents(
        token: String,
        modifiedSince: Date,
        transport: Transport? = nil
    ) async -> NetworkResult {
        let send = transport ?? activeTransport()
        // The dashboard endpoint expects epoch milliseconds as strings; ISO8601 makes it return 500.
        let startDate = epochMillisecondString(modifiedSince)
        let endDate = epochMillisecondString(Date())
        let deadline = Date().addingTimeInterval(fetchDeadline)
        var page = 1
        var globalIndex = 0
        var collected: [LocalUsageReader.Entry] = []
        var authMode = AuthMode.allCases[0]
        var authIndex = 0

        while page <= maxPages {
            guard Date() < deadline else {
                return .failure("pagination deadline exceeded after page \(page - 1)")
            }

            let body: [String: Any] = [
                "teamId": 0,
                "startDate": startDate,
                "endDate": endDate,
                "page": page,
                "pageSize": pageSize,
            ]
            guard let payload = try? JSONSerialization.data(withJSONObject: body) else {
                return .failure("failed to encode request body for page \(page)")
            }

            var request = URLRequest(url: filteredURL)
            request.httpMethod = "POST"
            request.httpBody = payload
            request.timeoutInterval = requestTimeout
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
            request.setValue("https://cursor.com", forHTTPHeaderField: "Origin")
            request.setValue("https://cursor.com/dashboard/usage", forHTTPHeaderField: "Referer")
            authMode.apply(to: &request, token: token)

            guard let (data, status) = await send(request) else {
                return .failure("transport error on page \(page)")
            }
            if status == 401 || status == 403 {
                AppLog.write("cursor api: filtered events \(authMode) http \(status)")
                authIndex += 1
                guard authIndex < AuthMode.allCases.count else {
                    return .failure("auth rejected for all modes (last http \(status))")
                }
                authMode = AuthMode.allCases[authIndex]
                continue
            }
            guard (200 ... 299).contains(status) else {
                let preview = String(data: data.prefix(160), encoding: .utf8)?
                    .replacingOccurrences(of: "\n", with: " ") ?? ""
                return .failure("http \(status) on page \(page) (\(data.count) bytes) \(preview)")
            }
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .failure("invalid JSON on page \(page) (\(data.count) bytes)")
            }

            guard let events = (object["usageEventsDisplay"] as? [[String: Any]])
                ?? (object["usageEvents"] as? [[String: Any]])
                ?? (object["events"] as? [[String: Any]]) else {
                let keys = object.keys.sorted().joined(separator: ",")
                return .failure("missing usageEvents/events on page \(page) (keys: \(keys))")
            }
            for event in events {
                if let entry = parseUsageEvent(
                    event, rowIndex: globalIndex, modifiedSince: modifiedSince) {
                    collected.append(entry)
                }
                globalIndex += 1
            }

            let hasNext = hasNextPage(pagination: object["pagination"] as? [String: Any],
                                      totalCount: intValue(object["totalUsageEventsCount"]),
                                      page: page,
                                      eventCount: events.count)
            guard hasNext else {
                return .success(LocalUsageReader.dedupKeepMax(collected))
            }
            guard !events.isEmpty else {
                return .failure("pagination indicated next page but page \(page) was empty")
            }
            page += 1
        }

        return .failure("pagination exceeded \(maxPages) pages")
    }

    static func hasNextPage(
        pagination: [String: Any]?,
        totalCount: Int? = nil,
        page: Int,
        eventCount: Int
    ) -> Bool {
        if let explicit = pagination?["hasNextPage"] as? Bool {
            return explicit
        }
        if let numPages = pagination?["numPages"] as? Int {
            return page < numPages
        }
        if let totalCount {
            return page * pageSize < totalCount
        }
        // Missing pagination metadata — keep going while pages are full.
        return eventCount >= pageSize
    }

    static func parseUsageEvent(
        _ event: [String: Any],
        rowIndex: Int,
        modifiedSince: Date
    ) -> LocalUsageReader.Entry? {
        guard let date = usageEventDate(event), date >= modifiedSince else { return nil }
        let model = stringValue(event["model"]) ?? "unknown"
        let stableID = stringValue(event["id"])
            ?? stringValue(event["eventId"])
            ?? stringValue(event["requestId"])
        let usage = event["tokenUsage"] as? [String: Any] ?? [:]
        let input = intValue(usage["inputTokens"])
        let output = intValue(usage["outputTokens"])
        let cacheWrite = intValue(usage["cacheWriteTokens"])
        let cacheRead = intValue(usage["cacheReadTokens"])
        let costCents = doubleValue(usage["totalCents"]).map { $0 / 100 }
        let stamp = stringValue(event["timestamp"]) ?? ISO8601DateFormatter().string(from: date)
        let entryID = stableID.map { "cursor|api|\($0)" }
            ?? "cursor|api|\(stamp)|\(model)|\(rowIndex)"
        return LocalAdditionalUsageReader.makeUsageEntry(
            id: entryID,
            date: date,
            model: model,
            input: input,
            output: output,
            cacheWrite: cacheWrite,
            cacheRead: cacheRead,
            cost: costCents)
    }

    static func usageEventDate(_ event: [String: Any]) -> Date? {
        if let raw = stringValue(event["timestamp"]), let epoch = Double(raw),
           let date = epochDate(epoch) {
            return date
        }
        if let raw = stringValue(event["timestamp"]) {
            return flexibleDateValue(raw)
        }
        if let epoch = doubleValue(event["timestamp"]), let date = epochDate(epoch) {
            return date
        }
        return nil
    }

    static func epochDate(_ value: Double) -> Date? {
        if value > 1_000_000_000_000 {
            return Date(timeIntervalSince1970: value / 1000)
        }
        if value >= 1_000_000_000 {
            return Date(timeIntervalSince1970: value)
        }
        return nil
    }

    // MARK: - Cache

    private static func cacheFileURL() -> URL {
        AppStatePaths.directory().appendingPathComponent("cursor-usage-api-cache.json")
    }

    private static func cachedEntries(
        accountIdentifier: String,
        modifiedSince: Date
    ) -> DiskCache? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        let candidate: DiskCache?
        if let memoryCache {
            let accountMatches = memoryCache.accountIdentifier == nil
                || memoryCache.accountIdentifier == accountIdentifier
            candidate = accountMatches ? memoryCache : nil
        } else if let data = try? Data(contentsOf: cacheFileURL()),
                  let decoded = try? JSONDecoder().decode(DiskCache.self, from: data) {
            let accountMatches = decoded.accountIdentifier == nil
                || decoded.accountIdentifier == accountIdentifier
            guard accountMatches else { return nil }
            memoryCache = decoded
            candidate = decoded
        } else {
            candidate = nil
        }
        guard let candidate else { return nil }
        if !candidate.covers(modifiedSince: modifiedSince) {
            AppLog.write("cursor api: disk cache window mismatch "
                + "(cached since \(candidate.coveredSince?.description ?? "unknown"), "
                + "need \(modifiedSince))")
            return nil
        }
        return candidate
    }

    private static func storeCache(
        entries: [LocalUsageReader.Entry],
        accountIdentifier: String,
        coveredSince: Date
    ) {
        let cache = DiskCache(
            fetchedAt: Date(),
            accountIdentifier: accountIdentifier,
            coveredSince: coveredSince,
            entries: LocalUsageReader.dedupKeepMax(entries))
        cacheLock.lock()
        memoryCache = cache
        cacheLock.unlock()
        if let data = try? JSONEncoder().encode(cache) {
            try? data.write(to: cacheFileURL(), options: .atomic)
        }
    }

    // MARK: - HTTP helpers

    static func cacheAccountIdentifier(from token: String) -> String {
        let decoded = token.removingPercentEncoding ?? token
        if let separator = decoded.range(of: "::") {
            let subject = String(decoded[..<separator.lowerBound])
            if !subject.isEmpty { return "subject:\(subject)" }
        }
        if let subject = jwtSubject(decoded) {
            return "subject:\(subject)"
        }
        let digest = SHA256.hash(data: Data(decoded.utf8))
        return "token:" + digest.map { String(format: "%02x", $0) }.joined()
    }

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

    private static func activeTransport() -> Transport {
        if let transportForTesting { return transportForTesting }
        return perform
    }

    private static func perform(_ request: URLRequest) async -> (Data, Int)? {
        do {
            let (data, response) = try await session.data(for: request)
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
        if let epoch = Double(raw), let date = epochDate(epoch) {
            return date
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: raw) { return date }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: raw)
    }
}
