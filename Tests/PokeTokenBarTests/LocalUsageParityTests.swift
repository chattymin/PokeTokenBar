import XCTest
@testable import PokeTokenBar

// keychain/네트워크 의존 없이 한도 provider 를 비활성화하는 스텁(통합 파이프라인 검증용).
private struct NoClaudeLimits: ClaudeLimitsProviding {
    func fetch(allowKeychainPrompt: Bool) async throws -> LimitStatus { throw LimitsError.keychainInteractionNotAllowed }
}
private struct NoCodexLimits: CodexLimitsProviding {
    func fetch() async throws -> CodexRateLimitStatus? { nil }
}

/// probe 호출 횟수 계측기 — 시간이 아니라 "파일을 다시 열었나"가 계약이다.
private final class ProbeMeter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
    func bump() { lock.lock(); value += 1; lock.unlock() }
}

// 임시 parity 검증 — 실제 ~/.claude, ~/.codex 로그로 집계해 콘솔 출력 → ccusage 와 수동 대조용.
// (CI 비결정적이므로 환경변수 PTB_PARITY=1 일 때만 실행)
final class LocalUsageParityTests: XCTestCase {

    /// 실제 LocalProvider 로 UsageStore.refresh 전체 파이프라인을 돌려 기존 기능 회귀 검증.
    @MainActor
    func testFullRefreshPipelineWithRealProviders() async throws {
        guard ProcessInfo.processInfo.environment["PTB_PARITY"] == "1" else { throw XCTSkip("PTB_PARITY != 1") }
        let store = UsageStore(
            providers: [LocalClaudeProvider(), LocalCodexProvider()],
            claudeLimitsProvider: NoClaudeLimits(),
            codexLimitsProvider: NoCodexLimits(),
            autoRefresh: false)
        await store.refresh(scheduleEmptyRetry: false)
        print("PARITY-PIPE today=\(store.todayTotalTokens) cost=\(String(format: "%.2f", store.todayCostTotal)) menu=[\(store.menuTitle)] week=\(store.weekTotalTokens) month=\(store.monthTotalTokens) snapshots=\(store.snapshots.count) burnTier=\(store.burnTier) stale=\(store.isStale) err=\(store.lastErrorDescription ?? "none")")
        for s in store.snapshots {
            print("PARITY-PIPE snapshot \(s.providerID): today=\(s.todayTotalTokens) block=\(s.activeBlock?.totalTokens ?? -1) week=\(s.weekTotal?.totalTokens ?? -1) month=\(s.monthTotal?.totalTokens ?? -1)")
        }
        // 회귀 가드: 파이프라인이 실제 값을 산출하고 에러가 없어야 한다.
        XCTAssertGreaterThan(store.todayTotalTokens, 0, "오늘 토큰이 0 — 파이프라인 단절")
        XCTAssertFalse(store.snapshots.isEmpty, "스냅샷 없음")
        XCTAssertNotNil(store.lastUpdated, "lastUpdated 미설정")
        XCTAssertNil(store.lastErrorDescription, "provider 에러 발생")
        XCTAssertGreaterThan(store.monthTotalTokens, 0, "월 누적 0 — enrichment 단절")
    }

