import Foundation

/// 앱 전체 UI 문자열 — 언어별. 단일 소스(AppLanguage)에서 파생한다.
/// 뷰는 `player.l.<key>` 로 접근하며, language 변경 시 @Observable 로 자동 재렌더된다.
/// 포켓몬 이름은 PokéAPI 다국어 데이터(EvoLine.localizedName)에서 별도로 온다.
struct L {
    let lang: AppLanguage
    init(_ lang: AppLanguage) { self.lang = lang }

    private func t(_ ko: String, _ en: String, _ ja: String) -> String {
        switch lang {
        case .ko: return ko
        case .en: return en
        case .ja: return ja
        }
    }

    // MARK: 탭
    var home: String { t("홈", "Home", "ホーム") }
    var box: String { t("박스", "Box", "ボックス") }
    var collection: String { t("도감", "Collection", "コレクション") }
    var shop: String { t("상점", "Shop", "ショップ") }

    // MARK: 상점 탭
    var shopWallet: String { t("재화", "Currency", "所持金") }
    var shopEggDraw: String { t("알 뽑기", "Egg draw", "タマゴ抽選") }
    var shopDrawing: String { t("뽑는 중…", "Drawing…", "抽選中…") }
    var shopDrawButton: String { t("뽑기", "Draw", "引く") }
    var shopDrawFetchFailed: String {
        t("부화 후보를 받지 못했어요. 잠시 뒤 다시 시도해 주세요.",
          "Couldn't fetch hatch candidates. Please try again shortly.",
          "ふ化候補を取得できませんでした。しばらくして再試行してください。")
    }
    var shopDrawUnavailable: String {
        t("지금은 뽑을 수 없어요. 재화와 빈 슬롯을 확인해 주세요.",
          "Can't draw right now. Check your currency and open slots.",
          "今は引けません。所持金と空きスロットを確認してください。")
    }
    func shopFreeSlots(_ free: Int, _ total: Int) -> String {
        t("빈 슬롯 \(free) / \(total)", "Open slots \(free) / \(total)", "空きスロット \(free) / \(total)")
    }
    var shopSlotSection: String { t("부화 슬롯", "Hatch slots", "ふ化スロット") }
    func shopSlotUpgrade(_ from: Int, _ to: Int) -> String {
        t("슬롯 늘리기 (\(from) → \(to))", "Add a slot (\(from) → \(to))", "スロット追加 (\(from) → \(to))")
    }
    var shopSlotsMaxed: String { t("슬롯을 최대까지 늘렸어요", "Slots are maxed out", "スロットは最大まで増やしました") }
    var shopItemSection: String { t("아이템", "Items", "アイテム") }
    var shopItemOwned: String { t("보유 중", "Owned", "所持中") }
    var shopItemOwnedButton: String { t("보유", "Owned", "所持") }

    // MARK: 스타터 픽커 (첫 실행 — 27마리 중 1마리 선택)
    var starterPickerTitle: String { t("함께 시작할 포켓몬을 고르세요", "Choose your starting Pokémon", "一緒に始めるポケモンを選んでください") }
    var starterPickerSubtitle: String {
        t("고른 포켓몬이 첫 파트너가 됩니다. 토큰을 쓸수록 경험치가 쌓여요.",
          "Your pick becomes your first partner. The more tokens you use, the more experience it earns.",
          "選んだポケモンが最初のパートナーになります。トークンを使うほど経験値がたまります。")
    }
    var starterPickFailed: String {
        t("선택이 반영되지 않았어요. 다시 눌러주세요.",
          "That choice didn't go through. Please try again.",
          "選択が反映されませんでした。もう一度お試しください。")
    }
    func generationLabel(_ generation: Int) -> String {
        t("\(generation)세대", "Gen \(generation)", "第\(generation)世代")
    }

