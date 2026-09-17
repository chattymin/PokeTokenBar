import Foundation

/// Tokens and cost of one Claude account, today and over the current month.
struct ClaudeAccountUsage: Sendable, Equatable {
    var todayTokens = 0
    var todayCost = UsageCost()
    var monthTokens = 0
    var monthCost = UsageCost()

    var isEmpty: Bool { monthTokens == 0 && todayTokens == 0 }

    mutating func add(_ other: ClaudeAccountUsage) {
        todayTokens += other.todayTokens
        todayCost.add(other.todayCost)
        monthTokens += other.monthTokens
        monthCost.add(other.monthCost)
    }
}

/// Splits local Claude usage between accounts.
///
/// Transcripts carry no account, and `projects/` may be shared between logins. Each login's own
/// `history.jsonl` does list its prompts, with their session and time. A turn belongs to the login
/// that sent the latest prompt of its session before it, so a session resumed from another login
/// changes owner at that point. Turns of sessions no history mentions (print mode, SDK runs, sessions
/// older than the history) stay unattributed rather than guessed.
enum ClaudeAccountUsageAttribution {
    /// Prompt times per session for one login, ascending.
    typealias Prompts = [String: [Date]]

    struct Account: Sendable {
        let id: String
        let prompts: Prompts
    }

    /// An account's official 5h window, as its limits report it.
    enum FiveHourWindow: Sendable, Equatable {
        case running(reset: Date)
        case notStarted
    }

    /// Accounts are checked in order; on equal times the first one wins.
    static func owner(session: String, at date: Date, accounts: [Account]) -> String? {
        var latest: (id: String, date: Date)?
        var earliest: (id: String, date: Date)?
        for account in accounts {
            guard let times = account.prompts[session], let first = times.first else { continue }
            if let before = times.last(where: { $0 <= date }), latest.map({ before > $0.date }) ?? true {
                latest = (account.id, before)
            }
            if earliest.map({ first < $0.date }) ?? true {
                earliest = (account.id, first)
            }
        }
        // A turn logged before any prompt of its session (clock skew) goes to the login that started it.
        return latest?.id ?? earliest?.id
    }

    /// `activeBlocks` holds each account's own 5h block, for its tab and forecast: the machine-wide block
    /// would mix another account's burn into it. With an official window (`fiveHourWindows`), the block
    /// counts that window's turns and ends at its reset; without one, it is the rolling local block.
    static func usage(
        entries: [LocalUsageReader.Entry], accounts: [Account], now: Date, todayKey: String, monthStartKey: String,
        fiveHourWindows: [String: FiveHourWindow] = [:]
    ) -> (byAccount: [String: ClaudeAccountUsage], unattributed: ClaudeAccountUsage,
          activeBlocks: [String: BlockUsage]) {
        // Account ids are never empty, so "" collects the unattributed turns.
        let unattributed = ""
        let blockStart = now.addingTimeInterval(-LocalUsageReader.blockWindow)
        var today: [String: LocalUsageReader.Bucket] = [:]
        var month: [String: LocalUsageReader.Bucket] = [:]
        var recent: [String: [LocalUsageReader.Entry]] = [:]
        for entry in entries {
            let inMonth = entry.localDay >= monthStartKey && entry.localDay <= todayKey
            // A block started before the month began still counts.
            let inBlock = entry.date >= blockStart
            guard inMonth || inBlock else { continue }
            let key = entry.sessionID.flatMap { owner(session: $0, at: entry.date, accounts: accounts) } ?? unattributed
            if inBlock, key != unattributed { recent[key, default: []].append(entry) }
            guard inMonth else { continue }
            month[key, default: LocalUsageReader.Bucket()].add(entry)
            if entry.localDay == todayKey {
                today[key, default: LocalUsageReader.Bucket()].add(entry)
            }
        }
        func usage(_ key: String) -> ClaudeAccountUsage {
            let day = today[key] ?? LocalUsageReader.Bucket()
            let period = month[key] ?? LocalUsageReader.Bucket()
            return ClaudeAccountUsage(
                todayTokens: day.total, todayCost: UsageCost(amount: day.cost, coverage: day.costCoverage),
                monthTokens: period.total, monthCost: UsageCost(amount: period.cost, coverage: period.costCoverage))
        }
        var byAccount: [String: ClaudeAccountUsage] = [:]
        for id in month.keys where id != unattributed { byAccount[id] = usage(id) }
        var activeBlocks: [String: BlockUsage] = [:]
        for (id, turns) in recent {
            switch fiveHourWindows[id] {
            case .running(let reset) where reset > now:
                let start = reset.addingTimeInterval(-LocalUsageReader.blockWindow)
                guard var block = LocalUsageReader.activeBlock(entries: turns.filter { $0.date >= start }, now: now)
                else { continue }
                block.endTime = ISO8601DateFormatter().string(from: reset)
                activeBlocks[id] = block
            case .running, .notStarted:
                // No session runs: these turns belong to a window that is over.
                continue
            case nil:
                activeBlocks[id] = LocalUsageReader.activeBlock(entries: turns, now: now)
            }
        }
        return (byAccount, usage(unattributed), activeBlocks)
    }
}

