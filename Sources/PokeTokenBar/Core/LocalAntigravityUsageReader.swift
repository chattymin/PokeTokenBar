import Foundation
import SQLite3

/// Antigravity usage, read from the conversation stores written under
/// `~/.gemini/antigravity/conversations/<conversation>.db`,
/// `~/.gemini/antigravity-cli/conversations/<conversation>.db`, or
/// `~/.gemini/antigravity-ide/conversations/<conversation>.db`.
///
/// Antigravity shares the `~/.gemini/` parent directory with Gemini CLI and nothing else.
/// Where Gemini CLI appends JSON lines, Antigravity keeps one SQLite database per
/// conversation and stores the per-call token ledger inside a protobuf blob, so the
/// existing Gemini file scan never sees any of it.
///
/// The field numbers below are the writer's own contract: the CLI binary embeds its
/// `FileDescriptorProto` pool, and these names and numbers were read out of it rather than
/// inferred from sample values. Two of the fields are shaped so that guessing would have
/// been wrong — `input_tokens` excludes cache reads (the opposite of Gemini's
/// `promptTokenCount`), and `output_tokens` is already the sum of its two siblings.
///
///     gen_metadata.data              exa.cortex_pb.CortexStepGeneratorMetadata
///       1     chat_model               exa.cortex_pb.ChatModelMetadata
///       1.4     usage                  exa.codeium_common_pb.ModelUsageStats
///       1.4.2     input_tokens         prompt tokens, cache reads NOT included
///       1.4.3     output_tokens        thinking_output_tokens + response_output_tokens
///       1.4.4     cache_write_tokens   declared, never written by this CLI
///       1.4.5     cache_read_tokens    prompt cache hit
///       1.4.11    response_id          globally unique per call
///       1.9     chat_start_metadata    exa.cortex_pb.ChatStartMetadata
///       1.9.4     created_at           google.protobuf.Timestamp, absent since Antigravity 2.0
///       1.19    response_model         e.g. "gemini-3.6-flash"
///       4       execution_id           the execution these tokens were spent in
///
/// Records written by Antigravity 2.0 carry `chat_start_metadata` with `created_at` removed, and
/// nothing else in the blob is a time. The date for those comes from the `steps` table of the
/// same store, whose `metadata` is an `exa.cortex_pb.StepMetadata`:
///
///     steps.metadata          exa.cortex_pb.StepMetadata
///       1     created_at        google.protobuf.Timestamp — when the step was queued
///       8     finished_at       google.protobuf.Timestamp — absent while the step is running
///       12    execution_id      matches `gen_metadata.data` field 4
///
/// The join is on `execution_id`, not on `idx`: `gen_metadata.idx` is its own dense sequence and
/// drifts from `steps.idx` by minutes within a single conversation. Against the stores that still
/// carry `created_at`, dating each record from the step timings of its own execution lands within
/// ~2 minutes of the writer's own value, where the store's mtime — one value for every record it
/// holds — moves a conversation's earlier days onto the day it was last written.
///
/// There is no total field anywhere in the schema, so the total is the sum of the three
/// populated counters — which is exactly the identity `LocalUsageReader.Entry` already keeps.
enum LocalAntigravityUsageReader {

