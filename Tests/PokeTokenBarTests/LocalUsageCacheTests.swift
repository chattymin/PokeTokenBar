import XCTest
@testable import PokeTokenBar

/// probe 호출 횟수 카운터 — "몇 ms 걸렸나"는 환경마다 흔들리므로 "파일을 다시 열었나"로 계약을 건다.
private final class ProbeCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
    func bump() { lock.lock(); value += 1; lock.unlock() }
}

/// 지정한 파일의 첫 probe 만 실패시키는 시임 — 일시적 I/O 오류를 결정적으로 재현한다.
private final class FlakyProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var pendingFailures: Set<String>
    private var counts: [String: Int] = [:]

    init(failOnceFor names: Set<String>) { pendingFailures = names }

    func callCount(_ name: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        return counts[name] ?? 0
    }

    func probe(_ url: URL) throws -> String? {
        let name = url.lastPathComponent
        lock.lock()
        counts[name, default: 0] += 1
        let shouldFail = pendingFailures.remove(name) != nil
        lock.unlock()
        if shouldFail { throw CocoaError(.fileReadUnknown) }
        return try LocalUsageReader.probeCodexRolloutSessionID(at: url)
    }
}

/// 저장 throttle(60초)·prune(40일)을 결정적으로 넘기기 위한 조작 가능한 시계.
private final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    init(_ start: Date) { value = start }
    var now: Date { lock.lock(); defer { lock.unlock() }; return value }
    func advance(_ seconds: TimeInterval) { lock.lock(); value += seconds; lock.unlock() }
}

/// LocalUsageCache — 파일별 증분 캐시의 핵심 계약을 픽스처 디렉토리로 검증.
/// (재사용/재파싱 판정, 디스크 영속·라운드트립, 40일 prune, 60초 저장 throttle)
final class LocalUsageCacheTests: XCTestCase {
    private var root: URL!
    private var archivedRoot: URL!
    private var cacheFile: URL!

