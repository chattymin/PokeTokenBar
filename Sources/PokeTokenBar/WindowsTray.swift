#if os(Windows)
import Foundation
import WinSDK

/// Windows system-tray host + popover — counterpart of the macOS `NSStatusItem` menu bar, driving
/// the real **companion** (egg → hatch → evolve) off token usage.
///
/// Threading mirrors the proven pattern: the Win32 message loop runs on the **main thread**
/// (blocking `GetMessageW`), and all async work — usage parse, companion update, sprite fetch,
/// limits — runs in a `Task.detached` kicked off from a 30s `SetTimer` (and on click/menu). Results
/// are handed back to the message-loop thread via `PostMessageW`. `CompanionStore` is
/// `@unchecked Sendable` on Windows (see its header) so it can be driven from that background task;
/// a `refreshing` guard keeps refreshes serial.
enum WindowsTray {
    private static let callbackMessage = UINT(WM_APP) + 1
    private static let updateMessage = UINT(WM_APP) + 2
    private static let showMessage = UINT(WM_APP) + 3   // a second instance asks the running one to show
    private static let sinkClassName = "PokeTokenBarTraySink"
    nonisolated(unsafe) private static var instanceMutex: HANDLE?   // single-instance guard (held for life)
    private static let menuRefresh = UINT(1001)
    private static let menuQuit = UINT(1002)
    private static let menuAutostart = UINT(1003)
    private static let timerID = UINT_PTR(1)        // 30s usage refresh
    private static let animTimerID = UINT_PTR(2)    // sprite animation frame cadence

    nonisolated(unsafe) static var sinkHwnd: HWND?
    nonisolated(unsafe) static var popupHwnd: HWND?
    nonisolated(unsafe) static var nid = NOTIFYICONDATAW()
    nonisolated(unsafe) private static var companion: CompanionStore?

    private static let popupWidth: Int32 = 384
    private static let popupHeight: Int32 = 648
    private static let bannerHeight: Int32 = 46   // update banner above the tabs (macOS parity)

    private static let lock = NSLock()
    nonisolated(unsafe) private static var pendingTip = "PokeTokenBar — loading…"
    nonisolated(unsafe) private static var pendingIcon: HICON?
    nonisolated(unsafe) private static var currentIcon: HICON?          // static sprite (egg / fallback)
    nonisolated(unsafe) private static var animFrames: [HICON] = []     // animated sprite frames (UI thread)
    nonisolated(unsafe) private static var animIndex = 0
    nonisolated(unsafe) private static var animSpeciesKey: String?      // which species' animation is loaded
    nonisolated(unsafe) private static var pendingAnim: [HICON]?        // bg → UI handoff (lock)
    nonisolated(unsafe) private static var pendingAnimKey: String?
    nonisolated(unsafe) private static var reportLines: [String] = ["Loading…"]
    nonisolated(unsafe) private static var currentDisplay = CompanionDisplay()
    nonisolated(unsafe) private static var currentUsage = UsageSnapshot()
    // Last successful Claude limit % — retained so a transient fetch failure (429 rate-limit, network)
    // shows the last-good value as stale instead of blanking the Home limit rows to "—" (macOS parity).
    nonisolated(unsafe) private static var lastClaude5h: Int?
    nonisolated(unsafe) private static var lastClaude7d: Int?
    nonisolated(unsafe) private static var lastLimitFetch: Date?   // throttle oauth/usage to ≥25s apart
    nonisolated(unsafe) private static var availableUpdate: WindowsUpdate.Available?   // newer release, if any
    nonisolated(unsafe) private static var lastUpdateCheck: Date?   // throttle the release check to ≥30 min
    nonisolated(unsafe) private static var updating = false   // true while an in-place update runs (full-cover overlay)
    nonisolated(unsafe) private static var updateDots = 0     // animated "…" for the update overlay
    nonisolated(unsafe) private static var buttonHits: [(rect: RECT, action: Int)] = []   // popover action buttons
    nonisolated(unsafe) private static var popupView = 0        // 0 = home, 1 = dex, 2 = settings
    nonisolated(unsafe) private static var dexIcons: [Int: HICON] = [:]   // finalID → sprite HICON (cache)
    nonisolated(unsafe) private static var itemIcons: [String: HICON] = [:]   // item spriteName → HICON (cache)
    nonisolated(unsafe) private static var emojiIcons: [String: HICON] = [:]   // emoji → color-image HICON (GDI can't draw color emoji)
    nonisolated(unsafe) private static var evoIcons: [Int: HICON] = [:]   // evo-line speciesID → sprite HICON (cache)
    nonisolated(unsafe) private static var selectedHomeProvider = 0   // 0=Claude 1=Codex 2=Gemini 3=OpenCode 4=Hermes (Home tabs)
    nonisolated(unsafe) private static var openDropdown = 0   // Settings: 0=none, 1=language, 2=interval (expanded inline)
    nonisolated(unsafe) private static var settingsScroll: Int32 = 0   // Settings tab mouse-wheel scroll (px)
    nonisolated(unsafe) static var settingsContentH: Int32 = 0   // total Settings content height (scroll clamp)
    nonisolated(unsafe) private static var uiLang = "en"                  // current UI language for L()
    nonisolated(unsafe) private static var dexScroll: Int32 = 0           // dex grid scroll offset (px)
    private static let dexGridTop: Int32 = 82   // below the tab bar + dex header
    private static let dexCellH: Int32 = 78
    private static let dexCols: Int32 = 4
    private static let contentTop: Int32 = 46    // below the tab bar
    nonisolated(unsafe) private static var pendingAlert: String?
    nonisolated(unsafe) private static var refreshing = false
    nonisolated(unsafe) private static var stayVisible = false
    nonisolated(unsafe) private static var lastAlertTier = 0

    // MARK: Entry (main thread — Win32 message loop)

    static func run() {
        if let console = GetConsoleWindow() { _ = ShowWindow(console, SW_HIDE) }
        // Single instance: hold a named mutex for the process's life. If another instance already owns
        // it, ask that one to show its popover (so re-launching from the Start menu feels responsive)
        // and exit.
        instanceMutex = "Local\\PokeTokenBar-SingleInstance".withCString(encodedAs: UTF16.self) {
            CreateMutexW(nil, false, $0)
        }
        if GetLastError() == DWORD(ERROR_ALREADY_EXISTS) {
            if let existing = sinkClassName.wide.withUnsafeBufferPointer({
                FindWindowExW(HWND(bitPattern: -3), nil, $0.baseAddress, nil)   // HWND_MESSAGE parent
            }) { _ = PostMessageW(existing, showMessage, 0, 0) }
            return
        }
        // CompanionStore is created lazily on CompanionActor in the first refresh (its init is
        // actor-isolated, so it can't be constructed from this synchronous context).
        let hInstance = GetModuleHandleW(nil)
        let sinkClass = sinkClassName.wide
        _ = sinkClass.withUnsafeBufferPointer { p -> Bool in
            var wc = WNDCLASSEXW()
            wc.cbSize = UINT(MemoryLayout<WNDCLASSEXW>.size)
            wc.lpfnWndProc = trayProc
            wc.hInstance = hInstance
            wc.lpszClassName = p.baseAddress
            return RegisterClassExW(&wc) != 0
        }
        sinkHwnd = sinkClass.withUnsafeBufferPointer { p in
            CreateWindowExW(0, p.baseAddress, p.baseAddress, 0, 0, 0, 0, 0,
                            HWND(bitPattern: -3), nil, hInstance, nil)
        }
        guard sinkHwnd != nil else { print("tray window failed: \(GetLastError())"); return }
        createPopup(hInstance)

        nid.cbSize = DWORD(MemoryLayout<NOTIFYICONDATAW>.size)
        nid.hWnd = sinkHwnd
        nid.uID = 1
        nid.uFlags = UINT(NIF_ICON | NIF_MESSAGE | NIF_TIP)
        nid.uCallbackMessage = callbackMessage
        nid.hIcon = LoadIconW(nil, UnsafePointer<WCHAR>(bitPattern: 32512))
        applySnapshot()
        _ = Shell_NotifyIconW(DWORD(NIM_ADD), &nid)

        scheduleRefresh()
        applyRefreshInterval()   // usage-refresh timer from the configured interval (default 2 min)
        _ = SetTimer(sinkHwnd, animTimerID, 120, nil)   // sprite animation ~8fps
        if CommandLine.arguments.contains("--show-popup") { stayVisible = true; togglePopup() }

        var msg = MSG()
        while GetMessageW(&msg, nil, 0, 0) {
            TranslateMessage(&msg)
            DispatchMessageW(&msg)
        }
        _ = Shell_NotifyIconW(DWORD(NIM_DELETE), &nid)
    }

    // MARK: Background refresh (Task.detached — off the message-loop thread)

    private static func scheduleRefresh() {
        let go = lock.withLock { () -> Bool in
            if refreshing { return false }
            refreshing = true; return true
        }
        guard go else { return }   // keep refreshes serial (companion isn't reentrancy-safe)
        Task.detached {
            await refresh()
            lock.withLock { refreshing = false }
        }
    }

    @CompanionActor
    private static func makeCompanion() -> CompanionStore {
        let c = CompanionStore()
        c.onEvent = { title, body in WindowsTray.queueToast("\(title): \(body)") }
        return c
    }

