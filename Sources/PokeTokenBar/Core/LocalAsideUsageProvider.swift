import Foundation
import SQLite3

struct LocalAsideProvider: UsageProvider {
    let id = "aside"
    let displayName = "Aside"
    let home: URL
    let customRootsValue: String?

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
         customRootsValue: String? = CustomScanRoots.storedValue(for: "aside")) {
        self.home = home
        self.customRootsValue = customRootsValue
    }

    func fetchDaily() async throws -> DailyUsage? {
        let now = Date()
        let entries = try LocalAsideUsageReader.entries(
            databases: LocalAsideUsageReader.databases(home: home, customRootsValue: customRootsValue),
            since: Calendar.current.startOfDay(for: now))
        return LocalUsageReader.daily(entries: entries, localDay: LocalUsageReader.todayKey(), includeModels: true)
    }

    func fetchEnrichment() async -> ProviderEnrichment {
        let now = Date()
        guard let entries = try? LocalAsideUsageReader.entries(
            databases: LocalAsideUsageReader.databases(home: home, customRootsValue: customRootsValue),
            since: LocalUsageReader.enrichmentScanStart(now: now)) else { return ProviderEnrichment() }
        let fmt = LocalUsageReader.localDayFormatter()
        let week = fmt.string(from: LocalUsageReader.startOfWeek(now))
        let month = fmt.string(from: LocalUsageReader.startOfMonth(now))
        var result = ProviderEnrichment()
        result.activeBlock = LocalUsageReader.activeBlock(entries: entries, now: now)
        result.blocksOK = true
        result.weekTotal = LocalUsageReader.period(entries: entries, periodKey: week, fromDay: week, toDay: fmt.string(from: now))
        result.monthTotal = LocalUsageReader.period(entries: entries, periodKey: LocalUsageReader.monthKey(now), fromDay: month, toDay: fmt.string(from: now))
        result.periodsOK = true
        return result
    }
}

/// Aside persists mutable turn aggregates, not append-only usage events.
/// Only usage metadata is selected; conversation bodies and credentials are never read.
enum LocalAsideUsageReader {
    enum ReadError: Error { case databaseUnavailable, queryFailed }

    static func roots(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                      customRootsValue: String? = nil) -> [URL] {
        CustomScanRoots.union(defaults: [home.appendingPathComponent(".aside/u")], extraRaw: customRootsValue)
    }

    /// Root folders may be `.aside/u` or individual user folders containing state.db.
    static func databases(home: URL, customRootsValue: String?) -> [URL] {
        let fm = FileManager.default
        var found = Set<URL>()
        for root in roots(home: home, customRootsValue: customRootsValue) {
            let children = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
            for directory in [root] + children {
                let db = directory.appendingPathComponent("state.db").resolvingSymlinksInPath().standardizedFileURL
                if fm.fileExists(atPath: db.path) { found.insert(db) }
            }
        }
        return found.sorted { $0.path < $1.path }
    }

    static func entries(databases: [URL], since: Date) throws -> [LocalUsageReader.Entry] {
        var result: [LocalUsageReader.Entry] = []
        let fmt = LocalUsageReader.localDayFormatter()
        for url in databases {
            var db: OpaquePointer?
            guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
                sqlite3_close(db)
                throw ReadError.databaseUnavailable
            }
            defer { sqlite3_close(db) }
            sqlite3_busy_timeout(db, 1000)
            var statement: OpaquePointer?
            let query = """
                SELECT t.id, t.token_usage, t.started_at, s.model
                FROM session_turns t LEFT JOIN sessions s ON s.id = t.session_id
                WHERE t.started_at >= ?
                """
            guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
                throw ReadError.queryFailed
            }
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_double(statement, 1, since.timeIntervalSince1970)
            var status = sqlite3_step(statement)
            while status == SQLITE_ROW {
                if let text = sqlite3_column_text(statement, 1),
                   let usage = try? JSONSerialization.jsonObject(with: Data(String(cString: text).utf8)) as? [String: Any] {
                    let date = Date(timeIntervalSince1970: sqlite3_column_double(statement, 2))
                    var model = "aside"
                    if let text = sqlite3_column_text(statement, 3),
                       let metadata = try? JSONSerialization.jsonObject(with: Data(String(cString: text).utf8)) as? [String: Any],
                       let modelID = metadata["modelId"] as? String { model = modelID }
                    let cost = (usage["cost"] as? [String: Any])?["total"] as? Double
                    let hasBuckets = ["input", "output", "cacheRead", "cacheWrite"].contains { usage[$0] is NSNumber }
                    result.append(.init(
                        id: "\(url.path):\(sqlite3_column_int64(statement, 0))",
                        date: date, localDay: fmt.string(from: date), model: model,
                        input: tokens(hasBuckets ? usage["input"] : usage["totalTokens"]), output: tokens(usage["output"]),
                        cacheWrite: tokens(usage["cacheWrite"]), cacheRead: tokens(usage["cacheRead"]),
                        explicitCost: cost))
                }
                status = sqlite3_step(statement)
            }
            guard status == SQLITE_DONE else { throw ReadError.queryFailed }
        }
        return result
    }

    private static func tokens(_ value: Any?) -> Int {
        guard let number = value as? NSNumber else { return 0 }
        let value = number.doubleValue
        guard value.isFinite, value > 0 else { return 0 }
        return Int(min(value, Double(LocalUsageReader.maxParsedTokenValue)))
    }
}