    /// Known conversation directories across Antigravity editions (2.0/Core, CLI, IDE).
    /// The directory is absent unless the respective Antigravity flavor ran.
    static func defaultRoots(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [URL] {
        [
            home.appendingPathComponent(".gemini/antigravity/conversations"),
            home.appendingPathComponent(".gemini/antigravity-cli/conversations"),
            home.appendingPathComponent(".gemini/antigravity-ide/conversations"),
        ]
    }

    static var defaultRoots: [URL] { defaultRoots() }

    /// Primary default directory for single-root callers and backwards compatibility.
    static var defaultRoot: URL {
        defaultRoots[0]
    }

    static func resolvedRoots(
        customRootsValue: String? = nil,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [URL] {
        CustomScanRoots.union(
            defaults: defaultRoots(home: home),
            extraRaw: customRootsValue)
    }

    /// Usage rows whose `created_at` falls at or after `modifiedSince`.
    static func entries(modifiedSince: Date, roots: [URL]? = nil) -> [LocalUsageReader.Entry] {
        let scanned = scan(
            roots: roots ?? resolvedRoots(
                customRootsValue: CustomScanRoots.storedValue(for: "antigravity")),
            modifiedSince: modifiedSince, known: [:])
        // The one place the side effects live. `AppLog.write` returns early outside the bundled
        // app, so the decisions above it are kept pure and tested on their own.
        for line in scanned.log { AppLog.write(line) }
        return assemble(scanned.blobs, since: modifiedSince)
    }

    /// Single-root overload for backwards compatibility and tests.
    static func entries(modifiedSince: Date, root: URL?) -> [LocalUsageReader.Entry] {
        entries(
            modifiedSince: modifiedSince,
            roots: root.map { [$0] } ?? resolvedRoots(
                customRootsValue: CustomScanRoots.storedValue(for: "antigravity")))
    }

    /// One conversation store's rows, valid for as long as its `(mtime, size)` hold. The rows
    /// are deliberately *unfiltered*: the window is applied after the lookup, so one blob serves
    /// both the daily call and the enrichment call — the contract `LocalUsageCache.Blob` keeps,
    /// and the reason a blob cache needs no time-based expiry.
    struct Blob: Sendable {
        let mtime: Date
        let size: Int
        let entries: [LocalUsageReader.Entry]
    }

    /// What one sweep produced: the surviving blobs keyed by path, and the lines it left behind.
    struct Scan: Sendable {
        var blobs: [String: Blob]
        var log: [String]
    }

    /// Rows from every blob, narrowed to the window and deduplicated. `response_id` is unique
    /// per call, so the dedup only ever collapses the same turn copied into a second store.
    static func assemble(_ blobs: [String: Blob], since: Date) -> [LocalUsageReader.Entry] {
        LocalUsageReader.dedupKeepMax(blobs.values.flatMap(\.entries).filter { $0.date >= since })
    }

    /// Reads every conversation store the window admits across roots, reusing any blob in `known`
    /// whose signature still matches. `known` is empty for a one-shot read.
    static func scan(roots: [URL], modifiedSince: Date, known: [String: Blob]) -> Scan {
        let formatter = LocalUsageReader.localDayFormatter()
        var blobs: [String: Blob] = [:]
        var reads: [(conversation: String, read: ConversationRead)] = []

        for database in databases(in: roots) {
            // Stat before the read, never after. A commit that lands mid-read then differs from
            // the stored signature on the next sweep and is re-read; stat afterwards and that
            // same commit is frozen into a signature that already looks current.
            guard let signature = signature(of: database), signature.mtime >= modifiedSince else { continue }
            let key = database.path
            if let blob = known[key], blob.mtime == signature.mtime, blob.size == signature.size {
                blobs[key] = blob
                continue
            }

            let read = conversationEntries(database, formatter: formatter)
            reads.append((database.deletingPathExtension().lastPathComponent, read))
            switch read {
            case .complete(let entries, _):
                blobs[key] = Blob(mtime: signature.mtime, size: signature.size, entries: entries)
            case .notAConversation:
                // A permanent property of the file, so cache the empty — otherwise every
                // database in the directory that is not a conversation store is reopened on
                // every refresh for the life of the install.
                blobs[key] = Blob(mtime: signature.mtime, size: signature.size, entries: [])
            case .incompleteScan, .unreadable:
                // Never write an empty blob under a signature that may never change again: the
                // store would read as no usage for as long as it sat still, and the retry the
                // discard was for would never happen. Carry the previous rows forward under
                // their *old* signature so the next sweep tries again.
                if let stale = known[key] { blobs[key] = stale }
            }
        }
        return Scan(blobs: blobs, log: lossLog(reads) + discardLog(reads))
    }

    /// Single-root scan overload.
    static func scan(root: URL, modifiedSince: Date, known: [String: Blob]) -> Scan {
        scan(roots: [root], modifiedSince: modifiedSince, known: known)
    }

    // MARK: Database discovery

    /// The cache key for one conversation store, and the same value the scan window is tested
    /// against. A WAL commit lands in the `-wal` sibling and leaves the main file's timestamp
    /// and length alone, so keying on the `.db` would miss precisely the stores that had just
    /// moved.
    ///
    /// `-shm` is deliberately excluded. It carries no committed data — it is a rebuildable index
    /// over `-wal` — and a read-only WAL connection writes read marks into it, so including it
    /// would let this reader invalidate the blob it had just written, on every sweep, forever.
    /// For the same reason it adds nothing to the window test: a `-shm` that is newer than both
    /// of the others means somebody read the store, not that anything was written to it.
    static func signature(of database: URL) -> (mtime: Date, size: Int)? {
        let manager = FileManager.default
        var newest: Date?
        var size = 0
        for path in [database.path, database.path + "-wal"] {
            guard let attributes = try? manager.attributesOfItem(atPath: path) else { continue }
            if let mtime = attributes[.modificationDate] as? Date {
                newest = max(newest ?? mtime, mtime)
            }
            size += (attributes[.size] as? Int) ?? 0
        }
        return newest.map { ($0, size) }
    }

    private static func databases(in roots: [URL]) -> [URL] {
        var results: [URL] = []
        for root in roots {
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: root.path) else { continue }
            results.append(contentsOf: names.filter { $0.hasSuffix(".db") }.sorted().map { root.appendingPathComponent($0) })
        }
        return results
    }

    private static func databases(in root: URL) -> [URL] {
        databases(in: [root])
    }

    // MARK: Reading one conversation

    /// What one conversation store yielded. Three of these four produce no rows, and only one
    /// of those three is a fact about the user's usage — collapsing them all to `[]`, which is
    /// what this reader used to do, is what let a store that could never be read pass for a
    /// store that was never used.
    enum ConversationRead: Sendable {
        /// Read through to `SQLITE_DONE`: these rows are all of them. `discardedCounters` is how
        /// many token fields across those rows carried a value too large to be a count.
        case complete(entries: [LocalUsageReader.Entry], discardedCounters: Int)
        /// The scan stopped early — BUSY because the CLI was writing, or a damaged page. Half a
        /// conversation must not pass for the whole of it, so the rows read so far are dropped.
        case incompleteScan(status: Int32, rows: Int)
        /// Neither `mode=ro` nor `immutable=1` could open it, or the query failed for a reason
        /// other than the table being absent.
        case unreadable(status: Int32?)
        /// No `gen_metadata`: this file is not a conversation store. A permanent, legitimate
        /// empty — the candidate directories may hold databases we don't read.
        case notAConversation

        var entries: [LocalUsageReader.Entry] {
            if case .complete(let entries, _) = self { return entries }
            return []
        }
    }

    /// At most this many stores are named per scan; the rest are counted. A store that cannot be
    /// read is re-read on every refresh (720 times a day at the default interval), so one line
    /// per store per scan could rotate `AppLog`'s 2 MB file — and the crash-diagnostic history
    /// with it — several times a day on a machine whose conversation directory went bad.
    static let namedLossLimit = 5

    /// The lines one scan leaves behind. Pure on purpose: `AppLog.write` returns early outside
    /// the bundled app (`AppEnv.isBundledApp`), so a test that watched the log file would cover
    /// nothing at all — the same reason the limit-alert decision was split out of its own
    /// side effect.
    static func lossLog(_ reads: [(conversation: String, read: ConversationRead)]) -> [String] {
        capped(reads.compactMap { entry -> String? in
            switch entry.read {
            case .complete, .notAConversation:
                return nil
            case .incompleteScan(let status, let rows):
                return "antigravity: lost conversation=\(entry.conversation)"
                    + " reason=scan-incomplete status=\(status) rows=\(rows)"
            case .unreadable(let status):
                return "antigravity: lost conversation=\(entry.conversation) reason=unreadable"
                    + (status.map { " status=\($0)" } ?? "")
            }
        }) { total, hidden in
            "antigravity: lost \(total) conversation(s) this scan (\(hidden) not named)"
        }
    }

    /// Token counters dropped for being too large to be counts, totalled per store. Reporting
    /// them where they happen would be up to four lines per record — tens of thousands from one
    /// scan of a live store — and the point of the ceiling is that this is rare enough to notice.
    static func discardLog(_ reads: [(conversation: String, read: ConversationRead)]) -> [String] {
        capped(reads.compactMap { entry -> String? in
            guard case .complete(_, let discarded) = entry.read, discarded > 0 else { return nil }
            return "antigravity: conversation=\(entry.conversation) discarded=\(discarded)"
                + " token counter(s) over \(AntigravityProto.tokenCeiling)"
        }) { total, hidden in
            "antigravity: discarded token counters in \(total) conversation(s) (\(hidden) not named)"
        }
    }

    private static func capped(_ lines: [String], summary: (Int, Int) -> String) -> [String] {
        guard lines.count > namedLossLimit else { return lines }
        return Array(lines.prefix(namedLossLimit))
            + [summary(lines.count, lines.count - namedLossLimit)]
    }

    /// Reads every row in the store. The window is *not* applied here: these rows go into a
    /// blob that outlives the call that produced it, and a cutoff baked into a cached unit is
    /// wrong the moment the window moves.
    static func conversationEntries(
        _ database: URL,
        formatter: DateFormatter
    ) -> ConversationRead {
        guard let handle = openReadOnly(database) else { return .unreadable(status: nil) }
        // `_v2` because the guarantee this needs is a property of the close, not of the order
        // the `defer`s happen to run in. `sqlite3_close` leaves the handle open and leaks it if
        // any statement is still live; today the finalize below is registered later and so runs
        // first, but that is an accident of two lines' relative position, and this function has
        // already grown early returns between the two.
        defer { sqlite3_close_v2(handle) }

        var statement: OpaquePointer?
        let prepared = sqlite3_prepare_v2(
            handle, "SELECT idx, data FROM gen_metadata WHERE data IS NOT NULL ORDER BY idx",
            -1, &statement, nil)
        guard prepared == SQLITE_OK, let statement else {
            // `SQLITE_ERROR` here is "no such table", which is a fact about the file and will
            // never change; anything else (BUSY, I/O) is this moment failing to read a store
            // that may well be a conversation.
            return prepared == SQLITE_ERROR ? .notAConversation : .unreadable(status: prepared)
        }
        defer { sqlite3_finalize(statement) }

        let stepDates = generationStepDates(handle)
        if let status = stepDates.status {
            return .incompleteScan(status: status, rows: 0)
        }

        let storeDate = signature(of: database)?.mtime ?? Date()
        let conversation = database.deletingPathExtension().lastPathComponent
        var entries: [LocalUsageReader.Entry] = []
        var discardedCounters = 0
        var rows = 0
        var takenByExecution: [String: Int] = [:]
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_ROW {
                rows += 1
                autoreleasepool {
                    let index = sqlite3_column_int64(statement, 0)
                    guard let pointer = sqlite3_column_blob(statement, 1) else { return }
                    let count = Int(sqlite3_column_bytes(statement, 1))
                    guard count > 0 else { return }
                    let blob = Data(bytes: pointer, count: count)
                    let record = parseGenerationMetadata(
                        blob, conversation: conversation, index: index,
                        fallbackDate: { responseID, executionID in
                            if let responseID, let date = stepDates.byResponse[responseID] {
                                return date
                            }
                            if let executionID, let list = stepDates.byExecution[executionID], !list.isEmpty {
                                let ordinal = takenByExecution[executionID, default: 0]
                                takenByExecution[executionID] = ordinal + 1
                                return list[min(ordinal, list.count - 1)]
                            }
                            return storeDate
                        },
                        formatter: formatter)
                    discardedCounters += record.discardedCounters
                    guard let entry = record.entry else { return }
                    entries.append(entry)
                }
                continue
            }
            // The CLI writes while the app polls, so a scan can end on BUSY rather than on
            // DONE. Half a conversation would otherwise be cached as the whole of it; drop
            // it instead and let the next refresh read it entire.
            guard step == SQLITE_DONE else { return .incompleteScan(status: step, rows: rows) }
            break
        }
        return .complete(entries: entries, discardedCounters: discardedCounters)
    }

