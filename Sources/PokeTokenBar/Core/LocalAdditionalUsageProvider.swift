import Foundation
import SQLite3

private enum LocalAdditionalSource: String, Sendable {
    case opencode
    case hermes
    case cursor
    case copilot
    case kiro
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

/// Cursor usage from the dashboard API when signed in, with local SQLite as fallback.
/// `reportsCost` is false — included-plan usage is token-only in the dashboard.
struct LocalCursorProvider: UsageProvider {
    let id = "cursor"
    let displayName = "Cursor"
    let reportsCost = false

    func fetchDaily() async throws -> DailyUsage? {
        let entries = await LocalAdditionalUsageCache.shared.entries(for: .cursor)
        return LocalUsageReader.daily(entries: entries, localDay: LocalUsageReader.todayKey())
    }

    func fetchEnrichment() async -> ProviderEnrichment {
        let entries = await LocalAdditionalUsageCache.shared.entries(for: .cursor)
        return enrichment(entries: entries)
    }
}

/// GitHub Copilot CLI usage from its local session store database.
struct LocalCopilotProvider: UsageProvider {
    let id = "copilot"
    let displayName = "Copilot"
    /// Copilot bills subscription premium requests, not per-token dollars — tokens only.
    let reportsCost = false

    func fetchDaily() async throws -> DailyUsage? {
        let entries = await LocalAdditionalUsageCache.shared.entries(for: .copilot)
        return LocalUsageReader.daily(entries: entries, localDay: LocalUsageReader.todayKey())
    }

    func fetchEnrichment() async -> ProviderEnrichment {
        let entries = await LocalAdditionalUsageCache.shared.entries(for: .copilot)
        return enrichment(entries: entries)
    }
}

/// Kiro CLI usage estimated from local conversation history.
///
/// Two on-disk generations coexist. Pre-2.20 writes
/// `~/Library/Application Support/kiro-cli/data.sqlite3`. 2.20+ / `kiro-cli --v3`
/// write JSONL under `~/.kiro/sessions` (`cli/*.jsonl`, or
/// `<workspace>/<session>/messages.jsonl`). Neither store persists a real token
/// count — tokens here are a bytes/4 estimate of resent conversation text.
/// `usage_summary` credits are not API dollars, so `reportsCost` stays false.
///
/// Kiro also *deletes* turns from its SQLite store on `/clear` or compaction (unlike every
/// other local source here, whose on-disk logs only grow), so this provider merges each
/// scan with previously-seen entries — see the `.kiro` case in `LocalAdditionalUsageCache`.
/// A cleared conversation's already-counted tokens stay counted for the rest of the app's
/// process lifetime, but are lost like any other in-memory cache on the next app restart.
struct LocalKiroProvider: UsageProvider {
    let id = "kiro"
    let displayName = "Kiro"
    let reportsCost = false

    func fetchDaily() async throws -> DailyUsage? {
        let entries = await LocalAdditionalUsageCache.shared.entries(for: .kiro)
        return LocalUsageReader.daily(entries: entries, localDay: LocalUsageReader.todayKey())
    }

    func fetchEnrichment() async -> ProviderEnrichment {
        let entries = await LocalAdditionalUsageCache.shared.entries(for: .kiro)
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
        /// Cursor `cursorDiskKV` / Copilot `assistant_usage_events` have no usable
        /// time column for the cache key — per-DB high-water for append-only rows.
        let highWaterByPath: [String: Int64]
        /// Kiro skip state lives next to the entries it justifies. A month-key
        /// drop that empties `entries` also drops the signatures, so the skip
        /// cannot fire against an empty `existing` (#179).
        let kiroSignatures: [String: (mtime: Date, size: Int)]
    }

    private struct ScanResult: Sendable {
        var entries: [LocalUsageReader.Entry]
        var highWaterByPath: [String: Int64] = [:]
        var kiroSignatures: [String: (mtime: Date, size: Int)] = [:]
    }

    private var cached: [LocalAdditionalSource: Cached] = [:]
    private var inFlight: [LocalAdditionalSource: Task<ScanResult, Never>] = [:]
    /// Bumped by `invalidate()` so a scan that started on old roots cannot republish.
    private var epoch = 0

    func invalidate() {
        epoch += 1
        cached = [:]
        inFlight = [:]
    }

