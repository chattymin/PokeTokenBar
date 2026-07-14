import AppKit
import Foundation
import Observation
import UserNotifications

/// burn rate 단계 — companion 표시 상태(작업/집중) 판정에 사용.
enum BurnTier: Sendable {
    case idle, normal, fast, blazing
}

@MainActor
@Observable
final class UsageStore {
    // MARK: 상태

    private(set) var snapshots: [ProviderSnapshot] = []
    private(set) var limits: LimitStatus?
    private(set) var codexLimits: CodexRateLimitStatus?
    private(set) var codexLimitsUpdatedAt: Date?
    private(set) var limitsUpdatedAt: Date?
    private(set) var limitsAvailable = true
    /// Claude 한도 조회가 401/403(세션 만료)로 실패한 상태 — UI 에서 명확한 안내+재시도 노출용.
    /// 성공 시 해제. 자동 폴링은 무프롬프트라 만료 토큰을 스스로 못 고치므로 사용자 액션 유도가 필요.
    private(set) var limitsAuthExpired = false
    /// providerID → 프로바이더 상태 페이지 인시던트 지표(표시 전용). 조회 실패 시 이전 값 유지.
    private(set) var statuses: [String: ProviderStatus] = [:]
    private(set) var lastUpdated: Date?
    private(set) var isRefreshing = false
    private(set) var isRefreshingLimitToken = false
    private(set) var lastErrorDescription: String?
    private(set) var limitTokenRefreshError: String?

    // MARK: 설정 (UserDefaults)

    /// 0 = manual
    var refreshInterval: TimeInterval {
        didSet {
            defaults.set(refreshInterval, forKey: "refreshInterval")
            reschedule()
        }
    }
    var warnThreshold: Double {
        didSet { defaults.set(warnThreshold, forKey: "warnThreshold") }
    }
    var critThreshold: Double {
        didSet { defaults.set(critThreshold, forKey: "critThreshold") }
    }
    // 메뉴바 표시 항목 (복수 선택 가능)
    var showTokensInMenu: Bool {
        didSet { defaults.set(showTokensInMenu, forKey: "showTokensInMenu") }
    }
    var showCostInMenu: Bool {
        didSet { defaults.set(showCostInMenu, forKey: "showCostInMenu") }
    }
    var showLimitInMenu: Bool {
        didSet { defaults.set(showLimitInMenu, forKey: "showLimitInMenu") }
    }
    // 알림(독립 토글)
    var limitNotifications: Bool {
        didSet { defaults.set(limitNotifications, forKey: "limitNotifications") }
    }
    var companionNotifications: Bool {
        didSet { defaults.set(companionNotifications, forKey: "companionNotifications") }
    }
    /// 프로바이더 상태(인시던트) 조회 — 기본 켬. 표시 전용(알림 아님). Claude/OpenAI statuspage.io.
    var statusChecksEnabled: Bool {
        didSet { defaults.set(statusChecksEnabled, forKey: "statusChecksEnabled") }
    }
    var disableKeychainAccess: Bool {
        didSet {
            defaults.set(disableKeychainAccess, forKey: "disableKeychainAccess")   // 저장 누락이던 기존 버그 — 재시작 후 풀렸음
            KeychainAccessGate.isDisabled = disableKeychainAccess
            if disableKeychainAccess {
                limits = nil
                limitsAvailable = false
            } else {
                Task { await refresh() }
            }
        }
    }

    static let intervalPresets: [(label: String, value: TimeInterval)] = [
        ("수동", 0), ("1분", 60), ("2분", 120), ("5분", 300), ("15분", 900),
    ]

    /// 앱 언어 미러(알림 현지화용). 단일 소스는 CompanionStore.language —
    /// 설정 변경/기동 시 동기화한다.
    var localizationLanguage: AppLanguage = .systemDefault   // companion.language 로 재시드 전까지의 기본(실행순서 무관 안전)

    private let providers: [any UsageProvider]

    /// 등록된 프로바이더 id 목록 — 확장 규약 레지스트리 무결성 테스트용.
    var registeredProviderIDs: [String] { providers.map(\.id) }
    private let limitsProvider: any ClaudeLimitsProviding
    private let codexLimitsProvider: any CodexLimitsProviding
    private let statusProvider: any ProviderStatusProviding
    /// 설정 저장소 — 테스트는 suite 를 주입해 실제 사용자 설정을 오염시키지 않는다.
    private let defaults: UserDefaults
    private var timer: Timer?
    private var pollingSuspended = false   // 디스플레이 꺼짐 동안 폴링 정지 (배터리)
    private var emptyUsageRetryTask: Task<Void, Never>?
    /// 한도 알림 상태(엣지 트리거) — 창 이름 → 이미 알린 최고 tier(0=없음, 1=경고, 2=위험).
    /// utilization 이 경고선 아래로 내려가면 맵에서 제거해 재무장. resets_at 같은 매 fetch 변하는
    /// 휘발성 필드를 키에 쓰지 않는다(rolling 주간 창 resets_at 가 매번 달라져 80·81·84…
    /// 갱신마다 재알림되던 회귀 원인 제거).
    private var notifiedTier: [String: Int] = [:]