    private static func refresh() async {
        let companion: CompanionStore
        if let existing = self.companion {
            companion = existing
        } else {
            companion = await makeCompanion()
            self.companion = companion
        }
        let now = Date()
        let fmt = LocalUsageReader.localDayFormatter()
        let monthStart = LocalUsageReader.startOfMonth(now)
        let weekStart = LocalUsageReader.startOfWeek(now)

        let claude = await LocalUsageCache.shared.claudeEntries(modifiedSince: monthStart)
        let codex = await LocalUsageCache.shared.codexEntries(modifiedSince: monthStart)
        let gemini = await LocalUsageCache.shared.geminiEntries(modifiedSince: monthStart)
        // OpenCode/Hermes read local SQLite DBs (cheap indexed queries). Empty where no SQLite module.
        let opencode = Self.openCodeEntries(since: monthStart)
        let hermes = Self.hermesEntries(since: monthStart)
        let all = claude + codex + gemini + opencode + hermes
        let todayKey = LocalUsageReader.todayKey()
        let todayTotal = LocalUsageReader.daily(entries: all, localDay: todayKey)?.totalTokens ?? 0
        let monthTotal = LocalUsageReader.period(entries: all, periodKey: "m",
            fromDay: fmt.string(from: monthStart), toDay: fmt.string(from: now)).totalTokens

        await companion.update(todayTokens: todayTotal, todayDate: todayKey, monthTotal: monthTotal,
                               burnTier: todayTotal > 0 ? .normal : .idle, limitWarning: false,
                               hasUsageData: !all.isEmpty)
        let disp = await companion.windowsDisplay   // Sendable snapshot (single actor hop)

        var claude5h: Int?, claude7d: Int?
        let codexPct: Int? = nil
        // Throttle the oauth/usage fetch to ≥25s apart. Every user action (buy/use/language change)
        // calls scheduleRefresh, so without this a burst of clicks would hammer the endpoint and trip
        // its 429 rate-limit. The 30s poll timer still refetches each tick; action-driven refreshes
        // in between reuse the cached %. The attempt time is stamped even on failure so an active 429
        // window isn't retried on every click.
        let limitDue = lock.withLock { () -> Bool in
            let due = lastLimitFetch.map { now.timeIntervalSince($0) >= 25 } ?? true
            if due { lastLimitFetch = now }
            return due
        }
        if limitDue {
            do {
                let limits = try await OAuthLimitsProvider().fetch(allowKeychainPrompt: false)
                claude5h = limits.fiveHour?.utilization.map { Int($0.rounded()) }
                claude7d = limits.sevenDay?.utilization.map { Int($0.rounded()) }
                lock.withLock { lastClaude5h = claude5h; lastClaude7d = claude7d }
            } catch {
                // Transient failure (429, offline, expired token) — reuse the last-good % rather than
                // blanking the Home limit rows to "—" (macOS keeps the last value stale, not empty).
                (claude5h, claude7d) = lock.withLock { (lastClaude5h, lastClaude7d) }
            }
        } else {
            (claude5h, claude7d) = lock.withLock { (lastClaude5h, lastClaude7d) }
        }
        // Codex rate-limit fetch is skipped on Windows: codex 0.145.0's account/rateLimits/read
        // returns no data (verified directly), and each attempt otherwise hangs the refresh on a
        // 20s spawn timeout. Codex *usage* (tokens) is unaffected — it's parsed from log files.

        let icon = await companionIcon(disp)
        // Animated companion sprite (Gen-V GIF → frame HICONs). Reload only when species/shiny changes.
        let animKey = disp.isEgg ? "egg" : (disp.speciesID.map { "\($0)-\(disp.isShiny)" } ?? "none")
        if lock.withLock({ animSpeciesKey != animKey && pendingAnimKey != animKey }) {
            var frames: [HICON] = []
            if !disp.isEgg, let id = disp.speciesID,
               let gif = await SpriteStore.shared.data(speciesID: id, animated: true, shiny: disp.isShiny) {
                frames = WindowsImaging.hiconsFromGIF(gif) ?? []
            }
            lock.withLock { pendingAnim = frames; pendingAnimKey = animKey }
        }
        // Pre-fetch dex sprites (once each) so the collection grid renders without flashes.
        for item in disp.dex {
            let have = lock.withLock { dexIcons[item.speciesID] != nil }
            if !have,
               let png = await SpriteStore.shared.data(speciesID: item.speciesID, animated: false, shiny: item.isShiny),
               let ic = WindowsImaging.hicon(fromPNG: png) {
                lock.withLock { dexIcons[item.speciesID] = ic }
            }
        }
        // Pre-fetch evolution-line sprites (Home card thumbnails) — one per node species.
        for node in disp.lineNodes {
            let have = lock.withLock { evoIcons[node.id] != nil }
            if !have,
               let png = await SpriteStore.shared.data(speciesID: node.id, animated: false, shiny: disp.isShiny),
               let ic = WindowsImaging.hicon(fromPNG: png) {
                lock.withLock { evoIcons[node.id] = ic }
            }
        }
        // Item sprites for Bag / Shop (rare-candy, shiny-charm; mint has no PokeAPI sprite).
        for name in ["rare-candy", "shiny-charm"] {
            if lock.withLock({ itemIcons[name] == nil }),
               let png = await SpriteStore.shared.data(itemName: name),
               let ic = WindowsImaging.hicon(fromPNG: png) {
                lock.withLock { itemIcons[name] = ic }
            }
        }
        // The Shop's fresh-egg card uses the pokemon/egg.png sprite (not an item sprite; there is no
        // items/egg.png), cached under "egg" — the same source as the companion egg.
        if lock.withLock({ itemIcons["egg"] == nil }),
           let png = await SpriteStore.shared.eggData(),
           let ic = WindowsImaging.hicon(fromPNG: png) {
            lock.withLock { itemIcons["egg"] = ic }
        }
        // Color emoji images (Noto, runtime-fetched) for Shop/Bag cards with no PokeAPI sprite (e.g.
        // mint 🌿). GDI draws color emoji as a flat monochrome glyph, so we render the fetched PNG
        // instead — matching how macOS shows the Apple color-emoji glyph.
        let fallbackEmojis = Set((disp.shopEntries + disp.bagEntries).filter { $0.icon == nil }.map(\.emoji))
        for emoji in fallbackEmojis {
            if lock.withLock({ emojiIcons[emoji] == nil }),
               let png = await SpriteStore.shared.emojiData(emoji),
               let ic = WindowsImaging.hicon(fromPNG: png) {
                lock.withLock { emojiIcons[emoji] = ic }
            }
        }
        // Combined usage + Claude breakdown for the Home tab.
        func period(_ e: [LocalUsageReader.Entry], _ from: Date) -> PeriodUsage {
            LocalUsageReader.period(entries: e, periodKey: "p", fromDay: fmt.string(from: from), toDay: fmt.string(from: now))
        }
        var us = UsageSnapshot()
        let allToday = LocalUsageReader.daily(entries: all, localDay: todayKey)
        us.todayTokens = allToday?.totalTokens ?? 0; us.todayCost = allToday?.totalCost ?? 0
        let w = period(all, weekStart); us.weekTokens = w.totalTokens; us.weekCost = w.totalCost
        let m = period(all, monthStart); us.monthTokens = m.totalTokens; us.monthCost = m.totalCost
        let ct = LocalUsageReader.daily(entries: claude, localDay: todayKey)
        us.claudeToday = ct?.totalTokens ?? 0; us.claudeCost = ct?.totalCost ?? 0
        us.claudeIn = ct?.inputTokens ?? 0; us.claudeOut = ct?.outputTokens ?? 0
        us.claudeCacheW = ct?.cacheCreationTokens ?? 0; us.claudeCacheR = ct?.cacheReadTokens ?? 0
        us.claude5h = claude5h; us.claude7d = claude7d
        us.claudeUsed = period(claude, monthStart).totalTokens > 0
        us.codexUsed = period(codex, monthStart).totalTokens > 0
        us.geminiUsed = period(gemini, monthStart).totalTokens > 0
        us.opencodeUsed = period(opencode, monthStart).totalTokens > 0
        us.hermesUsed = period(hermes, monthStart).totalTokens > 0
        let cot = LocalUsageReader.daily(entries: codex, localDay: todayKey)
        us.codexToday = cot?.totalTokens ?? 0; us.codexCost = cot?.totalCost ?? 0
        let get = LocalUsageReader.daily(entries: gemini, localDay: todayKey)
        us.geminiToday = get?.totalTokens ?? 0; us.geminiCost = get?.totalCost ?? 0
        let oot = LocalUsageReader.daily(entries: opencode, localDay: todayKey)
        us.opencodeToday = oot?.totalTokens ?? 0; us.opencodeCost = oot?.totalCost ?? 0
        let het = LocalUsageReader.daily(entries: hermes, localDay: todayKey)
        us.hermesToday = het?.totalTokens ?? 0; us.hermesCost = het?.totalCost ?? 0

        let tip = buildTip(disp: disp, claude: claude, claude5h: claude5h, claude7d: claude7d)
        let report = buildReport(disp: disp, claude: claude, codex: codex, gemini: gemini,
                                 opencode: opencode, hermes: hermes,
                                 now: now, fmt: fmt, weekStart: weekStart, monthStart: monthStart,
                                 claude5h: claude5h, claude7d: claude7d, codexPct: codexPct)
        let alert = limitAlert(claude7d)

        lock.withLock {
            pendingTip = tip; reportLines = report; currentDisplay = disp; currentUsage = us
            if icon != nil { pendingIcon = icon }
            if let alert { pendingAlert = alert }
        }
        if let sinkHwnd { _ = PostMessageW(sinkHwnd, updateMessage, 0, 0) }

        // Background release check — long throttle (the timer path), with a Windows toast on detection.
        // Opening the popover checks with no throttle but WITHOUT a toast (see togglePopup) — the banner
        // is enough for an explicit action; only the periodic background check pops a notification.
        checkForUpdate(minInterval: 1800, toast: true)
    }

    /// Check GitHub for a newer release and surface it (always the banner; a Windows toast only when
    /// `toast` is true). `minInterval` ≤ 0 always checks (popover open); otherwise throttled since the
    /// last check. `lastUpdateCheck` is shared, so opening the popover keeps the timer path's throttle
    /// fresh and it becomes a fallback.
    private static func checkForUpdate(minInterval: TimeInterval, toast: Bool) {
        let due = lock.withLock { () -> Bool in
            let ok = minInterval <= 0 || (lastUpdateCheck.map { Date().timeIntervalSince($0) >= minInterval } ?? true)
            if ok { lastUpdateCheck = Date() }
            return ok
        }
        guard due else { return }
        Task.detached {
            guard let upd = await WindowsUpdate.check() else { return }
            let isNew = lock.withLock { () -> Bool in let changed = availableUpdate != upd; availableUpdate = upd; return changed }
            if toast && isNew {
                queueToast(L("새 버전 \(upd.version) 사용 가능", "Update available: \(upd.version)", "新バージョン \(upd.version) が利用可能"))
            }
            resizePopupForBanner()   // grow the window if it's open so the banner doesn't clip content
        }
    }

    /// Resize the (visible) popup to the current effective height and repaint — used when the update
    /// banner appears/disappears while the popover is already open.
    /// Surface the popover (open it if hidden, else bring it forward) — used when a second instance
    /// is launched and hands off to the running one.
    private static func showPopup() {
        guard let popupHwnd else { return }
        if IsWindowVisible(popupHwnd) { _ = SetForegroundWindow(popupHwnd) } else { togglePopup() }
    }

    private static func resizePopupForBanner() {
        guard let popupHwnd else { return }
        if IsWindowVisible(popupHwnd) {
            _ = SetWindowPos(popupHwnd, nil, 0, 0, popupWidth, effectivePopupHeight(),
                             UINT(SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE))
        }
        InvalidateRect(popupHwnd, nil, true)
    }

    private static func companionIcon(_ disp: CompanionDisplay) async -> HICON? {
        let png: Data?
        if disp.isEgg {
            png = await SpriteStore.shared.eggData()
        } else if let id = disp.speciesID {
            png = await SpriteStore.shared.data(speciesID: id, animated: false, shiny: disp.isShiny)
        } else {
            png = nil
        }
        guard let png else { return nil }
        return WindowsImaging.hicon(fromPNG: png)
    }

    // OpenCode/Hermes usage comes from local SQLite DBs. The reader compiles only where a SQLite
    // module is importable (system SQLite3 on macOS, vendored CSQLite on Windows); elsewhere these
    // return empty so the rest of the tray sees "provider unused" and its pill/rows never appear.
    #if canImport(SQLite3) || canImport(CSQLite)
    private static func openCodeEntries(since: Date) -> [LocalUsageReader.Entry] {
        LocalAdditionalUsageReader.openCodeEntries(modifiedSince: since)
    }
    private static func hermesEntries(since: Date) -> [LocalUsageReader.Entry] {
        LocalAdditionalUsageReader.hermesEntries(modifiedSince: since)
    }
    #else
    private static func openCodeEntries(since: Date) -> [LocalUsageReader.Entry] { [] }
    private static func hermesEntries(since: Date) -> [LocalUsageReader.Entry] { [] }
    #endif

    // MARK: Snapshot text

    private static func buildTip(disp: CompanionDisplay, claude: [LocalUsageReader.Entry],
                                 claude5h: Int?, claude7d: Int?) -> String {
        // "Show in tray tooltip" toggles (the Windows analog of the macOS menu-bar display options).
        let d = UserDefaults.standard
        let showTok = d.object(forKey: "tipShowTokens") as? Bool ?? true
        let showCost = d.object(forKey: "tipShowCost") as? Bool ?? false
        let showLim = d.object(forKey: "tipShowLimit") as? Bool ?? true
        var lines = [companionStatusLine(disp)]
        let today = LocalUsageReader.daily(entries: claude, localDay: LocalUsageReader.todayKey())
        var parts: [String] = []
        if showTok { parts.append("Claude \(TokenFormatter.compact(today?.totalTokens ?? 0)) today") }
        if showCost { parts.append(TokenFormatter.cost(today?.totalCost ?? 0)) }
        if showLim {
            let lim = [claude5h.map { "5h \($0)%" }, claude7d.map { "7d \($0)%" }].compactMap { $0 }
            if !lim.isEmpty { parts.append("(\(lim.joined(separator: ", ")))") }
        }
        if !parts.isEmpty { lines.append(parts.joined(separator: " ")) }
        return String(lines.joined(separator: "\n").prefix(127))
    }

    private static func companionStatusLine(_ d: CompanionDisplay) -> String {
        if d.isEgg {
            return d.eggStarted
                ? "Egg \(Int(d.eggProgress * 100))% — \(TokenFormatter.compact(d.eggTokensToHatch)) to hatch"
                : "Token Egg"
        }
        let stage = d.stageText.isEmpty ? "" : " · \(d.stageText)"
        return d.isFinalStage ? "\(d.displayName)\(stage)"
                              : "\(d.displayName)\(stage) — \(TokenFormatter.compact(d.tokensToNext)) to evolve"
    }

    private static func buildReport(disp d: CompanionDisplay, claude: [LocalUsageReader.Entry],
                                    codex: [LocalUsageReader.Entry], gemini: [LocalUsageReader.Entry],
                                    opencode: [LocalUsageReader.Entry], hermes: [LocalUsageReader.Entry],
                                    now: Date, fmt: DateFormatter, weekStart: Date, monthStart: Date,
                                    claude5h: Int?, claude7d: Int?, codexPct: Int?) -> [String] {
        var lines: [String] = []   // usage + limits only; the Home view draws the companion card itself
        func block(_ name: String, _ entries: [LocalUsageReader.Entry], showCost: Bool) {
            let month = LocalUsageReader.period(entries: entries, periodKey: "m",
                fromDay: fmt.string(from: monthStart), toDay: fmt.string(from: now))
            guard month.totalTokens > 0 else { return }
            let today = LocalUsageReader.daily(entries: entries, localDay: LocalUsageReader.todayKey())
            let week = LocalUsageReader.period(entries: entries, periodKey: "w",
                fromDay: fmt.string(from: weekStart), toDay: fmt.string(from: now))
            lines.append(name)
            lines.append("  today \(pad(TokenFormatter.compact(today?.totalTokens ?? 0)))"
                       + "  week \(pad(TokenFormatter.compact(week.totalTokens)))"
                       + "  month \(pad(TokenFormatter.compact(month.totalTokens)))")
            if showCost { lines.append("  cost  \(TokenFormatter.cost(month.totalCost)) / month") }
            lines.append("")
        }
        block("Claude Code", claude, showCost: true)
        block("Codex", codex, showCost: false)
        block("Gemini", gemini, showCost: true)
        block("OpenCode", opencode, showCost: true)
        block("Hermes Agent", hermes, showCost: true)
        if claude5h != nil || claude7d != nil {
            lines.append("Claude limits")
            if let u = claude5h { lines.append("  5-hour  \(u)%") }
            if let u = claude7d { lines.append("  7-day   \(u)%") }
            lines.append("")
        }
        if let p = codexPct { lines.append("Codex limit  \(p)%") }
        return lines
    }

    private static func pad(_ s: String) -> String { s.padding(toLength: 7, withPad: " ", startingAt: 0) }