    func entries(for source: LocalAdditionalSource) async -> [LocalUsageReader.Entry] {
        let now = Date()
        let monthKey = LocalUsageReader.monthKey(now)
        let previous = cached[source].flatMap { $0.monthKey == monthKey ? $0 : nil }
        if let value = previous,
           now.timeIntervalSince(value.loadedAt) < 30 {
            return value.entries
        }
        if let task = inFlight[source] { return await task.value.entries }

        // 스캔 하한은 enrichment 의 세 윈도우(블록·주·월) 중 가장 이른 시작 — 월초 경계 흡수.
        // (Claude/Codex/Gemini 경로와 이 단일 소스를 공유해 과거의 window 드리프트를 원천 차단.)
        let periodStart = LocalUsageReader.enrichmentScanStart(now: now)
        // OpenCode messages / Cursor bubbles are append-only. After the cold monthly read,
        // only query records past the newest cached watermark (with a small OpenCode overlap).
        // This keeps minute-by-minute refreshes cheap even for large databases.
        let since: Date
        let afterRowIDByPath: [String: Int64]
        switch source {
        case .opencode:
            if let newest = previous?.entries.map(\.date).max() {
                since = max(periodStart, newest.addingTimeInterval(-1))
            } else {
                since = periodStart
            }
            afterRowIDByPath = [:]
        case .cursor:
            since = periodStart
            afterRowIDByPath = previous?.highWaterByPath ?? [:]
        case .copilot:
            // `assistant_usage_events` is append-only with an AUTOINCREMENT id — replay
            // only the rows written since the last scan.
            since = periodStart
            afterRowIDByPath = previous?.highWaterByPath ?? [:]
        case .hermes:
            since = periodStart
            afterRowIDByPath = [:]
        case .kiro:
            // Kiro rewrites a conversation's whole history JSON in place every turn — there
            // is no append-only table with a monotonic id to watermark, so every scan
            // re-reads and re-derives entries (idempotent via the stable per-turn id).
            // Unlike Hermes' durable `sessions` table, `/clear` and compaction *delete* turns
            // from Kiro's DB outright, so this source also merges with `existing` below —
            // a cleared turn must stay counted for the rest of the process lifetime, not
            // silently drop out of today's total.
            since = periodStart
            afterRowIDByPath = [:]
        }
        let existing = previous?.entries ?? []
        let knownKiro = previous?.kiroSignatures ?? [:]
        let task = Task.detached(priority: .utility) {
            () async -> ScanResult in
            switch source {
            case .opencode:
                let loaded = LocalAdditionalUsageReader.openCodeEntries(modifiedSince: since)
                return ScanResult(entries: LocalUsageReader.dedupKeepMax(existing + loaded))
            case .hermes:
                return ScanResult(entries: LocalAdditionalUsageReader.hermesEntries(modifiedSince: since))
            case .kiro:
                let loaded = LocalAdditionalUsageReader.kiroEntries(
                    modifiedSince: since, knownSignatures: knownKiro)
                return ScanResult(
                    entries: LocalUsageReader.dedupKeepMax(existing + loaded.entries),
                    kiroSignatures: loaded.signatures)
            case .cursor:
                let loaded = await LocalAdditionalUsageReader.cursorEntriesAsync(
                    modifiedSince: since, afterRowIDByPath: afterRowIDByPath)
                // DB rewrite / VACUUM can drop max(rowid) below the watermark — discard
                // the stale in-memory set and take the full rescan result.
                if loaded.didReset {
                    return ScanResult(entries: loaded.entries, highWaterByPath: loaded.highWaterByPath)
                }
                // A successful dashboard response is authoritative even when it is empty.
                // Do not retain stale API rows or merge local bubble estimates.
                if loaded.isAuthoritative {
                    return ScanResult(
                        entries: loaded.entries, highWaterByPath: loaded.highWaterByPath)
                }
                let localExisting = existing.filter {
                    !LocalAdditionalUsageReader.isCursorDashboardEntry($0)
                }
                return ScanResult(
                    entries: LocalUsageReader.dedupKeepMax(localExisting + loaded.entries),
                    highWaterByPath: loaded.highWaterByPath)
            case .copilot:
                let loaded = LocalAdditionalUsageReader.copilotEntries(
                    modifiedSince: since, afterRowIDByPath: afterRowIDByPath)
                // A pruned / recreated session store restarts ids — the cached rows would
                // then collide with different events, so keep only the rescan.
                if loaded.didReset {
                    return ScanResult(entries: loaded.entries, highWaterByPath: loaded.highWaterByPath)
                }
                return ScanResult(
                    entries: LocalUsageReader.dedupKeepMax(existing + loaded.entries),
                    highWaterByPath: loaded.highWaterByPath)
            }
        }
        let startEpoch = epoch
        inFlight[source] = task
        let result = await task.value
        if startEpoch != epoch {
            return result.entries
        }
        inFlight[source] = nil
        cached[source] = Cached(
            loadedAt: now, monthKey: monthKey, entries: result.entries,
            highWaterByPath: result.highWaterByPath,
            kiroSignatures: result.kiroSignatures)
        return result.entries
    }
}

/// Native parsers for the OpenCode / Hermes on-disk usage formats
/// (SQLite + legacy JSON). No external usage CLI is installed or launched.
enum LocalAdditionalUsageReader {
    typealias Object = [String: Any]

    /// Drop the 30s hit so a newly saved extra folder is scanned on the next refresh (#177).
    static func invalidateScanCache() async {
        await LocalAdditionalUsageCache.shared.invalidate()
    }

