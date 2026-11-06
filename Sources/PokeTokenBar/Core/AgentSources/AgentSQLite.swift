import Foundation
import SQLite3

/// A read-only connection for the agents that keep sessions in SQLite (OpenCode, Hermes, Devin,
/// Aside). Lives for one `AgentDatabaseReader.read`; never writes the database.
final class AgentSQLiteConnection {
    let handle: OpaquePointer
    private var tableCache: Set<String>?
    private var columnCache: [String: Set<String>] = [:]

    private init(handle: OpaquePointer) { self.handle = handle }

    deinit { sqlite3_close_v2(handle) }

    /// `mode=ro`, like `LocalAntigravityUsageReader.openReadOnly`: a WAL reader sees the agent's
    /// newest commits and writes nothing but read marks in `-shm` (which `database(_:)` ignores).
    /// No `immutable=1` fallback: immutable skips the WAL, so it would answer with the state before
    /// the commits this read was woken for. A failed open is retried on the next change.
    static func open(_ url: URL) -> AgentSQLiteConnection? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let escaped = url.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? url.path
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2("file:\(escaped)?mode=ro", &handle, flags, nil) == SQLITE_OK, let handle else {
            if let handle { sqlite3_close_v2(handle) }
            return nil
        }
        // Readers do not wait on a WAL writer; this only covers WAL recovery after a crash.
        sqlite3_busy_timeout(handle, 200)
        let connection = AgentSQLiteConnection(handle: handle)
        // Opening is lazy; force a read so a file that is not a database fails here.
        guard connection.tables != nil else { return nil }
        return connection
    }

    enum Bind {
        case int(Int64)
        case text(String)
    }

    struct Row {
        fileprivate let statement: OpaquePointer

        func isNull(_ index: Int32) -> Bool { sqlite3_column_type(statement, index) == SQLITE_NULL }
        func int64(_ index: Int32) -> Int64? { isNull(index) ? nil : sqlite3_column_int64(statement, index) }
        func double(_ index: Int32) -> Double? { isNull(index) ? nil : sqlite3_column_double(statement, index) }
        func text(_ index: Int32) -> String? {
            guard let bytes = sqlite3_column_text(statement, index) else { return nil }
            return String(cString: bytes)
        }
    }

    /// Rows mapped by `row` (nil rows are dropped). Nil when the statement fails or the scan
    /// stops early (BUSY, a missing table), so a caller never mistakes a partial read for "nothing".
    func query<T>(_ sql: String, _ binds: [Bind] = [], _ row: (Row) -> T?) -> [T]? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return nil }
        defer { sqlite3_finalize(statement) }
        for (offset, bind) in binds.enumerated() {
            let index = Int32(offset + 1)
            switch bind {
            case .int(let value): sqlite3_bind_int64(statement, index, value)
            case .text(let value):
                // SQLITE_TRANSIENT: SQLite copies the bytes; the Swift string dies after this call.
                sqlite3_bind_text(statement, index, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            }
        }
        var result: [T] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_ROW {
                if let value = row(Row(statement: statement)) { result.append(value) }
                continue
            }
            return step == SQLITE_DONE ? result : nil
        }
    }

    /// Tables in the database; nil when even the schema cannot be read.
    var tables: Set<String>? {
        if let tableCache { return tableCache }
        let names = query("SELECT name FROM sqlite_master WHERE type = 'table'") { $0.text(0) }
        tableCache = names.map(Set.init)
        return tableCache
    }

    /// Column names of `table`, for columns that only some versions of an agent have.
    func columns(_ table: String) -> Set<String> {
        if let cached = columnCache[table] { return cached }
        let names = Set(query("SELECT name FROM pragma_table_info(?1)", [.text(table)]) { $0.text(0) } ?? [])
        columnCache[table] = names
        return names
    }
}

/// A table whose new rows name the sessions that moved.
struct AgentDatabaseFeed {
    /// Key of the table's high-water rowid in the watermark.
    let table: String
    /// `SELECT <session>, rowid, <time or NULL> FROM … WHERE rowid > ?1`. Rowids grow with every
    /// insert (and only on insert), so the range is answered from the table's own b-tree.
    let sql: String
    /// Prepended to the session id, for databases that hold two generations of sessions.
    var prefix = ""
}

/// What a reader found about one session.
struct AgentSessionProbe {
    var reading: AgentLogReading
    /// Changes when the session moved without changing state (a newer row, a later timestamp),
    /// so a session rechecked without new rows still sends "still working".
    var progress: String? = nil
    /// The row to recheck next time, for agents whose state lives in one updatable row.
    var ref: Int64? = nil
}

/// What a database reader remembers between reads, kept in the watcher's watermark string.
struct AgentDatabaseCursor: Codable, Equatable {
    struct Open: Codable, Equatable {
        var signature: String
        var ref: Int64?
        /// When the signature last changed (seconds since 1970).
        var changed: Double
    }

    /// Highest rowid seen per feed table.
    var marks: [String: Int64] = [:]
    /// Sessions last seen working or waiting. Agents finish a turn (and answer a question) by
    /// updating rows in place, which no rowid shows, so these are rechecked on every read.
    var open: [String: Open] = [:]

    var encoded: String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(self)).map { String(decoding: $0, as: UTF8.self) }
    }

    init() {}

    init?(encoded: String?) {
        guard let encoded, let cursor = try? JSONDecoder().decode(Self.self, from: Data(encoded.utf8)) else { return nil }
        self = cursor
    }
}