    // MARK: 박스 (보유 개체)
    var partnerBadge: String { t("파트너", "Partner", "パートナー") }
    var makePartner: String { t("파트너로", "Make partner", "パートナーにする") }
    var evolve: String { t("진화", "Evolve", "しんか") }
    func evolveTo(_ name: String) -> String { t("\(name) 로 진화", "Evolve to \(name)", "\(name)にしんか") }
    /// 사탕 사용 버튼 — 남은 개수를 라벨에 달아 상점에 다시 안 가도 재고를 알 수 있게.
    /// 이름은 상점 품목(`ShopItem.label`)과 같은 말을 쓴다.
    func useExpCandy(_ remaining: Int) -> String {
        t("경험치 사탕 ×\(remaining)", "EXP Candy ×\(remaining)", "けいけんちアメ ×\(remaining)")
    }
    func useShinyCandy(_ remaining: Int) -> String {
        t("반짝이는 사탕 ×\(remaining)", "Shiny Candy ×\(remaining)", "ひかるアメ ×\(remaining)")
    }
    /// 홈 파트너 카드의 진화 가능 배지 — 실제 진화 실행은 박스에서.
    var evolutionReadyBadge: String { t("진화 가능", "Can evolve", "しんか可能") }
    /// 상세 화면 — 그리드에서 개체를 눌러 들어간다. 사탕·진화·파트너 지정이 모두 여기 있다.
    var backToBox: String { t("박스", "Box", "ボックス") }
    var boxEmpty: String { t("아직 가진 포켓몬이 없어요", "No Pokémon yet", "まだポケモンがいません") }
    func boxCount(_ count: Int) -> String { t("\(count)마리", "\(count)", "\(count)ひき") }
    var detailNature: String { t("성격", "Nature", "せいかく") }
    var detailGrade: String { t("등급", "Grade", "ランク") }
    var detailExp: String { t("경험치", "EXP", "けいけんち") }
    var detailMaxStage: String { t("더 진화하지 않아요", "Fully evolved", "これいじょうしんかしない") }
    var detailPartnerOnlyExp: String {
        t("경험치는 파트너만 쌓여요 — 사탕으로도 올릴 수 있어요",
          "Only your partner earns EXP — candy works too",
          "けいけんちはパートナーのみ — アメでも上げられます")
    }
    var detailNoCandy: String {
        t("가진 사탕이 없어요 (상점)", "No candy yet (Shop)", "アメがありません(ショップ)")
    }
    /// 폼 변경 버튼 — 바뀔 모습 이름과 남은 아이템 개수.
    func changeToForm(_ name: String, remaining: Int) -> String {
        t("\(name) ×\(remaining)", "\(name) ×\(remaining)", "\(name) ×\(remaining)")
    }
    /// 폼이 있는 종인데 아이템이 없을 때 — 어디서 구하는지 알려준다.
    func formNeedsItem(_ item: String) -> String {
        t("\(item)이 있으면 모습을 바꿀 수 있어요 (상점)",
          "\(item) changes its form (Shop)",
          "\(item)があればすがたを変えられます(ショップ)")
    }
    var revertForm: String { t("원래 모습으로", "Revert form", "もとのすがたに") }

    // MARK: 세이브 봉인
    var tamperedBadge: String { t("조작된 세이브", "Edited save", "改変されたセーブ") }
    var tamperedExplanation: String {
        t("세이브 파일을 직접 고친 흔적이 있어요. 스프라이트가 위아래로 뒤집힌 채로 남습니다 — 진행에는 영향이 없어요.",
          "This save was edited by hand. Sprites stay upside down — it doesn't affect progress.",
          "セーブファイルを直接編集した記録があります。スプライトは上下反転のままです — 進行には影響しません。")
    }

