import Darwin
import Foundation
import XCTest
@testable import PokeTokenBar

final class CodexLargeRolloutPerformanceTests: XCTestCase {
    private let targetBytes = 512 * 1024 * 1024
    private let rssBudgetBytes: UInt64 = 700 * 1024 * 1024
    private let rssGrowthBudgetBytes: UInt64 = 192 * 1024 * 1024

    func testCodexLargeRolloutStaysWithinMemoryBudget() throws {
        guard ProcessInfo.processInfo.environment["POKETOKENBAR_RUN_LARGE_PERF"] == "1" else {
            throw XCTSkip("Set POKETOKENBAR_RUN_LARGE_PERF=1 or run scripts/perf-codex-large-rollout.sh")
        }

        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let fixture = try writeLargeCodexRollout(to: root)
        XCTAssertGreaterThanOrEqual(fixture.fileSize, targetBytes)
        XCTAssertLessThan(fixture.fileSize, targetBytes + 16 * 1024)
        XCTAssertGreaterThan(fixture.expectedEventCount, 10)

        let baselineRSS = PeakResidentSampler.currentResidentBytes()
        let sampler = PeakResidentSampler()
        sampler.start()
        let started = Date()
        let entries = LocalUsageReader.codexEntries(modifiedSince: .distantPast, root: root)
        let elapsed = Date().timeIntervalSince(started)
        let peakRSS = sampler.stop()
        let rssGrowth = peakRSS >= baselineRSS ? peakRSS - baselineRSS : 0

        let elapsedText = String(format: "%.3f", elapsed)
        print(
            "PERF_RESULT size_mib=512 baseline_rss_mib=\(Self.mib(baselineRSS)) "
                + "peak_rss_mib=\(Self.mib(peakRSS)) rss_growth_mib=\(Self.mib(rssGrowth)) "
                + "elapsed_seconds=\(elapsedText)"
        )

        XCTAssertEqual(entries.count, fixture.expectedEventCount)
        XCTAssertEqual(entries.reduce(0) { $0 + $1.input }, fixture.expectedInput)
        XCTAssertEqual(entries.reduce(0) { $0 + $1.cacheRead }, fixture.expectedCacheRead)
        XCTAssertEqual(entries.reduce(0) { $0 + $1.output }, fixture.expectedOutput)
        XCTAssertEqual(entries.reduce(0) { $0 + $1.total }, fixture.expectedTotal)
        XCTAssertLessThan(
            peakRSS,
            rssBudgetBytes,
            "Peak RSS \(Self.mib(peakRSS)) MiB must stay below \(Self.mib(rssBudgetBytes)) MiB for a 512 MiB Codex rollout"
        )
        XCTAssertLessThan(
            rssGrowth,
            rssGrowthBudgetBytes,
            "Parsing RSS growth \(Self.mib(rssGrowth)) MiB must stay below \(Self.mib(rssGrowthBudgetBytes)) MiB"
        )
        XCTAssertLessThan(elapsed, 20, "512 MiB Codex rollout parse took \(elapsed)s")
    }

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ptb-codex-large-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private struct FixtureStats {
        let fileSize: Int
        let expectedEventCount: Int
        let expectedInput: Int
        let expectedCacheRead: Int
        let expectedOutput: Int
        let expectedTotal: Int
    }

    private func writeLargeCodexRollout(to root: URL) throws -> FixtureStats {
        let file = root.appendingPathComponent("rollout-large.jsonl")
        _ = FileManager.default.createFile(atPath: file.path, contents: nil)
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }

        func write(_ line: String) {
            handle.write(Data((line + "\n").utf8))
        }

        var written = 0
        func writeAndCount(_ line: String) {
            let data = Data((line + "\n").utf8)
            handle.write(data)
            written += data.count
        }

        writeAndCount("""
        {"type":"session_meta","timestamp":"2026-08-01T00:00:00.000Z","payload":{"id":"large-rollout","session_id":"large-rollout"}}
        """)

        let payload = String(repeating: "x", count: 8 * 1024)
        let noise = """
        {"type":"event_msg","timestamp":"2026-08-01T00:00:00.001Z","payload":{"type":"agent_message_delta","delta":"\(payload)"}}
        """
        let noiseBytes = Data((noise + "\n").utf8).count

        var eventCount = 0
        var expectedInput = 0
        var expectedCacheRead = 0
        var expectedOutput = 0
        var cumulativeInput = 0
        var cumulativeCached = 0
        var cumulativeOutput = 0
        var noiseSinceLastToken = 0

        while written < targetBytes {
            if eventCount < 64 && noiseSinceLastToken >= 1024 {
                eventCount += 1
                noiseSinceLastToken = 0

                let lastInput = 1_000 + eventCount
                let lastCached = 100 + eventCount
                let lastOutput = 50 + eventCount
                cumulativeInput += lastInput
                cumulativeCached += lastCached
                cumulativeOutput += lastOutput

                expectedInput += lastInput - lastCached
                expectedCacheRead += lastCached
                expectedOutput += lastOutput

                let second = String(format: "%02d", eventCount % 60)
                writeAndCount("""
                {"type":"event_msg","timestamp":"2026-08-01T00:00:\(second).000Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":\(cumulativeInput),"cached_input_tokens":\(cumulativeCached),"cache_write_input_tokens":0,"output_tokens":\(cumulativeOutput),"reasoning_output_tokens":0,"total_tokens":\(cumulativeInput + cumulativeOutput)},"last_token_usage":{"input_tokens":\(lastInput),"cached_input_tokens":\(lastCached),"cache_write_input_tokens":0,"output_tokens":\(lastOutput),"reasoning_output_tokens":0,"total_tokens":\(lastInput + lastOutput)}}}}
                """)
            } else {
                write(noise)
                written += noiseBytes
                noiseSinceLastToken += 1
            }
        }

        return FixtureStats(
            fileSize: written,
            expectedEventCount: eventCount,
            expectedInput: expectedInput,
            expectedCacheRead: expectedCacheRead,
            expectedOutput: expectedOutput,
            expectedTotal: expectedInput + expectedCacheRead + expectedOutput
        )
    }

    private static func mib(_ bytes: UInt64) -> UInt64 {
        bytes / 1024 / 1024
    }
}

private final class PeakResidentSampler: @unchecked Sendable {
    private let lock = NSLock()
    private var peak: UInt64 = 0
    private var shouldStop = false
    private lazy var thread = Thread { [weak self] in
        self?.run()
    }

    func start() {
        sample()
        thread.start()
    }

    func stop() -> UInt64 {
        lock.lock()
        shouldStop = true
        lock.unlock()

        while !thread.isFinished {
            Thread.sleep(forTimeInterval: 0.005)
        }
        return peak
    }

    private func run() {
        while true {
            lock.lock()
            let done = shouldStop
            lock.unlock()
            if done { return }

            sample()
            usleep(10_000)
        }
    }

    private func sample() {
        let resident = Self.currentResidentBytes()
        lock.lock()
        peak = max(peak, resident)
        lock.unlock()
    }

    static func currentResidentBytes() -> UInt64 {
        var info = mach_task_basic_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info_data_t>.stride / MemoryLayout<natural_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return UInt64(info.resident_size)
    }
}