/// Reads `<config folder>/history.jsonl` (one prompt per line: `sessionId`, `timestamp` in ms).
/// The prompt text itself is never kept.
enum ClaudePromptHistory {
    static func prompts(configDir: URL) -> ClaudeAccountUsageAttribution.Prompts {
        cache.prompts(for: configDir.appendingPathComponent("history.jsonl"))
    }

    /// App only, like `ClaudeAccountRoots.installedDiscovery`.
    static func installedPrompts(configDir: URL, isBundledApp: Bool = AppEnv.isBundledApp) -> ClaudeAccountUsageAttribution.Prompts {
        isBundledApp ? prompts(configDir: configDir) : [:]
    }

    static func parse(_ text: String) -> ClaudeAccountUsageAttribution.Prompts {
        var out: ClaudeAccountUsageAttribution.Prompts = [:]
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) where line.contains("\"sessionId\"") {
            autoreleasepool {
                guard let data = line.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let session = obj["sessionId"] as? String, !session.isEmpty,
                      let date = promptDate(obj["timestamp"]) else { return }
                out[session, default: []].append(date)
            }
        }
        for session in out.keys { out[session]?.sort() }
        return out
    }

    private static func promptDate(_ raw: Any?) -> Date? {
        if let number = raw as? NSNumber, number.doubleValue > 0 {
            return Date(timeIntervalSince1970: number.doubleValue / 1000)
        }
        if let text = raw as? String { return ISO8601Parser.date(from: text) }
        return nil
    }

    private static let cache = FileCache()

    /// Claude Code only appends to the history: after the first read, only the new lines are parsed.
    final class FileCache: @unchecked Sendable {
        private struct Parsed {
            let mtime: Date
            let size: Int
            /// Bytes parsed so far, always at a line end: a line still being written is read next time.
            let offset: UInt64
            let prompts: ClaudeAccountUsageAttribution.Prompts
        }

        private let lock = NSLock()
        private var parsed: [String: Parsed] = [:]

        func prompts(for file: URL) -> ClaudeAccountUsageAttribution.Prompts {
            guard let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                  let mtime = values.contentModificationDate else { return [:] }
            let size = values.fileSize ?? 0
            lock.lock()
            let hit = parsed[file.path]
            lock.unlock()
            if let hit, hit.mtime == mtime, hit.size == size { return hit.prompts }
            guard let handle = try? FileHandle(forReadingFrom: file) else { return [:] }
            defer { try? handle.close() }
            // Resume only where the previous read ended on a line break; anything else is a rewrite.
            var base = hit
            if let previous = base {
                let resumes = previous.offset > 0 && previous.offset <= UInt64(size)
                    && (try? handle.seek(toOffset: previous.offset - 1)) != nil
                    && (try? handle.read(upToCount: 1)) == Data([0x0A])
                if !resumes { base = nil }
            }
            let start = base?.offset ?? 0
            guard (try? handle.seek(toOffset: start)) != nil,
                  let data = try? handle.readToEnd() ?? Data() else { return base?.prompts ?? [:] }
            let complete = data.lastIndex(of: 0x0A).map { data[data.startIndex...$0] } ?? Data()
            var prompts = base?.prompts ?? [:]
            for (session, dates) in ClaudePromptHistory.parse(String(decoding: complete, as: UTF8.self)) {
                prompts[session, default: []].append(contentsOf: dates)
                prompts[session]?.sort()
            }
            lock.lock()
            parsed[file.path] = Parsed(mtime: mtime, size: size, offset: start + UInt64(complete.count),
                                       prompts: prompts)
            lock.unlock()
            return prompts
        }
    }
}
