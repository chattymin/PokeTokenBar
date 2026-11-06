import CoreServices
import Foundation

/// Watches agents' session-log folders with FSEvents and reports what changed lines say.
/// Nothing runs while no log changes: no timer, no polling. All state lives on `queue`.
final class AgentLogWatcher: @unchecked Sendable {
    typealias Handler = @Sendable (_ reading: AgentLogReading, _ source: AgentLogSource, _ hooksInstalled: Bool) -> Void

    /// FSEvents coalescing window: a burst of appended lines becomes one read.
    static let latency: CFTimeInterval = 0.3
    /// Hook status is read from the agent's settings file at most this often.
    static let hookStatusTTL: TimeInterval = 10
    /// Files with a known read offset; past this many the oldest are forgotten (their next change
    /// reads the tail again, which is harmless).
    static let maxCursors = 512

    private let sources: [AgentLogSource]
    private let handler: Handler
    private let queue = DispatchQueue(label: "PokeTokenBar.AgentLogWatcher", qos: .utility)
    private var stream: FSEventStreamRef?
    private var rootsBySource: [(source: AgentLogSource, roots: [String])] = []
    private var cursors: [String: (offset: UInt64, inode: UInt64?)] = [:]
    private var heads: [String: AgentLogHead] = [:]
    private var pathLabels: [String: String?] = [:]
    private var lastLabels: [String: String] = [:]
    private var watermarks: [String: String] = [:]
    private var emitter = AgentLogEmitter()
    private var sessions = AgentSessionMemory()
    private var hookStatus: [String: (installed: Bool, at: Date)] = [:]
    private var running = false

    init(sources: [AgentLogSource], handler: @escaping Handler) {
        self.sources = sources
        self.handler = handler
    }

    /// Through `stop()`, so the stream is torn down on `queue` and no callback can still be using
    /// the unretained `self`. The controller holds the only reference, on the main thread.
    deinit {
        stop()
    }

