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

    /// 비용은 **API 환산**이다 — 실제로 나간 돈이 아니라 "같은 양을 API 로 썼다면 얼마인가".
    /// 예전엔 Codex 만 0 으로 눌러 뒀는데(구독제라서), 그 논리대로면 정액제 사용자의 Claude Code 도
    /// 0 이어야 한다. 둘을 다르게 취급하는 대신 표시 이름을 환산으로 바꾸고 계산은 모든 프로바이더에
    /// 똑같이 적용한다 — 정액제 사용자에게는 "구독이 이만큼을 대신했다"로 읽힌다.
    func fetchDaily() async throws -> DailyUsage? {
        let now = Date()
        let entries = await LocalUsageCache.shared.codexEntries(modifiedSince: Calendar.current.startOfDay(for: now))
        return LocalUsageReader.daily(entries: entries, localDay: LocalUsageReader.todayKey())
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
        r.weekTotal = week
        r.monthTotal = month
        r.periodsOK = true
        return r
    }
}
