import Foundation
import SQLite3

/// Aside persists mutable turn aggregates, not append-only usage events, and `ON DELETE
/// CASCADE` removes a session's turns outright when the user deletes the session. The
/// `.aside` case in `LocalAdditionalUsageCache` therefore merges each scan with the
/// previously-seen entries (`dedupKeepMax(existing + loaded)`), exactly like Kiro: a
/// deleted session stays counted until the scan cache is dropped (Settings save, month
/// rollover, relaunch), after which the rescan is the truth.
/// Only usage metadata is selected; conversation bodies and credentials are never read.
///
/// Failure mapping (see `provider-extension.md`): this reader never throws. A database
/// that cannot be opened or queried is skipped, so the scan returns whatever the healthy
/// ones held — and after the first successful scan, an all-failed rescan returns `[]`,
/// which the keep-max merge treats as "nothing new" rather than "zero usage".
enum LocalAsideUsageReader {
    static func roots(customRootsValue: String? = nil,
                      home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        CustomScanRoots.union(defaults: [home.appendingPathComponent(".aside/u")], extraRaw: customRootsValue)
    }

    /// Root folders may be `.aside/u` or individual user folders containing state.db.
    static func databases(roots: [URL]) -> [URL] {
        let fm = FileManager.default
        var found = Set<URL>()
        for root in roots {
            let children = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
            for directory in [root] + children {
                let db = directory.appendingPathComponent("state.db").resolvingSymlinksInPath().standardizedFileURL
                if fm.fileExists(atPath: db.path) { found.insert(db) }
            }
        }
        return found.sorted { $0.path < $1.path }
    }

    /// A database that cannot be opened or queried (an unmigrated second profile, a foreign
    /// state.db under a custom root, a busy WAL recovery) is skipped so it never blanks out
    /// the healthy ones. A scan that fails after yielding rows discards that database's
    /// partial rows.
    static func entries(modifiedSince since: Date, roots: [URL]? = nil) -> [LocalUsageReader.Entry] {
        let databases = databases(roots: roots ?? self.roots(customRootsValue: CustomScanRoots.storedValue(for: "aside")))
        var result: [LocalUsageReader.Entry] = []
        var skipped: [String] = []
        let fmt = LocalUsageReader.localDayFormatter()
        for url in databases {
            var db: OpaquePointer?
            guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
                sqlite3_close(db)
                skipped.append(url.path)
                continue
            }
            defer { sqlite3_close(db) }
            sqlite3_busy_timeout(db, 1000)
            // Entry ids carry the file's inode: a recreated state.db (profile removed and
            // re-created) restarts AUTOINCREMENT at 1, and without the inode its new rows would
            // share ids with the cached pre-reset turns and hide behind them in the keep-max merge.
            let store = "aside|\(url.path)#\(inode(of: url.path))"
            var statement: OpaquePointer?
            // Turns run for a long time and `token_usage` grows while they run, so a turn is
            // anchored on its last activity rather than `started_at`; tokens then land in the
            // day / 5-hour block they were actually generated in.
            let query = """
                SELECT t.id, t.token_usage, COALESCE(t.finished_at, t.last_message_timestamp), s.model
                FROM session_turns t LEFT JOIN sessions s ON s.id = t.session_id
                WHERE COALESCE(t.finished_at, t.last_message_timestamp) >= ?
                """
            guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
                skipped.append(url.path)
                continue
            }
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_double(statement, 1, since.timeIntervalSince1970)
            var rows: [LocalUsageReader.Entry] = []
            var status = sqlite3_step(statement)
            while status == SQLITE_ROW {
                if let text = sqlite3_column_text(statement, 1),
                   let usage = try? JSONSerialization.jsonObject(with: Data(String(cString: text).utf8)) as? [String: Any] {
                    let date = Date(timeIntervalSince1970: sqlite3_column_double(statement, 2))
                    // The schema has no per-turn model: `sessions.model` is the session's *current*
                    // setting. Never price historical turns using that current model; only
                    // a source-recorded cost is usable for these aggregates.
                    var model = "aside"
                    if let text = sqlite3_column_text(statement, 3),
                       let metadata = try? JSONSerialization.jsonObject(with: Data(String(cString: text).utf8)) as? [String: Any],
                       let modelID = metadata["modelId"] as? String { model = modelID }
                    let cost = (usage["cost"] as? [String: Any])?["total"] as? Double
                    let hasBuckets = ["input", "output", "cacheRead", "cacheWrite"].contains { usage[$0] is NSNumber }
                    let input = tokens(hasBuckets ? usage["input"] : usage["totalTokens"])
                    let output = tokens(usage["output"])
                    let cacheWrite = tokens(usage["cacheWrite"])
                    let cacheRead = tokens(usage["cacheRead"])
                    // Zero-token turns (aborted before a response) are not usage; recording them
                    // would surface an empty active block and an Aside tab with nothing in it.
                    if input + output + cacheWrite + cacheRead > 0 {
                        rows.append(.init(
                            id: "\(store):\(sqlite3_column_int64(statement, 0))",
                            date: date, localDay: fmt.string(from: date), model: model,
                            input: input, output: output, cacheWrite: cacheWrite, cacheRead: cacheRead,
                            explicitCost: cost, costUnavailable: true))
                    }
                }
                status = sqlite3_step(statement)
            }
            guard status == SQLITE_DONE else {
                skipped.append(url.path)
                continue
            }
            result.append(contentsOf: rows)
        }
        if !skipped.isEmpty {
            AppLog.write("aside: skipped unreadable state.db: \(skipped.joined(separator: ", "))")
        }
        return result
    }

    private static func inode(of path: String) -> UInt64 {
        var info = stat()
        return stat(path, &info) == 0 ? UInt64(info.st_ino) : 0
    }

    private static func tokens(_ value: Any?) -> Int {
        guard let number = value as? NSNumber else { return 0 }
        let value = number.doubleValue
        guard value.isFinite, value > 0 else { return 0 }
        return Int(min(value, Double(LocalUsageReader.maxParsedTokenValue)))
    }
}
