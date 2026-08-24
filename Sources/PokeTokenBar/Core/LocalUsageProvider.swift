import Foundation

/// 로컬 로그 직접 파싱 기반 Claude provider (ccusage 대체).
struct LocalClaudeProvider: UsageProvider {
    let id = "claude_code"
    let displayName = "Claude Code"

    func fetchDaily() async throws -> DailyUsage? {
        let now = Date()
        let entries = await LocalUsageCache.shared.claudeEntries(modifiedSince: Calendar.current.startOfDay(for: now))
        return LocalUsageReader.daily(entries: entries, localDay: LocalUsageReader.todayKey())
    }

    func fetchEnrichment() async -> ProviderEnrichment {
        let now = Date()
        let monthStart = LocalUsageReader.startOfMonth(now)
        // 한 번 스캔으로 블록·주·월을 모두 도출 — 하한은 세 윈도우 중 가장 이른 시작(월초 경계 흡수).
        let entries = await LocalUsageCache.shared.claudeEntries(
            modifiedSince: LocalUsageReader.enrichmentScanStart(now: now))
        let fmt = LocalUsageReader.localDayFormatter()
        var r = ProviderEnrichment()
        r.activeBlock = LocalUsageReader.activeBlock(entries: entries, now: now)
        r.blocksOK = true
        let weekStart = LocalUsageReader.startOfWeek(now)
        r.weekTotal = LocalUsageReader.period(
            entries: entries, periodKey: fmt.string(from: weekStart),
            fromDay: fmt.string(from: weekStart), toDay: fmt.string(from: now))
        r.monthTotal = LocalUsageReader.period(
            entries: entries, periodKey: LocalUsageReader.monthKey(now),
            fromDay: fmt.string(from: monthStart), toDay: fmt.string(from: now))
        r.periodsOK = true
        return r
    }
}

/// 로컬 로그 직접 파싱 기반 Gemini CLI provider.
/// 세션이 ~/.gemini/tmp/<hash>/chats/ 에 있을 때만 데이터가 잡힌다(없으면 스냅샷 미생성 → UI 미표시).
/// Antigravity CLI 는 같은 ~/.gemini/ 아래에 있지만 별도 프로바이더다(`LocalAntigravityProvider`).
struct LocalGeminiProvider: UsageProvider {
    let id = "gemini"
    let displayName = "Gemini"

    func fetchDaily() async throws -> DailyUsage? {
        let now = Date()
        let entries = await LocalUsageCache.shared.geminiEntries(modifiedSince: Calendar.current.startOfDay(for: now))
        return LocalUsageReader.daily(entries: entries, localDay: LocalUsageReader.todayKey())
    }

    func fetchEnrichment() async -> ProviderEnrichment {
        let now = Date()
        let monthStart = LocalUsageReader.startOfMonth(now)
        let entries = await LocalUsageCache.shared.geminiEntries(
            modifiedSince: LocalUsageReader.enrichmentScanStart(now: now))
        let fmt = LocalUsageReader.localDayFormatter()
        var r = ProviderEnrichment()
        // 블록(burn rate) 계산은 프로바이더 공통 — companion 리듬이 전 프로바이더를 따르게.
        r.activeBlock = LocalUsageReader.activeBlock(entries: entries, now: now)
        r.blocksOK = true
        let weekStart = LocalUsageReader.startOfWeek(now)
        r.weekTotal = LocalUsageReader.period(entries: entries, periodKey: fmt.string(from: weekStart),
                                              fromDay: fmt.string(from: weekStart), toDay: fmt.string(from: now))
        r.monthTotal = LocalUsageReader.period(entries: entries, periodKey: LocalUsageReader.monthKey(now),
                                               fromDay: fmt.string(from: monthStart), toDay: fmt.string(from: now))
        r.periodsOK = true
        return r
    }
}