    /// Localize a UI string to the current companion language (uiLang set each paint).
    private static func L(_ ko: String, _ en: String, _ ja: String) -> String {
        switch uiLang { case "ko": return ko; case "ja": return ja; default: return en }
    }

    private static func limitAlert(_ claude7d: Int?) -> String? {
        guard UserDefaults.standard.object(forKey: "limitAlertsEnabled") as? Bool ?? true else { lastAlertTier = 0; return nil }
        let pct = claude7d ?? 0
        let warn = UserDefaults.standard.object(forKey: "warnThreshold") as? Int ?? 80
        let crit = UserDefaults.standard.object(forKey: "critThreshold") as? Int ?? 95
        let tier = pct >= crit ? 2 : pct >= warn ? 1 : 0   // edge-triggered on tier level
        defer { lastAlertTier = tier }
        guard tier > lastAlertTier else { return nil }
        return tier >= 2 ? "Claude weekly limit at \(pct)% — imminent!" : "Claude weekly limit at \(pct)% — heads up!"
    }

    private static func queueToast(_ message: String) {
        lock.withLock { pendingAlert = message }
        if let sinkHwnd { _ = PostMessageW(sinkHwnd, updateMessage, 0, 0) }
    }

    // MARK: Window-thread updates

    private static func applySnapshot() {
        writeWide(&nid.szTip, lock.withLock { pendingTip }, capacity: 128)
        let newIcon: HICON? = lock.withLock { let i = pendingIcon; pendingIcon = nil; return i }
        if let newIcon {
            if let old = currentIcon { DestroyIcon(old) }
            currentIcon = newIcon
        }
        // Consume a pending animation (empty array = "no animation, use the static icon").
        if let newAnim = lock.withLock({ let a = pendingAnim; pendingAnim = nil; return a }) {
            for old in animFrames { DestroyIcon(old) }
            animFrames = newAnim
            animIndex = 0
            animSpeciesKey = lock.withLock { pendingAnimKey }
        }
        nid.hIcon = displayedIcon()
        _ = Shell_NotifyIconW(DWORD(NIM_MODIFY), &nid)
        if let popupHwnd, IsWindowVisible(popupHwnd) { InvalidateRect(popupHwnd, nil, true) }
        if let msg = lock.withLock({ let m = pendingAlert; pendingAlert = nil; return m }) {
            notify(title: "PokeTokenBar", message: msg)
        }
    }

    /// The icon to show right now — the current animation frame if animated, else the static sprite.
    private static func displayedIcon() -> HICON? {
        animFrames.isEmpty ? currentIcon : animFrames[animIndex % animFrames.count]
    }

    /// Advance the sprite animation one frame — updates the tray icon and (if open) the popover sprite.
    private static func animateTick() {
        // While updating, animate the overlay's "…" dots instead of the sprite.
        if lock.withLock({ updating }) {
            lock.withLock { updateDots = (updateDots + 1) % 4 }
            if let popupHwnd, IsWindowVisible(popupHwnd) { InvalidateRect(popupHwnd, nil, false) }
            return
        }
        guard animFrames.count > 1 else { return }
        animIndex = (animIndex + 1) % animFrames.count
        nid.hIcon = animFrames[animIndex]
        _ = Shell_NotifyIconW(DWORD(NIM_MODIFY), &nid)
        if let popupHwnd, IsWindowVisible(popupHwnd), popupView == 0 {
            // Match the full-paint offset: the update banner shifts the whole Home view down, so the
            // incremental sprite redraw must shift too — otherwise it draws over the tabs.
            let dy: Int32 = bannerVisible() ? bannerHeight : 0
            let hdc = GetDC(popupHwnd)
            fillRound(hdc, RECT(left: 16, top: 50 + dy, right: 116, bottom: 150 + dy), 12, rgb(20, 20, 24))
            DrawIconEx(hdc, 22, 56 + dy, animFrames[animIndex], 88, 88, 0, nil, UINT(DI_NORMAL))
            ReleaseDC(popupHwnd, hdc)
        }
    }

    static func notify(title: String, message: String) {
        nid.uFlags = UINT(NIF_INFO)
        writeWide(&nid.szInfoTitle, title, capacity: 64)
        writeWide(&nid.szInfo, message, capacity: 256)
        // Show the current companion sprite (the app's own icon) as the toast icon, not the generic
        // system "info" glyph. NIIF_USER uses hBalloonIcon (falls back to the tray icon if nil).
        nid.hBalloonIcon = displayedIcon() ?? currentIcon
        nid.dwInfoFlags = DWORD(NIIF_USER) | 0x20   // NIIF_USER | NIIF_LARGE_ICON
        _ = Shell_NotifyIconW(DWORD(NIM_MODIFY), &nid)
        nid.uFlags = UINT(NIF_ICON | NIF_MESSAGE | NIF_TIP)
        nid.hBalloonIcon = nil
    }

    private static func writeWide<T>(_ field: inout T, _ text: String, capacity: Int) {
        withUnsafeMutablePointer(to: &field) { p in
            p.withMemoryRebound(to: UInt16.self, capacity: capacity) { buf in
                let chars = Array(text.utf16.prefix(capacity - 1))
                for (i, c) in chars.enumerated() { buf[i] = c }
                buf[chars.count] = 0
            }
        }
    }

    // MARK: Popover window

    private static func createPopup(_ hInstance: HMODULE?) {
        let cls = "PokeTokenBarPopup".wide
        _ = cls.withUnsafeBufferPointer { p -> Bool in
            var wc = WNDCLASSEXW()
            wc.cbSize = UINT(MemoryLayout<WNDCLASSEXW>.size)
            wc.lpfnWndProc = popupProc
            wc.hInstance = hInstance
            wc.hCursor = LoadCursorW(nil, UnsafePointer<WCHAR>(bitPattern: 32512))
            wc.lpszClassName = p.baseAddress
            return RegisterClassExW(&wc) != 0
        }
        popupHwnd = cls.withUnsafeBufferPointer { p in
            CreateWindowExW(DWORD(WS_EX_TOOLWINDOW) | DWORD(WS_EX_TOPMOST),
                            p.baseAddress, p.baseAddress, DWORD(WS_POPUP),
                            0, 0, popupWidth, popupHeight, nil, nil, hInstance, nil)
        }
        // Round the whole popover's corners (Windows 11 DWM). No-op on Windows 10.
        if let popupHwnd {
            var pref: Int32 = 2   // DWMWCP_ROUND
            _ = withUnsafePointer(to: &pref) {
                DwmSetWindowAttribute(popupHwnd, DWORD(33), $0, DWORD(MemoryLayout<Int32>.size))   // DWMWA_WINDOW_CORNER_PREFERENCE
            }
        }
    }

    private static func togglePopup() {
        guard let popupHwnd else { return }
        if IsWindowVisible(popupHwnd) { _ = ShowWindow(popupHwnd, SW_HIDE); return }
        var wa = RECT()
        _ = SystemParametersInfoW(UINT(SPI_GETWORKAREA), 0, &wa, 0)
        popupView = 0   // always open on the home view
        let h = effectivePopupHeight()
        let x = stayVisible ? 40 : wa.right - popupWidth - 8
        let y = stayVisible ? 40 : wa.bottom - h - 8
        _ = SetWindowPos(popupHwnd, HWND(bitPattern: -1), x, y, popupWidth, h, UINT(SWP_SHOWWINDOW))
        SetForegroundWindow(popupHwnd)
        checkForUpdate(minInterval: 0, toast: false)   // opening the popover always re-checks (no toast)
        scheduleRefresh()
        InvalidateRect(popupHwnd, nil, true)
    }

    private static func paintPopup(_ hWnd: HWND) {
        var ps = PAINTSTRUCT()
        let hdc = BeginPaint(hWnd, &ps)
        defer { EndPaint(hWnd, &ps) }
        var rc = RECT(); GetClientRect(hWnd, &rc)
        let bg = CreateSolidBrush(rgb(28, 28, 32))
        FillRect(hdc, &rc, bg); DeleteObject(bg)
        SetBkMode(hdc, 1)   // TRANSPARENT
        buttonHits.removeAll(keepingCapacity: true)
        let disp = lock.withLock { currentDisplay }
        uiLang = disp.languageCode

        // While an in-place update runs, cover everything with a loading overlay (no interactions).
        if lock.withLock({ updating }) { drawUpdateOverlay(hdc, rc); return }

        // Update banner above the tabs (macOS parity). Drawn in device coords; then the tabs + view
        // are shifted down by its height via the viewport origin so no hardcoded y needs to change.
        var offsetY: Int32 = 0
        if bannerVisible(), let upd = lock.withLock({ availableUpdate }) {
            offsetY = drawUpdateBanner(hdc, upd)   // appends the Get(30)/Later(31) hits in device coords
        }
        let bannerHits = buttonHits.count
        if offsetY > 0 { SetViewportOrgEx(hdc, 0, offsetY, nil) }

        drawTabs(hdc)
        switch popupView {
        case 1: paintShop(hdc, disp)
        case 2: paintBag(hdc, disp)
        case 3: paintDex(hdc, disp)
        case 4: paintSettings(hdc, disp)
        default: paintHome(hdc, disp, lock.withLock { currentUsage })
        }

        // Tabs/content were drawn in logical space; convert their hit rects to device coords so the
        // click test (raw client coords) matches what the user sees under the banner.
        if offsetY > 0 {
            SetViewportOrgEx(hdc, 0, 0, nil)
            var i = bannerHits
            while i < buttonHits.count {
                buttonHits[i].rect.top += offsetY; buttonHits[i].rect.bottom += offsetY
                i += 1
            }
        }
    }

    /// True when a newer release is known — the update banner is independent of the notification
    /// toggles (an available update should always be surfaced).
    private static func bannerVisible() -> Bool { lock.withLock { availableUpdate } != nil }

    /// Popup window height, grown by the banner strip while an update is pending.
    private static func effectivePopupHeight() -> Int32 { popupHeight + (bannerVisible() ? bannerHeight : 0) }

    /// Accent banner: "Update X.Y.Z" + Get/Later buttons. Returns its height (the content offset).
    private static func drawUpdateBanner(_ hdc: HDC?, _ upd: WindowsUpdate.Available) -> Int32 {
        let m: Int32 = 8
        fillRound(hdc, RECT(left: m, top: 6, right: popupWidth - m, bottom: bannerHeight - 4), 10, rgb(40, 62, 96))
        let tf = makeFont(-13, bold: true); let o = SelectObject(hdc, tf)
        SetTextColor(hdc, rgb(220, 235, 255))
        var tr = RECT(left: m + 12, top: 6, right: popupWidth - 150, bottom: bannerHeight - 4)
        drawText(L("새 버전 \(upd.version)", "Update \(upd.version)", "新バージョン \(upd.version)"),
                 in: hdc, rect: &tr, format: UINT(DT_LEFT | DT_VCENTER | DT_SINGLELINE))
        SelectObject(hdc, o); DeleteObject(tf)
        let bf = makeFont(-12, bold: true); let bo = SelectObject(hdc, bf)
        let get = RECT(left: popupWidth - 142, top: 10, right: popupWidth - 66, bottom: bannerHeight - 8)
        drawButton(hdc, get, L("받기", "Get", "取得"), enabled: true, selected: true)
        buttonHits.append((get, 30))
        let later = RECT(left: popupWidth - 60, top: 10, right: popupWidth - m, bottom: bannerHeight - 8)
        drawButton(hdc, later, L("나중에", "Later", "後で"), enabled: true, selected: false)
        buttonHits.append((later, 31))
        SelectObject(hdc, bo); DeleteObject(bf)
        return bannerHeight
    }

    /// Top tab bar — Home | Shop | Bag | Collection | Settings; active tab gets a rounded highlight.
    private static func drawTabs(_ hdc: HDC?) {
        let titles = [L("홈", "Home", "ホーム"), L("상점", "Shop", "ショップ"), L("가방", "Bag", "バッグ"),
                      L("도감", "Dex", "図鑑"), L("설정", "Settings", "設定")]
        let n = Int32(titles.count)
        let tabW = popupWidth / n
        let font = makeFont(-12, bold: true); let old = SelectObject(hdc, font)
        for (i, title) in titles.enumerated() {
            let x = Int32(i) * tabW
            let right = (i == titles.count - 1) ? popupWidth : x + tabW
            let hit = RECT(left: x, top: 6, right: right, bottom: 40)
            if popupView == i { fillRound(hdc, RECT(left: x + 4, top: 8, right: right - 4, bottom: 38), 9, rgb(58, 92, 130)) }
            SetTextColor(hdc, popupView == i ? rgb(240, 248, 255) : rgb(150, 150, 160))
            var tr = hit
            drawText(title, in: hdc, rect: &tr, format: UINT(DT_CENTER | DT_VCENTER | DT_SINGLELINE))
            buttonHits.append((hit, 100 + i))
        }
        SelectObject(hdc, old); DeleteObject(font)
    }

    // MARK: Home tab (macOS-style layout)

    private static func textWidth(_ hdc: HDC?, _ s: String) -> Int32 {
        var sz = SIZE()
        let w = Array(s.utf16)
        _ = w.withUnsafeBufferPointer { GetTextExtentPoint32W(hdc, $0.baseAddress, Int32($0.count), &sz) }
        return sz.cx
    }