    func testPrintRealAggregates() throws {
        guard ProcessInfo.processInfo.environment["PTB_PARITY"] == "1" else {
            throw XCTSkip("PTB_PARITY != 1")
        }
        let now = Date()
        let fmt = LocalUsageReader.localDayFormatter()
        let monthStart = LocalUsageReader.startOfMonth(now)
        let today = LocalUsageReader.todayKey()

        let claude = LocalUsageReader.claudeEntries(modifiedSince: monthStart)
        let codex = LocalUsageReader.codexEntries(modifiedSince: monthStart)

        print("PARITY ===== today=\(today)")
        // 최근 5일 일자별
        for offset in (0..<5).reversed() {
            let d = Calendar.current.date(byAdding: .day, value: -offset, to: now)!
            let day = fmt.string(from: d)
            let c = LocalUsageReader.daily(entries: claude, localDay: day)
            let x = LocalUsageReader.daily(entries: codex, localDay: day)
            print("PARITY claude \(day): tokens=\(c?.totalTokens ?? 0) cost=\(String(format: "%.2f", c?.totalCost ?? 0))")
            print("PARITY codex  \(day): tokens=\(x?.totalTokens ?? 0) cost=\(String(format: "%.2f", x?.totalCost ?? 0))")
        }
        let block = LocalUsageReader.activeBlock(entries: claude, now: now)
        print("PARITY active block: tokens=\(block?.totalTokens ?? 0) tpm=\(String(format: "%.0f", block?.tokensPerMinute ?? 0))")
        let ws = LocalUsageReader.startOfWeek(now)
        let week = LocalUsageReader.period(entries: claude, periodKey: "w", fromDay: fmt.string(from: ws), toDay: fmt.string(from: now))
        let month = LocalUsageReader.period(entries: claude, periodKey: "m", fromDay: fmt.string(from: monthStart), toDay: fmt.string(from: now))
        print("PARITY claude week tokens=\(week.totalTokens) cost=\(String(format: "%.2f", week.totalCost))")
        print("PARITY claude month tokens=\(month.totalTokens) cost=\(String(format: "%.2f", month.totalCost))")
    }

    /// 실제 rollout 으로 metadata probe 검증 — 픽스처는 파서와 같은 오해를 공유할 수 있으므로
    /// 상위 소스가 쓴 파일로 확인한다. 구방식(고정 64KB 통째 디코드)이 실패하던 파일 수도 함께 출력.
    func testCodexMetadataProbeOnRealRollouts() throws {
        guard ProcessInfo.processInfo.environment["PTB_PARITY"] == "1" else { throw XCTSkip("PTB_PARITY != 1") }
        let files = LocalUsageReader.jsonlFiles(in: LocalUsageReader.codexSessionsDir, modifiedSince: .distantPast)
        guard !files.isEmpty else { throw XCTSkip("~/.codex/sessions 비어 있음") }

        let fmt = LocalUsageReader.localDayFormatter()
        var parsedWithID = 0
        var mismatches: [String] = []
        var legacyDecodeFailures = 0
        for file in files {
            let probed = LocalUsageReader.codexRolloutSessionID(at: file)
            let parsed = LocalUsageReader.parseCodexRollout(file, fmt: fmt).sessionID
            if parsed != nil { parsedWithID += 1 }
            if probed != parsed { mismatches.append(file.lastPathComponent) }
            // 구방식 재현: 64KB 를 통째로 디코드하면 멀티바이트 경계에서 nil 이 된다.
            if let handle = try? FileHandle(forReadingFrom: file) {
                defer { try? handle.close() }
                if let data = try? handle.read(upToCount: 64 * 1024),
                   String(data: data, encoding: .utf8) == nil { legacyDecodeFailures += 1 }
            }
        }
        print("PARITY-PROBE files=\(files.count) parsedWithID=\(parsedWithID) legacyDecodeFailures=\(legacyDecodeFailures) mismatches=\(mismatches.count)")
        XCTAssertTrue(mismatches.isEmpty,
                      "metadata probe와 전체 parser의 session id가 다른 rollout: \(mismatches)")
    }

