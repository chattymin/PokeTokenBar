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
    private var cursors: [String: UInt64] = [:]
    private var emitter = AgentLogEmitter()
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
            emitter = AgentLogEmitter()
        }
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
        for path in paths.sorted() {
            let url = URL(fileURLWithPath: path)
            guard let source = rootsBySource.first(where: { entry in
                entry.roots.contains { path.hasPrefix($0 + "/") } && entry.source.accepts(url)
            })?.source,
                let reading = read(path).flatMap(source.interpret)
            else { continue }
            let installed = hooksInstalled(source)
            if emitter.shouldEmit(reading, sourceID: source.id, hooksReport: installed, now: Date()) {
                handler(reading, source, installed)
            }
        }
    }

    /// New complete lines since the last read, or the tail of a file seen for the first time.
    private func read(_ path: String) -> [Substring]? {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? UInt64,
              let range = AgentLogTail.range(size: size, knownOffset: cursors[path]),
              let handle = FileHandle(forReadingAtPath: path)
        else { return nil }
        defer { try? handle.close() }
        guard (try? handle.seek(toOffset: range.start)) != nil,
              let data = try? handle.read(upToCount: Int(size - range.start))
        else { return nil }
        let (lines, consumed) = AgentLogTail.completeLines(data, dropsFirstLine: range.dropsFirstLine)
        if cursors[path] == nil, cursors.count >= Self.maxCursors { cursors = [:] }
        cursors[path] = range.start + UInt64(consumed)
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