    private static func divider(_ hdc: HDC?, _ y: Int32) {
        var r = RECT(left: 16, top: y, right: popupWidth - 16, bottom: y + 1)
        let b = CreateSolidBrush(rgb(52, 52, 60)); FillRect(hdc, &r, b); DeleteObject(b)
    }

    /// Rounded progress bar: grey track + accent fill (`frac` 0…1).
    private static func drawProgress(_ hdc: HDC?, _ r: RECT, _ frac: Double, _ fill: COLORREF) {
        let rad = (r.bottom - r.top) / 2
        fillRound(hdc, r, rad, rgb(56, 56, 64))
        let w = Int32(Double(r.right - r.left) * max(0, min(1, frac)))
        if w > 3 { fillRound(hdc, RECT(left: r.left, top: r.top, right: r.left + w, bottom: r.bottom), rad, fill) }
    }

    /// Rounded pill with text; returns its right edge x.
    private static func drawPill(_ hdc: HDC?, x: Int32, y: Int32, _ text: String,
                                 fill: COLORREF, textColor: COLORREF, small: Bool = false) -> Int32 {
        let tw = textWidth(hdc, text)
        let pad: Int32 = small ? 8 : 11
        let rect = RECT(left: x, top: y, right: x + tw + pad * 2, bottom: y + (small ? 18 : 26))
        fillRound(hdc, rect, (rect.bottom - rect.top) / 2, fill)
        SetTextColor(hdc, textColor)
        var r = rect
        drawText(text, in: hdc, rect: &r, format: UINT(DT_CENTER | DT_VCENTER | DT_SINGLELINE))
        return rect.right
    }

    private static func rarityBadgeColor(_ r: String) -> COLORREF {
        switch r {
        case "legendary": return rgb(196, 148, 40)
        case "rare": return rgb(46, 108, 200)
        case "uncommon": return rgb(46, 150, 92)
        default: return rgb(90, 90, 102)
        }
    }

    private static func homeToNext(_ d: CompanionDisplay) -> String {
        let n = TokenFormatter.compact(d.isEgg ? d.eggTokensToHatch : d.tokensToNext)
        if d.isEgg { return L("부화까지 \(n)", "\(n) to hatch", "孵化まで\(n)") }
        if d.isFinalStage { return L("졸업까지 \(n)", "\(n) to graduation", "卒業まで\(n)") }
        return L("진화까지 \(n)", "\(n) to evolve", "進化まで\(n)")
    }

    private static func limitRow(_ hdc: HDC?, y: Int32, _ label: String, _ pct: Int?) {
        let lf = makeFont(-15, bold: true); let o = SelectObject(hdc, lf)
        SetTextColor(hdc, rgb(230, 230, 238))
        var lr = RECT(left: 20, top: y, right: 250, bottom: y + 22)
        drawText(label, in: hdc, rect: &lr, format: UINT(DT_LEFT | DT_SINGLELINE))
        let p = pct ?? 0
        let color = p >= 90 ? rgb(232, 96, 96) : (p >= 70 ? rgb(232, 184, 72) : rgb(96, 200, 120))
        SetTextColor(hdc, pct == nil ? rgb(120, 120, 132) : color)
        var pr = RECT(left: popupWidth - 96, top: y, right: popupWidth - 16, bottom: y + 22)
        drawText(pct == nil ? "—" : "\(p)%", in: hdc, rect: &pr, format: UINT(DT_RIGHT | DT_SINGLELINE))
        SelectObject(hdc, o); DeleteObject(lf)
        drawProgress(hdc, RECT(left: 20, top: y + 26, right: popupWidth - 16, bottom: y + 34), Double(p) / 100.0, color)
    }

    private static func paintHome(_ hdc: HDC?, _ disp: CompanionDisplay, _ u: UsageSnapshot) {
        // --- Companion card ---
        fillRound(hdc, RECT(left: 16, top: 50, right: 116, bottom: 150), 12, rgb(20, 20, 24))
        if let icon = displayedIcon() { DrawIconEx(hdc, 22, 56, icon, 88, 88, 0, nil, UINT(DI_NORMAL)) }

        let nameFont = makeFont(-19, bold: true); var o = SelectObject(hdc, nameFont)
        SetTextColor(hdc, rgb(242, 242, 248))
        var nameRect = RECT(left: 128, top: 52, right: popupWidth - 70, bottom: 78)
        drawText(disp.displayName, in: hdc, rect: &nameRect, format: UINT(DT_LEFT | DT_SINGLELINE | DT_END_ELLIPSIS))
        let nw = textWidth(hdc, disp.displayName)
        SelectObject(hdc, o); DeleteObject(nameFont)
        if !disp.isEgg, let rar = disp.rarityText {
            let bf = makeFont(-11, bold: true); let bo = SelectObject(hdc, bf)
            _ = drawPill(hdc, x: min(128 + nw + 8, popupWidth - 74), y: 56,
                         rar.uppercased(), fill: rarityBadgeColor(rar), textColor: rgb(255, 255, 255), small: true)
            SelectObject(hdc, bo); DeleteObject(bf)
        }

        SetTextColor(hdc, rgb(172, 172, 184))
        let subFont = makeFont(-13, bold: false); o = SelectObject(hdc, subFont)
        var subRect = RECT(left: 128, top: 82, right: popupWidth - 16, bottom: 100)
        // Stage · nature (성격) — the individual identity fixed at hatch, re-rollable with a Mint.
        let stageLine: String
        if disp.isEgg {
            stageLine = L("부화 중", "Incubating", "孵化中")
        } else if disp.natureText.isEmpty {
            stageLine = disp.stageText.isEmpty ? " " : disp.stageText
        } else {
            stageLine = disp.stageText.isEmpty ? disp.natureText : "\(disp.stageText) · \(disp.natureText)"
        }
        drawText(stageLine, in: hdc, rect: &subRect, format: UINT(DT_LEFT | DT_SINGLELINE))
        SelectObject(hdc, o); DeleteObject(subFont)

        drawProgress(hdc, RECT(left: 128, top: 106, right: popupWidth - 16, bottom: 114), disp.progress, rgb(92, 152, 232))
        SetTextColor(hdc, rgb(150, 150, 162))
        let toFont = makeFont(-12, bold: false); o = SelectObject(hdc, toFont)
        var toRect = RECT(left: 128, top: 118, right: popupWidth - 16, bottom: 136)
        drawText(homeToNext(disp), in: hdc, rect: &toRect, format: UINT(DT_LEFT | DT_SINGLELINE))
        SelectObject(hdc, o); DeleteObject(toFont)

        SetTextColor(hdc, rgb(212, 212, 220))
        let stFont = makeFont(-13, bold: false); o = SelectObject(hdc, stFont)
        var stRect = RECT(left: 128, top: 138, right: popupWidth - 16, bottom: 156)
        drawText(u.todayTokens > 0 ? L("오늘도 열일 중!", "Today's work is piling up.", "今日も作業がたまってます。")
                                   : L("휴식 중 — 코딩하면 성장해요.", "Resting — start coding.", "休憩中 — コーディングで成長。"),
                 in: hdc, rect: &stRect, format: UINT(DT_LEFT | DT_SINGLELINE))
        SelectObject(hdc, o); DeleteObject(stFont)

        // --- Evolution line (thumbnails under the card; current stage marked with a dot) ---
        let evoH: Int32 = (disp.isEgg || disp.lineNodes.isEmpty) ? 0 : 48
        if evoH > 0 { drawEvoLine(hdc, top: 158, disp) }

        divider(hdc, 168 + evoH)

        // --- Today's tokens ---
        SetTextColor(hdc, rgb(150, 150, 162))
        let lblFont = makeFont(-13, bold: false); o = SelectObject(hdc, lblFont)
        var r1 = RECT(left: 20, top: 176 + evoH, right: 260, bottom: 196 + evoH); drawText(L("오늘 토큰", "Today's tokens", "今日のトークン"), in: hdc, rect: &r1, format: UINT(DT_LEFT | DT_SINGLELINE))
        SelectObject(hdc, o); DeleteObject(lblFont)

        let bigFont = makeFont(-34, bold: true); o = SelectObject(hdc, bigFont)
        SetTextColor(hdc, rgb(246, 246, 250))
        var bigRect = RECT(left: 18, top: 196 + evoH, right: 270, bottom: 242 + evoH); drawText(TokenFormatter.compact(u.todayTokens), in: hdc, rect: &bigRect, format: UINT(DT_LEFT | DT_SINGLELINE))
        SelectObject(hdc, o); DeleteObject(bigFont)

        let costFont = makeFont(-17, bold: true); o = SelectObject(hdc, costFont)
        SetTextColor(hdc, rgb(205, 205, 214))
        var costRect = RECT(left: popupWidth - 130, top: 208 + evoH, right: popupWidth - 16, bottom: 234 + evoH); drawText(TokenFormatter.cost(u.todayCost), in: hdc, rect: &costRect, format: UINT(DT_RIGHT | DT_SINGLELINE))
        SelectObject(hdc, o); DeleteObject(costFont)

        // Week / month — labels + costs secondary, the token values bold white (segmented draw).
        let wmY: Int32 = 246 + evoH
        let wk = L("이번 주", "This week", "今週"), mo = L("이번 달", "This month", "今月")
        var wmX: Int32 = 20
        func wmSeg(_ s: String, bold: Bool, _ color: COLORREF) {
            let f = makeFont(-12, bold: bold); let so = SelectObject(hdc, f)
            SetTextColor(hdc, color)
            var rr = RECT(left: wmX, top: wmY, right: popupWidth - 8, bottom: wmY + 18)
            drawText(s, in: hdc, rect: &rr, format: UINT(DT_LEFT | DT_SINGLELINE))
            wmX += textWidth(hdc, s)
            SelectObject(hdc, so); DeleteObject(f)
        }
        let dim = rgb(150, 150, 162), strong = rgb(236, 236, 244)
        wmSeg("\(wk) ", bold: false, dim)
        wmSeg(TokenFormatter.compact(u.weekTokens), bold: true, strong)
        wmSeg(" \(TokenFormatter.cost(u.weekCost))     ", bold: false, dim)
        wmSeg("\(mo) ", bold: false, dim)
        wmSeg(TokenFormatter.compact(u.monthTokens), bold: true, strong)
        wmSeg(" \(TokenFormatter.cost(u.monthCost))", bold: false, dim)

        // --- Provider tabs — only providers used this month; click to switch the breakdown/limits ---
        var provs: [(idx: Int, label: String)] = []
        if u.claudeUsed { provs.append((0, "Claude Code")) }
        if u.codexUsed { provs.append((1, "Codex")) }
        if u.geminiUsed { provs.append((2, "Gemini")) }
        if u.opencodeUsed { provs.append((3, "OpenCode")) }
        if u.hermesUsed { provs.append((4, "Hermes")) }
        guard !provs.isEmpty else { return }
        var sel = selectedHomeProvider
        if !provs.contains(where: { $0.idx == sel }) { sel = provs[0].idx }
        let pillFont = makeFont(-12, bold: true); o = SelectObject(hdc, pillFont)
        let pillY: Int32 = 274 + evoH
        var px: Int32 = 20
        for prov in provs {
            let on = prov.idx == sel
            let right = drawPill(hdc, x: px, y: pillY, prov.label,
                                 fill: on ? rgb(40, 72, 112) : rgb(44, 44, 52),
                                 textColor: on ? rgb(125, 195, 255) : rgb(170, 170, 182))
            buttonHits.append((RECT(left: px, top: pillY, right: right, bottom: pillY + 26), 40 + prov.idx))
            px = right + 8
        }
        SelectObject(hdc, o); DeleteObject(pillFont)

        // --- Selected provider's breakdown ---
        let provLabel: String, provToday: Int, provCost: Double
        switch sel {
        case 1: (provLabel, provToday, provCost) = ("Codex", u.codexToday, u.codexCost)
        case 2: (provLabel, provToday, provCost) = ("Gemini", u.geminiToday, u.geminiCost)
        case 3: (provLabel, provToday, provCost) = ("OpenCode", u.opencodeToday, u.opencodeCost)
        case 4: (provLabel, provToday, provCost) = ("Hermes Agent", u.hermesToday, u.hermesCost)
        default: (provLabel, provToday, provCost) = ("Claude Code", u.claudeToday, u.claudeCost)
        }
        let cbFont = makeFont(-14, bold: true); o = SelectObject(hdc, cbFont)
        SetTextColor(hdc, rgb(236, 236, 244))
        var cbRect = RECT(left: 20, top: 312 + evoH, right: popupWidth - 16, bottom: 334 + evoH)
        drawText("\(provLabel)   \(TokenFormatter.compact(provToday))   \(TokenFormatter.cost(provCost))", in: hdc, rect: &cbRect, format: UINT(DT_LEFT | DT_SINGLELINE))
        SelectObject(hdc, o); DeleteObject(cbFont)

        // Token-type breakdown + official limits exist for Claude only (Codex limits absent on Windows,
        // Gemini has no limits API) — mirrors macOS `selectedProviderHasLimits`.
        if sel == 0 {
            let brFont = makeFont(-12, bold: false); o = SelectObject(hdc, brFont)
            SetTextColor(hdc, rgb(140, 140, 152))
            var brRect = RECT(left: 20, top: 336 + evoH, right: popupWidth - 16, bottom: 354 + evoH)
            let inL = L("입력", "in", "入力"), outL = L("출력", "out", "出力")
            drawText("\(inL) \(TokenFormatter.compact(u.claudeIn))   \(outL) \(TokenFormatter.compact(u.claudeOut))   cache w \(TokenFormatter.compact(u.claudeCacheW))   cache r \(TokenFormatter.compact(u.claudeCacheR))", in: hdc, rect: &brRect, format: UINT(DT_LEFT | DT_SINGLELINE))
            SelectObject(hdc, o); DeleteObject(brFont)

            divider(hdc, 364 + evoH)
            SetTextColor(hdc, rgb(150, 150, 162))
            let liFont = makeFont(-13, bold: false); o = SelectObject(hdc, liFont)
            var liRect = RECT(left: 20, top: 372 + evoH, right: popupWidth - 16, bottom: 392 + evoH); drawText(L("공식 한도", "Limits (official)", "公式リミット"), in: hdc, rect: &liRect, format: UINT(DT_LEFT | DT_SINGLELINE))
            SelectObject(hdc, o); DeleteObject(liFont)
            limitRow(hdc, y: 396 + evoH, L("5시간 세션", "5-hour session", "5時間セッション"), u.claude5h)
            limitRow(hdc, y: 440 + evoH, L("주간", "Weekly", "週間"), u.claude7d)
        }
    }