    func start() {
        queue.async { [self] in
            guard !running else { return }
            running = true
            rootsBySource = sources.map { source in
                (source, source.roots().compactMap { Self.realPath($0.path) })
            }
            let paths = Array(Set(rootsBySource.flatMap(\.roots)))
            guard !paths.isEmpty else { return }
            var context = FSEventStreamContext(
                version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                retain: nil, release: nil, copyDescription: nil)
            let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
            guard let stream = FSEventStreamCreate(
                kCFAllocatorDefault, Self.callback, &context, paths as CFArray,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow), Self.latency, flags)
            else { return }
            FSEventStreamSetDispatchQueue(stream, queue)
            guard FSEventStreamStart(stream) else { Self.release(stream); return }
            self.stream = stream
        }
    }

    /// Synchronous, so no callback can arrive after it returns.
    func stop() {
        queue.sync {
            running = false
            if let stream { Self.release(stream) }
            stream = nil
            cursors = [:]
            heads = [:]
            pathLabels = [:]
            lastLabels = [:]
            watermarks = [:]
            emitter = AgentLogEmitter()
            sessions = AgentSessionMemory()
        }
    }

    /// The session that last moved under `label`, for events that come in through hooks.
    func latestSession(label: String?) -> AgentSessionInfo? {
        queue.sync { sessions.latest(label: label) }
    }

    /// FSEvents reports real paths (`/private/var/…`, symlinks resolved). `resolvingSymlinksInPath`
    /// strips `/private` instead, so prefixes would never match. Nil for a missing folder.
    static func realPath(_ path: String) -> String? {
        guard let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    private static func release(_ stream: FSEventStreamRef) {
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }

    private static let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
        guard let info else { return }
        let watcher = Unmanaged<AgentLogWatcher>.fromOpaque(info).takeUnretainedValue()
        let list = Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as? [String] ?? []
        // Already on `queue` (FSEventStreamSetDispatchQueue).
        watcher.filesChanged(Array(Set(list.prefix(count))))
    }

    private func filesChanged(_ paths: [String]) {
        guard running else { return }
        var databases: [(url: URL, source: AgentLogSource, reader: AgentDatabaseReader)] = []
        for path in paths.sorted() {
            let url = URL(fileURLWithPath: path)
            guard let source = rootsBySource.first(where: { entry in
                entry.roots.contains { path.hasPrefix($0 + "/") } && entry.source.accepts(url)
            })?.source
            else { continue }
            if let reader = source.database {
                // `x.db` and `x.db-wal` often change in one batch: query each database once.
                if let db = reader.database(url), !databases.contains(where: { $0.url == db }) {
                    databases.append((db, source, reader))
                }
                continue
            }
            logChanged(path, url: url, source: source)
        }
        for (db, source, reader) in databases {
            let result = reader.read(db, watermarks[db.path])
            if watermarks[db.path] == nil, watermarks.count >= Self.maxCursors { watermarks = [:] }
            watermarks[db.path] = result.watermark
            for reading in result.readings {
                let key = db.path + "#" + (reading.session ?? "")
                sessions.noteActivity(label: reading.label, file: key)
                _ = sessions.update(file: key, title: AgentSessionTitle(named: nil, generated: reading.title), turn: { $0 })
                emit(reading, source: source)
            }
        }
    }

    private func logChanged(_ path: String, url: URL, source: AgentLogSource) {
        if source.head != nil, heads[path] == nil {
            if heads.count >= Self.maxCursors { heads = [:] }
            heads[path] = Self.readHead(path).map { source.head!($0) } ?? AgentLogHead()
        }
        let head = heads[path] ?? AgentLogHead()
        guard !head.skip, let lines = read(path) else { return }
        // Before interpreting: a batch can hold only a title or a turn start, and later
        // readings (and hook events) still need them.
        var title = head.title
        title.update(with: source.title(lines))
        var session = sessions.update(file: path, title: title, turn: { source.turns(lines, $0) })
        guard var reading = source.interpret(lines) else { return }
        // A batch without a folder keeps the file's last one: a resumed session can move folders,
        // and its head still names the first.
        if reading.label == nil { reading.label = lastLabels[path] ?? head.label ?? pathLabel(path, url: url, source: source) }
        if lastLabels[path] == nil, lastLabels.count >= Self.maxCursors { lastLabels = [:] }
        lastLabels[path] = reading.label
        if let externalTitle = source.externalTitle, reading.activity != .working, reading.activity != .idle {
            session = sessions.update(file: path, title: externalTitle(url), turn: { $0 })
        }
        reading.title = session.title
        // A turn nobody asked for ended: the agent is idle, but there is nothing to announce.
        if session.automaticTurn, case .done = reading.activity { reading.activity = .idle }
        sessions.noteActivity(label: reading.label, file: path)
        emit(reading, source: source)
    }

    /// Once per file: a path label can look at folders on disk.
    private func pathLabel(_ path: String, url: URL, source: AgentLogSource) -> String? {
        guard let pathLabel = source.pathLabel else { return nil }
        if let known = pathLabels[path] { return known }
        if pathLabels.count >= Self.maxCursors { pathLabels = [:] }
        let label = pathLabel(url)
        pathLabels[path] = .some(label)
        return label
    }

    private func emit(_ reading: AgentLogReading, source: AgentLogSource) {
        let installed = hooksInstalled(source)
        if emitter.shouldEmit(reading, sourceID: source.id, hooksReport: installed, now: Date()) {
            handler(reading, source, installed)
        }
    }

    /// The first few complete lines, for `AgentLogSource.head`. Bounded: some agents put long
    /// instructions in their first line.
    static let headLines = 4
    static let headBytes = 1024 * 1024

    private static func readHead(_ path: String) -> [Substring]? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        var data = Data()
        var newlines = 0
        while data.count < headBytes, newlines < headLines,
              let chunk = try? handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
            newlines += chunk.reduce(0) { $1 == 0x0A ? $0 + 1 : $0 }
            data.append(chunk)
        }
        let lines = AgentLogTail.completeLines(data, dropsFirstLine: false).lines
        return lines.isEmpty ? nil : Array(lines.prefix(headLines))
    }

    /// New complete lines since the last read, or the tail of a file seen for the first time.
    /// A file replaced by another (written aside, then renamed over it) is read as new.
    private func read(_ path: String) -> [Substring]? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attributes[.size] as? UInt64
        else { return nil }
        let inode = attributes[.systemFileNumber] as? UInt64
        let known = cursors[path].flatMap { $0.inode == inode ? $0.offset : nil }
        guard let range = AgentLogTail.range(size: size, knownOffset: known),
              let handle = FileHandle(forReadingAtPath: path)
        else { return nil }
        defer { try? handle.close() }
        guard (try? handle.seek(toOffset: range.start)) != nil,
              let data = try? handle.read(upToCount: Int(size - range.start))
        else { return nil }
        let (lines, consumed) = AgentLogTail.completeLines(data, dropsFirstLine: range.dropsFirstLine)
        if cursors[path] == nil, cursors.count >= Self.maxCursors { cursors = [:] }
        cursors[path] = (range.start + UInt64(consumed), inode)
        return lines.isEmpty ? nil : lines
    }

    private func hooksInstalled(_ source: AgentLogSource) -> Bool {
        guard let hooks = source.hooks else { return false }
        if let cached = hookStatus[source.id], Date().timeIntervalSince(cached.at) < Self.hookStatusTTL {
            return cached.installed
        }
        let installed = hooks.status().isInstalled
        hookStatus[source.id] = (installed, Date())
        return installed
    }

    /// After the app installs or removes hooks, so the next reading does not use a stale status.
    func invalidateHookStatus() {
        queue.async { [self] in hookStatus = [:] }
    }
}