    /// `mode=ro` cannot create the `-shm` file a WAL database needs, so it fails outright on
    /// conversations that have no `-wal` sibling yet. `immutable=1` reads those, and is only
    /// reached when there is no `-wal` — that is, when there is no uncommitted tail to miss.
    /// Using `immutable=1` first would silently drop the newest turns of an active conversation.
    private static func openReadOnly(_ database: URL) -> OpaquePointer? {
        guard FileManager.default.fileExists(atPath: database.path) else { return nil }
        let escaped = database.path.addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed) ?? database.path
        for parameters in ["mode=ro", "immutable=1"] {
            var handle: OpaquePointer?
            let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI | SQLITE_OPEN_NOMUTEX
            let opened = sqlite3_open_v2("file:\(escaped)?\(parameters)", &handle, flags, nil)
            // Opening is lazy: `mode=ro` reports success on a checkpointed WAL database and
            // only fails once something reads, which is late enough to look like an empty
            // conversation instead of a failed open. Force the read here so the fallback runs.
            if opened == SQLITE_OK, let handle,
               sqlite3_exec(handle, "SELECT count(*) FROM sqlite_master", nil, nil, nil) == SQLITE_OK {
                return handle
            }
            if let handle { sqlite3_close_v2(handle) }
        }
        return nil
    }

    // MARK: Dating a record Antigravity 2.0 left undated

    /// Current Antigravity stores keep the generation timestamp in the corresponding `steps.metadata`
    /// row rather than in `gen_metadata.data`. Records are correlated by `response_id` (1:1), falling
    /// back to `execution_id` and file mtime.
    private static func generationStepDates(
        _ handle: OpaquePointer
    ) -> (byResponse: [String: Date], byExecution: [String: [Date]], status: Int32?) {
        var statement: OpaquePointer?
        let sql = "SELECT metadata FROM steps WHERE metadata IS NOT NULL ORDER BY idx"
        let prepared = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard prepared == SQLITE_OK, let statement else {
            return ([:], [:], prepared == SQLITE_ERROR ? nil : prepared)
        }
        defer { sqlite3_finalize(statement) }

        var byResponse: [String: Date] = [:]
        var byExecution: [String: [Date]] = [:]
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_ROW {
                autoreleasepool {
                    guard let pointer = sqlite3_column_blob(statement, 0) else { return }
                    let count = Int(sqlite3_column_bytes(statement, 0))
                    guard count > 0 else { return }
                    let bytes = [UInt8](Data(bytes: pointer, count: count))
                    let date = timestamp(bytes[...], field: 8) ?? timestamp(bytes[...], field: 1)
                    guard let date else { return }
                    if let model = AntigravityProto.message(bytes[...], field: 9),
                       let responseID = AntigravityProto.string(model, field: 11) {
                        byResponse[responseID] = date
                    }
                    if let executionID = AntigravityProto.string(bytes[...], field: 12) {
                        byExecution[executionID, default: []].append(date)
                    }
                }
                continue
            }
            return (byResponse, byExecution, step == SQLITE_DONE ? nil : step)
        }
    }

    // MARK: Parsing one generation record

    /// What one `gen_metadata` row yielded. `discardedCounters` travels with the entry because
    /// `tokenCount` runs four times per row and a live store holds thousands of them — the scan
    /// totals these rather than reporting each one where it happens.
    struct Record: Sendable {
        var entry: LocalUsageReader.Entry?
        var discardedCounters = 0
    }

    static func parseGenerationMetadata(
        _ blob: Data,
        conversation: String,
        index: Int64,
        fallbackDate: (_ responseID: String?, _ executionID: String?) -> Date? = { _, _ in nil },
        formatter: DateFormatter
    ) -> Record {
        let bytes = [UInt8](blob)
        guard let chatModel = AntigravityProto.message(bytes[...], field: 1),
              let usage = AntigravityProto.message(chatModel, field: 4) else { return Record() }

        let responseID = AntigravityProto.string(usage, field: 11)
        let executionID = AntigravityProto.string(bytes[...], field: 4)

        let date: Date
        switch createdAt(chatModel) {
        case .valid(let d):
            date = d
        case .absent:
            guard let inferred = fallbackDate(responseID, executionID) else {
                return Record()
            }
            date = inferred
        case .invalid:
            return Record()
        }

        // The turn's own id, not the file it happens to sit in — a copied conversation must
        // not read as fresh spend. `response_id` is populated on every recorded call.
        let identity = responseID.map { "antigravity|\($0)" }
            ?? "antigravity|\(conversation)|\(index)"

        // `response_model` names the model that answered; the rate lookup is short-circuited
        // by the prefix, because Antigravity is a subscription and bills no per-token amount.
        let model = AntigravityProto.string(chatModel, field: 19) ?? "unknown"

        let input = AntigravityProto.tokenCount(usage, field: 2)
        let output = AntigravityProto.tokenCount(usage, field: 3)
        let cacheWrite = AntigravityProto.tokenCount(usage, field: 4)
        let cacheRead = AntigravityProto.tokenCount(usage, field: 5)

        return Record(
            entry: makeEntry(
                id: identity,
                date: date,
                localDay: formatter.string(from: date),
                model: "antigravity/\(model)",
                input: input ?? 0,
                output: output ?? 0,
                cacheWrite: cacheWrite ?? 0,
                cacheRead: cacheRead ?? 0),
            discardedCounters: [input, output, cacheWrite, cacheRead].filter { $0 == nil }.count)
    }

    private enum ParsedDate {
        case valid(Date)
        case absent
        case invalid
    }

    /// `chat_start_metadata.created_at`, a `google.protobuf.Timestamp`.
    private static func createdAt(_ chatModel: ArraySlice<UInt8>) -> ParsedDate {
        guard let start = AntigravityProto.message(chatModel, field: 9),
              let stamp = AntigravityProto.message(start, field: 4) else {
            return .absent
        }
        guard let seconds = AntigravityProto.varint(stamp, field: 1),
              seconds >= 1_000_000_000, seconds <= 4_102_444_800 else {
            return .invalid
        }
        let nanos = AntigravityProto.varint(stamp, field: 2).map { $0 < 1_000_000_000 ? Double($0) : 0 } ?? 0
        return .valid(Date(timeIntervalSince1970: Double(seconds) + nanos / 1_000_000_000))
    }

    /// A `google.protobuf.Timestamp` held at `field`, with the same plausibility window
    /// `createdAt` applies — a malformed varint can carry the whole `uint64` range, and a `Date`
    /// built from one would overflow the arithmetic downstream of it.
    static func timestamp(_ data: ArraySlice<UInt8>, field: Int) -> Date? {
        guard let stamp = AntigravityProto.message(data, field: field),
              let seconds = AntigravityProto.varint(stamp, field: 1),
              seconds >= 1_000_000_000, seconds <= 4_102_444_800 else { return nil }
        let nanos = AntigravityProto.varint(stamp, field: 2).map { $0 < 1_000_000_000 ? Double($0) : 0 } ?? 0
        return Date(timeIntervalSince1970: Double(seconds) + nanos / 1_000_000_000)
    }

    private static func makeEntry(
        id: String,
        date: Date,
        localDay: String,
        model: String,
        input: Int,
        output: Int,
        cacheWrite: Int,
        cacheRead: Int
    ) -> LocalUsageReader.Entry? {
        guard input + output + cacheWrite + cacheRead > 0 else { return nil }
        return LocalUsageReader.Entry(
            id: id, date: date, localDay: localDay, model: model,
            input: input, output: output, cacheWrite: cacheWrite, cacheRead: cacheRead)
    }
}