    /// Evolution-line thumbnails (초기→최종) with a "›" between and a dot under the current stage.
    private static func drawEvoLine(_ hdc: HDC?, top: Int32, _ disp: CompanionDisplay) {
        let thumb: Int32 = 40
        var x: Int32 = 20
        for (i, node) in disp.lineNodes.enumerated() {
            if i > 0 {
                let af = makeFont(-18, bold: false); let ao = SelectObject(hdc, af)
                SetTextColor(hdc, rgb(120, 120, 130))
                var ar = RECT(left: x, top: top + 8, right: x + 16, bottom: top + thumb)
                drawText("›", in: hdc, rect: &ar, format: UINT(DT_CENTER | DT_SINGLELINE))
                SelectObject(hdc, ao); DeleteObject(af)
                x += 18
            }
            if let ic = lock.withLock({ evoIcons[node.id] }) {
                DrawIconEx(hdc, x, top, ic, thumb, thumb, 0, nil, UINT(DI_NORMAL))
            }
            if node.kind == "cur" {
                fillRound(hdc, RECT(left: x + thumb / 2 - 3, top: top + thumb + 1, right: x + thumb / 2 + 3, bottom: top + thumb + 7), 3, rgb(92, 152, 232))
            }
            x += thumb + 6
        }
    }

    /// One item card: rounded panel with icon + name (+owned) + description + (price) + action button.
    /// Shared by Shop and Bag; `priceText` empty → Bag layout (no price line).
    private static let cardH: Int32 = 108
    private static func drawItemCard(_ hdc: HDC?, top: Int32, _ e: ShopCardEntry) {
        let left: Int32 = 16, right = popupWidth - 16
        fillRound(hdc, RECT(left: left, top: top, right: right, bottom: top + cardH), 14, rgb(30, 30, 36))
        // Icon: real item sprite → fetched color-emoji image → monochrome glyph (last resort while the
        // image loads / if the fetch failed).
        if let name = e.icon, let ic = lock.withLock({ itemIcons[name] }) {
            DrawIconEx(hdc, left + 16, top + 16, ic, 44, 44, 0, nil, UINT(DI_NORMAL))
        } else if let ic = lock.withLock({ emojiIcons[e.emoji] }) {
            DrawIconEx(hdc, left + 16, top + 16, ic, 44, 44, 0, nil, UINT(DI_NORMAL))
        } else {
            let ef = makeFont(-28, bold: false, face: "Segoe UI Emoji"); let eo = SelectObject(hdc, ef)
            SetTextColor(hdc, rgb(220, 220, 228))
            var er = RECT(left: left + 14, top: top + 14, right: left + 62, bottom: top + 60)
            drawText(e.emoji, in: hdc, rect: &er, format: UINT(DT_CENTER | DT_VCENTER | DT_SINGLELINE))
            SelectObject(hdc, eo); DeleteObject(ef)
        }
        let tx: Int32 = left + 72
        // Name (bold) + optional "보유 ×N" suffix.
        let nameFont = makeFont(-16, bold: true); var o = SelectObject(hdc, nameFont)
        SetTextColor(hdc, rgb(233, 233, 240))
        var nr = RECT(left: tx, top: top + 14, right: right - 16, bottom: top + 38)
        drawText(e.name, in: hdc, rect: &nr, format: UINT(DT_LEFT | DT_SINGLELINE))
        let nameW = textWidth(hdc, e.name)
        SelectObject(hdc, o); DeleteObject(nameFont)
        if !e.ownedText.isEmpty {
            let of = makeFont(-12, bold: true); o = SelectObject(hdc, of)
            SetTextColor(hdc, rgb(150, 150, 162))
            var or = RECT(left: tx + nameW + 8, top: top + 18, right: right - 16, bottom: top + 38)
            drawText(e.ownedText, in: hdc, rect: &or, format: UINT(DT_LEFT | DT_SINGLELINE))
            SelectObject(hdc, o); DeleteObject(of)
        }
        // Description (wraps, ellipsised).
        let df = makeFont(-13, bold: false); o = SelectObject(hdc, df)
        SetTextColor(hdc, rgb(150, 150, 160))
        var dr = RECT(left: tx, top: top + 40, right: right - 16, bottom: top + 74)
        drawText(e.desc, in: hdc, rect: &dr, format: UINT(DT_LEFT | DT_WORDBREAK | DT_END_ELLIPSIS))
        SelectObject(hdc, o); DeleteObject(df)
        // Bottom row: price (left) + Buy/Use button (right).
        if !e.priceText.isEmpty {
            let pf = makeFont(-13, bold: false); o = SelectObject(hdc, pf)
            SetTextColor(hdc, rgb(140, 140, 150))
            var pr = RECT(left: left + 20, top: top + cardH - 30, right: right - 110, bottom: top + cardH - 8)
            drawText(e.priceText, in: hdc, rect: &pr, format: UINT(DT_LEFT | DT_SINGLELINE))
            SelectObject(hdc, o); DeleteObject(pf)
        }
        let btnFont = makeFont(-13, bold: true); o = SelectObject(hdc, btnFont)
        let brect = RECT(left: right - 94, top: top + cardH - 40, right: right - 16, bottom: top + cardH - 8)
        drawButton(hdc, brect, e.button, enabled: e.enabled)
        if e.enabled { buttonHits.append((brect, e.action)) }
        SelectObject(hdc, o); DeleteObject(btnFont)
    }

    private static func paintBag(_ hdc: HDC?, _ disp: CompanionDisplay) {
        sectionHeader(hdc, L("가방", "Bag", "バッグ"))
        var top = contentTop + 34
        for e in disp.bagEntries { drawItemCard(hdc, top: top, e); top += cardH + 10 }
        if disp.ownsCharm { footNote(hdc, L("빛나는 부적 보유 중 — 부화마다 이로치 확률 상승.", "Shiny Charm owned — better shiny odds on every hatch.", "ひかるおまもり所持 — 色違い確率アップ。")) }
        else { footNote(hdc, L("5시간·주간 한도를 채우면 이상한 사탕을 받아요.", "Earn Strange Candy by filling 5-hour / weekly limits.", "5時間・週間リミットを埋めるとアメ獲得。")) }
    }

    private static func paintShop(_ hdc: HDC?, _ disp: CompanionDisplay) {
        // Header card: spendable-tokens label + big wallet number + hint (mirrors the macOS Shop header).
        let left: Int32 = 16, right = popupWidth - 16
        let hcTop = contentTop + 4, hcH: Int32 = 92
        fillRound(hdc, RECT(left: left, top: hcTop, right: right, bottom: hcTop + hcH), 14, rgb(30, 30, 36))
        let lf = makeFont(-13, bold: false); var o = SelectObject(hdc, lf)
        SetTextColor(hdc, rgb(150, 150, 160))
        var lr = RECT(left: left + 16, top: hcTop + 12, right: right - 16, bottom: hcTop + 32)
        drawText(disp.spendableLabel, in: hdc, rect: &lr, format: UINT(DT_LEFT | DT_SINGLELINE))
        SelectObject(hdc, o); DeleteObject(lf)
        let wf = makeFont(-30, bold: true); o = SelectObject(hdc, wf)
        SetTextColor(hdc, rgb(240, 240, 248))
        var wr = RECT(left: left + 16, top: hcTop + 30, right: right - 16, bottom: hcTop + 66)
        drawText(TokenFormatter.compact(disp.wallet), in: hdc, rect: &wr, format: UINT(DT_LEFT | DT_SINGLELINE))
        SelectObject(hdc, o); DeleteObject(wf)
        let hf = makeFont(-12, bold: false); o = SelectObject(hdc, hf)
        SetTextColor(hdc, rgb(140, 140, 150))
        var hr = RECT(left: left + 16, top: hcTop + 68, right: right - 16, bottom: hcTop + 88)
        drawText(disp.shopHint, in: hdc, rect: &hr, format: UINT(DT_LEFT | DT_SINGLELINE))
        SelectObject(hdc, o); DeleteObject(hf)
        // Item cards.
        var top = hcTop + hcH + 10
        for e in disp.shopEntries { drawItemCard(hdc, top: top, e); top += cardH + 10 }
    }

    private static func sectionHeader(_ hdc: HDC?, _ text: String) {
        SetTextColor(hdc, rgb(130, 205, 255))
        let f = makeFont(-16, bold: true); let o = SelectObject(hdc, f)
        var r = RECT(left: 22, top: contentTop + 2, right: popupWidth - 12, bottom: contentTop + 26)
        drawText(text, in: hdc, rect: &r, format: UINT(DT_LEFT | DT_SINGLELINE))
        SelectObject(hdc, o); DeleteObject(f)
    }

    private static func footNote(_ hdc: HDC?, _ text: String) {
        SetTextColor(hdc, rgb(140, 140, 150))
        let f = makeFont(-12, bold: false); let o = SelectObject(hdc, f)
        var r = RECT(left: 24, top: popupHeight - 60, right: popupWidth - 24, bottom: popupHeight - 16)
        drawText(text, in: hdc, rect: &r, format: UINT(DT_LEFT | DT_WORDBREAK))
        SelectObject(hdc, o); DeleteObject(f)
    }

    private static func paintDex(_ hdc: HDC?, _ disp: CompanionDisplay) {
        sectionHeader(hdc, "\(L("도감", "Collection", "図鑑")) (\(disp.dex.count))")

        if disp.dex.isEmpty {
            SetTextColor(hdc, rgb(150, 150, 158))
            let f = makeFont(-14, bold: false); let o = SelectObject(hdc, f)
            var r = RECT(left: 24, top: 210, right: popupWidth - 24, bottom: 300)
            drawText(L("아직 잡은 포켓몬이 없어요.\n최종 진화까지 키우면\n도감에 등록돼요.",
                       "No Pokemon caught yet.\nRaise your companion to its final form\nto add it to the collection.",
                       "まだ捕まえたポケモンがいません。\n最終進化まで育てると\n図鑑に登録されます。"),
                     in: hdc, rect: &r, format: UINT(DT_CENTER | DT_WORDBREAK))
            SelectObject(hdc, o); DeleteObject(f)
            return
        }

        // Grid: 4 cols of 44px sprite + rarity-coloured name, mouse-wheel scrollable. Clipped to the
        // grid area so scrolled rows don't paint over the header.
        let cellW = (popupWidth - 24) / dexCols
        let saved = SaveDC(hdc)
        IntersectClipRect(hdc, 0, dexGridTop - 2, popupWidth, popupHeight)
        let nameFont = makeFont(-11, bold: false); let nOld = SelectObject(hdc, nameFont)
        for (i, item) in disp.dex.enumerated() {
            let col = Int32(i) % dexCols, row = Int32(i) / dexCols
            let cx = 12 + col * cellW
            let cy = dexGridTop + row * dexCellH - dexScroll
            if cy + dexCellH < dexGridTop || cy > popupHeight { continue }   // off-screen
            if let ic = lock.withLock({ dexIcons[item.speciesID] }) {
                DrawIconEx(hdc, cx + (cellW - 44) / 2, cy, ic, 44, 44, 0, nil, UINT(DI_NORMAL))
            }
            SetTextColor(hdc, rarityColor(item.rarity))
            var nr = RECT(left: cx, top: cy + 46, right: cx + cellW, bottom: cy + 64)
            let label = (item.isShiny ? "* " : "") + item.name
            drawText(label, in: hdc, rect: &nr, format: UINT(DT_CENTER | DT_SINGLELINE | DT_END_ELLIPSIS))
        }
        SelectObject(hdc, nOld); DeleteObject(nameFont)
        RestoreDC(hdc, saved)
    }

    /// Max scroll offset for the current dex (rows below the fold).
    private static func dexMaxScroll(_ count: Int) -> Int32 {
        let rows = Int32((count + Int(dexCols) - 1) / Int(dexCols))
        let contentH = rows * dexCellH
        let visibleH = popupHeight - dexGridTop - 8
        return max(0, contentH - visibleH)
    }

