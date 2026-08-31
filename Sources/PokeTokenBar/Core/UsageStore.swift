import AppKit
import Foundation
import Observation
import PokeTokenBarShared
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
    private(set) var opencodeGoLimits: OpenCodeGoLimitStatus?
    private(set) var opencodeGoLimitsUpdatedAt: Date?
    /// OpenCode Go 폴링 예의용 마지막 시도 시각(성공·실패 무관) — 5분 최소 간격 스로틀.
    private(set) var antigravityLimits: AntigravityRateLimitStatus?
    private(set) var antigravityLimitsUpdatedAt: Date?
    private(set) var antigravityLimitsAuthExpired = false
    private(set) var limitsUpdatedAt: Date?
    private(set) var limitsAvailable = true
    /// Claude 한도 조회가 401/403(세션 만료)로 실패한 상태 — UI 에서 명확한 안내+재시도 노출용.
    /// 성공 시 해제. 자동 폴링은 무프롬프트라 만료 토큰을 스스로 못 고치므로 사용자 액션 유도가 필요.
    private(set) var limitsAuthExpired = false
    /// providerID → 프로바이더 상태 페이지 인시던트 지표(표시 전용). 조회 실패 시 이전 값 유지.
    private(set) var statuses: [String: ProviderStatus] = [:]
    private(set) var lastUpdated: Date?
    private(set) var isRefreshing = false
    private var refreshPending = false          // 진행 중 refresh 에 겹친 요청을 1회 코얼레싱(드롭 방지)
    private(set) var isRefreshingLimitToken = false
    private(set) var lastErrorDescription: String?
    private(set) var limitTokenRefreshError: String?

    // MARK: Bubble Alert State
    /// Transient speech-bubble payload for the floating pet. Cleared after the TTL.
    private(set) var currentBubbleAlert: LimitAlert?
    private var currentBubbleDate: Date = .distantPast

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
    /// 한도 % 표시 방식 — 사용한 양(기본) 또는 남은 양. 숫자 표시에만 적용되고
    /// 경고/위험 판정·게이지 채움·알림은 사용률 원값 기준을 유지한다(경고 의미론 분리).
    enum LimitDisplayMode: String, CaseIterable {
        case used, remaining
    }
    var limitDisplayMode: LimitDisplayMode {
        didSet { defaults.set(limitDisplayMode.rawValue, forKey: "limitDisplayMode") }
    }
    // 알림(독립 토글)
    var limitNotifications: Bool {
        didSet { defaults.set(limitNotifications, forKey: "limitNotifications") }
    }
    var companionNotifications: Bool {
        didSet { defaults.set(companionNotifications, forKey: "companionNotifications") }
    }
    /// 새 버전 알림(팝오버 업데이트 배너) 표시 여부 — 기본 켬. 끄면 배너 숨김(수동 확인은 설정에서 가능).
    var updateNotificationsEnabled: Bool {
        didSet { defaults.set(updateNotificationsEnabled, forKey: "updateNotificationsEnabled") }
    }
    /// 프로바이더 상태(인시던트) 조회 — 기본 켬. 표시 전용(알림 아님). Claude/OpenAI statuspage.io.
    var statusChecksEnabled: Bool {
        didSet { defaults.set(statusChecksEnabled, forKey: "statusChecksEnabled") }
    }
    // 플로팅 펫 (데스크톱 위 고정 오버레이 — 스스로 이동하지 않음, 드래그로만 위치 변경)
    var floatingPetEnabled: Bool {
        didSet { defaults.set(floatingPetEnabled, forKey: "floatingPetEnabled") }
    }
    /// 플로팅 펫 스프라이트 한 변 크기(pt).
    var floatingPetSize: Double {
        didSet { defaults.set(floatingPetSize, forKey: "floatingPetSize") }
    }
    /// Show limit alerts as speech bubbles on the floating pet. Default on; independent of Notification Center.
    var floatingPetBubbleAlerts: Bool {
        didSet { defaults.set(floatingPetBubbleAlerts, forKey: "floatingPetBubbleAlerts") }
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
    /// iPhone companion HTTP server — 기본 꺼짐. 켜면 port 7845 에 NWListener 를 열어
    /// PhonePayloadServer 가 /stats 엔드포인트로 JSON 을 서빙한다.
    var phoneServerEnabled: Bool {
        didSet {
            defaults.set(phoneServerEnabled, forKey: "phoneServerEnabled")
            if !phoneServerEnabled {
                Task { try? await CloudKitSync.delete() }
            }
        }
    }
    /// 폰이 `/stats` 를 가져올 때 제시하는 페어링 코드 — 서버는 `*:7845` 로 LAN 전체에 열리고
    /// Bonjour 로 광고까지 하므로 이 코드가 인증의 유일한 근거다. 최초 1회 생성해 보관한다.
    private(set) var phoneServerPairingCode: String {
        didSet { defaults.set(phoneServerPairingCode, forKey: "phoneServerPairingCode") }
    }

    /// 코드가 노출됐을 때(스크린샷·화면공유) 재발급. 폰은 새 코드를 다시 입력해야 한다.
    func regeneratePhoneServerPairingCode() {
        phoneServerPairingCode = PhonePairingCode.generate()
    }

    static let intervalPresets: [(label: String, value: TimeInterval)] = [
        ("수동", 0), ("1분", 60), ("2분", 120), ("5분", 300), ("15분", 900),
    ]

    /// 앱 언어 미러(알림 현지화용). 단일 소스는 CompanionStore.language —
    /// 설정 변경/기동 시 동기화한다.
    var localizationLanguage: AppLanguage = .systemDefault   // companion.language 로 재시드 전까지의 기본(실행순서 무관 안전)

    private let providers: [any UsageProvider]

    /// Registered usage sources — Settings lists these so extra scan folders
    /// stay provider-tagged (#177). Do not grow one text field per provider.
    var registeredProviders: [(id: String, displayName: String)] {
        providers.map { (id: $0.id, displayName: $0.displayName) }
    }

    /// 등록된 프로바이더 id 목록 — 확장 규약 레지스트리 무결성 테스트용.
    var registeredProviderIDs: [String] { registeredProviders.map(\.id) }

    func customScanRoots(for providerID: String) -> String {
        defaults.string(forKey: CustomScanRoots.defaultsKey(for: providerID)) ?? ""
    }

    func setCustomScanRoots(_ value: String, for providerID: String) {
        let key = CustomScanRoots.defaultsKey(for: providerID)
        let previous = defaults.string(forKey: key) ?? ""
        guard value != previous else { return }
        defaults.set(value, forKey: key)
        LocalUsageReader.invalidateProjectRootsCache()
        Task {
            await LocalAdditionalUsageReader.invalidateScanCache()
            await refresh()
        }
    }
    private let limitsProvider: any ClaudeLimitsProviding
    private let codexLimitsProvider: any CodexLimitsProviding
    private let opencodeGoLimitsProvider: any OpenCodeGoLimitsProviding
    private let antigravityLimitsProvider: any AntigravityLimitsProviding
    private let statusProvider: any ProviderStatusProviding
    /// Local limit-utilization time series. Injected so tests get a temp file instead of the
    /// user's real Application Support history.
    let limitHistory: LimitHistoryStore
    /// 설정 저장소 — 테스트는 suite 를 주입해 실제 사용자 설정을 오염시키지 않는다.
    private let defaults: UserDefaults
    private var timer: Timer?
    private var displayAsleep = false      // 디스플레이 꺼짐 동안 폴링을 늦춘다 (배터리 — 정지가 아니다)
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

    /// 오늘 사용량을 프로바이더 고유 ID별로 제공한다.
    ///
    /// companion 적립 장부는 전체 합계가 아니라 이 map을 기준으로 한다. `today == nil`인
    /// carrier snapshot이나 오늘이 아닌 snapshot은 map에서 제외한다. 그러면 프로바이더가
    /// 이번 refresh에서 보고하지 않은 경우에는 해당 프로바이더의 기존 장부를 건드리지 않고,
    /// 실제 오늘 수치가 있는 프로바이더만 증분 계산에 참여한다.
    /// 키는 `UsageProvider.id`를 그대로 사용하며, 프로바이더 등록/식별자 정책은
    /// `docs/reference/provider-extension.md`를 따른다.
    var todayTokensByProvider: [String: Int] {
        let todayKey = LocalUsageReader.todayKey()
        return snapshots.reduce(into: [:]) { result, snapshot in
            guard let today = snapshot.today, today.date == todayKey else { return }
            result[snapshot.providerID] = today.totalTokens
        }
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
        if showCostInMenu, showsCost { usage.append(TokenFormatter.costCompact(todayCostTotal)) }
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
    /// 한도 소스는 프로바이더 고유(Claude=OAuth·Codex=프로세스·Antigravity=OAuth)라 providerID 로 명시 분기(확장 규약).
    /// %는 limitDisplayMode 를 따르되 접미사 없음 — 좁은 표면이고 방향은 사용자가 고른 설정이 말해 준다
    /// (배터리 메뉴바 % 관례). 자기설명 접미사("남음")는 팝오버 행에서만.
    private var menuLimitLine: String? {
        guard showLimitInMenu else { return nil }
        let usedToday = Set(snapshots.filter { $0.todayTotalTokens > 0 }.map(\.providerID))
        var parts: [String] = []
        if usedToday.contains("claude_code"), let utilization = limits?.fiveHour?.utilization {
            parts.append("Claude \(TokenFormatter.percent(limitDisplayPercent(utilization)))")
        }
        if usedToday.contains("codex"), let usedPercent = codexLimits?.maxPrimaryUsedPercent {
            parts.append("Codex \(TokenFormatter.percent(limitDisplayPercent(Double(usedPercent))))")
        }
        if usedToday.contains("opencode"), let usedPercent = opencodeGoLimits?.maxUsedPercent {
            parts.append("OpenCode \(TokenFormatter.percent(limitDisplayPercent(Double(usedPercent))))")
        }
        if usedToday.contains("antigravity"), let usedPercent = antigravityLimits?.maxPrimaryUsedPercent {
            parts.append("AGY \(TokenFormatter.percent(limitDisplayPercent(usedPercent)))")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// 표시용 한도 % 변환 — remaining 모드면 100−사용률(0 하한: 사용률이 100 을 넘어도 음수 금지).
    /// 순수 판정을 분리해 테스트한다. 숫자 *표시* 전용 — 색·게이지·알림 판정에는 쓰지 않는다.
    nonisolated static func displayPercent(_ utilization: Double, mode: LimitDisplayMode) -> Double {
        mode == .remaining ? max(0, 100 - utilization) : utilization
    }

    func limitDisplayPercent(_ utilization: Double) -> Double {
        Self.displayPercent(utilization, mode: limitDisplayMode)
    }

    /// 단일 줄 표현 — 관찰(observeStore)·접근성·1줄 렌더 폴백용. 세로 렌더는 menuLines 사용.
    var menuTitle: String { menuLines.joined(separator: " · ") }

    /// Snapshots that participate in cost aggregates / cost UI (excludes flat-rate providers).
    var costingSnapshots: [ProviderSnapshot] { snapshots.filter(\.reportsCost) }

    /// Whether any connected provider reports real spend — gates menu/header `$0.00` for flat-rate-only setups.
    var showsCost: Bool { !costingSnapshots.isEmpty }

    var todayCostTotal: Double {
        let todayKey = LocalUsageReader.todayKey()
        return costingSnapshots.reduce(0) { $0 + ($1.today?.date == todayKey ? ($1.today?.totalCost ?? 0) : 0) }
    }

    /// 프로바이더 탭 선택 해석 — 선호 id 가 연결돼 있으면 그것, 아니면(첫 실행/연결 해제) 첫 번째.
    func snapshot(preferring id: String?) -> ProviderSnapshot? {
        if let id, let s = snapshots.first(where: { $0.providerID == id }) { return s }
        return snapshots.first
    }

    var weekTotalTokens: Int { snapshots.reduce(0) { $0 + ($1.weekTotal?.totalTokens ?? 0) } }
    var weekCostTotal: Double { costingSnapshots.reduce(0) { $0 + ($1.weekTotal?.totalCost ?? 0) } }
    var monthTotalTokens: Int { snapshots.reduce(0) { $0 + ($1.monthTotal?.totalTokens ?? 0) } }
    var monthCostTotal: Double { costingSnapshots.reduce(0) { $0 + ($1.monthTotal?.totalCost ?? 0) } }

    /// Claude 의 활성 5h 블록 — 5h forecast·"현재 블록" 행은 Claude 공식 한도와 짝이므로
    /// providerID 로 명시 조회한다 (전 프로바이더가 블록을 갖게 된 후 first-with-block 은 오매칭).
    private var claudeActiveBlock: BlockUsage? {
        snapshots.first { $0.providerID == "claude_code" }?.activeBlock
    }

    /// 전 프로바이더 활성 블록의 합산 burn (tokens/min) — companion 리듬 판정용.
    private var combinedBurnPerMinute: Double {
        snapshots.compactMap { $0.activeBlock?.tokensPerMinute }.reduce(0, +)
    }

    /// iPhone companion burn rate — public accessor for PhonePayloadServer.
    var combinedBurnPerMinuteForPhone: Double { combinedBurnPerMinute }

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
        for u in [opencodeGoLimits?.rolling?.utilization, opencodeGoLimits?.weekly?.utilization,
                  opencodeGoLimits?.monthly?.utilization] {
            if let u, u >= critThreshold { return true }
        }
        for group in antigravityLimits?.groups ?? [] {
            for bucket in group.buckets {
                if bucket.usedPercent >= critThreshold { return true }
            }
        }
        if let forecast = fiveHourForecast, forecast.beforeReset { return true }
        return false
    }

    /// Highest official-limit utilization across providers **used today** (compact surfaces only).
    /// Excludes Codex personal/spend limits (dollars). Renamed from `highestBurnPercent` —
    /// `burn` means token rate elsewhere in this codebase.
    var highestLimitUtilization: Double? {
        let usedToday = Set(snapshots.filter { $0.todayTotalTokens > 0 }.map(\.providerID))
        var utils: [Double] = []
        if usedToday.contains("claude_code") {
            for u in [limits?.fiveHour?.utilization, limits?.sevenDay?.utilization,
                      limits?.sevenDayOpus?.utilization, limits?.sevenDaySonnet?.utilization] {
                if let u { utils.append(u) }
            }
            for entry in limits?.scopedLimitEntries ?? [] {
                if let p = entry.percent { utils.append(p) }
            }
        }
        if usedToday.contains("codex") {
            for bucket in codexLimits?.visibleSnapshots ?? [] {
                if let u = bucket.primary?.usedPercent { utils.append(Double(u)) }
                if let u = bucket.secondary?.usedPercent { utils.append(Double(u)) }
                // individualLimit is a $ spend cap — intentionally omitted (candyEligibleWindows parity).
            }
        }
        if usedToday.contains("opencode") {
            for u in [opencodeGoLimits?.rolling?.utilization, opencodeGoLimits?.weekly?.utilization,
                      opencodeGoLimits?.monthly?.utilization] {
                if let u { utils.append(u) }
            }
        }
        if usedToday.contains("antigravity") {
            for group in antigravityLimits?.groups ?? [] {
                for bucket in group.buckets {
                    utils.append(bucket.usedPercent)
                }
            }
        }
        return utils.max()
    }

    /// 사탕 지급 대상 한도 창 — 세션급(≈5h)=1개, 주간급=5개, 전 프로바이더. 공식 한도 신호가 없는
    /// 프로바이더(Gemini·Hermes·Cursor·Grok)는 자연히 빠진다(창 목록에 없음).
    /// 지급 제외: Opus/Sonnet 주간·scoped·Codex 개인 spend
    /// limit(헤드라인 창의 하위/중복 → 이중지급 방지). 알림(checkLimitAlerts)보다 좁은 지급 전용.
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
        if let u = opencodeGoLimits?.rolling?.utilization {
            windows.append(CandyWindow(key: "opencodeGo.rolling", name: l.opencodeGoFiveHour,
                                       kind: .session, utilization: u))
        }
        if let u = opencodeGoLimits?.weekly?.utilization {
            windows.append(CandyWindow(key: "opencodeGo.weekly", name: l.opencodeGoWeekly,
                                       kind: .weekly, utilization: u))
        }
        // 월간은 주간급보다 긴 창이지만 지급 등급은 주간과 동일하게 취급한다(별도 등급 없음).
        if let u = opencodeGoLimits?.monthly?.utilization {
            windows.append(CandyWindow(key: "opencodeGo.monthly", name: l.opencodeGoMonthly,
                                       kind: .weekly, utilization: u))
        }
        for group in antigravityLimits?.groups ?? [] {
            let groupKey = group.displayName.localizedCaseInsensitiveContains("gemini") ? "gemini" : "3p"
            if let fiveHour = group.fiveHourBucket {
                windows.append(CandyWindow(
                    key: "antigravity.\(groupKey).5h",
                    name: "\(group.displayName) \(l.fiveHourSession)",
                    kind: .session,
                    utilization: fiveHour.usedPercent))
            }
            if let weekly = group.weeklyBucket {
                windows.append(CandyWindow(
                    key: "antigravity.\(groupKey).weekly",
                    name: "\(group.displayName) \(l.weekly)",
                    kind: .weekly,
                    utilization: weekly.usedPercent))
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
    var limitsReady: Bool { limits != nil || codexLimits != nil || opencodeGoLimits != nil || antigravityLimits != nil }

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

    init(providers: [any UsageProvider] = [
        LocalClaudeProvider(), LocalCodexProvider(), LocalGeminiProvider(),
        LocalAntigravityProvider(), LocalOpenCodeProvider(), LocalHermesProvider(),
        LocalCursorProvider(), LocalGrokProvider(), LocalCopilotProvider(), LocalKiroProvider(),
        LocalPiProvider(),
    ],
         claudeLimitsProvider: any ClaudeLimitsProviding = OAuthLimitsProvider(),
         codexLimitsProvider: any CodexLimitsProviding = CodexRateLimitsProvider(),
         opencodeGoLimitsProvider: any OpenCodeGoLimitsProviding = OpenCodeGoLimitsProvider(),
         antigravityLimitsProvider: any AntigravityLimitsProviding = AntigravityRateLimitsProvider(),
         statusProvider: any ProviderStatusProviding = StatuspageStatusProvider(),
         limitHistory: LimitHistoryStore = .shared,
         autoRefresh: Bool = true,
         remoteLimitsPollInterval: TimeInterval = LimitsPollCadence.minimumInterval,
         defaults: UserDefaults = .standard) {
        self.remoteLimitsPollInterval = remoteLimitsPollInterval
        self.providers = providers
        self.limitsProvider = claudeLimitsProvider
        self.codexLimitsProvider = codexLimitsProvider
        self.opencodeGoLimitsProvider = opencodeGoLimitsProvider
        self.antigravityLimitsProvider = antigravityLimitsProvider
        self.statusProvider = statusProvider
        self.limitHistory = limitHistory
        self.defaults = defaults
        let d = defaults
        refreshInterval = d.object(forKey: "refreshInterval") as? TimeInterval ?? 120
        warnThreshold = d.object(forKey: "warnThreshold") as? Double ?? 80
        critThreshold = d.object(forKey: "critThreshold") as? Double ?? 95
        showTokensInMenu = d.object(forKey: "showTokensInMenu") as? Bool ?? true
        showCostInMenu = d.object(forKey: "showCostInMenu") as? Bool ?? false
        showLimitInMenu = d.object(forKey: "showLimitInMenu") as? Bool ?? false
        limitDisplayMode = LimitDisplayMode(rawValue: d.string(forKey: "limitDisplayMode") ?? "") ?? .used
        limitNotifications = d.object(forKey: "limitNotifications") as? Bool ?? true
        companionNotifications = d.object(forKey: "companionNotifications") as? Bool ?? true
        updateNotificationsEnabled = d.object(forKey: "updateNotificationsEnabled") as? Bool ?? true
        statusChecksEnabled = d.object(forKey: "statusChecksEnabled") as? Bool ?? true
        floatingPetEnabled = d.object(forKey: "floatingPetEnabled") as? Bool ?? false
        floatingPetSize = d.object(forKey: "floatingPetSize") as? Double ?? 96
        floatingPetBubbleAlerts = d.object(forKey: "floatingPetBubbleAlerts") as? Bool ?? true
        disableKeychainAccess = d.object(forKey: "disableKeychainAccess") as? Bool ?? false
        phoneServerEnabled = d.object(forKey: "phoneServerEnabled") as? Bool ?? false
        // 저장된 코드가 없으면(최초 실행·기존 사용자 업그레이드) 지금 발급한다. didSet 은 init 에서
        // 돌지 않으므로 영속화를 여기서 명시적으로 한다 — 안 하면 매 기동마다 코드가 바뀌어
        // 폰이 계속 페어링을 다시 요구받는다.
        let storedPairingCode = d.string(forKey: "phoneServerPairingCode") ?? ""
        phoneServerPairingCode = storedPairingCode.isEmpty
            ? PhonePairingCode.generate()
            : storedPairingCode
        if storedPairingCode.isEmpty {
            d.set(phoneServerPairingCode, forKey: "phoneServerPairingCode")
        }

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
        // 디스플레이 꺼짐 → 폴링(ccusage 서브프로세스 spawn) 감속, 켜짐 → 원래 주기 복귀 + 즉시 갱신 (배터리)
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.slowPollingForDisplaySleep() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.restoreFullPolling() }
        }

        // 알림 권한은 기동 즉시 묻지 않는다 — 앱을 이해하기 전 콜드 프롬프트는 거부율이 높고
        // 거부 시 재요청 경로가 없다. 팝오버 첫 오픈(사용자 의도)에 requestNotificationAuthorizationIfNeeded 로 1회 요청.
        if autoRefresh { Task { await refresh() } }
    }

    /// 디스플레이가 꺼져 있는 동안의 폴링 주기 **하한**.
    ///
    /// 화면이 꺼졌다고 폴링을 *멈추면* 안 된다. iCloud 페이로드는 refresh 완료 훅에서만 나가므로
    /// (`AppDelegate.onStoreRefreshed` → `buildAndPublishPayload` → `CloudKitSync.save`) 폴링이 멈추면
    /// **iPhone 앱이 그대로 굳는다** — Mac 이 깨어서 토큰을 쓰는 중이어도 화면만 꺼져 있으면 폰은 영영
    /// 옛 숫자를 본다(실측 2026-08-29: 화면 꺼짐 4h24m·32m 동안 refresh 0건, 폰은 stale 표시).
    /// 화면 뒤에 사람이 없다는 전제 자체는 여전히 맞으므로 *늦추되*, 폰의 stale 기준
    /// (`DashboardView.isStale` 의 30분)보다 넉넉히 짧게 유지한다.
    static let displayAsleepMinimumInterval: TimeInterval = 300

    /// 실제 타이머 주기 — 화면 상태를 반영한 순수 함수(테스트 시임).
    /// `base == 0`(수동 모드)은 화면 상태와 무관하게 0 이다 — 수동은 사용자가 고른 것이라 뒤집지 않는다.
    static func effectiveRefreshInterval(base: TimeInterval, displayAsleep: Bool) -> TimeInterval {
        guard base > 0 else { return 0 }
        return displayAsleep ? max(base, displayAsleepMinimumInterval) : base
    }

    /// 현재 스케줄된 폴링 주기(타이머 없으면 nil) — 화면 슬립 회귀 가드가 "타이머가 살아 있는가"를 본다.
    var scheduledPollingInterval: TimeInterval? { timer?.timeInterval }

    private func reschedule() {
        timer?.invalidate()
        timer = nil
        let interval = Self.effectiveRefreshInterval(base: refreshInterval, displayAsleep: displayAsleep)
        guard interval > 0 else { return }
        let t = Timer(timeInterval: interval, repeats: true) { _ in
            Task { @MainActor [weak self] in await self?.refresh() }
        }
        t.tolerance = interval * 0.1
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// 디스플레이 꺼짐 → 폴링을 멈추지 않고 늦춘다(`displayAsleepMinimumInterval` 하한).
    /// internal 인 이유는 회귀 가드가 이 정책 지점을 직접 부르기 때문 — 알림 배달은 별도 배선 테스트가 본다.
    func slowPollingForDisplaySleep() {
        displayAsleep = true
        reschedule()
    }

    /// 디스플레이 켜짐 → 원래 주기 복귀 + 즉시 1회 갱신(켜졌을 때 메뉴 숫자 최신화).
    func restoreFullPolling() {
        guard displayAsleep else { return }
        displayAsleep = false
        reschedule()
        Task { await refresh() }
    }

    // MARK: 갱신

    func refresh(scheduleEmptyRetry: Bool = true) async {
        // 진행 중이면 드롭하지 말고 예약 — 완료 후 1회 재실행(코얼레싱). 수동모드(interval 0)에서 키체인
        // 재활성(disableKeychainAccess didSet)의 refresh 가 in-flight 폴에 묻혀, 자동폴이 없는 탓에
        // Claude 한도가 다음 수동 액션까지 빈 채로 남던 회귀 방지.
        if isRefreshing { refreshPending = true; return }
        isRefreshing = true
        // App Nap 방지 — 백그라운드 스로틀로 ccusage 가 타임아웃되는 것을 막는다 (시스템 슬립은 허용)
        let activity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep, reason: "PokeTokenBar usage refresh")
        defer {
            ProcessInfo.processInfo.endActivity(activity)
            isRefreshing = false
            // 진행 중 겹쳐 들어온 요청을 1회 반영. 요청 도착률이 유한하므로 무한 재실행 없음.
            if refreshPending {
                refreshPending = false
                Task { await self.refresh(scheduleEmptyRetry: scheduleEmptyRetry) }
            }
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
                AppLog.writeIfChanged("phase1-recv-\(outcome.id)",
                                      "phase1 recv id=\(outcome.id) today=\(outcome.today?.totalTokens.description ?? "nil") err=\(outcome.errorDescription ?? "none")")
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
                if let previous = prevToday, fetched.totalTokens < previous.totalTokens {
                    AppLog.write("usage regression provider=\(provider.id) date=\(fetched.date) previous=\(previous.totalTokens) current=\(fetched.totalTokens) drop=\(previous.totalTokens - fetched.totalTokens) — provider returned lower daily snapshot")
                }
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
                    fetchedAt: Date(),
                    reportsCost: provider.reportsCost))
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
                            fetchedAt: Date(),
                            reportsCost: provider.reportsCost))
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
            AppLog.writeIfChanged("claude-limits", "claude limits skipped: keychain access disabled")
        } else if let until = claudeLimitsBackoffUntil, Date() < until {
            // 429 백오프 중 — 폴링을 쉬어 rate limit 악화 방지 (버그 리포트 실측: 매분 429 재시도)
            AppLog.write("claude limits backoff: skipping (\(Int(until.timeIntervalSinceNow))s left)")
        } else if !LimitsPollCadence.shouldFetch(lastAttemptAt: lastRemoteLimitsAttempt["claude_code"],
                                                        minimumInterval: remoteLimitsPollInterval) {
            // 사용량 스캔 주기와 분리 — 자세한 이유는 LimitsPollCadence.
        } else {
            do {
                lastRemoteLimitsAttempt["claude_code"] = Date()
                limits = try await limitsProvider.fetch(allowKeychainPrompt: false)
                limitsAvailable = true
                limitsUpdatedAt = Date()
                limitsAuthExpired = false
                resetLimitsBackoff()
                recordLimitHistory()
                AppLog.write("limits refreshed fiveHour=\(limits?.fiveHour?.utilization?.description ?? "nil") sevenDay=\(limits?.sevenDay?.utilization?.description ?? "nil")")
            } catch {
                // 비공식 endpoint 실패 → 섹션 숨김, 토큰 표시는 무영향
                if limits == nil { limitsAvailable = false }
                updateAuthExpired(from: error)
                applyLimitsBackoffIfRateLimited(error)
                AppLog.writeIfChanged("claude-limits", "limits unavailable: \(error)")
            }
        }
        await refreshCodexLimits()
        await refreshOpenCodeGoLimits()
        await refreshAntigravityLimits(allowKeychainPrompt: false)
        await refreshProviderStatuses()

        checkLimitAlerts()
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

    /// Append the freshly fetched limit windows to the local history series.
    ///
    /// Both fetch paths call this rather than only the timer one: the automatic poll never touches
    /// the Keychain, so on machines where the token only ever arrives via the manual refresh button
    /// the timer path succeeds zero times and history would stay permanently empty.
    private func recordLimitHistory() {
        guard let limits else { return }
        limitHistory.record(providerID: "claude_code",
                            windows: LimitHistoryStore.claudeWindows(from: limits))
    }

    func refreshLimitTokenFromKeychain() async {
        guard !isRefreshingLimitToken else { return }
        isRefreshingLimitToken = true
        defer { isRefreshingLimitToken = false }

        do {
            // 명시적 사용자 액션은 백오프를 우회해 1회 시도 — 성공하면 백오프 해제.
            // 간격 게이트도 우회하지만 시도 시각은 남긴다(직후 자동 폴의 중복 호출 방지).
            lastRemoteLimitsAttempt["claude_code"] = Date()
            limits = try await limitsProvider.fetch(allowKeychainPrompt: true)
            limitsAvailable = true
            limitsUpdatedAt = Date()
            limitsAuthExpired = false
            limitTokenRefreshError = nil
            resetLimitsBackoff()
            recordLimitHistory()
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

    func refreshAntigravityLimitsFromKeychain() async {
        await refreshAntigravityLimits(allowKeychainPrompt: true)
    }

    private func refreshAntigravityLimits(allowKeychainPrompt: Bool) async {
        if disableKeychainAccess {
            antigravityLimits = nil
            antigravityLimitsAuthExpired = false
            return
        }
        // 사용자가 갱신을 누른 경로(allowKeychainPrompt)는 간격을 무시한다 — 누른 즉시 답이 나와야 한다.
        // 그래도 시도 시각은 기록해, 직후의 자동 폴이 같은 endpoint 를 곧바로 다시 두드리지 않게 한다.
        if !allowKeychainPrompt,
           !LimitsPollCadence.shouldFetch(lastAttemptAt: lastRemoteLimitsAttempt["antigravity"],
                                          minimumInterval: remoteLimitsPollInterval) {
            return
        }
        lastRemoteLimitsAttempt["antigravity"] = Date()
        do {
            let status = try await antigravityLimitsProvider.fetch(allowKeychainPrompt: allowKeychainPrompt)
            antigravityLimits = status
            antigravityLimitsUpdatedAt = Date()
            antigravityLimitsAuthExpired = false
            let groupsDesc = status.groups.map { group in
                "\(group.displayName): " + group.buckets.map { "\($0.bucketId)=\(String(format: "%.1f", $0.usedPercent))%" }.joined(separator: ", ")
            }.joined(separator: " | ")
            AppLog.write("antigravity limits refreshed [\(groupsDesc)]")
        } catch {
            if case LimitsError.httpStatus(let code) = error, code == 401 || code == 403 {
                antigravityLimitsAuthExpired = true
            }
            AppLog.writeIfChanged("antigravity-limits", "antigravity limits unavailable: \(error)")
        }
    }

    /// 401/403(세션 만료)면 auth-expired 플래그를 세운다. 다른 오류(네트워크·키체인 잠금 등)는
    /// 만료가 아니므로 건드리지 않는다 — 오탐으로 "세션 만료" 안내를 띄우지 않기 위함.
    private func updateAuthExpired(from error: any Error) {
        if case LimitsError.httpStatus(let status) = error, status == 401 || status == 403 {
            limitsAuthExpired = true
        }
    }

    // MARK: 원격 한도 조회 간격

    /// 프로바이더별 마지막 **시도** 시각. 사용량 스캔 틱마다 외부 endpoint 를 두드리지 않기 위한
    /// 게이트의 상태다(`LimitsPollCadence`). 로컬 자식 프로세스로 답하는 Codex 는 대상이 아니다 —
    /// rate limit 이 걸릴 원격 endpoint 가 없다.
    private var lastRemoteLimitsAttempt: [String: Date] = [:]

    /// 주입 가능 — 0 을 넘기면 게이트가 사실상 꺼진다. 간격과 무관한 동작(401 해제 등)을 검증하는
    /// 테스트가 "두 번째 refresh 가 실제로 조회한다"를 전제할 수 있어야 한다.
    private let remoteLimitsPollInterval: TimeInterval

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
        case .credentialMissingAccountOAuth:
            return l.limitRefreshReauthNeeded
        // liveFetchNotPermitted 는 실앱에선 발생하지 않는다(번들 게이트가 열려 있다) — 문구는 generic.
        case .keychainInteractionNotAllowed, .keychainAccessDisabled, .liveFetchNotPermitted:
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
                AppLog.writeIfChanged("codex-limits", "codex limits skipped: codex binary not found")
            }
        } catch {
            AppLog.write("codex limits unavailable: \(error)")
        }
    }

    private func refreshOpenCodeGoLimits() async {
        // 이 프로바이더가 먼저 쓰던 전용 스로틀(`opencodeGoPollInterval`)을 공용 게이트로 합쳤다 —
        // 같은 판정이 두 벌 있으면 한쪽만 고쳐지고 다른 쪽이 남는다(defect-log 동일 항목).
        guard LimitsPollCadence.shouldFetch(lastAttemptAt: lastRemoteLimitsAttempt["opencode_go"],
                                            minimumInterval: remoteLimitsPollInterval) else { return }
        lastRemoteLimitsAttempt["opencode_go"] = Date()
        do {
            if let status = try await opencodeGoLimitsProvider.fetch() {
                opencodeGoLimits = status
                opencodeGoLimitsUpdatedAt = Date()
                func pct(_ window: OpenCodeGoLimitWindow?) -> String {
                    window.flatMap { $0.percent.map(String.init) } ?? "nil"
                }
                AppLog.writeIfChanged("opencode-go-limits",
                                      "opencode go limits refreshed rolling=\(pct(status.rolling)) weekly=\(pct(status.weekly)) monthly=\(pct(status.monthly))")
            } else {
                AppLog.writeIfChanged("opencode-go-limits", "opencode go limits skipped: no opencode-go key in auth.json")
            }
        } catch {
            // 401/403(미구독·불명 키)·네트워크 실패 → 이전 값 유지(codex 와 동일). 섹션은 표시값이
            // 있으면 그대로 두고, 갱신이 15분+ 이어지지 않으면 stale 배지로 노출된다.
            AppLog.writeIfChanged("opencode-go-limits", "opencode go limits unavailable: \(error)")
        }
    }

    /// Antigravity 한도 staleness — 15분 경과 시 stale
    var antigravityLimitsStale: Bool {
        guard antigravityLimits != nil, let antigravityLimitsUpdatedAt else { return false }
        return Date().timeIntervalSince(antigravityLimitsUpdatedAt) > 15 * 60
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
            AppLog.writeIfChanged("provider-status", "provider status: "
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

    /// OpenCode Go 한도 staleness — Claude/Codex 와 동일 임계(15분). 폴링 스로틀(5분) 때문에
    /// 정상 최대 지연은 5분이고, 15분 초과는 갱신 실패가 이어진다는 뜻이다.
    var opencodeGoLimitsStale: Bool {
        guard opencodeGoLimits != nil, let opencodeGoLimitsUpdatedAt else { return false }
        return Date().timeIntervalSince(opencodeGoLimitsUpdatedAt) > 15 * 60
    }

    // MARK: 한도 알림 (ClaudeBar 임계값 패턴)

    private var notifAuthRequested = false
    /// 팝오버 첫 오픈 등 사용자 의도 시점에 1회만 알림 권한 요청(멱등).
    func requestNotificationAuthorizationIfNeeded() {
        guard !notifAuthRequested else { return }
        guard AppEnv.isBundledApp else { return }
        notifAuthRequested = true
        Task {
            try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        }
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

    /// Pick the single bubble to show for a refresh: critical > warn, then highest utilization.
    /// Pure — separate from AppKit presentation (issue #109 testing requirement).
    static func bubbleAlert(from alerts: [LimitAlert]) -> LimitAlert? {
        alerts.max { a, b in
            if a.isCritical != b.isCritical { return !a.isCritical && b.isCritical }
            return a.utilization < b.utilization
        }
    }

    /// Whether a bubble shown at `shownAt` should clear by `now` (default TTL 6s). Pure time check.
    static func shouldDismissBubble(shownAt: Date, now: Date, ttl: TimeInterval = 6) -> Bool {
        now.timeIntervalSince(shownAt) >= ttl
    }

    /// Shared limit-alert pipeline: evaluate once, advance tiers once, then fan out to
    /// Notification Center and/or the floating-pet bubble under independent gates.
    private func checkLimitAlerts() {
        let windows = buildLimitWindows()
        let alerts = Self.evaluateLimitAlerts(
            windows: windows, warn: warnThreshold, crit: critThreshold, tiers: &notifiedTier)
        guard !alerts.isEmpty else { return }

        if limitNotifications, AppEnv.isBundledApp {
            postLimitNotifications(alerts)
        }
        if floatingPetEnabled, floatingPetBubbleAlerts {
            showBubble(Self.bubbleAlert(from: alerts))
        }
    }

    /// (unique key, display name, utilization) for every window the popover shows as a limit row.
    private func buildLimitWindows() -> [(key: String, name: String, utilization: Double)] {
        let l = L(localizationLanguage)
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
        if let goLimits = opencodeGoLimits {
            if let u = goLimits.rolling?.utilization {
                windows.append(("opencodeGo.rolling", l.opencodeGoFiveHour, u))
            }
            if let u = goLimits.weekly?.utilization {
                windows.append(("opencodeGo.weekly", l.opencodeGoWeekly, u))
            }
            if let u = goLimits.monthly?.utilization {
                windows.append(("opencodeGo.monthly", l.opencodeGoMonthly, u))
            }
        }
        for group in antigravityLimits?.groups ?? [] {
            let groupKey = group.displayName.localizedCaseInsensitiveContains("gemini") ? "gemini" : "3p"
            for bucket in group.buckets {
                let windowName = l.antigravityWindow(window: bucket.window, bucketId: bucket.bucketId)
                windows.append(("antigravity.\(groupKey).\(bucket.bucketId)",
                                "\(group.displayName) \(windowName)",
                                bucket.usedPercent))
            }
        }
        return windows
    }

    private func postLimitNotifications(_ alerts: [LimitAlert]) {
        let l = L(localizationLanguage)
        for alert in alerts {
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

    private func showBubble(_ alert: LimitAlert?) {
        guard let alert else { return }
        let now = Date()
        currentBubbleAlert = alert
        currentBubbleDate = now
        Task {
            try? await Task.sleep(nanoseconds: UInt64(6 * 1_000_000_000))
            if Self.shouldDismissBubble(shownAt: now, now: Date()), self.currentBubbleDate == now {
                self.currentBubbleAlert = nil
            }
        }
    }

    // MARK: parity-check.sh 용 스냅샷 파일

    private func writeParitySnapshot() {
        // .app 번들에서만 기록 — 테스트가 실제 사용자 데이터 디렉토리의 스냅샷을 덮어쓰지 않도록.
        guard AppEnv.isBundledApp else { return }
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