    // MARK: 홈 — 부화 슬롯
    var eggSlotsHeader: String { t("부화 중", "Hatching", "ふ化中") }
    var eggHatchingNow: String { t("부화!", "Hatched!", "ふ化!") }
    func eggCountdownDaysHours(_ days: Int, _ hours: Int) -> String {
        t("\(days)일 \(hours)시간", "\(days)d \(hours)h", "\(days)日\(hours)時間")
    }
    func eggCountdownHoursMinutes(_ hours: Int, _ minutes: Int) -> String {
        t("\(hours)시간 \(minutes)분", "\(hours)h \(minutes)m", "\(hours)時間\(minutes)分")
    }
    func eggCountdownMinutesSeconds(_ minutes: Int, _ seconds: Int) -> String {
        t("\(minutes)분 \(seconds)초", "\(minutes)m \(seconds)s", "\(minutes)分\(seconds)秒")
    }
    func eggCountdownSeconds(_ seconds: Int) -> String {
        t("\(seconds)초", "\(seconds)s", "\(seconds)秒")
    }

    // MARK: 헤더 (오늘/주/월)
    var todayTokens: String { t("오늘 사용한 토큰", "Today's tokens", "本日のトークン") }
    var thisWeek: String { t("이번 주", "This week", "今週") }
    var thisMonth: String { t("이번 달", "This month", "今月") }

    // MARK: 한도 섹션
    var limitsOfficial: String { t("한도 (공식)", "Limits (official)", "上限（公式）") }
    var fiveHourSession: String { t("5시간 세션", "5-hour session", "5時間セッション") }
    var weekly: String { t("주간", "Weekly", "週間") }
    var weeklyOpus: String { t("주간 Opus", "Weekly Opus", "週間 Opus") }
    var weeklySonnet: String { t("주간 Sonnet", "Weekly Sonnet", "週間 Sonnet") }
    var claudeCurrentBlock: String { t("Claude 현재 5h 블록", "Claude current 5h block", "Claude 現在の5hブロック") }
    var reset: String { t("리셋", "Reset", "リセット") }
    var limitReached: String { t("한도 도달", "Limit reached", "上限到達") }
    var personalSpendLimit: String { t("개인 사용 한도", "Personal spend limit", "個人利用上限") }
    var staleLimits: String { t("갱신 지연", "Stale", "更新遅延") }
    var refresh: String { t("갱신", "Refresh", "更新") }
    var limitsTapToLoad: String { t("공식 한도 불러오기", "Load official limits", "公式上限を読み込む") }

    /// 프로바이더 상태 페이지 인시던트 지표 → 현지화 라벨(표시 전용).
    func providerStatusLabel(_ indicator: ProviderStatusIndicator) -> String {
        switch indicator {
        case .operational: return t("정상", "Operational", "正常")
        case .minor:       return t("일부 장애", "Minor issues", "一部障害")
        case .major:       return t("장애", "Major outage", "障害")
        case .critical:    return t("심각한 장애", "Critical outage", "重大障害")
        case .maintenance: return t("점검 중", "Maintenance", "メンテナンス")
        case .unknown:     return t("상태 불명", "Status unknown", "状態不明")
        }
    }
    func plan(_ p: String) -> String { t("플랜 \(p)", "Plan \(p)", "プラン \(p)") }
    func forecastReach(_ time: String) -> String {
        t("현재 속도면 \(time) 한도 도달", "At current rate, limit hit at \(time)", "現在のペースで \(time) に上限到達")
    }
    var forecastNoReach: String {
        t("현재 속도로는 리셋 전 한도 도달 없음", "Won't hit limit before reset at current rate", "現在のペースではリセット前に上限到達なし")
    }

    /// Claude oauth/usage 신형 limits[] 엔트리 이름 — kind + 모델 스코프 기반.
    func claudeLimitEntry(kind: String?, model: String?) -> String {
        switch kind {
        case "session": return fiveHourSession
        case "weekly_all": return weekly
        case "weekly_scoped":
            // 모델명이 없으면 레거시 "주간" 행과 이름이 겹치므로 scoped 임을 구분 표기
            guard let model else { return t("주간 (모델별)", "Weekly (scoped)", "週間（モデル別）") }
            return t("주간 \(model)", "Weekly \(model)", "週間 \(model)")
        default:
            let base = kind ?? "limit"
            let name = model.map { " \($0)" } ?? ""
            return base.replacingOccurrences(of: "_", with: " ") + name
        }
    }

