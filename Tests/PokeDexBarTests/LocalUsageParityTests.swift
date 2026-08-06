import XCTest
@testable import PokeDexBar

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
        print("PARITY-PIPE today=\(store.todayTotalTokens) cost=\(String(format: "%.2f", store.todayCostTotal)) menu=[\(store.menuTitle)] week=\(store.weekTotalTokens) month=\(store.monthTotalTokens) snapshots=\(store.snapshots.count) stale=\(store.isStale) err=\(store.lastErrorDescription ?? "none")")
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

/// [회귀] 비용은 **API 환산**이고, 프로바이더마다 규칙이 달라선 안 된다.
/// Codex 만 0 으로 눌러 뒀던 적이 있는데(구독제라서), 같은 논리면 정액제 사용자의 Claude Code 도
/// 0 이어야 했다 — 같은 성격의 사용을 다르게 취급하고 있었다.
@MainActor
final class CostParityAcrossProvidersTests: XCTestCase {
    private func entry(model: String, day: String) -> LocalUsageReader.Entry {
        LocalUsageReader.Entry(id: UUID().uuidString, date: Date(timeIntervalSince1970: 0),
                               localDay: day, model: model,
                               input: 1_000_000, output: 1_000_000, cacheWrite: 0, cacheRead: 0)
    }

    /// Codex 모델도 단가표를 지나 0 이 아닌 값이 나와야 한다 — 이게 0 이면 예전 동작으로 돌아간 것이다.
    func testCodexModelsAreNotFreeInThePricingTable() {
        for model in ["codex", "gpt-5-codex", "gpt-5.5"] {
            let cost = ModelPricing.cost(model: model, input: 1_000_000, output: 0,
                                         cacheWrite: 0, cacheRead: 0)
            XCTAssertGreaterThan(cost, 0, "\(model) 이 단가표에서 0 으로 떨어진다")
        }
    }

    /// 같은 토큰 수라면 프로바이더가 달라도 환산 규칙은 모델 단가 하나로만 갈려야 한다.
    func testTheSameModelCostsTheSameWhoeverReportedIt() {
        let day = "2026-01-01"
        let a = LocalUsageReader.daily(entries: [entry(model: "gpt-5.5", day: day)], localDay: day)
        let b = LocalUsageReader.daily(entries: [entry(model: "gpt-5.5", day: day)], localDay: day)
        XCTAssertEqual(a?.totalCost ?? -1, b?.totalCost ?? -2, accuracy: 1e-9)
        XCTAssertGreaterThan(a?.totalCost ?? 0, 0, "환산 비용이 0 이면 표시할 것이 없다")
    }

    /// 클로드와 코덱스가 **둘 다** 값을 내야 한다 — 한쪽만 0 이던 것이 이 회귀의 핵심이다.
    func testClaudeAndCodexBothProduceACost() {
        let day = "2026-01-01"
        let claude = LocalUsageReader.daily(entries: [entry(model: "claude-opus-4-8", day: day)],
                                            localDay: day)?.totalCost ?? 0
        let codex = LocalUsageReader.daily(entries: [entry(model: "gpt-5.5", day: day)],
                                           localDay: day)?.totalCost ?? 0
        XCTAssertGreaterThan(claude, 0)
        XCTAssertGreaterThan(codex, 0, "Codex 만 0 이면 같은 성격의 사용을 다르게 취급하는 것이다")
    }
}
