import AppKit
import QuartzCore
import SwiftUI
import PokeTokenBarShared

@main
@MainActor
struct PokeTokenBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // 메뉴바는 AppDelegate 의 NSStatusItem 이 담당.
        // MenuBarExtra 라벨은 고빈도 갱신 시 재렌더링 폭주로 CPU/메모리 문제가 있어 사용하지 않는다.
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var outsideClickMonitor = OutsideClickMonitor()
    private var store: UsageStore!
    private var companion: CompanionStore!
    private var updater: UpdateChecker!
    private var floatingPet: FloatingPetController!
    private var phoneServer: PhonePayloadServer!
    private let navigation = PopoverNavigation()

    // 메뉴바 캐릭터 애니메이션 — 단일 타이머로 프레임 순환.
    // 프레임 = 이미 22px 로 합성된 이미지 + delay. egg/static 은 2프레임 bob, animated 는 GIF 실제 프레임.
    private var menuSpriteKey: String?   // "id-shiny" — 같은 종이라도 shiny 여부가 바뀌면 재로딩
    private var menuFrames: [(image: NSImage, delay: TimeInterval)] = []
    private var menuIndex = 0
    private var menuTimer: Timer?
    private var menuLoadGen = 0     // async 로드 경합 방지
    private var displayAwake = true     // 디스플레이 켜짐 여부 (꺼지면 메뉴 애니메이션 정지 — 배터리)

    /// Persist the tail of the limit-history series. `LimitHistoryStore` throttles its writes to
    /// once a minute, so without this every quit drops up to a minute of samples — and a launch/quit
    /// cycle shorter than the throttle would record nothing at all.
    func applicationWillTerminate(_ notification: Notification) {
        store?.limitHistory.flush()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 로그인 에이전트 등록(plist 의 RunAtLoad)이 이미 떠 있는 앱을 한 번 더 실행한다 — 나중에 뜬
        // 쪽이 물러난다. 메뉴바 항목을 만들기 전에 판정해 아이콘이 떴다 사라지는 깜빡임을 없애고,
        // **`CrashReporter.install` 보다도 앞**에 둔다: 뒤면 물러나는 인스턴스가 running 마커를 덮어쓰고
        // 종료 시 `markClean()` 이 발화해, 살아남은 쪽이 나중에 크래시해도 다음 실행이 정상 종료로 읽는다.
        if SingleInstance.shouldYieldToRunningInstance() {
            // writeAndFlush: write is async and terminate reaches exit(0) in
            // the same turn. Without the drain this line is lost (42 of 100
            // in the #163 review) and a false positive looks like a crash.
            AppLog.writeAndFlush("duplicate instance: yielding to the instance already running")
            NSApp.terminate(nil)
            return
        }
        // 서브프로세스(codex app-server 등) 파이프가 조기 종료로 끊겨도 SIGPIPE 로 앱이 죽지 않게
        // 무시한다. ProcessRunner 의 throwing write 와 함께 broken-pipe 크래시를 막는 이중 방어.
        signal(SIGPIPE, SIG_IGN)
        // 크래시·OOM·강제종료·런치실패를 로그에 남기는 전역 처리. 가능한 이르게(초기 크래시도 잡히게).
        CrashReporter.install(
            version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")
        NSApp.setActivationPolicy(.accessory)
        Self.migrateLegacyStorageIfNeeded()   // TokenMac → PokeTokenBar 리네임: 기존 companion/캐시 보존
        LoginItem.migrateFromLegacyLoginItemIfNeeded()   // 로그인아이템 → KeepAlive 에이전트(크래시 자동 재실행)
        store = UsageStore()
        companion = CompanionStore()
        updater = UpdateChecker()
        store.localizationLanguage = companion.language   // 알림 현지화용 미러 시드
        store.onRefresh = { [weak self] in self?.onStoreRefreshed() }   // 한도 로드 후 companion·사탕 지급
        floatingPet = FloatingPetController(
            store: store, companion: companion,
            onOpenPopover: { [weak self] in self?.openPopover() },
            onHide: { [weak self] in self?.store.floatingPetEnabled = false }
        )   // 데스크톱 플로팅 펫(옵트인)
        phoneServer = PhonePayloadServer()
        if store.phoneServerEnabled {
            phoneServer.start()
        }
        Task { await buildAndPublishPayload() }
        Task { await updater.check() }                    // 기동 시 1회 업데이트 확인

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            setStatusImage(Self.eggImage(up: false))   // 초기 알도 전환 억제 경로로 통일(불변식)
            button.imagePosition = .imageLeading
            button.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
            button.cell?.usesSingleLineMode = false   // 사용량/한도를 2줄로 세로 스택 가능하게
            button.action = #selector(togglePopover)
            button.target = self
        }

        popover.behavior = .transient
        popover.delegate = self   // didShow: outside-click monitor; didClose: 호스팅 해제 + 모니터 제거

        observeStore()
        observeCompanionSprite()
        observeDisplaySleep()
        applyState()
        updateAppIcon()
    }

    /// Observation 기반 상태 반영 — store 의 menuTitle(=menuLines) 변경 시 재호출.
    /// (isStale 은 더 이상 추적 안 함 — 메뉴바 dim 제거로 시각 출력에 관여하지 않음.)
    private func observeStore() {
        withObservationTracking {
            _ = store.menuTitle
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.applyState()
                self.observeStore()
            }
        }
    }

    /// 대표 스프라이트 정체성(종/shiny) 관찰 — 대표 선택·해제뿐 아니라 사탕 진화·졸업(BagView),
    /// 세이브 가져오기, 부화·메타몽 리빌 async 완료처럼 store 갱신 틱 없이 companion 만 바뀌는
    /// 경로에서도 메뉴바를 즉시 갱신한다. observeStore(menuTitle)만으론 다음 사용량 폴링(기본 120s)까지
    /// 이전 포켓몬이 남는다(사탕 졸업 후 메뉴바 잔상 리포트 — UsageStore.onRefresh 주석과 같은 부류).
    private func observeCompanionSprite() {
        withObservationTracking {
            _ = companion.representativeSubject
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.ensureMenuAnimation()
                self.syncMenuAnimation()
                self.updateAppIcon()
                self.observeCompanionSprite()
            }
        }
    }

    private func applyState() {
        guard let button = statusItem.button else { return }
        Self.applyMenuText(store.menuLines, to: button)
        // stale 시각 dim 제거 — 슬립/런치 직후 refresh 완료 전 몇 초간 회색으로 보여 '고장/비활성'
        // 으로 오인되던 것 방지(사용자 반복 지적). 데이터가 오래됐다는 신호가 필요하면 팝오버
        // (limitsUpdatedAt 등)에서 제공하고, 메뉴바 아이콘·숫자는 흐리게 하지 않는다.
        button.appearsDisabled = false

        updateCompanion()
        ensureMenuAnimation()
        syncMenuAnimation()   // 가시성 상태 주기적 재평가(occlusion 이 잘못 멈춰도 자가 복구)
    }

    /// 메뉴바 버튼 텍스트 반영 — 1줄이면 기본 title(13pt), 2줄 이상이면 세로 스택.
    /// 줄 수에 맞춰 폰트를 자동 축소해 N줄이 메뉴바 높이에 클리핑 없이 들어오게 한다. 색을 지정하지
    /// 않아 메뉴바 명암(라이트/다크)·비활성(appearsDisabled) 상태에 자동 적응한다.
    private static func applyMenuText(_ lines: [String], to button: NSStatusBarButton) {
        if lines.count >= 2 {
            // NSStatusBarButton 은 멀티라인 title 을 세로 중앙에 두지 않고 위로 치우쳐 그린다(측정:
            // titleRect.y 가 음수 → 상단 클리핑 + 하단 여백, 사용자 지적). 그래서 baselineOffset 을
            // '런타임 측정'으로 보정한다: offset 0 으로 한번 세팅해 셀이 계산한 title 상자(titleRect)를
            // 재고, 그 상자 중앙을 버튼 중앙에 맞추는 offset 을 역산해 재적용. 매직넘버 없이 두께·폰트·
            // 아이콘에 자동 적응. 줄높이는 폰트 자연 줄높이(×1.16)보다 크게 둬 어센더 클리핑을 막는다.
            let thickness = NSStatusBar.system.thickness
            let share = thickness / CGFloat(lines.count)                 // 줄당 몫
            let fontSize = min(11, max(8, (share * 0.85).rounded(.down)))
            let effLH = min(share, (fontSize * 1.28).rounded())          // 자연 줄높이보다 크게(어센더 클리핑 방지)
            let font = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .regular)
            func titled(_ offset: CGFloat) -> NSAttributedString {
                let para = NSMutableParagraphStyle()
                para.alignment = .center
                para.minimumLineHeight = effLH
                para.maximumLineHeight = effLH
                return NSAttributedString(
                    string: lines.joined(separator: "\n"),
                    attributes: [.font: font, .paragraphStyle: para, .baselineOffset: offset])
            }
            let bounds = button.bounds
            if bounds.height > 1 {
                // 1) offset 0 으로 측정 → 2) 상자 중앙을 버튼 중앙에 맞추는 보정량 역산 → 3) 재적용.
                // (측정용 title 은 표시 전 즉시 교체되므로 깜빡임 없음.)
                button.attributedTitle = titled(0)
                let r0 = (button.cell as? NSButtonCell)?.titleRect(forBounds: bounds) ?? bounds
                button.attributedTitle = titled(r0.midY - bounds.midY)
            } else {
                button.attributedTitle = titled(0)   // 레이아웃 전(폭 0) — 보정 없이, 다음 갱신에 재보정
            }
        } else {
            // 1줄로 되돌릴 때 이전 attributedTitle 이 남지 않게 먼저 비운다.
            button.attributedTitle = NSAttributedString(string: "")
            let title = lines.first ?? ""
            button.title = title.isEmpty ? "" : " " + title
        }
    }

    /// UsageStore 값 → CompanionStore (사용량 적립 + 표시 상태). 매 관찰 변경 시 호출.
    private func updateCompanion() {
        companion.update(
            todayTokensByProvider: store.todayTokensByProvider,
            todayDate: LocalUsageReader.todayKey(),
            monthTotal: store.monthTotalTokens,
            burnTier: store.burnTier,
            limitWarning: store.isLimitWarning,
            hasUsageData: store.hasUsageData)
    }

    /// 매 refresh 완료 훅 — companion 갱신 + 사탕 지급(한도가 신선한 시점). 지급을 여기 묶는 이유는
    /// UsageStore.onRefresh 주석 참조(observeStore 만으론 한도 변경이 companion 에 안 전달되는 케이스).
    private func onStoreRefreshed() {
        updateCompanion()
        companion.grantCandies(from: store.candyEligibleWindows, limitsReady: store.limitsReady)
        Task { await buildAndPublishPayload() }
    }

    // MARK: - Phone Payload Server

    private func buildAndPublishPayload() async {
        let limits = Self.phoneLimitStatus(
            limits: store.limits, codex: store.codexLimits,
            opencodeGo: store.opencodeGoLimits, antigravity: store.antigravityLimits,
            warnThreshold: store.warnThreshold, critThreshold: store.critThreshold,
            history: Self.phoneLimitHistory(store.limitHistory,
                                            warnThreshold: store.warnThreshold, l: companion.l),
            l: companion.l)
        let companionState = PhoneCompanionState(
            name: companion.displayName,
            speciesID: companion.currentSpeciesID,
            isShiny: companion.currentIsShiny,
            isEgg: companion.isEgg,
            progress: companion.progress,
            stageText: companion.stageText,
            rarity: companion.rarity?.rawValue,
            dexCount: companion.dexEntries.count,
            eggProgress: companion.eggProgress,
            displayState: companion.displayState.rawValue,
            // Final stage → graduation counter only; otherwise evolution only. Sending both (as older
            // Macs did) leaves the phone unable to tell which wording applies.
            evolutionTokens: companion.isFinalStage ? nil : companion.tokensToNextEvolution,
            graduationTokens: companion.isFinalStage ? companion.tokensToGraduation : nil,
            representativeSpeciesID: companion.representativeSubject.speciesID,
            representativeIsShiny: companion.representativeSubject.isShiny,
            statusText: companion.statusText,
            natureText: companion.currentNature?.name(companion.language),
            lineNodes: companion.phoneLineNodes)
        let providers = store.snapshots.map { snapshot -> PhoneProviderSnapshot in
            PhoneProviderSnapshot(id: snapshot.providerID, displayName: snapshot.displayName,
                                   todayTokens: snapshot.todayTotalTokens,
                                   todayCost: snapshot.today?.totalCost ?? 0,
                                   inputTokens: snapshot.today?.inputTokens ?? 0,
                                   outputTokens: snapshot.today?.outputTokens ?? 0,
                                   cacheWriteTokens: snapshot.today?.cacheCreationTokens ?? 0,
                                   cacheReadTokens: snapshot.today?.cacheReadTokens ?? 0,
                                   reportsCost: snapshot.reportsCost)
        }
        // 가방·도감(폰 읽기 전용) — 표시 문자열은 폰에 현지화 인프라가 없어 여기서 미리 만든다
        // (companion.stageText 를 폰에 그대로 보내는 것과 같은 규약).
        let l = companion.l
        let bag = companion.ownedItems.map { item in
            PhoneBagItem(
                id: item.kind.rawValue,
                name: l.itemName(item.kind),
                itemDescription: l.itemDescription(item.kind),
                count: item.count,
                isPassive: item.kind.isPassive,
                effectHint: item.kind.isPassive ? l.shinyCharmEffectHint : "",
                iconName: item.kind.spriteName,
                fallbackEmoji: item.kind.fallbackEmoji)
        }
        let dex = companion.dexSpecies.map { sp in
            PhoneDexSpecies(id: sp.id, name: sp.name, rarity: sp.rarity.rawValue,
                            isShiny: sp.isShiny, isRaising: sp.isRaising)
        }
        let payload = PhonePayload(
            todayTokens: store.todayTotalTokens,
            todayCost: store.todayCostTotal,
            weekTokens: store.weekTotalTokens,
            monthTokens: store.monthTotalTokens,
            lastUpdated: store.lastUpdated ?? Date(),
            serverVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0",
            limits: limits,
            companion: companionState,
            providers: providers,
            bag: bag,
            dex: dex,
            spendableTokens: companion.availableTokens,
            shop: Self.phoneShopEntries(companion),
            weekCost: store.weekCostTotal,
            monthCost: store.monthCostTotal,
            burn: Self.phoneBurnForecast(forecast: store.fiveHourForecast,
                                         tokensPerMinute: store.combinedBurnPerMinuteForPhone))
        if phoneServer.isRunning, let data = try? JSONEncoder().encode(payload) {
            phoneServer.updatePayload(data)
        }
        Task { @MainActor in
            do { try await CloudKitSync.save(payload) }
            catch { AppLog.write("CloudKit sync failed: \(error)") }
        }
    }

    /// 폰·위젯이 그대로 표시할 한도 페이로드. 라벨은 여기서 프로바이더 접두어를 붙여 현지화한다
    /// (bag/dex 와 같은 규약 — 폰엔 현지화 인프라가 없다). 순수 함수라 라벨/매핑을 단위 테스트한다.
    /// Opus/Sonnet 레거시 필드 밖의 모델별 주간(예: Fable)은 scopedLimitEntries → claudeScoped 로 싣는다.
    static func phoneLimitStatus(
        limits: LimitStatus?,
        codex: CodexRateLimitStatus?,
        opencodeGo: OpenCodeGoLimitStatus?,
        antigravity: AntigravityRateLimitStatus? = nil,
        warnThreshold: Double? = nil,
        critThreshold: Double? = nil,
        history: [PhoneLimitHistorySeries]? = nil,
        l: L
    ) -> PhoneLimitStatus {
        // Codex 리셋 시각: 최대 사용률을 가진 창(메뉴바/폰이 표시하는 값)의 resetDate 를 짝지어 보낸다.
        let codexPrimaryWindow = codex?.visibleSnapshots.compactMap(\.primary).max { $0.usedPercent < $1.usedPercent }
        let codexSecondaryWindow = codex?.visibleSnapshots.compactMap(\.secondary).max { $0.usedPercent < $1.usedPercent }
        // Antigravity: 팝오버와 같은 그룹 순서·버킷 순서로 평탄화. 그룹명은 Gemini / Claude & GPT 로 정규화.
        let agy: [PhoneLimitWindow] = (antigravity?.groups ?? []).flatMap { group -> [PhoneLimitWindow] in
            let title = group.displayName.localizedCaseInsensitiveContains("gemini")
                ? l.phoneAntigravityGeminiGroup
                : (group.displayName.localizedCaseInsensitiveContains("claude") ? l.phoneAntigravityThirdPartyGroup : group.displayName)
            return group.buckets.map { bucket in
                PhoneLimitWindow(label: l.phoneAntigravity(group: title, window: bucket.window, bucketId: bucket.bucketId),
                                 utilization: bucket.usedPercent, resetsAt: bucket.resetDate)
            }
        }
        let scoped: [PhoneLimitWindow] = (limits?.scopedLimitEntries ?? []).compactMap { entry in
            guard let percent = entry.percent else { return nil }
            return PhoneLimitWindow(
                label: l.phoneClaudeScoped(model: entry.scope?.model?.displayName),
                utilization: percent,
                resetsAt: entry.resetsAt.flatMap { ISO8601Parser.date(from: $0) })
        }
        return PhoneLimitStatus(
            claude5h: limits?.fiveHour?.utilization.map {
                PhoneLimitWindow(label: l.phoneClaude5h, utilization: $0, resetsAt: limits?.fiveHour?.resetDate)
            },
            claudeWeekly: limits?.sevenDay?.utilization.map {
                PhoneLimitWindow(label: l.phoneClaudeWeekly, utilization: $0, resetsAt: limits?.sevenDay?.resetDate)
            },
            claudeOpusWeekly: limits?.sevenDayOpus?.utilization.map {
                PhoneLimitWindow(label: l.phoneClaudeOpusWeekly, utilization: $0, resetsAt: limits?.sevenDayOpus?.resetDate)
            },
            claudeSonnetWeekly: limits?.sevenDaySonnet?.utilization.map {
                PhoneLimitWindow(label: l.phoneClaudeSonnetWeekly, utilization: $0, resetsAt: limits?.sevenDaySonnet?.resetDate)
            },
            claudeScoped: scoped.isEmpty ? nil : scoped,
            codexPrimary: codex?.maxPrimaryUsedPercent.map {
                PhoneLimitWindow(label: l.phoneCodex, utilization: Double($0), resetsAt: codexPrimaryWindow?.resetDate)
            },
            codexSecondary: codex?.maxSecondaryUsedPercent.map {
                PhoneLimitWindow(label: l.phoneCodexSecondary, utilization: Double($0), resetsAt: codexSecondaryWindow?.resetDate)
            },
            opencodeGo5h: opencodeGo?.rolling.flatMap { window in
                window.utilization.map {
                    PhoneLimitWindow(label: l.phoneGo5h, utilization: $0, resetsAt: window.resetDate)
                }
            },
            opencodeGoWeekly: opencodeGo?.weekly.flatMap { window in
                window.utilization.map {
                    PhoneLimitWindow(label: l.phoneGoWeekly, utilization: $0, resetsAt: window.resetDate)
                }
            },
            opencodeGoMonthly: opencodeGo?.monthly.flatMap { window in
                window.utilization.map {
                    PhoneLimitWindow(label: l.phoneGoMonthly, utilization: $0, resetsAt: window.resetDate)
                }
            },
            antigravity: agy.isEmpty ? nil : agy,
            planDisplay: limits?.planDisplay,
            warnThreshold: warnThreshold,
            critThreshold: critThreshold,
            history: (history?.isEmpty ?? true) ? nil : history)
    }

    /// 로컬에 기록한 한도 이력 → 폰. 한도 endpoint 는 현재 스냅샷만 주므로 이력은 Mac 이
    /// 폴링하며 쌓은 것이 유일한 출처다(`LimitHistoryStore`). 폰은 기록 주체가 아니라 표시만 한다.
    ///
    /// 원시 샘플 로그가 아니라 **파생된 창**을 보낸다 — 로그는 90일 보관 기준 수천 행이고
    /// 폰이 그리는 건 창별 최고치뿐이라, 원시를 보내면 페이로드만 키우고 폰이 Mac 의 창 분할
    /// 규칙(rolling 감소 vs 리셋)을 재구현하게 된다. 규칙은 Mac 한 곳에만 있어야 한다.
    ///
    /// `atOrAbove` 는 페이로드에 함께 실리는 warnThreshold 로 여기서 센다 — 폰이 다시 세면
    /// 두 값이 어긋날 여지가 생긴다.
    static func phoneLimitHistory(
        _ history: LimitHistoryStore, warnThreshold: Double, limit: Int = 14, l: L
    ) -> [PhoneLimitHistorySeries] {
        let labels = [
            LimitHistoryStore.ClaudeWindow.fiveHour: l.phoneClaude5h,
            LimitHistoryStore.ClaudeWindow.sevenDay: l.phoneClaudeWeekly,
        ]
        return LimitHistoryStore.ClaudeWindow.displayed.compactMap { window in
            let summary = history.summary(providerID: "claude_code", window: window,
                                          threshold: warnThreshold, limit: limit)
            // 완료된 창이 없으면 시리즈 자체를 만들지 않는다 — 빈 시리즈를 보내면 폰이 "이력 있음"
            // 카드를 띄우고 빈 차트를 그린다.
            guard !summary.isEmpty else { return nil }
            return PhoneLimitHistorySeries(
                label: labels[window] ?? window,
                windows: summary.windows.map {
                    PhoneLimitHistoryWindow(peak: $0.peak, end: $0.end, truncated: $0.truncated)
                },
                peak: summary.peak, median: summary.median, atOrAbove: summary.atOrAbove)
        }
    }

    /// Claude 5h 소진 예측 → 폰. 예측이 없어도 burn 이 있으면 tokens/min 만 보낸다.
    static func phoneBurnForecast(forecast: UsageStore.FiveHourForecast?, tokensPerMinute: Double) -> PhoneBurnForecast? {
        guard forecast != nil || tokensPerMinute > 0 else { return nil }
        return PhoneBurnForecast(depletionDate: forecast?.depletionDate,
                                 beforeReset: forecast?.beforeReset ?? false,
                                 tokensPerMinute: tokensPerMinute > 0 ? tokensPerMinute : nil)
    }

    /// 상점 목록(판매 아이템 + 알 3종) → 폰 읽기 전용 엔트리 매핑. 순서·가격·구매가능 판정은
    /// CompanionStore.shopEntries/canBuy 를 그대로 따른다(폰은 재현하지 않고 표시만).
    /// 표시 문자열은 bag/dex 와 같은 규약으로 여기서 미리 현지화해 보낸다.
    static func phoneShopEntries(_ companion: CompanionStore) -> [PhoneShopEntry] {
        let l = companion.l
        return companion.shopEntries.map { entry in
            switch entry {
            case .item(let kind):
                let owned = companion.itemCount(kind)
                return PhoneShopEntry(
                    id: "item:\(kind.rawValue)",
                    isEgg: false,
                    name: l.itemName(kind),
                    itemDescription: l.itemDescription(kind),
                    price: entry.price,
                    rarity: nil,
                    ownedCount: owned,
                    isPassive: kind.isPassive,
                    isOwned: kind.isPassive && owned > 0,
                    canAfford: companion.canBuy(kind),
                    iconName: kind.spriteName,
                    fallbackEmoji: kind.fallbackEmoji)
            case .egg(let tier):
                return PhoneShopEntry(
                    id: "egg:\(tier?.rawValue ?? "plain")",
                    isEgg: true,
                    name: l.eggName(tier),
                    itemDescription: l.eggDescription(tier),
                    price: entry.price,
                    rarity: tier?.rawValue,
                    ownedCount: 0,
                    isPassive: false,
                    isOwned: false,
                    canAfford: companion.canBuyEgg(tier),
                    iconName: nil,
                    fallbackEmoji: "🥚")
            }
        }
    }

    // MARK: 메뉴바 애니메이션

    /// 대표 포켓몬에 맞춰 메뉴바 프레임을 준비. 종이 바뀐 경우에만 재로딩.
    /// 정적 스프라이트로 먼저 보여주고, animated GIF 가 받아지면 교체한다(메뉴바도 GIF로 움직임).
    /// 에너지 통제는 ① delay 하한 0.2s(≈5fps) ② 안 보이면 정지(menuShouldAnimate) ③ 저전력 모드
    /// 에선 GIF 생략(가벼운 bob)로 처리한다 — 통제된 저프레임 + 비가시 시 정지로 저전력.
    private func ensureMenuAnimation() {
        let subject = companion.representativeSubject
        let id = subject.speciesID
        let shiny = subject.isShiny
        let key = id.map { "\($0)-\(shiny)" }
        if key == menuSpriteKey, !menuFrames.isEmpty { return }   // 이미 이 개체로 애니메이션 중
        menuSpriteKey = key
        menuLoadGen += 1
        let gen = menuLoadGen

        guard let id else {                  // 알: 2프레임 bob
            setMenuFrames(Self.eggFrames())
            return
        }
        // 정적 스프라이트 bob 을 먼저(없으면 받아와서). GIF 가 받아지면 아래에서 교체.
        if let cached = SpriteLoader.cachedImage(speciesID: id, shiny: shiny) {
            setMenuFrames(Self.bobFrames(from: cached))
        } else {
            setMenuFrames(Self.eggFrames())
            Task { @MainActor [weak self] in
                guard let self, gen == self.menuLoadGen,
                      let sprite = await SpriteLoader.image(speciesID: id, shiny: shiny) else { return }
                guard gen == self.menuLoadGen else { return }
                self.setMenuFrames(Self.bobFrames(from: sprite))
            }
        }

        // 풀 GIF 애니메이션(저전력 모드에서는 생략하고 bob 유지). delay 하한 0.1s(≤10fps)로 redraw 통제.
        guard !ProcessInfo.processInfo.isLowPowerModeEnabled else { return }
        Task { @MainActor [weak self] in
            guard let self, gen == self.menuLoadGen else { return }
            // shiny GIF 미제공 종이면 일반 GIF 폴백
            var data = await SpriteStore.shared.data(speciesID: id, animated: true, shiny: shiny)
            if data == nil, shiny {
                data = await SpriteStore.shared.data(speciesID: id, animated: true, shiny: false)
            }
            guard let data else { return }
            let raw = GIFDecoder.frames(from: data)
            guard raw.count > 1, gen == self.menuLoadGen else { return }
            // 메뉴바 GIF delay 하한 0.4s(≈2.5fps)로 캡 — 22px 스프라이트엔 5fps와 구분 안 되고, 프레임당
            // 상태바 재합성(CA 커밋 → 디스플레이 사이클 wakeup)을 절반으로 줄여 배터리 절약. bob(0.5s/2fps)과 유사.
            self.setMenuFrames(raw.map { (Self.menuBarImage(from: $0.image, up: false), max(0.4, $0.delay)) })
        }
    }

    private func setMenuFrames(_ frames: [(image: NSImage, delay: TimeInterval)]) {
        menuFrames = frames
        menuIndex = 0
        advanceMenu()
    }

    private var lastStatusImage: NSImage?

    /// 상태아이템 이미지 교체. ① **diff-gate**: 같은 이미지 재대입이면 스킵 — 레이어 dirty → CA 커밋 →
    /// WindowServer 디스플레이 사이클 왕복(= idle wakeup)을 제거한다(배터리). 단일프레임 스프라이트·중복
    /// advanceMenu 패스에서 같은 프레임을 반복 대입하던 것을 걸러낸다(애니메이션 프레임은 서로 다른 객체라
    /// 정상 통과). ② **암묵적 CA 전환 억제**: 레이어 백드 NSStatusBarButton 은 대입마다 NSStatusItemScene
    /// 전환 애니메이션을 돌려 상태바를 재합성한다(측정: idle CPU 주범) → setDisableActions 로 전환 없이 즉시 반영.
    private func setStatusImage(_ image: NSImage?) {
        guard image !== lastStatusImage else { return }
        lastStatusImage = image
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        statusItem.button?.image = image
        CATransaction.commit()
    }

    /// 현재 프레임을 메뉴바에 올리고, 그 프레임의 delay 후 다음 프레임 예약(자기 재예약).
    private func advanceMenu() {
        menuTimer?.invalidate()
        menuTimer = nil
        guard !menuFrames.isEmpty else { return }
        let frame = menuFrames[menuIndex % menuFrames.count]
        setStatusImage(frame.image)   // 현재 프레임은 항상 반영(정지 중에도 올바른 스프라이트). 전환 억제 대입.
        // 화면 꺼짐/메뉴바 가림(occlusion) 또는 단일 프레임이면 다음 프레임 예약 안 함 → 정지(낭비 제거).
        guard menuShouldAnimate, menuFrames.count > 1 else { return }
        let timer = Timer(timeInterval: frame.delay, repeats: false) { [weak self] _ in
            // 메인 런루프에서 발화 → Task 없이 동기 처리(프레임당 Task 할당 제거, 배터리)
            MainActor.assumeIsolated {
                guard let self else { return }
                self.menuIndex = (self.menuIndex + 1) % self.menuFrames.count
                self.advanceMenu()
            }
        }
        timer.tolerance = frame.delay * 0.5   // 웨이크업 코얼레싱 (배터리) — 넓힐수록 다른 wakeup 과 합쳐짐
        RunLoop.main.add(timer, forMode: .common)
        menuTimer = timer
    }

    /// 메뉴바가 실제로 보이고(occlusion) 화면이 켜져 있을 때만 애니메이션 — 안 보이면 정지(낭비 제거).
    private var menuShouldAnimate: Bool {
        // 팝오버 열림 중엔 정지 — 팝오버 SpriteView 가 이미 컴패니언을 움직여 중복이고, 트래킹 중 상태아이콘
        // 리드로우는 WindowServer 부하(다른 앱 비컨볼) 위험. (status-item 앱은 occlusion 이 실제로 잘 안 떠서
        // displayAwake 슬립 게이팅이 실질 방어 — occlusion 체크는 유지하되 보조적.)
        displayAwake && !popover.isShown
            && (statusItem.button?.window?.occlusionState.contains(.visible) ?? true)
    }

    // MARK: 프레임 합성 (22px)

    /// 스프라이트 정적 + 가벼운 상하 bob 2프레임 (animated 미지원/로딩 폴백).
    private static func bobFrames(from sprite: NSImage) -> [(image: NSImage, delay: TimeInterval)] {
        [(menuBarImage(from: sprite, up: false), 0.5), (menuBarImage(from: sprite, up: true), 0.5)]
    }

    /// 부화 전/로딩 중 알 글리프 2프레임 bob.
    private static func eggFrames() -> [(image: NSImage, delay: TimeInterval)] {
        [(eggImage(up: false), 0.5), (eggImage(up: true), 0.5)]
    }

    /// 메뉴바 프레임 기하 — **비율 유지**(SpriteFit). 순수·테스트용.
    ///
    /// 캔버스 세로는 22 로 고정(baseline 이 프레임마다 흔들리면 안 된다), 가로는 맞춘 스프라이트 폭
    /// + 좌우 1pt 만큼만. 정사각 22 고정으로 두면 세로로 긴 종(잭키 36×66 → 폭 10.9)의 좌우에 죽은
    /// 여백이 5pt 씩 생겨 사용량 숫자와 사이가 벌어진다. 세로 기준선은 바닥 정렬 유지 — GIF 캔버스는
    /// 스프라이트에 딱 맞게 크롭돼 있어 바닥이 곧 발밑이고, 정사각 원본은 예전과 픽셀 단위로 같다.
    nonisolated static func menuBarLayout(for pixelSize: CGSize, height h: CGFloat = 22,
                                          up: Bool) -> (canvas: NSSize, rect: NSRect) {
        let fit = SpriteFit.size(for: pixelSize, box: h - 2)
        return (NSSize(width: fit.width + 2, height: h),
                NSRect(x: 1, y: up ? 1 : 0, width: fit.width, height: fit.height))
    }

    static func menuBarImage(from sprite: NSImage, up: Bool) -> NSImage {
        let layout = menuBarLayout(for: sprite.size, up: up)
        let img = NSImage(size: layout.canvas)
        img.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .none
        sprite.draw(in: layout.rect, from: .zero, operation: .sourceOver, fraction: 1)
        img.unlockFocus()
        return img
    }

    /// TokenMac→PokeTokenBar 리네임에 따른 1회 이전: 기존 Application Support 폴더를
    /// 새 이름으로 옮겨 companion 진행상황·스프라이트 캐시·스냅샷을 보존한다(신규 폴더 없을 때만).
    private static func migrateLegacyStorageIfNeeded() {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let old = base.appendingPathComponent("TokenMac")
        let new = base.appendingPathComponent("PokeTokenBar")
        guard fm.fileExists(atPath: old.path), !fm.fileExists(atPath: new.path) else { return }
        try? fm.moveItem(at: old, to: new)
    }

    /// 스프라이트가 아직 없을 때(부화 전/로딩 중) 메뉴바에 표시하는 알 글리프.
    private static func eggImage(up: Bool) -> NSImage {
        let h: CGFloat = 22
        let img = NSImage(size: NSSize(width: h, height: h))
        img.lockFocus()
        let off: CGFloat = up ? 1 : 0
        let s = "🥚" as NSString
        s.draw(in: NSRect(x: 2, y: off, width: h - 2, height: h - 2),
               withAttributes: [.font: NSFont.systemFont(ofSize: 15)])
        img.unlockFocus()
        return img
    }

    /// 팝오버 콘텐츠(SwiftUI 호스팅) 생성. .transient 팝오버는 contentViewController 를 평생 보유해 닫혀도
    /// NSHostingView 트리가 상주하며 매 디스플레이 사이클 재레이아웃된다(측정: idle CPU 최대 비용 — 닫힌
    /// 팝오버의 relative-time Text self-invalidation × 메뉴 애니메이션 CA 커밋). 그래서 열 때 만들고 닫힐 때 해제.
    func openPopover() {
        // Pet click is an outside click for a .transient popover — if already shown it is
        // already dismissing; the old "activate/makeKey" branch never applied.
        guard !popover.isShown else { return }
        togglePopover()
    }

    private func buildPopoverContent() {
        popover.contentViewController = NSHostingController(
            rootView: PopoverView()
                .environment(store).environment(companion).environment(updater).environment(navigation))
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)   // 해제·메뉴 애니메이션 재개는 popoverDidClose 에서
        } else {
            navigation.reset()   // 닫혔다 열리면 항상 Home 으로 (설정 화면 잔류 방지)
            buildPopoverContent()   // 열 때 호스팅 트리 생성(닫힐 때 해제)
            // LSUIElement 앱이 비활성이면 팝오버 내부 버튼 클릭이 무시됨 — show 전에 활성화 보장
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKeyAndOrderFront(nil)
            syncMenuAnimation()   // 팝오버 열림 → 메뉴바 애니메이션 정지(중복 + WindowServer 부하 회피)
            store.requestNotificationAuthorizationIfNeeded()   // 알림 권한은 사용자가 앱을 처음 열 때 요청
            Task { await updater.check() }   // 팝오버 열 때 재확인(내부 minInterval 디바운스)
        }
    }

    /// Start and stop are both delegate-driven so a second `show` path cannot
    /// overwrite a live token (#168). `start` is also idempotent if `didShow` fires twice.
    func popoverDidShow(_ notification: Notification) {
        startOutsideClickMonitor()
    }

    /// 팝오버가 닫히면 호스팅 컨트롤러 해제(숨은 트리 재레이아웃 비용 제거) + 메뉴바 애니메이션 재개.
    func popoverDidClose(_ notification: Notification) {
        stopOutsideClickMonitor()
        popover.contentViewController = nil
        syncMenuAnimation()
    }

    /// 다른 메뉴바 팝업은 앱을 비활성화 안 시켜 .transient 가 못 닫는다 → 열림 동안만 앱 밖 클릭을 직접 감지해 닫는다(관찰 전용, 권한 불필요).
    private func startOutsideClickMonitor() {
        outsideClickMonitor.start {
            NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.popover.isShown else { return }
                    self.popover.performClose(nil)
                }
            }
        }
    }

    private func stopOutsideClickMonitor() {
        outsideClickMonitor.stop { NSEvent.removeMonitor($0) }
    }

    // MARK: 디스플레이 / 메뉴바 가시성 (에너지 절약 — 안 보이면 애니메이션 정지)

    private func observeDisplaySleep() {
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.setDisplayAwake(false) }
        }
        workspace.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.setDisplayAwake(true) }
        }
        // 메뉴바가 가려지면(풀스크린 등으로 occlusion) 애니메이션 정지, 다시 보이면 재개.
        NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.syncMenuAnimation() }
        }
    }

    private func setDisplayAwake(_ awake: Bool) {
        displayAwake = awake
        syncMenuAnimation()
        floatingPet.setDisplayAwake(awake)   // 슬립 중엔 펫 호스팅 트리 해제(GIF 루프 정지)
    }

    /// menuShouldAnimate 상태에 맞춰 애니메이션을 재개/정지한다(멱등 — 중복 호출 안전).
    private func syncMenuAnimation() {
        if menuShouldAnimate {
            if menuTimer == nil { advanceMenu() }   // 재개
        } else {
            menuTimer?.invalidate()
            menuTimer = nil
        }
    }

    // MARK: - Dynamic App Icon

    /// 대표 포켓몬이 바뀔 때 Dock 아이콘도 동기화 — 1024×1024 캔버스에 스프라이트 중앙 배치.
    /// 에그면 기본 아이콘으로 복귀. 캐시된 정적 스프라이트만 사용(동기, 아이콘 변경 비용 최소).
    private func updateAppIcon() {
        let subject = companion.representativeSubject
        guard let id = subject.speciesID, !companion.isEgg else {
            // 알 또는 대표 없음 → 빌트인 아이콘으로 복귀
            if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
               let image = NSImage(contentsOf: iconURL) {
                NSApp.applicationIconImage = image
            }
            return
        }
        guard let sprite = SpriteLoader.cachedImage(speciesID: id, shiny: subject.isShiny) else { return }
        NSApp.applicationIconImage = Self.appIconImage(from: sprite)
    }

    /// 스프라이트를 1024×1024 아이콘 캔버스에 중앙 배치 (배경: 디스플레이 팔레트 미러).
    private static func appIconImage(from sprite: NSImage) -> NSImage {
        let size = NSSize(width: 1024, height: 1024)
        let icon = NSImage(size: size)
        icon.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        // 배경 — 다크 블렌드(폴백: #1a1a2e)
        let bg = NSColor(red: 0.102, green: 0.102, blue: 0.18, alpha: 1)
        bg.setFill()
        NSRect(origin: .zero, size: size).fill()
        // 스프라이트 — 72% 영역에 중앙 정렬
        let spriteArea: CGFloat = 738  // 1024 × 0.72
        let spriteSize = NSSize(width: spriteArea, height: spriteArea)
        let origin = NSPoint(
            x: (size.width - spriteSize.width) / 2,
            y: (size.height - spriteSize.height) / 2)
        sprite.draw(in: NSRect(origin: origin, size: spriteSize),
                     from: .zero, operation: .sourceOver, fraction: 1)
        icon.unlockFocus()
        return icon
    }
}