    /// Codex 한도 윈도우 이름 (windowDurationMins 기반). 알림·팝오버 공통.
    func codexWindow(_ mins: Int?) -> String {
        switch mins {
        case 300: return fiveHourSession
        case 10_080: return weekly
        case let m? where m >= 60 && m % 60 == 0:
            let h = m / 60
            return t("\(h)시간", "\(h)h", "\(h)時間")
        case let m?: return t("\(m)분", "\(m)m", "\(m)分")
        case nil: return t("한도", "Limit", "上限")
        }
    }

    // MARK: 푸터
    var refreshNow: String { t("지금 새로고침", "Refresh now", "今すぐ更新") }
    var updated: String { t("갱신", "Updated", "更新") }
    var settings: String { t("설정", "Settings", "設定") }
    var back: String { t("뒤로", "Back", "戻る") }
    var generalSectionTitle: String { t("일반", "General", "一般") }
    var menuBarSectionTitle: String { t("메뉴바에 표시", "Show in menu bar", "メニューバーに表示") }
    var advancedSectionTitle: String { t("고급", "Advanced", "詳細") }
    var advancedDisclosureLabel: String { t("고급 설정 · 진단", "Advanced · diagnostics", "詳細設定・診断") }
    var aboutSupportSectionTitle: String { t("정보 & 지원", "About & Support", "情報とサポート") }
    var quit: String { t("종료", "Quit", "終了") }

    // MARK: 설정
    var refreshInterval: String { t("새로고침 간격", "Refresh interval", "更新間隔") }
    var language: String { t("언어", "Language", "言語") }
    var menuBarItems: String { t("메뉴바 표시 항목 (복수 선택)", "Menu bar items (multi-select)", "メニューバー表示項目（複数選択）") }
    var todayTokensShort: String { t("오늘 토큰", "Today's tokens", "本日のトークン") }
    var todayCost: String { t("오늘 비용 ($)", "Today's cost ($)", "本日のコスト ($)") }
    var limitPercent: String { t("한도 %", "Limit %", "上限 %") }
    var allOffHint: String { t("전부 끄면 캐릭터만 표시됩니다", "All off shows only the character", "すべてオフにするとキャラクターのみ表示") }
    // MARK: 플로팅 펫
    var floatingPetSectionTitle: String { t("플로팅 펫", "Floating Pet", "フローティングペット") }
    var floatingPetEnableLabel: String { t("플로팅 펫 표시", "Show floating pet", "フローティングペットを表示") }
    var floatingPetHint: String {
        t("포켓몬이 화면 위에 떠 있어요 — 드래그로 위치를 옮길 수 있어요",
          "Your Pokémon floats over the screen — drag to reposition",
          "ポケモンが画面の上に浮かびます — ドラッグで移動できます")
    }
    var floatingPetSizeLabel: String { t("크기", "Size", "サイズ") }
    /// 지금은 한도 알림만 말풍선으로 뜨지만, 알림 종류가 늘어도 이 라벨은 그대로 쓴다.
    var floatingPetBubbleAlertsLabel: String {
        t("말풍선으로 알림 받기", "Show notifications as bubbles", "通知を吹き出しで表示")
    }
    var antialiasLabel: String {
        t("스프라이트 부드럽게", "Smooth sprites", "スプライトを滑らかに")
    }
    var floatingPetMenuOpen: String { t("토큰 바 열기", "Open Token Bar", "トークンバーを開く") }
    var floatingPetMenuHide: String {
        t("플로팅 펫 끄기", "Turn off floating pet", "フローティングペットをオフ")
    }
    func floatingPetHoverTokensOnly(_ tokens: String) -> String {
        t("오늘 \(tokens) 토큰", "Today: \(tokens) tokens", "今日: \(tokens) トークン")
    }
    func floatingPetHoverWithLimit(_ tokens: String, _ percent: String) -> String {
        t("오늘 \(tokens) 토큰 (한도 \(percent))",
          "Today: \(tokens) tokens (limit \(percent))",
          "今日: \(tokens) トークン（上限 \(percent)）")
    }