    private static let setRowH: Int32 = 42, setOptH: Int32 = 34
    private static func paintSettings(_ hdc: HDC?, _ disp: CompanionDisplay) {
        sectionHeader(hdc, L("설정", "Settings", "設定"))
        let d = UserDefaults.standard
        let top = contentTop + 28
        let saved = SaveDC(hdc)
        IntersectClipRect(hdc, 0, top, popupWidth, popupHeight)   // scrollable region below the header
        let rowH = setRowH, optH = setOptH
        var y = top - settingsScroll

        // ===== General =====
        settingsLabel(hdc, y, L("일반", "General", "一般")); y += 24
        let genH = 8 + rowH * 3 + (openDropdown == 1 ? optH * 3 : 0) + (openDropdown == 2 ? optH * 5 : 0)
        drawCard(hdc, y, genH)
        var ry = y + 4
        let langName = disp.languageCode == "ko" ? "한국어" : (disp.languageCode == "ja" ? "日本語" : "English")
        drawDropdownHeader(hdc, ry, L("언어", "Language", "言語"), value: langName, open: openDropdown == 1, action: 60); ry += rowH
        if openDropdown == 1 {
            for (label, code, act) in [("English", "en", 10), ("한국어", "ko", 11), ("日本語", "ja", 12)] {
                drawOptionRow(hdc, ry, label, selected: disp.languageCode == code, action: act); ry += optH
            }
        }
        let sec = d.object(forKey: "refreshIntervalSec") as? Int ?? 120
        drawDropdownHeader(hdc, ry, L("새로고침 간격", "Refresh interval", "更新間隔"), value: intervalLabel(sec), open: openDropdown == 2, action: 61); ry += rowH
        if openDropdown == 2 {
            for (i, p) in [0, 60, 120, 300, 900].enumerated() {
                drawOptionRow(hdc, ry, intervalLabel(p), selected: sec == p, action: 70 + i); ry += optH
            }
        }
        drawSwitchRow(hdc, ry, L("로그인 시 자동 시작", "Launch at login", "ログイン時に起動"), sub: nil, on: WindowsAutostart.isEnabled(), action: 53)
        y += genH + 12

        // ===== Show in tray tooltip (the Windows analog of the macOS menu-bar display options) =====
        settingsLabel(hdc, y, L("트레이 툴팁에 표시", "Show in tray tooltip", "トレイのツールチップに表示")); y += 24
        drawCard(hdc, y, 8 + rowH * 3)
        ry = y + 4
        drawSwitchRow(hdc, ry, L("오늘 토큰", "Today's tokens", "本日のトークン"), sub: nil, on: d.object(forKey: "tipShowTokens") as? Bool ?? true, action: 55); ry += rowH
        drawSwitchRow(hdc, ry, L("오늘 비용 ($)", "Today's cost ($)", "本日のコスト($)"), sub: nil, on: d.object(forKey: "tipShowCost") as? Bool ?? false, action: 56); ry += rowH
        drawSwitchRow(hdc, ry, L("한도 %", "Limit %", "上限 %"), sub: nil, on: d.object(forKey: "tipShowLimit") as? Bool ?? true, action: 57)
        y += 8 + rowH * 3
        settingsLabel(hdc, y + 4, L("전부 끄면 캐릭터만 보여요", "All off → character only", "全部オフ → キャラのみ")); y += 30

        // ===== Notifications =====
        settingsLabel(hdc, y, L("알림", "Notifications", "通知")); y += 24
        let limitOn = d.object(forKey: "limitAlertsEnabled") as? Bool ?? true
        let notifH = 8 + rowH + 48 + (limitOn ? 68 : 0)
        drawCard(hdc, y, notifH)
        ry = y + 4
        drawSwitchRow(hdc, ry, L("한도 알림", "Limit alerts", "上限アラート"), sub: nil, on: limitOn, action: 54); ry += rowH
        if limitOn {
            drawSlider(hdc, ry + 4, L("경고", "Warning", "警告"), value: d.object(forKey: "warnThreshold") as? Int ?? 80, lo: 50, hi: 95, action: 50); ry += 34
            drawSlider(hdc, ry + 4, L("임박", "Critical", "切迫"), value: d.object(forKey: "critThreshold") as? Int ?? 95, lo: 80, hi: 100, action: 51); ry += 34
        }
        drawSwitchRow(hdc, ry, L("Companion 이벤트", "Companion events", "コンパニオンイベント"),
                      sub: L("부화 · 진화 · 졸업", "Hatch · evolve · graduate", "孵化・進化・卒業"),
                      on: d.object(forKey: "companionNotifications") as? Bool ?? true, action: 13)
        y += notifH + 12

        // ===== Version =====
        settingsLabel(hdc, y, L("버전", "Version", "バージョン")); y += 22
        let upToDate = lock.withLock { availableUpdate } == nil
        let vf = makeFont(-14, bold: false); let vo = SelectObject(hdc, vf)
        SetTextColor(hdc, upToDate ? rgb(150, 150, 160) : rgb(120, 180, 130))
        var vr = RECT(left: 24, top: y, right: popupWidth - 24, bottom: y + 22)
        let vtext = upToDate ? WindowsUpdate.currentVersion
                             : "\(WindowsUpdate.currentVersion) → \(lock.withLock { availableUpdate }?.version ?? "")"
        drawText(vtext, in: hdc, rect: &vr, format: UINT(DT_LEFT | DT_SINGLELINE))
        SelectObject(hdc, vo); DeleteObject(vf)
        y += 28

        RestoreDC(hdc, saved)
        settingsContentH = (y + settingsScroll) - top   // total content height (for scroll clamping)
    }

    /// A small dim section/field label.
    private static func settingsLabel(_ hdc: HDC?, _ y: Int32, _ text: String) {
        let f = makeFont(-13, bold: false); let o = SelectObject(hdc, f)
        SetTextColor(hdc, rgb(150, 150, 162))
        var r = RECT(left: 24, top: y, right: popupWidth - 24, bottom: y + 20)
        drawText(text, in: hdc, rect: &r, format: UINT(DT_LEFT | DT_SINGLELINE))
        SelectObject(hdc, o); DeleteObject(f)
    }

    /// Rounded settings card background.
    private static func drawCard(_ hdc: HDC?, _ top: Int32, _ height: Int32) {
        fillRound(hdc, RECT(left: 16, top: top, right: popupWidth - 16, bottom: top + height), 14, rgb(32, 32, 38))
    }

    /// Row: label (+ optional subtitle) on the left, a macOS-style toggle switch on the right.
    private static func drawSwitchRow(_ hdc: HDC?, _ y: Int32, _ label: String, sub: String?, on: Bool, action: Int) {
        let lf = makeFont(-14, bold: false); var o = SelectObject(hdc, lf)
        SetTextColor(hdc, rgb(214, 214, 222))
        var lr = RECT(left: 28, top: y + 6, right: popupWidth - 84, bottom: y + 30)
        drawText(label, in: hdc, rect: &lr, format: UINT(DT_LEFT | DT_VCENTER | DT_SINGLELINE))
        SelectObject(hdc, o); DeleteObject(lf)
        if let sub {
            let sf = makeFont(-11, bold: false); o = SelectObject(hdc, sf)
            SetTextColor(hdc, rgb(140, 140, 150))
            var sr = RECT(left: 28, top: y + 27, right: popupWidth - 84, bottom: y + 45)
            drawText(sub, in: hdc, rect: &sr, format: UINT(DT_LEFT | DT_SINGLELINE))
            SelectObject(hdc, o); DeleteObject(sf)
        }
        let tw: Int32 = 42, th: Int32 = 24, sx = popupWidth - 28 - tw, sy = y + 6
        fillRound(hdc, RECT(left: sx, top: sy, right: sx + tw, bottom: sy + th), th / 2, on ? rgb(52, 199, 89) : rgb(72, 72, 82))
        let kd: Int32 = 18, kp: Int32 = 3, kx = on ? sx + tw - kd - kp : sx + kp
        fillRound(hdc, RECT(left: kx, top: sy + kp, right: kx + kd, bottom: sy + kp + kd), kd / 2, rgb(248, 248, 250))
        buttonHits.append((RECT(left: 20, top: y, right: popupWidth - 20, bottom: y + (sub == nil ? setRowH : 48)), action))
    }

    /// Row: label on the left, a value chip with a ▾ chevron on the right (click to expand options).
    private static func drawDropdownHeader(_ hdc: HDC?, _ y: Int32, _ label: String, value: String, open: Bool, action: Int) {
        let lf = makeFont(-14, bold: false); var o = SelectObject(hdc, lf)
        SetTextColor(hdc, rgb(214, 214, 222))
        var lr = RECT(left: 28, top: y, right: popupWidth - 128, bottom: y + setRowH)
        drawText(label, in: hdc, rect: &lr, format: UINT(DT_LEFT | DT_VCENTER | DT_SINGLELINE))
        SelectObject(hdc, o); DeleteObject(lf)
        let chip = RECT(left: popupWidth - 124, top: y + 7, right: popupWidth - 28, bottom: y + setRowH - 7)
        fillRound(hdc, chip, 8, rgb(50, 50, 58))
        let vf = makeFont(-13, bold: true); o = SelectObject(hdc, vf)
        SetTextColor(hdc, rgb(220, 224, 232))
        var vr = chip
        drawText("\(value)   \(open ? "▴" : "▾")", in: hdc, rect: &vr, format: UINT(DT_CENTER | DT_VCENTER | DT_SINGLELINE))
        SelectObject(hdc, o); DeleteObject(vf)
        buttonHits.append((chip, action))
    }

    /// An expanded dropdown option row (indented; the selected one is highlighted).
    private static func drawOptionRow(_ hdc: HDC?, _ y: Int32, _ label: String, selected: Bool, action: Int) {
        if selected { fillRound(hdc, RECT(left: 30, top: y + 2, right: popupWidth - 30, bottom: y + setOptH - 2), 7, rgb(48, 82, 120)) }
        let f = makeFont(-14, bold: selected); let o = SelectObject(hdc, f)
        SetTextColor(hdc, selected ? rgb(230, 240, 255) : rgb(200, 200, 210))
        var r = RECT(left: 42, top: y, right: popupWidth - 40, bottom: y + setOptH)
        drawText(label, in: hdc, rect: &r, format: UINT(DT_LEFT | DT_VCENTER | DT_SINGLELINE))
        SelectObject(hdc, o); DeleteObject(f)
        buttonHits.append((RECT(left: 30, top: y, right: popupWidth - 30, bottom: y + setOptH), action))
    }

    /// Owner-drawn slider: label + track + handle + "%". Clicking the track sets the value.
    private static func drawSlider(_ hdc: HDC?, _ y: Int32, _ label: String, value: Int, lo: Int, hi: Int, action: Int) {
        let lf = makeFont(-13, bold: false); var o = SelectObject(hdc, lf)
        SetTextColor(hdc, rgb(190, 190, 200))
        var lr = RECT(left: 24, top: y, right: 96, bottom: y + 24)
        drawText(label, in: hdc, rect: &lr, format: UINT(DT_LEFT | DT_VCENTER | DT_SINGLELINE))
        SelectObject(hdc, o); DeleteObject(lf)
        let trackL: Int32 = 96, trackR = popupWidth - 68, cy = y + 12
        fillRound(hdc, RECT(left: trackL, top: cy - 3, right: trackR, bottom: cy + 3), 3, rgb(52, 52, 60))
        let frac = Double(value - lo) / Double(max(1, hi - lo))
        let hx = trackL + Int32((Double(trackR - trackL) * frac).rounded())
        fillRound(hdc, RECT(left: trackL, top: cy - 3, right: hx, bottom: cy + 3), 3, rgb(70, 130, 190))
        fillRound(hdc, RECT(left: hx - 7, top: cy - 7, right: hx + 7, bottom: cy + 7), 7, rgb(232, 232, 240))
        let pf = makeFont(-13, bold: true); o = SelectObject(hdc, pf)
        SetTextColor(hdc, rgb(200, 200, 210))
        var pr = RECT(left: popupWidth - 62, top: y, right: popupWidth - 24, bottom: y + 24)
        drawText("\(value)%", in: hdc, rect: &pr, format: UINT(DT_RIGHT | DT_VCENTER | DT_SINGLELINE))
        SelectObject(hdc, o); DeleteObject(pf)
        buttonHits.append((RECT(left: trackL, top: y - 4, right: trackR, bottom: y + 28), action))   // click target = track
    }

    private static func intervalLabel(_ sec: Int) -> String {
        switch sec {
        case 0:   return L("수동", "Manual", "手動")
        case 60:  return L("1분", "1 min", "1分")
        case 120: return L("2분", "2 min", "2分")
        case 300: return L("5분", "5 min", "5分")
        case 900: return L("15분", "15 min", "15分")
        default:  return "\(sec)s"
        }
    }

    /// (Re)arm the usage-refresh timer from the configured interval (0 = manual → no timer).
    private static func applyRefreshInterval() {
        guard let sinkHwnd else { return }
        _ = KillTimer(sinkHwnd, timerID)
        let sec = UserDefaults.standard.object(forKey: "refreshIntervalSec") as? Int ?? 120
        if sec > 0 { _ = SetTimer(sinkHwnd, timerID, UINT(sec * 1000), nil) }
    }