    override func setUpWithError() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("ptb-cache-\(UUID().uuidString)")
        root = base.appendingPathComponent("projects")
        archivedRoot = base.appendingPathComponent("archived")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: archivedRoot, withIntermediateDirectories: true)
        cacheFile = base.appendingPathComponent("usage-cache.json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
    }

    /// Claude 로그 한 줄(assistant + usage) 픽스처.
    private func claudeLine(id: String, output: Int, ts: String = "2026-07-02T01:00:00.000Z") -> String {
        """
        {"type":"assistant","requestId":"r-\(id)","timestamp":"\(ts)","message":{"id":"m-\(id)","model":"claude-opus-4-8","usage":{"input_tokens":10,"output_tokens":\(output),"cache_creation_input_tokens":5,"cache_read_input_tokens":100}}}
        """
    }

    private func codexLine(ts: String, output: Int = 50) -> String {
        """
        {"type":"event_msg","timestamp":"\(ts)","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":1000,"cached_input_tokens":200,"cache_write_input_tokens":0,"output_tokens":\(output),"reasoning_output_tokens":10,"total_tokens":\(1000 + output)}}}}
        """
    }

    private func piLine(id: String, output: Int, ts: String = "2026-07-02T01:00:00.000Z") -> String {
        let milliseconds = (ISO8601Parser.date(from: ts)?.timeIntervalSince1970 ?? 0) * 1_000
        return """
        {"type":"message","id":"\(id)","parentId":null,"timestamp":"\(ts)","message":{"role":"assistant","provider":"test","model":"model","timestamp":\(milliseconds),"usage":{"input":10,"output":\(output),"cacheRead":20,"cacheWrite":0,"reasoning":1,"totalTokens":\(30 + output)}}}
        """
    }

    private func codexStateLine(ts: String, cumulativeInput: Int, cumulativeOutput: Int,
                                lastInput: Int, lastOutput: Int) -> String {
        """
        {"type":"event_msg","timestamp":"\(ts)","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":\(cumulativeInput),"cached_input_tokens":0,"output_tokens":\(cumulativeOutput),"reasoning_output_tokens":0,"total_tokens":\(cumulativeInput + cumulativeOutput)},"last_token_usage":{"input_tokens":\(lastInput),"cached_input_tokens":0,"output_tokens":\(lastOutput),"reasoning_output_tokens":0,"total_tokens":\(lastInput + lastOutput)}}}}
        """
    }

    private func forkedSessionMeta(ts: String) -> String {
        """
        {"type":"session_meta","timestamp":"\(ts)","payload":{"id":"child","forked_from_id":"parent","parent_thread_id":"parent","thread_source":"user"}}
        """
    }

    private func subagentSessionMeta(ts: String) -> String {
        """
        {"type":"session_meta","timestamp":"\(ts)","payload":{"id":"child","session_id":"parent","forked_from_id":"parent","parent_thread_id":"parent","thread_source":"subagent","source":{"subagent":{"thread_spawn":{"parent_thread_id":"parent","depth":1}}}}}
        """
    }

    private func sessionMeta(id: String, ts: String) -> String {
        """
        {"type":"session_meta","timestamp":"\(ts)","payload":{"id":"\(id)","session_id":"\(id)"}}
        """
    }

    private func forkedCodexLines() -> [String] {
        [
            forkedSessionMeta(ts: "2026-07-29T01:00:00.000Z"),
            codexLine(ts: "2026-07-29T01:00:00.010Z", output: 50),
            codexLine(ts: "2026-07-29T01:00:00.020Z", output: 51),
            codexLine(ts: "2026-07-29T01:00:03.000Z", output: 52),
        ]
    }

    @discardableResult
    private func writeFile(_ name: String, lines: [String], mtime: Date? = nil) throws -> URL {
        let url = root.appendingPathComponent(name)
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        if let mtime {
            try FileManager.default.setAttributes([.modificationDate: mtime], ofItemAtPath: url.path)
        }
        return url
    }

    private func makeCache(now: @escaping @Sendable () -> Date = Date.init,
                           probes: ProbeCounter? = nil,
                           probe: (@Sendable (URL) throws -> String?)? = nil,
                           codexRoots: [URL]? = nil, piRoots: [URL]? = nil) -> LocalUsageCache {
        LocalUsageCache(claudeRoot: root,
                        codexRoot: codexRoots == nil ? root : nil,
                        codexRoots: codexRoots, piRoots: piRoots,
                        fileURL: cacheFile, now: now,
                        codexProbe: { url in
                            probes?.bump()
                            if let probe { return try probe(url) }
                            return try LocalUsageReader.probeCodexRolloutSessionID(at: url)
                        })
    }

    private func writeLines(_ lines: [String], to directory: URL, name: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func forkMeta(id: String, parentID: String, ts: String) -> String {
        """
        {"type":"session_meta","timestamp":"\(ts)","payload":{"id":"\(id)","forked_from_id":"\(parentID)","parent_thread_id":"\(parentID)","thread_source":"user"}}
        """
    }

    /// 부모가 사라진 fork 하나 + 조회 윈도우 밖 rollout 두 개(= 내용을 열어봐야 아는 후보).
    private func writeOrphanedForkTree() throws {
        try writeFile("rollout-alpha.jsonl", lines: [
            sessionMeta(id: "alpha", ts: "2026-07-29T01:00:00.000Z"),
            codexStateLine(ts: "2026-07-29T01:00:01.000Z",
                           cumulativeInput: 10, cumulativeOutput: 1, lastInput: 10, lastOutput: 1),
        ], mtime: Date(timeIntervalSince1970: 1_000))
        try writeFile("rollout-beta.jsonl", lines: [
            sessionMeta(id: "beta", ts: "2026-07-29T02:00:00.000Z"),
            codexStateLine(ts: "2026-07-29T02:00:01.000Z",
                           cumulativeInput: 20, cumulativeOutput: 2, lastInput: 20, lastOutput: 2),
        ], mtime: Date(timeIntervalSince1970: 1_000))
        try writeFile("rollout-child.jsonl", lines: orphanedForkLines(lastOutput: 20),
                      mtime: Date(timeIntervalSince1970: 3_000))
    }

    /// 부모가 없는 fork — 시간 fallback 이 첫 이벤트만 replay 로 보고 두 번째는 남긴다.
    /// (`lastOutput` 은 두 자리로만 바꿔 파일 크기가 변하지 않게 한다 — blob 무효화는 mtime·size 기준.)
    private func orphanedForkLines(lastOutput: Int) -> [String] {
        [
            forkMeta(id: "child", parentID: "gone-parent", ts: "2026-07-30T01:00:00.000Z"),
            codexStateLine(ts: "2026-07-30T01:00:05.000Z",
                           cumulativeInput: 100, cumulativeOutput: 10, lastInput: 100, lastOutput: 10),
            codexStateLine(ts: "2026-07-30T01:00:10.000Z",
                           cumulativeInput: 300, cumulativeOutput: 30,
                           lastInput: 200, lastOutput: lastOutput),
        ]
    }

    private let orphanWindow = Date(timeIntervalSince1970: 2_000)

    private let since = Date(timeIntervalSince1970: 0)

    /// mtime·size 불변이면 재파싱하지 않는다 — 내용을 몰래 바꿔도(같은 길이+같은 mtime) 캐시 값이 나온다.
    /// mtime 은 정수 초로 고정 — 서브초 정밀도가 attributesOfItem/resourceValues 간 달라 비교가 깨지는 것 방지.
    func testUnchangedFileIsNotReparsed() async throws {
        let t = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970) - 3600)
        try writeFile("a.jsonl", lines: [claudeLine(id: "1", output: 111)], mtime: t)

        let cache = makeCache()
        let first = await cache.claudeEntries(modifiedSince: since)
        XCTAssertEqual(first.map(\.output), [111])

        // 같은 길이(111→222)·같은 mtime 으로 내용만 교체 → 캐시 히트라면 여전히 111
        try writeFile("a.jsonl", lines: [claudeLine(id: "1", output: 222)], mtime: t)
        let second = await cache.claudeEntries(modifiedSince: since)
        XCTAssertEqual(second.map(\.output), [111], "mtime/size 불변이면 재파싱하면 안 된다")
    }

    /// 프로덕션은 루트를 여러 개 훑는다(CLI 기본 + CLAUDE_CONFIG_DIR + Claude Desktop 임베디드).
    /// 단일 루트만 주면 그 루프가 1회로 단락돼 브랜치가 안 덮이므로, 다중 루트 시임으로 실제 경로를 밟는다.
    func testMultipleRootsAreScannedAndDedupedAcrossRoots() async throws {
        let second = root.deletingLastPathComponent().appendingPathComponent("second-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: second) }

        try writeFile("a.jsonl", lines: [claudeLine(id: "shared", output: 10)])
        try [claudeLine(id: "shared", output: 10), claudeLine(id: "only-second", output: 7)]
            .joined(separator: "\n")
            .write(to: second.appendingPathComponent("b.jsonl"), atomically: true, encoding: .utf8)

        let cache = LocalUsageCache(claudeRoots: [root, second], fileURL: cacheFile)
        let entries = await cache.claudeEntries(modifiedSince: since)

        XCTAssertEqual(Set(entries.map(\.output)), [10, 7], "두 루트가 합산돼야 한다")
        XCTAssertEqual(entries.filter { $0.id == "m-shared|r-shared" }.count, 1,
                       "두 루트에 같은 턴이 있으면 한 번만 세야 한다")

        // 대조군: 두 번째 루트를 빼면 only-second 가 사라진다 — 위 단언이 다중 루트를 실제로 밟았다는 보증.
        let single = LocalUsageCache(claudeRoot: root, fileURL: cacheFile.appendingPathExtension("single"))
        let singleEntries = await single.claudeEntries(modifiedSince: since)
        XCTAssertEqual(singleEntries.count, 1)
    }

    /// mtime 이 바뀌면 재파싱한다.
    func testChangedFileIsReparsed() async throws {
        try writeFile("a.jsonl", lines: [claudeLine(id: "1", output: 111)])
        let cache = makeCache()
        _ = await cache.claudeEntries(modifiedSince: since)

        try writeFile("a.jsonl", lines: [claudeLine(id: "1", output: 999)],
                      mtime: Date().addingTimeInterval(10))
        let second = await cache.claudeEntries(modifiedSince: since)
        XCTAssertEqual(second.map(\.output), [999])
    }

    func testCodexCacheDropsForkedReplayBurst() async throws {
        try writeFile("rollout-child.jsonl", lines: forkedCodexLines())

        let entries = await makeCache().codexEntries(modifiedSince: since)

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].output, 52)
    }

    func testCodexCacheDropsSameStateRerecord() async throws {
        try writeFile("rollout-session.jsonl", lines: [
            #"{"type":"session_meta","timestamp":"2026-07-29T01:00:00.000Z","payload":{"id":"session-a"}}"#,
            codexStateLine(
                ts: "2026-07-29T01:00:01.000Z",
                cumulativeInput: 100, cumulativeOutput: 10,
                lastInput: 100, lastOutput: 10),
            codexStateLine(
                ts: "2026-07-29T01:00:02.000Z",
                cumulativeInput: 100, cumulativeOutput: 10,
                lastInput: 100, lastOutput: 10),
        ])

        let entries = await makeCache().codexEntries(modifiedSince: since)

        XCTAssertEqual(entries.map(\.total), [110])
    }

    /// 활성 세션과 보관 세션에 같은 rollout이 동시에 보이는 이동 중 상태에서도
    /// 파일 경로가 아니라 session/state ID 기준으로 한 번만 집계해야 한다.
    func testCodexCacheDeduplicatesRolloutAcrossActiveAndArchivedRoots() async throws {
        let lines = [
            sessionMeta(id: "moved-session", ts: "2026-07-29T01:00:00.000Z"),
            codexStateLine(
                ts: "2026-07-29T01:00:01.000Z",
                cumulativeInput: 100, cumulativeOutput: 10,
                lastInput: 100, lastOutput: 10),
        ]
        try writeFile("rollout.jsonl", lines: lines)
        _ = try writeLines(lines, to: archivedRoot, name: "rollout.jsonl")

        let entries = await makeCache(codexRoots: [root, archivedRoot])
            .codexEntries(modifiedSince: since)

        XCTAssertEqual(entries.map(\.total), [110], "양쪽 루트의 같은 rollout은 한 번만 집계해야 한다")
    }

    /// Codex의 정상적인 sessions → archived_sessions 이동을 같은 캐시 인스턴스가
    /// 따라가야 한다. 이동 전 경로의 cache blob이 남아 있어도 보관 경로의 새 파일을
    /// 읽고, 이전 경로와 합산하지 않아야 한다.
    func testCodexCacheFollowsRolloutWhenMovedToArchivedRoot() async throws {
        let lines = [
            sessionMeta(id: "archived-session", ts: "2026-07-29T01:00:00.000Z"),
            codexStateLine(
                ts: "2026-07-29T01:00:01.000Z",
                cumulativeInput: 100, cumulativeOutput: 10,
                lastInput: 100, lastOutput: 10),
        ]
        let activeFile = try writeFile("rollout.jsonl", lines: lines)
        let archivedFile = archivedRoot.appendingPathComponent("rollout.jsonl")
        let cache = makeCache(codexRoots: [root, archivedRoot])

        let beforeMove = await cache.codexEntries(modifiedSince: since)
        XCTAssertEqual(beforeMove.map(\.total), [110])

        try FileManager.default.moveItem(at: activeFile, to: archivedFile)

        let afterMove = await cache.codexEntries(modifiedSince: since)
        XCTAssertEqual(afterMove.map(\.total), [110], "rollout 이동 후에도 기존 집계가 유지돼야 한다")
    }

    func testCodexCacheKeepsSubagentFirstTurnWhenParentIsMissing() async throws {
        try writeFile("rollout-subagent.jsonl", lines: [
            subagentSessionMeta(ts: "2026-07-30T01:00:00.000Z"),
            codexStateLine(
                ts: "2026-07-30T01:00:01.000Z",
                cumulativeInput: 50, cumulativeOutput: 5,
                lastInput: 50, lastOutput: 5),
            codexStateLine(
                ts: "2026-07-30T01:00:03.000Z",
                cumulativeInput: 110, cumulativeOutput: 10,
                lastInput: 60, lastOutput: 5),
        ])

        let entries = await makeCache().codexEntries(modifiedSince: since)

        XCTAssertEqual(entries.map(\.total), [55, 65])
        XCTAssertTrue(entries.allSatisfy { $0.id.hasPrefix("codex|child|") })
    }

    func testCodexCacheInvalidatesOutdatedParserVersion() async throws {
        try writeFile("rollout-child.jsonl", lines: forkedCodexLines())

        _ = await makeCache().codexEntries(modifiedSince: since)
        try rewriteCodexCacheAsPriorParserVersion()

        let entries = await makeCache().codexEntries(modifiedSince: since)

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].output, 52)
    }

    private func rewriteCodexCacheAsPriorParserVersion() throws {
        let raw = try Data(contentsOf: cacheFile)
        let plain = (try? (raw as NSData).decompressed(using: .zlib) as Data) ?? raw
        var snapshot = try XCTUnwrap(JSONSerialization.jsonObject(with: plain) as? [String: Any])
        var codex = try XCTUnwrap(snapshot["codex"] as? [String: Any])

        for (path, value) in codex {
            var blob = try XCTUnwrap(value as? [String: Any])
            var rollout = try XCTUnwrap(blob["rollout"] as? [String: Any])
            var events = try XCTUnwrap(rollout["events"] as? [[String: Any]])
            let last = try XCTUnwrap(events.indices.last)
            var event = events[last]
            var entry = try XCTUnwrap(event["entry"] as? [String: Any])
            entry["output"] = 999
            event["entry"] = entry
            events[last] = event
            rollout["events"] = events
            blob["rollout"] = rollout
            codex[path] = blob
        }
        snapshot["codex"] = codex
        snapshot["codexParserVersion"] = 3

        let data = try JSONSerialization.data(withJSONObject: snapshot)
        let compressed = try (data as NSData).compressed(using: .zlib) as Data
        try compressed.write(to: cacheFile, options: .atomic)
    }

    func testCodexCacheLoadsParentOutsideModifiedSinceForSubagentResolution() async throws {
        let old = Date(timeIntervalSince1970: 1_000)
        let recent = Date(timeIntervalSince1970: 3_000)
        try writeFile("old-parent.jsonl", lines: [
            sessionMeta(id: "parent", ts: "2026-07-29T01:00:00.000Z"),
            codexStateLine(
                ts: "2026-07-29T01:00:01.000Z",
                cumulativeInput: 100, cumulativeOutput: 10,
                lastInput: 100, lastOutput: 10),
        ], mtime: old)
        try writeFile("recent-child.jsonl", lines: [
            subagentSessionMeta(ts: "2026-07-30T01:00:00.000Z"),
            sessionMeta(id: "parent", ts: "2026-07-30T01:00:00.001Z"),
            // parent와 prefix가 다르므로 둘 다 실제 subagent usage다.
            codexStateLine(
                ts: "2026-07-30T01:00:01.000Z",
                cumulativeInput: 50, cumulativeOutput: 5,
                lastInput: 50, lastOutput: 5),
            codexStateLine(
                ts: "2026-07-30T01:00:03.000Z",
                cumulativeInput: 110, cumulativeOutput: 10,
                lastInput: 60, lastOutput: 5),
        ], mtime: recent)

        let entries = await makeCache().codexEntries(
            modifiedSince: Date(timeIntervalSince1970: 2_000)
        )

        XCTAssertEqual(entries.map(\.total), [55, 65])
        XCTAssertTrue(entries.allSatisfy { $0.id.hasPrefix("codex|child|") })
    }

    // MARK: 세션 id 인덱스 (부모가 사라진 fork 가 매번 전수 스캔을 유발하지 않도록)

    /// 부모를 못 찾았다는 사실도 상태다 — 같은 인스턴스의 두 번째 새로고침은 파일을 다시 열지 않는다.
    func testCodexOrphanedParentIsNotRescannedOnEveryRefresh() async throws {
        try writeOrphanedForkTree()
        let probes = ProbeCounter()
        let cache = makeCache(probes: probes)

        _ = await cache.codexEntries(modifiedSince: orphanWindow)
        let first = probes.count
        XCTAssertEqual(first, 2, "첫 조회는 윈도우 밖 rollout 두 개를 열어봐야 한다")

        _ = await cache.codexEntries(modifiedSince: orphanWindow)
        XCTAssertEqual(probes.count, first, "두 번째 새로고침은 같은 파일을 다시 열면 안 된다")
    }

    /// 인덱스는 스냅샷에 실려 콜드 스타트(새 인스턴스)에서도 전수 스캔을 막는다.
    func testCodexSessionIndexPersistsAcrossInstances() async throws {
        try writeOrphanedForkTree()
        _ = await makeCache(probes: ProbeCounter()).codexEntries(modifiedSince: orphanWindow)

        let probes = ProbeCounter()
        _ = await makeCache(probes: probes).codexEntries(modifiedSince: orphanWindow)

        XCTAssertEqual(probes.count, 0, "스냅샷의 세션 id 인덱스로 후보를 가려야 한다")
    }

    /// `sessionID == nil`도 완료된 probe 결과다 — 미탐색 상태와 혼동하면 매번 파일을 다시 연다.
    func testCodexNegativeSessionIDProbePersistsAcrossRefreshesAndInstances() async throws {
        try writeOrphanedForkTree()
        try writeFile("rollout-without-session-meta.jsonl", lines: [
            #"{"type":"response_item","timestamp":"2026-07-29T00:00:00.000Z","payload":{"type":"message"}}"#,
        ], mtime: Date(timeIntervalSince1970: 1_000))

        let probes = ProbeCounter()
        let cache = makeCache(probes: probes)
        _ = await cache.codexEntries(modifiedSince: orphanWindow)
        let first = probes.count
        XCTAssertEqual(first, 3)

        _ = await cache.codexEntries(modifiedSince: orphanWindow)
        XCTAssertEqual(probes.count, first, "negative probe 결과가 같은 인스턴스에서 재사용돼야 한다")

        let restoredProbes = ProbeCounter()
        _ = await makeCache(probes: restoredProbes).codexEntries(modifiedSince: orphanWindow)
        XCTAssertEqual(restoredProbes.count, 0, "negative probe 결과가 스냅샷에서도 복원돼야 한다")
    }

    /// 읽기 실패는 "세션 id 없음"과 다르다 — 인덱스에 굳히지 않고 다음 새로고침에 다시 시도한다.
    /// 대신 같은 새로고침 안에서는 고아 부모가 여럿이어도 그 파일을 한 번만 연다.
    func testCodexProbeReadFailureIsRetriedInsteadOfPersisted() async throws {
        try writeOrphanedForkTree()
        // 두 번째 고아 부모 — 실패한 파일을 부모 id 마다 다시 열지 않는지 보기 위해.
        try writeFile("rollout-child2.jsonl", lines: [
            forkMeta(id: "child2", parentID: "gone-parent-2", ts: "2026-07-30T02:00:00.000Z"),
            codexStateLine(ts: "2026-07-30T02:00:05.000Z",
                           cumulativeInput: 10, cumulativeOutput: 1, lastInput: 10, lastOutput: 1),
        ], mtime: Date(timeIntervalSince1970: 3_000))

        let flaky = FlakyProbe(failOnceFor: ["rollout-alpha.jsonl"])
        let cache = makeCache(probe: flaky.probe)

        _ = await cache.codexEntries(modifiedSince: orphanWindow)
        XCTAssertEqual(flaky.callCount("rollout-alpha.jsonl"), 1,
                       "같은 새로고침 안에서 실패한 파일을 다시 열면 안 된다")

        _ = await cache.codexEntries(modifiedSince: orphanWindow)
        XCTAssertEqual(flaky.callCount("rollout-alpha.jsonl"), 2,
                       "읽기 실패는 인덱스에 굳지 않는다 — 다음 새로고침에 재시도")
        XCTAssertEqual(flaky.callCount("rollout-beta.jsonl"), 1,
                       "성공한 결과는 인덱스에서 재사용된다")

        _ = await cache.codexEntries(modifiedSince: orphanWindow)
        XCTAssertEqual(flaky.callCount("rollout-alpha.jsonl"), 2,
                       "재시도가 성공한 뒤에는 다시 열지 않는다")
    }

    /// 실패한 probe 결과는 디스크 스냅샷에도 남지 않는다 — 새 인스턴스가 그 파일을 다시 연다.
    func testCodexProbeReadFailureIsNotPersistedToSnapshot() async throws {
        try writeOrphanedForkTree()

        let flaky = FlakyProbe(failOnceFor: ["rollout-alpha.jsonl"])
        _ = await makeCache(probe: flaky.probe).codexEntries(modifiedSince: orphanWindow)

        // 같은 스냅샷을 읽는 새 인스턴스(콜드 스타트). 이번 probe 는 실패하지 않는다.
        let restored = FlakyProbe(failOnceFor: [])
        _ = await makeCache(probe: restored.probe).codexEntries(modifiedSince: orphanWindow)

        XCTAssertEqual(restored.callCount("rollout-alpha.jsonl"), 1,
                       "실패는 스냅샷에 남지 않는다 — 새 인스턴스가 다시 시도해야 한다")
        XCTAssertEqual(restored.callCount("rollout-beta.jsonl"), 0,
                       "성공한 결과는 스냅샷에서 복원된다")
    }

    /// 인덱스 버전이 오르면 인덱스만 다시 만든다 — parsed rollout blob 은 그대로 재사용한다.
    func testCodexSessionIndexVersionBumpRebuildsIndexWithoutReparsingBlobs() async throws {
        // prune(40일)에 걸리지 않도록 최근 mtime 을 쓰되, alpha 는 조회 윈도우 밖에 둔다.
        let second = floor(Date().timeIntervalSince1970)
        let outsideWindow = Date(timeIntervalSince1970: second - 7_200)
        let insideWindow = Date(timeIntervalSince1970: second - 3_600)
        let window = Date(timeIntervalSince1970: second - 5_400)
        try writeFile("rollout-alpha.jsonl", lines: [
            sessionMeta(id: "alpha", ts: "2026-07-29T01:00:00.000Z"),
            codexStateLine(ts: "2026-07-29T01:00:01.000Z",
                           cumulativeInput: 10, cumulativeOutput: 1, lastInput: 10, lastOutput: 1),
        ], mtime: outsideWindow)
        try writeFile("rollout-child.jsonl", lines: orphanedForkLines(lastOutput: 20),
                      mtime: insideWindow)

        _ = await makeCache().codexEntries(modifiedSince: window)
        try downgradeCodexSessionIndexVersion()

        // blob 이 살아 있다면 mtime·size 가 같은 이 교체는 무시된다(220 유지).
        try writeFile("rollout-child.jsonl", lines: orphanedForkLines(lastOutput: 30),
                      mtime: insideWindow)

        let probes = ProbeCounter()
        let entries = await makeCache(probes: probes).codexEntries(modifiedSince: window)

        XCTAssertEqual(probes.count, 1, "구버전 인덱스 항목은 신뢰할 수 없으므로 다시 probe 한다")
        XCTAssertEqual(entries.map(\.total), [220], "blob 은 재사용된다 — 전체 재파싱이 아니다")
    }

    private func downgradeCodexSessionIndexVersion() throws {
        let raw = try Data(contentsOf: cacheFile)
        let plain = (try? (raw as NSData).decompressed(using: .zlib) as Data) ?? raw
        var snapshot = try XCTUnwrap(JSONSerialization.jsonObject(with: plain) as? [String: Any])
        XCTAssertFalse(
            (snapshot["codexSessionIDs"] as? [String: Any] ?? [:]).isEmpty,
            "다운그레이드 대상 인덱스가 비어 있으면 테스트가 아무것도 검증하지 못한다")
        snapshot["codexSessionIndexVersion"] = 1

        let data = try JSONSerialization.data(withJSONObject: snapshot)
        let compressed = try (data as NSData).compressed(using: .zlib) as Data
        try compressed.write(to: cacheFile, options: .atomic)
    }

    /// 인덱스는 blob 과 같은 `(path, mtime, size)` 로만 무효화된다 — 바뀐 파일만 다시 연다.
    func testCodexSessionIndexReprobesOnlyChangedFile() async throws {
        try writeOrphanedForkTree()
        _ = await makeCache(probes: ProbeCounter()).codexEntries(modifiedSince: orphanWindow)

        // 윈도우 밖에 머물도록 mtime 은 과거로 유지한 채 내용(크기)만 바꾼다.
        try writeFile("rollout-alpha.jsonl", lines: [
            sessionMeta(id: "alpha-renamed-session", ts: "2026-07-29T01:00:00.000Z"),
            codexStateLine(ts: "2026-07-29T01:00:01.000Z",
                           cumulativeInput: 10, cumulativeOutput: 1, lastInput: 10, lastOutput: 1),
        ], mtime: Date(timeIntervalSince1970: 1_500))

        let probes = ProbeCounter()
        _ = await makeCache(probes: probes).codexEntries(modifiedSince: orphanWindow)

        XCTAssertEqual(probes.count, 1, "내용이 바뀐 파일만 다시 열어야 한다")
    }

    /// blob 은 40일 prune 대상이지만 인덱스는 아니다 — 오래된 부모를 찾는 게 인덱스의 목적이다.
    /// (픽스처 mtime 이 1970 이라 첫 저장에서 Codex blob 은 전부 prune 된다.)
    func testCodexSessionIndexOutlivesBlobPrune() async throws {
        try writeOrphanedForkTree()
        _ = await makeCache(probes: ProbeCounter()).codexEntries(modifiedSince: orphanWindow)

        // blob 이 살아 있었다면 mtime·size 가 같은 이 교체는 무시된다(220 유지). 값이 바뀌면 prune 되었다는 뜻.
        try writeFile("rollout-child.jsonl", lines: orphanedForkLines(lastOutput: 30),
                      mtime: Date(timeIntervalSince1970: 3_000))

        let probes = ProbeCounter()
        let entries = await makeCache(probes: probes).codexEntries(modifiedSince: orphanWindow)

        XCTAssertEqual(entries.map(\.total), [230], "blob 은 prune 되어 재파싱되어야 한다")
        XCTAssertEqual(probes.count, 0, "blob 이 사라져도 인덱스만으로 후보를 가려야 한다")
    }

    /// 사라진 rollout 의 인덱스 항목은 제거되고, 그 제거가 디스크에도 반영된다(dirty 처리).
    func testCodexSessionIndexDropsDeletedFiles() async throws {
        try writeOrphanedForkTree()
        let clock = Clock(Date(timeIntervalSince1970: 10_000_000))
        let cache = makeCache(now: { clock.now })
        _ = await cache.codexEntries(modifiedSince: orphanWindow)
        let indexed = await cache.codexSessionIndexCount()
        XCTAssertEqual(indexed, 3)

        try FileManager.default.removeItem(at: root.appendingPathComponent("rollout-alpha.jsonl"))
        clock.advance(120)   // 저장 throttle(60초) 통과
        _ = await cache.codexEntries(modifiedSince: orphanWindow)

        let afterDelete = await cache.codexSessionIndexCount()
        XCTAssertEqual(afterDelete, 2)
        let persisted = await makeCache(now: { clock.now }).codexSessionIndexCount()
        XCTAssertEqual(persisted, 2, "제거가 스냅샷에도 반영돼야 한다")
    }

    /// 부모 두 턴을 그대로 복사한 fork. 시간 fallback 은 첫 이벤트만 replay 로 보므로(간격 5초)
    /// 부모를 실제로 찾았을 때만 두 번째 replay 까지 잘려 own turn 하나(330)만 남는다.
    private func writeReplayingFork(name: String = "rollout-fork.jsonl") throws {
        try writeFile(name, lines: [
            forkMeta(id: "fork", parentID: "P-123", ts: "2026-07-30T01:00:00.000Z"),
            codexStateLine(ts: "2026-07-30T01:00:05.000Z",
                           cumulativeInput: 100, cumulativeOutput: 10, lastInput: 100, lastOutput: 10),
            codexStateLine(ts: "2026-07-30T01:00:10.000Z",
                           cumulativeInput: 300, cumulativeOutput: 30, lastInput: 200, lastOutput: 20),
            codexStateLine(ts: "2026-07-30T01:00:15.000Z",
                           cumulativeInput: 600, cumulativeOutput: 60, lastInput: 300, lastOutput: 30),
        ], mtime: Date(timeIntervalSince1970: 3_000))
    }

    private func writeReplayedParent(name: String) throws {
        try writeFile(name, lines: [
            sessionMeta(id: "P-123", ts: "2026-07-29T01:00:00.000Z"),
            codexStateLine(ts: "2026-07-29T01:00:01.000Z",
                           cumulativeInput: 100, cumulativeOutput: 10, lastInput: 100, lastOutput: 10),
            codexStateLine(ts: "2026-07-29T01:00:03.000Z",
                           cumulativeInput: 300, cumulativeOutput: 30, lastInput: 200, lastOutput: 20),
        ], mtime: Date(timeIntervalSince1970: 1_000))
    }

    /// 파일명 힌트가 빗나가도(이름엔 부모 id, 내용은 다른 세션) 진짜 부모 탐색을 멈추지 않는다.
    func testCodexStaleFilenameHintDoesNotBlockContentProbe() async throws {
        try writeFile("rollout-P-123.jsonl", lines: [   // 이름만 부모 id 를 담은 미끼
            sessionMeta(id: "decoy-session", ts: "2026-07-29T00:00:00.000Z"),
        ], mtime: Date(timeIntervalSince1970: 1_000))
        try writeReplayedParent(name: "rollout-real.jsonl")   // 진짜 부모 — 이름엔 id 가 없다
        try writeReplayingFork()

        let entries = await makeCache().codexEntries(modifiedSince: orphanWindow)

        XCTAssertEqual(entries.map(\.total), [330], "미끼에서 멈추면 replay 220 이 그대로 남는다")
    }

    /// 부모가 나중에 복구돼도 찾아야 한다 — 부정 결과를 부모 id 단위로 굳히면 안 되는 이유.
    func testCodexRestoredParentIsFoundAfterNegativeProbe() async throws {
        let clock = Clock(Date(timeIntervalSince1970: 10_000_000))
        try writeReplayingFork()
        let cache = makeCache(now: { clock.now })

        let beforeRestore = await cache.codexEntries(modifiedSince: orphanWindow)
        XCTAssertEqual(beforeRestore.map(\.total).sorted(), [220, 330], "부모가 없으면 시간 fallback")

        try writeReplayedParent(name: "rollout-real.jsonl")
        clock.advance(120)

        let afterRestore = await cache.codexEntries(modifiedSince: orphanWindow)
        XCTAssertEqual(afterRestore.map(\.total), [330], "복구된 부모를 다시 찾아야 한다")
    }

    func testCodexParsedRolloutCacheRoundTripsAcrossInstances() async throws {
        let mtime = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970) - 3_600)
        let lines = [
            sessionMeta(id: "session-a", ts: "2026-07-30T01:00:00.000Z"),
            codexStateLine(
                ts: "2026-07-30T01:00:01.000Z",
                cumulativeInput: 100, cumulativeOutput: 10,
                lastInput: 100, lastOutput: 10),
        ]
        try writeFile("rollout-session.jsonl", lines: lines, mtime: mtime)

        let first = await makeCache().codexEntries(modifiedSince: since)
        XCTAssertEqual(first.map(\.total), [110])

        // 같은 길이와 mtime을 유지한 채 10→20으로 바꿔도 새 인스턴스는 persisted rollout을 사용한다.
        let changed = [
            sessionMeta(id: "session-a", ts: "2026-07-30T01:00:00.000Z"),
            codexStateLine(
                ts: "2026-07-30T01:00:01.000Z",
                cumulativeInput: 100, cumulativeOutput: 20,
                lastInput: 100, lastOutput: 20),
        ]
        try writeFile("rollout-session.jsonl", lines: changed, mtime: mtime)

        let second = await makeCache().codexEntries(modifiedSince: since)
        XCTAssertEqual(second.map(\.total), [110])
    }

    /// 디스크 영속: 새 인스턴스(콜드 스타트 시뮬레이션)가 스냅샷을 로드해 같은 결과를 낸다.
    func testDiskRoundTripAcrossInstances() async throws {
        let t = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970) - 3600)
        try writeFile("a.jsonl", lines: [claudeLine(id: "1", output: 42)], mtime: t)
        let c1 = makeCache()
        _ = await c1.claudeEntries(modifiedSince: since)
        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheFile.path), "스냅샷이 저장돼야 한다")

        // 내용을 몰래 바꿔도(길이·mtime 동일) 새 인스턴스가 디스크 캐시를 쓰면 42 유지
        try writeFile("a.jsonl", lines: [claudeLine(id: "1", output: 43)], mtime: t)
        let c2 = makeCache()
        let entries = await c2.claudeEntries(modifiedSince: since)
        XCTAssertEqual(entries.map(\.output), [42], "새 인스턴스가 디스크 스냅샷을 재사용해야 한다")
    }

    /// 40일보다 오래된 blob 은 저장 시 prune 되어 스냅샷에서 빠진다.
    func testPruneDropsBlobsOlderThan40Days() async throws {
        let old = Date().addingTimeInterval(-45 * 86400)
        try writeFile("old.jsonl", lines: [claudeLine(id: "o", output: 1)], mtime: old)
        try writeFile("new.jsonl", lines: [claudeLine(id: "n", output: 2)])

        let cache = makeCache()
        let entries = await cache.claudeEntries(modifiedSince: since)
        XCTAssertEqual(Set(entries.map(\.output)), [1, 2], "조회 자체는 둘 다 반환")

        let raw = try Data(contentsOf: cacheFile)
        let plain = (try? (raw as NSData).decompressed(using: .zlib) as Data) ?? raw
        let snap = String(decoding: plain, as: UTF8.self)
        XCTAssertFalse(snap.contains("old.jsonl"), "45일 지난 blob 은 스냅샷에서 prune")
        XCTAssertTrue(snap.contains("new.jsonl"))
    }

    /// 저장 throttle: 60초 내 재저장은 생략, 60초 경과 후 저장된다 (주입 clock 으로 결정적).
    func testSaveThrottle60s() async throws {
        nonisolated(unsafe) var fakeNow = Date(timeIntervalSince1970: 1_700_000_000)
        let cache = makeCache(now: { fakeNow })

        try writeFile("a.jsonl", lines: [claudeLine(id: "1", output: 1)], mtime: fakeNow)
        _ = await cache.claudeEntries(modifiedSince: since)   // 첫 저장
        let firstSnap = try Data(contentsOf: cacheFile)

        // 30초 뒤 파일 변경 → dirty 지만 throttle 로 저장 생략
        fakeNow = fakeNow.addingTimeInterval(30)
        try writeFile("a.jsonl", lines: [claudeLine(id: "1", output: 2)], mtime: fakeNow)
        _ = await cache.claudeEntries(modifiedSince: since)
        XCTAssertEqual(try Data(contentsOf: cacheFile), firstSnap, "60초 내 재저장은 생략")

        // 61초 경과 → 저장됨
        fakeNow = fakeNow.addingTimeInterval(61)
        _ = await cache.claudeEntries(modifiedSince: since)
        XCTAssertNotEqual(try Data(contentsOf: cacheFile), firstSnap, "throttle 해제 후 저장")
    }

    /// modifiedSince 이전 파일은 아예 수집하지 않는다.
    func testModifiedSinceFilters() async throws {
        try writeFile("old.jsonl", lines: [claudeLine(id: "o", output: 1)],
                      mtime: Date().addingTimeInterval(-10 * 86400))
        try writeFile("new.jsonl", lines: [claudeLine(id: "n", output: 2)])
        let cache = makeCache()
        let entries = await cache.claudeEntries(modifiedSince: Date().addingTimeInterval(-86400))
        XCTAssertEqual(entries.map(\.output), [2])
    }

    /// 구버전 평문 JSON 캐시(압축 도입 전)도 로드된다 — 업그레이드 시 콜드 스타트 재발 방지.
    func testLegacyPlainJSONCacheLoads() async throws {
        let t = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970) - 3600)
        try writeFile("a.jsonl", lines: [claudeLine(id: "1", output: 42)], mtime: t)
        _ = await makeCache().claudeEntries(modifiedSince: since)   // 압축 스냅샷 저장

        // 압축 해제해 평문으로 다운그레이드(구버전 캐시 파일 시뮬레이션)
        let raw = try Data(contentsOf: cacheFile)
        let plain = try (raw as NSData).decompressed(using: .zlib) as Data
        try plain.write(to: cacheFile)

        // 내용을 몰래 바꿔도(길이·mtime 동일) 평문 스냅샷이 로드되면 42 유지
        try writeFile("a.jsonl", lines: [claudeLine(id: "1", output: 43)], mtime: t)
        let entries = await makeCache().claudeEntries(modifiedSince: since)
        XCTAssertEqual(entries.map(\.output), [42], "평문(구버전) 캐시가 로드돼야 한다")
    }

    /// 압축 저장 — 스냅샷이 실제로 zlib 이고 평문 대비 작다.
    func testSnapshotIsCompressed() async throws {
        let t = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970) - 3600)
        try writeFile("a.jsonl", lines: (1...50).map { claudeLine(id: "\($0)", output: $0) }, mtime: t)
        _ = await makeCache().claudeEntries(modifiedSince: since)
        let raw = try Data(contentsOf: cacheFile)
        let plain = try (raw as NSData).decompressed(using: .zlib) as Data   // zlib 아니면 throw
        XCTAssertLessThan(raw.count, plain.count, "압축본이 평문보다 작아야 한다")
    }

    /// 포매터 — grouped/cost/costCompact 경계값(메뉴바·팝오버 표기 계약).
    ///
    /// `grouped` 는 로케일을 명시해 단언한다. 기본값(`Locale.current`)으로 두면 쉼표를 쓰지 않는
    /// 지역 설정의 기여자 머신에서만 빨갛게 뜬다(`253 412 890` — PR #160 보고). CI(en_US)와
    /// 국내 머신(ko_KR)은 둘 다 쉼표라 이 실패를 영영 못 본다.
    /// cost/costCompact/percent 는 `String(format:)` 이라 로케일과 무관하다.
    func testFormatterEdges() {
        XCTAssertEqual(TokenFormatter.grouped(253_412_890, locale: Locale(identifier: "en_US")), "253,412,890")
        // 구분기호가 지역 설정을 따르는지 — locale 인자가 무시되면 여기서 걸린다.
        XCTAssertEqual(TokenFormatter.grouped(253_412_890, locale: Locale(identifier: "es_ES")), "253.412.890")
        XCTAssertEqual(TokenFormatter.cost(48.104), "$48.10")
        XCTAssertEqual(TokenFormatter.costCompact(9.54), "$9.5")     // < 100 → 소수 1자리
        XCTAssertEqual(TokenFormatter.costCompact(311.4), "$311")    // < 10K → 정수
        XCTAssertEqual(TokenFormatter.costCompact(12_340), "$12.3K") // ≥ 10K → K
        XCTAssertEqual(TokenFormatter.percent(88), "88%")
        XCTAssertEqual(TokenFormatter.percent(88.35), "88.3%")
    }

    /// 날짜 유틸 — 주/월 경계와 monthKey (집계 윈도우 계산의 기반).
    func testDateHelpers() {
        var c = Calendar.current
        c.timeZone = .current
        let d = c.date(from: DateComponents(year: 2026, month: 7, day: 2, hour: 15))!
        let som = LocalUsageReader.startOfMonth(d)
        XCTAssertEqual(c.dateComponents([.year, .month, .day], from: som).day, 1)
        XCTAssertEqual(c.dateComponents([.month], from: som).month, 7)
        let sow = LocalUsageReader.startOfWeek(d)
        XCTAssertLessThanOrEqual(sow, d)
        XCTAssertLessThan(d.timeIntervalSince(sow), 7 * 86400)
        XCTAssertEqual(LocalUsageReader.monthKey(d), "2026-07")
    }

    /// Codex 파싱 경로 + 세션 모델 감지(turn_context.model) — cacheRead=cached, input=총-캐시.
    func testCodexEntriesParseModelAndCachedInput() async throws {
        let lines = [
            #"{"timestamp":"2026-07-02T01:00:00.000Z","payload":{"type":"turn_context","model":"gpt-5.5-codex"}}"#,
            #"{"timestamp":"2026-07-02T01:01:00.000Z","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"cached_input_tokens":80,"output_tokens":7}}}}"#,
        ]
        try writeFile("rollout-1.jsonl", lines: lines)
        let cache = makeCache()
        let entries = await cache.codexEntries(modifiedSince: since)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].model, "gpt-5.5-codex")
        XCTAssertEqual(entries[0].input, 20)      // 100 - 80
        XCTAssertEqual(entries[0].cacheRead, 80)
        XCTAssertEqual(entries[0].output, 7)
        XCTAssertEqual(entries[0].cacheWrite, 0)
    }

    /// 월초 경계 회귀: 이번 주가 지난달로 넘어가는 시점(2026년 12개월 중 11개월)엔 enrichment 스캔
    /// 하한이 monthStart 면 지난달에 수정된 '이번 주' 세션 파일이 mtime 필터에서 빠져 주간 합계가
    /// 과소집계된다. enrichmentScanStart(=weekStart 등 더 이른 시작)를 하한으로 써야 잡힌다.
    /// (실제 mtime 필터를 밟는 통합 테스트 — 순수 경로만 봤다면 못 걸렀을 결함 조건을 재현.)
    func testEnrichmentScanStartCatchesWeekStraddlingMonthBoundary() async throws {
        let cal = Calendar.current
        // 이번 주 시작이 지난달로 넘어가는 '월초' 시각을 하나 찾는다(로케일 firstWeekday 무관 결정적).
        let base = cal.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 12))!
        var straddle: Date?
        for offset in 0..<14 {
            guard let candidate = cal.date(byAdding: .month, value: offset, to: base) else { continue }
            if LocalUsageReader.startOfWeek(candidate) < LocalUsageReader.startOfMonth(candidate) {
                straddle = candidate; break
            }
        }
        let now = try XCTUnwrap(straddle, "이번 주가 지난달로 straddle 하는 월초를 못 찾음")
        let monthStart = LocalUsageReader.startOfMonth(now)
        let weekStart = LocalUsageReader.startOfWeek(now)
        XCTAssertLessThan(weekStart, monthStart, "전제: 이번 주가 지난달로 넘어간다")

        // 이번 주에 속하지만 지난달인 날의 세션 — 그 이후 수정 안 됨(파일 mtime = 그날).
        let fmt = LocalUsageReader.localDayFormatter()
        let straddleDay = weekStart.addingTimeInterval(3600)   // weekStart 직후(지난달·이번 주)
        let ts = ISO8601DateFormatter().string(from: straddleDay)
        try writeFile("straddle.jsonl", lines: [claudeLine(id: "s", output: 500, ts: ts)], mtime: straddleDay)

        let cache = makeCache(now: { now })
        // (버그 조건) monthStart 하한 → 지난달 mtime 파일이 필터에서 빠진다.
        let monthScoped = await cache.claudeEntries(modifiedSince: monthStart)
        XCTAssertTrue(monthScoped.isEmpty, "monthStart 하한은 지난달에 수정된 이번 주 세션을 놓친다")

        // (수정) enrichmentScanStart 하한 → 포함되고, 이번 주 합계에 반영된다.
        let fixed = await cache.claudeEntries(
            modifiedSince: LocalUsageReader.enrichmentScanStart(now: now))
        XCTAssertEqual(fixed.count, 1, "enrichmentScanStart 는 이번 주 세션을 포함해야 한다")
        let week = LocalUsageReader.period(
            entries: fixed, periodKey: "w",
            fromDay: fmt.string(from: weekStart), toDay: fmt.string(from: now))
        XCTAssertGreaterThan(week.totalTokens, 0, "이번 주 합계에 반영돼야 한다")
    }

    func testPiCacheInvalidatesGrowingFilesAndDedupsAcrossRoots() async throws {
        let second = root.deletingLastPathComponent().appendingPathComponent("pi-second")
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        let shared = piLine(id: "shared", output: 10)
        try writeFile("pi-a.jsonl", lines: [shared, piLine(id: "a", output: 20)])
        try [shared, piLine(id: "b", output: 30)].joined(separator: "\n")
            .write(to: second.appendingPathComponent("pi-b.jsonl"), atomically: true, encoding: .utf8)

        let cache = makeCache(piRoots: [root, second])
        let first = await cache.piEntries(modifiedSince: since)
        XCTAssertEqual(Set(first.map(\.id)), ["shared", "a", "b"])

        try writeFile("pi-a.jsonl", lines: [
            shared, piLine(id: "a", output: 20), piLine(id: "grown", output: 40),
        ])
        let grown = await cache.piEntries(modifiedSince: since)
        XCTAssertEqual(Set(grown.map(\.id)), ["shared", "a", "b", "grown"])
    }

    func testPiCacheRoundTripsAcrossInstances() async throws {
        let mtime = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970) - 3_600)
        try writeFile("pi.jsonl", lines: [piLine(id: "turn", output: 11)], mtime: mtime)
        let first = await makeCache(piRoots: [root]).piEntries(modifiedSince: since)
        XCTAssertEqual(first.map(\.output), [11])

        // Same signature, different same-width payload: a new actor must use the persisted blob.
        try writeFile("pi.jsonl", lines: [piLine(id: "turn", output: 22)], mtime: mtime)
        let second = await makeCache(piRoots: [root]).piEntries(modifiedSince: since)
        XCTAssertEqual(second.map(\.output), [11])
    }

    func testPiReadFailureKeepsOldBlobAndRetriesNextRefresh() async throws {
        let file = try writeFile("pi.jsonl", lines: [piLine(id: "turn", output: 10)])
        let cache = makeCache(piRoots: [root])
        let initial = await cache.piEntries(modifiedSince: since)
        XCTAssertEqual(initial.map(\.output), [10])

        try FileManager.default.removeItem(at: file)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        let duringFailure = await cache.piEntries(modifiedSince: since)
        XCTAssertEqual(duringFailure.map(\.output), [10],
                       "transient read failure should retain the previous blob")

        try FileManager.default.removeItem(at: file)
        try writeFile("pi.jsonl", lines: [piLine(id: "turn", output: 20)])
        let restored = await cache.piEntries(modifiedSince: since)
        XCTAssertEqual(restored.map(\.output), [20],
                       "failed signature must not be cached; the restored file should be retried")
    }

    func testPiCacheInvalidatesOutdatedOrMissingParserVersion() async throws {
        try writeFile("pi.jsonl", lines: [piLine(id: "turn", output: 10)])
        _ = await makeCache(piRoots: [root]).piEntries(modifiedSince: since)

        let raw = try Data(contentsOf: cacheFile)
        let plain = (try? (raw as NSData).decompressed(using: .zlib) as Data) ?? raw
        var snapshot = try XCTUnwrap(JSONSerialization.jsonObject(with: plain) as? [String: Any])
        var pi = try XCTUnwrap(snapshot["pi"] as? [String: Any])
        for (path, value) in pi {
            var blob = try XCTUnwrap(value as? [String: Any])
            var entries = try XCTUnwrap(blob["entries"] as? [[String: Any]])
            entries[0]["output"] = 999
            blob["entries"] = entries
            pi[path] = blob
        }
        snapshot["pi"] = pi
        snapshot["piParserVersion"] = 1 // v1 added reasoning to output; v2 must reparse this blob.
        let changed = try JSONSerialization.data(withJSONObject: snapshot)
        let compressed = try (changed as NSData).compressed(using: .zlib) as Data
        try compressed.write(to: cacheFile, options: .atomic)

        let entries = await makeCache(piRoots: [root]).piEntries(modifiedSince: since)
        XCTAssertEqual(entries.map(\.output), [10], "v1 Pi blobs must be invalidated and reparsed")
    }
}