    var disableKeychain: String { t("Keychain 접근 끄기", "Disable Keychain access", "Keychainアクセスを無効化") }
    var disableKeychainHint: String { t("켜면 Keychain 접근 허용 팝업이 더 안 뜹니다 — 공식 한도(%)만 숨겨지고 토큰·비용은 그대로", "When on, no more Keychain permission pop-ups — only official limits (%) are hidden; tokens/cost stay", "オンにするとKeychain許可のポップアップが出なくなります — 公式上限(%)のみ非表示、トークン・費用はそのまま") }
    var refreshLimitToken: String { t("한도 토큰 캐시 갱신", "Refresh limit token cache", "上限トークンキャッシュを更新") }
    var onlyOnPress: String { t("누를 때만 Keychain 을 읽어요 — 자동 폴링은 안 읽어 팝업이 안 떠요. 토큰 만료 후 이 버튼으로 한도 갱신", "Reads Keychain only when pressed — auto-polling never does, so no pop-ups. Refresh limits here after the token expires", "押した時のみKeychainを読みます — 自動更新では読まずポップアップも出ません。トークン期限切れ後はこのボタンで上限を更新") }
    var launchAtLogin: String { t("로그인 시 자동 시작", "Launch at login", "ログイン時に自動起動") }
    var bundledOnly: String { t(".app 번들로 설치된 경우에만 사용 가능 (scripts/build-app.sh)", "Available only when installed as an .app bundle (scripts/build-app.sh)", ".appバンドルでインストールした場合のみ利用可能 (scripts/build-app.sh)") }
    var notificationsSection: String { t("알림", "Notifications", "通知") }
    var limitNotificationsLabel: String { t("한도 알림", "Limit alerts", "上限通知") }
    var statusChecksLabel: String { t("프로바이더 상태 확인", "Provider status checks", "プロバイダー状態チェック") }
    var statusChecksHint: String { t("Claude·OpenAI 장애를 팝오버에 표시 (알림 아님)", "Show Claude / OpenAI incidents in the popover (not a notification)", "Claude・OpenAIの障害をポップオーバーに表示（通知ではない）") }
    var warning: String { t("경고", "Warning", "警告") }
    var critical: String { t("임박", "Critical", "切迫") }
    var aggregationNote: String { t("토큰 집계 기준: totalTokens (input + output + cache, 로컬 날짜)", "Token basis: totalTokens (input + output + cache, local date)", "集計基準: totalTokens (input + output + cache, ローカル日付)") }
    var close: String { t("닫기", "Close", "閉じる") }

