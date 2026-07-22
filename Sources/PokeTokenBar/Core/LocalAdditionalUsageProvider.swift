import Foundation
import SQLite3

private enum LocalAdditionalSource: String, Sendable {
    case opencode
    case hermes
}

/// OpenCode usage from its local SQLite database and legacy message files.
struct LocalOpenCodeProvider: UsageProvider {
    let id = "opencode"
    let displayName = "OpenCode"

    func fetchDaily() async throws -> DailyUsage? {
        let entries = await LocalAdditionalUsageCache.shared.entries(for: .opencode)
        return LocalUsageReader.daily(entries: entries, localDay: LocalUsageReader.todayKey())
    }

    func fetchEnrichment() async -> ProviderEnrichment {
        let entries = await LocalAdditionalUsageCache.shared.entries(for: .opencode)
        return enrichment(entries: entries)
    }
}

/// Hermes Agent usage from its local state database.
struct LocalHermesProvider: UsageProvider {
    let id = "hermes"
    let displayName = "Hermes Agent"

    func fetchDaily() async throws -> DailyUsage? {
        let entries = await LocalAdditionalUsageCache.shared.entries(for: .hermes)
        return LocalUsageReader.daily(entries: entries, localDay: LocalUsageReader.todayKey())
    }

    func fetchEnrichment() async -> ProviderEnrichment {
        let entries = await LocalAdditionalUsageCache.shared.entries(for: .hermes)
        return enrichment(entries: entries)
    }
}

private func enrichment(entries: [LocalUsageReader.Entry]) -> ProviderEnrichment {
    let now = Date()
    let monthStart = LocalUsageReader.startOfMonth(now)
    let weekStart = LocalUsageReader.startOfWeek(now)
    let formatter = LocalUsageReader.localDayFormatter()
    var result = ProviderEnrichment()
    result.activeBlock = LocalUsageReader.activeBlock(entries: entries, now: now)
    result.blocksOK = true
    result.weekTotal = LocalUsageReader.period(
        entries: entries, periodKey: formatter.string(from: weekStart),
        fromDay: formatter.string(from: weekStart), toDay: formatter.string(from: now))
    result.monthTotal = LocalUsageReader.period(
        entries: entries, periodKey: LocalUsageReader.monthKey(now),
        fromDay: formatter.string(from: monthStart), toDay: formatter.string(from: now))
    result.periodsOK = true
    return result
}

/// Shares a single native read between a provider's daily and enrichment calls.
private actor LocalAdditionalUsageCache {
    static let shared = LocalAdditionalUsageCache()

    private struct Cached: Sendable {
        let loadedAt: Date
        let monthKey: String
        let entries: [LocalUsageReader.Entry]
    }

    private var cached: [LocalAdditionalSource: Cached] = [:]
    private var inFlight: [LocalAdditionalSource: Task<[LocalUsageReader.Entry], Never>] = [:]

    func entries(for source: LocalAdditionalSource) async -> [LocalUsageReader.Entry] {
        let now = Date()
        let monthKey = LocalUsageReader.monthKey(now)
        let previous = cached[source].flatMap { $0.monthKey == monthKey ? $0 : nil }
        if let value = previous,
           now.timeIntervalSince(value.loadedAt) < 30 {
            return value.entries
        }
        if let task = inFlight[source] { return await task.value }

        let periodStart = min(LocalUsageReader.startOfMonth(now), now.addingTimeInterval(-7 * 86400))
        // OpenCode messages are immutable. After the cold monthly read, only query
        // records at and after the newest cached timestamp (with a small overlap).
        // This keeps minute-by-minute refreshes cheap even for large databases.
        let since: Date
        if source == .opencode, let newest = previous?.entries.map(\.date).max() {
            since = max(periodStart, newest.addingTimeInterval(-1))
        } else {
            since = periodStart
        }
        let existing = previous?.entries ?? []
        let task = Task.detached(priority: .utility) {
            let loaded: [LocalUsageReader.Entry] = switch source {
            case .opencode: LocalAdditionalUsageReader.openCodeEntries(modifiedSince: since)
            case .hermes: LocalAdditionalUsageReader.hermesEntries(modifiedSince: since)
            }
            return source == .opencode
                ? LocalUsageReader.dedupKeepMax(existing + loaded)
                : loaded
        }
        inFlight[source] = task
        let entries = await task.value
        inFlight[source] = nil
        cached[source] = Cached(loadedAt: now, monthKey: monthKey, entries: entries)
        return entries
    }
}

