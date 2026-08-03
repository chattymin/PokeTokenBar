import XCTest
@testable import PokeTokenBar

// keychain/네트워크 의존 없이 한도 provider 를 비활성화하는 스텁(통합 파이프라인 검증용).
private struct NoClaudeLimits: ClaudeLimitsProviding {
    func fetch(allowKeychainPrompt: Bool) async throws -> LimitStatus { throw LimitsError.keychainInteractionNotAllowed }
}
private struct NoCodexLimits: CodexLimitsProviding {
    func fetch() async throws -> CodexRateLimitStatus? { nil }
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
}