// MARK: - Protobuf wire format

/// Just enough of the protobuf wire format to walk the Cascade metadata blobs. Reading an
/// external file, a malformed byte is an expected outcome rather than an error: every helper
/// stops at the first thing it cannot parse and reports what it read up to that point.
enum AntigravityProto {

    /// Tokens are `uint64` on the wire. Widening one straight into `Int` hands unbounded
    /// values to arithmetic that traps on overflow, and a trap here would kill the app on
    /// every refresh until the file changed. A count this large is a sentinel, not a count.
    ///
    /// This is the sibling of `LocalUsageReader.maxParsedTokenValue`, which guards the JSON
    /// readers, and the two deliberately differ on both axes — see the PR for whether they
    /// should be reconciled:
    ///
    /// - **Ceiling.** That one leaves room for sums taken straight after parsing
    ///   (`output + thoughts`); nothing here adds two parsed values before `Entry.total`, whose
    ///   four terms are each bounded by this, so a tighter ceiling costs nothing. A per-call
    ///   counter three orders of magnitude past the largest context window is already a
    ///   sentinel.
    /// - **What happens above it.** That one clamps to the ceiling; this one discards the
    ///   counter. Both avoid the trap. Clamping keeps a number that then dominates every
    ///   aggregate it reaches — today's total, the burn tier, the companion — while discarding
    ///   loses that one counter and leaves the rest of the record intact.
    static let tokenCeiling: UInt64 = 1_000_000_000