    /// 매 refresh 완료(한도 로드 후) 시 호출 — companion 갱신·사탕 지급을 한도가 신선한 시점에 묶는다.
    /// observeStore(menuTitle)만으론 showLimitInMenu=false 일 때 한도 변경이 companion 에 전달 안 됨
    /// (menuTitle 미변경) → 지급은 이 훅으로 확실히 트리거한다. AppDelegate 가 설정.
    var onRefresh: (@MainActor () -> Void)?

    // MARK: 파생값

    var todayTotalTokens: Int {
        // 날짜 가드: 스냅샷의 일자가 현재 로컬 날짜와 다르면 (자정 직후 등) 합계에서 제외
        let todayKey = LocalUsageReader.todayKey()
        return snapshots.reduce(0) { $0 + ($1.today?.date == todayKey ? $1.todayTotalTokens : 0) }
    }

    /// 사용량 데이터(스냅샷)가 하나라도 있는가 — companion sleep 판정용
    var hasUsageData: Bool { !snapshots.isEmpty }

    /// 메뉴바 표시 줄 규칙 (사용자 확정 — 조합표 전수 검증: `UsageStoreTests.testMenuLinesAllCombinations`):
    /// - **활성 항목 2개 이하 → 각 항목을 개별 세로 줄로**(토큰/비용/한도 각 1줄).
    /// - **3개(토큰+비용+한도) 모두 활성 → 토큰·비용을 한 줄로, 한도를 아랫줄로**(= 총 2줄).
    /// 한도 줄은 오늘 사용한 프로바이더만(`menuLimitLine`). 빈 배열이면 아이콘만.
    var menuLines: [String] {
        guard lastUpdated != nil else { return ["—"] }
        var usage: [String] = []
        if showTokensInMenu { usage.append(TokenFormatter.compact(todayTotalTokens)) }
        if showCostInMenu { usage.append(TokenFormatter.costCompact(todayCostTotal)) }
        let limit = menuLimitLine   // nil = 한도 미표시/미가용

        if limit != nil && usage.count == 2 {
            // 3개 다 활성 → 토큰·비용 한 줄 + 한도 아랫줄 (≤2줄 유지)
            return [usage.joined(separator: " · "), limit!]
        }
        // 그 외(2개 이하) → 각 항목 개별 세로 줄
        var lines = usage
        if let limit { lines.append(limit) }
        return lines
    }