/// 로컬 대화 DB 직접 파싱 기반 Antigravity CLI provider.
/// ~/.gemini/ 라는 부모 디렉토리만 Gemini CLI 와 공유할 뿐 저장 형식이 완전히 다르다 — 대화마다
/// SQLite 한 개, 토큰 원장은 protobuf blob 안(`LocalAntigravityUsageReader` 참고). 안 쓰면
/// 스냅샷 미생성 → UI 미표시.
/// 구독제라 소스가 금액을 아예 보고하지 않는다(스키마에 비용 필드가 없고 `antigravity/` 프리픽스가
/// 단가표를 끊는다) → Cursor 와 같은 플랫요금 취급으로 토큰만 보고한다.
struct LocalAntigravityProvider: UsageProvider {
    let id = "antigravity"
    let displayName = "Antigravity"
    let reportsCost = false

    func fetchDaily() async throws -> DailyUsage? {
        let entries = await LocalAntigravityUsageCache.shared.entries()
        return LocalUsageReader.daily(entries: entries, localDay: LocalUsageReader.todayKey())
    }

    func fetchEnrichment() async -> ProviderEnrichment {
        let now = Date()
        let monthStart = LocalUsageReader.startOfMonth(now)
        let entries = await LocalAntigravityUsageCache.shared.entries()
        let fmt = LocalUsageReader.localDayFormatter()
        var r = ProviderEnrichment()
        // 블록(burn rate) 계산은 프로바이더 공통 — companion 리듬이 전 프로바이더를 따르게.
        r.activeBlock = LocalUsageReader.activeBlock(entries: entries, now: now)
        r.blocksOK = true
        let weekStart = LocalUsageReader.startOfWeek(now)
        r.weekTotal = LocalUsageReader.period(entries: entries, periodKey: fmt.string(from: weekStart),
                                              fromDay: fmt.string(from: weekStart), toDay: fmt.string(from: now))
        r.monthTotal = LocalUsageReader.period(entries: entries, periodKey: LocalUsageReader.monthKey(now),
                                               fromDay: fmt.string(from: monthStart), toDay: fmt.string(from: now))
        r.periodsOK = true
        return r
    }
}

/// 로컬 로그 직접 파싱 기반 Grok CLI provider (공식 xAI Grok CLI).
/// 세션이 ~/.grok/sessions/<id>/updates.jsonl 에 있을 때만 데이터가 잡힌다(없으면 스냅샷 미생성 → UI 미표시).
struct LocalGrokProvider: UsageProvider {
    let id = "grok"
    let displayName = "Grok"

    func fetchDaily() async throws -> DailyUsage? {
        let now = Date()
        let entries = await LocalUsageCache.shared.grokEntries(modifiedSince: Calendar.current.startOfDay(for: now))
        return LocalUsageReader.daily(entries: entries, localDay: LocalUsageReader.todayKey())
    }

    func fetchEnrichment() async -> ProviderEnrichment {
        let now = Date()
        let monthStart = LocalUsageReader.startOfMonth(now)
        let entries = await LocalUsageCache.shared.grokEntries(
            modifiedSince: LocalUsageReader.enrichmentScanStart(now: now))
        let fmt = LocalUsageReader.localDayFormatter()
        var r = ProviderEnrichment()
        // 블록(burn rate) 계산은 프로바이더 공통 — companion 리듬이 전 프로바이더를 따르게.
        r.activeBlock = LocalUsageReader.activeBlock(entries: entries, now: now)
        r.blocksOK = true
        let weekStart = LocalUsageReader.startOfWeek(now)
        r.weekTotal = LocalUsageReader.period(entries: entries, periodKey: fmt.string(from: weekStart),
                                              fromDay: fmt.string(from: weekStart), toDay: fmt.string(from: now))
        r.monthTotal = LocalUsageReader.period(entries: entries, periodKey: LocalUsageReader.monthKey(now),
                                               fromDay: fmt.string(from: monthStart), toDay: fmt.string(from: now))
        r.periodsOK = true
        return r
    }
}

/// 로컬 로그 직접 파싱 기반 Codex provider. (주간 = 일별 합산)
struct LocalCodexProvider: UsageProvider {
    let id = "codex"
    let displayName = "Codex"

