import XCTest
@testable import PokeTokenBar

/// LocalUsageCache — 파일별 증분 캐시의 핵심 계약을 픽스처 디렉토리로 검증.
/// (재사용/재파싱 판정, 디스크 영속·라운드트립, 40일 prune, 60초 저장 throttle)
final class LocalUsageCacheTests: XCTestCase {
    private var root: URL!
    private var cacheFile: URL!

    override func setUpWithError() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("ptb-cache-\(UUID().uuidString)")
        root = base.appendingPathComponent("projects")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
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

    private func codexStateLine(ts: String, cumulativeInput: Int, cumulativeOutput: Int,
                                lastInput: Int, lastOutput: Int) -> String {
        """
        {"type":"event_msg","timestamp":"\(ts)","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":\(cumulativeInput),"cached_input_tokens":0,"output_tokens":\(cumulativeOutput),"reasoning_output_tokens":0,"total_tokens":\(cumulativeInput + cumulativeOutput)},"last_token_usage":{"input_tokens":\(lastInput),"cached_input_tokens":0,"output_tokens":\(lastOutput),"reasoning_output_tokens":0,"total_tokens":\(lastInput + lastOutput)}}}}
        """
    }

    private func forkedSessionMeta(ts: String) -> String {
        """
        {"type":"session_meta","timestamp":"\(ts)","payload":{"id":"child","forked_from_id":"parent","parent_thread_id":"parent","thread_source":"subagent"}}
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

    private func makeCache(now: @escaping @Sendable () -> Date = Date.init) -> LocalUsageCache {
        LocalUsageCache(claudeRoot: root, codexRoot: root, fileURL: cacheFile, now: now)
    }

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
            var entries = try XCTUnwrap(blob["entries"] as? [[String: Any]])
            if var replay = entries.first {
                replay["id"] = "codex|legacy|\(path)"
                entries.append(replay)
            }
            blob["entries"] = entries
            codex[path] = blob
        }
        snapshot["codex"] = codex
        snapshot["codexParserVersion"] = 2

        let data = try JSONSerialization.data(withJSONObject: snapshot)
        let compressed = try (data as NSData).compressed(using: .zlib) as Data
        try compressed.write(to: cacheFile, options: .atomic)
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
    func testFormatterEdges() {
        XCTAssertEqual(TokenFormatter.grouped(253_412_890), "253,412,890")
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
}