    /// Expand/collapse a Settings dropdown (1=language, 2=interval); clicking the open one closes it.
    private static func toggleDropdown(_ which: Int) {
        openDropdown = (openDropdown == which) ? 0 : which
        if let popupHwnd { InvalidateRect(popupHwnd, nil, true) }
    }

    /// Pick a refresh-interval preset (index into [0,60,120,300,900]) and collapse the dropdown.
    private static func selectInterval(_ index: Int) {
        let presets = [0, 60, 120, 300, 900]
        guard presets.indices.contains(index) else { return }
        UserDefaults.standard.set(presets[index], forKey: "refreshIntervalSec")
        openDropdown = 0
        applyRefreshInterval()
        if let popupHwnd { InvalidateRect(popupHwnd, nil, true) }
    }

    /// Toggle a "show in tray tooltip" flag, then rebuild the tooltip on the next refresh.
    private static func toggleTip(_ key: String) {
        let on = UserDefaults.standard.object(forKey: key) as? Bool ?? (key != "tipShowCost")
        UserDefaults.standard.set(!on, forKey: key)
        if let popupHwnd { InvalidateRect(popupHwnd, nil, true) }
        scheduleRefresh()
    }

    private static func toggleLimitAlerts() {
        let on = UserDefaults.standard.object(forKey: "limitAlertsEnabled") as? Bool ?? true
        UserDefaults.standard.set(!on, forKey: "limitAlertsEnabled")
        if let popupHwnd { InvalidateRect(popupHwnd, nil, true) }
    }

    /// Map a click on a threshold slider track to a value snapped to 5, clamped to [lo, hi].
    private static func setThreshold(warn: Bool, x: Int32, rect: RECT) {
        let w = max(1, rect.right - rect.left)
        let frac = max(0.0, min(1.0, Double(x - rect.left) / Double(w)))
        let (lo, hi) = warn ? (50, 95) : (80, 100)
        var v = lo + Int((frac * Double(hi - lo)).rounded())
        v = max(lo, min(hi, (v / 5) * 5))
        UserDefaults.standard.set(v, forKey: warn ? "warnThreshold" : "critThreshold")
        if let popupHwnd { InvalidateRect(popupHwnd, nil, true) }
    }

    private static func rarityColor(_ r: String) -> COLORREF {
        switch r {
        case "legendary": return rgb(255, 200, 80)
        case "rare": return rgb(185, 145, 255)
        case "uncommon": return rgb(120, 220, 160)
        default: return rgb(205, 205, 212)   // common
        }
    }

    /// Fill a rounded rectangle (no visible border — pen matches fill).
    private static func fillRound(_ hdc: HDC?, _ r: RECT, _ radius: Int32, _ color: COLORREF) {
        let brush = CreateSolidBrush(color)
        let pen = CreatePen(PS_SOLID, 1, color)
        let ob = SelectObject(hdc, brush); let op = SelectObject(hdc, pen)
        RoundRect(hdc, r.left, r.top, r.right, r.bottom, radius, radius)
        SelectObject(hdc, op); SelectObject(hdc, ob)
        DeleteObject(pen); DeleteObject(brush)
    }

    /// Draw a rounded pill button. Enabled = accent fill; disabled = dim; selected = bright accent.
    private static func drawButton(_ hdc: HDC?, _ r: RECT, _ label: String, enabled: Bool, selected: Bool = false) {
        let color = selected ? rgb(70, 130, 190) : (enabled ? rgb(48, 84, 120) : rgb(44, 44, 52))
        fillRound(hdc, r, 10, color)
        SetTextColor(hdc, enabled ? rgb(230, 240, 255) : rgb(120, 120, 130))
        var rect = r
        drawText(label, in: hdc, rect: &rect, format: UINT(DT_CENTER | DT_VCENTER | DT_SINGLELINE))
    }

    private static func drawText(_ s: String, in hdc: HDC?, rect: inout RECT, format: UINT) {
        var chars = s.wide
        _ = chars.withUnsafeMutableBufferPointer { DrawTextW(hdc, $0.baseAddress, -1, &rect, format) }
    }

    private static func makeFont(_ height: Int32, bold: Bool, face: String = "Segoe UI") -> HFONT? {
        face.wide.withUnsafeBufferPointer {
            CreateFontW(height, 0, 0, 0, bold ? 700 : 400, 0, 0, 0,
                        DWORD(DEFAULT_CHARSET), 0, 0, 0, 0, $0.baseAddress)
        }
    }

    // MARK: Popover actions (shop / candy / mint / new egg)

    private static func handlePopupClick(x: Int32, y: Int32) {
        for (rect, action) in buttonHits where x >= rect.left && x < rect.right && y >= rect.top && y < rect.bottom {
            switch action {
            case 100...104:   // tab switch (Home/Bag/Shop/Dex/Settings)
                popupView = action - 100
                if popupView == 3 { dexScroll = 0 }
                if popupView == 4 { settingsScroll = 0; openDropdown = 0 }
                if let popupHwnd { InvalidateRect(popupHwnd, nil, true) }
            case 10, 11, 12: openDropdown = 0; setLanguage(action)   // pick language + close dropdown
            case 13: toggleNotifications()
            case 30: applyUpdate()
            case 31: skipUpdate()
            case 40, 41, 42, 43, 44:   // Home provider tab (Claude/Codex/Gemini/OpenCode/Hermes) — switch breakdown/limits
                selectedHomeProvider = action - 40
                if let popupHwnd { InvalidateRect(popupHwnd, nil, true) }
            case 50: setThreshold(warn: true, x: x, rect: rect)    // warning-threshold slider
            case 51: setThreshold(warn: false, x: x, rect: rect)   // critical-threshold slider
            case 53: WindowsAutostart.toggle(); if let popupHwnd { InvalidateRect(popupHwnd, nil, true) }
            case 54: toggleLimitAlerts()
            case 55: toggleTip("tipShowTokens")
            case 56: toggleTip("tipShowCost")
            case 57: toggleTip("tipShowLimit")
            case 60: toggleDropdown(1)   // language dropdown
            case 61: toggleDropdown(2)   // interval dropdown
            case 70...74: selectInterval(action - 70)   // interval preset
            default: doAction(action)
            }
            return
        }
    }

    /// Change the companion language (10=en, 11=ko, 12=ja), persist, and re-render.
    private static func setLanguage(_ action: Int) {
        guard let companion else { return }
        let lang: AppLanguage = action == 11 ? .ko : (action == 12 ? .ja : .en)
        Task {
            await companion.setLanguage(lang)
            let disp = await companion.windowsDisplay
            lock.withLock { currentDisplay = disp }
            if let popupHwnd { InvalidateRect(popupHwnd, nil, true) }
            scheduleRefresh()   // regenerate report/name text in the new language
        }
    }

    private static func toggleNotifications() {
        let on = UserDefaults.standard.object(forKey: "companionNotifications") as? Bool ?? true
        UserDefaults.standard.set(!on, forKey: "companionNotifications")
        resizePopupForBanner()   // banner is gated on notifications → its visibility may change
    }

    /// "Later" — remember this version as skipped (won't resurface) and collapse the banner.
    private static func skipUpdate() {
        let version = lock.withLock { () -> String? in
            let v = availableUpdate?.version; availableUpdate = nil; return v
        }
        if let version { UserDefaults.standard.set(version, forKey: "skippedUpdateVersion") }
        resizePopupForBanner()
    }

    /// Auto-update: download the release installer (via `gh`, which follows the asset redirect), and
    /// hand off to a detached updater script that waits for this app to exit, runs the installer in
    /// place, and relaunches. Falls back to opening the release page (manual download) if any step
    /// fails — e.g. `gh` not installed, no matching asset, or a non-writable install dir.
    private static func applyUpdate() {
        guard let upd = lock.withLock({ availableUpdate }) else { return }
        // Guard against double-clicks; flip on the full-cover overlay immediately for instant feedback.
        let start = lock.withLock { () -> Bool in if updating { return false }; updating = true; updateDots = 0; return true }
        guard start else { return }
        if let popupHwnd { InvalidateRect(popupHwnd, nil, true) }
        Task.detached {
            if !performUpdate(upd) {   // on success the app quits (overlay stays until then)
                lock.withLock { updating = false }
                if let popupHwnd { InvalidateRect(popupHwnd, nil, true) }
                WindowsUpdate.openReleasePage(upd.url)
            }
        }
    }

    /// Full-window "updating…" overlay shown while `applyUpdate` downloads + installs the new version.
    private static func drawUpdateOverlay(_ hdc: HDC?, _ rc: RECT) {
        var r = rc
        let cover = CreateSolidBrush(rgb(16, 16, 20)); FillRect(hdc, &r, cover); DeleteObject(cover)
        let cx = (rc.right - rc.left) / 2, cy = (rc.bottom - rc.top) / 2
        if let icon = displayedIcon() {   // the companion, centered above the text
            DrawIconEx(hdc, cx - 44, cy - 128, icon, 88, 88, 0, nil, UINT(DI_NORMAL))
        }
        let tf = makeFont(-22, bold: true); var o = SelectObject(hdc, tf)
        SetTextColor(hdc, rgb(236, 236, 244))
        let dots = String(repeating: "·", count: lock.withLock { updateDots })
        var tr = RECT(left: 0, top: cy - 18, right: rc.right, bottom: cy + 18)
        drawText(L("업데이트 중", "Updating", "更新中") + " " + dots, in: hdc, rect: &tr, format: UINT(DT_CENTER | DT_VCENTER | DT_SINGLELINE))
        SelectObject(hdc, o); DeleteObject(tf)
        let sf = makeFont(-13, bold: false); o = SelectObject(hdc, sf)
        SetTextColor(hdc, rgb(150, 150, 162))
        var sr = RECT(left: 0, top: cy + 26, right: rc.right, bottom: cy + 50)
        drawText(L("새 버전을 받고 있어요. 잠시만요…", "Downloading the new version…", "新しいバージョンを取得中…"),
                 in: hdc, rect: &sr, format: UINT(DT_CENTER | DT_SINGLELINE))
        SelectObject(hdc, o); DeleteObject(sf)
    }

    private static func performUpdate(_ upd: WindowsUpdate.Available) -> Bool {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("ptb-update-\(upd.version)")
        let dl = base.appendingPathComponent("dl")
        try? fm.removeItem(at: base)
        guard (try? fm.createDirectory(at: dl, withIntermediateDirectories: true)) != nil else { return false }
        // Download the installer asset from the public release (gh follows the asset redirect). If the
        // release carries no matching installer, this fails and `applyUpdate` opens the release page.
        guard runToCompletion("gh release download \(upd.version) --repo \(WindowsUpdate.repo) --pattern \"*Setup*.exe\" --dir \"\(dl.path)\" --clobber"),
              let setup = (try? fm.contentsOfDirectory(at: dl, includingPropertiesForKeys: nil))?
                .first(where: { $0.pathExtension.lowercased() == "exe" }) else { return false }
        // Hand off to a detached script: wait for this app to exit, then run the installer silently — it
        // reinstalls in place and relaunches the app via its [Run] entry. Then quit so the files unlock.
        guard launchUpdater(setup: setup.path, base: base.path) else { return false }
        if let sinkHwnd { _ = PostMessageW(sinkHwnd, UINT(WM_COMMAND), WPARAM(menuQuit), 0) }
        return true
    }

    /// Run a command (CREATE_NO_WINDOW) to completion; true iff it exited 0 within the timeout.
    private static func runToCompletion(_ commandLine: String, timeout: Double = 120) -> Bool {
        let tmp = FileManager.default.temporaryDirectory
        let o = tmp.appendingPathComponent("ptb-up-\(UUID().uuidString).out")
        let e = tmp.appendingPathComponent("ptb-up-\(UUID().uuidString).err")
        defer { try? FileManager.default.removeItem(at: o); try? FileManager.default.removeItem(at: e) }
        guard let p = WindowsProcess(commandLine: commandLine, stdoutPath: o.path, stderrPath: e.path), p.launched else { return false }
        defer { p.cleanup() }
        p.closeStdin()
        guard p.waitFor(timeout) else { p.terminate(); return false }
        return p.exitCode == 0
    }

    /// Write a batch script that waits for this PID to exit, runs the downloaded installer silently
    /// (which reinstalls in place and relaunches the app via its [Run] entry), and cleans up. Launched
    /// detached so it outlives the app.
    private static func launchUpdater(setup: String, base: String) -> Bool {
        let pid = GetCurrentProcessId()
        let tmp = FileManager.default.temporaryDirectory
        let cmdPath = tmp.appendingPathComponent("ptb-apply-\(pid).cmd").path
        let script = """
        @echo off
        :wait
        tasklist /fi "pid eq \(pid)" 2>nul | find "\(pid)" >nul && ( ping -n 2 127.0.0.1 >nul & goto wait )
        "\(setup)" /VERYSILENT /SUPPRESSMSGBOXES /NORESTART
        rmdir /s /q "\(base)" 2>nul
        del "%~f0" >nul 2>&1
        """
        guard (try? script.write(toFile: cmdPath, atomically: true, encoding: .utf8)) != nil else { return false }
        let comspec = ProcessInfo.processInfo.environment["ComSpec"] ?? "C:\\Windows\\System32\\cmd.exe"
        // Detached — must outlive this process, so don't wait/cleanup (our handles close on exit).
        return WindowsProcess(commandLine: "\"\(comspec)\" /c \"\(cmdPath)\"",
                              stdoutPath: tmp.appendingPathComponent("ptb-apply-\(pid).out").path,
                              stderrPath: tmp.appendingPathComponent("ptb-apply-\(pid).err").path)?.launched ?? false
    }