/// The read loop every database source shares: new rows (by rowid) and open sessions become
/// candidates, each candidate is probed through the agent's own indexes, and a reading goes out
/// when the session moved or its state changed. Every query is bounded by an index or a rowid
/// range: this runs on each commit while an agent works.
enum AgentDatabasePoll {
    /// A first look reports only sessions that moved this recently.
    static let firstLookWindow: TimeInterval = 60
    /// Rows a first look reads from the end of each feed.
    static let tailRows: Int64 = 256
    /// More new rows than this (an import, a migration) and the feed is read like a first look.
    static let maxJump: Int64 = 2_000
    /// Sessions probed per read, newest first.
    static let maxSessions = 32
    /// An open session that has not changed for this long is no longer rechecked; new rows still
    /// bring it back.
    static let openExpiry: TimeInterval = 3_600

    static func read(
        _ url: URL,
        watermark: String?,
        now: Date,
        feeds: (AgentSQLiteConnection) -> [AgentDatabaseFeed],
        probe: (AgentSQLiteConnection, _ key: String, _ ref: Int64?) -> AgentSessionProbe?
    ) -> (readings: [AgentLogReading], watermark: String?) {
        guard let db = AgentSQLiteConnection.open(url) else { return ([], watermark) }
        let previous = AgentDatabaseCursor(encoded: watermark)
        var cursor = AgentDatabaseCursor()
        let cutoff = now.timeIntervalSince1970 - firstLookWindow
        // Session key → highest new rowid that named it.
        var moved: [String: Int64] = [:]
        for feed in feeds(db) {
            // A failed read keeps the old watermark: the next change asks again.
            guard let max = db.query("SELECT MAX(rowid) FROM \(feed.table)", [], { $0.int64(0) ?? 0 })?.first
            else { return ([], watermark) }
            let known = previous?.marks[feed.table]
            // Nil: never seen (first look, or a table that appeared with an upgrade). Below the
            // mark: the database was recreated.
            let firstLook = known.map { max < $0 || max - $0 > maxJump } ?? true
            let after = firstLook ? max - tailRows : known!
            if max > after {
                guard let rows = db.query(feed.sql, [.int(after)], { row -> (String, Int64, Double?)? in
                    guard let session = row.text(0) else { return nil }
                    return (session, row.int64(1) ?? 0, row.double(2))
                }) else { return ([], watermark) }
                for (session, rowid, time) in rows {
                    if firstLook, (time.map(seconds) ?? 0) < cutoff { continue }
                    let key = feed.prefix + session
                    moved[key] = Swift.max(moved[key] ?? 0, rowid)
                }
            }
            cursor.marks[feed.table] = max
        }

        let open = previous?.open ?? [:]
        let keys = moved.sorted { $0.value > $1.value }.map(\.key)
            + open.keys.filter { moved[$0] == nil }.sorted()
        var probed: [(order: Int64, reading: AgentLogReading)] = []
        for key in keys.prefix(maxSessions) {
            let wasOpen = open[key]
            guard let found = probe(db, key, moved[key] ?? wasOpen?.ref) else { continue }
            let signature = [kind(found.reading.activity), found.reading.lineID ?? "", found.progress ?? ""]
                .joined(separator: "\u{1F}")
            let changed = signature != wasOpen?.signature
            if moved[key] != nil || changed {
                probed.append((moved[key] ?? 0, found.reading))
            }
            switch found.reading.activity {
            case .working, .waiting:
                cursor.open[key] = AgentDatabaseCursor.Open(
                    signature: signature, ref: found.ref ?? moved[key] ?? wasOpen?.ref,
                    changed: changed || moved[key] != nil ? now.timeIntervalSince1970 : wasOpen?.changed ?? 0)
            case .done, .idle:
                break
            }
        }
        cursor.open = cursor.open.filter { now.timeIntervalSince1970 - $0.value.changed < openExpiry }
        // Rechecked sessions first, then new rows oldest to newest: the newest reading per label wins.
        let readings = probed.enumerated()
            .sorted { ($0.element.order, $0.offset) < ($1.element.order, $1.offset) }
            .map(\.element.reading)
        return (readings, cursor.encoded ?? watermark)
    }

    /// Seconds since 1970 from a column that may hold seconds or milliseconds.
    static func seconds(_ raw: Double) -> Double {
        raw >= 100_000_000_000 ? raw / 1_000 : raw
    }

    /// Last path component of a working folder; nil for an empty one.
    static func folderName(_ path: String?) -> String? {
        guard let path, !path.isEmpty else { return nil }
        let name = URL(fileURLWithPath: path).lastPathComponent
        return name.isEmpty || name == "/" ? nil : name
    }

    static func nonEmpty(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    /// The database behind a changed `name` or `name-wal`; nil for `-shm` and anything else.
    static func database(_ url: URL, named matches: (String) -> Bool) -> URL? {
        let name = url.lastPathComponent
        if matches(name) { return url }
        if name.hasSuffix("-wal"), matches(String(name.dropLast(4))) {
            return url.deletingLastPathComponent().appendingPathComponent(String(name.dropLast(4)))
        }
        return nil
    }

    private static func kind(_ activity: AgentActivity) -> String {
        switch activity {
        case .idle: "idle"
        case .working: "working"
        case .waiting: "waiting"
        case .done: "done"
        }
    }
}