    /// `nil` means the field was there and its value cannot be a count. That is not the same as
    /// the field being absent, which is a legitimate zero — `cache_write_tokens` is declared and
    /// never written — and the caller needs to tell them apart to be able to say one happened.
    static func tokenCount(_ data: ArraySlice<UInt8>, field: Int) -> Int? {
        guard let value = varint(data, field: field) else { return 0 }
        return value <= tokenCeiling ? Int(value) : nil
    }

    static func varint(_ data: ArraySlice<UInt8>, field: Int) -> UInt64? {
        var result: UInt64?
        walk(data) { number, value, payload in
            guard number == field, payload == nil else { return true }
            result = value
            return false
        }
        return result
    }

    static func string(_ data: ArraySlice<UInt8>, field: Int) -> String? {
        guard let payload = message(data, field: field), !payload.isEmpty else { return nil }
        guard let text = String(bytes: payload, encoding: .utf8), !text.isEmpty else { return nil }
        return text
    }

    static func message(_ data: ArraySlice<UInt8>, field: Int) -> ArraySlice<UInt8>? {
        var result: ArraySlice<UInt8>?
        walk(data) { number, _, payload in
            guard number == field, let payload else { return true }
            result = payload
            return false
        }
        return result
    }

    /// Visits each field in order until `visit` returns false or the bytes stop making sense.
    /// Length-delimited fields arrive as `payload`; varints arrive as `value`. Fixed-width
    /// fields are skipped — nothing this reader wants is encoded that way.
    static func walk(
        _ data: ArraySlice<UInt8>,
        _ visit: (_ field: Int, _ value: UInt64, _ payload: ArraySlice<UInt8>?) -> Bool
    ) {
        var index = data.startIndex
        while index < data.endIndex {
            guard let (key, afterKey) = varint(data, from: index) else { return }
            index = afterKey
            let field = Int(key >> 3)
            guard field > 0 else { return }
            switch key & 7 {
            case 0:
                guard let (value, afterValue) = varint(data, from: index) else { return }
                index = afterValue
                if !visit(field, value, nil) { return }
            case 1:
                guard data.endIndex - index >= 8 else { return }
                index += 8
            case 2:
                guard let (length, afterLength) = varint(data, from: index),
                      length <= UInt64(data.endIndex - afterLength) else { return }
                let end = afterLength + Int(length)
                if !visit(field, 0, data[afterLength..<end]) { return }
                index = end
            case 5:
                guard data.endIndex - index >= 4 else { return }
                index += 4
            default:
                // Groups (3 and 4) were removed from the language, so meeting one means
                // these bytes are not the message we took them for.
                return
            }
        }
    }

