import AppKit
import SwiftUI

enum PopoverTab { case home, shop, bag, collection }

/// 팝오버 치수의 단일 소스. 자식이 쓸 수 있는 폭을 알아야 할 때 이 값을 쓴다 — 넘치는 자식이
/// 부모 폭을 부풀리므로 GeometryReader 로 재면 순환한다.
enum PopoverMetrics {
    static let width: CGFloat = 360
    static let padding: CGFloat = 14
    /// 이 폭을 넘는 자식은 팝오버 창에 좌우로 잘린다.
    static let contentWidth: CGFloat = width - padding * 2
}

/// 팝오버 내부 내비게이션 상태(현재 탭 / 컬렉션 세그먼트 / 설정 표시 여부).
/// NSHostingController 는 팝오버를 닫아도 재사용되어 @State 가 유지되므로, 화면 상태를 이
/// Observable 로 분리해 AppDelegate 가 팝오버를 열 때마다 reset() 한다 — 닫혔다 열리면 항상 Home.
@MainActor
@Observable
final class PopoverNavigation {
    var showSettings = false
    var tab: PopoverTab = .home
    /// 일반적인 컬렉션 재진입에는 마지막 세그먼트를 유지하되, 대표 포켓몬 선택 진입점은 도감으로 강제한다.
    var showingCollectionLog = false
    /// 프로바이더 탭 선택 — reset() 대상이 아님(팝오버를 다시 열어도 보던 서비스 유지).
    var providerID: String?
    /// 설정을 열 때 고급 섹션을 펼친 채로 시작할지. 세션 키 행이 접힌 disclosure 안에 살아서,
    /// 그냥 설정만 열면 "만료됐다"를 보고 들어온 사용자가 고칠 입력란을 못 찾는다.
    var expandAdvancedOnOpen = false

    func reset() {
        showSettings = false
        expandAdvancedOnOpen = false
        tab = .home
    }

    /// 세션 키 만료 안내 → 그 키를 고칠 수 있는 유일한 화면으로 바로 보낸다.
    func openSessionKeySettings() {
        showSettings = true
        expandAdvancedOnOpen = true
    }

    /// 설정의 대표 포켓몬 행에서 기존 도감으로 이동한다. 별도 선택 화면을 만들지 않고
    /// 컬렉션 세그먼트를 도감으로 명시해, 직전에 포획 로그를 봤어도 선택 액션이 있는 화면을 연다.
    func openRepresentativeDex() {
        showSettings = false
        showingCollectionLog = false
        tab = .collection
    }
}

@MainActor
struct PopoverView: View {
    @Environment(UsageStore.self) private var store
    @Environment(CompanionStore.self) private var companion
    @Environment(UpdateChecker.self) private var updater
    @Environment(PopoverNavigation.self) private var nav

    private var l: L { companion.l }

    var body: some View {
        // NOTE: 설정을 .sheet 로 띄우면 transient 팝오버가 닫힐 때 시트가 고아로 남아
        // 이후 팝오버의 모든 버튼 클릭을 차단할 수 있음 — 팝오버 내부 화면 전환으로 처리
        @Bindable var nav = nav
        Group {
            if nav.showSettings {
                SettingsView(
                    onClose: { nav.showSettings = false },
                    onChooseRepresentative: { nav.openRepresentativeDex() },
                    startExpanded: nav.expandAdvancedOnOpen
                )
                    .environment(store)
                    .environment(companion)
                    .environment(updater)
            } else {
                mainContent
            }
        }
        .frame(width: PopoverMetrics.width)
        .environment(\.locale, companion.language.displayLocale)
    }