    static var defaultOpenCodeRoots: [URL] {
        environmentPaths("OPENCODE_DATA_DIR")
            ?? [FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/share/opencode")]
    }

    static func openCodeRoots(
        customRootsValue: String? = nil,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [URL] {
        let curated = environmentPaths("OPENCODE_DATA_DIR")
            ?? [home.appendingPathComponent(".local/share/opencode")]
        return CustomScanRoots.union(defaults: curated, extraRaw: customRootsValue)
    }

    static var defaultHermesRoots: [URL] {
        environmentPaths("HERMES_HOME")
            ?? [FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".hermes")]
    }

    static func hermesRoots(
        customRootsValue: String? = nil,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [URL] {
        let curated = environmentPaths("HERMES_HOME")
            ?? [home.appendingPathComponent(".hermes")]
        return CustomScanRoots.union(defaults: curated, extraRaw: customRootsValue)
    }

    static func openCodeEntries(
        modifiedSince: Date,
        roots: [URL]? = nil
    ) -> [LocalUsageReader.Entry] {
        let sourceRoots = roots ?? openCodeRoots(
            customRootsValue: CustomScanRoots.storedValue(for: "opencode"))
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
        let sourceRoots = roots ?? hermesRoots(
            customRootsValue: CustomScanRoots.storedValue(for: "hermes"))
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
        var rows = query(database, sql: recentSQL, bindInt64: cutoff) { statement in
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
        return query(database, sql: sql, bindInt64: Int64(modifiedSince.timeIntervalSince1970)) { statement in
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

    // MARK: Incremental SQLite stores

    /// How to bind one append-only row query. Column 0 must be the monotonic id
    /// used as the per-database watermark (`rowid` for Cursor, `id` for Copilot).
    ///
    /// `rowSQL` is a closure rather than a single string because Cursor has two
    /// statements (cold GLOB vs incremental `NOT INDEXED`) and Copilot binds a
    /// second text cutoff. The watermark rules themselves stay in
    /// `scanIncrementalStores` (#157).
    struct IncrementalRowQuery: Sendable {
        var sql: String
        var bindInt64: Int64?
        var bindText: String?
    }

    /// Shared Cursor/Copilot load payload. Identical members collapsed into one
    /// type so a watermark fix cannot land in only one copy.
    struct IncrementalStoreLoadResult: Sendable {
        var entries: [LocalUsageReader.Entry]
        var highWaterByPath: [String: Int64]
        /// True when any DB was rescanned from scratch (watermark invalidated).
        var didReset: Bool
        /// True when a remote source produced a complete result, including an empty one.
        var isAuthoritative: Bool = false

        /// Convenience for single-database tests.
        var highWaterRowID: Int64 { highWaterByPath.values.max() ?? 0 }
    }

    typealias CursorLoadResult = IncrementalStoreLoadResult
    typealias CopilotLoadResult = IncrementalStoreLoadResult

    /// Incremental scan for append-only SQLite stores.
    ///
    /// Format-specific pieces (`databaseURL`, `maxRowIDSQL`, `rowSQL`, `parse`)
    /// stay with the provider. These rules live here once:
    /// - a failed `MAX(...)` is not a shrink (`nil` keeps the prior watermark)
    /// - `if highWater == 0 { highWater = effectiveAfter }` so an empty
    ///   incremental read does not replay the month
    /// - `didReset` on any root cold-rescans **every** root so a partial
    ///   payload cannot replace the cache
    static func scanIncrementalStores(
        roots: [URL],
        modifiedSince: Date,
        afterRowID: Int64 = 0,
        afterRowIDByPath: [String: Int64]? = nil,
        databaseURL: (URL) -> URL,
        maxRowIDSQL: String,
        rowSQL: (Int64, Date) -> IncrementalRowQuery,
        parse: (OpaquePointer, URL) -> LocalUsageReader.Entry?
    ) -> IncrementalStoreLoadResult {
        let marks = incrementalWatermarks(
            roots: roots, afterRowID: afterRowID, afterRowIDByPath: afterRowIDByPath,
            databaseURL: databaseURL)
        var result = scanIncrementalRoots(
            roots, modifiedSince: modifiedSince, marks: marks,
            databaseURL: databaseURL, maxRowIDSQL: maxRowIDSQL,
            rowSQL: rowSQL, parse: parse)
        if result.didReset {
            // A partial incremental payload must not replace the cache — rescan every root cold.
            // Keep didReset=true so the provider cache discards `existing` rather than merging.
            let recovered = scanIncrementalRoots(
                roots, modifiedSince: modifiedSince, marks: [:],
                databaseURL: databaseURL, maxRowIDSQL: maxRowIDSQL,
                rowSQL: rowSQL, parse: parse)
            result = IncrementalStoreLoadResult(
                entries: recovered.entries,
                highWaterByPath: recovered.highWaterByPath,
                didReset: true)
        }
        return result
    }

    /// Resolve per-database watermarks. An empty marks map means cold-scan every root.
    private static func incrementalWatermarks(
        roots: [URL],
        afterRowID: Int64,
        afterRowIDByPath: [String: Int64]?,
        databaseURL: (URL) -> URL
    ) -> [String: Int64] {
        if let afterRowIDByPath { return afterRowIDByPath }
        guard afterRowID > 0 else { return [:] }
        return Dictionary(uniqueKeysWithValues: roots.map { root in
            (databaseURL(root).path, afterRowID)
        })
    }

    private static func scanIncrementalRoots(
        _ sourceRoots: [URL],
        modifiedSince: Date,
        marks: [String: Int64],
        databaseURL: (URL) -> URL,
        maxRowIDSQL: String,
        rowSQL: (Int64, Date) -> IncrementalRowQuery,
        parse: (OpaquePointer, URL) -> LocalUsageReader.Entry?
    ) -> IncrementalStoreLoadResult {
        var entries: [LocalUsageReader.Entry] = []
        var highWaterByPath: [String: Int64] = [:]
        var didReset = false
        for root in sourceRoots {
            let database = databaseURL(root)
            let pathKey = database.path
            let loaded = loadIncrementalDatabase(
                database, modifiedSince: modifiedSince,
                afterRowID: marks[pathKey] ?? 0,
                maxRowIDSQL: maxRowIDSQL, rowSQL: rowSQL, parse: parse)
            entries += loaded.entries
            highWaterByPath[pathKey] = loaded.highWaterRowID
            if loaded.didReset { didReset = true }
        }
        return IncrementalStoreLoadResult(
            entries: LocalUsageReader.dedupKeepMax(entries.filter { $0.date >= modifiedSince }),
            highWaterByPath: highWaterByPath,
            didReset: didReset)
    }

    private struct IncrementalDatabaseLoad {
        var entries: [LocalUsageReader.Entry]
        var highWaterRowID: Int64
        var didReset: Bool
    }

    private static func loadIncrementalDatabase(
        _ database: URL,
        modifiedSince: Date,
        afterRowID: Int64,
        maxRowIDSQL: String,
        rowSQL: (Int64, Date) -> IncrementalRowQuery,
        parse: (OpaquePointer, URL) -> LocalUsageReader.Entry?
    ) -> IncrementalDatabaseLoad {
        // A failed MAX is *not* a shrink: open/prepare can fail while the writer
        // holds the file. Collapsing nil → 0 would wipe the cache for up to one
        // refreshInterval.
        guard let maxRowID = scalarInt64(database, sql: maxRowIDSQL) else {
            return IncrementalDatabaseLoad(
                entries: [], highWaterRowID: afterRowID, didReset: false)
        }
        let didReset = afterRowID > 0 && maxRowID < afterRowID
        let effectiveAfter = didReset ? 0 : afterRowID
        let querySpec = rowSQL(effectiveAfter, modifiedSince)

        // Incomplete scans (BUSY / interrupt) return nil — keep the prior watermark.
        guard let rows = query(
            database, sql: querySpec.sql,
            bindInt64: querySpec.bindInt64, bindText: querySpec.bindText,
            row: { statement -> (Int64, LocalUsageReader.Entry?) in
                (sqlite3_column_int64(statement, 0), parse(statement, database))
            }
        ) else {
            return IncrementalDatabaseLoad(
                entries: [], highWaterRowID: afterRowID, didReset: false)
        }

        var highWater: Int64 = 0
        var entries: [LocalUsageReader.Entry] = []
        for (rowID, entry) in rows {
            highWater = max(highWater, rowID)
            if let entry { entries.append(entry) }
        }
        // Preserve watermark when an incremental miss returns no new rows.
        if highWater == 0 { highWater = effectiveAfter }
        return IncrementalDatabaseLoad(
            entries: entries, highWaterRowID: highWater, didReset: didReset)
    }

    // MARK: Cursor database


    static var defaultCursorRoots: [URL] {
        environmentPaths("CURSOR_DATA_DIR") ?? [
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage"),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/Cursor Nightly/User/globalStorage"),
        ]
    }

    static func cursorRoots(
        customRootsValue: String? = nil,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [URL] {
        let curated = environmentPaths("CURSOR_DATA_DIR") ?? [
            home.appendingPathComponent("Library/Application Support/Cursor/User/globalStorage"),
            home.appendingPathComponent("Library/Application Support/Cursor Nightly/User/globalStorage"),
        ]
        return CustomScanRoots.union(defaults: curated, extraRaw: customRootsValue)
    }

    /// Cursor roots including the user's extra scan folders. The usage scan and the
    /// `cursorAuth/accessToken` lookup must agree, or a custom root would report usage
    /// while the dashboard API silently falls back to the local bubble scan.
    static var configuredCursorRoots: [URL] {
        cursorRoots(customRootsValue: CustomScanRoots.storedValue(for: "cursor"))
    }

    static func cursorEntries(
        modifiedSince: Date,
        afterRowID: Int64 = 0,
        afterRowIDByPath: [String: Int64]? = nil,
        roots: [URL]? = nil
    ) -> CursorLoadResult {
        cursorEntriesSync(
            modifiedSince: modifiedSince,
            afterRowID: afterRowID,
            afterRowIDByPath: afterRowIDByPath,
            roots: roots,
            apiEntries: [])
    }

    static func cursorEntriesAsync(
        modifiedSince: Date,
        afterRowID: Int64 = 0,
        afterRowIDByPath: [String: Int64]? = nil,
        roots: [URL]? = nil
    ) async -> CursorLoadResult {
        let api = await CursorUsageAPI.fetchEntries(modifiedSince: modifiedSince)
        return cursorEntriesSync(
            modifiedSince: modifiedSince,
            afterRowID: afterRowID,
            afterRowIDByPath: afterRowIDByPath,
            roots: roots,
            apiEntries: api.entries,
            apiIsAuthoritative: api.isAuthoritative)
    }

    /// Test hook for the dashboard/API path without network I/O.
    static func cursorEntriesFromDashboard(
        modifiedSince: Date,
        dashboardEntries: [LocalUsageReader.Entry],
        roots: [URL]? = nil
    ) -> CursorLoadResult {
        cursorEntriesSync(
            modifiedSince: modifiedSince,
            afterRowID: 0,
            afterRowIDByPath: nil,
            roots: roots,
            apiEntries: dashboardEntries,
            apiIsAuthoritative: true)
    }

    private static func cursorEntriesSync(
        modifiedSince: Date,
        afterRowID: Int64,
        afterRowIDByPath: [String: Int64]?,
        roots: [URL]?,
        apiEntries: [LocalUsageReader.Entry],
        apiIsAuthoritative: Bool = false
    ) -> CursorLoadResult {
        if apiIsAuthoritative {
            return IncrementalStoreLoadResult(
                entries: LocalUsageReader.dedupKeepMax(apiEntries),
                highWaterByPath: [:],
                didReset: false,
                isAuthoritative: true)
        }
        return scanIncrementalStores(
            roots: roots ?? configuredCursorRoots,
            modifiedSince: modifiedSince,
            afterRowID: afterRowID,
            afterRowIDByPath: afterRowIDByPath,
            databaseURL: cursorDatabaseURL(from:),
            maxRowIDSQL: "SELECT MAX(rowid) FROM cursorDiskKV",
            rowSQL: { effectiveAfter, _ in cursorRowQuery(effectiveAfter: effectiveAfter) },
            parse: { statement, _ in
                parseCursorBubbleRow(statement, modifiedSince: modifiedSince)
            })
    }

    /// Cursor IDE login token stored in `state.vscdb` ItemTable.
    static func cursorAuthAccessToken(roots: [URL]? = nil) -> String? {
        for root in roots ?? configuredCursorRoots {
            let database = root.appendingPathComponent("state.vscdb")
            guard FileManager.default.fileExists(atPath: database.path) else { continue }
            for attempt in 0 ..< 6 {
                let rows = query(database, sql: """
                    SELECT value FROM ItemTable WHERE key = 'cursorAuth/accessToken' LIMIT 1
                    """) { statement -> String? in
                    columnText(statement, 0)
                }
                if let token = rows?.first?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
                    return token
                }
                if rows != nil { break }
                Thread.sleep(forTimeInterval: 0.05 * Double(attempt + 1))
            }
        }
        return nil
    }

    /// Debug string for AppLog when session token lookup fails (no secret values).
    static func cursorAuthDiagnostics(roots: [URL]? = nil) -> String {
        var parts: [String] = []
        for root in roots ?? configuredCursorRoots {
            let database = root.appendingPathComponent("state.vscdb")
            guard FileManager.default.fileExists(atPath: database.path) else {
                parts.append("\(database.lastPathComponent): missing")
                continue
            }
            let rows = query(database, sql: """
                SELECT value FROM ItemTable WHERE key = 'cursorAuth/accessToken' LIMIT 1
                """) { statement -> String? in
                columnText(statement, 0)
            }
            switch rows {
            case .none:
                parts.append("\(root.lastPathComponent): sqlite busy/error")
            case .some(let values) where values.isEmpty:
                parts.append("\(root.lastPathComponent): key absent (not logged in?)")
            case .some(let values):
                parts.append("\(root.lastPathComponent): ok (\(values[0].count) chars)")
            }
        }
        return parts.isEmpty ? "no cursor data dirs" : parts.joined(separator: "; ")
    }

    /// Usage from Cursor's dashboard API (`cursor|api|` entry ids).
    static func isCursorDashboardEntry(_ entry: LocalUsageReader.Entry) -> Bool {
        entry.id.hasPrefix("cursor|api|")
    }

    static func makeUsageEntry(
        id: String,
        date: Date,
        model: String,
        input: Int = 0,
        output: Int = 0,
        cacheWrite: Int = 0,
        cacheRead: Int = 0,
        cost: Double? = nil
    ) -> LocalUsageReader.Entry? {
        makeEntry(
            id: id, date: date, model: model,
            input: input, output: output, cacheWrite: cacheWrite, cacheRead: cacheRead,
            cost: cost)
    }

    /// cursorDiskKV: key TEXT UNIQUE, value BLOB. No time column — filter by
    /// createdAt in JSON. Cold start uses the key index over bubbleId:* only.
    /// Incremental: NOT INDEXED + rowid > ? walks *new* rows; without NOT INDEXED
    /// SQLite prefers the key index. Shared with `cursorIncrementalQueryPlan` so
    /// the EXPLAIN test pins the SQL the scanner actually runs.
    private static func cursorRowQuery(effectiveAfter: Int64) -> IncrementalRowQuery {
        if effectiveAfter == 0 {
            return IncrementalRowQuery(
                sql: "SELECT rowid, key, value FROM cursorDiskKV WHERE key GLOB 'bubbleId:*'",
                bindInt64: nil, bindText: nil)
        }
        return IncrementalRowQuery(
            sql: """
            SELECT rowid, key, value FROM cursorDiskKV NOT INDEXED
            WHERE rowid > ?1 AND key GLOB 'bubbleId:*'
            """,
            bindInt64: effectiveAfter, bindText: nil)
    }

    private static func cursorDatabaseURL(from root: URL) -> URL {
        root.pathExtension == "vscdb" ? root : root.appendingPathComponent("state.vscdb")
    }

    /// Exposed for regression tests — incremental plan must walk rowids, not the key index.
    static func cursorIncrementalQueryPlan(database: URL, afterRowID: Int64) -> String? {
        guard afterRowID > 0 else { return nil }
        let query = cursorRowQuery(effectiveAfter: afterRowID)
        return explainQueryPlan(
            database, sql: "EXPLAIN QUERY PLAN \(query.sql)", bindInt64: query.bindInt64)
    }

    private static func parseCursorBubbleRow(
        _ statement: OpaquePointer,
        modifiedSince: Date
    ) -> LocalUsageReader.Entry? {
        guard let key = columnText(statement, 1),
              let payload = columnText(statement, 2),
              let object = jsonObject(data: Data(payload.utf8)) else { return nil }
        return parseCursorBubble(object, key: key, modifiedSince: modifiedSince)
    }

    /// Parse a single Cursor chat bubble JSON blob into a usage entry.
    /// Bubble schema (from cursorDiskKV): `tokenCount.{inputTokens, outputTokens}`,
    /// `createdAt` (ISO 8601 string or epoch number), `modelType` (nullable).
    static func parseCursorBubble(
        _ object: Object,
        key: String,
        modifiedSince: Date
    ) -> LocalUsageReader.Entry? {
        guard let tokenCount = object["tokenCount"] as? Object else { return nil }
        let input = intValue(tokenCount["inputTokens"])
        let output = intValue(tokenCount["outputTokens"])
        guard input + output > 0 else { return nil }
        guard let date = flexibleDateValue(object["createdAt"]) else { return nil }
        guard date >= modifiedSince else { return nil }
        let model = stringValue(object["modelType"]) ?? "unknown"
        return makeEntry(
            id: "cursor|\(key)",
            date: date,
            model: model,
            input: input,
            output: output)
    }

    private static let iso8601Lock = NSLock()
    // ISO8601DateFormatter is not Sendable; access is serialized by `iso8601Lock`.
    nonisolated(unsafe) private static let iso8601Fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    nonisolated(unsafe) private static let iso8601Plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// Reuses locked static formatters — Cursor cold scans parse thousands of `createdAt` rows.
    private static func parseISO8601(_ string: String) -> Date? {
        iso8601Lock.lock()
        let cached: Date?
        if let date = iso8601Fractional.date(from: string) {
            cached = date
        } else if let date = iso8601Plain.date(from: string) {
            cached = date
        } else {
            cached = nil
        }
        iso8601Lock.unlock()
        // Odd fractional widths (e.g. microseconds) — rare for Cursor bubbles.
        return cached ?? ISO8601Parser.date(from: string)
    }

    /// Accepts ISO-8601 strings or epoch numbers (seconds / millis), matching OpenCode.
    private static func flexibleDateValue(_ value: Any?) -> Date? {
        if let string = value as? String { return parseISO8601(string) }
        return dateValue(value)
    }

    // MARK: Copilot CLI database

    static var defaultCopilotRoots: [URL] {
        environmentPaths("COPILOT_HOME")
            ?? [FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".copilot")]
    }

    static func copilotRoots(
        customRootsValue: String? = nil,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [URL] {
        let curated = environmentPaths("COPILOT_HOME")
            ?? [home.appendingPathComponent(".copilot")]
        return CustomScanRoots.union(defaults: curated, extraRaw: customRootsValue)
    }

    /// Read Copilot CLI usage rows newer than `modifiedSince`.
    ///
    /// Every row in `assistant_usage_events` is one billed API call, including the ones a
    /// subagent makes — those are separate requests, not a copy of the parent turn, so
    /// unlike Grok's session logs there is nothing to exclude here.
    ///
    /// `afterRowIDByPath` carries the previous scan's high-water `id` per database so
    /// steady-state refreshes touch only the rows appended since then.
    static func copilotEntries(
        modifiedSince: Date,
        afterRowID: Int64 = 0,
        afterRowIDByPath: [String: Int64]? = nil,
        roots: [URL]? = nil
    ) -> CopilotLoadResult {
        scanIncrementalStores(
            roots: roots ?? copilotRoots(customRootsValue: CustomScanRoots.storedValue(for: "copilot")),
            modifiedSince: modifiedSince,
            afterRowID: afterRowID,
            afterRowIDByPath: afterRowIDByPath,
            databaseURL: copilotDatabaseURL(from:),
            maxRowIDSQL: "SELECT MAX(id) FROM assistant_usage_events",
            rowSQL: { effectiveAfter, since in
                // `created_at` is text, so the cutoff is a lexicographic compare, not a
                // time compare. It is only a coarse prefilter — the shared scanner
                // re-filters on parsed dates — but it must never drop a row that belongs
                // in the window, and a dropped row is lost for good once a later id
                // advances the watermark. A same-day row in the ISO-8601 shape is safe
                // (its "T" sorts after the cutoff's space), yet a row carrying a UTC
                // offset can still render an earlier calendar day than the instant it
                // represents ("2026-01-03T20:00:00-05:00" is 2026-01-04T01:00:00Z).
                // Backing the cutoff off by a full day covers every offset SQLite
                // accepts (±14h) and costs one extra day of rows.
                IncrementalRowQuery(
                    sql: """
                    SELECT id, model, input_tokens, output_tokens, cache_read_tokens, cache_write_tokens, created_at
                    FROM assistant_usage_events
                    WHERE id > ?1 AND created_at >= ?2
                    """,
                    bindInt64: effectiveAfter,
                    bindText: copilotDayCutoff(since))
            },
            parse: { statement, database in
                parseCopilotUsageRow(statement, database: database)
            })
    }

    private static func copilotDatabaseURL(from root: URL) -> URL {
        root.pathExtension == "db" ? root : root.appendingPathComponent("session-store.db")
    }

    private static func parseCopilotUsageRow(
        _ statement: OpaquePointer,
        database: URL
    ) -> LocalUsageReader.Entry? {
        let id = sqlite3_column_int64(statement, 0)
        guard let rawDate = columnText(statement, 6),
              let date = copilotDate(rawDate) else { return nil }
        let model = stringValue(columnText(statement, 1)) ?? "unknown"
        let cacheRead = columnInt(statement, 4)
        let cacheWrite = columnInt(statement, 5)
        // `input_tokens` is the whole prompt: cached reads and writes are a subset of it.
        // Subtracting them keeps the same prompt tokens from being counted three times.
        let input = max(0, columnInt(statement, 2) - cacheRead - cacheWrite)
        // `reasoning_tokens` is a breakdown of `output_tokens`, not an extra charge.
        return makeEntry(
            // The row id is only unique *within* one store, and `$COPILOT_HOME` may name
            // several. Without the database in the key, id 1 of each store would collapse
            // into a single event during dedup and the usage would silently go missing.
            id: "copilot|\(database.path)|\(id)",
            date: date,
            model: model,
            input: input,
            output: columnInt(statement, 3),
            cacheWrite: cacheWrite,
            cacheRead: cacheRead)
    }

    /// Start of the UTC day *before* `date`, in the SQLite default text shape
    /// ("YYYY-MM-DD HH:MM:SS"), so the coarse text cutoff always sits below the window.
    private static func copilotDayCutoff(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let shifted = date.addingTimeInterval(-86_400)
        let parts = calendar.dateComponents([.year, .month, .day], from: shifted)
        return String(
            format: "%04d-%02d-%02d 00:00:00",
            parts.year ?? 1970, parts.month ?? 1, parts.day ?? 1)
    }

    /// Copilot writes ISO-8601 with a "Z" suffix, while the column default
    /// (`datetime('now')`) writes "YYYY-MM-DD HH:MM:SS" in UTC. Normalize both.
    static func copilotDate(_ raw: String) -> Date? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 19 else { return nil }
        if let separator = text.firstIndex(of: " ") {
            text.replaceSubrange(separator...separator, with: "T")
        }
        let time = text.dropFirst(11)
        if !time.contains("Z"), !time.contains("+"), !time.contains("-") { text += "Z" }
        return parseISO8601(text)
    }

    // MARK: Kiro CLI database + JSONL sessions

    static var defaultKiroRoots: [URL] {
        kiroRoots(customRootsValue: nil)
    }

    static func kiroRoots(
        customRootsValue: String? = nil,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [URL] {
        let sqlite = environmentPaths("KIRO_CLI_HOME")
            ?? [home.appendingPathComponent("Library/Application Support/kiro-cli")]
        let kiroHomes = environmentPaths("KIRO_HOME")
            ?? [home.appendingPathComponent(".kiro")]
        let sessions = kiroHomes.map { $0.appendingPathComponent("sessions") }
        return CustomScanRoots.union(defaults: sqlite + sessions, extraRaw: customRootsValue)
    }

    /// Read Kiro CLI usage turns newer than `modifiedSince`.
    ///
    /// Pre-2.20 Kiro persists a conversation as one SQLite row whose `value` column holds
    /// the *entire* history as JSON, rewritten in place on every turn — there is no per-row
    /// token count (see the type doc on `LocalKiroProvider`) and no append-only id to
    /// watermark. Two schema generations coexist: `conversations_v2` (kiro-cli < 2.0.1) and
    /// `conversations` (2.0.1+). 2.20+ / `--v3` stopped writing that database and append
    /// JSONL under `~/.kiro/sessions` instead (#236). Both stores are scanned; overlapping
    /// extra folders are folded by file path so a custom `~/.kiro` does not double-count
    /// the default `~/.kiro/sessions` files.
    ///
    /// `modifiedSince` is applied *after* the parse, so it bounds the output, not the work
    /// (#178). The cheap gate is the file's own signature — reused from
    /// `LocalAntigravityUsageReader.signature` (for SQLite: `.sqlite3` + `-wal`, never
    /// `-shm`). An unchanged file returns `[]`; the `.kiro` cache merges
    /// `existing + loaded`, so that keeps previously-seen entries. Signatures are supplied
    /// by that cache (`knownSignatures`) and die with it on a month-key drop (#179).
    /// The first scan of a process passes `[:]`.
    static func kiroEntries(
        modifiedSince: Date,
        roots: [URL]? = nil
    ) -> [LocalUsageReader.Entry] {
        kiroEntries(modifiedSince: modifiedSince, knownSignatures: [:], roots: roots).entries
    }

    static func kiroEntries(
        modifiedSince: Date,
        knownSignatures: [String: (mtime: Date, size: Int)],
        roots: [URL]? = nil
    ) -> (entries: [LocalUsageReader.Entry], signatures: [String: (mtime: Date, size: Int)]) {
        let sourceRoots = roots ?? kiroRoots(
            customRootsValue: CustomScanRoots.storedValue(for: "kiro"))
        var entries: [LocalUsageReader.Entry] = []
        var signatures: [String: (mtime: Date, size: Int)] = [:]
        var seenFiles = Set<String>()
        for root in sourceRoots {
            let database = kiroDatabaseURL(from: root)
            if seenFiles.insert(database.path).inserted {
                let scanned = kiroDatabaseEntries(
                    database, modifiedSince: modifiedSince, known: knownSignatures)
                entries += scanned.entries
                if let signature = scanned.signature {
                    signatures[database.path] = signature
                }
            }
            for file in kiroJSONLSessionFiles(in: root) where seenFiles.insert(file.path).inserted {
                let scanned = kiroJSONLFileEntries(
                    file, modifiedSince: modifiedSince, known: knownSignatures)
                entries += scanned.entries
                if let signature = scanned.signature {
                    signatures[file.path] = signature
                }
            }
        }
        return (LocalUsageReader.dedupKeepMax(entries), signatures)
    }

    private static func kiroDatabaseURL(from root: URL) -> URL {
        root.pathExtension == "sqlite3" ? root : root.appendingPathComponent("data.sqlite3")
    }

    private static func kiroDatabaseEntries(
        _ database: URL,
        modifiedSince: Date,
        known: [String: (mtime: Date, size: Int)]
    ) -> (entries: [LocalUsageReader.Entry], signature: (mtime: Date, size: Int)?) {
        // Stat before the read. A commit that lands mid-read then differs from
        // the stored signature on the next poll and is re-read; stat afterwards
        // and that same commit is frozen into a signature that already looks current.
        let signature = LocalAntigravityUsageReader.signature(of: database)
        if let signature,
           let remembered = known[database.path],
           remembered.mtime == signature.mtime,
           remembered.size == signature.size {
            return ([], signature)
        }

        var entries: [LocalUsageReader.Entry] = []

        // kiro-cli < 2.0.1: one row per conversation, with dedicated id/timestamp columns.
        let v2Rows = query(database, sql: "SELECT conversation_id, value FROM conversations_v2") {
            statement -> (id: String?, value: String)? in
            guard let value = columnText(statement, 1) else { return nil }
            return (columnText(statement, 0), value)
        }
        // kiro-cli 2.0.1+: one row per working directory; the conversation id lives in the JSON.
        // A 2.0.1+ store may still keep `conversations_v2` (nil here is a missing table
        // *or* a scan that stopped early). `query` cannot tell them apart, so a BUSY on
        // one generation plus a success on the other still counts as a completed scan.
        let v1Rows = query(database, sql: "SELECT value FROM conversations") {
            statement -> String? in columnText(statement, 0)
        }
        // Both nil: open/prepare/step failed (BUSY, corrupt, missing file that
        // still couldn't be opened). Do not occupy the skip slot — the next
        // poll must retry. A missing table on one generation is nil while the
        // other succeeds, so "at least one non-nil" is a completed scan.
        guard v2Rows != nil || v1Rows != nil else { return ([], nil) }

        for row in v2Rows ?? [] {
            guard let object = jsonObject(data: Data(row.value.utf8)) else { continue }
            let conversationID = row.id ?? stringValue(object["conversation_id"]) ?? database.path
            entries += kiroTurnEntries(conversationID: conversationID, object: object, modifiedSince: modifiedSince)
        }
        for value in v1Rows ?? [] {
            guard let object = jsonObject(data: Data(value.utf8)),
                  let conversationID = stringValue(object["conversation_id"]) else { continue }
            entries += kiroTurnEntries(conversationID: conversationID, object: object, modifiedSince: modifiedSince)
        }

        return (entries, signature)
    }

    /// Bytes-per-token used to turn estimated byte counts into an approximate token count.
    /// There is nothing more precise available locally.
    private static let kiroBytesPerToken = 4

    /// Kiro has no server-side session — every turn resends the *whole* conversation, so a
    /// turn's real prompt size is the accumulated history plus its own new user message.
    /// `request_metadata.user_prompt_length` is **not** that: in kiro-cli's upstream
    /// (`aws/amazon-q-developer-cli`, `crates/chat-cli/src/cli/chat/parser.rs`) it is assigned
    /// from `conversation_state.user_input_message.content.len()` — only the bytes the user
    /// just typed, excluding the resent history entirely. Using it as-is would undercount a
    /// prompt by orders of magnitude once a conversation has any length. `response_size`
    /// (`received_response_size`, accumulated from the actual streamed response/tool-input
    /// bytes) has no such gap and is used as-is for output.
    private static func kiroTurnEntries(
        conversationID: String,
        object: Object,
        modifiedSince: Date
    ) -> [LocalUsageReader.Entry] {
        guard let turns = object["history"] as? [Any] else { return [] }
        var entries: [LocalUsageReader.Entry] = []
        // `latest_summary` stands in for turns compaction deleted from `history` — it still
        // gets resent on every later request, so it seeds the running total (matches the
        // reference `kiro-usage` tool's `cumulative = summary_tok`).
        var cumulativeHistoryBytes = kiroJSONValueByteLength(object["latest_summary"] ?? 0)
        for turn in turns {
            guard let turnObject = turn as? Object else { continue }
            let userBytes = kiroFieldByteLength(turnObject["user"])
            // Bytes must accumulate into history even for turns skipped below (missing
            // timestamp, outside the window) — later turns still resend them.
            defer { cumulativeHistoryBytes += userBytes + kiroFieldByteLength(turnObject["assistant"]) }

            guard let meta = turnObject["request_metadata"] as? Object,
                  // A turn missing its timestamp has nothing stable to key an entry id on —
                  // skip it rather than invent one, matching the reference `kiro-usage` tool.
                  let rawTimestamp = doubleValue(meta["request_start_timestamp_ms"]), rawTimestamp > 0,
                  let date = dateValue(meta["request_start_timestamp_ms"]),
                  date >= modifiedSince else { continue }
            let promptBytes = cumulativeHistoryBytes + userBytes
            guard let entry = makeEntry(
                id: "kiro|\(conversationID)|\(Int64(rawTimestamp))",
                date: date,
                model: stringValue(meta["model_id"]) ?? "unknown",
                input: promptBytes / kiroBytesPerToken,
                output: intValue(meta["response_size"]) / kiroBytesPerToken) else { continue }
            entries.append(entry)
        }
        return entries
    }

    /// Byte length of a turn's `user`/`assistant` field, matching the reference `kiro-usage`
    /// tool's `_text_len`: sum the stringified value of every key except `images` (a base64
    /// blob that would otherwise dwarf the actual text and isn't separately token-modeled here).
    private static func kiroFieldByteLength(_ value: Any?) -> Int {
        guard let dict = value as? Object else {
            if let string = value as? String { return string.utf8.count }
            return 0
        }
        return dict.reduce(0) { total, entry in
            entry.key == "images" ? total : total + kiroJSONValueByteLength(entry.value)
        }
    }

    private static func kiroJSONValueByteLength(_ value: Any) -> Int {
        if let string = value as? String { return string.utf8.count }
        if let number = value as? NSNumber { return number.stringValue.utf8.count }
        if let array = value as? [Any] { return array.reduce(0) { $0 + kiroJSONValueByteLength($1) } }
        if let dict = value as? Object { return dict.values.reduce(0) { $0 + kiroJSONValueByteLength($1) } }
        return 0
    }

    // MARK: Kiro JSONL sessions (CLI 2.20 / v3)

    /// Layout-shaped, not "every jsonl under the root". CLI 2.20 writes
    /// `sessions/cli/<id>.jsonl`; v3 / IDE writes `messages.jsonl` next to `session.json`.
    /// Event envelopes were pinned against tokscale/codeburn parsers that were written
    /// from real on-disk files — do not invent a third shape.
    private static func kiroJSONLSessionFiles(in root: URL) -> [URL] {
        if kiroIsJSONLSessionFile(root) { return [root] }
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var out: [URL] = []
        for case let url as URL in enumerator where kiroIsJSONLSessionFile(url) {
            out.append(url)
        }
        return out
    }

    private static func kiroIsJSONLSessionFile(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        if name == "messages.jsonl" { return true }
        return url.pathExtension == "jsonl"
            && url.deletingLastPathComponent().lastPathComponent == "cli"
    }

    private static func kiroJSONLFileEntries(
        _ url: URL,
        modifiedSince: Date,
        known: [String: (mtime: Date, size: Int)]
    ) -> (entries: [LocalUsageReader.Entry], signature: (mtime: Date, size: Int)?) {
        let signature = LocalAntigravityUsageReader.signature(of: url)
        if let signature,
           let remembered = known[url.path],
           remembered.mtime == signature.mtime,
           remembered.size == signature.size {
            return ([], signature)
        }
        guard FileManager.default.fileExists(atPath: url.path) else { return ([], nil) }
        let entries = url.lastPathComponent == "messages.jsonl"
            ? kiroV3JSONLEntries(url, modifiedSince: modifiedSince)
            : kiroCLIJSONLEntries(url, modifiedSince: modifiedSince)
        return (entries, signature)
    }

    /// CLI JSONL: `{version, kind: Prompt|AssistantMessage|ToolResults|Clear, data}`.
    /// Companion `<id>.json` carries `session_id` and `session_state...model_id`.
    private static func kiroCLIJSONLEntries(_ url: URL, modifiedSince: Date) -> [LocalUsageReader.Entry] {
        let companion = jsonObject(at: url.deletingPathExtension().appendingPathExtension("json"))
        let sessionID = stringValue(companion?["session_id"])
            ?? url.deletingPathExtension().lastPathComponent
        let modelInfo = ((companion?["session_state"] as? Object)?["rts_model_state"] as? Object)?["model_info"] as? Object
        let model = stringValue(modelInfo?["model_id"]) ?? "unknown"

        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var entries: [LocalUsageReader.Entry] = []
        var historyBytes = 0
        var promptBytes = 0
        var promptRawTimestamp: Any?
        var promptDate: Date?
        var assistantBytes = 0
        var toolBytes = 0
        var started = false

        func flush() {
            defer {
                historyBytes += promptBytes + assistantBytes + toolBytes
                promptBytes = 0
                promptRawTimestamp = nil
                promptDate = nil
                assistantBytes = 0
                toolBytes = 0
            }
            // Missing timestamp: skip the entry but keep the text in history, same as SQLite.
            guard started, let date = promptDate, date >= modifiedSince else { return }
            let input = (historyBytes + promptBytes + toolBytes) / kiroBytesPerToken
            let output = assistantBytes / kiroBytesPerToken
            let millis = kiroTimestampMillis(raw: promptRawTimestamp, date: date)
            if let entry = makeEntry(
                id: "kiro|cli|\(sessionID)|\(millis)",
                date: date, model: model, input: input, output: output) {
                entries.append(entry)
            }
        }

        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let object = jsonObject(data: Data(line.utf8)) else { continue }
            let kind = stringValue(object["kind"]) ?? ""
            let data = object["data"] as? Object
            if kind == "Prompt" {
                if started { flush() }
                started = true
                promptBytes = kiroJSONLTextBytes(data?["content"])
                promptRawTimestamp = (data?["meta"] as? Object)?["timestamp"]
                promptDate = flexibleDateValue(promptRawTimestamp)
                assistantBytes = 0
                toolBytes = 0
            } else if kind == "AssistantMessage" {
                assistantBytes += kiroJSONLTextBytes(data?["content"])
            } else if kind == "ToolResults" {
                toolBytes += kiroJSONLTextBytes(data?["content"])
            } else if kind == "Clear" {
                flush()
                started = false
                historyBytes = 0
            }
        }
        flush()
        return entries
    }

    /// v3 / IDE: `messages.jsonl` + sibling `session.json`. Two envelopes coexist:
    /// structured `{payload:{type}}` (usage_summary lives here) and flat `{role,content}`.
    /// Credits on `usage_summary` are ignored — they are not API dollars.
    private static func kiroV3JSONLEntries(_ url: URL, modifiedSince: Date) -> [LocalUsageReader.Entry] {
        let sessionURL = url.deletingLastPathComponent().appendingPathComponent("session.json")
        let session = jsonObject(at: sessionURL)
        let sessionID = stringValue(session?["id"])
            ?? url.deletingLastPathComponent().lastPathComponent
        let model = stringValue(session?["modelId"]) ?? "unknown"
        let fallbackDate = flexibleDateValue(session?["createdAt"])
            ?? flexibleDateValue(session?["lastModifiedAt"])

        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var entries: [LocalUsageReader.Entry] = []
        var historyBytes = 0
        var promptBytes = 0
        var promptDate: Date?
        var assistantBytes = 0
        var started = false
        var turnIndex = 0

        func flush() {
            let hadContent = started && promptBytes + assistantBytes > 0
            defer {
                historyBytes += promptBytes + assistantBytes
                promptBytes = 0
                promptDate = nil
                assistantBytes = 0
                // Advance even when the turn is outside the window so later in-window
                // ids stay stable (timestamp-keyed ids would also be window-independent).
                if hadContent { turnIndex += 1 }
            }
            guard hadContent else { return }
            let date = promptDate ?? fallbackDate
            guard let date, date >= modifiedSince else { return }
            let input = (historyBytes + promptBytes) / kiroBytesPerToken
            let output = assistantBytes / kiroBytesPerToken
            if let entry = makeEntry(
                id: "kiro|v3|\(sessionID)|\(turnIndex)",
                date: date, model: model, input: input, output: output) {
                entries.append(entry)
            }
        }

        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let object = jsonObject(data: Data(line.utf8)) else { continue }
            if let payload = object["payload"] as? Object, let type = stringValue(payload["type"]) {
                let eventDate = flexibleDateValue(object["timestamp"])
                switch type {
                case "user":
                    if started { flush() }
                    started = true
                    promptBytes = kiroJSONLTextBytes(payload["content"])
                    promptDate = eventDate
                    assistantBytes = 0
                case "assistant":
                    assistantBytes += kiroJSONLTextBytes(payload["content"])
                    if !started, assistantBytes > 0 { started = true }
                    if promptDate == nil { promptDate = eventDate }
                case "tool_call":
                    // Writer-shaped: tokscale counts payload.args toward the turn's output.
                    if let args = payload["args"] {
                        assistantBytes += (args as? String)?.utf8.count ?? kiroJSONValueByteLength(args)
                    }
                    if !started, assistantBytes > 0 { started = true }
                case "tool_result":
                    promptBytes += kiroJSONLTextBytes(payload["content"])
                case "turn_end":
                    if promptDate == nil { promptDate = eventDate }
                    flush()
                    started = false
                default:
                    // usage_summary / session_metadata: credits are not API dollars.
                    break
                }
            } else if let role = stringValue(object["role"]) {
                let eventDate = flexibleDateValue(object["timestamp"])
                if role == "user" || role == "human" || role == "prompt" {
                    if started { flush() }
                    started = true
                    promptBytes = kiroJSONLTextBytes(object["content"])
                    promptDate = eventDate
                    assistantBytes = 0
                } else if role == "assistant" || role == "bot" {
                    assistantBytes += kiroJSONLTextBytes(object["content"])
                    if !started, assistantBytes > 0 { started = true }
                    if promptDate == nil { promptDate = eventDate }
                }
            }
        }
        flush()
        return entries
    }

    private static func kiroJSONLTextBytes(_ value: Any?) -> Int {
        if let string = value as? String { return string.utf8.count }
        if let array = value as? [Any] {
            return array.reduce(0) { $0 + kiroJSONLTextBytes($1) }
        }
        guard let object = value as? Object else { return 0 }
        if let kind = object["kind"] as? String {
            return kind == "text" ? kiroJSONLTextBytes(object["data"]) : 0
        }
        for key in ["content", "text", "data"] where object[key] != nil {
            return kiroJSONLTextBytes(object[key])
        }
        return 0
    }

    private static func kiroTimestampMillis(raw: Any?, date: Date) -> Int64 {
        if let value = doubleValue(raw), value.isFinite, value > 0 {
            let ms = value < 1_000_000_000_000 ? value * 1000 : value
            return Int64(ms.rounded(.towardZero))
        }
        return Int64((date.timeIntervalSince1970 * 1000).rounded(.towardZero))
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

    /// GUI 앱은 셸 환경을 상속하지 않으므로 `UsageEnvironment` 를 통해 읽는다 — 프로세스 환경만
    /// 보면 `~/.zshrc` 에 `export OPENCODE_DATA_DIR=…` 해 둔 사용자가 앱에서만 조용히 0 을 본다.
    private static func environmentPaths(_ key: String) -> [URL]? {
        guard let raw = UsageEnvironment.value(key) else { return nil }
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
        bindInt64: Int64? = nil,
        bindText: String? = nil,
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
        if let bindInt64 { sqlite3_bind_int64(statement, 1, bindInt64) }
        if let bindText {
            // SQLITE_TRANSIENT: SQLite must copy the bytes, the Swift string dies at return.
            sqlite3_bind_text(statement, 2, bindText, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }

        var result: [T] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_ROW {
                autoreleasepool {
                    if let value = row(statement) { result.append(value) }
                }
                continue
            }
            // Distinguish a finished scan from BUSY / interrupt — partial rows must not
            // advance the Cursor watermark past bubbles we never read.
            guard step == SQLITE_DONE else { return nil }
            break
        }
        return result
    }

    private static func scalarInt64(_ databaseURL: URL, sql: String) -> Int64? {
        let rows = query(databaseURL, sql: sql) { statement -> Int64 in
            sqlite3_column_int64(statement, 0)
        }
        return rows?.first
    }

    private static func explainQueryPlan(
        _ databaseURL: URL,
        sql: String,
        bindInt64: Int64? = nil
    ) -> String? {
        let rows = query(databaseURL, sql: sql, bindInt64: bindInt64) { statement -> String in
            // EXPLAIN QUERY PLAN columns: id, parent, notused, detail
            columnText(statement, 3) ?? ""
        }
        guard let rows, !rows.isEmpty else { return nil }
        return rows.joined(separator: " | ")
    }

    private static func columnText(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard let bytes = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: bytes)
    }

    private static func columnInt(_ statement: OpaquePointer, _ index: Int32) -> Int {
        max(0, Int(sqlite3_column_int64(statement, index)))
    }
}