    private static func varint(_ data: ArraySlice<UInt8>, from start: Int) -> (UInt64, Int)? {
        var value: UInt64 = 0
        var shift: UInt64 = 0
        var index = start
        while index < data.endIndex {
            let byte = data[index]
            index += 1
            value |= UInt64(byte & 0x7f) << shift
            if byte & 0x80 == 0 { return (value, index) }
            shift += 7
            if shift > 63 { return nil }   // a varint is at most ten bytes
        }
        return nil
    }
}

// MARK: - Shared read

/// Holds the parse of each conversation store between calls, keyed on that store's
/// `(path, mtime, size)` the way `LocalUsageCache` keys its per-file blobs. The Antigravity
/// provider's daily and enrichment calls therefore share one parse without a clock being
/// involved: both re-stat every store, and neither reopens one that has not moved.
///
/// The keying replaces a 30-second expiry, which had the two failings a timer always has — it
/// served a store that had just changed from a stale parse for up to half a minute, and once it
/// lapsed it reopened all of them to find out that none had.
actor LocalAntigravityUsageCache {
    static let shared = LocalAntigravityUsageCache()

    private let roots: [URL]?
    private let now: @Sendable () -> Date
    private var blobs: [String: LocalAntigravityUsageReader.Blob] = [:]
    private var inFlight: Task<LocalAntigravityUsageReader.Scan, Never>?

    init(roots: [URL]? = nil, now: @escaping @Sendable () -> Date = Date.init) {
        self.roots = roots
        self.now = now
    }

    init(root: URL?, now: @escaping @Sendable () -> Date = Date.init) {
        self.roots = root.map { [$0] }
        self.now = now
    }

    func entries() async -> [LocalUsageReader.Entry] {
        // One scan covers every window the provider reports — the block, the week and the month
        // — so the lower bound is the earliest of the three. It is a min of three non-decreasing
        // functions of `now`, so it only ever advances: a bound sampled before the scan admits a
        // superset of what the bound current after it would have, which is why the blobs stay
        // sound across a month boundary that a `monthKey` guard used to throw them away at.
        let since = LocalUsageReader.enrichmentScanStart(now: now())

        let scanned: LocalAntigravityUsageReader.Scan
        if let inFlight {
            // Join rather than start a second scan, and leave the log to the owner.
            scanned = await inFlight.value
        } else {
            let targetRoots = self.roots ?? LocalAntigravityUsageReader.resolvedRoots(
                customRootsValue: CustomScanRoots.storedValue(for: "antigravity"))
            let known = blobs
            let task = Task.detached(priority: .utility) {
                LocalAntigravityUsageReader.scan(roots: targetRoots, modifiedSince: since, known: known)
            }
            inFlight = task
            scanned = await task.value
            inFlight = nil
            // A visited-only rebuild is the prune: a store that fell out of the window or off
            // the disk leaves the cache with it, exactly rather than on a 40-day approximation.
            blobs = scanned.blobs
            for line in scanned.log { AppLog.write(line) }
        }

        // Re-sampled after the suspension. `since` above bounds discovery; this bounds what the
        // caller is told, and the two are not the same instant.
        return LocalAntigravityUsageReader.assemble(
            scanned.blobs, since: LocalUsageReader.enrichmentScanStart(now: now()))
    }
}
