import Foundation

/// provider 확장 포인트 — 새 소스(Gemini/OpenCode 등)는 이 protocol 구현체 추가만으로 확장
protocol UsageProvider: Sendable {
    var id: String { get }
    var displayName: String { get }
    /// Whether this provider contributes to cost aggregates / per-row cost UI.
    /// Flat-rate subscriptions (e.g. Cursor) report tokens only.
    var reportsCost: Bool { get }

    /// 오늘 합계 (critical path) — 메뉴바 숫자와 stale 판정의 기준.
    /// 데이터 소스 자체가 없거나 오늘 사용량이 없으면 nil.
    func fetchDaily() async throws -> DailyUsage?

    /// 블록/주월 누적 상세 (best effort) — 느리거나 실패해도 메뉴바 숫자에 영향 없음.
    func fetchEnrichment() async -> ProviderEnrichment
}

extension UsageProvider {
    var reportsCost: Bool { true }
}

/// 부가 정보 수집 결과. *OK 플래그가 false 면 수집 실패 → 이전 값 유지.
struct ProviderEnrichment: Sendable {
    var activeBlock: BlockUsage?
    var blocksOK = false
    var weekTotal: PeriodUsage?
    var monthTotal: PeriodUsage?
    /// Day-by-day totals for the current month (month start → today, empty days as zeros).
    /// Comes out of the same scan as `monthTotal` and is gated by the same `periodsOK`.
    /// `nil` means this provider cannot produce a series — the UI drops the trend row and
    /// keeps the scalars, rather than drawing a chart that silently omits a provider.
    var monthDaily: [DailyUsage]?
    var periodsOK = false
}

extension ProviderEnrichment {
    /// Assembles the whole enrichment — active block, this week, this month, this month's daily
    /// series — from one already-loaded set of entries.
    ///
    /// Every local provider shares this one site. The assembly used to be copied per provider
    /// (twelve near-identical bodies), which is the shape the defect log warns about for the
    /// append-only watermark loop (#157): a field added later gets filled in some copies and not
    /// others, and the gap is invisible in a dev environment that does not use that provider.
    ///
    /// - Parameter zeroCost: subscription sources (Codex, Pi) do not report money at all, so the
    ///   model price table would invent a charge the user never paid. Their totals stay at 0.
    static func local(entries: [LocalUsageReader.Entry], now: Date = Date(),
                      zeroCost: Bool = false) -> ProviderEnrichment
    {
        let fmt = LocalUsageReader.localDayFormatter()
        let weekStart = LocalUsageReader.startOfWeek(now)
        let monthStart = LocalUsageReader.startOfMonth(now)

        var result = ProviderEnrichment()
        // Block (burn rate) computation is provider-generic — the companion rhythm follows all providers.
        result.activeBlock = LocalUsageReader.activeBlock(entries: entries, now: now)
        result.blocksOK = true

        let week = LocalUsageReader.period(
            entries: entries, periodKey: fmt.string(from: weekStart),
            fromDay: fmt.string(from: weekStart), toDay: fmt.string(from: now))
        let month = LocalUsageReader.period(
            entries: entries, periodKey: LocalUsageReader.monthKey(now),
            fromDay: fmt.string(from: monthStart), toDay: fmt.string(from: now))
        let series = LocalUsageReader.monthDailySeries(entries: entries, now: now)

        if zeroCost {
            result.weekTotal = PeriodUsage(period: week.period, totalTokens: week.totalTokens, totalCost: 0)
            result.monthTotal = PeriodUsage(period: month.period, totalTokens: month.totalTokens, totalCost: 0)
            result.monthDaily = series.map {
                DailyUsage(date: $0.date, inputTokens: $0.inputTokens, outputTokens: $0.outputTokens,
                           cacheCreationTokens: $0.cacheCreationTokens, cacheReadTokens: $0.cacheReadTokens,
                           totalTokens: $0.totalTokens, totalCost: 0)
            }
        } else {
            result.weekTotal = week
            result.monthTotal = month
            result.monthDaily = series
        }
        result.periodsOK = true
        return result
    }
}