    // Codex 사용은 구독제라 ccusage codex 가 비용을 $0 로 보고 → 동일하게 비용 0.
    func fetchDaily() async throws -> DailyUsage? {
        let now = Date()
        let entries = await LocalUsageCache.shared.codexEntries(modifiedSince: Calendar.current.startOfDay(for: now))
        guard let d = LocalUsageReader.daily(entries: entries, localDay: LocalUsageReader.todayKey()) else { return nil }
        return DailyUsage(date: d.date, inputTokens: d.inputTokens, outputTokens: d.outputTokens,
                          cacheCreationTokens: d.cacheCreationTokens, cacheReadTokens: d.cacheReadTokens,
                          totalTokens: d.totalTokens, totalCost: 0)
    }

    func fetchEnrichment() async -> ProviderEnrichment {
        let now = Date()
        let monthStart = LocalUsageReader.startOfMonth(now)
        let entries = await LocalUsageCache.shared.codexEntries(
            modifiedSince: LocalUsageReader.enrichmentScanStart(now: now))
        let fmt = LocalUsageReader.localDayFormatter()
        var r = ProviderEnrichment()
        // 블록(burn rate) 계산은 프로바이더 공통 — companion 리듬이 전 프로바이더를 따르게.
        r.activeBlock = LocalUsageReader.activeBlock(entries: entries, now: now)
        r.blocksOK = true
        let weekStart = LocalUsageReader.startOfWeek(now)
        let week = LocalUsageReader.period(entries: entries, periodKey: fmt.string(from: weekStart),
                                           fromDay: fmt.string(from: weekStart), toDay: fmt.string(from: now))
        let month = LocalUsageReader.period(entries: entries, periodKey: LocalUsageReader.monthKey(now),
                                            fromDay: fmt.string(from: monthStart), toDay: fmt.string(from: now))
        r.weekTotal = PeriodUsage(period: week.period, totalTokens: week.totalTokens, totalCost: 0)
        r.monthTotal = PeriodUsage(period: month.period, totalTokens: month.totalTokens, totalCost: 0)
        r.periodsOK = true
        return r
    }
}

/// Local pi agent session usage. (Token-only; reasoning is folded into output.)
struct LocalPiProvider: UsageProvider {
    let id = "pi"
    let displayName = "Pi"
    let reportsCost = false

    func fetchDaily() async throws -> DailyUsage? {
        let now = Date()
        let entries = await LocalUsageCache.shared.piEntries(
            modifiedSince: Calendar.current.startOfDay(for: now))
        guard let d = LocalUsageReader.daily(entries: entries, localDay: LocalUsageReader.todayKey()) else {
            return nil
        }
        return DailyUsage(date: d.date, inputTokens: d.inputTokens, outputTokens: d.outputTokens,
                          cacheCreationTokens: d.cacheCreationTokens, cacheReadTokens: d.cacheReadTokens,
                          totalTokens: d.totalTokens, totalCost: 0)
    }

    func fetchEnrichment() async -> ProviderEnrichment {
        let now = Date()
        let monthStart = LocalUsageReader.startOfMonth(now)
        let entries = await LocalUsageCache.shared.piEntries(
            modifiedSince: LocalUsageReader.enrichmentScanStart(now: now))
        let fmt = LocalUsageReader.localDayFormatter()
        var result = ProviderEnrichment()
        result.activeBlock = LocalUsageReader.activeBlock(entries: entries, now: now)
        result.blocksOK = true
        let weekStart = LocalUsageReader.startOfWeek(now)
        let week = LocalUsageReader.period(
            entries: entries, periodKey: fmt.string(from: weekStart),
            fromDay: fmt.string(from: weekStart), toDay: fmt.string(from: now))
        let month = LocalUsageReader.period(
            entries: entries, periodKey: LocalUsageReader.monthKey(now),
            fromDay: fmt.string(from: monthStart), toDay: fmt.string(from: now))
        result.weekTotal = PeriodUsage(period: week.period, totalTokens: week.totalTokens, totalCost: 0)
        result.monthTotal = PeriodUsage(period: month.period, totalTokens: month.totalTokens, totalCost: 0)
        result.periodsOK = true
        return result
    }
}
