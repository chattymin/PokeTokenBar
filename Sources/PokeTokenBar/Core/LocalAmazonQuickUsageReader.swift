import Foundation
import SQLite3

/// Amazon Quick (Quick Suite) usage from its local `sessions.db` SQLite database.
///
/// Quick is Amazon's desktop AI assistant (macOS/Windows). It persists every session under
/// `~/.quickwork/profiles/<profile>/sessions/sessions.db` (enterprise/team installs) and
/// `~/.quickwork/sessions/sessions.db` (single-profile installs). A single database holds
/// *all* of that profile's sessions — the `session_events.session_id` column separates them,
/// so multi-session totals are the natural sum of every event, no per-session file scanning.
///
/// Real token counts are recorded, unlike Kiro's byte estimate: each assistant turn writes a
/// `message_assistant_complete` event whose `data` JSON carries a `token_usage` object with
/// `input_tokens` / `output_tokens` / `cache_read_tokens` / `cache_write_tokens`. The event's
/// `id` is unique and stable, so re-scans are idempotent under `dedupKeepMax`.
///
/// Events are append-only in practice, but a session can be deleted (its events go with it),
/// so the `.amazonquick` case in `LocalAdditionalUsageCache` merges each scan with the
/// previously-seen entries — exactly like Kiro/Aside: a deleted session stays counted until
/// the scan cache resets (Settings save, month rollover, relaunch), after which the rescan is
/// the truth.
///
/// Only usage metadata is selected (event id, timestamp, `token_usage`, model). Conversation
/// bodies (`full_content`, `session_messages.content`) and credentials are never read.
///
/// Failure mapping (see `provider-extension.md`): this reader never throws. A database that
/// cannot be opened or queried is skipped, so the scan returns whatever the healthy ones held;
/// after the first successful scan, an all-failed rescan returns `[]`, which the keep-max merge
/// treats as "nothing new" rather than "zero usage".
enum LocalAmazonQuickUsageReader {

    /// `QUICKWORK_HOME` overrides the base directory (comma-separated for multiple installs);
    /// otherwise `~/.quickwork`. Custom scan roots from Settings are unioned on top.
    static func roots(customRootsValue: String? = nil,
                      home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        let bases = environmentPaths("QUICKWORK_HOME")
            ?? [home.appendingPathComponent(".quickwork")]
        return CustomScanRoots.union(defaults: bases, extraRaw: customRootsValue)
    }

    /// Every `sessions.db` reachable from the given roots.
    ///
    /// A root may be:
    ///   - a `.quickwork` base (default) → scan `sessions/sessions.db` and
    ///     `profiles/<profile>/sessions/sessions.db`,
    ///   - a `profiles` or `<profile>` folder (custom root) → scan `sessions/sessions.db`,
    ///   - a `sessions` folder or a direct `sessions.db` path.
    /// Paths are de-duplicated by resolved path so overlapping custom roots never double-count.
    static func databases(roots: [URL]) -> [URL] {
        let fm = FileManager.default
        var found = Set<URL>()

        func addIfExists(_ url: URL) {
            let resolved = url.resolvingSymlinksInPath().standardizedFileURL
            if fm.fileExists(atPath: resolved.path) { found.insert(resolved) }
        }

        for root in roots {
            // Direct sessions.db path.
            if root.lastPathComponent == "sessions.db" {
                addIfExists(root)
                continue
            }
            // <root>/sessions/sessions.db  (a .quickwork base or a single profile folder)
            addIfExists(root.appendingPathComponent("sessions/sessions.db"))
            // <root>/sessions.db          (root already points at a sessions folder)
            addIfExists(root.appendingPathComponent("sessions.db"))
            // <root>/profiles/<profile>/sessions/sessions.db  (enterprise/team installs)
            let profilesDir = root.appendingPathComponent("profiles")
            let profiles = (try? fm.contentsOfDirectory(
                at: profilesDir, includingPropertiesForKeys: nil)) ?? []
            for profile in profiles {
                addIfExists(profile.appendingPathComponent("sessions/sessions.db"))
            }
        }
        return found.sorted { $0.path < $1.path }
    }

    static func entries(modifiedSince since: Date, roots: [URL]? = nil) -> [LocalUsageReader.Entry] {
        let databases = databases(
            roots: roots ?? self.roots(customRootsValue: CustomScanRoots.storedValue(for: "amazonquick")))
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

            // Entry ids carry the file's inode: a re-created profile restarts its rowids, and
            // without the inode its fresh events could collide with cached pre-reset ids and
            // hide behind them in the keep-max merge.
            let store = "amazonquick|\(url.path)#\(inode(of: url.path))"

            var statement: OpaquePointer?
            // Only completed assistant turns carry a settled `token_usage`. `timestamp` is the
            // turn's completion time, so tokens land in the day / 5-hour block they were
            // generated in. Bind the lower bound so we read only rows newer than the watermark.
            let query = """
                SELECT id, data, timestamp
                FROM session_events
                WHERE type = 'message_assistant_complete'
                  AND timestamp >= ?
                  AND data LIKE '%token_usage%'
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
                if let eventID = sqlite3_column_text(statement, 0),
                   let dataText = sqlite3_column_text(statement, 1),
                   let json = try? JSONSerialization.jsonObject(
                       with: Data(String(cString: dataText).utf8)) as? [String: Any],
                   let usage = json["token_usage"] as? [String: Any] {
                    let date = Date(timeIntervalSince1970: sqlite3_column_double(statement, 2))
                    // Quick reports its plan-mode label (e.g. "balanced") as the model. There is
                    // no public price table for it, so cost is marked unavailable rather than
                    // priced against an unrelated model.
                    let model = (usage["model"] as? String) ?? "amazon_quick"
                    let input = tokens(usage["input_tokens"])
                    let output = tokens(usage["output_tokens"])
                    let cacheRead = tokens(usage["cache_read_tokens"])
                    let cacheWrite = tokens(usage["cache_write_tokens"])
                    // Aborted turns (no tokens) are not usage; recording them would surface an
                    // empty active block and a Quick tab with nothing in it.
                    if input + output + cacheRead + cacheWrite > 0 {
                        rows.append(.init(
                            id: "\(store):\(String(cString: eventID))",
                            date: date, localDay: fmt.string(from: date), model: model,
                            input: input, output: output, cacheWrite: cacheWrite, cacheRead: cacheRead,
                            costUnavailable: true))
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
            AppLog.write("amazonquick: skipped unreadable sessions.db: \(skipped.joined(separator: ", "))")
        }
        return result
    }

    /// `QUICKWORK_HOME` comma-separated → URLs, or nil when unset.
    private static func environmentPaths(_ key: String) -> [URL]? {
        guard let raw = UsageEnvironment.value(key) else { return nil }
        let urls = raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map(URL.init(fileURLWithPath:))
        return urls.isEmpty ? nil : urls
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