/// Native parsers derived from the corresponding ccusage adapters.
/// ccusage is a format reference only; it is never installed or launched.
enum LocalAdditionalUsageReader {
    typealias Object = [String: Any]

    static var defaultOpenCodeRoots: [URL] {
        environmentPaths("OPENCODE_DATA_DIR")
            ?? [FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/share/opencode")]
    }

    static func openCodeEntries(
        modifiedSince: Date,
        roots: [URL]? = nil
    ) -> [LocalUsageReader.Entry] {
        let sourceRoots = roots ?? defaultOpenCodeRoots
        var entries: [LocalUsageReader.Entry] = []
        for root in sourceRoots {
            if let database = preferredOpenCodeDatabase(in: root) {
                entries += openCodeDatabaseEntries(database, modifiedSince: modifiedSince)
            }
            let legacyRoot = root.appendingPathComponent("storage/message")
            for file in files(in: legacyRoot, modifiedSince: modifiedSince) where file.pathExtension == "json" {
                guard let object = jsonObject(at: file),
                      let entry = parseOpenCodeMessage(
                        object, fallbackID: file.deletingPathExtension().lastPathComponent) else { continue }
                entries.append(entry)
            }
        }
        return LocalUsageReader.dedupKeepMax(entries.filter { $0.date >= modifiedSince })
    }

    static func hermesEntries(
        modifiedSince: Date,
        roots: [URL]? = nil
    ) -> [LocalUsageReader.Entry] {
        let sourceRoots = roots ?? environmentPaths("HERMES_HOME")
            ?? [FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".hermes")]
        var seen = Set<String>()
        var entries: [LocalUsageReader.Entry] = []
        for root in sourceRoots {
            let database = root.pathExtension == "db" ? root : root.appendingPathComponent("state.db")
            for entry in hermesDatabaseEntries(database, modifiedSince: modifiedSince)
            where entry.date >= modifiedSince {
                if seen.insert(entry.id).inserted { entries.append(entry) }
            }
        }
        return entries
    }

    static func parseOpenCodeMessage(
        _ object: Object,
        fallbackID: String
    ) -> LocalUsageReader.Entry? {
        guard let tokens = object["tokens"] as? Object,
              let date = dateValue((object["time"] as? Object)?["created"]),
              let model = stringValue(object["modelID"]),
              stringValue(object["providerID"]) != nil else { return nil }
        let cache = tokens["cache"] as? Object
        return makeEntry(
            id: "opencode|\(stringValue(object["id"]) ?? fallbackID)",
            date: date,
            model: model,
            input: intValue(tokens["input"]),
            output: intValue(tokens["output"]),
            cacheWrite: intValue(cache?["write"]),
            cacheRead: intValue(cache?["read"]),
            total: intValue(tokens["total"]),
            cost: doubleValue(object["cost"]))
    }

    // MARK: OpenCode database