    /// 고아 부모(부모 파일이 사라진 fork)가 실제 rollout 규모에서 매 새로고침마다 전수 스캔을
    /// 유발하지 않는지 — 실 트리를 임시 디렉토리로 복제해 검증한다(원본은 읽기만 한다).
    func testCodexOrphanedParentDoesNotRescanRealTree() async throws {
        guard ProcessInfo.processInfo.environment["PTB_PARITY"] == "1" else { throw XCTSkip("PTB_PARITY != 1") }
        let source = LocalUsageReader.codexSessionsDir
        guard LocalUsageReader.codexRolloutFiles(in: source).count > 10 else {
            throw XCTSkip("rollout 이 너무 적어 의미 없음")
        }

        let fm = FileManager.default
        let tree = fm.temporaryDirectory.appendingPathComponent("ptb-orphan-\(UUID().uuidString)")
        try fm.copyItem(at: source, to: tree)
        defer { try? fm.removeItem(at: tree) }
        let cacheFile = tree.appendingPathComponent("usage-cache.json")

        // 부모 파일이 어디에도 없는 fork 를 하나 심는다(= 부모가 삭제·아카이브된 상태).
        try [
            #"{"type":"session_meta","timestamp":"2026-07-30T01:00:00.000Z","payload":{"id":"orphan-child","forked_from_id":"00000000-0000-7000-8000-ffffffffffff"}}"#,
            #"{"type":"event_msg","timestamp":"2026-07-30T01:00:05.000Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"output_tokens":10,"total_tokens":110},"last_token_usage":{"input_tokens":100,"output_tokens":10,"total_tokens":110}}}}"#,
        ].joined(separator: "\n").write(to: tree.appendingPathComponent("rollout-orphan-child.jsonl"),
                                        atomically: true, encoding: .utf8)

        let probes = ProbeMeter()
        // 캐시에 주입하는 probe 는 결과를 인덱스에 영속화하므로 throwing 버전을 써야 한다.
        // 편의 래퍼를 쓰면 I/O 실패가 "세션 id 없음"으로 굳어, 정확히 그 결함을 이 테스트가 재현한다.
        let cache = LocalUsageCache(codexRoot: tree, fileURL: cacheFile,
                                    codexProbe: { url in
                                        probes.bump()
                                        return try LocalUsageReader.probeCodexRolloutSessionID(at: url)
                                    })
        let since = LocalUsageReader.startOfMonth(Date())

        var t = Date()
        _ = await cache.codexEntries(modifiedSince: since)
        let cold = Date().timeIntervalSince(t)
        let coldProbes = probes.count

        t = Date()
        _ = await cache.codexEntries(modifiedSince: since)
        let warm = Date().timeIntervalSince(t)

        print(String(format: "PARITY-ORPHAN cold %.0fms (probe %d)  warm %.0fms (probe +%d)",
                     cold * 1000, coldProbes, warm * 1000, probes.count - coldProbes))
        XCTAssertEqual(probes.count, coldProbes, "두 번째 새로고침이 rollout 을 다시 열면 안 된다")
    }

    func testCachePerformance() async throws {
        guard ProcessInfo.processInfo.environment["PTB_PARITY"] == "1" else { throw XCTSkip("PTB_PARITY != 1") }
        let monthStart = LocalUsageReader.startOfMonth(Date())
        var t = Date()
        _ = await LocalUsageCache.shared.claudeEntries(modifiedSince: monthStart)
        let cold = Date().timeIntervalSince(t)
        t = Date()
        _ = await LocalUsageCache.shared.claudeEntries(modifiedSince: monthStart)
        let warm = Date().timeIntervalSince(t)
        print(String(format: "PARITY-PERF claude month scan: cold %.0fms  warm %.0fms", cold * 1000, warm * 1000))
    }

    /// 실제 auth.json 키로 /zen/go/v1/usage 라이브 조회 — 엔드포인트 스키마 드리프트 감지용.
    /// 키가 없는 머신(비구독·다른 CLI)은 skip. 401/403은 결함이 아니라 미구독 상태다.
    func testLiveOpenCodeGoUsageEndpoint() async throws {
        guard ProcessInfo.processInfo.environment["PTB_PARITY"] == "1" else { throw XCTSkip("PTB_PARITY != 1") }
        let provider = OpenCodeGoLimitsProvider()
        let status = try await provider.fetch()
        guard let status else { throw XCTSkip("~/.local/share/opencode/auth.json 에 opencode-go 키 없음") }
        print("PARITY-GO rolling=\(status.rolling?.percent ?? -1) weekly=\(status.weekly?.percent ?? -1) monthly=\(status.monthly?.percent ?? -1) rateLimited=\(status.isRateLimited)")
        XCTAssertTrue(status.hasVisibleLimit, "200 응답인데 표시할 창이 없다 — 응답 스키마가 바뀌었다")
    }
}