    /// 메뉴바 한도 줄 — **오늘 실제 사용한 프로바이더만** 한 줄에 나란히(미사용/미가용이면 nil).
    /// 한도 소스는 프로바이더 고유(Claude=OAuth·Codex=프로세스)라 providerID 로 명시 분기(확장 규약).
    private var menuLimitLine: String? {
        guard showLimitInMenu else { return nil }
        let usedToday = Set(snapshots.filter { $0.todayTotalTokens > 0 }.map(\.providerID))
        var parts: [String] = []
        if usedToday.contains("claude_code"), let utilization = limits?.fiveHour?.utilization {
            parts.append("Claude \(TokenFormatter.percent(utilization))")
        }
        if usedToday.contains("codex"), let usedPercent = codexLimits?.maxPrimaryUsedPercent {
            parts.append("Codex \(TokenFormatter.percent(Double(usedPercent)))")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// 단일 줄 표현 — 관찰(observeStore)·접근성·1줄 렌더 폴백용. 세로 렌더는 menuLines 사용.
    var menuTitle: String { menuLines.joined(separator: " · ") }

    var todayCostTotal: Double {
        let todayKey = LocalUsageReader.todayKey()
        return snapshots.reduce(0) { $0 + ($1.today?.date == todayKey ? ($1.today?.totalCost ?? 0) : 0) }
    }

    /// 프로바이더 탭 선택 해석 — 선호 id 가 연결돼 있으면 그것, 아니면(첫 실행/연결 해제) 첫 번째.
    func snapshot(preferring id: String?) -> ProviderSnapshot? {
        if let id, let s = snapshots.first(where: { $0.providerID == id }) { return s }
        return snapshots.first
    }

    var weekTotalTokens: Int { snapshots.reduce(0) { $0 + ($1.weekTotal?.totalTokens ?? 0) } }
    var weekCostTotal: Double { snapshots.reduce(0) { $0 + ($1.weekTotal?.totalCost ?? 0) } }
    var monthTotalTokens: Int { snapshots.reduce(0) { $0 + ($1.monthTotal?.totalTokens ?? 0) } }
    var monthCostTotal: Double { snapshots.reduce(0) { $0 + ($1.monthTotal?.totalCost ?? 0) } }

    /// Claude 의 활성 5h 블록 — 5h forecast·"현재 블록" 행은 Claude 공식 한도와 짝이므로
    /// providerID 로 명시 조회한다 (전 프로바이더가 블록을 갖게 된 후 first-with-block 은 오매칭).
    private var claudeActiveBlock: BlockUsage? {
        snapshots.first { $0.providerID == "claude_code" }?.activeBlock
    }

    /// 전 프로바이더 활성 블록의 합산 burn (tokens/min) — companion 리듬 판정용.
    private var combinedBurnPerMinute: Double {
        snapshots.compactMap { $0.activeBlock?.tokensPerMinute }.reduce(0, +)
    }

    // MARK: 한도 소진 예측

    struct FiveHourForecast {
        var depletionDate: Date
        var beforeReset: Bool
    }

    var fiveHourForecast: FiveHourForecast? {
        guard let window = limits?.fiveHour, let utilization = window.utilization,
              let reset = window.resetDate else { return nil }
        if utilization >= 100 { return FiveHourForecast(depletionDate: Date(), beforeReset: true) }
        guard let block = claudeActiveBlock, let burn = block.tokensPerMinute,
              let depletion = Self.forecastDepletion(
                  blockTokens: block.totalTokens, tokensPerMinute: burn,
                  utilization: utilization, now: Date())
        else { return nil }
        return FiveHourForecast(depletionDate: depletion, beforeReset: depletion < reset)
    }

    /// 5h 한도의 토큰량을 (현재 블록 토큰 ÷ 공식 utilization%) 로 추정하고 100% 도달 시각을 외삽.
    /// utilization 5% 미만이거나 burn 1만 토큰/분 미만이면 추정이 불안정해 nil.
    nonisolated static func forecastDepletion(
        blockTokens: Int, tokensPerMinute: Double, utilization: Double, now: Date
    ) -> Date? {
        guard utilization >= 5, utilization < 100, blockTokens > 0,
              tokensPerMinute >= 10_000 else { return nil }
        let tokensPerPercent = Double(blockTokens) / utilization
        let minutesLeft = (100 - utilization) * tokensPerPercent / tokensPerMinute
        guard minutesLeft.isFinite, minutesLeft < 60 * 24 else { return nil }
        return now.addingTimeInterval(minutesLeft * 60)
    }

    /// 메뉴바 경고 상태 — 임계 초과 또는 리셋 전 한도 도달 예측.
    /// Claude 는 5h 만이 아니라 팝오버가 표시하는 모든 한도 창(주간·모델별 주간 포함)의 위험선을
    /// 검사한다 — 5h 는 여유롭지만 주간이 100% 인 경우에도 경고/‘지침’ 상태가 뜨도록(누락 수정).
    var isLimitWarning: Bool {
        for u in [limits?.fiveHour?.utilization, limits?.sevenDay?.utilization,
                  limits?.sevenDayOpus?.utilization, limits?.sevenDaySonnet?.utilization] {
            if let u, u >= critThreshold { return true }
        }
        for entry in limits?.scopedLimitEntries ?? [] {
            if let p = entry.percent, p >= critThreshold { return true }
        }
        for bucket in codexLimits?.visibleSnapshots ?? [] {
            if let utilization = bucket.primary?.usedPercent,
               Double(utilization) >= critThreshold { return true }
            if let utilization = bucket.secondary?.usedPercent,
               Double(utilization) >= critThreshold { return true }
            if let utilization = bucket.individualLimit?.usedPercent,
               Double(utilization) >= critThreshold { return true }
        }
        if let forecast = fiveHourForecast, forecast.beforeReset { return true }
        return false
    }

    /// 사탕 지급 대상 한도 창 — 세션급(≈5h)=1개, 주간급=5개, 전 프로바이더. Gemini 는 공식 한도
    /// 신호가 없어 자연히 빠진다(창 목록에 없음). 지급 제외: Opus/Sonnet 주간·scoped·Codex 개인 spend
    /// limit(헤드라인 창의 하위/중복 → 이중지급 방지). 알림(checkLimitNotifications)보다 좁은 지급 전용.
    var candyEligibleWindows: [CandyWindow] {
        let l = L(localizationLanguage)
        var windows: [CandyWindow] = []
        if let u = limits?.fiveHour?.utilization {
            windows.append(CandyWindow(key: "claude.fiveHour", name: l.claudeFiveHour,
                                       kind: .session, utilization: u))
        }
        if let u = limits?.sevenDay?.utilization {
            windows.append(CandyWindow(key: "claude.sevenDay", name: l.claudeWeekly,
                                       kind: .weekly, utilization: u))
        }
        for bucket in codexLimits?.visibleSnapshots ?? [] {
            let bucketKey = bucket.limitId ?? bucket.limitName ?? "codex"
            let bucketName = bucket.bucketDisplayName
            if let primary = bucket.primary {
                windows.append(CandyWindow(
                    key: "codex.\(bucketKey).primary",
                    name: "\(bucketName) \(l.codexWindow(primary.windowDurationMins))",
                    kind: Self.windowClass(minutes: primary.windowDurationMins),
                    utilization: Double(primary.usedPercent)))
            }
            if let secondary = bucket.secondary {
                windows.append(CandyWindow(
                    key: "codex.\(bucketKey).secondary",
                    name: "\(bucketName) \(l.codexWindow(secondary.windowDurationMins))",
                    kind: Self.windowClass(minutes: secondary.windowDurationMins),
                    utilization: Double(secondary.usedPercent)))
            }
        }
        return windows
    }

    /// Codex 창 분류 — ≤24h(1440분)=세션, 초과=주간. 미상(nil)은 세션으로 간주(보수적).
    nonisolated static func windowClass(minutes: Int?) -> WindowClass {
        if let m = minutes, m > 1440 { return .weekly }
        return .session
    }

    /// 한도 데이터가 최소 1개 프로바이더 로드됐는가 — 사탕 첫 실행 시드 게이트(미로딩 중 시드 방지).
    var limitsReady: Bool { limits != nil || codexLimits != nil }

    /// burn rate 티어 — companion 표시 상태(idle/working/focus) 판정에 사용.
    /// 전 프로바이더 합산 — Codex/Gemini 전용 사용자도 코딩 리듬이 반영된다.
    var burnTier: BurnTier {
        let burn = combinedBurnPerMinute
        guard burn > 1_000 else { return .idle }
        if burn < 100_000 { return .normal }
        if burn < 400_000 { return .fast }
        return .blazing
    }

    var isStale: Bool {
        guard let lastUpdated else { return true }
        let allowance = refreshInterval > 0 ? refreshInterval * 2 : 1800
        return Date().timeIntervalSince(lastUpdated) > allowance
    }

    // MARK: 생명주기

    init(providers: [any UsageProvider] = [LocalClaudeProvider(), LocalCodexProvider(), LocalGeminiProvider()],
         claudeLimitsProvider: any ClaudeLimitsProviding = OAuthLimitsProvider(),
         codexLimitsProvider: any CodexLimitsProviding = CodexRateLimitsProvider(),
         statusProvider: any ProviderStatusProviding = StatuspageStatusProvider(),
         autoRefresh: Bool = true,
         defaults: UserDefaults = .standard) {
        self.providers = providers
        self.limitsProvider = claudeLimitsProvider
        self.codexLimitsProvider = codexLimitsProvider
        self.statusProvider = statusProvider
        self.defaults = defaults
        let d = defaults
        refreshInterval = d.object(forKey: "refreshInterval") as? TimeInterval ?? 120
        warnThreshold = d.object(forKey: "warnThreshold") as? Double ?? 80
        critThreshold = d.object(forKey: "critThreshold") as? Double ?? 95
        showTokensInMenu = d.object(forKey: "showTokensInMenu") as? Bool ?? true
        showCostInMenu = d.object(forKey: "showCostInMenu") as? Bool ?? false
        showLimitInMenu = d.object(forKey: "showLimitInMenu") as? Bool ?? false
        limitNotifications = d.object(forKey: "limitNotifications") as? Bool ?? true
        companionNotifications = d.object(forKey: "companionNotifications") as? Bool ?? true
        statusChecksEnabled = d.object(forKey: "statusChecksEnabled") as? Bool ?? true
        disableKeychainAccess = d.object(forKey: "disableKeychainAccess") as? Bool ?? false

        reschedule()

        // 자정 경계: 날짜가 바뀌면 "오늘" 버킷 즉시 갱신
        NotificationCenter.default.addObserver(
            forName: .NSCalendarDayChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        // 슬립 복귀 시 즉시 갱신
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        // 디스플레이 꺼짐 → 폴링(ccusage 서브프로세스 spawn) 일시정지, 켜짐 → 재개 + 즉시 갱신 (배터리)
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.suspendPolling() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.resumePolling() }
        }

        // 알림 권한은 기동 즉시 묻지 않는다 — 앱을 이해하기 전 콜드 프롬프트는 거부율이 높고
        // 거부 시 재요청 경로가 없다. 팝오버 첫 오픈(사용자 의도)에 requestNotificationAuthorizationIfNeeded 로 1회 요청.
        if autoRefresh { Task { await refresh() } }
    }

    private func reschedule() {
        timer?.invalidate()
        timer = nil
        guard !pollingSuspended, refreshInterval > 0 else { return }
        let t = Timer(timeInterval: refreshInterval, repeats: true) { _ in
            Task { @MainActor [weak self] in await self?.refresh() }
        }
        t.tolerance = refreshInterval * 0.1
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// 디스플레이 꺼짐 → 폴링 타이머 정지(예약된 ccusage 서브프로세스 spawn 중단).
    private func suspendPolling() {
        pollingSuspended = true
        timer?.invalidate()
        timer = nil
    }

    /// 디스플레이 켜짐 → 폴링 재개 + 즉시 1회 갱신(켜졌을 때 메뉴 숫자 최신화).
    private func resumePolling() {
        guard pollingSuspended else { return }
        pollingSuspended = false
        reschedule()
        Task { await refresh() }
    }

    // MARK: 갱신

    func refresh(scheduleEmptyRetry: Bool = true) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        // App Nap 방지 — 백그라운드 스로틀로 ccusage 가 타임아웃되는 것을 막는다 (시스템 슬립은 허용)
        let activity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep, reason: "PokeTokenBar usage refresh")
        defer {
            ProcessInfo.processInfo.endActivity(activity)
            isRefreshing = false
        }

        let todayKey = LocalUsageReader.todayKey()

        // ── Phase 1: daily (critical) — 메뉴바 숫자와 stale 판정은 여기서 확정.
        // 블록/주월 상세가 느리거나 멈춰도 메뉴바 숫자는 영향받지 않는다.
        var dailyByID: [String: DailyUsage] = [:]
        var failedIDs: Set<String> = []
        var errors: [String] = []

        // NOTE: (String, Result<DailyUsage?, any Error>) 튜플을 child task 결과로 쓰면
        // release 빌드에서 for-await 가 0건을 수신하는 문제가 있어, 평탄한 Sendable 구조체로 반환한다.
        struct DailyOutcome: Sendable {
            let id: String
            let today: DailyUsage?
            let errorDescription: String?
        }
        await withTaskGroup(of: DailyOutcome.self) { group in
            for provider in providers {
                group.addTask {
                    do {
                        let today = try await provider.fetchDaily()
                        return DailyOutcome(id: provider.id, today: today, errorDescription: nil)
                    } catch {
                        return DailyOutcome(id: provider.id, today: nil, errorDescription: "\(error)")
                    }
                }
            }
            for await outcome in group {
                AppLog.write("phase1 recv id=\(outcome.id) today=\(outcome.today?.totalTokens.description ?? "nil") err=\(outcome.errorDescription ?? "none")")
                if let today = outcome.today { dailyByID[outcome.id] = today }
                if let err = outcome.errorDescription {
                    failedIDs.insert(outcome.id)
                    errors.append("\(outcome.id): \(err)")
                }
            }
        }

        var newSnapshots: [ProviderSnapshot] = []
        for provider in providers {
            // 날짜 가드: 이전 스냅샷의 어제 데이터는 유지하지 않는다 (자정 동결 방지)
            var prevToday: DailyUsage?
            var prevBlock: BlockUsage?
            var prevWeek: PeriodUsage?
            var prevMonth: PeriodUsage?
            if let previous = snapshots.first(where: { $0.providerID == provider.id }) {
                if previous.today?.date == todayKey { prevToday = previous.today }
                prevBlock = previous.activeBlock
                // 주/월 누적도 이어받는다 — phase 2 가 다시 채우기 전까지 nil 로 비면
                // 팝오버의 "이번 주/이번 달" 행이 사라졌다 나타나 깜빡인다.
                prevWeek = previous.weekTotal
                prevMonth = previous.monthTotal
            }

            let today: DailyUsage?
            if let fetched = dailyByID[provider.id] {
                today = fetched
            } else if failedIDs.contains(provider.id) {
                today = prevToday   // 실패 → 오늘자 이전 값 유지
            } else {
                today = nil         // 성공했지만 오늘 데이터 없음 (예: Codex 미사용)
            }

            if today != nil {
                newSnapshots.append(ProviderSnapshot(
                    providerID: provider.id,
                    displayName: provider.displayName,
                    today: today,
                    activeBlock: prevBlock,
                    weekTotal: prevWeek,
                    monthTotal: prevMonth,
                    fetchedAt: Date()))
            }
        }
        snapshots = newSnapshots

        if errors.isEmpty {
            lastUpdated = Date()
            lastErrorDescription = nil
        } else {
            lastErrorDescription = errors.joined(separator: " / ")
            if lastUpdated == nil && !snapshots.isEmpty { lastUpdated = Date() }
        }
        writeParitySnapshot()
        AppLog.write("phase1 done total=\(todayTotalTokens) errors=\(errors.isEmpty ? "none" : errors.joined(separator: " | "))")
        handleEmptyUsageRetry(schedule: scheduleEmptyRetry, hasErrors: !errors.isEmpty)

        // ── Phase 2: 블록/주월 누적 상세 (best effort) — 실패 시 이전 값 유지
        await withTaskGroup(of: (String, ProviderEnrichment).self) { group in
            for provider in providers {
                group.addTask { (provider.id, await provider.fetchEnrichment()) }
            }
            for await (id, enrichment) in group {
                guard let index = snapshots.firstIndex(where: { $0.providerID == id }) else {
                    // 캐리어 스냅샷은 "**실제 활성 5h 블록**이 있을 때만" 만든다(어제 늦은밤 코딩이 5h
                    // 윈도우에 남아 자정 후 오늘 토큰 0인 경우 — burn/forecast/companion 보존). 주/월
                    // 누적만으로 만들면, weekTotal 이 옵셔널이 아니라(토큰 0이어도 non-nil) 오늘·최근
                    // 미사용 프로바이더까지 탭이 떠서 "안 썼는데 왜 뜨지" 회귀가 난다. 블록이 있을 때만
                    // 그 시점의 주/월도 함께 보존한다.
                    let hasActiveBlock = enrichment.blocksOK && enrichment.activeBlock != nil
                    if hasActiveBlock, let provider = providers.first(where: { $0.id == id }) {
                        snapshots.append(ProviderSnapshot(
                            providerID: id, displayName: provider.displayName, today: nil,
                            activeBlock: enrichment.activeBlock,
                            weekTotal: enrichment.periodsOK ? enrichment.weekTotal : nil,
                            monthTotal: enrichment.periodsOK ? enrichment.monthTotal : nil,
                            fetchedAt: Date()))
                    }
                    continue
                }
                if enrichment.blocksOK { snapshots[index].activeBlock = enrichment.activeBlock }
                if enrichment.periodsOK {
                    snapshots[index].weekTotal = enrichment.weekTotal
                    snapshots[index].monthTotal = enrichment.monthTotal
                }
            }
        }

        // ── 한도 조회 (Keychain 프롬프트로 블로킹될 수 있어 마지막)
        if disableKeychainAccess {
            limits = nil
            limitsAvailable = false
            limitsAuthExpired = false   // 조회 자체를 안 하므로 "세션 만료" 안내는 무의미 → 해제
            AppLog.write("claude limits skipped: keychain access disabled")
        } else if let until = claudeLimitsBackoffUntil, Date() < until {
            // 429 백오프 중 — 폴링을 쉬어 rate limit 악화 방지 (버그 리포트 실측: 매분 429 재시도)
            AppLog.write("claude limits backoff: skipping (\(Int(until.timeIntervalSinceNow))s left)")
        } else {
            do {
                limits = try await limitsProvider.fetch(allowKeychainPrompt: false)
                limitsAvailable = true
                limitsUpdatedAt = Date()
                limitsAuthExpired = false
                resetLimitsBackoff()
                AppLog.write("limits refreshed fiveHour=\(limits?.fiveHour?.utilization?.description ?? "nil") sevenDay=\(limits?.sevenDay?.utilization?.description ?? "nil")")
            } catch {
                // 비공식 endpoint 실패 → 섹션 숨김, 토큰 표시는 무영향
                if limits == nil { limitsAvailable = false }
                updateAuthExpired(from: error)
                applyLimitsBackoffIfRateLimited(error)
                AppLog.write("limits unavailable: \(error)")
            }
        }
        await refreshCodexLimits()
        await refreshProviderStatuses()

        checkLimitNotifications()
        writeParitySnapshot()
        let summary = snapshots.map { "\($0.providerID):\($0.today?.date ?? "nil")=\($0.todayTotalTokens)" }
            .joined(separator: ", ")
        AppLog.write("refresh done [\(summary)]")
        onRefresh?()   // 한도 로드 후 companion 갱신·사탕 지급(신선한 한도 시점)
    }