    private static func preferredOpenCodeDatabase(in root: URL) -> URL? {
        if root.pathExtension == "db" { return root }
        let standard = root.appendingPathComponent("opencode.db")
        if FileManager.default.fileExists(atPath: standard.path) { return standard }
        return (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil))?
            .filter { url in
                let name = url.lastPathComponent
                guard name.hasPrefix("opencode-"), name.hasSuffix(".db") else { return false }
                let channel = name.dropFirst("opencode-".count).dropLast(".db".count)
                return !channel.isEmpty && channel.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }
            }
            .sorted { $0.path < $1.path }
            .first
    }

    private static func openCodeDatabaseEntries(
        _ database: URL,
        modifiedSince: Date
    ) -> [LocalUsageReader.Entry] {
        let cutoff = Int64(modifiedSince.timeIntervalSince1970 * 1000)
        let recentSQL = "SELECT id, session_id, data FROM message WHERE time_created >= ?1"
        var rows = query(database, sql: recentSQL, bindMillis: cutoff) { statement in
            parseOpenCodeDatabaseRow(statement)
        }
        // Older OpenCode databases did not expose time_created as a column.
        if rows == nil {
            rows = query(database, sql: "SELECT id, session_id, data FROM message") { statement in
                parseOpenCodeDatabaseRow(statement)
            }
        }
        return rows ?? []
    }

    private static func parseOpenCodeDatabaseRow(_ statement: OpaquePointer) -> LocalUsageReader.Entry? {
        guard let id = columnText(statement, 0),
              let payload = columnText(statement, 2),
              let object = jsonObject(data: Data(payload.utf8)) else { return nil }
        return parseOpenCodeMessage(object, fallbackID: id)
    }

    // MARK: Hermes database

    private static func hermesDatabaseEntries(
        _ database: URL,
        modifiedSince: Date
    ) -> [LocalUsageReader.Entry] {
        let sql = """
        SELECT id, model, billing_provider, started_at, message_count,
               input_tokens, output_tokens, cache_read_tokens, cache_write_tokens,
               reasoning_tokens, estimated_cost_usd, actual_cost_usd
        FROM sessions
        WHERE model IS NOT NULL AND TRIM(model) != '' AND started_at >= ?1
        """
        return query(database, sql: sql, bindMillis: Int64(modifiedSince.timeIntervalSince1970)) { statement in
            guard let id = columnText(statement, 0)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !id.isEmpty,
                  let model = columnText(statement, 1)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !model.isEmpty,
                  let date = dateValue(sqlite3_column_double(statement, 3)) else { return nil }
            let estimatedCost = sqlite3_column_double(statement, 10)
            let actualCost = sqlite3_column_double(statement, 11)
            return makeEntry(
                id: "hermes|\(id)",
                date: date,
                model: model,
                input: columnInt(statement, 5),
                output: columnInt(statement, 6) + columnInt(statement, 9),
                cacheWrite: columnInt(statement, 8),
                cacheRead: columnInt(statement, 7),
                cost: actualCost > 0 ? actualCost : estimatedCost)
        } ?? []
    }

    // MARK: Shared utilities

    private static func makeEntry(
        id: String,
        date: Date,
        model: String,
        input: Int = 0,
        output: Int = 0,
        cacheWrite: Int = 0,
        cacheRead: Int = 0,
        total: Int = 0,
        cost: Double? = nil
    ) -> LocalUsageReader.Entry? {
        let safeInput = max(0, input)
        let safeCacheWrite = max(0, cacheWrite)
        let safeCacheRead = max(0, cacheRead)
        var safeOutput = max(0, output)
        let parts = safeInput + safeOutput + safeCacheWrite + safeCacheRead
        if total > parts { safeOutput += total - parts }
        guard safeInput + safeOutput + safeCacheWrite + safeCacheRead > 0 else { return nil }
        return LocalUsageReader.Entry(
            id: id,
            date: date,
            localDay: LocalUsageReader.localDayFormatter().string(from: date),
            model: model,
            input: safeInput,
            output: safeOutput,
            cacheWrite: safeCacheWrite,
            cacheRead: safeCacheRead,
            explicitCost: cost)
    }

    private static func environmentPaths(_ key: String) -> [URL]? {
        guard let raw = ProcessInfo.processInfo.environment[key] else { return nil }
        return raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map(URL.init(fileURLWithPath:))
    }

    private static func files(in root: URL, modifiedSince: Date) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        return enumerator.compactMap { item in
            guard let url = item as? URL,
                  let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey]),
                  values.isRegularFile == true,
                  (values.contentModificationDate ?? .distantPast) >= modifiedSince else { return nil }
            return url
        }
    }

    private static func jsonObject(at url: URL) -> Object? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return jsonObject(data: data)
    }

    private static func jsonObject(data: Data) -> Object? {
        try? JSONSerialization.jsonObject(with: data) as? Object
    }

    private static func stringValue(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func intValue(_ value: Any?) -> Int {
        if let number = value as? NSNumber { return max(0, number.intValue) }
        if let string = value as? String, let number = Int(string.trimmingCharacters(in: .whitespaces)) {
            return max(0, number)
        }
        return 0
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    private static func dateValue(_ value: Any?) -> Date? {
        guard let raw = doubleValue(value), raw.isFinite, raw > 0 else { return nil }
        let seconds = raw >= 100_000_000_000 ? raw / 1_000 : raw
        return Date(timeIntervalSince1970: seconds)
    }

    private static func query<T>(
        _ databaseURL: URL,
        sql: String,
        bindMillis: Int64? = nil,
        row: (OpaquePointer) -> T?
    ) -> [T]? {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return [] }
        var database: OpaquePointer?
        guard sqlite3_open_v2(
            databaseURL.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK,
              let database else { return nil }
        defer { sqlite3_close(database) }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { return nil }
        defer { sqlite3_finalize(statement) }
        if let bindMillis { sqlite3_bind_int64(statement, 1, bindMillis) }

        var result: [T] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            autoreleasepool {
                if let value = row(statement) { result.append(value) }
            }
        }
        return result
    }

    private static func columnText(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard let bytes = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: bytes)
    }

    private static func columnInt(_ statement: OpaquePointer, _ index: Int32) -> Int {
        max(0, Int(sqlite3_column_int64(statement, index)))
    }
}
