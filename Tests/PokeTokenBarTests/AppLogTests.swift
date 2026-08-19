import XCTest
@testable import PokeTokenBar

/// #174: `AppLog.write` is async, so a line written on the way out of the
/// process races `exit(0)` and is frequently lost. `flush` (`queue.sync {}`)
/// is the exit-path pair. `write` is gated on `AppEnv.isBundledApp`, so a
/// test that opens the production log file would pass with or without the
/// fix — the same split #163 left untested. These tests inject the sink so
/// the drain is visible without touching `~/Library/Logs`.
final class AppLogTests: XCTestCase {

    /// The #174 leak: `write` returns before the sink runs. Without `flush`
    /// the line has not landed; after `flush` it has. Dropping `flush` from
    /// the test (or making `write` skip the queue) fails the second assert.
    func testFlushDrainsAQueuedWriteBeforeReturning() {
        let queue = DispatchQueue(label: "poketokenbar.log.test")
        let landed = LineSink()
        let log = AsyncLineLog(queue: queue) { line in
            Thread.sleep(forTimeInterval: 0.03)
            landed.append(line)
        }

        log.write("clean shutdown")
        XCTAssertTrue(landed.lines.isEmpty, "write must return before the sink runs — otherwise flush is untestable")
        log.flush()
        XCTAssertEqual(landed.lines, ["clean shutdown"], "flush must wait for the queued write, not return while it is still in flight")
    }

    /// A second write queued ahead of flush must both land, in order.
    /// `queue.sync {}` is a barrier behind every earlier `async`, not a
    /// drain of only the most recent line.
    func testFlushDrainsEveryWriteQueuedBeforeIt() {
        let queue = DispatchQueue(label: "poketokenbar.log.test.multi")
        let landed = LineSink()
        let log = AsyncLineLog(queue: queue) { landed.append($0) }

        log.write("launch: start")
        log.write("clean shutdown")
        log.flush()
        XCTAssertEqual(landed.lines, ["launch: start", "clean shutdown"])
    }

    /// `writeAndFlush` is the call-site pair `markClean` and the duplicate
    /// yield path must use. A caller that reaches `exit()` after `write`
    /// alone is the defect.
    func testWriteAndFlushLandsTheLineBeforeReturning() {
        let queue = DispatchQueue(label: "poketokenbar.log.test.pair")
        let landed = LineSink()
        let log = AsyncLineLog(queue: queue) { line in
            Thread.sleep(forTimeInterval: 0.03)
            landed.append(line)
        }

        log.writeAndFlush("clean shutdown")
        XCTAssertEqual(landed.lines, ["clean shutdown"])
    }

    /// Production `AppLog.writeAndFlush` must go through the tested
    /// `backend.writeAndFlush`. `write()`+`flush()` is a second, untested
    /// pair — dropping `flush()` there reintroduces #174 with a green suite.
    func testAppLogWriteAndFlushRoutesThroughBackend() throws {
        let source = try String(contentsOf: repositoryFile("Sources/PokeTokenBar/Core/AppLog.swift"))
        let body = try XCTUnwrap(
            functionBody(named: "writeAndFlush", in: source),
            "AppLog.writeAndFlush is the production exit-path pair")
        XCTAssertTrue(
            body.contains("backend.writeAndFlush("),
            "the shipped writeAndFlush must call the tested drain, not a second pair")
        XCTAssertTrue(
            body.contains("AppEnv.isBundledApp"),
            "bypassing write() without the bundled-app guard lets swift test pollute the real log")
        XCTAssertFalse(
            body.contains("write(message)"),
            "write()+flush() is the untested pair the owner removed and the suite stayed green")
    }

    /// Wiring: `markClean` must go through `writeAndFlush`, not `write`
    /// alone. `AppLog.write` is a no-op under `swift test`, so calling
    /// `markClean` cannot prove the drain. The source scan does — the same
    /// shape as `testNoProviderReadsUsageLocationEnvDirectly`.
    func testMarkCleanUsesWriteAndFlushNotWriteAlone() throws {
        let source = try String(contentsOf: repositoryFile("Sources/PokeTokenBar/Core/CrashReporter.swift"))
        let body = try XCTUnwrap(
            functionBody(named: "markClean", in: source),
            "CrashReporter.markClean is the willTerminate site #174 names")
        XCTAssertTrue(
            body.contains("AppLog.writeAndFlush(\"clean shutdown\")"),
            "markClean must flush the clean-shutdown line; write alone races exit")
        XCTAssertFalse(
            body.contains("AppLog.write("),
            "a leftover write() without flush is the original leak")
    }

    /// Sweep: the #163 yield path is the other write-then-exit site. It
    /// already flushed; keep it on the same pair so a future edit cannot
    /// drop one and keep the other. Scan only the yield `if` — `functionBody`
    /// on `applicationDidFinishLaunching` spans ~ten methods and rejects a
    /// correct launch-path `AppLog.write`.
    func testDuplicateYieldUsesWriteAndFlushBeforeTerminate() throws {
        let source = try String(contentsOf: repositoryFile("Sources/PokeTokenBar/PokeTokenBarApp.swift"))
        let body = try XCTUnwrap(
            yieldBlock(in: source),
            "the yield path lives in the shouldYieldToRunningInstance block")
        XCTAssertTrue(
            body.contains("AppLog.writeAndFlush(\"duplicate instance: yielding to the instance already running\")"),
            "the yield path must flush before terminate — #163 review, 42/100 lost")
        XCTAssertFalse(
            body.contains("AppLog.write("),
            "write() without flush on this path is the race #163 already closed")
        XCTAssertTrue(
            body.contains("NSApp.terminate"),
            "the scanned block must still be the write-then-exit site")
    }

    // MARK: - Helpers

    /// Sink box so the `@Sendable` log closure can append without capturing a
    /// mutable `var`. Reads happen only after `flush`, so the queue is idle.
    private final class LineSink: @unchecked Sendable {
        private(set) var lines: [String] = []
        func append(_ line: String) { lines.append(line) }
    }

    private func repositoryFile(_ relative: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // PokeTokenBarTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repo root
            .appendingPathComponent(relative)
    }

    /// The `if SingleInstance.shouldYieldToRunningInstance()` block only —
    /// not the rest of `applicationDidFinishLaunching`. A launch-path
    /// `AppLog.write` after SIGPIPE is not an exit-path race.
    private func yieldBlock(in source: String) -> String? {
        guard let start = source.range(of: "if SingleInstance.shouldYieldToRunningInstance()") else { return nil }
        let rest = source[start.lowerBound...]
        guard let end = rest.range(of: "signal(SIGPIPE") else { return nil }
        return String(rest[..<end.lowerBound])
    }

    /// Body of `func <name>` up to the next top-level `func` / `///` type doc
    /// at the same indent, or end of file. Enough to pin a call inside one
    /// method without matching a comment elsewhere in the file.
    private func functionBody(named name: String, in source: String) -> String? {
        let marker = "func \(name)("
        guard let start = source.range(of: marker) else { return nil }
        let rest = source[start.lowerBound...]
        let next = rest.range(of: "\n    func ", options: [], range: rest.index(after: start.lowerBound)..<rest.endIndex)
            ?? rest.range(of: "\n    ///", options: [], range: rest.index(after: start.lowerBound)..<rest.endIndex)
        return String(rest[..<(next?.lowerBound ?? rest.endIndex)])
    }
}
