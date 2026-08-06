import Foundation
import SQLite3

/// Antigravity CLI usage, read from the conversation stores the CLI writes under
/// `~/.gemini/antigravity-cli/conversations/<conversation>.db`.
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
///       1.9.4     created_at           google.protobuf.Timestamp
///       1.19    response_model         e.g. "gemini-3.6-flash"
///
/// There is no total field anywhere in the schema, so the total is the sum of the three
/// populated counters — which is exactly the identity `LocalUsageReader.Entry` already keeps.
enum LocalAntigravityUsageReader {

    /// One database per conversation. The directory is absent unless Antigravity CLI ran.
    static var defaultRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gemini/antigravity-cli/conversations")
    }

    /// Usage rows whose `created_at` falls at or after `modifiedSince`.
    static func entries(modifiedSince: Date, root: URL? = nil) -> [LocalUsageReader.Entry] {
        let directory = root ?? defaultRoot
        let formatter = LocalUsageReader.localDayFormatter()
        var entries: [LocalUsageReader.Entry] = []
        var reads: [(conversation: String, read: ConversationRead)] = []
        for database in databases(in: directory, modifiedSince: modifiedSince) {
            let read = conversationEntries(database, modifiedSince: modifiedSince, formatter: formatter)
            entries += read.entries
            reads.append((database.deletingPathExtension().lastPathComponent, read))
        }
        // The one place the side effect lives. `AppLog.write` returns early outside the bundled
        // app, so the decision above it is kept pure and tested on its own (`lossLog`).
        for line in lossLog(reads) { AppLog.write(line) }
        // `response_id` is unique per call, so this only ever collapses a re-read.
        return LocalUsageReader.dedupKeepMax(entries)
    }

    // MARK: Database discovery

    /// A WAL commit lands in the `-wal` sibling and leaves the main file's timestamp alone,
    /// so the newest of the three is the only honest "has this conversation moved" signal.
    static func effectiveModificationDate(of database: URL) -> Date? {
        let manager = FileManager.default
        return [database.path, database.path + "-wal", database.path + "-shm"]
            .compactMap { (try? manager.attributesOfItem(atPath: $0))?[.modificationDate] as? Date }
            .max()
    }

    private static func databases(in root: URL, modifiedSince: Date) -> [URL] {
        let manager = FileManager.default
        guard let names = try? manager.contentsOfDirectory(atPath: root.path) else { return [] }
        return names
            .filter { $0.hasSuffix(".db") }
            .sorted()
            .map { root.appendingPathComponent($0) }
            .filter { (effectiveModificationDate(of: $0) ?? .distantPast) >= modifiedSince }
    }

    // MARK: Reading one conversation

    /// What one conversation store yielded. Three of these four produce no rows, and only one
    /// of those three is a fact about the user's usage — collapsing them all to `[]`, which is
    /// what this reader used to do, is what let a store that could never be read pass for a
    /// store that was never used.
    enum ConversationRead: Sendable {
        /// Read through to `SQLITE_DONE`: these rows are all of them.
        case complete([LocalUsageReader.Entry])
        /// The scan stopped early — BUSY because the CLI was writing, or a damaged page. Half a
        /// conversation must not pass for the whole of it, so the rows read so far are dropped.
        case incompleteScan(status: Int32, rows: Int)
        /// Neither `mode=ro` nor `immutable=1` could open it, or the query failed for a reason
        /// other than the table being absent.
        case unreadable(status: Int32?)
        /// No `gen_metadata`: this file is not a conversation store. A permanent, legitimate
        /// empty — `~/.gemini/antigravity-cli/conversations/` may hold databases we don't read.
        case notAConversation

        var entries: [LocalUsageReader.Entry] {
            if case .complete(let entries) = self { return entries }
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
        let losses = reads.compactMap { entry -> String? in
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
        }
        guard losses.count > namedLossLimit else { return losses }
        return Array(losses.prefix(namedLossLimit))
            + ["antigravity: lost \(losses.count) conversation(s) this scan"
               + " (\(losses.count - namedLossLimit) not named)"]
    }

    static func conversationEntries(
        _ database: URL,
        modifiedSince: Date,
        formatter: DateFormatter
    ) -> ConversationRead {
        guard let handle = openReadOnly(database) else { return .unreadable(status: nil) }
        defer { sqlite3_close(handle) }

        var statement: OpaquePointer?
        let prepared = sqlite3_prepare_v2(
            handle, "SELECT idx, data FROM gen_metadata WHERE data IS NOT NULL", -1, &statement, nil)
        guard prepared == SQLITE_OK, let statement else {
            // `SQLITE_ERROR` here is "no such table", which is a fact about the file and will
            // never change; anything else (BUSY, I/O) is this moment failing to read a store
            // that may well be a conversation.
            return prepared == SQLITE_ERROR ? .notAConversation : .unreadable(status: prepared)
        }
        defer { sqlite3_finalize(statement) }

        let conversation = database.deletingPathExtension().lastPathComponent
        var entries: [LocalUsageReader.Entry] = []
        var rows = 0
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
                    guard let entry = parseGenerationMetadata(
                        blob, conversation: conversation, index: index, formatter: formatter),
                          entry.date >= modifiedSince else { return }
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
        return .complete(entries)
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
            if let handle { sqlite3_close(handle) }
        }
        return nil
    }

    // MARK: Parsing one generation record

    static func parseGenerationMetadata(
        _ blob: Data,
        conversation: String,
        index: Int64,
        formatter: DateFormatter
    ) -> LocalUsageReader.Entry? {
        let bytes = [UInt8](blob)
        guard let chatModel = AntigravityProto.message(bytes[...], field: 1),
              let usage = AntigravityProto.message(chatModel, field: 4),
              let date = createdAt(chatModel) else { return nil }

        // The turn's own id, not the file it happens to sit in — a copied conversation must
        // not read as fresh spend. `response_id` is populated on every recorded call.
        let identity = AntigravityProto.string(usage, field: 11).map { "antigravity|\($0)" }
            ?? "antigravity|\(conversation)|\(index)"

        // `response_model` names the model that answered; the rate lookup is short-circuited
        // by the prefix, because Antigravity is a subscription and bills no per-token amount.
        let model = AntigravityProto.string(chatModel, field: 19) ?? "unknown"

        return makeEntry(
            id: identity,
            date: date,
            localDay: formatter.string(from: date),
            model: "antigravity/\(model)",
            input: AntigravityProto.tokenCount(usage, field: 2),
            output: AntigravityProto.tokenCount(usage, field: 3),
            cacheWrite: AntigravityProto.tokenCount(usage, field: 4),
            cacheRead: AntigravityProto.tokenCount(usage, field: 5))
    }

    /// `chat_start_metadata.created_at`, a `google.protobuf.Timestamp`.
    private static func createdAt(_ chatModel: ArraySlice<UInt8>) -> Date? {
        guard let start = AntigravityProto.message(chatModel, field: 9),
              let stamp = AntigravityProto.message(start, field: 4),
              let seconds = AntigravityProto.varint(stamp, field: 1) else { return nil }
        // A malformed varint can carry the whole uint64 range; a date built from it would
        // overflow downstream arithmetic. Anything outside a plausible window is not a time.
        guard seconds >= 1_000_000_000, seconds <= 4_102_444_800 else { return nil }
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
    static let tokenCeiling: UInt64 = 1_000_000_000

    static func tokenCount(_ data: ArraySlice<UInt8>, field: Int) -> Int {
        guard let value = varint(data, field: field), value <= tokenCeiling else { return 0 }
        return Int(value)
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

/// Shares one native read between the Antigravity provider's daily and enrichment calls, the
/// way `LocalAdditionalUsageCache` does for the other SQLite-backed providers.
actor LocalAntigravityUsageCache {
    static let shared = LocalAntigravityUsageCache()

    private struct Cached: Sendable {
        let loadedAt: Date
        let monthKey: String
        let entries: [LocalUsageReader.Entry]
    }

    private let root: URL?
    private let now: @Sendable () -> Date
    private var cached: Cached?
    private var inFlight: Task<[LocalUsageReader.Entry], Never>?

    init(root: URL? = nil, now: @escaping @Sendable () -> Date = Date.init) {
        self.root = root
        self.now = now
    }

    func entries() async -> [LocalUsageReader.Entry] {
        let moment = now()
        let monthKey = LocalUsageReader.monthKey(moment)
        if let cached, cached.monthKey == monthKey, moment.timeIntervalSince(cached.loadedAt) < 30 {
            return cached.entries
        }
        if let inFlight { return await inFlight.value }

        // One scan covers every window the provider reports — the block, the week and the
        // month — so the lower bound is the earliest of the three.
        let since = LocalUsageReader.enrichmentScanStart(now: moment)
        let root = root
        let task = Task.detached(priority: .utility) {
            LocalAntigravityUsageReader.entries(modifiedSince: since, root: root)
        }
        inFlight = task
        let entries = await task.value
        inFlight = nil
        cached = Cached(loadedAt: moment, monthKey: monthKey, entries: entries)
        return entries
    }
}