    private static func doAction(_ id: Int) {
        guard let companion else { return }
        Task {
            switch id {
            case 1: _ = await companion.useRareCandy()
            case 2: _ = await companion.useMint()
            case 3: _ = await companion.buyRareCandy()
            case 4: _ = await companion.buy(.shinyCharm)
            case 5: _ = await companion.buyFreshEgg()
            case 20: _ = await companion.buy(.mint)
            default: break
            }
            // Immediate feedback: refresh the shop/wallet snapshot + repaint, then a full refresh.
            let disp = await companion.windowsDisplay
            lock.withLock { currentDisplay = disp }
            if let popupHwnd { InvalidateRect(popupHwnd, nil, true) }
            scheduleRefresh()
        }
    }

    // MARK: Menu

    private static func showMenu() {
        guard let sinkHwnd else { return }
        var pt = POINT(); GetCursorPos(&pt)
        let menu = CreatePopupMenu()
        AppendMenuW(menu, UINT(MF_STRING), UINT_PTR(menuRefresh), "Refresh".wide)
        let startFlags = UINT(MF_STRING) | (WindowsAutostart.isEnabled() ? UINT(MF_CHECKED) : UINT(MF_UNCHECKED))
        AppendMenuW(menu, startFlags, UINT_PTR(menuAutostart), "Start at login".wide)
        AppendMenuW(menu, UINT(MF_SEPARATOR), 0, nil)
        AppendMenuW(menu, UINT(MF_STRING), UINT_PTR(menuQuit), "Quit".wide)
        SetForegroundWindow(sinkHwnd)
        _ = TrackPopupMenu(menu, UINT(TPM_RIGHTBUTTON), pt.x, pt.y, 0, sinkHwnd, nil)
        DestroyMenu(menu)
    }

    // MARK: Window procs

    private static let trayProc: WNDPROC = { hWnd, uMsg, wParam, lParam in
        switch uMsg {
        case WindowsTray.callbackMessage:
            let event = UINT(lParam & 0xFFFF)
            if event == UINT(WM_RBUTTONUP) || event == UINT(WM_CONTEXTMENU) {
                WindowsTray.showMenu()
            } else if event == UINT(WM_LBUTTONUP) {
                WindowsTray.togglePopup()
            }
            return 0
        case WindowsTray.updateMessage:
            WindowsTray.applySnapshot()
            return 0
        case WindowsTray.showMessage:   // a second instance asked us to surface the popover
            WindowsTray.showPopup()
            return 0
        case UINT(WM_COMMAND):
            switch UINT(wParam & 0xFFFF) {
            case WindowsTray.menuRefresh: WindowsTray.scheduleRefresh()
            case WindowsTray.menuAutostart: WindowsAutostart.toggle()
            case WindowsTray.menuQuit: PostQuitMessage(0)
            default: break
            }
            return 0
        case UINT(WM_TIMER):
            if wParam == WindowsTray.animTimerID { WindowsTray.animateTick() }
            else { WindowsTray.scheduleRefresh() }
            return 0
        case UINT(WM_DESTROY):
            PostQuitMessage(0)
            return 0
        default:
            return DefWindowProcW(hWnd, uMsg, wParam, lParam)
        }
    }

    private static let popupProc: WNDPROC = { hWnd, uMsg, wParam, lParam in
        switch uMsg {
        case UINT(WM_PAINT):
            if let hWnd { WindowsTray.paintPopup(hWnd) }
            return 0
        case UINT(WM_LBUTTONDOWN):
            WindowsTray.handlePopupClick(x: Int32(Int16(truncatingIfNeeded: lParam)),
                                         y: Int32(Int16(truncatingIfNeeded: lParam >> 16)))
            return 0
        case UINT(WM_MOUSEWHEEL):
            let delta = Int32(Int16(truncatingIfNeeded: wParam >> 16))   // ±120 per notch
            if WindowsTray.popupView == 3, let h = WindowsTray.popupHwnd {   // dex view
                let count = WindowsTray.lock.withLock { WindowsTray.currentDisplay.dex.count }
                let maxS = WindowsTray.dexMaxScroll(count)
                WindowsTray.dexScroll = min(maxS, max(0, WindowsTray.dexScroll - delta / 120 * 52))
                InvalidateRect(h, nil, true)
            } else if WindowsTray.popupView == 4, let h = WindowsTray.popupHwnd {   // settings
                let visible = WindowsTray.popupHeight - WindowsTray.contentTop - 28
                let maxS = max(0, WindowsTray.settingsContentH - visible)
                WindowsTray.settingsScroll = min(maxS, max(0, WindowsTray.settingsScroll - delta / 120 * 40))
                WindowsTray.openDropdown = 0
                InvalidateRect(h, nil, true)
            }
            return 0
        case UINT(WM_ACTIVATE):
            if (wParam & 0xFFFF) == WA_INACTIVE, !WindowsTray.stayVisible, let h = WindowsTray.popupHwnd {
                _ = ShowWindow(h, SW_HIDE)
            }
            return 0
        case UINT(WM_CLOSE):
            if let h = WindowsTray.popupHwnd { _ = ShowWindow(h, SW_HIDE) }
            return 0
        default:
            return DefWindowProcW(hWnd, uMsg, wParam, lParam)
        }
    }
}

/// Sendable snapshot of the companion's display state — gathered in one CompanionActor hop so the
/// tray's off-actor text/icon builders never touch actor-isolated state directly (avoids races).
struct CompanionDisplay: Sendable {
    var isEgg = true
    var eggStarted = false
    var eggProgress = 0.0
    var eggTokensToHatch = 0
    var displayName = "Token Egg"
    var stageText = ""
    var natureText = ""   // localized Pokémon nature (성격), empty for eggs / no active
    var isFinalStage = false
    var tokensToNext = 0
    var rarityText: String?
    var isShiny = false
    var speciesID: Int?
    // Shop / inventory / dex (for the interactive popover actions).
    var wallet = 0
    var candyCount = 0
    var mintCount = 0
    var dexCount = 0
    var canUseCandy = false
    var canUseMint = false
    var canBuyCandy = false
    var canBuyCharm = false
    var canBuyEgg = false
    var ownsCharm = false
    var candyPrice = 0
    var charmPrice = 0
    var eggPrice = 0
    var mintPrice = 0
    var canBuyMint = false
    var dex: [DexItem] = []
    var lineNodes: [EvoThumb] = []   // evolution line thumbnails for the Home card
    var languageCode = "en"   // ko / en / ja — for the settings highlight
    var progress = 0.0        // stage/graduation progress fraction (0…1) for the home bar
    // Shop / Bag item cards — pre-localized in `windowsDisplay` (reuses the cross-platform `L` strings,
    // so name/description/price/owned text never drift from the macOS app).
    var shopEntries: [ShopCardEntry] = []
    var bagEntries: [ShopCardEntry] = []
    var spendableLabel = "Spendable tokens"
    var shopHint = ""
}

/// One evolution-line node for the Home card thumbnail row. `kind` ∈ done / cur / future.
struct EvoThumb: Sendable {
    var id: Int
    var kind: String
}

/// One Shop/Bag item card (icon + name + description + price + action button), fully localized.
struct ShopCardEntry: Sendable {
    var icon: String?      // sprite name in `itemIcons` (nil → draw the emoji fallback)
    var emoji: String
    var name: String
    var desc: String
    var priceText: String  // "가격 100M" (Shop) or "" (Bag hides price)
    var ownedText: String  // "보유 ×2" or "" when none owned
    var button: String     // "구매" / "사용"
    var enabled: Bool
    var action: Int        // handlePopupClick action id
}

/// Combined usage + limits for the Home tab (computed in refresh from parsed logs).
struct UsageSnapshot: Sendable {
    var todayTokens = 0, weekTokens = 0, monthTokens = 0
    var todayCost = 0.0, weekCost = 0.0, monthCost = 0.0
    var claudeToday = 0; var claudeCost = 0.0
    var claudeIn = 0, claudeOut = 0, claudeCacheW = 0, claudeCacheR = 0
    var claude5h: Int?, claude7d: Int?
    // month usage > 0 → provider pill visibility. OpenCode/Hermes are SQLite-backed (macOS system
    // SQLite3 / vendored CSQLite on Windows) — read only where that module exists.
    var claudeUsed = false, codexUsed = false, geminiUsed = false, opencodeUsed = false, hermesUsed = false
    var codexToday = 0, geminiToday = 0, opencodeToday = 0, hermesToday = 0
    var codexCost = 0.0, geminiCost = 0.0, opencodeCost = 0.0, hermesCost = 0.0
}

/// One caught Pokémon for the Windows dex grid.
struct DexItem: Sendable {
    var speciesID: Int
    var name: String
    var rarity: String
    var isShiny: Bool
}

extension CompanionStore {
    /// Actor-isolated read of every field the tray needs, as one Sendable value.
    var windowsDisplay: CompanionDisplay {
        let loc = l   // cross-platform localized strings (same source as the macOS app → no drift)
        func price(_ tokens: Int) -> String { "\(loc.shopPriceLabel) \(TokenFormatter.compact(tokens))" }
        let candyN = rareCandyCount, mintN = itemCount(.mint)
        // Shop list derived from the shared, price-sorted `CompanionStore.shopEntries` — the single
        // source of truth with the macOS ShopView, so item order/content never drifts. A bought
        // passive item (Shiny Charm) stays at the bottom shown as "owned" (upstream ordering) rather
        // than being hidden. Each entry becomes one render card.
        func shopCard(_ entry: ShopEntry) -> ShopCardEntry {
            switch entry {
            case .item(let kind):
                let owned = itemCount(kind)
                let ownedPassive = kind.isPassive && owned > 0
                let action = kind == .rareCandy ? 3 : (kind == .mint ? 20 : 4)
                return ShopCardEntry(
                    icon: kind.spriteName, emoji: kind.fallbackEmoji,
                    name: loc.itemName(kind), desc: loc.itemDescription(kind),
                    priceText: price(kind.shopPrice ?? 0),
                    ownedText: (!kind.isPassive && owned > 0) ? loc.ownedCount(owned) : "",
                    button: ownedPassive ? loc.ownedAlready : loc.buy,
                    enabled: canBuy(kind), action: action)
            case .freshEgg:
                return ShopCardEntry(
                    icon: "egg", emoji: "🥚", name: loc.freshEggName, desc: loc.freshEggDescription,
                    priceText: price(FreshEgg.price), ownedText: "",
                    button: loc.buy, enabled: canBuyFreshEgg, action: 5)
            }
        }
        let shop: [ShopCardEntry] = shopEntries.map(shopCard)
        let bag: [ShopCardEntry] = [
            ShopCardEntry(icon: "rare-candy", emoji: "🍬", name: loc.itemName(.rareCandy), desc: loc.itemDescription(.rareCandy),
                      priceText: "", ownedText: loc.ownedCount(candyN), button: loc.use, enabled: canUseRareCandy, action: 1),
            ShopCardEntry(icon: nil, emoji: "🌿", name: loc.itemName(.mint), desc: loc.itemDescription(.mint),
                      priceText: "", ownedText: loc.ownedCount(mintN), button: loc.use, enabled: canUseMint, action: 2),
        ]
        return CompanionDisplay(
            isEgg: isEgg, eggStarted: eggStarted, eggProgress: eggProgress, eggTokensToHatch: eggTokensToHatch,
            displayName: displayName, stageText: stageText, natureText: currentNature.map { $0.name(language) } ?? "",
            isFinalStage: isFinalStage, tokensToNext: tokensToNext,
            rarityText: rarity.map { String(describing: $0) }, isShiny: currentIsShiny, speciesID: currentSpeciesID,
            wallet: availableTokens, candyCount: rareCandyCount, mintCount: itemCount(.mint), dexCount: dexEntries.count,
            canUseCandy: canUseRareCandy, canUseMint: canUseMint,
            canBuyCandy: canBuyRareCandy, canBuyCharm: canBuy(.shinyCharm), canBuyEgg: canBuyFreshEgg,
            ownsCharm: ownsShinyCharm,
            candyPrice: ItemKind.rareCandy.shopPrice ?? 0, charmPrice: ItemKind.shinyCharm.shopPrice ?? 0,
            eggPrice: FreshEgg.price, mintPrice: ItemKind.mint.shopPrice ?? 0, canBuyMint: canBuy(.mint),
            dex: dexEntriesSorted.map { e in
                DexItem(speciesID: e.finalID,
                        name: dexStoredChainNames(e)?[e.finalID] ?? "#\(e.finalID)",
                        rarity: String(describing: e.rarity), isShiny: e.isShiny)
            },
            lineNodes: hasActive ? lineNodes.map { EvoThumb(id: $0.id, kind: $0.kind) } : [],
            languageCode: language.rawValue,
            progress: isEgg ? eggProgress : progress,
            shopEntries: shop, bagEntries: bag,
            spendableLabel: loc.spendableTokens, shopHint: loc.shopHint)
    }
}
#endif
