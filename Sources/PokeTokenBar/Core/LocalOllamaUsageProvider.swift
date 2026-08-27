import Foundation

/// Usage captured by the transparent local Ollama proxy.
///
/// Ollama returns exact prompt/completion counts in the final response object, but it does
/// not persist a usage ledger. The companion proxy writes those response counts as JSONL
/// under `~/.ollama/usage`; this provider keeps PokeTokenBar decoupled from the proxy itself
/// and treats that ledger like every other local usage source.
struct LocalOllamaProvider: UsageProvider {
    let id = "ollama"
    let displayName = "Ollama"
    let reportsCost = false

    func fetchDaily() async throws -> DailyUsage? {
        let entries = LocalOllamaUsageReader.entries(
            modifiedSince: Calendar.current.startOfDay(for: Date()))
        return LocalUsageReader.daily(entries: entries, localDay: LocalUsageReader.todayKey())
    }

    func fetchEnrichment() async -> ProviderEnrichment {
        let now = Date()
        let entries = LocalOllamaUsageReader.entries(
            modifiedSince: LocalUsageReader.enrichmentScanStart(now: now))
        let formatter = LocalUsageReader.localDayFormatter()
        let weekStart = LocalUsageReader.startOfWeek(now)
        let monthStart = LocalUsageReader.startOfMonth(now)
        var result = ProviderEnrichment()
        result.activeBlock = LocalUsageReader.activeBlock(entries: entries, now: now)
        result.blocksOK = true
        result.weekTotal = LocalUsageReader.period(
            entries: entries,
            periodKey: formatter.string(from: weekStart),
            fromDay: formatter.string(from: weekStart),
            toDay: formatter.string(from: now))
        result.monthTotal = LocalUsageReader.period(
            entries: entries,
            periodKey: LocalUsageReader.monthKey(now),
            fromDay: formatter.string(from: monthStart),
            toDay: formatter.string(from: now))
        result.periodsOK = true
        return result
    }
}

enum LocalOllamaUsageReader {
    static var defaultRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ollama/usage", isDirectory: true)
    }

    static func roots(customRootsValue: String? = CustomScanRoots.storedValue(for: "ollama")) -> [URL] {
        CustomScanRoots.union(defaults: [defaultRoot], extraRaw: customRootsValue)
    }

    static func entries(modifiedSince: Date, roots: [URL]? = nil) -> [LocalUsageReader.Entry] {
        let formatter = LocalUsageReader.localDayFormatter()
        let minimumDay = formatter.string(from: modifiedSince)
        var entries: [LocalUsageReader.Entry] = []
        for root in roots ?? self.roots() {
            for file in usageFiles(root: root, minimumDay: minimumDay) {
                forEachLine(in: file) { lineNumber, line in
                    if let entry = parse(line: line, file: file.path, lineNumber: lineNumber,
                                         formatter: formatter),
                       entry.date >= modifiedSince {
                        entries.append(entry)
                    }
                }
            }
        }
        return entries
    }

    private static func usageFiles(root: URL, minimumDay: String) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var files: [URL] = []
        for case let url as URL in enumerator where url.pathExtension.lowercased() == "jsonl" {
            // The proxy names files by local day, so old files can be rejected before reading.
            let day = url.deletingPathExtension().lastPathComponent
            if day >= minimumDay { files.append(url) }
        }
        return files.sorted { $0.path < $1.path }
    }

    static func parse(
        line: Data, file: String, lineNumber: Int, formatter: DateFormatter
    ) -> LocalUsageReader.Entry? {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let timestamp = object["ts"] as? String,
              let date = ISO8601Parser.date(from: timestamp) else { return nil }
        let prompt = tokenValue(object["prompt_tokens"])
        let completion = tokenValue(object["completion_tokens"])
        let reportedTotal = tokenValue(object["total_tokens"])
        let partsTotal = safeAdd(prompt, completion)
        let total = max(partsTotal, reportedTotal)
        guard total > 0 else { return nil }

        // Retain a writer-reported total even if a future Ollama response adds a token class.
        let output = safeAdd(completion, max(0, total - partsTotal))
        return LocalUsageReader.Entry(
            id: "ollama|\(file)|\(lineNumber)",
            date: date,
            localDay: formatter.string(from: date),
            model: (object["model"] as? String) ?? "ollama",
            input: prompt,
            output: output,
            cacheWrite: 0,
            cacheRead: 0)
    }

    private static let maximumTokenValue = 1_000_000_000_000_000

    private static func tokenValue(_ value: Any?) -> Int {
        guard !(value is NSNull) else { return 0 }
        let number: Double
        if let value = value as? NSNumber { number = value.doubleValue }
        else if let value = value as? String, let parsed = Double(value) { number = parsed }
        else { return 0 }
        guard number.isFinite, number > 0 else { return 0 }
        return number >= Double(maximumTokenValue) ? maximumTokenValue : Int(number)
    }

    private static func safeAdd(_ lhs: Int, _ rhs: Int) -> Int {
        lhs > maximumTokenValue - rhs ? maximumTokenValue : lhs + rhs
    }

    /// Stream unbounded JSONL files so a long-running Ollama installation cannot make the
    /// menu-bar process mirror the entire ledger in memory.
    private static func forEachLine(in url: URL, body: (Int, Data) -> Void) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }
        var pending = Data()
        var lineNumber = 0
        while true {
            let chunk = autoreleasepool { try? handle.read(upToCount: 64 * 1024) }
            guard let chunk, !chunk.isEmpty else { break }
            pending.append(chunk)
            while let newline = pending.firstIndex(of: 0x0A) {
                let line = Data(pending[..<newline])
                pending.removeSubrange(...newline)
                lineNumber += 1
                autoreleasepool { body(lineNumber, line) }
            }
        }
        if !pending.isEmpty {
            lineNumber += 1
            autoreleasepool { body(lineNumber, pending) }
        }
    }
}