    // MARK: 문제점 알리기 (설정 → 메일 리포트)
    var reportProblem: String { t("문제점 알리기", "Report a problem", "問題を報告") }
    var showLogFile: String { t("로그 파일 보기", "Show log file", "ログファイルを表示") }
    var reportAttachHint: String {
        t("메일에 로그 파일을 첨부해 주시면 원인 파악에 큰 도움이 돼요.",
          "Attaching the log file to the email helps a lot with diagnosis.",
          "メールにログファイルを添付していただくと原因の特定に役立ちます。")
    }
    func reportMailFallback(_ address: String) -> String {
        t("메일 앱을 열 수 없어요. \(address) 로 직접 보내주세요.",
          "Couldn't open a mail app. Please email \(address) directly.",
          "メールアプリを開けません。\(address) 宛に直接お送りください。")
    }
    func reportMailSubject(_ version: String) -> String {
        t("[PokeDexBar] 문제 리포트 (v\(version))",
          "[PokeDexBar] Problem report (v\(version))",
          "[PokeDexBar] 問題レポート (v\(version))")
    }
    func reportMailBody(version: String, os: String) -> String {
        t("""
        문제 내용:
        (겪으신 문제를 적어주세요 — 언제, 어떤 화면에서, 어떻게 되었는지)


        ---
        앱 버전: v\(version)
        macOS: \(os)
        로그 파일(첨부 권장): ~/Library/Logs/PokeDexBar.log
        """,
        """
        What happened:
        (Describe the problem — when, on which screen, and what you saw)


        ---
        App version: v\(version)
        macOS: \(os)
        Log file (please attach): ~/Library/Logs/PokeDexBar.log
        """,
        """
        問題の内容:
        （いつ・どの画面で・どうなったかをご記入ください）


        ---
        アプリのバージョン: v\(version)
        macOS: \(os)
        ログファイル（添付推奨）: ~/Library/Logs/PokeDexBar.log
        """)
    }

    /// 새로고침 간격 라벨 (초 단위 값 → 표시). 0 = 수동.
    func intervalLabel(_ seconds: TimeInterval) -> String {
        if seconds == 0 { return t("수동", "Manual", "手動") }
        let m = Int(seconds / 60)
        return t("\(m)분", "\(m) min", "\(m)分")
    }

    // MARK: 진화 라인 뷰 (EvoLineView — 박스/도감 재사용 대비)
    var unknownNextEvolution: String { t("알 수 없는 다음 진화", "Unknown next evolution", "次の進化先は不明") }

    // MARK: Claude 한도 토큰 갱신 오류 (친절 안내)
    func limitRefreshHTTPError(_ status: Int) -> String {
        if status == 401 || status == 403 {
            return t(
                "Claude 자격증명이 만료됐거나 권한이 없어요 (\(status)). Claude Code 로그인을 확인하세요. Codex만 쓴다면 무시해도 됩니다 — Codex 한도는 따로 표시돼요.",
                "Claude credential is expired or unauthorized (\(status)). Check that you're signed in to Claude Code. If you only use Codex you can ignore this — Codex limits show separately.",
                "Claude の認証情報が期限切れか権限がありません (\(status))。Claude Code にサインインしているか確認してください。Codex のみ使用する場合は無視できます — Codex の上限は別に表示されます。")
        }
        return t("Claude 한도 조회 실패 (\(status)).", "Failed to fetch Claude limits (\(status)).", "Claude の上限取得に失敗しました (\(status))。")
    }
    var limitRefreshNoCredential: String {
        t("Claude 자격증명을 찾지 못했어요. Claude Code 에 로그인하면 한도가 표시됩니다. Codex만 쓴다면 무시해도 돼요.",
          "No Claude credential found. Sign in to Claude Code to see limits. If you only use Codex you can ignore this.",
          "Claude の認証情報が見つかりません。Claude Code にサインインすると上限が表示されます。Codex のみなら無視して構いません。")
    }
    var limitRefreshGeneric: String {
        t("Claude 한도 조회에 실패했어요. 잠시 후 다시 시도하세요.",
          "Couldn't fetch Claude limits. Please try again shortly.",
          "Claude の上限取得に失敗しました。しばらくして再試行してください。")
    }
    var limitRefreshRateLimited: String {
        t("Claude 한도 조회가 일시 제한됐어요 (429). 잠시 쉬었다가 자동으로 재시도합니다.",
          "Claude limit checks are temporarily rate-limited (429). Backing off and retrying automatically.",
          "Claude の上限取得が一時的に制限されています (429)。少し待って自動的に再試行します。")
    }