    private func handleEmptyUsageRetry(schedule: Bool, hasErrors: Bool) {
        emptyUsageRetryTask?.cancel()
        emptyUsageRetryTask = nil
        guard schedule, !hasErrors, snapshots.isEmpty else { return }

        AppLog.write("empty usage retry scheduled")
        emptyUsageRetryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            guard !Task.isCancelled else { return }
            self?.emptyUsageRetryTask = nil
            await self?.refresh(scheduleEmptyRetry: false)
        }
    }

    func refreshLimitTokenFromKeychain() async {
        guard !isRefreshingLimitToken else { return }
        isRefreshingLimitToken = true
        defer { isRefreshingLimitToken = false }

        do {
            // 명시적 사용자 액션은 백오프를 우회해 1회 시도 — 성공하면 백오프 해제
            limits = try await limitsProvider.fetch(allowKeychainPrompt: true)
            limitsAvailable = true
            limitsUpdatedAt = Date()
            limitsAuthExpired = false
            limitTokenRefreshError = nil
            resetLimitsBackoff()
            AppLog.write("limits refreshed by user action fiveHour=\(limits?.fiveHour?.utilization?.description ?? "nil") sevenDay=\(limits?.sevenDay?.utilization?.description ?? "nil")")
            AppLog.write("limits refreshed from keychain by user action")
        } catch {
            limitTokenRefreshError = Self.friendlyLimitError(error, L(localizationLanguage))
            if limits == nil { limitsAvailable = false }
            updateAuthExpired(from: error)
            applyLimitsBackoffIfRateLimited(error)
            AppLog.write("limits user refresh failed: \(error)")
        }
    }

    /// 401/403(세션 만료)면 auth-expired 플래그를 세운다. 다른 오류(네트워크·키체인 잠금 등)는
    /// 만료가 아니므로 건드리지 않는다 — 오탐으로 "세션 만료" 안내를 띄우지 않기 위함.
    private func updateAuthExpired(from error: any Error) {
        if case LimitsError.httpStatus(let status) = error, status == 401 || status == 403 {
            limitsAuthExpired = true
        }
    }

    // MARK: Claude 한도 429 백오프

    private var claudeLimitsBackoffUntil: Date?
    private var claudeLimitsBackoffInterval: TimeInterval = 0

    /// 429 시 지수 백오프: 5분 → 10분 → … → 최대 60분. Retry-After 가 오면 그 값 우선.
    private func applyLimitsBackoffIfRateLimited(_ error: any Error) {
        guard case LimitsError.rateLimited(let retryAfter) = error else { return }
        claudeLimitsBackoffInterval = Self.nextLimitsBackoff(after: claudeLimitsBackoffInterval)
        let delay = retryAfter ?? claudeLimitsBackoffInterval
        claudeLimitsBackoffUntil = Date().addingTimeInterval(delay)
        AppLog.write("claude limits rate-limited: backing off \(Int(delay))s")
    }

    private func resetLimitsBackoff() {
        claudeLimitsBackoffUntil = nil
        claudeLimitsBackoffInterval = 0
    }

    nonisolated static func nextLimitsBackoff(after current: TimeInterval) -> TimeInterval {
        current == 0 ? 300 : min(current * 2, 3600)
    }

    /// 한도 갱신 실패를 사용자 친화 메시지로 변환. Codex만 쓰는 사용자는 401 이 정상이라,
    /// raw "httpStatus(401)" 대신 "무시해도 된다"는 안내를 보여준다.
    static func friendlyLimitError(_ error: any Error, _ l: L) -> String {
        guard let limitsError = error as? LimitsError else { return l.limitRefreshGeneric }
        switch limitsError {
        case .rateLimited:
            return l.limitRefreshRateLimited
        case .httpStatus(let status):
            return l.limitRefreshHTTPError(status)
        case .keychainUnavailable, .credentialFormat:
            return l.limitRefreshNoCredential
        case .keychainInteractionNotAllowed, .keychainAccessDisabled:
            return l.limitRefreshGeneric
        }
    }

    private func refreshCodexLimits() async {
        do {
            codexLimits = try await codexLimitsProvider.fetch()
            if let status = codexLimits {
                codexLimitsUpdatedAt = Date()
                let buckets = status.snapshots.map { bucket in
                    "\(bucket.limitId ?? "codex"): primary=\(bucket.primary?.usedPercent.description ?? "nil") secondary=\(bucket.secondary?.usedPercent.description ?? "nil")"
                }.joined(separator: " | ")
                AppLog.write("codex limits refreshed [\(buckets)] plan=\(status.rateLimits.planType ?? "nil")")
            } else {
                AppLog.write("codex limits skipped: codex binary not found")
            }
        } catch {
            AppLog.write("codex limits unavailable: \(error)")
        }
    }

    /// 프로바이더 상태 페이지(인시던트) 조회 — 표시 전용, 기존 refresh 루프에 편승(별도 타이머 없음).
    /// 조회 실패한 provider 는 결과에서 빠지므로 이전 값 유지(keep-previous — flaky 엔드포인트가 앱을
    /// 흔들지 않게). 껐으면 저장된 상태를 비워 UI 에서 사라지게 한다.
    /// 트레이드오프: keep-previous 는 상한이 없어, 엔드포인트가 영구 폐기되면 마지막 값이 세션 내내
    /// 남는다. statuses 키는 항상 endpoints(claude_code·codex) 뿐이고 배너는 라이브 스냅샷과 co-gate
    /// 되므로 실질 영향은 없다(2개 안정 엔드포인트). 엔드포인트가 늘면 fetchedAt+만료를 재검토.
    private func refreshProviderStatuses() async {
        guard statusChecksEnabled else {
            if !statuses.isEmpty { statuses = [:] }
            return
        }
        let fresh = await statusProvider.fetch()
        for (id, status) in fresh { statuses[id] = status }
        if !fresh.isEmpty {
            AppLog.write("provider status: "
                + fresh.map { "\($0.key)=\($0.value.indicator.rawValue)" }.sorted().joined(separator: " "))
        }
    }

    /// 표시용 프로바이더 상태 — 조회 꺼짐이면 nil. 인시던트 없음(operational)도 반환하므로 호출부가
    /// hasIssue 로 게이트. (꺼짐 가드는 refreshProviderStatuses 의 statuses 비움과 중복이지만, 다음
    /// refresh 전에도 토글이 즉시 반영되게 여기서도 막는다.)
    func providerStatus(for providerID: String) -> ProviderStatus? {
        guard statusChecksEnabled else { return nil }
        return statuses[providerID]
    }

    /// codex 한도 스냅샷 staleness — 갱신 실패가 이어지면 이전 값이 남는다는 사실을 UI에 노출.
    /// 임계 15분은 codex TUI `RATE_LIMIT_STALE_THRESHOLD_MINUTES` 와 동일.
    var codexLimitsStale: Bool {
        guard codexLimits != nil, let codexLimitsUpdatedAt else { return false }
        return Date().timeIntervalSince(codexLimitsUpdatedAt) > 15 * 60
    }

    /// Claude 한도 staleness — Codex 와 동일 임계(15분). 429 백오프(최대 60분)로 폴링이
    /// 쉬는 동안 이전 스냅샷이 남는다는 사실을 노출한다 (프로바이더 간 표시 대칭).
    var claudeLimitsStale: Bool {
        guard limits != nil, let limitsUpdatedAt else { return false }
        return Date().timeIntervalSince(limitsUpdatedAt) > 15 * 60
    }

    // MARK: 한도 알림 (ClaudeBar 임계값 패턴)

    private var notifAuthRequested = false
    /// 팝오버 첫 오픈 등 사용자 의도 시점에 1회만 알림 권한 요청(멱등).
    func requestNotificationAuthorizationIfNeeded() {
        guard !notifAuthRequested else { return }
        guard Bundle.main.bundleIdentifier != nil, Bundle.main.bundlePath.hasSuffix(".app") else { return }
        notifAuthRequested = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// 한도 알림 1건의 발화 지시(순수 판정 결과). 부수효과와 분리해 테스트 가능하게.
    struct LimitAlert: Equatable {
        let key: String        // tier 추적·알림 identifier 용 유일 키(창마다 유일, 표시 안 함)
        let window: String     // 표시용 이름(알림 본문에 노출, 창끼리 중복 가능)
        let isCritical: Bool
        let utilization: Double
    }

    /// 알림 판정(순수·엣지 트리거) — 창별 utilization·임계값·직전 tier 상태로부터
    /// *임계값을 새로 넘어선 순간에만* 발화할 알림을 계산하고 tier 상태를 갱신한다.
    /// - 경고선 통과 1회 + 위험선 통과 1회만. 같은 tier 유지 중엔 재알림 없음(80·81·84… 억제).
    /// - utilization 이 경고선 아래로 내려가면(창 리셋 등) 재무장.
    /// - resets_at 등 매 fetch 변하는 휘발성 필드를 키에 쓰지 않는다(과거 반복-알림 회귀 원인).
    /// - 창 식별은 표시명(중복 가능)이 아니라 `key`(창마다 유일)로 한다 — 다른 두 창이 같은 표시명을
    ///   만들어도(예: Codex 다중 bucket 의 개인 한도, legacy opus 필드 vs weekly_scoped Opus 엔트리)
    ///   서로의 tier 를 덮어써 억제/중복 발화하던 회귀(#61 계열) 차단.
    static func evaluateLimitAlerts(
        windows: [(key: String, name: String, utilization: Double)],
        warn: Double, crit: Double,
        tiers: inout [String: Int]
    ) -> [LimitAlert] {
        var alerts: [LimitAlert] = []
        for (key, name, utilization) in windows {
            let tier = utilization >= crit ? 2 : (utilization >= warn ? 1 : 0)
            // 경고선 아래 → 맵에서 제거해 재무장. 0 을 저장하지 않고 제거하므로 맵은 "현재 상승
            // 중(tier≥1)인 창"만 보유 → 자연히 유한. 상한(removeAll) 을 두지 않는다 — 그 정리가
            // 임계 초과 유지 중인 창의 tier 까지 지워 스스로 재알림을 유발하는 역회귀이기 때문.
            if tier == 0 { tiers[key] = nil; continue }
            let previous = tiers[key] ?? 0
            guard tier > previous else { continue }       // 같은/낮은 tier → 재알림 안 함
            tiers[key] = tier
            alerts.append(LimitAlert(key: key, window: name, isCritical: tier == 2, utilization: utilization))
        }
        return alerts
    }

    private func checkLimitNotifications() {
        guard limitNotifications else { return }
        guard Bundle.main.bundleIdentifier != nil, Bundle.main.bundlePath.hasSuffix(".app") else { return }
        let l = L(localizationLanguage)
        // (유일 key, 표시 name, utilization). key 는 창 정체성(tier·identifier), name 은 알림 본문.
        // 팝오버가 한도 행으로 보여주는 모든 창을 알림 대상에 1:1 로 포함한다(표시=알림 일치).
        var windows: [(key: String, name: String, utilization: Double)] = []
        if let limits {
            if let u = limits.fiveHour?.utilization {
                windows.append(("claude.fiveHour", l.claudeFiveHour, u))
            }
            if let u = limits.sevenDay?.utilization {
                windows.append(("claude.sevenDay", l.claudeWeekly, u))
            }
            if let u = limits.sevenDayOpus?.utilization {
                windows.append(("claude.sevenDayOpus", "Claude \(l.weeklyOpus)", u))
            }
            if let u = limits.sevenDaySonnet?.utilization {
                windows.append(("claude.sevenDaySonnet", "Claude \(l.weeklySonnet)", u))
            }
            // 모델별 주간(weekly_scoped) 등 — 팝오버는 표시하나 알림엔 빠져 있던 창(누락 수정).
            // key 에 인덱스를 붙여 동일 kind/model 이 중복돼도 서로 안 덮어쓰게 한다.
            for (i, entry) in limits.scopedLimitEntries.enumerated() {
                guard let u = entry.percent else { continue }
                let model = entry.scope?.model?.displayName
                windows.append(("claude.scoped.\(entry.kind ?? "?").\(model ?? "?").\(i)",
                                "Claude \(l.claudeLimitEntry(kind: entry.kind, model: model))", u))
            }
        }
        for bucket in codexLimits?.visibleSnapshots ?? [] {
            let bucketKey = bucket.limitId ?? bucket.limitName ?? "codex"   // bucket 유일 식별
            let bucketName = bucket.bucketDisplayName                       // "Codex" / "Codex other" 등
            if let primary = bucket.primary {
                windows.append(("codex.\(bucketKey).primary",
                                "\(bucketName) \(l.codexWindow(primary.windowDurationMins))",
                                Double(primary.usedPercent)))
            }
            if let secondary = bucket.secondary {
                windows.append(("codex.\(bucketKey).secondary",
                                "\(bucketName) \(l.codexWindow(secondary.windowDurationMins))",
                                Double(secondary.usedPercent)))
            }
            if let individual = bucket.individualLimit {
                windows.append(("codex.\(bucketKey).individual",
                                l.codexPersonalLimit, Double(individual.usedPercent)))
            }
        }
        for alert in Self.evaluateLimitAlerts(
            windows: windows, warn: warnThreshold, crit: critThreshold, tiers: &notifiedTier)
        {
            let content = UNMutableNotificationContent()
            content.title = alert.isCritical ? l.notifCritical : l.notifWarning
            content.body = l.notifBody(alert.window, TokenFormatter.percent(alert.utilization))
            content.sound = alert.isCritical ? .default : nil
            UNUserNotificationCenter.current().add(
                UNNotificationRequest(
                    identifier: "\(alert.key)-\(alert.isCritical ? "critical" : "warning")",
                    content: content, trigger: nil))
        }
    }

    // MARK: parity-check.sh 용 스냅샷 파일

    private func writeParitySnapshot() {
        // .app 번들에서만 기록 — 테스트가 실제 사용자 데이터 디렉토리의 스냅샷을 덮어쓰지 않도록.
        guard Bundle.main.bundlePath.hasSuffix(".app") else { return }
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PokeTokenBar")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var providerEntries: [[String: Any]] = []
        for snapshot in snapshots {
            providerEntries.append([
                "id": snapshot.providerID,
                "date": snapshot.today?.date ?? "",
                "totalTokens": snapshot.todayTotalTokens,
            ])
        }
        let payload: [String: Any] = [
            "generatedAt": ISO8601DateFormatter().string(from: Date()),
            "todayTotalTokens": todayTotalTokens,
            "menuTitle": menuTitle,
            "providers": providerEntries,
            "lastError": lastErrorDescription ?? "",
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: dir.appendingPathComponent("last-snapshot.json"), options: .atomic)
        }
    }
}