    @ViewBuilder
    private var updateBanner: some View {
        if let update = updater.available, store.updateNotificationsEnabled {
            HStack(spacing: 8) {
                Text(l.updateAvailable(update.version, current: updater.currentVersion))
                    .font(.caption)
                Spacer()
                if updater.isUpdating {
                    Text(l.updating).font(.caption2).foregroundStyle(.secondary)
                    ProgressView().controlSize(.small)
                } else {
                    Button(l.updateButton) { updater.applyUpdate() }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                    Button(l.updateLater) { updater.skipCurrent() }
                        .buttonStyle(.borderless).controlSize(.small).foregroundStyle(.secondary)
                }
            }
            .padding(8)
            .background(Color.accentColor.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var mainContent: some View {
        @Bindable var nav = nav
        return VStack(alignment: .leading, spacing: 12) {
            updateBanner
            Picker("", selection: $nav.tab) {
                Text(l.home).tag(PopoverTab.home)
                Text(l.shop).tag(PopoverTab.shop)
                Text(l.bag).tag(PopoverTab.bag)
                Text(l.collection).tag(PopoverTab.collection)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if nav.tab == .collection {
                CollectionView(store: companion, navigation: nav)
            } else if nav.tab == .bag {
                BagView(store: companion, nav: nav)
            } else if nav.tab == .shop {
                ShopView(store: companion, nav: nav)
            } else {
                CompanionHeader(store: companion)
                Divider()
                header
                Divider()
                providerStatusBanner   // 인시던트 있을 때만 — 한도 가용 여부와 무관(API 다운=한도 nil 케이스에도)
                if selectedProviderHasLimits {
                    limitsSection
                    Divider()
                }
                if selectedSnapshot?.providerID == "claude_code", store.limits != nil {
                    limitHistorySection
                    Divider()
                }
            }
            footer
        }
        .padding(PopoverMetrics.padding)
    }

    // MARK: 헤더 — 오늘 합계 + provider/토큰타입 분해

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(l.todayTokens)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline) {
                Text(TokenFormatter.compact(store.todayTotalTokens))
                    .font(.system(size: 28, weight: .bold))
                    .monospacedDigit()
                Text(TokenFormatter.grouped(store.todayTotalTokens))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                if store.showsCost {
                    Text(TokenFormatter.cost(todayCost))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            // 주간/월간 누적 (전 서비스 합산 — 오늘 합계와 함께 통합 통계)
            if store.weekTotalTokens > 0 || store.monthTotalTokens > 0 {
                HStack(spacing: 14) {
                    periodLabel(l.thisWeek, tokens: store.weekTotalTokens, cost: store.showsCost ? store.weekCostTotal : nil)
                    periodLabel(l.thisMonth, tokens: store.monthTotalTokens, cost: store.showsCost ? store.monthCostTotal : nil)
                    Spacer()
                }
                .padding(.top, 2)
            }

            // 연결된 서비스가 2개 이상이면 작은 탭으로 서비스별 상세를 넘나든다
            // (합계는 위에 유지 — 상세·한도만 탭 스코프).
            if store.snapshots.count > 1 {
                providerTabBar
                    .padding(.top, 6)
            }
            if let snap = selectedSnapshot, let today = snap.today {
                providerRow(snapshot: snap, today: today)
            }
        }
    }

    /// 현재 선택된 프로바이더 스냅샷 — 선택이 없거나 연결 해제됐으면 첫 번째로 폴백.
    private var selectedSnapshot: ProviderSnapshot? {
        store.snapshot(preferring: nav.providerID)
    }

    private var providerTabBar: some View {
        ProviderTabBar(
            snapshots: store.snapshots,
            selectedID: selectedSnapshot?.providerID,
            onSelect: { nav.providerID = $0 })
    }

    private func periodLabel(_ name: String, tokens: Int, cost: Double?) -> some View {
        HStack(spacing: 4) {
            Text(name)
                .font(.caption)
                .foregroundStyle(.tertiary)
            Text(TokenFormatter.compact(tokens))
                .font(.caption.weight(.semibold))
                .monospacedDigit()
            if let cost {
                Text(TokenFormatter.cost(cost))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var todayCost: Double {
        store.costingSnapshots.reduce(0) { $0 + ($1.today?.totalCost ?? 0) }
    }

    private func providerRow(snapshot: ProviderSnapshot, today: DailyUsage) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(snapshot.displayName)
                    .font(.callout.weight(.semibold))
                Spacer()
                Text(TokenFormatter.compact(today.totalTokens))
                    .font(.callout)
                    .monospacedDigit()
                if snapshot.reportsCost {
                    Text(TokenFormatter.cost(today.totalCost))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 10) {
                tokenTypeLabel("in", today.inputTokens)
                tokenTypeLabel("out", today.outputTokens)
                tokenTypeLabel("cache w", today.cacheCreationTokens)
                tokenTypeLabel("cache r", today.cacheReadTokens)
            }
            if let models = today.models, models.count > 1 {
                ForEach(models.sorted(by: { $0.value > $1.value }), id: \.key) { model, tokens in
                    HStack(spacing: 6) {
                        Text(model.split(separator: "/").last.map(String.init) ?? model)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text(TokenFormatter.compact(tokens))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                    }
                }
            }
        }
        .padding(.top, 2)
    }

    private func tokenTypeLabel(_ name: String, _ value: Int) -> some View {
        HStack(spacing: 3) {
            Text(name)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(TokenFormatter.compact(value))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    // MARK: 한도 섹션 — 공식 5h/주간 % + 리셋 카운트다운

    /// 선택된 프로바이더에 표시할 공식 한도가 있는가 (Gemini 는 공식 한도 API 없음 → 섹션 생략).
    private var selectedProviderHasLimits: Bool {
        switch selectedSnapshot?.providerID {
        // Keychain 이 꺼져있지 않으면 한도가 아직 없어도 섹션을 노출한다 — 그래야 최초 실행에
        // claudeLimitsRefreshRow("탭해서 로드")가 보여, 설정까지 안 들어가도 원탭으로 켤 수 있다.
        // (자동 Keychain 읽기는 팝업 방지로 여전히 안 함 — 발견성만 살린다.)
        case "claude_code": return !store.disableKeychainAccess || store.limits != nil || store.limitsAuthExpired
        case "codex": return store.codexLimits?.hasVisibleLimit == true
        // OpenCode Go 구독 한도 — auth.json 의 opencode-go 키가 있을 때만 endpoint 가 200 을
        // 주므로, 로드된 한도가 있을 때만 섹션을 노출한다(zen 페이즈유고 사용자는 빈 섹션 안 뜸).
        case "opencode": return store.opencodeGoLimits?.hasVisibleLimit == true
        case "antigravity": return !store.disableKeychainAccess || store.antigravityLimits?.hasVisibleLimit == true || store.antigravityLimitsAuthExpired
        default: return false
        }
    }

    /// 선택 프로바이더의 상태 페이지 인시던트(있을 때만) — Claude/OpenAI API 장애를 앱 고장으로
    /// 오인하지 않게. 표시 전용(알림 아님). 인시던트 없거나 상태조회 꺼짐이면 아무것도 안 그림.
    /// 범위(v1): 선택된 provider 탭 한정. 오늘 안 쓴 provider 는 탭/스냅샷이 없어 배너도 안 뜬다 —
    /// 오인이 실제로 생기는 케이스(오늘 써서 이상 수치를 보는데 한도는 nil)는 로컬 사용 스냅샷이 있어
    /// 탭이 존재하므로 커버된다. 전 provider 전역 인시던트 행은 추후.
    @ViewBuilder
    private var providerStatusBanner: some View {
        if let id = selectedSnapshot?.providerID,
           let status = store.providerStatus(for: id), status.indicator.hasIssue {
            HStack(spacing: 6) {
                Circle().fill(statusColor(status.indicator)).frame(width: 7, height: 7)
                Text(l.providerStatusLabel(status.indicator))
                    .font(.caption).fontWeight(.medium)
                if !status.description.isEmpty {
                    Text(status.description)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
            }
        }
    }

    private func statusColor(_ indicator: ProviderStatusIndicator) -> Color {
        switch indicator {
        case .operational:         return .green
        case .minor, .maintenance: return .yellow
        case .major:               return .orange
        case .critical:            return .red
        case .unknown:             return .gray
        }
    }

    @ViewBuilder
    private var limitsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(l.limitsOfficial)
                .font(.caption)
                .foregroundStyle(.secondary)
            if selectedSnapshot?.providerID == "claude_code", store.limitsAuthExpiry == .sessionKey {
                sessionKeyExpiredNotice
            } else if selectedSnapshot?.providerID == "claude_code", store.limitsAuthExpired {
                claudeAuthExpiredNotice
            } else if selectedSnapshot?.providerID == "claude_code",
                      !store.disableKeychainAccess,
                      store.limits == nil || store.claudeLimitsStale {
                // 자동 폴링은 Keychain 을 안 읽으므로(팝업 방지), 최초/만료 후 공식 한도는 이 원탭으로
                // 사용자가 직접 갱신한다. 프롬프트가 뜨더라도 사용자 행동에 의한 것이라 예상 가능하다.
                claudeLimitsRefreshRow
            }
            // antigravity 와 같은 이유 — 버튼은 팝오버에 있는데 사유가 설정 화면에만 있으면 무반응으로 보인다.
            if selectedSnapshot?.providerID == "claude_code",
               let refreshError = store.limitTokenRefreshError {
                Text(refreshError)
                    .font(.caption2).foregroundStyle(.orange).lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if selectedSnapshot?.providerID == "claude_code", let limits = store.limits {
                // 플랜(계정 속성) — Codex codexMetaRow 와 동일 스타일. 구독 정보 있을 때만 노출.
                if let plan = limits.planDisplay {
                    Text(l.plan(plan))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                // 계정 라벨 — 두 계정이 한 Keychain 항목을 번갈아 쓰는 기기에서 이 한도가
                // 어느 계정 것인지 알려준다 (없으면 라벨 없이 종전과 동일).
                if let account = limits.accountDisplay {
                    Text(l.limitsAccount(account))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                // 세션 만료 시 표시값은 만료 전 기준 → 흐리게 처리해 "현재 값 아님"을 시각적으로 전달
                VStack(alignment: .leading, spacing: 8) {
                    limitRow(name: l.fiveHourSession, window: limits.fiveHour)
                    forecastRow
                    limitRow(name: l.weekly, window: limits.sevenDay)
                    limitRow(name: l.weeklyOpus, window: limits.sevenDayOpus)
                    limitRow(name: l.weeklySonnet, window: limits.sevenDaySonnet)
                    // 신형 limits[] — 모델별 주간(weekly_scoped) 등 레거시 필드 밖 윈도우
                    ForEach(Array(limits.scopedLimitEntries.enumerated()), id: \.offset) { _, entry in
                        limitRow(
                            name: l.claudeLimitEntry(kind: entry.kind, model: entry.scope?.model?.displayName),
                            window: LimitWindow(utilization: entry.percent, resetsAt: entry.resetsAt))
                    }
                    // 전 프로바이더가 블록을 갖게 됨 — "Claude 현재 5h 블록" 행은 명시 조회
                    if let block = store.snapshots.first(where: { $0.providerID == "claude_code" })?.activeBlock,
                       let end = block.endDate {
                        HStack {
                            Text(l.claudeCurrentBlock)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(TokenFormatter.compact(block.totalTokens))
                                .font(.caption)
                                .monospacedDigit()
                            Spacer()
                            (Text("\(l.reset) ") + Text(end, style: .relative))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .opacity(store.limitsAuthExpired ? 0.5 : 1)
            }
            if selectedSnapshot?.providerID == "codex",
               let codexStatus = store.codexLimits, codexStatus.hasVisibleLimit {
                let buckets = codexStatus.visibleSnapshots
                codexMetaRow(codexStatus)
                // id 는 offset — limitId 가 nil 인 bucket 이 2개 이상이면 \.limitId 는 충돌(행 누락)한다.
                // snapshots 순서는 결정적(sorted)이라 offset 안정. (scopedLimitEntries 와 동일 방식)
                ForEach(Array(buckets.enumerated()), id: \.offset) { _, bucket in
                    // bucket 이 여럿일 때만 구분 라벨 (단일 bucket 사용자는 기존 UI 그대로)
                    if buckets.count > 1 {
                        Text(bucket.bucketDisplayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                    }
                    codexLimitRow(name: l.codexWindow(bucket.primary?.windowDurationMins), window: bucket.primary)
                    codexLimitRow(name: l.codexWindow(bucket.secondary?.windowDurationMins), window: bucket.secondary)
                    codexSpendLimitRow(bucket.individualLimit)
                }
            }
            // OpenCode Go 구독 한도 — 5h rolling / 주간 / 월간 세 창(Claude/Codex 행과 동일 스타일).
            if selectedSnapshot?.providerID == "opencode",
               let goStatus = store.opencodeGoLimits, goStatus.hasVisibleLimit {
                opencodeGoMetaRow(goStatus)
                limitRow(name: l.fiveHourSession, window: goStatus.rolling.map(Self.limitWindow))
                limitRow(name: l.weekly, window: goStatus.weekly.map(Self.limitWindow))
                limitRow(name: l.monthly, window: goStatus.monthly.map(Self.limitWindow))
            }
            if selectedSnapshot?.providerID == "antigravity" {
                antigravityLimitsContent
            }
        }
    }

    /// OpenCodeGoLimitWindow → 표시용 LimitWindow 변환 — 기존 limitRow 렌더러를 그대로 재사용한다.
    private static func limitWindow(_ window: OpenCodeGoLimitWindow) -> LimitWindow {
        LimitWindow(utilization: window.utilization, resetsAt: window.resetsAt)
    }

    /// OpenCode Go 메타 행 — 플랜 정보는 응답에 없으므로 "한도 도달"·stale 배지만 표시(codexMetaRow 대응).
    @ViewBuilder
    private func opencodeGoMetaRow(_ status: OpenCodeGoLimitStatus) -> some View {
        if status.isRateLimited || store.opencodeGoLimitsStale {
            HStack(spacing: 8) {
                if status.isRateLimited {
                    Text(l.limitReached)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                if store.opencodeGoLimitsStale {
                    staleBadge(updatedAt: store.opencodeGoLimitsUpdatedAt)
                }
            }
        }
    }

    @ViewBuilder
    private var antigravityLimitsContent: some View {
        if store.antigravityLimitsAuthExpired {
            antigravityAuthExpiredNotice
        } else if !store.disableKeychainAccess && (store.antigravityLimits == nil || store.antigravityLimitsStale) {
            antigravityRefreshRow
        }
        // 갱신 버튼이 여기 있는데 사유는 설정 화면에만 있으면, 누른 사람은 "아무 일도 안 일어났다"고 본다.
        if let refreshError = store.antigravityLimitRefreshError {
            Text(refreshError)
                .font(.caption2).foregroundStyle(.orange).lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        if let status = store.antigravityLimits, status.hasVisibleLimit {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(status.groups.enumerated()), id: \.offset) { _, group in
                    VStack(alignment: .leading, spacing: 4) {
                        let groupTitle = group.displayName.localizedCaseInsensitiveContains("gemini")
                            ? l.antigravityGeminiGroup
                            : (group.displayName.localizedCaseInsensitiveContains("claude") ? l.antigravityThirdPartyGroup : group.displayName)
                        Text(groupTitle)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        ForEach(group.buckets, id: \.bucketId) { bucket in
                            antigravityBucketRow(bucket)
                        }
                    }
                }
            }
            .opacity(store.antigravityLimitsAuthExpired ? 0.5 : 1)
        }
    }

    @ViewBuilder
    private func antigravityBucketRow(_ bucket: AntigravityQuotaBucket) -> some View {
        let name = l.antigravityWindow(window: bucket.window, bucketId: bucket.bucketId)
        let utilization = bucket.usedPercent
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(name)
                    .font(.callout)
                Spacer()
                Text(limitPercentText(utilization))
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(limitColor(utilization))
                if let reset = bucket.resetDate {
                    Text("· \(reset, style: .relative)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            ProgressView(value: min(utilization, 100), total: 100)
                .tint(limitColor(utilization))
                .controlSize(.small)
        }
    }

    @ViewBuilder
    private var antigravityRefreshRow: some View {
        HStack(spacing: 6) {
            if store.antigravityLimits == nil {
                Text(l.limitsTapToLoad)
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                (Text(l.staleLimits) + Text(" · ") + Text(store.antigravityLimitsUpdatedAt ?? Date(), style: .relative))
                    .font(.caption).foregroundStyle(.orange)
            }
            Spacer()
            Button {
                Task { await store.refreshAntigravityLimitsFromKeychain() }
            } label: {
                if store.isRefreshingAntigravityLimits {
                    ProgressView().controlSize(.small)
                } else {
                    Text(l.refresh)
                }
            }
            .controlSize(.small)
            .disabled(store.isRefreshingAntigravityLimits)
        }
    }

    @ViewBuilder
    private var antigravityAuthExpiredNotice: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(l.antigravityAuthExpiredTitle)
                    .font(.caption).fontWeight(.medium)
            }
            Text(l.antigravityAuthExpiredHint)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Button(l.retry) {
                Task { await store.refreshAntigravityLimitsFromKeychain() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.mini)
            .padding(.top, 2)
        }
        .padding(8)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }


    /// 한도 % 표시 문자열 — remaining 모드면 남은 %에 자기설명 접미사("남음/left/残り").
    /// 게이지 채움·경고색은 사용률 원값 기준 유지 — 숫자 텍스트만 모드를 따른다.
    // MARK: 한도 이력 — 로컬 시계열 (서버는 현재 스냅샷만 준다)

    /// 완료된 한도 창들의 최고 사용률 이력. 한도 endpoint 는 "지금 몇 %"만 알려주고 창이 리셋되면
    /// 그 값은 어디에도 안 남으므로(LimitHistoryStore 참고), 이 섹션이 보여주는 건 전적으로
    /// 앱이 폴링하며 직접 쌓은 기록이다 — 설치 이전 구간은 존재하지 않는다.
    @ViewBuilder
    private var limitHistorySection: some View {
        let summaries = LimitHistoryStore.ClaudeWindow.displayed.map { window in
            (window: window,
             summary: store.limitHistory.summary(
                providerID: "claude_code", window: window,
                threshold: store.warnThreshold, limit: Self.historyWindowCount))
        }
        VStack(alignment: .leading, spacing: 8) {
            Text(l.limitHistory)
                .font(.caption)
                .foregroundStyle(.secondary)
            if summaries.allSatisfy(\.summary.isEmpty) {
                Text(l.limitHistoryCollecting)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(summaries, id: \.window) { entry in
                    if !entry.summary.isEmpty {
                        historyRow(name: historyWindowName(entry.window), summary: entry.summary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 팝오버 폭(332pt)에 막대가 뭉개지지 않고 들어가는 개수. 5시간 창 기준 약 3일치다.
    private static let historyWindowCount = 14

    private func historyWindowName(_ window: String) -> String {
        window == LimitHistoryStore.ClaudeWindow.sevenDay ? l.weekly : l.fiveHourSession
    }

    @ViewBuilder
    private func historyRow(name: String, summary: LimitHistoryStore.Summary) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(name)
                    .font(.callout)
                Text("· \(l.limitHistoryRecent(summary.windows.count))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                Text(l.limitHistoryPeak(TokenFormatter.percent(summary.peak)))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(limitColor(summary.peak))
                Text("· \(l.limitHistoryMedian(TokenFormatter.percent(summary.median)))")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
            historyBars(summary.windows)
            // 이력 화면의 결론 한 줄 — 사용자가 "요금제가 맞나"를 판단하는 지점.
            // 임계값은 사용자가 이미 고른 경고선(warnThreshold)을 그대로 재사용한다.
            Text(l.limitHistoryAtOrAbove(
                count: summary.atOrAbove, total: summary.windows.count,
                threshold: TokenFormatter.percent(store.warnThreshold)))
                .font(.caption2)
                .foregroundStyle(.secondary)
            if summary.hasTruncated {
                Text(l.limitHistoryPartial)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    /// 창별 최고 사용률 막대. 오래된 것이 왼쪽(시간순) — 배열이 이미 오래된 순이라 그대로 그린다.
    /// 관측이 잘린 창은 흐리게: 그 막대의 높이는 실제 최고치가 아니라 하한이다.
    private func historyBars(_ windows: [LimitHistoryStore.Window]) -> some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(windows.enumerated()), id: \.offset) { _, window in
                let fraction = min(max(window.peak, 0), 100) / 100
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    RoundedRectangle(cornerRadius: 1.5)
                        // 0% 창도 자리를 차지해야 "그 창이 있었다"가 보인다 — 최소 높이 2pt.
                        .frame(height: max(2, Self.historyBarHeight * fraction))
                        .foregroundStyle(limitColor(window.peak))
                        .opacity(window.truncated ? 0.35 : 1)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: Self.historyBarHeight)
    }

    private static let historyBarHeight: CGFloat = 26

    private func limitPercentText(_ utilization: Double) -> String {
        let text = TokenFormatter.percent(store.limitDisplayPercent(utilization))
        return store.limitDisplayMode == .remaining ? l.percentRemaining(text) : text
    }

    @ViewBuilder
    private func limitRow(name: String, window: LimitWindow?) -> some View {
        if let window, let utilization = window.utilization {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(name)
                        .font(.callout)
                    Spacer()
                    Text(limitPercentText(utilization))
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundStyle(limitColor(utilization))
                    if let reset = window.resetDate {
                        Text("· \(reset, style: .relative)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                ProgressView(value: min(utilization, 100), total: 100)
                    .tint(limitColor(utilization))
                    .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private func codexMetaRow(_ status: CodexRateLimitStatus) -> some View {
        // plan 은 계정 속성 — bucket 필터와 무관하게 top-level 에서 읽는다 (로그와 동일 소스)
        let planType = status.rateLimits.planType ?? status.visibleSnapshots.first?.planType
        let reached = status.visibleSnapshots.contains { $0.rateLimitReachedType != nil }
        if planType != nil || reached || store.codexLimitsStale {
            HStack(spacing: 8) {
                if let plan = planType {
                    Text(l.plan(plan))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                if reached {
                    Text(l.limitReached)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                // 갱신 실패가 15분+ 이어지면 이전 스냅샷임을 노출 (codex TUI stale 임계와 동일)
                if store.codexLimitsStale {
                    staleBadge(updatedAt: store.codexLimitsUpdatedAt)
                }
            }
        }
    }

    /// Claude 세션 만료(401) 안내 — 자동 폴링은 만료 토큰을 스스로 못 고치므로,
    /// "왜 어제 값에 멈췄는지 + 원탭 재시도 + Claude Code 실행 시 자동 갱신" 을 눈에 띄게 노출.
    @ViewBuilder
    /// 세션 키 만료 — OAuth 안내와 달리 재시도가 의미 없다(죽은 쿠키는 재조회로 안 살아난다).
    /// 그래서 버튼이 Keychain 을 읽지 않고, 키를 다시 넣을 수 있는 화면으로 보낸다.
    private var sessionKeyExpiredNotice: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "key.slash.fill")
                    .foregroundStyle(.orange)
                Text(l.sessionKeyExpiredTitle)
                    .font(.caption).fontWeight(.semibold)
                Spacer()
                Button(l.settings) { nav.openSessionKeySettings() }
                    .controlSize(.small)
            }
            Text(l.sessionKeyExpiredNoticeHint)
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    private var claudeAuthExpiredNotice: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(l.claudeAuthExpiredTitle)
                    .font(.caption).fontWeight(.semibold)
                Spacer()
                Button {
                    Task { await store.refreshLimitTokenFromKeychain() }
                } label: {
                    if store.isRefreshingLimitToken {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(l.retry)
                    }
                }
                .controlSize(.small)
                .disabled(store.isRefreshingLimitToken)
            }
            Text(l.claudeAuthExpiredHint)
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(8)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    /// Claude 공식 한도 — 최초 로드/만료(stale) 시 사용자가 원탭으로 Keychain 을 읽어 갱신.
    /// 자동 폴링이 Keychain 을 안 읽는 대신 여기서 명시적 사용자 동작으로만 재취득한다.
    @ViewBuilder
    private var claudeLimitsRefreshRow: some View {
        HStack(spacing: 6) {
            if store.limits == nil {
                Text(l.limitsTapToLoad)
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                (Text(l.staleLimits) + Text(" · ") + Text(store.limitsUpdatedAt ?? Date(), style: .relative))
                    .font(.caption).foregroundStyle(.orange)
            }
            Spacer()
            Button {
                Task { await store.refreshLimitTokenFromKeychain() }
            } label: {
                if store.isRefreshingLimitToken {
                    ProgressView().controlSize(.small)
                } else {
                    Text(l.refresh)
                }
            }
            .controlSize(.small)
            .disabled(store.isRefreshingLimitToken)
        }
    }

    /// 한도 스냅샷 갱신 지연 배지 — Claude/Codex 공용 (마지막 성공 시각 상대 표시).
    @ViewBuilder
    private func staleBadge(updatedAt: Date?) -> some View {
        if let updatedAt {
            (Text(l.staleLimits) + Text(" · ") + Text(updatedAt, style: .relative))
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private func codexLimitRow(name: String, window: CodexRateLimitWindow?) -> some View {
        if let window {
            let utilization = Double(window.usedPercent)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(name)
                        .font(.callout)
                    Spacer()
                    Text(limitPercentText(utilization))
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundStyle(limitColor(utilization))
                    if let reset = window.resetDate {
                        Text("· \(reset, style: .relative)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                ProgressView(value: min(utilization, 100), total: 100)
                    .tint(limitColor(utilization))
                    .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private func codexSpendLimitRow(_ limit: CodexSpendControlLimit?) -> some View {
        if let limit {
            let utilization = Double(limit.usedPercent)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(l.personalSpendLimit)
                        .font(.callout)
                    Spacer()
                    Text("\(limit.used) / \(limit.limit)")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Text(limitPercentText(utilization))
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundStyle(limitColor(utilization))
                    Text("· \(limit.resetDate, style: .relative)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                ProgressView(value: min(utilization, 100), total: 100)
                    .tint(limitColor(utilization))
                    .controlSize(.small)
            }
        }
    }

    /// 한도 소진 예측 — 현재 burn rate 로 5h 한도 100% 도달 시각 외삽
    @ViewBuilder
    private var forecastRow: some View {
        if let forecast = store.fiveHourForecast {
            HStack(spacing: 4) {
                Image(systemName: forecast.beforeReset
                    ? "exclamationmark.triangle.fill" : "checkmark.circle")
                    .font(.caption2)
                Text(forecast.beforeReset
                    ? l.forecastReach(Self.timeFormatter.string(from: forecast.depletionDate))
                    : l.forecastNoReach)
                    .font(.caption)
            }
            .foregroundStyle(forecast.beforeReset ? AnyShapeStyle(.orange) : AnyShapeStyle(.tertiary))
            .padding(.leading, 2)
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private func limitColor(_ utilization: Double) -> Color {
        if utilization >= store.critThreshold { return .red }
        if utilization >= store.warnThreshold { return .orange }
        return .green
    }

    // MARK: 푸터

    private var footer: some View {
        HStack(spacing: 10) {
            // 갱신·"Updated" 시각·에러 삼각형은 사용량 신선도 UI — 사용량을 표시하지 않는 탭(도감/가방/상점)에선
            // "뭘 갱신하라는 건지" 혼란만 줘서 홈 탭에서만 노출한다. 설정/종료는 전역이라 아래에 그대로 둔다.
            if nav.tab == .home {
                // 스피너 스왑을 두지 않는다 — 로컬 파싱이 보이는 오늘 숫자를 즉시 갱신하는데
                // enrichment/한도(네트워크)까지 기다리는 스피너가 데이터보다 오래 돌아 불필요해 보였다.
                // 중복 클릭은 refresh() 의 재진입 guard 가 무시하고, 피드백은 아래 "Updated" 시각이 준다.
                Button {
                    Task { await store.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help(l.refreshNow)
                if let updated = store.lastUpdated {
                    (Text("\(l.updated) ") + Text(updated, style: .relative))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                if store.lastErrorDescription != nil {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .help(store.lastErrorDescription ?? "")
                }
            }
            Spacer()
            Button {
                nav.showSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help(l.settings)
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
            .help(l.quit)
        }
    }
}

/// 서비스 전환 탭. 프로바이더가 늘면 캡슐 합계 폭이 `PopoverMetrics.contentWidth` 를 넘는다
/// (6개 기준 439pt vs 332pt). 폭 제한만 있고 줄바꿈을 막지 않으면 SwiftUI 가 캡슐 텍스트를 눌러
/// "Curso/r"·"Code/x" 처럼 **단어 중간에서** 접고 탭 바가 2~3줄이 된다.
/// 가로 스크롤 + `lineLimit(1)`/`fixedSize` 로 각 탭이 항상 자연 폭 한 줄을 유지한다.
/// (`Spacer()` 는 가로 ScrollView 안에서 무한 확장하므로 쓰지 않는다.)
@MainActor
struct ProviderTabBar: View {
    let snapshots: [ProviderSnapshot]
    let selectedID: String?
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(snapshots) { snap in
                    let isSelected = snap.providerID == selectedID
                    Button { onSelect(snap.providerID) } label: {
                        Text(snap.displayName)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .font(.caption.weight(isSelected ? .semibold : .regular))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(isSelected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08))
                            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        // 탭이 적으면(대부분의 사용자) 스크롤·바운스가 생기지 않아 기존과 동일하게 보인다.
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }
}