    // MARK: Claude 세션 만료(401) 안내
    var claudeAuthExpiredTitle: String {
        t("Claude 세션 만료 — 한도가 갱신 안 돼요",
          "Claude session expired — limits can't refresh",
          "Claude セッション期限切れ — 上限を更新できません")
    }
    var claudeAuthExpiredHint: String {
        t("표시된 값은 만료 전 기준이에요. 다시 시도하거나, Claude Code 를 한 번 실행하면 자동 갱신됩니다.",
          "Values shown are from before expiry. Retry, or run Claude Code once to refresh automatically.",
          "表示値は期限切れ前のものです。再試行するか、Claude Code を一度実行すると自動更新されます。")
    }
    var retry: String { t("다시 시도", "Retry", "再試行") }

    // MARK: 업데이트 알림
    func updateAvailable(_ version: String, current: String) -> String {
        t("🆕 v\(version) 사용 가능 (현재 \(current))",
          "🆕 v\(version) available (you have \(current))",
          "🆕 v\(version) が利用可能（現在 \(current)）")
    }
    var updateButton: String { t("업데이트", "Update", "更新") }
    var updateLater: String { t("나중에", "Later", "後で") }
    var updating: String { t("업데이트 중…", "Updating…", "更新中…") }
    var updateSectionTitle: String { t("업데이트", "Updates", "アップデート") }
    var updateNotificationsLabel: String { t("업데이트 알림", "Update notifications", "アップデート通知") }
    var checkForUpdatesLabel: String { t("업데이트 확인", "Check for updates", "アップデートを確認") }
    var checkNowButton: String { t("지금 확인", "Check now", "今すぐ確認") }
    func updateFound(_ version: String) -> String { t("새 버전 v\(version) 있어요", "Version \(version) is available", "バージョン \(version) が利用可能です") }
    func upToDate(_ version: String) -> String { t("최신 버전이에요 (v\(version))", "You're on the latest (v\(version))", "最新です (v\(version))") }

    // MARK: 알림
    var notifCritical: String { t("한도 임박", "Limit imminent", "上限切迫") }
    var notifWarning: String { t("한도 경고", "Limit warning", "上限警告") }
    func notifBody(_ name: String, _ percent: String) -> String {
        t("\(name) 한도 \(percent) 사용", "\(name) at \(percent)", "\(name) 上限 \(percent) 使用")
    }
    var claudeFiveHour: String { t("Claude 5시간 세션", "Claude 5-hour session", "Claude 5時間セッション") }
    var claudeWeekly: String { t("Claude 주간", "Claude weekly", "Claude 週間") }
    var codexPersonalLimit: String { t("Codex 개인 한도", "Codex personal limit", "Codex 個人上限") }

    // MARK: 부화 알림
    var notifHatchTitle: String { t("알이 부화했어요", "An egg hatched", "タマゴがふ化しました") }
    /// 하나만 깼을 때 — 어떤 종인지 짚어준다.
    func notifHatchSingleBody(_ speciesID: Int, shiny: Bool) -> String {
        let mark = shiny ? "✨ " : ""
        return t("\(mark)#\(speciesID) 를 만났어요", "\(mark)You met #\(speciesID)", "\(mark)#\(speciesID) に出会いました")
    }
    /// 여러 개가 한꺼번에 깼을 때 — 하나로 묶는다(알림 폭탄 방지). 이로치가 섞였으면 개수를 곁들인다.
    func notifHatchMultipleBody(_ count: Int, shinyCount: Int) -> String {
        let ko = shinyCount > 0 ? " (✨ \(shinyCount)마리)" : ""
        let en = shinyCount > 0 ? " (✨ \(shinyCount) shiny)" : ""
        let ja = shinyCount > 0 ? " (✨ \(shinyCount)匹)" : ""
        return t("\(count)마리가 부화했어요\(ko)", "\(count) hatched\(en)", "\(count)匹がふ化しました\(ja)")
    }
}
